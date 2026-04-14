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
    func pendingSkillGrantUsesAuthorizationHeadlineAndFocusLabel() {
        let presentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(rows: []),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(
                modeText: "等待 Hub grant",
                rows: [
                    SupervisorPendingSkillApprovalRowPresentation(
                        id: "approval-grant-1",
                        anchorID: "approval-grant-anchor",
                        iconName: "globe",
                        title: "Project · agent-browser",
                        ageText: "2m",
                        summary: "运行浏览器受治理技能前，还需要先通过 Hub 授权。",
                        nextStepText: "先完成 Hub grant，再恢复这次受治理技能调用。",
                        routingExplanationText: "路由说明： browser.search 会走 Hub governed package",
                        noteText: nil,
                        requestIdentifierText: "请求单号：req-grant-1",
                        isFocused: false,
                        actionDescriptors: [],
                        authorizationMode: .hubGrant
                    )
                ]
            ),
            runtimeActivityPresentation: runtimeBoard(rows: []),
            automationPresentation: automationPresentation(iconTone: .accent),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(presentation.priority == .immediate)
        #expect(presentation.headlineText == "技能授权待处理")
        #expect(presentation.detailText == "先完成 Hub grant，再恢复这次受治理技能调用。")
        #expect(presentation.metadataText.contains("等待 Hub grant"))
        #expect(
            presentation.focusAction == SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(
                    SupervisorFocusPresentation.pendingSupervisorSkillApprovalBoardAnchorID
                ),
                label: "查看技能授权",
                tone: .warning
            )
        )
    }

    @Test
    func pendingSkillGovernanceBlockUsesBlockedHeadlineAndFocusLabel() {
        let presentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(rows: []),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(
                modeText: "治理阻塞",
                rows: [
                    SupervisorPendingSkillApprovalRowPresentation(
                        id: "approval-blocked-1",
                        anchorID: "approval-blocked-anchor",
                        iconName: "exclamationmark.triangle",
                        title: "Project · governed-skill",
                        ageText: "4m",
                        summary: "当前运行面不允许继续执行这条受治理技能。",
                        nextStepText: "先按阻塞提示处理，再决定是否恢复这次调用。",
                        routingExplanationText: nil,
                        noteText: "执行就绪：治理阻塞",
                        requestIdentifierText: "请求单号：req-blocked-1",
                        isFocused: false,
                        actionDescriptors: [],
                        authorizationMode: .blocked
                    )
                ]
            ),
            runtimeActivityPresentation: runtimeBoard(rows: []),
            automationPresentation: automationPresentation(iconTone: .accent),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(presentation.priority == .immediate)
        #expect(presentation.headlineText == "技能治理待处理")
        #expect(presentation.detailText == "先按阻塞提示处理，再决定是否恢复这次调用。")
        #expect(presentation.metadataText.contains("治理阻塞"))
        #expect(
            presentation.focusAction == SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(
                    SupervisorFocusPresentation.pendingSupervisorSkillApprovalBoardAnchorID
                ),
                label: "查看技能处理",
                tone: .warning
            )
        )
    }

    @Test
    func projectCreationStatusWinsOverRuntimeActivityWhenPresent() {
        let presentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(rows: []),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(rows: []),
            projectCreationPresentation: projectCreationStatus(
                priority: .attention,
                priorityTone: .warning,
                reasonCode: "create_goal_missing",
                headlineText: "项目创建缺目标",
                detailText: "当前只收到了“建项目/立项”意图，还没拿到项目名或明确交付目标。",
                metadataText: "最短用法：直接说“新建项目，名字叫 俄罗斯方块”；或先说目标再说“立项”"
            ),
            runtimeActivityPresentation: runtimeBoard(
                rows: [
                    SupervisorRuntimeActivityRowPresentation(
                        id: "log-create-1",
                        timeText: "10:32",
                        text: "runtime activity should stay secondary",
                        blockedSummaryText: nil,
                        governanceTruthText: nil,
                        governanceReasonText: nil,
                        policyReasonText: nil,
                        actionDescriptors: [],
                        showsDivider: false
                    )
                ]
            ),
            automationPresentation: automationPresentation(iconTone: .neutral),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(presentation.priority == .attention)
        #expect(presentation.headlineText == "项目创建缺目标")
        #expect(presentation.detailText.contains("明确交付目标"))
        #expect(presentation.metadataText.contains("诊断码：create_goal_missing"))
        #expect(
            presentation.focusAction == SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(SupervisorFocusPresentation.projectCreationBoardAnchorID),
                label: "查看创建状态",
                tone: .warning
            )
        )
    }

    @Test
    func createdProjectAwaitingGoalStatusWinsOverRuntimeActivityWhenPresent() {
        let presentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(rows: []),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(rows: []),
            projectCreationPresentation: projectCreationStatus(
                priority: .attention,
                priorityTone: .accent,
                reasonCode: "create_goal_missing",
                headlineText: "项目已创建待补目标",
                detailText: "《坦克大战》已经创建完成，现在只差一句交付目标；补完后就会继续写入第一版工单。",
                metadataText: "最短用法：直接说“我要用默认的MVP”"
            ),
            runtimeActivityPresentation: runtimeBoard(
                rows: [
                    SupervisorRuntimeActivityRowPresentation(
                        id: "log-create-2",
                        timeText: "10:34",
                        text: "runtime activity should stay secondary",
                        blockedSummaryText: nil,
                        governanceTruthText: nil,
                        governanceReasonText: nil,
                        policyReasonText: nil,
                        actionDescriptors: [],
                        showsDivider: false
                    )
                ]
            ),
            automationPresentation: automationPresentation(iconTone: .neutral),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(presentation.priority == .attention)
        #expect(presentation.headlineText == "项目已创建待补目标")
        #expect(presentation.detailText.contains("坦克大战"))
        #expect(presentation.metadataText.contains("诊断码：create_goal_missing"))
        #expect(
            presentation.focusAction == SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(SupervisorFocusPresentation.projectCreationBoardAnchorID),
                label: "查看创建状态",
                tone: .accent
            )
        )
    }

    @Test
    func pendingHubGrantStillWinsOverProjectCreationStatus() {
        let presentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(
                rows: [
                    SupervisorPendingHubGrantRowPresentation(
                        id: "grant-2",
                        anchorID: "grant-anchor-2",
                        title: "P1 · Project · Paid model",
                        ageText: "1m",
                        summary: "等待审批",
                        supplementaryReasonText: nil,
                        priorityReasonText: nil,
                        nextActionText: "打开授权并批准 paid model grant",
                        scopeSummaryText: nil,
                        grantIdentifierText: "授权单号：g2",
                        isFocused: false,
                        isInFlight: false,
                        actionDescriptors: []
                    )
                ]
            ),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(rows: []),
            projectCreationPresentation: projectCreationStatus(
                priority: .attention,
                priorityTone: .accent,
                reasonCode: "create_trigger_required_pending_intake",
                headlineText: "项目创建差一句触发",
                detailText: "已锁定《俄罗斯方块》，再说“立项”就会真正创建。",
                metadataText: "目标：俄罗斯方块网页游戏 · 形态：网页版"
            ),
            runtimeActivityPresentation: runtimeBoard(rows: []),
            automationPresentation: automationPresentation(iconTone: .neutral),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(presentation.priority == .immediate)
        #expect(presentation.headlineText == "Hub 待处理授权")
        #expect(presentation.detailText == "打开授权并批准 paid model grant")
    }

    @Test
    func candidateReviewWinsOverGenericRuntimeWhenNoHigherPrioritySignalExists() {
        let presentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(rows: []),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(rows: []),
            candidateReviewPresentation: candidateReviewBoard(
                rows: [
                    SupervisorCandidateReviewRowPresentation(
                        id: "review-1",
                        anchorID: "candidate-anchor",
                        title: "Project Alpha · 3 条候选记忆",
                        ageText: "刚刚",
                        summary: "归并了 3 条高信号候选记忆",
                        reviewStateText: "状态：待转入审查",
                        scopeText: nil,
                        draftText: nil,
                        evidenceText: "handoff:req-1",
                        isFocused: false,
                        isInFlight: false,
                        actionDescriptors: []
                    )
                ]
            ),
            runtimeActivityPresentation: runtimeBoard(
                rows: [
                    SupervisorRuntimeActivityRowPresentation(
                        id: "log-1",
                        timeText: "10:32",
                        text: "runtime activity should stay secondary",
                        blockedSummaryText: nil,
                        governanceTruthText: nil,
                        governanceReasonText: nil,
                        policyReasonText: nil,
                        actionDescriptors: [],
                        showsDivider: false
                    )
                ]
            ),
            automationPresentation: automationPresentation(iconTone: .neutral),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(presentation.priority == .attention)
        #expect(presentation.headlineText == "候选记忆待审查")
        #expect(presentation.detailText == "归并了 3 条高信号候选记忆")
        #expect(presentation.metadataText.contains("1 项待处理"))
        #expect(presentation.metadataText.contains("状态：待转入审查"))
        #expect(
            presentation.focusAction == SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(SupervisorFocusPresentation.candidateReviewBoardAnchorID),
                label: "查看候选审查",
                tone: .accent
            )
        )
    }

    @Test
    func blockedSkillDoctorTruthWinsOverCandidateReviewAndRuntimeWhenNoHigherPrioritySignalExists() {
        let presentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(rows: []),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(rows: []),
            candidateReviewPresentation: candidateReviewBoard(
                rows: [
                    SupervisorCandidateReviewRowPresentation(
                        id: "review-doctor-truth-1",
                        anchorID: "candidate-anchor",
                        title: "Project Alpha · 1 条候选记忆",
                        ageText: "刚刚",
                        summary: "候选记忆待审查",
                        reviewStateText: "状态：待转入审查",
                        scopeText: nil,
                        draftText: nil,
                        evidenceText: "",
                        isFocused: false,
                        isInFlight: false,
                        actionDescriptors: []
                    )
                ]
            ),
            doctorPresentation: doctorBoardPresentation(
                skillDoctorTruthStatusLine: "技能 doctor truth：1 个技能当前不可运行。",
                skillDoctorTruthTone: .danger,
                skillDoctorTruthDetailLine: "当前可直接运行：observe_only；当前阻塞：delivery-runner（policy clamped）"
            ),
            runtimeActivityPresentation: runtimeBoard(
                rows: [
                    SupervisorRuntimeActivityRowPresentation(
                        id: "log-doctor-truth-1",
                        timeText: "10:32",
                        text: "runtime activity should stay secondary",
                        blockedSummaryText: nil,
                        governanceTruthText: nil,
                        governanceReasonText: nil,
                        policyReasonText: nil,
                        actionDescriptors: [],
                        showsDivider: false
                    )
                ]
            ),
            automationPresentation: automationPresentation(iconTone: .neutral),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(presentation.priority == SupervisorHeartbeatPriority.attention)
        #expect(presentation.priorityTone == SupervisorHeaderControlTone.danger)
        #expect(presentation.headlineText == "技能 doctor truth 需要处理")
        #expect(presentation.detailText == "技能 doctor truth：1 个技能当前不可运行。")
        #expect(presentation.metadataText.contains("当前阻塞：delivery-runner"))
        #expect(
            presentation.focusAction == SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(SupervisorFocusPresentation.doctorBoardAnchorID),
                label: "查看体检",
                tone: .danger
            )
        )
    }

    @Test
    func pendingSkillDoctorTruthWinsOverRuntimeWhenNoHigherPrioritySignalExists() {
        let presentation = SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantBoard(rows: []),
            pendingSkillApprovalPresentation: pendingSkillApprovalBoard(rows: []),
            doctorPresentation: doctorBoardPresentation(
                skillDoctorTruthStatusLine: "技能 doctor truth：1 个待 Hub grant，1 个待本地确认。",
                skillDoctorTruthTone: .warning,
                skillDoctorTruthDetailLine: "当前可直接运行：observe_only；待 Hub grant：tavily-websearch；待本地确认：browser-operator"
            ),
            runtimeActivityPresentation: runtimeBoard(
                rows: [
                    SupervisorRuntimeActivityRowPresentation(
                        id: "log-doctor-truth-2",
                        timeText: "10:40",
                        text: "runtime activity should stay secondary",
                        blockedSummaryText: nil,
                        governanceTruthText: nil,
                        governanceReasonText: nil,
                        policyReasonText: nil,
                        actionDescriptors: [],
                        showsDivider: false
                    )
                ]
            ),
            automationPresentation: automationPresentation(iconTone: .neutral),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(presentation.priority == SupervisorHeartbeatPriority.attention)
        #expect(presentation.priorityTone == SupervisorHeaderControlTone.warning)
        #expect(presentation.headlineText == "技能 doctor truth 需要处理")
        #expect(presentation.detailText == "技能 doctor truth：1 个待 Hub grant，1 个待本地确认。")
        #expect(presentation.metadataText.contains("待 Hub grant：tavily-websearch"))
        #expect(presentation.metadataText.contains("待本地确认：browser-operator"))
        #expect(
            presentation.focusAction == SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(SupervisorFocusPresentation.doctorBoardAnchorID),
                label: "查看体检",
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
                        blockedSummaryText: nil,
                        governanceTruthText: nil,
                        governanceReasonText: nil,
                        policyReasonText: nil,
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
                        blockedSummaryText: nil,
                        governanceTruthText: nil,
                        governanceReasonText: nil,
                        policyReasonText: nil,
                        contractText: "合同： 故障恢复 · blocker=project_memory_failed",
                        nextSafeActionText: "安全下一步： 先检查当前异常，再决定是否重规划",
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
        #expect(presentation.metadataText.contains("安全下一步： 先检查当前异常，再决定是否重规划"))
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
                nextSafeActionText: "安全下一步： 先检查当前异常，再决定是否重规划"
            ),
            laneHealthPresentation: laneHealthBoard(iconTone: .neutral)
        )

        #expect(presentation.priority == .attention)
        #expect(presentation.headlineText == "自动化执行需要关注")
        #expect(presentation.detailText == "合同： 故障恢复 · blocker=trusted_automation_workspace_mismatch")
        #expect(presentation.metadataText.contains("安全下一步： 先检查当前异常，再决定是否重规划"))
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
                statusLine: "泳道健康：总计 2 · 运行中 1 · 阻塞 1 · 停滞 0 · 失败 0",
                summaryLine: "running=1 · blocked=1 · stalled=0 · failed=0 · waiting=0 · recovering=0",
                rows: [
                    SupervisorLaneHealthRowPresentation(
                        laneID: "lane-3",
                        isFocused: false,
                        title: "lane-3 · 阻塞",
                        statusIconName: "pause.circle.fill",
                        statusTone: .warning,
                        reasonLine: "原因：等待授权（grant_pending） · 下一步：通知用户（notify_user）",
                        reasonTone: .warning,
                        contractText: "合同： 授权处理 · blocker=grant_pending",
                        nextSafeActionText: "安全下一步： 打开 Hub 授权面板 · 建议动作：通知用户",
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
        #expect(presentation.detailText == "原因：等待授权 · 下一步：通知用户")
        #expect(presentation.metadataText.contains("lane-3 · 阻塞"))
        #expect(presentation.metadataText.contains("泳道健康：总计 2 · 运行中 1 · 阻塞 1 · 停滞 0 · 失败 0"))
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
        modeText: String = "本地审批",
        rows: [SupervisorPendingSkillApprovalRowPresentation]
    ) -> SupervisorPendingSkillApprovalBoardPresentation {
        SupervisorPendingSkillApprovalBoardPresentation(
            iconName: rows.isEmpty ? "checkmark.shield" : "hand.raised.fill",
            iconTone: rows.isEmpty ? .neutral : .warning,
            title: "待审批技能：\(rows.count)",
            modeText: modeText,
            emptyStateText: rows.isEmpty ? "empty" : nil,
            rows: rows
        )
    }

    private func candidateReviewBoard(
        rows: [SupervisorCandidateReviewRowPresentation]
    ) -> SupervisorCandidateReviewBoardPresentation {
        SupervisorCandidateReviewBoardPresentation(
            iconName: rows.isEmpty ? "tray" : "square.stack.3d.up.badge.a.fill",
            iconTone: rows.isEmpty ? .neutral : .accent,
            title: "Supervisor 候选记忆审查：\(rows.count)",
            snapshotText: "来源：Hub · 快照新鲜",
            freshnessWarningText: nil,
            footerNote: nil,
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
        statusLine: String = "泳道健康：空闲",
        summaryLine: String = "running=0 · blocked=0 · stalled=0 · failed=0 · waiting=0 · recovering=0",
        rows: [SupervisorLaneHealthRowPresentation] = []
    ) -> SupervisorLaneHealthBoardPresentation {
        SupervisorLaneHealthBoardPresentation(
            iconName: "heart.text.square.fill",
            iconTone: iconTone,
            title: "泳道健康态",
            statusLine: statusLine,
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
            statusAction: SupervisorAutomationRuntimeActionResolver.descriptor(
                for: .status,
                context: SupervisorAutomationRuntimeActionResolver.Context(
                    hasSelectedProject: true,
                    hasRecipe: false,
                    hasLastLaunchRef: false
                )
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

    private func projectCreationStatus(
        priority: SupervisorHeartbeatPriority,
        priorityTone: SupervisorHeaderControlTone,
        reasonCode: String,
        headlineText: String,
        detailText: String,
        metadataText: String
    ) -> SupervisorProjectCreationStatusPresentation {
        SupervisorProjectCreationStatusPresentation(
            priority: priority,
            priorityTone: priorityTone,
            reasonCode: reasonCode,
            headlineText: headlineText,
            detailText: detailText,
            metadataText: metadataText,
            projectNameText: nil,
            goalText: nil,
            trackText: nil,
            recommendedCommands: []
        )
    }

    private func doctorBoardPresentation(
        skillDoctorTruthStatusLine: String?,
        skillDoctorTruthTone: SupervisorHeaderControlTone,
        skillDoctorTruthDetailLine: String?
    ) -> SupervisorDoctorBoardPresentation {
        SupervisorDoctorBoardPresentation(
            iconName: "checkmark.shield.fill",
            iconTone: .success,
            title: "Supervisor 体检",
            statusLine: "体检检查通过",
            releaseBlockLine: "发布级体检门已满足。",
            skillDoctorTruthStatusLine: skillDoctorTruthStatusLine,
            skillDoctorTruthTone: skillDoctorTruthTone,
            skillDoctorTruthDetailLine: skillDoctorTruthDetailLine,
            memoryReadinessLine: "战略复盘所需记忆已就绪。",
            memoryReadinessTone: .success,
            memoryIssueSummaryLine: nil,
            memoryIssueDetailLine: nil,
            projectMemoryAdvisoryLine: nil,
            projectMemoryAdvisoryTone: .neutral,
            projectMemoryAdvisoryDetailLine: nil,
            memoryContinuitySummaryLine: nil,
            memoryContinuityDetailLine: nil,
            canonicalRetryStatusLine: nil,
            canonicalRetryTone: .neutral,
            canonicalRetryMetaLine: nil,
            canonicalRetryDetailLine: nil,
            emptyStateText: nil,
            reportLine: nil
        )
    }
}
