import Foundation

protocol IntentClassifierBackend {
    /// Send one chat completion with the given system + user prompt.
    /// Returns the assistant message's raw content (may include markdown wrap).
    func classifyChat(system: String, user: String) async throws -> String
}

enum IntentClassifierError: LocalizedError {
    case retryExhausted(String)

    var errorDescription: String? {
        switch self {
        case .retryExhausted(let reason):
            return "意图分类器重试仍失败：\(reason)"
        }
    }
}

struct IntentClassifier {
    let backend: IntentClassifierBackend
    let prompt: IntentClassifierPrompt

    init(backend: IntentClassifierBackend, prompt: IntentClassifierPrompt = IntentClassifierPrompt()) {
        self.backend = backend
        self.prompt = prompt
    }

    func classify(
        selectedContext: String,
        previousIntent: WalletIntentDraft?,
        chainHint: String,
        question: String
    ) async throws -> StructuredIntent {
        let user = prompt.buildUserPayload(
            selectedContext: selectedContext,
            previousIntent: previousIntent,
            chainHint: chainHint,
            question: question
        )
        return try await classifyWithRetry(system: prompt.systemPrompt, user: user, retriesLeft: 1)
    }

    private func classifyWithRetry(
        system: String,
        user: String,
        retriesLeft: Int
    ) async throws -> StructuredIntent {
        let raw = try await backend.classifyChat(system: system, user: user)
        do {
            return try StructuredIntent.decode(raw: raw)
        } catch let decodeError as StructuredIntentDecodeError {
            guard retriesLeft > 0 else {
                throw IntentClassifierError.retryExhausted(decodeError.localizedDescription)
            }
            let retryUser = user + "\n\nYour previous output was rejected: \(decodeError.localizedDescription). Output ONLY a single JSON object matching the schema."
            return try await classifyWithRetry(system: system, user: retryUser, retriesLeft: retriesLeft - 1)
        }
    }
}

/// Test-only fake backend that returns canned responses in order.
/// Each call pops the head of `responses`. If empty, throws `noMoreResponses`.
final class StubIntentClassifierBackend: IntentClassifierBackend {
    enum CannedResponse {
        case success(String)
        case failure(Error)
    }

    enum StubError: Error {
        case noMoreResponses
    }

    private(set) var callCount: Int = 0
    private(set) var lastSystem: String = ""
    private(set) var lastUsers: [String] = []
    private var responses: [CannedResponse]

    init(responses: [CannedResponse]) {
        self.responses = responses
    }

    func classifyChat(system: String, user: String) async throws -> String {
        callCount += 1
        lastSystem = system
        lastUsers.append(user)
        guard !responses.isEmpty else {
            throw StubError.noMoreResponses
        }
        let head = responses.removeFirst()
        switch head {
        case .success(let raw):
            return raw
        case .failure(let error):
            throw error
        }
    }
}

// Placeholder so this task compiles. Full content lands in Task 9.
struct IntentClassifierPrompt {
    var systemPrompt: String { "" }

    func buildUserPayload(
        selectedContext: String,
        previousIntent: WalletIntentDraft?,
        chainHint: String,
        question: String
    ) -> String {
        return ""
    }
}
