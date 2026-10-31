import Foundation
import Markdown

/// Markdown to HTML where nothing from the note can become markup. swift-markdown's own HTMLFormatter writes text,
/// code, link targets and raw HTML exactly as they are in the note, so a note could carry a `<script>` or close an
/// attribute and add an `onmouseover`. Here every piece of text and every attribute value is escaped, raw HTML is
/// shown as code, and link and image targets must be web addresses, mail, or relative paths.
enum SafeHTML {
    static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for c in s.unicodeScalars {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            case "\u{0}": out += "\u{FFFD}"
            default: out.unicodeScalars.append(c)
            }
        }
        return out
    }

    /// A link or image target that is safe to put in an attribute, or nil.
    static func safeTarget(_ destination: String?) -> String? {
        guard let d = destination, !d.isEmpty else { return nil }
        if let scheme = LinkPolicy.scheme(of: d), !allowedSchemes.contains(scheme) { return nil }
        return escape(d)
    }

    static func render(_ document: Document) -> String { render(document as Markup) }

    private static func kids(_ m: Markup) -> String { m.children.map(render).joined() }

    private static func render(_ m: Markup) -> String {
        switch m {
        case is Document: return kids(m)
        case let h as Heading:
            let n = min(max(h.level, 1), 6)
            return "<h\(n)>\(kids(h))</h\(n)>\n"
        case let p as Paragraph: return "<p>\(kids(p))</p>\n"
        case let q as BlockQuote: return "<blockquote>\n\(kids(q))</blockquote>\n"
        case let l as UnorderedList: return "<ul>\n\(kids(l))</ul>\n"
        case let l as OrderedList:
            let start = l.startIndex != 1 ? " start=\"\(l.startIndex)\"" : ""
            return "<ol\(start)>\n\(kids(l))</ol>\n"
        case let i as ListItem:
            var box = ""
            if let c = i.checkbox { box = "<input type=\"checkbox\" disabled=\"\"\(c == .checked ? " checked=\"\"" : "") /> " }
            return "<li>\(box)\(kids(i))</li>\n"
        case let c as CodeBlock:
            // the language becomes a class name: letters, digits and a few symbols only
            let lang = (c.language ?? "").filter { $0.isLetter || $0.isNumber || "-_+#.".contains($0) }
            let attr = lang.isEmpty ? "" : " class=\"language-\(escape(lang))\""
            return "<pre><code\(attr)>\(escape(c.code))</code></pre>\n"
        case is ThematicBreak: return "<hr />\n"
        case let h as HTMLBlock: return "<pre><code>\(escape(h.rawHTML))</code></pre>\n"
        case let t as Markdown.Table: return table(t)
        case let t as Markdown.Text: return escape(t.string)
        case let e as Emphasis: return "<em>\(kids(e))</em>"
        case let s as Strong: return "<strong>\(kids(s))</strong>"
        case let s as Strikethrough: return "<del>\(kids(s))</del>"
        case let c as InlineCode: return "<code>\(escape(c.code))</code>"
        case let h as InlineHTML: return "<code>\(escape(h.rawHTML))</code>"
        case is SoftBreak: return "\n"
        case is LineBreak: return "<br />\n"
        case let l as Markdown.Link:
            guard let target = safeTarget(l.destination) else { return kids(l) }
            let title = l.title.flatMap { $0.isEmpty ? nil : " title=\"\(escape($0))\"" } ?? ""
            return "<a href=\"\(target)\"\(title)>\(kids(l))</a>"
        case let i as Markdown.Image:
            guard let target = safeTarget(i.source) else { return escape(i.plainText) }
            let title = i.title.flatMap { $0.isEmpty ? nil : " title=\"\(escape($0))\"" } ?? ""
            return "<img src=\"\(target)\" alt=\"\(escape(i.plainText))\"\(title) />"
        default: return escape(m.format())      // anything else (symbol links, directives) as plain text
        }
    }

    private static func table(_ t: Markdown.Table) -> String {
        let aligns = t.columnAlignments
        func cell(_ c: Markdown.Table.Cell, _ column: Int, tag: String) -> String {
            guard c.colspan > 0, c.rowspan > 0 else { return "" }
            let align = column < aligns.count ? aligns[column].map { " align=\"\($0)\"" } ?? "" : ""
            return "<\(tag)\(align)>\(kids(c))</\(tag)>\n"
        }
        func row(_ cells: [Markdown.Table.Cell], tag: String) -> String {
            "<tr>\n" + cells.enumerated().map { cell($0.element, $0.offset, tag: tag) }.joined() + "</tr>\n"
        }
        var out = "<table>\n<thead>\n" + row(Array(t.head.cells), tag: "th") + "</thead>\n"
        let rows = Array(t.body.rows)
        if !rows.isEmpty { out += "<tbody>\n" + rows.map { row(Array($0.cells), tag: "td") }.joined() + "</tbody>\n" }
        return out + "</table>\n"
    }
}
