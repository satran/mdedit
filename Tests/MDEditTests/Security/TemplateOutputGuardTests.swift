import XCTest
@testable import MDEdit

final class TemplateOutputGuardTests: XCTestCase {
    private func refused(_ html: String, _ tag: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        guard case .unsafe(let t, _)? = TemplateOutputGuard.check(html) else { return XCTFail("not refused: \(html)", file: file, line: line) }
        if let tag { XCTAssertEqual(t, tag, file: file, line: line) }
    }
    private func passes(_ html: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(TemplateOutputGuard.check(html), html, file: file, line: line)
    }

    func testConnectionHintsAndOtherLinksAreRefused() {
        for rel in ["dns-prefetch", "preconnect", "prefetch", "preload", "modulepreload", "icon", "stylesheet preload", "alternate stylesheet", ""] {
            refused("<link rel=\"\(rel)\" href=\"//host.example/\">", "<link>")
        }
        refused("<link rel=stylesheet href=\"https://host.example/a.css\">")
        refused("<link rel=stylesheet href=\"//host.example/a.css\">")
        refused("<link href=\"a.css\">", "<link>")
        refused("<link rel=\"stylesheet\">", "<link>")
    }

    func testTheOtherRefusedTags() {
        refused("<base href=\"https://x.example/\">", "<base>")
        refused("<object data=x></object>", "<object>"); refused("<embed src=x>", "<embed>"); refused("<iframe src=x></iframe>", "<iframe>")
        refused("<frame src=x>", "<frame>"); refused("<applet code=x></applet>", "<applet>")
        refused("<meta http-equiv=\"refresh\" content=\"0;url=https://x.example\">", "<meta http-equiv>")
        refused("<a href=\"x\" ping=\"https://x.example\">x</a>", "<a ping>")
        refused("<area href=x ping=\"https://x.example\">", "<area ping>")
        refused("<button formaction=\"https://x.example\">x</button>", "formaction")
        refused("<input type=submit formaction=x>", "formaction")
    }

    func testOddCaseSpacingQuotesAndSeparators() {
        refused("<LINK REL=DNS-PREFETCH HREF=//host.example>")
        refused("<link\n  rel =\n 'preconnect'\n href = '//host.example'>")
        refused("<link/rel=preconnect/href=//host.example>")
        refused("<BASE\thref=x>")
        refused("<a ping=x href=y>")
        refused("<a\nPING\n=\nx>")
        refused("<meta HTTP-EQUIV=refresh content=0>")
        refused("<p><b>x</b><iframe src=a></iframe></p>")
    }

    func testEntitiesAndHiddenCharactersInValues() {
        refused("<link rel=\"&#100;ns-prefetch\" href=\"//host.example\">")
        refused("<link rel=\"pre&#x63;onnect\" href=\"//host.example\">")
        refused("<link rel=stylesheet href=\"&#47;&#47;host.example/a.css\">")
        refused("<link rel=stylesheet href=\"&sol;&sol;host.example/a.css\">")
        refused("<link rel=stylesheet href=\"htt&#x70;s://host.example/a.css\">")
        refused("<link rel=stylesheet href=\"&#9;//host.example/a.css\">", "<link>")
        refused("<link rel=stylesheet href=\"\\\\host.example/a.css\">")
        refused("<link rel=stylesheet href=\"/\\host.example/a.css\">")
        refused("<link rel=stylesheet href=\"a&unknown;.css\">", "<link>")
        refused("<link rel=stylesheet href=\"a\tb:c.css\">", "<link>")
        refused("<link rel=stylesheet href=\"ja\nvascript:x\">")
    }

    func testAGreaterThanInsideAQuotedValueDoesNotEndTheTag() {
        refused("<a title=\"a>b\" ping=\"https://x.example\">x</a>")
        refused("<img alt=\"<link>\"><iframe src=x>")
        passes("<img alt=\"a > b\" src=\"pic.png\">")
    }

    func testHarmlessMarkupPasses() {
        passes("<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title>")
        passes("<link rel=\"stylesheet\" href=\"css/style.css\">")
        passes("<link rel=Stylesheet href=\"style.css?v=1#x\">")
        passes("<abbr title=x>a</abbr><article><base64>x</base64>")
        passes("<a href=\"https://example.com/x\">link</a> <a href=\"notes/a.md\">n</a> <img src=\"pic.png\"> <p>text &amp; more</p>")
        passes("<button type=submit>x</button><form action=\"x\"><input name=a></form>")
    }

    func testHintsInsideCommentsAndRawTextAreNotTags() {
        passes("<!-- <link rel=preconnect href=//host.example> --><p>x</p>")
        passes("<style>/* <link rel=preconnect href=//host.example> */ p {}</style>")
        passes("<textarea><iframe src=x></iframe></textarea>")
        passes("<title><base href=x></title>")
        refused("<style>p{}</style><iframe src=x>")
    }

    func testLineNumbersPointIntoTheRenderedOutput() {
        guard case .unsafe(_, let line)? = TemplateOutputGuard.check("<p>\n</p>\n<!-- c\nc -->\n<iframe src=x>") else { return XCTFail() }
        XCTAssertEqual(line, 5)
    }

    func testAHostNameBuiltFromNoteTextFailsTheRender() throws {
        let s = try Scratch(["n.md": "# abc-def\n"]); defer { s.remove() }
        let t = #"{% files "" as items %}{% for f in items %}<link rel="preconnect" href="//{{ f.title }}.example">{% endfor %}"#
        guard case .failure(let e) = T.run(t, in: s) else { return XCTFail("rendered") }
        if case .unsafe(let tag, _) = e { XCTAssertEqual(tag, "<link>") } else { XCTFail("\(e)") }
    }

    func testNoteTextWithATagIsPrintedEscapedAndPasses() throws {
        let s = try Scratch(["n.md": "# <link rel=preconnect href=//host.example>\n"]); defer { s.remove() }
        let p = T.page(#"{% files "" as items %}{% for f in items %}<h1>{{ f.title }}</h1>{% endfor %}"#, in: s)
        XCTAssertTrue(p.contains("&lt;link"), p)
    }

    func testDecodeAndRelative() {
        XCTAssertEqual(TemplateOutputGuard.decode("a&amp;b&#65;&#x42;&colon;"), "a&bAB:")
        XCTAssertNil(TemplateOutputGuard.decode("a&b"))
        XCTAssertNil(TemplateOutputGuard.decode("a&copy;"))
        for ok in ["a.css", "css/a.css", "../a.css", "a.css?x=1:2", "./a:b.css"] { XCTAssertTrue(TemplateOutputGuard.isRelative(ok), ok) }
        for bad in ["", "/a.css", "//h/a.css", "\\\\h", "https://h/a", "mailto:x", "a:b", "data:text/css,x"] { XCTAssertFalse(TemplateOutputGuard.isRelative(bad), bad) }
    }
}
