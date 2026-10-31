import XCTest
@testable import MDEdit

final class KeyboardNavTests: XCTestCase {
    var dir: URL!
    var ws: Workspace!

    override func setUpWithError() throws {
        let fm = FileManager.default
        dir = fm.temporaryDirectory.appendingPathComponent("nav-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("A"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("B"), withIntermediateDirectories: true)
        try "one".write(to: dir.appendingPathComponent("A/One.md"), atomically: true, encoding: .utf8)
        try "two".write(to: dir.appendingPathComponent("Two.md"), atomically: true, encoding: .utf8)
        ws = Workspace()
        ws.open(dir)
        ws.expanded = []
        ws.selection = nil
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private var names: [String] { ws.rows.map(\.node.name) }

    func testDownWalksRowsAndOpensNotesWithoutToggling() {
        ws.moveSelection(1)
        XCTAssertEqual(ws.selection?.lastPathComponent, "A")
        XCTAssertFalse(ws.expanded.contains(ws.selection!), "arrows highlight a folder, they do not open it")
        ws.moveSelection(1); ws.moveSelection(1)
        XCTAssertEqual(ws.selection?.lastPathComponent, "Two.md")
        XCTAssertEqual(ws.document.url?.lastPathComponent, "Two.md")
        ws.moveSelection(1)
        XCTAssertEqual(ws.selection?.lastPathComponent, "Two.md", "stops at the last row")
    }

    func testRightOpensThenStepsInAndLeftClosesThenGoesUp() {
        ws.moveSelection(1)                       // A
        ws.expandSelection()
        XCTAssertEqual(names, ["A", "One", "B", "Two"])
        ws.expandSelection()                      // already open: into it
        XCTAssertEqual(ws.selection?.lastPathComponent, "One.md")
        ws.collapseSelection()                    // a note: up to its folder
        XCTAssertEqual(ws.selection?.lastPathComponent, "A")
        ws.collapseSelection()                    // an open folder: close it
        XCTAssertEqual(names, ["A", "B", "Two"])
    }
}

final class KeyboardNavPreviewTests: XCTestCase {
    func testPassingAnImageDoesNotPreviewIt() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("nav2-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: dir.appendingPathComponent("pic.png"), atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: dir) }
        let ws = Workspace()
        ws.open(dir)
        ws.selection = nil
        QuickView.shared.hide()
        ws.moveSelection(1)
        XCTAssertEqual(ws.selection?.lastPathComponent, "pic.png")
        XCTAssertFalse(QuickView.shared.isShowing)
    }
}
