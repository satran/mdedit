import XCTest
import SwiftUI
import AppKit
@testable import MDEdit

/// What the find panel looks like: heights, hover tips, and the shared result rows.
@MainActor
final class FindPanelTests: XCTestCase {
    private var s: Scratch!
    private var ws: Workspace!

    override func setUpWithError() throws {
        s = try Scratch(["A.md": "Intro\nthe Time to restore is key\nand time to restore again\n", "Sub/B.md": "time to restore\n"])
        addTeardownBlock { [s] in s?.remove() }
        ws = makeWorkspace(open: s.url)
        ws.select(s.path("A.md"))
        ws.findVisible = true
    }

    private func host(dark: Bool = false, height: CGFloat = 700) -> (NSHostingView<AnyView>, NSWindow) {
        let v = AnyView(FindPanel(find: ws.find, document: ws.document).environmentObject(ws).environmentObject(Preferences(defaults: isolatedDefaults())).frame(width: 360, height: height))
        let h = NSHostingView(rootView: v)
        h.frame = NSRect(x: 0, y: 0, width: 360, height: height)
        let w = NSWindow(contentRect: h.frame, styleMask: [.titled], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.contentView = h; w.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        addTeardownBlock { w.close() }
        return (h, w)
    }

    private func tips(in v: NSView) -> [String] { (v.toolTip.map { [$0] } ?? []) + v.subviews.flatMap(tips) }

    func testEveryControlHasAHoverTip() {
        ws.find.scope = .file; ws.find.query = "time to restore"
        var t = tips(in: host().0)
        for want in ["Match case", "Whole word", "Regular expression", "Previous match", "Next match", "Preserve case", "Replace every match", "Replace the current match", "Go to line"] {
            XCTAssertTrue(t.contains { $0.hasPrefix(want) }, "no tip starting “\(want)” in \(t)")
        }
        ws.find.scope = .folder
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        t = tips(in: host().0)
        for want in ["Match case", "Whole word", "Regular expression", "Fold every note", "Replace the ticked matches", "Untick", "Open A at line"] {
            XCTAssertTrue(t.contains { $0.hasPrefix(want) }, "folder: no tip starting “\(want)” in \(t)")
        }
    }

    /// The panel's bottom row (the tab icons) is as high as the status bar beside it, so the two rules line up.
    func testThePanelTabBarIsExactlyAsHighAsTheStatusBar() throws {
        let v = AnyView(RightPanelView(document: ws.document).environmentObject(ws).environmentObject(Preferences(defaults: isolatedDefaults())).frame(width: 361, height: 600))
        let h = NSHostingView(rootView: v)
        h.frame = NSRect(x: 0, y: 0, width: 361, height: 600)
        let w = NSWindow(contentRect: h.frame, styleMask: [.titled], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = h; w.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        addTeardownBlock { w.close() }
        let rep = try XCTUnwrap(h.bitmapImageRepForCachingDisplay(in: h.bounds))
        h.cacheDisplay(in: h.bounds, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / 600
        // from the bottom edge upward, at a column with nothing in it, the first row that is not the panel's colour is the rule
        let x = Int(340 * scale)
        func px(_ y: Int) -> NSColor? { rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) }
        let base = try XCTUnwrap(px(rep.pixelsHigh - 3))
        var y = rep.pixelsHigh - 3
        while y > 0, let c = px(y), abs(c.redComponent - base.redComponent) + abs(c.greenComponent - base.greenComponent) + abs(c.blueComponent - base.blueComponent) < 0.02 { y -= 1 }
        let fromBottom = CGFloat(rep.pixelsHigh - y) / scale
        XCTAssertEqual(fromBottom, Metrics.footerHeight, accuracy: 1.5, "the rule above the footer sits \(fromBottom) pt from the bottom")
    }

    func testRowsAreYellowWhileReplaceIsEmptyAndShowTheNewTextOtherwise() throws {
        let m = FindMatch(range: NSRange(location: 4, length: 4), line: 2, before: "the ", text: "Time", after: " is", replacement: "Moment")
        let plain = FindPanel.lineText(m, replacement: "")
        XCTAssertEqual(String(plain.characters), "the Time is")
        let hit = try XCTUnwrap(plain.runs.first { String(plain.characters[$0.range]) == "Time" })
        XCTAssertNotNil(hit.backgroundColor); XCTAssertNil(hit.strikethroughStyle)

        let diff = FindPanel.lineText(m, replacement: "Moment")
        XCTAssertEqual(String(diff.characters), "the TimeMoment is")
        let old = try XCTUnwrap(diff.runs.first { String(diff.characters[$0.range]) == "Time" })
        let new = try XCTUnwrap(diff.runs.first { String(diff.characters[$0.range]) == "Moment" })
        XCTAssertNotNil(old.strikethroughStyle); XCTAssertNil(new.strikethroughStyle)
        XCTAssertNotEqual(old.backgroundColor, new.backgroundColor)
    }

    func testBothViewsListTheSameRowsTheSameWay() {
        ws.find.scope = .file; ws.find.query = "time to restore"
        let file = ws.find.matches
        ws.find.scope = .folder
        let end = Date().addingTimeInterval(8)
        repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) } while ws.find.busy && Date() < end
        let a = ws.find.groups.first { $0.name == "A" }?.matches
        XCTAssertEqual(a, file, "the same match for the same line, with the same context and replacement")
    }
}
