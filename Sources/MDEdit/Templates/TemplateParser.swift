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

enum Filter: Equatable {
    case defaultText(String)
    case urlencode
    case markdown
}

enum Condition: Equatable {
    case truth(Operand)
    case equal(Operand, Operand)
    case notEqual(Operand, Operand)
}

enum FilesSort: Equatable { case name, modified }

indirect enum Node: Equatable {
    case text(String, line: Int)
    case print(Operand, [Filter], line: Int)
    case forLoop(variable: String, source: [String], body: [Node], empty: [Node], line: Int)
    case ifElse(Condition, body: [Node], otherwise: [Node], line: Int)
    case files(folder: Operand, sort: FilesSort, reverse: Bool, limit: Operand?, name: String, line: Int)
    case section(path: Operand, heading: Operand, name: String, line: Int)
}

/// Turns template text into a tree, accepting exactly the grammar of plan 006 and nothing else.
/// Anything outside it is a syntax error with a line number; limits on size, nodes and nesting are checked here.
enum TemplateParser {
    static let reserved: Set<String> = ["for", "in", "empty", "endfor", "if", "else", "endif", "files", "section", "as", "sort", "reverse", "limit"]

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

    private struct Ended { let word: String; let line: Int }

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

        // Splits the text into text, `{{ }}` and `{% %}` pieces. Comments are dropped. A piece never spans a line break.
        mutating func tokenize(_ text: String) {
            let chars = Array(text.unicodeScalars)
            var i = 0, line = 1
            var buffer = String.UnicodeScalarView()
            var bufferLine = 1
            func flush(_ tokens: inout [Token]) {
                if !buffer.isEmpty { tokens.append(.text(String(buffer), line: bufferLine)); buffer = String.UnicodeScalarView() }
            }
            while i < chars.count {
                let c = chars[i]
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
                    switch open {
                    case "{": tokens.append(.print(content, line: startLine))
                    case "%": tokens.append(.tag(content, line: startLine))
                    default: break
                    }
                    i = j + 2
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
                        guard words.count == 1 else { throw TemplateError.syntax("{% \(word) %} takes no arguments.", line: line) }
                        return (nodes, Ended(word: word, line: line))
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
                let cond = try condition(args, line: line)
                try enter(line, isFor: false)
                let (body, end1) = try block(terminators: ["else", "endif"])
                var otherwise: [Node] = []
                var end = end1
                if end1?.word == "else" { (otherwise, end) = try block(terminators: ["endif"]) }
                leave(isFor: false)
                guard end?.word == "endif" else { throw TemplateError.syntax("{% if %} is never closed with {% endif %}.", line: line) }
                return .ifElse(cond, body: body, otherwise: otherwise, line: line)
            case "files":
                return try filesNode(args, line: line)
            case "section":
                guard args.count == 4, case .word(let kw) = args[2], kw == "as", case .word(let name) = args[3] else {
                    throw TemplateError.syntax("A section looks like {% section path heading as name %}.", line: line)
                }
                try checkTarget(name, line: line)
                return .section(path: try operand(args[0], line: line), heading: try operand(args[1], line: line), name: name, line: line)
            case "empty", "else", "endfor", "endif":
                throw TemplateError.syntax("Unexpected {% \(word) %}.", line: line)
            default:
                throw TemplateError.syntax("Unknown tag {% \(word) %}.", line: line)
            }
        }

        mutating func filesNode(_ args: [Lexeme], line: Int) throws -> Node {
            let usage = "A listing looks like {% files folder [sort \"name\"|\"modified\"] [reverse] [limit N] as name %}."
            guard args.count >= 3 else { throw TemplateError.syntax(usage, line: line) }
            var i = 1
            let folder = try operand(args[0], line: line)
            var sort = FilesSort.name, reverse = false
            var limit: Operand?
            if i < args.count, case .word("sort") = args[i] {
                guard i + 1 < args.count, case .string(let s) = args[i + 1], s == "name" || s == "modified" else {
                    throw TemplateError.syntax("sort is \"name\" or \"modified\".", line: line)
                }
                sort = s == "name" ? .name : .modified
                i += 2
            }
            if i < args.count, case .word("reverse") = args[i] { reverse = true; i += 1 }
            if i < args.count, case .word("limit") = args[i] {
                guard i + 1 < args.count else { throw TemplateError.syntax(usage, line: line) }
                limit = try operand(args[i + 1], line: line)
                i += 2
            }
            guard i + 2 == args.count, case .word("as") = args[i], case .word(let name) = args[i + 1] else { throw TemplateError.syntax(usage, line: line) }
            try checkTarget(name, line: line)
            return .files(folder: folder, sort: sort, reverse: reverse, limit: limit, name: name, line: line)
        }

