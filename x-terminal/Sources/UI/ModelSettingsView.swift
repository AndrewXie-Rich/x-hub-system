import SwiftUI

private enum RoleRoutePickerKind: Equatable {
    case primary
    case paidBackup
}

private struct RoleRoutePickerTarget: Equatable {
    var role: AXRole
    var kind: RoleRoutePickerKind
}

struct ModelSettingsView: View {
    let standaloneWindow: Bool

    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var modelSettingsStore: XTModelSettingsStore
    @EnvironmentObject private var navigationFocusStore: XTNavigationFocusStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var modelManager = HubModelManager.shared
    @StateObject private var supervisorManager = SupervisorManager.shared
    @StateObject private var roleModelUpdateFeedback = XTTransientUpdateFeedbackState()
    @State private var selectedRole: AXRole = .supervisor
    @State private var showRoleModelPicker = false
    @State private var activeFocusRequest: XTModelSettingsFocusRequest?
    @State private var roleModelChangeNotice: XTSettingsChangeNotice?
    @State private var visibleModelInventory = XTVisibleHubModelInventory.empty
    @State private var providerKeySelectionSummary: XTDoctorProjectionSummary?

    init(standaloneWindow: Bool = false) {
        self.standaloneWindow = standaloneWindow
    }

    private var interfaceLanguage: XTInterfaceLanguage {
        modelSettingsSnapshot.interfaceLanguage
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
        .onChange(of: navigationFocusSnapshot.modelSettingsFocusRequest?.nonce) { _ in
            processModelSettingsFocusRequest()
        }
        .onDisappear {
            resetRoleModelFeedback()
        }
        .task(id: providerKeySelectionTaskID) {
            await refreshProviderKeySelectionSummary()
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(XTL10n.text(
                        interfaceLanguage,
                        zhHans: "AI 模型设置",
                        en: "AI Model Settings"
                    ))
                        .font(.title2.weight(.semibold))

                    Text(XTL10n.text(
                        interfaceLanguage,
                        zhHans: "统一配置全局角色模型；项目级覆盖在 Supervisor 设置里处理。",
                        en: "Configure global role models here; project-level overrides stay in Supervisor Settings."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Button(XTL10n.text(
                        interfaceLanguage,
                        zhHans: "刷新模型列表",
                        en: "Refresh Models"
                    )) {
                        rustHubReadinessRefreshID += 1
                        rustHubModelRouteDiagnosticsRefreshID += 1
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
                .fixedSize()
            }

            modelSettingsStatusPills
            modelSettingsIntroBlock

            if let context = activeFocusRequest?.context {
                XTFocusContextCard(context: context)
            }
        }
    }

    private var modelSettingsStatusPills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                modelSettingsStatusPillContent
            }

            VStack(alignment: .leading, spacing: 6) {
                modelSettingsStatusPillContent
            }
        }
    }

    @ViewBuilder
    private var modelSettingsStatusPillContent: some View {
        XTCompactStatusPill(
            iconName: modelSettingsSnapshot.hubInteractive ? "link.circle.fill" : "link.circle",
            text: modelSettingsSnapshot.hubInteractive
                ? XTL10n.text(interfaceLanguage, zhHans: "Hub 已连接", en: "Hub connected")
                : XTL10n.text(interfaceLanguage, zhHans: "Hub 未连接", en: "Hub offline"),
            tint: modelSettingsSnapshot.hubInteractive
                ? UIThemeTokens.color(for: .ready)
                : UIThemeTokens.color(for: .blockedWaitingUpstream)
        )

        XTCompactStatusPill(
            iconName: rustHubReadinessIconName,
            text: rustHubReadinessCompactText,
            tint: rustHubReadinessTint(rustHubReadinessPresentation.tone)
        )

        XTCompactStatusPill(
            iconName: "rectangle.stack.badge.person.crop",
            text: XTL10n.text(
                interfaceLanguage,
                zhHans: "角色 \(configuredHubRoleCount)/\(AXRole.allCases.count)",
                en: "Roles \(configuredHubRoleCount)/\(AXRole.allCases.count)"
            ),
            tint: configuredHubRoleCount == AXRole.allCases.count
                ? UIThemeTokens.color(for: .ready)
                : UIThemeTokens.color(for: .inProgress),
            monospaced: true
        )

        XTCompactStatusPill(
            iconName: "shippingbox",
            text: XTL10n.text(
                interfaceLanguage,
                zhHans: "\(sortedAvailableHubModels.count) 个可用模型",
                en: "\(sortedAvailableHubModels.count) runnable models"
            ),
            tint: sortedAvailableHubModels.isEmpty
                ? UIThemeTokens.color(for: .diagnosticRequired)
                : UIThemeTokens.color(for: .ready),
            monospaced: true
        )
    }

    private var modelSettingsIntroBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(XTL10n.text(
                interfaceLanguage,
                zhHans: "Supervisor 与 Coding 角色都走 X-Hub。未固定模型时，XT 继承 Hub 默认或自动路由；需要明确路由时，在这里为角色绑定模型。",
                en: "Supervisor and coding roles run through X-Hub. When no model is pinned, XT inherits the Hub default or automatic routing; pin a role here only when you need an explicit route."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(XTL10n.text(
                interfaceLanguage,
                zhHans: "这里展示 Hub 返回的真实可执行模型视图。每设备 local model override 仍在 Hub Pairing / Edit Device 配置。",
                en: "This page shows the runnable model view returned by Hub. Per-device local model overrides still live in Hub Pairing / Edit Device."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(UIThemeTokens.secondaryCardBackground)
        )
    }
    
    private var modelSelectionArea: some View {
        VStack(alignment: .leading, spacing: 20) {
            roleRouteOverview
            
            Divider()
            
            modelList
        }
    }

    private func processModelSettingsFocusRequest() {
        guard let request = navigationFocusSnapshot.modelSettingsFocusRequest else { return }
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

    private var roleRouteOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(XTL10n.text(
                        interfaceLanguage,
                        zhHans: "角色模型路由",
                        en: "Role Model Routes"
                    ))
                        .font(.headline)
                    Text(XTL10n.text(
                        interfaceLanguage,
                        zhHans: "每个角色按「主模型 → 备用付费模型 → 本地兜底」执行；备用模型可以留空。",
                        en: "Each role runs primary → paid backup → local fallback. Backup can stay empty."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    rustHubReadinessRefreshID += 1
                    rustHubModelRouteDiagnosticsRefreshID += 1
                    Task {
                        await modelManager.fetchModels()
                    }
                } label: {
                    Label(XTL10n.text(interfaceLanguage, zhHans: "刷新", en: "Refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 250), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(AXRole.allCases) { role in
                    roleRouteCard(role)
                }
            }
        }
    }

    private func roleRouteCard(_ role: AXRole) -> some View {
        let route = modelSettingsSnapshot.settings.modelRoute(for: role)
        let isSelected = selectedRole == role

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                roleIcon(role)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(role.displayName(in: interfaceLanguage))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(isSelected ? "当前" : "详情")
                    .font(.caption2.monospaced())
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedRole = role
                showRoleModelPicker = false
                resetRoleModelFeedback()
            }

            roleRouteLine(
                title: "主",
                value: modelDisplayLabel(route.primaryModelId),
                help: "主模型不可用时，会尝试备用付费模型。",
                actionTitle: "选择"
            ) {
                selectedRole = role
                roleRoutePickerTarget = RoleRoutePickerTarget(role: role, kind: .primary)
            }
            .popover(
                isPresented: roleRoutePickerBinding(role: role, kind: .primary),
                arrowEdge: .bottom
            ) {
                roleRouteModelPicker(role: role, kind: .primary)
            }

            roleRouteLine(
                title: "备",
                value: modelDisplayLabel(route.paidBackupModelId, emptyLabel: "无备用"),
                help: "备用付费模型可为空；主模型失败后优先尝试它，再考虑本地兜底。",
                actionTitle: route.paidBackupModelId == nil ? "选择" : "修改"
            ) {
                selectedRole = role
                roleRoutePickerTarget = RoleRoutePickerTarget(role: role, kind: .paidBackup)
            }
            .popover(
                isPresented: roleRoutePickerBinding(role: role, kind: .paidBackup),
                arrowEdge: .bottom
            ) {
                roleRouteModelPicker(role: role, kind: .paidBackup)
            }

            HStack(spacing: 8) {
                Text("本地")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)
                Text(effectiveLocalFallbackDisplayName(route))
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if route.localFallbackMode != .automatic || route.localFallbackModelId != nil {
                    Button("恢复自动") {
                        modelManager.setLocalFallbackMode(for: role, mode: .automatic)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(UIThemeTokens.color(for: .ready))
                        .help("本地兜底当前使用自动策略")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.09) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func roleRouteLine(
        title: String,
        value: String,
        help: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(help)
            Spacer(minLength: 8)
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
    }

    private func roleRouteModelPicker(
        role: AXRole,
        kind: RoleRoutePickerKind
    ) -> some View {
        let route = modelSettingsSnapshot.settings.modelRoute(for: role)
        let selectedModelId = kind == .primary ? route.primaryModelId : route.paidBackupModelId
        let models = kind == .primary ? sortedAvailableHubModels : paidBackupSelectableModels

        return HubModelPickerPopover(
            title: kind == .primary
                ? "为 \(role.displayName(in: interfaceLanguage)) 选择主模型"
                : "为 \(role.displayName(in: interfaceLanguage)) 选择备用付费模型",
            selectedModelId: selectedModelId,
            inheritedModelId: nil,
            inheritedModelPresentation: nil,
            models: models,
            language: interfaceLanguage,
            automaticTitle: kind == .primary ? "使用 Hub 默认设置" : "不使用备用模型",
            automaticSelectedBadge: kind == .primary ? "当前默认" : "当前无备用",
            automaticRestoreBadge: kind == .primary ? "恢复默认" : "清空备用",
            inheritedModelLabel: "Hub 默认",
            automaticDescription: kind == .primary
                ? "未固定主模型时，XT 使用 Hub 默认/自动路由。"
                : "备用模型为空时，主模型失败后直接进入本地兜底策略。"
        ) { modelId in
            updateRoleRouteModelSelection(role: role, kind: kind, modelId: modelId)
            roleRoutePickerTarget = nil
        }
        .frame(width: 460, height: 420)
    }

    private func roleRoutePickerBinding(
        role: AXRole,
        kind: RoleRoutePickerKind
    ) -> Binding<Bool> {
        Binding(
            get: { roleRoutePickerTarget == RoleRoutePickerTarget(role: role, kind: kind) },
            set: { presented in
                if !presented, roleRoutePickerTarget == RoleRoutePickerTarget(role: role, kind: kind) {
                    roleRoutePickerTarget = nil
                }
            }
        )
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

            roleRoutePreferenceCard

            routeTruthCard

            if let providerKeySelectionSummary {
                providerKeySelectionCard(summary: providerKeySelectionSummary)
            }

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
                    disabled: !modelSettingsSnapshot.hubInteractive || sortedAvailableHubModels.isEmpty,
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

    private var roleRoutePreferenceCard: some View {
        let route = modelSettingsSnapshot.settings.modelRoute(for: selectedRole)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("当前路由链")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text("primary > backup > local")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    routeStepPill(title: "主", value: modelDisplayLabel(route.primaryModelId), tint: .accentColor)
                    routeStepPill(title: "备", value: modelDisplayLabel(route.paidBackupModelId, emptyLabel: "无备用"), tint: route.paidBackupModelId == nil ? .secondary : .orange)
                    routeStepPill(title: "本地", value: effectiveLocalFallbackDisplayName(route), tint: .green)
                }

                VStack(alignment: .leading, spacing: 8) {
                    routeStepPill(title: "主", value: modelDisplayLabel(route.primaryModelId), tint: .accentColor)
                    routeStepPill(title: "备", value: modelDisplayLabel(route.paidBackupModelId, emptyLabel: "无备用"), tint: route.paidBackupModelId == nil ? .secondary : .orange)
                    routeStepPill(title: "本地", value: effectiveLocalFallbackDisplayName(route), tint: .green)
                }
            }

            Text("主模型失败、额度不足、授权过期或远端降级到本地时，XT 会优先尝试备用付费模型；备用为空时直接进入本地兜底策略。")
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
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func routeStepPill(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
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

    private var rustHubModelRouteDiagnosticsCard: some View {
        let presentation = rustHubModelRouteDiagnosticsPresentation
        let tint = rustHubModelRouteDiagnosticsTint(presentation.tone)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)

                Text(presentation.badgeText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.10))
                    .clipShape(Capsule())
            }

            ForEach(presentation.lines, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
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
                .stroke(tint.opacity(0.18), lineWidth: 1)
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
        let raw = modelSettingsSnapshot.settings.modelRoute(for: selectedRole)
            .primaryModelId?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var currentRolePaidBackupModelId: String? {
        let raw = modelSettingsSnapshot.settings.modelRoute(for: selectedRole)
            .paidBackupModelId?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var configuredHubRoleCount: Int {
        AXRole.allCases.filter { role in
            modelSettingsSnapshot.settings.modelRoute(for: role)
                .primaryModelId?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false
        }.count
    }

    private var sortedAvailableHubModels: [HubModel] {
        visibleModelInventory.sortedModels
    }

    private var paidBackupSelectableModels: [HubModel] {
        sortedAvailableHubModels.filter { model in
            model.isSelectableForInteractiveRouting && !model.isLocalModel
        }
    }

    private func modelDisplayLabel(_ modelId: String?, emptyLabel: String = "Hub 自动") -> String {
        let trimmed = modelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return emptyLabel
        }
        if let presentation = visibleModelInventory.presentation(for: trimmed) {
            return presentation.displayName
        }
        return trimmed
    }

    private func effectiveLocalFallbackDisplayName(_ route: RoleModelRoutePreference) -> String {
        if route.localFallbackMode == .specific,
           let localModelId = route.localFallbackModelId,
           localModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return modelDisplayLabel(localModelId)
        }
        return LocalModelFallbackMode.automatic.displayName
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
        modelManager.visibleSnapshot(fallback: modelSettingsSnapshot.modelsState)
    }

    private var modelInventoryTruth: XTModelInventoryTruthPresentation {
        if let rustInventory = modelManager.latestRustInventoryProjection {
            return XTModelInventoryTruthPresentation.build(rustInventory: rustInventory)
        }
        return XTModelInventoryTruthPresentation.build(
            snapshot: modelInventorySnapshot,
            hubBaseDir: modelSettingsSnapshot.hubBaseDir ?? HubPaths.baseDir()
        )
    }

    private var remotePaidAccessProjection: XTUnifiedDoctorRemotePaidAccessProjection? {
        modelSettingsSnapshot.remotePaidAccessSnapshot.map(XTUnifiedDoctorRemotePaidAccessProjection.init)
    }

    private var shouldShowRemotePaidAccessCard: Bool {
        modelSettingsSnapshot.hubRemoteConnected
            || modelSettingsSnapshot.hubRemoteRoute != .none
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
        modelSettingsSnapshot.selectedProjectId
    }

    private var selectedScopedProjectName: String? {
        modelSettingsSnapshot.selectedProjectName
    }

    private var selectedScopedProjectContext: AXProjectContext? {
        modelSettingsSnapshot.selectedProjectContext
    }

    private var selectedScopedProjectConfig: AXProjectConfig? {
        modelSettingsSnapshot.selectedProjectConfig
    }

    private var selectedRoleExecutionSnapshot: AXRoleExecutionSnapshot {
        if selectedRole == .supervisor {
            return ExecutionRoutePresentation.supervisorSnapshot(from: supervisorManager)
        }

        guard let projectContext = selectedScopedProjectContext else {
            return .empty(role: selectedRole, source: "model_settings")
        }

        return XTProjectUIPresentationReadCache.roleExecutionSnapshot(
            for: projectContext,
            role: selectedRole
        ) {
            AXRoleExecutionSnapshots.latestSnapshots(for: projectContext)[selectedRole]
                ?? .empty(role: selectedRole, source: "model_settings")
        }
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
            settings: modelSettingsSnapshot.settings,
            snapshot: selectedRoleExecutionSnapshot,
            transportMode: HubAIClient.transportMode().rawValue,
            language: interfaceLanguage
        )
    }

    private var providerKeySelectionTaskID: String {
        [
            selectedRole.rawValue,
            providerKeySelectionModelID ?? "none",
            String(selectedRoleExecutionSnapshot.updatedAt),
            selectedRoleExecutionSnapshot.executionPath,
            String(appModel.unifiedDoctorReport.generatedAtMs)
        ].joined(separator: "::")
    }

    private var providerKeySelectionModelID: String? {
        let configured = currentRoleModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !configured.isEmpty {
            return configured
        }

        let requested = selectedRoleExecutionSnapshot.requestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requested.isEmpty {
            return requested
        }

        let actual = selectedRoleExecutionSnapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !actual.isEmpty {
            return actual
        }

        return nil
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

    private func refreshProviderKeySelectionSummary() async {
        guard let modelId = providerKeySelectionModelID else {
            await MainActor.run {
                providerKeySelectionSummary = nil
            }
            return
        }

        if !shouldShowProviderKeySelection(for: modelId) {
            await MainActor.run {
                providerKeySelectionSummary = nil
            }
            return
        }

        let decision = await ProviderKeyManager.shared.resolveProviderKeyDecision(forModelId: modelId)
        let importSnapshot = await HubProviderKeyImportSnapshotStore.refreshFromHub()
        let summary = XTProviderKeyRouteContextPresentation.summary(
            decision: decision,
            modelId: modelId,
            importSnapshot: importSnapshot
                ?? HubProviderKeyImportSnapshotStore.load(allowCompatibilityFallback: true),
            doctorSection: appModel.unifiedDoctorReport.section(.modelRouteReadiness),
            language: interfaceLanguage
        )
        await MainActor.run {
            providerKeySelectionSummary = summary
        }
    }

    private func shouldShowProviderKeySelection(for modelId: String) -> Bool {
        if let model = visibleModelInventory.model(for: modelId) {
            return model.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "mlx"
        }
        return !ProviderKeySelectionSupport.inferProvider(fromModelId: modelId).isEmpty
            && !modelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains("mlx")
    }

    @ViewBuilder
    private func providerKeySelectionCard(summary: XTDoctorProjectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.title)
                .font(.subheadline.weight(.semibold))

            ForEach(summary.lines, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
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

    private func updateRoleRouteModelSelection(
        role: AXRole,
        kind: RoleRoutePickerKind,
        modelId: String?
    ) {
        let trimmedModelId = modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModelId = trimmedModelId?.isEmpty == false ? trimmedModelId : nil
        let route = modelSettingsSnapshot.settings.modelRoute(for: role)

        switch kind {
        case .primary:
            guard normalizedModelOverrideValue(route.primaryModelId) != normalizedModelOverrideValue(normalizedModelId) else {
                return
            }
            modelManager.setModel(for: role, modelId: normalizedModelId)
        case .paidBackup:
            guard normalizedModelOverrideValue(route.paidBackupModelId) != normalizedModelOverrideValue(normalizedModelId) else {
                return
            }
            modelManager.setPaidBackupModel(for: role, modelId: normalizedModelId)
        }

        selectedRole = role
        roleModelChangeNotice = XTSettingsChangeNoticeBuilder.globalRoleModel(
            role: role,
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
