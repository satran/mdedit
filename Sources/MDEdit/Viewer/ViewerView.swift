import SwiftUI
import AppKit
import Markdown

/// Read mode: the same Markdown, set as a page, in the serif or sans template of the type specs.
struct ViewerView: View {
    let blocks: [VBlock]
    let baseURL: URL?
    @ObservedObject var prefs: Preferences

    var body: some View {
        let style = prefs.viewerStyle
        ScrollView {
            BlockList(blocks: blocks, prefs: prefs, baseURL: baseURL)
                .textSelection(.enabled)
                .frame(maxWidth: style.measure, alignment: .leading)
                .padding(.top, style.pageTop).padding(.bottom, style.pageBottom + 24)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
    }
}

/// Blocks one after the other. The space between two is the larger of the one below the first and the one above the
/// second, as margins collapse on a web page, so a heading keeps more room above it than below.
struct BlockList: View {
    let blocks: [VBlock]
    @ObservedObject var prefs: Preferences
    let baseURL: URL?
    /// Text inside a quote is set in the quote's size and colour.
    var textSize: CGFloat?
    var leading: CGFloat?
    var ink: NSColor?

    var body: some View {
        let style = prefs.viewerStyle
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, b in
                BlockView(block: b, prefs: prefs, baseURL: baseURL, textSize: textSize, leading: leading, ink: ink)
                    .padding(.top, i == 0 ? 0 : Self.gap(between: blocks[i - 1], and: b, style: style, textSize: textSize))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The space between two neighbouring blocks: the larger of the first's bottom margin and the second's top margin.
    static func gap(between a: VBlock, and b: VBlock, style: ViewerStyle, textSize: CGFloat? = nil) -> CGFloat {
        max(margins(a, style, textSize).bottom, margins(b, style, textSize).top)
    }

    static func margins(_ b: VBlock, _ style: ViewerStyle, _ textSize: CGFloat?) -> (top: CGFloat, bottom: CGFloat) {
        let body = textSize ?? style.body
        switch b {
        case .heading(let level, _): let h = style.heading(level); return (h.top, h.bottom)
        case .paragraph, .html: return (0, body * (style.isSerif ? 0.75 : 0.85))
        case .quote: return (0, style.quoteGap)
        case .list: return (0, body * (style.isSerif ? 0.75 : 0.85))
        case .code: return (style.codeTop, style.codeBottom)
        case .table: return (style.tableTop, style.tableBottom)
        case .rule: return (style.ruleGap, style.ruleGap)
        case .image: return (body * 0.25, body * 0.75)
        case .properties: return (0, style.propertiesBottom)
        }
    }
}

struct BlockView: View {
    let block: VBlock
    @ObservedObject var prefs: Preferences
    let baseURL: URL?
    var textSize: CGFloat?
    var leading: CGFloat?
    var ink: NSColor?

    private var style: ViewerStyle { prefs.viewerStyle }
    private var size: CGFloat { textSize ?? style.body }
    private var lead: CGFloat { leading ?? style.bodyLeading }
    private var inkColor: Color { Color(ink ?? style.ink) }

