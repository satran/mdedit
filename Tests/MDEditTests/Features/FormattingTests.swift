import XCTest
import SwiftUI
@testable import MDEdit

/// The Format menu: the pure transformation (table tests), then a real text view driven through the bridge.
///
/// Text is written with the selection inside it: `‹selected›`, or `|` for a caret.
@MainActor
final class FormattingTests: XCTestCase {
    // MARK: notation

    private func parse(_ marked: String) -> (String, NSRange) {
        var text = "", start: Int?, end: Int?, caret: Int?
        var n = 0
        for ch in marked {
            switch ch {
            case "‹": start = n
            case "›": end = n
            case "|": caret = n
            default: text.append(ch); n += ch.utf16.count
            }
        }
        if let caret { return (text, NSRange(location: caret, length: 0)) }
        return (text, NSRange(location: start ?? 0, length: (end ?? start ?? 0) - (start ?? 0)))
    }

    private func render(_ text: String, _ sel: NSRange) -> String {
        let ns = text as NSString
        let a = ns.substring(to: sel.location), b = ns.substring(with: NSRange(location: sel.location, length: sel.length)), c = ns.substring(from: NSMaxRange(sel))
        return sel.length == 0 ? a + "|" + c : a + "‹" + b + "›" + c
    }

    /// Runs the action on marked-up text and returns the marked-up result; nil when the action does nothing.
    private func run(_ action: FormatAction, _ marked: String) -> String? {
        let (text, sel) = parse(marked)
        guard let e = MarkdownFormatting.edit(action, in: text, selection: sel) else { return nil }
        let out = e.applied(to: text)
        XCTAssertLessThanOrEqual(NSMaxRange(e.selection), (out as NSString).length, "selection outside the text for \(marked)")
        return render(out, e.selection)
    }

    private func check(_ action: FormatAction, _ table: [(String, String)], file: StaticString = #filePath, line: UInt = #line) {
        for (input, expected) in table {
            XCTAssertEqual(run(action, input), expected, "\(action) on \(input.debugDescription)", file: file, line: line)
        }
    }

    // MARK: inline marks

    func testBoldWrapsUnwrapsAndHandlesWords() {
        check(.bold, [
            ("hello ‹world›", "hello **‹world›**"),
            ("hello **‹world›**", "hello ‹world›"),
            ("hello ‹**world**›", "hello ‹world›"),
            ("hel|lo", "**hel|lo**"),
            ("**hel|lo**", "hel|lo"),
            ("hello |", "hello **|**"),
            ("|", "**|**"),
            ("**|**", "|"),
            ("a ‹b ›c", "a **‹b›** c"),
            ("‹  ›", "  **|**"),
            ("end of line|", "end of **line|**"),
        ])
    }

    func testItalicAndBoldDoNotMangleEachOther() {
        check(.italic, [
            ("‹x›", "*‹x›*"),
            ("*‹x›*", "‹x›"),
            ("**‹x›**", "***‹x›***"),
            ("***‹x›***", "**‹x›**"),
            ("‹**x**›", "*‹**x**›*"),
            ("a *i|t* b", "a i|t b"),
            ("*|*", "|"),
        ])
        check(.bold, [
            ("*‹x›*", "***‹x›***"),
            ("***‹x›***", "*‹x›*"),
            ("***‹x›***", "*‹x›*"),
            ("**bo|ld**", "bo|ld"),
        ])
    }

    func testCodeStrikeAndHighlight() {
        check(.code, [("‹x›", "`‹x›`"), ("`‹x›`", "‹x›"), ("a|", "`a|`"), ("|", "`|`")])
        check(.strike, [("‹x y›", "~~‹x y›~~"), ("~~‹x y›~~", "‹x y›"), ("|", "~~|~~"), ("~~wo|rd~~", "wo|rd")])
        check(.highlight, [("‹x›", "::‹x›::"), ("::‹x›::", "‹x›"), ("|", "::|::")])
    }

    func testMarksWorkPerLineInMultiLineSelections() {
        check(.bold, [
            ("‹one\n\ntwo›", "‹**one**\n\n**two**›"),
            ("‹**one**\n\n**two**›", "‹one\n\ntwo›"),
            ("‹**one**\ntwo›", "‹**one**\n**two**›"),
        ])
    }

