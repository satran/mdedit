import XCTest
@testable import MDEdit

/// Query links, trusted addresses and the render tool for agents.
@MainActor
final class TemplateRequestsTests: XCTestCase {
    var s: Scratch!
    var ws: Workspace!
    var windows: AgentWindows!
    var tools: AgentTools!
    let page = #"<p id="v">[{{ query.due|default:"all" }}][{{ query.priority|default:"-" }}]</p><a href="?due=overdue&priority=A">x</a>"#

    override func setUpWithError() throws {
        s = try Scratch(["t.html": page, "bad.html": "{% nonsense %}", "n.md": "# N", "sub/deep.html": "{{ today }}"])
        ws = makeWorkspace(open: s.url)
        ws.select(s.path("t.html"))
        windows = AgentWindows(); windows.register(ws)
        tools = AgentTools(windows: windows)
        addTeardownBlock { self.s.remove() }
    }

    private func renderNow() {
        ws.templateConfirm = { _, _, _, _, _ in true }
        ws.mode = .view
        waitFor(ws.templateState != .rendering, "the render ends")
    }

    private func html() -> String { if case .rendered(let h) = ws.templateState { return h }; XCTFail("\(ws.templateState)"); return "" }

    // MARK: query

    func testALinkWithAQueryRendersThePageAgainWithTheParameters() {
        renderNow()
        XCTAssertTrue(html().contains("[all][-]"))
        let address = PreviewPage.templateAddress(root: s.url)
        ws.openTemplateLink(URL(string: address.absoluteString + "?due=overdue&priority=A")!)
        waitFor(ws.templateState != .rendering && ws.templateState != .needsRender, "the new render")
        XCTAssertTrue(html().contains("[overdue][A]"), html())
        ws.openTemplateLink(URL(string: address.absoluteString + "?priority=B")!)
        waitFor(ws.templateState != .rendering && ws.templateState != .needsRender, "the next render")
        XCTAssertTrue(html().contains("[all][B]"), "each click sets all the parameters: \(html())")
        ws.openTemplateLink(URL(string: address.absoluteString)!)
        waitFor(ws.templateState != .rendering && ws.templateState != .needsRender, "the render without a query")
        XCTAssertTrue(html().contains("[all][-]"))
    }

    func testAQueryNeverAsksAndNeverOpensAnything() {
        renderNow()
        var asked = 0; var opened: [URL] = []
        ws.templateConfirm = { _, _, _, _, _ in asked += 1; return true }
        ws.openAddress = { opened.append($0) }
        ws.openTemplateLink(URL(string: PreviewPage.templateAddress(root: s.url).absoluteString + "?due=x")!)
        waitFor(ws.templateState != .rendering && ws.templateState != .needsRender, "the render")
        XCTAssertEqual(asked, 0); XCTAssertTrue(opened.isEmpty)
    }

    func testQueryParametersAreSanitisedAndBounded() {
        let u = URL(string: "mdedit-file://local/x?a=1&_b=2&9x=no&c-d=no&e=%3Cscript%3E&" + (0..<30).map { "k\($0)=v" }.joined(separator: "&") + "&long=" + String(repeating: "y", count: 400))!
        let q = Workspace.queryParameters(u)
        XCTAssertEqual(q["a"], "1"); XCTAssertEqual(q["_b"], "2"); XCTAssertEqual(q["e"], "<script>")
        XCTAssertNil(q["9x"]); XCTAssertNil(q["c-d"])
        XCTAssertEqual(q.count, 20, "at most 20 keys")
        let long = Workspace.queryParameters(URL(string: "mdedit-file://local/x?long=" + String(repeating: "y", count: 400))!)
        XCTAssertEqual(long["long"]?.count, 256)
        XCTAssertEqual(Workspace.queryParameters("due=overdue&priority=A"), ["due": "overdue", "priority": "A"])
    }

    func testTheQueryIsForgottenWithTheDocumentAndShowSource() {
        renderNow()
        ws.openTemplateLink(URL(string: PreviewPage.templateAddress(root: s.url).absoluteString + "?due=x")!)
        waitFor(ws.templateState != .rendering && ws.templateState != .needsRender, "render")
        XCTAssertEqual(ws.templateQuery["due"], "x")
        ws.showTemplateSource()
        XCTAssertTrue(ws.templateQuery.isEmpty)
        ws.render(); waitFor(ws.templateState != .rendering, "render")
        XCTAssertTrue(html().contains("[all][-]"))
    }

