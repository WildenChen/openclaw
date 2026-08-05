import SwiftUI

/// The immersive chat bottom panel. Sits under the character scene on the same
/// screen and owns the message list, input bar, thinking indicator, and the
/// connection/error feedback so every send outcome is visible.
struct SoulNestImmersiveChatView: View {
    @Bindable private var store: SoulNestImmersiveChatStore
    @State private var textInput = ""
    @FocusState private var isInputFocused: Bool

    init(store: SoulNestImmersiveChatStore) {
        self.store = store
    }

    private var isInputDisabled: Bool {
        self.store.isSending || self.store.isGenerating || self.store.isOffline
    }

    var body: some View {
        VStack(spacing: 0) {
            if self.store.showError {
                self.errorBanner
            } else if self.store.isOffline, !self.store.isGenerating {
                self.offlineBanner
            }
            self.messageList
            self.inputBar
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14))
            Text("Not connected to Gateway")
                .font(OpenClawType.caption)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
            Text("Could not send. Check the connection and try again.")
                .font(OpenClawType.caption)
            Spacer()
        }
        .foregroundStyle(OpenClawBrand.danger)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if self.store.messages.isEmpty, !self.store.isSending {
                        self.emptyHint
                    }
                    ForEach(self.store.messages) { message in
                        self.messageBubble(message)
                            .id(message.id)
                    }
                    if self.store.isGenerating {
                        self.thinkingIndicator
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(minHeight: 0, maxHeight: 180)
            .onChange(of: self.store.messages) { _, messages in
                if let last = messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: self.store.isGenerating) { _, isGenerating in
                if isGenerating {
                    withAnimation {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyHint: some View {
        Text("Send a message to start the conversation.")
            .font(OpenClawType.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    @ViewBuilder
    private func messageBubble(_ message: SoulNestChatMessage) -> some View {
        let displayedText: String = if message.role == .assistant, message.isStreaming {
            self.store.assistantText(for: message.requestID ?? "")
        } else {
            message.text
        }

        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .assistant {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(OpenClawBrand.accent)
            }
            Text(displayedText.isEmpty ? "…" : displayedText)
                .font(OpenClawType.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(message.role == .user ? OpenClawBrand.accent : OpenClawBrand.obsidian)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if message.role == .user {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(OpenClawBrand.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(OpenClawBrand.accent)
                .frame(width: 6, height: 6)
            Circle()
                .fill(OpenClawBrand.accent)
                .frame(width: 6, height: 6)
            Circle()
                .fill(OpenClawBrand.accent)
                .frame(width: 6, height: 6)
        }
        .padding(12)
        .background(OpenClawBrand.obsidian)
        .clipShape(Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("", text: self.$textInput, prompt: Text("Message").font(OpenClawType.body), axis: .horizontal)
                .font(OpenClawType.body)
                .disabled(self.isInputDisabled)
                .focused(self.$isInputFocused)
                .accessibilityLabel("Message")
            Button {
                let text = self.textInput
                Task {
                    await self.store.sendText(text)
                    self.textInput = ""
                }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(OpenClawBrand.accent)
                    .accessibilityLabel("Send")
            }
            .disabled(self.isInputDisabled || self.textInput.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
