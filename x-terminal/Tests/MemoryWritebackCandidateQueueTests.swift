import Foundation
import Testing
@testable import XTerminal

actor MemoryWritebackCandidateQueueRecorder {
    private var listRequests: [(String?, Int, Double)] = []
    private var decisionRequests: [(String, String, HubIPCClient.MemoryWritebackCandidateDecisionPayload, Double)] = []
    private var maintenanceRequests: [(HubIPCClient.MemoryWritebackCandidateMaintenancePayload, Double)] = []
    private var objectRequests: [(String, Double)] = []

    func appendList(projectId: String?, limit: Int, timeoutSec: Double) {
        listRequests.append((projectId, limit, timeoutSec))
    }

    func appendDecision(
        action: String,
        memoryId: String,
        payload: HubIPCClient.MemoryWritebackCandidateDecisionPayload,
        timeoutSec: Double
    ) {
        decisionRequests.append((action, memoryId, payload, timeoutSec))
    }

    func appendMaintenance(
        payload: HubIPCClient.MemoryWritebackCandidateMaintenancePayload,
        timeoutSec: Double
    ) {
        maintenanceRequests.append((payload, timeoutSec))
    }

    func lists() -> [(String?, Int, Double)] {
        listRequests
    }

    func decisions() -> [(String, String, HubIPCClient.MemoryWritebackCandidateDecisionPayload, Double)] {
        decisionRequests
    }

    func appendObject(memoryId: String, timeoutSec: Double) {
        objectRequests.append((memoryId, timeoutSec))
    }

    func maintenance() -> [(HubIPCClient.MemoryWritebackCandidateMaintenancePayload, Double)] {
        maintenanceRequests
    }

    func objects() -> [(String, Double)] {
        objectRequests
    }
}
struct MemoryWritebackCandidateQueueTests {
    @Test
    func rustCandidateListResponseDecodesPendingObject() throws {
        let json = """
        {
          "schema_version": "xhub.memory.writeback_candidate.v1",
          "ok": true,
          "status": "ok",
          "candidate_count": 1,
          "candidate_diagnostics": {
            "schema_version": "xhub.memory.writeback_candidate_diagnostics.v1",
            "ready": true,
            "candidate_count": 1,
            "conflict_candidate_count": 1,
            "stale_review_required_count": 1,
            "superseding_candidate_count": 1,
            "archived_superseded_count": 1,
            "queue_pressure": "high",
            "noise_score": 10,
            "production_authority_change": false
          },
          "objects": [{
            "schema_version": "xhub.memory.object.v1",
            "memory_id": "mc_test_decision",
            "scope": "project",
            "project_id": "project_alpha",
            "source_kind": "decision_track",
            "layer": "l1_canonical",
            "title": "Decision candidate",
            "text": "Decision: keep writes approval-gated.",
            "summary": "Keep writes approval-gated.",
            "sensitivity": "internal",
            "visibility": "local_only",
            "status": "candidate",
            "ttl_ms": 604800000,
            "created_at_ms": 1779660000000,
            "updated_at_ms": 1779660000000,
            "version": 1,
            "policy": {
              "conflict_with": ["mem_active_decision"],
              "conflict_resolution_required": true,
              "candidate_generation": 2
            },
            "provenance": {
              "stale_review_required": true,
              "supersedes": ["mem_old_candidate"]
            }
          }],
          "candidate_writeback": {
            "enabled": true,
            "authority": "rust_policy_gated_candidate_queue",
            "production_authority_change": false
          }
        }
        """

        let result = try JSONDecoder().decode(
            HubIPCClient.MemoryWritebackCandidateListResult.self,
            from: Data(json.utf8)
        )

        #expect(result.ok)
        #expect(result.candidateCount == 1)
        #expect(result.objects.first?.memoryId == "mc_test_decision")
        #expect(result.objects.first?.status == "candidate")
        #expect(result.candidateDiagnostics?.conflictCandidateCount == 1)
        #expect(result.candidateDiagnostics?.staleReviewRequiredCount == 1)
        #expect(result.candidateDiagnostics?.queuePressure == "high")
        #expect(result.objects.first?.hasConflict == true)
        #expect(result.objects.first?.requiresStaleReview == true)
        #expect(result.objects.first?.supersedesMemoryIds == ["mem_old_candidate"])
        #expect(result.candidateWriteback?.productionAuthorityChange == false)
    }

