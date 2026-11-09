import AppKit

/// Open notes as tabs. A window has one open document; a tab is a note kept in the binder's Open section, so switching
/// is just opening that note. Every note that opens in the app becomes a tab, and closing a tab never touches the file.
extension Workspace {
    static func isSame(_ a: URL, _ b: URL) -> Bool { a.standardizedFileURL.path == b.standardizedFileURL.path }
    /// `url` is the folder or file at `path`, or inside it.
    static func isSame(_ url: URL, orInside path: String) -> Bool {
        let p = url.standardizedFileURL.path
        return p == path || p.hasPrefix(path + "/")
    }

    var activeTab: URL? { document.url.flatMap { u in openTabs.first { Self.isSame($0, u) } } }
    func isOpenTab(_ url: URL) -> Bool { openTabs.contains { Self.isSame($0, url) } }

    func addTab(_ url: URL) {
        guard !isOpenTab(url) else { return }
        openTabs.append(url)
    }

    /// Forgets tabs whose note is gone from the folder (deleted or renamed outside the app).
    func pruneTabs() {
        guard let root else { return }
        let kept = openTabs.filter { root.find($0) != nil }
        if kept.count != openTabs.count { openTabs = kept }
    }

    /// Closes one tab. When it is the open note, the neighbour to its right takes over (the one to its left if it was last);
    /// with no tab left the editor is empty.
    func closeTab(_ url: URL) {
        guard let i = openTabs.firstIndex(where: { Self.isSame($0, url) }) else { return }
        let wasOpen = document.url.map { Self.isSame($0, url) } ?? false
        remember(openTabs[i])
        openTabs.remove(at: i)
        guard wasOpen else { return }
        document.saveNow()
        if let next = openTabs.indices.contains(i) ? openTabs[i] : openTabs.last {
            reveal(next); select(next, recording: false)
        } else {
            document.open(nil)
            selection = nil
            forgetLastFile()
        }
    }

    func closeOtherTabs(than url: URL) {
        guard isOpenTab(url) else { return }
        for u in openTabs where !Self.isSame(u, url) { closeTab(u) }
        if !(document.url.map { Self.isSame($0, url) } ?? false) { select(url, recording: false) }
    }

    func closeTabs(below url: URL) {
        guard let i = openTabs.firstIndex(where: { Self.isSame($0, url) }) else { return }
        for u in openTabs[(i + 1)...] { closeTab(u) }
    }

    /// ⌘W: closes the open note's tab; on the last tab (or with none) it closes the window, as ⌘W always has.
    func closeTabOrWindow() {
        if openTabs.count > 1, let u = activeTab { closeTab(u); focusEditor() }
        else { (hostWindow ?? NSApp.keyWindow)?.performClose(nil) }
    }

    /// ⇧⌘[ and ⇧⌘]: the tab before or after the open one, wrapping around.
    func switchTab(by step: Int) {
        guard openTabs.count > 1 else { return }
        let i = activeTab.flatMap { a in openTabs.firstIndex { Self.isSame($0, a) } } ?? (step > 0 ? -1 : 0)
        let next = openTabs[((i + step) % openTabs.count + openTabs.count) % openTabs.count]
        reveal(next); select(next)
        focusEditor()
    }

    /// ⌥⌘T: brings back the tab closed last, skipping notes that are gone.
    func reopenClosedTab() {
        while let u = closedTabs.popLast() {
            guard root?.find(u)?.opensInApp == true else { continue }
            reveal(u); select(u)
            focusEditor()
            return
        }
    }

    /// Drag to reorder: `url` goes where `target` is (the end, with no target).
    func moveTab(_ url: URL, before target: URL?) {
        guard let from = openTabs.firstIndex(where: { Self.isSame($0, url) }) else { return }
        if let target, Self.isSame(target, url) { return }
        let moved = openTabs.remove(at: from)
        let to = target.flatMap { t in openTabs.firstIndex { Self.isSame($0, t) } } ?? openTabs.count
        openTabs.insert(moved, at: to)
    }

    /// The name shown on a tab.
    func tabTitle(_ url: URL) -> String { root?.find(url)?.label ?? url.deletingPathExtension().lastPathComponent }

    /// A short tag for a tab whose title another tab shares: the least of its folder path that tells the two apart
    /// ("X", or "A/Notes" against "B/Notes"), or the extension when they sit in the same folder and have the same icon
    /// (Plan.md and Plan.txt). Nil when the title is unique or the icons already differ.
    func tabFolder(_ url: URL) -> String? {
        let title = tabTitle(url)
        // a twin with another icon (index.html and index.json) is told apart by the icon already
        let icon = root?.find(url)?.symbol
        let twins = openTabs.filter { !Self.isSame($0, url) && tabTitle($0) == title && root?.find($0)?.symbol == icon }
        guard !twins.isEmpty else { return nil }
        func parents(_ u: URL) -> [String] { u.deletingLastPathComponent().standardizedFileURL.pathComponents.filter { $0 != "/" } }
        let mine = parents(url)
        let others = twins.map(parents)
        if others.contains(mine) { return url.pathExtension.isEmpty ? nil : "." + url.pathExtension }
        for depth in 1...max(1, mine.count) {
            let tail = mine.suffix(depth)
            if !others.contains(where: { $0.suffix(depth) == tail }) { return tail.joined(separator: "/") }
        }
        return mine.joined(separator: "/")
    }

    private func remember(_ url: URL) {
        closedTabs.removeAll { Self.isSame($0, url) }
        closedTabs.append(url)
        if closedTabs.count > 20 { closedTabs.removeFirst(closedTabs.count - 20) }
    }
}
