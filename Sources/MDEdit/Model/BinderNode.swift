import Foundation

/// One folder or Markdown file in the opened folder.
final class BinderNode: Identifiable {
    let url: URL
    let isFolder: Bool
    var children: [BinderNode]
    var id: URL { url }
    var name: String { isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent }

    init(url: URL, isFolder: Bool, children: [BinderNode] = []) {
        self.url = url; self.isFolder = isFolder; self.children = children
    }

    static let markdownExtensions: Set<String> = ["md", "markdown"]

    /// Reads the tree below `url`: folders first, then files, each in natural order. Hidden files are skipped.
    static func scan(_ url: URL, fileManager fm: FileManager = .default) -> BinderNode {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        let urls = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        var folders: [BinderNode] = [], files: [BinderNode] = []
        for u in urls {
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.isDirectory == true {
                if v?.isPackage == true { continue }
                folders.append(scan(u, fileManager: fm))
            } else if markdownExtensions.contains(u.pathExtension.lowercased()) {
                files.append(BinderNode(url: u, isFolder: false))
            }
        }
        let order: (BinderNode, BinderNode) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return BinderNode(url: url, isFolder: true, children: folders.sorted(by: order) + files.sorted(by: order))
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

    /// Every Markdown file below this node, depth first.
    var files: [BinderNode] { isFolder ? children.flatMap { $0.files } : [self] }
}

struct BinderRow: Identifiable {
    let node: BinderNode
    let depth: Int
    let isOpen: Bool
    var id: URL { node.url }
}
