import XCTest
import WebKit
@testable import MDEdit

/// A rendered template in a real web view: where it is served from, what it may load, and that nothing reaches the network.
@MainActor
final class TemplatePreviewTests: XCTestCase {
    var s: Scratch!
    var server: LocalHTTPServer!

    override func setUpWithError() throws {
        s = try Scratch(["Sub/placeholder.md": "x", "style.css": "p { color: rgb(255, 0, 0); }"])
        try s.write("pic.png", png()); try s.write("Sub/inner.png", png()); try s.write(".mdedit/hidden.png", png())
        let out = try Scratch(["out.png": png()])
        try FileManager.default.createSymbolicLink(at: s.path("outside.png"), withDestinationURL: out.path("out.png"))
        try FileManager.default.createSymbolicLink(at: s.path("visible.png"), withDestinationURL: s.path(".mdedit/hidden.png"))
        server = try LocalHTTPServer()
        addTeardownBlock { [s, server] in s?.remove(); out.remove(); server?.stop() }
    }

    private func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func options(remote: Bool) -> PreviewPage.Options { .init(style: ViewerStyle(family: "Inter"), loadRemote: remote, customCSS: nil) }

    private func controller() -> PreviewController {
        let c = PreviewController(open: { _ in })
        c.webView.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        return c
    }

    private func template(_ html: String, folder: URL? = nil, remote: Bool = true) -> PreviewRequest {
        PreviewRequest(source: .template(rendered: html), title: "", noteFolder: folder ?? s.url, root: s.url, options: options(remote: remote))
    }

    private func text(_ c: PreviewController) -> String { (pageJS(c, "document.body ? document.body.innerText : ''") as? String) ?? "" }

    // MARK: served from memory

    func testTheRenderedPageIsAnsweredFromMemoryWithTheTemplateHeader() throws {
        let files = PreviewFiles()
        let url = PreviewPage.templateAddress(root: s.url)
        files.templatePage = "<p>hi</p>"; files.templateURL = url
        let r = try XCTUnwrap(files.templateResponse(for: url))
        XCTAssertEqual(String(decoding: r.data, as: UTF8.self), "<p>hi</p>")
        XCTAssertEqual(r.headers["Content-Security-Policy"], PreviewPage.csp(loadRemote: false))
        XCTAssertTrue(r.headers["Content-Security-Policy"]!.contains("default-src 'none'"))
        XCTAssertNil(files.templateResponse(for: PreviewPage.url(forFile: s.path("pic.png"))))
        XCTAssertEqual(url.lastPathComponent, ".mdedit-template.html")
        XCTAssertTrue(url.path.hasPrefix(s.url.standardizedFileURL.path), "at the root of the opened folder")
    }

    func testARealFileOfTheSameNameDoesNotShadowIt() throws {
        try s.write(".mdedit-template.html", "<p>REAL FILE</p>")
        let c = controller()
        c.show(template("<p>RENDERED</p>"))
        waitFor(c.loads >= 1, "page")
        XCTAssertTrue(text(c).contains("RENDERED")); XCTAssertFalse(text(c).contains("REAL FILE"))
    }

    // MARK: hidden files

    func testHiddenPartsAreRefusedForTemplatePagesOnly() {
        let files = PreviewFiles(); files.roots = [s.url]
        XCTAssertTrue(files.allows(s.path(".mdedit/hidden.png")), "an ordinary page can still read the folder's hidden files")
        files.refuseHidden = true
        XCTAssertFalse(files.allows(s.path(".mdedit/hidden.png")))
        XCTAssertFalse(files.allows(s.path("visible.png")), "a visible name that links to a hidden file")
        XCTAssertTrue(files.allows(s.path("pic.png")))
        XCTAssertTrue(files.allows(s.path("Sub/inner.png")))
    }

