import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct XTRustModelInventoryLiveBridgeTests {
    @Test
    func configurationStaysDefaultOffWithoutExplicitOptIn() {
        let defaults = UserDefaults(suiteName: "XTRustModelInventoryLiveBridgeTests.defaultOff.\(UUID().uuidString)")!
        let config = XTRustModelInventoryLiveBridge.configuration(
            defaults: defaults,
            environment: [:]
        )

        #expect(config.enabled == false)
        #expect(config.snapshotPath == nil)
        #expect(config.httpBaseURL == nil)
    }

    @Test
    func loadIfEnabledUsesConfiguredSnapshotFile() async throws {
        let fixtureURL = try #require(Bundle.module.url(
            forResource: "remote_missing_scope",
            withExtension: "json",
            subdirectory: nil
        ))
        XTRustModelInventoryLiveBridge.installConfigurationOverrideForTesting(
            XTRustModelInventoryLiveBridgeConfiguration(
                enabled: true,
                snapshotPath: fixtureURL.path,
                httpBaseURL: nil
            )
        )
        defer { XTRustModelInventoryLiveBridge.resetConfigurationOverrideForTesting() }

        let result = await XTRustModelInventoryLiveBridge.loadIfEnabled(
            runtimeBaseDir: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        )

        guard case .loaded(let snapshot) = result else {
            Issue.record("expected loaded Rust inventory snapshot, got \(result)")
            return
        }
        #expect(snapshot.source == "rust_inventory_snapshot_file")
        #expect(snapshot.projection.schemaVersion == "xhub.model_inventory.v1")
        #expect(snapshot.projection.firstRemoteScopeBlocked?.blockingReasonCode == "missing_scope:api.model.read")
        #expect(snapshot.projection.containsPotentialSecretMaterial == false)
    }

    @Test
    func loadIfEnabledRejectsRawSecretMaterial() async throws {
        let tempDir = try makeTempDir(prefix: "xt_rust_inventory_secret")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let url = tempDir.appendingPathComponent("inventory.json")
        let payload = """
        {
          "schema_version": "xhub.model_inventory.v1",
          "ok": true,
          "updated_at_ms": 1000,
          "api_key": "sk-should-not-cross-xt-bridge",
          "remote_models": [],
          "local_models": []
        }
        """
        try payload.write(to: url, atomically: true, encoding: .utf8)

        XTRustModelInventoryLiveBridge.installConfigurationOverrideForTesting(
            XTRustModelInventoryLiveBridgeConfiguration(
                enabled: true,
                snapshotPath: url.path,
                httpBaseURL: nil
            )
        )
        defer { XTRustModelInventoryLiveBridge.resetConfigurationOverrideForTesting() }

        let result = await XTRustModelInventoryLiveBridge.loadIfEnabled(
            runtimeBaseDir: tempDir
        )

        #expect(result == .unavailable(reasonCode: "secret_material_detected"))
    }

    private func makeTempDir(prefix: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
