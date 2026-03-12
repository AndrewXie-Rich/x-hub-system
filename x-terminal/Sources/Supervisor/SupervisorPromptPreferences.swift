import Foundation

struct SupervisorPromptPreferences: Codable, Equatable {
    var identityName: String
    var roleSummary: String
    var toneDirectives: String
    var extraSystemPrompt: String

    static func `default`() -> SupervisorPromptPreferences {
        let identity = SupervisorIdentityProfile.default()
        return SupervisorPromptPreferences(
            identityName: identity.name,
            roleSummary: identity.roleSummary,
            toneDirectives: "",
            extraSystemPrompt: ""
        )
    }

    func normalized() -> SupervisorPromptPreferences {
        let defaults = SupervisorPromptPreferences.default()
        let name = trimmedOrFallback(identityName, fallback: defaults.identityName)
        let summary = trimmedOrFallback(roleSummary, fallback: defaults.roleSummary)
        return SupervisorPromptPreferences(
            identityName: name,
            roleSummary: summary,
            toneDirectives: normalizedMultiline(toneDirectives),
            extraSystemPrompt: extraSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var toneDirectiveLines: [String] {
        normalized()
            .toneDirectives
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-*•"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    var extraSystemPromptOrNil: String? {
        let trimmed = normalized().extraSystemPrompt
        return trimmed.isEmpty ? nil : trimmed
    }

    private func trimmedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func normalizedMultiline(_ value: String) -> String {
        value
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
