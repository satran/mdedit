import XCTest
@testable import MDEdit

@MainActor
final class HelpTests: XCTestCase {
    private var commands: [Cmd] { makeCommands(ws: nil, prefs: Preferences(), recents: RecentFolders(), newWindow: { _ in }) }
    private var pages: [HelpManual.Page] { HelpManual.pages(commands: commands) }

    func testTheManualShipsInTheAppAndHasTheMainTopics() {
        let titles = pages.map(\.title)
        for t in ["Getting started", "The window", "Writing", "Viewing", "Running shell commands", "Settings", "Keyboard shortcuts", "Troubleshooting"] {
            XCTAssertTrue(titles.contains(t), "no page called \(t)")
        }
        XCTAssertGreaterThan(HelpManual.source.count, 8_000, "the manual file is missing or empty")
        XCTAssertEqual(Set(titles).count, titles.count, "two pages share a title")
    }

    func testEveryPageHasContentAndParses() {
        for p in pages {
            XCTAssertGreaterThan(p.markdown.count, 60, p.title)
            XCTAssertFalse(ViewerParser.parse(p.markdown).isEmpty, p.title)
        }
    }

    func testShortcutsPageListsEveryKeyedCommandWithItsRealKey() {
        let page = pages.first { $0.title == "Keyboard shortcuts" }!
        for c in commands where c.key != nil { XCTAssertTrue(page.markdown.contains("| \(c.title) | \(c.shortcut) |"), c.title) }
        XCTAssertTrue(page.markdown.contains("| Forward to Next Note | ⌘] |"))
    }

    func testWrittenShortcutsAgreeWithTheMenus() {
        let keys = Dictionary(uniqueKeysWithValues: commands.filter { $0.key != nil }.map { ($0.title, $0.shortcut) })
        let text = HelpManual.source
        XCTAssertTrue(text.contains("(\(keys["Back to Previous Note"]!))"), "Back")
        XCTAssertTrue(text.contains("(\(keys["Forward to Next Note"]!))"), "Forward")
        XCTAssertTrue(text.contains("Press \(keys["Run Shell Command…"]!) in the editor"), "Run Shell Command")
        XCTAssertTrue(text.contains(keys["Rename"]!), "Rename")
        XCTAssertTrue(text.contains(keys["Command Palette…"]!), "Palette")
        for t in ["Bold", "Italic", "Inline Code", "Link", "Heading 1", "Task List"] { XCTAssertTrue(text.contains(keys[t]!), t) }
    }

    func testSplitsOnSecondLevelHeadingsOnly() {
        let p = HelpManual.pages(source: "# T\n\nintro\n\n## One\n\na\n\n### Sub\n\nb\n\n## Two\n\nc", commands: [])
        XCTAssertEqual(p.map(\.title), ["One", "Two"])
        XCTAssertTrue(p[0].markdown.contains("### Sub"))
    }
}
