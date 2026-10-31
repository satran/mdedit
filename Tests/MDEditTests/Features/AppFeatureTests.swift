import XCTest
import SwiftUI
@testable import MDEdit

/// One test per user-visible feature that is not covered by a more specific suite.
final class AppFeatureTests: XCTestCase {

    // MARK: recent folders

    func testRecentFoldersKeepNewestFirstWithoutDuplicatesAndAreLimited() throws {
        let recents = RecentFolders(defaults: isolatedDefaults())
        var scratches: [Scratch] = []
        defer { scratches.forEach { $0.remove() } }
        for _ in 0..<14 { let s = try Scratch(); scratches.append(s); recents.add(s.url) }
        XCTAssertEqual(recents.items.count, 10)
        XCTAssertEqual(recents.items.first?.path, scratches.last!.url.standardizedFileURL.path)
        recents.add(scratches[10].url)
        XCTAssertEqual(recents.items.first?.path, scratches[10].url.standardizedFileURL.path)
        XCTAssertEqual(Set(recents.items.map(\.path)).count, recents.items.count)
    }

    func testRecentFoldersSurviveARestartAndForgetMissingFolders() throws {
        let d = isolatedDefaults()
        let s = try Scratch()
        RecentFolders(defaults: d).add(s.url)
        let again = RecentFolders(defaults: d)
        XCTAssertEqual(again.items.count, 1)
        XCTAssertNotNil(again.resolve(again.items[0]))
        s.remove()
        XCTAssertNil(again.resolve(again.items[0]))
        XCTAssertTrue(again.items.isEmpty, "a folder that is gone drops off the list")
    }

    func testRecentFoldersClearAndCorruptStorage() {
        let d = isolatedDefaults()
        d.set(Data([1, 2, 3]), forKey: "recentFolders")
        let r = RecentFolders(defaults: d)
        XCTAssertTrue(r.items.isEmpty, "garbage in the settings is ignored")
        r.clear()
        XCTAssertTrue(r.items.isEmpty)
    }

    func testOpeningAFolderIsRemembered() throws {
        let s = try Scratch(["a.md": "x"]); defer { s.remove() }
        let d = isolatedDefaults(), recents = RecentFolders(defaults: d)
        let ws = Workspace(defaults: d, recents: recents)
        ws.open(s.url)
        XCTAssertEqual(recents.items.first?.path, s.url.standardizedFileURL.path)
    }

    // MARK: windows

    func testSecondFolderGoesToANewWindowAndFirstFillsAnEmptyOne() throws {
        let a = try Scratch(["a.md": "a"]), b = try Scratch(["b.md": "b"]); defer { a.remove(); b.remove() }
        let ws = makeWorkspace()
        var opened: [UUID] = []
        ws.newWindow = { opened.append($0) }
        ws.openFolder(a.url)
        XCTAssertEqual(ws.rootURL?.standardizedFileURL.path, a.url.standardizedFileURL.path)
        XCTAssertTrue(opened.isEmpty, "an empty window takes the folder itself")
        ws.openFolder(b.url)
        XCTAssertEqual(opened.count, 1, "a window that already has a folder opens another")
        XCTAssertEqual(ws.rootURL?.standardizedFileURL.path, a.url.standardizedFileURL.path, "and keeps its own")
    }

    func testANewWindowOnTheSameFolder() throws {
        let a = try Scratch(["a.md": "a"]); defer { a.remove() }
        let ws = makeWorkspace(open: a.url)
        var opened = 0
        ws.newWindow = { _ in opened += 1 }
        ws.openInNewWindow()
        XCTAssertEqual(opened, 1)
        let empty = makeWorkspace(); empty.newWindow = { _ in opened += 1 }
        empty.openInNewWindow()
        XCTAssertEqual(opened, 1, "nothing to duplicate")
    }

