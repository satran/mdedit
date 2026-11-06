import XCTest
@testable import MDEdit

/// Rendering through a real `Workspace`: the trust sheet, the lifecycle of a render, and clicks on a rendered page.
@MainActor
final class TemplateRenderTests: XCTestCase {
    var s: Scratch!
    var ws: Workspace!
    let template = #"<h1>J</h1>{% files "journal" as items %}{% for f in items %}<p>{{ f.title }}</p>{% endfor %}"#

    override func setUpWithError() throws {
        s = try Scratch(["journal/a.md": "# Alpha\n\n## Summary\n\n[site](https://example.com/?q=secret)\n", "journal/b.md": "# Beta", "Sub/t.html": template, "other.md": "# Other"])
        ws = makeWorkspace(open: s.url)
        ws.select(s.path("Sub/t.html"))
        addTeardownBlock { self.s.remove() }
    }

    /// Answers the sheets and remembers what they asked.
    private final class Asked { var calls: [(title: String, detail: String, button: String, text: String?, cancelDefault: Bool)] = []; var answer = true }
    private func answering(_ answer: Bool = true) -> Asked {
        let a = Asked(); a.answer = answer
        ws.templateConfirm = { t, d, b, text, cd in a.calls.append((t, d, b, text, cd)); return a.answer }
        return a
    }

    private func waitForRender() { waitFor(ws.templateState != .rendering, "the render ends") }

    // MARK: trust

    func testAPageWithTagsGetsTheBanner() {
        XCTAssertEqual(ws.templateState, .needsRender)
        ws.select(s.path("other.md")); XCTAssertEqual(ws.templateState, .notTemplate)
        ws.select(s.path("Sub/t.html")); XCTAssertEqual(ws.templateState, .needsRender)
    }

    func testASyntaxErrorAsksNothing() throws {
        try s.write("Sub/bad.html", "{% nonsense %}")
        ws.reload(); ws.select(s.path("Sub/bad.html"))
        let asked = answering()
        ws.render()
        XCTAssertEqual(asked.calls.count, 0, "the template is parsed before anyone is asked")
        guard case .failed(.syntax) = ws.templateState else { return XCTFail("\(ws.templateState)") }
    }

    func testTheFirstRenderAsksWithTheWholeTemplateAndIsRemembered() throws {
        let asked = answering()
        ws.render(); waitForRender()
        XCTAssertEqual(asked.calls.count, 1)
        XCTAssertEqual(asked.calls[0].text, template, "the sheet shows the same string that is hashed and run")
        XCTAssertEqual(asked.calls[0].button, "Render"); XCTAssertFalse(asked.calls[0].cancelDefault)
        XCTAssertEqual(asked.calls[0].detail, Workspace.trustSentence)
        guard case .rendered(let html) = ws.templateState else { return XCTFail("\(ws.templateState)") }
        XCTAssertTrue(html.contains("<p>Alpha</p>") && html.contains("<p>Beta</p>"), html)
        ws.showTemplateSource(); XCTAssertEqual(ws.templateState, .needsRender)
        ws.render(); waitForRender()
        XCTAssertEqual(asked.calls.count, 1, "an approved version runs without the sheet")
        if case .rendered = ws.templateState {} else { XCTFail("\(ws.templateState)") }
    }

