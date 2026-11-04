import SwiftUI
import AppKit

/// Every size, spacing, weight and colour of the viewer, from the type specs (the sans reading face).
/// Pixel values are the specs' for the default body size and scale with the body size set in Settings.
struct ViewerStyle {
    /// The face the text is set in; Settings picks it and the custom stylesheet can override it.
    let family: String
    /// 1 at the specs' own sizes.
    let scale: CGFloat

    /// Characters per line the reader asked for; `ViewerStyle.specWidth` is the specs' own column.
    let width: Int
    static let specWidth = 68
    /// The specs' body size in points, and the face they were drawn in.
    static let specBody: CGFloat = 18
    static let defaultFamily = "Inter"

    init(body: CGFloat = ViewerStyle.specBody, family: String = ViewerStyle.defaultFamily, width: Int = ViewerStyle.specWidth) {
        self.family = family; scale = body / Self.specBody; self.width = width
    }

    private func px(_ v: CGFloat) -> CGFloat { v * scale }

    // MARK: page

    /// 18 px / 1.6.
    var body: CGFloat { px(18) }
    var bodyLeading: CGFloat { 1.6 }
    /// The column: 36 em, about 65 to 70 characters.
    var measure: CGFloat { 36 * body * CGFloat(width) / CGFloat(Self.specWidth) }
    var pageTop: CGFloat { 64 }
    var pageBottom: CGFloat { 56 }

    var ink: NSColor { Palette.vInk }
    var headingInk: NSColor { Palette.vHead }
    var secondaryInk: NSColor { Palette.vSecondary }

    // MARK: blocks

    struct Heading { var size: CGFloat; var leading: CGFloat; var weight: Font.Weight; var tracking: CGFloat; var top: CGFloat; var bottom: CGFloat }

    /// H1 / H2 / H3 are 34 / 23 / 18; deeper levels are body size and semibold.
    /// Space is larger above a heading than below it. The first block of a page or quote gets no top space (BlockList),
    /// so H1 still has room above it when it turns up mid-note.
    func heading(_ level: Int) -> Heading {
        switch level {
        case 1: return Heading(size: px(34), leading: 1.15, weight: .bold, tracking: -0.022, top: px(34) * 1.6, bottom: px(28))
        case 2: return Heading(size: px(23), leading: 1.3, weight: .semibold, tracking: -0.012, top: px(23) * 1.75, bottom: px(23) * 0.45)
        case 3: return Heading(size: px(18), leading: 1.5, weight: .semibold, tracking: 0, top: px(18) * 1.6, bottom: px(18) * 0.35)
        default: return Heading(size: body, leading: bodyLeading, weight: .semibold, tracking: 0, top: body * 1.5, bottom: body * 0.35)
        }
    }

    /// Paragraphs are separated by space, never indented: 0.85 em.
    var paragraphGap: CGFloat { body * 0.85 }

    // quote: body size behind a hairline
    var quoteSize: CGFloat { body }
    var quoteLeading: CGFloat { bodyLeading }
    var quoteIndent: CGFloat { 0 }
    var quoteBar: CGFloat { 2 }
    var quotePadding: CGFloat { 18 }
    var quoteInk: NSColor { Palette.vQuote }
    var quoteGap: CGFloat { quoteSize * 0.85 }

    // lists
    var itemIndent: CGFloat { body * 1.25 }
    var itemGap: CGFloat { body * 0.25 }
    var bulletInk: NSColor { Palette.vBullet }

    // tables
    var tableSize: CGFloat { px(15.5) }
    var tableLeading: CGFloat { 1.4 }
    var tableLabelSize: CGFloat { px(12) }
    var tableLabelTracking: CGFloat { 0.06 }
    var tableTop: CGFloat { tableSize * 0.4 }
    var tableBottom: CGFloat { tableSize }

    // code
    var codeSize: CGFloat { px(14.5) }
    var codeLeading: CGFloat { 1.55 }
    var codeTop: CGFloat { codeSize * 0.5 }
    var codeBottom: CGFloat { codeSize }
    var inlineCodeScale: CGFloat { 0.86 }

    var ruleGap: CGFloat { body * 2 }
    var propertiesBottom: CGFloat { 44 }

    // MARK: fonts

    enum Figures { case text, table }

    /// The chosen face at a size and weight; the system font when it is not installed. Tables get lining tabular figures.
    func nsFont(_ size: CGFloat, weight: Font.Weight = .regular, figures: Figures = .text) -> NSFont {
        let w = Self.nsWeight(weight)
        var f: NSFont
        if Fonts.installed(family) {
            let d = NSFontDescriptor(fontAttributes: [.family: family, .traits: [NSFontDescriptor.TraitKey.weight: w.rawValue]])
            f = NSFont(descriptor: d, size: size) ?? NSFont.systemFont(ofSize: size, weight: w)
        } else {
            f = NSFont.systemFont(ofSize: size, weight: w)
        }
        // OpenType 'lnum' + 'tnum' through their AAT names: number case (21) and number spacing (6)
        if figures == .table {
            let features: [[NSFontDescriptor.FeatureKey: Int]] = [[.typeIdentifier: 21, .selectorIdentifier: 1], [.typeIdentifier: 6, .selectorIdentifier: 0]]
            f = NSFont(descriptor: f.fontDescriptor.addingAttributes([.featureSettings: features]), size: size) ?? f
        }
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
