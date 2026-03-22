import Foundation
import Testing
@testable import XTerminal

struct SupervisorVoicePreferenceOverlayTests {

    @Test
    func overlayAppliesPersonaAndHubVoicePackOverride() {
        var base = VoiceRuntimePreferences.default()
        base.persona = .conversational
        base.preferredHubVoicePackID = "hub.voice.runtime.default"
        base.timbre = .warm

        var slot = SupervisorPersonaSlot.seed(index: 1, defaultVoicePersona: .briefing)
        slot.voicePersonaOverride = .calm
        slot.voicePackOverrideID = "hub.voice.persona.atlas"

        let effective = xtVoicePreferencesApplyingPersonaOverlay(base, personaSlot: slot)

        #expect(effective.persona == .calm)
        #expect(effective.preferredHubVoicePackID == "hub.voice.persona.atlas")
        #expect(effective.timbre == .warm)
        #expect(effective.playbackPreference == base.playbackPreference)
    }

    @Test
    func overlayKeepsRuntimeDefaultsWhenSlotDoesNotOverride() {
        var base = VoiceRuntimePreferences.default()
        base.persona = .briefing
        base.preferredHubVoicePackID = "hub.voice.runtime.default"

        var slot = SupervisorPersonaSlot.seed(index: 2, defaultVoicePersona: .briefing)
        slot.voicePersonaOverride = nil
        slot.voicePackOverrideID = "   "

        let effective = xtVoicePreferencesApplyingPersonaOverlay(base, personaSlot: slot)

        #expect(effective.persona == .briefing)
        #expect(effective.preferredHubVoicePackID == "hub.voice.runtime.default")
    }

    @Test
    func overlayReturnsBasePreferencesWhenPersonaSlotIsMissing() {
        var base = VoiceRuntimePreferences.default()
        base.persona = .calm
        base.preferredHubVoicePackID = "hub.voice.runtime.default"

        let effective = xtVoicePreferencesApplyingPersonaOverlay(base, personaSlot: nil)

        #expect(effective == base)
    }
}
