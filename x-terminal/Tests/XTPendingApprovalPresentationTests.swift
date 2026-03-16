import Foundation
import Testing
@testable import XTerminal

struct XTPendingApprovalPresentationTests {

    @Test
    func projectApprovalMessageUsesHumanPreviewForBrowserOpen() {
        let toolCall = ToolCall(
            id: "pending-browser-1",
            tool: .deviceBrowserControl,
            args: [
                "action": .string("open_url"),
                "url": .string("https://example.com")
            ]
        )

        let message = XTPendingApprovalPresentation.approvalMessage(for: toolCall)
        let summary = XTPendingApprovalPresentation.actionSummary(for: toolCall)

        #expect(message.summary.contains("Waiting for local approval"))
        #expect(message.summary.contains("https://example.com"))
        #expect(summary == "Open https://example.com in the browser")
        #expect(message.nextStep?.contains("Approve it in X-Terminal") == true)
    }

    @Test
    func actionSummaryHumanizesCommandExecution() {
        let toolCall = ToolCall(
            id: "pending-command-1",
            tool: .run_command,
            args: [
                "command": .string("swift test --filter XTToolAuthorizationTests")
            ]
        )

        let summary = XTPendingApprovalPresentation.actionSummary(for: toolCall)
        let message = XTPendingApprovalPresentation.approvalMessage(for: toolCall)

        #expect(summary.contains("Run command"))
        #expect(summary.contains("swift test --filter XTToolAuthorizationTests"))
        #expect(message.summary.contains("command swift test --filter XTToolAuthorizationTests"))
    }

    @Test
    func supplementaryReasonDropsGenericApprovalCopy() {
        let message = XTGuardrailMessage(
            summary: "Waiting for local approval before running run command for command swift test.",
            nextStep: "Approve it in X-Terminal to let the guarded tool run."
        )

        let reason = XTPendingApprovalPresentation.supplementaryReason(
            "waiting for local governed approval",
            primaryMessage: message
        )

        #expect(reason == nil)
    }

    @Test
    func supplementaryReasonKeepsUsefulOperatorContext() {
        let message = XTGuardrailMessage(
            summary: "Waiting for local approval before running browser control on https://example.com.",
            nextStep: "Approve it in X-Terminal to let the guarded tool run."
        )

        let reason = XTPendingApprovalPresentation.supplementaryReason(
            "requested by nightly QA monitor",
            primaryMessage: message
        )

        #expect(reason == "requested by nightly QA monitor")
    }
}
