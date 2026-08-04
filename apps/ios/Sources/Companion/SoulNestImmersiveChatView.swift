import OpenClawKit
import SwiftUI

struct SoulNestImmersiveChatView: View {
    @Environment(\.dismiss) private var dismiss
    let profile: SoulNestAgentProfile
    let assetCache: SoulNestCharacterAssetCache
    let assetIndex: SoulNestCharacterAssetIndex
    @State private var conversationStore = SoulNestConversationSessionStore()
    @State private var messages: [SoulNestMessageMetadata] = []
    @State private var inputText = ""
    @State private var isSending = false
    @State private var sessionKey: String?
    @State private var conversationID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            self.headerBar
            Divider()
            self.messageList
            Divider()
            self.inputBar
        }
        .navigationTitle(self.profile.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    self.dismiss()
                }
            }
        }
        .onAppear {
            self.setupSession()
        }
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(OpenClawBrand.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(self.profile.displayName)
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(.primary)
                Text("Ready")
                    .font(OpenClawType.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(self.messages, id: \.id) { message in
                        self.messageBubble(message)
                    }
                }
                .padding()
            }
            .onChange(of: self.messages.count) {
                if let last = self.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func messageBubble(_ message: SoulNestMessageMetadata) -> some View {
        HStack {
            if message.role == .user {
                Spacer()
                Text("You")
                    .font(OpenClawType.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(message.contentType == .text ? "Message" : "Attachment")
                .font(OpenClawType.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(message.role == .user ? OpenClawBrand.accent : OpenClawBrand.void)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if message.role == .assistant {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Type a message...", text: self.$inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(OpenClawType.body)
                .lineLimit(1...4)

            Button {
                self.sendText()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(self.inputText.isEmpty ? .secondary : OpenClawBrand.accent)
            }
            .disabled(self.inputText.isEmpty || self.isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func setupSession() {
        let session = self.conversationStore.session(
            for: self.conversationID,
            profile: self.profile)
        self.sessionKey = session.sessionKey
        self.messages = []
    }

    private func sendText() {
        let trimmed = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let sessionKey = self.sessionKey else { return }

        self.isSending = true
        self.inputText = ""

        let metadata = SoulNestMessageMetadata(
            id: UUID(),
            conversationID: self.conversationID,
            role: .user,
            createdAt: Date(),
            position: self.messages.count,
            sizeHint: trimmed.count,
            contentType: .text)
        self.messages.append(metadata)

        self.isSending = false
    }
}
