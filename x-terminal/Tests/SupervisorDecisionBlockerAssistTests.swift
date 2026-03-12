import Foundation
import Testing
@testable import XTerminal

struct SupervisorDecisionBlockerAssistTests {
    @Test
    func lowRiskTemplateCatalogCoversAllGovernedDefaults() {
        let categories: [SupervisorDecisionBlockerCategory] = [
            .techStack,
            .scaffold,
            .testStack,
            .docTemplate
        ]

        for category in categories {
            let templates = SupervisorDecisionBlockerAssistEngine.templateCatalog(for: category)
            #expect(!templates.isEmpty)
            #expect(templates.allSatisfy { $0.category == category })
            #expect(templates.allSatisfy { $0.reversible })
        }
    }

    @Test
    func lowRiskProposalIsGeneratedButRemainsPendingByDefault() {
        let assist = SupervisorDecisionBlockerAssistEngine.build(
            context: SupervisorDecisionBlockerContext(
                projectId: "proj-demo",
                blockerId: "blk-test-stack",
                category: .testStack,
                reversible: true,
                riskLevel: .low,
                timeoutEscalationAfterMs: 900_000,
                evidenceRefs: ["build/reports/xt_w3_33_f_decision_blocker_assist_evidence.v1.json"]
            ),
            nowMs: 1_778_000_000_000
        )

        #expect(assist.schemaVersion == "xt.supervisor_decision_blocker_assist.v1")
        #expect(assist.blockerCategory == .testStack)
        #expect(assist.templateCandidates.contains("swift_testing_contract_default"))
        #expect(assist.recommendedOption == "swift_testing_contract_default")
        #expect(assist.governanceMode == .proposalWithTimeoutEscalation)
        #expect(assist.timeoutEscalationAfterMs == 900_000)
        #expect(assist.autoAdoptAllowed == false)
        #expect(assist.requiresUserDecision == true)
        #expect(assist.approvalState == .proposalPending)
        #expect(assist.failClosed == false)
        #expect(assist.policyReasons.contains("low_risk_reversible_default_available"))
        #expect(assist.explanation.contains("remains pending"))
    }

    @Test
    func autoAdoptModeIsExplicitButAssistStillDoesNotSelfApprove() {
        let assist = SupervisorDecisionBlockerAssistEngine.build(
            context: SupervisorDecisionBlockerContext(
                projectId: "proj-demo",
                blockerId: "blk-doc-template",
                category: .docTemplate,
                reversible: true,
                riskLevel: .low,
                allowAutoAdoptWhenPolicyAllows: true
            ),
            nowMs: 1_778_100_000_000
        )

        #expect(assist.governanceMode == .autoAdoptIfPolicyAllows)
        #expect(assist.autoAdoptAllowed == true)
        #expect(assist.approvalState == .proposalPending)
        #expect(assist.failClosed == false)
        #expect(assist.requiresUserDecision == false)
        #expect(assist.explanation.contains("does not mark the decision approved"))
    }

    @Test
    func irreversibleReleaseScopeChangeFailsClosedWithoutAuthorization() {
        let assist = SupervisorDecisionBlockerAssistEngine.build(
            context: SupervisorDecisionBlockerContext(
                projectId: "proj-demo",
                blockerId: "blk-release-scope",
                category: .releaseScope,
                reversible: false,
                riskLevel: .high,
                touchesReleaseScope: true,
                requiresHubAuthorization: true,
                explicitApprovalGranted: false
            ),
            nowMs: 1_778_200_000_000
        )

        #expect(assist.governanceMode == .proposalOnly)
        #expect(assist.autoAdoptAllowed == false)
        #expect(assist.requiresUserDecision == true)
        #expect(assist.approvalState == .proposalPending)
        #expect(assist.failClosed == true)
        #expect(assist.templateCandidates.isEmpty)
        #expect(assist.recommendedOption == nil)
        #expect(assist.policyReasons.contains("irreversible_decision_requires_manual_approval"))
        #expect(assist.policyReasons.contains("release_scope_change_must_fail_closed"))
        #expect(assist.policyReasons.contains("hub_or_user_authorization_missing"))
    }
}
