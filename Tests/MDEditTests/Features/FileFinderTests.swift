import XCTest
import SwiftUI
@testable import MDEdit

/// ⇧⌘O: the fuzzy matcher, its speed, and opening a file from the finder.
@MainActor
final class FileFinderTests: XCTestCase {
    private func top(_ idx: FileIndex, _ q: String, _ n: Int = 5) -> [String] { idx.search(q, limit: n).map { idx.entries[$0.entry].path } }

    func testLettersMustAppearInOrder() {
        let idx = FileIndex(paths: ["Notes/Meeting.md", "Journal/2026-11-08.md", "README.md"])
        XCTAssertEqual(top(idx, "mtg"), ["Notes/Meeting.md"])
        XCTAssertEqual(top(idx, "gtm"), [], "out of order does not match")
        XCTAssertEqual(top(idx, "MEETING"), ["Notes/Meeting.md"], "case does not matter")
        XCTAssertEqual(top(idx, ""), [])
    }

    func testTheFileNameBeatsAMatchSpreadOverTheFolders() {
        let idx = FileIndex(paths: ["projects/alpha/notes/design.md", "design/archive/old/x.md", "a/design.md", "design.md"])
        XCTAssertEqual(top(idx, "design").first, "design.md", "the exact name first")
        XCTAssertEqual(Set(top(idx, "design").prefix(2)), ["design.md", "a/design.md"])
    }

    func testWordBoundariesAndRunsScoreHigher() {
        let idx = FileIndex(paths: ["weekly-review.md", "wearily-vivid-ew.md", "Archive/wrap.md"])
        XCTAssertEqual(top(idx, "wr").first, "Archive/wrap.md", "a prefix of the name")
        XCTAssertEqual(top(idx, "wkrv").first, "weekly-review.md", "letters at the start of words")
    }

    /// Letters scattered over the whole path are not a match: they must sit in the file name, or the word must appear whole.
    func testLettersPickedFromAcrossTheWholePathAreNotAMatch() {
        let idx = FileIndex(paths: ["vaults/goals/goals.md", "src/plugin/scripts/normalise.py", "src/plugin/commands/normalise.md",
                                    "vaults/personal/agenda/todos/0014-find-paper-plane-model-diagram.md", "vaults/goals/plan.md", "notes/gold-aloe.md"])
        let found = top(idx, "goals")
        XCTAssertEqual(found.first, "vaults/goals/goals.md", "the file named goals first")
        XCTAssertEqual(Set(found), ["vaults/goals/goals.md", "vaults/goals/plan.md"], "and the notes in the goals folder; nothing that only has g, o, a, l, s spread out")
        XCTAssertFalse(found.contains("src/plugin/scripts/normalise.py"))
        XCTAssertFalse(found.contains { $0.contains("0014-find") })
        XCTAssertFalse(found.contains("notes/gold-aloe.md"), "g-o-a-l-s are not all in the name in order")
        XCTAssertEqual(top(idx, "norm").count, 2, "a word in one piece matches in a name")
    }

    func testSeveralWordsMatchInAnyOrder() {
        let idx = FileIndex(paths: ["Work/2026/budget.md", "Home/budget.md", "Work/plan.md"])
        XCTAssertEqual(top(idx, "budget work"), ["Work/2026/budget.md"])
        XCTAssertEqual(top(idx, "work budget"), ["Work/2026/budget.md"])
    }

    func testNonASCIINamesMatchAndKeepTheirPositions() {
        let idx = FileIndex(paths: ["Café/Ärger.md"])
        XCTAssertEqual(top(idx, "ärg"), ["Café/Ärger.md"])
        XCTAssertEqual(top(idx, "ÄRG"), ["Café/Ärger.md"], "case folds beyond ASCII")
        XCTAssertEqual(idx.positions("ärg", in: idx.entries[0]), [5, 6, 7])
    }

