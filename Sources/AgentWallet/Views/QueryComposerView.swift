import SwiftUI

struct QueryComposerView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Picker("类型", selection: $store.selectedKind) {
                    ForEach(QueryKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.systemImage)
                            .tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 460)

                Spacer()

                Button {
                    store.captureClipboard()
                } label: {
                    Label("剪贴板", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(ProductButtonStyle())

                Button {
                    store.captureSelectedText()
                } label: {
                    Label("选中文字", systemImage: "text.viewfinder")
                }
                .buttonStyle(ProductButtonStyle())

                Button {
                    Task {
                        await store.runResearch()
                    }
                } label: {
                    if store.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("查询", systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(ProductButtonStyle(prominent: true))
                .disabled(store.isLoading)
                .keyboardShortcut(.return, modifiers: [.command])
            }

            TextField("粘贴 Base 地址、代币合约、交易哈希或项目名称", text: $store.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(AppTheme.primaryText)
                .colorScheme(.light)
                .tint(AppTheme.accent)
                .padding(12)
                .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )

            HStack(spacing: 8) {
                Label("当前模式：\(store.effectiveKind.title)", systemImage: store.effectiveKind.systemImage)
                Text("仅 Base")
                Text("Surf 实时数据")
            }
            .font(.caption)
            .foregroundStyle(AppTheme.mutedText)

            if let selectedTextMessage = store.selectedTextMessage {
                Label(selectedTextMessage, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            LLMSettingsInlineView(store: store)
        }
        .padding(20)
        .background(Color.black.opacity(0.035))
    }
}

private struct LLMSettingsInlineView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        HStack(spacing: 10) {
            Label("AI 解释", systemImage: "brain")
                .foregroundStyle(store.hasLLMAPIKey ? .green : .secondary)

            if store.hasLLMAPIKey {
                Text("DeepSeek V4 Flash 已启用")
                    .foregroundStyle(.secondary)
            } else {
                SecureField("B.AI API Key", text: $store.apiKeyDraft)
                    .textFieldStyle(.plain)
                    .foregroundStyle(AppTheme.primaryText)
                    .colorScheme(.light)
                    .tint(AppTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(width: 260)

                Button {
                    store.saveAPIKey()
                } label: {
                    Label("保存", systemImage: "key")
                }
                .buttonStyle(ProductButtonStyle())
                .disabled(store.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let apiKeyStatusMessage = store.apiKeyStatusMessage {
                Text(apiKeyStatusMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .font(.caption)
        .foregroundStyle(AppTheme.mutedText)
    }
}
