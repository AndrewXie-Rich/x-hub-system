import Foundation

@MainActor
enum XTDeepLinkActionExecutor {
    static func execute(
        _ plan: XTDeepLinkActionPlan,
        appModel: AppModel,
        openSupervisor: (XTSupervisorWindowOpenIntent) -> Void
    ) {
        if let projectId = plan.selectProjectId {
            appModel.selectProject(projectId)
        }
        if let paneIntent = plan.projectPaneIntent {
            appModel.setPane(paneIntent.pane, for: paneIntent.projectId)
        }
        if let prefill = plan.prefillGrantContext {
            appModel.prefillGrantContext(
                projectId: prefill.projectId,
                grantRequestId: prefill.grantRequestId,
                capability: prefill.capability,
                reason: prefill.reason
            )
        }
        if let openIntent = plan.openSupervisorIntent {
            openSupervisor(openIntent)
        }
        applyFocusIntent(plan.focusIntent, appModel: appModel)
    }

    private static func applyFocusIntent(
        _ intent: XTDeepLinkFocusIntent?,
        appModel: AppModel
    ) {
        switch intent {
        case let .supervisorGrant(projectId, grantRequestId, capability):
            appModel.requestSupervisorGrantFocus(
                projectId: projectId,
                grantRequestId: grantRequestId,
                capability: capability
            )
        case let .supervisorApproval(projectId, requestId):
            appModel.requestSupervisorApprovalFocus(
                projectId: projectId,
                requestId: requestId
            )
        case let .supervisorCandidateReview(projectId, requestId):
            appModel.requestSupervisorCandidateReviewFocus(
                projectId: projectId,
                requestId: requestId
            )
        case let .supervisorSkillRecord(projectId, requestId):
            appModel.requestSupervisorSkillRecordFocus(
                projectId: projectId,
                requestId: requestId
            )
        case let .supervisorBoard(projectId, anchorID):
            appModel.requestSupervisorBoardFocus(
                anchorID: anchorID,
                projectId: projectId
            )
        case let .projectToolApproval(projectId, requestId):
            appModel.requestProjectToolApprovalFocus(
                projectId: projectId,
                requestId: requestId
            )
        case let .projectRouteDiagnose(projectId):
            appModel.requestProjectRouteDiagnoseFocus(projectId: projectId)
        case nil:
            break
        }
    }
}
