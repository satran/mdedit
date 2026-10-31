import XCTest
import SwiftUI
@testable import MDEdit

@MainActor
final class CommandTests: XCTestCase {
    func testCommandsHaveUniqueIDsAndShortcuts() {
        let cmds = Self.make()
        XCTAssertEqual(Set(cmds.map(\.id)).count, cmds.count)
        XCTAssertEqual(cmds.first { $0.id == "palette" }?.shortcut, "⇧⌘P")
        XCTAssertEqual(cmds.first { $0.id == "search" }?.shortcut, "⇧⌘F")
        XCTAssertEqual(cmds.first { $0.id == "binder" }?.shortcut, "⌘/")
        let keys = cmds.filter { $0.key != nil }.map(\.shortcut)
        XCTAssertEqual(Set(keys).count, keys.count, "two commands share a shortcut")
    }

    func testSearchShowsTheBinderFirst() {
        let ws = Workspace()
        ws.binderVisible = false
        ws.focusSearch()
        XCTAssertTrue(ws.binderVisible)
        XCTAssertTrue(ws.wantsSearchFocus)
    }

    private static func make() -> [Cmd] {
        return makeCommands(ws: nil, prefs: Preferences(), recents: RecentFolders(), newWindow: { _ in })
    }
}
