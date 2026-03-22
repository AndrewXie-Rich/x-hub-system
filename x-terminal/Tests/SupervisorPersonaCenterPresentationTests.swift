import Foundation
import Testing
@testable import XTerminal

struct SupervisorPersonaCenterPresentationTests {

    @Test
    func presentationFallsBackToActivePersonaAndSurfacesCardBadges() throws {
        var registry = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)
        registry = registry.setting(defaultPersonaID: "persona_slot_2")
        registry = registry.setting(activePersonaID: "persona_slot_3")

        var sage = registry.slots[3]
        sage.enabled = false
        registry = registry.setting(slot: sage)

        let presentation = SupervisorPersonaCenterPresentation(
            draftRegistry: registry,
            persistedRegistry: registry,
            selectedPersonaID: "missing-slot",
            defaultVoicePersona: .conversational
        )

        #expect(presentation.selectedPersonaID == "persona_slot_3")
        #expect(presentation.selectedCard.personaID == "persona_slot_3")

        let atlas = try #require(presentation.cards.first(where: { $0.personaID == "persona_slot_2" }))
        #expect(atlas.statusBadges.contains(where: { $0.text == "默认" }))

        let nova = try #require(presentation.cards.first(where: { $0.personaID == "persona_slot_3" }))
        #expect(nova.statusBadges.contains(where: { $0.text == "当前" }))

        let disabled = try #require(presentation.cards.first(where: { $0.personaID == "persona_slot_4" }))
        #expect(disabled.tags.contains(where: { $0.text == "已停用" }))
    }

    @Test
    func presentationTracksUnsavedDraftAndDisablesDefaultActiveActionsForDisabledSelection() {
        let persisted = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)
        var draft = persisted
        var breeze = draft.slots[4]
        breeze.enabled = false
        breeze.displayName = "Orbit"
        draft = draft.setting(slot: breeze)

        let presentation = SupervisorPersonaCenterPresentation(
            draftRegistry: draft,
            persistedRegistry: persisted,
            selectedPersonaID: "persona_slot_5",
            defaultVoicePersona: .conversational
        )

        #expect(presentation.syncState == .draftUnsaved)
        #expect(presentation.canSave)
        #expect(presentation.canRestore)
        #expect(!presentation.canSetSelectedAsDefault)
        #expect(!presentation.canSetSelectedAsActive)
        #expect(presentation.selectedCard.displayName == "Orbit")
    }

    @Test
    func presentationSummarizesVoiceAndWakeSuggestions() {
        var registry = SupervisorPersonaRegistry.default(defaultVoicePersona: .calm)
        registry = registry.setting(defaultPersonaID: "persona_slot_5")
        registry = registry.setting(activePersonaID: "persona_slot_5")

        var breeze = registry.slots[4]
        breeze.voicePersonaOverride = nil
        registry = registry.setting(slot: breeze)

        var nova = registry.slots[2]
        nova.enabled = false
        registry = registry.setting(slot: nova)

        let presentation = SupervisorPersonaCenterPresentation(
            draftRegistry: registry,
            persistedRegistry: registry,
            selectedPersonaID: "persona_slot_5",
            defaultVoicePersona: .calm,
            existingWakeTriggerWords: ["x hub", "atlas"]
        )

        #expect(presentation.persistedActivePersonaName == "Breeze")
        #expect(presentation.persistedDefaultPersonaName == "Breeze")
        #expect(presentation.persistedActiveVoiceSummary == "跟随运行时默认（平静）")
        #expect(presentation.persistedDefaultVoiceSummary == "跟随运行时默认（平静）")
        #expect(!presentation.wakeSuggestions.contains(where: { $0.token.lowercased() == "atlas" }))
        #expect(!presentation.wakeSuggestions.contains(where: { $0.personaID == "persona_slot_3" }))
        #expect(presentation.wakeSuggestions.contains(where: { $0.personaID == "persona_slot_5" && $0.isPrimaryName }))
    }
}
