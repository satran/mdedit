import XCTest
@testable import MDEdit

final class FindEngineTests: XCTestCase {
    private func find(_ text: String, _ q: String, _ rep: String = "", _ o: FindOptions = FindOptions()) throws -> FindEngine.Result {
        FindEngine.search(text, try XCTUnwrap(try FindEngine.compile(q, replacement: rep, options: o)))
    }
    private func replaceAll(_ text: String, _ q: String, _ rep: String, _ o: FindOptions = FindOptions(), only: Set<Int>? = nil) throws -> (text: String, count: Int)? {
        FindEngine.replace(in: text, try XCTUnwrap(try FindEngine.compile(q, replacement: rep, options: o)), only: only)
    }

    func testPlainSearchIsCaseInsensitiveByDefault() throws {
        let r = try find("Time to restore, time to restore, TIME TO RESTORE", "time to restore")
        XCTAssertEqual(r.matches.count, 3)
        XCTAssertEqual(try find("Time time", "time", "", FindOptions(matchCase: true)).matches.map(\.range.location), [5])
    }

    func testTheQueryIsLiteralUnlessRegexIsOn() throws {
        XCTAssertEqual(try find("a.c abc a.c", "a.c").matches.count, 2)
        XCTAssertEqual(try find("a.c abc a.c", "a.c", "", FindOptions(regex: true)).matches.count, 3)
        XCTAssertEqual(try find("(x) [y] $1 \\d", "(x) [y] $1 \\d").matches.count, 1)
    }

    func testWholeWordSkipsPartsOfWords() throws {
        let o = FindOptions(wholeWord: true)
        XCTAssertEqual(try find("cat concat cat's cats café_cat cat.", "cat", "", o).matches.map(\.range.location), [0, 11, 31])
        XCTAssertEqual(try find("naïve naïvety", "naïve", "", o).matches.count, 1, "accented letters are letters")
    }

    func testAnInvalidPatternIsReportedNotCrashed() {
        XCTAssertThrowsError(try FindEngine.compile("(unclosed", replacement: "", options: FindOptions(regex: true)))
        XCTAssertNil(try FindEngine.compile("", replacement: "x", options: FindOptions()))
    }

    func testLinesAreOneBasedAndContextIsTheLine() throws {
        let m = try find("one\ntwo target here\n\nfour target", "target").matches
        XCTAssertEqual(m.map(\.line), [2, 4])
        XCTAssertEqual(m[0].before, "two "); XCTAssertEqual(m[0].text, "target"); XCTAssertEqual(m[0].after, " here")
    }

    func testRangesAreUTF16SoEmojiAndCombiningMarksLineUp() throws {
        let text = "😀😀 find 👨‍👩‍👧 find"
        let r = try find(text, "find").matches
        let ns = text as NSString
        XCTAssertEqual(r.map { ns.substring(with: $0.range) }, ["find", "find"])
        XCTAssertEqual(try replaceAll(text, "find", "X")?.text, "😀😀 X 👨‍👩‍👧 X")
    }

    func testAMatchInAVeryLongLineGivesAShortRow() throws {
        let line = String(repeating: "x", count: 5_000) + "needle" + String(repeating: "y", count: 5_000)
        let m = try find(line, "needle").matches[0]
        XCTAssertLessThan(m.before.count + m.text.count + m.after.count, 120)
        XCTAssertTrue(m.before.hasPrefix("…")); XCTAssertTrue(m.after.hasSuffix("…"))
    }

    func testReplaceAll() throws {
        XCTAssertEqual(try replaceAll("a b a", "a", "z")?.text, "z b z")
        XCTAssertEqual(try replaceAll("a b a", "a", "z")?.count, 2)
        XCTAssertEqual(try replaceAll("remove me", " me", "")?.text, "remove")
    }

    func testRegexReplacementUsesGroupsButPlainDoesNot() throws {
        XCTAssertEqual(try replaceAll("2026-11-02", #"(\d+)-(\d+)-(\d+)"#, "$3/$2/$1", FindOptions(regex: true))?.text, "02/11/2026")
        XCTAssertEqual(try replaceAll("cost", "cost", "$1 \\1")?.text, "$1 \\1", "plain mode takes the replacement as typed")
    }

    func testPreserveCase() throws {
        let o = FindOptions(preserveCase: true)
        let out = try replaceAll("time to restore, Time to restore, TIME TO RESTORE, tIME", "time to restore", "failed deployment recovery time", o)
        XCTAssertEqual(out?.text, "failed deployment recovery time, Failed deployment recovery time, FAILED DEPLOYMENT RECOVERY TIME, tIME")
        XCTAssertEqual(FindEngine.recase("see DORA", like: "item"), "see DORA", "names keep their capitals")
        XCTAssertEqual(FindEngine.recase("mixed", like: "tIME"), "mixed")
        XCTAssertEqual(try replaceAll("a", "a", "b", FindOptions(preserveCase: false))?.text, "b")
    }

    func testOnlyTheChosenMatchesChange() throws {
        let text = "a a a"
        XCTAssertEqual(try replaceAll(text, "a", "z", only: [2])?.text, "a z a")
        XCTAssertNil(try replaceAll(text, "a", "z", only: [1]), "a position that is no longer a match means the text changed")
    }

    func testZeroLengthMatchesAreIgnored() throws {
        XCTAssertEqual(try find("abc", "^", "", FindOptions(regex: true)).matches.count, 0)
        XCTAssertEqual(try replaceAll("a\nb", "x*", "-", FindOptions(regex: true))?.text, "a\nb")
    }

    func testTheCapAndTheTimeLimitStopRunawaySearches() throws {
        let many = String(repeating: "a ", count: 6_000)
        let r = try find(many, "a")
        XCTAssertEqual(r.matches.count, FindEngine.maxMatchesPerFile); XCTAssertTrue(r.truncated)
        // catastrophic backtracking: must come back, cut short
        let evil = String(repeating: "a", count: 40) + "!"
        let c = try XCTUnwrap(try FindEngine.compile("(a+)+$", replacement: "", options: FindOptions(regex: true)))
        let start = Date()
        _ = FindEngine.search(evil, c, deadline: Date().addingTimeInterval(0.3))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testMultiLineQueryAndMultiLineAnchors() throws {
        XCTAssertEqual(try find("a\nb\na\nb", "a\nb").matches.count, 2)
        XCTAssertEqual(try find("x\nfoo\nfoo bar", "^foo$", "", FindOptions(regex: true)).matches.count, 1)
    }

    func testTheSpacesNextToAMatchAreKeptAndOnlyTheLineEdgesTrimmed() throws {
        let m = try find("  improve time to restore.  \n", "time to restore").matches[0]
        XCTAssertEqual(m.before, "improve "); XCTAssertEqual(m.after, ".")
        let n = try find("| time to restore | x |", "time to restore").matches[0]
        XCTAssertEqual(n.before, "| "); XCTAssertEqual(n.after, " | x |")
    }
}
