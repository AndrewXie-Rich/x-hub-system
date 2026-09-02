import Foundation

extension SupervisorManager {
    func buildExecutionProjectBootstrapSpec(
        project: AXProjectEntry,
        intake: SupervisorPendingExecutionIntake
    ) -> SupervisorExecutionProjectBootstrapSpec {
        let normalizedGoal = normalizedSupervisorIntentText(intake.goalSummary)
        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let projectToken = normalizedLookupKey(project.displayName).isEmpty
            ? String(project.projectId.prefix(8)).lowercased()
            : String(normalizedLookupKey(project.displayName).prefix(24))
        let planId = "plan-\(projectToken)-execution-intake-\(nowMs)"

        if containsAny(normalizedGoal, ["贪食蛇", "贪吃蛇", "snake"]) {
            let goal = "交付一个最小可运行的网页版贪食蛇游戏"
            let doneDefinition = "能在浏览器本地直接运行，支持方向键控制、吃到食物增长、撞墙或撞自己判负、显示分数，并且可以一键重新开始。"
            let nonGoals = ["先不做联网排行榜", "先不做账号系统", "先不做多人模式"]
            let approvedTechStack = ["HTML", "CSS", "Vanilla JavaScript"]
            let currentState = "默认方案已锁定，待 Project AI 按工单开始实现"
            let nextStep = "搭建最小可运行的页面骨架、渲染循环和输入控制"
            let alignmentDetail = [
                "bootstrap_source=pending_execution_intake",
                "requested_goal=\(intake.goalSummary)",
                "track=\(intake.track)",
                "done_definition=\(doneDefinition)",
                "non_goals=\(nonGoals.joined(separator: " | "))",
                "approved_stack=\(approvedTechStack.joined(separator: " | "))"
            ].joined(separator: "\n")
            let shellDetail = [
                "owner=coder",
                "deliverable=minimal_web_snake_shell",
                "must_include=single playable entry page, render loop, keyboard input, deterministic start state",
                "runtime=browser_local_open"
            ].joined(separator: "\n")
            let gameplayDetail = [
                "owner=coder",
                "must_include=movement tick, food spawn, growth, wall collision, self collision, score, restart",
                "acceptance=playable end-to-end without network",
                "failure_policy=replan_on_unexpected_loop"
            ].joined(separator: "\n")
            let verifyDetail = [
                "owner=coder",
                "verify=keyboard control works; food increases score/body; death condition fires; restart works",
                "write_back=short run instructions and extension ideas",
                "evidence=manual verification notes"
            ].joined(separator: "\n")
            let summaryDetail = [
                "owner=supervisor",
                "notify=user",
                "include=what shipped, how to run, remaining stretch ideas"
            ].joined(separator: "\n")
            return SupervisorExecutionProjectBootstrapSpec(
                goal: goal,
                doneDefinition: doneDefinition,
                nonGoals: nonGoals,
                approvedTechStack: approvedTechStack,
                milestones: [
                    SupervisorProjectSpecMilestone(
                        milestoneId: "m1-shell",
                        title: "跑通最小可玩的页面骨架",
                        status: .active
                    ),
                    SupervisorProjectSpecMilestone(
                        milestoneId: "m2-gameplay",
                        title: "补齐核心玩法闭环",
                        status: .planned
                    ),
                    SupervisorProjectSpecMilestone(
                        milestoneId: "m3-verify",
                        title: "完成自测和运行说明",
                        status: .planned
                    )
                ],
                requirements: [
                    doneDefinition,
                    "默认按离线单机版本推进",
                    "默认不接排行榜或账号体系"
                ],
                decisions: [
                    "默认先走网页版最小交付路径，优先尽快做出可玩的单机版本"
                ],
                currentState: currentState,
                nextStep: nextStep,
                jobGoal: "交付最小可运行的网页版贪食蛇游戏，并补运行说明",
                planId: planId,
                steps: [
                    SupervisorUpsertPlanStepPayload(
                        stepId: "step-001",
                        title: "锁定默认范围、交付边界和验收口径",
                        kind: SupervisorPlanStepKind.writeMemory.rawValue,
                        status: SupervisorPlanStepStatus.completed.rawValue,
                        skillId: nil,
                        currentOwner: "supervisor",
                        detail: alignmentDetail,
                        dependsOn: nil,
                        timeoutMs: nil,
                        maxRetries: nil,
                        failurePolicy: nil
                    ),
                    SupervisorUpsertPlanStepPayload(
                        stepId: "step-002",
                        title: "搭建最小可运行的游戏骨架",
                        kind: SupervisorPlanStepKind.launchRun.rawValue,
                        status: SupervisorPlanStepStatus.pending.rawValue,
                        skillId: nil,
                        currentOwner: "coder",
                        detail: shellDetail,
                        dependsOn: ["step-001"],
                        timeoutMs: nil,
                        maxRetries: 1,
                        failurePolicy: SupervisorPlanStepFailurePolicy.replan.rawValue
                    ),
                    SupervisorUpsertPlanStepPayload(
                        stepId: "step-003",
                        title: "实现核心玩法闭环",
                        kind: SupervisorPlanStepKind.launchRun.rawValue,
                        status: SupervisorPlanStepStatus.pending.rawValue,
                        skillId: nil,
                        currentOwner: "coder",
                        detail: gameplayDetail,
                        dependsOn: ["step-002"],
                        timeoutMs: nil,
                        maxRetries: 1,
                        failurePolicy: SupervisorPlanStepFailurePolicy.replan.rawValue
                    ),
                    SupervisorUpsertPlanStepPayload(
                        stepId: "step-004",
                        title: "完成自测、运行说明和交付收口",
                        kind: SupervisorPlanStepKind.writeMemory.rawValue,
                        status: SupervisorPlanStepStatus.pending.rawValue,
                        skillId: nil,
                        currentOwner: "coder",
                        detail: verifyDetail,
                        dependsOn: ["step-003"],
                        timeoutMs: nil,
                        maxRetries: 1,
                        failurePolicy: SupervisorPlanStepFailurePolicy.replan.rawValue
                    ),
                    SupervisorUpsertPlanStepPayload(
                        stepId: "step-005",
                        title: "向用户汇总结果并回写 project memory",
                        kind: SupervisorPlanStepKind.notifyUser.rawValue,
                        status: SupervisorPlanStepStatus.pending.rawValue,
                        skillId: nil,
                        currentOwner: "supervisor",
                        detail: summaryDetail,
                        dependsOn: ["step-004"],
                        timeoutMs: nil,
                        maxRetries: nil,
                        failurePolicy: nil
                    )
                ],
                statusDigest: "goal=\(goal); action=\(currentState); blocker=(无); next=\(nextStep)"
            )
        }

        let goal = intake.track == "网页版"
            ? "交付一个最小可运行的网页版本：\(project.displayName)"
            : "交付一个最小可运行的版本：\(project.displayName)"
        let doneDefinition: String
        let approvedTechStack: [String]
        switch intake.track {
        case "iOS 版":
            doneDefinition = "能在 iOS 目标环境上跑通核心主流程，并具备基础交互、最小验证和运行说明。"
            approvedTechStack = ["Swift", "SwiftUI"]
        case "macOS 桌面版":
            doneDefinition = "能在 macOS 目标环境上跑通核心主流程，并具备基础交互、最小验证和运行说明。"
            approvedTechStack = ["Swift", "SwiftUI"]
        case "终端版":
            doneDefinition = "能在终端本地直接运行，走通核心主流程，并附一段运行说明和最小验证。"
            approvedTechStack = ["Swift", "ArgumentParser"]
        default:
            doneDefinition = "能在默认目标平台上直接运行，走通核心主流程，并附一段运行说明和最小验证。"
            approvedTechStack = ["HTML", "CSS", "JavaScript"]
        }
        let currentState = "默认方案已锁定，待 Project AI 按第一版工单开始实现"
        let nextStep = "先搭建最小可运行骨架，再补齐核心主流程与验证"
        return SupervisorExecutionProjectBootstrapSpec(
            goal: goal,
            doneDefinition: doneDefinition,
            nonGoals: ["先不做重型扩展功能", "先不做超出 MVP 的复杂集成"],
            approvedTechStack: approvedTechStack,
            milestones: [
                SupervisorProjectSpecMilestone(
                    milestoneId: "m1-bootstrap",
                    title: "搭起最小可运行骨架",
                    status: .active
                ),
                SupervisorProjectSpecMilestone(
                    milestoneId: "m2-core-flow",
                    title: "补齐核心主流程",
                    status: .planned
                ),
                SupervisorProjectSpecMilestone(
                    milestoneId: "m3-verify",
                    title: "完成验证与交付收口",
                    status: .planned
                )
            ],
            requirements: [doneDefinition],
            decisions: ["默认先做最小可运行版本，避免一开始就铺太大范围"],
            currentState: currentState,
            nextStep: nextStep,
            jobGoal: goal,
            planId: planId,
            steps: [
                SupervisorUpsertPlanStepPayload(
                    stepId: "step-001",
                    title: "锁定默认方案与验收口径",
                    kind: SupervisorPlanStepKind.writeMemory.rawValue,
                    status: SupervisorPlanStepStatus.completed.rawValue,
                    skillId: nil,
                    currentOwner: "supervisor",
                    detail: "bootstrap_source=pending_execution_intake\ngoal=\(goal)\ntrack=\(intake.track)\ndone_definition=\(doneDefinition)",
                    dependsOn: nil,
                    timeoutMs: nil,
                    maxRetries: nil,
                    failurePolicy: nil
                ),
                SupervisorUpsertPlanStepPayload(
                    stepId: "step-002",
                    title: "搭建最小可运行骨架",
                    kind: SupervisorPlanStepKind.launchRun.rawValue,
                    status: SupervisorPlanStepStatus.pending.rawValue,
                    skillId: nil,
                    currentOwner: "coder",
                    detail: "owner=coder\nfocus=minimal runnable skeleton\nacceptance=core entry path can start",
                    dependsOn: ["step-001"],
                    timeoutMs: nil,
                    maxRetries: 1,
                    failurePolicy: SupervisorPlanStepFailurePolicy.replan.rawValue
                ),
                SupervisorUpsertPlanStepPayload(
                    stepId: "step-003",
                    title: "补齐核心主流程并完成验证",
                    kind: SupervisorPlanStepKind.writeMemory.rawValue,
                    status: SupervisorPlanStepStatus.pending.rawValue,
                    skillId: nil,
                    currentOwner: "coder",
                    detail: "owner=coder\nfocus=core flow + minimal verification + run notes",
                    dependsOn: ["step-002"],
                    timeoutMs: nil,
                    maxRetries: 1,
                    failurePolicy: SupervisorPlanStepFailurePolicy.replan.rawValue
                ),
                SupervisorUpsertPlanStepPayload(
                    stepId: "step-004",
                    title: "向用户汇总交付结果",
                    kind: SupervisorPlanStepKind.notifyUser.rawValue,
                    status: SupervisorPlanStepStatus.pending.rawValue,
                    skillId: nil,
                    currentOwner: "supervisor",
                    detail: "owner=supervisor\ninclude=what shipped, how to run, remaining gaps",
                    dependsOn: ["step-003"],
                    timeoutMs: nil,
                    maxRetries: nil,
                    failurePolicy: nil
                )
            ],
            statusDigest: "goal=\(goal); action=\(currentState); blocker=(无); next=\(nextStep)"
        )
    }
}
