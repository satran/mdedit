import Foundation
import Markdown

/// Markdown (GitHub flavoured) as blocks the viewer draws. Inline styling stays in the AttributedString.
indirect enum VBlock {
    case heading(Int, AttributedString)
    case paragraph(AttributedString)
    case quote([VBlock])
    case list(ordered: Bool, start: Int, items: [VItem])
    case code(String, language: String?)
    case table(header: [AttributedString], aligns: [Table.ColumnAlignment?], rows: [[AttributedString]])
    case rule
    case image(src: String, alt: String)
    case html(String)
}

struct VItem {
    var checkbox: Bool?
    var blocks: [VBlock]
}

enum ViewerParser {
    static func parse(_ source: String) -> [VBlock] {
        let doc = Document(parsing: source)
        return blocks(doc.children)
    }

    private static func blocks(_ children: MarkupChildren) -> [VBlock] {
        children.compactMap(block)
    }

    private static func block(_ m: Markup) -> VBlock? {
        switch m {
        case let h as Heading:
            return .heading(h.level, inlines(h))
        case let p as Paragraph:
            // a paragraph that is only an image is a figure
            if p.childCount == 1, let img = p.child(at: 0) as? Markdown.Image, let src = img.source {
                return .image(src: src, alt: img.plainText)
            }
            return .paragraph(inlines(p))
        case let q as BlockQuote:
            return .quote(blocks(q.children))
        case let l as UnorderedList:
            return .list(ordered: false, start: 1, items: items(l))
        case let l as OrderedList:
            return .list(ordered: true, start: Int(l.startIndex), items: items(l))
        case let c as CodeBlock:
            return .code(c.code.hasSuffix("\n") ? String(c.code.dropLast()) : c.code, language: c.language)
        case let t as Markdown.Table:
            let head = Array(t.head.cells).map { inlines($0) }
            let rows = Array(t.body.rows).map { Array($0.cells).map { inlines($0) } }
            return .table(header: head, aligns: t.columnAlignments, rows: rows)
        case is ThematicBreak:
            return .rule
        case let h as HTMLBlock:
            return .html(h.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func items(_ list: Markup) -> [VItem] {
        list.children.compactMap { $0 as? ListItem }.map { item in
            VItem(checkbox: item.checkbox.map { $0 == .checked }, blocks: blocks(item.children))
        }
    }

    // MARK: inline

    static func inlines(_ m: Markup) -> AttributedString {
        var out = AttributedString()
        for c in m.children { append(c, to: &out, intent: [], link: nil) }
        return out
    }

    private static func run(_ s: String, intent: InlinePresentationIntent, link: URL?) -> AttributedString {
        var a = AttributedString(s)
        if !intent.isEmpty { a.inlinePresentationIntent = intent }
        if let link { a.link = link }
        return a
    }

    private static func append(_ m: Markup, to out: inout AttributedString, intent: InlinePresentationIntent, link: URL?) {
        switch m {
        case let t as Markdown.Text:
            if link == nil, !intent.contains(.code) { out += linkified(t.string, intent: intent) }
            else { out += run(t.string, intent: intent, link: link) }
        case is SoftBreak: out += run(" ", intent: intent, link: link)
        case is LineBreak: out += run("\n", intent: intent, link: link)
        case let e as Emphasis:
            for c in e.children { append(c, to: &out, intent: intent.union(.emphasized), link: link) }
        case let s as Strong:
            for c in s.children { append(c, to: &out, intent: intent.union(.stronglyEmphasized), link: link) }
        case let s as Strikethrough:
            for c in s.children { append(c, to: &out, intent: intent.union(.strikethrough), link: link) }
        case let c as InlineCode:
            out += run(c.code, intent: intent.union(.code), link: link)
        case let l as Markdown.Link:
            let url = l.destination.flatMap { URL(string: $0) }
            for c in l.children { append(c, to: &out, intent: intent, link: url ?? link) }
        case let i as Markdown.Image:
            out += run(i.plainText, intent: intent, link: link)
        case let h as InlineHTML:
            out += run(h.rawHTML, intent: intent, link: link)
        default:
            for c in m.children { append(c, to: &out, intent: intent, link: link) }
        }
    }

    private static let bareURL = try! NSRegularExpression(pattern: "https?://[^\\s<>\\]]+")

    /// Plain text with [[wiki links]] and bare web addresses turned into links.
    static func linkified(_ s: String, intent: InlinePresentationIntent) -> AttributedString {
        var pieces: [(Range<String.Index>, String, URL?)] = []
        for (r, w) in WikiLink.parse(s) { pieces.append((r, w.shown, w.url)) }
        let ns = s as NSString
        for m in bareURL.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard var r = Range(m.range, in: s) else { continue }
            while s[r].count > 1, ".,;:!?)'\"".contains(s[r].last!) { r = r.lowerBound..<s.index(before: r.upperBound) }
            if pieces.contains(where: { $0.0.overlaps(r) }) { continue }
            pieces.append((r, String(s[r]), URL(string: String(s[r]))))
        }
        guard !pieces.isEmpty else { return run(s, intent: intent, link: nil) }
        pieces.sort { $0.0.lowerBound < $1.0.lowerBound }
        var out = AttributedString(), at = s.startIndex
        for (r, text, url) in pieces {
            if at < r.lowerBound { out += run(String(s[at..<r.lowerBound]), intent: intent, link: nil) }
            out += run(text, intent: intent, link: url)
            at = r.upperBound
        }
        if at < s.endIndex { out += run(String(s[at...]), intent: intent, link: nil) }
        return out
    }
}
