import AppKit
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
    @Published var tradeDraft = TradeIntentDraft()
    @Published var externalWalletSession: ExternalWalletSession?
    @Published var walletStatusMessage: String?
    @Published var tradePlan: UniswapTradePlan?
    @Published var isBuildingTradePlan = false
    @Published var tradeStatusMessage: String?
    @Published var tradeErrorMessage: String?

    private let surfClient = SurfClient()
    private let llmClient = LLMClient()
    private let tradeProvider = UniswapTradeProvider()
    private let externalWalletClient = ExternalWalletClient()
    private var selectedTextSourceRect: CGRect?

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
        externalWalletSession?.shortAddress ?? "未连接"
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
        selectedKind = .auto
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
            selectedKind = .auto
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
            tradeErrorMessage = nil
        } catch {
            uniswapAPIKeyStatusMessage = error.localizedDescription
        }
    }

    func selectChain(_ filter: ChainFilter) {
        selectedChainID = filter.id
        let chain = filter.profile ?? ChainRegistry.base
        tradeDraft.applyDefaultSpendToken(for: chain)
        tradePlan = nil
        tradeErrorMessage = nil
        tradeStatusMessage = nil
    }

    func connectExternalWallet() {
        do {
            let session = try externalWalletClient.connect(address: tradeDraft.walletAddress)
            externalWalletSession = session
            walletStatusMessage = "已连接外部钱包：\(session.shortAddress)"
            tradeErrorMessage = nil
        } catch {
            walletStatusMessage = error.localizedDescription
        }
    }

    func disconnectExternalWallet() {
        externalWalletSession = nil
        walletStatusMessage = "已断开外部钱包。"
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
        selectedKind = .auto
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
        if selectedChainFilter.isAutomatic {
            selectedChainID = chain.id
        }
        tradeDraft.applyDefaultSpendToken(for: chain)

        guard let externalWalletSession else {
            tradeErrorMessage = "请先输入外部钱包地址并连接，再生成 Uniswap 确认单。"
            return
        }

        guard tradeDraft.canBuildSwapPlan else {
            tradeErrorMessage = "请检查支付金额、支付资产和目标代币地址。"
            return
        }

        hasUniswapAPIKey = CredentialStore.hasUniswapAPIKey()
        isBuildingTradePlan = true
        tradePlan = nil
        tradeErrorMessage = nil
        tradeStatusMessage = "正在请求 Uniswap 报价。"

        do {
            let plan = try await tradeProvider.buildSwapPlan(
                draft: tradeDraft,
                chain: chain,
                walletAddress: externalWalletSession.address
            )
            tradePlan = plan
            tradeStatusMessage = "确认单已生成。请在确认风险后发送到外部钱包签名。"
        } catch {
            tradeErrorMessage = error.localizedDescription
            tradeStatusMessage = nil
        }

        isBuildingTradePlan = false
    }

    func sendTradeToExternalWallet() async {
        guard let tradePlan else {
            tradeErrorMessage = "请先生成 Uniswap 确认单。"
            return
        }

        let transaction = tradePlan.approvalTransaction ?? tradePlan.swapTransaction
        guard let transaction else {
            tradeErrorMessage = "确认单里没有可发送的交易。"
            return
        }

        tradeStatusMessage = "正在发送到外部钱包签名。"
        tradeErrorMessage = nil

        do {
            let hash = try await externalWalletClient.send(transaction)
            let explorerPrefix = tradePlan.chain.explorerTransactionURLPrefix
            tradeStatusMessage = "交易已广播：\(hash)\n\(explorerPrefix)/\(hash)"
        } catch {
            tradeErrorMessage = error.localizedDescription
            tradeStatusMessage = nil
        }
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
        contextDetailSnapshot = nil
        contextDetailErrorMessage = nil
        isLoadingContextDetails = false
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
