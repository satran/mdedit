import Foundation

/// The folders opened lately, for File > Open Recent. Each keeps a security-scoped bookmark so it can be reopened in the sandbox.
final class RecentFolders: ObservableObject {
    static let shared = RecentFolders(defaults: AppEnvironment.defaults)
    struct Item: Identifiable, Codable, Equatable {
        var path: String
        var bookmark: Data
        var id: String { path }
        var name: String { URL(fileURLWithPath: path).lastPathComponent }
    }

    private let key = "recentFolders"
    private let limit = 10
    @Published private(set) var items: [Item]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppEnvironment.defaults) {
        self.defaults = defaults
        let stored = (defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Item].self, from: $0) }) ?? []
        // a scratch folder that is gone (an old test run, a download unpacked and deleted) is clutter, not a recent folder;
        // a folder on a drive that is merely unplugged stays
        items = stored.filter { !Self.isTemporary($0.path) || FileManager.default.fileExists(atPath: $0.path) }
        if items.count != stored.count { save() }
    }

    static func isTemporary(_ path: String) -> Bool {
        let tmp = NSTemporaryDirectory()
        return path.hasPrefix(tmp) || path.hasPrefix((tmp as NSString).resolvingSymlinksInPath) || path.contains("/Data/tmp/")
            || path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/") || path.hasPrefix("/var/folders/") || path.hasPrefix("/private/var/folders/")
    }

    func add(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        let path = url.standardizedFileURL.path
        items.removeAll { $0.path == path }
        items.insert(Item(path: path, bookmark: data), at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
        save()
    }

    /// The folder behind an item, or nil (and the item is dropped) when it no longer resolves.
    func resolve(_ item: Item) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: item.bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            items.removeAll { $0 == item }; save(); return nil
        }
        // a folder outside the sandbox can only be looked at while its access is open
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else {
            items.removeAll { $0 == item }; save(); return nil
        }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil),
           let i = items.firstIndex(of: item) { items[i].bookmark = fresh; save() }
        return url
    }

    func clear() { items = []; save() }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
    }
}
