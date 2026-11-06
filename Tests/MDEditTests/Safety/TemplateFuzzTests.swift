import XCTest
@testable import MDEdit

/// Random soup of template tokens: every input returns a page or an error within the clock, and never crashes.
final class TemplateFuzzTests: XCTestCase {
    func testRandomTokenSoupAlwaysEnds() throws {
        let s = try Scratch(["a.md": "# A\n\n## S\n\ntext", "d/b.md": "# B"]); defer { s.remove() }
        let pieces = [
            "{% for x in items %}", "{% endfor %}", "{% empty %}", "{% if a == b %}", "{% if x %}", "{% else %}", "{% endif %}", "{{ x }}", "{{ x|markdown }}",
            "{{ x.y|default:\"d\" }}", "{% files \"\" as items %}", "{% files \"d\" sort \"modified\" reverse limit 3 as items %}", "{% section \"a.md\" \"S\" as x %}",
            "{{", "}}", "{%", "%}", "{#", "#}", "text", "\n", "\"", "|", " ", "<b>", "&", "{{ \"", "9999999999", "{% for", "{% files \"..\" as q %}",
        ]
        var rng = SeededRNG(seed: 42)
        let started = Date()
        for _ in 0..<600 {
            let n = Int.random(in: 1...60, using: &rng)
            let t = (0..<n).map { _ in pieces.randomElement(using: &rng)! }.joined()
            _ = T.run(t, in: s, limits: { var l = TemplateLimits.standard; l.clock = 1; return l }())
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 30)
    }

    func testLongRunsAndDeepNesting() throws {
        let s = try Scratch(["a.md": "# A"]); defer { s.remove() }
        for t in [String(repeating: "{{", count: 30_000), String(repeating: "{% if 1 %}", count: 30_000), String(repeating: "{# ", count: 30_000),
                  String(repeating: "x", count: 100_000), String(repeating: "{{ 1 }}", count: 20_000), String(repeating: "\"", count: 60_000)] {
            _ = T.run(t, in: s)
        }
    }
}
