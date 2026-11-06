import XCTest
@testable import MDEdit

/// One test per row of the Limits table: pass the limit by one and see the stated outcome.
final class TemplateLimitTests: XCTestCase {
    var s: Scratch!

    override func setUpWithError() throws {
        s = try Scratch(["a.md": "# A\n\n## S\n\n" + String(repeating: "x", count: 100), "b.md": "# B\n\n## S\n\n" + String(repeating: "y", count: 100)])
        addTeardownBlock { self.s.remove() }
    }

    private func with(_ change: (inout TemplateLimits) -> Void) -> TemplateLimits { var l = TemplateLimits.standard; change(&l); return l }

    func testTemplateSize() {
        let l = with { $0.templateBytes = 10 }
        XCTAssertNotNil(T.run("1234567890", in: s, limits: l).success)
        XCTAssertTrue(T.isLimit(T.error("12345678901", in: s, limits: l)))
    }

    func testNodes() {
        let l = with { $0.nodes = 3 }
        XCTAssertNotNil(T.run("{{ 1 }}{{ 2 }}{{ 3 }}", in: s, limits: l).success)
        XCTAssertTrue(T.isLimit(T.error("{{ 1 }}{{ 2 }}{{ 3 }}{{ 4 }}", in: s, limits: l)))
        XCTAssertTrue(T.isLimit(T.error("a{{ 1 }}b{{ 2 }}", in: s, limits: l)), "text nodes count")
    }

    func testForDepthAndBlockDepth() {
        let three = "{% for a in n %}{% for b in n %}{% for c in n %}x{% endfor %}{% endfor %}{% endfor %}"
        XCTAssertNotNil(T.run(three, in: s).success)
        XCTAssertTrue(T.isLimit(T.error("{% for a in n %}{% for b in n %}{% for c in n %}{% for d in n %}x{% endfor %}{% endfor %}{% endfor %}{% endfor %}", in: s)))
        func nested(_ n: Int) -> String { String(repeating: "{% if 1 %}", count: n) + "x" + String(repeating: "{% endif %}", count: n) }
        XCTAssertNotNil(T.run(nested(10), in: s).success)
        XCTAssertTrue(T.isLimit(T.error(nested(11), in: s)))
        XCTAssertTrue(T.isLimit(T.error(nested(5_000), in: s)), "deep nesting stops at the limit and cannot overflow the stack")
    }

    func testDigits() {
        XCTAssertNotNil(T.run("{{ 123456789 }}", in: s).success)
        XCTAssertTrue(T.isLimit(T.error("{{ 1234567890 }}", in: s)))
    }

