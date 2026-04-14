import XCTest
@testable import RELFlowHub

final class HubStoreNotificationCopyTests: XCTestCase {
    func testPairingNotificationsUseHumanizedChineseCopy() {
        XCTAssertEqual(HubStoreNotificationCopy.pairingApprovedTitle(), "配对请求已按策略批准")
        XCTAssertEqual(
            HubStoreNotificationCopy.pairingApprovedBody(subject: "Andrew 的 MacBook Pro"),
            "Andrew 的 MacBook Pro 已按当前策略完成配对授权。"
        )
        XCTAssertEqual(
            HubStoreNotificationCopy.pairingApprovedBody(subject: " "),
            "该设备 已按当前策略完成配对授权。"
        )
        XCTAssertEqual(HubStoreNotificationCopy.pairingApproveFailedTitle(), "批准配对失败")
        XCTAssertEqual(HubStoreNotificationCopy.pairingDeniedTitle(), "配对请求已拒绝")
        XCTAssertEqual(
            HubStoreNotificationCopy.pairingDeniedBody(subject: "XT-Device"),
            "XT-Device 的配对申请已被拒绝。"
        )
        XCTAssertEqual(HubStoreNotificationCopy.pairingDenyFailedTitle(), "拒绝配对失败")
    }

    func testOperatorChannelReviewCopyHumanizesDecisionAndStatus() {
        XCTAssertEqual(
            HubStoreNotificationCopy.operatorChannelReviewTitle(for: .approve),
            "操作员通道接入已批准"
        )
        XCTAssertEqual(
            HubStoreNotificationCopy.operatorChannelReviewTitle(for: .hold),
            "操作员通道工单已暂缓"
        )
        XCTAssertEqual(
            HubStoreNotificationCopy.operatorChannelReviewTitle(for: .reject),
            "操作员通道接入已拒绝"
        )
        XCTAssertEqual(
            HubStoreNotificationCopy.operatorChannelReviewBody(
                provider: "slack",
                conversationId: "C123",
                status: "query_executed"
            ),
            "SLACK · C123 · 已完成首轮验证"
        )
        XCTAssertEqual(HubStoreNotificationCopy.operatorChannelStatusLabel("pending"), "待审批")
        XCTAssertEqual(HubStoreNotificationCopy.operatorChannelStatusLabel("ready"), "已就绪")
        XCTAssertEqual(HubStoreNotificationCopy.operatorChannelStatusLabel("unknown_state"), "unknown_state")
    }

    func testOperatorChannelRetryAndFailureCopyUseReadableLabels() {
        XCTAssertEqual(HubStoreNotificationCopy.operatorChannelRetryCompleteTitle(), "操作员通道重试完成")
        XCTAssertEqual(
            HubStoreNotificationCopy.operatorChannelRetryCompleteBody(
                ticketId: "ticket-123",
                deliveredCount: 2,
                pendingCount: 1
            ),
            "ticket-123 · 已送达 2 条 · 待发送 1 条"
        )
        XCTAssertEqual(HubStoreNotificationCopy.operatorChannelReviewFailedTitle(), "处理操作员通道工单失败")
        XCTAssertEqual(HubStoreNotificationCopy.operatorChannelRevokedTitle(), "操作员通道接入已撤销")
        XCTAssertEqual(
            HubStoreNotificationCopy.operatorChannelRevokedBody(
                provider: "telegram",
                conversationId: "chat-7",
                status: "revoked"
            ),
            "TELEGRAM · chat-7 · 已撤销"
        )
        XCTAssertEqual(HubStoreNotificationCopy.operatorChannelRevokeFailedTitle(), "撤销操作员通道接入失败")
    }
}
