import Testing
@testable import OpenClaw

struct SoulNestSecureCredentialStoreTests {
    @Test func `in memory credential store round trips and removes secrets`() throws {
        let store = SoulNestInMemoryCredentialStore()

        try store.save("token-value", for: .gatewayToken)
        try store.save("pairing-value", for: .pairingCredential)

        #expect(try store.value(for: .gatewayToken) == "token-value")
        #expect(try store.value(for: .pairingCredential) == "pairing-value")

        try store.remove(.gatewayToken)
        #expect(try store.value(for: .gatewayToken) == nil)
        #expect(try store.value(for: .pairingCredential) == "pairing-value")
    }

    @Test func `private data eraser clears every protection domain`() throws {
        let store = SoulNestInMemoryCredentialStore()
        try store.save("secret", for: .gatewayToken)

        final class Flags: @unchecked Sendable {
            var cacheCleared = false
            var mediaCleared = false
        }
        let flags = Flags()

        let eraser = SoulNestPrivateDataEraser(
            credentials: store,
            clearConversationCache: { flags.cacheCleared = true },
            clearPrivateMediaIndex: { flags.mediaCleared = true })

        try eraser.eraseAll()

        #expect(try store.value(for: .gatewayToken) == nil)
        #expect(flags.cacheCleared)
        #expect(flags.mediaCleared)
    }
}
