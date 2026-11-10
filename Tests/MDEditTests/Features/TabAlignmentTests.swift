import XCTest
import SwiftUI
@testable import MDEdit

/// Draws `view` in a real (off-screen) window, light appearance, and returns the pixels.
@MainActor
private func renderedBitmap<V: View>(_ view: V, width: CGFloat, height: CGFloat) throws -> NSBitmapImageRep {
    let host = NSHostingView(rootView: view.frame(width: width, height: height))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    win.appearance = NSAppearance(named: .aqua); win.contentView = host; win.orderBack(nil)
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep
}

/// What the eye sees in the active tab: the icon, the name and the shortcut sit on the pill's horizontal centre line.
@MainActor
final class TabAlignmentTests: XCTestCase {
    func testIconNameAndShortcutAreCentredInTheActivePill() throws {
        let s = try Scratch(["A.md": "a", "B.md": "b", "C.md": "c"])
        addTeardownBlock { s.remove() }
        let ws = makeWorkspace(open: s.url)
        ws.select(s.path("B.md")); ws.select(s.path("C.md"))
        let rep = try renderedBitmap(HeaderTabs(document: ws.document).environmentObject(ws).background(Color(white: 0.8)), width: 700, height: 44)
        let W = rep.pixelsWide, H = rep.pixelsHigh, k = Double(H) / 44
        func lum(_ x: Int, _ y: Int) -> Double { Double(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.redComponent ?? 1) }
        // the active tab is the one white pill: its rows are those with a long run of white
        let white = (0..<H).filter { y in (0..<W).filter { lum($0, y) > 0.99 }.count > 80 }
        let top = try XCTUnwrap(white.first), bottom = try XCTUnwrap(white.last)
        let pillCentre = Double(top + bottom + 1) / 2 / k
        let ink = (top...bottom).filter { y in (0..<W).contains { lum($0, y) < 0.6 } }
        let inkCentre = Double(ink.first! + ink.last! + 1) / 2 / k
        XCTAssertEqual(inkCentre, pillCentre, accuracy: 1.0, "the contents sit on the pill's centre line")
        XCTAssertLessThanOrEqual(inkCentre, pillCentre + 0.25, "and never below it")

        // the outline of the active tab is as thick at the sides as at the top and bottom (one point)
        // the outline is what lies between the pill and the flat colour beyond it, so walk out from the pill until the colour settles
        func thickness(from start: Int, step: Int, at value: (Int) -> Double) -> Int {
            let plateau = value(start + step * 8)
            var n = 0, i = start
            while n < 8, abs(value(i) - plateau) > 0.003 { n += 1; i += step }
            return n
        }
        let midRow = (top + bottom) / 2
        let pillCols = (0..<W).filter { lum($0, midRow) > 0.99 }
        let side = thickness(from: pillCols.first! - 1, step: -1) { lum($0, midRow) }
        let midCol = (pillCols.first! + pillCols.last!) / 2
        let topEdge = thickness(from: top - 1, step: -1) { lum(midCol, $0) }
        XCTAssertEqual(Double(side) / k, 1.0, accuracy: 0.75, "outline at the side")
        XCTAssertEqual(Double(side), Double(topEdge), accuracy: 1, "side and top are the same thickness: \(side) vs \(topEdge) px")
    }
}

/// Every element of the header row (the buttons, the tab names, the shortcuts) sits on the header's centre line.
@MainActor
final class HeaderAlignmentTests: XCTestCase {
    func testHeaderElementsShareACentreLine() throws {
        let s = try Scratch(["A.md": "a", "B.md": "b", "C.md": "c"])
        addTeardownBlock { s.remove() }
        let ws = makeWorkspace(open: s.url)
        ws.select(s.path("B.md")); ws.select(s.path("C.md"))
        let prefs = Preferences(defaults: isolatedDefaults())
        let rep = try renderedBitmap(DetailView(document: ws.document).environmentObject(ws).environmentObject(prefs), width: 1000, height: 300)
        let W = rep.pixelsWide, k = Double(rep.pixelsHigh) / 300, bandRows = Int(Double(Metrics.headerHeight) * k)
        func lum(_ x: Int, _ y: Int) -> Double { Double(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.redComponent ?? 1) }
        var groups = [(Int, Int)](); var cur: (Int, Int)?
        for x in 0..<W {
            let has = (0..<bandRows).contains { lum(x, $0) < 0.62 }
            if has { if let c = cur, x - c.1 <= Int(14 * k) { cur = (c.0, x) } else { if let c = cur { groups.append(c) }; cur = (x, x) } }
        }
        if let c = cur { groups.append(c) }
        var centres = [Double]()
        for g in groups {
            let ys = (0..<bandRows).filter { y in (g.0...g.1).contains { lum($0, y) < 0.62 } }
            let c = Double(ys.first! + ys.last! + 1) / 2 / k
                centres.append(c)
        }
        XCTAssertGreaterThan(centres.count, 4)
        // the icon buttons: the first two at the left and the last three at the right are evenly spaced
        let icons = groups.enumerated().filter { $0.offset < 2 || $0.offset >= groups.count - 3 }.map { Double($0.element.0 + $0.element.1) / 2 / k }
        let gaps = zip(icons.dropFirst(), icons).map { $0 - $1 }
        let left = gaps[0], right = [gaps[2], gaps[3]]
        for g in right { XCTAssertEqual(g, left, accuracy: 4, "icon spacing is even") }
        let mid = Double(Metrics.headerHeight) / 2
        for c in centres { XCTAssertEqual(c, mid, accuracy: 1.5) }
    }
}
