import Foundation
import Markdown

/// What one render has used so far. `charge()` is called for every node and loop pass; every 1,024 steps (and at every source call)
/// it checks the clock and the cancel flag, so a template cannot run past its budget.
final class Budget {
    let limits: TemplateLimits
    let cancel: CancelFlag
    private let deadline: Date
    private(set) var steps = 0
    private var nextCheck = 1_024
    var bytesRead = 0
    var entriesRead = 0

    init(limits: TemplateLimits, cancel: CancelFlag) {
        self.limits = limits; self.cancel = cancel
        deadline = Date().addingTimeInterval(limits.clock)
    }

    func charge(_ n: Int = 1) throws {
        steps += n
        if steps > limits.steps { throw TemplateError.limit("The template needed more than \(limits.steps) steps.", line: nil) }
        if steps >= nextCheck { nextCheck = steps + 1_024; try checkNow() }
    }

    func checkNow() throws {
        if cancel.isCancelled { throw TemplateError.cancelled }
        if Date() > deadline { throw TemplateError.timeout }
    }
}

enum TemplateEvaluator {
    /// Parses and runs a template on a background task. The result is the page, or why there is none.
    static func render(text: String, root: URL, cancel: CancelFlag, limits: TemplateLimits = .standard, source: TemplateSource? = nil) async -> Result<String, TemplateError> {
        await Task.detached(priority: .userInitiated) {
            run(text: text, root: root, cancel: cancel, limits: limits, source: source)
        }.value
    }

    /// The same, on the calling thread.
    static func run(text: String, root: URL, cancel: CancelFlag, limits: TemplateLimits = .standard, source: TemplateSource? = nil) -> Result<String, TemplateError> {
        let nodes: [Node]
        switch TemplateParser.parse(text, limits: limits) {
        case .success(let n): nodes = n
        case .failure(let e): return .failure(e)
        }
        let budget = Budget(limits: limits, cancel: cancel)
        let interp = Interpreter(budget: budget, source: source ?? TemplateSources(root: root))
        do {
            try budget.checkNow()
            try interp.run(nodes)
            // layer 3 of the containment: a tag that could open a connection means no page
            if let unsafe = TemplateOutputGuard.check(interp.out) { return .failure(unsafe) }
            return .success(interp.out)
        } catch let e as TemplateError {
            return .failure(e)
        } catch {
            return .failure(.syntax("The template could not be run.", line: nil))
        }
    }
}

private final class Interpreter {
    let budget: Budget
    let source: TemplateSource
    var vars: [String: Value] = [:]
    var out = ""
    private var outBytes = 0

    init(budget: Budget, source: TemplateSource) { self.budget = budget; self.source = source }

    func append(_ s: String) throws {
        let n = s.utf8.count
        if outBytes + n > budget.limits.outputBytes { throw TemplateError.limit("The page is larger than \(budget.limits.outputBytes / 1_048_576) MB.", line: nil) }
        outBytes += n
        out += s
    }

    func run(_ nodes: [Node]) throws {
        for node in nodes {
            try budget.charge()
            switch node {
            case .text(let t, _): try append(t)
            case .print(let operand, let filters, let line): try print(operand, filters, line: line)
            case .forLoop(let variable, let source, let body, let empty, let line): try loop(variable, source, body, empty, line: line)
            case .ifElse(let cond, let body, let otherwise, let line): try run(try truth(cond, line: line) ? body : otherwise)
            case .files(let folder, let sort, let reverse, let limit, let name, let line): try files(folder, sort, reverse, limit, name, line: line)
            case .section(let path, let heading, let name, let line): try section(path, heading, name, line: line)
            case .meta(let path, let name, let line): try meta(path, name, line: line)
            }
        }
    }

    // MARK: values

    func value(_ o: Operand) -> Value {
        switch o {
        case .string(let s): return .text(s)
        case .number(let n): return .number(n)
        case .variable(let p): return lookup(p)
        }
    }

    func lookup(_ path: [String]) -> Value {
        var v = vars[path[0]] ?? .empty
        for key in path.dropFirst() {
            guard case .record(let r) = v else { return .empty }
            v = r[key] ?? .empty
        }
        return v
    }

