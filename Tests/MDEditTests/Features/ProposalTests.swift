import XCTest
import AppKit
import SwiftUI
@testable import MDEdit

/// Suggestions from creation to Accept, on a real editor in a real window.
@MainActor
final class ProposalTests: XCTestCase {
    var s: Scratch!
    var windows: AgentWindows!
    var store: ProposalStore!
    var tools: AgentTools!
    var ws: Workspace!
    var tv: EditorTextView!
    var window: NSWindow!
    private var coordinator: AnyObject?

    let text = "# Notes\n\nfirst line\nsecond line\nthird line\n"

    override func setUpWithError() throws {
        s = try Scratch(["A.md": text, "B.md": "other note\n"])
        windows = AgentWindows(); store = ProposalStore(debounce: 0.05); tools = AgentTools(windows: windows, store: store)
        ws = makeWorkspace(open: s.url)
        ws.select(s.path("A.md"))
        windows.register(ws)
        tv = EditorTextView()
        tv.isRichText = false; tv.allowsUndo = true
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scroll.documentView = tv
        tv.isVerticallyResizable = true; tv.autoresizingMask = [.width]; tv.textContainer?.widthTracksTextView = true
        let style = EditorStyle(fontName: "IBM Plex Mono", size: 16, lineWidth: 72)
        tv.style = style
        let binding = Binding<String>(get: { [unowned ws] in ws!.document.text }, set: { [unowned ws] in ws!.document.text = $0 })
        let c = MarkdownTextEditor(text: binding, style: style).makeCoordinator()
        tv.delegate = c; coordinator = c
        tv.font = tv.baseFont; tv.string = ws.document.text; tv.restyle()
        window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        ws.editor.textView = tv; ws.hostWindow = window
    }

    override func tearDown() {
        tv?.delegate = nil; window?.close(); ws = nil; s.remove()
    }

    @discardableResult
    private func propose(_ old: String, _ new: String, path: String = "A.md", title: String = "t") -> Proposal {
        switch store.propose(in: ws, path: path, old: old, new: new, title: title, reason: "r", client: "test") {
        case .success(let p): return p
        case .failure(let e): XCTFail("\(e.code): \(e.message)"); fatalError()
        }
    }

    private func settle(_ seconds: TimeInterval = 0.3) {
        let e = expectation(description: "settle"); DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { e.fulfill() }; wait(for: [e], timeout: seconds + 3)
    }

    // MARK: normal use

    func testAcceptReplacesTheTextInOneUndoableStep() async {
        let p = propose("second line", "2nd line")
        let outcome = await store.accept(p.id)
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(ws.document.text, "# Notes\n\nfirst line\n2nd line\nthird line\n")
        XCTAssertEqual(store.proposal(p.id)?.status, .accepted)
        XCTAssertEqual(tv.undoManager?.undoActionName, "Accept Suggestion")
        tv.undoManager?.undo()
        XCTAssertEqual(ws.document.text, text, "one ⌘Z restores the exact text")
        XCTAssertEqual(tv.string, text)
    }

