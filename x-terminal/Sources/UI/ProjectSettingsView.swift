import SwiftUI

struct ProjectSettingsView: View {
    let ctx: AXProjectContext
    let initialGovernanceDestination: XTProjectGovernanceDestination

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var modelManager = HubModelManager.shared
    @StateObject private var projectModelUpdateFeedback = XTTransientUpdateFeedbackState()
    @State private var trustedAutomationDeviceIdDraft: String = ""
    @State private var governedReadableRootsDraft: String = ""
    @State private var governanceInlineMessage: String = ""
    @State private var governanceInlineMessageIsError = false
    @State private var modelPickerRole: AXRole?
    @State private var advancedGovernanceExpanded = false
    @State private var activeFocusRequest: XTProjectSettingsFocusRequest?
    @State private var selectedGovernanceDestination: XTProjectGovernanceDestination
    @State private var projectModelChangeNotice: XTSettingsChangeNotice?

    init(
        ctx: AXProjectContext,
        initialGovernanceDestination: XTProjectGovernanceDestination = .overview
    ) {
        self.ctx = ctx
        self.initialGovernanceDestination = initialGovernanceDestination
        _selectedGovernanceDestination = State(initialValue: initialGovernanceDestination)
    }

    var body: some View {
        Group {
            if selectedGovernanceDestination == .overview {
                overviewSettingsBody
            } else {
                focusedGovernanceBody
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            modelManager.setAppModel(appModel)
            trustedAutomationDeviceIdDraft = appModel.projectConfig?.trustedAutomationDeviceId ?? ""
            governedReadableRootsDraft = governedReadableRootsText(appModel.projectConfig?.governedReadableRoots ?? [])
            selectedGovernanceDestination = initialGovernanceDestination
            processProjectSettingsFocusRequest()
            Task {
                await modelManager.fetchModels()
            }
        }
        .onChange(of: initialGovernanceDestination) { value in
            selectedGovernanceDestination = value
        }
        .onChange(of: appModel.projectSettingsFocusRequest?.nonce) { _ in
            processProjectSettingsFocusRequest()
        }
        .onChange(of: appModel.hubInteractive) { connected in
            if connected {
                Task {
                    await modelManager.fetchModels()
                }
            }
        }
        .onChange(of: appModel.projectConfig?.trustedAutomationDeviceId ?? "") { value in
            trustedAutomationDeviceIdDraft = value
        }
        .onChange(of: governedReadableRootsText(appModel.projectConfig?.governedReadableRoots ?? [])) { value in
            governedReadableRootsDraft = value
        }
        .onDisappear {
            resetProjectModelRoutingFeedback()
        }
    }

    private var overviewSettingsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("项目设置（Project Settings）")
                        .font(.headline)
                    Spacer()
                    Button("关闭") { dismiss() }
                }

