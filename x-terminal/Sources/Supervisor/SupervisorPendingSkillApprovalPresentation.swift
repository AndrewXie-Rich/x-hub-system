import Foundation

enum SupervisorPendingSkillAuthorizationMode: Hashable {
    case localApproval
    case hubGrant
    case blocked
}

struct SupervisorPendingSkillApprovalRowPresentation: Equatable, Identifiable {
    var id: String
    var anchorID: String
    var iconName: String
    var title: String
    var ageText: String
    var summary: String
    var nextStepText: String?
    var routingText: String? = nil
    var routingExplanationText: String? = nil
    var noteText: String?
    var requestIdentifierText: String
    var isFocused: Bool
    var actionDescriptors: [SupervisorCardActionDescriptor]
    var authorizationMode: SupervisorPendingSkillAuthorizationMode = .localApproval
}

struct SupervisorPendingSkillApprovalBoardPresentation: Equatable {
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var title: String
    var modeText: String
    var emptyStateText: String?
    var rows: [SupervisorPendingSkillApprovalRowPresentation]

    var isEmpty: Bool {
        rows.isEmpty
    }
}

enum SupervisorPendingSkillApprovalPresentation {
    static func board(
        approvals: [SupervisorManager.SupervisorPendingSkillApproval],
        focusedRowAnchor: String?
    ) -> SupervisorPendingSkillApprovalBoardPresentation {
        SupervisorPendingSkillApprovalBoardPresentation(
            iconName: approvals.isEmpty ? "checkmark.shield" : "hand.raised.fill",
            iconTone: approvals.isEmpty ? .neutral : .warning,
            title: "待审批技能：\(approvals.count)",
            modeText: boardModeText(for: approvals),
            emptyStateText: approvals.isEmpty
                ? "当前没有待审批的 Supervisor 高风险技能。"
                : nil,
            rows: approvals.map {
                row(
                    $0,
                    isFocused: focusedRowAnchor == SupervisorFocusPresentation.pendingSupervisorSkillApprovalRowAnchor($0)
                )
            }
        )
    }

    static func row(
        _ approval: SupervisorManager.SupervisorPendingSkillApproval,
        isFocused: Bool
    ) -> SupervisorPendingSkillApprovalRowPresentation {
        let routingSummary = SupervisorSkillActivityPresentation.displaySkillSummary(
            requestedSkillId: approval.requestedSkillId,
            effectiveSkillId: approval.skillId,
            routingReasonCode: approval.routingReasonCode,
            routingExplanation: approval.routingExplanation
        )
        let displaySkill = SupervisorSkillActivityPresentation.governedShortSummary(for: approval)
            ?? routingSummary
        let activityItem = SupervisorSkillActivityPresentation.governedSkillPresentationItem(
            for: approval
        )
        let message = XTPendingApprovalPresentation.approvalMessage(
            toolName: approval.toolName,
            tool: approval.tool,
            toolSummary: approval.toolSummary,
            activity: activityItem
        )
        let note = XTPendingApprovalPresentation.supplementaryReason(
            approval.reason,
            primaryMessage: message
        )
        let routingExplanationText = SupervisorSkillActivityPresentation.routingNarrative(
            requestedSkillId: approval.requestedSkillId,
            effectiveSkillId: approval.skillId,
            routingReasonCode: approval.routingReasonCode,
            routingExplanation: approval.routingExplanation
        ).map { "路由说明： \($0)" }
        let governedContextLines = SupervisorSkillActivityPresentation.governedApprovalContextLines(
            requestID: approval.requestId,
            skillID: approval.skillId,
            requestedSkillID: approval.requestedSkillId,
            toolName: approval.toolName,
            status: "awaiting_authorization",
            deltaApproval: approval.deltaApproval,
            readiness: approval.readiness
        )
        let noteLines = noteLines(
            governedContextLines: governedContextLines,
            supplementaryReason: note
        )

        return SupervisorPendingSkillApprovalRowPresentation(
            id: approval.id,
            anchorID: SupervisorFocusPresentation.pendingSupervisorSkillApprovalRowAnchor(approval),
            iconName: iconName(approval),
            title: displaySkill.isEmpty
                ? approval.projectName
                : "\(approval.projectName) · \(displaySkill)",
            ageText: SupervisorPendingHubGrantPresentation.ageText(approval.createdAt),
            summary: message.summary,
            nextStepText: nonEmpty(message.nextStep),
            routingText: nil,
            routingExplanationText: nonEmpty(routingExplanationText),
            noteText: nonEmpty(noteLines.joined(separator: "\n")),
            requestIdentifierText: "请求单号：\(approval.requestId)",
            isFocused: isFocused,
            actionDescriptors: SupervisorCardActionResolver.pendingSkillApprovalActions(approval),
            authorizationMode: authorizationMode(for: approval)
        )
    }

