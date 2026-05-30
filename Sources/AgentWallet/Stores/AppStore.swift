import AppKit
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var input: String = ""
    @Published var selectedKind: QueryKind = .auto
    @Published var isLoading = false
    @Published var isExplaining = false
    @Published var result: ResearchSnapshot?
    @Published var aiExplanation: String?
    @Published var chatQuestion: String = ""
    @Published var chatMessages: [ContextChatMessage] = []
    @Published var chatSessions: [ContextChatSession] = []
    @Published var activeChatSessionID: ContextChatSession.ID?
    @Published var isAnsweringQuestion = false
    @Published var errorMessage: String?
    @Published var llmErrorMessage: String?
    @Published var selectedTextMessage: String?
    @Published var apiKeyDraft: String = ""
    @Published var apiKeyStatusMessage: String?
    @Published var hasLLMAPIKey = CredentialStore.hasBAIAPIKey()
    @Published var tradeDraft = TradeIntentDraft()

    private let surfClient = SurfClient()
    private let llmClient = LLMClient()
    private var selectedTextSourceRect: CGRect?

    var effectiveKind: QueryKind {
        QueryClassifier.classify(input, preferredKind: selectedKind)
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
        captureSelectedText()
        showFloatingChatPanel()
    }

    func captureClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            errorMessage = "剪贴板里没有可查询的文本。"
            return
        }

        input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedTextSourceRect = nil
        selectedTextMessage = "已读取剪贴板内容。"
        startNewContextSession(with: input)
        if QueryClassifier.isAddress(input) {
            tradeDraft.tokenAddress = input
        }
    }

    func captureSelectedText() {
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
        case .failure(let message):
            selectedTextMessage = nil
            errorMessage = message
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

    func useExample(_ example: QueryExample) {
        input = example.value
        selectedKind = example.kind
        if example.kind == .token {
            tradeDraft.tokenAddress = example.value
        }
    }

    func selectChatSession(_ session: ContextChatSession) {
        activeChatSessionID = session.id
        input = session.context
        chatMessages = session.messages
        chatQuestion = ""
        selectedTextSourceRect = nil
        selectedTextMessage = "已切换到历史对话。"
        result = nil
        aiExplanation = nil
        llmErrorMessage = nil
        errorMessage = nil
    }

    func runResearch() async {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            errorMessage = "请先粘贴地址、交易哈希、代币合约或项目名称。"
            return
        }

        let kind = QueryClassifier.classify(query, preferredKind: selectedKind)
        guard kind != .auto else {
            errorMessage = "这段内容看起来不像 Base 地址、交易哈希或项目名。可以直接在下方对话框向 AI 提问。"
            return
        }

        isLoading = true
        aiExplanation = nil
        llmErrorMessage = nil
        errorMessage = nil

        do {
            let snapshot = try await surfClient.research(query: query, kind: kind)
            result = snapshot

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

        do {
            let snapshot = try await optionalSurfContext(for: context)
            let answer = try await llmClient.answerAboutContext(
                selectedText: context,
                surfSnapshot: snapshot,
                history: chatMessages
            )
            chatMessages.append(ContextChatMessage(role: .assistant, text: answer))
            syncActiveSessionMessages()
        } catch {
            llmErrorMessage = error.localizedDescription
            chatMessages.append(ContextChatMessage(role: .assistant, text: error.localizedDescription))
            syncActiveSessionMessages()
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

    private func optionalSurfContext(for context: String) async throws -> ResearchSnapshot? {
        if let result, result.query == context {
            return result
        }

        guard shouldFetchSurfContext(for: context) else {
            return nil
        }

        let kind = QueryClassifier.classify(context, preferredKind: selectedKind)
        guard kind != .auto else {
            return nil
        }

        do {
            let snapshot = try await surfClient.research(query: context, kind: kind)
            result = snapshot
            return snapshot
        } catch SurfClientError.unsupportedInput {
            return nil
        }
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

    static let defaults: [QueryExample] = [
        QueryExample(
            title: "Base USDC 代币",
            value: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
            kind: .token
        ),
        QueryExample(
            title: "Base WETH 合约钱包",
            value: "0x4200000000000000000000000000000000000006",
            kind: .wallet
        ),
        QueryExample(
            title: "Uniswap 项目",
            value: "Uniswap",
            kind: .project
        )
    ]
}
