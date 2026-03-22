import Foundation

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
            modeText: "本地审批",
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
        let displaySkill = SupervisorSkillActivityPresentation.displaySkillSummary(
            requestedSkillId: approval.requestedSkillId,
            effectiveSkillId: approval.skillId,
            routingReasonCode: approval.routingReasonCode,
            routingExplanation: approval.routingExplanation
        )
        let message = XTPendingApprovalPresentation.approvalMessage(
            toolName: approval.toolName,
            tool: approval.tool,
            toolSummary: approval.toolSummary
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
            routingText: SupervisorSkillActivityPresentation.routingLine(
                requestedSkillId: approval.requestedSkillId,
                effectiveSkillId: approval.skillId,
                routingReasonCode: approval.routingReasonCode,
                routingExplanation: approval.routingExplanation
            ),
            routingExplanationText: nonEmpty(routingExplanationText),
            noteText: nonEmpty(note).map { "补充说明：\($0)" },
            requestIdentifierText: "请求单号：\(approval.requestId)",
            isFocused: isFocused,
            actionDescriptors: SupervisorCardActionResolver.pendingSkillApprovalActions(approval)
        )
    }

    static func iconName(
        _ approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> String {
        if let tool = approval.tool {
            return XTPendingApprovalPresentation.iconName(for: tool)
        }
        return "hand.raised.fill"
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
