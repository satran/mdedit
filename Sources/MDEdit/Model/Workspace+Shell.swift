import SwiftUI
import AppKit
import CryptoKit

/// Where a command's output goes.
enum ShellDestination: String, CaseIterable {
    case insert, replace, newFile, panel
    var title: String {
        switch self {
        case .insert: return "Insert"
        case .replace: return "Replace"
        case .newFile: return "New File"
        case .panel: return "Panel"
        }
    }
    var detail: String {
        switch self {
        case .insert: return "Output goes in at the caret"
        case .replace: return "Output replaces the selection, or the whole note"
        case .newFile: return "Output goes in a new note next to this one"
        case .panel: return "Output is only shown; for commands that act on files"
        }
    }
}

/// What the log panel shows: the last command that failed, or whose output was only to be shown.
struct ShellLog: Identifiable {
    let id = UUID()
    var command: String
    var result: ShellResult
    var note: String?
}

/// What runs: a line typed in the box, or a saved script from `.mdedit/scripts`.
enum ShellSource: Equatable {
    case command(String)
    case script(String)
}

enum ShellPrompts {
    static func confirm(_ title: String, _ detail: String, _ button: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = detail
        a.addButton(withTitle: button)
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }
}

/// Saved scripts and the history live in `<folder>/.mdedit`, which the binder does not show.
enum ShellFiles {
    static let maxScript = 256 * 1024
    static let maxHistoryBytes = 256 * 1024

    private static func isLink(_ u: URL) -> Bool { (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false }

    static func scriptsFolder(_ root: URL) -> URL { root.appendingPathComponent(".mdedit/scripts", isDirectory: true) }
    static func historyFile(_ root: URL) -> URL { root.appendingPathComponent(".mdedit/history") }

    /// Plain files directly in the scripts folder. Links, hidden files and folders are not scripts.
    static func scripts(in root: URL) -> [String] {
        let dir = scriptsFolder(root)
        guard !isLink(root.appendingPathComponent(".mdedit")), !isLink(dir),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { name in
            let u = dir.appendingPathComponent(name)
            guard !name.hasPrefix("."), !isLink(u), let v = try? u.resourceValues(forKeys: [.isRegularFileKey]) else { return false }
            return v.isRegularFile == true
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.prefix(200).map { $0 }
    }

    /// The script's text, read once. Nil when it is not a plain file, is too big or is not text.
    static func script(named name: String, in root: URL) -> String? {
        guard scripts(in: root).contains(name) else { return nil }
        let u = scriptsFolder(root).appendingPathComponent(name)
        guard let data = try? Data(contentsOf: u), data.count <= maxScript, !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }

    static func history(in root: URL) -> [String] {
        let f = historyFile(root)
        guard !isLink(root.appendingPathComponent(".mdedit")), !isLink(f),
              let h = try? FileHandle(forReadingFrom: f) else { return [] }
        defer { try? h.close() }
        let data = (try? h.read(upToCount: maxHistoryBytes)) ?? Data()
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }

    /// Remembers a command (newest last, no repeats), keeping the last `limit`. The file is for its owner only.
    static func remember(_ command: String, in root: URL, limit: Int) {
        guard limit > 0 else { return }
        let folder = root.appendingPathComponent(".mdedit", isDirectory: true)
        guard !isLink(folder), !isLink(historyFile(root)) else { return }
        let line = command.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "; ")
        guard !line.isEmpty else { return }
        var all = history(in: root).filter { $0 != line }
        all.append(line)
        all = Array(all.suffix(limit))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let f = historyFile(root)
            try Data((all.joined(separator: "\n") + "\n").utf8).write(to: f, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path)
        } catch {}
    }
}

extension Workspace {
    /// ⌘R. Needs a note open in Write mode, and the feature turned on in Settings.
    func openShellBar(prefs: Preferences = .shared) {
        guard document.url != nil, mode == .write else { return }
        guard prefs.shellEnabled else { message = "Shell commands are off. Turn them on in Settings → Shell."; return }
        shellBarVisible = true
    }

    func cancelShell() { shellJob?.cancel() }

    /// Runs a command on the open note and puts the result where `destination` says.
    /// Order: save the note, work out what the command sees, run it away from the main thread, then apply the result
    /// only if the note is still the one it ran on.
    func runShell(_ source: ShellSource, destination: ShellDestination, prefs: Preferences = .shared) {
        guard shellJob == nil else { return }
        guard prefs.shellEnabled else { message = "Shell commands are off. Turn them on in Settings → Shell."; return }
        guard let root = rootURL, let file = document.url, let tv = editor.textView else { return }
        guard !document.unreadable, !document.changedOnDisk else { message = "This note changed on disk. Sort that out first, then run the command."; return }
        let shell = prefs.shellPath
        guard shell.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: shell) else { message = "The shell \(shell) was not found. Check Settings → Shell."; return }

