import SwiftUI

enum HubModelRoutingBadgeTone: String, Equatable {
    case neutral
    case success
    case caution
    case warning
    case danger

    var color: Color {
        switch self {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .caution:
            return .yellow
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}

enum HubModelRoutingBadgeKind: String, Equatable {
    case source
    case status
    case detail
    case evidence
}

struct HubModelRoutingBadgePresentation: Equatable, Identifiable {
    let text: String
    let tone: HubModelRoutingBadgeTone
    let kind: HubModelRoutingBadgeKind
    let iconName: String?

    init(
        text: String,
        tone: HubModelRoutingBadgeTone,
        kind: HubModelRoutingBadgeKind,
        iconName: String? = nil
    ) {
        self.text = text
        self.tone = tone
        self.kind = kind
        self.iconName = iconName
    }

    var id: String {
        "\(kind.rawValue)::\(tone.rawValue)::\(iconName ?? "")::\(text)"
    }
}

extension HubModel {
    func routingSourceBadges(language: XTInterfaceLanguage = .defaultPreference) -> [HubModelRoutingBadgePresentation] {
        remoteIdentityComponents.compactMap { component in
            switch component.kind {
            case .keyReference:
                return HubModelRoutingBadgePresentation(
                    text: component.value,
                    tone: .warning,
                    kind: .source,
                    iconName: "key.fill"
                )
            case .endpointHost:
                return HubModelRoutingBadgePresentation(
                    text: component.value,
                    tone: .neutral,
                    kind: .source,
                    iconName: "network"
                )
            case .providerModelID:
                return HubModelRoutingBadgePresentation(
                    text: component.value,
                    tone: .caution,
                    kind: .detail,
                    iconName: language == .english ? "arrow.triangle.branch" : "arrow.triangle.branch"
                )
            }
        }
    }
}

struct HubModelRoutingSupplementaryPresentation: Equatable {
    var badges: [HubModelRoutingBadgePresentation]
    var summaryText: String
    var tooltip: String? = nil

    var hasContent: Bool {
        !badges.isEmpty || !summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var compactButtonPresentation: HubModelRoutingSupplementaryPresentation {
        let preferredKinds: Set<HubModelRoutingBadgeKind> = [.status, .detail]
        let filteredBadges = badges.filter { preferredKinds.contains($0.kind) }
        let compactBadges = filteredBadges.isEmpty
            ? badges.filter { $0.kind == .source }
            : filteredBadges
        return HubModelRoutingSupplementaryPresentation(
            badges: compactBadges,
            summaryText: "",
            tooltip: tooltip
        )
    }

    var primaryBadges: [HubModelRoutingBadgePresentation] {
        badges.filter { $0.kind != .evidence }
    }

    var evidenceBadges: [HubModelRoutingBadgePresentation] {
        badges.filter { $0.kind == .evidence }
    }
}

struct HubModelRoutingSelectionState {
    let explicitModelId: String?
    let inheritedModelId: String?
    let explicitPresentation: ModelInfo?
    let inheritedPresentation: ModelInfo?
    let explicitSourceLabel: String
    let inheritedSourceLabel: String
    let automaticTitle: String

    var effectivePresentation: ModelInfo? {
        explicitPresentation ?? inheritedPresentation
    }

    var title: String {
        effectivePresentation?.displayName ?? automaticTitle
    }

    var identifier: String? {
        explicitModelId ?? inheritedModelId
    }

    var sourceLabel: String {
        explicitModelId == nil ? inheritedSourceLabel : explicitSourceLabel
    }

    static func resolved(
        explicitModelId: String?,
        inheritedModelId: String?,
        models: [HubModel],
        explicitSourceLabel: String,
        inheritedSourceLabel: String,
        automaticTitle: String
    ) -> HubModelRoutingSelectionState {
        let explicit = normalizedModelId(explicitModelId)
        let inherited = normalizedModelId(inheritedModelId)
        return HubModelRoutingSelectionState(
            explicitModelId: explicit,
            inheritedModelId: inherited,
            explicitPresentation: presentation(for: explicit, models: models),
            inheritedPresentation: presentation(for: inherited, models: models),
            explicitSourceLabel: explicitSourceLabel,
            inheritedSourceLabel: inheritedSourceLabel,
            automaticTitle: automaticTitle
        )
    }

    private static func normalizedModelId(_ modelId: String?) -> String? {
        let trimmed = (modelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func presentation(for modelId: String?, models: [HubModel]) -> ModelInfo? {
        guard let modelId else { return nil }
        return models.first(where: { $0.id == modelId })?.capabilityPresentationModel
            ?? XTModelCatalog.modelInfo(for: modelId)
    }
}

struct HubModelPickerRecommendationState: Equatable {
    let kind: HubModelPickerRecommendationKind
    let modelId: String
    let message: String

    static func resolved(
        explicitRecommendation: HubModelPickerRecommendationState?,
        selectedModelId: String?,
        models: [HubModel],
        language: XTInterfaceLanguage = .defaultPreference
    ) -> HubModelPickerRecommendationState? {
        if let explicitRecommendation {
            return explicitRecommendation
        }
        return resolved(
            explicitModelId: nil,
            explicitMessage: nil,
            explicitKind: .switchRecommended,
            selectedModelId: selectedModelId,
            models: models,
            language: language
        )
    }

    static func resolved(
        explicitModelId: String?,
        explicitMessage: String?,
        explicitKind: HubModelPickerRecommendationKind = .switchRecommended,
        selectedModelId: String?,
        models: [HubModel],
        language: XTInterfaceLanguage = .defaultPreference
    ) -> HubModelPickerRecommendationState? {
        let normalizedExplicitModelId = normalizedText(explicitModelId)
        let normalizedExplicitMessage = normalizedText(explicitMessage)
        if let normalizedExplicitModelId,
           let normalizedExplicitMessage {
            return HubModelPickerRecommendationState(
                kind: explicitKind,
                modelId: normalizedExplicitModelId,
                message: normalizedExplicitMessage
            )
        }

        guard let selectedModelId = normalizedText(selectedModelId),
              let assessment = HubModelSelectionAdvisor.assess(
                requestedId: selectedModelId,
                snapshot: ModelStateSnapshot(models: models, updatedAt: 0)
              ),
              !assessment.isExactMatchLoaded,
              let fallbackModelId = normalizedText(assessment.loadedCandidates.first?.id),
              fallbackModelId.caseInsensitiveCompare(selectedModelId) != .orderedSame else {
            return nil
        }

        if let blocked = assessment.nonInteractiveExactMatch {
            return HubModelPickerRecommendationState(
                kind: .switchRecommended,
                modelId: fallbackModelId,
                message: XTL10n.text(
                    language,
                    zhHans: "`\(blocked.id)` 是检索专用模型，Supervisor 会按需调用它做检索；如果你要立刻继续，可改用 `\(fallbackModelId)`。",
                    en: "`\(blocked.id)` is a retrieval-only model. Supervisor can still call it when needed, but if you want to continue right now, switch to `\(fallbackModelId)`."
                )
            )
        }

        if let exact = assessment.exactMatch {
            return HubModelPickerRecommendationState(
                kind: .switchRecommended,
                modelId: fallbackModelId,
                message: XTL10n.text(
                    language,
                    zhHans: "`\(exact.id)` 当前是 \(HubModelSelectionAdvisor.stateLabel(exact.state, language: language))；如果你要立刻继续，可改用已加载的 `\(fallbackModelId)`。",
                    en: "`\(exact.id)` is currently \(HubModelSelectionAdvisor.stateLabel(exact.state, language: language)). If you want to continue right now, switch to the loaded model `\(fallbackModelId)`."
                )
            )
        }

        return HubModelPickerRecommendationState(
            kind: .switchRecommended,
            modelId: fallbackModelId,
            message: XTL10n.text(
                language,
                zhHans: "`\(selectedModelId)` 当前不在可直接执行的模型清单里；如果你要立刻继续，可改用已加载的 `\(fallbackModelId)`，避免这轮直接掉到本地。",
                en: "`\(selectedModelId)` is not in the directly runnable model list right now. If you want to continue immediately, switch to the loaded model `\(fallbackModelId)` to avoid dropping straight to local."
            )
        )
    }

    private static func normalizedText(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum HubModelPickerRecommendationKind: Equatable {
    case switchRecommended
    case continueWithoutSwitch

    init(_ projectKind: AXProjectModelSelectionRecommendationKind) {
        switch projectKind {
        case .switchRecommended:
            self = .switchRecommended
        case .continueWithoutSwitch:
            self = .continueWithoutSwitch
        }
    }
}

struct HubModelRoutingButton: View {
    let title: String
    let identifier: String?
    let sourceLabel: String
    let presentation: ModelInfo?
    var sourceIdentityLine: String? = nil
    var sourceBadges: [HubModelRoutingBadgePresentation] = []
    var supplementary: HubModelRoutingSupplementaryPresentation? = nil
    var disabled: Bool = false
    var automaticRouteLabel: String = "自动路由"
    let action: () -> Void

    init(
        title: String,
        identifier: String?,
        sourceLabel: String,
        presentation: ModelInfo?,
        sourceIdentityLine: String? = nil,
        sourceBadges: [HubModelRoutingBadgePresentation] = [],
        supplementary: HubModelRoutingSupplementaryPresentation? = nil,
        disabled: Bool = false,
        automaticRouteLabel: String = "自动路由",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.identifier = identifier
        self.sourceLabel = sourceLabel
        self.presentation = presentation
        self.sourceIdentityLine = sourceIdentityLine
        self.sourceBadges = sourceBadges
        self.supplementary = supplementary
        self.disabled = disabled
        self.automaticRouteLabel = automaticRouteLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let identifier, identifier != title {
                            Text(identifier)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(sourceLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if let presentation {
                            ModelCapabilityStrip(model: presentation, limit: 4, compact: true)
                        } else {
                            Text(automaticRouteLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !sourceBadges.isEmpty {
                        HubModelRoutingBadgeCloud(
                            badges: sourceBadges,
                            minimumWidth: 90
                        )
                    } else if let sourceIdentityLine,
                       !sourceIdentityLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(sourceIdentityLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let supplementary,
                       supplementary.compactButtonPresentation.hasContent {
                        HubModelRoutingSupplementaryContent(
                            presentation: supplementary.compactButtonPresentation,
                            showsBackground: false
                        )
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(supplementary?.tooltip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
}

struct HubModelPickerPopover: View {
    let title: String
    let selectedModelId: String?
    let inheritedModelId: String?
    let inheritedModelPresentation: ModelInfo?
    let models: [HubModel]
    var language: XTInterfaceLanguage = .defaultPreference
    var focusContext: XTSectionFocusContext? = nil
    var recommendation: HubModelPickerRecommendationState? = nil
    var selectionTruth: HubModelRoutingSupplementaryPresentation? = nil
    var selectionTruthTitle: String = "当前 Route Truth"
    var showContextDetails: Bool = true
    var automaticTitle: String = "使用全局设置"
    var automaticSelectedBadge: String = "当前生效"
    var automaticRestoreBadge: String = "恢复继承"
    var inheritedModelLabel: String = "全局模型"
    var automaticDescription: String = "当前没有全局固定模型，恢复后会交给系统自动路由。"
    var emptyStateTitle: String? = nil
    var emptyStateDetail: String? = nil
    let onSelect: (String?) -> Void

    @State private var query: String = ""

    init(
        title: String,
        selectedModelId: String?,
        inheritedModelId: String?,
        inheritedModelPresentation: ModelInfo?,
        models: [HubModel],
        language: XTInterfaceLanguage = .defaultPreference,
        focusContext: XTSectionFocusContext? = nil,
        recommendation: HubModelPickerRecommendationState? = nil,
        selectionTruth: HubModelRoutingSupplementaryPresentation? = nil,
        selectionTruthTitle: String = "当前 Route Truth",
        showContextDetails: Bool = true,
        automaticTitle: String = "使用全局设置",
        automaticSelectedBadge: String = "当前生效",
        automaticRestoreBadge: String = "恢复继承",
        inheritedModelLabel: String = "全局模型",
        automaticDescription: String = "当前没有全局固定模型，恢复后会交给系统自动路由。",
        emptyStateTitle: String? = nil,
        emptyStateDetail: String? = nil,
        onSelect: @escaping (String?) -> Void
    ) {
        self.title = title
        self.selectedModelId = selectedModelId
        self.inheritedModelId = inheritedModelId
        self.inheritedModelPresentation = inheritedModelPresentation
        self.models = models
        self.language = language
        self.focusContext = focusContext
        self.recommendation = recommendation
        self.selectionTruth = selectionTruth
        self.selectionTruthTitle = selectionTruthTitle
        self.showContextDetails = showContextDetails
        self.automaticTitle = automaticTitle
        self.automaticSelectedBadge = automaticSelectedBadge
        self.automaticRestoreBadge = automaticRestoreBadge
        self.inheritedModelLabel = inheritedModelLabel
        self.automaticDescription = automaticDescription
        self.emptyStateTitle = emptyStateTitle
        self.emptyStateDetail = emptyStateDetail
        self.onSelect = onSelect
    }

    private var effectiveRecommendation: HubModelPickerRecommendationState? {
        HubModelPickerRecommendationState.resolved(
            explicitRecommendation: recommendation,
            selectedModelId: selectedModelId,
            models: models,
            language: language
        )
    }

    private var normalizedRecommendedModelId: String? {
        let trimmed = (effectiveRecommendation?.modelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var filteredModels: [HubModel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return models }
        return models.filter { model in
            let presentation = model.capabilityPresentationModel
            let haystack = [
                model.id,
                model.name,
                presentation.displayName,
                model.backend,
                model.note ?? "",
                model.remoteSearchKeywords.joined(separator: " "),
                presentation.suitableFor.joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            return haystack.contains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)

                TextField(
                    XTL10n.text(
                        language,
                        zhHans: "搜索模型 / backend / 能力",
                        en: "Search model / backend / capability"
                    ),
                    text: $query
                )
                    .textFieldStyle(.roundedBorder)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let focusContext {
                        XTFocusContextCard(context: focusContext)
                    }

                    if let selectionTruth,
                       selectionTruth.hasContent {
                        HubModelRoutingSupplementaryContent(
                            presentation: selectionTruth,
                            title: selectionTruthTitle,
                            showsBackground: true,
                            collapsesEvidence: true,
                            evidenceDisclosureTitle: XTL10n.text(
                                language,
                                zhHans: "执行证据",
                                en: "Execution Evidence"
                            )
                        )
                    }

                    recommendationCard

                    autoRouteRow

                    if filteredModels.isEmpty {
                        emptyStateCard
                    } else {
                        ForEach(filteredModels) { model in
                            modelRow(model)
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private var recommendationCard: some View {
        if let recommendedModelId = normalizedRecommendedModelId,
           recommendedModelId != selectedModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           let recommendation = effectiveRecommendation,
           let message = effectiveRecommendation?.message.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            let presentation = models.first(where: {
                $0.id.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(recommendedModelId) == .orderedSame
            })?.capabilityPresentationModel ?? XTModelCatalog.modelInfo(for: recommendedModelId)
            let displayTitle = presentation.displayName
            let passive = recommendation.kind == .continueWithoutSwitch
            let title = XTL10n.text(
                language,
                zhHans: passive ? "继续可不切换" : "推荐切换",
                en: passive ? "Continue Without Switching" : "Recommended Switch"
            )
            let subtitle = XTL10n.text(
                language,
                zhHans: passive ? "XT 已会先自动改试这个记住的远端模型" : "可直接避免这轮继续撞当前配置",
                en: passive ? "XT will already retry the remembered remote model first" : "This can avoid running into the current broken configuration again"
            )
            let buttonTitle = XTL10n.text(
                language,
                zhHans: passive ? "固定成 \(recommendedModelId)" : "改用 \(recommendedModelId)",
                en: passive ? "Pin \(recommendedModelId)" : "Switch to \(recommendedModelId)"
            )
            let accent = passive ? Color.accentColor : Color.orange
            let fill = passive ? Color.accentColor.opacity(0.08) : Color.orange.opacity(0.08)
            let stroke = passive ? Color.accentColor.opacity(0.22) : Color.orange.opacity(0.22)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(displayTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    ModelCapabilityStrip(model: presentation, limit: 4, compact: true)
                }

                if passive {
                    Button(buttonTitle) {
                        onSelect(recommendedModelId)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button(buttonTitle) {
                        onSelect(recommendedModelId)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(stroke, lineWidth: 1)
            )
        }
    }

    private var autoRouteRow: some View {
        Button {
            onSelect(nil)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(automaticTitle)
                            .foregroundStyle(.primary)
                        Text(selectedModelId == nil ? automaticSelectedBadge : automaticRestoreBadge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let inheritedModelPresentation {
                        HStack(spacing: 8) {
                            Text(inheritedModelLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(inheritedModelPresentation.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ModelCapabilityStrip(model: inheritedModelPresentation, limit: 4, compact: true)
                        }
                    } else if let inheritedModelId, !inheritedModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 8) {
                            Text(inheritedModelLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(inheritedModelId)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(automaticDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if selectedModelId == nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(selected: selectedModelId == nil))
        }
        .buttonStyle(.plain)
    }

    private var emptyStateCard: some View {
        let hasModels = !models.isEmpty
        let title = {
            let trimmed = (emptyStateTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !hasModels {
                return trimmed
            }
            return hasModels
                ? XTL10n.text(language, zhHans: "没有匹配的模型", en: "No Matching Models")
                : XTL10n.text(language, zhHans: "当前没有可选模型", en: "No Selectable Models")
        }()
        let detail = {
            if hasModels {
                return XTL10n.text(
                    language,
                    zhHans: "换个关键词试试，或者先恢复自动路由。",
                    en: "Try a different keyword, or restore automatic routing first."
                )
            }
            let trimmed = (emptyStateDetail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
            return XTL10n.text(
                language,
                zhHans: "先去 Hub 侧确认模型是否真的已加载，再回来刷新。",
                en: "First confirm on the Hub side that the model is really loaded, then come back and refresh."
            )
        }()

        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private func modelRow(_ model: HubModel) -> some View {
        let presentation = model.capabilityPresentationModel
        let isSelected = selectedModelId == model.id
        let isRecommended = normalizedRecommendedModelId == model.id && !isSelected
        let disabledReason = model.interactiveRoutingDisabledReason
        let isSelectable = model.isSelectableForInteractiveRouting

        return Button {
            guard isSelectable else { return }
            onSelect(model.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(presentation.displayName)
                                .foregroundStyle(.primary)

                            if presentation.displayName != model.id {
                                Text(model.id)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            if isRecommended {
                                Text(XTL10n.text(language, zhHans: "推荐", en: "Recommended"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }

                            if disabledReason != nil {
                                Text(XTL10n.text(language, zhHans: "检索专用", en: "Retrieval Only"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Text(HubModelSelectionAdvisor.stateLabel(model.state, language: language))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(model.state == .loaded ? .green : .secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        ModelCapabilityStrip(model: presentation, limit: 4, compact: true)

                        if !model.backend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(model.backend)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let capabilitySummary = model.capabilitySummaryLine {
                        Text(capabilitySummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let remoteSourceIdentityLine = model.remoteSourceIdentityLine(language: language) {
                        Text(remoteSourceIdentityLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let disabledReason {
                        Text(disabledReason)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let note = model.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if showContextDetails {
                        Text(model.defaultLoadConfigDisplayLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let localLoadConfigLimitLine = model.localLoadConfigLimitLine {
                            Text(localLoadConfigLimitLine)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(selected: isSelected))
            .opacity(isSelectable ? 1.0 : 0.72)
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
    }

    private func cardBackground(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(selected ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
    }
}

struct HubModelRoutingSupplementaryContent: View {
    let presentation: HubModelRoutingSupplementaryPresentation
    var title: String? = nil
    var showsBackground: Bool = false
    var collapsesEvidence: Bool = false
    var evidenceDisclosureTitle: String = "执行证据"

    private var normalizedTitle: String? {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedSummary: String? {
        let trimmed = presentation.summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var primaryBadges: [HubModelRoutingBadgePresentation] {
        collapsesEvidence ? presentation.primaryBadges : presentation.badges
    }

    private var evidenceBadges: [HubModelRoutingBadgePresentation] {
        collapsesEvidence ? presentation.evidenceBadges : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let normalizedTitle {
                Text(normalizedTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !primaryBadges.isEmpty {
                badgeGrid(primaryBadges)
            }

            if !evidenceBadges.isEmpty {
                DisclosureGroup {
                    badgeGrid(evidenceBadges)
                        .padding(.top, 6)
                } label: {
                    Text(evidenceDisclosureTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let normalizedSummary {
                Text(normalizedSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(showsBackground ? 12 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if showsBackground {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                } else {
                    Color.clear
                }
            }
        )
        .overlay(
            Group {
                if showsBackground {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                }
            }
        )
        .help(presentation.tooltip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    @ViewBuilder
    private func badgeGrid(_ badges: [HubModelRoutingBadgePresentation]) -> some View {
        HubModelRoutingBadgeCloud(badges: badges)
    }
}

struct HubModelRoutingBadgeCloud: View {
    let badges: [HubModelRoutingBadgePresentation]
    var minimumWidth: CGFloat = 120

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumWidth), alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(badges) { badge in
                HStack(spacing: 5) {
                    if let iconName = badge.iconName,
                       !iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Image(systemName: iconName)
                            .font(.caption2.weight(.semibold))
                    }
                    Text(badge.text)
                        .lineLimit(1)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(badge.tone.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(badge.tone.color.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }
}
