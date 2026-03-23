import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct SupervisorIncidentExportTests {
    private static let gate = HubGlobalStateTestGate.shared

    @MainActor
    @Test
    func buildXTReadyIncidentEventsFiltersHandledRequiredCodes() {
        let incidents = [
            makeIncident(
                code: LaneBlockedReason.grantPending.rawValue,
                laneID: "lane-2",
                status: .handled,
                detectedAt: 100,
                handledAt: 1_500
            ),
            makeIncident(
                code: LaneBlockedReason.awaitingInstruction.rawValue,
                laneID: "lane-3",
                status: .handled,
                detectedAt: 200,
                handledAt: 1_200
            ),
            makeIncident(
                code: LaneBlockedReason.quotaExceeded.rawValue,
                laneID: "lane-x",
                status: .handled,
                detectedAt: 300,
                handledAt: 1_100
            ),
            makeIncident(
                code: LaneBlockedReason.runtimeError.rawValue,
                laneID: "lane-4",
                status: .detected,
                detectedAt: 400,
                handledAt: nil
            ),
        ]

        let events = SupervisorManager.buildXTReadyIncidentEvents(from: incidents, limit: 20)

        #expect(events.count == 2)
        #expect(events.map(\.incidentCode) == [
            LaneBlockedReason.awaitingInstruction.rawValue,
            LaneBlockedReason.grantPending.rawValue,
        ])
        #expect(events[0].eventType == "supervisor.incident.awaiting_instruction.handled")
        #expect(events[1].denyCode == LaneBlockedReason.grantPending.rawValue)
    }

    @MainActor
    @Test
    func missingXTReadyIncidentCodesReportsRequiredGaps() {
        let grantOnly = XTReadyIncidentEvent(
            eventType: "supervisor.incident.grant_pending.handled",
            incidentCode: LaneBlockedReason.grantPending.rawValue,
            laneID: "lane-2",
            detectedAtMs: 100,
            handledAtMs: 500,
            denyCode: LaneBlockedReason.grantPending.rawValue,
            auditEventType: "supervisor.incident.handled",
            auditRef: "audit-grant",
            takeoverLatencyMs: 400
        )

        let missing = SupervisorManager.missingXTReadyIncidentCodes(in: [grantOnly])
        #expect(missing == [
            LaneBlockedReason.awaitingInstruction.rawValue,
            LaneBlockedReason.runtimeError.rawValue,
        ])
    }

    @MainActor
    @Test
    func evaluateXTReadyIncidentReadinessPassesWhenStrictContractValid() {
        let events = [
            makeEvent(
                code: LaneBlockedReason.grantPending.rawValue,
                laneID: "lane-1",
                detectedAtMs: 100,
                handledAtMs: 900,
                denyCode: LaneBlockedReason.grantPending.rawValue,
                auditRef: "audit-grant",
                takeoverLatencyMs: 800
            ),
            makeEvent(
                code: LaneBlockedReason.awaitingInstruction.rawValue,
                laneID: "lane-2",
                detectedAtMs: 200,
                handledAtMs: 800,
                denyCode: LaneBlockedReason.awaitingInstruction.rawValue,
                auditRef: "audit-await",
                takeoverLatencyMs: 600
            ),
            makeEvent(
                code: LaneBlockedReason.runtimeError.rawValue,
                laneID: "lane-3",
                detectedAtMs: 300,
                handledAtMs: 1_300,
                denyCode: LaneBlockedReason.runtimeError.rawValue,
                auditRef: "audit-runtime",
                takeoverLatencyMs: 1_000
            ),
        ]

        let readiness = SupervisorManager.evaluateXTReadyIncidentReadiness(events: events)
        #expect(readiness.ready)
        #expect(readiness.issues.isEmpty)
    }

    @MainActor
    @Test
    func evaluateXTReadyIncidentReadinessFailsWhenRequiredIncidentMissing() {
        let events = [
            makeEvent(
                code: LaneBlockedReason.grantPending.rawValue,
                laneID: "lane-1",
                detectedAtMs: 100,
                handledAtMs: 900,
                denyCode: LaneBlockedReason.grantPending.rawValue,
                auditRef: "audit-grant",
                takeoverLatencyMs: 800
            ),
            makeEvent(
                code: LaneBlockedReason.awaitingInstruction.rawValue,
                laneID: "lane-2",
                detectedAtMs: 200,
                handledAtMs: 800,
                denyCode: LaneBlockedReason.awaitingInstruction.rawValue,
                auditRef: "audit-await",
                takeoverLatencyMs: 600
            ),
        ]

        let readiness = SupervisorManager.evaluateXTReadyIncidentReadiness(events: events)
        #expect(readiness.ready == false)
        #expect(readiness.issues.contains("\(LaneBlockedReason.runtimeError.rawValue):missing_incident"))
    }

    @MainActor
    @Test
    func evaluateXTReadyIncidentReadinessFailsOnEventTypeAndDenyCodeMismatch() {
        let events = [
            makeEvent(
                code: LaneBlockedReason.grantPending.rawValue,
                laneID: "lane-1",
                detectedAtMs: 100,
                handledAtMs: 900,
                eventType: "supervisor.incident.grant_pending.detected",
                denyCode: LaneBlockedReason.awaitingInstruction.rawValue,
                auditRef: "audit-grant",
                takeoverLatencyMs: 800
            ),
            makeEvent(
                code: LaneBlockedReason.awaitingInstruction.rawValue,
                laneID: "lane-2",
                detectedAtMs: 200,
                handledAtMs: 800,
                denyCode: LaneBlockedReason.awaitingInstruction.rawValue,
                auditRef: "audit-await",
                takeoverLatencyMs: 600
            ),
            makeEvent(
                code: LaneBlockedReason.runtimeError.rawValue,
                laneID: "lane-3",
                detectedAtMs: 300,
                handledAtMs: 1_300,
                denyCode: LaneBlockedReason.runtimeError.rawValue,
                auditRef: "audit-runtime",
                takeoverLatencyMs: 1_000
            ),
        ]

        let readiness = SupervisorManager.evaluateXTReadyIncidentReadiness(events: events)
        #expect(readiness.ready == false)
        #expect(readiness.issues.contains("\(LaneBlockedReason.grantPending.rawValue):event_type_mismatch"))
        #expect(readiness.issues.contains("\(LaneBlockedReason.grantPending.rawValue):deny_code_mismatch"))
    }

    @MainActor
    @Test
    func evaluateXTReadyIncidentReadinessFailsWhenAuditRefMissing() {
        let events = [
            makeEvent(
                code: LaneBlockedReason.grantPending.rawValue,
                laneID: "lane-1",
                detectedAtMs: 100,
                handledAtMs: 900,
                denyCode: LaneBlockedReason.grantPending.rawValue,
                auditRef: "audit-grant",
                takeoverLatencyMs: 800
            ),
            makeEvent(
                code: LaneBlockedReason.awaitingInstruction.rawValue,
                laneID: "lane-2",
                detectedAtMs: 200,
                handledAtMs: 800,
                denyCode: LaneBlockedReason.awaitingInstruction.rawValue,
                auditRef: "",
                takeoverLatencyMs: 600
            ),
            makeEvent(
                code: LaneBlockedReason.runtimeError.rawValue,
                laneID: "lane-3",
                detectedAtMs: 300,
                handledAtMs: 1_300,
                denyCode: LaneBlockedReason.runtimeError.rawValue,
                auditRef: "audit-runtime",
                takeoverLatencyMs: 1_000
            ),
        ]

        let readiness = SupervisorManager.evaluateXTReadyIncidentReadiness(events: events)
        #expect(readiness.ready == false)
        #expect(readiness.issues.contains("\(LaneBlockedReason.awaitingInstruction.rawValue):audit_ref_missing"))
    }

    @MainActor
    @Test
    func evaluateXTReadyIncidentReadinessFailsWhenTakeoverLatencyExceedsThreshold() {
        let events = [
            makeEvent(
                code: LaneBlockedReason.grantPending.rawValue,
                laneID: "lane-1",
                detectedAtMs: 100,
                handledAtMs: 900,
                denyCode: LaneBlockedReason.grantPending.rawValue,
                auditRef: "audit-grant",
                takeoverLatencyMs: 2_100
            ),
            makeEvent(
                code: LaneBlockedReason.awaitingInstruction.rawValue,
                laneID: "lane-2",
                detectedAtMs: 200,
                handledAtMs: 800,
                denyCode: LaneBlockedReason.awaitingInstruction.rawValue,
                auditRef: "audit-await",
                takeoverLatencyMs: 600
            ),
            makeEvent(
                code: LaneBlockedReason.runtimeError.rawValue,
                laneID: "lane-3",
                detectedAtMs: 300,
                handledAtMs: 1_300,
                denyCode: LaneBlockedReason.runtimeError.rawValue,
                auditRef: "audit-runtime",
                takeoverLatencyMs: 1_000
            ),
        ]

        let readiness = SupervisorManager.evaluateXTReadyIncidentReadiness(events: events)
        #expect(readiness.ready == false)
        #expect(readiness.issues.contains("\(LaneBlockedReason.grantPending.rawValue):takeover_latency_exceeded"))
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSnapshotIncludesMemoryAssemblyRisk() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_memory_risk_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(
                makeMemorySnapshot(
                    profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                    resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue
                )
            )

            let snapshot = manager.xtReadyIncidentExportSnapshot(limit: 20)

            #expect(snapshot.memoryAssemblyReady == false)
            #expect(snapshot.memoryAssemblyIssues.contains("memory_review_floor_not_met"))
            #expect(snapshot.strictE2EReady == false)
            #expect(snapshot.strictE2EIssues.contains("memory:memory_review_floor_not_met"))
        }
    }

    @MainActor
    @Test
    func exportReportPersistsMemoryAssemblySummary() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_export_summary_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(
                makeMemorySnapshot(
                    truncatedLayers: ["l1_canonical"],
                    durableCandidateMirrorStatus: .hubMirrorFailed,
                    durableCandidateMirrorTarget: XTSupervisorDurableCandidateMirror.mirrorTarget,
                    durableCandidateMirrorAttempted: true,
                    durableCandidateMirrorErrorCode: "remote_route_not_preferred"
                )
            )

            let outputURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("xt_ready_incident_export_\(UUID().uuidString).json")
            let result = manager.exportXTReadyIncidentEventsReport(outputURL: outputURL, limit: 20)
            #expect(result.ok)

            let data = try Data(contentsOf: outputURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let summary = json?["summary"] as? [String: Any]

            #expect((summary?["memory_assembly_ready"] as? Bool) == false)
            #expect((summary?["memory_assembly_issue_count"] as? Int) == 1)
            #expect((summary?["memory_assembly_requested_profile"] as? String) == XTMemoryServingProfile.m3DeepDive.rawValue)
            #expect((summary?["memory_assembly_resolved_profile"] as? String) == XTMemoryServingProfile.m3DeepDive.rawValue)
            #expect((summary?["memory_assembly_truncated_layer_count"] as? Int) == 1)
            #expect((summary?["durable_candidate_mirror_status"] as? String) == SupervisorDurableCandidateMirrorStatus.hubMirrorFailed.rawValue)
            #expect((summary?["durable_candidate_mirror_target"] as? String) == XTSupervisorDurableCandidateMirror.mirrorTarget)
            #expect((summary?["durable_candidate_mirror_attempted"] as? Bool) == true)
            #expect((summary?["durable_candidate_mirror_error_code"] as? String) == "remote_route_not_preferred")
            #expect((summary?["durable_candidate_local_store_role"] as? String) == XTSupervisorDurableCandidateMirror.localStoreRole)
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSnapshotCarriesContinuityDrillDownWhenNotable() async {
        await Self.gate.runOnMainActor { @MainActor in
            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(
                SupervisorMemoryAssemblySnapshot(
                    source: "unit_test",
                    resolutionSource: "unit_test",
                    updatedAt: 1_773_000_000,
                    reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
                    requestedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
                    profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                    resolvedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
                    attemptedProfiles: [XTMemoryServingProfile.m3DeepDive.rawValue],
                    progressiveUpgradeCount: 0,
                    focusedProjectId: "project-alpha",
                    rawWindowProfile: XTSupervisorRecentRawContextProfile.standard12Pairs.rawValue,
                    rawWindowFloorPairs: 8,
                    rawWindowCeilingPairs: 12,
                    rawWindowSelectedPairs: 12,
                    eligibleMessages: 24,
                    lowSignalDroppedMessages: 2,
                    rawWindowSource: "mixed",
                    rollingDigestPresent: true,
                    continuityFloorSatisfied: true,
                    truncationAfterFloor: false,
                    continuityTraceLines: [
                        "remote_continuity=ok cache_hit=false working_entries=18 assembled_source=mixed"
                    ],
                    lowSignalDropSampleLines: [
                        "role=user reason=pure_ack_or_greeting text=你好"
                    ],
                    selectedSections: [
                        "dialogue_window",
                        "portfolio_brief",
                        "focused_project_anchor_pack",
                        "longterm_outline",
                        "delta_feed",
                        "conflict_set",
                        "context_refs",
                        "evidence_pack",
                    ],
                    omittedSections: [],
                    contextRefsSelected: 2,
                    contextRefsOmitted: 0,
                    evidenceItemsSelected: 2,
                    evidenceItemsOmitted: 0,
                    budgetTotalTokens: 1_800,
                    usedTotalTokens: 1_050,
                    truncatedLayers: [],
                    freshness: "fresh_remote",
                    cacheHit: false,
                    denyCode: nil,
                    downgradeCode: nil,
                    reasonCode: nil,
                    compressionPolicy: "progressive_disclosure"
                )
            )

            let snapshot = manager.xtReadyIncidentExportSnapshot(limit: 20)

            #expect(snapshot.memoryAssemblyDetailLines.contains(where: { $0.contains("continuity raw_source=mixed") }))
            #expect(
                snapshot.memoryAssemblyDetailLines.contains(where: {
                    $0.contains("continuity_source_label=Hub 快照 + 本地 overlay")
                })
            )
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSnapshotIncludesDurableCandidateMirrorWhenMirroredToHub() async {
        await Self.gate.runOnMainActor { @MainActor in
            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(
                makeMemorySnapshot(
                    durableCandidateMirrorStatus: .mirroredToHub,
                    durableCandidateMirrorTarget: XTSupervisorDurableCandidateMirror.mirrorTarget,
                    durableCandidateMirrorAttempted: true
                )
            )

            let snapshot = manager.xtReadyIncidentExportSnapshot(limit: 20)
            let statusText = manager.renderXTReadyIncidentEventsStatusForTesting()

            #expect(snapshot.durableCandidateMirrorStatus == .mirroredToHub)
            #expect(snapshot.durableCandidateMirrorTarget == XTSupervisorDurableCandidateMirror.mirrorTarget)
            #expect(snapshot.durableCandidateMirrorAttempted)
            #expect(snapshot.durableCandidateLocalStoreRole == XTSupervisorDurableCandidateMirror.localStoreRole)
            #expect(statusText.contains("memory_assembly_status"))
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSummaryIncludesDurableCandidateMirrorFailureDetails() async {
        await Self.gate.runOnMainActor { @MainActor in
            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(
                makeMemorySnapshot(
                    durableCandidateMirrorStatus: .hubMirrorFailed,
                    durableCandidateMirrorTarget: XTSupervisorDurableCandidateMirror.mirrorTarget,
                    durableCandidateMirrorAttempted: true,
                    durableCandidateMirrorErrorCode: "remote_route_not_preferred"
                )
            )

            let summary = manager.renderXTReadyIncidentExportSummaryForTesting(
                .init(
                    ok: true,
                    outputPath: "/tmp/xt_ready_incident_export.json",
                    exportedEventCount: 3,
                    missingIncidentCodes: [],
                    reason: "ok"
                )
            )

            #expect(summary.contains("memory_assembly_status"))
            let snapshot = manager.xtReadyIncidentExportSnapshot(limit: 20)
            #expect(snapshot.durableCandidateMirrorStatus == .hubMirrorFailed)
            #expect(snapshot.durableCandidateMirrorErrorCode == "remote_route_not_preferred")
        }
    }

    @MainActor
    @Test
    func exportReportFallsBackToNonAtomicOverwriteWhenAtomicWriteRunsOutOfSpace() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_export_fallback_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())

            let capture = XTReadyIncidentReportWriteTestCapture()
            let outputURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("xt_ready_incident_export_\(UUID().uuidString).json")
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("{\"stale\":true}\n".utf8).write(to: outputURL)

            manager.installXTReadyIncidentReportWriteAttemptOverrideForTesting { data, url, options in
                capture.appendWriteOption(options)
                if options.contains(.atomic) {
                    throw NSError(domain: NSPOSIXErrorDomain, code: 28)
                }
                try data.write(to: url, options: options)
            }
            defer { manager.resetXTReadyIncidentReportWriteBehaviorForTesting() }

            let result = manager.exportXTReadyIncidentEventsReport(outputURL: outputURL, limit: 20)

            #expect(result.ok)
            let options = capture.writeOptionsSnapshot()
            #expect(options.count == 2)
            #expect(options[0].contains(.atomic))
            #expect(options[1].isEmpty)

            let data = try Data(contentsOf: outputURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect((json?["schema_version"] as? String) == "xt_ready_incident_events.v1")
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentStatusTextIncludesCanonicalRetryFeedback() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_status_retry_feedback_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())
            manager.setCanonicalMemoryRetryFeedbackForTesting(
                .init(
                    statusLine: "canonical_sync_retry: partial ok=1 · failed=1 · waiting=0",
                    detailLine: "failed: project:project-alpha(Alpha) reason=project_canonical_memory_write_failed detail=no space left",
                    metaLine: "attempt: 刚刚 · last_status: 刚刚",
                    tone: .warning
                )
            )

            let text = manager.renderXTReadyIncidentEventsStatusForTesting()

            #expect(text.contains("canonical_sync_retry: partial ok=1 · failed=1 · waiting=0"))
            #expect(text.contains("canonical_sync_retry_meta：attempt: 刚刚 · last_status: 刚刚"))
            #expect(text.contains("canonical_sync_retry_detail：failed: project:project-alpha(Alpha) reason=project_canonical_memory_write_failed detail=no space left"))
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSummaryIncludesCanonicalRetryFeedback() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_export_retry_feedback_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())
            manager.setCanonicalMemoryRetryFeedbackForTesting(
                .init(
                    statusLine: "canonical_sync_retry: ok scopes=2 · projects=1",
                    detailLine: "ok: device:supervisor-main(Supervisor), project:project-alpha(Alpha)",
                    metaLine: "attempt: 刚刚 · last_status: 刚刚",
                    tone: .success
                )
            )

            let summary = manager.renderXTReadyIncidentExportSummaryForTesting(
                .init(
                    ok: true,
                    outputPath: "/tmp/xt-ready.json",
                    exportedEventCount: 3,
                    missingIncidentCodes: [],
                    reason: "ok"
                )
            )

            #expect(summary.contains("canonical_sync_retry: ok scopes=2 · projects=1"))
            #expect(summary.contains("canonical_sync_retry_meta：attempt: 刚刚 · last_status: 刚刚"))
            #expect(summary.contains("canonical_sync_retry_detail：ok: device:supervisor-main(Supervisor), project:project-alpha(Alpha)"))
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSummaryPrependsWorkbenchGovernanceBriefWhenPendingGrantExists() async {
        await Self.gate.runOnMainActor { @MainActor in
            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())
            manager.setPendingHubGrantsForTesting(
                [
                    SupervisorManager.SupervisorPendingGrant(
                        id: "xt-ready-export-grant-1",
                        dedupeKey: "xt-ready-export-grant-1",
                        grantRequestId: "xt-ready-export-grant-1",
                        requestId: "req-xt-ready-export-grant-1",
                        projectId: "project-release",
                        projectName: "Release Runtime",
                        capability: "device_authority",
                        modelId: "",
                        reason: "需要批准设备级权限后继续自动化",
                        requestedTtlSec: 3600,
                        requestedTokenCap: 12_000,
                        createdAt: 1_000,
                        actionURL: nil,
                        priorityRank: 1,
                        priorityReason: "release_path",
                        nextAction: "打开授权并批准设备级权限"
                    )
                ]
            )

            let summary = manager.renderXTReadyIncidentExportSummaryForTesting(
                .init(
                    ok: true,
                    outputPath: "/tmp/xt-ready.json",
                    exportedEventCount: 3,
                    missingIncidentCodes: [],
                    reason: "ok"
                )
            )

            #expect(summary.contains("🧭 Supervisor Brief · 当前工作台"))
            #expect(summary.contains("Hub 待处理授权"))
            #expect(summary.contains("查看：查看授权板"))
            #expect(summary.contains("🧾 XT-Ready incident 事件导出"))
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSnapshotIncludesCanonicalSyncFailureRisk() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_canonical_sync_risk_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            try writeCanonicalSyncStatus(
                HubIPCClient.CanonicalMemorySyncStatusSnapshot(
                    schemaVersion: "canonical_memory_sync_status.v1",
                    updatedAtMs: 1_773_000_020_000,
                    items: [
                        HubIPCClient.CanonicalMemorySyncStatusItem(
                            scopeKind: "project",
                            scopeId: "project-alpha",
                            displayName: "Alpha",
                            source: "file_ipc",
                            ok: false,
                            updatedAtMs: 1_773_000_020_000,
                            reasonCode: "project_canonical_memory_write_failed",
                            detail: "xterminal_project_memory_write_failed=NSError:No space left on device"
                        )
                    ]
                ),
                in: base
            )

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())

            let snapshot = manager.xtReadyIncidentExportSnapshot(limit: 20)

            #expect(snapshot.memoryAssemblyReady == false)
            #expect(snapshot.memoryAssemblyIssues.contains("memory_canonical_sync_delivery_failed"))
            #expect(
                snapshot.memoryAssemblyDetailLines.contains(where: {
                    $0.contains("project_canonical_memory_write_failed") &&
                    $0.contains("No space left on device")
                })
            )
            #expect(snapshot.strictE2EIssues.contains("memory:memory_canonical_sync_delivery_failed"))
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSnapshotIncludesHubRuntimeDiagnosis() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_hub_runtime_risk_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            try writeHubDoctorReport(
                sampleHubDoctorOutputReport(outputPath: XHubDoctorOutputStore.defaultHubReportURL(baseDir: base).path),
                in: base
            )

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())

            let snapshot = manager.xtReadyIncidentExportSnapshot(limit: 20)

            #expect(snapshot.strictE2EReady == false)
            #expect(snapshot.strictE2EIssues.contains("hub_runtime:xhub_local_service_unreachable"))
            #expect(snapshot.hubRuntimeDiagnosis?.overallState == XHubDoctorOverallState.blocked.rawValue)
            #expect(snapshot.hubRuntimeDiagnosis?.failureCode == "xhub_local_service_unreachable")
            #expect(snapshot.hubRuntimeDiagnosis?.headline == "Hub-managed local service is unreachable")
            #expect(
                snapshot.hubRuntimeDiagnosis?.detailLines.contains(where: {
                    $0.contains("endpoint=http://127.0.0.1:50171")
                }) == true
            )
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSnapshotFallsBackToHubLocalServiceSnapshotWhenDoctorReportMissing() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_hub_runtime_snapshot_only_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            try writeHubLocalServiceSnapshot(sampleHubLocalServiceSnapshotReport(), in: base)

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())

            let snapshot = manager.xtReadyIncidentExportSnapshot(limit: 20)

            #expect(snapshot.strictE2EReady == false)
            #expect(snapshot.strictE2EIssues.contains("hub_runtime:xhub_local_service_unreachable"))
            #expect(snapshot.hubRuntimeDiagnosis?.headline == "Hub-managed local service is unreachable")
            #expect(
                snapshot.hubRuntimeDiagnosis?.nextStep
                    == "Inspect the managed service snapshot and stderr log, fix the launch error, then refresh diagnostics."
            )
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSnapshotPrefersNewerHubLocalServiceSnapshotOverOlderDoctorReport() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_hub_runtime_snapshot_newer_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            try writeHubDoctorReport(
                sampleHubDoctorOutputReport(outputPath: XHubDoctorOutputStore.defaultHubReportURL(baseDir: base).path),
                in: base
            )
            try writeHubLocalServiceSnapshot(sampleHubLocalServiceSnapshotReport(), in: base)

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())

            let snapshot = manager.xtReadyIncidentExportSnapshot(limit: 20)

            #expect(
                snapshot.hubRuntimeDiagnosis?.nextStep
                    == "Inspect the managed service snapshot and stderr log, fix the launch error, then refresh diagnostics."
            )
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSnapshotSurfacesHubRuntimeRecoveryGuidance() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_hub_runtime_guidance_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            try writeHubDoctorReport(
                sampleHubDoctorOutputReport(outputPath: XHubDoctorOutputStore.defaultHubReportURL(baseDir: base).path),
                in: base
            )
            try writeHubLocalServiceRecoveryGuidance(sampleHubLocalServiceRecoveryGuidanceReport(), in: base)

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())

            let snapshot = manager.xtReadyIncidentExportSnapshot(limit: 20)

            #expect(snapshot.hubRuntimeDiagnosis?.failureCode == "xhub_local_service_unreachable")
            #expect(snapshot.hubRuntimeDiagnosis?.actionCategory == "inspect_health_payload")
            #expect(
                snapshot.hubRuntimeDiagnosis?.installHint ==
                    "Inspect the local /health payload and stderr log to confirm why xhub_local_service never reached ready."
            )
            #expect(
                snapshot.hubRuntimeDiagnosis?.recommendedAction ==
                    "Inspect the local /health payload | Open Hub Diagnostics and compare /health with stderr."
            )
            #expect(snapshot.hubRuntimeDiagnosis?.supportFAQSummary.contains("Why does XT stay blocked after pairing succeeds?") == true)
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSnapshotAddsMonitorLoadSummaryToHubRuntimeDiagnosis() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_hub_runtime_monitor_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            try writeHubDoctorReport(
                sampleHubDoctorOutputReport(outputPath: XHubDoctorOutputStore.defaultHubReportURL(baseDir: base).path),
                in: base
            )
            try writeHubLocalRuntimeMonitorSnapshot(sampleHubLocalRuntimeMonitorSnapshotReport(), in: base)

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())

            let snapshot = manager.xtReadyIncidentExportSnapshot(limit: 20)

            #expect(
                snapshot.hubRuntimeDiagnosis?.loadConfigSummaryLine ==
                    "current_target=bge-small provider=transformers load_summary=ctx=8192 · ttl=600s · par=2 · id=diag-a"
            )
            #expect(
                snapshot.hubRuntimeDiagnosis?.detailLines.contains(where: {
                    $0.contains("current_target=bge-small")
                        && $0.contains("ttl=600s")
                        && $0.contains("par=2")
                }) == true
            )
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSnapshotFallsBackToHubLocalServiceRecoveryGuidanceWhenDoctorArtifactsMissing() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_hub_runtime_guidance_only_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            try writeHubLocalServiceRecoveryGuidance(sampleHubLocalServiceRecoveryGuidanceReport(), in: base)

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())

            let snapshot = manager.xtReadyIncidentExportSnapshot(limit: 20)

            #expect(snapshot.strictE2EReady == false)
            #expect(snapshot.strictE2EIssues.contains("hub_runtime:xhub_local_service_unreachable"))
            #expect(snapshot.hubRuntimeDiagnosis?.overallState == XHubDoctorOverallState.blocked.rawValue)
            #expect(snapshot.hubRuntimeDiagnosis?.headline == "Hub-managed local service is unreachable")
            #expect(
                snapshot.hubRuntimeDiagnosis?.detailLines.contains(where: {
                    $0.contains("service_base_url=http://127.0.0.1:50171")
                }) == true
            )
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentStatusTextIncludesHubRuntimeDiagnosis() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_hub_runtime_status_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            try writeHubDoctorReport(
                sampleHubDoctorOutputReport(outputPath: XHubDoctorOutputStore.defaultHubReportURL(baseDir: base).path),
                in: base
            )

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())

            let text = manager.renderXTReadyIncidentEventsStatusForTesting()

            #expect(text.contains("hub_runtime：blocked · xhub_local_service_unreachable"))
            #expect(text.contains("hub_runtime_issue：Hub-managed local service is unreachable"))
            #expect(text.contains("hub_runtime_next：Start xhub_local_service or fix the configured endpoint, then refresh diagnostics."))
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentStatusTextIncludesHubRuntimeRecoveryGuidance() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_hub_runtime_guidance_status_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            try writeHubDoctorReport(
                sampleHubDoctorOutputReport(outputPath: XHubDoctorOutputStore.defaultHubReportURL(baseDir: base).path),
                in: base
            )
            try writeHubLocalServiceRecoveryGuidance(sampleHubLocalServiceRecoveryGuidanceReport(), in: base)

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())

            let text = manager.renderXTReadyIncidentEventsStatusForTesting()

            #expect(text.contains("hub_runtime_action_category：inspect_health_payload"))
            #expect(text.contains("hub_runtime_install_hint：Inspect the local /health payload and stderr log to confirm why xhub_local_service never reached ready."))
            #expect(text.contains("hub_runtime_recommended_action：Inspect the local /health payload | Open Hub Diagnostics and compare /health with stderr."))
            #expect(text.contains("hub_runtime_support_faq：Q: Why does XT stay blocked after pairing succeeds?"))
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentStatusTextSurfacesHubRuntimeLoadConfigSummary() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_hub_runtime_monitor_status_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            try writeHubDoctorReport(
                sampleHubDoctorOutputReport(outputPath: XHubDoctorOutputStore.defaultHubReportURL(baseDir: base).path),
                in: base
            )
            try writeHubLocalRuntimeMonitorSnapshot(sampleHubLocalRuntimeMonitorSnapshotReport(), in: base)

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())

            let text = manager.renderXTReadyIncidentEventsStatusForTesting()

            #expect(
                text.contains(
                    "hub_runtime_load_config：current_target=bge-small provider=transformers load_summary=ctx=8192 · ttl=600s · par=2 · id=diag-a"
                )
            )
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSummaryIncludesHubRuntimeRecoveryGuidance() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_hub_runtime_guidance_summary_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            try writeHubDoctorReport(
                sampleHubDoctorOutputReport(outputPath: XHubDoctorOutputStore.defaultHubReportURL(baseDir: base).path),
                in: base
            )
            try writeHubLocalServiceRecoveryGuidance(sampleHubLocalServiceRecoveryGuidanceReport(), in: base)

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())

            let summary = manager.renderXTReadyIncidentExportSummaryForTesting(
                .init(
                    ok: true,
                    outputPath: "/tmp/xt-ready.json",
                    exportedEventCount: 3,
                    missingIncidentCodes: [],
                    reason: "ok"
                )
            )

            #expect(summary.contains("hub_runtime_action_category：inspect_health_payload"))
            #expect(summary.contains("hub_runtime_install_hint：Inspect the local /health payload and stderr log to confirm why xhub_local_service never reached ready."))
            #expect(summary.contains("hub_runtime_recommended_action：Inspect the local /health payload | Open Hub Diagnostics and compare /health with stderr."))
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentExportSummarySurfacesHubRuntimeLoadConfigSummary() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_ready_hub_runtime_monitor_summary_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            try writeHubDoctorReport(
                sampleHubDoctorOutputReport(outputPath: XHubDoctorOutputStore.defaultHubReportURL(baseDir: base).path),
                in: base
            )
            try writeHubLocalRuntimeMonitorSnapshot(sampleHubLocalRuntimeMonitorSnapshotReport(), in: base)

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())

            let summary = manager.renderXTReadyIncidentExportSummaryForTesting(
                .init(
                    ok: true,
                    outputPath: "/tmp/xt-ready.json",
                    exportedEventCount: 3,
                    missingIncidentCodes: [],
                    reason: "ok"
                )
            )

            #expect(
                summary.contains(
                    "hub_runtime_load_config：current_target=bge-small provider=transformers load_summary=ctx=8192 · ttl=600s · par=2 · id=diag-a"
                )
            )
        }
    }

    @MainActor
    @Test
    func xtReadyIncidentStatusPrependsWorkbenchGovernanceBriefWhenPendingSkillApprovalExists() async {
        await Self.gate.runOnMainActor { @MainActor in
            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())
            manager.setPendingSupervisorSkillApprovalsForTesting(
                [
                    SupervisorManager.SupervisorPendingSkillApproval(
                        id: "xt-ready-skill-approval-1",
                        requestId: "xt-ready-skill-approval-1",
                        projectId: "project-release",
                        projectName: "Release Runtime",
                        jobId: "job-1",
                        planId: "plan-1",
                        stepId: "step-1",
                        skillId: "agent-browser",
                        toolName: "browser.open",
                        tool: nil,
                        toolSummary: "打开浏览器采集 staging 页状态",
                        reason: "需要人工确认后再继续执行",
                        createdAt: 1_000,
                        actionURL: nil,
                        routingReasonCode: nil,
                        routingExplanation: nil
                    )
                ]
            )

            let text = manager.renderXTReadyIncidentEventsStatusForTesting()

            #expect(text.contains("🧭 Supervisor Brief · 当前工作台"))
            #expect(text.contains("待审批技能"))
            #expect(text.contains("查看：查看技能审批"))
            #expect(text.contains("📌 XT-Ready incident 导出状态"))
        }
    }

    @MainActor
    private func makeReadyIncidentLedger() -> [SupervisorLaneIncident] {
        [
            makeIncident(
                code: LaneBlockedReason.grantPending.rawValue,
                laneID: "lane-1",
                status: .handled,
                detectedAt: 100,
                handledAt: 900
            ),
            makeIncident(
                code: LaneBlockedReason.awaitingInstruction.rawValue,
                laneID: "lane-2",
                status: .handled,
                detectedAt: 200,
                handledAt: 800
            ),
            makeIncident(
                code: LaneBlockedReason.runtimeError.rawValue,
                laneID: "lane-3",
                status: .handled,
                detectedAt: 300,
                handledAt: 1_300
            ),
        ]
    }

    private func makeMemorySnapshot(
        reviewLevelHint: SupervisorReviewLevel = .r2Strategic,
        requestedProfile: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        profileFloor: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        resolvedProfile: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        truncatedLayers: [String] = [],
        omittedSections: [String] = [],
        durableCandidateMirrorStatus: SupervisorDurableCandidateMirrorStatus = .notNeeded,
        durableCandidateMirrorTarget: String? = nil,
        durableCandidateMirrorAttempted: Bool = false,
        durableCandidateMirrorErrorCode: String? = nil,
        durableCandidateLocalStoreRole: String = XTSupervisorDurableCandidateMirror.localStoreRole
    ) -> SupervisorMemoryAssemblySnapshot {
        SupervisorMemoryAssemblySnapshot(
            source: "unit_test",
            resolutionSource: "unit_test",
            updatedAt: 1_773_000_000,
            reviewLevelHint: reviewLevelHint.rawValue,
            requestedProfile: requestedProfile,
            profileFloor: profileFloor,
            resolvedProfile: resolvedProfile,
            attemptedProfiles: [requestedProfile, resolvedProfile],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            selectedSections: [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack",
            ],
            omittedSections: omittedSections,
            contextRefsSelected: 2,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 2,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 1_800,
            usedTotalTokens: 1_050,
            truncatedLayers: truncatedLayers,
            freshness: "fresh_local_ipc",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "progressive_disclosure",
            durableCandidateMirrorStatus: durableCandidateMirrorStatus,
            durableCandidateMirrorTarget: durableCandidateMirrorTarget,
            durableCandidateMirrorAttempted: durableCandidateMirrorAttempted,
            durableCandidateMirrorErrorCode: durableCandidateMirrorErrorCode,
            durableCandidateLocalStoreRole: durableCandidateLocalStoreRole
        )
    }

    private func writeCanonicalSyncStatus(
        _ snapshot: HubIPCClient.CanonicalMemorySyncStatusSnapshot,
        in base: URL
    ) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(
            to: base.appendingPathComponent("canonical_memory_sync_status.json"),
            options: .atomic
        )
    }

    private func writeHubDoctorReport(
        _ report: XHubDoctorOutputReport,
        in base: URL
    ) throws {
        let data = try JSONEncoder().encode(report)
        try data.write(
            to: XHubDoctorOutputStore.defaultHubReportURL(baseDir: base),
            options: .atomic
        )
    }

    private func writeHubLocalServiceSnapshot(
        _ snapshot: XHubLocalServiceSnapshotReport,
        in base: URL
    ) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(
            to: XHubDoctorOutputStore.defaultHubLocalServiceSnapshotURL(baseDir: base),
            options: .atomic
        )
    }

    private func writeHubLocalServiceRecoveryGuidance(
        _ guidance: XHubLocalServiceRecoveryGuidanceReport,
        in base: URL
    ) throws {
        let data = try JSONEncoder().encode(guidance)
        try data.write(
            to: XHubDoctorOutputStore.defaultHubLocalServiceRecoveryGuidanceURL(baseDir: base),
            options: .atomic
        )
    }

    private func writeHubLocalRuntimeMonitorSnapshot(
        _ snapshot: XHubLocalRuntimeMonitorSnapshotReport,
        in base: URL
    ) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(
            to: XHubDoctorOutputStore.defaultHubLocalRuntimeMonitorSnapshotURL(baseDir: base),
            options: .atomic
        )
    }

    private func makeIncident(
        code: String,
        laneID: String,
        status: SupervisorIncidentStatus,
        detectedAt: Int64,
        handledAt: Int64?
    ) -> SupervisorLaneIncident {
        SupervisorLaneIncident(
            id: "incident-\(UUID().uuidString.lowercased())",
            laneID: laneID,
            taskID: UUID(),
            projectID: UUID(),
            incidentCode: code,
            eventType: "supervisor.incident.\(code).handled",
            denyCode: code,
            severity: .medium,
            category: .runtime,
            autoResolvable: true,
            requiresUserAck: false,
            proposedAction: .autoRetry,
            detectedAtMs: detectedAt,
            handledAtMs: handledAt,
            takeoverLatencyMs: handledAt.map { max(0, $0 - detectedAt) },
            auditRef: "audit-\(UUID().uuidString.lowercased())",
            detail: "test",
            status: status
        )
    }

    private func makeEvent(
        code: String,
        laneID: String,
        detectedAtMs: Int64,
        handledAtMs: Int64,
        eventType: String? = nil,
        denyCode: String,
        auditRef: String,
        takeoverLatencyMs: Int64?
    ) -> XTReadyIncidentEvent {
        XTReadyIncidentEvent(
            eventType: eventType ?? expectedEventType(for: code),
            incidentCode: code,
            laneID: laneID,
            detectedAtMs: detectedAtMs,
            handledAtMs: handledAtMs,
            denyCode: denyCode,
            auditEventType: "supervisor.incident.handled",
            auditRef: auditRef,
            takeoverLatencyMs: takeoverLatencyMs
        )
    }

    private func expectedEventType(for incidentCode: String) -> String {
        switch incidentCode {
        case LaneBlockedReason.grantPending.rawValue:
            return "supervisor.incident.grant_pending.handled"
        case LaneBlockedReason.awaitingInstruction.rawValue:
            return "supervisor.incident.awaiting_instruction.handled"
        case LaneBlockedReason.runtimeError.rawValue:
            return "supervisor.incident.runtime_error.handled"
        default:
            return "supervisor.incident.\(incidentCode).handled"
        }
    }

    private func sampleHubDoctorOutputReport(outputPath: String) -> XHubDoctorOutputReport {
        XHubDoctorOutputReport(
            schemaVersion: XHubDoctorOutputReport.currentSchemaVersion,
            contractVersion: XHubDoctorOutputReport.currentContractVersion,
            reportID: "xhub-doctor-hub-hub_ui-1741300000",
            bundleKind: .providerRuntimeReadiness,
            producer: .xHub,
            surface: .hubUI,
            overallState: .blocked,
            summary: XHubDoctorOutputSummary(
                headline: "Hub-managed local service is unreachable",
                passed: 1,
                failed: 1,
                warned: 0,
                skipped: 0
            ),
            readyForFirstTask: false,
            checks: [
                XHubDoctorOutputCheckResult(
                    checkID: "xhub_local_service_unreachable",
                    checkKind: "provider_readiness",
                    status: .fail,
                    severity: .error,
                    blocking: true,
                    headline: "Hub-managed local service is unreachable",
                    message: "Providers are pinned to xhub_local_service, but Hub cannot reach /health.",
                    nextStep: "Start xhub_local_service or fix the configured endpoint, then refresh diagnostics.",
                    repairDestinationRef: "hub://settings/diagnostics",
                    detailLines: [
                        "ready_providers=none",
                        "managed_service_ready_count=0",
                        "provider=local-chat service_state=unreachable ready=0 runtime_reason=xhub_local_service_unreachable endpoint=http://127.0.0.1:50171 execution_mode=xhub_local_service loaded_instances=0 queued=1"
                    ],
                    projectContextSummary: nil,
                    observedAtMs: 1_741_300_000
                )
            ],
            nextSteps: [
                XHubDoctorOutputNextStep(
                    stepID: "provider_readiness",
                    kind: .repairRuntime,
                    label: "Repair Runtime",
                    owner: .hubRuntime,
                    blocking: true,
                    destinationRef: "hub://settings/diagnostics",
                    instruction: "Start xhub_local_service or fix the configured endpoint, then refresh diagnostics."
                )
            ],
            routeSnapshot: nil,
            generatedAtMs: 1_741_300_000,
            reportPath: outputPath,
            sourceReportSchemaVersion: "ai_runtime_status.v1",
            sourceReportPath: "/tmp/ai_runtime_status.json",
            currentFailureCode: "xhub_local_service_unreachable",
            currentFailureIssue: nil,
            consumedContracts: ["xhub.doctor_output.v1"]
        )
    }

    private func sampleHubLocalServiceSnapshotReport() -> XHubLocalServiceSnapshotReport {
        XHubLocalServiceSnapshotReport(
            schemaVersion: "xhub_local_service_snapshot_export.v1",
            generatedAtMs: 1_741_300_100,
            statusSource: "/tmp/ai_runtime_status.json",
            runtimeAlive: true,
            providerCount: 1,
            readyProviderCount: 0,
            primaryIssue: XHubLocalServiceSnapshotPrimaryIssue(
                reasonCode: "xhub_local_service_unreachable",
                headline: "Hub-managed local service is unreachable",
                message: "Providers are pinned to xhub_local_service, but Hub cannot reach /health.",
                nextStep: "Inspect the managed service snapshot and stderr log, fix the launch error, then refresh diagnostics."
            ),
            doctorProjection: XHubLocalServiceSnapshotDoctorProjection(
                overallState: .blocked,
                readyForFirstTask: false,
                currentFailureCode: "xhub_local_service_unreachable",
                currentFailureIssue: "provider_readiness",
                providerCheckStatus: .fail,
                providerCheckBlocking: true,
                headline: "Hub-managed local service is unreachable",
                message: "Providers are pinned to xhub_local_service, but Hub cannot reach /health.",
                nextStep: "Inspect the managed service snapshot and stderr log, fix the launch error, then refresh diagnostics.",
                repairDestinationRef: "hub://settings/diagnostics"
            ),
            providers: [
                XHubLocalServiceProviderEvidence(
                    providerID: "local-chat",
                    serviceState: "unreachable",
                    runtimeReasonCode: "xhub_local_service_unreachable",
                    serviceBaseURL: "http://127.0.0.1:50171",
                    executionMode: "xhub_local_service",
                    loadedInstanceCount: 0,
                    queuedTaskCount: 1,
                    ready: false
                )
            ]
        )
    }

    private func sampleHubLocalServiceRecoveryGuidanceReport() -> XHubLocalServiceRecoveryGuidanceReport {
        XHubLocalServiceRecoveryGuidanceReport(
            schemaVersion: "xhub_local_service_recovery_guidance_export.v1",
            generatedAtMs: 1_741_300_200,
            statusSource: "/tmp/ai_runtime_status.json",
            runtimeAlive: true,
            guidancePresent: true,
            providerCount: 1,
            readyProviderCount: 0,
            currentFailureCode: "xhub_local_service_unreachable",
            currentFailureIssue: "provider_readiness",
            providerCheckStatus: XHubDoctorCheckStatus.fail.rawValue,
            providerCheckBlocking: true,
            actionCategory: "inspect_health_payload",
            severity: "high",
            installHint: "Inspect the local /health payload and stderr log to confirm why xhub_local_service never reached ready.",
            repairDestinationRef: "hub://settings/diagnostics",
            serviceBaseURL: "http://127.0.0.1:50171",
            managedProcessState: "running",
            managedStartAttemptCount: 3,
            managedLastStartError: "",
            managedLastProbeError: "connect ECONNREFUSED 127.0.0.1:50171",
            blockedCapabilities: ["ai.embed.local"],
            primaryIssue: XHubLocalServiceSnapshotPrimaryIssue(
                reasonCode: "xhub_local_service_unreachable",
                headline: "Hub-managed local service is unreachable",
                message: "Providers are pinned to xhub_local_service, but Hub cannot reach /health.",
                nextStep: "Inspect the managed service snapshot and stderr log, fix the launch error, then refresh diagnostics."
            ),
            recommendedActions: [
                XHubLocalServiceRecoveryGuidanceAction(
                    rank: 1,
                    actionID: "inspect_health_payload",
                    title: "Inspect the local /health payload",
                    why: "The service process exists but never reported a ready health payload.",
                    commandOrReference: "Open Hub Diagnostics and compare /health with stderr."
                ),
            ],
            supportFAQ: [
                XHubLocalServiceRecoveryGuidanceFAQItem(
                    faqID: "faq-1",
                    question: "Why does XT stay blocked after pairing succeeds?",
                    answer: "Pairing only proves the surfaces can talk. Hub still blocks first-task readiness until the managed local runtime reaches ready."
                ),
            ]
        )
    }

    private func sampleHubLocalRuntimeMonitorSnapshotReport() -> XHubLocalRuntimeMonitorSnapshotReport {
        XHubLocalRuntimeMonitorSnapshotReport(
            schemaVersion: "xhub_local_runtime_monitor_export.v1",
            generatedAtMs: 1_741_300_300,
            statusSource: "/tmp/ai_runtime_status.json",
            runtimeAlive: true,
            monitorSummary: "monitor_provider_count=1\nmonitor_active_task_count=1",
            runtimeOperations: XHubLocalRuntimeMonitorOperationsReport(
                runtimeSummary: "provider=transformers state=fallback",
                queueSummary: "1 个执行中 · 2 个排队中",
                loadedSummary: "1 个已加载实例",
                currentTargets: [
                    XHubLocalRuntimeMonitorCurrentTargetEvidence(
                        modelID: "bge-small",
                        modelName: "BGE Small",
                        providerID: "transformers",
                        uiSummary: "配对目标",
                        technicalSummary: "loaded_instance_preferred_profile",
                        loadSummary: "ctx=8192 · ttl=600s · par=2 · id=diag-a"
                    )
                ],
                loadedInstances: [
                    XHubLocalRuntimeMonitorLoadedInstanceEvidence(
                        providerID: "transformers",
                        modelID: "bge-small",
                        modelName: "BGE Small",
                        loadSummary: "ctx 8192 · ttl 600s · par 2 · 加载配置 diag-a",
                        detailSummary: "transformers · resident · mps · 配置 diag-a",
                        currentTargetSummary: "配对目标"
                    )
                ]
            )
        )
    }
}

private final class XTReadyIncidentReportWriteTestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var writeOptions: [Data.WritingOptions] = []

    func appendWriteOption(_ option: Data.WritingOptions) {
        lock.lock()
        defer { lock.unlock() }
        writeOptions.append(option)
    }

    func writeOptionsSnapshot() -> [Data.WritingOptions] {
        lock.lock()
        defer { lock.unlock() }
        return writeOptions
    }
}
