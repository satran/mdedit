import SwiftUI

enum TemplateState: Equatable {
    case notTemplate
    case needsRender
    case rendering
    case rendered(String)
    case cancelled
    case failed(TemplateError)
}

/// Rendering an HTML page that uses template tags (plan 006). A render starts only when the person presses Render; nothing here
/// writes to the folder, and nothing renders by itself when a file or the folder changes.
extension Workspace {
    static let trustSentence = "A rendered page can read every note in this folder and show it on screen. It cannot change anything, and it makes no network request on its own. You are asked this once."

    /// The open file is an HTML page whose text holds `{%` or `{{`.
    static func isTemplateCandidate(url: URL?, text: String) -> Bool {
        guard let url, BinderNode.htmlExtensions.contains(url.pathExtension.lowercased()) else { return false }
        return text.contains("{%") || text.contains("{{")
    }

    var isTemplateCandidate: Bool { Self.isTemplateCandidate(url: document.url, text: document.text) }

    /// A document was opened or reloaded: stop a running render, forget its result, and show the banner again if the page has tags.
    func resetTemplateState(url: URL?, text: String) {
        templateGeneration += 1
        if renderBusy { templateCancel.cancel() }
        let next: TemplateState = Self.isTemplateCandidate(url: url, text: text) ? .needsRender : .notTemplate
        if templateState != next { templateState = next }
    }

    /// The Render button: parse, ask once per version of the file, then evaluate on a background task.
    func render() {
        guard !renderBusy, let rootURL, let url = document.url, showingHTML else { return }
        switch templateState { case .needsRender, .cancelled, .failed: break; default: return }
        // the file is read once; this one string is parsed and evaluated
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            templateState = .failed(.syntax("This file cannot be read as text.", line: nil)); return
        }
        if case .failure(let e) = TemplateParser.parse(text, limits: templateLimits) { templateState = .failed(e); return }
        // the very first Render in the app warns once; after that Render just renders
        if !TemplateTrust.hasBeenWarned(defaults: defaults) {
            guard templateConfirm("Render this page?", Self.trustSentence, "Render", nil, false) else { templateState = .needsRender; return }
            TemplateTrust.markWarned(defaults: defaults)
        }
        start(text: text, root: rootURL)
    }

    private func start(text: String, root: URL) {
        templateGeneration += 1
        let generation = templateGeneration
        let flag = CancelFlag()
        templateCancel = flag
        templateState = .rendering
        renderBusy = true
        let limits = templateLimits, source = templateSource
        Task { @MainActor [weak self] in
            let result = await TemplateEvaluator.render(text: text, root: root, cancel: flag, limits: limits, source: source)
            self?.renderFinished(result, generation: generation)
        }
        // the clock is also watched from here: a read blocked in the operating system cannot be interrupted,
        // and the preview must not wait for it
        DispatchQueue.main.asyncAfter(deadline: .now() + limits.clock) { [weak self] in
            guard let self, self.templateGeneration == generation, self.templateState == .rendering else { return }
            flag.cancel()
            self.templateState = .failed(.timeout)
        }
    }

    private func renderFinished(_ result: Result<String, TemplateError>, generation: Int) {
        renderBusy = false
        // another document, a cancel or the timeout got there first: this result is dropped
        guard templateGeneration == generation, templateState == .rendering else { return }
        switch result {
        case .success(let html): templateState = .rendered(html)
        case .failure(.cancelled): templateState = .cancelled
        case .failure(let e): templateState = .failed(e)
        }
    }

    func cancelRender() {
        guard templateState == .rendering else { return }
        templateCancel.cancel()
        templateState = .cancelled
    }

    /// Back to the plain page and the Render button.
    func showTemplateSource() {
        switch templateState { case .rendered, .failed: templateState = .needsRender; default: break }
    }

    /// A click in a rendered template page. Links to notes and files behave as on any page, relative to the opened folder;
    /// a web or mail address asks first, with the whole address, and Cancel is the default.
    func openTemplateLink(_ url: URL) {
        switch LinkPolicy.decide(url, noteFolder: rootURL, root: rootURL) {
        case .wiki(let t): openWiki(t)
        case .openWeb(let u):
            let text = u.absoluteString
            let shown = text.firstIndex(of: "?").map { String(text[..<$0]) + "\n" + String(text[$0...]) } ?? text
            let detail = u.scheme?.lowercased() == "mailto"
                ? "Opens your mail program with this draft. It may contain text from your notes."
                : "It may contain text from your notes."
            if templateConfirm("Open this address?", detail, "Open", shown, true) { openAddress(u) }
        case .selectNote(let u): select(u)
        case .openFile(let u): NSWorkspace.shared.open(u)
        case .reveal(let u): NSWorkspace.shared.activateFileViewerSelecting([u])
        case .ignore: break
        }
    }
}
