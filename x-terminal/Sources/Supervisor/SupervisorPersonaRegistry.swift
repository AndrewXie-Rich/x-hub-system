import Foundation

struct SupervisorPersonaSlot: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = "xt.supervisor_persona_slot.v1"

    var schemaVersion: String
    var personaID: String
    var displayName: String
    var aliases: [String]
    var enabled: Bool
    var identityName: String
    var roleSummary: String
    var toneDirectives: String
    var extraSystemPrompt: String
    var preferredUserName: String
    var goalsSummary: String
    var workStyle: String
    var communicationPreferences: String
    var dailyRhythm: String
    var reviewPreferences: String
    var relationshipMode: SupervisorRelationshipMode
    var briefingStyle: SupervisorBriefingStyle
    var riskTolerance: SupervisorPersonalRiskTolerance
    var interruptionTolerance: SupervisorInterruptionTolerance
    var reminderAggressiveness: SupervisorReminderAggressiveness
    var preferredMorningBriefTime: String
    var preferredEveningWrapUpTime: String
    var weeklyReviewDay: String
    var voicePersonaOverride: VoicePersonaPreset?
    var voicePackOverrideID: String
    var iconToken: String
    var accentColorToken: String
    var updatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case personaID = "persona_id"
        case displayName = "display_name"
        case aliases
        case enabled
        case identityName = "identity_name"
        case roleSummary = "role_summary"
        case toneDirectives = "tone_directives"
        case extraSystemPrompt = "extra_system_prompt"
        case preferredUserName = "preferred_user_name"
        case goalsSummary = "goals_summary"
        case workStyle = "work_style"
        case communicationPreferences = "communication_preferences"
        case dailyRhythm = "daily_rhythm"
        case reviewPreferences = "review_preferences"
        case relationshipMode = "relationship_mode"
        case briefingStyle = "briefing_style"
        case riskTolerance = "risk_tolerance"
        case interruptionTolerance = "interruption_tolerance"
        case reminderAggressiveness = "reminder_aggressiveness"
        case preferredMorningBriefTime = "preferred_morning_brief_time"
        case preferredEveningWrapUpTime = "preferred_evening_wrap_up_time"
        case weeklyReviewDay = "weekly_review_day"
        case voicePersonaOverride = "voice_persona_override"
        case voicePackOverrideID = "voice_pack_override_id"
        case iconToken = "icon_token"
        case accentColorToken = "accent_color_token"
        case updatedAtMs = "updated_at_ms"
    }

    var id: String { personaID }

    init(
        schemaVersion: String,
        personaID: String,
        displayName: String,
        aliases: [String],
        enabled: Bool,
        identityName: String,
        roleSummary: String,
        toneDirectives: String,
        extraSystemPrompt: String,
        preferredUserName: String,
        goalsSummary: String,
        workStyle: String,
        communicationPreferences: String,
        dailyRhythm: String,
        reviewPreferences: String,
        relationshipMode: SupervisorRelationshipMode,
        briefingStyle: SupervisorBriefingStyle,
        riskTolerance: SupervisorPersonalRiskTolerance,
        interruptionTolerance: SupervisorInterruptionTolerance,
        reminderAggressiveness: SupervisorReminderAggressiveness,
        preferredMorningBriefTime: String,
        preferredEveningWrapUpTime: String,
        weeklyReviewDay: String,
        voicePersonaOverride: VoicePersonaPreset?,
        voicePackOverrideID: String,
        iconToken: String,
        accentColorToken: String,
        updatedAtMs: Int64
    ) {
        self.schemaVersion = schemaVersion
        self.personaID = personaID
        self.displayName = displayName
        self.aliases = aliases
        self.enabled = enabled
        self.identityName = identityName
        self.roleSummary = roleSummary
        self.toneDirectives = toneDirectives
        self.extraSystemPrompt = extraSystemPrompt
        self.preferredUserName = preferredUserName
        self.goalsSummary = goalsSummary
        self.workStyle = workStyle
        self.communicationPreferences = communicationPreferences
        self.dailyRhythm = dailyRhythm
        self.reviewPreferences = reviewPreferences
        self.relationshipMode = relationshipMode
        self.briefingStyle = briefingStyle
        self.riskTolerance = riskTolerance
        self.interruptionTolerance = interruptionTolerance
        self.reminderAggressiveness = reminderAggressiveness
        self.preferredMorningBriefTime = preferredMorningBriefTime
        self.preferredEveningWrapUpTime = preferredEveningWrapUpTime
        self.weeklyReviewDay = weeklyReviewDay
        self.voicePersonaOverride = voicePersonaOverride
        self.voicePackOverrideID = voicePackOverrideID
        self.iconToken = iconToken
        self.accentColorToken = accentColorToken
        self.updatedAtMs = updatedAtMs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: (try? container.decode(String.self, forKey: .schemaVersion)) ?? Self.currentSchemaVersion,
            personaID: (try? container.decode(String.self, forKey: .personaID)) ?? "",
            displayName: (try? container.decode(String.self, forKey: .displayName)) ?? "",
            aliases: (try? container.decode([String].self, forKey: .aliases)) ?? [],
            enabled: (try? container.decode(Bool.self, forKey: .enabled)) ?? true,
            identityName: (try? container.decode(String.self, forKey: .identityName)) ?? "",
            roleSummary: (try? container.decode(String.self, forKey: .roleSummary)) ?? "",
            toneDirectives: (try? container.decode(String.self, forKey: .toneDirectives)) ?? "",
            extraSystemPrompt: (try? container.decode(String.self, forKey: .extraSystemPrompt)) ?? "",
            preferredUserName: (try? container.decode(String.self, forKey: .preferredUserName)) ?? "",
            goalsSummary: (try? container.decode(String.self, forKey: .goalsSummary)) ?? "",
            workStyle: (try? container.decode(String.self, forKey: .workStyle)) ?? "",
            communicationPreferences: (try? container.decode(String.self, forKey: .communicationPreferences)) ?? "",
            dailyRhythm: (try? container.decode(String.self, forKey: .dailyRhythm)) ?? "",
            reviewPreferences: (try? container.decode(String.self, forKey: .reviewPreferences)) ?? "",
            relationshipMode: (try? container.decode(SupervisorRelationshipMode.self, forKey: .relationshipMode)) ?? .operatorPartner,
            briefingStyle: (try? container.decode(SupervisorBriefingStyle.self, forKey: .briefingStyle)) ?? .balanced,
            riskTolerance: (try? container.decode(SupervisorPersonalRiskTolerance.self, forKey: .riskTolerance)) ?? .balanced,
            interruptionTolerance: (try? container.decode(SupervisorInterruptionTolerance.self, forKey: .interruptionTolerance)) ?? .balanced,
            reminderAggressiveness: (try? container.decode(SupervisorReminderAggressiveness.self, forKey: .reminderAggressiveness)) ?? .balanced,
            preferredMorningBriefTime: (try? container.decode(String.self, forKey: .preferredMorningBriefTime)) ?? "09:00",
            preferredEveningWrapUpTime: (try? container.decode(String.self, forKey: .preferredEveningWrapUpTime)) ?? "18:00",
            weeklyReviewDay: (try? container.decode(String.self, forKey: .weeklyReviewDay)) ?? "Sunday",
            voicePersonaOverride: try? container.decodeIfPresent(VoicePersonaPreset.self, forKey: .voicePersonaOverride),
            voicePackOverrideID: (try? container.decode(String.self, forKey: .voicePackOverrideID)) ?? "",
            iconToken: (try? container.decode(String.self, forKey: .iconToken)) ?? "person.crop.circle.fill",
            accentColorToken: (try? container.decode(String.self, forKey: .accentColorToken)) ?? "persona_blue",
            updatedAtMs: (try? container.decode(Int64.self, forKey: .updatedAtMs)) ?? 0
        )
    }

    func normalized(defaults: SupervisorPersonaSlot) -> SupervisorPersonaSlot {
        SupervisorPersonaSlot(
            schemaVersion: Self.currentSchemaVersion,
            personaID: normalizedSingleLine(personaID, fallback: defaults.personaID),
            displayName: normalizedSingleLine(displayName, fallback: defaults.displayName),
            aliases: normalizedAliases(aliases),
            enabled: enabled,
            identityName: normalizedSingleLine(identityName, fallback: defaults.identityName),
            roleSummary: normalizedSingleLine(roleSummary, fallback: defaults.roleSummary),
            toneDirectives: normalizedMultiline(toneDirectives),
            extraSystemPrompt: extraSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            preferredUserName: normalizedSingleLine(preferredUserName, fallback: ""),
            goalsSummary: normalizedMultiline(goalsSummary),
            workStyle: normalizedMultiline(workStyle),
            communicationPreferences: normalizedMultiline(communicationPreferences),
            dailyRhythm: normalizedMultiline(dailyRhythm),
            reviewPreferences: normalizedMultiline(reviewPreferences),
            relationshipMode: relationshipMode,
            briefingStyle: briefingStyle,
            riskTolerance: riskTolerance,
            interruptionTolerance: interruptionTolerance,
            reminderAggressiveness: reminderAggressiveness,
            preferredMorningBriefTime: normalizedSingleLine(preferredMorningBriefTime, fallback: defaults.preferredMorningBriefTime),
            preferredEveningWrapUpTime: normalizedSingleLine(preferredEveningWrapUpTime, fallback: defaults.preferredEveningWrapUpTime),
            weeklyReviewDay: normalizedSingleLine(weeklyReviewDay, fallback: defaults.weeklyReviewDay),
            voicePersonaOverride: voicePersonaOverride,
            voicePackOverrideID: normalizedSingleLine(voicePackOverrideID, fallback: ""),
            iconToken: normalizedSingleLine(iconToken, fallback: defaults.iconToken),
            accentColorToken: normalizedSingleLine(accentColorToken, fallback: defaults.accentColorToken),
            updatedAtMs: max(0, updatedAtMs)
        )
    }

    var promptPreferences: SupervisorPromptPreferences {
        SupervisorPromptPreferences(
            identityName: identityName,
            roleSummary: roleSummary,
            toneDirectives: toneDirectives,
            extraSystemPrompt: extraSystemPrompt
        ).normalized()
    }

    var personalProfile: SupervisorPersonalProfile {
        SupervisorPersonalProfile(
            preferredName: preferredUserName,
            goalsSummary: goalsSummary,
            workStyle: workStyle,
            communicationPreferences: communicationPreferences,
            dailyRhythm: dailyRhythm,
            reviewPreferences: reviewPreferences
        ).normalized()
    }

    var personalPolicy: SupervisorPersonalPolicy {
        SupervisorPersonalPolicy(
            relationshipMode: relationshipMode,
            briefingStyle: briefingStyle,
            riskTolerance: riskTolerance,
            interruptionTolerance: interruptionTolerance,
            reminderAggressiveness: reminderAggressiveness,
            preferredMorningBriefTime: preferredMorningBriefTime,
            preferredEveningWrapUpTime: preferredEveningWrapUpTime,
            weeklyReviewDay: weeklyReviewDay
        ).normalized()
    }

    func setting(
        prompt: SupervisorPromptPreferences? = nil,
        personalProfile: SupervisorPersonalProfile? = nil,
        personalPolicy: SupervisorPersonalPolicy? = nil,
        voicePersonaOverride: VoicePersonaPreset? = nil,
        preserveExistingVoiceOverride: Bool = true,
        voicePackOverrideID: String? = nil,
        preserveExistingVoicePackOverride: Bool = true
    ) -> SupervisorPersonaSlot {
        let nextPrompt = (prompt ?? promptPreferences).normalized()
        let nextProfile = (personalProfile ?? self.personalProfile).normalized()
        let nextPolicy = (personalPolicy ?? self.personalPolicy).normalized()
        let resolvedVoiceOverride: VoicePersonaPreset?
        if let voicePersonaOverride {
            resolvedVoiceOverride = voicePersonaOverride
        } else if preserveExistingVoiceOverride {
            resolvedVoiceOverride = self.voicePersonaOverride
        } else {
            resolvedVoiceOverride = nil
        }
        let resolvedVoicePackOverrideID: String
        if let voicePackOverrideID {
            resolvedVoicePackOverrideID = voicePackOverrideID.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if preserveExistingVoicePackOverride {
            resolvedVoicePackOverrideID = self.voicePackOverrideID
        } else {
            resolvedVoicePackOverrideID = ""
        }
        return SupervisorPersonaSlot(
            schemaVersion: Self.currentSchemaVersion,
            personaID: personaID,
            displayName: displayName,
            aliases: aliases,
            enabled: enabled,
            identityName: nextPrompt.identityName,
            roleSummary: nextPrompt.roleSummary,
            toneDirectives: nextPrompt.toneDirectives,
            extraSystemPrompt: nextPrompt.extraSystemPrompt,
            preferredUserName: nextProfile.preferredName,
            goalsSummary: nextProfile.goalsSummary,
            workStyle: nextProfile.workStyle,
            communicationPreferences: nextProfile.communicationPreferences,
            dailyRhythm: nextProfile.dailyRhythm,
            reviewPreferences: nextProfile.reviewPreferences,
            relationshipMode: nextPolicy.relationshipMode,
            briefingStyle: nextPolicy.briefingStyle,
            riskTolerance: nextPolicy.riskTolerance,
            interruptionTolerance: nextPolicy.interruptionTolerance,
            reminderAggressiveness: nextPolicy.reminderAggressiveness,
            preferredMorningBriefTime: nextPolicy.preferredMorningBriefTime,
            preferredEveningWrapUpTime: nextPolicy.preferredEveningWrapUpTime,
            weeklyReviewDay: nextPolicy.weeklyReviewDay,
            voicePersonaOverride: resolvedVoiceOverride,
            voicePackOverrideID: resolvedVoicePackOverrideID,
            iconToken: iconToken,
            accentColorToken: accentColorToken,
            updatedAtMs: updatedAtMs
        )
    }

    static func seed(index: Int, defaultVoicePersona: VoicePersonaPreset) -> SupervisorPersonaSlot {
        switch index {
        case 0:
            return SupervisorPersonaSlot(
                schemaVersion: currentSchemaVersion,
                personaID: "persona_slot_1",
                displayName: "Supervisor",
                aliases: ["supervisor"],
                enabled: true,
                identityName: "Supervisor",
                roleSummary: "Supervisor AI for project orchestration, model routing, and execution coordination.",
                toneDirectives: "",
                extraSystemPrompt: "",
                preferredUserName: "",
                goalsSummary: "",
                workStyle: "",
                communicationPreferences: "",
                dailyRhythm: "",
                reviewPreferences: "",
                relationshipMode: .operatorPartner,
                briefingStyle: .balanced,
                riskTolerance: .balanced,
                interruptionTolerance: .balanced,
                reminderAggressiveness: .balanced,
                preferredMorningBriefTime: "09:00",
                preferredEveningWrapUpTime: "18:00",
                weeklyReviewDay: "Sunday",
                voicePersonaOverride: defaultVoicePersona,
                voicePackOverrideID: "",
                iconToken: "person.crop.circle.fill",
                accentColorToken: "persona_blue",
                updatedAtMs: 0
            )
        case 1:
            return SupervisorPersonaSlot(
                schemaVersion: currentSchemaVersion,
                personaID: "persona_slot_2",
                displayName: "Atlas",
                aliases: ["atlas", "阿特拉斯"],
                enabled: true,
                identityName: "Atlas Supervisor",
                roleSummary: "Strategic chief-of-staff style partner for execution alignment and prioritization.",
                toneDirectives: "Lead with the answer.\nPoint out tradeoffs directly.",
                extraSystemPrompt: "",
                preferredUserName: "",
                goalsSummary: "",
                workStyle: "",
                communicationPreferences: "",
                dailyRhythm: "",
                reviewPreferences: "",
                relationshipMode: .chiefOfStaff,
                briefingStyle: .proactive,
                riskTolerance: .balanced,
                interruptionTolerance: .high,
                reminderAggressiveness: .assertive,
                preferredMorningBriefTime: "08:30",
                preferredEveningWrapUpTime: "18:30",
                weeklyReviewDay: "Friday",
                voicePersonaOverride: .briefing,
                voicePackOverrideID: "",
                iconToken: "sparkles.rectangle.stack.fill",
                accentColorToken: "persona_amber",
                updatedAtMs: 0
            )
        case 2:
            return SupervisorPersonaSlot(
                schemaVersion: currentSchemaVersion,
                personaID: "persona_slot_3",
                displayName: "Nova",
                aliases: ["nova"],
                enabled: true,
                identityName: "Nova",
                roleSummary: "Practical personal assistant focused on reminders, logistics, and follow-through.",
                toneDirectives: "Keep it concise.\nSurface the next action clearly.",
                extraSystemPrompt: "",
                preferredUserName: "",
                goalsSummary: "",
                workStyle: "",
                communicationPreferences: "",
                dailyRhythm: "",
                reviewPreferences: "",
                relationshipMode: .personalAssistant,
                briefingStyle: .concise,
                riskTolerance: .balanced,
                interruptionTolerance: .balanced,
                reminderAggressiveness: .balanced,
                preferredMorningBriefTime: "08:45",
                preferredEveningWrapUpTime: "17:45",
                weeklyReviewDay: "Sunday",
                voicePersonaOverride: .conversational,
                voicePackOverrideID: "",
                iconToken: "checklist.checked",
                accentColorToken: "persona_teal",
                updatedAtMs: 0
            )
        case 3:
            return SupervisorPersonaSlot(
                schemaVersion: currentSchemaVersion,
                personaID: "persona_slot_4",
                displayName: "Sage",
                aliases: ["sage"],
                enabled: true,
                identityName: "Sage",
                roleSummary: "Calm coach who helps the user notice drift, clarify priorities, and reduce noise.",
                toneDirectives: "Stay calm and direct.\nName the most important tradeoff first.",
                extraSystemPrompt: "",
                preferredUserName: "",
                goalsSummary: "",
                workStyle: "",
                communicationPreferences: "",
                dailyRhythm: "",
                reviewPreferences: "",
                relationshipMode: .coach,
                briefingStyle: .balanced,
                riskTolerance: .conservative,
                interruptionTolerance: .low,
                reminderAggressiveness: .quiet,
                preferredMorningBriefTime: "09:00",
                preferredEveningWrapUpTime: "19:00",
                weeklyReviewDay: "Saturday",
                voicePersonaOverride: .calm,
                voicePackOverrideID: "",
                iconToken: "leaf.circle.fill",
                accentColorToken: "persona_green",
                updatedAtMs: 0
            )
        default:
            return SupervisorPersonaSlot(
                schemaVersion: currentSchemaVersion,
                personaID: "persona_slot_5",
                displayName: "Breeze",
                aliases: ["breeze"],
                enabled: true,
                identityName: "Breeze",
                roleSummary: "Lightweight collaborator for quick check-ins, summaries, and low-friction conversation.",
                toneDirectives: "Keep momentum high.\nAvoid ceremony.",
                extraSystemPrompt: "",
                preferredUserName: "",
                goalsSummary: "",
                workStyle: "",
                communicationPreferences: "",
                dailyRhythm: "",
                reviewPreferences: "",
                relationshipMode: .operatorPartner,
                briefingStyle: .concise,
                riskTolerance: .aggressive,
                interruptionTolerance: .balanced,
                reminderAggressiveness: .quiet,
                preferredMorningBriefTime: "09:15",
                preferredEveningWrapUpTime: "18:15",
                weeklyReviewDay: "Sunday",
                voicePersonaOverride: .conversational,
                voicePackOverrideID: "",
                iconToken: "wind",
                accentColorToken: "persona_sky",
                updatedAtMs: 0
            )
        }
    }

    private func normalizedSingleLine(_ value: String, fallback: String) -> String {
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

    private func normalizedAliases(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            output.append(trimmed)
        }
        return output
    }
}

