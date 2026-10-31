import Foundation

/// One Markdown formatting command: the Format menu, the shortcuts and the command palette all use this list.
enum FormatAction: Hashable {
    case bold, italic, code, strike, highlight, link
    case heading(Int), body
    case bullet, numbered, task, quote
    case codeBlock, rule

    static let all: [FormatAction] = [.bold, .italic, .code, .strike, .highlight, .link,
                                      .heading(1), .heading(2), .heading(3), .heading(4), .heading(5), .heading(6), .body,
                                      .bullet, .numbered, .task, .quote, .codeBlock, .rule]
}

/// What a formatting command does to the text: replace `range` by `replacement`, then select `selection`
/// (in the coordinates of the text after the replacement). All offsets are UTF-16, like NSString and NSTextView.
struct FormatEdit: Equatable {
    var range: NSRange
    var replacement: String
    var selection: NSRange

    /// The text after the edit (for tests).
    func applied(to text: String) -> String { (text as NSString).replacingCharacters(in: range, with: replacement) }
}

/// The pure part of the Format menu: text and selection in, one replacement out. No view, no state.
enum MarkdownFormatting {
    static func edit(_ action: FormatAction, in text: String, selection: NSRange) -> FormatEdit? {
        edit(action, in: text as NSString, selection: selection)
    }

    static func edit(_ action: FormatAction, in ns: NSString, selection: NSRange) -> FormatEdit? {
        let loc = min(max(0, selection.location), ns.length)
        let sel = NSRange(location: loc, length: min(max(0, selection.length), ns.length - loc))
        switch action {
        case .bold: return inline("**", ns, sel)
        case .italic: return inline("*", ns, sel)
        case .code: return inline("`", ns, sel)
        case .strike: return inline("~~", ns, sel)
        case .highlight: return inline("::", ns, sel)
        case .link: return link(ns, sel)
        case .heading(let n): return lines(.heading(min(6, max(1, n))), ns, sel)
        case .body: return lines(.body, ns, sel)
        case .bullet: return lines(.bullet, ns, sel)
        case .numbered: return lines(.numbered, ns, sel)
        case .task: return lines(.task, ns, sel)
        case .quote: return lines(.quote, ns, sel)
        case .codeBlock: return codeBlock(ns, sel)
        case .rule: return rule(ns, sel)
        }
    }

