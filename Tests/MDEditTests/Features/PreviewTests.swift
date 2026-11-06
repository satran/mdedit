import XCTest
import WebKit
@testable import MDEdit

/// The preview: a note (or an HTML file) shown in a web view that cannot run scripts, reach the web unless asked,
/// or read outside the opened folder.
@MainActor
final class PreviewTests: XCTestCase {
    private var s: Scratch!

    override func setUpWithError() throws {
        s = try Scratch(["Notes/One.md": "# One", "page.html": "<p>hello</p>"])
        addTeardownBlock { [s] in s?.remove() }
    }

    private func options(remote: Bool = false, css: String? = nil, family: String = "Inter") -> PreviewPage.Options {
        .init(style: ViewerStyle(family: family), loadRemote: remote, customCSS: css)
    }
    private func page(_ md: String, _ o: PreviewPage.Options? = nil) -> String { PreviewPage.html(markdown: md, title: "T", options: o ?? options()) }
    private func body(_ md: String) -> String { PreviewPage.body(markdown: md) }

    // MARK: the page

    func testTaskBoxesAreDrawnByThePageSoTheyLineUpWithTheText() {
        let css = page("- [ ] a\n")
        XCTAssertTrue(css.contains("li > input[type=checkbox] {"))
        XCTAssertTrue(css.contains("appearance: none; font-size: inherit"), "the native box is tiny and rides above the line")
    }

    func testEveryBlockKindIsInThePageAndPropertiesComeFirst() {
        let h = body("---\ntitle: T\ntags: [a, b]\ndone: true\n---\n# H\n\npara\n\n> q\n\n- a\n- [x] b\n\n1. x\n\n```swift\nlet a = 1\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n---\n\n![alt](pic.png)\n")
        let order = ["class=\"props\"", "<h1>", "<p>para", "<blockquote>", "<ul>", "type=\"checkbox\"", "<ol>", "<pre><code class=\"language-swift\">", "<table>", "<hr", "<img src=\"pic.png\""]
        var at = h.startIndex
        for needle in order {
            guard let r = h.range(of: needle, range: at..<h.endIndex) else { return XCTFail("\(needle) missing or out of order in \(h)") }
            at = r.upperBound
        }
        XCTAssertTrue(h.contains("<span class=\"chip\">a</span>"))
    }

    func testRawHTMLInANoteIsShownAsTextNotRun() {
        let h = body("<script>alert(1)</script>\n\ntext <b>bold</b> <img src=x onerror=1>")
        XCTAssertFalse(h.contains("<script"), h)
        XCTAssertFalse(h.contains("<b>"), h)
        XCTAssertFalse(h.contains("onerror=1>"), h)
        XCTAssertTrue(h.contains("&lt;script&gt;") && h.contains("&lt;b&gt;"))
    }

    func testHostileLinksAndImagesLoseTheirTarget() {
        let h = body("[a](javascript:alert(1)) [b](java\tscript:x) ![c](file:///etc/passwd) [d](data:text/html,x) [ok](https://x.io)")
        XCTAssertFalse(h.contains("javascript"), h)
        XCTAssertFalse(h.contains("file:///etc"), h)
        XCTAssertFalse(h.contains("data:text"), h)
        XCTAssertTrue(h.contains("href=\"https://x.io\""))
    }

    func testPunctuationWikiLinksAndAddressesAreSetLikeTheViewerSetThem() {
        let h = body("She said \"hi\" -- and left... go [[Goals|our goals]] or https://dora.dev.\n\n`it's \"raw\"` and [\"quoted\" link](https://a.b)")
        XCTAssertTrue(h.contains("“hi” – and left…"), h)
        XCTAssertTrue(h.contains("<a href=\"mdedit://wiki/Goals\">our goals</a>"), h)
        XCTAssertTrue(h.contains("<a href=\"https://dora.dev\">https://dora.dev</a>."), "the full stop is the sentence's, not the address's: \(h)")
        XCTAssertTrue(h.contains("<code>it&#39;s &quot;raw&quot;</code>"), "code is never touched: \(h)")
        XCTAssertTrue(h.contains(">“quoted” link</a>"), h)
    }

