import AppKit

/// What the editor looks like; changing any of it styles the text again.
struct EditorStyle: Equatable {
    var fontName: String
    var size: CGFloat
    var lineWidth: Int      // characters per line
}

/// The writing surface: Markdown stays in the text, quiet, and is styled as you type. Block markers
/// (`#`, `>`, `-`) hang in the left margin so the text keeps one straight edge.
final class EditorTextView: NSTextView {
    var style = EditorStyle(fontName: "IBM Plex Mono", size: 16, lineWidth: 66) { didSet { if style != oldValue { relayout() } } }
    var placeholder = "Start writing…"
    var onOpenWiki: ((String) -> Void)?
    private(set) var syntax = MarkdownSyntax.Result(spans: [], lines: [])

    static let gutter: CGFloat = 72
    static let verticalInset: CGFloat = 48

    // MARK: fonts

    var baseFont: NSFont {
        NSFont(name: style.fontName, size: style.size) ?? NSFont(name: "SFMono-Regular", size: style.size) ?? .monospacedSystemFont(ofSize: style.size, weight: .regular)
    }
    var charWidth: CGFloat { NSAttributedString(string: "0", attributes: [.font: baseFont]).size().width }

    private func paragraph(first: CGFloat, head: CGFloat) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = style.size * 0.55
        p.firstLineHeadIndent = first; p.headIndent = head
        return p
    }
    var baseAttributes: [NSAttributedString.Key: Any] {
        let g = Self.gutter
        return [.font: baseFont, .foregroundColor: Palette.text, .paragraphStyle: paragraph(first: g, head: g)]
    }

    // MARK: layout: a centred column with a gutter on its left

    private func relayout() {
        font = baseFont
        updateInsets()
        restyle()
    }

    /// The text column is centred in the pane; the gutter for hanging markers sits outside it, on its left.
    func updateInsets() {
        let width = enclosingScrollView?.contentSize.width ?? bounds.width
        let column = min(CGFloat(style.lineWidth) * charWidth, max(200, width - 2 * Self.gutter))
        let x = max(8, ((width - column) / 2 - Self.gutter).rounded())
        let inset = NSSize(width: x, height: Self.verticalInset)
        if textContainerInset != inset { textContainerInset = inset }
        let size = NSSize(width: column + Self.gutter, height: CGFloat.greatestFiniteMagnitude)
        if textContainer?.widthTracksTextView == true { textContainer?.widthTracksTextView = false }
        if textContainer?.size != size { textContainer?.size = size }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    // MARK: styling

    /// Styles all of the text again. Notes are short, and this keeps the rules in one place.
    func restyle() {
        guard let storage = textStorage, !hasMarkedText() else { return }
        syntax = MarkdownSyntax.analyze(string)
        let full = NSRange(location: 0, length: storage.length)
        let selection = selectedRange()
        let size = style.size
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)
        for span in syntax.spans {
            let r = span.range
            guard r.length > 0, NSMaxRange(r) <= storage.length else { continue }
            switch span.kind {
            case .marker:
                storage.addAttribute(.foregroundColor, value: Palette.marker, range: r)
            case .heading(let n):
                let bump: [CGFloat] = [10, 4, 2, 0, 0, 0]
                let f = baseFont.withSize(size + bump[min(n, 6) - 1])
                storage.addAttributes([.font: NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask), .foregroundColor: Palette.strongText], range: r)
            case .bold: trait(.boldFontMask, r)
            case .italic: trait(.italicFontMask, r)
            case .highlight: storage.addAttribute(.backgroundColor, value: Palette.highlight, range: r)
            case .strike: storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: Palette.done], range: r)
            case .code: storage.addAttribute(.backgroundColor, value: Palette.chip, range: r)
            case .codeBlock: storage.addAttribute(.backgroundColor, value: Palette.chip, range: r)
            case .link: storage.addAttribute(.foregroundColor, value: Palette.link, range: r)
            case .wikiLink: storage.addAttributes([.foregroundColor: Palette.link, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Palette.link.withAlphaComponent(0.35)], range: r)
            case .listMarker: storage.addAttribute(.foregroundColor, value: Palette.marker, range: r)
            case .checkbox(let on): storage.addAttribute(.foregroundColor, value: on ? Palette.green : Palette.link, range: r)
            case .done: storage.addAttributes([.foregroundColor: Palette.done, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: r)
            case .quote:
                storage.addAttributes([.foregroundColor: Palette.quoteText], range: r)
                trait(.italicFontMask, r)
            case .rule: storage.addAttribute(.foregroundColor, value: Palette.marker, range: r)
            case .tableRow:
                let ns = storage.string as NSString
                for i in r.location..<NSMaxRange(r) where ns.character(at: i) == 0x7C {
                    storage.addAttribute(.foregroundColor, value: Palette.marker, range: NSRange(location: i, length: 1))
                }
            }
        }
        // markers hang in the margin; wrapped lines line up under the text
        let g = Self.gutter
        for line in syntax.lines where NSMaxRange(line.prefix) <= storage.length {
            let lead = NSRange(location: line.prefix.location, length: line.lead)
            let leadW = line.lead > 0 ? storage.attributedSubstring(from: lead).size().width : 0
            let markerW = storage.attributedSubstring(from: line.prefix).size().width - leadW
            let p = paragraph(first: max(0, g + leadW - markerW), head: g + leadW)
            storage.addAttribute(.paragraphStyle, value: p, range: NSRange(location: line.range.location, length: line.range.length))
        }
        storage.endEditing()
        if selectedRange() != selection { setSelectedRange(selection) }
        typingAttributes = baseAttributes
        insertionPointColor = Palette.caret
    }

    private func trait(_ t: NSFontTraitMask, _ r: NSRange) {
        guard let storage = textStorage else { return }
        storage.enumerateAttribute(.font, in: r) { v, sub, _ in
            storage.addAttribute(.font, value: NSFontManager.shared.convert((v as? NSFont) ?? baseFont, toHaveTrait: t), range: sub)
        }
    }

    // MARK: placeholder

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty, let container = textContainer else { return }
        let x = textContainerOrigin.x + container.lineFragmentPadding + Self.gutter
        (placeholder as NSString).draw(at: NSPoint(x: x, y: textContainerOrigin.y), withAttributes: [.font: baseFont, .foregroundColor: Palette.marker])
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); restyle(); needsDisplay = true }

    // MARK: ticking boxes and opening links

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let idx = characterIndexForInsertion(at: point)
        let ns = string as NSString
        for span in syntax.spans {
            switch span.kind {
            case .checkbox(let on) where NSLocationInRange(idx, NSRange(location: span.range.location, length: span.range.length + 1)):
                if let lm = layoutManager, let tc = textContainer {
                    let g = lm.glyphIndexForCharacter(at: span.range.location)
                    let rect = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 3), in: tc).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
                    if rect.insetBy(dx: -3, dy: -3).contains(point) {
                        let at = NSRange(location: span.range.location + 1, length: 1)
                        guard NSMaxRange(at) <= ns.length else { break }
                        if shouldChangeText(in: at, replacementString: on ? " " : "x") {
                            replaceCharacters(in: at, with: on ? " " : "x")
                            didChangeText()
                        }
                        return
                    }
                }
            case .link(let url) where event.modifierFlags.contains(.command) && NSLocationInRange(idx, span.range):
                if let u = URL(string: url.hasPrefix("http") ? url : "https://" + url) { NSWorkspace.shared.open(u) }
                return
            case .wikiLink(let target) where event.modifierFlags.contains(.command) && NSLocationInRange(idx, span.range):
                onOpenWiki?(target)
                return
            default: break
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: keys: ⌘B bold, ⌘I italic, ⇧⌘H highlight, ⌘K link, ⌘E code

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, let c = event.charactersIgnoringModifiers?.lowercased() else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags == .command {
            switch c {
            case "b": toggleWrap("**"); return true
            case "i": toggleWrap("*"); return true
            case "e": toggleWrap("`"); return true
            case "k": insertLink(); return true
            default: break
            }
        }
        if flags == [.command, .shift], c == "h" { toggleWrap("::"); return true }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: formatting actions

    /// Puts a marker around the selection (or the word at the cursor), or takes it off if it is already there.
    func toggleWrap(_ marker: String) {
        let ns = string as NSString
        var r = selectedRange()
        let m = (marker as NSString).length
        if r.length == 0 {
            let w = ns.rangeOfWord(at: r.location)
            if w.length > 0 { r = w }
        }
        let before = r.location >= m ? ns.substring(with: NSRange(location: r.location - m, length: m)) : ""
        let after = NSMaxRange(r) + m <= ns.length ? ns.substring(with: NSRange(location: NSMaxRange(r), length: m)) : ""
        if before == marker, after == marker {
            insertText(ns.substring(with: r), replacementRange: NSRange(location: r.location - m, length: r.length + 2 * m))
            setSelectedRange(NSRange(location: r.location - m, length: r.length))
        } else {
            insertText(marker + ns.substring(with: r) + marker, replacementRange: r)
            setSelectedRange(NSRange(location: r.location + m, length: r.length))
        }
    }

    /// Puts `prefix` at the start of the line (a heading, a list, a quote), or takes it off.
    func togglePrefix(_ prefix: String) {
        let ns = string as NSString
        let para = ns.paragraphRange(for: selectedRange())
        let line = ns.substring(with: para)
        let p = (prefix as NSString).length
        if line.hasPrefix(prefix) {
            insertText("", replacementRange: NSRange(location: para.location, length: p))
        } else {
            var cut = 0
            if let m = ListMarker(line: line.trimmingCharacters(in: .newlines)), prefix.hasPrefix("- ") { cut = (m.prefix as NSString).length }
            else if line.hasPrefix("#") { cut = line.prefix { $0 == "#" }.count + 1 }
            insertText(prefix, replacementRange: NSRange(location: para.location, length: min(cut, (line as NSString).length)))
        }
    }

    func insertLink() {
        let r = selectedRange()
        let text = (string as NSString).substring(with: r)
        let label = text.isEmpty ? "text" : text
        insertText("[\(label)](https://)", replacementRange: r)
        setSelectedRange(NSRange(location: r.location + (label as NSString).length + 3, length: 8))
    }
}

extension NSString {
    func rangeOfWord(at i: Int) -> NSRange {
        let ws = CharacterSet.alphanumerics
        var lo = min(i, length), hi = min(i, length)
        while lo > 0, let u = UnicodeScalar(character(at: lo - 1)), ws.contains(u) { lo -= 1 }
        while hi < length, let u = UnicodeScalar(character(at: hi)), ws.contains(u) { hi += 1 }
        return NSRange(location: lo, length: hi - lo)
    }
}
