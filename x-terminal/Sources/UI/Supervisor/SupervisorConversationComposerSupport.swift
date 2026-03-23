import Foundation

struct SupervisorConversationComposerTransition: Equatable {
    var payload: String
    var nextDraft: String
    var nextInput: String
}

enum SupervisorConversationComposerSupport {
    static func syncedDraft(currentDraft: String, externalInput: String) -> String {
        currentDraft == externalInput ? currentDraft : externalInput
    }

    static func syncedInput(currentInput: String, draft: String) -> String {
        currentInput == draft ? currentInput : draft
    }

    static func submissionTransition(draft: String) -> SupervisorConversationComposerTransition? {
        guard let payload = normalizedPayload(draft) else { return nil }
        return SupervisorConversationComposerTransition(
            payload: payload,
            nextDraft: "",
            nextInput: ""
        )
    }

    static func autoSendVoiceTransition(
        recognized: String,
        autoSendVoice: Bool
    ) -> SupervisorConversationComposerTransition? {
        guard autoSendVoice, let payload = normalizedPayload(recognized) else { return nil }
        return SupervisorConversationComposerTransition(
            payload: payload,
            nextDraft: "",
            nextInput: ""
        )
    }

    private static func normalizedPayload(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
