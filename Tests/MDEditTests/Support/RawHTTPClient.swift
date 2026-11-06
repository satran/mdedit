import Foundation
import Darwin

/// A client that writes exact bytes to a loopback port. URLSession cannot send a wrong Host, no Content-Length or odd framing.
/// Calls block, so run them off the main thread (`await client.send(...)`): tool calls hop to the main actor.
struct RawResponse { let status: Int; let headers: [String: String]; let body: String }

final class RawHTTPClient {
    let port: Int
    init(port: Int) { self.port = port }

    /// A POST /mcp with sensible headers; pass `headers` to replace or (with nil) drop one.
    func post(_ body: String, token: String? = nil, headers: [String: String?] = [:], path: String = "/mcp", method: String = "POST") async -> RawResponse? {
        var h: [String: String?] = ["Host": "127.0.0.1:\(port)", "Content-Type": "application/json", "Content-Length": "\(body.utf8.count)"]
        if let token { h["Authorization"] = "Bearer \(token)" }
        for (k, v) in headers { h[k] = v }
        let lines = h.compactMap { k, v in v.map { "\(k): \($0)" } }.sorted()
        return await raw("\(method) \(path) HTTP/1.1\r\n" + lines.joined(separator: "\r\n") + "\r\n\r\n" + body)
    }

    func raw(_ request: String, wait: TimeInterval = 5) async -> RawResponse? {
        let port = self.port
        return await Task.detached { Self.exchange(port: port, request: request, wait: wait) }.value
    }

    /// Opens a connection and sends nothing more (to hold one of the connection slots).
    static func open(port: Int, send: String = "") -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        // The server answers 411/413 and closes while a big body is still being sent. Without this, the write to the
        // closed socket raises SIGPIPE, which ends the whole test process.
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_port = in_port_t(port).bigEndian; a.sin_addr.s_addr = inet_addr("127.0.0.1")
        let ok = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        if ok != 0 { close(fd); return -1 }
        if !send.isEmpty { _ = send.withCString { Darwin.send(fd, $0, strlen($0), 0) } }
        return fd
    }

    static func read(_ fd: Int32, wait: TimeInterval) -> RawResponse? {
        var tv = timeval(tv_sec: Int(wait), tv_usec: Int32((wait - floor(wait)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var data = Data(); var buf = [UInt8](repeating: 0, count: 65_536)
        while true { let n = recv(fd, &buf, buf.count, 0); if n <= 0 { break }; data.append(contentsOf: buf[0..<n]) }
        let text = String(decoding: data, as: UTF8.self)
        guard let split = text.range(of: "\r\n\r\n") else { return nil }
        var lines = text[..<split.lowerBound].components(separatedBy: "\r\n")
        let status = Int(lines.removeFirst().split(separator: " ").dropFirst().first ?? "") ?? 0
        var headers: [String: String] = [:]
        for l in lines { if let i = l.firstIndex(of: ":") { headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) } }
        return RawResponse(status: status, headers: headers, body: String(text[split.upperBound...]))
    }

    private static func exchange(port: Int, request: String, wait: TimeInterval) -> RawResponse? {
        let fd = open(port: port)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var sent = 0; let bytes = Array(request.utf8)
        while sent < bytes.count { let n = bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress! + sent, bytes.count - sent, 0) }; if n <= 0 { break }; sent += n }
        return read(fd, wait: wait)
    }
}
