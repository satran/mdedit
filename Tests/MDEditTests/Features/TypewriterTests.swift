import XCTest
import AppKit
@testable import MDEdit

/// Typewriter mode keeps the caret's line in the vertical middle of the pane, including when it is switched on
/// while the caret is scrolled out of view.
final class TypewriterTests: XCTestCase {
    private func make(lines: Int = 300, text: String? = nil) -> (EditorTextView, NSScrollView) {
        let tv = EditorTextView()
        tv.isRichText = false
        tv.textContainer?.lineFragmentPadding = 0
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))
        scroll.hasVerticalScroller = true
        scroll.documentView = tv
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.font = tv.baseFont
        tv.string = text ?? (0..<lines).map { "Line \($0) of the document" }.joined(separator: "\n")
        tv.updateInsets()
        tv.restyle()
        return (tv, scroll)
    }

    private func caretMidY(_ tv: EditorTextView) -> CGFloat {
        let lm = tv.layoutManager!
        lm.ensureLayout(for: tv.textContainer!)
        let loc = tv.selectedRange().location
        var rect = NSRect.zero
        if loc >= (tv.string as NSString).length {
            rect = lm.extraLineFragmentRect
            if rect.isEmpty, lm.numberOfGlyphs > 0 { rect = lm.lineFragmentRect(forGlyphAt: lm.numberOfGlyphs - 1, effectiveRange: nil) }
        } else {
            rect = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: loc), effectiveRange: nil)
        }
        return rect.midY + tv.textContainerOrigin.y
    }

    private func assertCentred(_ tv: EditorTextView, _ scroll: NSScrollView, file: StaticString = #filePath, line: UInt = #line) {
        let clip = scroll.contentView
        let offset = caretMidY(tv) - clip.bounds.origin.y - clip.bounds.height / 2
        XCTAssertEqual(offset, 0, accuracy: 4, "caret line is \(offset)pt from the middle", file: file, line: line)
    }

    func testEnablingScrollsAwayCaretToCentre() {
        let (tv, scroll) = make()
        tv.setSelectedRange(NSRange(location: ("Line 0 of the document\n" as NSString).length * 150, length: 0))
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        tv.typewriter = true
        assertCentred(tv, scroll)
    }

    func testToggleOnOffOn() {
        let (tv, scroll) = make()
        tv.setSelectedRange(NSRange(location: 4000, length: 0))
        tv.typewriter = true
        assertCentred(tv, scroll)
        tv.typewriter = false
        XCTAssertEqual(tv.textContainerInset.height, EditorTextView.verticalInset)
        tv.setSelectedRange(NSRange(location: 100, length: 0))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 3000)); scroll.reflectScrolledClipView(scroll.contentView)
        tv.typewriter = true
        assertCentred(tv, scroll)
    }

    func testCaretAtStartAndEnd() {
        let (tv, scroll) = make()
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 3000)); scroll.reflectScrolledClipView(scroll.contentView)
        tv.typewriter = true
        assertCentred(tv, scroll)
        tv.typewriter = false
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        tv.typewriter = true
        assertCentred(tv, scroll)
    }

    func testEmptyDocument() {
        let (tv, scroll) = make(text: "")
        tv.typewriter = true
        XCTAssertGreaterThanOrEqual(tv.textContainerInset.height, 299)
        assertCentred(tv, scroll)
    }

    func testDisablingRestoresInsets() {
        let (tv, _) = make()
        tv.typewriter = true
        XCTAssertGreaterThan(tv.textContainerInset.height, EditorTextView.verticalInset)
        tv.typewriter = false
        XCTAssertEqual(tv.textContainerInset.height, EditorTextView.verticalInset)
    }
}
