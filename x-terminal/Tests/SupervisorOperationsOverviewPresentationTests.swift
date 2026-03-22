import Foundation
import Testing
@testable import XTerminal

struct SupervisorSignalCenterOverviewPresentationTests {

    @Test
    func pendingHubGrantWinsAsImmediateSignal() {
        let presentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(
                rows: [
                    SupervisorPendingHubGrantRowPresentation(
                        id: "grant-1",
                        anchorID: "grant-anchor",
                        title: "P1 · Project · Paid model",
                        ageText: "2m",
                        summary: "等待审批",
                        supplementaryReasonText: nil,
                        priorityReasonText: nil,
                        nextActionText: "打开授权并批准 paid model grant",
                        scopeSummaryText: nil,
                        grantIdentifierText: "授权单号：g1",
                        isFocused: false,
                        isInFlight: false,
                        actionDescriptors: []
                    )
                ]
            ),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(rows: []),
            runtimeActivityPresentation: runtimeBoard(rows: []),
            automationPresentation: automationPresentation(iconTone: .accent),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(presentation.priority == .immediate)
        #expect(presentation.headlineText == "Hub 待处理授权")
        #expect(presentation.detailText == "打开授权并批准 paid model grant")
        #expect(
            presentation.focusAction == SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(SupervisorFocusPresentation.pendingHubGrantBoardAnchorID),
                label: "查看授权板",
                tone: .warning
            )
        )
    }

    @Test
    func pendingSkillApprovalWinsWhenNoHubGrantExists() {
        let presentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(rows: []),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(
                rows: [
                    SupervisorPendingSkillApprovalRowPresentation(
                        id: "approval-1",
                        anchorID: "approval-anchor",
                        iconName: "hammer.fill",
                        title: "Project · device-control",
                        ageText: "5m",
                        summary: "这条高风险技能还需要确认",
                        nextStepText: "确认后再运行设备级技能",
                        routingExplanationText: "路由说明： 浏览器入口会先收敛到受治理内建 guarded-automation 再执行",
                        noteText: nil,
                        requestIdentifierText: "请求单号：req-1",
                        isFocused: false,
                        actionDescriptors: []
                    )
                ]
            ),
            runtimeActivityPresentation: runtimeBoard(rows: []),
            automationPresentation: automationPresentation(iconTone: .accent),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(presentation.priority == .immediate)
        #expect(presentation.headlineText == "待审批技能")
        #expect(presentation.detailText == "确认后再运行设备级技能")
        #expect(presentation.metadataText.contains("本地审批"))
        #expect(presentation.metadataText.contains("受治理内建 guarded-automation"))
        #expect(
            presentation.focusAction == SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(
                    SupervisorFocusPresentation.pendingSupervisorSkillApprovalBoardAnchorID
                ),
                label: "查看技能审批",
                tone: .warning
            )
        )
    }

    @Test
    func automationWarningBecomesAttentionSignal() {
        let presentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(rows: []),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(rows: []),
            runtimeActivityPresentation: runtimeBoard(rows: []),
            automationPresentation: automationPresentation(
                iconTone: .warning,
                statusLine: "blocked at governed checkpoint",
                projectText: "project: Governance Runtime"
            ),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(presentation.priority == .attention)
        #expect(presentation.priorityTone == .warning)
        #expect(presentation.headlineText == "自动化执行需要关注")
        #expect(presentation.detailText == "blocked at governed checkpoint")
        #expect(presentation.metadataText.contains("project: Governance Runtime"))
        #expect(
            presentation.focusAction == SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(SupervisorFocusPresentation.automationRuntimeBoardAnchorID),
                label: "查看自动化执行",
                tone: .warning
            )
        )
    }

    @Test
    func runtimeActivityFallsBackToWatchSignalAndStableEmptyState() {
        let runtimePresentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(rows: []),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(rows: []),
            runtimeActivityPresentation: runtimeBoard(
                rows: [
                    SupervisorRuntimeActivityRowPresentation(
                        id: "log-1",
                        timeText: "10:32",
                        text: "voice playback fell back to local output",
                        actionDescriptors: [],
                        showsDivider: false
                    )
                ]
            ),
            automationPresentation: automationPresentation(iconTone: .neutral),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )
        let stablePresentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(rows: []),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(rows: []),
            runtimeActivityPresentation: runtimeBoard(rows: []),
            automationPresentation: automationPresentation(
                iconTone: .neutral,
                projectText: "project: Demo"
            ),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(runtimePresentation.priority == .watch)
        #expect(runtimePresentation.headlineText == "运行动态有新事件")
        #expect(runtimePresentation.detailText == "voice playback fell back to local output")
        #expect(
            runtimePresentation.focusAction == SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(SupervisorFocusPresentation.runtimeActivityBoardAnchorID),
                label: "查看运行动态",
                tone: .accent
            )
        )

        #expect(stablePresentation.priority == .stable)
        #expect(stablePresentation.headlineText == "信号中心空闲")
        #expect(stablePresentation.focusAction == nil)
        #expect(stablePresentation.metadataText == "project: Demo")
        #expect(runtimePresentation.shouldPulseHeader)
        #expect(!stablePresentation.shouldPulseHeader)
        #expect(runtimePresentation.signalFingerprint.contains("运行动态有新事件"))
    }

    @Test
    func runtimeActivityPromotesContractSummaryIntoOverviewDetail() {
        let presentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(rows: []),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(rows: []),
            runtimeActivityPresentation: runtimeBoard(
                rows: [
                    SupervisorRuntimeActivityRowPresentation(
                        id: "log-2",
                        timeText: "10:40",
                        text: "after_turn project_memory_failed · project=Project Alpha · error=disk_full",
                        contractText: "合同： 故障恢复 · blocker=project_memory_failed",
                        nextSafeActionText: "安全下一步： inspect_incident_and_replan",
                        actionDescriptors: [
                            .init(
                                action: .openURL(label: "打开诊断", url: "xterminal://settings?section_id=diagnostics"),
                                label: "打开诊断",
                                style: .standard,
                                isEnabled: true
                            )
                        ],
                        showsDivider: false
                    )
                ]
            ),
            automationPresentation: automationPresentation(iconTone: .neutral),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(presentation.priority == .watch)
        #expect(presentation.headlineText == "运行动态有新事件")
        #expect(presentation.detailText == "合同： 故障恢复 · blocker=project_memory_failed")
        #expect(presentation.metadataText.contains("安全下一步： inspect_incident_and_replan"))
        #expect(presentation.metadataText.contains("after_turn project_memory_failed"))
    }

    @Test
    func automationContractPromotesOverviewEvenWhenIconToneIsAccent() {
        let presentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(rows: []),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(rows: []),
            runtimeActivityPresentation: runtimeBoard(rows: []),
            automationPresentation: automationPresentation(
                iconTone: .accent,
                statusLine: "automation runtime: stale",
                projectText: "project: Recovery Project",
                contractText: "合同： 故障恢复 · blocker=trusted_automation_workspace_mismatch",
                nextSafeActionText: "安全下一步： inspect_incident_and_replan"
            ),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(presentation.priority == .attention)
        #expect(presentation.headlineText == "自动化执行需要关注")
        #expect(presentation.detailText == "合同： 故障恢复 · blocker=trusted_automation_workspace_mismatch")
        #expect(presentation.metadataText.contains("安全下一步： inspect_incident_and_replan"))
        #expect(presentation.metadataText.contains("automation runtime: stale"))
    }

    @Test
    func laneHealthPromotesAbnormalLaneWhenNoHigherPrioritySignalExists() {
        let presentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(rows: []),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(rows: []),
            runtimeActivityPresentation: runtimeBoard(rows: []),
            automationPresentation: automationPresentation(iconTone: .neutral),
            laneHealthPresentation: laneHealthBoard(
                iconTone: .warning,
                summaryLine: "running=1 · blocked=1 · stalled=0 · failed=0 · waiting=0 · recovering=0",
                rows: [
                    SupervisorLaneHealthRowPresentation(
                        laneID: "lane-3",
                        isFocused: false,
                        title: "lane-3 · blocked",
                        statusIconName: "pause.circle.fill",
                        statusTone: .warning,
                        reasonLine: "reason=grant_pending · next=notify_user",
                        reasonTone: .warning,
                        contractText: "合同： 授权处理 · blocker=grant_pending",
                        nextSafeActionText: "安全下一步： open_hub_grants · actions=notify_user",
                        heartbeatSequenceText: "hb#3",
                        heartbeatAgeText: "heartbeat=1s",
                        taskText: "task=12345678",
                        splitPlanText: "plan=split-3",
                        waitText: "wait=8s",
                        openAction: nil,
                        focusAction: SupervisorLaneHealthRowActionDescriptor(
                            action: .focusLane("lane-3"),
                            label: "定位",
                            isEnabled: true
                        )
                    )
                ]
            )
        )

        #expect(presentation.priority == .attention)
        #expect(presentation.headlineText == "泳道健康需要关注")
        #expect(presentation.detailText == "合同： 授权处理 · blocker=grant_pending")
        #expect(presentation.metadataText.contains("安全下一步： open_hub_grants"))
        #expect(presentation.focusAction == SupervisorSignalCenterOverviewActionDescriptor(
            action: .scrollToBoard(SupervisorFocusPresentation.laneHealthBoardAnchorID),
            label: "查看泳道健康",
            tone: .warning
        ))
    }

    private func pendingHubGrantBoard(
        rows: [SupervisorPendingHubGrantRowPresentation]
    ) -> SupervisorPendingHubGrantBoardPresentation {
        SupervisorPendingHubGrantBoardPresentation(
            iconName: rows.isEmpty ? "checkmark.shield" : "exclamationmark.shield.fill",
            iconTone: rows.isEmpty ? .neutral : .warning,
            title: "Hub 待处理授权：\(rows.count)",
            snapshotText: "来源：Hub · 快照新鲜",
            freshnessWarningText: nil,
            footerNote: nil,
            emptyStateText: rows.isEmpty ? "empty" : nil,
            rows: rows
        )
    }

    private func pendingSkillApprovalBoard(
        rows: [SupervisorPendingSkillApprovalRowPresentation]
    ) -> SupervisorPendingSkillApprovalBoardPresentation {
        SupervisorPendingSkillApprovalBoardPresentation(
            iconName: rows.isEmpty ? "checkmark.shield" : "hand.raised.fill",
            iconTone: rows.isEmpty ? .neutral : .warning,
            title: "待审批技能：\(rows.count)",
            modeText: "本地审批",
            emptyStateText: rows.isEmpty ? "empty" : nil,
            rows: rows
        )
    }

    private func runtimeBoard(
        rows: [SupervisorRuntimeActivityRowPresentation]
    ) -> SupervisorRuntimeActivityBoardPresentation {
        SupervisorRuntimeActivityBoardPresentation(
            iconName: rows.isEmpty ? "list.bullet.rectangle" : "list.bullet.rectangle.fill",
            iconTone: rows.isEmpty ? .neutral : .accent,
            title: "运行动态",
            countText: "\(rows.count) 条",
            emptyStateText: rows.isEmpty ? "empty" : nil,
            rows: rows
        )
    }

    private func laneHealthBoard(
        iconTone: SupervisorLaneHealthTone,
        summaryLine: String = "running=0 · blocked=0 · stalled=0 · failed=0 · waiting=0 · recovering=0",
        rows: [SupervisorLaneHealthRowPresentation] = []
    ) -> SupervisorLaneHealthBoardPresentation {
        SupervisorLaneHealthBoardPresentation(
            iconName: "heart.text.square.fill",
            iconTone: iconTone,
            title: "泳道健康态",
            statusLine: "lane health: status",
            summaryLine: summaryLine,
            rows: rows,
            emptyStateText: rows.isEmpty ? "empty" : nil
        )
    }

    private func automationPresentation(
        iconTone: SupervisorHeaderControlTone,
        statusLine: String = "idle",
        projectText: String? = nil,
        contractText: String? = nil,
        nextSafeActionText: String? = nil
    ) -> SupervisorAutomationRuntimePresentation {
        SupervisorAutomationRuntimePresentation(
            iconName: "bolt.circle",
            iconTone: iconTone,
            title: "Automation Runtime",
            statusLine: statusLine,
            contractText: contractText,
            nextSafeActionText: nextSafeActionText,
            statusAction: SupervisorAutomationRuntimeActionDescriptor(
                action: .status,
                label: "Status",
                isEnabled: true
            ),
            projectLine: projectText.map {
                SupervisorAutomationRuntimeLinePresentation(
                    id: "project",
                    text: $0,
                    tone: .secondary,
                    style: .caption2,
                    isSelectable: false,
                    lineLimit: nil
                )
            },
            recipeLine: nil,
            goalLine: nil,
            controls: nil,
            detailRows: [],
            primaryActions: [],
            advanceActions: [],
            emptyStateText: nil
        )
    }
}
