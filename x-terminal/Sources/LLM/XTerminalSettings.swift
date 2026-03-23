import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case hub
    case openai_compatible
    case anthropic
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hub: return "Hub"
        case .openai_compatible: return "OpenAI"
        case .anthropic: return "Claude"
        case .gemini: return "Gemini"
        }
    }
}

struct RoleProviderAssignment: Codable, Equatable {
    var role: AXRole
    var providerKind: ProviderKind
    var model: String?
}

struct OpenAICompatibleConfig: Codable, Equatable {
    var baseURL: String
    var model: String
}

struct AnthropicConfig: Codable, Equatable {
    var baseURL: String
    var model: String
}

struct GeminiConfig: Codable, Equatable {
    var baseURL: String
    var model: String
}

struct SupervisorCalendarReminderPreferences: Codable, Equatable {
    var enabled: Bool
    var headsUpMinutes: Int
    var finalCallMinutes: Int
    var notificationFallbackEnabled: Bool

    init(
        enabled: Bool = false,
        headsUpMinutes: Int = 15,
        finalCallMinutes: Int = 3,
        notificationFallbackEnabled: Bool = true
    ) {
        let resolvedHeadsUpMinutes = max(5, min(120, headsUpMinutes))
        let resolvedFinalCallMinutes = max(1, min(resolvedHeadsUpMinutes - 1, finalCallMinutes))
        self.enabled = enabled
        self.headsUpMinutes = resolvedHeadsUpMinutes
        self.finalCallMinutes = resolvedFinalCallMinutes
        self.notificationFallbackEnabled = notificationFallbackEnabled
    }

    static func `default`() -> SupervisorCalendarReminderPreferences {
        SupervisorCalendarReminderPreferences()
    }

    func normalized() -> SupervisorCalendarReminderPreferences {
        SupervisorCalendarReminderPreferences(
            enabled: enabled,
            headsUpMinutes: headsUpMinutes,
            finalCallMinutes: finalCallMinutes,
            notificationFallbackEnabled: notificationFallbackEnabled
        )
    }
}

struct XTerminalSettings: Codable, Equatable {
    static let currentSchemaVersion = 10

    var schemaVersion: Int

    // Role -> provider selection.
    var assignments: [RoleProviderAssignment]

    // Provider configs.
    var openAICompatible: OpenAICompatibleConfig
    var anthropic: AnthropicConfig
    var gemini: GeminiConfig
    var voice: VoiceRuntimePreferences
    var supervisorPrompt: SupervisorPromptPreferences
    var supervisorPersonalProfile: SupervisorPersonalProfile
    var supervisorPersonalPolicy: SupervisorPersonalPolicy
    var supervisorWorkMode: XTSupervisorWorkMode
    var supervisorPrivacyMode: XTPrivacyMode
    var supervisorCalendarReminders: SupervisorCalendarReminderPreferences
    var supervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile
    var supervisorPersonaRegistry: SupervisorPersonaRegistry