    func testExtendingAQueryGivesTheSameAnswerAsAFreshOne() {
        var paths: [String] = []
        for i in 0..<400 { paths.append("folder\(i % 17)/note-\(i)-\(["alpha", "beta", "gamma"][i % 3]).md") }
        let incremental = FileIndex(paths: paths), fresh = FileIndex(paths: paths)
        for q in ["n", "no", "not", "note 1", "note 12", "note 12 al", "note 1", "n", "gam"] {
            let a = incremental.search(q, limit: 400), b = FileIndex(paths: paths).search(q, limit: 400)
            XCTAssertEqual(a, b, q)
        }
        _ = fresh
    }

    func testTheResultCountIsCappedAndBestFirst() {
        let idx = FileIndex(paths: (0..<1000).map { "dir/file\($0).md" })
        let hits = idx.search("file", limit: 20)
        XCTAssertEqual(hits.count, 20)
        XCTAssertEqual(hits.map(\.score), hits.map(\.score).sorted(by: >), "already ordered by score")
    }

    func testAHundredThousandFilesAreSearchedQuickly() {
        let paths = (0..<100_000).map { "area\($0 % 50)/project\($0 % 997)/note-\($0).md" }
        let idx = FileIndex(paths: paths)
        let t0 = Date()
        _ = idx.search("proj nt", limit: 50)
        let first = Date().timeIntervalSince(t0)
        XCTAssertLessThan(first, 0.5, "a cold search over 100,000 files")
        let t1 = Date()
        _ = idx.search("proj nt4", limit: 50)
        XCTAssertLessThan(Date().timeIntervalSince(t1), first + 0.05, "the longer query reuses the earlier matches")
    }

    func testGoToFileOpensTheNoteAndShowsItInTheBinder() throws {
        let s = try Scratch(["A.md": "# A", "Deep/Er/Target.md": "target", "pic.png": "x"]); defer { s.remove() }
        let ws = Workspace(); ws.open(s.url)
        let idx = try XCTUnwrap(ws.fileIndex())
        XCTAssertEqual(Set(idx.entries.map(\.path)), ["A.md", "Deep/Er/Target.md", "pic.png"], "every file, not only notes")
        XCTAssertTrue(ws.fileIndex() === idx, "the index is kept until the folder is read again")
        let hit = try XCTUnwrap(idx.search("tgt").first)
        ws.finderVisible = true
        ws.goToFile(idx.entries[hit.entry].url)
        XCTAssertFalse(ws.finderVisible)
        XCTAssertEqual(ws.document.url?.lastPathComponent, "Target.md")
        XCTAssertTrue(ws.expanded.contains(where: { $0.lastPathComponent == "Er" }))
        ws.reload()
        XCTAssertFalse(ws.fileIndex() === idx, "a new read gives a new index")
    }

    /// The finder always covers the whole opened folder, whatever note is open and wherever it lives.
    func testTheFinderSearchesTheWholeFolderFromAnyOpenNote() throws {
        let s = try Scratch(["Top.md": "t", "Work/Plan.md": "p", "Work/2026/Q4/Deep.md": "d", "Home/Garden/Beds.md": "b", "Home/Todo.txt": "x", "Data/table.json": "{}", "Data/pic.png": "x"])
        defer { s.remove() }
        let ws = Workspace(); ws.open(s.url)
        for start in ["Top.md", "Work/2026/Q4/Deep.md", "Home/Garden/Beds.md"] {
            ws.select(s.path(start))
            let model = FileFinderModel()
            model.load(index: ws.fileIndex(), recent: ws.visited + [ws.document.url].compactMap { $0 })
            XCTAssertEqual(model.rows.count, 7, "open note \(start): every file is listed")
            for (q, want) in [("deep", "Work/2026/Q4/Deep.md"), ("beds", "Home/Garden/Beds.md"), ("top", "Top.md"), ("pic", "Data/pic.png"), ("todo", "Home/Todo.txt")] {
                model.query = q
                XCTAssertEqual(model.rows.first.map { $0.folder + ($0.folder.isEmpty ? "" : "/") + String($0.name.characters) }, want, "open note \(start), searching \(q)")
            }
        }
    }

