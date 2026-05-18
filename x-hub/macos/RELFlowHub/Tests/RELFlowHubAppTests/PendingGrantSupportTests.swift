import XCTest
@testable import RELFlowHub

final class PendingGrantSupportTests: XCTestCase {
    func testPendingGrantRequestDecodesHubAdminHTTPShape() throws {
        let json = """
        {
          "grant_request_id": "grant_req_1",
          "request_id": "req_1",
          "client": {
            "device_id": "dev_1",
            "user_id": "user_1",
            "app_id": "x_terminal",
            "project_id": "project_1",
            "session_id": ""
          },
          "capability": "skills.execute",
          "model_id": "",
          "reason": "XT requested skill preflight approval",
          "requested_ttl_sec": 900,
          "requested_token_cap": 0,
          "status": "pending",
          "decision": "queued",
          "created_at_ms": 1710000000000,
          "decided_at_ms": 0
        }
        """.data(using: .utf8)!

        let grant = try JSONDecoder().decode(HubPendingGrantRequest.self, from: json)

        XCTAssertEqual(grant.id, "grant_req_1")
        XCTAssertEqual(grant.displayCapability, "Skill 执行")
        XCTAssertEqual(grant.client.projectId, "project_1")
        XCTAssertEqual(grant.scopeSummary, "project project_1 · device dev_1 · x_terminal")
        XCTAssertTrue(grant.isPending)
    }
}
