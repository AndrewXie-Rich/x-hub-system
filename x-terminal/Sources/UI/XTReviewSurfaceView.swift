import SwiftUI

struct XTReviewSurfaceView: View {
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore
    @Environment(\.openURL) private var openURL

    @StateObject private var reviewStore = XTReviewProjectionStore(
        minimumUpdateIntervalNanoseconds: 16_000_000
    )
    @State private var initialRefreshTask: Task<Void, Never>? = nil

    let onOpenSupervisor: () -> Void
    let onOpenControl: () -> Void

    private static let initialRefreshDelayNanoseconds: UInt64 = 180_000_000

    var body: some View {
        let transcriptInputs = projectTranscriptInputs

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                summaryStrip

                if !transcriptInputs.isEmpty {
                    projectTranscriptSection(transcriptInputs)
                }

                if grants.isEmpty && approvals.isEmpty && candidateReviews.isEmpty {
                    emptyState
                } else {
                    if !grants.isEmpty {
                        grantSection
                    }

                    if !approvals.isEmpty {
                        approvalSection
                    }

                    if !candidateReviews.isEmpty {
                        candidateReviewSection
                    }
                }
            }
            .padding(16)
        }
        .frame(minWidth: 820, minHeight: 620)
        .onAppear {
            reviewStore.bind(supervisor: supervisor, appModel: appModel)
            scheduleInitialRefresh()
        }
        .onDisappear {
            initialRefreshTask?.cancel()
            initialRefreshTask = nil
            reviewStore.unbind()
        }
    }

    private func projectTranscriptSection(
        _ inputs: [XTProjectTranscriptObservationInput]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "项目角色对话",
                subtitle: "Reviewer 复用 XT 本地运行时投影查看 Supervisor 派发、Coder 回复和 Reviewer 备注；Hub 仍是 Memory、Skills、grant、model route、quota、kill-switch、audit 的权威。",
                count: inputs.count
            )

            ForEach(inputs) { input in
                XTProjectTranscriptObservationPanel(
                    input: input,
                    style: .elevated,
                    loadLimit: 120,
                    showsEmptyState: true
                )
            }
        }
    }

    private var grants: [SupervisorManager.SupervisorPendingGrant] {
        reviewSnapshot.grants
    }

    private var approvals: [SupervisorManager.SupervisorPendingSkillApproval] {
        reviewSnapshot.approvals
    }

    private var candidateReviews: [HubIPCClient.SupervisorCandidateReviewItem] {
        reviewSnapshot.candidateReviews
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review Center")
                .font(.title2.weight(.semibold))

            Text("Reviewer 只在这里处理授权、技能审批和候选审查，不再混进普通执行路径。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryActionRail(
                title: "操作",
                actions: [
                    PrimaryActionRailAction(
                        id: "refresh",
                        title: "刷新队列",
                        subtitle: "重新拉取 grant / approval / candidate review",
                        systemImage: "arrow.clockwise.circle",
                        style: .primary
                    ),
                    PrimaryActionRailAction(
                        id: "supervisor",
                        title: "打开 Supervisor",
                        subtitle: "切回总控面继续做 drill-down 或调度",
                        systemImage: "person.3.fill",
                        style: .secondary
                    ),
                    PrimaryActionRailAction(
                        id: "control",
                        title: "打开 Control",
                        subtitle: "修 Hub、模型或技能兼容问题",
                        systemImage: "slider.horizontal.3",
                        style: .secondary
                    )
                ],
                onTap: handleHeaderAction
            )
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 12) {
            metricCard(
                title: "Hub 授权",
                value: "\(grants.count)",
                tint: grants.isEmpty ? .secondary : .orange,
                detail: grants.isEmpty ? "当前清空" : "有待处理 grant"
            )

            metricCard(
                title: "技能审批",
                value: "\(approvals.count)",
                tint: approvals.isEmpty ? .secondary : .orange,
                detail: approvals.isEmpty ? "当前清空" : "等待本地审批或 Hub grant"
            )

            metricCard(
                title: "候选审查",
                value: "\(candidateReviews.count)",
                tint: candidateReviews.isEmpty ? .secondary : .accentColor,
                detail: candidateReviews.isEmpty ? "当前清空" : "待转入审查"
            )
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前没有待处理审查项")
                .font(.headline)

            Text("如果你想继续普通项目执行，请回 Work；如果是系统级阻塞，去 Control 修 Hub、模型或技能兼容。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var grantSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Hub 授权",
                subtitle: "高风险能力和付费链路的 grant 在这里集中处理。",
                count: grants.count
            )

            ForEach(grants) { grant in
                let row = SupervisorPendingHubGrantPresentation.row(
                    grant,
                    inFlightGrantIDs: [],
                    hubInteractive: hubInteractive,
                    isFocused: false
                )
                queueCard(
                    iconName: "exclamationmark.shield.fill",
                    iconTint: .orange,
                    title: row.title,
                    metaText: [row.ageText, row.grantIdentifierText].joined(separator: " · "),
                    summary: row.summary,
                    detailLines: row.governedContextLines +
                        [
                            row.supplementaryReasonText,
                            row.priorityReasonText,
                            row.nextActionText,
                            row.scopeSummaryText
                        ]
                        .compactMap { $0 },
                    actions: row.actionDescriptors,
                    onAction: handleReviewAction
                )
            }
        }
    }

    private var approvalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "技能审批",
                subtitle: "本地审批、Hub grant 和技能阻塞统一从这里进入。",
                count: approvals.count
            )

            ForEach(approvals) { approval in
                let row = SupervisorPendingSkillApprovalPresentation.row(
                    approval,
                    isFocused: false
                )
                queueCard(
                    iconName: row.iconName,
                    iconTint: row.authorizationMode == .blocked ? .red : .orange,
                    title: row.title,
                    metaText: [row.ageText, row.requestIdentifierText].joined(separator: " · "),
                    summary: row.summary,
                    detailLines: [
                        row.nextStepText,
                        row.routingExplanationText,
                        row.noteText
                    ]
                    .compactMap { $0 },
                    actions: row.actionDescriptors,
                    onAction: handleReviewAction
                )
            }
        }
    }

    private var candidateReviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "候选审查",
                subtitle: "Reviewer 只负责转入审查和 gate，不直接混进普通会话执行。",
                count: candidateReviews.count
            )

            ForEach(candidateReviews) { item in
                let row = SupervisorCandidateReviewPresentation.row(
                    item,
                    inFlightRequestIDs: [],
                    hubInteractive: hubInteractive,
                    projectNamesByID: reviewSnapshot.candidateProjectNamesByID,
                    isFocused: false
                )
                queueCard(
                    iconName: "square.stack.3d.up.badge.a.fill",
                    iconTint: .accentColor,
                    title: row.title,
                    metaText: [row.ageText, row.reviewStateText].joined(separator: " · "),
                    summary: row.summary,
                    detailLines: [
                        row.scopeText,
                        row.draftText,
                        row.evidenceText
                    ]
                    .compactMap { $0 },
                    actions: row.actionDescriptors,
                    onAction: handleReviewAction
                )
            }
        }
    }

    private func handleHeaderAction(_ action: PrimaryActionRailAction) {
        switch action.id {
        case "refresh":
            refreshAll()
        case "supervisor":
            onOpenSupervisor()
        case "control":
            onOpenControl()
        default:
            break
        }
    }

    private func handleReviewAction(_ descriptor: SupervisorCardActionDescriptor) {
        switch descriptor.action {
        case .openAudit(let auditAction):
            handleAuditAction(auditAction)
        case .openURL(_, let rawURL):
            guard let url = URL(string: rawURL) else { return }
            openURL(url)
        case .openProjectGovernance(let projectId, let destination):
            appModel.requestProjectSettingsFocus(
                projectId: projectId,
                destination: destination
            )
        case .stageSupervisorCandidateReview(let item):
            supervisor.stageSupervisorCandidateReview(item)
        case .approvePendingGrant(let grant):
            supervisor.approvePendingHubGrant(grant)
        case .denyPendingGrant(let grant):
            supervisor.denyPendingHubGrant(grant)
        case .approvePendingSkillApproval(let approval):
            supervisor.approvePendingSupervisorSkillApproval(approval)
        case .denyPendingSkillApproval(let approval):
            supervisor.denyPendingSupervisorSkillApproval(approval)
        case .approveSkillActivity(let item):
            supervisor.approveSupervisorSkillActivity(item)
        case .denySkillActivity(let item):
            supervisor.denySupervisorSkillActivity(item)
        case .retrySkillActivity(let item):
            supervisor.retrySupervisorSkillActivity(item)
        }
    }

    private func handleAuditAction(_ action: SupervisorAuditDrillDownAction) {
        onOpenSupervisor()

        switch action {
        case .pendingGrant(let grant):
            appModel.requestSupervisorGrantFocus(
                projectId: grant.projectId,
                grantRequestId: grant.grantRequestId,
                capability: grant.capability
            )
        case .pendingSkillApproval(let approval):
            appModel.requestSupervisorApprovalFocus(
                projectId: approval.projectId,
                requestId: approval.requestId
            )
        case .recentSkillActivity(let item):
            appModel.requestSupervisorSkillRecordFocus(
                projectId: item.projectId,
                requestId: item.requestId
            )
        case .officialSkillsChannel,
             .eventLoop(_),
             .infrastructureItem(_),
             .fullRecordFallback(_, _, _):
            break
        }
    }

    private func refreshAll() {
        supervisor.refreshPendingHubGrantSnapshotNow()
        supervisor.refreshPendingSupervisorSkillApprovalsNow()
        supervisor.refreshSupervisorCandidateReviewSnapshotNow()
    }

    private func scheduleInitialRefresh() {
        guard initialRefreshTask == nil else { return }
        XTPerformanceTrace.event("XT Review Initial Refresh Scheduled", "delay_ms=180")
        initialRefreshTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: Self.initialRefreshDelayNanoseconds)
            guard !Task.isCancelled else {
                initialRefreshTask = nil
                return
            }
            initialRefreshTask = nil
            refreshAll()
            XTPerformanceTrace.event("XT Review Initial Refresh Committed")
        }
    }

    private var hubInteractive: Bool {
        hubConnectionStore.snapshot.interactive
    }

    private var reviewSnapshot: XTReviewSurfaceSnapshot {
        reviewStore.snapshot
    }

    private var projectTranscriptInputs: [XTProjectTranscriptObservationInput] {
        var seen = Set<String>()
        var ids: [String] = []

        func appendProjectId(_ raw: String?) {
            let projectId = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !projectId.isEmpty,
                  projectId != AXProjectRegistry.globalHomeId,
                  seen.insert(projectId).inserted else {
                return
            }
            ids.append(projectId)
        }

        appendProjectId(appModel.selectedProjectId)
        grants.forEach { appendProjectId($0.projectId) }
        approvals.forEach { appendProjectId($0.projectId) }
        candidateReviews.forEach { item in
            appendProjectId(item.projectId)
            item.projectIds.forEach { appendProjectId($0) }
        }

        return ids.prefix(4).compactMap(projectTranscriptInput)
    }

    private func projectTranscriptInput(
        for projectId: String
    ) -> XTProjectTranscriptObservationInput? {
        guard let project = appModel.registry.project(for: projectId),
              let context = appModel.projectContext(for: projectId) else {
            return nil
        }
        return XTProjectTranscriptObservationInput(
            projectId: project.projectId,
            projectName: project.displayName,
            context: context,
            session: appModel.session(for: context)
        )
    }

    private var supervisor: SupervisorManager {
        SupervisorManager.shared
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("XTReviewSurfaceView requires xtAppModelReference")
        }
        return appModelReference
    }

    private func sectionHeader(
        title: String,
        subtitle: String,
        count: Int
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text("\(count)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.10))
                .clipShape(Capsule())
        }
    }

    private func metricCard(
        title: String,
        value: String,
        tint: Color,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private func queueCard(
        iconName: String,
        iconTint: Color,
        title: String,
        metaText: String,
        summary: String,
        detailLines: [String],
        actions: [SupervisorCardActionDescriptor],
        onAction: @escaping (SupervisorCardActionDescriptor) -> Void
    ) -> some View {
        XTReviewQueueCardView(
            iconName: iconName,
            iconTint: iconTint,
            title: title,
            metaText: metaText,
            summary: summary,
            detailLines: detailLines,
            actions: actions,
            onAction: onAction
        )
    }
}

private struct XTReviewQueueCardView: View {
    let iconName: String
    let iconTint: Color
    let title: String
    let metaText: String
    let summary: String
    let detailLines: [String]
    let actions: [SupervisorCardActionDescriptor]
    let onAction: (SupervisorCardActionDescriptor) -> Void

    private var filteredDetailLines: [(Int, String)] {
        detailLines
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .enumerated()
            .map { ($0.offset, $0.element) }
    }

    private var visibleActions: ArraySlice<SupervisorCardActionDescriptor> {
        actions.prefix(3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(iconTint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Text(metaText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }

            Text(summary)
                .font(.body)

            ForEach(filteredDetailLines, id: \.0) { _, line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !visibleActions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(visibleActions) { descriptor in
                        actionButton(descriptor)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func actionButton(_ descriptor: SupervisorCardActionDescriptor) -> some View {
        if descriptor.style == .prominent {
            Button(descriptor.label) {
                onAction(descriptor)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!descriptor.isEnabled)
        } else {
            Button(descriptor.label) {
                onAction(descriptor)
            }
            .buttonStyle(.bordered)
            .disabled(!descriptor.isEnabled)
        }
    }
}
