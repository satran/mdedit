import XCTest
@testable import MDEdit

/// Rendering helpers for the template tests.
enum T {
    /// 2026-11-06, a Friday, at noon in the local time zone.
    static let friday: Date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12))!

    static func run(_ template: String, in s: Scratch, limits: TemplateLimits = .standard, source: TemplateSource? = nil, cancel: CancelFlag = CancelFlag(),
                    now: Date = Date(), query: [String: String] = [:]) -> Result<String, TemplateError> {
        TemplateEvaluator.run(text: template, root: s.url, cancel: cancel, limits: limits, source: source, now: now, query: query)
    }

    /// The page, failing the test when the render failed.
    static func page(_ template: String, in s: Scratch, limits: TemplateLimits = .standard, source: TemplateSource? = nil, now: Date = Date(), query: [String: String] = [:],
                     file: StaticString = #filePath, line: UInt = #line) -> String {
        switch run(template, in: s, limits: limits, source: source, now: now, query: query) {
        case .success(let p): return p
        case .failure(let e): XCTFail("render failed: \(e.message)", file: file, line: line); return ""
        }
    }

    static func error(_ template: String, in s: Scratch, limits: TemplateLimits = .standard, source: TemplateSource? = nil, file: StaticString = #filePath, line: UInt = #line) -> TemplateError? {
        switch run(template, in: s, limits: limits, source: source) {
        case .success(let p): XCTFail("expected an error, got a page: \(p.prefix(80))", file: file, line: line); return nil
        case .failure(let e): return e
        }
    }

    static func isLimit(_ e: TemplateError?) -> Bool { if case .limit = e { return true }; return false }
    static func isSyntax(_ e: TemplateError?) -> Bool { if case .syntax = e { return true }; return false }
    static func isType(_ e: TemplateError?) -> Bool { if case .type = e { return true }; return false }

    /// A SHA-256 of every file and the list of paths: equal before and after means nothing changed.
    static func fingerprint(_ s: Scratch) -> String {
        var lines: [String] = []
        let fm = FileManager.default
        if let it = fm.enumerator(at: s.url, includingPropertiesForKeys: nil, options: []) {
            for case let u as URL in it {
                let rel = String(u.path.dropFirst(s.url.path.count))
                let d = (try? Data(contentsOf: u)).map { ContentHash.sha256(String(decoding: $0, as: UTF8.self)) } ?? "-"
                lines.append(rel + " " + d)
            }
        }
        return lines.sorted().joined(separator: "\n")
    }
}

/// A source that sleeps (as a read blocked on a stalled volume would) and can run a hook.
final class SlowSource: TemplateSource {
    let delay: TimeInterval
    var onList: (() -> Void)?
    init(delay: TimeInterval) { self.delay = delay }
    private func wait(_ budget: Budget) throws { try budget.checkNow(); Thread.sleep(forTimeInterval: delay) }
    func list(_ folder: String, options: FilesOptions, budget: Budget) throws -> (items: [Value], error: String) {
        try wait(budget); onList?()
        return ([.record(["name": .text("x"), "path": .text("x.md"), "title": .text("x")])], "")
    }
    func section(_ path: String, _ heading: String, budget: Budget) throws -> (text: String, error: String) { try wait(budget); return ("slow", "") }
    func meta(_ path: String, budget: Budget) throws -> (meta: Value, error: String) { try wait(budget); return (.record([:]), "") }
    func tasks(_ path: String, budget: Budget) throws -> (items: [Value], error: String) { try wait(budget); return ([], "") }
    func data(_ path: String, budget: Budget) throws -> (meta: Value, error: String) { try wait(budget); return (.empty, "") }
    func include(_ path: String, budget: Budget) throws -> (text: String, error: String) { try wait(budget); return ("", "") }
    func wikiTarget(_ name: String, budget: Budget) throws -> String? { try wait(budget); return nil }
}
