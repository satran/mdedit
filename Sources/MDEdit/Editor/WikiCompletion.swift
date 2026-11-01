import AppKit

/// The list of notes that appears under the caret while a `[[` link is being typed.
///
/// It is our own small panel rather than AppKit's completion popup: that one ends as soon as a space or punctuation is typed, does not
/// filter live, and re-inserted a suggestion on every Backspace so the `[[` could not be deleted. This one filters as you type, is
/// updated by deleting too, and only ever *opens* when a second `[` is typed.
///
/// Keys while it is open: ↑ ↓ choose, Return or Tab take the note, Esc closes it. Everything else goes to the text as usual.
final class WikiCompletion: NSObject {
    weak var textView: EditorTextView?
    private(set) var items: [String] = []
    private(set) var selected = 0
    private var panel: Panel?
    private var rows: [RowView] = []
    /// The `[[` the person closed with Esc: it does not reopen for the same link.
    private var dismissedOpenAt: Int?
    private static let maxItems = 12, rowHeight: CGFloat = 26

    var isOpen: Bool { panel?.isVisible == true }

    /// Notes whose names start with what was typed come first, then those that contain it; case does not matter.
    static func matches(typed: String, in names: [String], limit: Int = maxItems) -> [String] {
        // a space inside or at the end of what was typed counts ("goal " finds "Goal Setting"); only leading space is ignored
        let t = String(typed.drop { $0 == " " || $0 == "\t" }).lowercased()
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty else { return Array(names.prefix(limit)) }
        let starts = names.filter { $0.lowercased().hasPrefix(t) }
        let contains = names.filter { !$0.lowercased().hasPrefix(t) && $0.lowercased().contains(t) }
        return Array((starts + contains).prefix(limit))
    }

    // MARK: following the text

    /// Called after every change of the text or the caret. `justTypedBracket` is true when the edit was typing a `[`.
    func update(justTypedBracket: Bool) {
        guard let tv = textView, let typed = tv.openWikiRange else { close(); return }
        let openAt = typed.location - 2
        if !isOpen {
            // it opens when the second "[" is typed, not when a link is edited or deleted into
            guard justTypedBracket, typed.length == 0, dismissedOpenAt != openAt else { return }
        } else if dismissedOpenAt == openAt { return }
        let text = (tv.string as NSString).substring(with: typed)
        items = Self.matches(typed: text, in: tv.wikiNames())
        guard !items.isEmpty else { close(keepDismissal: true); return }
        selected = min(selected, items.count - 1)
        if !isOpen { selected = 0; dismissedOpenAt = nil }
        show()
    }

    func close(keepDismissal: Bool = false) {
        if let p = panel, p.isVisible { p.parent?.removeChildWindow(p); p.orderOut(nil) }
        items = []; selected = 0
        if !keepDismissal { dismissedOpenAt = nil }
    }

    // MARK: keys

    /// Handles the keys that belong to the list while it is open; returns true when it used the key.
    func handle(_ selector: Selector) -> Bool {
        guard isOpen else { return false }
        switch selector {
        case #selector(NSResponder.moveDown(_:)): move(1); return true
        case #selector(NSResponder.moveUp(_:)): move(-1); return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertLineBreak(_:)):
            accept(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            if let tv = textView, let r = tv.openWikiRange { dismissedOpenAt = r.location - 2 }
            close(keepDismissal: true); return true
        default: return false
        }
    }

    private func move(_ d: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + d + items.count) % items.count
        refreshHighlight()
    }

    /// Replaces what was typed with the chosen note and closes the link (`]]` is added unless it is already there).
    func accept(_ index: Int? = nil) {
        guard let tv = textView, let typed = tv.openWikiRange else { close(); return }
        let i = index ?? selected
        guard items.indices.contains(i) else { close(); return }
        let name = items[i]
        let ns = tv.string as NSString
        let end = NSMaxRange(typed)
        let hasClose = end + 2 <= ns.length && ns.substring(with: NSRange(location: end, length: 2)) == "]]"
        close()
        tv.insertText(hasClose ? name : name + "]]", replacementRange: typed)
        if hasClose { tv.setSelectedRange(NSRange(location: typed.location + (name as NSString).length + 2, length: 0)) }
    }

