import XCTest
@testable import MDEdit

final class WorkspaceTests: XCTestCase {
    var dir: URL!
    var ws: Workspace!

    override func setUpWithError() throws {
        let fm = FileManager.default
        dir = fm.temporaryDirectory.appendingPathComponent("ws-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("A"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("B"), withIntermediateDirectories: true)
        try "# One\n\nsee [[Two]]".write(to: dir.appendingPathComponent("A/One.md"), atomically: true, encoding: .utf8)
        try "# Two\n\n## Sub\n".write(to: dir.appendingPathComponent("Two.md"), atomically: true, encoding: .utf8)
        ws = Workspace()
        ws.open(dir)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func url(_ p: String) -> URL { dir.appendingPathComponent(p) }

    func testRenameKeepsExtensionAndFollowsOpenDocument() throws {
        ws.select(url("A/One.md"))
        XCTAssertEqual(ws.document.url?.lastPathComponent, "One.md")
        ws.rename(url("A/One.md"), to: "Uno")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url("A/Uno.md").path))
        XCTAssertEqual(ws.document.url?.lastPathComponent, "Uno.md")
        XCTAssertEqual(ws.selection?.lastPathComponent, "Uno.md")
        XCTAssertNotNil(ws.root?.find(url("A/Uno.md")))
    }

    func testRenameFolderMovesOpenDocumentWithIt() throws {
        ws.select(url("A/One.md"))
        ws.rename(url("A"), to: "Alpha")
        XCTAssertEqual(ws.document.url?.path, url("Alpha/One.md").standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url("Alpha/One.md").path))
    }

    func testRenameToExistingNameIsRefused() throws {
        try "x".write(to: url("Three.md"), atomically: true, encoding: .utf8)
        ws.reload()
        ws.rename(url("Three.md"), to: "Two")
        XCTAssertNotNil(ws.message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url("Three.md").path))
    }

    func testMoveIntoFolderAndRefuseIntoItself() throws {
        ws.moveItem(url("Two.md"), into: url("B"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url("B/Two.md").path))
        ws.moveItem(url("A"), into: url("A"))
        ws.moveItem(url("B"), into: url("B/Sub"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url("A").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url("B").path))
    }

    func testTrashClosesOpenDocument() throws {
        ws.select(url("Two.md"))
        ws.trash(url("Two.md"))
        XCTAssertNotEqual(ws.document.url?.lastPathComponent, "Two.md", "the tab next to it takes over")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url("Two.md").path))
        XCTAssertNil(ws.root?.find(url("Two.md")))
    }

    func testNewDocumentStartsRenaming() throws {
        ws.newDocument(in: url("B"))
        XCTAssertEqual(ws.renaming?.lastPathComponent, "Untitled.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url("B/Untitled.md").path))
    }

    func testBacklinksFindLinkingNotes() throws {
        ws.outlineVisible = true
        ws.select(url("Two.md"))
        let exp = expectation(description: "backlinks")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exp.fulfill() }
        wait(for: [exp], timeout: 3)
        XCTAssertEqual(ws.backlinks.map(\.lastPathComponent), ["One.md"])
        ws.outlineVisible = false
    }

    func testIndexNamesAndResolution() throws {
        XCTAssertEqual(ws.index.names, ["One", "Two"])
        XCTAssertTrue(ws.wikiResolves("two"))
        XCTAssertFalse(ws.wikiResolves("Nope"))
    }
}

final class OutlineExportTests: XCTestCase {
    func testHeadingsSkipFencesAndNeedASpace() {
        let md = "# A\n\n```\n# not\n```\n\n#tag\n## B ##\n"
        let h = Outline.headings(in: md)
        XCTAssertEqual(h.map(\.title), ["A", "B ##"])
        XCTAssertEqual(h.map(\.level), [1, 2])
        XCTAssertEqual(h[0].location, 0)
    }

    func testHTMLExport() {
        let html = Exporter.html(markdown: "# T\n\nsee [[Goals|goals]] **b**\n\n| a |\n|---|\n| 1 |\n\n- [x] done\n", title: "T")
        XCTAssertTrue(html.contains("<h1>T</h1>"))
        XCTAssertTrue(html.contains("see goals <strong>b</strong>"))
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("checkbox"))
        XCTAssertFalse(html.contains("[["))
    }

    func testWikiLinksInCodeFenceAreKept() {
        XCTAssertEqual(Exporter.plainWikiLinks("```\n[[x]]\n```\n[[y]]"), "```\n[[x]]\n```\ny")
    }
}
