import XCTest
@testable import RELFlowHub
import RELFlowHubCore

@MainActor
final class ProviderKeyRefreshCoordinatorTests: XCTestCase {
    func testNormalizedRetrySourceMapsLegacyValuesIntoContractEnum() {
        XCTAssertEqual(
            ProviderKeyRefreshCoordinator.normalizedRetrySource("codex_usage", nextRetryAtMs: 1),
            "usage_window"
        )
        XCTAssertEqual(
            ProviderKeyRefreshCoordinator.normalizedRetrySource("quota_refresh", nextRetryAtMs: 1),
            "usage_window"
        )
        XCTAssertEqual(
            ProviderKeyRefreshCoordinator.normalizedRetrySource(
                "refresh_schema",
                status: "degraded",
                reasonCode: "unsupported_refresh_schema"
            ),
            "manual"
        )
    }

    func testRetryDecisionUsesProviderDeclaredRetryTextBeforeUsageEstimate() async {
        defer { CodexUsageService.httpDataOverride = nil }
        let decision = await ProviderKeyRefreshCoordinator.retryDecision(
            from: "Your rate limit resets on Apr 15, 2026, 8:58 AM. To continue using Codex, upgrade to Plus today.",
            category: .quota,
            credential: makeCredential()
        )

        XCTAssertEqual(decision?.retryAtSource, "provider_header")
        XCTAssertEqual(decision?.retryAtText, "Apr 15, 2026, 8:58 AM")
        XCTAssertGreaterThan(decision?.nextRetryAtMs ?? 0, 0)
    }

    func testRetryDecisionUsesUsageWindowEstimateForPermissionStyleFailures() async throws {
        defer { CodexUsageService.httpDataOverride = nil }
        let futureResetAt = 1_776_729_600
        CodexUsageService.httpDataOverride = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
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
                        "reset_at": futureResetAt,
                    ],
                ],
            ])
            return (payload, response)
        }

        let decision = await ProviderKeyRefreshCoordinator.retryDecision(
            from: "Provider 权限不足，缺少生成 scope：api.responses.write。",
            category: .auth,
            state: .blockedAuth,
            credential: makeCredential()
        )

        XCTAssertEqual(decision?.nextRetryAtMs, 1_776_729_600_000)
        XCTAssertEqual(decision?.retryAtSource, "usage_window")
        XCTAssertEqual(decision?.retryAtText, "2026-04-21 00:00 UTC")
    }

    func testRetryDecisionFallsBackToStoredRetryAndNormalizesLegacySource() async {
        defer { CodexUsageService.httpDataOverride = nil }
        let futureRetryAtMs = Int64((Date().addingTimeInterval(4 * 60 * 60).timeIntervalSince1970 * 1000.0).rounded())
        var credential = makeCredential()
        credential.nextRetryAtMs = futureRetryAtMs
        credential.retryAtSource = "codex_usage"
        credential.reasonCode = "missing_scope"

        let decision = await ProviderKeyRefreshCoordinator.retryDecision(
            from: "Provider 权限不足，缺少生成 scope：api.responses.write。",
            category: .auth,
            state: .blockedAuth,
            credential: credential
        )

        XCTAssertEqual(decision?.nextRetryAtMs, futureRetryAtMs)
        XCTAssertEqual(decision?.retryAtSource, "usage_window")
        XCTAssertNotNil(decision?.retryAtText)
    }

    func testRuntimeFailureDecisionUsesRefreshSourceForExpiredTokenWithRefreshCapability() {
        let nowMs = Int64(1_776_000_000_000)
        let decision = ProviderKeyRefreshCoordinator.runtimeFailureDecision(
            for: .init(
                accountKey: "openai:test",
                provider: "openai",
                modelID: "gpt-5.4",
                outcome: "auth_error",
                httpStatus: 401,
                reasonCode: "token_expired",
                statusMessage: "Your authentication token has expired. Please try signing in again.",
                tokensUsed: 0,
                latencyMs: 1500,
                occurredAtMs: nowMs
            ),
            accountSupportsRefresh: true,
            nowMs: nowMs
        )

        XCTAssertEqual(decision.retryAtSource, "refresh")
        XCTAssertEqual(decision.nextRetryAtMs, nowMs + 60_000)
    }

    private func makeCredential() -> ProviderKeyResolvedCredential {
        ProviderKeyResolvedCredential(
            accountKey: "openai:test",
            provider: "openai",
            poolID: "openai:api.openai.com:chat_completions",
            providerHost: "api.openai.com",
            apiKey: "ey-test-token",
            refreshToken: "refresh-token",
            baseURL: "https://api.openai.com/v1",
            proxyURL: "",
            enabled: true,
            authType: "oauth",
            wireAPI: "chat_completions",
            expiresAtMs: 0,
            customHeaders: [:],
            models: ["gpt-5.4"],
            accountId: "acct-test-1",
            oauthSourceKey: "chatgpt",
            authIndex: 19,
            sourceType: "auth_file",
            sourceRef: "/tmp/auth19.json",
            statusMessage: "",
            reasonCode: "",
            lastRefreshAtMs: 0,
            nextRetryAtMs: 0,
            retryAtSource: ""
        )
    }
}
