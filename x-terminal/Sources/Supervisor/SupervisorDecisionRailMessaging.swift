import Foundation

enum SupervisorDecisionRailMessaging {
    static let waitingOnText = "decision/background precedence cleanup"

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
        "Decision rail cleanup: \(reasonSummary(shadowedBackgroundNoteCount: shadowedBackgroundNoteCount, weakOnlyBackgroundNoteCount: weakOnlyBackgroundNoteCount))"
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
            return "decision/background signal"
        }

        if shadowed > 0 && weakOnly > 0 {
            return "\(countText(shadowed, singular: "shadowed background note", plural: "shadowed background notes")) + \(countText(weakOnly, singular: "weak-only preference", plural: "weak-only preferences"))"
        }
        if shadowed > 0 {
            return countText(shadowed, singular: "shadowed background note", plural: "shadowed background notes")
        }
        return countText(weakOnly, singular: "weak-only preference", plural: "weak-only preferences")
    }

    static func recommendedNextAction(
        projectName: String,
        shadowedBackgroundNoteCount: Int,
        weakOnlyBackgroundNoteCount: Int
    ) -> String {
        let shadowed = max(0, shadowedBackgroundNoteCount)
        let weakOnly = max(0, weakOnlyBackgroundNoteCount)

        if shadowed > 0 && weakOnly > 0 {
            return "Review \(countText(shadowed, singular: "shadowed background note", plural: "shadowed background notes")) and \(countText(weakOnly, singular: "weak-only preference", plural: "weak-only preferences")) for \(projectName); either formalize them or keep them explicitly non-binding."
        }
        if shadowed > 0 {
            return "Review \(countText(shadowed, singular: "shadowed background note", plural: "shadowed background notes")) for \(projectName) and confirm they stay non-binding under the approved decision."
        }
        return "Decide whether to formalize \(countText(weakOnly, singular: "weak-only preference", plural: "weak-only preferences")) for \(projectName) or keep them explicitly background-only."
    }

    static func whyItMatters(
        shadowedBackgroundNoteCount: Int,
        weakOnlyBackgroundNoteCount: Int
    ) -> String {
        let shadowed = max(0, shadowedBackgroundNoteCount)
        let weakOnly = max(0, weakOnlyBackgroundNoteCount)

        if shadowed > 0 && weakOnly > 0 {
            return "Formal decisions already exist, but shadowed notes and weak-only preferences can still leak back into execution unless Supervisor cleans up the precedence boundary."
        }
        if shadowed > 0 {
            return "Shadowed background notes should stay visibly non-binding so the approved decision remains the only hard constraint."
        }
        return "Weak-only preferences remain helpful context, but they should not keep masquerading as formal project requirements."
    }

    private static func countText(
        _ count: Int,
        singular: String,
        plural: String
    ) -> String {
        let normalized = max(0, count)
        let label = normalized == 1 ? singular : plural
        return "\(normalized) \(label)"
    }
}
