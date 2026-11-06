import XCTest
import SwiftUI
@testable import MDEdit

/// The bar above a template while something is going on, drawn in a real hosting view.
@MainActor
final class TemplateBannerTests: XCTestCase {
    func testTheBarSaysSomethingOnlyWhileARenderRunsOrAReadIsBlocked() throws {
        for state: TemplateState in [.notTemplate, .needsRender, .rendered("<p>x</p>"), .failed(.timeout), .failed(.syntax("bad", line: 3))] {
            XCTAssertNil(TemplateBanner.content(state, busy: false), "\(state)")
        }
        let rendering = try XCTUnwrap(TemplateBanner.content(.rendering, busy: true))
        XCTAssertTrue(rendering.spinner); XCTAssertEqual(rendering.buttons.map(\.title), ["Cancel"])
        for state: TemplateState in [.needsRender, .failed(.timeout), .rendered("x"), .notTemplate] {
            let waiting = try XCTUnwrap(TemplateBanner.content(state, busy: true), "\(state)")
            XCTAssertTrue(waiting.text.contains("blocked file read")); XCTAssertTrue(waiting.buttons.isEmpty)
        }
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

    func testTheBarIsDrawnInLightAndDark() throws {
        for dark in [false, true] {
            for (state, busy) in [(TemplateState.rendering, true), (.needsRender, true)] {
                let (rep, expected) = try draw(state, busy: busy, dark: dark)
                XCTAssertGreaterThan(rep.pixelsHigh, 0)
                let px = try XCTUnwrap(rep.colorAt(x: 4, y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB))
                if dark {
                    for c in [px.redComponent, px.greenComponent, px.blueComponent] { XCTAssertLessThan(c, 0.3, "\(state) dark") }
                } else {
                    XCTAssertEqual(px.redComponent, expected.redComponent, accuracy: 0.03, "\(state)")
                    XCTAssertEqual(px.greenComponent, expected.greenComponent, accuracy: 0.03, "\(state)")
                    XCTAssertEqual(px.blueComponent, expected.blueComponent, accuracy: 0.03, "\(state)")
                }
            }
        }
    }

    func testCancelGoesBackToTheEditor() throws {
        let s = try Scratch(["p.html": "{{ x }}"]); defer { s.remove() }
        let ws = makeWorkspace(open: s.url)
        ws.select(s.path("p.html"))
        XCTAssertEqual(ws.mode, .write, "a template opens in the editor")
        ws.templateSource = SlowSource(delay: 0.4)
        ws.templateConfirm = { _, _, _, _, _ in true }
        ws.mode = .view
        XCTAssertEqual(ws.templateState, .rendering)
        TemplateBanner(ws: ws).run("Cancel")
        XCTAssertEqual(ws.mode, .write)
        XCTAssertEqual(ws.templateState, .needsRender)
        waitFor(!ws.renderBusy, "the task returns")
    }
}
