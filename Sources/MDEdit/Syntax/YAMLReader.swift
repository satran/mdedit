import Foundation

/// A small YAML reader: block maps and lists, `key: value` with the value on the line or below, `- item`, `- key: value` list items that
/// are maps, flow lists `[a, b]`, quoted and plain scalars, block scalars `|` and `>`, comments. No anchors, tags, merge keys, flow maps
/// or multiple documents (the first document is read). It exists to show a file as a table and to read data into a template.
/// Input is bounded: at most 20,000 lines, 20 levels, 5,000 entries; anything it cannot read gives nil.
indirect enum YAMLNode: Equatable {
    case scalar(String)
    case list([YAMLNode])
    case map([Entry])

    struct Entry: Equatable { var key: String; var value: YAMLNode }
}

enum YAMLReader {
    static let maxLines = 20_000
    static let maxDepth = 20
    static let maxEntries = 5_000

    private struct Line { var indent: Int; var text: String; var raw: String }

    static func parse(_ source: String) -> YAMLNode? {
        var lines: [Line] = []
        var started = false
        for raw in source.components(separatedBy: "\n").prefix(maxLines + 1) {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed.hasPrefix("--- ") { if started { break } else { started = true; continue } }
            if trimmed == "..." { break }
            lines.append(Line(indent: line.prefix(while: { $0 == " " }).count, text: stripComment(line.trimmingCharacters(in: .whitespaces)), raw: line))
            started = true
        }
        guard lines.count <= maxLines else { return nil }
        var p = Parser(lines: lines)
        p.skipBlank()
        guard p.i < lines.count else { return nil }
        guard let node = try? p.block(indent: p.lines[p.i].indent, depth: 0), p.rest() else { return nil }
        return node
    }

    /// Removes a `# comment` that is not inside quotes and starts a word.
    static func stripComment(_ s: String) -> String {
        guard s.contains("#") else { return s }
        var inSingle = false, inDouble = false
        var prev: Character = " "
        for (i, c) in s.enumerated() {
            if c == "'" && !inDouble { inSingle.toggle() }
            else if c == "\"" && !inSingle { inDouble.toggle() }
            else if c == "#" && !inSingle && !inDouble && (prev == " " || prev == "\t" || i == 0) {
                return String(s.prefix(i)).trimmingCharacters(in: .whitespaces)
            }
            prev = c
        }
        return s
    }

    struct Failure: Error {}

    private struct Parser {
        let lines: [Line]
        var i = 0
        var entries = 0
        init(lines: [Line]) { self.lines = lines }

        mutating func skipBlank() { while i < lines.count, lines[i].text.isEmpty { i += 1 } }
        mutating func rest() -> Bool { skipBlank(); return i >= lines.count }

        mutating func block(indent: Int, depth: Int) throws -> YAMLNode {
            if depth > YAMLReader.maxDepth { throw Failure() }
            skipBlank()
            guard i < lines.count, lines[i].indent == indent else { throw Failure() }
            return isItem(lines[i].text) ? try list(indent: indent, depth: depth) : try map(indent: indent, depth: depth)
        }

        func isItem(_ t: String) -> Bool { t == "-" || t.hasPrefix("- ") }

