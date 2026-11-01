import Foundation

/// A piece of the note that can be folded: a heading with everything under it, or a list item with its nested
/// items and continuation lines. Pure data; the editor decides what to hide from it.
struct FoldBlock: Equatable {
    enum Kind: Equatable { case heading(Int), listItem }
    var kind: Kind
    /// The line that stays visible, without its line break (a list item includes its indentation).
    var header: NSRange
    /// Whole lines that fold away: from the start of the line after the header through the last line of the block,
    /// including that line's break. Trailing blank lines are not part of it, so folded sections keep their spacing.
    var body: NSRange
    /// The block runs to the end of a note that does not end with a line break.
    var unterminated: Bool
    var textLength: Int

    /// What is hidden. Normally the body. When the note ends without a line break the header's own break goes too,
    /// so no empty last line is left behind.
    var hidden: NSRange {
        unterminated ? NSRange(location: NSMaxRange(header), length: NSMaxRange(body) - NSMaxRange(header)) : body
    }
    /// Caret positions that fall on hidden text: just after the header's first line-break character up to the end
    /// of the hidden text (exclusive). The end of the header line itself and the start of the next visible line are fine.
    var lock: NSRange {
        let s = NSMaxRange(header) + 1
        return NSRange(location: s, length: max(0, NSMaxRange(body) - s))
    }
    /// The hidden text reaches the end of the note, so the position after the last character is hidden too.
    var lockIncludesEnd: Bool { NSMaxRange(body) == textLength }
    var level: Int? { if case .heading(let n) = kind { return n }; return nil }
    var fullRange: NSRange { NSRange(location: header.location, length: NSMaxRange(body) - header.location) }
}

/// Finds what can be folded in a note. One linear pass, no recursion, so hostile notes (100,000 headings,
/// thousands of nested list levels, one huge line) cost no more than their size.
///
/// * Headings (`# ` to `###### ` at the start of a line) hide everything up to the next heading of the same or a
///   higher level. Headings in fenced code and the front matter are not headings. A heading with nothing under it
///   (or only blank lines) is not foldable.
/// * A list item (`-`, `*`, `+`, `•`, `1.`, `1)`, with or without a task box) hides the lines after it that are
///   indented more than its marker: nested items, continuation lines, and blank lines between them. A tab counts as
///   four columns of indentation.
/// * Line breaks are `\n`, `\r\n`, `\r` and U+2029, the same paragraphs the text view uses.
enum Folding {
    static func blocks(in text: String) -> [FoldBlock] {
        let u = Array(text.utf16)
        let n = u.count
        guard n > 0 else { return [] }
        let frontMatterEnd = FrontMatter.parse(text)?.end ?? 0

        struct Open { var slot: Int; var indent: Int; var level: Int; var header: NSRange; var bodyStart: Int }
        var slots: [FoldBlock?] = []
        var headings: [Open] = [], items: [Open] = []
        var lastEnd = 0, lastTerminated = true         // the end of the last non-blank line seen
        var fence: UInt16?

        func emit(_ o: Open, _ kind: FoldBlock.Kind) {
            guard lastEnd > o.bodyStart else { return }
            slots[o.slot] = FoldBlock(kind: kind, header: o.header, body: NSRange(location: o.bodyStart, length: lastEnd - o.bodyStart),
                                      unterminated: lastEnd == n && !lastTerminated, textLength: n)
        }
        @inline(__always) func isBreak(_ c: UInt16) -> Bool { c == 10 || c == 13 || c == 0x2029 }
        @inline(__always) func isBlankChar(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == 0xA0 }
        @inline(__always) func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }

