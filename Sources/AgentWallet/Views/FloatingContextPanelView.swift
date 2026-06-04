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

    private var walletActionLayoutToken: String {
        [
            store.hasFloatingWalletAction ? "1" : "0",
            store.isBuildingFloatingWalletAction ? "1" : "0",
            store.floatingWalletIntent?.id.uuidString ?? "",
            store.swapTokenCandidates.map(\.id).joined(separator: ","),
            store.selectedSwapTokenCandidate?.id ?? "",
            store.isResolvingSwapTokenCandidates ? "1" : "0",
            store.transferPlan?.id.uuidString ?? "",
            store.tradePlan?.id.uuidString ?? "",
            store.floatingWalletActionStatusMessage ?? "",
            store.floatingWalletActionErrorMessage ?? ""
        ].joined(separator: "|")
    }

    private var hasScrollableContent: Bool {
        store.isLoadingContextDetails
            || store.contextDetailErrorMessage != nil
            || store.currentContextSnapshot != nil
            || !store.chatMessages.isEmpty
            || store.hasFloatingWalletAction
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

        if store.hasFloatingWalletAction {
            height += 280
        }

        return min(max(height, 80), 370)
    }

    var body: some View {
        panelContent
            .onAppear(perform: reportSize)
            .onChange(of: store.chatMessages.count) { reportSize() }
            .onChange(of: store.chatQuestion) { reportSize() }
            .onChange(of: store.chatSessions.count) { reportSize() }
            .onChange(of: store.activeChatSessionID) { reportSize() }
            .onChange(of: store.isLoadingContextDetails) { reportSize() }
            .onChange(of: store.contextDetailErrorMessage) { reportSize() }
            .onChange(of: store.currentContextSnapshot?.id) { reportSize() }
            .onChange(of: store.isAnsweringQuestion) { reportSize() }
            .onChange(of: walletActionLayoutToken) { reportSize() }
    }

    private var panelContent: some View {
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
        .foregroundStyle(AppTheme.primaryText)
        .environment(\.colorScheme, .light)
        .tint(AppTheme.accent)
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

                        if store.hasFloatingWalletAction {
                            FloatingWalletActionSection(store: store)
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
                Text("正在读取 EVM / Surf 详情")
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
                .foregroundStyle(AppTheme.primaryText)
                .font(.callout)
                .colorScheme(.light)
                .tint(AppTheme.accent)
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

private struct FloatingWalletActionSection: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("钱包动作", systemImage: "bolt.shield")
                    .font(.callout.weight(.semibold))
                Spacer()
                if let intent = store.floatingWalletIntent {
                    Text(intent.action.title)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(AppTheme.cyan)
                }
            }

            if let intent = store.floatingWalletIntent {
                FloatingIntentOverview(intent: intent)
            }

            if store.isBuildingFloatingWalletAction {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(store.isResolvingSwapTokenCandidates ? "正在查询候选和流动性" : "正在准备确认单")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }

            if let intent = store.floatingWalletIntent,
               !intent.missingFields.isEmpty {
                Label("缺少：\(intent.missingFieldsText)", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !store.swapTokenCandidates.isEmpty {
                FloatingTokenCandidateList(store: store, candidates: store.swapTokenCandidates)
            }

            if store.floatingWalletIntent?.action == .swap,
               let plan = store.tradePlan {
                FloatingSwapConfirmationCard(store: store, plan: plan)
            }

            if let plan = store.transferPlan {
                FloatingTransferConfirmationCard(store: store, plan: plan)
            }

            if let message = store.tradeStatusMessage,
               store.floatingWalletIntent?.action == .swap {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .textSelection(.enabled)
            }

            if let message = store.floatingWalletActionStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .textSelection(.enabled)
            }

            if let message = store.tradeErrorMessage,
               store.floatingWalletIntent?.action == .swap {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            if let message = store.floatingWalletActionErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

private struct FloatingIntentOverview: View {
    let intent: WalletIntentDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FloatingIntentRow(label: "链", value: intent.chain.displayName)
            FloatingIntentRow(label: "金额", value: "\(intent.spendAmount.isEmpty ? "待补充" : intent.spendAmount) \(intent.spendAsset.symbol)")
            if intent.action == .swap {
                let target = intent.targetAddress.isEmpty
                    ? (intent.targetQuery.isEmpty ? "待补充" : "\(intent.targetQuery)（待选合约）")
                    : JSONPrettyPrinter.shortAddress(intent.targetAddress)
                FloatingIntentRow(label: "目标", value: target)
            }
            if intent.action == .transfer {
                FloatingIntentRow(label: "收款", value: intent.recipientAddress.isEmpty ? "待补充" : JSONPrettyPrinter.shortAddress(intent.recipientAddress))
            }
        }
        .padding(10)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct FloatingTokenCandidateList: View {
    @ObservedObject var store: AppStore
    let candidates: [UniswapTokenCandidate]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Uniswap 候选合约", systemImage: "list.bullet.rectangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)

            ForEach(candidates) { candidate in
                FloatingTokenCandidateRow(
                    store: store,
                    candidate: candidate,
                    isSelected: candidate.id == store.selectedSwapTokenCandidate?.id
                )
            }
        }
        .padding(10)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct FloatingTokenCandidateRow: View {
    @ObservedObject var store: AppStore
    let candidate: UniswapTokenCandidate
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: riskIcon)
                    .foregroundStyle(riskColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(candidate.symbol) · \(candidate.name)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)

                    Text("\(candidate.shortAddress) · \(candidate.matchReason)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(AppTheme.mutedText)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)

                Button {
                    Task {
                        await store.selectSwapTokenCandidate(candidate)
                    }
                } label: {
                    Label(isSelected ? "已选择" : "选择", systemImage: isSelected ? "checkmark" : "target")
                }
                .buttonStyle(ProductButtonStyle(prominent: candidate.canSelectForSwap && candidate.riskLevel.rawValue <= ContractRiskLevel.medium.rawValue))
                .disabled(!candidate.canSelectForSwap || store.isBuildingTradePlan)
            }

            VStack(alignment: .leading, spacing: 5) {
                FloatingIntentRow(label: "状态", value: candidate.status.title)
                FloatingIntentRow(label: "合约风险", value: candidate.riskLevel.title)

                if let safetyLevel = candidate.safetyLevel {
                    FloatingIntentRow(label: "安全等级", value: safetyLevel)
                }

                if let isSpam = candidate.isSpam {
                    FloatingIntentRow(label: "Spam", value: isSpam ? "是" : "否")
                }

                if !candidate.riskReasons.isEmpty {
                    FloatingIntentRow(label: "风险原因", value: candidate.riskReasons.prefix(3).joined(separator: "\n"))
                }

                if let outputAmount = candidate.outputAmount {
                    FloatingIntentRow(label: "预计收到", value: outputAmount)
                }

                if let gasFeeUSD = candidate.gasFeeUSD {
                    FloatingIntentRow(label: "Gas", value: "$\(gasFeeUSD)")
                }

                if let priceImpact = candidate.priceImpact {
                    FloatingIntentRow(label: "价格影响", value: String(format: "%.2f%%", priceImpact))
                }

                if let routeSummary = candidate.routeSummary {
                    FloatingIntentRow(label: "路由", value: routeSummary)
                }

                if let liquiditySummary = candidate.liquiditySummary {
                    FloatingIntentRow(label: "流动性", value: liquiditySummary)
                }

                if let quoteError = candidate.quoteError {
                    FloatingIntentRow(label: "报价", value: quoteError)
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? AppTheme.accent.opacity(0.13) : AppTheme.panelSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? AppTheme.accent.opacity(0.55) : AppTheme.border, lineWidth: 1)
        )
    }

    private var riskIcon: String {
        switch candidate.riskLevel {
        case .low:
            return "checkmark.seal.fill"
        case .medium:
            return "exclamationmark.shield.fill"
        case .high:
            return "exclamationmark.triangle.fill"
        case .blocked:
            return "xmark.octagon.fill"
        }
    }

    private var riskColor: Color {
        switch candidate.riskLevel {
        case .low:
            return AppTheme.accent
        case .medium:
            return .orange
        case .high:
            return AppTheme.rose
        case .blocked:
            return .red
        }
    }
}

