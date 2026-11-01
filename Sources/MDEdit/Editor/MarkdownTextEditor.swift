import SwiftUI
import AppKit

/// The text component: a scrolling editor that takes the room it is given.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var documentID: URL?
    var style: EditorStyle
    var onOpenWiki: ((String) -> Void)?
    var wikiResolves: (String) -> Bool = { _ in true }
    var wikiNames: () -> [String] = { [] }
    /// Changes when the notes do, so link styling is redone.
    var linksVersion = 0
    var typewriter = false
    var focusDim = false
    var bridge: EditorBridge?
    /// Return true when Esc was used up (leaving focus mode).
    var onEscape: (() -> Bool)?
    /// Files dropped on the text become links; see `EditorTextView.dropText`.
    var dropText: (([URL]) -> String)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = EditorTextView()
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        // The system's own spelling and autocorrect. Smart quotes and dashes stay off: they would break code and "---".
        tv.isContinuousSpellCheckingEnabled = true
        tv.isAutomaticSpellingCorrectionEnabled = true
        tv.isAutomaticTextReplacementEnabled = true
        tv.smartInsertDeleteEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.onOpenWiki = onOpenWiki
        tv.wikiResolves = wikiResolves; tv.wikiNames = wikiNames
        tv.typewriter = typewriter; tv.focusDim = focusDim
        tv.dropText = dropText
        bridge?.textView = tv

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = tv
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        tv.style = style
        tv.font = tv.baseFont
        tv.string = text
        tv.updateInsets()
        tv.restyle()
        context.coordinator.documentID = documentID
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? EditorTextView else { return }
        tv.onOpenWiki = onOpenWiki
        tv.wikiResolves = wikiResolves; tv.wikiNames = wikiNames
        tv.typewriter = typewriter; tv.focusDim = focusDim
        tv.dropText = dropText
        bridge?.textView = tv
        if context.coordinator.linksVersion != linksVersion { context.coordinator.linksVersion = linksVersion; tv.restyle() }
        tv.style = style                                    // restyles itself when it changed
        let switched = context.coordinator.documentID != documentID
        if switched { tv.fold.folded.removeAll() }           // folds belong to one note
        if tv.string != text || switched {
            tv.string = text
            tv.restyle()
            tv.needsDisplay = true
        }
        if switched {
            context.coordinator.documentID = documentID
            tv.undoManager?.removeAllActions()
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            tv.scrollToBeginningOfDocument(nil)
            if documentID != nil, bridge?.keepFocusElsewhere != true { DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) } }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        var documentID: URL?
        var linksVersion = 0
        init(_ p: MarkdownTextEditor) { parent = p }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? EditorTextView else { return }
            tv.restyle()
            parent.text = tv.string
            tv.needsDisplay = true
            tv.offerNotesIfTypingLink()
        }

        func textViewDidChangeSelection(_ n: Notification) {
            guard let tv = n.object as? EditorTextView, !tv.isRestyling else { return }
            if tv.focusDim { tv.restyle() }
            if tv.typewriter { DispatchQueue.main.async { tv.centerCaret() } }
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.cancelOperation(_:)):
                if parent.onEscape?() == true { return true }
                tv.window?.makeFirstResponder(nil); return true
            case #selector(NSResponder.insertNewline(_:)): return continueList(tv)
            case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                return softBreak(tv)
            case #selector(NSResponder.insertTab(_:)): return shift(tv, by: 2)
            case #selector(NSResponder.insertBacktab(_:)): return shift(tv, by: -2)
            case #selector(NSResponder.deleteBackward(_:)): return deleteMarker(tv)
            default: return false
            }
        }

        func currentLine(_ tv: NSTextView) -> (para: NSRange, line: String, caret: Int) {
            let ns = tv.string as NSString
            let caret = tv.selectedRange().location
            let para = ns.paragraphRange(for: NSRange(location: caret, length: 0))
            return (para, ns.substring(with: para).trimmingCharacters(in: .newlines), caret)
        }

        /// Return in a list item starts the next one; Return on an empty item ends the list.
        func continueList(_ tv: NSTextView) -> Bool {
            guard tv.selectedRange().length == 0 else { return false }
            let (para, line, caret) = currentLine(tv)
            var prefix: String?, next: String?
            if let m = ListMarker(line: line) { prefix = m.prefix; next = m.next }
            else if line.hasPrefix("> ") { prefix = "> "; next = "> " }
            guard let prefix, let next, caret >= para.location + (prefix as NSString).length else { return false }
            if line.trimmingCharacters(in: .whitespaces) == prefix.trimmingCharacters(in: .whitespaces) {
                tv.insertText("", replacementRange: NSRange(location: para.location, length: (line as NSString).length))
            } else {
                tv.insertText("\n" + next, replacementRange: tv.selectedRange())
            }
            return true
        }

        /// Shift-Return (insertLineBreak) in a list item stays in the same item: a newline plus spaces as wide as the
        /// marker, so the wrapped line sits under the item's text. No new bullet, number or checkbox, and an empty item
        /// does not end the list. In a quote the `> ` carries on (a quote line without it would leave the quote), which
        /// is the same as Return. Plain paragraphs fall through to the text view's normal newline.
        func softBreak(_ tv: NSTextView) -> Bool {
            guard tv.selectedRange().length == 0 else { return false }
            let (para, line, caret) = currentLine(tv)
            let indent: String
            if let m = ListMarker(line: line) { indent = String(repeating: " ", count: (m.prefix as NSString).length) }
            else if line.hasPrefix("> ") { indent = "> " }
            else { return false }
            guard caret >= para.location + (indent as NSString).length else { return false }
            tv.insertText("\n" + indent, replacementRange: tv.selectedRange())
            return true
        }

        /// Tab and Shift-Tab nest and un-nest a list item.
        func shift(_ tv: NSTextView, by n: Int) -> Bool {
            let (para, line, _) = currentLine(tv)
            guard ListMarker(line: line) != nil else { return false }
            if n > 0 {
                tv.insertText(String(repeating: " ", count: n), replacementRange: NSRange(location: para.location, length: 0))
            } else {
                let lead = line.prefix { $0 == " " }.count
                if lead > 0 { tv.insertText("", replacementRange: NSRange(location: para.location, length: min(-n, lead))) }
            }
            return true
        }

        /// Backspace just after a bullet un-nests it, and then removes the bullet.
        func deleteMarker(_ tv: NSTextView) -> Bool {
            guard tv.selectedRange().length == 0 else { return false }
            let (para, line, caret) = currentLine(tv)
            guard let m = ListMarker(line: line), caret == para.location + (m.prefix as NSString).length else { return false }
            let lead = line.prefix { $0 == " " }.count
            if lead >= 2 { tv.insertText("", replacementRange: NSRange(location: para.location, length: 2)) }
            else { tv.insertText("", replacementRange: NSRange(location: para.location, length: (m.prefix as NSString).length)) }
            return true
        }
    }
}

/// Lets the rest of the app reach the editor (jump to a heading).
final class EditorBridge {
    weak var textView: EditorTextView?
    /// The binder is being walked with the arrow keys: opening a note must not pull the caret away.
    var keepFocusElsewhere = false
}
