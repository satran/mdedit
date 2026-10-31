import AppKit

extension EditorTextView {
    /// Runs one Format command on the selection: a single replacement, so one undo step.
    @discardableResult
    func applyFormat(_ action: FormatAction) -> Bool {
        guard isEditable, let edit = MarkdownFormatting.edit(action, in: string as NSString, selection: selectedRange()) else { return false }
        breakUndoCoalescing()
        insertText(edit.replacement, replacementRange: edit.range)
        breakUndoCoalescing()
        let n = (string as NSString).length
        let loc = min(edit.selection.location, n)
        setSelectedRange(NSRange(location: loc, length: min(edit.selection.length, n - loc)))
        scrollRangeToVisible(selectedRange())
        return true
    }
}

extension EditorBridge {
    /// Applies a Markdown formatting command to the editor in front. Does nothing without an editor.
    @discardableResult
    func apply(_ action: FormatAction) -> Bool { textView?.applyFormat(action) ?? false }
}
