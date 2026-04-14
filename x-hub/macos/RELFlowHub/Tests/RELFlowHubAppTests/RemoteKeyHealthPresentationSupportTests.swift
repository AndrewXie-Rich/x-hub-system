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
}
