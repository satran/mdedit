import AppKit
import SwiftUI

/// What the find & replace panel shows and does, for "This file" and "Folder".
final class FindModel: ObservableObject {
    enum Scope { case file, folder }
    enum Area: String { case project, noteFolder }
    enum Field { case find, replace }

    struct Key: Hashable { let url: URL; let start: Int }

    weak var ws: Workspace?

    @Published var scope: Scope = .file { didSet { if scope != oldValue { note = nil; refresh() } } }
    @Published var area: Area = .project { didSet { if area != oldValue { refresh() } } }
    @Published var query = "" { didSet { if query != oldValue { note = nil; refresh() } } }
    @Published var replacement = "" { didSet { if replacement != oldValue { refresh() } } }
    @Published var options = FindOptions() { didSet { if options != oldValue { note = nil; refresh() } } }
    /// Which text field the keyboard should land in; the panel takes the request and clears it.
    @Published var focus: Field?

    @Published private(set) var matches: [FindMatch] = []
    @Published var current = 0
    @Published private(set) var truncated = false
    @Published private(set) var groups: [FileHits] = []
    @Published var unchecked: Set<Key> = []
    @Published var expanded: Set<URL> = []
    @Published private(set) var problem: String?
    @Published private(set) var note: String?
    @Published private(set) var busy = false
    @Published private(set) var canUndo = false

    private var task: Task<Void, Never>?
    private var backups: [FolderFind.Backup] = []
    private var undoRegistered = false

    // MARK: searching

    private func compiled() -> FindEngine.Compiled? {
        do { problem = nil; return try FindEngine.compile(query, replacement: replacement, options: options) }
        catch FindEngine.FindError.invalid(let m) { problem = m; return nil }
        catch { return nil }
    }