    // MARK: drawing

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class RowView: NSView {
        let label = NSTextField(labelWithString: "")
        var onClick: (() -> Void)?
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true; layer?.cornerRadius = 6
            label.font = .systemFont(ofSize: 13); label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                                         label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                                         label.centerYAnchor.constraint(equalTo: centerYAnchor)])
        }
        required init?(coder: NSCoder) { return nil }   // built in code only
        override func mouseDown(with event: NSEvent) { onClick?() }
        override var acceptsFirstResponder: Bool { false }
    }

    private func show() {
        guard let tv = textView, let window = tv.window else { return }
        let width: CGFloat = 300, height = CGFloat(items.count) * Self.rowHeight + 8
        let p = panel ?? {
            let p = Panel(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            p.isReleasedWhenClosed = false
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.hidesOnDeactivate = true
            panel = p
            return p
        }()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.wantsLayer = true
        content.layer?.cornerRadius = 10; content.layer?.borderWidth = 1
        content.layer?.backgroundColor = Palette.binderBg.cgColor
        content.layer?.borderColor = Palette.binderBorder.cgColor
        rows = items.enumerated().map { i, name in
            let r = RowView(frame: NSRect(x: 4, y: height - 4 - CGFloat(i + 1) * Self.rowHeight, width: width - 8, height: Self.rowHeight))
            r.label.stringValue = name
            r.label.textColor = Palette.binderText
            r.onClick = { [weak self] in self?.accept(i) }
            content.addSubview(r)
            return r
        }
        p.contentView = content
        p.setContentSize(NSSize(width: width, height: height))
        p.setFrameOrigin(Self.origin(forPanelOf: NSSize(width: width, height: height), under: caretRect(in: tv), on: window.screen))
        if p.parent !== window { window.addChildWindow(p, ordered: .above) }
        p.orderFront(nil)
        refreshHighlight()
    }

    /// The line the caret is on, in screen coordinates: the character just before the caret (the `[` that was typed, or the last
    /// letter), because an empty range gives a zero-width rect that cannot be told from "no answer".
    private func caretRect(in tv: EditorTextView) -> NSRect {
        let loc = tv.selectedRange().location
        let ask = NSRange(location: max(0, loc - 1), length: loc > 0 ? 1 : 0)
        let r = tv.firstRect(forCharacterRange: ask, actualRange: nil)
        var screenRect = NSRect(x: r.maxX, y: r.minY, width: 0, height: r.height)
        if r.height <= 0 || r == .zero, let lm = tv.layoutManager, let tc = tv.textContainer, loc > 0 {
            // ask the layout instead: where the previous character ends, converted view -> window -> screen
            let g = NSRange(location: lm.glyphIndexForCharacter(at: loc - 1), length: 1)
            let box = lm.boundingRect(forGlyphRange: g, in: tc).offsetBy(dx: tv.textContainerOrigin.x, dy: tv.textContainerOrigin.y)
            let inWindow = tv.convert(box, to: nil)
            let onScreen = tv.window?.convertToScreen(inWindow) ?? inWindow
            screenRect = NSRect(x: onScreen.maxX, y: onScreen.minY, width: 0, height: onScreen.height)
        }
        return screenRect
    }

    /// Below the line the caret is on, a little to the left of it; above the line when there is no room below, and always on screen.
    static func origin(forPanelOf size: NSSize, under caret: NSRect, on screen: NSScreen?) -> NSPoint {
        var x = caret.maxX - 14, y = caret.minY - size.height - 4
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            if y < visible.minY { y = caret.maxY + 4 }                          // no room below: above the line
            x = min(max(visible.minX + 4, x), visible.maxX - size.width - 4)
            y = min(max(visible.minY + 4, y), visible.maxY - size.height - 4)
        }
        return NSPoint(x: x, y: y)
    }

    /// For tests: where the list is on screen.
    var panelFrame: NSRect? { isOpen ? panel?.frame : nil }

    private func refreshHighlight() {
        for (i, r) in rows.enumerated() {
            r.layer?.backgroundColor = (i == selected ? Palette.selection : .clear).cgColor
        }
    }

    deinit { if let p = panel { p.parent?.removeChildWindow(p); p.orderOut(nil) } }
}
