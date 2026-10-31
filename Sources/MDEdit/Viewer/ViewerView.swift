import SwiftUI
import AppKit
import Markdown

/// Read mode: the same Markdown, set as a page.
struct ViewerView: View {
    let blocks: [VBlock]
    let baseURL: URL?
    @ObservedObject var prefs: Preferences

    var body: some View {
        ScrollView {
            BlockList(blocks: blocks, prefs: prefs, baseURL: baseURL, spacing: prefs.viewerSize)
                .textSelection(.enabled)
                .frame(maxWidth: Metrics.column, alignment: .leading)
                .padding(.top, 44).padding(.bottom, 80)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
    }
}

struct BlockList: View {
    let blocks: [VBlock]
    @ObservedObject var prefs: Preferences
    let baseURL: URL?
    var spacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, b in
                BlockView(block: b, prefs: prefs, baseURL: baseURL, first: i == 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BlockView: View {
    let block: VBlock
    @ObservedObject var prefs: Preferences
    let baseURL: URL?
    var first = false

    private var size: CGFloat { CGFloat(prefs.viewerSize) }
    private var ink: Color { Color(Palette.text) }

    var body: some View {
        switch block {
        case .heading(let level, let text):
            let (s, w): (CGFloat, Font.Weight) = {
                switch level {
                case 1: return (size * 2, .bold)
                case 2: return (size * 1.33, .semibold)
                case 3: return (size * 1.11, .semibold)
                default: return (size, .semibold)
                }
            }()
            Text(styled(text, size: s))
                .font(prefs.viewerFont(size: s, weight: w))
                .foregroundStyle(Color(Palette.strongText))
                .lineSpacing(s * 0.15)
                .modifier(LinkCursor(text: text, font: prefs.viewerNSFont(size: s, bold: true), size: s, lineSpacing: s * 0.15, prefs: prefs))
                .padding(.top, first ? 0 : (level <= 2 ? size * 0.9 : size * 0.4))
                .padding(.bottom, level == 1 ? size * 0.25 : 0)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(styled(text, size: size))
                .font(prefs.viewerFont(size: size))
                .foregroundStyle(ink)
                .lineSpacing(size * 0.33)
                .modifier(LinkCursor(text: text, font: prefs.viewerNSFont(size: size, bold: false), size: size, lineSpacing: size * 0.33, prefs: prefs))
                .fixedSize(horizontal: false, vertical: true)
        case .quote(let inner):
            HStack(alignment: .top, spacing: 0) {
                Rectangle().fill(Color(Palette.rule)).frame(width: 3)
                BlockList(blocks: inner, prefs: prefs, baseURL: baseURL, spacing: size * 0.5)
                    .italic().foregroundStyle(Color(Palette.quoteText))
                    .padding(.leading, 20).padding(.vertical, 2)
            }
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: size * 0.3) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        marker(ordered: ordered, number: start + i, item: item)
                        BlockList(blocks: item.blocks, prefs: prefs, baseURL: baseURL, spacing: size * 0.3)
                            .strikethrough(item.checkbox == true)
                            .foregroundStyle(item.checkbox == true ? Color(Palette.done) : ink)
                    }
                }
            }
            .padding(.leading, size * 0.4)
        case .code(let code, _):
            ScrollView(.horizontal) {
                Text(code)
                    .font(prefs.monoFont(size * 0.85))
                    .foregroundStyle(ink)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.chip)))
        case .table(let header, let aligns, let rows):
            TableBlock(header: header, aligns: aligns, rows: rows, prefs: prefs)
        case .rule:
            Rectangle().fill(Color(Palette.rule)).frame(height: 1).padding(.vertical, size * 0.5)
        case .image(let src, let alt):
            ImageBlock(src: src, alt: alt, baseURL: baseURL, size: size)
        case .html(let raw):
            Text(raw).font(prefs.monoFont(size * 0.8)).foregroundStyle(Color(Palette.marker))
        case .properties(let props):
            PropertiesBlock(props: props, prefs: prefs)
        }
    }

    @ViewBuilder private func marker(ordered: Bool, number: Int, item: VItem) -> some View {
        if let on = item.checkbox {
            Image(systemName: on ? "checkmark.square.fill" : "square")
                .font(.system(size: size * 0.85))
                .foregroundStyle(on ? Color(Palette.green) : Color(Palette.muted))
                .accessibilityLabel(on ? "Done" : "Not done")
        } else if ordered {
            Text("\(number).").font(prefs.viewerFont(size: size)).monospacedDigit().foregroundStyle(Color(Palette.muted))
                .frame(minWidth: size * 1.3, alignment: .trailing)
        } else {
            Text("•").font(prefs.viewerFont(size: size)).foregroundStyle(Color(Palette.muted)).frame(width: size * 0.6)
        }
    }

    func styled(_ a: AttributedString, size: CGFloat) -> AttributedString {
        var out = a
        for run in a.runs {
            if let i = run.inlinePresentationIntent, i.contains(.code) {
                out[run.range].font = prefs.monoFont(size * 0.85)
                out[run.range].backgroundColor = Color(Palette.chip)
            }
            if run.link != nil {
                out[run.range].foregroundColor = Color(Palette.link)
                out[run.range].underlineStyle = .single
            }
        }
        return out
    }
}

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
        let size = CGFloat(prefs.viewerSize) * 0.9
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow { ForEach(Array(header.enumerated()), id: \.offset) { i, c in cell(c, i, size, bold: true) } }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Divider().gridCellColumns(max(header.count, 1))
                GridRow { ForEach(Array(row.enumerated()), id: \.offset) { i, c in cell(c, i, size, bold: false) } }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(Palette.rule)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func cell(_ t: AttributedString, _ col: Int, _ size: CGFloat, bold: Bool) -> some View {
        Text(t).font(prefs.viewerFont(size: size, weight: bold ? .semibold : .regular))
            .foregroundStyle(Color(Palette.text))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: alignment(col))
            .background(bold ? Color(Palette.chip) : .clear)
    }
}

