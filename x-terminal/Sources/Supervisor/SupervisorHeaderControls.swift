import Foundation

enum SupervisorHeaderControlTone: String, Equatable {
    case neutral
    case accent
    case success
    case warning
    case danger
}

enum SupervisorHeaderButtonKind: Equatable {
    case heartbeat
    case supervisorSettings
    case modelSettings
    case clearConversation
}

struct SupervisorHeaderButtonPresentation: Equatable {
    var iconName: String?
    var label: String?
    var tone: SupervisorHeaderControlTone
    var helpText: String
    var chrome: SupervisorHeaderButtonChrome
}

struct SupervisorHeaderButtonChrome: Equatable {
    var tone: SupervisorHeaderControlTone
    var fillOpacity: Double
    var strokeOpacity: Double
    var shadowOpacity: Double

    static let plain = SupervisorHeaderButtonChrome(
        tone: .neutral,
        fillOpacity: 0,
        strokeOpacity: 0,
        shadowOpacity: 0
    )
}

enum SupervisorHeaderAction: Equatable {
    case heartbeatButtonTapped
    case focusSignalCenterOverview(SupervisorSignalCenterOverviewAction)
    case supervisorSettingsTapped
    case modelSettingsTapped
    case clearConversationTapped
}

enum SupervisorHeaderLifecycleEvent: Equatable {
    case focusRequestChanged
    case pendingHubGrantsChanged
    case pendingSkillApprovalsChanged
    case requestedWindowSheetChanged
    case latestHeartbeatChanged
    case signalCenterChanged
}

struct SupervisorHeaderPulseStep: Equatable {
    var delaySeconds: Double
    var scale: Double
}

enum SupervisorHeaderControls {
    struct SignalActionPresentation: Equatable {
        var action: SupervisorSignalCenterOverviewAction
        var label: String
        var tone: SupervisorHeaderControlTone
        var helpText: String
    }

    struct Context: Equatable {
        var hasFocusRequest: Bool
        var pendingHubGrantCount: Int
        var pendingSkillApprovalCount: Int
        var hasLatestHeartbeat: Bool
        var highestHeartbeatPriority: SupervisorHeartbeatPriority?
        var heartbeatOverview: SupervisorHeartbeatOverviewPresentation?
        var hasLatestRuntimeActivity: Bool
        var signalCenterOverview: SupervisorSignalCenterOverviewPresentation?
        var isSignalCenterVisible: Bool
        var requestedWindowSheet: SupervisorManager.SupervisorWindowSheet?
    }

    enum Effect: Equatable {
        case setSignalCenter(Bool)
        case focusSignalCenterOverview(SupervisorSignalCenterOverviewAction)
        case setWindowSheet(SupervisorManager.SupervisorWindowSheet?)
        case clearRequestedWindowSheet
        case clearConversation
        case pulse
    }

    struct Plan: Equatable {
        var effects: [Effect]
    }

    private enum PrimarySignal: Equatable {
        case heartbeat(SupervisorHeartbeatOverviewPresentation)
        case signalCenter(SupervisorSignalCenterOverviewPresentation)

        var priority: SupervisorHeartbeatPriority {
            switch self {
            case .heartbeat(let overview):
                return overview.priority
            case .signalCenter(let overview):
                return overview.priority
            }
        }

        var tone: SupervisorHeaderControlTone {
            switch self {
            case .heartbeat(let overview):
                return overview.priorityTone
            case .signalCenter(let overview):
                return overview.priorityTone
            }
        }

        var headlineText: String {
            switch self {
            case .heartbeat(let overview):
                return overview.headlineText
            case .signalCenter(let overview):
                return overview.headlineText
            }
        }
    }

