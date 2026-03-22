import SwiftUI

@MainActor
enum SupervisorViewFocusRequestExecution {
    struct Dependencies {
        let currentSelectedProjectID: String?
        let currentRefreshAttemptNonce: Int?
        let setSignalCenterVisible: (Bool) -> Void
        let setSelectedPortfolioProjectID: (String?) -> Void
        let selectProject: (String) -> Void
        let scrollToAnchor: (String) -> Void
        let setHighlightedPendingHubGrantAnchor: (String?) -> Void
        let setHighlightedPendingSkillApprovalAnchor: (String?) -> Void
        let setHighlightedRecentSkillActivityRequestID: (String?) -> Void
        let setAuditDrillDown: (SupervisorAuditDrillDownSelection?) -> Void
        let setRefreshAttemptNonce: (Int?) -> Void
        let refreshPendingHubGrants: () -> Void
        let refreshPendingSkillApprovals: () -> Void
        let refreshRecentSkillActivities: () -> Void
        let completeRequest: (AXSupervisorFocusRequest) -> Void
    }

    static func apply(
        plan: SupervisorFocusRequestEffects.Plan,
        request: AXSupervisorFocusRequest,
        dependencies: Dependencies
    ) {
        dependencies.setSignalCenterVisible(true)

        if let resolvedProjectId = plan.selectedProjectId,
           !resolvedProjectId.isEmpty {
            dependencies.setSelectedPortfolioProjectID(resolvedProjectId)
            if dependencies.currentSelectedProjectID != resolvedProjectId {
                dependencies.selectProject(resolvedProjectId)
            }
        }

        dependencies.scrollToAnchor(plan.boardAnchorID)

        dependencies.setHighlightedPendingHubGrantAnchor(plan.highlights.pendingHubGrantAnchor)
        dependencies.setHighlightedPendingSkillApprovalAnchor(plan.highlights.pendingSupervisorSkillApprovalAnchor)
        dependencies.setHighlightedRecentSkillActivityRequestID(plan.highlights.recentSkillActivityRequestId)

        if let rowAnchorID = plan.rowAnchorID {
            dependencies.scrollToAnchor(rowAnchorID)
        }

        if let auditDrillDown = plan.auditDrillDown {
            dependencies.setAuditDrillDown(auditDrillDown)
        }

        guard let refresh = plan.refresh else {
            dependencies.completeRequest(request)
            return
        }

        guard dependencies.currentRefreshAttemptNonce != request.nonce else {
            dependencies.completeRequest(request)
            return
        }

        dependencies.setRefreshAttemptNonce(request.nonce)
        switch refresh {
        case .pendingHubGrants:
            dependencies.refreshPendingHubGrants()
        case .pendingSupervisorSkillApprovals:
            dependencies.refreshPendingSkillApprovals()
        case .recentSupervisorSkillActivities:
            dependencies.refreshRecentSkillActivities()
        }
    }
}
