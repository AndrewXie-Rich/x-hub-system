import XCTest
@testable import RELFlowHub

final class HubFirstPairApprovalSummaryBuilderTests: XCTestCase {
    func testBuildPrefersNewestPendingRequestAndHumanizesCardCopy() {
        let older = makeRequest(
            pairingRequestId: "pair-old",
            deviceName: "XT Older",
            claimedDeviceId: "xt-older",
            peerIp: "192.168.1.8",
            createdAtMs: 100,
            requestedScopes: ["chat"]
        )
        let newer = makeRequest(
            pairingRequestId: "pair-new",
            deviceName: "Andrew XT",
            claimedDeviceId: "xt-new",
            peerIp: "192.168.1.9",
            createdAtMs: 200,
            requestedScopes: ["chat", "web_fetch"]
        )

        let summary = HubFirstPairApprovalSummaryBuilder.build(
            requests: [older, newer],
            approvalInFlightRequestIDs: []
        )

        XCTAssertEqual(summary?.leadRequest.pairingRequestId, "pair-new")
        XCTAssertEqual(summary?.leadDeviceTitle, "Andrew XT · paired-terminal")
        XCTAssertEqual(summary?.sourceAddress, "192.168.1.9")
        XCTAssertEqual(summary?.requestedScopesSummary, "chat, web_fetch")
        XCTAssertEqual(summary?.headline, "2 台新设备等待首配")
        XCTAssertEqual(summary?.reviewButtonTitle, "查看队列")
        XCTAssertEqual(summary?.approveRecommendedButtonTitle, "按推荐批准")
        XCTAssertEqual(summary?.customizeButtonTitle, "自定义策略")
        XCTAssertEqual(summary?.queueHint, "队列里还有 1 台设备等待你核对。")
        XCTAssertEqual(summary?.state, .pending)
    }

    func testBuildSwitchesToAuthenticatingStateWhenApprovalIsInFlight() {
        let request = makeRequest(
            pairingRequestId: "pair-1",
            deviceName: "XT Auth",
            claimedDeviceId: "xt-auth",
            peerIp: "",
            createdAtMs: 100,
            requestedScopes: []
        )

        let summary = HubFirstPairApprovalSummaryBuilder.build(
            requests: [request],
            approvalInFlightRequestIDs: ["pair-1"]
        )

        XCTAssertEqual(summary?.state, .authenticating)
        XCTAssertEqual(summary?.approveRecommendedButtonTitle, "批准中…")
        XCTAssertEqual(
            summary?.statusLine,
            "正在等待本机 owner 验证完成。验证通过后才会真正下发首配 token 和 profile。"
        )
        XCTAssertEqual(summary?.sourceAddress, "同一局域网已验证")
        XCTAssertEqual(summary?.requestedScopesSummary, "默认最小权限模板")
        XCTAssertEqual(summary?.reviewButtonTitle, "查看详情")
    }

    func testBuildCarriesRecentOutcomeIntoSummary() {
        let request = makeRequest(
            pairingRequestId: "pair-3",
            deviceName: "XT Outcome",
            claimedDeviceId: "xt-outcome",
            peerIp: "192.168.1.11",
            createdAtMs: 100,
            requestedScopes: ["chat"]
        )
        let outcome = HubPairingApprovalOutcomeSnapshot(
            requestID: "pair-2",
            deviceTitle: "Andrew XT",
            deviceID: nil,
            kind: .approved,
            detailText: nil,
            occurredAt: 1000
        )

        let summary = HubFirstPairApprovalSummaryBuilder.build(
            requests: [request],
            approvalInFlightRequestIDs: [],
            recentOutcome: outcome
        )

        XCTAssertEqual(summary?.recentOutcome, outcome)
    }

    func testDisplayDeviceTitleFallsBackToClaimedDeviceAndAppID() {
        let request = makeRequest(
            pairingRequestId: "pair-2",
            deviceName: " ",
            claimedDeviceId: "xt-fallback",
            appId: "x-terminal",
            peerIp: "192.168.1.10",
            createdAtMs: 100,
            requestedScopes: ["chat"]
        )

        XCTAssertEqual(
            HubFirstPairApprovalSummaryBuilder.displayDeviceTitle(for: request),
            "xt-fallback · x-terminal"
        )
    }

    private func makeRequest(
        pairingRequestId: String,
        deviceName: String,
        claimedDeviceId: String,
        appId: String = "paired-terminal",
        peerIp: String,
        createdAtMs: Int64,
        requestedScopes: [String]
    ) -> HubPairingRequest {
        HubPairingRequest(
            pairingRequestId: pairingRequestId,
            requestId: "request-\(pairingRequestId)",
            status: "pending",
            appId: appId,
            claimedDeviceId: claimedDeviceId,
            userId: "owner",
            deviceName: deviceName,
            peerIp: peerIp,
            createdAtMs: createdAtMs,
            decidedAtMs: 0,
            denyReason: "",
            requestedScopes: requestedScopes
        )
    }
}
