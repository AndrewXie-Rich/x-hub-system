//
//  ProjectDetailView.swift
//  XTerminal
//
//  项目详情视图
//

import SwiftUI

struct ProjectDetailGovernanceSummary: Equatable {
    let headerSummary: String
    let executionTierSummary: String
    let supervisorTierSummary: String
    let capabilitySummary: String
    let clampSummary: String
    let sourceLabel: String
    let sourceDetail: String?

    init(presentation: ProjectGovernancePresentation) {
        var headerParts: [String] = [
            "\(presentation.effectiveExecutionLabel) / \(presentation.effectiveSupervisorLabel)",
            "Review \(presentation.reviewPolicyMode.displayName)",
            "Guidance \(presentation.guidanceSummary)"
        ]
        if let clamp = presentation.homeClampMessage {
            headerParts.append(clamp)
        } else {
            headerParts.append(presentation.homeStatusMessage)
        }
        headerSummary = headerParts.joined(separator: " · ")

        let effectiveExecutionTier = presentation.effectiveExecutionTier ?? presentation.executionTier
        executionTierSummary = "预设 \(presentation.executionTier.shortToken) ，当前生效 \(effectiveExecutionTier.shortToken)。"

        let effectiveSupervisorTier = presentation.effectiveSupervisorInterventionTier ?? presentation.supervisorInterventionTier
        var supervisorParts: [String] = []
        supervisorParts.append(
            "预设 \(presentation.supervisorInterventionTier.shortToken) ，当前生效 \(effectiveSupervisorTier.shortToken)。"
        )
        if let recommended = presentation.recommendedSupervisorInterventionTier {
            supervisorParts.append("建议至少 \(recommended.shortToken)。")
        }
        supervisorTierSummary = supervisorParts.joined(separator: " ")

        capabilitySummary = presentation.capabilityLabels.isEmpty
            ? "(none)"
            : presentation.capabilityLabels.joined(separator: ", ")
        clampSummary = presentation.homeClampMessage ?? "无额外 clamp"
        sourceLabel = presentation.compatSourceLabel
        sourceDetail = presentation.compatSourceDetail
    }
}

/// 项目详情视图
struct ProjectDetailView: View {
    @ObservedObject var project: ProjectModel
    let initialFocusSection: XTProjectDetailSection
    let initialFocusContext: XTSectionFocusContext?
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false
    @StateObject private var uiReviewActionState = XTUIReviewActionState()
    @StateObject private var uiReviewUpdateFeedback = XTTransientUpdateFeedbackState()
    @State private var uiReviewRefreshNonce = 0
    @State private var lastObservedUIReviewSignature: String?
    @State private var governanceDestination: XTProjectGovernanceDestination = .overview
    @State private var selectedSection: XTProjectDetailSection

