import Foundation
import Testing
@testable import XTerminal

let oneShotTestProjectID = "11111111-2222-3333-4444-555555555555"
let oneShotEvidenceRefs = OneShotControlPlaneSnapshot.defaultEvidenceRefs()

func oneShotSourceRefs() -> [String] {
    [
        "x-terminal/Sources/Supervisor/OneShotIntakeCoordinator.swift",
        "x-terminal/Sources/Supervisor/AdaptivePoolPlanner.swift",
        "x-terminal/Sources/Supervisor/CriticalPathSeatAllocator.swift",
        "x-terminal/Sources/Supervisor/OneShotRunStateStore.swift",
        "x-terminal/Sources/Supervisor/SupervisorManager.swift",
        "x-terminal/Tests/SupervisorOneShotIntakeTests.swift",
        "x-terminal/Tests/AdaptivePoolPlannerTests.swift"
    ]
}

func makeOneShotSubmission(allowAutoLaunch: Bool = true) -> OneShotIntakeSubmission {
    OneShotIntakeSubmission(
        projectID: oneShotTestProjectID,
        requestID: "66666666-7777-8888-9999-000000000026",
        userGoal: "Build one-shot intake, adaptive pool planner, seat governor, and explicit run state for XT-W3-26 without lane explosion or cross-pool cycles.",
        documents: oneShotIntakeDocuments(),
        contextRefs: [
            "memory://project/xt-w3-26",
            "file://x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md"
        ],
        preferredSplitProfile: .auto,
        participationMode: .zeroTouch,
        innovationLevel: .l2,
        tokenBudgetClass: .standard,
        deliveryMode: .implementationFirst,
        allowAutoLaunch: allowAutoLaunch,
        requiresHumanAuthorizationTypes: [.externalSideEffect],
        auditRef: "audit-xt-w3-26-a1",
        now: Date(timeIntervalSince1970: 1_772_220_026)
    )
}

func oneShotIntakeDocuments() -> [SupervisorIntakeSourceDocument] {
    [
        SupervisorIntakeSourceDocument(
            ref: "docs/xt-w3-26-one-shot.md",
            kind: .markdown,
            contents: """
            project_goal: Build one-shot supervisor entry and governed planning surface
            touch_policy: zero_touch
            innovation_level: L2
            suggestion_governance: hybrid
            risk_level: medium
            requires_user_authorization: true
            acceptance_mode: release_candidate
            token_budget_tier: balanced
            paid_ai_allowed: false

            ## in_scope
            - one-shot intake entry
            - adaptive pool planner
            - seat governor
            - run state machine

            ## out_of_scope
            - UI product surfaces
            - directed unblock baton runtime
            - delivery freeze messaging

            ## constraints
            - fail closed
            - no lane explosion
            - no cross pool cycle
            - external side effects require grant
            - secret refs stay out of prompt bundles

            ## acceptance_targets
            - normalized_request_ready
            - explain_ready
            - run_state_explicit
            - evidence_complete
            """
        )
    ]
}

@MainActor
func buildOneShotControlFixture() async -> (
    normalization: OneShotIntakeNormalizationResult,
    buildResult: SplitProposalBuildResult,
    planning: AdaptivePoolPlanningResult,
    runState: OneShotRunStateSnapshot
) {
    let coordinator = OneShotIntakeCoordinator()
    let normalization = coordinator.normalize(makeOneShotSubmission())
    let decomposer = TaskDecomposer()
    let buildResult = await decomposer.analyzeAndBuildSplitProposal(
        normalization.request.userGoal,
        rootProjectId: normalization.request.projectUUID,
        planVersion: 1
    )
    let planning = AdaptivePoolPlanner().plan(
        request: normalization.request,
        buildResult: buildResult
    )

    let store = OneShotRunStateStore()
    _ = store.bootstrap(
        request: normalization.request,
        planDecision: planning.decision,
        owner: .supervisor,
        evidenceRefs: oneShotEvidenceRefs
    )
    _ = store.transition(
        to: .planning,
        owner: .supervisor,
        activePools: planning.decision.poolPlan.map(\ .poolID),
        activeLanes: planning.decision.poolPlan.flatMap(\ .laneIDs),
        topBlocker: "none",
        nextDirectedTarget: "Supervisor",
        userVisibleSummary: "adaptive pool planning completed",
        evidenceRefs: oneShotEvidenceRefs,
        auditRef: normalization.request.auditRef
    )
    let runState = store.transition(
        to: .awaitingGrant,
        owner: .hubL5,
        activePools: planning.decision.poolPlan.map(\ .poolID),
        activeLanes: planning.decision.poolPlan.flatMap(\ .laneIDs),
        topBlocker: normalization.request.requiresHumanAuthorizationTypes.map(\ .rawValue).joined(separator: ","),
        nextDirectedTarget: "Hub-L5",
        userVisibleSummary: "awaiting grant for guarded one-shot launch",
        evidenceRefs: oneShotEvidenceRefs,
        auditRef: normalization.request.auditRef
    )

    return (normalization, buildResult, planning, runState)
}

func writeOneShotJSON<T: Encodable>(_ value: T, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    try data.write(to: url)
}

struct SupervisorOneShotIntakeTests {

    @Test
    @MainActor
    func oneShotIntakeNormalizesFailClosedRequest() {
        let result = OneShotIntakeCoordinator().normalize(makeOneShotSubmission())

        #expect(result.request.schemaVersion == "xt.supervisor_one_shot_intake_request.v1")
        #expect(result.request.projectID == oneShotTestProjectID)
        #expect(result.request.requestID == "66666666-7777-8888-9999-000000000026")
        #expect(result.request.userGoal.contains("one-shot intake"))
        #expect(result.request.contextRefs.contains("docs/xt-w3-26-one-shot.md"))
        #expect(result.request.preferredSplitProfile == .conservative)
        #expect(result.request.participationMode == .zeroTouch)
        #expect(result.request.innovationLevel == .l2)
        #expect(result.request.tokenBudgetClass == .standard)
        #expect(result.request.allowAutoLaunch == false)
        #expect(result.request.requiresHumanAuthorizationTypes.contains(.externalSideEffect))
        #expect(result.freezeDecision == .pass)
        #expect(result.accepted)
        #expect(result.issues.contains { $0.code == "auto_launch_downgraded_fail_closed" })
    }

    @Test
    @MainActor
    func runStateStoreFailsClosedOnInvalidTransition() {
        let normalization = OneShotIntakeCoordinator().normalize(makeOneShotSubmission())
        let store = OneShotRunStateStore()
        let initial = store.bootstrap(request: normalization.request, evidenceRefs: oneShotEvidenceRefs)
        let failed = store.transition(
            to: .running,
            owner: .supervisor,
            userVisibleSummary: "invalid direct jump",
            evidenceRefs: oneShotEvidenceRefs,
            auditRef: normalization.request.auditRef
        )

        #expect(initial.state == .intakeNormalized)
        #expect(failed.state == .failedClosed)
        #expect(failed.topBlocker.contains("invalid_transition_intake_normalized_to_running"))
        #expect(failed.nextDirectedTarget == "Supervisor")
    }
}