    @Test
    func rustMemoryObjectResultDecodesReferencedObject() throws {
        let json = """
        {
          "schema_version": "xhub.memory.object_result.v1",
          "ok": true,
          "status": "ok",
          "memory_id": "mem_active_decision",
          "object": {
            "schema_version": "xhub.memory.object.v1",
            "memory_id": "mem_active_decision",
            "scope": "project",
            "project_id": "project_alpha",
            "source_kind": "decision_track",
            "layer": "l1_canonical",
            "title": "Active decision",
            "text": "Existing active memory.",
            "summary": "Existing active memory.",
            "sensitivity": "internal",
            "visibility": "local_only",
            "status": "active",
            "ttl_ms": 0,
            "created_at_ms": 1779660000000,
            "updated_at_ms": 1779660000000,
            "version": 3,
            "policy": {},
            "provenance": {}
          }
        }
        """

        let result = try JSONDecoder().decode(
            HubIPCClient.MemoryObjectResult.self,
            from: Data(json.utf8)
        )

        #expect(result.ok)
        #expect(result.memoryId == "mem_active_decision")
        #expect(result.object?.status == "active")
        #expect(result.object?.title == "Active decision")
        #expect(XTMemoryWritebackCandidateQueuePresentation.bodyPreview(for: try #require(result.object)) == "Existing active memory.")
    }

    @Test
    func rustCandidateMaintenanceResponseDecodesPlanWithoutContent() throws {
        let json = """
        {
          "schema_version": "xhub.memory.writeback_candidate_maintenance.v1",
          "ok": true,
          "status": "ok",
          "project_id": "project_alpha",
          "apply_requested": false,
          "dry_run": true,
          "applied": false,
          "limit": 100,
          "candidate_count": 2,
          "stale_count": 1,
          "archived_count": 0,
          "planned_archive_count": 1,
          "stale_review_required_count": 0,
          "planned_stale_review_required_count": 1,
          "skipped_count": 1,
          "mutation_count": 0,
          "items": [{
            "memory_id": "mc_stale",
            "project_id": "project_alpha",
            "source_kind": "decision_track",
            "layer": "l1_canonical",
            "current_status": "candidate",
            "planned_status": "archived",
            "operation": "archive",
            "reason_code": "low_risk_candidate_stale",
            "age_ms": 604800001,
            "ttl_ms": 604800000,
            "applied": false
          }],
          "candidate_writeback": {
            "enabled": true,
            "authority": "rust_policy_gated_candidate_queue",
            "active_write": false,
            "production_authority_change": false
          },
          "production_authority_change": false
        }
        """

        let result = try JSONDecoder().decode(
            HubIPCClient.MemoryWritebackCandidateMaintenanceResult.self,
            from: Data(json.utf8)
        )

        #expect(result.ok)
        #expect(result.dryRun == true)
        #expect(result.plannedArchiveCount == 1)
        #expect(result.plannedStaleReviewRequiredCount == 1)
        #expect(result.items.first?.operation == "archive")
        #expect(result.items.first?.memoryId == "mc_stale")
        #expect(result.candidateWriteback?.activeWrite == false)
        #expect(result.productionAuthorityChange == false)
    }

    @MainActor
    @Test
    func queueStoreRefreshProjectsPendingNotActiveTruth() async throws {
        let root = try makeProjectRoot(named: "candidate-queue-refresh")
        let ctx = AXProjectContext(root: root)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let recorder = MemoryWritebackCandidateQueueRecorder()
        let candidate = makeCandidate(projectId: projectId)

        HubIPCClient.installMemoryWritebackCandidateListOverrideForTesting { requestedProjectId, limit, timeoutSec in
            await recorder.appendList(projectId: requestedProjectId, limit: limit, timeoutSec: timeoutSec)
            return HubIPCClient.MemoryWritebackCandidateListResult(
                ok: true,
                source: "rust_http",
                status: "ok",
                candidateCount: 1,
                objects: [candidate],
                candidateWriteback: HubIPCClient.MemoryWritebackCandidateWriteback(
                    enabled: true,
                    authority: "rust_policy_gated_candidate_queue",
                    requiresApproval: true,
                    activeWrite: false,
                    productionAuthorityChange: false
                )
            )
        }
        defer { HubIPCClient.resetMemoryWritebackCandidateQueueOverridesForTesting() }

        let store = XTMemoryWritebackCandidateQueueStore()
        await store.refresh(projectId: projectId, limit: 10, timeoutSec: 0.25)

        #expect(store.snapshot.pendingCount == 1)
        #expect(store.snapshot.candidates.first?.status == "candidate")
        #expect(XTMemoryWritebackCandidateQueuePresentation.statusText(snapshot: store.snapshot) == "1 pending")
        let lists = await recorder.lists()
        #expect(lists.count == 1)
        #expect(lists.first?.0 == projectId)
        #expect(lists.first?.1 == 10)
        _ = ctx
    }

