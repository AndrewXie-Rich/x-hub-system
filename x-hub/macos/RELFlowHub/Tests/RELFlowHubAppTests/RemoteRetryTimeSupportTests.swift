import XCTest
@testable import RELFlowHub
import RELFlowHubCore

@MainActor
final class RemoteRetryTimeSupportTests: XCTestCase {
    func testEnrichedDetailAppendsRetryEstimateForExpiredCodexToken() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        addTeardownBlock {
            CodexUsageService.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }
        let futureResetDate = Date().addingTimeInterval(6 * 60 * 60)
        let futureResetAt = Int(futureResetDate.timeIntervalSince1970.rounded())
        let expectedRetryAtText = formattedUTCRetryText(futureResetDate)

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
                  "account_key": "openai:expired-auth",
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

        let model = RemoteModelEntry(
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

        CodexUsageService.httpDataOverride = { request in
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

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try JSONSerialization.data(withJSONObject: [
                "rate_limit": [
                    "allowed": true,
                    "limit_reached": false,
                    "primary_window": [
                        "used_percent": 42.0,
                        "limit_window_seconds": 10_800,
                        "reset_at": futureResetAt,
                    ],
                ],
            ])
            return (payload, response)
        }

        let detail = await RemoteRetryTimeSupport.enrichedDetail(
            "Provider ** (status=401): Your authentication token has expired. Please try signing in again. [token_expired]",
            category: .auth,
            model: model
        )

        XCTAssertTrue(detail.contains("token_expired"))
        XCTAssertTrue(detail.contains("预计下次可用：\(expectedRetryAtText)"))
    }

    func testRetryAtTextFallsBackToStoredNextRetryAtWhenUsageEstimateUnavailable() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        addTeardownBlock {
            CodexUsageService.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }
        let futureRetryDate = Date().addingTimeInterval(12 * 60 * 60)
        let futureRetryAtMs = Int64((futureRetryDate.timeIntervalSince1970 * 1000.0).rounded())
        let expectedRetryAtText = formattedUTCRetryText(futureRetryDate)

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
                  "account_key": "openai:stored-retry-auth",
                  "provider": "openai",
                  "email": "pool@test.local",
                  "api_key": "ey-stored-token",
                  "refresh_token": "refresh-token-1",
                  "base_url": "https://api.openai.com/v1",
                  "enabled": true,
                  "auth_type": "oauth",
                  "error_state": {
                    "status": "blocked_auth",
                    "status_message": "missing scope: api.responses.write",
                    "reason_code": "missing_scope",
                    "next_retry_at_ms": \(futureRetryAtMs),
                    "retry_at_source": "scheduler"
                  }
                }
              ]
            }
          }
        }
        """
        try providerStore.write(to: providerStoreURL, atomically: true, encoding: .utf8)

        CodexUsageService.httpDataOverride = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data("{}".utf8), response)
        }

        let model = RemoteModelEntry(
            id: "gpt-5.4",
            name: "GPT 5.4",
            backend: "openai",
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            apiKeyRef: "openai:api.openai.com",
            upstreamModelId: "gpt-5.4",
            wireAPI: "chat_completions",
            apiKey: "ey-stored-token"
        )

        let retryAtText = await RemoteRetryTimeSupport.retryAtText(
            from: "Provider 权限不足，缺少生成 scope:api.responses.write。",
            category: .auth,
            model: model
        )

        XCTAssertEqual(retryAtText, expectedRetryAtText)
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("relflowhub-remote-retry-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func formattedUTCRetryText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter.string(from: date)
    }
}
