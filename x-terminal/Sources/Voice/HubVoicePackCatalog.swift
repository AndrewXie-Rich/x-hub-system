import Foundation

struct HubVoicePackPickerOption: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String?
    let menuLabel: String
    let isUnavailableSelection: Bool
}

enum HubVoicePackCatalog {
    static let automaticSelectionID = ""
    static let automaticSelectionTitle = "自动 / 最佳匹配"
    static let automaticSelectionDetail =
        "当 Hub 已暴露并准备好本地语音包时，XT 会自动选择最匹配的一项；否则回退到系统语音。"
    private static let unavailableInventoryTitle = "Hub 清单中不可用"

    static func eligibleModels(from rawModels: [HubModel]) -> [HubModel] {
        var dedup: [String: HubModel] = [:]
        for model in rawModels where model.isEligibleHubVoicePackModel {
            let key = normalizedModelID(model.id)
            if let existing = dedup[key] {
                if shouldReplace(existing: existing, with: model) {
                    dedup[key] = model
                }
            } else {
                dedup[key] = model
            }
        }

        return dedup.values.sorted(by: compareModels(_:_:))
    }

    static func pickerOptions(
        models: [HubModel],
        selectedModelID rawSelectedModelID: String
    ) -> [HubVoicePackPickerOption] {
        let eligible = eligibleModels(from: models)
        var options: [HubVoicePackPickerOption] = [
            HubVoicePackPickerOption(
                id: automaticSelectionID,
                title: automaticSelectionTitle,
                detail: automaticSelectionDetail,
                menuLabel: automaticSelectionTitle,
                isUnavailableSelection: false
            )
        ]

        let selectedModelID = normalized(rawSelectedModelID)
        if let selectedModelID,
           !eligible.contains(where: { normalizedModelID($0.id) == normalizedModelID(selectedModelID) }) {
            options.append(
                HubVoicePackPickerOption(
                    id: selectedModelID,
                    title: unavailableInventoryTitle,
                    detail: selectedModelID,
                    menuLabel: unavailableInventoryTitle,
                    isUnavailableSelection: true
                )
            )
        }

        options.append(contentsOf: eligible.map(pickerOption(for:)))
        return options
    }

    static func selectedModel(
        preferredModelID rawPreferredModelID: String,
        models: [HubModel]
    ) -> HubModel? {
        model(modelID: rawPreferredModelID, models: models)
    }

    static func model(
        modelID rawModelID: String,
        models: [HubModel]
    ) -> HubModel? {
        let modelID = normalized(rawModelID)
        guard let modelID else { return nil }
        return eligibleModels(from: models).first {
            normalizedModelID($0.id) == normalizedModelID(modelID)
        }
    }

    static func recommendedModel(
        localeIdentifier: String,
        timbre: VoiceTimbrePreset,
        models: [HubModel]
    ) -> HubModel? {
        let eligible = eligibleModels(from: models)
        guard !eligible.isEmpty else { return nil }

        let normalizedLocale = localeIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let preferredLanguage = normalizedLocale
            .split(separator: "-")
            .first
            .map(String.init) ?? normalizedLocale

        return eligible.max { lhs, rhs in
            let leftScore = recommendationScore(
                for: lhs,
                preferredLanguage: preferredLanguage,
                timbre: timbre
            )
            let rightScore = recommendationScore(
                for: rhs,
                preferredLanguage: preferredLanguage,
                timbre: timbre
            )
            if leftScore != rightScore {
                return leftScore < rightScore
            }
            return compareModels(rhs, lhs)
        }
    }

    static func selectionTitle(
        preferredModelID rawPreferredModelID: String,
        models: [HubModel]
    ) -> String {
        let preferredModelID = normalized(rawPreferredModelID)
        guard let preferredModelID else {
            return automaticSelectionTitle
        }
        guard let model = selectedModel(preferredModelID: preferredModelID, models: models) else {
            return unavailableInventoryTitle
        }
        return modelTitle(model)
    }

    static func selectionDetail(
        preferredModelID rawPreferredModelID: String,
        models: [HubModel]
    ) -> String? {
        let preferredModelID = normalized(rawPreferredModelID)
        guard let preferredModelID else { return nil }
        guard let model = selectedModel(preferredModelID: preferredModelID, models: models) else {
            return preferredModelID
        }

        return detailLine(for: model)
    }

    private static func pickerOption(for model: HubModel) -> HubVoicePackPickerOption {
        let title = modelTitle(model)
        let detail = detailLine(for: model)
        let menuLabel = compactMenuLabel(for: model, title: title)
        return HubVoicePackPickerOption(
            id: model.id,
            title: title,
            detail: detail,
            menuLabel: menuLabel,
            isUnavailableSelection: false
        )
    }

    private static func modelTitle(_ model: HubModel) -> String {
        let displayName = model.capabilityPresentationModel.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if displayName.isEmpty {
            return model.id
        }
        return displayName
    }

    private static func shouldReplace(existing: HubModel, with candidate: HubModel) -> Bool {
        if stateRank(candidate.state) != stateRank(existing.state) {
            return stateRank(candidate.state) < stateRank(existing.state)
        }
        return compareModels(candidate, existing)
    }

