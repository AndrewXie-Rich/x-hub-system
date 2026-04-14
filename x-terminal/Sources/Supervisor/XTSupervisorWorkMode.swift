import Foundation

enum XTSupervisorWorkMode: String, Codable, CaseIterable, Identifiable {
    case conversationOnly = "conversation_only"
    case guidedProgress = "guided_progress"
    case governedAutomation = "governed_automation"

    static let defaultMode: XTSupervisorWorkMode = .guidedProgress

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .conversationOnly:
            return "对话"
        case .guidedProgress:
            return "推进"
        case .governedAutomation:
            return "自动执行"
        }
    }

    var displayName: String {
        switch self {
        case .conversationOnly:
            return "对话模式"
        case .guidedProgress:
            return "推进模式"
        case .governedAutomation:
            return "自动执行模式"
        }
    }

    var summary: String {
        switch self {
        case .conversationOnly:
            return "只在你明确需要时回答，不主动推进，也不会自己调 coder / skill / tool 去执行。"
        case .guidedProgress:
            return "会主动给计划、提醒和下一步建议，但先给方案、不直接开跑，也不会自己发起 coder / skill / tool 执行。"
        case .governedAutomation:
            return "会主动推进，并且在治理边界、授权状态和运行时条件都允许时，可以自动发起 coder / skill / tool 执行。"
        }
    }

    var runtimeBehaviorSummary: String {
        switch self {
        case .conversationOnly:
            return "实际效果：只回答当前问题；不主动追进度；任何自动执行都会收回到 manual。"
        case .guidedProgress:
            return "实际效果：可以主动给计划、提醒和下一步；但执行层面仍会收回到 manual。"
        case .governedAutomation:
            return "实际效果：允许主动推进；但执行权限仍会被 A-Tier、S-Tier、授权、runtime readiness 和 fail-closed gate 继续收紧。"
        }
    }

    var promptSummary: String {
        switch self {
        case .conversationOnly:
            return "Only answer direct user requests. Do not proactively push plans, reminders, or governed execution unless the user explicitly asks."
        case .guidedProgress:
            return "You may proactively suggest plans, next steps, and reminders, but stay proposal-first. Do not autonomously launch governed coder/skill/tool execution."
        case .governedAutomation:
            return "You may proactively suggest plans and, when user intent plus governance allow it, initiate governed coder/skill/tool execution. Never bypass grants, A-Tier, S-Tier, runtime readiness, or fail-closed safety gates."
        }
    }

    var allowsGovernedAutomation: Bool {
        self == .governedAutomation
    }

    func clamped(_ autoLaunchPolicy: OneShotAutoLaunchPolicy) -> OneShotAutoLaunchPolicy {
        allowsGovernedAutomation ? autoLaunchPolicy : .manual
    }
}
