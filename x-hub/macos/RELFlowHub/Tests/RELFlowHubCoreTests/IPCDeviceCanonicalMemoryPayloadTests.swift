import XCTest
@testable import RELFlowHubCore

final class IPCDeviceCanonicalMemoryPayloadTests: XCTestCase {
    func testIPCRequestRoundTripsDeviceCanonicalMemoryPayload() throws {
        let request = IPCRequest(
            type: "device_canonical_memory",
            reqId: "req-1",
            deviceCanonicalMemory: IPCDeviceCanonicalMemoryPayload(
                supervisorId: "supervisor-main",
                displayName: "Supervisor",
                updatedAt: 123_456,
                items: [
                    IPCProjectCanonicalMemoryItem(
                        key: "xterminal.supervisor.portfolio.status_line",
                        value: "projects=1 · active=1 · blocked=0 · auth=0 · completed=0"
                    )
                ]
            )
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(IPCRequest.self, from: data)

        XCTAssertEqual(decoded.type, "device_canonical_memory")
        XCTAssertEqual(decoded.deviceCanonicalMemory?.supervisorId, "supervisor-main")
        XCTAssertEqual(decoded.deviceCanonicalMemory?.displayName, "Supervisor")
        XCTAssertEqual(decoded.deviceCanonicalMemory?.items.first?.key, "xterminal.supervisor.portfolio.status_line")
    }
}
