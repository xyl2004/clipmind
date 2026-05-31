import SwiftUI

struct TradeIntentView: View {
    @ObservedObject var store: AppStore
    let query: String
    @State private var mode: TradeMode = .swap

    private var chain: ChainProfile {
        store.selectedTradeChain
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            externalWalletPanel

            if mode == .swap {
                swapComposer
                confirmationPanel
            } else {
                transferPlaceholder
            }
        }
        .productPanel(padding: 16)
    }

    private var header: some View {
        HStack {
            Label("交易确认单", systemImage: "checkmark.shield")
                .font(.headline)

            Spacer()

            Picker("模式", selection: $mode) {
                ForEach(TradeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .colorScheme(.light)
        }
    }

    private var externalWalletPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("外部钱包", systemImage: "wallet.pass")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(store.signerStatusTitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(store.externalWalletSession == nil ? AppTheme.mutedText : AppTheme.accent)
            }

            HStack(spacing: 10) {
                TextField("0x 钱包地址，用于 Uniswap 报价和外部签名", text: $store.tradeDraft.walletAddress)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(AppTheme.primaryText)
                    .colorScheme(.light)
                    .tint(AppTheme.accent)
                    .padding(10)
                    .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )

                Button {
                    if store.externalWalletSession == nil {
                        store.connectExternalWallet()
                    } else {
                        store.disconnectExternalWallet()
                    }
                } label: {
                    Label(store.externalWalletSession == nil ? "连接" : "断开", systemImage: store.externalWalletSession == nil ? "link" : "xmark.circle")
                }
                .buttonStyle(ProductButtonStyle())
            }

            Text(store.walletStatusMessage ?? "第一版不保存私钥。交易会发送到外部钱包确认签名。")
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)
        }
        .padding(12)
        .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    private var swapComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TradeField(title: "链", value: chain.displayName, systemImage: "link")
                TradeField(title: "支付资产", value: store.tradeDraft.spendTokenSymbol, systemImage: "creditcard")
                TradeField(title: "目标", value: JSONPrettyPrinter.shortAddress(store.tradeDraft.tokenAddress.isEmpty ? query : store.tradeDraft.tokenAddress), systemImage: "seal")
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("支付金额")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                    TextField("20", text: $store.tradeDraft.spendAmount)
                        .textFieldStyle(.plain)
                        .foregroundStyle(AppTheme.primaryText)
                        .colorScheme(.light)
                        .tint(AppTheme.accent)
                        .padding(10)
                        .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                }
                .frame(width: 120)

                VStack(alignment: .leading, spacing: 6) {
                    Text("目标代币地址")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                    TextField("0x token", text: $store.tradeDraft.tokenAddress)
                        .textFieldStyle(.plain)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(AppTheme.primaryText)
                        .colorScheme(.light)
                        .tint(AppTheme.accent)
                        .padding(10)
                        .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("滑点")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                    Text("\(store.tradeDraft.slippage, specifier: "%.1f")%")
                        .font(.system(.callout, design: .monospaced))
                        .frame(width: 52, alignment: .trailing)
                    Slider(value: $store.tradeDraft.slippage, in: 0.1...5.0, step: 0.1)
                        .frame(width: 140)
                }

                Button {
                    Task {
                        await store.buildTradePlan()
                    }
                } label: {
                    if store.isBuildingTradePlan {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("生成报价", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(ProductButtonStyle(prominent: true))
                .disabled(store.isBuildingTradePlan)
            }
        }
    }

    @ViewBuilder
    private var confirmationPanel: some View {
        if let plan = store.tradePlan {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Uniswap 确认单", systemImage: "doc.text.magnifyingglass")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(plan.routing)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppTheme.mutedText)
                }

                VStack(alignment: .leading, spacing: 8) {
                    IntentRow(label: "链", value: plan.chain.displayName)
                    IntentRow(label: "支付", value: "\(plan.inputAmount) \(plan.inputToken.symbol)")
                    IntentRow(label: "支付单位", value: plan.inputAmountBaseUnits)
                    IntentRow(label: "预计收到", value: plan.outputAmount ?? "等待 Uniswap 返回")
                    IntentRow(label: "Gas 预估", value: plan.gasFee ?? "未返回")
                    IntentRow(label: "授权", value: plan.needsApproval ? "需要先授权" : "无需额外授权")
                    if let swap = plan.swapTransaction {
                        IntentRow(label: "Swap To", value: swap.shortTo)
                    }
                }

                HStack {
                    Button {
                        Task {
                            await store.sendTradeToExternalWallet()
                        }
                    } label: {
                        Label("发送到外部钱包", systemImage: "paperplane")
                    }
                    .buttonStyle(ProductButtonStyle(prominent: true))

                    Text("AI 不会签名。请只在外部钱包中确认你看懂的交易。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
            .padding(12)
            .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
        }

        if let message = store.tradeStatusMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)
                .textSelection(.enabled)
        }

        if let message = store.tradeErrorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }

    private var transferPlaceholder: some View {
        Text("转账会复用同一个外部钱包确认边界；当前版本先实现 Uniswap 同链 swap。")
            .font(.caption)
            .foregroundStyle(AppTheme.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TradeField: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                Text(value)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct IntentRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(AppTheme.primaryText)
                .textSelection(.enabled)
        }
    }
}

private enum TradeMode: String, CaseIterable, Identifiable {
    case swap
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swap:
            "兑换"
        case .transfer:
            "转账"
        }
    }
}
