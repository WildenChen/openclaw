import SwiftUI

/// Covers private character and conversation content whenever the app is not
/// active, preventing sensitive snapshots from appearing in the app switcher.
struct SoulNestPrivacyShieldModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .privacySensitive()
            .overlay {
                if isEnabled && scenePhase != .active {
                    ZStack {
                        Color.black
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 42))
                            Text("SoulNest Locked")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("SoulNest content hidden")
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
    }
}

extension View {
    func soulNestPrivacyShield(isEnabled: Bool = true) -> some View {
        modifier(SoulNestPrivacyShieldModifier(isEnabled: isEnabled))
    }
}

/// Coordinates complete local-secret removal. Cache and private media cleanup
/// are injected so the caller can clear every local protection domain without
/// coupling the Keychain layer to a particular database implementation.
@MainActor
struct SoulNestPrivateDataEraser {
    let credentials: any SoulNestSecureCredentialStore
    let clearConversationCache: () throws -> Void
    let clearPrivateMediaIndex: () throws -> Void

    func eraseAll() throws {
        try credentials.removeAll()
        try clearConversationCache()
        try clearPrivateMediaIndex()
    }
}
