import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import XTerminal

@Suite(.serialized)
struct ProviderKeySnapshotStoreTests {
    @Test
    func runtimeMetadataLoadRequiresExplicitCompatibilityFallback() throws {
        let tempDir = try makeTempDir(prefix: "provider_key_runtime_metadata_snapshot_store")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try writeProviderKeySnapshotFixture(to: tempDir)

        try withProviderKeySnapshotFixtureBaseDir(tempDir) {
            #expect(HubProviderKeyAccountRuntimeMetadataSnapshotStore.load().isEmpty)

            let fallback = HubProviderKeyAccountRuntimeMetadataSnapshotStore.load(
                allowCompatibilityFallback: true
            )
            let account = try #require(fallback["acct-gemini-primary"])
            #expect(account.provider == "google")
            #expect(account.authType == "oauth")
            #expect(account.oauthSourceKey == "gemini-cli")
            #expect(account.requiredRefreshMetadata == ["client_secret", "token_uri"])

            #expect(HubProviderKeyAccountRuntimeMetadataSnapshotStore.load() == fallback)
        }
    }

    @Test
    func importSnapshotLoadRequiresExplicitCompatibilityFallback() throws {
        let tempDir = try makeTempDir(prefix: "provider_key_import_snapshot_store")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try writeProviderKeySnapshotFixture(to: tempDir)

        try withProviderKeySnapshotFixtureBaseDir(tempDir) {
            #expect(HubProviderKeyImportSnapshotStore.load() == nil)

            let fallback = try #require(
                HubProviderKeyImportSnapshotStore.load(allowCompatibilityFallback: true)
            )
            #expect(fallback.sources.count == 1)
            #expect(fallback.sources.first?.sourceKey == "auth_dir:/tmp/auth19.json")
            #expect(fallback.sources.first?.state == "error")
            #expect(fallback.accountSourceOwners["acct-gemini-primary"] == ["auth_dir:/tmp/auth19.json"])
            #expect(
                fallback.sources(forAccountKey: "acct-gemini-primary").map(\.sourceKey)
                    == ["auth_dir:/tmp/auth19.json"]
            )

            #expect(HubProviderKeyImportSnapshotStore.load() == fallback)
        }
    }

    @Test
    func refreshFromHubDoesNotUseCompatibilityFileUnlessExplicitlyAllowed() async throws {
        let tempDir = try makeTempDir(prefix: "provider_key_snapshot_refresh")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try writeProviderKeySnapshotFixture(to: tempDir)
        let stateDir = tempDir.appendingPathComponent("axhub", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)

        await withAXHubStateDirAsync(stateDir) {
            await withProviderKeySnapshotFixtureBaseDirAsync(tempDir) {
                let noFallbackSnapshot = await HubProviderKeyImportSnapshotStore.refreshFromHub()
                #expect(noFallbackSnapshot == nil)
                #expect(HubProviderKeyImportSnapshotStore.load() == nil)

                let fallbackSnapshot = await HubProviderKeyImportSnapshotStore.refreshFromHub(
                    allowCompatibilityFallback: true
                )
                #expect(fallbackSnapshot?.sources.first?.sourceKey == "auth_dir:/tmp/auth19.json")
                #expect(HubProviderKeyImportSnapshotStore.load() == fallbackSnapshot)
            }
        }
    }

    private func withProviderKeySnapshotFixtureBaseDir(
        _ baseDir: URL,
        body: () throws -> Void
    ) rethrows {
        HubPaths.setPinnedBaseDirOverride(baseDir)
        HubPaths.setCandidateBaseDirsOverrideForTesting([baseDir])
        HubProviderKeyAccountRuntimeMetadataSnapshotStore.resetForTesting()
        HubProviderKeyImportSnapshotStore.resetForTesting()
        defer {
            HubProviderKeyAccountRuntimeMetadataSnapshotStore.resetForTesting()
            HubProviderKeyImportSnapshotStore.resetForTesting()
            HubPaths.clearPinnedBaseDirOverride()
            HubPaths.setCandidateBaseDirsOverrideForTesting(nil)
        }
        try body()
    }

    private func withProviderKeySnapshotFixtureBaseDirAsync(
        _ baseDir: URL,
        body: () async throws -> Void
    ) async rethrows {
        HubPaths.setPinnedBaseDirOverride(baseDir)
        HubPaths.setCandidateBaseDirsOverrideForTesting([baseDir])
        HubProviderKeyAccountRuntimeMetadataSnapshotStore.resetForTesting()
        HubProviderKeyImportSnapshotStore.resetForTesting()
        defer {
            HubProviderKeyAccountRuntimeMetadataSnapshotStore.resetForTesting()
            HubProviderKeyImportSnapshotStore.resetForTesting()
            HubPaths.clearPinnedBaseDirOverride()
            HubPaths.setCandidateBaseDirsOverrideForTesting(nil)
        }
        try await body()
    }

    private func makeTempDir(prefix: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func withAXHubStateDirAsync(
        _ stateDir: URL,
        body: () async throws -> Void
    ) async rethrows {
        let key = "AXHUBCTL_STATE_DIR"
        let previous = getenv(key).flatMap { String(validatingUTF8: $0) }
        setenv(key, stateDir.path, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        try await body()
    }

    private func writeProviderKeySnapshotFixture(to baseDir: URL) throws {
        let payload = """
        {
          "providers": {
            "google": {
              "accounts": [
                {
                  "account_key": "acct-gemini-primary",
                  "provider": "google",
                  "auth_type": "oauth",
                  "oauth_source_key": "gemini-cli",
                  "oauth_refresh_config": {
                    "client_id": "gemini-client"
                  },
                  "source_owners": ["auth_dir:/tmp/auth19.json"]
                }
              ]
            }
          },
          "import_source_statuses": {
            "auth_dir:/tmp/auth19.json": {
              "kind": "auth_dir",
              "source_ref": "/tmp/auth19.json",
              "state": "error",
              "last_sync_at_ms": 1234,
              "last_imported_count": 1,
              "owned_account_count": 1,
              "last_error_count": 1,
              "last_errors": ["token_expired"]
            }
          }
        }
        """
        try payload.write(
            to: baseDir.appendingPathComponent("hub_provider_keys.json"),
            atomically: true,
            encoding: .utf8
        )
    }
}