    func testFrontMatterValuesAreEscapedAndLinked() {
        let h = body("---\ntitle: <b>x</b> [[Goals]]\nlink: https://x.io\n---\ntext")
        XCTAssertFalse(h.contains("<b>"), h)
        XCTAssertTrue(h.contains("mdedit://wiki/Goals") && h.contains("href=\"https://x.io\""), h)
    }

    func testThePageTakesItsSizesFromTheTypeSpecs() {
        let css = PreviewPage.css(ViewerStyle())
        XCTAssertTrue(css.contains("h1 { font-size: 34px") && css.contains("max-width: 648px"), css)
        let big = PreviewPage.css(ViewerStyle(body: 21.6))
        XCTAssertTrue(big.contains("h1 { font-size: 40.8px"), "sizes follow the text size setting")
        XCTAssertTrue(css.contains("prefers-color-scheme: dark"), "dark mode is in the page itself")
    }

    func testTheFontComesFromTheSettingAndCannotBreakOutOfTheStylesheet() {
        XCTAssertTrue(PreviewPage.css(ViewerStyle()).contains("\"Inter\", system-ui"))
        XCTAssertTrue(PreviewPage.css(ViewerStyle(family: "Helvetica Neue")).contains("\"Helvetica Neue\", system-ui"))
        let evil = PreviewPage.css(ViewerStyle(family: "x\"; } </style><script>alert(1)</script>"))
        XCTAssertFalse(evil.contains("<script>"), evil)
    }

    func testTheCustomStylesheetComesAfterTheBuiltInFont() throws {
        let h = page("x", options(css: "body { font-family: Georgia; }"))
        let builtIn = try XCTUnwrap(h.range(of: "\"Inter\", system-ui")), custom = try XCTUnwrap(h.range(of: "font-family: Georgia"))
        XCTAssertLessThan(builtIn.lowerBound, custom.lowerBound, "later rules win")
    }

    func testCSPAllowsTheWebOnlyWhenAsked() {
        let off = PreviewPage.csp(loadRemote: false), on = PreviewPage.csp(loadRemote: true)
        XCTAssertFalse(off.contains("https:") || off.contains("http:"), off)
        XCTAssertTrue(on.contains("https:"))
        for c in [off, on] { XCTAssertTrue(c.contains("script-src 'none'") && c.contains("default-src 'none'"), c) }
        XCTAssertTrue(PreviewPage.headerCSP(loadRemote: false).contains("script-src 'none'"))
        XCTAssertFalse(PreviewPage.headerCSP(loadRemote: false).contains("https:"))
        XCTAssertTrue(page("x", options(remote: true)).contains(on))
    }

    func testCustomStylesheetComesLastAndCannotBreakOut() {
        let h = page("x", options(css: "h1 { color: red }\n</style><script>alert(1)</script>"))
        XCTAssertFalse(h.contains("</style><script"), "the sheet cannot close its element: \(h)")
        let built = h.range(of: "h1 { font-size")!.lowerBound, custom = h.range(of: "color: red")!.lowerBound
        XCTAssertLessThan(built, custom, "the reader's sheet wins")
        XCTAssertFalse(page("x").contains("id=\"custom\""))
        let huge = page("x", options(css: String(repeating: "a", count: PreviewPage.maxCustomCSS * 2)))
        XCTAssertLessThan(huge.utf8.count, PreviewPage.maxCustomCSS * 2)
    }

    func testTheTitleAndFontNamesCannotInjectMarkup() {
        let h = PreviewPage.html(markdown: "x", title: "</title><script>alert(1)</script>", options: options())
        XCTAssertFalse(h.contains("<script>"), h)
    }

