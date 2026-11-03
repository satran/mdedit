import SwiftUI
import AppKit

/// Every size, spacing, weight and colour of the viewer, from the type specs ("One writing face, two reading faces").
/// Pixel values are the specs' for the default body size and scale with the body size set in Settings.
struct ViewerStyle {
    enum Template { case serif, sans }
    let template: Template
    /// 1 at the specs' own sizes.
    let scale: CGFloat

    /// Characters per line the reader asked for; `ViewerStyle.specWidth` is the specs' own column.
    let width: Int
    static let specWidth = 68

    init(template: Template, serifBody: CGFloat, width: Int = ViewerStyle.specWidth) { self.template = template; scale = serifBody / 20; self.width = width }

    var isSerif: Bool { template == .serif }
    private func px(_ v: CGFloat) -> CGFloat { v * scale }

    // MARK: page

    /// Serif 20 px / 1.45, sans 18 px / 1.6.
    var body: CGFloat { px(isSerif ? 20 : 18) }
    var bodyLeading: CGFloat { isSerif ? 1.45 : 1.6 }
    /// The column: 34 em (serif) or 36 em (sans), about 65 to 70 characters.
    var measure: CGFloat { (isSerif ? 34 : 36) * body * CGFloat(width) / CGFloat(Self.specWidth) }
    var pageTop: CGFloat { 64 }
    var pageBottom: CGFloat { 56 }

    var ink: NSColor { isSerif ? Palette.vInkSerif : Palette.vInkSans }
    var headingInk: NSColor { isSerif ? Palette.vHeadSerif : Palette.vHeadSans }
    var secondaryInk: NSColor { Palette.vSecondary }

    // MARK: blocks

    struct Heading { var size: CGFloat; var leading: CGFloat; var weight: Font.Weight; var tracking: CGFloat; var top: CGFloat; var bottom: CGFloat }

    /// H1 / H2 / H3 are 40 / 26 / 20 (serif) and 34 / 23 / 18 (sans); deeper levels are body size and semibold.
    /// Space is larger above a heading than below it. The first block of a page or quote gets no top space (BlockList),
    /// so H1 still has room above it when it turns up mid-note.
    func heading(_ level: Int) -> Heading {
        switch (isSerif, level) {
        case (true, 1): return Heading(size: px(40), leading: 1.12, weight: .semibold, tracking: -0.012, top: px(40) * 1.6, bottom: px(30))
        case (true, 2): return Heading(size: px(26), leading: 1.25, weight: .semibold, tracking: -0.005, top: px(26) * 1.7, bottom: px(26) * 0.45)
        case (true, 3): return Heading(size: px(20), leading: 1.45, weight: .semibold, tracking: 0, top: px(20) * 1.5, bottom: px(20) * 0.35)
        case (false, 1): return Heading(size: px(34), leading: 1.15, weight: .bold, tracking: -0.022, top: px(34) * 1.6, bottom: px(28))
        case (false, 2): return Heading(size: px(23), leading: 1.3, weight: .semibold, tracking: -0.012, top: px(23) * 1.75, bottom: px(23) * 0.45)
        case (false, 3): return Heading(size: px(18), leading: 1.5, weight: .semibold, tracking: 0, top: px(18) * 1.6, bottom: px(18) * 0.35)
        default: return Heading(size: body, leading: bodyLeading, weight: .semibold, tracking: 0, top: body * 1.5, bottom: body * 0.35)
        }
    }

    /// Paragraphs are separated by space, never indented: 0.75 em (serif) or 0.85 em (sans).
    var paragraphGap: CGFloat { body * (isSerif ? 0.75 : 0.85) }

    // quote: the serif one is set in, smaller, with no rule; the sans one is body size behind a hairline
    var quoteSize: CGFloat { isSerif ? px(18.5) : body }
    var quoteLeading: CGFloat { isSerif ? 1.5 : bodyLeading }
    var quoteIndent: CGFloat { isSerif ? quoteSize * 1.25 : 0 }
    var quoteBar: CGFloat { isSerif ? 0 : 2 }
    var quotePadding: CGFloat { isSerif ? 0 : 18 }
    var quoteInk: NSColor { isSerif ? Palette.vQuoteSerif : Palette.vQuoteSans }
    var quoteGap: CGFloat { quoteSize * 0.85 }

