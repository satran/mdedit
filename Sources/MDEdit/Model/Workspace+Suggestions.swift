import AppKit

extension Workspace {
    /// Accepts a suggestion: the one place an agent's text reaches a note, and only after the person pressed Accept.
    /// Opens the note if needed, finds `old` again in the editor's own text, and replaces it in one undoable step.
    @MainActor func accept(_ p: Proposal) async -> AcceptOutcome {
        // 1. get the note into an editable editor (the app may need a moment to build it)
        if document.url?.resolvingSymlinksInPath() != p.url, let root = rootURL { select(root.appendingPathComponent(p.path)) }
        if mode == .view, !showingHTML { mode = .write }
        guard let tv = await editorReady(for: p.url) else { return .blocked("Couldn't open the note.") }
        // 2. the passage must still be there exactly once
        let found = ProposalStore.matches(of: p.old, in: tv.string)
        guard found.count == 1 else { return .stale }
        // 3. the disk guard stays in charge
        if document.changedOnDisk && document.dirty { return .blocked("The note changed on disk. Resolve that first.") }
        // 4. one undoable edit
        guard tv.applySuggestion(range: found[0], replacement: p.new) else { return .blocked("The note is not editable.") }
        return .applied
    }

    /// Polls every 20 ms, up to 2 s, for an editor that shows `url`.
    @MainActor private func editorReady(for url: URL) async -> EditorTextView? {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if document.url?.resolvingSymlinksInPath() == url, mode == .write, let tv = editor.textView, tv.window != nil, tv.string == document.text { return tv }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }
}

extension EditorTextView {
    /// Replaces `range` with `replacement` as one undo step named "Accept Suggestion", and shows the result.
    /// false when the view cannot be edited. The text goes through the text system so the delegate runs and ⌘Z works.
    @discardableResult
    func applySuggestion(range: NSRange, replacement: String) -> Bool {
        guard isEditable else { return false }
        let n = (string as NSString).length
        guard range.location >= 0, range.location + range.length <= n else { return false }
        breakUndoCoalescing()
        insertText(replacement, replacementRange: range)
        undoManager?.setActionName("Accept Suggestion")
        breakUndoCoalescing()
        let shown = NSRange(location: range.location, length: (replacement as NSString).length)
        setSelectedRange(shown)
        scrollRangeToVisible(shown)
        return true
    }
}
