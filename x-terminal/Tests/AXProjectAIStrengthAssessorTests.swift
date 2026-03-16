import Foundation
import Testing
@testable import XTerminal

struct AXProjectAIStrengthAssessorTests {

    @Test
    func assessWeakProjectWhenFailuresRegressionsAndFallbacksPileUp() {
        let evidence = AXProjectAIStrengthEvidence(
            recentActivities: [
                activity(requestID: "req-3", status: "blocked", createdAt: 30, authorizationDisposition: "deny", denyCode: "policy_denied"),
                activity(requestID: "req-2", status: "failed", createdAt: 20),
                activity(requestID: "req-1", status: "blocked", createdAt: 10, authorizationDisposition: "deny", denyCode: "grant_required")
            ],
            latestUIReview: AXProjectAIReviewEvidence(
                verdict: .attentionNeeded,
                sufficientEvidence: true,
                objectiveReady: false,
                trendStatus: .regressed
            ),
            recentUIReviewVerdicts: [.attentionNeeded, .insufficientEvidence, .insufficientEvidence],
            executionSnapshots: [
                executionSnapshot(role: .coder, updatedAt: 100, executionPath: "local_fallback_after_remote_error"),
                executionSnapshot(role: .reviewer, updatedAt: 90, executionPath: "hub_downgraded_to_local")
            ]
        )

        let profile = AXProjectAIStrengthAssessor.assess(
            evidence: evidence,
            assessedAtMs: 123_000
        )

        #expect(profile.strengthBand == .weak)
        #expect(profile.recommendedSupervisorFloor == .s4TightSupervision)
        #expect(profile.recommendedWorkOrderDepth == .stepLockedRescue)
        #expect(profile.confidence >= 0.70)
        #expect(profile.reasons.contains(where: { $0.contains("consecutive blocked/failed") }))
        #expect(profile.reasons.contains(where: { $0.contains("latest UI review still needs attention") }))
    }

    @Test
    func assessStrongProjectWhenSignalsAreCleanAndStable() {
        let evidence = AXProjectAIStrengthEvidence(
            recentActivities: [
                activity(requestID: "req-4", status: "completed", createdAt: 40),
                activity(requestID: "req-3", status: "completed", createdAt: 30),
                activity(requestID: "req-2", status: "completed", createdAt: 20),
                activity(requestID: "req-1", status: "completed", createdAt: 10)
            ],
            latestUIReview: AXProjectAIReviewEvidence(
                verdict: .ready,
                sufficientEvidence: true,
                objectiveReady: true,
                trendStatus: .improved
            ),
            recentUIReviewVerdicts: [.ready, .ready],
            executionSnapshots: [
                executionSnapshot(role: .coder, updatedAt: 100, executionPath: "remote_model"),
                executionSnapshot(role: .reviewer, updatedAt: 95, executionPath: "remote_model")
            ]
        )

        let profile = AXProjectAIStrengthAssessor.assess(
            evidence: evidence,
            assessedAtMs: 456_000
        )

        #expect(profile.strengthBand == .strong)
        #expect(profile.recommendedSupervisorFloor == .s0SilentAudit)
        #expect(profile.recommendedWorkOrderDepth == .none)
        #expect(profile.confidence >= 0.80)
        #expect(profile.reasons.contains(where: { $0.contains("completed cleanly") }))
        #expect(profile.reasons.contains(where: { $0.contains("execution-ready") }))
    }

    @Test
    func assessUnknownProjectWhenEvidenceIsStillSparse() {
        let profile = AXProjectAIStrengthAssessor.assess(
            evidence: AXProjectAIStrengthEvidence(
                recentActivities: [],
                latestUIReview: nil,
                recentUIReviewVerdicts: [],
                executionSnapshots: []
            ),
            assessedAtMs: 789_000
        )

        #expect(profile.strengthBand == .unknown)
        #expect(profile.recommendedSupervisorFloor == .s0SilentAudit)
        #expect(profile.recommendedWorkOrderDepth == .brief)
        #expect(profile.confidence <= 0.24)
        #expect(profile.reasons == ["recent project evidence is still sparse"])
    }
}

private func activity(
    requestID: String,
    status: String,
    createdAt: Double,
    authorizationDisposition: String = "",
    denyCode: String = ""
) -> ProjectSkillActivityItem {
    ProjectSkillActivityItem(
        requestID: requestID,
        skillID: "agent-browser",
        toolName: "device.browser.control",
        status: status,
        createdAt: createdAt,
        resolutionSource: "test",
        toolArgs: [:],
        resultSummary: "",
        detail: "",
        denyCode: denyCode,
        authorizationDisposition: authorizationDisposition
    )
}

private func executionSnapshot(
    role: AXRole,
    updatedAt: Double,
    executionPath: String
) -> AXRoleExecutionSnapshot {
    AXRoleExecutionSnapshots.snapshot(
        role: role,
        updatedAt: updatedAt,
        stage: "test",
        requestedModelId: "openai/gpt-5.4",
        actualModelId: executionPath == "remote_model" ? "openai/gpt-5.4" : "qwen3-17b-mlx-bf16",
        runtimeProvider: "Hub",
        executionPath: executionPath,
        fallbackReasonCode: executionPath == "remote_model" ? "" : "model_not_found",
        source: "test"
    )
}
