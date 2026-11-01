import XCTest
@testable import MDEdit

/// Shell commands run real programs, so these tests run real programs: what a command sees (a clean environment, the
/// folder, stdin), what it cannot leave behind (children, open files, hung pipes) and what comes back (safe text).
final class ShellRunnerTests: XCTestCase {
    var s: Scratch!
    override func setUpWithError() throws { s = try Scratch(["a.md": "x"]) }
    override func tearDown() { s.remove() }

    @discardableResult
    private func run(_ command: String, input: String = "", env: [String: String]? = nil, timeout: TimeInterval = 10, cap: Int = ShellJob.maxOutput, shell: String = "/bin/sh") -> ShellResult {
        let e = env ?? ShellEnvironment.build(path: ShellEnvironment.defaultPath, extra: "", md: [:])
        return ShellJob(ShellRequest(shell: shell, arguments: ["-c", command], directory: s.url, environment: e, input: Data(input.utf8), timeout: timeout, maxOutput: cap)).run()
    }

    // MARK: normal use

    func testACommandsOutputComesBack() {
        let r = run("echo hello")
        XCTAssertEqual(r.stdout, "hello\n"); XCTAssertEqual(r.status, 0); XCTAssertTrue(r.succeeded)
    }

    func testInputGoesToStdinIntact() {
        let text = "héllo\nwörld 😀\n" + String(repeating: "line\n", count: 20_000)
        XCTAssertEqual(run("cat", input: text).stdout, text)
    }

    func testFailureReportsStatusAndErrors() {
        let r = run("echo bad >&2; exit 3")
        XCTAssertEqual(r.status, 3); XCTAssertEqual(r.stderr, "bad\n"); XCTAssertFalse(r.succeeded)
        XCTAssertEqual(r.summary, "Exit status 3")
    }

    func testTheCommandRunsInTheGivenFolder() {
        XCTAssertEqual(run("pwd -P").stdout.trimmingCharacters(in: .whitespacesAndNewlines), s.url.resolvingSymlinksInPath().path)
        run("echo made > made.txt")
        XCTAssertTrue(s.exists("made.txt"))
    }

    func testAShellThatIsMissingIsReportedNotCrashed() {
        let r = run("true", shell: "/nonexistent/sh")
        XCTAssertNotNil(r.startError); XCTAssertFalse(r.succeeded)
    }

    // MARK: environment

