import SwiftUI

struct ContextChatView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !store.chatMessages.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.chatMessages) { message in
                        ChatBubble(message: message)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("问 AI：这段内容是什么？这个地址有什么风险？这个项目在做什么？", text: $store.chatQuestion, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(AppTheme.primaryText)
                    .colorScheme(.light)
                    .tint(AppTheme.accent)
                    .padding(12)
                    .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                    .lineLimit(1...4)

                Button {
                    Task {
                        await store.askAboutSelectedContext()
                    }
                } label: {
                    if store.isAnsweringQuestion {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("询问 AI", systemImage: "paperplane")
                    }
                }
                .buttonStyle(ProductButtonStyle(prominent: true))
                .disabled(store.isAnsweringQuestion)
                .keyboardShortcut(.return, modifiers: [.command])
            }

            if let llmErrorMessage = store.llmErrorMessage {
                Label(llmErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            if let contextDetailErrorMessage = store.contextDetailErrorMessage {
                Label(contextDetailErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .productPanel(padding: 16)
    }

    private var header: some View {
        HStack {
            Label("追问当前内容", systemImage: "text.bubble")
                .font(.headline)

            Spacer()

            if store.isLoadingContextDetails {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

private struct ChatBubble: View {
    let message: ContextChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 56)
            } else {
                Spacer(minLength: 56)
                bubble
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role == .assistant ? "AI" : "你")
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)
            Text(verbatim: message.text)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var background: some ShapeStyle {
        message.role == .assistant ? AnyShapeStyle(AppTheme.panelSoft) : AnyShapeStyle(AppTheme.accent.opacity(0.18))
    }
}
