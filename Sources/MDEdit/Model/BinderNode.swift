import Foundation

/// One folder or file in the opened folder. Markdown and text files are notes; anything else opens in its default app.
final class BinderNode: Identifiable {
    let url: URL
    let isFolder: Bool
    var children: [BinderNode]
    var id: URL { url }
    /// Notes show without their extension; other files keep it.
    var isDocument: Bool { !isFolder && Self.documentExtensions.contains(url.pathExtension.lowercased()) }
    /// A web page: shown in the preview and never edited, so it is not a note (no wiki links, no search, no replace) and keeps its extension.
    var isHTML: Bool { !isFolder && Self.htmlExtensions.contains(url.pathExtension.lowercased()) }
    /// Opens in the writing pane rather than in Quick Look.
    /// A file shown as code: HTML, JSON and YAML open in the editor, and the preview shows the page, a table or pretty JSON.
    var isCode: Bool { !isFolder && Self.codeExtensions.contains(url.pathExtension.lowercased()) }
    var opensInApp: Bool { isDocument || isCode }
    var name: String { isFolder || !isDocument ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent }
    /// The SF Symbol that stands for the file: its own for notes, web pages, JSON and the other code files; a plain page for the rest.
    var symbol: String {
        isFolder ? "folder" : isDocument ? "doc.text" : isHTML ? "globe"
            : Self.jsonExtensions.contains(url.pathExtension.lowercased()) ? "curlybraces" : isCode ? "list.bullet.rectangle" : "doc"
    }
    /// What the binder shows. A file whose icon already says what it is goes without its extension; one with the plain
    /// page icon (and the files that only preview, never open in the editor) keeps it, since the extension is all that tells.
    var label: String { isCode ? url.deletingPathExtension().lastPathComponent : name }

    init(url: URL, isFolder: Bool, children: [BinderNode] = []) {
        self.url = url; self.isFolder = isFolder; self.children = children
    }

    static let maxDepth = 40
    static let markdownExtensions: Set<String> = ["md", "markdown"]
    static let documentExtensions: Set<String> = markdownExtensions.union(["txt"])
    static let htmlExtensions: Set<String> = ["html", "htm"]
    static let jsonExtensions: Set<String> = ["json"]
    static let yamlExtensions: Set<String> = ["yaml", "yml"]
    static let codeExtensions: Set<String> = htmlExtensions.union(jsonExtensions).union(yamlExtensions)

    /// One level of a folder: subfolders (not yet read) first, then files, each in natural order. Hidden entries, packages and
    /// links to folders are skipped; links to files are kept. `rawCount` is how many entries the folder held before any were skipped.
    static func entries(of url: URL, fileManager fm: FileManager = .default) -> (nodes: [BinderNode], rawCount: Int) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey]
        let urls = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])) ?? []
        var folders: [BinderNode] = [], files: [BinderNode] = []
        for u in urls {
            if u.lastPathComponent.hasPrefix(".") { continue }
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.isHidden == true { continue }
            if v?.isSymbolicLink == true {
                // a link to a folder could lead back into this one, or out of it; links to files are fine
                var d: ObjCBool = false
                if fm.fileExists(atPath: u.resolvingSymlinksInPath().path, isDirectory: &d), d.boolValue { continue }
                files.append(BinderNode(url: u, isFolder: false))
            } else if v?.isDirectory == true {
                if v?.isPackage == true { continue }
                folders.append(BinderNode(url: u, isFolder: true))
            } else {
                files.append(BinderNode(url: u, isFolder: false))
            }
        }
        let order: (BinderNode, BinderNode) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (folders.sorted(by: order) + files.sorted(by: order), urls.count)
    }

    /// Reads the tree below `url`: folders first, then files, each in natural order. Hidden files are skipped.
    static func scan(_ url: URL, fileManager fm: FileManager = .default, depth: Int = 0) -> BinderNode {
        // deeper than any real folder tree: a guard against loops and hostile folders
        guard depth < maxDepth else { return BinderNode(url: url, isFolder: true) }
        let kids = entries(of: url, fileManager: fm).nodes.map { $0.isFolder ? scan($0.url, fileManager: fm, depth: depth + 1) : $0 }
        return BinderNode(url: url, isFolder: true, children: kids)
    }

    /// The rows to show, in order: a folder's children follow it when it is expanded.
    /// With a search, only matching items and the folders that lead to them show, all open.
    func rows(expanded: Set<URL>, search: String) -> [BinderRow] {
        var out: [BinderRow] = []
        let q = search.trimmingCharacters(in: .whitespaces)
        func matches(_ n: BinderNode) -> Bool {
            if q.isEmpty { return true }
            if n.name.localizedCaseInsensitiveContains(q) { return true }
            return n.isFolder && n.children.contains(where: matches)
        }
        func walk(_ n: BinderNode, _ depth: Int) {
            for c in n.children where matches(c) {
                let open = c.isFolder && (!q.isEmpty || expanded.contains(c.url))
                out.append(BinderRow(node: c, depth: depth, isOpen: open))
                if open { walk(c, depth + 1) }
            }
        }
        walk(self, 0)
        return out
    }

    func find(_ target: URL) -> BinderNode? {
        if url == target { return self }
        for c in children { if let f = c.find(target) { return f } }
        return nil
    }

    /// Every note (Markdown or text) below this node, depth first.
    var files: [BinderNode] { isFolder ? children.flatMap { $0.files } : (isDocument ? [self] : []) }
}

struct BinderRow: Identifiable {
    let node: BinderNode
    let depth: Int
    let isOpen: Bool
    var id: URL { node.url }
}
