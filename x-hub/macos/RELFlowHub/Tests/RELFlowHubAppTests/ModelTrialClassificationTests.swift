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
