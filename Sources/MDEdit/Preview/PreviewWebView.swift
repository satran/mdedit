import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// What the preview shows: a note as Markdown, or an HTML file.
struct PreviewRequest {
    enum Source: Equatable {
        case markdown(String)
        case html(URL, text: String)
        /// A rendered template (plan 006): served from memory at `PreviewPage.templateAddress(root:)`, under the template rules.
        case template(rendered: String)
    }
    var source: Source
    var title = ""
    /// The folder pictures and links are relative to (the note's own).
    var noteFolder: URL?
    /// The opened folder: the only place a page may read from.
    var root: URL?
    var options: PreviewPage.Options

    /// The note itself, so a reload of the same one keeps its scroll position.
    var identity: String {
        switch source {
        case .markdown: return "md:" + (noteFolder?.path ?? "") + "/" + title
        case .html(let u, _): return "html:" + u.path
        case .template: return "template:" + (root?.path ?? "")
        }
    }

    /// Everything a page is made of. Equal keys: nothing to reload.
    var key: String {
        let o = options
        let body: String
        switch source { case .markdown(let t): body = t; case .html(_, let t): body = t; case .template(let t): body = t }
        var h = Hasher()
        h.combine(body); h.combine(o.customCSS ?? "")
        return "\(identity)|\(o.style.family)|\(o.style.scale)|\(o.style.width)|\(isTemplate ? false : o.loadRemote)|\(h.finalize())"
    }

    var isTemplate: Bool { if case .template = source { return true }; return false }
}

/// Serves what a page loads. A page can read the opened folder and the app's own fonts, and nothing else on the Mac.
final class PreviewFiles: NSObject, WKURLSchemeHandler {
    var roots: [URL] = []
    var loadRemote = false
    static let maxBytes = 50 * 1024 * 1024

    /// A rendered template, held in memory and answered at `templateURL` before any file is looked up, so a real file of that name
    /// cannot take its place. Set and cleared by the controller together with the request.
    var templatePage: String?
    var templateURL: URL?
    /// For template pages: a path with a hidden part below the opened folder (also one reached through a link) is not served.
    var refuseHidden = false

    func allows(_ file: URL) -> Bool {
        let path = file.resolvingSymlinksInPath().path
        for root in roots {
            let r = root.resolvingSymlinksInPath().path
            guard path.hasPrefix(r + "/") else { continue }
            if refuseHidden, path.dropFirst(r.count + 1).split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            return true
        }
        return false
    }

    /// The body and headers for the template address, or nil for any other address.
    func templateResponse(for url: URL) -> (data: Data, headers: [String: String])? {
        guard let page = templatePage, let t = templateURL, url.absoluteString == t.absoluteString else { return nil }
        let data = Data(page.utf8)
        return (data, ["Content-Type": "text/html; charset=utf-8", "Content-Length": String(data.count),
                       "Content-Security-Policy": PreviewPage.csp(loadRemote: false)])
    }

    private func bundled(_ name: String) -> URL? {
        guard PreviewPage.fontFaces.contains(where: { $0.file == name }), let dir = Bundle.main.resourceURL else { return nil }
        return [dir.appendingPathComponent("Fonts/" + name), dir.appendingPathComponent(name)].first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The file behind an address, if the page may have it.
    func resolve(_ url: URL) -> URL? {
        if url.host == "bundle" { return bundled(url.lastPathComponent) }
        guard let f = PreviewPage.file(from: url), allows(f) else { return nil }
        return f.resolvingSymlinksInPath()
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        if let url = task.request.url, let page = templateResponse(for: url) {
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: page.headers) else { return fail(task, .badServerResponse) }
            task.didReceive(response); task.didReceive(page.data); task.didFinish()
            return
        }
        guard let url = task.request.url, let file = resolve(url) else { return fail(task, .noPermissionsToReadFile) }
        var isDir: ObjCBool = false
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir), !isDir.boolValue, size <= Self.maxBytes,
              let data = try? Data(contentsOf: file) else { return fail(task, .fileDoesNotExist) }
        let ext = file.pathExtension.lowercased()
        var mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        if ext == "html" || ext == "htm" { mime = "text/html" }
        var headers = ["Content-Type": mime + (mime.hasPrefix("text/") ? "; charset=utf-8" : ""), "Content-Length": String(data.count)]
        if mime == "text/html" { headers["Content-Security-Policy"] = PreviewPage.headerCSP(loadRemote: loadRemote) }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else { return fail(task, .badServerResponse) }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func fail(_ task: any WKURLSchemeTask, _ code: URLError.Code) { task.didFailWithError(URLError(code)) }
}

