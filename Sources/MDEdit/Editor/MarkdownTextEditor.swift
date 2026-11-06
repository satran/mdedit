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
    /// HTML, JSON or YAML: the editor shows the file as code. nil is a Markdown note.
    var code: CodeKind?
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
        tv.bridge = bridge
        bridge?.textView = tv
        Self.configure(tv, code: code)

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
        tv.code = code
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
        tv.bridge = bridge
        bridge?.textView = tv
        if tv.code != code { Self.configure(tv, code: code); tv.code = code }
        if context.coordinator.linksVersion != linksVersion { context.coordinator.linksVersion = linksVersion; tv.restyle() }
        tv.style = style                                    // restyles itself when it changed
        let switched = context.coordinator.documentID != documentID
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

    /// Code is not prose: no spelling, no autocorrection, no smart replacements.
    static func configure(_ tv: NSTextView, code: CodeKind?) {
        let prose = code == nil
        tv.isContinuousSpellCheckingEnabled = prose
        tv.isAutomaticSpellingCorrectionEnabled = prose
        tv.isAutomaticTextReplacementEnabled = prose
        tv.smartInsertDeleteEnabled = prose
        tv.isGrammarCheckingEnabled = false
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
            tv.updateWikiCompletion()
        }

        func textViewDidChangeSelection(_ n: Notification) {
            guard let tv = n.object as? EditorTextView, !tv.isRestyling else { return }
            if tv.focusDim { tv.restyle() }
            if tv.wikiList.isOpen { tv.updateWikiCompletion() }
            if tv.typewriter { DispatchQueue.main.async { tv.centerCaret() } }
        }

        /// Return keeps the indentation; Tab indents by two spaces; Shift-Tab takes two away.
        func codeCommand(_ tv: NSTextView, _ sel: Selector) -> Bool {
            let ns = tv.string as NSString
            switch sel {
            case #selector(NSResponder.cancelOperation(_:)):
                if parent.onEscape?() == true { return true }
                tv.window?.makeFirstResponder(nil); return true
            case #selector(NSResponder.insertNewline(_:)):
                let sel = tv.selectedRange()
                let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
                let lead = String(ns.substring(with: line).prefix { $0 == " " || $0 == "\t" })
                let carried = String(lead.prefix(max(0, min((lead as NSString).length, sel.location - line.location))))
                tv.insertText("\n" + carried, replacementRange: sel)
                return true
            case #selector(NSResponder.insertTab(_:)):
                let sel = tv.selectedRange()
                let lines = ns.lineRange(for: sel)
                if sel.length == 0 || !ns.substring(with: sel).contains("\n") { tv.insertText("  ", replacementRange: sel); return true }
                let text = ns.substring(with: lines)
                let out = text.components(separatedBy: "\n").map { $0.isEmpty ? $0 : "  " + $0 }.joined(separator: "\n")
                tv.insertText(out, replacementRange: lines)
                tv.setSelectedRange(NSRange(location: lines.location, length: (out as NSString).length))
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                let lines = ns.lineRange(for: tv.selectedRange())
                let text = ns.substring(with: lines)
                let out = text.components(separatedBy: "\n").map { l -> String in
                    var n = 0; for c in l.prefix(2) where c == " " { n += 1 }
                    return String(l.dropFirst(n))
                }.joined(separator: "\n")
                guard out != text else { return true }
                tv.insertText(out, replacementRange: lines)
                tv.setSelectedRange(NSRange(location: lines.location, length: (out as NSString).length))
                return true
            default: return false
            }
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            if parent.code != nil { return codeCommand(tv, sel) }
            if let editor = tv as? EditorTextView, editor.wikiList.handle(sel) { return true }
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

        /// Shift-Return: just a new line. It never starts a bullet, number, task or quote; the only thing it carries over is
        /// the indentation the current line already has (the spaces or tabs it starts with), so indented text stays indented.
        func softBreak(_ tv: NSTextView) -> Bool {
            let (para, line, caret) = currentLine(tv)
            let lead = String(line.prefix { $0 == " " || $0 == "\t" })
            // with the caret inside the indentation, only the part before it is carried over
            let carried = String(lead.prefix(max(0, min((lead as NSString).length, caret - para.location))))
            tv.insertText("\n" + carried, replacementRange: tv.selectedRange())
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
    weak var textView: EditorTextView? { didSet { if let tv = textView, tv !== oldValue { onAttach?() } } }   // assigned on every SwiftUI update: only a new view counts
    /// Called when an editor view arrives, so state drawn behind the text (the selected suggestion) reaches it.
    var onAttach: (() -> Void)?
    /// The keyboard should land in the editor as soon as there is one in a window. Switching Write/View or distraction-free
    /// replaces the editor view, so asking the current one is not enough: the new one takes the request when it arrives.
    private(set) var wantsFocus = false

    func requestFocus() {
        wantsFocus = true
        if let tv = textView { tv.window?.makeFirstResponder(tv) }
        // a request that nobody picks up must not stay armed and surprise a later editor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in self?.wantsFocus = false }
    }

    /// A new editor view has reached a window: give it the keyboard if one was asked for.
    func fulfil(_ tv: EditorTextView) {
        guard wantsFocus, tv.window != nil else { return }
        wantsFocus = false
        tv.window?.makeFirstResponder(tv)
    }
    /// The binder is being walked with the arrow keys: opening a note must not pull the caret away.
    var keepFocusElsewhere = false
}
