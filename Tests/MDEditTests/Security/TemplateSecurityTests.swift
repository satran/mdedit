import XCTest
@testable import MDEdit

/// Every template is hostile. Whatever it says, it must not read outside the rules, must not change a file, and must not make
/// text from a note into markup except through `markdown`.
final class TemplateSecurityTests: XCTestCase {
    var s: Scratch!
    var outside: Scratch!

    override func setUpWithError() throws {
        s = try Scratch([
            "A.md": "# A\n\n## S\n\nvisible",
            ".mdedit/secret.md": "# Secret\n\n## S\n\nhidden text",
            ".hidden.md": "# H", "Thing.app/Contents/x.md": "# Package", "page.html": "<b>x</b>",
            "evil.md": "# <script>alert(1)</script>\n\n## S\n\n<img src=\"https://evil.example/?q=1\"> {% files \"\" as x %} {{ y }} javascript:alert(1)\n",
        ])
        outside = try Scratch(["Out.md": "# Outside secret\n\n## S\n\noutside text"])
        try FileManager.default.createSymbolicLink(at: s.path("out.md"), withDestinationURL: outside.path("Out.md"))
        try FileManager.default.createSymbolicLink(at: s.path("visible.md"), withDestinationURL: s.path(".mdedit/secret.md"))
        try FileManager.default.createSymbolicLink(at: s.path("outdir"), withDestinationURL: outside.url)
        addTeardownBlock { self.s.remove(); self.outside.remove() }
    }

    private let leaks = ["outside text", "Outside secret", "hidden text", "Secret"]

    func testPathsThatLeaveTheRulesGiveNothing() {
        let paths = ["../Out.md", "/etc/hosts", "~/x.md", "out.md", "outdir/Out.md", ".mdedit/secret.md", ".hidden.md", "visible.md", "Thing.app/Contents/x.md", "page.html", "A.md/../../Out.md", "", "Missing.md"]
        for p in paths {
            let page = T.page("{% section \"\(p)\" \"S\" as t %}[{{ t }}][{{ t_error }}]", in: s)
            XCTAssertTrue(page.hasPrefix("[]["), "\(p): \(page)")
            for l in leaks { XCTAssertFalse(page.contains(l), "\(p) leaked \(l)") }
        }
    }

    func testListingsDoNotLeakHiddenOrOutsideFiles() {
        for folder in ["", ".mdedit", "outdir", "../", "/", "Thing.app", "~"] {
            let page = T.page("{% files \"\(folder)\" as items %}{% for f in items %}{{ f.path }}={{ f.title }};{% endfor %}", in: s)
            for l in leaks + ["secret.md", "out.md", "visible.md", ".hidden", "Out.md"] {
                XCTAssertFalse(page.contains(l), "\(folder) leaked \(l): \(page)")
            }
        }
    }

    func testEveryTagAndFilterOutsideTheGrammarIsASyntaxError() {
        let bad = [
            "{% include \"a.md\" %}", "{% extends \"a\" %}", "{% block x %}{% endblock %}", "{% now \"Y\" %}", "{% filter upper %}x{% endfilter %}",
            "{% ifnot x %}y{% endif %}", "{% break %}", "{% for i in 1...5 %}x{% endfor %}", "{% for i in items.count() %}x{% endfor %}", "{% load x %}",
            "{{ x|safe }}", "{{ x|lower }}", "{{ x|upper }}", "{{ x|join:\", \" }}", "{{ x|escape }}", "{{ x.method() }}", "{{ x|default }}",
            "{% if a and b %}x{% endif %}", "{% if a or b %}x{% endif %}", "{% if not a %}x{% endif %}", "{% if a %}x{% elif b %}y{% endif %}",
            "{% lines \"a.md\" 1 2 as t %}", "{% field \"a.md\" \"k\" as t %}", "{% files \"\" recursive as i %}", "{% comment %}x{% endcomment %}",
            "{% for x in items %}no end", "{% if a %}no end", "{% endfor %}", "{% else %}", "{{ unclosed", "{% unclosed", "{# unclosed",
            "{{ a b }}", "{% files \"\" as 1x %}", "{% files \"\" as x_error %}", "{% files \"\" sort \"size\" as i %}", "{% section \"a.md\" as t %}",
            "{{ \"bad \\n escape\" }}", "{{ for }}", "{{ -5 }}", "{{ 1234567890 }}",
        ]
        for t in bad {
            let e = T.run(t, in: s)
            if case .success(let p) = e { XCTFail("\(t) rendered: \(p)") }
        }
    }

    func testNoteTextIsEscapedAndInert() {
        let page = T.page(#"{% files "" as items %}{% for f in items %}{% if f.name == "evil.md" %}{{ f.title }}|{% section f.path "S" as t %}{{ t }}{% endif %}{% endfor %}"#, in: s)
        XCTAssertFalse(page.contains("<script"), page)
        XCTAssertFalse(page.contains("<img"), page)
        XCTAssertTrue(page.contains("&lt;script&gt;"), page)
        XCTAssertTrue(page.contains("{% files"), "template markers inside a note are printed, not run")
        XCTAssertTrue(page.contains("{{ y }}"))
    }

    func testTheMarkdownFilterOnHostileMarkdown() {
        let page = T.page(#"{% section "evil.md" "S" as t %}{{ t|markdown }}"#, in: s)
        XCTAssertFalse(page.contains("<img"), page)
        XCTAssertFalse(page.contains("<script"), page)
        XCTAssertFalse(page.contains("href=\"javascript"), page)
        let links = T.page(#"{{ "[a](javascript:alert(1)) [b](data:text/html,x) [c](vbscript:x) [d](JaVa\#tScript:x)"|markdown }}"#, in: s)
        for scheme in ["javascript", "data:", "vbscript"] { XCTAssertFalse(links.lowercased().contains("href=\"\(scheme)"), links) }
    }

    func testNothingOnDiskChangesWhateverTheCorpusDoes() {
        let before = T.fingerprint(s), outsideBefore = T.fingerprint(outside)
        let templates = [
            #"{% section "out.md" "S" as t %}{{ t }}"#, #"{% files "" as i %}{% for f in i %}{% section f.path "S" as t %}{{ t|markdown }}{% endfor %}"#,
            #"{% files "outdir" as i %}"#, "{% include \"../x\" %}", #"{{ "x"|default:"y" }}"#, #"{% section "evil.md" "S" as t %}{{ t|urlencode }}"#,
        ]
        for t in templates { _ = T.run(t, in: s) }
        XCTAssertEqual(T.fingerprint(s), before, "the opened folder is byte-for-byte the same")
        XCTAssertEqual(T.fingerprint(outside), outsideBefore)
    }

    func testAnAttributeValueFromANoteCannotBreakOutOfItsQuotes() throws {
        try s.write("q.md", "# a\" onmouseover=\"x\n")
        let page = T.page(#"{% files "" as i %}{% for f in i %}{% if f.name == "q.md" %}<a title="{{ f.title }}" href="{{ f.path|urlencode }}">{% endif %}{% endfor %}"#, in: s)
        XCTAssertTrue(page.contains("title=\"a&quot; onmouseover=&quot;x\""), page)
    }
}
