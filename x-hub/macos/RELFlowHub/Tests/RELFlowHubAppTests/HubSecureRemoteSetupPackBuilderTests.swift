import XCTest
@testable import RELFlowHub

final class HubSecureRemoteSetupPackBuilderTests: XCTestCase {
    func testBuildReturnsNilForRawIPHost() {
        let text = HubSecureRemoteSetupPackBuilder.build(
            externalHost: "17.81.11.116",
            alias: "ops-main",
            inviteToken: "axhub_invite_test_123",
            pairingPort: 50054,
            grpcPort: 50053,
            hubInstanceID: "hub_deadbeefcafefeed00"
        )

        XCTAssertNil(text)
    }

    func testBuildReturnsSecurePackForStableNamedHost() throws {
        let text = try XCTUnwrap(
            HubSecureRemoteSetupPackBuilder.build(
                externalHost: "hub.tailnet.example",
                alias: "ops-main",
                inviteToken: "axhub_invite_test_123",
                pairingPort: 50054,
                grpcPort: 50053,
                hubInstanceID: "hub_deadbeefcafefeed00"
            )
        )

        XCTAssertTrue(text.contains("xterminal://pair-hub?hub_host=hub.tailnet.example"))
        XCTAssertTrue(text.contains("\"$AXHUBCTL\" bootstrap --hub 'hub.tailnet.example'"))
        XCTAssertTrue(text.contains("--invite-token 'axhub_invite_test_123'"))
        XCTAssertTrue(text.contains("--require-client-kit"))
        XCTAssertTrue(text.contains("Fails closed if the required client kit cannot be installed"))
        XCTAssertTrue(text.contains("Does not fetch `axhubctl` over unauthenticated remote HTTP"))
    }
}