    func testALinkToAnotherNoteIsNotAQuery() {
        renderNow()
        ws.openTemplateLink(s.path("n.md"))
        XCTAssertEqual(ws.document.url?.lastPathComponent, "n.md")
    }

    // MARK: trusted addresses

    func testTrustedHostsAreNormalisedAndMatchedExactly() {
        let d = isolatedDefaults()
        TemplateTrust.setTrustedHosts(["  Mail.Google.com ", "*.atlassian.net", "evil", "a b.com", "https://x.com", "x.com/path", "", "mail.google.com", "xn--e1afmkfd.xn--p1ai", "-.com"], root: s.url, defaults: d)
        XCTAssertEqual(TemplateTrust.trustedHosts(root: s.url, defaults: d), ["mail.google.com", "*.atlassian.net", "xn--e1afmkfd.xn--p1ai"])
        func trusted(_ u: String) -> Bool { TemplateTrust.isTrusted(URL(string: u)!, root: s.url, defaults: d) }
        XCTAssertTrue(trusted("https://mail.google.com/mail/u/0/?q=1"))
        XCTAssertTrue(trusted("https://MAIL.google.com"))
        XCTAssertTrue(trusted("https://acme.atlassian.net/browse/X-1"))
        XCTAssertTrue(trusted("https://a.b.atlassian.net/"))
        XCTAssertFalse(trusted("https://atlassian.net/"), "*.x is the hosts below x, not x")
        XCTAssertFalse(trusted("https://evilatlassian.net/"), "a longer name that ends the same")
        XCTAssertFalse(trusted("https://atlassian.net.evil.com/"))
        XCTAssertFalse(trusted("https://mail.google.com.evil.com/"))
        XCTAssertFalse(trusted("http://mail.google.com/"), "https only")
        XCTAssertFalse(trusted("mailto:a@mail.google.com"))
        XCTAssertFalse(trusted("https://user@mail.google.com/"), "a user name can hide the real host")
        XCTAssertFalse(trusted("https://mail.google.com:8443/"))
        XCTAssertTrue(trusted("https://mail.google.com:443/"))
        XCTAssertFalse(trusted("https://mаil.google.com/"), "a look-alike (Cyrillic а)")
        XCTAssertFalse(trusted("ftp://mail.google.com/"))
    }

    func testTrustedHostsBelongToTheFolderAndTheAppSettingsAndAreCapped() throws {
        let d = isolatedDefaults()
        TemplateTrust.setTrustedHosts(["a.com"], root: s.url, defaults: d)
        let other = try Scratch(); defer { other.remove() }
        XCTAssertFalse(TemplateTrust.isTrusted(URL(string: "https://a.com")!, root: other.url, defaults: d), "another folder does not trust it")
        XCTAssertTrue(TemplateTrust.isTrusted(URL(string: "https://a.com")!, root: s.url, defaults: d))
        XCTAssertEqual(TemplateTrust.normalized((0..<80).map { "h\($0).com" }).count, 50)
        TemplateTrust.setTrustedHosts([], root: s.url, defaults: d)
        XCTAssertTrue(TemplateTrust.trustedHosts(root: s.url, defaults: d).isEmpty)
        XCTAssertNil(try? FileManager.default.contentsOfDirectory(atPath: s.path(".mdedit").path), "nothing is stored in the folder")
    }

    func testATrustedAddressOpensWithoutAskingAndOthersStillAsk() {
        renderNow()
        TemplateTrust.setTrustedHosts(["mail.google.com"], root: s.url, defaults: ws.defaults)
        var opened: [URL] = []; var asked = 0
        ws.openAddress = { opened.append($0) }
        ws.templateConfirm = { _, _, _, _, _ in asked += 1; return false }
        ws.openTemplateLink(URL(string: "https://mail.google.com/mail/?q=x")!)
        XCTAssertEqual(opened.count, 1); XCTAssertEqual(asked, 0)
        ws.openTemplateLink(URL(string: "https://example.com/?q=x")!)
        XCTAssertEqual(opened.count, 1); XCTAssertEqual(asked, 1, "a host that is not listed still asks")
        ws.openTemplateLink(URL(string: "http://mail.google.com/")!)
        XCTAssertEqual(asked, 2)
        ws.openTemplateLink(URL(string: "mailto:a@b.c")!)
        XCTAssertEqual(asked, 3)
    }

