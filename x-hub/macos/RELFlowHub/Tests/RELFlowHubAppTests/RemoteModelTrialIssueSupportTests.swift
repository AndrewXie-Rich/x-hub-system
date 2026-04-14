import XCTest
@testable import RELFlowHub

final class RemoteModelTrialIssueSupportTests: XCTestCase {
    func testLatestUsageLimitNoticeCapturesRetryTimeAndUpgradeHint() {
        let statuses: [ModelTrialStatus] = [
            ModelTrialStatus(
                state: .failure,
                category: .quota,
                summary: "Try Failed",
                detail: "1.2s · 当前额度已用完，可升级 Plus，或到 Apr 15th, 2026 8:58 AM 再试。",
                updatedAt: 100
            ),
            ModelTrialStatus(
                state: .failure,
                category: .quota,
                summary: "Try Failed",
                detail: "0.9s · Provider 配额不足或额度已用尽（status=429）：You exceeded your current quota.",
                updatedAt: 90
            ),
        ]

        let notice = RemoteModelTrialIssueSupport.latestUsageLimitNotice(in: statuses)

        XCTAssertEqual(notice?.badgeText, HubUIStrings.Settings.RemoteModels.usageLimitBadge)
        XCTAssertEqual(
            notice?.detailText,
            HubUIStrings.Settings.RemoteModels.usageLimitUpgradeRetryDetail("Apr 15th, 2026 8:58 AM")
        )
    }

    func testLatestUsageLimitNoticeIgnoresNonQuotaFailures() {
        let statuses: [ModelTrialStatus] = [
            ModelTrialStatus(
                state: .failure,
                category: .network,
                summary: "Try Failed",
                detail: "2.0s · network timeout",
                updatedAt: 100
            ),
        ]

        XCTAssertNil(RemoteModelTrialIssueSupport.latestUsageLimitNotice(in: statuses))
    }
}
