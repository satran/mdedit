import XCTest
@testable import MDEdit

final class TemplateTrustTests: XCTestCase {
    func testTheWarningIsShownUntilItHasBeenAnswered() {
        let d = isolatedDefaults()
        XCTAssertFalse(TemplateTrust.hasBeenWarned(defaults: d))
        TemplateTrust.markWarned(defaults: d)
        XCTAssertTrue(TemplateTrust.hasBeenWarned(defaults: d))
    }

    func testItIsKeptInTheSettingsOfTheAppAndNotInAFolder() throws {
        let s = try Scratch(["t.html": "{{ x }}"]); defer { s.remove() }
        let before = T.fingerprint(s)
        TemplateTrust.markWarned(defaults: isolatedDefaults())
        XCTAssertEqual(T.fingerprint(s), before)
    }

    // MARK: pages that were rendered

    func testARenderedPageIsRecognisedByFolderPathAndText() throws {
        let s = try Scratch(); defer { s.remove() }
        let d = isolatedDefaults()
        XCTAssertFalse(TemplateTrust.wasRendered("t.html", text: "{{ x }}", root: s.url, defaults: d))
        TemplateTrust.markRendered("t.html", text: "{{ x }}", root: s.url, defaults: d)
        XCTAssertTrue(TemplateTrust.wasRendered("t.html", text: "{{ x }}", root: s.url, defaults: d))
        XCTAssertFalse(TemplateTrust.wasRendered("t.html", text: "{{ x }} ", root: s.url, defaults: d), "one more character")
        XCTAssertFalse(TemplateTrust.wasRendered("sub/t.html", text: "{{ x }}", root: s.url, defaults: d))
        let other = try Scratch(); defer { other.remove() }
        XCTAssertFalse(TemplateTrust.wasRendered("t.html", text: "{{ x }}", root: other.url, defaults: d))
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.path(".mdedit").path) == false, "nothing is written into the folder")
    }

    func testTheRenderedRecordKeepsTheLatestTextAndIsBounded() throws {
        let s = try Scratch(); defer { s.remove() }
        let d = isolatedDefaults()
        TemplateTrust.markRendered("t.html", text: "one", root: s.url, defaults: d)
        TemplateTrust.markRendered("t.html", text: "two", root: s.url, defaults: d)
        XCTAssertFalse(TemplateTrust.wasRendered("t.html", text: "one", root: s.url, defaults: d), "only the text last rendered counts")
        XCTAssertTrue(TemplateTrust.wasRendered("t.html", text: "two", root: s.url, defaults: d))
        for i in 0..<201 { TemplateTrust.markRendered("f\(i).html", text: "t", root: s.url, defaults: d) }
        XCTAssertFalse(TemplateTrust.wasRendered("t.html", text: "two", root: s.url, defaults: d), "past 200 files the oldest goes")
        XCTAssertTrue(TemplateTrust.wasRendered("f200.html", text: "t", root: s.url, defaults: d))
        var roots: [Scratch] = []; defer { roots.forEach { $0.remove() } }
        for _ in 0..<51 { let r = try Scratch(); roots.append(r); TemplateTrust.markRendered("t.html", text: "t", root: r.url, defaults: d) }
        XCTAssertFalse(TemplateTrust.wasRendered("t.html", text: "t", root: roots[0].url, defaults: d))
        XCTAssertTrue(TemplateTrust.wasRendered("t.html", text: "t", root: roots[50].url, defaults: d))
    }
}