    /// The case from a real folder: a note in `log` is open and the search is for a note at the top.
    func testASearchFromInsideASubfolderFindsANoteAtTheTop() throws {
        var files = ["Apple care.md": "a", "Atomic Habits.md": "b", "0 Test Canvas.canvas": "{}", "Decision Log.md": "d", "false positive.md": "f"]
        for d in ["2023-07-08", "2024-03-16", "2025-02-23", "2025-11-08"] { files["log/\(d).md"] = "x" }
        let s = try Scratch(files); defer { s.remove() }
        let ws = Workspace(); ws.open(s.url)
        ws.select(s.path("log/2025-02-23.md"))
        let model = FileFinderModel()
        model.load(index: ws.fileIndex(), recent: ws.visited + [ws.document.url].compactMap { $0 })
        XCTAssertEqual(model.rows.count, files.count)
        for q in ["a", "ap", "app", "appl", "apple"] { model.query = q }
        XCTAssertEqual(model.rows.map { String($0.name.characters) }.first, "Apple care.md")
        XCTAssertFalse(model.rows.contains { String($0.name.characters) == "2025-02-23.md" }, "a note that does not match is not listed")
        model.query = "apple "
        XCTAssertEqual(model.rows.first.map { String($0.name.characters) }, "Apple care.md", "a trailing space does not change the answer")
    }

    func testTheCommandHasItsKey() {
        let cmds = makeCommands(ws: nil, prefs: Preferences(defaults: isolatedDefaults()), recents: RecentFolders(defaults: isolatedDefaults()), newWindow: { _ in })
        XCTAssertEqual(cmds.first { $0.id == "go-to-file" }?.shortcut, "⇧⌘O")
    }
}

/// What the box shows as the person types: the list must narrow to the matches, in the model and in the real view.
@MainActor
final class FileFinderBoxTests: XCTestCase {
    private func model(_ paths: [String], recent: [URL] = []) -> FileFinderModel {
        let m = FileFinderModel()
        m.load(index: FileIndex(paths: paths), recent: recent)
        return m
    }
    private func names(_ m: FileFinderModel) -> [String] { m.rows.map { String($0.name.characters) } }

    func testTypingNarrowsTheListAndClearingBringsItBack() {
        let m = model(["Notes/Meeting.md", "Journal/Daily.md", "README.md", "Notes/Ideas.md"])
        XCTAssertEqual(m.rows.count, 4, "nothing typed: every file")
        m.query = "mee"
        XCTAssertEqual(names(m), ["Meeting.md"])
        m.query = "md"
        XCTAssertEqual(m.rows.count, 4)
        m.query = "ide"
        XCTAssertEqual(names(m), ["Ideas.md"])
        m.query = "zzz"
        XCTAssertTrue(m.rows.isEmpty)
        m.query = ""
        XCTAssertEqual(m.rows.count, 4)
    }

    func testTheHighlightGoesBackToTheTopWhenTheTextChangesAndStaysInRange() {
        let m = model(["a1.md", "a2.md", "a3.md"])
        m.move(1); m.move(1); m.move(1)
        XCTAssertEqual(m.selected, 2, "stops at the last row")
        m.query = "a"
        XCTAssertEqual(m.selected, 0)
        m.move(-1)
        XCTAssertEqual(m.selected, 0, "stops at the first row")
        m.query = "a3"
        XCTAssertEqual(m.selectedURL?.lastPathComponent, "a3.md")
    }

    func testTheNotesOpenedLastComeFirstWhenNothingIsTyped() {
        let m = model(["a.md", "b.md", "c.md"], recent: [URL(fileURLWithPath: "/b.md"), URL(fileURLWithPath: "/c.md")])
        XCTAssertEqual(names(m), ["c.md", "b.md", "a.md"])
    }

