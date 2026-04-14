import XCTest
@testable import RELFlowHub
import RELFlowHubCore

final class LocalModelHealthSectionSummarySupportTests: XCTestCase {
    func testPresentationCountsAvailableReviewDiscouragedAndUnscannedModels() {
        let now = Date().timeIntervalSince1970
        let models = [
            makeModel(id: "healthy"),
            makeModel(id: "review"),
            makeModel(id: "blocked"),
            makeModel(id: "missing"),
        ]
        let snapshot = LocalModelHealthSnapshot(
            records: [
                makeRecord(modelID: "healthy", state: .healthy, checkedAt: now - 60),
                makeRecord(modelID: "review", state: .degraded, checkedAt: now - 60),
                makeRecord(modelID: "blocked", state: .blockedRuntime, checkedAt: now - 60),
            ],
            updatedAt: now
        )

        let presentation = LocalModelHealthSectionSummarySupport.presentation(
            models: models,
            healthSnapshot: snapshot,
            scanningModelIDs: [],
            now: now
        )

        XCTAssertEqual(
            presentation,
            LocalModelHealthSectionSummaryPresentation(
                scanningCount: 0,
                availableCount: 1,
                reviewCount: 1,
                discouragedCount: 1,
                unscannedCount: 1,
                text: "可用 1 · 待复检 1 · 不推荐 1 · 未扫描 1"
            )
        )
    }

    func testPresentationIncludesScanningOverlayAndTreatsStaleAsReview() {
        let now = Date().timeIntervalSince1970
        let staleCheckedAt = now - (LocalModelHealthSupport.staleAfter + 60)
        let models = [
            makeModel(id: "stale"),
            makeModel(id: "scanning"),
        ]
        let snapshot = LocalModelHealthSnapshot(
            records: [
                makeRecord(modelID: "stale", state: .healthy, checkedAt: staleCheckedAt),
                makeRecord(modelID: "scanning", state: .healthy, checkedAt: now - 30),
            ],
            updatedAt: now
        )

        let presentation = LocalModelHealthSectionSummarySupport.presentation(
            models: models,
            healthSnapshot: snapshot,
            scanningModelIDs: ["scanning"],
            now: now
        )

        XCTAssertEqual(presentation?.scanningCount, 1)
        XCTAssertEqual(presentation?.availableCount, 1)
        XCTAssertEqual(presentation?.reviewCount, 1)
        XCTAssertEqual(presentation?.discouragedCount, 0)
        XCTAssertEqual(presentation?.unscannedCount, 0)
        XCTAssertEqual(presentation?.text, "扫描中 1 · 可用 1 · 待复检 1")
    }

    func testPresentationShowsZeroAvailableWhenNoLocalModelIsRecommended() {
        let now = Date().timeIntervalSince1970
        let models = [
            makeModel(id: "blocked"),
            makeModel(id: "missing"),
        ]
        let snapshot = LocalModelHealthSnapshot(
            records: [
                makeRecord(modelID: "blocked", state: .blockedRuntime, checkedAt: now - 60),
            ],
            updatedAt: now
        )

        let presentation = LocalModelHealthSectionSummarySupport.presentation(
            models: models,
            healthSnapshot: snapshot,
            scanningModelIDs: [],
            now: now
        )

        XCTAssertEqual(presentation?.availableCount, 0)
        XCTAssertEqual(presentation?.text, "可用 0 · 不推荐 1 · 未扫描 1")
    }

    private func makeModel(id: String) -> HubModel {
        HubModel(
            id: id,
            name: id,
            backend: "mlx",
            quant: "Q4_K_M",
            contextLength: 8192,
            paramsB: 7.0,
            state: .available,
            modelPath: "/tmp/\(id)"
        )
    }

    private func makeRecord(
        modelID: String,
        state: LocalModelHealthState,
        checkedAt: TimeInterval
    ) -> LocalModelHealthRecord {
        LocalModelHealthRecord(
            modelId: modelID,
            providerID: "mlx",
            state: state,
            summary: "state",
            detail: "detail",
            lastCheckedAt: checkedAt,
            lastSuccessAt: state == .healthy ? checkedAt : nil
        )
    }
}
