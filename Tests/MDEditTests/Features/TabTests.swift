import XCTest
@testable import MDEdit

/// Notes open as tabs in the binder's Open section: every note that opens becomes one, and closing it never touches the file.
@MainActor
final class TabTests: XCTestCase {
    private var s: Scratch!
    private var ws: Workspace!

    override func setUpWithError() throws {
        s = try Scratch(["A.md": "a", "B.md": "b", "C.md": "c", "D.md": "d"])
        addTeardownBlock { [s] in s?.remove() }
        ws = makeWorkspace(open: s.url)
    }

    private var names: [String] { ws.openTabs.map { $0.deletingPathExtension().lastPathComponent } }
    private var open: String? { ws.document.url?.lastPathComponent }

    func testEachNoteThatOpensBecomesATabInOrder() {
        ws.select(s.path("B.md")); ws.select(s.path("C.md"))
        XCTAssertEqual(names, ["A", "B", "C"], "the folder opened on A")
        XCTAssertEqual(open, "C.md")
    }

    func testOpeningANoteThatIsAlreadyOpenSwitchesToItWithoutAnotherTab() {
        ws.select(s.path("B.md")); ws.select(s.path("A.md"))
        XCTAssertEqual(names, ["A", "B"])
        XCTAssertEqual(open, "A.md")
    }

    func testFoldersAndFilesThatOnlyPreviewAreNotTabs() throws {
        try s.write("pic.png", Data([1, 2, 3])); try s.write("Sub/E.md", "e"); ws.reload()
        ws.select(s.path("Sub")); ws.select(s.path("pic.png"))
        XCTAssertEqual(names, ["A"])
    }

    func testClosingTheOpenTabShowsTheNeighbourToItsRight() {
        ws.select(s.path("B.md")); ws.select(s.path("C.md")); ws.select(s.path("B.md"))
        ws.closeTab(s.path("B.md"))
        XCTAssertEqual(names, ["A", "C"])
        XCTAssertEqual(open, "C.md")
        XCTAssertEqual(ws.selection?.lastPathComponent, "C.md")
    }

    func testClosingTheLastTabInTheListShowsTheOneBefore() {
        ws.select(s.path("B.md")); ws.select(s.path("C.md"))
        ws.closeTab(s.path("C.md"))
        XCTAssertEqual(open, "B.md")
    }

    func testClosingAnotherTabLeavesTheOpenNoteAlone() {
        ws.select(s.path("B.md")); ws.select(s.path("C.md"))
        ws.closeTab(s.path("A.md"))
        XCTAssertEqual(names, ["B", "C"]); XCTAssertEqual(open, "C.md")
    }

