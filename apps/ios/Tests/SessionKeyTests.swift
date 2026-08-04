import Foundation
import XCTest
@testable import OpenClaw

final class SessionKeyTests: XCTestCase {
    func testNormalizeMainKeyDefaultsToMainForMissingOrBlank() {
        XCTAssertEqual(SessionKey.normalizeMainKey(nil), "main")
        XCTAssertEqual(SessionKey.normalizeMainKey(""), "main")
        XCTAssertEqual(SessionKey.normalizeMainKey("   "), "main")
    }

    func testNormalizeMainKeyTrimsAndKeepsNonBlankValues() {
        XCTAssertEqual(SessionKey.normalizeMainKey("  agent:yujie:abc  "), "agent:yujie:abc")
    }

    func testMakeAgentSessionKeyEmbedsAgentAndBaseKey() {
        let key = SessionKey.makeAgentSessionKey(agentId: "yujie", baseKey: "soulnest-ios-abc")
        XCTAssertEqual(key, "agent:yujie:soulnest-ios-abc")
    }

    func testMakeAgentSessionKeyTrimsWhitespace() {
        let key = SessionKey.makeAgentSessionKey(agentId: "  yujie  ", baseKey: "  soulnest-ios-abc  ")
        XCTAssertEqual(key, "agent:yujie:soulnest-ios-abc")
    }

    func testMakeAgentSessionKeyFallsBackToMainWhenEmpty() {
        XCTAssertEqual(SessionKey.makeAgentSessionKey(agentId: "", baseKey: ""), "main")
        XCTAssertEqual(SessionKey.makeAgentSessionKey(agentId: "yujie", baseKey: ""), "agent:yujie:main")
        XCTAssertEqual(SessionKey.makeAgentSessionKey(agentId: "", baseKey: "soulnest-ios-abc"), "soulnest-ios-abc")
    }

    func testAgentIdExtractsFromValidAgentKey() {
        XCTAssertEqual(SessionKey.agentId(from: "agent:yujie:soulnest-ios-abc"), "yujie")
        XCTAssertEqual(SessionKey.agentId(from: "  agent:yujie:main  "), "yujie")
    }

    func testAgentIdRejectsMainAndMalformedKeys() {
        XCTAssertNil(SessionKey.agentId(from: nil))
        XCTAssertNil(SessionKey.agentId(from: "main"))
        XCTAssertNil(SessionKey.agentId(from: "agent:yujie"))
        XCTAssertNil(SessionKey.agentId(from: "agent:"))
        XCTAssertNil(SessionKey.agentId(from: "telegram:yujie:main"))
        XCTAssertNil(SessionKey.agentId(from: "other:yujie:main"))
    }

    func testAgentScopedKeysRemainIsolatedAcrossBases() {
        let first = SessionKey.makeAgentSessionKey(agentId: "yujie", baseKey: "soulnest-ios-1")
        let second = SessionKey.makeAgentSessionKey(agentId: "yujie", baseKey: "soulnest-ios-2")
        let telegram = SessionKey.makeAgentSessionKey(agentId: "yujie", baseKey: "main")

        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first, telegram)
        XCTAssertEqual(SessionKey.agentId(from: first), SessionKey.agentId(from: second))
        XCTAssertEqual(SessionKey.agentId(from: first), SessionKey.agentId(from: telegram))
    }
}
