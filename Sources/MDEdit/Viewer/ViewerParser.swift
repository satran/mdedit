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
    case properties([VProperty])
}

struct VProperty {
    enum Value {
        case text(AttributedString)
        case list([AttributedString])
        case bool(Bool)
    }
    var key: String
    var value: Value
}

struct VItem {
    var checkbox: Bool?
    var blocks: [VBlock]
}

enum ViewerParser {
    static func parse(_ source: String) -> [VBlock] {
        var out: [VBlock] = []
        var body = source
        if let fm = FrontMatter.parse(source) {
            out.append(.properties(fm.properties.map { p in
                switch p.value {
                case .text(let t): return VProperty(key: p.key, value: .text(linkified(t, intent: [])))
                case .list(let l): return VProperty(key: p.key, value: .list(l.map { linkified($0, intent: []) }))
                case .bool(let b): return VProperty(key: p.key, value: .bool(b))
                }
            }))
            body = (source as NSString).substring(from: fm.end)
        }
        return out + blocks(Document(parsing: MarkdownLimits.clamp(body), options: [.disableSmartOpts]).children)
    }

    private static func blocks(_ children: MarkupChildren) -> [VBlock] {
        children.flatMap(block)
    }

    private static func block(_ m: Markup) -> [VBlock] {
        guard let single = singleBlock(m) else { return paragraphBlocks(m) }
        return [single]
    }

    /// A paragraph is text and images in reading order. Without a blank line an image belongs to the paragraph around it
    /// (`text\n![a](b.png)\nmore`), so the paragraph is split at every image: text runs stay paragraphs, each image becomes a figure.
    /// An image inside a link (`[![a](b.png)](url)`) shows as a figure and loses the link: a figure cannot carry one.
    private static func paragraphBlocks(_ m: Markup) -> [VBlock] {
        guard let p = m as? Paragraph else { return [] }
        let sink = ImageSink()
        var out = AttributedString()
        for c in p.children { append(c, to: &out, intent: [], link: nil, sink: sink) }
        sink.flush(&out)
        return sink.blocks
    }

