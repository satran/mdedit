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

    /// Raw HTML without its comments; a comment that is never closed runs to the end, as in CommonMark.
    static func withoutComments(_ html: String) -> String {
        html.replacingOccurrences(of: "<!--[\\s\\S]*?(-->|$)", with: "", options: .regularExpression)
    }

    /// A link or image target that is safe to put in an attribute, or nil.
    static func safeTarget(_ destination: String?) -> String? {
        guard let d = destination, !d.isEmpty else { return nil }
        if let scheme = LinkPolicy.scheme(of: d), !allowedSchemes.contains(scheme) { return nil }
        return escape(d)
    }

    /// What the preview needs while it walks a note: whether it is inside a link, and the character before the text at hand
    /// (for curly quotes). Nil flow: plain output, as for export.
    struct Ctx {
        final class Flow { var last: Character? }
        var flow: Flow?
        var inLink = false
    }

    static func render(_ document: Document, preview: Bool = false) -> String { render(document as Markup, Ctx(flow: preview ? Ctx.Flow() : nil)) }

    private static func kids(_ m: Markup, _ pv: Ctx) -> String { m.children.map { render($0, pv) }.joined() }

    private static func render(_ m: Markup, _ pv: Ctx) -> String {
        switch m {
        case is Document: return kids(m, pv)
        case let h as Heading:
            pv.flow?.last = nil
            let n = min(max(h.level, 1), 6)
            return "<h\(n)>\(kids(h, pv))</h\(n)>\n"
        case let p as Paragraph: pv.flow?.last = nil; return "<p>\(kids(p, pv))</p>\n"
        case let q as BlockQuote: return "<blockquote>\n\(kids(q, pv))</blockquote>\n"
        case let l as UnorderedList: return "<ul>\n\(kids(l, pv))</ul>\n"
        case let l as OrderedList:
            let start = l.startIndex != 1 ? " start=\"\(l.startIndex)\"" : ""
            return "<ol\(start)>\n\(kids(l, pv))</ol>\n"
        case let i as ListItem:
            var box = ""
            if let c = i.checkbox { box = "<input type=\"checkbox\" disabled=\"\"\(c == .checked ? " checked=\"\"" : "") /> " }
            return "<li>\(box)\(kids(i, pv))</li>\n"
        case let c as CodeBlock:
            // the language becomes a class name: letters, digits and a few symbols only
            let lang = (c.language ?? "").filter { $0.isLetter || $0.isNumber || "-_+#.".contains($0) }
            let attr = lang.isEmpty ? "" : " class=\"language-\(escape(lang))\""
            return "<pre><code\(attr)>\(escape(c.code))</code></pre>\n"
        case is ThematicBreak: return "<hr />\n"
        case let h as HTMLBlock:
            // comments are for the writer: they are not shown, and other raw HTML is shown as code
            let raw = withoutComments(h.rawHTML)
            return raw.allSatisfy(\.isWhitespace) ? "" : "<pre><code>\(escape(raw))</code></pre>\n"
        case let t as Markdown.Table: return table(t, pv)
        case let t as Markdown.Text:
            guard let f = pv.flow else { return escape(t.string) }
            let (html, last) = PreviewText.html(t.string, previous: f.last, inLink: pv.inLink)
            f.last = last ?? f.last
            return html
        case let e as Emphasis: return "<em>\(kids(e, pv))</em>"
        case let s as Strong: return "<strong>\(kids(s, pv))</strong>"
        case let s as Strikethrough: return "<del>\(kids(s, pv))</del>"
        case let c as InlineCode: pv.flow?.last = c.code.last ?? pv.flow?.last; return "<code>\(escape(c.code))</code>"
        case let h as InlineHTML:
            let raw = withoutComments(h.rawHTML)
            if raw.isEmpty { return "" }
            pv.flow?.last = raw.last ?? pv.flow?.last; return "<code>\(escape(raw))</code>"
        case is SoftBreak: pv.flow?.last = " "; return "\n"
        case is LineBreak: pv.flow?.last = "\n"; return "<br />\n"
        case let l as Markdown.Link:
            var inside = pv; inside.inLink = true
            guard let target = safeTarget(l.destination) else { return kids(l, inside) }
            let title = l.title.flatMap { $0.isEmpty ? nil : " title=\"\(escape($0))\"" } ?? ""
            return "<a href=\"\(target)\"\(title)>\(kids(l, inside))</a>"
        case let i as Markdown.Image:
            pv.flow?.last = i.plainText.last ?? pv.flow?.last
            guard let target = safeTarget(i.source) else { return escape(i.plainText) }
            let title = i.title.flatMap { $0.isEmpty ? nil : " title=\"\(escape($0))\"" } ?? ""
            return "<img src=\"\(target)\" alt=\"\(escape(i.plainText))\"\(title) />"
        default: return escape(m.format())      // anything else (symbol links, directives) as plain text
        }
    }

    private static func table(_ t: Markdown.Table, _ pv: Ctx) -> String {
        let aligns = t.columnAlignments
        func cell(_ c: Markdown.Table.Cell, _ column: Int, tag: String) -> String {
            guard c.colspan > 0, c.rowspan > 0 else { return "" }
            let align = column < aligns.count ? aligns[column].map { " align=\"\($0)\"" } ?? "" : ""
            pv.flow?.last = nil
            return "<\(tag)\(align)>\(kids(c, pv))</\(tag)>\n"
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