    func testAnEditAsksAgainAndADeclinedSheetRendersNothingAndWritesNothing() throws {
        let asked = answering()
        ws.render(); waitForRender()
        let edited = template + "<!-- edited -->"
        try s.write("Sub/t.html", edited)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(30)], ofItemAtPath: s.path("Sub/t.html").path)
        ws.reload()
        XCTAssertEqual(ws.templateState, .needsRender, "a changed file returns to the banner")
        asked.answer = false
        let before = T.fingerprint(s)
        ws.render()
        XCTAssertEqual(asked.calls.count, 2); XCTAssertEqual(asked.calls[1].text, edited)
        XCTAssertEqual(ws.templateState, .needsRender, "declined: nothing is rendered")
        XCTAssertEqual(T.fingerprint(s), before, "nothing is written into the folder")
        XCTAssertFalse(ws.renderBusy)
    }

    func testAnotherFolderWithTheSameTemplateAsksAgain() throws {
        let asked = answering()
        ws.render(); waitForRender()
        let other = try Scratch(["Sub/t.html": template, "journal/x.md": "# X"]); defer { other.remove() }
        let ws2 = makeWorkspace(open: other.url); ws2.defaults.setValuesForKeys([:])
        var n = 0
        ws2.templateConfirm = { _, _, _, _, _ in n += 1; return true }
        // the settings of ws and ws2 are separate, so test the key itself: the same text at the same path in another folder
        XCTAssertFalse(TemplateTrust.isApproved("Sub/t.html", text: template, root: other.url, defaults: ws.defaults))
        XCTAssertTrue(TemplateTrust.isApproved("Sub/t.html", text: template, root: s.url, defaults: ws.defaults))
        XCTAssertEqual(asked.calls.count, 1)
    }

    func testSavingOrEditingOtherFilesNeverStartsARender() throws {
        _ = answering()
        try s.write("other.md", "# Changed"); ws.reload()
        try s.write("journal/c.md", "# C"); ws.reload()
        XCTAssertEqual(ws.templateState, .needsRender)
        XCTAssertFalse(ws.renderBusy)
    }

    // MARK: lifecycle

    func testASecondRenderDoesNotStartWhileOneRunsAndCancelShowsThePlainFile() {
        let asked = answering()
        ws.templateSource = SlowSource(delay: 0.6)
        ws.render()
        XCTAssertEqual(ws.templateState, .rendering); XCTAssertTrue(ws.renderBusy)
        let generation = ws.templateGeneration
        ws.render()
        XCTAssertEqual(ws.templateGeneration, generation, "a second Render does not start")
        XCTAssertEqual(asked.calls.count, 1)
        ws.cancelRender()
        XCTAssertEqual(ws.templateState, .cancelled)
        waitFor(!ws.renderBusy, "the task returns")
        XCTAssertEqual(ws.templateState, .cancelled, "a late result does not replace the cancel")
        ws.render(); XCTAssertEqual(ws.templateState, .rendering, "Render works again once the task has returned")
        waitFor(ws.templateState != .rendering, "second render")
    }

    func testChangingTheDocumentDropsTheRunningRenderAndItsLateResult() {
        _ = answering()
        ws.templateSource = SlowSource(delay: 0.5)
        ws.render()
        XCTAssertEqual(ws.templateState, .rendering)
        ws.select(s.path("other.md"))
        XCTAssertEqual(ws.templateState, .notTemplate)
        waitFor(!ws.renderBusy, "the task returns")
        XCTAssertEqual(ws.templateState, .notTemplate, "the late result is dropped")
    }

    func testABlockedReadGivesATimeoutOnTimeAndKeepsRenderDisabledUntilItReturns() {
        _ = answering()
        ws.templateLimits.clock = 0.2
        ws.templateSource = SlowSource(delay: 1.0)
        let started = Date()
        ws.render()
        waitFor(ws.templateState == .failed(.timeout), "the timeout is shown")
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.8, "on time, not when the read returns")
        XCTAssertTrue(ws.renderBusy)
        ws.showTemplateSource()
        XCTAssertEqual(ws.templateState, .needsRender)
        let generation = ws.templateGeneration
        ws.render()
        XCTAssertEqual(ws.templateGeneration, generation); XCTAssertEqual(ws.templateState, .needsRender, "Render is refused while the read is outstanding")
        waitFor(!ws.renderBusy, "the blocked read returns")
        ws.templateSource = nil; ws.templateLimits = .standard
        ws.render(); waitForRender()
        if case .rendered = ws.templateState {} else { XCTFail("\(ws.templateState)") }
    }

    func testOutputThatCouldOpenAConnectionIsNotShown() throws {
        try s.write("Sub/hint.html", #"{% files "journal" as items %}{% for f in items %}<link rel="preconnect" href="//{{ f.title }}.example">{% endfor %}"#)
        ws.reload(); ws.select(s.path("Sub/hint.html"))
        _ = answering()
        ws.render(); waitForRender()
        guard case .failed(.unsafe(let tag, _)) = ws.templateState else { return XCTFail("\(ws.templateState)") }
        XCTAssertEqual(tag, "<link>")
    }

    // MARK: links on a rendered page (the template is in Sub/, the links mean the opened folder)

    private func rendered() {
        _ = answering()
        ws.render(); waitForRender()
        if case .rendered = ws.templateState {} else { XCTFail("\(ws.templateState)") }
    }

    func testALinkToANoteMeansTheOpenedFolder() {
        rendered()
        // a relative link `journal/a.md` in a page served at the folder root reaches the policy as this file address
        ws.openTemplateLink(s.path("journal/a.md"))
        XCTAssertEqual(ws.document.url?.standardizedFileURL, s.path("journal/a.md").standardizedFileURL)
    }

    func testWebAndMailLinksAskFirstWithTheWholeAddress() {
        rendered()
        var opened: [URL] = []
        ws.openAddress = { opened.append($0) }
        let cases = ["https://example.com/a?q=note+text", "http://example.com/", "mailto:x@example.com?body=note%20text"]
        for c in cases {
            let asked = answering(false)
            ws.openTemplateLink(URL(string: c)!)
            XCTAssertEqual(asked.calls.count, 1, c)
            XCTAssertEqual(asked.calls[0].title, "Open this address?")
            XCTAssertEqual(asked.calls[0].button, "Open")
            XCTAssertTrue(asked.calls[0].cancelDefault, "Cancel is the default")
            let shown = asked.calls[0].text ?? ""
            XCTAssertEqual(shown.replacingOccurrences(of: "\n", with: ""), c, "the whole address")
            if c.contains("?") { XCTAssertTrue(shown.contains("\n?"), "the query is on its own line") }
            if c.hasPrefix("mailto") { XCTAssertTrue(asked.calls[0].detail.contains("mail program")) }
            XCTAssertTrue(opened.isEmpty, "Cancel opens nothing")
        }
        let yes = answering(true)
        ws.openTemplateLink(URL(string: cases[0])!)
        XCTAssertEqual(opened, [URL(string: cases[0])!], "calls=\(yes.calls.count) answer=\(yes.answer)"); XCTAssertEqual(yes.calls.count, 1)
    }

    func testNoOtherSchemeReachesTheSystem() {
        rendered()
        var opened: [URL] = []
        ws.openAddress = { opened.append($0) }
        let asked = answering(true)
        for c in ["javascript:alert(1)", "data:text/html,x", "ftp://example.com/x", "file:///etc/hosts", "x-apple.systempreferences:", "tel:123", "../../outside.md"] {
            ws.openTemplateLink(URL(string: c)!)
        }
        XCTAssertTrue(opened.isEmpty); XCTAssertEqual(asked.calls.count, 0)
    }

    func testALinkFromMarkdownOutputBehavesTheSame() throws {
        try s.write("Sub/md.html", #"{% section "journal/a.md" "Summary" as t %}{{ t|markdown }}"#)
        ws.reload(); ws.select(s.path("Sub/md.html"))
        _ = answering()
        ws.render(); waitForRender()
        guard case .rendered(let html) = ws.templateState, let r = html.range(of: #"href="[^"]+""#, options: .regularExpression) else { return XCTFail("\(ws.templateState)") }
        let href = String(html[r].dropFirst(6).dropLast()).replacingOccurrences(of: "&amp;", with: "&")
        var opened: [URL] = []
        ws.openAddress = { opened.append($0) }
        let asked = answering(false)
        ws.openTemplateLink(URL(string: href)!)
        XCTAssertEqual(asked.calls.count, 1, href); XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue((asked.calls.first?.text ?? "").contains("example.com"))
    }
}
