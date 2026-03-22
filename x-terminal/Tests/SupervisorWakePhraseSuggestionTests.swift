import Foundation
import Testing
@testable import XTerminal

struct SupervisorWakePhraseSuggestionTests {

    @Test
    func suggestionsExcludeReservedAndExistingWakeTokens() {
        let registry = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)

        let suggestions = SupervisorWakePhraseSuggestionBuilder.suggestions(
            registry: registry,
            existingTriggerWords: ["x hub", "atlas"]
        )

        #expect(!suggestions.contains(where: { $0.normalizedToken == "xhub" }))
        #expect(!suggestions.contains(where: { $0.normalizedToken == "supervisor" }))
        #expect(!suggestions.contains(where: { $0.normalizedToken == "atlas" }))
        #expect(suggestions.contains(where: { $0.normalizedToken == "nova" }))
        #expect(suggestions.contains(where: { $0.normalizedToken == "sage" }))
    }

    @Test
    func suggestionsSkipDisabledPersonasAndDeduplicateAliases() {
        var registry = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)
        var atlas = registry.slots[1]
        atlas.aliases.append("Atlas")
        registry = registry.setting(slot: atlas)

        var nova = registry.slots[2]
        nova.enabled = false
        registry = registry.setting(slot: nova)

        let suggestions = SupervisorWakePhraseSuggestionBuilder.suggestions(
            registry: registry,
            existingTriggerWords: []
        )

        #expect(suggestions.filter { $0.personaID == "persona_slot_2" && $0.normalizedToken == "atlas" }.count == 1)
        #expect(!suggestions.contains(where: { $0.personaID == "persona_slot_3" }))
    }

    @Test
    func appendingSuggestionTokenNormalizesAndPreservesOrder() {
        let updated = SupervisorWakePhraseSuggestionBuilder.appendingSuggestionToken(
            "Atlas",
            to: "x hub, sage"
        )

        #expect(updated == "x hub, sage, atlas")
    }
}
