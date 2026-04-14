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
    var helpText: String

    var id: String {
        "\(label)|\(isEnabled)|\(helpText)|\(action)"
    }
}

enum SupervisorAutomationRuntimeActionResolver {
    struct Context: Equatable {
        var hasSelectedProject: Bool
        var hasRecipe: Bool
        var hasLastLaunchRef: Bool
        var runtimeReadiness: AXProjectGovernanceRuntimeReadinessSnapshot? = nil

        var executionHoldSummary: String? {
            guard let runtimeReadiness,
                  runtimeReadiness.requiresA4RuntimeReady,
                  !runtimeReadiness.runtimeReady else {
                return nil
            }

            let summary = runtimeReadiness.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let missing = runtimeReadiness.missingSummaryLine?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if summary.isEmpty { return missing.isEmpty ? nil : missing }
            if missing.isEmpty { return summary }
            return "\(summary) \(missing)"
        }
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
            isEnabled: isEnabled(action, context: context),
            helpText: helpText(for: action, context: context)
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
            return context.hasSelectedProject
                && context.executionHoldSummary == nil
                && context.hasRecipe
        case .recover, .advance:
            return context.hasSelectedProject
                && context.executionHoldSummary == nil
                && context.hasLastLaunchRef
        case .cancel:
            return context.hasSelectedProject && context.hasLastLaunchRef
        }
    }

    private static func helpText(
        for action: SupervisorAutomationRuntimeAction,
        context: Context
    ) -> String {
        switch action {
        case .status:
            return context.hasSelectedProject
                ? "刷新当前项目的自动化执行状态"
                : "先选中一个项目，再查看自动化执行状态"
        case .start:
            if !context.hasSelectedProject {
                return "先选中一个项目，再启动自动化执行"
            }
            if let hold = context.executionHoldSummary {
                return hold
            }
            if !context.hasRecipe {
                return "当前项目还没有激活执行配方，暂时无法启动"
            }
            return "启动当前项目的自动化执行"
        case .recover:
            if !context.hasSelectedProject {
                return "先选中一个项目，再恢复最近一次自动化运行"
            }
            if let hold = context.executionHoldSummary {
                return hold
            }
            if !context.hasLastLaunchRef {
                return "当前还没有最近一次运行引用，暂时无法恢复"
            }
            return "从最近一次运行和检查点恢复自动化执行"
        case .cancel:
            if !context.hasSelectedProject {
                return "先选中一个项目，再取消当前自动化运行"
            }
            if !context.hasLastLaunchRef {
                return "当前还没有最近一次运行引用，暂时无法取消"
            }
            return "取消当前自动化运行"
        case .advance(let state):
            if !context.hasSelectedProject {
                return "先选中一个项目，再手动推进自动化状态"
            }
            if let hold = context.executionHoldSummary {
                return hold
            }
            if !context.hasLastLaunchRef {
                return "当前还没有最近一次运行引用，暂时无法推进状态"
            }
            return "手动把当前自动化运行推进到\(advanceStateLabel(state))"
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
