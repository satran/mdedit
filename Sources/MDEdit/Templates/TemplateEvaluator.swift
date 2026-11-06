import Foundation

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
    /// Parses and runs a template on a background task. The result is the page, or why there is none. `now` is the time `today` and `now`
    /// stand for; `query` holds the parameters of the link that was clicked.
    static func render(text: String, root: URL, cancel: CancelFlag, limits: TemplateLimits = .standard, source: TemplateSource? = nil,
                       now: Date = Date(), query: [String: String] = [:]) async -> Result<String, TemplateError> {
        await Task.detached(priority: .userInitiated) {
            run(text: text, root: root, cancel: cancel, limits: limits, source: source, now: now, query: query)
        }.value
    }

    /// The same, on the calling thread.
    static func run(text: String, root: URL, cancel: CancelFlag, limits: TemplateLimits = .standard, source: TemplateSource? = nil,
                    now: Date = Date(), query: [String: String] = [:]) -> Result<String, TemplateError> {
        let nodes: [Node]
        switch TemplateParser.parse(text, limits: limits) {
        case .success(let n): nodes = n
        case .failure(let e): return .failure(e)
        }
        let budget = Budget(limits: limits, cancel: cancel)
        let interp = Interpreter(budget: budget, source: source ?? TemplateSources(root: root), now: now, query: query)
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
    let now: Date
    var vars: [String: Value] = [:]
    var out = ""
    private var outBytes = 0
    private var includeDepth = 0
    private var includesRun = 0
    private var includeCache: [String: [Node]] = [:]
    private var wikiCache: [String: String?] = [:]

    init(budget: Budget, source: TemplateSource, now: Date, query: [String: String]) {
        self.budget = budget; self.source = source; self.now = now
        vars["today"] = .text(TemplateDates.today(now))
        vars["now"] = .text(TemplateDates.nowText(now))
        vars["query"] = .record(query.mapValues { .text($0) })
    }

    var limits: TemplateLimits { budget.limits }

    func append(_ s: String) throws {
        let n = s.utf8.count
        if outBytes + n > limits.outputBytes { throw TemplateError.limit("The page is larger than \(limits.outputBytes / 1_048_576) MB.", line: nil) }
        outBytes += n
        out += s
    }

    func run(_ nodes: [Node]) throws {
        for node in nodes {
            try budget.charge()
            switch node {
            case .text(let t, _): try append(t)
            case .print(let v, let line): try print(v, line: line)
            case .forLoop(let variable, let source, let body, let empty, let line): try loop(variable, source, body, empty, line: line)
            case .ifElse(let cond, let body, let otherwise, let line): try run(try truth(cond, line: line) ? body : otherwise)
            case .files(let clause, let name, let line): try files(clause, name, line: line)
            case .section(let path, let heading, let name, let line): try section(path, heading, name, line: line)
            case .meta(let path, let name, let line): try readOne(path, name, line: line) { try self.source.meta($0, budget: self.budget) }
            case .tasks(let path, let name, let line): try readOne(path, name, line: line) { p in
                let r = try self.source.tasks(p, budget: self.budget); return (Value.list(r.items), r.error) }
            case .data(let path, let name, let line): try readOne(path, name, line: line) { try self.source.data($0, budget: self.budget) }
            case .include(let path, let with, let line): try include(path, with, line: line)
            case .sortList(let src, let keys, let missingFirst, let name, let line): try sortList(src, keys, missingFirst, name, line: line)
            case .whereList(let src, let key, let negate, let op, let value, let name, let line): try whereList(src, key, negate, op, value, name, line: line)
            case .groupBy(let src, let key, let name, let line): try groupBy(src, key, name, line: line)
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

    func lookup(_ path: [String]) -> Value { Self.valueAt(vars[path[0]] ?? .empty, Array(path.dropFirst())) }

    static func valueAt(_ v: Value, _ path: [String]) -> Value {
        var v = v
        for key in path {
            guard case .record(let r) = v else { return .empty }
            v = r[key] ?? .empty
        }
        return v
    }

    func eval(_ e: ValueExpr, line: Int) throws -> Value {
        var v = value(e.operand)
        for f in e.filters { try budget.charge(); v = try apply(f, v, shown: e.operand.display, line: line) }
        return v
    }

    func text(_ e: ValueExpr, what: String, line: Int) throws -> String {
        switch try eval(e, line: line) {
        case .text(let t): return t
        case .empty: return ""
        case let v: throw TemplateError.type("\(e.display) is \(v.kind), but \(what) needs text.", line: line)
        }
    }

    // MARK: filters

    func apply(_ f: Filter, _ v: Value, shown: String, line: Int) throws -> Value {
        func textOrEmpty(_ what: String) throws -> String {
            switch v {
            case .text(let s): return s
            case .empty: return ""
            default: throw TemplateError.type("\(shown) is \(v.kind), but \(what) needs text.", line: line)
            }
        }
        switch f {
        case .defaultValue(let d):
            if case .empty = v { return value(d) }
            if case .text(let t) = v, t.isEmpty { return value(d) }
            return v
        case .urlencode:
            return .text(Self.urlencode(try textOrEmpty("urlencode")))
        case .markdown(let base):
            let t = try textOrEmpty("markdown")
            try budget.charge(t.utf8.count / 256)
            var baseText: String?
            if let base { if case .text(let b) = value(base), !b.isEmpty { baseText = b } }
            return .markup(TemplateMarkdown.render(t, base: baseText, wiki: { self.wikiTarget($0) }))
        case .length:
            switch v {
            case .text(let s): return .number(s.count)
            case .list(let l): return .number(l.count)
            case .record(let r): return .number(r.count)
            case .empty: return .number(0)
            default: throw TemplateError.type("\(shown) is \(v.kind), but length needs text, a list or a record.", line: line)
            }
        case .daysUntil, .daysSince:
            guard case .text(let s) = v, let d = TemplateDates.parse(s) else { return .empty }
            return .number(f == .daysUntil ? TemplateDates.days(from: now, to: d) : TemplateDates.days(from: d, to: now))
        case .week:
            guard case .text(let s) = v, let d = TemplateDates.parse(s) else { return .empty }
            return .text(TemplateDates.week(d))
        case .date(let pattern):
            guard case .text(let s) = v, let d = TemplateDates.parse(s) else { return .empty }
            guard case .text(let p) = value(pattern), let shownDate = TemplateDates.format(d, pattern: p) else {
                throw TemplateError.type("The date format must be text of letters, digits, spaces and - / . , :, up to 40 characters.", line: line)
            }
            return .text(shownDate)
        }
    }

    /// The path of the note a wiki link stands for, looked up once per name.
    func wikiTarget(_ name: String) -> String? {
        if let cached = wikiCache[name] { return cached }
        let r = (try? source.wikiTarget(name, budget: budget)) ?? nil
        wikiCache[name] = .some(r)
        return r
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

    // MARK: print

    func print(_ e: ValueExpr, line: Int) throws {
        let v = try eval(e, line: line)
        switch v {
        case .text(let t): try append(SafeHTML.escape(t))
        case .markup(let m): try append(m)
        case .number(let n): try append(String(n))
        case .empty: break
        case .list, .record: throw TemplateError.type("\(e.display) is a \(v.kind) and cannot be printed.", line: line)
        }
    }

    // MARK: conditions

    func truth(_ e: Expr, line: Int) throws -> Bool {
        try budget.charge()
        switch e {
        case .value(let v): return try eval(v, line: line).isTrue
        case .compare(let a, let op, let b): return compare(op, try eval(a, line: line), try eval(b, line: line))
        case .not(let x): return !(try truth(x, line: line))
        case .and(let a, let b): return try truth(a, line: line) ? try truth(b, line: line) : false
        case .or(let a, let b): return try truth(a, line: line) ? true : try truth(b, line: line)
        }
    }

    /// `==` and `!=` compare any two values (different types are never equal). `<` `<=` `>` `>=` compare two numbers or two texts
    /// (dates written `yyyy-MM-dd` compare correctly as text); anything else, an empty value included, is false. `in` is a substring of
    /// a text, a member of a list or a key of a record.
    func compare(_ op: CompareOp, _ a: Value, _ b: Value) -> Bool {
        // an empty value and empty text are the same thing, so `done == ""` finds a task that is not done
        func norm(_ v: Value) -> Value { if case .text(let t) = v, t.isEmpty { return .empty }; return v }
        switch op {
        case .eq: return norm(a) == norm(b)
        case .ne: return norm(a) != norm(b)
        case .lt, .le, .gt, .ge:
            let order: ComparisonResult
            switch (a, b) {
            case (.number(let x), .number(let y)): order = x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
            case (.text(let x), .text(let y)): order = x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
            default: return false
            }
            switch op {
            case .lt: return order == .orderedAscending
            case .le: return order != .orderedDescending
            case .gt: return order == .orderedDescending
            default: return order != .orderedAscending
            }
        case .within:
            switch (a, b) {
            case (.text(let x), .text(let y)): return !x.isEmpty && y.contains(x)
            case (_, .list(let l)): return l.contains(a)
            case (.text(let x), .record(let r)): return r[x] != nil
            default: return false
            }
        }
    }

    // MARK: control

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

    func list(_ path: [String], line: Int) throws -> [Value] {
        switch lookup(path) {
        case .empty: return []
        case .list(let l): return l
        case let v: throw TemplateError.type("\(path.joined(separator: ".")) is \(v.kind), but a list is needed.", line: line)
        }
    }

    func files(_ c: FilesClause, _ name: String, line: Int) throws {
        let folder = try text(c.folder, what: "a folder", line: line)
        var o = FilesOptions(sort: c.sort, reverse: c.reverse, limit: nil, recursive: c.recursive, pages: c.pages, match: nil)
        if let limit = c.limit {
            switch try eval(limit, line: line) {
            case .number(let k): o.limit = k
            case let v: throw TemplateError.type("\(limit.display) is \(v.kind), but limit needs a number.", line: line)
            }
        }
        if let m = c.match {
            let pattern = try text(m, what: "a pattern", line: line)
            if pattern.count > limits.patternLength { throw TemplateError.type("A match pattern is at most \(limits.patternLength) characters.", line: line) }
            o.match = pattern
        }
        let r = try source.list(folder, options: o, budget: budget)
        vars[name] = .list(r.items)
        vars[name + "_error"] = r.error.isEmpty ? .empty : .text(r.error)
    }

    func section(_ path: ValueExpr, _ heading: ValueExpr, _ name: String, line: Int) throws {
        let p = try text(path, what: "a path", line: line)
        let h = try text(heading, what: "a heading", line: line)
        let r = try source.section(p, h, budget: budget)
        vars[name] = .text(r.text)
        vars[name + "_error"] = r.error.isEmpty ? .empty : .text(r.error)
    }

    /// `meta`, `tasks` and `data`: one path in, a value and a reason out.
    func readOne(_ path: ValueExpr, _ name: String, line: Int, _ read: (String) throws -> (Value, String)) throws {
        let p = try text(path, what: "a path", line: line)
        let r = try read(p)
        vars[name] = r.0
        vars[name + "_error"] = r.1.isEmpty ? .empty : .text(r.1)
    }

    // MARK: include

    func include(_ path: ValueExpr, _ with: [IncludeValue], line: Int) throws {
        let p = try text(path, what: "a path", line: line)
        if includeDepth >= limits.includeDepth { throw TemplateError.limit("Includes are nested more than \(limits.includeDepth) deep.", line: line) }
        includesRun += 1
        if includesRun > limits.includes { throw TemplateError.limit("More than \(limits.includes) includes in one render.", line: line) }
        let nodes: [Node]
        if let cached = includeCache[p] { nodes = cached } else {
            let r = try source.include(p, budget: budget)
            guard r.error.isEmpty else { throw TemplateError.syntax("Cannot include \"\(p)\": \(r.error).", line: line) }
            switch TemplateParser.parse(r.text, limits: limits) {
            case .success(let n): nodes = n
            case .failure(let e): throw Self.wrap(e, p, line)
            }
            includeCache[p] = nodes
        }
        // the values are worked out first, then bound for the length of the include
        var bound: [(String, Value)] = []
        for b in with { bound.append((b.name, try eval(b.value, line: line))) }
        let previous = bound.map { ($0.0, vars[$0.0]) }
        for (n, v) in bound { vars[n] = v }
        includeDepth += 1
        defer { includeDepth -= 1; for (n, old) in previous { vars[n] = old } }
        do { try run(nodes) } catch let e as TemplateError { throw Self.wrap(e, p, line) }
    }

    /// An error in an included file is reported at the include, with the file named.
    static func wrap(_ e: TemplateError, _ path: String, _ line: Int) -> TemplateError {
        switch e {
        case .syntax(let m, let l): return .syntax("In \(path)\(l.map { " (line \($0))" } ?? ""): \(m)", line: line)
        case .type(let m, let l): return .type("In \(path)\(l.map { " (line \($0))" } ?? ""): \(m)", line: line)
        case .limit(let m, let l): return .limit("In \(path)\(l.map { " (line \($0))" } ?? ""): \(m)", line: line)
        default: return e
        }
    }

    // MARK: sort, where, groupby

    private static func missing(_ v: Value) -> Bool {
        switch v { case .empty: return true; case .text(let t): return t.isEmpty; case .number, .markup: return false; default: return true }
    }

    /// Numbers before texts; numbers by value, texts in natural order.
    private static func order(_ a: Value, _ b: Value) -> ComparisonResult {
        switch (a, b) {
        case (.number(let x), .number(let y)): return x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
        case (.number, _): return .orderedAscending
        case (_, .number): return .orderedDescending
        case (.text(let x), .text(let y)): return x.localizedStandardCompare(y)
        default: return .orderedSame
        }
    }

    func sortList(_ src: [String], _ keys: [SortKey], _ missingFirst: Bool, _ name: String, line: Int) throws {
        let items = try list(src, line: line)
        var n = 1
        while (1 << n) < max(items.count, 2) { n += 1 }
        try budget.charge(items.count * n)
        let keyed = items.enumerated().map { i, item in (i, item, keys.map { Self.valueAt(item, $0.path) }) }
        let sorted = keyed.sorted { a, b in
            for (k, key) in keys.enumerated() {
                let x = a.2[k], y = b.2[k]
                let mx = Self.missing(x), my = Self.missing(y)
                if mx || my {
                    if mx && my { continue }
                    return mx == missingFirst
                }
                var o = Self.order(x, y)
                if key.descending { o = o == .orderedAscending ? .orderedDescending : o == .orderedDescending ? .orderedAscending : .orderedSame }
                if o != .orderedSame { return o == .orderedAscending }
            }
            return a.0 < b.0
        }
        vars[name] = .list(sorted.map(\.1))
    }

    func whereList(_ src: [String], _ key: [String], _ negate: Bool, _ op: CompareOp?, _ value: ValueExpr?, _ name: String, line: Int) throws {
        let items = try list(src, line: line)
        try budget.charge(items.count)
        let rhs = try value.map { try eval($0, line: line) }
        let kept = items.filter { item in
            let v = Self.valueAt(item, key)
            var pass = op.map { compare($0, v, rhs ?? .empty) } ?? v.isTrue
            if negate { pass.toggle() }
            return pass
        }
        vars[name] = .list(kept)
    }

    func groupBy(_ src: [String], _ key: [String], _ name: String, line: Int) throws {
        let items = try list(src, line: line)
        try budget.charge(items.count)
        var order: [String] = [], groups: [String: [Value]] = [:]
        for item in items {
            let k: String
            switch Self.valueAt(item, key) { case .text(let t): k = t; case .number(let n): k = String(n); default: k = "" }
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(item)
        }
        vars[name] = .list(order.map { k in .record(["key": .text(k), "items": .list(groups[k] ?? []), "count": .number(groups[k]?.count ?? 0)]) })
    }
}
