import SwiftUI
import AppKit

enum Mode: String { case write, view }

/// The opened folder, its tree, what is selected, and the open document.
final class Workspace: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var root: BinderNode?
    @Published var expanded: Set<URL> = [] { didSet { saveExpanded() } }
    @Published var selection: URL?
    @Published var search = ""
    @Published var mode: Mode = .write
    @Published var message: String?

    let document = DocumentStore()
    private var watcher: FolderWatcher?
    private var scoped: URL?
    private let defaults = UserDefaults.standard

    init() { restore() }

    // MARK: opening a folder

    func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.prompt = "Open"; p.message = "Choose the folder to write in"
        guard p.runModal() == .OK, let url = p.url else { return }
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(data, forKey: "folderBookmark")
        }
        open(url)
    }

    /// A folder dropped on the Dock icon, or opened with `open -a`.
    func openExternal(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(data, forKey: "folderBookmark")
        }
        open(url)
    }

    private func restore() {
        guard let data = defaults.data(forKey: "folderBookmark") else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: "folderBookmark")
        }
        open(url, restoring: true)
    }

    func open(_ url: URL, restoring: Bool = false) {
        document.saveNow()
        watcher?.stop(); watcher = nil
        scoped?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        scoped = url
        rootURL = url
        search = ""
        document.open(nil)
        selection = nil
        expanded = Set((defaults.stringArray(forKey: expandedKey(url)) ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) })
        reload()
        watcher = FolderWatcher(url: url) { [weak self] in self?.reload() }
        if restoring, let last = defaults.string(forKey: "lastFile").map({ URL(fileURLWithPath: $0) }), root?.find(last) != nil { select(last) }
        else if let first = root?.files.first { select(first.url) }
    }

    func reload() {
        guard let rootURL else { return }
        root = BinderNode.scan(rootURL)
        document.checkDisk()
        if let s = selection, root?.find(s) == nil { selection = nil }
    }

    // MARK: selection

    func select(_ url: URL) {
        selection = url
        guard let node = root?.find(url) else { return }
        if node.isFolder { toggle(url) }
        else {
            document.open(url)
            defaults.set(url.path, forKey: "lastFile")
        }
    }

    func toggle(_ url: URL) {
        if expanded.contains(url) { expanded.remove(url) } else { expanded.insert(url) }
    }

    func collapseAll() { expanded = [] }

    private func expandedKey(_ url: URL) -> String { "expanded:" + url.path }
    private func saveExpanded() {
        guard let rootURL else { return }
        defaults.set(expanded.map(\.path), forKey: expandedKey(rootURL))
    }

    var rows: [BinderRow] { root?.rows(expanded: expanded, search: search) ?? [] }

    /// Folder names from the opened folder down to the open file, for the header.
    var breadcrumb: [String] {
        guard let rootURL, let url = document.url else { return [] }
        let base = rootURL.standardizedFileURL.pathComponents, full = url.standardizedFileURL.deletingPathExtension().pathComponents
        guard full.count > base.count, Array(full.prefix(base.count)) == base else { return [url.deletingPathExtension().lastPathComponent] }
        return Array(full.dropFirst(base.count))
    }

    // MARK: making things

    /// The folder new items go in: the selected folder, the folder of the selected file, else the root.
    private var targetFolder: URL? {
        if let s = selection, let n = root?.find(s) { return n.isFolder ? n.url : n.url.deletingLastPathComponent() }
        return rootURL
    }

    static func uniqueURL(in folder: URL, base: String, ext: String?) -> URL {
        let fm = FileManager.default
        func make(_ n: Int) -> URL {
            let name = n == 0 ? base : "\(base) \(n + 1)"
            let u = folder.appendingPathComponent(name, isDirectory: ext == nil)
            return ext.map { u.appendingPathExtension($0) } ?? u
        }
        var n = 0
        while fm.fileExists(atPath: make(n).path) { n += 1 }
        return make(n)
    }

    func newDocument() {
        guard let folder = targetFolder else { return }
        let url = Self.uniqueURL(in: folder, base: "Untitled", ext: "md")
        do { try "".write(to: url, atomically: true, encoding: .utf8) } catch { message = error.localizedDescription; return }
        expanded.insert(folder)
        reload()
        select(url)
    }

    func newFolder() {
        guard let parent = targetFolder else { return }
        let url = Self.uniqueURL(in: parent, base: "New Folder", ext: nil)
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) } catch { message = error.localizedDescription; return }
        expanded.insert(parent)
        reload()
        selection = url
    }

    // MARK: wiki links

    /// Opens the note a [[link]] points at, or offers to make it.
    func openWiki(_ target: String) {
        let link = WikiLink(target: target, alias: nil)
        if let url = WikiIndex.resolve(link, from: document.url, in: root) { reveal(url); select(url); return }
        let name = link.note.split(separator: "/").last.map(String.init) ?? link.note
        guard !name.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Create “\(name)”?"
        alert.informativeText = "No note with that name exists yet."
        alert.addButton(withTitle: "Create"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let folder = document.url?.deletingLastPathComponent() ?? rootURL
        guard let folder else { return }
        let url = Self.uniqueURL(in: folder, base: name, ext: "md")
        do { try "# \(name)\n\n".write(to: url, atomically: true, encoding: .utf8) } catch { message = error.localizedDescription; return }
        reload(); reveal(url); select(url)
    }

    /// Opens the folders above a file so it shows in the binder.
    func reveal(_ url: URL) {
        guard let rootURL else { return }
        var dir = url.deletingLastPathComponent().standardizedFileURL
        let top = rootURL.standardizedFileURL
        while dir.path.count > top.path.count, dir.path.hasPrefix(top.path) {
            expanded.insert(URL(fileURLWithPath: dir.path, isDirectory: true))
            dir = dir.deletingLastPathComponent()
        }
    }

    func revealInFinder() {
        if let u = selection ?? rootURL { NSWorkspace.shared.activateFileViewerSelecting([u]) }
    }
}
