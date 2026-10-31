import Foundation

/// The folders opened lately, for File > Open Recent. Each keeps a security-scoped bookmark so it can be reopened in the sandbox.
final class RecentFolders: ObservableObject {
    static let shared = RecentFolders()
    struct Item: Identifiable, Codable, Equatable {
        var path: String
        var bookmark: Data
        var id: String { path }
        var name: String { URL(fileURLWithPath: path).lastPathComponent }
    }

    private let key = "recentFolders"
    private let limit = 10
    @Published private(set) var items: [Item]

    init() {
        items = (UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Item].self, from: $0) }) ?? []
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
        guard let url = try? URL(resolvingBookmarkData: item.bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else {
            items.removeAll { $0 == item }; save(); return nil
        }
        return url
    }

    func clear() { items = []; save() }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
    }
}
