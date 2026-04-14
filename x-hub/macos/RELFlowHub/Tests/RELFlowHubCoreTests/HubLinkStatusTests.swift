import XCTest
@testable import RELFlowHubCore

final class HubLinkStatusTests: XCTestCase {
    func testIsAliveRejectsDeadPIDEvenWhenTimestampIsFresh() throws {
        let status = try decodeStatus([
            "pid": Int(Int32.max) - 1,
            "updatedAt": Date().timeIntervalSince1970,
        ])

        XCTAssertFalse(status.isAlive(ttl: 10))
    }

    func testIsAliveAllowsFreshHeartbeatWithoutPID() throws {
        let status = try decodeStatus([
            "updatedAt": Date().timeIntervalSince1970,
        ])

        XCTAssertTrue(status.isAlive(ttl: 10))
    }

    func testIsAliveRejectsStaleHeartbeat() throws {
        let status = try decodeStatus([
            "updatedAt": Date().addingTimeInterval(-30).timeIntervalSince1970,
        ])

        XCTAssertFalse(status.isAlive(ttl: 5))
    }

    private func decodeStatus(_ object: [String: Any]) throws -> HubLinkStatus {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        return try JSONDecoder().decode(HubLinkStatus.self, from: data)
    }
}
