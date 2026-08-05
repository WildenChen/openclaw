import Foundation

/// Semantic message classes used by the companion UI. Classification is based
/// on Gateway metadata, never on natural-language keyword guesses.
enum SoulNestMessageKind: String, Codable, CaseIterable, Sendable {
    case user
    case assistant
    case tool
    case system
    case status
    case error
    case debug
}

/// Where a classified message is allowed to appear.
enum SoulNestMessagePresentation: Equatable, Sendable {
    case chatBubble
    case collapsibleStatus
    case developerOnly
    case hidden
}

/// Normalized metadata received from the Gateway boundary before presentation.
struct SoulNestGatewayMessageEnvelope: Equatable, Sendable {
    let kind: SoulNestMessageKind?
    let eventType: String?
    let content: String
    let metadata: [String: String]

    init(
        kind: SoulNestMessageKind?,
        eventType: String? = nil,
        content: String,
        metadata: [String: String] = [:])
    {
        self.kind = kind
        self.eventType = eventType
        self.content = content
        self.metadata = metadata
    }
}

struct SoulNestPresentedMessage: Equatable, Sendable {
    let kind: SoulNestMessageKind
    let presentation: SoulNestMessagePresentation
    let content: String
}

/// Conservative presentation policy for companion chat.
///
/// Unknown events never become assistant speech. They are retained as a
/// redacted, collapsible status so diagnostics remain available without
/// breaking character immersion or exposing raw payloads.
struct SoulNestMessagePresentationPolicy: Sendable {
    private let sanitizer = SoulNestMessageSanitizer()

    func present(_ envelope: SoulNestGatewayMessageEnvelope, developerMode: Bool = false)
        -> SoulNestPresentedMessage
    {
        let kind = envelope.kind ?? Self.kind(forEventType: envelope.eventType)
        let safeContent = sanitizer.sanitize(
            envelope.content,
            metadata: envelope.metadata)

        switch kind {
        case .user, .assistant:
            return SoulNestPresentedMessage(
                kind: kind,
                presentation: .chatBubble,
                content: safeContent)
        case .tool, .status:
            return SoulNestPresentedMessage(
                kind: kind,
                presentation: .collapsibleStatus,
                content: safeContent)
        case .error:
            return SoulNestPresentedMessage(
                kind: .error,
                presentation: .collapsibleStatus,
                content: safeContent)
        case .system:
            return SoulNestPresentedMessage(
                kind: .system,
                presentation: developerMode ? .developerOnly : .hidden,
                content: safeContent)
        case .debug:
            return SoulNestPresentedMessage(
                kind: .debug,
                presentation: developerMode ? .developerOnly : .hidden,
                content: safeContent)
        }
    }

    private static func kind(forEventType eventType: String?) -> SoulNestMessageKind {
        switch eventType {
        case "assistant.message", "assistant.final":
            return .assistant
        case "tool.started", "tool.progress", "tool.completed":
            return .tool
        case "system.memory", "system.schedule", "system.background":
            return .system
        case "status", "connection.status":
            return .status
        case "request.failed", "gateway.error":
            return .error
        case "debug", "trace":
            return .debug
        default:
            return .status
        }
    }
}

/// Removes secrets and private machine paths before content reaches any UI or
/// export surface. This is a defense-in-depth display sanitizer, not a
/// substitute for avoiding sensitive payloads at the source.
struct SoulNestMessageSanitizer: Sendable {
    func sanitize(_ content: String, metadata: [String: String] = [:]) -> String {
        var output = content

        let sensitiveMetadataKeys = [
            "authorization",
            "proxy-authorization",
            "api-key",
            "x-api-key",
            "token",
            "access_token",
            "refresh_token",
        ]

        for (key, value) in metadata where sensitiveMetadataKeys.contains(key.lowercased()) {
            guard !value.isEmpty else { continue }
            output = output.replacingOccurrences(of: value, with: "[REDACTED]")
        }

        output = replacing(
            pattern: #"(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+"#,
            in: output,
            with: "$1 [REDACTED]")
        output = replacing(
            pattern: #"(?i)\b(api[_-]?key|access[_-]?token|refresh[_-]?token)\s*[:=]\s*[^\s,;]+"#,
            in: output,
            with: "$1=[REDACTED]")
        output = replacing(
            pattern: #"/(Users|home)/[^/\s]+(?:/[^\s]*)?"#,
            in: output,
            with: "/$1/[PRIVATE_PATH]")

        return output
    }

    private func replacing(pattern: String, in value: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: template)
    }
}
