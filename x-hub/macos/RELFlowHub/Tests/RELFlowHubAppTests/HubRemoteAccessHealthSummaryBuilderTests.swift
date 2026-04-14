import XCTest
@testable import RELFlowHub

final class HubRemoteAccessHealthSummaryBuilderTests: XCTestCase {
    func testBuildReturnsBlockedSummaryWhenAccessIsDisabled() {
        let summary = HubRemoteAccessHealthSummaryBuilder.build(
            autoStartEnabled: false,
            serverRunning: false,
            externalHost: nil,
            hasInviteToken: false,
            keepSystemAwakeWhileServing: true
        )

        XCTAssertEqual(summary.state, .critical)
        XCTAssertEqual(summary.badgeText, HubUIStrings.Settings.GRPC.RemoteHealth.badgeBlocked)
        XCTAssertEqual(summary.headline, HubUIStrings.Settings.GRPC.RemoteHealth.disabledHeadline)
        XCTAssertEqual(summary.accessScopeText, HubUIStrings.Settings.GRPC.RemoteHealth.scopeDisabled)
        XCTAssertEqual(summary.operatorHintText, HubUIStrings.Settings.GRPC.RemoteHealth.hintDisabled)
    }

    func testBuildReturnsOfflineSummaryWhenHostExistsButServerIsDown() {
        let summary = HubRemoteAccessHealthSummaryBuilder.build(
            autoStartEnabled: true,
            serverRunning: false,
            externalHost: "hub.tailnet.example",
            hasInviteToken: true,
            keepSystemAwakeWhileServing: true
        )

        XCTAssertEqual(summary.state, .critical)
        XCTAssertEqual(summary.headline, HubUIStrings.Settings.GRPC.RemoteHealth.offlineHeadline)
        XCTAssertTrue(summary.detail.contains("hub.tailnet.example"))
        XCTAssertEqual(summary.accessScopeText, HubUIStrings.Settings.GRPC.RemoteHealth.scopeRemoteOffline)
        XCTAssertEqual(summary.operatorHintText, HubUIStrings.Settings.GRPC.RemoteHealth.hintOfflineStableNamed)
    }

    func testBuildReturnsTemporarySummaryForRawIPHost() {
        let summary = HubRemoteAccessHealthSummaryBuilder.build(
            autoStartEnabled: true,
            serverRunning: true,
            externalHost: "17.81.11.116",
            hasInviteToken: false,
            keepSystemAwakeWhileServing: true
        )

        XCTAssertEqual(summary.state, .warning)
        XCTAssertEqual(summary.badgeText, HubUIStrings.Settings.GRPC.RemoteHealth.badgeTemporary)
        XCTAssertEqual(summary.headline, HubUIStrings.Settings.GRPC.RemoteHealth.rawIPHeadline)
        XCTAssertTrue(summary.detail.contains("17.81.11.116"))
        XCTAssertEqual(summary.accessScopeText, HubUIStrings.Settings.GRPC.RemoteHealth.scopeTemporaryRemote)
        XCTAssertEqual(summary.operatorHintText, HubUIStrings.Settings.GRPC.RemoteHealth.hintRawIP)
    }

    func testBuildReturnsNeedsTokenSummaryForStableHostWithoutInviteToken() {
        let summary = HubRemoteAccessHealthSummaryBuilder.build(
            autoStartEnabled: true,
            serverRunning: true,
            externalHost: "hub.tailnet.example",
            hasInviteToken: false,
            keepSystemAwakeWhileServing: true
        )

        XCTAssertEqual(summary.state, .warning)
        XCTAssertEqual(summary.badgeText, HubUIStrings.Settings.GRPC.RemoteHealth.badgeNeedsToken)
        XCTAssertEqual(summary.headline, HubUIStrings.Settings.GRPC.RemoteHealth.tokenMissingHeadline)
        XCTAssertEqual(summary.accessScopeText, HubUIStrings.Settings.GRPC.RemoteHealth.scopeRemotePending)
        XCTAssertEqual(summary.operatorHintText, HubUIStrings.Settings.GRPC.RemoteHealth.hintTokenMissing)
    }

    func testBuildReturnsSleepRiskSummaryWhenKeepAwakeIsDisabled() {
        let summary = HubRemoteAccessHealthSummaryBuilder.build(
            autoStartEnabled: true,
            serverRunning: true,
            externalHost: "hub.tailnet.example",
            hasInviteToken: true,
            keepSystemAwakeWhileServing: false
        )

        XCTAssertEqual(summary.state, .warning)
        XCTAssertEqual(summary.headline, HubUIStrings.Settings.GRPC.RemoteHealth.sleepRiskHeadline)
        XCTAssertEqual(summary.accessScopeText, HubUIStrings.Settings.GRPC.RemoteHealth.scopeRemoteReady)
        XCTAssertEqual(summary.operatorHintText, HubUIStrings.Settings.GRPC.RemoteHealth.hintSleepRisk)
    }

    func testBuildReturnsReadySummaryWhenRemoteAccessIsFormallyProvisioned() {
        let summary = HubRemoteAccessHealthSummaryBuilder.build(
            autoStartEnabled: true,
            serverRunning: true,
            externalHost: "hub.tailnet.example",
            hasInviteToken: true,
            keepSystemAwakeWhileServing: true
        )

        XCTAssertEqual(summary.state, .ready)
        XCTAssertEqual(summary.badgeText, HubUIStrings.Settings.GRPC.RemoteHealth.badgeReady)
        XCTAssertEqual(summary.headline, HubUIStrings.Settings.GRPC.RemoteHealth.readyHeadline)
        XCTAssertTrue(summary.detail.contains("hub.tailnet.example"))
        XCTAssertEqual(summary.accessScopeText, HubUIStrings.Settings.GRPC.RemoteHealth.scopeRemoteReady)
        XCTAssertEqual(summary.operatorHintText, HubUIStrings.Settings.GRPC.RemoteHealth.hintReady)
    }

    func testBuildTreatsRunningServerAsEnabledEvenWhenAutoStartIsOff() {
        let summary = HubRemoteAccessHealthSummaryBuilder.build(
            autoStartEnabled: false,
            serverRunning: true,
            externalHost: "hub.tailnet.example",
            hasInviteToken: true,
            keepSystemAwakeWhileServing: true
        )

        XCTAssertEqual(summary.state, .ready)
        XCTAssertEqual(summary.badgeText, HubUIStrings.Settings.GRPC.RemoteHealth.badgeReady)
        XCTAssertEqual(summary.headline, HubUIStrings.Settings.GRPC.RemoteHealth.readyHeadline)
        XCTAssertEqual(summary.accessScopeText, HubUIStrings.Settings.GRPC.RemoteHealth.scopeRemoteReady)
    }
}
