import Foundation
import XCTest
@testable import OpenClaw

@MainActor
final class SoulNestConversationSessionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        self.suiteName = "SoulNestConversationSessionStoreTests.\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: self.suiteName)
        self.defaults.removePersistentDomain(forName: self.suiteName)
    }

    override func tearDown() {
        self.defaults.removePersistentDomain(forName: self.suiteName)
        self.defaults = nil
        self.suiteName = nil
        super.tearDown()
    }

    func testSameConversationReusesSameOpenClawSession() {
        let store = SoulNestConversationSessionStore(defaults: self.defaults)
        let conversationID = UUID()

        let first = store.session(for: conversationID)
        let second = store.session(for: conversationID)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.openClawAgentID, "yujie")
        XCTAssertEqual(SessionKey.agentId(from: first.sessionKey), "yujie")
        XCTAssertTrue(first.sessionKey.hasPrefix("agent:yujie:soulnest-ios-"))
    }

    func testDifferentConversationsUseDifferentSessionKeys() {
        let store = SoulNestConversationSessionStore(defaults: self.defaults)

        let first = store.session(for: UUID())
        let second = store.session(for: UUID())

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.sessionKey, second.sessionKey)
    }

    func testMappingsRestoreAcrossLaunches() {
        let conversationID = UUID()
        let firstStore = SoulNestConversationSessionStore(defaults: self.defaults)
        let original = firstStore.session(for: conversationID)

        let relaunchedStore = SoulNestConversationSessionStore(defaults: self.defaults)

        XCTAssertEqual(relaunchedStore.session(for: conversationID), original)
        XCTAssertEqual(relaunchedStore.allSessions, [original])
    }

    func testReplacingExpiredSessionKeepsConversationAndChangesRemoteKey() {
        let conversationID = UUID()
        let store = SoulNestConversationSessionStore(defaults: self.defaults)
        let original = store.session(for: conversationID)

        let replacement = store.replaceSession(for: conversationID)

        XCTAssertEqual(replacement.id, conversationID)
        XCTAssertEqual(replacement.createdAt, original.createdAt)
        XCTAssertNotEqual(replacement.generation, original.generation)
        XCTAssertNotEqual(replacement.sessionKey, original.sessionKey)
        XCTAssertEqual(store.session(for: conversationID), replacement)
    }

    func testMappingForAnotherProfileIsRejectedAndRebuiltOnLoad() throws {
        let conversationID = UUID()
        let otherProfile = SoulNestConversationSession(
            id: conversationID,
            profileID: "someone-else",
            openClawAgentID: "someone-else",
            generation: UUID(),
            sessionKey: "agent:someone-else:soulnest-ios-abc",
            createdAt: Date(),
            updatedAt: Date())
        self.defaults.set(
            try JSONEncoder().encode([otherProfile]),
            forKey: SoulNestConversationSessionStore.storageKey)

        let store = SoulNestConversationSessionStore(defaults: self.defaults)
        let rebuilt = store.session(for: conversationID)

        XCTAssertNotEqual(rebuilt.sessionKey, otherProfile.sessionKey)
        XCTAssertEqual(rebuilt.profileID, SoulNestAgentProfile.yujie.id)
        XCTAssertEqual(rebuilt.openClawAgentID, SoulNestAgentProfile.yujie.openClawAgentID)
        XCTAssertTrue(rebuilt.sessionKey.hasPrefix("agent:yujie:soulnest-ios-"))
    }

    func testTelegramOrMainSessionIsNotAcceptedAsIOSConversationMapping() throws {
        let conversationID = UUID()
        let invalid = SoulNestConversationSession(
            id: conversationID,
            profileID: SoulNestAgentProfile.yujie.id,
            openClawAgentID: SoulNestAgentProfile.yujie.openClawAgentID,
            generation: UUID(),
            sessionKey: "agent:yujie:main",
            createdAt: Date(),
            updatedAt: Date())
        self.defaults.set(
            try JSONEncoder().encode([invalid]),
            forKey: SoulNestConversationSessionStore.storageKey)

        let store = SoulNestConversationSessionStore(defaults: self.defaults)
        let repaired = store.session(for: conversationID)

        XCTAssertNotEqual(repaired.sessionKey, invalid.sessionKey)
        XCTAssertTrue(repaired.sessionKey.hasPrefix("agent:yujie:soulnest-ios-"))
    }

    func testCorruptedPersistenceStartsWithAnEmptyRebuildableIndex() {
        self.defaults.set(
            Data("not-json".utf8),
            forKey: SoulNestConversationSessionStore.storageKey)

        let store = SoulNestConversationSessionStore(defaults: self.defaults)

        XCTAssertTrue(store.allSessions.isEmpty)
        XCTAssertFalse(store.session(for: UUID()).sessionKey.isEmpty)
    }

    func testRemovingMappingsDoesNotRequireOrReplayTranscriptData() throws {
        let store = SoulNestConversationSessionStore(defaults: self.defaults)
        let conversationID = UUID()
        _ = store.session(for: conversationID)

        let data = try XCTUnwrap(
            self.defaults.data(forKey: SoulNestConversationSessionStore.storageKey))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("message"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("transcript"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("history"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("token"))

        store.removeSession(for: conversationID)
        XCTAssertTrue(store.allSessions.isEmpty)

        _ = store.session(for: UUID())
        store.removeAllSessions()
        XCTAssertNil(self.defaults.data(forKey: SoulNestConversationSessionStore.storageKey))
    }
}
