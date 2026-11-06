import XCTest
@testable import MDEdit

/// A template through a real `Workspace`: it opens in the editor, the preview renders it, and a rendered page opens in the preview again.
@MainActor
final class TemplateRenderTests: XCTestCase {
    var s: Scratch!
    var ws: Workspace!
    let template = #"<h1>J</h1>{% files "journal" as items %}{% for f in items %}<p>{{ f.title }}</p>{% endfor %}"#

    override func setUpWithError() throws {
        s = try Scratch(["journal/a.md": "# Alpha\n\n## Summary\n\n[site](https://example.com/?q=secret)\n", "journal/b.md": "# Beta", "Sub/t.html": template, "other.md": "# Other",
                         "plain.html": "<p>hello</p>", "data.json": #"{"b":1,"a":[1,2]}"#, "conf.yaml": "name: x\nlist:\n  - a\n"])
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

    /// Presses the preview button.
    private func preview() { ws.mode = .view }

    private func reopen(_ name: String) {
        ws.select(s.path("other.md"))
        ws.select(s.path(name))
    }

    // MARK: the editor and the preview

    func testATemplateOpensInTheEditorAndThePreviewRendersIt() {
        XCTAssertEqual(ws.mode, .write, "the source is shown as code")
        XCTAssertEqual(ws.templateState, .needsRender)
        let asked = answering()
        preview(); waitForRender()
        XCTAssertEqual(ws.mode, .view)
        guard case .rendered(let html) = ws.templateState else { return XCTFail("\(ws.templateState)") }
        XCTAssertTrue(html.contains("<p>Alpha</p>") && html.contains("<p>Beta</p>"), html)
        XCTAssertEqual(asked.calls.count, 1)
        XCTAssertNil(asked.calls[0].text, "no template text on the sheet: just the warning")
        XCTAssertEqual(asked.calls[0].title, "Render this page?"); XCTAssertEqual(asked.calls[0].button, "Render"); XCTAssertFalse(asked.calls[0].cancelDefault)
        XCTAssertEqual(asked.calls[0].detail, Workspace.trustSentence)
    }

    func testTheWarningIsAskedOnceAndBackToWritingForgetsTheRender() {
        let asked = answering()
        preview(); waitForRender()
        ws.mode = .write
        XCTAssertEqual(ws.templateState, .needsRender)
        preview(); waitForRender()
        XCTAssertEqual(asked.calls.count, 1, "after the first time Preview just renders")
        if case .rendered = ws.templateState {} else { XCTFail("\(ws.templateState)") }
    }

    func testDecliningTheWarningStaysInTheEditorWritesNothingAndAsksAgainNextTime() {
        let asked = answering(false)
        let before = T.fingerprint(s)
        preview()
        XCTAssertEqual(ws.mode, .write); XCTAssertEqual(ws.templateState, .needsRender)
        XCTAssertEqual(T.fingerprint(s), before, "nothing is written into the folder")
        XCTAssertFalse(ws.renderBusy)
        XCTAssertFalse(TemplateTrust.hasBeenWarned(defaults: ws.defaults))
        asked.answer = true
        preview(); waitForRender()
        XCTAssertEqual(asked.calls.count, 2)
        XCTAssertTrue(TemplateTrust.hasBeenWarned(defaults: ws.defaults))
    }

    func testASyntaxErrorAsksNothingAndShowsTheError() throws {
        try s.write("Sub/bad.html", "{% nonsense %}")
        ws.reload(); ws.select(s.path("Sub/bad.html"))
        let asked = answering()
        preview()
        XCTAssertEqual(asked.calls.count, 0, "the template is parsed before anyone is asked")
        guard case .failed(.syntax) = ws.templateState else { return XCTFail("\(ws.templateState)") }
        XCTAssertEqual(ws.mode, .view, "the preview shows the error page")
    }

    func testThePreviewRendersWhatTheEditorShowsNotTheOldFile() throws {
        _ = answering()
        ws.document.text = template + "<p>EDITED</p>"
        preview(); waitForRender()
        guard case .rendered(let html) = ws.templateState else { return XCTFail("\(ws.templateState)") }
        XCTAssertTrue(html.contains("EDITED"), "the buffer is saved first and rendered")
        XCTAssertTrue(try s.read("Sub/t.html").contains("EDITED"), "and the file now holds it")
    }

    // MARK: opening again

    func testARenderedPageThatHasNotChangedOpensInThePreviewAndRendersByItself() {
        let asked = answering()
        preview(); waitForRender()
        reopen("Sub/t.html")
        XCTAssertEqual(ws.mode, .view, "it was previewed before and has not changed")
        waitFor(ws.templateState != .rendering, "the render")
        if case .rendered(let html) = ws.templateState { XCTAssertTrue(html.contains("<p>Alpha</p>")) } else { XCTFail("\(ws.templateState)") }
        XCTAssertEqual(asked.calls.count, 1, "no sheet: the person already said yes")
    }

    func testAnEditedPageOpensInTheEditor() throws {
        _ = answering()
        preview(); waitForRender()
        ws.select(s.path("other.md"))
        try s.write("Sub/t.html", template + "<!-- edited -->")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(30)], ofItemAtPath: s.path("Sub/t.html").path)
        ws.reload()
        ws.select(s.path("Sub/t.html"))
        XCTAssertEqual(ws.mode, .write, "the text changed since it was previewed")
        preview(); waitForRender()
        reopen("Sub/t.html")
        XCTAssertEqual(ws.mode, .view, "the edited text, once previewed, opens in the preview")
        waitForRender()
    }

    func testEditingThePreviewedPageOutsideBringsBackTheEditor() throws {
        _ = answering()
        preview(); waitForRender()
        try s.write("Sub/t.html", template + " ")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: s.path("Sub/t.html").path)
        ws.reload()
        XCTAssertEqual(ws.mode, .write)
        XCTAssertEqual(ws.templateState, .needsRender)
    }

