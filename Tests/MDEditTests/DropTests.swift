import XCTest
@testable import MDEdit

final class DropTests: XCTestCase {
    var dir: URL!
    var outside: URL!
    var ws: Workspace!
    let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString)")
        outside = fm.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("Notes/Deep"), withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try "# Note".write(to: dir.appendingPathComponent("Notes/Note.md"), atomically: true, encoding: .utf8)
        try "pic".write(to: outside.appendingPathComponent("My Photo (1).png"), atomically: true, encoding: .utf8)
        try "pdf".write(to: outside.appendingPathComponent("Report.pdf"), atomically: true, encoding: .utf8)
        ws = Workspace()
        ws.open(dir)
        ws.select(dir.appendingPathComponent("Notes/Note.md"))
    }
    override func tearDownWithError() throws {
        try? fm.removeItem(at: dir); try? fm.removeItem(at: outside)
    }

    func testRelativePathEncodesAndWalksUp() {
        let from = dir.appendingPathComponent("Notes")
        XCTAssertEqual(Workspace.relativePath(from: from, to: from.appendingPathComponent("My Photo (1).png")), "My%20Photo%20%281%29.png")
        XCTAssertEqual(Workspace.relativePath(from: from.appendingPathComponent("Deep"), to: dir.appendingPathComponent("x/y.png")), "../../x/y.png")
    }

    func testImageDroppedOnEditorIsCopiedBesideTheNoteAndLinked() {
        let text = ws.linkText(forDropped: [outside.appendingPathComponent("My Photo (1).png")])
        XCTAssertEqual(text, "![My Photo (1)](My%20Photo%20%281%29.png)")
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("Notes/My Photo (1).png").path))
    }

    func testOtherFileBecomesALinkAndASecondDropGetsANewName() {
        let pdf = outside.appendingPathComponent("Report.pdf")
        XCTAssertEqual(ws.linkText(forDropped: [pdf]), "[Report.pdf](Report.pdf)")
        XCTAssertEqual(ws.linkText(forDropped: [pdf]), "[Report 2.pdf](Report%202.pdf)")
    }

    func testFileAlreadyInTheBinderIsLinkedNotCopied() {
        let inside = dir.appendingPathComponent("Notes/Deep/Chart.png")
        try? "x".write(to: inside, atomically: true, encoding: .utf8)
        XCTAssertEqual(ws.linkText(forDropped: [inside]), "![Chart](Deep/Chart.png)")
        XCTAssertEqual(ws.linkText(forDropped: [dir.appendingPathComponent("Notes/Note.md")]), "[[Note]]")
    }

    func testBinderDropCopiesFromOutsideAndMovesFromInside() throws {
        ws.drop([outside.appendingPathComponent("Report.pdf")], into: dir.appendingPathComponent("Notes/Deep"))
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("Notes/Deep/Report.pdf").path))
        XCTAssertTrue(fm.fileExists(atPath: outside.appendingPathComponent("Report.pdf").path), "the original stays")
        ws.drop([dir.appendingPathComponent("Notes/Deep/Report.pdf")], into: dir)
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("Report.pdf").path))
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("Notes/Deep/Report.pdf").path))
    }
}
