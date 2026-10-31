import Foundation
import UniformTypeIdentifiers

/// What a click on a link in a note may do. Notes can come from anywhere, so a link is never trusted:
/// only web addresses and mail go to the system, and files only from inside the opened folder — and programs
/// are shown in Finder, never run.
enum LinkPolicy {
    enum Action: Equatable {
        case wiki(String)
        case openWeb(URL)
        case selectNote(URL)
        case openFile(URL)
        case reveal(URL)
        case ignore
    }

    static let webSchemes: Set<String> = ["http", "https", "mailto"]

    /// Extensions that run or install something when opened.
    static let programExtensions: Set<String> = [
        "app", "command", "sh", "bash", "zsh", "csh", "tcsh", "ksh", "fish", "pkg", "mpkg", "dmg", "jar", "workflow", "scpt", "scptd",
        "applescript", "terminal", "tool", "action", "osax", "prefpane", "webloc", "inetloc", "fileloc", "url", "exe", "bat", "cmd", "com",
        "msi", "ps1", "vbs", "js", "jse", "wsf", "py", "pl", "rb", "php", "plugin", "kext", "xpc", "service", "saver", "qlgenerator",
        "mdimporter", "dylib", "bundle", "framework", "ipa", "apk", "iso", "pyc", "lnk", "scr", "jnlp",
    ]

    static func isProgram(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if programExtensions.contains(ext) { return true }
        if let t = UTType(filenameExtension: ext), t.conforms(to: .executable) || t.conforms(to: .application) || t.conforms(to: .script) || t.conforms(to: .shellScript) { return true }
        var dir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &dir), !dir.boolValue, FileManager.default.isExecutableFile(atPath: url.path) { return true }
        return false
    }

    /// Browsers ignore tabs, newlines and other control characters inside a scheme (`java\tscript:`), so look at the cleaned text.
    static func cleaned(_ s: String) -> String {
        String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0) })
    }

    /// The scheme of a link as a browser would read it, or nil when it is a relative path.
    static func scheme(of s: String) -> String? {
        let c = cleaned(s)
        guard let colon = c.firstIndex(of: ":") else { return nil }
        let head = c[..<colon]
        if head.contains(where: { "/?#".contains($0) }) { return nil }
        return head.lowercased()
    }

    static func decide(_ url: URL, noteFolder: URL?, root: URL?) -> Action {
        if let target = WikiLink.target(from: url) { return .wiki(target) }
        if let scheme = scheme(of: url.absoluteString) {
            if webSchemes.contains(scheme) { return .openWeb(url) }
            guard scheme == "file", url.isFileURL else { return .ignore }
            return local(url.standardizedFileURL, root: root)
        }
        guard let noteFolder else { return .ignore }
        let rel = url.path(percentEncoded: false)
        guard !rel.isEmpty else { return .ignore }
        let target = (rel.hasPrefix("/") ? URL(fileURLWithPath: rel) : URL(fileURLWithPath: rel, relativeTo: noteFolder)).standardizedFileURL
        return local(target, root: root)
    }

    /// A file link: only inside the opened folder; notes open in the app, programs and folders are revealed.
    private static func local(_ target: URL, root: URL?) -> Action {
        guard let root, target.path.hasPrefix(root.standardizedFileURL.path + "/") else { return .ignore }
        let resolved = target.resolvingSymlinksInPath()
        // a link inside the folder that points out of it is not inside it
        guard resolved.path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { return .ignore }
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &dir) else { return .ignore }
        if dir.boolValue || isProgram(resolved) { return .reveal(resolved) }
        if BinderNode.documentExtensions.contains(resolved.pathExtension.lowercased()) { return .selectNote(target) }
        return .openFile(resolved)
    }
}
