import Foundation

struct XTProjectConversationMirrorMessage: Codable, Equatable {
    var role: String
    var content: String
}

enum XTProjectConversationMirror {
    static let maxCharsPerMessage = 6_000

    static func projectThreadKey(projectId: String) -> String {
        let trimmed = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "xterminal_project_unknown" }
        return "xterminal_project_\(trimmed)"
    }

    static func requestID(projectId: String, createdAt: Double) -> String {
        let compactProjectId = projectId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
        let token = compactProjectId.isEmpty ? "unknown" : String(compactProjectId.prefix(12))
        return "xterminal_turn_\(token)_\(createdAtMs(createdAt))"
    }

    static func createdAtMs(_ createdAt: Double) -> Int64 {
        Int64((createdAt * 1000.0).rounded())
    }

    static func messages(userText: String, assistantText: String) -> [XTProjectConversationMirrorMessage] {
        let candidates: [(String, String)] = [
            ("user", normalizedContent(userText)),
            ("assistant", normalizedContent(assistantText)),
        ]

        return candidates.compactMap { role, content in
            guard !content.isEmpty else { return nil }
            return XTProjectConversationMirrorMessage(role: role, content: content)
        }
    }

    private static func normalizedContent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= maxCharsPerMessage { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxCharsPerMessage)
        return String(trimmed[..<idx]) + "\n\n[x-terminal] truncated"
    }
}