private struct FloatingSwapConfirmationCard: View {
    @ObservedObject var store: AppStore
    let plan: UniswapTradePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Uniswap 确认单", systemImage: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                Spacer()
                Text(plan.routing)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(AppTheme.mutedText)
            }

            VStack(alignment: .leading, spacing: 7) {
                FloatingIntentRow(label: "支付", value: "\(plan.inputAmount) \(plan.inputToken.symbol)")
                FloatingIntentRow(label: "预计收到", value: plan.outputAmount ?? "等待返回")
                FloatingIntentRow(label: "Gas", value: plan.gasFee ?? "未返回")
                FloatingIntentRow(label: "授权", value: plan.needsApproval ? "需要先授权" : "无需额外授权")
                FloatingIntentRow(label: "有效期", value: plan.quoteFreshnessStatus)
                if let swap = plan.swapTransaction {
                    FloatingIntentRow(label: "Swap To", value: swap.shortTo)
                }
            }

            FloatingSafetyChecklist(checks: plan.safetyChecks)
            FloatingSwapSigningGate(store: store, plan: plan)
        }
        .padding(10)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct FloatingTransferConfirmationCard: View {
    @ObservedObject var store: AppStore
    let plan: TransferPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("转账确认单", systemImage: "arrow.up.right.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 7) {
                FloatingIntentRow(label: "链", value: plan.chain.displayName)
                FloatingIntentRow(label: "收款", value: JSONPrettyPrinter.shortAddress(plan.recipientAddress))
                FloatingIntentRow(label: "资产", value: "\(plan.amount) \(plan.asset.symbol)")
                FloatingIntentRow(label: "最小单位", value: plan.amountBaseUnits)
                FloatingIntentRow(label: "交易目标", value: plan.transaction.shortTo)
                FloatingIntentRow(label: "有效期", value: plan.freshnessStatus)
            }

            FloatingSafetyChecklist(checks: plan.safetyChecks)
            FloatingTransferSigningGate(store: store, plan: plan)
        }
        .padding(10)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct FloatingIntentRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(AppTheme.primaryText)
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FloatingSafetyChecklist: View {
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

private struct FloatingSwapSigningGate: View {
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

            FloatingSigningGateLayout(
                title: "签名前确认",
                expectedCode: expectedCode,
                text: $store.tradeConfirmationText,
                confirmationMatches: confirmationMatches,
                buttonTitle: plan.needsApproval ? "本机签名授权" : "本机签名兑换",
                buttonIcon: "signature",
                isSigning: store.isSigningTrade,
                isDisabled: !canSign,
                status: statusText(isFresh: isFresh, expectedCode: expectedCode)
            ) {
                Task {
                    await store.signAndBroadcastTrade()
                }
            }
        }
    }

    private func statusText(isFresh: Bool, expectedCode: String) -> String {
        if !isFresh {
            return "报价已过期，请重新生成后再签名。"
        }

        if plan.needsApproval {
            return "输入钱包后 4 位 \(expectedCode) 后，只会签名授权。"
        }

        return "输入钱包后 4 位 \(expectedCode) 后才会本机签名。"
    }
}