    // MARK: small helpers

    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }
    private static func isNewline(_ c: unichar) -> Bool { c == 0x0A || c == 0x0D }
    private static func isWhite(_ c: unichar) -> Bool { isSpace(c) || isNewline(c) }

    /// `r` without leading and trailing blanks and line breaks.
    private static func trimmed(_ ns: NSString, _ r: NSRange) -> NSRange {
        var lo = r.location, hi = NSMaxRange(r)
        while lo < hi, isWhite(ns.character(at: lo)) { lo += 1 }
        while hi > lo, isWhite(ns.character(at: hi - 1)) { hi -= 1 }
        return NSRange(location: lo, length: hi - lo)
    }

    /// End of a line's text, before its line break.
    private static func contentEnd(_ ns: NSString, _ line: NSRange) -> Int {
        var e = NSMaxRange(line)
        while e > line.location, isNewline(ns.character(at: e - 1)) { e -= 1 }
        return e
    }

    private static func word(_ ns: NSString, at i: Int) -> NSRange {
        let ok = CharacterSet.alphanumerics
        func isWord(_ c: unichar) -> Bool { UnicodeScalar(c).map { ok.contains($0) } ?? false }
        var lo = i, hi = i
        while lo > 0, isWord(ns.character(at: lo - 1)) { lo -= 1 }
        while hi < ns.length, isWord(ns.character(at: hi)) { hi += 1 }
        return NSRange(location: lo, length: hi - lo)
    }

    // MARK: inline marks

    /// Number of "*" in a row from `from` going forward (up to `limit`), at most 3.
    private static func starsForward(_ ns: NSString, _ from: Int, _ limit: Int) -> Int {
        var n = 0
        while n < 3, from + n < limit, ns.character(at: from + n) == 0x2A { n += 1 }
        return n
    }
    /// The same, going backward from `from` down to `limit`.
    private static func starsBackward(_ ns: NSString, _ from: Int, _ limit: Int) -> Int {
        var n = 0
        while n < 3, from - n - 1 >= limit, ns.character(at: from - n - 1) == 0x2A { n += 1 }
        return n
    }

    /// Where the marker pair around (or just inside) `seg` is, if there is one: the marker on the left and on the right.
    /// Handles "*" next to "**": bold needs two stars on both sides, italic an odd number (so "***x***" is both).
    private static func markers(_ marker: String, _ ns: NSString, _ seg: NSRange) -> (left: NSRange, right: NSRange)? {
        let n = marker.utf16.count, end = NSMaxRange(seg)
        if marker.hasPrefix("*") {
            func ok(_ m: Int) -> Bool { n == 2 ? m >= 2 : m % 2 == 1 }
            let la = starsForward(ns, seg.location, end), lb = starsBackward(ns, end, seg.location)
            if la + lb < seg.length, ok(min(la, lb)) { return (NSRange(location: seg.location, length: n), NSRange(location: end - n, length: n)) }
            let a = starsBackward(ns, seg.location, 0), b = starsForward(ns, end, ns.length)
            if ok(min(a, b)) { return (NSRange(location: seg.location - n, length: n), NSRange(location: end, length: n)) }
            return nil
        }
        if seg.length >= 2 * n + 1,
           ns.substring(with: NSRange(location: seg.location, length: n)) == marker,
           ns.substring(with: NSRange(location: end - n, length: n)) == marker {
            return (NSRange(location: seg.location, length: n), NSRange(location: end - n, length: n))
        }
        if seg.location >= n, end + n <= ns.length,
           ns.substring(with: NSRange(location: seg.location - n, length: n)) == marker,
           ns.substring(with: NSRange(location: end, length: n)) == marker {
            return (NSRange(location: seg.location - n, length: n), NSRange(location: end, length: n))
        }
        return nil
    }

    private static func inline(_ marker: String, _ ns: NSString, _ sel: NSRange) -> FormatEdit? {
        let n = marker.utf16.count
        func pair(at i: Int) -> FormatEdit {
            FormatEdit(range: NSRange(location: i, length: 0), replacement: marker + marker, selection: NSRange(location: i + n, length: 0))
        }
        if sel.length == 0 {
            let w = word(ns, at: sel.location)
            let seg = w.length > 0 ? w : sel
            if w.length == 0, markers(marker, ns, seg) == nil { return pair(at: sel.location) }
            guard var e = toggle(marker, ns, [seg]) else { return nil }
            // a caret stays where it was in the word
            e.selection = NSRange(location: e.selection.location + (w.length > 0 ? sel.location - w.location : 0), length: 0)
            return e
        }
        // one piece per line, without the blanks around it
        var segs: [NSRange] = []
        var pos = sel.location
        let end = NSMaxRange(sel)
        while pos < end {
            let line = ns.lineRange(for: NSRange(location: pos, length: 0))
            let s = max(line.location, sel.location), e = min(contentEnd(ns, line), end)
            if e > s { let t = trimmed(ns, NSRange(location: s, length: e - s)); if t.length > 0 { segs.append(t) } }
            pos = max(NSMaxRange(line), pos + 1)
        }
        if segs.isEmpty { return pair(at: end) }
        return toggle(marker, ns, segs)
    }

    /// Wraps every piece, or unwraps them all when each one is already wrapped.
    private static func toggle(_ marker: String, _ ns: NSString, _ segs: [NSRange]) -> FormatEdit? {
        guard !segs.isEmpty else { return nil }
        let n = marker.utf16.count
        let found = segs.map { markers(marker, ns, $0) }
        let unwrap = found.allSatisfy { $0 != nil }
        struct Piece { var region: NSRange; var text: String; var offset: Int; var length: Int }
        var pieces: [Piece] = []
        for (seg, f) in zip(segs, found) {
            if unwrap, let f {
                let region = NSRange(location: f.left.location, length: NSMaxRange(f.right) - f.left.location)
                let inner = NSRange(location: NSMaxRange(f.left), length: f.right.location - NSMaxRange(f.left))
                pieces.append(Piece(region: region, text: ns.substring(with: inner), offset: 0, length: inner.length))
            } else if f != nil {
                pieces.append(Piece(region: seg, text: ns.substring(with: seg), offset: 0, length: seg.length))
            } else {
                pieces.append(Piece(region: seg, text: marker + ns.substring(with: seg) + marker, offset: n, length: seg.length))
            }
        }
        let start = pieces[0].region.location
        var out = "", selStart = 0, selEnd = 0
        var outLen = 0
        for (i, p) in pieces.enumerated() {
            if i > 0 {
                let prevEnd = NSMaxRange(pieces[i - 1].region)
                let gap = ns.substring(with: NSRange(location: prevEnd, length: p.region.location - prevEnd))
                out += gap; outLen += (gap as NSString).length
            }
            if i == 0 { selStart = outLen + p.offset }
            selEnd = outLen + p.offset + p.length
            out += p.text; outLen += (p.text as NSString).length
        }
        let last = pieces[pieces.count - 1].region
        // several lines: select all of it (markers included), so the same key takes the marks off again
        let selection = pieces.count > 1 ? NSRange(location: start, length: outLen) : NSRange(location: start + selStart, length: selEnd - selStart)
        return FormatEdit(range: NSRange(location: start, length: NSMaxRange(last) - start), replacement: out, selection: selection)
    }

    // MARK: link

    private static func looksLikeURL(_ ns: NSString, _ r: NSRange) -> Bool {
        if ns.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "[]()")), options: [], range: r).location != NSNotFound { return false }
        let s = ns.substring(with: NSRange(location: r.location, length: min(r.length, 12))).lowercased()
        if s.hasPrefix("www.") || s.hasPrefix("mailto:") { return true }
        return ns.range(of: "://", options: [], range: r).location != NSNotFound
    }

    private static func link(_ ns: NSString, _ sel0: NSRange) -> FormatEdit? {
        var sel = sel0
        if sel.length > 0 {
            sel = trimmed(ns, sel)
            if sel.length == 0 { sel = NSRange(location: NSMaxRange(sel0), length: 0) }
        }
        if sel.length == 0 {
            return FormatEdit(range: sel, replacement: "[](url)", selection: NSRange(location: sel.location + 1, length: 0))
        }
        let text = ns.substring(with: sel)
        if looksLikeURL(ns, sel) {
            return FormatEdit(range: sel, replacement: "[](\(text))", selection: NSRange(location: sel.location + 1, length: 0))
        }
        return FormatEdit(range: sel, replacement: "[\(text)](url)", selection: NSRange(location: sel.location + 1 + sel.length + 2, length: 3))
    }

    // MARK: line formats

    private enum Kind: Equatable { case none, heading(Int), bullet, task, numbered, quote }

    private struct Parsed {
        var indent: Int       // spaces and tabs at the start
        var marker: Int       // length of the prefix after the indent (the marker and the spaces after it)
        var kind: Kind
        var blank: Bool
    }

    private static func parse(_ ns: NSString, _ r: NSRange) -> Parsed {
        let end = NSMaxRange(r)
        var i = r.location
        while i < end, isSpace(ns.character(at: i)) { i += 1 }
        let indent = i - r.location
        if i >= end { return Parsed(indent: indent, marker: 0, kind: .none, blank: true) }
        func p(_ kind: Kind, _ markerEnd: Int) -> Parsed { Parsed(indent: indent, marker: markerEnd - i, kind: kind, blank: false) }
        func skipSpaces(_ j: Int) -> Int { var j = j; while j < end, isSpace(ns.character(at: j)) { j += 1 }; return j }
        let c = ns.character(at: i)
        if c == 0x23 {
            var h = 0
            while i + h < end, h <= 6, ns.character(at: i + h) == 0x23 { h += 1 }
            if h <= 6, i + h == end || isSpace(ns.character(at: i + h)) { return p(.heading(h), skipSpaces(i + h)) }
            return p(.none, i)
        }
        if c == 0x3E { return p(.quote, i + 1 < end && isSpace(ns.character(at: i + 1)) ? i + 2 : i + 1) }
        if c == 0x2D || c == 0x2A || c == 0x2B || c == 0x2022, i + 1 < end, isSpace(ns.character(at: i + 1)) {
            let j = i + 2
            if j + 2 < end, ns.character(at: j) == 0x5B, " xX".utf16.contains(ns.character(at: j + 1)), ns.character(at: j + 2) == 0x5D,
               j + 3 == end || isSpace(ns.character(at: j + 3)) {
                return p(.task, j + 3 == end ? j + 3 : j + 4)
            }
            return p(.bullet, j)
        }
        if c >= 0x30, c <= 0x39 {
            var d = 0
            while i + d < end, d <= 9, ns.character(at: i + d) >= 0x30, ns.character(at: i + d) <= 0x39 { d += 1 }
            if d <= 9, i + d < end, ns.character(at: i + d) == 0x2E || ns.character(at: i + d) == 0x29,
               i + d + 1 == end || isSpace(ns.character(at: i + d + 1)) {
                return p(.numbered, i + d + 1 == end ? end : i + d + 2)
            }
        }
        return p(.none, i)
    }

    private enum Target: Equatable { case heading(Int), body, bullet, numbered, task, quote }

    /// The lines touched by a selection, whole, with their line breaks.
    private static func block(_ ns: NSString, _ sel: NSRange) -> NSRange {
        let first = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        guard sel.length > 0 else { return first }
        let last = ns.lineRange(for: NSRange(location: NSMaxRange(sel) - 1, length: 0))
        return NSRange(location: first.location, length: max(first.length, NSMaxRange(last) - first.location))
    }

    private static func lineList(_ ns: NSString, _ block: NSRange) -> [NSRange] {
        var out: [NSRange] = []
        var pos = block.location
        repeat {
            let l = ns.lineRange(for: NSRange(location: pos, length: 0))
            out.append(l)
            if l.length == 0 { break }
            pos = NSMaxRange(l)
        } while pos < NSMaxRange(block)
        return out
    }

    private static func lines(_ target: Target, _ ns: NSString, _ sel: NSRange) -> FormatEdit? {
        let blk = block(ns, sel)
        let ranges = lineList(ns, blk)
        let infos = ranges.map { r -> (full: NSRange, text: NSRange, p: Parsed) in
            let t = NSRange(location: r.location, length: contentEnd(ns, r) - r.location)
            return (r, t, parse(ns, t))
        }
        // blank lines are skipped, unless the one line is all there is
        let todo = Set(infos.indices.filter { ranges.count == 1 || !infos[$0].p.blank })
        guard !todo.isEmpty else { return nil }
        func matches(_ k: Kind) -> Bool {
            switch (target, k) {
            case (.heading(let a), .heading(let b)): return a == b
            case (.bullet, .bullet), (.numbered, .numbered), (.task, .task), (.quote, .quote): return true
            default: return false
            }
        }
        let off = target != .body && todo.allSatisfy { matches(infos[$0].p.kind) }

        var out = "", outLen = 0
        var counters: [Int: Int] = [:]
        var caret: Int?
        for (i, l) in infos.enumerated() {
            let prefixStart = l.text.location + l.p.indent
            let indent = ns.substring(with: NSRange(location: l.text.location, length: l.p.indent))
            let restStart = prefixStart + l.p.marker
            let rest = ns.substring(with: NSRange(location: restStart, length: NSMaxRange(l.text) - restStart))
            var newIndent = indent, prefix = "", keep = false
            if !todo.contains(i) {
                keep = true
            } else if target == .body {
                if case .heading = l.p.kind { prefix = "" } else { keep = true }
            } else if off {
                prefix = ""
            } else if matches(l.p.kind), target != .numbered {
                keep = true
            } else {
                switch target {
                case .heading(let n): newIndent = ""; prefix = String(repeating: "#", count: n) + " "
                case .bullet: prefix = "- "
                case .task: prefix = "- [ ] "
                case .quote: prefix = "> "
                case .numbered:
                    for k in counters.keys where k > l.p.indent { counters[k] = nil }
                    counters[l.p.indent, default: 0] += 1
                    prefix = "\(counters[l.p.indent]!). "
                case .body: break
                }
            }
            let line = keep ? ns.substring(with: l.text) : newIndent + prefix + rest
            if sel.length == 0, caret == nil {
                let lineStart = blk.location + outLen
                if keep { caret = lineStart + (sel.location - l.text.location) }
                else {
                    let newContent = lineStart + (newIndent as NSString).length + (prefix as NSString).length
                    let oldContent = restStart
                    caret = sel.location >= oldContent ? newContent + (sel.location - oldContent) : newContent
                }
            }
            let term = ns.substring(with: NSRange(location: NSMaxRange(l.text), length: NSMaxRange(l.full) - NSMaxRange(l.text)))
            out += line + term
            outLen += (line as NSString).length + (term as NSString).length
        }
        if out == ns.substring(with: blk) { return nil }
        let lastTerm = infos.last.map { NSMaxRange($0.full) - NSMaxRange($0.text) } ?? 0
        let selection = sel.length == 0
            ? NSRange(location: caret ?? blk.location, length: 0)
            : NSRange(location: blk.location, length: max(0, outLen - lastTerm))
        return FormatEdit(range: blk, replacement: out, selection: selection)
    }

    // MARK: code block

    private static func fence(_ ns: NSString, _ text: NSRange) -> (char: unichar, count: Int, info: Bool)? {
        var i = text.location
        let end = NSMaxRange(text)
        while i < end, i - text.location < 3, ns.character(at: i) == 0x20 { i += 1 }
        guard i < end else { return nil }
        let c = ns.character(at: i)
        guard c == 0x60 || c == 0x7E else { return nil }
        var n = 0
        while i + n < end, ns.character(at: i + n) == c { n += 1 }
        guard n >= 3 else { return nil }
        let rest = trimmed(ns, NSRange(location: i + n, length: end - i - n))
        if c == 0x60, ns.rangeOfCharacter(from: CharacterSet(charactersIn: "`"), options: [], range: rest).location != NSNotFound { return nil }
        return (c, n, rest.length > 0)
    }

    private static func codeBlock(_ ns: NSString, _ sel: NSRange) -> FormatEdit? {
        let blk = block(ns, sel)
        // inside a fenced block already? Walk the fences from the top.
        var open: (full: NSRange, c: unichar, n: Int)?
        var pos = 0
        let stop = max(NSMaxRange(blk), blk.location + 1)
        while pos < ns.length {
            let l = ns.lineRange(for: NSRange(location: pos, length: 0))
            if l.length == 0 { break }
            let t = NSRange(location: l.location, length: contentEnd(ns, l) - l.location)
            if let f = fence(ns, t) {
                if let o = open {
                    if f.char == o.c, f.count >= o.n, !f.info {
                        if o.full.location < stop, NSMaxRange(l) > blk.location { return unfence(ns, sel, open: o.full, close: l) }
                        open = nil
                    }
                } else {
                    if l.location >= stop { break }
                    open = (l, f.char, f.count)
                }
            }
            pos = NSMaxRange(l)
        }
        let blockText = ns.substring(with: blk)
        let hasTerm = blk.length > 0 && isNewline(ns.character(at: NSMaxRange(blk) - 1))
        if sel.length == 0, trimmed(ns, blk).length == 0 {
            return FormatEdit(range: blk, replacement: "```\n\n```" + (hasTerm ? "\n" : ""), selection: NSRange(location: blk.location + 4, length: 0))
        }
        let inner = hasTerm ? blockText : blockText + "\n"
        let selection = sel.length == 0
            ? NSRange(location: sel.location + 4, length: 0)
            : NSRange(location: blk.location + 4, length: blk.length - (hasTerm ? (blockText.hasSuffix("\r\n") ? 2 : 1) : 0))
        return FormatEdit(range: blk, replacement: "```\n" + inner + "```" + (hasTerm ? "\n" : ""), selection: selection)
    }

    private static func unfence(_ ns: NSString, _ sel: NSRange, open o: NSRange, close c: NSRange) -> FormatEdit {
        var inner = ns.substring(with: NSRange(location: NSMaxRange(o), length: c.location - NSMaxRange(o)))
        let closeHasTerm = isNewline(ns.character(at: NSMaxRange(c) - 1))
        if !closeHasTerm, inner.hasSuffix("\n") { inner.removeLast() }
        let innerLen = (inner as NSString).length
        let whole = NSRange(location: o.location, length: NSMaxRange(c) - o.location)
        let selection = sel.length == 0
            ? NSRange(location: min(max(sel.location - o.length, o.location), o.location + innerLen), length: 0)
            : NSRange(location: o.location, length: max(0, innerLen - (inner.hasSuffix("\n") ? 1 : 0)))
        return FormatEdit(range: whole, replacement: inner, selection: selection)
    }

    // MARK: horizontal rule

    /// A "---" on a line of its own after the lines at the caret, with a blank line before it (or on the blank line itself).
    private static func rule(_ ns: NSString, _ sel: NSRange) -> FormatEdit? {
        let blk = block(ns, sel)
        let hasTerm = blk.length > 0 && isNewline(ns.character(at: NSMaxRange(blk) - 1))
        if sel.length == 0, trimmed(ns, blk).length == 0 {
            // right under a line of text "---" would make that line a heading
            var lead = ""
            if blk.location > 0, trimmed(ns, ns.lineRange(for: NSRange(location: blk.location - 1, length: 0))).length > 0 { lead = "\n" }
            return FormatEdit(range: blk, replacement: lead + "---\n", selection: NSRange(location: blk.location + lead.utf16.count + 4, length: 0))
        }
        let text = (hasTerm ? "" : "\n") + "\n---\n"
        let at = NSMaxRange(blk)
        return FormatEdit(range: NSRange(location: at, length: 0), replacement: text, selection: NSRange(location: at + (text as NSString).length, length: 0))
    }
}
