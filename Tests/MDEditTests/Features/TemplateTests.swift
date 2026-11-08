import XCTest
@testable import MDEdit

/// What the template language does when it is used as intended.
final class TemplateTests: XCTestCase {
    var s: Scratch!

    override func setUpWithError() throws {
        s = try Scratch([
            "journal/a.md": "# Alpha\n\nintro\n\n## Summary\n\nFirst **bold** line\n\n## Other\n\nelse\n",
            "journal/b.md": "# Beta\n\n## Summary\n\nSecond one\n",
            "journal/c.txt": "plain text note",
            "journal/sub/d.md": "# Deep\n",
            "journal/page.html": "<p>not a note</p>",
            "journal/.hidden.md": "# Hidden",
            "root.md": "# Root",
        ])
        addTeardownBlock { self.s.remove() }
    }

    func testTheWorkedExampleRenders() {
        let t = """
        <h1>Journal</h1>
        {% files "journal" as items %}
        {% for f in items %}
          <h2><a href="{{ f.path|urlencode }}">{{ f.title }}</a> <small>{{ f.modified }}</small></h2>
          {% section f.path "Summary" as text %}
          {{ text|markdown }}
        {% empty %}
          <p>No notes yet.</p>
        {% endfor %}
        """
        let p = T.page(t, in: s)
        XCTAssertTrue(p.contains("<h1>Journal</h1>"))
        XCTAssertTrue(p.contains("<a href=\"journal/a.md\">Alpha</a>"), p)
        XCTAssertTrue(p.contains("<a href=\"journal/b.md\">Beta</a>"))
        XCTAssertTrue(p.contains("<strong>bold</strong>"), "the section is turned into markup")
        XCTAssertTrue(p.contains("Second one"))
        XCTAssertFalse(p.contains("No notes yet."))
        XCTAssertFalse(p.contains("else"), "the next section is not included")
    }