    func refresh() {
        task?.cancel()
        guard let ws, ws.findVisible else { return }
        guard let c = compiled() else { matches = []; groups = []; truncated = false; busy = false; highlight(); return }
        switch scope {
        case .file:
            let r = FindEngine.search(ws.document.text, c)
            matches = r.matches; truncated = r.truncated; groups = []; busy = false
            if current >= matches.count { current = max(0, matches.count - 1) }
            highlight(); reveal()
        case .folder:
            matches = []; highlight()
            ws.document.saveNow()
            let files = searchFiles(ws)
            busy = true
            let wasChecked = unchecked
            task = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                if Task.isCancelled { return }
                let found = await Task.detached(priority: .userInitiated) { FolderFind.search(files, c, cancelled: { Task.isCancelled }) }.value
                guard !Task.isCancelled, let self else { return }
                self.groups = found
                self.truncated = found.contains { $0.truncated } || found.reduce(0) { $0 + $1.matches.count } >= FindEngine.maxMatchesTotal
                self.unchecked = wasChecked.filter { k in found.contains { $0.url == k.url && $0.matches.contains { $0.range.location == k.start } } }
                self.expanded = self.expanded.isEmpty ? Set(found.prefix(2).map(\.url)) : self.expanded
                self.busy = false
            }
        }
    }

    private func searchFiles(_ ws: Workspace) -> [(url: URL, folder: String)] {
        guard let root = ws.root, let rootURL = ws.rootURL else { return [] }
        let top = rootURL.standardizedFileURL.path
        var scopeDir: String?
        if area == .noteFolder, let u = ws.document.url { scopeDir = u.deletingLastPathComponent().standardizedFileURL.path }
        return root.files.compactMap { n in
            let dir = n.url.deletingLastPathComponent().standardizedFileURL.path
            if let s = scopeDir, dir != s, !dir.hasPrefix(s + "/") { return nil }
            let rel = dir == top ? "" : String(dir.dropFirst(top.count + 1))
            return (n.url, rel)
        }
    }

    // MARK: this file

    func next(_ step: Int = 1) {
        guard !matches.isEmpty else { return }
        current = (current + step + matches.count) % matches.count
        highlight(); reveal()
    }

    private func reveal() {
        guard scope == .file, matches.indices.contains(current), let tv = ws?.editor.textView, ws?.mode == .write else { return }
        tv.scrollRangeToVisible(matches[current].range)
    }

    func highlight() {
        guard let tv = ws?.editor.textView else { return }
        let show = ws?.findVisible == true && scope == .file && ws?.mode == .write
        tv.setFindHighlights(show ? matches.map(\.range) : [], current: show && matches.indices.contains(current) ? current : nil)
    }

    /// Runs `body` with the editor, switching to Write first when the note is being viewed.
    private func withEditor(_ body: @escaping (EditorTextView) -> Void) {
        guard let ws else { return }
        if ws.mode == .write, let tv = ws.editor.textView, tv.window != nil { body(tv); return }
        ws.mode = .write
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak ws] in if let tv = ws?.editor.textView { body(tv) } }
    }

    func replaceCurrent() {
        guard scope == .file, matches.indices.contains(current), let c = compiled() else { return }
        let at = matches[current].range.location
        withEditor { [weak self] tv in
            guard let self else { return }
            // search the editor's own text again: it is what gets changed
            guard let m = FindEngine.search(tv.string, c).matches.first(where: { $0.range.location == at }) else { self.refresh(); return }
            tv.insertOutput(m.replacement, at: m.range)
            self.refresh()
        }
    }

    func replaceAllInFile() {
        guard scope == .file, !matches.isEmpty, let c = compiled() else { return }
        withEditor { [weak self] tv in
            guard let self, let done = FindEngine.replace(in: tv.string, c) else { self?.refresh(); return }
            tv.insertOutput(done.text, at: NSRange(location: 0, length: (tv.string as NSString).length))
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            self.note = "Replaced \(done.count) \(done.count == 1 ? "match" : "matches")"
            self.refresh()
        }
    }

    // MARK: folder

    var selectedCount: Int { groups.reduce(0) { n, g in n + g.matches.filter { isOn(g.url, $0) }.count } }
    var totalCount: Int { groups.reduce(0) { $0 + $1.matches.count } }
    var selectedFiles: Int { groups.filter { g in g.matches.contains { isOn(g.url, $0) } }.count }

    func isOn(_ url: URL, _ m: FindMatch) -> Bool { !unchecked.contains(Key(url: url, start: m.range.location)) }
    func toggle(_ url: URL, _ m: FindMatch) {
        let k = Key(url: url, start: m.range.location)
        if unchecked.contains(k) { unchecked.remove(k) } else { unchecked.insert(k) }
    }
    /// A file's box: all on, unless all are on already.
    func toggleFile(_ g: FileHits) {
        let keys = g.matches.map { Key(url: g.url, start: $0.range.location) }
        if keys.allSatisfy({ !unchecked.contains($0) }) { unchecked.formUnion(keys) } else { unchecked.subtract(keys) }
    }
    func fileState(_ g: FileHits) -> Int {   // 0 none, 1 some, 2 all
        let on = g.matches.filter { isOn(g.url, $0) }.count
        return on == 0 ? 0 : on == g.matches.count ? 2 : 1
    }
    var allExpanded: Bool { !groups.isEmpty && groups.allSatisfy { expanded.contains($0.url) } }
    func toggleAllExpanded() { expanded = allExpanded ? [] : Set(groups.map(\.url)) }

    func open(_ url: URL, _ m: FindMatch) {
        guard let ws else { return }
        ws.reveal(url)
        if ws.document.url?.standardizedFileURL != url.standardizedFileURL { ws.select(url) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { ws.jump(to: m.range.location, length: m.range.length) }
    }

    func replaceSelected() {
        guard scope == .folder, let ws, let c = compiled() else { return }
        ws.document.saveNow()
        var others: [(url: URL, starts: Set<Int>)] = []
        var mine: Set<Int>?
        let open = ws.document.url?.standardizedFileURL
        for g in groups {
            let starts = Set(g.matches.filter { isOn(g.url, $0) }.map(\.range.location))
            if g.url.standardizedFileURL == open { mine = starts } else { others.append((g.url, starts)) }
        }
        let report = FolderFind.replace(others, c)
        var replaced = report.replaced, files = report.files
        var skipped = report.skipped
        var group: [FolderFind.Backup] = report.backups
        if let mine, !mine.isEmpty {
            if let tv = ws.editor.textView, ws.mode == .write, let done = FindEngine.replace(in: tv.string, c, only: mine) {
                let um = tv.undoManager
                um?.beginUndoGrouping()
                tv.insertOutput(done.text, at: NSRange(location: 0, length: (tv.string as NSString).length))
                tv.setSelectedRange(NSRange(location: 0, length: 0))
                replaced += done.count; files += 1
                register(group, in: um)
                um?.endUndoGrouping()
                group = []
            } else {
                let r = FolderFind.replace([(ws.document.url!, mine)], c)
                replaced += r.replaced; files += r.files; skipped += r.skipped; group += r.backups
            }
        }
        if !group.isEmpty { register(group, in: ws.editor.textView?.undoManager) }
        backups = group
        canUndo = replaced > 0
        note = "Replaced \(replaced) in \(files) \(files == 1 ? "file" : "files")" + (skipped.isEmpty ? "" : " · skipped: " + skipped.joined(separator: "; "))
        ws.reload()
        refresh()
    }

    private func register(_ group: [FolderFind.Backup], in um: UndoManager?) {
        guard let um, !group.isEmpty else { undoRegistered = false; return }
        undoRegistered = true
        um.registerUndo(withTarget: self) { m in m.restore(group) }
        um.setActionName("Replace in Folder")
    }

    private func restore(_ group: [FolderFind.Backup]) {
        let r = FolderFind.restore(group)
        if let um = ws?.editor.textView?.undoManager, !r.done.isEmpty { um.registerUndo(withTarget: self) { m in m.restore(r.done) } }
        note = r.skipped.isEmpty ? "Undone" : "Undone, skipped: " + r.skipped.joined(separator: "; ")
        canUndo = false
        ws?.reload(); refresh()
    }

    func undoLast() {
        if undoRegistered, let um = ws?.editor.textView?.undoManager, um.canUndo { um.undo(); return }
        guard !backups.isEmpty else { return }
        let b = backups; backups = []
        restore(b)
    }
}