struct SupervisorPersonaRegistry: Codable, Equatable {
    static let currentSchemaVersion = "xt.supervisor_persona_registry.v1"
    static let slotCount = 5

    var schemaVersion: String
    var defaultPersonaID: String
    var activePersonaID: String
    var slots: [SupervisorPersonaSlot]
    var updatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case defaultPersonaID = "default_persona_id"
        case activePersonaID = "active_persona_id"
        case slots
        case updatedAtMs = "updated_at_ms"
    }

    func normalized(defaultVoicePersona: VoicePersonaPreset) -> SupervisorPersonaRegistry {
        var normalizedSlots: [SupervisorPersonaSlot] = []
        var seenIDs = Set<String>()

        for index in 0..<Self.slotCount {
            let defaultSlot = SupervisorPersonaSlot.seed(index: index, defaultVoicePersona: defaultVoicePersona)
            let matched = slots.first(where: {
                $0.personaID.trimmingCharacters(in: .whitespacesAndNewlines) == defaultSlot.personaID
            })
            let resolved = (matched ?? defaultSlot).normalized(defaults: defaultSlot)
            guard seenIDs.insert(resolved.personaID).inserted else { continue }
            normalizedSlots.append(resolved)
        }

        for slot in slots {
            guard normalizedSlots.count < Self.slotCount else { break }
            let trimmedID = slot.personaID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else { continue }
            guard seenIDs.insert(trimmedID).inserted else { continue }
            let fallback = SupervisorPersonaSlot.seed(index: normalizedSlots.count, defaultVoicePersona: defaultVoicePersona)
            normalizedSlots.append(slot.normalized(defaults: fallback))
        }

        while normalizedSlots.count < Self.slotCount {
            let fallback = SupervisorPersonaSlot.seed(index: normalizedSlots.count, defaultVoicePersona: defaultVoicePersona)
            guard seenIDs.insert(fallback.personaID).inserted else { break }
            normalizedSlots.append(fallback)
        }

        let resolvedDefaultID = normalizedSlots.contains(where: { $0.personaID == defaultPersonaID })
            ? defaultPersonaID
            : (normalizedSlots.first?.personaID ?? "persona_slot_1")
        let resolvedActiveID = normalizedSlots.contains(where: { $0.personaID == activePersonaID })
            ? activePersonaID
            : resolvedDefaultID

        return SupervisorPersonaRegistry(
            schemaVersion: Self.currentSchemaVersion,
            defaultPersonaID: resolvedDefaultID,
            activePersonaID: resolvedActiveID,
            slots: normalizedSlots,
            updatedAtMs: max(0, updatedAtMs)
        )
    }

    var defaultPersona: SupervisorPersonaSlot {
        slot(for: defaultPersonaID) ?? slots.first ?? SupervisorPersonaSlot.seed(index: 0, defaultVoicePersona: .conversational)
    }

    var activePersona: SupervisorPersonaSlot {
        slot(for: activePersonaID) ?? defaultPersona
    }

    var legacyPrimaryPersona: SupervisorPersonaSlot {
        activePersona
    }

    func slot(for personaID: String) -> SupervisorPersonaSlot? {
        let trimmed = personaID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return slots.first { $0.personaID == trimmed }
    }

    func setting(slot updatedSlot: SupervisorPersonaSlot) -> SupervisorPersonaRegistry {
        var next = self
        if let index = next.slots.firstIndex(where: { $0.personaID == updatedSlot.personaID }) {
            next.slots[index] = updatedSlot
        } else if next.slots.count < Self.slotCount {
            next.slots.append(updatedSlot)
        }
        return next
    }

    func setting(activePersonaID: String) -> SupervisorPersonaRegistry {
        var next = self
        next.activePersonaID = activePersonaID
        return next
    }

    func setting(defaultPersonaID: String) -> SupervisorPersonaRegistry {
        var next = self
        next.defaultPersonaID = defaultPersonaID
        return next
    }

    static func `default`(defaultVoicePersona: VoicePersonaPreset) -> SupervisorPersonaRegistry {
        let slots = (0..<slotCount).map { SupervisorPersonaSlot.seed(index: $0, defaultVoicePersona: defaultVoicePersona) }
        return SupervisorPersonaRegistry(
            schemaVersion: currentSchemaVersion,
            defaultPersonaID: slots.first?.personaID ?? "persona_slot_1",
            activePersonaID: slots.first?.personaID ?? "persona_slot_1",
            slots: slots,
            updatedAtMs: 0
        )
    }

    static func seededFromLegacy(
        prompt: SupervisorPromptPreferences,
        personalProfile: SupervisorPersonalProfile,
        personalPolicy: SupervisorPersonalPolicy,
        defaultVoicePersona: VoicePersonaPreset
    ) -> SupervisorPersonaRegistry {
        var registry = Self.default(defaultVoicePersona: defaultVoicePersona)
        let primaryID = registry.defaultPersonaID
        guard let slot = registry.slot(for: primaryID) else { return registry }
        let legacyDisplayName = prompt.normalized().identityName
        var migrated = slot.setting(
            prompt: prompt,
            personalProfile: personalProfile,
            personalPolicy: personalPolicy,
            voicePersonaOverride: defaultVoicePersona,
            preserveExistingVoiceOverride: false
        )
        migrated.displayName = legacyDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? slot.displayName
            : legacyDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if migrated.aliases.isEmpty {
            migrated.aliases = [migrated.displayName]
        }
        registry = registry.setting(slot: migrated)
        return registry
    }
}
