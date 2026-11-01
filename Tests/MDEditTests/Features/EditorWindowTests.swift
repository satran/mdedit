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

    func testShiftReturnIsJustANewLineInEveryKindOfList() {
        XCTAssertEqual(shiftReturn(on: "- [ ] task one"), "- [ ] task one\n", "a task: a new line, no new task")
        XCTAssertEqual(shiftReturn(on: "- [x] done"), "- [x] done\n")
        XCTAssertEqual(shiftReturn(on: "- bullet"), "- bullet\n")
        XCTAssertEqual(shiftReturn(on: "* star"), "* star\n")
        XCTAssertEqual(shiftReturn(on: "+ plus"), "+ plus\n")
        XCTAssertEqual(shiftReturn(on: "• dot"), "• dot\n")
        XCTAssertEqual(shiftReturn(on: "1. numbered"), "1. numbered\n")
        XCTAssertEqual(shiftReturn(on: "10. ten"), "10. ten\n")
        XCTAssertEqual(shiftReturn(on: "> quote"), "> quote\n")
        XCTAssertEqual(shiftReturn(on: "plain text"), "plain text\n")
        XCTAssertEqual(shiftReturn(on: "# Heading"), "# Heading\n")
    }

    func testShiftReturnOnlyAddsIndentWhenTheLineWasAlreadyIndented() {
        XCTAssertEqual(shiftReturn(on: "  - nested"), "  - nested\n  ")
        XCTAssertEqual(shiftReturn(on: "    - [ ] deep task"), "    - [ ] deep task\n    ")
        XCTAssertEqual(shiftReturn(on: "      continuation"), "      continuation\n      ")
        XCTAssertEqual(shiftReturn(on: "\tcode"), "\tcode\n\t")
    }

    func testShiftReturnInTheMiddleOfAnItemSplitsTheLine() {
        XCTAssertEqual(shiftReturn(on: "- [ ] one two", caret: 10), "- [ ] one \ntwo")
    }

    func testShiftReturnOnAnEmptyItemDoesNotEndTheList() {
        XCTAssertEqual(shiftReturn(on: "- [ ] "), "- [ ] \n")
        XCTAssertEqual(shiftReturn(on: "- "), "- \n")
    }

    func testShiftEnterOnTheKeypadDoesTheSame() {
        let (w, tv, _, _) = make("- [ ] a")
        tv.setSelectedRange(NSRange(location: 7, length: 0))
        press(w, code: 76, chars: "\u{3}", flags: .shift)
        XCTAssertEqual(tv.string, "- [ ] a\n")
    }

    func testPlainReturnStillContinuesTheListAndOptionReturnDoesTheSameAsShift() {
        let (w, tv, _, _) = make("- [ ] a")
        tv.setSelectedRange(NSRange(location: 7, length: 0))
        press(w, code: 36, chars: "\r")
        XCTAssertEqual(tv.string, "- [ ] a\n- [ ] ")
        let (w2, tv2, _, _) = make("- b")
        tv2.setSelectedRange(NSRange(location: 3, length: 0))
        press(w2, code: 36, chars: "\r", flags: .option)
        XCTAssertEqual(tv2.string, "- b\n")
    }

    func testShiftReturnTwiceNeverAddsAnItem() {
        let (w, tv, _, _) = make("- [ ] a")
        tv.setSelectedRange(NSRange(location: 7, length: 0))
        press(w, code: 36, chars: "\r", flags: .shift)
        tv.insertText("b", replacementRange: tv.selectedRange())
        press(w, code: 36, chars: "\r", flags: .shift)
        XCTAssertEqual(tv.string, "- [ ] a\nb\n", "no second task, no marker")
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

    // MARK: code blocks are one tinted band

    /// The colour of the pixel at the right-hand end of the line that starts with `needle`, inside the text column.
    private func pixel(onLineStarting needle: String, text: String, tv: EditorTextView, fromRight inset: CGFloat) -> NSColor? {
        let lm = tv.layoutManager!
        let g = lm.glyphIndexForCharacter(at: (text as NSString).range(of: needle).location)
        let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
        guard let rep = tv.bitmapImageRepForCachingDisplay(in: tv.bounds) else { return nil }
        tv.cacheDisplay(in: tv.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / tv.bounds.width
        let x = (tv.textContainerOrigin.x + tv.textContainer!.size.width - inset) * scale
        let y = (frag.midY + tv.textContainerOrigin.y) * scale
        return rep.colorAt(x: Int(x), y: Int(y))?.usingColorSpace(.sRGB)
    }

    func testACodeBlockHasItsBandAndOrdinaryTextHasNone() {
        let text = "## Heading\n\nprose with `inline code` here\n\n```swift\nlet x = 1\n```\n\ntext\n"
        let (_, tv, _, _) = make(text, size: NSSize(width: 1000, height: 700))
        XCTAssertGreaterThan(pixel(onLineStarting: "let x", text: text, tv: tv, fromRight: 30)?.alphaComponent ?? 0, 0.9, "the band is drawn behind the code")
        XCTAssertEqual(pixel(onLineStarting: "## Heading", text: text, tv: tv, fromRight: 30)?.alphaComponent ?? 1, 0, accuracy: 0.01, "nothing behind a heading")
        XCTAssertEqual(pixel(onLineStarting: "text", text: text, tv: tv, fromRight: 30)?.alphaComponent ?? 1, 0, accuracy: 0.01, "nothing behind a paragraph")
    }

    /// A chip stays under its own words: a wrapped inline-code span must not paint into the margin or the list's hanging indent.
    func testAWrappedInlineCodeChipStaysUnderItsWords() {
        let code = (0..<22).map { "word\($0)" }.joined(separator: " ")             // long enough to wrap in a 72-character column
        let text = "- see `\(code)` and then more text\n"
        let (_, tv, _, _) = make(text, size: NSSize(width: 1000, height: 700))
        let lm = tv.layoutManager!
        lm.ensureLayout(for: tv.textContainer!)
        let secondLine = (text as NSString).range(of: "word15")                        // on a wrapped line of the span
        let g = lm.glyphIndexForCharacter(at: secondLine.location)
        var fragmentRange = NSRange()
        let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: &fragmentRange)
        XCTAssertGreaterThan(fragmentRange.location, 0, "the code really wraps onto a second line")
        guard let rep = tv.bitmapImageRepForCachingDisplay(in: tv.bounds) else { return XCTFail() }
        tv.cacheDisplay(in: tv.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / tv.bounds.width
        func alpha(atX x: CGFloat) -> CGFloat {
            rep.colorAt(x: Int(x * scale), y: Int((frag.minY + tv.textContainerOrigin.y + 8) * scale))?.alphaComponent ?? -1
        }
        let origin = tv.textContainerOrigin.x
        let textStart = origin + lm.location(forGlyphAt: fragmentRange.location).x + frag.minX
        XCTAssertEqual(alpha(atX: origin + 6), 0, accuracy: 0.01, "nothing in the left margin")
        XCTAssertEqual(alpha(atX: origin + EditorTextView.gutter - 8), 0, accuracy: 0.01, "nothing in the gutter where the list marker hangs")
        XCTAssertGreaterThan(alpha(atX: textStart + 14), 0.9, "the chip is behind the words on the wrapped line")
    }

    // MARK: the caret comes back when the editor view is replaced

    /// A new editor view in a new window, attached to `bridge` the way the app's wrapper does it.
    private func newEditor(bridge: EditorBridge, text: String = "text") -> (NSWindow, EditorTextView) {
        let (w, tv, _, _) = make(text)
        tv.bridge = bridge
        bridge.textView = tv
        return (w, tv)
    }

    func testARequestForTheKeyboardWaitsForTheEditorThatReplacesTheOldOne() {
        let bridge = EditorBridge()
        let (w1, old) = newEditor(bridge: bridge)
        w1.makeFirstResponder(nil)
        bridge.requestFocus()
        XCTAssertTrue(w1.firstResponder === old, "an editor that is already there gets the keyboard at once")
        // the view is swapped (distraction free, or Write after View): the new editor arrives in a window
        let tv2 = EditorTextView()
        tv2.bridge = bridge
        let w2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        w2.isReleasedWhenClosed = false; windows.append(w2)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400)); scroll.documentView = tv2
        w2.contentView = scroll
        settle()
        XCTAssertTrue(w2.firstResponder === tv2, "the new editor has the keyboard, so its caret shows and typing starts at once")
    }

    func testAnUnansweredRequestDoesNotStealTheKeyboardLater() {
        let bridge = EditorBridge()
        bridge.requestFocus()                       // no editor: nobody answers
        settle(1.0)
        XCTAssertFalse(bridge.wantsFocus, "the request expires")
        let tv = EditorTextView(); tv.bridge = bridge
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false; windows.append(w)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400)); scroll.documentView = tv
        w.contentView = scroll
        settle()
        XCTAssertFalse(w.firstResponder === tv)
    }

    func testToggleDistractionFreeAsksForTheCaretBack() throws {
        let s = try Scratch(["a.md": "text"]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url)
        ws.select(s.path("a.md"))
        let was = Preferences.shared.focusFullScreen
        Preferences.shared.focusFullScreen = false          // do not take a window full screen from a test
        defer { Preferences.shared.focusFullScreen = was }
        XCTAssertFalse(ws.editor.wantsFocus)
        ws.toggleFocus()
        XCTAssertTrue(ws.editor.wantsFocus, "entering distraction free: the new editor gets the caret")
        ws.toggleFocus()
        XCTAssertTrue(ws.editor.wantsFocus, "and leaving it")
    }

    func testGoingBackToWriteFromViewAsksForTheCaretBack() throws {
        let s = try Scratch(["a.md": "text"]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url)
        ws.mode = .view
        settle(0.9)                                          // let any earlier request expire
        XCTAssertFalse(ws.editor.wantsFocus)
        ws.mode = .write
        XCTAssertTrue(ws.editor.wantsFocus)
    }
}
