import Foundation
import Testing
@testable import XTerminal

@MainActor
struct XTW330PolicyRecoveryEvidenceTests {
    private let permissionGate = TrustedAutomationPermissionTestGate.shared

    @Test
    func policyRecoveryProducesDeliveredEvidenceAndCaptureArtifactWhenRequested() async throws {
        try await permissionGate.run {
            let pendingGrantRoot = try makeProjectRoot(name: "xt-w3-30-b-policy-unbound")
            let downgradeRoot = try makeProjectRoot(name: "xt-w3-30-b-budget-downgrade")
            let recoveryRoot = try makeProjectRoot(name: "xt-w3-30-b-restart-recovery")
            let clampGuidedFixture = ToolExecutorProjectFixture(name: "xt-w3-30-b-clamp-guided")
            let clampManualFixture = ToolExecutorProjectFixture(name: "xt-w3-30-b-clamp-manual")
            let manager = SupervisorManager.makeForTesting()

            defer {
                manager.resetAutomationRuntimeState()
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                clampGuidedFixture.cleanup()
                clampManualFixture.cleanup()
                try? FileManager.default.removeItem(at: pendingGrantRoot)
                try? FileManager.default.removeItem(at: downgradeRoot)
                try? FileManager.default.removeItem(at: recoveryRoot)
            }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePolicyRecoveryPermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-xt-w3-30-b-policy-recovery-permissions"
                )
            }

