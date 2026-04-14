import Foundation

@MainActor
enum SupervisorViewCardActionExecution {
    struct Context {
        let auditDrillDownContext: SupervisorAuditDrillDownResolver.Context
        let loadFullRecord: (String, String, String) -> SupervisorSkillFullRecord?
    }

    enum Effect {
        case setAuditDrillDown(SupervisorAuditDrillDownSelection?)
        case openURL(String)
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

    static func resolve(
        _ action: SupervisorCardAction,
        context: Context
    ) -> Effect {
        switch action {
        case .openAudit(let auditAction):
            return .setAuditDrillDown(
                SupervisorAuditDrillDownActionResolver.selection(
                    for: auditAction,
                    context: context.auditDrillDownContext,
                    loadFullRecord: context.loadFullRecord
                )
            )
        case .openURL(_, let rawURL):
            return .openURL(rawURL)
        case .openProjectGovernance(let projectId, let destination):
            return .openProjectGovernance(projectId: projectId, destination: destination)
        case .stageSupervisorCandidateReview(let item):
            return .stageSupervisorCandidateReview(item)
        case .approvePendingGrant(let grant):
            return .approvePendingGrant(grant)
        case .denyPendingGrant(let grant):
            return .denyPendingGrant(grant)
        case .approvePendingSkillApproval(let approval):
            return .approvePendingSkillApproval(approval)
        case .denyPendingSkillApproval(let approval):
            return .denyPendingSkillApproval(approval)
        case .approveSkillActivity(let item):
            return .approveSkillActivity(item)
        case .denySkillActivity(let item):
            return .denySkillActivity(item)
        case .retrySkillActivity(let item):
            return .retrySkillActivity(item)
        }
    }

    static func apply(
        _ effect: Effect,
        supervisor: SupervisorManager,
        setAuditDrillDown: (SupervisorAuditDrillDownSelection?) -> Void,
        openURL: (URL) -> Void,
        openProjectGovernance: (String, XTProjectGovernanceDestination) -> Void
    ) {
        switch effect {
        case .setAuditDrillDown(let selection):
            setAuditDrillDown(selection)
        case .openURL(let rawURL):
            guard let url = URL(string: rawURL) else { return }
            openURL(url)
        case .openProjectGovernance(let projectId, let destination):
            openProjectGovernance(projectId, destination)
        case .stageSupervisorCandidateReview(let item):
            supervisor.stageSupervisorCandidateReview(item)
        case .approvePendingGrant(let grant):
            supervisor.approvePendingHubGrant(grant)
        case .denyPendingGrant(let grant):
            supervisor.denyPendingHubGrant(grant)
        case .approvePendingSkillApproval(let approval):
            supervisor.approvePendingSupervisorSkillApproval(approval)
        case .denyPendingSkillApproval(let approval):
            supervisor.denyPendingSupervisorSkillApproval(approval)
        case .approveSkillActivity(let item):
            supervisor.approveSupervisorSkillActivity(item)
        case .denySkillActivity(let item):
            supervisor.denySupervisorSkillActivity(item)
        case .retrySkillActivity(let item):
            supervisor.retrySupervisorSkillActivity(item)
        }
    }
}
