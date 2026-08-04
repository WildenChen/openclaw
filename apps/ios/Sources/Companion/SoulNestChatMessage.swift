import Foundation

/// A message in the immersive chat UI. Distinct from `SoulNestMessageMetadata`
/// (which is cache index metadata only): this carries display content for the
/// active conversation, including in-flight assistant text.
struct SoulNestChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: SoulNestMessageRole
    let text: String
    let isStreaming: Bool
    let requestID: String?
}
