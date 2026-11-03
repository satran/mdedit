import XCTest
@testable import MDEdit

final class FrontMatterTests: XCTestCase {
    let note = """
    ---
    title: "DORA, you have a naming problem"
    tags: [regulation, devops]
    aliases:
      - DORA
      - Naming
    published: false
    related: [[Goals]]
    ---
    # Body

    text
    """

    func testParsesScalarsListsAndBooleans() throws {
        let fm = try XCTUnwrap(FrontMatter.parse(note))
        XCTAssertEqual(fm.properties.map(\.key), ["title", "tags", "aliases", "published", "related"])
        XCTAssertEqual(fm.properties[0].value, .text("DORA, you have a naming problem"))
        XCTAssertEqual(fm.properties[1].value, .list(["regulation", "devops"]))
        XCTAssertEqual(fm.properties[2].value, .list(["DORA", "Naming"]))
        XCTAssertEqual(fm.properties[3].value, .bool(false))
        XCTAssertEqual(fm.properties[4].value, .text("[[Goals]]"))
        XCTAssertEqual((note as NSString).substring(from: fm.end).hasPrefix("# Body"), true)
    }

    func testNotFrontMatter() {
        XCTAssertNil(FrontMatter.parse("# Title\n---\na: b\n---\n"))           // not at the top
        XCTAssertNil(FrontMatter.parse("---\njust words\n---\n"))              // no properties
        XCTAssertNil(FrontMatter.parse("---\na: b\nnever closed"))
        XCTAssertNil(FrontMatter.parse(""))
    }

    func testBodyAndCountsSkipIt() {
        XCTAssertTrue(FrontMatter.body(of: note).hasPrefix("# Body"))
        XCTAssertEqual(DocumentStore.wordCount(note), 2)           // "Body" and "text"
        XCTAssertEqual(Outline.headings(in: "---\ntitle: x\n# a comment\n---\n# Real").map(\.title), ["Real"])
    }

    func testEditorQuietsTheBlock() {
        let r = MarkdownSyntax.analyze(note)
        XCTAssertEqual(r.spans.filter { $0.kind == .frontMatter }.count, 9)
        XCTAssertTrue(r.spans.contains { $0.kind == .heading(1) })
    }

    func testViewerPutsPropertiesFirst() {
        let html = PreviewPage.body(markdown: note)
        XCTAssertTrue(html.hasPrefix("<div class=\"props\">"), "properties come first")
        XCTAssertEqual(html.components(separatedBy: "<tr>").count - 1, 5)
        XCTAssertLessThan(html.range(of: "class=\"props\"")!.lowerBound, html.range(of: "<h1>")!.lowerBound)
    }

    func testHTMLExportHasTable() {
        let html = Exporter.html(markdown: note, title: "T")
        XCTAssertTrue(html.contains("<table class=\"properties\">"))
        XCTAssertTrue(html.contains("<span class=\"chip\">regulation</span>"))
        XCTAssertFalse(html.contains("tags: ["))
    }
}
