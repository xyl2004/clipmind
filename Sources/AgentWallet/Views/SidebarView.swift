import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: AppStore
    @State private var showsServices = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusStrip

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SidebarSection("本地钱包") {
                        WalletSidebarSection(store: store)
                    }

                    SidebarDisclosureSection(title: "服务连接", isExpanded: $showsServices) {
                        SidebarServiceSection(store: store)
                    }

                    SidebarSection("交易历史") {
                        TradeHistorySidebarSection(store: store)
                    }

                    SidebarSection("对话历史") {
                        ChatHistorySidebarSection(store: store)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.50))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(AppTheme.primaryText, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("ClipMind")
                    .font(.system(size: 21, weight: .bold))
                Text("EVM Multi-chain Agent")
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var statusStrip: some View {
        HStack(spacing: 6) {
            SidebarStatusChip(title: "EVM", systemImage: "link")
            SidebarStatusChip(title: "Surf", systemImage: "waveform.path.ecg")
            SidebarStatusChip(
                title: store.localWalletAccount == nil ? "未签名" : "已签名",
                systemImage: "lock.shield"
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            SidebarFooterMetric(title: "Network", value: "EVM")
            SidebarFooterMetric(title: "Signer", value: store.signerStatusTitle)
        }
        .padding(.top, 2)
    }
}

private struct WalletSidebarSection: View {
    @ObservedObject var store: AppStore
    @State private var isConfirmingDeletion = false
    @State private var isConfirmingPrivateKeyExport = false
    @State private var deleteConfirmationText = ""
    @State private var exportConfirmationText = ""
    @State private var showsWalletAssets = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let account = store.localWalletAccount {
                Button {
                    showsWalletAssets.toggle()
                    if showsWalletAssets, store.walletChainAssets.isEmpty {
                        Task {
                            await store.refreshSupportedWalletAssets()
                        }
                    }
                } label: {
                    WalletConnectedRow(
                        account: account,
                        chain: store.selectedTradeChain,
                        balance: store.walletBalance,
                        isRefreshingBalance: store.isRefreshingWalletBalance || store.isRefreshingWalletAssets,
                        balanceErrorMessage: store.walletBalanceErrorMessage,
                        isExpanded: showsWalletAssets
                    )
                }
                .buttonStyle(.plain)

                if showsWalletAssets {
                    WalletAssetsPanel(store: store)
                }

                if isConfirmingDeletion {
                    DeleteWalletConfirmationCard(
                        account: account,
                        confirmationText: $deleteConfirmationText,
                        onCancel: resetDeletionConfirmation
                    ) {
                        store.deleteLocalWallet()
                        if store.localWalletAccount == nil {
                            resetDeletionConfirmation()
                        }
                    }
                } else if isConfirmingPrivateKeyExport || store.exportedPrivateKey != nil {
                    ExportPrivateKeyCard(
                        account: account,
                        confirmationText: $exportConfirmationText,
                        privateKeyHex: store.exportedPrivateKey,
                        onCancel: resetExportConfirmation,
                        onReveal: store.revealLocalWalletPrivateKey,
                        onCopyAndHide: {
                            store.copyExportedPrivateKeyAndHide()
                            resetExportConfirmation()
                        },
                        onHide: {
                            store.hideExportedPrivateKey()
                            resetExportConfirmation()
                        }
                    )
                } else {
                    HStack(spacing: 8) {
                        Button {
                            store.copyLocalWalletAddress()
                        } label: {
                            Label("复制地址", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ProductButtonStyle())

                        Button {
                            Task {
                                await store.refreshSupportedWalletAssets()
                            }
                        } label: {
                            if store.isRefreshingWalletBalance || store.isRefreshingWalletAssets {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("刷新资产", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(ProductButtonStyle())
                        .disabled(store.isRefreshingWalletBalance || store.isRefreshingWalletAssets)
                    }

                    Button {
                        resetDeletionConfirmation()
                        exportConfirmationText = ""
                        isConfirmingPrivateKeyExport = true
                    } label: {
                        Label("导出私钥", systemImage: "key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ProductButtonStyle())

                    Button(role: .destructive) {
                        resetExportConfirmation()
                        deleteConfirmationText = ""
                        isConfirmingDeletion = true
                    } label: {
                        Label("删除私钥", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ProductButtonStyle())

                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(AppTheme.mutedText)
                        Text("Gas 是交易手续费余额；刷新会读取支持链 Gas 和代币余额，不会生成新钱包。")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                SidebarEmptyRow(
                    title: "未创建钱包",
                    subtitle: "用于本机签名，私钥保存在 Keychain。",
                    systemImage: "lock.shield"
                )

                SecureField("导入 0x 私钥", text: $store.privateKeyDraft)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(AppTheme.primaryText)
                    .colorScheme(.light)
                    .tint(AppTheme.accent)
                    .padding(9)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 8) {
                    Button {
                        store.createLocalWallet()
                    } label: {
                        Label("创建", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ProductButtonStyle(prominent: true))

                    Button {
                        store.importLocalWallet()
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ProductButtonStyle())
                    .disabled(store.privateKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Button {
                    store.unlockLocalWallet()
                } label: {
                    Label("解锁已有钱包", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProductButtonStyle())

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "shield")
                        .foregroundStyle(AppTheme.mutedText)
                    Text("如果已有本地钱包，创建或导入会被阻止，避免覆盖 Keychain 私钥。")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(store.walletStatusMessage ?? "私钥保存在 macOS Keychain，签名前需要手动确认。")
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)
                .lineLimit(3)
        }
    }

    private func resetDeletionConfirmation() {
        isConfirmingDeletion = false
        deleteConfirmationText = ""
    }

    private func resetExportConfirmation() {
        isConfirmingPrivateKeyExport = false
        exportConfirmationText = ""
    }
}

private struct DeleteWalletConfirmationCard: View {
    let account: LocalWalletAccount
    @Binding var confirmationText: String
    let onCancel: () -> Void
    let onDelete: () -> Void

    private var requiredSuffix: String {
        String(account.address.suffix(4)).uppercased()
    }

    private var canDelete: Bool {
        confirmationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() == requiredSuffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 24)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("确认删除私钥")
                        .font(.caption.weight(.semibold))
                    Text("这会从 Keychain 永久移除当前本地钱包。请确认已备份私钥，且地址内资产已转出。")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("输入地址后 4 位 \(requiredSuffix) 继续")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.mutedText)

            TextField(requiredSuffix, text: $confirmationText)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(AppTheme.primaryText)
                .colorScheme(.light)
                .tint(AppTheme.rose)
                .padding(9)
                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(canDelete ? AppTheme.rose.opacity(0.55) : AppTheme.border, lineWidth: 1)
                )

            HStack(spacing: 8) {
                Button {
                    onCancel()
                } label: {
                    Label("取消", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProductButtonStyle())

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("永久删除", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DestructiveSidebarButtonStyle())
                .disabled(!canDelete)
            }
        }
        .padding(10)
        .background(AppTheme.rose.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.rose.opacity(0.26), lineWidth: 1)
        )
    }
}

private struct ExportPrivateKeyCard: View {
    let account: LocalWalletAccount
    @Binding var confirmationText: String
    let privateKeyHex: String?
    let onCancel: () -> Void
    let onReveal: () -> Void
    let onCopyAndHide: () -> Void
    let onHide: () -> Void

    private var requiredSuffix: String {
        String(account.address.suffix(4)).uppercased()
    }

    private var canReveal: Bool {
        confirmationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() == requiredSuffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "key.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 24)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(privateKeyHex == nil ? "确认导出私钥" : "私钥已显示")
                        .font(.caption.weight(.semibold))
                    Text("任何拿到私钥的人都可以转走该地址资产。只在离线或可信环境保存。")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let privateKeyHex {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(privateKeyHex)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppTheme.primaryText)
                        .textSelection(.enabled)
                        .padding(9)
                }
                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.orange.opacity(0.34), lineWidth: 1)
                )

                HStack(spacing: 8) {
                    Button {
                        onHide()
                    } label: {
                        Label("隐藏", systemImage: "eye.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ProductButtonStyle())

                    Button {
                        onCopyAndHide()
                    } label: {
                        Label("复制并隐藏", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ProductButtonStyle(prominent: true))
                }
            } else {
                Text("输入地址后 4 位 \(requiredSuffix) 继续")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)

                TextField(requiredSuffix, text: $confirmationText)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(AppTheme.primaryText)
                    .colorScheme(.light)
                    .tint(.orange)
                    .padding(9)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(canReveal ? .orange.opacity(0.55) : AppTheme.border, lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    Button {
                        onCancel()
                    } label: {
                        Label("取消", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ProductButtonStyle())

                    Button {
                        onReveal()
                    } label: {
                        Label("显示私钥", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ProductButtonStyle(prominent: true))
                    .disabled(!canReveal)
                }
            }
        }
        .padding(10)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.orange.opacity(0.26), lineWidth: 1)
        )
    }
}

private struct SidebarServiceSection: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarServiceRow(
                title: "B.AI",
                subtitle: "中文解释",
                placeholder: "B.AI API Key",
                isEnabled: store.hasLLMAPIKey,
                draft: $store.apiKeyDraft,
                status: store.apiKeyStatusMessage,
                onSave: store.saveAPIKey
            )

            SidebarServiceRow(
                title: "Surf",
                subtitle: "价格和链上数据",
                placeholder: "Surf API Key",
                isEnabled: store.hasSurfAPIKey,
                draft: $store.surfAPIKeyDraft,
                status: store.surfAPIKeyStatusMessage,
                onSave: store.saveSurfAPIKey
            )

            SidebarServiceRow(
                title: "Uniswap",
                subtitle: "报价和交易确认",
                placeholder: "Uniswap API Key",
                isEnabled: store.hasUniswapAPIKey,
                draft: $store.uniswapAPIKeyDraft,
                status: store.uniswapAPIKeyStatusMessage,
                onSave: store.saveUniswapAPIKey
            )

            SepoliaDryRunRow(store: store)
        }
    }
}