    @Test
    func queuePresentationUsesRustDiagnosticsAndCandidateMetadata() {
        var candidate = makeCandidate(projectId: "project_diag")
        candidate.policy = HubIPCClient.MemoryWritebackCandidateMetadata(
            conflictWith: ["mem_active"],
            conflictResolutionRequired: true
        )
        candidate.provenance = HubIPCClient.MemoryWritebackCandidateMetadata(
            supersedes: ["mem_old"],
            staleReviewRequired: true
        )
        let snapshot = XTMemoryWritebackCandidateQueueSnapshot(
            projectId: "project_diag",
            candidates: [candidate],
            candidateDiagnostics: HubIPCClient.MemoryWritebackCandidateDiagnostics(
                candidateCount: 1,
                conflictCandidateCount: 1,
                staleReviewRequiredCount: 1,
                supersededCandidateCount: 1,
                queuePressure: "high",
                productionAuthorityChange: false
            ),
            loading: false,
            inFlightMemoryId: nil,
            lastUpdatedAt: nil,
            lastError: nil,
            lastDecision: nil
        )

        #expect(snapshot.conflictCount == 1)
        #expect(snapshot.staleReviewRequiredCount == 1)
        #expect(snapshot.supersededCount == 1)
        #expect(XTMemoryWritebackCandidateQueuePresentation.statusText(snapshot: snapshot) == "1 pending · 1 conflict · 1 stale review · 1 superseded")
        #expect(XTMemoryWritebackCandidateQueuePresentation.metadataLine(for: candidate).contains("conflict"))
        #expect(XTMemoryWritebackCandidateQueuePresentation.metadataLine(for: candidate).contains("stale review"))
        #expect(XTMemoryWritebackCandidateQueuePresentation.metadataLine(for: candidate).contains("supersedes 1"))
        #expect(XTMemoryWritebackCandidateQueuePresentation.stalenessLabel(for: candidate) == "conflict")
    }

    @MainActor
    @Test
    func conflictApproveRequiresAndSendsResolutionReason() async throws {
        let root = try makeProjectRoot(named: "candidate-queue-conflict-approve")
        let ctx = AXProjectContext(root: root)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        var candidateDraft = makeCandidate(projectId: projectId)
        candidateDraft.policy = HubIPCClient.MemoryWritebackCandidateMetadata(
            conflictWith: ["mem_active"],
            conflictResolutionRequired: true
        )
        let candidate = candidateDraft
        let recorder = MemoryWritebackCandidateQueueRecorder()

        HubIPCClient.installMemoryWritebackCandidateListOverrideForTesting { _, _, _ in
            HubIPCClient.MemoryWritebackCandidateListResult(
                ok: true,
                source: "rust_http",
                status: "ok",
                candidateCount: 1,
                objects: [candidate]
            )
        }
        HubIPCClient.installMemoryWritebackCandidateDecisionOverrideForTesting { action, memoryId, payload, timeoutSec in
            await recorder.appendDecision(
                action: action,
                memoryId: memoryId,
                payload: payload,
                timeoutSec: timeoutSec
            )
            return HubIPCClient.MemoryWritebackCandidateDecisionResult(
                ok: true,
                source: "rust_http",
                status: "approved",
                memoryId: memoryId,
                version: 2,
                eventId: "evt_conflict_approve",
                action: action,
                transition: HubIPCClient.MemoryWritebackCandidateDecisionTransition(
                    operation: action,
                    fromStatus: "candidate",
                    toStatus: "active",
                    candidateWriteback: true
                ),
                object: candidate,
                productionAuthorityChange: false
            )
        }
        defer { HubIPCClient.resetMemoryWritebackCandidateQueueOverridesForTesting() }

        let store = XTMemoryWritebackCandidateQueueStore()
        await store.approve(
            candidate: candidate,
            ctx: ctx,
            conflictResolutionReason: "   ",
            timeoutSec: 0.25
        )
        #expect(store.snapshot.lastError == "conflict_resolution_reason_required")
        let deniedDecisions = await recorder.decisions()
        #expect(deniedDecisions.isEmpty)

        await store.approve(
            candidate: candidate,
            ctx: ctx,
            conflictResolutionReason: "Reviewer accepts the replacement decision.",
            timeoutSec: 0.25
        )

        let decisions = await recorder.decisions()
        #expect(decisions.count == 1)
        #expect(decisions[0].0 == "approve")
        #expect(decisions[0].2.conflictResolutionReason == "Reviewer accepts the replacement decision.")

        let rawLog = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
        #expect(rawLog.contains("\"conflict_resolution_required\":true"))
        #expect(rawLog.contains("\"conflict_with\":\"mem_active\""))
    }

