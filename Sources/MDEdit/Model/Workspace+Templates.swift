import SwiftUI

enum TemplateState: Equatable {
    case notTemplate
    /// A page with template tags that is not rendered at the moment (the editor shows its source).
    case needsRender
    case rendering
    case rendered(String)
    case failed(TemplateError)
}

/// Rendering an HTML page that uses template tags (plan 006). The editor shows the source; the preview renders it. Nothing here writes
/// to the folder, and nothing renders by itself when a note or the folder changes.
extension Workspace {
    static let trustSentence = "A rendered page can read every note in this folder and show it on screen. It cannot change anything, and it makes no network request on its own. You are asked this once."

    static func isTemplateCandidate(url: URL?, text: String) -> Bool {
        guard let url, BinderNode.htmlExtensions.contains(url.pathExtension.lowercased()) else { return false }
        return text.contains("{%") || text.contains("{{")
    }

    var isTemplateCandidate: Bool { Self.isTemplateCandidate(url: document.url, text: document.text) }

    // MARK: the preview of a code file

    /// The path used for the record of previewed files.
    private func previewPath(_ url: URL) -> String { rootURL.flatMap { SafePath.relative(url, in: $0) } ?? url.lastPathComponent }

    /// True when this exact text was previewed before (and, for a template, the one-time warning has been answered): it opens in the preview.
    var previewedBefore: Bool {
        guard let url = document.url, let rootURL else { return false }
        if isTemplateCandidate && !TemplateTrust.hasBeenWarned(defaults: defaults) { return false }
        return TemplateTrust.wasRendered(previewPath(url), text: document.text, root: rootURL, defaults: defaults)
    }

    /// The mode became the preview. A template is rendered (the first time in the app, after the warning; declining goes back to the
    /// editor); any other file is shown as it is. Either way the text is saved first, so the preview shows what the editor shows.
    func enterPreview() {
        guard let url = document.url, let rootURL else { return }
        document.saveNow()
        if isTemplateCandidate {
            if !render() { mode = .write }
        } else {
            TemplateTrust.markRendered(previewPath(url), text: document.text, root: rootURL, defaults: defaults)
        }
    }

    /// The mode went back to the editor (or the document changed): stop a render, forget its result and the query.
    func leavePreview() { resetTemplateState(url: document.url, text: document.text) }

    /// A document was opened, reloaded or edited, or the preview was left: stop a running render, forget its result, and note
    /// whether the page has tags. A page that was being previewed when its text changed goes back to the editor.
    func resetTemplateState(url: URL?, text: String) {
        templateGeneration += 1
        templateQuery = [:]
        if renderBusy { templateCancel.cancel() }
        let wasPreviewing: Bool
        switch templateState { case .rendering, .rendered, .failed: wasPreviewing = true; default: wasPreviewing = false }
        let next: TemplateState = Self.isTemplateCandidate(url: url, text: text) ? .needsRender : .notTemplate
        if templateState != next { templateState = next }
        if wasPreviewing, mode == .view { mode = .write }
    }

    /// Renders the open template: parse, warn once in the app, then evaluate on a background task. False when nothing was started because
    /// a blocked read is still outstanding or the warning was declined; true when a render started or the page failed to parse.
    @discardableResult
    func render() -> Bool {
        guard !renderBusy, let rootURL, let url = document.url, showingHTML else { return false }
        switch templateState { case .needsRender, .failed: break; default: return false }
        // this one string is parsed, shown to nobody and evaluated; it is the editor's text, saved just before
        document.saveNow()
        let text = document.text
        if case .failure(let e) = TemplateParser.parse(text, limits: templateLimits) { templateState = .failed(e); return true }
        let path = previewPath(url)
        // the very first Render in the app warns once; after that Render just renders
        if !TemplateTrust.hasBeenWarned(defaults: defaults) {
            guard templateConfirm("Render this page?", Self.trustSentence, "Render", nil, false) else { templateState = .needsRender; return false }
            TemplateTrust.markWarned(defaults: defaults)
        }
        TemplateTrust.markRendered(path, text: text, root: rootURL, defaults: defaults)
        start(text: text, root: rootURL)
        return true
    }

    private func start(text: String, root: URL) {
        templateGeneration += 1
        let generation = templateGeneration
        let flag = CancelFlag()
        templateCancel = flag
        templateState = .rendering
        renderBusy = true
        let limits = templateLimits, source = templateSource, query = templateQuery
        Task { @MainActor [weak self] in
            let result = await TemplateEvaluator.render(text: text, root: root, cancel: flag, limits: limits, source: source, query: query)
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
        case .failure(.cancelled): templateState = .needsRender
        case .failure(let e): templateState = .failed(e)
        }
    }

    /// Cancel: stop the render and go back to the editor.
    func cancelRender() {
        guard templateState == .rendering else { return }
        templateCancel.cancel()
        mode = .write
    }

    /// Back to the source.
    func showTemplateSource() { mode = .write }

    /// A click in a rendered template page. Links to notes and files behave as on any page, relative to the opened folder;
    /// a web or mail address asks first, with the whole address, and Cancel is the default.
    func openTemplateLink(_ url: URL) {
        // a link to the rendered page itself, `?due=overdue`: render again with those parameters
        if url.scheme == PreviewPage.scheme, let rootURL, url.path == PreviewPage.templateAddress(root: rootURL).path {
            rerender(query: Self.queryParameters(url, limits: templateLimits)); return
        }
        switch LinkPolicy.decide(url, noteFolder: rootURL, root: rootURL) {
        case .wiki(let t): openWiki(t)
        case .openWeb(let u):
            if let rootURL, TemplateTrust.isTrusted(u, root: rootURL, defaults: defaults) { openAddress(u); return }
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

    // MARK: query and trusted addresses

    /// The `?key=value&key=value` of a link as text values: keys are plain names (at most 20), a value is at most 256 characters.
    static func queryParameters(_ url: URL, limits: TemplateLimits = .standard) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        return parseQuery(items.map { ($0.name, $0.value ?? "") }, limits: limits)
    }

    /// `due=overdue&priority=A`, for a tool that cannot send a record.
    static func queryParameters(_ text: String, limits: TemplateLimits = .standard) -> [String: String] {
        var c = URLComponents(); c.query = text
        return parseQuery((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, limits: limits)
    }

    private static func parseQuery(_ items: [(String, String)], limits: TemplateLimits) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in items {
            guard let f = k.unicodeScalars.first, f.isASCII, f.properties.isAlphabetic || f == "_",
                  k.unicodeScalars.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || $0 == "_" || ("0"..."9").contains($0)) }), k.count <= 40,
                  out[k] != nil || out.count < limits.queryKeys else { continue }
            out[k] = String(v.prefix(limits.queryValueLength))
        }
        return out
    }

    /// Renders the page that is showing again with new query parameters (a click on a link such as `?due=overdue`).
    func rerender(query: [String: String]) {
        guard case .rendered = templateState, !renderBusy else { return }
        templateQuery = query
        templateState = .needsRender
        render()
    }

    /// The command "Trusted Addresses for Templates…": the hosts that open without asking, for this folder.
    func editTrustedAddresses() {
        guard let rootURL else { return }
        let current = TemplateTrust.trustedHosts(root: rootURL, defaults: defaults).joined(separator: "\n")
        guard let edited = editTrustedHosts(current) else { return }
        TemplateTrust.setTrustedHosts(edited.components(separatedBy: .newlines), root: rootURL, defaults: defaults)
    }
}
