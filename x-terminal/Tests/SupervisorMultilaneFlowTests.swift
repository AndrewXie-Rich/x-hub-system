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

        let materializer = ProjectMaterializer(supervisor: nil)
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

        let materializer = ProjectMaterializer(supervisor: nil)
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

        let allocator = LaneAllocator()
        let allocation = allocator.allocate(lanes: [lane], projects: [rootProject, childProject])
        #expect(allocation.blockedLanes.isEmpty)

        let assignment = try #require(allocation.assignments.first)
        #expect(assignment.project.id == childProject.id)
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
}
