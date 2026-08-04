import OpenClawKit
import SwiftUI

struct SoulNestImmersiveChatView: View {
    @Bindable private var store: SoulNestImmersiveChatStore
    @State private var textInput = ""
    @FocusState private var isInputFocused: Bool

    init(store: SoulNestImmersiveChatStore) {
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
                .safeAreaInset(edge: .bottom) {
                    inputBar
                        .background(.ultraThinMaterial)
                }
        }
        .background(OpenClawBrand.void)
        .onAppear {
            self.store.startNewConversation()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if self.store.messages.isEmpty && !self.store.isSending {
                        characterIdlePlaceholder
                    }
                    ForEach(self.store.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if self.store.isGenerating {
                        thinkingIndicator
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .scrollDismissDisplaysScrollIndicators(false)
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

    private var characterIdlePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(OpenClawBrand.accent)
            Text(self.store.profile.displayName)
                .font(OpenClawType.subheadline)
                .foregroundStyle(.secondary)
            Text("Send a message to start the conversation.")
                .font(OpenClawType.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private func messageBubble(_ message: SoulNestChatMessage) -> some View {
        let displayedText: String
        if message.role == .assistant && message.isStreaming {
            displayedText = self.store.assistantText(for: message.requestID ?? "")
        } else {
            displayedText = message.text
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
                .background(message.role == .user ? OpenClawBrand.accent : OpenClawGray.field)
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
        .background(OpenClawGray.field)
        .clipShape(Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            Button(action: {}) label: {
                Image(systemName: "waveform")
                    .font(.system(size: 20))
                    .foregroundStyle(OpenClawBrand.accent)
                    .accessibilityLabel("Voice input")
            }
            TextField("", text: $textInput, axis: .horizontal, prompt: Text("Message").font(OpenClawType.body))
                .font(OpenClawType.body)
                .disabled(self.store.isSending || self.store.isGenerating)
                .focused($isInputFocused)
                .accessibilityLabel("Message")
            Button {
                Task {
                    await self.store.sendText(self.textInput)
                    self.textInput = ""
                }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(OpenClawBrand.accent)
                    .accessibilityLabel("Send")
            }
            .disabled(self.store.isSending || self.store.isGenerating || self.textInput.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