    func testMarksUseUTF16Offsets() {
        check(.bold, [("😀 ‹é›", "😀 **‹é›**"), ("‹😀›", "**‹😀›**"), ("a|😀b", "**a|**😀b"), ("😀|", "😀**|**"), ("日本|語 x", "**日本|語** x")])
        let e = MarkdownFormatting.edit(.bold, in: "😀 x", selection: NSRange(location: 3, length: 1))
        XCTAssertEqual(e?.range, NSRange(location: 3, length: 1))
        XCTAssertEqual(e?.selection, NSRange(location: 5, length: 1))
        XCTAssertEqual(e?.replacement, "**x**")
    }

    // MARK: link

    func testLink() {
        check(.link, [
            ("‹click›", "[click](‹url›)"),
            ("‹two words›", "[two words](‹url›)"),
            ("‹https://a.com/x›", "[|](https://a.com/x)"),
            ("see ‹www.a.com›", "see [|](www.a.com)"),
            ("‹mailto:a@b.c›", "[|](mailto:a@b.c)"),
            ("|", "[|](url)"),
            ("ab|cd", "ab[|](url)cd"),
            ("‹ x ›", " [x](‹url›) "),
            ("😀 ‹é›", "😀 [é](‹url›)"),
        ])
    }

    // MARK: line formats

    func testBulletsTasksQuotesOnOneAndManyLines() {
        check(.bullet, [
            ("|one", "- |one"), ("on|e", "- on|e"), ("one|", "- one|"),
            ("‹a\nb›", "‹- a\n- b›"), ("‹- a\n- b›", "‹a\nb›"), ("‹- a\nb›", "‹- a\n- b›"),
            ("‹a\n\nb›", "‹- a\n\n- b›"), ("- |a", "|a"), ("‹  a›", "‹  - a›"),
            ("‹# a›", "‹- a›"), ("‹> a›", "‹- a›"), ("‹1. a\n2. b›", "‹- a\n- b›"), ("‹* a\n+ b›", "‹a\nb›"),
        ])
        check(.task, [
            ("|a", "- [ ] |a"), ("‹- a\n- b›", "‹- [ ] a\n- [ ] b›"), ("‹- [ ] a\n- [x] b›", "‹a\nb›"),
            ("‹- [x] a›", "‹a›"), ("‹- [x] a\nb›", "‹- [x] a\n- [ ] b›"), ("‹  - a›", "‹  - [ ] a›"), ("‹1. a›", "‹- [ ] a›"),
        ])
        check(.bullet, [("‹- [x] a›", "‹- a›")])
        check(.quote, [
            ("|a", "> |a"), ("‹a\nb›", "‹> a\n> b›"), ("‹> a\n> b›", "‹a\nb›"), ("‹- a›", "‹> a›"), ("‹  - a›", "‹  > a›"), ("‹## a›", "‹> a›"),
        ])
    }

    func testNumberedListsCountInOrderAndPerIndent() {
        check(.numbered, [
            ("‹a\nb\nc›", "‹1. a\n2. b\n3. c›"),
            ("‹a\n\nb›", "‹1. a\n\n2. b›"),
            ("‹1. a\n2. b›", "‹a\nb›"),
            ("‹3. a\n9. b›", "‹a\nb›"),
            ("‹- a\n  - b\n- c›", "‹1. a\n  1. b\n2. c›"),
            ("‹a\n1. b›", "‹1. a\n2. b›"),
            ("‹- a\n- b›", "‹1. a\n2. b›"),
            ("|", "1. |"),
        ])
    }

    func testHeadingsToggleSwitchAndBecomeBody() {
        check(.heading(2), [
            ("|title", "## |title"), ("## |title", "|title"), ("# |title", "## |title"), ("### |title", "## |title"),
            ("‹- a›", "‹## a›"), ("‹  - a›", "‹## a›"), ("‹> a\nb›", "‹## a\n## b›"), ("‹## a\n## b›", "‹a\nb›"), ("‹# a\n## b›", "‹## a\n## b›"),
            ("####### x|", "## ####### x|"),
        ])
        for n in 1...6 {
            XCTAssertEqual(run(.heading(n), "x|"), String(repeating: "#", count: n) + " x|")
        }
        XCTAssertEqual(run(.heading(9), "x|"), "###### x|", "levels are clamped")
        check(.body, [("## |title", "|title"), ("‹# a\n## b\nc›", "‹a\nb\nc›"), ("#|", "|"), ("  # |x", "  |x")])
        XCTAssertNil(run(.body, "|plain"))
        XCTAssertNil(run(.body, "‹- list›"))
    }