    var body: some View {
        switch block {
        case .heading(let level, let text):
            let h = style.heading(level)
            Text(styled(text, size: h.size))
                .font(style.font(h.size, weight: h.weight))
                .tracking(h.size * h.tracking)
                .foregroundStyle(Color(style.headingInk))
                .lineSpacing(style.lineSpacing(size: h.size, leading: h.leading, weight: h.weight))
                .modifier(LinkCursor(text: text, font: style.nsFont(h.size, weight: h.weight), size: h.size, lineSpacing: style.lineSpacing(size: h.size, leading: h.leading, weight: h.weight), prefs: prefs))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(styled(text, size: size))
                .font(style.font(size))
                .foregroundStyle(inkColor)
                .lineSpacing(style.lineSpacing(size: size, leading: lead))
                .modifier(LinkCursor(text: text, font: style.nsFont(size), size: size, lineSpacing: style.lineSpacing(size: size, leading: lead), prefs: prefs))
                .fixedSize(horizontal: false, vertical: true)
        case .quote(let inner):
            // serif: set in and a little smaller, no rule. sans: body size behind a hairline
            HStack(alignment: .top, spacing: 0) {
                if style.quoteBar > 0 { Rectangle().fill(Color(Palette.vQuoteBar)).frame(width: style.quoteBar) }
                BlockList(blocks: inner, prefs: prefs, baseURL: baseURL, textSize: style.quoteSize, leading: style.quoteLeading, ink: style.quoteInk)
                    .padding(.leading, style.quotePadding).padding(.vertical, style.isSerif ? 0 : 2)
            }
            .padding(.horizontal, style.quoteIndent)
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: style.itemGap) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        marker(ordered: ordered, number: start + i, item: item)
                        BlockList(blocks: item.blocks, prefs: prefs, baseURL: baseURL, textSize: textSize, leading: leading, ink: ink)
                            .strikethrough(item.checkbox == true)
                            .foregroundStyle(item.checkbox == true ? Color(Palette.done) : inkColor)
                    }
                }
            }
        case .code(let code, _):
            ScrollView(.horizontal) {
                Text(code)
                    .font(style.mono(style.codeSize))
                    .foregroundStyle(Color(Palette.codeInk))
                    .lineSpacing(codeLineSpacing)
                    .padding(.vertical, 16).padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.codeBand)))
        case .table(let header, let aligns, let rows):
            TableBlock(header: header, aligns: aligns, rows: rows, prefs: prefs)
        case .rule:
            // a short centred hairline, not a full-width line
            Rectangle().fill(Color(Palette.vRule)).frame(width: 96, height: 1).frame(maxWidth: .infinity)
        case .image(let src, let alt):
            ImageBlock(src: src, alt: alt, baseURL: baseURL, size: size, allowRemote: prefs.loadRemoteImages)
        case .html(let raw):
            Text(raw).font(style.mono(size * 0.8)).foregroundStyle(Color(Palette.marker))
        case .properties(let props):
            PropertiesBlock(props: props, prefs: prefs)
        }
    }

    private var codeLineSpacing: CGFloat {
        let f = Fonts.nsFont(family: "IBM Plex Mono", size: style.codeSize) ?? NSFont.monospacedSystemFont(ofSize: style.codeSize, weight: .regular)
        return max(0, style.codeSize * style.codeLeading - (f.ascender - f.descender + f.leading))
    }

    /// Markers hang on the first line's baseline, so they track the text in every font. Serif: a bullet 0.2 em in.
    /// Sans: a 5 px dot centred on the x-height. Numbers and task boxes sit in the same gutter.
    @ViewBuilder private func marker(ordered: Bool, number: Int, item: VItem) -> some View {
        if let on = item.checkbox {
            Image(systemName: on ? "checkmark.square.fill" : "square")
                .font(.system(size: size * 0.8))
                .foregroundStyle(on ? Color(Palette.green) : Color(Palette.muted))
                .frame(width: style.itemIndent + size * 0.2, alignment: .leading)
                .accessibilityLabel(on ? "Done" : "Not done")
        } else if ordered {
            Text("\(number).").font(style.font(size, figures: .table)).foregroundStyle(Color(style.bulletInk))
                .frame(width: size * 1.7, alignment: .leading)
        } else if style.isSerif {
            Text("•").font(style.font(size)).foregroundStyle(Color(style.bulletInk))
                .padding(.leading, size * 0.2).frame(width: style.itemIndent, alignment: .leading)
        } else {
            let middle = style.nsFont(size).xHeight / 2
            Circle().fill(Color(style.bulletInk)).frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { d in d.height / 2 + middle }
                .padding(.leading, size * 0.25).frame(width: style.itemIndent, alignment: .leading)
        }
    }

    /// Links in the link colour with a thin faint underline; inline code in Plex Mono on a light chip.
    func styled(_ a: AttributedString, size: CGFloat) -> AttributedString {
        var out = a
        for run in a.runs {
            if let i = run.inlinePresentationIntent, i.contains(.code) {
                out[run.range].font = style.mono(size * style.inlineCodeScale)
                out[run.range].backgroundColor = Color(Palette.vChip)
                out[run.range].foregroundColor = Color(Palette.codeInk)
            }
            if run.link != nil {
                out[run.range].foregroundColor = Color(Palette.linkText)
                out[run.range].underlineStyle = Text.LineStyle(pattern: .solid, color: Color(Palette.linkText).opacity(0.35))
            }
        }
        return out
    }
}

