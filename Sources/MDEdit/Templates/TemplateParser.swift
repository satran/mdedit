import Foundation

enum Operand: Equatable {
    case string(String)
    case number(Int)
    case variable([String])

    var display: String {
        switch self {
        case .string(let s): return "\"\(s)\""
        case .number(let n): return String(n)
        case .variable(let p): return p.joined(separator: ".")
        }
    }
}

/// The filters. Arguments are values (a quoted text, a number or a variable).
enum Filter: Equatable {
    case defaultValue(Operand)
    case urlencode
    /// `markdown` or `markdown:base`: `base` is a folder that relative links and pictures in the text are made relative to.
    case markdown(base: Operand?)
    case length
    case daysUntil
    case daysSince
    case date(Operand)
    case week

    var name: String {
        switch self {
        case .defaultValue: return "default"
        case .urlencode: return "urlencode"
        case .markdown: return "markdown"
        case .length: return "length"
        case .daysUntil: return "days_until"
        case .daysSince: return "days_since"
        case .date: return "date"
        case .week: return "week"
        }
    }
}

/// An operand and the filters applied to it.
struct ValueExpr: Equatable {
    var operand: Operand
    var filters: [Filter] = []
    var display: String { ([operand.display] + filters.map(\.name)).joined(separator: "|") }
}

enum CompareOp: Equatable { case eq, ne, lt, le, gt, ge, within }

indirect enum Expr: Equatable {
    case value(ValueExpr)
    case compare(ValueExpr, CompareOp, ValueExpr)
    case not(Expr)
    case and(Expr, Expr)
    case or(Expr, Expr)
}

enum FilesSort: Equatable { case name, modified }

struct SortKey: Equatable { var path: [String]; var descending: Bool }
struct IncludeValue: Equatable { var name: String; var value: ValueExpr }

struct FilesClause: Equatable {
    var folder: ValueExpr
    var recursive = false
    var pages = false
    var match: ValueExpr?
    var sort = FilesSort.name
    var reverse = false
    var limit: ValueExpr?
}

indirect enum Node: Equatable {
    case text(String, line: Int)
    case print(ValueExpr, line: Int)
    case forLoop(variable: String, source: [String], body: [Node], empty: [Node], line: Int)
    case ifElse(Expr, body: [Node], otherwise: [Node], line: Int)
    case files(FilesClause, name: String, line: Int)
    case section(path: ValueExpr, heading: ValueExpr, name: String, line: Int)
    case meta(path: ValueExpr, name: String, line: Int)
    case tasks(path: ValueExpr, name: String, line: Int)
    case data(path: ValueExpr, name: String, line: Int)
    case include(path: ValueExpr, with: [IncludeValue], line: Int)
    case sortList(source: [String], keys: [SortKey], missingFirst: Bool, name: String, line: Int)
    case whereList(source: [String], key: [String], negate: Bool, op: CompareOp?, value: ValueExpr?, name: String, line: Int)
    case groupBy(source: [String], key: [String], name: String, line: Int)
}

/// Turns template text into a tree, accepting exactly the grammar of plan 006 and nothing else.
/// Anything outside it is a syntax error with a line number; limits on size, nodes and nesting are checked here.
enum TemplateParser {
    static let reserved: Set<String> = [
        "for", "in", "empty", "endfor", "if", "elif", "else", "endif", "and", "or", "not", "files", "section", "meta", "tasks", "data", "include",
        "sort", "where", "groupby", "verbatim", "endverbatim", "as", "reverse", "limit", "recursive", "pages", "match", "with",
        "today", "now", "query",
    ]

    static func parse(_ text: String, limits: TemplateLimits = .standard) -> Result<[Node], TemplateError> {
        if text.utf8.count > limits.templateBytes {
            return .failure(.limit("The template is larger than \(limits.templateBytes / 1024) KB.", line: nil))
        }
        var p = Parser(text: text, limits: limits)
        do {
            let (nodes, end) = try p.block(terminators: [])
            if let end { throw TemplateError.syntax("Unexpected {% \(end.word) %}.", line: end.line) }
            return .success(nodes)
        } catch let e as TemplateError {
            return .failure(e)
        } catch {
            return .failure(.syntax("Cannot read the template.", line: nil))
        }
    }