    func testEdgesOfTheDocument() {
        check(.bullet, [("|", "- |"), ("a\n|b", "a\n- |b"), ("a\n|", "a\n- |"), ("|a\nb", "- |a\nb"), ("a\nb|", "a\n- b|")])
        check(.heading(1), [("|", "# |"), ("a\n|", "a\n# |")])
        check(.task, [("|", "- [ ] |")])
        check(.quote, [("|", "> |"), ("- |", "> |")])
        XCTAssertNotNil(MarkdownFormatting.edit(.bullet, in: "a\n\nb", selection: NSRange(location: 2, length: 0)))
        // all blank lines in a multi-line selection: nothing to do
        XCTAssertNil(run(.bullet, "‹\n\n›"))
    }

    func testSelectionsWithTrailingNewlinesOnlyTouchTheirLines() {
        check(.bullet, [("‹a\nb\n›c", "‹- a\n- b›\nc"), ("‹a\n›b", "‹- a›\nb"), ("x\n‹a\nb\n›", "x\n‹- a\n- b›\n")])
        check(.bullet, [("‹a\r\nb›", "‹- a\r\n- b›"), ("‹a\r\nb\r\n›", "‹- a\r\n- b›\r\n")])
    }

    func testLineFormatsWithUnicode() {
        check(.bullet, [("‹😀 a\né›", "‹- 😀 a\n- é›"), ("😀|", "- 😀|")])
        check(.heading(1), [("日本|語", "# 日本|語")])
        check(.numbered, [("‹😀\n日本›", "‹1. 😀\n2. 日本›")])
    }

    func testCaretMovesWithItsText() {
        check(.bullet, [("ab|cd", "- ab|cd"), ("- ab|cd", "ab|cd")])
        check(.heading(3), [("ab|cd", "### ab|cd"), ("### ab|cd", "ab|cd")])
        check(.quote, [("  ab|cd", "  > ab|cd")])
    }

    func testCodeBlock() {
        check(.codeBlock, [
            ("‹a\nb›", "```\n‹a\nb›\n```"),
            ("‹a\nb\n›c", "```\n‹a\nb›\n```\nc"),
            ("|", "```\n|\n```"),
            ("|x\ny", "```\n|x\n```\ny"),
            ("a\n|\nb", "a\n```\n|\n```\nb"),
            ("```\n‹a\nb›\n```", "‹a\nb›"),
            ("```\na|\n```", "a|"),
            ("```swift\n|x\n```\nafter", "|x\nafter"),
            ("before\n```\n‹x›\n```\nafter", "before\n‹x›\nafter"),
            ("```\ncode\n```\n\n|para", "```\ncode\n```\n\n```\n|para\n```"),
            ("~~~\n|x\n~~~", "|x"),
            ("```\nunclosed\n|x", "```\nunclosed\n```\n|x\n```"),
        ])
    }

    func testHorizontalRule() {
        check(.rule, [
            ("|", "---\n|"),
            ("abc|", "abc\n\n---\n|"),
            ("abc|\nnext", "abc\n\n---\n|next"),
            ("a\n|\nb", "a\n\n---\n|b"),
            ("x\n\n|\ny", "x\n\n---\n|y"),
        ])
    }

    func testEveryActionIsSafeOnAnyEdgeSelection() {
        let docs = ["", "\n", "a", "a\n", "\n\n", "# h\n- [ ] t\n1. n\n> q\n```\nc\n```\n", "😀\r\n日本", "**b** *i* `c` ~~s~~ ::h::", "   ", "[](u)"]
        for text in docs {
            let n = (text as NSString).length
            for loc in 0...n { for len in 0...(n - loc) {
                for action in FormatAction.all {
                    guard let e = MarkdownFormatting.edit(action, in: text, selection: NSRange(location: loc, length: len)) else { continue }
                    let ns = text as NSString
                    XCTAssertTrue(NSMaxRange(e.range) <= ns.length, "\(action) \(text.debugDescription) \(loc),\(len)")
                    let out = e.applied(to: text) as NSString
                    XCTAssertTrue(NSMaxRange(e.selection) <= out.length, "\(action) \(text.debugDescription) \(loc),\(len) selection")
                }
            } }
        }
        // positions outside the text are clamped, not crashes
        for action in FormatAction.all { _ = MarkdownFormatting.edit(action, in: "abc", selection: NSRange(location: 99, length: 50)) }
        for action in FormatAction.all { _ = MarkdownFormatting.edit(action, in: "", selection: NSRange(location: -4, length: -1)) }
    }

