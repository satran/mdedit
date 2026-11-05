import XCTest
import AppKit
import SwiftUI
@testable import MDEdit

/// The Review tab: what it draws, how it opens and closes, and the passage painted in the editor.
@MainActor
final class ReviewPanelTests: XCTestCase {
    var s: Scratch!
    var windows: AgentWindows!
    var tools: AgentTools!
    var ws: Workspace!
    var tv: EditorTextView!
    var window: NSWindow!
    private var coordinator: AnyObject?
    private var keep: [NSWindow] = []
    let store = ProposalStore.shared
    let text = "# Notes\n\nfirst line\nsecond line\nthird line\n"

    override func setUpWithError() throws {
        s = try Scratch(["A.md": text])
        windows = AgentWindows(); tools = AgentTools(windows: windows, store: store)
        ws = makeWorkspace(open: s.url)
        ws.select(s.path("A.md")); windows.register(ws)
        tv = EditorTextView()
        tv.isRichText = false; tv.allowsUndo = true
        tv.textContainer?.lineFragmentPadding = 0
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
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        ws.editor.textView = tv; ws.hostWindow = window
    }

    override func tearDown() {
        store.withdrawAll()
        tv?.delegate = nil; window?.close(); keep.forEach { $0.close() }; ws = nil; s.remove()
    }

    @discardableResult
    private func propose(_ old: String, _ new: String, title: String = "Fix it") -> Proposal {
        switch store.propose(in: ws, path: "A.md", old: old, new: new, title: title, reason: "Because.", client: "claude-code") {
        case .success(let p): return p
        case .failure(let e): XCTFail("\(e.code)"); fatalError()
        }
    }

    private func settle(_ seconds: TimeInterval = 0.4) {
        let e = expectation(description: "settle"); DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { e.fulfill() }; wait(for: [e], timeout: seconds + 3)
    }

    private enum Tint { case removed, added }

    /// How many pixels of `view` carry the pale red of removed text or the pale green of added text (whatever the colour space
    /// does to the exact value).
    private func pixels(in view: NSView, like tint: Tint) -> Int {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
        view.cacheDisplay(in: view.bounds, to: rep)
        var n = 0
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded()), b = Int((c.blueComponent * 255).rounded())
            switch tint {
            case .removed: if r >= 0xF0, r - g >= 10, r - b >= 6, g >= 0xD0 { n += 1 }
            case .added: if g >= 0xEE, g - r >= 10, g - b >= 4, r >= 0xD0 { n += 1 }
            }
        } }
        return n
    }

    private func hostedPanel() -> NSHostingView<AnyView> {
        let v = AnyView(ReviewPanelView().environmentObject(ws).frame(width: 361, height: 600).background(Color.white))
        let h = NSHostingView(rootView: v)
        h.frame = NSRect(x: 0, y: 0, width: 361, height: 600)
        let w = NSWindow(contentRect: h.frame, styleMask: [.titled], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = h; w.makeKeyAndOrderFront(nil)
        keep.append(w)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        return h
    }

    // MARK: what it draws

    func testACardShowsTheRemovedAndAddedLines() {
        propose("second line", "2nd line")
        let h = hostedPanel()
        XCTAssertGreaterThan(pixels(in: h, like: .removed), 200, "the removed line has its tint")
        XCTAssertGreaterThan(pixels(in: h, like: .added), 200, "the added line has its tint")
    }

    func testAStaleCardAndTheEmptyState() {
        propose("second line", "2nd line")
        tv.insertText("X", replacementRange: NSRange(location: (ws.document.text as NSString).range(of: "second").location, length: 1))
        settle()
        XCTAssertEqual(store.open(in: ws).first?.status, .stale)
        XCTAssertGreaterThan(pixels(in: hostedPanel(), like: .removed), 100, "a stale card is still drawn")
        store.withdrawAll()
        let empty = hostedPanel()
        XCTAssertEqual(pixels(in: empty, like: .removed), 0)
        XCTAssertEqual(pixels(in: empty, like: .added), 0)
    }

    func testOnlyThisWindowsSuggestionsAreListed() throws {
        propose("second line", "2nd")
        let other = makeWorkspace(open: s.url); windows.register(other)
        _ = store.propose(in: other, path: "A.md", old: "third line", new: "3rd", title: "Other", reason: "", client: "c")
        XCTAssertEqual(store.open(in: ws).count, 1)
        XCTAssertEqual(store.open(in: other).count, 1)
        _ = other
    }

    // MARK: the tab

    func testReviewIsAVisitNeverSavedNeverRestored() {
        let d = isolatedDefaults()
        let w = Workspace(defaults: d, recents: RecentFolders(defaults: d))
        w.openPanel(.outline)
        w.openPanel(.review)
        XCTAssertEqual(w.panel, .review)
        XCTAssertEqual(d.string(forKey: "rightPanelTab"), "outline")
        XCTAssertEqual(d.bool(forKey: "rightPanelOpen"), false)
        XCTAssertEqual(w.lastPanel, .outline)
        d.set("review", forKey: "rightPanelTab"); d.set(true, forKey: "rightPanelOpen")
        XCTAssertEqual(Workspace(defaults: d, recents: RecentFolders(defaults: d)).panel, .outline, "a saved review tab opens as the outline")
    }

    func testClosingReviewGoesBackToWhereThePanelWas() {
        ws.openPanel(.outline)
        ws.openPanel(.review)
        ws.closeReview()
        XCTAssertEqual(ws.panel, .outline)
        ws.closePanel()
        ws.openPanel(.review)
        ws.closeReview()
        XCTAssertNil(ws.panel)
        ws.closeReview()   // not showing: nothing happens
        XCTAssertNil(ws.panel)
    }

    func testFindAndReviewShareTheWayBack() {
        ws.openPanel(.outline)
        ws.openPanel(.find)
        ws.openPanel(.review)
        ws.closeReview()
        XCTAssertEqual(ws.panel, .outline)
    }

    func testTheStatusBarCountsPendingSuggestionsOfThisWindow() {
        let a = propose("first line", "1st"); propose("third line", "3rd")
        XCTAssertEqual(store.items.filter { $0.status == .pending && $0.workspace === ws }.count, 2)
        store.reject(a.id)
        XCTAssertEqual(store.items.filter { $0.status == .pending && $0.workspace === ws }.count, 1)
    }

    // MARK: the passage in the editor

    func testSelectingACardPaintsItsPassageAndFindDoesNotClearIt() async {
        let p = propose("second line", "2nd line")
        await ws.showSuggestion(p.id)
        let range = (ws.document.text as NSString).range(of: "second line")
        XCTAssertEqual(tv.suggestionMark, range)
        let before = pixels(in: tv, like: .removed)
        XCTAssertGreaterThan(before, 100, "the passage is tinted behind the text")
        // Find puts temporary attributes on the text and clears them all; the mark is not one of them
        ws.showFind(.file); ws.find.query = "line"; ws.find.refresh(); ws.find.highlight()
        ws.find.query = ""; ws.find.refresh(); ws.find.highlight()
        XCTAssertEqual(tv.suggestionMark, range)
        XCTAssertGreaterThan(pixels(in: tv, like: .removed), 100)
    }

    func testTheMarkGoesWhenTheSuggestionIsDecidedOrTheTextChanges() async {
        let p = propose("second line", "2nd line")
        await ws.showSuggestion(p.id)
        XCTAssertNotNil(tv.suggestionMark)
        tv.insertText("X", replacementRange: NSRange(location: (ws.document.text as NSString).range(of: "second").location, length: 1))
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(tv.suggestionMark, "stale: no mark")
        let q = propose("third line", "3rd")
        await ws.showSuggestion(q.id)
        XCTAssertNotNil(tv.suggestionMark)
        store.reject(q.id); ws.refreshSuggestionMark()
        XCTAssertNil(tv.suggestionMark)
        XCTAssertNil(ws.selectedProposal)
    }

    func testAcceptedTextIsNotMarked() async {
        let p = propose("second line", "2nd line")
        await ws.showSuggestion(p.id)
        _ = await store.accept(p.id)
        XCTAssertNil(tv.suggestionMark)
        XCTAssertEqual(pixels(in: tv, like: .removed), 0)
    }

    func testSelectingACardForAnotherNoteOpensItInWriteMode() async throws {
        try s.write("B.md", "bee line\n")
        let p = { () -> Proposal in
            switch self.store.propose(in: self.ws, path: "B.md", old: "bee line", new: "x", title: "B", reason: "", client: "c") { case .success(let p): return p; case .failure: fatalError() }
        }()
        ws.mode = .view
        await ws.showSuggestion(p.id)
        XCTAssertEqual(ws.document.url?.lastPathComponent, "B.md")
        XCTAssertEqual(ws.mode, .write)
        XCTAssertEqual(ws.selectedProposal, p.id)
    }
}

