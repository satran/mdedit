import XCTest
import AppKit
@testable import MDEdit

/// ⌘R: run a command on the open note and put the result where the person chose. Real folder, real note, real editor
/// in a real window, real programs.
@MainActor
final class ShellCommandTests: XCTestCase {
    var s: Scratch!
    var ws: Workspace!
    var prefs: Preferences!
    var window: NSWindow!
    var tv: EditorTextView!
    private var coordinator: AnyObject?

    override func setUpWithError() throws {
        s = try Scratch(["Note.md": "one\ntwo", "Other.md": "x"])
        ws = makeWorkspace(open: s.url)
        prefs = Preferences(defaults: isolatedDefaults())
        prefs.shellEnabled = true
        ws.select(s.path("Note.md"))
        tv = EditorTextView()
        tv.isRichText = false; tv.allowsUndo = true
        tv.textContainer?.lineFragmentPadding = 0
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scroll.documentView = tv
        tv.isVerticallyResizable = true; tv.autoresizingMask = [.width]; tv.textContainer?.widthTracksTextView = true
        let style = EditorStyle(fontName: "IBM Plex Mono", size: 16, lineWidth: 72)
        tv.style = style
        let c = MarkdownTextEditor(text: .constant(""), style: style).makeCoordinator()
        tv.delegate = c; coordinator = c
        tv.font = tv.baseFont; tv.string = ws.document.text; tv.restyle()
        window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(tv)
        ws.editor.textView = tv
        ws.shellConfirm = { _, _, _ in XCTFail("nobody should have been asked"); return false }
    }

    override func tearDown() {
        tv.delegate = nil; window.close()
        ws = nil; s.remove()
    }