    func testOnlyAShortListOfVariablesIsPassedOn() {
        setenv("MDEDIT_TEST_SECRET", "s3cret", 1); defer { unsetenv("MDEDIT_TEST_SECRET") }
        let r = run("env")
        XCTAssertFalse(r.stdout.contains("s3cret")); XCTAssertFalse(r.stdout.contains("MDEDIT_TEST_SECRET"))
        let names = Set(r.stdout.split(separator: "\n").compactMap { $0.split(separator: "=", maxSplits: 1).first.map(String.init) })
        XCTAssertTrue(names.isSubset(of: ["PATH", "HOME", "LANG", "TERM", "TMPDIR", "PWD", "SHLVL", "_", "OLDPWD"]), "unexpected variables: \(names)")
        XCTAssertTrue(r.stdout.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
    }

    func testPathCanBeChangedAndABadOneFallsBack() {
        XCTAssertEqual(ShellEnvironment.build(path: "/opt/x/bin:/usr/bin", extra: "", md: [:])["PATH"], "/opt/x/bin:/usr/bin")
        for bad in ["", "   ", "a\nb", "a\0b", String(repeating: "x", count: 5000)] {
            XCTAssertEqual(ShellEnvironment.build(path: bad, extra: "", md: [:])["PATH"], ShellEnvironment.defaultPath)
        }
    }

    func testExtraVariablesAreParsedAndDangerousOnesAreIgnored() {
        let text = """
        # a comment
        FOO=bar
        export QUOTED="two words"
        SINGLE='it'
        EMPTY=
        1BAD=x
        BAD NAME=x
        MD_FILE_PATH=/etc/passwd
        DYLD_INSERT_LIBRARIES=/tmp/evil.dylib
        LD_PRELOAD=/tmp/evil.so
        BASH_ENV=/tmp/evil
        NOEQUALS
        """
        let e = ShellEnvironment.parse(text)
        XCTAssertEqual(e["FOO"], "bar"); XCTAssertEqual(e["QUOTED"], "two words"); XCTAssertEqual(e["SINGLE"], "it"); XCTAssertEqual(e["EMPTY"], "")
        for k in ["1BAD", "BAD NAME", "MD_FILE_PATH", "DYLD_INSERT_LIBRARIES", "LD_PRELOAD", "BASH_ENV", "NOEQUALS"] { XCTAssertNil(e[k], k) }
        let many = (0..<500).map { "V\($0)=1" }.joined(separator: "\n")
        XCTAssertLessThanOrEqual(ShellEnvironment.parse(many).count, ShellEnvironment.maxExtra)
        XCTAssertTrue(ShellEnvironment.parse("BIG=" + String(repeating: "x", count: 10_000)).isEmpty)
    }

    func testTheNotesOwnVariablesWinOverSettings() {
        let md = ["MD_FILE_PATH": "/real"]
        XCTAssertEqual(ShellEnvironment.build(path: "", extra: "MD_FILE_PATH=/fake", md: md)["MD_FILE_PATH"], "/real")
    }

    func testVariablesDescribeTheNoteAndCaret() {
        let text = "ab\ncd😀e" as NSString
        let v = ShellEnvironment.variables(root: URL(fileURLWithPath: "/r"), file: URL(fileURLWithPath: "/r/n.md"), text: text, caret: text.length, selection: "")
        XCTAssertEqual(v["MD_WORKING_DIR"], "/r"); XCTAssertEqual(v["MD_FILE_PATH"], "/r/n.md")
        XCTAssertEqual(v["MD_FILE_LINE"], "2"); XCTAssertEqual(v["MD_FILE_COLUMN"], "5", "c d 😀 e, then the caret: characters, from 1")
        XCTAssertNil(v["MD_FILE_SELECTION"], "nothing selected, nothing set")
        XCTAssertEqual(ShellEnvironment.position(in: "abc", at: 0).line, 1); XCTAssertEqual(ShellEnvironment.position(in: "abc", at: 0).column, 1)
        XCTAssertEqual(ShellEnvironment.position(in: "a\n", at: 99).line, 2, "a caret past the end is clamped")
    }

    func testALargeSelectionIsNotPutInTheEnvironment() {
        let big = String(repeating: "x", count: ShellEnvironment.maxSelection + 1)
        XCTAssertNil(ShellEnvironment.variables(root: s.url, file: s.url, text: "", caret: 0, selection: big)["MD_FILE_SELECTION"])
        XCTAssertEqual(ShellEnvironment.variables(root: s.url, file: s.url, text: "", caret: 0, selection: "ok")["MD_FILE_SELECTION"], "ok")
        XCTAssertEqual(run("wc -c", input: big).stdout.trimmingCharacters(in: .whitespacesAndNewlines), String(big.utf8.count), "it still reaches stdin")
    }

    func testAHostileFileNameIsOnlyEverData() {
        let evil = "/tmp/a b\"$(touch pwned)`touch pwned2`';touch pwned3.md"
        let env = ShellEnvironment.build(path: "", extra: "", md: ["MD_FILE_PATH": evil, "MD_FILE_SELECTION": "$(touch pwned4) \"; rm -rf /"])
        XCTAssertEqual(run("printf %s \"$MD_FILE_PATH\"", env: env).stdout, evil)
        XCTAssertEqual(run("printf %s \"$MD_FILE_SELECTION\"", env: env).stdout, "$(touch pwned4) \"; rm -rf /")
        for f in ["pwned", "pwned2", "pwned3.md", "pwned4"] { XCTAssertFalse(s.exists(f), f) }
    }

    // MARK: what a command cannot leave behind

    func testATimeoutStopsTheCommand() {
        let r = run("sleep 30", timeout: 1)
        XCTAssertTrue(r.timedOut); XCTAssertFalse(r.succeeded); XCTAssertLessThan(r.duration, 6)
    }

    func testACommandThatIgnoresTheStopSignalIsStillKilled() {
        let r = run("trap '' TERM; sleep 30", timeout: 1)
        XCTAssertTrue(r.timedOut); XCTAssertLessThan(r.duration, 8)
    }

    func testThingsTheCommandStartedDoNotOutliveIt() throws {
        let r = run("sleep 60 & echo $!", timeout: 10)
        let pid = try XCTUnwrap(Int32(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertLessThan(r.duration, 5, "a background child holding the pipe must not hang us")
        let deadline = Date().addingTimeInterval(2)
        while kill(pid, 0) == 0 && Date() < deadline { usleep(50_000) }
        XCTAssertNotEqual(kill(pid, 0), 0, "the background process was left running")
    }

    func testCancelStopsARunningCommand() {
        let job = ShellJob(ShellRequest(arguments: ["-c", "sleep 30"], directory: s.url, environment: ShellEnvironment.build(path: "", extra: "", md: [:])))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { job.cancel() }
        let r = job.run()
        XCTAssertTrue(r.cancelled); XCTAssertFalse(r.succeeded); XCTAssertLessThan(r.duration, 5)
    }

    func testCancelAllKillsEveryRunningCommand() {
        let job = ShellJob(ShellRequest(arguments: ["-c", "sleep 30"], directory: s.url, environment: ShellEnvironment.build(path: "", extra: "", md: [:])))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { ShellJob.cancelAll() }
        let r = job.run()
        XCTAssertTrue(r.cancelled); XCTAssertLessThan(r.duration, 3)
    }

    func testRunawayOutputIsCappedAndStopped() {
        let r = run("yes", cap: 100_000)
        XCTAssertTrue(r.truncated); XCTAssertFalse(r.succeeded)
        XCTAssertLessThanOrEqual(r.stdout.utf8.count, 100_000); XCTAssertLessThan(r.duration, 8)
    }

    func testACommandThatNeverReadsItsInputDoesNotHangUs() {
        let r = run("true", input: String(repeating: "x", count: 10_000_000), timeout: 10)
        XCTAssertTrue(r.succeeded); XCTAssertLessThan(r.duration, 5)
    }

    func testFilesTheAppHasOpenAreNotHandedToTheCommand() {
        let leak = open("/etc/hosts", O_RDONLY)             // deliberately without close-on-exec
        defer { close(leak) }
        let seen = run("ls /dev/fd").stdout.split(separator: "\n").map(String.init)
        XCTAssertFalse(seen.contains(String(leak)), "the command inherited fd \(leak): \(seen)")
        XCTAssertTrue(seen.allSatisfy { (Int($0) ?? 99) <= 4 }, "unexpected files open in the command: \(seen)")
    }

    // MARK: what comes back

    func testOutputIsMadeSafeForANote() {
        func clean(_ s: String) -> String { ShellOutput.clean(Data(s.utf8)) }
        XCTAssertEqual(clean("\u{1B}[31mred\u{1B}[0m plain"), "red plain", "colours")
        XCTAssertEqual(clean("a\u{1B}]0;title\u{07}b"), "ab", "window titles")
        XCTAssertEqual(clean("a\u{1B}]8;;http://evil\u{1B}\\link\u{1B}]8;;\u{1B}\\b"), "alinkb", "hyperlink escapes")
        XCTAssertEqual(clean("a\u{1B}[2J\u{1B}[Hb"), "ab", "clear screen")
        XCTAssertEqual(clean("a\0b\u{07}c\u{08}d"), "abcd", "NUL, bell, backspace")
        XCTAssertEqual(clean("one\r\ntwo\rthree\n"), "one\ntwo\nthree\n", "line endings")
        XCTAssertEqual(clean("tab\there"), "tab\there")
        XCTAssertEqual(clean("safe \u{202E}txet\u{202C} \u{2066}x\u{2069}"), "safe txet x", "text direction tricks")
        XCTAssertEqual(clean("\u{FEFF}start"), "start")
        XCTAssertEqual(clean("émoji 😀 日本語"), "émoji 😀 日本語")
        XCTAssertTrue(ShellOutput.clean(Data([0x61, 0xFF, 0xFE, 0x62])).hasPrefix("a"), "invalid UTF-8 does not crash")
        XCTAssertEqual(clean("a\u{1B}"), "a", "a lone escape at the end")
        XCTAssertEqual(clean("a\u{1B}[" + String(repeating: "1", count: 100_000)), "a", "an unfinished sequence is dropped, quickly")
    }

    func testTerminalEscapesFromARealCommandAreCleaned() {
        XCTAssertEqual(run("printf '\\033[1mbold\\033[0m\\r\\n'").stdout, "bold\n")
    }
}
