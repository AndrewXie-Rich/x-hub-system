import SwiftUI

struct SupervisorView: View {
    @StateObject private var supervisor = SupervisorManager.shared
    @State private var inputText: String = ""
    @State private var autoSendVoice: Bool = true
    @State private var conversationFocusRequestID: Int = 0
    @State private var laneHealthFilter: LaneHealthFilter = .abnormal
    @State private var focusedSplitLaneID: String?
    @State private var selectedPortfolioProjectID: String?
    @State private var selectedPortfolioDrillDownScope: SupervisorProjectDrillDownScope = .capsuleOnly
    @State private var selectedSupervisorSkillRecord: SupervisorSkillRecordSheetState?
    @State private var highlightedPendingSupervisorSkillApprovalAnchor: String?
    @State private var highlightedPendingHubGrantAnchor: String?
    @State private var supervisorFocusRefreshAttemptNonce: Int?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: AppModel

    private enum LaneHealthFilter: CaseIterable, Hashable {
        case all
        case abnormal
        case running
        case blocked
        case stalled
        case failed

        var label: String {
            switch self {
            case .all: return "全部"
            case .abnormal: return "异常"
            case .running: return "运行中"
            case .blocked: return "阻塞"
            case .stalled: return "停滞"
            case .failed: return "失败"
            }
        }
    }

    private enum DashboardFocusAnchor: String {
        case pendingSupervisorSkillApprovalBoard = "supervisor.dashboard.pendingSupervisorSkillApprovalBoard"
        case pendingHubGrantBoard = "supervisor.dashboard.pendingHubGrantBoard"
    }
    
    private var cockpitPresentation: SupervisorCockpitPresentation {
        SupervisorCockpitPresentation.fromRuntime(
            supervisorManager: supervisor,
            orchestrator: appModel.supervisor.orchestrator,
            monitor: appModel.supervisor.orchestrator.executionMonitor
        )
    }

    private var selectedAutomationProject: AXProjectEntry? {
        guard let projectID = appModel.selectedProjectId,
              projectID != AXProjectRegistry.globalHomeId else {
            return nil
        }
        return appModel.registry.project(for: projectID)
    }

    private var selectedAutomationRecipe: AXAutomationRecipeRuntimeBinding? {
        guard selectedAutomationProject != nil else { return nil }
        return appModel.projectConfig?.activeAutomationRecipe
    }

    private var selectedAutomationLastLaunchRef: String {
        guard selectedAutomationProject != nil else { return "" }
        return (appModel.projectConfig?.lastAutomationLaunchRef ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header

                Divider()

                ScrollViewReader { dashboardScrollProxy in
                    // Keep operations panels scrollable so the chat composer remains reachable
                    // even when dashboard cards grow taller than the window.
                    ScrollView {
                        dashboardBoards
                    }
                    .frame(maxHeight: dashboardPanelMaxHeight(totalHeight: proxy.size.height))
                    .onAppear {
                        processSupervisorFocusRequest(using: dashboardScrollProxy)
                    }
                    .onChange(of: appModel.supervisorFocusRequest?.nonce) { _ in
                        processSupervisorFocusRequest(using: dashboardScrollProxy)
                    }
                    .onChange(of: supervisor.pendingHubGrants) { _ in
                        processSupervisorFocusRequest(using: dashboardScrollProxy)
                    }
                    .onChange(of: supervisor.pendingSupervisorSkillApprovals) { _ in
                        processSupervisorFocusRequest(using: dashboardScrollProxy)
                    }
                }

                Divider()

                SupervisorConversationPanel(
                    supervisor: supervisor,
                    inputText: $inputText,
                    autoSendVoice: $autoSendVoice,
                    focusRequestID: conversationFocusRequestID
                )
                .frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            supervisor.setAppModel(appModel)
            supervisor.syncAutomationRuntimeSnapshot(forSelectedProject: selectedAutomationProject)
            supervisor.refreshSupervisorMemorySnapshotNow()
            requestConversationFocus()
        }
        .onChange(of: appModel.selectedProjectId) { _ in
            supervisor.syncAutomationRuntimeSnapshot(forSelectedProject: selectedAutomationProject)
        }
        .onChange(of: selectedAutomationLastLaunchRef) { _ in
            supervisor.syncAutomationRuntimeSnapshot(forSelectedProject: selectedAutomationProject)
        }
        .onChange(of: selectedPortfolioProjectID) { _ in
            refreshSelectedPortfolioDrillDown()
        }
        .onChange(of: selectedPortfolioDrillDownScope) { _ in
            refreshSelectedPortfolioDrillDown()
        }
        .onChange(of: supervisor.supervisorPortfolioSnapshot.updatedAt) { _ in
            refreshSelectedPortfolioDrillDown()
        }
        .sheet(item: $selectedSupervisorSkillRecord) { record in
            SupervisorSkillRecordSheet(record: record)
        }
    }

    @ViewBuilder
    private var dashboardBoards: some View {
        VStack(spacing: 0) {
            cockpitSummaryBoard
            Divider()
            supervisorPortfolioBoard
            Divider()
            supervisorMemoryBoard
            Divider()
            pendingSupervisorSkillApprovalBoard
                .id(DashboardFocusAnchor.pendingSupervisorSkillApprovalBoard.rawValue)
            Divider()
            recentSupervisorSkillActivityBoard
            Divider()
            supervisorEventLoopBoard
            Divider()
            pendingHubGrantBoard
                .id(DashboardFocusAnchor.pendingHubGrantBoard.rawValue)
            Divider()
            supervisorDoctorBoard
            Divider()
            automationRuntimeBoard
            Divider()
            splitProposalBoard
            Divider()
            laneHealthBoard
            Divider()
            xtReadyIncidentBoard
        }
    }

    private func dashboardPanelMaxHeight(totalHeight: CGFloat) -> CGFloat {
        let bounded = totalHeight * 0.42
        return min(max(180, bounded), 360)
    }

    private func todayQueuePriorityHint(_ items: [SupervisorPortfolioActionabilityItem]) -> String? {
        let names = Array(items.prefix(2)).map(\.projectName)
        guard !names.isEmpty else { return nil }
        return "建议优先处理：\(names.joined(separator: "、"))"
    }
    
    private var header: some View {
        let snapshot = ExecutionRoutePresentation.supervisorSnapshot(from: supervisor)
        let statusColor = supervisorHeaderStatusColor(snapshot: snapshot)
        let tooltip = ExecutionRoutePresentation.tooltip(
            configuredModelId: configuredSupervisorModelId,
            snapshot: snapshot
        )

        return HStack {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .foregroundColor(.accentColor)
                Text("Supervisor (\(ExecutionRoutePresentation.activeModelLabel(configuredModelId: configuredSupervisorModelId, snapshot: snapshot)))")
                    .font(.headline)
                    .help(tooltip)
                Text(supervisorHeaderStatusText(snapshot: snapshot))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())
                    .help(tooltip)
            }
            
            Spacer()
            