    func testAcceptWorksWithUnsavedEditsElsewhere() async {
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.insertText("typed ", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertTrue(ws.document.dirty)
        let p = propose("third line", "3rd line")
        let outcome = await store.accept(p.id)
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(ws.document.text, "typed # Notes\n\nfirst line\nsecond line\n3rd line\n")
    }

    func testADeletionAndTheSelectionAfterwards() async {
        let p = propose("second line\n", "")
        _ = await store.accept(p.id)
        XCTAssertEqual(ws.document.text, "# Notes\n\nfirst line\nthird line\n")
        XCTAssertEqual(tv.selectedRange().length, 0)
    }

    func testTheToolsRoundTrip() {
        let r = tools.call(AgentToolCall(name: "propose_edit", arguments: ["path": "A.md", "old": "first line", "new": "1st line", "title": "T", "reason": "R"], client: "c"))
        XCTAssertFalse(r.isError, r.json)
        let id = ((try? JSONSerialization.jsonObject(with: Data(r.json.utf8))) as? [String: Any])?["id"] as? String ?? ""
        let g = tools.call(AgentToolCall(name: "get_proposal", arguments: ["id": id], client: "c"))
        XCTAssertTrue(g.json.contains("\"status\":\"pending\""), g.json)
        XCTAssertEqual(store.proposal(id)?.client, "c")
        XCTAssertEqual(store.proposal(id)?.range, (text as NSString).range(of: "first line"))
    }

    func testRejectLeavesTheNoteAlone() {
        let p = propose("first line", "x")
        store.reject(p.id)
        XCTAssertEqual(store.proposal(p.id)?.status, .rejected)
        XCTAssertEqual(ws.document.text, text)
    }

    // MARK: the stale check

    func testEditingUnderASuggestionMakesItStaleAndEditingBackRestoresIt() {
        let p = propose("second line", "2nd")
        let ns = ws.document.text as NSString
        let r = ns.range(of: "second")
        tv.insertText("SECOND", replacementRange: r)
        settle()
        XCTAssertEqual(store.proposal(p.id)?.status, .stale)
        tv.insertText("second", replacementRange: NSRange(location: r.location, length: 6))
        settle()
        XCTAssertEqual(store.proposal(p.id)?.status, .pending)
        XCTAssertEqual(store.proposal(p.id)?.range, (ws.document.text as NSString).range(of: "second line"))
    }

    func testAStaleSuggestionCannotBeAccepted() async {
        let p = propose("second line", "2nd")
        tv.insertText("changed", replacementRange: (ws.document.text as NSString).range(of: "second line"))
        try? await Task.sleep(nanoseconds: 300_000_000)
        let outcome = await store.accept(p.id)
        XCTAssertEqual(outcome, .stale)
        XCTAssertEqual(ws.document.text, "# Notes\n\nfirst line\nchanged\nthird line\n")
    }

    func testOverlappingSuggestionsAcceptingOneMakesTheOtherStale() async {
        let a = propose("first line\nsecond line", "ONE")
        let b = propose("second line\nthird line", "TWO")
        _ = await store.accept(a.id)
        XCTAssertEqual(store.proposal(b.id)?.status, .stale)
        XCTAssertEqual(ws.document.text, "# Notes\n\nONE\nthird line\n")
    }

    // MARK: failure halfway

    func testWhenTheEditorNeverAppearsTheSuggestionStaysPending() async {
        let p = propose("other note", "x", path: "B.md")
        let t0 = Date()
        let outcome = await store.accept(p.id)
        XCTAssertEqual(outcome, .blocked("Couldn't open the note."))
        XCTAssertEqual(store.proposal(p.id)?.status, .pending)
        XCTAssertEqual(store.proposal(p.id)?.message, "Couldn't open the note.")
        XCTAssertEqual(ws.document.url?.lastPathComponent, "B.md", "the note was opened")
        XCTAssertLessThan(Date().timeIntervalSince(t0), 4)
        XCTAssertEqual(try s.read("B.md"), "other note\n")
    }

    func testAChangedFileWithUnsavedEditsIsLeftAlone() async {
        tv.insertText("typed ", replacementRange: NSRange(location: 0, length: 0))
        let p = propose("first line", "x")
        ws.document.changedOnDisk = true
        let before = ws.document.text
        let outcome = await store.accept(p.id)
        if case .blocked = outcome {} else { XCTFail("expected blocked, got \(outcome)") }
        XCTAssertEqual(ws.document.text, before)
        XCTAssertEqual(store.proposal(p.id)?.status, .pending)
    }

    func testAViewThatCannotBeEditedRefusesAndChangesNothing() async {
        let p = propose("first line", "x")
        tv.isEditable = false
        let outcome = await store.accept(p.id)
        XCTAssertEqual(outcome, .blocked("The note is not editable."))
        XCTAssertEqual(ws.document.text, text)
    }

    func testClosingTheWindowWithdrawsItsSuggestions() {
        let p = propose("first line", "x")
        tv.delegate = nil; coordinator = nil; tv = nil
        window.close(); window = nil
        ws = nil
        windows = AgentWindows()
        XCTAssertEqual(store.report(p.id)?.status, "withdrawn")
    }

    func testSwitchingAccessOffWithdrawsEverything() {
        let p = propose("first line", "x")
        store.withdrawAll()
        XCTAssertEqual(store.report(p.id)?.status, "withdrawn")
    }

    func testDecidedSuggestionsAreForgottenAfterTheRetentionTime() {
        let p = propose("first line", "x")
        store.reject(p.id)
        XCTAssertNotNil(store.report(p.id))
        store.retention = -1
        XCTAssertNil(store.report(p.id))
        XCTAssertEqual(tools.call(AgentToolCall(name: "get_proposal", arguments: ["id": p.id], client: "c")).json.contains("unknown_proposal"), true)
    }

    // MARK: speed

    func testTheStaleCheckOnALargeNoteWithTwentySuggestionsIsFast() {
        let big = (0..<20_000).map { "line number \($0) of the note\n" }.joined()   // about 600 KB
        ws.document.text = big
        tv.string = big
        for i in 0..<20 { propose("line number \(i * 1_000) of the note", "x") }
        within(1, "recheck") { store.recheck(ws) }
    }
}