    func testAPageThatWasNeverPreviewedOpensInTheEditorEvenWithTheSameText() throws {
        _ = answering()
        preview(); waitForRender()
        ws.select(s.path("other.md"))
        try s.write("Sub/new.html", template)
        ws.reload(); ws.select(s.path("Sub/new.html"))
        XCTAssertEqual(ws.mode, .write)
    }

    func testTheRecordIsPerFolder() throws {
        _ = answering()
        preview(); waitForRender()
        let other = try Scratch(["Sub/t.html": template, "journal/x.md": "# X"]); defer { other.remove() }
        let ws2 = makeWorkspace(open: other.url)
        ws2.defaults.set(true, forKey: TemplateTrust.key)
        ws2.select(other.path("Sub/t.html"))
        XCTAssertEqual(ws2.mode, .write)
        XCTAssertFalse(TemplateTrust.wasRendered("Sub/t.html", text: template, root: other.url, defaults: ws.defaults))
        XCTAssertTrue(TemplateTrust.wasRendered("Sub/t.html", text: template, root: s.url, defaults: ws.defaults))
    }

    func testSavingOrEditingOtherFilesNeverStartsARender() throws {
        _ = answering()
        try s.write("other.md", "# Changed"); ws.reload()
        try s.write("journal/c.md", "# C"); ws.reload()
        XCTAssertEqual(ws.mode, .write); XCTAssertEqual(ws.templateState, .needsRender); XCTAssertFalse(ws.renderBusy)
    }

    func testTheNextNoteGetsItsModeBack() {
        ws.select(s.path("other.md"))
        XCTAssertEqual(ws.mode, .write)
        ws.mode = .view
        ws.select(s.path("Sub/t.html"))
        XCTAssertEqual(ws.mode, .write, "a template opens in the editor")
        ws.select(s.path("other.md"))
        XCTAssertEqual(ws.mode, .view, "the note is back in the mode it was in")
    }

    // MARK: other code files

    func testAPlainHTMLFileOpensInTheEditorAndIsRememberedWhenPreviewed() {
        ws.select(s.path("plain.html"))
        XCTAssertEqual(ws.mode, .write); XCTAssertEqual(ws.templateState, .notTemplate)
        XCTAssertEqual(ws.codeKind, .html)
        preview()
        XCTAssertEqual(ws.mode, .view); XCTAssertEqual(ws.templateState, .notTemplate, "no render and no warning for a page without tags")
        reopen("plain.html")
        XCTAssertEqual(ws.mode, .view)
        ws.document.text = "<p>changed</p>"
        ws.document.saveNow()
        reopen("plain.html")
        XCTAssertEqual(ws.mode, .write)
    }