    /// Types into the real text field of the real view and reads what the rows show.
    func testTypingInTheRealFieldNarrowsTheRowsOnScreen() throws {
        let s = try Scratch(["Alpha.md": "a", "Beta.md": "b", "Sub/Gamma.md": "g"]); defer { s.remove() }
        let ws = Workspace(); ws.open(s.url)
        let model = FileFinderModel()
        let host = NSHostingView(rootView: FileFinderView(model: model).environmentObject(ws).frame(width: 520, height: 400))
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.contentView = host
        win.makeKeyAndOrderFront(nil)
        func pump(_ t: TimeInterval = 0.3) { RunLoop.current.run(until: Date().addingTimeInterval(t)) }
        func field() -> NSTextField? {
            var stack: [NSView] = [host]
            while let v = stack.popLast() { if let f = v as? NSTextField, f.isEditable { return f }; stack += v.subviews }
            return nil
        }
        pump(0.5)
        let f = try XCTUnwrap(field(), "the finder has a text field")
        XCTAssertTrue(win.makeFirstResponder(f))
        pump()
        let editor = try XCTUnwrap(f.currentEditor() as? NSTextView, "the field is being edited")
        XCTAssertEqual(model.rows.count, 3, "opened: every file listed")
        editor.insertText("gam", replacementRange: NSRange(location: 0, length: 0))
        pump(0.5)
        XCTAssertEqual(f.stringValue, "gam")
        XCTAssertEqual(model.query, "gam", "the text field feeds the model")
        XCTAssertEqual(model.rows.map { $0.url.lastPathComponent }, ["Gamma.md"], "and the list narrows to the match")
        win.orderOut(nil); win.contentView = nil; win.close()
    }

    /// The text the box draws, read from the screen: after typing, only the matching file is on show, not the row that was
    /// first in the list before.
    func testTheRowsOnScreenFollowTheText() throws {
        var files = ["Apple care.md": "a", "Atomic Habits.md": "b", "Decision Log.md": "d", "false positive.md": "f"]
        for d in ["2023-07-08", "2024-03-16", "2025-02-23", "2025-11-08"] { files["log/\(d).md"] = "x" }
        let s = try Scratch(files); defer { s.remove() }
        let ws = Workspace(); ws.open(s.url)
        ws.select(s.path("log/2025-02-23.md"))
        let model = FileFinderModel()
        let host = NSHostingView(rootView: FileFinderView(model: model).environmentObject(ws).frame(width: 540, height: 420))
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.contentView = host
        win.makeKeyAndOrderFront(nil)
        func pump(_ t: TimeInterval = 0.3) { RunLoop.current.run(until: Date().addingTimeInterval(t)) }
        func field() -> NSTextField? {
            var stack: [NSView] = [host]
            while let v = stack.popLast() { if let f = v as? NSTextField, f.isEditable { return f }; stack += v.subviews }
            return nil
        }
        /// The first row's strip of the box, as sampled pixels: it must look different once the text has changed it.
        func firstRow() -> [UInt32] {
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return [] }
            host.cacheDisplay(in: host.bounds, to: rep)
            var out: [UInt32] = []
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width
            for y in stride(from: Int(76 * scale), to: Int(104 * scale), by: 1) {
                for x in stride(from: Int(24 * scale), to: Int(240 * scale), by: 1) {
                    let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                    out.append(UInt32((c?.redComponent ?? 0) * 255) << 16 | UInt32((c?.greenComponent ?? 0) * 255) << 8 | UInt32((c?.blueComponent ?? 0) * 255))
                }
            }
            return out
        }
        pump(0.5)
        let before = firstRow()
        XCTAssertFalse(before.isEmpty)
        let f = try XCTUnwrap(field())
        XCTAssertTrue(win.makeFirstResponder(f)); pump()
        let editor = try XCTUnwrap(f.currentEditor() as? NSTextView)
        for ch in "appl" { editor.insertText(String(ch), replacementRange: editor.selectedRange()); pump(0.2) }
        pump(0.5)
        XCTAssertNotEqual(firstRow(), before, "the first row is drawn again with the new match; a stale row would look the same as before")
        XCTAssertEqual(model.rows.map { String($0.name.characters) }, ["Apple care.md"])
        win.orderOut(nil); win.contentView = nil; win.close()
    }
}
