import AppKit
import BigInt
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var input: String = ""
    @Published var selectedKind: QueryKind = .auto
    @Published var selectedChainID: String = ChainFilter.automatic.id
    @Published var isLoading = false
    @Published var isExplaining = false
    @Published var result: ResearchSnapshot?
    @Published var aiExplanation: String?
    @Published var chatQuestion: String = ""
    @Published var chatMessages: [ContextChatMessage] = []
    @Published var chatSessions: [ContextChatSession] = []
    @Published var activeChatSessionID: ContextChatSession.ID?
    @Published var contextDetailSnapshot: ResearchSnapshot?
    @Published var isLoadingContextDetails = false
    @Published var contextDetailErrorMessage: String?
    @Published var isAnsweringQuestion = false
    @Published var errorMessage: String?
    @Published var llmErrorMessage: String?
    @Published var selectedTextMessage: String?
    @Published var apiKeyDraft: String = ""
    @Published var apiKeyStatusMessage: String?
    @Published var hasLLMAPIKey = CredentialStore.hasBAIAPIKey()
    @Published var uniswapAPIKeyDraft: String = ""
    @Published var uniswapAPIKeyStatusMessage: String?
    @Published var hasUniswapAPIKey = CredentialStore.hasUniswapAPIKey()
    @Published var isRunningSepoliaDryRun = false
    @Published var sepoliaDryRunStatusMessage: String?
    @Published var tradeDraft = TradeIntentDraft()
    @Published var localWalletAccount: LocalWalletAccount?
    @Published var walletBalance: LocalWalletBalance?
    @Published var isRefreshingWalletBalance = false
    @Published var walletBalanceErrorMessage: String?
    @Published var privateKeyDraft: String = ""
    @Published var walletStatusMessage: String?
    @Published var tradePlan: UniswapTradePlan?
    @Published var tradeConfirmationText: String = ""
    @Published var floatingWalletIntent: WalletIntentDraft?
    @Published var swapTokenCandidates: [UniswapTokenCandidate] = []
    @Published var selectedSwapTokenCandidate: UniswapTokenCandidate?
    @Published var transferPlan: TransferPlan?
    @Published var transferConfirmationText: String = ""
    @Published var floatingWalletActionStatusMessage: String?
    @Published var floatingWalletActionErrorMessage: String?
    @Published var isBuildingFloatingWalletAction = false
    @Published var isResolvingSwapTokenCandidates = false
    @Published var isBuildingTradePlan = false
    @Published var isSigningTrade = false
    @Published var isSigningTransfer = false
    @Published var tradeStatusMessage: String?
    @Published var tradeErrorMessage: String?
    @Published var tradeHistory: [TradeHistoryItem] = []

    private let surfClient = SurfClient()
    private let llmClient = LLMClient()
    private let tradeProvider = UniswapTradeProvider()
    private let localWalletClient = LocalWalletClient()
    private var selectedTextSourceRect: CGRect?

    init() {
        do {
            localWalletAccount = try localWalletClient.loadAccount()
            if localWalletAccount != nil {
                Task {
                    await refreshWalletBalance()
                }
            }
        } catch {
            walletStatusMessage = error.localizedDescription
        }
    }

    var effectiveKind: QueryKind {
        QueryClassifier.classify(input, preferredKind: selectedKind)
    }

    var selectedChainFilter: ChainFilter {
        ChainFilter.filter(for: selectedChainID)
    }

    var selectedTradeChain: ChainProfile {
        selectedChainFilter.profile ?? result?.chains.first ?? ChainRegistry.base
    }

    var signerStatusTitle: String {
        localWalletAccount?.shortAddress ?? "未创建"
    }

    var canSignCurrentTrade: Bool {
        guard let tradePlan,
              localWalletAccount != nil,
              !isSigningTrade,
              tradePlan.isFreshForSigning else {
            return false
        }

        return tradeConfirmationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() == tradePlan.confirmationCode
    }

    var canSignCurrentTransfer: Bool {
        guard let transferPlan,
              localWalletAccount != nil,
              !isSigningTransfer,
              transferPlan.isFreshForSigning else {
            return false
        }

        return transferConfirmationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() == transferPlan.confirmationCode
    }

    var hasFloatingWalletAction: Bool {
        floatingWalletIntent != nil
            || transferPlan != nil
            || floatingWalletActionStatusMessage != nil
            || floatingWalletActionErrorMessage != nil
            || isBuildingFloatingWalletAction
            || isResolvingSwapTokenCandidates
            || !swapTokenCandidates.isEmpty
            || (floatingWalletIntent?.action == .swap && tradePlan != nil)
    }

    var activeChatSession: ContextChatSession? {
        guard let activeChatSessionID else {
            return nil
        }

        return chatSessions.first { $0.id == activeChatSessionID }
    }

    var currentContextSnapshot: ResearchSnapshot? {
        let context = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if let contextDetailSnapshot, contextDetailSnapshot.query == context {
            return contextDetailSnapshot
        }

        if let result, result.query == context {
            return result
        }

        if let snapshot = activeChatSession?.surfSnapshot, snapshot.query == context {
            return snapshot
        }

        return nil
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.title.contains("AgentWallet") {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }

    func showFloatingChatPanel() {
        FloatingPanelController.shared.show(store: self, near: selectedTextSourceRect)
    }

    func configureGlobalHotKey() {
        GlobalHotKeyManager.shared.onHotKey = { [weak self] in
            self?.handleGlobalHotKey()
        }
        GlobalHotKeyManager.shared.register()
    }

    func handleGlobalHotKey() {
        let didCaptureText = captureSelectedText()
        showFloatingChatPanel()
        if didCaptureText {
            Task {
                await preloadContextDetailsIfUseful()
            }
        }
    }

    @discardableResult
    func captureClipboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            errorMessage = "剪贴板里没有可查询的文本。"
            return false
        }

        input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        resetAutomaticRecognition()
        selectedTextSourceRect = nil
        selectedTextMessage = "已读取剪贴板内容。"
        startNewContextSession(with: input)
        if QueryClassifier.isAddress(input) {
            tradeDraft.tokenAddress = input
        }
        return true
    }

    @discardableResult
    func captureSelectedText() -> Bool {
        switch SelectedTextReader.readSelectedText() {
        case .success(let text, let source, let sourceRect):
            input = text
            resetAutomaticRecognition()
            selectedTextSourceRect = sourceRect
            selectedTextMessage = source.label
            chatQuestion = ""
            startNewContextSession(with: text)
            errorMessage = nil
            if QueryClassifier.isAddress(input) {
                tradeDraft.tokenAddress = input
            }
            return true
        case .failure(let message):
            selectedTextMessage = nil
            errorMessage = message
            return false
        }
    }

    func saveAPIKey() {
        do {
            try CredentialStore.saveBAIAPIKey(apiKeyDraft)
            apiKeyDraft = ""
            hasLLMAPIKey = true
            apiKeyStatusMessage = "API Key 已保存到 Keychain。"
            llmErrorMessage = nil
        } catch {
            apiKeyStatusMessage = error.localizedDescription
        }
    }

    func saveUniswapAPIKey() {
        do {
            try CredentialStore.saveUniswapAPIKey(uniswapAPIKeyDraft)
            uniswapAPIKeyDraft = ""
            hasUniswapAPIKey = true
            uniswapAPIKeyStatusMessage = "Uniswap API Key 已保存到 Keychain。"
            sepoliaDryRunStatusMessage = nil
            tradeErrorMessage = nil
        } catch {
            uniswapAPIKeyStatusMessage = error.localizedDescription
        }
    }

    func runSepoliaDryRun() async {
        hasUniswapAPIKey = CredentialStore.hasUniswapAPIKey()
        isRunningSepoliaDryRun = true
        sepoliaDryRunStatusMessage = "正在测试 Sepolia ETH → WETH 报价。"
        guard let apiKey = CredentialStore.readUniswapAPIKeyWithoutPrompt() ?? CredentialStore.readUniswapAPIKey() else {
            sepoliaDryRunStatusMessage = "Sepolia 干跑需要 Uniswap API Key。请在上方“更新 Uniswap API Key”里保存后再测试。"
            isRunningSepoliaDryRun = false
            return
        }

        let draft = TradeIntentDraft(
            spendAmount: "0.001",
            spendTokenSymbol: "ETH",
            spendTokenAddress: TokenProfile.nativeETH.address,
            spendTokenDecimals: TokenProfile.nativeETH.decimals,
            tokenAddress: "0xfff9976782d46cc05630d1f6ebab18b2324d6b14",
            slippage: 1.0,
            recipientAddress: ""
        )
        let walletAddress = localWalletAccount?.address ?? "0x000000000000000000000000000000000000dEaD"

        do {
            let dryRunProvider = UniswapTradeProvider(apiKeyOverride: apiKey)
            let plan = try await dryRunProvider.buildSwapPlan(
                draft: draft,
                chain: ChainRegistry.ethereumSepolia,
                walletAddress: walletAddress
            )
            sepoliaDryRunStatusMessage = [
                "Sepolia 干跑成功：Uniswap 已返回待签名交易。",
                "支付：\(plan.inputAmount) \(plan.inputToken.symbol)",
                "预计收到：\(plan.outputAmount ?? "未返回")",
                "Swap To：\(plan.swapTransaction?.shortTo ?? "未返回")",
                "不会签名或广播。"
            ].joined(separator: "\n")
        } catch {
            sepoliaDryRunStatusMessage = "Sepolia 干跑失败：\(error.localizedDescription)"
        }

        isRunningSepoliaDryRun = false
    }

    func selectChain(_ filter: ChainFilter) {
        selectedChainID = filter.id
        let chain = filter.profile ?? ChainRegistry.base
        tradeDraft.applyDefaultSpendToken(for: chain)
        resetFloatingWalletAction(clearTradePlan: true)
        tradeErrorMessage = nil
        tradeStatusMessage = nil
        if localWalletAccount != nil {
            Task {
                await refreshWalletBalance()
            }
        }
    }

    func createLocalWallet() {
        do {
            let account = try localWalletClient.createWallet()
            localWalletAccount = account
            walletBalance = nil
            walletBalanceErrorMessage = nil
            resetFloatingWalletAction(clearTradePlan: true)
            privateKeyDraft = ""
            walletStatusMessage = "已创建本地钱包：\(account.shortAddress)。请先给该地址转入交易所需资产和 Gas。"
            tradeErrorMessage = nil
            Task {
                await refreshWalletBalance()
            }
        } catch {
            walletStatusMessage = error.localizedDescription
        }
    }

    func importLocalWallet() {
        do {
            let account = try localWalletClient.importWallet(privateKeyHex: privateKeyDraft)
            localWalletAccount = account
            walletBalance = nil
            walletBalanceErrorMessage = nil
            resetFloatingWalletAction(clearTradePlan: true)
            privateKeyDraft = ""
            walletStatusMessage = "已导入本地钱包：\(account.shortAddress)。私钥仅保存到 macOS Keychain。"
            tradeErrorMessage = nil
            Task {
                await refreshWalletBalance()
            }
        } catch {
            walletStatusMessage = error.localizedDescription
        }
    }

    func unlockLocalWallet() {
        do {
            guard let account = try localWalletClient.unlockWallet() else {
                walletStatusMessage = "当前没有可解锁的本地钱包。"
                return
            }

            localWalletAccount = account
            walletBalance = nil
            walletBalanceErrorMessage = nil
            resetFloatingWalletAction(clearTradePlan: true)
            walletStatusMessage = "已解锁本地钱包：\(account.shortAddress)。"
            Task {
                await refreshWalletBalance()
            }
        } catch {
            walletStatusMessage = error.localizedDescription
        }
    }

    func deleteLocalWallet() {
        do {
            try localWalletClient.deleteWallet()
            localWalletAccount = nil
            walletBalance = nil
            walletBalanceErrorMessage = nil
            privateKeyDraft = ""
            resetFloatingWalletAction(clearTradePlan: true)
            walletStatusMessage = "已从 Keychain 删除本地钱包私钥。"
        } catch {
            walletStatusMessage = error.localizedDescription
        }
    }

    func reloadLocalWallet() {
        do {
            localWalletAccount = try localWalletClient.loadAccount()
            if localWalletAccount == nil {
                walletBalance = nil
                walletBalanceErrorMessage = nil
                resetFloatingWalletAction(clearTradePlan: true)
                walletStatusMessage = "当前没有本地钱包。"
            } else {
                walletStatusMessage = "已读取本地钱包：\(localWalletAccount?.shortAddress ?? "")。"
                Task {
                    await refreshWalletBalance()
                }
            }
        } catch {
            walletStatusMessage = error.localizedDescription
        }
    }

    func copyLocalWalletAddress() {
        guard let address = localWalletAccount?.address else {
            walletStatusMessage = "当前没有可复制的钱包地址。"
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        walletStatusMessage = "钱包地址已复制。"
    }

    func refreshWalletBalance() async {
        guard let account = localWalletAccount else {
            walletBalance = nil
            walletBalanceErrorMessage = nil
            return
        }

        let chain = selectedTradeChain
        isRefreshingWalletBalance = true
        walletBalanceErrorMessage = nil

        do {
            walletBalance = try await localWalletClient.fetchNativeBalance(for: account, chain: chain)
            walletStatusMessage = "已刷新 \(chain.displayName) Gas 余额。"
        } catch {
            walletBalanceErrorMessage = error.localizedDescription
        }

        isRefreshingWalletBalance = false
    }

    func useExample(_ example: QueryExample) {
        input = example.value
        selectedKind = example.kind
        if let chainID = example.chainID {
            selectChain(ChainFilter.filter(for: chainID))
        }
        if example.kind == .token {
            tradeDraft.tokenAddress = example.value
        }
    }

    func selectChatSession(_ session: ContextChatSession) {
        activeChatSessionID = session.id
        input = session.context
        resetAutomaticRecognition()
        chatMessages = session.messages
        contextDetailSnapshot = session.surfSnapshot
        contextDetailErrorMessage = nil
        isLoadingContextDetails = false
        chatQuestion = ""
        selectedTextSourceRect = nil
        selectedTextMessage = "已切换到历史对话。"
        result = session.surfSnapshot
        aiExplanation = nil
        llmErrorMessage = nil
        errorMessage = nil
        resetFloatingWalletAction(clearTradePlan: true)
        Task {
            await preloadContextDetailsIfUseful()
        }
    }

    func runResearch() async {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            errorMessage = "请先粘贴地址、交易哈希、代币合约或项目名称。"
            return
        }

        resetAutomaticRecognition()
        let kind = QueryClassifier.classify(query, preferredKind: selectedKind)
        guard kind != .auto else {
            errorMessage = "这段内容看起来不像 EVM 地址、交易哈希或项目名。可以直接在下方对话框向 AI 提问。"
            return
        }

        isLoading = true
        aiExplanation = nil
        llmErrorMessage = nil
        errorMessage = nil

        do {
            let snapshot = try await surfClient.research(
                query: query,
                kind: kind,
                chainFilter: selectedChainFilter
            )
            result = snapshot
            contextDetailSnapshot = snapshot
            syncActiveSessionSnapshot(snapshot)

            if kind == .token || (kind == .wallet && QueryClassifier.isAddress(query)) {
                tradeDraft.tokenAddress = query
            }

            isLoading = false
            await runLLMExplanation()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func buildTradePlan() async {
        let chain = selectedTradeChain
        tradeDraft.applyDefaultSpendToken(for: chain)

        guard let localWalletAccount else {
            tradeErrorMessage = "请先创建或导入本地钱包，再生成 Uniswap 确认单。"
            return
        }

        if walletBalance?.chain.id != chain.id {
            await refreshWalletBalance()
        }

        if let walletBalance, walletBalance.chain.id == chain.id, !walletBalance.hasGas {
            tradeErrorMessage = "\(chain.displayName) 钱包 Gas 余额为 0。请先转入 \(chain.nativeTokenSymbol)，否则无法签名广播交易。"
            return
        }

        guard tradeDraft.canBuildSwapPlan else {
            tradeErrorMessage = "请检查支付金额、支付资产和目标代币地址。"
            return
        }

        hasUniswapAPIKey = CredentialStore.hasUniswapAPIKey()
        isBuildingTradePlan = true
        tradePlan = nil
        tradeConfirmationText = ""
        tradeErrorMessage = nil
        tradeStatusMessage = "正在请求 Uniswap 报价。"

        do {
            let plan = try await tradeProvider.buildSwapPlan(
                draft: tradeDraft,
                chain: chain,
                walletAddress: localWalletAccount.address
            )
            tradePlan = plan
            tradeConfirmationText = ""
            tradeStatusMessage = "确认单已生成。请确认风险后在本机签名广播。"
        } catch {
            tradeErrorMessage = error.localizedDescription
            tradeStatusMessage = nil
        }

        isBuildingTradePlan = false
    }

    func signAndBroadcastTrade() async {
        guard let tradePlan else {
            tradeErrorMessage = "请先生成 Uniswap 确认单。"
            return
        }

        guard !isSigningTrade else {
            return
        }

        guard let localWalletAccount else {
            tradeErrorMessage = "请先创建或导入本地钱包。"
            return
        }

        guard tradePlan.isFreshForSigning else {
            tradeErrorMessage = "报价已超过 \(Int(UniswapTradePlan.quoteValiditySeconds)) 秒。请重新生成报价，避免签名过期或价格变化的交易。"
            tradeConfirmationText = ""
            return
        }

        guard canSignCurrentTrade else {
            tradeErrorMessage = "请先输入钱包地址后 4 位 \(tradePlan.confirmationCode)，再签名。"
            return
        }

        let transaction = tradePlan.approvalTransaction ?? tradePlan.swapTransaction
        guard let transaction else {
            tradeErrorMessage = "确认单里没有可发送的交易。"
            return
        }

        do {
            try transaction.validateForBroadcast(
                expectedFrom: localWalletAccount.address,
                expectedChainID: tradePlan.chain.chainID,
                requiresCalldata: true
            )
        } catch {
            tradeErrorMessage = error.localizedDescription
            return
        }

        isSigningTrade = true
        tradeStatusMessage = tradePlan.needsApproval ? "正在本机签名授权交易。" : "正在本机签名并广播 swap。"
        tradeErrorMessage = nil

        do {
            let hash = try await localWalletClient.signAndBroadcast(transaction, chain: tradePlan.chain)
            let explorerPrefix = tradePlan.chain.explorerTransactionURLPrefix
            if tradePlan.needsApproval {
                tradeStatusMessage = "授权交易已广播：\(hash)\n\(explorerPrefix)/\(hash)\n授权上链后请重新生成报价，再签名兑换。"
                addTradeHistory(hash: hash, chain: tradePlan.chain, action: "授权")
            } else {
                tradeStatusMessage = "交易已广播：\(hash)\n\(explorerPrefix)/\(hash)"
                addTradeHistory(hash: hash, chain: tradePlan.chain, action: "兑换")
            }
            self.tradePlan = nil
            tradeConfirmationText = ""
        } catch {
            tradeErrorMessage = error.localizedDescription
            tradeStatusMessage = nil
        }

        isSigningTrade = false
    }

    func signAndBroadcastTransfer() async {
        guard let transferPlan else {
            floatingWalletActionErrorMessage = "请先生成转账确认单。"
            return
        }

        guard !isSigningTransfer else {
            return
        }

        guard let localWalletAccount else {
            floatingWalletActionErrorMessage = "请先创建或导入本地钱包。"
            return
        }

        guard transferPlan.isFreshForSigning else {
            floatingWalletActionErrorMessage = "转账确认单已超过 \(Int(TransferPlan.validitySeconds)) 秒。请重新生成后再签名。"
            transferConfirmationText = ""
            return
        }

        guard canSignCurrentTransfer else {
            floatingWalletActionErrorMessage = "请先输入收款地址后 4 位 \(transferPlan.confirmationCode)，再签名。"
            return
        }

        do {
            try transferPlan.transaction.validateForBroadcast(
                expectedFrom: localWalletAccount.address,
                expectedChainID: transferPlan.chain.chainID,
                requiresCalldata: transferPlan.requiresCalldata
            )
        } catch {
            floatingWalletActionErrorMessage = error.localizedDescription
            return
        }

        isSigningTransfer = true
        floatingWalletActionStatusMessage = "正在本机签名并广播转账。"
        floatingWalletActionErrorMessage = nil

        do {
            let hash = try await localWalletClient.signAndBroadcast(
                transferPlan.transaction,
                chain: transferPlan.chain
            )
            let explorerPrefix = transferPlan.chain.explorerTransactionURLPrefix
            floatingWalletActionStatusMessage = "转账已广播：\(hash)\n\(explorerPrefix)/\(hash)"
            addTradeHistory(hash: hash, chain: transferPlan.chain, action: "转账")
            self.transferPlan = nil
            transferConfirmationText = ""
        } catch {
            floatingWalletActionErrorMessage = error.localizedDescription
            floatingWalletActionStatusMessage = nil
        }

        isSigningTransfer = false
    }

    func preloadContextDetailsIfUseful() async {
        let context = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isEmpty, shouldFetchSurfContext(for: context) else {
            contextDetailSnapshot = nil
            contextDetailErrorMessage = nil
            isLoadingContextDetails = false
            return
        }

        if snapshotForCurrentContext(context) != nil {
            contextDetailSnapshot = snapshotForCurrentContext(context)
            contextDetailErrorMessage = nil
            return
        }

        let sessionID = activeChatSessionID
        isLoadingContextDetails = true
        contextDetailErrorMessage = nil

        do {
            _ = try await optionalSurfContext(for: context, sessionID: sessionID)
        } catch {
            guard activeChatSessionID == sessionID else {
                return
            }
            contextDetailErrorMessage = error.localizedDescription
        }

        if activeChatSessionID == sessionID {
            isLoadingContextDetails = false
        }
    }

    func runLLMExplanation() async {
        guard let result else {
            return
        }

        hasLLMAPIKey = CredentialStore.hasBAIAPIKey()
        isExplaining = true
        llmErrorMessage = nil

        do {
            aiExplanation = try await llmClient.explain(snapshot: result)
        } catch {
            llmErrorMessage = error.localizedDescription
        }

        isExplaining = false
    }

    func askAboutSelectedContext() async {
        let context = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let question = chatQuestion.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !context.isEmpty else {
            errorMessage = "请先选中文字，或粘贴一段内容作为上下文。"
            return
        }

        guard !question.isEmpty else {
            errorMessage = "请输入你想问 AI 的问题。"
            return
        }

        chatMessages.append(ContextChatMessage(role: .user, text: question))
        syncActiveSessionMessages()
        chatQuestion = ""
        isAnsweringQuestion = true
        llmErrorMessage = nil
        errorMessage = nil
        let sessionID = activeChatSessionID
        let requestHistory = chatMessages

        if await handleWalletIntentIfNeeded(context: context, question: question, sessionID: sessionID) {
            isAnsweringQuestion = false
            return
        }

        do {
            let snapshot = try await optionalSurfContext(for: context, sessionID: sessionID)
            let answer = try await llmClient.answerAboutContext(
                selectedText: context,
                surfSnapshot: snapshot,
                history: requestHistory
            )
            appendMessage(ContextChatMessage(role: .assistant, text: answer), to: sessionID)
        } catch {
            llmErrorMessage = error.localizedDescription
            appendMessage(ContextChatMessage(role: .assistant, text: error.localizedDescription), to: sessionID)
        }

        isAnsweringQuestion = false
    }

    private func startNewContextSession(with context: String) {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let session = ContextChatSession(context: trimmed)
        chatSessions.insert(session, at: 0)
        activeChatSessionID = session.id
        input = trimmed
        chatMessages = []
        result = nil
        aiExplanation = nil
        llmErrorMessage = nil
        tradePlan = nil
        tradeStatusMessage = nil
        tradeErrorMessage = nil
        resetFloatingWalletAction(clearTradePlan: true)
        contextDetailSnapshot = nil
        contextDetailErrorMessage = nil
        isLoadingContextDetails = false
    }

    private func resetFloatingWalletAction(clearTradePlan: Bool) {
        floatingWalletIntent = nil
        transferPlan = nil
        transferConfirmationText = ""
        floatingWalletActionStatusMessage = nil
        floatingWalletActionErrorMessage = nil
        isBuildingFloatingWalletAction = false
        isResolvingSwapTokenCandidates = false
        swapTokenCandidates = []
        selectedSwapTokenCandidate = nil
        isSigningTransfer = false
        if clearTradePlan {
            tradePlan = nil
            tradeConfirmationText = ""
        }
    }

    private func handleWalletIntentIfNeeded(
        context: String,
        question: String,
        sessionID: ContextChatSession.ID?
    ) async -> Bool {
        let intent = WalletIntentParser.parse(
            selectedText: context,
            question: question,
            chain: selectedTradeChain
        )
        guard intent.action != .ask else {
            return false
        }

        resetFloatingWalletAction(clearTradePlan: true)
        floatingWalletIntent = intent

        if !intent.missingFields.isEmpty {
            let message = "我识别到\(intent.action.title)意图，但还缺：\(intent.missingFieldsText)。请补充清楚后我再生成确认单。"
            floatingWalletActionErrorMessage = message
            appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
            return true
        }

        appendMessage(ContextChatMessage(role: .assistant, text: intent.confirmationSummary), to: sessionID)
        isBuildingFloatingWalletAction = true
        floatingWalletActionStatusMessage = "正在生成\(intent.action.title)确认单。"
        floatingWalletActionErrorMessage = nil

        switch intent.action {
        case .transfer:
            await buildFloatingTransferPlan(intent, sessionID: sessionID)
        case .swap:
            await buildFloatingSwapPlan(intent, sessionID: sessionID)
        case .unsupported:
            let message = "这个钱包操作暂不支持，我不会生成可签名交易。"
            floatingWalletActionErrorMessage = message
            appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
        case .ask:
            break
        }

        isBuildingFloatingWalletAction = false
        return true
    }

    private func buildFloatingSwapPlan(
        _ intent: WalletIntentDraft,
        sessionID: ContextChatSession.ID?
    ) async {
        if intent.targetAddress.isEmpty {
            await resolveFloatingSwapTokenCandidates(intent, sessionID: sessionID)
            return
        }

        tradeDraft.spendAmount = intent.spendAmount
        tradeDraft.spendTokenSymbol = intent.spendAsset.symbol
        tradeDraft.spendTokenAddress = intent.spendAsset.address
        tradeDraft.spendTokenDecimals = intent.spendAsset.decimals
        tradeDraft.tokenAddress = intent.targetAddress
        tradeDraft.slippage = intent.slippage

        await buildTradePlan()

        if tradePlan != nil {
            let message = "买币确认单已生成。请在悬浮窗核对链、金额、目标合约和安全检查后，再输入确认码签名。"
            floatingWalletActionStatusMessage = message
            floatingWalletActionErrorMessage = nil
            appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
        } else {
            let message = tradeErrorMessage ?? "生成买币确认单失败。"
            floatingWalletActionStatusMessage = nil
            floatingWalletActionErrorMessage = message
            appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
        }
    }

    private func resolveFloatingSwapTokenCandidates(
        _ intent: WalletIntentDraft,
        sessionID: ContextChatSession.ID?
    ) async {
        let query = intent.targetQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            let message = "请补充目标代币名称或合约地址。"
            floatingWalletActionStatusMessage = nil
            floatingWalletActionErrorMessage = message
            appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
            return
        }

        isResolvingSwapTokenCandidates = true
        swapTokenCandidates = []
        selectedSwapTokenCandidate = nil
        floatingWalletActionStatusMessage = "正在从 Uniswap 搜索 \(query)，并探测 \(intent.spendAmount) \(intent.spendAsset.symbol) 的可成交流动性。"
        floatingWalletActionErrorMessage = nil

        let quoteWalletAddress = localWalletAccount?.address ?? "0x000000000000000000000000000000000000dEaD"

        do {
            let candidates = try await tradeProvider.resolveTokenCandidates(
                query: query,
                chain: intent.chain,
                spendAsset: intent.spendAsset,
                spendAmount: intent.spendAmount,
                walletAddress: quoteWalletAddress
            )
            swapTokenCandidates = candidates

            if candidates.isEmpty {
                let message = "Uniswap token list 里没有找到 \(intent.chain.displayName) 上和 \(query) 匹配的候选。请改用明确合约地址。"
                floatingWalletActionStatusMessage = nil
                floatingWalletActionErrorMessage = message
                appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
            } else {
                let quotedCount = candidates.filter(\.canSelectForSwap).count
                let highRiskCount = candidates.filter { $0.riskLevel == .high }.count
                let blockedCount = candidates.filter { $0.riskLevel == .blocked }.count
                let message = "找到 \(candidates.count) 个候选，其中 \(quotedCount) 个可选择，\(highRiskCount) 个高风险，\(blockedCount) 个已拦截。请先看合约风险和流动性，再选择合约生成签名确认单。"
                floatingWalletActionStatusMessage = message
                floatingWalletActionErrorMessage = nil
                appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
            }
        } catch {
            let message = error.localizedDescription
            floatingWalletActionStatusMessage = nil
            floatingWalletActionErrorMessage = message
            appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
        }

        isResolvingSwapTokenCandidates = false
    }

    func selectSwapTokenCandidate(_ candidate: UniswapTokenCandidate) async {
        guard candidate.canSelectForSwap else {
            floatingWalletActionErrorMessage = "这个候选没有 Uniswap 可成交报价，不能直接生成交易确认单。"
            return
        }

        guard let intent = floatingWalletIntent, intent.action == .swap else {
            floatingWalletActionErrorMessage = "当前没有可继续的买币意图。"
            return
        }

        selectedSwapTokenCandidate = candidate
        tradeDraft.spendAmount = intent.spendAmount
        tradeDraft.spendTokenSymbol = intent.spendAsset.symbol
        tradeDraft.spendTokenAddress = intent.spendAsset.address
        tradeDraft.spendTokenDecimals = intent.spendAsset.decimals
        tradeDraft.tokenAddress = candidate.address
        tradeDraft.slippage = intent.slippage
        let riskNotice = candidate.riskLevel == .high ? "这是高风险候选，请再次核对风险原因。" : "风险等级：\(candidate.riskLevel.title)。"
        floatingWalletActionStatusMessage = "已选择 \(candidate.symbol) \(candidate.shortAddress)。\(riskNotice) 正在生成正式 Uniswap 确认单。"
        floatingWalletActionErrorMessage = nil

        await buildTradePlan()

        if tradePlan != nil {
            floatingWalletActionStatusMessage = "买币确认单已生成。请再次核对合约、流动性和安全检查后输入确认码签名。"
        } else {
            floatingWalletActionStatusMessage = nil
            floatingWalletActionErrorMessage = tradeErrorMessage ?? "生成买币确认单失败。"
        }
    }

    private func buildFloatingTransferPlan(
        _ intent: WalletIntentDraft,
        sessionID: ContextChatSession.ID?
    ) async {
        guard let localWalletAccount else {
            let message = "请先创建或导入本地钱包，再生成转账确认单。"
            floatingWalletActionStatusMessage = nil
            floatingWalletActionErrorMessage = message
            appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
            return
        }

        if walletBalance?.chain.id != intent.chain.id {
            await refreshWalletBalance()
        }

        if let walletBalance, walletBalance.chain.id == intent.chain.id, !walletBalance.hasGas {
            let message = "\(intent.chain.displayName) 钱包 Gas 余额为 0。请先转入 \(intent.chain.nativeTokenSymbol)，否则无法签名广播转账。"
            floatingWalletActionStatusMessage = nil
            floatingWalletActionErrorMessage = message
            appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
            return
        }

        do {
            let plan = try TransferPlanBuilder.build(intent: intent, account: localWalletAccount)
            if plan.asset.address.lowercased() == TokenProfile.nativeETH.address.lowercased(),
               let baseUnits = BigUInt(plan.amountBaseUnits, radix: 10),
               let walletBalance,
               walletBalance.chain.id == plan.chain.id,
               walletBalance.balanceWei <= baseUnits {
                let message = "本地钱包 \(plan.chain.displayName) \(plan.chain.nativeTokenSymbol) 余额不足以覆盖转账金额和 Gas。"
                floatingWalletActionStatusMessage = nil
                floatingWalletActionErrorMessage = message
                appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
                return
            }

            transferPlan = plan
            transferConfirmationText = ""
            let message = "转账确认单已生成。请核对收款地址、资产、金额和安全检查后，再输入收款地址后 4 位签名。"
            floatingWalletActionStatusMessage = message
            floatingWalletActionErrorMessage = nil
            appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
        } catch {
            let message = error.localizedDescription
            floatingWalletActionStatusMessage = nil
            floatingWalletActionErrorMessage = message
            appendMessage(ContextChatMessage(role: .assistant, text: message), to: sessionID)
        }
    }

    private func syncActiveSessionMessages() {
        guard let activeChatSessionID,
              let index = chatSessions.firstIndex(where: { $0.id == activeChatSessionID }) else {
            return
        }

        chatSessions[index].messages = chatMessages
        chatSessions[index].updatedAt = Date()

        if index != 0 {
            let session = chatSessions.remove(at: index)
            chatSessions.insert(session, at: 0)
        }
    }

    private func syncActiveSessionSnapshot(_ snapshot: ResearchSnapshot) {
        guard let activeChatSessionID else {
            return
        }

        syncSessionSnapshot(snapshot, sessionID: activeChatSessionID)
    }

    private func appendMessage(_ message: ContextChatMessage, to sessionID: ContextChatSession.ID?) {
        guard let sessionID else {
            chatMessages.append(message)
            return
        }

        if activeChatSessionID == sessionID {
            chatMessages.append(message)
            syncActiveSessionMessages()
            return
        }

        guard let index = chatSessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        chatSessions[index].messages.append(message)
        chatSessions[index].updatedAt = Date()

        let session = chatSessions.remove(at: index)
        chatSessions.insert(session, at: 0)
    }

    private func syncSessionSnapshot(_ snapshot: ResearchSnapshot, sessionID: ContextChatSession.ID) {
        guard let index = chatSessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        chatSessions[index].surfSnapshot = snapshot
        chatSessions[index].updatedAt = Date()
    }

    private func optionalSurfContext(
        for context: String,
        sessionID: ContextChatSession.ID?
    ) async throws -> ResearchSnapshot? {
        if let snapshot = snapshotForCurrentContext(context) {
            return snapshot
        }

        guard shouldFetchSurfContext(for: context) else {
            return nil
        }

        let kind = QueryClassifier.classify(context, preferredKind: selectedKind)
        guard kind != .auto else {
            return nil
        }

        do {
            let snapshot = try await surfClient.research(
                query: context,
                kind: kind,
                chainFilter: selectedChainFilter
            )
            if let sessionID {
                syncSessionSnapshot(snapshot, sessionID: sessionID)
            }

            if activeChatSessionID == sessionID,
               input.trimmingCharacters(in: .whitespacesAndNewlines) == context {
                result = snapshot
                contextDetailSnapshot = snapshot
            }
            return snapshot
        } catch SurfClientError.unsupportedInput {
            return nil
        }
    }

    private func snapshotForCurrentContext(_ context: String) -> ResearchSnapshot? {
        if let contextDetailSnapshot, contextDetailSnapshot.query == context {
            return contextDetailSnapshot
        }

        if let result, result.query == context {
            return result
        }

        if let snapshot = activeChatSession?.surfSnapshot, snapshot.query == context {
            return snapshot
        }

        return nil
    }

    private func shouldFetchSurfContext(for context: String) -> Bool {
        if QueryClassifier.isAddress(context) || QueryClassifier.isTransactionHash(context) {
            return true
        }

        if selectedKind != .auto {
            return true
        }

        return QueryClassifier.looksLikeProjectName(context)
    }

    private func resetAutomaticRecognition() {
        selectedKind = .auto
        selectedChainID = ChainFilter.automatic.id
    }

    private func addTradeHistory(hash: String, chain: ChainProfile, action: String) {
        tradeHistory.insert(
            TradeHistoryItem(hash: hash, chain: chain, action: action),
            at: 0
        )
        if tradeHistory.count > 20 {
            tradeHistory.removeLast(tradeHistory.count - 20)
        }
    }
}

struct QueryExample: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let kind: QueryKind
    let chainID: String?

    init(title: String, value: String, kind: QueryKind, chainID: String? = nil) {
        self.title = title
        self.value = value
        self.kind = kind
        self.chainID = chainID
    }

    static let defaults: [QueryExample] = [
        QueryExample(
            title: "Base USDC 代币",
            value: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
            kind: .token,
            chainID: ChainRegistry.base.id
        ),
        QueryExample(
            title: "Ethereum USDC 代币",
            value: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            kind: .token,
            chainID: ChainRegistry.ethereum.id
        ),
        QueryExample(
            title: "Base WETH 合约",
            value: "0x4200000000000000000000000000000000000006",
            kind: .token,
            chainID: ChainRegistry.base.id
        ),
        QueryExample(
            title: "Uniswap 项目",
            value: "Uniswap",
            kind: .project
        )
    ]
}