        let label: String, arguments: [String]
        switch source {
        case .command(let raw):
            let c = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !c.isEmpty else { return }
            label = c; arguments = ["-c", c]
            ShellFiles.remember(c, in: root, limit: prefs.shellHistory)
        case .script(let name):
            guard let text = ShellFiles.script(named: name, in: root) else { message = "The script \(name) could not be read."; return }
            guard approved(name, text, root: root) else { return }
            label = name; arguments = ["-c", text, name]
        }

        document.saveNow()
        let text = tv.string as NSString
        let sel = tv.selectedRange()
        let chosen = sel.length > 0 ? text.substring(with: sel) : ""
        let snapshot = tv.string
        let env = ShellEnvironment.build(path: prefs.shellSearchPath, extra: prefs.shellEnvironment,
                                         md: ShellEnvironment.variables(root: root, file: file, text: text, caret: sel.location, selection: chosen))
        let job = ShellJob(ShellRequest(shell: shell, arguments: arguments, directory: root, environment: env,
                                        input: Data((sel.length > 0 ? chosen : snapshot).utf8), timeout: TimeInterval(prefs.shellTimeout)))
        shellJob = job
        shellLog = nil
        Task { @MainActor [weak self] in
            let result = await job.start()
            self?.finishShell(result, label: label, destination: destination, file: file, snapshot: snapshot, selection: sel)
        }
    }

    /// A saved script runs only with your say-so for exactly this text.
    private func approved(_ name: String, _ text: String, root: URL) -> Bool {
        let key = "shellApproved:" + root.path
        var known = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        let h = ShellFiles.hash(text)
        if known[name] == h { return true }
        let shown = text.count > 3000 ? String(text.prefix(3000)) + "\n…" : text
        let again = known[name] != nil
        guard shellConfirm(again ? "“\(name)” has changed. Run it?" : "Run the script “\(name)”?", shown, "Run") else { return false }
        known[name] = h
        defaults.set(known, forKey: key)
        return true
    }

    private func finishShell(_ result: ShellResult, label: String, destination: ShellDestination, file: URL, snapshot: String, selection: NSRange) {
        shellJob = nil
        shellBarVisible = false
        guard result.succeeded else { shellLog = ShellLog(command: label, result: result); return }
        guard let tv = editor.textView, document.url == file, tv.string == snapshot || destination == .newFile || destination == .panel else {
            shellLog = ShellLog(command: label, result: result, note: "The note changed while the command ran, so its output was not applied.")
            return
        }
        switch destination {
        case .panel:
            shellLog = ShellLog(command: label, result: result)
        case .insert:
            tv.insertOutput(result.stdout, at: NSRange(location: selection.location + selection.length, length: 0))
        case .replace:
            let target = selection.length > 0 ? selection : NSRange(location: 0, length: (snapshot as NSString).length)
            if result.stdout.isEmpty, target.length > 0,
               !shellConfirm("The command printed nothing.", selection.length > 0 ? "Replace the selection with nothing?" : "Replace the whole note with nothing? You can undo it with ⌘Z.", "Replace") { return }
            tv.insertOutput(result.stdout, at: target)
        case .newFile:
            let folder = file.deletingLastPathComponent()
            let url = Self.uniqueURL(in: folder, base: "Output " + file.deletingPathExtension().lastPathComponent, ext: file.pathExtension.isEmpty ? "md" : file.pathExtension)
            do { try Data(result.stdout.utf8).write(to: url, options: .withoutOverwriting) } catch { message = error.localizedDescription; return }
            reload()
            select(url)
        }
    }
}

extension EditorTextView {
    /// One undo step: output replaces `range`, and the caret lands after it.
    func insertOutput(_ output: String, at range: NSRange) {
        guard isEditable else { return }
        let n = (string as NSString).length
        let r = NSRange(location: min(range.location, n), length: min(range.length, n - min(range.location, n)))
        breakUndoCoalescing()
        insertText(output, replacementRange: r)
        breakUndoCoalescing()
        setSelectedRange(NSRange(location: min(r.location + (output as NSString).length, (string as NSString).length), length: 0))
        scrollRangeToVisible(selectedRange())
    }
}
