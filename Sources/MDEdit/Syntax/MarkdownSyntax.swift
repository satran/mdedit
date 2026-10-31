import Foundation

/// What a piece of text is, while it is being typed. The editor styles the text live and leaves the
/// Markdown characters in place (quiet), the way Things does: remove the markup and the style goes.
struct MDSpan: Equatable {
    enum Kind: Equatable {
        case heading(Int)          // the text after "# "
        case bold, italic, highlight, strike
        case code, codeBlock
        case link(String)          // the visible text of a link; the URL is the payload
        case wikiLink(String)      // the target of [[target|alias]]; covers the whole [[...]]
        case marker                // **, *, ::, ~~, `, [ ]( ), [[ ]] and "# ": shown quietly
        case listMarker            // "-", "*", "+", "•", "1."
        case checkbox(Bool)        // "[ ]" or "[x]"
        case done                  // the text of a ticked checklist item
        case quote                 // text after "> "
        case rule
        case tableRow
        case frontMatter           // a line of the YAML block at the top
    }
    var range: NSRange
    var kind: Kind
}

/// A line whose first characters hang in the margin: headings, list items and quotes. The text of its
/// wrapped lines lines up under the text, not under the marker.
struct MDLine: Equatable {
    enum Kind: Equatable { case heading(Int), list, quote }
    var range: NSRange      // the paragraph, without its newline
    var prefix: NSRange     // leading spaces, the marker and the space after it
    var lead: Int           // how many characters of the prefix are indentation
    var kind: Kind
    /// Length of a task's "[ ] " inside the prefix; it sits in the text, only the bullet hangs in the margin.
    var box = 0
}

enum MarkdownSyntax {
    struct Result {
        var spans: [MDSpan]; var lines: [MDLine]
    }

    private static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    private static let code = re("`([^`\\n]+)`")
    private static let wiki = re("\\[\\[([^\\[\\]\\n|]+)(\\|([^\\[\\]\\n]+))?\\]\\]")
    private static let link = re("\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)")
    private static let url = re("https?://[^\\s<>\\]]+")
    private static let bold = re("\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*")
    private static let highlight = re("::(?=\\S)(.+?)(?<=\\S)::")
    private static let strike = re("~~(?=\\S)(.+?)(?<=\\S)~~")
    private static let italic = re("(?<![*\\w])\\*(?=[^\\s*])(.+?)(?<=[^\\s*])\\*(?![*\\w])")
    private static let heading = re("^(#{1,6}) +")
    private static let listItem = re("^([ \\t]*)([-*+•]|\\d{1,4}[.)])[ \\t]+(\\[( |x|X)\\][ \\t]+)?")
    private static let quote = re("^[ \\t]*>[ \\t]?")
    private static let rule = re("^[ \\t]*([-*_])([ \\t]*\\1){2,}[ \\t]*$")

