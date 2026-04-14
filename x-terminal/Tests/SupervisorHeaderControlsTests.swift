import Foundation
import Testing
@testable import XTerminal

struct SupervisorHeaderControlsTests {

    @Test
    func presentationsReflectCurrentHeaderState() {
        let neutralContext = SupervisorHeaderControls.Context(
            hasFocusRequest: false,
            pendingHubGrantCount: 0,
            pendingSkillApprovalCount: 0,
            hasLatestHeartbeat: false,
            highestHeartbeatPriority: nil,
            heartbeatOverview: nil,
            hasLatestRuntimeActivity: false,
            signalCenterOverview: nil,
            isSignalCenterVisible: false,
            requestedWindowSheet: nil
        )
        let activeContext = SupervisorHeaderControls.Context(
            hasFocusRequest: true,
            pendingHubGrantCount: 2,
            pendingSkillApprovalCount: 1,
            hasLatestHeartbeat: true,
            highestHeartbeatPriority: .immediate,
            heartbeatOverview: heartbeatOverview(
                priority: .immediate,
                headlineText: "治理修复"
            ),
            hasLatestRuntimeActivity: true,
            signalCenterOverview: signalCenterOverview(
                priority: .immediate,
                priorityTone: .warning,
                headlineText: "Hub 待处理授权"
            ),
            isSignalCenterVisible: true,
            requestedWindowSheet: .modelSettings
        )

        let neutralHeartbeat = SupervisorHeaderControls.presentation(
            for: .heartbeat,
            context: neutralContext
        )
        let activeHeartbeat = SupervisorHeaderControls.presentation(
            for: .heartbeat,
            context: activeContext
        )
        let activeOperations = SupervisorHeaderControls.presentation(
            for: .operations,
            context: activeContext
        )
        let supervisorSettings = SupervisorHeaderControls.presentation(
            for: .supervisorSettings,
            context: activeContext
        )
        let modelSettings = SupervisorHeaderControls.presentation(
            for: .modelSettings,
            context: activeContext
        )
        let operationsDrivenHeartbeat = SupervisorHeaderControls.presentation(
            for: .heartbeat,
            context: SupervisorHeaderControls.Context(
                hasFocusRequest: false,
                pendingHubGrantCount: 1,
                pendingSkillApprovalCount: 0,
                hasLatestHeartbeat: false,
                highestHeartbeatPriority: nil,
                heartbeatOverview: nil,
                hasLatestRuntimeActivity: true,
                signalCenterOverview: signalCenterOverview(
                    priority: .immediate,
                    priorityTone: .warning,
                    headlineText: "Hub 待处理授权"
                ),
                isSignalCenterVisible: false,
                requestedWindowSheet: nil
            )
        )

        #expect(neutralHeartbeat.iconName == "heart")
        #expect(neutralHeartbeat.tone == .neutral)
        #expect(neutralHeartbeat.chrome == .plain)
        #expect(activeHeartbeat.iconName == "heart.fill")
        #expect(activeHeartbeat.tone == .warning)
        #expect(activeHeartbeat.helpText == "打开 Supervisor 心跳（当前：治理修复）")
        #expect(
            activeHeartbeat.chrome == SupervisorHeaderButtonChrome(
                tone: .warning,
                fillOpacity: 0.18,
                strokeOpacity: 0.30,
                shadowOpacity: 0.16
            )
        )
        #expect(activeOperations.iconName == "square.grid.2x2.fill")
        #expect(activeOperations.tone == .warning)
        #expect(activeOperations.helpText == "收起 Supervisor 看板（当前：Hub 待处理授权）")
        #expect(supervisorSettings.helpText == "在当前 Supervisor 主窗口打开 Control Center（含 AI 模型）")
        #expect(modelSettings.helpText == "在当前 Supervisor 主窗口打开 Control Center 的 AI 模型页签")
        #expect(operationsDrivenHeartbeat.iconName == "heart")
        #expect(operationsDrivenHeartbeat.tone == .neutral)
        #expect(operationsDrivenHeartbeat.helpText == "打开 Supervisor 心跳")
    }

    @Test
    func heartbeatPresentationTracksPriorityTone() {
        let attentionContext = SupervisorHeaderControls.Context(
            hasFocusRequest: false,
            pendingHubGrantCount: 0,
            pendingSkillApprovalCount: 0,
            hasLatestHeartbeat: true,
            highestHeartbeatPriority: .attention,
            heartbeatOverview: heartbeatOverview(
                priority: .attention,
                headlineText: "语音就绪"
            ),
            hasLatestRuntimeActivity: false,
            signalCenterOverview: nil,
            isSignalCenterVisible: false,
            requestedWindowSheet: nil
        )
        let watchContext = SupervisorHeaderControls.Context(
            hasFocusRequest: false,
            pendingHubGrantCount: 0,
            pendingSkillApprovalCount: 0,
            hasLatestHeartbeat: true,
            highestHeartbeatPriority: .watch,
            heartbeatOverview: heartbeatOverview(
                priority: .watch,
                headlineText: "继续观察"
            ),
            hasLatestRuntimeActivity: false,
            signalCenterOverview: nil,
            isSignalCenterVisible: false,
            requestedWindowSheet: nil
        )

        let attentionHeartbeat = SupervisorHeaderControls.presentation(
            for: .heartbeat,
            context: attentionContext
        )
        let watchHeartbeat = SupervisorHeaderControls.presentation(
            for: .heartbeat,
            context: watchContext
        )

        #expect(attentionHeartbeat.tone == .accent)
        #expect(attentionHeartbeat.helpText == "打开 Supervisor 心跳（当前：语音就绪）")
        #expect(
            attentionHeartbeat.chrome == SupervisorHeaderButtonChrome(
                tone: .accent,
                fillOpacity: 0.16,
                strokeOpacity: 0.28,
                shadowOpacity: 0.12
            )
        )
        #expect(watchHeartbeat.tone == .success)
        #expect(watchHeartbeat.helpText == "打开 Supervisor 心跳（当前：继续观察）")
        #expect(
            watchHeartbeat.chrome == SupervisorHeaderButtonChrome(
                tone: .success,
                fillOpacity: 0.14,
                strokeOpacity: 0.22,
                shadowOpacity: 0.08
            )
        )
    }

    @Test
    func operationsPresentationReflectsOpenSignalCenterState() {
        let watchContext = SupervisorHeaderControls.Context(
            hasFocusRequest: false,
            pendingHubGrantCount: 0,
            pendingSkillApprovalCount: 0,
            hasLatestHeartbeat: false,
            highestHeartbeatPriority: nil,
            heartbeatOverview: nil,
            hasLatestRuntimeActivity: true,
            signalCenterOverview: signalCenterOverview(
                priority: .watch,
                priorityTone: .accent,
                headlineText: "运行动态有新事件"
            ),
            isSignalCenterVisible: false,
            requestedWindowSheet: nil
        )
        let stableOpenContext = SupervisorHeaderControls.Context(
            hasFocusRequest: false,
            pendingHubGrantCount: 0,
            pendingSkillApprovalCount: 0,
            hasLatestHeartbeat: false,
            highestHeartbeatPriority: nil,
            heartbeatOverview: nil,
            hasLatestRuntimeActivity: false,
            signalCenterOverview: signalCenterOverview(
                priority: .stable,
                priorityTone: .neutral,
                headlineText: "信号中心空闲"
            ),
            isSignalCenterVisible: true,
            requestedWindowSheet: nil
        )

        let watchOperations = SupervisorHeaderControls.presentation(
            for: .operations,
            context: watchContext
        )
        let stableOpenOperations = SupervisorHeaderControls.presentation(
            for: .operations,
            context: stableOpenContext
        )

        #expect(watchOperations.iconName == "square.grid.2x2.fill")
        #expect(watchOperations.tone == .accent)
        #expect(watchOperations.helpText == "打开 Supervisor 看板（当前：运行动态有新事件）")
        #expect(
            watchOperations.chrome == SupervisorHeaderButtonChrome(
                tone: .accent,
                fillOpacity: 0.14,
                strokeOpacity: 0.22,
                shadowOpacity: 0.08
            )
        )
        #expect(stableOpenOperations.iconName == "square.grid.2x2.fill")
        #expect(
            stableOpenOperations.chrome == SupervisorHeaderButtonChrome(
                tone: .neutral,
                fillOpacity: 0.10,
                strokeOpacity: 0.16,
                shadowOpacity: 0
            )
        )
    }

    @Test
    func actionResolverBuildsHeaderEffects() {
        let context = SupervisorHeaderControls.Context(
            hasFocusRequest: false,
            pendingHubGrantCount: 0,
            pendingSkillApprovalCount: 0,
            hasLatestHeartbeat: true,
            highestHeartbeatPriority: .attention,
            heartbeatOverview: heartbeatOverview(
                priority: .attention,
                headlineText: "语音就绪"
            ),
            hasLatestRuntimeActivity: false,
            signalCenterOverview: nil,
            isSignalCenterVisible: true,
            requestedWindowSheet: nil
        )

        #expect(
            SupervisorHeaderControls.resolve(
                action: .heartbeatButtonTapped,
                context: context
            ).effects == [
                .setSignalCenter(false),
                .setHeartbeatFeed(true)
            ]
        )
        #expect(
            SupervisorHeaderControls.resolve(
                action: .operationsButtonTapped,
                context: context
            ).effects == [
                .setSignalCenter(false)
            ]
        )
        #expect(
            SupervisorHeaderControls.resolve(
                action: .focusSignalCenterOverview(
                    .scrollToBoard(SupervisorFocusPresentation.pendingHubGrantBoardAnchorID)
                ),
                context: context
            ).effects == [
                .setHeartbeatFeed(false),
                .setSignalCenter(true),
                .focusSignalCenterOverview(
                    .scrollToBoard(SupervisorFocusPresentation.pendingHubGrantBoardAnchorID)
                )
            ]
        )
        #expect(
            SupervisorHeaderControls.resolve(
                action: .supervisorSettingsTapped,
                context: context
            ).effects == [.setWindowSheet(.supervisorSettings)]
        )
        #expect(
            SupervisorHeaderControls.resolve(
                action: .modelSettingsTapped,
                context: context
            ).effects == [.setWindowSheet(.modelSettings)]
        )
        #expect(
            SupervisorHeaderControls.resolve(
                action: .clearConversationTapped,
                context: context
            ).effects == [.clearConversation]
        )
    }

    @Test
    func lifecycleResolverAutoOpensPanelsAndPulses() {
        let autoOpenContext = SupervisorHeaderControls.Context(
            hasFocusRequest: true,
            pendingHubGrantCount: 2,
            pendingSkillApprovalCount: 1,
            hasLatestHeartbeat: true,
            highestHeartbeatPriority: .immediate,
            heartbeatOverview: heartbeatOverview(
                priority: .immediate,
                headlineText: "治理修复"
            ),
            hasLatestRuntimeActivity: true,
            signalCenterOverview: signalCenterOverview(
                priority: .immediate,
                priorityTone: .warning,
                headlineText: "Hub 待处理授权"
            ),
            isSignalCenterVisible: false,
            requestedWindowSheet: .modelSettings
        )
        let idleContext = SupervisorHeaderControls.Context(
            hasFocusRequest: false,
            pendingHubGrantCount: 0,
            pendingSkillApprovalCount: 0,
            hasLatestHeartbeat: false,
            highestHeartbeatPriority: nil,
            heartbeatOverview: nil,
            hasLatestRuntimeActivity: false,
            signalCenterOverview: nil,
            isSignalCenterVisible: false,
            requestedWindowSheet: nil
        )

        #expect(
            SupervisorHeaderControls.resolve(
                event: .focusRequestChanged,
                context: autoOpenContext
            )?.effects == [.setHeartbeatFeed(false), .setSignalCenter(true)]
        )
        #expect(
            SupervisorHeaderControls.resolve(
                event: .pendingHubGrantsChanged,
                context: autoOpenContext
            )?.effects == [.setHeartbeatFeed(false), .setSignalCenter(true)]
        )
        #expect(
            SupervisorHeaderControls.resolve(
                event: .pendingSkillApprovalsChanged,
                context: autoOpenContext
            )?.effects == [.setHeartbeatFeed(false), .setSignalCenter(true)]
        )
        #expect(
            SupervisorHeaderControls.resolve(
                event: .requestedWindowSheetChanged,
                context: autoOpenContext
            )?.effects == [.setWindowSheet(.modelSettings), .clearRequestedWindowSheet]
        )
        #expect(
            SupervisorHeaderControls.resolve(
                event: .latestHeartbeatChanged,
                context: autoOpenContext
            )?.effects == [.pulse]
        )
        #expect(
            SupervisorHeaderControls.resolve(
                event: .signalCenterChanged,
                context: autoOpenContext
            )?.effects == [.pulse]
        )

        #expect(
            SupervisorHeaderControls.resolve(
                event: .focusRequestChanged,
                context: idleContext
            ) == nil
        )
        #expect(
            SupervisorHeaderControls.resolve(
                event: .requestedWindowSheetChanged,
                context: idleContext
            ) == nil
        )
        #expect(
            SupervisorHeaderControls.resolve(
                event: .signalCenterChanged,
                context: idleContext
            ) == nil
        )
    }

    @Test
    func signalCenterPulseFollowsOverviewPriority() {
        let watchContext = SupervisorHeaderControls.Context(
            hasFocusRequest: false,
            pendingHubGrantCount: 0,
            pendingSkillApprovalCount: 0,
            hasLatestHeartbeat: false,
            highestHeartbeatPriority: nil,
            heartbeatOverview: nil,
            hasLatestRuntimeActivity: true,
            signalCenterOverview: signalCenterOverview(
                priority: .watch,
                priorityTone: .accent,
                headlineText: "运行动态有新事件"
            ),
            isSignalCenterVisible: false,
            requestedWindowSheet: nil
        )
        let stableContext = SupervisorHeaderControls.Context(
            hasFocusRequest: false,
            pendingHubGrantCount: 0,
            pendingSkillApprovalCount: 0,
            hasLatestHeartbeat: false,
            highestHeartbeatPriority: nil,
            heartbeatOverview: nil,
            hasLatestRuntimeActivity: false,
            signalCenterOverview: signalCenterOverview(
                priority: .stable,
                priorityTone: .neutral,
                headlineText: "信号中心空闲"
            ),
            isSignalCenterVisible: false,
            requestedWindowSheet: nil
        )

        #expect(
            SupervisorHeaderControls.resolve(
                event: .signalCenterChanged,
                context: watchContext
            )?.effects == [.pulse]
        )
        #expect(
            SupervisorHeaderControls.resolve(
                event: .signalCenterChanged,
                context: stableContext
            ) == nil
        )
    }

    @Test
    func pulseStepsMatchExpectedSequences() {
        #expect(
            SupervisorHeaderControls.pulseSteps() == [
                SupervisorHeaderPulseStep(delaySeconds: 0.0, scale: 1.18),
                SupervisorHeaderPulseStep(delaySeconds: 0.16, scale: 1.0),
                SupervisorHeaderPulseStep(delaySeconds: 0.28, scale: 1.14),
                SupervisorHeaderPulseStep(delaySeconds: 0.44, scale: 1.0)
            ]
        )
    }

    @Test
    func signalActionReflectsHighestPrioritySignalCenterFocus() {
        let context = SupervisorHeaderControls.Context(
            hasFocusRequest: false,
            pendingHubGrantCount: 1,
            pendingSkillApprovalCount: 0,
            hasLatestHeartbeat: false,
            highestHeartbeatPriority: nil,
            heartbeatOverview: nil,
            hasLatestRuntimeActivity: false,
            signalCenterOverview: signalCenterOverview(
                priority: .immediate,
                priorityTone: .warning,
                headlineText: "Hub 待处理授权",
                focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                    action: .scrollToBoard(SupervisorFocusPresentation.pendingHubGrantBoardAnchorID),
                    label: "查看授权板",
                    tone: .warning
                )
            ),
            isSignalCenterVisible: false,
            requestedWindowSheet: nil
        )

        #expect(
            SupervisorHeaderControls.signalAction(context: context)
                == SupervisorHeaderControls.SignalActionPresentation(
                    action: .scrollToBoard(SupervisorFocusPresentation.pendingHubGrantBoardAnchorID),
                    label: "查看授权板",
                    tone: .warning,
                    helpText: "聚焦当前主信号（Hub 待处理授权）"
                )
        )
    }

    private func signalCenterOverview(
        priority: SupervisorHeartbeatPriority,
        priorityTone: SupervisorHeaderControlTone,
        headlineText: String,
        focusAction: SupervisorSignalCenterOverviewActionDescriptor? = nil
    ) -> SupervisorSignalCenterOverviewPresentation {
        SupervisorSignalCenterOverviewPresentation(
            priority: priority,
            priorityText: priority.label,
            priorityTone: priorityTone,
            headlineText: headlineText,
            detailText: "detail",
            metadataText: "metadata",
            focusAction: focusAction
        )
    }

    private func heartbeatOverview(
        priority: SupervisorHeartbeatPriority,
        headlineText: String
    ) -> SupervisorHeartbeatOverviewPresentation {
        SupervisorHeartbeatOverviewPresentation(
            priority: priority,
            priorityText: priority.label,
            priorityTone: priority.tone,
            headlineText: headlineText,
            detailText: "detail",
            metadataText: "metadata",
            focusAction: nil
        )
    }
}
