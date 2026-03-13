//
//  CreateProjectSheet.swift
//  XTerminal
//
//  创建项目对话框
//

import SwiftUI

/// 创建项目对话框
struct CreateProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel

    @State private var projectName: String = ""
    @State private var taskDescription: String = ""
    @State private var selectedModel: String = "claude-opus-4.6"
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

    // 可用模型列表
    private let availableModels = [
        ("claude-opus-4.6", "Claude Opus 4.6", "最强大的模型"),
        ("claude-sonnet-4.6", "Claude Sonnet 4.6", "平衡性能和成本"),
        ("claude-haiku-4.5", "Claude Haiku 4.5", "快速且经济"),
        ("llama-3-70b-local", "Llama 3 70B (本地)", "本地运行，免费"),
        ("qwen-2.5-72b-local", "Qwen 2.5 72B (本地)", "本地运行，免费")
    ]

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

                    // 项目治理
                    governanceSection

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
                ForEach(availableModels, id: \.0) { model in
                    ModelOptionCard(
                        modelId: model.0,
                        displayName: model.1,
                        description: model.2,
                        isSelected: selectedModel == model.0,
                        onSelect: { selectedModel = model.0 }
                    )
                }
            }
        }
    }

    private var governanceSection: some View {
        let presentation = draftGovernancePresentation

        return VStack(alignment: .leading, spacing: 12) {
            Text("项目治理")
                .font(.headline)

            ProjectGovernanceBadge(presentation: presentation)
            ProjectGovernanceInspector(presentation: presentation)

            if let governanceInlineMessage, !governanceInlineMessage.isEmpty {
                Text(governanceInlineMessage)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

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

                Picker("", selection: $reviewPolicyMode) {
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
                    set: { progressHeartbeatSeconds = $0 }
                ),
                in: 1...240,
                step: 5
            ) {
                Text("Heartbeat: \(governanceDurationLabel(progressHeartbeatSeconds))")
            }

            Stepper(
                value: minutesBinding(
                    get: { reviewPulseSeconds },
                    set: { reviewPulseSeconds = $0 },
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
                    set: { brainstormReviewSeconds = $0 },
                    allowsOff: true
                ),
                in: 0...240,
                step: 5
            ) {
                Text("Brainstorm Review: \(governanceDurationLabel(brainstormReviewSeconds))")
            }
            .disabled(reviewPolicyMode == .off || reviewPolicyMode == .milestoneOnly)

            Toggle("Enable event-driven review", isOn: $eventDrivenReviewEnabled)
                .disabled(reviewPolicyMode == .off)

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("safe-point: \(supervisorInterventionTier.defaultInterventionMode.displayName) · \(supervisorInterventionTier.defaultAckRequired ? "guidance ack required" : "guidance ack optional")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.1))
            )
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
            executionTier: executionTier,
            supervisorInterventionTier: supervisorInterventionTier,
            reviewPolicyMode: reviewPolicyMode,
            progressHeartbeatSeconds: progressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            eventDrivenReviewEnabled: eventDrivenReviewEnabled
        )
    }

    // MARK: - Actions

    private func applyExecutionTier(_ tier: AXProjectExecutionTier) {
        let previousSupervisor = supervisorInterventionTier
        let adjustedSupervisor = max(supervisorInterventionTier, tier.minimumSafeSupervisorTier)
        executionTier = tier
        supervisorInterventionTier = adjustedSupervisor
        reviewPolicyMode = tier.defaultReviewPolicyMode
        progressHeartbeatSeconds = tier.defaultProgressHeartbeatSeconds
        reviewPulseSeconds = tier.defaultReviewPulseSeconds
        brainstormReviewSeconds = tier.defaultBrainstormReviewSeconds
        eventDrivenReviewEnabled = tier.defaultEventDrivenReviewEnabled

        if adjustedSupervisor != previousSupervisor {
            governanceInlineMessage = "\(tier.displayName) 至少需要 \(tier.minimumSafeSupervisorTier.displayName)，已自动抬升 supervisor 安全下限。"
        } else {
            governanceInlineMessage = nil
        }
    }

    private func applySupervisorTier(_ tier: AXProjectSupervisorInterventionTier) {
        let minimumSafe = executionTier.minimumSafeSupervisorTier
        guard tier >= minimumSafe else {
            governanceInlineMessage = "\(executionTier.displayName) 不能低于 \(minimumSafe.displayName)。"
            return
        }

        supervisorInterventionTier = tier
        if tier < executionTier.defaultSupervisorInterventionTier {
            governanceInlineMessage = "\(executionTier.displayName) 推荐 \(executionTier.defaultSupervisorInterventionTier.displayName) 及以上；当前组合允许，但会放松 review 纠偏强度。"
        } else {
            governanceInlineMessage = nil
        }
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
}

/// 模型选项卡片
struct ModelOptionCard: View {
    let modelId: String
    let displayName: String
    let description: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // 选择指示器
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 模型图标
                Image(systemName: modelId.contains("local") ? "desktopcomputer" : "cloud")
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