    init(
        schemaVersion: Int,
        assignments: [RoleProviderAssignment],
        openAICompatible: OpenAICompatibleConfig,
        anthropic: AnthropicConfig,
        gemini: GeminiConfig,
        voice: VoiceRuntimePreferences,
        supervisorPrompt: SupervisorPromptPreferences,
        supervisorPersonalProfile: SupervisorPersonalProfile,
        supervisorPersonalPolicy: SupervisorPersonalPolicy,
        supervisorWorkMode: XTSupervisorWorkMode = .defaultMode,
        supervisorPrivacyMode: XTPrivacyMode = .defaultMode,
        supervisorCalendarReminders: SupervisorCalendarReminderPreferences = .default(),
        supervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile = .defaultProfile,
        supervisorPersonaRegistry: SupervisorPersonaRegistry? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.assignments = Self.assignmentsEnsuringAllRoles(assignments)
        self.openAICompatible = openAICompatible
        self.anthropic = anthropic
        self.gemini = gemini
        let synchronized = Self.synchronizedSupervisorState(
            voice: voice,
            supervisorPrompt: supervisorPrompt,
            supervisorPersonalProfile: supervisorPersonalProfile,
            supervisorPersonalPolicy: supervisorPersonalPolicy,
            supervisorPersonaRegistry: supervisorPersonaRegistry
        )
        self.voice = synchronized.voice
        self.supervisorPrompt = synchronized.supervisorPrompt
        self.supervisorPersonalProfile = synchronized.supervisorPersonalProfile
        self.supervisorPersonalPolicy = synchronized.supervisorPersonalPolicy
        self.supervisorWorkMode = supervisorWorkMode
        self.supervisorPrivacyMode = supervisorPrivacyMode
        self.supervisorCalendarReminders = supervisorCalendarReminders.normalized()
        self.supervisorRecentRawContextProfile = supervisorRecentRawContextProfile
        self.supervisorPersonaRegistry = synchronized.supervisorPersonaRegistry
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? Self.currentSchemaVersion
        assignments = Self.assignmentsEnsuringAllRoles(
            (try? c.decode([RoleProviderAssignment].self, forKey: .assignments)) ?? []
        )
        openAICompatible = (try? c.decode(OpenAICompatibleConfig.self, forKey: .openAICompatible)) ?? OpenAICompatibleConfig(baseURL: "https://api.openai.com/", model: "gpt-4o-mini")
        anthropic = (try? c.decode(AnthropicConfig.self, forKey: .anthropic)) ?? AnthropicConfig(baseURL: "https://api.anthropic.com/", model: "claude-3-5-sonnet-latest")
        gemini = (try? c.decode(GeminiConfig.self, forKey: .gemini)) ?? GeminiConfig(baseURL: "https://generativelanguage.googleapis.com/", model: "gemini-1.5-pro")
        let decodedVoice = (try? c.decode(VoiceRuntimePreferences.self, forKey: .voice)) ?? .default()
        let decodedPrompt = ((try? c.decode(SupervisorPromptPreferences.self, forKey: .supervisorPrompt)) ?? .default()).normalized()
        let decodedProfile = ((try? c.decode(SupervisorPersonalProfile.self, forKey: .supervisorPersonalProfile)) ?? .default()).normalized()
        let decodedPolicy = ((try? c.decode(SupervisorPersonalPolicy.self, forKey: .supervisorPersonalPolicy)) ?? .default()).normalized()
        supervisorWorkMode = (try? c.decode(
            XTSupervisorWorkMode.self,
            forKey: .supervisorWorkMode
        )) ?? Self.defaultSupervisorWorkMode(forDecodedSchemaVersion: schemaVersion)
        supervisorPrivacyMode = (try? c.decode(
            XTPrivacyMode.self,
            forKey: .supervisorPrivacyMode
        )) ?? .defaultMode
        supervisorCalendarReminders = ((try? c.decode(
            SupervisorCalendarReminderPreferences.self,
            forKey: .supervisorCalendarReminders
        )) ?? .default()).normalized()
        supervisorRecentRawContextProfile = (try? c.decode(
            XTSupervisorRecentRawContextProfile.self,
            forKey: .supervisorRecentRawContextProfile
        )) ?? .defaultProfile
        let decodedRegistry = try? c.decode(SupervisorPersonaRegistry.self, forKey: .supervisorPersonaRegistry)
        let synchronized = Self.synchronizedSupervisorState(
            voice: decodedVoice,
            supervisorPrompt: decodedPrompt,
            supervisorPersonalProfile: decodedProfile,
            supervisorPersonalPolicy: decodedPolicy,
            supervisorPersonaRegistry: decodedRegistry
        )
        voice = synchronized.voice
        supervisorPrompt = synchronized.supervisorPrompt
        supervisorPersonalProfile = synchronized.supervisorPersonalProfile
        supervisorPersonalPolicy = synchronized.supervisorPersonalPolicy
        supervisorPersonaRegistry = synchronized.supervisorPersonaRegistry
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case assignments
        case openAICompatible
        case anthropic
        case gemini
        case voice
        case supervisorPrompt
        case supervisorPersonalProfile
        case supervisorPersonalPolicy
        case supervisorWorkMode
        case supervisorPrivacyMode
        case supervisorCalendarReminders
        case supervisorRecentRawContextProfile
        case supervisorPersonaRegistry
    }

