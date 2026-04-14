import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class HubNotificationPresentationTests: XCTestCase {
    func testPairingNotificationUsesInspectActionAndLivePairingContext() {
        let notification = HubNotification.make(
            source: "Hub",
            title: "Pairing request",
            body: "",
            dedupeKey: "pairing_request:req-123"
        )

        let presentation = hubNotificationPresentation(for: notification)
        let context = hubNotificationPairingContext(
            for: notification,
            pendingRequests: [
                makePairingRequest(
                    pairingRequestId: "req-123",
                    appId: "paired-terminal",
                    claimedDeviceId: "xt-mac",
                    deviceName: "XT Mac",
                    peerIp: "192.168.0.12",
                    createdAtMs: 1_712_345_600_000,
                    requestedScopes: ["memory", "web.fetch"]
                )
            ]
        )

        XCTAssertEqual(presentation.group, .actionRequired)
        XCTAssertEqual(presentation.primaryLabel, "查看明细")
        XCTAssertEqual(presentation.primaryAction, .inspect)
        XCTAssertEqual(context?.deviceTitle, "XT Mac · paired-terminal")
        XCTAssertEqual(context?.sourceAddress, "192.168.0.12")
        XCTAssertEqual(context?.requestedScopesSummary, "memory, web.fetch")
        XCTAssertEqual(context?.queueStateText, HubUIStrings.Notifications.Pairing.pendingState)
        XCTAssertEqual(context?.isLivePending, true)
    }

    func testRecentPairingApprovalOutcomeMatchesFreshRequestID() {
        let outcome = HubPairingApprovalOutcomeSnapshot(
            requestID: "req-123",
            deviceTitle: "XT Mac",
            deviceID: nil,
            kind: .approved,
            detailText: nil,
            occurredAt: 1_000
        )

        let matched = hubNotificationRecentPairingApprovalOutcome(
            pairingRequestId: "req-123",
            latestOutcome: outcome,
            now: 1_030
        )

        XCTAssertEqual(matched, outcome)
    }

    func testRecentPairingApprovalOutcomeIgnoresExpiredOrMismatchedRequests() {
        let outcome = HubPairingApprovalOutcomeSnapshot(
            requestID: "req-123",
            deviceTitle: "XT Mac",
            deviceID: nil,
            kind: .approved,
            detailText: nil,
            occurredAt: 1_000
        )

        XCTAssertNil(
            hubNotificationRecentPairingApprovalOutcome(
                pairingRequestId: "req-999",
                latestOutcome: outcome,
                now: 1_010
            )
        )
        XCTAssertNil(
            hubNotificationRecentPairingApprovalOutcome(
                pairingRequestId: "req-123",
                latestOutcome: outcome,
                now: 1_500
            )
        )
    }

    func testGrantPendingTerminalNotificationIsHumanizedForHub() {
        let notification = HubNotification.make(
            source: "X-Terminal",
            title: "2 Lane 需要处理：grant_pending",
            body: """
lane=lane-gate-downstream
action=notify_user
deny=grant_pending
latency=-1ms
audit=audit://incident/123
""",
            actionURL: "xterminal://project/alpha"
        )

        let presentation = hubNotificationPresentation(for: notification)

        XCTAssertEqual(presentation.group, .actionRequired)
        XCTAssertEqual(presentation.badge, "X-Terminal")
        XCTAssertEqual(presentation.primaryLabel, "查看授权原因")
        XCTAssertEqual(presentation.primaryAction, .inspect)
        XCTAssertEqual(presentation.displayTitle, "有 2 项执行请求等待授权")
        XCTAssertEqual(
            presentation.recommendedNextStep,
            "回到 Supervisor 对话确认是否授权；如果只是想先看清原因，可以先打开摘要。"
        )
        XCTAssertEqual(presentation.executionSurface, "Supervisor 对话 / X-Terminal 侧")
        XCTAssertEqual(
            presentation.subline,
            "有 2 项执行请求在等待授权，需回到 Supervisor 对话继续处理。"
        )
        XCTAssertEqual(
            presentation.detailFacts.first(where: { $0.label == "问题类型" })?.value,
            "等待授权"
        )
        XCTAssertEqual(
            presentation.detailFacts.first(where: { $0.label == "建议动作" })?.value,
            "提醒你在 Supervisor 对话里继续处理"
        )
        XCTAssertNil(presentation.detailFacts.first(where: { $0.label == "处理耗时" }))
        XCTAssertNil(presentation.detailFacts.first(where: { $0.label == "执行通道" }))
        XCTAssertNil(presentation.detailFacts.first(where: { $0.label == "审计记录" }))

        let summary = hubNotificationSummaryText(notification)
        XCTAssertTrue(summary.contains("有 2 项执行请求等待授权"))
        XCTAssertTrue(summary.contains("建议下一步：回到 Supervisor 对话确认是否授权"))
        XCTAssertTrue(summary.contains("建议动作: 提醒你在 Supervisor 对话里继续处理"))
        XCTAssertFalse(summary.contains("原始标题："))
        XCTAssertFalse(summary.contains("为什么 Hub 会显示这条："))
        XCTAssertFalse(summary.contains("原始明细："))
    }

    func testGrantPendingTerminalNotificationHighlightsCapabilitySpecificRemediation() {
        let notification = HubNotification.make(
            source: "X-Terminal",
            title: "1 Lane 需要处理：grant_pending",
            body: """
lane=lane-gate-downstream
required_capability=web.fetch
action=open_grant_pending_board
deny=grant_pending
latency=-1ms
audit=audit://incident/456
""",
            actionURL: "xterminal://project/alpha"
        )

        let presentation = hubNotificationPresentation(for: notification)

        XCTAssertEqual(presentation.displayTitle, "有执行请求等待网页抓取授权")
        XCTAssertEqual(
            presentation.subline,
            "有一项执行请求在等待网页抓取授权，建议先到 Hub 的已配对设备里检查这台 XT 的能力边界。"
        )
        XCTAssertEqual(
            presentation.recommendedNextStep,
            "打开 Hub 设置 → 已配对设备，放开这台 XT 的“网页抓取”；然后回到 Supervisor 再试一次。"
        )
        XCTAssertEqual(
            presentation.detailFacts.first(where: { $0.label == "能力" })?.value,
            "网页抓取"
        )
    }

    func testGrantPendingTerminalNotificationKeepsDeviceIDForTargetedRemediation() {
        let notification = HubNotification.make(
            source: "X-Terminal",
            title: "1 Lane 需要处理：grant_pending",
            body: """
lane=lane-gate-downstream
required_capability=ai.generate.paid
device_id=dev-xt-paid-01
action=open_grant_pending_board
deny=grant_pending
latency=-1ms
audit=audit://incident/789
""",
            actionURL: "xterminal://project/alpha"
        )

        let presentation = hubNotificationPresentation(for: notification)

        XCTAssertEqual(
            presentation.detailFacts.first(where: { $0.label == "能力" })?.value,
            "付费 AI"
        )
        XCTAssertEqual(
            presentation.detailFacts.first(where: { $0.label == "设备 ID" })?.value,
            "dev-xt-paid-01"
        )

        let summary = hubNotificationSummaryText(notification)
        XCTAssertTrue(summary.contains("设备 ID: dev-xt-paid-01"))
    }

    func testMissingContextNotificationSurfacesQuestionGapAndSuggestedReply() {
        let notification = HubNotification.make(
            source: "X-Terminal",
            title: "待补背景：Alpha Demo",
            body: "《Alpha Demo》还缺这项项目背景：这个项目的长期目标和完成标准分别是什么？ 当前缺口：Canonical 里还没有明确 done 定义。 这是最后 1 项。 直接说“长期目标是上线 Demo，完成标准是能稳定演示三条核心链路。”即可。",
            actionURL: "xterminal://project/alpha-demo"
        )

        let presentation = hubNotificationPresentation(for: notification)

        XCTAssertEqual(presentation.group, .advisory)
        XCTAssertEqual(presentation.badge, "待补背景")
        XCTAssertEqual(presentation.primaryLabel, "查看缺失背景")
        XCTAssertEqual(presentation.displayTitle, "Alpha Demo 还缺背景信息")
        XCTAssertEqual(presentation.executionSurface, "Supervisor 对话 / X-Terminal 侧")
        XCTAssertEqual(
            presentation.recommendedNextStep,
            "先确认缺失背景，再把建议回复调整一下后发回 Supervisor。"
        )
        XCTAssertEqual(
            presentation.subline,
            "项目还缺这项背景：这个项目的长期目标和完成标准分别是什么？"
        )
        XCTAssertEqual(
            presentation.detailFacts.first(where: { $0.label == "项目" })?.value,
            "Alpha Demo"
        )
        XCTAssertEqual(
            presentation.detailFacts.first(where: { $0.label == "当前缺口" })?.value,
            "Canonical 里还没有明确 done 定义。 这是最后 1 项。"
        )
        XCTAssertEqual(
            presentation.detailFacts.first(where: { $0.label == "建议回复" })?.value,
            "长期目标是上线 Demo，完成标准是能稳定演示三条核心链路。"
        )

        XCTAssertEqual(
            hubNotificationQuickCopyAction(notification),
            HubNotificationQuickCopyAction(
                label: "复制建议回复",
                text: "长期目标是上线 Demo，完成标准是能稳定演示三条核心链路。"
            )
        )
    }

    func testHeartbeatSummaryUsesHumanizedReasonInsteadOfRawEvent() {
        let notification = HubNotification.make(
            source: "X-Terminal",
            title: "Supervisor 心跳：项目有更新（静默）",
            body: """
时间：10:51PM
原因：event...
项目总数：3
阻塞项目数：0
排队项目数：1
待授权项目数：2
待治理修复项目数：0
""",
            actionURL: "xterminal://heartbeat"
        )

        let presentation = hubNotificationPresentation(for: notification)

        XCTAssertEqual(presentation.group, .background)
        XCTAssertEqual(presentation.primaryLabel, "查看项目状态")
        XCTAssertEqual(presentation.displayTitle, "Supervisor 项目状态有更新")
        XCTAssertEqual(presentation.executionSurface, "项目状态跟踪（通常无需立刻处理）")
        XCTAssertEqual(
            presentation.recommendedNextStep,
            "这类更新通常不需要立刻处理，只有当你想追踪项目状态时再打开摘要即可。"
        )
        XCTAssertEqual(
            presentation.subline,
            "后台检测到项目更新 · 无阻塞项目 · 排队 1 · 待授权 2"
        )
        XCTAssertEqual(
            presentation.detailFacts.first(where: { $0.label == "原因" })?.value,
            "后台检测到项目更新"
        )
    }

    func testRuntimeErrorIncidentUsesProblemSummaryInsteadOfLaneRawText() {
        let notification = HubNotification.make(
            source: "X-Terminal",
            title: "🚧 Lane 需要处理：runtime_error",
            body: """
lane=lane-alpha
action=notify_user
deny=runtime_error
latency=223ms
audit=audit://incident/456
""",
            actionURL: "xterminal://project/runtime"
        )

        let presentation = hubNotificationPresentation(for: notification)

        XCTAssertEqual(presentation.group, .advisory)
        XCTAssertEqual(presentation.primaryLabel, "查看失败摘要")
        XCTAssertEqual(presentation.displayTitle, "有执行请求执行出错")
        XCTAssertEqual(presentation.executionSurface, "Supervisor 对话 / X-Terminal 侧")
        XCTAssertEqual(
            presentation.recommendedNextStep,
            "先看摘要确认失败原因，再决定是重试、改方案，还是补充缺失信息。"
        )
        XCTAssertEqual(
            presentation.subline,
            "有一项执行请求执行出错，建议先看摘要确认是否重试。"
        )
        XCTAssertEqual(
            presentation.detailFacts.first(where: { $0.label == "阻断原因" })?.value,
            "运行时异常"
        )
        XCTAssertEqual(
            presentation.detailFacts.first(where: { $0.label == "建议动作" })?.value,
            "提醒你在 Supervisor 对话里继续处理"
        )

        let quickCopy = hubNotificationQuickCopyAction(notification)
        XCTAssertEqual(quickCopy?.label, "复制摘要")
        XCTAssertTrue(quickCopy?.text.contains("有执行请求执行出错") == true)
        XCTAssertTrue(quickCopy?.text.contains("建议下一步：先看摘要确认失败原因") == true)
    }

    func testTerminalSourceStaysInspectableEvenWhenActionURLLooksLikeLocalOpen() {
        let notification = HubNotification.make(
            source: "X-Terminal",
            title: "项目状态同步",
            body: "这是来自另一台设备上 Supervisor 的状态更新。",
            actionURL: "relflowhub://openapp?bundle_id=com.apple.Terminal"
        )

        let presentation = hubNotificationPresentation(for: notification)

        XCTAssertEqual(presentation.group, .advisory)
        XCTAssertEqual(presentation.badge, "X-Terminal")
        XCTAssertEqual(presentation.primaryLabel, "查看 Terminal 摘要")
        XCTAssertEqual(presentation.primaryAction, .inspect)
        XCTAssertEqual(presentation.executionSurface, "Supervisor 对话 / X-Terminal 侧")
        XCTAssertEqual(
            presentation.recommendedNextStep,
            "先在 Hub 里看摘要；如果需要真正执行或回复，再回到 Terminal 侧继续。"
        )
    }

    func testGenericTerminalMachineReadableBodyDoesNotLeakRawKeys() {
        let notification = HubNotification.make(
            source: "X-Terminal",
            title: "Supervisor 系统更新",
            body: """
job_id=job-123
plan_id=plan-456
source_ref=workflow://abc
""",
            actionURL: "xterminal://project/abc"
        )

        let presentation = hubNotificationPresentation(for: notification)
        let summary = hubNotificationSummaryText(notification)

        XCTAssertEqual(
            presentation.subline,
            "收到一条来自 X-Terminal 的系统更新，建议先在 Hub 里看摘要。"
        )
        XCTAssertTrue(presentation.detailFacts.isEmpty)
        XCTAssertFalse(summary.contains("job_id"))
        XCTAssertFalse(summary.contains("plan_id"))
        XCTAssertFalse(summary.contains("source_ref"))
    }

    func testDisplaySourceHumanizesKnownSourceNames() {
        XCTAssertEqual(
            hubNotificationDisplaySource(
                HubNotification.make(source: "FAtracker", title: "t", body: "b", dedupeKey: nil)
            ),
            "FA Tracker"
        )
        XCTAssertEqual(
            hubNotificationDisplaySource(
                HubNotification.make(source: "X-Terminal", title: "t", body: "b", dedupeKey: nil)
            ),
            "X-Terminal"
        )
        XCTAssertEqual(
            hubNotificationDisplaySource(
                HubNotification.make(source: "Hub", title: "t", body: "b", dedupeKey: nil)
            ),
            "Hub"
        )
        XCTAssertEqual(
            hubNotificationDisplaySource(
                HubNotification.make(source: "mail", title: "t", body: "b", dedupeKey: nil)
            ),
            "Mail"
        )
    }

    func testLocalAppNotificationsUseCentralizedFallbackNames() {
        let radarNotification = HubNotification.make(
            source: "",
            title: "Radar update",
            body: "",
            dedupeKey: nil,
            actionURL: "rdar://123456"
        )
        let genericAppNotification = HubNotification.make(
            source: "",
            title: "Open app",
            body: "",
            dedupeKey: nil,
            actionURL: "relflowhub://openapp"
        )

        let radarPresentation = hubNotificationPresentation(for: radarNotification)
        let genericAppPresentation = hubNotificationPresentation(for: genericAppNotification)

        XCTAssertEqual(radarPresentation.badge, "Radar")
        XCTAssertEqual(radarPresentation.primaryLabel, "打开Radar")
        XCTAssertEqual(genericAppPresentation.badge, "App")
        XCTAssertEqual(genericAppPresentation.primaryLabel, "打开App")
    }

    private func makePairingRequest(
        pairingRequestId: String,
        appId: String,
        claimedDeviceId: String,
        deviceName: String,
        peerIp: String,
        createdAtMs: Int64,
        requestedScopes: [String]
    ) -> HubPairingRequest {
        HubPairingRequest(
            pairingRequestId: pairingRequestId,
            requestId: pairingRequestId,
            status: "pending",
            appId: appId,
            claimedDeviceId: claimedDeviceId,
            userId: "user",
            deviceName: deviceName,
            peerIp: peerIp,
            createdAtMs: createdAtMs,
            decidedAtMs: 0,
            denyReason: "",
            requestedScopes: requestedScopes
        )
    }
}
