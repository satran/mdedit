import Foundation
import Darwin
import AppKit

/// Everything one shell command needs. The command is an argument, never part of a string we build, and the
/// environment is exactly the one given here: nothing is inherited from the app.
struct ShellRequest {
    var shell = "/bin/sh"
    /// What follows the shell on its command line: `["-c", command]`.
    var arguments: [String]
    var directory: URL
    var environment: [String: String]
    var input = Data()
    var timeout: TimeInterval = 30
    var maxOutput = ShellJob.maxOutput
}

struct ShellResult {
    var stdout = ""
    var stderr = ""
    /// The exit code, or 128 + the signal that ended it.
    var status: Int32 = 0
    var timedOut = false
    var cancelled = false
    /// The output went over the cap and the command was stopped.
    var truncated = false
    /// The shell could not be started at all.
    var startError: String?
    var duration: TimeInterval = 0

    var succeeded: Bool { status == 0 && !timedOut && !cancelled && !truncated && startError == nil }

    /// One line for the log panel header.
    var summary: String {
        if let startError { return startError }
        if cancelled { return "Cancelled" }
        if timedOut { return "Stopped: it ran too long" }
        if truncated { return "Stopped: the output was too large" }
        return status == 0 ? "Finished" : "Exit status \(status)"
    }
}

/// One running command. This is the only place in the app that starts a program (`make audit` checks).
///
/// - The command gets its own process group, and the whole group is killed when the command ends, so nothing it
///   started stays behind. It is also killed on cancel, on timeout, when the output is too large, and when the app quits.
/// - Output is read as it arrives and capped, so a runaway command cannot fill memory.
/// - The command inherits the app's sandbox: it can only reach the opened folder.
final class ShellJob: @unchecked Sendable {
    static let maxOutput = 5 * 1024 * 1024
    static let maxErrors = 64 * 1024

    private enum Stop { case timeout, cancel, size }

    private let request: ShellRequest
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var stop: Stop?
    private var reaped = false
    private var exited = false

    private static let liveLock = NSLock()
    private static var live: [ObjectIdentifier: ShellJob] = [:]

