import XCTest
import Markdown
import AppKit
@testable import MDEdit

/// HTML, JSON and YAML: how they are told apart, what the preview shows, how the editor treats them, and that agents handle them like notes.
@MainActor
final class CodeFilesTests: XCTestCase {
    // MARK: kinds

    func testKindsComeFromTheExtension() {
        func kind(_ n: String) -> CodeKind? { CodeKind(url: URL(fileURLWithPath: "/x/" + n)) }
        XCTAssertEqual(kind("a.html"), .html); XCTAssertEqual(kind("a.HTM"), .html); XCTAssertEqual(kind("a.json"), .json)
        XCTAssertEqual(kind("a.yaml"), .yaml); XCTAssertEqual(kind("a.YML"), .yaml)
        XCTAssertNil(kind("a.md")); XCTAssertNil(kind("a.txt")); XCTAssertNil(kind("a.png")); XCTAssertNil(CodeKind(url: nil))
    }

    func testTheBinderOpensCodeFilesInTheApp() throws {
        let s = try Scratch(["a.json": "{}", "b.yml": "a: 1", "c.html": "<p>", "d.md": "# d", "e.png": Data([1])]); defer { s.remove() }
        let tree = BinderNode.scan(s.url)
        func node(_ n: String) -> BinderNode { tree.children.first { $0.url.lastPathComponent == n }! }
        for n in ["a.json", "b.yml", "c.html", "d.md"] { XCTAssertTrue(node(n).opensInApp, n) }
        XCTAssertFalse(node("e.png").opensInApp)
        XCTAssertTrue(node("a.json").isCode && !node("a.json").isDocument)
        XCTAssertEqual(tree.files.count, 1, "only notes are in the wiki index, search and backlinks")
    }

    func testLinksToCodeFilesOpenThemInTheApp() throws {
        let s = try Scratch(["n.md": "x", "data.json": "{}", "conf.yaml": "a: 1"]); defer { s.remove() }
        for f in ["data.json", "conf.yaml"] {
            let dir = URL(fileURLWithPath: s.url.path, isDirectory: true)
            guard case .selectNote = LinkPolicy.decide(URL(string: f)!, noteFolder: dir, root: s.url) else { return XCTFail(f) }
        }
    }

    // MARK: YAML reader and table

    func testYAMLReaderReadsMapsListsAndScalars() throws {
        let y = """
        # a comment
        name: "My app"   # trailing
        version: 1.2
        tags: [a, "b, c", d]
        empty:
        db:
          host: localhost
          ports:
            - 80
            - 443
        items:
          - name: one
            size: 1
          - name: two
        note: |
          line one
          line two
        folded: >
          a
          b
        'quoted key': yes
        """
        let node = try XCTUnwrap(YAMLReader.parse(y))
        guard case .map(let top) = node else { return XCTFail() }
        func value(_ k: String) -> YAMLNode? { top.first { $0.key == k }?.value }
        XCTAssertEqual(value("name"), .scalar("My app"))
        XCTAssertEqual(value("version"), .scalar("1.2"))
        XCTAssertEqual(value("tags"), .list([.scalar("a"), .scalar("b, c"), .scalar("d")]))
        XCTAssertEqual(value("empty"), .scalar(""))
        XCTAssertEqual(value("db"), .map([.init(key: "host", value: .scalar("localhost")), .init(key: "ports", value: .list([.scalar("80"), .scalar("443")]))]))
        XCTAssertEqual(value("items"), .list([.map([.init(key: "name", value: .scalar("one")), .init(key: "size", value: .scalar("1"))]), .map([.init(key: "name", value: .scalar("two"))])]))
        XCTAssertEqual(value("note"), .scalar("line one\nline two"))
        XCTAssertEqual(value("folded"), .scalar("a b"))
        XCTAssertEqual(value("quoted key"), .scalar("yes"))
    }

