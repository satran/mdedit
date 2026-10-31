import XCTest
@testable import MDEdit

/// Text built to hang or crash a Markdown tool. Every parser the app runs on a note gets every input, under a time budget.
final class HostileInputTests: XCTestCase {

    static let inputs: [(String, String)] = {
        let r = { (s: String, n: Int) in String(repeating: s, count: n) }
        return [
            ("empty", ""), ("one newline", "\n"), ("only spaces", r(" ", 50_000)), ("only newlines", r("\n", 200_000)),
            ("brackets open", r("[[", 20_000)), ("wiki pipes", r("[[a|", 10_000)), ("link starts", r("[a](", 20_000)), ("image starts", r("![", 20_000)),
            ("stars", r("*", 50_000)), ("underscores", r("_a", 30_000)), ("ticks", r("`", 50_000)), ("tildes", r("~~a", 30_000)),
            ("hashes", r("#", 200_000)), ("long url", "http://" + r("a", 200_000)), ("many urls", r("https://a.b/c ", 20_000)),
            ("mixed marks", r("**a_b`c~~d[[e", 5_000)), ("highlight", r("::a", 30_000)),
            ("checkbox spam", r("- [ ] x\n", 20_000)), ("table wide", "|" + r("a|", 5_000) + "\n|" + r("-|", 5_000) + "\n"),
            ("table tall", "|a|b|\n|-|-|\n" + r("|1|2|\n", 20_000)), ("rules", r("---\n", 20_000)), ("fence unclosed", "```\n" + r("code\n", 20_000)),
            ("nested quotes", r(">", 100_000) + " x"), ("quotes per line", r("> ", 50_000)), ("deep list", (0..<400).map { String(repeating: "  ", count: $0) + "- x" }.joined(separator: "\n")),
            ("nul bytes", r("a\u{0}b", 10_000)), ("controls", r("\u{1}\u{2}\u{7}\u{1B}", 10_000)), ("bom everywhere", r("\u{FEFF}x", 10_000)),
            ("rtl override", r("\u{202E}abc\u{202C}", 10_000)), ("zero width", r("\u{200B}\u{200D}", 50_000)), ("emoji zwj", r("👨‍👩‍👧‍👦", 10_000)),
            ("combining", "e" + r("\u{0301}", 50_000)), ("cr only", r("a\r", 50_000)), ("crlf", r("a\r\n", 50_000)),
            ("front matter open", "---\n" + r("k: v\n", 20_000)), ("front matter keys", "---\n" + (0..<20_000).map { "key\($0): v" }.joined(separator: "\n") + "\n---\n"),
            ("front matter lists", "---\ntags: [" + r("a,", 50_000) + "]\n---\n"), ("front matter dashes", "---\n" + r("- x\n", 20_000) + "---\n"),
            ("html soup", r("<a href='x'>", 10_000)), ("entities", r("&amp;&#x41;&bogus;", 10_000)), ("backslashes", r("\\", 100_000)),
            ("html comment open", "<!--" + r("x", 100_000)), ("setext", r("a\n===\n", 10_000)), ("long line", r("word ", 400_000)),
            ("one huge word", r("a", 2_000_000)),
        ]
    }()

    func testEveryParserSurvivesEveryInput() {
        for (name, text) in Self.inputs {
            let start = Date()
            _ = MarkdownSyntax.analyze(text)
            _ = ViewerParser.parse(text)
            _ = Exporter.html(markdown: text, title: name)
            _ = Outline.headings(in: text)
            _ = DocumentStore.wordCount(text)
            _ = FrontMatter.parse(text)
            _ = WikiLink.parse(text)
            _ = Exporter.plainWikiLinks(text)
            let took = Date().timeIntervalSince(start)
            XCTAssertLessThan(took, 12, "\(name): \(String(format: "%.1f", took))s for \(text.utf8.count) bytes")
        }
    }

    /// Each stage alone, so a slow one is named.
    func testEachStageIsFastOnTheWorstInputs() {
        let worst = ["link starts", "wiki pipes", "mixed marks", "image starts", "highlight", "stars", "long line", "one huge word"]
        for (name, text) in Self.inputs where worst.contains(name) {
            within(4, "analyze \(name)") { _ = MarkdownSyntax.analyze(text) }
            within(4, "parse \(name)") { _ = ViewerParser.parse(text) }
            within(4, "export \(name)") { _ = Exporter.html(markdown: text, title: "t") }
        }
    }

