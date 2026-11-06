import XCTest
@testable import MDEdit

/// The success criterion of plan 006. Budgets are loose (see TESTING.md): they catch an order of magnitude, not noise.
final class TemplatePerformanceTests: XCTestCase {
    func testAHundredNoteIndexWithASectionEach() async throws {
        let s = try Scratch(); defer { s.remove() }
        for i in 0..<120 { try s.write(String(format: "notes/n%03d.md", i), "# Note \(i)\n\n## Summary\n\n" + String(repeating: "Some **text** and a [[link]]. ", count: 40)) }
        let t = #"{% files "notes" limit 100 as items %}{% for f in items %}<h2><a href="{{ f.path|urlencode }}">{{ f.title }}</a></h2>{% section f.path "Summary" as t %}{{ t|markdown }}{% endfor %}"#
        var page = ""
        await withinAsync(1.0, "a 100-note index") {
            let r = await TemplateEvaluator.render(text: t, root: s.url, cancel: CancelFlag())
            page = (try? r.get()) ?? ""
        }
        XCTAssertEqual(page.components(separatedBy: "<h2>").count - 1, 100)
    }

    func testTheWorstCaseTemplateEndsWithinTheClockPlusGrace() async throws {
        let s = try Scratch(); defer { s.remove() }
        for i in 0..<100 { try s.write("w/n\(i).md", "# N\(i)\n\n## Summary\n\n" + String(repeating: "word ", count: 2_000)) }
        let t = #"{% files "w" as a %}{% for x in a %}{% for y in a %}{% section y.path "Summary" as t %}{{ t|markdown }}{% endfor %}{% endfor %}"#
        let started = Date()
        let r = await TemplateEvaluator.render(text: t, root: s.url, cancel: CancelFlag())
        let took = Date().timeIntervalSince(started)
        XCTAssertLessThan(took, TemplateLimits.standard.clock + 0.5, "the render ends with a page or the limit error within the clock plus grace")
        if case .success = r { return }
        if case .failure(let e) = r { XCTAssertTrue(T.isLimit(e) || e == .timeout, e.message) }
    }
}