    @MainActor
    @Test
    func approveAndRejectCallRustDecisionPathAndWriteEvidence() async throws {
        let root = try makeProjectRoot(named: "candidate-queue-decision")
        let ctx = AXProjectContext(root: root)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let candidate = makeCandidate(projectId: projectId)
        let recorder = MemoryWritebackCandidateQueueRecorder()

        HubIPCClient.installMemoryWritebackCandidateListOverrideForTesting { _, _, _ in
            HubIPCClient.MemoryWritebackCandidateListResult(
                ok: true,
                source: "rust_http",
                status: "ok",
                candidateCount: 1,
                objects: [candidate]
            )
        }
        HubIPCClient.installMemoryWritebackCandidateDecisionOverrideForTesting { action, memoryId, payload, timeoutSec in
            await recorder.appendDecision(
                action: action,
                memoryId: memoryId,
                payload: payload,
                timeoutSec: timeoutSec
            )
            return HubIPCClient.MemoryWritebackCandidateDecisionResult(
                ok: true,
                source: "rust_http",
                status: action == "approve" ? "approved" : "rejected",
                memoryId: memoryId,
                version: 2,
                eventId: "evt_\(action)",
                action: action,
                transition: HubIPCClient.MemoryWritebackCandidateDecisionTransition(
                    operation: action,
                    fromStatus: "candidate",
                    toStatus: action == "approve" ? "active" : "rejected",
                    candidateWriteback: true
                ),
                object: candidate,
                productionAuthorityChange: false
            )
        }
        defer { HubIPCClient.resetMemoryWritebackCandidateQueueOverridesForTesting() }

        let store = XTMemoryWritebackCandidateQueueStore()
        await store.approve(candidate: candidate, ctx: ctx, timeoutSec: 0.25)
        await store.reject(candidate: candidate, ctx: ctx, timeoutSec: 0.25)

        let decisions = await recorder.decisions()
        #expect(decisions.count == 2)
        #expect(decisions[0].0 == "approve")
        #expect(decisions[0].1 == candidate.memoryId)
        #expect(decisions[0].2.auditRef.contains(":approve:"))
        #expect(decisions[0].2.requesterRole == "tool")
        #expect(decisions[0].2.useMode == "tool_plan")
        #expect(decisions[1].0 == "reject")
        #expect(decisions[1].1 == candidate.memoryId)
        #expect(decisions[1].2.auditRef.contains(":reject:"))

        let rawLog = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
        #expect(rawLog.contains("\"type\":\"memory_writeback_candidate_review\""))
        #expect(rawLog.contains("\"production_authority_change\":false"))
        #expect(rawLog.contains("\"action\":\"approve\""))
        #expect(rawLog.contains("\"action\":\"reject\""))
    }

