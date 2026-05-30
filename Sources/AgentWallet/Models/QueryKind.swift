import Foundation

enum QueryKind: String, CaseIterable, Identifiable {
    case auto
    case wallet
    case token
    case transaction
    case project

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            "自动"
        case .wallet:
            "钱包"
        case .token:
            "代币"
        case .transaction:
            "交易"
        case .project:
            "项目"
        }
    }

    var systemImage: String {
        switch self {
        case .auto:
            "sparkle.magnifyingglass"
        case .wallet:
            "wallet.pass"
        case .token:
            "seal"
        case .transaction:
            "arrow.left.arrow.right"
        case .project:
            "building.columns"
        }
    }
}

enum QueryClassifier {
    static func classify(_ input: String, preferredKind: QueryKind) -> QueryKind {
        guard preferredKind == .auto else {
            return preferredKind
        }

        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if isTransactionHash(value) {
            return .transaction
        }

        if isAddress(value) {
            return .wallet
        }

        if looksLikeProjectName(value) {
            return .project
        }

        // Free-form text (a sentence, a paragraph, CJK content): don't burn
        // Surf calls on it. The caller will treat it as plain context.
        return .auto
    }

    static func isAddress(_ value: String) -> Bool {
        matches(value, pattern: "^0x[a-fA-F0-9]{40}$")
    }

    static func isTransactionHash(_ value: String) -> Bool {
        matches(value, pattern: "^0x[a-fA-F0-9]{64}$")
    }

    /// Heuristic: project lookups only make sense for short, mostly-ASCII tokens
    /// like "Uniswap", "Aerodrome", "base-eco". Anything longer or with prose
    /// punctuation is treated as free-form context instead.
    static func looksLikeProjectName(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 40 else {
            return false
        }
        let words = value.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard words.count <= 4 else {
            return false
        }
        return matches(value, pattern: "^[A-Za-z0-9 ._\\-]+$")
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
