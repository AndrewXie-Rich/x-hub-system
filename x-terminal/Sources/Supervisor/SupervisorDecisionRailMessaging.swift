import Foundation

enum SupervisorDecisionRailMessaging {
    static let waitingOnText = "决策 / 背景优先级清理"

    static func hasSignal(
        shadowedBackgroundNoteCount: Int,
        weakOnlyBackgroundNoteCount: Int
    ) -> Bool {
        max(0, shadowedBackgroundNoteCount) > 0 || max(0, weakOnlyBackgroundNoteCount) > 0
    }

    static func actionSummary(
        shadowedBackgroundNoteCount: Int,
        weakOnlyBackgroundNoteCount: Int
    ) -> String {
        "决策护栏清理：\(reasonSummary(shadowedBackgroundNoteCount: shadowedBackgroundNoteCount, weakOnlyBackgroundNoteCount: weakOnlyBackgroundNoteCount))"
    }

    static func reasonSummary(
        shadowedBackgroundNoteCount: Int,
        weakOnlyBackgroundNoteCount: Int
    ) -> String {
        let shadowed = max(0, shadowedBackgroundNoteCount)
        let weakOnly = max(0, weakOnlyBackgroundNoteCount)

        guard hasSignal(
            shadowedBackgroundNoteCount: shadowed,
            weakOnlyBackgroundNoteCount: weakOnly
        ) else {
            return "决策 / 背景信号"
        }

        if shadowed > 0 && weakOnly > 0 {
            return "\(countText(shadowed, label: "被遮蔽背景说明")) + \(countText(weakOnly, label: "弱约束偏好"))"
        }
        if shadowed > 0 {
            return countText(shadowed, label: "被遮蔽背景说明")
        }
        return countText(weakOnly, label: "弱约束偏好")
    }

    static func recommendedNextAction(
        projectName: String,
        shadowedBackgroundNoteCount: Int,
        weakOnlyBackgroundNoteCount: Int
    ) -> String {
        let shadowed = max(0, shadowedBackgroundNoteCount)
        let weakOnly = max(0, weakOnlyBackgroundNoteCount)

        if shadowed > 0 && weakOnly > 0 {
            return "检查 \(projectName) 的\(countText(shadowed, label: "被遮蔽背景说明"))和\(countText(weakOnly, label: "弱约束偏好"))，决定是转成正式决策，还是继续明确保持非约束。"
        }
        if shadowed > 0 {
            return "检查 \(projectName) 的\(countText(shadowed, label: "被遮蔽背景说明"))，确认它们在已批准决策下继续保持非约束。"
        }
        return "判断是否要把 \(projectName) 的\(countText(weakOnly, label: "弱约束偏好"))转成正式决策；如果不需要，就继续明确只作为背景。"
    }

    static func whyItMatters(
        shadowedBackgroundNoteCount: Int,
        weakOnlyBackgroundNoteCount: Int
    ) -> String {
        let shadowed = max(0, shadowedBackgroundNoteCount)
        let weakOnly = max(0, weakOnlyBackgroundNoteCount)

        if shadowed > 0 && weakOnly > 0 {
            return "正式决策已经存在，但被遮蔽的背景说明和弱约束偏好仍可能重新渗回执行，除非 Supervisor 清理优先级边界。"
        }
        if shadowed > 0 {
            return "被遮蔽的背景说明应继续明确保持非约束状态，避免盖过已批准决策。"
        }
        return "弱约束偏好可以保留为参考，但不应继续伪装成正式项目要求。"
    }

    private static func countText(
        _ count: Int,
        label: String
    ) -> String {
        let normalized = max(0, count)
        return "\(normalized) 条\(label)"
    }
}
