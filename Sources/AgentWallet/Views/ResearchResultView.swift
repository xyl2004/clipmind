import SwiftUI

struct ResearchResultView: View {
    @ObservedObject var store: AppStore
    let snapshot: ResearchSnapshot
    let aiExplanation: String?
    let isExplaining: Bool
    let llmErrorMessage: String?
    let onRefreshExplanation: () -> Void
    @State private var showsRawJSON = false
    @State private var showsDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            AIExplanationCard(
                explanation: aiExplanation,
                isExplaining: isExplaining,
                errorMessage: llmErrorMessage,
                onRefresh: onRefreshExplanation
            )

            ForEach(snapshot.warnings, id: \.self) { warning in
                StatusBanner(
                    title: "部分数据",
                    message: warning,
                    systemImage: "exclamationmark.triangle",
                    tint: .orange
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], alignment: .leading, spacing: 16) {
                ForEach(snapshot.sections) { section in
                    ResultSectionCard(section: section)
                }
            }

            if snapshot.kind == .token {
                TradeIntentView(store: store, query: snapshot.query)
            }

            DisclosureGroup("调试信息", isExpanded: $showsDiagnostics) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(snapshot.commands) { command in
                            HStack {
                                Image(systemName: command.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(command.succeeded ? .green : .red)
                                Text(command.command)
                                    .font(.system(.caption, design: .monospaced))
                                Spacer()
                                Text(command.summary)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }

                    DisclosureGroup("原始 JSON", isExpanded: $showsRawJSON) {
                        Text(snapshot.rawJSON)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.top, 8)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(snapshot.title, systemImage: snapshot.kind.systemImage)
                    .font(.title2.weight(.semibold))
                Spacer()
                Text(snapshot.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(snapshot.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(snapshot.query)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}

private struct AIExplanationCard: View {
    let explanation: String?
    let isExplaining: Bool
    let errorMessage: String?
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI 中文解读", systemImage: "brain")
                    .font(.headline)

                Spacer()

                Button {
                    onRefresh()
                } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
                }
                .disabled(isExplaining)
            }

            if isExplaining {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("DeepSeek V4 Flash 正在整理 Surf 数据")
                        .foregroundStyle(.secondary)
                }
            } else if let explanation, !explanation.isEmpty {
                Text(verbatim: explanation)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            } else {
                Text("等待查询结果。")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .productPanel(padding: 16)
    }
}

struct ResultSectionCard: View {
    let section: ResearchSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(section.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                            .frame(width: 104, alignment: .leading)
                            .lineLimit(2)

                        Text(row.value)
                            .font(row.style == .mono ? .system(.body, design: .monospaced) : .body)
                            .foregroundStyle(color(for: row.style))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .productPanel(padding: 16)
    }

    private func color(for style: ResearchRowStyle) -> Color {
        switch style {
        case .regular, .mono:
            .primary
        case .positive:
            .green
        case .warning:
            .orange
        }
    }
}
