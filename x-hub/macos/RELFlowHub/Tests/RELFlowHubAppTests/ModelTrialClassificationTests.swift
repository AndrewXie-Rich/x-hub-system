import XCTest
@testable import RELFlowHub

final class ModelTrialClassificationTests: XCTestCase {
    func testQuotaMessagesMapToQuotaCategory() {
        XCTAssertEqual(
            hubClassifyModelTrialFailure(
                "Provider 配额不足或额度已用尽（status=429）：You exceeded your current quota."
            ),
            .quota
        )
    }

    func testUsageLimitMessagesMapToQuotaCategory() {
        XCTAssertEqual(
            hubClassifyModelTrialFailure(
                "当前额度已用完，可升级 Plus，或到 Apr 15th, 2026 8:58 AM 再试。"
            ),
            .quota
        )
    }

    func testRateLimitResetMessagesMapToQuotaCategory() {
        XCTAssertEqual(
            hubClassifyModelTrialFailure(
                "Your rate limit resets on Apr 15, 2026, 8:58 AM. To continue using Codex, upgrade to Plus today."
            ),
            .quota
        )
    }

    func testRateLimitMessagesMapToRateLimitCategory() {
        XCTAssertEqual(
            hubClassifyModelTrialFailure(
                "Provider 当前正在限流，请稍后重试（status=429）：Rate limit reached for requests per min."
            ),
            .rateLimit
        )
    }

    func testAuthMessagesMapToAuthCategory() {
        XCTAssertEqual(
            hubClassifyModelTrialFailure("API Key 未设置。"),
            .auth
        )
    }

    func testInvalidAPIKeyNoticeProjectsAsAuthCategory() {
        let projection = RemoteProviderKeyRuntimeFeedbackSupport.failureProjection(
            accountKey: "openai:test",
            provider: "openai",
            modelID: "gpt-5.4",
            status: 401,
            error: "Provider API Key 无效或已被撤销（status=401）。请重新粘贴有效的 Provider API Key，或在服务商后台轮换后再导入。"
        )

        XCTAssertEqual(projection.event.outcome, "auth_error")
        XCTAssertEqual(projection.event.reasonCode, "invalid_api_key")
        XCTAssertEqual(
            RemoteProviderKeyRuntimeFeedbackSupport.projectedCategory(
                status: 401,
                error: "Provider API Key 无效或已被撤销（status=401）。请重新粘贴有效的 Provider API Key，或在服务商后台轮换后再导入。"
            ),
            .auth
        )
        XCTAssertEqual(
            RemoteProviderKeyRuntimeFeedbackSupport.projectedHealthState(
                status: 401,
                error: "Provider API Key 无效或已被撤销（status=401）。请重新粘贴有效的 Provider API Key，或在服务商后台轮换后再导入。"
            ),
            .blockedAuth
        )
    }

    func testTimeoutMessagesMapToTimeoutCategory() {
        XCTAssertEqual(
            hubClassifyModelTrialFailure("AI 请求超时"),
            .timeout
        )
    }

    func testRuntimeMessagesMapToRuntimeCategory() {
        XCTAssertEqual(
            hubClassifyModelTrialFailure("Python runtime warmup failed while preparing provider"),
            .runtime
        )
    }

    func testConfigMessagesMapToConfigCategory() {
        XCTAssertEqual(
            hubClassifyModelTrialFailure("Hub 当前没有把这个远程模型挂到可执行面。请先 Load 再试。"),
            .config
        )
    }
}
