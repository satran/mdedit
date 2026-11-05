import AppKit

/// The windows an agent can act on. The only place that knows about windows: a weak list filled when a note window appears
/// (`WindowRoot.onAppear`, never `Workspace.init`, so test workspaces do not join it).
@MainActor final class AgentWindows {
    static let shared = AgentWindows()

    private struct Entry { weak var ws: Workspace? }
    private var entries: [Entry] = []
    private weak var lastKey: Workspace?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] n in
            guard let w = n.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.noteKey(w) }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func register(_ ws: Workspace) {
        entries.removeAll { $0.ws == nil }
        if !entries.contains(where: { $0.ws === ws }) { entries.append(Entry(ws: ws)) }
    }

    var all: [Workspace] { entries.compactMap(\.ws) }

    private func noteKey(_ w: NSWindow) {
        if let ws = all.first(where: { $0.hostWindow === w }) { lastKey = ws }
    }

    /// The window to act on: the key one; else the one that was key most recently (the agent usually runs in a terminal, so the
    /// app is in the background and nothing is key); else the only one there is. nil when there is none, or it is ambiguous.
    func front() -> Workspace? {
        entries.removeAll { $0.ws == nil }
        if let key = NSApp.keyWindow, let ws = all.first(where: { $0.hostWindow === key }) { return ws }
        if let ws = lastKey, all.contains(where: { $0 === ws }) { return ws }
        return all.count == 1 ? all.first : nil
    }
}
