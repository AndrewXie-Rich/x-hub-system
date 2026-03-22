import SwiftUI

@MainActor
extension SupervisorViewActionSupport {
    static func resolveFocusRequest(
        request: AXSupervisorFocusRequest?,
        context: SupervisorFocusRequestEffects.Context,
        loadRecentSkillRecord: @escaping (String, String, String) -> SupervisorSkillFullRecord?,
        loadFallbackSkillRecord: @escaping (String, String) -> SupervisorFocusRequestEffects.FallbackSkillRecord?
    ) -> (AXSupervisorFocusRequest, SupervisorFocusRequestEffects.Plan)? {
        guard let request else {
            return nil
        }

        let plan = SupervisorFocusRequestEffects.resolve(
            request: request,
            context: context,
            loadRecentSkillRecord: loadRecentSkillRecord,
            loadFallbackSkillRecord: loadFallbackSkillRecord
        )
        return (request, plan)
    }

    static func focusRequestExecutionDependencies(
        currentSelectedProjectID: String?,
        currentRefreshAttemptNonce: Int?,
        setSignalCenterVisible: @escaping (Bool) -> Void,
        setSelectedPortfolioProjectID: @escaping (String?) -> Void,
        selectProject: @escaping (String) -> Void,
        scrollToAnchor: @escaping (String) -> Void,
        setHighlightedPendingHubGrantAnchor: @escaping (String?) -> Void,
        setHighlightedPendingSkillApprovalAnchor: @escaping (String?) -> Void,
        setHighlightedRecentSkillActivityRequestID: @escaping (String?) -> Void,
        setAuditDrillDown: @escaping (SupervisorAuditDrillDownSelection?) -> Void,
        setRefreshAttemptNonce: @escaping (Int?) -> Void,
        refreshPendingHubGrants: @escaping () -> Void,
        refreshPendingSkillApprovals: @escaping () -> Void,
        refreshRecentSkillActivities: @escaping () -> Void,
        completeRequest: @escaping (AXSupervisorFocusRequest) -> Void
    ) -> SupervisorViewFocusRequestExecution.Dependencies {
        .init(
            currentSelectedProjectID: currentSelectedProjectID,
            currentRefreshAttemptNonce: currentRefreshAttemptNonce,
            setSignalCenterVisible: setSignalCenterVisible,
            setSelectedPortfolioProjectID: setSelectedPortfolioProjectID,
            selectProject: selectProject,
            scrollToAnchor: scrollToAnchor,
            setHighlightedPendingHubGrantAnchor: setHighlightedPendingHubGrantAnchor,
            setHighlightedPendingSkillApprovalAnchor: setHighlightedPendingSkillApprovalAnchor,
            setHighlightedRecentSkillActivityRequestID: setHighlightedRecentSkillActivityRequestID,
            setAuditDrillDown: setAuditDrillDown,
            setRefreshAttemptNonce: setRefreshAttemptNonce,
            refreshPendingHubGrants: refreshPendingHubGrants,
            refreshPendingSkillApprovals: refreshPendingSkillApprovals,
            refreshRecentSkillActivities: refreshRecentSkillActivities,
            completeRequest: completeRequest
        )
    }

    static func performFocusRequest(
        request: AXSupervisorFocusRequest?,
        context: SupervisorFocusRequestEffects.Context,
        loadRecentSkillRecord: @escaping (String, String, String) -> SupervisorSkillFullRecord?,
        loadFallbackSkillRecord: @escaping (String, String) -> SupervisorFocusRequestEffects.FallbackSkillRecord?,
        dependencies: SupervisorViewFocusRequestExecution.Dependencies
    ) {
        guard let (resolvedRequest, plan) = resolveFocusRequest(
            request: request,
            context: context,
            loadRecentSkillRecord: loadRecentSkillRecord,
            loadFallbackSkillRecord: loadFallbackSkillRecord
        ) else {
            return
        }

        SupervisorViewFocusRequestExecution.apply(
            plan: plan,
            request: resolvedRequest,
            dependencies: dependencies
        )
    }

    static func performFocusRequest(
        request: AXSupervisorFocusRequest?,
        context: SupervisorFocusRequestEffects.Context,
        loadRecentSkillRecord: @escaping (String, String, String) -> SupervisorSkillFullRecord?,
        loadFallbackSkillRecord: @escaping (String, String) -> SupervisorFocusRequestEffects.FallbackSkillRecord?,
        currentSelectedProjectID: String?,
        currentRefreshAttemptNonce: Int?,
        setSignalCenterVisible: @escaping (Bool) -> Void,
        setSelectedPortfolioProjectID: @escaping (String?) -> Void,
        selectProject: @escaping (String) -> Void,
        scrollToAnchor: @escaping (String) -> Void,
        setHighlightedPendingHubGrantAnchor: @escaping (String?) -> Void,
        setHighlightedPendingSkillApprovalAnchor: @escaping (String?) -> Void,
        setHighlightedRecentSkillActivityRequestID: @escaping (String?) -> Void,
        setAuditDrillDown: @escaping (SupervisorAuditDrillDownSelection?) -> Void,
        setRefreshAttemptNonce: @escaping (Int?) -> Void,
        refreshPendingHubGrants: @escaping () -> Void,
        refreshPendingSkillApprovals: @escaping () -> Void,
        refreshRecentSkillActivities: @escaping () -> Void,
        completeRequest: @escaping (AXSupervisorFocusRequest) -> Void
    ) {
        performFocusRequest(
            request: request,
            context: context,
            loadRecentSkillRecord: loadRecentSkillRecord,
            loadFallbackSkillRecord: loadFallbackSkillRecord,
            dependencies: focusRequestExecutionDependencies(
                currentSelectedProjectID: currentSelectedProjectID,
                currentRefreshAttemptNonce: currentRefreshAttemptNonce,
                setSignalCenterVisible: setSignalCenterVisible,
                setSelectedPortfolioProjectID: setSelectedPortfolioProjectID,
                selectProject: selectProject,
                scrollToAnchor: scrollToAnchor,
                setHighlightedPendingHubGrantAnchor: setHighlightedPendingHubGrantAnchor,
                setHighlightedPendingSkillApprovalAnchor: setHighlightedPendingSkillApprovalAnchor,
                setHighlightedRecentSkillActivityRequestID: setHighlightedRecentSkillActivityRequestID,
                setAuditDrillDown: setAuditDrillDown,
                setRefreshAttemptNonce: setRefreshAttemptNonce,
                refreshPendingHubGrants: refreshPendingHubGrants,
                refreshPendingSkillApprovals: refreshPendingSkillApprovals,
                refreshRecentSkillActivities: refreshRecentSkillActivities,
                completeRequest: completeRequest
            )
        )
    }
}
