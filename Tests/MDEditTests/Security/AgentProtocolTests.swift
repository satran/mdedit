import XCTest
@testable import MDEdit

/// The MCP server over a real loopback socket on a random port, with a stub in place of the editor.
@MainActor
final class AgentProtocolTests: XCTestCase {
    final class Stub: AgentBridge {
        var calls: [AgentToolCall] = []
        func call(_ call: AgentToolCall) -> AgentToolResult { calls.append(call); return AgentToolResult(json: "{\"ok\":true}", isError: false) }
    }

    let token = String(repeating: "a", count: 64)
    var stub = Stub()
    var server: MCPServer!
    var client: RawHTTPClient!

    private func startServer(limits: MCPServer.Limits = .init()) throws {
        server = MCPServer(port: 0, token: token, bridge: stub, limits: limits)
        server.start()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline { if case .listening = server.state { break }; RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        guard case .listening(let p) = server.state, p > 0 else { throw XCTSkip("could not listen: \(server.state)") }
        client = RawHTTPClient(port: p)
        addTeardownBlock { [server] in server?.stop() }
    }

    override func setUp() async throws { try startServer() }

    private func rpc(_ body: String, token: String? = nil, headers: [String: String?] = [:]) async -> RawResponse? {
        await client.post(body, token: token ?? self.token, headers: headers)
    }

    private func json(_ r: RawResponse?) -> [String: Any] { (try? JSONSerialization.jsonObject(with: Data((r?.body ?? "").utf8))) as? [String: Any] ?? [:] }

    // MARK: normal use

    func testInitializeAnswersWithTheServersVersionAndTools() async {
        let r = await rpc(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"x"}}}"#)
        XCTAssertEqual(r?.status, 200)
        let result = json(r)["result"] as? [String: Any]
        XCTAssertEqual(result?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertNotNil((result?["capabilities"] as? [String: Any])?["tools"])
    }