    // MARK: tokens

    private enum Token {
        case text(String, line: Int)
        case print(String, line: Int)
        case tag(String, line: Int)
    }

    enum Lexeme: Equatable { case word(String), string(String) }

    private struct Ended { let word: String; let line: Int; let args: [Lexeme] }

    private struct Parser {
        let limits: TemplateLimits
        var tokens: [Token] = []
        var index = 0
        var nodeCount = 0
        var blockDepth = 0
        var forDepth = 0
        var tokenError: TemplateError?

        init(text: String, limits: TemplateLimits) {
            self.limits = limits
            tokenize(text)
        }

        // Splits the text into text, `{{ }}` and `{% %}` pieces. Comments `{# #}` are dropped. A `{% %}` or `{{ }}` never spans a line
        // break. An HTML comment `<!-- -->` and a `{% verbatim %}` block are copied as they are, so they can hold braces.
        mutating func tokenize(_ text: String) {
            let chars = Array(text.unicodeScalars)
            var i = 0, line = 1
            var buffer = String.UnicodeScalarView()
            var bufferLine = 1
            func flush(_ tokens: inout [Token]) {
                if !buffer.isEmpty { tokens.append(.text(String(buffer), line: bufferLine)); buffer = String.UnicodeScalarView() }
            }
            func matches(_ s: String, at k: Int) -> Bool {
                let t = Array(s.unicodeScalars)
                guard k + t.count <= chars.count else { return false }
                for j in 0..<t.count where chars[k + j] != t[j] { return false }
                return true
            }
            while i < chars.count {
                let c = chars[i]
                if c == "<", matches("<!--", at: i) {
                    // an HTML comment is text: copy to its end
                    if buffer.isEmpty { bufferLine = line }
                    var j = i + 4
                    while j < chars.count, !matches("-->", at: j) { if chars[j] == "\n" { line += 1 }; j += 1 }
                    let end = min(chars.count, j + 3)
                    buffer.append(contentsOf: chars[i..<end])
                    i = end
                    continue
                }
                if c == "{", i + 1 < chars.count, "{%#".unicodeScalars.contains(chars[i + 1]) {
                    let open = chars[i + 1]
                    let close: Unicode.Scalar = open == "{" ? "}" : open
                    flush(&tokens)
                    let startLine = line
                    var j = i + 2
                    var inner = String.UnicodeScalarView()
                    var found = false
                    while j < chars.count {
                        if chars[j] == close, j + 1 < chars.count, chars[j + 1] == "}" { found = true; break }
                        if chars[j] == "\n" {
                            if open == "#" { line += 1 } else {
                                tokenError = tokenError ?? .syntax("A tag cannot span a line break.", line: startLine); return
                            }
                        }
                        inner.append(chars[j]); j += 1
                    }
                    if !found {
                        let what = open == "{" ? "{{" : open == "%" ? "{%" : "{#"
                        tokenError = tokenError ?? .syntax("\(what) is never closed.", line: startLine); return
                    }
                    let content = String(inner)
                    i = j + 2
                    switch open {
                    case "{": tokens.append(.print(content, line: startLine))
                    case "%":
                        if content.trimmingCharacters(in: .whitespaces) == "verbatim" {
                            // copy everything up to {% endverbatim %} as text
                            var raw = String.UnicodeScalarView()
                            var k = i, endFound = false
                            let rawLine = line
                            while k < chars.count {
                                if chars[k] == "{", chars.count > k + 1, chars[k + 1] == "%" {
                                    var m = k + 2, word = ""
                                    while m < chars.count, chars[m] != "%", chars[m] != "\n" { word.unicodeScalars.append(chars[m]); m += 1 }
                                    if m + 1 < chars.count, chars[m] == "%", chars[m + 1] == "}", word.trimmingCharacters(in: .whitespaces) == "endverbatim" {
                                        k = m + 2; endFound = true; break
                                    }
                                }
                                if chars[k] == "\n" { line += 1 }
                                raw.append(chars[k]); k += 1
                            }
                            if !endFound { tokenError = tokenError ?? .syntax("{% verbatim %} is never closed with {% endverbatim %}.", line: startLine); return }
                            if !raw.isEmpty { tokens.append(.text(String(raw), line: rawLine)) }
                            i = k
                        } else { tokens.append(.tag(content, line: startLine)) }
                    default: break
                    }
                    bufferLine = line
                } else {
                    if buffer.isEmpty { bufferLine = line }
                    buffer.append(c)
                    if c == "\n" { line += 1 }
                    i += 1
                }
            }
            flush(&tokens)
        }