private struct FloatingTransferSigningGate: View {
    @ObservedObject var store: AppStore
    let plan: TransferPlan

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let isFresh = plan.isFresh(at: context.date)
            let expectedCode = plan.confirmationCode
            let confirmationMatches = store.transferConfirmationText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() == expectedCode
            let canSign = isFresh && confirmationMatches && !store.isSigningTransfer

            FloatingSigningGateLayout(
                title: "收款地址确认",
                expectedCode: expectedCode,
                text: $store.transferConfirmationText,
                confirmationMatches: confirmationMatches,
                buttonTitle: "本机签名发送",
                buttonIcon: "paperplane",
                isSigning: store.isSigningTransfer,
                isDisabled: !canSign,
                status: statusText(isFresh: isFresh, expectedCode: expectedCode)
            ) {
                Task {
                    await store.signAndBroadcastTransfer()
                }
            }
        }
    }

    private func statusText(isFresh: Bool, expectedCode: String) -> String {
        if !isFresh {
            return "确认单已过期，请重新生成后再签名。"
        }

        return "输入收款地址后 4 位 \(expectedCode) 后才会本机签名。"
    }
}

private struct FloatingSigningGateLayout: View {
    let title: String
    let expectedCode: String
    @Binding var text: String
    let confirmationMatches: Bool
    let buttonTitle: String
    let buttonIcon: String
    let isSigning: Bool
    let isDisabled: Bool
    let status: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)

                    TextField(expectedCode, text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(AppTheme.primaryText)
                        .colorScheme(.light)
                        .tint(AppTheme.accent)
                        .padding(10)
                        .background(AppTheme.panelSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(confirmationMatches ? AppTheme.accent.opacity(0.55) : AppTheme.border, lineWidth: 1)
                        )
                }
                .frame(width: 132)

                Button(action: action) {
                    if isSigning {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 104)
                    } else {
                        Label(buttonTitle, systemImage: buttonIcon)
                    }
                }
                .buttonStyle(ProductButtonStyle(prominent: true))
                .disabled(isDisabled)

                Text(status)
                    .font(.caption)
                    .foregroundStyle(status.contains("过期") ? .orange : AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
