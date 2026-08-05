import Foundation
import Testing
@testable import OpenClaw

struct SoulNestConversationCachePersistenceTests {
    private func temporaryStore() -> SoulNestConversationCacheDiskStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return SoulNestConversationCacheDiskStore(
            fileURL: directory.appendingPathComponent("cache.json"))
    }

    @Test func `protected snapshot round trips metadata only`() throws {
        let store = temporaryStore()
        defer { try? store.clear() }

        let conversationID = UUID()
        let messageID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = SoulNestConversationCacheSnapshot(
            conversations: [SoulNestConversationMetadata(
                id: conversationID,
                agentID: "yujie",
                sessionKey: "agent:yujie:soulnest-ios-test",
                title: "Conversation",
                createdAt: now,
                updatedAt: now)],
            messages: [SoulNestMessageMetadata(
                id: messageID,
                conversationID: conversationID,
                role: .assistant,
                createdAt: now,
                position: 0,
                sizeHint: 42)],
            attachments: [SoulNestAttachmentReference(
                conversationID: conversationID,
                messageID: messageID,
                kind: .image,
                byteSize: 128)],
            savedAt: now)

        try store.save(snapshot)

        #expect(store.load() == .loaded(snapshot))
        #expect(snapshot.isAuthoritative == false)
    }

    @Test func `corrupt snapshot requests rebuild`() throws {
        let store = temporaryStore()
        defer { try? store.clear() }
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: store.fileURL)

        #expect(store.load() == .corrupt)
    }

    @Test func `search excludes archived conversations by default`() {
        let now = Date()
        let active = SoulNestConversationMetadata(
            agentID: "yujie",
            sessionKey: "active",
            title: "Trip planning",
            state: .active,
            createdAt: now,
            updatedAt: now)
        let archived = SoulNestConversationMetadata(
            agentID: "yujie",
            sessionKey: "archived",
            title: "Trip archive",
            state: .archived,
            createdAt: now,
            updatedAt: now)

        let results = SoulNestConversationSearchIndex().search(
            "trip",
            in: [archived, active])

        #expect(results.map(\.id) == [active.id])
    }

    @Test func `reconciliation fetches remote metadata without transcript replay`() {
        let conversationID = UUID()
        let now = Date()
        let local = SoulNestConversationMetadata(
            id: conversationID,
            agentID: "yujie",
            sessionKey: "old-session",
            title: "Chat",
            createdAt: now,
            updatedAt: now)
        let localMessage = SoulNestMessageMetadata(
            conversationID: conversationID,
            role: .user,
            createdAt: now,
            position: 3,
            sizeHint: 10)
        let remote = SoulNestGatewayConversationDigest(
            conversationID: conversationID,
            sessionKey: "new-session",
            latestPosition: 8,
            updatedAt: now)

        let actions = SoulNestConversationReconciler().reconcile(
            localConversations: [local],
            localMessages: [localMessage],
            gateway: [remote])

        #expect(actions.contains(.replaceSessionKey(
            conversationID: conversationID,
            sessionKey: "new-session")))
        #expect(actions.contains(.fetchMetadata(
            conversationID: conversationID,
            afterPosition: 3)))
    }
}
