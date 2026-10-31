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
            CommandGroup(after: .sidebar) {
                Button("Write") { ws.mode = .write }.keyboardShortcut("1")
                Button("View") { ws.mode = .view }.keyboardShortcut("2")
            }
        }
    }
}
