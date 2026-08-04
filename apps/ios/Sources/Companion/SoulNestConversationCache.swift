import Foundation

/// Protocol for the SoulNest local conversation cache.
///
/// The cache is explicitly **not authoritative**: `isAuthoritative` is always
/// false. The Gateway owns the transcript and message content; this layer only
/// indexes local metadata and caches it. Body bytes and large image data are
/// never stored here — attachments are references resolved on demand.
protocol SoulNestConversationCacheProtocol: AnyObject {
    @MainActor var schemaVersion: SoulNestSchemaVersion { get }
    @MainActor var isAuthoritative: Bool { get }
    @MainActor var isCorrupt: Bool { get }

    @MainActor func createConversation(
        agentID: String,
        sessionKey: String,
        title: String,
        at now: Date) -> SoulNestConversationMetadata

    @MainActor func conversation(id: UUID) -> SoulNestConversationMetadata?
    @MainActor func allConversations() -> [SoulNestConversationMetadata]
    @MainActor func renameConversation(id: UUID, title: String, at now: Date)
    @MainActor func archiveConversation(id: UUID, at now: Date)
    @MainActor func deleteConversation(id: UUID)
    @MainActor func deleteAllConversations()

    @MainActor func saveMessages(_ messages: [SoulNestMessageMetadata])
    @MainActor func loadMessages(
        conversationID: UUID,
        offset: Int,
        limit: Int) -> [SoulNestMessageMetadata]
    @MainActor func latestMessage(conversationID: UUID) -> SoulNestMessageMetadata?
    @MainActor func deleteMessages(conversationID: UUID)

    @MainActor func saveAttachment(_ attachment: SoulNestAttachmentReference)
    @MainActor func attachment(id: UUID) -> SoulNestAttachmentReference?
    @MainActor func markAttachmentCached(id: UUID, at now: Date)
    @MainActor func evictUncachedAttachments()

    @MainActor func pruneMessageMetadata(conversationID: UUID, keeping: Int, now: Date)
    @MainActor func clearCache()

    @MainActor func rebuildFromCorruptState()
    @MainActor func migrateIfNeeded()
}

/// In-memory cache backing. Replaces the local index on load/rebuild; the
/// session key mapping remains owned by `SoulNestConversationSessionStore`.
@MainActor
final class SoulNestConversationCache: SoulNestConversationCacheProtocol {
    let isAuthoritative: Bool = false
    var schemaVersion: SoulNestSchemaVersion = .v1
    var isCorrupt: Bool = false

    private let now: () -> Date
    private var conversations: [UUID: SoulNestConversationMetadata] = [:]
    private var messages: [UUID: [SoulNestMessageMetadata]] = [:]
    private var attachments: [UUID: SoulNestAttachmentReference] = [:]
    private var attachmentOrder: [UUID] = []

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: - Conversations

    func createConversation(
        agentID: String,
        sessionKey: String,
        title: String,
        at now: Date) -> SoulNestConversationMetadata
    {
        let metadata = SoulNestConversationMetadata(
            agentID: agentID,
            sessionKey: sessionKey,
            title: title,
            createdAt: now,
            updatedAt: now,
            syncState: .pendingAck)
        self.conversations[metadata.id] = metadata
        self.messages[metadata.id] = []
        return metadata
    }

    func conversation(id: UUID) -> SoulNestConversationMetadata? {
        self.conversations[id]
    }

    func allConversations() -> [SoulNestConversationMetadata] {
        self.conversations.values.sorted { $0.createdAt < $1.createdAt }
    }

    func renameConversation(id: UUID, title: String, at now: Date) {
        guard var existing = self.conversations[id] else { return }
        existing.title = title
        existing.updatedAt = now
        self.conversations[id] = existing
    }

    func archiveConversation(id: UUID, at now: Date) {
        guard var existing = self.conversations[id] else { return }
        existing.state = .archived
        existing.updatedAt = now
        self.conversations[id] = existing
    }

    func deleteConversation(id: UUID) {
        self.conversations.removeValue(forKey: id)
        self.messages.removeValue(forKey: id)
        self.attachments = self.attachments.filter { $0.value.conversationID != id }
        self.reindexAttachments()
    }