private struct SepoliaDryRunRow: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.cyan)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Sepolia 干跑")
                        .font(.caption.weight(.semibold))
                    Text("只生成测试网报价和 calldata")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedText)
                }

                Spacer(minLength: 0)
            }

            Button {
                Task {
                    await store.runSepoliaDryRun()
                }
            } label: {
                if store.isRunningSepoliaDryRun {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("测试 ETH → WETH", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(ProductButtonStyle())
            .disabled(store.isRunningSepoliaDryRun || !store.hasUniswapAPIKey)

            if let message = store.sepoliaDryRunStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.contains("成功") ? AppTheme.mutedText : .orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SidebarServiceRow: View {
    let title: String
    let subtitle: String
    let placeholder: String
    let isEnabled: Bool
    @Binding var draft: String
    let status: String?
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "key")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isEnabled ? AppTheme.accent : AppTheme.mutedText)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedText)
                }

                Spacer(minLength: 0)

                Text(isEnabled ? "已启用" : "待配置")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isEnabled ? AppTheme.accent : AppTheme.mutedText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppTheme.panelSoft, in: Capsule())
            }

            HStack(spacing: 8) {
                SecureField(isEnabled ? "更新 \(title) API Key" : placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .foregroundStyle(AppTheme.primaryText)
                    .colorScheme(.light)
                    .tint(AppTheme.accent)
                    .padding(8)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    onSave()
                } label: {
                    Image(systemName: "checkmark")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(ProductButtonStyle())
                .help("保存 \(title) API Key")
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(2)
            }
        }
    }
}

