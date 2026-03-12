import XCTest
@testable import RELFlowHubCore

final class SecretVaultStorageTests: XCTestCase {
    func testCreateListAndBeginUsePersistEncryptedVaultState() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("hub_secret_vault_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let created = HubSecretVaultStorage.create(
            payload: IPCSecretVaultCreateRequestPayload(
                scope: "project",
                name: "minecraft-login",
                plaintext: "CorrectHorseBatteryStaple!",
                sensitivity: "credential",
                projectID: "proj-1",
                displayName: "Minecraft Login",
                reason: "website_sign_in"
            ),
            baseDir: base
        )
        XCTAssertTrue(created.ok)
        XCTAssertEqual(created.item?.name, "minecraft-login")

        let stateURL = HubSecretVaultStorage.stateURL(baseDir: base)
        let raw = try String(contentsOf: stateURL, encoding: .utf8)
        XCTAssertFalse(raw.contains("CorrectHorseBatteryStaple!"))
        XCTAssertTrue(raw.contains("minecraft-login"))

        let listed = HubSecretVaultStorage.list(
            payload: IPCSecretVaultListRequestPayload(scope: "project", namePrefix: "mine", projectID: "proj-1", limit: 10),
            baseDir: base
        )
        XCTAssertEqual(listed.items.count, 1)
        XCTAssertEqual(listed.items.first?.itemID, created.item?.itemID)

        let use = HubSecretVaultStorage.beginUse(
            payload: IPCSecretVaultUseRequestPayload(
                itemID: created.item?.itemID,
                scope: nil,
                name: nil,
                projectID: "proj-1",
                purpose: "browser_login",
                target: "https://example.com/login",
                ttlMs: 45_000
            ),
            baseDir: base
        )
        XCTAssertTrue(use.ok)
        XCTAssertEqual(use.itemID, created.item?.itemID)
        XCTAssertNotNil(use.useToken)

        let snapshotURL = HubSecretVaultStorage.snapshotURL(baseDir: base)
        let snapshotRaw = try String(contentsOf: snapshotURL, encoding: .utf8)
        XCTAssertFalse(snapshotRaw.contains("CorrectHorseBatteryStaple!"))
        XCTAssertTrue(snapshotRaw.contains("minecraft-login"))
    }

    func testProjectScopedLookupFailsClosedAcrossProjects() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("hub_secret_vault_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        _ = HubSecretVaultStorage.create(
            payload: IPCSecretVaultCreateRequestPayload(
                scope: "project",
                name: "deploy-token",
                plaintext: "top-secret",
                sensitivity: "secret",
                projectID: "proj-owner"
            ),
            baseDir: base
        )

        let denied = HubSecretVaultStorage.beginUse(
            payload: IPCSecretVaultUseRequestPayload(
                itemID: nil,
                scope: "project",
                name: "deploy-token",
                projectID: "proj-other",
                purpose: "deploy",
                target: nil,
                ttlMs: 30_000
            ),
            baseDir: base
        )
        XCTAssertFalse(denied.ok)
        XCTAssertEqual(denied.reasonCode, "secret_vault_item_not_found")
    }

    func testProjectScopedListFailsClosedWithoutProjectContext() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("hub_secret_vault_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        _ = HubSecretVaultStorage.create(
            payload: IPCSecretVaultCreateRequestPayload(
                scope: "project",
                name: "deploy-token",
                plaintext: "top-secret",
                sensitivity: "secret",
                projectID: "proj-owner"
            ),
            baseDir: base
        )

        let denied = HubSecretVaultStorage.list(
            payload: IPCSecretVaultListRequestPayload(scope: "project", namePrefix: nil, projectID: nil, limit: 10),
            baseDir: base
        )
        XCTAssertEqual(denied.items.count, 0)

        let allowed = HubSecretVaultStorage.list(
            payload: IPCSecretVaultListRequestPayload(scope: "project", namePrefix: nil, projectID: "proj-owner", limit: 10),
            baseDir: base
        )
        XCTAssertEqual(allowed.items.count, 1)
        XCTAssertEqual(allowed.items.first?.name, "deploy-token")
    }

    func testRedeemUseTokenDecryptsPlaintextAndConsumesLease() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("hub_secret_vault_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let created = HubSecretVaultStorage.create(
            payload: IPCSecretVaultCreateRequestPayload(
                scope: "project",
                name: "minecraft-login",
                plaintext: "CorrectHorseBatteryStaple!",
                sensitivity: "credential",
                projectID: "proj-1"
            ),
            baseDir: base
        )
        XCTAssertTrue(created.ok)

        let lease = HubSecretVaultStorage.beginUse(
            payload: IPCSecretVaultUseRequestPayload(
                itemID: created.item?.itemID,
                scope: nil,
                name: nil,
                projectID: "proj-1",
                purpose: "browser_login",
                target: "https://example.com/login",
                ttlMs: 30_000
            ),
            baseDir: base
        )
        XCTAssertTrue(lease.ok)

        let redeemed = HubSecretVaultStorage.redeemUseToken(
            lease.useToken ?? "",
            projectID: "proj-1",
            baseDir: base
        )
        XCTAssertTrue(redeemed.ok)
        XCTAssertEqual(redeemed.itemID, created.item?.itemID)
        XCTAssertEqual(redeemed.plaintext, "CorrectHorseBatteryStaple!")

        let replay = HubSecretVaultStorage.redeemUseToken(
            lease.useToken ?? "",
            projectID: "proj-1",
            baseDir: base
        )
        XCTAssertFalse(replay.ok)
        XCTAssertEqual(replay.reasonCode, "secret_vault_use_token_not_found")
    }
}
