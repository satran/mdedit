import AppKit

/// What the editor looks like; changing any of it styles the text again.
struct EditorStyle: Equatable {
    var fontName: String
    var size: CGFloat
    var lineWidth: Int      // characters per line
    var headingSizes = true
}

/// The writing surface: Markdown stays in the text, quiet, and is styled as you type. Block markers
/// (`#`, `>`, `-`) hang in the left margin so the text keeps one straight edge.
final class EditorTextView: NSTextView {
    var style = EditorStyle(fontName: "IBM Plex Mono", size: 17, lineWidth: 72) { didSet { if style != oldValue { semiboldCache = [:]; cachedBase = nil; relayout() } } }
    var placeholder = "Start writing…"
    var onOpenWiki: ((String) -> Void)?
    var wikiResolves: (String) -> Bool = { _ in true }
    var wikiNames: () -> [String] = { [] }
    /// Where a request for the keyboard is kept; see `EditorBridge.requestFocus`.
    weak var bridge: EditorBridge?
    /// Turns files dropped on the editor into Markdown (copying them in first); empty means nothing was done.
    var dropText: (([URL]) -> String)?
    /// Keeps the line being written in the middle of the pane.
    var typewriter = false { didSet { if typewriter != oldValue { typewriterChanged() } } }
    /// Everything but the paragraph being written is dimmed.
    var focusDim = false { didSet { if focusDim != oldValue { restyle() } } }
    private(set) var isRestyling = false
    private(set) var syntax = MarkdownSyntax.Result(spans: [], lines: [])
    /// What is drawn behind the text: code blocks as one tinted band, inline code as chips.
    private var codeBlocks: [NSRange] = []
    private var inlineCode: [NSRange] = []

    static let gutter: CGFloat = 72
    static let verticalInset: CGFloat = 48

    // MARK: fonts

    private var cachedBase: NSFont?
    var baseFont: NSFont {
        if let cachedBase { return cachedBase }
        let f = Fonts.nsFont(family: style.fontName, size: style.size) ?? .monospacedSystemFont(ofSize: style.size, weight: .regular)
        cachedBase = f
        return f
    }
    var charWidth: CGFloat { NSAttributedString(string: "0", attributes: [.font: baseFont]).size().width }

    /// Body text sits on a 1.65 line (28 px at 17 px), so one blank line is exactly one line of rhythm.
    static let leading: CGFloat = 1.65

