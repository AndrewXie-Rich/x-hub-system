import SwiftUI

struct ModelSelectorView: View {
    let projectContext: AXProjectContext?
    let config: AXProjectConfig?
    var focusContext: XTSectionFocusContext? = nil

    @EnvironmentObject private var appModel: AppModel
    @StateObject private var modelManager = HubModelManager.shared
    @StateObject private var updateFeedback = XTTransientUpdateFeedbackState()
    @State private var showPopover: Bool = false
    @State private var visibleModelInventory = XTVisibleHubModelInventory.empty

    init(
        projectContext: AXProjectContext? = nil,
        config: AXProjectConfig?,
        focusContext: XTSectionFocusContext? = nil
    ) {
        self.projectContext = projectContext
        self.config = config
        self.focusContext = focusContext
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { showPopover.toggle() }) {
                VStack(alignment: .leading, spacing: 6) {
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
                                        title: XTL10n.Common.updated.resolve(interfaceLanguage)
                                    )
                                }
                                if let presentation = selectedPresentationModel {
                                    ModelCapabilityStrip(model: presentation, limit: 3, compact: true)
                                } else {
                                    Text(XTL10n.Common.automaticRouting.resolve(interfaceLanguage))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Image(systemName: "chevron.down")
                    }

                    if let routeTruth = currentProjectRouteTruth,
                       routeTruth.compactButtonPresentation.hasContent {
                        HubModelRoutingSupplementaryContent(
                            presentation: routeTruth.compactButtonPresentation,
                            showsBackground: false
                        )
                    }
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
            .help(currentProjectRouteTruth?.tooltip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            .popover(isPresented: $showPopover) {
                modelList
            }
        }
        .onDisappear {
            updateFeedback.cancel(resetState: true)
        }
        .onAppear {
            modelManager.setAppModel(appModel)
            syncVisibleModelInventory()
        }
        .onChange(of: modelInventorySnapshot) { _ in
            syncVisibleModelInventory()
        }
    }

    private var modelList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if modelInventoryTruth.showsStatusCard {
                VStack(alignment: .leading, spacing: 0) {
                    XTModelInventoryTruthCard(presentation: modelInventoryTruth)
                        .padding(12)
                    Divider()
                }
            }

            if let warning = selectedModelWarningText() {
                VStack(alignment: .leading, spacing: 6) {
                    Text(XTL10n.ModelSelector.currentConfigurationTitle.resolve(interfaceLanguage))
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
                    title: XTL10n.ModelSelector.pickerTitle(language: interfaceLanguage),
                    selectedModelId: explicitModelId,
                    inheritedModelId: inheritedModelId,
                    inheritedModelPresentation: routingSelectionState.inheritedPresentation,
                    models: selectableModels,
                    language: interfaceLanguage,
                    focusContext: focusContext,
                    recommendation: selectedModelRecommendation,
                    selectionTruth: currentProjectRouteTruth,
                    selectionTruthTitle: currentProjectRouteTruthTitle,
                    showContextDetails: false,
                    automaticTitle: XTL10n.ModelSelector.automaticPopoverTitle(language: interfaceLanguage),
                    automaticSelectedBadge: XTL10n.ModelSelector.automaticSelectedBadge.resolve(interfaceLanguage),
                    automaticRestoreBadge: XTL10n.ModelSelector.automaticRestoreBadge.resolve(interfaceLanguage),
                    inheritedModelLabel: XTL10n.ModelSelector.inheritedModelLabel(
                        inheritedModelId: inheritedModelId,
                        language: interfaceLanguage
                    ),
                    automaticDescription: XTL10n.ModelSelector.automaticDescription.resolve(interfaceLanguage)
                ) { modelId in
                    updateProjectCoderModelSelection(modelId: modelId)
                    showPopover = false
                }
            } else {
                Text(XTL10n.ModelSelector.hubDisconnected.resolve(interfaceLanguage))
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .frame(width: 420)
    }

    private var effectiveConfig: AXProjectConfig? {
        guard let effectiveProjectContext else {
            return appModel.projectConfig ?? config
        }
        if appModel.projectContext?.root.standardizedFileURL == effectiveProjectContext.root.standardizedFileURL,
           let current = appModel.projectConfig {
            return current
        }
        return (try? AXProjectStore.loadOrCreateConfig(for: effectiveProjectContext))
            ?? config
            ?? .default(forProjectRoot: effectiveProjectContext.root)
    }

    private var explicitModelId: String? {
        let raw = effectiveConfig?.modelOverride(for: .coder)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var inheritedModelId: String? {
        let raw = appModel.settingsStore.settings.assignment(for: .coder).model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var interfaceLanguage: XTInterfaceLanguage {
        appModel.settingsStore.settings.interfaceLanguage
    }

    private var routingSelectionState: HubModelRoutingSelectionState {
        HubModelRoutingSelectionState.resolved(
            explicitModelId: explicitModelId,
            inheritedModelId: inheritedModelId,
            models: selectableModels,
            explicitSourceLabel: XTL10n.ModelSelector.explicitSourceLabel(language: interfaceLanguage),
            inheritedSourceLabel: XTL10n.ModelSelector.inheritedSourceLabel(
                inheritedModelId: inheritedModelId,
                language: interfaceLanguage
            ),
            automaticTitle: XTL10n.ModelSelector.automaticTitle(language: interfaceLanguage)
        )
    }

    private var selectorTitle: String {
        XTL10n.ModelSelector.selectorTitle(
            selectionTitle: routingSelectionState.title,
            language: interfaceLanguage
        )
    }

    private var selectedPresentationModel: ModelInfo? {
        routingSelectionState.effectivePresentation
    }

    private var effectiveProjectContext: AXProjectContext? {
        projectContext ?? appModel.projectContext ?? appModel.projectRoot.map { AXProjectContext(root: $0) }
    }

    private var currentProjectID: String? {
        effectiveProjectContext.map { AXProjectRegistryStore.projectId(forRoot: $0.root) }
    }

    private var currentProjectName: String? {
        guard let effectiveProjectContext else { return nil }
        let projectID = AXProjectRegistryStore.projectId(forRoot: effectiveProjectContext.root)
        return appModel.registry.project(for: projectID)?.displayName
            ?? AXProjectRegistryStore.displayName(
                forRoot: effectiveProjectContext.root,
                registry: appModel.registry
            )
    }

    private var currentProjectRouteTruthTitle: String {
        XTL10n.text(
            interfaceLanguage,
            zhHans: "Coder · 当前项目 Route Truth",
            en: "Coder · Current Project Route Truth"
        )
    }

    private var currentProjectRouteTruth: HubModelRoutingSupplementaryPresentation? {
        guard let effectiveProjectContext else { return nil }
        let snapshot = AXRoleExecutionSnapshots.latestSnapshots(for: effectiveProjectContext)[.coder]
            ?? .empty(role: .coder, source: "model_selector")
        return HubModelRoutingTruthBuilder.build(
            surface: .projectRoleSettings,
            role: .coder,
            selectedProjectID: currentProjectID,
            selectedProjectName: currentProjectName,
            projectConfig: effectiveConfig,
            settings: appModel.settingsStore.settings,
            snapshot: snapshot,
            transportMode: HubAIClient.transportMode().rawValue,
            language: interfaceLanguage
        )
        .pickerTruth
    }

    private var selectableModels: [HubModel] {
        visibleModelInventory.sortedModels
    }

    private var selectedModelId: String? {
        routingSelectionState.identifier
    }

    private var selectedModelAssessment: HubModelAvailabilityAssessment? {
        guard let selectedModelId else { return nil }
        return HubModelSelectionAdvisor.assess(
            requestedId: selectedModelId,
            snapshot: modelInventorySnapshot
        )
    }

    private var selectedModelRecommendation: HubModelPickerRecommendationState? {
        if let guidance = AXProjectModelRouteMemoryStore.selectionGuidance(
            configuredModelId: selectedModelId,
            role: .coder,
            ctx: effectiveProjectContext,
            snapshot: modelInventorySnapshot,
            paidAccessSnapshot: appModel.hubRemotePaidAccessSnapshot,
            language: interfaceLanguage
        ),
           let recommendedModelId = guidance.recommendedModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !recommendedModelId.isEmpty {
            let message = guidance.recommendationText?.trimmingCharacters(in: .whitespacesAndNewlines)
            return HubModelPickerRecommendationState(
                kind: HubModelPickerRecommendationKind(guidance.recommendationKind),
                modelId: recommendedModelId,
                message: (message?.isEmpty == false ? message! : guidance.warningText)
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
            return HubModelPickerRecommendationState(
                kind: .switchRecommended,
                modelId: candidate,
                message: XTL10n.ModelSelector.nonInteractiveRecommendation(
                    blockedId: blocked.id,
                    candidate: candidate,
                    language: interfaceLanguage
                )
            )
        }

        if let exact = assessment.exactMatch {
            return HubModelPickerRecommendationState(
                kind: .switchRecommended,
                modelId: candidate,
                message: XTL10n.ModelSelector.exactStateRecommendation(
                    exactId: exact.id,
                    stateLabel: XTL10n.HubModelStateCopy.label(
                        exact.state,
                        language: interfaceLanguage
                    ),
                    candidate: candidate,
                    language: interfaceLanguage
                )
            )
        }

        return HubModelPickerRecommendationState(
            kind: .switchRecommended,
            modelId: candidate,
            message: XTL10n.ModelSelector.missingRecommendation(
                selectedModelId: selectedModelId,
                candidate: candidate,
                language: interfaceLanguage
            )
        )
    }

    private func selectedModelWarningText() -> String? {
        if let routeWarning = AXProjectModelRouteMemoryStore.selectionWarningText(
            configuredModelId: selectedModelId,
            role: .coder,
            ctx: effectiveProjectContext,
            snapshot: modelInventorySnapshot,
            paidAccessSnapshot: appModel.hubRemotePaidAccessSnapshot,
            language: interfaceLanguage
        ) {
            return appendingGrpcRouteInterpretationWarning(
                routeWarning,
                configuredModelId: selectedModelId ?? "",
                snapshot: currentProjectExecutionSnapshot
            )
        }

        guard let selectedModelId else { return nil }
        let sourceLabel = explicitModelId == nil
            ? XTL10n.text(interfaceLanguage, zhHans: "继承的全局模型", en: "Inherited Global Model")
            : XTL10n.text(interfaceLanguage, zhHans: "项目覆盖模型", en: "Project Override Model")
        guard let assessment = selectedModelAssessment else {
            return appendingGrpcRouteInterpretationWarning(
                XTL10n.ModelSelector.availabilityUnknown(
                    sourceLabel: sourceLabel,
                    selectedModelId: selectedModelId,
                    language: interfaceLanguage
                ),
                configuredModelId: selectedModelId,
                snapshot: currentProjectExecutionSnapshot
            )
        }
        guard !assessment.isExactMatchLoaded else { return nil }

        if let blocked = assessment.nonInteractiveExactMatch,
           let reason = assessment.interactiveRoutingBlockedReason {
            let suggestions = suggestedCandidates(from: assessment)
            return appendingGrpcRouteInterpretationWarning(
                XTL10n.ModelSelector.nonInteractiveWarning(
                    sourceLabel: sourceLabel,
                    blockedId: blocked.id,
                    reason: reason,
                    suggested: suggestions.first,
                    language: interfaceLanguage
                ),
                configuredModelId: selectedModelId,
                snapshot: currentProjectExecutionSnapshot
            )
        }

        if let exact = assessment.exactMatch {
            let suggestions = suggestedCandidates(from: assessment)
            return appendingGrpcRouteInterpretationWarning(
                XTL10n.ModelSelector.exactStateWarning(
                    sourceLabel: sourceLabel,
                    exactId: exact.id,
                    stateLabel: XTL10n.HubModelStateCopy.label(
                        exact.state,
                        language: interfaceLanguage
                    ),
                    suggested: suggestions.first,
                    language: interfaceLanguage
                ),
                configuredModelId: selectedModelId,
                snapshot: currentProjectExecutionSnapshot
            )
        }

        let suggestions = suggestedCandidates(from: assessment)
        if !suggestions.isEmpty {
            return appendingGrpcRouteInterpretationWarning(
                XTL10n.text(
                    interfaceLanguage,
                    zhHans: "\(sourceLabel) `\(selectedModelId)` 不在当前模型清单里。如果你要立刻继续，可改用 `\(suggestions.joined(separator: "`, `"))`。",
                    en: "The \(sourceLabel.lowercased()) `\(selectedModelId)` is not in the current model list. If you want to continue right now, switch to `\(suggestions.joined(separator: "`, `"))`."
                ),
                configuredModelId: selectedModelId,
                snapshot: currentProjectExecutionSnapshot
            )
        }
        return appendingGrpcRouteInterpretationWarning(
            XTL10n.text(
                interfaceLanguage,
                zhHans: "\(sourceLabel) `\(selectedModelId)` 不在当前模型清单里，这轮请求可能直接走本地模式。",
                en: "The \(sourceLabel.lowercased()) `\(selectedModelId)` is not in the current model list, so this request may go straight to local mode."
            ),
            configuredModelId: selectedModelId,
            snapshot: currentProjectExecutionSnapshot
        )
    }

    private var currentProjectExecutionSnapshot: AXRoleExecutionSnapshot {
        guard let effectiveProjectContext else {
            return .empty(role: .coder, source: "model_selector")
        }
        return AXRoleExecutionSnapshots.latestSnapshots(for: effectiveProjectContext)[.coder]
            ?? .empty(role: .coder, source: "model_selector")
    }

    private func appendingGrpcRouteInterpretationWarning(
        _ warning: String,
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> String {
        let hint = ExecutionRoutePresentation.grpcTransportMismatchHint(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            transportMode: HubAIClient.transportMode().rawValue,
            language: interfaceLanguage
        )
        return hint.isEmpty ? warning : warning + hint
    }

    private var modelInventorySnapshot: ModelStateSnapshot {
        modelManager.visibleSnapshot(fallback: appModel.modelsState)
    }

    private var modelInventoryTruth: XTModelInventoryTruthPresentation {
        XTModelInventoryTruthPresentation.build(
            snapshot: modelInventorySnapshot,
            hubBaseDir: appModel.hubBaseDir ?? HubPaths.baseDir()
        )
    }

    private func suggestedCandidates(from assessment: HubModelAvailabilityAssessment) -> [String] {
        let source = assessment.loadedCandidates.isEmpty ? assessment.inventoryCandidates : assessment.loadedCandidates
        return source.prefix(3).map(\.id)
    }

    private func syncVisibleModelInventory() {
        visibleModelInventory = XTVisibleHubModelInventorySupport.build(
            snapshot: modelInventorySnapshot
        )
    }

    private func updateProjectCoderModelSelection(modelId: String?) {
        let trimmedModelId = modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModelId = trimmedModelId?.isEmpty == false ? trimmedModelId : nil
        guard normalizedModelOverrideValue(explicitModelId) != normalizedModelOverrideValue(normalizedModelId) else {
            return
        }

        if let effectiveProjectContext {
            appModel.setProjectRoleModel(for: effectiveProjectContext, role: .coder, modelId: normalizedModelId)
        } else {
            appModel.setProjectRoleModel(role: .coder, modelId: normalizedModelId)
        }
        updateFeedback.trigger()
    }

    private func normalizedModelOverrideValue(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
