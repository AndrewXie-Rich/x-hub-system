import Foundation
import Testing
@testable import XTerminal

struct SupervisorMultilaneFlowTests {

    @MainActor
    @Test
    func projectMaterializerHybridHardSoftMaterialization() async throws {
        let rootProject = ProjectModel(
            name: "Root",
            taskDescription: "Root project",
            modelName: "claude-sonnet-4.6"
        )

        var softTask = DecomposedTask(
            description: "Update docs",
            type: .documentation,
            complexity: .simple,
            estimatedEffort: 900,
            priority: 3
        )
        softTask.metadata["lane_id"] = "lane-soft"
        softTask.metadata["risk_tier"] = LaneRiskTier.low.rawValue
        softTask.metadata["budget_class"] = LaneBudgetClass.economy.rawValue
        softTask.metadata["create_child_project"] = "0"

        var hardTask = DecomposedTask(
            description: "Production release changes",
            type: .deployment,
            complexity: .complex,
            estimatedEffort: 4_800,
            priority: 9
        )
        hardTask.metadata["lane_id"] = "lane-hard"
        hardTask.metadata["risk_tier"] = LaneRiskTier.high.rawValue
        hardTask.metadata["budget_class"] = LaneBudgetClass.premium.rawValue
        hardTask.metadata["create_child_project"] = "1"

        let materializer = ProjectMaterializer(runtimeHost: nil)
        let result = await materializer.materialize(
            tasks: [softTask, hardTask],
            rootProject: rootProject,
            splitPlanID: "split-test"
        )

        #expect(result.lanes.count == 2)
        #expect(result.hardSplitWithoutChildProject == 0)
        #expect(result.softSplitLineagePollution == 0)

        let softLane = try #require(result.lanes.first(where: { $0.plan.laneID == "lane-soft" }))
        #expect(softLane.mode == .softSplit)
        #expect(softLane.targetProject?.id == rootProject.id)
        #expect(softLane.lineageOperations.isEmpty)
        #expect(softLane.task.metadata["create_child_project"] == "0")

        let hardLane = try #require(result.lanes.first(where: { $0.plan.laneID == "lane-hard" }))
        #expect(hardLane.mode == .hardSplit)
        #expect(hardLane.targetProject != nil)
        #expect(hardLane.targetProject?.id != rootProject.id)
        #expect(hardLane.lineageOperations.count == 2)
        #expect(hardLane.task.metadata["create_child_project"] == "1")
    }

    @MainActor
    @Test
    func projectMaterializerPersistsVerificationContractMetadata() async throws {
        let rootProject = ProjectModel(
            name: "Root",
            taskDescription: "Root project",
            modelName: "claude-sonnet-4.6"
        )

        let verificationContract = LaneVerificationContract(
            expectedState: "Release plan is ready and rollback proof is attached.",
            verifyMethod: .preflightAndSmoke,
            retryPolicy: .noAutoRetry,
            holdPolicy: .holdUntilEvidence,
            evidenceRequired: ["release_plan", "rollback_readiness", "smoke_result"],
            verificationChecklist: ["expected_state_confirmed", "evidence_attached", "rollback_ready"]
        )

        let lane = SplitLaneProposal(
            laneId: "lane-release",
            goal: "Prepare release lane",
            dependsOn: [],
            riskTier: .high,
            budgetClass: .premium,
            createChildProject: true,
            expectedArtifacts: ["release_plan"],
            dodChecklist: ["rollback_ready"],
            verificationContract: verificationContract,
            estimatedEffortMs: 3_000,
            tokenBudget: 8_000,
            sourceTaskId: nil,
            notes: []
        )

        let proposal = SplitProposal(
            splitPlanId: UUID(),
            rootProjectId: rootProject.id,
            planVersion: 1,
            complexityScore: 72,
            lanes: [lane],
            recommendedConcurrency: 1,
            tokenBudgetTotal: 8_000,
            estimatedWallTimeMs: 3_000,
            sourceTaskDescription: "release proposal",
            createdAt: Date()
        )

        let materializer = ProjectMaterializer(runtimeHost: nil)
        let result = await materializer.materialize(
            proposal: proposal,
            decomposition: nil,
            rootProject: rootProject
        )

        let materializedLane = try #require(result.lanes.first)
        #expect(materializedLane.plan.verificationContract == verificationContract)
        #expect(materializedLane.task.metadata["verification_expected_state"] == verificationContract.expectedState)
        #expect(materializedLane.task.metadata["verification_method"] == verificationContract.verifyMethod.rawValue)
        #expect(materializedLane.task.metadata["verification_retry_policy"] == verificationContract.retryPolicy.rawValue)
        #expect(materializedLane.task.metadata["verification_hold_policy"] == verificationContract.holdPolicy.rawValue)
        #expect(materializedLane.task.metadata["verification_evidence_required"] == verificationContract.evidenceRequired.joined(separator: "|"))
        #expect(materializedLane.task.metadata["verification_checklist"] == verificationContract.verificationChecklist.joined(separator: "|"))
    }

