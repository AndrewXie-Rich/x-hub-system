import Foundation

enum SupervisorRelationshipMode: String, Codable, CaseIterable, Identifiable {
    case operatorPartner = "operator_partner"
    case chiefOfStaff = "chief_of_staff"
    case personalAssistant = "personal_assistant"
    case coach = "coach"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .operatorPartner:
            return "Operator Partner"
        case .chiefOfStaff:
            return "Chief of Staff"
        case .personalAssistant:
            return "Personal Assistant"
        case .coach:
            return "Coach"
        }
    }

    var promptSummary: String {
        switch self {
        case .operatorPartner:
            return "Act like a trusted operator partner who keeps project work, personal admin, and follow-through aligned without sounding ceremonial."
        case .chiefOfStaff:
            return "Act like a chief of staff who helps prioritize commitments, protects focus, and turns loose goals into a concrete operating rhythm."
        case .personalAssistant:
            return "Act like a practical personal assistant who keeps track of commitments, upcoming obligations, and routine follow-ups."
        case .coach:
            return "Act like a direct coach who spots drift early, names tradeoffs clearly, and pushes the user back toward stated priorities."
        }
    }
}

enum SupervisorBriefingStyle: String, Codable, CaseIterable, Identifiable {
    case concise
    case balanced
    case proactive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .concise:
            return "Concise"
        case .balanced:
            return "Balanced"
        case .proactive:
            return "Proactive"
        }
    }

    var promptSummary: String {
        switch self {
        case .concise:
            return "Default to short executive summaries with only the most important actions and risks."
        case .balanced:
            return "Balance concise summaries with enough context for the user to understand why the recommendation matters."
        case .proactive:
            return "Proactively surface missed follow-ups, weak plans, and better options instead of waiting to be asked."
        }
    }
}

enum SupervisorPersonalRiskTolerance: String, Codable, CaseIterable, Identifiable {
    case conservative
    case balanced
    case aggressive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .conservative:
            return "Conservative"
        case .balanced:
            return "Balanced"
        case .aggressive:
            return "Aggressive"
        }
    }

    var promptSummary: String {
        switch self {
        case .conservative:
            return "Prefer safer, more reversible plans and call out hidden downside before endorsing bold moves."
        case .balanced:
            return "Balance speed and downside; surface the main tradeoff before recommending a path."
        case .aggressive:
            return "Bias toward decisive forward motion when the upside is clear, but still call out irreversible risk."
        }
    }
}

enum SupervisorInterruptionTolerance: String, Codable, CaseIterable, Identifiable {
    case low
    case balanced
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .balanced:
            return "Balanced"
        case .high:
            return "High"
        }
    }

    var promptSummary: String {
        switch self {
        case .low:
            return "Avoid interrupting the user unless something is time-sensitive, high-risk, or likely to be forgotten."
        case .balanced:
            return "Interrupt when timing materially changes the outcome, but avoid constant nagging."
        case .high:
            return "Interrupt early when commitments, deadlines, or important follow-ups are drifting."
        }
    }
}

enum SupervisorReminderAggressiveness: String, Codable, CaseIterable, Identifiable {
    case quiet
    case balanced
    case assertive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quiet:
            return "Quiet"
        case .balanced:
            return "Balanced"
        case .assertive:
            return "Assertive"
        }
    }

    var promptSummary: String {
        switch self {
        case .quiet:
            return "Remind lightly and avoid repeating the same follow-up unless the due state changes."
        case .balanced:
            return "Remind with moderate persistence when commitments or review loops start slipping."
        case .assertive:
            return "Be persistent about overdue follow-ups, review loops, and time-sensitive obligations."
        }
    }
}

struct SupervisorPersonalProfile: Codable, Equatable {
    var preferredName: String
    var goalsSummary: String
    var workStyle: String
    var communicationPreferences: String
    var dailyRhythm: String
    var reviewPreferences: String

    static func `default`() -> SupervisorPersonalProfile {
        SupervisorPersonalProfile(
            preferredName: "",
            goalsSummary: "",
            workStyle: "",
            communicationPreferences: "",
            dailyRhythm: "",
            reviewPreferences: ""
        )
    }

    func normalized() -> SupervisorPersonalProfile {
        SupervisorPersonalProfile(
            preferredName: Self.normalizeSingleLine(preferredName),
            goalsSummary: Self.normalizeMultiline(goalsSummary),
            workStyle: Self.normalizeMultiline(workStyle),
            communicationPreferences: Self.normalizeMultiline(communicationPreferences),
            dailyRhythm: Self.normalizeMultiline(dailyRhythm),
            reviewPreferences: Self.normalizeMultiline(reviewPreferences)
        )
    }

    var isEffectivelyEmpty: Bool {
        let normalized = normalized()
        return normalized.preferredName.isEmpty
            && normalized.goalsSummary.isEmpty
            && normalized.workStyle.isEmpty
            && normalized.communicationPreferences.isEmpty
            && normalized.dailyRhythm.isEmpty
            && normalized.reviewPreferences.isEmpty
    }

    private static func normalizeSingleLine(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeMultiline(_ value: String) -> String {
        value
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SupervisorPersonalPolicy: Codable, Equatable {
    var relationshipMode: SupervisorRelationshipMode
    var briefingStyle: SupervisorBriefingStyle
    var riskTolerance: SupervisorPersonalRiskTolerance
    var interruptionTolerance: SupervisorInterruptionTolerance
    var reminderAggressiveness: SupervisorReminderAggressiveness
    var preferredMorningBriefTime: String
    var preferredEveningWrapUpTime: String
    var weeklyReviewDay: String

    static func `default`() -> SupervisorPersonalPolicy {
        SupervisorPersonalPolicy(
            relationshipMode: .operatorPartner,
            briefingStyle: .balanced,
            riskTolerance: .balanced,
            interruptionTolerance: .balanced,
            reminderAggressiveness: .balanced,
            preferredMorningBriefTime: "09:00",
            preferredEveningWrapUpTime: "18:00",
            weeklyReviewDay: "Sunday"
        )
    }

    func normalized() -> SupervisorPersonalPolicy {
        SupervisorPersonalPolicy(
            relationshipMode: relationshipMode,
            briefingStyle: briefingStyle,
            riskTolerance: riskTolerance,
            interruptionTolerance: interruptionTolerance,
            reminderAggressiveness: reminderAggressiveness,
            preferredMorningBriefTime: Self.normalizeSingleLine(preferredMorningBriefTime, fallback: Self.default().preferredMorningBriefTime),
            preferredEveningWrapUpTime: Self.normalizeSingleLine(preferredEveningWrapUpTime, fallback: Self.default().preferredEveningWrapUpTime),
            weeklyReviewDay: Self.normalizeSingleLine(weeklyReviewDay, fallback: Self.default().weeklyReviewDay)
        )
    }

    var hasNonDefaultConfiguration: Bool {
        normalized() != .default()
    }

    private static func normalizeSingleLine(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
