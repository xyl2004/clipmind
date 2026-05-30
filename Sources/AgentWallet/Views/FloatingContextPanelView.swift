import SwiftUI

struct FloatingContextPanelView: View {
    @ObservedObject var store: AppStore
    let onClose: () -> Void
    let onSizeChange: (CGSize) -> Void

    private let panelWidth: CGFloat = 820
    private let chromePadding: CGFloat = 8

    private var contentHeight: CGFloat {
        let base: CGFloat = 228
        guard hasScrollableContent else {
            return base
        }

        return min(base + scrollContentHeight + 12, 610)
    }

    private var reportedSize: CGSize {
        CGSize(
            width: panelWidth + chromePadding * 2,
            height: contentHeight + chromePadding * 2
        )
    }

    private var hasScrollableContent: Bool {
        store.isLoadingContextDetails
            || store.contextDetailErrorMessage != nil
            || store.currentContextSnapshot != nil
            || !store.chatMessages.isEmpty
    }

    private var scrollContentHeight: CGFloat {
        var height: CGFloat = 0

        if store.isLoadingContextDetails || store.contextDetailErrorMessage != nil {
            height += 44
        }

        if let snapshot = store.currentContextSnapshot {
            height += estimatedSnapshotHeight(snapshot)
        }

        if !store.chatMessages.isEmpty {
            height += min(CGFloat(store.chatMessages.count) * 88 + 12, 260)
        }

        return min(max(height, 80), 370)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(spacing: 0) {
                historySidebar

                Divider()

                chatColumn
            }
        }
        .frame(width: panelWidth, height: contentHeight)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 24, x: 0, y: 12)
        .padding(chromePadding)
        .onAppear(perform: reportSize)
        .onChange(of: store.chatMessages.count) { reportSize() }
        .onChange(of: store.chatQuestion) { reportSize() }
        .onChange(of: store.chatSessions.count) { reportSize() }
        .onChange(of: store.activeChatSessionID) { reportSize() }
        .onChange(of: store.isLoadingContextDetails) { reportSize() }
        .onChange(of: store.contextDetailErrorMessage) { reportSize() }
        .onChange(of: store.currentContextSnapshot?.id) { reportSize() }
        .onChange(of: store.isAnsweringQuestion) { reportSize() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("AgentWallet", systemImage: "wallet.pass")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            Spacer()

            Text("⌃⌥W")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(AppTheme.mutedText)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.24))
    }

    private var historySidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(AppTheme.cyan)
                Text("历史")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)
                Spacer()
            }

            if store.chatSessions.isEmpty {
                Text("暂无对话")
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.chatSessions) { session in
                            Button {
                                store.selectChatSession(session)
                            } label: {
                                FloatingHistoryRow(
                                    session: session,
                                    isActive: session.id == store.activeChatSessionID
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 178)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.30))
    }

    private var chatColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            FloatingContextPreview(context: store.input)

            if hasScrollableContent {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        detailStatus

                        if let snapshot = store.currentContextSnapshot {
                            FloatingResearchSummary(snapshot: snapshot)
                        }

                        if !store.chatMessages.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(store.chatMessages) { message in
                                    FloatingChatBubble(message: message)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: scrollContentHeight)
            }

            composer

            if let llmErrorMessage = store.llmErrorMessage {
                Label(llmErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var detailStatus: some View {
        if store.isLoadingContextDetails {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在读取 Base / Surf 详情")
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
        } else if let message = store.contextDetailErrorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("问 AI：这段内容是什么？这个地址有什么风险？这个项目在做什么？", text: $store.chatQuestion, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(11)
                .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
                .lineLimit(1...4)

            Button {
                Task {
                    await store.askAboutSelectedContext()
                    reportSize()
                }
            } label: {
                if store.isAnsweringQuestion {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 60)
                } else {
                    Label("询问 AI", systemImage: "paperplane.fill")
                }
            }
            .buttonStyle(ProductButtonStyle(prominent: true))
            .disabled(store.isAnsweringQuestion)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private func estimatedSnapshotHeight(_ snapshot: ResearchSnapshot) -> CGFloat {
        let rowCount = snapshot.sections.reduce(0) { $0 + $1.rows.count }
        let sectionEstimate = CGFloat(snapshot.sections.count) * 46
        let rowEstimate = CGFloat(rowCount) * 22
        return min(max(64 + sectionEstimate + rowEstimate, 150), 360)
    }

    private func reportSize() {
        DispatchQueue.main.async {
            onSizeChange(reportedSize)
        }
    }
}

private struct FloatingContextPreview: View {
    let context: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前上下文")
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)

            Text(context.isEmpty ? "还没有读取到选中文本。" : context)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(context.isEmpty ? AppTheme.mutedText : AppTheme.primaryText)
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
        }
    }
}

private struct FloatingResearchSummary: View {
    let snapshot: ResearchSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(snapshot.title, systemImage: snapshot.kind.systemImage)
                    .font(.headline)
                Spacer()
                Text(snapshot.subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 230), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(snapshot.sections.prefix(5)) { section in
                    FloatingSectionCard(section: section)
                }
            }
        }
    }
}

private struct FloatingSectionCard: View {
    let section: ResearchSection

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(section.title)
                .font(.callout.weight(.semibold))

            VStack(spacing: 7) {
                ForEach(section.rows.prefix(6)) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.label)
                            .font(.caption)
                            .foregroundStyle(AppTheme.mutedText)
                            .frame(width: 76, alignment: .leading)
                            .lineLimit(1)

                        Text(row.value)
                            .font(row.style == .mono ? .system(.caption, design: .monospaced) : .caption)
                            .foregroundStyle(color(for: row.style))
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    private func color(for style: ResearchRowStyle) -> Color {
        switch style {
        case .regular, .mono:
            AppTheme.primaryText
        case .positive:
            .green
        case .warning:
            .orange
        }
    }
}

private struct FloatingChatBubble: View {
    let message: ContextChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 42)
            } else {
                Spacer(minLength: 42)
                bubble
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(message.role == .assistant ? "AI" : "你")
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)
            Text(verbatim: message.text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: 480, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.border.opacity(message.role == .assistant ? 1 : 0), lineWidth: 1)
        )
    }

    private var background: some ShapeStyle {
        message.role == .assistant ? AnyShapeStyle(AppTheme.panelSoft) : AnyShapeStyle(AppTheme.accent.opacity(0.18))
    }
}

private struct FloatingHistoryRow: View {
    let session: ContextChatSession
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(isActive ? AppTheme.accent : AppTheme.border)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)

                Text(session.subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? AppTheme.accent.opacity(0.16) : Color.white.opacity(0.36))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActive ? AppTheme.accent.opacity(0.42) : AppTheme.border, lineWidth: 1)
        )
    }
}
