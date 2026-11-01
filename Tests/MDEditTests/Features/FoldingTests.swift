import XCTest
import AppKit
@testable import MDEdit

/// Folding hides a heading's section or a list item's children without touching the text.
final class FoldingTests: XCTestCase {

    // MARK: helpers

    private func ns(_ s: String) -> NSString { s as NSString }
    private func hiddenText(_ text: String, _ b: FoldBlock) -> String { ns(text).substring(with: b.hidden) }
    private func header(_ text: String, _ b: FoldBlock) -> String { ns(text).substring(with: b.header) }
    private func headings(_ text: String) -> [FoldBlock] { Folding.blocks(in: text).filter { $0.level != nil } }

    // MARK: pure: headings

    func testEveryHeadingLevelFoldsToTheNextOfTheSameOrHigherLevel() {
        for level in 1...6 {
            let marks = String(repeating: "#", count: level)
            let text = "\(marks) Title\nbody\n\(marks) Next\nmore\n"
            let b = Folding.blocks(in: text)
            XCTAssertEqual(b.count, 2, "level \(level)")
            XCTAssertEqual(b[0].kind, .heading(level))
            XCTAssertEqual(header(text, b[0]), "\(marks) Title")
            XCTAssertEqual(hiddenText(text, b[0]), "body\n")
            XCTAssertEqual(hiddenText(text, b[1]), "more\n")
        }
    }

    func testNestedHeadingsFoldInsideTheirParent() {
        let text = "# A\na\n## B\nb\n### C\nc\n## D\nd\n# E\ne\n"
        let b = Folding.blocks(in: text)
        XCTAssertEqual(b.map { header(text, $0) }, ["# A", "## B", "### C", "## D", "# E"])
        XCTAssertEqual(hiddenText(text, b[0]), "a\n## B\nb\n### C\nc\n## D\nd\n")
        XCTAssertEqual(hiddenText(text, b[1]), "b\n### C\nc\n")
        XCTAssertEqual(hiddenText(text, b[2]), "c\n")
        XCTAssertEqual(hiddenText(text, b[3]), "d\n")
        XCTAssertEqual(hiddenText(text, b[4]), "e\n")
    }

    func testAHigherHeadingEndsALowerOneAndALevelSkipStillNests() {
        let text = "## A\na\n#### B\nb\n# C\nc\n"
        let b = Folding.blocks(in: text)
        XCTAssertEqual(hiddenText(text, b[0]), "a\n#### B\nb\n")
        XCTAssertEqual(hiddenText(text, b[1]), "b\n")
    }

    func testLastHeadingRunsToTheEndOfTheNote() {
        let terminated = "# A\nx\ny\n"
        XCTAssertEqual(hiddenText(terminated, Folding.blocks(in: terminated)[0]), "x\ny\n")
        XCTAssertFalse(Folding.blocks(in: terminated)[0].unterminated)
        // no final line break: the header's own break goes too, so no empty line is left behind
        let bare = "# A\nx\ny"
        let b = Folding.blocks(in: bare)[0]
        XCTAssertTrue(b.unterminated)
        XCTAssertEqual(hiddenText(bare, b), "\nx\ny")
        XCTAssertEqual(ns(bare).substring(with: b.header), "# A")
    }

    func testEmptySectionsAreNotFoldable() {
        XCTAssertTrue(Folding.blocks(in: "# A\n# B\n").isEmpty)
        XCTAssertTrue(Folding.blocks(in: "# A").isEmpty)
        XCTAssertTrue(Folding.blocks(in: "# A\n").isEmpty)
        XCTAssertTrue(Folding.blocks(in: "# A\n\n\n  \n# B\n").isEmpty, "only blank lines under it")
        XCTAssertTrue(Folding.blocks(in: "").isEmpty)
        XCTAssertTrue(Folding.blocks(in: "just text\nmore text").isEmpty)
    }

    func testTrailingBlankLinesStayVisible() {
        let text = "# A\nbody\n\n\n# B\nb\n"
        let b = Folding.blocks(in: text)
        XCTAssertEqual(hiddenText(text, b[0]), "body\n")
        // blank lines inside the section are hidden
        let inner = "# A\none\n\ntwo\n\n# B\nb\n"
        XCTAssertEqual(hiddenText(inner, Folding.blocks(in: inner)[0]), "one\n\ntwo\n")
    }