    private static let quitHook: Void = {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in ShellJob.cancelAll() }
    }()

    init(_ request: ShellRequest) { self.request = request; _ = Self.quitHook }

    /// Asks the command to stop; it is killed outright a moment later if it does not.
    func cancel() { halt(.cancel) }

    /// For quitting: every command still running is killed at once.
    static func cancelAll() {
        liveLock.lock(); let jobs = Array(live.values); liveLock.unlock()
        jobs.forEach { $0.halt(.cancel, immediately: true) }
    }

    func start() async -> ShellResult {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async { c.resume(returning: self.run()) }
        }
    }

    // MARK: running

    /// Runs the command and waits for it. Call from a background thread.
    func run() -> ShellResult {
        let began = Date()
        var result = ShellResult()
        var inPipe: [Int32] = [-1, -1], outPipe: [Int32] = [-1, -1], errPipe: [Int32] = [-1, -1]
        func closeAll() { (inPipe + outPipe + errPipe).filter { $0 >= 0 }.forEach { close($0) } }
        guard pipe(&inPipe) == 0, pipe(&outPipe) == 0, pipe(&errPipe) == 0 else {
            closeAll()
            result.startError = "Could not start the command (no pipes)"
            return result
        }
        // our ends must not leak into the child; the child's ends are handed over explicitly
        for fd in [inPipe[1], outPipe[0], errPipe[0]] { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        _ = fcntl(inPipe[1], F_SETNOSIGPIPE, 1)

        var actions: posix_spawn_file_actions_t?
        var attr: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attr)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attr) }
        posix_spawn_file_actions_adddup2(&actions, inPipe[0], 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
        posix_spawn_file_actions_addchdir_np(&actions, request.directory.path)
        var none = sigset_t(), all = sigset_t()
        sigemptyset(&none); sigfillset(&all)
        posix_spawnattr_setsigmask(&attr, &none)
        posix_spawnattr_setsigdefault(&attr, &all)
        posix_spawnattr_setpgroup(&attr, 0)
        // a new process group, default signals, and no file descriptors beyond the three above
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT))

        let argv = ([request.shell] + request.arguments).map { strdup($0) } + [nil]
        let envp = request.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }

        var child: pid_t = 0
        let rc = posix_spawn(&child, request.shell, &actions, &attr, argv, envp)
        close(inPipe[0]); close(outPipe[1]); close(errPipe[1])
        guard rc == 0 else {
            close(inPipe[1]); close(outPipe[0]); close(errPipe[0])
            result.startError = "Could not start \(request.shell): \(String(cString: strerror(rc)))"
            return result
        }

        lock.lock(); pid = child; let early = stop; lock.unlock()
        Self.liveLock.lock(); Self.live[ObjectIdentifier(self)] = self; Self.liveLock.unlock()
        defer { Self.liveLock.lock(); Self.live[ObjectIdentifier(self)] = nil; Self.liveLock.unlock() }
        if early != nil { signalGroup(SIGKILL) }

        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        var out = Data(), err = Data()
        let input = request.input
        group.enter(); queue.async { Self.feed(input, to: inPipe[1]); group.leave() }
        group.enter(); queue.async {
            out = self.drain(outPipe[0], cap: self.request.maxOutput) { self.halt(.size) }
            group.leave()
        }
        group.enter(); queue.async {
            err = self.drain(errPipe[0], cap: Self.maxErrors) {}
            group.leave()
        }

        let timer = DispatchWorkItem { [weak self] in self?.halt(.timeout) }
        DispatchQueue.global().asyncAfter(deadline: .now() + request.timeout, execute: timer)

        // wait without reaping, so the group id cannot be reused while we still signal it
        var info = siginfo_t()
        while waitid(P_PID, id_t(child), &info, WEXITED | WNOWAIT) != 0 && errno == EINTR {}
        timer.cancel()
        lock.lock(); exited = true; lock.unlock()
        signalGroup(SIGKILL)                       // whatever the command left running goes with it
        var raw: Int32 = 0
        while waitpid(child, &raw, 0) < 0 && errno == EINTR {}
        lock.lock(); reaped = true; let why = stop; lock.unlock()
        group.wait()

        result.status = info.si_code == CLD_EXITED ? info.si_status : 128 + info.si_status
        result.timedOut = why == .timeout
        result.cancelled = why == .cancel
        result.truncated = why == .size
        result.stdout = ShellOutput.clean(out)
        result.stderr = ShellOutput.clean(err)
        result.duration = Date().timeIntervalSince(began)
        return result
    }

    // MARK: stopping

    private func halt(_ why: Stop, immediately: Bool = false) {
        lock.lock()
        if stop == nil { stop = why }
        let p = pid, done = reaped || exited
        lock.unlock()
        guard p > 0, !done else { return }
        signalGroup(immediately ? SIGKILL : SIGTERM)
        if !immediately { DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.signalGroup(SIGKILL) } }
    }

    /// Signals the command's whole group, as long as the command has not been reaped (its id could then be someone else's).
    private func signalGroup(_ sig: Int32) {
        lock.lock(); defer { lock.unlock() }
        if pid > 0, !reaped { killpg(pid, sig) }
    }

    // MARK: pipes

    private static func feed(_ data: Data, to fd: Int32) {
        defer { close(fd) }
        data.withUnsafeBytes { raw in
            guard var p = raw.baseAddress else { return }
            var left = raw.count
            while left > 0 {
                let n = write(fd, p, min(left, 65536))
                if n < 0 { if errno == EINTR { continue }; return }      // the command stopped reading: fine
                p += n; left -= n
            }
        }
    }

    /// Reads until the command is gone and its pipe is quiet. Keeps at most `cap` bytes; going over stops the command.
    private func drain(_ fd: Int32, cap: Int, over: () -> Void) -> Data {
        defer { close(fd) }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 65536), total = 0, quiet = 0, tripped = false
        while true {
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&p, 1, 100)
            if ready < 0 { if errno == EINTR { continue }; break }
            if ready == 0 {
                lock.lock(); let gone = exited; lock.unlock()
                quiet = gone ? quiet + 1 : 0
                if quiet >= 3 { break }                // the command is gone, but something that escaped still holds the pipe
                continue
            }
            let n = read(fd, &buffer, buffer.count)
            if n < 0 { if errno == EINTR { continue }; break }
            if n == 0 { break }
            total += n
            if data.count < cap { data.append(contentsOf: buffer[0..<min(n, cap - data.count)]) }
            if total > cap, !tripped { tripped = true; over() }
        }
        return data
    }
}

