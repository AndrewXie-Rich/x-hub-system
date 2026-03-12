import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

@MainActor
final class SupervisorProjectActionAuditStoreTests: XCTestCase {
    func testAppendSupervisorProjectActionAuditWritesAuditEventRow() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xt_w331_hub_project_action_\(UUID().uuidString)", isDirectory: true)
        let dbDir = root.appendingPathComponent("hub_grpc", isDirectory: true)
        let dbURL = dbDir.appendingPathComponent("hub.sqlite3")
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        _ = try runSQLite(
            dbURL: dbURL,
            sql: """
CREATE TABLE audit_events(
  event_id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  severity TEXT,
  device_id TEXT,
  user_id TEXT,
  app_id TEXT,
  project_id TEXT,
  session_id TEXT,
  request_id TEXT,
  capability TEXT,
  model_id TEXT,
  prompt_tokens INTEGER,
  completion_tokens INTEGER,
  total_tokens INTEGER,
  cost_usd_estimate REAL,
  network_allowed INTEGER,
  ok INTEGER,
  error_code TEXT,
  error_message TEXT,
  duration_ms INTEGER,
  ext_json TEXT
);
"""
        )
        let originalDatabaseURLProvider = hubAuditDatabaseURLProvider
        hubAuditDatabaseURLProvider = { dbURL }
        defer {
            hubAuditDatabaseURLProvider = originalDatabaseURLProvider
            try? FileManager.default.removeItem(at: root)
        }

        let ok = appendSupervisorProjectActionAuditToHubDB(
            IPCSupervisorProjectActionAuditPayload(
                eventId: "evt-1",
                projectId: "project-1",
                projectName: "Project One",
                eventType: "blocked",
                severity: "brief_card",
                actionTitle: "项目阻塞",
                actionSummary: "waiting_on_dependency",
                whyItMatters: "Supervisor 需要优先处理 blocker",
                nextAction: "Unblock dependency",
                occurredAtMs: 123_456,
                deliveryChannel: "brief_card",
                deliveryStatus: "delivered",
                jurisdictionRole: "owner",
                grantedScope: "capsule_plus_recent",
                auditRef: "project_action_audit:evt-1",
                source: "x_terminal_supervisor"
            )
        )

        XCTAssertTrue(ok)
        let row = try runSQLite(
            dbURL: dbURL,
            sql: "SELECT event_type || '|' || project_id || '|' || request_id || '|' || capability || '|' || ok || '|' || ext_json FROM audit_events;"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = row.split(separator: "|", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(fields.count, 6)
        XCTAssertEqual(fields[0], "supervisor.project_action.blocked")
        XCTAssertEqual(fields[1], "project-1")
        XCTAssertEqual(fields[2], "evt-1")
        XCTAssertEqual(fields[3], "supervisor_project_action_feed")
        XCTAssertEqual(fields[4], "1")

        let extData = try XCTUnwrap(fields[5].data(using: .utf8))
        let ext = try XCTUnwrap(JSONSerialization.jsonObject(with: extData) as? [String: Any])
        XCTAssertEqual(ext["delivery_channel"] as? String, "brief_card")
        XCTAssertEqual(ext["delivery_status"] as? String, "delivered")
        XCTAssertEqual(ext["jurisdiction_role"] as? String, "owner")
        XCTAssertEqual(ext["granted_scope"] as? String, "capsule_plus_recent")
    }

    func testAppendSupervisorProjectActionAuditRejectsMissingRequiredFields() {
        let ok = appendSupervisorProjectActionAuditToHubDB(
            IPCSupervisorProjectActionAuditPayload(
                eventId: "",
                projectId: "project-1",
                projectName: "Project One",
                eventType: "blocked",
                severity: "brief_card",
                actionTitle: "项目阻塞",
                actionSummary: "waiting_on_dependency",
                whyItMatters: "Supervisor 需要优先处理 blocker",
                nextAction: "Unblock dependency",
                occurredAtMs: 123_456,
                deliveryChannel: "brief_card",
                deliveryStatus: "delivered",
                auditRef: "project_action_audit:evt-1"
            )
        )

        XCTAssertFalse(ok)
    }

    private func runSQLite(dbURL: URL, sql: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbURL.path, sql]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, error)
        return output
    }
}
