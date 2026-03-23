import SwiftUI

struct ModelSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var modelManager = HubModelManager.shared
    @StateObject private var roleModelUpdateFeedback = XTTransientUpdateFeedbackState()
    @State private var selectedRole: AXRole = .supervisor
    @State private var showRoleModelPicker = false
    @State private var activeFocusRequest: XTModelSettingsFocusRequest?
    @State private var roleModelChangeNotice: XTSettingsChangeNotice?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            
            Divider()
            
            if modelManager.isLoading {
                ProgressView("正在加载模型列表...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if let error = modelManager.error {
                Text("加载失败：\(error)")
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
            Task {
                await modelManager.fetchModels()
            }
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
                Text("AI 模型设置")
                    .font(.title2)
                Spacer()
                
                Button("刷新模型列表") {
                    Task {
                        await modelManager.fetchModels()
                    }
                }
                .buttonStyle(.bordered)
            }
            
            Text("Supervisor 和 Coding 的 AI 都来自于 X-Hub。如果 X-Hub 有默认设置，X-Terminal 没有设置就用 Hub 默认设置。如果没有，可以在 X-Terminal 选择使用哪个模型作为 Supervisor，哪个模型作为主要编程角色。Supervisor 也可以建议或自己指派每个 project 的编程模型。")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("本页展示的是 Hub catalog 的模型信息。若某个 paired Terminal 需要独立的本地 context length，请到 Hub 的 Pairing / Edit Device 里设置每设备 local model override。")
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
            Text("选择要配置的角色")
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
                Text(role.displayName)
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
            Text("为 \(selectedRole.displayName) 配置默认模型")
                .font(.headline)

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
                        Button("改用推荐") {
                            updateRoleModelSelection(modelId: suggestedModelId)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("把 \(selectedRole.displayName) 直接切到 `\(suggestedModelId)`。")
                    }
                }
            }
            
            if sortedAvailableHubModels.isEmpty {
                Text("没有可用的模型。请确保 X-Hub 已启动并加载了模型。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                HubModelRoutingButton(
                    title: routingSelectionState.title,
                    identifier: routingSelectionState.identifier,
                    sourceLabel: routingSelectionState.sourceLabel,
                    presentation: routingSelectionState.effectivePresentation,
                    disabled: !appModel.hubInteractive || sortedAvailableHubModels.isEmpty
                ) {
                    showRoleModelPicker = true
                }
                .frame(maxWidth: 480, alignment: .leading)
                .popover(isPresented: $showRoleModelPicker, arrowEdge: .bottom) {
                    HubModelPickerPopover(
                        title: "为 \(selectedRole.displayName) 选择默认模型",
                        selectedModelId: currentRoleModelId,
                        inheritedModelId: nil,
                        inheritedModelPresentation: nil,
                        models: sortedAvailableHubModels,
                        automaticTitle: "使用 Hub 默认设置",
                        automaticSelectedBadge: "当前默认",
                        automaticRestoreBadge: "恢复默认",
                        inheritedModelLabel: "Hub 默认",
                        automaticDescription: "当前没有为这个角色单独绑定固定模型，会继续使用 Hub 默认/自动路由。"
                    ) { modelId in
                        updateRoleModelSelection(modelId: modelId)
                        showRoleModelPicker = false
                    }
                    .frame(width: 460, height: 420)
                }

                Text(currentRoleModelId == nil
                     ? "当前未为这个角色固定具体模型，运行时会继续走 Hub 默认/自动路由。"
                     : "当前已为这个角色固定具体模型；如果清空绑定，会回到 Hub 默认/自动路由。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text("Hub Catalog 预览")
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
                            Text("检索专用")
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
                    
                    Text("Hub 默认上下文：\(model.hubDefaultContextLength) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if model.isLocalModel {
                        Text("本地上限：\(model.hubMaxContextLength) tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let roles = model.roles, !roles.isEmpty {
                        Text("角色：\(roles.joined(separator: ", "))")
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
        let snapshot = ModelStateSnapshot(
            models: sortedAvailableHubModels,
            updatedAt: Date().timeIntervalSince1970
        )
        return HubModelSelectionAdvisor.globalAssignmentIssue(
            for: selectedRole,
            configuredModelId: configured,
            snapshot: snapshot
        )
    }

    private var currentRoleModelId: String? {
        let raw = (modelManager.getPreferredModel(for: selectedRole) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    private var sortedAvailableHubModels: [HubModel] {
        var dedup: [String: HubModel] = [:]
        for model in modelManager.availableModels {
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

    private var routingSelectionState: HubModelRoutingSelectionState {
        let explicitModelId = currentRoleModelId
        let explicitPresentation = explicitModelId.flatMap { modelId in
            sortedAvailableHubModels.first(where: { $0.id == modelId })?.capabilityPresentationModel
                ?? XTModelCatalog.modelInfo(for: modelId)
        }
        return HubModelRoutingSelectionState(
            explicitModelId: explicitModelId,
            inheritedModelId: nil,
            explicitPresentation: explicitPresentation,
            inheritedPresentation: nil,
            explicitSourceLabel: "当前绑定",
            inheritedSourceLabel: "Hub 默认",
            automaticTitle: "使用 Hub 默认设置"
        )
    }

    private func stateRank(_ s: HubModelState) -> Int {
        switch s {
        case .loaded: return 0
        case .available: return 1
        case .sleeping: return 2
        }
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
            snapshot: ModelStateSnapshot(
                models: sortedAvailableHubModels,
                updatedAt: Date().timeIntervalSince1970
            )
        )
        roleModelUpdateFeedback.trigger()
    }

    private func normalizedModelOverrideValue(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