        // MARK: blocks

        mutating func count(_ line: Int) throws {
            nodeCount += 1
            if nodeCount > limits.nodes { throw TemplateError.limit("The template has more than \(limits.nodes) parts.", line: line) }
        }

        /// Parses until one of the `terminators` tag words (or the end). Returns the nodes and the terminator that ended them.
        mutating func block(terminators: Set<String>) throws -> ([Node], Ended?) {
            if let e = tokenError { throw e }
            var nodes: [Node] = []
            while index < tokens.count {
                let token = tokens[index]
                index += 1
                switch token {
                case .text(let t, let line):
                    try count(line)
                    nodes.append(.text(t, line: line))
                case .print(let content, let line):
                    try count(line)
                    nodes.append(try printNode(content, line: line))
                case .tag(let content, let line):
                    let words = try lex(content, line: line)
                    guard let first = words.first, case .word(let word) = first else {
                        throw TemplateError.syntax("An empty or malformed tag.", line: line)
                    }
                    if terminators.contains(word) {
                        if word != "elif" { guard words.count == 1 else { throw TemplateError.syntax("{% \(word) %} takes no arguments.", line: line) } }
                        return (nodes, Ended(word: word, line: line, args: Array(words.dropFirst())))
                    }
                    try count(line)
                    nodes.append(try tagNode(word, Array(words.dropFirst()), line: line))
                }
            }
            return (nodes, nil)
        }

        mutating func enter(_ line: Int, isFor: Bool) throws {
            blockDepth += 1
            if blockDepth > limits.blockDepth { throw TemplateError.limit("Blocks are nested more than \(limits.blockDepth) deep.", line: line) }
            if isFor {
                forDepth += 1
                if forDepth > limits.forDepth { throw TemplateError.limit("Loops are nested more than \(limits.forDepth) deep.", line: line) }
            }
        }

        mutating func leave(isFor: Bool) { blockDepth -= 1; if isFor { forDepth -= 1 } }

        mutating func tagNode(_ word: String, _ args: [Lexeme], line: Int) throws -> Node {
            switch word {
            case "for":
                guard args.count == 3, case .word(let v) = args[0], case .word(let kw) = args[1], kw == "in", case .word(let src) = args[2],
                      isPlainName(v), let source = path(src) else { throw TemplateError.syntax("A loop looks like {% for x in list %}.", line: line) }
                try enter(line, isFor: true)
                let (body, end1) = try block(terminators: ["empty", "endfor"])
                var emptyBody: [Node] = []
                var end = end1
                if end1?.word == "empty" { (emptyBody, end) = try block(terminators: ["endfor"]) }
                leave(isFor: true)
                guard end?.word == "endfor" else { throw TemplateError.syntax("{% for %} is never closed with {% endfor %}.", line: line) }
                return .forLoop(variable: v, source: source, body: body, empty: emptyBody, line: line)
            case "if":
                try enter(line, isFor: false)
                let node = try ifChain(try expression(args, line: line), line: line)
                leave(isFor: false)
                return node
            case "files": return try filesNode(args, line: line)
            case "section":
                guard args.count == 4, case .word("as") = args[2], case .word(let name) = args[3] else {
                    throw TemplateError.syntax("A section looks like {% section path heading as name %}.", line: line)
                }
                try checkTarget(name, line: line)
                return .section(path: try value(args[0], line: line), heading: try value(args[1], line: line), name: name, line: line)
            case "meta", "tasks", "data":
                guard args.count == 3, case .word("as") = args[1], case .word(let name) = args[2] else {
                    throw TemplateError.syntax("{% \(word) path as name %} is the form of this tag.", line: line)
                }
                try checkTarget(name, line: line)
                let p = try value(args[0], line: line)
                switch word {
                case "meta": return .meta(path: p, name: name, line: line)
                case "tasks": return .tasks(path: p, name: name, line: line)
                default: return .data(path: p, name: name, line: line)
                }
            case "include": return try includeNode(args, line: line)
            case "sort": return try sortNode(args, line: line)
            case "where": return try whereNode(args, line: line)
            case "groupby":
                guard args.count == 5, case .word(let list) = args[0], let source = path(list), case .word("by") = args[1], case .string(let key) = args[2],
                      let kp = path(key), case .word("as") = args[3], case .word(let name) = args[4] else {
                    throw TemplateError.syntax("{% groupby list by \"key\" as name %} is the form of this tag.", line: line)
                }
                try checkTarget(name, line: line)
                return .groupBy(source: source, key: kp, name: name, line: line)
            case "empty", "else", "endfor", "endif", "elif", "endverbatim":
                throw TemplateError.syntax("Unexpected {% \(word) %}.", line: line)
            default:
                throw TemplateError.syntax("Unknown tag {% \(word) %}.", line: line)
            }
        }

