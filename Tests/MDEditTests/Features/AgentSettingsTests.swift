import XCTest
@testable import MDEdit

/// The settings behind agent access: off by default, a port that stays in range, and a token that is random and never weak.
final class AgentSettingsTests: XCTestCase {

    func testAgentAccessIsOffWithTheDefaultPortAndAFreshToken() {
        let p = Preferences(defaults: isolatedDefaults())
        XCTAssertFalse(p.agentsEnabled)
        XCTAssertEqual(p.agentPort, Preferences.defaultAgentPort)
        XCTAssertEqual(p.agentToken.count, 64)
        XCTAssertTrue(p.agentToken.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    func testSettingsAndTokenSurviveARestart() {
        let d = isolatedDefaults()
        let a = Preferences(defaults: d)
        a.agentsEnabled = true; a.agentPort = 50_000
        let token = a.agentToken
        let b = Preferences(defaults: d)
        XCTAssertTrue(b.agentsEnabled)
        XCTAssertEqual(b.agentPort, 50_000)
        XCTAssertEqual(b.agentToken, token, "the client's configuration must keep working after a restart")
    }

    func testRegeneratingTheTokenChangesItAndKeepsTheNewOne() {
        let d = isolatedDefaults()
        let a = Preferences(defaults: d)
        let old = a.agentToken
        a.regenerateAgentToken()
        XCTAssertNotEqual(a.agentToken, old)
        XCTAssertEqual(Preferences(defaults: d).agentToken, a.agentToken)
    }

    func testAPortOutsideTheUnprivilegedRangeIsClamped() {
        let d = isolatedDefaults()
        d.set(80, forKey: "agentPort")
        XCTAssertEqual(Preferences(defaults: d).agentPort, 1024)
        d.set(99_999, forKey: "agentPort")
        XCTAssertEqual(Preferences(defaults: d).agentPort, 65_535)
        d.set("not a number", forKey: "agentPort")
        XCTAssertEqual(Preferences(defaults: d).agentPort, Preferences.defaultAgentPort)
    }

    func testAWeakOrTamperedStoredTokenIsReplaced() {
        for bad in ["", "abc", "password", String(repeating: "A", count: 64), String(repeating: "g", count: 64), String(repeating: "a", count: 63)] {
            let d = isolatedDefaults()
            d.set(bad, forKey: "agentToken")
            let p = Preferences(defaults: d)
            XCTAssertNotEqual(p.agentToken, bad, "“\(bad)” must not be accepted as a token")
            XCTAssertEqual(p.agentToken.count, 64)
            XCTAssertEqual(d.string(forKey: "agentToken"), p.agentToken, "the replacement is stored, so it stays the same next time")
        }
    }

    func testTokensDoNotRepeat() {
        let tokens = Set((0..<200).map { _ in Preferences.makeAgentToken() })
        XCTAssertEqual(tokens.count, 200)
    }
}
