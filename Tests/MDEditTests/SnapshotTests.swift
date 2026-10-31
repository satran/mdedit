import XCTest
import SwiftUI
@testable import MDEdit

/// Renders the window offscreen to PNGs in the test's temp folder (see the paths it prints), so the look can be checked without a screen.
final class SnapshotTests: XCTestCase {
    static let sample = """
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
    """

    func render(dark: Bool, mode: Mode, name: String) throws {
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

        let root = RootView().environmentObject(ws).environmentObject(Preferences.shared).frame(width: 1280, height: 820)
        let host = NSHostingView(rootView: root)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.contentView = host
        win.titlebarAppearsTransparent = true
        host.frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
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
    func testViewLight() throws { try render(dark: false, mode: .view, name: "view-light") }
}
