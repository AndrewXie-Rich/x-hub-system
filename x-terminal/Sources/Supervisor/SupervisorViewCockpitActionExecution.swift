import Foundation

@MainActor
enum SupervisorViewCockpitActionExecution {
    struct Dependencies {
        let setInputText: (String) -> Void
        let requestConversationFocus: () -> Void
        let refreshPendingHubGrants: () -> Void
        let refreshSupervisorDoctorReport: () -> Void
        let setWindowSheet: (SupervisorManager.SupervisorWindowSheet?) -> Void
        let openURL: (URL) -> Void
        let openWindow: (String) -> Void
        let openProjectGovernance: (String, XTProjectGovernanceDestination, String?, String?) -> Void
        let setFocusedSplitLane: (String) -> Void
    }

    static func apply(
        _ plan: SupervisorCockpitActionResolver.Plan,
        dependencies: Dependencies
    ) {
        for effect in plan.effects {
            switch effect {
            case .setInputText(let text):
                dependencies.setInputText(text)
            case .requestConversationFocus:
                dependencies.requestConversationFocus()
            case .refreshPendingHubGrants:
                dependencies.refreshPendingHubGrants()
            case .refreshSupervisorDoctorReport:
                dependencies.refreshSupervisorDoctorReport()
            case .presentWindowSheet(let sheet):
                dependencies.setWindowSheet(sheet)
            case .openURL(let target):
                switch target {
                case .absolute(let rawURL):
                    guard let url = URL(string: rawURL) else { continue }
                    dependencies.openURL(url)
                case .filePath(let path):
                    dependencies.openURL(URL(fileURLWithPath: path))
                }
            case .openWindow(let windowID):
                dependencies.openWindow(windowID)
            case .openProjectGovernance(let projectId, let destination, let title, let detail):
                dependencies.openProjectGovernance(projectId, destination, title, detail)
            case .setFocusedSplitLane(let laneID):
                dependencies.setFocusedSplitLane(laneID)
            }
        }
    }
}