    func testATemplatePageCannotLoadAHiddenPictureButCanLoadItsOwnFolderPictures() {
        let hidden = PreviewPage.url(forFile: s.path(".mdedit/hidden.png")).absoluteString
        let c = controller()
        c.show(template("<img id=a src=\"\(hidden)\"><img id=b src=\"pic.png\"><img id=c src=\"Sub/inner.png\"><img id=d src=\"visible.png\"><img id=e src=\"outside.png\">"))
        waitFor(c.loads >= 1, "page")
        waitFor((pageJS(c, "document.images[1].complete && document.images[2].complete && document.images[0].complete") as? Bool) == true, "images")
        func width(_ i: Int) -> Int { (pageJS(c, "document.images[\(i)].naturalWidth") as? Int) ?? -1 }
        XCTAssertEqual(width(0), 0, "hidden folder")
        XCTAssertGreaterThan(width(1), 0, "a picture in the folder, relative to the folder root")
        XCTAssertGreaterThan(width(2), 0)
        XCTAssertEqual(width(3), 0, "a visible name linking to a hidden file")
        XCTAssertEqual(width(4), 0, "a link out of the folder")
    }

    func testRelativePathsMeanTheOpenedFolderWhateverFolderTheTemplateIsIn() {
        let c = controller()
        c.show(template("<link rel=stylesheet href=\"style.css\"><p id=p>x</p><img src=\"Sub/inner.png\">", folder: s.path("Sub")))
        waitFor(c.loads >= 1, "page")
        waitFor((pageJS(c, "document.images[0].complete") as? Bool) == true, "image")
        XCTAssertGreaterThan((pageJS(c, "document.images[0].naturalWidth") as? Int) ?? 0, 0)
        waitFor((pageJS(c, "getComputedStyle(document.getElementById('p')).color") as? String) == "rgb(255, 0, 0)", "the folder's stylesheet applies")
    }

    // MARK: nothing reaches the network

    private func vectors(_ u: String) -> [(name: String, html: String, control: Bool)] {
        [
            ("img", "<img src=\"\(u)/img.png\">", true),
            ("link stylesheet", "<link rel=stylesheet href=\"\(u)/a.css\">", true),
            ("css @import", "<style>@import url(\"\(u)/b.css\");</style>", true),
            ("css url()", "<div style=\"background-image:url('\(u)/c.png');width:50px;height:50px\">x</div>", true),
            ("iframe", "<iframe src=\"\(u)/f.html\"></iframe>", false),
            ("form action", "<form id=f action=\"\(u)/form\"><input name=a value=b></form>", false),
            ("a ping", "<a id=l href=\"pic.png\" ping=\"\(u)/ping\">x</a>", false),
        ]
    }

    func testEachResourceVectorReachesTheServerWithoutTheLayersAndNotWithThem() throws {
        for v in vectors(server.address) {
            if v.control {
                // the same markup in an ordinary HTML page with remote loads on: the server must see it, or the test proves nothing
                server.reset()
                try s.write("control.html", v.html)
                let c = controller()
                c.show(PreviewRequest(source: .html(s.path("control.html"), text: v.html), title: "", noteFolder: s.url, root: s.url, options: options(remote: true)))
                waitFor(c.loads >= 1, "control page \(v.name)")
                waitFor(server.requestCount > 0, "control \(v.name) reaches the server")
            }
            server.reset()
            let c = controller()
            c.show(template(v.html, remote: true))
            waitFor(c.loads >= 1, "template page \(v.name)")
            _ = pageJS(c, "(function(){var f=document.getElementById('f'); if(f) f.submit(); var l=document.getElementById('l'); if(l) l.click();})()")
            letPageSettle(1.0)
            XCTAssertEqual(server.requestCount, 0, "\(v.name) must not reach the network from a template page")
        }
    }

