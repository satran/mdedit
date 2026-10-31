import XCTest
import SwiftUI
@testable import MDEdit

/// The editing keys, run against a real text view with no window.
@MainActor
final class EditorBehaviorTests: XCTestCase {
    private func make(_ text: String, caret: Int? = nil) -> (EditorTextView, MarkdownTextEditor.Coordinator) {
        let tv = EditorTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        tv.string = text
        tv.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
        let c = MarkdownTextEditor(text: .constant(text), style: EditorStyle(fontName: "IBM Plex Mono", size: 16, lineWidth: 66)).makeCoordinator()
        return (tv, c)
    }

    func testReturnContinuesBulletsNumbersQuotesAndTasks() {
        for (text, expected) in [("- one", "- one\n- "), ("* one", "* one\n* "), ("1. one", "1. one\n2. "), ("9) nine", "9) nine\n10) "),
                                 ("> quote", "> quote\n> "), ("- [x] done", "- [x] done\n- [ ] "), ("  - nested", "  - nested\n  - ")] {
            let (tv, c) = make(text)
            XCTAssertTrue(c.continueList(tv), text)
            XCTAssertEqual(tv.string, expected, text)
        }
    }

    func testReturnOnAnEmptyItemEndsTheList() {
        let (tv, c) = make("- one\n- ")
        XCTAssertTrue(c.continueList(tv))
        XCTAssertEqual(tv.string, "- one\n")
    }

    func testReturnInPlainTextIsLeftToTheTextView() {
        let (tv, c) = make("just text")
        XCTAssertFalse(c.continueList(tv))
        XCTAssertEqual(tv.string, "just text")
    }

    func testReturnInTheMiddleOfAMarkerDoesNotTouchIt() {
        let (tv, c) = make("- one", caret: 1)
        XCTAssertFalse(c.continueList(tv), "before the text there is nothing to continue")
    }

    func testTabNestsAndShiftTabUnnests() {
        let (tv, c) = make("- one")
        XCTAssertTrue(c.shift(tv, by: 2)); XCTAssertEqual(tv.string, "  - one")
        XCTAssertTrue(c.shift(tv, by: -2)); XCTAssertEqual(tv.string, "- one")
        XCTAssertTrue(c.shift(tv, by: -2), "nothing to remove is not an error"); XCTAssertEqual(tv.string, "- one")
        let (plain, c2) = make("text")
        XCTAssertFalse(c2.shift(plain, by: 2), "outside a list, Tab is Tab")
    }

    func testBackspaceAfterABulletUnnestsThenRemovesIt() {
        let (tv, c) = make("  - ")
        XCTAssertTrue(c.deleteMarker(tv)); XCTAssertEqual(tv.string, "- ")
        XCTAssertTrue(c.deleteMarker(tv)); XCTAssertEqual(tv.string, "")
    }

    func testEveryEditingKeySurvivesAnEmptyAndAHugeDocument() {
        for text in ["", String(repeating: "- item\n", count: 20_000), String(repeating: "x", count: 500_000)] {
            let (tv, c) = make(text)
            _ = c.continueList(tv); _ = c.shift(tv, by: 2); _ = c.shift(tv, by: -2); _ = c.deleteMarker(tv)
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            _ = c.continueList(tv); _ = c.deleteMarker(tv)
        }
    }

    func testHeadingsAreBiggerOnlyWhenTheSettingIsOn() {
        let tv = EditorTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        tv.string = "# Title\n\nbody"
        tv.style = EditorStyle(fontName: "IBM Plex Mono", size: 16, lineWidth: 66, headingSizes: true)
        tv.restyle()
        let big = (tv.textStorage!.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
        tv.style = EditorStyle(fontName: "IBM Plex Mono", size: 16, lineWidth: 66, headingSizes: false)
        tv.restyle()
        let flat = (tv.textStorage!.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
        XCTAssertGreaterThan(big, flat)
        XCTAssertEqual(flat, 16)
    }

    func testMarkdownIsStyledNotChanged() {
        let text = "# H\n\n**bold** *it* `code` [[Link]] [a](https://x.y) ~~s~~\n\n- [ ] t\n> q\n"
        let tv = EditorTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        tv.string = text
        tv.restyle()
        XCTAssertEqual(tv.string, text, "styling never edits the text")
    }

    func testDroppedFilesBecomeLinksAtTheDropPoint() throws {
        let s = try Scratch(["Note.md": "x", "pic.png": "png"]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url)
        ws.select(s.path("Note.md"))
        let tv = EditorTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        tv.dropText = { ws.linkText(forDropped: $0) }
        XCTAssertEqual(tv.dropText?([s.path("pic.png")]), "![pic](pic.png)")
    }
}