        /// `if` and its `elif`/`else` branches, up to the one `endif`.
        mutating func ifChain(_ cond: Expr, line: Int) throws -> Node {
            let (body, end) = try block(terminators: ["elif", "else", "endif"])
            guard let end else { throw TemplateError.syntax("{% if %} is never closed with {% endif %}.", line: line) }
            switch end.word {
            case "elif":
                try count(end.line)
                let next = try ifChain(try expression(end.args, line: end.line), line: end.line)
                return .ifElse(cond, body: body, otherwise: [next], line: line)
            case "else":
                let (otherwise, end2) = try block(terminators: ["endif"])
                guard end2?.word == "endif" else { throw TemplateError.syntax("{% if %} is never closed with {% endif %}.", line: line) }
                return .ifElse(cond, body: body, otherwise: otherwise, line: line)
            default:
                return .ifElse(cond, body: body, otherwise: [], line: line)
            }
        }

        func filesNode(_ args: [Lexeme], line: Int) throws -> Node {
            let usage = "A listing looks like {% files folder [recursive] [pages] [match pattern] [sort \"name\"|\"modified\"] [reverse] [limit N] as name %}."
            guard args.count >= 3 else { throw TemplateError.syntax(usage, line: line) }
            var c = FilesClause(folder: try value(args[0], line: line))
            var i = 1
            if i < args.count, case .word("recursive") = args[i] { c.recursive = true; i += 1 }
            if i < args.count, case .word("pages") = args[i] { c.pages = true; i += 1 }
            if i < args.count, case .word("match") = args[i] {
                guard i + 1 < args.count else { throw TemplateError.syntax(usage, line: line) }
                c.match = try value(args[i + 1], line: line); i += 2
            }
            if i < args.count, case .word("sort") = args[i] {
                guard i + 1 < args.count, case .string(let s) = args[i + 1], s == "name" || s == "modified" else {
                    throw TemplateError.syntax("sort is \"name\" or \"modified\".", line: line)
                }
                c.sort = s == "name" ? .name : .modified
                i += 2
            }
            if i < args.count, case .word("reverse") = args[i] { c.reverse = true; i += 1 }
            if i < args.count, case .word("limit") = args[i] {
                guard i + 1 < args.count else { throw TemplateError.syntax(usage, line: line) }
                c.limit = try value(args[i + 1], line: line); i += 2
            }
            guard i + 2 == args.count, case .word("as") = args[i], case .word(let name) = args[i + 1] else { throw TemplateError.syntax(usage, line: line) }
            try checkTarget(name, line: line)
            return .files(c, name: name, line: line)
        }

