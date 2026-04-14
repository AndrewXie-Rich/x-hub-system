import XCTest
@testable import RELFlowHub

final class HubGRPCServerSupportInternetHostTests: XCTestCase {
    @MainActor
    func testPreferredXTTerminalInternetHostUsesOverrideWhenPresent() {
        let selected = HubGRPCServerSupport.preferredXTTerminalInternetHost(
            override: "hub.tailnet.example",
            interfaceRows: [
                "en0: 192.168.0.12",
                "utun4: 100.96.10.8",
            ]
        )

        XCTAssertEqual(selected, "hub.tailnet.example")
    }

    @MainActor
    func testPreferredXTTerminalInternetHostPrefersTunnelStyleAddressOverWifiLAN() {
        let selected = HubGRPCServerSupport.preferredXTTerminalInternetHost(
            override: "",
            interfaceRows: [
                "en0: 192.168.0.12",
                "utun4: 100.96.10.8",
                "en1: 10.0.0.7",
            ]
        )

        XCTAssertEqual(selected, "100.96.10.8")
    }

    @MainActor
    func testPreferredExternalHubAliasPrefersSanitizedOverride() {
        let alias = HubExternalAccessInviteSupport.preferredExternalHubAlias(
            override: " Ops Main / CN ",
            bonjourMetadata: HubBonjourAdvertiser.Metadata(
                hubInstanceID: "hub_deadbeefcafefeed00",
                lanDiscoveryName: "axhub-deadbeef"
            ),
            externalHost: "hub.tailnet.example"
        )

        XCTAssertEqual(alias, "ops-main-cn")
    }

    @MainActor
    func testExternalInviteURLAllowsLANRawIPForPairHubDeepLink() {
        let rawIPInvite = HubExternalAccessInviteSupport.externalInviteURL(
            alias: "ops-main",
            externalHost: "17.81.11.116",
            inviteToken: "axhub_invite_test_123",
            pairingPort: 50054,
            grpcPort: 50053,
            hubInstanceID: "hub_deadbeefcafefeed00"
        )

        XCTAssertEqual(
            rawIPInvite?.absoluteString,
            "xterminal://pair-hub?hub_host=17.81.11.116&pairing_port=50054&grpc_port=50053&invite_token=axhub_invite_test_123&hub_alias=ops-main&hub_instance_id=hub_deadbeefcafefeed00"
        )
    }

    @MainActor
    func testExternalInviteURLBuildsPairHubDeepLink() {
        let invite = HubExternalAccessInviteSupport.externalInviteURL(
            alias: "ops-main",
            externalHost: "hub.tailnet.example",
            inviteToken: "axhub_invite_test_123",
            pairingPort: 50054,
            grpcPort: 50053,
            hubInstanceID: "hub_deadbeefcafefeed00"
        )

        XCTAssertEqual(
            invite?.absoluteString,
            "xterminal://pair-hub?hub_host=hub.tailnet.example&pairing_port=50054&grpc_port=50053&invite_token=axhub_invite_test_123&hub_alias=ops-main&hub_instance_id=hub_deadbeefcafefeed00"
        )
    }
}