    static func authorizationMode(
        for approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> SupervisorPendingSkillAuthorizationMode {
        switch normalizedReadinessToken(approval.readiness?.executionReadiness) {
        case XTSkillExecutionReadinessState.grantRequired.rawValue:
            return .hubGrant
        case "",
             XTSkillExecutionReadinessState.ready.rawValue,
             XTSkillExecutionReadinessState.degraded.rawValue,
             XTSkillExecutionReadinessState.localApprovalRequired.rawValue:
            return .localApproval
        default:
            return .blocked
        }
    }

    static func overviewHeadline(
        for row: SupervisorPendingSkillApprovalRowPresentation
    ) -> String {
        switch row.authorizationMode {
        case .localApproval:
            return "待审批技能"
        case .hubGrant:
            return "技能授权待处理"
        case .blocked:
            return "技能治理待处理"
        }
    }

    static func overviewFocusLabel(
        for row: SupervisorPendingSkillApprovalRowPresentation
    ) -> String {
        switch row.authorizationMode {
        case .localApproval:
            return "查看技能审批"
        case .hubGrant:
            return "查看技能授权"
        case .blocked:
            return "查看技能处理"
        }
    }

    static func openActionLabel(
        for approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> String {
        switch authorizationMode(for: approval) {
        case .localApproval:
            return "打开审批"
        case .hubGrant:
            return "打开授权"
        case .blocked:
            return "打开处理"
        }
    }

    static func infrastructureTitle(
        for approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> String {
        switch authorizationMode(for: approval) {
        case .localApproval:
            return "本地技能审批"
        case .hubGrant:
            return "技能授权待处理"
        case .blocked:
            return "技能治理待处理"
        }
    }

    static func infrastructureBadgeText(
        for approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> String {
        switch authorizationMode(for: approval) {
        case .localApproval:
            return "待审批"
        case .hubGrant:
            return "待授权"
        case .blocked:
            return "阻塞"
        }
    }

    static func drillDownTitle(
        for approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> String {
        switch authorizationMode(for: approval) {
        case .localApproval:
            return "本地技能审批待处理"
        case .hubGrant:
            return "技能授权待处理"
        case .blocked:
            return "技能治理待处理"
        }
    }

    static func prominentActionDescriptor(
        for approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> SupervisorCardActionDescriptor {
        switch authorizationMode(for: approval) {
        case .localApproval:
            return .init(
                action: .approvePendingSkillApproval(approval),
                label: "批准",
                style: .prominent,
                isEnabled: true
            )
        case .hubGrant:
            if let actionURL = nonEmpty(approval.actionURL) {
                return .init(
                    action: .openURL(label: "打开授权", url: actionURL),
                    label: "打开授权",
                    style: .prominent,
                    isEnabled: true
                )
            }
            return .init(
                action: .openAudit(.pendingSkillApproval(approval)),
                label: "查看授权",
                style: .prominent,
                isEnabled: true
            )
        case .blocked:
            if let actionURL = nonEmpty(approval.actionURL) {
                return .init(
                    action: .openURL(label: "打开处理", url: actionURL),
                    label: "打开处理",
                    style: .prominent,
                    isEnabled: true
                )
            }
            return .init(
                action: .openAudit(.pendingSkillApproval(approval)),
                label: "查看阻塞",
                style: .prominent,
                isEnabled: true
            )
        }
    }

    static func iconName(
        _ approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> String {
        if let tool = approval.tool {
            return XTPendingApprovalPresentation.iconName(for: tool)
        }
        return "hand.raised.fill"
    }

    private static func boardModeText(
        for approvals: [SupervisorManager.SupervisorPendingSkillApproval]
    ) -> String {
        guard !approvals.isEmpty else { return "本地审批" }

        let modes = approvals.map(authorizationMode(for:))
        var parts: [String] = []
        if modes.contains(.localApproval) {
            parts.append("本地审批")
        }
        if modes.contains(.hubGrant) {
            parts.append(modes.allSatisfy { $0 == .hubGrant } ? "等待 Hub grant" : "Hub grant")
        }
        if modes.contains(.blocked) {
            parts.append("治理阻塞")
        }
        return parts.isEmpty ? "本地审批" : parts.joined(separator: " + ")
    }

    private static func noteLines(
        governedContextLines: [String],
        supplementaryReason: String?
    ) -> [String] {
        var lines: [String] = []

        if let deltaLine = governedContextLines.first(where: { $0.hasPrefix("能力增量：") }) {
            lines.append(deltaLine)
        }

        let gateLine = governedContextLines.first(where: { $0.hasPrefix("授权门槛：") })
        let readinessLine = governedContextLines.first(where: { $0.hasPrefix("执行就绪：") })

        if let gateLine, let readinessLine {
            lines.append("\(gateLine)；\(readinessLine)")
        } else if let readinessLine {
            lines.append(readinessLine)
        } else if let gateLine {
            lines.append(gateLine)
        }

        if lines.isEmpty {
            lines.append(contentsOf: governedContextLines.prefix(2))
        }

        if let supplementaryReason = nonEmpty(supplementaryReason) {
            lines.append("补充说明：\(supplementaryReason)")
        }

        return lines
    }

    private static func normalizedReadinessToken(
        _ raw: String?
    ) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
