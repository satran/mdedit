import AppKit

/// Everything the editor knows about folding. Kept in one object so `EditorTextView` itself gains a single property.
///
/// How folds are tracked: a fold is the character offset of its header line. Every text edit moves the offsets of
/// folds after it (`adjust`), and after each restyle the blocks are found again from the text (`Folding.blocks`);
/// a fold whose header is no longer a foldable block (the heading was edited away, the section emptied) is dropped.
/// The hidden ranges are always derived from the current text, so they cannot go stale.
final class FoldState {
    var blocks: [FoldBlock] = []
    /// Header offsets of the folded blocks.
    var folded = Set<Int>()
    /// Merged ranges whose glyphs are not drawn.
    var hidden: [NSRange] = []
    /// Merged whole-paragraph ranges that get a zero-height paragraph style.
    var bodies: [NSRange] = []
    /// Merged ranges where a caret would sit on hidden text.
    var locks: [NSRange] = []
    var lockAtEnd = false
    /// The text changed and the ranges above describe the old text until the next restyle.
    var stale = false
    var textLength = 0
    /// Header offset of the line under the pointer.
    var hover: Int?
    var tracking: NSTrackingArea?
    var observer: NSObjectProtocol?
    var revealing = false

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    var active: [FoldBlock] { blocks.filter { folded.contains($0.header.location) } }

    func isLocked(_ position: Int) -> Bool {
        (lockAtEnd && position == textLength) || Folding.contains(position, in: locks)
    }

    /// Moves the folds after an edit that replaced `oldLength` characters at `at` with `newLength`.
    func adjust(at: Int, oldLength: Int, newLength: Int, insertedHasBreak: Bool, replacedAll: Bool) {
        if replacedAll { folded.removeAll(); return }
        let end = at + oldLength, delta = newLength - oldLength
        var out = Set<Int>()
        for h in folded {
            if h < at { out.insert(h) }
            else if h >= end {
                if oldLength == 0 && h == at { out.insert(insertedHasBreak ? h + delta : h) }   // typing at the start of the header line
                else { out.insert(h + delta) }
            } else if h == at { out.insert(h) }                      // the start of the line was replaced; kept only if it is still a heading
            // otherwise the header was inside the replaced text: gone
        }
        folded = out
    }
}

extension EditorTextView: NSLayoutManagerDelegate {

    // MARK: state

    var hasFolds: Bool { !fold.folded.isEmpty }
    var foldBlocks: [FoldBlock] { fold.blocks }
    /// Header offsets of the folded blocks that exist right now.
    var foldedHeaders: [Int] { fold.blocks.filter { fold.folded.contains($0.header.location) }.map(\.header.location) }
    /// The character ranges that are hidden at the moment.
    var hiddenRanges: [NSRange] { fold.hidden }

    func isFolded(_ block: FoldBlock) -> Bool { fold.folded.contains(block.header.location) }

    /// Forgets every fold (a different note was opened).
    func clearFolds() {
        guard !fold.folded.isEmpty else { return }
        fold.folded.removeAll()
        restyle()
    }

    /// Called at the end of `restyle()`: finds the blocks again, drops folds that no longer exist, and hides what is folded.
    func applyFolding() {
        guard let storage = textStorage, let lm = layoutManager else { return }
        if lm.delegate !== self { lm.delegate = self }
        installFoldObserver(storage)
        fold.blocks = Folding.blocks(in: string)
        fold.textLength = storage.length
        if !fold.folded.isEmpty {
            let headers = Set(fold.blocks.map(\.header.location))
            fold.folded.formIntersection(headers)
        }
        let active = fold.active
        let oldHidden = fold.hidden
        fold.hidden = Folding.merged(active.map(\.hidden))
        fold.bodies = Folding.merged(active.map(\.body))
        fold.locks = Folding.merged(active.map(\.lock))
        fold.lockAtEnd = active.contains(where: \.lockIncludesEnd)
        if let h = fold.hover, !fold.blocks.contains(where: { $0.header.location == h }) { fold.hover = nil }

        if !fold.bodies.isEmpty {
            let flat = NSMutableParagraphStyle()
            flat.minimumLineHeight = 0.01; flat.maximumLineHeight = 0.01
            flat.lineSpacing = 0; flat.paragraphSpacing = 0; flat.paragraphSpacingBefore = 0
            storage.beginEditing()
            for r in fold.bodies where NSMaxRange(r) <= storage.length { storage.addAttribute(.paragraphStyle, value: flat, range: r) }
            storage.endEditing()
        }
        let afterEdit = fold.stale
        fold.stale = false
        let changed = Set(oldHidden).symmetricDifference(Set(fold.hidden))
        for r in changed where NSMaxRange(r) <= storage.length {
            lm.invalidateGlyphs(forCharacterRange: r, changeInLength: 0, actualCharacterRange: nil)
            lm.invalidateLayout(forCharacterRange: r, actualCharacterRange: nil)
        }
        // an edit can leave the caret on text that is now hidden: show it rather than type out of sight
        if afterEdit, !fold.folded.isEmpty, !fold.revealing, rangeIsLocked(selectedRange()) {
            fold.revealing = true; defer { fold.revealing = false }
            let sel = selectedRange()
            fold.folded.subtract(fold.active.filter { NSLocationInRange(sel.location, $0.lock) || NSLocationInRange(NSMaxRange(sel), $0.lock) || ($0.lockIncludesEnd && sel.length == 0 && sel.location == $0.textLength) }.map(\.header.location))
            restyle()
        }
    }

