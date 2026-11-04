import XCTest
import SwiftUI
@testable import MDEdit

/// One right panel with an outline tab and a find tab, and Print and Share in the toolbar.
@MainActor
final class RightPanelTests: XCTestCase {
    private var s: Scratch!
    private var d: UserDefaults!

    override func setUpWithError() throws {
        s = try Scratch(["A.md": "# Title\n\nbody text\n", "page.html": "<h1>Hi</h1>"])
        addTeardownBlock { [s] in s?.remove() }
        d = isolatedDefaults()
    }

    private func workspace() -> Workspace {
        let ws = Workspace(defaults: d, recents: RecentFolders(defaults: d))
        ws.open(s.url); ws.select(s.path("A.md"))
        return ws
    }

    func testTheToolbarButtonOpensOnTheLastTabAndCloses() {
        let ws = workspace()
        XCTAssertNil(ws.panel)
        ws.togglePanel(); XCTAssertEqual(ws.panel, .outline, "the outline the first time")
        ws.togglePanel(); XCTAssertNil(ws.panel)
        ws.showFind(.file); ws.togglePanel(); XCTAssertNil(ws.panel)
        ws.togglePanel(); XCTAssertEqual(ws.panel, .find, "opens on the tab used last")
    }

    func testTheOutlineShortcutOpensSwitchesAndCloses() {
        let ws = workspace()
        ws.toggleOutline(); XCTAssertEqual(ws.panel, .outline)
        ws.showFind(.file); XCTAssertEqual(ws.panel, .find)
        ws.toggleOutline(); XCTAssertEqual(ws.panel, .outline, "from Find it switches")
        ws.toggleOutline(); XCTAssertNil(ws.panel, "on the outline it closes")
    }

    func testEscFromFindGoesBackToWhereThePanelWas() {
        let ws = workspace()
        ws.showFind(.file); ws.closeFind(); XCTAssertNil(ws.panel, "it was closed before")
        ws.toggleOutline(); ws.showFind(.file); ws.closeFind(); XCTAssertEqual(ws.panel, .outline, "it was the outline before")
    }

    func testTheTabIconsSwitchAndLeavingFindClearsTheMarks() {
        let ws = workspace()
        ws.showFind(.file); ws.find.query = "text"; ws.find.refresh()
        ws.selectPanel(.outline)
        XCTAssertEqual(ws.panel, .outline); XCTAssertFalse(ws.findVisible)
        ws.selectPanel(.find)
        XCTAssertEqual(ws.panel, .find); XCTAssertEqual(ws.find.query, "text", "the query is still there")
    }

    func testOneWidthForBothTabsThatCanBeDraggedAndIsRemembered() {
        let ws = workspace()
        ws.togglePanel()
        let w = ws.panelWidth
        XCTAssertEqual(ws.rightPanelWidth, w + 1, "the divider is part of it")
        ws.selectPanel(.find); XCTAssertEqual(ws.panelWidth, w)
        ws.panelWidth = ws.clampedPanelWidth(430)
        XCTAssertEqual(Workspace(defaults: d, recents: RecentFolders(defaults: d)).panelWidth, 430)
        XCTAssertEqual(ws.clampedPanelWidth(10), Workspace.panelWidthRange.lowerBound)
        XCTAssertEqual(ws.clampedPanelWidth(10_000), Workspace.panelWidthRange.upperBound)
        d.set(5.0, forKey: "rightPanelWidth"); XCTAssertEqual(Workspace(defaults: d, recents: RecentFolders(defaults: d)).panelWidth, Workspace.panelWidthRange.lowerBound)
    }

    func testTheOpenOutlineAndTheLastTabAreRememberedAndTheOldSettingIsRead() {
        let ws = workspace()
        ws.toggleOutline()
        XCTAssertEqual(Workspace(defaults: d, recents: RecentFolders(defaults: d)).panel, .outline)
        ws.showFind(.file)
        let again = Workspace(defaults: d, recents: RecentFolders(defaults: d))
        XCTAssertNil(again.panel, "find does not come back open"); XCTAssertEqual(again.lastPanel, .find)
        let old = isolatedDefaults(); old.set(true, forKey: "outlineVisible")
        XCTAssertEqual(Workspace(defaults: old, recents: RecentFolders(defaults: old)).panel, .outline)
    }

    func testAPageSearchesTheFolderAndTheMinimumWidthLeavesRoomForTheToolbar() {
        let ws = workspace()
        ws.select(s.path("page.html")); ws.showFind(.file)
        XCTAssertEqual(ws.find.scope, .folder)
        XCTAssertGreaterThanOrEqual(ws.minContentWidth, 520 + ws.rightPanelWidth)
    }
}
