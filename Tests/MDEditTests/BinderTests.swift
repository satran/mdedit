import XCTest
@testable import MDEdit

final class BinderTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mdedit-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("Ideas"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("Draft/Letter"), withIntermediateDirectories: true)
        for f in ["Zeta.md", "alpha.md", "notes.txt", "photo.png", ".hidden.md", "Ideas/Goals.md", "Ideas/Metrics.markdown", "Draft/Letter/Dora.md", "Draft/Outline.md"] {
            try "x".write(to: dir.appendingPathComponent(f), atomically: true, encoding: .utf8)
        }
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testScanListsEveryVisibleFileFoldersFirstNaturalOrder() {
        let root = BinderNode.scan(dir)
        XCTAssertEqual(root.children.map(\.name), ["Draft", "Ideas", "alpha", "notes", "photo.png", "Zeta"])
        XCTAssertEqual(root.files.map(\.name).sorted(), ["Dora", "Goals", "Metrics", "Outline", "Zeta", "alpha", "notes"], "photo.png is not a note")
        XCTAssertEqual(root.children.first { $0.name == "Ideas" }?.children.map(\.name), ["Goals", "Metrics"])
    }

    func testRowsFollowExpansion() {
        let root = BinderNode.scan(dir)
        XCTAssertEqual(root.rows(expanded: [], search: "").map(\.node.name), ["Draft", "Ideas", "alpha", "notes", "photo.png", "Zeta"])
        let draft = root.children[0].url
        let rows = root.rows(expanded: [draft], search: "")
        XCTAssertEqual(rows.map(\.node.name), ["Draft", "Letter", "Outline", "Ideas", "alpha", "notes", "photo.png", "Zeta"])
        XCTAssertEqual(rows[1].depth, 1)
        XCTAssertTrue(rows[0].isOpen)
    }

    func testSearchShowsMatchesAndTheirFolders() {
        let root = BinderNode.scan(dir)
        XCTAssertEqual(root.rows(expanded: [], search: "dora").map(\.node.name), ["Draft", "Letter", "Dora"])
        XCTAssertTrue(root.rows(expanded: [], search: "nothing").isEmpty)
    }

    func testUniqueURL() throws {
        let a = Workspace.uniqueURL(in: dir, base: "alpha", ext: "md")
        XCTAssertEqual(a.lastPathComponent, "alpha 2.md")
    }

    func testWikiResolveNearestAndPath() {
        let root = BinderNode.scan(dir)
        let from = dir.appendingPathComponent("Ideas/Goals.md")
        XCTAssertEqual(WikiIndex.resolve(WikiLink(target: "metrics", alias: nil), from: from, in: root)?.lastPathComponent, "Metrics.markdown")
        XCTAssertEqual(WikiIndex.resolve(WikiLink(target: "Letter/Dora#Intro", alias: nil), from: from, in: root)?.lastPathComponent, "Dora.md")
        XCTAssertNil(WikiIndex.resolve(WikiLink(target: "Missing", alias: nil), from: from, in: root))
    }

    // MARK: entries (one level, shared with templates)

    func testEntriesIsOneLevelFoldersFirstAndCountsEverythingTheFolderHeld() throws {
        let s = try Scratch(["b.md": "x", "a.md": "x", "Z/inner.md": "x", "A folder/x.md": "x", ".hidden.md": "x", "Pack.app/Contents/x": "x", "pic.png": Data([1])])
        defer { s.remove() }
        let out = BinderNode.entries(of: s.url)
        XCTAssertEqual(out.nodes.map(\.name), ["A folder", "Z", "a", "b", "pic.png"], "folders first, natural order, not recursive")
        XCTAssertTrue(out.nodes.filter(\.isFolder).allSatisfy { $0.children.isEmpty })
        XCTAssertEqual(out.rawCount, 7, "hidden entries and the package are counted before they are skipped")
    }

    func testEntriesSkipsLinksToFoldersAndKeepsLinksToFiles() throws {
        let s = try Scratch(["real.md": "x", "Dir/n.md": "x"]); defer { s.remove() }
        try FileManager.default.createSymbolicLink(at: s.path("dirlink"), withDestinationURL: s.path("Dir"))
        try FileManager.default.createSymbolicLink(at: s.path("filelink.md"), withDestinationURL: s.path("real.md"))
        let names = BinderNode.entries(of: s.url).nodes.map(\.name)
        XCTAssertFalse(names.contains("dirlink"))
        XCTAssertTrue(names.contains("filelink"))
    }
}