    private func installFoldObserver(_ storage: NSTextStorage) {
        guard fold.observer == nil else { return }
        let state = fold
        fold.observer = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { note in
            guard let s = note.object as? NSTextStorage, s.editedMask.contains(.editedCharacters), !state.folded.isEmpty else { return }
            let edited = s.editedRange, delta = s.changeInLength
            let oldLength = edited.length - delta
            let oldTotal = s.length - delta
            let all = edited.location == 0 && oldLength == oldTotal && oldLength > 0
            var hasBreak = false
            if oldLength == 0, edited.length > 0, edited.length < 100_000 {
                let ns = s.string as NSString
                hasBreak = ns.rangeOfCharacter(from: .newlines, options: [], range: edited).location != NSNotFound
            }
            state.stale = true
            state.adjust(at: edited.location, oldLength: oldLength, newLength: edited.length, insertedHasBreak: hasBreak, replacedAll: all)
        }
    }

    // MARK: folding and unfolding

    func setFolded(_ headers: Set<Int>, _ on: Bool) {
        guard !headers.isEmpty else { return }
        if on { fold.folded.formUnion(headers) } else { fold.folded.subtract(headers) }
        restyle()
        moveCaretOutOfFolds()
    }

    func toggleFold(headerAt location: Int) {
        guard fold.blocks.contains(where: { $0.header.location == location }) else { return }
        setFolded([location], !fold.folded.contains(location))
    }

    /// ⌥⌘[: folds the innermost block around the caret that is not folded yet (on a folded heading, its parent).
    @discardableResult
    func foldAtCaret() -> Bool {
        let blocks = fold.blocks
        for i in Folding.blocks(containing: selectedRange().location, in: blocks) where !fold.folded.contains(blocks[i].header.location) {
            setFolded([blocks[i].header.location], true)
            return true
        }
        return false
    }

    /// ⌥⌘]: unfolds the block whose header holds the caret, or else the innermost folded block around it.
    @discardableResult
    func unfoldAtCaret() -> Bool {
        let blocks = fold.blocks
        let around = Folding.blocks(containing: selectedRange().location, in: blocks).filter { fold.folded.contains(blocks[$0].header.location) }
        guard let i = around.first else { return false }
        setFolded([blocks[i].header.location], false)
        return true
    }

    func foldAll() { setFolded(Set(fold.blocks.filter { $0.level != nil }.map(\.header.location)), true) }

    func unfoldAll() {
        guard hasFolds else { return }
        fold.folded.removeAll()
        restyle()
    }

    /// ⌥⌘\: folds every heading, or unfolds everything when all headings are already folded.
    func toggleFoldAll() {
        let headings = fold.blocks.filter { $0.level != nil }
        if !headings.isEmpty, headings.allSatisfy({ fold.folded.contains($0.header.location) }) || (headings.isEmpty && hasFolds) { unfoldAll() }
        else { foldAll() }
    }

