import XCTest
@testable import MDEdit

/// Back goes to the note that was open before the current one.
@MainActor
final class BackNavigationTests: XCTestCase {
    private var s: Scratch!
    private var ws: Workspace!

    override func setUpWithError() throws {
        s = try Scratch(["A.md": "a", "B.md": "b", "C.md": "c"])
        addTeardownBlock { [s] in s?.remove() }
        ws = makeWorkspace(open: s.url)
        ws.select(s.path("A.md"))
    }

    private var open: String? { ws.document.url?.lastPathComponent }

    func testBackReturnsToThePreviousNoteAndWalksFurtherBack() {
        ws.select(s.path("B.md")); ws.select(s.path("C.md"))
        XCTAssertEqual(open, "C.md")
        ws.goBack(); XCTAssertEqual(open, "B.md"); XCTAssertEqual(ws.selection?.lastPathComponent, "B.md")
        ws.goBack(); XCTAssertEqual(open, "A.md")
        XCTAssertTrue(ws.visited.isEmpty)
        ws.goBack(); XCTAssertEqual(open, "A.md", "nothing before the first note")
    }

    func testGoingBackDoesNotRecordItself() {
        ws.select(s.path("B.md")); ws.goBack()
        XCTAssertEqual(open, "A.md")
        XCTAssertTrue(ws.visited.isEmpty, "Back must not make a trail that bounces between two notes")
    }

    func testReopeningTheOpenNoteAddsNothing() {
        ws.select(s.path("A.md")); ws.select(s.path("A.md"))
        XCTAssertTrue(ws.visited.isEmpty)
        ws.select(s.path("B.md")); ws.select(s.path("B.md"))
        XCTAssertEqual(ws.visited.map(\.lastPathComponent), ["A.md"])
    }

    func testFoldersAndOtherFilesAreNotPartOfTheTrail() throws {
        try s.write("pic.png", Data([1, 2, 3])); try s.write("Sub/D.md", "d"); ws.reload()
        ws.select(s.path("Sub")); ws.select(s.path("pic.png"))
        XCTAssertTrue(ws.visited.isEmpty)
        ws.select(s.path("B.md"))
        XCTAssertEqual(ws.visited.map(\.lastPathComponent), ["A.md"])
    }

    func testDeletedNotesAreSkipped() throws {
        ws.select(s.path("B.md")); ws.select(s.path("C.md"))
        try FileManager.default.removeItem(at: s.path("B.md")); ws.reload()
        ws.goBack()
        XCTAssertEqual(open, "A.md")
    }

    func testBackRevealsTheNoteInTheBinder() {
        try? s.write("Sub/D.md", "d"); ws.reload()
        ws.select(s.path("Sub/D.md")); ws.select(s.path("A.md"))
        ws.expanded = []
        ws.goBack()
        XCTAssertEqual(open, "D.md")
        XCTAssertTrue(ws.expanded.contains { $0.lastPathComponent == "Sub" })
    }

    func testTheTrailIsCappedAndClearedWithTheFolder() throws {
        for i in 0..<130 { ws.select(s.path(i % 2 == 0 ? "B.md" : "C.md")) }
        XCTAssertEqual(ws.visited.count, 100)
        let t = try Scratch(["Z.md": "z"]); addTeardownBlock { t.remove() }
        ws.open(t.url)
        XCTAssertTrue(ws.visited.isEmpty)
    }

    func testCommandIsEnabledOnlyWithSomewhereToGo() {
        func back() -> Cmd { makeCommands(ws: ws, prefs: Preferences(), recents: RecentFolders(), newWindow: { _ in }).first { $0.id == "back" }! }
        XCTAssertFalse(back().enabled); XCTAssertEqual(back().shortcut, "⌘[")
        ws.select(s.path("B.md"))
        XCTAssertTrue(back().enabled)
        back().run(); XCTAssertEqual(open, "A.md")
    }

    func testForwardRetracesBack() {
        ws.select(s.path("B.md")); ws.select(s.path("C.md"))
        ws.goBack(); ws.goBack()
        XCTAssertEqual(open, "A.md")
        ws.goForward(); XCTAssertEqual(open, "B.md"); XCTAssertEqual(ws.selection?.lastPathComponent, "B.md")
        ws.goForward(); XCTAssertEqual(open, "C.md")
        ws.goForward(); XCTAssertEqual(open, "C.md", "nothing after the last note")
        ws.goBack(); XCTAssertEqual(open, "B.md", "Back still works after Forward")
    }

    func testOpeningAnotherNoteEmptiesForward() {
        ws.select(s.path("B.md")); ws.goBack()
        XCTAssertFalse(ws.ahead.isEmpty)
        ws.select(s.path("C.md"))
        XCTAssertTrue(ws.ahead.isEmpty)
    }

    func testForwardSkipsDeletedNotesAndClearsWithTheFolder() throws {
        ws.select(s.path("B.md")); ws.select(s.path("C.md")); ws.goBack(); ws.goBack()
        try FileManager.default.removeItem(at: s.path("B.md")); ws.reload()
        ws.goForward()
        XCTAssertEqual(open, "C.md")
        ws.goBack()
        let t = try Scratch(["Z.md": "z"]); addTeardownBlock { t.remove() }
        ws.open(t.url)
        XCTAssertTrue(ws.ahead.isEmpty)
    }

    func testForwardCommand() {
        func fwd() -> Cmd { makeCommands(ws: ws, prefs: Preferences(), recents: RecentFolders(), newWindow: { _ in }).first { $0.id == "forward" }! }
        XCTAssertFalse(fwd().enabled); XCTAssertEqual(fwd().shortcut, "⌘]")
        ws.select(s.path("B.md")); ws.goBack()
        XCTAssertTrue(fwd().enabled)
        fwd().run(); XCTAssertEqual(open, "B.md")
    }
}