    private func paragraph(first: CGFloat, head: CGFloat) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        let f = baseFont
        p.lineSpacing = max(0, style.size * Self.leading - (f.ascender - f.descender + f.leading))
        p.firstLineHeadIndent = first; p.headIndent = head
        return p
    }
    var baseAttributes: [NSAttributedString.Key: Any] {
        let g = Self.gutter
        // ligatures off, so every character of the Markdown is visible
        return [.font: baseFont, .foregroundColor: Palette.text, .paragraphStyle: paragraph(first: g, head: g), .ligature: 0]
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
        let vertical = typewriter ? max(Self.verticalInset, ((enclosingScrollView?.contentSize.height ?? 0) / 2).rounded()) : Self.verticalInset
        let inset = NSSize(width: x, height: vertical)
        if textContainerInset != inset { textContainerInset = inset }
        let size = NSSize(width: column + Self.gutter, height: CGFloat.greatestFiniteMagnitude)
        if textContainer?.widthTracksTextView == true { textContainer?.widthTracksTextView = false }
        if textContainer?.size != size { textContainer?.size = size }
    }

    private var paneObserver: NSObjectProtocol?
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let o = paneObserver { NotificationCenter.default.removeObserver(o); paneObserver = nil }
        guard let clip = superview as? NSClipView else { return }
        clip.postsFrameChangedNotifications = true
        // The typewriter padding is half the pane's height, so it follows the pane when its height changes.
        paneObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            guard let self, self.typewriter else { return }
            self.updateInsets()
            self.fitToContent()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    /// The caret's line in the text view's own coordinates (its vertical middle).
    private func caretMidY() -> CGFloat {
        guard let lm = layoutManager, let tc = textContainer else { return 0 }
        lm.ensureLayout(for: tc)
        let loc = selectedRange().location
        var rect = NSRect.zero
        if loc >= (string as NSString).length {
            rect = lm.extraLineFragmentRect
            if rect.isEmpty, lm.numberOfGlyphs > 0 { rect = lm.lineFragmentRect(forGlyphAt: lm.numberOfGlyphs - 1, effectiveRange: nil) }
        } else {
            rect = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: loc), effectiveRange: nil)
        }
        return rect.midY + textContainerOrigin.y
    }

    /// Makes the view exactly as tall as its text and padding (and never shorter than the pane). A text view only grows
    /// by itself, so after the padding shrinks it would stay tall, and the pane could sit scrolled over empty space.
    func fitToContent() {
        guard let lm = layoutManager, let tc = textContainer else { return }
        lm.ensureLayout(for: tc)
        let pane = enclosingScrollView?.contentSize.height ?? 0
        let h = max(lm.usedRect(for: tc).maxY + 2 * textContainerInset.height, pane)
        if abs(frame.height - h) > 0.5 { setFrameSize(NSSize(width: frame.width, height: h)) }
    }

    /// Turning typewriter mode on centres the caret; turning it off keeps the caret where it was on the screen.
    /// Either way the caret ends up in view, and the pane moves no more than it has to.
    private func typewriterChanged() {
        guard let scroll = enclosingScrollView else { updateInsets(); return }
        let clip = scroll.contentView
        let before = caretMidY() - clip.bounds.origin.y           // where the caret is on the screen now
        updateInsets()
        fitToContent()
        if typewriter {
            centerCaret()
            DispatchQueue.main.async { [weak self] in if self?.typewriter == true { self?.fitToContent(); self?.centerCaret() } }
        } else {
            scrollCaret(toScreenY: before)
        }
        updateInsertionPointStateAndRestartTimer(true)
        needsDisplay = true
    }

    /// Scrolls so the caret's line is at `y` from the top of the pane if the document allows, and always in view.
    private func scrollCaret(toScreenY y: CGFloat) {
        guard let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        let caret = caretMidY()
        let maxOrigin = max(0, frame.height - clip.bounds.height)
        var origin = min(maxOrigin, max(0, caret - y))
        // a caret near the edge of the pane is brought a little way in
        let margin = min(60, clip.bounds.height / 4)
        if caret - origin < margin { origin = max(0, caret - margin) }
        if caret - origin > clip.bounds.height - margin { origin = min(maxOrigin, caret - clip.bounds.height + margin) }
        guard abs(clip.bounds.origin.y - origin) > 0.5 else { return }
        clip.scroll(to: NSPoint(x: 0, y: origin))
        scroll.reflectScrolledClipView(clip)
    }

    /// Scrolls so the caret's line is in the vertical middle of the pane.
    func centerCaret() {
        guard let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        fitToContent()
        let maxY = max(0, frame.height - clip.bounds.height)
        let y = min(maxY, max(0, caretMidY() - clip.bounds.height / 2))
        guard abs(clip.bounds.origin.y - y) > 1 else { return }
        clip.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(clip)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, bridge?.wantsFocus == true else { return }
        // once the view is in place: the window is still arranging its views at this moment
        DispatchQueue.main.async { [weak self] in if let self { self.bridge?.fulfil(self) } }
    }

    // MARK: Shift-Return

    /// Shift-Return arrives at a text view as a plain Return (`insertNewline:`), so the list code could not tell the two apart.
    /// In a list item it continues the same item, indented under its text; elsewhere it behaves as Return.
    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if (event.keyCode == 36 || event.keyCode == 76), flags.contains(.shift), !flags.contains(.command), !hasMarkedText(),
           let coordinator = delegate as? MarkdownTextEditor.Coordinator, coordinator.softBreak(self) { return }
        super.keyDown(with: event)
    }

    // MARK: styling

    /// Styles all of the text again. Notes are short, and this keeps the rules in one place.
    func restyle() {
        guard let storage = textStorage, !hasMarkedText() else { return }
        isRestyling = true; defer { isRestyling = false }
        syntax = MarkdownSyntax.analyze(string)
        let full = NSRange(location: 0, length: storage.length)
        let selection = selectedRange()
        let size = style.size
        codeBlocks = []; inlineCode = []
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)
        for span in syntax.spans {
            let r = span.range
            guard r.length > 0, NSMaxRange(r) <= storage.length else { continue }
            switch span.kind {
            case .marker:
                storage.addAttribute(.foregroundColor, value: Palette.marker, range: r)
            case .heading(let n):
                let bump: [CGFloat] = style.headingSizes ? [10, 4, 2, 0, 0, 0] : [0, 0, 0, 0, 0, 0]
                let f = baseFont.withSize(size + bump[min(n, 6) - 1])
                storage.addAttributes([.font: semibold(f), .foregroundColor: Palette.strongText], range: r)
            case .bold:
                semibold(in: r)
                storage.addAttribute(.foregroundColor, value: Palette.strongText, range: r)
            case .italic: trait(.italicFontMask, r)
            case .highlight: storage.addAttribute(.backgroundColor, value: Palette.highlight, range: r)
            case .strike: storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: Palette.done], range: r)
            case .code:
                storage.addAttribute(.foregroundColor, value: Palette.codeInk, range: r)
                inlineCode.append(r)
            case .codeBlock:
                let line = (storage.string as NSString).substring(with: r).trimmingCharacters(in: .whitespaces)
                let fence = line.hasPrefix("```") || line.hasPrefix("~~~")
                storage.addAttribute(.foregroundColor, value: fence ? Palette.marker : Palette.codeInk, range: r)
                // one band per block: lines that follow each other join it
                if let last = codeBlocks.last, NSMaxRange(last) + 1 == r.location { codeBlocks[codeBlocks.count - 1] = NSUnionRange(last, r) } else { codeBlocks.append(r) }
            case .link: storage.addAttribute(.foregroundColor, value: Palette.linkText, range: r)
            case .wikiLink(let target):
                // a note that exists reads as a link; one that does not is faint and dashed, and a click offers to make it
                if wikiResolves(target) {
                    storage.addAttributes([.foregroundColor: Palette.linkText, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Palette.linkText.withAlphaComponent(0.35)], range: r)
                } else {
                    storage.addAttributes([.foregroundColor: Palette.unresolved, .underlineStyle: NSUnderlineStyle.patternDash.union(.single).rawValue, .underlineColor: Palette.unresolved], range: r)
                }
            case .listMarker: storage.addAttribute(.foregroundColor, value: Palette.marker, range: r)
            case .checkbox(let on): storage.addAttribute(.foregroundColor, value: on ? Palette.green : Palette.link, range: r)
            case .done: storage.addAttributes([.foregroundColor: Palette.done, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: r)
            case .quote:
                storage.addAttributes([.foregroundColor: Palette.quoteText], range: r)
                trait(.italicFontMask, r)
            case .rule: storage.addAttribute(.foregroundColor, value: Palette.marker, range: r)
            case .frontMatter:
                // the fences are faint, the key is a step lighter than its value
                let ns = storage.string as NSString
                let line = ns.substring(with: r)
                if line.trimmingCharacters(in: .whitespaces) == "---" { storage.addAttribute(.foregroundColor, value: Palette.fmFence, range: r) }
                else {
                    storage.addAttribute(.foregroundColor, value: Palette.fmValue, range: r)
                    let colon = (line as NSString).range(of: ":")
                    if colon.location != NSNotFound, !line.hasPrefix(" "), !line.hasPrefix("-") {
                        storage.addAttribute(.foregroundColor, value: Palette.fmKey, range: NSRange(location: r.location, length: colon.location + 1))
                    }
                }
            case .tableRow:
                // the separator row is all markup; the header row above it is semibold; pipes are always faint
                let ns = storage.string as NSString
                let line = ns.substring(with: r)
                if Self.isTableSeparator(line) { storage.addAttribute(.foregroundColor, value: Palette.marker, range: r); break }
                let next = NSMaxRange(r) + 1 < ns.length ? ns.paragraphRange(for: NSRange(location: NSMaxRange(r) + 1, length: 0)) : NSRange(location: 0, length: 0)
                if next.length > 0, Self.isTableSeparator(ns.substring(with: next).trimmingCharacters(in: .newlines)) {
                    semibold(in: r)
                    storage.addAttribute(.foregroundColor, value: Palette.strongText, range: r)
                }
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
            // only the bullet or number hangs in the margin; a task's box starts where a plain item's text would
            let boxW = line.box > 0 && line.box <= line.prefix.length
                ? storage.attributedSubstring(from: NSRange(location: NSMaxRange(line.prefix) - line.box, length: line.box)).size().width : 0
            let markerW = storage.attributedSubstring(from: line.prefix).size().width - leadW - boxW
            let p = paragraph(first: max(0, g + leadW - markerW), head: g + leadW + boxW)
            storage.addAttribute(.paragraphStyle, value: p, range: NSRange(location: line.range.location, length: line.range.length))
        }
        if focusDim {
            let ns = storage.string as NSString
            let here = ns.paragraphRange(for: selection)
            if here.location > 0 { storage.addAttribute(.foregroundColor, value: Palette.focusDim, range: NSRange(location: 0, length: here.location)) }
            if NSMaxRange(here) < ns.length { storage.addAttribute(.foregroundColor, value: Palette.focusDim, range: NSRange(location: NSMaxRange(here), length: ns.length - NSMaxRange(here))) }
        }
        storage.endEditing()
        if selectedRange() != selection { setSelectedRange(selection) }
        typingAttributes = baseAttributes
        insertionPointColor = Palette.caret
        selectedTextAttributes = [.backgroundColor: Palette.selectionText]
        needsDisplay = true
    }

    static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.contains("-") && t.allSatisfy { "|:- \t".contains($0) } && t.contains("|")
    }

    /// Weight 600 of the same family, keeping italic: IBM Plex Mono has a SemiBold, and the type specs use it for bold and headings.
    private var semiboldCache: [String: NSFont] = [:]

    private func semibold(_ f: NSFont) -> NSFont {
        let italic = f.fontDescriptor.symbolicTraits.contains(.italic)
        // looking a font up is slow and a note repeats the same few, so they are kept
        let key = "\(f.fontName)|\(f.pointSize)|\(italic)"
        if let hit = semiboldCache[key] { return hit }
        let made = makeSemibold(f, italic: italic)
        semiboldCache[key] = made
        return made
    }

    private func makeSemibold(_ f: NSFont, italic: Bool) -> NSFont {
        var traits: [NSFontDescriptor.TraitKey: Any] = [.weight: NSFont.Weight.semibold.rawValue]
        if italic { traits[.symbolic] = NSFontDescriptor.SymbolicTraits.italic.rawValue }
        let d = NSFontDescriptor(fontAttributes: [.family: f.familyName ?? style.fontName, .traits: traits])
        return NSFont(descriptor: d, size: f.pointSize) ?? NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask)
    }

    private func semibold(in r: NSRange) {
        guard let storage = textStorage else { return }
        storage.enumerateAttribute(.font, in: r) { v, sub, _ in
            storage.addAttribute(.font, value: semibold((v as? NSFont) ?? baseFont), range: sub)
        }
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

    // MARK: behind the text, and the caret

    /// Code blocks are one tinted band that reaches 2 ch past the text on each side; inline code is a small rounded chip.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer, !codeBlocks.isEmpty || !inlineCode.isEmpty else { return }
        let origin = textContainerOrigin, ch = charWidth
        let columnLeft = origin.x + Self.gutter, columnWidth = max(0, tc.size.width - Self.gutter)
        Palette.codeBand.setFill()
        for r in codeBlocks where NSMaxRange(r) <= (string as NSString).length {
            let g = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            var union = NSRect.null
            lm.enumerateLineFragments(forGlyphRange: g) { frag, _, _, _, _ in union = union.union(frag) }
            guard !union.isNull else { continue }
            let band = NSRect(x: columnLeft - 2 * ch, y: union.minY + origin.y - 6, width: columnWidth + 4 * ch, height: union.height + 12)
            if band.intersects(rect) { NSBezierPath(roundedRect: band, xRadius: 8, yRadius: 8).fill() }
        }
        Palette.inlineCode.setFill()
        let natural = baseFont.ascender - baseFont.descender
        for r in inlineCode where NSMaxRange(r) <= (string as NSString).length {
            let g = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            // one chip per line the code sits on, as wide as its own glyphs there. (The "enclosing rects" TextKit offers run from
            // the container's left edge on wrapped lines, which painted the chip across the margin and the list's hanging indent.)
            lm.enumerateLineFragments(forGlyphRange: g) { _, _, _, fragmentGlyphs, _ in
                let part = NSIntersectionRange(g, fragmentGlyphs)
                guard part.length > 0 else { return }
                let box = lm.boundingRect(forGlyphRange: part, in: tc)
                let chip = NSRect(x: box.minX + origin.x - 2, y: box.minY + origin.y, width: box.width + 4, height: natural)
                if chip.intersects(rect) { NSBezierPath(roundedRect: chip, xRadius: 3, yRadius: 3).fill() }
            }
        }
    }

    /// A 2 px caret, as in the type specs.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var r = rect
        r.size.width = 2
        super.drawInsertionPoint(in: r, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        super.setNeedsDisplay(rect.insetBy(dx: -2, dy: 0), avoidAdditionalLayout: flag)
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
                // only web addresses and mail open from the editor; anything else is just text
                let scheme = LinkPolicy.scheme(of: url)
                let text = scheme == nil && url.lowercased().hasPrefix("www.") ? "https://" + url : url
                if let scheme = LinkPolicy.scheme(of: text), LinkPolicy.webSchemes.contains(scheme), let u = URL(string: text) { NSWorkspace.shared.open(u) }
                return
            case .wikiLink(let target) where event.modifierFlags.contains(.command) && NSLocationInRange(idx, span.range):
                onOpenWiki?(target)
                return
            default: break
            }
        }
        super.mouseDown(with: event)
    }


    // MARK: [[ completion

    /// The text between an open "[[" and the caret, when the caret is inside one.
    private var openWikiRange: NSRange? {
        let ns = string as NSString
        let caret = selectedRange().location
        guard selectedRange().length == 0, caret >= 2 else { return nil }
        let line = ns.lineRange(for: NSRange(location: caret, length: 0))
        let before = ns.substring(with: NSRange(location: line.location, length: caret - line.location))
        guard let open = before.range(of: "[[", options: .backwards) else { return nil }
        let typed = before[open.upperBound...]
        guard !typed.contains("]"), !typed.contains("["), !typed.contains("|") else { return nil }
        return NSRange(location: caret - (typed as Substring).utf16.count, length: (typed as Substring).utf16.count)
    }

    override var rangeForUserCompletion: NSRange { openWikiRange ?? super.rangeForUserCompletion }

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        guard openWikiRange != nil else { return super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index) }
        let typed = (string as NSString).substring(with: charRange).lowercased()
        index.pointee = 0
        let all = wikiNames()
        let starts = all.filter { $0.lowercased().hasPrefix(typed) }
        let contains = all.filter { !$0.lowercased().hasPrefix(typed) && $0.lowercased().contains(typed) }
        return Array((starts + contains).prefix(12))
    }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        guard openWikiRange != nil || flag else { return super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag) }
        // choosing a note closes the link; Esc leaves what was typed
        let chosen = movement == NSCancelTextMovement ? nil : word
        guard flag, let chosen else { return super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag) }
        let ns = string as NSString
        let after = NSMaxRange(charRange) + 2 <= ns.length ? ns.substring(with: NSRange(location: NSMaxRange(charRange), length: 2)) : ""
        super.insertCompletion(after == "]]" ? chosen : chosen + "]]", forPartialWordRange: charRange, movement: movement, isFinal: flag)
    }

    /// Called after typing: a second "[" opens the list of notes.
    func offerNotesIfTypingLink() {
        guard let r = openWikiRange, r.length == 0 else { return }
        DispatchQueue.main.async { [weak self] in self?.complete(nil) }
    }

    // MARK: dropped files

    private func droppedFiles(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropText != nil && !droppedFiles(sender).isEmpty ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropText != nil && !droppedFiles(sender).isEmpty ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = droppedFiles(sender)
        guard let dropText, !files.isEmpty else { return super.performDragOperation(sender) }
        var text = dropText(files)
        guard !text.isEmpty else { return false }
        let at = min(characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil)), (string as NSString).length)
        // a picture is a paragraph of its own
        if text.hasPrefix("![") {
            let ns = string as NSString
            if at > 0, ns.character(at: at - 1) != 10 { text = "\n\n" + text }
            if at < ns.length, ns.character(at: at) != 10 { text += "\n\n" }
        }
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: at, length: 0))
        insertText(text, replacementRange: NSRange(location: at, length: 0))
        return true
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