    @MainActor
    @Test
    func laneAllocatorIncludesRiskBudgetLoadExplain() throws {
        let highTrustProject = ProjectModel(
            name: "HighTrust",
            taskDescription: "Critical lanes",
            modelName: "claude-opus-4.6",
            autonomyLevel: .auto,
            budget: Budget(daily: 25, monthly: 750)
        )
        highTrustProject.currentModel = ModelInfo(
            id: "high-trust",
            name: "high-trust",
            displayName: "high-trust",
            type: .hubPaid,
            capability: .expert,
            speed: .medium,
            costPerMillionTokens: 3.0,
            memorySize: nil,
            suitableFor: ["critical"],
            badge: nil,
            badgeColor: nil
        )

        let lowTrustProject = ProjectModel(
            name: "LowTrust",
            taskDescription: "Cheap lanes",
            modelName: "local-small",
            isLocalModel: true,
            autonomyLevel: .manual,
            budget: Budget(daily: 2, monthly: 60)
        )
        lowTrustProject.currentModel = ModelInfo(
            id: "low-trust",
            name: "low-trust",
            displayName: "low-trust",
            type: .local,
            capability: .basic,
            speed: .fast,
            costPerMillionTokens: 0.2,
            memorySize: "8GB",
            suitableFor: ["simple"],
            badge: nil,
            badgeColor: nil
        )

        let laneTask = DecomposedTask(
            description: "Handle high-risk rollout",
            type: .deployment,
            complexity: .complex,
            estimatedEffort: 7_200,
            priority: 9
        )

        let lanePlan = SupervisorLanePlan(
            laneID: "lane-critical",
            goal: laneTask.description,
            dependsOn: [],
            riskTier: .high,
            budgetClass: .premium,
            createChildProject: false,
            expectedArtifacts: ["release_plan"],
            dodChecklist: ["rollback_ready"],
            source: .inferred,
            metadata: [:],
            task: laneTask
        )

        let lane = MaterializedLane(
            plan: lanePlan,
            mode: .softSplit,
            task: laneTask,
            targetProject: nil,
            lineageOperations: [],
            decisionReasons: ["test"],
            explain: "test lane"
        )

        let allocator = LaneAllocator()
        let result = allocator.allocate(
            lanes: [lane],
            projects: [lowTrustProject, highTrustProject]
        )

        let assignment = try #require(result.assignments.first)
        #expect(assignment.project.id == highTrustProject.id)
        #expect(assignment.factors.riskFit >= 0)
        #expect(assignment.factors.budgetFit >= 0)
        #expect(assignment.factors.loadFit >= 0)
        #expect(assignment.factors.skillFit >= 0)
        #expect(assignment.factors.reliabilityFit >= 0)
        #expect(assignment.explain.contains("risk_fit="))
        #expect(assignment.explain.contains("budget_fit="))
        #expect(assignment.explain.contains("load_fit="))
        #expect(assignment.explain.contains("skill_fit="))
        #expect(assignment.explain.contains("reliability_fit="))
        #expect(assignment.explain.contains("weights="))
        #expect(result.explainByLaneID["lane-critical"]?.isEmpty == false)
    }

    @MainActor
    @Test
    func laneAllocatorPrefersGovernanceTiersOverLegacyAutonomyShadow() throws {
        let governancePreferredProject = ProjectModel(
            name: "GovernancePreferred",
            taskDescription: "Critical lanes",
            modelName: "claude-sonnet-4.6",
            autonomyLevel: .manual,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s3StrategicCoach,
            budget: Budget(daily: 25, monthly: 750)
        )
        governancePreferredProject.autonomyLevel = .manual
        governancePreferredProject.currentModel = ModelInfo(
            id: "governance-preferred",
            name: "governance-preferred",
            displayName: "governance-preferred",
            type: .hubPaid,
            capability: .advanced,
            speed: .medium,
            costPerMillionTokens: 3.0,
            memorySize: nil,
            suitableFor: ["critical"],
            badge: nil,
            badgeColor: nil
        )

        let misleadingLegacyProject = ProjectModel(
            name: "LegacyShadowOnly",
            taskDescription: "Critical lanes",
            modelName: "claude-sonnet-4.6",
            autonomyLevel: .fullAuto,
            executionTier: .a1Plan,
            supervisorInterventionTier: .s1MilestoneReview,
            budget: Budget(daily: 25, monthly: 750)
        )
        misleadingLegacyProject.autonomyLevel = .fullAuto
        misleadingLegacyProject.currentModel = governancePreferredProject.currentModel

        let laneTask = DecomposedTask(
            description: "Handle privileged rollout",
            type: .deployment,
            complexity: .complex,
            estimatedEffort: 7_200,
            priority: 9
        )
        let lanePlan = SupervisorLanePlan(
            laneID: "lane-governance-preferred",
            goal: laneTask.description,
            dependsOn: [],
            riskTier: .high,
            budgetClass: .premium,
            createChildProject: false,
            expectedArtifacts: ["release_plan"],
            dodChecklist: ["rollback_ready"],
            source: .inferred,
            metadata: [:],
            task: laneTask
        )
        let lane = MaterializedLane(
            plan: lanePlan,
            mode: .softSplit,
            task: laneTask,
            targetProject: nil,
            lineageOperations: [],
            decisionReasons: ["test"],
            explain: "test lane"
        )

        let allocator = LaneAllocator()
        let result = allocator.allocate(
            lanes: [lane],
            projects: [misleadingLegacyProject, governancePreferredProject]
        )

        let assignment = try #require(result.assignments.first)
        #expect(assignment.project.id == governancePreferredProject.id)
    }

