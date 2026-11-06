import XCTest
@testable import MDEdit

/// Shell commands were removed (plan 007): what they left behind is cleaned up once, and nothing answers ⌘R.
@MainActor
final class RemovedShellTests: XCTestCase {
    private let oldKeys = ["shellEnabled", "shellPath", "shellSearchPath", "shellEnvironment", "shellTimeout", "shellHistory", "shellDestination"]

    func testOldShellSettingsAreRemovedOnceAndOtherSettingsStay() {
        let d = isolatedDefaults()
        for k in oldKeys { d.set("x", forKey: k) }
        d.set(["Script.sh": "abc"], forKey: "shellApproved:/Users/someone/notes")
        d.set(18.0, forKey: "editorSize"); d.set("light", forKey: "theme")
        _ = Preferences(defaults: d)
        for k in oldKeys { XCTAssertNil(d.object(forKey: k), k) }
        XCTAssertNil(d.object(forKey: "shellApproved:/Users/someone/notes"))
        XCTAssertEqual(d.double(forKey: "editorSize"), 18.0); XCTAssertEqual(d.string(forKey: "theme"), "light")
        // the clean-up ran: it does not run again, so a key set later is not touched by it
        d.set("later", forKey: "shellPath")
        _ = Preferences(defaults: d)
        XCTAssertEqual(d.string(forKey: "shellPath"), "later")
    }

    func testASavedRunTabOpensAsTheOutline() {
        let d = isolatedDefaults()
        d.set("run", forKey: "rightPanelTab"); d.set(true, forKey: "rightPanelOpen")
        XCTAssertEqual(Workspace(defaults: d, recents: RecentFolders(defaults: d)).panel, .outline)
    }

    func testNoCommandAnswersCommandR() {
        let d = isolatedDefaults()
        let ws = Workspace(defaults: d, recents: RecentFolders(defaults: d))
        let cmds = makeCommands(ws: ws, prefs: Preferences(defaults: d), recents: RecentFolders(defaults: d), newWindow: { _ in })
        XCTAssertNil(cmds.first { $0.shortcut == "⌘R" })
        XCTAssertEqual(cmds.first { $0.id == "rename" }?.shortcut, "⌥⌘R", "rename keeps its own shortcut")
    }
}
