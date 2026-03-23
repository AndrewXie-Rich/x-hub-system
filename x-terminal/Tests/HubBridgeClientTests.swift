import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct HubBridgeClientTests {
    @Test
    func requestEnableReportsCommandQueueFailure() throws {
        let base = try makeTempDirectory("bridge_client")
        defer {
            HubBridgeClient.resetForTesting()
            try? FileManager.default.removeItem(at: base)
        }

        try writeBridgeStatus(
            alive: true,
            enabledUntil: 0,
            to: base.appendingPathComponent("bridge_status.json")
        )

        HubBridgeClient.installBaseDirOverrideForTesting(base)
        HubBridgeClient.installCommandWriteOverrideForTesting { _, _, _ in
            throw NSError(domain: NSPOSIXErrorDomain, code: 28)
        }

        let status = HubBridgeClient.requestEnable(seconds: 60)
        #expect(status.alive == true)
        #expect(status.enabled == false)
        #expect(status.requestQueued == false)
        #expect(status.requestError.contains("bridge_enable_command_write_failed"))
    }

    private func makeTempDirectory(_ suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_bridge_client_\(suffix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeBridgeStatus(alive: Bool, enabledUntil: Double, to url: URL) throws {
        let payload: [String: Any] = [
            "updatedAt": alive ? Date().timeIntervalSince1970 : 0,
            "enabledUntil": enabledUntil
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
