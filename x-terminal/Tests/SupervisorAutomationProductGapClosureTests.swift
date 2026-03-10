import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorAutomationProductGapClosureTests {
    private let projectID = UUID(uuidString: "12345678-1234-1234-1234-1234567890ab")!

    @Test
    func recipeManifestBindsTriggersDeliveryTargetsAndAcceptancePack() {
        let vertical = XTAutomationProductGapClosureEngine().buildVerticalSlice(verticalSliceInput())

        #expect(vertical.recipeManifest.recipeManifest.schemaVersion == "xt.automation_recipe_manifest.v1")
        #expect(vertical.recipeManifest.recipeManifest.deliveryTargets == ["channel://telegram/project-a"])
        #expect(vertical.recipeManifest.recipeManifest.acceptancePackRef == "build/reports/xt_w3_22_acceptance_pack.v1.json")
        #expect(vertical.recipeManifest.recipeManifest.triggerRefs.count == 4)
        #expect(vertical.recipeManifest.recipeManifestSchemaCoverage == 1.0)
        #expect(vertical.recipeManifest.ambiguousTriggerFieldCount == 0)
        #expect(vertical.recipeManifest.triggerEnvelopes.contains { $0.triggerType == .webhook && !$0.dedupeKey.isEmpty })
        #expect(vertical.overall.gateVector.contains("XT-AUTO-G0:candidate_pass"))
    }

    @Test
    func eventRunnerMaintainsStableRunIdentityAndBoundedDowngradePaths() {
        let vertical = XTAutomationProductGapClosureEngine().buildVerticalSlice(verticalSliceInput())
        let states = vertical.eventRunner.statePath

        #expect(vertical.eventRunner.runTimeline.runID == "run-20260306-001")
        #expect(vertical.eventRunner.runIdentityStable)
        #expect(vertical.eventRunner.triggerDedupeFalseNegative == 0)
        #expect(vertical.eventRunner.replayGuardPass)
        #expect(vertical.eventRunner.grantBindingPass)
        #expect(states.contains(.queued))
        #expect(states.contains(.running))
        #expect(states.contains(.blocked))
        #expect(states.contains(.takeover))
        #expect(states.contains(.downgraded))
        #expect(states.contains(.delivered))
        #expect(Set(vertical.eventRunner.downgradePaths) == Set(XTAutomationDegradeMode.allCases))
        #expect(vertical.overall.gateVector.contains("XT-AUTO-G2:candidate_pass"))
    }

    @Test
    func directedTakeoverStaysSameProjectScopedAndRollbackReady() {
        let vertical = XTAutomationProductGapClosureEngine().buildVerticalSlice(verticalSliceInput())
        let decision = vertical.directedTakeover.takeoverDecision

        #expect(decision.takeoverMode == .claimUpstream)
        #expect(decision.scopeGuard == "same_project_only")
        #expect(!decision.rollbackRef.isEmpty)
        #expect(vertical.directedTakeover.blockedRunWithoutDirectedAction == 0)
        #expect(vertical.directedTakeover.criticalPathTakeoverSuccessRate >= 0.95)
        #expect(vertical.directedTakeover.guardViolationCount == 0)
        #expect(!vertical.directedTakeover.nextOwner.isEmpty)
        #expect(!vertical.directedTakeover.unblockChecklist.isEmpty)
        #expect(vertical.overall.gateVector.contains("XT-AUTO-G3:candidate_pass"))
    }

    @Test
    func timelineBootstrapAndGraduationStayExplainableAndReleaseReady() {
        let vertical = XTAutomationProductGapClosureEngine().buildVerticalSlice(verticalSliceInput())

        #expect(vertical.runTimeline.timeline.schemaVersion == "xt.automation_run_timeline.v1")
        #expect(vertical.runTimeline.visibleFieldsCoverage == 1.0)
        #expect(vertical.runTimeline.rawCotLeakCount == 0)
        #expect(vertical.runTimeline.operatorConsoleEvidenceRef == "build/reports/xt_w3_24_d_operator_console_evidence.v1.json")
        #expect(!vertical.runTimeline.userExplanation.lowercased().contains("chain-of-thought"))

        #expect(vertical.bootstrapTemplates.bundle.schemaVersion == "xt.automation_bootstrap_bundle.v1")
        #expect(vertical.bootstrapTemplates.templates.count == 5)
        #expect(vertical.bootstrapTemplates.highRiskTemplateTouchGuardPass)
        #expect(vertical.bootstrapTemplates.templates.contains { $0.kind == .releaseAssistant && $0.recommendedTouchMode == .criticalTouch })
        #expect(vertical.bootstrapTemplates.recipeToFirstRunP95Ms <= 180_000)

        #expect(vertical.competitiveGraduation.requireRealPass)
        #expect(vertical.competitiveGraduation.samples.count == 5)
        #expect(vertical.competitiveGraduation.automationDeliverySuccessRate >= 0.98)
        #expect(vertical.competitiveGraduation.tokenPerSuccessfulDeliveryDeltaVsBaseline <= -0.20)
        #expect(vertical.competitiveGraduation.whereIsMyRunQuestionRate <= 0.05)
        #expect(vertical.overall.gateVector.contains("XT-AUTO-G4:candidate_pass"))
        #expect(vertical.overall.gateVector.contains("XT-AUTO-G5:candidate_pass"))
    }

    @Test
    func runtimeCaptureWritesXTW325EvidenceFilesWhenRequested() throws {
        guard let captureDir = ProcessInfo.processInfo.environment["XT_W3_25_CAPTURE_DIR"], !captureDir.isEmpty else {
            return
        }
        let vertical = XTAutomationProductGapClosureEngine().buildVerticalSlice(verticalSliceInput())
        let base = URL(fileURLWithPath: captureDir)

        try writeJSON(vertical.recipeManifest, to: base.appendingPathComponent("xt_w3_25_a_recipe_manifest_evidence.v1.json"))
        try writeJSON(vertical.eventRunner, to: base.appendingPathComponent("xt_w3_25_b_event_runner_evidence.v1.json"))
        try writeJSON(vertical.directedTakeover, to: base.appendingPathComponent("xt_w3_25_c_directed_takeover_evidence.v1.json"))
        try writeJSON(vertical.runTimeline, to: base.appendingPathComponent("xt_w3_25_d_run_timeline_evidence.v1.json"))
        try writeJSON(vertical.bootstrapTemplates, to: base.appendingPathComponent("xt_w3_25_e_bootstrap_templates_evidence.v1.json"))
        try writeJSON(vertical.competitiveGraduation, to: base.appendingPathComponent("xt_w3_25_f_competitive_graduation_evidence.v1.json"))
        try writeJSON(vertical.overall, to: base.appendingPathComponent("xt_w3_25_automation_gap_closure_evidence.v1.json"))

        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("xt_w3_25_automation_gap_closure_evidence.v1.json").path))
    }

    private func verticalSliceInput() -> XTAutomationVerticalSliceInput {
        let intakeWorkflow = SupervisorIntakeAcceptanceEngine().buildProjectIntakeWorkflow(
            projectID: projectID,
            documents: intakeDocuments(),
            splitProposal: splitProposal(),
            now: Date(timeIntervalSince1970: 1_772_100_000)
        )
        let acceptanceWorkflow = SupervisorIntakeAcceptanceEngine().buildAcceptanceWorkflow(
            input: AcceptanceAggregationInput(
                projectID: projectID.uuidString.lowercased(),
                completedTasks: ["XT-W3-21", "XT-W3-22", "XT-W3-23", "XT-W3-24"],
                gateReadings: [
                    AcceptanceGateReading(gateID: "XT-MP-G5", status: .pass),
                    AcceptanceGateReading(gateID: "XT-AUTO-G2", status: .candidatePass),
                    AcceptanceGateReading(gateID: "XT-AUTO-G3", status: .candidatePass)
                ],
                riskSummary: [
                    AcceptanceRisk(riskID: "risk-auto-1", severity: .low, mitigation: "automation remains grant-bound and same-project scoped")
                ],
                rollbackPoints: [
                    AcceptanceRollbackPoint(component: "automation-runner", rollbackRef: "board://rollback/automation-runner-v1")
                ],
                evidenceRefs: [
                    "build/reports/xt_w3_22_acceptance_pack.v1.json",
                    "build/reports/xt_w3_24_multichannel_gateway_productization.v1.json"
                ],
                userSummaryRef: "board://delivery/summary/xt-w3-25",
                auditRef: "audit-xt-w3-25"
            ),
            participationMode: .guidedTouch,
            now: Date(timeIntervalSince1970: 1_772_100_010)
        )
        return XTAutomationVerticalSliceInput(
            projectID: projectID,
            recipeID: "xt-auto-pr-review",
            goal: "nightly triage + code review + summary delivery",
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l2,
            laneStrategy: .adaptive,
            runID: "run-20260306-001",
            currentOwner: "XT-L2",
            activePoolCount: 1,
            activeLaneCount: 1,
            blockedTaskID: "XT-W3-25-C",
            upstreamDependencyIDs: ["Hub-Wx", "XT-Wy"],
            operatorConsoleEvidenceRef: "build/reports/xt_w3_24_d_operator_console_evidence.v1.json",
            latestDeltaRef: "build/reports/xt_w3_25_run_delta_3line.v1.json",
            deliveryRef: "build/reports/xt_w3_25_delivery_card.v1.json",
            firstRunChecklistRef: "docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md",
            triggerSeeds: triggerSeeds(),
            intakeWorkflow: intakeWorkflow,
            acceptanceWorkflow: acceptanceWorkflow,
            additionalEvidenceRefs: [
                "build/reports/hub_l5_xt_w3_dependency_delta_3line.v1.json",
                "build/reports/xt_w3_25_hub_dependency_readiness.v1.json",
                "build/reports/xt_w3_24_multichannel_gateway_productization.v1.json",
                "build/reports/xt_main_xt_l2_delta_3line.v91.json"
            ],
            now: Date(timeIntervalSince1970: 1_772_100_030)
        )
    }

    private func triggerSeeds() -> [XTAutomationTriggerSeed] {
        [
            XTAutomationTriggerSeed(triggerID: "schedule/nightly", triggerType: .schedule, source: .timer, payloadRef: "local://trigger-payload/20260306-001", requiresGrant: true, policyRef: "policy://automation-trigger/project-a", dedupeKey: "sha256:schedule-nightly"),
            XTAutomationTriggerSeed(triggerID: "webhook/github_pr", triggerType: .webhook, source: .github, payloadRef: "local://trigger-payload/20260306-002", requiresGrant: true, policyRef: "policy://automation-trigger/project-a", dedupeKey: "sha256:webhook-github-pr"),
            XTAutomationTriggerSeed(triggerID: "connector_event/slack_dm", triggerType: .connectorEvent, source: .slack, payloadRef: "local://trigger-payload/20260306-003", requiresGrant: true, policyRef: "policy://automation-trigger/project-a", dedupeKey: "sha256:connector-event-slack-dm"),
            XTAutomationTriggerSeed(triggerID: "manual/retry", triggerType: .manual, source: .hub, payloadRef: "local://trigger-payload/20260306-004", requiresGrant: true, policyRef: "policy://automation-trigger/project-a", dedupeKey: "sha256:manual-retry")
        ]
    }

    private func intakeDocuments() -> [SupervisorIntakeSourceDocument] {
        [
            SupervisorIntakeSourceDocument(
                ref: "docs/xt-automation.md",
                kind: .markdown,
                contents: """
                project_goal: Close XT automation product gaps on top of Hub truth-source rails
                touch_policy: guided_touch
                innovation_level: L2
                suggestion_governance: hybrid
                risk_level: medium
                requires_user_authorization: true
                acceptance_mode: release_candidate
                token_budget_tier: balanced
                paid_ai_allowed: true

                ## in_scope
                - recipe manifest
                - event runner
                - directed takeover
                - run timeline
                - bootstrap templates
                - competitive graduation evidence

                ## out_of_scope
                - second automation backend
                - bypassing grants
                - broadcast-driven daily progress

                ## constraints
                - hub remains sole truth source
                - all side effects require grants and audit
                - automation stays directed-only by default

                ## acceptance_targets
                - gate_green
                - rollback_ready
                - evidence_complete
                """
            )
        ]
    }

    private func splitProposal() -> SplitProposal {
        SplitProposal(
            splitPlanId: UUID(uuidString: "cccccccc-0000-0000-0000-000000000025")!,
            rootProjectId: projectID,
            planVersion: 1,
            complexityScore: 0.67,
            lanes: [
                SplitLaneProposal(
                    laneId: "lane-automation-core",
                    goal: "Build recipe, trigger, runner, and takeover contracts",
                    dependsOn: [],
                    riskTier: .high,
                    budgetClass: .premium,
                    createChildProject: false,
                    expectedArtifacts: [
                        "build/reports/xt_w3_25_a_recipe_manifest_evidence.v1.json",
                        "build/reports/xt_w3_25_b_event_runner_evidence.v1.json",
                        "build/reports/xt_w3_25_c_directed_takeover_evidence.v1.json"
                    ],
                    dodChecklist: ["schema_frozen", "run_identity_stable", "takeover_guarded"],
                    estimatedEffortMs: 2400,
                    tokenBudget: 3600,
                    sourceTaskId: nil,
                    notes: ["automation-core"]
                ),
                SplitLaneProposal(
                    laneId: "lane-automation-product-surface",
                    goal: "Build run timeline, bootstrap templates, and graduation harness",
                    dependsOn: ["lane-automation-core"],
                    riskTier: .medium,
                    budgetClass: .standard,
                    createChildProject: true,
                    expectedArtifacts: [
                        "build/reports/xt_w3_25_d_run_timeline_evidence.v1.json",
                        "build/reports/xt_w3_25_e_bootstrap_templates_evidence.v1.json",
                        "build/reports/xt_w3_25_f_competitive_graduation_evidence.v1.json"
                    ],
                    dodChecklist: ["explainable", "first_run_ready", "require_real_pass"],
                    estimatedEffortMs: 2200,
                    tokenBudget: 3200,
                    sourceTaskId: nil,
                    notes: ["automation-surface"]
                )
            ],
            recommendedConcurrency: 1,
            tokenBudgetTotal: 6800,
            estimatedWallTimeMs: 4200,
            sourceTaskDescription: "XT-W3-25 automation product gap closure",
            createdAt: Date(timeIntervalSince1970: 1_772_100_000)
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