            if supervisor.isProcessing {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("处理中...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 8) {
                Button(action: { openWindow(id: "supervisor_settings") }) {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .help("Supervisor 设置")
                
                Button(action: { openWindow(id: "model_settings") }) {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.borderless)
                .help("AI 模型设置")
                
                Button("清空") {
                    supervisor.clearMessages()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var configuredSupervisorModelId: String {
        appModel.settingsStore.settings.assignment(for: .supervisor).model?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func supervisorHeaderStatusText(snapshot: AXRoleExecutionSnapshot) -> String {
        if snapshot.executionPath == "no_record" && !appModel.hubInteractive {
            return "Hub Off"
        }
        return ExecutionRoutePresentation.statusText(snapshot: snapshot)
    }

    private func supervisorHeaderStatusColor(snapshot: AXRoleExecutionSnapshot) -> Color {
        if snapshot.executionPath == "no_record" && !appModel.hubInteractive {
            return .red
        }
        return ExecutionRoutePresentation.statusColor(snapshot: snapshot)
    }

    private var cockpitSummaryBoard: some View {
        SupervisorCockpitSummarySection(
            supervisorManager: supervisor,
            orchestrator: appModel.supervisor.orchestrator,
            monitor: appModel.supervisor.orchestrator.executionMonitor,
            onTap: handleCockpitAction,
            onStageTap: handleRuntimeStageTap
        )
    }

    private func handleCockpitAction(_ action: PrimaryActionRailAction) {
        switch action.id {
        case "submit_intake":
            if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                inputText = "请开始一个复杂任务：目标 / 约束 / 交付物 / 风险"
            }
            requestConversationFocus()
        case "approve_risk":
            supervisor.refreshPendingHubGrantSnapshotNow()
        case "review_delivery":
            let replayPath = appModel.supervisor.orchestrator.latestReplayHarnessReport?.evidenceRefs.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let path = (replayPath.isEmpty ? cockpitPresentation.reviewReportPath : replayPath)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                openURL(URL(fileURLWithPath: path))
            } else {
                supervisor.refreshSupervisorDoctorReport()
            }
        default:
            break
        }
    }

    private func handleRuntimeStageTap(_ item: SupervisorRuntimeStageItemPresentation) {
        guard let actionID = item.actionID else { return }
        switch actionID {
        case "submit_intake":
            handleCockpitAction(
                PrimaryActionRailAction(
                    id: "submit_intake",
                    title: "",
                    subtitle: nil,
                    systemImage: "paperplane.circle.fill",
                    style: .primary
                )
            )
        case "review_delivery":
            handleCockpitAction(
                PrimaryActionRailAction(
                    id: "review_delivery",
                    title: "",
                    subtitle: nil,
                    systemImage: "doc.text.magnifyingglass",
                    style: .diagnostic
                )
            )
        case "resolve_access":
            resolveAccessStage()
        case "directed_resume":
            prepareDirectedResumeDraft()
        default:
            break
        }
    }

    private func resolveAccessStage() {
        if let action = supervisor.pendingHubGrants.first?.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: action),
           !action.isEmpty {
            openURL(url)
            return
        }
        if let action = supervisor.pendingSupervisorSkillApprovals.first?.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: action),
           !action.isEmpty {
            openURL(url)
            return
        }

        let accessSurface = cockpitPresentation.runtimeStageRail.items
            .first(where: { $0.id == "access" })?
            .surfaceState

        switch accessSurface {
        case .permissionDenied:
            openWindow(id: "model_settings")
        case .grantRequired:
            supervisor.refreshPendingHubGrantSnapshotNow()
            openWindow(id: "hub_setup")
        default:
            openWindow(id: "hub_setup")
        }
    }

    private func prepareDirectedResumeDraft() {
        guard let baton = appModel.supervisor.orchestrator.executionMonitor.directedUnblockBatons.first else {
            inputText = "请先说明当前 blocker 和目标 lane，再决定是否继续当前任务。"
            requestConversationFocus()
            return
        }

        let laneID = baton.blockedLane.trimmingCharacters(in: .whitespacesAndNewlines)
        if !laneID.isEmpty {
            focusedSplitLaneID = laneID
        }

        let draft = [
            "请只继续当前任务，不要扩 scope，不要 claim 新 lane。",
            laneID.isEmpty ? nil : "目标 lane=\(laneID)。",
            "next_action=\(baton.nextAction)。",
            baton.mustNotDo.isEmpty ? nil : "must_not_do=\(baton.mustNotDo.joined(separator: ","))。",
            "基于现有 directed unblock baton 续推，并显式汇报 blocker 是否已解除。"
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        inputText = draft
        requestConversationFocus()
    }

    private func requestConversationFocus() {
        conversationFocusRequestID += 1
    }

    private func processSupervisorFocusRequest(using scrollProxy: ScrollViewProxy) {
        guard let request = appModel.supervisorFocusRequest else { return }

        switch request.subject {
        case let .grant(grantRequestId, capability):
            processGrantFocusRequest(
                request,
                grantRequestId: grantRequestId,
                capability: capability,
                using: scrollProxy
            )
        case let .approval(requestId):
            processApprovalFocusRequest(
                request,
                requestId: requestId,
                using: scrollProxy
            )
        }
    }

    private func processApprovalFocusRequest(
        _ request: AXSupervisorFocusRequest,
        requestId: String,
        using scrollProxy: ScrollViewProxy
    ) {
        let resolvedProjectId = resolvedProjectIdForApprovalFocus(
            explicitProjectId: request.projectId,
            requestId: requestId
        )

        if let resolvedProjectId,
           !resolvedProjectId.isEmpty {
            selectedPortfolioProjectID = resolvedProjectId
            if appModel.selectedProjectId != resolvedProjectId {
                appModel.selectProject(resolvedProjectId)
            }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            scrollProxy.scrollTo(DashboardFocusAnchor.pendingSupervisorSkillApprovalBoard.rawValue, anchor: .center)
        }

        highlightedPendingHubGrantAnchor = nil

        if let approval = matchingPendingSupervisorSkillApproval(
            projectId: resolvedProjectId ?? request.projectId,
            requestId: requestId
        ) {
            let rowAnchor = pendingSupervisorSkillApprovalRowAnchor(approval)
            highlightedPendingSupervisorSkillApprovalAnchor = rowAnchor
            highlightedPendingHubGrantAnchor = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                scrollProxy.scrollTo(rowAnchor, anchor: .center)
            }
            completeSupervisorFocusRequest(request)
            return
        }

        highlightedPendingSupervisorSkillApprovalAnchor = nil

        if supervisor.pendingSupervisorSkillApprovals.isEmpty,
           supervisorFocusRefreshAttemptNonce != request.nonce {
            supervisorFocusRefreshAttemptNonce = request.nonce
            supervisor.refreshPendingSupervisorSkillApprovalsNow()
            return
        }

        completeSupervisorFocusRequest(request)
    }

    private func processGrantFocusRequest(
        _ request: AXSupervisorFocusRequest,
        grantRequestId: String?,
        capability: String?,
        using scrollProxy: ScrollViewProxy
    ) {
        let resolvedProjectId = resolvedProjectIdForGrantFocus(
            explicitProjectId: request.projectId,
            grantRequestId: grantRequestId,
            capability: capability
        )

        if let resolvedProjectId,
           !resolvedProjectId.isEmpty {
            selectedPortfolioProjectID = resolvedProjectId
            if appModel.selectedProjectId != resolvedProjectId {
                appModel.selectProject(resolvedProjectId)
            }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            scrollProxy.scrollTo(DashboardFocusAnchor.pendingHubGrantBoard.rawValue, anchor: .center)
        }

        highlightedPendingSupervisorSkillApprovalAnchor = nil

        if let grant = matchingPendingHubGrant(
            projectId: resolvedProjectId ?? request.projectId,
            grantRequestId: grantRequestId,
            capability: capability
        ) {
            let rowAnchor = pendingHubGrantRowAnchor(grant)
            highlightedPendingSupervisorSkillApprovalAnchor = nil
            highlightedPendingHubGrantAnchor = rowAnchor
            withAnimation(.easeInOut(duration: 0.2)) {
                scrollProxy.scrollTo(rowAnchor, anchor: .center)
            }
            completeSupervisorFocusRequest(request)
            return
        }

        highlightedPendingHubGrantAnchor = nil

        if supervisor.pendingHubGrants.isEmpty,
           supervisorFocusRefreshAttemptNonce != request.nonce {
            supervisorFocusRefreshAttemptNonce = request.nonce
            supervisor.refreshPendingHubGrantSnapshotNow()
            return
        }

        completeSupervisorFocusRequest(request)
    }

    private func resolvedProjectIdForApprovalFocus(
        explicitProjectId: String?,
        requestId: String
    ) -> String? {
        let explicit = normalizedFocusToken(explicitProjectId)
        if let explicit,
           !explicit.isEmpty {
            return explicit
        }
        return matchingPendingSupervisorSkillApproval(
            projectId: nil,
            requestId: requestId
        )?.projectId
    }

    private func resolvedProjectIdForGrantFocus(
        explicitProjectId: String?,
        grantRequestId: String?,
        capability: String?
    ) -> String? {
        let explicit = normalizedFocusToken(explicitProjectId)
        if let explicit,
           !explicit.isEmpty {
            return explicit
        }
        return matchingPendingHubGrant(
            projectId: nil,
            grantRequestId: grantRequestId,
            capability: capability
        )?.projectId
    }

    private func matchingPendingSupervisorSkillApproval(
        projectId: String?,
        requestId: String
    ) -> SupervisorManager.SupervisorPendingSkillApproval? {
        let normalizedProjectId = normalizedFocusToken(projectId)
        let normalizedRequestId = normalizedFocusToken(requestId)
        guard let normalizedRequestId,
              !normalizedRequestId.isEmpty else {
            return nil
        }

        return supervisor.pendingSupervisorSkillApprovals.first { approval in
            let projectMatches = normalizedProjectId == nil
                || approval.projectId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedProjectId
            return projectMatches
                && approval.requestId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedRequestId
        }
    }

    private func matchingPendingHubGrant(
        projectId: String?,
        grantRequestId: String?,
        capability: String?
    ) -> SupervisorManager.SupervisorPendingGrant? {
        let normalizedProjectId = normalizedFocusToken(projectId)
        let normalizedGrantId = normalizedFocusToken(grantRequestId)
        let normalizedCapability = normalizedFocusToken(capability)?.lowercased()

        if let normalizedGrantId,
           !normalizedGrantId.isEmpty {
            return supervisor.pendingHubGrants.first { grant in
                let projectMatches = normalizedProjectId == nil
                    || grant.projectId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedProjectId
                return projectMatches
                    && grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedGrantId
            }
        }

        guard let normalizedCapability,
              !normalizedCapability.isEmpty else {
            return nil
        }

        let candidates = supervisor.pendingHubGrants.filter { grant in
            let projectMatches = normalizedProjectId == nil
                || grant.projectId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedProjectId
            return projectMatches
                && grant.capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedCapability
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private func completeSupervisorFocusRequest(_ request: AXSupervisorFocusRequest) {
        supervisorFocusRefreshAttemptNonce = nil
        appModel.clearSupervisorFocusRequest(request)
    }

    private func pendingHubGrantRowAnchor(_ grant: SupervisorManager.SupervisorPendingGrant) -> String {
        let token = normalizedFocusToken(grant.grantRequestId) ?? grant.id
        return "supervisor.pendingHubGrant.\(token)"
    }

    private func pendingSupervisorSkillApprovalRowAnchor(
        _ approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> String {
        "supervisor.pendingSupervisorSkillApproval.\(approval.requestId)"
    }

    private func normalizedFocusToken(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var pendingSupervisorSkillApprovalBoard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: supervisor.pendingSupervisorSkillApprovals.isEmpty ? "checkmark.shield" : "hand.raised.fill")
                    .foregroundColor(supervisor.pendingSupervisorSkillApprovals.isEmpty ? .secondary : .orange)
                Text("Supervisor 待批技能：\(supervisor.pendingSupervisorSkillApprovals.count)")
                    .font(.headline)

                Spacer()

                Text("local gate")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: supervisor.refreshPendingSupervisorSkillApprovalsNow) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新 Supervisor 本地待批技能")
            }

            if supervisor.pendingSupervisorSkillApprovals.isEmpty {
                Text("当前没有待审批的 Supervisor 高风险技能。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(supervisor.pendingSupervisorSkillApprovals) { approval in
                            supervisorSkillApprovalRowView(approval)
                                .id(pendingSupervisorSkillApprovalRowAnchor(approval))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 178)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var recentSupervisorSkillActivityBoard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: supervisor.recentSupervisorSkillActivities.isEmpty ? "sparkles.rectangle.stack" : "sparkles.rectangle.stack.fill")
                    .foregroundColor(supervisor.recentSupervisorSkillActivities.isEmpty ? .secondary : .accentColor)
                Text("Supervisor 最近技能活动：\(supervisor.recentSupervisorSkillActivities.count)")
                    .font(.headline)

                Spacer()

                Text("recent activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: supervisor.refreshRecentSupervisorSkillActivitiesNow) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新 Supervisor 最近技能活动")
            }

            if supervisor.recentSupervisorSkillActivities.isEmpty {
                Text("当前还没有 Supervisor skill activity 记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(supervisor.recentSupervisorSkillActivities) { item in
                            supervisorSkillActivityCard(item)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var supervisorEventLoopBoard: some View {
        let items = Array(supervisor.recentSupervisorEventLoopActivities.suffix(6).reversed())

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: items.isEmpty ? "arrow.triangle.branch" : "arrow.triangle.branch.fill")
                    .foregroundColor(items.isEmpty ? .secondary : .accentColor)
                Text("Supervisor 自动跟进：\(supervisor.recentSupervisorEventLoopActivities.count)")
                    .font(.headline)

                Spacer()

                Text(supervisor.supervisorEventLoopStatusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                Text("当前还没有自动 follow-up 事件。skill callback、grant resolution、heartbeat 或 incident 触发后，这里会显示最近事件循环审计。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            supervisorEventLoopActivityRow(item)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 176)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var pendingHubGrantBoard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: supervisor.pendingHubGrants.isEmpty ? "checkmark.shield" : "exclamationmark.shield.fill")
                    .foregroundColor(supervisor.pendingHubGrants.isEmpty ? .secondary : .orange)
                Text("Hub 待处理授权：\(supervisor.pendingHubGrants.count)")
                    .font(.headline)

                Spacer()

                Text(pendingHubGrantSnapshotText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: supervisor.refreshPendingHubGrantSnapshotNow) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新 Hub 授权快照")
            }

            if !supervisor.hasFreshPendingHubGrantSnapshot {
                Text("暂未拿到新鲜 Hub 快照（不会再回退日志推断）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !supervisor.pendingHubGrants.isEmpty {
                Text(XTHubGrantPresentation.approvalFooterNote(count: supervisor.pendingHubGrants.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if supervisor.pendingHubGrants.isEmpty {
                Text("当前没有待审批的 Hub 授权。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(supervisor.pendingHubGrants) { grant in
                            pendingHubGrantRow(grant)
                                .id(pendingHubGrantRowAnchor(grant))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 178)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var supervisorMemoryBoard: some View {
        let memoryReadiness = supervisor.supervisorMemoryAssemblyReadiness
        let pendingFollowUpQuestion = supervisor.supervisorPendingMemoryFactFollowUpQuestion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: supervisor.supervisorMemoryProjectDigests.isEmpty ? "memorychip" : "internaldrive.fill")
                    .foregroundColor(supervisor.supervisorMemoryProjectDigests.isEmpty ? .secondary : .accentColor)
                Text("Supervisor Memory")
                    .font(.headline)

                Spacer()

                Text(supervisor.supervisorMemoryStatusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button(action: supervisor.refreshSupervisorMemorySnapshotNow) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新 Supervisor memory 汇总")
            }

            Text("mode=\(XTMemoryUseMode.supervisorOrchestration.rawValue) · source=\(supervisor.supervisorMemorySource.isEmpty ? "(none)" : supervisor.supervisorMemorySource)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: memoryReadinessIconName)
                    .foregroundStyle(memoryReadinessColor)
                Text(memoryReadinessHeadline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(memoryReadinessColor)
            }

            Text(memoryReadiness.statusLine)
                .font(.caption2)
                .foregroundStyle(memoryReadinessColor)
                .textSelection(.enabled)
                .lineLimit(2)

            Text(supervisor.supervisorMemoryAssemblyStatusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !pendingFollowUpQuestion.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble.fill")
                            .foregroundStyle(.orange)
                        Text("Pending Memory Follow-up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }

                    Text("还缺这项项目背景：\(pendingFollowUpQuestion)")
                        .font(.caption)
                        .foregroundStyle(.primary)

                    Text("你可以直接继续说事实，我会接着补进项目记忆。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if let assembly = supervisor.supervisorMemoryAssemblySnapshot {
                Text(assembly.detailLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            if !memoryReadiness.issues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Strategic Review Risks")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(memoryReadinessColor)
                    ForEach(Array(memoryReadiness.issues.prefix(3))) { issue in
                        supervisorMemoryIssueRow(issue)
                    }
                }
            }

            Text(supervisor.supervisorSkillRegistryStatusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let snapshot = supervisor.supervisorSkillRegistrySnapshot,
               !snapshot.items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Focused Skill Registry")
                        .font(.caption.weight(.semibold))
                    ForEach(snapshot.items.prefix(4)) { item in
                        supervisorSkillRegistryRow(item)
                    }
                }
            }

            if supervisor.supervisorMemoryProjectDigests.isEmpty {
                Text("当前还没有项目级记忆摘要。创建项目、生成 `.xterminal/AX_MEMORY.md` 或等待 registry 状态更新后，这里会显示所有案子的汇总。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(supervisor.supervisorMemoryProjectDigests.prefix(8)) { digest in
                            supervisorMemoryRow(digest)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 176)
            }

            if !supervisor.supervisorMemoryPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(supervisorMemoryPreviewExcerpt)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var supervisorPortfolioBoard: some View {
        let snapshot = supervisor.supervisorPortfolioSnapshot
        let actionability = snapshot.actionabilitySnapshot()
        let actionabilityByProject = Dictionary(grouping: actionability.recommendedActions, by: \.projectId)
        let cards = Array(snapshot.projects.prefix(6))
        let criticalQueue = Array(snapshot.criticalQueue.prefix(3))
        let todayQueue = Array(actionability.recommendedActions.prefix(4))
        let actionEvents = Array(supervisor.supervisorRecentProjectActionEvents.prefix(4))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: snapshot.projects.isEmpty ? "square.stack.3d.up" : "square.stack.3d.up.fill")
                    .foregroundColor(snapshot.projects.isEmpty ? .secondary : .accentColor)
                Text("Project Portfolio")
                    .font(.headline)

                Spacer()

                Text(snapshot.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                portfolioCountBadge(title: "Active", count: snapshot.counts.active, color: .accentColor)
                portfolioCountBadge(title: "Blocked", count: snapshot.counts.blocked, color: .orange)
                portfolioCountBadge(title: "Auth", count: snapshot.counts.awaitingAuthorization, color: .red)
                portfolioCountBadge(title: "Done", count: snapshot.counts.completed, color: .green)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    portfolioMetricBadge(title: "Changed 24h", count: actionability.projectsChangedLast24h, color: .accentColor)
                    portfolioMetricBadge(title: "Decision blocker", count: actionability.decisionBlockerProjectsCount, color: .red)
                    portfolioMetricBadge(title: "Missing next", count: actionability.projectsMissingNextStep, color: .orange)
                }

                HStack(spacing: 8) {
                    portfolioMetricBadge(title: "Stalled", count: actionability.stalledProjects, color: .orange)
                    portfolioMetricBadge(title: "Zombie", count: actionability.zombieProjects, color: .secondary)
                    portfolioMetricBadge(title: "Action today", count: actionability.actionableToday, color: .accentColor)
                }
            }

            if supervisor.supervisorProjectNotificationSnapshot.hasActivity {
                Text(supervisor.supervisorProjectNotificationSnapshot.statusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if cards.isEmpty {
                Text("当前还没有可展示的受辖项目。项目进入 registry 并产生状态摘要后，这里会显示当前动作、阻塞和下一步。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if !todayQueue.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today to Handle")
                            .font(.caption.weight(.semibold))
                        if let priorityHint = todayQueuePriorityHint(todayQueue) {
                            Text(priorityHint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(actionability.statusLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ForEach(todayQueue) { item in
                            supervisorPortfolioActionabilityRow(item)
                        }
                    }
                }

                if !criticalQueue.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Critical Queue")
                            .font(.caption.weight(.semibold))
                        ForEach(criticalQueue) { item in
                            Text("• \(item.projectName): \(item.reason) → \(item.nextAction)")
                                .font(.caption2)
                                .foregroundStyle(item.severity == .authorizationRequired ? .red : .orange)
                                .lineLimit(2)
                        }
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(cards) { card in
                            supervisorPortfolioProjectRow(
                                card,
                                actionabilityItems: Array((actionabilityByProject[card.projectId] ?? []).prefix(2)),
                                isSelected: selectedPortfolioProjectID == card.projectId
                            ) {
                                selectedPortfolioProjectID = card.projectId
                                appModel.selectedProjectId = card.projectId
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 170)

                if let drillDown = supervisor.supervisorLastProjectDrillDownSnapshot,
                   selectedPortfolioProjectID == drillDown.projectId {
                    supervisorProjectDrillDownPanel(drillDown)
                }

                if !actionEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Action Feed")
                            .font(.caption.weight(.semibold))
                        ForEach(actionEvents) { event in
                            supervisorPortfolioActionEventRow(event)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func supervisorMemoryRow(_ digest: SupervisorManager.SupervisorMemoryProjectDigest) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(digest.displayName)
                    .font(.caption.weight(.semibold))
                Text(digest.runtimeState)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("recent=\(digest.recentMessageCount)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text(supervisorMemoryUpdatedText(digest.updatedAt))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text("source: \(digest.source)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("goal: \(digest.goal)")
                .font(.caption2)
                .lineLimit(2)

            Text("next: \(digest.nextStep)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if digest.blocker != "(无)" {
                Text("blocker: \(digest.blocker)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func supervisorMemoryIssueRow(
        _ issue: SupervisorMemoryAssemblyIssue
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(issue.severity.rawValue.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(issue.severity == .blocking ? Color.red : Color.orange)
                Text(issue.summary)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }

            Text(issue.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func supervisorSkillRegistryRow(_ item: SupervisorSkillRegistryItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.displayName)
                    .font(.caption.weight(.semibold))
                Text(item.skillId)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(item.requiresGrant ? "grant" : item.riskLevel.rawValue)
                    .font(.caption2)
                    .foregroundStyle(item.requiresGrant ? .orange : .secondary)
            }

            Text("\(item.policyScope) · \(item.sideEffectClass) · timeout \(item.timeoutMs)ms · retry \(item.maxRetries)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(item.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func portfolioCountBadge(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(title) \(count)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(Capsule())
    }

    private func portfolioMetricBadge(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(title) \(count)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .clipShape(Capsule())
    }

    private func supervisorPortfolioProjectRow(
        _ card: SupervisorPortfolioProjectCard,
        actionabilityItems: [SupervisorPortfolioActionabilityItem],
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) -> some View {
        let projectEntry = appModel.registry.project(for: card.projectId)
        let governed = projectEntry.map { appModel.governedAuthorityPresentation(for: $0) }
        let switchboard = projectEntry.map { appModel.autonomySwitchboardPresentation(for: $0) }

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.displayName)
                    .font(.caption.weight(.semibold))
                Text(card.projectState.rawValue)
                    .font(.caption2.monospaced())
                    .foregroundStyle(portfolioStateColor(card.projectState))
                Spacer()
                Text(card.memoryFreshness.rawValue)
                    .font(.caption2.monospaced())
                    .foregroundStyle(portfolioFreshnessColor(card.memoryFreshness))
                Text("recent=\(card.recentMessageCount)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Button(isSelected ? "Selected" : "View") {
                    onSelect()
                }
                .buttonStyle(.borderless)
                .font(.caption2)
            }

            if !actionabilityItems.isEmpty {
                HStack(spacing: 6) {
                    ForEach(actionabilityItems) { item in
                        portfolioActionabilityTag(item)
                    }
                }
            }

            if let switchboard {
                HStack(spacing: 6) {
                    portfolioGovernedTag(switchboard.configuredProfile.displayName, color: portfolioProfileColor(switchboard.configuredProfile))
                    if switchboard.hasConfiguredEffectiveDrift {
                        portfolioGovernedTag("effective \(switchboard.effectiveProfile.displayName)", color: portfolioProfileColor(switchboard.effectiveProfile))
                    }
                    portfolioGovernedTag(switchboard.effectiveDeviceAuthorityPosture.displayName, color: .green)
                    portfolioGovernedTag(switchboard.effectiveGrantPosture.displayName, color: .orange)
                    if let governed, governed.localAutoApproveConfigured {
                        portfolioGovernedTag("local auto", color: .orange)
                    }
                    if let governed, governed.governedReadableRootCount > 0 {
                        portfolioGovernedTag("read+\(governed.governedReadableRootCount)", color: .blue)
                    }
                }
            } else if let governed, governed.hasAnyVisibleSignal {
                HStack(spacing: 6) {
                    if governed.governedReadableRootCount > 0 {
                        portfolioGovernedTag("read+\(governed.governedReadableRootCount)", color: .blue)
                    }
                }
            }

            Text("action: \(card.currentAction)")
                .font(.caption2)
                .lineLimit(2)

            Text("next: \(card.nextStep)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !card.topBlocker.isEmpty {
                Text("blocker: \(card.topBlocker)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func supervisorPortfolioActionabilityRow(
        _ item: SupervisorPortfolioActionabilityItem
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(portfolioActionabilityColor(item.kind))
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.projectName) · \(item.kindLabel)")
                    .font(.caption2.weight(.semibold))
                Text(item.recommendedNextAction)
                    .font(.caption2)
                    .lineLimit(2)
                Text("why: \(item.whyItMatters)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func portfolioActionabilityTag(
        _ item: SupervisorPortfolioActionabilityItem
    ) -> some View {
        Text(item.kindLabel)
            .font(.caption2.monospaced())
            .foregroundStyle(portfolioActionabilityColor(item.kind))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(portfolioActionabilityColor(item.kind).opacity(0.12))
            .clipShape(Capsule())
    }

    private func portfolioGovernedTag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.monospaced())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func portfolioProfileColor(_ profile: AXProjectAutonomyProfile) -> Color {
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

    @ViewBuilder
    private func supervisorProjectDrillDownPanel(_ snapshot: SupervisorProjectDrillDownSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Project Drill-down")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(snapshot.projectName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            let allowedScopes = supervisor.supervisorJurisdictionRegistry.allowedDrillDownScopes(projectId: snapshot.projectId)
            Picker("Drill-down Scope", selection: $selectedPortfolioDrillDownScope) {
                Text("Capsule").tag(SupervisorProjectDrillDownScope.capsuleOnly)
                Text("Capsule+Recent").tag(SupervisorProjectDrillDownScope.capsulePlusRecent)
            }
            .pickerStyle(.segmented)

            Text(
                "view: drilldown · scope: \(snapshot.grantedScope?.rawValue ?? snapshot.requestedScope.rawValue) · reason: \(snapshot.openedReason) · refs: \(snapshot.refs.count)"
            )
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let project = appModel.registry.project(for: snapshot.projectId) {
                let governed = appModel.governedAuthorityPresentation(for: project)
                let switchboard = appModel.autonomySwitchboardPresentation(for: project)
                HStack(spacing: 6) {
                    portfolioGovernedTag(switchboard.configuredProfile.displayName, color: portfolioProfileColor(switchboard.configuredProfile))
                    if switchboard.hasConfiguredEffectiveDrift {
                        portfolioGovernedTag("effective \(switchboard.effectiveProfile.displayName)", color: portfolioProfileColor(switchboard.effectiveProfile))
                    }
                    portfolioGovernedTag(switchboard.effectiveDeviceAuthorityPosture.displayName, color: .green)
                    portfolioGovernedTag(switchboard.effectiveGrantPosture.displayName, color: .orange)
                    if governed.localAutoApproveConfigured {
                        portfolioGovernedTag("local auto", color: .orange)
                    }
                    if governed.governedReadableRootCount > 0 {
                        portfolioGovernedTag("read+\(governed.governedReadableRootCount)", color: .blue)
                    }
                }
                Text(switchboard.runtimeSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !allowedScopes.contains(.capsulePlusRecent) {
                Text("当前管辖仅允许 `capsule_only`。更深 recent 视图已按 scope-safe 规则禁用。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            switch snapshot.status {
            case .allowed:
                if let capsule = snapshot.capsule {
                    Text("action: \(capsule.currentAction)")
                        .font(.caption2)
                        .lineLimit(2)
                    Text("next: \(capsule.nextStep)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if !capsule.topBlocker.isEmpty {
                        Text("blocker: \(capsule.topBlocker)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }

                if let spec = snapshot.specCapsule {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Spec Capsule")
                            .font(.caption2.weight(.semibold))
                        Text("goal: \(spec.goal)")
                            .font(.caption2)
                            .lineLimit(2)
                        Text("mvp: \(spec.mvpDefinition)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if !spec.approvedTechStack.isEmpty {
                            Text("tech stack: \(spec.approvedTechStack.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }

                if let rails = snapshot.decisionRails,
                   !rails.decisionTrack.isEmpty || rails.resolutions.contains(where: { !$0.shadowedBackgroundNotes.isEmpty || $0.preferredBackgroundNote != nil }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Decision Rails")
                            .font(.caption2.weight(.semibold))
                        ForEach(Array(rails.decisionTrack.prefix(3).enumerated()), id: \.offset) { _, decision in
                            Text("approved \(decision.category.rawValue): \(decision.statement)")
                                .font(.caption2)
                                .lineLimit(2)
                        }
                        ForEach(Array(rails.resolutions.prefix(3).enumerated()), id: \.offset) { _, resolution in
                            if let note = resolution.preferredBackgroundNote {
                                Text("background \(resolution.domain.rawValue): \(note.statement)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            } else if let note = resolution.shadowedBackgroundNotes.first {
                                Text("shadowed \(resolution.domain.rawValue): \(note.statement)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                if snapshot.latestReview != nil
                    || snapshot.pendingAckGuidance != nil
                    || snapshot.latestGuidance != nil {
                    supervisorProjectDrillDownGovernanceSection(snapshot)
                }

                if let workflow = snapshot.workflow,
                   let activeJob = workflow.activeJob {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Active Workflow")
                            .font(.caption2.weight(.semibold))
                        Text("job: \(activeJob.goal)")
                            .font(.caption2)
                            .lineLimit(2)
                        Text("status: \(activeJob.status.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let activePlan = workflow.activePlan {
                            Text("plan: \(activePlan.status.rawValue)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ForEach(Array(activePlan.steps.sorted { lhs, rhs in
                                if lhs.orderIndex != rhs.orderIndex {
                                    return lhs.orderIndex < rhs.orderIndex
                                }
                                return lhs.stepId < rhs.stepId
                            }.prefix(3).enumerated()), id: \.offset) { _, step in
                                Text("\(step.orderIndex + 1). \(step.title)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                if snapshot.recentMessages.isEmpty {
                    Text(selectedPortfolioDrillDownScope == .capsuleOnly
                        ? "当前只展示 capsule 摘要。切到 `capsule_plus_recent` 后可查看最近短上下文。"
                        : "当前没有可展示的 recent short context。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Short Context")
                            .font(.caption2.weight(.semibold))
                        ForEach(Array(snapshot.recentMessages.enumerated()), id: \.offset) { _, message in
                            Text("\(message.role): \(message.content)")
                                .font(.caption2)
                                .foregroundStyle(message.role == "assistant" ? .secondary : .primary)
                                .lineLimit(2)
                        }
                    }
                }

                if !snapshot.refs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scope-safe Refs")
                            .font(.caption2.weight(.semibold))
                        ForEach(Array(snapshot.refs.prefix(4).enumerated()), id: \.offset) { _, ref in
                            Text(ref)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            case .deniedProjectInvisible, .deniedScope, .projectNotFound:
                Text(snapshot.denyReason ?? snapshot.status.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func supervisorProjectDrillDownGovernanceSection(
        _ snapshot: SupervisorProjectDrillDownSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Latest Governance")
                .font(.caption2.weight(.semibold))

            if let followUp = snapshot.followUpRhythmSummary,
               !followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("follow-up rhythm: \(followUp)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let review = snapshot.latestReview {
                Text("review: \(review.verdict.displayName) · \(review.reviewLevel.displayName) · \(review.trigger.displayName)")
                    .font(.caption2)
                    .lineLimit(2)
                Text(
                    "tier: \((review.effectiveSupervisorTier?.displayName) ?? "(none)") · depth: \((review.effectiveWorkOrderDepth?.displayName) ?? "(none)") · strength: \(supervisorProjectAIStrengthText(band: review.projectAIStrengthBand, confidence: review.projectAIStrengthConfidence))"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                Text("summary: \(supervisorGovernanceScalar(review.summary))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let action = review.recommendedActions.first,
                   !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("next: \(action)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                let workOrderRef = supervisorGovernanceScalar(review.workOrderRef)
                if workOrderRef != "(none)" {
                    Text("work_order: \(workOrderRef)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let guidance = snapshot.pendingAckGuidance {
                Text("pending guidance: \(guidance.deliveryMode.displayName) · \(guidance.interventionMode.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                Text(
                    "ack: \(supervisorProjectGuidanceAckText(guidance)) · safe point: \(guidance.safePointPolicy.displayName) · lifecycle: \(SupervisorGuidanceInjectionStore.lifecycleSummary(for: guidance, nowMs: supervisorGovernanceNowMs))"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(2)
                Text(
                    "tier: \((guidance.effectiveSupervisorTier?.displayName) ?? "(none)") · depth: \((guidance.effectiveWorkOrderDepth?.displayName) ?? "(none)") · work_order: \(supervisorGovernanceScalar(guidance.workOrderRef))"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                Text("guidance: \(supervisorGovernanceScalar(guidance.guidanceText))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let guidance = snapshot.latestGuidance,
               guidance.injectionId != snapshot.pendingAckGuidance?.injectionId {
                Text("latest delivered guidance: \(guidance.deliveryMode.displayName) · \(guidance.interventionMode.displayName)")
                    .font(.caption2)
                    .lineLimit(2)
                Text(
                    "ack: \(supervisorProjectGuidanceAckText(guidance)) · safe point: \(guidance.safePointPolicy.displayName) · lifecycle: \(SupervisorGuidanceInjectionStore.lifecycleSummary(for: guidance, nowMs: supervisorGovernanceNowMs))"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                Text("guidance: \(supervisorGovernanceScalar(guidance.guidanceText))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func supervisorPortfolioActionEventRow(_ event: SupervisorProjectActionEvent) -> some View {
        let recommendation = SupervisorRhythmRecommendationEngine.recommendation(for: event)
        return HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(portfolioSeverityColor(event.severity))
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.actionTitle)
                    .font(.caption2.weight(.semibold))
                Text(recommendation.whatChanged)
                    .font(.caption2)
                    .lineLimit(2)
                Text("next: \(recommendation.recommendedNextAction)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("why: \(recommendation.whyItMatters)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var supervisorMemoryPreviewExcerpt: String {
        let trimmed = supervisor.supervisorMemoryPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 800 else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 800)
        return String(trimmed[..<idx]) + "…"
    }

    private var supervisorGovernanceNowMs: Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }

    private func supervisorGovernanceScalar(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(none)" : trimmed
    }

    private func supervisorProjectAIStrengthText(
        band: AXProjectAIStrengthBand?,
        confidence: Double?
    ) -> String {
        guard let band else { return "(none)" }
        guard let confidence else { return band.displayName }
        let normalized = max(0, min(1, confidence))
        return "\(band.displayName) · conf=\(Int((normalized * 100).rounded()))%"
    }

    private func supervisorProjectGuidanceAckText(_ record: SupervisorGuidanceInjectionRecord) -> String {
        "\(record.ackStatus.displayName) · \(record.ackRequired ? "required" : "optional")"
    }

    private func supervisorMemoryUpdatedText(_ timestamp: TimeInterval) -> String {
        guard timestamp > 0 else { return "updated=(none)" }
        return "updated=\(Int(timestamp))"
    }

    private func portfolioStateColor(_ state: SupervisorPortfolioProjectState) -> Color {
        switch state {
        case .active:
            return .accentColor
        case .blocked:
            return .orange
        case .awaitingAuthorization:
            return .red
        case .completed:
            return .green
        case .idle:
            return .secondary
        }
    }

    private func portfolioFreshnessColor(_ freshness: SupervisorPortfolioMemoryFreshness) -> Color {
        switch freshness {
        case .fresh:
            return .green
        case .ttlCached:
            return .orange
        case .stale:
            return .red
        }
    }

    private func portfolioSeverityColor(_ severity: SupervisorProjectActionSeverity) -> Color {
        switch severity {
        case .silentLog:
            return .secondary
        case .badgeOnly:
            return .accentColor
        case .briefCard:
            return .orange
        case .interruptNow, .authorizationRequired:
            return .red
        }
    }

    private func portfolioActionabilityColor(_ kind: SupervisorPortfolioActionabilityKind) -> Color {
        switch kind {
        case .decisionBlocker:
            return .red
        case .missingNextStep:
            return .orange
        case .stalled:
            return .orange
        case .zombie:
            return .secondary
        case .activeFollowUp:
            return .accentColor
        }
    }

    private func refreshSelectedPortfolioDrillDown() {
        let visibleProjectIDs = Set(supervisor.supervisorPortfolioSnapshot.projects.map(\.projectId))
        let resolvedProjectID: String
        if let current = selectedPortfolioProjectID, visibleProjectIDs.contains(current) {
            resolvedProjectID = current
        } else if let first = supervisor.supervisorPortfolioSnapshot.projects.first?.projectId {
            selectedPortfolioProjectID = first
            return
        } else {
            return
        }

        let allowedScopes = supervisor.supervisorJurisdictionRegistry.allowedDrillDownScopes(projectId: resolvedProjectID)
        if !allowedScopes.contains(selectedPortfolioDrillDownScope) {
            selectedPortfolioDrillDownScope = .capsuleOnly
            return
        }
        _ = supervisor.buildSupervisorProjectDrillDown(
            projectId: resolvedProjectID,
            requestedScope: selectedPortfolioDrillDownScope
        )
    }

    private var splitProposalBoard: some View {
        SplitProposalPanel(
            orchestrator: appModel.supervisor.orchestrator,
            monitor: appModel.supervisor.orchestrator.monitor,
            draftTaskDescription: $inputText,
            focusedLaneID: $focusedSplitLaneID
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var laneHealthBoard: some View {
        let snapshot = supervisor.supervisorLaneHealthSnapshot
        let summary = snapshot?.summary ?? .empty
        let lanes = filteredLaneHealthLanes(from: snapshot)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "heart.text.square.fill")
                    .foregroundColor(laneSummaryColor(summary))
                Text("Lane 健康态")
                    .font(.headline)

                Spacer()

                Text(supervisor.supervisorLaneHealthStatusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Picker("Lane 状态过滤", selection: $laneHealthFilter) {
                ForEach(LaneHealthFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Text("running=\(summary.running) · blocked=\(summary.blocked) · stalled=\(summary.stalled) · failed=\(summary.failed) · waiting=\(summary.waiting) · recovering=\(summary.recovering)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !lanes.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(lanes.prefix(8))) { lane in
                            laneHealthRow(lane)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 168)
            } else {
                Text(snapshot == nil
                    ? "暂无 lane 运行快照。启动多泳道后会自动展示 running/blocked/stalled/failed。"
                    : "当前过滤条件下无匹配 lane。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var xtReadyIncidentBoard: some View {
        let snapshot = supervisor.xtReadyIncidentExportSnapshot(limit: 120)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .foregroundColor(xtReadyStatusColor(snapshot))
                Text("XT-Ready Incident 导出")
                    .font(.headline)

                Spacer()

                Text("required=\(snapshot.requiredIncidentEventCount) · ledger=\(snapshot.ledgerIncidentCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: { _ = supervisor.exportXTReadyIncidentEventsReport() }) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .help("立即导出 XT-Ready incident events")

                Button(action: {
                    let path = snapshot.reportPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !path.isEmpty {
                        openURL(URL(fileURLWithPath: path))
                    }
                }) {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.borderless)
                .help("打开导出文件")
            }

            Text("status: \(snapshot.status)")
                .font(.caption2)
                .foregroundStyle(xtReadyStatusColor(snapshot))

            Text("strict_e2e_ready: \(snapshot.strictE2EReady ? "yes" : "no")")
                .font(.caption2)
                .foregroundStyle(snapshot.strictE2EReady ? .green : .red)

            if snapshot.missingIncidentCodes.isEmpty {
                Text("missing incident_code: none")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("missing incident_code: \(snapshot.missingIncidentCodes.joined(separator: ","))")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if snapshot.strictE2EIssues.isEmpty {
                Text("strict_e2e_issues: none")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                let issues = snapshot.strictE2EIssues.prefix(4).joined(separator: ",")
                Text("strict_e2e_issues: \(issues)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Text("report: \(snapshot.reportPath)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var supervisorDoctorBoard: some View {
        let memoryReadiness = supervisor.supervisorMemoryAssemblyReadiness
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: doctorStatusIconName)
                    .foregroundColor(doctorStatusColor)
                Text("Supervisor Doctor")
                    .font(.headline)

                Spacer()

                Text(supervisor.doctorStatusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button(action: supervisor.refreshSupervisorDoctorReport) {
                    Image(systemName: "stethoscope")
                }
                .buttonStyle(.borderless)
                .help("重新运行 Doctor + Secrets dry-run 预检")
            }

            Text("release_blocked_by_doctor_without_report=\(supervisor.releaseBlockedByDoctorWithoutReport)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("strategic_memory_ready=\(memoryReadiness.ready ? "yes" : "no") · memory_issues=\(memoryReadiness.issues.count)")
                .font(.caption2)
                .foregroundStyle(memoryReadinessColor)
                .textSelection(.enabled)

            if !memoryReadiness.issues.isEmpty {
                Text(memoryReadiness.issues.prefix(2).map(\.summary).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(memoryReadinessColor)
                    .lineLimit(2)
            }

            if supervisor.doctorSuggestionCards.isEmpty {
                Text(supervisor.doctorReport == nil ? "尚未生成 Doctor 报告，运行一次预检后可查看修复建议卡片。" : "未发现可执行修复项。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(supervisor.doctorSuggestionCards.prefix(4)) { card in
                            doctorSuggestionCard(card)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 154)
            }

            if !supervisor.doctorReportPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("report: \(supervisor.doctorReportPath)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var automationRuntimeBoard: some View {
        let project = selectedAutomationProject
        let recipe = selectedAutomationRecipe
        let lastLaunchRef = selectedAutomationLastLaunchRef
        let currentCheckpoint = supervisor.automationCurrentCheckpoint
        let currentRunMatchesSelection = !lastLaunchRef.isEmpty && currentCheckpoint?.runID == lastLaunchRef
        let trustedStatus = project.map {
            (appModel.projectConfig ?? .default(forProjectRoot: ctxRoot(for: $0)))
                .trustedAutomationStatus(
                    forProjectRoot: ctxRoot(for: $0),
                    permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness.current(),
                    requiredDeviceToolGroups: recipe?.requiredDeviceToolGroups ?? []
                )
        }
        let trustedRequiredPermissions = trustedStatus.map {
            AXTrustedAutomationPermissionOwnerReadiness.requiredPermissionKeys(forDeviceToolGroups: $0.deviceToolGroups)
        } ?? []

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: automationRuntimeIconName(recipe: recipe, currentRunMatchesSelection: currentRunMatchesSelection))
                    .foregroundColor(automationRuntimeColor(recipe: recipe, checkpoint: currentCheckpoint, currentRunMatchesSelection: currentRunMatchesSelection))
                Text("Automation Runtime")
                    .font(.headline)

                Spacer()

                Text(supervisor.automationStatusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button(action: { triggerAutomationCommand("/automation status") }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新当前项目 automation runtime 状态")
            }

            if let project {
                Text("project: \(project.displayName) (\(project.projectId))")
                    .font(.caption)
                    .textSelection(.enabled)

                Text("recipe: \(recipe?.ref ?? "(未激活)")")
                    .font(.caption2)
                    .foregroundStyle(recipe == nil ? .orange : .secondary)
                    .textSelection(.enabled)

                if let recipe, !recipe.goal.isEmpty {
                    Text("goal: \(recipe.goal)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                let selfIterateMode = appModel.projectConfig?.automationSelfIterateEnabled == true ? "enabled" : "disabled"
                let maxAutoRetryDepth = appModel.projectConfig?.automationMaxAutoRetryDepth ?? 2
                Text("self_iterate: \(selfIterateMode) · max_auto_retry_depth=\(maxAutoRetryDepth)")
                    .font(.caption2)
                    .foregroundStyle(appModel.projectConfig?.automationSelfIterateEnabled == true ? .orange : .secondary)

                HStack(spacing: 12) {
                    Toggle("Auto Self-Iterate", isOn: automationSelfIterateEnabledBinding)
                        .toggleStyle(.switch)
                        .font(.caption2)

                    Stepper(value: automationMaxAutoRetryDepthBinding, in: 1...8) {
                        Text("max_depth=\(appModel.projectConfig?.automationMaxAutoRetryDepth ?? 2)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 220, alignment: .leading)
                }

                Text("bounded_auto_retry_only: 当前只会生成受控 runtime patch overlay / retry recipe proposal，不会自由改 planner")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let recipe, !recipe.requiredDeviceToolGroups.isEmpty {
                    Text("required_device_tool_groups: \(recipe.requiredDeviceToolGroups.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let trustedStatus {
                    Text("trusted_automation: \(trustedStatus.state.rawValue)")
                        .font(.caption2)
                        .foregroundStyle(trustedStatus.state == .active ? .green : trustedStatus.state == .off ? .secondary : .orange)

                    if !trustedRequiredPermissions.isEmpty {
                        Text("required_permissions: \(trustedRequiredPermissions.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if !trustedStatus.armedDeviceToolGroups.isEmpty {
                        Text("armed_device_tool_groups: \(trustedStatus.armedDeviceToolGroups.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if !trustedStatus.missingPrerequisites.isEmpty {
                        Text("trusted_missing: \(trustedStatus.missingPrerequisites.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }

                    if !trustedStatus.missingRequiredDeviceToolGroups.isEmpty {
                        Text("missing_required_device_groups: \(trustedStatus.missingRequiredDeviceToolGroups.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }

                Text("last_launch: \(lastLaunchRef.isEmpty ? "(none)" : lastLaunchRef)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if currentRunMatchesSelection, let report = supervisor.automationLatestExecutionReport {
                    Text("execution: \(report.finalState.rawValue) · actions=\(report.executedActionCount)/\(report.totalActionCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let lineage = report.lineage {
                        Text("lineage: \(lineage.lineageID) · root=\(lineage.rootRunID) · depth=\(lineage.retryDepth)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if !lineage.parentRunID.isEmpty {
                            Text("parent_run: \(lineage.parentRunID)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    if let handoffPath = report.handoffArtifactPath,
                       !handoffPath.isEmpty {
                        Text("handoff: \(handoffPath)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let verification = report.verificationReport,
                       verification.required {
                        Text("verify: \(verification.passedCommandCount)/\(verification.commandCount) · \(verification.detail)")
                            .font(.caption2)
                            .foregroundStyle(verification.ok ? Color.secondary : Color.orange)
                    }
                }

                if currentRunMatchesSelection, let checkpoint = currentCheckpoint {
                    Text("checkpoint: \(checkpoint.state.rawValue) · attempt=\(checkpoint.attempt) · retry_after=\(checkpoint.retryAfterSeconds)s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if !lastLaunchRef.isEmpty {
                    Text("checkpoint: 使用 Status / Recover 可从 raw_log 重放最新状态")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let retryPackage = supervisor.automationLatestRetryPackage,
                   retryPackage.projectID == project.projectId {
                    Text("retry: \(retryPackage.retryStrategy) · from=\(retryPackage.sourceRunID)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let lineage = retryPackage.lineage {
                        Text("retry_lineage: \(lineage.lineageID) · root=\(lineage.rootRunID) · depth=\(lineage.retryDepth)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if !lineage.parentRunID.isEmpty {
                            Text("retry_parent_run: \(lineage.parentRunID)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    if let planningMode = retryPackage.planningMode,
                       !planningMode.isEmpty {
                        Text("retry_planning_mode: \(planningMode)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let planningSummary = retryPackage.planningSummary,
                       !planningSummary.isEmpty {
                        Text("retry_planning_summary: \(planningSummary)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    if let revisedVerifyCommands = retryPackage.revisedVerifyCommands,
                       !revisedVerifyCommands.isEmpty {
                        Text("retry_revised_verify_commands: \(revisedVerifyCommands.joined(separator: " || "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    let runtimePatchOverlayKeys = xtAutomationRuntimePatchOverlayKeys(retryPackage.runtimePatchOverlay)
                    if !runtimePatchOverlayKeys.isEmpty {
                        Text("retry_runtime_patch_overlay_keys: \(runtimePatchOverlayKeys.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let recipeProposalArtifactPath = retryPackage.recipeProposalArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !recipeProposalArtifactPath.isEmpty {
                        Text("retry_recipe_proposal_artifact: \(recipeProposalArtifactPath)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let planningArtifactPath = retryPackage.planningArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !planningArtifactPath.isEmpty {
                        Text("retry_planning_artifact: \(planningArtifactPath)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("retry_trigger: \(supervisor.automationRetryTriggerForTesting())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("retry_handoff: \(retryPackage.sourceHandoffArtifactPath)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if currentRunMatchesSelection, let decision = supervisor.automationRecoveryDecision {
                    let holdReason = decision.holdReason.isEmpty ? "none" : decision.holdReason
                    Text("recovery: \(decision.decision.rawValue) (\(holdReason))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button("Start") {
                        triggerAutomationCommand("/automation start")
                    }
                    .disabled(recipe == nil)

                    Button("Recover") {
                        triggerAutomationCommand("/automation recover")
                    }
                    .disabled(lastLaunchRef.isEmpty)

                    Button("Cancel") {
                        triggerAutomationCommand("/automation cancel")
                    }
                    .disabled(lastLaunchRef.isEmpty)

                    Menu("Advance") {
                        ForEach(automationAdvanceStates, id: \.rawValue) { state in
                            Button(state.rawValue) {
                                triggerAutomationCommand("/automation advance \(state.rawValue)")
                            }
                        }
                    }
                    .disabled(lastLaunchRef.isEmpty)

                    Spacer(minLength: 8)
                }
            } else {
                Text("请选择一个具体项目后再触发 automation runtime。当前 Home 视图不会直接启动项目级 run。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func supervisorSkillApprovalRowView(
        _ approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> some View {
        let rowAnchor = pendingSupervisorSkillApprovalRowAnchor(approval)
        let isFocused = highlightedPendingSupervisorSkillApprovalAnchor == rowAnchor
        let message = XTPendingApprovalPresentation.approvalMessage(
            toolName: approval.toolName,
            tool: approval.tool,
            toolSummary: approval.toolSummary
        )
        let supplementaryReason = XTPendingApprovalPresentation.supplementaryReason(
            approval.reason,
            primaryMessage: message
        )

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(
                    "\(approval.projectName) · \(approval.skillId)",
                    systemImage: supervisorSkillApprovalIcon(approval)
                )
                .font(.subheadline)
                .fontWeight(.medium)

                Spacer(minLength: 8)

                Text(grantAgeText(approval.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(message.summary)
                .font(.caption)
                .lineLimit(2)

            if let nextStep = message.nextStep,
               !nextStep.isEmpty {
                Text(nextStep)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let supplementaryReason {
                Text("note: \(supplementaryReason)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(alignment: .center, spacing: 8) {
                Text("request=\(approval.requestId)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                if let action = approval.actionURL,
                   let actionURL = URL(string: action) {
                    Button("Open") {
                        openURL(actionURL)
                    }
                }

                Button("Approve") {
                    supervisor.approvePendingSupervisorSkillApproval(approval)
                }

                Button("Deny") {
                    supervisor.denyPendingSupervisorSkillApproval(approval)
                }
            }
        }
        .padding(10)
        .background(isFocused ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.orange.opacity(0.65) : Color.clear, lineWidth: 1.5)
        )
        .cornerRadius(10)
    }

    @ViewBuilder
    private func pendingSupervisorSkillApprovalRow(
        _ approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> some View {
        let rowAnchor = pendingSupervisorSkillApprovalRowAnchor(approval)
        let isFocused = highlightedPendingSupervisorSkillApprovalAnchor == rowAnchor
        let message = XTPendingApprovalPresentation.approvalMessage(
            toolName: approval.toolName,
            tool: approval.tool,
            toolSummary: approval.toolSummary
        )
        let supplementaryReason = XTPendingApprovalPresentation.supplementaryReason(
            approval.reason,
            primaryMessage: message
        )

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(
                    "\(approval.projectName) · \(approval.skillId)",
                    systemImage: supervisorSkillApprovalIcon(approval)
                )
                .font(.subheadline)
                .fontWeight(.medium)

                Spacer(minLength: 8)

                Text(grantAgeText(approval.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(message.summary)
                .font(.caption)
                .lineLimit(2)

            if let nextStep = message.nextStep,
               !nextStep.isEmpty {
                Text(nextStep)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let supplementaryReason {
                Text("note: \(supplementaryReason)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(alignment: .center, spacing: 8) {
                Text("request=\(approval.requestId)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                if let action = approval.actionURL,
                   let actionURL = URL(string: action) {
                    Button("Open") {
                        openURL(actionURL)
                    }
                }

                Button("Approve") {
                    supervisor.approvePendingSupervisorSkillApproval(approval)
                }

                Button("Deny") {
                    supervisor.denyPendingSupervisorSkillApproval(approval)
                }
            }
        }
        .padding(10)
        .background(isFocused ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.orange.opacity(0.65) : Color.clear, lineWidth: 1.5)
        )
        .cornerRadius(10)
    }

    @ViewBuilder
    private func supervisorSkillActivityCard(
        _ item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> some View {
        SupervisorSkillActivityCard(
            item: item,
            onApprove: {
                supervisor.approveSupervisorSkillActivity(item)
            },
            onDeny: {
                supervisor.denySupervisorSkillActivity(item)
            },
            onRetry: {
                supervisor.retrySupervisorSkillActivity(item)
            },
            onViewFullRecord: {
                showSupervisorSkillFullRecord(item)
            },
            onOpenActionURL: {
                guard let action = item.actionURL,
                      let actionURL = URL(string: action) else { return }
                openURL(actionURL)
            }
        )
    }

    private func showSupervisorSkillFullRecord(
        _ item: SupervisorManager.SupervisorRecentSkillActivity
    ) {
        guard let ctx = appModel.projectContext(for: item.projectId),
              let record = SupervisorSkillActivityPresentation.fullRecord(
                ctx: ctx,
                projectName: item.projectName,
                requestID: item.requestId
              ) else {
            return
        }
        selectedSupervisorSkillRecord = SupervisorSkillRecordSheetState(record: record)
    }

    @ViewBuilder
    private func supervisorEventLoopActivityRow(
        _ item: SupervisorManager.SupervisorEventLoopActivity
    ) -> some View {
        let statusColor = supervisorEventLoopStatusColor(item.status)
        let projectLabel = item.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (item.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(global)" : item.projectId)
            : item.projectName

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(supervisorEventLoopTriggerLabel(item.triggerSource))
                    .font(.caption.weight(.semibold))
                Text(projectLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(supervisorEventLoopStatusLabel(item.status))
                    .font(.caption2.monospaced())
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            if !item.triggerSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("trigger: \(item.triggerSummary)")
                    .font(.caption)
                    .lineLimit(2)
            }

            if !item.resultSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("result: \(item.resultSummary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !item.policySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(item.policySummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text("reason=\(item.reasonCode)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text("key=\(item.dedupeKey)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(relativeTimeText(item.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(statusColor.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(statusColor.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func pendingHubGrantRow(_ grant: SupervisorManager.SupervisorPendingGrant) -> some View {
        let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let rowAnchor = pendingHubGrantRowAnchor(grant)
        let isFocused = highlightedPendingHubGrantAnchor == rowAnchor
        let inFlight = !grantId.isEmpty && supervisor.pendingHubGrantActionsInFlight.contains(grantId)
        let canAct = appModel.hubInteractive && !grantId.isEmpty
        let summary = XTHubGrantPresentation.awaitingSummary(
            capability: grant.capability,
            modelId: grant.modelId
        )
        let supplementaryReason = XTHubGrantPresentation.supplementaryReason(
            grant.reason,
            capability: grant.capability,
            modelId: grant.modelId
        )
        let scopeSummary = XTHubGrantPresentation.scopeSummary(
            requestedTtlSec: grant.requestedTtlSec,
            requestedTokenCap: grant.requestedTokenCap
        )

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("P\(grant.priorityRank) · \(grant.projectName) · \(grantCapabilityText(grant))")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer(minLength: 8)

                Text(grantAgeText(grant.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(summary)
                .font(.caption)
                .lineLimit(2)

            if let supplementaryReason {
                Text("原因：\(supplementaryReason)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !grant.priorityReason.isEmpty {
                Text("优先级解释：\(grant.priorityReason)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !grant.nextAction.isEmpty {
                Text("建议动作：\(grant.nextAction)")
                    .font(.caption)
                    .lineLimit(2)
            }

            if let scopeSummary {
                Text(scopeSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 8) {
                Text("grant=\(grantId.isEmpty ? grant.id : grantId)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                if inFlight {
                    ProgressView()
                        .controlSize(.small)
                }

                if let action = grant.actionURL,
                   let actionURL = URL(string: action) {
                    Button("Open") {
                        openURL(actionURL)
                    }
                    .disabled(inFlight)
                }

                Button("Approve") {
                    supervisor.approvePendingHubGrant(grant)
                }
                .disabled(!canAct || inFlight)

                Button("Deny") {
                    supervisor.denyPendingHubGrant(grant)
                }
                .disabled(!canAct || inFlight)
            }
        }
        .padding(10)
        .background(isFocused ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.orange.opacity(0.65) : Color.clear, lineWidth: 1.5)
        )
        .cornerRadius(10)
    }

    @ViewBuilder
    private func doctorSuggestionCard(_ card: SupervisorDoctorSuggestionCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("[\(card.priority.rawValue.uppercased())] \(card.title)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer(minLength: 8)
            }

            Text(card.why)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let first = card.actions.first, !first.isEmpty {
                Text("建议：\(first)")
                    .font(.caption)
            }
            if let verify = card.verifyHint, !verify.isEmpty {
                Text("验证：\(verify)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }

    private var pendingHubGrantSnapshotText: String {
        let source = supervisor.pendingHubGrantSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceText = source.isEmpty ? "Hub" : source
        let freshness = supervisor.hasFreshPendingHubGrantSnapshot ? "fresh" : "stale"
        let updatedAt = supervisor.pendingHubGrantUpdatedAt
        if updatedAt <= 0 {
            return "source=\(sourceText) · \(freshness)"
        }
        return "source=\(sourceText) · 更新 \(relativeTimeText(updatedAt)) · \(freshness)"
    }

    private func supervisorSkillApprovalIcon(
        _ approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> String {
        switch approval.tool {
        case .some(.read_file):
            return "doc.text"
        case .some(.write_file):
            return "pencil"
        case .some(.search):
            return "magnifyingglass"
        case .some(.run_command):
            return "terminal"
        case .some(.deviceBrowserControl):
            return "safari"
        case .some(.web_fetch), .some(.web_search), .some(.browser_read):
            return "network"
        case .some(.project_snapshot):
            return "folder.badge.gearshape"
        case .some(.agentImportRecord):
            return "checklist"
        case .some(.memory_snapshot):
            return "memorychip"
        default:
            return "hand.raised.fill"
        }
    }

    private func supervisorEventLoopTriggerLabel(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "heartbeat":
            return "Heartbeat"
        case "skill_callback":
            return "Skill Callback"
        case "guidance_ack":
            return "Guidance Ack"
        case "automation_safe_point":
            return "Safe Point"
        case "incident":
            return "Incident"
        case "external_trigger_ingress":
            return "External Trigger"
        case "grant_resolution":
            return "Grant Resolution"
        case "approval_resolution":
            return "Approval Resolution"
        default:
            return "User Turn"
        }
    }

    private func supervisorEventLoopStatusLabel(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "queued":
            return "Queued"
        case "running":
            return "Running"
        case "completed":
            return "Completed"
        case "completed_empty":
            return "Noop"
        case "deduped":
            return "Deduped"
        default:
            return raw
        }
    }

    private func supervisorEventLoopStatusColor(_ raw: String) -> Color {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "queued":
            return .blue
        case "running":
            return .mint
        case "completed":
            return .green
        case "completed_empty":
            return .secondary
        case "deduped":
            return .orange
        default:
            return .secondary
        }
    }

    private func grantCapabilityText(_ grant: SupervisorManager.SupervisorPendingGrant) -> String {
        XTHubGrantPresentation.capabilityLabel(
            capability: grant.capability,
            modelId: grant.modelId
        )
    }

    private func grantAgeText(_ createdAt: TimeInterval?) -> String {
        guard let createdAt, createdAt > 0 else { return "待处理" }
        return relativeTimeText(createdAt)
    }

    private func relativeTimeText(_ ts: TimeInterval) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince1970 - ts))
        if elapsed < 90 { return "刚刚" }
        let mins = elapsed / 60
        if mins < 60 { return "\(mins) 分钟前" }
        let hours = mins / 60
        if hours < 48 { return "\(hours) 小时前" }
        return "\(hours / 24) 天前"
    }

    private var automationAdvanceStates: [XTAutomationRunState] {
        [.queued, .running, .blocked, .takeover, .delivered, .failed, .downgraded]
    }

    private func triggerAutomationCommand(_ command: String) {
        _ = supervisor.performAutomationRuntimeCommand(command, emitSystemMessage: true)
    }

    private var automationSelfIterateEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.projectConfig?.automationSelfIterateEnabled ?? false },
            set: { appModel.setProjectAutomationSelfIteration(enabled: $0) }
        )
    }

    private var automationMaxAutoRetryDepthBinding: Binding<Int> {
        Binding(
            get: { appModel.projectConfig?.automationMaxAutoRetryDepth ?? 2 },
            set: { appModel.setProjectAutomationSelfIteration(maxAutoRetryDepth: $0) }
        )
    }

    private func ctxRoot(for project: AXProjectEntry) -> URL {
        URL(fileURLWithPath: project.rootPath, isDirectory: true)
    }

    private func automationRuntimeIconName(
        recipe: AXAutomationRecipeRuntimeBinding?,
        currentRunMatchesSelection: Bool
    ) -> String {
        if recipe == nil {
            return "bolt.slash.circle"
        }
        if currentRunMatchesSelection {
            return "bolt.circle.fill"
        }
        return "bolt.circle"
    }

    private func automationRuntimeColor(
        recipe: AXAutomationRecipeRuntimeBinding?,
        checkpoint: XTAutomationRunCheckpoint?,
        currentRunMatchesSelection: Bool
    ) -> Color {
        guard recipe != nil else { return .secondary }
        guard currentRunMatchesSelection, let checkpoint else { return .blue }

        switch checkpoint.state {
        case .queued, .running:
            return .blue
        case .blocked, .takeover, .downgraded:
            return .orange
        case .delivered:
            return .green
        case .failed:
            return .red
        }
    }

    private var doctorStatusIconName: String {
        if supervisor.doctorReport == nil { return "questionmark.shield" }
        if supervisor.doctorHasBlockingFindings { return "xmark.shield.fill" }
        if let report = supervisor.doctorReport, report.summary.warningCount > 0 { return "exclamationmark.shield.fill" }
        return "checkmark.shield.fill"
    }

    private var doctorStatusColor: Color {
        if supervisor.doctorReport == nil { return .secondary }
        if supervisor.doctorHasBlockingFindings { return .red }
        if let report = supervisor.doctorReport, report.summary.warningCount > 0 { return .orange }
        return .green
    }

    private var memoryReadinessIconName: String {
        let readiness = supervisor.supervisorMemoryAssemblyReadiness
        if readiness.ready { return "checkmark.seal.fill" }
        if readiness.blockingCount > 0 { return "exclamationmark.triangle.fill" }
        return "exclamationmark.circle.fill"
    }

    private var memoryReadinessColor: Color {
        let readiness = supervisor.supervisorMemoryAssemblyReadiness
        if readiness.ready { return .green }
        if readiness.blockingCount > 0 { return .red }
        return .orange
    }

    private var memoryReadinessHeadline: String {
        let readiness = supervisor.supervisorMemoryAssemblyReadiness
        if readiness.ready {
            return "Strategic review memory ready"
        }
        return "Strategic review memory underfed (\(readiness.issues.count))"
    }

    private func xtReadyStatusColor(_ snapshot: SupervisorManager.XTReadyIncidentExportSnapshot) -> Color {
        if snapshot.status.hasPrefix("failed") {
            return .red
        }
        if !snapshot.strictE2EReady {
            return .red
        }
        if !snapshot.missingIncidentCodes.isEmpty {
            return .orange
        }
        if snapshot.status == "ok" {
            return .green
        }
        if snapshot.status == "disabled" {
            return .secondary
        }
        return .blue
    }

    @ViewBuilder
    private func laneHealthRow(_ lane: SupervisorLaneHealthLaneState) -> some View {
        let splitPlanText = laneSplitPlanID(for: lane) ?? "n/a"
        let isFocused = focusedSplitLaneID == lane.laneID

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: laneStatusIcon(lane.status))
                    .foregroundColor(laneStatusColor(lane.status))
                Text("\(lane.laneID) · \(lane.status.rawValue)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer(minLength: 8)

                Text("hb#\(lane.heartbeatSeq)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(laneHeartbeatAgeText(lane.lastHeartbeatAtMs))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("reason=\(lane.blockedReason?.rawValue ?? "none") · next=\(lane.nextActionRecommendation)")
                .font(.caption2)
                .foregroundStyle(lane.status == .failed || lane.status == .stalled ? .orange : .secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text("task=\(lane.taskID.uuidString.prefix(8))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("plan=\(splitPlanText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if lane.oldestWaitMs > 0 {
                    Text("wait=\(laneWaitText(lane.oldestWaitMs))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if let url = laneProjectURL(lane.projectID) {
                    Button("Open") {
                        openURL(url)
                    }
                    .buttonStyle(.borderless)
                }

                Button(isFocused ? "已定位" : "定位") {
                    focusedSplitLaneID = lane.laneID
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(isFocused ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.accentColor.opacity(0.42) : .clear, lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private func laneSummaryColor(_ summary: LaneHealthSummary) -> Color {
        if summary.failed > 0 {
            return .red
        }
        if summary.stalled > 0 {
            return .orange
        }
        if summary.blocked > 0 {
            return .yellow
        }
        if summary.running > 0 || summary.recovering > 0 {
            return .green
        }
        return .secondary
    }

    private func laneStatusColor(_ status: LaneHealthStatus) -> Color {
        switch status {
        case .failed:
            return .red
        case .stalled:
            return .orange
        case .blocked:
            return .yellow
        case .recovering:
            return .blue
        case .running:
            return .green
        case .waiting, .completed:
            return .secondary
        }
    }

    private func laneStatusIcon(_ status: LaneHealthStatus) -> String {
        switch status {
        case .failed:
            return "xmark.octagon.fill"
        case .stalled:
            return "hourglass.circle.fill"
        case .blocked:
            return "pause.circle.fill"
        case .recovering:
            return "arrow.clockwise.circle.fill"
        case .running:
            return "play.circle.fill"
        case .waiting:
            return "clock.badge.questionmark.fill"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    private func laneHeartbeatAgeText(_ lastHeartbeatAtMs: Int64) -> String {
        guard lastHeartbeatAtMs > 0 else { return "heartbeat=unknown" }
        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let ageMs = max(0, nowMs - lastHeartbeatAtMs)
        if ageMs < 1_000 {
            return "heartbeat<1s"
        }
        return "heartbeat=\(ageMs / 1_000)s"
    }

    private func laneWaitText(_ oldestWaitMs: Int64) -> String {
        guard oldestWaitMs > 0 else { return "-" }
        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let ageMs = max(0, nowMs - oldestWaitMs)
        if ageMs < 1_000 {
            return "<1s"
        }
        return "\(ageMs / 1_000)s"
    }

    private func laneProjectURL(_ projectID: UUID?) -> URL? {
        guard let projectID else { return XTDeepLinkURLBuilder.supervisorURL() }
        return XTDeepLinkURLBuilder.projectURL(
            projectId: projectID.uuidString,
            pane: .chat,
            resumeRequested: true
        )
    }

    private func filteredLaneHealthLanes(from snapshot: SupervisorLaneHealthSnapshot?) -> [SupervisorLaneHealthLaneState] {
        guard let snapshot else { return [] }
        return snapshot.lanes
            .filter { lane in
                switch laneHealthFilter {
                case .all:
                    return true
                case .abnormal:
                    return lane.status == .blocked || lane.status == .stalled || lane.status == .failed
                case .running:
                    return lane.status == .running
                case .blocked:
                    return lane.status == .blocked
                case .stalled:
                    return lane.status == .stalled
                case .failed:
                    return lane.status == .failed
                }
            }
            .sorted { lhs, rhs in
                if laneStatusPriority(lhs.status) != laneStatusPriority(rhs.status) {
                    return laneStatusPriority(lhs.status) > laneStatusPriority(rhs.status)
                }
                return lhs.laneID < rhs.laneID
            }
    }

    private func laneStatusPriority(_ status: LaneHealthStatus) -> Int {
        switch status {
        case .failed: return 6
        case .stalled: return 5
        case .blocked: return 4
        case .recovering: return 3
        case .running: return 2
        case .waiting: return 1
        case .completed: return 0
        }
    }

    private func laneSplitPlanID(for lane: SupervisorLaneHealthLaneState) -> String? {
        if let value = trimmedNonEmpty(appModel.supervisor.orchestrator.monitor.taskStates[lane.taskID]?.task.metadata["split_plan_id"]) {
            return value
        }

        if let proposal = appModel.supervisor.orchestrator.activeSplitProposal,
           proposal.lanes.contains(where: { $0.laneId == lane.laneID }) {
            return proposal.splitPlanId.uuidString.lowercased()
        }

        if let launch = appModel.supervisor.orchestrator.lastLaneLaunchReport {
            let inLaunch = launch.launchedLaneIDs.contains(lane.laneID)
                || launch.deferredLaneIDs.contains(lane.laneID)
                || launch.blockedLaneReasons[lane.laneID] != nil
            if inLaunch {
                return trimmedNonEmpty(launch.splitPlanID)
            }
        }

        return nil
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
    
}

private struct SplitProposalPanel: View {
    @ObservedObject var orchestrator: SupervisorOrchestrator
    @ObservedObject var monitor: ExecutionMonitor
    @Binding var draftTaskDescription: String
    @Binding var focusedLaneID: String?
    @State private var pendingHighRiskSoftOverrideLane: SplitLaneProposal?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let proposal = orchestrator.activeSplitProposal {
                proposalSummary(proposal)
                laneList(proposal)
                actions(proposal)
            } else {
                Text("输入复杂任务后可生成拆分提案（DAG/lane/risk/budget/DoD）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            validationSection
            promptLintSection
            executionSection
            laneHealthSection
            incidentSection
            auditTrailSection
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(12)
        .alert(item: $pendingHighRiskSoftOverrideLane) { lane in
            Alert(
                title: Text("高风险 lane 降级确认"),
                message: Text(
                    "lane=\(lane.laneId) 风险=\(lane.riskTier.displayName)。\n将 hard split 改为 soft split 可能降低隔离/回滚边界，且高风险副作用动作会被拒绝。确认继续并写入审计？"
                ),
                primaryButton: .destructive(Text("确认降级")) {
                    applyMaterializationOverride(
                        for: lane,
                        createChildProject: false,
                        note: "ui_confirmed_high_risk_hard_to_soft",
                        confirmHighRiskHardToSoft: true
                    )
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundColor(.accentColor)
            Text("拆分提案")
                .font(.headline)

            Text(orchestrator.splitProposalState.rawValue)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(stateColor.opacity(0.2))
                .foregroundStyle(stateColor)
                .cornerRadius(6)

            Spacer()

            Button("生成提案") {
                let task = draftTaskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !task.isEmpty else { return }
                Task { @MainActor in
                    _ = await orchestrator.proposeSplit(for: task)
                }
            }
            .disabled(draftTaskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private func proposalSummary(_ proposal: SplitProposal) -> some View {
        let replayStatus: String = {
            guard let consistent = orchestrator.splitOverrideReplayConsistent else {
                return "n/a"
            }
            return consistent ? "ok" : "mismatch"
        }()

        VStack(alignment: .leading, spacing: 4) {
            Text("plan=\(proposal.splitPlanId.uuidString)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("复杂度 \(Int(proposal.complexityScore))/100 · 并发建议 \(proposal.recommendedConcurrency) · Token \(proposal.tokenBudgetTotal)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("override=\(orchestrator.splitOverrideHistory.count) · replay=\(replayStatus)")
                .font(.caption2)
                .foregroundStyle(replayStatus == "mismatch" ? .orange : .secondary)
        }
    }

    @ViewBuilder
    private func laneList(_ proposal: SplitProposal) -> some View {
        let lanes = displayLanes(from: proposal)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(lanes) { lane in
                    laneRow(lane)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 172)

        if let focusedLaneID, !proposal.lanes.contains(where: { $0.laneId == focusedLaneID }) {
            HStack(spacing: 8) {
                Text("已定位 lane=\(focusedLaneID)，当前提案不包含该 lane。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("清除定位") {
                    self.focusedLaneID = nil
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func laneRow(_ lane: SplitLaneProposal) -> some View {
        let isFocused = lane.laneId == focusedLaneID

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(lane.laneId) · \(lane.goal)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if isFocused {
                    Text("定位中")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }

                Text("\(lane.riskTier.displayName)/\(lane.budgetClass.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 8) {
                Text("depends=\(lane.dependsOn.isEmpty ? "-" : lane.dependsOn.joined(separator: ","))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("mode=\(lane.materializationMode.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("DoD=\(lane.dodChecklist.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if lane.isHighRisk && lane.createChildProject {
                    Text("高风险降级需确认")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Spacer(minLength: 8)

                Button(lane.createChildProject ? "Override->Soft" : "Override->Hard") {
                    if lane.createChildProject && lane.isHighRisk {
                        pendingHighRiskSoftOverrideLane = lane
                    } else {
                        applyMaterializationOverride(
                            for: lane,
                            createChildProject: !lane.createChildProject,
                            note: "ui_toggle_materialization"
                        )
                    }
                }
                .buttonStyle(.borderless)

                Button(isFocused ? "取消定位" : "定位") {
                    focusedLaneID = isFocused ? nil : lane.laneId
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(isFocused ? Color.accentColor.opacity(0.16) : Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? Color.accentColor.opacity(0.42) : .clear, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    @ViewBuilder
    private func actions(_ proposal: SplitProposal) -> some View {
        HStack(spacing: 8) {
            Button("Confirm") {
                let context = draftTaskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = orchestrator.confirmActiveSplitProposal(globalContext: context)
            }
            .buttonStyle(.borderedProminent)

            Button("启动多泳道") {
                Task { @MainActor in
                    _ = await orchestrator.executeActiveSplitProposal()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(orchestrator.activeSplitProposal == nil)

            Button("Reject") {
                orchestrator.rejectActiveSplitProposal(reason: "user_rejected_from_supervisor_view")
            }
            .buttonStyle(.bordered)

            Button("Replay Check") {
                _ = orchestrator.replayActiveSplitProposalOverrides()
            }
            .buttonStyle(.borderless)
            .disabled(orchestrator.splitProposalBaseSnapshot == nil)

            Button("Reset") {
                orchestrator.clearSplitProposalFlow()
            }
            .buttonStyle(.borderless)

            Spacer()

            if let error = orchestrator.splitFlowErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var validationSection: some View {
        if let validation = orchestrator.splitProposalValidation, !validation.issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Proposal 校验")
                    .font(.caption)
                    .fontWeight(.semibold)
                ForEach(validation.issues.prefix(4)) { issue in
                    Text("• [\(issue.severity.rawValue)] \(issue.code)")
                        .font(.caption2)
                        .foregroundStyle(issue.severity == .blocking ? .red : .secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var promptLintSection: some View {
        if let promptResult = orchestrator.promptCompilationResult {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt Contract · \(promptResult.contracts.count)/\(promptResult.expectedLaneCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(promptResult.status.rawValue)
                    .font(.caption2)
                    .foregroundStyle(promptResult.status == .ready ? .green : .red)
                if !promptResult.lintResult.issues.isEmpty {
                    ForEach(promptResult.lintResult.issues.prefix(4)) { issue in
                        Text("• [\(issue.severity.rawValue)] \(issue.code)")
                            .font(.caption2)
                            .foregroundStyle(issue.severity == .error ? .red : .secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var executionSection: some View {
        if let launch = orchestrator.lastLaneLaunchReport {
            VStack(alignment: .leading, spacing: 4) {
                Text("多泳道执行")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("split=\(launch.splitPlanID)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("launched=\(launch.launchedLaneIDs.count) · blocked=\(launch.blockedLaneReasons.count) · concurrency=\(launch.concurrencyLimit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !launch.blockedLaneReasons.isEmpty {
                    let detail = launch.blockedLaneReasons
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key):\($0.value)" }
                        .joined(separator: " | ")
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private var incidentSection: some View {
        let incidents = monitor.recentIncidents(limit: 3)
        if !incidents.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Incident 接管")
                    .font(.caption)
                    .fontWeight(.semibold)
                ForEach(incidents.reversed(), id: \.id) { incident in
                    Text("• \(incident.incidentCode) → \(incident.proposedAction.rawValue) · deny=\(incident.denyCode) · latency=\(incident.takeoverLatencyMs ?? -1)ms")
                        .font(.caption2)
                        .foregroundStyle(incident.requiresUserAck ? .orange : .secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var laneHealthSection: some View {
        let summary = monitor.laneHealthSummary
        if summary.total > 0 {
            let hotspots = monitor.laneStates.values
                .filter { state in
                    state.status == .failed || state.status == .stalled || state.status == .blocked
                }
                .sorted { lhs, rhs in
                    if laneStatusPriority(lhs.status) != laneStatusPriority(rhs.status) {
                        return laneStatusPriority(lhs.status) > laneStatusPriority(rhs.status)
                    }
                    return lhs.laneID < rhs.laneID
                }
                .prefix(4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Lane 健康态")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("total=\(summary.total) · running=\(summary.running) · blocked=\(summary.blocked) · stalled=\(summary.stalled) · failed=\(summary.failed)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if hotspots.isEmpty {
                    Text("• 当前无 blocked/stalled/failed lane")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    ForEach(Array(hotspots), id: \.laneID) { lane in
                        Text("• \(lane.laneID) -> \(lane.status.rawValue) · reason=\(lane.blockedReason?.rawValue ?? "none") · action=\(lane.nextActionRecommendation)")
                            .font(.caption2)
                            .foregroundStyle(lane.status == .failed || lane.status == .stalled ? .orange : .secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var auditTrailSection: some View {
        if let last = orchestrator.splitAuditTrail.last {
            VStack(alignment: .leading, spacing: 3) {
                Text("审计: \(last.eventType.rawValue) · \(relativeTime(last.at))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let decoded = SplitAuditPayloadDecoder.decode(last) {
                    switch decoded {
                    case .splitOverridden(let payload):
                        Text(
                            "override=\(payload.overrideCount) · blocking=\(payload.blockingIssueCount) · high_risk_confirmed=\(payload.highRiskHardToSoftConfirmedCount) · replay=\(payload.isReplay ? "yes" : "no")"
                        )
                        .font(.caption2)
                        .foregroundStyle(payload.blockingIssueCount > 0 ? .orange : .secondary)

                        if !payload.blockingIssueCodes.isEmpty {
                            Text("blocking_codes: \(payload.blockingIssueCodes.joined(separator: ","))")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }

                        if !payload.highRiskHardToSoftConfirmedLaneIDs.isEmpty {
                            Text("confirmed_lanes: \(payload.highRiskHardToSoftConfirmedLaneIDs.joined(separator: ","))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                    default:
                        EmptyView()
                    }
                }

                if !last.payload.isEmpty {
                    Text(last.payload.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " | "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var stateColor: Color {
        switch orchestrator.splitProposalState {
        case .idle:
            return .secondary
        case .proposing:
            return .blue
        case .proposed:
            return .accentColor
        case .overridden:
            return .orange
        case .confirmed:
            return .green
        case .rejected:
            return .red
        case .blocked:
            return .red
        }
    }

    private func displayLanes(from proposal: SplitProposal) -> [SplitLaneProposal] {
        guard let focusedLaneID,
              let focusedIndex = proposal.lanes.firstIndex(where: { $0.laneId == focusedLaneID }) else {
            return proposal.lanes
        }

        var lanes = proposal.lanes
        let focusedLane = lanes.remove(at: focusedIndex)
        lanes.insert(focusedLane, at: 0)
        return lanes
    }

    private func relativeTime(_ date: Date) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince(date)))
        if elapsed < 60 {
            return "刚刚"
        }
        let mins = elapsed / 60
        if mins < 60 {
            return "\(mins)m"
        }
        return "\(mins / 60)h"
    }

    private func laneStatusPriority(_ status: LaneHealthStatus) -> Int {
        switch status {
        case .failed: return 4
        case .stalled: return 3
        case .blocked: return 2
        case .recovering: return 1
        case .running, .waiting, .completed: return 0
        }
    }

    private func applyMaterializationOverride(
        for lane: SplitLaneProposal,
        createChildProject: Bool,
        note: String,
        confirmHighRiskHardToSoft: Bool? = nil
    ) {
        _ = orchestrator.overrideActiveSplitProposal(
            [
                SplitLaneOverride(
                    laneId: lane.laneId,
                    createChildProject: createChildProject,
                    note: note,
                    confirmHighRiskHardToSoft: confirmHighRiskHardToSoft
                )
            ],
            reason: "ui_lane_materialization_override"
        )
    }
}

private struct SupervisorSkillRecordSheetState: Identifiable {
    let record: SupervisorSkillFullRecord

    var id: String { record.id }
}

private struct SupervisorSkillActivityCard: View {
    let item: SupervisorManager.SupervisorRecentSkillActivity
    let onApprove: () -> Void
    let onDeny: () -> Void
    let onRetry: () -> Void
    let onViewFullRecord: () -> Void
    let onOpenActionURL: () -> Void
    @State private var showDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: SupervisorSkillActivityPresentation.iconName(for: item))
                    .foregroundStyle(iconColor)
                    .font(.system(size: 14))

                Text(SupervisorSkillActivityPresentation.title(for: item))
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)

                Spacer()

                Text(SupervisorSkillActivityPresentation.statusLabel(for: item))
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(iconColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(iconColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                Text(item.projectName)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)

                if !item.skillId.isEmpty {
                    Text(item.skillId)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(SupervisorSkillActivityPresentation.toolBadge(for: item))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(timeLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(SupervisorSkillActivityPresentation.body(for: item))
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !item.toolSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("目标：\(item.toolSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let workflowLine = SupervisorSkillActivityPresentation.workflowLine(for: item) {
                Text(workflowLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let governanceLine = SupervisorSkillActivityPresentation.governanceLine(for: item) {
                Text(governanceLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let followUpRhythmLine = SupervisorSkillActivityPresentation.followUpRhythmLine(for: item) {
                Text(followUpRhythmLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let guidanceLine = SupervisorSkillActivityPresentation.pendingGuidanceLine(for: item) {
                Text(guidanceLine)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if SupervisorSkillActivityPresentation.isAwaitingLocalApproval(item) {
                    Button("Approve") {
                        onApprove()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Deny") {
                        onDeny()
                    }
                    .buttonStyle(.bordered)
                }

                if SupervisorSkillActivityPresentation.canRetry(item) {
                    Button("Retry") {
                        onRetry()
                    }
                    .buttonStyle(.bordered)
                }

                if item.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    Button(SupervisorSkillActivityPresentation.actionButtonTitle(for: item)) {
                        onOpenActionURL()
                    }
                    .buttonStyle(.bordered)
                }

                Button("View Full Record") {
                    onViewFullRecord()
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                ScrollView {
                    Text(SupervisorSkillActivityPresentation.diagnostics(for: item))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding(.top, 6)
            }
            .font(.caption)
            .tint(.secondary)
        }
        .padding(12)
        .background(iconColor.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(iconColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var iconColor: Color {
        switch item.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "queued":
            return .blue
        case "running":
            return .mint
        case "awaiting_authorization":
            return item.requiredCapability.isEmpty ? .yellow : .orange
        case "completed":
            return .green
        case "failed":
            return .red
        case "blocked":
            return .orange
        case "canceled":
            return .secondary
        default:
            return .secondary
        }
    }

    private var timeLabel: String {
        let timestamp = item.updatedAt ?? item.createdAt ?? 0
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

private struct SupervisorSkillRecordSheet: View {
    let record: SupervisorSkillRecordSheetState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.record.title)
                        .font(.system(.headline, design: .rounded))
                    HStack(spacing: 8) {
                        Text(record.record.requestID)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        ProjectSkillRecordStatusBadge(statusLabel: record.record.latestStatusLabel)
                    }
                    Text(record.record.projectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        SupervisorSkillActivityPresentation.fullRecordText(record.record),
                        forType: .string
                    )
                }
                .buttonStyle(.bordered)

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !record.record.requestMetadata.isEmpty {
                        ProjectSkillRecordFieldSection(
                            title: "Request Metadata",
                            fields: record.record.requestMetadata
                        )
                    }

                    if !record.record.approvalFields.isEmpty {
                        ProjectSkillRecordFieldSection(
                            title: "Approval Status",
                            fields: record.record.approvalFields
                        )
                    }

                    if !record.record.governanceFields.isEmpty {
                        ProjectSkillRecordFieldSection(
                            title: "Governance Context",
                            fields: record.record.governanceFields
                        )
                    }

                    if let payload = record.record.skillPayloadText,
                       !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ProjectSkillRecordCodeSection(
                            title: "Skill Payload",
                            text: payload,
                            initiallyExpanded: false
                        )
                    }

                    if let toolArgs = record.record.toolArgumentsText,
                       !toolArgs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ProjectSkillRecordCodeSection(
                            title: "Tool Arguments",
                            text: toolArgs,
                            initiallyExpanded: true
                        )
                    }

                    if !record.record.resultFields.isEmpty
                        || !(record.record.rawOutputPreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !(record.record.rawOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SupervisorSkillRecordResultSection(record: record.record)
                    }

                    if !record.record.evidenceFields.isEmpty {
                        ProjectSkillRecordFieldSection(
                            title: "Evidence Refs",
                            fields: record.record.evidenceFields
                        )
                    }

                    if !record.record.approvalHistory.isEmpty {
                        ProjectSkillRecordTimelineSection(
                            title: "Approval History",
                            entries: record.record.approvalHistory
                        )
                    }

                    if !record.record.timeline.isEmpty {
                        ProjectSkillRecordTimelineSection(
                            title: "Event Timeline",
                            entries: record.record.timeline
                        )
                    }

                    if let evidenceJSON = record.record.supervisorEvidenceJSON,
                       !evidenceJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ProjectSkillRecordCodeSection(
                            title: "Supervisor Evidence JSON",
                            text: evidenceJSON,
                            initiallyExpanded: false
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
    }
}

private struct SupervisorSkillRecordResultSection: View {
    let record: SupervisorSkillFullRecord
    @State private var showFullRawOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Result Summary")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                Spacer()
            }

            if !record.resultFields.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(record.resultFields) { field in
                        HStack(alignment: .top, spacing: 12) {
                            Text(field.label)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 150, alignment: .leading)

                            Text(field.value)
                                .font(.system(.subheadline, design: .default))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            if let preview = record.rawOutputPreview,
               !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Raw Output Preview")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(preview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
            }

            if let rawOutput = record.rawOutput,
               !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("Full Raw Output", isExpanded: $showFullRawOutput) {
                    ScrollView {
                        Text(rawOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    .frame(maxHeight: 220)
                }
                .font(.caption)
                .tint(.secondary)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SupervisorCockpitSummarySection: View {
    @ObservedObject var supervisorManager: SupervisorManager
    @ObservedObject var orchestrator: SupervisorOrchestrator
    @ObservedObject var monitor: ExecutionMonitor
    let onTap: (PrimaryActionRailAction) -> Void
    let onStageTap: (SupervisorRuntimeStageItemPresentation) -> Void

    private var presentation: SupervisorCockpitPresentation {
        SupervisorCockpitPresentation.fromRuntime(
            supervisorManager: supervisorManager,
            orchestrator: orchestrator,
            monitor: monitor
        )
    }

    var body: some View {
        let presentation = presentation

        return VStack(alignment: .leading, spacing: UIThemeTokens.sectionSpacing) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Supervisor Cockpit")
                        .font(UIThemeTokens.sectionFont())
                    Text("one-shot intake / planner explain / blocker / next action / validated scope freeze")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                ValidatedScopeBadge(presentation: presentation.badge)
                    .frame(maxWidth: 280)
            }

            PrimaryActionRail(
                title: "Cockpit Actions",
                actions: presentation.actions,
                onTap: onTap
            )

            OneShotRuntimeStageRail(
                presentation: presentation.runtimeStageRail,
                onTap: onStageTap
            )

            StatusExplanationCard(explanation: presentation.intakeStatus)

            VStack(alignment: .leading, spacing: 12) {
                Text("Planner Explain")
                    .font(UIThemeTokens.sectionFont())
                Text(presentation.plannerExplain)
                    .font(UIThemeTokens.bodyFont())
                Text("machine_status_ref: \(presentation.plannerMachineStatusRef)")
                    .font(UIThemeTokens.monoFont())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                    .fill(UIThemeTokens.secondaryCardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                    .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
            )

            StatusExplanationCard(explanation: presentation.blockerStatus)
            StatusExplanationCard(explanation: presentation.releaseFreezeStatus)
            if supervisorManager.voiceAuthorizationResolution != nil || supervisorManager.activeVoiceChallenge != nil {
                SupervisorVoiceAuthorizationCard(supervisorManager: supervisorManager)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct SupervisorCockpitPresentationInput: Codable, Equatable {
    let isProcessing: Bool
    let pendingGrantCount: Int
    let hasFreshPendingGrantSnapshot: Bool
    let doctorStatusLine: String
    let doctorSuggestionCount: Int
    let releaseBlockedByDoctorWithoutReport: Int
    let laneSummary: LaneHealthSummary
    let abnormalLaneStatus: String?
    let abnormalLaneRecommendation: String?
    let xtReadyStatus: String
    let xtReadyStrictE2EReady: Bool
    let xtReadyIssueCount: Int
    let xtReadyReportPath: String
    let memoryAssemblyReady: Bool
    let memoryAssemblyIssueCount: Int
    let memoryAssemblyStatusLine: String
    let memoryAssemblyTopIssueCode: String?
    let autoConfirmPolicy: String?
    let autoLaunchPolicy: String?
    let grantGateMode: String?
    let humanTouchpointCount: Int
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
    let oneShotRuntimeState: String?
    let oneShotRuntimeOwner: String?
    let oneShotRuntimeTopBlocker: String?
    let oneShotRuntimeSummary: String?
    let oneShotRuntimeNextTarget: String?
    let oneShotRuntimeActiveLaneCount: Int

    init(
        isProcessing: Bool,
        pendingGrantCount: Int,
        hasFreshPendingGrantSnapshot: Bool,
        doctorStatusLine: String,
        doctorSuggestionCount: Int,
        releaseBlockedByDoctorWithoutReport: Int,
        laneSummary: LaneHealthSummary,
        abnormalLaneStatus: String?,
        abnormalLaneRecommendation: String?,
        xtReadyStatus: String,
        xtReadyStrictE2EReady: Bool,
        xtReadyIssueCount: Int,
        xtReadyReportPath: String,
        memoryAssemblyReady: Bool = true,
        memoryAssemblyIssueCount: Int = 0,
        memoryAssemblyStatusLine: String = "ready",
        memoryAssemblyTopIssueCode: String? = nil,
        autoConfirmPolicy: String? = nil,
        autoLaunchPolicy: String? = nil,
        grantGateMode: String? = nil,
        humanTouchpointCount: Int = 0,
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
        replayEvidenceRefs: [String] = [],
        oneShotRuntimeState: String? = nil,
        oneShotRuntimeOwner: String? = nil,
        oneShotRuntimeTopBlocker: String? = nil,
        oneShotRuntimeSummary: String? = nil,
        oneShotRuntimeNextTarget: String? = nil,
        oneShotRuntimeActiveLaneCount: Int = 0
    ) {
        self.isProcessing = isProcessing
        self.pendingGrantCount = pendingGrantCount
        self.hasFreshPendingGrantSnapshot = hasFreshPendingGrantSnapshot
        self.doctorStatusLine = doctorStatusLine
        self.doctorSuggestionCount = doctorSuggestionCount
        self.releaseBlockedByDoctorWithoutReport = releaseBlockedByDoctorWithoutReport
        self.laneSummary = laneSummary
        self.abnormalLaneStatus = abnormalLaneStatus
        self.abnormalLaneRecommendation = abnormalLaneRecommendation
        self.xtReadyStatus = xtReadyStatus
        self.xtReadyStrictE2EReady = xtReadyStrictE2EReady
        self.xtReadyIssueCount = xtReadyIssueCount
        self.xtReadyReportPath = xtReadyReportPath
        self.memoryAssemblyReady = memoryAssemblyReady
        self.memoryAssemblyIssueCount = memoryAssemblyIssueCount
        self.memoryAssemblyStatusLine = memoryAssemblyStatusLine
        self.memoryAssemblyTopIssueCode = memoryAssemblyTopIssueCode
        self.autoConfirmPolicy = autoConfirmPolicy
        self.autoLaunchPolicy = autoLaunchPolicy
        self.grantGateMode = grantGateMode
        self.humanTouchpointCount = humanTouchpointCount
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
        self.oneShotRuntimeState = oneShotRuntimeState
        self.oneShotRuntimeOwner = oneShotRuntimeOwner
        self.oneShotRuntimeTopBlocker = oneShotRuntimeTopBlocker
        self.oneShotRuntimeSummary = oneShotRuntimeSummary
        self.oneShotRuntimeNextTarget = oneShotRuntimeNextTarget
        self.oneShotRuntimeActiveLaneCount = oneShotRuntimeActiveLaneCount
    }

    enum CodingKeys: String, CodingKey {
        case isProcessing = "is_processing"
        case pendingGrantCount = "pending_grant_count"
        case hasFreshPendingGrantSnapshot = "has_fresh_pending_grant_snapshot"
        case doctorStatusLine = "doctor_status_line"
        case doctorSuggestionCount = "doctor_suggestion_count"
        case releaseBlockedByDoctorWithoutReport = "release_blocked_by_doctor_without_report"
        case laneSummary = "lane_summary"
        case abnormalLaneStatus = "abnormal_lane_status"
        case abnormalLaneRecommendation = "abnormal_lane_recommendation"
        case xtReadyStatus = "xt_ready_status"
        case xtReadyStrictE2EReady = "xt_ready_strict_e2e_ready"
        case xtReadyIssueCount = "xt_ready_issue_count"
        case xtReadyReportPath = "xt_ready_report_path"
        case memoryAssemblyReady = "memory_assembly_ready"
        case memoryAssemblyIssueCount = "memory_assembly_issue_count"
        case memoryAssemblyStatusLine = "memory_assembly_status_line"
        case memoryAssemblyTopIssueCode = "memory_assembly_top_issue_code"
        case autoConfirmPolicy = "auto_confirm_policy"
        case autoLaunchPolicy = "auto_launch_policy"
        case grantGateMode = "grant_gate_mode"
        case humanTouchpointCount = "human_touchpoint_count"
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
        case oneShotRuntimeState = "one_shot_runtime_state"
        case oneShotRuntimeOwner = "one_shot_runtime_owner"
        case oneShotRuntimeTopBlocker = "one_shot_runtime_top_blocker"
        case oneShotRuntimeSummary = "one_shot_runtime_summary"
        case oneShotRuntimeNextTarget = "one_shot_runtime_next_target"
        case oneShotRuntimeActiveLaneCount = "one_shot_runtime_active_lane_count"
    }
}

struct SupervisorCockpitPresentation: Codable, Equatable {
    let badge: ValidatedScopePresentation
    let runtimeStageRail: SupervisorRuntimeStageRailPresentation
    let intakeStatus: StatusExplanation
    let blockerStatus: StatusExplanation
    let releaseFreezeStatus: StatusExplanation
    let plannerExplain: String
    let plannerMachineStatusRef: String
    let actions: [PrimaryActionRailAction]
    let reviewReportPath: String
    let consumedFrozenFields: [String]

    enum CodingKeys: String, CodingKey {
        case badge
        case runtimeStageRail = "runtime_stage_rail"
        case intakeStatus = "intake_status"
        case blockerStatus = "blocker_status"
        case releaseFreezeStatus = "release_freeze_status"
        case plannerExplain = "planner_explain"
        case plannerMachineStatusRef = "planner_machine_status_ref"
        case actions
        case reviewReportPath = "review_report_path"
        case consumedFrozenFields = "consumed_frozen_fields"
    }

    @MainActor
    static func fromRuntime(
        supervisorManager: SupervisorManager,
        orchestrator: SupervisorOrchestrator,
        monitor: ExecutionMonitor
    ) -> SupervisorCockpitPresentation {
        let xtReadySnapshot = supervisorManager.xtReadyIncidentExportSnapshot(limit: 120)
        let memoryReadiness = supervisorManager.supervisorMemoryAssemblyReadiness
        let laneSnapshot = supervisorManager.supervisorLaneHealthSnapshot
        let abnormalLane = laneSnapshot?.lanes.first { lane in
            switch lane.status {
            case .blocked, .stalled, .failed:
                return true
            default:
                return false
            }
        }
        let runtimePolicy = orchestrator.oneShotAutonomyPolicy
        let scopeFreeze = orchestrator.latestDeliveryScopeFreeze
        let replayReport = orchestrator.latestReplayHarnessReport
        let deniedLaunches = orchestrator.laneLaunchDecisions.values
            .filter { $0.autoLaunchAllowed == false || $0.decision != .allow }
            .sorted { lhs, rhs in
                lhs.laneID.localizedCaseInsensitiveCompare(rhs.laneID) == .orderedAscending
            }
        let nextBaton = monitor.directedUnblockBatons.first
        let oneShotRunState = supervisorManager.oneShotRunState

        return map(
            input: SupervisorCockpitPresentationInput(
                isProcessing: supervisorManager.isProcessing,
                pendingGrantCount: supervisorManager.pendingHubGrants.count,
                hasFreshPendingGrantSnapshot: supervisorManager.hasFreshPendingHubGrantSnapshot,
                doctorStatusLine: supervisorManager.doctorStatusLine,
                doctorSuggestionCount: supervisorManager.doctorSuggestionCards.count,
                releaseBlockedByDoctorWithoutReport: supervisorManager.releaseBlockedByDoctorWithoutReport,
                laneSummary: laneSnapshot?.summary ?? monitor.laneHealthSummary,
                abnormalLaneStatus: abnormalLane?.status.rawValue,
                abnormalLaneRecommendation: abnormalLane?.nextActionRecommendation,
                xtReadyStatus: xtReadySnapshot.status,
                xtReadyStrictE2EReady: xtReadySnapshot.strictE2EReady,
                xtReadyIssueCount: xtReadySnapshot.strictE2EIssues.count + xtReadySnapshot.missingIncidentCodes.count,
                xtReadyReportPath: xtReadySnapshot.reportPath,
                memoryAssemblyReady: memoryReadiness.ready,
                memoryAssemblyIssueCount: memoryReadiness.issues.count,
                memoryAssemblyStatusLine: memoryReadiness.statusLine,
                memoryAssemblyTopIssueCode: memoryReadiness.issues.first?.code,
                autoConfirmPolicy: runtimePolicy?.autoConfirmPolicy.rawValue,
                autoLaunchPolicy: runtimePolicy?.autoLaunchPolicy.rawValue,
                grantGateMode: runtimePolicy?.grantGateMode,
                humanTouchpointCount: runtimePolicy?.humanTouchpoints.count ?? 0,
                directedUnblockBatonCount: monitor.directedUnblockBatons.count,
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
                replayFailClosedScenarioCount: replayReport?.scenarios.filter(\.failClosed).count ?? 0,
                replayEvidenceRefs: replayReport?.evidenceRefs ?? [],
                oneShotRuntimeState: oneShotRunState?.state.rawValue,
                oneShotRuntimeOwner: oneShotRunState?.currentOwner.rawValue,
                oneShotRuntimeTopBlocker: oneShotRunState?.topBlocker,
                oneShotRuntimeSummary: oneShotRunState?.userVisibleSummary,
                oneShotRuntimeNextTarget: oneShotRunState?.nextDirectedTarget,
                oneShotRuntimeActiveLaneCount: oneShotRunState?.activeLanes.count ?? 0
            )
        )
    }

    static func map(input: SupervisorCockpitPresentationInput) -> SupervisorCockpitPresentation {
        let badge = ValidatedScopePresentation.validatedMainlineOnly
        let freezeDecision = input.scopeFreezeDecision ?? "pending"
        let oneShotState = input.oneShotRuntimeState.flatMap(OneShotRunStateStatus.init(rawValue:))
        let oneShotOwner = input.oneShotRuntimeOwner ?? "none"
        let oneShotTopBlocker = input.oneShotRuntimeTopBlocker ?? "none"
        let oneShotSummary = input.oneShotRuntimeSummary ?? ""
        let oneShotNextTarget = input.oneShotRuntimeNextTarget ?? "none"
        let replayStatus: String
        if let replayPass = input.replayPass {
            replayStatus = replayPass ? "pass" : "fail"
        } else {
            replayStatus = "pending"
        }
        let plannerMachineStatusRef = "processing=\(input.isProcessing); pending_grants=\(input.pendingGrantCount); grant_snapshot_fresh=\(input.hasFreshPendingGrantSnapshot); lane_running=\(input.laneSummary.running); lane_blocked=\(input.laneSummary.blocked); lane_stalled=\(input.laneSummary.stalled); lane_failed=\(input.laneSummary.failed); xt_ready_status=\(input.xtReadyStatus); xt_ready_issues=\(input.xtReadyIssueCount); memory_ready=\(input.memoryAssemblyReady); memory_issues=\(input.memoryAssemblyIssueCount); memory_top_issue=\(input.memoryAssemblyTopIssueCode ?? "none"); one_shot_state=\(input.oneShotRuntimeState ?? "none"); one_shot_owner=\(oneShotOwner); one_shot_blocker=\(oneShotTopBlocker); one_shot_next=\(oneShotNextTarget); one_shot_active_lanes=\(input.oneShotRuntimeActiveLaneCount); auto_confirm=\(input.autoConfirmPolicy ?? "none"); auto_launch=\(input.autoLaunchPolicy ?? "none"); freeze=\(freezeDecision); denied_launches=\(input.deniedLaunchCount); batons=\(input.directedUnblockBatonCount); replay=\(replayStatus)"
        let runtimeStageRail = buildRuntimeStageRail(
            input: input,
            oneShotState: oneShotState,
            oneShotOwner: oneShotOwner,
            oneShotTopBlocker: oneShotTopBlocker,
            oneShotSummary: oneShotSummary,
            oneShotNextTarget: oneShotNextTarget,
            freezeDecision: freezeDecision,
            plannerMachineStatusRef: plannerMachineStatusRef
        )
        let contractSummary = [
            input.autoConfirmPolicy.map { "auto_confirm=\($0)" },
            input.autoLaunchPolicy.map { "auto_launch=\($0)" },
            input.grantGateMode.map { "grant_gate=\($0)" },
            "strategic_memory=\(input.memoryAssemblyReady ? "ready" : "underfed")",
            input.oneShotRuntimeState.map { "one_shot=\($0)" },
            "freeze=\(freezeDecision)",
            "replay=\(replayStatus)"
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        let directedResumeSummary = input.nextDirectedResumeAction.map { action in
            let laneSuffix = input.nextDirectedResumeLane.map { " @ \($0)" } ?? ""
            return "directed_resume=\(action)\(laneSuffix)"
        }

        let intakeStatus: StatusExplanation
        let blockerStatus: StatusExplanation
        let plannerExplain: String

        if input.pendingGrantCount > 0 || input.topLaunchDenyCode == "grant_required" || oneShotState == .awaitingGrant {
            intakeStatus = StatusExplanation(
                state: .grantRequired,
                headline: "one-shot intake 已接收，但等待风险授权",
                whatHappened: oneShotSummary.isEmpty ? "Cockpit 发现授权链仍未完成，runtime policy 保持 fail-closed，不放行高风险 lane。" : oneShotSummary,
                whyItHappened: "grant_required 来自 AI-2 runtime 合同、one-shot run state 与 lane launch deny 决策；未授权前不会越过 grant gate。",
                userAction: directedResumeSummary ?? "先审批风险授权，再继续当前 one-shot intake。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "grant_fail_closed must remain visible",
                highlights: [
                    contractSummary,
                    "human_touchpoints=\(input.humanTouchpointCount)",
                    "denied_launches=\(input.deniedLaunchCount)",
                    "owner=\(oneShotOwner)"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .grantRequired,
                headline: "Top blocker: \(oneShotTopBlocker == "none" ? "grant_required" : oneShotTopBlocker)",
                whatHappened: "当前主 blocker 是 grant chain 未完成，auto-launch 被显式 deny。",
                whyItHappened: "AI-2 的 `oneShotAutonomyPolicy` 与 `laneLaunchDecisions` 明确要求保持 fail-closed。",
                userAction: directedResumeSummary ?? "在 grant center 完成审批，然后回到当前 intake。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "high-risk path remains fail-closed",
                highlights: [input.grantGateMode.map { "grant_gate_mode=\($0)" } ?? "", "next_target=\(oneShotNextTarget)"]
                    .filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。one-shot intake → planner explain → blocker triage → delivery freeze。当前停在 awaiting_grant；grant gate 未绿前不会自动继续。"
        } else if input.topLaunchDenyCode == "permission_denied" || oneShotTopBlocker == "permission_denied" {
            intakeStatus = StatusExplanation(
                state: .permissionDenied,
                headline: "runtime patch 检出 permission_denied，自动启动保持关闭",
                whatHappened: "lane launch 决策返回 permission_denied，当前链路不会被 UI 包装成可继续。",
                whyItHappened: "AI-2 在 runtime deny 决策里显式发出了 `permission_denied`，属于必须可见的 fail-closed 状态。",
                userAction: directedResumeSummary ?? "先修复权限或授权配置，再重新发起 intake / resume。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "permission_denied remains explicit",
                highlights: [contractSummary, "top_launch_deny_code=permission_denied"].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .permissionDenied,
                headline: "Top blocker: permission_denied",
                whatHappened: "当前主 blocker 是权限链路拒绝。",
                whyItHappened: "runtime deny note 会在 UI 中保持可见，避免误导用户为普通等待态。",
                userAction: directedResumeSummary ?? "先处理权限问题，再回到当前复杂任务。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "authz must stay fail-closed",
                highlights: ["denied_launches=\(input.deniedLaunchCount)"]
            )
            plannerExplain = "\(contractSummary)。当前停在 permission_denied；lane launch deny 已把权限问题前移到 cockpit。"
        } else if input.topLaunchDenyCode == "scope_expansion" || freezeDecision == "no_go" || !input.scopeFreezeBlockedExpansionItems.isEmpty {
            let blockedItems = input.scopeFreezeBlockedExpansionItems.joined(separator: ",")
            let nextAction = input.scopeFreezeNextActions.first ?? "drop_scope_expansion"
            intakeStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "validated scope freeze 拒绝 scope expansion",
                whatHappened: "delivery scope freeze 标记为 `\(freezeDecision)`，且存在超出 validated mainline 的扩 scope 项。",
                whyItHappened: "AI-2 的 `xt.delivery_scope_freeze.v1` 已明确 no-go / blocked expansion，UI 继续保持 fail-closed。",
                userAction: nextAction,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "scope_not_validated must remain visible",
                highlights: [contractSummary, blockedItems.isEmpty ? "" : "blocked_expansion=\(blockedItems)"].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "Top blocker: scope_expansion",
                whatHappened: "当前主 blocker 是请求范围超出 validated scope。",
                whyItHappened: "scope freeze 已落下 no-go 决策，因此不能继续对外或对内暗示已验证。",
                userAction: nextAction,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "validated-mainline-only stays enforced",
                highlights: ["validated_scope=\(input.scopeFreezeValidatedScope.joined(separator: ","))"].filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。当前停在 scope_expansion；需先回退到 validated mainline，再重新计算 delivery freeze。"
        } else if input.releaseBlockedByDoctorWithoutReport != 0 {
            intakeStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "Cockpit 等待 Doctor 预检证据",
                whatHappened: "当前缺少可用的 Doctor release 证据，因此 release 相关动作仍保持阻断。",
                whyItHappened: "secret scrub、diagnostics 与 fail-closed 口径要求先有机读报告，再允许 UI 提示可继续。",
                userAction: "运行 Doctor 预检，确认阻断项与建议卡后再 review delivery。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "diagnostic_required remains visible",
                highlights: [contractSummary, "doctor_suggestions=\(input.doctorSuggestionCount)"].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "Top blocker: diagnostic_required",
                whatHappened: "当前主 blocker 是 Doctor 证据链未就绪。",
                whyItHappened: "缺少 Doctor 报告时，release line 不能被 UI 包装成已放行。",
                userAction: "先运行 diagnostics，再回到 review delivery。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "release stays fail-closed without doctor report",
                highlights: ["release_blocked_by_doctor_without_report=\(input.releaseBlockedByDoctorWithoutReport)"]
            )
            plannerExplain = "\(contractSummary)。当前停在 diagnostic_required，因为 Doctor / secret scrub 证据尚未齐备。"
        } else if oneShotState == .failedClosed {
            let recommendation = directedResumeSummary ?? input.scopeFreezeNextActions.first ?? "先修复 fail-closed blocker，再重新发起当前 one-shot。"
            intakeStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "one-shot runtime 已 fail-closed",
                whatHappened: oneShotSummary.isEmpty ? "运行时没有继续假装可恢复，而是明确停在 fail-closed。" : oneShotSummary,
                whyItHappened: "真实 one-shot run state 已进入 failed_closed；cockpit 必须直出 blocker，而不是退回泛化的 planning / ready 文案。",
                userAction: recommendation,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "fail_closed must remain visible",
                highlights: [
                    contractSummary,
                    "owner=\(oneShotOwner)",
                    "top_blocker=\(oneShotTopBlocker)"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "Top blocker: \(oneShotTopBlocker)",
                whatHappened: "当前主 blocker 来自 one-shot runtime fail-closed。",
                whyItHappened: "执行链已经做出 fail-closed 判定，所以 UI 不能回退成普通等待态。",
                userAction: recommendation,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "runtime blocker stays explicit",
                highlights: [input.oneShotRuntimeState.map { "one_shot_state=\($0)" } ?? ""].filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。当前停在 failed_closed；需先消除 blocker=\(oneShotTopBlocker)，再允许重试当前 one-shot 主链。"
        } else if oneShotState == .blocked || input.laneSummary.failed > 0 || input.laneSummary.stalled > 0 || input.laneSummary.blocked > 0 {
            let abnormalStatus = input.abnormalLaneStatus ?? "lane_health_abnormal"
            let recommendation = directedResumeSummary ?? input.abnormalLaneRecommendation ?? "查看 lane 健康态与阻塞原因，按 next action 续推。"
            intakeStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "one-shot run 已进入执行，但当前存在 blocker",
                whatHappened: oneShotSummary.isEmpty ? "lane snapshot 显示 blocked/stalled/failed，且可选 directed resume baton 已可消费。" : oneShotSummary,
                whyItHappened: "冻结契约要求 Supervisor cockpit 清楚暴露 blocker、resume baton 与 next action，而不是只显示聊天流水。",
                userAction: recommendation,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "blocked_waiting_upstream must remain visible",
                highlights: [
                    contractSummary,
                    "lane_blocked=\(input.laneSummary.blocked)",
                    "batons=\(input.directedUnblockBatonCount)",
                    "owner=\(oneShotOwner)"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "Top blocker: \(oneShotTopBlocker == "none" ? abnormalStatus : oneShotTopBlocker)",
                whatHappened: oneShotState == .blocked ? "当前主 blocker 已被 one-shot runtime 直接声明。" : "当前主 blocker 来自 lane health abnormal。",
                whyItHappened: "planner 不会隐藏上游依赖或 runtime blocker；已有 baton 时也只允许 directed resume。",
                userAction: recommendation,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "upstream blocker stays explicit",
                highlights: [
                    directedResumeSummary ?? "",
                    "xt_ready_status=\(input.xtReadyStatus)"
                ].filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。one-shot intake → planner explain → blocker triage → delivery freeze。当前停在 blocked_waiting_upstream；如 baton 已发出，则只允许 directed resume。"
        } else if input.isProcessing
            || input.laneSummary.running > 0
            || input.laneSummary.recovering > 0
            || oneShotState == .planning
            || oneShotState == .launching
            || oneShotState == .running
            || oneShotState == .resuming
            || oneShotState == .mergeback {
            intakeStatus = StatusExplanation(
                state: .inProgress,
                headline: oneShotState == .running || oneShotState == .mergeback ? "one-shot run 正在真实执行" : "one-shot intake 已进入 planning / running",
                whatHappened: oneShotSummary.isEmpty ? "Cockpit 发现 planner 正在归一化任务、分配 lane，并带着 AI-2 runtime policy / freeze / replay 合同推进。" : oneShotSummary,
                whyItHappened: "XT-W3-27-D 现已绑定真实 runtime 数据，不再只依赖 mock 状态映射。",
                userAction: directedResumeSummary ?? "保持关注 planner explain；如果出现授权提示，先处理授权再继续。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "validated-mainline-only stays visible during execution",
                highlights: [
                    contractSummary,
                    "replay_scenarios=\(input.replayScenarioCount)",
                    "allowed_public_statements=\(input.allowedPublicStatementCount)",
                    "active_lanes=\(input.oneShotRuntimeActiveLaneCount)"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: input.directedUnblockBatonCount > 0 ? .inProgress : .ready,
                headline: input.directedUnblockBatonCount > 0 ? "Top blocker: directed_resume_available" : "Top blocker: none",
                whatHappened: input.directedUnblockBatonCount > 0 ? "当前没有新硬阻塞，但已存在 directed resume baton 可供续推。" : "当前没有 grant / doctor / lane 异常硬阻塞。",
                whyItHappened: input.directedUnblockBatonCount > 0 ? "AI-2 的 baton 路由已把 resume scope 收敛到 continue_current_task_only。" : "执行仍在进行，但没有额外 fail-closed blocker 需要立刻人工干预。",
                userAction: directedResumeSummary ?? "继续观察 planner explain，并在需要时 review delivery。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "scope freeze still applies",
                highlights: ["xt_ready_status=\(input.xtReadyStatus)", "owner=\(oneShotOwner)"]
            )
            plannerExplain = "\(contractSummary)。one-shot intake → planner explain → blocker triage → delivery freeze。当前处于 \(input.oneShotRuntimeState ?? "planning_or_running")，并附带 replay=\(replayStatus)、freeze=\(freezeDecision) 的解释上下文。"
        } else if oneShotState == .deliveryFreeze || oneShotState == .completed || !input.xtReadyStrictE2EReady || input.xtReadyIssueCount > 0 {
            let memoryUnderfed = !input.memoryAssemblyReady || input.memoryAssemblyIssueCount > 0
            let deliveryHeadline = memoryUnderfed
                ? "交付冻结前仍需补齐 strategic memory"
                : "交付冻结前仍需 review delivery"
            let deliveryWhatHappened = if memoryUnderfed {
                oneShotSummary.isEmpty
                    ? "当前 review / freeze 阶段虽然已经接近交付，但 Supervisor memory assembly 仍存在 underfed 风险，因此不能把当前状态上提为可信的 strategic review。"
                    : oneShotSummary
            } else {
                oneShotSummary.isEmpty
                    ? "XT-Ready 还存在未清零问题，Cockpit 因此不把当前状态上提为已交付完成。"
                    : oneShotSummary
            }
            let deliveryWhyItHappened = memoryUnderfed
                ? "如果 strategic review 建立在 underfed memory 上，Supervisor 很容易因为缺少长期目标、关键决策来由和可靠依据而给出失真的纠偏。"
                : "delivery freeze 需要 strict e2e 与 incident 证据；问题未清零时继续保持 explainable hold。"
            let deliveryUserAction = if memoryUnderfed {
                "先刷新 Supervisor memory，并确认当前项目的深度记忆、长期目标、关键决策原因、当前卡点以及可作为依据的日志或结果都已补齐，再 review delivery。"
            } else {
                input.scopeFreezeNextActions.first ?? "先 review delivery，确认 XT-Ready issues 再决定是否推进。"
            }
            let deliveryBlockerHeadline = memoryUnderfed ? "Top blocker: memory_context_underfed" : "Top blocker: review_delivery"
            intakeStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: deliveryHeadline,
                whatHappened: deliveryWhatHappened,
                whyItHappened: deliveryWhyItHappened,
                userAction: deliveryUserAction,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "delivery freeze requires strict evidence",
                highlights: [
                    contractSummary,
                    "xt_ready_issue_count=\(input.xtReadyIssueCount)",
                    "memory_issue_count=\(input.memoryAssemblyIssueCount)",
                    input.memoryAssemblyTopIssueCode.map { "memory_top_issue=\($0)" } ?? ""
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: deliveryBlockerHeadline,
                whatHappened: memoryUnderfed
                    ? "当前主 blocker 是 strategic review 的 memory 供给仍不可信。"
                    : "当前主 blocker 是交付冻结证据仍待复核。",
                whyItHappened: memoryUnderfed
                    ? "memory assembly 没有达到 review-ready 之前，Cockpit 不能把当前 freeze / completion 展示成可信的 release 收口。"
                    : "XT-Ready 未绿时，Cockpit 不能向外暗示 release 已完成。",
                userAction: memoryUnderfed
                    ? deliveryUserAction
                    : (input.scopeFreezeNextActions.first ?? "查看 delivery report 与 XT-Ready export，再决定下一步。"),
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "no release without strict evidence",
                highlights: [
                    "xt_ready_status=\(input.xtReadyStatus)",
                    "memory_status=\(input.memoryAssemblyStatusLine)"
                ]
            )
            plannerExplain = memoryUnderfed
                ? "\(contractSummary)。当前停在 memory_context_underfed；需先补齐 strategic review memory，再进入可信的 delivery review。"
                : "\(contractSummary)。当前停在 delivery review，原因是 XT-Ready 仍有未消化问题。"
        } else if !input.memoryAssemblyReady || input.memoryAssemblyIssueCount > 0 {
            let topIssue = input.memoryAssemblyTopIssueCode ?? "memory_context_underfed"
            intakeStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "Strategic review 记忆仍未喂够",
                whatHappened: "当前没有 grant / lane / XT-Ready 的显式硬阻塞，但 Supervisor memory assembly 仍未达到可信的 review 供给线。",
                whyItHappened: "如果在这时直接做战略纠偏，Supervisor 会更容易受到浅层 working set 或局部噪声误导，而不是依据完整项目背景做判断。",
                userAction: "先刷新 Supervisor memory，并确认当前项目的深度记忆、长期目标、关键决策原因、当前卡点以及可作为依据的日志或结果都已补齐。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "strategic review must not run on underfed memory",
                highlights: [
                    contractSummary,
                    "memory_issue_count=\(input.memoryAssemblyIssueCount)",
                    "memory_status=\(input.memoryAssemblyStatusLine)"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "Top blocker: \(topIssue)",
                whatHappened: "当前主 blocker 是 Supervisor strategic memory 仍未准备好。",
                whyItHappened: "memory assembly 的锚点、层级或证据链不完整时，Cockpit 不应把状态包装成 ready。",
                userAction: "刷新 memory 并重做 focused strategic review 前的装配检查。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "memory readiness stays explicit before strategic review",
                highlights: [
                    "memory_ready=\(input.memoryAssemblyReady)",
                    "memory_top_issue=\(topIssue)"
                ]
            )
            plannerExplain = "\(contractSummary)。当前停在 \(topIssue)；需要先把 strategic memory 从 underfed 拉回 review-ready，才适合继续推进纠偏或评审。"
        } else {
            intakeStatus = StatusExplanation(
                state: .ready,
                headline: "提交 one-shot intake 以开始复杂任务",
                whatHappened: "Cockpit 已把 one-shot intake、planner explain、blocker、resume baton 与 validated scope freeze 组合成首个可运行入口。",
                whyItHappened: "AI-3 当前已消费 AI-2 runtime 合同，不等待整包验证恢复后才展示真实状态语义。",
                userAction: directedResumeSummary ?? "点击“提交 one-shot intake”，输入目标 / 约束 / 交付物 / 风险。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "validated-mainline-only remains the only external scope",
                highlights: [
                    contractSummary,
                    "primary_cta=submit_intake",
                    "validated_paths=\((input.scopeFreezeValidatedScope.isEmpty ? badge.validatedPaths : input.scopeFreezeValidatedScope).joined(separator: ","))"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: input.directedUnblockBatonCount > 0 ? .inProgress : .ready,
                headline: input.directedUnblockBatonCount > 0 ? "Top blocker: directed_resume_available" : "Top blocker: none",
                whatHappened: input.directedUnblockBatonCount > 0 ? "当前存在可执行的 directed resume baton。" : "当前没有显式 blocker；下一步由 one-shot intake 驱动 planner。",
                whyItHappened: input.directedUnblockBatonCount > 0 ? "baton 已把恢复动作收敛到继续当前任务，不允许 scope expand。" : "冻结契约要求 UI 在 ready 态也明确 next action，而不是显示空白。",
                userAction: directedResumeSummary ?? "提交 one-shot intake，随后观察 planner explain 与 blocker card。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "grant / scope / secret blocker will still fail-closed once triggered",
                highlights: ["xt_ready_status=\(input.xtReadyStatus)"]
            )
            plannerExplain = "\(contractSummary)。当前处于 ready；一旦提交复杂任务，Cockpit 会把 planner explain、blocker、baton 与 next action 持续显式展示。"
        }

        let releaseFreezeState: XTUISurfaceState = (freezeDecision == "no_go" || !input.scopeFreezeBlockedExpansionItems.isEmpty) ? .blockedWaitingUpstream : .releaseFrozen
        let releaseNextAction = input.scopeFreezeNextActions.first ?? "review delivery 时只引用 validated refs；任何新 surface 另起切片。"
        let validatedScope = input.scopeFreezeValidatedScope.isEmpty ? badge.validatedPaths : input.scopeFreezeValidatedScope
        let replayRef = input.replayEvidenceRefs.first ?? input.xtReadyReportPath

        let releaseFreezeStatus = StatusExplanation(
            state: releaseFreezeState,
            headline: "validated-mainline-only / delivery scope freeze (\(freezeDecision))",
            whatHappened: "Cockpit 明确只围绕 \(validatedScope.joined(separator: " → ")) 的 validated mainline 展示与复盘；对外文案只消费 allowlist。",
            whyItHappened: "R1 不扩 scope，不把未验证 surface 重新拉回当前 claim；AI-2 的 freeze 与 replay 摘要已成为 UI 真实数据源。",
            userAction: releaseNextAction,
            machineStatusRef: "current_release_scope=\(badge.currentReleaseScope); validated_paths=\(validatedScope.joined(separator: ",")); decision=\(freezeDecision); allowed_public_statements=\(input.allowedPublicStatementCount); replay=\(replayStatus)",
            hardLine: "scope_not_validated must remain visible",
            highlights: [
                "release_statement_allowlist=validated_mainline_only",
                "allowed_public_statements=\(input.allowedPublicStatementCount)",
                "replay_fail_closed_scenarios=\(input.replayFailClosedScenarioCount)/\(input.replayScenarioCount)"
            ] + input.scopeFreezeBlockedExpansionItems.prefix(3).map { "blocked_item=\($0)" }
        )

        let actions = [
            PrimaryActionRailAction(
                id: "submit_intake",
                title: "提交 one-shot intake",
                subtitle: directedResumeSummary ?? "把复杂任务送入 planner，并保留 what happened / why / next action",
                systemImage: "paperplane.circle.fill",
                style: .primary
            ),
            PrimaryActionRailAction(
                id: "approve_risk",
                title: "审批风险授权",
                subtitle: input.grantGateMode.map { "grant_required 时先走授权（\($0)）" } ?? "grant_required 时先走授权，不越过 fail-closed 边界",
                systemImage: "checkmark.shield",
                style: .secondary
            ),
            PrimaryActionRailAction(
                id: "review_delivery",
                title: "查看交付冻结",
                subtitle: "freeze=\(freezeDecision) · replay=\(replayStatus) · refs=\(replayRef.isEmpty ? 0 : 1)",
                systemImage: "doc.text.magnifyingglass",
                style: .diagnostic
            )
        ]

        return SupervisorCockpitPresentation(
            badge: badge,
            runtimeStageRail: runtimeStageRail,
            intakeStatus: intakeStatus,
            blockerStatus: blockerStatus,
            releaseFreezeStatus: releaseFreezeStatus,
            plannerExplain: plannerExplain,
            plannerMachineStatusRef: plannerMachineStatusRef,
            actions: actions,
            reviewReportPath: replayRef,
            consumedFrozenFields: [
                "xt.ui_information_architecture.v1.primary_actions.xt.supervisor_cockpit",
                "xt.ui_surface_state_contract.v1.state_types",
                "xt.ui_release_scope_badge.v1.validated_paths",
                "xt.one_shot_run_state.v1.state",
                "xt.unblock_baton.v1.next_action",
                "xt.delivery_scope_freeze.v1.validated_scope",
                "xt.one_shot_autonomy_policy.v1.auto_launch_policy",
                "xt.one_shot_replay_regression.v1.scenarios"
            ]
        )
    }

    private static func buildRuntimeStageRail(
        input: SupervisorCockpitPresentationInput,
        oneShotState: OneShotRunStateStatus?,
        oneShotOwner: String,
        oneShotTopBlocker: String,
        oneShotSummary: String,
        oneShotNextTarget: String,
        freezeDecision: String,
        plannerMachineStatusRef: String
    ) -> SupervisorRuntimeStageRailPresentation {
        let accessItem = runtimeAccessStage(input: input, oneShotState: oneShotState, oneShotTopBlocker: oneShotTopBlocker)
        let runtimeItem = runtimeExecutionStage(
            input: input,
            oneShotState: oneShotState,
            oneShotTopBlocker: oneShotTopBlocker,
            oneShotSummary: oneShotSummary
        )
        let freezeItem = runtimeFreezeStage(
            input: input,
            oneShotState: oneShotState,
            freezeDecision: freezeDecision
        )
        let summary = [
            "state=\(oneShotState?.rawValue ?? "none")",
            "owner=\(oneShotOwner)",
            "next=\(oneShotNextTarget)",
            oneShotTopBlocker == "none" ? nil : "blocker=\(oneShotTopBlocker)"
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        return SupervisorRuntimeStageRailPresentation(
            headline: "One-shot Runtime Stage",
            summary: summary.isEmpty ? "submit_intake 后会进入 access gate、runtime 和 freeze。" : summary,
            items: [
                SupervisorRuntimeStageItemPresentation(
                    id: "intake",
                    title: "Intake",
                    detail: oneShotState == nil
                        ? "等待提交复杂任务并冻结目标/约束/交付物。"
                        : "请求已被 intake 接收并写入 runtime contract。",
                    progress: oneShotState == nil ? .active : .completed,
                    surfaceState: oneShotState == nil ? .ready : .inProgress,
                    actionID: "submit_intake",
                    actionLabel: "Open intake"
                ),
                accessItem,
                runtimeItem,
                freezeItem
            ],
            machineStatusRef: plannerMachineStatusRef
        )
    }

    private static func runtimeAccessStage(
        input: SupervisorCockpitPresentationInput,
        oneShotState: OneShotRunStateStatus?,
        oneShotTopBlocker: String
    ) -> SupervisorRuntimeStageItemPresentation {
        if input.topLaunchDenyCode == "permission_denied" || oneShotTopBlocker == "permission_denied" {
            return SupervisorRuntimeStageItemPresentation(
                id: "access",
                title: "Access",
                detail: "权限链路拒绝，需先修复 trust / authz 配置。",
                progress: .blocked,
                surfaceState: .permissionDenied,
                actionID: "resolve_access",
                actionLabel: "Open repair"
            )
        }

        if input.pendingGrantCount > 0 || input.topLaunchDenyCode == "grant_required" || oneShotState == .awaitingGrant {
            return SupervisorRuntimeStageItemPresentation(
                id: "access",
                title: "Access",
                detail: "风险授权仍未完成，grant gate 保持 fail-closed。",
                progress: .active,
                surfaceState: .grantRequired,
                actionID: "resolve_access",
                actionLabel: "Open grant"
            )
        }

        if let oneShotState,
           oneShotState != .intakeNormalized {
            return SupervisorRuntimeStageItemPresentation(
                id: "access",
                title: "Access",
                detail: "授权链已验证通过，或当前路径无需额外授权。",
                progress: .completed,
                surfaceState: .ready,
                actionID: nil,
                actionLabel: nil
            )
        }

        return SupervisorRuntimeStageItemPresentation(
            id: "access",
            title: "Access",
            detail: "等待 risk gate / permission gate 决议。",
            progress: .pending,
            surfaceState: .ready,
            actionID: nil,
            actionLabel: nil
        )
    }

    private static func runtimeExecutionStage(
        input: SupervisorCockpitPresentationInput,
        oneShotState: OneShotRunStateStatus?,
        oneShotTopBlocker: String,
        oneShotSummary: String
    ) -> SupervisorRuntimeStageItemPresentation {
        switch oneShotState {
        case .planning, .launching, .running, .resuming, .mergeback:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "Runtime",
                detail: oneShotSummary.isEmpty
                    ? "active_lanes=\(input.oneShotRuntimeActiveLaneCount) · planner / launch / mergeback 正在推进。"
                    : oneShotSummary,
                progress: .active,
                surfaceState: .inProgress,
                actionID: nil,
                actionLabel: nil
            )
        case .blocked:
            let hasDirectedResume = input.directedUnblockBatonCount > 0
                && (input.nextDirectedResumeAction?.isEmpty == false)
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "Runtime",
                detail: oneShotSummary.isEmpty
                    ? "runtime 当前阻塞于 \(oneShotTopBlocker)。"
                    : oneShotSummary,
                progress: .blocked,
                surfaceState: .blockedWaitingUpstream,
                actionID: hasDirectedResume ? "directed_resume" : nil,
                actionLabel: hasDirectedResume ? "Continue lane" : nil
            )
        case .failedClosed:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "Runtime",
                detail: oneShotSummary.isEmpty
                    ? "runtime 已 fail-closed，blocker=\(oneShotTopBlocker)。"
                    : oneShotSummary,
                progress: .blocked,
                surfaceState: oneShotTopBlocker == "permission_denied" ? .permissionDenied : .blockedWaitingUpstream,
                actionID: nil,
                actionLabel: nil
            )
        case .deliveryFreeze, .completed:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "Runtime",
                detail: "主执行链已结束，进入 freeze / completion 收口。",
                progress: .completed,
                surfaceState: .ready,
                actionID: nil,
                actionLabel: nil
            )
        case .awaitingGrant:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "Runtime",
                detail: "等待 access gate 放行后才会真正执行。",
                progress: .pending,
                surfaceState: .ready,
                actionID: nil,
                actionLabel: nil
            )
        case .intakeNormalized, nil:
            return SupervisorRuntimeStageItemPresentation(
                id: "runtime",
                title: "Runtime",
                detail: "等待 planner / launcher 接手当前 one-shot。",
                progress: .pending,
                surfaceState: .ready,
                actionID: nil,
                actionLabel: nil
            )
        }
    }

    private static func runtimeFreezeStage(
        input: SupervisorCockpitPresentationInput,
        oneShotState: OneShotRunStateStatus?,
        freezeDecision: String
    ) -> SupervisorRuntimeStageItemPresentation {
        let memoryNeedsReview = !input.memoryAssemblyReady || input.memoryAssemblyIssueCount > 0
        if input.topLaunchDenyCode == "scope_expansion" || freezeDecision == "no_go" || !input.scopeFreezeBlockedExpansionItems.isEmpty {
            return SupervisorRuntimeStageItemPresentation(
                id: "freeze",
                title: "Freeze",
                detail: input.scopeFreezeBlockedExpansionItems.isEmpty
                    ? "validated scope freeze 当前为 \(freezeDecision)。"
                    : "blocked_expansion=\(input.scopeFreezeBlockedExpansionItems.joined(separator: ","))",
                progress: .blocked,
                surfaceState: .blockedWaitingUpstream,
                actionID: "review_delivery",
                actionLabel: "Open review"
            )
        }

        switch oneShotState {
        case .deliveryFreeze:
            return SupervisorRuntimeStageItemPresentation(
                id: "freeze",
                title: "Freeze",
                detail: memoryNeedsReview
                    ? "交付冻结进行中，但 strategic memory 仍需补齐后再 review delivery。"
                    : "交付冻结进行中，等待 strict evidence / review delivery。",
                progress: .active,
                surfaceState: input.xtReadyStrictE2EReady && input.xtReadyIssueCount == 0 && !memoryNeedsReview ? .releaseFrozen : .diagnosticRequired,
                actionID: "review_delivery",
                actionLabel: "Open review"
            )
        case .completed:
            return SupervisorRuntimeStageItemPresentation(
                id: "freeze",
                title: "Freeze",
                detail: memoryNeedsReview
                    ? "validated mainline 已完成执行，但 release freeze 仍需补齐 strategic memory。"
                    : "validated mainline 已完成冻结收口。",
                progress: .completed,
                surfaceState: memoryNeedsReview ? .diagnosticRequired : .releaseFrozen,
                actionID: "review_delivery",
                actionLabel: "Open report"
            )
        default:
            return SupervisorRuntimeStageItemPresentation(
                id: "freeze",
                title: "Freeze",
                detail: "当前尚未进入 delivery freeze。",
                progress: .pending,
                surfaceState: .ready,
                actionID: nil,
                actionLabel: nil
            )
        }
    }
}
