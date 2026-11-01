import XCTest
import AppKit
@testable import MDEdit

/// The editor in a real (offscreen) window with real key events and a real scroll view: what a person does at the keyboard.
/// These tests exist because tests that call the editor's methods directly passed while the app itself still misbehaved.
@MainActor
final class EditorWindowTests: XCTestCase {
    private var windows: [NSWindow] = []
    /// A text view does not retain its delegate (SwiftUI keeps the coordinator alive in the app), so the tests must.
    private var coordinators: [AnyObject] = []
    override func tearDown() {
        windows.forEach { ($0.contentView as? NSScrollView)?.documentView.flatMap { ($0 as? NSTextView)?.delegate = nil }; $0.close() }
        windows = []; coordinators = []
    }

    private func settle(_ t: TimeInterval = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }

    private func make(_ text: String, size: NSSize = NSSize(width: 800, height: 600)) -> (NSWindow, EditorTextView, NSScrollView, MarkdownTextEditor.Coordinator) {
        let tv = EditorTextView()
        tv.isRichText = false; tv.allowsUndo = true; tv.drawsBackground = false
        tv.textContainer?.lineFragmentPadding = 0
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = tv
        tv.isVerticallyResizable = true; tv.isHorizontallyResizable = false; tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true; tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let style = EditorStyle(fontName: "IBM Plex Mono", size: 17, lineWidth: 72)
        tv.style = style
        let coordinator = MarkdownTextEditor(text: .constant(text), style: style).makeCoordinator()
        tv.delegate = coordinator
        coordinators.append(coordinator)
        tv.font = tv.baseFont; tv.string = text; tv.updateInsets(); tv.restyle()
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false          // ARC owns the window; closing must not release it a second time
        w.contentView = scroll
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(tv)
        windows.append(w)
        settle()
        return (w, tv, scroll, coordinator)
    }

    private func press(_ w: NSWindow, code: UInt16, chars: String, flags: NSEvent.ModifierFlags = []) {
        let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                  characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        w.sendEvent(ev)
    }

    // MARK: Shift-Return, as the keyboard sends it

    private func shiftReturn(on text: String, caret: Int? = nil) -> String {
        let (w, tv, _, _) = make(text)
        tv.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
        press(w, code: 36, chars: "\r", flags: .shift)
        return tv.string
    }

    func testShiftReturnNeverStartsANewItemInAnyKindOfList() {
        XCTAssertEqual(shiftReturn(on: "- [ ] task one"), "- [ ] task one\n      ", "a task: indented under its text, no new task")
        XCTAssertEqual(shiftReturn(on: "- [x] done"), "- [x] done\n      ")
        XCTAssertEqual(shiftReturn(on: "- bullet"), "- bullet\n  ")
        XCTAssertEqual(shiftReturn(on: "* star"), "* star\n  ")
        XCTAssertEqual(shiftReturn(on: "+ plus"), "+ plus\n  ")
        XCTAssertEqual(shiftReturn(on: "• dot"), "• dot\n  ")
        XCTAssertEqual(shiftReturn(on: "1. numbered"), "1. numbered\n   ")
        XCTAssertEqual(shiftReturn(on: "10. ten"), "10. ten\n    ")
        XCTAssertEqual(shiftReturn(on: "9) paren"), "9) paren\n   ")
        XCTAssertEqual(shiftReturn(on: "  - nested"), "  - nested\n    ", "a nested item keeps its own indentation")
        XCTAssertEqual(shiftReturn(on: "    - [ ] deep task"), "    - [ ] deep task\n          ")
    }

    func testShiftReturnInTheMiddleOfAnItemKeepsTheRestUnderTheText() {
        XCTAssertEqual(shiftReturn(on: "- [ ] one two", caret: 10), "- [ ] one \n      two")
    }

    func testShiftReturnOnAnEmptyItemDoesNotEndTheList() {
        XCTAssertEqual(shiftReturn(on: "- [ ] "), "- [ ] \n      ")
        XCTAssertEqual(shiftReturn(on: "- "), "- \n  ")
    }

    func testShiftReturnKeepsAQuoteAndLeavesPlainTextAlone() {
        XCTAssertEqual(shiftReturn(on: "> quote"), "> quote\n> ")
        XCTAssertEqual(shiftReturn(on: "plain text"), "plain text\n")
        XCTAssertEqual(shiftReturn(on: "# Heading"), "# Heading\n")
    }

    func testShiftEnterOnTheKeypadDoesTheSame() {
        let (w, tv, _, _) = make("- [ ] a")
        tv.setSelectedRange(NSRange(location: 7, length: 0))
        press(w, code: 76, chars: "\u{3}", flags: .shift)
        XCTAssertEqual(tv.string, "- [ ] a\n      ")
    }