private struct TradeHistorySidebarSection: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.tradeHistory.isEmpty {
                SidebarEmptyRow(
                    title: "暂无交易",
                    subtitle: "广播后的交易会显示在这里。",
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(store.tradeHistory.prefix(8)) { item in
                        TradeHistoryRow(item: item)
                    }
                }
            }
        }
    }
}

private struct TradeHistoryRow: View {
    let item: TradeHistoryItem

    var body: some View {
        Group {
            if let explorerURL = item.explorerURL {
                Link(destination: explorerURL) {
                    content
                }
            } else {
                content
            }
        }
        .buttonStyle(.plain)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.action)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Text(item.chain.shortName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            Text(item.shortHash)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(AppTheme.mutedText)
            Text(item.createdAt, style: .time)
                .font(.caption2)
                .foregroundStyle(AppTheme.mutedText)
        }
    }
}

private struct ChatHistorySidebarSection: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.chatSessions.isEmpty {
                SidebarEmptyRow(
                    title: "暂无对话",
                    subtitle: "选中文字后会创建新的上下文。",
                    systemImage: "text.bubble"
                )
            } else {
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
}

private struct SidebarSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SidebarSectionTitle(title)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarDisclosureSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let content: Content

    init(title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, 8)
        } label: {
            SidebarSectionTitle(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.mutedText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.mutedText)
            .tracking(0.6)
    }
}

