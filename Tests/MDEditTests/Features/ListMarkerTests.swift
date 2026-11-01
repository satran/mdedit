import XCTest
import SwiftUI
@testable import MDEdit

/// Bug: bullets and numbers sat off the middle of the first line, differently in Serif and Sans.
/// The item text is "xxxx", so its ink spans exactly the x-height; a bullet's ink must be centred on it and a number must stand on its baseline.
@MainActor
final class ListMarkerTests: XCTestCase {
    private static func isInk(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> Bool {
        guard let c = rep.colorAt(x: x, y: y) else { return false }
        return c.alphaComponent > 0.5 && c.brightnessComponent < 0.8
    }

    private func inkRows(_ rep: NSBitmapImageRep, x: ClosedRange<Int>) -> (top: Int, bottom: Int)? {
        var rows: [Int] = []
        for y in 0..<rep.pixelsHigh where x.contains(where: { Self.isInk(rep, $0, y) }) { rows.append(y) }
        guard let f = rows.first, let l = rows.last else { return nil }
        return (f, l)
    }

    private func render(_ template: ViewerStyle.Template, ordered: Bool) -> (marker: (top: Int, bottom: Int), text: (top: Int, bottom: Int))? {
        let prefs = Preferences.shared
        let old = prefs.viewerTemplate
        defer { prefs.viewerTemplate = old }
        prefs.viewerTemplate = template == .serif ? "serif" : "sans"
        let item = VItem(checkbox: nil, blocks: [.paragraph(AttributedString("xxxx"))])
        let view = BlockList(blocks: [.list(ordered: ordered, start: 1, items: [item])], prefs: prefs, baseURL: nil)
            .frame(width: 400, height: 80, alignment: .topLeading).environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: view)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.appearance = NSAppearance(named: .aqua)
        win.contentView = host
        for _ in 0..<4 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        let w = rep.pixelsWide, scale = w / 400
        // the marker lives in the first columns; find where the text starts: first column with ink, then the gap
        var cols: [Int] = []
        for x in 0..<w where (0..<rep.pixelsHigh).contains(where: { Self.isInk(rep, x, $0) }) { cols.append(x) }
        guard let first = cols.first else { return nil }
        var end = first
        for c in cols where c - end <= 3 * scale { end = c }          // the marker is one connected cluster
        guard let textStart = cols.first(where: { $0 > end + 6 * scale }), let m = inkRows(rep, x: first...end), let t = inkRows(rep, x: textStart...(textStart + 20 * scale)) else { return nil }
        win.close()
        return (m, t)
    }

    func testSansBulletIsCentredOnTheFirstLine() throws {
        let r = try XCTUnwrap(render(.sans, ordered: false))
        XCTAssertEqual(Double(r.marker.top + r.marker.bottom) / 2, Double(r.text.top + r.text.bottom) / 2, accuracy: 1.5, "marker \(r.marker) text \(r.text)")
    }

    func testSerifBulletIsCentredOnTheFirstLine() throws {
        let r = try XCTUnwrap(render(.serif, ordered: false))
        XCTAssertEqual(Double(r.marker.top + r.marker.bottom) / 2, Double(r.text.top + r.text.bottom) / 2, accuracy: 2.5, "marker \(r.marker) text \(r.text)")
    }

    func testNumbersStandOnTheBaselineInBothTemplates() throws {
        for t in [ViewerStyle.Template.serif, .sans] {
            let r = try XCTUnwrap(render(t, ordered: true))
            XCTAssertEqual(r.marker.bottom, r.text.bottom, accuracy: 2, "\(t) marker \(r.marker) text \(r.text)")
        }
    }
}