    func testJSONAndYAMLOpenInTheEditorAndAreRememberedWhenPreviewed() {
        for (name, kind) in [("data.json", CodeKind.json), ("conf.yaml", .yaml)] {
            ws.select(s.path(name))
            XCTAssertEqual(ws.codeKind, kind); XCTAssertEqual(ws.mode, .write, name)
            preview()
            reopen(name)
            XCTAssertEqual(ws.mode, .view, "\(name) was previewed and has not changed")
        }
    }

    func testCodeFilesCanBeEditedAndSaved() throws {
        ws.select(s.path("data.json"))
        ws.document.text = #"{"changed": true}"#
        ws.document.saveNow()
        XCTAssertEqual(try s.read("data.json"), #"{"changed": true}"#)
        XCTAssertTrue(ws.isCodeFile)
        XCTAssertEqual(ws.backlinks.count, 0)
    }

    // MARK: lifecycle

    func testASecondPreviewDoesNotStartWhileOneRunsAndCancelGoesBackToTheEditor() {
        let asked = answering()
        ws.templateSource = SlowSource(delay: 0.6)
        preview()
        XCTAssertEqual(ws.templateState, .rendering); XCTAssertTrue(ws.renderBusy)
        let generation = ws.templateGeneration
        XCTAssertFalse(ws.render(), "a second render does not start")
        XCTAssertEqual(ws.templateGeneration, generation)
        XCTAssertEqual(asked.calls.count, 1)
        ws.cancelRender()
        XCTAssertEqual(ws.mode, .write); XCTAssertEqual(ws.templateState, .needsRender)
        waitFor(!ws.renderBusy, "the task returns")
        XCTAssertEqual(ws.templateState, .needsRender, "a late result does not replace the editor")
        preview(); XCTAssertEqual(ws.templateState, .rendering, "Preview works again once the task has returned")
        waitFor(ws.templateState != .rendering, "second render")
    }

    func testChangingTheDocumentDropsTheRunningRenderAndItsLateResult() {
        _ = answering()
        ws.templateSource = SlowSource(delay: 0.5)
        preview()
        XCTAssertEqual(ws.templateState, .rendering)
        ws.select(s.path("other.md"))
        XCTAssertEqual(ws.templateState, .notTemplate)
        waitFor(!ws.renderBusy, "the task returns")
        XCTAssertEqual(ws.templateState, .notTemplate, "the late result is dropped")
    }

    func testABlockedReadGivesATimeoutOnTimeAndKeepsPreviewRefusedUntilItReturns() {
        _ = answering()
        ws.templateLimits.clock = 0.2
        ws.templateSource = SlowSource(delay: 1.0)
        let started = Date()
        preview()
        waitFor(ws.templateState == .failed(.timeout), "the timeout is shown")
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.8, "on time, not when the read returns")
        XCTAssertTrue(ws.renderBusy)
        ws.mode = .write
        XCTAssertEqual(ws.templateState, .needsRender)
        ws.mode = .view
        XCTAssertEqual(ws.mode, .write, "refused while the read is outstanding")
        waitFor(!ws.renderBusy, "the blocked read returns")
        ws.templateSource = nil; ws.templateLimits = .standard
        preview(); waitForRender()
        if case .rendered = ws.templateState {} else { XCTFail("\(ws.templateState)") }
    }

    func testOutputThatCouldOpenAConnectionIsNotShown() throws {
        try s.write("Sub/hint.html", #"{% files "journal" as items %}{% for f in items %}<link rel="preconnect" href="//{{ f.title }}.example">{% endfor %}"#)
        ws.reload(); ws.select(s.path("Sub/hint.html"))
        _ = answering()
        preview(); waitForRender()
        guard case .failed(.unsafe(let tag, _)) = ws.templateState else { return XCTFail("\(ws.templateState)") }
        XCTAssertEqual(tag, "<link>")
    }

    // MARK: links on a rendered page (the template is in Sub/, the links mean the opened folder)

    private func rendered() {
        _ = answering()
        preview(); waitForRender()
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
            XCTAssertLessThan(asked.calls[0].detail.count, 90, "the dialog is kept short")
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
