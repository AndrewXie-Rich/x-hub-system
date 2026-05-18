import XCTest
@testable import RELFlowHubCore

final class ProviderKeyStorageRustRuntimeSnapshotTests: XCTestCase {
    func testLoadsProviderStoreSnapshotFromRustRuntimeSnapshotEnvelope() throws {
        let data = Data("""
        {
          "schema_version": "xhub.provider_bridge.v1",
          "ok": true,
          "command": "runtime-snapshot",
          "snapshot_schema_version": "xhub.provider_key_snapshot.v1",
          "snapshot": {
            "accounts": [
              {
                "account_key": "openai:test",
                "provider": "openai",
                "email": "user@example.com",
                "enabled": true,
                "auth_type": "api_key",
                "api_key_redacted": "sk-testabcd",
                "base_url": "https://api.openai.com/v1",
                "pool_id": "openai:api.openai.com:responses",
                "provider_host": "api.openai.com",
                "wire_api": "responses",
                "models": ["gpt-5.5"],
                "quota": {
                  "daily_token_cap": 10000,
                  "daily_tokens_used": 2500,
                  "daily_tokens_remaining": 7500,
                  "usage_windows": [
                    {
                      "key": "rate_limit:primary:18000",
                      "source": "rate_limit",
                      "window_key": "primary",
                      "label": "primary 5-hour window",
                      "limit_window_seconds": 18000,
                      "used_percent": 25.0,
                      "used_basis_points": 2500,
                      "remaining_basis_points": 7500,
                      "limited": false,
                      "reset_at_ms": 123456,
                      "updated_at_ms": 120000
                    }
                  ]
                },
                "error_state": {
                  "status": "healthy"
                },
                "refresh_state": {
                  "status": "idle",
                  "next_refresh_at_ms": 130000
                },
                "created_at_ms": 1000,
                "updated_at_ms": 2000
              }
            ],
            "import_source_statuses": [
              {
                "source_key": "config_path:/tmp/config.toml",
                "kind": "config_path",
                "source_ref": "/tmp/config.toml",
                "state": "synced",
                "last_sync_at_ms": 2000,
                "last_imported_count": 1,
                "owned_account_count": 1,
                "last_error_count": 0,
                "last_errors": [],
                "updated_at_ms": 2000
              }
            ],
            "updated_at_ms": 2000,
            "global_routing_strategy": "fill-first",
            "providers": [
              {
                "provider": "openai",
                "routing_strategy": "balanced"
              }
            ]
          }
        }
        """.utf8)

        let snapshot = try XCTUnwrap(ProviderKeyStorage.loadRustRuntimeSnapshotData(data))

        XCTAssertEqual(snapshot.schemaVersion, "xhub.provider_key_snapshot.v1")
        XCTAssertEqual(snapshot.updatedAtMs, 2000)
        XCTAssertEqual(snapshot.globalRoutingStrategy, "fill-first")
        XCTAssertEqual(snapshot.providerGroups.count, 1)
        XCTAssertEqual(snapshot.providerGroups.first?.provider, "openai")
        XCTAssertEqual(snapshot.providerGroups.first?.routingStrategy, "balanced")
        XCTAssertEqual(snapshot.importSources.first?.sourceKey, "config_path:/tmp/config.toml")

        let account = try XCTUnwrap(snapshot.providerGroups.first?.accounts.first)
        XCTAssertEqual(account.accountKey, "openai:test")
        XCTAssertEqual(account.apiKeyRedacted, "sk-t...abcd")
        XCTAssertEqual(account.quota.dailyTokenCap, 10000)
        XCTAssertEqual(account.quota.usageWindows.first?.limitWindowSeconds, 18000)
        XCTAssertEqual(account.refreshState.nextRefreshAtMs, 130000)
        XCTAssertEqual(snapshot.quotaPools.count, 1)
    }

    func testRejectsFailedRustRuntimeSnapshotEnvelope() {
        let data = Data(#"{"ok":false,"snapshot":{"accounts":[]}}"#.utf8)

        XCTAssertNil(ProviderKeyStorage.loadRustRuntimeSnapshotData(data))
    }
}