    func testTheCommandEditsOnlyThisFoldersList() {
        var shown: [String] = []
        ws.editTrustedHosts = { shown.append($0); return "mail.google.com\n*.atlassian.net\nbad host\n" }
        ws.editTrustedAddresses()
        XCTAssertEqual(shown, [""])
        XCTAssertEqual(TemplateTrust.trustedHosts(root: s.url, defaults: ws.defaults), ["mail.google.com", "*.atlassian.net"])
        ws.editTrustedHosts = { shown.append($0); return nil }
        ws.editTrustedAddresses()
        XCTAssertEqual(shown.last, "mail.google.com\n*.atlassian.net")
        XCTAssertEqual(TemplateTrust.trustedHosts(root: s.url, defaults: ws.defaults).count, 2, "Cancel changes nothing")
        let cmds = makeCommands(ws: ws, prefs: Preferences(), recents: RecentFolders(), newWindow: { _ in })
        XCTAssertTrue(cmds.contains { $0.title == "Trusted Addresses for Templates…" && $0.enabled })
    }

    // MARK: the render tool

    private func render(_ args: [String: Any]) async -> (json: [String: Any], isError: Bool) {
        let r = await tools.callAsync(AgentToolCall(name: "render_template", arguments: args, client: "test"))
        return ((try? JSONSerialization.jsonObject(with: Data(r.json.utf8))) as? [String: Any] ?? [:], r.isError)
    }

    func testTheToolRendersATemplateLikeTheButton() async {
        let r = await render(["path": "t.html", "query": "due=overdue&priority=A"])
        XCTAssertFalse(r.isError)
        XCTAssertEqual(r.json["ok"] as? Bool, true)
        XCTAssertTrue((r.json["html"] as? String)?.contains("[overdue][A]") == true, "\(r.json)")
        XCTAssertEqual(r.json["path"] as? String, "t.html")
        let plain = await render(["path": "t.html"])
        XCTAssertTrue((plain.json["html"] as? String)?.contains("[all][-]") == true)
    }

    func testTheToolCanPretendItIsAnotherDay() async {
        let r = await render(["path": "sub/deep.html", "today": "2026-01-31"])
        XCTAssertEqual(r.json["html"] as? String, "2026-01-31")
        let bad = await render(["path": "sub/deep.html", "today": "nope"])
        XCTAssertTrue(bad.isError)
    }

    func testTheToolReportsErrorsWithTheirLine() async {
        let r = await render(["path": "bad.html"])
        XCTAssertFalse(r.isError, "a template error is a result for the agent, not a failure of the tool")
        XCTAssertEqual(r.json["ok"] as? Bool, false)
        let e = r.json["error"] as? [String: Any]
        XCTAssertEqual(e?["line"] as? Int, 1)
        XCTAssertTrue((e?["message"] as? String)?.contains("nonsense") == true)
    }

    func testTheToolOnlyReadsTemplatesInsideTheFolder() async throws {
        let out = try Scratch(["o.html": "<p>outside</p>"]); defer { out.remove() }
        try FileManager.default.createSymbolicLink(at: s.path("link.html"), withDestinationURL: out.path("o.html"))
        try s.write(".mdedit/h.html", "<p>hidden</p>")
        for p in ["../o.html", "link.html", ".mdedit/h.html", "/etc/hosts", "n.md", "missing.html", ""] {
            let r = await render(["path": p])
            XCTAssertTrue(r.isError, p)
            XCTAssertFalse(String(describing: r.json).contains("<p>outside</p>") || String(describing: r.json).contains("<p>hidden</p>"), p)
        }
    }

    func testTheToolWritesNothingAndOpensNothing() async {
        let before = T.fingerprint(s)
        var opened = 0
        ws.openAddress = { _ in opened += 1 }
        _ = await render(["path": "t.html", "query": "a=1"])
        XCTAssertEqual(T.fingerprint(s), before); XCTAssertEqual(opened, 0)
    }

    func testTheToolIsListedWithItsArguments() {
        let spec = AgentToolSpec.all.first { $0["name"] as? String == "render_template" }
        XCTAssertNotNil(spec)
        let schema = spec?["inputSchema"] as? [String: Any]
        XCTAssertEqual(schema?["required"] as? [String], ["path"])
        XCTAssertEqual(Set((schema?["properties"] as? [String: Any])?.keys.map { $0 } ?? []), ["path", "query", "today"])
    }

    func testAnOutputThatCouldOpenAConnectionIsNotReturned() async throws {
        try s.write("hint.html", #"<link rel="preconnect" href="//x.example">"#)
        let r = await render(["path": "hint.html"])
        XCTAssertEqual(r.json["ok"] as? Bool, false)
        XCTAssertNil(r.json["html"])
    }
}
