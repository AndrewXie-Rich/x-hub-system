import XCTest
@testable import RELFlowHubCore

final class DeviceCanonicalMemoryStorageTests: XCTestCase {
    func testUpsertAndLookupDeviceCanonicalMemorySnapshot() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("hub_device_memory_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let snapshot = HubDeviceCanonicalMemorySnapshot(
            supervisorId: "supervisor-main",
            displayName: "Supervisor",
            updatedAt: 123_456,
            items: [
                HubDeviceCanonicalMemoryItem(
                    key: "xterminal.supervisor.portfolio.project_count_total",
                    value: "4"
                )
            ]
        )

        _ = HubDeviceCanonicalMemoryStorage.upsert(snapshot, baseDir: base)
        let stored = try XCTUnwrap(
            HubDeviceCanonicalMemoryStorage.lookup(supervisorId: "supervisor-main", displayName: nil, baseDir: base)
        )

        XCTAssertEqual(stored.supervisorId, "supervisor-main")
        XCTAssertEqual(stored.displayName, "Supervisor")
        XCTAssertEqual(stored.items.first?.value, "4")
    }
}
