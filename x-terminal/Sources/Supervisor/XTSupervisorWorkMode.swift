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
            return "只在你明确发问时回答，不主动推进，也不自动发起 governed coder / skill / tool 执行。"
        case .guidedProgress:
            return "会主动给计划、提醒和下一步建议，但保持 proposal-first，不会自动发起 governed coder / skill / tool 执行。"
        case .governedAutomation:
            return "会主动推进，并且在治理边界、授权状态和运行时条件都允许时，可以自动发起 governed coder / skill / tool 执行。"
        }
    }

    var runtimeBehaviorSummary: String {
        switch self {
        case .conversationOnly:
            return "实际行为上限：回答直达问题；不主动推进；自动执行上限固定收束到 manual。"
        case .guidedProgress:
            return "实际行为上限：可以主动给计划、提醒、下一步；自动执行上限固定收束到 manual。"
        case .governedAutomation:
            return "实际行为上限：允许主动推进；自动执行仍只会受 A-tier、S-tier、授权、runtime readiness 和 fail-closed gate 继续收紧。"
        }
    }

    var promptSummary: String {
        switch self {
        case .conversationOnly:
            return "Only answer direct user requests. Do not proactively push plans, reminders, or governed execution unless the user explicitly asks."
        case .guidedProgress:
            return "You may proactively suggest plans, next steps, and reminders, but stay proposal-first. Do not autonomously launch governed coder/skill/tool execution."
        case .governedAutomation:
            return "You may proactively suggest plans and, when user intent plus governance allow it, initiate governed coder/skill/tool execution. Never bypass grants, A-tier, S-tier, runtime readiness, or fail-closed safety gates."
        }
    }

    var allowsGovernedAutomation: Bool {
        self == .governedAutomation
    }

    func clamped(_ autoLaunchPolicy: OneShotAutoLaunchPolicy) -> OneShotAutoLaunchPolicy {
        allowsGovernedAutomation ? autoLaunchPolicy : .manual
    }
}
