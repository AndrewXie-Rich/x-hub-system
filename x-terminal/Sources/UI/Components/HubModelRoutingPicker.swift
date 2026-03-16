import SwiftUI

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
    let modelId: String
    let message: String

    static func resolved(
        explicitModelId: String?,
        explicitMessage: String?,
        selectedModelId: String?,
        models: [HubModel]
    ) -> HubModelPickerRecommendationState? {
        let normalizedExplicitModelId = normalizedText(explicitModelId)
        let normalizedExplicitMessage = normalizedText(explicitMessage)
        if let normalizedExplicitModelId,
           let normalizedExplicitMessage {
            return HubModelPickerRecommendationState(
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

        if let exact = assessment.exactMatch {
            return HubModelPickerRecommendationState(
                modelId: fallbackModelId,
                message: "`\(exact.id)` 当前是 \(HubModelSelectionAdvisor.stateLabel(exact.state))；如果你现在就要继续，先切到已加载的 `\(fallbackModelId)` 更稳。"
            )
        }

        return HubModelPickerRecommendationState(
            modelId: fallbackModelId,
            message: "`\(selectedModelId)` 当前不在可直接执行的 inventory 里；先切到已加载的 `\(fallbackModelId)`，可以避免这轮直接掉到本地。"
        )
    }

    private static func normalizedText(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct HubModelRoutingButton: View {
    let title: String
    let identifier: String?
    let sourceLabel: String
    let presentation: ModelInfo?
    var disabled: Bool = false
    let action: () -> Void

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
                            Text("自动路由")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
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
    }
}

struct HubModelPickerPopover: View {
    let title: String
    let selectedModelId: String?
    let inheritedModelId: String?
    let inheritedModelPresentation: ModelInfo?
    let models: [HubModel]
    var focusContext: XTSectionFocusContext? = nil
    var recommendedModelId: String? = nil
    var recommendationMessage: String? = nil
    var showContextDetails: Bool = true
    var automaticTitle: String = "使用全局设置"
    var automaticSelectedBadge: String = "当前生效"
    var automaticRestoreBadge: String = "恢复继承"
    var inheritedModelLabel: String = "全局模型"
    var automaticDescription: String = "当前没有全局固定模型，恢复后会交给系统自动路由。"
    let onSelect: (String?) -> Void

    @State private var query: String = ""

    private var effectiveRecommendation: HubModelPickerRecommendationState? {
        HubModelPickerRecommendationState.resolved(
            explicitModelId: recommendedModelId,
            explicitMessage: recommendationMessage,
            selectedModelId: selectedModelId,
            models: models
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

                TextField("搜索模型 / backend / 能力", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let focusContext {
                        XTFocusContextCard(context: focusContext)
                    }

                    recommendationCard

                    autoRouteRow

                    ForEach(filteredModels) { model in
                        modelRow(model)
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
           let message = effectiveRecommendation?.message.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            let presentation = models.first(where: {
                $0.id.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(recommendedModelId) == .orderedSame
            })?.capabilityPresentationModel ?? XTModelCatalog.modelInfo(for: recommendedModelId)
            let displayTitle = presentation.displayName

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("推荐切换")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("可直接避免这轮继续撞当前配置")
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

                Button("改用 \(recommendedModelId)") {
                    onSelect(recommendedModelId)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange.opacity(0.22), lineWidth: 1)
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

    private func modelRow(_ model: HubModel) -> some View {
        let presentation = model.capabilityPresentationModel
        let isSelected = selectedModelId == model.id
        let isRecommended = normalizedRecommendedModelId == model.id && !isSelected

        return Button {
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
                                Text("推荐")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }

                            Text(HubModelSelectionAdvisor.stateLabel(model.state))
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

                    if let note = model.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if showContextDetails {
                        Text("Hub 默认上下文：\(model.hubDefaultContextLength) tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if model.isLocalModel {
                            Text("本地上限：\(model.hubMaxContextLength) tokens")
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
        }
        .buttonStyle(.plain)
    }

    private func cardBackground(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(selected ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
    }
}
