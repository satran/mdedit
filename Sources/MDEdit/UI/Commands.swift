import SwiftUI

/// One thing the app can do. The menu bar and the command palette are both built from the same list.
struct Cmd: Identifiable {
    enum Place { case file, fileMore, tabs, view, find, format, paletteOnly }
    let id: String
    let title: String
    var place: Place = .paletteOnly
    var key: KeyEquivalent?
    var modifiers: EventModifiers = .command
    var enabled = true
    var dividerBefore = false
    let run: () -> Void

    /// "⇧⌘P"
    var shortcut: String {
        guard let key else { return "" }
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + String(key.character).uppercased()
    }
}

@MainActor
func makeCommands(ws: Workspace?, prefs: Preferences, recents: RecentFolders, newWindow: @escaping (UUID) -> Void) -> [Cmd] {
    let hasRoot = ws?.root != nil, hasDoc = ws?.document.url != nil
    // a web page is only shown: no editing, no export, nothing that works on Markdown
    let isPage = ws?.isCodeFile == true, hasNote = hasDoc && !isPage
    func docName(_ w: Workspace) -> String { w.document.url?.deletingPathExtension().lastPathComponent ?? "" }

    var c: [Cmd] = [
        Cmd(id: "open", title: "Open Folder…", place: .file, key: "o") {
            if let ws { ws.chooseFolder() }
            else if let url = Workspace.pickFolder(), let id = Workspace.stash(url, defaults: AppEnvironment.defaults) { newWindow(id) }
        },
        Cmd(id: "new-window", title: "New Window", place: .file, key: "n", modifiers: [.command, .option]) { newWindow(UUID()) },
        Cmd(id: "template-hosts", title: "Trusted Addresses for Templates…", enabled: hasRoot) { ws?.editTrustedAddresses() },
        Cmd(id: "same-folder", title: "New Window with This Folder", place: .file, enabled: hasRoot) { ws?.openInNewWindow() },
        Cmd(id: "new-doc", title: "New Document", place: .file, key: "n", enabled: hasRoot, dividerBefore: true) { ws?.newDocument() },
        Cmd(id: "go-to-file", title: "Go to File…", place: .file, key: "o", modifiers: [.command, .shift], enabled: hasRoot) { ws?.paletteVisible = false; ws?.finderVisible = true },
        Cmd(id: "new-folder", title: "New Folder", place: .file, key: "n", modifiers: [.command, .option, .shift], enabled: hasRoot) { ws?.newFolder() },

        Cmd(id: "rename", title: "Rename", place: .fileMore, key: "r", modifiers: [.command, .option], enabled: ws?.selection != nil) { if let s = ws?.selection { ws?.renaming = s } },
        Cmd(id: "trash", title: "Move to Trash", place: .fileMore, enabled: ws?.selection != nil) { if let s = ws?.selection { ws?.trash(s) } },
        Cmd(id: "export-html", title: "Export as HTML…", place: .fileMore, enabled: hasNote, dividerBefore: true) {
            if let ws { Exporter.shared.saveHTML(markdown: ws.document.text, name: docName(ws), prefs: prefs) }
        },
        Cmd(id: "copy-md", title: "Copy as Markdown", place: .fileMore, enabled: hasNote) { if let ws { Exporter.shared.copyMarkdown(ws.document.text) } },
        Cmd(id: "print", title: "Print…", place: .fileMore, key: "p", enabled: hasNote) {
            if let ws { Exporter.shared.print(markdown: ws.document.text, name: docName(ws), prefs: prefs) }
        },

        Cmd(id: "close-tab", title: "Close Tab", place: .tabs, key: "w") { if let ws { ws.closeTabOrWindow() } else { NSApp.keyWindow?.performClose(nil) } },
        Cmd(id: "reopen-tab", title: "Reopen Closed Tab", place: .tabs, key: "t", modifiers: [.command, .option], enabled: ws?.closedTabs.isEmpty == false) { ws?.reopenClosedTab() },
        Cmd(id: "next-tab", title: "Show Next Tab", place: .view, key: "]", modifiers: [.command, .shift], enabled: (ws?.openTabs.count ?? 0) > 1) { ws?.switchTab(by: 1) },
        Cmd(id: "previous-tab", title: "Show Previous Tab", place: .view, key: "[", modifiers: [.command, .shift], enabled: (ws?.openTabs.count ?? 0) > 1) { ws?.switchTab(by: -1) },
        Cmd(id: "back", title: "Back to Previous Note", place: .view, key: "[", enabled: ws?.visited.isEmpty == false) { ws?.goBack() },
        Cmd(id: "forward", title: "Forward to Next Note", place: .view, key: "]", enabled: ws?.ahead.isEmpty == false) { ws?.goForward() },
        Cmd(id: "find", title: "Find…", place: .find, key: "f", enabled: hasDoc) { ws?.showFind(.file) },
        Cmd(id: "replace", title: "Find and Replace…", place: .find, key: "f", modifiers: [.command, .option], enabled: hasDoc) { ws?.showFind(.file, field: .replace) },
        Cmd(id: "find-folder", title: "Find in Folder…", place: .find, key: "f", modifiers: [.command, .shift], enabled: hasRoot) { ws?.showFind(.folder) },
        Cmd(id: "find-next", title: "Find Next", place: .find, key: "g", enabled: hasDoc, dividerBefore: true) { ws?.findNext(1) },
        Cmd(id: "find-previous", title: "Find Previous", place: .find, key: "g", modifiers: [.command, .shift], enabled: hasDoc) { ws?.findNext(-1) },
        Cmd(id: "binder", title: ws?.binderVisible == false ? "Show Binder" : "Hide Binder", place: .view, key: "b", modifiers: [.command, .shift], enabled: ws != nil) { ws?.toggleBinder() },
        Cmd(id: "right-panel", title: ws?.panel == nil ? "Show Side Panel" : "Hide Side Panel", place: .view, key: "\\", enabled: ws != nil) { ws?.togglePanel() },
        Cmd(id: "search", title: "Search Binder", place: .view, key: "s", modifiers: [.command, .option], enabled: ws != nil) { ws?.focusSearch() },
        Cmd(id: "outline", title: ws?.panel == .outline ? "Hide Outline" : "Show Outline", place: .view, key: "o", modifiers: [.command, .option], enabled: ws != nil) { ws?.toggleOutline() },
        Cmd(id: "status", title: prefs.showStatusBar ? "Hide Status Bar" : "Show Status Bar", place: .view, key: "s", modifiers: [.command, .control]) { prefs.showStatusBar.toggle() },
        Cmd(id: "write", title: "Write", place: .view, key: "w", modifiers: [.command, .control], enabled: ws != nil, dividerBefore: true) { ws?.mode = .write },
        Cmd(id: "view", title: "View", place: .view, key: "v", modifiers: [.command, .control], enabled: ws != nil) { ws?.mode = .view },
        Cmd(id: "preview", title: ws?.mode == .view ? "Back to Writing" : "Preview", place: .view, key: "e", enabled: ws != nil) { ws?.mode = ws?.mode == .view ? .write : .view },
        Cmd(id: "font-bigger", title: "Increase Font Size", place: .view, key: "=", enabled: ws != nil, dividerBefore: true) { prefs.changeTextSize(by: 1, viewer: ws?.mode == .view) },
        Cmd(id: "font-smaller", title: "Decrease Font Size", place: .view, key: "-", enabled: ws != nil) { prefs.changeTextSize(by: -1, viewer: ws?.mode == .view) },
        Cmd(id: "margins-bigger", title: "Increase Margins", place: .view, key: "-", modifiers: [.command, .shift], enabled: ws != nil) { prefs.changeMargins(direction: 1, viewer: ws?.mode == .view) },
        Cmd(id: "margins-smaller", title: "Decrease Margins", place: .view, key: "=", modifiers: [.command, .shift], enabled: ws != nil) { prefs.changeMargins(direction: -1, viewer: ws?.mode == .view) },
        Cmd(id: "focus", title: ws?.focus == true ? "Leave Distraction Free" : "Distraction Free", place: .view, key: "d", modifiers: [.command, .shift], enabled: ws != nil && !isPage, dividerBefore: true) { ws?.toggleFocus() },
        Cmd(id: "preview-css", title: "Edit Preview Stylesheet…", place: .view, enabled: hasRoot) { _ = ws?.editPreviewStylesheet() },
        Cmd(id: "typewriter", title: ws?.typewriter == true ? "Turn Off Typewriter Mode" : "Typewriter Mode", place: .view, key: "t", modifiers: [.command, .control], enabled: ws != nil) { ws?.typewriter.toggle() },
        Cmd(id: "palette", title: "Command Palette…", place: .view, key: "p", modifiers: [.command, .shift], enabled: ws != nil, dividerBefore: true) { ws?.paletteVisible.toggle() },

        // only in the palette
        Cmd(id: "reveal", title: "Reveal Folder in Finder", enabled: hasRoot) { ws?.revealInFinder() },
        Cmd(id: "collapse", title: "Collapse All Folders", enabled: hasRoot) { ws?.collapseAll() },
        Cmd(id: "settings", title: "Open Settings…") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) },
    ]
    c += formatCommands(ws: ws)
    for item in recents.items {
        c.append(Cmd(id: "recent-" + item.path, title: "Open Recent: " + item.name) {
            if let ws { ws.openRecent(item) }
            else if recents.resolve(item) != nil { newWindow(Workspace.stash(bookmark: item.bookmark, defaults: AppEnvironment.defaults)) }
        })
    }
    return c
}

