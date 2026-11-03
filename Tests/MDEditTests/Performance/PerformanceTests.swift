import XCTest
@testable import MDEdit

/// Speed is a feature. These do not measure; they fail when something becomes much slower.
/// Budgets are about 5x what a current Mac needs. If one trips, find what changed before raising it.
final class PerformanceTests: XCTestCase {
    static let paragraph = "The quick **brown** fox jumps over the [[lazy]] dog, see https://example.com and `code`.\n\n- item one\n- [ ] task\n\n> quote\n\n## Heading\n\n"
    static func doc(bytes: Int) -> String { String(repeating: paragraph, count: max(1, bytes / paragraph.utf8.count)) }

    func testOpeningALargeFolderIsQuick() throws {
        let s = try Scratch(); defer { s.remove() }
        for d in 0..<40 { for f in 0..<75 { try s.write("Folder \(d)/Note \(f).md", "# Note\n[[Note 1]]") } }       // 3,000 notes
        var root: BinderNode!
        within(2.0, "scan 3,000 notes") { root = BinderNode.scan(s.url) }
        XCTAssertEqual(root.files.count, 3_000)
        within(0.5, "wiki index 3,000 notes") { _ = WikiIndex(root: root) }
        within(0.5, "rows with nothing open") { _ = root.rows(expanded: [], search: "") }
        within(1.0, "rows with everything open") { _ = root.rows(expanded: Set(root.children.map(\.url)), search: "") }
        within(1.0, "search across 3,000 notes") { _ = root.rows(expanded: [], search: "note 7") }
    }

    func testStylingWhileTyping() {
        for kb in [20, 100, 400] {
            let text = Self.doc(bytes: kb * 1024)
            let tv = EditorTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
            tv.string = text
            let budget = kb <= 20 ? 0.25 : kb <= 100 ? 1.0 : 4.0
            within(budget, "restyle \(kb) KB") { tv.restyle() }
            within(budget, "analyze \(kb) KB") { _ = MarkdownSyntax.analyze(text) }
        }
    }

    func testReadingModeAndExport() {
        let text = Self.doc(bytes: 300 * 1024)
        within(3, "preview page 300 KB") { _ = PreviewPage.body(markdown: text) }
        within(3, "html export 300 KB") { _ = Exporter.html(markdown: text, title: "t") }
        within(1, "outline 300 KB") { _ = Outline.headings(in: text) }
        within(1, "word count 300 KB") { _ = DocumentStore.wordCount(text) }
    }

    func testOpeningSavingAndReloadingAMegabyte() throws {
        let s = try Scratch(["big.md": Self.doc(bytes: 1_000_000)]); defer { s.remove() }
        let store = DocumentStore()
        within(1, "open 1 MB") { store.open(s.path("big.md")) }
        store.text += "x"
        within(1, "save 1 MB") { store.saveNow() }
    }

    func testAKeystrokeIsNotSlowerBecauseOfWatchingTheFolder() throws {
        let s = try Scratch(); defer { s.remove() }
        for i in 0..<500 { try s.write("n\(i).md", "[[n\((i + 1) % 500)]]") }
        let ws = makeWorkspace(open: s.url)
        ws.select(s.path("n0.md"))
        within(1.0, "reload 500 notes (what each save causes)") { ws.reload() }
        within(0.5, "document edit") { for i in 0..<200 { ws.document.text = "edit \(i)" } }
    }

    func testBacklinkScanOfManyNotes() async throws {
        let s = try Scratch(); defer { s.remove() }
        for i in 0..<1_000 { try s.write("n\(i).md", String(repeating: "filler text here. ", count: 40) + (i % 10 == 0 ? "[[Target]]" : "")) }
        try s.write("Target.md", "t")
        let ws = makeWorkspace(open: s.url)
        ws.outlineVisible = true
        let start = Date()
        ws.select(s.path("Target.md"))
        while ws.backlinks.count < 100, Date().timeIntervalSince(start) < 10 { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(ws.backlinks.count, 100)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "backlinks across 1,000 notes")
    }

    func testPaletteFilterIsInstant() {
        let cmds = (0..<2_000).map { Cmd(id: "c\($0)", title: "Command number \($0) does a thing") { } }
        within(0.3, "filter 2,000 commands") { for q in ["", "com", "number 19", "zzz"] { _ = PaletteView.filter(cmds, q) } }
    }

    func testMeasuredBaselines() {
        // `measure` records numbers in the test report so a slow drift is visible over time
        let text = Self.doc(bytes: 100 * 1024)
        measure { _ = MarkdownSyntax.analyze(text) }
    }
}
