import Foundation

struct SupervisorConversationComposerTransition: Equatable {
    var payload: String
    var attachments: [AXChatAttachment] = []
    var nextDraft: String
    var nextInput: String
    var nextAttachments: [AXChatAttachment] = []
}

enum SupervisorConversationComposerSupport {
    static func syncedDraft(currentDraft: String, externalInput: String) -> String {
        currentDraft == externalInput ? currentDraft : externalInput
    }

    static func syncedInput(currentInput: String, draft: String) -> String {
        currentInput == draft ? currentInput : draft
    }

    static func submissionTransition(
        draft: String,
        attachments: [AXChatAttachment] = []
    ) -> SupervisorConversationComposerTransition? {
        guard let payload = normalizedPayload(draft, attachments: attachments) else { return nil }
        return SupervisorConversationComposerTransition(
            payload: payload,
            attachments: attachments,
            nextDraft: "",
            nextInput: "",
            nextAttachments: []
        )
    }

    static func applyingImportContinuation(
        draft: String,
        continuation: AXChatImportContinuationSuggestion?
    ) -> String {
        guard let continuation else { return draft }
        return AXChatAttachmentSupport.draftApplyingImportContinuation(
            continuation,
            existingDraft: draft
        )
    }

    static func continueAndSendTransition(
        draft: String,
        attachments: [AXChatAttachment] = [],
        continuation: AXChatImportContinuationSuggestion?
    ) -> SupervisorConversationComposerTransition? {
        guard continuation != nil else { return nil }
        let continuedDraft = applyingImportContinuation(
            draft: draft,
            continuation: continuation
        )
        return submissionTransition(
            draft: continuedDraft,
            attachments: attachments
        )
    }

    static func autoSendVoiceTransition(
        recognized: String,
        autoSendVoice: Bool,
        attachments: [AXChatAttachment] = []
    ) -> SupervisorConversationComposerTransition? {
        guard autoSendVoice, let payload = normalizedPayload(recognized, attachments: attachments) else { return nil }
        return SupervisorConversationComposerTransition(
            payload: payload,
            attachments: attachments,
            nextDraft: "",
            nextInput: "",
            nextAttachments: []
        )
    }

    private static func normalizedPayload(
        _ raw: String,
        attachments: [AXChatAttachment]
    ) -> String? {
        AXChatAttachmentSupport.normalizedUserPrompt(
            draft: raw,
            attachments: attachments
        )
    }
}
