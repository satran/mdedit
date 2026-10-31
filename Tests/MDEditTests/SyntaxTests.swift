import XCTest
@testable import MDEdit

final class SyntaxTests: XCTestCase {
    private func kinds(_ s: String) -> [MDSpan.Kind] { MarkdownSyntax.analyze(s).spans.map(\.kind) }
    private func text(_ s: String, _ span: MDSpan) -> String { (s as NSString).substring(with: span.range) }

    func testHeadingMarkerAndBody() {
        let s = "## Two acronyms"
        let r = MarkdownSyntax.analyze(s)
        XCTAssertEqual(r.spans.first?.kind, .marker)
        XCTAssertEqual(text(s, r.spans[0]), "## ")
        XCTAssertEqual(r.spans[1].kind, .heading(2))
        XCTAssertEqual(text(s, r.spans[1]), "Two acronyms")
        XCTAssertEqual(r.lines.first?.kind, .heading(2))
    }

    func testBoldItalicCodeStrike() {
        let s = "a **b** and *c* and `d` and ~~e~~"
        let k = kinds(s)
        XCTAssertTrue(k.contains(.bold)); XCTAssertTrue(k.contains(.italic))
        XCTAssertTrue(k.contains(.code)); XCTAssertTrue(k.contains(.strike))
    }

    func testListAndCheckbox() {
        let s = "  - [x] done"
        let r = MarkdownSyntax.analyze(s)
        XCTAssertTrue(r.spans.contains { $0.kind == .checkbox(true) })
        XCTAssertTrue(r.spans.contains { $0.kind == .done })
        XCTAssertEqual(r.lines.first?.lead, 2)
        XCTAssertEqual(r.lines.first?.kind, .list)
    }

    func testQuoteAndRule() {
        XCTAssertTrue(kinds("> hi").contains(.quote))
        XCTAssertEqual(kinds("---"), [.rule])
    }

    func testCodeFenceHidesInlineStyling() {
        let k = kinds("```\n**not bold**\n```")
        XCTAssertFalse(k.contains(.bold))
        XCTAssertEqual(k.filter { $0 == .codeBlock }.count, 3)
    }

    func testWikiLinkWithAlias() {
        let s = "see [[Goals|our goals]] now"
        let r = MarkdownSyntax.analyze(s)
        let link = r.spans.first { if case .wikiLink = $0.kind { return true } else { return false } }
        XCTAssertEqual(link.map { text(s, $0) }, "our goals")
        XCTAssertEqual(link?.kind, .wikiLink("Goals"))
    }

    func testTableRow() {
        XCTAssertTrue(kinds("| a | b |").contains(.tableRow))
    }

    func testListMarkerContinuation() {
        XCTAssertEqual(ListMarker(line: "- a")?.next, "- ")
        XCTAssertEqual(ListMarker(line: "3. a")?.next, "4. ")
        XCTAssertEqual(ListMarker(line: "  - [x] a")?.next, "  - [ ] ")
        XCTAssertNil(ListMarker(line: "plain"))
    }
}
