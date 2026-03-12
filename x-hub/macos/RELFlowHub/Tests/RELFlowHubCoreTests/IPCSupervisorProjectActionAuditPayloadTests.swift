import XCTest
@testable import RELFlowHubCore

final class IPCSupervisorProjectActionAuditPayloadTests: XCTestCase {
    func testIPCRequestRoundTripsSupervisorProjectActionPayload() throws {
        let request = IPCRequest(
            type: "supervisor_project_action_audit",
            reqId: "req-1",
            supervisorProjectAction: IPCSupervisorProjectActionAuditPayload(
                eventId: "evt-1",
                projectId: "project-1",
                projectName: "Project One",
                eventType: "awaiting_authorization",
                severity: "authorization_required",
                actionTitle: "等待授权",
                actionSummary: "grant_required",
                whyItMatters: "需要用户批准后才能继续",
                nextAction: "Approve paid model access",
                occurredAtMs: 123_456,
                deliveryChannel: "interrupt_now",
                deliveryStatus: "delivered",
                jurisdictionRole: "owner",
                grantedScope: "capsule_plus_recent",
                auditRef: "project_action_audit:evt-1",
                source: "x_terminal_supervisor"
            )
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(IPCRequest.self, from: data)

        XCTAssertEqual(decoded.type, "supervisor_project_action_audit")
        XCTAssertEqual(decoded.supervisorProjectAction?.projectId, "project-1")
        XCTAssertEqual(decoded.supervisorProjectAction?.deliveryStatus, "delivered")
        XCTAssertEqual(decoded.supervisorProjectAction?.grantedScope, "capsule_plus_recent")
    }
}