/// What a command printed, made safe to put in a note: valid UTF-8, no terminal escape sequences, no control
/// characters, no characters that reorder text, and plain newlines.
enum ShellOutput {
    static func clean(_ data: Data) -> String {
        let u = Array(String(decoding: data, as: UTF8.self).unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        /// Past a string sequence (title, link, device control): up to its terminator, or the end if it never comes.
        func skip(until done: (Unicode.Scalar) -> Bool) {
            while i < u.count {
                let c = u[i]; i += 1
                if done(c) { return }
                if c == "\u{1B}", i < u.count, u[i] == "\\" { i += 1; return }
            }
        }
        while i < u.count {
            let c = u[i]; i += 1
            switch c.value {
            case 0x1B:
                guard i < u.count else { break }
                let next = u[i]; i += 1
                switch next {
                case "[":                                                                                // CSI: colours, cursor
                    while i < u.count, (0x20...0x3F).contains(u[i].value) { i += 1 }
                    if i < u.count, (0x40...0x7E).contains(u[i].value) { i += 1 }
                case "]": skip { $0 == "\u{07}" }                                                        // OSC: titles, links
                case "P", "X", "^", "_": skip { _ in false }                                             // DCS and friends
                default: break                                                                           // ESC plus one
                }
            case 0x0D:
                if i < u.count, u[i] == "\n" { continue }
                out.append("\n")
            case 0x0A, 0x09: out.append(c)
            case 0x2028, 0x2029: out.append("\n")
            case 0..<0x20, 0x7F, 0x80...0x9F: continue
            case 0x200E, 0x200F, 0x061C, 0x202A...0x202E, 0x2066...0x2069, 0xFEFF: continue
            default: out.append(c)
            }
        }
        return String(out)
    }
}

/// The environment a command gets: a short list we choose, what the user added in Settings, then the `MD_` variables.
enum ShellEnvironment {
    static let defaultPath = "/usr/bin:/bin:/usr/sbin:/sbin"
    static let defaultShell = "/bin/sh"
    /// Larger selections go to stdin only; environments are limited to about 1 MB in all.
    static let maxSelection = 64 * 1024
    static let maxExtra = 64
    /// Variables that change how programs load code or start the shell: not settable from Settings.
    private static let blocked: [String] = ["DYLD_", "LD_", "BASH_ENV", "ENV", "IFS", "SHELLOPTS", "BASHOPTS", "PROMPT_COMMAND", "ZDOTDIR"]

    static func validName(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 128, let f = s.unicodeScalars.first, !("0"..."9").contains(f) else { return false }
        return s.unicodeScalars.allSatisfy { ($0 == "_") || ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("0"..."9").contains($0) }
    }

    /// `KEY=value` lines; blank lines and `#` comments are skipped, a leading `export` and matching quotes are dropped.
    static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let name = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let f = value.first, f == value.last, f == "\"" || f == "'" { value = String(value.dropFirst().dropLast()) }
            value = value.replacingOccurrences(of: "\0", with: "")
            guard validName(name), !name.hasPrefix("MD_"), !blocked.contains(where: { name == $0 || ($0.hasSuffix("_") && name.hasPrefix($0)) }),
                  value.utf8.count <= 4096, out.count < maxExtra else { continue }
            out[name] = value
        }
        return out
    }

    static func build(path: String, extra: String, md: [String: String]) -> [String: String] {
        var env: [String: String] = [
            "PATH": usablePath(path),
            "HOME": NSHomeDirectory(),
            "LANG": "en_US.UTF-8",
            "TERM": "dumb",
            "TMPDIR": NSTemporaryDirectory(),
        ]
        for (k, v) in parse(extra) { env[k] = v }
        for (k, v) in md { env[k] = v.replacingOccurrences(of: "\0", with: "") }
        return env
    }

    static func usablePath(_ p: String) -> String {
        let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t.contains("\0") || t.contains("\n") || t.utf8.count > 4096 ? defaultPath : t
    }

    /// The `MD_` variables for a note and a caret. Lines and columns start at 1; a column counts characters.
    static func variables(root: URL, file: URL, text: NSString, caret: Int, selection: String) -> [String: String] {
        let (line, column) = position(in: text, at: caret)
        var v = ["MD_WORKING_DIR": root.path, "MD_FILE_PATH": file.path, "MD_FILE_LINE": String(line), "MD_FILE_COLUMN": String(column)]
        if !selection.isEmpty, selection.utf8.count <= maxSelection { v["MD_FILE_SELECTION"] = selection }
        return v
    }

    static func position(in text: NSString, at location: Int) -> (line: Int, column: Int) {
        let loc = min(max(0, location), text.length)
        var line = 1, start = 0, i = 0
        while i < loc { if text.character(at: i) == 0x0A { line += 1; start = i + 1 }; i += 1 }
        let before = text.substring(with: NSRange(location: start, length: loc - start))
        return (line, before.count + 1)
    }
}
