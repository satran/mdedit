import XCTest
@testable import MDEdit

@MainActor
final class UpdaterTests: XCTestCase {
    func testVersionOrder() {
        XCTAssertTrue(Updater.isNewer("v0.3.0", than: "0.2.0"))
        XCTAssertTrue(Updater.isNewer("0.2.1", than: "0.2.0"))
        XCTAssertTrue(Updater.isNewer("1.0", than: "0.9.9"))
        XCTAssertTrue(Updater.isNewer("0.10.0", than: "0.9.0"), "numbers, not text")
        XCTAssertFalse(Updater.isNewer("0.2.0", than: "0.2.0"))
        XCTAssertFalse(Updater.isNewer("0.2", than: "0.2.0"))
        XCTAssertFalse(Updater.isNewer("0.1.9", than: "0.2.0"))
        XCTAssertFalse(Updater.isNewer("nightly", than: "0.2.0"))
    }

    func testReleaseParsing() {
        let ok = #"{"tag_name":"v0.3.0","html_url":"https://evil.example/x","draft":false,"prerelease":false}"#.data(using: .utf8)!
        let r = Updater.release(from: ok)
        XCTAssertEqual(r?.version, "0.3.0")
        XCTAssertEqual(r?.page.host, "github.com", "the page is always the repository's, whatever the answer says")
        XCTAssertNil(Updater.release(from: #"{"tag_name":"v0.3.0","prerelease":true}"#.data(using: .utf8)!))
        XCTAssertNil(Updater.release(from: #"{"tag_name":"../../x"}"#.data(using: .utf8)!))
        XCTAssertNil(Updater.release(from: Data("not json".utf8)))
    }

    func testCheckReportsNewerCurrentAndFailure() async {
        let d = UserDefaults(suiteName: "updater-\(UUID().uuidString)")!
        func updater(_ body: String?) -> Updater {
            Updater(defaults: d) { _ in
                guard let body else { throw URLError(.notConnectedToInternet) }
                return Data(body.utf8)
            }
        }
        let current = updater(nil).currentVersion
        let newer = await updater(#"{"tag_name":"v99.0.0"}"#).check()
        XCTAssertEqual(newer, .newer(Updater.Release(version: "99.0.0", page: URL(string: "https://github.com/satran/mdedit/releases/tag/v99.0.0")!)))
        let same = await updater(#"{"tag_name":"v\#(current)"}"#).check()
        XCTAssertEqual(same, .current)
        let failed = await updater(nil).check()
        XCTAssertEqual(failed, .failed)
        XCTAssertNotNil(d.object(forKey: "lastUpdateCheck"))
    }

    func testTheAppReportsItsRealVersion() {
        let v = Updater.shared.currentVersion
        XCTAssertNotNil(Updater.parts(v))
        XCTAssertNotEqual(v, "1.0", "the About window reads this; it comes from the project's MARKETING_VERSION")
        let project = try? String(contentsOfFile: #filePath.replacingOccurrences(of: "Tests/MDEditTests/Features/UpdaterTests.swift", with: "project.yml"), encoding: .utf8)
        if let project { XCTAssertTrue(project.contains("MARKETING_VERSION: \"\(v)\""), "built \(v) but project.yml says otherwise") }
    }

    func testUpdateCheckIsOnByDefaultAndSwitchable() {
        let d = UserDefaults(suiteName: "updater-prefs-\(UUID().uuidString)")!
        let p = Preferences(defaults: d)
        XCTAssertTrue(p.checkForUpdates)
        p.checkForUpdates = false
        XCTAssertFalse(Preferences(defaults: d).checkForUpdates)
    }

    func testMenuHasAboutAndUpdateCommandsNotInPalette() {
        XCTAssertTrue(Updater.blurb.contains("Markdown"))
        XCTAssertEqual(Updater.website.host, "mdedit.satran.in")
    }
}