        func includeNode(_ args: [Lexeme], line: Int) throws -> Node {
            let usage = "An include looks like {% include path [with name=value ...] %}."
            guard let first = args.first else { throw TemplateError.syntax(usage, line: line) }
            let p = try value(first, line: line)
            var bindings: [IncludeValue] = []
            if args.count > 1 {
                guard case .word("with") = args[1], args.count > 2 else { throw TemplateError.syntax(usage, line: line) }
                for a in args.dropFirst(2) {
                    guard case .word(let w) = a, let eq = w.firstIndex(of: "="), isPlainName(String(w[..<eq])), !w[..<eq].hasSuffix("_error") else {
                        throw TemplateError.syntax("with takes name=value pairs.", line: line)
                    }
                    bindings.append(IncludeValue(name: String(w[..<eq]), value: try valueText(String(w[w.index(after: eq)...]), line: line)))
                }
                if bindings.count > 8 { throw TemplateError.limit("An include takes at most 8 values.", line: line) }
            }
            return .include(path: p, with: bindings, line: line)
        }

        func sortNode(_ args: [Lexeme], line: Int) throws -> Node {
            let usage = "A sort looks like {% sort list by \"key\" [desc] [\"key2\" [desc]] [missing first|last] as name %}."
            guard args.count >= 5, case .word(let list) = args[0], let source = path(list), case .word("by") = args[1] else { throw TemplateError.syntax(usage, line: line) }
            var i = 2
            var keys: [SortKey] = []
            while i < args.count, case .string(let k) = args[i] {
                guard let kp = path(k) else { throw TemplateError.syntax("\"\(k)\" is not a key.", line: line) }
                i += 1
                var desc = false
                if i < args.count, case .word(let d) = args[i], d == "desc" || d == "asc" { desc = d == "desc"; i += 1 }
                keys.append(SortKey(path: kp, descending: desc))
            }
            guard !keys.isEmpty, keys.count <= 4 else { throw TemplateError.syntax(usage, line: line) }
            var missingFirst = false
            if i + 1 < args.count, case .word("missing") = args[i] {
                guard case .word(let w) = args[i + 1], w == "first" || w == "last" else { throw TemplateError.syntax(usage, line: line) }
                missingFirst = w == "first"; i += 2
            }
            guard i + 2 == args.count, case .word("as") = args[i], case .word(let name) = args[i + 1] else { throw TemplateError.syntax(usage, line: line) }
            try checkTarget(name, line: line)
            return .sortList(source: source, keys: keys, missingFirst: missingFirst, name: name, line: line)
        }

        func whereNode(_ args: [Lexeme], line: Int) throws -> Node {
            let usage = "A filter looks like {% where list [not] key [== value] as name %} (== != < <= > >= in)."
            guard args.count >= 4, case .word(let list) = args[0], let source = path(list) else { throw TemplateError.syntax(usage, line: line) }
            var i = 1
            var negate = false
            if case .word("not") = args[i] { negate = true; i += 1 }
            guard i < args.count, case .word(let k) = args[i], let key = path(k) else { throw TemplateError.syntax(usage, line: line) }
            i += 1
            var op: CompareOp?
            var v: ValueExpr?
            if i + 2 < args.count, case .word(let o) = args[i], let parsed = Self.compareOp(o) {
                op = parsed; v = try value(args[i + 1], line: line); i += 2
            }
            guard i + 2 == args.count, case .word("as") = args[i], case .word(let name) = args[i + 1] else { throw TemplateError.syntax(usage, line: line) }
            try checkTarget(name, line: line)
            return .whereList(source: source, key: key, negate: negate, op: op, value: v, name: name, line: line)
        }

        func checkTarget(_ name: String, line: Int) throws {
            guard isPlainName(name), !name.hasSuffix("_error") else {
                throw TemplateError.syntax("\"\(name)\" cannot be used as a name here.", line: line)
            }
        }

        // MARK: expressions

        static func compareOp(_ w: String) -> CompareOp? {
            switch w { case "==": return .eq; case "!=": return .ne; case "<": return .lt; case "<=": return .le; case ">": return .gt; case ">=": return .ge; case "in": return .within; default: return nil }
        }

