import XCTest
@testable import MDEdit

/// The rule: a file is never changed unless the user changed it, and an edit is never lost.
final class DocumentSafetyTests: XCTestCase {
    var s: Scratch!
    var store: DocumentStore!

    override func setUpWithError() throws { s = try Scratch(); store = DocumentStore() }
    override func tearDown() { store = nil; s.remove() }

    // MARK: encodings

    func testUTF8RoundTripIsByteIdentical() throws {
        let u = try s.write("a.md", "# Héllo — “quoted” 日本語 🎉\nline2\n")
        let before = try Data(contentsOf: u)
        store.open(u)
        XCTAssertEqual(store.text, "# Héllo — “quoted” 日本語 🎉\nline2\n")
        store.text += "x"; store.text.removeLast()          // dirty, then back
        store.saveNow()
        XCTAssertEqual(try Data(contentsOf: u), before)
    }

    func testLatin1FileIsReadAndWrittenBackAsLatin1() throws {
        let bytes = Data([0x63, 0x61, 0x66, 0xE9, 0x0A])         // "café\n" in Latin-1 / CP1252
        let u = try s.write("l.txt", bytes)
        store.open(u)
        XCTAssertFalse(store.unreadable)
        XCTAssertEqual(store.text, "café\n")
        store.text += "ü"
        store.saveNow()
        XCTAssertEqual(try Data(contentsOf: u), Data([0x63, 0x61, 0x66, 0xE9, 0x0A, 0xFC]), "stays in its own encoding")
    }

    func testTextThatTheFileEncodingCannotHoldIsSavedAsUTF8NotLost() throws {
        let u = try s.write("l.txt", Data([0x63, 0xE9]))
        store.open(u)
        store.text += " 🎉"
        store.saveNow()
        XCTAssertEqual(try String(contentsOf: u, encoding: .utf8), "cé 🎉")
    }

    func testUTF8BOMIsKept() throws {
        let u = try s.write("b.md", Data([0xEF, 0xBB, 0xBF]) + Data("hi".utf8))
        store.open(u)
        XCTAssertEqual(store.text, "hi")
        store.text = "hi there"; store.saveNow()
        XCTAssertEqual(try Data(contentsOf: u), Data([0xEF, 0xBB, 0xBF]) + Data("hi there".utf8))
    }

    func testUTF16WithBOMRoundTrips() throws {
        let u = try s.write("w.txt", "wide ✓".data(using: .utf16)!)
        store.open(u)
        XCTAssertEqual(store.text, "wide ✓")
        store.text += "!"; store.saveNow()
        XCTAssertEqual(try String(data: Data(contentsOf: u), encoding: .utf16), "wide ✓!")
    }

    func testCRLFAndLoneCRSurvive() throws {
        let u = try s.write("c.md", "a\r\nb\rc\n")
        let before = try Data(contentsOf: u)
        store.open(u)
        store.text += "x"; store.text.removeLast(); store.saveNow()
        XCTAssertEqual(try Data(contentsOf: u), before)
    }

    // MARK: files that are not text

