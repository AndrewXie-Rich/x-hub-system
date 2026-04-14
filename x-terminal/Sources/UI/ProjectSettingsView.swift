import SwiftUI

func xtProjectSettingsInlineMessage(
    title: String,
    detail: String?
) -> String {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !normalizedDetail.isEmpty else { return normalizedTitle }
    if normalizedDetail.contains("\n") {
        return "\(normalizedTitle)\n\(normalizedDetail)"
    }
    return "\(normalizedTitle) · \(normalizedDetail)"
}

struct ProjectSettingsView: View {
    let ctx: AXProjectContext
    let initialGovernanceDestination: XTProjectGovernanceDestination

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var modelManager = HubModelManager.shared
    @StateObject private var supervisorManager = SupervisorManager.shared
    @StateObject private var projectModelUpdateFeedback = XTTransientUpdateFeedbackState()
    @State private var trustedAutomationDeviceIdDraft: String = ""
    @State private var governedReadableRootsDraft: String = ""
    @State private var governanceInlineMessage: String = ""
    @State private var governanceInlineMessageIsError = false
    @State private var modelPickerRole: AXRole?
    @State private var advancedGovernanceExpanded = false
    @State private var activeFocusRequest: XTProjectSettingsFocusRequest?
    @State private var pendingOverviewAnchor: XTProjectSettingsOverviewAnchor?
    @State private var selectedGovernanceDestination: XTProjectGovernanceDestination
    @State private var projectModelChangeNotice: XTSettingsChangeNotice?
    @State private var projectConfigSnapshot: AXProjectConfig
    @State private var projectSkillsCompatibilitySnapshot: AXSkillsDoctorSnapshot = .empty

