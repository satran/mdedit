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
}
