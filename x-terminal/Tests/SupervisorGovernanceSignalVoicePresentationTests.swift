import Foundation
import Testing
@testable import XTerminal

struct SupervisorGovernanceSignalVoicePresentationTests {

    @Test
    func projectCreationOverviewUsesActionableVoiceTextAndHidesDiagnosticCode() {
        let presentation = SupervisorGovernanceSignalVoicePresentationMapper.map(
            overview: SupervisorSignalCenterOverviewPresentation(
                priority: .attention,
                priorityText: SupervisorHeartbeatPriority.attention.label,
                priorityTone: .accent,
                headlineText: "项目创建差一句触发",
                detailText: "已锁定《俄罗斯方块》，再说“立项”“创建一个project”就会真正创建。",
                metadataText: "目标：俄罗斯方块网页游戏 · 形态：网页版 · 诊断码：create_trigger_required_pending_intake",
                focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                    action: .scrollToBoard(SupervisorFocusPresentation.projectCreationBoardAnchorID),
                    label: "查看创建状态",
                    tone: .accent
                )
            )
        )

        #expect(presentation?.trigger == .blocked)
        #expect(presentation?.actionText == "直接说立项，或说创建一个project")
        #expect(presentation?.metadataText == "目标：俄罗斯方块网页游戏 · 形态：网页版")
    }

    @Test
    func projectCreationAwaitingGoalVoiceActionGuidesNextSentence() {
        let presentation = SupervisorGovernanceSignalVoicePresentationMapper.map(
            overview: SupervisorSignalCenterOverviewPresentation(
                priority: .attention,
                priorityText: SupervisorHeartbeatPriority.attention.label,
                priorityTone: .warning,
                headlineText: "项目创建缺目标",
                detailText: "当前只收到了“建项目/立项”意图，还没拿到项目名或明确交付目标。",
                metadataText: "最短用法：直接说“新建项目，名字叫 俄罗斯方块”；或先说目标再说“立项” · 诊断码：create_goal_missing",
                focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                    action: .scrollToBoard(SupervisorFocusPresentation.projectCreationBoardAnchorID),
                    label: "查看创建状态",
                    tone: .warning
                )
            )
        )

        #expect(presentation?.actionText == "直接给项目名，或先补一句要做什么")
        #expect(
            presentation?.metadataText
                == "最短用法：直接说“新建项目，名字叫 俄罗斯方块”；或先说目标再说“立项”"
        )
    }

    @Test
    func createdProjectAwaitingGoalVoiceActionPointsToGoalFollowUp() {
        let presentation = SupervisorGovernanceSignalVoicePresentationMapper.map(
            overview: SupervisorSignalCenterOverviewPresentation(
                priority: .attention,
                priorityText: SupervisorHeartbeatPriority.attention.label,
                priorityTone: .accent,
                headlineText: "项目已创建待补目标",
                detailText: "《坦克大战》已经创建完成，现在只差一句交付目标；补完后就会继续写入第一版工单。",
                metadataText: "最短用法：直接说“我要用默认的MVP” · 诊断码：create_goal_missing",
                focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                    action: .scrollToBoard(SupervisorFocusPresentation.projectCreationBoardAnchorID),
                    label: "查看创建状态",
                    tone: .accent
                )
            )
        )

        #expect(presentation?.actionText == "直接说我要用默认的MVP，或说第一版先做成最小可运行版本")
        #expect(presentation?.metadataText == "最短用法：直接说“我要用默认的MVP”")
    }

    @Test
    func blockedDoctorTruthOverviewUsesConcreteDoctorVoiceAction() {
        let presentation = SupervisorGovernanceSignalVoicePresentationMapper.map(
            overview: SupervisorSignalCenterOverviewPresentation(
                priority: .attention,
                priorityText: SupervisorHeartbeatPriority.attention.label,
                priorityTone: .danger,
                headlineText: "技能 doctor truth 需要处理",
                detailText: "技能 doctor truth：1 个技能当前不可运行。",
                metadataText: "当前可直接运行：2 个；当前阻塞：1 个（delivery-runner）；技能计数：3 个。",
                focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                    action: .scrollToBoard(SupervisorFocusPresentation.doctorBoardAnchorID),
                    label: "查看体检",
                    tone: .danger
                )
            )
        )

        #expect(presentation?.trigger == .blocked)
        #expect(presentation?.actionText == "打开体检，先处理技能 doctor truth 阻塞项")
        #expect(presentation?.metadataText.contains("当前阻塞：1 个") == true)
    }

    @Test
    func pendingDoctorTruthOverviewUsesConcreteGrantVoiceAction() {
        let presentation = SupervisorGovernanceSignalVoicePresentationMapper.map(
            overview: SupervisorSignalCenterOverviewPresentation(
                priority: .attention,
                priorityText: SupervisorHeartbeatPriority.attention.label,
                priorityTone: .warning,
                headlineText: "技能 doctor truth 需要处理",
                detailText: "技能 doctor truth：1 个待 Hub grant，1 个待本地确认。",
                metadataText: "当前可直接运行：4 个；待 Hub grant：1 个；待本地确认：1 个；技能计数：6 个。",
                focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                    action: .scrollToBoard(SupervisorFocusPresentation.doctorBoardAnchorID),
                    label: "查看体检",
                    tone: .warning
                )
            )
        )

        #expect(presentation?.trigger == .blocked)
        #expect(presentation?.actionText == "打开体检，先补技能 doctor truth 授权和确认")
        #expect(presentation?.metadataText.contains("待 Hub grant：1 个") == true)
    }
}
