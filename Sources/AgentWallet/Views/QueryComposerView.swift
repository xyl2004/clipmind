import SwiftUI

struct QueryComposerView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                TextField("粘贴地址、合约、交易哈希、项目名或一段 Web3 内容", text: $store.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(AppTheme.primaryText)
                    .colorScheme(.light)
                    .tint(AppTheme.accent)
                    .padding(12)
                    .lineLimit(1...4)
                    .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )

                Button {
                    performPrimaryAction()
                } label: {
                    if store.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(primaryActionTitle, systemImage: primaryActionIcon)
                    }
                }
                .buttonStyle(ProductButtonStyle(prominent: true))
                .disabled(store.isLoading)
                .keyboardShortcut(.return, modifiers: [.command])
                .padding(.top, 1)
            }

            if let selectedTextMessage = store.selectedTextMessage {
                Label(selectedTextMessage, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(20)
        .background(Color.black.opacity(0.035))
    }

    private var hasInput: Bool {
        !store.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var primaryActionTitle: String {
        hasInput ? "查询" : "读取选中内容"
    }

    private var primaryActionIcon: String {
        hasInput ? "magnifyingglass" : "text.viewfinder"
    }

    private func performPrimaryAction() {
        if hasInput {
            Task {
                await store.runResearch()
            }
            return
        }

        if store.captureSelectedText() {
            Task {
                await store.preloadContextDetailsIfUseful()
            }
        }
    }
}