/// A beachball once came from these: a view update reassigned the editor, which refreshed the mark, which wrote to the store,
/// which rebuilt the view, forever. Nothing in that chain may publish unless something changed.
@MainActor
final class SuggestionRenderLoopTests: XCTestCase {
    func testReadingOrRecheckingWithNothingNewPublishesNothing() throws {
        let s = try Scratch(["A.md": "one two three\n"]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url); ws.select(s.path("A.md"))
        let store = ProposalStore(debounce: 0.05)
        guard case .success(let p) = store.propose(in: ws, path: "A.md", old: "two", new: "2", title: "t", reason: "", client: "c") else { return XCTFail() }
        var published = 0
        let sub = store.objectWillChange.sink { published += 1 }
        for _ in 0..<20 { _ = store.proposal(p.id); _ = store.report(p.id); store.recheck(ws) }
        XCTAssertEqual(published, 0, "nothing changed, so nothing is published")
        withExtendedLifetime(sub) {}
    }

    func testAssigningTheSameEditorAgainIsNotAnAttach() {
        let bridge = EditorBridge()
        var attaches = 0
        bridge.onAttach = { attaches += 1 }
        let tv = EditorTextView()
        for _ in 0..<10 { bridge.textView = tv }
        XCTAssertEqual(attaches, 1)
        let other = EditorTextView()
        bridge.textView = other
        XCTAssertEqual(attaches, 2)
    }

    func testRefreshingTheMarkOverAndOverDoesNotPublish() async throws {
        let s = try Scratch(["A.md": "one two three\n"]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url); ws.select(s.path("A.md"))
        guard case .success(let p) = ProposalStore.shared.propose(in: ws, path: "A.md", old: "two", new: "2", title: "t", reason: "", client: "c") else { return XCTFail() }
        ws.selectedProposal = p.id
        var published = 0
        let a = ProposalStore.shared.objectWillChange.sink { published += 1 }
        let b = ws.objectWillChange.sink { published += 1 }
        for _ in 0..<20 { ws.refreshSuggestionMark() }
        XCTAssertEqual(published, 0)
        ProposalStore.shared.withdrawAll()
        withExtendedLifetime((a, b)) {}
    }
}