    func testPlainReturnStillContinuesTheListAndOptionReturnStillIndents() {
        let (w, tv, _, _) = make("- [ ] a")
        tv.setSelectedRange(NSRange(location: 7, length: 0))
        press(w, code: 36, chars: "\r")
        XCTAssertEqual(tv.string, "- [ ] a\n- [ ] ")
        let (w2, tv2, _, _) = make("- b")
        tv2.setSelectedRange(NSRange(location: 3, length: 0))
        press(w2, code: 36, chars: "\r", flags: .option)
        XCTAssertEqual(tv2.string, "- b\n  ")
    }

    func testShiftReturnTwiceKeepsIndentingTheSameItem() {
        let (w, tv, _, _) = make("- [ ] a")
        tv.setSelectedRange(NSRange(location: 7, length: 0))
        press(w, code: 36, chars: "\r", flags: .shift)
        tv.insertText("b", replacementRange: tv.selectedRange())
        press(w, code: 36, chars: "\r", flags: .shift)
        XCTAssertEqual(tv.string, "- [ ] a\n      b\n      ", "no second task appears")
    }

    // MARK: typewriter mode

    private func caretY(_ tv: EditorTextView) -> CGFloat {
        let lm = tv.layoutManager!; lm.ensureLayout(for: tv.textContainer!)
        let loc = tv.selectedRange().location
        var rect = NSRect.zero
        if loc >= (tv.string as NSString).length {
            rect = lm.extraLineFragmentRect
            if rect.isEmpty, lm.numberOfGlyphs > 0 { rect = lm.lineFragmentRect(forGlyphAt: lm.numberOfGlyphs - 1, effectiveRange: nil) }
        } else { rect = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: loc), effectiveRange: nil) }
        return rect.midY + tv.textContainerOrigin.y
    }

    private let shortNote = "# Title\n\nA short note\nwith a few lines\n"
    private var longNote: String { (0..<200).map { "Line \($0) of a long note" }.joined(separator: "\n") }

    private func assertCaretInView(_ tv: EditorTextView, _ scroll: NSScrollView, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let vis = scroll.contentView.documentVisibleRect, y = caretY(tv)
        XCTAssertTrue(y >= vis.minY && y <= vis.maxY, "\(what): the caret (y \(Int(y))) is outside the visible \(Int(vis.minY))–\(Int(vis.maxY))", file: file, line: line)
    }

    func testEnablingTypewriterModeNeverLosesTheCaretAndCentresIt() {
        for (name, text, caret) in [("short, caret at end", shortNote, -1), ("short, caret at start", shortNote, 0), ("long, middle", longNote, 2000), ("long, end", longNote, -1), ("long, start", longNote, 0)] {
            let (_, tv, scroll, _) = make(text)
            tv.setSelectedRange(NSRange(location: caret < 0 ? (text as NSString).length : caret, length: 0)); settle()
            tv.typewriter = true; settle()
            assertCaretInView(tv, scroll, "\(name) after enabling")
            let vis = scroll.contentView.documentVisibleRect
            XCTAssertEqual(caretY(tv) - vis.minY, vis.height / 2, accuracy: 6, "\(name): the caret line is in the middle of the pane")
            XCTAssertLessThanOrEqual(tv.frame.height, (tv.layoutManager!.usedRect(for: tv.textContainer!).maxY + 2 * tv.textContainerInset.height) + 1, "\(name): the view is not taller than its content")
        }
    }

    func testDisablingTypewriterModeDoesNotThrowThePageAway() {
        for (name, text, caret) in [("short, end", shortNote, -1), ("short, start", shortNote, 0), ("long, middle", longNote, 2000), ("long, end", longNote, -1)] {
            let (_, tv, scroll, _) = make(text)
            tv.setSelectedRange(NSRange(location: caret < 0 ? (text as NSString).length : caret, length: 0)); settle()
            tv.typewriter = true; settle()
            tv.typewriter = false; settle()
            assertCaretInView(tv, scroll, "\(name) after disabling")
            let paneH = scroll.contentView.bounds.height
            let content = tv.layoutManager!.usedRect(for: tv.textContainer!).maxY + 2 * tv.textContainerInset.height
            XCTAssertLessThanOrEqual(tv.frame.height, max(content, paneH) + 1, "\(name): the view shrank back to its content")
            if content <= paneH { XCTAssertEqual(scroll.contentView.bounds.origin.y, 0, accuracy: 1, "\(name): a short note shows from the top, not scrolled down over empty space") }
        }
    }

    func testTurningTypewriterOffKeepsTheCaretWhereItWasOnTheScreen() {
        let (_, tv, scroll, _) = make(longNote)
        tv.setSelectedRange(NSRange(location: 4000, length: 0)); settle()
        tv.typewriter = true; settle()
        let before = caretY(tv) - scroll.contentView.bounds.origin.y
        tv.typewriter = false; settle()
        let after = caretY(tv) - scroll.contentView.bounds.origin.y
        XCTAssertEqual(after, before, accuracy: 6, "the caret stays at the same height on the screen, so the eye does not have to look for it")
    }

    func testTogglingManyTimesStaysStable() {
        let (_, tv, scroll, _) = make(shortNote)
        tv.setSelectedRange(NSRange(location: (shortNote as NSString).length, length: 0))
        for _ in 0..<6 { tv.typewriter = true; settle(0.05); tv.typewriter = false; settle(0.05) }
        settle()
        assertCaretInView(tv, scroll, "after six toggles")
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 0, accuracy: 1)
    }

    func testTypingKeepsTheCaretCentredInTypewriterMode() {
        let (w, tv, scroll, _) = make(longNote)
        tv.setSelectedRange(NSRange(location: 3000, length: 0))
        tv.typewriter = true; settle()
        for _ in 0..<5 { press(w, code: 36, chars: "\r"); tv.insertText("new line", replacementRange: tv.selectedRange()) }
        settle()
        let vis = scroll.contentView.documentVisibleRect
        XCTAssertEqual(caretY(tv) - vis.minY, vis.height / 2, accuracy: 30)
    }

    func testClosingTheCommandPaletteGivesTheCaretBack() {
        let s = try! Scratch(["a.md": "text"]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url)
        let (w, tv, _, _) = make("text")
        ws.editor.textView = tv
        ws.paletteVisible = true
        w.makeFirstResponder(nil)                      // the palette's field took the keyboard
        ws.paletteVisible = false
        settle()
        XCTAssertTrue(w.firstResponder === tv, "the note has the keyboard again, so its caret shows")
    }

    // MARK: fold chevrons

    /// Dark pixels in a strip of the text view's left margin on the line that starts with `of`, left of where its hanging marker starts
    /// (so the marker itself, the `#` or the bullet, is not counted).
    private func ink(left of: String, in text: String, tv: EditorTextView, w: NSWindow) -> Int {
        let lm = tv.layoutManager!
        let r = (text as NSString).range(of: of)
        let g = lm.glyphIndexForCharacter(at: r.location)
        let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
        let markerLeft = tv.textContainerOrigin.x + frag.minX + lm.location(forGlyphAt: g).x
        let strip = NSRect(x: 0, y: frag.minY + tv.textContainerOrigin.y, width: max(0, markerLeft - 2), height: frag.height)
        guard strip.width > 4, let rep = tv.bitmapImageRepForCachingDisplay(in: tv.bounds) else { return 0 }
        tv.cacheDisplay(in: tv.bounds, to: rep)
        var count = 0
        let scale = CGFloat(rep.pixelsWide) / tv.bounds.width
        for px in Int(strip.minX * scale)..<Int(strip.maxX * scale) {
            for py in Int(strip.minY * scale)..<min(rep.pixelsHigh, Int(strip.maxY * scale)) {
                if let c = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB), c.alphaComponent > 0.1, c.brightnessComponent < 0.85 { count += 1 }
            }
        }
        return count
    }

    func testFoldableHeadingsAndListItemsShowAChevronAndOthersDoNot() {
        let text = "# Title\nbody under the title\n\n## Sub\nmore body\n\n- item\n  - child\n\n## Empty\n"
        let (w, tv, _, _) = make(text, size: NSSize(width: 1000, height: 700))
        XCTAssertGreaterThan(ink(left: "# Title", in: text, tv: tv, w: w), 6, "a heading with text under it shows a chevron")
        XCTAssertGreaterThan(ink(left: "## Sub", in: text, tv: tv, w: w), 6)
        XCTAssertGreaterThan(ink(left: "- item", in: text, tv: tv, w: w), 6, "a list item with children shows one")
        XCTAssertEqual(ink(left: "## Empty", in: text, tv: tv, w: w), 0, "a heading with nothing under it does not")
        XCTAssertEqual(ink(left: "  - child", in: text, tv: tv, w: w), 0, "an item without children does not")
    }

    func testTheChevronIsVisibleInANarrowWindowToo() {
        let text = "# Title\nbody\n"
        let (w, tv, _, _) = make(text, size: NSSize(width: 520, height: 500))
        XCTAssertGreaterThan(ink(left: "# Title", in: text, tv: tv, w: w), 6)
    }
}
