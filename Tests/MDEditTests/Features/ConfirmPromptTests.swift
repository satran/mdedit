import XCTest
import AppKit
@testable import MDEdit

@MainActor
final class ConfirmPromptTests: XCTestCase {
    func testTheDefaultAlertHasTheActionFirstAndAsDefault() {
        let a = ConfirmPrompt.makeAlert("Title", "Detail", "Render")
        XCTAssertEqual(a.buttons.map(\.title), ["Render", "Cancel"])
        XCTAssertEqual(a.buttons[0].keyEquivalent, "\r")
        XCTAssertNil(a.accessoryView)
        XCTAssertEqual(a.messageText, "Title"); XCTAssertEqual(a.informativeText, "Detail")
    }

    func testCancelCanBeTheDefault() {
        let a = ConfirmPrompt.makeAlert("T", "D", "Open", cancelIsDefault: true)
        XCTAssertEqual(a.buttons[1].title, "Cancel")
        XCTAssertEqual(a.buttons[1].keyEquivalent, "\r")
        XCTAssertEqual(a.buttons[0].keyEquivalent, "")
    }

    func testTheScrollingTextHoldsAllOfALongStringAndCannotBeEdited() throws {
        let long = String(repeating: "line of a template\n", count: 3_500)    // about 66 KB
        let a = ConfirmPrompt.makeAlert("T", "D", "Render", scrollingText: long)
        let scroll = try XCTUnwrap(a.accessoryView as? NSScrollView)
        let tv = try XCTUnwrap(scroll.documentView as? NSTextView)
        XCTAssertEqual(tv.string, long)
        XCTAssertFalse(tv.isEditable)
        XCTAssertTrue(tv.isSelectable)
        XCTAssertTrue(scroll.hasVerticalScroller)
    }
}