    func testOnlyRealHeadingsCount() {
        for not in ["#nospace\nx", " # indented\nx", "\t# tab\nx", "####### seven\nx", "#\nx"] {
            XCTAssertTrue(headings(not).isEmpty, not)
        }
        XCTAssertEqual(headings("###### six\nx").count, 1)
    }

    func testHeadingsInsideCodeFencesAreIgnored() {
        let text = "# A\n```\n# not a heading\nstuff\n```\ntail\n# B\nb\n"
        let b = Folding.blocks(in: text)
        XCTAssertEqual(b.map { header(text, $0) }, ["# A", "# B"])
        XCTAssertEqual(hiddenText(text, b[0]), "```\n# not a heading\nstuff\n```\ntail\n")
        // a tilde fence, and a fence that is never closed swallows the rest
        let open = "# A\nx\n~~~\n# no\n## no\n"
        XCTAssertEqual(Folding.blocks(in: open).count, 1)
        XCTAssertEqual(hiddenText(open, Folding.blocks(in: open)[0]), "x\n~~~\n# no\n## no\n")
        // a fence of the other kind does not close it
        let mixed = "```\n# a\n~~~\n# b\n```\n# real\nx\n"
        XCTAssertEqual(Folding.blocks(in: mixed).map { header(mixed, $0) }, ["# real"])
    }

    func testFrontMatterIsNotFoldable() {
        let text = "---\ntitle: T\n# comment-ish\ntags: [a]\n---\n# A\nbody\n"
        let b = Folding.blocks(in: text)
        XCTAssertEqual(b.map { header(text, $0) }, ["# A"])
        XCTAssertEqual(hiddenText(text, b[0]), "body\n")
        let onlyFM = "---\ntitle: T\n---\n"
        XCTAssertTrue(Folding.blocks(in: onlyFM).isEmpty)
    }

    // MARK: pure: lists

    func testListItemHidesItsNestedChildren() {
        let text = "- a\n  - b\n    - c\n  - d\n- e\n"
        let b = Folding.blocks(in: text)
        XCTAssertEqual(b.map { header(text, $0) }, ["- a", "  - b"])
        XCTAssertEqual(hiddenText(text, b[0]), "  - b\n    - c\n  - d\n")
        XCTAssertEqual(hiddenText(text, b[1]), "    - c\n")
        XCTAssertEqual(b[0].kind, .listItem)
    }

    func testItemWithoutChildrenIsNotFoldable() {
        XCTAssertTrue(Folding.blocks(in: "- a\n- b\n- c\n").isEmpty)
        XCTAssertTrue(Folding.blocks(in: "- a").isEmpty)
    }

    func testBlankLinesBetweenChildrenAreHiddenButTrailingOnesAreNot() {
        let text = "- a\n\n  - b\n\n  - c\n\n- d\n"
        let b = Folding.blocks(in: text)
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(hiddenText(text, b[0]), "\n  - b\n\n  - c\n")
    }

    func testContinuationLinesAreChildren() {
        let text = "- one\n  continued here\n  and here\n- two\n"
        let b = Folding.blocks(in: text)
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(hiddenText(text, b[0]), "  continued here\n  and here\n")
        // a lazy, unindented continuation ends the item (it is not "more indented")
        XCTAssertTrue(Folding.blocks(in: "- one\nlazy\n").isEmpty)
    }

    func testTaskNumberedAndOtherMarkers() {
        let text = "1. a\n   - [ ] t\n   - [x] u\n2) b\n   x\n• c\n  y\n+ d\n  z\n* e\n  w\n"
        let b = Folding.blocks(in: text)
        XCTAssertEqual(b.map { header(text, $0) }, ["1. a", "2) b", "• c", "+ d", "* e"])
        XCTAssertEqual(hiddenText(text, b[0]), "   - [ ] t\n   - [x] u\n")
        // rules are not items
        XCTAssertTrue(Folding.blocks(in: "- - -\n  x\n").isEmpty)
        XCTAssertTrue(Folding.blocks(in: "***\n  x\n").isEmpty)
        // "-text" and "1.text" are not items
        XCTAssertTrue(Folding.blocks(in: "-a\n  x\n1.a\n  y\n").isEmpty)
    }

