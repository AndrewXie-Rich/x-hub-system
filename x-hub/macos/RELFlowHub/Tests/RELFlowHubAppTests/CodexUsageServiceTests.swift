import XCTest
@testable import RELFlowHub
import RELFlowHubCore

@MainActor
final class CodexUsageServiceTests: XCTestCase {
    func testRetryEstimateUsesLatestBlockedWindowReset() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        addTeardownBlock {
            CodexUsageService.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let providerStoreURL = SharedPaths.ensureHubDirectory().appendingPathComponent("hub_provider_keys.json")
        try FileManager.default.createDirectory(
            at: providerStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let providerStore = """
        {
          "schema_version": "hub_provider_keys.v1",
          "updated_at_ms": 1717000000000,
          "routing_strategy": "fill-first",
          "providers": {
            "openai": {
              "accounts": [
                {
                  "account_key": "openai:codex-auth",
                  "provider": "openai",
                  "email": "pool@test.local",
                  "api_key": "ey-window-token",
                  "refresh_token": "refresh-token",
                  "base_url": "https://api.openai.com/v1",
                  "enabled": true,
                  "auth_type": "oauth",
                  "account_id": "acct-window-1"
                }
              ]
            }
          }
        }
        """
        try providerStore.write(to: providerStoreURL, atomically: true, encoding: .utf8)

        let credential = try XCTUnwrap(
            ProviderKeyStorage.loadResolvedCredential(accountKey: "openai:codex-auth")
        )

        CodexUsageService.httpDataOverride = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ey-window-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct-window-1")

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try JSONSerialization.data(withJSONObject: [
                "rate_limit": [
                    "allowed": false,
                    "limit_reached": true,
                    "primary_window": [
                        "used_percent": 100.0,
                        "limit_window_seconds": 10_800,
                        "reset_at": 1_776_729_600,
                    ],
                    "secondary_window": [
                        "used_percent": 100.0,
                        "limit_window_seconds": 86_400,
                        "reset_at": 1_776_816_000,
                    ],
                ],
            ])
            return (payload, response)
        }

        let estimate = await CodexUsageService.retryEstimate(
            for: credential,
            preference: .blockingOnly
        )

        XCTAssertEqual(estimate?.retryAtMs, 1_776_816_000_000)
        XCTAssertEqual(estimate?.retryAtText, "2026-04-22 00:00 UTC")
        XCTAssertEqual(estimate?.retryAtSource, "usage_window")
        XCTAssertEqual(estimate?.isQuotaBlocked, true)
    }

    func testRetryEstimateRefreshesExpiredTokenAndPersistsUpdatedCredentials() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        addTeardownBlock {
            CodexUsageService.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let providerStoreURL = SharedPaths.ensureHubDirectory().appendingPathComponent("hub_provider_keys.json")
        try FileManager.default.createDirectory(
            at: providerStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let providerStore = """
        {
          "schema_version": "hub_provider_keys.v1",
          "updated_at_ms": 1717000000000,
          "routing_strategy": "fill-first",
          "providers": {
            "openai": {
              "accounts": [
                {
                  "account_key": "openai:codex-auth",
                  "provider": "openai",
                  "email": "pool@test.local",
                  "api_key": "ey-expired-token",
                  "refresh_token": "refresh-token-1",
                  "base_url": "https://api.openai.com/v1",
                  "enabled": true,
                  "auth_type": "oauth",
                  "account_id": "acct-refresh-1"
                }
              ]
            }
          }
        }
        """
        try providerStore.write(to: providerStoreURL, atomically: true, encoding: .utf8)

        let remoteModel = RemoteModelEntry(
            id: "gpt-5.4",
            name: "GPT 5.4",
            backend: "openai",
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            apiKeyRef: "openai:api.openai.com",
            upstreamModelId: "gpt-5.4",
            wireAPI: "chat_completions",
            apiKey: "ey-expired-token"
        )
        RemoteModelStorage.save(.init(models: [remoteModel], updatedAt: 0))

        let credential = try XCTUnwrap(
            ProviderKeyStorage.loadResolvedCredential(accountKey: "openai:codex-auth")
        )

        var requests: [String] = []
        CodexUsageService.httpDataOverride = { request in
            requests.append("\(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")

            if request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage",
               request.value(forHTTPHeaderField: "Authorization") == "Bearer ey-expired-token" {
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (Data(#"{"detail":"token_invalidated"}"#.utf8), response)
            }

            if request.url?.absoluteString == "https://auth.openai.com/oauth/token" {
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let payload = try JSONSerialization.data(withJSONObject: [
                    "access_token": "ey-new-token",
                    "refresh_token": "refresh-token-2",
                    "token_type": "Bearer",
                    "expires_in": 3600,
                ])
                return (payload, response)
            }

            XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ey-new-token")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try JSONSerialization.data(withJSONObject: [
                "rate_limit": [
                    "allowed": false,
                    "limit_reached": true,
                    "primary_window": [
                        "used_percent": 100.0,
                        "reset_at": 1_776_729_600,
                    ],
                ],
            ])
            return (payload, response)
        }

        let estimate = await CodexUsageService.retryEstimate(
            for: credential,
            preference: .blockingOnly
        )

        XCTAssertEqual(
            requests,
            [
                "GET https://chatgpt.com/backend-api/wham/usage",
                "POST https://auth.openai.com/oauth/token",
                "GET https://chatgpt.com/backend-api/wham/usage",
            ]
        )
        XCTAssertEqual(estimate?.retryAtMs, 1_776_729_600_000)
        XCTAssertEqual(estimate?.retryAtText, "2026-04-21 00:00 UTC")
        XCTAssertEqual(estimate?.retryAtSource, "usage_window")

        let refreshedCredential = try XCTUnwrap(
            ProviderKeyStorage.loadResolvedCredential(accountKey: "openai:codex-auth")
        )
        XCTAssertEqual(refreshedCredential.apiKey, "ey-new-token")
        XCTAssertEqual(refreshedCredential.refreshToken, "refresh-token-2")
        XCTAssertGreaterThan(refreshedCredential.expiresAtMs, 0)

        let refreshedModel = try XCTUnwrap(
            RemoteModelStorage.load().models.first(where: { $0.id == "gpt-5.4" })
        )
        XCTAssertEqual(refreshedModel.apiKey, "ey-new-token")
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("relflowhub-codex-usage-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