    static func presentation(
        for kind: SupervisorHeaderButtonKind,
        context: Context
    ) -> SupervisorHeaderButtonPresentation {
        switch kind {
        case .heartbeat:
            let heartbeatTone = heartbeatTone(context: context)
            let heartbeatHelpText = heartbeatHelpText(context: context)
            return SupervisorHeaderButtonPresentation(
                iconName: heartbeatIconName(context: context),
                label: nil,
                tone: heartbeatTone,
                helpText: heartbeatHelpText,
                chrome: heartbeatChrome(context: context)
            )
        case .supervisorSettings:
            return SupervisorHeaderButtonPresentation(
                iconName: "slider.horizontal.3",
                label: nil,
                tone: .neutral,
                helpText: "打开 Supervisor Control Center（含 AI 模型）",
                chrome: .plain
            )
        case .modelSettings:
            return SupervisorHeaderButtonPresentation(
                iconName: "gearshape.fill",
                label: nil,
                tone: .neutral,
                helpText: "打开 Supervisor Control Center 的 AI 模型页签",
                chrome: .plain
            )
        case .clearConversation:
            return SupervisorHeaderButtonPresentation(
                iconName: nil,
                label: "清空",
                tone: .neutral,
                helpText: "清空当前对话",
                chrome: .plain
            )
        }
    }

    static func resolve(
        action: SupervisorHeaderAction,
        context: Context
    ) -> Plan {
        switch action {
        case .heartbeatButtonTapped:
            return Plan(effects: [.setSignalCenter(!context.isSignalCenterVisible)])
        case .focusSignalCenterOverview(let action):
            return Plan(
                effects: [
                    .setSignalCenter(true),
                    .focusSignalCenterOverview(action)
                ]
            )
        case .supervisorSettingsTapped:
            return Plan(effects: [.setWindowSheet(.supervisorSettings)])
        case .modelSettingsTapped:
            return Plan(effects: [.setWindowSheet(.modelSettings)])
        case .clearConversationTapped:
            return Plan(effects: [.clearConversation])
        }
    }

    static func resolve(
        event: SupervisorHeaderLifecycleEvent,
        context: Context
    ) -> Plan? {
        switch event {
        case .focusRequestChanged:
            guard context.hasFocusRequest else { return nil }
            return Plan(effects: [.setSignalCenter(true)])
        case .pendingHubGrantsChanged:
            guard context.pendingHubGrantCount > 0 else { return nil }
            return Plan(effects: [.setSignalCenter(true)])
        case .pendingSkillApprovalsChanged:
            guard context.pendingSkillApprovalCount > 0 else { return nil }
            return Plan(effects: [.setSignalCenter(true)])
        case .requestedWindowSheetChanged:
            guard let requested = context.requestedWindowSheet else { return nil }
            return Plan(effects: [.setWindowSheet(requested), .clearRequestedWindowSheet])
        case .latestHeartbeatChanged:
            guard context.hasLatestHeartbeat else { return nil }
            return Plan(effects: [.pulse])
        case .signalCenterChanged:
            guard shouldPulseSignalCenter(context: context) else { return nil }
            return Plan(effects: [.pulse])
        }
    }

    static func pulseSteps() -> [SupervisorHeaderPulseStep] {
        [
            SupervisorHeaderPulseStep(delaySeconds: 0.0, scale: 1.18),
            SupervisorHeaderPulseStep(delaySeconds: 0.16, scale: 1.0),
            SupervisorHeaderPulseStep(delaySeconds: 0.28, scale: 1.14),
            SupervisorHeaderPulseStep(delaySeconds: 0.44, scale: 1.0)
        ]
    }

    static func signalAction(
        context: Context
    ) -> SignalActionPresentation? {
        guard let overview = context.signalCenterOverview,
              overview.priority != .stable,
              let focusAction = overview.focusAction else {
            return nil
        }
        return SignalActionPresentation(
            action: focusAction.action,
            label: focusAction.label,
            tone: focusAction.tone,
            helpText: "聚焦当前主信号（\(overview.headlineText)）"
        )
    }

    private static func heartbeatTone(context: Context) -> SupervisorHeaderControlTone {
        if let primarySignal = primarySignal(context: context) {
            return primarySignal.tone
        }
        return context.hasLatestHeartbeat ? .danger : .neutral
    }