        mutating func list(indent: Int, depth: Int) throws -> YAMLNode {
            var items: [YAMLNode] = []
            while true {
                skipBlank()
                guard i < lines.count, lines[i].indent == indent, isItem(lines[i].text) else { break }
                entries += 1
                if entries > YAMLReader.maxEntries { throw Failure() }
                let after = lines[i].text == "-" ? "" : String(lines[i].text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if after.isEmpty {
                    i += 1
                    skipBlank()
                    if i < lines.count, lines[i].indent > indent { items.append(try block(indent: lines[i].indent, depth: depth + 1)) } else { items.append(.scalar("")) }
                } else if Self.keyValue(after) != nil, !after.hasPrefix("\""), !after.hasPrefix("'"), !after.hasPrefix("[") {
                    // `- key: value`: a map whose first key sits on the item's line
                    let inner = indent + (lines[i].text.count - after.count)
                    var copy = lines
                    copy[i] = Line(indent: inner, text: after, raw: after)
                    var sub = Parser(lines: copy); sub.i = i; sub.entries = entries
                    let node = try sub.map(indent: inner, depth: depth + 1)
                    i = sub.i; entries = sub.entries
                    items.append(node)
                } else {
                    i += 1
                    items.append(try scalarOrFlow(after, indent: indent))
                }
            }
            return .list(items)
        }

        mutating func map(indent: Int, depth: Int) throws -> YAMLNode {
            var out: [YAMLNode.Entry] = []
            while true {
                skipBlank()
                guard i < lines.count, lines[i].indent == indent, !isItem(lines[i].text) else { break }
                guard let (key, value) = Self.keyValue(lines[i].text) else { throw Failure() }
                entries += 1
                if entries > YAMLReader.maxEntries { throw Failure() }
                i += 1
                if value.isEmpty {
                    skipBlank()
                    if i < lines.count, lines[i].indent > indent { out.append(.init(key: key, value: try block(indent: lines[i].indent, depth: depth + 1))) }
                    else if i < lines.count, lines[i].indent == indent, isItem(lines[i].text) { out.append(.init(key: key, value: try list(indent: indent, depth: depth + 1))) }
                    else { out.append(.init(key: key, value: .scalar(""))) }
                } else {
                    out.append(.init(key: key, value: try scalarOrFlow(value, indent: indent)))
                }
            }
            return .map(out)
        }

        /// A plain, quoted, flow-list or block scalar value that started on the line just read.
        mutating func scalarOrFlow(_ v: String, indent: Int) throws -> YAMLNode {
            if v == "|" || v == ">" || v.hasPrefix("|") || v.hasPrefix(">") {
                var parts: [String] = []
                var base: Int?
                while i < lines.count {
                    let l = lines[i]
                    if l.raw.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(""); i += 1; continue }
                    guard l.indent > indent else { break }
                    base = base ?? l.indent
                    parts.append(String(l.raw.dropFirst(min(base ?? 0, l.indent))))
                    i += 1
                }
                while parts.last == "" { parts.removeLast() }
                return .scalar(parts.joined(separator: v.hasPrefix("|") ? "\n" : " "))
            }
            if v.hasPrefix("["), v.hasSuffix("]") {
                let inner = String(v.dropFirst().dropLast())
                return .list(Self.splitFlow(inner).map { .scalar(Self.unquote($0)) })
            }
            return .scalar(Self.unquote(v))
        }

        static func splitFlow(_ s: String) -> [String] {
            var out: [String] = [], cur = ""
            var q: Character?
            for c in s {
                if let open = q { cur.append(c); if c == open { q = nil } }
                else if c == "\"" || c == "'" { q = c; cur.append(c) }
                else if c == "," { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
                else { cur.append(c) }
            }
            if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur.trimmingCharacters(in: .whitespaces)) }
            return out
        }

        static func unquote(_ s: String) -> String {
            if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
                return String(s.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\\", with: "\\")
            }
            if s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") { return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
            return s
        }

        /// `key: value` or `key:`; the key may be quoted. nil when the line is not a mapping entry.
        static func keyValue(_ t: String) -> (String, String)? {
            var key = "", rest = Substring(t)
            if t.hasPrefix("\"") || t.hasPrefix("'") {
                let q = t.first!
                guard let end = t.dropFirst().firstIndex(of: q) else { return nil }
                key = String(t[t.index(after: t.startIndex)..<end])
                rest = t[t.index(after: end)...]
                guard rest.hasPrefix(":") else { return nil }
                rest = rest.dropFirst()
            } else {
                var idx = t.startIndex
                var found = false
                while idx < t.endIndex {
                    if t[idx] == ":" { let n = t.index(after: idx); if n == t.endIndex || t[n] == " " || t[n] == "\t" { found = true; break } }
                    idx = t.index(after: idx)
                }
                guard found else { return nil }
                key = String(t[..<idx]).trimmingCharacters(in: .whitespaces)
                rest = t[t.index(after: idx)...]
            }
            guard !key.isEmpty else { return nil }
            return (key, rest.trimmingCharacters(in: .whitespaces))
        }
    }
}
