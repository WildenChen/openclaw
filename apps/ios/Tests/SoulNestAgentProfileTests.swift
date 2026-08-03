import Foundation
import XCTest
@testable import OpenClaw

@MainActor
final class SoulNestAgentProfileTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        self.suiteName = "SoulNestAgentProfileTests.\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: self.suiteName)
        self.defaults.removePersistentDomain(forName: self.suiteName)
    }

    override func tearDown() {
        self.defaults.removePersistentDomain(forName: self.suiteName)
        self.defaults = nil
        self.suiteName = nil
        super.tearDown()
    }

    func testFirstReleaseExposesOnlyBuiltInYujie() {
        XCTAssertEqual(SoulNestAgentProfile.builtInProfiles, [.yujie])
        XCTAssertEqual(SoulNestAgentProfile.yujie.id, "yujie")
        XCTAssertEqual(SoulNestAgentProfile.yujie.openClawAgentID, "yujie")
        XCTAssertEqual(SoulNestAgentProfile.yujie.displayName, "語婕")
        XCTAssertEqual(SoulNestAgentProfile.yujie.sessionNamespace, "soulnest.yujie")
    }

    func testMissingProfileStartsWithAndPersistsBuiltInYujie() throws {
        let store = SoulNestAgentProfileStore(defaults: self.defaults)

        XCTAssertEqual(store.current, .yujie)
        let data = try XCTUnwrap(self.defaults.data(forKey: SoulNestAgentProfileStore.storageKey))
        XCTAssertEqual(try JSONDecoder().decode(SoulNestAgentProfile.self, from: data), .yujie)
    }

    func testNonSensitiveUIPreferencesRoundTripAcrossLaunches() {
        let store = SoulNestAgentProfileStore(defaults: self.defaults)
        var edited = store.current
        edited.uiPreferences.showsSecretaryDrawer = false
        edited.uiPreferences.preferredCharacterState = "thinking"
        store.save(edited)

        let relaunched = SoulNestAgentProfileStore(defaults: self.defaults)
        XCTAssertEqual(relaunched.current, edited)
    }

    func testCorruptedProfileFallsBackAndRepairsStoredValue() throws {
        self.defaults.set(Data("not-json".utf8), forKey: SoulNestAgentProfileStore.storageKey)

        let store = SoulNestAgentProfileStore(defaults: self.defaults)

        XCTAssertEqual(store.current, .yujie)
        let repaired = try XCTUnwrap(self.defaults.data(forKey: SoulNestAgentProfileStore.storageKey))
        XCTAssertEqual(try JSONDecoder().decode(SoulNestAgentProfile.self, from: repaired), .yujie)
    }

    func testUnknownAgentCannotReplaceYujieInFirstRelease() {
        let store = SoulNestAgentProfileStore(defaults: self.defaults)
        let unsupported = SoulNestAgentProfile(
            id: "other",
            openClawAgentID: "other",
            displayName: "Other",
            characterAssetPackID: "other.default",
            sessionNamespace: "soulnest.other",
            capabilities: [.textChat],
            uiPreferences: .yujieDefault)

        store.save(unsupported)

        XCTAssertEqual(store.current, .yujie)
    }

    func testEncodedProfileContainsNoCredentialOrMemoryFields() throws {
        let data = try JSONEncoder().encode(SoulNestAgentProfile.yujie)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.localizedCaseInsensitiveContains("apiKey"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("soul"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("memory"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("provider"))
    }
}
