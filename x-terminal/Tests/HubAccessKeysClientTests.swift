import Foundation
import Testing
@testable import XTerminal

struct HubAccessKeysClientTests {
    @Test
    func sessionContextPrefersCurrentHubHostAndPairingPort() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writePairingEnv(
            at: tempDir,
            contents: """
            AXHUB_HUB_HOST='192.168.0.10'
            AXHUB_INTERNET_HOST='hub.tailnet.example'
            AXHUB_PAIRING_PORT='50054'
            """
        )
        try writeHubEnv(
            at: tempDir,
            contents: """
            export HUB_HOST='17.81.11.116'
            export HUB_PORT='50053'
            export HUB_CLIENT_TOKEN='tok_current'
            export HUB_DEVICE_ID='dev_xt_alpha'
            export HUB_USER_ID='xt_alpha'
            export HUB_APP_ID='x_terminal'
            """
        )

        let context = try #require(HubAccessKeysClient.resolveSessionContext(stateDir: tempDir))
        #expect(context.baseURL.absoluteString == "http://17.81.11.116:50054")
        #expect(context.clientToken == "tok_current")
        #expect(context.deviceID == "dev_xt_alpha")
        #expect(context.userID == "xt_alpha")
        #expect(context.appID == "x_terminal")
    }

    @Test
    func sessionContextFallsBackToPairingHostWhenHubHostMissing() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writePairingEnv(
            at: tempDir,
            contents: """
            AXHUB_INTERNET_HOST='hub.tailnet.example'
            AXHUB_PAIRING_PORT='50052'
            """
        )
        try writeHubEnv(
            at: tempDir,
            contents: """
            export HUB_CLIENT_TOKEN='tok_current'
            """
        )

        let context = try #require(HubAccessKeysClient.resolveSessionContext(stateDir: tempDir))
        #expect(context.baseURL.absoluteString == "http://hub.tailnet.example:50052")
    }

    @Test
    func sessionContextNormalizesWildcardHubHostToLoopback() throws {
        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writeHubEnv(
            at: tempDir,
            contents: """
            export HUB_HOST='0.0.0.0'
            export HUB_PORT='50051'
            export HUB_CLIENT_TOKEN='tok_local'
            """
        )

        let context = try #require(HubAccessKeysClient.resolveSessionContext(stateDir: tempDir))
        #expect(context.baseURL.absoluteString == "http://127.0.0.1:50052")
    }

    private func makeTempStateDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hub_access_keys_client_tests", isDirectory: true)
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

    private func writeHubEnv(at dir: URL, contents: String) throws {
        try contents.write(
            to: dir.appendingPathComponent("hub.env"),
            atomically: true,
            encoding: .utf8
        )
    }
}
