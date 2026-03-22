import Foundation

struct SupervisorInfrastructureFeedInput: Equatable {
    var officialSkillsStatusLine: String
    var officialSkillsTransitionLine: String
    var officialSkillsTopBlockersLine: String
    var officialSkillsTopBlockerSummaries: [AXOfficialSkillBlockerSummaryItem] = []
    var builtinGovernedSkills: [AXBuiltinGovernedSkillSummary] = []
    var managedSkillsStatusLine: String = ""
    var eventLoopStatusLine: String
    var pendingHubGrants: [SupervisorManager.SupervisorPendingGrant]
    var pendingSupervisorSkillApprovals: [SupervisorManager.SupervisorPendingSkillApproval]
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
            case pendingHubGrant = "pending_hub_grant"
            case pendingSkillApproval = "pending_skill_approval"
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
            let skillLabel = firstMeaningfulScalar([
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
            let detail = [
                normalizedScalar(top.projectName),
                skillLabel,
                firstMeaningfulScalar([
                    normalizedScalar(top.toolSummary),
                    normalizedScalar(top.reason)
                ])
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            items.append(
                Item(
                    id: "pending-skill-approvals",
                    kind: .pendingSkillApproval,
                    iconName: "hand.raised.square.on.square",
                    title: "本地技能审批",
                    summary: "待处理 \(input.pendingSupervisorSkillApprovals.count) 项",
                    detail: detail,
                    badgeText: "待处理",
                    tone: .attention,
                    timestamp: top.createdAt,
                    contractText: normalizedOptionalScalar(
                        routingNarrative.map { "路由说明： \($0)" }
                    ),
                    nextSafeActionText: nil,
                    actionURL: normalizedOptionalScalar(top.actionURL),
                    actionLabel: "打开审批"
                )
            )
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

    private static func firstMeaningfulScalar(_ values: [String]) -> String {
        values.first { !$0.isEmpty } ?? ""
    }

    private static func normalizedOptionalScalar(_ value: String?) -> String? {
        let normalized = normalizedScalar(value ?? "")
        return normalized.isEmpty ? nil : normalized
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

    private static func normalizedScalar(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
