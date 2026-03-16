import SwiftUI

struct ProjectSettingsView: View {
    let ctx: AXProjectContext

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var modelManager = HubModelManager.shared
    @State private var trustedAutomationDeviceIdDraft: String = ""
    @State private var governedReadableRootsDraft: String = ""
    @State private var governanceInlineMessage: String = ""
    @State private var governanceInlineMessageIsError = false
    @State private var modelPickerRole: AXRole?
    @State private var advancedGovernanceExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Project Settings")
                        .font(.headline)
                    Spacer()
                    Button("Close") { dismiss() }
                }

                Text(ctx.displayName(registry: appModel.registry))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                latestUIReviewSection
                GroupBox("Per-Project Model Routing") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("每个角色可选择不同模型；留空 = 使用全局 Settings。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

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

                hubMemorySection
                automationSelfIterateSection
                autonomyProfileSection
                ProjectGovernanceActivityView(ctx: ctx)
                advancedGovernanceSection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            modelManager.setAppModel(appModel)
            trustedAutomationDeviceIdDraft = appModel.projectConfig?.trustedAutomationDeviceId ?? ""
            governedReadableRootsDraft = governedReadableRootsText(appModel.projectConfig?.governedReadableRoots ?? [])
            Task {
                await modelManager.fetchModels()
            }
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
    }

    private func projectModelOverrideId(for role: AXRole) -> String? {
        let raw = appModel.projectConfig?.modelOverride(for: role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var latestUIReviewSection: some View {
        GroupBox("Latest UI Review") {
            ProjectUIReviewWorkspaceView(
                ctx: ctx,
                emptyTitle: "暂无浏览器 UI review",
                emptyMessage: "当前项目还没有浏览器 UI review。执行一次 `device.browser.control snapshot` 后，系统会在这里展示最近一次受治理 UI 观察结果。",
                helperText: "这条 review 会被 project AI / supervisor memory / resume brief 共同消费。它的作用不是替代人工验收，而是让系统先判断“当前页面是否真的可执行”。"
            )
            .padding(8)
        }
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
                    appModel.setProjectRoleModel(role: role, modelId: modelId)
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

    private var autonomyProfileSection: some View {
        let config = appModel.projectConfig ?? .default(forProjectRoot: ctx.root)
        let resolved = appModel.resolvedProjectGovernance(config: config)
        let governancePresentation = ProjectGovernancePresentation(resolved: resolved)
        let switchboard = xtProjectAutonomySwitchboardPresentation(
            projectRoot: ctx.root,
            config: config,
            resolved: resolved
        )

        return GroupBox("Governance Presets") {
            VStack(alignment: .leading, spacing: 12) {
                Text("这是 A-tier / S-tier / review cadence 的快捷预设。需要单独调执行权限、supervisor 介入、TTL、trusted automation 或 read roots 时，再展开下方治理设置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 10) {
                    ForEach(AXProjectAutonomyProfile.selectableProfiles, id: \.self) { profile in
                        autonomyProfileButton(
                            profile,
                            isSelected: switchboard.configuredProfile == profile
                        )
                    }
                }

                if switchboard.configuredProfile == .custom {
                    Text("当前处于自定义：你已经偏离快捷预设，系统会以实际 A-tier / S-tier / review 配置为准。")
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
                    showCallout: true
                )

                HStack(alignment: .top, spacing: 12) {
                    autonomyProfileStateCard(
                        title: "Configured",
                        profile: switchboard.configuredProfile,
                        summary: switchboard.configuredProfileSummary
                    )

                    autonomyProfileStateCard(
                        title: "Effective",
                        profile: switchboard.effectiveProfile,
                        summary: switchboard.effectiveProfileSummary
                    )
                }

                if switchboard.hasConfiguredEffectiveDrift {
                    Text("configured 与 effective 当前不完全一致。真正放行动作仍继续受 runtime surface TTL、clamp、trusted automation、grant 和 kill-switch 共同约束。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 12) {
                    autonomyProfileDimensionCard(
                        title: "Project Device Authority",
                        configuredTitle: switchboard.configuredDeviceAuthorityPosture.displayName,
                        configuredDetail: switchboard.configuredDeviceAuthorityDetail,
                        effectiveTitle: switchboard.effectiveDeviceAuthorityPosture.displayName,
                        effectiveDetail: switchboard.effectiveDeviceAuthorityDetail
                    )

                    autonomyProfileDimensionCard(
                        title: "Supervisor Scope",
                        configuredTitle: switchboard.configuredSupervisorScope.displayName,
                        configuredDetail: switchboard.configuredSupervisorScopeDetail,
                        effectiveTitle: switchboard.effectiveSupervisorScope.displayName,
                        effectiveDetail: switchboard.effectiveSupervisorScopeDetail
                    )

                    autonomyProfileDimensionCard(
                        title: "Hub Grant",
                        configuredTitle: switchboard.configuredGrantPosture.displayName,
                        configuredDetail: switchboard.configuredGrantDetail,
                        effectiveTitle: switchboard.effectiveGrantPosture.displayName,
                        effectiveDetail: switchboard.effectiveGrantDetail
                    )
                }

                if !switchboard.configuredDeviationReasons.isEmpty {
                    Text("custom_reasons: \(switchboard.configuredDeviationReasons.joined(separator: " · "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if !switchboard.effectiveDeviationReasons.isEmpty {
                    Text("effective_notes: \(switchboard.effectiveDeviationReasons.joined(separator: " · "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text(switchboard.runtimeSummary)
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

        return GroupBox("Hub Memory Governance") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "Prefer Hub memory for this project",
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

    private var trustedAutomationSection: some View {
        let config = appModel.projectConfig ?? .default(forProjectRoot: ctx.root)
        let effective = appModel.resolvedProjectAutonomyPolicy(config: config)
        let readiness = AXTrustedAutomationPermissionOwnerReadiness.current()
        let status = config.trustedAutomationStatus(forProjectRoot: ctx.root, permissionReadiness: readiness)
        let expectedHash = xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
        let configuredAutoApprove = config.governedAutoApproveLocalToolCalls
        let effectiveAutoApprove = xtProjectGovernedAutoApprovalEnabled(
            projectRoot: ctx.root,
            config: config,
            effectiveAutonomy: effective
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

                Text("这是一条 project 级设备执行绑定，不等于把整个 X-Terminal 永久全开；高自治预设也不等于自动拥有全部设备权限。")
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

    private var governanceSection: some View {
        let config = appModel.projectConfig ?? .default(forProjectRoot: ctx.root)
        let resolved = appModel.resolvedProjectGovernance(config: config)
        let presentation = ProjectGovernancePresentation(resolved: resolved)
        let effective = resolved.effectiveAutonomy
        let configuredSurfaceText = configuredAutonomySurfaceText(config)
        let effectiveSurfaceText = effective.allowedSurfaceLabels.isEmpty ? "(none)" : effective.allowedSurfaceLabels.joined(separator: ", ")
        let updatedAtText = config.autonomyUpdatedAtDate.map { autonomyTimestampFormatter.string(from: $0) } ?? "(never armed)"
        let hubOverrideUpdatedAtText: String = {
            guard effective.remoteOverrideUpdatedAtMs > 0 else { return "(none)" }
            let date = Date(timeIntervalSince1970: TimeInterval(effective.remoteOverrideUpdatedAtMs) / 1000.0)
            return autonomyTimestampFormatter.string(from: date)
        }()
        let reviewMode = config.reviewPolicyMode

        return GroupBox("Project Governance") {
            VStack(alignment: .leading, spacing: 12) {
                ProjectGovernanceBadge(presentation: presentation)
                ProjectGovernanceInspector(presentation: presentation)

                if !governanceInlineMessage.isEmpty {
                    Text(governanceInlineMessage)
                        .font(.caption)
                        .foregroundStyle(governanceInlineMessageIsError ? .red : .orange)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Execution Tier")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 140, alignment: .leading)

                    Picker(
                        "",
                        selection: Binding(
                            get: { appModel.projectConfig?.executionTier ?? .a0Observe },
                            set: { updateExecutionTier($0) }
                        )
                    ) {
                        ForEach(AXProjectExecutionTier.allCases, id: \.self) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 260, alignment: .leading)

                    Spacer()

                    Text("运行时 Surface: \(config.autonomyMode.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Supervisor Tier")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 140, alignment: .leading)

                    Picker(
                        "",
                        selection: Binding(
                            get: { appModel.projectConfig?.supervisorInterventionTier ?? .s0SilentAudit },
                            set: { updateSupervisorTier($0) }
                        )
                    ) {
                        ForEach(AXProjectSupervisorInterventionTier.allCases, id: \.self) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 260, alignment: .leading)

                    Spacer()

                        Text("最低安全监督：\(config.executionTier.minimumSafeSupervisorTier.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Review Policy")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 140, alignment: .leading)

                    Picker(
                        "",
                        selection: Binding(
                            get: { appModel.projectConfig?.reviewPolicyMode ?? .milestoneOnly },
                            set: { appModel.setProjectGovernance(reviewPolicyMode: $0) }
                        )
                    ) {
                        ForEach(AXProjectReviewPolicyMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 260, alignment: .leading)

                    Spacer()

                    Text("来源: \(presentation.compatSourceLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Stepper(
                    value: governanceMinutesBinding(
                        get: { appModel.projectConfig?.progressHeartbeatSeconds ?? config.progressHeartbeatSeconds },
                        set: { appModel.setProjectGovernance(progressHeartbeatSeconds: $0) }
                    ),
                    in: 1...240,
                    step: 5
                ) {
                    Text("Heartbeat: \(governanceDurationLabel(config.progressHeartbeatSeconds))")
                }

                Stepper(
                    value: governanceMinutesBinding(
                        get: { appModel.projectConfig?.reviewPulseSeconds ?? config.reviewPulseSeconds },
                        set: { appModel.setProjectGovernance(reviewPulseSeconds: $0) },
                        allowsOff: true
                    ),
                    in: 0...240,
                    step: 5,
                    onEditingChanged: { _ in }
                ) {
                    Text("Review Pulse: \(governanceDurationLabel(config.reviewPulseSeconds))")
                }
                .disabled(reviewMode == .off || reviewMode == .milestoneOnly)

                Stepper(
                    value: governanceMinutesBinding(
                        get: { appModel.projectConfig?.brainstormReviewSeconds ?? config.brainstormReviewSeconds },
                        set: { appModel.setProjectGovernance(brainstormReviewSeconds: $0) },
                        allowsOff: true
                    ),
                    in: 0...240,
                    step: 5,
                    onEditingChanged: { _ in }
                ) {
                    Text("Brainstorm Review: \(governanceDurationLabel(config.brainstormReviewSeconds))")
                }
                .disabled(reviewMode == .off || reviewMode == .milestoneOnly)

                Toggle(
                    "Enable event-driven review",
                    isOn: Binding(
                        get: { appModel.projectConfig?.eventDrivenReviewEnabled ?? config.eventDrivenReviewEnabled },
                        set: { appModel.setProjectGovernance(eventDrivenReviewEnabled: $0) }
                    )
                )
                .toggleStyle(.switch)
                .disabled(reviewMode == .off)

                Text("Guidance 注入：\(presentation.guidanceSummary) · \(presentation.guidanceAckSummary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("事件触发条件：\(config.eventReviewTriggers.isEmpty ? "(none)" : config.eventReviewTriggers.map(\.displayName).joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Divider()

                Stepper(
                    value: Binding(
                        get: { max(5, (appModel.projectConfig?.autonomyTTLSeconds ?? 3600) / 60) },
                        set: { appModel.setProjectAutonomyPolicy(ttlSeconds: max(5, $0) * 60) }
                    ),
                    in: 5...1440,
                    step: 5
                ) {
                    Text("Surface TTL: \((config.autonomyTTLSeconds / 60)) min")
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Local Surface Clamp")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 140, alignment: .leading)

                    Picker(
                        "",
                        selection: Binding(
                            get: { appModel.projectConfig?.autonomyHubOverrideMode ?? AXProjectAutonomyHubOverrideMode.none },
                            set: { appModel.setProjectAutonomyPolicy(hubOverrideMode: $0) }
                        )
                    ) {
                        ForEach(AXProjectAutonomyHubOverrideMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 260, alignment: .leading)

                    Spacer()
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Hub Surface Clamp")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 140, alignment: .leading)

                    Text(effective.remoteOverrideMode.displayName)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)

                    Spacer()
                }

                Text("预设执行面：\(configuredSurfaceText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("生效执行面：\(effectiveSurfaceText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Surface TTL 剩余：\(autonomyRemainingText(config: config, effective: effective)) · 最近更新时间：\(updatedAtText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Hub clamp 来源：\(effective.remoteOverrideSource.isEmpty ? "(none)" : effective.remoteOverrideSource) · Hub clamp 更新时间：\(hubOverrideUpdatedAtText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("执行档位会同步默认执行面，但真正放行动作仍继续受 TTL、clamp、设备执行绑定、权限宿主和 kill-switch 共同约束。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(autonomyExplanation(config: config, effective: effective))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var advancedGovernanceSection: some View {
        GroupBox("Advanced Governance") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("这里保留执行档位、监督档位、复盘节奏、设备执行绑定、可读目录和本地自动审批细项。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("动这些细项后，顶部主档会自动显示为 `自定义`。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(advancedGovernanceExpanded ? "隐藏细节" : "显示细节") {
                        advancedGovernanceExpanded.toggle()
                    }
                }

                if advancedGovernanceExpanded {
                    governanceSection
                    trustedAutomationSection
                }
            }
            .padding(8)
        }
    }

    private var automationSelfIterateSection: some View {
        let enabled = appModel.projectConfig?.automationSelfIterateEnabled ?? false
        let maxDepth = appModel.projectConfig?.automationMaxAutoRetryDepth ?? 2
        let recipeRef = appModel.projectConfig?.activeAutomationRecipeRef.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return GroupBox("Automation Self-Iteration") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "Enable bounded self-iterate auto retry",
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
                    Text("Max Auto Retry Depth: \(maxDepth)")
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

    private func saveTrustedAutomationBinding(armed: Bool) {
        let deviceId = trustedAutomationDeviceIdDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode: AXProjectAutomationMode = armed ? .trustedAutomation : .standard
        appModel.setProjectTrustedAutomationBinding(
            mode: mode,
            deviceId: deviceId,
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
        )
    }

    private func applyAutonomyProfile(_ profile: AXProjectAutonomyProfile) {
        appModel.applyProjectAutonomyProfile(profile)

        let config = appModel.projectConfig ?? .default(forProjectRoot: ctx.root)
        let resolved = appModel.resolvedProjectGovernance(config: config)
        let switchboard = xtProjectAutonomySwitchboardPresentation(
            projectRoot: ctx.root,
            config: config,
            resolved: resolved
        )

        switch profile {
        case .fullAutonomy:
            if switchboard.effectiveDeviceAuthorityPosture == .off {
                governanceInlineMessage = "已切到高自治预设（A4 + S3 默认组合）。若要真正放开设备级能力，请在治理细节里完成设备绑定和权限就绪。"
                governanceInlineMessageIsError = false
                advancedGovernanceExpanded = true
            } else {
                clearGovernanceInlineMessage()
            }
        case .safe:
            governanceInlineMessage = "已切到推荐预设（A3 + S3 默认组合）。project 会优先持续推进，但高风险动作仍继续受 grant 与 clamp 约束。"
            governanceInlineMessageIsError = false
        case .conservative:
            governanceInlineMessage = "已切到保守预设（A1 + S2 默认组合）。当前更偏向理解、规划与审阅，不主动放大执行面。"
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

    private func governanceMinutesBinding(
        get: @escaping () -> Int,
        set: @escaping (Int) -> Void,
        allowsOff: Bool = false
    ) -> Binding<Int> {
        Binding(
            get: {
                let seconds = max(0, get())
                if seconds == 0 && allowsOff {
                    return 0
                }
                return max(1, seconds / 60)
            },
            set: { minutes in
                if allowsOff && minutes <= 0 {
                    set(0)
                } else {
                    set(max(1, minutes) * 60)
                }
            }
        )
    }

    private func clearGovernanceInlineMessage() {
        governanceInlineMessage = ""
        governanceInlineMessageIsError = false
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

    private func autonomyProfileButton(
        _ profile: AXProjectAutonomyProfile,
        isSelected: Bool
    ) -> some View {
        let accent = autonomyProfileAccent(profile)

        return Button {
            applyAutonomyProfile(profile)
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

    private func autonomyProfileStateCard(
        title: String,
        profile: AXProjectAutonomyProfile,
        summary: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(profile.displayName)
                .font(.headline)
                .foregroundStyle(autonomyProfileAccent(profile))

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(autonomyProfileAccent(profile).opacity(0.08))
        )
    }

    private func autonomyProfileDimensionCard(
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

            Text("Configured")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text(configuredTitle)
                .font(.subheadline.weight(.semibold))
            Text(configuredDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Effective")
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

    private func autonomyProfileAccent(_ profile: AXProjectAutonomyProfile) -> Color {
        switch profile {
        case .conservative:
            return .secondary
        case .safe:
            return .green
        case .fullAutonomy:
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

    private func configuredAutonomySurfaceText(_ config: AXProjectConfig) -> String {
        let labels = config.configuredAutonomySurfaceLabels
        return labels.isEmpty ? "(none)" : labels.joined(separator: ", ")
    }

    private func governedReadableRootsText(_ roots: [String]) -> String {
        roots.joined(separator: "\n")
    }

    private func effectiveGovernedReadableRootsText(
        config: AXProjectConfig,
        effective: AXProjectAutonomyEffectivePolicy
    ) -> String {
        let authorityOn = xtProjectGovernedDeviceAuthorityEnabled(
            projectRoot: ctx.root,
            config: config,
            effectiveAutonomy: effective
        )
        var roots = [PathGuard.resolve(ctx.root).path]
        if authorityOn {
            roots.append(contentsOf: config.governedReadableRoots)
        }
        return roots.joined(separator: ", ")
    }

    private func autonomyRemainingText(
        config: AXProjectConfig,
        effective: AXProjectAutonomyEffectivePolicy
    ) -> String {
        if effective.killSwitchEngaged {
            return "kill_switch"
        }
        if effective.expired {
            return "expired"
        }
        if config.autonomyMode == .manual {
            return "n/a"
        }
        let minutes = max(1, (effective.remainingSeconds + 59) / 60)
        return "\(minutes)m"
    }

    private func autonomyExplanation(
        config: AXProjectConfig,
        effective: AXProjectAutonomyEffectivePolicy
    ) -> String {
        if let clamp = xtAutonomyClampExplanation(
            effective: effective,
            style: .uiChinese
        ) {
            return clamp.summary
        }
        return xtRuntimeSurfaceExplanation(mode: effective.effectiveMode, style: .uiChinese)
    }

    private var autonomyTimestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}