    func testClosingTheOnlyTabEmptiesTheEditorAndKeepsTheFile() {
        ws.closeTab(s.path("A.md"))
        XCTAssertTrue(ws.openTabs.isEmpty)
        XCTAssertNil(ws.document.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.path("A.md").path))
    }

    func testClosingSavesTheNoteFirst() throws {
        ws.document.text = "changed"
        ws.select(s.path("B.md"))
        ws.closeTab(s.path("A.md"))
        XCTAssertEqual(try String(contentsOf: s.path("A.md")), "changed")
    }

    func testCloseOthersAndCloseBelow() {
        ws.select(s.path("B.md")); ws.select(s.path("C.md")); ws.select(s.path("D.md"))
        ws.closeTabs(below: s.path("B.md"))
        XCTAssertEqual(names, ["A", "B"])
        XCTAssertEqual(open, "B.md", "the open note was one of those closed, so its neighbour took over")
        ws.closeOtherTabs(than: s.path("A.md"))
        XCTAssertEqual(names, ["A"]); XCTAssertEqual(open, "A.md")
    }

    func testReorderingByDrag() {
        ws.select(s.path("B.md")); ws.select(s.path("C.md"))
        ws.moveTab(s.path("C.md"), before: s.path("A.md"))
        XCTAssertEqual(names, ["C", "A", "B"])
        ws.moveTab(s.path("C.md"), before: nil)
        XCTAssertEqual(names, ["A", "B", "C"])
    }

    func testNextAndPreviousWrapAround() {
        ws.select(s.path("B.md")); ws.select(s.path("C.md"))
        ws.switchTab(by: 1); XCTAssertEqual(open, "A.md")
        ws.switchTab(by: -1); XCTAssertEqual(open, "C.md")
        ws.switchTab(by: -1); XCTAssertEqual(open, "B.md")
    }

    func testReopenClosedTabBringsBackTheLastOneAndSkipsDeletedNotes() throws {
        ws.select(s.path("B.md")); ws.select(s.path("C.md"))
        ws.closeTab(s.path("B.md")); ws.closeTab(s.path("A.md"))
        try FileManager.default.removeItem(at: s.path("A.md")); ws.reload()
        ws.reopenClosedTab()
        XCTAssertEqual(open, "B.md", "A was closed last but is gone")
        XCTAssertTrue(names.contains("B"))
    }

    func testRenamingOrMovingAKeepsItsTab() throws {
        try s.write("Sub/E.md", "e"); ws.reload()
        ws.select(s.path("B.md"))
        ws.rename(s.path("B.md"), to: "Beta")
        XCTAssertEqual(names, ["A", "Beta"]); XCTAssertEqual(open, "Beta.md")
        ws.moveItem(s.path("Beta.md"), into: s.path("Sub"))
        XCTAssertEqual(ws.openTabs.last?.deletingLastPathComponent().lastPathComponent, "Sub")
        XCTAssertEqual(ws.openTabs.last?.lastPathComponent, "Beta.md")
    }

    func testTrashingTheOpenNoteClosesItsTabAndShowsANeighbour() {
        ws.select(s.path("B.md")); ws.select(s.path("C.md"))
        ws.trash(s.path("C.md"))
        XCTAssertEqual(names, ["A", "B"])
        XCTAssertEqual(open, "B.md")
    }

    func testTrashingAFolderClosesTheTabsInsideIt() throws {
        try s.write("Sub/E.md", "e"); ws.reload()
        ws.select(s.path("Sub/E.md")); ws.select(s.path("B.md"))
        ws.trash(s.path("Sub"))
        XCTAssertEqual(names, ["A", "B"])
    }

    func testNotesDeletedOutsideTheAppLoseTheirTab() throws {
        ws.select(s.path("B.md")); ws.select(s.path("C.md"))
        try FileManager.default.removeItem(at: s.path("B.md")); ws.reload()
        XCTAssertEqual(names, ["A", "C"])
    }

    func testTabsComeBackWhenTheWindowReopens() throws {
        let d = isolatedDefaults()
        let id = try XCTUnwrap(Workspace.stash(s.url, defaults: d))
        let w1 = Workspace(id: id, defaults: d, recents: RecentFolders(defaults: d))
        w1.select(s.path("B.md")); w1.select(s.path("C.md"))
        let w2 = Workspace(id: id, defaults: d, recents: RecentFolders(defaults: d))
        XCTAssertEqual(w2.openTabs.map(\.lastPathComponent), ["A.md", "B.md", "C.md"])
        XCTAssertEqual(w2.document.url?.lastPathComponent, "C.md")
    }

    func testSameTitleInTwoFoldersShowsTheFolder() throws {
        try s.write("X/Notes.md", "x"); try s.write("Y/Notes.md", "y"); ws.reload()
        ws.select(s.path("X/Notes.md")); ws.select(s.path("Y/Notes.md"))
        XCTAssertEqual(ws.tabFolder(s.path("X/Notes.md")), "X")
        XCTAssertNil(ws.tabFolder(s.path("A.md")))
    }

    func testTheTagGrowsUntilTwoSameNamedTabsDiffer() throws {
        try s.write("A/Notes/Plan.md", "1"); try s.write("B/Notes/Plan.md", "2"); try s.write("B/Other/Plan.md", "3")
        ws.reload()
        for f in ["A/Notes/Plan.md", "B/Notes/Plan.md"] { ws.select(s.path(f)) }
        XCTAssertEqual(ws.tabFolder(s.path("A/Notes/Plan.md")), "A/Notes")
        XCTAssertEqual(ws.tabFolder(s.path("B/Notes/Plan.md")), "B/Notes")
        ws.select(s.path("B/Other/Plan.md"))
        XCTAssertEqual(ws.tabFolder(s.path("B/Other/Plan.md")), "Other", "one level is enough here")
        ws.closeTab(s.path("A/Notes/Plan.md"))
        XCTAssertEqual(ws.tabFolder(s.path("B/Notes/Plan.md")), "Notes")
    }

    func testSameNameInOneFolderIsToldApartByExtension() throws {
        try s.write("Plan.md", "1"); try s.write("Plan.txt", "2"); ws.reload()
        ws.select(s.path("Plan.md")); ws.select(s.path("Plan.txt"))
        XCTAssertEqual(ws.tabFolder(s.path("Plan.txt")), ".txt")
        XCTAssertEqual(ws.tabFolder(s.path("Plan.md")), ".md")
    }

    func testTwinsWithDifferentIconsNeedNoTag() throws {
        try s.write("index.html", "<p>"); try s.write("index.json", "{}"); try s.write("index.md", "x"); ws.reload()
        for f in ["index.html", "index.json", "index.md"] { ws.select(s.path(f)) }
        XCTAssertNil(ws.tabFolder(s.path("index.html")))
        XCTAssertNil(ws.tabFolder(s.path("index.json")))
        XCTAssertNil(ws.tabFolder(s.path("index.md")))
    }

    func testFilesWithAnIconShowWithoutTheirExtension() throws {
        try s.write("page.html", "<p>"); try s.write("data.json", "{}"); try s.write("cfg.yaml", "a: 1"); try s.write("pic.png", Data([1])); try s.write("report.pdf", Data([1])); ws.reload()
        func label(_ f: String) -> String? { ws.root?.find(s.path(f))?.label }
        XCTAssertEqual(label("A.md"), "A"); XCTAssertEqual(label("page.html"), "page")
        XCTAssertEqual(label("data.json"), "data"); XCTAssertEqual(label("cfg.yaml"), "cfg")
        XCTAssertEqual(label("pic.png"), "pic.png", "a plain page icon says nothing, so the extension stays")
        XCTAssertEqual(label("report.pdf"), "report.pdf")
        XCTAssertEqual(ws.root?.find(s.path("page.html"))?.name, "page.html", "the real name is unchanged, for rename and search")
    }

    func testCloseTabHasACommandAndNoShortcutClashes() {
        let cmds = makeCommands(ws: ws, prefs: Preferences.shared, recents: RecentFolders.shared, newWindow: { _ in })
        XCTAssertEqual(cmds.first { $0.id == "close-tab" }?.shortcut, "⌘W")
        XCTAssertEqual(cmds.first { $0.id == "next-tab" }?.shortcut, "⇧⌘]")
        XCTAssertEqual(cmds.first { $0.id == "previous-tab" }?.shortcut, "⇧⌘[")
        let keys = cmds.filter { $0.key != nil }.map(\.shortcut)
        XCTAssertEqual(Set(keys).count, keys.count)
    }
}