struct ImageBlock: View {
    let src: String
    let alt: String
    let baseURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if src.hasPrefix("http://") || src.hasPrefix("https://"), let url = URL(string: src) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFit().frame(maxWidth: .infinity) } else { placeholder }
                }
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

    private var placeholder: some View {
        Text(alt.isEmpty ? src : alt).font(.system(size: size * 0.8)).foregroundStyle(Color(Palette.muted))
            .padding(10).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.chip)))
    }

    private func local() -> NSImage? {
        let path = src.removingPercentEncoding ?? src
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(fileURLWithPath: path, relativeTo: baseURL)
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
        let size = CGFloat(prefs.viewerSize) * 0.78
        VStack(spacing: 0) {
            ForEach(Array(props.enumerated()), id: \.offset) { i, p in
                if i > 0 { Rectangle().fill(Color(Palette.paneBorder)).frame(height: 1) }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    HStack(spacing: 7) {
                        Image(systemName: symbol(p)).font(.system(size: size * 0.9)).frame(width: size * 1.2)
                        Text(p.key).lineLimit(1)
                    }
                    .foregroundStyle(Color(Palette.muted))
                    .frame(width: size * 10, alignment: .leading)
                    value(p.value, size: size).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(prefs.viewerFont(size: size))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .accessibilityElement(children: .combine)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(Palette.rule)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    Text(link(t)).foregroundStyle(Color(Palette.text))
                        .padding(.horizontal, 9).padding(.vertical, 2)
                        .background(Capsule().fill(Color(Palette.chip)))
                }
            }
        }
    }

    private func link(_ a: AttributedString) -> AttributedString {
        var out = a
        for run in a.runs where run.link != nil {
            out[run.range].foregroundColor = Color(Palette.link)
            out[run.range].underlineStyle = .single
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
