import XCTest
@testable import MDEdit

/// The font lists come from the Mac's installed fonts; ⌘= ⌘- change the size and ⇧⌘- ⇧⌘= the margins (bigger, smaller).
@MainActor
final class FontAndMarginTests: XCTestCase {
    func testTheEditorListHoldsMonospacedFontsOnly() {
        let mono = Fonts.monospacedFamilies
        for f in ["IBM Plex Mono", "Menlo"] { XCTAssertTrue(mono.contains(f), f) }
        for f in ["Helvetica Neue", "Georgia", "Inter"] { XCTAssertFalse(mono.contains(f), f) }
        XCTAssertEqual(mono, mono.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func testTheViewerListHoldsSansAndSerifFontsButNoMonospaceOrSymbols() {
        let text = Fonts.readingFamilies
        for f in ["Inter", "Literata", "Source Serif 4", "Helvetica Neue", "Georgia"] { XCTAssertTrue(text.contains(f), f) }
        for f in ["Menlo", "IBM Plex Mono", "Zapfino", "Webdings"] { XCTAssertFalse(text.contains(f), f) }
        XCTAssertTrue(text.allSatisfy { Preferences.cleanFamily($0) == $0 }, "every name is safe to put in a stylesheet")
        XCTAssertFalse(text.contains { $0.hasPrefix(".") })
    }

    func testBothListsAreLargerThanTheOldShortLists() {
        XCTAssertGreaterThan(Fonts.monospacedFamilies.count, 5)
        XCTAssertGreaterThan(Fonts.readingFamilies.count, 20)
    }

    func testFontSizeStepsAndStaysWithinSettingsRange() {
        let p = Preferences(defaults: isolatedDefaults())
        p.editorSize = 17; p.viewerSize = 18
        p.changeTextSize(by: 1, viewer: false); XCTAssertEqual(p.editorSize, 18); XCTAssertEqual(p.viewerSize, 18)
        p.changeTextSize(by: -2, viewer: true); XCTAssertEqual(p.viewerSize, 16); XCTAssertEqual(p.editorSize, 18)
        for _ in 0..<40 { p.changeTextSize(by: 1, viewer: false); p.changeTextSize(by: -1, viewer: true) }
        XCTAssertEqual(p.editorSize, 28); XCTAssertEqual(p.viewerSize, 12)
    }

    func testBiggerMarginsMakeTheLineNarrowerAndTheCustomFlagFollows() {
        let p = Preferences(defaults: isolatedDefaults())
        p.lineWidth = 72; p.widthCustom = false
        p.changeMargins(direction: 1, viewer: false)
        XCTAssertEqual(p.lineWidth, 68); XCTAssertTrue(p.widthCustom, "68 is not a preset")
        p.changeMargins(direction: 1, viewer: false)
        XCTAssertEqual(p.lineWidth, 64); XCTAssertFalse(p.widthCustom, "64 is Narrow again")
        p.changeMargins(direction: -1, viewer: false); p.changeMargins(direction: -1, viewer: false)
        XCTAssertEqual(p.lineWidth, 72); XCTAssertFalse(p.widthCustom)
        for _ in 0..<60 { p.changeMargins(direction: 1, viewer: false) }
        XCTAssertEqual(p.lineWidth, 40)
        for _ in 0..<60 { p.changeMargins(direction: -1, viewer: false) }
        XCTAssertEqual(p.lineWidth, 160)
    }

    func testViewerMarginsAreSeparateFromTheEditors() {
        let p = Preferences(defaults: isolatedDefaults())
        let editor = p.lineWidth
        p.changeMargins(direction: 1, viewer: true)
        XCTAssertEqual(p.viewerWidth, ViewerStyle.specWidth - 4)
        XCTAssertEqual(p.lineWidth, editor)
        for _ in 0..<60 { p.changeMargins(direction: -1, viewer: true) }
        XCTAssertEqual(p.viewerWidth, 120)
    }

    func testTheCommandsHaveTheirShortcutsAndActOnTheModeInUse() throws {
        let s = try Scratch(["A.md": "a"]); addTeardownBlock { s.remove() }
        let ws = makeWorkspace(open: s.url)
        let prefs = Preferences(defaults: isolatedDefaults())
        func cmd(_ id: String) -> Cmd { makeCommands(ws: ws, prefs: prefs, recents: RecentFolders(defaults: isolatedDefaults()), newWindow: { _ in }).first { $0.id == id }! }
        XCTAssertEqual(cmd("font-bigger").shortcut, "⌘="); XCTAssertEqual(cmd("font-smaller").shortcut, "⌘-")
        XCTAssertEqual(cmd("margins-bigger").shortcut, "⇧⌘-"); XCTAssertEqual(cmd("margins-smaller").shortcut, "⇧⌘=")
        let e = prefs.editorSize, v = prefs.viewerSize, w = prefs.lineWidth, vw = prefs.viewerWidth
        ws.mode = .write
        cmd("font-bigger").run(); cmd("margins-bigger").run()
        XCTAssertEqual(prefs.editorSize, e + 1); XCTAssertEqual(prefs.lineWidth, w - 4)
        XCTAssertEqual(prefs.viewerSize, v); XCTAssertEqual(prefs.viewerWidth, vw)
        ws.mode = .view
        cmd("font-smaller").run(); cmd("margins-smaller").run()
        XCTAssertEqual(prefs.viewerSize, v - 1); XCTAssertEqual(prefs.viewerWidth, vw + 4)
        XCTAssertEqual(prefs.editorSize, e + 1)
    }

    // MARK: the settings take effect

    func testTheSavedFontStaysInThePickerWhenItIsNotInstalledOrNotOfThatKind() {
        XCTAssertEqual(SettingsView.choices(["A", "B"], keeping: "B"), ["A", "B"])
        XCTAssertEqual(SettingsView.choices(["A", "B"], keeping: "Source Serif 4"), ["Source Serif 4", "A", "B"], "an old serif choice for the editor is kept")
        XCTAssertEqual(SettingsView.choices(["A"], keeping: "Gone")[0], "Gone")
        XCTAssertFalse(Fonts.installed("Gone Font That Is Not Installed"))
    }

    func testEveryListedFontResolvesToARealFontOfThatKind() {
        for f in Fonts.monospacedFamilies.prefix(40) {
            let font = Fonts.nsFont(family: f, size: 14)
            XCTAssertNotNil(font, f)
            XCTAssertEqual(font?.isFixedPitch, true, "\(f) should be monospaced")
        }
        for f in Fonts.readingFamilies.prefix(60) { XCTAssertNotNil(Fonts.nsFont(family: f, size: 14), f) }
    }

    func testPickingAnInstalledMonospacedFontChangesTheEditorFont() {
        let p = Preferences(defaults: isolatedDefaults())
        p.editorFont = "Menlo"
        XCTAssertEqual(p.editorNSFont().familyName, "Menlo")
        XCTAssertEqual(p.editorNSFont(size: 20).pointSize, 20)
        let d = isolatedDefaults(); let q = Preferences(defaults: d); q.editorFont = "Menlo"
        XCTAssertEqual(Preferences(defaults: d).editorFont, "Menlo", "the choice is saved")
    }

    func testPickingAnInstalledFontChangesTheViewerStyleAndItsPage() {
        let p = Preferences(defaults: isolatedDefaults())
        p.viewerFont = "Georgia"
        XCTAssertEqual(p.viewerStyle.family, "Georgia")
        XCTAssertTrue(PreviewPage.css(p.viewerStyle).contains("\"Georgia\""))
    }

    func testSizeAndMarginChangesAreSavedAndComeBackAfterARestart() {
        let d = isolatedDefaults(); let p = Preferences(defaults: d)
        p.changeTextSize(by: 1, viewer: false); p.changeTextSize(by: -1, viewer: true)
        p.changeMargins(direction: 1, viewer: false); p.changeMargins(direction: -1, viewer: true)
        let q = Preferences(defaults: d)
        XCTAssertEqual(q.editorSize, 18); XCTAssertEqual(q.viewerSize, 17)
        XCTAssertEqual(q.lineWidth, 68); XCTAssertTrue(q.widthCustom)
        XCTAssertEqual(q.viewerWidth, ViewerStyle.specWidth + 4); XCTAssertTrue(q.viewerWidthCustom)
    }

    func testTheEditorGrowsAndItsColumnNarrowsWhenTheCommandsRun() throws {
        let s = try Scratch(["A.md": "one\ntwo\n"]); addTeardownBlock { s.remove() }
        let ws = makeWorkspace(open: s.url); let prefs = Preferences(defaults: isolatedDefaults())
        func cmd(_ id: String) -> Cmd { makeCommands(ws: ws, prefs: prefs, recents: RecentFolders(defaults: isolatedDefaults()), newWindow: { _ in }).first { $0.id == id }! }
        func editor() -> EditorTextView {
            let tv = EditorTextView(frame: NSRect(x: 0, y: 0, width: 1400, height: 600))
            tv.style = EditorStyle(fontName: prefs.editorFont, size: CGFloat(prefs.editorSize), lineWidth: prefs.lineWidth, headingSizes: prefs.headingSizes)
            tv.string = "one\n"; tv.restyle(); tv.updateInsets()
            return tv
        }
        ws.mode = .write
        let before = editor()
        let size0 = (before.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as! NSFont).pointSize
        cmd("font-bigger").run(); cmd("font-bigger").run()
        let bigger = editor()
        XCTAssertEqual((bigger.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as! NSFont).pointSize, size0 + 2)
        // a wider margin is more room on each side of the text (measured at the new size: bigger letters make the column wider too)
        let gutter = bigger.textContainerInset.width
        for _ in 0..<6 { cmd("margins-bigger").run() }
        XCTAssertGreaterThan(editor().textContainerInset.width, gutter, "bigger margins: the text column sits further from the edges")
        for _ in 0..<12 { cmd("margins-smaller").run() }
        XCTAssertLessThan(editor().textContainerInset.width, gutter, "smaller margins: a wider column")
    }

    func testTheViewerFollowsTheSizeAndMarginCommands() {
        let prefs = Preferences(defaults: isolatedDefaults())
        let m0 = prefs.viewerStyle.measure, b0 = prefs.viewerStyle.body
        prefs.changeMargins(direction: 1, viewer: true)
        XCTAssertLessThan(prefs.viewerStyle.measure, m0, "bigger margins, a narrower column")
        prefs.changeMargins(direction: -1, viewer: true); prefs.changeMargins(direction: -1, viewer: true)
        XCTAssertGreaterThan(prefs.viewerStyle.measure, m0)
        prefs.changeTextSize(by: 1, viewer: true)
        XCTAssertEqual(prefs.viewerStyle.body, b0 + 1)
    }

    func testTheCommandsAreInTheViewMenuAndNeedAWindow() {
        let all = makeCommands(ws: nil, prefs: Preferences(defaults: isolatedDefaults()), recents: RecentFolders(defaults: isolatedDefaults()), newWindow: { _ in })
        for id in ["font-bigger", "font-smaller", "margins-bigger", "margins-smaller"] {
            let c = all.first { $0.id == id }!
            XCTAssertEqual(c.place, .view, id); XCTAssertFalse(c.enabled, "\(id) needs a window to act on")
        }
    }

    func testTheOldFontChoicesStillWork() {
        let d = isolatedDefaults(); d.set("Source Serif 4", forKey: "editorFont"); d.set("Helvetica Neue", forKey: "viewerFont")
        let p = Preferences(defaults: d)
        XCTAssertEqual(p.editorNSFont().familyName, "Source Serif 4")
        XCTAssertEqual(p.viewerFont, "Helvetica Neue")
    }
}