    func testCustomSheetFileIsReadFromTheFolderOnly() throws {
        XCTAssertNil(CustomCSS.load(s.url))
        let f = CustomCSS.createStarter(s.url)
        XCTAssertEqual(f?.lastPathComponent, "preview.css")
        XCTAssertEqual(CustomCSS.load(s.url), CustomCSS.starter)
        try s.write(".mdedit/preview.css", "h1{color:red}")
        XCTAssertEqual(CustomCSS.load(s.url), "h1{color:red}")
        CustomCSS.createStarter(s.url)
        XCTAssertEqual(CustomCSS.load(s.url), "h1{color:red}", "an existing sheet is never overwritten")
        try s.write(".mdedit/preview.css", Data(repeating: 97, count: PreviewPage.maxCustomCSS + 5))
        XCTAssertNil(CustomCSS.load(s.url), "too big")
        try FileManager.default.removeItem(at: s.path(".mdedit/preview.css"))
        try s.write("elsewhere.css", "h1{}")
        try FileManager.default.createSymbolicLink(at: s.path(".mdedit/preview.css"), withDestinationURL: s.path("elsewhere.css"))
        XCTAssertNil(CustomCSS.load(s.url), "a link could lead out of the folder")
    }

    func testPageWordsLeaveOutTagsScriptsAndStyles() {
        let t = HTMLText.visible("<html><head><style>p{color:red}</style><script>var a = 'many words here'</script></head><body><!-- no --><p>one and &amp; two</p> <b>three</b></body></html>")
        XCTAssertEqual(DocumentStore.wordCount(t), 4, t)
    }

    // MARK: HTML files in the binder

    func testHTMLFilesOpenInThePaneButAreNotNotes() throws {
        try s.write("Sub/about.HTM", "<p>x</p>")
        let root = BinderNode.scan(s.url)
        let node = root.find(s.path("page.html"))!
        XCTAssertTrue(node.isHTML && node.opensInApp && !node.isDocument)
        XCTAssertEqual(node.name, "page.html", "pages keep their extension")
        XCTAssertTrue(root.find(s.path("Sub/about.HTM"))!.isHTML)
        XCTAssertFalse(root.files.contains { $0.isHTML }, "pages are not in the wiki, search or replace")
        XCTAssertEqual(LinkPolicy.decide(s.path("page.html"), noteFolder: s.url, root: s.url), .selectNote(s.path("page.html")))
    }

    func testOpeningAPageForcesThePreviewAndTheNoteAfterGetsItsModeBack() {
        let ws = makeWorkspace(open: s.url)
        ws.select(s.path("Notes/One.md")); ws.mode = .write
        ws.select(s.path("page.html"))
        XCTAssertTrue(ws.showingHTML); XCTAssertEqual(ws.mode, .view)
        ws.mode = .write
        XCTAssertEqual(ws.mode, .view, "a page has no editor")
        ws.toggleFocus(); XCTAssertFalse(ws.focus, "distraction free needs an editor")
        ws.select(s.path("Notes/One.md"))
        XCTAssertEqual(ws.mode, .write, "back to what the reader was doing")
        XCTAssertFalse(ws.showingHTML)
        ws.mode = .view; ws.select(s.path("page.html")); ws.select(s.path("Notes/One.md"))
        XCTAssertEqual(ws.mode, .view)
    }

    func testPageDisablesWhatNeedsAnEditorButKeepsThePreviewButton() {
        let ws = makeWorkspace(open: s.url)
        func enabled(_ id: String) -> Bool { makeCommands(ws: ws, prefs: Preferences(), recents: RecentFolders(), newWindow: { _ in }).first { $0.id == id }!.enabled }
        ws.select(s.path("Notes/One.md"))
        for id in ["write", "view", "preview", "find", "replace", "export-html", "print", "focus"] { XCTAssertTrue(enabled(id), id) }
        ws.select(s.path("page.html"))
        for id in ["write", "view", "preview", "find", "replace", "find-next", "export-html", "copy-md", "print", "focus"] { XCTAssertFalse(enabled(id), id) }
        XCTAssertTrue(enabled("find-folder") && enabled("back") == !ws.visited.isEmpty)
    }

    func testEditPreviewStylesheetMakesTheStarterOnce() throws {
        let ws = makeWorkspace(open: s.url)
        let f = ws.editPreviewStylesheet()
        XCTAssertEqual(f?.standardizedFileURL, s.path(".mdedit/preview.css").standardizedFileURL)
        try s.write(".mdedit/preview.css", "h1{}")
        ws.editPreviewStylesheet()
        XCTAssertEqual(try s.read(".mdedit/preview.css"), "h1{}")
    }

