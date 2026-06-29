import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class HubStatusPresentationSupportTests: XCTestCase {
    func testServingWithRunningGRPCIsReady() {
        let presentation = HubStatusPresentationSupport.make(
            snapshot: launchSnapshot(state: .serving),
            grpcIsRunning: true,
            grpcStatusText: "  gRPC serving on 5123  "
        )

        XCTAssertEqual(presentation.tone, .ready)
        XCTAssertEqual(presentation.title, "正常")
        XCTAssertEqual(presentation.detail, "gRPC serving on 5123")
        XCTAssertEqual(presentation.stateKey, "serving")
        XCTAssertEqual(presentation.systemName, "checkmark.circle.fill")
        XCTAssertFalse(presentation.needsActionHint)
        XCTAssertEqual(presentation.actionTitle, "继续使用")
        XCTAssertEqual(presentation.toolTip, "X-Hub • 正常 • gRPC serving on 5123")
    }

    func testServingWithoutGRPCReportRemainsReady() {
        let presentation = HubStatusPresentationSupport.make(
            snapshot: launchSnapshot(state: .serving),
            grpcIsRunning: false,
            grpcStatusText: ""
        )

        XCTAssertEqual(presentation.tone, .ready)
        XCTAssertEqual(presentation.title, "正常")
        XCTAssertEqual(presentation.detail, "Rust kernel serving")
        XCTAssertEqual(presentation.stateKey, "serving")
        XCTAssertFalse(presentation.needsActionHint)
    }

    func testServingWithBlockedCapabilitiesIsDegraded() {
        let presentation = HubStatusPresentationSupport.make(
            snapshot: launchSnapshot(
                state: .serving,
                degraded: HubLaunchDegraded(
                    isDegraded: true,
                    blockedCapabilities: ["web.fetch", "ai.generate.local"]
                )
            ),
            grpcIsRunning: true,
            grpcStatusText: "running"
        )

        XCTAssertEqual(presentation.tone, .degraded)
        XCTAssertEqual(presentation.title, "降级")
        XCTAssertEqual(presentation.detail, "2 个能力被阻止")
        XCTAssertEqual(presentation.stateKey, "degraded")
        XCTAssertEqual(presentation.systemName, "exclamationmark.triangle.fill")
        XCTAssertTrue(presentation.needsActionHint)
        XCTAssertEqual(presentation.actionTitle, "查看受阻能力")
    }

    func testStartingStateUsesLaunchStateAsDetail() {
        let presentation = HubStatusPresentationSupport.make(
            snapshot: launchSnapshot(state: .waitRuntimeReady),
            grpcIsRunning: false,
            grpcStatusText: ""
        )

        XCTAssertEqual(presentation.tone, .starting)
        XCTAssertEqual(presentation.title, "启动中")
        XCTAssertEqual(presentation.detail, "WAIT_RUNTIME_READY")
        XCTAssertEqual(presentation.stateKey, "starting:WAIT_RUNTIME_READY")
        XCTAssertEqual(presentation.systemName, "arrow.triangle.2.circlepath")
        XCTAssertTrue(presentation.needsActionHint)
        XCTAssertEqual(presentation.actionTitle, "等待启动")
    }

    func testFailedStateUsesRootCauseCode() {
        let presentation = HubStatusPresentationSupport.make(
            snapshot: launchSnapshot(
                state: .failed,
                rootCause: HubLaunchRootCause(component: .runtime, errorCode: "XHUB_RUNTIME_LOCKED")
            ),
            grpcIsRunning: false,
            grpcStatusText: ""
        )

        XCTAssertEqual(presentation.tone, .failed)
        XCTAssertEqual(presentation.title, "错误")
        XCTAssertEqual(presentation.detail, "XHUB_RUNTIME_LOCKED")
        XCTAssertEqual(presentation.stateKey, "failed:XHUB_RUNTIME_LOCKED")
        XCTAssertEqual(presentation.systemName, "xmark.octagon.fill")
        XCTAssertTrue(presentation.needsActionHint)
        XCTAssertEqual(presentation.actionTitle, "立即修复")
    }

    func testNilSnapshotUsesGRPCFallbackWhenRunning() {
        let presentation = HubStatusPresentationSupport.make(
            snapshot: nil,
            grpcIsRunning: true,
            grpcStatusText: "connected"
        )

        XCTAssertEqual(presentation.tone, .ready)
        XCTAssertEqual(presentation.title, "正常")
        XCTAssertEqual(presentation.detail, "connected")
        XCTAssertEqual(presentation.stateKey, "grpc-running")
        XCTAssertFalse(presentation.needsActionHint)
    }

    func testNilSnapshotAndNoGRPCIsUnknown() {
        let presentation = HubStatusPresentationSupport.make(
            snapshot: nil,
            grpcIsRunning: false,
            grpcStatusText: ""
        )

        XCTAssertEqual(presentation.tone, .unknown)
        XCTAssertEqual(presentation.title, "未知")
        XCTAssertEqual(presentation.detail, "等待 Hub 状态")
        XCTAssertEqual(presentation.stateKey, "unknown")
        XCTAssertEqual(presentation.systemName, "questionmark.circle.fill")
        XCTAssertTrue(presentation.needsActionHint)
        XCTAssertEqual(presentation.actionTitle, "刷新状态")
        XCTAssertEqual(presentation.actionDetail, "等待 Hub 写入启动状态；必要时在诊断页重启组件。")
    }

    private func launchSnapshot(
        state: HubLaunchState,
        rootCause: HubLaunchRootCause? = nil,
        degraded: HubLaunchDegraded = HubLaunchDegraded(isDegraded: false, blockedCapabilities: [])
    ) -> HubLaunchStatusSnapshot {
        HubLaunchStatusSnapshot(
            launchId: "launch-test",
            updatedAtMs: 1_700_000_000_000,
            state: state,
            steps: [],
            rootCause: rootCause,
            degraded: degraded
        )
    }
}
