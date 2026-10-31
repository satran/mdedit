import SwiftUI

@main
struct MDEditApp: App {
    @StateObject private var ws = Workspace()
    @StateObject private var prefs = Preferences.shared

    var body: some Scene {
        Window("MDEdit", id: "main") {
            RootView()
                .environmentObject(ws)
                .environmentObject(prefs)
                .frame(minWidth: 760, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") { ws.chooseFolder() }.keyboardShortcut("o")
                Divider()
                Button("New Document") { ws.newDocument() }.keyboardShortcut("n").disabled(ws.root == nil)
                Button("New Folder") { ws.newFolder() }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(ws.root == nil)
            }
            CommandGroup(after: .newItem) {
                Button("Rename") { if let s = ws.selection { ws.renaming = s } }.keyboardShortcut("r").disabled(ws.selection == nil)
                Button("Move to Trash") { if let s = ws.selection { ws.trash(s) } }.disabled(ws.selection == nil)
                Divider()
                Button("Print…") { if let u = ws.document.url { Exporter.shared.print(markdown: ws.document.text, name: u.deletingPathExtension().lastPathComponent, prefs: prefs) } }
                    .keyboardShortcut("p").disabled(ws.document.url == nil)
            }
            CommandGroup(after: .sidebar) {
                Button("Write") { ws.mode = .write }.keyboardShortcut("1")
                Button("View") { ws.mode = .view }.keyboardShortcut("2")
                Divider()
                Button(ws.focus ? "Leave Distraction Free" : "Distraction Free") { ws.toggleFocus() }.keyboardShortcut("f", modifiers: [.command, .control])
                Button(ws.typewriter ? "Turn Off Typewriter Mode" : "Typewriter Mode") { ws.typewriter.toggle() }.keyboardShortcut("t", modifiers: [.command, .control])
                Button(ws.outlineVisible ? "Hide Outline" : "Show Outline") { ws.outlineVisible.toggle() }.keyboardShortcut("o", modifiers: [.command, .option])
            }
        }
        Settings {
            SettingsView().environmentObject(prefs)
        }
    }
}