    func testMarkingTwiceRestoresTheText() {
        for (text, sel) in [("hello world", NSRange(location: 6, length: 5)), ("hello world", NSRange(location: 8, length: 0)), ("😀 é", NSRange(location: 3, length: 1))] {
            for action in [FormatAction.bold, .italic, .code, .strike, .highlight] {
                let e1 = MarkdownFormatting.edit(action, in: text, selection: sel)!
                let once = e1.applied(to: text)
                let e2 = MarkdownFormatting.edit(action, in: once, selection: e1.selection)!
                XCTAssertEqual(e2.applied(to: once), text, "\(action) twice on \(text) \(sel)")
            }
        }
    }

    // MARK: hostile input

    func testHugeLinesStayFast() {
        let long = String(repeating: "word ", count: 20_000)             // 100,000 characters, one line
        let stars = String(repeating: "*", count: 100_000)
        let many = (0..<50_000).map { "line \($0)" }.joined(separator: "\n")
        let ns = long as NSString
        let all = [NSRange(location: 0, length: ns.length), NSRange(location: 50_000, length: 0), NSRange(location: 3, length: 40_000)]
        _ = within(5, "every action on a 100,000-character line") {
            for sel in all { for a in FormatAction.all { _ = MarkdownFormatting.edit(a, in: long, selection: sel) } }
        }
        _ = within(5, "marks inside 100,000 asterisks") {
            for a in [FormatAction.bold, .italic, .code, .link] {
                _ = MarkdownFormatting.edit(a, in: stars, selection: NSRange(location: 50_000, length: 0))
                _ = MarkdownFormatting.edit(a, in: stars, selection: NSRange(location: 10, length: 99_000))
            }
        }
        let n = (many as NSString).length
        _ = within(10, "lists and code blocks over 50,000 lines") {
            for a in [FormatAction.bullet, .numbered, .task, .quote, .heading(2), .codeBlock, .bold] {
                _ = MarkdownFormatting.edit(a, in: many, selection: NSRange(location: 0, length: n))
                _ = MarkdownFormatting.edit(a, in: many, selection: NSRange(location: n / 2, length: 0))
            }
        }
        let fences = String(repeating: "```\nx\n```\n", count: 20_000)
        _ = within(5, "code block among 20,000 fences") {
            _ = MarkdownFormatting.edit(.codeBlock, in: fences, selection: NSRange(location: (fences as NSString).length - 3, length: 0))
        }
    }

    // MARK: a real text view

