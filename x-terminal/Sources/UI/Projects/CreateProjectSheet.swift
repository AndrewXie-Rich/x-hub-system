//
//  CreateProjectSheet.swift
//  XTerminal
//
//  创建项目对话框
//

import SwiftUI

/// 创建项目对话框
struct CreateProjectSheet: View {
    private static let unboundProjectSelection = "__unbound_project__"

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    private let availableModels = XTModelCatalog.projectCreationEntries

    @State private var projectName: String = ""
    @State private var taskDescription: String = ""
    @State private var selectedRegisteredProjectId: String = Self.unboundProjectSelection
    @State private var selectedModel: String = XTModelCatalog.projectCreationEntries.first?.id ?? "claude-opus-4.6"
    @State private var autonomyProfileBaseline: AXProjectAutonomyProfile = .safe
    @State private var executionTier: AXProjectExecutionTier = .a3DeliverAuto
    @State private var supervisorInterventionTier: AXProjectSupervisorInterventionTier = .s3StrategicCoach
    @State private var reviewPolicyMode: AXProjectReviewPolicyMode = .hybrid
    @State private var progressHeartbeatSeconds: Int = AXProjectExecutionTier.a3DeliverAuto.defaultProgressHeartbeatSeconds
    @State private var reviewPulseSeconds: Int = AXProjectExecutionTier.a3DeliverAuto.defaultReviewPulseSeconds
    @State private var brainstormReviewSeconds: Int = AXProjectExecutionTier.a3DeliverAuto.defaultBrainstormReviewSeconds
    @State private var eventDrivenReviewEnabled: Bool = AXProjectExecutionTier.a3DeliverAuto.defaultEventDrivenReviewEnabled
    @State private var priority: Int = 5
    @State private var budget: Double = 10.0
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @State private var governanceInlineMessage: String?
    @State private var governanceInlineMessageIsError: Bool = false
    @State private var advancedGovernanceExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            titleBar

            Divider()

            // 表单内容
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 基本信息
                    basicInfoSection

                    Divider()

                    // 模型选择
                    modelSelectionSection

                    Divider()

                    // 自治总开关
                    autonomyProfileSection

                    Divider()

                    // 高级治理
                    advancedGovernanceSection

                    Divider()