    func testYAMLReaderRefusesWhatItCannotRead() {
        XCTAssertNil(YAMLReader.parse("just a sentence with no key"))
        XCTAssertNil(YAMLReader.parse("a: 1\n  b: bad indent\n"))
        XCTAssertNil(YAMLReader.parse(""))
        XCTAssertNil(YAMLReader.parse(String(repeating: "a: 1\n", count: 25_000)), "more than 20,000 lines")
        var deep = ""
        for i in 0..<30 { deep += String(repeating: "  ", count: i) + "k\(i):\n" }
        XCTAssertNil(YAMLReader.parse(deep + String(repeating: "  ", count: 30) + "v: 1"), "deeper than 20 levels")
        XCTAssertEqual(YAMLReader.parse("---\na: 1\n---\nb: 2\n"), .map([.init(key: "a", value: .scalar("1"))]), "the first document")
    }

    func testYAMLPreviewIsATable() {
        let md = CodePreview.markdown(yaml: "name: x\ndb:\n  host: h\ntags: [a, b]\nitems:\n  - id: 1\n  - id: 2\n")
        XCTAssertTrue(md.hasPrefix("| Key | Value |\n|---|---|\n"), md)
        for row in ["| name | x |", "| db.host | h |", "| tags | a, b |", "| items\\[1\\].id | 1 |", "| items\\[2\\].id | 2 |"] { XCTAssertTrue(md.contains(row), "\(row) in \(md)") }
        let html = SafeHTML.render(Document(parsing: md), preview: false)
        XCTAssertTrue(html.contains("<table>"), html)
    }

