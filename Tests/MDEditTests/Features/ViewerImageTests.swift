import XCTest
@testable import MDEdit

/// An image needs no blank line around it: it is split out of its paragraph as a figure, in reading order.
final class ViewerImageTests: XCTestCase {
    private func kinds(_ md: String) -> [String] { ViewerParser.parse(md).map(kind) }

    private func kind(_ b: VBlock) -> String {
        switch b {
        case .paragraph: return "p"
        case .image(let src, _): return "img:\(src)"
        case .heading: return "h"
        case .quote(let inner): return "q[" + inner.map(kind).joined(separator: ",") + "]"
        case .list(_, _, let items): return "l[" + items.map { $0.blocks.map(kind).joined(separator: ",") }.joined(separator: ";") + "]"
        default: return "other"
        }
    }

    func testImageBetweenTextLines() {
        XCTAssertEqual(kinds("Some text\n![alt](pic.png)\nmore text"), ["p", "img:pic.png", "p"])
    }

    func testTextKeepsOrderAndFormatting() {
        let b = ViewerParser.parse("Some **bold**\n![alt](pic.png)\nafter [l](https://x.y)")
        guard b.count == 3, case .paragraph(let a) = b[0], case .paragraph(let c) = b[2] else { return XCTFail("\(b.map(kind))") }
        XCTAssertEqual(String(a.characters), "Some bold")
        XCTAssertEqual(String(c.characters), "after l")
        XCTAssertTrue(c.runs.contains { $0.link != nil })
        XCTAssertTrue(a.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    func testImageAfterHeadingLine() {
        XCTAssertEqual(kinds("# Title\n![alt](pic.png)"), ["h", "img:pic.png"])
    }

    func testConsecutiveImages() {
        XCTAssertEqual(kinds("![a](1.png)\n![b](2.png)\n![c](3.png)"), ["img:1.png", "img:2.png", "img:3.png"])
        XCTAssertEqual(kinds("![a](1.png)  \n![b](2.png)"), ["img:1.png", "img:2.png"])
    }

    func testImageThenTextAndTextThenImage() {
        XCTAssertEqual(kinds("![a](1.png)\ntext after"), ["img:1.png", "p"])
        XCTAssertEqual(kinds("text before\n![a](1.png)"), ["p", "img:1.png"])
    }

    func testImageInMiddleOfSentence() {
        XCTAssertEqual(kinds("before ![a](1.png) after"), ["p", "img:1.png", "p"])
    }

    func testImageInListAndQuote() {
        XCTAssertEqual(kinds("- item\n  ![a](1.png)\n- next"), ["l[p,img:1.png;p]"])
        XCTAssertEqual(kinds("> quoted\n> ![a](1.png)"), ["q[p,img:1.png]"])
    }

    func testImageInsideLinkStillShows() {
        XCTAssertEqual(kinds("[![alt](pic.png)](https://x.y)"), ["img:pic.png"])
        XCTAssertEqual(kinds("see\n[![alt](pic.png)](https://x.y)"), ["p", "img:pic.png"])
    }

    func testPlainParagraphUnchanged() {
        XCTAssertEqual(kinds("one\ntwo three"), ["p"])
        XCTAssertEqual(kinds("just an image\n\n![a](1.png)\n\nlast"), ["p", "img:1.png", "p"])
        guard case .paragraph(let a) = ViewerParser.parse("one\ntwo")[0] else { return XCTFail() }
        XCTAssertEqual(String(a.characters), "one two")
    }

    func testNoEmptyParagraphs() {
        for md in ["![a](1.png)", " ![a](1.png) ", "![a](1.png)\n![b](2.png)", "![a](1.png) ![b](2.png)"] {
            XCTAssertFalse(kinds(md).contains("p"), md)
        }
    }

    func testQuotesInTextPartsStaySmart() {
        let b = ViewerParser.parse("say\n![a](1.png)\n\"hi\"")
        guard b.count == 3, case .paragraph(let c) = b[2] else { return XCTFail() }
        XCTAssertEqual(String(c.characters), "“hi”")
    }

    func testHostileManyImagesIsFast() {
        let md = String(repeating: "text\n![a](p.png)\n", count: 5_000)
        within(5, "5,000 inline images") { XCTAssertEqual(ViewerParser.parse(md).count, 10_000) }
    }
}
