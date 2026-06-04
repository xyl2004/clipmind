import SwiftUI

struct TradeIntentView: View {
    @ObservedObject var store: AppStore
    let query: String

    private var chain: ChainProfile {
        store.selectedTradeChain
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            swapComposer
            confirmationPanel
        }
        .productPanel(padding: 16)
    }

    private var header: some View {
        HStack {
            Label("交易确认单", systemImage: "checkmark.shield")
                .font(.headline)

            Spacer()

            Label(store.localWalletAccount == nil ? "请先在左侧栏创建或导入钱包" : store.signerStatusTitle, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(store.localWalletAccount == nil ? AppTheme.mutedText : AppTheme.accent)
        }
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
                    IntentRow(label: "报价有效期", value: plan.quoteFreshnessStatus)
                    if let swap = plan.swapTransaction {
                        IntentRow(label: "Swap To", value: swap.shortTo)
                    }
                }

                TradeSafetyChecklist(checks: plan.safetyChecks)
                TradeSigningGate(store: store, plan: plan)
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

private struct TradeSafetyChecklist: View {
    let checks: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("安全检查", systemImage: "checkmark.seal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)

            ForEach(checks, id: \.self) { check in
                Label(check, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct TradeSigningGate: View {
    @ObservedObject var store: AppStore
    let plan: UniswapTradePlan

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let isFresh = plan.isFresh(at: context.date)
            let expectedCode = plan.confirmationCode
            let confirmationMatches = store.tradeConfirmationText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() == expectedCode
            let canSign = isFresh && confirmationMatches && !store.isSigningTrade

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("签名前确认")
                            .font(.caption)
                            .foregroundStyle(AppTheme.mutedText)

                        TextField(expectedCode, text: $store.tradeConfirmationText)
                            .textFieldStyle(.plain)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(AppTheme.primaryText)
                            .colorScheme(.light)
                            .tint(AppTheme.accent)
                            .padding(10)
                            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(confirmationMatches ? AppTheme.accent.opacity(0.55) : AppTheme.border, lineWidth: 1)
                            )
                    }
                    .frame(width: 140)

                    Button {
                        Task {
                            await store.signAndBroadcastTrade()
                        }
                    } label: {
                        if store.isSigningTrade {
                            ProgressView()
                                .controlSize(.small)
                                .frame(minWidth: 112)
                        } else {
                            Label(plan.needsApproval ? "本机签名授权" : "本机签名兑换", systemImage: "signature")
                        }
                    }
                    .buttonStyle(ProductButtonStyle(prominent: true))
                    .disabled(!canSign)

                    Text(statusText(isFresh: isFresh, expectedCode: expectedCode))
                        .font(.caption)
                        .foregroundStyle(isFresh ? AppTheme.mutedText : .orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func statusText(isFresh: Bool, expectedCode: String) -> String {
        if !isFresh {
            return "报价已过期，请重新生成后再签名。"
        }

        if plan.needsApproval {
            return "输入钱包后 4 位 \(expectedCode) 后，只会签名授权；授权上链后需重新生成报价再兑换。"
        }

        return "输入钱包后 4 位 \(expectedCode) 后才会本机签名。AI 不会自动签名或广播。"
    }
}