            let pendingGrantCtx = AXProjectContext(root: pendingGrantRoot)
            _ = try AXProjectStore.upsertAutomationRecipe(
                makeScheduleRecipe(
                    recipeID: "xt-auto-policy-unbound",
                    goal: "hold when trigger grant binding is unbound",
                    grantPolicyRef: "",
                    lastEditAuditRef: "audit-xt-w3-30-b-policy-unbound"
                ),
                activate: true,
                for: pendingGrantCtx
            )
            let pendingGrantCoordinator = XTAutomationRunCoordinator()
            let pendingGrantPrepared = try pendingGrantCoordinator.prepareActiveRun(
                for: pendingGrantCtx,
                request: makeScheduleRequest(
                    policyRef: "policy://automation-trigger/project-a",
                    now: Date(timeIntervalSince1970: 1_773_600_100)
                )
            )
            let pendingGrantLaunchRow = try #require(
                rawLogEntries(for: pendingGrantCtx).last(where: {
                    ($0["type"] as? String) == "automation_run_launch"
                        && ($0["run_id"] as? String) == pendingGrantPrepared.launchRef
                })
            )

            let downgradeCtx = AXProjectContext(root: downgradeRoot)
            _ = try AXProjectStore.upsertAutomationRecipe(
                makeScheduleRecipe(
                    recipeID: "xt-auto-budget-downgrade",
                    goal: "downgrade to read-only when budget closes",
                    grantPolicyRef: "policy://automation-trigger/project-a",
                    lastEditAuditRef: "audit-xt-w3-30-b-budget-downgrade"
                ),
                activate: true,
                for: downgradeCtx
            )
            let downgradeCoordinator = XTAutomationRunCoordinator()
            let downgradePrepared = try downgradeCoordinator.prepareActiveRun(
                for: downgradeCtx,
                request: makeScheduleRequest(
                    policyRef: "policy://automation-trigger/project-a",
                    budgetOK: false,
                    now: Date(timeIntervalSince1970: 1_773_600_120)
                )
            )
            let downgradeLaunchRow = try #require(
                rawLogEntries(for: downgradeCtx).last(where: {
                    ($0["type"] as? String) == "automation_run_launch"
                        && ($0["run_id"] as? String) == downgradePrepared.launchRef
                })
            )

            let clampGuidedCtx = AXProjectContext(root: clampGuidedFixture.root)
            var clampGuidedConfig = try AXProjectStore.loadOrCreateConfig(for: clampGuidedCtx)
            clampGuidedConfig = clampGuidedConfig.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.clipboard.read"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: clampGuidedFixture.root)
            )
            clampGuidedConfig = clampGuidedConfig.settingProjectGovernance(
                executionTier: .a4OpenClaw,
                supervisorInterventionTier: .s2PeriodicReview
            )
            clampGuidedConfig = clampGuidedConfig.settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                hubOverrideMode: .clampGuided,
                updatedAt: Date()
            )
            try AXProjectStore.saveConfig(clampGuidedConfig, for: clampGuidedCtx)

            let clampGuidedResult = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceClipboardRead, args: [:]),
                projectRoot: clampGuidedFixture.root
            )
            let clampGuidedSummary = try #require(toolSummaryObject(clampGuidedResult.output))

            let clampManualCtx = AXProjectContext(root: clampManualFixture.root)
            var clampManualConfig = try AXProjectStore.loadOrCreateConfig(for: clampManualCtx)
            clampManualConfig = clampManualConfig.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_002",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: clampManualFixture.root)
            )
            clampManualConfig = clampManualConfig.settingProjectGovernance(
                executionTier: .a4OpenClaw,
                supervisorInterventionTier: .s2PeriodicReview
            )
            clampManualConfig = clampManualConfig.settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                hubOverrideMode: .clampManual,
                updatedAt: Date()
            )
            try AXProjectStore.saveConfig(clampManualConfig, for: clampManualCtx)

            let clampManualResult = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string("https://example.com/openclaw-mode")
                    ]
                ),
                projectRoot: clampManualFixture.root
            )
            let clampManualSummary = try #require(toolSummaryObject(clampManualResult.output))

            manager.resetAutomationRuntimeState()
            let recoveryCtx = AXProjectContext(root: recoveryRoot)
            try armRepoAutomationGovernance(for: recoveryCtx)
            _ = try AXProjectStore.upsertAutomationRecipe(
                makeResumeFromFailedActionRecipe(),
                activate: true,
                for: recoveryCtx
            )
            manager.installAutomationRunExecutorForTesting(
                XTAutomationRunExecutor { call, _ in
                    switch call.tool {
                    case .write_file:
                        return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
                    case .run_command:
                        return ToolResult(id: call.id, tool: call.tool, ok: false, output: "exit: 1\nstep failed")
                    default:
                        return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                    }
                }
            )

            let initialPrepared = try manager.startAutomationRun(
                for: recoveryCtx,
                request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_600_300))
            )
            let recoveryProjectID = AXProjectRegistryStore.projectId(forRoot: recoveryRoot)
            let sourceRunID = initialPrepared.launchRef

            try await waitUntil("initial recovery source run blocked") {
                guard let report = xtAutomationLoadExecutionReport(
                    for: sourceRunID,
                    ctx: recoveryCtx
                ) else {
                    return false
                }
                return report.finalState == .blocked
                    && report.holdReason == "automation_action_failed"
            }

            if xtAutomationLoadExecutionReport(for: sourceRunID, ctx: recoveryCtx) == nil {
                Issue.record("initial source run raw log summary: \(rawLogSummary(for: recoveryCtx))")
            }

            _ = try #require(
                xtAutomationLoadExecutionReport(for: sourceRunID, ctx: recoveryCtx)
            )
            let recoveryDecision = try #require(
                try manager.recoverLatestAutomationRun(
                    for: recoveryCtx,
                    checkpointAgeSeconds: 0,
                    auditRef: "audit-xt-w3-30-b-restart-recovery"
                )
            )

            try await waitUntil("restart recovery retry scheduled") {
                xtAutomationReadRawLogRows(for: recoveryCtx).contains(where: {
                    ($0["type"] as? String) == "automation_retry"
                        && ($0["status"] as? String) == "scheduled"
                        && ($0["source_run_id"] as? String) == sourceRunID
                        && (($0["retry_run_id"] as? String) ?? "").isEmpty == false
                })
            }

            let recoveryRows = try rawLogEntries(for: recoveryCtx)
            let scheduledRetryRow = try #require(
                recoveryRows.last(where: {
                    ($0["type"] as? String) == "automation_retry"
                        && ($0["status"] as? String) == "scheduled"
                        && ($0["source_run_id"] as? String) == sourceRunID
                })
            )
            let retryRunID = try #require(scheduledRetryRow["retry_run_id"] as? String)

            try await waitUntil("restart recovery retry blocked") {
                guard let report = xtAutomationLoadExecutionReport(
                    for: retryRunID,
                    ctx: recoveryCtx
                ) else {
                    return false
                }
                return report.runID == retryRunID && report.finalState == .blocked
            }

            if xtAutomationLoadExecutionReport(for: retryRunID, ctx: recoveryCtx) == nil {
                Issue.record("retry run raw log summary: \(rawLogSummary(for: recoveryCtx))")
            }

            let retryPackage = try #require(
                xtAutomationLoadRetryPackage(
                    forRetryRunID: retryRunID,
                    projectID: recoveryProjectID,
                    ctx: recoveryCtx
                )
            )
            let retryLineage = try #require(retryPackage.lineage)
            let retryReport = try #require(
                xtAutomationLoadExecutionReport(for: retryRunID, ctx: recoveryCtx)
            )
            let retryLaunchRow = try #require(
                recoveryRows.last(where: {
                    ($0["type"] as? String) == "automation_run_launch"
                        && ($0["run_id"] as? String) == retryRunID
                })
            )

            let pendingGrantLaunchPass =
                pendingGrantPrepared.verticalSlice.eventRunner.launchDecision.decision == .hold
                && pendingGrantPrepared.verticalSlice.eventRunner.launchDecision.holdReason == "automation_trigger_policy_unbound"
                && pendingGrantPrepared.currentCheckpoint.state == .blocked
                && (pendingGrantLaunchRow["launch_decision"] as? String) == "hold"
                && (pendingGrantLaunchRow["hold_reason"] as? String) == "automation_trigger_policy_unbound"

            let downgradeLaunchPass =
                downgradePrepared.verticalSlice.eventRunner.launchDecision.decision == .downgrade
                && downgradePrepared.verticalSlice.eventRunner.launchDecision.holdReason == "budget_blocked_downgrade_to_read_only"
                && downgradePrepared.currentCheckpoint.state == .downgraded
                && (downgradeLaunchRow["launch_decision"] as? String) == "downgrade"
                && (downgradeLaunchRow["hold_reason"] as? String) == "budget_blocked_downgrade_to_read_only"

            let clampGuidedPass =
                !clampGuidedResult.ok
                && jsonString(clampGuidedSummary["deny_code"]) == "autonomy_policy_denied"
                && jsonString(clampGuidedSummary["policy_source"]) == "project_autonomy_policy"
                && jsonString(clampGuidedSummary["policy_reason"]) == "hub_override=clamp_guided"
                && jsonString(clampGuidedSummary["runtime_surface_policy_reason"]) == "hub_override=clamp_guided"
                && jsonString(jsonObject(clampGuidedSummary["runtime_surface"])?["effective_surface"]) == AXProjectRuntimeSurfaceMode.guided.rawValue
                && jsonString(clampGuidedSummary["autonomy_effective_mode"]) == AXProjectRuntimeSurfaceMode.guided.rawValue

            let clampManualPass =
                !clampManualResult.ok
                && jsonString(clampManualSummary["deny_code"]) == "autonomy_policy_denied"
                && jsonString(clampManualSummary["policy_source"]) == "project_autonomy_policy"
                && jsonString(clampManualSummary["policy_reason"]) == "hub_override=clamp_manual"
                && jsonString(clampManualSummary["runtime_surface_policy_reason"]) == "hub_override=clamp_manual"
                && jsonString(jsonObject(clampManualSummary["runtime_surface"])?["effective_surface"]) == AXProjectRuntimeSurfaceMode.manual.rawValue
                && jsonString(clampManualSummary["autonomy_effective_mode"]) == AXProjectRuntimeSurfaceMode.manual.rawValue

            let recoverySchedulePass =
                recoveryDecision.decision == .resume
                && recoveryDecision.recoveredState == .blocked
                && (scheduledRetryRow["retry_strategy"] as? String) == "action_failure_retry"
                && (scheduledRetryRow["retry_reason"] as? String) == "automation_action_failed"
                && (scheduledRetryRow["source_run_id"] as? String) == sourceRunID
                && (scheduledRetryRow["retry_run_id"] as? String) == retryRunID

            let recoveryLineagePass =
                retryLineage.rootRunID == sourceRunID
                && retryLineage.parentRunID == sourceRunID
                && retryLineage.retryDepth == 1
                && (retryLaunchRow["root_run_id"] as? String) == sourceRunID
                && (retryLaunchRow["parent_run_id"] as? String) == sourceRunID
                && (retryLaunchRow["retry_depth"] as? Int) == 1

            let evidence = XTW330BPolicyRecoveryEvidence(
                schemaVersion: "xt_w3_30_b_policy_recovery_evidence.v1",
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                status: "delivered",
                claimScope: ["XT-W3-30-B", "XT-OC-G2"],
                claim: "Grant pending hold, budget downgrade, hub clamp, and restart recovery are exported as first-class XT runtime evidence instead of remaining implicit launch gate behavior.",
                runtimeContracts: PolicyRecoveryContractEvidence(
                    launchDecisionSchemaVersion: pendingGrantPrepared.verticalSlice.eventRunner.launchDecision.schemaVersion,
                    checkpointSchemaVersion: pendingGrantPrepared.currentCheckpoint.schemaVersion,
                    recoveryDecisionSchemaVersion: recoveryDecision.schemaVersion
                ),
                runtimeSurface: [
                    PolicyRecoverySurfaceEvidence(
                        surface: "grant_pending_launch_gate",
                        state: pendingGrantPrepared.currentCheckpoint.state.rawValue,
                        exercised: true,
                        decision: pendingGrantPrepared.verticalSlice.eventRunner.launchDecision.decision.rawValue,
                        holdReason: pendingGrantPrepared.verticalSlice.eventRunner.launchDecision.holdReason,
                        denyCode: nil,
                        policyReason: nil
                    ),
                    PolicyRecoverySurfaceEvidence(
                        surface: "budget_downgrade_launch_gate",
                        state: downgradePrepared.currentCheckpoint.state.rawValue,
                        exercised: true,
                        decision: downgradePrepared.verticalSlice.eventRunner.launchDecision.decision.rawValue,
                        holdReason: downgradePrepared.verticalSlice.eventRunner.launchDecision.holdReason,
                        denyCode: nil,
                        policyReason: nil
                    ),
                    PolicyRecoverySurfaceEvidence(
                        surface: "hub_clamp_guided_device_surface",
                        state: "fail_closed",
                        exercised: true,
                        decision: "deny",
                        holdReason: nil,
                        denyCode: jsonString(clampGuidedSummary["deny_code"]),
                        policyReason: jsonString(clampGuidedSummary["policy_reason"])
                    ),
                    PolicyRecoverySurfaceEvidence(
                        surface: "hub_clamp_manual_browser_surface",
                        state: "fail_closed",
                        exercised: true,
                        decision: "deny",
                        holdReason: nil,
                        denyCode: jsonString(clampManualSummary["deny_code"]),
                        policyReason: jsonString(clampManualSummary["policy_reason"])
                    ),
                    PolicyRecoverySurfaceEvidence(
                        surface: "restart_recovery_retry_surface",
                        state: retryReport.finalState.rawValue,
                        exercised: true,
                        decision: recoveryDecision.decision.rawValue,
                        holdReason: recoveryDecision.holdReason.isEmpty ? nil : recoveryDecision.holdReason,
                        denyCode: nil,
                        policyReason: retryPackage.retryStrategy
                    )
                ],
                verificationResults: [
                    PolicyRecoveryVerificationResult(
                        name: "grant_pending_launch_exported",
                        status: pendingGrantLaunchPass ? "pass" : "fail",
                        detail: pendingGrantLaunchPass ? "automation_run_launch exports hold automation_trigger_policy_unbound and checkpoint blocks the run" : "grant pending hold export drifted"
                    ),
                    PolicyRecoveryVerificationResult(
                        name: "budget_downgrade_launch_exported",
                        status: downgradeLaunchPass ? "pass" : "fail",
                        detail: downgradeLaunchPass ? "automation_run_launch exports downgrade budget_blocked_downgrade_to_read_only and checkpoint starts downgraded" : "budget downgrade export drifted"
                    ),
                    PolicyRecoveryVerificationResult(
                        name: "hub_clamp_guided_fail_closed",
                        status: clampGuidedPass ? "pass" : "fail",
                        detail: clampGuidedPass ? "device surface deny exports autonomy_policy_denied with hub_override=clamp_guided" : "clamp_guided device deny export drifted"
                    ),
                    PolicyRecoveryVerificationResult(
                        name: "hub_clamp_manual_fail_closed",
                        status: clampManualPass ? "pass" : "fail",
                        detail: clampManualPass ? "browser surface deny exports autonomy_policy_denied with hub_override=clamp_manual" : "clamp_manual browser deny export drifted"
                    ),
                    PolicyRecoveryVerificationResult(
                        name: "restart_recovery_resume_schedules_retry",
                        status: recoverySchedulePass ? "pass" : "fail",
                        detail: recoverySchedulePass ? "recovery decision resumes blocked run and appends scheduled automation_retry row" : "restart recovery did not export scheduled retry evidence"
                    ),
                    PolicyRecoveryVerificationResult(
                        name: "restart_recovery_lineage_exported",
                        status: recoveryLineagePass ? "pass" : "fail",
                        detail: recoveryLineagePass ? "retry launch exports root_run_id/parent_run_id/retry_depth for resumable lineage" : "retry lineage export drifted"
                    )
                ],
                boundedGaps: [],
                sourceRefs: [
                    "x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md:286",
                    "x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift:800",
                    "x-terminal/Sources/Supervisor/SupervisorManager.swift:7745",
                    "x-terminal/Sources/Supervisor/XTAutomationRunCheckpointStore.swift:1",
                    "x-terminal/Sources/Supervisor/XTAutomationRunCoordinator.swift:1",
                    "x-terminal/Sources/Tools/XTToolRuntimePolicy.swift:1",
                    "x-terminal/Tests/ToolExecutorRuntimePolicyTests.swift:1",
                    "x-terminal/Tests/XTW330PolicyRecoveryEvidenceTests.swift:1"
                ]
            )

            #expect(evidence.verificationResults.allSatisfy { $0.status == "pass" })
            #expect(evidence.boundedGaps.isEmpty)

            guard let captureDir = ProcessInfo.processInfo.environment["XT_W3_30_CAPTURE_DIR"],
                  !captureDir.isEmpty else {
                return
            }

            let destination = URL(fileURLWithPath: captureDir)
                .appendingPathComponent("xt_w3_30_b_policy_recovery_evidence.v1.json")
            try writeJSON(evidence, to: destination)
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    private func makeProjectRoot(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func rawLogEntries(for ctx: AXProjectContext) throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path) else { return [] }
        let data = try Data(contentsOf: ctx.rawLogURL)
        let text = try #require(String(data: data, encoding: .utf8))
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let lineData = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    return nil
                }
                return object
            }
    }

    private func rawLogSummary(for ctx: AXProjectContext) -> String {
        let rows = (try? rawLogEntries(for: ctx)) ?? []
        guard !rows.isEmpty else { return "(empty)" }
        return rows.map { row in
            let type = (row["type"] as? String) ?? "?"
            let phase = (row["phase"] as? String) ?? ""
            let runID = (row["run_id"] as? String) ?? ""
            let state = (row["state"] as? String) ?? ((row["final_state"] as? String) ?? "")
            let holdReason = (row["hold_reason"] as? String) ?? ""
            let status = (row["status"] as? String) ?? ""
            return [type, phase, status, runID, state, holdReason]
                .filter { !$0.isEmpty }
                .joined(separator: ":")
        }.joined(separator: " | ")
    }

    private func armRepoAutomationGovernance(for ctx: AXProjectContext) throws {
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)
    }

    private func makeScheduleRecipe(
        recipeID: String,
        goal: String,
        grantPolicyRef: String,
        lastEditAuditRef: String
    ) -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: recipeID,
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: goal,
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:schedule/nightly"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: grantPolicyRef,
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_600_000_000,
            lastEditAuditRef: lastEditAuditRef,
            lastLaunchRef: ""
        )
    }

    private func makeScheduleRequest(
        policyRef: String,
        budgetOK: Bool = true,
        now: Date
    ) -> XTAutomationRunRequest {
        XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "schedule/nightly",
                    triggerType: .schedule,
                    source: .timer,
                    payloadRef: "local://trigger-payload/xt-w3-30-b-schedule",
                    requiresGrant: true,
                    policyRef: policyRef,
                    dedupeKey: "sha256:xt-w3-30-b-schedule-\(Int(now.timeIntervalSince1970))"
                )
            ],
            budgetOK: budgetOK,
            blockedTaskID: "XT-W3-30-B",
            upstreamDependencyIDs: ["Hub-Wx"],
            now: now
        )
    }

    private func makeManualRequest(now: Date) -> XTAutomationRunRequest {
        XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "manual/retry",
                    triggerType: .manual,
                    source: .hub,
                    payloadRef: "local://trigger-payload/manual-retry",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: "manual|project-a|\(Int(now.timeIntervalSince1970))"
                )
            ],
            blockedTaskID: "XT-W3-30-B",
            upstreamDependencyIDs: ["Hub-Wx"],
            now: now
        )
    }

    private func makeResumeFromFailedActionRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-resume-failed-action",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "resume from failed action instead of replaying successful prefix",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:manual/retry"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            actionGraph: [
                XTAutomationRecipeAction(
                    title: "Write README",
                    tool: .write_file,
                    args: [
                        "path": .string("README.md"),
                        "content": .string("hello")
                    ]
                ),
                XTAutomationRecipeAction(
                    title: "Run failing step",
                    tool: .run_command,
                    args: [
                        "command": .string("false"),
                        "timeout_sec": .number(10)
                    ]
                )
            ],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_600_300_000,
            lastEditAuditRef: "audit-xt-w3-30-b-restart-recovery-recipe",
            lastLaunchRef: ""
        )
    }

    private func waitUntil(
        _ label: String,
        timeoutMs: UInt64 = 2_000,
        intervalMs: UInt64 = 50,
        condition: @escaping @MainActor @Sendable () -> Bool
    ) async throws {
        let attempts = max(1, Int(timeoutMs / intervalMs))
        for _ in 0..<attempts {
            if await MainActor.run(body: condition) {
                return
            }
            try await Task.sleep(nanoseconds: intervalMs * 1_000_000)
        }
        Issue.record("Timed out waiting for \(label)")
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

private func makePolicyRecoveryPermissionReadiness(
    accessibility: AXTrustedAutomationPermissionStatus,
    automation: AXTrustedAutomationPermissionStatus,
    screenRecording: AXTrustedAutomationPermissionStatus,
    auditRef: String
) -> AXTrustedAutomationPermissionOwnerReadiness {
    AXTrustedAutomationPermissionOwnerReadiness(
        schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
        ownerID: "owner-xt",
        ownerType: "xterminal_app",
        bundleID: "com.xterminal.app",
        installState: "ready",
        mode: "managed_or_prompted",
        accessibility: accessibility,
        automation: automation,
        screenRecording: screenRecording,
        fullDiskAccess: .missing,
        inputMonitoring: .missing,
        canPromptUser: true,
        managedByMDM: false,
        overallState: "partial",
        openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
        auditRef: auditRef
    )
}

private struct XTW330BPolicyRecoveryEvidence: Codable, Equatable {
    var schemaVersion: String
    var generatedAt: String
    var status: String
    var claimScope: [String]
    var claim: String
    var runtimeContracts: PolicyRecoveryContractEvidence
    var runtimeSurface: [PolicyRecoverySurfaceEvidence]
    var verificationResults: [PolicyRecoveryVerificationResult]
    var boundedGaps: [PolicyRecoveryGapEvidence]
    var sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case status
        case claimScope = "claim_scope"
        case claim
        case runtimeContracts = "runtime_contracts"
        case runtimeSurface = "runtime_surface"
        case verificationResults = "verification_results"
        case boundedGaps = "bounded_gaps"
        case sourceRefs = "source_refs"
    }
}

