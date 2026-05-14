import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import XTerminal

@Suite(.serialized)
struct HubIPCClientSecretVaultSnapshotTests {
    @Test
    func requestSecretVaultSnapshotReadsLocalSnapshotAndFailsClosedForProjectScopedItems() async throws {
        let originalMode = HubAIClient.transportMode()
        let defaults = UserDefaults.standard
        let defaultsKey = "xterminal_hub_base_dir"
        let previousBaseDir = defaults.object(forKey: defaultsKey)
        let envKey = "REL_FLOW_HUB_BASE_DIR"
        let previousEnv = getenv(envKey).flatMap { String(validatingUTF8: $0) }
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_hub_secret_vault_snapshot_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        HubAIClient.setTransportMode(.fileIPC)
        HubPaths.setPinnedBaseDirOverride(base)
        HubPaths.setCandidateBaseDirsOverrideForTesting([base])
        defaults.set(base.path, forKey: defaultsKey)
        unsetenv(envKey)
        defer {
            HubAIClient.setTransportMode(originalMode)
            HubPaths.clearPinnedBaseDirOverride()
            HubPaths.setCandidateBaseDirsOverrideForTesting(nil)
            if let previousBaseDir {
                defaults.set(previousBaseDir, forKey: defaultsKey)
            } else {
                defaults.removeObject(forKey: defaultsKey)
            }
            if let previousEnv {
                setenv(envKey, previousEnv, 1)
            } else {
                unsetenv(envKey)
            }
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

    @Test
    func requestSecretVaultSnapshotPrefersLocalIPCOverCompatibilityFileSnapshot() async throws {
        let originalMode = HubAIClient.transportMode()
        let defaults = UserDefaults.standard
        let defaultsKey = "xterminal_hub_base_dir"
        let previousBaseDir = defaults.object(forKey: defaultsKey)
        let envKey = "REL_FLOW_HUB_BASE_DIR"
        let previousEnv = getenv(envKey).flatMap { String(validatingUTF8: $0) }
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_hub_secret_vault_snapshot_ipc_\(UUID().uuidString)", isDirectory: true)
        let ipcDir = base.appendingPathComponent("ipc_events", isDirectory: true)
        let responseDir = base.appendingPathComponent("ipc_responses", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ipcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: responseDir, withIntermediateDirectories: true)

        HubAIClient.setTransportMode(.fileIPC)
        HubPaths.setPinnedBaseDirOverride(base)
        HubPaths.setCandidateBaseDirsOverrideForTesting([base])
        defaults.set(base.path, forKey: defaultsKey)
        unsetenv(envKey)
        HubIPCClient.installIPCEventWriteOverrideForTesting { data, _, file in
            try data.write(to: file, options: .atomic)

            let request = try JSONDecoder().decode(
                HubIPCClient.SecretVaultListIPCRequest.self,
                from: data
            )
            let response = HubIPCClient.SecretVaultListIPCResponse(
                type: "secret_vault_list_result",
                reqId: request.reqId,
                ok: true,
                id: request.reqId,
                error: nil,
                secretVaultSnapshot: HubIPCClient.SecretVaultSnapshot(
                    source: "file_ipc",
                    updatedAtMs: 1_900,
                    items: [
                        HubIPCClient.SecretVaultItem(
                            itemId: "ipc-secret",
                            scope: "user",
                            name: "openai.api_key.primary",
                            sensitivity: "secret",
                            createdAtMs: 1_100,
                            updatedAtMs: 1_900
                        )
                    ]
                )
            )
            let responseData = try JSONEncoder().encode(response)
            try responseData.write(
                to: responseDir.appendingPathComponent("resp_\(request.reqId).json"),
                options: .atomic
            )
        }
        defer {
            HubIPCClient.resetIPCEventWriteOverrideForTesting()
            HubAIClient.setTransportMode(originalMode)
            HubPaths.clearPinnedBaseDirOverride()
            HubPaths.setCandidateBaseDirsOverrideForTesting(nil)
            if let previousBaseDir {
                defaults.set(previousBaseDir, forKey: defaultsKey)
            } else {
                defaults.removeObject(forKey: defaultsKey)
            }
            if let previousEnv {
                setenv(envKey, previousEnv, 1)
            } else {
                unsetenv(envKey)
            }
            try? FileManager.default.removeItem(at: base)
        }

        let hubStatus = HubStatus(
            pid: nil,
            startedAt: Date().timeIntervalSince1970,
            updatedAt: Date().timeIntervalSince1970,
            ipcMode: "file",
            ipcPath: ipcDir.path,
            baseDir: base.path,
            protocolVersion: 1,
            aiReady: true,
            loadedModelCount: 0,
            modelsUpdatedAt: Date().timeIntervalSince1970
        )
        let hubStatusData = try JSONEncoder().encode(hubStatus)
        try hubStatusData.write(to: base.appendingPathComponent("hub_status.json"), options: .atomic)

        let filePayload: [String: Any] = [
            "schema_version": "secret_vault_items_status.v1",
            "updated_at_ms": 100,
            "items": [
                [
                    "item_id": "file-secret",
                    "scope": "user",
                    "name": "openai.api_key.legacy",
                    "sensitivity": "secret",
                    "created_at_ms": 50,
                    "updated_at_ms": 100,
                ]
            ],
        ]
        let fileData = try JSONSerialization.data(withJSONObject: filePayload, options: [.sortedKeys])
        try fileData.write(to: base.appendingPathComponent("secret_vault_items_status.json"), options: .atomic)

        let snapshot = await HubIPCClient.requestSecretVaultSnapshot(
            scope: nil,
            namePrefix: "openai.api_key",
            limit: 10
        )
        let resolved = try #require(snapshot)

        #expect(resolved.source == "file_ipc")
        #expect(resolved.updatedAtMs == 1_900)
        #expect(resolved.items.map(\.itemId) == ["ipc-secret"])
        #expect(resolved.items.first?.name == "openai.api_key.primary")
    }
}