    func testToolsListHasTheFiveToolsWithSchemas() async {
        let r = await rpc(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = (json(r)["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }, ["get_context", "read_note", "propose_edit", "render_template", "get_proposal"])
        XCTAssertTrue(tools.allSatisfy { $0["inputSchema"] is [String: Any] })
    }

    func testPingAndInitializedNotification() async {
        let ping = await rpc(#"{"jsonrpc":"2.0","id":3,"method":"ping"}"#)
        XCTAssertEqual(ping?.status, 200)
        let note = await rpc(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertEqual(note?.status, 202)
        XCTAssertEqual(note?.body, "")
    }

    func testAToolCallReachesTheBridgeWithItsArguments() async {
        let r = await rpc(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"read_note","arguments":{"path":"a.md"}}}"#, headers: ["User-Agent": "claude-code/1"])
        XCTAssertEqual(r?.status, 200)
        XCTAssertEqual(stub.calls.first?.name, "read_note")
        XCTAssertEqual(stub.calls.first?.arguments["path"] as? String, "a.md")
        XCTAssertEqual(stub.calls.first?.client, "claude-code/1")
        let result = json(r)["result"] as? [String: Any]
        XCTAssertEqual(result?["isError"] as? Bool, false)
    }

    func testWithNoWindowAToolReportsIt() async throws {
        server.stop(); server = nil
        let none = NoWindowBridge()
        server = MCPServer(port: 0, token: token, bridge: none); server.start()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline { if case .listening = server.state { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        guard case .listening(let p) = server.state else { return XCTFail("not listening") }
        let r = await RawHTTPClient(port: p).post(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_context"}}"#, token: token)
        let text = ((json(r)["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        XCTAssertTrue(text.contains("no_window"))
        XCTAssertEqual((json(r)["result"] as? [String: Any])?["isError"] as? Bool, true)
    }

    // MARK: hostile input

    func testProtocolErrors() async {
        let unknown = await rpc(#"{"jsonrpc":"2.0","id":1,"method":"nope"}"#)
        XCTAssertEqual((json(unknown)["error"] as? [String: Any])?["code"] as? Int, -32601)
        let bad = await rpc("{not json")
        XCTAssertEqual((json(bad)["error"] as? [String: Any])?["code"] as? Int, -32700)
        let batch = await rpc(#"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#)
        XCTAssertEqual((json(batch)["error"] as? [String: Any])?["code"] as? Int, -32600)
        let tool = await rpc(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"rm_rf"}}"#)
        XCTAssertEqual((json(tool)["error"] as? [String: Any])?["code"] as? Int, -32602)
        XCTAssertTrue(stub.calls.isEmpty)
    }

    func testWrongPathAndMethod() async {
        let get = await client.post("", token: token, headers: ["Content-Length": nil], method: "GET")
        XCTAssertEqual(get?.status, 405)
        let path = await client.post("{}", token: token, path: "/other")
        XCTAssertEqual(path?.status, 404)
    }

    func testFramingIsStrict() async {
        let noLength = await client.post("{}", token: token, headers: ["Content-Length": nil])
        XCTAssertEqual(noLength?.status, 411)
        let chunked = await client.post("0\r\n\r\n", token: token, headers: ["Transfer-Encoding": "chunked", "Content-Length": nil])
        XCTAssertEqual(chunked?.status, 411)
        let big = await client.post(String(repeating: "x", count: 1_000_001), token: token)
        XCTAssertEqual(big?.status, 413)
    }

    func testHostAndOriginAreChecked() async {
        let host = await rpc(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, headers: ["Host": "evil.example:\(client.port)"])
        XCTAssertEqual(host?.status, 403)
        for origin in ["null", "https://example.com", "http://127.0.0.1.evil.com"] {
            let r = await rpc(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, headers: ["Origin": origin])
            XCTAssertEqual(r?.status, 403, origin)
        }
        let local = await rpc(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, headers: ["Origin": "http://localhost:3000"])
        XCTAssertEqual(local?.status, 200)
        let localhostHost = await rpc(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, headers: ["Host": "localhost:\(client.port)"])
        XCTAssertEqual(localhostHost?.status, 200)
    }

    func testTheTokenIsRequiredAndNeverEchoed() async {
        let none = await client.post("{}", token: nil)
        XCTAssertEqual(none?.status, 401)
        let wrong = await client.post("{}", token: String(repeating: "b", count: 64))
        XCTAssertEqual(wrong?.status, 401)
        let short = await client.post("{}", token: String(token.dropLast()))
        XCTAssertEqual(short?.status, 401)
        for r in [none, wrong, short] { XCTAssertFalse((r?.body ?? "").contains(token)); XCTAssertFalse((r?.headers.description ?? "").contains(token)) }
        // a bad Origin wins over a missing token (the Origin check runs first)
        let both = await client.post("{}", token: nil, headers: ["Origin": "https://example.com"])
        XCTAssertEqual(both?.status, 403)
        // a good Origin with no token is a 401
        let good = await client.post("{}", token: nil, headers: ["Origin": "http://localhost"])
        XCTAssertEqual(good?.status, 401)
    }

    func testRegenerateLocksTheOldTokenOutAtOnce() async {
        let ping = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        let before = await client.post(ping, token: token)
        XCTAssertEqual(before?.status, 200)
        let fresh = String(repeating: "c", count: 64)
        server.setToken(fresh)
        let old = await client.post(ping, token: token)
        XCTAssertEqual(old?.status, 401)
        let new = await client.post(ping, token: fresh)
        XCTAssertEqual(new?.status, 200)
    }

    func testConstantTimeCompare() {
        XCTAssertTrue(MCPServer.constantTimeEqual("abc", "abc"))
        XCTAssertFalse(MCPServer.constantTimeEqual("abc", "abd"))
        XCTAssertFalse(MCPServer.constantTimeEqual("abc", "abcd"))
        XCTAssertFalse(MCPServer.constantTimeEqual("", "a"))
    }

    // MARK: failure halfway

    func testAStalledRequestIsClosed() async throws {
        server.stop()
        try startServer(limits: .init(requestTimeout: 0.4, lifetime: 5))
        let fd = RawHTTPClient.open(port: client.port, send: "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:\(client.port)\r\n")
        defer { close(fd) }
        let r = await Task.detached { RawHTTPClient.read(fd, wait: 3) }.value
        XCTAssertEqual(r?.status, 408)
    }

    func testTheNinthConnectionIsRefused() async throws {
        server.stop()
        try startServer(limits: .init(maxConnections: 2, requestTimeout: 5, lifetime: 5))
        let held = (0..<2).map { _ in RawHTTPClient.open(port: client.port) }
        defer { held.forEach { close($0) } }
        try await Task.sleep(nanoseconds: 200_000_000)
        let r = await client.post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, token: token)
        XCTAssertEqual(r?.status, 503)
    }

    func testStoppingClosesThePortAndAPortInUseIsReported() async throws {
        let port = client.port
        let second = MCPServer(port: port, token: token, bridge: stub)
        second.start()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline { if case .failed = second.state { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        if case .failed(let m) = second.state { XCTAssertTrue(m.contains("in use"), m) } else { XCTFail("expected a failure, got \(second.state)") }
        server.stop()
        try await Task.sleep(nanoseconds: 200_000_000)
        let r = await client.post("{}", token: token)
        XCTAssertNil(r, "nothing listens after stop")
        XCTAssertEqual(server.state, .stopped)
    }

    func testTheTestRunNeverStartsTheServerByItself() {
        XCTAssertTrue(AppEnvironment.isTesting)
        XCTAssertEqual(AgentServerController.shared.state, .stopped)
        AgentServerController.shared.start()
        XCTAssertEqual(AgentServerController.shared.state, .stopped)
    }

    // MARK: speed

    func testManyRequestsAreFast() async {
        let start = Date()
        for _ in 0..<50 { _ = await rpc(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}
