import XCTest
@testable import RELFlowHub

@MainActor
final class HubBootstrapCommandBuilderTests: XCTestCase {
    func testBootstrapCommandRequiresClientKitInstallation() {
        let text = HubGRPCServerSupport.bootstrapCommandText(
            host: "17.81.11.116",
            grpcPort: 50053,
            pairingPort: 50054,
            inviteToken: "axhub_invite_test_123"
        )

        XCTAssertTrue(text.contains("HUB_HOST='17.81.11.116'"))
        XCTAssertTrue(text.contains("GRPC_PORT=50053"))
        XCTAssertTrue(text.contains("PAIRING_PORT=50054"))
        XCTAssertTrue(text.contains("INVITE_TOKEN='axhub_invite_test_123'"))
        XCTAssertTrue(text.contains("--require-client-kit"))
        XCTAssertTrue(text.contains("\"$AXHUBCTL\" list-models"))
    }

    func testBootstrapCommandOmitsInviteTokenWhenMissing() {
        let text = HubGRPCServerSupport.bootstrapCommandText(
            host: "17.81.11.116",
            grpcPort: 50053,
            pairingPort: 50054,
            inviteToken: nil
        )

        XCTAssertFalse(text.contains("INVITE_TOKEN="))
        XCTAssertFalse(text.contains("--invite-token"))
        XCTAssertTrue(text.contains("--require-client-kit"))
    }
}