    func testFindFromAPageOpensTheFolderSearch() {
        let ws = makeWorkspace(open: s.url)
        ws.select(s.path("page.html"))
        ws.showFind(.file)
        XCTAssertEqual(ws.find.scope, .folder)
    }

    // MARK: files a page may read

    func testAPageReadsTheFolderAndTheAppsFontsOnly() throws {
        try s.write("Notes/pic.png", "x")
        try FileManager.default.createSymbolicLink(at: s.path("Notes/out.txt"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        let files = PreviewFiles(); files.roots = [s.url]
        XCTAssertNotNil(files.resolve(PreviewPage.url(forFile: s.path("Notes/pic.png"))))
        XCTAssertNil(files.resolve(PreviewPage.url(forFile: URL(fileURLWithPath: "/etc/hosts"))))
        XCTAssertNil(files.resolve(PreviewPage.url(forFile: s.path("Notes/out.txt"))), "a link in the folder that leaves it")
        XCTAssertNil(files.resolve(PreviewPage.url(forFile: s.path("../../../etc/hosts"))), "dots")
        XCTAssertNil(files.resolve(URL(string: "mdedit-file://local/etc/hosts")!))
        XCTAssertNil(files.resolve(URL(string: "mdedit-file://bundle/../Info.plist")!))
        XCTAssertNil(files.resolve(URL(string: "mdedit-file://bundle/Info.plist")!), "only the fonts")
        XCTAssertNotNil(files.resolve(URL(string: "mdedit-file://bundle/Literata.ttf")!), "the fonts the page asks for")
        XCTAssertEqual(PreviewPage.file(from: PreviewPage.url(forFile: s.path("Notes/a b#c.md")))?.lastPathComponent, "a b#c.md", "odd names survive")
        XCTAssertNil(PreviewPage.file(from: URL(string: "https://x.io/a")!))
        XCTAssertNil(PreviewPage.file(from: URL(string: "mdedit-file://elsewhere/a")!))
    }

    // MARK: in a real web view

    private func controller(opened: [URL] = []) -> PreviewController {
        let c = PreviewController(open: { _ in })
        c.webView.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        return c
    }

    private func request(_ md: String, folder: URL? = nil, remote: Bool = false, css: String? = nil) -> PreviewRequest {
        PreviewRequest(source: .markdown(md), title: "N", noteFolder: folder ?? s.path("Notes"), root: s.url, options: options(remote: remote, css: css))
    }

    private func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testMarkdownLoadsItsPicturesStylesAndFontsFromTheFolder() throws {
        try s.write("Notes/pic.png", png())
        try s.write("Notes/sub/deep.png", png())
        let c = controller()
        c.show(request("# Title\n\n![a](pic.png)\n\n![b](sub/deep.png)\n\n![c](../../../../etc/hosts.png)"))
        waitFor(c.loads >= 1, "page")
        waitFor((pageJS(c, "[...document.images].map(i => i.complete ? i.naturalWidth : -1).join(',')") as? String) == "3,3,0", "pictures: inside the folder load, outside does not")
        XCTAssertEqual(pageJS(c, "getComputedStyle(document.querySelector('h1')).fontSize") as? String, "34px")
        XCTAssertEqual(pageJS(c, "document.querySelector('main').getBoundingClientRect().width") as? Double, 648)
    }

    func testRelativeLinksResolveAgainstTheNotesFolder() throws {
        let c = controller()
        c.show(request("[x](sub/other.md) [y](../Two.md) [[Goals]]"))
        waitFor(c.loads >= 1, "page")
        let hrefs = pageJS(c, "[...document.querySelectorAll('a')].map(a => a.href).join(' ')") as? String ?? ""
        XCTAssertTrue(hrefs.contains("mdedit-file://local" + s.path("Notes/sub/other.md").path), hrefs)
        XCTAssertTrue(hrefs.contains("mdedit-file://local" + s.path("Two.md").path), hrefs)
        XCTAssertTrue(hrefs.contains("mdedit://wiki/Goals"), hrefs)
    }

    func testScriptsInAPageNeverRun() throws {
        try s.write("evil.html", "<title>before</title><script>document.title = 'ran'</script><body onload=\"document.title='onload'\"><img src=x onerror=\"document.title='onerror'\"><p id=p>text</p></body>")
        let c = controller()
        c.show(PreviewRequest(source: .html(s.path("evil.html"), text: ""), title: "", noteFolder: s.url, root: s.url, options: options()))
        waitFor(c.loads >= 1, "page")
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(pageJS(c, "document.title") as? String, "before")
        XCTAssertEqual(pageJS(c, "document.getElementById('p').textContent") as? String, "text", "the page itself is shown")
    }

    func testAPageCanUseItsOwnRelativeStylesheetsAndPictures() throws {
        try s.write("site/style.css", "p { color: rgb(1, 2, 3) }")
        try s.write("site/pic.png", png())
        try s.write("site/index.html", "<link rel=stylesheet href=style.css><p>x</p><img src=pic.png>")
        let c = controller()
        c.show(PreviewRequest(source: .html(s.path("site/index.html"), text: "a"), title: "", noteFolder: s.path("site"), root: s.url, options: options()))
        waitFor(c.loads >= 1, "page")
        waitFor((pageJS(c, "getComputedStyle(document.querySelector('p')).color") as? String) == "rgb(1, 2, 3)", "stylesheet")
        waitFor((pageJS(c, "document.images[0].naturalWidth") as? Int) == 3, "picture")
    }

    func testAPageCannotReadOutsideTheOpenedFolder() throws {
        try s.write("site/index.html", "<img src=\"../../outside.png\"><img src=\"/etc/hosts\"><p>x</p>")
        let c = controller()
        c.show(PreviewRequest(source: .html(s.path("site/index.html"), text: "b"), title: "", noteFolder: s.path("site"), root: s.path("site"), options: options()))
        waitFor(c.loads >= 1, "page")
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(pageJS(c, "[...document.images].map(i => i.naturalWidth).join(',')") as? String, "0,0")
    }

    func testCustomCSSStylesTheNote() throws {
        let c = controller()
        c.show(request("# T", css: "h1 { color: rgb(9, 8, 7); letter-spacing: 3px }"))
        waitFor(c.loads >= 1, "page")
        XCTAssertEqual(pageJS(c, "getComputedStyle(document.querySelector('h1')).color") as? String, "rgb(9, 8, 7)")
    }

    func testEditingTheTextReloadsAndKeepsTheScrollPosition() throws {
        let long = (1...200).map { "Paragraph \($0)\n" }.joined(separator: "\n")
        let c = controller()
        c.show(request(long))
        waitFor(c.loads >= 1, "page")
        _ = pageJS(c, "window.scrollTo(0, 900)")
        waitFor((pageJS(c, "window.scrollY") as? Double ?? 0) > 800, "scrolled")
        c.show(request(long + "\nmore"))
        waitFor(c.loads >= 2, "reload")
        waitFor((pageJS(c, "window.scrollY") as? Double ?? 0) > 800, "the reader's place is kept")
        c.show(PreviewRequest(source: .markdown("short"), title: "Another", noteFolder: s.url, root: s.url, options: options()))
        waitFor(c.loads >= 3, "another note")
        XCTAssertEqual(pageJS(c, "window.scrollY") as? Double, 0)
    }

    func testNothingReloadsWhenNothingChanged() {
        let c = controller()
        c.show(request("same")); waitFor(c.loads >= 1, "page")
        c.show(request("same"))
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(c.loads, 1)
    }

    // clicks: WebKit asks the delegate; a fake action stands in for the pointer
    private final class Action: WKNavigationAction {
        let req: URLRequest, kind: WKNavigationType
        init(_ url: URL, _ kind: WKNavigationType) { req = URLRequest(url: url); self.kind = kind }
        override var request: URLRequest { req }
        override var navigationType: WKNavigationType { kind }
        override var targetFrame: WKFrameInfo? { nil }
    }

    private func decide(_ c: PreviewController, _ url: String, _ kind: WKNavigationType) -> WKNavigationActionPolicy {
        var result: WKNavigationActionPolicy?
        c.webView(c.webView, decidePolicyFor: Action(URL(string: url)!, kind), preferences: WKWebpagePreferences()) { p, prefs in
            result = p
            XCTAssertFalse(prefs.allowsContentJavaScript)
        }
        return result ?? .allow
    }

    func testAClickOpensThroughTheAppAndTheViewNeverNavigates() throws {
        var opened: [URL] = []
        let c = PreviewController(open: { opened.append($0) })
        c.show(request("x")); waitFor(c.loads >= 1, "page")
        XCTAssertEqual(decide(c, "https://example.com/a", .linkActivated), .cancel)
        XCTAssertEqual(decide(c, "mdedit-file://local" + s.path("Two.md").path, .linkActivated), .cancel)
        XCTAssertEqual(decide(c, "mdedit://wiki/Goals", .linkActivated), .cancel)
        XCTAssertEqual(opened, [URL(string: "https://example.com/a")!, s.path("Two.md"), URL(string: "mdedit://wiki/Goals")!])
        XCTAssertEqual(decide(c, "https://example.com/refresh", .other), .cancel, "meta refresh and scripts' navigations")
        XCTAssertEqual(decide(c, "https://example.com/form", .formSubmitted), .cancel)
        XCTAssertEqual(decide(c, "https://example.com/r", .reload), .cancel)
        XCTAssertEqual(opened.count, 3, "only clicks reach the app")
    }

    func testTheSameKeyDoesNotLetALoadSlipThrough() {
        let c = controller()
        c.show(request("a")); waitFor(c.loads >= 1, "first")
        XCTAssertEqual(decide(c, "https://evil.example/", .other), .cancel, "after the page is up, nothing else loads on its own")
    }

    func testTheContentRulesBlockTheWeb() throws {
        var rules: WKContentRuleList?, done = false
        PreviewRules.shared.whenReady { rules = PreviewRules.shared.list; done = true }
        waitFor(done, "rules")
        XCTAssertNotNil(rules, "the block list compiles")
        XCTAssertTrue(PreviewRules.noRemoteJSON.contains("^https?://") && PreviewRules.noRemoteJSON.contains("\"block\""))
    }

    func testPageLoadsEvenWhenRemoteContentIsAllowed() {
        let c = controller()
        c.show(request("# T ![x](https://127.0.0.1:9/never.png)", remote: true)); waitFor(c.loads >= 1, "page")
        XCTAssertEqual(pageJS(c, "document.querySelector('h1') !== null") as? Bool, true)
    }
}

/// HTML comments in a note are for the writer; the preview leaves them out.
final class HTMLCommentTests: XCTestCase {
    private func html(_ md: String) -> String { PreviewPage.body(markdown: md) }

    func testACommentOnItsOwnLineIsNotShown() {
        let h = html("Before\n\n<!-- a note to self -->\n\nAfter")
        XCTAssertFalse(h.contains("note to self")); XCTAssertFalse(h.contains("&lt;!--")); XCTAssertFalse(h.contains("<pre>"))
        XCTAssertTrue(h.contains("Before") && h.contains("After"))
    }

    func testAMultiLineAndAnUnclosedCommentAreNotShown() {
        XCTAssertFalse(html("<!--\nline one\nline two\n-->\n\nText").contains("line one"))
        let h = html("Text\n\n<!-- never closed\n\nstill hidden")
        XCTAssertFalse(h.contains("never closed")); XCTAssertTrue(h.contains("Text"))
    }

    func testACommentInsideAParagraphLeavesTheTextAlone() {
        let h = html("one <!-- hidden --> two")
        XCTAssertFalse(h.contains("hidden")); XCTAssertTrue(h.contains("one") && h.contains("two"))
    }

    func testOtherRawHTMLIsStillShownAsCode() {
        let h = html("<div>hello</div>\n\n<!-- gone -->")
        XCTAssertTrue(h.contains("&lt;div&gt;")); XCTAssertFalse(h.contains("gone"))
    }
}