        /// `or` binds loosest, then `and`, then `not`, then a comparison of two values.
        func expression(_ args: [Lexeme], line: Int) throws -> Expr {
            var i = 0
            let e = try parseOr(args, &i, line)
            guard i == args.count else { throw TemplateError.syntax("A condition is values joined by == != < <= > >= in, and, or, not.", line: line) }
            return e
        }

        func parseOr(_ a: [Lexeme], _ i: inout Int, _ line: Int) throws -> Expr {
            var l = try parseAnd(a, &i, line)
            while i < a.count, case .word("or") = a[i] { i += 1; l = .or(l, try parseAnd(a, &i, line)) }
            return l
        }

        func parseAnd(_ a: [Lexeme], _ i: inout Int, _ line: Int) throws -> Expr {
            var l = try parseNot(a, &i, line)
            while i < a.count, case .word("and") = a[i] { i += 1; l = .and(l, try parseNot(a, &i, line)) }
            return l
        }

        func parseNot(_ a: [Lexeme], _ i: inout Int, _ line: Int) throws -> Expr {
            if i < a.count, case .word("not") = a[i] { i += 1; return .not(try parseNot(a, &i, line)) }
            guard i < a.count else { throw TemplateError.syntax("A condition ends too soon.", line: line) }
            let left = try value(a[i], line: line)
            i += 1
            if i < a.count, case .word(let w) = a[i], let op = Self.compareOp(w) {
                i += 1
                guard i < a.count else { throw TemplateError.syntax("\(w) needs a value after it.", line: line) }
                let right = try value(a[i], line: line)
                i += 1
                return .compare(left, op, right)
            }
            return .value(left)
        }

        // MARK: print

        func printNode(_ content: String, line: Int) throws -> Node {
            // one value and its filters, with spaces allowed around the `|`
            let trimmed = content.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            guard !trimmed.isEmpty else { throw TemplateError.syntax("{{ }} holds one value and its filters.", line: line) }
            return .print(try valueText(trimmed, line: line), line: line)
        }

        /// Splits at `|` that are not inside a quoted string.
        func splitFilters(_ s: String) -> [String] {
            var out: [String] = [], cur = ""
            var inString = false, escaped = false
            for c in s {
                if inString {
                    cur.append(c)
                    if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                } else if c == "|" { out.append(cur); cur = "" }
                else { if c == "\"" { inString = true }; cur.append(c) }
            }
            out.append(cur)
            return out
        }

        // MARK: operands

        /// Words are runs without spaces or tabs outside quotes; a quoted string on its own is a string. `\"` and `\\` are the only escapes.
        func lex(_ s: String, line: Int) throws -> [Lexeme] {
            var out: [Lexeme] = []
            let chars = Array(s)
            var i = 0
            /// Reads the quoted text that starts at `start`; returns its text and the index after the closing quote.
            func readString(_ start: Int) throws -> (String, Int) {
                var str = ""
                var j = start + 1
                while j < chars.count {
                    if chars[j] == "\\" {
                        guard j + 1 < chars.count, chars[j + 1] == "\"" || chars[j + 1] == "\\" else { throw TemplateError.syntax("Only \\\" and \\\\ can follow a backslash.", line: line) }
                        str.append(chars[j + 1]); j += 2
                    } else if chars[j] == "\"" { return (str, j + 1) }
                    else { str.append(chars[j]); j += 1 }
                }
                throw TemplateError.syntax("A quoted text is never closed.", line: line)
            }
            while i < chars.count {
                let c = chars[i]
                if c == " " || c == "\t" { i += 1; continue }
                if c == "\"" {
                    let (str, end) = try readString(i)
                    if end >= chars.count || chars[end] == " " || chars[end] == "\t" { out.append(.string(str)); i = end; continue }
                }
                // a word, which may hold quoted strings (`name|default:"a b"`)
                var w = ""
                while i < chars.count, chars[i] != " ", chars[i] != "\t" {
                    if chars[i] == "\"" {
                        let (_, end) = try readString(i)
                        w += String(chars[i..<end])
                        i = end
                    } else { w.append(chars[i]); i += 1 }
                }
                out.append(.word(w))
            }
            return out
        }

