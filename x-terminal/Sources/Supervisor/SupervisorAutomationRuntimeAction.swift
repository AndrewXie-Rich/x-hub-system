import Foundation

enum SupervisorAutomationRuntimeAction: Equatable {
    case status
    case start
    case recover
    case cancel
    case advance(XTAutomationRunState)
}

struct SupervisorAutomationRuntimeActionDescriptor: Equatable, Identifiable {
    var action: SupervisorAutomationRuntimeAction
    var label: String
    var isEnabled: Bool

    var id: String {
        "\(label)|\(isEnabled)|\(action)"
    }
}

enum SupervisorAutomationRuntimeActionResolver {
    struct Context: Equatable {
        var hasSelectedProject: Bool
        var hasRecipe: Bool
        var hasLastLaunchRef: Bool
    }

    static let defaultAdvanceStates: [XTAutomationRunState] = [
        .queued,
        .running,
        .blocked,
        .takeover,
        .delivered,
        .failed,
        .downgraded
    ]

    static func descriptor(
        for action: SupervisorAutomationRuntimeAction,
        context: Context
    ) -> SupervisorAutomationRuntimeActionDescriptor {
        SupervisorAutomationRuntimeActionDescriptor(
            action: action,
            label: label(for: action),
            isEnabled: isEnabled(action, context: context)
        )
    }

    static func advanceDescriptors(
        context: Context,
        states: [XTAutomationRunState] = defaultAdvanceStates
    ) -> [SupervisorAutomationRuntimeActionDescriptor] {
        states.map { descriptor(for: .advance($0), context: context) }
    }

    static func command(for action: SupervisorAutomationRuntimeAction) -> String {
        switch action {
        case .status:
            return "/automation status"
        case .start:
            return "/automation start"
        case .recover:
            return "/automation recover"
        case .cancel:
            return "/automation cancel"
        case .advance(let state):
            return "/automation advance \(state.rawValue)"
        }
    }

    private static func label(for action: SupervisorAutomationRuntimeAction) -> String {
        switch action {
        case .status:
            return "状态"
        case .start:
            return "启动"
        case .recover:
            return "恢复"
        case .cancel:
            return "取消"
        case .advance(let state):
            return advanceStateLabel(state)
        }
    }

    private static func isEnabled(
        _ action: SupervisorAutomationRuntimeAction,
        context: Context
    ) -> Bool {
        switch action {
        case .status:
            return context.hasSelectedProject
        case .start:
            return context.hasSelectedProject && context.hasRecipe
        case .recover, .cancel, .advance:
            return context.hasSelectedProject && context.hasLastLaunchRef
        }
    }

    private static func advanceStateLabel(_ state: XTAutomationRunState) -> String {
        switch state {
        case .queued:
            return "排队中"
        case .running:
            return "运行中"
        case .blocked:
            return "受阻"
        case .takeover:
            return "待接管"
        case .delivered:
            return "已交付"
        case .failed:
            return "失败"
        case .downgraded:
            return "已降级"
        }
    }
}
