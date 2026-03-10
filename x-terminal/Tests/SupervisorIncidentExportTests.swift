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
