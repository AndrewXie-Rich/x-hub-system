import Foundation

enum SupervisorCardAction: Equatable {
    case openAudit(SupervisorAuditDrillDownAction)
    case openURL(label: String, url: String)
    case openProjectGovernance(projectId: String, destination: XTProjectGovernanceDestination)
    case stageSupervisorCandidateReview(HubIPCClient.SupervisorCandidateReviewItem)
    case approvePendingGrant(SupervisorManager.SupervisorPendingGrant)
    case denyPendingGrant(SupervisorManager.SupervisorPendingGrant)
    case approvePendingSkillApproval(SupervisorManager.SupervisorPendingSkillApproval)
    case denyPendingSkillApproval(SupervisorManager.SupervisorPendingSkillApproval)
    case approveSkillActivity(SupervisorManager.SupervisorRecentSkillActivity)
    case denySkillActivity(SupervisorManager.SupervisorRecentSkillActivity)
    case retrySkillActivity(SupervisorManager.SupervisorRecentSkillActivity)
}

struct SupervisorCardActionDescriptor: Equatable, Identifiable {
    enum Style: Equatable {
        case prominent
        case standard
    }

    var action: SupervisorCardAction
    var label: String
    var style: Style
    var isEnabled: Bool

    var id: String {
        "\(label)|\(style)|\(isEnabled)|\(action)"
    }
}

enum SupervisorCardActionResolver {
    static func candidateReviewActions(
        _ item: HubIPCClient.SupervisorCandidateReviewItem,
        inFlight: Bool,
        canAct: Bool
    ) -> [SupervisorCardActionDescriptor] {
        let reviewState = normalizedScalar(item.reviewState)?.lowercased() ?? ""
        guard reviewState == "pending_review" else { return [] }
        return [
            .init(
                action: .stageSupervisorCandidateReview(item),
                label: "转入审查",
                style: .prominent,
                isEnabled: canAct && !inFlight
            )
        ]
    }

    static func pendingHubGrantActions(
        _ grant: SupervisorManager.SupervisorPendingGrant,
        inFlight: Bool,
        canAct: Bool
    ) -> [SupervisorCardActionDescriptor] {
        var actions: [SupervisorCardActionDescriptor] = [
            .init(
                action: .openAudit(.pendingGrant(grant)),
                label: "详情",
                style: .standard,
                isEnabled: !inFlight
            )
        ]

        if let actionURL = normalizedScalar(grant.actionURL) {
            actions.append(
                .init(
                    action: .openURL(label: "打开", url: actionURL),
                    label: "打开",
                    style: .standard,
                    isEnabled: !inFlight
                )
            )
        }

        actions.append(
            .init(
                action: .approvePendingGrant(grant),
                label: "批准",
                style: .prominent,
                isEnabled: canAct && !inFlight
            )
        )
        actions.append(
            .init(
                action: .denyPendingGrant(grant),
                label: "拒绝",
                style: .standard,
                isEnabled: canAct && !inFlight
            )
        )
        return actions
    }

