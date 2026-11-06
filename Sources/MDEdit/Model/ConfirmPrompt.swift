import AppKit

/// A plain question with one action button and Cancel. True when the person pressed the action button.
enum ConfirmPrompt {
    /// `scrollingText` is shown in a read-only, scrolling text view under the message (a template, a long address).
    /// With `cancelIsDefault` the Return key means Cancel, so a careless press does nothing.
    static func makeAlert(_ title: String, _ detail: String, _ button: String, scrollingText: String? = nil, textSize: NSSize = NSSize(width: 480, height: 220), cancelIsDefault: Bool = false) -> NSAlert {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = detail
        a.addButton(withTitle: button)
        a.addButton(withTitle: "Cancel")
        if cancelIsDefault {
            a.buttons[0].keyEquivalent = ""
            a.buttons[1].keyEquivalent = "\r"
        }
        if let text = scrollingText {
            let scroll = NSScrollView(frame: NSRect(origin: .zero, size: textSize))
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            let tv = NSTextView(frame: scroll.contentView.bounds)
            tv.isEditable = false
            tv.isSelectable = true
            tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            tv.string = text
            tv.autoresizingMask = [.width]
            tv.isVerticallyResizable = true
            tv.textContainer?.widthTracksTextView = true
            scroll.documentView = tv
            a.accessoryView = scroll
        }
        return a
    }

    static func ask(_ title: String, _ detail: String, _ button: String, scrollingText: String? = nil, textSize: NSSize = NSSize(width: 480, height: 220), cancelIsDefault: Bool = false) -> Bool {
        makeAlert(title, detail, button, scrollingText: scrollingText, textSize: textSize, cancelIsDefault: cancelIsDefault).runModal() == .alertFirstButtonReturn
    }
}
