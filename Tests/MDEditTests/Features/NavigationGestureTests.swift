import XCTest
import AppKit
@testable import MDEdit

/// The mouse's side buttons go Back and Forward.
@MainActor
final class NavigationGestureTests: XCTestCase {
    func testTheSideButtonsAreBackAndForward() {
        XCTAssertEqual(NavigationGesture.step(type: .otherMouseDown, button: 4), .back)
        XCTAssertEqual(NavigationGesture.step(type: .otherMouseDown, button: 3), .forward)
        XCTAssertNil(NavigationGesture.step(type: .otherMouseDown, button: 2), "the middle button is not navigation")
        XCTAssertNil(NavigationGesture.step(type: .otherMouseDown, button: 5))
    }

    func testOtherEventsAreLeftAlone() {
        XCTAssertNil(NavigationGesture.step(type: .leftMouseDown, button: 3))
    }

    private func sideButton(_ n: Int) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center))
        cg.setIntegerValueField(.mouseEventButtonNumber, value: Int64(n))
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    func testTheViewTakesTheSideButtonsAndGoesThroughTheTrail() throws {
        let s = try Scratch(["A.md": "a", "B.md": "b"])
        addTeardownBlock { s.remove() }
        let ws = makeWorkspace(open: s.url)
        ws.select(s.path("A.md")); ws.select(s.path("B.md"))
        let v = NavigationGestures.V()
        v.go = { $0 == .back ? ws.goBack() : ws.goForward() }
        let back = try sideButton(4), forward = try sideButton(3)
        XCTAssertEqual(back.buttonNumber, 4)

        XCTAssertNil(v.consume(back), "the event is taken")
        XCTAssertEqual(ws.document.url?.lastPathComponent, "A.md")
        XCTAssertNil(v.consume(forward))
        XCTAssertEqual(ws.document.url?.lastPathComponent, "B.md")

        let other = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        XCTAssertNotNil(v.consume(other), "an ordinary click passes on")
    }
}
