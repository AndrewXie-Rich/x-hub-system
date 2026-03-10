import Testing
@testable import XTerminal

struct PaidModelAccessTroubleshootRoutingTests {
    @Test
    func paidModelIssueGuideStaysWithinThreeFixSteps() {
        let guide = UITroubleshootKnowledgeBase.guide(for: .paidModelAccessBlocked)
        #expect(guide.maxFixSteps == 3)
        #expect(guide.steps.map(\.destination).contains(.hubPairing))
        #expect(guide.steps.map(\.destination).contains(.hubModels))
        #expect(guide.steps.first?.destination == .xtChooseModel)
    }

    @Test
    func paidModelDevicePolicyCodesMapToDedicatedTroubleshootIssue() {
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "device_paid_model_disabled") == .paidModelAccessBlocked)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "device_paid_model_not_allowed") == .paidModelAccessBlocked)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "device_daily_token_budget_exceeded") == .paidModelAccessBlocked)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "device_single_request_token_exceeded") == .paidModelAccessBlocked)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "legacy_grant_flow_required") == .paidModelAccessBlocked)
    }
}
