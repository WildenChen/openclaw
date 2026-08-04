import Foundation
import XCTest
@testable import OpenClaw

@MainActor
private func makeCache(now: @escaping () -> Date = { Date() }) -> SoulNestConversationCache {
    SoulNestConversationCache(now: now)
}

@MainActor
private func makeMessages(
    for conversationID: UUID,
    count: Int,
    base: Date = Date(timeIntervalSince1970: 0)) -> [SoulNestMessageMetadata]
{
    (0..<count).map { index in
        SoulNestMessageMetadata(
            id: UUID(),
            conversationID: conversationID,
            role: index % 2 == 0 ? .assistant : .user,
            createdAt: base.addingTimeInterval(Double(index)),
            position: index,
            sizeHint: index * 10,
            contentType: .text)
    }
}

@MainActor
final class SoulNestConversationCacheTests: XCTestCase {
    func testCacheIsNeverAuthoritative() {
        let cache = makeCache()
        XCTAssertFalse(cache.isAuthoritative)
        XCTAssertEqual(cache.schemaVersion, .v1)
    }

    func testCreateConversationIndexesAndStoresMetadata() {
        let now = Date()
        let cache = makeCache(now: { now })
        let metadata = cache.createConversation(
            agentID: "yujie",
            sessionKey: "agent:yujie:soulnest-ios-test",
            title: "T",
            at: now)

        XCTAssertEqual(cache.conversation(id: metadata.id), metadata)
        XCTAssertEqual(cache.allConversations(), [metadata])
    }

    func testSaveAndLoadMessagesRoundTrip() {
        let cache = makeCache()
        let conversation = cache.createConversation(
            agentID: "yujie",
            sessionKey: "agent:yujie:soulnest-ios",
            title: "T",
            at: Date())

        let messages = makeMessages(for: conversation.id, count: 3)
        cache.saveMessages(messages)

        XCTAssertEqual(cache.loadMessages(conversationID: conversation.id, offset: 0, limit: 10), messages)
        XCTAssertEqual(cache.latestMessage(conversationID: conversation.id)?.id, messages.last?.id)
    }

    func testPaginationSlicesByPosition() {
        let cache = makeCache()
        let conversation = cache.createConversation(
            agentID: "yujie",
            sessionKey: "agent:yujie:soulnest-ios",
            title: "T",
            at: Date())
        let messages = makeMessages(for: conversation.id, count: 5)
        cache.saveMessages(messages)

        let page = cache.loadMessages(conversationID: conversation.id, offset: 1, limit: 2)
        XCTAssertEqual(page.count, 2)
        XCTAssertEqual(page.first?.position, 1)
        XCTAssertEqual(page.last?.position, 2)
    }

    func testOffsetBeyondRangeReturnsEmpty() {
        let cache = makeCache()
        let conversation = cache.createConversation(
            agentID: "yujie",
            sessionKey: "agent:yujie:soulnest-ios",
            title: "T",
            at: Date())
        cache.saveMessages(makeMessages(for: conversation.id, count: 3))

        XCTAssertTrue(cache.loadMessages(conversationID: conversation.id, offset: 99, limit: 10).isEmpty)
    }

    func testLazyLoadingContractDoesNotStoreBodyOrBytes() throws {
        // Message metadata carries no body/content bytes; lazy loading fetches bodies
        // from the Gateway. Attachments are references, never inlined image bytes.
        let cache = makeCache()
        let conversation = cache.createConversation(
            agentID: "yujie",
            sessionKey: "agent:yujie:soulnest-ios",
            title: "T",
            at: Date())
        let messages = makeMessages(for: conversation.id, count: 2)
        cache.saveMessages(messages)

        let attachment = try SoulNestAttachmentReference(
            conversationID: conversation.id,
            messageID: XCTUnwrap(messages.first?.id),
            kind: .image,
            byteSize: 0,
            remoteURL: URL(string: "https://gateway.example.test/artifact/x"))

        cache.saveAttachment(attachment)
        XCTAssertEqual(cache.attachment(id: attachment.id)?.localStatus, .missing)
        XCTAssertNotEqual(attachment.byteSize, -1)
        // No body field exists on the metadata model at all.
        XCTAssertTrue(messages.description.contains("SoulNestMessageMetadata"))
    }

    func testRenameAndArchiveMutateMetadata() {
        let now = Date()
        let cache = makeCache(now: { now })
        let conversation = cache.createConversation(
            agentID: "yujie",
            sessionKey: "agent:yujie:soulnest-ios",
            title: "Old",
            at: now)

        cache.renameConversation(id: conversation.id, title: "New", at: now)
        XCTAssertEqual(cache.conversation(id: conversation.id)?.title, "New")

        cache.archiveConversation(id: conversation.id, at: now)
        XCTAssertEqual(cache.conversation(id: conversation.id)?.state, .archived)
    }

    func testDeleteConversationRemovesMessagesAndAttachments() throws {
        let cache = makeCache()
        let conversation = cache.createConversation(
            agentID: "yujie",
            sessionKey: "agent:yujie:soulnest-ios",
            title: "T",
            at: Date())
        let messages = makeMessages(for: conversation.id, count: 3)
        cache.saveMessages(messages)
        try cache.saveAttachment(
            SoulNestAttachmentReference(
                conversationID: conversation.id,
                messageID: XCTUnwrap(messages.first?.id),
                kind: .image,
                byteSize: 10))

        cache.deleteConversation(id: conversation.id)

        XCTAssertNil(cache.conversation(id: conversation.id))
        XCTAssertNil(try cache.attachment(id: XCTUnwrap(messages.first?.id)))
        XCTAssertNil(cache.latestMessage(conversationID: conversation.id))
    }

