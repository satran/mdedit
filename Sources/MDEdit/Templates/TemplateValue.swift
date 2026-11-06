import Foundation

/// The only kinds of value the engine knows. Nothing from Swift (no property, no method) can enter a template.
enum Value: Equatable {
    case text(String)
    case number(Int)
    case list([Value])
    case record([String: Value])
    case markup(String)
    case empty

    /// In `{% if %}`: empty, 0, empty text and an empty list are false.
    var isTrue: Bool {
        switch self {
        case .empty: return false
        case .number(let n): return n != 0
        case .text(let t): return !t.isEmpty
        case .list(let l): return !l.isEmpty
        case .record, .markup: return true
        }
    }

    var kind: String {
        switch self {
        case .text: return "text"
        case .number: return "number"
        case .list: return "list"
        case .record: return "record"
        case .markup: return "markup"
        case .empty: return "empty"
        }
    }
}

/// Why a render did not produce a page. `line` is the template line where there is one.
enum TemplateError: Error, Equatable {
    case syntax(String, line: Int?)
    case type(String, line: Int?)
    case limit(String, line: Int?)
    case timeout
    case cancelled
    /// The output holds a tag that could open a connection (step 3). `line` is a line of the rendered output.
    case unsafe(tag: String, line: Int?)

    var message: String {
        switch self {
        case .syntax(let m, _), .type(let m, _), .limit(let m, _): return m
        case .timeout: return "The template took too long and was stopped."
        case .cancelled: return "The render was cancelled."
        case .unsafe(let tag, _): return "The page contains \(tag), which could open a connection, so it is not shown."
        }
    }

    var line: Int? {
        switch self {
        case .syntax(_, let l), .type(_, let l), .limit(_, let l), .unsafe(_, let l): return l
        case .timeout, .cancelled: return nil
        }
    }

    var title: String {
        switch self {
        case .syntax: return "Template syntax error"
        case .type: return "Template type error"
        case .limit: return "Template limit reached"
        case .timeout: return "Template timed out"
        case .cancelled: return "Render cancelled"
        case .unsafe: return "Page not shown"
        }
    }
}

/// Set from any thread to ask a running render to stop.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func cancel() { lock.lock(); flag = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
