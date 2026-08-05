import SwiftUI

/// The SoulNest landing scene: one immersive character view with the chat as a
/// bottom panel on the same screen. The character stays the primary visual and
/// its state tracks the gateway connection and generation.
struct SoulNestCharacterHomeView: View {
    @Binding private var isPresented: Bool
    @State private var store: SoulNestImmersiveChatStore

    init(
        gatewaySession: SoulNestGatewaySession,
        isPresented: Binding<Bool>)
    {
        self._isPresented = isPresented
        self._store = State(initialValue: SoulNestImmersiveChatStore(
            profile: .yujie,
            gatewaySession: gatewaySession))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                self.characterScene
                self.chatPanel
            }
            .background(OpenClawBrand.void)
            .navigationTitle("SoulNest")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        self.isPresented = false
                    } label: {
                        Text("Done")
                            .font(OpenClawType.body)
                    }
                }
            }
            .onAppear {
                self.store.startNewConversation()
            }
        }
    }

    private var characterScene: some View {
        VStack(spacing: 12) {
            self.characterArtwork
            self.characterName
            self.characterStateLabel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var characterArtwork: some View {
        SoulNestCharacterArtworkView(state: self.store.characterState)
            .frame(maxWidth: 280, maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(OpenClawBrand.obsidian, lineWidth: 1))
    }

    private var characterName: some View {
        Text(self.store.profile.displayName)
            .font(OpenClawType.headlineBold)
            .foregroundStyle(.primary)
    }

    private var characterStateLabel: some View {
        Text(self.store.characterState.humanReadable)
            .font(OpenClawType.caption)
            .foregroundStyle(.secondary)
    }

    private var chatPanel: some View {
        SoulNestImmersiveChatView(store: self.store)
            .frame(maxHeight: 300)
            .background(.ultraThinMaterial)
    }
}
