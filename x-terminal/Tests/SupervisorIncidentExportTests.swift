import Foundation
import Testing
@testable import XTerminal

struct SupervisorIncidentExportTests {

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
    func xtReadyIncidentExportSnapshotIncludesMemoryAssemblyRisk() {
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

    @MainActor
    @Test
    func exportReportPersistsMemoryAssemblySummary() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeMemorySnapshot(
                truncatedLayers: ["l1_canonical"]
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
        omittedSections: [String] = []
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
            compressionPolicy: "progressive_disclosure"
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
}
