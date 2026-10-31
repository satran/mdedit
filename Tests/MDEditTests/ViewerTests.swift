import XCTest
import SwiftUI
@testable import MDEdit

final class ViewerTests: XCTestCase {
    func testGFMBlocks() {
        let md = """
        # Title

        Para with **bold** and ~~gone~~ and [site](https://dora.dev).

        - [x] done
        - [ ] todo

        1. one
        2. two

        | a | b |
        |:--|--:|
        | 1 | 2 |

        > quote

        ```swift
        let x = 1
        ```

        ---
        """
        let blocks = ViewerParser.parse(md)
        var names: [String] = []
        for b in blocks {
            switch b {
            case .heading: names.append("h")
            case .paragraph: names.append("p")
            case .list(let ordered, _, let items):
                names.append(ordered ? "ol" : "ul")
                if !ordered { XCTAssertEqual(items.map(\.checkbox), [true, false]) }
            case .table(let h, let aligns, let rows):
                names.append("table")
                XCTAssertEqual(h.count, 2); XCTAssertEqual(rows.count, 1); XCTAssertEqual(aligns.count, 2)
            case .quote: names.append("q")
            case .code(let c, let lang): names.append("code"); XCTAssertEqual(c, "let x = 1"); XCTAssertEqual(lang, "swift")
            case .rule: names.append("hr")
            default: names.append("?")
            }
        }
        XCTAssertEqual(names, ["h", "p", "ul", "ol", "table", "q", "code", "hr"])
    }

    func testInlineIntentsAndLinks() {
        guard case .paragraph(let a) = ViewerParser.parse("**b** ~~s~~ `c` [l](https://x.io)")[0] else { return XCTFail() }
        let intents = a.runs.compactMap(\.inlinePresentationIntent)
        XCTAssertTrue(intents.contains(.stronglyEmphasized))
        XCTAssertTrue(intents.contains(.strikethrough))
        XCTAssertTrue(intents.contains(.code))
        XCTAssertEqual(a.runs.compactMap(\.link).first?.absoluteString, "https://x.io")
    }

    func testWikiLinkAndBareURLBecomeLinks() {
        guard case .paragraph(let a) = ViewerParser.parse("go [[Goals|our goals]] or https://dora.dev.")[0] else { return XCTFail() }
        let links = a.runs.compactMap(\.link)
        XCTAssertEqual(WikiLink.target(from: links[0]), "Goals")
        XCTAssertEqual(links[1].absoluteString, "https://dora.dev")
        XCTAssertEqual(String(a.characters), "go our goals or https://dora.dev.")
    }

    func testWikiLinkParts() {
        let l = WikiLink.parse("[[folder/Note#Head|alias]]")[0].link
        XCTAssertEqual(l.note, "folder/Note"); XCTAssertEqual(l.heading, "Head"); XCTAssertEqual(l.shown, "alias")
        XCTAssertEqual(WikiLink.target(from: l.url!), "folder/Note#Head")
    }

    func testWordCount() {
        XCTAssertEqual(DocumentStore.wordCount("one two  three\nfour"), 4)
        XCTAssertEqual(DocumentStore.readMinutes(words: 132), 1)
        XCTAssertEqual(DocumentStore.readMinutes(words: 1000), 5)
    }
}

final class DocumentStoreTests: XCTestCase {
    func testSaveAndReload() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("doc-\(UUID().uuidString).md")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let d = DocumentStore()
        d.open(url)
        XCTAssertEqual(d.text, "hello")
        d.text = "changed"
        d.saveNow()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "changed")
        // outside edit while clean is picked up
        Thread.sleep(forTimeInterval: 0.05)
        try "outside".write(to: url, atomically: true, encoding: .utf8)
        d.checkDisk()
        XCTAssertEqual(d.text, "outside")
        // outside edit while dirty is flagged, not overwritten
        d.text = "mine"
        Thread.sleep(forTimeInterval: 0.05)
        try "again".write(to: url, atomically: true, encoding: .utf8)
        d.checkDisk()
        XCTAssertTrue(d.changedOnDisk)
        XCTAssertEqual(d.text, "mine")
    }
}