private struct WalletConnectedRow: View {
    let account: LocalWalletAccount
    let chain: ChainProfile
    let balance: LocalWalletBalance?
    let isRefreshingBalance: Bool
    let balanceErrorMessage: String?
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("本地钱包已就绪")
                        .font(.caption.weight(.semibold))
                    Text(account.address)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(chain.shortName) 交易费")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedText)
                    Text(balanceText)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(balance?.hasGas == false ? AppTheme.rose : AppTheme.primaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isRefreshingBalance {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(balanceUpdatedText)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }

            Text("用于支付 \(chain.displayName) 交易 Gas，不代表全部资产。")
                .font(.caption2)
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            if let balanceErrorMessage {
                Label(balanceErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    private var balanceText: String {
        guard let balance, balance.chain.id == chain.id else {
            return "未刷新"
        }

        return balance.formattedNativeBalance
    }

    private var balanceUpdatedText: String {
        guard let balance, balance.chain.id == chain.id else {
            return chain.displayName
        }

        return balance.updatedAt.formatted(date: .omitted, time: .shortened)
    }
}

private struct WalletAssetsPanel: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("支持链资产", systemImage: "square.stack.3d.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer(minLength: 0)

                if store.isRefreshingWalletAssets {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if store.walletChainAssets.isEmpty {
                SidebarEmptyRow(
                    title: store.isRefreshingWalletAssets ? "正在读取资产" : "尚未读取资产",
                    subtitle: "点击刷新资产，查看支持链上的 Gas 和代币余额。",
                    systemImage: "sparkle.magnifyingglass"
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(store.walletChainAssets) { assets in
                        WalletChainAssetsRow(assets: assets)
                    }
                }
            }

            if let message = store.walletAssetsErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

private struct WalletChainAssetsRow: View {
    let assets: WalletChainAssets

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(assets.chain.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer(minLength: 0)

                Text(assets.assetSummary)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Gas")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 38, alignment: .leading)

                Text(assets.gasText)
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(assets.gasBalance?.hasGas == false ? AppTheme.rose : AppTheme.primaryText)
                    .lineLimit(1)
            }

            if let gasErrorMessage = assets.gasErrorMessage {
                Label(gasErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if assets.tokens.isEmpty {
                Text(assets.tokenErrorMessage ?? "未发现代币余额。")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(assets.tokens.prefix(5)) { token in
                        WalletTokenBalanceRow(token: token)
                    }

                    if assets.tokens.count > 5 {
                        Text("还有 \(assets.tokens.count - 5) 个代币未展开显示")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }
            }
        }
        .padding(9)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

private struct WalletTokenBalanceRow: View {
    let token: WalletTokenBalance

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(token.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                if let address = token.address {
                    Text(JSONPrettyPrinter.shortAddress(address))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppTheme.mutedText)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text(token.balance)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                if let usdValue = token.usdValue {
                    Text(usdValue)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct SidebarEmptyRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 24, height: 24)
                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText.opacity(0.82))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

private struct SidebarStatusChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppTheme.primaryText.opacity(0.74))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
    }
}

private struct SidebarFooterMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.mutedText)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DestructiveSidebarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.rose.opacity(isEnabled ? 0.95 : 0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? AppTheme.accent.opacity(0.16) : AppTheme.panelSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? AppTheme.accent.opacity(0.45) : AppTheme.border, lineWidth: 1)
        )
    }
}
