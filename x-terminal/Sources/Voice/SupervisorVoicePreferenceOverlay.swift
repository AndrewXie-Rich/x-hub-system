import Foundation

func xtVoicePreferencesApplyingPersonaOverlay(
    _ base: VoiceRuntimePreferences,
    personaSlot: SupervisorPersonaSlot?
) -> VoiceRuntimePreferences {
    guard let personaSlot else { return base }

    var preferences = base
    if let voicePersonaOverride = personaSlot.voicePersonaOverride {
        preferences.persona = voicePersonaOverride
    }

    let voicePackOverrideID = personaSlot.voicePackOverrideID
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if !voicePackOverrideID.isEmpty {
        preferences.preferredHubVoicePackID = voicePackOverrideID
    }

    return preferences
}
