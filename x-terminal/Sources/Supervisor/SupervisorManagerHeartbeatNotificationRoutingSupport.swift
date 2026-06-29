import Foundation

extension SupervisorManager {
    func heartbeatNotificationHasRouteDiagnoseAction(
        _ focusActionURL: String?
    ) -> Bool {
        let raw = focusActionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let route = XTDeepLinkParser.parse(url) else {
            return false
        }

        switch route {
        case let .project(projectRoute):
            return projectRoute.focusTarget == .routeDiagnose
        default:
            return false
        }
    }

    func heartbeatNotificationAuthorizationDestination(
        _ focusActionURL: String?
    ) -> HeartbeatAuthorizationNotificationDestination? {
        let raw = focusActionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let route = XTDeepLinkParser.parse(url) else {
            return nil
        }

        let focusTarget: XTDeepLinkFocusTarget?
        switch route {
        case .project(let projectRoute):
            focusTarget = projectRoute.focusTarget
        case .supervisor(let supervisorRoute):
            focusTarget = supervisorRoute.focusTarget
        default:
            focusTarget = nil
        }

        switch focusTarget {
        case .grant:
            return .grant
        case .approval:
            return .approval
        case .toolApproval:
            return .toolApproval
        case .candidateReview, .skillRecord, .projectCreationBoard, .routeDiagnose, nil:
            return nil
        }
    }

    func heartbeatNotificationRouteRepairDestination(
        _ focusActionURL: String?,
        nextStepSummary: String
    ) -> HeartbeatRouteRepairNotificationDestination? {
        guard heartbeatRouteDiagnoseHighlight(nextStepSummary: nextStepSummary) != nil else {
            return nil
        }
        let raw = focusActionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let route = XTDeepLinkParser.parse(url) else {
            return nil
        }

        switch route {
        case .supervisorModelSettings:
            return .modelSettings
        case .settings(let settingsRoute):
            return settingsRoute.sectionId == "diagnostics" ? .xtDiagnostics : nil
        case .hubSetup(let hubRoute):
            switch hubRoute.sectionId {
            case "connection_log":
                return .hubConnectionLog
            case "troubleshoot":
                return .hubRecovery
            default:
                return nil
            }
        case .project(let projectRoute):
            return projectRoute.focusTarget == .routeDiagnose ? .routeDiagnose : nil
        default:
            return nil
        }
    }

    func heartbeatNotificationHasGovernanceRepairAction(
        _ focusActionURL: String?
    ) -> Bool {
        let raw = focusActionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let route = XTDeepLinkParser.parse(url) else {
            return false
        }

        switch route {
        case let .project(projectRoute):
            return projectRoute.governanceDestination != nil
        default:
            return false
        }
    }

    func heartbeatNotificationHasHubLoadAction(
        _ focusActionURL: String?,
        hubLoadSignal: HeartbeatHubLoadSignal?
    ) -> Bool {
        let focus = focusActionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hubAction = hubLoadSignal?.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !focus.isEmpty && !hubAction.isEmpty && focus == hubAction
    }

    func heartbeatRouteDiagnoseHighlight(
        nextStepSummary: String
    ) -> String? {
        let lines = SupervisorHeartbeatPresentation.userFacingSanitizedLines(
            from: nextStepSummary
        )

        if let routeLine = lines.first(where: { $0.contains("模型路由：") || $0.contains("/route diagnose") }) {
            return routeLine
        }
        return nil
    }

    func heartbeatGovernanceRepairHighlight(
        governanceRepairSummary: String,
        nextStepSummary: String
    ) -> String? {
        let summaryLines = SupervisorHeartbeatPresentation.userFacingSanitizedLines(
            from: governanceRepairSummary
        )
        if let first = summaryLines.first {
            return first
        }

        let lines = SupervisorHeartbeatPresentation.userFacingSanitizedLines(
            from: nextStepSummary
        )

        if let governanceLine = lines.first(where: {
            $0.contains("治理修复：")
                || $0.contains("A-Tier")
                || $0.contains("S-Tier")
                || $0.contains("Heartbeat / Review")
                || $0.contains("Execution Tier")
                || $0.contains("Supervisor Tier")
                || $0.contains("Heartbeat & Review")
                || $0.contains("Project Governance")
        }) {
            return governanceLine
        }
        return nil
    }

    func heartbeatPermissionNotificationHighlight(
        permissionSummary: String,
        nextStepSummary: String
    ) -> String? {
        let permissionLines = SupervisorHeartbeatPresentation.userFacingSanitizedLines(
            from: permissionSummary
        )
        if let first = permissionLines.first {
            return first
        }

        let nextStepLines = SupervisorHeartbeatPresentation.userFacingSanitizedLines(
            from: nextStepSummary
        )
        if let permissionStep = nextStepLines.first(where: {
            $0.contains("授权") || $0.contains("审批") || $0.contains("批准")
        }) {
            return permissionStep
        }
        return nextStepLines.first
    }
}
