import XCTest
import SwiftUI
@testable import MDEdit

/// Opening and closing a side panel resizes the window and nothing else: the writing column keeps its size and place on
/// screen for the whole animation, so the text does not reflow from frame to frame.
@MainActor
final class PanelSlideTests: XCTestCase {
    private var s: Scratch!
    private var ws: Workspace!
    private var window: NSWindow!

    override func setUpWithError() throws {
        s = try Scratch(["A.md": String(repeating: "A line of text that wraps in a narrow pane.\n\n", count: 40)])
        addTeardownBlock { [s] in s?.remove() }
        ws = makeWorkspace(open: s.url)
        // the view reads the saved width from the standard defaults, the workspace from its own: make them agree
        ws.defaults.set(UserDefaults.standard.object(forKey: "binderWidth") as? Double ?? 272, forKey: "binderWidth")
        ws.select(s.path("A.md"))
        let host = NSHostingView(rootView: AnyView(RootView().environmentObject(ws).environmentObject(Preferences.shared)))
        window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 1000, height: 600), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrame(NSRect(x: 300, y: 300, width: 1000, height: 600), display: true)
        window.makeKeyAndOrderFront(nil)
        addTeardownBlock { [window] in window?.close() }
        spin(0.3)
    }

    private func spin(_ t: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(t)) }

    /// The editor's scroll view in screen coordinates.
    private func column() -> NSRect? {
        func find(_ v: NSView) -> NSScrollView? {
            if let sv = v as? NSScrollView, sv.documentView is EditorTextView { return sv }
            for c in v.subviews { if let r = find(c) { return r } }
            return nil
        }
        guard let sv = find(window.contentView!) else { return nil }
        return window.convertToScreen(sv.convert(sv.bounds, to: nil))
    }

    /// Runs `toggle` and samples the column's place and width while the window animates.
    private func samples(_ toggle: () -> Void) -> (before: NSRect, during: [NSRect], after: NSRect, frames: [CGFloat])? {
        guard let before = column() else { return nil }
        toggle()
        var out: [NSRect] = [], frames: [CGFloat] = []
        let end = Date().addingTimeInterval(0.6)
        while Date() < end { spin(0.02); if let c = column() { out.append(c)}; frames.append(window.frame.width) }
        guard let after = column() else { return nil }
        return (before, out, after, frames)
    }

    private func assertSteady(_ r: (before: NSRect, during: [NSRect], after: NSRect, frames: [CGFloat])?, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let r else { return XCTFail("no editor in the window", file: file, line: line) }
        for c in r.during {
            XCTAssertEqual(c.minX, r.before.minX, accuracy: 1, "\(what): the column moved", file: file, line: line)
            XCTAssertEqual(c.width, r.before.width, accuracy: 1, "\(what): the column changed size", file: file, line: line)
        }
        XCTAssertEqual(r.after.minX, r.before.minX, accuracy: 1, file: file, line: line)
        XCTAssertEqual(r.after.width, r.before.width, accuracy: 1, file: file, line: line)
        XCTAssertGreaterThan(Set(r.frames.map { Int($0) }).count, 2, "\(what): the window really animates", file: file, line: line)
    }

    func testTheBinderSlidesWithoutResizingTheColumn() {
        XCTAssertTrue(ws.binderVisible)
        assertSteady(samples { ws.toggleBinder() }, "hide binder")
        XCTAssertFalse(ws.binderVisible); XCTAssertFalse(ws.holdBinder); XCTAssertNil(ws.pinnedMainWidth)
        assertSteady(samples { ws.toggleBinder() }, "show binder")
        XCTAssertTrue(ws.binderVisible); XCTAssertNil(ws.pinnedMainWidth)
    }

    func testThePanelSlidesWithoutResizingTheColumnAndATabSwitchMovesNothing() {
        assertSteady(samples { ws.toggleOutline() }, "open the panel")
        let open = window.frame
        ws.showFind(.file); spin(0.5)
        XCTAssertEqual(window.frame, open, "switching to Find does not touch the window")
        ws.selectPanel(.outline); spin(0.5)
        XCTAssertEqual(window.frame, open, "nor does switching back")
        assertSteady(samples { ws.togglePanel() }, "close the panel")
        assertSteady(samples { ws.showFind(.file) }, "open on Find")
        assertSteady(samples { ws.closeFind() }, "Esc")
        XCTAssertNil(ws.heldPanel); XCTAssertNil(ws.pinnedMainWidth); XCTAssertNil(ws.minWidthOverride)
    }

    func testAPanelOnItsWayOutStaysUntilTheWindowHasShrunk() {
        ws.toggleOutline(); spin(0.5)
        ws.toggleOutline()
        XCTAssertNil(ws.panel); XCTAssertEqual(ws.heldPanel, .outline, "still drawn while the window shrinks")
        spin(0.5)
        XCTAssertNil(ws.heldPanel)
    }
}