    func deleteAllConversations() {
        self.conversations.removeAll()
        self.messages.removeAll()
        self.attachments.removeAll()
        self.attachmentOrder.removeAll()
    }

    // MARK: - Messages

    /// Replaces local message metadata for a conversation without touching any
    /// body content. Local dirty flags are preserved via caller-provided state.
    func saveMessages(_ messages: [SoulNestMessageMetadata]) {
        guard let conversationID = messages.first?.conversationID else { return }
        self.messages[conversationID] = messages.sorted { $0.position < $1.position }
    }

    /// Paginated, lazy-loaded view of message metadata. Callers page forward and
    /// fetch message bodies from the Gateway authoritatively rather than storing
    /// them locally.
    func loadMessages(
        conversationID: UUID,
        offset: Int,
        limit: Int) -> [SoulNestMessageMetadata]
    {
        let all = self.messages[conversationID] ?? []
        let start = max(0, offset)
        let end = min(all.endIndex, start + max(0, limit))
        guard start < all.endIndex else { return [] }
        return Array(all[start..<end])
    }

    func latestMessage(conversationID: UUID) -> SoulNestMessageMetadata? {
        self.messages[conversationID]?.max { $0.position < $1.position }
    }

    func deleteMessages(conversationID: UUID) {
        self.messages[conversationID]?.removeAll()
    }

    // MARK: - Attachments

    func saveAttachment(_ attachment: SoulNestAttachmentReference) {
        let isNew = self.attachments[attachment.id] == nil
        self.attachments[attachment.id] = attachment
        if isNew { self.attachmentOrder.append(attachment.id) }
    }

    func attachment(id: UUID) -> SoulNestAttachmentReference? {
        self.attachments[id]
    }

    func markAttachmentCached(id: UUID, at now: Date) {
        guard var existing = self.attachments[id] else { return }
        existing.localStatus = .cached
        existing.cachedAt = now
        self.attachments[id] = existing
    }

    /// Drops reference metadata for attachments that never made it to the device.
    func evictUncachedAttachments() {
        self.attachments = self.attachments.filter { $0.value.localStatus == .cached }
        self.reindexAttachments()
    }

    // MARK: - Eviction / reset

    /// Keeps only the most recent `keeping` message metadata entries per
    /// conversation; older entries are dropped locally and can be repaginated
    /// from the Gateway without replaying stored transcript bytes.
    func pruneMessageMetadata(conversationID: UUID, keeping: Int, now: Date) {
        guard let all = self.messages[conversationID],
              all.count > keeping
        else { return }
        let sorted = all.sorted { $0.position < $1.position }
        let dropped = sorted.dropLast(keeping)
        let kept = Array(sorted.suffix(keeping))
        for message in dropped {
            self.attachments = self.attachments.filter { $0.value.messageID != message.id }
        }
        self.messages[conversationID] = kept
        self.reindexAttachments()
        self.touchConversation(conversationID, at: now)
    }

    func clearCache() {
        self.conversations.removeAll()
        self.messages.removeAll()
        self.attachments.removeAll()
        self.attachmentOrder.removeAll()
    }

    // MARK: - Schema / corruption / migration

    /// Rebuilds the local index after a corrupt store is detected. Drops every
    /// local metadata record; the authoritative session key mapping lives in
    /// `SoulNestConversationSessionStore` and is rebuilt separately by the
    /// lifecycle layer. This deliberately never reconstructs transcript bytes.
    func rebuildFromCorruptState() {
        self.isCorrupt = false
        self.schemaVersion = Self.migrationTarget
        self.deleteAllConversations()
    }

    func migrateIfNeeded() {
        guard self.schemaVersion != Self.migrationTarget else { return }
        self.schemaVersion = SoulNestConversationCacheMigration.migrate(
            store: self,
            from: self.schemaVersion,
            to: Self.migrationTarget)
        self.isCorrupt = false
    }

    static let migrationTarget: SoulNestSchemaVersion = .v1

    // MARK: - Private

    private func touchConversation(_ id: UUID, at now: Date) {
        guard var existing = self.conversations[id] else { return }
        existing.updatedAt = now
        self.conversations[id] = existing
    }

    private func reindexAttachments() {
        let ids = Set(self.attachments.keys)
        self.attachmentOrder = self.attachmentOrder.filter { ids.contains($0) }
    }
}
