import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorPersonaRoutingTests {

    @Test
    func explicitPersonaMentionFeedsLocalDirectReplyAndPrompt() {
        let manager = SupervisorManager.makeForTesting()
        let appModel = AppModel()
        appModel.settingsStore.settings = .default()
        manager.setAppModel(appModel)

        let directReply = manager.directSupervisorReplyIfApplicableForTesting("Atlas，你是谁")
        let prompt = manager.buildSupervisorSystemPromptForTesting("Atlas，帮我看下今天最重要的事")

        #expect(directReply?.contains("Atlas Supervisor") == true)
        #expect(prompt.contains("You are Atlas Supervisor"))
    }

    @Test
    func sessionPersonaSwitchCarriesAcrossTurnsWithoutChangingDefault() {
        let manager = SupervisorManager.makeForTesting()
        let appModel = AppModel()
        appModel.settingsStore.settings = .default()
        manager.setAppModel(appModel)

        let reply = manager.supervisorPersonaRoutingReplyForTesting("接下来用 Atlas 跟我说话")
        let identityReply = manager.directSupervisorReplyIfApplicableForTesting("你是谁")

        #expect(reply?.contains("Atlas") == true)
        #expect(identityReply?.contains("Atlas Supervisor") == true)
        #expect(manager.supervisorPersonaStatusLineForTesting().contains("session") == true)
        #expect(appModel.settingsStore.settings.supervisorPersonaRegistry.defaultPersonaID == "persona_slot_1")
    }

    @Test
    func persistedDefaultSwitchUpdatesRegistryAndSubsequentReplies() {
        let manager = SupervisorManager.makeForTesting()
        let appModel = AppModel()
        appModel.settingsStore.settings = .default()
        manager.setAppModel(appModel)

        let reply = manager.supervisorPersonaRoutingReplyForTesting("以后默认用 Sage")
        let identityReply = manager.directSupervisorReplyIfApplicableForTesting("你是谁")

        #expect(reply?.contains("Sage") == true)
        #expect(appModel.settingsStore.settings.supervisorPersonaRegistry.defaultPersonaID == "persona_slot_4")
        #expect(appModel.settingsStore.settings.supervisorPersonaRegistry.activePersonaID == "persona_slot_4")
        #expect(identityReply?.contains("Sage") == true)
    }

    @Test
    func runtimeUsesPersonaSlotInsteadOfLegacyShadowFields() {
        let manager = SupervisorManager.makeForTesting()
        let appModel = AppModel()

        var registry = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)
        let activeID = registry.slots[2].personaID
        var slot = registry.slots[2]
        slot.displayName = "Echo"
        slot = slot.setting(
            prompt: SupervisorPromptPreferences(
                identityName: "Echo",
                roleSummary: "Deep context operator.",
                toneDirectives: "Lead with the answer.",
                extraSystemPrompt: ""
            )
        )
        registry = registry.setting(slot: slot)
        registry = registry.setting(activePersonaID: activeID)

        var settings = XTerminalSettings.default().setting(supervisorPersonaRegistry: registry)
        settings.supervisorPrompt = SupervisorPromptPreferences(
            identityName: "Stale Legacy Supervisor",
            roleSummary: "Old shadow field",
            toneDirectives: "",
            extraSystemPrompt: ""
        )
        appModel.settingsStore.settings = settings
        manager.setAppModel(appModel)

        let identityReply = manager.directSupervisorReplyIfApplicableForTesting("你是谁")
        let prompt = manager.buildSupervisorSystemPromptForTesting("帮我看下今天最重要的事")

        #expect(identityReply?.contains("Echo") == true)
        #expect(identityReply?.contains("Stale Legacy Supervisor") == false)
        #expect(prompt.contains("You are Echo"))
        #expect(prompt.contains("Stale Legacy Supervisor") == false)
    }

    @Test
    func voicePreferencesFollowCurrentExecutionPersonaOverlay() {
        let manager = SupervisorManager.makeForTesting()
        let appModel = AppModel()

        var registry = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)
        var atlas = registry.slots[1]
        atlas.voicePersonaOverride = .calm
        atlas.voicePackOverrideID = "hub.voice.persona.atlas"
        registry = registry.setting(slot: atlas)

        var settings = XTerminalSettings.default().setting(supervisorPersonaRegistry: registry)
        settings.voice.persona = .briefing
        settings.voice.preferredHubVoicePackID = "hub.voice.runtime.default"
        appModel.settingsStore.settings = settings
        manager.setAppModel(appModel)

        _ = manager.supervisorPersonaRoutingReplyForTesting("接下来用 Atlas 跟我说话")
        let effective = manager.currentVoicePreferencesForTesting()

        #expect(effective.persona == .calm)
        #expect(effective.preferredHubVoicePackID == "hub.voice.persona.atlas")
    }
}