    private static func singleBlock(_ m: Markup) -> VBlock? {
        switch m {
        case let h as Heading:
            return .heading(h.level, inlines(h))
        case is Paragraph:
            return nil // handled by paragraphBlocks
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

    /// Collects the blocks of a paragraph while its inlines are walked; nil where images stay inline text (headings, table cells).
    private final class ImageSink {
        var blocks: [VBlock] = []
        /// Text before an image becomes a paragraph (dropping the soft break or space next to the image); nothing if only blanks.
        func flush(_ out: inout AttributedString) {
            defer { out = AttributedString() }
            var text = out
            while let c = text.characters.last, c.isWhitespace { text.characters.removeLast() }
            while let c = text.characters.first, c.isWhitespace { text.characters.removeFirst() }
            if !text.characters.isEmpty { blocks.append(.paragraph(text)) }
        }
    }

    private static func append(_ m: Markup, to out: inout AttributedString, intent: InlinePresentationIntent, link: URL?, sink: ImageSink? = nil) {
        switch m {
        case let t as Markdown.Text:
            if link == nil, !intent.contains(.code) { out += linkified(t.string, intent: intent, smart: true, previous: out.characters.last) }
            else {
                // the words of a link are prose; a web address shown as the link is not
                let isAddress = t.string.contains("://") || t.string.lowercased().hasPrefix("www.") || t.string.hasPrefix("mailto:")
                out += run(intent.contains(.code) || isAddress ? t.string : SmartPunctuation.apply(t.string, previous: out.characters.last), intent: intent, link: link)
            }
        case is SoftBreak: out += run(" ", intent: intent, link: link)
        case is LineBreak: out += run("\n", intent: intent, link: link)
        case let e as Emphasis:
            for c in e.children { append(c, to: &out, intent: intent.union(.emphasized), link: link, sink: sink) }
        case let s as Strong:
            for c in s.children { append(c, to: &out, intent: intent.union(.stronglyEmphasized), link: link, sink: sink) }
        case let s as Strikethrough:
            for c in s.children { append(c, to: &out, intent: intent.union(.strikethrough), link: link, sink: sink) }
        case let c as InlineCode:
            out += run(c.code, intent: intent.union(.code), link: link)
        case let l as Markdown.Link:
            let url = l.destination.flatMap { URL(string: $0) }
            for c in l.children { append(c, to: &out, intent: intent, link: url ?? link, sink: sink) }
        case let i as Markdown.Image:
            if let sink, let src = i.source, !src.isEmpty {
                sink.flush(&out)
                sink.blocks.append(.image(src: src, alt: i.plainText))
            } else {
                out += run(i.plainText, intent: intent, link: link)
            }
        case let h as InlineHTML:
            out += run(h.rawHTML, intent: intent, link: link)
        default:
            for c in m.children { append(c, to: &out, intent: intent, link: link, sink: sink) }
        }
    }

    private static let bareURL = try! NSRegularExpression(pattern: "https?://[^\\s<>\\]]+")

    /// Plain text with [[wiki links]] and bare web addresses turned into links.
    static func linkified(_ s: String, intent: InlinePresentationIntent, smart: Bool = false, previous: Character? = nil) -> AttributedString {
        func plain(_ t: String, _ before: Character?) -> String { smart ? SmartPunctuation.apply(t, previous: before) : t }
        var pieces: [(Range<String.Index>, String, URL?)] = []
        let wikis = WikiLink.parse(s)
        for (r, w) in wikis { pieces.append((r, w.shown, w.url)) }
        let ns = s as NSString
        // wiki links come in order, so overlap is found by walking both lists once (a note with thousands of addresses was quadratic)
        var w = 0
        for m in bareURL.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard var r = Range(m.range, in: s) else { continue }
            // trailing punctuation belongs to the sentence, not the address; a quote only when it has no partner inside the address
            while s[r].count > 1, let last = s[r].last, ".,;:!?)'\"".contains(last),
                  last != "'" && last != "\"" || s[r].filter({ $0 == last }).count % 2 == 1 {
                r = r.lowerBound..<s.index(before: r.upperBound)
            }
            while w < wikis.count, wikis[w].range.upperBound <= r.lowerBound { w += 1 }
            if w < wikis.count, wikis[w].range.overlaps(r) { continue }
            pieces.append((r, String(s[r]), URL(string: String(s[r]))))
        }
        guard !pieces.isEmpty else { return run(plain(s, previous), intent: intent, link: nil) }
        pieces.sort { $0.0.lowerBound < $1.0.lowerBound }
        var out = AttributedString(), at = s.startIndex
        for (r, text, url) in pieces {
            if at < r.lowerBound { out += run(plain(String(s[at..<r.lowerBound]), out.characters.last ?? previous), intent: intent, link: nil) }
            out += run(text, intent: intent, link: url)
            at = r.upperBound
        }
        if at < s.endIndex { out += run(plain(String(s[at...]), out.characters.last ?? previous), intent: intent, link: nil) }
        return out
    }
}


/// The viewer sets real punctuation: curly quotes, en and em dashes, true ellipses. Only the viewer: the text on disk is not changed,
/// and code, addresses and link targets are never touched.
enum SmartPunctuation {
    static func apply(_ s: String, previous: Character? = nil) -> String {
        guard s.contains(where: { "\"'.-".contains($0) }) else { return s }
        var out = ""
        var prev = previous
        let chars = Array(s)
        var i = 0
        func opens(_ before: Character?) -> Bool {
            guard let b = before else { return true }
            return b.isWhitespace || "([{<“‘—–/".contains(b)
        }
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "\"": out.append(opens(prev) ? "“" : "”")
            case "'":
                // an apostrophe or a closing quote after a word; an opening quote after a space, before a letter
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                out.append(opens(prev) && (next?.isLetter ?? false) ? "‘" : "’")
            case "." where i + 2 < chars.count + 0 && chars[i + 1] == "." && chars[i + 2] == ".":
                out.append("…"); i += 2
            case "-" where i + 2 < chars.count && chars[i + 1] == "-" && chars[i + 2] == "-":
                out.append("—"); i += 2
            case "-" where i + 1 < chars.count && chars[i + 1] == "-":
                out.append("–"); i += 1
            default: out.append(c)
            }
            prev = out.last
            i += 1
        }
        return out
    }
}
