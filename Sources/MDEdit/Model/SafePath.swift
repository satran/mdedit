import Foundation

/// The one rule for a path that comes from outside the app (an agent, a template): relative, inside the opened folder after
/// symlinks are followed, no hidden part (written or reached through a link), and of the kind asked for.
enum SafePath {
    enum Kind {
        /// A note file: `.md`, `.markdown` or `.txt`, a regular file.
        case note
        /// A folder (not a package). `""` is the opened folder itself.
        case folder
    }

    struct Failure: Error, Equatable {
        let code: String
        let message: String
    }

    static func resolve(_ path: String, in root: URL, kind: Kind) -> Result<URL, Failure> {
        func fail(_ c: String, _ m: String) -> Result<URL, Failure> { .failure(Failure(code: c, message: m)) }
        if path.hasPrefix("/") || path.hasPrefix("~") { return fail("outside_folder", "Use a path relative to the folder.") }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.contains("..") { return fail("outside_folder", "The path leaves the folder.") }
        if parts.contains(where: { $0.hasPrefix(".") }) { return fail("not_a_note", "Hidden files are not available.") }
        if kind == .note {
            guard let last = parts.last, BinderNode.documentExtensions.contains((last as NSString).pathExtension.lowercased()) else {
                return fail("not_a_note", "Only .md, .markdown and .txt notes are available.")
            }
        }
        let rootR = root.resolvingSymlinksInPath()
        let url = parts.reduce(rootR) { $0.appendingPathComponent($1) }.resolvingSymlinksInPath()
        guard url.path == rootR.path || url.path.hasPrefix(rootR.path + "/") else { return fail("outside_folder", "The path leaves the folder.") }
        // a visible name can link to a hidden file inside the folder (`a.md -> .secret/a.md`): look at the resolved path too
        if let below = relative(url, in: root), below.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
            return fail("not_a_note", "Hidden files are not available.")
        }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey])
        switch kind {
        case .note:
            guard values?.isRegularFile == true, values?.isPackage != true else { return fail("not_a_note", "No such note.") }
        case .folder:
            guard values?.isDirectory == true, values?.isPackage != true else { return fail("not_a_note", "No such folder.") }
        }
        return .success(url)
    }

    /// The path of `url` below the resolved `root`: `""` for the root itself, nil when it is outside.
    static func relative(_ url: URL, in root: URL) -> String? {
        let u = url.resolvingSymlinksInPath().path, r = root.resolvingSymlinksInPath().path
        if u == r { return "" }
        return u.hasPrefix(r + "/") ? String(u.dropFirst(r.count + 1)) : nil
    }
}
