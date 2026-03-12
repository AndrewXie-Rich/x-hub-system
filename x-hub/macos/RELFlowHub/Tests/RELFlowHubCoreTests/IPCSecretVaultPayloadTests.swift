import XCTest
@testable import RELFlowHubCore

final class IPCSecretVaultPayloadTests: XCTestCase {
    func testIPCRequestRoundTripsSecretVaultCreatePayload() throws {
        let request = IPCRequest(
            type: "secret_vault_create",
            reqId: "req-secret-1",
            secretVaultCreate: IPCSecretVaultCreateRequestPayload(
                scope: "project",
                name: "minecraft-login",
                plaintext: "super-secret",
                sensitivity: "credential",
                projectID: "proj-1",
                displayName: "Minecraft Login",
                reason: "website_sign_in"
            )
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(IPCRequest.self, from: data)

        XCTAssertEqual(decoded.type, "secret_vault_create")
        XCTAssertEqual(decoded.secretVaultCreate?.scope, "project")
        XCTAssertEqual(decoded.secretVaultCreate?.name, "minecraft-login")
        XCTAssertEqual(decoded.secretVaultCreate?.projectID, "proj-1")
    }

    func testIPCResponseRoundTripsSecretVaultUsePayload() throws {
        let response = IPCResponse(
            type: "secret_vault_use_ack",
            reqId: "req-secret-2",
            ok: true,
            id: "svl_local_1",
            error: nil,
            secretVaultUse: IPCSecretVaultUseResult(
                ok: true,
                source: "hub_local_secret_vault",
                leaseID: "svl_local_1",
                useToken: "svtok_local_1",
                itemID: "sv_local_1",
                expiresAtMs: 123_456,
                reasonCode: nil
            )
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(IPCResponse.self, from: data)

        XCTAssertEqual(decoded.type, "secret_vault_use_ack")
        XCTAssertEqual(decoded.secretVaultUse?.leaseID, "svl_local_1")
        XCTAssertEqual(decoded.secretVaultUse?.useToken, "svtok_local_1")
        XCTAssertEqual(decoded.secretVaultUse?.itemID, "sv_local_1")
    }
}