    /// The header (layer 1) already blocks every vector above, so the rule list (layer 2) is tested on its own, in a bare web view with no
    /// header: without the list the server sees each request, with it the server sees none.
    func testTheTemplateRuleListAloneBlocksEveryRequestType() throws {
        var ready = false
        PreviewRules.template.whenReady { ready = true }
        waitFor(ready, "the template list is compiled")
        let list = try XCTUnwrap(PreviewRules.template.list)
        for v in vectors(server.address) where ["img", "link stylesheet", "css @import", "css url()"].contains(v.name) {   // (a frame loads unreliably in a bare view in a long run; the header and the controller block frames too)
            for withList in [false, true] {
                server.reset()
                let config = WKWebViewConfiguration()
                if withList { config.userContentController.add(list) }
                let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: config)
                web.loadHTMLString(v.html, baseURL: nil)
                if withList { letPageSettle(1.5); XCTAssertEqual(server.requestCount, 0, "\(v.name) with the list") }
                else { waitFor(server.requestCount > 0, "\(v.name) without the list reaches the server (the control)") }
            }
        }
    }

    func testThePageDoesNotLoadBeforeItsRuleListIsReady() {
        let rules = PreviewRules(identifier: "in.ranjeev.mdedit.test-\(UUID().uuidString)", json: PreviewRules.templateJSON)
        let c = controller(); c.templateRules = rules
        c.show(template("<img src=\"\(server.address)/img.png\"><p>PAGE</p>", remote: true))
        XCTAssertEqual(c.loads, 0, "nothing is loaded before the list is compiled")
        XCTAssertFalse(rules.ready)
        waitFor(c.loads >= 1, "page after the list is ready")
        XCTAssertTrue(rules.ready)
        XCTAssertTrue(text(c).contains("PAGE"))
        letPageSettle(1.0)
        XCTAssertEqual(server.requestCount, 0)
    }

    func testACompileFailureShowsAnErrorAndLoadsNothing() {
        let rules = PreviewRules(identifier: "in.ranjeev.mdedit.test-\(UUID().uuidString)", json: "this is not json")
        let c = controller(); c.templateRules = rules
        c.show(template("<img src=\"\(server.address)/img.png\"><p>SECRET PAGE</p>", remote: true))
        waitFor(c.loads >= 1, "error page")
        XCTAssertNil(rules.list)
        let t = text(c)
        XCTAssertTrue(t.contains("Page not shown"), t)
        XCTAssertFalse(t.contains("SECRET PAGE"))
        letPageSettle(1.0)
        XCTAssertEqual(server.requestCount, 0)
    }

    func testTheTemplateRulesAreUsedEvenWhenRemoteLoadsAreOnAndAnOrdinaryPageStillLoads() {
        let c = controller()
        c.show(template("<p id=p>ok</p>", remote: true))
        waitFor(c.loads >= 1, "template page")
        XCTAssertNotNil(PreviewRules.template.list, "the template list is compiled and applied")
        let ordinary = controller()
        ordinary.show(PreviewRequest(source: .markdown("# Hello"), title: "N", noteFolder: s.url, root: s.url, options: options(remote: false)))
        waitFor(ordinary.loads >= 1, "markdown page")
        XCTAssertTrue(text(ordinary).contains("Hello"), "an ordinary page is not affected by the template list")
    }

    // MARK: the error page

    func testTheErrorPageEscapesEverythingDynamic() {
        let p = PreviewPage.errorPage(title: "<script>t</script>", message: "<img src=x onerror=1> & \"q\"", line: 7)
        XCTAssertFalse(p.contains("<script>t"), p)
        XCTAssertFalse(p.contains("<img src=x"), p)
        XCTAssertTrue(p.contains("&lt;script&gt;")); XCTAssertTrue(p.contains("Line 7"))
        XCTAssertFalse(PreviewPage.errorPage(title: "t", message: "m", line: nil).contains("Line"))
        XCTAssertTrue(PreviewPage.errorPage(title: "t", message: "m", line: nil).contains("default-src 'none'"))
    }
}
