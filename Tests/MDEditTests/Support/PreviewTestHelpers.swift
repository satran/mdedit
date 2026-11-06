import XCTest
import WebKit
@testable import MDEdit

/// Helpers for tests that drive a real preview web view (shared by `PreviewTests` and `TemplatePreviewTests`).
extension XCTestCase {
    /// Spins the run loop until `ok()` is true or the time is up.
    @MainActor
    func waitFor(_ ok: @autoclosure () -> Bool, _ what: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        let end = Date().addingTimeInterval(timeout)
        while !ok(), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertTrue(ok(), "timed out: \(what)", file: file, line: line)
    }

    /// Spins the run loop for a fixed time (to let a request, if any, arrive).
    @MainActor
    func letPageSettle(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }

    /// Runs JavaScript in the page's client world (works although the page itself has JavaScript off).
    @MainActor
    func pageJS(_ c: PreviewController, _ code: String) -> Any? {
        var out: Any?, done = false
        c.webView.evaluateJavaScript(code, in: nil, in: .defaultClient) { r in out = try? r.get(); done = true }
        waitFor(done, code)
        return out
    }
}