/// Horizontal hairlines only, generous padding, small tracked capitals for the headers.
struct TableBlock: View {
    let header: [AttributedString]
    let aligns: [Markdown.Table.ColumnAlignment?]
    let rows: [[AttributedString]]
    @ObservedObject var prefs: Preferences

    private func alignment(_ col: Int) -> Alignment {
        guard col < aligns.count, let a = aligns[col] else { return .leading }
        switch a { case .left: return .leading; case .center: return .center; case .right: return .trailing }
    }

    var body: some View {
        let st = prefs.viewerStyle
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { i, c in
                    Text(String(c.characters).uppercased())
                        .font(.system(size: st.tableLabelSize, weight: .semibold)).tracking(st.tableLabelSize * st.tableLabelTracking)
                        .foregroundStyle(Color(Palette.vLabel))
                        .padding(.trailing, i == header.count - 1 ? 0 : 16).padding(.bottom, 9)
                        .frame(maxWidth: .infinity, alignment: alignment(i))
                }
            }
            Rectangle().fill(Color(Palette.vRule)).frame(height: 1).gridCellColumns(max(header.count, 1))
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { i, c in
                        Text(c).font(st.font(st.tableSize, weight: !st.isSerif && i == 0 ? .medium : .regular, figures: .table))
                            .foregroundStyle(Color(i == 1 ? Palette.vSecondary : st.ink))
                            .lineSpacing(st.lineSpacing(size: st.tableSize, leading: st.tableLeading))
                            .padding(.trailing, i == row.count - 1 ? 0 : 16).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: alignment(i))
                    }
                }
                if r < rows.count - 1 { Rectangle().fill(Color(Palette.vRowLine)).frame(height: 1).gridCellColumns(max(header.count, 1)) }
            }
        }
        .padding(.top, 0)
    }
}

struct ImageBlock: View {
    let src: String
    let alt: String
    let baseURL: URL?
    let size: CGFloat
    var allowRemote = false

    /// Pictures larger than this are not decoded: a small file can hold an enormous bitmap.
    static let maxBytes = 40 * 1024 * 1024

    var body: some View {
        Group {
            if src.hasPrefix("http://") || src.hasPrefix("https://") {
                if allowRemote, let url = URL(string: src) { remote(url) } else { blocked }
            } else if let image = local() {
                // as wide as the page, never larger than the picture itself, and centred
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: image.size.width)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                placeholder
            }
        }
        .accessibilityLabel(alt)
    }

    private var blocked: some View {
        Text("Remote picture not loaded" + (alt.isEmpty ? "" : ": \(alt)")).font(.system(size: size * 0.8)).foregroundStyle(Color(Palette.muted))
            .padding(10).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.chip)))
            .help(src)
    }

    private func remote(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image { image.resizable().scaledToFit().frame(maxWidth: .infinity) } else { placeholder }
        }
    }

    private var placeholder: some View {
        Text(alt.isEmpty ? src : alt).font(.system(size: size * 0.8)).foregroundStyle(Color(Palette.muted))
            .padding(10).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.chip)))
    }

    private func local() -> NSImage? {
        let path = src.removingPercentEncoding ?? src
        guard !path.contains("\0"), !path.lowercased().hasPrefix("file:") || path.count > 7 else { return nil }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(fileURLWithPath: path, relativeTo: baseURL)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)[.size] as? Int) ?? 0
        guard size > 0, size <= Self.maxBytes else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// The note's front matter as a table of properties, the way Obsidian shows them.
struct PropertiesBlock: View {
    let props: [VProperty]
    @ObservedObject var prefs: Preferences

    private static let dateKeys: Set<String> = ["date", "created", "updated", "modified", "due", "published"]

    private func symbol(_ p: VProperty) -> String {
        if case .bool = p.value { return "checkmark.square" }
        let k = p.key.lowercased()
        if k == "tags" || k == "tag" { return "tag" }
        if k == "aliases" || k == "alias" { return "arrow.turn.down.right" }
        if Self.dateKeys.contains(k) { return "calendar" }
        if k == "url" || k == "link" || k == "source" { return "link" }
        switch p.value {
        case .list: return "list.bullet"
        case .bool: return "checkmark.square"
        case .text: return "text.alignleft"
        }
    }