    func testBinaryFileIsRefusedAndNeverWritten() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, 0x48, 0x44, 0x52, 0xFF, 0xFE, 0x00])
        let u = try s.write("fake.md", png)
        store.open(u)
        XCTAssertTrue(store.unreadable)
        XCTAssertEqual(store.text, "")
        XCTAssertNotNil(store.error)
        store.text = "typed over it"          // a view that failed to disable editing
        store.saveNow(); store.flush(); store.keepMine()
        XCTAssertEqual(try Data(contentsOf: u), png, "the original bytes are untouched")
        XCTAssertFalse(s.exists("fake (unsaved changes).md"))
    }

    func testFileOverTheLimitIsRefusedAndUntouched() throws {
        let u = s.path("big.md")
        FileManager.default.createFile(atPath: u.path, contents: nil)
        let h = try FileHandle(forWritingTo: u)
        try h.truncate(atOffset: UInt64(DocumentStore.maxBytes + 1)); try h.close()
        store.open(u)
        XCTAssertTrue(store.unreadable)
        XCTAssertTrue(store.error?.contains("too large") == true, store.error ?? "")
        store.text = "x"; store.flush()
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int), DocumentStore.maxBytes + 1)
    }

    func testMissingAndUnreadableFilesGiveAnErrorNotACrash() throws {
        store.open(s.path("missing.md"))
        XCTAssertTrue(store.unreadable)
        let u = try s.write("locked.md", "secret")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: u.path)
        store.open(u)
        XCTAssertTrue(store.unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: u.path)
    }

    func testDecodeNeverCrashesOnRandomBytes() {
        var rng = SeededRNG(seed: 7)
        for _ in 0..<500 {
            let n = Int.random(in: 0...200, using: &rng)
            let d = Data((0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) })
            _ = try? DocumentStore.decode(d)
        }
    }

    // MARK: outside changes

    func testOutsideChangeIsNotWrittenOverWhileEditing() throws {
        let u = try s.write("n.md", "original")
        store.open(u)
        store.text = "my edit"
        try "someone else".write(to: u, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: u.path)
        store.saveNow()
        XCTAssertEqual(try s.read("n.md"), "someone else", "autosave must not clobber it")
        XCTAssertTrue(store.changedOnDisk)
        XCTAssertTrue(store.dirty, "my edit is still held")
    }

    func testKeepMineOverwritesAndReloadTakesTheirs() throws {
        let u = try s.write("n.md", "original")
        store.open(u); store.text = "mine"
        try "theirs".write(to: u, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: u.path)
        store.checkDisk()
        XCTAssertTrue(store.changedOnDisk)
        store.keepMine()
        XCTAssertEqual(try s.read("n.md"), "mine")
        XCTAssertFalse(store.changedOnDisk)

        store.text = "mine again"
        try "theirs again".write(to: u, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: u.path)
        store.checkDisk()
        store.reloadFromDisk()
        XCTAssertEqual(store.text, "theirs again")
        XCTAssertFalse(store.dirty)
    }

    func testCleanDocumentFollowsAnOutsideChange() throws {
        let u = try s.write("n.md", "one")
        store.open(u)
        try "two".write(to: u, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: u.path)
        store.checkDisk()
        XCTAssertEqual(store.text, "two")
        XCTAssertFalse(store.changedOnDisk)
    }

    func testEditsAreKeptInARecoveryCopyWhenTheFileIsInConflictAndIsLeft() throws {
        let u = try s.write("n.md", "original")
        store.open(u); store.text = "precious edit"
        try "theirs".write(to: u, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: u.path)
        store.open(nil)                          // moving to another note, or the window closing
        XCTAssertEqual(try s.read("n.md"), "theirs")
        XCTAssertEqual(try s.read("n (unsaved changes).md"), "precious edit")
    }

    func testDeletedWhileCleanClosesAndDeletedWhileEditingKeepsTheText() throws {
        let u = try s.write("gone.md", "x")
        store.open(u)
        try FileManager.default.removeItem(at: u)
        store.checkDisk()
        XCTAssertNil(store.url)

        let v = try s.write("kept.md", "x")
        store.open(v); store.text = "important"
        try FileManager.default.removeItem(at: v)
        store.checkDisk()
        XCTAssertEqual(store.text, "important", "an edit is not discarded because the file vanished")
        store.saveNow()
        XCTAssertEqual(try s.read("kept.md"), "important", "saving puts the file back")
    }

    // MARK: never losing an edit

    func testSwitchingNotesSavesTheFirst() throws {
        let a = try s.write("a.md", "a"), b = try s.write("b.md", "b")
        store.open(a); store.text = "a edited"
        store.open(b)
        XCTAssertEqual(try s.read("a.md"), "a edited")
        XCTAssertEqual(store.text, "b")
    }

    func testClosingTheWindowWithinTheAutosaveDelayStillSaves() throws {
        let u = try s.write("a.md", "a")
        var local: DocumentStore? = DocumentStore()
        local!.open(u)
        local!.text = "typed just now"
        local = nil                                // the window closed; the 0.8s timer never fired
        XCTAssertEqual(try s.read("a.md"), "typed just now")
    }

    func testAutosaveFiresAfterTheDelay() throws {
        let u = try s.write("a.md", "a")
        store.open(u); store.text = "later"
        let saved = expectation(description: "autosaved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { saved.fulfill() }
        wait(for: [saved], timeout: 4)
        XCTAssertEqual(try s.read("a.md"), "later")
        XCTAssertFalse(store.dirty)
    }

    func testRelocateKeepsTheText() throws {
        let u = try s.write("a.md", "a")
        store.open(u); store.text = "edit"
        let moved = s.path("b.md")
        try FileManager.default.moveItem(at: u, to: moved)
        store.relocate(to: moved)
        store.saveNow()
        XCTAssertEqual(try s.read("b.md"), "edit")
    }

    // MARK: links and write failures

    func testSavingThroughASymlinkKeepsTheLink() throws {
        let target = try s.write("real/target.md", "t")
        let link = s.path("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        store.open(link)
        XCTAssertEqual(store.text, "t")
        store.text = "edited through the link"; store.saveNow()
        XCTAssertEqual(try s.read("real/target.md"), "edited through the link")
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path), "still a link")
    }

    func testWriteFailureIsReportedAndTheEditIsKept() throws {
        let u = try s.write("ro/a.md", "a")
        store.open(u); store.text = "edit"
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: s.path("ro").path)
        store.saveNow()
        XCTAssertNotNil(store.error)
        XCTAssertTrue(store.dirty, "still unsaved, so a later save can succeed")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: s.path("ro").path)
        store.saveNow()
        XCTAssertEqual(try s.read("ro/a.md"), "edit")
        XCTAssertNil(store.error)
    }

    func testEmptyFileOpensAndSaves() throws {
        let u = try s.write("e.md", "")
        store.open(u)
        XCTAssertEqual(store.text, ""); XCTAssertFalse(store.unreadable)
        store.text = "now"; store.saveNow()
        XCTAssertEqual(try s.read("e.md"), "now")
    }
}

