import XCTest
@testable import MDEdit

/// Everything that changes files from the binder: rename, move, copy, drop, trash, create. Odd names and odd places.
final class FileOperationTests: XCTestCase {
    var s: Scratch!
    var ws: Workspace!

    override func setUpWithError() throws {
        s = try Scratch(["A/One.md": "one", "A/Deep/Two.md": "two", "B/": "", "Top.md": "top", "pic.png": "png", "notes.txt": "txt"])
        ws = makeWorkspace(open: s.url)
    }
    override func tearDown() { ws = nil; s.remove() }

    // MARK: names

    func testCleanNameRemovesWhatCannotBeInAFileName() {
        XCTAssertEqual(Workspace.cleanName("a/b"), "a-b")
        XCTAssertEqual(Workspace.cleanName("a:b"), "a-b")
        XCTAssertEqual(Workspace.cleanName("  spaced  "), "spaced")
        XCTAssertEqual(Workspace.cleanName("tab\there\nnew\u{0}nul"), "tabherenewnul")
        XCTAssertEqual(Workspace.cleanName(".."), "")
        XCTAssertEqual(Workspace.cleanName("."), "")
        XCTAssertEqual(Workspace.cleanName("..."), "")
        XCTAssertEqual(Workspace.cleanName(""), "")
        XCTAssertEqual(Workspace.cleanName("   "), "")
        XCTAssertLessThanOrEqual(Workspace.cleanName(String(repeating: "é", count: 500)).utf8.count, 200)
        XCTAssertEqual(Workspace.cleanName("日本語 🎉"), "日本語 🎉")
        XCTAssertEqual(Workspace.cleanName("../../etc/passwd"), "..-..-etc-passwd")
    }

    func testRenameRefusesDangerousNamesAndLeavesTheFile() {
        let u = s.path("Top.md")
        for bad in ["..", ".", "", "   ", "\u{0}"] {
            ws.rename(u, to: bad)
            XCTAssertTrue(s.exists("Top.md"), "after renaming to \(bad.debugDescription)")
        }
    }