extension Workspace {
    var rightPanelWidth: CGFloat { findVisible ? 361 : outlineVisible ? 241 : 0 }

    /// ⌘F, ⌥⌘F, ⇧⌘F: opens the panel in the scope, with the keyboard in a field. The window grows to make room, as for the outline.
    func showFind(_ scope: FindModel.Scope, field: FindModel.Field = .find) {
        if focus { toggleFocus() }
        // the selected text becomes the query, as in other editors
        if let tv = editor.textView, tv.selectedRange().length > 0, tv.selectedRange().length < 200 {
            let s = (tv.string as NSString).substring(with: tv.selectedRange())
            if !s.contains("\n") { find.query = s }
        }
        let before = rightPanelWidth
        findVisible = true
        find.scope = showingHTML ? .folder : scope          // a page is not edited here
        find.focus = field
        find.refresh()
        resizeWindow(by: rightPanelWidth - before)
    }

    func closeFind() {
        let before = rightPanelWidth
        findVisible = false
        find.refresh()
        find.highlight()
        resizeWindow(by: rightPanelWidth - before)
        if mode == .write { focusEditor() }
    }

    func toggleFindPanel() { findVisible ? closeFind() : showFind(.file) }

    func findNext(_ step: Int = 1) {
        guard findVisible, find.scope == .file else { showFind(.file); return }
        find.next(step)
    }

    func resizeWindow(by delta: CGFloat) {
        guard delta != 0, let w = NSApp.keyWindow ?? NSApp.windows.first, !w.styleMask.contains(.fullScreen) else { return }
        var f = w.frame
        f.size.width += delta
        if let screen = w.screen?.visibleFrame, f.maxX > screen.maxX { f.origin.x = max(screen.minX, screen.maxX - f.width) }
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.25
            c.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            w.animator().setFrame(f, display: true)
        }
    }
}

extension EditorTextView {
    /// Pale marks on every match and a stronger one on the current. They are drawn over the text, never written into it.
    func setFindHighlights(_ ranges: [NSRange], current: Int?) {
        guard let lm = layoutManager else { return }
        let n = (string as NSString).length
        let all = NSRange(location: 0, length: n)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
        for (i, r) in ranges.enumerated() where NSMaxRange(r) <= n {
            lm.addTemporaryAttribute(.backgroundColor, value: i == current ? Palette.findCurrent : Palette.findMatch, forCharacterRange: r)
        }
    }
}
