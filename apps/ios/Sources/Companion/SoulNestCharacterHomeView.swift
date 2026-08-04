import OpenClawKit
import SwiftUI

struct SoulNestCharacterHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profileStore = SoulNestAgentProfileStore()
    @State private var assetCache = SoulNestCharacterAssetCache(maxBytes: 50 * 1024 * 1024)
    @State private var assetIndex = SoulNestCharacterAssetIndex(access: .general)
    @State private var isChatPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    self.headerSection
                    self.characterCard
                }
                .padding()
            }
            .navigationTitle("Characters")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        self.dismiss()
                    }
                }
            }
            .sheet(isPresented: self.$isChatPresented) {
                SoulNestImmersiveChatView(
                    profile: self.profileStore.current,
                    assetCache: self.assetCache,
                    assetIndex: self.assetIndex)
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Available Characters")
                .font(OpenClawType.headlineBold)
                .foregroundStyle(.primary)
            Text("Tap a character to start a conversation")
                .font(OpenClawType.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var characterCard: some View {
        Button {
            self.isChatPresented = true
        } label: {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(OpenClawBrand.accent)
                    .frame(width: 80, height: 80)
                    .background(OpenClawBrand.void)
                    .clipShape(Circle())

                Text(self.profileStore.current.displayName)
                    .font(OpenClawType.headline)
                    .foregroundStyle(.primary)

                Text(self.profileStore.current.characterAssetPackID)
                    .font(OpenClawType.caption)
                    .foregroundStyle(.secondary)

                self.capabilitiesHStack
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(OpenClawBrand.obsidian)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var capabilitiesHStack: some View {
        HStack(spacing: 8) {
            ForEach(
                self.profileStore.current.capabilities.sorted(by: { $0.rawValue < $1.rawValue }),
                id: \.self)
            { capability in
                Text(capability.label)
                    .font(OpenClawType.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(OpenClawBrand.void)
                    .clipShape(Capsule())
            }
        }
    }
}

extension SoulNestAgentProfile.Capability {
    fileprivate var label: String {
        switch self {
        case .textChat: "Text"
        case .talkMode: "Talk"
        case .imageAttachments: "Images"
        case .secretaryCards: "Cards"
        case .deviceCapabilities: "Device"
        }
    }
}
