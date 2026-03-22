import SwiftUI

struct SplitProposalPanel: View {
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
                    performSplitProposalPanelAction(.confirmHighRiskSoftOverride(lane))
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var splitProposalPanelContext: SplitProposalPanelActionResolver.Context {
        SplitProposalPanelActionResolver.Context(
            draftTaskDescription: draftTaskDescription,
            focusedLaneID: focusedLaneID,
            hasActiveProposal: orchestrator.activeSplitProposal != nil,
            hasBaseSnapshot: orchestrator.splitProposalBaseSnapshot != nil
        )
    }

    private var header: some View {
        let generateAction = SplitProposalPanelActionResolver.generateDescriptor(
            context: splitProposalPanelContext
        )

        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundColor(.accentColor)
            Text("拆分提案")
                .font(.headline)

            Text(splitProposalStateLabel(orchestrator.splitProposalState))
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(stateColor.opacity(0.2))
                .foregroundStyle(stateColor)
                .cornerRadius(6)

            Spacer()

            Button(generateAction.label) {
                performSplitProposalPanelAction(generateAction.action)
            }
            .disabled(!generateAction.isEnabled)
        }
    }

    @ViewBuilder
    private func proposalSummary(_ proposal: SplitProposal) -> some View {
        let replayStatus: String = {
            guard let consistent = orchestrator.splitOverrideReplayConsistent else {
                return "未校验"
            }
            return consistent ? "一致" : "不一致"
        }()

        VStack(alignment: .leading, spacing: 4) {
            Text("方案 ID=\(proposal.splitPlanId.uuidString)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("复杂度 \(Int(proposal.complexityScore))/100 · 并发建议 \(proposal.recommendedConcurrency) · Token \(proposal.tokenBudgetTotal)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("覆写 \(orchestrator.splitOverrideHistory.count) 次 · 回放 \(replayStatus)")
                .font(.caption2)
                .foregroundStyle(replayStatus == "不一致" ? .orange : .secondary)
        }
    }

    @ViewBuilder
    private func laneList(_ proposal: SplitProposal) -> some View {
        let lanes = SplitProposalPanelActionResolver.displayLanes(
            from: proposal,
            focusedLaneID: focusedLaneID
        )
        let clearFocusAction = SplitProposalPanelActionResolver.clearFocusedLaneDescriptor(
            focusedLaneID: focusedLaneID
        )

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
                if let clearFocusAction {
                    Button(clearFocusAction.label) {
                        performSplitProposalPanelAction(clearFocusAction.action)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private func laneRow(_ lane: SplitLaneProposal) -> some View {
        let presentation = SplitProposalPanelActionResolver.lanePresentation(
            for: lane,
            focusedLaneID: focusedLaneID
        )

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(lane.laneId) · \(lane.goal)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if presentation.isFocused {
                    Text("定位中")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }

                Text("\(lane.riskTier.displayName)/\(lane.budgetClass.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 8) {
                Text("依赖=\(lane.dependsOn.isEmpty ? "-" : lane.dependsOn.joined(separator: ","))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("落地=\(materializationModeLabel(lane.materializationMode))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("完成标准=\(lane.dodChecklist.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if presentation.needsHighRiskSoftConfirmation {
                    Text("高风险降级需确认")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Spacer(minLength: 8)

                Button(presentation.overrideLabel) {
                    performSplitProposalPanelAction(.toggleLaneMaterialization(lane))
                }
                .buttonStyle(.borderless)

                Button(presentation.focusLabel) {
                    performSplitProposalPanelAction(.toggleLaneFocus(lane))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(presentation.isFocused ? Color.accentColor.opacity(0.16) : Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(presentation.isFocused ? Color.accentColor.opacity(0.42) : .clear, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    @ViewBuilder
    private func actions(_: SplitProposal) -> some View {
        let footerActions = SplitProposalPanelActionResolver.footerDescriptors(
            context: splitProposalPanelContext
        )
        let confirmAction = footerActions[0]
        let executeAction = footerActions[1]
        let rejectAction = footerActions[2]
        let replayAction = footerActions[3]
        let resetAction = footerActions[4]

        HStack(spacing: 8) {
            Button(confirmAction.label) {
                performSplitProposalPanelAction(confirmAction.action)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!confirmAction.isEnabled)

            Button(executeAction.label) {
                performSplitProposalPanelAction(executeAction.action)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!executeAction.isEnabled)

            Button(rejectAction.label) {
                performSplitProposalPanelAction(rejectAction.action)
            }
            .buttonStyle(.bordered)
            .disabled(!rejectAction.isEnabled)

            Button(replayAction.label) {
                performSplitProposalPanelAction(replayAction.action)
            }
            .buttonStyle(.borderless)
            .disabled(!replayAction.isEnabled)

            Button(resetAction.label) {
                performSplitProposalPanelAction(resetAction.action)
            }
            .buttonStyle(.borderless)
            .disabled(!resetAction.isEnabled)

            Spacer()

            if let error = orchestrator.splitFlowErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }

    private func performSplitProposalPanelAction(_ action: SplitProposalPanelAction) {
        guard let plan = SplitProposalPanelActionResolver.resolve(
            action,
            context: splitProposalPanelContext
        ) else {
            return
        }
        applySplitProposalPanelPlan(plan)
    }

    private func applySplitProposalPanelPlan(_ plan: SplitProposalPanelActionResolver.Plan) {
        for effect in plan.effects {
            switch effect {
            case .proposeSplit(let task):
                Task { @MainActor in
                    _ = await orchestrator.proposeSplit(for: task)
                }
            case .confirmProposal(let context):
                _ = orchestrator.confirmActiveSplitProposal(globalContext: context)
            case .executeProposal:
                Task { @MainActor in
                    _ = await orchestrator.executeActiveSplitProposal()
                }
            case .rejectProposal(let reason):
                orchestrator.rejectActiveSplitProposal(reason: reason)
            case .replayCheck:
                _ = orchestrator.replayActiveSplitProposalOverrides()
            case .reset:
                orchestrator.clearSplitProposalFlow()
            case .setFocusedLane(let laneID):
                focusedLaneID = laneID
            case .showHighRiskSoftOverrideConfirmation(let lane):
                pendingHighRiskSoftOverrideLane = lane
            case .applyOverride(let override, let reason):
                _ = orchestrator.overrideActiveSplitProposal(
                    [override],
                    reason: reason
                )
            }
        }
    }

    @ViewBuilder
    private var validationSection: some View {
        if let validation = orchestrator.splitProposalValidation, !validation.issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("提案校验")
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
                Text("提示词契约 · \(promptResult.contracts.count)/\(promptResult.expectedLaneCount)")
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
                Text("拆分方案=\(launch.splitPlanID)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("已启动 \(launch.launchedLaneIDs.count) · 被阻塞 \(launch.blockedLaneReasons.count) · 并发上限 \(launch.concurrencyLimit)")
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
                Text("异常接管")
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
                Text("泳道健康态")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("总数 \(summary.total) · 运行中 \(summary.running) · 阻塞 \(summary.blocked) · 停滞 \(summary.stalled) · 失败 \(summary.failed)")
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
                            "覆写 \(payload.overrideCount) · 阻塞项 \(payload.blockingIssueCount) · 高风险确认 \(payload.highRiskHardToSoftConfirmedCount) · 回放 \(payload.isReplay ? "yes" : "no")"
                        )
                        .font(.caption2)
                        .foregroundStyle(payload.blockingIssueCount > 0 ? .orange : .secondary)

                        if !payload.blockingIssueCodes.isEmpty {
                            Text("阻塞码：\(payload.blockingIssueCodes.joined(separator: ","))")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }

                        if !payload.highRiskHardToSoftConfirmedLaneIDs.isEmpty {
                            Text("已确认泳道：\(payload.highRiskHardToSoftConfirmedLaneIDs.joined(separator: ","))")
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

    private func splitProposalStateLabel(_ state: SplitProposalFlowState) -> String {
        switch state {
        case .idle:
            return "空闲"
        case .proposing:
            return "生成中"
        case .proposed:
            return "待确认"
        case .overridden:
            return "已覆写"
        case .confirmed:
            return "已确认"
        case .rejected:
            return "已放弃"
        case .blocked:
            return "已阻塞"
        }
    }

    private func materializationModeLabel(_ mode: SplitMaterializationMode) -> String {
        switch mode {
        case .hard:
            return "独立项目"
        case .soft:
            return "项目内执行"
        }
    }
}