    var body: some View {
        // Inter 14 px in a card: rows 40 px high, the key column 150 px, chips for lists
        let size = 14 * prefs.viewerStyle.scale
        VStack(spacing: 0) {
            ForEach(Array(props.enumerated()), id: \.offset) { i, p in
                if i > 0 { Rectangle().fill(Color(Palette.vRowLine)).frame(height: 1) }
                HStack(alignment: .center, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: symbol(p)).font(.system(size: size * 0.95)).frame(width: size * 1.2)
                        Text(p.key).lineLimit(1)
                    }
                    .foregroundStyle(Color(Palette.vLabel))
                    .frame(width: 150, alignment: .leading)
                    value(p.value, size: size).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: size))
                .padding(.horizontal, 16).frame(minHeight: 40)
                .accessibilityElement(children: .combine)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(Palette.vCard)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Properties")
    }

    @ViewBuilder private func value(_ v: VProperty.Value, size: CGFloat) -> some View {
        switch v {
        case .text(let t):
            Text(link(t)).foregroundStyle(Color(Palette.text)).fixedSize(horizontal: false, vertical: true)
        case .bool(let b):
            Image(systemName: b ? "checkmark.square.fill" : "square")
                .foregroundStyle(b ? Color(Palette.green) : Color(Palette.muted)).accessibilityLabel(b ? "Yes" : "No")
        case .list(let items):
            FlowLayout(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                    Text(link(t)).font(.system(size: size * 13 / 14)).foregroundStyle(Color(Palette.text))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Color(Palette.vChip)))
                }
            }
        }
    }

    private func link(_ a: AttributedString) -> AttributedString {
        var out = a
        for run in a.runs where run.link != nil {
            out[run.range].foregroundColor = Color(Palette.linkText)
            out[run.range].underlineStyle = Text.LineStyle(pattern: .solid, color: Color(Palette.linkText).opacity(0.35))
        }
        return out
    }
}

/// Lays its children out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, f) in arrange(subviews, width: bounds.width).frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, used: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += row + spacing; row = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: s))
            x += s.width + spacing; row = max(row, s.height); used = max(used, x - spacing)
        }
        return (frames, CGSize(width: used, height: y + row))
    }
}


/// Text that is selectable shows an I-beam everywhere, links included. This finds the link under the pointer by laying the
/// same text out with TextKit, and asks for the pointing hand when the pointer is on one.
struct LinkCursor: ViewModifier {
    let text: AttributedString
    let font: NSFont
    let size: CGFloat
    let lineSpacing: CGFloat
    let prefs: Preferences
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        if text.runs.contains(where: { $0.link != nil }) {
            content
                .background(GeometryReader { g in
                    Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, w in width = w }
                })
                .onContinuousHover { phase in
                    if case .active(let p) = phase, overLink(p) {
                        NSCursor.pointingHand.set()
                        DispatchQueue.main.async { NSCursor.pointingHand.set() }
                    }
                }
        } else {
            content
        }
    }

    private func overLink(_ p: CGPoint) -> Bool {
        guard width > 0 else { return false }
        let storage = NSTextStorage()
        let para = NSMutableParagraphStyle(); para.lineSpacing = lineSpacing
        for run in text.runs {
            var f = font
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { f = prefs.editorNSFont(size: size * 0.85) }
            if intent.contains(.stronglyEmphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
            var attrs: [NSAttributedString.Key: Any] = [.font: f, .paragraphStyle: para]
            if let url = run.link { attrs[.link] = url }
            storage.append(NSAttributedString(string: String(text[run.range].characters), attributes: attrs))
        }
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let glyph = layout.glyphIndex(for: p, in: container)
        let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard rect.insetBy(dx: -1, dy: -1).contains(p) else { return false }
        let char = layout.characterIndexForGlyph(at: glyph)
        return char < storage.length && storage.attribute(.link, at: char, effectiveRange: nil) != nil
    }
}
