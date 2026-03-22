import Foundation

enum SupervisorAuditDrillDownAction: Equatable {
    case officialSkillsChannel
    case pendingGrant(SupervisorManager.SupervisorPendingGrant)
    case pendingSkillApproval(SupervisorManager.SupervisorPendingSkillApproval)
    case recentSkillActivity(SupervisorManager.SupervisorRecentSkillActivity)
    case fullRecordFallback(projectId: String, projectName: String, record: SupervisorSkillFullRecord)
    case eventLoop(SupervisorManager.SupervisorEventLoopActivity)
    case infrastructureItem(SupervisorInfrastructureFeedPresentation.Item)
}

enum SupervisorAuditDrillDownActionResolver {
    typealias Context = SupervisorAuditDrillDownResolver.Context
    typealias FullRecordLoader = SupervisorAuditDrillDownResolver.FullRecordLoader

    static func selection(
        for action: SupervisorAuditDrillDownAction,
        context: Context,
        loadFullRecord: FullRecordLoader
    ) -> SupervisorAuditDrillDownSelection? {
        switch action {
        case .officialSkillsChannel:
            return SupervisorAuditDrillDownResolver.selectionForOfficialSkillsChannel(
                context: context
            )
        case .pendingGrant(let grant):
            return SupervisorAuditDrillDownResolver.selection(for: grant)
        case .pendingSkillApproval(let approval):
            return SupervisorAuditDrillDownResolver.selection(for: approval)
        case .recentSkillActivity(let item):
            return SupervisorAuditDrillDownResolver.selection(
                for: item,
                loadFullRecord: loadFullRecord
            )
        case .fullRecordFallback(let projectId, let projectName, let record):
            return .fullRecordFallback(
                projectId: projectId,
                projectName: projectName,
                record: record
            )
        case .eventLoop(let item):
            return SupervisorAuditDrillDownResolver.selection(
                for: item,
                recentSkillActivities: context.recentSupervisorSkillActivities,
                loadFullRecord: loadFullRecord
            )
        case .infrastructureItem(let item):
            return SupervisorAuditDrillDownResolver.selection(
                for: item,
                context: context,
                loadFullRecord: loadFullRecord
            )
        }
    }
}