    static func `default`() -> XTerminalSettings {
        XTerminalSettings(
            schemaVersion: currentSchemaVersion,
            assignments: [
                RoleProviderAssignment(role: .coder, providerKind: .hub, model: nil),
                RoleProviderAssignment(role: .coarse, providerKind: .hub, model: nil),
                RoleProviderAssignment(role: .refine, providerKind: .hub, model: nil),
                RoleProviderAssignment(role: .reviewer, providerKind: .hub, model: nil),
                RoleProviderAssignment(role: .advisor, providerKind: .hub, model: nil),
                RoleProviderAssignment(role: .supervisor, providerKind: .hub, model: nil),
            ],
            openAICompatible: OpenAICompatibleConfig(baseURL: "https://api.openai.com/", model: "gpt-4o-mini"),
            anthropic: AnthropicConfig(baseURL: "https://api.anthropic.com/", model: "claude-3-5-sonnet-latest"),
            gemini: GeminiConfig(baseURL: "https://generativelanguage.googleapis.com/", model: "gemini-1.5-pro"),
            voice: .default(),
            supervisorPrompt: .default(),
            supervisorPersonalProfile: .default(),
            supervisorPersonalPolicy: .default(),
            supervisorWorkMode: .defaultMode,
            supervisorPrivacyMode: .defaultMode,
            supervisorCalendarReminders: .default(),
            supervisorRecentRawContextProfile: .defaultProfile,
            supervisorPersonaRegistry: SupervisorPersonaRegistry.default(
                defaultVoicePersona: VoiceRuntimePreferences.default().persona
            )
        )
    }

    func assignment(for role: AXRole) -> RoleProviderAssignment {
        assignments.first(where: { $0.role == role }) ?? RoleProviderAssignment(role: role, providerKind: .hub, model: nil)
    }

    func setting(role: AXRole, providerKind: ProviderKind, model: String?) -> XTerminalSettings {
        var s = self
        s.schemaVersion = Self.currentSchemaVersion
        var arr = s.assignments
        if let idx = arr.firstIndex(where: { $0.role == role }) {
            arr[idx] = RoleProviderAssignment(role: role, providerKind: providerKind, model: model)
        } else {
            arr.append(RoleProviderAssignment(role: role, providerKind: providerKind, model: model))
        }
        s.assignments = arr
        return s
    }

    var legacyPrimarySupervisorPersona: SupervisorPersonaSlot {
        supervisorPersonaRegistry.legacyPrimaryPersona
    }

    func setting(voice: VoiceRuntimePreferences) -> XTerminalSettings {
        let updatedRegistry = updatingLegacyPrimaryPersona { slot in
            slot.setting(
                voicePersonaOverride: voice.persona,
                preserveExistingVoiceOverride: false
            )
        }
        return XTerminalSettings(
            schemaVersion: Self.currentSchemaVersion,
            assignments: assignments,
            openAICompatible: openAICompatible,
            anthropic: anthropic,
            gemini: gemini,
            voice: voice,
            supervisorPrompt: supervisorPrompt,
            supervisorPersonalProfile: supervisorPersonalProfile,
            supervisorPersonalPolicy: supervisorPersonalPolicy,
            supervisorWorkMode: supervisorWorkMode,
            supervisorPrivacyMode: supervisorPrivacyMode,
            supervisorCalendarReminders: supervisorCalendarReminders,
            supervisorRecentRawContextProfile: supervisorRecentRawContextProfile,
            supervisorPersonaRegistry: updatedRegistry
        )
    }

