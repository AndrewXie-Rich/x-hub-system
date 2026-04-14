import Foundation

struct SupervisorInfrastructureFeedInput: Equatable {
    var officialSkillsStatusLine: String
    var officialSkillsTransitionLine: String
    var officialSkillsTopBlockersLine: String
    var officialSkillsTopBlockerSummaries: [AXOfficialSkillBlockerSummaryItem] = []
    var builtinGovernedSkills: [AXBuiltinGovernedSkillSummary] = []
    var managedSkillsStatusLine: String = ""
    var historicalProjectBoundaryRepairStatusLine: String = ""
    var memoryReadiness: SupervisorMemoryAssemblyReadiness? = nil
    var memoryAssemblySnapshot: SupervisorMemoryAssemblySnapshot? = nil
    var eventLoopStatusLine: String
    var pendingHubGrants: [SupervisorManager.SupervisorPendingGrant]
    var pendingSupervisorSkillApprovals: [SupervisorManager.SupervisorPendingSkillApproval]
    var candidateReviews: [HubIPCClient.SupervisorCandidateReviewItem] = []
    var candidateReviewProjectNamesByID: [String: String] = [:]
    var recentEventLoopActivities: [SupervisorManager.SupervisorEventLoopActivity]
}

struct SupervisorInfrastructureFeedPresentation: Equatable {
    enum Tone: String, Equatable {
        case neutral
        case attention
        case critical
        case success
    }

    struct Item: Identifiable, Equatable {
        enum Kind: String, Equatable {
            case officialSkillsChannel = "official_skills_channel"
            case xtBuiltinGovernedSkills = "xt_builtin_governed_skills"
            case historicalProjectBoundaryRepair = "historical_project_boundary_repair"
            case memoryAssembly = "memory_assembly"
            case pendingHubGrant = "pending_hub_grant"
            case pendingSkillApproval = "pending_skill_approval"
            case candidateReview = "candidate_review"
            case eventLoop = "event_loop"
        }

        var id: String
        var kind: Kind
        var iconName: String
        var title: String
        var summary: String
        var detail: String
        var badgeText: String
        var tone: Tone
        var timestamp: TimeInterval?
        var contractText: String?
        var nextSafeActionText: String?
        var actionURL: String?
        var actionLabel: String?
    }

    var summaryLine: String
    var items: [Item]

    var isEmpty: Bool {
        items.isEmpty
    }

