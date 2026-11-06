import XCTest
@testable import MDEdit

/// `SafePath` is the one check for a path from an agent or a template: every rule is tested here directly.
@MainActor
final class SafePathTests: XCTestCase {
    var s: Scratch!
    var outside: Scratch!

    override func setUpWithError() throws {
        s = try Scratch(["A.md": "# A", "Sub/B.txt": "b", "Sub/C.markdown": "c", "page.html": "<p>", ".secret/x.md": "hidden", ".hidden.md": "h", "Sub/deep/D.md": "d"])
        outside = try Scratch(["Out.md": "outside", "Dir/E.md": "e"])
        addTeardownBlock { self.s.remove(); self.outside.remove() }
    }

    private func note(_ p: String) -> Result<URL, SafePath.Failure> { SafePath.resolve(p, in: s.url, kind: .note) }
    private func folder(_ p: String) -> Result<URL, SafePath.Failure> { SafePath.resolve(p, in: s.url, kind: .folder) }
    private func code(_ r: Result<URL, SafePath.Failure>) -> String? { if case .failure(let f) = r { return f.code }; return nil }
    private func message(_ r: Result<URL, SafePath.Failure>) -> String? { if case .failure(let f) = r { return f.message }; return nil }

    func testNotesInsideTheFolderResolve() throws {
        XCTAssertEqual(try note("A.md").get(), s.url.appendingPathComponent("A.md"))
        XCTAssertNoThrow(try note("Sub/B.txt").get())
        XCTAssertNoThrow(try note("Sub/C.markdown").get())
        XCTAssertNoThrow(try note("Sub//deep/D.md").get(), "empty path parts are skipped")
    }

    func testTraversalAbsoluteAndTildePathsAreRefused() {
        for p in ["../Out.md", "Sub/../../Out.md", "/etc/passwd.md", "~/x.md"] {
            XCTAssertEqual(code(note(p)), "outside_folder", p)
            XCTAssertEqual(code(folder(p)), "outside_folder", p)
        }
        XCTAssertEqual(message(note("/a.md")), "Use a path relative to the folder.")
        XCTAssertEqual(message(note("../a.md")), "The path leaves the folder.")
    }

    func testHiddenPartsAreRefusedInTheWrittenPath() {
        for p in [".hidden.md", ".secret/x.md", "Sub/.x.md"] {
            XCTAssertEqual(code(note(p)), "not_a_note", p)
            XCTAssertEqual(message(note(p)), "Hidden files are not available.", p)
        }
        XCTAssertEqual(code(folder(".secret")), "not_a_note")
    }

    func testOnlyNoteExtensionsAreNotes() {
        for p in ["page.html", "Sub", "A"] {
            XCTAssertEqual(code(note(p)), "not_a_note", p)
        }
        XCTAssertEqual(message(note("page.html")), "Only .md, .markdown and .txt notes are available.")
        XCTAssertEqual(message(note("Missing.md")), "No such note.")
    }

    func testASymlinkOutOfTheFolderIsRefusedAndOneInsideIsFine() throws {
        try FileManager.default.createSymbolicLink(at: s.path("link.md"), withDestinationURL: outside.path("Out.md"))
        try FileManager.default.createSymbolicLink(at: s.path("dirlink"), withDestinationURL: outside.path("Dir"))
        try FileManager.default.createSymbolicLink(at: s.path("inside.md"), withDestinationURL: s.path("A.md"))
        XCTAssertEqual(code(note("link.md")), "outside_folder")
        XCTAssertEqual(code(note("dirlink/E.md")), "outside_folder")
        XCTAssertEqual(code(folder("dirlink")), "outside_folder")
        XCTAssertEqual(try note("inside.md").get().lastPathComponent, "A.md")
    }

    func testAVisibleNameLinkingToAHiddenTargetIsRefused() throws {
        try FileManager.default.createSymbolicLink(at: s.path("visible.md"), withDestinationURL: s.path(".secret/x.md"))
        try FileManager.default.createSymbolicLink(at: s.path("visibledir"), withDestinationURL: s.path(".secret"))
        try FileManager.default.createSymbolicLink(at: s.path("viahidden.md"), withDestinationURL: s.path(".hidden.md"))
        for p in ["visible.md", "visibledir/x.md", "viahidden.md"] {
            XCTAssertEqual(code(note(p)), "not_a_note", p)
            XCTAssertEqual(message(note(p)), "Hidden files are not available.", p)
        }
        XCTAssertEqual(code(folder("visibledir")), "not_a_note")
    }

    func testFoldersResolveAndNotesDoNotCountAsFolders() throws {
        XCTAssertEqual(try folder("Sub").get().lastPathComponent, "Sub")
        XCTAssertNoThrow(try folder("Sub/deep").get())
        XCTAssertEqual(code(folder("A.md")), "not_a_note")
        XCTAssertEqual(message(folder("A.md")), "No such folder.")
        XCTAssertEqual(message(folder("Nope")), "No such folder.")
    }

    func testThePackageIsRefused() throws {
        try s.write("Thing.app/Contents/Info.plist", "x")
        try s.write("Bundle.bundle/n.md", "x")
        XCTAssertEqual(code(folder("Thing.app")), "not_a_note")
        XCTAssertEqual(code(folder("Bundle.bundle")), "not_a_note")
    }

    func testTheRootIsAFolderButNotANote() throws {
        XCTAssertEqual(try folder("").get(), s.url.resolvingSymlinksInPath())
        XCTAssertEqual(try folder("/".dropFirst().description).get(), s.url.resolvingSymlinksInPath())
        XCTAssertEqual(code(note("")), "not_a_note")
        XCTAssertEqual(code(folder("/")), "outside_folder")
    }

    func testRelativeGivesThePathBelowTheRoot() throws {
        XCTAssertEqual(SafePath.relative(s.path("Sub/B.txt"), in: s.url), "Sub/B.txt")
        XCTAssertEqual(SafePath.relative(s.url, in: s.url), "")
        XCTAssertNil(SafePath.relative(outside.path("Out.md"), in: s.url))
        XCTAssertNil(SafePath.relative(URL(fileURLWithPath: s.url.path + "-sibling/x.md"), in: s.url), "a sibling that shares the prefix is outside")
    }

    func testTheAgentToolsKeepTheirBehaviour() throws {
        switch AgentTools.resolve("A.md", in: s.url) {
        case .success(let u): XCTAssertEqual(u.lastPathComponent, "A.md")
        case .failure(let e): XCTFail(e.message)
        }
        if case .failure(let e) = AgentTools.resolve("../x.md", in: s.url) { XCTAssertEqual(e.code, "outside_folder") } else { XCTFail() }
        if case .failure(let e) = AgentTools.resolve("pic.png", in: s.url) { XCTAssertEqual(e.code, "not_a_note") } else { XCTFail() }
        // HTML, JSON and YAML are text files to the agent tools, like notes
        for p in ["page.html", "Sub/B.txt"] { if case .failure(let e) = AgentTools.resolve(p, in: s.url) { XCTFail(e.message) } }
        XCTAssertNil(AgentTools.relative(s.url, in: s.url), "the root has no relative path for the agent tools")
        XCTAssertEqual(AgentTools.relative(s.path("Sub/B.txt"), in: s.url), "Sub/B.txt")
        XCTAssertNil(AgentTools.relative(nil, in: s.url))
    }
}
