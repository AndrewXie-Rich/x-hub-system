import SwiftUI

struct ModelSettingsView: View {
    let standaloneWindow: Bool

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var modelManager = HubModelManager.shared
    @StateObject private var supervisorManager = SupervisorManager.shared
    @StateObject private var roleModelUpdateFeedback = XTTransientUpdateFeedbackState()
    @State private var selectedRole: AXRole = .supervisor
    @State private var showRoleModelPicker = false
    @State private var activeFocusRequest: XTModelSettingsFocusRequest?
    @State private var roleModelChangeNotice: XTSettingsChangeNotice?
    @State private var visibleModelInventory = XTVisibleHubModelInventory.empty

    init(standaloneWindow: Bool = false) {
        self.standaloneWindow = standaloneWindow
    }

    private var interfaceLanguage: XTInterfaceLanguage {
        appModel.settingsStore.settings.interfaceLanguage
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            
            Divider()
            
            if modelManager.isLoading {
                ProgressView(XTL10n.text(
                    interfaceLanguage,
                    zhHans: "正在加载模型列表...",
                    en: "Loading model list..."
                ))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if let error = modelManager.error {
                Text(XTL10n.text(
                    interfaceLanguage,
                    zhHans: "加载失败：\(error)",
                    en: "Failed to load: \(error)"
                ))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                modelSelectionArea
            }
        }
        .padding(16)
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            modelManager.setAppModel(appModel)
            processModelSettingsFocusRequest()
            syncVisibleModelInventory()
            Task {
                await modelManager.fetchModels()
            }
        }
        .onChange(of: modelInventorySnapshot) { _ in
            syncVisibleModelInventory()
        }
        .onChange(of: appModel.modelSettingsFocusRequest?.nonce) { _ in
            processModelSettingsFocusRequest()
        }
        .onDisappear {
            resetRoleModelFeedback()
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(XTL10n.text(
                    interfaceLanguage,
                    zhHans: "AI 模型设置",
                    en: "AI Model Settings"
                ))
                    .font(.title2)
                Spacer()
                
                Button(XTL10n.text(
                    interfaceLanguage,
                    zhHans: "刷新模型列表",
                    en: "Refresh Models"
                )) {
                    Task {
                        await modelManager.fetchModels()
                    }
                }
                .buttonStyle(.bordered)

                if standaloneWindow {
                    Button(XTL10n.text(
                        interfaceLanguage,
                        zhHans: "关闭",
                        en: "Close"
                    )) {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Text(XTL10n.text(
                interfaceLanguage,
                zhHans: "Supervisor 和 Coding 的 AI 都来自于 X-Hub。如果 X-Hub 有默认设置，X-Terminal 没有设置就用 Hub 默认设置。如果没有，可以在 X-Terminal 选择使用哪个模型作为 Supervisor，哪个模型作为主要编程角色。Supervisor 也可以建议或自己指派每个 project 的编程模型。",
                en: "Supervisor and coding roles both run on X-Hub. If Hub already has a default, X-Terminal will inherit it unless you pin a model here. Otherwise you can choose which model should act as Supervisor and which model should handle the main coding role. Supervisor can also recommend or assign project-specific coding models."
            ))
                .font(.body)
                .foregroundStyle(.secondary)

            Text(XTL10n.text(
                interfaceLanguage,
                zhHans: "本页展示的是 Hub 当前返回给 XT 的真实可用模型视图，不是 XT 本地猜测。若某个 paired Terminal 需要独立的本地加载配置覆盖，例如 `ctx / ttl / par / id`，请到 Hub 的 Pairing / Edit Device 里设置每设备 local model override。",
                en: "This page shows the true runnable model view currently returned by Hub to XT, not a local guess inside XT. If a paired terminal needs its own local load override such as `ctx / ttl / par / id`, configure the per-device local model override in Hub Pairing / Edit Device."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let context = activeFocusRequest?.context {
                XTFocusContextCard(context: context)
            }
        }
    }
    
    private var modelSelectionArea: some View {
        VStack(alignment: .leading, spacing: 20) {
            roleSelector
            
            Divider()
            
            modelList
        }
    }

    private func processModelSettingsFocusRequest() {
        guard let request = appModel.modelSettingsFocusRequest else { return }
        activeFocusRequest = request
        if let role = request.role {
            selectedRole = role
            showRoleModelPicker = false
            resetRoleModelFeedback()
        }
        appModel.clearModelSettingsFocusRequest(request)
        scheduleFocusContextClear(nonce: request.nonce)
    }

    private func scheduleFocusContextClear(nonce: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if activeFocusRequest?.nonce == nonce {
                activeFocusRequest = nil
            }
        }
    }
    
    private var roleSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(XTL10n.text(
                interfaceLanguage,
                zhHans: "选择要配置的角色",
                en: "Choose Role to Configure"
            ))
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AXRole.allCases) { role in
                        roleButton(role)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func roleButton(_ role: AXRole) -> some View {
        Button(action: {
            selectedRole = role
            showRoleModelPicker = false
            resetRoleModelFeedback()
        }) {
            HStack(spacing: 8) {
                roleIcon(role)
                Text(role.displayName(in: interfaceLanguage))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(selectedRole == role ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .foregroundStyle(selectedRole == role ? .white : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private func roleIcon(_ role: AXRole) -> some View {
        Image(systemName: iconName(for: role))
            .font(.system(size: 16))
    }
    
    private func iconName(for role: AXRole) -> String {
        switch role {
        case .supervisor:
            return "person.3.fill"
        case .coder:
            return "hammer.fill"
        case .coarse:
            return "doc.text.fill"
        case .refine:
            return "sparkles"
        case .reviewer:
            return "checkmark.circle.fill"
        case .advisor:
            return "lightbulb.fill"
        }
    }
    
    private var modelList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(XTL10n.text(
                interfaceLanguage,
                zhHans: "为 \(selectedRole.displayName(in: interfaceLanguage)) 配置默认模型",
                en: "Configure Default Model for \(selectedRole.displayName(in: interfaceLanguage))"
            ))
                .font(.headline)

            routeTruthCard

            if shouldShowRemotePaidAccessCard {
                remotePaidAccessCard
            }

            if modelInventoryTruth.showsStatusCard && !sortedAvailableHubModels.isEmpty {
                XTModelInventoryTruthCard(presentation: modelInventoryTruth)
            }

            if roleModelUpdateFeedback.showsBadge,
               let roleModelChangeNotice {
                XTSettingsChangeNoticeInlineView(
                    notice: roleModelChangeNotice,
                    tint: .accentColor
                )
            }

            if let issue = selectedRoleIssue {
                HStack(alignment: .top, spacing: 10) {
                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let suggestedModelId = issue.suggestedModelId {
                        Button(XTL10n.text(
                            interfaceLanguage,
                            zhHans: "改用推荐",
                            en: "Use Recommended"
                        )) {
                            updateRoleModelSelection(modelId: suggestedModelId)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(XTL10n.text(
                            interfaceLanguage,
                            zhHans: "把 \(selectedRole.displayName(in: interfaceLanguage)) 直接切到 `\(suggestedModelId)`。",
                            en: "Switch \(selectedRole.displayName(in: interfaceLanguage)) directly to `\(suggestedModelId)`."
                        ))
                    }
                }
            }
            
            if sortedAvailableHubModels.isEmpty {
                XTModelInventoryTruthCard(presentation: modelInventoryTruth)
            } else {
                HubModelRoutingButton(
                    title: routingSelectionState.title,
                    identifier: routingSelectionState.identifier,
                    sourceLabel: routingSelectionState.sourceLabel,
                    presentation: routingSelectionState.effectivePresentation,
                    sourceIdentityLine: currentRoleSelectedHubModel?.remoteSourceIdentityLine(language: interfaceLanguage),
                    sourceBadges: currentRoleSelectedHubModel?.routingSourceBadges(language: interfaceLanguage) ?? [],
                    supplementary: routeTruthPresentation.pickerTruth,
                    disabled: !appModel.hubInteractive || sortedAvailableHubModels.isEmpty,
                    automaticRouteLabel: XTL10n.Common.automaticRouting.resolve(interfaceLanguage)
                ) {
                    showRoleModelPicker = true
                }
                .frame(maxWidth: 480, alignment: .leading)
                .popover(isPresented: $showRoleModelPicker, arrowEdge: .bottom) {
                    HubModelPickerPopover(
                        title: XTL10n.text(
                            interfaceLanguage,
                            zhHans: "为 \(selectedRole.displayName(in: interfaceLanguage)) 选择默认模型",
                            en: "Choose Default Model for \(selectedRole.displayName(in: interfaceLanguage))"
                        ),
                        selectedModelId: currentRoleModelId,
                        inheritedModelId: nil,
                        inheritedModelPresentation: nil,
                        models: sortedAvailableHubModels,
                        language: interfaceLanguage,
                        selectionTruth: routeTruthPresentation.pickerTruth,
                        selectionTruthTitle: XTL10n.text(
                            interfaceLanguage,
                            zhHans: "\(selectedRole.displayName(in: interfaceLanguage)) · 当前 Route Truth",
                            en: "\(selectedRole.displayName(in: interfaceLanguage)) · Current Route Truth"
                        ),
                        automaticTitle: XTL10n.text(
                            interfaceLanguage,
                            zhHans: "使用 Hub 默认设置",
                            en: "Use Hub Default Setting"
                        ),
                        automaticSelectedBadge: XTL10n.text(
                            interfaceLanguage,
                            zhHans: "当前默认",
                            en: "Current Default"
                        ),
                        automaticRestoreBadge: XTL10n.text(
                            interfaceLanguage,
                            zhHans: "恢复默认",
                            en: "Restore Default"
                        ),
                        inheritedModelLabel: XTL10n.text(
                            interfaceLanguage,
                            zhHans: "Hub 默认",
                            en: "Hub Default"
                        ),
                        automaticDescription: XTL10n.text(
                            interfaceLanguage,
                            zhHans: "当前没有为这个角色单独绑定固定模型，会继续使用 Hub 默认/自动路由。",
                            en: "There is no pinned model for this role right now, so XT will keep using the Hub default / automatic routing."
                        )
                    ) { modelId in
                        updateRoleModelSelection(modelId: modelId)
                        showRoleModelPicker = false
                    }
                    .frame(width: 460, height: 420)
                }

                Text(currentRoleModelId == nil
                     ? XTL10n.text(
                        interfaceLanguage,
                        zhHans: "当前未为这个角色固定具体模型，运行时会继续走 Hub 默认/自动路由。",
                        en: "No concrete model is pinned for this role right now, so runtime will keep using the Hub default / automatic routing."
                     )
                     : XTL10n.text(
                        interfaceLanguage,
                        zhHans: "当前已为这个角色固定具体模型；如果清空绑定，会回到 Hub 默认/自动路由。",
                        en: "A concrete model is currently pinned for this role. If you clear the binding, XT will return to the Hub default / automatic routing."
                     ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text(XTL10n.text(
                    interfaceLanguage,
                    zhHans: "Hub 模型目录预览",
                    en: "Hub Model Catalog Preview"
                ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(sortedAvailableHubModels) { model in
                            modelRow(model)
                        }
                    }
                }
            }
        }
        .xtTransientUpdateCardChrome(
            cornerRadius: 10,
            isUpdated: roleModelUpdateFeedback.isHighlighted,
            focusTint: .accentColor,
            updateTint: .accentColor,
            baseBackground: .clear
        )
    }

    private var routeTruthCard: some View {
        let presentation = routeTruthPresentation
        let snapshot = selectedRoleExecutionSnapshot

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)

                Text(snapshot.hasRecord
                     ? ExecutionRoutePresentation.statusText(snapshot: snapshot)
                     : XTL10n.text(
                        interfaceLanguage,
                        zhHans: "待观察",
                        en: "Pending"
                     ))
                    .font(.caption2.monospaced())
                    .foregroundStyle(snapshot.hasRecord ? ExecutionRoutePresentation.statusColor(snapshot: snapshot) : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Capsule())
            }

            Text(presentation.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(presentation.lines, id: \.self) { line in
                Text(line)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var remotePaidAccessCard: some View {
        let projection = remotePaidAccessProjection

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(XTL10n.text(
                    interfaceLanguage,
                    zhHans: "远端付费模型额度",
                    en: "Remote Paid-Model Budget"
                ))
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)

                Text(remotePaidAccessBadgeText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(remotePaidAccessBadgeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(remotePaidAccessBadgeColor.opacity(0.10))
                    .clipShape(Capsule())
            }

            Text(remotePaidAccessSummaryText)
                .font(.caption)
                .foregroundStyle(projection?.trustProfilePresent == false ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(XTL10n.text(
                interfaceLanguage,
                zhHans: "这里展示的是 paired device 当前回报给 XT 的真实额度，不是 XT 在本地按上下文长度反推出来的估算值。",
                en: "This shows the real paid-model budget currently reported by the paired device, not a local estimate inferred from context size."
            ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
    
    private func modelRow(_ model: HubModel) -> some View {
        let isSelected = currentRoleModelId == model.id
        let presentation = model.capabilityPresentationModel
        let isSelectable = model.isSelectableForInteractiveRouting
        
        return Button(action: {
            guard isSelectable else { return }
            updateRoleModelSelection(modelId: model.id)
        }) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(presentation.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        if model.state == .loaded {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        
                        Text(model.backend)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if model.interactiveRoutingDisabledReason != nil {
                            Text(XTL10n.text(
                                interfaceLanguage,
                                zhHans: "检索专用",
                                en: "Retrieval Only"
                            ))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if presentation.displayName != model.id {
                        Text(model.id)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    ModelCapabilityStrip(model: presentation, limit: 5)

                    if let capabilitySummary = model.capabilitySummaryLine {
                        Text(capabilitySummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    if let note = model.note, !note.isEmpty {
                        Text(note)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let disabledReason = model.interactiveRoutingDisabledReason {
                        Text(disabledReason)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Text(model.defaultLoadConfigDisplayLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let localLoadConfigLimitLine = model.localLoadConfigLimitLine {
                        Text(localLoadConfigLimitLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let roles = model.roles, !roles.isEmpty {
                        Text(XTL10n.text(
                            interfaceLanguage,
                            zhHans: "角色：\(roles.joined(separator: ", "))",
                            en: "Roles: \(roles.joined(separator: ", "))"
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                }
            }
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .opacity(isSelectable ? 1.0 : 0.72)
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
    }

    private var selectedRoleIssue: HubGlobalRoleModelIssue? {
        let configured = currentRoleModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !configured.isEmpty else { return nil }
        return HubModelSelectionAdvisor.globalAssignmentIssue(
            for: selectedRole,
            configuredModelId: configured,
            snapshot: visibleModelInventory.snapshot,
            language: interfaceLanguage
        )
    }

    private var currentRoleModelId: String? {
        let raw = (modelManager.getPreferredModel(for: selectedRole) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    private var sortedAvailableHubModels: [HubModel] {
        visibleModelInventory.sortedModels
    }

    private var routingSelectionState: HubModelRoutingSelectionState {
        let explicitModelId = currentRoleModelId
        let explicitPresentation = visibleModelInventory.presentation(for: explicitModelId)
        return HubModelRoutingSelectionState(
            explicitModelId: explicitModelId,
            inheritedModelId: nil,
            explicitPresentation: explicitPresentation,
            inheritedPresentation: nil,
            explicitSourceLabel: XTL10n.text(
                interfaceLanguage,
                zhHans: "全局绑定",
                en: "Global Override"
            ),
            inheritedSourceLabel: XTL10n.text(
                interfaceLanguage,
                zhHans: "Hub 默认",
                en: "Hub Default"
            ),
            automaticTitle: XTL10n.text(
                interfaceLanguage,
                zhHans: "使用 Hub 默认设置",
                en: "Use Hub Default Setting"
            )
        )
    }

    private var currentRoleSelectedHubModel: HubModel? {
        visibleModelInventory.model(for: currentRoleModelId)
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

    private var remotePaidAccessProjection: XTUnifiedDoctorRemotePaidAccessProjection? {
        appModel.hubRemotePaidAccessSnapshot.map(XTUnifiedDoctorRemotePaidAccessProjection.init)
    }

    private var shouldShowRemotePaidAccessCard: Bool {
        appModel.hubRemoteConnected
            || appModel.hubRemoteRoute != .none
            || remotePaidAccessProjection != nil
    }

    private var remotePaidAccessBadgeText: String {
        guard let projection = remotePaidAccessProjection else {
            return XTL10n.text(
                interfaceLanguage,
                zhHans: "未回报",
                en: "Not Reported"
            )
        }
        return projection.trustProfilePresent
            ? XTL10n.text(interfaceLanguage, zhHans: "已接管", en: "Trusted")
            : XTL10n.text(interfaceLanguage, zhHans: "旧授权", en: "Legacy")
    }

    private var remotePaidAccessBadgeColor: Color {
        guard let projection = remotePaidAccessProjection else {
            return .secondary
        }
        return projection.trustProfilePresent ? .green : .orange
    }

    private var remotePaidAccessSummaryText: String {
        if let projection = remotePaidAccessProjection {
            return projection.compactBudgetLine
        }
        return XTL10n.text(
            interfaceLanguage,
            zhHans: "这台远端设备暂时还没有把额度真值回报给 XT。先刷新模型列表，或等待下一次远端路由同步。",
            en: "The paired remote device has not reported budget truth to XT yet. Refresh the model list or wait for the next remote-route sync."
        )
    }

    private var selectedScopedProjectID: String? {
        guard let projectID = appModel.selectedProjectId,
              projectID != AXProjectRegistry.globalHomeId else {
            return nil
        }
        return projectID
    }

    private var selectedScopedProjectName: String? {
        guard let selectedScopedProjectID else { return nil }
        return appModel.registry.project(for: selectedScopedProjectID)?.displayName
    }

    private var selectedScopedProjectContext: AXProjectContext? {
        selectedScopedProjectID.flatMap(appModel.projectContext(for:))
    }

    private var selectedScopedProjectConfig: AXProjectConfig? {
        guard let selectedScopedProjectContext else { return nil }
        return appModel.projectConfigSnapshot(for: selectedScopedProjectContext)
    }

    private var selectedRoleExecutionSnapshot: AXRoleExecutionSnapshot {
        if selectedRole == .supervisor {
            return ExecutionRoutePresentation.supervisorSnapshot(from: supervisorManager)
        }

        guard let projectContext = selectedScopedProjectContext else {
            return .empty(role: selectedRole, source: "model_settings")
        }

        return AXRoleExecutionSnapshots.latestSnapshots(for: projectContext)[selectedRole]
            ?? .empty(role: selectedRole, source: "model_settings")
    }

    private var routeTruthPresentation: ModelSettingsRouteTruthPresentation {
        let projectRuntimeReadiness: AXProjectGovernanceRuntimeReadinessSnapshot? = {
            guard let projectContext = selectedScopedProjectContext,
                  let config = selectedScopedProjectConfig else {
                return nil
            }
            return xtResolveProjectGovernance(
                projectRoot: projectContext.root,
                config: config
            ).runtimeReadinessSnapshot
        }()
        return ModelSettingsRouteTruthBuilder.build(
            role: selectedRole,
            selectedProjectID: selectedScopedProjectID,
            selectedProjectName: selectedScopedProjectName,
            projectConfig: selectedScopedProjectConfig,
            projectRuntimeReadiness: projectRuntimeReadiness,
            settings: appModel.settingsStore.settings,
            snapshot: selectedRoleExecutionSnapshot,
            transportMode: HubAIClient.transportMode().rawValue,
            language: interfaceLanguage
        )
    }

    private func syncVisibleModelInventory() {
        visibleModelInventory = XTVisibleHubModelInventorySupport.build(
            snapshot: modelInventorySnapshot
        )
    }

    private func resetRoleModelFeedback() {
        roleModelUpdateFeedback.cancel(resetState: true)
        roleModelChangeNotice = nil
    }

    private func updateRoleModelSelection(modelId: String?) {
        let trimmedModelId = modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModelId = trimmedModelId?.isEmpty == false ? trimmedModelId : nil
        guard normalizedModelOverrideValue(currentRoleModelId) != normalizedModelOverrideValue(normalizedModelId) else {
            return
        }

        modelManager.setModel(for: selectedRole, modelId: normalizedModelId)
        roleModelChangeNotice = XTSettingsChangeNoticeBuilder.globalRoleModel(
            role: selectedRole,
            modelId: normalizedModelId,
            snapshot: visibleModelInventory.snapshot,
            executionSnapshot: selectedRoleExecutionSnapshot,
            transportMode: HubAIClient.transportMode().rawValue,
            language: interfaceLanguage
        )
        roleModelUpdateFeedback.trigger()
    }

    private func normalizedModelOverrideValue(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
