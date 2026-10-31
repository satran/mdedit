import SwiftUI

@main
struct MDEditApp: App {
    @StateObject private var prefs = Preferences.shared

    init() {
        // windows, not tabs: this also removes Show Tab Bar and Show All Tabs from the menus
        NSWindow.allowsAutomaticWindowTabbing = false
    }

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
            .onAppear { Preferences.shared.applyTheme(); ws.newWindow = { openWindow(id: "main", value: $0) } }
    }
}