private struct PolicyRecoveryContractEvidence: Codable, Equatable {
    var launchDecisionSchemaVersion: String
    var checkpointSchemaVersion: String
    var recoveryDecisionSchemaVersion: String

    enum CodingKeys: String, CodingKey {
        case launchDecisionSchemaVersion = "launch_decision_schema_version"
        case checkpointSchemaVersion = "checkpoint_schema_version"
        case recoveryDecisionSchemaVersion = "recovery_decision_schema_version"
    }
}

private struct PolicyRecoverySurfaceEvidence: Codable, Equatable {
    var surface: String
    var state: String
    var exercised: Bool
    var decision: String
    var holdReason: String?
    var denyCode: String?
    var policyReason: String?

    enum CodingKeys: String, CodingKey {
        case surface
        case state
        case exercised
        case decision
        case holdReason = "hold_reason"
        case denyCode = "deny_code"
        case policyReason = "policy_reason"
    }
}

private struct PolicyRecoveryVerificationResult: Codable, Equatable {
    var name: String
    var status: String
    var detail: String
}

private struct PolicyRecoveryGapEvidence: Codable, Equatable {
    var id: String
    var severity: String
    var currentBehavior: String
    var requiredNextStep: String

    enum CodingKeys: String, CodingKey {
        case id
        case severity
        case currentBehavior = "current_behavior"
        case requiredNextStep = "required_next_step"
    }
}
