import Foundation

/// Schema version for the SoulNest local conversation cache.
///
/// The cache is rebuildable from the Gateway; a corrupt store only ever loses
/// local metadata, never authoritative transcript. Bump this when the on-disk
/// model shape changes and provide a migration path.
enum SoulNestSchemaVersion: Int, Codable, Equatable, Sendable {
    case v1 = 1
}

/// Migration entry point for the local conversation cache. Each version pair
/// that needs transformation gets a case here; unknown/older versions rebuild
/// from scratch rather than guessing.
enum SoulNestConversationCacheMigration {
    static func migrate(
        store: Any,
        from version: SoulNestSchemaVersion,
        to target: SoulNestSchemaVersion) -> SoulNestSchemaVersion
    {
        if version == target { return target }
        // No shape to migrate to; a future version would transform here.
        // Anything below the known floor rebuilds the local cache.
        return target
    }
}

/// High-level lifecycle state of a conversation index on device.
enum SoulNestConversationState: String, Codable, Equatable, Sendable {
    case active
    case archived
}

/// How far a local record has been reflected on the Gateway.
enum SoulNestMessageSyncState: String, Codable, Equatable, Sendable {
    case localDraft
    case pendingAck
    case synced
    case syncError
}

enum SoulNestMessageRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case system
}

/// Content shape of a cached message reference. Body bytes are never stored
/// locally; they are lazy-loaded from the Gateway authoritatively.
enum SoulNestMessageContentType: String, Codable, Equatable, Sendable {
    case text
    case note
}

/// Kind of a locally cached attachment. The actual media bytes live outside
/// this metadata store; only a reference + local status is kept.
enum SoulNestAttachmentKind: String, Codable, Equatable, Sendable {
    case image
    case video
    case file
}

enum SoulNestAttachmentLocalStatus: String, Codable, Equatable, Sendable {
    case missing
    case downloading
    case cached
    case available
}

/// Local metadata for a conversation. This mirrors, and is owned solely by,
/// the device: the Gateway keeps the authoritative transcript and session.
struct SoulNestConversationMetadata: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let agentID: String
    var sessionKey: String
    var title: String
    var state: SoulNestConversationState
    var createdAt: Date
    var updatedAt: Date
    var lastSyncedAt: Date?
    var syncState: SoulNestMessageSyncState

    init(
        id: UUID = UUID(),
        agentID: String,
        sessionKey: String,
        title: String,
        state: SoulNestConversationState = .active,
        createdAt: Date,
        updatedAt: Date = .distantPast,
        lastSyncedAt: Date? = nil,
        syncState: SoulNestMessageSyncState = .pendingAck)
    {
        self.id = id
        self.agentID = agentID
        self.sessionKey = sessionKey
        self.title = title
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSyncedAt = lastSyncedAt
        self.syncState = syncState
    }

    var isAuthoritative: Bool {
        false
    }
}

/// Local-only index entry for a single message. Never carries the message body.
struct SoulNestMessageMetadata: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let conversationID: UUID
    let role: SoulNestMessageRole
    let createdAt: Date
    let position: Int
    let sizeHint: Int
    let contentType: SoulNestMessageContentType
    let hasAttachments: Bool
    var syncState: SoulNestMessageSyncState

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        role: SoulNestMessageRole,
        createdAt: Date,
        position: Int,
        sizeHint: Int,
        contentType: SoulNestMessageContentType = .text,
        hasAttachments: Bool = false,
        syncState: SoulNestMessageSyncState = .synced)
    {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.createdAt = createdAt
        self.position = position
        self.sizeHint = sizeHint
        self.contentType = contentType
        self.hasAttachments = hasAttachments
        self.syncState = syncState
    }
}

/// Local reference for an attachment. Bytes are fetched/loaded on demand and
/// never inlined into the message metadata store.
struct SoulNestAttachmentReference: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let conversationID: UUID
    let messageID: UUID
    let kind: SoulNestAttachmentKind
    let byteSize: Int
    let remoteURL: URL?
    var localStatus: SoulNestAttachmentLocalStatus
    var cachedAt: Date?

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        messageID: UUID,
        kind: SoulNestAttachmentKind,
        byteSize: Int,
        remoteURL: URL? = nil,
        localStatus: SoulNestAttachmentLocalStatus = .missing)
    {
        self.id = id
        self.conversationID = conversationID
        self.messageID = messageID
        self.kind = kind
        self.byteSize = byteSize
        self.remoteURL = remoteURL
        self.localStatus = localStatus
        self.cachedAt = nil
    }
}