                Text(ctx.displayName(registry: appModel.registry))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                latestUIReviewSection
                GroupBox("项目级模型路由") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("每个角色可选择不同模型；留空 = 使用全局 Settings。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if projectModelUpdateFeedback.showsBadge,
                           let projectModelChangeNotice {
                            XTSettingsChangeNoticeInlineView(
                                notice: projectModelChangeNotice,
                                tint: .accentColor
                            )
                        }

                        if !appModel.hubInteractive {
                            Text("Hub 未连接，无法读取可用模型列表。")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if sortedAvailableHubModels.isEmpty {
                            Text("Hub 暂无可用模型。请在 Hub 中注册/加载模型，或配置付费模型后再试。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(AXRole.allCases) { role in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top, spacing: 12) {
                                    Text(roleLabel(role))
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 90, alignment: .leading)

                                    roleModelSelectionButton(role)
                                }

                                if let warning = modelAvailabilityWarningText(for: role) {
                                    Text(warning)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                if let globalHint = inheritedGlobalModelHint(for: role) {
                                    Text(globalHint)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .xtTransientUpdateCardChrome(
                    cornerRadius: 10,
                    isUpdated: projectModelUpdateFeedback.isHighlighted,
                    focusTint: .accentColor,
                    updateTint: .accentColor,
                    baseBackground: Color(NSColor.controlBackgroundColor)
                )

                hubMemorySection
                contextAssemblySection
                automationSelfIterateSection
                governanceTemplateSection
                ProjectGovernanceActivityView(ctx: ctx)
                advancedGovernanceSection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var focusedGovernanceBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                governancePageHeader
                governanceDestinationSurface
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func projectModelOverrideId(for role: AXRole) -> String? {
        let raw = appModel.projectConfig?.modelOverride(for: role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var latestUIReviewSection: some View {
        GroupBox("最近一次 UI 审查") {
            ProjectUIReviewWorkspaceView(
                ctx: ctx,
                emptyTitle: "暂无浏览器 UI review",
                emptyMessage: "当前项目还没有浏览器 UI review。执行一次 `device.browser.control snapshot` 后，系统会在这里展示最近一次受治理 UI 观察结果。",
                helperText: "这条 review 会被 project AI / supervisor memory / resume brief 共同消费。它的作用不是替代人工验收，而是让系统先判断“当前页面是否真的可执行”。"
            )
            .padding(8)
        }
    }

    private var focusedSettingsDestinations: [XTProjectGovernanceDestination] {
        [.uiReview] + XTProjectGovernanceDestination.editorCases
    }

    private var governanceConfig: AXProjectConfig {
        appModel.projectConfig ?? .default(forProjectRoot: ctx.root)
    }

    private var resolvedGovernanceState: AXProjectResolvedGovernanceState {
        appModel.resolvedProjectGovernance(config: governanceConfig)
    }

    private var currentProjectContextAssemblyDiagnostics: AXProjectContextAssemblyDiagnosticsSummary {
        AXProjectContextAssemblyDiagnosticsStore.doctorSummary(
            for: appModel.projectContext ?? ctx,
            config: appModel.projectConfig
        )
    }

    private var currentProjectContextAssemblyPresentation: AXProjectContextAssemblyPresentation? {
        AXProjectContextAssemblyPresentation.from(summary: currentProjectContextAssemblyDiagnostics)
    }

    private var resolvedGovernancePresentation: ProjectGovernancePresentation {
        ProjectGovernancePresentation(resolved: resolvedGovernanceState)
    }

    private var effectiveRuntimeSurface: AXProjectRuntimeSurfaceEffectivePolicy {
        resolvedGovernanceState.effectiveRuntimeSurface
    }

    private var configuredRuntimeSurfaceSummary: String {
        configuredRuntimeSurfaceText(governanceConfig)
    }

    private var effectiveRuntimeSurfaceSummary: String {
        let labels = effectiveRuntimeSurface.allowedSurfaceLabels
        return labels.isEmpty ? "(none)" : labels.joined(separator: ", ")
    }

    private var runtimeSurfaceUpdatedAtText: String {
        governanceConfig.runtimeSurfaceUpdatedAtDate.map {
            runtimeSurfaceTimestampFormatter.string(from: $0)
        } ?? "(never armed)"
    }

    private var hubOverrideUpdatedAtText: String {
        guard effectiveRuntimeSurface.remoteOverrideUpdatedAtMs > 0 else { return "(none)" }
        let date = Date(
            timeIntervalSince1970: TimeInterval(effectiveRuntimeSurface.remoteOverrideUpdatedAtMs) / 1000.0
        )
        return runtimeSurfaceTimestampFormatter.string(from: date)
    }

    private func globalModelId(_ role: AXRole) -> String? {
        appModel.settingsStore.settings.assignment(for: role).model
    }

    private func roleModelSelectionButton(_ role: AXRole) -> some View {
        let title = selectedModelButtonTitle(for: role)
        let presentation = selectedModelPresentation(for: role)
        let identifier = selectedModelIdentifier(for: role)
        let sourceLabel = selectedModelPresentationSourceLabel(for: role)
        let buttonDisabled = !appModel.hubInteractive || sortedAvailableHubModels.isEmpty

        return HubModelRoutingButton(
            title: title,
            identifier: identifier,
            sourceLabel: sourceLabel,
            presentation: presentation,
            disabled: buttonDisabled
        ) {
            modelPickerRole = role
        }
        .frame(maxWidth: 420, alignment: .leading)
        .popover(isPresented: modelPickerBinding(for: role), arrowEdge: .bottom) {
            HubModelPickerPopover(
                title: "为 \(roleLabel(role)) 选择模型",
                selectedModelId: projectModelOverrideId(for: role),
                inheritedModelId: globalModelId(role),
                inheritedModelPresentation: globalModelPresentation(for: role),
                models: sortedAvailableHubModels,
                recommendedModelId: modelSelectionRecommendation(for: role)?.modelId,
                recommendationMessage: modelSelectionRecommendation(for: role)?.message,
                onSelect: { modelId in
                    updateProjectRoleModelAssignment(role: role, modelId: modelId)
                    modelPickerRole = nil
                }
            )
            .frame(width: 460, height: 420)
        }
    }

    private func modelPickerBinding(for role: AXRole) -> Binding<Bool> {
        Binding(
            get: { modelPickerRole == role },
            set: { isPresented in
                if isPresented {
                    modelPickerRole = role
                } else if modelPickerRole == role {
                    modelPickerRole = nil
                }
            }
        )
    }

    private var governanceTemplateSection: some View {
        let config = governanceConfig
        let resolved = resolvedGovernanceState
        let governancePresentation = resolvedGovernancePresentation
        let templatePreview = xtProjectGovernanceTemplatePresentation(
            projectRoot: ctx.root,
            config: config,
            resolved: resolved
        )

        return GroupBox("治理模板") {
            VStack(alignment: .leading, spacing: 12) {
                Text("这些模板只是 A-tier / S-tier / review cadence 的快捷映射。真正生效的执行权限、supervisor 介入、TTL、trusted automation 与 read roots，仍以下方治理设置和运行时收束为准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 10) {
                    ForEach(AXProjectGovernanceTemplate.selectableTemplates, id: \.self) { profile in
                        governanceTemplateButton(
                            profile,
                            isSelected: templatePreview.configuredProfile == profile
                        )
                    }
                }

                if templatePreview.configuredProfile == .custom {
                    Text("当前模板已偏离默认映射：系统会以实际保存的 A-tier / S-tier / review 配置为准。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if !governanceInlineMessage.isEmpty {
                    Text(governanceInlineMessage)
                        .font(.caption)
                        .foregroundStyle(governanceInlineMessageIsError ? .red : .orange)
                }

                ProjectGovernanceCompactSummaryView(
                    presentation: governancePresentation,
                    showCallout: true,
                    onExecutionTierTap: { selectedGovernanceDestination = .executionTier },
                    onSupervisorTierTap: { selectedGovernanceDestination = .supervisorTier },
                    onReviewCadenceTap: { selectedGovernanceDestination = .heartbeatReview },
                    onStatusTap: { selectedGovernanceDestination = .overview },
                    onCalloutTap: { selectedGovernanceDestination = .overview }
                )

                HStack(alignment: .top, spacing: 12) {
                    governanceTemplateStateCard(
                        title: "模板输入",
                        profile: templatePreview.configuredProfile,
                        summary: templatePreview.configuredProfileSummary
                    )

                    governanceTemplateStateCard(
                        title: "运行时投影",
                        profile: templatePreview.effectiveProfile,
                        summary: templatePreview.effectiveProfileSummary
                    )
                }

                if templatePreview.hasConfiguredEffectiveDrift {
                    Text("模板输入和运行时投影当前不完全一致。真正放行动作仍继续受执行面 TTL、收束规则、trusted automation、grant 和 kill-switch 共同约束。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 12) {
                    governanceTemplateDimensionCard(
                        title: "设备门槛",
                        configuredTitle: templatePreview.configuredDeviceAuthorityPosture.displayName,
                        configuredDetail: templatePreview.configuredDeviceAuthorityDetail,
                        effectiveTitle: templatePreview.effectiveDeviceAuthorityPosture.displayName,
                        effectiveDetail: templatePreview.effectiveDeviceAuthorityDetail
                    )

                    governanceTemplateDimensionCard(
                        title: "监督覆盖",
                        configuredTitle: templatePreview.configuredSupervisorScope.displayName,
                        configuredDetail: templatePreview.configuredSupervisorScopeDetail,
                        effectiveTitle: templatePreview.effectiveSupervisorScope.displayName,
                        effectiveDetail: templatePreview.effectiveSupervisorScopeDetail
                    )

                    governanceTemplateDimensionCard(
                        title: "Hub 授权门",
                        configuredTitle: templatePreview.configuredGrantPosture.displayName,
                        configuredDetail: templatePreview.configuredGrantDetail,
                        effectiveTitle: templatePreview.effectiveGrantPosture.displayName,
                        effectiveDetail: templatePreview.effectiveGrantDetail
                    )
                }

                if !templatePreview.configuredDeviationReasons.isEmpty {
                    Text("template_delta: \(templatePreview.configuredDeviationReasons.joined(separator: " · "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if !templatePreview.effectiveDeviationReasons.isEmpty {
                    Text("runtime_notes: \(templatePreview.effectiveDeviationReasons.joined(separator: " · "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text("运行时约束：\(templatePreview.runtimeSummary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(8)
        }
    }

    private var hubMemorySection: some View {
        let preferHubMemory = appModel.projectConfig?.preferHubMemory ?? true
        let mode = XTProjectMemoryGovernance.modeLabel(appModel.projectConfig)

        return GroupBox("Hub 记忆治理") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "当前项目优先使用 Hub memory",
                    isOn: Binding(
                        get: { appModel.projectConfig?.preferHubMemory ?? true },
                        set: { appModel.setProjectHubMemoryPreference(enabled: $0) }
                    )
                )
                .toggleStyle(.switch)

                Text("default: on · mode: \(mode)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text(preferHubMemory
                     ? "开启后：X-Terminal 会优先用 Hub memory 组装 prompt，并继续保留本地 `.xterminal/AX_MEMORY.md` / `recent_context.json` 作为 continuity/fallback 层。Hub 侧 X-宪章、remote export gate、skills revoked gate、kill-switch 会参与约束。"
                     : "关闭后：当前项目只使用本地 `.xterminal/AX_MEMORY.md` / `recent_context.json` 组装 prompt，不请求 Hub memory context。适合离线或临时隔离场景。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("注意：当前实现仍保留本地 memory 文件用于崩溃恢复与 fallback，所以这还不是单一 Hub 真源；这里只控制 prompt 组装时是否优先走 Hub。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var contextAssemblySection: some View {
        let config = governanceConfig

        return GroupBox("上下文组装") {
            VStack(alignment: .leading, spacing: 12) {
                Text("这里控制 project AI 最近能看到多少项目对话，以及项目背景带多完整。它不会改变执行权限、Supervisor 介入强度或 heartbeat。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("最近项目对话")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 180, alignment: .leading)

                    Picker(
                        "",
                        selection: Binding(
                            get: { governanceConfig.projectRecentDialogueProfile },
                            set: { appModel.setProjectContextAssembly(projectRecentDialogueProfile: $0) }
                        )
                    ) {
                        ForEach(AXProjectRecentDialogueProfile.allCases) { profile in
                            Text("\(profile.displayName) · \(profile.shortLabel)").tag(profile)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 280, alignment: .leading)

                    Spacer()
                }

                Text(config.projectRecentDialogueProfile.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("项目背景深度")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 180, alignment: .leading)

                    Picker(
                        "",
                        selection: Binding(
                            get: { governanceConfig.projectContextDepthProfile },
                            set: { appModel.setProjectContextAssembly(projectContextDepthProfile: $0) }
                        )
                    ) {
                        ForEach(AXProjectContextDepthProfile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 280, alignment: .leading)

                    Spacer()
                }

                Text(config.projectContextDepthProfile.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                    contextAssemblyMetric(
                        title: "对话窗口",
                        value: config.projectRecentDialogueProfile.shortLabel,
                        tone: .teal
                    )
                    contextAssemblyMetric(
                        title: "背景深度",
                        value: config.projectContextDepthProfile.displayName,
                        tone: .indigo
                    )
                }

                Text("上面两项就是 project AI 的主要背景开关：前者决定保留多少最近项目对话，后者决定带入多少项目材料。实际运行后，下面会显示它这轮真正吃到的背景。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let presentation = currentProjectContextAssemblyPresentation {
                    contextAssemblyRuntimeSummary(presentation: presentation)
                }
            }
            .padding(8)
        }
    }

    private var trustedAutomationSection: some View {
        let config = appModel.projectConfig ?? .default(forProjectRoot: ctx.root)
        let effective = appModel.resolvedProjectRuntimeSurfacePolicy(config: config)
        let readiness = AXTrustedAutomationPermissionOwnerReadiness.current()
        let status = config.trustedAutomationStatus(forProjectRoot: ctx.root, permissionReadiness: readiness)
        let expectedHash = xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
        let configuredAutoApprove = config.governedAutoApproveLocalToolCalls
        let effectiveAutoApprove = xtProjectGovernedAutoApprovalEnabled(
            projectRoot: ctx.root,
            config: config,
            effectiveRuntimeSurface: effective
        )
        let deviceGroups = status.deviceToolGroups.isEmpty
            ? (status.mode == .trustedAutomation ? xtTrustedAutomationDefaultDeviceToolGroups() : [])
            : status.deviceToolGroups
        let requirementStatuses = readiness.requirementStatuses(
            forDeviceToolGroups: status.mode == .trustedAutomation ? deviceGroups : []
        )
        let repairActions = readiness.suggestedOpenSettingsActions(
            forDeviceToolGroups: status.mode == .trustedAutomation ? deviceGroups : []
        )

        return GroupBox("设备执行绑定") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: trustedAutomationIcon(status.state))
                        .foregroundStyle(trustedAutomationColor(status.state))
                    Text("状态：\(trustedAutomationStateLabel(status.state))")
                        .font(.headline)

                    Spacer()

                    Text("模式：\(trustedAutomationModeLabel(status.mode))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("这是一条 project 级设备执行绑定，不等于把整个 X-Terminal 永久全开；高档治理模板也不等于自动拥有全部设备权限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("绑定设备 ID")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 120, alignment: .leading)

                    TextField("device_xt_001", text: $trustedAutomationDeviceIdDraft)
                        .textFieldStyle(.roundedBorder)

                    Button("绑定当前项目") {
                        saveTrustedAutomationBinding(armed: true)
                    }
                    .disabled(trustedAutomationDeviceIdDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("关闭绑定") {
                        saveTrustedAutomationBinding(armed: false)
                    }
                }

                Text("工作区绑定哈希：\(expectedHash)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("设备能力组：\(deviceGroups.isEmpty ? "(none)" : deviceGroups.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)

                Text("权限宿主状态：overall=\(readiness.overallState) · install=\(readiness.installState) · 可主动拉起授权=\(readiness.canPromptUser ? "是" : "否")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("需要的系统权限：\(requirementStatuses.isEmpty ? "(none)" : requirementStatuses.map { $0.key.rawValue }.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if requirementStatuses.isEmpty {
                    Text("当前设备能力组不需要额外系统权限。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(requirementStatuses) { requirement in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(requirement.displayName)
                                        .font(.caption.weight(.semibold))
                                    Text(trustedAutomationPermissionStatusLabel(requirement.status))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(trustedAutomationPermissionColor(requirement.status))
                                    Spacer()
                                    Text(requirement.requiredByDeviceToolGroups.joined(separator: ", "))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Text(requirement.rationale)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if status.missingPrerequisites.isEmpty {
                    Text("额外前提：无")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("额外前提：\(status.missingPrerequisites.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }

                Toggle(
                    "允许低风险本地工具跳过本地审批",
                    isOn: Binding(
                        get: { appModel.projectConfig?.governedAutoApproveLocalToolCalls ?? false },
                        set: { appModel.setProjectGovernedAutoApproveLocalToolCalls(enabled: $0) }
                    )
                )
                .toggleStyle(.switch)
                .disabled(status.mode != .trustedAutomation)

                Text(configuredAutoApprove
                     ? "开启后：当前 project 下的低风险 needs-confirm 本地工具会直接执行，不再等待本地审批。高风险 shell 和网络 grant 仍保留人工 / Hub 门禁。"
                     : "关闭后：写文件、跑命令、设备浏览器控制、UI 动作等本地高风险操作仍会停在本地审批。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("本地自动审批：预设=\(toggleStateLabel(configuredAutoApprove)) · 生效=\(toggleStateLabel(effectiveAutoApprove))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text("额外可读目录")
                        .font(.caption.weight(.semibold))

                    TextEditor(text: $governedReadableRootsDraft)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                        )

                    HStack(spacing: 8) {
                        Button("保存目录") {
                            saveGovernedReadableRoots()
                        }

                        Button("添加上级目录") {
                            appendGovernedReadableRootSuggestion(ctx.root.deletingLastPathComponent())
                        }

                        Button("添加上上级目录") {
                            appendGovernedReadableRootSuggestion(ctx.root.deletingLastPathComponent().deletingLastPathComponent())
                        }

                        Button("清空") {
                            governedReadableRootsDraft = ""
                            saveGovernedReadableRoots()
                        }

                        Spacer()
                    }

                    Text("每行一个路径；支持绝对路径，也支持相对当前 project root 的路径。这里只扩展 `read_file` / `list_dir` / `search(path=...)`，不会放开 project 外的 `write_file` / `run_command`。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("当前可读目录：\(effectiveGovernedReadableRootsText(config: config, effective: effective))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 8) {
                    ForEach(repairActions, id: \.self) { action in
                        Button(XTSystemSettingsLinks.label(forOpenSettingsAction: action)) {
                            XTSystemSettingsLinks.openPrivacyAction(action)
                        }
                    }

                    Button("打开系统设置") {
                        XTSystemSettingsLinks.openSystemSettings()
                    }

                    Spacer()
                }
            }
            .padding(8)
        }
    }

    private var governancePageHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedGovernanceDestination.displayTitle)
                        .font(.headline)
                    Text(ctx.displayName(registry: appModel.registry))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("All Settings") {
                    selectedGovernanceDestination = .overview
                }
                .buttonStyle(.bordered)

                Button("Close") {
                    dismiss()
                }
            }

            governanceDestinationTabs
        }
    }

    private var governanceDestinationTabs: some View {
        HStack(spacing: 8) {
            ForEach(focusedSettingsDestinations, id: \.self) { destination in
                governanceDestinationTab(destination)
            }
            Spacer()
        }
    }

    private func governanceDestinationTab(_ destination: XTProjectGovernanceDestination) -> some View {
        let selected = selectedGovernanceDestination == destination
        return Button {
            selectedGovernanceDestination = destination
        } label: {
            Text(destination.displayTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : .accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(selected ? Color.accentColor : Color.accentColor.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    private var governanceSummaryPanel: some View {
        GroupBox("Current Governance") {
            VStack(alignment: .leading, spacing: 12) {
                ProjectGovernanceBadge(
                    presentation: resolvedGovernancePresentation,
                    onExecutionTierTap: { selectedGovernanceDestination = .executionTier },
                    onSupervisorTierTap: { selectedGovernanceDestination = .supervisorTier },
                    onReviewCadenceTap: { selectedGovernanceDestination = .heartbeatReview },
                    onStatusTap: { selectedGovernanceDestination = .overview }
                )
                ProjectGovernanceInspector(presentation: resolvedGovernancePresentation)

                if !governanceInlineMessage.isEmpty {
                    Text(governanceInlineMessage)
                        .font(.caption)
                        .foregroundStyle(governanceInlineMessageIsError ? .red : .orange)
                }
            }
            .padding(8)
        }
    }

    private var governanceDestinationSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            governanceSummaryPanel

            switch selectedGovernanceDestination {
            case .overview:
                EmptyView()
            case .uiReview:
                uiReviewFocusedSection
            case .executionTier:
                executionTierFocusedSection
            case .supervisorTier:
                supervisorTierFocusedSection
            case .heartbeatReview:
                heartbeatReviewFocusedSection
            }
        }
    }

    private var uiReviewFocusedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            latestUIReviewSection

            Text("这里是项目的 UI review 专属工作区。Supervisor / 项目 AI 都可以把这里当作“页面是否真的可执行”的当前真相入口。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(XTProjectSettingsSectionID.uiReview)
    }

    private var executionTierFocusedSection: some View {
        ProjectExecutionTierView(
            configuredTier: governanceConfig.executionTier,
            effectiveTier: resolvedGovernanceState.effectiveBundle.executionTier,
            effectiveProjectMemoryCeiling: resolvedGovernanceState.projectMemoryCeiling,
            effectiveRuntimeSurfaceMode: effectiveRuntimeSurface.effectiveMode,
            inlineMessage: governanceInlineMessage,
            inlineMessageIsError: governanceInlineMessageIsError,
            onSelectTier: updateExecutionTier
        )
        .id(XTProjectSettingsSectionID.executionTier)
    }

    private var supervisorTierFocusedSection: some View {
        ProjectSupervisorTierView(
            currentExecutionTier: governanceConfig.executionTier,
            configuredTier: governanceConfig.supervisorInterventionTier,
            effectiveTier: resolvedGovernanceState.effectiveBundle.supervisorInterventionTier,
            effectiveReviewMemoryCeiling: resolvedGovernanceState.supervisorReviewMemoryCeiling,
            inlineMessage: governanceInlineMessage,
            inlineMessageIsError: governanceInlineMessageIsError,
            onSelectTier: updateSupervisorTier
        )
        .id(XTProjectSettingsSectionID.supervisorTier)
    }

    private var heartbeatReviewFocusedSection: some View {
        ProjectHeartbeatReviewView(
            ctx: ctx,
            configuredExecutionTier: governanceConfig.executionTier,
            configuredReviewPolicyMode: governanceConfig.reviewPolicyMode,
            progressHeartbeatSeconds: governanceConfig.progressHeartbeatSeconds,
            reviewPulseSeconds: governanceConfig.reviewPulseSeconds,
            brainstormReviewSeconds: governanceConfig.brainstormReviewSeconds,
            eventDrivenReviewEnabled: governanceConfig.eventDrivenReviewEnabled,
            eventReviewTriggers: governanceConfig.eventReviewTriggers,
            resolvedGovernance: resolvedGovernanceState,
            governancePresentation: resolvedGovernancePresentation,
            inlineMessage: governanceInlineMessage,
            inlineMessageIsError: governanceInlineMessageIsError,
            onSelectReviewPolicy: { appModel.setProjectGovernance(reviewPolicyMode: $0) },
            onUpdateProgressHeartbeatSeconds: { appModel.setProjectGovernance(progressHeartbeatSeconds: $0) },
            onUpdateReviewPulseSeconds: { appModel.setProjectGovernance(reviewPulseSeconds: $0) },
            onUpdateBrainstormReviewSeconds: { appModel.setProjectGovernance(brainstormReviewSeconds: $0) },
            onSetEventDrivenReviewEnabled: { appModel.setProjectGovernance(eventDrivenReviewEnabled: $0) },
            onSetEventReviewTriggers: { appModel.setProjectGovernance(eventReviewTriggers: $0) }
        )
        .id(XTProjectSettingsSectionID.reviewCadence)
    }

    private var runtimeSurfaceSection: some View {
        GroupBox("Execution Surface Runtime") {
            VStack(alignment: .leading, spacing: 12) {
                Text("A-tier / S-tier / Heartbeat & Review 已拆到各自独立页面。这里仅保留执行面、TTL 与 Hub 收束相关细项。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Stepper(
                    value: Binding(
                        get: { max(5, (appModel.projectConfig?.runtimeSurfaceTTLSeconds ?? 3600) / 60) },
                        set: { appModel.setProjectRuntimeSurfacePolicy(ttlSeconds: max(5, $0) * 60) }
                    ),
                    in: 5...1440,
                    step: 5
                ) {
                    Text("执行面 TTL：\((governanceConfig.runtimeSurfaceTTLSeconds / 60)) 分钟")
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("本地执行面收束")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 140, alignment: .leading)

                    Picker(
                        "",
                        selection: Binding(
                            get: { appModel.projectConfig?.runtimeSurfaceHubOverrideMode ?? AXProjectRuntimeSurfaceHubOverrideMode.none },
                            set: { appModel.setProjectRuntimeSurfacePolicy(hubOverrideMode: $0) }
                        )
                    ) {
                        ForEach(AXProjectRuntimeSurfaceHubOverrideMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 260, alignment: .leading)

                    Spacer()
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Hub 执行面收束")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 140, alignment: .leading)

                    Text(effectiveRuntimeSurface.remoteOverrideMode.displayName)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)

                    Spacer()
                }

                Text("预设执行面：\(configuredRuntimeSurfaceSummary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("生效执行面：\(effectiveRuntimeSurfaceSummary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("执行面 TTL 剩余：\(runtimeSurfaceRemainingText(config: governanceConfig, effective: effectiveRuntimeSurface)) · 最近更新时间：\(runtimeSurfaceUpdatedAtText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Hub 收束来源：\(effectiveRuntimeSurface.remoteOverrideSource.isEmpty ? "(none)" : effectiveRuntimeSurface.remoteOverrideSource) · Hub 收束更新时间：\(hubOverrideUpdatedAtText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("执行档位会同步默认执行面，但真正放行动作仍继续受 TTL、收束规则、设备执行绑定、权限宿主和 kill-switch 共同约束。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(runtimeSurfaceExplanationText(config: governanceConfig, effective: effectiveRuntimeSurface))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var advancedGovernanceSection: some View {
        GroupBox("Execution Surface & Trusted Automation") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("这里保留执行面、设备执行绑定、可读目录和本地自动审批细项。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("A-tier / S-tier / Heartbeat & Review 已拆到各自独立页面；点治理摘要卡即可进入对应编辑器。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(advancedGovernanceExpanded ? "隐藏细节" : "显示细节") {
                        advancedGovernanceExpanded.toggle()
                    }
                }

                if advancedGovernanceExpanded {
                    runtimeSurfaceSection
                    trustedAutomationSection
                }
            }
            .padding(8)
        }
    }

    private func contextAssemblyMetric(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption)
                .foregroundStyle(tone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tone.opacity(0.10))
        )
    }

    private func contextAssemblyRuntimeSummary(
        presentation: AXProjectContextAssemblyPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("最近一次运行时组装")
                    .font(.system(.body, design: .monospaced))

                Text(presentation.userSourceBadge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((presentation.sourceKind == .latestCoderUsage ? Color.green : Color.orange).opacity(0.16))
                    )
                    .foregroundStyle(presentation.sourceKind == .latestCoderUsage ? Color.green : Color.orange)

                Spacer()
            }

            if let projectLabel = presentation.projectLabel {
                Text(projectLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(presentation.userStatusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                contextAssemblyMetric(
                    title: "运行时对话",
                    value: presentation.userDialogueMetric,
                    tone: .mint
                )
                contextAssemblyMetric(
                    title: "运行时深度",
                    value: presentation.userDepthMetric,
                    tone: .blue
                )
                if let coverageMetric = presentation.userCoverageSummary {
                    contextAssemblyMetric(
                        title: "纳入内容",
                        value: coverageMetric,
                        tone: .orange
                    )
                }
                if let boundaryMetric = presentation.userBoundarySummary {
                    contextAssemblyMetric(
                        title: "隐私边界",
                        value: boundaryMetric,
                        tone: .pink
                    )
                }
            }

            Text(presentation.userDialogueLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(presentation.userDepthLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(UIThemeTokens.secondaryCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
        )
    }

    private var automationSelfIterateSection: some View {
        let enabled = appModel.projectConfig?.automationSelfIterateEnabled ?? false
        let maxDepth = appModel.projectConfig?.automationMaxAutoRetryDepth ?? 2
        let recipeRef = appModel.projectConfig?.activeAutomationRecipeRef.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return GroupBox("自动自迭代") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "开启有边界的自迭代自动重试",
                    isOn: Binding(
                        get: { appModel.projectConfig?.automationSelfIterateEnabled ?? false },
                        set: { appModel.setProjectAutomationSelfIteration(enabled: $0) }
                    )
                )
                .toggleStyle(.switch)

                Stepper(
                    value: Binding(
                        get: { appModel.projectConfig?.automationMaxAutoRetryDepth ?? 2 },
                        set: { appModel.setProjectAutomationSelfIteration(maxAutoRetryDepth: $0) }
                    ),
                    in: 1...8
                ) {
                    Text("最大自动重试深度：\(maxDepth)")
                }

                Text("current_mode: \(enabled ? "enabled" : "disabled") · active_recipe: \(recipeRef.isEmpty ? "(none)" : recipeRef)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("当前实现是受控的证据驱动自动重试，不会自动改 recipe、patch 或 planner。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private func roleLabel(_ role: AXRole) -> String {
        switch role {
        case .coder: return "coder"
        case .coarse: return "coarse"
        case .refine: return "refine"
        case .reviewer: return "reviewer"
        case .advisor: return "advisor"
        case .supervisor: return "supervisor"
        }
    }

    private var sortedAvailableHubModels: [HubModel] {
        var dedup: [String: HubModel] = [:]
        let source = availableHubModels
        for model in source {
            dedup[model.id] = model
        }
        let models = Array(dedup.values)
        return models.sorted { a, b in
            let sa = stateRank(a.state)
            let sb = stateRank(b.state)
            if sa != sb { return sa < sb }
            let na = (a.name.isEmpty ? a.id : a.name).lowercased()
            let nb = (b.name.isEmpty ? b.id : b.name).lowercased()
            if na != nb { return na < nb }
            return a.id.lowercased() < b.id.lowercased()
        }
    }

    private func modelInventorySnapshot() -> ModelStateSnapshot {
        ModelStateSnapshot(
            models: availableHubModels,
            updatedAt: appModel.modelsState.updatedAt
        )
    }

    private var availableHubModels: [HubModel] {
        modelManager.availableModels.isEmpty ? appModel.modelsState.models : modelManager.availableModels
    }

    private func selectedModelPresentation(for role: AXRole) -> ModelInfo? {
        if let projectModelId = projectModelOverrideId(for: role) {
            return availableHubModels.first(where: { $0.id == projectModelId })?.capabilityPresentationModel
                ?? XTModelCatalog.modelInfo(for: projectModelId)
        }

        let inheritedModelId = globalModelId(role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !inheritedModelId.isEmpty else { return nil }
        return availableHubModels.first(where: { $0.id == inheritedModelId })?.capabilityPresentationModel
            ?? XTModelCatalog.modelInfo(for: inheritedModelId)
    }

    private func globalModelPresentation(for role: AXRole) -> ModelInfo? {
        let inheritedModelId = globalModelId(role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !inheritedModelId.isEmpty else { return nil }
        return availableHubModels.first(where: { $0.id == inheritedModelId })?.capabilityPresentationModel
            ?? XTModelCatalog.modelInfo(for: inheritedModelId)
    }

    private func selectedModelPresentationSourceLabel(for role: AXRole) -> String {
        projectModelOverrideId(for: role) == nil ? "继承全局" : "项目覆盖"
    }

    private func selectedModelButtonTitle(for role: AXRole) -> String {
        if let presentation = selectedModelPresentation(for: role) {
            return presentation.displayName
        }
        return "使用全局设置"
    }

    private func selectedModelIdentifier(for role: AXRole) -> String? {
        if let projectModelId = projectModelOverrideId(for: role) {
            return projectModelId
        }
        let inheritedModelId = globalModelId(role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return inheritedModelId.isEmpty ? nil : inheritedModelId
    }

    private func inheritedGlobalModelHint(for role: AXRole) -> String? {
        guard projectModelOverrideId(for: role) != nil else { return nil }
        if let global = globalModelId(role)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !global.isEmpty {
            return "当前不选项目覆盖时，会回到全局模型 `\(global)`。"
        }
        return "当前不选项目覆盖时，会回到全局自动路由。"
    }

    private func modelSelectionRecommendation(for role: AXRole) -> (modelId: String, message: String)? {
        let configured = selectedModelIdentifier(for: role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !configured.isEmpty else { return nil }

        if let guidance = AXProjectModelRouteMemoryStore.selectionGuidance(
            configuredModelId: configured,
            role: role,
            ctx: ctx,
            snapshot: modelInventorySnapshot()
        ),
           let recommendedModelId = guidance.recommendedModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !recommendedModelId.isEmpty {
            let message = guidance.recommendationText?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                recommendedModelId,
                (message?.isEmpty == false ? message! : guidance.warningText)
            )
        }

        let assessment = HubModelSelectionAdvisor.assess(
            requestedId: configured,
            snapshot: modelInventorySnapshot()
        )
        guard let assessment,
              assessment.isExactMatchLoaded != true else {
            return nil
        }
        guard let rawCandidate = assessment.loadedCandidates.first?.id else {
            return nil
        }
        let candidate = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              candidate.caseInsensitiveCompare(configured) != .orderedSame else {
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
            "`\(configured)` 当前不在可直接执行的 inventory 里；先切到已加载的 `\(candidate)`，可以避免这轮继续掉本地。"
        )
    }

    private func modelAvailabilityWarningText(for role: AXRole) -> String? {
        guard let configuredBinding = warningConfiguredModelBinding(for: role) else { return nil }
        let configured = configuredBinding.modelId
        if let routeWarning = AXProjectModelRouteMemoryStore.selectionWarningText(
            configuredModelId: configured,
            role: role,
            ctx: ctx,
            snapshot: modelInventorySnapshot()
        ) {
            return routeWarning
        }
        let assessment = HubModelSelectionAdvisor.assess(
            requestedId: configured,
            snapshot: modelInventorySnapshot()
        )
        guard assessment?.isExactMatchLoaded != true else { return nil }

        if let assessment,
           let blocked = assessment.nonInteractiveExactMatch,
           let reason = assessment.interactiveRoutingBlockedReason {
            let candidates = suggestedModelIDs(from: assessment)
            if let first = candidates.first {
                return "\(configuredBinding.subject) `\(blocked.id)`，但它是检索专用模型。\(reason) 可先切到 `\(first)`。"
            }
            return "\(configuredBinding.subject) `\(blocked.id)`，但它是检索专用模型。\(reason)"
        }

        if let assessment, let exact = assessment.exactMatch {
            let candidates = suggestedModelIDs(from: assessment)
            if let first = candidates.first {
                return "\(configuredBinding.subject) `\(exact.id)`，但它现在是 \(HubModelSelectionAdvisor.stateLabel(exact.state))。若你现在执行，这一路可能会回退到本地；可先切到 `\(first)`。"
            }
            return "\(configuredBinding.subject) `\(exact.id)`，但它现在是 \(HubModelSelectionAdvisor.stateLabel(exact.state))。若你现在执行，这一路可能会回退到本地。"
        }

        if let assessment {
            let candidates = suggestedModelIDs(from: assessment)
            if !candidates.isEmpty {
                return "\(configuredBinding.subject) `\(configured)`，但 inventory 里没有精确匹配。可先试 `\(candidates.joined(separator: "`, `"))`。"
            }
        }
        return "\(configuredBinding.subject) `\(configured)`，但现在无法确认它可执行。"
    }

    private func warningConfiguredModelBinding(for role: AXRole) -> (modelId: String, subject: String)? {
        if let projectModelId = projectModelOverrideId(for: role)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !projectModelId.isEmpty {
            return (
                projectModelId,
                "当前 project 为 \(roleLabel(role)) 配的是"
            )
        }

        if let inheritedModelId = globalModelId(role)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !inheritedModelId.isEmpty {
            return (
                inheritedModelId,
                "\(roleLabel(role)) 当前继承的全局模型是"
            )
        }

        return nil
    }

    private func suggestedModelIDs(from assessment: HubModelAvailabilityAssessment) -> [String] {
        let source = assessment.loadedCandidates.isEmpty ? assessment.inventoryCandidates : assessment.loadedCandidates
        return source.prefix(3).map(\.id)
    }

    private func isRemote(_ m: HubModel) -> Bool {
        let mp = (m.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !mp.isEmpty { return false }
        return m.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "mlx"
    }

    private func stateRank(_ s: HubModelState) -> Int {
        switch s {
        case .loaded: return 0
        case .available: return 1
        case .sleeping: return 2
        }
    }

    private func resetProjectModelRoutingFeedback() {
        projectModelUpdateFeedback.cancel(resetState: true)
        projectModelChangeNotice = nil
    }

    private func updateProjectRoleModelAssignment(role: AXRole, modelId: String?) {
        let trimmedModelId = modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModelId = trimmedModelId?.isEmpty == false ? trimmedModelId : nil
        let currentModelId = projectModelOverrideId(for: role)
        guard normalizedModelOverrideValue(currentModelId) != normalizedModelOverrideValue(normalizedModelId) else {
            return
        }

        appModel.setProjectRoleModel(role: role, modelId: normalizedModelId)
        projectModelChangeNotice = XTSettingsChangeNoticeBuilder.projectRoleModel(
            projectName: ctx.displayName(registry: appModel.registry),
            role: role,
            modelId: normalizedModelId,
            inheritedModelId: globalModelId(role),
            snapshot: modelInventorySnapshot()
        )
        projectModelUpdateFeedback.trigger()
    }

    private func normalizedModelOverrideValue(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func saveTrustedAutomationBinding(armed: Bool) {
        let deviceId = trustedAutomationDeviceIdDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode: AXProjectAutomationMode = armed ? .trustedAutomation : .standard
        appModel.setProjectTrustedAutomationBinding(
            mode: mode,
            deviceId: deviceId,
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
        )
    }

    private func applyGovernanceTemplate(_ profile: AXProjectGovernanceTemplate) {
        appModel.applyProjectGovernanceTemplate(profile)

        let config = appModel.projectConfig ?? .default(forProjectRoot: ctx.root)
        let resolved = appModel.resolvedProjectGovernance(config: config)
        let templatePreview = xtProjectGovernanceTemplatePresentation(
            projectRoot: ctx.root,
            config: config,
            resolved: resolved
        )

        switch profile {
        case .agent:
            if templatePreview.effectiveDeviceAuthorityPosture == .off {
                governanceInlineMessage = "已切到 Agent 治理模板（默认 A4 Agent + S3）。若要真正放开设备级能力，请在执行面与设备绑定细节里完成权限就绪。"
                governanceInlineMessageIsError = false
                advancedGovernanceExpanded = true
            } else {
                clearGovernanceInlineMessage()
            }
        case .safe:
            governanceInlineMessage = "已切到推荐治理模板（默认 A3 + S3）。项目会优先持续推进，但高风险动作仍继续受 grant 与收束规则约束。"
            governanceInlineMessageIsError = false
        case .conservative:
            governanceInlineMessage = "已切到保守治理模板（默认 A1 + S2）。当前更偏向理解、规划与审阅，不主动放大执行面。"
            governanceInlineMessageIsError = false
        case .custom:
            break
        }
    }

    private func updateExecutionTier(_ tier: AXProjectExecutionTier) {
        let currentSupervisor = appModel.projectConfig?.supervisorInterventionTier ?? tier.defaultSupervisorInterventionTier
        let minimumSafe = tier.minimumSafeSupervisorTier
        let adjustedSupervisor = max(currentSupervisor, minimumSafe)
        appModel.setProjectGovernance(
            executionTier: tier,
            supervisorInterventionTier: adjustedSupervisor
        )
        if adjustedSupervisor != currentSupervisor {
            governanceInlineMessage = "\(tier.displayName) 至少需要 \(minimumSafe.displayName)，已自动把 supervisor 提升到安全下限。"
            governanceInlineMessageIsError = false
        } else {
            clearGovernanceInlineMessage()
        }
    }

    private func updateSupervisorTier(_ tier: AXProjectSupervisorInterventionTier) {
        let executionTier = appModel.projectConfig?.executionTier ?? .a0Observe
        let minimumSafe = executionTier.minimumSafeSupervisorTier
        guard tier >= minimumSafe else {
            governanceInlineMessage = "\(executionTier.displayName) 不能低于 \(minimumSafe.displayName)。当前更低组合会被系统直接拦下。"
            governanceInlineMessageIsError = true
            return
        }

        appModel.setProjectGovernance(supervisorInterventionTier: tier)
        if tier < executionTier.defaultSupervisorInterventionTier {
            governanceInlineMessage = "\(executionTier.displayName) 推荐 \(executionTier.defaultSupervisorInterventionTier.displayName) 及以上；当前配置允许，但 supervisor 纠偏窗口会更松。"
            governanceInlineMessageIsError = false
        } else {
            clearGovernanceInlineMessage()
        }
    }

    private func clearGovernanceInlineMessage() {
        governanceInlineMessage = ""
        governanceInlineMessageIsError = false
    }

    private func processProjectSettingsFocusRequest() {
        guard let request = appModel.projectSettingsFocusRequest else { return }
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        guard request.projectId == projectId else { return }
        guard activeFocusRequest?.nonce != request.nonce else { return }

        activeFocusRequest = request
        selectedGovernanceDestination = request.destination
        if let context = request.context {
            governanceInlineMessage = context.detail.map { "\(context.title) · \($0)" } ?? context.title
            governanceInlineMessageIsError = false
        }

        appModel.clearProjectSettingsFocusRequest(request)
    }

    private func saveGovernedReadableRoots() {
        let roots = governedReadableRootsDraft
            .split(whereSeparator: { $0.isNewline })
            .map { String($0) }
        appModel.setProjectGovernedReadableRoots(paths: roots)
    }

    private func appendGovernedReadableRootSuggestion(_ url: URL) {
        let path = PathGuard.resolve(url).path
        guard path != PathGuard.resolve(ctx.root).path else { return }
        guard path != "/" else { return }

        var lines = governedReadableRootsDraft
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !lines.contains(path) {
            lines.append(path)
            governedReadableRootsDraft = governedReadableRootsText(lines)
        }
    }

    private func governanceTemplateButton(
        _ profile: AXProjectGovernanceTemplate,
        isSelected: Bool
    ) -> some View {
        let accent = governanceTemplateAccent(profile)

        return Button {
            applyGovernanceTemplate(profile)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(profile.displayName)
                        .font(.headline)
                    if isSelected {
                        Text("当前")
                            .font(.caption2.monospaced())
                            .foregroundStyle(accent)
                    }
                    Spacer()
                }

                Text(profile.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(accent.opacity(isSelected ? 0.14 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? accent : Color.secondary.opacity(0.15), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func governanceTemplateStateCard(
        title: String,
        profile: AXProjectGovernanceTemplate,
        summary: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(profile.displayName)
                .font(.headline)
                .foregroundStyle(governanceTemplateAccent(profile))

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(governanceTemplateAccent(profile).opacity(0.08))
        )
    }

    private func governanceTemplateDimensionCard(
        title: String,
        configuredTitle: String,
        configuredDetail: String,
        effectiveTitle: String,
        effectiveDetail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("配置值")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text(configuredTitle)
                .font(.subheadline.weight(.semibold))
            Text(configuredDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("生效值")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text(effectiveTitle)
                .font(.subheadline.weight(.semibold))
            Text(effectiveDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func governanceTemplateAccent(_ profile: AXProjectGovernanceTemplate) -> Color {
        switch profile {
        case .conservative:
            return .secondary
        case .safe:
            return .green
        case .agent:
            return .orange
        case .custom:
            return .blue
        }
    }

    private func trustedAutomationIcon(_ state: AXTrustedAutomationProjectState) -> String {
        switch state {
        case .off:
            return "bolt.slash.circle"
        case .armed:
            return "bolt.badge.clock"
        case .active:
            return "bolt.shield.fill"
        case .blocked:
            return "exclamationmark.shield.fill"
        }
    }

    private func trustedAutomationColor(_ state: AXTrustedAutomationProjectState) -> Color {
        switch state {
        case .off:
            return .secondary
        case .armed:
            return .orange
        case .active:
            return .green
        case .blocked:
            return .red
        }
    }

    private func trustedAutomationPermissionColor(_ status: AXTrustedAutomationPermissionStatus) -> Color {
        switch status {
        case .granted:
            return .green
        case .missing:
            return .orange
        case .denied:
            return .red
        case .managed:
            return .blue
        }
    }

    private func trustedAutomationStateLabel(_ state: AXTrustedAutomationProjectState) -> String {
        switch state {
        case .off:
            return "未开启"
        case .armed:
            return "已绑定，等待生效"
        case .active:
            return "已生效"
        case .blocked:
            return "已阻塞"
        }
    }

    private func trustedAutomationModeLabel(_ mode: AXProjectAutomationMode) -> String {
        switch mode {
        case .standard:
            return "标准模式"
        case .trustedAutomation:
            return "受信自动化"
        }
    }

    private func trustedAutomationPermissionStatusLabel(_ status: AXTrustedAutomationPermissionStatus) -> String {
        switch status {
        case .granted:
            return "已授权"
        case .missing:
            return "缺失"
        case .denied:
            return "被拒绝"
        case .managed:
            return "受管"
        }
    }

    private func toggleStateLabel(_ enabled: Bool) -> String {
        enabled ? "开启" : "关闭"
    }

    private func configuredRuntimeSurfaceText(_ config: AXProjectConfig) -> String {
        let labels = config.configuredRuntimeSurfaceLabels
        return labels.isEmpty ? "(none)" : labels.joined(separator: ", ")
    }

    private func governedReadableRootsText(_ roots: [String]) -> String {
        roots.joined(separator: "\n")
    }

    private func effectiveGovernedReadableRootsText(
        config: AXProjectConfig,
        effective: AXProjectRuntimeSurfaceEffectivePolicy
    ) -> String {
        let authorityOn = xtProjectGovernedDeviceAuthorityEnabled(
            projectRoot: ctx.root,
            config: config,
            effectiveRuntimeSurface: effective
        )
        var roots = [PathGuard.resolve(ctx.root).path]
        if authorityOn {
            roots.append(contentsOf: config.governedReadableRoots)
        }
        return roots.joined(separator: ", ")
    }

    private func runtimeSurfaceRemainingText(
        config: AXProjectConfig,
        effective: AXProjectRuntimeSurfaceEffectivePolicy
    ) -> String {
        if effective.killSwitchEngaged {
            return "kill_switch"
        }
        if effective.expired {
            return "expired"
        }
        if config.runtimeSurfaceMode == .manual {
            return "n/a"
        }
        let minutes = max(1, (effective.remainingSeconds + 59) / 60)
        return "\(minutes)m"
    }

    private func runtimeSurfaceExplanationText(
        config: AXProjectConfig,
        effective: AXProjectRuntimeSurfaceEffectivePolicy
    ) -> String {
        if let clamp = xtProjectGovernanceClampExplanation(
            effective: effective,
            style: .uiChinese
        ) {
            return clamp.summary
        }
        return xtProjectRuntimeSurfaceExplanation(mode: effective.effectiveMode, style: .uiChinese)
    }

    private var runtimeSurfaceTimestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}