    private func finish(timeout: TimeInterval = 10) {
        let end = Date().addingTimeInterval(timeout)
        while (ws.shellJob != nil) && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func go(_ cmd: String, _ dest: ShellDestination) {
        ws.runShell(.command(cmd), destination: dest, prefs: prefs)
        finish()
    }

    // MARK: where the output goes

    func testInsertPutsTheOutputAtTheCaret() {
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        go("printf X", .insert)
        XCTAssertEqual(tv.string, "oneX\ntwo")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 4, length: 0), "the caret is after what came in")
    }

    func testInsertWithASelectionKeepsTheSelectionAndInsertsAfterIt() {
        tv.setSelectedRange(NSRange(location: 4, length: 3))
        go("printf '<'; cat; printf '>'", .insert)
        XCTAssertEqual(tv.string, "one\ntwo<two>")
    }

    func testReplaceChangesOnlyTheSelection() {
        tv.setSelectedRange(NSRange(location: 4, length: 3))
        go("tr a-z A-Z", .replace)
        XCTAssertEqual(tv.string, "one\nTWO", "the selection went in on stdin and came back")
    }

    func testReplaceWithoutASelectionTakesTheWholeNote() {
        tv.setSelectedRange(NSRange(location: 1, length: 0))
        go("tr a-z A-Z", .replace)
        XCTAssertEqual(tv.string, "ONE\nTWO")
    }

    func testReplaceIsASingleUndoStep() {
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        go("tr a-z A-Z", .replace)
        XCTAssertEqual(tv.string, "ONE\nTWO")
        tv.undoManager?.undo()
        XCTAssertEqual(tv.string, "one\ntwo", "one ⌘Z brings the note back")
    }

    func testInsertIsASingleUndoStep() {
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        go("seq 1 200", .insert)
        tv.undoManager?.undo()
        XCTAssertEqual(tv.string, "one\ntwo")
    }

    func testNewFileIsCreatedNextToTheNoteAndOpened() throws {
        go("echo hi", .newFile)
        XCTAssertEqual(try s.read("Output Note.md"), "hi\n")
        XCTAssertEqual(ws.document.url?.lastPathComponent, "Output Note.md")
        XCTAssertEqual(tv.string, "one\ntwo", "the editor still holds the note it ran on until SwiftUI swaps it")
        XCTAssertEqual(try s.read("Note.md"), "one\ntwo")
    }

    func testNewFileNeverOverwritesAnExistingOne() throws {
        try s.write("Output Note.md", "precious")
        go("echo hi", .newFile)
        XCTAssertEqual(try s.read("Output Note.md"), "precious")
        XCTAssertEqual(try s.read("Output Note 2.md"), "hi\n")
    }

    func testNewFileInAFolderStaysInThatFolder() throws {
        try s.write("Sub/Deep.md", "deep")
        ws.reload(); ws.select(s.path("Sub/Deep.md"))
        tv.string = "deep"
        go("echo hi", .newFile)
        XCTAssertTrue(s.exists("Sub/Output Deep.md"))
        XCTAssertFalse(s.exists("Output Deep.md"))
    }

    func testPanelOnlyShowsTheOutput() {
        go("echo shown; touch side-effect", .panel)
        XCTAssertEqual(tv.string, "one\ntwo")
        XCTAssertEqual(ws.shellLog?.result.stdout, "shown\n")
        XCTAssertTrue(s.exists("side-effect"), "commands that only act on files work")
    }

    // MARK: what the command sees

    func testTheCommandSeesTheNoteAndTheCaret() {
        tv.setSelectedRange(NSRange(location: 5, length: 2))
        go("printf '%s|%s|%s|%s|%s' \"$MD_FILE_LINE\" \"$MD_FILE_COLUMN\" \"$MD_FILE_SELECTION\" \"$(basename \"$MD_FILE_PATH\")\" \"$(basename \"$MD_WORKING_DIR\")\"", .panel)
        XCTAssertEqual(ws.shellLog?.result.stdout, "2|2|wo|Note.md|\(s.url.lastPathComponent)")
    }

    func testTheNoteIsSavedBeforeTheCommandRuns() {
        ws.document.text = "edited, not yet saved"
        tv.string = "edited, not yet saved"
        go("cat \"$MD_FILE_PATH\"", .panel)
        XCTAssertEqual(ws.shellLog?.result.stdout, "edited, not yet saved")
    }

    // MARK: when it goes wrong

    func testAFailureLeavesTheNoteAloneAndShowsTheError() {
        go("echo oops >&2; echo partial; exit 2", .replace)
        XCTAssertEqual(tv.string, "one\ntwo")
        XCTAssertEqual(ws.shellLog?.result.stderr, "oops\n"); XCTAssertEqual(ws.shellLog?.result.status, 2)
        XCTAssertFalse(ws.shellBarVisible)
    }

    func testATimeoutLeavesTheNoteAlone() {
        prefs.shellTimeout = 1
        go("echo late; sleep 20", .replace)
        XCTAssertEqual(tv.string, "one\ntwo")
        XCTAssertEqual(ws.shellLog?.result.timedOut, true)
    }

    func testCancelLeavesTheNoteAlone() {
        ws.runShell(.command("sleep 20"), destination: .replace, prefs: prefs)
        XCTAssertNotNil(ws.shellJob)
        ws.cancelShell()
        finish()
        XCTAssertEqual(tv.string, "one\ntwo"); XCTAssertEqual(ws.shellLog?.result.cancelled, true)
    }

    func testOnlyOneCommandRunsAtATime() {
        ws.runShell(.command("sleep 1; touch first"), destination: .panel, prefs: prefs)
        ws.runShell(.command("touch second"), destination: .panel, prefs: prefs)
        finish()
        XCTAssertTrue(s.exists("first")); XCTAssertFalse(s.exists("second"))
    }

    func testEmptyOutputDoesNotWipeANoteWithoutAsking() {
        var asked = 0
        ws.shellConfirm = { _, _, _ in asked += 1; return false }
        go("true", .replace)
        XCTAssertEqual(asked, 1); XCTAssertEqual(tv.string, "one\ntwo")
        ws.shellConfirm = { _, _, _ in asked += 1; return true }
        go("true", .replace)
        XCTAssertEqual(asked, 2); XCTAssertEqual(tv.string, "")
        tv.undoManager?.undo()
        XCTAssertEqual(tv.string, "one\ntwo", "and it can be undone")
    }

    func testOutputIsNotAppliedToANoteThatChangedMeanwhile() {
        ws.runShell(.command("sleep 0.6; echo LATE"), destination: .insert, prefs: prefs)
        tv.string = "typed meanwhile"
        finish()
        XCTAssertEqual(tv.string, "typed meanwhile")
        XCTAssertEqual(ws.shellLog?.result.stdout, "LATE\n", "nothing is lost: it is in the log")
        XCTAssertNotNil(ws.shellLog?.note)
    }

    func testNothingRunsWhileTheFeatureIsOff() {
        prefs.shellEnabled = false
        ws.runShell(.command("touch ran"), destination: .panel, prefs: prefs)
        finish()
        XCTAssertFalse(s.exists("ran")); XCTAssertNotNil(ws.message)
        ws.message = nil
        ws.openShellBar(prefs: prefs)
        XCTAssertFalse(ws.shellBarVisible); XCTAssertNotNil(ws.message)
    }

    func testAMissingShellIsReported() {
        prefs.shellPath = "/nonexistent/sh"
        ws.runShell(.command("touch ran"), destination: .panel, prefs: prefs)
        XCTAssertNil(ws.shellJob); XCTAssertNotNil(ws.message); XCTAssertFalse(s.exists("ran"))
        prefs.shellPath = "relative/sh"
        ws.message = nil
        ws.runShell(.command("touch ran"), destination: .panel, prefs: prefs)
        XCTAssertNotNil(ws.message)
    }

    func testTheBarOpensOnlyOnANoteInWriteMode() {
        ws.mode = .view
        ws.openShellBar(prefs: prefs)
        XCTAssertFalse(ws.shellBarVisible)
        ws.mode = .write
        ws.openShellBar(prefs: prefs)
        XCTAssertTrue(ws.shellBarVisible)
    }

    func testTheCommandIsInTheMenuOnCommandR() {
        let cmds = makeCommands(ws: ws, prefs: prefs, recents: RecentFolders(defaults: isolatedDefaults()), newWindow: { _ in })
        XCTAssertEqual(cmds.first { $0.id == "shell" }?.shortcut, "⌘R")
        XCTAssertEqual(cmds.first { $0.id == "rename" }?.shortcut, "⌥⌘R")
        XCTAssertEqual(cmds.first { $0.id == "shell" }?.enabled, true)
    }

    func testDestinationIsRemembered() {
        ws.shellDestination = .replace
        XCTAssertEqual(ws.shellDestination, .replace)
        XCTAssertEqual(ShellDestination(rawValue: ws.defaults.string(forKey: "shellDestination") ?? ""), .replace)
    }

    // MARK: history

    func testCommandsAreRememberedInTheFolderForTheOwnerOnly() throws {
        go("echo one", .panel); go("echo two", .panel); go("echo one", .panel)
        XCTAssertEqual(ShellFiles.history(in: s.url), ["echo two", "echo one"], "newest last, no repeats")
        let perms = try FileManager.default.attributesOfItem(atPath: s.path(".mdedit/history").path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        XCTAssertNil(ws.root?.find(s.path(".mdedit")), "the binder does not show it")
    }

    func testHistoryKeepsOnlyTheLastN() {
        prefs.shellHistory = 3
        for i in 1...6 { go("echo \(i)", .panel) }
        XCTAssertEqual(ShellFiles.history(in: s.url), ["echo 4", "echo 5", "echo 6"])
    }

    func testHistoryCanBeSwitchedOff() {
        prefs.shellHistory = 0
        go("echo secret", .panel)
        XCTAssertFalse(s.exists(".mdedit/history"))
    }

    func testHistoryIgnoresALinkedFolder() throws {
        let outside = try Scratch(); defer { outside.remove() }
        try FileManager.default.createSymbolicLink(at: s.path(".mdedit"), withDestinationURL: outside.url)
        go("echo hi", .panel)
        XCTAssertFalse(outside.exists("history"), "never written through a link")
    }

    func testAMultiLineCommandIsStoredOnOneLine() {
        ShellFiles.remember("echo a\n\n echo b \n", in: s.url, limit: 10)
        XCTAssertEqual(ShellFiles.history(in: s.url), ["echo a; echo b"])
    }

    func testAHugeHistoryFileIsReadSafely() throws {
        try s.write(".mdedit/history", String(repeating: "echo x\n", count: 500_000))
        XCTAssertLessThanOrEqual(ShellFiles.history(in: s.url).count, ShellFiles.maxHistoryBytes / 7 + 1)
    }

    // MARK: saved scripts

    func testOnlyPlainFilesInTheScriptsFolderAreScripts() throws {
        try s.write(".mdedit/scripts/b.sh", "echo b"); try s.write(".mdedit/scripts/a.sh", "echo a")
        try s.write(".mdedit/scripts/.hidden.sh", "x"); try s.write(".mdedit/scripts/sub/c.sh", "x")
        try FileManager.default.createSymbolicLink(at: s.path(".mdedit/scripts/link.sh"), withDestinationURL: s.path("Note.md"))
        XCTAssertEqual(ShellFiles.scripts(in: s.url), ["a.sh", "b.sh"])
        XCTAssertNil(ShellFiles.script(named: "../../Note.md", in: s.url)); XCTAssertNil(ShellFiles.script(named: "link.sh", in: s.url))
        XCTAssertNil(ShellFiles.script(named: "sub", in: s.url))
    }

    func testAScriptNeedsApprovalOfItsExactText() throws {
        try s.write(".mdedit/scripts/mark.sh", "touch ran-1")
        var shown: [String] = []
        ws.shellConfirm = { _, text, _ in shown.append(text); return false }
        ws.runShell(.script("mark.sh"), destination: .panel, prefs: prefs); finish()
        XCTAssertEqual(shown, ["touch ran-1"]); XCTAssertFalse(s.exists("ran-1"), "declined: it did not run")

        ws.shellConfirm = { _, text, _ in shown.append(text); return true }
        ws.runShell(.script("mark.sh"), destination: .panel, prefs: prefs); finish()
        XCTAssertTrue(s.exists("ran-1"))

        ws.shellConfirm = { _, _, _ in XCTFail("approved text should not ask again"); return false }
        ws.runShell(.script("mark.sh"), destination: .panel, prefs: prefs); finish()

        try s.write(".mdedit/scripts/mark.sh", "touch ran-2")
        var asked = 0
        ws.shellConfirm = { title, _, _ in asked += 1; XCTAssertTrue(title.contains("changed")); return false }
        ws.runShell(.script("mark.sh"), destination: .panel, prefs: prefs); finish()
        XCTAssertEqual(asked, 1); XCTAssertFalse(s.exists("ran-2"), "a changed script asks again")
    }

    func testAScriptGetsTheSameInputsAsATypedCommand() throws {
        try s.write(".mdedit/scripts/show.sh", "printf '%s|%s|' \"$0\" \"$MD_FILE_LINE\"; cat")
        ws.shellConfirm = { _, _, _ in true }
        tv.setSelectedRange(NSRange(location: 4, length: 3))
        ws.runShell(.script("show.sh"), destination: .panel, prefs: prefs); finish()
        XCTAssertEqual(ws.shellLog?.result.stdout, "show.sh|2|two")
    }

    func testNothingInANoteRunsByItself() throws {
        let hostile = "```sh\ntouch pwned-block\n```\n\n!touch pwned-bang\n\n---\nrun: touch pwned-fm\n---\n"
        try s.write("Evil.md", hostile)
        ws.reload(); ws.select(s.path("Evil.md"))
        ws.mode = .view; ws.mode = .write
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        for f in ["pwned-block", "pwned-bang", "pwned-fm"] { XCTAssertFalse(s.exists(f), f) }
    }

    // MARK: settings

    func testShellSettingsAreOffByDefaultPersistAndAreClamped() {
        let d = isolatedDefaults()
        let p = Preferences(defaults: d)
        XCTAssertFalse(p.shellEnabled); XCTAssertEqual(p.shellPath, "/bin/sh"); XCTAssertEqual(p.shellSearchPath, ShellEnvironment.defaultPath)
        XCTAssertEqual(p.shellEnvironment, ""); XCTAssertEqual(p.shellTimeout, 30); XCTAssertEqual(p.shellHistory, 50)
        p.shellEnabled = true; p.shellPath = "/bin/zsh"; p.shellEnvironment = "A=1"
        let q = Preferences(defaults: d)
        XCTAssertTrue(q.shellEnabled); XCTAssertEqual(q.shellPath, "/bin/zsh"); XCTAssertEqual(q.shellEnvironment, "A=1")
        d.set(99999, forKey: "shellTimeout"); d.set(-4, forKey: "shellHistory"); d.set(String(repeating: "x", count: 100_000), forKey: "shellEnvironment")
        let r = Preferences(defaults: d)
        XCTAssertEqual(r.shellTimeout, 600); XCTAssertEqual(r.shellHistory, 0); XCTAssertLessThanOrEqual(r.shellEnvironment.count, 16 * 1024)
    }
}

