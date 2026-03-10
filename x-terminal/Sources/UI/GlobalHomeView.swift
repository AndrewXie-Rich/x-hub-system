import Foundation
import SwiftUI
import AppKit

struct GlobalHomeView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
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
                Text("Global Home")
                    .font(UIThemeTokens.heroFont())
                Text("开始复杂任务、解释当前发生了什么，以及为什么只能沿 validated mainline 推进。")
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
            PrimaryActionRail(
                title: "Primary Actions",
                actions: presentation.actions,
                onTap: handleHomeAction
            )

            StatusExplanationCard(explanation: presentation.primaryStatus)
            StatusExplanationCard(explanation: presentation.releaseStatus)
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
            headline: "先从一个复杂任务开始，再让首页持续显示 blocker / next action",
            whatHappened: "当前还没有已登记项目，但首页主入口、validated scope badge 与 fail-closed 文案已经就绪。",
            whyItHappened: "本轮 claim 只冻结 XT-W3-27-A/B/C/D，不等待未验证 surface 或后端补齐后才开始 UI 产品化。",
            userAction: appModel.hubInteractive ? "点击“开始大任务”，把复杂任务送入 Supervisor one-shot intake。" : "先点击“Pair Hub”，完成连接后再点击“开始大任务”。",
            machineStatusRef: "projects=0; hub_interactive=\(appModel.hubInteractive)",
            hardLine: "validated-mainline-only; no_scope_expansion",
            highlights: [
                "badge_text=Validated mainline only",
                "primary_cta=start_big_task"
            ]
        )

        return StatusExplanationCard(explanation: explanation)
    }

    private var projectsSection: some View {
        let projectSessions: [(project: AXProjectEntry, session: ChatSessionModel)] = appModel.sortedProjects.compactMap { project in
            guard let session = appModel.sessionForProjectId(project.projectId) else { return nil }
            return (project, session)
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Project Watchlist")
                .font(UIThemeTokens.sectionFont())
            Text("先在产品入口理解 what happened / why / next action，再进入具体项目执行。")
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
        case "start_big_task":
            openSupervisor()
        case "resume_project":
            if let project = appModel.sortedProjects.first {
                appModel.selectProject(project.projectId)
            } else {
                openSupervisor()
            }
        case "pair_hub":
            openWindow(id: "hub_setup")
        case "model_status":
            openWindow(id: "model_settings")
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

    private func openSupervisor() {
        openWindow(id: "supervisor")
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
                    decisionDrafts[projectId] = "Hub 授权审批失败（\(result.reasonCode ?? "unknown")）：grant_request_id=\(grantId)"
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
                    decisionDrafts[projectId] = "Hub 授权拒绝失败（\(result.reasonCode ?? "unknown")）：grant_request_id=\(grantId)"
                }
            }
            await refreshPendingGrants()
        }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.displayName)
                    .font(.headline)
                Spacer(minLength: 8)
                Text("更新：\(timeText(project.lastSummaryAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open") {
                    appModel.selectProject(project.projectId)
                }
            }

            let digest = (project.statusDigest ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let stateValue = (project.currentStateSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            row(title: "状态", value: stateValue.isEmpty ? digest : stateValue, placeholder: "未生成")
            row(title: "记忆", value: memoryHealthSummary(), placeholder: "未知")
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
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hubGrantTitle(grant))
                                .font(.subheadline)
                            Text("grant=\(grantId) · \(grantTimingText(grant.createdAtMs))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 8)
                        if inFlight {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Approve") {
                            onApprovePendingGrant(grant)
                        }
                        .disabled(inFlight || !appModel.hubInteractive)
                        Button("Deny") {
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

    private func timeText(_ ts: Double?) -> String {
        guard let ts, ts > 0 else { return "未更新" }
        let d = Date(timeIntervalSince1970: ts)
        return Self.timeFormatter.string(from: d)
    }

    @ViewBuilder
    private func row(title: String, value: String?, placeholder: String) -> some View {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Text("\(title)：\(placeholder)")
                .foregroundStyle(.secondary)
        } else {
            Text("\(title)：\(trimmed)")
        }
    }

    private func pendingSummary(_ calls: [ToolCall]) -> String {
        calls.map { c in
            let keys = c.args.keys.sorted().joined(separator: ",")
            return "- \(c.tool.rawValue) id=\(c.id) args=\(keys)"
        }.joined(separator: "\n")
    }

    private func hubGrantTitle(_ grant: HubIPCClient.PendingGrantItem) -> String {
        let capability = grant.capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let modelId = grant.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = grant.reason.trimmingCharacters(in: .whitespacesAndNewlines)

        let capabilityLabel: String
        if capability.contains("web_fetch") || capability.contains("web.fetch") {
            capabilityLabel = "联网访问"
        } else if capability.contains("ai_generate_paid") || capability.contains("ai.generate.paid") {
            capabilityLabel = modelId.isEmpty ? "付费模型调用" : "付费模型调用（\(modelId)）"
        } else if capability.contains("ai_generate_local") || capability.contains("ai.generate.local") {
            capabilityLabel = modelId.isEmpty ? "本地模型调用" : "本地模型调用（\(modelId)）"
        } else if capability.isEmpty {
            capabilityLabel = "高风险能力"
        } else {
            capabilityLabel = grant.capability
        }

        if reason.isEmpty {
            return capabilityLabel
        }
        return "\(capabilityLabel) · \(reason)"
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
                highlightedProjectName: appModel.sortedProjects.first?.displayName,
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
                headline: "Hub 未连接，先 Pair Hub 再开始大任务",
                whatHappened: "Global Home 已切成产品入口，但当前缺少 Hub truth source，因此不会把入口伪装成可直接放行。",
                whyItHappened: "冻结契约要求 require-real、grant 与 secret 边界继续 fail-closed；未连 Hub 时不得隐藏阻塞原因。",
                userAction: "点击“Pair Hub”，完成连接后回到“开始大任务”进入 one-shot 主链。",
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
                headline: "runtime deny 检出 permission_denied，首页保持 fail-closed",
                whatHappened: "AI-2 runtime launch decision 返回 permission_denied；Global Home 不会继续把当前状态渲染为可直接开始。",
                whyItHappened: "真实 runtime 合同要求权限拒绝必须在入口显式可见，而不是被 project list 掩盖。",
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
                whatHappened: "首页检测到高风险链路需要人工授权，因此不会把当前状态渲染成已完成或可自动继续。",
                whyItHappened: "冻结契约要求 grant_required 明示可见，未授权前不得越过 require-real、远端 secret 或副作用边界。",
                userAction: directedResumeSummary ?? "先处理授权，再返回“开始大任务”或“继续当前项目”继续推进。",
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
                headline: "validated scope freeze 拒绝超范围请求",
                whatHappened: "Global Home 已读取 delivery scope freeze 的 no-go / blocked expansion 状态，因此入口不会继续暗示当前请求可放行。",
                whyItHappened: "validated-mainline-only 是当前唯一允许范围；scope expansion 必须留在 fail-closed。",
                userAction: input.scopeFreezeNextActions.first ?? "drop_scope_expansion",
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
                whatHappened: "AI-2 replay harness 当前未 pass，说明 fail-closed 回归还需要复核。",
                whyItHappened: "入口不能在 replay 未绿时暗示对外 release 语义已经稳定。",
                userAction: input.replayEvidenceRefs.first ?? "review replay regression evidence",
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
                whatHappened: "Global Home 检测到当前存在运行中的复杂任务，并附带 AI-2 runtime contract 摘要。",
                whyItHappened: "AI-3 现已直接消费 runtime policy / freeze / replay / baton，不再只停留在 mock state mapping。",
                userAction: directedResumeSummary ?? "点击“继续当前项目”或进入 Supervisor 查看 planner explain / blocker / next action。",
                machineStatusRef: machineStatusRef,
                hardLine: "validated-mainline-only; no_unverified_claims",
                highlights: [
                    contractSummary,
                    "allowed_public_statements=\(input.allowedPublicStatementCount)"
                ].filter { !$0.isEmpty }
            )
        } else {
            let headline = input.projectCount == 0 ? "开始一个复杂任务，直接进入 validated mainline" : "主入口已就绪，可开始新的复杂任务"
            let nextAction = directedResumeSummary
                ?? (input.projectCount == 0
                    ? "点击“开始大任务”，让 Supervisor 从 one-shot intake 开始推进。"
                    : "继续当前项目，或直接点击“开始大任务”发起下一条复杂任务主链。")
            primaryStatus = StatusExplanation(
                state: .ready,
                headline: headline,
                whatHappened: "首页已把 Global Home、scope badge 与主 CTA 冻结为产品入口，并接入 runtime contracts 的摘要状态。",
                whyItHappened: "XT-W3-27-C 要求首页先清楚表达 what happened / why / next action，并把复杂任务入口前置。",
                userAction: nextAction,
                machineStatusRef: machineStatusRef,
                hardLine: "validated-mainline-only remains the only external scope",
                highlights: [
                    contractSummary,
                    "primary_cta=开始大任务"
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
            headline: "Validated scope 已冻结为 \(validatedScope.joined(separator: " → "))",
            whatHappened: "首页显式展示“Validated mainline only”，并把 scope freeze / replay 摘要纳入 release 说明。",
            whyItHappened: "R1 UI 产品化只消费 validated mainline，不重新把未纳入主链的功能拉回本轮范围。",
            userAction: input.scopeFreezeNextActions.first
                ?? input.replayEvidenceRefs.first
                ?? "如需新 surface，请另起切片；当前只围绕 validated mainline 继续验证与交付。",
            machineStatusRef: "current_release_scope=\(badge.currentReleaseScope); validated_paths=\(validatedScope.joined(separator: ",")); decision=\(freezeDecision); allowed_public_statements=\(input.allowedPublicStatementCount); replay=\(replayStatus)",
            hardLine: "scope_not_validated must remain visible",
            highlights: [
                "external_messaging=frozen",
                "no_scope_expansion=\((freezeDecision == "no_go" || !input.scopeFreezeBlockedExpansionItems.isEmpty) ? "false" : "true")",
                "replay_fail_closed_scenarios=\(input.replayFailClosedScenarioCount)/\(input.replayScenarioCount)"
            ] + input.scopeFreezeBlockedExpansionItems.prefix(3).map { "blocked_item=\($0)" }
        )

        let actions = [
            PrimaryActionRailAction(
                id: "start_big_task",
                title: "开始大任务",
                subtitle: directedResumeSummary ?? "进入 one-shot intake，并把复杂任务送进 validated mainline",
                systemImage: "play.circle.fill",
                style: .primary
            ),
            PrimaryActionRailAction(
                id: "resume_project",
                title: input.highlightedProjectName.map { "继续 \($0)" } ?? "继续当前项目",
                subtitle: input.projectCount > 0 ? "回到最近项目，查看 blocker / next action" : "暂无项目时回到主入口，不扩 scope",
                systemImage: "arrow.clockwise.circle",
                style: .secondary
            ),
            PrimaryActionRailAction(
                id: "pair_hub",
                title: "Pair Hub",
                subtitle: input.grantGateMode.map { "连接 Hub truth source；grant gate=\($0)" } ?? "连接 Hub truth source、授权链与 require-real 主入口",
                systemImage: "cable.connector",
                style: .secondary
            ),
            PrimaryActionRailAction(
                id: "model_status",
                title: "模型状态",
                subtitle: "freeze=\(freezeDecision) · replay=\(replayStatus) · batons=\(input.directedUnblockBatonCount)",
                systemImage: "waveform.path.ecg",
                style: .diagnostic
            )
        ]

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
