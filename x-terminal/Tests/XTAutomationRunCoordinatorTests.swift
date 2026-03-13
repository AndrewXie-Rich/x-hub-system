import Foundation
import Testing
@testable import XTerminal

struct XTAutomationRunCoordinatorTests {
    @Test
    func prepareActiveRunPersistsLaunchRefAndBootstrapCheckpoint() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let recipe = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let coordinator = XTAutomationRunCoordinator()

        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_000))
        )
        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let rawLog = try rawLogEntries(for: ctx)

        #expect(prepared.recipeRef == recipe.ref)
        #expect(prepared.launchRef == reloaded.lastAutomationLaunchRef)
        #expect(prepared.verticalSlice.eventRunner.launchDecision.decision == .run)
        #expect(prepared.currentCheckpoint.runID == prepared.launchRef)
        #expect(prepared.currentCheckpoint.state == .queued)
        #expect(rawLog.contains {
            ($0["type"] as? String) == "automation_run_launch"
                && ($0["run_id"] as? String) == prepared.launchRef
                && ($0["external_trigger_ingress_schema_version"] as? String) == XTAutomationExternalTriggerIngressEnvelope.currentSchemaVersion
        })
        #expect(rawLog.contains { ($0["type"] as? String) == "automation_checkpoint" && ($0["run_id"] as? String) == prepared.launchRef })
    }

    @Test
    func recoverLatestRunReplaysPersistedCheckpointAcrossCoordinatorInstances() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_100))
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .blocked,
            retryAfterSeconds: 90,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-001",
            now: Date(timeIntervalSince1970: 1_773_100_101)
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .takeover,
            for: ctx,
            auditRef: "audit-xt-auto-takeover-001",
            now: Date(timeIntervalSince1970: 1_773_100_102)
        )

        let freshCoordinator = XTAutomationRunCoordinator()
        let latestRecovery = try freshCoordinator.recoverLatestRun(
            for: ctx,
            checkpointAgeSeconds: 60,
            auditRef: "audit-xt-auto-recover-001"
        )
        let recovered = try #require(latestRecovery)

        #expect(recovered.decision == .resume)
        #expect(recovered.recoveredState == .takeover)
        #expect(recovered.runID == prepared.launchRef)
        #expect(recovered.stableIdentityPass)
    }

    @Test
    func recoveryFailsClosedForCancelledAndStaleRuns() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_200))
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .blocked,
            retryAfterSeconds: 120,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-002",
            now: Date(timeIntervalSince1970: 1_773_100_201)
        )

        try coordinator.cancelRun(
            prepared.launchRef,
            for: ctx,
            auditRef: "audit-xt-auto-cancel-001",
            now: Date(timeIntervalSince1970: 1_773_100_202)
        )
        let cancelled = try coordinator.recoverRun(
            prepared.launchRef,
            for: ctx,
            checkpointAgeSeconds: 60,
            auditRef: "audit-xt-auto-recover-cancelled"
        )

        #expect(cancelled.decision == .suppressed)
        #expect(cancelled.holdReason == "manual_cancelled")

        let staleRoot = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: staleRoot) }

        let staleCtx = AXProjectContext(root: staleRoot)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: staleCtx)

        let staleCoordinator = XTAutomationRunCoordinator()
        let stalePrepared = try staleCoordinator.prepareActiveRun(
            for: staleCtx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_300))
        )
        _ = try staleCoordinator.advanceRun(
            stalePrepared.launchRef,
            to: .blocked,
            retryAfterSeconds: 120,
            for: staleCtx,
            auditRef: "audit-xt-auto-blocked-stale",
            now: Date(timeIntervalSince1970: 1_773_100_301)
        )
        let stale = try staleCoordinator.recoverRun(
            stalePrepared.launchRef,
            for: staleCtx,
            checkpointAgeSeconds: 3_600,
            auditRef: "audit-xt-auto-recover-stale"
        )

        #expect(stale.decision == .scavenged)
        #expect(stale.holdReason == "stale_run_scavenged")
    }

    @Test
    func prepareRunFailsClosedWithoutActiveReadyRecipe() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let coordinator = XTAutomationRunCoordinator()

        do {
            _ = try coordinator.prepareActiveRun(
                for: ctx,
                request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_400))
            )
            Issue.record("Expected activeRecipeMissing error")
        } catch let error as XTAutomationRunCoordinatorError {
            #expect(error == .activeRecipeMissing)
        }
    }

    @Test
    func prepareRunFailsClosedWhenNonManualTriggerIsNotDeclaredByRecipe() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let coordinator = XTAutomationRunCoordinator()
        let request = XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "webhook/rogue",
                    triggerType: .webhook,
                    source: .github,
                    payloadRef: "local://trigger-payload/rogue",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: "sha256:rogue"
                )
            ],
            now: Date(timeIntervalSince1970: 1_773_100_450)
        )

        do {
            _ = try coordinator.prepareActiveRun(for: ctx, request: request)
            Issue.record("Expected triggerIngressNotAllowed error")
        } catch let error as XTAutomationRunCoordinatorError {
            #expect(error == .triggerIngressNotAllowed("webhook/rogue"))
        }
    }

    @Test
    func prepareRunFailsClosedWhenNonManualReplayDedupeCollides() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let coordinator = XTAutomationRunCoordinator()
        let duplicateKey = "sha256:duplicate-webhook"
        let request = XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "schedule/nightly",
                    triggerType: .schedule,
                    source: .timer,
                    payloadRef: "local://trigger-payload/20260310-001",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: duplicateKey
                ),
                XTAutomationTriggerSeed(
                    triggerID: "webhook/github_pr",
                    triggerType: .webhook,
                    source: .github,
                    payloadRef: "local://trigger-payload/20260310-002",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: duplicateKey
                )
            ],
            now: Date(timeIntervalSince1970: 1_773_100_460)
        )

        do {
            _ = try coordinator.prepareActiveRun(for: ctx, request: request)
            Issue.record("Expected triggerIngressReplayDetected error")
        } catch let error as XTAutomationRunCoordinatorError {
            #expect(error == .triggerIngressReplayDetected(duplicateKey))
        }
    }

    @Test
    func prepareRunAllowsManualTriggerOutsideRecipeAllowlist() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let coordinator = XTAutomationRunCoordinator()
        let request = XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "manual/recover",
                    triggerType: .manual,
                    source: .hub,
                    payloadRef: "local://supervisor/recover/project-a",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: "manual|project-a|recover"
                )
            ],
            now: Date(timeIntervalSince1970: 1_773_100_470)
        )

        let prepared = try coordinator.prepareActiveRun(for: ctx, request: request)
        #expect(prepared.currentCheckpoint.state == .queued)
        #expect(prepared.verticalSlice.eventRunner.launchDecision.decision == .run)
    }

    @Test
    func advanceRunHoldsAtSafePointWhenPendingGuidanceExists() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let coordinator = XTAutomationRunCoordinator()

        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_500))
        )
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-automation-safe-point-1",
                reviewId: "review-automation-safe-point-1",
                projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .checkpointBoundary,
                guidanceText: "在 automation checkpoint 先暂停，重新评估。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_100_500_500,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-automation-safe-point-1"
            ),
            for: ctx
        )

        let checkpoint = try coordinator.advanceRun(
            prepared.launchRef,
            to: .running,
            for: ctx,
            auditRef: "audit-xt-auto-safe-point-hold-001",
            now: Date(timeIntervalSince1970: 1_773_100_501)
        )
        let rawLog = try rawLogEntries(for: ctx)

        #expect(checkpoint.state == .blocked)
        #expect(rawLog.contains {
            ($0["type"] as? String) == "automation_safe_point_hold" &&
            ($0["run_id"] as? String) == prepared.launchRef &&
            ($0["requested_state"] as? String) == XTAutomationRunState.running.rawValue &&
            ($0["injection_id"] as? String) == "guidance-automation-safe-point-1"
        })
    }

    @Test
    func automationSafePointHoldDoesNotLoopForeverForSameGuidance() throws {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let coordinator = XTAutomationRunCoordinator()

        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_600))
        )
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-automation-safe-point-2",
                reviewId: "review-automation-safe-point-2",
                projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                interventionMode: .suggestNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "下一 automation step 再切换方向。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_100_600_500,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-automation-safe-point-2"
            ),
            for: ctx
        )

        let first = try coordinator.advanceRun(
            prepared.launchRef,
            to: .running,
            for: ctx,
            auditRef: "audit-xt-auto-safe-point-hold-002a",
            now: Date(timeIntervalSince1970: 1_773_100_601)
        )
        let second = try coordinator.advanceRun(
            prepared.launchRef,
            to: .running,
            for: ctx,
            auditRef: "audit-xt-auto-safe-point-hold-002b",
            now: Date(timeIntervalSince1970: 1_773_100_602)
        )
        let rawLog = try rawLogEntries(for: ctx)
        let holdCount = rawLog.filter {
            ($0["type"] as? String) == "automation_safe_point_hold" &&
            ($0["run_id"] as? String) == prepared.launchRef &&
            ($0["injection_id"] as? String) == "guidance-automation-safe-point-2"
        }.count

        #expect(first.state == .blocked)
        #expect(second.state == .running)
        #expect(holdCount == 1)
    }

    private func makeProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-automation-run-coordinator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-pr-review",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "nightly triage + code review + summary delivery",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:schedule/nightly",
                "xt.automation_trigger_envelope.v1:webhook/github_pr"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l2,
            laneStrategy: .adaptive,
            requiredToolGroups: ["group:full", "group:device_automation"],
            requiresTrustedAutomation: true,
            trustedDeviceID: "device://trusted/project-a",
            workspaceBindingHash: "sha256:workspace-binding-project-a",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_100_000_000,
            lastEditAuditRef: "audit-xt-auto-bind-001",
            lastLaunchRef: ""
        )
    }

    private func makeRequest(now: Date) -> XTAutomationRunRequest {
        XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "schedule/nightly",
                    triggerType: .schedule,
                    source: .timer,
                    payloadRef: "local://trigger-payload/20260310-001",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: "sha256:schedule-nightly-20260310"
                ),
                XTAutomationTriggerSeed(
                    triggerID: "webhook/github_pr",
                    triggerType: .webhook,
                    source: .github,
                    payloadRef: "local://trigger-payload/20260310-002",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: "sha256:webhook-github-pr-20260310"
                )
            ],
            blockedTaskID: "XT-W3-25-C",
            upstreamDependencyIDs: ["Hub-Wx", "XT-Wy"],
            additionalEvidenceRefs: [
                "build/reports/xt_w3_25_hub_dependency_readiness.v1.json"
            ],
            now: now
        )
    }

    private func rawLogEntries(for ctx: AXProjectContext) throws -> [[String: Any]] {
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
}
