import XCTest
@testable import MDEdit

/// File > Open Recent and the palette's "Open Recent: …".
final class OpenRecentTests: XCTestCase {
    private func setup(_ s: Scratch) -> (Workspace, RecentFolders, UserDefaults) {
        let d = isolatedDefaults(), r = RecentFolders(defaults: d)
        return (Workspace(defaults: d, recents: r), r, d)
    }

    func testClickingARecentFolderInAWindowThatAlreadyHasOneOpensANewWindow() throws {
        let a = try Scratch(["a.md": "a"]), b = try Scratch(["b.md": "b"]); defer { a.remove(); b.remove() }
        let (ws, recents, d) = setup(a)
        ws.open(a.url); ws.open(b.url)                  // b is the folder in this window; a is in the list
        guard let item = recents.items.first(where: { $0.path == a.url.standardizedFileURL.path }) else { return XCTFail("a is in the list") }
        var opened: [UUID] = []
        ws.newWindow = { opened.append($0) }
        ws.openRecent(item)
        XCTAssertEqual(opened.count, 1, "the click opens a window")
        XCTAssertEqual(ws.rootURL?.standardizedFileURL.path, b.url.standardizedFileURL.path, "and leaves this one alone")
        let fresh = Workspace(id: opened[0], defaults: d, recents: recents)
        XCTAssertEqual(fresh.rootURL?.standardizedFileURL.path, a.url.standardizedFileURL.path, "the new window comes up on that folder")
    }

    func testClickingARecentFolderInAnEmptyWindowOpensItThere() throws {
        let a = try Scratch(["a.md": "a"]); defer { a.remove() }
        let d = isolatedDefaults(), recents = RecentFolders(defaults: d)
        Workspace(defaults: d, recents: recents).open(a.url)
        let id = UUID()
        let empty = Workspace(id: id, defaults: d, recents: recents)
        XCTAssertNil(empty.root)
        empty.openRecent(recents.items[0])
        XCTAssertEqual(empty.rootURL?.standardizedFileURL.path, a.url.standardizedFileURL.path)
        XCTAssertNotNil(empty.root)
        XCTAssertEqual(Workspace(id: id, defaults: d, recents: recents).rootURL?.standardizedFileURL.path, a.url.standardizedFileURL.path, "it is remembered for next launch")
    }

    func testAFolderThatIsGoneIsReportedAndDropped() throws {
        let a = try Scratch(["a.md": "a"])
        let (ws, recents, _) = setup(a)
        ws.open(a.url)
        let item = recents.items[0]
        a.remove()
        let other = try Scratch(); defer { other.remove() }
        let empty = Workspace(defaults: isolatedDefaults(), recents: recents)
        empty.openRecent(item)
        XCTAssertNil(empty.root); XCTAssertNotNil(empty.message, "it says what happened")
        XCTAssertTrue(recents.items.isEmpty, "and the entry is gone from the list")
    }

    func testScratchFoldersLeftByOldTestRunsDoNotShowInTheList() throws {
        let d = isolatedDefaults()
        let gone = FileManager.default.temporaryDirectory.appendingPathComponent("ws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: gone, withIntermediateDirectories: true)
        let real = try Scratch(); defer { real.remove() }
        let first = RecentFolders(defaults: d)
        first.add(gone); first.add(real.url)
        try FileManager.default.removeItem(at: gone)
        let again = RecentFolders(defaults: d)
        XCTAssertFalse(again.items.contains { $0.name.hasPrefix("ws-") }, "a deleted scratch folder is not a recent folder")
        XCTAssertEqual(again.items.count, 1)
        XCTAssertTrue(RecentFolders.isTemporary(gone.path))
        XCTAssertFalse(RecentFolders.isTemporary("/Users/someone/Documents/notes"))
        XCTAssertFalse(RecentFolders.isTemporary("/Volumes/Backup/notes"))
    }

    @MainActor func testTheMenuAndThePaletteBothOpenARecentFolder() throws {
        let a = try Scratch(["a.md": "a"]), b = try Scratch(["b.md": "b"]); defer { a.remove(); b.remove() }
        let (ws, recents, _) = setup(a)
        ws.open(a.url); ws.open(b.url)
        var opened = 0
        ws.newWindow = { _ in opened += 1 }
        let cmds = makeCommands(ws: ws, prefs: Preferences(defaults: isolatedDefaults()), recents: recents, newWindow: { _ in })
        guard let entry = cmds.first(where: { $0.title == "Open Recent: " + a.url.lastPathComponent }) else { return XCTFail("the palette lists it") }
        entry.run()
        XCTAssertEqual(opened, 1)
    }

    func testAStashedBookmarkBecomesAWindowOnThatFolder() throws {
        let a = try Scratch(["a.md": "a"]); defer { a.remove() }
        let d = isolatedDefaults(), recents = RecentFolders(defaults: d)
        Workspace(defaults: d, recents: recents).open(a.url)
        let id = Workspace.stash(bookmark: recents.items[0].bookmark, defaults: d)
        XCTAssertEqual(Workspace(id: id, defaults: d, recents: recents).rootURL?.standardizedFileURL.path, a.url.standardizedFileURL.path)
        XCTAssertNotNil(Workspace.stash(a.url, defaults: d))
    }
}