/// The suggestions under the ⌘R box: saved scripts on top, then recent commands, newest first.
final class ShellSuggestionTests: XCTestCase {
    func testScriptsComeFirstThenRecentCommandsNewestFirst() {
        let p = ShellBarView.picks(scripts: ["a.sh", "b.sh"], history: ["old", "newer", "newest"], query: "")
        XCTAssertEqual(p, [.script("a.sh"), .script("b.sh"), .recent("newest"), .recent("newer"), .recent("old")])
    }

    func testTypedWordsNarrowBothAndManyCommandsNeverHideScripts() {
        let history = (1...30).map { "echo \($0)" }
        let p = ShellBarView.picks(scripts: ["tidy.sh", "export.sh"], history: history, query: "")
        XCTAssertEqual(Array(p.prefix(2)), [.script("tidy.sh"), .script("export.sh")])
        XCTAssertEqual(p.count, 2 + 8)
        XCTAssertEqual(ShellBarView.picks(scripts: ["tidy.sh", "export.sh"], history: ["git status", "ls"], query: "ti"), [.script("tidy.sh")])
        XCTAssertEqual(ShellBarView.picks(scripts: ["tidy.sh"], history: ["git status", "ls"], query: "GIT st"), [.recent("git status")])
    }

    func testScriptsAddedToTheFolderAreListed() throws {
        let s = try Scratch([".mdedit/scripts/one.sh": "echo 1", "Note.md": "x"]); defer { s.remove() }
        try s.write(".mdedit/history", "echo hi\n")
        let p = ShellBarView.picks(scripts: ShellFiles.scripts(in: s.url), history: ShellFiles.history(in: s.url), query: "")
        XCTAssertEqual(p, [.script("one.sh"), .recent("echo hi")])
    }
}
