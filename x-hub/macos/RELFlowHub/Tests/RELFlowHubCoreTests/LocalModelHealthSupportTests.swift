import XCTest
@testable import RELFlowHubCore

final class LocalModelHealthSupportTests: XCTestCase {
    func testEffectiveStateBecomesStaleAfterOneDay() {
        let record = LocalModelHealthRecord(
            modelId: "mlx/qwen",
            providerID: "mlx",
            state: .healthy,
            summary: "",
            detail: "",
            lastCheckedAt: 100,
            lastSuccessAt: 100
        )

        let state = LocalModelHealthSupport.effectiveState(
            for: record,
            now: 100 + LocalModelHealthSupport.staleAfter + 1
        )

        XCTAssertEqual(state, .unknownStale)
    }

    func testRecommendationDiscouragesBlockedRuntimeModels() {
        let record = LocalModelHealthRecord(
            modelId: "mlx/deepseek",
            providerID: "mlx",
            state: .blockedRuntime,
            summary: "",
            detail: "",
            lastCheckedAt: 100,
            lastSuccessAt: nil
        )

        XCTAssertEqual(LocalModelHealthSupport.recommendation(for: record, now: 100), .discouraged)
    }
}
