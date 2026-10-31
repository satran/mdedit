import XCTest
@testable import MDEdit

/// Exported HTML and the print view are built from untrusted notes: nothing in a note may become live HTML or script.
final class ExportSecurityTests: XCTestCase {
    private func html(_ md: String) -> String { Exporter.html(markdown: md, title: "T") }

    /// No live tag from the dangerous set, and no live event handler or javascript: URL, however it was written.
    private func assertInert(_ out: String, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let body = out.components(separatedBy: "<body>").last ?? out
        let live = try! NSRegularExpression(pattern: "<\\s*(script|iframe|object|embed|link|meta|base|form|input|svg|math|style|img[^>]*\\son\\w+\\s*=)|<[a-z][^<>]*\\son\\w+\\s*=", options: [.caseInsensitive])
        XCTAssertNil(live.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)), "\(label): live markup in \(body)", file: file, line: line)
        XCTAssertFalse(body.lowercased().contains("href=\"javascript"), "\(label)", file: file, line: line)
        XCTAssertFalse(body.lowercased().contains("src=\"javascript"), "\(label)", file: file, line: line)
    }

    func testRawHTMLIsShownAsText() {
        let attacks = [
            "<script>alert(1)</script>",
            "text <script>alert(1)</script> text",
            "<img src=x onerror=alert(1)>",
            "<a href=\"javascript:alert(1)\">x</a>",
            "<iframe src=\"https://evil\"></iframe>",
            "<svg onload=alert(1)>",
            "<body onload=alert(1)>",
            "<div onclick=\"x()\">click</div>",
            "<style>body{background:url(https://evil/x)}</style>",
            "<meta http-equiv=refresh content=\"0;url=https://evil\">",
            "<base href=\"https://evil/\">",
            "<form action=https://evil><input name=x></form>",
            "<object data=x></object><embed src=x>",
            "<math><mi xlink:href=\"javascript:alert(1)\">x</mi></math>",
            "<!-- <script>alert(1)</script> -->",
            "<scr<script>ipt>alert(1)</scr</script>ipt>",
        ]
        for a in attacks {
            assertInert(html(a), a)
            assertInert(html("para\n\n" + a + "\n\npara"), "block: " + a)
            assertInert(html("- item " + a), "list: " + a)
            assertInert(html("> " + a), "quote: " + a)
            assertInert(html("| a |\n|---|\n| " + a + " |"), "table: " + a)
            assertInert(html("# " + a), "heading: " + a)
        }
    }

    func testDangerousLinkAndImageDestinationsAreDropped() {
        let dests = ["javascript:alert(1)", "JAVASCRIPT:alert(1)", "  javascript:alert(1)", "java\tscript:alert(1)", "vbscript:x",
                     "data:text/html;base64,PHNjcmlwdD4=", "file:///etc/passwd", "x-apple.systempreferences:", "&#106;avascript:alert(1)"]
        for d in dests {
            for md in ["[click](\(d))", "![pic](\(d))", "[ref]\n\n[ref]: \(d)", "<\(d)>", "[click](<\(d)>)"] {
                let out = html(md)
                assertInert(out, md)
                XCTAssertFalse(out.lowercased().contains("href=\"data:"), md)
                XCTAssertFalse(out.lowercased().contains("href=\"file:"), md)
                XCTAssertFalse(out.lowercased().contains("src=\"data:"), md)
                XCTAssertFalse(out.lowercased().contains("src=\"file:"), md)
            }
        }
    }

    func testOrdinaryLinksAndImagesSurvive() {
        let out = html("[site](https://example.com) [mail](mailto:a@b.c) [note](Other.md) ![pic](images/a.png) ![web](https://example.com/a.png)")
        XCTAssertTrue(out.contains("href=\"https://example.com\""))
        XCTAssertTrue(out.contains("href=\"mailto:a@b.c\""))
        XCTAssertTrue(out.contains("href=\"Other.md\""))
        XCTAssertTrue(out.contains("src=\"images/a.png\""))
        XCTAssertTrue(out.contains("src=\"https://example.com/a.png\""))
    }

    func testTitleAndFontCannotBreakOut() {
        let out = Exporter.html(markdown: "x", title: "</title><script>alert(1)</script>", viewerFont: "Evil\"; } </style><script>alert(1)</script>")
        XCTAssertFalse(out.contains("<script"), out)
        XCTAssertFalse(out.contains("</style><script"))
        XCTAssertTrue(out.contains("&lt;/title&gt;"))
    }

    func testFrontMatterIsEscaped() {
        let md = "---\n<script>k</script>: <img src=x onerror=alert(1)>\ntags: [<b>x</b>, \"<script>\"]\ndone: true\n---\nbody"
        let out = html(md)
        assertInert(out, "front matter")
        XCTAssertTrue(out.contains("&lt;script&gt;"))
    }

    func testWikiLinkAliasIsEscaped() {
        assertInert(html("[[Note|<script>alert(1)</script>]] and [[<img src=x onerror=alert(1)>]]"), "wiki")
    }

    func testPageCarriesAContentSecurityPolicyThatForbidsScript() {
        let out = html("x")
        XCTAssertTrue(out.contains("Content-Security-Policy"))
        XCTAssertTrue(out.contains("default-src 'none'"))
        XCTAssertFalse(out.contains("script-src"))
        XCTAssertTrue(out.contains("no-referrer"))
    }

    func testCodeBlocksKeepTheirTextButNotTheirMarkup() {
        let out = html("```html\n<script>alert(1)</script>\n```\n\n`<script>`")
        assertInert(out, "code")
        XCTAssertTrue(out.contains("&lt;script&gt;"))
    }

    func testRandomHostileSoupNeverProducesLiveMarkup() {
        var rng = SeededRNG(seed: 20261031)
        let pieces = ["<", ">", "script", "img", "src=", "onerror=", "javascript:", "[", "]", "(", ")", "![", "](", "\"", "'", "=", "&", "#", "\n", "\n\n",
                      "<script>", "</script>", "<img src=x onerror=1>", "[a](", "javascript:alert(1))", "`", "~~~", "|", "---", "> ", "- ", "1. ", " ", "\t", "&lt;", "&#60;", "\u{0}"]
        for i in 0..<400 {
            var md = ""
            for _ in 0..<Int.random(in: 1...60, using: &rng) { md += pieces.randomElement(using: &rng)! }
            assertInert(html(md), "seed 20261031 case \(i): \(md.debugDescription)")
        }
    }
}