                    // 高级设置
                    advancedSection
                }
                .padding(20)
            }

            Divider()

            // 底部按钮
            bottomBar
        }
        .frame(width: 600, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            ensureDefaultRegisteredProjectSelection()
        }
    }

    // MARK: - Subviews

    private var titleBar: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .foregroundColor(.blue)
                .font(.system(size: 20))

            Text("创建新项目")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基本信息")
                .font(.headline)

            // 项目名称
            VStack(alignment: .leading, spacing: 6) {
                Text("项目名称")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("例如：重构前端代码", text: $projectName)
                    .textFieldStyle(.roundedBorder)
            }

            // 任务描述
            VStack(alignment: .leading, spacing: 6) {
                Text("任务描述")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextEditor(text: $taskDescription)
                    .frame(height: 100)
                    .font(.body)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .help("详细描述你希望 AI 完成的任务")
        }
    }

    private var modelSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("模型选择")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(availableModels, id: \.id) { model in
                    ModelOptionCard(
                        model: model,
                        isSelected: selectedModel == model.id,
                        onSelect: { selectedModel = model.id }
                    )
                }
            }
        }
    }

    private var autonomyProfileSection: some View {
        let governancePresentation = draftGovernancePresentation
        let switchboard = draftSwitchboardPresentation

        return VStack(alignment: .leading, spacing: 12) {
            Text("Governance Presets")
                .font(.headline)

            Text("这是创建项目时的产品级快捷预设。需要单独调 execution/supervisor 档位、review cadence 或绑定关系时，再展开下方 Governance Details。")
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
                Text("当前处于自定义：你已经偏离快捷预设，创建后系统会按实际治理参数运行。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let governanceInlineMessage, !governanceInlineMessage.isEmpty {
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
                    title: "当前预设",
                    profile: switchboard.configuredProfile,
                    summary: switchboard.configuredProfileSummary
                )

                autonomyProfileStateCard(
                    title: "生效预演",
                    profile: switchboard.effectiveProfile,
                    summary: switchboard.effectiveProfileSummary
                )
            }

            if switchboard.hasConfiguredEffectiveDrift {
                Text("这里只展示创建前的 effective 预演。真正运行时仍继续受 trusted automation、grant、TTL、kill-switch 和是否绑定真实 project 共同约束。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                autonomyProfileDimensionCard(
                    title: "设备执行面",
                    configuredTitle: switchboard.configuredDeviceAuthorityPosture.displayName,
                    configuredDetail: switchboard.configuredDeviceAuthorityDetail,
                    effectiveTitle: switchboard.effectiveDeviceAuthorityPosture.displayName,
                    effectiveDetail: switchboard.effectiveDeviceAuthorityDetail
                )

                autonomyProfileDimensionCard(
                    title: "Supervisor 视角",
                    configuredTitle: switchboard.configuredSupervisorScope.displayName,
                    configuredDetail: switchboard.configuredSupervisorScopeDetail,
                    effectiveTitle: switchboard.effectiveSupervisorScope.displayName,
                    effectiveDetail: switchboard.effectiveSupervisorScopeDetail
                )

                autonomyProfileDimensionCard(
                    title: "Hub 授权",
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
                Text("effective_runtime_notes: \(switchboard.effectiveDeviationReasons.joined(separator: " · "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text(switchboard.runtimeSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var advancedGovernanceSection: some View {
        let presentation = draftGovernancePresentation

        return DisclosureGroup(
            isExpanded: $advancedGovernanceExpanded,
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("这里保留治理绑定、execution/supervisor tier 和 review cadence 细项。只有需要偏离快捷预设时，才建议展开调整。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("治理绑定")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Picker("", selection: $selectedRegisteredProjectId) {
                            Text("不绑定真实 Project").tag(Self.unboundProjectSelection)

                            ForEach(bindableProjects, id: \.projectId) { entry in
                                Text("\(entry.displayName) · \(String(entry.projectId.suffix(8)))")
                                    .tag(entry.projectId)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 320, alignment: .leading)

                        if let selectedBoundProject {
                            Text("治理 activity 会直接读取 \(selectedBoundProject.displayName) 的 review / guidance / schedule 记录。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if bindableProjects.isEmpty {
                            Text("当前 registry 里还没有可绑定的 project。先导入真实 project，这里才能接到 supervisor 的上下文记忆和治理记录。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("未绑定时，这个多项目卡片只保存治理档位；详情页不会显示真实的 review / guidance 时间线。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ProjectGovernanceBadge(presentation: presentation)
                    ProjectGovernanceInspector(presentation: presentation)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Execution Tier")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 120, alignment: .leading)

                        Picker("", selection: Binding(
                            get: { executionTier },
                            set: { applyExecutionTier($0) }
                        )) {
                            ForEach(AXProjectExecutionTier.allCases, id: \.self) { tier in
                                Text(tier.displayName).tag(tier)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 280, alignment: .leading)

                        Spacer()
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Supervisor Tier")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 120, alignment: .leading)

                        Picker("", selection: Binding(
                            get: { supervisorInterventionTier },
                            set: { applySupervisorTier($0) }
                        )) {
                            ForEach(AXProjectSupervisorInterventionTier.allCases, id: \.self) { tier in
                                Text(tier.displayName).tag(tier)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 280, alignment: .leading)

                        Spacer()
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Review Policy")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 120, alignment: .leading)

                        Picker("", selection: Binding(
                            get: { reviewPolicyMode },
                            set: {
                                reviewPolicyMode = $0
                                clearGovernanceInlineMessage()
                            }
                        )) {
                            ForEach(AXProjectReviewPolicyMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 280, alignment: .leading)

                        Spacer()
                    }

                    Stepper(
                        value: minutesBinding(
                            get: { progressHeartbeatSeconds },
                            set: {
                                progressHeartbeatSeconds = $0
                                clearGovernanceInlineMessage()
                            }
                        ),
                        in: 1...240,
                        step: 5
                    ) {
                        Text("Heartbeat: \(governanceDurationLabel(progressHeartbeatSeconds))")
                    }

                    Stepper(
                        value: minutesBinding(
                            get: { reviewPulseSeconds },
                            set: {
                                reviewPulseSeconds = $0
                                clearGovernanceInlineMessage()
                            },
                            allowsOff: true
                        ),
                        in: 0...240,
                        step: 5
                    ) {
                        Text("Review Pulse: \(governanceDurationLabel(reviewPulseSeconds))")
                    }
                    .disabled(reviewPolicyMode == .off || reviewPolicyMode == .milestoneOnly)

                    Stepper(
                        value: minutesBinding(
                            get: { brainstormReviewSeconds },
                            set: {
                                brainstormReviewSeconds = $0
                                clearGovernanceInlineMessage()
                            },
                            allowsOff: true
                        ),
                        in: 0...240,
                        step: 5
                    ) {
                        Text("Brainstorm Review: \(governanceDurationLabel(brainstormReviewSeconds))")
                    }
                    .disabled(reviewPolicyMode == .off || reviewPolicyMode == .milestoneOnly)

                    Toggle(
                        "Enable event-driven review",
                        isOn: Binding(
                            get: { eventDrivenReviewEnabled },
                            set: {
                                eventDrivenReviewEnabled = $0
                                clearGovernanceInlineMessage()
                            }
                        )
                    )
                        .disabled(reviewPolicyMode == .off)

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("safe-point guidance: \(presentation.guidanceSummary) · \(presentation.guidanceAckSummary)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
                .padding(.top, 4)
            },
            label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Governance Details")
                        .font(.headline)
                    Text("当你需要偏离保守 / 安全 / 高自治预设，或绑定真实 Project 时，再展开这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        )
        .tint(.primary)
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("高级设置")
                .font(.headline)

            // 优先级
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("优先级")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(priority)")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }

                Slider(value: Binding(
                    get: { Double(priority) },
                    set: { priority = Int($0) }
                ), in: 1...10, step: 1)

                HStack {
                    Text("低")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("高")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 预算
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("预算上限")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("$\(String(format: "%.2f", budget))")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }

                Slider(value: $budget, in: 1...100, step: 1)

                HStack {
                    Text("$1")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("$100")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.escape)

            Button("创建项目") {
                createProject()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .disabled(!isFormValid || isCreating)
        }
        .padding()
    }

    // MARK: - Computed Properties

    private var isFormValid: Bool {
        !projectName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !taskDescription.trimmingCharacters(in: .whitespaces).isEmpty &&
        draftGovernancePresentation.invalidMessages.isEmpty
    }

    private var draftGovernancePresentation: ProjectGovernancePresentation {
        ProjectGovernancePresentation(
            resolved: draftResolvedGovernance
        )
    }

    private var draftSwitchboardPresentation: AXProjectAutonomySwitchboardPresentation {
        xtProjectAutonomySwitchboardPresentation(
            projectRoot: draftProjectRoot,
            config: draftAutonomyConfig,
            resolved: draftResolvedGovernance
        )
    }

    private var bindableProjects: [AXProjectEntry] {
        appModel.sortedProjects
    }

    private var selectedBoundProject: AXProjectEntry? {
        guard let projectId = normalizedRegisteredProjectId else { return nil }
        return bindableProjects.first(where: { $0.projectId == projectId })
    }

    private var normalizedRegisteredProjectId: String? {
        let selected = selectedRegisteredProjectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selected != Self.unboundProjectSelection else { return nil }
        guard bindableProjects.contains(where: { $0.projectId == selected }) else { return nil }
        return selected
    }

    private var draftProjectRoot: URL {
        if let selectedBoundProject {
            return URL(fileURLWithPath: selectedBoundProject.rootPath, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private var draftAutonomyConfig: AXProjectConfig {
        xtAutonomySwitchboardDraftConfig(
            projectRoot: draftProjectRoot,
            baselineProfile: autonomyProfileBaseline,
            executionTier: executionTier,
            supervisorInterventionTier: supervisorInterventionTier,
            reviewPolicyMode: reviewPolicyMode,
            progressHeartbeatSeconds: progressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            eventDrivenReviewEnabled: eventDrivenReviewEnabled
        )
    }

    private var draftResolvedGovernance: AXProjectResolvedGovernanceState {
        xtResolveProjectGovernance(
            projectRoot: draftProjectRoot,
            config: draftAutonomyConfig
        )
    }

    // MARK: - Actions

    private func ensureDefaultRegisteredProjectSelection() {
        guard selectedRegisteredProjectId == Self.unboundProjectSelection else { return }
        guard let currentProjectId = appModel.selectedProjectId,
              currentProjectId != AXProjectRegistry.globalHomeId,
              bindableProjects.contains(where: { $0.projectId == currentProjectId }) else {
            return
        }

        selectedRegisteredProjectId = currentProjectId
    }

    private func applyAutonomyProfile(_ profile: AXProjectAutonomyProfile) {
        let config = AXProjectConfig
            .default(forProjectRoot: draftProjectRoot)
            .settingAutonomySwitchboardProfile(profile, projectRoot: draftProjectRoot)

        autonomyProfileBaseline = profile
        executionTier = config.executionTier
        supervisorInterventionTier = config.supervisorInterventionTier
        reviewPolicyMode = config.reviewPolicyMode
        progressHeartbeatSeconds = config.progressHeartbeatSeconds
        reviewPulseSeconds = config.reviewPulseSeconds
        brainstormReviewSeconds = config.brainstormReviewSeconds
        eventDrivenReviewEnabled = config.eventDrivenReviewEnabled

        switch profile {
        case .fullAutonomy:
            governanceInlineMessage = "已切到高自治预设（A4 + S3 默认组合）。创建后如果要真正放开设备级执行面，仍需要绑定真实 project 并完成 trusted automation 与权限就绪。"
            governanceInlineMessageIsError = false
            advancedGovernanceExpanded = true
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

    private func applyExecutionTier(_ tier: AXProjectExecutionTier) {
        let currentBundle = AXProjectGovernanceBundle(
            executionTier: executionTier,
            supervisorInterventionTier: supervisorInterventionTier,
            reviewPolicyMode: reviewPolicyMode,
            schedule: AXProjectGovernanceSchedule(
                progressHeartbeatSeconds: progressHeartbeatSeconds,
                reviewPulseSeconds: reviewPulseSeconds,
                brainstormReviewSeconds: brainstormReviewSeconds,
                eventDrivenReviewEnabled: eventDrivenReviewEnabled,
                eventReviewTriggers: executionTier.defaultEventReviewTriggers
            )
        )
        let updatedBundle = currentBundle.applyingExecutionTierPreservingReviewConfiguration(tier)
        let previousSupervisor = supervisorInterventionTier

        executionTier = updatedBundle.executionTier
        supervisorInterventionTier = updatedBundle.supervisorInterventionTier

        if updatedBundle.supervisorInterventionTier != previousSupervisor {
            governanceInlineMessage = "\(tier.displayName) 至少需要 \(tier.minimumSafeSupervisorTier.displayName)，已自动抬升 supervisor 安全下限。"
            governanceInlineMessageIsError = false
        } else {
            clearGovernanceInlineMessage()
        }
    }

    private func applySupervisorTier(_ tier: AXProjectSupervisorInterventionTier) {
        let minimumSafe = executionTier.minimumSafeSupervisorTier
        guard tier >= minimumSafe else {
            governanceInlineMessage = "\(executionTier.displayName) 不能低于 \(minimumSafe.displayName)。"
            governanceInlineMessageIsError = true
            return
        }

        supervisorInterventionTier = tier
        if tier < executionTier.defaultSupervisorInterventionTier {
            governanceInlineMessage = "\(executionTier.displayName) 推荐 \(executionTier.defaultSupervisorInterventionTier.displayName) 及以上；当前组合允许，但会放松 review 纠偏强度。"
            governanceInlineMessageIsError = false
        } else {
            clearGovernanceInlineMessage()
        }
    }

    private func clearGovernanceInlineMessage() {
        governanceInlineMessage = nil
        governanceInlineMessageIsError = false
    }

    private func minutesBinding(
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

    private func createProject() {
        guard isFormValid else { return }

        isCreating = true
        errorMessage = nil

        Task {
            let project = await appModel.createMultiProject(
                name: projectName.trimmingCharacters(in: .whitespaces),
                taskDescription: taskDescription.trimmingCharacters(in: .whitespaces),
                modelName: selectedModel,
                registeredProjectId: normalizedRegisteredProjectId,
                executionTier: executionTier,
                supervisorInterventionTier: supervisorInterventionTier,
                reviewPolicyMode: reviewPolicyMode,
                progressHeartbeatSeconds: progressHeartbeatSeconds,
                reviewPulseSeconds: reviewPulseSeconds,
                brainstormReviewSeconds: brainstormReviewSeconds,
                eventDrivenReviewEnabled: eventDrivenReviewEnabled
            )

            // 设置优先级和预算
            project.priority = priority
            project.budget.daily = budget

            await MainActor.run {
                isCreating = false
                dismiss()
            }
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

            Text("当前预设")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text(configuredTitle)
                .font(.subheadline.weight(.semibold))
            Text(configuredDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("生效预演")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text(effectiveTitle)
                .font(.subheadline.weight(.semibold))
            Text(effectiveDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
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
}

/// 模型选项卡片
struct ModelOptionCard: View {
    let model: XTModelCatalogEntry
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                // 选择指示器
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        if let badge = model.badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(model.badgeColor ?? .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill((model.badgeColor ?? .secondary).opacity(0.12))
                                )
                        }
                    }

                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ModelCapabilityStrip(model: model.modelInfo, limit: 5)
                }

                Spacer()

                // 模型图标
                Image(systemName: model.type == .local ? "desktopcomputer" : "cloud")
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct CreateProjectSheet_Previews: PreviewProvider {
    static var previews: some View {
        CreateProjectSheet()
            .environmentObject(AppModel())
    }
}
#endif
