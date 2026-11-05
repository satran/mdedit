import Foundation
import Combine

/// Starts, stops and restarts the MCP server when the settings change, and tells Settings how it is doing.
/// Never starts under the test runner: a test builds its own `MCPServer` on a random port.
@MainActor final class AgentServerController: ObservableObject {
    static let shared = AgentServerController()

    @Published private(set) var state: MCPServer.State = .stopped
    var bridge: any AgentBridge = AgentTools()

    private var server: MCPServer?
    private var token = ""
    private var bag = Set<AnyCancellable>()
    private var started = false

    /// One line for Settings.
    var statusText: String {
        switch state {
        case .stopped: return "Off"
        case .starting: return "Starting…"
        case .listening(let p): return "Listening on 127.0.0.1:\(p)"
        case .failed(let m): return m
        }
    }

    func start(prefs: Preferences = .shared) {
        guard !started, !AppEnvironment.isTesting else { return }
        started = true
        prefs.$agentToken.sink { [weak self] t in self?.token = t; self?.server?.setToken(t) }.store(in: &bag)
        prefs.$agentsEnabled.combineLatest(prefs.$agentPort).removeDuplicates { $0 == $1 }
            .sink { [weak self] on, port in self?.apply(enabled: on, port: port) }.store(in: &bag)
    }

    private func apply(enabled: Bool, port: Int) {
        server?.stop(); server = nil
        guard enabled else { state = .stopped; ProposalStore.shared.withdrawAll(); return }
        let s = MCPServer(port: port, token: token, bridge: bridge)
        s.onState { [weak self] st in Task { @MainActor in if self?.server === s { self?.state = st } } }
        server = s
        s.start()
    }
}