    private static func heartbeatHelpText(context: Context) -> String {
        if let primarySignal = primarySignal(context: context) {
            return "打开 Supervisor 信号中心（当前：\(primarySignal.headlineText)）"
        }
        if let priority = context.highestHeartbeatPriority {
            return "打开 Supervisor 信号中心（当前：\(priority.label)）"
        }
        return "打开 Supervisor 信号中心"
    }

    private static func heartbeatChrome(context: Context) -> SupervisorHeaderButtonChrome {
        if let primarySignal = primarySignal(context: context) {
            switch primarySignal.priority {
            case .immediate:
                return SupervisorHeaderButtonChrome(
                    tone: primarySignal.tone,
                    fillOpacity: context.isSignalCenterVisible ? 0.22 : 0.18,
                    strokeOpacity: context.isSignalCenterVisible ? 0.32 : 0.30,
                    shadowOpacity: 0.16
                )
            case .attention:
                return SupervisorHeaderButtonChrome(
                    tone: primarySignal.tone,
                    fillOpacity: context.isSignalCenterVisible ? 0.18 : 0.16,
                    strokeOpacity: context.isSignalCenterVisible ? 0.30 : 0.28,
                    shadowOpacity: 0.12
                )
            case .watch:
                return SupervisorHeaderButtonChrome(
                    tone: primarySignal.tone,
                    fillOpacity: context.isSignalCenterVisible ? 0.16 : 0.14,
                    strokeOpacity: context.isSignalCenterVisible ? 0.24 : 0.22,
                    shadowOpacity: 0.08
                )
            case .stable:
                return context.isSignalCenterVisible
                    ? SupervisorHeaderButtonChrome(
                        tone: .neutral,
                        fillOpacity: 0.10,
                        strokeOpacity: 0.16,
                        shadowOpacity: 0
                    )
                    : .plain
            }
        }

        if context.hasLatestHeartbeat {
            return SupervisorHeaderButtonChrome(
                tone: .danger,
                fillOpacity: 0.14,
                strokeOpacity: 0.22,
                shadowOpacity: 0.08
            )
        }

        if context.isSignalCenterVisible {
            return SupervisorHeaderButtonChrome(
                tone: .neutral,
                fillOpacity: 0.10,
                strokeOpacity: 0.16,
                shadowOpacity: 0
            )
        }

        return .plain
    }

    private static func heartbeatIconName(context: Context) -> String {
        if context.isSignalCenterVisible || hasNonStableSignalCenterSignal(context: context) {
            return "heart.fill"
        }
        return context.hasLatestHeartbeat ? "heart.fill" : "heart"
    }

    private static func shouldPulseSignalCenter(context: Context) -> Bool {
        if let overview = context.signalCenterOverview {
            return overview.shouldPulseHeader
        }
        return context.pendingHubGrantCount > 0
            || context.pendingSkillApprovalCount > 0
            || context.hasLatestRuntimeActivity
    }

    private static func primarySignal(context: Context) -> PrimarySignal? {
        let heartbeatSignal = context.heartbeatOverview.map(PrimarySignal.heartbeat)
        let signalCenterSignal = context.signalCenterOverview
            .flatMap { $0.priority != .stable ? $0 : nil }
            .map(PrimarySignal.signalCenter)

        switch (heartbeatSignal, signalCenterSignal) {
        case let (.some(heartbeat), .some(signalCenter)):
            if signalCenter.priority.rawValue <= heartbeat.priority.rawValue {
                return signalCenter
            }
            return heartbeat
        case let (.some(heartbeat), nil):
            return heartbeat
        case let (nil, .some(signalCenter)):
            return signalCenter
        case (nil, nil):
            return nil
        }
    }

    private static func hasNonStableSignalCenterSignal(context: Context) -> Bool {
        guard let overview = context.signalCenterOverview else { return false }
        return overview.priority != .stable
    }
}