    func testMixedTabsAndSpaces() {
        // a tab is four columns: the tab line is a child of "- a" but a sibling of nothing
        let text = "- a\n\t- b\n\t\t- c\n    - d\n- e\n"
        let b = Folding.blocks(in: text)
        XCTAssertEqual(b.map { header(text, $0) }, ["- a", "\t- b"])
        XCTAssertEqual(hiddenText(text, b[0]), "\t- b\n\t\t- c\n    - d\n")
        XCTAssertEqual(hiddenText(text, b[1]), "\t\t- c\n", "four spaces is the same level as one tab, so d is a sibling of b")
    }

    func testAListEndsAtAHeadingAndAHeadingHoldsItsLists() {
        let text = "# H\n- a\n  - b\n# I\n- c\n  - d\n"
        let b = Folding.blocks(in: text)
        XCTAssertEqual(b.map { header(text, $0) }, ["# H", "- a", "# I", "- c"])
        XCTAssertEqual(hiddenText(text, b[0]), "- a\n  - b\n")
        XCTAssertEqual(hiddenText(text, b[1]), "  - b\n")
    }

    func testListItemsInCodeFencesAreIgnoredAndFencesInItemsAreChildren() {
        let text = "```\n- a\n  - b\n```\n- c\n  ```\n  code\n```\n  - d\n"
        let b = Folding.blocks(in: text)
        XCTAssertEqual(b.map { header(text, $0) }, ["- c"])
        // the unindented closing fence is still inside the fence, so the fence belongs to the item
        XCTAssertEqual(hiddenText(text, b[0]), "  ```\n  code\n```\n  - d\n")
    }

    // MARK: pure: line endings, Unicode, shape

    func testCRLFAndCRLineBreaks() {
        let crlf = "# A\r\nbody\r\n\r\n# B\r\nb\r\n"
        let b = Folding.blocks(in: crlf)
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(header(crlf, b[0]), "# A")
        XCTAssertEqual(hiddenText(crlf, b[0]), "body\r\n")
        XCTAssertEqual(b[0].body.location, 5)
        let cr = "# A\rbody\r# B\rb"
        let c = Folding.blocks(in: cr)
        XCTAssertEqual(c.map { header(cr, $0) }, ["# A", "# B"])
        XCTAssertEqual(hiddenText(cr, c[0]), "body\r")
        // without a final break the CRLF after the header goes with the body
        let bare = "# A\r\nx"
        XCTAssertEqual(hiddenText(bare, Folding.blocks(in: bare)[0]), "\r\nx")
    }

    func testUnicodeOffsetsAreUTF16() {
        let text = "# 日本語 🎉 émoji\n👨‍👩‍👧 text\n## Sub ✓\nx\n"
        let b = Folding.blocks(in: text)
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(header(text, b[0]), "# 日本語 🎉 émoji")
        XCTAssertEqual(hiddenText(text, b[0]), "👨‍👩‍👧 text\n## Sub ✓\nx\n")
        XCTAssertEqual(hiddenText(text, b[1]), "x\n")
        XCTAssertEqual(NSMaxRange(b[0].body), ns(text).length)
    }

    func testBlocksAreInDocumentOrderAndRangesAreInsideTheText() {
        var rng = SeededRNG(seed: 7)
        let pieces = ["# H\n", "## h\n", "- a\n", "  - b\n", "text\n", "\n", "```\n", "\t- t\n", "1. n\n", "###### x\n", "  more\n"]
        for round in 0..<200 {
            var text = ""
            for _ in 0..<Int.random(in: 1...40, using: &rng) { text += pieces.randomElement(using: &rng)! }
            if round % 3 == 0 { text.removeLast() }
            let len = ns(text).length
            let b = Folding.blocks(in: text)
            var previous = -1
            for blk in b {
                XCTAssertGreaterThan(blk.header.location, previous, "seed 7 round \(round)")
                previous = blk.header.location
                XCTAssertGreaterThan(blk.body.length, 0)
                XCTAssertLessThanOrEqual(NSMaxRange(blk.body), len)
                XCTAssertEqual(blk.body.location, NSMaxRange(blk.header) + (text.utf16.count > NSMaxRange(blk.header) ? 1 : 0), "seed 7 round \(round)")
                XCTAssertFalse(blk.hidden.length == 0)
            }
        }
    }