    func testDeepNestingIsFlattenedNotFollowed() {
        for n in [1_000, 5_000, 50_000, 500_000] {
            let src = String(repeating: ">", count: n) + " deep"
            within(2, "quotes \(n)") { _ = ViewerParser.parse(src); _ = Exporter.html(markdown: src, title: "t") }
            let spaced = String(repeating: "> ", count: n)
            within(2, "spaced quotes \(n)") { _ = ViewerParser.parse(spaced) }
        }
        var list = ""
        for i in 0..<3_000 { list += String(repeating: "  ", count: i) + "- item\n" }
        within(10, "deep list") { _ = ViewerParser.parse(list); _ = Exporter.html(markdown: list, title: "t") }
        let nested = String(repeating: "- ", count: 100_000) + "x"
        within(4, "marker chain") { _ = ViewerParser.parse(nested); _ = Exporter.html(markdown: nested, title: "t") }
    }

    func testInlineNestingDoesNotOverflowTheStack() {
        for s in [String(repeating: "*a ", count: 50_000), String(repeating: "[", count: 100_000), String(repeating: "(", count: 100_000),
                  String(repeating: "**_~~", count: 20_000), String(repeating: "[a](", count: 30_000) + String(repeating: ")", count: 30_000),
                  String(repeating: "<", count: 100_000), String(repeating: "![a](", count: 30_000)] {
            within(6, "inline nesting") { _ = ViewerParser.parse(s); _ = Exporter.html(markdown: s, title: "t"); _ = MarkdownSyntax.analyze(s) }
        }
    }

    func testClampKeepsOrdinaryNotesIdenticalAndCapsHostileOnes() {
        let normal = "# T\n\n> quote\n> > nested\n\n- a\n  - b\n    - c\n\n    code in list\n"
        XCTAssertEqual(MarkdownLimits.clamp(normal), normal)
        let deep = String(repeating: ">", count: 500) + " x"
        XCTAssertLessThanOrEqual(MarkdownLimits.clamp(deep).filter { $0 == ">" }.count, MarkdownLimits.maxQuoteDepth + 1)
        XCTAssertTrue(MarkdownLimits.clamp(deep).hasSuffix("x"))
        let wide = String(repeating: " ", count: 500) + "text"
        XCTAssertEqual(MarkdownLimits.clamp(wide).count, MarkdownLimits.maxIndent + 4)
        let long = String(repeating: "a", count: MarkdownLimits.maxLine + 100)
        XCTAssertEqual(MarkdownLimits.clamp(long).utf16.count, MarkdownLimits.maxLine)
    }

    func testStyledEditorSurvivesHostileText() {
        for (name, text) in Self.inputs where text.utf8.count < 400_000 {
            let tv = EditorTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
            tv.string = text
            within(10, "restyle \(name)") { tv.restyle() }
        }
    }

    func testPlainWikiLinksAndFrontMatterNeverTrapOnRandomText() {
        var rng = SeededRNG(seed: 99)
        let alphabet = Array("[]|#:-\n -—\"'`*_~<>()!\\&;=\t abcXYZ012").map(String.init)
        for _ in 0..<500 {
            var s = ""
            for _ in 0..<Int.random(in: 0...300, using: &rng) { s += alphabet.randomElement(using: &rng)! }
            _ = Exporter.plainWikiLinks(s); _ = FrontMatter.parse(s); _ = FrontMatter.body(of: s)
            _ = Outline.headings(in: s); _ = WikiLink.parse(s); _ = MarkdownSyntax.analyze(s)
            _ = ViewerParser.parse(s); _ = Exporter.html(markdown: s, title: "x")
        }
    }

    func testAnalyzerSpansStayInsideTheText() {
        var rng = SeededRNG(seed: 4242)
        let alphabet = Array("[]|#:-\n *_~`>()!\\ab12 \t").map(String.init)
        for _ in 0..<600 {
            var s = ""
            for _ in 0..<Int.random(in: 0...200, using: &rng) { s += alphabet.randomElement(using: &rng)! }
            let len = (s as NSString).length
            let r = MarkdownSyntax.analyze(s)
            for sp in r.spans { XCTAssertTrue(sp.range.location >= 0 && NSMaxRange(sp.range) <= len, "span \(sp.range) in \(s.debugDescription)") }
            for l in r.lines { XCTAssertTrue(NSMaxRange(l.range) <= len && NSMaxRange(l.prefix) <= len, "line in \(s.debugDescription)") }
        }
    }
}
