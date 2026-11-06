import XCTest
@testable import MDEdit

/// Shared helpers. Every test that touches the disk or settings should use these, never the real ones.

/// A scratch folder that is removed when the test ends.
///
///     let s = try Scratch(["Notes/One.md": "# One", "pic.png": Data([1, 2, 3])])
///     addTeardownBlock { s.remove() }
final class Scratch {
    let url: URL
    private let fm = FileManager.default

    init(_ files: [String: Any] = [:]) throws {
        url = fm.temporaryDirectory.appendingPathComponent("mdedit-test-\(UUID().uuidString)").resolvingSymlinksInPath()
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        for (path, content) in files { try write(path, content) }
    }

    func path(_ rel: String) -> URL { url.appendingPathComponent(rel) }

    /// Writes a String (as UTF-8) or Data, creating folders as needed. A path ending in "/" makes a folder.
    @discardableResult
    func write(_ rel: String, _ content: Any = "") throws -> URL {
        let u = path(rel)
        if rel.hasSuffix("/") { try fm.createDirectory(at: u, withIntermediateDirectories: true); return u }
        try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        switch content {
        case let s as String: try Data(s.utf8).write(to: u)
        case let d as Data: try d.write(to: u)
        default: preconditionFailure("write a String or Data")
        }
        return u
    }

    func read(_ rel: String) throws -> String { try String(contentsOf: path(rel), encoding: .utf8) }
    func data(_ rel: String) throws -> Data { try Data(contentsOf: path(rel)) }
    func exists(_ rel: String) -> Bool { fm.fileExists(atPath: path(rel).path) }
    func remove() { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path); try? fm.removeItem(at: url) }
}

/// Settings that live in memory only. The app is never given `.standard` in a test.
func isolatedDefaults() -> UserDefaults {
    let name = "in.ranjeev.mdedit.test-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

extension XCTestCase {
    /// A workspace on its own settings and recent list, optionally with a folder already open.
    func makeWorkspace(open folder: URL? = nil, id: UUID? = nil) -> Workspace {
        let d = isolatedDefaults()
        let ws = Workspace(id: id, defaults: d, recents: RecentFolders(defaults: d))
        if let folder { ws.open(folder) }
        return ws
    }

    /// Fails when `body` takes longer than `budget` seconds. Budgets are loose (about 5x what a recent Mac needs):
    /// they catch a change that makes something slow by an order of magnitude, not noise.
    @discardableResult
    func within(_ budget: TimeInterval, _ label: String, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) rethrows -> TimeInterval {
        let start = Date()
        try body()
        let took = Date().timeIntervalSince(start)
        XCTAssertLessThan(took, budget, "\(label) took \(String(format: "%.2f", took))s, budget \(budget)s", file: file, line: line)
        return took
    }

    /// The same for an async body.
    @discardableResult
    func withinAsync(_ budget: TimeInterval, _ label: String, file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> Void) async rethrows -> TimeInterval {
        let start = Date()
        try await body()
        let took = Date().timeIntervalSince(start)
        XCTAssertLessThan(took, budget, "\(label) took \(String(format: "%.2f", took))s, budget \(budget)s", file: file, line: line)
        return took
    }
}

/// Repeatable randomness for fuzz tests: a failing seed can be replayed.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}
