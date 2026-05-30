import SwiftUI

struct ContextChatView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            contextPreview

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
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .productPanel(padding: 16)
    }

    private var header: some View {
        HStack {
            Label("上下文对话", systemImage: "text.bubble")
                .font(.headline)

            Spacer()

            Label("⌃⌥W 读取选中文字", systemImage: "keyboard")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var contextPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前上下文")
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)

            Text(store.input.isEmpty ? "还没有上下文。选中文字后按快捷键，或直接在上方输入框粘贴内容。" : store.input)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(store.input.isEmpty ? AppTheme.mutedText : AppTheme.primaryText)
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
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
