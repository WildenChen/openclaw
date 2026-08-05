import Testing
@testable import OpenClaw

struct SoulNestMessagePresentationPolicyTests {
    private let policy = SoulNestMessagePresentationPolicy()

    @Test func `assistant metadata becomes chat bubble`() {
        let result = policy.present(SoulNestGatewayMessageEnvelope(
            kind: .assistant,
            content: "Hello"))

        #expect(result.kind == .assistant)
        #expect(result.presentation == .chatBubble)
        #expect(result.content == "Hello")
    }

    @Test func `tool payload is collapsible and never assistant speech`() {
        let result = policy.present(SoulNestGatewayMessageEnvelope(
            kind: .tool,
            eventType: "tool.completed",
            content: #"{"result":"ok"}"#))

        #expect(result.kind == .tool)
        #expect(result.presentation == .collapsibleStatus)
    }

    @Test func `background system event is hidden outside developer mode`() {
        let envelope = SoulNestGatewayMessageEnvelope(
            kind: nil,
            eventType: "system.memory",
            content: "memory maintenance")

        #expect(policy.present(envelope).presentation == .hidden)
        #expect(policy.present(envelope, developerMode: true).presentation == .developerOnly)
    }

    @Test func `unknown event uses conservative status fallback`() {
        let result = policy.present(SoulNestGatewayMessageEnvelope(
            kind: nil,
            eventType: "future.event",
            content: "opaque payload"))

        #expect(result.kind == .status)
        #expect(result.presentation == .collapsibleStatus)
    }

    @Test func `authorization and private paths are redacted`() {
        let result = policy.present(SoulNestGatewayMessageEnvelope(
            kind: .debug,
            content: "Authorization: Bearer abc.def token=supersecret /Users/wilden/private/file",
            metadata: ["token": "supersecret"]), developerMode: true)

        #expect(!result.content.contains("abc.def"))
        #expect(!result.content.contains("supersecret"))
        #expect(!result.content.contains("/Users/wilden"))
        #expect(result.content.contains("[REDACTED]"))
        #expect(result.content.contains("[PRIVATE_PATH]"))
    }
}
