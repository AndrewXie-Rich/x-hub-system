import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorIntakeAcceptanceTests {

    @Test
    func projectIntakeWorkflowExtractsManifestAndBootstrapBinding() {
        let engine = SupervisorIntakeAcceptanceEngine()
        let projectID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        let workflow = engine.buildProjectIntakeWorkflow(
            projectID: projectID,
            documents: makeHappyPathDocuments(),
            splitProposal: makeSplitProposal(projectID: projectID),
            now: Date(timeIntervalSince1970: 1_772_000_000)
        )

        #expect(workflow.freezeGate.decision == .pass)
        #expect(workflow.status == "intake_frozen_and_bootstrap_ready")
        #expect(workflow.extractorEvidence.requiredFieldCoverage == 1.0)
        #expect(workflow.manifest.projectGoal == "Ship a supervisor intake and acceptance vertical slice")
        #expect(workflow.manifest.touchPolicy == .criticalTouch)
        #expect(workflow.manifest.acceptanceMode == .releaseCandidate)
        #expect(workflow.manifest.poolPlan.count == 2)
        #expect(workflow.bootstrapBinding.bootstrapReady)
        #expect(workflow.bootstrapBinding.laneBindings.count == 2)
        #expect(workflow.bootstrapBinding.promptPackRefs.count == 2)
        #expect(workflow.minimalGaps.isEmpty)
    }

    @Test
    func projectIntakeFailsClosedWhenRequiredScopeIsMissing() {
        let engine = SupervisorIntakeAcceptanceEngine()
        let projectID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let docs = [
            SupervisorIntakeSourceDocument(
                ref: "docs/intake-missing.md",
                kind: .markdown,
                contents: """
                project_goal: Validate missing scope handling
                constraints: fail closed, machine readable evidence
                acceptance_targets:
                - gate_green
                touch_policy: guided_touch
                risk_level: medium
                requires_user_authorization: true
                acceptance_mode: internal_beta
                """
            )
        ]

        let workflow = engine.buildProjectIntakeWorkflow(
            projectID: projectID,
            documents: docs,
            splitProposal: makeSplitProposal(projectID: projectID),
            now: Date(timeIntervalSince1970: 1_772_000_020)
        )

        #expect(workflow.freezeGate.decision == .failClosed)
        #expect(workflow.freezeGate.denyCode == "intake_missing_required_field")
        #expect(workflow.status == "fail_closed_needs_user_decision")
        #expect(workflow.minimalGaps.contains("in_scope"))
        #expect(workflow.minimalGaps.contains("out_of_scope"))
        #expect(workflow.bootstrapBinding.bootstrapReady == false)
    }

    @Test
    func acceptanceWorkflowAcceptsGreenExecutionMonitorSnapshot() async throws {
        let engine = SupervisorIntakeAcceptanceEngine()
        let monitor = ExecutionMonitor()
        let project = ProjectModel(
            id: UUID(uuidString: "99999999-aaaa-bbbb-cccc-dddddddddddd")!,
            name: "XT-W3-21/22",
            taskDescription: "acceptance monitor export",
            modelName: "claude-sonnet-4.6"
        )

        let taskA = makeCompletionTask(
            taskID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            laneID: "lane-intake",
            taskRef: "XT-W3-21",
            gateVector: "XT-MP-G0:PASS|XT-MP-G1:PASS|XT-MP-G3:PASS",
            evidenceRefs: "build/reports/xt_w3_21_project_intake_manifest.v1.json|build/reports/xt_w3_21_c_bootstrap_binding_evidence.v1.json",
            rollbackRef: "board://rollback/intake-manifest-v1",
            riskSummary: "low: manifest can be regenerated deterministically"
        )
        let taskB = makeCompletionTask(
            taskID: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            laneID: "lane-acceptance",
            taskRef: "XT-W3-22",
            gateVector: "XT-MP-G5:PASS",
            evidenceRefs: "build/reports/xt_w3_22_acceptance_pack.v1.json|build/reports/xt_w3_22_c_delivery_package_evidence.v1.json",
            rollbackRef: "board://rollback/acceptance-pack-v1",
            riskSummary: "medium: watch evidence drift after downstream edits"
        )

        await monitor.startMonitoring(taskA, in: project)
        await monitor.updateState(taskA.id, status: .completed, note: "intake_done")
        await monitor.startMonitoring(taskB, in: project)
        await monitor.updateState(taskB.id, status: .completed, note: "acceptance_done")

        let input = monitor.buildAcceptanceAggregationInput(
            projectID: project.id,
            userSummaryRef: "board://delivery/summary/xt-w3-22-demo"
        )
        let workflow = engine.buildAcceptanceWorkflow(
            input: input,
            participationMode: .guidedTouch,
            now: Date(timeIntervalSince1970: 1_772_000_040)
        )

        #expect(workflow.validationReport.pass)
        #expect(workflow.acceptancePack.deliveryStatus == .accepted)
        #expect(workflow.acceptancePack.completedTasks == ["XT-W3-21", "XT-W3-22"])
        #expect(workflow.acceptancePack.evidenceRefs.count == 4)
        #expect(workflow.deliveryPackage.notificationAttempt.status == .sent)
        #expect(workflow.deliveryPackage.userSummary.contains("delivery_status=accepted"))
    }

    @Test
    func acceptanceWorkflowFailsClosedWhenEvidenceOrRollbackIsMissing() {
        let engine = SupervisorIntakeAcceptanceEngine()
        let input = AcceptanceAggregationInput(
            projectID: "xt-w3-22-missing-evidence",
            completedTasks: ["XT-W3-22"],
            gateReadings: [AcceptanceGateReading(gateID: "XT-MP-G5", status: .pass)],
            riskSummary: [],
            rollbackPoints: [],
            evidenceRefs: [],
            userSummaryRef: "",
            auditRef: "audit-missing-evidence"
        )

        let workflow = engine.buildAcceptanceWorkflow(
            input: input,
            participationMode: .guidedTouch,
            now: Date(timeIntervalSince1970: 1_772_000_060)
        )

        #expect(workflow.validationReport.pass == false)
        #expect(workflow.acceptancePack.deliveryStatus == .insufficientEvidence)
        #expect(workflow.minimalGaps.contains("missing_evidence_refs"))
        #expect(workflow.minimalGaps.contains("missing_rollback_points"))
        #expect(workflow.deliveryPackage.notificationAttempt.status == .blocked)
    }

    @Test
    func runtimeCaptureWritesEvidenceFilesWhenRequested() async throws {
        guard let captureDir = ProcessInfo.processInfo.environment["XT_W3_21_22_CAPTURE_DIR"], !captureDir.isEmpty else {
            return
        }

        let engine = SupervisorIntakeAcceptanceEngine()
        let projectID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let intakeWorkflow = engine.buildProjectIntakeWorkflow(
            projectID: projectID,
            documents: makeHappyPathDocuments(),
            splitProposal: makeSplitProposal(projectID: projectID),
            now: Date(timeIntervalSince1970: 1_772_000_000)
        )

        let monitor = ExecutionMonitor()
        let project = ProjectModel(
            id: projectID,
            name: "Capture Project",
            taskDescription: "capture evidence",
            modelName: "claude-sonnet-4.6"
        )
        let taskA = makeCompletionTask(
            taskID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            laneID: "lane-intake",
            taskRef: "XT-W3-21",
            gateVector: "XT-MP-G0:PASS|XT-MP-G1:PASS|XT-MP-G3:PASS",
            evidenceRefs: "build/reports/xt_w3_21_project_intake_manifest.v1.json|build/reports/xt_w3_21_c_bootstrap_binding_evidence.v1.json",
            rollbackRef: "board://rollback/intake-manifest-v1",
            riskSummary: "low: manifest can be regenerated deterministically"
        )
        let taskB = makeCompletionTask(
            taskID: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            laneID: "lane-acceptance",
            taskRef: "XT-W3-22",
            gateVector: "XT-MP-G5:PASS",
            evidenceRefs: "build/reports/xt_w3_22_acceptance_pack.v1.json|build/reports/xt_w3_22_c_delivery_package_evidence.v1.json",
            rollbackRef: "board://rollback/acceptance-pack-v1",
            riskSummary: "medium: watch evidence drift after downstream edits"
        )

        await monitor.startMonitoring(taskA, in: project)
        await monitor.updateState(taskA.id, status: .completed, note: "capture_intake_done")
        await monitor.startMonitoring(taskB, in: project)
        await monitor.updateState(taskB.id, status: .completed, note: "capture_acceptance_done")

        let acceptanceInput = monitor.buildAcceptanceAggregationInput(
            projectID: project.id,
            userSummaryRef: "board://delivery/summary/xt-w3-22-capture"
        )
        let acceptanceWorkflow = engine.buildAcceptanceWorkflow(
            input: acceptanceInput,
            participationMode: .guidedTouch,
            now: Date(timeIntervalSince1970: 1_772_000_040)
        )

        try writeJSON(intakeWorkflow.extractorEvidence, to: URL(fileURLWithPath: captureDir).appendingPathComponent("xt_w3_21_a_intake_extractor_evidence.v1.json"))
        try writeJSON(intakeWorkflow.freezeGate, to: URL(fileURLWithPath: captureDir).appendingPathComponent("xt_w3_21_b_intake_freeze_evidence.v1.json"))
        try writeJSON(intakeWorkflow.bootstrapBinding, to: URL(fileURLWithPath: captureDir).appendingPathComponent("xt_w3_21_c_bootstrap_binding_evidence.v1.json"))
        try writeJSON(intakeWorkflow.manifest, to: URL(fileURLWithPath: captureDir).appendingPathComponent("xt_w3_21_project_intake_manifest.v1.json"))

        try writeJSON(acceptanceWorkflow.aggregationEvidence, to: URL(fileURLWithPath: captureDir).appendingPathComponent("xt_w3_22_a_acceptance_aggregator_evidence.v1.json"))
        try writeJSON(acceptanceWorkflow.validationReport, to: URL(fileURLWithPath: captureDir).appendingPathComponent("xt_w3_22_b_acceptance_validation_evidence.v1.json"))
        try writeJSON(acceptanceWorkflow.deliveryPackage, to: URL(fileURLWithPath: captureDir).appendingPathComponent("xt_w3_22_c_delivery_package_evidence.v1.json"))
        try writeJSON(acceptanceWorkflow.acceptancePack, to: URL(fileURLWithPath: captureDir).appendingPathComponent("xt_w3_22_acceptance_pack.v1.json"))

        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: captureDir).appendingPathComponent("xt_w3_21_project_intake_manifest.v1.json").path))
        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: captureDir).appendingPathComponent("xt_w3_22_acceptance_pack.v1.json").path))
    }

    private func makeHappyPathDocuments() -> [SupervisorIntakeSourceDocument] {
        [
            SupervisorIntakeSourceDocument(
                ref: "docs/intake.md",
                kind: .markdown,
                contents: """
                project_goal: Ship a supervisor intake and acceptance vertical slice
                touch_policy: critical_touch
                innovation_level: L2
                suggestion_governance: hybrid
                risk_level: medium
                requires_user_authorization: true
                acceptance_mode: release_candidate
                token_budget_tier: balanced
                paid_ai_allowed: true

                ## in_scope
                - compile project intake manifest from source bundle refs
                - bind split proposal lanes into prompt-pack refs

                ## out_of_scope
                - direct production deploy
                - unrelated UX polish

                ## constraints
                - fail closed on missing authorization boundaries
                - keep evidence machine readable

                ## acceptance_targets
                - gate_green
                - rollback_ready
                - evidence_complete
                """
            ),
            SupervisorIntakeSourceDocument(
                ref: "work-orders/xt.md",
                kind: .workOrder,
                contents: """
                goal: Ship a supervisor intake and acceptance vertical slice
                constraints: deterministic extraction, prompt-pack binding
                acceptance_targets: gate_green, rollback_ready, evidence_complete
                """
            )
        ]
    }

    private func makeSplitProposal(projectID: UUID) -> SplitProposal {
        SplitProposal(
            splitPlanId: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
            rootProjectId: projectID,
            planVersion: 1,
            complexityScore: 0.64,
            lanes: [
                SplitLaneProposal(
                    laneId: "lane-intake",
                    goal: "Freeze intake manifest",
                    dependsOn: [],
                    riskTier: .medium,
                    budgetClass: .standard,
                    createChildProject: false,
                    expectedArtifacts: ["build/reports/xt_w3_21_project_intake_manifest.v1.json"],
                    dodChecklist: ["intake_frozen", "scope_confirmed", "rollback_ready"],
                    estimatedEffortMs: 1_200,
                    tokenBudget: 2_000,
                    sourceTaskId: nil,
                    notes: ["intake-first"]
                ),
                SplitLaneProposal(
                    laneId: "lane-acceptance",
                    goal: "Compile acceptance pack",
                    dependsOn: ["lane-intake"],
                    riskTier: .high,
                    budgetClass: .premium,
                    createChildProject: true,
                    expectedArtifacts: ["build/reports/xt_w3_22_acceptance_pack.v1.json"],
                    dodChecklist: ["evidence_complete", "rollback_ready", "delivery_summary_ready"],
                    estimatedEffortMs: 1_600,
                    tokenBudget: 3_000,
                    sourceTaskId: nil,
                    notes: ["acceptance-second"]
                )
            ],
            recommendedConcurrency: 1,
            tokenBudgetTotal: 5_000,
            estimatedWallTimeMs: 2_800,
            sourceTaskDescription: "XT-W3-21/22 vertical slice",
            createdAt: Date(timeIntervalSince1970: 1_772_000_000)
        )
    }

    private func makeCompletionTask(
        taskID: UUID,
        laneID: String,
        taskRef: String,
        gateVector: String,
        evidenceRefs: String,
        rollbackRef: String,
        riskSummary: String
    ) -> DecomposedTask {
        DecomposedTask(
            id: taskID,
            description: "Complete \(taskRef)",
            type: .development,
            complexity: .moderate,
            estimatedEffort: 60,
            priority: 5,
            metadata: [
                "lane_id": laneID,
                "task_ref": taskRef,
                "gate_vector": gateVector,
                "evidence_refs": evidenceRefs,
                "rollback_ref": rollbackRef,
                "risk_summary": riskSummary,
                "audit_ref": "audit-\(taskRef.lowercased())"
            ]
        )
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url)
    }
}