    init(
        project: ProjectModel,
        initialFocusSection: XTProjectDetailSection = .overview,
        initialFocusContext: XTSectionFocusContext? = nil
    ) {
        self.project = project
        self.initialFocusSection = initialFocusSection
        self.initialFocusContext = initialFocusContext
        _selectedSection = State(initialValue: initialFocusSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            titleBar

            Divider()

            // 内容区域
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        if let initialFocusContext {
                            XTFocusContextCard(context: initialFocusContext)
                        }

                        projectDetailSectionRail

                        // 基本信息
                        basicInfoSection
                            .id(XTProjectDetailSection.overview)

                        Divider()

                        // 状态和进度
                        statusSection
                            .id(XTProjectDetailSection.status)

                        Divider()

                        // 最新 UI review
                        uiReviewSection
                            .id(XTProjectDetailSection.uiReview)

                        Divider()

                        // 模型和配置
                        modelSection
                            .id(XTProjectDetailSection.model)

                        Divider()

                        // 治理活动
                        governanceActivitySection
                            .id(XTProjectDetailSection.governanceActivity)

                        Divider()

                        // 成本和预算
                        costSection
                            .id(XTProjectDetailSection.cost)

                        Divider()

                        // 协作信息
                        collaborationSection
                            .id(XTProjectDetailSection.collaboration)

                        Divider()

                        // 时间线
                        timelineSection
                            .id(XTProjectDetailSection.timeline)

                        Divider()

                        // 危险操作
                        dangerZoneSection
                            .id(XTProjectDetailSection.dangerZone)
                    }
                    .padding(20)
                }
                .onAppear {
                    if initialFocusSection != .overview {
                        focusSection(initialFocusSection, using: proxy)
                    }
                }
                .onChange(of: initialFocusSection) { section in
                    if selectedSection != section {
                        selectedSection = section
                    }
                }
                .onChange(of: selectedSection) { section in
                    focusSection(section, using: proxy)
                }
            }

            Divider()

            // 底部按钮
            bottomBar
        }
        .frame(width: 700, height: 800)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "确认删除项目",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                deleteProject()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除项目 \"\(project.name)\" 将无法恢复。确定要继续吗？")
        }
        .sheet(isPresented: $showEditSheet) {
            if let ctx = projectSettingsContext {
                ProjectSettingsView(
                    ctx: ctx,
                    initialGovernanceDestination: governanceDestination
                )
                    .environmentObject(appModel)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Project Settings unavailable")
                        .font(.headline)
                    Text("当前多项目卡片还没有绑定到可编辑的 project context，因此这里暂时无法打开治理设置。")
                        .foregroundStyle(.secondary)
                    Button("Close") {
                        showEditSheet = false
                    }
                }
                .padding(20)
                .frame(minWidth: 420, minHeight: 180, alignment: .topLeading)
            }
        }
        .sheet(isPresented: $uiReviewActionState.showHistorySheet) {
            if let uiReviewContext {
                ProjectUIReviewHistorySheet(ctx: uiReviewContext)
            }
        }
    }

    // MARK: - Subviews

    private var titleBar: some View {
        let canOpenGovernance = projectSettingsContext != nil
        let executionTap: (() -> Void)? = canOpenGovernance ? {
            openGovernanceSettings(.executionTier)
        } : nil
        let supervisorTap: (() -> Void)? = canOpenGovernance ? {
            openGovernanceSettings(.supervisorTier)
        } : nil
        let heartbeatTap: (() -> Void)? = canOpenGovernance ? {
            openGovernanceSettings(.heartbeatReview)
        } : nil
        let overviewTap: (() -> Void)? = canOpenGovernance ? {
            openGovernanceSettings(.overview)
        } : nil

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                // 状态指示器
                Circle()
                    .fill(project.statusColor)
                    .frame(width: 12, height: 12)

                Text(project.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    openGovernanceSettings(.overview)
                } label: {
                    Label("治理设置", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .disabled(projectSettingsContext == nil)
                .help(projectSettingsContext == nil
                      ? "当前卡片未绑定可编辑的 project context"
                      : "打开 Project Settings，调整 A/S 档位和治理细节")

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }

            ProjectGovernanceCompactSummaryView(
                presentation: governancePresentation,
                onExecutionTierTap: executionTap,
                onSupervisorTierTap: supervisorTap,
                onReviewCadenceTap: heartbeatTap,
                onStatusTap: overviewTap,
                onCalloutTap: overviewTap
            )

            Text(governanceDetailSummary.headerSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基本信息")
                .font(.headline)

            InfoRow(label: "卡片 ID", value: project.id.uuidString)
            InfoRow(label: "任务描述", value: project.taskDescription)
            InfoRow(label: "创建时间", value: formatDate(project.createdAt))
            InfoRow(label: "最后活动", value: project.lastActivityTime)
            if let latestSessionSummary {
                InfoRow(label: "最近交接", value: latestSessionSummary.detailText)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("状态和进度")
                .font(.headline)

            // 状态卡片
            HStack(spacing: 16) {
                StatusCard(
                    icon: project.primaryStatusIcon,
                    label: "状态",
                    value: project.status.text,
                    color: project.statusColor
                )

                StatusCard(
                    icon: "message",
                    label: "消息",
                    value: "\(project.messageCount)",
                    color: .blue
                )

                if project.pendingApprovals > 0 {
                    StatusCard(
                        icon: "bolt",
                        label: "待授权",
                        value: "\(project.pendingApprovals)",
                        color: .orange
                    )
                }
            }

            // 优先级
            HStack {
                Text("优先级")
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(0..<10, id: \.self) { index in
                        Circle()
                            .fill(index < project.priority ? Color.blue : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
    }

    private var uiReviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("最新 UI Review")
                    .font(.headline)
                if uiReviewUpdateFeedback.showsBadge {
                    XTTransientUpdateBadge(tint: uiReviewUpdateTintColor)
                }
            }

            if let latestUIReview {
                uiReviewSnapshotOverview(latestUIReview)
                    .xtTransientUpdateCardChrome(
                        cornerRadius: 14,
                        isUpdated: uiReviewUpdateFeedback.isHighlighted,
                        focusTint: uiReviewUpdateTintColor,
                        updateTint: uiReviewUpdateTintColor,
                        baseBackground: .clear,
                        baseBorder: .clear,
                        updateBackgroundOpacity: 0.04,
                        updateBorderOpacity: 0.24,
                        updateShadowOpacity: 0.12
                    )
            }

            if let uiReviewContext {
                ProjectUIReviewWorkspaceView(
                    ctx: uiReviewContext,
                    emptyTitle: "暂无浏览器 UI review",
                    emptyMessage: "该项目还没有最近一次浏览器页面自观察结果。运行 `device.browser.control snapshot` 后，这里会显示最新的受治理 UI review，帮助你和 Agent 判断页面是否真的可执行。",
                    helperText: "这里保留完整 review 卡片、历史和重采样动作，Supervisor 与 Project Agent 会共用这份页面证据。",
                    showsScreenshotPreview: true,
                    reloadNonce: uiReviewRefreshNonce,
                    onSnapshotResolved: { _ in
                        uiReviewRefreshNonce += 1
                    }
                )
            } else {
                infoNote(
                    title: "暂无浏览器 UI review",
                    message: "当前多项目卡片还没有绑定到稳定的 project root，因此无法加载本地 UI review 证据。"
                )
            }
        }
        .onAppear {
            lastObservedUIReviewSignature = observedUIReviewSignature
        }
        .onChange(of: observedUIReviewSignature) { newValue in
            defer { lastObservedUIReviewSignature = newValue }
            guard let lastObservedUIReviewSignature, lastObservedUIReviewSignature != newValue else {
                return
            }
            uiReviewUpdateFeedback.trigger()
        }
        .onChange(of: uiReviewActionState.refreshNonce) { refreshNonce in
            guard refreshNonce > 0 else { return }
            uiReviewUpdateFeedback.trigger()
        }
        .onDisappear {
            uiReviewUpdateFeedback.cancel(resetState: true)
        }
    }

    private var modelSection: some View {
        return VStack(alignment: .leading, spacing: 12) {
            Text("模型和治理")
                .font(.headline)

            InfoRow(label: "当前模型", value: project.currentModel.displayName)
            InfoRow(label: "模型 ID", value: project.currentModel.id)
            HStack(alignment: .top) {
                Text("类型标识")
                    .foregroundColor(.secondary)
                Spacer()
                ModelCapabilityStrip(model: project.currentModel, limit: 5)
            }
            HStack(alignment: .top, spacing: 12) {
                governanceStateCard(
                    title: "执行档位",
                    value: governancePresentation.executionTier.displayName,
                    summary: governanceDetailSummary.executionTierSummary,
                    destination: projectSettingsContext == nil ? nil : .executionTier,
                    help: "打开 Execution Tier 设置"
                )

                governanceStateCard(
                    title: "Supervisor 档位",
                    value: governancePresentation.supervisorInterventionTier.displayName,
                    summary: governanceDetailSummary.supervisorTierSummary,
                    destination: projectSettingsContext == nil ? nil : .supervisorTier,
                    help: "打开 Supervisor Tier 设置"
                )
            }
            governanceStateCard(
                title: "Review 策略",
                value: governancePresentation.reviewPolicyMode.displayName,
                summary: governancePresentation.reviewCadenceText,
                destination: projectSettingsContext == nil ? nil : .heartbeatReview,
                help: "打开 Heartbeat & Review 设置"
            )
            InfoRow(
                label: "执行档位",
                value: governancePresentation.effectiveExecutionLabel,
                destination: projectSettingsContext == nil ? nil : .executionTier,
                help: "打开 Execution Tier 设置"
            )
            InfoRow(
                label: "Supervisor 档位",
                value: governancePresentation.effectiveSupervisorLabel,
                destination: projectSettingsContext == nil ? nil : .supervisorTier,
                help: "打开 Supervisor Tier 设置"
            )
            InfoRow(
                label: "Review 策略",
                value: governancePresentation.reviewPolicyMode.displayName,
                destination: projectSettingsContext == nil ? nil : .heartbeatReview,
                help: "打开 Heartbeat & Review 设置"
            )
            InfoRow(
                label: "Review 节奏",
                value: governancePresentation.reviewCadenceText,
                destination: projectSettingsContext == nil ? nil : .heartbeatReview,
                help: "打开 Heartbeat & Review 设置"
            )
            if let followUpRhythmSummary = governancePresentation.followUpRhythmSummary,
               !followUpRhythmSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                InfoRow(
                    label: "自动跟进",
                    value: followUpRhythmSummary,
                    destination: projectSettingsContext == nil ? nil : .heartbeatReview,
                    help: "打开 Heartbeat & Review 设置"
                )
            }
            InfoRow(
                label: "Guidance 注入",
                value: "\(governancePresentation.guidanceSummary) · \(governancePresentation.guidanceAckSummary)",
                destination: projectSettingsContext == nil ? nil : .overview,
                help: "打开治理概览"
            )
            InfoRow(
                label: "能力包",
                value: governanceDetailSummary.capabilitySummary,
                destination: projectSettingsContext == nil ? nil : .overview,
                help: "打开治理概览"
            )
            InfoRow(
                label: "治理状态",
                value: governancePresentation.homeStatusMessage,
                destination: projectSettingsContext == nil ? nil : .overview,
                help: "打开治理概览"
            )
            InfoRow(
                label: "Clamp / 收束",
                value: governanceDetailSummary.clampSummary,
                destination: projectSettingsContext == nil ? nil : .overview,
                help: "打开治理概览"
            )
            InfoRow(
                label: "治理来源",
                value: governanceDetailSummary.sourceLabel,
                destination: projectSettingsContext == nil ? nil : .overview,
                help: "打开治理概览"
            )

            if let detail = governanceDetailSummary.sourceDetail {
                infoNote(title: "治理来源说明", message: detail)
            }

            ProjectGovernanceInspector(presentation: governancePresentation)
        }
    }

    private var governanceActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("治理活动")
                .font(.headline)

            if let binding = project.registeredProjectBinding {
                InfoRow(label: "绑定 Project", value: binding.displayName)
                InfoRow(label: "Stable ID", value: binding.projectId)
                InfoRow(label: "Root", value: binding.rootPath)

                if let ctx = governanceActivityContext {
                    ProjectGovernanceActivityView(ctx: ctx)
                } else {
                    Text("这张卡片已经记录了 project 绑定，但当前无法解析到可用的 project context，所以这里只保留治理档位展示，不加载 review / guidance 时间线。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("当前多项目卡片还没有绑定到真实 project root，所以这里只展示执行档位和 supervisor 档位，不展示 supervisor review / guidance 的实际时间线。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var costSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("成本和预算")
                .font(.headline)

            // 成本统计
            HStack(spacing: 16) {
                CostCard(
                    label: "总成本",
                    value: String(format: "$%.2f", project.costTracker.totalCost),
                    color: .green
                )

                CostCard(
                    label: "总 Tokens",
                    value: formatNumber(project.costTracker.totalTokens),
                    color: .blue
                )
            }

            // 预算信息
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("每日预算")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "$%.2f", project.budget.daily))
                        .foregroundColor(.primary)
                }

                ProgressView(value: project.budget.used, total: project.budget.daily)
                    .tint(project.budget.used > project.budget.daily ? .red : .green)

                HStack {
                    Text("已使用")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "$%.2f / $%.2f", project.budget.used, project.budget.daily))
                        .font(.caption)
                        .foregroundColor(project.budget.used > project.budget.daily ? .red : .secondary)
                }
            }
        }
    }

    private var collaborationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("协作信息")
                .font(.headline)

            if !project.dependencies.isEmpty {
                InfoRow(label: "依赖项目", value: "\(project.dependencies.count) 个")
            }

            if !project.dependents.isEmpty {
                InfoRow(label: "被依赖", value: "\(project.dependents.count) 个项目")
            }

            if !project.sharedKnowledge.isEmpty {
                InfoRow(label: "共享知识", value: "\(project.sharedKnowledge.count) 条")
            }

            if !project.collaboratingProjects.isEmpty {
                InfoRow(label: "协作项目", value: "\(project.collaboratingProjects.count) 个")
            }

            if project.dependencies.isEmpty && project.dependents.isEmpty &&
               project.sharedKnowledge.isEmpty && project.collaboratingProjects.isEmpty {
                Text("暂无协作信息")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("时间线")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TimelineItem(
                    icon: "plus.circle",
                    label: "创建",
                    time: formatDate(project.createdAt),
                    color: .blue
                )

                if let startTime = project.startTime {
                    TimelineItem(
                        icon: "play.circle",
                        label: "开始",
                        time: formatDate(startTime),
                        color: .green
                    )
                }

                if let pauseTime = project.pauseTime {
                    TimelineItem(
                        icon: "pause.circle",
                        label: "暂停",
                        time: formatDate(pauseTime),
                        color: .orange
                    )
                }

                if let resumeTime = project.resumeTime {
                    TimelineItem(
                        icon: "play.circle",
                        label: "恢复",
                        time: formatDate(resumeTime),
                        color: .green
                    )
                }

                if let completionTime = project.completionTime {
                    TimelineItem(
                        icon: "checkmark.circle",
                        label: "完成",
                        time: formatDate(completionTime),
                        color: .green
                    )
                }

                if let archiveTime = project.archiveTime {
                    TimelineItem(
                        icon: "archivebox",
                        label: "归档",
                        time: formatDate(archiveTime),
                        color: .secondary
                    )
                }
            }
        }
    }

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("危险操作")
                .font(.headline)
                .foregroundColor(.red)

            Button(action: { showDeleteConfirmation = true }) {
                HStack {
                    Image(systemName: "trash")
                    Text("删除项目")
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // 快速操作按钮
            if project.status == .pending {
                Button("开始项目") {
                    startProject()
                }
                .buttonStyle(.borderedProminent)
            } else if project.status == .running {
                Button("暂停项目") {
                    pauseProject()
                }
                .buttonStyle(.bordered)
            } else if project.status == .paused {
                Button("恢复项目") {
                    resumeProject()
                }
                .buttonStyle(.borderedProminent)
            } else if project.status == .completed {
                Button("归档项目") {
                    archiveProject()
                }
                .buttonStyle(.bordered)
            }

            if let registeredProjectId {
                Button("接上次进度") {
                    appModel.presentResumeBrief(projectId: registeredProjectId)
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("关闭") {
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
        .padding()
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func InfoRow(
        label: String,
        value: String,
        destination: XTProjectGovernanceDestination? = nil,
        help: String? = nil
    ) -> some View {
        let content = HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if destination != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }

        if let destination {
            Button {
                openGovernanceSettings(destination)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help(help ?? governanceDrillDownHelp(for: destination))
        } else {
            content
        }
    }

    private func infoNote(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Actions

    private func startProject() {
        Task {
            await appModel.startMultiProject(project.id)
        }
    }

    private func pauseProject() {
        Task {
            await appModel.pauseMultiProject(project.id)
        }
    }

    private func resumeProject() {
        Task {
            await appModel.resumeMultiProject(project.id)
        }
    }

    private func archiveProject() {
        Task {
            await appModel.multiProjectManager.archiveProject(project.id)
        }
    }

    private func deleteProject() {
        Task {
            await appModel.deleteMultiProject(project.id)
            dismiss()
        }
    }

    private func openGovernanceSettings(_ destination: XTProjectGovernanceDestination) {
        guard projectSettingsContext != nil else { return }
        governanceDestination = destination
        showEditSheet = true
    }

    private func governanceDrillDownHelp(for destination: XTProjectGovernanceDestination) -> String {
        switch destination {
        case .overview:
            return "打开治理概览"
        case .uiReview:
            return "打开 UI Review"
        case .executionTier:
            return "打开 Execution Tier 设置"
        case .supervisorTier:
            return "打开 Supervisor Tier 设置"
        case .heartbeatReview:
            return "打开 Heartbeat & Review 设置"
        }
    }

    private func focusSection(
        _ section: XTProjectDetailSection,
        using proxy: ScrollViewProxy
    ) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(section, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private var projectDetailSectionRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(XTProjectDetailSection.allCases, id: \.rawValue) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        projectDetailSectionLabel(section)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selectedSection == section ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(
                                selectedSection == section
                                    ? Color.accentColor.opacity(0.12)
                                    : Color(nsColor: .controlBackgroundColor)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .stroke(
                                selectedSection == section
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.secondary.opacity(0.12),
                                lineWidth: 1
                            )
                    )
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func projectDetailSectionLabel(_ section: XTProjectDetailSection) -> some View {
        HStack(spacing: 6) {
            Text(section.displayTitle)

            if section == .uiReview, let latestUIReview {
                Text(latestUIReview.verdictLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(uiReviewVerdictColor(latestUIReview.verdict))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(uiReviewVerdictColor(latestUIReview.verdict).opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private var registeredProjectId: String? {
        let trimmed = project.registeredProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var latestSessionSummary: AXSessionSummaryCapsulePresentation? {
        guard let rootPath = project.registeredProjectRootPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            return nil
        }
        let ctx = AXProjectContext(root: URL(fileURLWithPath: rootPath, isDirectory: true))
        return AXSessionSummaryCapsulePresentation.load(for: ctx)
    }

    private var uiReviewContext: AXProjectContext? {
        guard let rootPath = project.registeredProjectRootPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            return nil
        }
        return AXProjectContext(root: URL(fileURLWithPath: rootPath, isDirectory: true))
    }

    private var latestUIReview: XTUIReviewPresentation? {
        guard let uiReviewContext else {
            return nil
        }
        return XTUIReviewPresentation.loadLatestBrowserPage(for: uiReviewContext)
    }

    private var governancePresentation: ProjectGovernancePresentation {
        if let resolved = appModel.resolvedProjectGovernance(for: project) {
            return ProjectGovernancePresentation(resolved: resolved)
        }

        return ProjectGovernancePresentation(
            executionTier: project.executionTier,
            supervisorInterventionTier: project.supervisorInterventionTier,
            reviewPolicyMode: project.reviewPolicyMode,
            progressHeartbeatSeconds: project.progressHeartbeatSeconds,
            reviewPulseSeconds: project.reviewPulseSeconds,
            brainstormReviewSeconds: project.brainstormReviewSeconds,
            eventDrivenReviewEnabled: project.eventDrivenReviewEnabled,
            eventReviewTriggers: project.eventReviewTriggers,
            compatSource: "multi_project_detail"
        )
    }

    private var governanceDetailSummary: ProjectDetailGovernanceSummary {
        ProjectDetailGovernanceSummary(presentation: governancePresentation)
    }

    private var governanceActivityContext: AXProjectContext? {
        project.governanceActivityContext { projectId in
            appModel.projectContext(for: projectId)
        }
    }

    private var projectSettingsContext: AXProjectContext? {
        project.governanceActivityContext { projectId in
            appModel.projectContext(for: projectId)
        }
    }

    @ViewBuilder
    private func governanceStateCard(
        title: String,
        value: String,
        summary: String,
        destination: XTProjectGovernanceDestination? = nil,
        help: String? = nil
    ) -> some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if destination != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(summary)
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

        if let destination {
            Button {
                openGovernanceSettings(destination)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .help(help ?? governanceDrillDownHelp(for: destination))
        } else {
            content
        }
    }

    private func uiReviewSnapshotOverview(_ review: XTUIReviewPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(review.verdictLabel)
                            .font(.headline)
                            .foregroundStyle(uiReviewVerdictColor(review.verdict))
                        Text(review.updatedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(review.issueSummary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let trend = review.trend {
                        Text("\(trend.headline) · \(trend.detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }

            XTUIReviewActionStrip(
                items: projectDetailUIReviewActions(review),
                controlSize: .small
            )

            XTUIReviewStatusMessageView(
                message: uiReviewActionState.statusMessage,
                isError: uiReviewActionState.statusIsError,
                font: .caption
            )

            HStack(alignment: .top, spacing: 12) {
                uiReviewSignalCard(
                    title: "执行结论",
                    value: review.objectiveLabel,
                    summary: review.summary,
                    tint: uiReviewVerdictColor(review.verdict)
                )
                uiReviewSignalCard(
                    title: "证据状态",
                    value: review.evidenceLabel,
                    summary: review.interactiveTargetSummary,
                    tint: review.sufficientEvidence ? .green : .orange
                )
                uiReviewSignalCard(
                    title: "关键动作",
                    value: review.criticalActionSummary,
                    summary: review.confidenceLabel + " 置信度",
                    tint: review.criticalActionExpected && !review.criticalActionVisible ? .red : .blue
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(uiReviewVerdictColor(review.verdict).opacity(0.16), lineWidth: 1)
        )
    }

    private func uiReviewSignalCard(
        title: String,
        value: String,
        summary: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.08))
        )
    }

    private func uiReviewVerdictColor(_ verdict: XTUIReviewVerdict) -> Color {
        switch verdict {
        case .ready:
            return .green
        case .attentionNeeded:
            return .orange
        case .insufficientEvidence:
            return .red
        }
    }

    private var observedUIReviewSignature: String {
        latestUIReview?.transientUpdateSignature ?? "none"
    }

    private var uiReviewUpdateTintColor: Color {
        guard let latestUIReview else { return .accentColor }
        return uiReviewVerdictColor(latestUIReview.verdict)
    }

    private func openArtifact(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    private func projectDetailUIReviewActions(
        _ review: XTUIReviewPresentation
    ) -> [XTUIReviewActionStripItem] {
        var items: [XTUIReviewActionStripItem] = [
            XTUIReviewActionStripItem(
                id: "history",
                title: "History",
                style: .bordered,
                isDisabled: uiReviewContext == nil
            ) {
                uiReviewActionState.presentHistory()
            },
            XTUIReviewActionStripItem(
                id: "resample",
                title: uiReviewActionState.isResampling ? "Sampling…" : "Re-run Snapshot",
                systemImage: uiReviewActionState.isResampling
                    ? "arrow.triangle.2.circlepath"
                    : "camera.viewfinder",
                style: .borderedProminent,
                isDisabled: uiReviewContext == nil || uiReviewActionState.isResampling
            ) {
                guard let uiReviewContext else { return }
                Task {
                    await uiReviewActionState.runSnapshot(in: uiReviewContext) { _ in
                        uiReviewRefreshNonce += 1
                    }
                }
            }
        ]

        if review.reviewFileURL != nil {
            items.append(
                XTUIReviewActionStripItem(
                    id: "open-review",
                    title: "Open Review",
                    style: .bordered
                ) {
                    openArtifact(review.reviewFileURL)
                }
            )
        }

        if review.screenshotFileURL != nil {
            items.append(
                XTUIReviewActionStripItem(
                    id: "open-screenshot",
                    title: "Open Screenshot",
                    style: .bordered
                ) {
                    openArtifact(review.screenshotFileURL)
                }
            )
        }

        return items
    }
}

/// 状态卡片
struct StatusCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 24))

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

/// 成本卡片
struct CostCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

/// 时间线项目
struct TimelineItem: View {
    let icon: String
    let label: String
    let time: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 16))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                Text(time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ProjectDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let project = ProjectModel(
            name: "重构前端代码",
            taskDescription: "重构整个前端 UI 系统，使用 SwiftUI 替代 UIKit",
            modelName: "claude-opus-4.6",
            executionTier: .a3DeliverAuto
        )
        project.status = .running
        project.messageCount = 42
        project.pendingApprovals = 2
        project.priority = 7

        return ProjectDetailView(project: project)
            .environmentObject(AppModel())
    }
}
#endif
