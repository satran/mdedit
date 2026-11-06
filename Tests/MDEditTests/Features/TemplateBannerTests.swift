import XCTest
import SwiftUI
@testable import MDEdit

/// The bar above a template page, drawn in a real hosting view. (`SnapshotTests.render` cannot set the template state.)
@MainActor
final class TemplateBannerTests: XCTestCase {
    private let states: [(TemplateState, Bool, [String])] = [
        (.needsRender, false, ["Render"]), (.needsRender, true, ["Render"]), (.rendering, true, ["Cancel"]), (.cancelled, false, ["Render"]),
        (.rendered("<p>x</p>"), false, ["Show source"]), (.failed(.timeout), false, ["Show source"]), (.failed(.syntax("bad", line: 3)), true, ["Show source"]),
    ]

    func testWhatTheBarSaysAndOffersForEachState() throws {
        XCTAssertNil(TemplateBanner.content(.notTemplate, busy: false))
        for (state, busy, buttons) in states {
            let c = try XCTUnwrap(TemplateBanner.content(state, busy: busy), "\(state)")
            XCTAssertEqual(c.buttons.map(\.title), buttons, "\(state)")
            XCTAssertFalse(c.text.isEmpty)
        }
        let waiting = try XCTUnwrap(TemplateBanner.content(.needsRender, busy: true))
        XCTAssertEqual(waiting.buttons.first?.enabled, false, "Render is disabled while a blocked read is outstanding")
        XCTAssertTrue(waiting.text.contains("blocked file read"))
        XCTAssertEqual(try XCTUnwrap(TemplateBanner.content(.needsRender, busy: false)).buttons.first?.enabled, true)
        XCTAssertTrue(try XCTUnwrap(TemplateBanner.content(.rendering, busy: true)).spinner)
        XCTAssertTrue(try XCTUnwrap(TemplateBanner.content(.failed(.syntax("bad", line: 3)), busy: false)).text.contains("line 3"))
    }

    private func draw(_ state: TemplateState, busy: Bool, dark: Bool) throws -> (NSBitmapImageRep, NSColor) {
        let ws = makeWorkspace()
        ws.templateState = state; ws.renderBusy = busy
        let size = NSSize(width: 800, height: 34)
        let host = NSHostingView(rootView: TemplateBanner(ws: ws).frame(width: size.width, height: size.height))
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = appearance
        win.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        for _ in 0..<4 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        var expected = NSColor.black
        appearance.performAsCurrentDrawingAppearance { expected = Palette.chip.usingColorSpace(.sRGB) ?? .black }
        return (rep, expected)
    }

    func testTheBarIsDrawnInLightAndDarkForEveryState() throws {
        for dark in [false, true] {
            for (state, busy, _) in states {
                let (rep, expected) = try draw(state, busy: busy, dark: dark)
                XCTAssertGreaterThan(rep.pixelsHigh, 0)
                // a pixel in the left margin, where there is no text: the bar's own colour
                let px = try XCTUnwrap(rep.colorAt(x: 4, y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB))
                if dark {
                    // the hosting view blends the dark bar a little lighter than the palette value: check it is the dark bar, not the light one
                    for c in [px.redComponent, px.greenComponent, px.blueComponent] { XCTAssertLessThan(c, 0.3, "\(state) dark") }
                } else {
                    XCTAssertEqual(px.redComponent, expected.redComponent, accuracy: 0.03, "\(state)")
                    XCTAssertEqual(px.greenComponent, expected.greenComponent, accuracy: 0.03, "\(state)")
                    XCTAssertEqual(px.blueComponent, expected.blueComponent, accuracy: 0.03, "\(state)")
                }
            }
        }
    }

    func testTheButtonsRunTheWorkspaceActions() throws {
        let s = try Scratch(["p.html": "{{ x }}"]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url)
        ws.select(s.path("p.html"))
        XCTAssertEqual(ws.templateState, .needsRender)
        var asked = 0
        ws.templateConfirm = { _, _, _, _, _ in asked += 1; return false }
        TemplateBanner(ws: ws).run("Render")
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(ws.templateState, .needsRender)
    }
}