    func text(_ o: Operand, what: String, line: Int) throws -> String {
        switch value(o) {
        case .text(let t): return t
        case .empty: return ""
        case let v: throw TemplateError.type("\(o.display) is \(v.kind), but \(what) needs text.", line: line)
        }
    }

    // MARK: print and filters

    func print(_ operand: Operand, _ filters: [Filter], line: Int) throws {
        var v = value(operand)
        for f in filters {
            try budget.charge()
            switch f {
            case .defaultText(let d):
                if case .empty = v { v = .text(d) } else if case .text(let t) = v, t.isEmpty { v = .text(d) }
            case .urlencode:
                switch v {
                case .text(let t): v = .text(Self.urlencode(t))
                case .empty: v = .text("")
                default: throw TemplateError.type("\(operand.display) is \(v.kind), but urlencode needs text.", line: line)
                }
            case .markdown:
                let t: String
                switch v {
                case .text(let s): t = s
                case .empty: t = ""
                default: throw TemplateError.type("\(operand.display) is \(v.kind), but markdown needs text.", line: line)
                }
                try budget.charge(t.utf8.count / 256)
                v = .markup(SafeHTML.render(Document(parsing: MarkdownLimits.clamp(t), options: [.disableSmartOpts]), preview: false))
            }
        }
        switch v {
        case .text(let t): try append(SafeHTML.escape(t))
        case .markup(let m): try append(m)
        case .number(let n): try append(String(n))
        case .empty: break
        case .list, .record: throw TemplateError.type("\(operand.display) is a \(v.kind) and cannot be printed.", line: line)
        }
    }

    /// Percent-encodes everything except letters, digits, `-._~` and `/`.
    static func urlencode(_ s: String) -> String {
        var out = ""
        for b in s.utf8 {
            let c = Character(Unicode.Scalar(b))
            if b < 0x80, c.isLetter || c.isNumber || "-._~/".contains(c) { out.append(c) } else { out += String(format: "%%%02X", b) }
        }
        return out
    }

    // MARK: control

    func truth(_ c: Condition, line: Int) throws -> Bool {
        switch c {
        case .truth(let o): return value(o).isTrue
        case .equal(let a, let b): return value(a) == value(b)
        case .notEqual(let a, let b): return value(a) != value(b)
        }
    }

    func loop(_ variable: String, _ sourcePath: [String], _ body: [Node], _ empty: [Node], line: Int) throws {
        let items: [Value]
        switch lookup(sourcePath) {
        case .empty: items = []
        case .list(let l): items = l
        case let v: throw TemplateError.type("\(sourcePath.joined(separator: ".")) is \(v.kind), but a loop needs a list.", line: line)
        }
        if items.isEmpty { try run(empty); return }
        let previous = vars[variable]
        defer { vars[variable] = previous }
        for item in items {
            try budget.charge()
            vars[variable] = item
            try run(body)
        }
    }

    func files(_ folder: Operand, _ sort: FilesSort, _ reverse: Bool, _ limit: Operand?, _ name: String, line: Int) throws {
        let f = try text(folder, what: "a folder", line: line)
        var n: Int?
        if let limit {
            switch value(limit) {
            case .number(let k): n = k
            case let v: throw TemplateError.type("\(limit.display) is \(v.kind), but limit needs a number.", line: line)
            }
        }
        let r = try source.list(f, sort: sort, reverse: reverse, limit: n, budget: budget)
        vars[name] = .list(r.items)
        vars[name + "_error"] = r.error.isEmpty ? .empty : .text(r.error)
    }

    func meta(_ path: Operand, _ name: String, line: Int) throws {
        let p = try text(path, what: "a path", line: line)
        let r = try source.meta(p, budget: budget)
        vars[name] = r.meta
        vars[name + "_error"] = r.error.isEmpty ? .empty : .text(r.error)
    }

    func section(_ path: Operand, _ heading: Operand, _ name: String, line: Int) throws {
        let p = try text(path, what: "a path", line: line)
        let h = try text(heading, what: "a heading", line: line)
        let r = try source.section(p, h, budget: budget)
        vars[name] = .text(r.text)
        vars[name + "_error"] = r.error.isEmpty ? .empty : .text(r.error)
    }
}
