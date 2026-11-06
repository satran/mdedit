import XCTest
@testable import MDEdit

/// Logic, dates, lists as views, tasks, data, includes, recursive listings, markdown links and queries (the requests in
/// docs/mdedit-template-requests.md that fit the security rules).
final class TemplateLanguageTests: XCTestCase {
    var s: Scratch!
    let friday = T.friday

    override func setUpWithError() throws {
        s = try Scratch([
            "tasks.md": """
            ---
            owner: Sat
            ---
            # Tasks

            - [ ] Pay the invoice @due(2026-11-04) @priority(A)
              Waiting on the bank
              - extra context line
            - [x] Send the report @due(2026-11-05) @priority(B)
            - [ ] Plan the week @due(2026-11-09)
              - [ ] Book a room @due(2026-11-10) @priority(A)
            - [ ] No date at all

            ```
            - [ ] not a task, it is in a fence
            ```
            """,
            "journal/a.md": "# Alpha\n\n## Summary\n\nSee [[Beta]] and [[Missing]] and [pic](img/p.png) ![i](img/i.png) `[[Beta]]`.\n",
            "journal/b.md": "# Beta\n",
            "Notes/Beta.md": "# Wiki Beta\n",
            "meetings/2026-11-06-sync.md": "# Sync\n", "meetings/2026-11-06-1on1.md": "# 1on1\n", "meetings/2026-11-05-old.md": "# Old\n", "meetings/deep/2026-11-06-deep.md": "# Deep\n",
            "pages/index.html": "<html><head><title>  The   Index </title></head><body>hi</body></html>", "pages/about.htm": "<p>x</p>",
            "data/day.json": #"{"focus":["a","b"],"count":3,"ratio":1.5,"ok":true,"no":false,"nothing":null,"events":[{"t":"09:00","who":"Sat"}]}"#,
            "data/day.yaml": "title: Today\ntags: [x, y]\nok: true\n",
            "inc/row.html": "<li>{{ t.text }}|{{ extra }}</li>", "inc/outer.html": "[{% include \"inc/row.html\" %}]", "inc/loop.html": "{% include \"inc/loop.html\" %}",
            "inc/bad.html": "{% nonsense %}",
        ])
        addTeardownBlock { self.s.remove() }
    }

    private func page(_ t: String, query: [String: String] = [:]) -> String { T.page(t, in: s, now: friday, query: query) }
    private func error(_ t: String) -> TemplateError? { T.error(t, in: s) }

    // MARK: logic