        func checkTarget(_ name: String, line: Int) throws {
            guard isPlainName(name), !name.hasSuffix("_error") else {
                throw TemplateError.syntax("\"\(name)\" cannot be used as a name here.", line: line)
            }
        }

        func condition(_ args: [Lexeme], line: Int) throws -> Condition {
            let usage = "A condition is one value, or two values joined by == or !=."
            switch args.count {
            case 1: return .truth(try operand(args[0], line: line))
            case 3:
                guard case .word(let op) = args[1], op == "==" || op == "!=" else { throw TemplateError.syntax(usage, line: line) }
                let l = try operand(args[0], line: line), r = try operand(args[2], line: line)
                return op == "==" ? .equal(l, r) : .notEqual(l, r)
            default: throw TemplateError.syntax(usage, line: line)
            }
        }

        // MARK: print

        func printNode(_ content: String, line: Int) throws -> Node {
            let parts = splitFilters(content)
            let lexemes = try lex(parts[0], line: line)
            guard lexemes.count == 1 else { throw TemplateError.syntax("{{ }} holds one value and its filters.", line: line) }
            let value = try operand(lexemes[0], line: line)
            var filters: [Filter] = []
            for raw in parts.dropFirst() {
                let f = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
                if f == "urlencode" { filters.append(.urlencode) }
                else if f == "markdown" { filters.append(.markdown) }
                else if f.hasPrefix("default") {
                    let rest = f.dropFirst("default".count).trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
                    guard rest.hasPrefix(":") else { throw TemplateError.syntax("default needs a text, as default:\"none\".", line: line) }
                    let arg = try lex(String(rest.dropFirst()), line: line)
                    guard arg.count == 1, case .string(let s) = arg[0] else { throw TemplateError.syntax("default needs a quoted text.", line: line) }
                    filters.append(.defaultText(s))
                } else { throw TemplateError.syntax("Unknown filter \"\(f)\".", line: line) }
            }
            return .print(value, filters, line: line)
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

        enum Lexeme: Equatable { case word(String), string(String) }

        /// Words are runs without spaces or tabs; a quoted string may hold spaces. `\"` and `\\` are the only escapes.
        func lex(_ s: String, line: Int) throws -> [Lexeme] {
            var out: [Lexeme] = []
            let chars = Array(s)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c == " " || c == "\t" { i += 1; continue }
                if c == "\"" {
                    var str = ""
                    i += 1
                    var closed = false
                    while i < chars.count {
                        if chars[i] == "\\" {
                            guard i + 1 < chars.count, chars[i + 1] == "\"" || chars[i + 1] == "\\" else { throw TemplateError.syntax("Only \\\" and \\\\ can follow a backslash.", line: line) }
                            str.append(chars[i + 1]); i += 2
                        } else if chars[i] == "\"" { closed = true; i += 1; break }
                        else { str.append(chars[i]); i += 1 }
                    }
                    if !closed { throw TemplateError.syntax("A quoted text is never closed.", line: line) }
                    out.append(.string(str))
                } else {
                    var w = ""
                    while i < chars.count, chars[i] != " ", chars[i] != "\t" { w.append(chars[i]); i += 1 }
                    out.append(.word(w))
                }
            }
            return out
        }

        func operand(_ l: Lexeme, line: Int) throws -> Operand {
            switch l {
            case .string(let s): return .string(s)
            case .word(let w):
                if let first = w.unicodeScalars.first, first.properties.numericType != nil || first == "-" {
                    guard !w.hasPrefix("-"), w.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw TemplateError.syntax("\"\(w)\" is not a whole number.", line: line) }
                    guard w.count <= limits.digits, let n = Int(w) else { throw TemplateError.limit("A number has more than \(limits.digits) digits.", line: line) }
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

        func path(_ s: String) -> [String]? {
            let parts = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard !parts.isEmpty, parts.allSatisfy({ isPlainName($0) }) else { return nil }
            return parts
        }
    }
}