    @MainActor
    @Test
    func laneAllocatorSkillProfileRejectsUnreliableHighRiskLane() throws {
        let unstableProject = ProjectModel(
            name: "Unstable",
            taskDescription: "Handles release and deployment",
            modelName: "claude-sonnet-4.6",
            autonomyLevel: .semiAuto,
            budget: Budget(daily: 30, monthly: 900)
        )
        unstableProject.currentModel = ModelInfo(
            id: "unstable-model",
            name: "unstable-model",
            displayName: "unstable-model",
            type: .hubPaid,
            capability: .advanced,
            speed: .medium,
            costPerMillionTokens: 3.0,
            memorySize: nil,
            suitableFor: ["deployment", "release"],
            badge: nil,
            badgeColor: nil
        )

        unstableProject.taskQueue = [
            historicalTask(status: .failed),
            historicalTask(status: .failed),
            historicalTask(status: .completed),
            historicalTask(status: .failed),
        ]

        var laneTask = DecomposedTask(
            description: "Deploy signed skill bundle",
            type: .deployment,
            complexity: .complex,
            estimatedEffort: 7_200,
            priority: 10
        )
        laneTask.metadata["required_skills"] = "deployment,release"

        let lanePlan = SupervisorLanePlan(
            laneID: "lane-skill-risk",
            goal: laneTask.description,
            dependsOn: [],
            riskTier: .high,
            budgetClass: .premium,
            createChildProject: false,
            expectedArtifacts: ["release_manifest"],
            dodChecklist: ["rollback_validated"],
            source: .inferred,
            metadata: laneTask.metadata,
            task: laneTask
        )

        let lane = MaterializedLane(
            plan: lanePlan,
            mode: .softSplit,
            task: laneTask,
            targetProject: nil,
            lineageOperations: [],
            decisionReasons: ["test"],
            explain: "test lane"
        )

        let allocator = LaneAllocator()
        let result = allocator.allocate(lanes: [lane], projects: [unstableProject])

        #expect(result.assignments.isEmpty)
        #expect(result.blockedLanes.count == 1)
        #expect(result.blockedLanes[0].reason == "allocation_blocked")
        #expect(result.blockedLanes[0].explain.contains("reliability_history_insufficient"))
    }

    @MainActor
    @Test
    func hardSplitPinnedHighRiskLaneKeepsTrustedProfileAndCanAllocate() async throws {
        let rootProject = ProjectModel(
            name: "Root",
            taskDescription: "Root project",
            modelName: "claude-sonnet-4.6"
        )

        var highRiskTask = DecomposedTask(
            description: "Run privileged release checks",
            type: .deployment,
            complexity: .complex,
            estimatedEffort: 3_600,
            priority: 8
        )
        highRiskTask.metadata["lane_id"] = "lane-risk"
        highRiskTask.metadata["risk_tier"] = LaneRiskTier.high.rawValue
        highRiskTask.metadata["budget_class"] = LaneBudgetClass.premium.rawValue
        highRiskTask.metadata["create_child_project"] = "1"

        let materializer = ProjectMaterializer(runtimeHost: nil)
        let materialized = await materializer.materialize(
            tasks: [highRiskTask],
            rootProject: rootProject,
            splitPlanID: "split-risk"
        )
        let lane = try #require(materialized.lanes.first)
        #expect(lane.mode == .hardSplit)

        let childProject = try #require(lane.targetProject)
        #expect(childProject.currentModel.capability.rawValue >= ModelCapability.advanced.rawValue)
        #expect(childProject.autonomyLevel.rawValue >= AutonomyLevel.semiAuto.rawValue)
        #expect(childProject.executionTier == .a3DeliverAuto)
        #expect(childProject.supervisorInterventionTier == .s3StrategicCoach)

        let allocator = LaneAllocator()
        let allocation = allocator.allocate(lanes: [lane], projects: [rootProject, childProject])
        #expect(allocation.blockedLanes.isEmpty)

        let assignment = try #require(allocation.assignments.first)
        #expect(assignment.project.id == childProject.id)
    }

