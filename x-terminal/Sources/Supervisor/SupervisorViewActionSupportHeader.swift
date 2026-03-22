import SwiftUI

@MainActor
extension SupervisorViewActionSupport {
    static func headerEffectDependencies(
        setSignalCenterVisible: @escaping (Bool) -> Void,
        focusSignalCenterOverview: @escaping (SupervisorSignalCenterOverviewAction) -> Void,
        setWindowSheet: @escaping (SupervisorManager.SupervisorWindowSheet?) -> Void,
        clearRequestedWindowSheet: @escaping () -> Void,
        clearConversation: @escaping () -> Void,
        setHeartbeatScale: @escaping (CGFloat) -> Void
    ) -> SupervisorViewHeaderEffects.Dependencies {
        SupervisorViewHeaderEffects.Dependencies(
            setSignalCenterVisible: setSignalCenterVisible,
            focusSignalCenterOverview: focusSignalCenterOverview,
            setWindowSheet: setWindowSheet,
            clearRequestedWindowSheet: clearRequestedWindowSheet,
            clearConversation: clearConversation,
            setPulseScale: { scale, animate in
                setHeaderPulseScale(
                    scale,
                    animate: animate,
                    setHeartbeatScale: setHeartbeatScale
                )
            }
        )
    }

    static func performHeaderAction(
        _ action: SupervisorHeaderAction,
        context: SupervisorHeaderControls.Context,
        dependencies: SupervisorViewHeaderEffects.Dependencies
    ) {
        let plan = SupervisorHeaderControls.resolve(
            action: action,
            context: context
        )
        SupervisorViewHeaderEffects.apply(
            plan,
            dependencies: dependencies
        )
    }

    static func performHeaderAction(
        _ action: SupervisorHeaderAction,
        context: SupervisorHeaderControls.Context,
        setSignalCenterVisible: @escaping (Bool) -> Void,
        setWindowSheet: @escaping (SupervisorManager.SupervisorWindowSheet?) -> Void,
        clearRequestedWindowSheet: @escaping () -> Void,
        clearConversation: @escaping () -> Void,
        setHeartbeatScale: @escaping (CGFloat) -> Void
    ) {
        performHeaderAction(
            action,
            context: context,
            dependencies: headerEffectDependencies(
                setSignalCenterVisible: setSignalCenterVisible,
                focusSignalCenterOverview: { _ in },
                setWindowSheet: setWindowSheet,
                clearRequestedWindowSheet: clearRequestedWindowSheet,
                clearConversation: clearConversation,
                setHeartbeatScale: setHeartbeatScale
            )
        )
    }

    static func performHeaderLifecycleEvent(
        _ event: SupervisorHeaderLifecycleEvent,
        context: SupervisorHeaderControls.Context,
        dependencies: SupervisorViewHeaderEffects.Dependencies
    ) {
        guard let plan = SupervisorHeaderControls.resolve(
            event: event,
            context: context
        ) else {
            return
        }
        SupervisorViewHeaderEffects.apply(
            plan,
            dependencies: dependencies
        )
    }

    static func performHeaderLifecycleEvent(
        _ event: SupervisorHeaderLifecycleEvent,
        context: SupervisorHeaderControls.Context,
        setSignalCenterVisible: @escaping (Bool) -> Void,
        setWindowSheet: @escaping (SupervisorManager.SupervisorWindowSheet?) -> Void,
        clearRequestedWindowSheet: @escaping () -> Void,
        clearConversation: @escaping () -> Void,
        setHeartbeatScale: @escaping (CGFloat) -> Void
    ) {
        performHeaderLifecycleEvent(
            event,
            context: context,
            dependencies: headerEffectDependencies(
                setSignalCenterVisible: setSignalCenterVisible,
                focusSignalCenterOverview: { _ in },
                setWindowSheet: setWindowSheet,
                clearRequestedWindowSheet: clearRequestedWindowSheet,
                clearConversation: clearConversation,
                setHeartbeatScale: setHeartbeatScale
            )
        )
    }

    private static func setHeaderPulseScale(
        _ scale: Double,
        animate: Bool,
        setHeartbeatScale: @escaping (CGFloat) -> Void
    ) {
        let applyScale = {
            setHeartbeatScale(scale)
        }

        if animate {
            withAnimation(.easeInOut(duration: 0.2)) {
                applyScale()
            }
        } else {
            applyScale()
        }
    }
}