    func testAndOrNotElifAndIn() {
        XCTAssertEqual(page(#"{% if 1 == 1 and 2 == 2 %}y{% endif %}{% if 1 == 2 or 2 == 2 %}y{% endif %}{% if not 1 == 2 %}y{% endif %}"#), "yyy")
        XCTAssertEqual(page(#"{% if 1 == 2 or 2 == 3 and 3 == 3 %}y{% else %}n{% endif %}"#), "n", "and binds tighter than or")
        XCTAssertEqual(page(#"{% if not 1 == 1 or 2 == 2 %}y{% else %}n{% endif %}"#), "y", "not binds tightest")
        XCTAssertEqual(page(#"{% if 5 == 1 %}a{% elif 5 == 2 %}b{% elif 5 == 5 %}c{% else %}d{% endif %}"#), "c")
        XCTAssertEqual(page(#"{% if 5 == 1 %}a{% elif 5 == 2 %}b{% else %}d{% endif %}"#), "d")
        XCTAssertEqual(page(#"{% if "meet" in "a meeting" %}y{% endif %}{% if "x" in "abc" %}n{% endif %}{% if "" in "abc" %}n{% endif %}"#), "y")
        XCTAssertEqual(page(#"{% meta "tasks.md" as m %}{% if "Sat" in m.owner %}y{% endif %}"#), "y")
    }

    func testInOnListsAndRecords() {
        XCTAssertEqual(page(#"{% meta "journal/a.md" as m %}{% data "data/day.json" as d %}{% if "a" in d.focus %}y{% endif %}{% if "z" in d.focus %}n{% endif %}{% if "count" in d %}y{% endif %}{% if "nope" in d %}n{% endif %}"#), "yy")
    }

    func testOrderingComparisons() {
        XCTAssertEqual(page(#"{% if 1 < 2 %}a{% endif %}{% if 2 <= 2 %}b{% endif %}{% if 3 > 2 %}c{% endif %}{% if 3 >= 4 %}n{% endif %}"#), "abc")
        XCTAssertEqual(page(#"{% if "2026-11-04" < "2026-11-05" %}a{% endif %}{% if "b" > "a" %}b{% endif %}"#), "ab")
        XCTAssertEqual(page(#"{% if 1 < "2" %}n{% endif %}{% if missing < 5 %}n{% endif %}{% if 5 < missing %}n{% endif %}"#), "", "mixed types and empty values are false")
        XCTAssertEqual(page("{% if 5 > -3 %}neg{% endif %}"), "neg")
    }

    func testLengthAndFiltersInConditions() {
        XCTAssertEqual(page(#"{% data "data/day.json" as d %}{{ d.focus|length }} {{ d.events|length }} {{ "héllo"|length }} {{ missing|length }}"#), "2 1 5 0")
        XCTAssertEqual(page(#"{% data "data/day.json" as d %}{% if d.focus|length == 2 %}two{% endif %}{% if d.focus|length > 5 %}n{% endif %}"#), "two")
        XCTAssertTrue(T.isType(error("{{ 5|length }}")))
    }

    func testFiltersWithArgumentsAsVariables() {
        XCTAssertEqual(page(#"{% meta "tasks.md" as m %}{{ missing|default:m.owner }}|{{ ""|default:"x" }}"#), "Sat|x")
    }

    // MARK: dates

    func testTodayAndNow() {
        XCTAssertEqual(page("{{ today }} {{ now }}"), "2026-11-06 2026-11-06 12:00")
        XCTAssertTrue(T.isSyntax(error("{% files \"\" as today %}")), "today cannot be assigned")
    }

    func testDaysUntilSinceAndComparisons() {
        XCTAssertEqual(page(#"{{ "2026-11-09"|days_until }} {{ "2026-11-06"|days_until }} {{ "2026-11-04"|days_until }} {{ "2026-11-04"|days_since }} {{ "2026-11-09"|days_since }}"#), "3 0 -2 2 -3")
        XCTAssertEqual(page(#"{% if "2026-11-04"|days_until < 0 %}late{% endif %}{% if "2026-11-06" == today %}today{% endif %}{% if "2026-11-04" < today %}before{% endif %}"#), "latetodaybefore")
        XCTAssertEqual(page(#"[{{ ""|days_until }}][{{ "garbage"|days_until }}][{{ "2026-13-40"|days_until }}][{{ missing|days_since }}]"#), "[][][][]")
        XCTAssertEqual(page(#"{{ "2026-11-06 23:59"|days_until }}"#), "0", "the time of day does not matter")
    }

    func testDateFormatAndWeek() {
        XCTAssertEqual(page(#"{{ "2026-11-02"|date:"EEE d MMM" }}|{{ today|date:"d MMMM yyyy" }}|{{ "2026-11-06 14:30"|date:"HH:mm" }}"#), "Mon 2 Nov|6 November 2026|14:30")
        XCTAssertEqual(page(#"{{ "2026-11-06"|week }} {{ today|week }} {{ "2026-11-09"|week }} {{ "2026-12-31"|week }} {{ "2027-01-01"|week }}"#), "2026-W45 2026-W45 2026-W46 2026-W53 2026-W53")
        XCTAssertEqual(page(#"{% if "2026-11-02"|week == today|week %}this week{% endif %}"#), "this week")
        XCTAssertTrue(T.isType(error(#"{{ today|date:"yyyy-MM-dd'T'HH" }}"#)), "only letters, digits, spaces and - / . , :")
        XCTAssertTrue(T.isType(error(#"{{ today|date:"yyyy-MM-dd yyyy-MM-dd yyyy-MM-dd yyyy-MM-dd yyyy" }}"#)))
        XCTAssertEqual(page(#"[{{ "nope"|date:"yyyy" }}]"#), "[]")
    }

    // MARK: sort, where, groupby

    private let listing = #"{% files "meetings" as items %}"#

    func testSortWhereGroupby() {
        XCTAssertEqual(page(#"{% tasks "tasks.md" as ts %}{% sort ts by "attrs.due" as x %}{% for t in x %}{{ t.line }};{% endfor %}"#), "6;9;10;11;12;", "oldest due first, no date last")
        XCTAssertEqual(page(#"{% tasks "tasks.md" as ts %}{% sort ts by "attrs.due" desc as x %}{% for t in x %}{{ t.line }};{% endfor %}"#), "11;10;9;6;12;", "missing stays last when descending")
        XCTAssertEqual(page(#"{% tasks "tasks.md" as ts %}{% sort ts by "attrs.due" missing first as x %}{% for t in x %}{{ t.line }};{% endfor %}"#), "12;6;9;10;11;")
        XCTAssertEqual(page(#"{% tasks "tasks.md" as ts %}{% sort ts by "attrs.priority" "attrs.due" desc as x %}{% for t in x %}{{ t.line }};{% endfor %}"#), "11;6;9;10;12;", "several keys: priority, then due")
        XCTAssertEqual(page(#"{% tasks "tasks.md" as ts %}{% where ts done == "" as open %}{{ open|length }}"#), "4")
        XCTAssertEqual(page(#"{% tasks "tasks.md" as ts %}{% where ts not done as open %}{{ open|length }}{% where ts done as closed %}{{ closed|length }}"#), "41")
        XCTAssertEqual(page(#"{% tasks "tasks.md" as ts %}{% where ts attrs.due < today as late %}{% for t in late %}{{ t.line }};{% endfor %}"#), "6;9;")
        XCTAssertEqual(page(#"{% tasks "tasks.md" as ts %}{% where ts attrs.priority == "A" as a %}{{ a|length }}{% where a is_sub as s %}{{ s|length }}"#), "21")
        XCTAssertEqual(page(#"{% tasks "tasks.md" as ts %}{% groupby ts by "attrs.priority" as g %}{% for x in g %}[{{ x.key|default:"none" }}:{{ x.count }}:{% for t in x.items %}{{ t.line }},{% endfor %}]{% endfor %}"#), "[A:2:6,11,][B:1:9,][none:2:10,12,]")
    }

    func testSortingTextAndNumbersAndNonRecords() {
        XCTAssertEqual(page(#"{% files "meetings" recursive as f %}{% sort f by "name" desc as x %}{% for i in x %}{{ i.name }};{% endfor %}"#),
                       "2026-11-06-sync.md;2026-11-06-deep.md;2026-11-06-1on1.md;2026-11-05-old.md;")
        XCTAssertEqual(page(#"{% data "data/day.json" as d %}{% sort d.focus by "x" as s %}{{ s|length }}"#), "2", "items that are not records have no key: they keep their order")
        XCTAssertEqual(page(#"{% sort nothing by "x" as s %}[{{ s|length }}]"#), "[0]")
        XCTAssertTrue(T.isType(error(#"{% meta "tasks.md" as m %}{% sort m by "x" as s %}"#)), "a record is not a list")
    }

    func testListToolsOnlyShrinkOrReorder() {
        // no tag makes a list longer than its source, so a loop stays as bounded as the lists the app supplies
        XCTAssertEqual(page(#"{% tasks "tasks.md" as ts %}{% sort ts by "line" as a %}{% where a text != "x" as b %}{% groupby b by "done" as g %}{{ ts|length }}{{ a|length }}{{ b|length }}{{ g|length }}"#), "5552")
    }

    // MARK: tasks

    func testTaskRecords() {
        let p = page(#"{% tasks "tasks.md" as ts %}{% for t in ts %}[{{ t.line }}|{{ t.done }}|{{ t.text }}|{{ t.is_sub }}|{{ t.attrs.due }}|{{ t.attrs.priority }}|{{ t.context }}]{% endfor %}"#)
        XCTAssertTrue(p.contains("[6||Pay the invoice||2026-11-04|A|Waiting on the bank\n- extra context line]"), p)
        XCTAssertTrue(p.contains("[9|true|Send the report||2026-11-05|B|]"), p)
        XCTAssertTrue(p.contains("[11||Book a room|true|2026-11-10|A|]"), p)
        XCTAssertFalse(p.contains("not a task"), "a fenced block is not a task list")
        XCTAssertEqual(page(#"{% tasks "tasks.md" as ts %}{% for t in ts %}{% if t.is_sub %}{{ t.indent }}{% endif %}{% endfor %}"#), "2")
    }

    func testTaskDetails() throws {
        try s.write("t2.md", "- [ ]\n- [X] Upper @a( spaced )  @b(x) text\n* [ ] star\n+ [ ] plus\n\t- [ ] tab sub\n- [] not a task\n- [ ]not a task either\n")
        let p = page(#"{% tasks "t2.md" as ts %}{% for t in ts %}<{{ t.text }}|{{ t.done }}|{{ t.attrs.a }}|{{ t.attrs.b }}|{{ t.indent }}>{% endfor %}"#)
        XCTAssertEqual(p, "<||||0><Upper text|true|spaced|x|0><star||||0><plus||||0><tab sub||||4>")
        XCTAssertEqual(page(#"{% tasks "tasks.md" as ts %}{% for t in ts %}{{ t.raw }};{% endfor %}"#).contains("Pay the invoice @due(2026-11-04) @priority(A);"), true)
    }

    func testTasksOfAMissingOrHiddenNoteAreEmptyWithAReason() throws {
        try s.write(".mdedit/t.md", "- [ ] hidden")
        XCTAssertEqual(page(#"{% tasks "nope.md" as ts %}[{{ ts|length }}][{{ ts_error }}]"#), "[0][not available]")
        XCTAssertEqual(page(#"{% tasks ".mdedit/t.md" as ts %}[{{ ts|length }}][{{ ts_error }}]"#), "[0][not available]")
        XCTAssertEqual(page(#"{% tasks "../x.md" as ts %}[{{ ts_error }}]"#), "[not available]")
    }

    func testAnOversizedTaskNoteSaysSo() throws {
        try s.write("big.md", String(repeating: "- [ ] x\n", count: 40_000))
        XCTAssertEqual(page(#"{% tasks "big.md" as ts %}[{{ ts|length }}][{{ ts_error }}]"#), "[0][too large]")
        var l = TemplateLimits.standard; l.taskItems = 3
        XCTAssertEqual(T.page(#"{% tasks "tasks.md" as ts %}{{ ts|length }}"#, in: s, limits: l), "3", "the list is cut at the limit")
    }

    // MARK: files

    func testRecursiveListingAndMatch() {
        XCTAssertEqual(page(#"{% files "meetings" recursive match "2026-11-06-*.md" as n %}{% for f in n %}{{ f.path }};{% endfor %}"#),
                       "meetings/2026-11-06-1on1.md;meetings/2026-11-06-sync.md;meetings/deep/2026-11-06-deep.md;")
        XCTAssertEqual(page(#"{% files "meetings" match "2026-11-06-*.md" as n %}{{ n|length }}"#), "2", "not recursive: only this level")
        XCTAssertEqual(page(#"{% files "" recursive match "?ew.md" as n %}{% for f in n %}{{ f.name }};{% endfor %}"#), "", "? is exactly one character")
        XCTAssertEqual(page(#"{% files "" recursive match "BETA.MD" as n %}{% for f in n %}{{ f.path }};{% endfor %}"#), "Notes/Beta.md;", "ignoring case, by path")
        XCTAssertEqual(page(#"{% files "meetings" recursive as n %}{% for f in n %}{% if f.kind == "folder" %}F{% endif %}{% endfor %}[{{ n|length }}]"#), "[4]", "no folders in a recursive list")
        XCTAssertEqual(page(#"{% files "meetings" recursive sort "modified" reverse limit 2 as n %}{{ n|length }}"#), "2")
    }

    func testPagesInListings() {
        XCTAssertEqual(page(#"{% files "pages" as n %}{{ n|length }}"#), "0", "pages are only listed when asked for")
        XCTAssertEqual(page(#"{% files "pages" pages as n %}{% for f in n %}{{ f.kind }}:{{ f.name }}:{{ f.title }}:{{ f.ext }};{% endfor %}"#), "page:about.htm:about:htm;page:index.html:The Index:html;")
        XCTAssertEqual(page(#"{% files "" recursive pages match "*.html" as n %}{% for f in n %}{{ f.path }};{% endfor %}"#), "inc/bad.html;inc/loop.html;inc/outer.html;inc/row.html;pages/index.html;")
    }

    func testListingFieldsFolderAndExt() {
        XCTAssertEqual(page(#"{% files "meetings" recursive match "*deep.md" as n %}{% for f in n %}{{ f.folder }}|{{ f.ext }};{% endfor %}"#), "meetings/deep|md;")
        XCTAssertEqual(page(#"{% files "" match "tasks.md" as n %}{% for f in n %}[{{ f.folder }}]{% endfor %}"#), "[]")
    }

    func testRecursiveListingDoesNotLeakHiddenOrOutside() throws {
        try s.write(".mdedit/secret.md", "# s"); try s.write("meetings/.git/x.md", "# g")
        let out = try Scratch(["o.md": "# out"]); defer { out.remove() }
        try FileManager.default.createSymbolicLink(at: s.path("meetings/outlink.md"), withDestinationURL: out.path("o.md"))
        try FileManager.default.createSymbolicLink(at: s.path("meetings/outdir"), withDestinationURL: out.url)
        let p = page(#"{% files "" recursive pages as n %}{% for f in n %}{{ f.path }};{% endfor %}"#)
        for bad in [".mdedit", ".git", "outlink", "outdir", "o.md"] { XCTAssertFalse(p.contains(bad), "\(bad): \(p)") }
    }

    func testPatternsCannotBeMadeSlow() {
        let started = Date()
        let pattern = String(repeating: "*a", count: 49) + "b"
        _ = page("{% files \"\" recursive match \"\(pattern)\" as n %}")
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
        XCTAssertTrue(T.isType(error("{% files \"\" match \"\(String(repeating: "a", count: 101))\" as n %}")), "a pattern is at most 100 characters")
        XCTAssertTrue(TemplateGlob.matches("*", "") && TemplateGlob.matches("a*b*c", "aXXbYYc") && !TemplateGlob.matches("a*b*c", "aXXbYY"))
    }

    func testRecursionIsBoundedInDepthAndEntries() throws {
        var path = ""
        for i in 0..<15 { path += "d\(i)/" }
        try s.write(path + "deepest.md", "# d")
        XCTAssertFalse(page(#"{% files "" recursive match "deepest.md" as n %}{{ n|length }}"#).contains("1"), "deeper than 12 levels is not reached")
        var l = TemplateLimits.standard; l.entries = 5
        XCTAssertTrue(T.isLimit(T.error(#"{% files "" recursive as n %}"#, in: s, limits: l)))
    }

    // MARK: data

    func testDataJSON() {
        XCTAssertEqual(page(#"{% data "data/day.json" as d %}{{ d.count }}|{{ d.ratio }}|{{ d.ok }}|[{{ d.no }}]|[{{ d.nothing }}]|{% for e in d.events %}{{ e.t }} {{ e.who }}{% endfor %}|{{ d.focus|length }}[{{ d_error }}]"#),
                       "3|1.5|true|[]|[]|09:00 Sat|2[]")
        XCTAssertEqual(page(#"{% data "data/day.json" as d %}{% if d.ok %}ok{% endif %}{% if d.no %}no{% endif %}"#), "ok")
    }

    func testDataYAMLIsTheSameSmallSubsetAsAProperties() {
        XCTAssertEqual(page(#"{% data "data/day.yaml" as d %}{{ d.title }}|{% for t in d.tags %}{{ t }}{% endfor %}|{{ d.ok }}"#), "Today|xy|true")
    }

    func testDataErrorsAndRules() throws {
        try s.write("data/bad.json", "{not json"); try s.write(".mdedit/h.json", #"{"a":1}"#); try s.write("data/x.txt", "hi")
        let out = try Scratch(["o.json": #"{"a":1}"#]); defer { out.remove() }
        try FileManager.default.createSymbolicLink(at: s.path("data/link.json"), withDestinationURL: out.path("o.json"))
        try FileManager.default.createSymbolicLink(at: s.path("data/tohidden.json"), withDestinationURL: s.path(".mdedit/h.json"))
        for (p, why) in [("data/bad.json", "not text"), (".mdedit/h.json", "not available"), ("data/x.txt", "not available"), ("data/link.json", "not available"),
                         ("data/tohidden.json", "not available"), ("nope.json", "not available"), ("../o.json", "not available")] {
            XCTAssertEqual(page("{% data \"\(p)\" as d %}[{{ d_error }}]"), "[\(why)]", p)
        }
    }

    func testDataSizeAndDepthAreBounded() throws {
        try s.write("data/deep.json", String(repeating: "[", count: 40) + String(repeating: "]", count: 40))
        XCTAssertEqual(page(#"{% data "data/deep.json" as d %}[{{ d_error }}]"#), "[too large]")
        try s.write("data/wide.json", "[" + (0..<60_000).map(String.init).joined(separator: ",") + "]")
        XCTAssertEqual(page(#"{% data "data/wide.json" as d %}[{{ d_error }}]"#), "[too large]")
        try s.write("data/huge.json", "[" + String(repeating: "1,", count: 140_000) + "1]")
        XCTAssertEqual(page(#"{% data "data/huge.json" as d %}[{{ d_error }}]"#), "[too large]")
    }

    // MARK: include

    func testIncludeWithValuesAndScope() throws {
        let t = #"{% tasks "tasks.md" as ts %}{% for t in ts %}{% if t.line == 6 %}{% include "inc/row.html" with extra="x y" %}{% endif %}{% endfor %}|{{ extra }}|{% include "inc/outer.html" with t=ts extra="e" %}"#
        let out = page(t)
        XCTAssertTrue(out.hasPrefix("<li>Pay the invoice|x y</li>||[<li>"), out)
        XCTAssertTrue(out.hasSuffix("|e</li>]"), "the include sees the caller's variables, and a binding is gone after it: \(out)")
        XCTAssertEqual(page(#"{% include "inc/row.html" with t=ts %}"#), "<li>|</li>")
    }

    func testIncludeErrors() {
        XCTAssertTrue(T.isSyntax(error(#"{% include "nope.html" %}"#)))
        XCTAssertTrue(error(#"{% include "inc/bad.html" %}"#)?.message.contains("inc/bad.html") == true)
        XCTAssertTrue(T.isLimit(error(#"{% include "inc/loop.html" %}"#)), "a file that includes itself stops at the depth limit")
        for p in ["../x.html", ".mdedit/x.html", "/etc/hosts", "tasks.md", "data/day.json"] { XCTAssertTrue(T.isSyntax(error("{% include \"\(p)\" %}")), p) }
    }

    func testIncludeCountIsBounded() {
        var l = TemplateLimits.standard; l.includes = 3
        XCTAssertNotNil(T.run(#"{% include "inc/row.html" %}{% include "inc/row.html" %}{% include "inc/row.html" %}"#, in: s, limits: l).success)
        XCTAssertTrue(T.isLimit(T.error(#"{% include "inc/row.html" %}{% include "inc/row.html" %}{% include "inc/row.html" %}{% include "inc/row.html" %}"#, in: s, limits: l)))
    }

    func testIncludedOutputGoesThroughTheGuard() throws {
        try s.write("inc/evil.html", #"<link rel="preconnect" href="//x.example">"#)
        guard case .unsafe = T.error(#"{% include "inc/evil.html" %}"#, in: s) ?? .cancelled else { return XCTFail() }
    }

    // MARK: verbatim and comments

    func testBracesInHTMLCommentsAndVerbatim() {
        XCTAssertEqual(page("<!-- {{ x }} {% for %} -->ok"), "<!-- {{ x }} {% for %} -->ok")
        XCTAssertEqual(page("a<!-- multi\n{% line %} -->b{{ 1 }}"), "a<!-- multi\n{% line %} -->b1")
        XCTAssertEqual(page("{% verbatim %}{{ x }} {% if %}{% endverbatim %}{{ 2 }}"), "{{ x }} {% if %}2")
        XCTAssertTrue(T.isSyntax(error("{% verbatim %}never closed")))
        XCTAssertEqual(T.error("<!-- c -->\n{% nonsense %}", in: s)?.line, 2, "lines are counted through a comment")
    }

    // MARK: markdown: wiki links and base

    func testWikiLinksBecomeLinksToTheNote() {
        let p = page(#"{% section "journal/a.md" "Summary" as t %}{{ t|markdown }}"#)
        XCTAssertTrue(p.contains(#"<a href="Notes/Beta.md">Beta</a>"#), p)
        XCTAssertFalse(p.contains("[[Missing]]"), "a link to a note that does not exist is plain text")
        XCTAssertTrue(p.contains("Missing"))
        XCTAssertTrue(p.contains("<code>[[Beta]]</code>"), "code is left alone: \(p)")
    }

    func testWikiLinkAliasAndFolder() throws {
        try s.write("x.md", "[[Notes/Beta|the beta note]] and [[meetings/2026-11-06-sync]]")
        let p = page(#"{% section "x.md" "none" as t %}{{ "[[Notes/Beta|the beta note]] and [[2026-11-06-sync]]"|markdown }}"#)
        XCTAssertTrue(p.contains(#"<a href="Notes/Beta.md">the beta note</a>"#), p)
        XCTAssertTrue(p.contains(#"href="meetings/2026-11-06-sync.md""#), p)
    }

    func testBaseRebasesRelativeLinksAndPictures() {
        let p = page(#"{% section "journal/a.md" "Summary" as t %}{{ t|markdown:"journal" }}"#)
        XCTAssertTrue(p.contains(#"href="journal/img/p.png""#), p)
        XCTAssertTrue(p.contains(#"src="journal/img/i.png""#), p)
        XCTAssertTrue(page(#"{{ "[a](../x.md) [b](https://e.com/p) [c](#top) [d](/abs)"|markdown:"journal/sub" }}"#).contains(#"href="journal/x.md""#))
    }

    func testBaseCannotLeaveTheOpenedFolderAndLeavesOtherLinksAlone() {
        let p = page(#"{{ "[up](../../x.md) [web](https://e.com/p) [frag](#top) [mail](mailto:a@b.c)"|markdown:"journal" }}"#)
        XCTAssertFalse(p.contains("x.md\""), "a link that would leave the folder has no target: \(p)")
        XCTAssertTrue(p.contains(#"href="https://e.com/p""#) && p.contains(##"href="#top""##) && p.contains("mailto:a@b.c"), p)
        XCTAssertTrue(page(#"{{ "[a](b%20c.md)"|markdown:"my folder" }}"#).contains("my%20folder"))
    }

    func testTheBaseCanBeAVariableAndNoBaseMeansNoChange() {
        XCTAssertTrue(page(#"{% files "journal" as items %}{% for f in items %}{% if f.name == "a.md" %}{% section f.path "Summary" as t %}{{ t|markdown:f.folder }}{% endif %}{% endfor %}"#).contains(#"href="journal/img/p.png""#))
        XCTAssertTrue(page(#"{{ "[a](x.md)"|markdown }}"#).contains(#"href="x.md""#))
        XCTAssertTrue(page(#"{{ "[a](x.md)"|markdown:missing }}"#).contains(#"href="x.md""#), "an empty base is no base")
    }

    func testWikiAndBaseKeepEverythingEscaped() {
        let p = page(#"{{ "[[<script>]] [x](javascript:alert(1)) <img src=x onerror=1> [[Beta|<b>]]"|markdown:"journal" }}"#)
        XCTAssertFalse(p.contains("<script"), p); XCTAssertFalse(p.contains("<img"), p); XCTAssertFalse(p.contains("href=\"javascript"), p); XCTAssertFalse(p.contains("<b>"), p)
    }

    // MARK: query

    func testQueryParameters() {
        XCTAssertEqual(page("[{{ query.due }}][{{ query.priority }}][{{ query.nothing|default:\"-\" }}]", query: ["due": "overdue", "priority": "A"]), "[overdue][A][-]")
        XCTAssertEqual(page(#"{% if query.due == "overdue" %}late{% else %}all{% endif %}"#, query: ["due": "overdue"]), "late")
        XCTAssertEqual(page(#"{% if query.due == "overdue" %}late{% else %}all{% endif %}"#), "all")
        XCTAssertEqual(page("{{ query.x }}", query: ["x": "<script>alert(1)</script>"]), "&lt;script&gt;alert(1)&lt;/script&gt;", "query values are escaped like any text")
        XCTAssertTrue(T.isSyntax(error("{% files \"\" as query %}")))
    }
}