    func testFilesListsNotesAndFoldersInTheBindersOrder() {
        let p = T.page(#"{% files "journal" as items %}{% for f in items %}{{ f.kind }}:{{ f.name }};{% endfor %}"#, in: s)
        XCTAssertEqual(p, "folder:sub;note:a.md;note:b.md;note:c.txt;", "folders first, then notes by name; no HTML, no hidden files, not recursive")
    }

    func testFilesFieldsAndTheRoot() {
        let p = T.page(#"{% files "" as items %}{% for f in items %}{{ f.path }}|{{ f.title }}|{{ f.size }};{% endfor %}"#, in: s)
        XCTAssertTrue(p.contains("journal|journal|0;"), "a folder's title is its name and its size is 0: "+p)
        XCTAssertTrue(p.contains("root.md|Root|"), p)
    }

    func testATitleFallsBackToTheFileName() {
        let p = T.page(#"{% files "journal" as items %}{% for f in items %}{{ f.title }};{% endfor %}"#, in: s)
        XCTAssertTrue(p.contains("c;"), "a note without a heading is named by its file: \(p)")
        XCTAssertTrue(p.contains("sub;"))
    }

    func testSortByModifiedReverseAndLimit() throws {
        let day: TimeInterval = 86_400
        for (i, name) in ["a.md", "b.md", "c.txt"].enumerated() {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(2 - i) * day)], ofItemAtPath: s.path("journal/" + name).path)
        }
        // oldest first: c, b, a
        XCTAssertEqual(T.page(#"{% files "journal" sort "modified" as items %}{% for f in items %}{% if f.kind == "note" %}{{ f.name }};{% endif %}{% endfor %}"#, in: s), "c.txt;b.md;a.md;")
        let newestTwo = T.page(#"{% files "journal" sort "modified" reverse limit 2 as items %}{% for f in items %}{{ f.name }};{% endfor %}"#, in: s)
        XCTAssertEqual(newestTwo, "sub;a.md;", "the folder was changed last, then a.md")
        XCTAssertEqual(T.page(#"{% files "journal" limit 0 as items %}[{% for f in items %}x{% empty %}none{% endfor %}]"#, in: s), "[none]")
        XCTAssertTrue(T.isType(T.error(#"{% files "journal" limit n as items %}"#, in: s)), "an unset limit variable is empty, which is not a number")
    }

    func testMoreThanAHundredNotesListTheFirstHundred() throws {
        for i in 0..<101 { try s.write(String(format: "many/n%03d.md", i), "# N\(i)") }
        var l = TemplateLimits.standard; l.listItems = 100
        let p = T.page(#"{% files "many" as items %}{% for f in items %}x{% endfor %}"#, in: s, limits: l)
        XCTAssertEqual(p.count, 100)
        XCTAssertEqual(T.page(#"{% files "many" limit 500 as items %}{% for f in items %}x{% endfor %}"#, in: s, limits: l).count, 100, "a limit over the cap is the cap")
        XCTAssertEqual(T.page(#"{% files "many" as items %}{% for f in items %}x{% endfor %}"#, in: s).count, 101, "the standard cap is 500")
    }

    func testSectionRules() throws {
        try s.write("n.md", "# T\n\n## One\n\nalpha\n\n### Child\n\nchild text\n\n## Two ##\n\nbeta\n\n## One\n\nduplicate\n")
        func sec(_ h: String) -> String { T.page("{% section \"n.md\" \"\(h)\" as t %}[{{ t }}]", in: s) }
        XCTAssertTrue(sec("One").contains("alpha"))
        XCTAssertTrue(sec("One").contains("child text"), "a deeper heading stays inside the section")
        XCTAssertFalse(sec("One").contains("beta"), "up to the next heading of the same level")
        XCTAssertFalse(sec("One").contains("duplicate"), "the first match wins")
        XCTAssertEqual(sec("Two"), "[beta]", "closing # marks are not part of the title")
        XCTAssertEqual(sec("Missing"), "[]")
        XCTAssertEqual(sec("T").contains("duplicate"), true, "the last section runs to the end, and the top heading holds everything below")
        XCTAssertEqual(T.page(#"{% section "n.md" "Missing" as t %}[{{ t_error }}]"#, in: s), "[]", "a missing heading is not an error")
    }

    func testForEmptyOverAnUnsetVariableAndANonList() {
        XCTAssertEqual(T.page("{% for x in nothing %}a{% empty %}none{% endfor %}", in: s), "none")
        XCTAssertTrue(T.isType(T.error(#"{% section "root.md" "Root" as t %}{% for x in t %}a{% endfor %}"#, in: s)))
    }

    func testConditions() {
        XCTAssertEqual(T.page(#"{% if "a" == "a" %}yes{% else %}no{% endif %}"#, in: s), "yes")
        XCTAssertEqual(T.page(#"{% if "a" != "a" %}yes{% else %}no{% endif %}"#, in: s), "no")
        XCTAssertEqual(T.page(#"{% if 1 == "1" %}yes{% else %}no{% endif %}"#, in: s), "no", "different types are never equal")
        XCTAssertEqual(T.page("{% if 0 %}yes{% else %}no{% endif %}", in: s), "no")
        XCTAssertEqual(T.page("{% if 5 %}yes{% endif %}", in: s), "yes")
        XCTAssertEqual(T.page("{% if missing %}yes{% else %}no{% endif %}", in: s), "no")
        XCTAssertEqual(T.page(#"{% files "journal" as items %}{% if items %}list{% endif %}"#, in: s), "list")
        XCTAssertEqual(T.page(#"{% files "nowhere" as items %}{% if items %}list{% else %}empty{% endif %}"#, in: s), "empty")
    }

    func testFilters() {
        XCTAssertEqual(T.page(#"{{ missing|default:"none" }}"#, in: s), "none")
        XCTAssertEqual(T.page(#"{{ "" |default:"none" }}"#, in: s), "none", "empty text counts as empty")
        XCTAssertEqual(T.page(#"{{ "x"|default:"none" }}"#, in: s), "x")
        XCTAssertEqual(T.page(#"{{ "a b/c#d?e%f"|urlencode }}"#, in: s), "a%20b/c%23d%3Fe%25f")
        XCTAssertEqual(T.page(#"{{ missing|urlencode }}"#, in: s), "")
        XCTAssertEqual(T.page(#"{{ "**x**"|markdown }}"#, in: s).trimmingCharacters(in: .whitespacesAndNewlines), "<p><strong>x</strong></p>")
        XCTAssertEqual(T.page(#"{{ "a|b"|default:"x|y" }}"#, in: s), "a|b", "a pipe inside a string is not a filter separator")
    }

    func testWrongTypesAreErrorsNamingTheVariable() {
        let list = T.error(#"{% files "journal" as items %}{{ items }}"#, in: s)
        XCTAssertTrue(T.isType(list)); XCTAssertTrue(list?.message.contains("items") == true)
        XCTAssertTrue(T.isType(T.error(#"{% files "journal" as items %}{% for f in items %}{{ f|urlencode }}{% endfor %}"#, in: s)))
        XCTAssertTrue(T.isType(T.error("{{ 5|urlencode }}", in: s)))
        XCTAssertTrue(T.isType(T.error("{{ 5|markdown }}", in: s)))
        XCTAssertTrue(T.isType(T.error(#"{% files 5 as items %}"#, in: s)))
    }

    func testEscapingInTextAndAttributes() throws {
        try s.write("x.md", "# <b>Bold</b> & \"q\" 'a'\n\n## S\n\n<script>alert(1)</script>\n\n[x](javascript:alert(1)) and [y](https://example.com)\n")
        let p = T.page(#"<a title="{{ f.title }}">{% files "" as items %}{% for f in items %}{% if f.name == "x.md" %}{{ f.title }}{% section f.path "S" as t %}|{{ t }}|{{ t|markdown }}{% endif %}{% endfor %}</a>"#, in: s)
        XCTAssertTrue(p.contains("&lt;b&gt;Bold&lt;/b&gt; &amp; &quot;q&quot; &#39;a&#39;") || p.contains("&lt;b&gt;Bold&lt;/b&gt; &amp; &quot;q&quot; &#x27;a&#x27;"), p)
        XCTAssertFalse(p.contains("<script"), p)
        XCTAssertFalse(p.contains("href=\"javascript"), "markdown blocks unsafe link schemes: \(p)")
        XCTAssertTrue(p.contains("example.com"), p)
    }

    func testAUnsetVariableAndANumberPrint() {
        XCTAssertEqual(T.page("[{{ nothing }}][{{ 42 }}][{{ a.b.c }}]", in: s), "[][42][]")
    }

    func testCommentsAndLineNumbers() {
        XCTAssertEqual(T.page("a{# hidden\nstill #}b", in: s), "ab")
        let e = T.error("line1\nline2\n{% nonsense %}", in: s)
        XCTAssertEqual(e?.line, 3)
    }

    func testASymlinkedChildPointingOutsideIsLeftOut() throws {
        let out = try Scratch(["Out.md": "# Outside secret"]); defer { out.remove() }
        try FileManager.default.createSymbolicLink(at: s.path("journal/link.md"), withDestinationURL: out.path("Out.md"))
        try s.write(".secret/x.md", "# Hidden secret")
        try FileManager.default.createSymbolicLink(at: s.path("journal/tohidden.md"), withDestinationURL: s.path(".secret/x.md"))
        let p = T.page(#"{% files "journal" as items %}{% for f in items %}{{ f.name }}={{ f.title }};{% endfor %}"#, in: s)
        XCTAssertFalse(p.contains("link.md"), p)
        XCTAssertFalse(p.contains("tohidden.md"), p)
        XCTAssertFalse(p.contains("secret"), p)
    }

    func testRenderThroughTheAsyncEntryPoint() async {
        let r = await TemplateEvaluator.render(text: #"{% files "journal" as items %}{{ items_error }}{% for f in items %}x{% endfor %}"#, root: s.url, cancel: CancelFlag())
        XCTAssertEqual(try? r.get(), "xxxx")
    }

    // MARK: a note's meta block

    private func withMetaNote() throws {
        try s.write("m.md", "---\ntitle: My note\nauthor: \"Sam R\"\ndraft: false\npublished: true\ntags: [a, b]\nlinks:\n  - x\n  - y\n---\n# Heading\n\nBody")
    }

    func testANotesMetaIsAvailableByKey() throws {
        try withMetaNote()
        let t = #"{% meta "m.md" as m %}<h1>{{ m.title }}</h1><p>{{ m.author }}</p>{% if m.published %}[pub]{% endif %}{% if m.draft %}[draft]{% endif %}{% for t in m.tags %}<i>{{ t }}</i>{% endfor %}{% for l in m.links %}<b>{{ l }}</b>{% endfor %}[{{ m_error }}]"#
        XCTAssertEqual(T.page(t, in: s), "<h1>My note</h1><p>Sam R</p>[pub]<i>a</i><i>b</i><b>x</b><b>y</b>[]")
    }

    func testMetaForEveryNoteInAFolder() throws {
        try withMetaNote()
        try s.write("n.md", "---\ntitle: Other\n---\n# H")
        let p = T.page(#"{% files "" as items %}{% for f in items %}{% if f.kind == "note" %}{% meta f.path as m %}{{ f.name }}={{ m.title|default:"-" }};{% endif %}{% endfor %}"#, in: s)
        XCTAssertTrue(p.contains("m.md=My note;") && p.contains("n.md=Other;") && p.contains("root.md=-;"), p)
    }

    func testMetaValuesAreEscaped() throws {
        try s.write("e.md", "---\ntitle: <b>x</b> & y\n---\n")
        XCTAssertEqual(T.page(#"{% meta "e.md" as m %}{{ m.title }}"#, in: s), "&lt;b&gt;x&lt;/b&gt; &amp; y")
    }

    func testNoMetaABlockNotAtTheTopAndAMissingKeyAreEmpty() throws {
        try s.write("plain.md", "# T\n\n---\ntitle: nope\n---\n")
        XCTAssertEqual(T.page(#"{% meta "plain.md" as m %}[{{ m.title }}][{{ m_error }}]"#, in: s), "[][]")
        try withMetaNote()
        XCTAssertEqual(T.page(#"{% meta "m.md" as m %}[{{ m.nothing }}][{{ m.nothing|default:"none" }}]"#, in: s), "[][none]")
    }

    func testMetaOfAFileThatCannotBeReadSaysWhy() throws {
        try s.write("bin.md", Data([0x2D, 0x2D, 0x2D, 0x0A, 0x00, 0xFF]))
        XCTAssertEqual(T.page(#"{% meta "bin.md" as m %}[{{ m_error }}]"#, in: s), "[not text]")
        XCTAssertEqual(T.page(#"{% meta "nope.md" as m %}[{{ m_error }}]"#, in: s), "[not available]")
        XCTAssertEqual(T.page(#"{% meta "../x.md" as m %}[{{ m_error }}]"#, in: s), "[not available]")
    }

    func testAnOversizedNoteStillGivesItsMeta() throws {
        try s.write("big.md", "---\ntitle: Big one\n---\n" + String(repeating: "x", count: 200_000))
        XCTAssertEqual(T.page(#"{% meta "big.md" as m %}{{ m.title }}"#, in: s), "Big one", "only the top of the note is read")
    }

    func testMetaCanChooseAFolder() throws {
        try s.write("cfg.md", "---\nfolder: journal\n---\n")
        let p = T.page(#"{% meta "cfg.md" as m %}{% files m.folder as items %}{% for f in items %}{{ f.name }};{% endfor %}"#, in: s)
        XCTAssertEqual(p, "sub;a.md;b.md;c.txt;")
    }
}
