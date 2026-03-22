import Foundation

struct SupervisorWakePhraseSuggestion: Identifiable, Equatable {
    let personaID: String
    let personaDisplayName: String
    let token: String
    let normalizedToken: String
    let isPrimaryName: Bool

    var id: String { "\(personaID):\(normalizedToken)" }
}

enum SupervisorWakePhraseSuggestionBuilder {
    static func suggestions(
        registry: SupervisorPersonaRegistry,
        existingTriggerWords: [String]
    ) -> [SupervisorWakePhraseSuggestion] {
        let existing = Set(
            VoiceWakeProfile.sanitizeTriggerWords(
                existingTriggerWords,
                fallbackToDefaults: false
            ).map(normalizedLookupKey)
        )
        let reserved = Set(VoiceWakeProfile.defaultTriggerWords.map(normalizedLookupKey))

        var seen = Set<String>()
        var output: [SupervisorWakePhraseSuggestion] = []

        for slot in registry.slots where slot.enabled {
            let rawTokens = [slot.displayName] + slot.aliases
            for (index, raw) in rawTokens.enumerated() {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = normalizedLookupKey(trimmed)
                guard !trimmed.isEmpty, !normalized.isEmpty else { continue }
                guard !reserved.contains(normalized) else { continue }
                guard !existing.contains(normalized) else { continue }
                guard seen.insert("\(slot.personaID):\(normalized)").inserted else { continue }

                output.append(
                    SupervisorWakePhraseSuggestion(
                        personaID: slot.personaID,
                        personaDisplayName: slot.displayName,
                        token: trimmed,
                        normalizedToken: normalized,
                        isPrimaryName: index == 0
                    )
                )
            }
        }

        return output
    }

    static func appendingSuggestionToken(
        _ token: String,
        to rawText: String
    ) -> String {
        let existing = editableTriggerWords(from: rawText)
        let combined = VoiceWakeProfile.sanitizeTriggerWords(
            existing + [token],
            fallbackToDefaults: false
        )
        return combined.joined(separator: ", ")
    }

    private static func editableTriggerWords(from rawText: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n\r\t|/\\，、")
        return VoiceWakeProfile.sanitizeTriggerWords(
            rawText.components(separatedBy: separators),
            fallbackToDefaults: false
        )
    }

    private static func normalizedLookupKey(_ text: String) -> String {
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }
}
