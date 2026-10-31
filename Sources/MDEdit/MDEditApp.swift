import SwiftUI

@main
struct MDEditApp: App {
    @StateObject private var prefs = Preferences.shared

    var body: some Scene {
        // One window per folder; the value is the window's own id, which keys what it remembers.
        WindowGroup("MDEdit", id: "main", for: UUID.self) { $id in
            WindowRoot(id: id).environmentObject(prefs)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands { AppCommands(prefs: prefs) }
        Settings {
            SettingsView().environmentObject(prefs)
        }
    }
}

/// A window: its own workspace, shared with the menu commands while it is frontmost.
struct WindowRoot: View {
    @StateObject private var ws: Workspace
    @Environment(\.openWindow) private var openWindow

    init(id: UUID?) { _ws = StateObject(wrappedValue: Workspace(id: id)) }

    var body: some View {
        RootView()
            .environmentObject(ws)
            .focusedSceneObject(ws)
            .navigationTitle(ws.rootURL?.lastPathComponent ?? "MDEdit")
            .frame(minWidth: (ws.binderVisible ? 760 : 488) + (ws.outlineVisible ? 241 : 0), minHeight: 480)
            .onAppear { ws.newWindow = { openWindow(id: "main", value: $0) } }
    }
}

struct AppCommands: Commands {
    @ObservedObject var prefs: Preferences
    @ObservedObject private var recents = RecentFolders.shared
    @FocusedObject private var ws: Workspace?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") {
                if let ws { ws.chooseFolder() }
                else if let url = Workspace.pickFolder(), let id = Workspace.stash(url) { openWindow(id: "main", value: id) }
            }.keyboardShortcut("o")
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
            Button("New Window") { openWindow(id: "main", value: UUID()) }.keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("New Document") { ws?.newDocument() }.keyboardShortcut("n").disabled(ws?.root == nil)
            Button("New Folder") { ws?.newFolder() }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(ws?.root == nil)
        }
        CommandGroup(after: .newItem) {
            Button("Rename") { if let s = ws?.selection { ws?.renaming = s } }.keyboardShortcut("r").disabled(ws?.selection == nil)
            Button("Move to Trash") { if let s = ws?.selection { ws?.trash(s) } }.disabled(ws?.selection == nil)
            Divider()
            Button("Export as HTML…") { if let ws, let u = ws.document.url { Exporter.shared.saveHTML(markdown: ws.document.text, name: u.deletingPathExtension().lastPathComponent, prefs: prefs) } }
                .disabled(ws?.document.url == nil)
            Button("Copy as Markdown") { if let ws { Exporter.shared.copyMarkdown(ws.document.text) } }.disabled(ws?.document.url == nil)
            Button("Print…") {
                if let ws, let u = ws.document.url { Exporter.shared.print(markdown: ws.document.text, name: u.deletingPathExtension().lastPathComponent, prefs: prefs) }
            }
            .keyboardShortcut("p").disabled(ws?.document.url == nil)
        }
        CommandGroup(after: .sidebar) {
            Button(ws?.binderVisible == false ? "Show Binder" : "Hide Binder") { ws?.toggleBinder() }.keyboardShortcut("s", modifiers: [.command, .control]).disabled(ws == nil)
            Button(prefs.showStatusBar ? "Hide Status Bar" : "Show Status Bar") { prefs.showStatusBar.toggle() }.keyboardShortcut("b", modifiers: [.command, .option])
            Button("Write") { ws?.mode = .write }.keyboardShortcut("1").disabled(ws == nil)
            Button("View") { ws?.mode = .view }.keyboardShortcut("2").disabled(ws == nil)
            Divider()
            Button(ws?.focus == true ? "Leave Distraction Free" : "Distraction Free") { ws?.toggleFocus() }.keyboardShortcut("f", modifiers: [.command, .control]).disabled(ws == nil)
            Button(ws?.typewriter == true ? "Turn Off Typewriter Mode" : "Typewriter Mode") { ws?.typewriter.toggle() }.keyboardShortcut("t", modifiers: [.command, .control]).disabled(ws == nil)
            Button(ws?.outlineVisible == true ? "Hide Outline" : "Show Outline") { ws?.toggleOutline() }.keyboardShortcut("o", modifiers: [.command, .option]).disabled(ws == nil)
        }
    }
}
