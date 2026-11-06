import Foundation

/// Which template files the person has approved: a SHA-256 of the exact text, kept in the app's settings and never in the folder
/// (a record in a received folder could approve its own template). A changed file, another folder or another path is not approved.
enum TemplateTrust {
    static let maxFiles = 200
    static let maxRoots = 50
    static let rootsKey = "templateApprovedRoots"

    static func key(for root: URL) -> String { "templateApproved:" + root.resolvingSymlinksInPath().path }

    private static func entries(_ root: URL, _ defaults: UserDefaults) -> [[String]] {
        (defaults.array(forKey: key(for: root)) as? [[String]]) ?? []
    }

    static func isApproved(_ path: String, text: String, root: URL, defaults: UserDefaults) -> Bool {
        let hash = ContentHash.sha256(text)
        return entries(root, defaults).contains { $0.count == 2 && $0[0] == path && $0[1] == hash }
    }

    /// Records the approval and makes it the most recently used. Past 200 files per folder or 50 folders, the least recently used goes.
    static func approve(_ path: String, text: String, root: URL, defaults: UserDefaults) {
        var list = entries(root, defaults).filter { $0.first != path }
        list.insert([path, ContentHash.sha256(text)], at: 0)
        defaults.set(Array(list.prefix(maxFiles)), forKey: key(for: root))

        let k = key(for: root)
        var roots = (defaults.stringArray(forKey: rootsKey) ?? []).filter { $0 != k }
        roots.insert(k, at: 0)
        for dropped in roots.dropFirst(maxRoots) { defaults.removeObject(forKey: dropped) }
        defaults.set(Array(roots.prefix(maxRoots)), forKey: rootsKey)
    }
}
