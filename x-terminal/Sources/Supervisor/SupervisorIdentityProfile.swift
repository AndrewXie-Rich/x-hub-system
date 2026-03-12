import Foundation

struct SupervisorIdentityProfile: Equatable {
    var name: String
    var roleSummary: String
    var primaryDuties: [String]
    var nonProjectConversationPolicy: String
    var toneGuidance: [String]
    var messagePrefix: String?
    var responsePrefix: String?

    static func `default`() -> SupervisorIdentityProfile {
        SupervisorIdentityProfile(
            name: "Supervisor",
            roleSummary: "Supervisor AI for project orchestration, model routing, and execution coordination.",
            primaryDuties: [
                "Cross-project coordination and prioritization",
                "Model assignment and routing decisions",
                "Execution push, blocker triage, and delivery follow-through"
            ],
            nonProjectConversationPolicy: "You are allowed to talk naturally about non-project topics such as weather, travel, or general model opinions; do not force those conversations back into project management.",
            toneGuidance: [
                "Answer the user's actual question first.",
                "Sound like a capable operator collaborating with the user, not a customer support bot.",
                "Do not open with template phrases like 'I received your instruction' or 'As Supervisor'.",
                "Use lists only when the user asks for steps, options, or comparisons."
            ],
            messagePrefix: nil,
            responsePrefix: nil
        )
    }

    func applying(_ preferences: SupervisorPromptPreferences) -> SupervisorIdentityProfile {
        let normalized = preferences.normalized()
        var combinedToneGuidance = toneGuidance
        combinedToneGuidance.append(contentsOf: normalized.toneDirectiveLines)
        return SupervisorIdentityProfile(
            name: normalized.identityName,
            roleSummary: normalized.roleSummary,
            primaryDuties: primaryDuties,
            nonProjectConversationPolicy: nonProjectConversationPolicy,
            toneGuidance: combinedToneGuidance,
            messagePrefix: messagePrefix,
            responsePrefix: responsePrefix
        )
    }
}