    func testItemsInAList() throws {
        for i in 0..<6 { try s.write("many/\(i).md", "# \(i)") }
        let l = with { $0.listItems = 5 }
        XCTAssertEqual(T.page(#"{% files "many" as i %}{% for f in i %}x{% endfor %}"#, in: s, limits: l).count, 5)
        XCTAssertEqual(T.page(#"{% files "many" limit 6 as i %}{% for f in i %}x{% endfor %}"#, in: s, limits: l).count, 5)
        XCTAssertEqual(T.page(#"{% files "many" limit 6 as i %}{% for f in i %}x{% endfor %}"#, in: s, limits: with { $0.listItems = 6 }).count, 6)
    }

    func testBytesPerSection() {
        let l = with { $0.sectionBytes = 100 }
        let ok = T.page(#"{% section "a.md" "S" as t %}[{{ t_error }}]"#, in: s)
        XCTAssertEqual(ok, "[]")
        let big = T.page(#"{% section "a.md" "S" as t %}[{{ t }}][{{ t_error }}]"#, in: s, limits: l)
        XCTAssertEqual(big, "[][too large]", "the note is larger than the cap: that one result is empty, the page renders")
    }

    func testBytesReadInOneRender() {
        let l = with { $0.readBytes = 150 }
        let page = T.page(#"{% section "a.md" "S" as t %}[{{ t_error }}]{% section "b.md" "S" as u %}[{{ u_error }}]"#, in: s, limits: l)
        XCTAssertEqual(page, "[][read budget used]", "the first note fits, the second does not")
    }

    func testEntriesReadInOneRender() throws {
        for i in 0..<6 { try s.write("six/\(i).md", "x") }
        let l = with { $0.entries = 5 }
        XCTAssertTrue(T.isLimit(T.error(#"{% files "six" as i %}"#, in: s, limits: l)))
        XCTAssertNotNil(T.run(#"{% files "six" as i %}"#, in: s, limits: with { $0.entries = 6 }).success)
        XCTAssertTrue(T.isLimit(T.error(#"{% files "six" as i %}{% files "" as j %}"#, in: s, limits: with { $0.entries = 8 })), "the count is for the whole render")
    }

    func testSteps() throws {
        for i in 0..<60 { try s.write("steps/\(i).md", "x") }
        let t = #"{% files "steps" as i %}{% for f in i %}{{ f.name }}{% endfor %}"#
        XCTAssertNotNil(T.run(t, in: s, limits: with { $0.steps = 1_000 }).success)
        XCTAssertTrue(T.isLimit(T.error(t, in: s, limits: with { $0.steps = 100 })))
    }

    func testOutputSize() {
        let l = with { $0.outputBytes = 100 }
        XCTAssertNotNil(T.run(String(repeating: "a", count: 100), in: s, limits: l).success)
        XCTAssertTrue(T.isLimit(T.error(String(repeating: "a", count: 101), in: s, limits: l)))
        XCTAssertTrue(T.isLimit(T.error(#"{% for x in n %}{% endfor %}{{ "" }}"# + String(repeating: "{{ \"aaaaaaaaaa\" }}", count: 11), in: s, limits: l)))
    }

    func testTheClock() {
        XCTAssertEqual(T.error("x", in: s, limits: with { $0.clock = 0 }), .timeout)
        let slow = SlowSource(delay: 0.25)
        let e = T.error(#"{% files "" as i %}{% files "" as j %}"#, in: s, limits: with { $0.clock = 0.1 }, source: slow)
        XCTAssertEqual(e, .timeout, "the check at the next source call sees the clock has run out")
    }

    func testCancel() {
        let flag = CancelFlag(); flag.cancel()
        if case .failure(let e) = T.run("x", in: s, cancel: flag) { XCTAssertEqual(e, .cancelled) } else { XCTFail() }
        let flag2 = CancelFlag()
        let slow = SlowSource(delay: 0); slow.onList = { flag2.cancel() }
        if case .failure(let e) = T.run(#"{% files "" as i %}{% files "" as j %}"#, in: s, source: slow, cancel: flag2) { XCTAssertEqual(e, .cancelled) } else { XCTFail() }
    }

    func testAMaximumSizeTemplateUnderATinyBudgetEnds() {
        let body = String(repeating: "{% for a in n %}{% for b in n %}x{{ 1 }}{% endfor %}{% endfor %}", count: 20)
        XCTAssertTrue(T.isLimit(T.error(body, in: s, limits: with { $0.steps = 10 })))
    }

    func testEveryNodeTypeChargesTheBudget() {
        let nodes = ["x", "{{ 1 }}", "{% for a in n %}{% endfor %}", "{% if 1 %}{% endif %}", #"{% files "" as i %}"#, #"{% section "a.md" "S" as t %}"#, #"{% meta "a.md" as m %}"#, #"{% tasks "a.md" as t %}"#, #"{% data "d.json" as d %}"#, #"{% include "i.html" %}"#, "{% sort n by \"k\" as x %}", "{% where n k as x %}", "{% groupby n by \"k\" as x %}", "{% verbatim %}x{% endverbatim %}", "<!-- c -->"]
        for n in nodes {
            XCTAssertTrue(T.isLimit(T.error(n, in: s, limits: with { $0.steps = 0 })), "\(n) does not call charge()")
        }
    }

    func testMarkdownOnA64KBHostileNoteEndsInTime() throws {
        let hostile = "## S\n\n" + String(repeating: "> ", count: 20_000) + "x\n"
        XCTAssertLessThanOrEqual(hostile.utf8.count, 64 * 1024)
        try s.write("hostile.md", hostile)
        let started = Date()
        _ = T.run(#"{% section "hostile.md" "S" as t %}{{ t|markdown }}"#, in: s)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3.0)
    }

    func testAnUnreadableAndANonUTF8FileGiveAnEmptyResult() throws {
        try s.write("bin.md", Data([0xFF, 0xFE, 0x00, 0xC3, 0x28]))
        try s.write("locked.md", "# L\n\n## S\n\nsecret")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: s.path("locked.md").path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: self.s.path("locked.md").path) }
        XCTAssertEqual(T.page(#"{% section "bin.md" "S" as t %}[{{ t_error }}]"#, in: s), "[not text]")
        XCTAssertEqual(T.page(#"{% section "locked.md" "S" as t %}[{{ t_error }}]"#, in: s), "[unreadable]")
        XCTAssertEqual(T.page(#"{% section "nope.md" "S" as t %}[{{ t_error }}]"#, in: s), "[not available]")
    }
}

extension Result {
    var success: Success? { if case .success(let v) = self { return v }; return nil }
}
