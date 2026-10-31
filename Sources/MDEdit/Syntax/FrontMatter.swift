import Foundation

/// The YAML block at the top of a note (between two `---` lines): its properties, shown as a table in View mode.
struct FrontMatter: Equatable {
    enum Value: Equatable {
        case text(String)
        case list([String])
        case bool(Bool)
    }
    struct Property: Equatable {
        var key: String
        var value: Value
    }

    var properties: [Property]
    /// UTF-16 offset of the first character after the closing `---` line.
    var end: Int

    private static let keyLine = try! NSRegularExpression(pattern: "^([^\\s#:\\-][^:]*?)\\s*:(?:\\s+(.*))?$")

    /// nil when the text does not start with a block of `key: value` lines between `---` lines.
    static func parse(_ text: String) -> FrontMatter? {
        let ns = text as NSString
        var lines: [(text: String, end: Int)] = []
        var at = 0
        while at < ns.length, lines.count < 400 {
            let r = ns.lineRange(for: NSRange(location: at, length: 0))
            lines.append((ns.substring(with: r).trimmingCharacters(in: .newlines).trimmingCharacters(in: CharacterSet(charactersIn: " \t\r")), NSMaxRange(r)))
            at = NSMaxRange(r)
        }
        let first = lines.first?.text.replacingOccurrences(of: "\u{FEFF}", with: "")
        guard first == "---", let close = lines.dropFirst().firstIndex(where: { $0.text == "---" || $0.text == "..." }) else { return nil }
        // the lines between the dashes, with their indentation (nesting needs it)
        let body = (1..<close).map { i -> String in
            let start = lines[i - 1].end
            return ns.substring(with: NSRange(location: start, length: lines[i].end - start)).trimmingCharacters(in: .newlines).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        }

        var props: [Property] = []
        var i = 0
        while i < body.count {
            let line = body[i]
            i += 1
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty, !line.hasPrefix("#"), !line.hasPrefix(" "), !line.hasPrefix("\t"), !line.hasPrefix("-") else { continue }
            let lns = line as NSString
            guard let m = keyLine.firstMatch(in: line, range: NSRange(location: 0, length: lns.length)) else { continue }
            let key = lns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let rest = m.range(at: 2).location == NSNotFound ? "" : lns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                var items: [String] = [], nested: [String] = []
                while i < body.count {
                    let l = body[i]
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if t.isEmpty { i += 1; continue }
                    guard l.hasPrefix(" ") || l.hasPrefix("\t") || l.hasPrefix("-") else { break }
                    if t.hasPrefix("- ") || t == "-" { items.append(unquote(String(t.dropFirst(1)).trimmingCharacters(in: .whitespaces))) } else { nested.append(t) }
                    i += 1
                }
                if !items.isEmpty { props.append(Property(key: key, value: .list(items))) }
                else if !nested.isEmpty { props.append(Property(key: key, value: .text(nested.joined(separator: "\n")))) }
                else { props.append(Property(key: key, value: .text(""))) }
            } else if rest.hasPrefix("["), rest.hasSuffix("]"), !rest.hasPrefix("[[") {
                let inner = rest.dropFirst().dropLast()
                props.append(Property(key: key, value: .list(inner.split(separator: ",").map { unquote($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty })))
            } else if rest.lowercased() == "true" || rest.lowercased() == "false" {
                props.append(Property(key: key, value: .bool(rest.lowercased() == "true")))
            } else {
                props.append(Property(key: key, value: .text(unquote(rest))))
            }
        }
        guard !props.isEmpty else { return nil }
        return FrontMatter(properties: props, end: lines[close].end)
    }

    private static func unquote(_ s: String) -> String {
        if s.count >= 2, (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) { return String(s.dropFirst().dropLast()) }
        return s
    }

    /// The note without its front matter.
    static func body(of text: String) -> String {
        guard let fm = parse(text) else { return text }
        return (text as NSString).substring(from: fm.end)
    }
}