    static func map(input: SupervisorInfrastructureFeedInput, maxEventItems: Int = 4) -> SupervisorInfrastructureFeedPresentation {
        var items: [Item] = []

        let officialStatus = normalizedScalar(input.officialSkillsStatusLine)
        let officialTransition = normalizedScalar(input.officialSkillsTransitionLine)
        let officialTopBlockers = normalizedScalar(input.officialSkillsTopBlockersLine)
        let officialDetail = [officialTransition, officialTopBlockers]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let officialAction = SupervisorOfficialSkillsChannelActionSupport.readinessAction(
            statusLine: officialStatus,
            transitionLine: officialTransition,
            detailLine: officialDetail,
            blockerSummaries: input.officialSkillsTopBlockerSummaries
        )
        if !officialStatus.isEmpty {
            items.append(
                Item(
                    id: "official-skills-channel",
                    kind: .officialSkillsChannel,
                    iconName: officialSkillsTone(for: officialStatus) == .critical ? "shippingbox.fill" : "shippingbox",
                    title: "官方技能通道",
                    summary: officialStatus,
                    detail: officialDetail,
                    badgeText: officialSkillsBadge(for: officialStatus),
                    tone: officialSkillsTone(for: officialStatus),
                    timestamp: nil,
                    contractText: nil,
                    nextSafeActionText: nil,
                    actionURL: officialAction?.url,
                    actionLabel: officialAction?.label
                )
            )
        }

        let builtinSkills = input.builtinGovernedSkills
        if !builtinSkills.isEmpty {
            let preferredIDs = ["guarded-automation", "supervisor-voice"]
            let preferredBuiltinSkills = preferredIDs.compactMap { skillID in
                builtinSkills.first(where: {
                    normalizedScalar($0.skillID).caseInsensitiveCompare(skillID) == .orderedSame
                })
            }
            let highlightSkills = preferredBuiltinSkills.isEmpty
                ? Array(builtinSkills.prefix(2))
                : preferredBuiltinSkills
            let highlightIDs = highlightSkills.map { normalizedScalar($0.skillID) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            let managedSkillsStatus = normalizedScalar(input.managedSkillsStatusLine)
            let detail = [
                "仅限 XT 本地/原生",
                highlightIDs.isEmpty ? "" : "重点技能=\(highlightIDs)",
                managedSkillsStatus.isEmpty ? "" : "托管技能=\(managedSkillsStatus)"
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            let actionURL = XTDeepLinkURLBuilder.settingsURL(
                sectionId: "diagnostics",
                title: "XT 内建受治理技能",
                detail: "在诊断页查看 XT 内建受治理技能与 managed skills 的兼容状态。"
            )?.absoluteString

            items.append(
                Item(
                    id: "xt-builtin-governed-skills",
                    kind: .xtBuiltinGovernedSkills,
                    iconName: "bolt.shield",
                    title: "XT 内建技能",
                    summary: "已就绪 \(builtinSkills.count) 个",
                    detail: detail,
                    badgeText: "内建",
                    tone: .success,
                    timestamp: nil,
                    contractText: nil,
                    nextSafeActionText: nil,
                    actionURL: normalizedOptionalScalar(actionURL),
                    actionLabel: actionURL == nil ? nil : "打开诊断"
                )
            )
        }

        if let historicalRepairItem = historicalProjectBoundaryRepairItem(
            statusLine: input.historicalProjectBoundaryRepairStatusLine
        ) {
            items.append(historicalRepairItem)
        }

        if let memoryAssemblyItem = memoryAssemblyInfrastructureItem(
            readiness: input.memoryReadiness,
            snapshot: input.memoryAssemblySnapshot
        ) {
            items.append(memoryAssemblyItem)
        }

        if !input.pendingHubGrants.isEmpty {
            let top = input.pendingHubGrants[0]
            let detail = [
                normalizedScalar(top.projectName),
                normalizedScalar(top.capability),
                normalizedScalar(top.nextAction)
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            items.append(
                Item(
                    id: "pending-hub-grants",
                    kind: .pendingHubGrant,
                    iconName: "checkmark.shield.trianglebadge.exclamationmark",
                    title: "Hub 授权待处理",
                    summary: "待处理 \(input.pendingHubGrants.count) 项",
                    detail: detail,
                    badgeText: "待处理",
                    tone: .attention,
                    timestamp: top.createdAt,
                    contractText: pendingGrantContractLine(for: top),
                    nextSafeActionText: pendingGrantNextSafeActionLine(for: top),
                    actionURL: normalizedOptionalScalar(top.actionURL),
                    actionLabel: "打开授权"
                )
            )
        }

        if !input.pendingSupervisorSkillApprovals.isEmpty {
            let top = input.pendingSupervisorSkillApprovals[0]
            let authorizationMode = SupervisorPendingSkillApprovalPresentation.authorizationMode(
                for: top
            )
            let activityItem = SupervisorSkillActivityPresentation.governedSkillPresentationItem(
                for: top
            )
            let approvalMessage = XTPendingApprovalPresentation.approvalMessage(
                toolName: top.toolName,
                tool: top.tool,
                toolSummary: top.toolSummary,
                activity: activityItem
            )
            let skillLabel = firstMeaningfulScalar([
                SupervisorSkillActivityPresentation.governedShortSummary(for: top) ?? "",
                SupervisorSkillActivityPresentation.routingSummary(
                    requestedSkillId: top.requestedSkillId,
                    effectiveSkillId: top.skillId,
                    routingReasonCode: top.routingReasonCode,
                    routingExplanation: top.routingExplanation
                ) ?? "",
                normalizedScalar(top.skillId)
            ])
            let routingNarrative = SupervisorSkillActivityPresentation.routingNarrative(
                requestedSkillId: top.requestedSkillId,
                effectiveSkillId: top.skillId,
                routingReasonCode: top.routingReasonCode,
                routingExplanation: top.routingExplanation
            )
            let statusSummary = pendingSkillApprovalStatusSummary(
                for: top,
                authorizationMode: authorizationMode,
                approvalMessage: approvalMessage
            )
            let detail = [
                normalizedScalar(top.projectName),
                skillLabel,
                statusSummary
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            items.append(
                Item(
                    id: "pending-skill-approvals",
                    kind: .pendingSkillApproval,
                    iconName: "hand.raised.square.on.square",
                    title: SupervisorPendingSkillApprovalPresentation.infrastructureTitle(for: top),
                    summary: "待处理 \(input.pendingSupervisorSkillApprovals.count) 项",
                    detail: detail,
                    badgeText: SupervisorPendingSkillApprovalPresentation.infrastructureBadgeText(
                        for: top
                    ),
                    tone: .attention,
                    timestamp: top.createdAt,
                    contractText: pendingSkillApprovalContractText(
                        routingNarrative: routingNarrative,
                        activity: activityItem
                    ),
                    nextSafeActionText: pendingSkillApprovalNextSafeActionText(
                        activity: activityItem,
                        approvalMessage: approvalMessage
                    ),
                    actionURL: normalizedOptionalScalar(top.actionURL),
                    actionLabel: SupervisorPendingSkillApprovalPresentation.openActionLabel(
                        for: top
                    )
                )
            )
        }

        if let candidateReviewItem = candidateReviewInfrastructureItem(
            items: input.candidateReviews,
            projectNamesByID: input.candidateReviewProjectNamesByID
        ) {
            items.append(candidateReviewItem)
        }

        let infrastructureEventItems = input.recentEventLoopActivities
            .filter { activity in
                infrastructureEventTriggerAllowed(activity.triggerSource)
                    && normalizedScalar(activity.status).lowercased() != "deduped"
            }
            .sorted { lhs, rhs in
                let left = lhs.updatedAt
                let right = rhs.updatedAt
                if left != right { return left > right }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(maxEventItems)
            .map { activity in
                let action = SupervisorEventLoopActionPresentation.action(for: activity)
                let contract = SupervisorEventLoopFeedPresentation.guidanceContract(activity)
                let summary = firstMeaningfulScalar([
                    normalizedScalar(activity.triggerSummary),
                    normalizedScalar(activity.resultSummary),
                    normalizedScalar(activity.reasonCode)
                ])
                let detail = [
                    normalizedEventProjectLabel(activity),
                    normalizedScalar(activity.resultSummary),
                    normalizedScalar(activity.policySummary)
                ]
                .filter { !$0.isEmpty && $0 != summary }
                .joined(separator: " · ")

                return Item(
                    id: "event-loop-\(activity.id)",
                    kind: .eventLoop,
                    iconName: infrastructureEventIconName(activity.triggerSource),
                    title: infrastructureEventTitle(activity.triggerSource),
                    summary: summary,
                    detail: detail,
                    badgeText: infrastructureEventStatusBadge(activity.status),
                    tone: infrastructureEventTone(activity.status),
                    timestamp: activity.updatedAt,
                    contractText: contract.map(SupervisorGuidanceContractLinePresentation.contractLine),
                    nextSafeActionText: contract.map(SupervisorGuidanceContractLinePresentation.nextSafeActionLine),
                    actionURL: action?.url,
                    actionLabel: action?.label
                )
            }

        items.append(contentsOf: infrastructureEventItems)

        let attentionCount = items.filter { item in
            item.tone == .attention || item.tone == .critical
        }.count
        let summaryBase = infrastructureSummaryBase(
            officialStatus: officialStatus,
            attentionCount: attentionCount
        )
        let eventLoopStatus = infrastructureStatusLine(input.eventLoopStatusLine)
        let summaryLine = [summaryBase, eventLoopStatus]
            .filter { !$0.isEmpty }
            .enumerated()
            .filter { index, value in
                index == 0 || value != summaryBase
            }
            .map(\.element)
            .joined(separator: " · ")

        return SupervisorInfrastructureFeedPresentation(
            summaryLine: summaryLine.isEmpty ? "被动观察" : summaryLine,
            items: items
        )
    }

    private static func historicalProjectBoundaryRepairItem(
        statusLine: String
    ) -> Item? {
        let normalizedStatus = normalizedScalar(statusLine)
        guard !normalizedStatus.isEmpty else { return nil }

        let fields = scalarFields(from: normalizedStatus)
        let outcome = normalizedScalar(
            fields["historical_project_boundary_repair"] ?? fields["status"] ?? ""
        ).lowercased()
        let reasonToken = normalizedScalar(fields["reason"] ?? "")
        let scannedCount = Int(normalizedScalar(fields["scanned"] ?? "")) ?? 0
        let repairedConfigCount = Int(normalizedScalar(fields["repaired_config"] ?? "")) ?? 0
        let repairedMemoryCount = Int(normalizedScalar(fields["repaired_memory"] ?? "")) ?? 0
        let failedCount = Int(normalizedScalar(fields["failed"] ?? "")) ?? 0
        let repairedCount = repairedConfigCount + repairedMemoryCount

        let reasonLabel = humanizedHistoricalProjectBoundaryRepairReason(reasonToken)
        let detail = [
            reasonLabel.isEmpty ? "" : "原因=\(reasonLabel)",
            scannedCount > 0 ? "扫描=\(scannedCount)" : "",
            repairedConfigCount > 0 ? "补齐 config=\(repairedConfigCount)" : "",
            repairedMemoryCount > 0 ? "补齐 memory=\(repairedMemoryCount)" : "",
            failedCount > 0 ? "失败=\(failedCount)" : ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")

        let settingsDetail = firstMeaningfulScalar([
            detail,
            "从诊断页重新扫描 registry 已登记项目，补齐缺失的 config.json 和 project memory 边界。"
        ])
        let actionURL = XTDeepLinkURLBuilder.settingsURL(
            sectionId: "diagnostics",
            title: "历史项目修复",
            detail: settingsDetail,
            refreshAction: .repairHistoricalProjectBoundaries,
            refreshReason: "supervisor_historical_project_boundary_repair"
        )?.absoluteString

        return Item(
            id: "historical-project-boundary-repair",
            kind: .historicalProjectBoundaryRepair,
            iconName: historicalProjectBoundaryRepairIconName(for: outcome),
            title: "历史项目修复",
            summary: historicalProjectBoundaryRepairSummary(
                outcome: outcome,
                scannedCount: scannedCount,
                repairedCount: repairedCount,
                failedCount: failedCount
            ),
            detail: detail,
            badgeText: historicalProjectBoundaryRepairBadge(for: outcome),
            tone: historicalProjectBoundaryRepairTone(for: outcome),
            timestamp: nil,
            contractText: nil,
            nextSafeActionText: nil,
            actionURL: normalizedOptionalScalar(actionURL),
            actionLabel: outcome == "running" ? "打开诊断" : "重跑修复"
        )
    }

    private static func memoryAssemblyInfrastructureItem(
        readiness: SupervisorMemoryAssemblyReadiness?,
        snapshot: SupervisorMemoryAssemblySnapshot?
    ) -> Item? {
        guard let readiness,
              let issue = readiness.issues.first(where: {
                  $0.code == "memory_scoped_hidden_project_recovery_missing"
              }) else {
            return nil
        }

        let recoveredSections = snapshot?.normalizedScopedPromptRecoverySections ?? []
        let detail = [
            "显式 hidden focus 后仍未补回项目范围上下文",
            recoveredSections.isEmpty ? "恢复分区=(none)" : "恢复分区=\(recoveredSections.count) 项"
        ]
        .joined(separator: " · ")
        let actionURL = XTDeepLinkURLBuilder.settingsURL(
            sectionId: "diagnostics",
            title: "检查 hidden project recovery",
            detail: "打开诊断，检查 explicit hidden project focus 后的 scoped recovery 是否恢复项目范围上下文。",
            refreshReason: "supervisor_infra_hidden_project_scoped_recovery"
        )?.absoluteString

        return Item(
            id: "memory-assembly-hidden-project-scoped-recovery",
            kind: .memoryAssembly,
            iconName: issue.severity == .blocking ? "brain.head.profile" : "brain",
            title: "记忆装配提醒",
            summary: issue.summary,
            detail: detail,
            badgeText: issue.severity == .blocking ? "阻断" : "关注",
            tone: issue.severity == .blocking ? .critical : .attention,
            timestamp: snapshot?.updatedAt,
            contractText: "合同： memory_assembly · blocker=memory_scoped_hidden_project_recovery_missing",
            nextSafeActionText: SupervisorGuidanceContractLinePresentation.nextSafeActionLine(
                nextSafeAction: "open_diagnostics_and_reassemble_hidden_project_memory"
            ),
            actionURL: normalizedOptionalScalar(actionURL),
            actionLabel: actionURL == nil ? nil : "打开诊断"
        )
    }

    private static func candidateReviewInfrastructureItem(
        items: [HubIPCClient.SupervisorCandidateReviewItem],
        projectNamesByID: [String: String]
    ) -> Item? {
        guard let top = items.first else { return nil }

        let requestId = normalizedScalar(top.requestId)
        let reviewId = normalizedScalar(top.reviewId)
        let state = SupervisorCandidateReviewPresentation.stateText(top.reviewState)
        let projectIDs = candidateReviewProjectIDs(top)
        let projectLabels = projectIDs.map { projectNamesByID[$0] ?? $0 }
        let detail = [
            projectLabels.isEmpty ? "" : projectLabels.joined(separator: "、"),
            "状态=\(state)",
            top.candidateCount > 0 ? "候选=\(top.candidateCount)" : "",
            normalizedScalar(top.summaryLine)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
        let reviewState = normalizedScalar(top.reviewState).lowercased()
        let contractText = "合同： 候选记忆审查 · blocker=\(reviewState.isEmpty ? "candidate_review_pending" : reviewState)"
        let nextSafeActionText = candidateReviewNextSafeActionText(reviewState: reviewState)
        let actionURL = XTDeepLinkURLBuilder.supervisorURL(
            focusTarget: candidateReviewFocusRequestID(top) == nil ? nil : .candidateReview,
            requestId: candidateReviewFocusRequestID(top)
        )?.absoluteString
        let itemID = !requestId.isEmpty
            ? "candidate-review-\(requestId)"
            : (!reviewId.isEmpty ? "candidate-review-\(reviewId)" : "candidate-review")

        return Item(
            id: itemID,
            kind: .candidateReview,
            iconName: candidateReviewIconName(for: reviewState),
            title: "候选记忆审查",
            summary: "待处理 \(items.count) 项",
            detail: detail,
            badgeText: candidateReviewBadge(for: reviewState),
            tone: candidateReviewTone(for: reviewState),
            timestamp: candidateReviewTimestamp(top),
            contractText: contractText,
            nextSafeActionText: nextSafeActionText,
            actionURL: normalizedOptionalScalar(actionURL),
            actionLabel: "打开 Supervisor"
        )
    }

    private static func officialSkillsTone(for statusLine: String) -> Tone {
        let normalized = statusLine.lowercased()
        if normalized.contains("official failed") || normalized.contains("official missing") {
            return .critical
        }
        if normalized.contains("official healthy") {
            return .success
        }
        return .neutral
    }

    private static func officialSkillsBadge(for statusLine: String) -> String {
        switch officialSkillsTone(for: statusLine) {
        case .critical:
            return "降级"
        case .success:
            return "健康"
        case .attention:
            return "关注"
        case .neutral:
            return "观察"
        }
    }

    private static func infrastructureSummaryBase(
        officialStatus: String,
        attentionCount: Int
    ) -> String {
        if attentionCount > 0 {
            return "需关注 \(attentionCount) 项"
        }
        let normalized = officialStatus.lowercased()
        if normalized.contains("official healthy") {
            return "官方技能健康"
        }
        if !officialStatus.isEmpty {
            return "被动观察"
        }
        return "被动观察"
    }

    private static func infrastructureEventTriggerAllowed(_ raw: String) -> Bool {
        switch normalizedScalar(raw).lowercased() {
        case "official_skills_channel", "grant_resolution", "approval_resolution", "incident":
            return true
        default:
            return false
        }
    }

    private static func infrastructureEventTitle(_ raw: String) -> String {
        switch normalizedScalar(raw).lowercased() {
        case "official_skills_channel":
            return "官方技能跟进"
        case "grant_resolution":
            return "授权处理"
        case "approval_resolution":
            return "审批处理"
        case "incident":
            return "异常跟进"
        default:
            return "基础设施事件"
        }
    }

    private static func infrastructureEventIconName(_ raw: String) -> String {
        switch normalizedScalar(raw).lowercased() {
        case "official_skills_channel":
            return "shippingbox.fill"
        case "grant_resolution":
            return "checkmark.shield"
        case "approval_resolution":
            return "hand.raised.fill"
        case "incident":
            return "exclamationmark.triangle.fill"
        default:
            return "waveform.path.ecg"
        }
    }

    private static func infrastructureEventStatusBadge(_ raw: String) -> String {
        let normalized = normalizedScalar(raw).lowercased()
        switch normalized {
        case "completed":
            return "已完成"
        case "completed_empty":
            return "无动作"
        case "running":
            return "进行中"
        case "queued":
            return "排队中"
        case "failed":
            return "失败"
        default:
            return normalized.isEmpty ? "事件" : normalized
        }
    }

    private static func infrastructureEventTone(_ raw: String) -> Tone {
        switch normalizedScalar(raw).lowercased() {
        case "completed":
            return .success
        case "failed":
            return .critical
        case "queued", "running":
            return .attention
        default:
            return .neutral
        }
    }

    private static func infrastructureStatusLine(_ raw: String) -> String {
        let normalized = normalizedScalar(raw)
        guard !normalized.isEmpty else { return "" }
        let parts = normalized.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let head = parts.first.map(String.init)?.lowercased() ?? ""
        let tail = parts.count > 1 ? String(parts[1]) : ""

        let mappedHead: String
        switch head {
        case "idle":
            mappedHead = "空闲"
        case "queued":
            mappedHead = "排队中"
        case "running":
            mappedHead = "进行中"
        case "completed":
            mappedHead = "已完成"
        case "completed_empty":
            mappedHead = "无动作"
        case "failed":
            mappedHead = "失败"
        default:
            return normalized
        }

        return tail.isEmpty ? mappedHead : "\(mappedHead) \(tail)"
    }

    private static func candidateReviewTone(for reviewState: String) -> Tone {
        switch reviewState {
        case "pending_review", "staged", "in_review", "reviewed_pending_approval", "approved_for_writeback", "writeback_queued":
            return .attention
        case "rejected", "rolled_back":
            return .critical
        case "promoted":
            return .success
        default:
            return .attention
        }
    }

    private static func candidateReviewBadge(for reviewState: String) -> String {
        switch candidateReviewTone(for: reviewState) {
        case .attention:
            return "待审查"
        case .critical:
            return "异常"
        case .success:
            return "已推进"
        case .neutral:
            return "观察"
        }
    }

    private static func candidateReviewIconName(for reviewState: String) -> String {
        switch candidateReviewTone(for: reviewState) {
        case .attention:
            return "square.stack.3d.up.badge.a.fill"
        case .critical:
            return "exclamationmark.square.fill"
        case .success:
            return "checkmark.square.fill"
        case .neutral:
            return "square.stack.3d.up"
        }
    }

    private static func candidateReviewNextSafeActionText(reviewState: String) -> String {
        switch reviewState {
        case "pending_review":
            return SupervisorGuidanceContractLinePresentation.nextSafeActionLine(
                nextSafeAction: "open_candidate_review_board",
                recommendedActions: ["stage_to_review"]
            )
        case "staged", "in_review":
            return SupervisorGuidanceContractLinePresentation.nextSafeActionLine(
                nextSafeAction: "open_candidate_review_board",
                recommendedActions: ["continue_review"]
            )
        case "reviewed_pending_approval", "approved_for_writeback", "writeback_queued":
            return SupervisorGuidanceContractLinePresentation.nextSafeActionLine(
                nextSafeAction: "open_candidate_review_board",
                recommendedActions: ["follow_writeback_boundary"]
            )
        case "rejected", "rolled_back":
            return SupervisorGuidanceContractLinePresentation.nextSafeActionLine(
                nextSafeAction: "open_candidate_review_board",
                recommendedActions: ["inspect_rejection"]
            )
        case "promoted":
            return SupervisorGuidanceContractLinePresentation.nextSafeActionLine(
                nextSafeAction: "open_candidate_review_board",
                recommendedActions: ["verify_promotion"]
            )
        default:
            return SupervisorGuidanceContractLinePresentation.nextSafeActionLine(
                nextSafeAction: "open_candidate_review_board"
            )
        }
    }

    private static func candidateReviewProjectIDs(
        _ item: HubIPCClient.SupervisorCandidateReviewItem
    ) -> [String] {
        var ids = [normalizedScalar(item.projectId)] + item.projectIds.map(normalizedScalar)
        ids = ids.filter { !$0.isEmpty }

        var deduped: [String] = []
        var seen = Set<String>()
        for id in ids where seen.insert(id).inserted {
            deduped.append(id)
        }
        return deduped
    }

    private static func candidateReviewTimestamp(
        _ item: HubIPCClient.SupervisorCandidateReviewItem
    ) -> TimeInterval? {
        let rawMs = [item.stageUpdatedAtMs, item.latestEmittedAtMs, item.updatedAtMs, item.createdAtMs]
            .first(where: { $0 > 0 }) ?? 0
        guard rawMs > 0 else { return nil }
        return rawMs / 1000.0
    }

    private static func candidateReviewFocusRequestID(
        _ item: HubIPCClient.SupervisorCandidateReviewItem
    ) -> String? {
        normalizedOptionalScalar(item.requestId) ?? normalizedOptionalScalar(item.reviewId)
    }

    private static func normalizedEventProjectLabel(
        _ activity: SupervisorManager.SupervisorEventLoopActivity
    ) -> String {
        let projectName = normalizedScalar(activity.projectName)
        if !projectName.isEmpty, projectName != "Official Skills Channel" {
            return projectName
        }
        let projectId = normalizedScalar(activity.projectId)
        if !projectId.isEmpty {
            return projectId
        }
        return ""
    }

    private static func historicalProjectBoundaryRepairSummary(
        outcome: String,
        scannedCount: Int,
        repairedCount: Int,
        failedCount: Int
    ) -> String {
        switch outcome {
        case "running":
            return "正在扫描历史项目边界"
        case "repaired":
            return repairedCount > 0
                ? "已补齐 \(repairedCount) 处历史项目边界"
                : "历史项目边界已补齐"
        case "partial":
            if repairedCount > 0 && failedCount > 0 {
                return "已补齐 \(repairedCount) 处，仍有 \(failedCount) 个项目失败"
            }
            if failedCount > 0 {
                return "部分修复完成，仍有 \(failedCount) 个项目失败"
            }
            return "历史项目修复部分完成"
        case "failed":
            return failedCount > 0
                ? "修复失败，\(failedCount) 个项目未完成"
                : "历史项目修复失败"
        case "noop":
            return scannedCount > 0
                ? "已检查 \(scannedCount) 个项目，无需修复"
                : "历史项目边界已对齐"
        case "idle":
            return "尚未执行历史项目修复"
        default:
            return normalizedScalar(outcome).isEmpty ? "历史项目修复" : normalizedScalar(outcome)
        }
    }

    private static func historicalProjectBoundaryRepairTone(
        for outcome: String
    ) -> Tone {
        switch outcome {
        case "running", "partial":
            return .attention
        case "repaired":
            return .success
        case "failed":
            return .critical
        default:
            return .neutral
        }
    }

    private static func historicalProjectBoundaryRepairBadge(
        for outcome: String
    ) -> String {
        switch outcome {
        case "running":
            return "修复中"
        case "repaired":
            return "已补齐"
        case "partial":
            return "部分完成"
        case "failed":
            return "失败"
        case "noop":
            return "已检查"
        case "idle":
            return "待运行"
        default:
            return "观察"
        }
    }

    private static func historicalProjectBoundaryRepairIconName(
        for outcome: String
    ) -> String {
        switch outcome {
        case "running":
            return "wrench.and.screwdriver.fill"
        case "repaired":
            return "checkmark.seal.fill"
        case "partial":
            return "wrench.and.screwdriver"
        case "failed":
            return "exclamationmark.triangle.fill"
        default:
            return "shippingbox"
        }
    }

    private static func humanizedHistoricalProjectBoundaryRepairReason(
        _ raw: String
    ) -> String {
        switch normalizedScalar(raw).lowercased() {
        case "load_registry":
            return "启动时加载项目注册表"
        case "settings_diagnostics_manual":
            return "诊断页手动重跑"
        case "supervisor_historical_project_boundary_repair":
            return "Supervisor 触发重跑"
        case "test_manual":
            return "测试手动触发"
        default:
            return normalizedScalar(raw)
        }
    }

    private static func firstMeaningfulScalar(_ values: [String]) -> String {
        values.first { !$0.isEmpty } ?? ""
    }

    private static func normalizedOptionalScalar(_ value: String?) -> String? {
        let normalized = normalizedScalar(value ?? "")
        return normalized.isEmpty ? nil : normalized
    }

    private static func scalarFields(from raw: String?) -> [String: String] {
        normalizedScalar(raw ?? "")
            .split(separator: " ")
            .reduce(into: [String: String]()) { result, token in
                let parts = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return }
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !value.isEmpty else { return }
                result[key] = value
            }
    }

    private static func pendingGrantContractLine(
        for grant: SupervisorManager.SupervisorPendingGrant
    ) -> String? {
        let contract = pendingGrantContract(for: grant)
        return contract.map(SupervisorGuidanceContractLinePresentation.contractLine)
    }

    private static func pendingGrantNextSafeActionLine(
        for grant: SupervisorManager.SupervisorPendingGrant
    ) -> String? {
        let contract = pendingGrantContract(for: grant)
        return contract.map(SupervisorGuidanceContractLinePresentation.nextSafeActionLine)
    }

    private static func pendingGrantContract(
        for grant: SupervisorManager.SupervisorPendingGrant
    ) -> SupervisorGuidanceContractSummary? {
        let capability = normalizedScalar(grant.capability)
        let reason = normalizedScalar(grant.reason)
        let nextAction = normalizedScalar(grant.nextAction)
        guard !capability.isEmpty || !reason.isEmpty || !nextAction.isEmpty else {
            return nil
        }

        return SupervisorGuidanceContractSummary(
            kind: .grantResolution,
            trigger: "待处理授权",
            reviewLevel: "",
            verdict: "",
            summary: firstMeaningfulScalar([
                reason,
                capability
            ]),
            primaryBlocker: capability.isEmpty ? "grant_pending" : capability,
            currentState: "",
            nextStep: "",
            nextSafeAction: "open_hub_grants",
            recommendedActions: nextAction.isEmpty ? [] : [nextAction],
            workOrderRef: "",
            effectiveSupervisorTier: "",
            effectiveWorkOrderDepth: ""
        )
    }

    private static func pendingSkillApprovalStatusSummary(
        for approval: SupervisorManager.SupervisorPendingSkillApproval,
        authorizationMode: SupervisorPendingSkillAuthorizationMode,
        approvalMessage: XTGuardrailMessage
    ) -> String {
        switch authorizationMode {
        case .hubGrant:
            return firstMeaningfulScalar([
                normalizedScalar(approvalMessage.summary),
                normalizedScalar(approval.toolSummary),
                normalizedScalar(approval.reason)
            ])
        case .localApproval, .blocked:
            return firstMeaningfulScalar([
                normalizedScalar(approval.toolSummary),
                normalizedScalar(approval.reason),
                normalizedScalar(approvalMessage.summary)
            ])
        }
    }

    private static func pendingSkillApprovalContractText(
        routingNarrative: String?,
        activity: ProjectSkillActivityItem
    ) -> String? {
        if let routingNarrative = normalizedOptionalScalar(routingNarrative) {
            return "路由说明： \(routingNarrative)"
        }

        return normalizedOptionalScalar(
            XTPendingApprovalPresentation.governedSkillDetailLines(for: activity)
                .first(where: { line in
                    line.hasPrefix("执行就绪：") || line.hasPrefix("治理闸门：")
                })
        )
    }

    private static func pendingSkillApprovalNextSafeActionText(
        activity: ProjectSkillActivityItem,
        approvalMessage: XTGuardrailMessage
    ) -> String? {
        if let nextStep = normalizedOptionalScalar(approvalMessage.nextStep) {
            return "安全下一步： \(nextStep)"
        }

        guard !activity.unblockActions.isEmpty else { return nil }
        return "安全下一步： \(XTPendingApprovalPresentation.displayUnblockActionList(activity.unblockActions))"
    }

    private static func normalizedScalar(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