    /// After folding, a caret or selection edge that fell on hidden text moves to the end of the heading that now holds it.
    private func moveCaretOutOfFolds() {
        let sel = selectedRange()
        guard rangeIsLocked(sel) else { return }
        let hit = fold.active.first { $0.lock.length > 0 && (NSLocationInRange(sel.location, $0.lock) || NSLocationInRange(NSMaxRange(sel), $0.lock) || (sel.length == 0 && $0.lockIncludesEnd && sel.location == $0.textLength)) }
        if let hit { setSelectedRange(NSRange(location: NSMaxRange(hit.header), length: 0)) }
    }

    // MARK: the caret never rests on hidden text

    /// A caret is locked at any hidden position. A range is locked when one of its ends lands inside hidden text;
    /// a range that merely covers a fold (Select All) is fine, so copying it takes the hidden text along.
    fileprivate func rangeIsLocked(_ r: NSRange) -> Bool {
        guard !fold.folded.isEmpty else { return false }
        if r.length == 0 { return fold.isLocked(r.location) }
        return Folding.contains(r.location, in: fold.locks) || Folding.contains(NSMaxRange(r), in: fold.locks)
    }

    /// Moving the selection onto hidden text (find, the outline, the arrow key at the end of a heading) unfolds what hides it.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        if !isRestyling, !fold.stale, !fold.folded.isEmpty, ranges.contains(where: { rangeIsLocked($0.rangeValue) }) {
            let hit = fold.active.filter { b in
                ranges.contains { v in
                    let r = v.rangeValue
                    if r.length == 0 { return NSLocationInRange(r.location, b.lock) || (b.lockIncludesEnd && r.location == b.textLength) }
                    return NSLocationInRange(r.location, b.lock) || NSLocationInRange(NSMaxRange(r), b.lock)
                }
            }
            fold.folded.subtract(hit.map(\.header.location))
            restyle()
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
    }

    /// An edit that touches hidden text unfolds it first, so nothing is changed out of sight. Typing at the end of a
    /// folded heading's own line is not such an edit, a line break there is.
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if !fold.folded.isEmpty {
            let a = affectedCharRange.location, b = NSMaxRange(affectedCharRange)
            let breaks = replacementString?.rangeOfCharacter(from: .newlines) != nil
            let hit = fold.active.filter { blk in
                let h = blk.hidden
                if affectedCharRange.length > 0 { return b > NSMaxRange(blk.header) && a < NSMaxRange(h) }
                if a == NSMaxRange(blk.header) { return breaks }
                return NSLocationInRange(a, blk.lock) || (blk.lockIncludesEnd && a == blk.textLength)
            }
            if !hit.isEmpty {
                fold.folded.subtract(hit.map(\.header.location))
                restyle()
            }
        }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    // MARK: hiding glyphs

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>, font aFont: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        let hidden = fold.hidden
        let n = glyphRange.length
        guard !hidden.isEmpty, n > 0 else { return 0 }
        var touches = false
        for i in 0..<n where Folding.contains(charIndexes[i], in: hidden) { touches = true; break }
        guard touches else { return 0 }
        var out = [NSLayoutManager.GlyphProperty](repeating: [], count: n)
        for i in 0..<n { out[i] = Folding.contains(charIndexes[i], in: hidden) ? .null : props[i] }
        layoutManager.setGlyphs(glyphs, properties: out, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return n
    }

    // MARK: the chevron and the ellipsis

    private var chevronX: CGFloat {
        let o = textContainerOrigin.x
        return o >= 22 ? o - 15 : o + 1
    }

    /// Where the chevron of a block sits, and (for a folded block) the ellipsis after its header. nil when not laid out or hidden.
    private func foldGeometry(_ b: FoldBlock) -> (chevron: NSRect, ellipsis: NSRect?, ellipsisOrigin: NSPoint)? {
        guard let lm = layoutManager, !Folding.contains(b.header.location, in: fold.hidden) else { return nil }
        let origin = textContainerOrigin
        let first = lm.glyphIndexForCharacter(at: b.header.location)
        guard first < lm.numberOfGlyphs else { return nil }
        let used = lm.lineFragmentUsedRect(forGlyphAt: first, effectiveRange: nil)
        let chevron = NSRect(x: chevronX - 3, y: used.midY + origin.y - 8, width: 16, height: 16)
        guard isFolded(b) else { return (chevron, nil, .zero) }
        let g = lm.glyphRange(forCharacterRange: b.header, actualCharacterRange: nil)
        let last = max(first, NSMaxRange(g) - 1)
        let frag = lm.lineFragmentRect(forGlyphAt: last, effectiveRange: nil)
        let lastUsed = lm.lineFragmentUsedRect(forGlyphAt: last, effectiveRange: nil)
        let font = baseFont
        let x = lastUsed.maxX + origin.x + 6
        let y = frag.minY + origin.y + lm.location(forGlyphAt: last).y - font.ascender
        return (chevron, NSRect(x: x - 4, y: frag.minY + origin.y, width: 30, height: frag.height), NSPoint(x: x, y: y))
    }

    func drawFoldIndicators(_ dirty: NSRect) {
        guard !fold.blocks.isEmpty, let lm = layoutManager, let tc = textContainer else { return }
        let origin = textContainerOrigin
        let probe = NSRect(x: 0, y: dirty.minY - origin.y - 40, width: tc.size.width, height: dirty.height + 80)
        let g = lm.glyphRange(forBoundingRect: probe, in: tc)
        guard g.length > 0 else { return }
        let chars = lm.characterRange(forGlyphRange: g, actualGlyphRange: nil)
        var i = Folding.firstBlock(atOrAfter: chars.location, in: fold.blocks)
        while i < fold.blocks.count, fold.blocks[i].header.location < NSMaxRange(chars) {
            let b = fold.blocks[i]; i += 1
            guard let geo = foldGeometry(b) else { continue }
            let folded = isFolded(b), hot = fold.hover == b.header.location
            let alpha: CGFloat = hot ? 0.95 : folded ? 0.7 : 0.3
            let r = geo.chevron.insetBy(dx: 4, dy: 4)                  // an 8 pt box
            let path = NSBezierPath()
            if folded {
                path.move(to: NSPoint(x: r.minX + 2, y: r.minY)); path.line(to: NSPoint(x: r.minX + 6, y: r.midY)); path.line(to: NSPoint(x: r.minX + 2, y: r.maxY))
            } else {
                path.move(to: NSPoint(x: r.minX, y: r.minY + 2)); path.line(to: NSPoint(x: r.midX, y: r.minY + 6)); path.line(to: NSPoint(x: r.maxX, y: r.minY + 2))
            }
            path.lineWidth = 1.4; path.lineCapStyle = .round; path.lineJoinStyle = .round
            Palette.marker.withAlphaComponent(alpha).setStroke()
            path.stroke()
            if folded {
                ("…" as NSString).draw(at: geo.ellipsisOrigin, withAttributes: [.font: baseFont, .foregroundColor: Palette.marker.withAlphaComponent(hot ? 0.95 : 0.7)])
            }
        }
    }

    /// The block whose header line holds the character at `index`.
    private func foldBlock(atCharacter index: Int) -> FoldBlock? {
        guard !fold.blocks.isEmpty else { return nil }
        let ns = string as NSString
        let para = ns.paragraphRange(for: NSRange(location: min(max(0, index), ns.length), length: 0))
        guard let i = Folding.block(startingAt: para.location, in: fold.blocks) else { return nil }
        return fold.blocks[i]
    }

    /// A click on a chevron (or on the ellipsis of a folded line) folds or unfolds it.
    func foldMouseDown(_ event: NSEvent) -> Bool {
        guard !fold.blocks.isEmpty, event.clickCount == 1 else { return false }
        let point = convert(event.locationInWindow, from: nil)
        guard let b = foldBlock(atCharacter: characterIndexForInsertion(at: point)), let geo = foldGeometry(b) else { return false }
        let onChevron = geo.chevron.insetBy(dx: -2, dy: -2).contains(point)
        let onEllipsis = geo.ellipsis?.contains(point) ?? false
        guard onChevron || onEllipsis else { return false }
        toggleFold(headerAt: b.header.location)
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = fold.tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        fold.tracking = t
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard !fold.blocks.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        setHover(foldBlock(atCharacter: characterIndexForInsertion(at: point))?.header.location)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHover(nil)
    }

    private func setHover(_ header: Int?) {
        guard header != fold.hover else { return }
        let old = fold.hover
        fold.hover = header
        for h in [old, header].compactMap({ $0 }) {
            if let i = Folding.block(startingAt: h, in: fold.blocks), let geo = foldGeometry(fold.blocks[i]) {
                setNeedsDisplay(geo.chevron.union(geo.ellipsis ?? .zero).insetBy(dx: -4, dy: -4))
            }
        }
    }
}
