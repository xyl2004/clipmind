import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label("AgentWallet", systemImage: "wallet.pass")
                    .font(.system(size: 22, weight: .bold))
                Text("Base Context Agent")
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
            .padding(.top, 8)

            VStack(spacing: 10) {
                SidebarMetric(title: "Network", value: "Base", systemImage: "bolt.horizontal.circle")
                SidebarMetric(title: "Data", value: "Surf", systemImage: "waveform.path.ecg")
                SidebarMetric(title: "Signer", value: "Locked", systemImage: "lock.shield")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("示例")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)

                ForEach(QueryExample.defaults) { example in
                    Button {
                        store.useExample(example)
                    } label: {
                        HStack {
                            Image(systemName: example.kind.systemImage)
                                .foregroundStyle(AppTheme.accent)
                            Text(example.title)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("对话历史")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)

                if store.chatSessions.isEmpty {
                    Text("暂无历史")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(store.chatSessions) { session in
                                Button {
                                    store.selectChatSession(session)
                                } label: {
                                    ChatSessionRow(
                                        session: session,
                                        isActive: session.id == store.activeChatSessionID
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color.white.opacity(0.55))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1)
        }
    }
}

private struct SidebarMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.cyan)
                .frame(width: 20)
            Text(title)
                .foregroundStyle(AppTheme.mutedText)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ChatSessionRow: View {
    let session: ContextChatSession
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(isActive ? AppTheme.accent : AppTheme.border)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Text(session.subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? AppTheme.accent.opacity(0.16) : AppTheme.panelSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActive ? AppTheme.accent.opacity(0.45) : AppTheme.border, lineWidth: 1)
        )
    }
}
