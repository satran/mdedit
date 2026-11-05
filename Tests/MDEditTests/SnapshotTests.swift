import XCTest
import SwiftUI
@testable import MDEdit

/// Renders the window offscreen to PNGs in the test's temp folder (see the paths it prints), so the look can be checked without a screen.
final class SnapshotTests: XCTestCase {
    static let sample = """
    ---
    title: DORA, you have a naming problem
    tags: [regulation, devops, compliance]
    aliases:
      - DORA
      - Naming problem
    date: 2026-10-31
    published: false
    related: "[[Goals]]"
    source: https://dora.dev
    ---
    # DORA, you have a naming problem

    Say “DORA” to a room of engineers and most of them will think of the four **DevOps metrics**. Say it to a room of compliance people and they will think of the *Digital Operational Resilience Act*.

    Both are about the same thing: how well your systems hold up when something goes wrong. One measures it. The other makes it law.

    ## Two acronyms, one question

    > Can we change our systems quickly without breaking them, and recover fast when we do?

    The metrics come from [DevOps Research and Assessment](https://dora.dev). Read them next to the regulation and the overlap is hard to miss:

    - **Time to restore** → incident management
    - **Change failure rate** → ICT change management
    - **Lead time** → `nothing`

    The Act has no opinion on speed. See [[Goals]] and [[Missing note]].

    ## Checklist

    - [x] Read the regulation
    - [ ] Write the letter
      - [ ] Outline

    | Metric | Owner | Target |
    |:--|:-:|--:|
    | Lead time | Dev | 1 day |
    | Time to restore | Ops | 1 hour |

    ```swift
    let answer = 42
    ```

    ~~Struck~~ and https://dora.dev

    The line above
    ```
    This is a code block
    ```
    The line below the code block.
    """

    func render(dark: Bool, mode: Mode, name: String, outline: Bool = false, panel: Workspace.RightPanel? = nil, focus: Bool = false, size: NSSize = NSSize(width: 1280, height: 820)) throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("snap-\(UUID().uuidString)")
        for d in ["Ideas", "Draft/A love letter to Regulations"] { try fm.createDirectory(at: dir.appendingPathComponent(d), withIntermediateDirectories: true) }
        try Self.sample.write(to: dir.appendingPathComponent("Draft/A love letter to Regulations/DORA, you have a naming problem.md"), atomically: true, encoding: .utf8)
        for f in ["Ideas/Goals.md", "Ideas/Highly performing teams.md", "Draft/Engineering Manager.md", "Why and How.md"] { try "# x".write(to: dir.appendingPathComponent(f), atomically: true, encoding: .utf8) }
        let ws = Workspace()
        ws.open(dir)
        ws.expanded = [dir.appendingPathComponent("Draft"), dir.appendingPathComponent("Draft/A love letter to Regulations"), dir.appendingPathComponent("Ideas")]
        ws.select(dir.appendingPathComponent("Draft/A love letter to Regulations/DORA, you have a naming problem.md"))
        ws.mode = mode
        ws.outlineVisible = outline
        if outline { ws.refreshBacklinks() }
        if let panel { ws.panel = panel }

        let host: NSHostingView<AnyView>
        if focus {
            host = NSHostingView(rootView: AnyView(FocusView(document: ws.document).environmentObject(ws).environmentObject(Preferences.shared).frame(width: size.width, height: size.height)))
        } else {
            host = NSHostingView(rootView: AnyView(RootView().environmentObject(ws).environmentObject(Preferences.shared).frame(width: size.width, height: size.height)))
        }
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.contentView = host
        win.titlebarAppearsTransparent = true
        host.frame = NSRect(origin: .zero, size: size)
        for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.15)) }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no rep") }
        host.cacheDisplay(in: host.bounds, to: rep)
        let out = fm.temporaryDirectory.appendingPathComponent("\(name).png")
        try rep.representation(using: .png, properties: [:])?.write(to: out)
        print("SNAPSHOT \(out.path)")
        try? fm.removeItem(at: dir)
    }

    func testWriteLight() throws { try render(dark: false, mode: .write, name: "write-light") }
    func testWriteDark() throws { try render(dark: true, mode: .write, name: "write-dark") }
    func testOutlineLight() throws { try render(dark: false, mode: .write, name: "outline-light", outline: true) }
    func testFindPanelLight() throws { try render(dark: false, mode: .write, name: "find-light", panel: .find) }
    func testReviewPanelLight() throws {
        // two suggestions, one to look at in build/snapshots (the tab's real assertions are in ReviewPanelTests)
        try render(dark: false, mode: .write, name: "review-light", panel: .review)
    }
    func testFocusLight() throws { try render(dark: false, mode: .write, name: "focus-light", focus: true, size: NSSize(width: 1440, height: 900)) }

    func testSettings() throws {
        let host = NSHostingView(rootView: SettingsView().environmentObject(Preferences.shared))
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = host
        for _ in 0..<4 { host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no rep") }
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("settings.png"))
    }

    func testViewLight() throws { try render(dark: false, mode: .view, name: "view-light") }
}
