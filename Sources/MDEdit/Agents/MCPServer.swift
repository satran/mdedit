import Foundation
import Network

/// A minimal MCP server (streamable HTTP, without streaming) on the loopback address.
/// HTTP and JSON-RPC only: tool calls go to an `AgentBridge` on the main actor. This is the only file that may create a listener
/// (`make audit` checks it), and it binds to 127.0.0.1 only.
final class MCPServer: @unchecked Sendable {
    enum State: Equatable {
        case stopped, starting
        case listening(port: Int)
        case failed(String)
    }

    struct Limits {
        var maxBody = 1_000_000
        var maxConnections = 8
        /// The whole request must arrive within this.
        var requestTimeout: TimeInterval = 10
        /// A connection is closed after this, whatever it is doing.
        var lifetime: TimeInterval = 30
    }

    static let protocolVersion = "2025-06-18"

    private let queue = DispatchQueue(label: "in.ranjeev.mdedit.mcp")
    private let lock = NSLock()
    private let requestedPort: Int
    private let limits: Limits
    private weak var bridge: (any AgentBridge)?
    private var listener: NWListener?
    private var _token: String
    private var _state: State = .stopped
    private var active = 0
    private var stateHandler: (@Sendable (State) -> Void)?

    /// `port` 0 picks a free port (tests). `bridge` is held weakly.
    init(port: Int, token: String, bridge: any AgentBridge, limits: Limits = Limits()) {
        requestedPort = port; _token = token; self.bridge = bridge; self.limits = limits
    }

    var state: State { lock.lock(); defer { lock.unlock() }; return _state }
    /// A new token applies to the very next request.
    func setToken(_ t: String) { lock.lock(); _token = t; lock.unlock() }
    private var token: String { lock.lock(); defer { lock.unlock() }; return _token }
    func onState(_ h: @escaping @Sendable (State) -> Void) { lock.lock(); stateHandler = h; lock.unlock() }

    private func set(_ s: State) {
        lock.lock(); _state = s; let h = stateHandler; lock.unlock()
        h?(s)
    }

