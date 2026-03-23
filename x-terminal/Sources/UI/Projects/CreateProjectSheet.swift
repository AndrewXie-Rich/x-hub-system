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
    @State private var governanceTemplateBaseline: AXProjectGovernanceTemplate = .safe
    @State private var executionTier: AXProjectExecutionTier = .a3DeliverAuto
    @State private var supervisorInterventionTier: AXProjectSupervisorInterventionTier = .s3StrategicCoach
    @State private var reviewPolicyMode: AXProjectReviewPolicyMode = .hybrid
    @State private var progressHeartbeatSeconds: Int = AXProjectExecutionTier.a3DeliverAuto.defaultProgressHeartbeatSeconds
    @State private var reviewPulseSeconds: Int = AXProjectExecutionTier.a3DeliverAuto.defaultReviewPulseSeconds
    @State private var brainstormReviewSeconds: Int = AXProjectExecutionTier.a3DeliverAuto.defaultBrainstormReviewSeconds
    @State private var eventDrivenReviewEnabled: Bool = AXProjectExecutionTier.a3DeliverAuto.defaultEventDrivenReviewEnabled
    @State private var eventReviewTriggers: [AXProjectReviewTrigger] = AXProjectExecutionTier.a3DeliverAuto.defaultEventReviewTriggers
    @State private var selectedGovernanceDestination: XTProjectGovernanceDestination = .executionTier
    @State private var priority: Int = 5
    @State private var budget: Double = 10.0
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @State private var governanceInlineMessage: String?
    @State private var governanceInlineMessageIsError: Bool = false

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
                    governanceTemplateSection

                    Divider()

                    // 治理组合器
                    governanceComposerSection

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

    private var governanceTemplateSection: some View {
        let governancePresentation = draftGovernancePresentation
        let templatePreview = draftGovernanceTemplatePreview

        return VStack(alignment: .leading, spacing: 12) {
            Text("治理模板（可选）")
                .font(.headline)

            Text("这些模板只是创建项目时的快捷映射。真正生效的 execution/supervisor 档位、review cadence、绑定关系与运行时收束，仍以下方 Governance Composer 为准。")
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
                Text("当前模板已偏离默认映射：创建后系统会按实际治理参数运行。")
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
                    title: "运行时预演",
                    profile: templatePreview.effectiveProfile,
                    summary: templatePreview.effectiveProfileSummary
                )
            }

            if templatePreview.hasConfiguredEffectiveDrift {
                Text("这里只展示创建前的运行时预演。真正运行时仍继续受 trusted automation、grant、TTL、kill-switch 和是否绑定真实 project 共同约束。")
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
        }
    }

    private var governanceComposerSection: some View {
        let presentation = draftGovernancePresentation

        return VStack(alignment: .leading, spacing: 12) {
            Text("Governance Composer")
                .font(.headline)

            Text("创建阶段也保持三根独立治理拨盘：Execution Tier 决定能做什么，Supervisor Tier 决定盯多深，Heartbeat & Review 决定多久做一次审查。")
                .font(.caption)
                .foregroundStyle(.secondary)

            governanceBindingSection

            ProjectGovernanceCompactSummaryView(
                presentation: presentation,
                showCallout: true,
                onExecutionTierTap: { selectedGovernanceDestination = .executionTier },
                onSupervisorTierTap: { selectedGovernanceDestination = .supervisorTier },
                onReviewCadenceTap: { selectedGovernanceDestination = .heartbeatReview },
                onStatusTap: { selectedGovernanceDestination = .overview },
                onCalloutTap: { selectedGovernanceDestination = .overview }
            )

            governanceDestinationCards

            selectedGovernanceEditor
        }
    }

    private var governanceBindingSection: some View {
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
                Text("当前会直接读取 \(selectedBoundProject.displayName) 的治理活动。Heartbeat & Review 子页会显示真实的审查 / 指导 / 调度时间线。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if bindableProjects.isEmpty {
                Text("当前 registry 里还没有可绑定的 project。先导入真实 project，这里才能接到 supervisor 的上下文记忆和治理记录。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("未绑定时，这个多项目卡片只保存治理草稿；Heartbeat & Review 子页不会显示真实的审查 / 指导时间线。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var governanceDestinationCards: some View {
        let composer = governanceComposerPresentation

        return HStack(alignment: .top, spacing: 10) {
            ForEach(composer.cards, id: \.destination) { card in
                governanceDestinationCard(card)
            }
        }
    }

    private func governanceDestinationCard(
        _ card: ProjectGovernanceDestinationCardPresentation
    ) -> some View {
        let accent = governanceCardAccent(card.accentTone)
        return Button {
            selectedGovernanceDestination = card.destination
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(card.heading)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(card.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(card.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(accent.opacity(card.isSelected ? 0.14 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        card.isSelected ? accent : Color.secondary.opacity(0.18),
                        lineWidth: card.isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var selectedGovernanceEditor: some View {
        Group {
            switch selectedGovernanceDestination {
            case .overview, .uiReview, .executionTier:
                ProjectExecutionTierView(
                    configuredTier: executionTier,
                    effectiveTier: draftResolvedGovernance.effectiveBundle.executionTier,
                    effectiveProjectMemoryCeiling: draftResolvedGovernance.projectMemoryCeiling,
                    effectiveRuntimeSurfaceMode: draftResolvedGovernance.effectiveRuntimeSurface.effectiveMode,
                    inlineMessage: governanceInlineMessage ?? "",
                    inlineMessageIsError: governanceInlineMessageIsError,
                    onSelectTier: applyExecutionTier
                )
            case .supervisorTier:
                ProjectSupervisorTierView(
                    currentExecutionTier: executionTier,
                    configuredTier: supervisorInterventionTier,
                    effectiveTier: draftResolvedGovernance.effectiveBundle.supervisorInterventionTier,
                    effectiveReviewMemoryCeiling: draftResolvedGovernance.supervisorReviewMemoryCeiling,
                    inlineMessage: governanceInlineMessage ?? "",
                    inlineMessageIsError: governanceInlineMessageIsError,
                    onSelectTier: applySupervisorTier
                )
            case .heartbeatReview:
                ProjectHeartbeatReviewView(
                    ctx: boundGovernanceActivityContext,
                    configuredExecutionTier: executionTier,
                    configuredReviewPolicyMode: reviewPolicyMode,
                    progressHeartbeatSeconds: progressHeartbeatSeconds,
                    reviewPulseSeconds: reviewPulseSeconds,
                    brainstormReviewSeconds: brainstormReviewSeconds,
                    eventDrivenReviewEnabled: eventDrivenReviewEnabled,
                    eventReviewTriggers: eventReviewTriggers,
                    resolvedGovernance: draftResolvedGovernance,
                    governancePresentation: draftGovernancePresentation,
                    inlineMessage: governanceInlineMessage ?? "",
                    inlineMessageIsError: governanceInlineMessageIsError,
                    onSelectReviewPolicy: {
                        reviewPolicyMode = $0
                        clearGovernanceInlineMessage()
                    },
                    onUpdateProgressHeartbeatSeconds: {
                        progressHeartbeatSeconds = $0
                        clearGovernanceInlineMessage()
                    },
                    onUpdateReviewPulseSeconds: {
                        reviewPulseSeconds = $0
                        clearGovernanceInlineMessage()
                    },
                    onUpdateBrainstormReviewSeconds: {
                        brainstormReviewSeconds = $0
                        clearGovernanceInlineMessage()
                    },
                    onSetEventDrivenReviewEnabled: {
                        eventDrivenReviewEnabled = $0
                        clearGovernanceInlineMessage()
                    },
                    onSetEventReviewTriggers: {
                        eventReviewTriggers = AXProjectReviewTrigger.normalizedList($0)
                        clearGovernanceInlineMessage()
                    },
                    showActivityTimeline: boundGovernanceActivityContext != nil
                )
            }
        }
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

    private var governanceComposerPresentation: ProjectGovernanceComposerPresentation {
        ProjectGovernanceComposerPresentation(
            executionTier: executionTier,
            supervisorInterventionTier: supervisorInterventionTier,
            reviewPolicyMode: reviewPolicyMode,
            governancePresentation: draftGovernancePresentation,
            selectedDestination: selectedGovernanceDestination
        )
    }

    private var draftGovernanceTemplatePreview: AXProjectGovernanceTemplatePreview {
        xtProjectGovernanceTemplatePresentation(
            projectRoot: draftProjectRoot,
            config: draftGovernanceTemplateConfig,
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

    private var draftGovernanceTemplateConfig: AXProjectConfig {
        xtGovernanceTemplateDraftConfig(
            projectRoot: draftProjectRoot,
            template: governanceTemplateBaseline,
            executionTier: executionTier,
            supervisorInterventionTier: supervisorInterventionTier,
            reviewPolicyMode: reviewPolicyMode,
            progressHeartbeatSeconds: progressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            eventDrivenReviewEnabled: eventDrivenReviewEnabled,
            eventReviewTriggers: eventReviewTriggers
        )
    }

    private var draftResolvedGovernance: AXProjectResolvedGovernanceState {
        xtResolveProjectGovernance(
            projectRoot: draftProjectRoot,
            config: draftGovernanceTemplateConfig
        )
    }

    private var boundGovernanceActivityContext: AXProjectContext? {
        guard let selectedBoundProject else { return nil }
        return AXProjectContext(root: URL(fileURLWithPath: selectedBoundProject.rootPath, isDirectory: true))
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

    private func applyGovernanceTemplate(_ profile: AXProjectGovernanceTemplate) {
        let config = AXProjectConfig
            .default(forProjectRoot: draftProjectRoot)
            .settingGovernanceTemplate(profile, projectRoot: draftProjectRoot)

        governanceTemplateBaseline = profile
        executionTier = config.executionTier
        supervisorInterventionTier = config.supervisorInterventionTier
        reviewPolicyMode = config.reviewPolicyMode
        progressHeartbeatSeconds = config.progressHeartbeatSeconds
        reviewPulseSeconds = config.reviewPulseSeconds
        brainstormReviewSeconds = config.brainstormReviewSeconds
        eventDrivenReviewEnabled = config.eventDrivenReviewEnabled
        eventReviewTriggers = config.eventReviewTriggers

        switch profile {
        case .agent:
            governanceInlineMessage = "已切到 Agent 治理模板（默认 A4 Agent + S3）。创建后如果要真正放开设备级执行面，仍需要绑定真实 project 并完成 trusted automation 与权限就绪。"
            governanceInlineMessageIsError = false
            selectedGovernanceDestination = .executionTier
        case .safe:
            governanceInlineMessage = "已切到推荐治理模板（默认 A3 + S3）。project 会优先持续推进，但高风险动作仍继续受 grant 与 clamp 约束。"
            governanceInlineMessageIsError = false
        case .conservative:
            governanceInlineMessage = "已切到保守治理模板（默认 A1 + S2）。当前更偏向理解、规划与审阅，不主动放大执行面。"
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
                eventReviewTriggers: eventReviewTriggers
            )
        )
        let updatedBundle = currentBundle.applyingExecutionTierPreservingReviewConfiguration(tier)
        let previousSupervisor = supervisorInterventionTier

        executionTier = updatedBundle.executionTier
        supervisorInterventionTier = updatedBundle.supervisorInterventionTier
        eventReviewTriggers = normalizedEventReviewTriggers(
            for: updatedBundle.executionTier,
            preserving: eventReviewTriggers
        )

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

    private func normalizedEventReviewTriggers(
        for executionTier: AXProjectExecutionTier,
        preserving current: [AXProjectReviewTrigger]
    ) -> [AXProjectReviewTrigger] {
        AXProjectReviewTrigger.normalizedSelectionForExecutionTierTransition(
            to: executionTier,
            preserving: current
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
                eventDrivenReviewEnabled: eventDrivenReviewEnabled,
                eventReviewTriggers: eventReviewTriggers
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

    private func governanceCardAccent(_ tone: ProjectGovernanceComposerAccentTone) -> Color {
        switch tone {
        case .gray:
            return .gray
        case .blue:
            return .blue
        case .teal:
            return .teal
        case .green:
            return .green
        case .orange:
            return .orange
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
