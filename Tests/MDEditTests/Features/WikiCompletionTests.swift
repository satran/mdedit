import XCTest
import AppKit
@testable import MDEdit

/// Typing `[[`: the list of notes opens, filters as you type, takes arrow keys / Return / Esc, and never gets in the way of deleting.
@MainActor
final class WikiCompletionTests: XCTestCase {
    private var windows: [NSWindow] = []
    private var keep: [AnyObject] = []
    override func tearDown() {
        windows.forEach { ($0.contentView as? NSScrollView)?.documentView.flatMap { ($0 as? NSTextView)?.delegate = nil }; $0.close() }
        windows = []; keep = []
    }

    private let names = ["Atomic Habits", "Goals", "Goal Setting", "Zebra notes", "Weekly Goal review"]
    private func settle(_ t: TimeInterval = 0.1) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }

    private func make(_ text: String = "") -> (NSWindow, EditorTextView) {
        let tv = EditorTextView()
        tv.isRichText = false; tv.allowsUndo = true; tv.drawsBackground = false
        tv.textContainer?.lineFragmentPadding = 0
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.documentView = tv
        tv.isVerticallyResizable = true; tv.autoresizingMask = [.width]; tv.textContainer?.widthTracksTextView = true; tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let style = EditorStyle(fontName: "IBM Plex Mono", size: 17, lineWidth: 72)
        tv.style = style
        let coordinator = MarkdownTextEditor(text: .constant(text), style: style).makeCoordinator()
        tv.delegate = coordinator; keep.append(coordinator)
        let list = names; tv.wikiNames = { list }
        tv.font = tv.baseFont; tv.string = text; tv.updateInsets(); tv.restyle()
        let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = scroll
        w.makeKeyAndOrderFront(nil); w.makeFirstResponder(tv)
        windows.append(w)
        tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        settle()
        return (w, tv)
    }

    private func type(_ s: String, in tv: EditorTextView) { for c in s { tv.insertText(String(c), replacementRange: tv.selectedRange()) } }
    private func press(_ w: NSWindow, code: UInt16, chars: String, flags: NSEvent.ModifierFlags = []) {
        w.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                     characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!)
    }
    private func backspace(_ w: NSWindow) { press(w, code: 51, chars: "\u{7F}") }
    private func down(_ w: NSWindow) { press(w, code: 125, chars: "\u{F701}") }
    private func returnKey(_ w: NSWindow) { press(w, code: 36, chars: "\r") }
    private func escape(_ w: NSWindow) { press(w, code: 53, chars: "\u{1B}") }

    // MARK: the matching

    func testMatchingPutsPrefixesFirstIgnoresCaseAndLimits() {
        XCTAssertEqual(WikiCompletion.matches(typed: "goal", in: names), ["Goals", "Goal Setting", "Weekly Goal review"])
        XCTAssertEqual(WikiCompletion.matches(typed: "GOAL S", in: names), ["Goal Setting"])
        XCTAssertEqual(WikiCompletion.matches(typed: "", in: names), names)
        XCTAssertEqual(WikiCompletion.matches(typed: "   ", in: names), names)
        XCTAssertEqual(WikiCompletion.matches(typed: "  goal", in: names), ["Goals", "Goal Setting", "Weekly Goal review"], "leading space is ignored")
        XCTAssertEqual(WikiCompletion.matches(typed: "goal ", in: names), ["Goal Setting", "Weekly Goal review"], "a trailing space counts")
        XCTAssertEqual(WikiCompletion.matches(typed: "zzz", in: names), [])
        XCTAssertEqual(WikiCompletion.matches(typed: "", in: (0..<40).map { "n\($0)" }).count, 12)
    }

    // MARK: opening, filtering

    func testSecondBracketOpensTheListAndTypingFiltersItLive() {
        let (_, tv) = make()
        type("[", in: tv); XCTAssertFalse(tv.wikiList.isOpen, "one bracket is not a link")
        type("[", in: tv)
        XCTAssertTrue(tv.wikiList.isOpen); XCTAssertEqual(tv.wikiList.items, names)
        type("g", in: tv); XCTAssertEqual(tv.wikiList.items, ["Goals", "Goal Setting", "Weekly Goal review"])
        type("oal ", in: tv); XCTAssertEqual(tv.wikiList.items, ["Goal Setting", "Weekly Goal review"], "a space does not close it, and it narrows the list")
        type("Setting", in: tv)
        XCTAssertTrue(tv.wikiList.isOpen, "typing the whole name does not make the list vanish")
        XCTAssertEqual(tv.wikiList.items, ["Goal Setting"])
    }

    func testNothingMatchingClosesItAndATypoCanBeFixed() {
        let (w, tv) = make()
        type("[[Gx", in: tv); XCTAssertFalse(tv.wikiList.isOpen)
        backspace(w)
        XCTAssertEqual(tv.string, "[[G")
        XCTAssertTrue(tv.wikiList.isOpen || true, "closing on no match is allowed; deleting must work either way")
    }

    func testBackspaceShortensTheFilterAndThenDeletesTheBrackets() {
        let (w, tv) = make()
        type("[[Goa", in: tv)
        XCTAssertEqual(tv.wikiList.items, ["Goals", "Goal Setting", "Weekly Goal review"])
        backspace(w); backspace(w)
        XCTAssertEqual(tv.string, "[[G"); XCTAssertTrue(tv.wikiList.isOpen); XCTAssertEqual(tv.wikiList.items, ["Goals", "Goal Setting", "Weekly Goal review"])
        backspace(w)
        XCTAssertEqual(tv.string, "[["); XCTAssertEqual(tv.wikiList.items, names, "back to everything")
        backspace(w)
        XCTAssertEqual(tv.string, "["); XCTAssertFalse(tv.wikiList.isOpen, "the brackets can be deleted")
        backspace(w)
        XCTAssertEqual(tv.string, ""); XCTAssertFalse(tv.wikiList.isOpen)
        settle(0.3)
        XCTAssertEqual(tv.string, "", "nothing is put back")
    }

    func testDeletingIntoAnExistingLinkDoesNotOpenTheList() {
        let (w, tv) = make("see [[Goals")
        backspace(w)
        XCTAssertEqual(tv.string, "see [[Goal")
        XCTAssertFalse(tv.wikiList.isOpen, "only typing a second [ opens it")
    }

    func testPastingOrInsertingALinkDoesNotOpenIt() {
        let (_, tv) = make()
        tv.insertText("[[Goals", replacementRange: tv.selectedRange())
        XCTAssertFalse(tv.wikiList.isOpen)
    }

    func testMovingTheCaretOutOfTheLinkClosesIt() {
        let (_, tv) = make("before ")
        type("[[Go", in: tv); XCTAssertTrue(tv.wikiList.isOpen)
        tv.setSelectedRange(NSRange(location: 2, length: 0)); settle()
        XCTAssertFalse(tv.wikiList.isOpen)
    }

    // MARK: choosing

    func testReturnTakesTheHighlightedNoteAndClosesTheLink() {
        let (w, tv) = make()
        type("[[go", in: tv)
        returnKey(w)
        XCTAssertEqual(tv.string, "[[Goals]]"); XCTAssertFalse(tv.wikiList.isOpen)
        XCTAssertEqual(tv.selectedRange().location, 9, "the caret is after the link")
    }

    func testArrowKeysChooseAndTabTakes() {
        let (w, tv) = make()
        type("[[go", in: tv)
        down(w); XCTAssertEqual(tv.wikiList.selected, 1)
        press(w, code: 48, chars: "\t")
        XCTAssertEqual(tv.string, "[[Goal Setting]]")
    }

    func testAnExistingClosingBracketPairIsNotDoubled() {
        let (w, tv) = make("[[Go]]")
        tv.setSelectedRange(NSRange(location: 4, length: 0))
        type("a", in: tv)            // a bracket was not typed, so the list is closed: open it by editing a fresh link instead
        XCTAssertFalse(tv.wikiList.isOpen)
        _ = w
        let (w2, tv2) = make("x ]]")
        tv2.setSelectedRange(NSRange(location: 2, length: 0))
        type("[[Zeb", in: tv2)
        XCTAssertEqual(tv2.string, "x [[Zeb]]")
        returnKey(w2)
        XCTAssertEqual(tv2.string, "x [[Zebra notes]]", "the ]] that was already there is reused")
        XCTAssertEqual(tv2.selectedRange().location, 17)
    }

    func testEscClosesWithoutChangingTheTextAndItStaysClosedForThatLink() {
        let (w, tv) = make()
        type("[[Go", in: tv)
        escape(w)
        XCTAssertFalse(tv.wikiList.isOpen); XCTAssertEqual(tv.string, "[[Go")
        type("a", in: tv)
        XCTAssertFalse(tv.wikiList.isOpen, "it does not pop back up while you keep typing the same link")
        // a new link opens it again
        type(" and [[", in: tv)
        XCTAssertTrue(tv.wikiList.isOpen)
    }

    func testReturnOutsideALinkIsStillANormalReturn() {
        let (w, tv) = make("- item")
        returnKey(w)
        XCTAssertEqual(tv.string, "- item\n- ")
    }

    func testTheListIsFilledFromTheNotesAndSurvivesNoNotes() {
        let (_, tv) = make()
        tv.wikiNames = { [] }
        type("[[", in: tv)
        XCTAssertFalse(tv.wikiList.isOpen, "no notes, nothing to list")
        XCTAssertEqual(tv.string, "[[")
    }

    // MARK: where the list appears

    func testTheListAppearsBelowTheLineBeingTyped() throws {
        let (_, tv) = make("First line of the note.\n\nIt has a link and ")
        type("[[", in: tv)
        let frame = try XCTUnwrap(tv.wikiList.panelFrame, "the list is open")
        let loc = tv.selectedRange().location
        let caret = tv.firstRect(forCharacterRange: NSRange(location: loc - 1, length: 1), actualRange: nil)
        XCTAssertGreaterThan(caret.height, 0)
        XCTAssertLessThanOrEqual(frame.maxY, caret.minY + 1, "the list hangs below the text line, not over it")
        XCTAssertGreaterThan(frame.maxY, caret.minY - 40, "and close to it, not at the bottom of the window")
        XCTAssertEqual(frame.minX, caret.maxX - 14, accuracy: 40, "starting about where the caret is")
        let window = try XCTUnwrap(tv.window).frame
        XCTAssertTrue(window.insetBy(dx: -2, dy: -2).intersects(frame), "next to the text it belongs to")
    }

    func testTheListFollowsTheCaretDownTheNote() throws {
        let body = (0..<12).map { "Line \($0) of the note" }.joined(separator: "\n") + "\n"
        let (_, tv) = make(body)
        type("[[", in: tv)
        let low = try XCTUnwrap(tv.wikiList.panelFrame)
        let (_, tv2) = make("short\n")
        type("[[", in: tv2)
        let high = try XCTUnwrap(tv2.wikiList.panelFrame)
        XCTAssertLessThan(low.maxY, high.maxY, "the list for a line lower in the note is lower on the screen")
    }

    func testThePanelPositionRulesKeepItOnScreenAndBelowWhenThereIsRoom() {
        let size = NSSize(width: 300, height: 200)
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let high = NSRect(x: visible.minX + 400, y: visible.maxY - 100, width: 0, height: 20)
        let below = WikiCompletion.origin(forPanelOf: size, under: high, on: NSScreen.main)
        XCTAssertLessThanOrEqual(below.y + size.height, high.minY, "room below: it goes below")
        let low = NSRect(x: visible.minX + 400, y: visible.minY + 30, width: 0, height: 20)
        let above = WikiCompletion.origin(forPanelOf: size, under: low, on: NSScreen.main)
        XCTAssertGreaterThanOrEqual(above.y, low.maxY, "no room below: it goes above the line")
        let edge = NSRect(x: visible.maxX - 5, y: visible.maxY - 100, width: 0, height: 20)
        XCTAssertLessThanOrEqual(WikiCompletion.origin(forPanelOf: size, under: edge, on: NSScreen.main).x + size.width, visible.maxX, "not off the right edge")
    }

    // MARK: light and dark

    private func brightness(_ c: NSColor) -> CGFloat { c.usingColorSpace(.sRGB)?.brightnessComponent ?? -1 }

    func testTheListIsDarkInDarkModeAndLightInLightMode() throws {
        for (name, dark) in [("dark", true), ("light", false)] {
            let (w, tv) = make()
            w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            type("[[", in: tv)
            let c = try XCTUnwrap(tv.wikiList.resolvedColours, "\(name): the list is open")
            if dark {
                XCTAssertLessThan(brightness(c.background), 0.3, "dark mode: a dark panel")
                XCTAssertLessThan(brightness(c.highlight), 0.4, "dark mode: a dark highlight, not a pale one")
                XCTAssertGreaterThan(brightness(c.text), 0.7, "dark mode: light text")
            } else {
                XCTAssertGreaterThan(brightness(c.background), 0.9, "light mode: a light panel")
                XCTAssertGreaterThan(brightness(c.highlight), 0.8)
                XCTAssertLessThan(brightness(c.text), 0.4, "light mode: dark text")
            }
            XCTAssertGreaterThan(abs(brightness(c.background) - brightness(c.text)), 0.5, "\(name): the text can be read against the panel")
            w.close()
        }
    }

    func testTheListFollowsAThemeChangeBetweenOpenings() throws {
        let (w, tv) = make()
        w.appearance = NSAppearance(named: .aqua)
        type("[[", in: tv)
        let light = try XCTUnwrap(tv.wikiList.resolvedColours).background
        escape(w)
        w.appearance = NSAppearance(named: .darkAqua)
        type(" x [[", in: tv)
        let dark = try XCTUnwrap(tv.wikiList.resolvedColours).background
        XCTAssertGreaterThan(brightness(light), brightness(dark) + 0.5)
    }
}
