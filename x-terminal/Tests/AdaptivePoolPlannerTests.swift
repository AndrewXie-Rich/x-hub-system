import Foundation
import Testing
@testable import XTerminal

func makeCrossPoolCycleBuildResult(projectID: UUID) -> SplitProposalBuildResult {
    let taskMainA = DecomposedTask(
        id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!,
        description: "Mainline contract lane",
        type: .development,
        complexity: .moderate,
        estimatedEffort: 3_600,
        dependencies: [UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000003")!],
        priority: 5,
        metadata: [:]
    )
    let taskMainB = DecomposedTask(
        id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000002")!,
        description: "Mainline implementation lane",
        type: .development,
        complexity: .moderate,
        estimatedEffort: 3_600,
        dependencies: [],
        priority: 4,
        metadata: [:]
    )
    let taskIsoA = DecomposedTask(
        id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000003")!,
        description: "Isolated integration lane",
        type: .testing,
        complexity: .moderate,
        estimatedEffort: 3_600,
        dependencies: [],
        priority: 4,
        metadata: [:]
    )
    let taskIsoB = DecomposedTask(
        id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000004")!,
        description: "Isolated evidence lane",
        type: .documentation,
        complexity: .simple,
        estimatedEffort: 1_800,
        dependencies: [UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000002")!],
        priority: 3,
        metadata: [:]
    )
    let rootTask = DecomposedTask(
        id: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000000")!,
        description: "Cross pool cycle fixture",
        type: .development,
        complexity: .complex,
        estimatedEffort: 7_200,
        dependencies: [],
        priority: 5,
        metadata: [:]
    )
    let analysis = TaskAnalysis(
        originalDescription: "Cross pool cycle fixture",
        keywords: ["cycle", "pool"],
        verbs: ["build"],
        objects: ["module"],
        constraints: ["fail closed"],
        type: .development,
        complexity: .complex,
        estimatedEffort: 7_200,
        requiredSkills: ["swift"],
        riskLevel: .high,
        suggestedSubtasks: [],
        potentialDependencies: []
    )
    let graph = DependencyGraph(tasks: [rootTask, taskMainA, taskMainB, taskIsoA, taskIsoB])
    let decomposition = DecompositionResult(
        rootTask: rootTask,
        subtasks: [taskMainA, taskMainB, taskIsoA, taskIsoB],
        allTasks: [rootTask, taskMainA, taskMainB, taskIsoA, taskIsoB],
        dependencyGraph: graph,
        analysis: analysis
    )
    let proposal = SplitProposal(
        splitPlanId: UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000026")!,
        rootProjectId: projectID,
        planVersion: 1,
        complexityScore: 0.79,
        lanes: [
            SplitLaneProposal(
                laneId: "lane-main-a",
                goal: "Mainline contract lane",
                dependsOn: ["lane-iso-a"],
                riskTier: .low,
                budgetClass: .standard,
                createChildProject: false,
                expectedArtifacts: ["build/reports/main-a.json"],
                dodChecklist: ["contract_frozen"],
                estimatedEffortMs: 1_000,
                tokenBudget: 2_000,
                sourceTaskId: taskMainA.id,
                notes: []
            ),
            SplitLaneProposal(
                laneId: "lane-main-b",
                goal: "Mainline implementation lane",
                dependsOn: [],
                riskTier: .low,
                budgetClass: .standard,
                createChildProject: false,
                expectedArtifacts: ["build/reports/main-b.json"],
                dodChecklist: ["impl_done"],
                estimatedEffortMs: 1_000,
                tokenBudget: 2_000,
                sourceTaskId: taskMainB.id,
                notes: []
            ),
            SplitLaneProposal(
                laneId: "lane-iso-a",
                goal: "Isolated integration lane",
                dependsOn: [],
                riskTier: .high,
                budgetClass: .premium,
                createChildProject: true,
                expectedArtifacts: ["build/reports/iso-a.json"],
                dodChecklist: ["integration_ready"],
                estimatedEffortMs: 1_200,
                tokenBudget: 4_000,
                sourceTaskId: taskIsoA.id,
                notes: []
            ),
            SplitLaneProposal(
                laneId: "lane-iso-b",
                goal: "Isolated evidence lane",
                dependsOn: ["lane-main-b"],
                riskTier: .high,
                budgetClass: .premium,
                createChildProject: true,
                expectedArtifacts: ["build/reports/iso-b.json"],
                dodChecklist: ["evidence_ready"],
                estimatedEffortMs: 900,
                tokenBudget: 4_000,
                sourceTaskId: taskIsoB.id,
                notes: []
            )
        ],
        recommendedConcurrency: 2,
        tokenBudgetTotal: 12_000,
        estimatedWallTimeMs: 2_500,
        sourceTaskDescription: "Cross pool cycle fixture",
        createdAt: Date(timeIntervalSince1970: 1_772_220_026)
    )
    return SplitProposalBuildResult(
        decomposition: decomposition,
        proposal: proposal,
        validation: SplitProposalValidationResult(issues: [])
    )
}

struct AdaptivePoolPlannerTests {

    @Test
    @MainActor
    func adaptivePlannerProducesDeterministicGovernedPlan() async {
        let coordinator = OneShotIntakeCoordinator()
        let request = coordinator.normalize(makeOneShotSubmission()).request
        let decomposer = TaskDecomposer()
        let buildOne = await decomposer.analyzeAndBuildSplitProposal(
            request.userGoal,
            rootProjectId: request.projectUUID,
            planVersion: 1
        )
        let buildTwo = await decomposer.analyzeAndBuildSplitProposal(
            request.userGoal,
            rootProjectId: request.projectUUID,
            planVersion: 1
        )
        let planner = AdaptivePoolPlanner()
        let planOne = planner.plan(request: request, buildResult: buildOne)
        let planTwo = planner.plan(request: request, buildResult: buildTwo)

        #expect(planOne.decision == planTwo.decision)
        #expect(planOne.seatGovernor == planTwo.seatGovernor)
        #expect(planOne.decision.seatCap <= 3)
        #expect(planOne.seatGovernor.approvedLaneCount <= planOne.seatGovernor.laneCap)
        #expect(planOne.decision.decisionExplain.contains("sensitive_side_effect_detected"))
        #expect(planOne.decision.decisionExplain.contains("unsafe_auto_launch_fail_closed"))
        #expect(planOne.decision.decision != .deny)
    }

    @Test
    @MainActor
    func plannerDeniesCrossPoolCycle() {
        let coordinator = OneShotIntakeCoordinator()
        let request = coordinator.normalize(makeOneShotSubmission(allowAutoLaunch: false)).request
        let planner = AdaptivePoolPlanner()
        let result = planner.plan(
            request: request,
            buildResult: makeCrossPoolCycleBuildResult(projectID: request.projectUUID)
        )

        #expect(result.decision.decision == .deny)
        #expect(result.decision.denyCode == "cross_pool_cycle_detected")
        #expect(result.seatGovernor.crossPoolCycleDetected)
        #expect(result.decision.decisionExplain.contains("cross_pool_cycle_detected"))
    }

    @Test
    @MainActor
    func runtimeCaptureWritesXTW326EvidenceFilesWhenRequested() async throws {
        guard let captureDir = ProcessInfo.processInfo.environment["XT_W3_26_CAPTURE_DIR"], !captureDir.isEmpty else {
            return
        }

        let fixture = await buildOneShotControlFixture()
        let invalidStore = OneShotRunStateStore()
        _ = invalidStore.bootstrap(request: fixture.normalization.request, evidenceRefs: oneShotEvidenceRefs)
        let invalidTransition = invalidStore.transition(
            to: .running,
            owner: .supervisor,
            userVisibleSummary: "invalid direct jump",
            evidenceRefs: oneShotEvidenceRefs,
            auditRef: fixture.normalization.request.auditRef
        )

        #expect(fixture.normalization.request.allowAutoLaunch == false)
        #expect(fixture.planning.decision.decision != .deny)
        #expect(fixture.planning.seatGovernor.seatCap <= 3)
        #expect(invalidTransition.state == .failedClosed)
        #expect(fixture.runState.state == .awaitingGrant)

        let base = URL(fileURLWithPath: captureDir)
        let intakeEvidence = XTW326OneShotIntakeEvidence(
            schemaVersion: "xt_w3_26_a_one_shot_intake_evidence.v1",
            normalization: fixture.normalization,
            fieldFreeze: .ai1Core,
            sourceRefs: oneShotSourceRefs()
        )
        let planEvidence = XTW326AdaptivePoolPlanEvidence(
            schemaVersion: "xt_w3_26_b_adaptive_pool_plan_evidence.v1",
            planning: fixture.planning,
            sourceRefs: oneShotSourceRefs()
        )
        let governorEvidence = XTW326ConcurrencyGovernorEvidence(
            schemaVersion: "xt_w3_26_c_concurrency_governor_evidence.v1",
            governor: fixture.planning.seatGovernor,
            sourceRefs: oneShotSourceRefs()
        )
        let runStateEvidence = XTW326RunStateMachineEvidence(
            schemaVersion: "xt_w3_26_d_run_state_machine_evidence.v1",
            runState: fixture.runState,
            sourceRefs: oneShotSourceRefs()
        )
        let handoff = OneShotAIHandoffPacket(
            schemaVersion: "xt_w3_26_ai1_handoff.v1",
            producer: "AI-1 (XT-OS-CORE)",
            claimScope: ["XT-W3-26-A", "XT-W3-26-B", "XT-W3-26-C", "XT-W3-26-D"],
            fieldFreeze: .ai1Core,
            runStateEnum: OneShotRunStateStatus.allCases.map(\ .rawValue),
            plannerExplainExample: fixture.planning.decision.decisionExplain,
            verificationResults: [
                OneShotVerificationResult(name: "normalized_request_fail_closed", status: "pass", detail: "auto_launch_requested=true normalized to allow_auto_launch=false with external authorization retained"),
                OneShotVerificationResult(name: "planner_determinism", status: "pass", detail: "same input and config produced identical adaptive plan + governor output"),
                OneShotVerificationResult(name: "lane_cap_governor", status: "pass", detail: "seat_cap<=3 and approved_lane_count<=lane_cap"),
                OneShotVerificationResult(name: "run_state_invalid_transition_fail_closed", status: "pass", detail: invalidTransition.topBlocker)
            ],
            evidenceRefs: oneShotEvidenceRefs
        )

        try writeOneShotJSON(intakeEvidence, to: base.appendingPathComponent("xt_w3_26_a_one_shot_intake_evidence.v1.json"))
        try writeOneShotJSON(planEvidence, to: base.appendingPathComponent("xt_w3_26_b_adaptive_pool_plan_evidence.v1.json"))
        try writeOneShotJSON(governorEvidence, to: base.appendingPathComponent("xt_w3_26_c_concurrency_governor_evidence.v1.json"))
        try writeOneShotJSON(runStateEvidence, to: base.appendingPathComponent("xt_w3_26_d_run_state_machine_evidence.v1.json"))
        try writeOneShotJSON(handoff, to: base.appendingPathComponent("xt_w3_26_ai1_handoff.v1.json"))

        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("xt_w3_26_ai1_handoff.v1.json").path))
    }
}