    private static func compareModels(_ lhs: HubModel, _ rhs: HubModel) -> Bool {
        if stateRank(lhs.state) != stateRank(rhs.state) {
            return stateRank(lhs.state) < stateRank(rhs.state)
        }

        let leftName = normalizedSortName(lhs)
        let rightName = normalizedSortName(rhs)
        if leftName != rightName {
            return leftName < rightName
        }
        return normalizedModelID(lhs.id) < normalizedModelID(rhs.id)
    }

    private static func normalizedSortName(_ model: HubModel) -> String {
        let displayName = model.capabilityPresentationModel.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if displayName.isEmpty {
            return normalizedModelID(model.id)
        }
        return displayName.lowercased()
    }

    private static func stateRank(_ state: HubModelState) -> Int {
        switch state {
        case .loaded:
            return 0
        case .available:
            return 1
        case .sleeping:
            return 2
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func detailLine(for model: HubModel) -> String {
        var parts = [HubModelSelectionAdvisor.stateLabel(model.state)]
        let signals = signalLabels(for: model)
        if !signals.isEmpty {
            parts.append("特征：\(signals.joined(separator: "、"))")
        }
        parts.append(model.id)
        return parts.joined(separator: " · ")
    }

    private static func compactMenuLabel(for model: HubModel, title: String) -> String {
        let state = HubModelSelectionAdvisor.stateLabel(model.state)
        let compactSignals = Array(signalLabels(for: model).prefix(2))
        guard !compactSignals.isEmpty else {
            return "\(title) · \(state)"
        }
        return "\(title) · \(compactSignals.joined(separator: " · ")) · \(state)"
    }

    private static func signalLabels(for model: HubModel) -> [String] {
        var labels: [String] = []
        if let voiceProfile = model.voiceProfile {
            let languageHints = Set(voiceProfile.languageHints.map { $0.lowercased() })
            if languageHints.contains("multi") {
                labels.append("多语种")
            } else {
                if languageHints.contains("zh") {
                    labels.append("中文偏好")
                }
                if languageHints.contains("en") {
                    labels.append("英文偏好")
                }
            }

            for token in voiceProfile.styleHints {
                switch token.lowercased() {
                case "warm":
                    labels.append("温暖风格")
                case "clear":
                    labels.append("清晰风格")
                case "bright":
                    labels.append("明亮风格")
                case "calm":
                    labels.append("平静风格")
                case "neutral":
                    labels.append("中性风格")
                default:
                    break
                }
            }

            for token in voiceProfile.engineHints {
                switch token.lowercased() {
                case "kokoro":
                    labels.append("Kokoro")
                case "cosyvoice":
                    labels.append("CosyVoice")
                case "melotts":
                    labels.append("MeloTTS")
                case "chattts":
                    labels.append("ChatTTS")
                case "f5-tts":
                    labels.append("F5-TTS")
                case "bark":
                    labels.append("Bark")
                case "parler":
                    labels.append("Parler")
                case "vits":
                    labels.append("VITS")
                default:
                    break
                }
            }
        }

        return orderedUnique(labels)
    }

    private static func recommendationScore(
        for model: HubModel,
        preferredLanguage: String,
        timbre: VoiceTimbrePreset
    ) -> Int {
        var score = 0
        switch model.state {
        case .loaded:
            score += 40
        case .available:
            score += 24
        case .sleeping:
            score += 12
        }

        let voiceProfile = model.voiceProfile
        let languageHints = Set(voiceProfile?.languageHints.map { $0.lowercased() } ?? [])
        if preferredLanguage == "zh" {
            if languageHints.contains("zh") {
                score += 36
            } else if languageHints.contains("multi") {
                score += 28
            } else if languageHints.isEmpty {
                score += 10
            }
        } else if preferredLanguage == "en" {
            if languageHints.contains("en") {
                score += 36
            } else if languageHints.contains("multi") {
                score += 28
            } else if languageHints.isEmpty {
                score += 10
            }
        } else if languageHints.contains("multi") {
            score += 20
        }

        let styleHints = Set((voiceProfile?.styleHints ?? []).map(normalizedRouteStyle))
        let requestedStyle = normalizedRouteStyle(timbre.rawValue.lowercased())
        if styleHints.contains(requestedStyle) {
            score += 24
        } else if requestedStyle == "neutral" {
            score += styleHints.isEmpty ? 14 : 6
        } else if styleHints.isEmpty {
            score += 8
        }

        let engineHints = Set(voiceProfile?.engineHints.map { $0.lowercased() } ?? [])
        if engineHints.contains("kokoro") {
            score += 4
            score += kokoroRouteBonus(
                preferredLanguage: preferredLanguage,
                requestedStyle: requestedStyle
            )
        } else if engineHints.contains("cosyvoice") || engineHints.contains("melotts") {
            score += 4
        }

        return score
    }

    private static func normalizedRouteStyle(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "bright", "studio", "crisp":
            return "clear"
        case "soft", "gentle", "soothing":
            return "calm"
        default:
            return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private static func kokoroRouteBonus(
        preferredLanguage: String,
        requestedStyle: String
    ) -> Int {
        switch (preferredLanguage, requestedStyle) {
        case ("zh", "warm"), ("zh", "clear"), ("en", "warm"), ("en", "calm"):
            return 10
        default:
            return 0
        }
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func normalizedModelID(_ modelID: String) -> String {
        modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
