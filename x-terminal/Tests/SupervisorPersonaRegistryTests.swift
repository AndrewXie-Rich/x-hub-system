import Foundation
import Testing
@testable import XTerminal

struct SupervisorPersonaRegistryTests {

    @Test
    func normalizationRepairsInvalidPointersAndFillsSeedSlots() {
        let defaultVoice: VoicePersonaPreset = .calm
        var atlas = SupervisorPersonaSlot.seed(index: 1, defaultVoicePersona: defaultVoice)
        atlas.displayName = "  Atlas Prime  "
        atlas.roleSummary = "  Strategic partner for execution alignment.  "
        atlas.voicePackOverrideID = "  hub.voice.atlas  "

        let registry = SupervisorPersonaRegistry(
            schemaVersion: "legacy",
            defaultPersonaID: "missing_default",
            activePersonaID: "missing_active",
            slots: [atlas],
            updatedAtMs: -42
        ).normalized(defaultVoicePersona: defaultVoice)

        #expect(registry.schemaVersion == SupervisorPersonaRegistry.currentSchemaVersion)
        #expect(registry.slots.count == SupervisorPersonaRegistry.slotCount)
        #expect(registry.defaultPersonaID == "persona_slot_1")
        #expect(registry.activePersonaID == "persona_slot_1")
        #expect(registry.slot(for: "persona_slot_2")?.displayName == "Atlas Prime")
        #expect(registry.slot(for: "persona_slot_2")?.roleSummary == "Strategic partner for execution alignment.")
        #expect(registry.slot(for: "persona_slot_2")?.voicePackOverrideID == "hub.voice.atlas")
        #expect(registry.slot(for: "persona_slot_1")?.voicePersonaOverride == .calm)
        #expect(registry.updatedAtMs == 0)
    }

    @Test
    func normalizationKeepsSeedOrderWhenSlotsArriveOutOfOrder() {
        let defaultVoice: VoicePersonaPreset = .conversational
        var orbit = SupervisorPersonaSlot.seed(index: 3, defaultVoicePersona: defaultVoice)
        orbit.displayName = "Orbit"
        orbit.aliases = ["orbit", "轨道"]

        var supervisor = SupervisorPersonaSlot.seed(index: 0, defaultVoicePersona: defaultVoice)
        supervisor.displayName = "Control"

        let registry = SupervisorPersonaRegistry(
            schemaVersion: SupervisorPersonaRegistry.currentSchemaVersion,
            defaultPersonaID: orbit.personaID,
            activePersonaID: orbit.personaID,
            slots: [orbit, supervisor],
            updatedAtMs: 7
        ).normalized(defaultVoicePersona: defaultVoice)

        #expect(registry.slots.map(\.personaID) == [
            "persona_slot_1",
            "persona_slot_2",
            "persona_slot_3",
            "persona_slot_4",
            "persona_slot_5"
        ])
        #expect(registry.slots[0].displayName == "Control")
        #expect(registry.slots[3].displayName == "Orbit")
        #expect(registry.defaultPersonaID == "persona_slot_4")
        #expect(registry.activePersonaID == "persona_slot_4")
    }

    @Test
    func decodingLegacyPersonaSlotDefaultsMissingVoicePackOverride() throws {
        let json = #"""
        {
          "schema_version": "xt.supervisor_persona_slot.v1",
          "persona_id": "persona_slot_2",
          "display_name": "Atlas",
          "aliases": ["atlas"],
          "enabled": true,
          "identity_name": "Atlas",
          "role_summary": "Strategic partner.",
          "tone_directives": "Lead with the answer.",
          "extra_system_prompt": "",
          "preferred_user_name": "",
          "goals_summary": "",
          "work_style": "",
          "communication_preferences": "",
          "daily_rhythm": "",
          "review_preferences": "",
          "relationship_mode": "chief_of_staff",
          "briefing_style": "proactive",
          "risk_tolerance": "balanced",
          "interruption_tolerance": "high",
          "reminder_aggressiveness": "assertive",
          "preferred_morning_brief_time": "08:30",
          "preferred_evening_wrap_up_time": "18:30",
          "weekly_review_day": "Friday",
          "voice_persona_override": "briefing",
          "icon_token": "sparkles.rectangle.stack.fill",
          "accent_color_token": "persona_amber",
          "updated_at_ms": 7
        }
        """#

        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SupervisorPersonaSlot.self, from: data)

        #expect(decoded.voicePersonaOverride == .briefing)
        #expect(decoded.voicePackOverrideID.isEmpty)
    }

    @Test
    func settingTrimsVoicePackOverrideAndCanClearIt() {
        var slot = SupervisorPersonaSlot.seed(index: 0, defaultVoicePersona: .conversational)
        slot = slot.setting(
            voicePersonaOverride: .calm,
            preserveExistingVoiceOverride: false,
            voicePackOverrideID: "  hub.voice.zh.warm  ",
            preserveExistingVoicePackOverride: false
        )

        #expect(slot.voicePersonaOverride == .calm)
        #expect(slot.voicePackOverrideID == "hub.voice.zh.warm")

        slot = slot.setting(
            voicePackOverrideID: nil,
            preserveExistingVoicePackOverride: false
        )

        #expect(slot.voicePackOverrideID.isEmpty)
        #expect(slot.voicePersonaOverride == .calm)
    }
}
