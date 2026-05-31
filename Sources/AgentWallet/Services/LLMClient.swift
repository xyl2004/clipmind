import Foundation

struct LLMClient {
    private static let defaultBaseURL = URL(string: "https://api.b.ai")!
    private static let baseURLOverrideEnv = "AGENTWALLET_BAI_BASE_URL"
    private let model = "deepseek-v4-flash"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private var endpoint: URL {
        let base = ProcessInfo.processInfo.environment[Self.baseURLOverrideEnv]
            .flatMap { URL(string: $0) }
            ?? Self.defaultBaseURL
        return base.appendingPathComponent("v1/chat/completions")
    }

    func explain(snapshot: ResearchSnapshot) async throws -> String {
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt(for: snapshot)]
        ]
        return try await sendChat(messages: messages, temperature: 0.2, maxTokens: 900)
    }

    func answerAboutContext(
        selectedText: String,
        surfSnapshot: ResearchSnapshot?,
        history: [ContextChatMessage]
    ) async throws -> String {
        let systemContent = buildContextSystemPrompt(
            selectedText: selectedText,
            surfSnapshot: surfSnapshot
        )

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemContent]
        ]

        for message in history {
            messages.append([
                "role": message.role == .user ? "user" : "assistant",
                "content": message.text
            ])
        }

        return try await sendChat(messages: messages, temperature: 0.25, maxTokens: 900)
    }

    private func sendChat(
        messages: [[String: Any]],
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        guard let apiKey = CredentialStore.readBAIAPIKey() else {
            throw LLMClientError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "messages": messages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                CredentialStore.invalidateCache()
                throw LLMClientError.apiError("API Key 无效，请检查或重新保存。")
            }
            let message = parseAPIError(data) ?? "HTTP \(httpResponse.statusCode)"
            throw LLMClientError.apiError(message)
        }

        guard let content = parseContent(data), !content.isEmpty else {
            throw LLMClientError.emptyResponse
        }

        return normalizeAssistantOutput(content)
    }

    private var systemPrompt: String {
        """
        你是 AgentWallet 的链上研究助手。你只根据用户提供的 Surf 数据做中文解释，不要编造未出现的数据。
        输出面向普通 Web3 用户，简洁、直接、可执行。
        必须使用纯文本中文，不要使用 Markdown 标记，不要输出星号、井号、反引号或表格。
        结构固定为：
        结论：
        关键信号：
        风险提示：
        下一步建议：
        如果数据不足，明确写“当前数据不足以判断”。不要构成投资建议，不要让用户直接买入。
        """
    }

    private var contextSystemPrompt: String {
        """
        你是 AgentWallet 的上下文 AI 助手。用户会选中一段文字、地址、合约、交易哈希或网页内容，然后向你提问。
        请优先解释“被选中的内容是什么、可能代表什么、用户下一步可以怎么理解它”。
        如果提供了 Surf 链上数据，只能基于这些数据补充说明，不要编造没有出现的数据。
        回答用中文，简洁直接。必须使用纯文本，不要使用 Markdown，不要输出星号、井号、反引号或表格。
        如果内容涉及项目、代币或地址，优先使用这些小标题：结论：、它是什么：、关键数据：、风险：、下一步：。
        关键数据只能引用 Surf 数据或用户明确提供的信息。
        涉及交易或代币时必须提醒这不是投资建议，也不要直接劝用户买入。
        多轮对话时请保持对“当前选中内容”的连贯解释，不要忘记上下文。
        """
    }

    private func userPrompt(for snapshot: ResearchSnapshot) -> String {
        """
        查询对象：\(snapshot.query)
        查询类型：\(snapshot.kind.title)
        网络：\(chainSummary(for: snapshot))

        结构化展示：
        \(sectionSummary(for: snapshot))

        Surf 原始 JSON：
        \(truncate(snapshot.rawJSON, byteLimit: 22_000))
        """
    }

    private func buildContextSystemPrompt(
        selectedText: String,
        surfSnapshot: ResearchSnapshot?
    ) -> String {
        var parts: [String] = [contextSystemPrompt]

        parts.append("""

        [用户当前选中的内容]
        \(selectedText)
        """)

        if let surfSnapshot {
            parts.append("""

            [可用的 Surf/EVM 数据]
            \(sectionSummary(for: surfSnapshot))

            [Surf 原始 JSON]
            \(truncate(surfSnapshot.rawJSON, byteLimit: 16_000))
            """)
        }

        return parts.joined(separator: "\n")
    }

    private func sectionSummary(for snapshot: ResearchSnapshot) -> String {
        snapshot.sections.map { section in
            let rows = section.rows.map { "- \($0.label): \($0.value)" }.joined(separator: "\n")
            return "## \(section.title)\n\(rows)"
        }
        .joined(separator: "\n\n")
    }

    private func chainSummary(for snapshot: ResearchSnapshot) -> String {
        guard !snapshot.chains.isEmpty else {
            return "EVM"
        }

        return snapshot.chains.map(\.displayName).joined(separator: ", ")
    }

    /// Truncate by UTF-8 byte length so we don't blow up token budget on
    /// multi-byte (CJK) content. Cuts at a UTF-8 boundary and tags the cut.
    private func truncate(_ value: String, byteLimit: Int) -> String {
        let utf8 = Array(value.utf8)
        guard utf8.count > byteLimit else {
            return value
        }
        var cutoff = byteLimit
        while cutoff > 0, (utf8[cutoff] & 0xC0) == 0x80 {
            cutoff -= 1
        }
        let head = String(decoding: utf8.prefix(cutoff), as: UTF8.self)
        return head + "\n…(已按字节截断，剩余内容省略)"
    }

    private func normalizeAssistantOutput(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines).map { rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            line = line.replacingOccurrences(
                of: "^#{1,6}\\s+",
                with: "",
                options: .regularExpression
            )
            line = line.replacingOccurrences(
                of: "^[-*]\\s+",
                with: "",
                options: .regularExpression
            )
            return line
        }

        var normalized = lines.joined(separator: "\n")
        normalized = normalized.replacingOccurrences(
            of: "\\*\\*(.*?)\\*\\*",
            with: "$1",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: "__(.*?)__",
            with: "$1",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(of: "`", with: "")
        normalized = normalized.replacingOccurrences(of: "*", with: "")
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseContent(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            return nil
        }

        return message["content"] as? String
    }

    private func parseAPIError(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }

        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        if let message = object["message"] as? String {
            return message
        }

        return String(data: data, encoding: .utf8)
    }
}

enum LLMClientError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "未设置 B.AI API Key。请在页面顶部保存到 Keychain，或设置 AGENTWALLET_BAI_API_KEY / B_AI_API_KEY 环境变量。"
        case .invalidResponse:
            "LLM 服务返回了无效响应。"
        case .apiError(let message):
            "LLM 服务调用失败：\(message)"
        case .emptyResponse:
            "LLM 服务没有返回可展示的内容。"
        }
    }
}