    init(
        ctx: AXProjectContext,
        initialGovernanceDestination: XTProjectGovernanceDestination = .overview
    ) {
        self.ctx = ctx
        self.initialGovernanceDestination = initialGovernanceDestination
        let initialConfig = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
        _selectedGovernanceDestination = State(initialValue: initialGovernanceDestination)
        _projectConfigSnapshot = State(initialValue: initialConfig)
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
            reloadProjectConfigSnapshot()
            refreshProjectSkillsCompatibilitySnapshot()
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
            Task {
                await refreshProjectSkillGovernanceSurface(force: true)
            }
            if connected {
                Task {
                    await modelManager.fetchModels()
                }
            }
        }
        .onChange(of: appModel.projectConfig) { _ in
            syncProjectConfigSnapshotFromCurrentSelection()
            refreshProjectSkillsCompatibilitySnapshot()
        }
        .task(id: projectSkillGovernanceRefreshKey) {
            await refreshProjectSkillGovernanceSurface(force: true)
        }
        .onDisappear {
            resetProjectModelRoutingFeedback()
        }
    }

    private var overviewSettingsBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("项目设置")
                            .font(.headline)
                        Spacer()
                        Button("关闭") { dismiss() }
                    }

                    Text(ctx.displayName(registry: appModel.registry))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()

                    governanceQuickAccessSection
                    governanceThreeAxisOverviewSection

                    latestUIReviewSection
                    GroupBox("项目级模型路由") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("每个角色可选择不同模型；留空 = 使用全局设置。")
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
                            } else if projectModelInventoryTruth.showsStatusCard {
                                XTModelInventoryTruthCard(presentation: projectModelInventoryTruth)
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
                        .id(XTProjectSettingsOverviewAnchor.contextAssembly.rawValue)
                    automationSelfIterateSection
                    governanceTemplateSection
                    skillGovernanceSection
                    ProjectGovernanceActivityView(ctx: ctx)
                    advancedGovernanceSection
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                processOverviewAnchor(proxy)
            }
            .onChange(of: pendingOverviewAnchor?.rawValue) { _ in
                processOverviewAnchor(proxy)
            }
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
        let raw = governanceConfig.modelOverride(for: role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var latestUIReviewSection: some View {
        GroupBox("最近一次 UI 审查") {
            ProjectUIReviewWorkspaceView(
                ctx: ctx,
                emptyTitle: "暂无浏览器 UI 审查",
                emptyMessage: "当前项目还没有浏览器 UI 审查。执行一次 `device.browser.control snapshot` 后，系统会在这里展示最近一次受治理 UI 观察结果。",
                helperText: "这条审查会被项目 AI / Supervisor 记忆 / 恢复摘要共同消费。它的作用不是替代人工验收，而是先让系统判断“当前页面是否真的可执行”。"
            )
            .padding(8)
        }
    }

    private var focusedSettingsDestinations: [XTProjectGovernanceDestination] {
        [.uiReview] + XTProjectGovernanceDestination.editorCases
    }

    private var governanceConfig: AXProjectConfig {
        projectConfigSnapshot
    }

    private var isCurrentProjectSelected: Bool {
        appModel.projectContext?.root.standardizedFileURL.path == ctx.root.standardizedFileURL.path
    }

    private var currentProjectRemoteRuntimeSurfaceOverride: AXProjectRuntimeSurfaceRemoteOverrideSnapshot? {
        isCurrentProjectSelected ? appModel.projectRemoteRuntimeSurfaceOverride : nil
    }

    private var currentProjectAIStrengthProfile: AXProjectAIStrengthProfile {
        AXProjectAIStrengthAssessor.assess(
            ctx: ctx,
            adaptationPolicy: .default
        )
    }

    private var resolvedGovernanceState: AXProjectResolvedGovernanceState {
        xtResolveProjectGovernance(
            projectRoot: ctx.root,
            config: governanceConfig,
            remoteOverride: currentProjectRemoteRuntimeSurfaceOverride,
            projectAIStrengthProfile: currentProjectAIStrengthProfile,
            adaptationPolicy: .default
        )
    }

    private var currentProjectContextAssemblyDiagnostics: AXProjectContextAssemblyDiagnosticsSummary {
        AXProjectContextAssemblyDiagnosticsStore.doctorSummary(
            for: ctx,
            config: governanceConfig
        )
    }

    private var currentProjectContextAssemblyPresentation: AXProjectContextAssemblyPresentation? {
        AXProjectContextAssemblyPresentation.from(summary: currentProjectContextAssemblyDiagnostics)
    }

    private var resolvedGovernancePresentation: ProjectGovernancePresentation {
        ProjectGovernancePresentation(
            resolved: resolvedGovernanceState,
            scheduleState: SupervisorReviewScheduleStore.load(for: ctx)
        )
    }

    private var recentGovernanceInterception: ProjectGovernanceInterceptionPresentation? {
        ProjectGovernanceInterceptionPresentation.latest(
            from: AXProjectSkillActivityStore.loadRecentActivities(ctx: ctx, limit: 32)
        )
    }

    private var skillGovernanceProjectID: String {
        AXProjectRegistryStore.projectId(forRoot: ctx.root)
    }

    private var skillGovernanceProjectName: String {
        ctx.displayName(registry: appModel.registry)
    }

    private var skillGovernanceHubBaseDir: URL {
        appModel.hubBaseDir ?? HubPaths.baseDir()
    }

    private var projectSkillProfileSnapshot: XTProjectEffectiveSkillProfileSnapshot {
        AXSkillsLibrary.projectEffectiveSkillProfileSnapshot(
            projectId: skillGovernanceProjectID,
            projectName: skillGovernanceProjectName,
            projectRoot: ctx.root,
            config: governanceConfig,
            hubBaseDir: skillGovernanceHubBaseDir
        )
    }

    private var projectGovernanceSurfaceEntries: [AXSkillGovernanceSurfaceEntry] {
        projectSkillsCompatibilitySnapshot.governanceSurfaceEntries(
            projectId: skillGovernanceProjectID,
            projectName: skillGovernanceProjectName,
            projectRoot: ctx.root,
            config: governanceConfig,
            hubBaseDir: skillGovernanceHubBaseDir
        )
    }

    private var projectSkillGovernanceRefreshKey: String {
        [
            skillGovernanceProjectID,
            skillGovernanceHubBaseDir.path,
            appModel.hubInteractive ? "hub=interactive" : "hub=offline"
        ].joined(separator: "|")
    }

    private var effectiveRuntimeSurface: AXProjectRuntimeSurfaceEffectivePolicy {
        resolvedGovernanceState.effectiveRuntimeSurface
    }

    private func refreshProjectSkillsCompatibilitySnapshot() {
        projectSkillsCompatibilitySnapshot = AXSkillsLibrary.compatibilityDoctorSnapshot(
            projectId: skillGovernanceProjectID,
            projectName: skillGovernanceProjectName,
            skillsDir: AXSkillsLibrary.resolveSkillsDirectory(),
            hubBaseDir: skillGovernanceHubBaseDir
        )
    }

    @MainActor
    private func refreshProjectSkillGovernanceSurface(force: Bool = false) async {
        refreshProjectSkillsCompatibilitySnapshot()
        _ = await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
            projectId: skillGovernanceProjectID,
            projectName: skillGovernanceProjectName,
            context: ctx,
            hubBaseDir: skillGovernanceHubBaseDir,
            force: force
        )
        refreshProjectSkillsCompatibilitySnapshot()
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

    private var interfaceLanguage: XTInterfaceLanguage {
        appModel.settingsStore.settings.interfaceLanguage
    }

    private func roleModelSelectionButton(_ role: AXRole) -> some View {
        let title = selectedModelButtonTitle(for: role)
        let presentation = selectedModelPresentation(for: role)
        let identifier = selectedModelIdentifier(for: role)
        let sourceLabel = selectedModelPresentationSourceLabel(for: role)
        let routeTruth = projectRoleRouteTruth(for: role)
        let buttonDisabled = !appModel.hubInteractive || sortedAvailableHubModels.isEmpty

        return HubModelRoutingButton(
            title: title,
            identifier: identifier,
            sourceLabel: sourceLabel,
            presentation: presentation,
            sourceIdentityLine: selectedHubModel(for: role)?.remoteSourceIdentityLine(language: interfaceLanguage),
            sourceBadges: selectedHubModel(for: role)?.routingSourceBadges(language: interfaceLanguage) ?? [],
            supplementary: routeTruth,
            disabled: buttonDisabled,
            automaticRouteLabel: XTL10n.Common.automaticRouting.resolve(interfaceLanguage)
        ) {
            modelPickerRole = role
        }
        .frame(maxWidth: 420, alignment: .leading)
        .popover(isPresented: modelPickerBinding(for: role), arrowEdge: .bottom) {
                HubModelPickerPopover(
                    title: XTL10n.text(
                        interfaceLanguage,
                        zhHans: "为 \(role.displayName(in: interfaceLanguage)) 选择模型",
                        en: "Choose Model for \(role.displayName(in: interfaceLanguage))"
                    ),
                    selectedModelId: projectModelOverrideId(for: role),
                    inheritedModelId: globalModelId(role),
                    inheritedModelPresentation: globalModelPresentation(for: role),
                    models: sortedAvailableHubModels,
                    language: interfaceLanguage,
                    recommendation: modelSelectionRecommendation(for: role),
                    selectionTruth: routeTruth,
                    selectionTruthTitle: XTL10n.text(
                        interfaceLanguage,
                        zhHans: "\(roleLabel(role)) · 当前项目 Route Truth",
                        en: "\(role.displayName(in: interfaceLanguage)) · Current Project Route Truth"
                    ),
                    automaticTitle: XTL10n.text(
                        interfaceLanguage,
                        zhHans: "使用全局设置",
                        en: "Use Global Setting"
                    ),
                    automaticSelectedBadge: XTL10n.text(
                        interfaceLanguage,
                        zhHans: "当前生效",
                        en: "Currently Active"
                    ),
                    automaticRestoreBadge: XTL10n.text(
                        interfaceLanguage,
                        zhHans: "恢复继承",
                        en: "Restore Inheritance"
                    ),
                    inheritedModelLabel: XTL10n.text(
                        interfaceLanguage,
                        zhHans: "全局模型",
                        en: "Global Model"
                    ),
                    automaticDescription: XTL10n.text(
                        interfaceLanguage,
                        zhHans: "当前没有全局固定模型，恢复后会交给系统自动路由。",
                        en: "There is no global pinned model right now. Restoring inheritance will hand routing back to the system."
                    ),
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

        return GroupBox("执行场景模板") {
            VStack(alignment: .leading, spacing: 12) {
                Text("这些模板会一次初始化 A-Tier / S-Tier / Heartbeat / Review / Project Context 连续性。真正生效的执行权限、Supervisor 介入、TTL、受治理自动化与可读根目录，仍以下方治理设置和运行时收束为准。")
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
                    Text("当前场景模板已偏离默认映射：系统会以实际保存的 A-Tier / S-Tier / Heartbeat / Review 配置与 Project Context 连续性为准。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if templatePreview.configuredProfile == .legacyObserve {
                    Text("当前项目仍是旧 Observe 基线；点任一场景模板即可迁入新的五档执行场景真相。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

                recentGovernanceInterceptionSection

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
                    Text("模板输入和运行时投影当前不完全一致。真正放行动作仍继续受执行面 TTL、收束规则、受治理自动化、授权门、Project Context 实际装配和紧急回收共同约束。")
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
                    Text("配置偏差：\(templatePreview.configuredDeviationReasons.joined(separator: " · "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if !templatePreview.effectiveDeviationReasons.isEmpty {
                    Text("运行时备注：\(templatePreview.effectiveDeviationReasons.joined(separator: " · "))")
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

    private var skillGovernanceSection: some View {
        Group {
            if !projectGovernanceSurfaceEntries.isEmpty {
                GroupBox("技能治理") {
                    VStack(alignment: .leading, spacing: 10) {
                        skillProfileSummaryCard

                        XTSkillGovernanceSurfaceView(
                            items: projectGovernanceSurfaceEntries,
                            title: "当前 governed skills 可执行真相",
                            maxItems: 4
                        )
                    }
                    .padding(8)
                }
            }
        }
    }

    private var skillProfileSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("项目级 capability profile 真相")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(
                "discoverable=\(projectSkillProfileSnapshot.discoverableProfiles.count) " +
                "installable=\(projectSkillProfileSnapshot.installableProfiles.count) " +
                "requestable=\(projectSkillProfileSnapshot.requestableProfiles.count) " +
                "runnable_now=\(projectSkillProfileSnapshot.runnableNowProfiles.count)"
            )
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

            if !projectSkillProfileSnapshot.discoverableProfiles.isEmpty {
                skillProfileSummaryRow(
                    label: "Discoverable",
                    values: projectSkillProfileSnapshot.discoverableProfiles
                )
            }
            if !projectSkillProfileSnapshot.installableProfiles.isEmpty {
                skillProfileSummaryRow(
                    label: "Installable",
                    values: projectSkillProfileSnapshot.installableProfiles
                )
            }
            if !projectSkillProfileSnapshot.requestableProfiles.isEmpty {
                skillProfileSummaryRow(
                    label: "Requestable",
                    values: projectSkillProfileSnapshot.requestableProfiles
                )
            }
            if !projectSkillProfileSnapshot.runnableNowProfiles.isEmpty {
                skillProfileSummaryRow(
                    label: "Runnable now",
                    values: projectSkillProfileSnapshot.runnableNowProfiles
                )
            }

            if !projectSkillProfileSnapshot.blockedProfiles.isEmpty {
                let blockedSummary = projectSkillProfileSnapshot.blockedProfiles
                    .prefix(3)
                    .map { blocked in
                        "\(blocked.profileID)=\(blocked.reasonCode)"
                    }
                    .joined(separator: " | ")
                Text("why_not_runnable: \(blockedSummary)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func skillProfileSummaryRow(label: String, values: [String]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(values.joined(separator: ", "))
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hubMemorySection: some View {
        let preferHubMemory = governanceConfig.preferHubMemory
        let mode = XTProjectMemoryGovernance.modeLabel(governanceConfig)

        return GroupBox("Hub 记忆治理") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "当前项目优先使用 Hub 记忆",
                    isOn: Binding(
                        get: { governanceConfig.preferHubMemory },
                        set: { updateProjectHubMemoryPreference($0) }
                    )
                )
                .toggleStyle(.switch)

                Text("默认：开 · 模式：\(mode)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text(preferHubMemory
                     ? "开启后：X-Terminal 会优先用 Hub 记忆组装上下文，并继续保留本地 `.xterminal/AX_MEMORY.md` / `recent_context.json` 作为连续上下文 / 兜底层。Hub 侧 X-宪章、远端导出门、技能撤销门和紧急回收会参与约束。"
                     : "关闭后：当前项目只使用本地 `.xterminal/AX_MEMORY.md` / `recent_context.json` 组装上下文，不请求 Hub 记忆上下文。适合离线或临时隔离场景。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("注意：当前实现仍保留本地记忆文件用于崩溃恢复与兜底，所以这还不是单一 Hub 真源；这里只控制上下文组装时是否优先走 Hub。")
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
                Text("这里控制项目 AI 最近能看到多少项目对话，以及项目背景带多完整。默认值通常由上面的执行场景模板初始化，之后可以单独微调；它不会改变执行权限、Supervisor 介入强度或心跳节奏。")
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
                            set: { updateProjectContextAssembly(projectRecentDialogueProfile: $0) }
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
                            set: { updateProjectContextAssembly(projectContextDepthProfile: $0) }
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

                Text("上面两项就是项目 AI 的主要背景开关：前者决定保留多少最近项目对话，后者决定带入多少项目材料。实际运行后，下面会显示它这轮真正吃到的背景。")
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
        let config = governanceConfig
        let effective = effectiveRuntimeSurface
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

                Text("这是一条项目级设备执行绑定，不等于把整个 X-Terminal 永久全开；高档执行场景模板也不等于自动拥有全部设备权限。")
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
                        get: { governanceConfig.governedAutoApproveLocalToolCalls },
                        set: { updateProjectGovernedAutoApproveLocalToolCalls(enabled: $0) }
                    )
                )
                .toggleStyle(.switch)
                .disabled(status.mode != .trustedAutomation)

                Text(configuredAutoApprove
                     ? "开启后：当前项目下的低风险待确认本地工具会直接执行，不再等待本地审批。高风险 shell 和网络授权仍保留人工 / Hub 门禁。"
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

                    Text("每行一个路径；支持绝对路径，也支持相对当前项目根目录的路径。这里只扩展 `read_file` / `list_dir` / `search(path=...)`，不会放开项目外的 `write_file` / `run_command`。")
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
                    Text(selectedGovernanceDestination.localizedDisplayTitle)
                        .font(.headline)
                    Text(ctx.displayName(registry: appModel.registry))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("全部设置") {
                    selectedGovernanceDestination = .overview
                }
                .buttonStyle(.bordered)

                Button("关闭") {
                    dismiss()
                }
            }

            governanceDestinationTabs
        }
    }

    private var governanceQuickAccessSection: some View {
        GroupBox("治理快捷入口") {
            ProjectGovernanceQuickAccessStrip(
                selectedDestination: selectedGovernanceDestination == .overview ? nil : selectedGovernanceDestination,
                governancePresentation: resolvedGovernancePresentation,
                onSelect: { destination in
                    selectedGovernanceDestination = destination
                }
            )
            .padding(8)
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
            Text(destination.localizedDisplayTitle)
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
                ProjectGovernanceThreeAxisOverviewView(
                    presentation: resolvedGovernancePresentation,
                    compact: true,
                    onSelectDestination: { destination in
                        selectedGovernanceDestination = destination
                    },
                    onOpenProjectMemoryControls: openProjectMemoryControls,
                    onOpenSupervisorMemoryControls: openSupervisorMemoryControls
                )
                ProjectGovernanceInspector(presentation: resolvedGovernancePresentation)
                recentGovernanceInterceptionSection

                if !governanceInlineMessage.isEmpty {
                    Text(governanceInlineMessage)
                        .font(.caption)
                        .foregroundStyle(governanceInlineMessageIsError ? .red : .orange)
                }
            }
            .padding(8)
        }
    }

    private var governanceThreeAxisOverviewSection: some View {
        ProjectGovernanceThreeAxisOverviewView(
            presentation: resolvedGovernancePresentation,
            onSelectDestination: { destination in
                selectedGovernanceDestination = destination
            },
            onOpenProjectMemoryControls: openProjectMemoryControls,
            onOpenSupervisorMemoryControls: openSupervisorMemoryControls
        )
    }

    private var recentGovernanceInterceptionSection: some View {
        GroupBox("最近治理拦截") {
            VStack(alignment: .leading, spacing: 8) {
                if let interception = recentGovernanceInterception {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ProjectSkillActivityPresentation.toolBadge(for: interception.item))
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(ProjectSkillActivityPresentation.statusLabel(for: interception.item))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    if let truthLine = interception.governanceTruthLine {
                        Text(truthLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let blockedSummary = interception.blockedSummary {
                        Text(blockedSummary)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if interception.shouldShowGovernanceReason {
                        Text("治理原因：\(interception.governanceReason)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let policyReason = interception.policyReason {
                        Text("策略原因：\(policyReason)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        if let repairHint = interception.repairHint {
                            VStack(alignment: .leading, spacing: 4) {
                                Button(repairHint.buttonTitle) {
                                    selectedGovernanceDestination = repairHint.destination
                                    if let inlineMessage = interception.repairInlineMessage {
                                        governanceInlineMessage = inlineMessage
                                        governanceInlineMessageIsError = false
                                    }
                                }
                                .buttonStyle(.bordered)
                                .help(repairHint.helpText)

                                Text(repairHint.helpText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer()

                        Text("请求 \(interception.item.requestID) · \(recentGovernanceInterceptionTimestamp(interception.item.createdAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("最近没有记录到 A-Tier 或运行面拦截。后续一旦出现 A-Tier / runtime surface 拦截，这里会直接显示最近一次真相与修复入口。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

            Text("这里是项目的 UI 审查专属工作区。Supervisor / 项目 AI 都可以把这里当作“页面是否真的可执行”的当前真相入口。")
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
            projectConfig: governanceConfig,
            configuredExecutionTier: governanceConfig.executionTier,
            configuredReviewPolicyMode: governanceConfig.reviewPolicyMode,
            progressHeartbeatSeconds: governanceConfig.progressHeartbeatSeconds,
            reviewPulseSeconds: governanceConfig.reviewPulseSeconds,
            brainstormReviewSeconds: governanceConfig.brainstormReviewSeconds,
            eventDrivenReviewEnabled: governanceConfig.eventDrivenReviewEnabled,
            eventReviewTriggers: governanceConfig.eventReviewTriggers,
            configuredSupervisorRecentRawContextProfile: appModel.settingsStore.settings.supervisorRecentRawContextProfile,
            configuredSupervisorReviewMemoryDepth: appModel.settingsStore.settings.supervisorReviewMemoryDepthProfile,
            supervisorPrivacyMode: appModel.settingsStore.settings.supervisorPrivacyMode,
            resolvedGovernance: resolvedGovernanceState,
            governancePresentation: resolvedGovernancePresentation,
            inlineMessage: governanceInlineMessage,
            inlineMessageIsError: governanceInlineMessageIsError,
            onSelectReviewPolicy: { updateProjectGovernance(reviewPolicyMode: $0) },
            onUpdateProgressHeartbeatSeconds: { updateProjectGovernance(progressHeartbeatSeconds: $0) },
            onUpdateReviewPulseSeconds: { updateProjectGovernance(reviewPulseSeconds: $0) },
            onUpdateBrainstormReviewSeconds: { updateProjectGovernance(brainstormReviewSeconds: $0) },
            onSetEventDrivenReviewEnabled: { updateProjectGovernance(eventDrivenReviewEnabled: $0) },
            onSetEventReviewTriggers: { updateProjectGovernance(eventReviewTriggers: $0) }
        )
        .id(XTProjectSettingsSectionID.reviewCadence)
    }

    private var runtimeSurfaceSection: some View {
        GroupBox("执行面运行时") {
            VStack(alignment: .leading, spacing: 12) {
                Text("A-Tier / S-Tier / Heartbeat / Review 已拆到各自独立页面。这里仅保留执行面、TTL 与 Hub 收束相关细项。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Stepper(
                    value: Binding(
                        get: { max(5, governanceConfig.runtimeSurfaceTTLSeconds / 60) },
                        set: { updateProjectRuntimeSurfacePolicy(ttlSeconds: max(5, $0) * 60) }
                    ),
                    in: 5...1440,
                    step: 5
                ) {
                    Text("执行面 TTL：\((governanceConfig.runtimeSurfaceTTLSeconds / 60)) 分钟")
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("终端本地收束")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 140, alignment: .leading)

                    Picker(
                        "",
                        selection: Binding(
                            get: { governanceConfig.runtimeSurfaceHubOverrideMode },
                            set: { updateProjectRuntimeSurfacePolicy(hubOverrideMode: $0) }
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

                Text("Hub 收束来源：\(effectiveRuntimeSurface.remoteOverrideSource.isEmpty ? "无" : effectiveRuntimeSurface.remoteOverrideSource) · Hub 收束更新时间：\(hubOverrideUpdatedAtText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("A-Tier 会同步默认执行面，但真正放行动作仍继续受 TTL、收束规则、设备执行绑定、权限宿主和紧急回收共同约束。")
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
        GroupBox("执行面与受治理自动化") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("这里保留执行面、设备执行绑定、可读目录和本地自动审批细项。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("A-Tier / S-Tier / Heartbeat / Review 已拆到各自独立页面；点治理摘要卡即可进入对应编辑器。")
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
            if let assemblySummary = presentation.userAssemblySummary {
                Text(assemblySummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let omissionSummary = presentation.userOmissionSummary {
                Text(omissionSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let budgetSummary = presentation.userBudgetSummary {
                Text(budgetSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        let enabled = governanceConfig.automationSelfIterateEnabled
        let maxDepth = governanceConfig.automationMaxAutoRetryDepth
        let recipeRef = governanceConfig.activeAutomationRecipeRef.trimmingCharacters(in: .whitespacesAndNewlines)

        return GroupBox("自动自迭代") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "开启有边界的自迭代自动重试",
                    isOn: Binding(
                        get: { governanceConfig.automationSelfIterateEnabled },
                        set: { updateProjectAutomationSelfIteration(enabled: $0) }
                    )
                )
                .toggleStyle(.switch)

                Stepper(
                    value: Binding(
                        get: { governanceConfig.automationMaxAutoRetryDepth },
                        set: { updateProjectAutomationSelfIteration(maxAutoRetryDepth: $0) }
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
        modelManager.visibleSnapshot(fallback: appModel.modelsState)
    }

    private var projectModelInventoryTruth: XTModelInventoryTruthPresentation {
        XTModelInventoryTruthPresentation.build(
            snapshot: modelInventorySnapshot(),
            hubBaseDir: appModel.hubBaseDir ?? HubPaths.baseDir()
        )
    }

    private var availableHubModels: [HubModel] {
        modelManager.visibleSnapshot(fallback: appModel.modelsState).models
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

    private func selectedHubModel(for role: AXRole) -> HubModel? {
        if let projectModelId = projectModelOverrideId(for: role) {
            return availableHubModels.first(where: { $0.id == projectModelId })
        }
        let inheritedModelId = globalModelId(role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !inheritedModelId.isEmpty else { return nil }
        return availableHubModels.first(where: { $0.id == inheritedModelId })
    }

    private func globalModelPresentation(for role: AXRole) -> ModelInfo? {
        let inheritedModelId = globalModelId(role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !inheritedModelId.isEmpty else { return nil }
        return availableHubModels.first(where: { $0.id == inheritedModelId })?.capabilityPresentationModel
            ?? XTModelCatalog.modelInfo(for: inheritedModelId)
    }

    private func selectedModelPresentationSourceLabel(for role: AXRole) -> String {
        projectModelOverrideId(for: role) == nil
            ? XTL10n.text(
                interfaceLanguage,
                zhHans: "继承全局",
                en: "Inherited Global"
            )
            : XTL10n.text(
                interfaceLanguage,
                zhHans: "项目覆盖",
                en: "Project Override"
            )
    }

    private var routeTruthProjectID: String {
        AXProjectRegistryStore.projectId(forRoot: ctx.root)
    }

    private var routeTruthProjectName: String {
        ctx.displayName(registry: appModel.registry)
    }

    private func projectRoleExecutionSnapshot(for role: AXRole) -> AXRoleExecutionSnapshot {
        if role == .supervisor {
            return ExecutionRoutePresentation.supervisorSnapshot(from: supervisorManager)
        }
        return AXRoleExecutionSnapshots.latestSnapshots(for: ctx)[role]
            ?? .empty(role: role, source: "project_settings")
    }

    private func projectRoleRouteTruth(for role: AXRole) -> HubModelRoutingSupplementaryPresentation {
        HubModelRoutingTruthBuilder.build(
            surface: .projectRoleSettings,
            role: role,
            selectedProjectID: routeTruthProjectID,
            selectedProjectName: routeTruthProjectName,
            projectConfig: governanceConfig,
            projectRuntimeReadiness: xtResolveProjectGovernance(
                projectRoot: ctx.root,
                config: governanceConfig
            ).runtimeReadinessSnapshot,
            settings: appModel.settingsStore.settings,
            snapshot: projectRoleExecutionSnapshot(for: role),
            transportMode: HubAIClient.transportMode().rawValue,
            language: interfaceLanguage
        )
        .pickerTruth
    }

    private func selectedModelButtonTitle(for role: AXRole) -> String {
        if let presentation = selectedModelPresentation(for: role) {
            return presentation.displayName
        }
        return XTL10n.text(
            interfaceLanguage,
            zhHans: "使用全局设置",
            en: "Use Global Setting"
        )
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
            return XTL10n.text(
                interfaceLanguage,
                zhHans: "当前不选项目覆盖时，会回到全局模型 `\(global)`。",
                en: "If you clear the project override, XT will fall back to the global model `\(global)`."
            )
        }
        return XTL10n.text(
            interfaceLanguage,
            zhHans: "当前不选项目覆盖时，会回到全局自动路由。",
            en: "If you clear the project override, XT will fall back to global automatic routing."
        )
    }

    private func modelSelectionRecommendation(for role: AXRole) -> HubModelPickerRecommendationState? {
        let configured = selectedModelIdentifier(for: role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !configured.isEmpty else { return nil }

        if let guidance = AXProjectModelRouteMemoryStore.selectionGuidance(
            configuredModelId: configured,
            role: role,
            ctx: ctx,
            snapshot: modelInventorySnapshot(),
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
                    stateLabel: HubModelSelectionAdvisor.stateLabel(
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
                selectedModelId: configured,
                candidate: candidate,
                language: interfaceLanguage
            )
        )
    }

    private func modelAvailabilityWarningText(for role: AXRole) -> String? {
        guard let configuredBinding = warningConfiguredModelBinding(for: role) else { return nil }
        let configured = configuredBinding.modelId
        let executionSnapshot = projectRoleExecutionSnapshot(for: role)
        if let routeWarning = AXProjectModelRouteMemoryStore.selectionWarningText(
            configuredModelId: configured,
            role: role,
            ctx: ctx,
            snapshot: modelInventorySnapshot(),
            paidAccessSnapshot: appModel.hubRemotePaidAccessSnapshot,
            language: interfaceLanguage
        ) {
            return appendingGrpcRouteInterpretationWarning(
                routeWarning,
                configuredModelId: configured,
                snapshot: executionSnapshot
            )
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
                return appendingGrpcRouteInterpretationWarning(
                    XTL10n.text(
                        interfaceLanguage,
                        zhHans: "\(configuredBinding.subject) `\(blocked.id)`，但它是检索专用模型。\(reason) 如果你要立刻继续，可改用 `\(first)`。",
                        en: "The \(configuredBinding.subject) `\(blocked.id)` is retrieval-only. \(reason) If you want to continue right now, switch to `\(first)`."
                    ),
                    configuredModelId: configured,
                    snapshot: executionSnapshot
                )
            }
            return appendingGrpcRouteInterpretationWarning(
                XTL10n.text(
                    interfaceLanguage,
                    zhHans: "\(configuredBinding.subject) `\(blocked.id)`，但它是检索专用模型。\(reason)",
                    en: "The \(configuredBinding.subject) `\(blocked.id)` is retrieval-only. \(reason)"
                ),
                configuredModelId: configured,
                snapshot: executionSnapshot
            )
        }

        if let assessment, let exact = assessment.exactMatch {
            let candidates = suggestedModelIDs(from: assessment)
            if let first = candidates.first {
                return appendingGrpcRouteInterpretationWarning(
                    XTL10n.text(
                        interfaceLanguage,
                        zhHans: "\(configuredBinding.subject) `\(exact.id)`，但它现在是 \(HubModelSelectionAdvisor.stateLabel(exact.state, language: interfaceLanguage))。若你现在执行，这一路可能会回退到本地；如果你要立刻继续，可改用 `\(first)`。",
                        en: "The \(configuredBinding.subject) `\(exact.id)` is currently \(HubModelSelectionAdvisor.stateLabel(exact.state, language: interfaceLanguage)). This route may fall back to local if you run it now. If you want to continue right away, switch to `\(first)`."
                    ),
                    configuredModelId: configured,
                    snapshot: executionSnapshot
                )
            }
            return appendingGrpcRouteInterpretationWarning(
                XTL10n.text(
                    interfaceLanguage,
                    zhHans: "\(configuredBinding.subject) `\(exact.id)`，但它现在是 \(HubModelSelectionAdvisor.stateLabel(exact.state, language: interfaceLanguage))。若你现在执行，这一路可能会回退到本地。",
                    en: "The \(configuredBinding.subject) `\(exact.id)` is currently \(HubModelSelectionAdvisor.stateLabel(exact.state, language: interfaceLanguage)). This route may fall back to local if you run it now."
                ),
                configuredModelId: configured,
                snapshot: executionSnapshot
            )
        }

        if let assessment {
            let candidates = suggestedModelIDs(from: assessment)
            if !candidates.isEmpty {
                return appendingGrpcRouteInterpretationWarning(
                    XTL10n.text(
                        interfaceLanguage,
                        zhHans: "\(configuredBinding.subject) `\(configured)`，但 inventory 里没有精确匹配。可先试 `\(candidates.joined(separator: "`, `"))`。",
                        en: "The \(configuredBinding.subject) `\(configured)` has no exact match in the current inventory. Try `\(candidates.joined(separator: "`, `"))` first."
                    ),
                    configuredModelId: configured,
                    snapshot: executionSnapshot
                )
            }
        }
        return appendingGrpcRouteInterpretationWarning(
            XTL10n.text(
                interfaceLanguage,
                zhHans: "\(configuredBinding.subject) `\(configured)`，但现在无法确认它可执行。",
                en: "XT cannot confirm whether the \(configuredBinding.subject) `\(configured)` is currently runnable."
            ),
            configuredModelId: configured,
            snapshot: executionSnapshot
        )
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

    private func warningConfiguredModelBinding(for role: AXRole) -> (modelId: String, subject: String)? {
        if let projectModelId = projectModelOverrideId(for: role)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !projectModelId.isEmpty {
            return (
                projectModelId,
                XTL10n.text(
                    interfaceLanguage,
                    zhHans: "当前项目给 \(roleLabel(role)) 配的模型",
                    en: "project override for \(role.displayName(in: interfaceLanguage))"
                )
            )
        }

        if let inheritedModelId = globalModelId(role)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !inheritedModelId.isEmpty {
            return (
                inheritedModelId,
                XTL10n.text(
                    interfaceLanguage,
                    zhHans: "\(roleLabel(role)) 当前继承的全局模型",
                    en: "global model inherited by \(role.displayName(in: interfaceLanguage))"
                )
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

    private func syncProjectConfigDrafts(_ config: AXProjectConfig) {
        trustedAutomationDeviceIdDraft = config.trustedAutomationDeviceId
        governedReadableRootsDraft = governedReadableRootsText(config.governedReadableRoots)
    }

    private func reloadProjectConfigSnapshot() {
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
        projectConfigSnapshot = config
        syncProjectConfigDrafts(config)
    }

    private func syncProjectConfigSnapshotFromCurrentSelection() {
        guard isCurrentProjectSelected, let config = appModel.projectConfig else { return }
        projectConfigSnapshot = config
        syncProjectConfigDrafts(config)
    }

    private func updateProjectHubMemoryPreference(_ enabled: Bool) {
        appModel.setProjectHubMemoryPreference(for: ctx, enabled: enabled)
        reloadProjectConfigSnapshot()
    }

    private func updateProjectContextAssembly(
        projectRecentDialogueProfile: AXProjectRecentDialogueProfile? = nil,
        projectContextDepthProfile: AXProjectContextDepthProfile? = nil
    ) {
        appModel.setProjectContextAssembly(
            for: ctx,
            projectRecentDialogueProfile: projectRecentDialogueProfile,
            projectContextDepthProfile: projectContextDepthProfile
        )
        reloadProjectConfigSnapshot()
    }

    private func updateProjectGovernance(
        executionTier: AXProjectExecutionTier? = nil,
        supervisorInterventionTier: AXProjectSupervisorInterventionTier? = nil,
        reviewPolicyMode: AXProjectReviewPolicyMode? = nil,
        progressHeartbeatSeconds: Int? = nil,
        reviewPulseSeconds: Int? = nil,
        brainstormReviewSeconds: Int? = nil,
        eventDrivenReviewEnabled: Bool? = nil,
        eventReviewTriggers: [AXProjectReviewTrigger]? = nil
    ) {
        appModel.setProjectGovernance(
            for: ctx,
            executionTier: executionTier,
            supervisorInterventionTier: supervisorInterventionTier,
            reviewPolicyMode: reviewPolicyMode,
            progressHeartbeatSeconds: progressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            eventDrivenReviewEnabled: eventDrivenReviewEnabled,
            eventReviewTriggers: eventReviewTriggers
        )
        reloadProjectConfigSnapshot()
    }

    private func updateProjectRuntimeSurfacePolicy(
        mode: AXProjectRuntimeSurfaceMode? = nil,
        allowDeviceTools: Bool? = nil,
        allowBrowserRuntime: Bool? = nil,
        allowConnectorActions: Bool? = nil,
        allowExtensions: Bool? = nil,
        ttlSeconds: Int? = nil,
        hubOverrideMode: AXProjectRuntimeSurfaceHubOverrideMode? = nil
    ) {
        appModel.setProjectRuntimeSurfacePolicy(
            for: ctx,
            mode: mode,
            allowDeviceTools: allowDeviceTools,
            allowBrowserRuntime: allowBrowserRuntime,
            allowConnectorActions: allowConnectorActions,
            allowExtensions: allowExtensions,
            ttlSeconds: ttlSeconds,
            hubOverrideMode: hubOverrideMode
        )
        reloadProjectConfigSnapshot()
    }

    private func updateProjectGovernedAutoApproveLocalToolCalls(enabled: Bool) {
        appModel.setProjectGovernedAutoApproveLocalToolCalls(for: ctx, enabled: enabled)
        reloadProjectConfigSnapshot()
    }

    private func updateProjectAutomationSelfIteration(
        enabled: Bool? = nil,
        maxAutoRetryDepth: Int? = nil
    ) {
        appModel.setProjectAutomationSelfIteration(
            for: ctx,
            enabled: enabled,
            maxAutoRetryDepth: maxAutoRetryDepth
        )
        reloadProjectConfigSnapshot()
    }

    private func updateProjectRoleModelAssignment(role: AXRole, modelId: String?) {
        let trimmedModelId = modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModelId = trimmedModelId?.isEmpty == false ? trimmedModelId : nil
        let currentModelId = projectModelOverrideId(for: role)
        guard normalizedModelOverrideValue(currentModelId) != normalizedModelOverrideValue(normalizedModelId) else {
            return
        }

        appModel.setProjectRoleModelOverride(
            projectId: routeTruthProjectID,
            role: role,
            modelId: normalizedModelId
        )
        reloadProjectConfigSnapshot()
        projectModelChangeNotice = XTSettingsChangeNoticeBuilder.projectRoleModel(
            projectName: ctx.displayName(registry: appModel.registry),
            role: role,
            modelId: normalizedModelId,
            inheritedModelId: globalModelId(role),
            snapshot: modelInventorySnapshot(),
            executionSnapshot: projectRoleExecutionSnapshot(for: role),
            transportMode: HubAIClient.transportMode().rawValue,
            language: interfaceLanguage
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
            for: ctx,
            mode: mode,
            deviceId: deviceId,
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
        )
        reloadProjectConfigSnapshot()
    }

    private func applyGovernanceTemplate(_ profile: AXProjectGovernanceTemplate) {
        appModel.applyProjectGovernanceTemplate(profile, for: ctx)
        reloadProjectConfigSnapshot()

        let config = governanceConfig
        let resolved = resolvedGovernanceState
        let templatePreview = xtProjectGovernanceTemplatePresentation(
            projectRoot: ctx.root,
            config: config,
            resolved: resolved
        )

        switch profile {
        case .highGovernance:
            if templatePreview.effectiveDeviceAuthorityPosture == .off {
                governanceInlineMessage = "已切到高治理场景（默认 A4 Agent + S3，Extended 40 / Full）。若要真正放开设备级能力，请在执行面与设备绑定细节里完成 runtime ready 和权限就绪。"
                governanceInlineMessageIsError = false
                advancedGovernanceExpanded = true
            } else {
                clearGovernanceInlineMessage()
            }
        case .largeProject:
            governanceInlineMessage = "已切到大型项目场景（默认 A3 + S3，Deep 20 / Deep）。当前更强调 continuity、checkpoint、review 和交付收口。"
            governanceInlineMessageIsError = false
        case .feature:
            governanceInlineMessage = "已切到功能开发场景（默认 A2 + S2，Standard 12 / Balanced）。这是日常 feature 的默认主力模式。"
            governanceInlineMessageIsError = false
        case .prototype:
            governanceInlineMessage = "已切到原型场景（默认 A2 + S1，Floor 8 / Lean）。适合 demo / spike，不默认进入高风险交付面。"
            governanceInlineMessageIsError = false
        case .inception:
            governanceInlineMessage = "已切到产品开局场景（默认 A1 + S2，Deep 20 / Deep）。适合先收敛 scope、architecture 和 work orders。"
            governanceInlineMessageIsError = false
        case .legacyObserve:
            governanceInlineMessage = "已回到旧 Observe 基线（默认 A0 + S0）。当前只围绕观测、建议和记忆读取。"
            governanceInlineMessageIsError = false
        case .custom:
            break
        }
    }

    private func updateExecutionTier(_ tier: AXProjectExecutionTier) {
        let currentSupervisor = governanceConfig.supervisorInterventionTier
        updateProjectGovernance(
            executionTier: tier,
            supervisorInterventionTier: currentSupervisor
        )
        let reviewReference = tier.minimumSafeSupervisorTier
        if currentSupervisor < reviewReference {
            governanceInlineMessage = "\(tier.displayName) 已保留当前 S-Tier \(currentSupervisor.displayName)。这个组合允许保存，但低于 \(reviewReference.displayName) 风险参考线，建议只在你明确接受更弱监督时使用。"
            governanceInlineMessageIsError = false
        } else {
            clearGovernanceInlineMessage()
        }
    }

    private func updateSupervisorTier(_ tier: AXProjectSupervisorInterventionTier) {
        let executionTier = governanceConfig.executionTier
        updateProjectGovernance(supervisorInterventionTier: tier)
        let reviewReference = executionTier.minimumSafeSupervisorTier
        if tier < reviewReference {
            governanceInlineMessage = "\(executionTier.displayName) 当前搭配 \(tier.displayName) 属于高风险监督区：系统允许保存，但 drift、误操作和高风险动作前的纠偏窗口会明显变弱。"
            governanceInlineMessageIsError = false
        } else if tier < executionTier.defaultSupervisorInterventionTier {
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
        pendingOverviewAnchor = request.destination == .overview ? request.overviewAnchor : nil
        if let context = request.context {
            governanceInlineMessage = xtProjectSettingsInlineMessage(
                title: context.title,
                detail: context.detail
            )
            governanceInlineMessageIsError = false
        }

        appModel.clearProjectSettingsFocusRequest(request)
    }

    private func openProjectMemoryControls() {
        governanceInlineMessage = "这里调 Project AI 的 Recent Project Dialogue / Project Context Depth；A-Tier 只提供 memory ceiling。"
        governanceInlineMessageIsError = false
        selectedGovernanceDestination = .overview
        pendingOverviewAnchor = .contextAssembly
    }

    private func openSupervisorMemoryControls() {
        appModel.requestSupervisorSettingsFocus(
            section: .reviewMemoryDepth,
            title: "Supervisor Settings",
            detail: "Review Memory Depth"
        )
        supervisorManager.requestSupervisorWindow(
            sheet: .supervisorSettings,
            reason: "project_governance_review_memory_depth",
            focusConversation: false,
            startConversation: false
        )
    }

    private func processOverviewAnchor(_ proxy: ScrollViewProxy) {
        guard selectedGovernanceDestination == .overview,
              let anchor = pendingOverviewAnchor else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(anchor.rawValue, anchor: .top)
        }
        DispatchQueue.main.async {
            if pendingOverviewAnchor == anchor {
                pendingOverviewAnchor = nil
            }
        }
    }

    private func saveGovernedReadableRoots() {
        let roots = governedReadableRootsDraft
            .split(whereSeparator: { $0.isNewline })
            .map { String($0) }
        appModel.setProjectGovernedReadableRoots(for: ctx, paths: roots)
        reloadProjectConfigSnapshot()
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

                Text(profile.selectableDescription)
                    .font(.caption2)
                    .foregroundStyle(accent)
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
        case .prototype:
            return .mint
        case .feature:
            return .green
        case .largeProject:
            return .blue
        case .highGovernance:
            return .orange
        case .inception:
            return .indigo
        case .legacyObserve:
            return .secondary
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

    private func recentGovernanceInterceptionTimestamp(
        _ createdAt: Double
    ) -> String {
        guard createdAt > 0 else { return "(unknown time)" }
        return runtimeSurfaceTimestampFormatter.string(
            from: Date(timeIntervalSince1970: createdAt)
        )
    }

    private var runtimeSurfaceTimestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}
