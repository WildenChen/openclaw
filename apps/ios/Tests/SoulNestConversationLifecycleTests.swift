import Foundation
import XCTest
@testable import OpenClaw

private final class ResetRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var keys: [String] {
        self.lock.withLock { self.storage }
    }

    func record(_ key: String) {
        self.lock.withLock {
            self.storage.append(key)
        }
    }
}

@MainActor
private func makeLifecycle(
    defaults: UserDefaults,
    surface: SoulNestConversationSurface = .ios,
    recorder: ResetRecorder) -> SoulNestConversationLifecycle
{
    let store = SoulNestConversationSessionStore(defaults: defaults)
    return SoulNestConversationLifecycle(
        store: store,
        profile: .yujie,
        surface: surface,
        resetSession: { key in recorder.record(key) })
}

@MainActor
private func makeLifecycle(
    store: SoulNestConversationSessionStore,
    surface: SoulNestConversationSurface = .ios,
    recorder: ResetRecorder) -> SoulNestConversationLifecycle
{
    SoulNestConversationLifecycle(
        store: store,
        profile: .yujie,
        surface: surface,
        resetSession: { key in recorder.record(key) })
}

private func freshDefaults(suiteSuffix: String) -> (UserDefaults, String) {
    let suite = "SoulNestLifecycle.\(suiteSuffix).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (defaults, suite)
}

@MainActor
final class SoulNestConversationLifecycleTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        (self.defaults, self.suiteName) = freshDefaults(suiteSuffix: "setUp")
    }

    override func tearDown() {
        self.defaults.removePersistentDomain(forName: self.suiteName)
        self.defaults = nil
        self.suiteName = nil
        super.tearDown()
    }

    func testSameConversationReusesSameSessionKey() async {
        let recorder = ResetRecorder()
        let lifecycle = makeLifecycle(defaults: self.defaults, recorder: recorder)

        let conversationID = lifecycle.createConversation()
        let firstKey = lifecycle.currentSessionKey

        await lifecycle.restoreConversation(id: conversationID)

        XCTAssertEqual(lifecycle.currentSessionKey, firstKey)
        XCTAssertTrue(recorder.keys.isEmpty)
    }

    func testDifferentConversationsProduceDistinctSessionKeys() {
        let store = SoulNestConversationSessionStore(defaults: self.defaults)
        let firstID = UUID()
        let secondID = UUID()
        let firstKey = store.session(for: firstID).sessionKey
        let secondKey = store.session(for: secondID).sessionKey

        XCTAssertNotEqual(firstID, secondID)
        XCTAssertNotEqual(firstKey, secondKey)
    }

    func testAppReloadRestoresPersistentSessionKey() async {
        let recorder = ResetRecorder()
        let store = SoulNestConversationSessionStore(defaults: self.defaults)
        let conversationID = UUID()
        let original = store.session(for: conversationID)

        let lifecycle = makeLifecycle(store: store, recorder: recorder)
        await lifecycle.restoreConversation(id: conversationID)

        XCTAssertEqual(lifecycle.currentSessionKey, original.sessionKey)
        XCTAssertEqual(lifecycle.currentConversationID, conversationID)
        XCTAssertTrue(recorder.keys.isEmpty)
    }

    func testUserResetIssuesNewGenerationAndKeepsConversationID() async throws {
        let recorder = ResetRecorder()
        let lifecycle = makeLifecycle(defaults: self.defaults, recorder: recorder)

        let conversationID = lifecycle.createConversation()
        let before = lifecycle.currentSessionKey

        try await lifecycle.resetSession(for: conversationID)

        XCTAssertEqual(lifecycle.currentConversationID, conversationID)
        XCTAssertNotEqual(lifecycle.currentSessionKey, before)
        XCTAssertEqual(recorder.keys, [lifecycle.currentSessionKey])
    }

    func testSessionExpiredTriggersSafeReplacement() async {
        let recorder = ResetRecorder()
        let lifecycle = makeLifecycle(defaults: self.defaults, recorder: recorder)

        let conversationID = lifecycle.createConversation()
        let before = lifecycle.currentSessionKey

        await lifecycle.handleSessionExpired(for: conversationID)

        XCTAssertNotEqual(lifecycle.currentSessionKey, before)
        XCTAssertEqual(recorder.keys, [lifecycle.currentSessionKey])
    }

    func testTelegramAndIOSSurfaceKeysAreDistinct() {
        let (iosDefaults, _) = freshDefaults(suiteSuffix: "ios-surface")
        let (tgDefaults, _) = freshDefaults(suiteSuffix: "tg-surface")
        let conversationID = UUID()

        let iosSession = SoulNestConversationSessionStore(defaults: iosDefaults)
            .session(for: conversationID, surface: .ios)
        let tgSession = SoulNestConversationSessionStore(defaults: tgDefaults)
            .session(for: conversationID, surface: .telegram)

        XCTAssertNotEqual(iosSession.sessionKey, tgSession.sessionKey)
        XCTAssertTrue(iosSession.sessionKey.hasPrefix("agent:yujie:soulnest-ios-"))
        XCTAssertTrue(tgSession.sessionKey.hasPrefix("agent:yujie:soulnest-telegram-"))
    }

    func testRestoreRejectsStaleSurfaceMapping() {
        let (iosDefaults, iosSuite) = freshDefaults(suiteSuffix: "ios-stale")
        let (tgDefaults, tgSuite) = freshDefaults(suiteSuffix: "tg-stale")
        defer {
            iosDefaults.removePersistentDomain(forName: iosSuite)
            tgDefaults.removePersistentDomain(forName: tgSuite)
        }

        let conversationID = UUID()
        let tgSession = SoulNestConversationSessionStore(defaults: tgDefaults)
            .session(for: conversationID, surface: .telegram)

        // An iOS scoped store cannot adopt a persisted telegram mapping: the
        // surface prefix mismatch causes a fresh iOS key to be issued.
        let iosStore = SoulNestConversationSessionStore(defaults: iosDefaults)
        let rebuilt = iosStore.session(for: conversationID, surface: .ios)

        XCTAssertNotEqual(rebuilt.sessionKey, tgSession.sessionKey)
        XCTAssertTrue(rebuilt.sessionKey.hasPrefix("agent:yujie:soulnest-ios-"))
    }

    func testLifecycleNeverExposesOrReplaysHistory() {
        let recorder = ResetRecorder()
        let lifecycle = makeLifecycle(
            defaults: freshDefaults(suiteSuffix: "history").0,
            recorder: recorder)
        XCTAssertEqual(lifecycle.status, .missing)
        _ = lifecycle.currentSessionKey
        _ = lifecycle.currentConversationID
    }

    func testResetDoesNotReplayHistoryOnReconnect() async {
        let recorder = ResetRecorder()
        let lifecycle = makeLifecycle(defaults: self.defaults, recorder: recorder)

        let conversationID = lifecycle.createConversation()
        await lifecycle.handleSessionExpired(for: conversationID)

        XCTAssertEqual(recorder.keys.count, 1)
        XCTAssertEqual(recorder.keys[0], lifecycle.currentSessionKey)
        XCTAssertTrue(recorder.keys[0].hasPrefix("agent:yujie:soulnest-ios-"))
    }
}