    @MainActor
    @Test
    func mergeReviewLoadsConflictAndSupersedesObjectsWithoutAuthorityChange() async throws {
        let root = try makeProjectRoot(named: "candidate-queue-merge-review")
        let ctx = AXProjectContext(root: root)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        var candidate = makeCandidate(projectId: projectId)
        candidate.policy = HubIPCClient.MemoryWritebackCandidateMetadata(
            conflictWith: ["mem_active"],
            conflictResolutionRequired: true
        )
        candidate.provenance = HubIPCClient.MemoryWritebackCandidateMetadata(
            supersedes: ["mem_old"]
        )
        let active = makeCandidate(
            projectId: projectId,
            text: "Active canonical decision."
        ).withMemoryId("mem_active", status: "active", title: "Active decision")
        let old = makeCandidate(
            projectId: projectId,
            text: "Old pending decision."
        ).withMemoryId("mem_old", status: "candidate", title: "Old candidate")
        let recorder = MemoryWritebackCandidateQueueRecorder()

        HubIPCClient.installMemoryObjectGetOverrideForTesting { memoryId, timeoutSec in
            await recorder.appendObject(memoryId: memoryId, timeoutSec: timeoutSec)
            let object: HubIPCClient.MemoryWritebackCandidateObject? = {
                switch memoryId {
                case "mem_active": return active
                case "mem_old": return old
                default: return nil
                }
            }()
            return HubIPCClient.MemoryObjectResult(
                ok: object != nil,
                source: "rust_http",
                status: object == nil ? "not_found" : "ok",
                memoryId: memoryId,
                object: object,
                reasonCode: object == nil ? "memory_object_not_found" : nil
            )
        }
        defer { HubIPCClient.resetMemoryWritebackCandidateQueueOverridesForTesting() }

        let ids = XTMemoryWritebackCandidateQueuePresentation.mergeReferenceIds(for: candidate)
        #expect(ids == ["mem_active", "mem_old"])

        let store = XTMemoryWritebackCandidateQueueStore()
        await store.loadMergeReview(candidate: candidate, ctx: ctx, timeoutSec: 0.25)

        let requests = await recorder.objects()
        #expect(requests.map(\.0) == ["mem_active", "mem_old"])
        let review = try #require(store.snapshot.mergeReviews[candidate.memoryId])
        #expect(review.objects.map(\.memoryId) == ["mem_active", "mem_old"])
        #expect(review.missingIds.isEmpty)
        #expect(XTMemoryWritebackCandidateQueuePresentation.mergeReviewStatusText(review) == "loaded 2")
        #expect(XTMemoryWritebackCandidateQueuePresentation.mergeReviewLine(for: active).contains("active"))

        let rawLog = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
        #expect(rawLog.contains("\"type\":\"memory_writeback_candidate_merge_review\""))
        #expect(rawLog.contains("\"reference_count\":2"))
        #expect(!rawLog.contains("Active canonical decision."))
    }

