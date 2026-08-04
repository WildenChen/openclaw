import OpenClawKit
import SwiftUI

struct SoulNestCharacterHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profileStore = SoulNestAgentProfileStore()
    @Binding private var isPresented: Bool

    private let gatewaySession: SoulNestGatewaySession

    init(
        gatewaySession: SoulNestGatewaySession,
        isPresented: Binding<Bool>)
    {
        self.gatewaySession = gatewaySession
        self._isPresented = isPresented
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                characterDisplay
                Spacer()
                startButton
            }
            .padding()
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
        }
    }

    private var characterDisplay: some View {
        VStack(spacing: 12) {
            characterImage
            characterName
            characterStateLabel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var characterImage: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 120))
            .foregroundStyle(OpenClawBrand.accent)
            .frame(width: 160, height: 160)
            .background(OpenClawBrand.void)
            .clipShape(Circle())
            .overlay(Circle().stroke(OpenClawBrand.obsidian, lineWidth: 4))
    }

    private var characterName: some View {
        Text(profileStore.current.displayName)
            .font(OpenClawType.headlineBold)
            .foregroundStyle(.primary)
    }

    private var characterStateLabel: some View {
        Text(self.gatewaySession.state.toCharacterState.humanReadable)
            .font(OpenClawType.caption)
            .foregroundStyle(.secondary)
    }

    private var startButton: some View {
        Button {
            self.isPresented = false
        } label: {
            Text("Start Conversation")
                .font(OpenClawType.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(OpenClawBrand.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private extension SoulNestGatewayConnectionState {
    var toCharacterState: SoulNestCharacterState {
        switch self {
        case .connected: return .idle
        case .connecting, .reconnecting: return .thinking
        case .pairing: return .offline
        case .failed: return .offline
        case .disconnected: return .offline
        }
    }
}
