import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Mode: String { case write, view }

/// The opened folder, its tree, what is selected, and the open document.
final class Workspace: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var root: BinderNode?
    @Published var expanded: Set<URL> = [] { didSet { saveExpanded() } }
    @Published var selection: URL?
    @Published var search = ""
    @Published var mode: Mode = .write
    @Published var focus = false
    /// The row being renamed in the binder.
    @Published var renaming: URL?
    @Published var typewriter: Bool { didSet { defaults.set(typewriter, forKey: "typewriter") } }
    @Published var outlineVisible: Bool { didSet { defaults.set(outlineVisible, forKey: "outlineVisible"); refreshBacklinks() } }
    @Published var binderVisible: Bool
    @Published var paletteVisible = false
    /// Set by "Search Binder"; the binder's search field takes it when it can.
    @Published var wantsSearchFocus = false
    /// Set when the binder is shown; the list takes the keyboard focus.
    @Published var wantsTreeFocus = false
    private var enteredFullScreen = false
    let editor = EditorBridge()
    @Published private(set) var backlinks: [URL] = []
    private var backlinkTask: Task<Void, Never>?
    @Published var message: String?
    /// Bumped on every scan, so views that depend on the notes (link styling) refresh.
    @Published private(set) var treeVersion = 0
    private(set) var index = WikiIndex(root: nil)

    let document = DocumentStore()
    private var watcher: FolderWatcher?
    private var scoped: URL?
    private let defaults = UserDefaults.standard

    /// Suffix for the per-window defaults keys; nil is the original, single-window state.
    private let windowKey: String
    /// Set by the window so a second folder can open in a window of its own.
    var newWindow: ((UUID) -> Void)?
    private static var lastExternal: (url: URL, at: Date)?

    init(id: UUID? = nil) {
        windowKey = id.map { ".\($0.uuidString)" } ?? ""
        typewriter = UserDefaults.standard.bool(forKey: "typewriter")
        outlineVisible = UserDefaults.standard.bool(forKey: "outlineVisible")
        binderVisible = UserDefaults.standard.object(forKey: "binderVisible") as? Bool ?? true
        restore()
    }

    /// Distraction-free writing: just the text, in full screen, with everything but the current paragraph dimmed.
    /// Slides the binder away and shrinks the window by the same amount, so the writing pane keeps its width and place.
    func toggleBinder() {
        let width = CGFloat(UserDefaults.standard.object(forKey: "binderWidth") as? Double ?? 272) + 1
        binderVisible.toggle()
        defaults.set(binderVisible, forKey: "binderVisible")
        if binderVisible { wantsTreeFocus = true }
        let delta = binderVisible ? width : -width
        guard let w = NSApp.keyWindow ?? NSApp.windows.first, !w.styleMask.contains(.fullScreen) else { return }
        var f = w.frame
        f.size.width += delta
        f.origin.x -= delta
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.25
            c.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            w.animator().setFrame(f, display: true)
        }
    }

    /// Same for the outline on the right: the window grows or shrinks, the writing pane stays as it is.
    func toggleOutline() {
        outlineVisible.toggle()
        let delta: CGFloat = outlineVisible ? 241 : -241
        guard let w = NSApp.keyWindow ?? NSApp.windows.first, !w.styleMask.contains(.fullScreen) else { return }
        var f = w.frame
        f.size.width += delta
        if let screen = w.screen?.visibleFrame, f.maxX > screen.maxX { f.origin.x = max(screen.minX, screen.maxX - f.width) }
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.25
            c.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            w.animator().setFrame(f, display: true)
        }
    }

    /// Another window on the folder that is open here.
    func openInNewWindow() {
        guard let rootURL, let id = Workspace.stash(rootURL) else { return }
        newWindow?(id)
    }

    /// Brings up the binder if it is hidden, then puts the cursor in its search field.
    func focusSearch() {
        if focus { toggleFocus() }
        if !binderVisible { toggleBinder() }
        wantsSearchFocus = true
        wantsTreeFocus = false
    }

    func toggleFocus() {
        guard focus || document.url != nil else { return }
        focus.toggle()
        mode = .write
        guard let w = NSApp.keyWindow ?? NSApp.windows.first else { return }
        let fullScreen = Preferences.shared.focusFullScreen
        if focus, fullScreen, !w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil); enteredFullScreen = true }
        else if !focus, enteredFullScreen { if w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }; enteredFullScreen = false }
        // in a plain window the traffic lights would sit over the text; Esc brings everything back
        for t in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            w.standardWindowButton(t)?.isHidden = focus && !fullScreen
        }
    }

    // MARK: opening a folder

    static func pickFolder() -> URL? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.prompt = "Open"; p.message = "Choose the folder to write in"
        return p.runModal() == .OK ? p.url : nil
    }

    /// Remembers a folder for a window that does not exist yet; returns the id to open it with.
    static func stash(_ url: URL) -> UUID? {
        let id = UUID()
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return nil }
        UserDefaults.standard.set(data, forKey: "folderBookmark.\(id.uuidString)")
        return id
    }

    func chooseFolder() {
        if let url = Workspace.pickFolder() { openFolder(url) }
    }

    /// Opens in this window when it is empty, otherwise in a new one.
    func openFolder(_ url: URL) {
        if root == nil {
            if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(data, forKey: "folderBookmark" + windowKey)
            }
            open(url)
        } else if let id = Workspace.stash(url) {
            newWindow?(id)
        }
    }

    /// A folder dropped on the Dock icon, or opened with `open -a`.
    func openExternal(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
        // every window is told about the URL; only the first acts
        if let l = Workspace.lastExternal, l.url == url, Date().timeIntervalSince(l.at) < 1 { return }
        Workspace.lastExternal = (url, Date())
        openFolder(url)
    }

    private func restore() {
        let key = "folderBookmark" + windowKey
        guard let data = defaults.data(forKey: key) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: key)
        }
        open(url, restoring: true)
    }

    func open(_ url: URL, restoring: Bool = false) {
        document.saveNow()
        watcher?.stop(); watcher = nil
        scoped?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        scoped = url
        RecentFolders.shared.add(url)
        rootURL = url
        search = ""
        document.open(nil)
        selection = nil
        expanded = Set((defaults.stringArray(forKey: expandedKey(url)) ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) })
        reload()
        watcher = FolderWatcher(url: url) { [weak self] in self?.reload() }
        if restoring, let last = defaults.string(forKey: "lastFile" + windowKey).map({ URL(fileURLWithPath: $0) }), root?.find(last) != nil { select(last) }
        else if let first = root?.files.first { select(first.url) }
    }

    func reload() {
        guard let rootURL else { return }
        root = BinderNode.scan(rootURL)
        index = WikiIndex(root: root)
        treeVersion += 1
        document.checkDisk()
        refreshBacklinks()
        if let s = selection, root?.find(s) == nil { selection = nil }
    }

    // MARK: selection

    func select(_ url: URL) {
        selection = url
        guard let node = root?.find(url) else { return }
        if node.isFolder { toggle(url) }
        else if !node.isDocument { QuickView.shared.show(url) }
        else {
            QuickView.shared.hide()
            document.open(url)
            defaults.set(url.path, forKey: "lastFile" + windowKey)
            refreshBacklinks()
        }
    }

    // MARK: keyboard

    /// Up or down one row. Notes open as you pass them; folders and other files are only highlighted.
    func moveSelection(_ delta: Int) {
        let rows = self.rows
        guard !rows.isEmpty else { return }
        let i = rows.firstIndex { $0.node.url == selection } ?? (delta > 0 ? -1 : rows.count)
        let n = rows[min(rows.count - 1, max(0, i + delta))].node
        if n.isFolder { selection = n.url }
        else if n.isDocument { select(n.url) }
        else {
            // a file the editor cannot open is only highlighted; Space previews it (and a preview already up follows along)
            selection = n.url
            if QuickView.shared.isShowing { QuickView.shared.show(n.url) }
        }
    }

    /// Right opens a folder; on an open one it steps into it.
    func expandSelection() {
        guard search.isEmpty, let s = selection, let node = root?.find(s), node.isFolder else { return }
        if !expanded.contains(s) { expanded.insert(s) } else if !node.children.isEmpty { moveSelection(1) }
    }

    /// Left closes an open folder; otherwise it goes up to the folder this is in.
    func collapseSelection() {
        guard search.isEmpty, let s = selection else { return }
        if expanded.contains(s), root?.find(s)?.isFolder == true { expanded.remove(s); return }
        let parent = s.deletingLastPathComponent()
        if parent.standardizedFileURL != rootURL?.standardizedFileURL, root?.find(parent)?.isFolder == true { selection = parent }
    }

    func focusEditor() {
        guard let tv = editor.textView else { return }
        tv.window?.makeFirstResponder(tv)
    }

    /// Space shows or hides the preview of a file the editor cannot open.
    func toggleQuickLook() {
        guard let s = selection, let n = root?.find(s), !n.isFolder, !n.isDocument else { return }
        if QuickView.shared.isShowing { QuickView.shared.hide() } else { QuickView.shared.show(s) }
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

    func newDocument(in folder: URL? = nil) {
        guard let folder = folder ?? targetFolder else { return }
        let url = Self.uniqueURL(in: folder, base: "Untitled", ext: "md")
        do { try "".write(to: url, atomically: true, encoding: .utf8) } catch { message = error.localizedDescription; return }
        expanded.insert(folder)
        reload()
        select(url)
        renaming = url
    }

    func newFolder(in parent: URL? = nil) {
        guard let parent = parent ?? targetFolder else { return }
        let url = Self.uniqueURL(in: parent, base: "New Folder", ext: nil)
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) } catch { message = error.localizedDescription; return }
        expanded.insert(parent)
        reload()
        selection = url
        renaming = url
    }

    // MARK: dropped files

    func isInside(_ url: URL) -> Bool {
        guard let rootURL else { return false }
        return url.standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path + "/")
    }

    /// Copies a file or folder into `folder` under a name that is free; nil (with a message) when it fails.
    @discardableResult
    func copyIn(_ src: URL, to folder: URL) -> URL? {
        let ext = src.pathExtension
        let dest = Self.uniqueURL(in: folder, base: src.deletingPathExtension().lastPathComponent, ext: ext.isEmpty ? nil : ext)
        do { try FileManager.default.copyItem(at: src, to: dest) } catch { message = error.localizedDescription; return nil }
        return dest
    }

    /// Files dropped on the binder: ones from outside are copied in, ones already in the binder are moved.
    func drop(_ urls: [URL], into folder: URL) {
        for u in urls {
            if isInside(u) { moveItem(u, into: folder) } else { copyIn(u, to: folder) }
        }
        expanded.insert(folder)
        reload()
    }

    /// `rel/path` from a folder to a file, percent-encoded for a Markdown link.
    static func relativePath(from folder: URL, to target: URL) -> String {
        let f = folder.standardizedFileURL.pathComponents, t = target.standardizedFileURL.pathComponents
        var i = 0
        while i < f.count, i < t.count, f[i] == t[i] { i += 1 }
        let parts = Array(repeating: "..", count: f.count - i) + t[i...]
        return parts.map { part in
            part == ".." ? part : (part.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? part)
                .replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
        }.joined(separator: "/")
    }

    /// Files dropped on the editor: copied next to the note (unless already in the binder), then the Markdown that points at them.
    func linkText(forDropped urls: [URL]) -> String {
        guard let note = document.url else { return "" }
        let folder = note.deletingLastPathComponent()
        var out: [String] = []
        for u in urls {
            var target = u
            if !isInside(u) { guard let copied = copyIn(u, to: folder) else { continue }; target = copied }
            let name = target.deletingPathExtension().lastPathComponent
            let isImage = UTType(filenameExtension: target.pathExtension)?.conforms(to: .image) == true
            if isImage { out.append("![\(name)](\(Self.relativePath(from: folder, to: target)))") }
            else if BinderNode.documentExtensions.contains(target.pathExtension.lowercased()) { out.append("[[\(name)]]") }
            else { out.append("[\(target.lastPathComponent)](\(Self.relativePath(from: folder, to: target)))") }
        }
        reload()
        return out.joined(separator: "\n")
    }

    // MARK: rename, move, trash

    func rename(_ url: URL, to newName: String) {
        renaming = nil
        guard let node = root?.find(url) else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        guard !name.isEmpty, name != node.name else { return }
        let parent = url.deletingLastPathComponent()
        let new = node.isFolder ? parent.appendingPathComponent(name, isDirectory: true)
            : node.isDocument ? parent.appendingPathComponent(name).appendingPathExtension(url.pathExtension)
            : parent.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: new.path), new.path.lowercased() != url.path.lowercased() {
            message = "“\(name)” already exists here."; return
        }
        move(url, to: new)
    }

    /// Moves a file or folder into another folder of the binder (drag and drop).
    func moveItem(_ url: URL, into folder: URL) {
        guard let node = root?.find(url), root?.find(folder)?.isFolder == true else { return }
        let from = url.standardizedFileURL.path, to = folder.standardizedFileURL.path
        guard url.deletingLastPathComponent().standardizedFileURL.path != to, to != from, !to.hasPrefix(from + "/") else { return }
        let dest = Self.uniqueURL(in: folder, base: node.name, ext: node.isDocument ? url.pathExtension : nil)
        move(url, to: dest)
        expanded.insert(folder)
    }

    private func move(_ old: URL, to new: URL) {
        document.saveNow()
        do { try FileManager.default.moveItem(at: old, to: new) } catch { message = error.localizedDescription; return }
        let oldPath = old.standardizedFileURL.path, newPath = new.standardizedFileURL.path
        func remap(_ u: URL) -> URL? {
            let p = u.standardizedFileURL.path
            if p == oldPath { return new }
            if p.hasPrefix(oldPath + "/") { return URL(fileURLWithPath: newPath + p.dropFirst(oldPath.count), isDirectory: u.hasDirectoryPath) }
            return nil
        }
        expanded = Set(expanded.map { remap($0) ?? $0 })
        if let s = selection, let r = remap(s) { selection = r }
        if let d = document.url, let r = remap(d) { document.relocate(to: r); defaults.set(r.path, forKey: "lastFile" + windowKey) }
        reload()
    }

    func trash(_ url: URL) {
        let p = url.standardizedFileURL.path
        if let d = document.url?.standardizedFileURL.path, d == p || d.hasPrefix(p + "/") { document.open(nil) }
        do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { message = error.localizedDescription; return }
        if let s = selection?.standardizedFileURL.path, s == p || s.hasPrefix(p + "/") { selection = nil }
        reload()
    }

    // MARK: outline and backlinks

    /// Notes that link to the open one. Reads the notes off the main thread.
    func refreshBacklinks() {
        backlinkTask?.cancel()
        guard outlineVisible, let current = document.url, let root else { backlinks = []; return }
        let files = root.files.map(\.url).filter { $0 != current }
        let index = self.index
        backlinkTask = Task.detached(priority: .utility) { [weak self] in
            var found: [URL] = []
            for f in files {
                if Task.isCancelled { return }
                guard let text = try? String(contentsOf: f, encoding: .utf8), text.contains("[[") else { continue }
                if WikiLink.parse(text).contains(where: { index.resolve($0.link, from: f) == current }) { found.append(f) }
            }
            let result = found
            await MainActor.run { [weak self] in if !Task.isCancelled { self?.backlinks = result } }
        }
    }

    /// Puts the caret on a heading of the open note.
    func jump(to location: Int) {
        let go = { [weak self] in
            guard let tv = self?.editor.textView else { return }
            let r = NSRange(location: min(location, (tv.string as NSString).length), length: 0)
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(r)
            tv.scrollRangeToVisible(r)
            tv.showFindIndicator(for: (tv.string as NSString).paragraphRange(for: r))
        }
        if mode == .view { mode = .write; DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: go) } else { go() }
    }

    // MARK: wiki links

    func wikiResolves(_ target: String) -> Bool { index.resolve(WikiLink(target: target, alias: nil), from: document.url) != nil }

    /// Opens the note a [[link]] points at, or offers to make it.
    func openWiki(_ target: String) {
        let link = WikiLink(target: target, alias: nil)
        if let url = index.resolve(link, from: document.url) { reveal(url); select(url); return }
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