    func testAWindowComesBackWithItsFolderAndNote() throws {
        let a = try Scratch(["a.md": "a", "b.md": "b"]); defer { a.remove() }
        let d = isolatedDefaults(), id = UUID()
        let first = Workspace(id: id, defaults: d, recents: RecentFolders(defaults: d))
        first.openFolder(a.url)
        first.select(a.path("b.md"))
        let back = Workspace(id: id, defaults: d, recents: RecentFolders(defaults: d))
        XCTAssertEqual(back.rootURL?.standardizedFileURL.path, a.url.standardizedFileURL.path)
        XCTAssertEqual(back.document.url?.lastPathComponent, "b.md")
        let other = Workspace(id: UUID(), defaults: d, recents: RecentFolders(defaults: d))
        XCTAssertNil(other.rootURL, "another window has its own state")
    }

    func testExpandedFoldersAreRemembered() throws {
        let a = try Scratch(["F/x.md": "x", "G/y.md": "y"]); defer { a.remove() }
        let d = isolatedDefaults()
        let w1 = Workspace(defaults: d, recents: RecentFolders(defaults: d))
        w1.open(a.url); w1.toggle(a.path("F"))
        let w2 = Workspace(defaults: d, recents: RecentFolders(defaults: d))
        w2.open(a.url)
        XCTAssertTrue(w2.expanded.contains(a.path("F")))
        XCTAssertFalse(w2.expanded.contains(a.path("G")))
    }

    // MARK: preferences

