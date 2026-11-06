import Foundation
import Network

/// A server on 127.0.0.1 that counts connections, to prove a page made no request. It answers every request with an empty 200.
/// (It lives in the test target; the audit scans `Sources` only.)
final class LocalHTTPServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "local-http-server")
    private let lock = NSLock()
    private var connections = 0
    private(set) var port: UInt16 = 0

    /// Connections accepted so far: a request, a prefetch or a bare TCP connect all count.
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return connections }
    var address: String { "http://127.0.0.1:\(port)" }

    init() throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        listener = try NWListener(using: params, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            self.lock.lock(); self.connections += 1; self.lock.unlock()
            conn.start(queue: self.queue)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                let body = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                conn.send(content: Data(body.utf8), completion: .contentProcessed { _ in conn.cancel() })
            }
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let p = listener.port?.rawValue else { throw URLError(.cannotConnectToHost) }
        port = p
    }

    func reset() { lock.lock(); connections = 0; lock.unlock() }
    func stop() { listener.cancel() }
}
