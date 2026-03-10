import SwiftUI

struct SupervisorView: View {
    @StateObject private var supervisor = SupervisorManager.shared
    @State private var inputText: String = ""
    @State private var autoSendVoice: Bool = true
    @State private var laneHealthFilter: LaneHealthFilter = .abnormal
    @State private var focusedSplitLaneID: String?
    @FocusState private var isInputFocused: Bool
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
    
    private var cockpitPresentation: SupervisorCockpitPresentation {
        SupervisorCockpitPresentation.fromRuntime(
            supervisorManager: supervisor,
            orchestrator: appModel.supervisor.orchestrator,
            monitor: appModel.supervisor.orchestrator.executionMonitor
        )
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header

                Divider()

                // Keep operations panels scrollable so the chat composer remains reachable
                // even when dashboard cards grow taller than the window.
                ScrollView {
                    dashboardBoards
                }
                .frame(maxHeight: dashboardPanelMaxHeight(totalHeight: proxy.size.height))

                Divider()

                messageList
                    .frame(maxHeight: .infinity)

                Divider()

                inputArea
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            supervisor.setAppModel(appModel)
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }

    @ViewBuilder
    private var dashboardBoards: some View {
        VStack(spacing: 0) {
            cockpitSummaryBoard
            Divider()
            pendingHubGrantBoard
            Divider()
            supervisorDoctorBoard
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
    
    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .foregroundColor(.accentColor)
                Text("Supervisor AI")
                    .font(.headline)
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

    private var cockpitSummaryBoard: some View {
        SupervisorCockpitSummarySection(
            supervisorManager: supervisor,
            orchestrator: appModel.supervisor.orchestrator,
            monitor: appModel.supervisor.orchestrator.executionMonitor,
            onTap: handleCockpitAction
        )
    }

    private func handleCockpitAction(_ action: PrimaryActionRailAction) {
        switch action.id {
        case "submit_intake":
            if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                inputText = "请开始一个复杂任务：目标 / 约束 / 交付物 / 风险"
            }
            isInputFocused = true
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

            if supervisor.pendingHubGrants.isEmpty {
                Text("当前没有待审批的 Hub 授权。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(supervisor.pendingHubGrants) { grant in
                            pendingHubGrantRow(grant)
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
        VStack(alignment: .leading, spacing: 10) {
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

    @ViewBuilder
    private func pendingHubGrantRow(_ grant: SupervisorManager.SupervisorPendingGrant) -> some View {
        let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let inFlight = !grantId.isEmpty && supervisor.pendingHubGrantActionsInFlight.contains(grantId)
        let canAct = appModel.hubInteractive && !grantId.isEmpty

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

            if !grant.reason.isEmpty {
                Text(grant.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !grant.priorityReason.isEmpty {
                Text("优先级解释：\(grant.priorityReason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !grant.nextAction.isEmpty {
                Text("建议动作：\(grant.nextAction)")
                    .font(.caption)
                    .lineLimit(2)
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
        .background(Color.secondary.opacity(0.08))
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

    private func grantCapabilityText(_ grant: SupervisorManager.SupervisorPendingGrant) -> String {
        let capability = grant.capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let modelId = grant.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if capability.contains("web_fetch") || capability.contains("web.fetch") {
            return "联网访问"
        }
        if capability.contains("ai_generate_paid") || capability.contains("ai.generate.paid") {
            return modelId.isEmpty ? "付费模型调用" : "付费模型调用（\(modelId)）"
        }
        if capability.contains("ai_generate_local") || capability.contains("ai.generate.local") {
            return modelId.isEmpty ? "本地模型调用" : "本地模型调用（\(modelId)）"
        }
        if capability.isEmpty {
            return "高风险能力"
        }
        return grant.capability
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
        guard let projectID else { return URL(string: "xterminal://supervisor") }
        var components = URLComponents()
        components.scheme = "xterminal"
        components.host = "project"
        components.queryItems = [
            URLQueryItem(name: "project_id", value: projectID.uuidString),
            URLQueryItem(name: "pane", value: "chat"),
            URLQueryItem(name: "open", value: "supervisor"),
        ]
        return components.url
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
    
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if supervisor.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(supervisor.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(16)
            }
            .onChange(of: supervisor.messages.count) { _ in
                if let lastMessage = supervisor.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("欢迎使用Supervisor AI")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("我可以帮你管理所有项目，了解进度、分析卡点、提供下一步建议")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("你可以问我：")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("• 查看所有项目进度")
                    Text("• 哪个项目卡住了")
                    Text("• 接下来该做什么")
                    Text("• 告诉项目A做xxx")
                }
                .font(.body)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var inputArea: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                TextEditor(text: $inputText)
                    .focused($isInputFocused)
                    .frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .onTapGesture {
                        isInputFocused = true
                    }
                
                VStack(spacing: 8) {
                    VoiceInputButton(text: $inputText, autoAppend: !autoSendVoice) { recognized in
                        handleVoiceRecognized(recognized)
                    }
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 16)
            
            HStack {
                Text("💡 提示：你可以使用 Cmd+Enter 发送消息，或使用语音输入")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("语音自动发送", isOn: $autoSendVoice)
                    .toggleStyle(.switch)
                    .font(.caption)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        supervisor.sendMessage(trimmed, fromVoice: false)
        inputText = ""
        isInputFocused = true
    }

    private func handleVoiceRecognized(_ recognized: String) {
        let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard autoSendVoice, !trimmed.isEmpty else { return }
        supervisor.sendMessage(trimmed, fromVoice: true)
        inputText = ""
        isInputFocused = true
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

private struct SupervisorCockpitSummarySection: View {
    @ObservedObject var supervisorManager: SupervisorManager
    @ObservedObject var orchestrator: SupervisorOrchestrator
    @ObservedObject var monitor: ExecutionMonitor
    let onTap: (PrimaryActionRailAction) -> Void

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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct MessageBubble: View {
    let message: SupervisorMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(roleText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    if message.isVoice {
                        Image(systemName: "mic.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(backgroundColor)
                    .cornerRadius(12)
            }
        }
    }
    
    private var avatar: some View {
        ZStack {
            Circle()
                .fill(avatarColor)
                .frame(width: 32, height: 32)
            
            Image(systemName: iconName)
                .foregroundColor(.white)
                .font(.system(size: 14))
        }
    }
    
    private var roleText: String {
        switch message.role {
        case .user:
            return "你"
        case .assistant:
            return "Supervisor"
        case .system:
            return "系统"
        }
    }
    
    private var iconName: String {
        switch message.role {
        case .user:
            return "person.fill"
        case .assistant:
            return "person.3.fill"
        case .system:
            return "gear.fill"
        }
    }
    
    private var avatarColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return .accentColor
        case .system:
            return .secondary
        }
    }
    
    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.blue.opacity(0.1)
        case .assistant:
            return Color.accentColor.opacity(0.1)
        case .system:
            return Color.secondary.opacity(0.1)
        }
    }
    
    private var timeText: String {
        let date = Date(timeIntervalSince1970: message.timestamp)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
        replayEvidenceRefs: [String] = []
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
    }
}

struct SupervisorCockpitPresentation: Codable, Equatable {
    let badge: ValidatedScopePresentation
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
                replayEvidenceRefs: replayReport?.evidenceRefs ?? []
            )
        )
    }

    static func map(input: SupervisorCockpitPresentationInput) -> SupervisorCockpitPresentation {
        let badge = ValidatedScopePresentation.validatedMainlineOnly
        let freezeDecision = input.scopeFreezeDecision ?? "pending"
        let replayStatus: String
        if let replayPass = input.replayPass {
            replayStatus = replayPass ? "pass" : "fail"
        } else {
            replayStatus = "pending"
        }
        let plannerMachineStatusRef = "processing=\(input.isProcessing); pending_grants=\(input.pendingGrantCount); grant_snapshot_fresh=\(input.hasFreshPendingGrantSnapshot); lane_running=\(input.laneSummary.running); lane_blocked=\(input.laneSummary.blocked); lane_stalled=\(input.laneSummary.stalled); lane_failed=\(input.laneSummary.failed); xt_ready_status=\(input.xtReadyStatus); xt_ready_issues=\(input.xtReadyIssueCount); auto_confirm=\(input.autoConfirmPolicy ?? "none"); auto_launch=\(input.autoLaunchPolicy ?? "none"); freeze=\(freezeDecision); denied_launches=\(input.deniedLaunchCount); batons=\(input.directedUnblockBatonCount); replay=\(replayStatus)"
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
            return "directed_resume=\(action)\(laneSuffix)"
        }

        let intakeStatus: StatusExplanation
        let blockerStatus: StatusExplanation
        let plannerExplain: String

        if input.pendingGrantCount > 0 || input.topLaunchDenyCode == "grant_required" {
            intakeStatus = StatusExplanation(
                state: .grantRequired,
                headline: "one-shot intake 已接收，但等待风险授权",
                whatHappened: "Cockpit 发现授权链仍未完成，runtime policy 保持 fail-closed，不放行高风险 lane。",
                whyItHappened: "grant_required 来自 AI-2 runtime 合同与 lane launch deny 决策；未授权前不会越过 grant gate。",
                userAction: directedResumeSummary ?? "先审批风险授权，再继续当前 one-shot intake。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "grant_fail_closed must remain visible",
                highlights: [
                    contractSummary,
                    "human_touchpoints=\(input.humanTouchpointCount)",
                    "denied_launches=\(input.deniedLaunchCount)"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .grantRequired,
                headline: "Top blocker: grant_required",
                whatHappened: "当前主 blocker 是 grant chain 未完成，auto-launch 被显式 deny。",
                whyItHappened: "AI-2 的 `oneShotAutonomyPolicy` 与 `laneLaunchDecisions` 明确要求保持 fail-closed。",
                userAction: directedResumeSummary ?? "在 grant center 完成审批，然后回到当前 intake。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "high-risk path remains fail-closed",
                highlights: [input.grantGateMode.map { "grant_gate_mode=\($0)" } ?? ""]
                    .filter { !$0.isEmpty }
            )
            plannerExplain = "\(contractSummary)。one-shot intake → planner explain → blocker triage → delivery freeze。当前停在 awaiting_grant；grant gate 未绿前不会自动继续。"
        } else if input.topLaunchDenyCode == "permission_denied" {
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
        } else if input.laneSummary.failed > 0 || input.laneSummary.stalled > 0 || input.laneSummary.blocked > 0 {
            let abnormalStatus = input.abnormalLaneStatus ?? "lane_health_abnormal"
            let recommendation = directedResumeSummary ?? input.abnormalLaneRecommendation ?? "查看 lane 健康态与阻塞原因，按 next action 续推。"
            intakeStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "one-shot run 已进入执行，但当前存在 blocker",
                whatHappened: "lane snapshot 显示 blocked/stalled/failed，且可选 directed resume baton 已可消费。",
                whyItHappened: "冻结契约要求 Supervisor cockpit 清楚暴露 blocker、resume baton 与 next action，而不是只显示聊天流水。",
                userAction: recommendation,
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "blocked_waiting_upstream must remain visible",
                highlights: [
                    contractSummary,
                    "lane_blocked=\(input.laneSummary.blocked)",
                    "batons=\(input.directedUnblockBatonCount)"
                ].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .blockedWaitingUpstream,
                headline: "Top blocker: \(abnormalStatus)",
                whatHappened: "当前主 blocker 来自 lane health abnormal。",
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
        } else if input.isProcessing || input.laneSummary.running > 0 || input.laneSummary.recovering > 0 {
            intakeStatus = StatusExplanation(
                state: .inProgress,
                headline: "one-shot intake 已进入 planning / running",
                whatHappened: "Cockpit 发现 planner 正在归一化任务、分配 lane，并带着 AI-2 runtime policy / freeze / replay 合同推进。",
                whyItHappened: "XT-W3-27-D 现已绑定真实 runtime 数据，不再只依赖 mock 状态映射。",
                userAction: directedResumeSummary ?? "保持关注 planner explain；如果出现授权提示，先处理授权再继续。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "validated-mainline-only stays visible during execution",
                highlights: [
                    contractSummary,
                    "replay_scenarios=\(input.replayScenarioCount)",
                    "allowed_public_statements=\(input.allowedPublicStatementCount)"
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
                highlights: ["xt_ready_status=\(input.xtReadyStatus)"]
            )
            plannerExplain = "\(contractSummary)。one-shot intake → planner explain → blocker triage → delivery freeze。当前处于 planning / running，并附带 replay=\(replayStatus)、freeze=\(freezeDecision) 的解释上下文。"
        } else if !input.xtReadyStrictE2EReady || input.xtReadyIssueCount > 0 {
            intakeStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "交付冻结前仍需 review delivery",
                whatHappened: "XT-Ready 还存在未清零问题，Cockpit 因此不把当前状态上提为已交付完成。",
                whyItHappened: "delivery freeze 需要 strict e2e 与 incident 证据；问题未清零时继续保持 explainable hold。",
                userAction: input.scopeFreezeNextActions.first ?? "先 review delivery，确认 XT-Ready issues 再决定是否推进。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "delivery freeze requires strict evidence",
                highlights: [contractSummary, "xt_ready_issue_count=\(input.xtReadyIssueCount)"].filter { !$0.isEmpty }
            )
            blockerStatus = StatusExplanation(
                state: .diagnosticRequired,
                headline: "Top blocker: review_delivery",
                whatHappened: "当前主 blocker 是交付冻结证据仍待复核。",
                whyItHappened: "XT-Ready 未绿时，Cockpit 不能向外暗示 release 已完成。",
                userAction: input.scopeFreezeNextActions.first ?? "查看 delivery report 与 XT-Ready export，再决定下一步。",
                machineStatusRef: plannerMachineStatusRef,
                hardLine: "no release without strict evidence",
                highlights: ["xt_ready_status=\(input.xtReadyStatus)"]
            )
            plannerExplain = "\(contractSummary)。当前停在 delivery review，原因是 XT-Ready 仍有未消化问题。"
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
}

