import XCTest
import AppKit
@testable import MDEdit

/// `EditorTextView.insertOutput`: text replaces a range as one undo step and the caret lands after it. Find & Replace
/// uses it. Real text view in a real window.
@MainActor
final class EditorInsertTests: XCTestCase {
    var window: NSWindow!
    var tv: EditorTextView!
    private var coordinator: AnyObject?

    override func setUp() {
        tv = EditorTextView()
        tv.isRichText = false; tv.allowsUndo = true
        tv.textContainer?.lineFragmentPadding = 0
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scroll.documentView = tv
        tv.isVerticallyResizable = true; tv.autoresizingMask = [.width]; tv.textContainer?.widthTracksTextView = true
        let style = EditorStyle(fontName: "IBM Plex Mono", size: 16, lineWidth: 72)
        tv.style = style
        let c = MarkdownTextEditor(text: .constant(""), style: style).makeCoordinator()
        tv.delegate = c; coordinator = c
        tv.font = tv.baseFont; tv.string = "one\ntwo"; tv.restyle()
        window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(tv)
    }

    override func tearDown() {
        tv.delegate = nil; window.close()
        coordinator = nil; tv = nil
    }

    func testInsertingAtACaretPutsTheTextThereAndMovesTheCaretAfterIt() {
        tv.insertOutput("X", at: NSRange(location: 3, length: 0))
        XCTAssertEqual(tv.string, "oneX\ntwo")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testAnInsertionAfterASelectionLeavesTheSelectedTextAlone() {
        tv.setSelectedRange(NSRange(location: 4, length: 3))
        tv.insertOutput("<two>", at: NSRange(location: 7, length: 0))
        XCTAssertEqual(tv.string, "one\ntwo<two>")
    }

    func testAReplacementChangesOnlyTheRangeGiven() {
        tv.insertOutput("TWO", at: NSRange(location: 4, length: 3))
        XCTAssertEqual(tv.string, "one\nTWO")
    }

    func testReplacingTheWholeTextTakesEverything() {
        tv.insertOutput("ONE\nTWO", at: NSRange(location: 0, length: (tv.string as NSString).length))
        XCTAssertEqual(tv.string, "ONE\nTWO")
    }

    func testAReplacementIsASingleUndoStep() {
        tv.insertOutput("ONE\nTWO", at: NSRange(location: 0, length: (tv.string as NSString).length))
        tv.undoManager?.undo()
        XCTAssertEqual(tv.string, "one\ntwo", "one undo brings the text back")
    }

    func testALongInsertionIsASingleUndoStep() {
        tv.insertOutput((1...200).map(String.init).joined(separator: "\n"), at: NSRange(location: 3, length: 0))
        tv.undoManager?.undo()
        XCTAssertEqual(tv.string, "one\ntwo")
    }

    func testARangePastTheEndIsClamped() {
        tv.insertOutput("!", at: NSRange(location: 99, length: 5))
        XCTAssertEqual(tv.string, "one\ntwo!")
    }

    func testNothingHappensInAViewThatCannotBeEdited() {
        tv.isEditable = false
        tv.insertOutput("X", at: NSRange(location: 0, length: 0))
        XCTAssertEqual(tv.string, "one\ntwo")
    }
}
