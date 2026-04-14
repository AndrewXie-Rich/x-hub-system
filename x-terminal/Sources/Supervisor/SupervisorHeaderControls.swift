import Foundation

enum SupervisorHeaderControlTone: String, Equatable {
    case neutral
    case accent
    case success
    case warning
    case danger
}

enum SupervisorHeaderButtonKind: Equatable {
    case operations
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
    case operationsButtonTapped
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
        var isHeartbeatFeedVisible: Bool = false
        var isSignalCenterVisible: Bool
        var requestedWindowSheet: SupervisorManager.SupervisorWindowSheet?
    }

    enum Effect: Equatable {
        case setHeartbeatFeed(Bool)
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
    static func presentation(
        for kind: SupervisorHeaderButtonKind,
        context: Context
    ) -> SupervisorHeaderButtonPresentation {
        switch kind {
        case .operations:
            return SupervisorHeaderButtonPresentation(
                iconName: operationsIconName(context: context),
                label: nil,
                tone: operationsTone(context: context),
                helpText: operationsHelpText(context: context),
                chrome: operationsChrome(context: context)
            )
        case .heartbeat:
            return SupervisorHeaderButtonPresentation(
                iconName: heartbeatIconName(context: context),
                label: nil,
                tone: heartbeatTone(context: context),
                helpText: heartbeatHelpText(context: context),
                chrome: heartbeatChrome(context: context)
            )
        case .supervisorSettings:
            return SupervisorHeaderButtonPresentation(
                iconName: "slider.horizontal.3",
                label: nil,
                tone: .neutral,
                helpText: "在当前 Supervisor 主窗口打开 Control Center（含 AI 模型）",
                chrome: .plain
            )
        case .modelSettings:
            return SupervisorHeaderButtonPresentation(
                iconName: "gearshape.fill",
                label: nil,
                tone: .neutral,
                helpText: "在当前 Supervisor 主窗口打开 Control Center 的 AI 模型页签",
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
        case .operationsButtonTapped:
            let nextVisible = !context.isSignalCenterVisible
            let effects: [Effect] = nextVisible
                ? [.setHeartbeatFeed(false), .setSignalCenter(true)]
                : [.setSignalCenter(false)]
            return Plan(effects: effects)
        case .heartbeatButtonTapped:
            let nextVisible = !context.isHeartbeatFeedVisible
            let effects: [Effect] = nextVisible
                ? [.setSignalCenter(false), .setHeartbeatFeed(true)]
                : [.setHeartbeatFeed(false)]
            return Plan(effects: effects)
        case .focusSignalCenterOverview(let action):
            return Plan(
                effects: [
                    .setHeartbeatFeed(false),
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
            return Plan(effects: [.setHeartbeatFeed(false), .setSignalCenter(true)])
        case .pendingHubGrantsChanged:
            guard context.pendingHubGrantCount > 0 else { return nil }
            return Plan(effects: [.setHeartbeatFeed(false), .setSignalCenter(true)])
        case .pendingSkillApprovalsChanged:
            guard context.pendingSkillApprovalCount > 0 else { return nil }
            return Plan(effects: [.setHeartbeatFeed(false), .setSignalCenter(true)])
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

    private static func operationsTone(context: Context) -> SupervisorHeaderControlTone {
        if let overview = context.signalCenterOverview {
            return overview.priority == .stable ? .neutral : overview.priorityTone
        }
        return .neutral
    }

    private static func operationsHelpText(context: Context) -> String {
        let verb = context.isSignalCenterVisible ? "收起" : "打开"
        if let overview = context.signalCenterOverview {
            return "\(verb) Supervisor 看板（当前：\(overview.headlineText)）"
        }
        return "\(verb) Supervisor 看板"
    }

    private static func heartbeatTone(context: Context) -> SupervisorHeaderControlTone {
        if let overview = context.heartbeatOverview {
            return overview.priorityTone
        }
        return context.hasLatestHeartbeat ? .danger : .neutral
    }

    private static func heartbeatHelpText(context: Context) -> String {
        let verb = context.isHeartbeatFeedVisible ? "收起" : "打开"
        if let overview = context.heartbeatOverview {
            return "\(verb) Supervisor 心跳（当前：\(overview.headlineText)）"
        }
        if let priority = context.highestHeartbeatPriority {
            return "\(verb) Supervisor 心跳（当前：\(priority.label)）"
        }
        return "\(verb) Supervisor 心跳"
    }

    private static func operationsChrome(context: Context) -> SupervisorHeaderButtonChrome {
        guard let overview = context.signalCenterOverview else {
            return context.isSignalCenterVisible
                ? SupervisorHeaderButtonChrome(
                    tone: .neutral,
                    fillOpacity: 0.10,
                    strokeOpacity: 0.16,
                    shadowOpacity: 0
                )
                : .plain
        }

        switch overview.priority {
        case .immediate:
            return SupervisorHeaderButtonChrome(
                tone: overview.priorityTone,
                fillOpacity: context.isSignalCenterVisible ? 0.22 : 0.18,
                strokeOpacity: context.isSignalCenterVisible ? 0.32 : 0.30,
                shadowOpacity: 0.16
            )
        case .attention:
            return SupervisorHeaderButtonChrome(
                tone: overview.priorityTone,
                fillOpacity: context.isSignalCenterVisible ? 0.18 : 0.16,
                strokeOpacity: context.isSignalCenterVisible ? 0.30 : 0.28,
                shadowOpacity: 0.12
            )
        case .watch:
            return SupervisorHeaderButtonChrome(
                tone: overview.priorityTone,
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

    private static func heartbeatChrome(context: Context) -> SupervisorHeaderButtonChrome {
        if let overview = context.heartbeatOverview {
            switch overview.priority {
            case .immediate:
                return SupervisorHeaderButtonChrome(
                    tone: overview.priorityTone,
                    fillOpacity: context.isHeartbeatFeedVisible ? 0.22 : 0.18,
                    strokeOpacity: context.isHeartbeatFeedVisible ? 0.32 : 0.30,
                    shadowOpacity: 0.16
                )
            case .attention:
                return SupervisorHeaderButtonChrome(
                    tone: overview.priorityTone,
                    fillOpacity: context.isHeartbeatFeedVisible ? 0.18 : 0.16,
                    strokeOpacity: context.isHeartbeatFeedVisible ? 0.30 : 0.28,
                    shadowOpacity: 0.12
                )
            case .watch:
                return SupervisorHeaderButtonChrome(
                    tone: overview.priorityTone,
                    fillOpacity: context.isHeartbeatFeedVisible ? 0.16 : 0.14,
                    strokeOpacity: context.isHeartbeatFeedVisible ? 0.24 : 0.22,
                    shadowOpacity: 0.08
                )
            case .stable:
                return context.isHeartbeatFeedVisible
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

        if context.isHeartbeatFeedVisible {
            return SupervisorHeaderButtonChrome(
                tone: .neutral,
                fillOpacity: 0.10,
                strokeOpacity: 0.16,
                shadowOpacity: 0
            )
        }

        return .plain
    }

    private static func operationsIconName(context: Context) -> String {
        if context.isSignalCenterVisible || hasNonStableSignalCenterSignal(context: context) {
            return "square.grid.2x2.fill"
        }
        return "square.grid.2x2"
    }

    private static func heartbeatIconName(context: Context) -> String {
        (context.isHeartbeatFeedVisible || context.hasLatestHeartbeat) ? "heart.fill" : "heart"
    }

    private static func shouldPulseSignalCenter(context: Context) -> Bool {
        if let overview = context.signalCenterOverview {
            return overview.shouldPulseHeader
        }
        return context.pendingHubGrantCount > 0
            || context.pendingSkillApprovalCount > 0
            || context.hasLatestRuntimeActivity
    }

    private static func hasNonStableSignalCenterSignal(context: Context) -> Bool {
        guard let overview = context.signalCenterOverview else { return false }
        return overview.priority != .stable
    }
}
