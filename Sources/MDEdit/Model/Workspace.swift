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
    /// Notes opened before this one, oldest first; Back walks it from the end.
    @Published private(set) var visited: [URL] = []
    /// Notes Back stepped away from, nearest last; Forward walks it. Opening any other note empties it.
    @Published private(set) var ahead: [URL] = []
    @Published var search = ""
    /// Going back to Write gives the caret back to the note, so typing can start at once.
    @Published var mode: Mode = .write {
        didSet {
            // a web page has no editor
            if mode == .write, showingHTML { mode = .view; return }
            if mode == .write, oldValue == .view { focusEditor() }
        }
    }
    /// The open file is an HTML page: shown in the preview only.
    var showingHTML: Bool { document.url.map { BinderNode.htmlExtensions.contains($0.pathExtension.lowercased()) } ?? false }
    private var modeBeforeHTML: Mode?
    /// A page forces the preview; the note after it gets back the mode the reader was in.
    private func syncModeToFile() {
        if showingHTML {
            if modeBeforeHTML == nil { modeBeforeHTML = mode }
            mode = .view
            if findVisible, find.scope == .file { find.scope = .folder; find.refresh() }
        }
        else if let m = modeBeforeHTML { modeBeforeHTML = nil; mode = m }
    }
    @Published var focus = false
    /// The row being renamed in the binder.
    @Published var renaming: URL?
    @Published var typewriter: Bool { didSet { defaults.set(typewriter, forKey: "typewriter") } }
    /// The right-hand panel: the outline or find & replace, one at a time; nil is closed.
    @Published var panel: RightPanel? {
        didSet {
            // Run is a visit: the toolbar button and the next launch never open on it
            if let p = panel, p != .run { lastPanel = p; defaults.set(p.rawValue, forKey: "rightPanelTab") }
            defaults.set(panel != nil && panel != .run, forKey: "rightPanelOpen")
            if (oldValue == .outline) != (panel == .outline) { refreshBacklinks() }
        }
    }
    /// The tab the toolbar button opens, and where Esc goes back to from Find.
    var lastPanel: RightPanel = .outline
    /// Where Esc goes back to from the find or run tab: the outline, or closed.
    var panelBefore: RightPanel?
    /// Width of the panel's content in points; the person can drag it. The same for both tabs.
    @Published var panelWidth: CGFloat { didSet { defaults.set(Double(panelWidth), forKey: "rightPanelWidth") } }
    static let panelWidthRange: ClosedRange<CGFloat> = 280...560
    var outlineVisible: Bool {
        get { panel == .outline }
        set { if newValue { panel = .outline } else if panel == .outline { panel = nil } }
    }
    var findVisible: Bool {
        get { panel == .find }
        set { if newValue { panel = .find } else if panel == .find { panel = nil } }
    }
    @Published var binderVisible: Bool
    // While a side panel slides in or out, only the window changes size: the writing column keeps this width and place,
    // a panel on its way out stays until the window has shrunk past it, and the minimum width waits for the end.
    @Published var pinnedMainWidth: CGFloat?
    @Published var pinnedToTrailingEdge = false
    @Published var holdBinder = false
    @Published var heldPanel: RightPanel?
    @Published var minWidthOverride: CGFloat?
    /// The window this workspace is shown in, once its view is on screen.
    weak var hostWindow: NSWindow?
    var slideGeneration = 0
    var slideTarget: NSRect?
    let find = FindModel()
    /// Closing the palette gives the keyboard back to the note, so the caret is not left without a home.
    @Published var paletteVisible = false { didSet { if oldValue, !paletteVisible, mode == .write { DispatchQueue.main.async { [weak self] in self?.focusEditor() } } } }
    /// Set by "Search Binder"; the binder's search field takes it when it can.
    @Published var wantsSearchFocus = false
    /// Set when the binder is shown; the list takes the keyboard focus.
    @Published var wantsTreeFocus = false
    private var enteredFullScreen = false
    // Shell commands (⌘R); the work is in Workspace+Shell.swift
    /// The run tab is showing.
    var shellBarVisible: Bool {
        get { panel == .run }
        set { if newValue { panel = .run } else { closeRun() } }
    }
    /// What the Run tab suggests: the saved scripts of the folder, and the commands run there before (oldest first).
    @Published var shellScripts: [String] = []
    @Published var shellRecents: [String] = []
    /// Counts ⌘R presses, so the command field takes the keyboard again when the tab is already open.
    @Published var shellFocusTick = 0
    @Published var shellLog: ShellLog?
    @Published var shellJob: ShellJob?
    @Published var shellDestination: ShellDestination { didSet { defaults.set(shellDestination.rawValue, forKey: "shellDestination") } }
    /// Asks the person a yes/no question (title, detail, button). The tests replace it.
    var shellConfirm: (String, String, String) -> Bool = ShellPrompts.confirm
    let editor = EditorBridge()
    @Published private(set) var backlinks: [URL] = []
    private var backlinkTask: Task<Void, Never>?
    private var backlinkTarget: URL?
    private var backlinkRunning = false
    private var backlinkAgain = false
    private var backlinkGeneration = 0
    @Published var message: String?
    /// Bumped on every scan, so views that depend on the notes (link styling) refresh.
    @Published private(set) var treeVersion = 0
    private(set) var index = WikiIndex(root: nil)

    let document = DocumentStore()
    private var watcher: FolderWatcher?
    private var scoped: URL?
    let defaults: UserDefaults
    private let recents: RecentFolders

    /// Suffix for the per-window defaults keys; nil is the original, single-window state.
    private let windowKey: String
    /// Set by the window so a second folder can open in a window of its own.
    var newWindow: ((UUID) -> Void)?
    private static var lastExternal: (url: URL, at: Date)?

    deinit { shellJob?.cancel() }

    init(id: UUID? = nil, defaults: UserDefaults = AppEnvironment.defaults, recents: RecentFolders = .shared) {
        self.defaults = defaults
        self.recents = recents
        windowKey = id.map { ".\($0.uuidString)" } ?? ""
        typewriter = defaults.bool(forKey: "typewriter")
        let tab = defaults.string(forKey: "rightPanelTab").flatMap(RightPanel.init(rawValue:)) ?? .outline
        let open = defaults.object(forKey: "rightPanelOpen") as? Bool ?? defaults.bool(forKey: "outlineVisible")
        lastPanel = tab
        panel = open && tab == .outline ? .outline : nil      // find does not come back open: its fields start empty
        panelWidth = min(Self.panelWidthRange.upperBound, max(Self.panelWidthRange.lowerBound, CGFloat(defaults.object(forKey: "rightPanelWidth") as? Double ?? 360)))
        binderVisible = defaults.object(forKey: "binderVisible") as? Bool ?? true
        shellDestination = defaults.string(forKey: "shellDestination").flatMap(ShellDestination.init(rawValue:)) ?? .insert
        find.ws = self
        restore()
    }

    /// Distraction-free writing: just the text, in full screen, with everything but the current paragraph dimmed.
    /// Slides the binder away and shrinks the window by the same amount, so the writing pane keeps its width and place.
    func toggleBinder() {
        slidePanel(.left) {
            binderVisible.toggle()
            defaults.set(binderVisible, forKey: "binderVisible")
            if binderVisible { wantsTreeFocus = true }
        }
    }

    /// ⌥⌘O: the outline on the right. From the find tab it switches to the outline; on the outline it closes the panel.
    func toggleOutline() {
        if panel == .outline { closePanel() } else { openPanel(.outline) }
    }

    /// The toolbar button: opens the panel on the tab used last, or closes it.
    func togglePanel() {
        if panel != nil { closePanel() } else { openPanel(lastPanel) }
    }

    /// Another window on the folder that is open here.
    func openInNewWindow() {
        guard let rootURL, let id = Workspace.stash(rootURL, defaults: defaults) else { return }
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
        guard focus || (document.url != nil && !showingHTML) else { return }
        focus.toggle()
        mode = .write
        focusEditor()                       // the editor view is replaced; its caret must come back
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
    static func stash(_ url: URL, defaults: UserDefaults = AppEnvironment.defaults) -> UUID? {
        // a bookmark can only be made while access to the folder is open (it is not for a folder that came from a saved bookmark)
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return nil }
        return stash(bookmark: data, defaults: defaults)
    }

    /// Hands a saved bookmark to a window that does not exist yet.
    static func stash(bookmark data: Data, defaults: UserDefaults = AppEnvironment.defaults) -> UUID {
        let id = UUID()
        defaults.set(data, forKey: "folderBookmark.\(id.uuidString)")
        return id
    }

    func chooseFolder() {
        if let url = Workspace.pickFolder() { openFolder(url) }
    }

    /// Opens in this window when it is empty, otherwise in a new one.
    func openFolder(_ url: URL) {
        if root == nil {
            let opened = url.startAccessingSecurityScopedResource()
            if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(data, forKey: "folderBookmark" + windowKey)
            }
            if opened { url.stopAccessingSecurityScopedResource() }
            open(url)
        } else if let id = Workspace.stash(url, defaults: defaults) {
            newWindow?(id)
        }
    }

    /// File > Open Recent: here when this window is empty, otherwise in a window of its own. It reuses the saved bookmark,
    /// so nothing has to be made from a folder the app has not opened yet in this run.
    func openRecent(_ item: RecentFolders.Item) {
        guard let url = recents.resolve(item) else { message = "“\(item.name)” is no longer there, so it was taken off the list."; return }
        if root == nil {
            defaults.set(item.bookmark, forKey: "folderBookmark" + windowKey)
            open(url)
        } else {
            newWindow?(Workspace.stash(bookmark: item.bookmark, defaults: defaults))
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
        recents.add(url)
        rootURL = url
        search = ""
        document.open(nil)
        selection = nil
        visited = []; ahead = []
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

    /// Makes `.mdedit/preview.css` (with a starter, if there is none) and shows it in Finder, for the person to edit.
    @discardableResult
    func editPreviewStylesheet() -> URL? {
        guard let rootURL, let f = CustomCSS.createStarter(rootURL) else { message = "The folder does not allow a stylesheet here."; return nil }
        if !AppEnvironment.isTesting { NSWorkspace.shared.activateFileViewerSelecting([f]) }
        return f
    }

    func select(_ url: URL) { select(url, recording: true) }

    /// Back to the note that was open before this one. Notes that were deleted or renamed since are skipped.
    func goBack() {
        while let last = visited.popLast() {
            guard root?.find(last)?.opensInApp == true else { continue }
            if let here = document.url { ahead.append(here) }
            reveal(last); select(last, recording: false)
            return
        }
    }

    /// Undoes a Back: on to the note Back came from.
    func goForward() {
        while let next = ahead.popLast() {
            guard root?.find(next)?.opensInApp == true else { continue }
            if let here = document.url { visited.append(here) }
            reveal(next); select(next, recording: false)
            return
        }
    }

    private func select(_ url: URL, recording: Bool) {
        selection = url
        guard let node = root?.find(url) else { return }
        if node.isFolder { toggle(url) }
        else if !node.opensInApp { QuickView.shared.show(url) }
        else {
            QuickView.shared.hide()
            if recording, document.url?.standardizedFileURL != url.standardizedFileURL { ahead = [] }
            if recording, let from = document.url, from.standardizedFileURL != url.standardizedFileURL, visited.last != from {
                visited.append(from)
                if visited.count > 100 { visited.removeFirst(visited.count - 100) }
            }
            document.open(url)
            syncModeToFile()
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
        else if n.opensInApp { select(n.url) }
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

    /// Puts the caret in the note so typing can start at once, also when the editor is about to be replaced (Write/View,
    /// distraction free): the request waits for the new editor.
    func focusEditor() { editor.requestFocus() }

    /// Space shows or hides the preview of a file the editor cannot open.
    func toggleQuickLook() {
        guard let s = selection, let n = root?.find(s), !n.isFolder, !n.opensInApp else { return }
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
        let from = src.standardizedFileURL.path, into = folder.standardizedFileURL.path
        if into == from || into.hasPrefix(from + "/") { message = "A folder cannot be copied into itself."; return nil }
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

    /// File names go into Markdown link text; brackets and backslashes would end it early.
    static func escapeLinkText(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
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
            let label = Self.escapeLinkText(name)
            let isImage = UTType(filenameExtension: target.pathExtension)?.conforms(to: .image) == true
            if isImage { out.append("![\(label)](\(Self.relativePath(from: folder, to: target)))") }
            else if BinderNode.documentExtensions.contains(target.pathExtension.lowercased()), !name.contains(where: { "[]|#".contains($0) }) { out.append("[[\(name)]]") }
            else { out.append("[\(Self.escapeLinkText(target.lastPathComponent))](\(Self.relativePath(from: folder, to: target)))") }
        }
        reload()
        return out.joined(separator: "\n")
    }

    // MARK: rename, move, trash

    /// A name that is safe as a file name: no path separators or control characters, not "." or "..", and short enough.
    static func cleanName(_ raw: String) -> String {
        var s = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != "\u{0}" })
        s = s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.utf8.count > 200 { s.removeLast() }
        return s.allSatisfy({ $0 == "." }) ? "" : s
    }

    func rename(_ url: URL, to newName: String) {
        renaming = nil
        guard let node = root?.find(url) else { return }
        let name = Self.cleanName(newName)
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
        guard outlineVisible, let current = document.url, let root else {
            backlinkTask?.cancel(); backlinkRunning = false; backlinkGeneration += 1; backlinks = []; return
        }
        // a scan of this same note is under way: let it finish and run once more, instead of restarting it on every change in the folder
        if backlinkRunning, backlinkTarget == current { backlinkAgain = true; return }
        backlinkTask?.cancel()
        backlinkGeneration += 1
        let generation = backlinkGeneration
        backlinkTarget = current; backlinkRunning = true; backlinkAgain = false
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
            await MainActor.run { [weak self] in
                guard let self, self.backlinkGeneration == generation else { return }
                self.backlinks = result
                self.backlinkRunning = false
                if self.backlinkAgain { self.backlinkAgain = false; self.refreshBacklinks() }
            }
        }
    }

    /// Puts the caret on a heading of the open note.
    func jump(to location: Int, length: Int = 0) {
        let go = { [weak self] in
            guard let tv = self?.editor.textView else { return }
            let n = (tv.string as NSString).length
            let r = NSRange(location: min(location, n), length: min(length, max(0, n - location)))
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
        let name = Self.cleanName(link.note.split(separator: "/").last.map(String.init) ?? link.note)
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