        var pos = 0
        while pos < n {
            let start = pos
            var e = start
            while e < n, !isBreak(u[e]) { e += 1 }
            var next = e
            if e < n { next = e + ((u[e] == 13 && e + 1 < n && u[e + 1] == 10) ? 2 : 1) }
            pos = next
            if start < frontMatterEnd { continue }

            var f = start, cols = 0
            while f < e, isBlankChar(u[f]) { cols += u[f] == 9 ? 4 - cols % 4 : 1; f += 1 }
            if f == e { continue }                       // blank

            if let fc = fence {                          // inside a code fence: content, never a heading or an item
                if e - f >= 3, u[f] == fc, u[f + 1] == fc, u[f + 2] == fc { fence = nil }
                lastEnd = next; lastTerminated = next > e
                continue
            }

            var headingLevel = 0
            var isItem = false
            if cols == 0, u[f] == 35 {
                var k = 0
                while f + k < e, u[f + k] == 35, k <= 6 { k += 1 }
                if k <= 6, f + k < e, u[f + k] == 32 { headingLevel = k }
            }
            if headingLevel == 0 {
                let c = u[f]
                if c == 45 || c == 42 || c == 43 || c == 0x2022 {
                    if f + 1 < e, u[f + 1] == 32 || u[f + 1] == 9 { isItem = true }
                    if isItem, c == 45 || c == 42 {      // "- - -" and "* * *" are rules
                        var marks = 0, others = false
                        var i = f
                        while i < e { if u[i] == c { marks += 1 } else if !isBlankChar(u[i]) { others = true; break }; i += 1 }
                        if !others, marks >= 3 { isItem = false }
                    }
                } else if isDigit(c) {
                    var d = 0
                    while f + d < e, d < 5, isDigit(u[f + d]) { d += 1 }
                    if d <= 4, f + d + 1 < e, u[f + d] == 46 || u[f + d] == 41, u[f + d + 1] == 32 || u[f + d + 1] == 9 { isItem = true }
                }
            }

            if headingLevel > 0 {
                while let t = headings.last, t.level >= headingLevel { emit(t, .heading(t.level)); headings.removeLast() }
                while let t = items.popLast() { emit(t, .listItem) }
                headings.append(Open(slot: slots.count, indent: 0, level: headingLevel, header: NSRange(location: start, length: e - start), bodyStart: next))
                slots.append(nil)
            } else {
                while let t = items.last, t.indent >= cols { emit(t, .listItem); items.removeLast() }
                if isItem {
                    items.append(Open(slot: slots.count, indent: cols, level: 0, header: NSRange(location: start, length: e - start), bodyStart: next))
                    slots.append(nil)
                }
                if e - f >= 3, u[f] == 96 || u[f] == 126, u[f + 1] == u[f], u[f + 2] == u[f] { fence = u[f] }
            }
            lastEnd = next; lastTerminated = next > e
        }
        while let t = items.popLast() { emit(t, .listItem) }
        while let t = headings.popLast() { emit(t, .heading(t.level)) }
        return slots.compactMap { $0 }
    }

    /// Index of the first block whose header starts at or after `location` (blocks are in document order).
    static func firstBlock(atOrAfter location: Int, in blocks: [FoldBlock]) -> Int {
        var lo = 0, hi = blocks.count
        while lo < hi { let mid = (lo + hi) / 2; if blocks[mid].header.location < location { lo = mid + 1 } else { hi = mid } }
        return lo
    }

    /// The index of the block whose header line starts at `location`.
    static func block(startingAt location: Int, in blocks: [FoldBlock]) -> Int? {
        let i = firstBlock(atOrAfter: location, in: blocks)
        return i < blocks.count && blocks[i].header.location == location ? i : nil
    }

    /// The blocks that contain `position` (in the header line or the body), innermost first.
    static func blocks(containing position: Int, in blocks: [FoldBlock]) -> [Int] {
        var out: [Int] = []
        var i = firstBlock(atOrAfter: position + 1, in: blocks) - 1
        while i >= 0 {
            let b = blocks[i]
            if position <= NSMaxRange(b.header) || position < NSMaxRange(b.body) { out.append(i) }
            i -= 1
        }
        return out
    }

    /// Sorted, overlapping or touching ranges joined.
    static func merged(_ ranges: [NSRange]) -> [NSRange] {
        var out: [NSRange] = []
        for r in ranges.sorted(by: { $0.location < $1.location }) where r.length > 0 {
            if let last = out.last, r.location <= NSMaxRange(last) {
                out[out.count - 1].length = max(NSMaxRange(last), NSMaxRange(r)) - last.location
            } else { out.append(r) }
        }
        return out
    }

    /// Whether `index` lies in one of the merged ranges.
    static func contains(_ index: Int, in ranges: [NSRange]) -> Bool {
        var lo = 0, hi = ranges.count
        while lo < hi { let mid = (lo + hi) / 2; if NSMaxRange(ranges[mid]) <= index { lo = mid + 1 } else { hi = mid } }
        return lo < ranges.count && ranges[lo].location <= index
    }
}
