import XCTest
import AppKit
@testable import MDEdit

/// The folder search and replace on real files, and the panel's model working a real editor in a real window.
@MainActor
final class FindReplaceTests: XCTestCase {
    var s: Scratch!
    var ws: Workspace!
    var window: NSWindow!
    var tv: EditorTextView!
    private var coordinator: AnyObject?

    override func setUpWithError() throws {
        s = try Scratch([
            "Draft/DORA.md": "Intro\n- **Time to restore** is key\n| Time to restore | x |\nimprove time to restore.\n",
            "Ideas/Teams.md": "Track time to restore per team\n> “Time to restore is a team sport.”\n",
            "Ideas/Sub/Deep.md": "time to restore here\n",
            "Other.md": "nothing to see\n",
            "Note.md": "alpha beta alpha\nalpha\n",
            "pic.png": Data([1, 2, 3]),
        ])
        ws = makeWorkspace(open: s.url)
        ws.select(s.path("Note.md"))
        tv = EditorTextView()
        tv.isRichText = false; tv.allowsUndo = true
        tv.textContainer?.lineFragmentPadding = 0
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scroll.documentView = tv
        tv.isVerticallyResizable = true; tv.autoresizingMask = [.width]; tv.textContainer?.widthTracksTextView = true
        let style = EditorStyle(fontName: "IBM Plex Mono", size: 16, lineWidth: 72)
        tv.style = style
        let c = MarkdownTextEditor(text: .constant(""), style: style).makeCoordinator()
        tv.delegate = c; coordinator = c
        tv.font = tv.baseFont; tv.string = ws.document.text; tv.restyle()
        window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(tv)
        ws.editor.textView = tv
    }

    override func tearDown() {
        tv.delegate = nil; window.close()
        ws = nil; s.remove()
    }