    // lists
    var itemIndent: CGFloat { body * (isSerif ? 1.2 : 1.25) }
    var itemGap: CGFloat { body * (isSerif ? 0.2 : 0.25) }
    var bulletInk: NSColor { isSerif ? Palette.vBulletSerif : Palette.vBulletSans }

    // tables
    var tableSize: CGFloat { px(isSerif ? 17 : 15.5) }
    var tableLeading: CGFloat { isSerif ? 1.35 : 1.4 }
    var tableLabelSize: CGFloat { px(12) }
    var tableLabelTracking: CGFloat { isSerif ? 0.07 : 0.06 }
    var tableTop: CGFloat { tableSize * 0.4 }
    var tableBottom: CGFloat { tableSize }

    // code
    var codeSize: CGFloat { px(isSerif ? 15 : 14.5) }
    var codeLeading: CGFloat { 1.55 }
    var codeTop: CGFloat { codeSize * 0.5 }
    var codeBottom: CGFloat { codeSize }
    var inlineCodeScale: CGFloat { isSerif ? 0.8 : 0.86 }

    var ruleGap: CGFloat { body * 2 }
    var propertiesBottom: CGFloat { 44 }

    // MARK: fonts

    enum Figures { case text, table }

    /// The template's face at a size and weight. Serif text gets old-style figures; tables get lining tabular ones.
    func nsFont(_ size: CGFloat, weight: Font.Weight = .regular, figures: Figures = .text) -> NSFont {
        let w = Self.nsWeight(weight)
        let family = isSerif ? "Literata" : "Inter"
        var f: NSFont
        if Fonts.installed(family) {
            let d = NSFontDescriptor(fontAttributes: [.family: family, .traits: [NSFontDescriptor.TraitKey.weight: w.rawValue]])
            f = NSFont(descriptor: d, size: size) ?? NSFont.systemFont(ofSize: size, weight: w)
        } else if isSerif {
            let sys = NSFont.systemFont(ofSize: size, weight: w)
            f = sys.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? sys     // New York
        } else {
            f = NSFont.systemFont(ofSize: size, weight: w)
        }
        // OpenType 'onum' / 'lnum' + 'tnum' through their AAT names: number case (21) and number spacing (6)
        let features: [[NSFontDescriptor.FeatureKey: Int]]
        switch (figures, isSerif) {
        case (.table, _): features = [[.typeIdentifier: 21, .selectorIdentifier: 1], [.typeIdentifier: 6, .selectorIdentifier: 0]]
        case (.text, true): features = [[.typeIdentifier: 21, .selectorIdentifier: 0]]
        case (.text, false): features = []
        }
        if !features.isEmpty { f = NSFont(descriptor: f.fontDescriptor.addingAttributes([.featureSettings: features]), size: size) ?? f }
        return f
    }

    func font(_ size: CGFloat, weight: Font.Weight = .regular, figures: Figures = .text) -> Font {
        Font(nsFont(size, weight: weight, figures: figures) as CTFont)
    }

    /// IBM Plex Mono for code, falling back to the system monospaced font.
    func mono(_ size: CGFloat) -> Font {
        Fonts.installed("IBM Plex Mono") ? .custom("IBM Plex Mono", size: size) : .system(size: size, design: .monospaced)
    }

    /// The extra space between lines that gives `leading` times the font size, given what the font already has.
    func lineSpacing(size: CGFloat, leading: CGFloat, weight: Font.Weight = .regular) -> CGFloat {
        let f = nsFont(size, weight: weight)
        let natural = f.ascender - f.descender + f.leading
        return max(0, size * leading - natural)
    }

    static func nsWeight(_ w: Font.Weight) -> NSFont.Weight {
        switch w {
        case .bold: return .bold
        case .semibold: return .semibold
        case .medium: return .medium
        case .heavy: return .heavy
        default: return .regular
        }
    }
}