    // MARK: pure: hostile and fast

    func testHundredThousandHeadingsAreFast() {
        let text = (0..<100_000).map { "# H\($0)\nx\n" }.joined()
        var count = 0
        within(3, "100,000 headings") { count = Folding.blocks(in: text).count }
        XCTAssertEqual(count, 100_000)
        let bare = String(repeating: "# \n", count: 100_000)
        within(3, "100,000 empty headings") { XCTAssertTrue(Folding.blocks(in: bare).isEmpty) }
    }

    func testOneMegabyteLineIsFast() {
        let line = String(repeating: "word ", count: 210_000)
        within(3, "one 1 MB line") { XCTAssertTrue(Folding.blocks(in: line).isEmpty) }
        let item = "- " + line + "\n  - child\n"
        within(3, "one 1 MB list line") { XCTAssertEqual(Folding.blocks(in: item).count, 1) }
        let rule = String(repeating: "- ", count: 500_000)
        within(3, "one 1 MB rule-like line") { _ = Folding.blocks(in: rule) }
    }

    func testDeepListNestingIsFast() {
        let text = (0..<5_000).map { String(repeating: " ", count: $0 * 2) + "- item\n" }.joined()
        var blocks: [FoldBlock] = []
        within(5, "5,000 nested levels") { blocks = Folding.blocks(in: text) }
        XCTAssertEqual(blocks.count, 4_999)
        XCTAssertEqual(NSMaxRange(blocks[0].body), (text as NSString).length)
    }

    func testFourHundredKilobyteNoteIsFast() {
        var text = ""
        var i = 0
        while text.utf8.count < 400_000 {
            text += "## Section \(i)\nSome words in a paragraph of the note.\n\n- item one\n  - nested\n  continuation\n- item two\n\n"
            i += 1
        }
        within(1, "400 KB note") { _ = Folding.blocks(in: text) }
    }

    // MARK: the editor

    private func make(_ text: String, folded: Bool = false) -> (EditorTextView, NSScrollView) {
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
        tv.string = text
        tv.updateInsets()
        tv.restyle()
        return (tv, scroll)
    }

    private func height(_ tv: EditorTextView) -> CGFloat {
        tv.layoutManager!.ensureLayout(for: tv.textContainer!)
        return tv.layoutManager!.usedRect(for: tv.textContainer!).height
    }

    /// The characters whose glyphs are null (not drawn).
    private func nullCharacters(_ tv: EditorTextView) -> [Int] {
        let lm = tv.layoutManager!
        lm.ensureLayout(for: tv.textContainer!)
        var out: [Int] = []
        for g in 0..<lm.numberOfGlyphs where lm.propertyForGlyph(at: g).contains(.null) { out.append(lm.characterIndexForGlyph(at: g)) }
        return out
    }

    private let doc = "# One\nalpha\nbeta\n\n## Two\ngamma\n\n# Three\ndelta\n"