    func setting(supervisorPrompt: SupervisorPromptPreferences) -> XTerminalSettings {
        let normalized = supervisorPrompt.normalized()
        let updatedRegistry = updatingLegacyPrimaryPersona { slot in
            var updated = slot.setting(prompt: normalized)
            let trimmedName = normalized.identityName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                updated.displayName = trimmedName
                if updated.aliases.isEmpty {
                    updated.aliases = [trimmedName]
                }
            }
            return updated
        }
        return XTerminalSettings(
            schemaVersion: Self.currentSchemaVersion,
            assignments: assignments,
            openAICompatible: openAICompatible,
            anthropic: anthropic,
            gemini: gemini,
            voice: voice,
            supervisorPrompt: normalized,
            supervisorPersonalProfile: supervisorPersonalProfile,
            supervisorPersonalPolicy: supervisorPersonalPolicy,
            supervisorWorkMode: supervisorWorkMode,
            supervisorPrivacyMode: supervisorPrivacyMode,
            supervisorCalendarReminders: supervisorCalendarReminders,
            supervisorRecentRawContextProfile: supervisorRecentRawContextProfile,
            supervisorPersonaRegistry: updatedRegistry
        )
    }

    func setting(supervisorPersonalProfile: SupervisorPersonalProfile) -> XTerminalSettings {
        let normalized = supervisorPersonalProfile.normalized()
        let updatedRegistry = updatingLegacyPrimaryPersona { slot in
            slot.setting(personalProfile: normalized)
        }
        return XTerminalSettings(
            schemaVersion: Self.currentSchemaVersion,
            assignments: assignments,
            openAICompatible: openAICompatible,
            anthropic: anthropic,
            gemini: gemini,
            voice: voice,
            supervisorPrompt: supervisorPrompt,
            supervisorPersonalProfile: normalized,
            supervisorPersonalPolicy: supervisorPersonalPolicy,
            supervisorWorkMode: supervisorWorkMode,
            supervisorPrivacyMode: supervisorPrivacyMode,
            supervisorCalendarReminders: supervisorCalendarReminders,
            supervisorRecentRawContextProfile: supervisorRecentRawContextProfile,
            supervisorPersonaRegistry: updatedRegistry
        )
    }

    func setting(supervisorPersonalPolicy: SupervisorPersonalPolicy) -> XTerminalSettings {
        let normalized = supervisorPersonalPolicy.normalized()
        let updatedRegistry = updatingLegacyPrimaryPersona { slot in
            slot.setting(personalPolicy: normalized)
        }
        return XTerminalSettings(
            schemaVersion: Self.currentSchemaVersion,
            assignments: assignments,
            openAICompatible: openAICompatible,
            anthropic: anthropic,
            gemini: gemini,
            voice: voice,
            supervisorPrompt: supervisorPrompt,
            supervisorPersonalProfile: supervisorPersonalProfile,
            supervisorPersonalPolicy: normalized,
            supervisorWorkMode: supervisorWorkMode,
            supervisorPrivacyMode: supervisorPrivacyMode,
            supervisorCalendarReminders: supervisorCalendarReminders,
            supervisorRecentRawContextProfile: supervisorRecentRawContextProfile,
            supervisorPersonaRegistry: updatedRegistry
        )
    }

    func setting(supervisorWorkMode: XTSupervisorWorkMode) -> XTerminalSettings {
        XTerminalSettings(
            schemaVersion: Self.currentSchemaVersion,
            assignments: assignments,
            openAICompatible: openAICompatible,
            anthropic: anthropic,
            gemini: gemini,
            voice: voice,
            supervisorPrompt: supervisorPrompt,
            supervisorPersonalProfile: supervisorPersonalProfile,
            supervisorPersonalPolicy: supervisorPersonalPolicy,
            supervisorWorkMode: supervisorWorkMode,
            supervisorPrivacyMode: supervisorPrivacyMode,
            supervisorCalendarReminders: supervisorCalendarReminders,
            supervisorRecentRawContextProfile: supervisorRecentRawContextProfile,
            supervisorPersonaRegistry: supervisorPersonaRegistry
        )
    }

    func setting(supervisorPrivacyMode: XTPrivacyMode) -> XTerminalSettings {
        XTerminalSettings(
            schemaVersion: Self.currentSchemaVersion,
            assignments: assignments,
            openAICompatible: openAICompatible,
            anthropic: anthropic,
            gemini: gemini,
            voice: voice,
            supervisorPrompt: supervisorPrompt,
            supervisorPersonalProfile: supervisorPersonalProfile,
            supervisorPersonalPolicy: supervisorPersonalPolicy,
            supervisorWorkMode: supervisorWorkMode,
            supervisorPrivacyMode: supervisorPrivacyMode,
            supervisorCalendarReminders: supervisorCalendarReminders,
            supervisorRecentRawContextProfile: supervisorRecentRawContextProfile,
            supervisorPersonaRegistry: supervisorPersonaRegistry
        )
    }

    func setting(
        supervisorCalendarReminders: SupervisorCalendarReminderPreferences
    ) -> XTerminalSettings {
        XTerminalSettings(
            schemaVersion: Self.currentSchemaVersion,
            assignments: assignments,
            openAICompatible: openAICompatible,
            anthropic: anthropic,
            gemini: gemini,
            voice: voice,
            supervisorPrompt: supervisorPrompt,
            supervisorPersonalProfile: supervisorPersonalProfile,
            supervisorPersonalPolicy: supervisorPersonalPolicy,
            supervisorWorkMode: supervisorWorkMode,
            supervisorPrivacyMode: supervisorPrivacyMode,
            supervisorCalendarReminders: supervisorCalendarReminders,
            supervisorRecentRawContextProfile: supervisorRecentRawContextProfile,
            supervisorPersonaRegistry: supervisorPersonaRegistry
        )
    }

    func setting(
        supervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile
    ) -> XTerminalSettings {
        XTerminalSettings(
            schemaVersion: Self.currentSchemaVersion,
            assignments: assignments,
            openAICompatible: openAICompatible,
            anthropic: anthropic,
            gemini: gemini,
            voice: voice,
            supervisorPrompt: supervisorPrompt,
            supervisorPersonalProfile: supervisorPersonalProfile,
            supervisorPersonalPolicy: supervisorPersonalPolicy,
            supervisorWorkMode: supervisorWorkMode,
            supervisorPrivacyMode: supervisorPrivacyMode,
            supervisorCalendarReminders: supervisorCalendarReminders,
            supervisorRecentRawContextProfile: supervisorRecentRawContextProfile,
            supervisorPersonaRegistry: supervisorPersonaRegistry
        )
    }

    func setting(supervisorPersonaRegistry: SupervisorPersonaRegistry) -> XTerminalSettings {
        XTerminalSettings(
            schemaVersion: Self.currentSchemaVersion,
            assignments: assignments,
            openAICompatible: openAICompatible,
            anthropic: anthropic,
            gemini: gemini,
            voice: voice,
            supervisorPrompt: supervisorPrompt,
            supervisorPersonalProfile: supervisorPersonalProfile,
            supervisorPersonalPolicy: supervisorPersonalPolicy,
            supervisorWorkMode: supervisorWorkMode,
            supervisorPrivacyMode: supervisorPrivacyMode,
            supervisorCalendarReminders: supervisorCalendarReminders,
            supervisorRecentRawContextProfile: supervisorRecentRawContextProfile,
            supervisorPersonaRegistry: supervisorPersonaRegistry
        )
    }

    func normalizedForPersistence() -> XTerminalSettings {
        XTerminalSettings(
            schemaVersion: Self.currentSchemaVersion,
            assignments: assignments,
            openAICompatible: openAICompatible,
            anthropic: anthropic,
            gemini: gemini,
            voice: voice,
            supervisorPrompt: supervisorPrompt,
            supervisorPersonalProfile: supervisorPersonalProfile,
            supervisorPersonalPolicy: supervisorPersonalPolicy,
            supervisorWorkMode: supervisorWorkMode,
            supervisorPrivacyMode: supervisorPrivacyMode,
            supervisorCalendarReminders: supervisorCalendarReminders,
            supervisorRecentRawContextProfile: supervisorRecentRawContextProfile,
            supervisorPersonaRegistry: supervisorPersonaRegistry
        )
    }

    private func updatingLegacyPrimaryPersona(
        _ transform: (SupervisorPersonaSlot) -> SupervisorPersonaSlot
    ) -> SupervisorPersonaRegistry {
        supervisorPersonaRegistry.setting(slot: transform(legacyPrimarySupervisorPersona))
    }

    private static func assignmentsEnsuringAllRoles(
        _ assignments: [RoleProviderAssignment]
    ) -> [RoleProviderAssignment] {
        var output = assignments
        for role in AXRole.allCases where !output.contains(where: { $0.role == role }) {
            output.append(RoleProviderAssignment(role: role, providerKind: .hub, model: nil))
        }
        return output
    }

    private static func defaultSupervisorWorkMode(
        forDecodedSchemaVersion schemaVersion: Int
    ) -> XTSupervisorWorkMode {
        schemaVersion < Self.currentSchemaVersion ? .governedAutomation : .defaultMode
    }

    private static func synchronizedSupervisorState(
        voice: VoiceRuntimePreferences,
        supervisorPrompt: SupervisorPromptPreferences,
        supervisorPersonalProfile: SupervisorPersonalProfile,
        supervisorPersonalPolicy: SupervisorPersonalPolicy,
        supervisorPersonaRegistry: SupervisorPersonaRegistry?
    ) -> SynchronizedSupervisorState {
        let normalizedPrompt = supervisorPrompt.normalized()
        let normalizedProfile = supervisorPersonalProfile.normalized()
        let normalizedPolicy = supervisorPersonalPolicy.normalized()

        let resolvedRegistry = (supervisorPersonaRegistry
            ?? SupervisorPersonaRegistry.seededFromLegacy(
                prompt: normalizedPrompt,
                personalProfile: normalizedProfile,
                personalPolicy: normalizedPolicy,
                defaultVoicePersona: voice.persona
            ))
            .normalized(defaultVoicePersona: voice.persona)

        let primaryPersona = resolvedRegistry.legacyPrimaryPersona
        let resolvedVoicePersona = primaryPersona.voicePersonaOverride ?? voice.persona
        let synchronizedPrimaryPersona = primaryPersona.setting(
            voicePersonaOverride: resolvedVoicePersona,
            preserveExistingVoiceOverride: false
        )
        let synchronizedRegistry = resolvedRegistry
            .setting(slot: synchronizedPrimaryPersona)
            .normalized(defaultVoicePersona: resolvedVoicePersona)

        var synchronizedVoice = voice
        synchronizedVoice.persona = resolvedVoicePersona

        return SynchronizedSupervisorState(
            voice: synchronizedVoice,
            supervisorPrompt: synchronizedPrimaryPersona.promptPreferences,
            supervisorPersonalProfile: synchronizedPrimaryPersona.personalProfile,
            supervisorPersonalPolicy: synchronizedPrimaryPersona.personalPolicy,
            supervisorPersonaRegistry: synchronizedRegistry
        )
    }

    private struct SynchronizedSupervisorState {
        var voice: VoiceRuntimePreferences
        var supervisorPrompt: SupervisorPromptPreferences
        var supervisorPersonalProfile: SupervisorPersonalProfile
        var supervisorPersonalPolicy: SupervisorPersonalPolicy
        var supervisorPersonaRegistry: SupervisorPersonaRegistry
    }
}