    @MainActor
    @Test
    func orchestratorLaneLaunchPreparesWorktreeForRegisteredGitProject() async throws {
        let fixture = ToolExecutorProjectFixture(name: "orchestrator-lane-worktree")
        defer { fixture.cleanup() }
        try seedCommittedRepo(at: fixture.root)

        let project = ProjectModel(
            name: "Registered Repo",
            taskDescription: "Code lane target",
            modelName: "claude-sonnet-4.6",
            registeredProjectBinding: ProjectRegistryBinding(
                projectId: "registered-repo",
                rootPath: fixture.root.path,
                displayName: "Registered Repo"
            ),
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            budget: Budget(daily: 50, monthly: 500)
        )
        project.priority = 10

        let runtimeHost = MultilaneRuntimeHostSpy(projects: [project])
        let orchestrator = SupervisorOrchestrator(runtimeHost: runtimeHost)

        var task = DecomposedTask(
            description: "Implement small code change",
            type: .development,
            complexity: .simple,
            estimatedEffort: 900,
            priority: 8
        )
        task.metadata["agent_mode"] = XTAgentMode.code.rawValue

        let lane = SplitLaneProposal(
            laneId: "lane-code",
            goal: task.description,
            dependsOn: [],
            riskTier: .low,
            budgetClass: .standard,
            createChildProject: false,
            expectedArtifacts: ["patch"],
            dodChecklist: ["diagnostics_green"],
            verificationContract: nil,
            estimatedEffortMs: 900_000,
            tokenBudget: 4_000,
            sourceTaskId: task.id,
            notes: []
        )
        let proposal = SplitProposal(
            splitPlanId: UUID(),
            rootProjectId: project.id,
            planVersion: 1,
            complexityScore: 12,
            lanes: [lane],
            recommendedConcurrency: 1,
            tokenBudgetTotal: lane.tokenBudget,
            estimatedWallTimeMs: lane.estimatedEffortMs,
            sourceTaskDescription: task.description,
            createdAt: Date()
        )
        let analysis = TaskAnalysis(
            originalDescription: task.description,
            keywords: ["code"],
            verbs: ["implement"],
            objects: ["change"],
            constraints: [],
            type: .development,
            complexity: .simple,
            estimatedEffort: task.estimatedEffort,
            requiredSkills: ["swift"],
            riskLevel: .low,
            suggestedSubtasks: [],
            potentialDependencies: []
        )
        let decomposition = DecompositionResult(
            rootTask: task,
            subtasks: [task],
            allTasks: [task],
            dependencyGraph: DependencyGraph(tasks: [task]),
            analysis: analysis
        )
        let buildResult = SplitProposalBuildResult(
            decomposition: decomposition,
            proposal: proposal,
            validation: SplitProposalValidationResult(issues: [])
        )

        _ = orchestrator.adoptPreparedSplitProposal(buildResult)
        let report = try #require(await orchestrator.executeActiveSplitProposal())

        #expect(report.launchedLaneIDs == ["lane-code"])
        #expect(report.worktreeStateRefs["lane-code"] == ".xterminal/lane-state/lane-code.json")
        #expect(report.worktreePaths["lane-code"] == ".xterminal/worktrees/lane-code")

        let manager = LaneWorktreeManager(projectRoot: fixture.root)
        let state = try #require(try manager.loadState(laneID: "lane-code"))
        #expect(state.mode == .code)
        #expect(state.sessionID == proposal.splitPlanId.uuidString.lowercased())
        #expect(state.worktreePath == ".xterminal/worktrees/lane-code")

        let monitoredTask = try #require(orchestrator.monitor.taskStates.values.first?.task)
        #expect(monitoredTask.metadata["lane_worktree_path"] == ".xterminal/worktrees/lane-code")
        #expect(monitoredTask.metadata["lane_worktree_state_ref"] == ".xterminal/lane-state/lane-code.json")
        #expect(monitoredTask.metadata["agent_mode"] == XTAgentMode.code.rawValue)
    }