    private func makeView(_ marked: String, undo: Bool = false) -> (EditorTextView, EditorBridge, NSWindow?) {
        let (text, sel) = parse(marked)
        let tv = EditorTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        tv.isRichText = false
        tv.allowsUndo = true
        var window: NSWindow?
        if undo {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: true)
            window?.contentView = tv
        }
        tv.string = text
        tv.setSelectedRange(sel)
        let bridge = EditorBridge()
        bridge.textView = tv
        return (tv, bridge, window)
    }

    func testBridgeAppliesTextAndSelection() {
        for (action, input, expected) in [
            (FormatAction.bold, "hello ‹world›", "hello **‹world›**"),
            (.italic, "hel|lo", "*hel|lo*"),
            (.link, "‹click›", "[click](‹url›)"),
            (.heading(2), "ti|tle", "## ti|tle"),
            (.numbered, "‹a\nb›", "‹1. a\n2. b›"),
            (.codeBlock, "‹a›", "```\n‹a›\n```"),
        ] {
            let (tv, bridge, _) = makeView(input)
            XCTAssertTrue(bridge.apply(action))
            XCTAssertEqual(render(tv.string, tv.selectedRange()), expected, "\(action)")
        }
    }

    func testBridgeWithoutAnEditorDoesNothing() {
        XCTAssertFalse(EditorBridge().apply(.bold))
        let (tv, bridge, _) = makeView("x|")
        XCTAssertFalse(bridge.apply(.body), "nothing to change")
        XCTAssertEqual(tv.string, "x")
    }

    func testEachActionIsOneUndoStep() throws {
        for action in [FormatAction.bold, .link, .numbered, .heading(1), .codeBlock, .rule, .task] {
            let (tv, bridge, window) = makeView("‹one\ntwo›", undo: true)
            _ = window
            let um = try XCTUnwrap(tv.undoManager, "no undo manager")
            um.removeAllActions()
            let before = tv.string
            XCTAssertTrue(bridge.apply(action))
            XCTAssertNotEqual(tv.string, before)
            let after = tv.string
            XCTAssertTrue(um.canUndo, "\(action)")
            um.undo()
            XCTAssertEqual(tv.string, before, "one undo undoes \(action) completely")
            XCTAssertFalse(um.canUndo, "\(action) took more than one undo step")
            XCTAssertTrue(um.canRedo)
            um.redo()
            XCTAssertEqual(tv.string, after, "redo of \(action)")
        }
    }

    func testTwoActionsInARowAreTwoUndoSteps() throws {
        let (tv, bridge, window) = makeView("‹word›", undo: true)
        _ = window
        let um = try XCTUnwrap(tv.undoManager)
        um.removeAllActions()
        um.groupsByEvent = false   // the menu gives each command its own event; here the groups are closed by hand
        um.beginUndoGrouping(); bridge.apply(.bold); um.endUndoGrouping()
        um.beginUndoGrouping(); bridge.apply(.heading(1)); um.endUndoGrouping()
        XCTAssertEqual(tv.string, "# **word**")
        um.undo(); XCTAssertEqual(tv.string, "**word**")
        um.undo(); XCTAssertEqual(tv.string, "word")
    }

    func testFormattingRestylesAndReportsTheChange() {
        let (tv, bridge, _) = makeView("‹word›")
        var changed = 0
        let obs = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: tv, queue: nil) { _ in changed += 1 }
        defer { NotificationCenter.default.removeObserver(obs) }
        bridge.apply(.bold)
        XCTAssertEqual(changed, 1, "the delegate hears about the edit once, so the note is saved and restyled")
    }

    // MARK: commands

    func testEveryFormatActionIsInTheMenuAndPalette() {
        let cmds = makeCommands(ws: nil, prefs: Preferences(defaults: isolatedDefaults()), recents: RecentFolders(defaults: isolatedDefaults()), newWindow: { _ in })
        let format = cmds.filter { $0.place == .format }
        XCTAssertEqual(format.count, FormatAction.all.count)
        XCTAssertTrue(format.allSatisfy { $0.key != nil && !$0.enabled }, "no note open: all disabled")
        let shortcuts = Dictionary(uniqueKeysWithValues: format.map { ($0.title, $0.shortcut) })
        XCTAssertEqual(shortcuts["Bold"], "⌘B"); XCTAssertEqual(shortcuts["Italic"], "⌘I"); XCTAssertEqual(shortcuts["Link"], "⌘K")
        XCTAssertEqual(shortcuts["Inline Code"], "⌘E"); XCTAssertEqual(shortcuts["Strikethrough"], "⇧⌘X"); XCTAssertEqual(shortcuts["Highlight"], "⇧⌘H")
        XCTAssertEqual(shortcuts["Heading 1"], "⌥⌘1"); XCTAssertEqual(shortcuts["Heading 6"], "⌥⌘6"); XCTAssertEqual(shortcuts["Body Text"], "⌥⌘0")
        XCTAssertEqual(shortcuts["Bulleted List"], "⇧⌘8"); XCTAssertEqual(shortcuts["Numbered List"], "⇧⌘7"); XCTAssertEqual(shortcuts["Task List"], "⇧⌘T")
        XCTAssertEqual(shortcuts["Quote"], "⇧⌘."); XCTAssertEqual(shortcuts["Code Block"], "⌥⌘K"); XCTAssertEqual(shortcuts["Horizontal Rule"], "⌥⌘-")
        let found = PaletteView.filter(cmds, "heading").map(\.title)
        XCTAssertEqual(found.count, 6)
    }

    func testFormatCommandsNeedANoteInWriteMode() throws {
        let s = try Scratch(["A.md": "x"]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url)
        func enabled() -> Bool { formatCommands(ws: ws).allSatisfy(\.enabled) }
        ws.document.open(nil)
        XCTAssertFalse(enabled(), "no note open")
        ws.select(s.path("A.md"))
        XCTAssertTrue(enabled())
        ws.mode = .view
        XCTAssertFalse(formatCommands(ws: ws).contains(where: \.enabled), "not in View mode")
    }

    func testFormatCommandRunsOnTheFocusedEditor() throws {
        let s = try Scratch(["A.md": "x"]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url)
        let tv = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        tv.string = "word"; tv.setSelectedRange(NSRange(location: 0, length: 4))
        ws.editor.textView = tv
        formatCommands(ws: ws).first { $0.id == "format-bold" }?.run()
        XCTAssertEqual(tv.string, "**word**")
    }
}