    @MainActor
    @Test
    func maintenancePreviewIsRequiredBeforeApplyAndWritesEvidence() async throws {
        let root = try makeProjectRoot(named: "candidate-queue-maintenance")
        let ctx = AXProjectContext(root: root)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let candidate = makeCandidate(projectId: projectId)
        let recorder = MemoryWritebackCandidateQueueRecorder()

        HubIPCClient.installMemoryWritebackCandidateListOverrideForTesting { _, _, _ in
            HubIPCClient.MemoryWritebackCandidateListResult(
                ok: true,
                source: "rust_http",
                status: "ok",
                candidateCount: 1,
                objects: [candidate]
            )
        }
        HubIPCClient.installMemoryWritebackCandidateMaintenanceOverrideForTesting { payload, timeoutSec in
            await recorder.appendMaintenance(payload: payload, timeoutSec: timeoutSec)
            return HubIPCClient.MemoryWritebackCandidateMaintenanceResult(
                ok: true,
                source: "rust_http",
                status: "ok",
                projectId: payload.projectId,
                applyRequested: payload.apply,
                dryRun: payload.dryRun,
                applied: payload.apply,
                limit: payload.limit,
                candidateCount: 1,
                staleCount: 1,
                archivedCount: payload.apply ? 1 : 0,
                plannedArchiveCount: 1,
                staleReviewRequiredCount: 0,
                plannedStaleReviewRequiredCount: 0,
                skippedCount: 0,
                mutationCount: payload.apply ? 1 : 0,
                items: [
                    HubIPCClient.MemoryWritebackCandidateMaintenanceItem(
                        memoryId: candidate.memoryId,
                        projectId: projectId,
                        sourceKind: "decision_track",
                        layer: "l1_canonical",
                        currentStatus: "candidate",
                        plannedStatus: "archived",
                        operation: "archive",
                        reasonCode: "low_risk_candidate_stale",
                        ageMs: 604_800_001,
                        ttlMs: 604_800_000,
                        applied: payload.apply,
                        eventId: payload.apply ? "evt_maintenance" : nil
                    )
                ],
                candidateWriteback: HubIPCClient.MemoryWritebackCandidateWriteback(
                    enabled: true,
                    authority: "rust_policy_gated_candidate_queue",
                    requiresApproval: true,
                    activeWrite: false,
                    productionAuthorityChange: false
                ),
                productionAuthorityChange: false
            )
        }
        defer { HubIPCClient.resetMemoryWritebackCandidateQueueOverridesForTesting() }

        let store = XTMemoryWritebackCandidateQueueStore()
        await store.applyMaintenance(ctx: ctx, timeoutSec: 0.25)
        #expect(store.snapshot.lastError == "memory_writeback_candidate_maintenance_preview_required")
        #expect(await recorder.maintenance().isEmpty)

        await store.previewMaintenance(ctx: ctx, timeoutSec: 0.25)
        #expect(store.snapshot.lastMaintenance?.dryRun == true)
        #expect(store.snapshot.plannedMaintenanceCount == 1)
        #expect(XTMemoryWritebackCandidateQueuePresentation.maintenanceStatusText(snapshot: store.snapshot) == "预检 · 1 planned")

        await store.applyMaintenance(ctx: ctx, timeoutSec: 0.25)
        #expect(store.snapshot.lastMaintenance?.applied == true)
        #expect(store.snapshot.lastMaintenance?.mutationCount == 1)
        #expect(XTMemoryWritebackCandidateQueuePresentation.maintenanceStatusText(snapshot: store.snapshot) == "已应用 · mutation 1")

        let maintenanceRequests = await recorder.maintenance()
        #expect(maintenanceRequests.count == 2)
        #expect(maintenanceRequests[0].0.projectId == projectId)
        #expect(maintenanceRequests[0].0.dryRun == true)
        #expect(maintenanceRequests[0].0.apply == false)
        #expect(maintenanceRequests[1].0.apply == true)
        #expect(maintenanceRequests[1].0.dryRun == false)

        let rawLog = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
        #expect(rawLog.contains("\"type\":\"memory_writeback_candidate_maintenance\""))
        #expect(rawLog.contains("\"planned_archive_count\":1"))
        #expect(rawLog.contains("\"production_authority_change\":false"))
    }

    @Test
    func secretCandidatePreviewIsHiddenByDefault() {
        let candidate = makeCandidate(
            projectId: "project_secret",
            sensitivity: "secret",
            text: "api_key_live_should_not_render"
        )

        #expect(candidate.redactedContentByDefault)
        #expect(XTMemoryWritebackCandidateQueuePresentation.bodyPreview(for: candidate) == "content hidden by policy")
    }

    private func makeCandidate(
        projectId: String,
        sensitivity: String = "internal",
        text: String = "Decision: approve memory candidates only through Rust Hub."
    ) -> HubIPCClient.MemoryWritebackCandidateObject {
        HubIPCClient.MemoryWritebackCandidateObject(
            schemaVersion: "xhub.memory.object.v1",
            memoryId: "mc_test_candidate",
            scope: "project",
            ownerId: nil,
            runId: nil,
            projectId: projectId,
            agentId: nil,
            sourceKind: "decision_track",
            layer: "l1_canonical",
            title: "Decision candidate",
            text: text,
            summary: "Approve memory candidates only through Rust Hub.",
            sensitivity: sensitivity,
            visibility: "local_only",
            status: "candidate",
            pinned: false,
            immutable: false,
            ttlMs: 604_800_000,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            lastAccessedAtMs: nil,
            version: 1
        )
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private extension HubIPCClient.MemoryWritebackCandidateObject {
    func withMemoryId(
        _ memoryId: String,
        status: String,
        title: String
    ) -> HubIPCClient.MemoryWritebackCandidateObject {
        var copy = self
        copy.memoryId = memoryId
        copy.status = status
        copy.title = title
        return copy
    }
}
