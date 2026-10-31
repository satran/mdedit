import SwiftUI

/// One thing the app can do. The menu bar and the command palette are both built from the same list.
struct Cmd: Identifiable {
    enum Place { case file, fileMore, view, paletteOnly }
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
    func docName(_ w: Workspace) -> String { w.document.url?.deletingPathExtension().lastPathComponent ?? "" }
    func openFolderElsewhere(_ url: URL) {
        if let ws { ws.openFolder(url) } else if let id = Workspace.stash(url) { newWindow(id) }
    }

    var c: [Cmd] = [
        Cmd(id: "open", title: "Open Folder…", place: .file, key: "o") {
            if let ws { ws.chooseFolder() }
            else if let url = Workspace.pickFolder(), let id = Workspace.stash(url) { newWindow(id) }
        },
        Cmd(id: "new-window", title: "New Window", place: .file, key: "n", modifiers: [.command, .option]) { newWindow(UUID()) },
        Cmd(id: "new-doc", title: "New Document", place: .file, key: "n", enabled: hasRoot, dividerBefore: true) { ws?.newDocument() },
        Cmd(id: "new-folder", title: "New Folder", place: .file, key: "n", modifiers: [.command, .shift], enabled: hasRoot) { ws?.newFolder() },

        Cmd(id: "rename", title: "Rename", place: .fileMore, key: "r", enabled: ws?.selection != nil) { if let s = ws?.selection { ws?.renaming = s } },
        Cmd(id: "trash", title: "Move to Trash", place: .fileMore, enabled: ws?.selection != nil) { if let s = ws?.selection { ws?.trash(s) } },
        Cmd(id: "export-html", title: "Export as HTML…", place: .fileMore, enabled: hasDoc, dividerBefore: true) {
            if let ws { Exporter.shared.saveHTML(markdown: ws.document.text, name: docName(ws), prefs: prefs) }
        },
        Cmd(id: "copy-md", title: "Copy as Markdown", place: .fileMore, enabled: hasDoc) { if let ws { Exporter.shared.copyMarkdown(ws.document.text) } },
        Cmd(id: "print", title: "Print…", place: .fileMore, key: "p", enabled: hasDoc) {
            if let ws { Exporter.shared.print(markdown: ws.document.text, name: docName(ws), prefs: prefs) }
        },

        Cmd(id: "binder", title: ws?.binderVisible == false ? "Show Binder" : "Hide Binder", place: .view, key: "s", modifiers: [.command, .control], enabled: ws != nil) { ws?.toggleBinder() },
        Cmd(id: "search", title: "Search Binder", place: .view, key: "f", modifiers: [.command, .shift], enabled: ws != nil) { ws?.focusSearch() },
        Cmd(id: "outline", title: ws?.outlineVisible == true ? "Hide Outline" : "Show Outline", place: .view, key: "o", modifiers: [.command, .option], enabled: ws != nil) { ws?.toggleOutline() },
        Cmd(id: "status", title: prefs.showStatusBar ? "Hide Status Bar" : "Show Status Bar", place: .view, key: "b", modifiers: [.command, .option]) { prefs.showStatusBar.toggle() },
        Cmd(id: "write", title: "Write", place: .view, key: "1", enabled: ws != nil, dividerBefore: true) { ws?.mode = .write },
        Cmd(id: "view", title: "View", place: .view, key: "2", enabled: ws != nil) { ws?.mode = .view },
        Cmd(id: "focus", title: ws?.focus == true ? "Leave Distraction Free" : "Distraction Free", place: .view, key: "f", modifiers: [.command, .control], enabled: ws != nil, dividerBefore: true) { ws?.toggleFocus() },
        Cmd(id: "typewriter", title: ws?.typewriter == true ? "Turn Off Typewriter Mode" : "Typewriter Mode", place: .view, key: "t", modifiers: [.command, .control], enabled: ws != nil) { ws?.typewriter.toggle() },
        Cmd(id: "palette", title: "Command Palette…", place: .view, key: "p", modifiers: [.command, .shift], enabled: ws != nil, dividerBefore: true) { ws?.paletteVisible.toggle() },

        // only in the palette
        Cmd(id: "reveal", title: "Reveal Folder in Finder", enabled: hasRoot) { ws?.revealInFinder() },
        Cmd(id: "collapse", title: "Collapse All Folders", enabled: hasRoot) { ws?.collapseAll() },
        Cmd(id: "settings", title: "Open Settings…") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) },
    ]
    for item in recents.items {
        c.append(Cmd(id: "recent-" + item.path, title: "Open Recent: " + item.name) {
            if let url = recents.resolve(item) { openFolderElsewhere(url) }
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
        CommandGroup(after: .sidebar) { items(all, .view) }
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
                    guard let url = recents.resolve(item) else { return }
                    if let ws { ws.openFolder(url) }
                    else if let id = Workspace.stash(url) { openWindow(id: "main", value: id) }
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
        let words = query.lowercased().split(separator: " ")
        return all.filter { c in words.allSatisfy { c.title.lowercased().contains($0) } }
    }

    var body: some View {
        let list = results
        VStack(spacing: 0) {
            TextField("Type a command", text: $query)
                .textFieldStyle(.plain).font(.system(size: 15))
                .focused($focused)
                .padding(.horizontal, 16).frame(height: 46)
                .onSubmit { run(list) }
                .onKeyPress(.upArrow) { selected = max(0, selected - 1); return .handled }
                .onKeyPress(.downArrow) { selected = min(max(0, list.count - 1), selected + 1); return .handled }
                .onExitCommand { ws.paletteVisible = false }
                .onChange(of: query) { _, _ in selected = 0 }
            Rectangle().fill(Color(Palette.binderBorder)).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, cmd in
                            HStack {
                                Text(cmd.title).font(.system(size: 13))
                                Spacer()
                                Text(cmd.shortcut).font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
                            }
                            .foregroundStyle(Color(cmd.enabled ? Palette.binderText : Palette.marker))
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 7).fill(i == selected ? Color(Palette.selection) : .clear))
                            .contentShape(Rectangle())
                            .onTapGesture { selected = i; run(list) }
                            .id(i)
                        }
                        if list.isEmpty { Text("No matching command").font(.system(size: 12.5)).foregroundStyle(Color(Palette.muted)).padding(.top, 14) }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 320)
                .onChange(of: selected) { _, n in proxy.scrollTo(n) }
            }
        }
        .frame(width: 520)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(Palette.binderBg)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(Palette.binderBorder), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
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
