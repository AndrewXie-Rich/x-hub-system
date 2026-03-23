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

        #expect(message.summary.contains("本地审批"))
        #expect(message.summary.contains("https://example.com"))
        #expect(summary == "在浏览器中打开 https://example.com")
        #expect(message.nextStep?.contains("先在 X-Terminal 里批准") == true)
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

        #expect(summary.contains("运行命令"))
        #expect(summary.contains("swift test --filter XTToolAuthorizationTests"))
        #expect(message.summary.contains("命令 swift test --filter XTToolAuthorizationTests"))
    }

    @Test
    func supplementaryReasonDropsGenericApprovalCopy() {
        let message = XTGuardrailMessage(
            summary: "运行命令（命令 swift test）前，还需要先通过本地审批。",
            nextStep: "先在 X-Terminal 里批准，让受治理工具继续执行。"
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
            summary: "运行浏览器控制（https://example.com）前，还需要先通过本地审批。",
            nextStep: "先在 X-Terminal 里批准，让受治理工具继续执行。"
        )

        let reason = XTPendingApprovalPresentation.supplementaryReason(
            "requested by nightly QA monitor",
            primaryMessage: message
        )

        #expect(reason == "requested by nightly QA monitor")
    }
}
