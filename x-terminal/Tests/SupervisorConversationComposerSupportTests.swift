import Foundation
import Testing
@testable import XTerminal

struct SupervisorConversationComposerSupportTests {

    @Test
    func syncedDraftOnlyChangesWhenExternalInputActuallyDiffers() {
        #expect(
            SupervisorConversationComposerSupport.syncedDraft(
                currentDraft: "hello",
                externalInput: "hello"
            ) == "hello"
        )
        #expect(
            SupervisorConversationComposerSupport.syncedDraft(
                currentDraft: "hello",
                externalInput: "hello world"
            ) == "hello world"
        )
    }

    @Test
    func syncedInputOnlyChangesWhenDraftActuallyDiffers() {
        #expect(
            SupervisorConversationComposerSupport.syncedInput(
                currentInput: "draft",
                draft: "draft"
            ) == "draft"
        )
        #expect(
            SupervisorConversationComposerSupport.syncedInput(
                currentInput: "",
                draft: "draft"
            ) == "draft"
        )
    }

    @Test
    func submissionTransitionTrimsPayloadAndClearsComposer() {
        let transition = SupervisorConversationComposerSupport.submissionTransition(
            draft: "  continue this task  \n"
        )

        #expect(
            transition == SupervisorConversationComposerTransition(
                payload: "continue this task",
                nextDraft: "",
                nextInput: ""
            )
        )
        #expect(
            SupervisorConversationComposerSupport.submissionTransition(draft: "   \n") == nil
        )
    }

    @Test
    func autoSendVoiceTransitionRequiresAutoSendAndClearsComposer() {
        #expect(
            SupervisorConversationComposerSupport.autoSendVoiceTransition(
                recognized: "批准这个 grant",
                autoSendVoice: false
            ) == nil
        )
        #expect(
            SupervisorConversationComposerSupport.autoSendVoiceTransition(
                recognized: "  批准这个 grant  ",
                autoSendVoice: true
            ) == SupervisorConversationComposerTransition(
                payload: "批准这个 grant",
                nextDraft: "",
                nextInput: ""
            )
        )
    }
}
