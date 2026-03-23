import Foundation
import Testing
@testable import XTerminal

struct HubAIClientRemoteConnectOptionsTests {
    @Test
    func remoteConnectOptionsFallbackToCachedInternetHost() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writePairingEnv(
            at: tempDir,
            contents: """
            AXHUB_HUB_HOST='192.168.0.10'
            AXHUB_INTERNET_HOST='hub.tailnet.example'
            AXHUB_PAIRING_PORT='50052'
            AXHUB_GRPC_PORT='50051'
            """
        )

        try withHubRemoteDefaultsCleared {
            let options = HubAIClient.remoteConnectOptionsFromDefaults(stateDir: tempDir)
            #expect(options.internetHost == "hub.tailnet.example")
            #expect(options.pairingPort == 50052)
            #expect(options.grpcPort == 50051)
        }
    }

    @Test
    func remoteConnectOptionsInferReusableHostFromNonPrivateCachedHost() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writePairingEnv(
            at: tempDir,
            contents: """
            AXHUB_HUB_HOST='100.96.10.8'
            AXHUB_PAIRING_PORT='50052'
            AXHUB_GRPC_PORT='50051'
            """
        )

        try withHubRemoteDefaultsCleared {
            let options = HubAIClient.remoteConnectOptionsFromDefaults(stateDir: tempDir)
            #expect(options.internetHost == "100.96.10.8")
        }
    }

    @Test
    func remoteConnectOptionsDoNotPromoteCorporateLanIpToInternetHostWhenHubIdentityWasDiscovered() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writePairingEnv(
            at: tempDir,
            contents: """
            AXHUB_HUB_HOST='17.81.12.12'
            AXHUB_HUB_INSTANCE_ID='hub_deadbeefcafefeed00'
            AXHUB_LAN_DISCOVERY_NAME='axhub-edge-bj'
            AXHUB_PAIRING_PORT='50053'
            AXHUB_GRPC_PORT='50052'
            """
        )

        try withHubRemoteDefaultsCleared {
            let options = HubAIClient.remoteConnectOptionsFromDefaults(stateDir: tempDir)
            #expect(options.internetHost.isEmpty)
            #expect(options.pairingPort == 50053)
            #expect(options.grpcPort == 50052)
        }
    }

    private func makeTempStateDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hub_ai_client_remote_options_tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writePairingEnv(at dir: URL, contents: String) throws {
        try contents.write(
            to: dir.appendingPathComponent("pairing.env"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func withHubRemoteDefaultsCleared(_ body: () throws -> Void) throws {
        let defaults = UserDefaults.standard
        let keys = [
            "xterminal_hub_pairing_port",
            "xterminal_hub_grpc_port",
            "xterminal_hub_internet_host",
            "xterminal_hub_axhubctl_path",
        ]
        let previous = keys.reduce(into: [String: Any?]()) { partialResult, key in
            partialResult[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
        defer {
            for key in keys {
                if let value = previous[key] ?? nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        try body()
    }
}
