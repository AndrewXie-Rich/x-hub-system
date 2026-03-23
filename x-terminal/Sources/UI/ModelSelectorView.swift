import SwiftUI

struct ModelSelectorView: View {
    let config: AXProjectConfig?
    var focusContext: XTSectionFocusContext? = nil

    @EnvironmentObject private var appModel: AppModel
    @StateObject private var updateFeedback = XTTransientUpdateFeedbackState()
    @State private var showPopover: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { showPopover.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectorTitle)
                        HStack(spacing: 6) {
                            Text(routingSelectionState.sourceLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if updateFeedback.showsBadge {
                                XTTransientUpdateBadge(
                                    tint: .accentColor,
                                    title: "已更新"
                                )
                            }
                            if let presentation = selectedPresentationModel {
                                ModelCapabilityStrip(model: presentation, limit: 3, compact: true)
                            } else {
                                Text("自动路由")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Image(systemName: "chevron.down")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .xtTransientUpdateCardChrome(
                    cornerRadius: 6,
                    isUpdated: updateFeedback.isHighlighted,
                    focusTint: .accentColor,
                    updateTint: .accentColor,
                    baseBackground: Color(NSColor.controlBackgroundColor)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover) {
                modelList
            }
        }
        .onDisappear {
            updateFeedback.cancel(resetState: true)
        }
    }

    private var modelList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let warning = selectedModelWarningText() {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前配置提示")
                        .font(.caption.weight(.semibold))
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                Divider()
            }

            if appModel.hubInteractive {
                HubModelPickerPopover(
                    title: "为 coder 选择模型",
                    selectedModelId: explicitModelId,
                    inheritedModelId: inheritedModelId,
                    inheritedModelPresentation: routingSelectionState.inheritedPresentation,
                    models: selectableModels,
                    focusContext: focusContext,
                    recommendedModelId: selectedModelRecommendation?.modelId,
                    recommendationMessage: selectedModelRecommendation?.message,
                    showContextDetails: false,
                    automaticTitle: "自动（使用全局 / Hub 路由）",
                    automaticSelectedBadge: "当前生效",
                    automaticRestoreBadge: "恢复继承",
                    inheritedModelLabel: inheritedModelId == nil ? "自动路由" : "全局模型",
                    automaticDescription: "让 Hub 或全局配置自行路由当前 coder 模型。"
                ) { modelId in
                    updateProjectCoderModelSelection(modelId: modelId)
                    showPopover = false
                }
            } else {
                Text("Hub 未连接")
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .frame(width: 420)
    }

    private var effectiveConfig: AXProjectConfig? {
        appModel.projectConfig ?? config
    }

    private var explicitModelId: String? {
        let raw = effectiveConfig?.modelOverride(for: .coder)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var inheritedModelId: String? {
        let raw = appModel.settingsStore.settings.assignment(for: .coder).model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var routingSelectionState: HubModelRoutingSelectionState {
        HubModelRoutingSelectionState.resolved(
            explicitModelId: explicitModelId,
            inheritedModelId: inheritedModelId,
            models: selectableModels,
            explicitSourceLabel: "项目覆盖",
            inheritedSourceLabel: inheritedModelId == nil ? "自动路由" : "继承全局",
            automaticTitle: "自动"
        )
    }

    private var selectorTitle: String {
        "Coder：\(routingSelectionState.title)"
    }

    private var selectedPresentationModel: ModelInfo? {
        routingSelectionState.effectivePresentation
    }

    private var selectableModels: [HubModel] {
        let source = appModel.modelsState.models
        var dedup: [String: HubModel] = [:]
        for model in source {
            dedup[model.id] = model
        }
        return dedup.values.sorted { a, b in
            let sa = stateRank(a.state)
            let sb = stateRank(b.state)
            if sa != sb { return sa < sb }
            let an = (a.name.isEmpty ? a.id : a.name).lowercased()
            let bn = (b.name.isEmpty ? b.id : b.name).lowercased()
            if an != bn { return an < bn }
            return a.id.lowercased() < b.id.lowercased()
        }
    }

    private var selectedModelId: String? {
        routingSelectionState.identifier
    }

    private var selectedModelAssessment: HubModelAvailabilityAssessment? {
        guard let selectedModelId else { return nil }
        return HubModelSelectionAdvisor.assess(
            requestedId: selectedModelId,
            snapshot: appModel.modelsState
        )
    }

    private var selectedModelRecommendation: (modelId: String, message: String)? {
        let projectContext = appModel.projectRoot.map { AXProjectContext(root: $0) }
        if let guidance = AXProjectModelRouteMemoryStore.selectionGuidance(
            configuredModelId: selectedModelId,
            role: .coder,
            ctx: projectContext,
            snapshot: appModel.modelsState
        ),
           let recommendedModelId = guidance.recommendedModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !recommendedModelId.isEmpty {
            let message = guidance.recommendationText?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                recommendedModelId,
                (message?.isEmpty == false ? message! : guidance.warningText)
            )
        }

        guard let selectedModelId,
              let assessment = selectedModelAssessment,
              !assessment.isExactMatchLoaded else {
            return nil
        }
        guard let rawCandidate = assessment.loadedCandidates.first?.id else {
            return nil
        }
        let candidate = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              candidate.caseInsensitiveCompare(selectedModelId) != .orderedSame else {
            return nil
        }

        if let blocked = assessment.nonInteractiveExactMatch {
            return (
                candidate,
                "`\(blocked.id)` 是检索专用模型，Supervisor 会按需调用它做 retrieval；当前对话先切到 `\(candidate)` 更稳。"
            )
        }

        if let exact = assessment.exactMatch {
            return (
                candidate,
                "`\(exact.id)` 当前是 \(HubModelSelectionAdvisor.stateLabel(exact.state))；如果你现在就要继续，先切到已加载的 `\(candidate)` 更稳。"
            )
        }

        return (
            candidate,
            "`\(selectedModelId)` 当前不在可直接执行的 inventory 里；先切到已加载的 `\(candidate)`，可以避免这轮直接掉到本地。"
        )
    }

    private func selectedModelWarningText() -> String? {
        let projectContext = appModel.projectRoot.map { AXProjectContext(root: $0) }
        if let routeWarning = AXProjectModelRouteMemoryStore.selectionWarningText(
            configuredModelId: selectedModelId,
            role: .coder,
            ctx: projectContext,
            snapshot: appModel.modelsState
        ) {
            return routeWarning
        }

        guard let selectedModelId else { return nil }
        let sourceLabel = explicitModelId == nil ? "继承的全局模型" : "项目覆盖模型"
        guard let assessment = selectedModelAssessment else { return "当前无法确认\(sourceLabel) `\(selectedModelId)` 是否可用。" }
        guard !assessment.isExactMatchLoaded else { return nil }

        if let blocked = assessment.nonInteractiveExactMatch,
           let reason = assessment.interactiveRoutingBlockedReason {
            let suggestions = suggestedCandidates(from: assessment)
            if let first = suggestions.first {
                return "\(sourceLabel) `\(blocked.id)` 当前是检索专用模型。\(reason) 可先改用 `\(first)`，或恢复 Auto。"
            }
            return "\(sourceLabel) `\(blocked.id)` 当前是检索专用模型。\(reason)"
        }

        if let exact = assessment.exactMatch {
            let suggestions = suggestedCandidates(from: assessment)
            if let first = suggestions.first {
                return "\(sourceLabel) `\(exact.id)` 当前状态是 \(HubModelSelectionAdvisor.stateLabel(exact.state))，这轮请求可能回退到本地。可先改用 `\(first)`。"
            }
            return "\(sourceLabel) `\(exact.id)` 当前状态是 \(HubModelSelectionAdvisor.stateLabel(exact.state))，这轮请求可能回退到本地。"
        }

        let suggestions = suggestedCandidates(from: assessment)
        if !suggestions.isEmpty {
            return "\(sourceLabel) `\(selectedModelId)` 不在当前 inventory 里。可先改用 `\(suggestions.joined(separator: "`, `"))`。"
        }
        return "\(sourceLabel) `\(selectedModelId)` 不在当前 inventory 里，这轮请求可能直接走本地模式。"
    }

    private func suggestedCandidates(from assessment: HubModelAvailabilityAssessment) -> [String] {
        let source = assessment.loadedCandidates.isEmpty ? assessment.inventoryCandidates : assessment.loadedCandidates
        return source.prefix(3).map(\.id)
    }

    private func stateRank(_ s: HubModelState) -> Int {
        switch s {
        case .loaded: return 0
        case .available: return 1
        case .sleeping: return 2
        }
    }

    private func updateProjectCoderModelSelection(modelId: String?) {
        let trimmedModelId = modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModelId = trimmedModelId?.isEmpty == false ? trimmedModelId : nil
        guard normalizedModelOverrideValue(explicitModelId) != normalizedModelOverrideValue(normalizedModelId) else {
            return
        }

        appModel.setProjectRoleModel(role: .coder, modelId: normalizedModelId)
        updateFeedback.trigger()
    }

    private func normalizedModelOverrideValue(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
