import SwiftUI

@MainActor
extension SupervisorViewActionSupport {
    static func performCardAction(
        _ action: SupervisorCardAction,
        context: SupervisorViewCardActionExecution.Context,
        supervisor: SupervisorManager,
        setAuditDrillDown: @escaping (SupervisorAuditDrillDownSelection?) -> Void,
        openURL: @escaping (URL) -> Void,
        openProjectGovernance: @escaping (String, XTProjectGovernanceDestination) -> Void
    ) {
        let effect = SupervisorViewCardActionExecution.resolve(
            action,
            context: context
        )
        SupervisorViewCardActionExecution.apply(
            effect,
            supervisor: supervisor,
            setAuditDrillDown: setAuditDrillDown,
            openURL: openURL,
            openProjectGovernance: openProjectGovernance
        )
    }
}
