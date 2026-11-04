import XCTest
import SwiftUI
@testable import MDEdit

/// The type specs ("Editor · Typography", "Viewer · Serif / Sans template", "Type specs"): every number in them, so a change that
/// drifts from the design fails here.
@MainActor
final class TypographyTests: XCTestCase {
    private func approx(_ a: CGFloat, _ b: CGFloat, _ what: String, tol: CGFloat = 0.01, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: tol, what, file: file, line: line)
    }

    // MARK: viewer

    func testTheViewerFollowsTheSpecs() {
        let s = ViewerStyle()
        approx(s.body, 18, "body 18 px"); approx(s.bodyLeading, 1.6, "line height 1.6")
        approx(s.measure, 648, "measure 36 em")
        approx(s.heading(1).size, 34, "H1 34"); approx(s.heading(2).size, 23, "H2 23"); approx(s.heading(3).size, 18, "H3 18")
        XCTAssertEqual(s.heading(1).weight, .bold)
        approx(s.heading(1).tracking, -0.022, "H1 tracked -2.2%"); approx(s.heading(3).tracking, 0, "H3 not tracked")
        approx(s.heading(2).top, 23 * 1.75, "H2 above 1.75 em"); approx(s.heading(3).top, 18 * 1.6, "H3 above 1.6 em")
        approx(s.paragraphGap, 18 * 0.85, "paragraphs 0.85 em")
        approx(s.quoteSize, 18, "quote at body size"); approx(s.quoteBar, 2, "2 px hairline"); approx(s.quotePadding, 18, "quote text 18 px from the hairline"); approx(s.quoteIndent, 0, "not indented")
        approx(s.codeSize, 14.5, "code 14.5 px"); approx(s.inlineCodeScale, 0.86, "inline code 0.86 em")
        approx(s.tableSize, 15.5, "table 15.5 px"); approx(s.tableLabelTracking, 0.06, "labels +6%")
        approx(s.itemIndent, 22.5, "list item padding 1.25 em"); approx(s.itemGap, 4.5, "list items 0.25 em apart")
    }

    func testTheViewerStaysInsidePracticalTypographysRanges() {
        let s = ViewerStyle()
        XCTAssertTrue((15...25).contains(s.body), "body 15 to 25 px")
        XCTAssertTrue((1.2...1.65).contains(s.bodyLeading), "line spacing 120 to 165%")
        let chars = s.measure / (s.body * 0.5)          // an average character is about half an em wide
        XCTAssertTrue((60...75).contains(chars), "about 65 to 70 characters per line, got \(chars)")
        for level in 1...3 {
            XCTAssertGreaterThan(s.heading(level).size, level == 3 ? 0 : s.heading(level + 1 > 3 ? 3 : level + 1).size - 0.001)
            if level > 1 { XCTAssertGreaterThan(s.heading(level).top, s.heading(level).bottom, "more space above a heading than below it") }
        }
    }

    func testTheSizeSettingScalesEverythingTogether() {
        let big = ViewerStyle(body: 21.6), normal = ViewerStyle()
        approx(big.body, 21.6, "body"); approx(big.heading(1).size / normal.heading(1).size, 1.2, "H1 in proportion")
        approx(big.measure / normal.measure, 1.2, "the column grows with the type, so characters per line stay the same")
    }

    func testViewerLineWidthSetsTheColumnAndKeepsTheSpecsAtItsMiddle() {
        approx(ViewerStyle(width: 68).measure, 648, "68 characters is the specs' 36 em")
        let wide = ViewerStyle(width: 80).measure, narrow = ViewerStyle(width: 58).measure
        XCTAssertGreaterThan(wide, 648); XCTAssertLessThan(narrow, 648)
        approx(ViewerStyle(width: 136).measure, 1296, "proportional to the number of characters")
        XCTAssertEqual(SettingsView.viewerPresets.map(\.1), [58, 68, 80])
    }

    func testViewerWidthIsRememberedAndKeptSane() {
        let d = isolatedDefaults()
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.viewerWidth, 68); XCTAssertFalse(p.viewerWidthCustom)
        p.viewerWidth = 90; p.viewerWidthCustom = true
        let q = Preferences(defaults: d)
        XCTAssertEqual(q.viewerWidth, 90); XCTAssertTrue(q.viewerWidthCustom); XCTAssertEqual(q.viewerStyle.width, 90)
        d.set(100_000, forKey: "viewerWidth"); XCTAssertEqual(Preferences(defaults: d).viewerWidth, 140)
        d.set(-3, forKey: "viewerWidth"); XCTAssertEqual(Preferences(defaults: d).viewerWidth, 30)
    }

    func testPreferencesPickTheFontAndTheSize() {
        let d = isolatedDefaults()
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.viewerFont, "Inter"); approx(p.viewerStyle.body, 18, "default body"); XCTAssertEqual(p.viewerStyle.family, "Inter")
        p.viewerFont = "Literata"; p.viewerSize = 21.6
        let q = Preferences(defaults: d)
        XCTAssertEqual(q.viewerFont, "Literata"); approx(q.viewerStyle.body, 21.6, "body follows the size")
        let junk = isolatedDefaults(); junk.set("Evil\"; } </style><script>", forKey: "viewerFont")
        XCTAssertFalse(Preferences(defaults: junk).viewerFont.contains { "\"<>;{}".contains($0) }, "a stored name cannot carry markup")
        let empty = isolatedDefaults(); empty.set("", forKey: "viewerFont")
        XCTAssertEqual(Preferences(defaults: empty).viewerFont, "Inter")
    }

    // MARK: real punctuation

    func testQuotesDashesAndEllipsesAreSetProperly() {
        XCTAssertEqual(SmartPunctuation.apply("She said \"hello\" and 'left'."), "She said “hello” and ‘left’.")
        XCTAssertEqual(SmartPunctuation.apply("don't, it's, rock 'n' roll"), "don’t, it’s, rock ‘n’ roll")
        XCTAssertEqual(SmartPunctuation.apply("wait... what"), "wait… what")
        XCTAssertEqual(SmartPunctuation.apply("pages 3--5 and a break---here"), "pages 3–5 and a break—here")
        XCTAssertEqual(SmartPunctuation.apply("(\"quoted\")"), "(“quoted”)")
        XCTAssertEqual(SmartPunctuation.apply("\"Say\" \"it\""), "“Say” “it”")
        XCTAssertEqual(SmartPunctuation.apply("plain text, 1.5 and a-b"), "plain text, 1.5 and a-b")
        XCTAssertEqual(SmartPunctuation.apply("\"after\"", previous: "x"), "”after”", "directly after a word it closes")
        XCTAssertEqual(SmartPunctuation.apply("\"after\"", previous: " "), "“after”")
    }

    func testPunctuationIsSetInTheViewerButNeverInCodeAddressesOrProperties() {
        func text(_ md: String) -> String {
            HTMLText.visible(PreviewPage.body(markdown: md)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        XCTAssertEqual(text("He said \"no\" -- twice..."), "He said “no” – twice…")
        XCTAssertEqual(text("`a--b \"c\"` and \"d\""), "a--b \"c\" and “d”")
        XCTAssertEqual(text("see https://example.com/a--b?q='x' now"), "see https://example.com/a--b?q='x' now")
        XCTAssertEqual(text("[it's a \"link\"](https://x.y)"), "it’s a “link”")
        XCTAssertEqual(text("**bold\"** and *it's*"), "bold” and it’s", "a quote right after the opening of an emphasis run reads as closing, as in most typesetters")
        XCTAssertEqual(text("---\ntitle: It's \"raw\"\n---\nx"), "title It's \"raw\" x", "front matter is data, not prose")
    }

    func testTheNoteOnDiskIsNeverChangedByIt() throws {
        let s = try Scratch(["a.md": "\"quoted\" -- it's..."]); defer { s.remove() }
        let store = DocumentStore(); store.open(s.path("a.md"))
        _ = PreviewPage.body(markdown: store.text); _ = Exporter.html(markdown: store.text, title: "t")
        XCTAssertEqual(store.text, "\"quoted\" -- it's...")
    }

    // MARK: editor

    private func editor(_ text: String, size: CGFloat = 17, headings: Bool = false) -> EditorTextView {
        let tv = EditorTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        tv.style = EditorStyle(fontName: "IBM Plex Mono", size: size, lineWidth: 72, headingSizes: headings)
        tv.string = text
        tv.restyle()
        return tv
    }
    private func attr<T>(_ tv: EditorTextView, _ key: NSAttributedString.Key, at needle: String, in text: String) -> T? {
        let r = (text as NSString).range(of: needle)
        return tv.textStorage?.attribute(key, at: r.location, effectiveRange: nil) as? T
    }

    func testEditorDefaultsAreThe17pt72chSpec() {
        let p = Preferences(defaults: isolatedDefaults())
        XCTAssertEqual(p.editorFont, "IBM Plex Mono"); XCTAssertEqual(p.editorSize, 17); XCTAssertEqual(p.lineWidth, 72)
        XCTAssertFalse(p.headingSizes, "headings are body size")
        XCTAssertEqual(SettingsView.presets.map(\.1), [64, 72, 80], "64, 72 or 80 characters, or custom")
    }

    func testBodyLineIsOneAndSixtyFiveHundredthsOfTheSize() {
        let text = "one\ntwo\n"
        let tv = editor(text)
        let font: NSFont = attr(tv, .font, at: "one", in: text)!
        let para: NSParagraphStyle = attr(tv, .paragraphStyle, at: "one", in: text)!
        approx(font.pointSize, 17, "17 px")
        approx(font.ascender - font.descender + font.leading + para.lineSpacing, 17 * 1.65, "one line is 28 px", tol: 0.3)
    }

    func testHeadingsAreBodySizeAndSemiboldWithTheirMarkerFaint() {
        let text = "# Title\n\n## Sub\n\ntext\n"
        let tv = editor(text)
        let h1: NSFont = attr(tv, .font, at: "Title", in: text)!, h2: NSFont = attr(tv, .font, at: "Sub", in: text)!, body: NSFont = attr(tv, .font, at: "text", in: text)!
        approx(h1.pointSize, body.pointSize, "H1 is body size"); approx(h2.pointSize, body.pointSize, "H2 is body size")
        let w = (h1.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? 0
        XCTAssertTrue((0.2...0.4).contains(w), "weight 600, got \(w)")
        XCTAssertEqual(attr(tv, .foregroundColor, at: "Title", in: text) as NSColor?, Palette.strongText)
        XCTAssertEqual(attr(tv, .foregroundColor, at: "#", in: text) as NSColor?, Palette.marker, "the # is dimmed to #AEB4BC")
        let bigger = editor(text, headings: true)
        let h1b: NSFont = attr(bigger, .font, at: "Title", in: text)!
        XCTAssertGreaterThan(h1b.pointSize, body.pointSize, "the setting still allows larger headings")
    }

    func testHeadingMarkersHangInTheMarginSoTheTextKeepsOneEdge() {
        let text = "# Title\n\ntext\n"
        let tv = editor(text)
        let h: NSParagraphStyle = attr(tv, .paragraphStyle, at: "Title", in: text)!, p: NSParagraphStyle = attr(tv, .paragraphStyle, at: "text", in: text)!
        XCTAssertLessThan(h.firstLineHeadIndent, p.firstLineHeadIndent, "the marker is left of the text column")
        approx(h.headIndent, p.firstLineHeadIndent, "wrapped heading lines start at the column edge", tol: 0.5)
    }

    func testMarkupStaysVisibleButFaintAndLigaturesAreOff() {
        let text = "a **bold** and *it* `code` [link](https://x.y)\n"
        let tv = editor(text)
        XCTAssertEqual(attr(tv, .foregroundColor, at: "**", in: text) as NSColor?, Palette.marker)
        XCTAssertEqual(attr(tv, .foregroundColor, at: "bold", in: text) as NSColor?, Palette.strongText, "bold is semibold in the heading colour")
        XCTAssertEqual(attr(tv, .foregroundColor, at: "link", in: text) as NSColor?, Palette.linkText)
        XCTAssertEqual(attr(tv, .ligature, at: "and", in: text) as Int?, 0, "ligatures off")
        XCTAssertEqual(tv.string, text)
    }

    func testCodeIsTintedAndItsFencesAreFaint() {
        let text = "```yaml\nid: 1\n```\n"
        let tv = editor(text)
        XCTAssertEqual(attr(tv, .foregroundColor, at: "```yaml", in: text) as NSColor?, Palette.marker)
        XCTAssertEqual(attr(tv, .foregroundColor, at: "id: 1", in: text) as NSColor?, Palette.codeInk)
        XCTAssertNil(attr(tv, .backgroundColor, at: "id: 1", in: text) as NSColor?, "the band is drawn behind the text, not as a text background")
    }

    func testFrontMatterHasThreeQuietShades() {
        let text = "---\ntitle: Hello there\ntags: [a, b]\n---\nbody\n"
        let tv = editor(text)
        XCTAssertEqual(attr(tv, .foregroundColor, at: "---", in: text) as NSColor?, Palette.fmFence)
        XCTAssertEqual(attr(tv, .foregroundColor, at: "title", in: text) as NSColor?, Palette.fmKey)
        XCTAssertEqual(attr(tv, .foregroundColor, at: "Hello", in: text) as NSColor?, Palette.fmValue)
    }

    func testTablesDimThePipesAndTheSeparatorAndWeightTheHeader() {
        let text = "| Name | Kind |\n| ---- | ---- |\n| a    | b    |\n"
        let tv = editor(text)
        XCTAssertEqual(attr(tv, .foregroundColor, at: "----", in: text) as NSColor?, Palette.marker, "the separator row is all markup")
        XCTAssertEqual(attr(tv, .foregroundColor, at: "Name", in: text) as NSColor?, Palette.strongText, "the header is semibold")
        XCTAssertEqual(attr(tv, .foregroundColor, at: "a ", in: text) as NSColor?, Palette.text)
        XCTAssertTrue(EditorTextView.isTableSeparator("| --- | :-: |")); XCTAssertFalse(EditorTextView.isTableSeparator("| a | b |")); XCTAssertFalse(EditorTextView.isTableSeparator("---"))
    }

    func testSelectionAndCaretColoursAreTheSpecs() {
        let tv = editor("x")
        XCTAssertEqual(tv.selectedTextAttributes[.backgroundColor] as? NSColor, Palette.selectionText)
        XCTAssertEqual(tv.insertionPointColor, Palette.caret)
    }

    func testTheSpecColoursAreTheSpecsInLightMode() {
        func hex(_ c: NSColor) -> UInt32 {
            var out: UInt32 = 0
            NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
                let rgb = c.usingColorSpace(.sRGB)!
                out = (UInt32((rgb.redComponent * 255).rounded()) << 16) | (UInt32((rgb.greenComponent * 255).rounded()) << 8) | UInt32((rgb.blueComponent * 255).rounded())
            }
            return out
        }
        XCTAssertEqual(hex(Palette.marker), 0xAEB4BC); XCTAssertEqual(hex(Palette.strongText), 0x15171A); XCTAssertEqual(hex(Palette.linkText), 0x2453B3)
        XCTAssertEqual(hex(Palette.selectionText), 0xCFE0FB); XCTAssertEqual(hex(Palette.caret), 0x3478F6); XCTAssertEqual(hex(Palette.codeBand), 0xF6F7F9)
        XCTAssertEqual(hex(Palette.fmValue), 0x7C828A); XCTAssertEqual(hex(Palette.fmKey), 0x9AA0A8); XCTAssertEqual(hex(Palette.text), 0x2A2D31)
        XCTAssertEqual(hex(Palette.vInk), 0x25282C); XCTAssertEqual(hex(Palette.vHead), 0x131518)
        XCTAssertEqual(hex(Palette.vQuoteBar), 0xD9DEE4); XCTAssertEqual(hex(Palette.vRule), 0xD5D9DF); XCTAssertEqual(hex(Palette.vRowLine), 0xECEEF1)
    }
}

/// The reading faces ship with the app, so the preview looks the same on every Mac.
@MainActor
final class BundledFontTests: XCTestCase {
    func testLiterataAndInterAreBundledAndWeightsWork() {
        for family in ["Literata", "Inter", "IBM Plex Mono"] { XCTAssertTrue(Fonts.installed(family), "\(family) is bundled") }
        for family in ["Literata", "Inter"] {
            let s = ViewerStyle(family: family)
            let sample = "Hamburgefonstiv 1234"
            func width(_ w: Font.Weight) -> CGFloat { NSAttributedString(string: sample, attributes: [.font: s.nsFont(20, weight: w)]).size().width }
            XCTAssertGreaterThan(width(.bold), width(.regular), "\(family): bold is wider than regular, so the variable weight axis is used")
            XCTAssertEqual(s.nsFont(20).familyName, family)
        }
    }

    func testFontLicencesShipWithTheFonts() {
        let names = Bundle.main.paths(forResourcesOfType: "txt", inDirectory: nil).map { ($0 as NSString).lastPathComponent }
        for n in ["OFL-Literata.txt", "OFL-Inter.txt", "OFL-IBMPlexMono.txt"] { XCTAssertTrue(names.contains(n), n) }
    }
}