struct AppCommands: Commands {
    @ObservedObject var prefs: Preferences
    @ObservedObject private var recents = RecentFolders.shared
    @FocusedObject private var ws: Workspace?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let all = makeCommands(ws: ws, prefs: prefs, recents: recents, newWindow: { openWindow(id: "main", value: $0) })
        CommandGroup(replacing: .newItem) { items(all, .file) }
        CommandGroup(after: .newItem) { items(all, .fileMore) }
        CommandGroup(replacing: .saveItem) { items(all, .tabs) }
        CommandGroup(after: .sidebar) { items(all, .view) }
        CommandMenu("Find") { items(all, .find) }
        CommandMenu("Format") { items(all, .format) }
        CommandGroup(replacing: .help) {
            Button("MDEdit Help") { openWindow(id: "help") }.keyboardShortcut("?", modifiers: .command)
        }
    }

    @ViewBuilder private func items(_ all: [Cmd], _ place: Cmd.Place) -> some View {
        ForEach(all.filter { $0.place == place }) { cmd in
            if cmd.dividerBefore { Divider() }
            button(cmd)
            if cmd.id == "open" { recentMenu }
        }
    }

    @ViewBuilder private func button(_ cmd: Cmd) -> some View {
        if let key = cmd.key {
            Button(cmd.title, action: cmd.run).keyboardShortcut(key, modifiers: cmd.modifiers).disabled(!cmd.enabled)
        } else {
            Button(cmd.title, action: cmd.run).disabled(!cmd.enabled)
        }
    }

    private var recentMenu: some View {
        Menu("Open Recent") {
            ForEach(recents.items) { item in
                Button(item.name) {
                    if let ws { ws.openRecent(item) }
                    else if recents.resolve(item) != nil { openWindow(id: "main", value: Workspace.stash(bookmark: item.bookmark, defaults: AppEnvironment.defaults)) }
                }
            }
            Divider()
            Button("Clear Menu") { recents.clear() }.disabled(recents.items.isEmpty)
        }
    }
}

