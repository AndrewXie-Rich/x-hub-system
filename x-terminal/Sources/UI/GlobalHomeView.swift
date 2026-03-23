import Foundation
import SwiftUI
import AppKit

struct GlobalHomeView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
    @StateObject private var supervisorManager = SupervisorManager.shared
    @State private var decisionDrafts: [String: String] = [:]
    @State private var pendingGrantSnapshot: HubIPCClient.PendingGrantSnapshot?
    @State private var pendingGrantActionsInFlight: Set<String> = []

    private var homePendingGrantCount: Int {
        guard let snapshot = pendingGrantSnapshot else { return 0 }
        return snapshot.items.filter { grant in
            let status = grant.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let decision = grant.decision.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return status == "pending" || decision == "queued"
        }.count
    }

    private var homePresentation: GlobalHomePresentation {
        GlobalHomePresentation.fromRuntime(
            appModel: appModel,
            pendingGrantCount: homePendingGrantCount
        )
    }

    private var homeResumeReminder: AXResumeReminderProjectPresentation? {
        appModel.latestResumeReminderProject()
    }

    private var routeRepairWatchItems: [AXRouteRepairProjectWatchItem] {
        AXRouteRepairLogStore.watchItems(for: appModel.sortedProjects, limit: 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: UIThemeTokens.sectionSpacing) {
                    homeHeroPanel
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    if appModel.sortedProjects.isEmpty {
                        emptyProjectsCard
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    } else {
                        projectsSection
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .task {
            while !Task.isCancelled {
                await refreshPendingGrants()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private var headerView: some View {
        let presentation = homePresentation

        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("全局首页（Global Home）")
                    .font(UIThemeTokens.heroFont())
                Text("汇总每个 project 的状态、blocker、授权与下一步入口；大任务入口已收敛进 Supervisor 窗口。")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            ValidatedScopeBadge(presentation: presentation.badge)
                .frame(maxWidth: 280)
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var homeHeroPanel: some View {
        let presentation = homePresentation

        return VStack(alignment: .leading, spacing: UIThemeTokens.sectionSpacing) {
            if let reminder = homeResumeReminder {
                HomeResumeReminderCard(
                    reminder: reminder,
                    onDismiss: {
                        appModel.dismissResumeReminder(projectId: reminder.projectId)
                    },
                    onResume: {
                        appModel.presentResumeBrief(projectId: reminder.projectId)
                    }
                )
            }

            PrimaryActionRail(
                title: "快速入口",
                actions: presentation.actions,
                onTap: handleHomeAction
            )

            StatusExplanationCard(explanation: presentation.primaryStatus)
            StatusExplanationCard(explanation: presentation.releaseStatus)

            if !appModel.skillsCompatibilitySnapshot.builtinGovernedSkills.isEmpty {
                builtinGovernedSkillsCard
            }

            if !routeRepairWatchItems.isEmpty {
                routeRepairWatchlistCard
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .fill(UIThemeTokens.secondaryCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
        )
    }

    private var emptyProjectsCard: some View {
        let explanation = StatusExplanation(
            state: appModel.hubInteractive ? .ready : .blockedWaitingUpstream,
            headline: "先准备第一个 project，首页只保留项目汇总与运行状态",
            whatHappened: "当前还没有已登记项目，但首页的项目总览、发布范围提醒和阻断说明都已经就绪。",
            whyItHappened: "大任务入口已从 Home 收敛进 Supervisor 对话窗，首页只负责项目级概览、resume 与诊断入口。",
            userAction: appModel.hubInteractive ? "先创建一个 project；需要发起大任务时，从右上角打开 Supervisor 窗口。" : "先点击“Pair Hub”，完成连接后再创建 project。",
            machineStatusRef: "projects=0; hub_interactive=\(appModel.hubInteractive)",
            hardLine: "validated-mainline-only; no_scope_expansion",
            highlights: [
                "badge_text=Validated mainline only",
                "primary_cta=resume_project"
            ]
        )

        return StatusExplanationCard(explanation: explanation)
    }

    private var routeRepairWatchlistCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("路由观察清单（Route Watchlist）", systemImage: "waveform.path.ecg.rectangle")
                    .font(.headline)
                Spacer(minLength: 8)
                Text("优先看最近最容易掉回本地的项目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(routeRepairWatchItems) { item in
                let reminderStatus = supervisorManager.routeAttentionReminderStatus(for: item)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(item.projectDisplayName)
                                .font(.subheadline.weight(.semibold))
                            Text(item.digest.failureCount > 0 ? "需要关注（needs_attention）" : "已观测（observed）")
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(item.digest.failureCount > 0 ? UIThemeTokens.color(for: .diagnosticRequired) : .secondary)
                        }
                        Text(item.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let reminderLine = routeReminderLine(reminderStatus) {
                            Text(reminderLine)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 8) {
                        Button("查看路由") {
                            openProjectRouteDiagnose(item.projectId)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if reminderStatus.quietingCurrentIssue {
                            Button("恢复提醒") {
                                supervisorManager.clearRouteAttentionReminderState(projectId: item.projectId)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .help("清掉当前静默状态；如果问题还在，下一次 timer 心跳会重新主动提醒。")
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .fill(UIThemeTokens.stateBackground(for: .diagnosticRequired))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .stroke(UIThemeTokens.color(for: .diagnosticRequired).opacity(0.24), lineWidth: 1)
        )
    }

    private var builtinGovernedSkillsCard: some View {
        let snapshot = appModel.skillsCompatibilitySnapshot
        let managedStatusLine = snapshot.statusLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let extraCount = max(0, snapshot.builtinGovernedSkillCount - builtinGovernedSkillHighlights.count)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("XT 内建技能（XT Native Skills）", systemImage: "bolt.shield")
                    .font(.headline)

                Spacer(minLength: 8)

                Text("builtin \(snapshot.builtinGovernedSkillCount)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Capsule())
            }

            Text(
                "这些能力由 XT 本地内置提供，Supervisor 可以直接发现并按治理规则调用；它们不会被当成可安装、可删除的 Hub skill 包。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            XTBuiltinGovernedSkillsListView(
                items: snapshot.builtinGovernedSkills,
                style: .compact
            )

            if !managedStatusLine.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("托管（managed）")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Capsule())

                    Text(managedStatusLine)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(skillsStatusColor(snapshot.statusKind))

                    if snapshot.installedSkillCount > 0 {
                        Text("installed=\(snapshot.installedSkillCount)")
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(builtinGovernedSkillHighlights) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.displayName)
                                .font(.caption.weight(.semibold))
                            Text(item.skillID)
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            Text(normalizedRiskToken(item.riskLevel))
                                .font(.caption2.monospaced())
                                .foregroundStyle(toneColor(for: item.riskLevel))
                        }

                        Text(item.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if extraCount > 0 {
                    Text("另外还有 \(extraCount) 个 XT 内建受治理技能已注册；完整清单会继续保留在 Settings / Hub Setup 诊断页。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .fill(UIThemeTokens.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
        )
    }

    private var builtinGovernedSkillHighlights: [AXBuiltinGovernedSkillSummary] {
        let items = appModel.skillsCompatibilitySnapshot.builtinGovernedSkills
        let preferredIDs = ["guarded-automation", "supervisor-voice"]
        let preferred = preferredIDs.compactMap { skillID in
            items.first(where: { $0.skillID == skillID })
        }
        if !preferred.isEmpty {
            return preferred
        }
        return Array(items.prefix(2))
    }

    private func skillsStatusColor(_ status: AXSkillsCompatibilityStatusKind) -> Color {
        switch status {
        case .supported:
            return .secondary
        case .partial:
            return .orange
        case .blocked, .unavailable:
            return .red
        }
    }

    private func toneColor(for riskLevel: String) -> Color {
        switch riskLevel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high", "critical":
            return .red
        case "medium":
            return .orange
        case "low":
            return .green
        default:
            return .secondary
        }
    }

    private func normalizedRiskToken(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private var projectsSection: some View {
        let projectSessions: [(project: AXProjectEntry, session: ChatSessionModel)] = appModel.sortedProjects.compactMap { project in
            guard let session = appModel.sessionForProjectId(project.projectId) else { return nil }
            return (project, session)
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("项目总览（Project watchlist）")
                .font(UIThemeTokens.sectionFont())
            Text("先看发生了什么 / 原因 / 下一步，再进入具体项目执行。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(projectSessions.indices, id: \.self) { index in
                    let entry = projectSessions[index]
                    if index > 0 {
                        Divider()
                    }
                    ProjectHomeRow(
                        project: entry.project,
                        session: entry.session,
                        decisionText: decisionBinding(entry.project.projectId),
                        pendingGrants: pendingGrants(for: entry.project.projectId),
                        pendingGrantActionsInFlight: pendingGrantActionsInFlight,
                        onApprovePendingGrant: { grant in
                            approvePendingGrant(grant, projectId: entry.project.projectId)
                        },
                        onDenyPendingGrant: { grant in
                            denyPendingGrant(grant, projectId: entry.project.projectId)
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                    .fill(UIThemeTokens.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                    .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
            )
        }
    }

    private func handleHomeAction(_ action: PrimaryActionRailAction) {
        switch action.id {
        case "resume_project":
            if appModel.canPresentPreferredResumeBrief {
                appModel.presentPreferredResumeBrief()
            } else {
                supervisorManager.requestSupervisorWindow(reason: "home_resume_fallback")
            }
        case "pair_hub":
            openWindow(id: "hub_setup")
        case "model_status":
            supervisorManager.requestSupervisorWindow(
                sheet: .modelSettings,
                reason: "home_model_status"
            )
        default:
            break
        }
    }

    private func decisionBinding(_ projectId: String) -> Binding<String> {
        Binding(
            get: { decisionDrafts[projectId] ?? "" },
            set: { decisionDrafts[projectId] = $0 }
        )
    }

    private func routeReminderLine(
        _ status: SupervisorManager.RouteAttentionReminderStatus
    ) -> String? {
        guard let lastAlertAt = status.lastAlertAt else { return nil }
        let lastAlertText = relativeTimeText(lastAlertAt)
        if status.quietingCurrentIssue {
            let cooldownText = compactDurationText(status.cooldownRemainingSec)
            return "上次提醒：\(lastAlertText)；当前静默观察中，约 \(cooldownText) 后才会再次主动提醒。"
        }
        return "上次提醒：\(lastAlertText)。"
    }

    private func relativeTimeText(_ ts: Double) -> String {
        guard ts > 0 else { return "未知" }
        let elapsedSec = max(0, Int(Date().timeIntervalSince1970 - ts))
        if elapsedSec < 90 { return "刚刚" }
        let mins = elapsedSec / 60
        if mins < 60 { return "\(mins) 分钟前" }
        let hours = mins / 60
        if hours < 48 { return "\(hours) 小时前" }
        return "\(hours / 24) 天前"
    }

    private func compactDurationText(_ seconds: Int) -> String {
        let normalized = max(0, seconds)
        if normalized < 90 { return "1 分钟内" }
        let mins = normalized / 60
        if mins < 60 { return "\(mins) 分钟" }
        let hours = mins / 60
        if hours < 48 { return "\(hours) 小时" }
        return "\(hours / 24) 天"
    }

    private func openProjectRouteDiagnose(_ projectId: String) {
        appModel.selectProject(projectId)
        appModel.setPane(.chat, for: projectId)
        appModel.requestProjectRouteDiagnoseFocus(projectId: projectId)
    }

    private func pendingGrants(for projectId: String) -> [HubIPCClient.PendingGrantItem] {
        guard let snapshot = pendingGrantSnapshot else { return [] }
        return snapshot.items
            .filter { grant in
                let pid = grant.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pid.isEmpty, pid == projectId else { return false }
                let status = grant.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let decision = grant.decision.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return status == "pending" || decision == "queued"
            }
            .sorted { lhs, rhs in
                if lhs.createdAtMs != rhs.createdAtMs {
                    return lhs.createdAtMs < rhs.createdAtMs
                }
                return lhs.grantRequestId.localizedCaseInsensitiveCompare(rhs.grantRequestId) == .orderedAscending
            }
    }

    private func refreshPendingGrants() async {
        let snapshot = await HubIPCClient.requestPendingGrantRequests(projectId: nil, limit: 260)
        await MainActor.run {
            pendingGrantSnapshot = snapshot
        }
    }

    private func approvePendingGrant(_ grant: HubIPCClient.PendingGrantItem, projectId: String) {
        let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !grantId.isEmpty else { return }
        guard !pendingGrantActionsInFlight.contains(grantId) else { return }
        pendingGrantActionsInFlight.insert(grantId)

        Task {
            let ttlOverride = grant.requestedTtlSec > 0 ? grant.requestedTtlSec : nil
            let tokenOverride = grant.requestedTokenCap > 0 ? grant.requestedTokenCap : nil
            let result = await HubIPCClient.approvePendingGrantRequest(
                grantRequestId: grantId,
                projectId: projectId,
                requestedTtlSec: ttlOverride,
                requestedTokenCap: tokenOverride,
                note: "x_terminal_home_quick_approve"
            )
            await MainActor.run {
                pendingGrantActionsInFlight.remove(grantId)
                if !result.ok {
                    decisionDrafts[projectId] = XTHubGrantPresentation.decisionFailureDraft(
                        intent: .approve,
                        capability: grant.capability,
                        modelId: grant.modelId,
                        grantRequestId: grantId,
                        reasonCode: result.reasonCode
                    )
                }
            }
            await refreshPendingGrants()
        }
    }

    private func denyPendingGrant(_ grant: HubIPCClient.PendingGrantItem, projectId: String) {
        let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !grantId.isEmpty else { return }
        guard !pendingGrantActionsInFlight.contains(grantId) else { return }
        pendingGrantActionsInFlight.insert(grantId)

        Task {
            let result = await HubIPCClient.denyPendingGrantRequest(
                grantRequestId: grantId,
                projectId: projectId,
                reason: "user_denied_from_home"
            )
            await MainActor.run {
                pendingGrantActionsInFlight.remove(grantId)
                if !result.ok {
                    decisionDrafts[projectId] = XTHubGrantPresentation.decisionFailureDraft(
                        intent: .deny,
                        capability: grant.capability,
                        modelId: grant.modelId,
                        grantRequestId: grantId,
                        reasonCode: result.reasonCode
                    )
                }
            }
            await refreshPendingGrants()
        }
    }
}

private struct HomeResumeReminderCard: View {
    let reminder: AXResumeReminderProjectPresentation
    let onDismiss: () -> Void
    let onResume: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("检测到最近交接摘要", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                Spacer(minLength: 12)
                Text(reminder.summary.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(reminder.projectDisplayName)
                .font(.subheadline.weight(.semibold))

            Text("这是最近一次在生命周期边界写入的项目交接摘要。只有你点“接上次进度”时才会展开，不会自动塞进当前 prompt。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("接上次进度", action: onResume)
                    .buttonStyle(.borderedProminent)
                Button("稍后", action: onDismiss)
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .fill(UIThemeTokens.stateBackground(for: .inProgress))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .stroke(UIThemeTokens.color(for: .inProgress).opacity(0.24), lineWidth: 1)
        )
    }
}

private struct ProjectHomeRow: View {
    let project: AXProjectEntry
    @ObservedObject var session: ChatSessionModel
    @Binding var decisionText: String
    let pendingGrants: [HubIPCClient.PendingGrantItem]
    let pendingGrantActionsInFlight: Set<String>
    let onApprovePendingGrant: (HubIPCClient.PendingGrantItem) -> Void
    let onDenyPendingGrant: (HubIPCClient.PendingGrantItem) -> Void
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        let pending = session.pendingToolCalls
        let isRunning = session.isSending
        let candidates = appModel.skillCandidates(for: project.projectId)
        let curations = appModel.curationSuggestions(for: project.projectId)
        let latestSessionSummary = AXSessionSummaryCapsulePresentation.load(for: projectContext)
        let latestUIReview = XTUIReviewPresentation.loadLatestBrowserPage(for: projectContext)
        let governed = appModel.governedAuthorityPresentation(for: project)
        let governancePresentation = ProjectGovernancePresentation(
            resolved: appModel.resolvedProjectGovernance(for: project)
        )
        let routeRepairDigest = AXRouteRepairLogStore.digest(for: projectContext, limit: 50)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.displayName)
                    .font(.headline)
                Spacer(minLength: 8)
                Text("更新：\(timeText(project.lastSummaryAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("接上次进度") {
                    appModel.presentResumeBrief(projectId: project.projectId)
                }
                .disabled(session.isSending)
                Button("打开") {
                    appModel.selectProject(project.projectId)
                    if !pending.isEmpty {
                        appModel.setPane(.chat, for: project.projectId)
                        appModel.requestProjectToolApprovalFocus(
                            projectId: project.projectId,
                            requestId: pending.first?.id
                        )
                    }
                }
            }

            ProjectGovernanceCompactSummaryView(
                presentation: governancePresentation,
                onExecutionTierTap: { openGovernanceSettings(.executionTier) },
                onSupervisorTierTap: { openGovernanceSettings(.supervisorTier) },
                onReviewCadenceTap: { openGovernanceSettings(.heartbeatReview) },
                onStatusTap: { openGovernanceSettings(.overview) },
                onCalloutTap: { openGovernanceSettings(.overview) }
            )

            if let latestSessionSummary {
                Text(latestSessionSummary.badgeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(latestSessionSummary.helpText)
            }

            if let latestUIReview {
                ProjectUIReviewCompactSummaryView(review: latestUIReview)
                row(title: "UI 审查", value: latestUIReview.updatedText, placeholder: "未生成")
            }

            let digest = (project.statusDigest ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let stateValue = (project.currentStateSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            row(title: "状态", value: stateValue.isEmpty ? digest : stateValue, placeholder: "未生成")
            row(title: "记忆", value: memoryHealthSummary(), placeholder: "未知")
            if routeRepairDigest.totalEvents > 0 {
                row(title: "路由修复", value: routeRepairDigest.headline, placeholder: "无")
            }
            row(
                title: "治理档位",
                value: governanceAxisSummary(governancePresentation),
                placeholder: "A0 / S0",
                action: { openGovernanceSettings(.overview) },
                help: "打开 Project Governance 概览"
            )
            row(
                title: "治理状态",
                value: governancePresentation.homeStatusMessage,
                placeholder: "预设值与生效值当前一致。",
                action: { openGovernanceSettings(.overview) },
                help: "查看当前治理状态和收束原因",
                tone: governanceStatusTone(governancePresentation)
            )
            row(
                title: "Review 节奏",
                value: governancePresentation.reviewCadenceText,
                placeholder: "off",
                action: { openGovernanceSettings(.heartbeatReview) },
                help: "打开 Heartbeat & Review 设置"
            )
            if let clampMessage = governancePresentation.homeClampMessage {
                row(
                    title: "Clamp / 收束",
                    value: clampMessage,
                    placeholder: "无",
                    action: { openGovernanceSettings(.overview) },
                    help: "查看当前收束原因、运行限制和治理状态",
                    tone: governanceClampTone(governancePresentation)
                )
            }
            row(
                title: "执行权限",
                value: governedSummary(governed),
                placeholder: "人工审批",
                action: { openGovernanceSettings(.overview) },
                help: "查看当前项目的治理边界、执行权限和收束状态"
            )
            row(title: "卡点", value: project.blockerSummary, placeholder: "无")
            row(title: "下一步", value: project.nextStepSummary, placeholder: "未生成")

            if !digest.isEmpty, !stateValue.isEmpty {
                Text(digest)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !pending.isEmpty || isRunning {
                Text("待处理：\(pending.count) · 运行中：\(isRunning ? "是" : "否")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !pendingGrants.isEmpty {
                Text("Hub 授权待处理：\(pendingGrants.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(pendingGrants, id: \.grantRequestId) { grant in
                    let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
                    let inFlight = pendingGrantActionsInFlight.contains(grantId)
                    let supplementaryReason = XTHubGrantPresentation.supplementaryReason(
                        grant.reason,
                        capability: grant.capability,
                        modelId: grant.modelId
                    )
                    let scopeSummary = XTHubGrantPresentation.scopeSummary(
                        requestedTtlSec: grant.requestedTtlSec,
                        requestedTokenCap: grant.requestedTokenCap
                    )
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hubGrantTitle(grant))
                                .font(.subheadline)
                            if let supplementaryReason {
                                Text(supplementaryReason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Text("授权单号：\(grantId) · \(grantTimingText(grant.createdAtMs))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if let scopeSummary {
                                Text(scopeSummary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        if inFlight {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("批准") {
                            onApprovePendingGrant(grant)
                        }
                        .disabled(inFlight || !appModel.hubInteractive)
                        Button("拒绝") {
                            onDenyPendingGrant(grant)
                        }
                        .disabled(inFlight || !appModel.hubInteractive)
                    }
                }
            }

            if !pending.isEmpty {
                ScrollView(.horizontal) {
                    Text(pendingSummary(pending))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if !candidates.isEmpty {
                Text("技能候选：\(candidates.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(candidates) { cand in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cand.title)
                                .font(.subheadline)
                            if !cand.summary.isEmpty {
                                Text(cand.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Button("晋升") {
                            appModel.approveSkillCandidate(projectId: project.projectId, candidateId: cand.id)
                        }
                        Button("忽略") {
                            appModel.rejectSkillCandidate(projectId: project.projectId, candidateId: cand.id)
                        }
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("整理建议：\(curations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Scan Vault") {
                    appModel.scanVaultNow(projectId: project.projectId)
                }
                .font(.caption)
            }

            if !curations.isEmpty {
                ForEach(curations) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title)
                                .font(.subheadline)
                            let conf = s.confidence ?? 0
                            Text("\(s.type) · confidence=\(String(format: "%.2f", conf)) · refs=\(s.refs.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !s.summary.isEmpty {
                                Text(s.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Button("应用") {
                            appModel.applyCurationSuggestion(projectId: project.projectId, suggestionId: s.id)
                        }
                        Button("忽略") {
                            appModel.dismissCurationSuggestion(projectId: project.projectId, suggestionId: s.id)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Decision / 指令…", text: $decisionText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let trimmed = decisionText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        guard pending.isEmpty else { return }
                        guard appModel.hubInteractive else { return }
                        appModel.sendFromHome(projectId: project.projectId, text: trimmed)
                        decisionText = ""
                    }

                Button("OK") {
                    if !pending.isEmpty {
                        appModel.approvePending(for: project.projectId)
                        decisionText = ""
                        return
                    }
                    let trimmed = decisionText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        appModel.sendFromHome(projectId: project.projectId, text: trimmed)
                        decisionText = ""
                    }
                }
                .disabled(!appModel.hubInteractive || (decisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pending.isEmpty))

                Button("Reject") {
                    if !pending.isEmpty {
                        appModel.rejectPending(for: project.projectId)
                    }
                    decisionText = ""
                }
                .disabled(decisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pending.isEmpty)
            }

            if !appModel.hubInteractive {
                Text("Hub 未连接：可先输入，连接后再发送。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !pending.isEmpty {
                Text("当前有待审批工具调用，处理后可提交新指令。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var projectContext: AXProjectContext {
        AXProjectContext(root: URL(fileURLWithPath: project.rootPath, isDirectory: true))
    }

    private func timeText(_ ts: Double?) -> String {
        guard let ts, ts > 0 else { return "未更新" }
        let d = Date(timeIntervalSince1970: ts)
        return Self.timeFormatter.string(from: d)
    }

    @ViewBuilder
    private func row(
        title: String,
        value: String?,
        placeholder: String,
        action: (() -> Void)? = nil,
        help: String? = nil,
        tone: HomeSummaryTone? = nil
    ) -> some View {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let textLine = trimmed.isEmpty ? "\(title)：\(placeholder)" : "\(title)：\(trimmed)"
        let isPlaceholder = trimmed.isEmpty

        if let action {
            Button(action: action) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(textLine)
                        .foregroundStyle(rowTextColor(isPlaceholder: isPlaceholder, tone: tone))
                    Spacer(minLength: 6)
                    if let tone {
                        Image(systemName: tone.iconName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tone.color)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help ?? "Open the related project setting")
        } else {
            if isPlaceholder {
                Text(textLine)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(textLine)
                        .foregroundStyle(rowTextColor(isPlaceholder: false, tone: tone))
                    if let tone {
                        Image(systemName: tone.iconName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tone.color)
                    }
                }
            }
        }
    }

    private func rowTextColor(isPlaceholder: Bool, tone: HomeSummaryTone?) -> Color {
        if isPlaceholder { return .secondary }
        return tone?.color ?? .primary
    }

    private func openGovernanceSettings(_ destination: XTProjectGovernanceDestination) {
        appModel.requestProjectSettingsFocus(
            projectId: project.projectId,
            destination: destination
        )
    }

    private func governanceStatusTone(_ presentation: ProjectGovernancePresentation) -> HomeSummaryTone? {
        if !presentation.invalidMessages.isEmpty {
            return .invalid
        }
        if !presentation.warningMessages.isEmpty {
            return .warning
        }
        if presentation.governanceSourceHint != nil {
            return .info
        }
        return nil
    }

    private func governanceClampTone(_ presentation: ProjectGovernancePresentation) -> HomeSummaryTone {
        if !presentation.invalidMessages.isEmpty {
            return .invalid
        }
        if !presentation.warningMessages.isEmpty {
            return .warning
        }
        return .info
    }

    private func pendingSummary(_ calls: [ToolCall]) -> String {
        calls.map { c in
            let keys = c.args.keys.sorted().joined(separator: ",")
            return "- \(c.tool.rawValue) id=\(c.id) args=\(keys)"
        }.joined(separator: "\n")
    }

    private func hubGrantTitle(_ grant: HubIPCClient.PendingGrantItem) -> String {
        XTHubGrantPresentation.capabilityLabel(
            capability: grant.capability,
            modelId: grant.modelId
        )
    }

    private func grantTimingText(_ createdAtMs: Double) -> String {
        guard createdAtMs > 0 else { return "待处理" }
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        let elapsedSec = max(0, Int((nowMs - createdAtMs) / 1000.0))
        if elapsedSec < 90 { return "刚刚" }
        let mins = elapsedSec / 60
        if mins < 60 { return "\(mins) 分钟前" }
        let hours = mins / 60
        if hours < 48 { return "\(hours) 小时前" }
        return "\(hours / 24) 天前"
    }

    private func memoryHealthSummary() -> String {
        let root = URL(fileURLWithPath: project.rootPath)
        let modern = root.appendingPathComponent(".xterminal", isDirectory: true)
        let legacy = root.appendingPathComponent(".xterminal", isDirectory: true)
        let fm = FileManager.default
        let dataDir: URL
        if fm.fileExists(atPath: modern.path) {
            dataDir = modern
        } else if fm.fileExists(atPath: legacy.path) {
            dataDir = legacy
        } else {
            return "未初始化（.xterminal 缺失）"
        }

        func exists(_ name: String) -> Bool {
            fm.fileExists(atPath: dataDir.appendingPathComponent(name).path)
        }

        let hasMem = exists("ax_memory.json")
        let hasRecent = exists("recent_context.json")
        let hasRaw = exists("raw_log.jsonl")

        var recentEmpty = false
        if hasRecent {
            let ctx = AXProjectContext(root: root)
            recentEmpty = AXRecentContextStore.load(for: ctx).messages.isEmpty
        }

        if hasMem && hasRecent && !recentEmpty { return "OK" }

        var missing: [String] = []
        if !hasMem { missing.append("ax_memory.json") }
        if !hasRecent { missing.append("recent_context.json") }
        if missing.isEmpty { return "OK" }

        var out = "缺失: " + missing.joined(separator: ", ")
        if missing.contains("recent_context.json") {
            out += hasRaw ? "（可从 raw_log 回填）" : "（raw_log 也缺失）"
        }
        return out
    }

    private enum HomeSummaryTone {
        case info
        case warning
        case invalid

        var color: Color {
            switch self {
            case .info:
                return .blue
            case .warning:
                return .orange
            case .invalid:
                return .red
            }
        }

        var iconName: String {
            switch self {
            case .info:
                return "lock.shield"
            case .warning:
                return "exclamationmark.triangle.fill"
            case .invalid:
                return "xmark.octagon.fill"
            }
        }
    }

    private func governanceAxisSummary(
        _ presentation: ProjectGovernancePresentation
    ) -> String {
        "\(presentation.effectiveExecutionLabel) / \(presentation.effectiveSupervisorLabel) · \(presentation.reviewPolicyMode.displayName)"
    }

    private func governedSummary(
        _ governed: AXProjectGovernedAuthorityPresentation
    ) -> String {
        var parts: [String] = []
        if governed.deviceAuthorityConfigured {
            parts.append("设备绑定")
        }
        if governed.governedReadableRootCount > 0 {
            parts.append("read+\(governed.governedReadableRootCount)")
        }
        if governed.localAutoApproveConfigured {
            parts.append("local auto")
        }
        return parts.isEmpty ? "人工审批" : parts.joined(separator: " · ")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}


struct GlobalHomePresentationInput: Codable, Equatable {
    let hubInteractive: Bool
    let projectCount: Int
    let runningProjectCount: Int
    let pendingGrantCount: Int
    let highlightedProjectName: String?
    let autoConfirmPolicy: String?
    let autoLaunchPolicy: String?
    let grantGateMode: String?
    let directedUnblockBatonCount: Int
    let nextDirectedResumeAction: String?
    let nextDirectedResumeLane: String?
    let scopeFreezeDecision: String?
    let scopeFreezeValidatedScope: [String]
    let allowedPublicStatementCount: Int
    let scopeFreezeBlockedExpansionItems: [String]
    let scopeFreezeNextActions: [String]
    let deniedLaunchCount: Int
    let topLaunchDenyCode: String?
    let replayPass: Bool?
    let replayScenarioCount: Int
    let replayFailClosedScenarioCount: Int
    let replayEvidenceRefs: [String]

    init(
        hubInteractive: Bool,
        projectCount: Int,
        runningProjectCount: Int,
        pendingGrantCount: Int,
        highlightedProjectName: String?,
        autoConfirmPolicy: String? = nil,
        autoLaunchPolicy: String? = nil,
        grantGateMode: String? = nil,
        directedUnblockBatonCount: Int = 0,
        nextDirectedResumeAction: String? = nil,
        nextDirectedResumeLane: String? = nil,
        scopeFreezeDecision: String? = nil,
        scopeFreezeValidatedScope: [String] = [],
        allowedPublicStatementCount: Int = 0,
        scopeFreezeBlockedExpansionItems: [String] = [],
        scopeFreezeNextActions: [String] = [],
        deniedLaunchCount: Int = 0,
        topLaunchDenyCode: String? = nil,
        replayPass: Bool? = nil,
        replayScenarioCount: Int = 0,
        replayFailClosedScenarioCount: Int = 0,
        replayEvidenceRefs: [String] = []
    ) {
        self.hubInteractive = hubInteractive
        self.projectCount = projectCount
        self.runningProjectCount = runningProjectCount
        self.pendingGrantCount = pendingGrantCount
        self.highlightedProjectName = highlightedProjectName
        self.autoConfirmPolicy = autoConfirmPolicy
        self.autoLaunchPolicy = autoLaunchPolicy
        self.grantGateMode = grantGateMode
        self.directedUnblockBatonCount = directedUnblockBatonCount
        self.nextDirectedResumeAction = nextDirectedResumeAction
        self.nextDirectedResumeLane = nextDirectedResumeLane
        self.scopeFreezeDecision = scopeFreezeDecision
        self.scopeFreezeValidatedScope = scopeFreezeValidatedScope
        self.allowedPublicStatementCount = allowedPublicStatementCount
        self.scopeFreezeBlockedExpansionItems = scopeFreezeBlockedExpansionItems
        self.scopeFreezeNextActions = scopeFreezeNextActions
        self.deniedLaunchCount = deniedLaunchCount
        self.topLaunchDenyCode = topLaunchDenyCode
        self.replayPass = replayPass
        self.replayScenarioCount = replayScenarioCount
        self.replayFailClosedScenarioCount = replayFailClosedScenarioCount
        self.replayEvidenceRefs = replayEvidenceRefs
    }

    enum CodingKeys: String, CodingKey {
        case hubInteractive = "hub_interactive"
        case projectCount = "project_count"
        case runningProjectCount = "running_project_count"
        case pendingGrantCount = "pending_grant_count"
        case highlightedProjectName = "highlighted_project_name"
        case autoConfirmPolicy = "auto_confirm_policy"
        case autoLaunchPolicy = "auto_launch_policy"
        case grantGateMode = "grant_gate_mode"
        case directedUnblockBatonCount = "directed_unblock_baton_count"
        case nextDirectedResumeAction = "next_directed_resume_action"
        case nextDirectedResumeLane = "next_directed_resume_lane"
        case scopeFreezeDecision = "scope_freeze_decision"
        case scopeFreezeValidatedScope = "scope_freeze_validated_scope"
        case allowedPublicStatementCount = "allowed_public_statement_count"
        case scopeFreezeBlockedExpansionItems = "scope_freeze_blocked_expansion_items"
        case scopeFreezeNextActions = "scope_freeze_next_actions"
        case deniedLaunchCount = "denied_launch_count"
        case topLaunchDenyCode = "top_launch_deny_code"
        case replayPass = "replay_pass"
        case replayScenarioCount = "replay_scenario_count"
        case replayFailClosedScenarioCount = "replay_fail_closed_scenario_count"
        case replayEvidenceRefs = "replay_evidence_refs"
    }
}

struct GlobalHomePresentation: Codable, Equatable {
    let informationArchitecture: XTUIInformationArchitectureContract
    let badge: ValidatedScopePresentation
    let primaryStatus: StatusExplanation
    let releaseStatus: StatusExplanation
    let actions: [PrimaryActionRailAction]
    let consumedFrozenFields: [String]

    enum CodingKeys: String, CodingKey {
        case informationArchitecture = "information_architecture"
        case badge
        case primaryStatus = "primary_status"
        case releaseStatus = "release_status"
        case actions
        case consumedFrozenFields = "consumed_frozen_fields"
    }

    @MainActor
    static func fromRuntime(appModel: AppModel, pendingGrantCount: Int) -> GlobalHomePresentation {
        let runningProjectCount = appModel.sortedProjects.reduce(into: 0) { partial, project in
            if appModel.sessionForProjectId(project.projectId)?.isSending == true {
                partial += 1
            }
        }

        let orchestrator = appModel.supervisor.orchestrator
        let monitor = orchestrator?.executionMonitor
        let runtimePolicy = orchestrator?.oneShotAutonomyPolicy
        let scopeFreeze = orchestrator?.latestDeliveryScopeFreeze
        let replayReport = orchestrator?.latestReplayHarnessReport
        let laneLaunchDecisions = orchestrator?.laneLaunchDecisions.values.map { $0 } ?? []
        let deniedLaunches = laneLaunchDecisions
            .filter { $0.autoLaunchAllowed == false || $0.decision != .allow }
            .sorted { lhs, rhs in
                lhs.laneID.localizedCaseInsensitiveCompare(rhs.laneID) == .orderedAscending
            }
        let nextBaton = monitor?.directedUnblockBatons.first

        return map(
            input: GlobalHomePresentationInput(
                hubInteractive: appModel.hubInteractive,
                projectCount: appModel.sortedProjects.count,
                runningProjectCount: runningProjectCount,
                pendingGrantCount: pendingGrantCount,
                highlightedProjectName: appModel.preferredResumeProject()?.projectDisplayName ?? appModel.sortedProjects.first?.displayName,
                autoConfirmPolicy: runtimePolicy?.autoConfirmPolicy.rawValue,
                autoLaunchPolicy: runtimePolicy?.autoLaunchPolicy.rawValue,
                grantGateMode: runtimePolicy?.grantGateMode,
                directedUnblockBatonCount: monitor?.directedUnblockBatons.count ?? 0,
                nextDirectedResumeAction: nextBaton?.nextAction,
                nextDirectedResumeLane: nextBaton?.blockedLane,
                scopeFreezeDecision: scopeFreeze?.decision.rawValue,
                scopeFreezeValidatedScope: scopeFreeze?.validatedScope ?? [],
                allowedPublicStatementCount: scopeFreeze?.allowedPublicStatements.count ?? 0,
                scopeFreezeBlockedExpansionItems: scopeFreeze?.blockedExpansionItems ?? [],
                scopeFreezeNextActions: scopeFreeze?.nextActions ?? [],
                deniedLaunchCount: deniedLaunches.count,
                topLaunchDenyCode: deniedLaunches.first?.denyCode,
                replayPass: replayReport?.pass,
                replayScenarioCount: replayReport?.scenarios.count ?? 0,
                replayFailClosedScenarioCount: replayReport?.scenarios.filter { $0.failClosed }.count ?? 0,
                replayEvidenceRefs: replayReport?.evidenceRefs ?? []
            )
        )
    }

    static func map(input: GlobalHomePresentationInput) -> GlobalHomePresentation {
        let architecture = XTUIInformationArchitectureContract.frozen
        let badge = ValidatedScopePresentation.validatedMainlineOnly
        let freezeDecision = input.scopeFreezeDecision ?? "pending"
        let validatedScope = input.scopeFreezeValidatedScope.isEmpty ? badge.validatedPaths : input.scopeFreezeValidatedScope
        let replayStatus: String
        if let replayPass = input.replayPass {
            replayStatus = replayPass ? "pass" : "fail"
        } else {
            replayStatus = "pending"
        }
        let machineStatusRef = "hub_interactive=\(input.hubInteractive); projects=\(input.projectCount); running=\(input.runningProjectCount); pending_grants=\(input.pendingGrantCount); auto_launch=\(input.autoLaunchPolicy ?? "none"); freeze=\(freezeDecision); denied_launches=\(input.deniedLaunchCount); batons=\(input.directedUnblockBatonCount); replay=\(replayStatus)"
        let contractSummary = [
            input.autoConfirmPolicy.map { "auto_confirm=\($0)" },
            input.autoLaunchPolicy.map { "auto_launch=\($0)" },
            input.grantGateMode.map { "grant_gate=\($0)" },
            "freeze=\(freezeDecision)",
            "replay=\(replayStatus)"
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        let directedResumeSummary = input.nextDirectedResumeAction.map { action in
            let laneSuffix = input.nextDirectedResumeLane.map { " @ \($0)" } ?? ""
            return "\(action)\(laneSuffix)"
        }
        let topDenyCode = input.topLaunchDenyCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let primaryStatus: StatusExplanation
        if !input.hubInteractive {
            primaryStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "Hub 未连接，先 Pair Hub 再进入项目总览（Project watchlist）",
                whatHappened: "Home 已经是正式入口，但还没连上 Hub，所以不会把状态装成可直接开始。",
                whyItHappened: "未连 Hub 时，授权、远端密钥和真实连接状态都必须直接说明，不能被首页入口遮掉。",
                userAction: "点击“Pair Hub”，完成连接后回首页（Home）查看 project 状态；大任务从 Supervisor 窗口发起。",
                machineStatusRef: machineStatusRef,
                hardLine: "remote_secret_blocked / require-real remain fail-closed",
                highlights: [
                    contractSummary,
                    "diagnostic_entrypoint=pairing_health"
                ].filter { !$0.isEmpty }
            )
        } else if topDenyCode == "permission_denied" {
            primaryStatus = StatusExplanation(
                state: .permissionDenied,
                headline: "检测到 permission_denied，首页继续保持 fail-closed",
                whatHappened: "运行时返回了 permission_denied，所以 Home 不会继续把当前状态显示成可直接开始。",
                whyItHappened: "权限拒绝必须在主入口直接可见，避免被项目列表和普通状态提示掩盖。",
                userAction: directedResumeSummary ?? "先修复权限链路，再重新发起复杂任务或恢复当前任务。",
                machineStatusRef: machineStatusRef,
                hardLine: "permission_denied remains explicit",
                highlights: [
                    contractSummary,
                    "top_launch_deny_code=permission_denied"
                ].filter { !$0.isEmpty }
            )
        } else if input.pendingGrantCount > 0 || topDenyCode == "grant_required" {
            primaryStatus = StatusExplanation(
                state: .grantRequired,
                headline: "存在授权待处理，主入口保持 fail-closed",
                whatHappened: "系统检测到这条链路还需要人工授权，所以不会显示成已完成或可自动继续。",
                whyItHappened: "授权没完成前，首页要明确挡住高风险动作，而不是默认放行。",
                userAction: directedResumeSummary ?? "先处理授权，再返回项目或进入 Supervisor 窗口继续推进。",
                machineStatusRef: machineStatusRef,
                hardLine: "grant_fail_closed must remain visible",
                highlights: [
                    contractSummary,
                    input.grantGateMode.map { "grant_gate_mode=\($0)" } ?? ""
                ].filter { !$0.isEmpty }
            )
        } else if topDenyCode == "scope_expansion" || freezeDecision == "no_go" || !input.scopeFreezeBlockedExpansionItems.isEmpty {
            let blockedItems = input.scopeFreezeBlockedExpansionItems.joined(separator: ",")
            primaryStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "已验证范围拒绝超范围请求",
                whatHappened: "当前请求已经落在 no-go / blocked expansion，所以首页不会再暗示这条路可以放行。",
                whyItHappened: "现在只允许已验证主链，超范围请求必须继续挡住。",
                userAction: input.scopeFreezeNextActions.first ?? "先收回 scope expansion",
                machineStatusRef: machineStatusRef,
                hardLine: "scope_not_validated must remain visible",
                highlights: [
                    contractSummary,
                    blockedItems.isEmpty ? "" : "blocked_expansion=\(blockedItems)"
                ].filter { !$0.isEmpty }
            )
        } else if input.replayPass == false {
            primaryStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "replay regression 尚未通过，入口保持 explainable hold",
                whatHappened: "回放回归还没通过，说明之前的阻断场景还需要复核。",
                whyItHappened: "回放没变绿之前，首页不能暗示当前发布口径已经稳定。",
                userAction: input.replayEvidenceRefs.first ?? "先查看 replay 证据",
                machineStatusRef: machineStatusRef,
                hardLine: "replay fail-closed remains visible",
                highlights: [
                    contractSummary,
                    "replay_fail_closed_scenarios=\(input.replayFailClosedScenarioCount)/\(input.replayScenarioCount)"
                ].filter { !$0.isEmpty }
            )
        } else if input.runningProjectCount > 0 {
            primaryStatus = StatusExplanation(
                state: .inProgress,
                headline: "已有 \(input.runningProjectCount) 个复杂任务在推进",
                whatHappened: "当前有复杂任务正在推进，首页会把关键运行状态一起摘要出来。",
                whyItHappened: "这样你在 Home 也能先看进度、阻塞和下一步，而不用先切进聊天流水。",
                userAction: directedResumeSummary ?? "点击“继续当前项目”或进入 Supervisor 查看 planner explain / blocker / next action。",
                machineStatusRef: machineStatusRef,
                hardLine: "validated-mainline-only; no_unverified_claims",
                highlights: [
                    contractSummary,
                    "allowed_public_statements=\(input.allowedPublicStatementCount)"
                ].filter { !$0.isEmpty }
            )
        } else {
            let headline = input.projectCount == 0 ? "项目总览（Project watchlist）已就绪，等待第一个项目" : "项目总览（Project watchlist）已同步，可继续当前项目"
            let nextAction = directedResumeSummary
                ?? (input.projectCount == 0
                    ? "先创建一个 project；如需发起大任务，请从 Supervisor 窗口进入。"
                    : "继续当前项目；需要新的大任务时，从 Supervisor 窗口发起。")
            primaryStatus = StatusExplanation(
                state: .ready,
                headline: headline,
                whatHappened: "Home 现在只负责项目汇总、继续当前项目和诊断入口，主入口已经收口。",
                whyItHappened: "新的复杂任务统一从 Supervisor 发起，Home 不再承担大任务入口。",
                userAction: nextAction,
                machineStatusRef: machineStatusRef,
                hardLine: "validated-mainline-only remains the only external scope",
                highlights: [
                    contractSummary,
                    "primary_cta=resume_project"
                ].filter { !$0.isEmpty }
            )
        }

        let releaseState: XTUISurfaceState
        if freezeDecision == "no_go" || !input.scopeFreezeBlockedExpansionItems.isEmpty {
            releaseState = .blockedWaitingUpstream
        } else if input.replayPass == false {
            releaseState = .diagnosticRequired
        } else {
            releaseState = .releaseFrozen
        }

        let releaseStatus = StatusExplanation(
            state: releaseState,
            headline: "已验证主链当前冻结为 \(validatedScope.joined(separator: " → "))",
            whatHappened: "首页会明确显示“Validated mainline only”，并把范围与 replay 摘要一起说明。",
            whyItHappened: "这里现在只围绕已验证主链对外表达，不把未验证功能重新拉回本轮。",
            userAction: input.scopeFreezeNextActions.first
                ?? input.replayEvidenceRefs.first
                ?? "如需新 surface，请另起切片；当前只围绕已验证主链继续验证与交付。",
            machineStatusRef: "current_release_scope=\(badge.currentReleaseScope); validated_paths=\(validatedScope.joined(separator: ",")); decision=\(freezeDecision); allowed_public_statements=\(input.allowedPublicStatementCount); replay=\(replayStatus)",
            hardLine: "scope_not_validated must remain visible",
            highlights: [
                "external_messaging=frozen",
                "no_scope_expansion=\((freezeDecision == "no_go" || !input.scopeFreezeBlockedExpansionItems.isEmpty) ? "false" : "true")",
                "replay_fail_closed_scenarios=\(input.replayFailClosedScenarioCount)/\(input.replayScenarioCount)"
            ] + input.scopeFreezeBlockedExpansionItems.prefix(3).map { "blocked_item=\($0)" }
        )

        var actions: [PrimaryActionRailAction] = []
        if input.projectCount > 0 {
            actions.append(
                PrimaryActionRailAction(
                    id: "resume_project",
                    title: input.highlightedProjectName.map { "继续 \($0)" } ?? "继续当前项目",
                    subtitle: "回到最近项目，查看 blocker / next action",
                    systemImage: "arrow.clockwise.circle",
                    style: .primary
                )
            )
        }
        actions.append(
                PrimaryActionRailAction(
                    id: "pair_hub",
                    title: "连接 Hub（Pair Hub）",
                    subtitle: input.grantGateMode.map { "连接 Hub 真正数据源；grant gate=\($0)" } ?? "连接 Hub 真正数据源，打通授权链和主入口",
                    systemImage: "cable.connector",
                    style: .secondary
            )
        )
        actions.append(
            PrimaryActionRailAction(
                id: "model_status",
                title: "模型状态",
                subtitle: "freeze=\(freezeDecision) · replay=\(replayStatus) · batons=\(input.directedUnblockBatonCount)",
                systemImage: "waveform.path.ecg",
                style: .diagnostic
            )
        )

        return GlobalHomePresentation(
            informationArchitecture: architecture,
            badge: badge,
            primaryStatus: primaryStatus,
            releaseStatus: releaseStatus,
            actions: actions,
            consumedFrozenFields: [
                "xt.ui_information_architecture.v1.primary_actions.xt.global_home",
                "xt.ui_design_token_bundle.v1.surface_tokens",
                "xt.ui_surface_state_contract.v1.required_fields",
                "xt.ui_release_scope_badge.v1.badge_text",
                "xt.unblock_baton.v1.next_action",
                "xt.delivery_scope_freeze.v1.validated_scope",
                "xt.one_shot_autonomy_policy.v1.auto_launch_policy",
                "xt.one_shot_replay_regression.v1.scenarios"
            ]
        )
    }
}
