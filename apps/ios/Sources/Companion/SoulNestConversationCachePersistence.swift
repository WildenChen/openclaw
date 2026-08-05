import Foundation

/// Codable, rebuildable on-disk representation of local conversation metadata.
/// It never contains message bodies, prompts, tool payloads, or attachment bytes.
struct SoulNestConversationCacheSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: SoulNestSchemaVersion
    let conversations: [SoulNestConversationMetadata]
    let messages: [SoulNestMessageMetadata]
    let attachments: [SoulNestAttachmentReference]
    let savedAt: Date

    init(
        schemaVersion: SoulNestSchemaVersion = .v1,
        conversations: [SoulNestConversationMetadata],
        messages: [SoulNestMessageMetadata],
        attachments: [SoulNestAttachmentReference],
        savedAt: Date = Date())
    {
        self.schemaVersion = schemaVersion
        self.conversations = conversations
        self.messages = messages
        self.attachments = attachments
        self.savedAt = savedAt
    }

    var isAuthoritative: Bool { false }
}

enum SoulNestConversationCacheLoadResult: Equatable, Sendable {
    case missing
    case loaded(SoulNestConversationCacheSnapshot)
    case corrupt
    case unsupportedSchema
}

enum SoulNestConversationCachePersistenceError: Error, Equatable, Sendable {
    case createDirectoryFailed
    case encodeFailed
    case writeFailed
}

/// Stores only rebuildable metadata with complete file protection. A corrupt or
/// unsupported file is never guessed at; callers discard it and rebuild from
/// the Gateway/session mapping.
struct SoulNestConversationCacheDiskStore: Sendable {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func applicationSupportURL(
        fileManager: FileManager = .default,
        bundleIdentifier: String = "com.wildenstudio.soulnest") -> URL
    {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("conversation-cache-v1.json", isDirectory: false)
    }

    func save(_ snapshot: SoulNestConversationCacheSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true)
        } catch {
            throw SoulNestConversationCachePersistenceError.createDirectoryFailed
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else {
            throw SoulNestConversationCachePersistenceError.encodeFailed
        }

        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            throw SoulNestConversationCachePersistenceError.writeFailed
        }
    }

    func load() -> SoulNestConversationCacheLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        guard let data = try? Data(contentsOf: fileURL) else { return .corrupt }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(SoulNestConversationCacheSnapshot.self, from: data)
        else {
            return .corrupt
        }
        guard snapshot.schemaVersion == .v1 else { return .unsupportedSchema }
        return .loaded(snapshot)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

/// Read-only local search over metadata. Search never queries message bodies and
/// never changes the Gateway-authoritative transcript.
struct SoulNestConversationSearchIndex: Sendable {
    func search(
        _ query: String,
        in conversations: [SoulNestConversationMetadata],
        includeArchived: Bool = false) -> [SoulNestConversationMetadata]
    {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return conversations
            .filter { includeArchived || $0.state == .active }
            .filter { normalized.isEmpty || $0.title.localizedCaseInsensitiveContains(normalized) }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt { return lhs.createdAt > rhs.createdAt }
                return lhs.updatedAt > rhs.updatedAt
            }
    }
}

/// Minimal authoritative digest returned by the Gateway. It intentionally
/// carries no transcript body; message bodies are fetched lazily when displayed.
struct SoulNestGatewayConversationDigest: Equatable, Sendable {
    let conversationID: UUID
    let sessionKey: String
    let latestPosition: Int?
    let updatedAt: Date
}

enum SoulNestConversationReconciliationAction: Equatable, Sendable {
    case keepLocal(conversationID: UUID)
    case fetchMetadata(conversationID: UUID, afterPosition: Int?)
    case replaceSessionKey(conversationID: UUID, sessionKey: String)
    case archiveLocalOnly(conversationID: UUID)
}

/// Produces a reconciliation plan without ever replaying local messages back to
/// the Gateway. The caller may fetch missing authoritative metadata, but there
/// is deliberately no upload-transcript action in this API.
struct SoulNestConversationReconciler: Sendable {
    func reconcile(
        localConversations: [SoulNestConversationMetadata],
        localMessages: [SoulNestMessageMetadata],
        gateway: [SoulNestGatewayConversationDigest]) -> [SoulNestConversationReconciliationAction]
    {
        let gatewayByID = Dictionary(uniqueKeysWithValues: gateway.map { ($0.conversationID, $0) })
        let messagesByConversation = Dictionary(grouping: localMessages, by: \.conversationID)
        var actions: [SoulNestConversationReconciliationAction] = []

        for local in localConversations {
            guard let remote = gatewayByID[local.id] else {
                actions.append(.archiveLocalOnly(conversationID: local.id))
                continue
            }

            if local.sessionKey != remote.sessionKey {
                actions.append(.replaceSessionKey(
                    conversationID: local.id,
                    sessionKey: remote.sessionKey))
            }

            let latestLocalPosition = messagesByConversation[local.id]?.map(\.position).max()
            if let latestRemotePosition = remote.latestPosition,
               latestLocalPosition == nil || latestLocalPosition! < latestRemotePosition
            {
                actions.append(.fetchMetadata(
                    conversationID: local.id,
                    afterPosition: latestLocalPosition))
            } else {
                actions.append(.keepLocal(conversationID: local.id))
            }
        }

        let localIDs = Set(localConversations.map(\.id))
        for remote in gateway where !localIDs.contains(remote.conversationID) {
            actions.append(.fetchMetadata(
                conversationID: remote.conversationID,
                afterPosition: nil))
        }

        return actions
    }
}