/// A compiled web-view content rule list. `shared` keeps ordinary pages from reaching the web (images, styles, fonts, scripts and
/// similar requests to http(s) are blocked); `template` blocks every http(s) request of any type, for rendered templates.
@MainActor final class PreviewRules {
    static let shared = PreviewRules(identifier: "in.ranjeev.mdedit.noremote", json: noRemoteJSON)
    static let template = PreviewRules(identifier: "in.ranjeev.mdedit.template", json: templateJSON)

    nonisolated static let noRemoteJSON = """
    [{"trigger":{"url-filter":"^https?://","resource-type":["image","style-sheet","script","font","raw","svg-document","media"]},"action":{"type":"block"}}]
    """
    /// No `resource-type`: the rule matches every type of request.
    nonisolated static let templateJSON = """
    [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]
    """

    let identifier: String
    let json: String
    private(set) var list: WKContentRuleList?
    private(set) var ready = false
    private var compiling = false
    private var waiting: [() -> Void] = []

    init(identifier: String, json: String) { self.identifier = identifier; self.json = json }

    func whenReady(_ f: @escaping () -> Void) {
        if ready { f(); return }
        waiting.append(f)
        guard !compiling else { return }
        compiling = true
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { [weak self] list, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // `list` is nil when compiling failed: ready, but with nothing to apply
                self.list = list; self.ready = true; self.compiling = false
                let w = self.waiting; self.waiting = []
                w.forEach { $0() }
            }
        }
    }
}

/// One web view and the rules for what it may load and where a click on a link goes.
@MainActor final class PreviewController: NSObject, WKNavigationDelegate, WKUIDelegate {
    let files: PreviewFiles
    let webView: WKWebView
    /// Where a click goes: the address as the note wrote it (relative links already made absolute; local files as `file:` addresses).
    var open: (URL) -> Void
    /// Counts finished loads; the tests wait on it.
    private(set) var loads = 0

    /// The rule list for rendered templates; a test can supply its own.
    var templateRules = PreviewRules.template

    private var key = ""
    private var identity = ""
    private var generation = 0
    /// The addresses of the loads this controller started and that have not been through the navigation policy yet. A load of ours is
    /// allowed once per entry; a page's own navigation (a reload, a form, meta refresh) is not in the list and is cancelled. It is a list,
    /// not a flag: two loads close together (a blank page, then the rendered one) must both be allowed, whatever order the policy
    /// answers come in, or the second page stays blank.
    private var expected: [String] = []

    private func expect(_ url: URL?) {
        expected.append(Self.normalized(url))
        if expected.count > 8 { expected.removeFirst(expected.count - 8) }
    }

    private static func normalized(_ url: URL?) -> String { (url ?? URL(string: "about:blank")!).absoluteString }
    private var restoreY: Double?

    init(open: @escaping (URL) -> Void) {
        self.open = open
        let files = PreviewFiles()
        self.files = files
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // the web view keeps a copy of the configuration made here
        config.setURLSchemeHandler(files, forURLScheme: PreviewPage.scheme)
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.underPageBackgroundColor = Palette.paneBg
    }

