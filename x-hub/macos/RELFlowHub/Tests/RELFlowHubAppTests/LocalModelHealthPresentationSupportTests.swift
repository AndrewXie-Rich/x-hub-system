import XCTest
@testable import RELFlowHub
import RELFlowHubCore

final class LocalModelHealthPresentationSupportTests: XCTestCase {
    func testHealthyPresentationMentionsDefaultPriority() {
        let now = Date().timeIntervalSince1970
        let record = LocalModelHealthRecord(
            modelId: "mlx/qwen",
            providerID: "mlx",
            state: .healthy,
            summary: "",
            detail: "轻量扫描通过。Response OK",
            lastCheckedAt: now,
            lastSuccessAt: now
        )

        let presentation = LocalModelHealthPresentationSupport.presentation(
            health: record,
            isScanning: false
        )

        XCTAssertEqual(presentation?.badgeText, HubUIStrings.Models.LocalHealth.recommendedBadge)
        XCTAssertTrue(presentation?.detailText.contains("默认会优先考虑这个本地模型。") == true)
    }

    func testStalePresentationFallsBackToReviewBadge() {
        let stalePresentation = LocalModelHealthPresentationSupport.presentation(
            health: LocalModelHealthRecord(
                modelId: "mlx/qwen",
                providerID: "mlx",
                state: .healthy,
                summary: "",
                detail: "轻量扫描通过。Response OK",
                lastCheckedAt: Date().timeIntervalSince1970 - LocalModelHealthSupport.staleAfter - 10,
                lastSuccessAt: Date().timeIntervalSince1970 - LocalModelHealthSupport.staleAfter - 10
            ),
            isScanning: false
        )

        XCTAssertEqual(stalePresentation?.badgeText, HubUIStrings.Models.LocalHealth.reviewBadge)
        XCTAssertTrue(stalePresentation?.detailText.contains("上次扫描结果已过期") == true)
    }

    func testReviewStatesSurfaceRescanAction() {
        let record = LocalModelHealthRecord(
            modelId: "hf-qwen",
            providerID: "transformers",
            state: .degraded,
            summary: "",
            detail: "预检通过，但还没有新的轻量扫描结果。",
            lastCheckedAt: Date().timeIntervalSince1970,
            lastSuccessAt: nil
        )

        XCTAssertTrue(
            LocalModelHealthPresentationSupport.shouldSurfaceRescanAction(
                health: record,
                isScanning: false
            )
        )
        XCTAssertFalse(
            LocalModelHealthPresentationSupport.shouldSurfaceRescanAction(
                health: record,
                isScanning: true
            )
        )
    }

    func testHealthyStateDoesNotSurfaceRescanAction() {
        let now = Date().timeIntervalSince1970
        let record = LocalModelHealthRecord(
            modelId: "mlx/qwen",
            providerID: "mlx",
            state: .healthy,
            summary: "",
            detail: "轻量扫描通过。Response OK",
            lastCheckedAt: now,
            lastSuccessAt: now
        )

        XCTAssertFalse(
            LocalModelHealthPresentationSupport.shouldSurfaceRescanAction(
                health: record,
                isScanning: false
            )
        )
    }

    func testSortedPrefersHealthyModelsBeforeBlockedModels() {
        let now = Date().timeIntervalSince1970
        let blocked = HubModel(
            id: "blocked",
            name: "Blocked",
            backend: "mlx",
            quant: "Q4",
            contextLength: 8192,
            paramsB: 7.0,
            state: .loaded,
            modelPath: "/tmp/blocked"
        )
        let healthy = HubModel(
            id: "healthy",
            name: "Healthy",
            backend: "mlx",
            quant: "Q4",
            contextLength: 8192,
            paramsB: 7.0,
            state: .available,
            modelPath: "/tmp/healthy"
        )
        let snapshot = LocalModelHealthSnapshot(
            records: [
                LocalModelHealthRecord(
                    modelId: "blocked",
                    providerID: "mlx",
                    state: .blockedRuntime,
                    summary: "",
                    detail: "",
                    lastCheckedAt: now,
                    lastSuccessAt: nil
                ),
                LocalModelHealthRecord(
                    modelId: "healthy",
                    providerID: "mlx",
                    state: .healthy,
                    summary: "",
                    detail: "",
                    lastCheckedAt: now,
                    lastSuccessAt: now
                ),
            ],
            updatedAt: now
        )

        let sorted = LocalModelHealthPresentationSupport.sorted([blocked, healthy], healthSnapshot: snapshot)

        XCTAssertEqual(sorted.map(\.id), ["healthy", "blocked"])
    }
}