    static func pendingSkillApprovalActions(
        _ approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> [SupervisorCardActionDescriptor] {
        var actions: [SupervisorCardActionDescriptor] = [
            .init(
                action: .openAudit(.pendingSkillApproval(approval)),
                label: "详情",
                style: .standard,
                isEnabled: true
            )
        ]

        if let actionURL = normalizedScalar(approval.actionURL) {
            actions.append(
                .init(
                    action: .openURL(label: "打开", url: actionURL),
                    label: "打开",
                    style: .standard,
                    isEnabled: true
                )
            )
        }

        actions.append(
            SupervisorPendingSkillApprovalPresentation.prominentActionDescriptor(for: approval)
        )
        actions.append(
            .init(
                action: .denyPendingSkillApproval(approval),
                label: "拒绝",
                style: .standard,
                isEnabled: true
            )
        )
        return actions
    }

    static func recentSkillActivityActions(
        _ item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> [SupervisorCardActionDescriptor] {
        var actions: [SupervisorCardActionDescriptor] = []

        if let repairAction = governanceRepairAction(
            projectId: item.projectId,
            denyCode: item.denyCode,
            policySource: item.policySource,
            policyReason: item.policyReason
        ) {
            actions.append(repairAction)
        }

        if SupervisorSkillActivityPresentation.isAwaitingLocalApproval(item) {
            actions.append(
                .init(
                    action: .approveSkillActivity(item),
                    label: "批准",
                    style: .prominent,
                    isEnabled: true
                )
            )
            actions.append(
                .init(
                    action: .denySkillActivity(item),
                    label: "拒绝",
                    style: .standard,
                    isEnabled: true
                )
            )
        }

        if SupervisorSkillActivityPresentation.canRetry(item) {
            actions.append(
                .init(
                    action: .retrySkillActivity(item),
                    label: "重试",
                    style: .standard,
                    isEnabled: true
                )
            )
        }

        if let actionURL = normalizedScalar(item.actionURL) {
            let label = SupervisorSkillActivityPresentation.actionButtonTitle(for: item)
            actions.append(
                .init(
                    action: .openURL(label: label, url: actionURL),
                    label: label,
                    style: .standard,
                    isEnabled: true
                )
            )
        }

        actions.append(
            .init(
                action: .openAudit(.recentSkillActivity(item)),
                label: "查看详情",
                style: .standard,
                isEnabled: true
            )
        )

        return actions
    }

    static func eventLoopActions(
        _ item: SupervisorManager.SupervisorEventLoopActivity,
        action: SupervisorEventLoopActionPresentation?
    ) -> [SupervisorCardActionDescriptor] {
        var actions: [SupervisorCardActionDescriptor] = [
            .init(
                action: .openAudit(.eventLoop(item)),
                label: "详情",
                style: .standard,
                isEnabled: true
            )
        ]

        if let action,
           let url = normalizedScalar(action.url) {
            actions.append(
                .init(
                    action: .openURL(label: action.label, url: url),
                    label: action.label,
                    style: .standard,
                    isEnabled: true
                )
            )
        }

        return actions
    }

    static func infrastructureActions(
        _ item: SupervisorInfrastructureFeedPresentation.Item
    ) -> [SupervisorCardActionDescriptor] {
        var actions: [SupervisorCardActionDescriptor] = [
            .init(
                action: .openAudit(.infrastructureItem(item)),
                label: "详情",
                style: .standard,
                isEnabled: true
            )
        ]

        if let actionLabel = normalizedScalar(item.actionLabel),
           let actionURL = normalizedScalar(item.actionURL) {
            actions.append(
                .init(
                    action: .openURL(label: actionLabel, url: actionURL),
                    label: actionLabel,
                    style: .standard,
                    isEnabled: true
                )
            )
        }

        return actions
    }

    static func auditSheetActions(
        _ detail: SupervisorAuditDrillDownSelection
    ) -> [SupervisorCardActionDescriptor] {
        var actions: [SupervisorCardActionDescriptor] = []

        if let actionLabel = normalizedScalar(detail.presentation.actionLabel),
           let actionURL = normalizedScalar(detail.presentation.actionURL) {
            actions.append(
                .init(
                    action: .openURL(label: actionLabel, url: actionURL),
                    label: actionLabel,
                    style: .standard,
                    isEnabled: true
                )
            )
        }

        actions.append(
            contentsOf: detail.presentation.secondaryActions.compactMap { action in
                guard let label = normalizedScalar(action.label),
                      let url = normalizedScalar(action.url) else {
                    return nil
                }
                return .init(
                    action: .openURL(label: label, url: url),
                    label: label,
                    style: .standard,
                    isEnabled: true
                )
            }
        )

        switch detail.source {
        case .candidateReview(let item):
            actions.append(contentsOf: candidateReviewActions(
                item,
                inFlight: false,
                canAct: true
            ))
        case .pendingGrant(let grant):
            actions.append(
                .init(
                    action: .approvePendingGrant(grant),
                    label: "批准",
                    style: .prominent,
                    isEnabled: true
                )
            )
            actions.append(
                .init(
                    action: .denyPendingGrant(grant),
                    label: "拒绝",
                    style: .standard,
                    isEnabled: true
                )
            )
        case .pendingSkillApproval(let approval):
            actions.append(
                .init(
                    action: .approvePendingSkillApproval(approval),
                    label: "批准",
                    style: .prominent,
                    isEnabled: true
                )
            )
            actions.append(
                .init(
                    action: .denyPendingSkillApproval(approval),
                    label: "拒绝",
                    style: .standard,
                    isEnabled: true
                )
            )
        case .recentSkillActivity(let item):
            actions.append(contentsOf: recentSkillActivityActions(item).filter {
                switch $0.action {
                case .openAudit, .openURL:
                    return false
                default:
                    return true
                }
            })
        case .fullRecordFallback(let projectId, _, let record):
            if let repairAction = governanceRepairAction(
                projectId: projectId,
                record: record
            ) {
                actions.append(repairAction)
            }
        case .officialSkillsChannel, .xtBuiltinGovernedSkills, .eventLoop:
            break
        }

        return actions
    }

    private static func normalizedScalar(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func governanceRepairAction(
        projectId: String,
        denyCode: String,
        policySource: String = "",
        policyReason: String = ""
    ) -> SupervisorCardActionDescriptor? {
        guard let normalizedProjectId = normalizedScalar(projectId),
              let hint = XTGuardrailMessagePresentation.repairHint(
                  denyCode: denyCode,
                  policySource: policySource,
                  policyReason: policyReason
              ) else {
            return nil
        }

        return .init(
            action: .openProjectGovernance(
                projectId: normalizedProjectId,
                destination: hint.destination
            ),
            label: hint.buttonTitle,
            style: .standard,
            isEnabled: true
        )
    }

    private static func governanceRepairAction(
        projectId: String,
        record: SupervisorSkillFullRecord
    ) -> SupervisorCardActionDescriptor? {
        governanceRepairAction(
            projectId: projectId,
            denyCode: approvalFieldValue("deny_code", in: record),
            policySource: approvalFieldValue("policy_source", in: record),
            policyReason: approvalFieldValue("policy_reason", in: record)
        )
    }

    private static func approvalFieldValue(
        _ label: String,
        in record: SupervisorSkillFullRecord
    ) -> String {
        record.approvalFields.first(where: {
            $0.label.caseInsensitiveCompare(label) == .orderedSame
        })?.value ?? ""
    }
}
