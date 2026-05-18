import XCTest
@testable import RELFlowHub
import RELFlowHubCore

final class RemoteKeyHealthPresentationSupportTests: XCTestCase {
    func testHealthyPresentationMentionsDefaultPriority() {
        let record = RemoteKeyHealthRecord(
            keyReference: "team-healthy",
            backend: "openai",
            providerHost: "api.openai.com",
            canaryModelID: "gpt-5.4",
            state: .healthy,
            summary: "",
            detail: HubUIStrings.Settings.RemoteModels.healthHealthyDetail("gpt-5.4"),
            lastCheckedAt: 100,
            lastSuccessAt: 100
        )

        let presentation = RemoteKeyHealthPresentationSupport.presentation(
            health: record,
            usageLimitNotice: nil,
            isScanning: false
        )

        XCTAssertEqual(presentation?.badgeText, HubUIStrings.Settings.RemoteModels.healthHealthyBadge)
        XCTAssertTrue(presentation?.detailText.contains("默认会优先使用这把已通过扫描的 key。") == true)
    }

    func testUsageLimitFallbackMentionsSoftDemotionInsteadOfHardBlock() {
        let notice = RemoteKeyUsageLimitNotice(
            retryAtText: "Apr 15, 2026, 8:58 AM",
            suggestsPlusUpgrade: false
        )

        let presentation = RemoteKeyHealthPresentationSupport.presentation(
            health: nil,
            usageLimitNotice: notice,
            isScanning: false
        )

        XCTAssertEqual(presentation?.badgeText, HubUIStrings.Settings.RemoteModels.usageLimitBadge)
        XCTAssertTrue(presentation?.detailText.contains("默认会后排") == true)
        XCTAssertTrue(presentation?.detailText.contains("Apr 15, 2026, 8:58 AM") == true)
    }

    func testHealthPresentationShowsRetryEstimateForBlockedKeys() {
        let record = RemoteKeyHealthRecord(
            keyReference: "openai:primary",
            backend: "openai",
            providerHost: "api.openai.com",
            canaryModelID: "gpt-5.4",
            state: .blockedAuth,
            summary: "",
            detail: "Provider 权限不足，缺少生成 scope：api.responses.write。",
            retryAtText: "2026-04-21 00:00 UTC",
            lastCheckedAt: 100,
            lastSuccessAt: nil
        )

        let presentation = RemoteKeyHealthPresentationSupport.presentation(
            health: record,
            usageLimitNotice: nil,
            isScanning: false
        )

        XCTAssertTrue(presentation?.detailText.contains("预计下次可用：2026-04-21 00:00 UTC") == true)
        XCTAssertTrue(presentation?.detailText.contains("默认会后排") == true)
    }

    func testSlotPresentationsShowReasonAndRetryTimePerKey() {
        let models = [
            RemoteModelEntry(
                id: "gpt-5.4",
                name: "GPT 5.4",
                backend: "openai",
                enabled: true,
                apiKeyRef: "openai:primary",
                apiKey: "sk-primary"
            ),
            RemoteModelEntry(
                id: "gpt-5.4#2",
                name: "GPT 5.4",
                backend: "openai",
                enabled: true,
                apiKeyRef: "openai:primary#2",
                apiKey: "sk-secondary"
            )
        ]
        let snapshot = RemoteKeyHealthSnapshot(
            records: [
                RemoteKeyHealthRecord(
                    keyReference: "openai:primary",
                    backend: "openai",
                    state: .blockedAuth,
                    summary: "",
                    detail: "Provider 权限不足，缺少生成 scope：api.responses.write。",
                    retryAtText: nil,
                    lastCheckedAt: 10,
                    lastSuccessAt: nil
                ),
                RemoteKeyHealthRecord(
                    keyReference: "openai:primary#2",
                    backend: "openai",
                    state: .blockedQuota,
                    summary: "",
                    detail: "当前额度已用完。",
                    retryAtText: "Apr 18, 2026, 8:58 AM",
                    lastCheckedAt: 20,
                    lastSuccessAt: nil
                ),
            ],
            updatedAt: 20
        )

        let slots = RemoteKeyHealthPresentationSupport.slotPresentations(
            models: models,
            healthSnapshot: snapshot,
            isScanning: { _ in false }
        )

        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(slots[0].keyReference, "openai:primary")
        XCTAssertTrue(slots[0].detailText.contains("scope：api.responses.write") == true)
        XCTAssertTrue(slots[0].detailText.contains("预计下次可用：未知") == true)
        XCTAssertEqual(slots[1].keyReference, "openai:primary#2")
        XCTAssertTrue(slots[1].detailText.contains("Apr 18, 2026, 8:58 AM") == true)
    }
}
