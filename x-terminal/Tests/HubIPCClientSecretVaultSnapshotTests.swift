import Foundation
import Testing
@testable import XTerminal

struct HubIPCClientSecretVaultSnapshotTests {
    @Test
    func requestSecretVaultSnapshotReadsLocalSnapshotAndFailsClosedForProjectScopedItems() async throws {
        let originalMode = HubAIClient.transportMode()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_hub_secret_vault_snapshot_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        HubAIClient.setTransportMode(.fileIPC)
        HubPaths.setPinnedBaseDirOverride(base)
        defer {
            HubAIClient.setTransportMode(originalMode)
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
        }

        let payload: [String: Any] = [
            "schema_version": "secret_vault_items_status.v1",
            "updated_at_ms": 1_773_320_290_000,
            "items": [
                [
                    "item_id": "secret-openai-old",
                    "scope": "project",
                    "name": "openai.api_key.primary",
                    "sensitivity": "secret",
                    "created_at_ms": 1_773_320_010_000,
                    "updated_at_ms": 1_773_320_050_000,
                ],
                [
                    "item_id": "secret-openai-new",
                    "scope": "project",
                    "name": "openai.api_key.backup",
                    "sensitivity": "secret",
                    "created_at_ms": 1_773_320_060_000,
                    "updated_at_ms": 1_773_320_180_000,
                ],
                [
                    "item_id": "secret-slack",
                    "scope": "project",
                    "name": "slack.bot_token",
                    "sensitivity": "secret",
                    "created_at_ms": 1_773_320_070_000,
                    "updated_at_ms": 1_773_320_190_000,
                ],
                [
                    "item_id": "secret-user-openai",
                    "scope": "user",
                    "name": "openai.api_key.personal",
                    "sensitivity": "secret",
                    "created_at_ms": 1_773_320_080_000,
                    "updated_at_ms": 1_773_320_200_000,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: base.appendingPathComponent("secret_vault_items_status.json"), options: .atomic)

        let snapshot = await HubIPCClient.requestSecretVaultSnapshot(
            scope: nil,
            namePrefix: "openai.api_key",
            limit: 10
        )
        let resolved = try #require(snapshot)

        #expect(resolved.source == "hub_secret_vault_file")
        #expect(resolved.updatedAtMs == 1_773_320_290_000)
        #expect(resolved.items.count == 1)
        #expect(resolved.items.map(\.itemId) == ["secret-user-openai"])
        #expect(resolved.items.allSatisfy { $0.scope != "project" })
        #expect(resolved.items.allSatisfy { $0.name.hasPrefix("openai.api_key") })
        #expect(resolved.items.first?.sensitivity == "secret")
        #expect(resolved.items.first?.updatedAtMs == 1_773_320_200_000)
    }
}