    func show(_ r: PreviewRequest) {
        let k = r.key
        guard k != key else { return }
        let sameNote = r.identity == identity
        key = k; identity = r.identity
        files.roots = [r.root, r.noteFolder].compactMap { $0 }
        files.loadRemote = r.isTemplate ? false : r.options.loadRemote
        files.refuseHidden = r.isTemplate
        if case .template(let page) = r.source, let root = r.root {
            files.templatePage = page; files.templateURL = PreviewPage.templateAddress(root: root)
        } else { files.templatePage = nil; files.templateURL = nil }
        generation += 1
        let mine = generation
        let rules: PreviewRules? = r.isTemplate ? templateRules : (r.options.loadRemote ? nil : PreviewRules.shared)
        let go = { [weak self] in
            guard let self, self.generation == mine else { return }
            // a template page is only shown under its rule list: if there is none (compiling failed), it is not loaded
            if r.isTemplate, rules?.list == nil { self.showCompileFailure(); return }
            self.apply(rules: rules?.list)
            if sameNote {
                self.webView.evaluateJavaScript("window.scrollY", in: nil, in: .defaultClient) { result in
                    MainActor.assumeIsolated {
                        guard self.generation == mine else { return }
                        self.load(r, scrollTo: (try? result.get()) as? Double)
                    }
                }
            } else {
                self.load(r, scrollTo: nil)
            }
        }
        if let rules { rules.whenReady(go) } else { go() }
    }

    private func apply(rules list: WKContentRuleList?) {
        let c = webView.configuration.userContentController
        c.removeAllContentRuleLists()
        if let list { c.add(list) }
    }

    private func showCompileFailure() {
        expect(URL(string: "about:blank"))
        files.templatePage = nil
        webView.loadHTMLString(PreviewPage.errorPage(title: "Page not shown", message: "The rules that keep a template page off the web could not be loaded.", line: nil),
                               baseURL: URL(string: "about:blank"))
    }

    private func load(_ r: PreviewRequest, scrollTo y: Double?) {
        restoreY = y
        switch r.source {
        case .markdown(let text):
            let html = PreviewPage.html(markdown: text, title: r.title, options: r.options)
            let base = r.noteFolder.map { PreviewPage.url(forFile: $0, directory: true) } ?? URL(string: "\(PreviewPage.scheme)://none/")
            expect(base)
            webView.loadHTMLString(html, baseURL: base)
        case .html(let url, _):
            let address = PreviewPage.url(forFile: url)
            expect(address)
            webView.load(URLRequest(url: address))
        case .template:
            guard let root = r.root else { return showCompileFailure() }
            let address = PreviewPage.templateAddress(root: root)
            expect(address)
            webView.load(URLRequest(url: address))
        }
    }

    // MARK: navigation

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.allowsContentJavaScript = false
        decisionHandler(policy(for: action), preferences)
    }

    private func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
        let url = action.request.url
        if action.targetFrame?.isMainFrame == false {
            // a frame inside an HTML file: only the folder's own pages
            return url?.scheme == PreviewPage.scheme || url?.absoluteString == "about:blank" ? .allow : .cancel
        }
        if action.navigationType == .other, let i = expected.firstIndex(of: Self.normalized(url)) { expected.remove(at: i); return .allow }
        if action.navigationType == .linkActivated, let url {
            if let current = webView.url, url.fragment != nil, strip(url) == strip(current) { return .allow }
            // a link to the rendered page itself (`?due=overdue`) keeps its address, so the query reaches the template
            if url.scheme == PreviewPage.scheme, let t = files.templateURL, url.path == t.path { self.open(url) }
            else { self.open(PreviewPage.file(from: url) ?? url) }
        }
        // reloads, meta refresh, forms, scripts' navigations: the page stays where it is
        return .cancel
    }

    private func strip(_ u: URL) -> String { u.absoluteString.components(separatedBy: "#")[0] }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loads += 1
        if let y = restoreY, y > 0 { webView.evaluateJavaScript("window.scrollTo(0, \(y))", in: nil, in: .defaultClient) { _ in } }
        restoreY = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { loads += 1 }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { loads += 1 }

    /// A page never opens windows.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
}

struct PreviewWebView: NSViewRepresentable {
    let request: PreviewRequest
    let open: (URL) -> Void

    func makeCoordinator() -> PreviewController { PreviewController(open: open) }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.show(request)
        return context.coordinator.webView
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.open = open
        context.coordinator.show(request)
    }
}