        func value(_ l: Lexeme, line: Int) throws -> ValueExpr {
            switch l {
            case .string(let s): return ValueExpr(operand: .string(s))
            case .word(let w): return try valueText(w, line: line)
            }
        }

        /// A word that may carry filters: `name`, `name|length`, `"text"|default:"x"`.
        func valueText(_ w: String, line: Int) throws -> ValueExpr {
            let parts = splitFilters(w)
            let head = try lex(parts[0], line: line)
            guard head.count == 1 else { throw TemplateError.syntax("\"\(w)\" is not a value.", line: line) }
            var v = ValueExpr(operand: try operand(head[0], line: line))
            for raw in parts.dropFirst() { v.filters.append(try filter(raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t")), line: line)) }
            return v
        }

        func filter(_ f: String, line: Int) throws -> Filter {
            let name: String, arg: String?
            if let colon = firstColonOutsideQuotes(f) { name = String(f[..<colon]); arg = String(f[f.index(after: colon)...]) } else { name = f; arg = nil }
            func argument() throws -> Operand {
                guard let arg, !arg.isEmpty else { throw TemplateError.syntax("\(name) needs a value, as \(name):\"x\".", line: line) }
                let l = try lex(arg, line: line)
                guard l.count == 1 else { throw TemplateError.syntax("\(name) takes one value.", line: line) }
                return try operand(l[0], line: line)
            }
            func none() throws { if arg != nil { throw TemplateError.syntax("\(name) takes no value.", line: line) } }
            switch name {
            case "default": return .defaultValue(try argument())
            case "urlencode": try none(); return .urlencode
            case "markdown": return .markdown(base: arg == nil ? nil : try argument())
            case "length": try none(); return .length
            case "days_until": try none(); return .daysUntil
            case "days_since": try none(); return .daysSince
            case "date": return .date(try argument())
            case "week": try none(); return .week
            default: throw TemplateError.syntax("Unknown filter \"\(f)\".", line: line)
            }
        }

        func firstColonOutsideQuotes(_ s: String) -> String.Index? {
            var inString = false, escaped = false
            for i in s.indices {
                let c = s[i]
                if inString { if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false } }
                else if c == "\"" { inString = true } else if c == ":" { return i }
            }
            return nil
        }

        func operand(_ l: Lexeme, line: Int) throws -> Operand {
            switch l {
            case .string(let s): return .string(s)
            case .word(let w):
                if let first = w.unicodeScalars.first, first.properties.numericType != nil || first == "-" {
                    let digits = w.hasPrefix("-") ? String(w.dropFirst()) : w
                    guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw TemplateError.syntax("\"\(w)\" is not a whole number.", line: line) }
                    guard digits.count <= limits.digits, let n = Int(w) else { throw TemplateError.limit("A number has more than \(limits.digits) digits.", line: line) }
                    return .number(n)
                }
                guard let p = path(w) else { throw TemplateError.syntax("\"\(w)\" is not a value.", line: line) }
                return .variable(p)
            }
        }

        func isPlainName(_ s: String) -> Bool {
            guard let f = s.unicodeScalars.first, f.isASCII, f.properties.isAlphabetic || f == "_" else { return false }
            return s.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || $0 == "_" || ("0"..."9").contains($0)) } && !TemplateParser.reserved.contains(s)
        }

        /// A dotted path of names. The words `today`, `now` and `query` are variables, so they are allowed as the first part.
        func path(_ s: String) -> [String]? {
            let parts = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard let head = parts.first else { return nil }
            let headOK = ["today", "now", "query"].contains(head) || isPlainName(head)
            return headOK && parts.dropFirst().allSatisfy({ isKey($0) }) ? parts : nil
        }

        /// After the first part a key may be a reserved word too (`m.in`, `t.match`): it is only a record key.
        func isKey(_ s: String) -> Bool {
            guard let f = s.unicodeScalars.first, f.isASCII, f.properties.isAlphabetic || f == "_" else { return false }
            return s.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || $0 == "_" || ("0"..."9").contains($0)) }
        }
    }
}
