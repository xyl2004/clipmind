import Foundation

struct ResearchSnapshot: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let query: String
    let kind: QueryKind
    let createdAt: Date
    let sections: [ResearchSection]
    let commands: [SurfCommandSummary]
    let rawJSON: String
    let warnings: [String]
}

struct ResearchSection: Identifiable {
    let title: String
    let rows: [ResearchRow]
    var id: String { title }
}

struct ResearchRow: Identifiable {
    let label: String
    let value: String
    let style: ResearchRowStyle

    var id: String { "\(label)|\(value)|\(style)" }

    init(_ label: String, _ value: String, style: ResearchRowStyle = .regular) {
        self.label = label
        self.value = value
        self.style = style
    }
}

enum ResearchRowStyle: String {
    case regular
    case positive
    case warning
    case mono
}

struct SurfCommandSummary: Identifiable {
    let command: String
    let succeeded: Bool
    let summary: String
    var id: String { command }
}

struct ContextChatMessage: Identifiable {
    let id = UUID()
    let role: ContextChatRole
    let text: String
    let createdAt = Date()
}

enum ContextChatRole {
    case user
    case assistant
}

struct ContextChatSession: Identifiable {
    let id = UUID()
    let context: String
    let createdAt = Date()
    var updatedAt = Date()
    var messages: [ContextChatMessage] = []
    var surfSnapshot: ResearchSnapshot?

    var title: String {
        let normalized = context
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty {
            return "空白上下文"
        }

        if normalized.count <= 32 {
            return normalized
        }

        return "\(normalized.prefix(32))..."
    }

    var subtitle: String {
        if let surfSnapshot {
            return "\(surfSnapshot.kind.title) · \(messages.count) 条消息"
        }

        if messages.isEmpty {
            return "尚未提问"
        }

        return "\(messages.count) 条消息"
    }
}