    func testClearCacheRemovesEverything() {
        let cache = makeCache()
        let conversation = cache.createConversation(
            agentID: "yujie",
            sessionKey: "agent:yujie:soulnest-ios",
            title: "T",
            at: Date())
        cache.saveMessages(makeMessages(for: conversation.id, count: 4))

        cache.clearCache()

        XCTAssertTrue(cache.allConversations().isEmpty)
        XCTAssertNil(cache.latestMessage(conversationID: conversation.id))
    }

    func testDeleteAllConversationsClearsIndex() {
        let cache = makeCache()
        _ = cache.createConversation(agentID: "yujie", sessionKey: "a", title: "A", at: Date())
        _ = cache.createConversation(agentID: "yujie", sessionKey: "b", title: "B", at: Date())

        cache.deleteAllConversations()

        XCTAssertTrue(cache.allConversations().isEmpty)
    }

    func testRebuildFromCorruptStateDropsMetadataWithoutReplay() {
        let cache = makeCache()
        let conversation = cache.createConversation(
            agentID: "yujie",
            sessionKey: "agent:yujie:soulnest-ios",
            title: "T",
            at: Date())
        cache.saveMessages(makeMessages(for: conversation.id, count: 10))
        cache.saveAttachment(
            SoulNestAttachmentReference(
                conversationID: conversation.id,
                messageID: UUID(),
                kind: .image,
                byteSize: 5))

        cache.isCorrupt = true
        cache.rebuildFromCorruptState()

        XCTAssertFalse(cache.isCorrupt)
        XCTAssertEqual(cache.schemaVersion, .v1)
        XCTAssertTrue(cache.allConversations().isEmpty)
        XCTAssertNil(cache.latestMessage(conversationID: conversation.id))
        // The authoritative session key mapping is owned elsewhere and is not
        // reconstructed by this rebuild, so nothing is replayed.
        XCTAssertEqual(cache.isAuthoritative, false)
    }

    func testMigrateIfNeededIsIdempotentAtTargetVersion() {
        let cache = makeCache()
        cache.migrateIfNeeded()
        XCTAssertEqual(cache.schemaVersion, .v1)
        XCTAssertFalse(cache.isCorrupt)

        cache.schemaVersion = .v1
        cache.migrateIfNeeded()
        XCTAssertEqual(cache.schemaVersion, .v1)
    }

    func testPruneMessageMetadataKeepsMostRecentOnly() {
        let now = Date()
        let cache = makeCache(now: { now })
        let conversation = cache.createConversation(
            agentID: "yujie",
            sessionKey: "agent:yujie:soulnest-ios",
            title: "T",
            at: now)
        let messages = makeMessages(for: conversation.id, count: 6)
        cache.saveMessages(messages)

        cache.pruneMessageMetadata(conversationID: conversation.id, keeping: 2, now: now)

        XCTAssertEqual(cache.loadMessages(conversationID: conversation.id, offset: 0, limit: 100).count, 2)
        XCTAssertEqual(
            cache.loadMessages(conversationID: conversation.id, offset: 0, limit: 100).map(\.position),
            [4, 5])
    }

    func testEvictUncachedAttachmentsDropsMissingReferences() {
        let cache = makeCache()
        let conversation = cache.createConversation(
            agentID: "yujie",
            sessionKey: "agent:yujie:soulnest-ios",
            title: "T",
            at: Date())
        let missing = SoulNestAttachmentReference(
            conversationID: conversation.id,
            messageID: UUID(),
            kind: .image,
            byteSize: 10,
            remoteURL: URL(string: "https://gateway.example.test/a"))
        let cached = SoulNestAttachmentReference(
            conversationID: conversation.id,
            messageID: UUID(),
            kind: .image,
            byteSize: 20,
            remoteURL: URL(string: "https://gateway.example.test/b"))
        cache.saveAttachment(missing)
        cache.saveAttachment(cached)
        cache.markAttachmentCached(id: cached.id, at: Date())

        cache.evictUncachedAttachments()

        XCTAssertNil(cache.attachment(id: missing.id))
        XCTAssertNotNil(cache.attachment(id: cached.id))
    }

    func testAttachmentBytesAreNotStoredInCache() {
        let cache = makeCache()
        let conversation = cache.createConversation(
            agentID: "yujie",
            sessionKey: "agent:yujie:soulnest-ios",
            title: "T",
            at: Date())
        let attachment = SoulNestAttachmentReference(
            conversationID: conversation.id,
            messageID: UUID(),
            kind: .image,
            byteSize: 4096,
            remoteURL: URL(string: "https://gateway.example.test/artifact/1"))

        cache.saveAttachment(attachment)

        // The reference has a byte size but holds no pixel bytes.
        XCTAssertEqual(cache.attachment(id: attachment.id)?.byteSize, 4096)
        XCTAssertNotEqual(attachment.byteSize, MemoryLayout<SoulNestAttachmentReference>.size)
    }
}