    func testFoldingHidesTheRightGlyphsAndShrinksTheText() {
        let (tv, _) = make(doc)
        let before = height(tv)
        XCTAssertTrue(nullCharacters(tv).isEmpty)
        let one = tv.foldBlocks[0]
        tv.toggleFold(headerAt: one.header.location)
        let hidden = tv.hiddenRanges
        XCTAssertEqual(hidden, [one.body])
        let expected = Array(one.body.location..<NSMaxRange(one.body))
        XCTAssertEqual(nullCharacters(tv), expected)
        XCTAssertLessThan(height(tv), before - 60, "five lines disappeared")
        // the line below the fold is where the heading's section used to end
        let lm = tv.layoutManager!
        let threeY = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: (doc as NSString).range(of: "# Three").location), effectiveRange: nil).minY
        let oneY = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY
        XCTAssertLessThan(threeY - oneY, 120, "the next heading is close under the folded one")
        tv.toggleFold(headerAt: one.header.location)
        XCTAssertTrue(nullCharacters(tv).isEmpty)
        XCTAssertEqual(height(tv), before, accuracy: 0.5)
    }

    func testTheStringTheUndoStackAndSelectAllAreUntouched() {
        let (tv, _) = make(doc)
        tv.allowsUndo = true
        let undoBefore = tv.undoManager?.canUndo ?? false
        tv.foldAll()
        XCTAssertEqual(tv.string, doc)
        XCTAssertEqual(tv.textStorage?.string, doc)
        XCTAssertEqual(tv.undoManager?.canUndo ?? false, undoBefore)
        XCTAssertTrue(tv.hasFolds)
        tv.selectAll(nil)
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 0, length: (doc as NSString).length))
        XCTAssertTrue(tv.hasFolds, "Select All does not unfold")
        let pb = NSPasteboard(name: NSPasteboard.Name("folding-test-\(UUID().uuidString)"))
        pb.clearContents()
        XCTAssertTrue(pb.writeObjects([(tv.string as NSString).substring(with: tv.selectedRange()) as NSString]))
        XCTAssertEqual(pb.string(forType: .string), doc, "copy includes the hidden text")
        tv.unfoldAll()
        XCTAssertEqual(tv.string, doc)
        XCTAssertFalse(tv.hasFolds)
    }

    func testFoldedHeadingKeepsItsMarkerAndNestedFoldsSurviveAParentToggle() {
        let (tv, _) = make(doc)
        let two = tv.foldBlocks[1], one = tv.foldBlocks[0]
        tv.toggleFold(headerAt: two.header.location)
        tv.toggleFold(headerAt: one.header.location)
        XCTAssertEqual(tv.hiddenRanges, [one.body], "the inner fold is inside the outer one")
        tv.toggleFold(headerAt: one.header.location)
        XCTAssertEqual(tv.hiddenRanges, [two.body], "the inner fold is still folded")
        // headings still hang their marker: the paragraph style of the visible heading is untouched
        let style = tv.textStorage!.attribute(.paragraphStyle, at: one.header.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertGreaterThan(style?.firstLineHeadIndent ?? 0, 0)
        XCTAssertGreaterThan(style?.minimumLineHeight ?? 0, -1)
        let hiddenStyle = tv.textStorage!.attribute(.paragraphStyle, at: two.body.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertLessThan(hiddenStyle?.maximumLineHeight ?? 99, 1)
    }

    func testFoldCommandsAtTheCaret() {
        let text = "# One\nalpha\n## Two\nbeta\n- a\n  - b\n"
        let (tv, _) = make(text)
        let ns = text as NSString
        // caret in "beta": folds the innermost block, "## Two"
        tv.setSelectedRange(NSRange(location: ns.range(of: "beta").location, length: 0))
        XCTAssertTrue(tv.foldAtCaret())
        XCTAssertEqual(tv.foldedHeaders, [ns.range(of: "## Two").location])
        XCTAssertEqual(tv.selectedRange().location, NSMaxRange(ns.paragraphRange(for: NSRange(location: ns.range(of: "## Two").location, length: 0))) - 1, "the caret moved to the end of the folded heading")
        // fold again on that heading: its parent
        XCTAssertTrue(tv.foldAtCaret())
        XCTAssertEqual(Set(tv.foldedHeaders), [0, ns.range(of: "## Two").location])
        // unfold at the caret (now on "# One"): the block under the caret only
        tv.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertTrue(tv.unfoldAtCaret())
        XCTAssertEqual(tv.foldedHeaders, [ns.range(of: "## Two").location])
        XCTAssertFalse(tv.unfoldAtCaret(), "nothing folded at the caret")
        // list item
        tv.setSelectedRange(NSRange(location: ns.range(of: "- a").location, length: 0))
        XCTAssertTrue(tv.foldAtCaret())
        XCTAssertEqual(tv.foldedHeaders, [ns.range(of: "- a").location], "\"- a\" is under ## Two, which opened to show it")
        tv.unfoldAll()
        XCTAssertTrue(tv.foldedHeaders.isEmpty)
        // outside any block
        let (plain, _) = make("nothing here\n")
        XCTAssertFalse(plain.foldAtCaret())
    }

    func testFoldAllAndUnfoldAll() {
        let (tv, _) = make(doc)
        tv.toggleFoldAll()
        XCTAssertEqual(tv.foldedHeaders.count, 3)
        XCTAssertEqual(tv.hiddenRanges.count, 2, "## Two is inside # One, so the hidden ranges are merged")
        tv.toggleFoldAll()
        XCTAssertFalse(tv.hasFolds)
        XCTAssertTrue(nullCharacters(tv).isEmpty)
        tv.foldAll()
        tv.unfoldAll()
        XCTAssertFalse(tv.hasFolds)
    }

    func testTheCaretNeverRestsOnHiddenText() {
        let (tv, _) = make(doc)
        let one = tv.foldBlocks[0]
        tv.toggleFold(headerAt: one.header.location)
        // the end of the heading line and the start of the next visible block are fine
        tv.setSelectedRange(NSRange(location: NSMaxRange(one.header), length: 0))
        XCTAssertTrue(tv.hasFolds)
        tv.setSelectedRange(NSRange(location: NSMaxRange(one.body), length: 0))
        XCTAssertTrue(tv.hasFolds)
        // anywhere inside the hidden text unfolds (find, the outline, arrow keys at the end of the heading)
        let beta = (doc as NSString).range(of: "beta").location
        tv.setSelectedRange(NSRange(location: beta + 1, length: 0))
        XCTAssertFalse(tv.hasFolds)
        XCTAssertEqual(tv.selectedRange(), NSRange(location: beta + 1, length: 0))
        // a selection that ends inside hidden text unfolds too; one that only covers it does not
        tv.toggleFold(headerAt: one.header.location)
        tv.setSelectedRange(NSRange(location: 0, length: beta))
        XCTAssertFalse(tv.hasFolds)
        tv.toggleFold(headerAt: one.header.location)
        tv.setSelectedRange(NSRange(location: 0, length: NSMaxRange(one.body)))
        XCTAssertTrue(tv.hasFolds, "covering a fold is not landing in it")
    }

    func testFindingTextInsideAFoldRevealsIt() {
        let (tv, _) = make(doc)
        tv.foldAll()
        XCTAssertTrue(tv.hasFolds)
        let r = (doc as NSString).range(of: "gamma")
        tv.setSelectedRange(r)
        XCTAssertEqual(tv.selectedRange(), r)
        XCTAssertTrue(nullCharacters(tv).filter { NSLocationInRange($0, r) }.isEmpty, "the match is visible")
        XCTAssertEqual(tv.foldedHeaders, [(doc as NSString).range(of: "# Three").location], "only the folds around it opened")
    }

    func testTypingOnTheFoldedHeadingKeepsItFolded() {
        let (tv, _) = make(doc)
        let one = tv.foldBlocks[0]
        tv.toggleFold(headerAt: one.header.location)
        tv.setSelectedRange(NSRange(location: NSMaxRange(one.header), length: 0))
        tv.insertText("!", replacementRange: tv.selectedRange())
        tv.restyle()
        XCTAssertTrue(tv.string.hasPrefix("# One!\nalpha\n"))
        XCTAssertEqual(tv.foldedHeaders, [0], "typing in the heading itself does not unfold it")
        XCTAssertEqual(tv.hiddenRanges.count, 1)
        XCTAssertEqual(NSMaxRange(tv.hiddenRanges[0]), NSMaxRange(one.body) + 1)
    }

    func testReturnAtTheEndOfAFoldedHeadingAndBackspaceIntoItUnfold() {
        let (tv, _) = make(doc)
        let one = tv.foldBlocks[0]
        tv.toggleFold(headerAt: one.header.location)
        tv.setSelectedRange(NSRange(location: NSMaxRange(one.header), length: 0))
        tv.insertText("\n", replacementRange: tv.selectedRange())
        tv.restyle()
        XCTAssertFalse(tv.hasFolds, "a new line there would have been hidden")
        XCTAssertTrue(tv.string.hasPrefix("# One\n\nalpha\n"))

        let (b, _) = make(doc)
        let o = b.foldBlocks[0]
        b.toggleFold(headerAt: o.header.location)
        b.setSelectedRange(NSRange(location: NSMaxRange(o.body), length: 0))
        XCTAssertTrue(b.hasFolds)
        b.deleteBackward(nil)                     // would remove the last hidden line break
        b.restyle()
        XCTAssertFalse(b.hasFolds)
        XCTAssertTrue(b.string.contains("gamma\n# Three"), "the line break was removed after the text was shown")
    }

    func testTypingBeforeAFoldKeepsItOnTheSameSection() {
        let (tv, _) = make(doc)
        let three = (doc as NSString).range(of: "# Three").location
        tv.toggleFold(headerAt: three)
        XCTAssertEqual(tv.foldedHeaders, [three])
        // type at the very start of the note
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.insertText("INTRO paragraph\n\n", replacementRange: tv.selectedRange())
        tv.restyle()
        let moved = (tv.string as NSString).range(of: "# Three").location
        XCTAssertEqual(moved, three + 17)
        XCTAssertEqual(tv.foldedHeaders, [moved])
        XCTAssertEqual(tv.hiddenRanges.map { (tv.string as NSString).substring(with: $0) }, ["delta\n"])
        // delete a line above it
        tv.setSelectedRange(NSRange(location: 0, length: 17))
        tv.insertText("", replacementRange: tv.selectedRange())
        tv.restyle()
        XCTAssertEqual(tv.foldedHeaders, [three])
        XCTAssertEqual(tv.hiddenRanges.map { (tv.string as NSString).substring(with: $0) }, ["delta\n"])
    }

    func testInsertingALineBreakAtTheStartOfAFoldedHeadingMovesTheFold() {
        let (tv, _) = make(doc)
        let three = (doc as NSString).range(of: "# Three").location
        tv.toggleFold(headerAt: three)
        tv.setSelectedRange(NSRange(location: three, length: 0))
        tv.insertText("\n", replacementRange: tv.selectedRange())
        tv.restyle()
        XCTAssertEqual(tv.foldedHeaders, [three + 1])
        // typing a letter in front of "#" makes it plain text: the fold goes
        tv.setSelectedRange(NSRange(location: three + 1, length: 0))
        tv.insertText("x", replacementRange: tv.selectedRange())
        tv.restyle()
        XCTAssertFalse(tv.hasFolds)
    }

    func testEditingTheHeadingAwayDropsTheFoldAndEmptyingTheSectionDoes() {
        let (tv, _) = make("# A\nbody\n# B\nb\n")
        tv.toggleFold(headerAt: 0)
        tv.setSelectedRange(NSRange(location: 0, length: 2))
        tv.insertText("", replacementRange: tv.selectedRange())     // "# " removed
        tv.restyle()
        XCTAssertFalse(tv.hasFolds)
        XCTAssertTrue(tv.hiddenRanges.isEmpty)
        XCTAssertTrue(nullCharacters(tv).isEmpty)

        let (u, _) = make("# A\nbody\n# B\nb\n")
        u.toggleFold(headerAt: 0)
        u.setSelectedRange(NSRange(location: 4, length: 5))
        u.insertText("", replacementRange: u.selectedRange())       // removes the body: hidden text, so it unfolds first
        u.restyle()
        XCTAssertFalse(u.hasFolds)
        XCTAssertEqual(u.string, "# A\n# B\nb\n")
    }

    func testReplacingTheWholeNoteOrOpeningAnotherClearsFolds() {
        let (tv, _) = make(doc)
        tv.foldAll()
        tv.string = "# New\nbody\n"
        tv.restyle()
        XCTAssertFalse(tv.hasFolds, "a replaced note starts unfolded")
        XCTAssertTrue(tv.hiddenRanges.isEmpty)
        tv.toggleFold(headerAt: 0)
        tv.clearFolds()
        XCTAssertFalse(tv.hasFolds)
        XCTAssertTrue(nullCharacters(tv).isEmpty)
    }

    func testLastSectionWithoutFinalBreakHidesCleanly() {
        let text = "# A\nx\n# B\ny"
        let (tv, _) = make(text)
        let before = height(tv)
        tv.toggleFold(headerAt: (text as NSString).range(of: "# B").location)
        XCTAssertLessThan(height(tv), before)
        XCTAssertEqual(tv.string, text)
        // the end of the note is hidden text now: the caret there reveals the section
        tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        XCTAssertFalse(tv.hasFolds)
    }

    func testFoldedListItemHidesChildrenAndKeepsItsBullet() {
        let text = "- parent\n  - child\n  - child two\n- sibling\n"
        let (tv, _) = make(text)
        let before = height(tv)
        tv.toggleFold(headerAt: 0)
        XCTAssertEqual(tv.hiddenRanges.map { (text as NSString).substring(with: $0) }, ["  - child\n  - child two\n"])
        XCTAssertLessThan(height(tv), before - 40)
        XCTAssertFalse(nullCharacters(tv).contains(0))
    }

    func testCodeBlockBandAndLayoutStillWorkWhenFolded() {
        let text = "# A\n```\ncode\n```\n# B\n```\nmore\n```\n"
        let (tv, scroll) = make(text)
        tv.toggleFold(headerAt: 0)
        scroll.layoutSubtreeIfNeeded()
        // drawing everything with a fold in the middle must not trap
        let img = tv.bitmapImageRepForCachingDisplay(in: tv.bounds)!
        tv.cacheDisplay(in: tv.bounds, to: img)
        XCTAssertEqual(tv.string, text)
        XCTAssertEqual(tv.syntax.spans.filter { $0.kind == .codeBlock }.count, 6)
    }

    func testTypewriterStillCentresTheCaretAfterAFold() {
        let text = (0..<80).map { "# H\($0)\nline a\nline b\n" }.joined()
        let (tv, scroll) = make(text)
        tv.typewriter = true
        tv.foldAll()
        let target = (text as NSString).range(of: "# H60").location
        tv.setSelectedRange(NSRange(location: target, length: 0))
        tv.centerCaret()
        let lm = tv.layoutManager!
        let rect = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: target), effectiveRange: nil)
        let offset = rect.midY + tv.textContainerOrigin.y - scroll.contentView.bounds.origin.y - scroll.contentView.bounds.height / 2
        XCTAssertEqual(offset, 0, accuracy: 6)
    }

    func testFoldComputationOnABigNoteIsFast() {
        var text = ""
        var i = 0
        while text.utf8.count < 400_000 {
            text += "## Section \(i)\nSome words in a paragraph of the note.\n\n- item one\n  - nested\n- item two\n\n"
            i += 1
        }
        let (tv, _) = make(text)
        XCTAssertGreaterThan(tv.foldBlocks.count, 1000)
        within(2, "fold all on a 400 KB note") { tv.foldAll() }
        XCTAssertEqual(tv.string, text)
        within(2, "unfold all on a 400 KB note") { tv.unfoldAll() }
    }

    @MainActor func testCommandsAreListedWithFreeShortcuts() {
        let cmds = makeCommands(ws: nil, prefs: Preferences(defaults: isolatedDefaults()), recents: RecentFolders(defaults: isolatedDefaults()), newWindow: { _ in })
        let byID = Dictionary(uniqueKeysWithValues: cmds.map { ($0.id, $0) })
        XCTAssertEqual(byID["fold"]?.shortcut, "⌥⌘[")
        XCTAssertEqual(byID["unfold"]?.shortcut, "⌥⌘]")
        XCTAssertEqual(byID["fold-toggle-all"]?.shortcut, "⌥⌘\\")
        XCTAssertNotNil(byID["fold-all"]); XCTAssertNotNil(byID["unfold-all"])
        XCTAssertFalse(byID["fold"]!.enabled, "no window, nothing to fold")
        let keys = cmds.filter { $0.key != nil }.map(\.shortcut)
        XCTAssertEqual(Set(keys).count, keys.count)
    }
}
