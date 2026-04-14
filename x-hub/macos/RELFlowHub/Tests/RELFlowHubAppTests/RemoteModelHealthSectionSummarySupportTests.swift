import XCTest
@testable import RELFlowHub
import RELFlowHubCore

final class RemoteModelHealthSectionSummarySupportTests: XCTestCase {
    func testPresentationCountsKeyHealthStatesAcrossRemoteModels() {
        let models = [
            makeModel(id: "healthy", apiKeyRef: "k-healthy"),
            makeModel(id: "quota", apiKeyRef: "k-quota"),
            makeModel(id: "auth", apiKeyRef: "k-auth"),
            makeModel(id: "missing", apiKeyRef: "k-missing"),
        ]
        let snapshot = RemoteKeyHealthSnapshot(
            records: [
                makeHealth(keyReference: "k-healthy", state: .healthy),
                makeHealth(keyReference: "k-quota", state: .blockedQuota),
                makeHealth(keyReference: "k-auth", state: .blockedAuth),
            ],
            updatedAt: Date().timeIntervalSince1970
        )

        let presentation = RemoteModelHealthSectionSummarySupport.presentation(
            models: models,
            healthSnapshot: snapshot,
            scanningKeyReferences: []
        )

        XCTAssertEqual(
            presentation,
            RemoteModelHealthSectionSummaryPresentation(
                scanningCount: 0,
                availableCount: 1,
                reviewCount: 0,
                quotaCount: 1,
                authCount: 1,
                networkCount: 0,
                providerCount: 0,
                configCount: 0,
                unscannedCount: 1,
                text: "可用 1 · 额度 1 · 权限 1 · 未扫描 1"
            )
        )
    }

    func testPresentationIncludesScanningAndReviewCounts() {
        let models = [
            makeModel(id: "review", apiKeyRef: "k-review"),
            makeModel(id: "network", apiKeyRef: "k-network"),
        ]
        let snapshot = RemoteKeyHealthSnapshot(
            records: [
                makeHealth(keyReference: "k-review", state: .degraded),
                makeHealth(keyReference: "k-network", state: .blockedNetwork),
            ],
            updatedAt: Date().timeIntervalSince1970
        )

        let presentation = RemoteModelHealthSectionSummarySupport.presentation(
            models: models,
            healthSnapshot: snapshot,
            scanningKeyReferences: ["k-review"]
        )

        XCTAssertEqual(presentation?.scanningCount, 1)
        XCTAssertEqual(presentation?.reviewCount, 1)
        XCTAssertEqual(presentation?.networkCount, 1)
        XCTAssertEqual(presentation?.text, "扫描中 1 · 可用 0 · 待复检 1 · 网络 1")
    }

    func testPresentationShowsZeroAvailableWhenAllRemoteModelsBlocked() {
        let models = [
            makeModel(id: "quota", apiKeyRef: "k-quota"),
            makeModel(id: "auth", apiKeyRef: "k-auth"),
        ]
        let snapshot = RemoteKeyHealthSnapshot(
            records: [
                makeHealth(keyReference: "k-quota", state: .blockedQuota),
                makeHealth(keyReference: "k-auth", state: .blockedAuth),
            ],
            updatedAt: Date().timeIntervalSince1970
        )

        let presentation = RemoteModelHealthSectionSummarySupport.presentation(
            models: models,
            healthSnapshot: snapshot,
            scanningKeyReferences: []
        )

        XCTAssertEqual(presentation?.availableCount, 0)
        XCTAssertEqual(presentation?.text, "可用 0 · 额度 1 · 权限 1")
    }

    private func makeModel(id: String, apiKeyRef: String) -> RemoteModelEntry {
        RemoteModelEntry(
            id: id,
            name: id,
            backend: "openai_compatible",
            contextLength: 8192,
            enabled: true,
            baseURL: "https://example.com",
            apiKeyRef: apiKeyRef
        )
    }

    private func makeHealth(keyReference: String, state: RemoteKeyHealthState) -> RemoteKeyHealthRecord {
        RemoteKeyHealthRecord(
            keyReference: keyReference,
            backend: "openai_compatible",
            providerHost: "example.com",
            canaryModelID: "gpt-test",
            state: state,
            summary: "summary",
            detail: "detail",
            lastCheckedAt: Date().timeIntervalSince1970
        )
    }
}
