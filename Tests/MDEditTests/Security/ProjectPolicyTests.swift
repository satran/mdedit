import XCTest
import Security
@testable import MDEdit

/// The app's own privileges, checked on the running (test-hosted) app: it must stay sandboxed with no more access than it needs.
final class ProjectPolicyTests: XCTestCase {
    private func entitlement(_ name: String) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, name as CFString, nil)
    }

    func testTheAppIsSandboxed() {
        XCTAssertEqual(entitlement("com.apple.security.app-sandbox") as? Bool, true)
    }

    func testItHasOnlyTheAccessItNeeds() {
        XCTAssertEqual(entitlement("com.apple.security.files.user-selected.read-write") as? Bool, true)
        XCTAssertEqual(entitlement("com.apple.security.files.bookmarks.app-scope") as? Bool, true)
        // The one network privilege beyond the client: agent access (plan 005) listens on the loopback address only.
        // `scripts/audit.sh` checks that only Agents/MCPServer.swift opens a listener and that it binds to loopback.
        XCTAssertEqual(entitlement("com.apple.security.network.server") as? Bool, true)
        // printing: without it the sandbox answers the print panel with "This application does not support printing"
        XCTAssertEqual(entitlement("com.apple.security.print") as? Bool, true)
        let forbidden = [
            "com.apple.security.files.all", "com.apple.security.files.user-selected.executable",
            "com.apple.security.files.downloads.read-write", "com.apple.security.assets.pictures.read-write", "com.apple.security.assets.music.read-write",
            "com.apple.security.assets.movies.read-write", "com.apple.security.device.camera", "com.apple.security.device.microphone",
            "com.apple.security.device.usb", "com.apple.security.device.bluetooth", "com.apple.security.personal-information.addressbook",
            "com.apple.security.personal-information.calendars", "com.apple.security.personal-information.location",
            "com.apple.security.automation.apple-events", "com.apple.security.cs.allow-unsigned-executable-memory",
            "com.apple.security.cs.disable-library-validation", "com.apple.security.cs.allow-jit",
            "com.apple.security.temporary-exception.files.absolute-path.read-write", "com.apple.security.temporary-exception.files.home-relative-path.read-write",
            "com.apple.security.temporary-exception.apple-events",
        ]
        for e in forbidden { XCTAssertNil(entitlement(e), "unexpected entitlement \(e)") }
    }

    // Xcode adds a few test-only exceptions to the Debug test host, so the exact entitlement set of the shipped app is checked by
    // `make audit` against build/MDEdit.app (the Release build), not here.

    func testInfoPlistDoesNotLoosenSecurity() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertNil(info["NSAppTransportSecurity"], "no exceptions to transport security")
        XCTAssertNil(info["CFBundleURLTypes"], "no URL scheme that other apps or web pages could use to drive the app")
        XCTAssertNil(info["NSAppleScriptEnabled"])
        XCTAssertNil(info["OSAScriptingDefinition"])
        XCTAssertNil(info["NSServices"])
    }

    func testBundledFontsAreLicensed() {
        let fonts = Bundle.main.paths(forResourcesOfType: "ttf", inDirectory: nil)
        XCTAssertFalse(fonts.isEmpty)
        XCTAssertFalse(Bundle.main.paths(forResourcesOfType: "txt", inDirectory: nil).filter { $0.contains("OFL") }.isEmpty)
    }

    func testTheTestRunNeverUsesTheRealSettings() {
        XCTAssertTrue(AppEnvironment.isTesting)
        XCTAssertFalse(AppEnvironment.defaults === UserDefaults.standard)
    }
}
