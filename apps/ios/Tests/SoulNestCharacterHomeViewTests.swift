import Foundation
import XCTest
@testable import OpenClaw

@MainActor
final class SoulNestCharacterHomeViewTests: XCTestCase {
    func testProfileStoreYieldsYujie() {
        let store = SoulNestAgentProfileStore()
        XCTAssertEqual(store.current.displayName, "語婕")
        XCTAssertEqual(store.current.characterAssetPackID, "yujie.default")
    }

    func testAssetCacheStartsEmpty() {
        let cache = SoulNestCharacterAssetCache(maxBytes: 50 * 1024 * 1024)
        XCTAssertEqual(cache.count, 0)
        XCTAssertFalse(cache.isOverCapacity)
    }

    func testAssetIndexAcceptsGeneralAccess() {
        let index = SoulNestCharacterAssetIndex(access: .general)
        XCTAssertTrue(index.isValid)
    }

    func testConversationSessionStoreCreatesSession() {
        let store = SoulNestConversationSessionStore()
        let session = store.session(
            for: UUID(),
            profile: .yujie)
        XCTAssertFalse(session.sessionKey.isEmpty)
        XCTAssertEqual(session.profileID, SoulNestAgentProfile.yujie.id)
    }
}