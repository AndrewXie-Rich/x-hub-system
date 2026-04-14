import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct HubInviteOnboardingFlowTests {
    @Test
    func pairHubInviteRouteFeedsAppModelAndRemoteConnectOptions() throws {
        let url = try #require(
            URL(string: "xterminal://pair-hub?hub_alias=ops-main&hub_host=hub.tailnet.example&pairing_port=50054&grpc_port=50053&invite_token=axhub_invite_test_123&hub_instance_id=hub_deadbeefcafefeed00")
        )
        let route = try #require(XTDeepLinkParser.parse(url))
        guard case let .hubSetup(hubSetupRoute) = route else {
            Issue.record("expected hub setup route")
            return
        }
        let prefill = try #require(hubSetupRoute.pairingPrefill)

        let tempDir = try makeTempStateDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try withHubRemoteDefaultsCleared {
            let appModel = AppModel()
            appModel.applyHubPairingInvitePrefill(prefill)

            let options = HubAIClient.remoteConnectOptionsFromDefaults(stateDir: tempDir)
            #expect(appModel.hubInviteAlias == "ops-main")
            #expect(appModel.hubInviteInstanceID == "hub_deadbeefcafefeed00")
            #expect(options.internetHost == "hub.tailnet.example")
            #expect(options.pairingPort == 50054)
            #expect(options.grpcPort == 50053)
            #expect(options.inviteToken == "axhub_invite_test_123")
            #expect(options.inviteAlias == "ops-main")
            #expect(options.inviteInstanceID == "hub_deadbeefcafefeed00")
        }
    }

    private func makeTempStateDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hub_invite_onboarding_flow_tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func withHubRemoteDefaultsCleared(_ body: () throws -> Void) throws {
        let defaults = UserDefaults.standard
        let keys = [
            "xterminal_hub_pairing_port",
            "xterminal_hub_grpc_port",
            "xterminal_hub_internet_host",
            "xterminal_hub_invite_token",
            "xterminal_hub_invite_alias",
            "xterminal_hub_invite_instance_id",
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
