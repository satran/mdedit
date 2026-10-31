import XCTest
@testable import MDEdit

/// A note is untrusted input. What a click on a link in it may do.
final class LinkPolicyTests: XCTestCase {
    var s: Scratch!
    var folder: URL { s.path("Notes") }

    override func setUpWithError() throws {
        s = try Scratch(["Notes/Note.md": "x", "Notes/Other.md": "x", "Notes/pic.png": "x", "Notes/doc.pdf": "x", "Notes/Sub/": ""])
        try s.write("Notes/run.sh", "#!/bin/sh\necho hi")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.path("Notes/run.sh").path)
        try s.write("Notes/Tool.app/Contents/Info.plist", "x")
        try s.write("outside.txt", "secret")
        try FileManager.default.createSymbolicLink(at: s.path("Notes/leak"), withDestinationURL: s.path("outside.txt"))
    }
    override func tearDown() { s.remove() }

    private func decide(_ link: String) -> LinkPolicy.Action {
        guard let url = URL(string: link) else { return .ignore }
        return LinkPolicy.decide(url, noteFolder: folder, root: s.url.appendingPathComponent("Notes"))
    }

    func testWebAndMailGoToTheSystem() {
        XCTAssertEqual(decide("https://example.com/a?b=c#d"), .openWeb(URL(string: "https://example.com/a?b=c#d")!))
        XCTAssertEqual(decide("HTTP://EXAMPLE.COM"), .openWeb(URL(string: "HTTP://EXAMPLE.COM")!))
        XCTAssertEqual(decide("mailto:a@b.c"), .openWeb(URL(string: "mailto:a@b.c")!))
    }

    func testEveryOtherSchemeIsIgnored() {
        for link in ["javascript:alert(1)", "JaVaScRiPt:alert(1)", "vbscript:x", "data:text/html,<script>1</script>", "tel:123", "sms:123",
                     "x-apple.systempreferences:com.apple.preference.security", "ssh://host", "smb://host/share", "afp://x", "ftp://x",
                     "itms-services://?action=download-manifest&url=https://evil", "slack://open", "zoommtg://x", "file://localhost/etc/passwd"] {
            XCTAssertEqual(decide(link), .ignore, link)
        }
    }

    func testSchemesHiddenByControlCharactersAreStillSchemes() {
        // browsers drop tabs and newlines inside a scheme
        XCTAssertEqual(LinkPolicy.scheme(of: "java\tscript:alert(1)"), "javascript")
        XCTAssertEqual(LinkPolicy.scheme(of: " \n javascript:alert(1)"), "javascript")
        XCTAssertNil(LinkPolicy.scheme(of: "folder/file:with-colon.md"))
        XCTAssertNil(LinkPolicy.scheme(of: "note.md#a:b"))
        XCTAssertEqual(LinkPolicy.scheme(of: "https://x"), "https")
    }

    func testWikiLinksStayInTheApp() {
        XCTAssertEqual(decide("mdedit://wiki/Atomic%20Habits"), .wiki("Atomic Habits"))
    }

    func testFilesInsideTheFolderOpenSensibly() {
        XCTAssertEqual(decide("Other.md"), .selectNote(folder.appendingPathComponent("Other.md")))
        XCTAssertEqual(decide("Sub/../Other.md"), .selectNote(folder.appendingPathComponent("Other.md")))
        XCTAssertEqual(decide("pic.png"), .openFile(folder.appendingPathComponent("pic.png").resolvingSymlinksInPath()))
        XCTAssertEqual(decide("doc.pdf"), .openFile(folder.appendingPathComponent("doc.pdf").resolvingSymlinksInPath()))
        XCTAssertEqual(decide("Sub"), .reveal(folder.appendingPathComponent("Sub").resolvingSymlinksInPath()))
    }

    func testProgramsAreShownNeverRun() {
        XCTAssertEqual(decide("run.sh"), .reveal(folder.appendingPathComponent("run.sh").resolvingSymlinksInPath()))
        XCTAssertEqual(decide("Tool.app"), .reveal(folder.appendingPathComponent("Tool.app").resolvingSymlinksInPath()))
        for ext in ["command", "pkg", "dmg", "jar", "workflow", "scpt", "terminal", "webloc", "exe", "bat", "py", "js", "app"] {
            XCTAssertTrue(LinkPolicy.isProgram(URL(fileURLWithPath: "/x/y.\(ext)")), ext)
        }
        XCTAssertTrue(LinkPolicy.isProgram(URL(fileURLWithPath: "/x/y.APP")), "case does not matter")
        XCTAssertFalse(LinkPolicy.isProgram(URL(fileURLWithPath: "/x/y.pdf")))
        XCTAssertFalse(LinkPolicy.isProgram(URL(fileURLWithPath: "/x/y.md")))
    }

    func testNothingOutsideTheFolderOpens() {
        XCTAssertEqual(decide("../outside.txt"), .ignore)
        XCTAssertEqual(decide("../../../../../../etc/passwd"), .ignore)
        XCTAssertEqual(decide("/etc/passwd"), .ignore)
        XCTAssertEqual(decide("file:///etc/passwd"), .ignore)
        XCTAssertEqual(decide("file://\(s.url.path)/outside.txt"), .ignore)
        XCTAssertEqual(decide("Sub/../../outside.txt"), .ignore)
    }

    func testASymlinkInsideThatPointsOutsideIsNotInside() {
        XCTAssertEqual(decide("leak"), .ignore)
    }

    func testMissingFilesAndGarbageAreIgnored() {
        XCTAssertEqual(decide("nope.md"), .ignore)
        XCTAssertEqual(decide(""), .ignore)
        XCTAssertEqual(decide("#heading"), .ignore)
        XCTAssertEqual(LinkPolicy.decide(URL(string: "Other.md")!, noteFolder: nil, root: folder), .ignore)
        XCTAssertEqual(LinkPolicy.decide(URL(string: "Other.md")!, noteFolder: folder, root: nil), .ignore)
    }
}
