import Foundation

struct SupervisorPersonaCenterPresentation: Equatable {
    enum SyncState: String, Equatable {
        case synced
        case draftUnsaved

        var badgeText: String {
            switch self {
            case .synced:
                return "已同步"
            case .draftUnsaved:
                return "草稿未保存"
            }
        }
    }

    struct Pill: Equatable, Identifiable {
        enum Tone: String, Equatable {
            case neutral
            case accent
            case strong
            case inactive
        }

        var text: String
        var tone: Tone

        var id: String { "\(tone.rawValue):\(text)" }
    }

    struct Card: Equatable, Identifiable {
        var personaID: String
        var slotIndex: Int
        var displayName: String
        var identityName: String
        var roleSummary: String
        var iconToken: String
        var accentColorToken: String
        var enabled: Bool
        var isSelected: Bool
        var isDefault: Bool
        var isActive: Bool
        var aliasCount: Int
        var aliasSummary: String
        var voiceLabel: String
        var tags: [Pill]
        var statusBadges: [Pill]

        var id: String { personaID }
    }

    struct WakeSuggestionItem: Equatable, Identifiable {
        var personaID: String
        var personaDisplayName: String
        var token: String
        var isPrimaryName: Bool

        var id: String { "\(personaID):\(token.lowercased())" }
    }

    var syncState: SyncState
    var selectedPersonaID: String
    var cards: [Card]
    var selectedCard: Card
    var canSave: Bool
    var canRestore: Bool
    var canSetSelectedAsDefault: Bool
    var canSetSelectedAsActive: Bool
    var persistedActivePersonaName: String
    var persistedDefaultPersonaName: String
    var persistedActiveVoiceSummary: String
    var persistedDefaultVoiceSummary: String
    var wakeSuggestions: [WakeSuggestionItem]

    init(
        draftRegistry: SupervisorPersonaRegistry,
        persistedRegistry: SupervisorPersonaRegistry,
        selectedPersonaID: String,
        defaultVoicePersona: VoicePersonaPreset,
        existingWakeTriggerWords: [String] = []
    ) {
        let normalizedDraft = draftRegistry.normalized(defaultVoicePersona: defaultVoicePersona)
        let normalizedPersisted = persistedRegistry.normalized(defaultVoicePersona: defaultVoicePersona)
        let resolvedSelectedID = normalizedDraft.slot(for: selectedPersonaID)?.personaID ?? normalizedDraft.activePersonaID

        let cards = normalizedDraft.slots.enumerated().map { index, slot in
            Self.makeCard(
                slot: slot,
                slotIndex: index,
                resolvedSelectedID: resolvedSelectedID,
                defaultPersonaID: normalizedDraft.defaultPersonaID,
                activePersonaID: normalizedDraft.activePersonaID
            )
        }

        self.syncState = normalizedDraft == normalizedPersisted ? .synced : .draftUnsaved
        self.selectedPersonaID = resolvedSelectedID
        self.cards = cards
        self.selectedCard = cards.first(where: { $0.personaID == resolvedSelectedID }) ?? cards[0]
        self.canSave = self.syncState == .draftUnsaved
        self.canRestore = self.syncState == .draftUnsaved
        self.canSetSelectedAsDefault = self.selectedCard.enabled && !self.selectedCard.isDefault
        self.canSetSelectedAsActive = self.selectedCard.enabled && !self.selectedCard.isActive
        self.persistedActivePersonaName = normalizedPersisted.activePersona.displayName
        self.persistedDefaultPersonaName = normalizedPersisted.defaultPersona.displayName
        self.persistedActiveVoiceSummary = Self.voiceSummary(
            slot: normalizedPersisted.activePersona,
            inheritedVoice: defaultVoicePersona
        )
        self.persistedDefaultVoiceSummary = Self.voiceSummary(
            slot: normalizedPersisted.defaultPersona,
            inheritedVoice: defaultVoicePersona
        )
        self.wakeSuggestions = SupervisorWakePhraseSuggestionBuilder.suggestions(
            registry: normalizedDraft,
            existingTriggerWords: existingWakeTriggerWords
        ).map {
            WakeSuggestionItem(
                personaID: $0.personaID,
                personaDisplayName: $0.personaDisplayName,
                token: $0.token,
                isPrimaryName: $0.isPrimaryName
            )
        }
    }

    private static func makeCard(
        slot: SupervisorPersonaSlot,
        slotIndex: Int,
        resolvedSelectedID: String,
        defaultPersonaID: String,
        activePersonaID: String
    ) -> Card {
        let isSelected = slot.personaID == resolvedSelectedID
        let isDefault = slot.personaID == defaultPersonaID
        let isActive = slot.personaID == activePersonaID
        let voiceLabel = slot.voicePersonaOverride?.displayName ?? "跟随运行时"
        var tags = [
            Pill(text: slot.relationshipMode.displayName, tone: .accent),
            Pill(text: slot.briefingStyle.displayName, tone: .neutral)
        ]
        if slot.voicePersonaOverride != nil {
            tags.append(Pill(text: voiceLabel, tone: .neutral))
        }
        if !slot.enabled {
            tags.append(Pill(text: "已停用", tone: .inactive))
        }

        var statusBadges: [Pill] = []
        if isDefault {
            statusBadges.append(Pill(text: "默认", tone: .strong))
        }
        if isActive {
            statusBadges.append(Pill(text: "当前", tone: .accent))
        }
        statusBadges.append(Pill(text: "槽位 \(slotIndex + 1)", tone: .neutral))

        return Card(
            personaID: slot.personaID,
            slotIndex: slotIndex,
            displayName: slot.displayName,
            identityName: slot.identityName,
            roleSummary: displayRoleSummary(for: slot),
            iconToken: slot.iconToken,
            accentColorToken: slot.accentColorToken,
            enabled: slot.enabled,
            isSelected: isSelected,
            isDefault: isDefault,
            isActive: isActive,
            aliasCount: slot.aliases.count,
            aliasSummary: slot.aliases.isEmpty ? "无别名" : slot.aliases.joined(separator: "、"),
            voiceLabel: voiceLabel,
            tags: tags,
            statusBadges: statusBadges
        )
    }

    private static func voiceSummary(
        slot: SupervisorPersonaSlot,
        inheritedVoice: VoicePersonaPreset
    ) -> String {
        if let override = slot.voicePersonaOverride {
            return override.displayName
        }
        return "跟随运行时默认（\(inheritedVoice.displayName)）"
    }

    private static func displayRoleSummary(for slot: SupervisorPersonaSlot) -> String {
        switch slot.personaID {
        case "persona_slot_1":
            return "负责项目编排、模型路由与执行协调的总控助手。"
        case "persona_slot_2":
            return "偏战略幕僚，擅长执行对齐与优先级判断。"
        case "persona_slot_3":
            return "偏务实助理，擅长提醒、后勤与持续跟进。"
        case "persona_slot_4":
            return "偏冷静教练，帮助识别跑偏、澄清重点、减少噪音。"
        case "persona_slot_5":
            return "偏轻量搭档，适合快速确认、总结与低打扰对话。"
        default:
            return slot.roleSummary
        }
    }
}