    func testPreferencesHaveSaneDefaultsAndPersist() {
        let d = isolatedDefaults()
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.theme, "auto"); XCTAssertFalse(p.headingSizes, "headings are body size by default"); XCTAssertTrue(p.focusFullScreen)
        XCTAssertTrue(p.showStatusBar); XCTAssertFalse(p.loadRemoteImages, "remote pictures are off until asked for")
        p.theme = "dark"; p.editorSize = 20; p.headingSizes = false; p.loadRemoteImages = true; p.showStatusBar = false
        let q = Preferences(defaults: d)
        XCTAssertEqual(q.theme, "dark"); XCTAssertEqual(q.editorSize, 20); XCTAssertFalse(q.headingSizes)
        XCTAssertTrue(q.loadRemoteImages); XCTAssertFalse(q.showStatusBar)
    }

    func testAbsurdStoredPreferencesAreClamped() {
        let d = isolatedDefaults()
        d.set(1e9, forKey: "editorSize"); d.set(-5, forKey: "lineWidth"); d.set(0.0, forKey: "viewerSize"); d.set("<script>", forKey: "theme")
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.editorSize, 72); XCTAssertEqual(p.lineWidth, 20); XCTAssertEqual(p.viewerSize, 14); XCTAssertEqual(p.theme, "auto")
    }

    func testMissingFontsFallBack() {
        let p = Preferences(defaults: isolatedDefaults())
        p.editorFont = "No Such Font"
        XCTAssertGreaterThan(p.editorNSFont().pointSize, 0)
        // Literata and Inter fall back to the system serif and sans when they are not installed
        for t in ["serif", "sans"] {
            p.viewerTemplate = t
            XCTAssertGreaterThan(p.viewerStyle.nsFont(16, weight: .semibold).pointSize, 0)
            XCTAssertGreaterThan(p.viewerStyle.lineSpacing(size: 16, leading: 1.5), -1)
        }
    }

    // MARK: command palette and menus

    @MainActor func testPaletteFilterMatchesEveryWordInAnyOrderIgnoringCase() {
        let cmds = makeCommands(ws: nil, prefs: Preferences(defaults: isolatedDefaults()), recents: RecentFolders(defaults: isolatedDefaults()), newWindow: { _ in })
        func titles(_ q: String) -> [String] { PaletteView.filter(cmds, q).map(\.title) }
        XCTAssertTrue(titles("binder").contains { $0.contains("Binder") })
        XCTAssertEqual(titles("BINDER search"), ["Search Binder"])
        XCTAssertEqual(titles("search binder"), ["Search Binder"])
        XCTAssertEqual(titles("zzzz"), [])
        XCTAssertEqual(titles("").count, cmds.count)
        XCTAssertEqual(titles("   ").count, cmds.count)
    }

    @MainActor func testCommandsThatNeedAWindowAreDisabledWithoutOne() {
        let cmds = makeCommands(ws: nil, prefs: Preferences(defaults: isolatedDefaults()), recents: RecentFolders(defaults: isolatedDefaults()), newWindow: { _ in })
        for id in ["new-doc", "new-folder", "rename", "trash", "print", "binder", "search", "outline", "write", "view", "focus", "typewriter", "palette"] {
            XCTAssertEqual(cmds.first { $0.id == id }?.enabled, false, id)
        }
        XCTAssertEqual(cmds.first { $0.id == "open" }?.enabled, true)
    }

    @MainActor func testCommandsFollowTheWorkspaceState() throws {
        let s = try Scratch(["a.md": "a"]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url)
        let prefs = Preferences(defaults: isolatedDefaults())
        func cmds() -> [Cmd] { makeCommands(ws: ws, prefs: prefs, recents: RecentFolders(defaults: isolatedDefaults()), newWindow: { _ in }) }
        XCTAssertEqual(cmds().first { $0.id == "new-doc" }?.enabled, true)
        XCTAssertEqual(cmds().first { $0.id == "binder" }?.title, "Hide Binder")
        ws.binderVisible = false
        XCTAssertEqual(cmds().first { $0.id == "binder" }?.title, "Show Binder")
        XCTAssertEqual(cmds().first { $0.id == "status" }?.title, "Hide Status Bar")
        prefs.showStatusBar = false
        XCTAssertEqual(cmds().first { $0.id == "status" }?.title, "Show Status Bar")
        ws.mode = .view
        XCTAssertEqual(cmds().first { $0.id == "preview" }?.title, "Back to Writing")
    }

    @MainActor func testCommandIDsAndShortcutsNeverClash() {
        let cmds = makeCommands(ws: nil, prefs: Preferences(defaults: isolatedDefaults()), recents: RecentFolders(defaults: isolatedDefaults()), newWindow: { _ in })
        XCTAssertEqual(Set(cmds.map(\.id)).count, cmds.count)
        let keys = cmds.filter { $0.key != nil }.map(\.shortcut)
        XCTAssertEqual(Set(keys).count, keys.count, "two commands share a shortcut: \(keys.sorted())")
        // shortcuts the system or text editing already owns
        for taken in ["⌘C", "⌘V", "⌘X", "⌘Z", "⌘A", "⌘Q", "⌘W", "⌘H", "⌘M", "⌘S", "⌘,"] { XCTAssertFalse(keys.contains(taken), taken) }
    }

    @MainActor func testRecentFoldersAppearInThePalette() throws {
        let s = try Scratch(); defer { s.remove() }
        let recents = RecentFolders(defaults: isolatedDefaults()); recents.add(s.url)
        let cmds = makeCommands(ws: nil, prefs: Preferences(defaults: isolatedDefaults()), recents: recents, newWindow: { _ in })
        XCTAssertTrue(cmds.contains { $0.title == "Open Recent: " + s.url.lastPathComponent })
    }

    // MARK: window layout and toggles

    func testFocusSearchShowsAHiddenBinder() {
        let ws = makeWorkspace()
        ws.binderVisible = false
        ws.focusSearch()
        XCTAssertTrue(ws.binderVisible); XCTAssertTrue(ws.wantsSearchFocus); XCTAssertFalse(ws.wantsTreeFocus)
    }

    func testShowingTheBinderAsksForTheListToTakeFocus() {
        let ws = makeWorkspace()
        ws.binderVisible = false
        ws.toggleBinder()
        XCTAssertTrue(ws.binderVisible); XCTAssertTrue(ws.wantsTreeFocus)
        ws.toggleBinder()
        XCTAssertFalse(ws.binderVisible)
    }

    func testOutlineToggleRemembersItself() {
        let d = isolatedDefaults()
        let ws = Workspace(defaults: d, recents: RecentFolders(defaults: d))
        XCTAssertFalse(ws.outlineVisible)
        ws.toggleOutline()
        XCTAssertTrue(Workspace(defaults: d, recents: RecentFolders(defaults: d)).outlineVisible)
    }

    // MARK: outline, backlinks, search

    func testOutlineListsHeadingsAndSkipsCodeAndFrontMatter() {
        let md = "---\ntitle: T\n# not a heading\n---\n# One\n```\n# in code\n```\n## Two\ntext\n###### Six\n####### Seven\n"
        let h = Outline.headings(in: md)
        XCTAssertEqual(h.map(\.title), ["One", "Two", "Six"])
        XCTAssertEqual(h.map(\.level), [1, 2, 6])
    }

    func testBinderSearchShowsMatchesAndTheirFolders() throws {
        let s = try Scratch(["Work/Plan.md": "x", "Work/Notes/Plan B.md": "x", "Home/Other.md": "x"]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url)
        ws.search = "plan"
        XCTAssertEqual(ws.rows.map(\.node.name), ["Work", "Notes", "Plan B", "Plan"])
        ws.search = "PLAN B"
        XCTAssertEqual(ws.rows.map(\.node.name), ["Work", "Notes", "Plan B"])
        ws.search = "zzz"
        XCTAssertTrue(ws.rows.isEmpty)
        ws.search = ""
        XCTAssertFalse(ws.rows.isEmpty)
    }

    func testBacklinksFindNotesThatLinkHere() async throws {
        let s = try Scratch(["Target.md": "t", "A.md": "see [[Target]]", "B.md": "see [[target|alias]]", "C.md": "nothing", "D.md": "[[Other]]"]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url)
        ws.outlineVisible = true
        ws.select(s.path("Target.md"))
        for _ in 0..<50 where ws.backlinks.count < 2 { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(ws.backlinks.map(\.lastPathComponent).sorted(), ["A.md", "B.md"])
    }

    func testWikiLinkResolutionPrefersTheNearestFolder() throws {
        let s = try Scratch(["A/Note.md": "a", "B/Note.md": "b", "B/Other.md": "o", "Top.md": "t"]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url)
        ws.select(s.path("B/Other.md"))
        XCTAssertEqual(ws.index.resolve(WikiLink(target: "Note", alias: nil), from: s.path("B/Other.md"))?.deletingLastPathComponent().lastPathComponent, "B")
        XCTAssertEqual(ws.index.resolve(WikiLink(target: "A/Note", alias: nil), from: s.path("B/Other.md"))?.deletingLastPathComponent().lastPathComponent, "A")
        XCTAssertEqual(ws.index.resolve(WikiLink(target: "note#Heading", alias: nil), from: nil) != nil, true)
        XCTAssertNil(ws.index.resolve(WikiLink(target: "Missing", alias: nil), from: nil))
        XCTAssertNil(ws.index.resolve(WikiLink(target: "../../etc/passwd", alias: nil), from: nil))
    }

    // MARK: viewer

    func testViewerKeepsEveryBlockKindAndPropertiesFirst() {
        let blocks = ViewerParser.parse("---\ntitle: T\n---\n# H\n\npara\n\n> q\n\n- a\n- b\n\n1. x\n\n```swift\nlet a = 1\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n---\n\n![alt](pic.png)\n")
        guard case .properties = blocks.first else { return XCTFail("front matter comes first") }
        var kinds: [String] = []
        for b in blocks.dropFirst() {
            switch b {
            case .heading: kinds.append("h"); case .paragraph: kinds.append("p"); case .quote: kinds.append("q"); case .list: kinds.append("l")
            case .code: kinds.append("c"); case .table: kinds.append("t"); case .rule: kinds.append("r"); case .image: kinds.append("i")
            default: kinds.append("?")
            }
        }
        XCTAssertEqual(kinds, ["h", "p", "q", "l", "l", "c", "t", "r", "i"])
    }

    func testRawHTMLInANoteIsNotRenderedAsHTMLInTheViewer() {
        let blocks = ViewerParser.parse("<script>alert(1)</script>\n\ntext <b>bold</b> <img src=x onerror=1>")
        for b in blocks {
            switch b {
            case .html(let raw): XCTAssertTrue(raw.contains("script"))   // kept as text
            case .paragraph(let a): XCTAssertTrue(String(a.characters).contains("<b>"))
            default: break
            }
        }
    }

    // MARK: quick look

    func testQuickViewHidesWithoutAPanel() {
        QuickView.shared.hide()
        XCTAssertFalse(QuickView.shared.isShowing)
    }
}
