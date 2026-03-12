import Foundation
import Testing
@testable import XTerminal

struct SupervisorProjectActionCanonicalSyncTests {
    @Test
    func itemsIncludeStableProjectActionKeysAndSummaryJSON() throws {
        let record = SupervisorProjectActionCanonicalRecord(
            schemaVersion: SupervisorProjectActionCanonicalSync.schemaVersion,
            eventId: "evt-1",
            projectId: "project-1",
            projectName: "Project One",
            eventType: "awaiting_authorization",
            severity: "authorization_required",
            actionTitle: "等待授权",
            actionSummary: "grant_required",
            whyItMatters: "需要用户批准付费模型权限",
            nextAction: "Approve paid model access",
            occurredAtMs: 123_456,
            deliveryChannel: "interrupt_now",
            deliveryStatus: "delivered",
            jurisdictionRole: "owner",
            grantedScope: "capsule_plus_recent",
            auditRef: "project_action_audit:evt-1"
        )

        let items = SupervisorProjectActionCanonicalSync.items(record: record)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0.value) })

        #expect(values["xterminal.project.action.event_type"] == "awaiting_authorization")
        #expect(values["xterminal.project.action.delivery_status"] == "delivered")
        #expect(values["xterminal.project.action.jurisdiction_role"] == "owner")
        #expect(values["xterminal.project.action.granted_scope"] == "capsule_plus_recent")

        let summaryText = try #require(values["xterminal.project.action.summary_json"])
        let summaryData = try #require(summaryText.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SupervisorProjectActionCanonicalRecord.self, from: summaryData)
        #expect(decoded.projectId == "project-1")
        #expect(decoded.deliveryChannel == "interrupt_now")
        #expect(decoded.auditRef == "project_action_audit:evt-1")
    }

    @Test
    func itemsOmitEmptyOptionalFieldsButKeepRequiredCoreFields() {
        let record = SupervisorProjectActionCanonicalRecord(
            schemaVersion: SupervisorProjectActionCanonicalSync.schemaVersion,
            eventId: "evt-2",
            projectId: "project-2",
            projectName: "Project Two",
            eventType: "blocked",
            severity: "brief_card",
            actionTitle: "项目阻塞",
            actionSummary: "waiting_on_dependency",
            whyItMatters: "需要先解阻依赖链",
            nextAction: "Unblock dependency",
            occurredAtMs: 789,
            deliveryChannel: "brief_card",
            deliveryStatus: "suppressed_duplicate",
            jurisdictionRole: nil,
            grantedScope: nil,
            auditRef: "project_action_audit:evt-2"
        )

        let items = SupervisorProjectActionCanonicalSync.items(record: record)
        let keys = Set(items.map(\.key))

        #expect(keys.contains("xterminal.project.action.summary_json"))
        #expect(keys.contains("xterminal.project.action.action_summary"))
        #expect(keys.contains("xterminal.project.action.delivery_status"))
        #expect(!keys.contains("xterminal.project.action.jurisdiction_role"))
        #expect(!keys.contains("xterminal.project.action.granted_scope"))
    }
}