    private func settle(_ seconds: TimeInterval = 0.6) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }
    }
    private func waitSearch() {
        let end = Date().addingTimeInterval(10)
        repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) } while ws.find.busy && Date() < end
    }
    private func folderSearch(_ q: String, rep: String = "", _ o: FindOptions = FindOptions()) {
        ws.showFind(.folder)
        ws.find.options = o; ws.find.replacement = rep; ws.find.query = q
        waitSearch()
    }
    private let ttr = FindOptions(matchCase: false)

    // MARK: the folder

    func testFolderSearchFindsEveryNoteWithTheCountsAndFoldersOnTheDesign() {
        folderSearch("time to restore")
        let g = ws.find.groups
        XCTAssertEqual(g.map(\.name).sorted(), ["DORA", "Deep", "Teams"])
        XCTAssertEqual(g.first { $0.name == "DORA" }?.matches.map(\.line), [2, 3, 4])
        XCTAssertEqual(g.first { $0.name == "Teams" }?.folder, "Ideas")
        XCTAssertEqual(g.first { $0.name == "Deep" }?.folder, "Ideas/Sub")
        XCTAssertEqual(ws.find.totalCount, 6)
    }

    func testSearchInTheNotesFolderStaysInThatFolderAndBelow() {
        ws.select(s.path("Ideas/Teams.md"))
        ws.showFind(.folder); ws.find.area = .noteFolder; ws.find.query = "time to restore"; waitSearch()
        XCTAssertEqual(ws.find.groups.map(\.name).sorted(), ["Deep", "Teams"])
    }

    func testNonNotesAreNotSearched() throws {
        try s.write("data.csv", "time to restore"); ws.reload()
        folderSearch("time to restore")
        XCTAssertFalse(ws.find.groups.contains { $0.url.lastPathComponent == "data.csv" })
    }

    func testReplaceInFolderChangesOnlyTheCheckedMatches() throws {
        folderSearch("time to restore", rep: "recovery time")
        let dora = try XCTUnwrap(ws.find.groups.first { $0.name == "DORA" })
        ws.find.toggle(dora.url, dora.matches[1])                         // leave line 3 alone
        let teams = try XCTUnwrap(ws.find.groups.first { $0.name == "Teams" })
        ws.find.toggleFile(teams)                                          // and the whole of Teams
        XCTAssertEqual(ws.find.selectedCount, 3, "6 matches, one unchecked in DORA, two in Teams")
        ws.find.replaceSelected()
        XCTAssertEqual(try s.read("Draft/DORA.md"), "Intro\n- **recovery time** is key\n| Time to restore | x |\nimprove recovery time.\n")
        XCTAssertEqual(try s.read("Ideas/Teams.md"), "Track time to restore per team\n> “Time to restore is a team sport.”\n")
        XCTAssertEqual(try s.read("Ideas/Sub/Deep.md"), "recovery time here\n")
        XCTAssertTrue(ws.find.note?.hasPrefix("Replaced 3 in 2 files") == true, ws.find.note ?? "nil")
    }

    func testPreserveCaseAcrossFiles() throws {
        folderSearch("time to restore", rep: "failed deployment recovery time", FindOptions(preserveCase: true))
        ws.find.replaceSelected()
        XCTAssertEqual(try s.read("Ideas/Sub/Deep.md"), "failed deployment recovery time here\n")
        XCTAssertTrue(try s.read("Draft/DORA.md").contains("**Failed deployment recovery time**"))
    }

    func testUndoPutsEveryFileBackExactly() throws {
        let before = try ["Draft/DORA.md", "Ideas/Teams.md", "Ideas/Sub/Deep.md"].map { try s.data($0) }
        folderSearch("time to restore", rep: "X")
        ws.find.replaceSelected()
        XCTAssertNotEqual(try s.data("Ideas/Sub/Deep.md"), before[2])
        XCTAssertTrue(ws.find.canUndo)
        ws.find.undoLast(); settle(0.3)
        XCTAssertEqual(try ["Draft/DORA.md", "Ideas/Teams.md", "Ideas/Sub/Deep.md"].map { try s.data($0) }, before)
    }

    func testUndoSkipsAFileChangedSinceTheReplace() throws {
        folderSearch("time to restore", rep: "X")
        ws.find.replaceSelected()
        try s.write("Ideas/Sub/Deep.md", "edited by hand\n")
        ws.find.undoLast(); settle(0.3)
        XCTAssertEqual(try s.read("Ideas/Sub/Deep.md"), "edited by hand\n", "a later edit is never overwritten")
        XCTAssertFalse(try s.read("Draft/DORA.md").contains("X is"), "the others were still restored") 
        XCTAssertTrue(ws.find.note?.contains("skipped") == true)
    }

    func testAFileChangedAfterTheSearchIsSkippedNotCorrupted() throws {
        folderSearch("time to restore", rep: "X")
        try s.write("Ideas/Sub/Deep.md", "a time to restore moved\nand time to restore\n")   // the match moved
        ws.find.replaceSelected()
        XCTAssertEqual(try s.read("Ideas/Sub/Deep.md"), "a time to restore moved\nand time to restore\n")
        XCTAssertTrue(ws.find.note?.contains("changed since the search") == true, ws.find.note ?? "nil")
    }

    func testEncodingAndByteOrderMarkSurviveAReplace() throws {
        let latin = Data(Array("caf".utf8) + [0xE9] + Array(" time to restore\n".utf8))
        try s.write("latin.txt", latin)
        try s.write("bom.md", Data([0xEF, 0xBB, 0xBF]) + Data("time to restore\n".utf8))
        ws.reload(); folderSearch("time to restore", rep: "ok")
        ws.find.replaceSelected()
        XCTAssertEqual(try s.data("latin.txt"), Data(Array("caf".utf8) + [0xE9] + Array(" ok\n".utf8)), "still Latin-1")
        XCTAssertEqual(try s.data("bom.md"), Data([0xEF, 0xBB, 0xBF]) + Data("ok\n".utf8), "BOM kept")
    }

    func testTheOpenNoteIsReplacedThroughTheEditorWithOneUndo() throws {
        ws.select(s.path("Draft/DORA.md")); tv.string = ws.document.text
        ws.find.refresh()
        folderSearch("time to restore", rep: "X")
        ws.find.replaceSelected()
        XCTAssertFalse(tv.string.lowercased().contains("time to restore"))
        XCTAssertEqual(try s.read("Ideas/Sub/Deep.md"), "X here\n")
        tv.undoManager?.undo(); settle(0.3)
        XCTAssertTrue(tv.string.contains("Time to restore"), "the open note is back")
        XCTAssertEqual(try s.read("Ideas/Sub/Deep.md"), "time to restore here\n", "one undo takes back the other files too")
    }

    func testHostileNamesAndPathsAreHandled() throws {
        try s.write("we ird/na\"me $(touch pwn).md", "time to restore\n"); ws.reload()
        folderSearch("time to restore", rep: "ok"); ws.find.replaceSelected()
        XCTAssertEqual(try s.read("we ird/na\"me $(touch pwn).md"), "ok\n")
        XCTAssertFalse(s.exists("pwn"))
    }

    func testASymlinkOutOfTheFolderIsNotFollowed() throws {
        let outside = try Scratch(["secret.md": "time to restore\n"]); addTeardownBlock { outside.remove() }
        try FileManager.default.createSymbolicLink(at: s.path("link.md"), withDestinationURL: outside.path("secret.md"))
        ws.reload(); folderSearch("time to restore", rep: "pwned"); ws.find.replaceSelected()
        XCTAssertEqual(try outside.read("secret.md"), "time to restore\n")
    }

    func testAnInvalidPatternReportsAndChangesNothing() throws {
        folderSearch("(oops", FindOptions(regex: true))
        XCTAssertNotNil(ws.find.problem); XCTAssertTrue(ws.find.groups.isEmpty)
        ws.find.replaceSelected()
        XCTAssertEqual(try s.read("Ideas/Sub/Deep.md"), "time to restore here\n")
    }

    // MARK: this file

    func testThisFileCountsMatchesAndStepsThroughThemWrappingRound() {
        ws.showFind(.file); ws.find.query = "alpha"
        XCTAssertEqual(ws.find.matches.map(\.line), [1, 1, 2])
        XCTAssertEqual(ws.find.current, 0)
        ws.find.next(); XCTAssertEqual(ws.find.current, 1)
        ws.find.next(); ws.find.next(); XCTAssertEqual(ws.find.current, 0, "wraps")
        ws.find.next(-1); XCTAssertEqual(ws.find.current, 2, "and back")
    }

    func testReplaceCurrentChangesOneMatchAndMovesOn() {
        ws.showFind(.file); ws.find.query = "alpha"; ws.find.replacement = "OMEGA"
        ws.find.next()                                      // second alpha
        ws.find.replaceCurrent(); settle(0.1)
        XCTAssertEqual(tv.string, "alpha beta OMEGA\nalpha\n")
        ws.document.text = tv.string       // the app binds the editor to the document; this test's editor is not bound
        ws.find.refresh()
        XCTAssertEqual(ws.find.matches.count, 2)
    }

    func testReplaceAllIsOneUndoStep() {
        ws.showFind(.file); ws.find.query = "alpha"; ws.find.replacement = "Z"
        ws.find.replaceAllInFile(); settle(0.1)
        XCTAssertEqual(tv.string, "Z beta Z\nZ\n")
        tv.undoManager?.undo(); settle(0.1)
        XCTAssertEqual(tv.string, "alpha beta alpha\nalpha\n")
    }

    func testMatchesAreMarkedInTheEditorAndClearedWhenThePanelCloses() throws {
        ws.showFind(.file); ws.find.query = "alpha"
        let lm = try XCTUnwrap(tv.layoutManager)
        func marked(_ i: Int) -> NSColor? { lm.temporaryAttribute(.backgroundColor, atCharacterIndex: i, effectiveRange: nil) as? NSColor }
        XCTAssertEqual(marked(0), Palette.findCurrent)
        XCTAssertEqual(marked(11), Palette.findMatch)
        XCTAssertNil(marked(6), "the text between is not marked")
        XCTAssertEqual(tv.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor, nil, "the note's own text is not touched")
        ws.closeFind()
        XCTAssertNil(marked(0))
    }

    func testTheSelectedTextBecomesTheQuery() {
        tv.setSelectedRange(NSRange(location: 6, length: 4))   // "beta"
        ws.showFind(.file)
        XCTAssertEqual(ws.find.query, "beta")
    }

    func testTheOutlineAndFindShareOnePanelOfOneWidth() {
        ws.outlineVisible = true
        let w = ws.rightPanelWidth
        XCTAssertGreaterThan(w, 0)
        ws.showFind(.file); XCTAssertEqual(ws.rightPanelWidth, w, "switching tabs does not change the width")
        ws.closeFind(); XCTAssertTrue(ws.outlineVisible, "the outline comes back as it was"); XCTAssertEqual(ws.rightPanelWidth, w)
        ws.showFind(.file); ws.toggleOutline()
        XCTAssertFalse(ws.findVisible); XCTAssertTrue(ws.outlineVisible)
    }

    func testCommandsAndKeys() {
        let cmds = makeCommands(ws: ws, prefs: Preferences(), recents: RecentFolders(), newWindow: { _ in })
        func key(_ id: String) -> String? { cmds.first { $0.id == id }?.shortcut }
        XCTAssertEqual(key("find"), "⌘F"); XCTAssertEqual(key("replace"), "⌥⌘F"); XCTAssertEqual(key("find-folder"), "⇧⌘F")
        XCTAssertEqual(key("find-next"), "⌘G"); XCTAssertEqual(key("find-previous"), "⇧⌘G")
        cmds.first { $0.id == "find-folder" }!.run()
        XCTAssertTrue(ws.findVisible); XCTAssertEqual(ws.find.scope, .folder)
    }
}