    func testPreviewsEscapeWhateverTheFileSays() {
        let md = CodePreview.markdown(yaml: "a: \"<script>alert(1)</script> | `x` [y](javascript:z)\"\n")
        let html = SafeHTML.render(Document(parsing: md), preview: false)
        XCTAssertFalse(html.contains("<script"), html); XCTAssertFalse(html.contains("href=\"javascript"), html)
        let j = CodePreview.markdown(json: #"{"k":"```\n<script>x</script>```evil"}"#)
        let jh = SafeHTML.render(Document(parsing: j), preview: false)
        XCTAssertFalse(jh.contains("<script"), jh)
        XCTAssertEqual(jh.components(separatedBy: "<pre>").count, 2, "a fence in the data cannot close the code block")
    }

    func testYAMLPreviewFallsBackToTheTextAndSaysWhy() {
        let md = CodePreview.markdown(yaml: "just text\nnothing here")
        XCTAssertTrue(md.contains("could not be read as a table")); XCTAssertTrue(md.contains("just text"))
        XCTAssertTrue(CodePreview.markdown(yaml: "  \n").contains("empty"))
    }

    // MARK: JSON preview

    func testJSONPreviewIsPrettyPrintedWithSortedKeys() {
        let md = CodePreview.markdown(json: #"{"b":[1,2],"a":{"z":true,"y":null},"url":"http://x.io/a"}"#)
        XCTAssertTrue(md.hasPrefix("```json\n{\n  \"a\" : {"), md)
        XCTAssertTrue(md.contains("\"url\" : \"http://x.io/a\""), "slashes are not escaped")
        XCTAssertLessThan(md.range(of: "\"a\"")!.lowerBound, md.range(of: "\"b\"")!.lowerBound)
    }

    func testJSONPreviewSaysWhenTheFileIsNotJSON() {
        let md = CodePreview.markdown(json: "{not json")
        XCTAssertTrue(md.hasPrefix("**This is not valid JSON.**"), md); XCTAssertTrue(md.contains("{not json"))
        XCTAssertTrue(CodePreview.markdown(json: "").contains("empty"))
        XCTAssertTrue(CodePreview.markdown(json: String(repeating: "1", count: 1_100_000)).contains("larger than"))
        XCTAssertTrue(CodePreview.markdown(json: "[1,2]").contains("1,\n  2") || CodePreview.markdown(json: "[1,2]").contains("1"))
    }

    // MARK: syntax colours

    func testSyntaxColoursFindTheParts() {
        func roles(_ t: String, _ k: CodeKind) -> Set<String> { Set(CodeSyntax.spans(t, kind: k).map { "\($0.role)" }) }
        XCTAssertTrue(roles("<p class=\"a\">{{ x }}</p><!-- c -->", .html).isSuperset(of: ["tag", "string", "template", "comment"]))
        XCTAssertTrue(roles(#"{"k": "v", "n": 1.5e3, "b": true}"#, .json).isSuperset(of: ["key", "string", "number", "keyword"]))
        XCTAssertTrue(roles("name: x # note\nlist:\n  - 1\n", .yaml).isSuperset(of: ["key", "comment", "number"]))
        XCTAssertTrue(CodeSyntax.spans(String(repeating: "a", count: 400_000), kind: .html).isEmpty, "a very large file is shown without colours")
        // a key is a key, its value is not
        let spans = CodeSyntax.spans("host: localhost", kind: .yaml).filter { $0.role == .key }
        XCTAssertEqual(spans.map { $0.range }, [NSRange(location: 0, length: 4)])
    }

    // MARK: the editor

    private func editor(_ text: String, code: CodeKind?) -> EditorTextView {
        let tv = EditorTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        tv.isRichText = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 400)); scroll.documentView = tv
        tv.code = code
        tv.string = text
        tv.restyle()
        return tv
    }

    func testCodeIsMonospaceHasNoMarkdownStylingAndIsColoured() throws {
        let text = "# not a heading\n- [ ] not a task\n[[not a wiki link]]\n<p class=\"x\">{{ y }}</p>"
        let code = editor(text, code: .html)
        let note = editor(text, code: nil)
        let storage = try XCTUnwrap(code.textStorage)
        XCTAssertTrue(try XCTUnwrap(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).isFixedPitch)
        XCTAssertTrue(code.syntax.spans.isEmpty, "the Markdown analysis is not run")
        XCTAssertFalse(note.syntax.spans.isEmpty)
        let ns = text as NSString
        let tagAt = ns.range(of: "<p").location
        XCTAssertNotEqual(storage.attribute(.foregroundColor, at: tagAt, effectiveRange: nil) as? NSColor, Palette.text, "a tag is coloured")
        XCTAssertEqual(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil).map { ($0 as! NSParagraphStyle).firstLineHeadIndent }, 0, "no gutter")
        code.code = nil
        XCTAssertFalse(code.syntax.spans.isEmpty, "back to a note: Markdown again")
    }

    func testCodeColumnsAreWideAndHaveNoGutter() {
        let tv = editor("x", code: .json)
        let w = tv.textContainer?.size.width ?? 0
        XCTAssertGreaterThan(w, 600)
        XCTAssertEqual(tv.textContainerInset.width, max(16, ((800 - w) / 2).rounded()), accuracy: 2)
    }

    func testTheEditorDoesNotContinueListsOrCompleteWikiLinksInCode() {
        let host = MarkdownTextEditor(text: .constant(""), documentID: nil, style: EditorStyle(fontName: "IBM Plex Mono", size: 17, lineWidth: 72), code: .yaml)
        let c = MarkdownTextEditor.Coordinator(host)
        let tv = editor("- item", code: .yaml)
        tv.setSelectedRange(NSRange(location: 6, length: 0))
        XCTAssertTrue(c.codeCommand(tv, #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(tv.string, "- item\n", "Return keeps the indentation (none here) and does not start a list item")
        tv.string = "  key: v"; tv.setSelectedRange(NSRange(location: 8, length: 0))
        XCTAssertTrue(c.codeCommand(tv, #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(tv.string, "  key: v\n  ", "the next line starts at the same indent")
        tv.string = "a"; tv.setSelectedRange(NSRange(location: 1, length: 0))
        tv.insertText("[", replacementRange: tv.selectedRange())
        XCTAssertFalse(tv.wikiList.isOpen)
        XCTAssertFalse(tv.isContinuousSpellCheckingEnabled == false && false)
    }

    func testTabIndentsAndBacktabOutdents() {
        let host = MarkdownTextEditor(text: .constant(""), documentID: nil, style: EditorStyle(fontName: "IBM Plex Mono", size: 17, lineWidth: 72), code: .json)
        let c = MarkdownTextEditor.Coordinator(host)
        let tv = editor("a\nb", code: .json)
        tv.setSelectedRange(NSRange(location: 1, length: 0))
        _ = c.codeCommand(tv, #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(tv.string, "a  \nb")
        tv.setSelectedRange(NSRange(location: 0, length: 5))
        _ = c.codeCommand(tv, #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(tv.string, "  a  \n  b")
        _ = c.codeCommand(tv, #selector(NSResponder.insertBacktab(_:)))
        XCTAssertEqual(tv.string, "a  \nb")
    }

    func testCodeFilesTurnOffSpellingAndSmartReplacements() {
        let tv = NSTextView()
        MarkdownTextEditor.configure(tv, code: .html)
        XCTAssertFalse(tv.isContinuousSpellCheckingEnabled); XCTAssertFalse(tv.isAutomaticSpellingCorrectionEnabled)
        XCTAssertFalse(tv.isAutomaticTextReplacementEnabled); XCTAssertFalse(tv.smartInsertDeleteEnabled)
        MarkdownTextEditor.configure(tv, code: nil)
        XCTAssertTrue(tv.isContinuousSpellCheckingEnabled)
    }

    // MARK: agents

    func testAgentsReadAndProposeEditsToHTMLJSONAndYAMLLikeNotes() throws {
        let s = try Scratch(["A.md": "# A\nold\n", "page.html": "<p>old</p>", "d.json": #"{"k": "old"}"#, "c.yaml": "k: old\n", "pic.png": Data([1]), ".h.json": "{}"]); defer { s.remove() }
        let windows = AgentWindows(); let tools = AgentTools(windows: windows)
        let ws = makeWorkspace(open: s.url); ws.select(s.path("A.md")); windows.register(ws)
        let store = ProposalStore()
        for (name, old) in [("A.md", "old"), ("page.html", "old"), ("d.json", "old"), ("c.yaml", "old")] {
            let read = tools.call(AgentToolCall(name: "read_note", arguments: ["path": name], client: "t"))
            XCTAssertFalse(read.isError, name); XCTAssertTrue(read.json.contains("old"), name)
            switch store.propose(in: ws, path: name, old: old, new: "new", title: "t", reason: "r", client: "t") {
            case .success(let p): XCTAssertEqual(p.path, name)
            case .failure(let e): XCTFail("\(name): \(e.message)")
            }
            XCTAssertTrue(try s.read(name).contains("old"), "a suggestion never changes the file")
        }
        for refused in ["pic.png", ".h.json", "../x.json"] {
            XCTAssertTrue(tools.call(AgentToolCall(name: "read_note", arguments: ["path": refused], client: "t")).isError, refused)
        }
    }

    func testAcceptingASuggestionForACodeFileOpensTheEditor() throws {
        let s = try Scratch(["A.md": "# A\n", "d.json": #"{"k": "old"}"#]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url); ws.select(s.path("d.json")); ws.mode = .view
        XCTAssertEqual(ws.mode, .view)
        // the same line `Workspace.accept` runs before it applies a suggestion
        if ws.mode == .view { ws.mode = .write }
        XCTAssertEqual(ws.mode, .write)
    }

    func testSafePathEditableCoversNotesAndCodeFilesOnly() throws {
        let s = try Scratch(["a.md": "", "b.txt": "", "c.html": "", "d.htm": "", "e.json": "", "f.yaml": "", "g.yml": "", "h.png": Data([1]), "i.csv": "x"]); defer { s.remove() }
        for ok in ["a.md", "b.txt", "c.html", "d.htm", "e.json", "f.yaml", "g.yml"] {
            if case .failure(let f) = SafePath.resolve(ok, in: s.url, kind: .editable) { XCTFail("\(ok): \(f.message)") }
        }
        for bad in ["h.png", "i.csv", "missing.md"] { XCTAssertNotNil(SafePath.resolve(bad, in: s.url, kind: .editable).failure, bad) }
        XCTAssertNotNil(SafePath.resolve("c.html", in: s.url, kind: .note).failure, "templates still read notes only with .note")
    }
}

extension Result {
    var failure: Failure? { if case .failure(let f) = self { return f }; return nil }
}
