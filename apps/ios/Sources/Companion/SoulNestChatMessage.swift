import Foundation

/// The lifecycle status of a message in the active conversation.
enum SoulNestChatMessageStatus: Equatable, Sendable {
    /// Sent to the gateway, no event observed yet.
    case queued
    /// The gateway is processing; awaiting the first assistant text.
    case thinking
    /// Assistant text is streaming in full-snapshot updates.
    case streaming
    /// The final event arrived and the response is complete.
    case completed
    /// The turn was stopped by the operator.
    case cancelled
    /// The turn ended in a failure the operator can retry.
    case failed(SoulNestGatewayError)
}

/// A message in the immersive chat UI. Distinct from `SoulNestMessageMetadata`
/// (which is cache index metadata only): this carries display content for the
/// active conversation, including in-flight assistant text.
struct SoulNestChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: SoulNestMessageRole
    let text: String
    let status: SoulNestChatMessageStatus
    let requestID: String?

    /// True while the turn is still in flight and the message should read its
    /// text live from the gateway snapshot.
    var isStreaming: Bool {
        switch self.status {
        case .queued, .thinking, .streaming: true
        case .completed, .cancelled, .failed: false
        }
    }

    /// True when the turn ended in a way the operator can retry in place.
    var isRetryable: Bool {
        switch self.status {
        case .failed, .cancelled: true
        case .queued, .thinking, .streaming, .completed: false
        }
    }

    /// Returns a copy with the given status, keeping the current text. Used for
    /// non-terminal transitions (queued -> thinking -> streaming).
    func withStatus(_ status: SoulNestChatMessageStatus) -> SoulNestChatMessage {
        SoulNestChatMessage(
            id: self.id,
            role: self.role,
            text: self.text,
            status: status,
            requestID: self.requestID)
    }

    /// Returns a copy with the final/partial snapshot committed as the display
    /// text and a terminal status.
    func commit(_ text: String, status: SoulNestChatMessageStatus) -> SoulNestChatMessage {
        SoulNestChatMessage(
            id: self.id,
            role: self.role,
            text: text,
            status: status,
            requestID: self.requestID)
    }
}
