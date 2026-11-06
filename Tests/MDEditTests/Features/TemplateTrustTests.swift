import XCTest
@testable import MDEdit

final class TemplateTrustTests: XCTestCase {
    var s: Scratch!
    var d: UserDefaults!

    override func setUpWithError() throws {
        s = try Scratch(["t.html": "{{ x }}"]); d = isolatedDefaults()
        addTeardownBlock { self.s.remove() }
    }

    func testApprovalIsRemembered() {
        XCTAssertFalse(TemplateTrust.isApproved("t.html", text: "{{ x }}", root: s.url, defaults: d))
        TemplateTrust.approve("t.html", text: "{{ x }}", root: s.url, defaults: d)
        XCTAssertTrue(TemplateTrust.isApproved("t.html", text: "{{ x }}", root: s.url, defaults: d))
    }

    func testAnEditAnotherPathAndAnotherFolderAreNotApproved() throws {
        TemplateTrust.approve("t.html", text: "{{ x }}", root: s.url, defaults: d)
        XCTAssertFalse(TemplateTrust.isApproved("t.html", text: "{{ x }} ", root: s.url, defaults: d), "a changed file asks again")
        XCTAssertFalse(TemplateTrust.isApproved("sub/t.html", text: "{{ x }}", root: s.url, defaults: d), "another path with the same text")
        let other = try Scratch(); defer { other.remove() }
        XCTAssertFalse(TemplateTrust.isApproved("t.html", text: "{{ x }}", root: other.url, defaults: d), "a copy of the folder elsewhere")
    }

    func testAMovedFolderAsksAgainAndALinkToTheFolderDoesNot() throws {
        TemplateTrust.approve("t.html", text: "{{ x }}", root: s.url, defaults: d)
        let moved = s.url.deletingLastPathComponent().appendingPathComponent("moved-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: s.url, to: moved)
        addTeardownBlock { try? FileManager.default.removeItem(at: moved) }
        XCTAssertFalse(TemplateTrust.isApproved("t.html", text: "{{ x }}", root: moved, defaults: d))
        let link = moved.deletingLastPathComponent().appendingPathComponent("link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: moved)
        addTeardownBlock { try? FileManager.default.removeItem(at: link) }
        TemplateTrust.approve("t.html", text: "{{ x }}", root: moved, defaults: d)
        XCTAssertTrue(TemplateTrust.isApproved("t.html", text: "{{ x }}", root: link, defaults: d), "the key is the path after symlinks are resolved")
    }

    func testThe201stFileAndThe51stFolderPushOutTheLeastRecentlyUsed() throws {
        for i in 0..<201 { TemplateTrust.approve("f\(i).html", text: "t", root: s.url, defaults: d) }
        XCTAssertFalse(TemplateTrust.isApproved("f0.html", text: "t", root: s.url, defaults: d))
        XCTAssertTrue(TemplateTrust.isApproved("f1.html", text: "t", root: s.url, defaults: d))
        XCTAssertTrue(TemplateTrust.isApproved("f200.html", text: "t", root: s.url, defaults: d))
        TemplateTrust.approve("f1.html", text: "t", root: s.url, defaults: d)         // refreshed: now the newest
        TemplateTrust.approve("new.html", text: "t", root: s.url, defaults: d)
        XCTAssertTrue(TemplateTrust.isApproved("f1.html", text: "t", root: s.url, defaults: d), "an approved Render refreshes its entry")
        XCTAssertFalse(TemplateTrust.isApproved("f2.html", text: "t", root: s.url, defaults: d))

        var roots: [Scratch] = []
        defer { roots.forEach { $0.remove() } }
        for _ in 0..<51 { let r = try Scratch(); roots.append(r); TemplateTrust.approve("t.html", text: "t", root: r.url, defaults: d) }
        XCTAssertFalse(TemplateTrust.isApproved("t.html", text: "t", root: roots[0].url, defaults: d))
        XCTAssertTrue(TemplateTrust.isApproved("t.html", text: "t", root: roots[50].url, defaults: d))
        XCTAssertEqual(d.stringArray(forKey: TemplateTrust.rootsKey)?.count, 50)
    }

    func testNothingIsWrittenIntoTheFolder() {
        let before = T.fingerprint(s)
        TemplateTrust.approve("t.html", text: "{{ x }}", root: s.url, defaults: d)
        _ = TemplateTrust.isApproved("t.html", text: "{{ x }}", root: s.url, defaults: d)
        XCTAssertEqual(T.fingerprint(s), before)
    }
}