/// ⇧⌘P: type to filter every command, ↑↓ to choose, ⏎ to run.
struct PaletteView: View {
    @EnvironmentObject var ws: Workspace
    @EnvironmentObject var prefs: Preferences
    @ObservedObject private var recents = RecentFolders.shared
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var results: [Cmd] {
        let all = makeCommands(ws: ws, prefs: prefs, recents: recents, newWindow: { openWindow(id: "main", value: $0) }).filter { $0.id != "palette" }
        return Self.filter(all, query)
    }

    /// Every word typed must appear in the title; case does not matter.
    static func filter(_ commands: [Cmd], _ query: String) -> [Cmd] {
        let words = query.lowercased().split(separator: " ")
        return commands.filter { c in words.allSatisfy { c.title.lowercased().contains($0) } }
    }

    var body: some View {
        let list = results
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
                TextField("Type a command", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .focused($focused)
                    .focusEffectDisabled()
                    .onSubmit { run(list) }
                    .onKeyPress(.upArrow) { selected = max(0, selected - 1); return .handled }
                    .onKeyPress(.downArrow) { selected = min(max(0, list.count - 1), selected + 1); return .handled }
                    .onExitCommand { ws.paletteVisible = false }
                    .onChange(of: query) { _, _ in selected = 0 }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)) }
                        .buttonStyle(.plain).foregroundStyle(Color(Palette.muted)).accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 9).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.field)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(Palette.binderBorder), lineWidth: 1))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, cmd in
                            if cmd.dividerBefore && query.isEmpty && i > 0 {
                                Rectangle().fill(Color(Palette.binderBorder)).frame(height: 1).padding(.vertical, 3).padding(.horizontal, 4)
                            }
                            HStack {
                                Text(cmd.title).font(.system(size: 13)).lineLimit(1)
                                Spacer(minLength: 12)
                                Text(cmd.shortcut).font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
                            }
                            .foregroundStyle(Color(cmd.enabled ? Palette.binderText : Palette.marker))
                            .padding(.horizontal, 8).frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 6).fill(i == selected ? Color(Palette.selection) : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(i == selected ? Color(Palette.binderBorder) : .clear, lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture { selected = i; run(list) }
                            .id(i)
                        }
                        if list.isEmpty { Text("No matching command").font(.system(size: 12.5)).foregroundStyle(Color(Palette.muted)).padding(.vertical, 10) }
                    }
                }
                .frame(maxHeight: 300)
                .onChange(of: selected) { _, n in proxy.scrollTo(n) }
            }
        }
        .padding(6)
        .frame(width: 440)
        // the shadow belongs to the panel's own shape, not to the field and rows inside it
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(Palette.binderBg)).shadow(color: .black.opacity(0.16), radius: 14, y: 6))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(Palette.binderBorder), lineWidth: 1))
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command palette")
    }

    private func run(_ list: [Cmd]) {
        guard list.indices.contains(selected), list[selected].enabled else { return }
        let cmd = list[selected]
        ws.paletteVisible = false
        DispatchQueue.main.async { cmd.run() }
    }
}
