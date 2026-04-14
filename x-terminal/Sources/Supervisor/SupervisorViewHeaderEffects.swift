import Foundation

@MainActor
enum SupervisorViewHeaderEffects {
    struct Dependencies {
        let setHeartbeatFeedVisible: (Bool) -> Void
        let setSignalCenterVisible: (Bool) -> Void
        let focusSignalCenterOverview: (SupervisorSignalCenterOverviewAction) -> Void
        let setWindowSheet: (SupervisorManager.SupervisorWindowSheet?) -> Void
        let clearRequestedWindowSheet: () -> Void
        let clearConversation: () -> Void
        let setPulseScale: (Double, Bool) -> Void
    }

    static func apply(
        _ plan: SupervisorHeaderControls.Plan,
        dependencies: Dependencies
    ) {
        for effect in plan.effects {
            switch effect {
            case .setHeartbeatFeed(let isVisible):
                dependencies.setHeartbeatFeedVisible(isVisible)
            case .setSignalCenter(let isVisible):
                dependencies.setSignalCenterVisible(isVisible)
            case .focusSignalCenterOverview(let action):
                dependencies.focusSignalCenterOverview(action)
            case .setWindowSheet(let sheet):
                dependencies.setWindowSheet(sheet)
            case .clearRequestedWindowSheet:
                dependencies.clearRequestedWindowSheet()
            case .clearConversation:
                dependencies.clearConversation()
            case .pulse:
                runPulse(dependencies: dependencies)
            }
        }
    }

    private static func runPulse(dependencies: Dependencies) {
        dependencies.setPulseScale(1.0, false)
        for step in SupervisorHeaderControls.pulseSteps() {
            DispatchQueue.main.asyncAfter(deadline: .now() + step.delaySeconds) {
                dependencies.setPulseScale(step.scale, true)
            }
        }
    }
}