    func testRenameCannotEscapeTheFolder() {
        ws.rename(s.path("A/One.md"), to: "../../escaped")
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.url.deletingLastPathComponent().appendingPathComponent("escaped.md").path))
        XCTAssertTrue(s.exists("A/..-..-escaped.md"), "the slashes became dashes and the file stayed where it was")
    }

    func testRenameToAnExistingNameIsRefused() {
        ws.rename(s.path("Top.md"), to: "pic")        // pic.png exists; Top.md -> pic.md is fine
        XCTAssertTrue(s.exists("pic.md"))
        try? s.write("Again.md", "x")
        ws.reload()
        ws.rename(s.path("Again.md"), to: "pic")
        XCTAssertTrue(s.exists("Again.md"), "pic.md is taken")
        XCTAssertNotNil(ws.message)
    }

    func testRenameKeepsTheExtensionOfNotesButNotOfOtherFiles() {
        ws.rename(s.path("notes.txt"), to: "renamed")
        XCTAssertTrue(s.exists("renamed.txt"))
        ws.rename(s.path("pic.png"), to: "photo.jpeg")
        XCTAssertTrue(s.exists("photo.jpeg"))
        XCTAssertFalse(s.exists("photo.jpeg.png"))
    }

    func testRenameVeryLongAndUnicodeNames() {
        ws.rename(s.path("Top.md"), to: String(repeating: "x", count: 5_000))
        XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: s.url.path))?.contains { $0.hasPrefix("xxxxxxxx") } == true)
        ws.rename(s.path("A/One.md"), to: "日本語 – ñ 🎉")
        XCTAssertTrue(s.exists("A/日本語 – ñ 🎉.md"))
    }

    // MARK: moving

    func testMoveIntoItselfOrADescendantIsRefused() {
        ws.moveItem(s.path("A"), into: s.path("A/Deep"))
        ws.moveItem(s.path("A"), into: s.path("A"))
        XCTAssertTrue(s.exists("A/One.md")); XCTAssertTrue(s.exists("A/Deep/Two.md"))
    }

    func testMoveCarriesTheOpenNoteAlong() {
        ws.select(s.path("A/One.md"))
        ws.moveItem(s.path("A/One.md"), into: s.path("B"))
        XCTAssertTrue(s.exists("B/One.md")); XCTAssertFalse(s.exists("A/One.md"))
        XCTAssertEqual(ws.document.url?.lastPathComponent, "One.md")
        XCTAssertEqual(ws.document.url?.deletingLastPathComponent().lastPathComponent, "B")
    }

    func testMoveOntoANameThatExistsKeepsBoth() throws {
        try s.write("B/One.md", "other one")
        ws.moveItem(s.path("A/One.md"), into: s.path("B"))
        XCTAssertEqual(try s.read("B/One.md"), "other one")
        XCTAssertEqual(try s.read("B/One 2.md"), "one")
    }

    func testMovingAFileThatNoLongerExistsDoesNotCrash() throws {
        try FileManager.default.removeItem(at: s.path("Top.md"))
        ws.moveItem(s.path("Top.md"), into: s.path("B"))
        ws.rename(s.path("Top.md"), to: "x")
        ws.trash(s.path("Top.md"))
    }

    // MARK: drops

    func testDropCopiesFromOutsideAndNeverTouchesTheOriginal() throws {
        let other = try Scratch(["Report.pdf": "pdf", "Folder/inner.txt": "inner"])
        defer { other.remove() }
        ws.drop([other.path("Report.pdf"), other.path("Folder")], into: s.path("B"))
        XCTAssertEqual(try s.read("B/Report.pdf"), "pdf")
        XCTAssertEqual(try s.read("B/Folder/inner.txt"), "inner")
        XCTAssertTrue(other.exists("Report.pdf") && other.exists("Folder/inner.txt"))
    }

    func testDroppingTheSameFileTwiceKeepsBoth() throws {
        let other = try Scratch(["r.pdf": "x"]); defer { other.remove() }
        ws.drop([other.path("r.pdf")], into: s.url); ws.drop([other.path("r.pdf")], into: s.url)
        XCTAssertTrue(s.exists("r.pdf") && s.exists("r 2.pdf"))
    }

    func testAFolderCannotBeCopiedIntoItself() {
        XCTAssertNil(ws.copyIn(s.path("A"), to: s.path("A/Deep")))
        XCTAssertNotNil(ws.message)
        XCTAssertNil(ws.copyIn(s.url, to: s.path("B")), "the opened folder into its own subfolder")
    }

    func testDropOfAMissingFileReportsAndContinues() throws {
        let other = try Scratch(["ok.pdf": "x"]); defer { other.remove() }
        ws.drop([other.path("gone.pdf"), other.path("ok.pdf")], into: s.url)
        XCTAssertNotNil(ws.message)
        XCTAssertTrue(s.exists("ok.pdf"))
    }

    func testDropIntoAReadOnlyFolderReportsInsteadOfCrashing() throws {
        let other = try Scratch(["r.pdf": "x"]); defer { other.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: s.path("B").path)
        ws.drop([other.path("r.pdf")], into: s.path("B"))
        XCTAssertNotNil(ws.message)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.path("B").path)
    }

    func testLinkTextForHostileFileNames() throws {
        ws.select(s.path("Top.md"))
        let other = try Scratch(["a](javascript:alert(1)) [b.png": "x", "x]y[z.pdf": "x", "line\nbreak.pdf": "x"])
        defer { other.remove() }
        for name in ["a](javascript:alert(1)) [b.png", "x]y[z.pdf", "line\nbreak.pdf"] {
            let text = ws.linkText(forDropped: [other.path(name)])
            XCTAssertFalse(text.contains("\n"), text)
            // the whole thing must be one link or image whose label holds the name and whose target is a plain encoded path
            let out = Exporter.html(markdown: text, title: "t")
            XCTAssertFalse(out.lowercased().contains("href=\"javascript"), out)
            XCTAssertEqual(out.components(separatedBy: "<a ").count - 1 + out.components(separatedBy: "<img ").count - 1, 1, text)
        }
    }

    func testLinkTextForDroppedNotesAndImages() throws {
        ws.select(s.path("Top.md"))
        XCTAssertEqual(ws.linkText(forDropped: [s.path("A/One.md")]), "[[One]]")
        XCTAssertEqual(ws.linkText(forDropped: [s.path("pic.png")]), "![pic](pic.png)")
        XCTAssertEqual(ws.linkText(forDropped: [s.path("notes.txt")]), "[[notes]]")
        XCTAssertEqual(ws.linkText(forDropped: [s.path("A/Deep/Two.md"), s.path("pic.png")]), "[[Two]]\n![pic](pic.png)")
    }

    func testLinkTextWithNoOpenNoteDoesNothing() throws {
        let fresh = makeWorkspace(open: s.url)
        fresh.document.open(nil)
        XCTAssertEqual(fresh.linkText(forDropped: [s.path("pic.png")]), "")
    }

    // MARK: trash and create

    func testTrashRemovesTheFileAndClearsTheOpenNote() {
        ws.select(s.path("Top.md"))
        ws.trash(s.path("Top.md"))
        XCTAssertFalse(s.exists("Top.md"))
        XCTAssertNil(ws.document.url)
        XCTAssertNil(ws.selection)
    }

    func testTrashingAFolderClosesANoteInsideIt() {
        ws.select(s.path("A/Deep/Two.md"))
        ws.trash(s.path("A"))
        XCTAssertNil(ws.document.url)
        XCTAssertFalse(s.exists("A"))
    }

    func testNewDocumentsAndFoldersGetFreeNames() {
        ws.newDocument(in: s.url); ws.newDocument(in: s.url); ws.newDocument(in: s.url)
        XCTAssertTrue(s.exists("Untitled.md") && s.exists("Untitled 2.md") && s.exists("Untitled 3.md"))
        ws.newFolder(in: s.url); ws.newFolder(in: s.url)
        XCTAssertTrue(s.exists("New Folder") && s.exists("New Folder 2"))
    }

    func testNewDocumentInAReadOnlyFolderReports() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: s.path("B").path)
        ws.newDocument(in: s.path("B"))
        XCTAssertNotNil(ws.message)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.path("B").path)
    }

    func testWikiLinkToAnOddNameCreatesASafeFile() {
        // openWiki asks before it creates; the name it would use must be clean
        let name = Workspace.cleanName("../../../tmp/evil\u{0}name")
        XCTAssertFalse(name.contains("/")); XCTAssertFalse(name.contains("\u{0}"))
    }

    // MARK: scanning

    func testScanSkipsLinkedFoldersSoLoopsCannotHappen() throws {
        try FileManager.default.createSymbolicLink(at: s.path("A/loop"), withDestinationURL: s.url)
        try FileManager.default.createSymbolicLink(at: s.path("B/up"), withDestinationURL: s.path("A"))
        let root = BinderNode.scan(s.url)
        XCTAssertNil(root.find(s.path("A/loop")))
        XCTAssertNil(root.find(s.path("B/up")))
        XCTAssertEqual(root.files.map(\.name).sorted(), ["One", "Top", "Two", "notes"].sorted())
    }

    func testScanKeepsLinkedFilesAndSurvivesBrokenLinks() throws {
        try FileManager.default.createSymbolicLink(at: s.path("B/linked.md"), withDestinationURL: s.path("Top.md"))
        try FileManager.default.createSymbolicLink(at: s.path("B/broken.md"), withDestinationURL: s.path("nowhere.md"))
        let root = BinderNode.scan(s.url)
        XCTAssertNotNil(root.find(s.path("B/linked.md")))
        _ = root.rows(expanded: [s.path("B")], search: "")
    }

    func testScanStopsAtADepthLimit() throws {
        var path = "deep"
        for _ in 0..<(BinderNode.maxDepth + 20) { path += "/d" }
        try s.write(path + "/")
        let root = BinderNode.scan(s.url)
        var depth = 0, node: BinderNode? = root.children.first { $0.name == "deep" }
        while let n = node, let next = n.children.first { depth += 1; node = next }
        XCTAssertLessThanOrEqual(depth, BinderNode.maxDepth)
    }

    func testScanSurvivesAFolderItCannotRead() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: s.path("B").path)
        let root = BinderNode.scan(s.url)
        XCTAssertNotNil(root.find(s.path("B")))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.path("B").path)
    }

    func testHiddenFilesAndPackagesAreNotListed() throws {
        try s.write(".hidden.md", "x"); try s.write(".git/config", "x"); try s.write("Thing.app/Contents/x", "x")
        let names = BinderNode.scan(s.url).children.map(\.name)
        XCTAssertFalse(names.contains(".hidden")); XCTAssertFalse(names.contains(".git")); XCTAssertFalse(names.contains("Thing.app"))
    }
}
