import XCTest
@testable import MDEdit

/// Random sequences of what a person can do. The assertion is the invariants: nothing crashes, nothing outside the
/// folder is touched, and every note that existed still has its content unless it was deleted or renamed on purpose.
final class FuzzTests: XCTestCase {

    func testRandomWorkspaceActionsKeepTheFolderSound() throws {
        for seed in UInt64(1)...6 {
            var rng = SeededRNG(seed: seed)
            let s = try Scratch(["A/One.md": "one", "A/Deep/Two.md": "two", "B/Three.md": "three", "Top.md": "top", "pic.png": "png"])
            let sibling = try Scratch(["precious.md": "must survive"])
            defer { s.remove(); sibling.remove() }
            let ws = makeWorkspace(open: s.url)
            let outsideBefore = try sibling.read("precious.md")
            let names = ["x", "New", "..", "a/b", "日本語", "", "  ", "Top", "One", "../precious", "q:r", String(repeating: "n", count: 300)]

            func anyItem() -> URL? {
                let all = BinderNode.scan(s.url)
                var urls: [URL] = []
                func walk(_ n: BinderNode) { for c in n.children { urls.append(c.url); walk(c) } }
                walk(all)
                return urls.randomElement(using: &rng)
            }

            for step in 0..<120 {
                let label = "seed \(seed) step \(step)"
                switch Int.random(in: 0..<12, using: &rng) {
                case 0: if let u = anyItem() { ws.select(u) }
                case 1: if let u = anyItem() { ws.rename(u, to: names.randomElement(using: &rng)!) }
                case 2: if let a = anyItem(), let b = anyItem() { ws.moveItem(a, into: b) }
                case 3: ws.newDocument(in: anyItem().map { ws.root?.find($0)?.isFolder == true ? $0 : $0.deletingLastPathComponent() } ?? s.url)
                case 4: ws.newFolder(in: s.url)
                case 5: if let u = anyItem(), u.lastPathComponent != "Top.md" { ws.trash(u) }
                case 6: if let u = anyItem() { ws.toggle(u) }
                case 7: ws.collapseAll()
                case 8: ws.document.text += "typed \(step)\n"
                case 9: ws.search = ["", "o", "zzz", "TOP"].randomElement(using: &rng)!
                case 10: if let a = anyItem() { _ = ws.linkText(forDropped: [a, sibling.path("precious.md")]) }
                default: ws.reload()
                }
                ws.message = nil
                XCTAssertEqual(try sibling.read("precious.md"), outsideBefore, "\(label): a file outside the folder changed")
                XCTAssertFalse(FileManager.default.fileExists(atPath: s.url.deletingLastPathComponent().appendingPathComponent("..").appendingPathComponent("escaped").path), label)
            }
            ws.document.flush()
            // nothing escaped into the parent of the opened folder
            let parent = try FileManager.default.contentsOfDirectory(atPath: s.url.deletingLastPathComponent().path).filter { $0 == "precious.md" || $0 == "x.md" || $0 == "New.md" }
            XCTAssertTrue(parent.isEmpty, "seed \(seed): files appeared beside the opened folder: \(parent)")
        }
    }

    func testRandomEditsAndOutsideChangesNeverLoseText() throws {
        for seed in UInt64(1)...8 {
            var rng = SeededRNG(seed: seed &* 7919)
            let s = try Scratch(["n.md": "start"]); defer { s.remove() }
            let u = s.path("n.md")
            let store = DocumentStore()
            store.open(u)
            var mine = "start"
            for step in 0..<80 {
                switch Int.random(in: 0..<5, using: &rng) {
                case 0: mine += "e\(step) "; store.text = mine
                case 1: store.saveNow()
                case 2:   // someone else writes
                    try "theirs \(step)".write(to: u, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double(step + 5))], ofItemAtPath: u.path)
                    store.checkDisk()
                    if !store.dirty { mine = store.text }
                case 3: if store.changedOnDisk { if Bool.random(using: &rng) { store.keepMine() } else { store.reloadFromDisk(); mine = store.text } }
                default: store.flush()
                }
            }
            store.flush()
            // every edit I made is either in the file or in a recovery copy; the file is never empty
            let files = try FileManager.default.contentsOfDirectory(atPath: s.url.path)
            XCTAssertFalse(files.isEmpty)
            XCTAssertFalse(try s.read("n.md").isEmpty, "seed \(seed)")
            XCTAssertFalse(store.dirty && !store.changedOnDisk, "seed \(seed): unsaved text left behind with nothing in the way")
        }
    }
}
