import Foundation

/// The task lines of a note (`- [ ] text` and `- [x] text`) as records, for `{% tasks path as ts %}`.
///
/// Each record: `done` ("true" or empty), `text` (the line without its `@name(value)` attributes), `raw` (the line after the box), `line`
/// (the line number in the file), `indent`, `is_sub` ("true" when indented), `attrs` (a record of the attributes) and `context` (the
/// lines below the task that are indented deeper and are not tasks themselves, up to a blank line; empty when there are none).
enum TemplateTasks {
    private static let taskLine = try! NSRegularExpression(pattern: "^([ \\t]*)[-*+][ \\t]+\\[([ xX])\\](?:[ \\t]+(.*))?$")
    private static let attribute = try! NSRegularExpression(pattern: "@([A-Za-z_][A-Za-z0-9_]*)\\(([^()\\n]*)\\)")
    static let maxContextLines = 20
    static let maxContextBytes = 2_048

    private static func indent(_ s: String) -> Int {
        var n = 0
        for c in s { if c == " " { n += 1 } else if c == "\t" { n += 4 } else { break } }
        return n
    }

    static func parse(_ text: String, maxItems: Int) -> [Value] {
        var lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        // the properties block at the top is not part of the note's tasks (its lines stay numbered)
        var skip = 0
        if let fm = FrontMatter.parse(text) { skip = (text as NSString).substring(to: fm.end).components(separatedBy: "\n").count - 1 }
        for i in 0..<min(skip, lines.count) { lines[i] = "" }

        func task(_ i: Int) -> (indent: Int, done: Bool, rest: String)? {
            let l = lines[i]
            let ns = l as NSString
            guard let m = taskLine.firstMatch(in: l, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let mark = ns.substring(with: m.range(at: 2))
            let rest = m.range(at: 3).location == NSNotFound ? "" : ns.substring(with: m.range(at: 3))
            return (indent(ns.substring(with: m.range(at: 1))), mark != " ", rest)
        }

        var out: [Value] = []
        var fence: String?
        var i = 0
        while i < lines.count, out.count < maxItems {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                let f = String(t.prefix(3))
                if fence == nil { fence = f } else if fence == f { fence = nil }
                i += 1; continue
            }
            guard fence == nil, let k = task(i) else { i += 1; continue }
            // attributes
            let ns = k.rest as NSString
            var attrs: [String: Value] = [:]
            var plain = k.rest
            for m in attribute.matches(in: k.rest, range: NSRange(location: 0, length: ns.length)).reversed() {
                attrs[ns.substring(with: m.range(at: 1))] = .text(ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces))
                if let r = Range(m.range, in: plain) { plain.removeSubrange(r) }
            }
            let words = plain.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
            // context
            var ctx: [String] = [], bytes = 0
            var j = i + 1
            while j < lines.count, ctx.count < maxContextLines {
                let l = lines[j]
                if l.trimmingCharacters(in: .whitespaces).isEmpty || indent(l) <= k.indent || task(j) != nil { break }
                let cut = l.trimmingCharacters(in: .whitespaces)
                bytes += cut.utf8.count
                if bytes > maxContextBytes { break }
                ctx.append(cut); j += 1
            }
            out.append(.record([
                "done": k.done ? .text("true") : .empty, "text": .text(words), "raw": .text(k.rest.trimmingCharacters(in: .whitespaces)),
                "line": .number(i + 1), "indent": .number(k.indent), "is_sub": k.indent > 0 ? .text("true") : .empty,
                "attrs": .record(attrs), "context": ctx.isEmpty ? .empty : .text(ctx.joined(separator: "\n")),
            ]))
            i += 1
        }
        return out
    }
}