    func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: UInt16(requestedPort)) else {
            if listener == nil { set(.failed("Invalid port \(requestedPort).")) }
            return
        }
        set(.starting)
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        params.allowLocalEndpointReuse = true
        do {
            let l = try NWListener(using: params)
            listener = l
            l.stateUpdateHandler = { [weak self, weak l] s in
                guard let self else { return }
                switch s {
                case .ready: self.set(.listening(port: Int(l?.port?.rawValue ?? 0)))
                case .failed(let e), .waiting(let e):
                    let inUse = "\(e)".lowercased().contains("in use") || "\(e)".contains("48")
                    self.set(.failed(inUse ? "Port \(self.requestedPort) is in use. Choose another port." : "Could not listen: \(e)"))
                    l?.cancel()
                default: break
                }
            }
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.start(queue: queue)
        } catch {
            set(.failed("Could not listen: \(error)"))
        }
    }

    func stop() {
        listener?.cancel(); listener = nil
        set(.stopped)
    }

    // MARK: connections

    private func accept(_ c: NWConnection) {
        if active >= limits.maxConnections {
            c.start(queue: queue)
            Self.send(c, status: 503, body: Self.errorBody("busy"))
            return
        }
        active += 1
        let conn = Conn(c)
        c.stateUpdateHandler = { [weak self] s in
            if case .cancelled = s { self?.queue.async { self?.active -= 1 } }
        }
        c.start(queue: queue)
        queue.asyncAfter(deadline: .now() + limits.requestTimeout) { [weak conn] in
            if let conn, !conn.complete { conn.fail(408, "request timeout") }
        }
        queue.asyncAfter(deadline: .now() + limits.lifetime) { [weak conn] in conn?.c.cancel() }
        receive(conn)
    }

    private final class Conn {
        let c: NWConnection
        var buffer = Data()
        var complete = false          // a response has been decided
        var head: Head?
        init(_ c: NWConnection) { self.c = c }
        func fail(_ status: Int, _ message: String) {
            complete = true
            MCPServer.send(c, status: status, body: MCPServer.errorBody(message))
        }
    }

    private struct Head { let method: String, path: String, headers: [String: String], bodyStart: Int, length: Int }

    private func receive(_ conn: Conn) {
        conn.c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isDone, error in
            guard let self, !conn.complete else { return }
            if let data { conn.buffer.append(data) }
            if error != nil { conn.c.cancel(); return }
            self.process(conn)
            if !conn.complete { if isDone { conn.c.cancel() } else { self.receive(conn) } }
        }
    }

    private func process(_ conn: Conn) {
        if conn.head == nil {
            guard let end = conn.buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if conn.buffer.count > 16_384 { conn.fail(431, "headers too large") }
                return
            }
            let text = String(decoding: conn.buffer[..<end.lowerBound], as: UTF8.self)
            var lines = text.components(separatedBy: "\r\n")
            let parts = lines.removeFirst().split(separator: " ")
            guard parts.count == 3 else { return conn.fail(400, "bad request line") }
            var headers: [String: String] = [:]
            for l in lines { if let i = l.firstIndex(of: ":") { headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) } }
            let method = String(parts[0]), path = String(parts[1])

            // 1. path and method
            guard path == "/mcp" else { return conn.fail(404, "not found") }
            guard method == "POST" else { return conn.fail(405, "method not allowed") }
            // 2. Host
            let port = { if case .listening(let p) = state { return p }; return requestedPort }()
            let host = (headers["host"] ?? "").lowercased()
            guard host == "127.0.0.1:\(port)" || host == "localhost:\(port)" else { return conn.fail(403, "bad host") }
            // 3. Origin, if sent
            if let origin = headers["origin"], !Self.isLoopbackOrigin(origin) { return conn.fail(403, "bad origin") }
            // 4. token
            let auth = headers["authorization"] ?? ""
            let given = auth.lowercased().hasPrefix("bearer ") ? String(auth.dropFirst(7)) : ""
            guard Self.constantTimeEqual(given, token) else { return conn.fail(401, "unauthorized") }
            // framing
            if headers["transfer-encoding"] != nil { return conn.fail(411, "length required") }
            guard let n = headers["content-length"].flatMap({ Int($0) }), n >= 0 else { return conn.fail(411, "length required") }
            guard n <= limits.maxBody else { return conn.fail(413, "body too large") }
            conn.head = Head(method: method, path: path, headers: headers, bodyStart: end.upperBound, length: n)
        }
        guard let head = conn.head, conn.buffer.count - head.bodyStart >= head.length else { return }
        conn.complete = true
        let body = conn.buffer[head.bodyStart..<(head.bodyStart + head.length)]
        let client = String((head.headers["user-agent"] ?? "").prefix(40))
        handle(Data(body), client: client.isEmpty ? "Agent" : client) { status, response in
            Self.send(conn.c, status: status, body: response)
        }
    }

    // MARK: JSON-RPC

    private func handle(_ body: Data, client: String, reply: @escaping @Sendable (Int, Data) -> Void) {
        func rpcError(_ id: Any?, _ code: Int, _ message: String) -> Data {
            Self.json(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message] as [String: Any]])
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: body) else { return reply(200, rpcError(nil, -32700, "Parse error")) }
        guard let msg = parsed as? [String: Any], msg["jsonrpc"] as? String == "2.0", let method = msg["method"] as? String else {
            return reply(200, rpcError(nil, -32600, "Invalid request (batches are not supported)"))
        }
        let id = msg["id"]
        let params = msg["params"] as? [String: Any] ?? [:]
        func result(_ r: [String: Any]) -> Data { Self.json(["jsonrpc": "2.0", "id": id as Any, "result": r]) }

        if id == nil { return reply(202, Data()) }   // a notification (notifications/initialized and the rest)
        switch method {
        case "initialize":
            reply(200, result(["protocolVersion": Self.protocolVersion, "capabilities": ["tools": [String: Any]()] as [String: Any],
                               "serverInfo": ["name": "MDEdit", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"] as [String: Any]]))
        case "ping": reply(200, result([:]))
        case "tools/list": reply(200, result(["tools": AgentToolSpec.all]))
        case "tools/call":
            guard let name = params["name"] as? String, AgentToolSpec.names.contains(name) else { return reply(200, rpcError(id, -32602, "Unknown tool")) }
            let call = AgentToolCall(name: name, arguments: params["arguments"] as? [String: Any] ?? [:], client: client)
            let bridge = self.bridge
            let idBox = IDBox(id)
            Task { @MainActor in
                let r: AgentToolResult
                if let bridge { r = await bridge.callAsync(call) } else { r = .error("no_window", "No MDEdit window is open.") }
                let out = Self.json(["jsonrpc": "2.0", "id": idBox.id as Any,
                                     "result": ["content": [["type": "text", "text": r.json]], "isError": r.isError] as [String: Any]])
                reply(200, out)
            }
        default: reply(200, rpcError(id, -32601, "Method not found"))
        }
    }

    private struct IDBox: @unchecked Sendable { let id: Any?; init(_ i: Any?) { id = i } }

    // MARK: helpers

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = x.count ^ y.count
        for i in 0..<max(x.count, y.count) { diff |= Int(i < x.count ? x[i] : 0) ^ Int(i < y.count ? y[i] : 0) }
        return diff == 0
    }

    static func isLoopbackOrigin(_ origin: String) -> Bool {
        guard let u = URLComponents(string: origin), u.scheme == "http", let h = u.host else { return false }
        return h == "127.0.0.1" || h == "localhost"
    }

    private static func json(_ o: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])) ?? Data() }
    private static func errorBody(_ m: String) -> Data { json(["error": m]) }

    private static func send(_ c: NWConnection, status: Int, body: Data) {
        let reasons = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed",
                       408: "Request Timeout", 411: "Length Required", 413: "Payload Too Large", 431: "Request Header Fields Too Large", 503: "Service Unavailable"]
        var head = "HTTP/1.1 \(status) \(reasons[status] ?? "Error")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if status == 401 { head += "WWW-Authenticate: Bearer\r\n" }
        if status == 405 { head += "Allow: POST\r\n" }
        c.send(content: Data((head + "\r\n").utf8) + body, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in c.cancel() })
    }
}
