import SwiftUI

@MainActor
extension SupervisorViewActionSupport {
    static func cockpitExecutionDependencies(
        setInputText: @escaping (String) -> Void,
        requestConversationFocus: @escaping () -> Void,
        refreshPendingHubGrants: @escaping () -> Void,
        refreshSupervisorDoctorReport: @escaping () -> Void,
        setWindowSheet: @escaping (SupervisorManager.SupervisorWindowSheet?) -> Void,
        openURL: @escaping (URL) -> Void,
        openWindow: @escaping (String) -> Void,
        openProjectGovernance: @escaping (String, XTProjectGovernanceDestination, String?, String?) -> Void,
        setFocusedSplitLane: @escaping (String) -> Void
    ) -> SupervisorViewCockpitActionExecution.Dependencies {
        .init(
            setInputText: setInputText,
            requestConversationFocus: requestConversationFocus,
            refreshPendingHubGrants: refreshPendingHubGrants,
            refreshSupervisorDoctorReport: refreshSupervisorDoctorReport,
            setWindowSheet: setWindowSheet,
            openURL: openURL,
            openWindow: openWindow,
            openProjectGovernance: openProjectGovernance,
            setFocusedSplitLane: setFocusedSplitLane
        )
    }

    static func performCockpitAction(
        _ action: SupervisorCockpitAction,
        context: SupervisorCockpitActionResolver.Context,
        dependencies: SupervisorViewCockpitActionExecution.Dependencies
    ) {
        guard let plan = SupervisorCockpitActionResolver.resolve(
            action,
            context: context
        ) else {
            return
        }
        SupervisorViewCockpitActionExecution.apply(
            plan,
            dependencies: dependencies
        )
    }

    static func performCockpitAction(
        _ action: SupervisorCockpitAction,
        context: SupervisorCockpitActionResolver.Context,
        setInputText: @escaping (String) -> Void,
        requestConversationFocus: @escaping () -> Void,
        refreshPendingHubGrants: @escaping () -> Void,
        refreshSupervisorDoctorReport: @escaping () -> Void,
        setWindowSheet: @escaping (SupervisorManager.SupervisorWindowSheet?) -> Void,
        openURL: @escaping (URL) -> Void,
        openWindow: @escaping (String) -> Void,
        openProjectGovernance: @escaping (String, XTProjectGovernanceDestination, String?, String?) -> Void,
        setFocusedSplitLane: @escaping (String) -> Void
    ) {
        performCockpitAction(
            action,
            context: context,
            dependencies: cockpitExecutionDependencies(
                setInputText: setInputText,
                requestConversationFocus: requestConversationFocus,
                refreshPendingHubGrants: refreshPendingHubGrants,
                refreshSupervisorDoctorReport: refreshSupervisorDoctorReport,
                setWindowSheet: setWindowSheet,
                openURL: openURL,
                openWindow: openWindow,
                openProjectGovernance: openProjectGovernance,
                setFocusedSplitLane: setFocusedSplitLane
            )
        )
    }
}