    @MainActor
    @Test
    func orchestratorMergebackSelectedWorktreeLaneAppliesWinnerAndRecordsAudit() async throws {
        let fixture = ToolExecutorProjectFixture(name: "orchestrator-lane-mergeback")
        defer { fixture.cleanup() }
        try seedCommittedSwiftPackageRepo(at: fixture.root)

        let project = ProjectModel(
            name: "Registered Repo",
            taskDescription: "Code lane target",
            modelName: "claude-sonnet-4.6",
            registeredProjectBinding: ProjectRegistryBinding(
                projectId: "registered-repo",
                rootPath: fixture.root.path,
                displayName: "Registered Repo"
            ),
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            budget: Budget(daily: 50, monthly: 500)
        )
        project.priority = 10

        let runtimeHost = MultilaneRuntimeHostSpy(projects: [project])
        let orchestrator = SupervisorOrchestrator(runtimeHost: runtimeHost)

        var task = DecomposedTask(
            description: "Implement winner code change",
            type: .development,
            complexity: .simple,
            estimatedEffort: 900,
            priority: 8
        )
        task.metadata["agent_mode"] = XTAgentMode.code.rawValue

        let lane = SplitLaneProposal(
            laneId: "lane-code",
            goal: task.description,
            dependsOn: [],
            riskTier: .low,
            budgetClass: .standard,
            createChildProject: false,
            expectedArtifacts: ["patch"],
            dodChecklist: ["diagnostics_green"],
            verificationContract: nil,
            estimatedEffortMs: 900_000,
            tokenBudget: 4_000,
            sourceTaskId: task.id,
            notes: []
        )
        let proposal = SplitProposal(
            splitPlanId: UUID(),
            rootProjectId: project.id,
            planVersion: 1,
            complexityScore: 12,
            lanes: [lane],
            recommendedConcurrency: 1,
            tokenBudgetTotal: lane.tokenBudget,
            estimatedWallTimeMs: lane.estimatedEffortMs,
            sourceTaskDescription: task.description,
            createdAt: Date()
        )
        let analysis = TaskAnalysis(
            originalDescription: task.description,
            keywords: ["code"],
            verbs: ["implement"],
            objects: ["change"],
            constraints: [],
            type: .development,
            complexity: .simple,
            estimatedEffort: task.estimatedEffort,
            requiredSkills: ["swift"],
            riskLevel: .low,
            suggestedSubtasks: [],
            potentialDependencies: []
        )
        let decomposition = DecompositionResult(
            rootTask: task,
            subtasks: [task],
            allTasks: [task],
            dependencyGraph: DependencyGraph(tasks: [task]),
            analysis: analysis
        )
        let buildResult = SplitProposalBuildResult(
            decomposition: decomposition,
            proposal: proposal,
            validation: SplitProposalValidationResult(issues: [])
        )

        _ = orchestrator.adoptPreparedSplitProposal(buildResult)
        _ = try #require(await orchestrator.executeActiveSplitProposal())

        let manager = LaneWorktreeManager(projectRoot: fixture.root)
        let state = try #require(try manager.loadState(laneID: "lane-code"))
        let worktreeURL = fixture.root.appendingPathComponent(state.worktreePath, isDirectory: true)
        try """
        print("winner")
        """.write(
            to: worktreeURL.appendingPathComponent("Sources/GateFixture/main.swift"),
            atomically: true,
            encoding: .utf8
        )

        let taskID = try #require(orchestrator.monitor.taskStates.values.first?.task.id)
        await orchestrator.monitor.updateState(taskID, status: .completed, note: "ready_for_mergeback")

        let missingOutputReport = await orchestrator.mergebackSelectedWorktreeLane(
            laneID: "lane-code",
            strictIncidentCoverage: false,
            timeoutSec: 120
        )
        #expect(missingOutputReport?.pass == false)
        #expect(missingOutputReport?.blockedReason == "coder_lane_output_missing")
        #expect(orchestrator.lastLaneWinnerScoreReport?.recommendedLaneID == "")
        #expect(orchestrator.lastLaneWinnerScoreReport?.candidates.first?.blockers.contains("coder_lane_output_missing") == true)

        let output = try orchestrator.recordCoderLaneOutput(
            laneID: "lane-code",
            summary: "Implemented winner code change.",
            artifactRefs: ["local://lane-code/patch"],
            auditRef: "audit-coder-lane-output-1"
        )
        #expect(output.role == "coder")
        #expect(output.changedFiles == ["Sources/GateFixture/main.swift"])
        #expect(output.outputRef == ".xterminal/lane-output/lane-code.json")
        #expect(orchestrator.coderLaneOutputs["lane-code"] == output)

        let missingReviewReport = await orchestrator.mergebackSelectedWorktreeLane(
            laneID: "lane-code",
            strictIncidentCoverage: false,
            timeoutSec: 120
        )
        #expect(missingReviewReport?.pass == false)
        #expect(missingReviewReport?.blockedReason == "reviewer_verdict_missing")
        #expect(orchestrator.lastLaneWinnerScoreReport?.candidates.first?.blockers.contains("reviewer_verdict_missing") == true)

        let blockedReview = try orchestrator.recordLaneReviewReport(
            laneID: "lane-code",
            verdict: .changesRequested,
            reviewerID: "reviewer-1",
            summary: "Needs a final approval before mergeback.",
            issues: ["approval_not_final"],
            recommendedActions: ["rerun review after confirming diagnostics"],
            residualRisks: ["none"],
            evidenceRefs: [output.outputRef],
            auditRef: "audit-review-lane-code-blocked"
        )
        #expect(blockedReview.verdict == .changesRequested)
        let blockedReviewReport = await orchestrator.mergebackSelectedWorktreeLane(
            laneID: "lane-code",
            strictIncidentCoverage: false,
            timeoutSec: 120
        )
        #expect(blockedReviewReport?.pass == false)
        #expect(blockedReviewReport?.blockedReason == "reviewer_verdict_not_approved")
        #expect(orchestrator.lastLaneWinnerScoreReport?.recommendedLaneID == "")
        #expect(orchestrator.lastLaneWinnerScoreReport?.candidates.first?.blockers.contains("reviewer_changes_requested") == true)

        let review = try orchestrator.recordLaneReviewReport(
            laneID: "lane-code",
            verdict: .approved,
            reviewerID: "reviewer-1",
            summary: "Diff and diagnostics are acceptable for mergeback.",
            issues: [],
            recommendedActions: ["mergeback"],
            residualRisks: ["low"],
            evidenceRefs: [output.outputRef, output.diffRef],
            auditRef: "audit-review-lane-code-approved"
        )
        #expect(review.role == "reviewer")
        #expect(review.verdict == .approved)
        #expect(review.coderOutputRef == output.outputRef)
        #expect(review.reviewRef == ".xterminal/lane-review/lane-code.json")
        #expect(orchestrator.laneReviewReports["lane-code"] == review)

        let overrideScore = try #require(
            orchestrator.overrideLaneWinnerSelection(
                laneID: "lane-code",
                reason: "test_manual_lane_selection"
            )
        )
        #expect(orchestrator.laneWinnerSelectionOverride?.laneID == "lane-code")
        #expect(overrideScore.recommendedLaneID == "lane-code")
        #expect(overrideScore.selectionSource == "manual_override")
        #expect(overrideScore.manualOverrideLaneID == "lane-code")

        let maybeReport = await orchestrator.mergebackSelectedWorktreeLane(
            strictIncidentCoverage: false,
            timeoutSec: 120
        )
        let report = try #require(maybeReport)