/// Saving replaces a file atomically; what belongs to the file (permissions, Finder tags and other extended attributes) must survive.
final class DocumentMetadataTests: XCTestCase {
    func testSavingKeepsPermissionsAndExtendedAttributes() throws {
        let s = try Scratch(["n.md": "one"]); defer { s.remove() }
        let u = s.path("n.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
        let tag = Data("bplist-ish".utf8)
        XCTAssertEqual(tag.withUnsafeBytes { setxattr(u.path, "com.apple.metadata:_kMDItemUserTags", $0.baseAddress, tag.count, 0, 0) }, 0)

        let store = DocumentStore()
        store.open(u)
        store.text = "two"
        store.saveNow()
        XCTAssertEqual(try s.read("n.md"), "two")

        let perms = (try FileManager.default.attributesOfItem(atPath: u.path)[.posixPermissions] as? Int) ?? 0
        XCTAssertEqual(perms, 0o600, "permissions are kept")
        let size = getxattr(u.path, "com.apple.metadata:_kMDItemUserTags", nil, 0, 0, 0)
        XCTAssertEqual(size, tag.count, "Finder tags and other extended attributes are kept")
    }

    func testSavingKeepsTheFileIdentityWhereItMatters() throws {
        let s = try Scratch(["n.md": "one"]); defer { s.remove() }
        let u = s.path("n.md")
        let created = (try FileManager.default.attributesOfItem(atPath: u.path)[.creationDate] as? Date)
        let store = DocumentStore(); store.open(u); store.text = "two"; store.saveNow()
        let after = (try FileManager.default.attributesOfItem(atPath: u.path)[.creationDate] as? Date)
        XCTAssertEqual(created, after, "the creation date is kept")
    }
}
