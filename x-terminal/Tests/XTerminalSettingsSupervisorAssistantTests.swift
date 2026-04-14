import Foundation
import Testing
@testable import XTerminal

struct XTerminalSettingsSupervisorAssistantTests {

    @Test
    func decodingLegacySettingsFallsBackToDefaultSupervisorAssistantConfig() throws {
        let legacyJSON = #"""
        {
          "schemaVersion": 4,
          "assignments": [],
          "openAICompatible": {
            "baseURL": "https://api.openai.com/",
            "model": "gpt-4o-mini"
          },
          "anthropic": {
            "baseURL": "https://api.anthropic.com/",
            "model": "claude-3-5-sonnet-latest"
          },
          "gemini": {
            "baseURL": "https://generativelanguage.googleapis.com/",
            "model": "gemini-1.5-pro"
          },
          "supervisorPrompt": {
            "identityName": "Supervisor",
            "roleSummary": "Supervisor AI",
            "toneDirectives": "",
            "extraSystemPrompt": ""
          },
          "voice": {
            "preferredRoute": "automatic",
            "wakeMode": "push_to_talk",
            "autoReportMode": "summary",
            "persona": "briefing",
            "interruptOnSpeech": true,
            "quietHours": {
              "enabled": false,
              "fromLocal": "22:00",
              "toLocal": "08:00"
            },
            "localeIdentifier": "zh-CN",
            "funASR": {
              "enabled": false,
              "transport": "websocket",
              "webSocketURL": "ws://127.0.0.1:10096",
              "wakeEnabled": true,
              "partialsEnabled": true
            }
          }
        }
        """#

        let data = try #require(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(XTerminalSettings.self, from: data)

        #expect(decoded.supervisorPersonalProfile == .default())
        #expect(decoded.supervisorPersonalPolicy == .default())
        #expect(decoded.supervisorWorkMode == .governedAutomation)
        #expect(decoded.supervisorPrivacyMode == .balanced)
        #expect(decoded.supervisorRecentRawContextProfile == .standard12Pairs)
        #expect(decoded.supervisorReviewMemoryDepthProfile == .auto)
        #expect(decoded.interfaceLanguage == .simplifiedChinese)
        #expect(decoded.supervisorPersonaRegistry.slots.count == SupervisorPersonaRegistry.slotCount)
        #expect(decoded.legacyPrimarySupervisorPersona.promptPreferences == decoded.supervisorPrompt)
        #expect(decoded.legacyPrimarySupervisorPersona.personalProfile == decoded.supervisorPersonalProfile)
        #expect(decoded.legacyPrimarySupervisorPersona.personalPolicy == decoded.supervisorPersonalPolicy)
        #expect(decoded.legacyPrimarySupervisorPersona.voicePersonaOverride == .briefing)
        #expect(decoded.voice.persona == .briefing)
        #expect(decoded.voice.timbre == .neutral)
        #expect(decoded.voice.speechRateMultiplier == 1.0)
        #expect(decoded.schemaVersion == 4)
    }

    @Test
    func settingSupervisorAssistantConfigNormalizesAndBumpsSchemaVersion() {
        let settings = XTerminalSettings.default()
            .setting(
                supervisorPersonalProfile: SupervisorPersonalProfile(
                    preferredName: " Andrew ",
                    goalsSummary: "  Keep shipping  ",
                    workStyle: " direct ",
                    communicationPreferences: " concise ",
                    dailyRhythm: " mornings ",
                    reviewPreferences: " friday "
                )
            )
            .setting(
                supervisorPersonalPolicy: SupervisorPersonalPolicy(
                    relationshipMode: .chiefOfStaff,
                    briefingStyle: .proactive,
                    riskTolerance: .aggressive,
                    interruptionTolerance: .high,
                    reminderAggressiveness: .assertive,
                    preferredMorningBriefTime: " 08:00 ",
                    preferredEveningWrapUpTime: " 19:00 ",
                    weeklyReviewDay: " Monday "
                )
            )

        #expect(settings.schemaVersion == XTerminalSettings.currentSchemaVersion)
        #expect(settings.supervisorPersonalProfile.preferredName == "Andrew")
        #expect(settings.supervisorPersonalProfile.goalsSummary == "Keep shipping")
        #expect(settings.supervisorPersonalPolicy.relationshipMode == .chiefOfStaff)
        #expect(settings.supervisorPersonalPolicy.preferredMorningBriefTime == "08:00")
        #expect(settings.supervisorPersonalPolicy.weeklyReviewDay == "Monday")
        #expect(settings.supervisorRecentRawContextProfile == .standard12Pairs)
        #expect(settings.supervisorReviewMemoryDepthProfile == .auto)
        #expect(settings.legacyPrimarySupervisorPersona.personalProfile == settings.supervisorPersonalProfile)
        #expect(settings.legacyPrimarySupervisorPersona.personalPolicy == settings.supervisorPersonalPolicy)
    }

    @Test
    func settingSupervisorRecentRawContextProfilePersistsOnSettings() throws {
        let settings = XTerminalSettings.default()
            .setting(supervisorRecentRawContextProfile: .extended40Pairs)

        #expect(settings.schemaVersion == XTerminalSettings.currentSchemaVersion)
        #expect(settings.supervisorRecentRawContextProfile == .extended40Pairs)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(XTerminalSettings.self, from: data)

        #expect(decoded.supervisorRecentRawContextProfile == .extended40Pairs)
    }

    @Test
    func settingSupervisorReviewMemoryDepthProfilePersistsOnSettings() throws {
        let settings = XTerminalSettings.default()
            .setting(supervisorReviewMemoryDepthProfile: .deepDive)

        #expect(settings.schemaVersion == XTerminalSettings.currentSchemaVersion)
        #expect(settings.supervisorReviewMemoryDepthProfile == .deepDive)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(XTerminalSettings.self, from: data)

        #expect(decoded.supervisorReviewMemoryDepthProfile == .deepDive)
    }

    @Test
    func interfaceLanguageDefaultsToSimplifiedChineseForNewAndLegacySettings() throws {
        let settings = XTerminalSettings.default()
        #expect(settings.interfaceLanguage == .simplifiedChinese)

        let legacyJSON = #"""
        {
          "schemaVersion": 10,
          "assignments": [],
          "openAICompatible": {
            "baseURL": "https://api.openai.com/",
            "model": "gpt-4o-mini"
          },
          "anthropic": {
            "baseURL": "https://api.anthropic.com/",
            "model": "claude-3-5-sonnet-latest"
          },
          "gemini": {
            "baseURL": "https://generativelanguage.googleapis.com/",
            "model": "gemini-1.5-pro"
          },
          "voice": {
            "preferredRoute": "automatic",
            "wakeMode": "push_to_talk",
            "autoReportMode": "summary",
            "persona": "briefing",
            "interruptOnSpeech": true,
            "quietHours": {
              "enabled": false,
              "fromLocal": "22:00",
              "toLocal": "08:00"
            },
            "localeIdentifier": "zh-CN",
            "funASR": {
              "enabled": false,
              "transport": "websocket",
              "webSocketURL": "ws://127.0.0.1:10096",
              "wakeEnabled": true,
              "partialsEnabled": true
            }
          }
        }
        """#

        let data = try #require(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(XTerminalSettings.self, from: data)
        #expect(decoded.interfaceLanguage == .simplifiedChinese)
        #expect(decoded.supervisorWorkMode == .guidedProgress)
    }

    @Test
    func settingInterfaceLanguagePersistsOnSettings() throws {
        let settings = XTerminalSettings.default()
            .setting(interfaceLanguage: .english)

        #expect(settings.schemaVersion == XTerminalSettings.currentSchemaVersion)
        #expect(settings.interfaceLanguage == .english)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(XTerminalSettings.self, from: data)

        #expect(decoded.interfaceLanguage == .english)
    }

    @Test
    func supervisorWorkModeDefaultsToGuidedProgressForNewSettings() {
        let settings = XTerminalSettings.default()

        #expect(settings.supervisorWorkMode == .guidedProgress)
    }

    @Test
    func settingSupervisorWorkModePersistsOnSettings() throws {
        let settings = XTerminalSettings.default()
            .setting(supervisorWorkMode: .conversationOnly)

        #expect(settings.schemaVersion == XTerminalSettings.currentSchemaVersion)
        #expect(settings.supervisorWorkMode == .conversationOnly)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(XTerminalSettings.self, from: data)

        #expect(decoded.supervisorWorkMode == .conversationOnly)
    }

    @Test
    func supervisorPrivacyModeDefaultsToBalancedForNewSettings() {
        let settings = XTerminalSettings.default()

        #expect(settings.supervisorPrivacyMode == .balanced)
    }

    @Test
    func settingSupervisorPrivacyModePersistsOnSettings() throws {
        let settings = XTerminalSettings.default()
            .setting(supervisorPrivacyMode: .tightenedContext)

        #expect(settings.schemaVersion == XTerminalSettings.currentSchemaVersion)
        #expect(settings.supervisorPrivacyMode == .tightenedContext)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(XTerminalSettings.self, from: data)

        #expect(decoded.supervisorPrivacyMode == .tightenedContext)
    }

    @Test
    func calendarReminderSettingsDefaultToXtOwnedMeetingReminderProfile() {
        let settings = XTerminalSettings.default()

        #expect(settings.supervisorCalendarReminders.enabled == false)
        #expect(settings.supervisorCalendarReminders.headsUpMinutes == 15)
        #expect(settings.supervisorCalendarReminders.finalCallMinutes == 3)
        #expect(settings.supervisorCalendarReminders.notificationFallbackEnabled == true)
    }

    @Test
    func settingCalendarReminderPreferencesNormalizesAndPersists() throws {
        let settings = XTerminalSettings.default().setting(
            supervisorCalendarReminders: SupervisorCalendarReminderPreferences(
                enabled: true,
                headsUpMinutes: 180,
                finalCallMinutes: 80,
                notificationFallbackEnabled: false
            )
        )

        #expect(settings.schemaVersion == XTerminalSettings.currentSchemaVersion)
        #expect(settings.supervisorCalendarReminders.enabled == true)
        #expect(settings.supervisorCalendarReminders.headsUpMinutes == 120)
        #expect(settings.supervisorCalendarReminders.finalCallMinutes == 80)
        #expect(settings.supervisorCalendarReminders.notificationFallbackEnabled == false)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(XTerminalSettings.self, from: data)

        #expect(decoded.supervisorCalendarReminders == settings.supervisorCalendarReminders)
    }

    @Test
    func decodingPersonaRegistryRehydratesLegacyShadowFieldsFromActivePersona() throws {
        let registryJSON = #"""
        {
          "schemaVersion": 6,
          "assignments": [],
          "openAICompatible": {
            "baseURL": "https://api.openai.com/",
            "model": "gpt-4o-mini"
          },
          "anthropic": {
            "baseURL": "https://api.anthropic.com/",
            "model": "claude-3-5-sonnet-latest"
          },
          "gemini": {
            "baseURL": "https://generativelanguage.googleapis.com/",
            "model": "gemini-1.5-pro"
          },
          "voice": {
            "preferredRoute": "automatic",
            "wakeMode": "push_to_talk",
            "autoReportMode": "summary",
            "persona": "conversational",
            "interruptOnSpeech": true,
            "quietHours": {
              "enabled": false,
              "fromLocal": "22:00",
              "toLocal": "08:00"
            },
            "localeIdentifier": "zh-CN",
            "funASR": {
              "enabled": false,
              "transport": "websocket",
              "webSocketURL": "ws://127.0.0.1:10096",
              "wakeEnabled": true,
              "partialsEnabled": true
            }
          },
          "supervisorPrompt": {
            "identityName": "Stale Prompt",
            "roleSummary": "Stale",
            "toneDirectives": "",
            "extraSystemPrompt": ""
          },
          "supervisorPersonalProfile": {
            "preferredName": "",
            "goalsSummary": "",
            "workStyle": "",
            "communicationPreferences": "",
            "dailyRhythm": "",
            "reviewPreferences": ""
          },
          "supervisorPersonalPolicy": {
            "relationshipMode": "operator_partner",
            "briefingStyle": "balanced",
            "riskTolerance": "balanced",
            "interruptionTolerance": "balanced",
            "reminderAggressiveness": "balanced",
            "preferredMorningBriefTime": "09:00",
            "preferredEveningWrapUpTime": "18:00",
            "weeklyReviewDay": "Sunday"
          },
          "supervisorPersonaRegistry": {
            "schema_version": "xt.supervisor_persona_registry.v1",
            "default_persona_id": "persona_slot_1",
            "active_persona_id": "persona_slot_2",
            "updated_at_ms": 42,
            "slots": [
              {
                "schema_version": "xt.supervisor_persona_slot.v1",
                "persona_id": "persona_slot_1",
                "display_name": "Supervisor",
                "aliases": ["supervisor"],
                "enabled": true,
                "identity_name": "Supervisor",
                "role_summary": "Supervisor AI for project orchestration, model routing, and execution coordination.",
                "tone_directives": "",
                "extra_system_prompt": "",
                "preferred_user_name": "",
                "goals_summary": "",
                "work_style": "",
                "communication_preferences": "",
                "daily_rhythm": "",
                "review_preferences": "",
                "relationship_mode": "operator_partner",
                "briefing_style": "balanced",
                "risk_tolerance": "balanced",
                "interruption_tolerance": "balanced",
                "reminder_aggressiveness": "balanced",
                "preferred_morning_brief_time": "09:00",
                "preferred_evening_wrap_up_time": "18:00",
                "weekly_review_day": "Sunday",
                "voice_persona_override": "conversational",
                "icon_token": "person.crop.circle.fill",
                "accent_color_token": "persona_blue",
                "updated_at_ms": 0
              },
              {
                "schema_version": "xt.supervisor_persona_slot.v1",
                "persona_id": "persona_slot_2",
                "display_name": "Mira",
                "aliases": ["mira", "米拉"],
                "enabled": true,
                "identity_name": "Mira",
                "role_summary": "Personal chief of staff.",
                "tone_directives": "Be direct.",
                "extra_system_prompt": "Remember family logistics.",
                "preferred_user_name": "Andrew",
                "goals_summary": "Keep shipping.",
                "work_style": "Fast loops.",
                "communication_preferences": "Short updates.",
                "daily_rhythm": "Morning maker blocks.",
                "review_preferences": "Friday weekly review.",
                "relationship_mode": "chief_of_staff",
                "briefing_style": "proactive",
                "risk_tolerance": "aggressive",
                "interruption_tolerance": "high",
                "reminder_aggressiveness": "assertive",
                "preferred_morning_brief_time": "08:00",
                "preferred_evening_wrap_up_time": "20:00",
                "weekly_review_day": "Friday",
                "voice_persona_override": "calm",
                "icon_token": "star.fill",
                "accent_color_token": "persona_gold",
                "updated_at_ms": 1
              }
            ]
          }
        }
        """#

        let data = try #require(registryJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(XTerminalSettings.self, from: data)

        #expect(decoded.supervisorPrompt.identityName == "Mira")
        #expect(decoded.supervisorPrompt.roleSummary == "Personal chief of staff.")
        #expect(decoded.supervisorPersonalProfile.preferredName == "Andrew")
        #expect(decoded.supervisorPersonalPolicy.relationshipMode == .chiefOfStaff)
        #expect(decoded.supervisorPersonalPolicy.briefingStyle == .proactive)
        #expect(decoded.voice.persona == .calm)
        #expect(decoded.voice.timbre == .neutral)
        #expect(decoded.voice.speechRateMultiplier == 1.0)
        #expect(decoded.legacyPrimarySupervisorPersona.displayName == "Mira")
    }

    @Test
    func legacySettersUpdatePrimaryPersonaRegistrySlot() {
        let prompt = SupervisorPromptPreferences(
            identityName: "Nora",
            roleSummary: "Project and life operator.",
            toneDirectives: "Be crisp.",
            extraSystemPrompt: "Track family errands."
        )
        let profile = SupervisorPersonalProfile(
            preferredName: "Andrew",
            goalsSummary: "Ship the next release.",
            workStyle: "Fast and direct.",
            communicationPreferences: "Keep it brief.",
            dailyRhythm: "Protect mornings.",
            reviewPreferences: "Review every Friday."
        )
        let policy = SupervisorPersonalPolicy(
            relationshipMode: .chiefOfStaff,
            briefingStyle: .proactive,
            riskTolerance: .aggressive,
            interruptionTolerance: .high,
            reminderAggressiveness: .assertive,
            preferredMorningBriefTime: "08:15",
            preferredEveningWrapUpTime: "19:30",
            weeklyReviewDay: "Friday"
        )
        let voice = VoiceRuntimePreferences(
            preferredRoute: .automatic,
            playbackPreference: .automatic,
            wakeMode: .pushToTalk,
            autoReportMode: .summary,
            persona: .briefing,
            timbre: .neutral,
            preferredHubVoicePackID: "",
            speechRateMultiplier: 1.0,
            interruptOnSpeech: true,
            quietHours: .default(),
            localeIdentifier: "zh-CN",
            funASR: .default()
        )

        let settings = XTerminalSettings.default()
            .setting(supervisorPrompt: prompt)
            .setting(supervisorPersonalProfile: profile)
            .setting(supervisorPersonalPolicy: policy)
            .setting(voice: voice)

        #expect(settings.supervisorPrompt == prompt.normalized())
        #expect(settings.supervisorPersonalProfile == profile.normalized())
        #expect(settings.supervisorPersonalPolicy == policy.normalized())
        #expect(settings.voice.persona == .briefing)
        #expect(settings.legacyPrimarySupervisorPersona.displayName == "Nora")
        #expect(settings.legacyPrimarySupervisorPersona.promptPreferences == prompt.normalized())
        #expect(settings.legacyPrimarySupervisorPersona.personalProfile == profile.normalized())
        #expect(settings.legacyPrimarySupervisorPersona.personalPolicy == policy.normalized())
        #expect(settings.legacyPrimarySupervisorPersona.voicePersonaOverride == .briefing)
    }

    @Test
    func settingPersonaRegistryUpdatesLegacyShadowFields() {
        var registry = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)
        let activeID = registry.slots[2].personaID
        var slot = registry.slots[2]
        slot.displayName = "Echo"
        slot = slot.setting(
            prompt: SupervisorPromptPreferences(
                identityName: "Echo",
                roleSummary: "Deep context partner.",
                toneDirectives: "Lead with the answer.",
                extraSystemPrompt: "Prefer long-horizon tradeoffs."
            ),
            personalProfile: SupervisorPersonalProfile(
                preferredName: "Andrew",
                goalsSummary: "Scale the system.",
                workStyle: "Long uninterrupted blocks.",
                communicationPreferences: "Call out tradeoffs.",
                dailyRhythm: "Late afternoon sync.",
                reviewPreferences: "Sunday reset."
            ),
            personalPolicy: SupervisorPersonalPolicy(
                relationshipMode: .coach,
                briefingStyle: .balanced,
                riskTolerance: .balanced,
                interruptionTolerance: .low,
                reminderAggressiveness: .quiet,
                preferredMorningBriefTime: "10:00",
                preferredEveningWrapUpTime: "21:00",
                weeklyReviewDay: "Sunday"
            ),
            voicePersonaOverride: .calm,
            preserveExistingVoiceOverride: false
        )
        registry = registry.setting(slot: slot)
        registry = registry.setting(activePersonaID: activeID)

        let settings = XTerminalSettings.default().setting(supervisorPersonaRegistry: registry)

        #expect(settings.supervisorPrompt.identityName == "Echo")
        #expect(settings.supervisorPersonalProfile.preferredName == "Andrew")
        #expect(settings.supervisorPersonalPolicy.relationshipMode == .coach)
        #expect(settings.voice.persona == .calm)
        #expect(settings.legacyPrimarySupervisorPersona.personaID == activeID)
    }
}