        #expect(report.pass)
        #expect(report.changedFiles == ["Sources/GateFixture/main.swift"])
        #expect(report.reportRef == ".xterminal/mergeback/lane-code.json")
        #expect(orchestrator.lastLaneWorktreeMergebackReport == report)
        #expect(orchestrator.lastMergebackGateReport?.pass == true)
        #expect(orchestrator.lastMergebackQualityReport?.runAudits.first?.laneID == "lane-code")
        let scoreReport = try #require(orchestrator.lastLaneWinnerScoreReport)
        #expect(scoreReport.recommendedLaneID == "lane-code")
        #expect(scoreReport.eligibleCount == 1)
        #expect(scoreReport.candidates.first?.selected == true)
        #expect(scoreReport.candidates.first?.reviewVerdict == "approved")
        #expect(scoreReport.selectionSource == "manual_override")
        #expect(scoreReport.manualOverrideLaneID == "lane-code")

        let mergedSource = try String(
            contentsOf: fixture.root.appendingPathComponent("Sources/GateFixture/main.swift"),
            encoding: .utf8
        )
        #expect(mergedSource.contains("winner"))

        let reportURL = fixture.root.appendingPathComponent(report.reportRef)
        let persisted = try JSONDecoder().decode(
            LaneWorktreeMergebackReport.self,
            from: Data(contentsOf: reportURL)
        )
        #expect(persisted == report)
        let persistedOutput = try JSONDecoder().decode(
            CoderLaneOutput.self,
            from: Data(contentsOf: fixture.root.appendingPathComponent(output.outputRef))
        )
        #expect(persistedOutput == output)
        let persistedReview = try JSONDecoder().decode(
            LaneReviewReport.self,
            from: Data(contentsOf: fixture.root.appendingPathComponent(review.reviewRef))
        )
        #expect(persistedReview == review)
        let persistedScore = try JSONDecoder().decode(
            LaneWinnerScoreReport.self,
            from: Data(contentsOf: fixture.root.appendingPathComponent(scoreReport.reportRef))
        )
        #expect(persistedScore == scoreReport)
        #expect(orchestrator.splitAuditTrail.contains(where: {
            $0.detail.contains("worktree_mergeback lane=lane-code pass=true")
                && $0.payload["reviewer_verdict"] == "approved"
                && $0.payload["coder_lane_output_ref"] == output.outputRef
        }))
        #expect(orchestrator.splitAuditTrail.contains(where: {
            $0.detail.contains("lane_winner_score recommended=lane-code")
                && $0.payload["lane_winner_score_ref"] == scoreReport.reportRef
        }))
        #expect(orchestrator.splitAuditTrail.contains(where: {
            $0.detail.contains("lane_winner_manual_override lane=lane-code")
                && $0.payload["hub_first_note"] == "local_selection_only_mergeback_still_requires_reviewer_gate_hub_policy"
        }))
    }

    @MainActor
    @Test
    func supervisorOrchestratorTreatsA4ProjectAsExclusiveEvenIfLegacyAutonomyShadowIsManual() {
        let supervisor = SupervisorModel()
        let orchestrator = supervisor.orchestrator!
        let project = ProjectModel(
            name: "Exclusive A4",
            taskDescription: "write docs",
            modelName: "claude-sonnet-4.6",
            autonomyLevel: .manual,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s3StrategicCoach
        )
        project.autonomyLevel = .manual

        let plan = orchestrator.allocateResources([project])

        #expect(plan.exclusiveProjects.count == 1)
        #expect(plan.parallelProjects.isEmpty)
    }

    @MainActor
    @Test
    func heartbeatControllerDetectsBlockedStalledAndFailed() {
        let controller = LaneHeartbeatController(stallTimeoutMs: 100)
        let taskID = UUID()

        controller.registerLane(
            laneID: "lane-1",
            taskId: taskID,
            projectId: UUID(),
            agentProfile: "trusted_high",
            initialStatus: .running
        )

        controller.recordHeartbeat(
            laneID: "lane-1",
            taskId: taskID,
            projectId: nil,
            agentProfile: "trusted_high",
            status: .running,
            blockedReason: .grantPending,
            recommendation: "notify_user",
            note: "waiting grant"
        )

        let blockedTransitions = controller.inspect(now: Date())
        #expect(blockedTransitions.contains(where: { $0.to == .blocked }))
        #expect(controller.healthSummary().blocked == 1)

        let stalledTransitions = controller.inspect(now: Date().addingTimeInterval(0.7))
        #expect(stalledTransitions.contains(where: { $0.to == .stalled }))

        controller.markFailed(laneID: "lane-1", note: "runtime error", blockedReason: .runtimeError)
        let snapshot = controller.snapshot()
        #expect(snapshot["lane-1"]?.status == .failed)
        #expect(controller.healthSummary().failed == 1)
    }

    @MainActor
    @Test
    func mergebackGateProducesRollbackPointsAndPassesStrictChecks() {
        let laneA = makeMaterializedLane(
            laneID: "lane-2",
            riskTier: .high,
            budgetClass: .premium,
            requiredSkills: "deployment,release"
        )
        let laneB = makeMaterializedLane(
            laneID: "lane-3",
            riskTier: .medium,
            budgetClass: .balanced,
            requiredSkills: "testing"
        )

        var laneStateA = LaneRuntimeState(
            laneID: "lane-2",
            taskId: laneA.task.id,
            projectId: UUID(),
            agentProfile: "trusted_high_skill_deployment",
            status: .completed,
            blockedReason: nil,
            nextActionRecommendation: "mergeback"
        )
        laneStateA.heartbeatSeq = 8
        laneStateA.updatedAtMs = 1_730_000_200

        var laneStateB = LaneRuntimeState(
            laneID: "lane-3",
            taskId: laneB.task.id,
            projectId: UUID(),
            agentProfile: "balanced_general_skill_testing",
            status: .completed,
            blockedReason: nil,
            nextActionRecommendation: "mergeback"
        )
        laneStateB.heartbeatSeq = 6
        laneStateB.updatedAtMs = 1_730_000_300

        let contracts = [buildPromptContract(laneID: "lane-2"), buildPromptContract(laneID: "lane-3")]
        let promptResult = PromptCompilationResult(
            splitPlanId: UUID(),
            expectedLaneCount: 2,
            contracts: contracts,
            lintResult: PromptLintResult(issues: []),
            status: .ready,
            compiledAt: Date(timeIntervalSince1970: 1_730_000_100)
        )
        let launchReport = LaneLaunchReport(
            splitPlanID: "split-mergeback-pass",
            launchedLaneIDs: ["lane-2", "lane-3"],
            blockedLaneReasons: [:],
            deferredLaneIDs: [],
            concurrencyLimit: 2,
            reproducibilitySignature: "assign:[lane-2->projectA|lane-3->projectB]::blocked:[]"
        )
        let incidents = [
            makeHandledIncident(
                laneID: "lane-2",
                incidentCode: LaneBlockedReason.grantPending.rawValue,
                action: .notifyUser,
                latencyMs: 900
            ),
            makeHandledIncident(
                laneID: "lane-3",
                incidentCode: LaneBlockedReason.awaitingInstruction.rawValue,
                action: .replan,
                latencyMs: 600
            ),
            makeHandledIncident(
                laneID: "lane-3",
                incidentCode: LaneBlockedReason.runtimeError.rawValue,
                action: .autoRetry,
                latencyMs: 1_100
            ),
        ]

        let evaluator = LaneMergebackGateEvaluator()
        let report = evaluator.evaluate(
            splitPlanID: "split-mergeback-pass",
            lanes: [laneA, laneB],
            laneStates: ["lane-2": laneStateA, "lane-3": laneStateB],
            incidents: incidents,
            promptCompilationResult: promptResult,
            launchReport: launchReport,
            strictIncidentCoverage: true,
            now: Date(timeIntervalSince1970: 1_730_000_400)
        )

        #expect(report.pass)
        #expect(report.rollbackPoints.count == 2)
        #expect(report.kpi.supervisorActionLatencyP95Ms <= 1_500)
        #expect(report.kpi.highRiskLaneWithoutGrant == 0)
        #expect(report.assertions.contains(where: { $0.id == "mergeback_rollback_points_ready" && $0.ok }))
    }

    @MainActor
    @Test
    func mergebackGateFailsClosedWithoutCompletedStablePoint() {
        let lane = makeMaterializedLane(
            laneID: "lane-4",
            riskTier: .high,
            budgetClass: .premium,
            requiredSkills: "deployment"
        )
        let failedLaneState = LaneRuntimeState(
            laneID: "lane-4",
            taskId: lane.task.id,
            projectId: UUID(),
            agentProfile: "trusted_high_skill_deployment",
            status: .failed,
            blockedReason: .runtimeError,
            nextActionRecommendation: "pause_lane"
        )
        let promptResult = PromptCompilationResult(
            splitPlanId: UUID(),
            expectedLaneCount: 1,
            contracts: [buildPromptContract(laneID: "lane-4")],
            lintResult: PromptLintResult(issues: []),
            status: .ready,
            compiledAt: Date(timeIntervalSince1970: 1_730_000_100)
        )

        let evaluator = LaneMergebackGateEvaluator()
        let report = evaluator.evaluate(
            splitPlanID: "split-mergeback-fail",
            lanes: [lane],
            laneStates: ["lane-4": failedLaneState],
            incidents: [],
            promptCompilationResult: promptResult,
            launchReport: nil,
            strictIncidentCoverage: false,
            now: Date(timeIntervalSince1970: 1_730_000_450)
        )

        #expect(report.pass == false)
        #expect(report.assertions.contains(where: { $0.id == "mergeback_only_completed_lanes" && $0.ok == false }))
        #expect(report.assertions.contains(where: { $0.id == "mergeback_rollback_points_ready" && $0.ok == false }))
    }

    private func historicalTask(status: DecomposedTaskStatus) -> DecomposedTask {
        var task = DecomposedTask(
            description: "Historical deployment task",
            type: .deployment,
            complexity: .moderate,
            estimatedEffort: 1_800,
            priority: 5
        )
        task.status = status
        task.metadata["required_skills"] = "deployment,release"
        return task
    }

    private func makeMaterializedLane(
        laneID: String,
        riskTier: LaneRiskTier,
        budgetClass: LaneBudgetClass,
        requiredSkills: String
    ) -> MaterializedLane {
        var task = DecomposedTask(
            description: "Task for \(laneID)",
            type: .deployment,
            complexity: .complex,
            estimatedEffort: 1_800,
            priority: 8
        )
        task.metadata["lane_id"] = laneID
        task.metadata["required_skills"] = requiredSkills

        let plan = SupervisorLanePlan(
            laneID: laneID,
            goal: task.description,
            dependsOn: [],
            riskTier: riskTier,
            budgetClass: budgetClass,
            createChildProject: false,
            expectedArtifacts: ["artifact-\(laneID)"],
            dodChecklist: ["rollback_validated"],
            source: .inferred,
            metadata: task.metadata,
            task: task
        )

        return MaterializedLane(
            plan: plan,
            mode: .softSplit,
            task: task,
            targetProject: nil,
            lineageOperations: [],
            decisionReasons: ["test"],
            explain: "test lane"
        )
    }

    private func buildPromptContract(laneID: String) -> PromptContract {
        PromptContract(
            laneId: laneID,
            goal: "goal",
            boundaries: ["boundary"],
            inputs: ["input"],
            outputs: ["output"],
            dodChecklist: ["dod"],
            riskBoundaries: ["grant required"],
            prohibitions: ["no bypass"],
            rollbackPoints: ["restore snapshot \(laneID)"],
            refusalSemantics: ["refuse if missing grant"],
            compiledPrompt: "compiled",
            tokenBudget: 1000
        )
    }

    private func makeHandledIncident(
        laneID: String,
        incidentCode: String,
        action: SupervisorIncidentAction,
        latencyMs: Int64
    ) -> SupervisorLaneIncident {
        let now = Int64(1_730_000_000)
        return SupervisorLaneIncident(
            id: "incident-\(UUID().uuidString.lowercased())",
            laneID: laneID,
            taskID: UUID(),
            projectID: UUID(),
            incidentCode: incidentCode,
            eventType: "supervisor.incident.\(incidentCode).handled",
            denyCode: incidentCode,
            severity: .medium,
            category: .runtime,
            autoResolvable: action == .autoRetry || action == .autoGrant || action == .replan,
            requiresUserAck: action == .notifyUser,
            proposedAction: action,
            detectedAtMs: now,
            handledAtMs: now + latencyMs,
            takeoverLatencyMs: latencyMs,
            auditRef: "audit-\(UUID().uuidString.lowercased())",
            detail: "test",
            status: .handled
        )
    }

    private func seedCommittedRepo(at root: URL) throws {
        try requireGitSuccess(try runGit(["init", "-q"], cwd: root), "git init")
        try requireGitSuccess(try runGit(["config", "user.email", "xt-tests@example.com"], cwd: root), "git config user.email")
        try requireGitSuccess(try runGit(["config", "user.name", "XT Tests"], cwd: root), "git config user.name")
        try "old\n".write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try requireGitSuccess(try runGit(["add", "README.md"], cwd: root), "git add")
        try requireGitSuccess(try runGit(["commit", "-q", "-m", "base"], cwd: root), "git commit")
    }

    private func seedCommittedSwiftPackageRepo(at root: URL) throws {
        try requireGitSuccess(try runGit(["init", "-q"], cwd: root), "git init")
        try requireGitSuccess(try runGit(["config", "user.email", "xt-tests@example.com"], cwd: root), "git config user.email")
        try requireGitSuccess(try runGit(["config", "user.name", "XT Tests"], cwd: root), "git config user.name")
        try """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "GateFixture",
            targets: [
                .executableTarget(name: "GateFixture", path: "Sources/GateFixture")
            ]
        )
        """.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        let sourceDir = root.appendingPathComponent("Sources/GateFixture", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try """
        print("ok")
        """.write(
            to: sourceDir.appendingPathComponent("main.swift"),
            atomically: true,
            encoding: .utf8
        )
        try requireGitSuccess(try runGit(["add", "."], cwd: root), "git add")
        try requireGitSuccess(try runGit(["commit", "-q", "-m", "base"], cwd: root), "git commit")
    }

    private func runGit(_ args: [String], cwd: URL) throws -> ProcessResult {
        try ProcessCapture.run("/usr/bin/git", args, cwd: cwd)
    }

    private func requireGitSuccess(_ result: ProcessResult, _ operation: String) throws {
        guard result.exitCode == 0 else {
            throw NSError(
                domain: "SupervisorMultilaneFlowTests",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: "\(operation) failed\n\(result.combined)"]
            )
        }
    }
}

@MainActor
private final class MultilaneRuntimeHostSpy: SupervisorProjectRuntimeHosting {
    var activeProjects: [ProjectModel]
    var taskAssignerForRuntime: TaskAssigner? = nil

    init(projects: [ProjectModel]) {
        self.activeProjects = projects
    }

    func addActiveProjectIfNeeded(_ project: ProjectModel) {
        guard !activeProjects.contains(where: { $0.id == project.id }) else { return }
        activeProjects.append(project)
    }

    func onProjectCreated(_ project: ProjectModel) async {}
    func onProjectDeleted(_ project: ProjectModel) async {}
    func onProjectStarted(_ project: ProjectModel) async {}
    func onProjectPaused(_ project: ProjectModel) async {}
    func onProjectResumed(_ project: ProjectModel) async {}
    func onProjectCompleted(_ project: ProjectModel) async {}
    func onProjectArchived(_ project: ProjectModel) async {}
    func onProjectExecutionStarted(_ project: ProjectModel, model: ModelInfo) async {}
    func suggestModelUpgrade(for project: ProjectModel) async {}
}