    static func analyze(_ text: String) -> Result {
        var spans: [MDSpan] = []
        var lines: [MDLine] = []
        let ns = text as NSString
        var fence: String?
        let fmEnd = FrontMatter.parse(text)?.end ?? 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            if line.location < fmEnd { spans.append(MDSpan(range: line, kind: .frontMatter)); return }
            let s = ns.substring(with: line).trimmingCharacters(in: .whitespaces)
            if let f = fence {
                spans.append(MDSpan(range: line, kind: .codeBlock))
                if s.hasPrefix(f) { fence = nil }
                return
            }
            if s.hasPrefix("```") || s.hasPrefix("~~~") {
                spans.append(MDSpan(range: line, kind: .codeBlock))
                fence = String(s.prefix(3))
                return
            }
            analyzeLine(ns, line, &spans, &lines)
        }
        return Result(spans: spans, lines: lines)
    }

    private static func first(_ r: NSRegularExpression, _ ns: NSString, _ range: NSRange) -> NSTextCheckingResult? {
        r.firstMatch(in: ns as String, options: [.anchored], range: range)
    }

    private static func analyzeLine(_ ns: NSString, _ line: NSRange, _ spans: inout [MDSpan], _ lines: inout [MDLine]) {
        var body = line                       // what is left for inline styling
        var checked = false

        if first(rule, ns, line) != nil, ns.substring(with: line).trimmingCharacters(in: .whitespaces).count >= 3 {
            spans.append(MDSpan(range: line, kind: .rule)); return
        }
        if let m = first(heading, ns, line) {
            let n = m.range(at: 1).length
            spans.append(MDSpan(range: m.range, kind: .marker))
            body = NSRange(location: NSMaxRange(m.range), length: NSMaxRange(line) - NSMaxRange(m.range))
            spans.append(MDSpan(range: body, kind: .heading(n)))
            lines.append(MDLine(range: line, prefix: m.range, lead: 0, kind: .heading(n)))
        } else if let m = first(quote, ns, line) {
            spans.append(MDSpan(range: m.range, kind: .marker))
            body = NSRange(location: NSMaxRange(m.range), length: NSMaxRange(line) - NSMaxRange(m.range))
            spans.append(MDSpan(range: body, kind: .quote))
            lines.append(MDLine(range: line, prefix: m.range, lead: 0, kind: .quote))
        } else if let m = first(listItem, ns, line) {
            let lead = m.range(at: 1), marker = m.range(at: 2)
            spans.append(MDSpan(range: marker, kind: .listMarker))
            if m.range(at: 3).location != NSNotFound {
                let box = NSRange(location: m.range(at: 3).location, length: 3)
                checked = m.range(at: 4).length > 0 && ns.substring(with: m.range(at: 4)).lowercased() == "x"
                spans.append(MDSpan(range: box, kind: .checkbox(checked)))
            }
            body = NSRange(location: NSMaxRange(m.range), length: NSMaxRange(line) - NSMaxRange(m.range))
            if checked { spans.append(MDSpan(range: body, kind: .done)) }
            let boxLen = m.range(at: 3).location != NSNotFound ? m.range(at: 3).length : 0
            lines.append(MDLine(range: line, prefix: m.range, lead: lead.length, kind: .list, box: boxLen))
        } else if ns.substring(with: line).trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            spans.append(MDSpan(range: line, kind: .tableRow))
        }
        inline(ns, body, &spans)
    }

    /// Inline styling looks for pairs of marks in a line, which is quadratic in its length for hostile text (thousands of
    /// "[a](" in a row took seconds). Lines longer than any real paragraph are left plain.
    static let maxInlineLength = 8000

    private static func inline(_ ns: NSString, _ range: NSRange, _ spans: inout [MDSpan]) {
        guard range.length > 0, range.length <= maxInlineLength else { return }
        var taken: [NSRange] = []            // code and links: nothing inside them is styled again
        func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }
        let s = ns as String

        for m in code.matches(in: s, range: range) where free(m.range) {
            spans.append(MDSpan(range: NSRange(location: m.range.location, length: 1), kind: .marker))
            spans.append(MDSpan(range: m.range(at: 1), kind: .code))
            spans.append(MDSpan(range: NSRange(location: NSMaxRange(m.range) - 1, length: 1), kind: .marker))
            taken.append(m.range)
        }
        for m in wiki.matches(in: s, range: range) where free(m.range) {
            // [[target|alias]]: the brackets (and "target|" when there is an alias) are quiet, the shown name is the link
            let target = m.range(at: 1), alias = m.range(at: 3)
            let shown = alias.location != NSNotFound ? alias : target
            spans.append(MDSpan(range: NSRange(location: m.range.location, length: shown.location - m.range.location), kind: .marker))
            spans.append(MDSpan(range: shown, kind: .wikiLink(ns.substring(with: target))))
            spans.append(MDSpan(range: NSRange(location: NSMaxRange(shown), length: NSMaxRange(m.range) - NSMaxRange(shown)), kind: .marker))
            taken.append(m.range)
        }
        for m in link.matches(in: s, range: range) where free(m.range) {
            let text = m.range(at: 1), dest = m.range(at: 2)
            spans.append(MDSpan(range: NSRange(location: m.range.location, length: 1), kind: .marker))
            spans.append(MDSpan(range: text, kind: .link(ns.substring(with: dest))))
            spans.append(MDSpan(range: NSRange(location: NSMaxRange(text), length: NSMaxRange(m.range) - NSMaxRange(text)), kind: .marker))
            taken.append(m.range)
        }
        for m in url.matches(in: s, range: range) {
            var r = m.range
            while r.length > 1, ".,;:!?)'\"".contains(ns.substring(with: NSRange(location: NSMaxRange(r) - 1, length: 1))) { r.length -= 1 }
            guard free(r) else { continue }
            spans.append(MDSpan(range: r, kind: .link(ns.substring(with: r))))
            taken.append(r)
        }
        func pair(_ regex: NSRegularExpression, _ kind: MDSpan.Kind, _ markerLen: Int) {
            for m in regex.matches(in: s, range: range) where free(m.range) {
                spans.append(MDSpan(range: NSRange(location: m.range.location, length: markerLen), kind: .marker))
                spans.append(MDSpan(range: m.range(at: 1), kind: kind))
                spans.append(MDSpan(range: NSRange(location: NSMaxRange(m.range) - markerLen, length: markerLen), kind: .marker))
            }
        }
        pair(bold, .bold, 2)
        pair(highlight, .highlight, 2)
        pair(strike, .strike, 2)
        pair(italic, .italic, 1)
    }
}

private extension NSRegularExpression {
    func matches(in s: String, range: NSRange) -> [NSTextCheckingResult] { matches(in: s, options: [], range: range) }
}
