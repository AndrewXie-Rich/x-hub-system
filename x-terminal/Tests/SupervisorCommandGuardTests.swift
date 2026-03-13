import Foundation
import Testing
@testable import XTerminal

@MainActor
@Suite(.serialized)
struct SupervisorCommandGuardTests {

    @Test
    func identityQuestionStripsHallucinatedActionTags() throws {
        let manager = SupervisorManager.makeForTesting()

        let rendered = manager.processSupervisorResponseForTesting(
            """
            我是 X-Terminal 里的 Supervisor。
            [CREATE_PROJECT]我的世界还原项目[/CREATE_PROJECT]
            [ASSIGN_MODEL]我的世界还原项目|开发者|openai/gpt-5.3-codex[/ASSIGN_MODEL]
            [CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"修复 browser runtime smoke","priority":"high"}[/CREATE_JOB]
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"job-1","step_id":"step-1","skill_id":"browser.open","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """,
            userMessage: "你是不是GPT模型"
        )

        #expect(rendered.contains("我是 X-Terminal 里的 Supervisor"))
        #expect(!rendered.contains("正在创建项目"))
        #expect(!rendered.contains("单项目分配标签解析失败"))
        #expect(!rendered.contains("[CREATE_PROJECT]"))
        #expect(!rendered.contains("[ASSIGN_MODEL]"))
        #expect(!rendered.contains("[CREATE_JOB]"))
        #expect(!rendered.contains("[CALL_SKILL]"))
        #expect(manager.messages.isEmpty)
    }

    @Test
    func supervisorSkillSummaryUsesHumanSummaryForSecretVaultBrowserFill() throws {
        let manager = SupervisorManager.makeForTesting()
        let toolCall = ToolCall(
            id: "skill-browser-secret-fill",
            tool: .deviceBrowserControl,
            args: [
                "action": .string("type"),
                "selector": .string("input[type=password]"),
                "secret_item_id": .string("sv_project_login")
            ]
        )

        let summary = manager.summarizedSupervisorSkillOutputForTesting(
            ToolExecutor.structuredOutput(
                summary: [
                    "tool": .string(ToolName.deviceBrowserControl.rawValue),
                    "ok": .bool(true),
                    "action": .string("type"),
                    "selector": .string("input[type=password]"),
                    "browser_runtime_driver_state": .string("secret_vault_applescript_fill"),
                ],
                body: "session_id=browser_session_1"
            ),
            ok: true,
            toolCall: toolCall
        )

        #expect(summary.contains("device.browser.control completed"))
        #expect(summary.contains("Secret Vault credential"))
        #expect(summary.contains("input[type=password]"))
    }

    @Test
    func executionIntakeDoesNotAutoCreateProjectFromHallucinatedTag() throws {
        let manager = SupervisorManager.makeForTesting()

        let rendered = manager.processSupervisorResponseForTesting(
            """
            我会先把这件事当成一个交付任务。
            [CREATE_PROJECT]贪食蛇游戏[/CREATE_PROJECT]
            [CREATE_JOB]{"project_ref":"","goal":"实现贪食蛇最小可运行版本","priority":"high"}[/CREATE_JOB]
            [CALL_SKILL]{"project_ref":"","job_id":"job-1","step_id":"step-1","skill_id":"coder.run","payload":{"task":"实现贪食蛇"}}[/CALL_SKILL]
            """,
            userMessage: "帮我做个贪食蛇游戏"
        )

        #expect(rendered.contains("我会先把这件事当成一个交付任务"))
        #expect(!rendered.contains("正在创建项目"))
        #expect(!rendered.contains("[CREATE_PROJECT]"))
        #expect(!rendered.contains("[CREATE_JOB]"))
        #expect(!rendered.contains("[CALL_SKILL]"))
        #expect(manager.messages.isEmpty)
    }

    @Test
    func explicitWorkflowRequestCreatesProjectScopedSupervisorJob() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-create-job")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let goal = "修复 browser runtime smoke 并重跑证据"
        let rendered = manager.processSupervisorResponseForTesting(
            """
            我会先把这个执行请求登记成受治理任务。
            [CREATE_JOB]{"project_ref":"","goal":"\(goal)","priority":"high","source":"user","current_owner":"supervisor"}[/CREATE_JOB]
            """,
            userMessage: "请创建任务，修复 browser runtime smoke 并重跑证据"
        )

        #expect(rendered.contains("我会先把这个执行请求登记成受治理任务。"))
        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 创建任务：\(goal)（priority=high）"))
        #expect(!rendered.contains("[CREATE_JOB]"))

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let snapshot = SupervisorProjectJobStore.load(for: ctx)
        #expect(snapshot.jobs.count == 1)

        let job = try #require(snapshot.jobs.first)
        #expect(job.projectId == project.projectId)
        #expect(job.goal == goal)
        #expect(job.priority == .high)
        #expect(job.status == .queued)
        #expect(job.source == .user)
        #expect(job.currentOwner == "supervisor")

        let task = try #require(manager.currentTask)
        #expect(task.id == job.jobId)
        #expect(task.projectId == job.projectId)
        #expect(task.title == goal)
        #expect(task.status == SupervisorJobStatus.queued.rawValue)

        let rawEntries = try readRawLogEntries(at: ctx.rawLogURL)
        let rawJob = try #require(rawEntries.last(where: { ($0["type"] as? String) == "supervisor_job" }))
        #expect(rawJob["action"] as? String == "create")
        #expect(rawJob["job_id"] as? String == job.jobId)
        #expect(rawJob["project_id"] as? String == project.projectId)
        #expect(rawJob["goal"] as? String == goal)
        #expect(rawJob["priority"] as? String == SupervisorJobPriority.high.rawValue)
        #expect(rawJob["source"] as? String == SupervisorJobSource.user.rawValue)
        #expect(rawJob["trigger_source"] as? String == "user_turn")
    }

    @Test
    func createJobAcceptsSanitizedHexProjectReferenceAlias() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-create-job-hex-alias")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let goal = "梳理项目结构并给出重构建议"
        let hexAlias = "hex:\(String(project.projectId.prefix(8)))"
        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            我会把这件事登记成一个受治理任务继续推进。
            [CREATE_JOB]{"project_ref":"\#(hexAlias)","goal":"\#(goal)","priority":"high","source":"user","current_owner":"supervisor"}[/CREATE_JOB]
            """#,
            userMessage: "给亮亮建一个任务：梳理项目结构并给出重构建议"
        )

        #expect(rendered.contains("我会把这件事登记成一个受治理任务继续推进。"))
        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 创建任务：\(goal)（priority=high）"))
        #expect(!rendered.contains("[CREATE_JOB]"))

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let snapshot = SupervisorProjectJobStore.load(for: ctx)
        #expect(snapshot.jobs.count == 1)

        let job = try #require(snapshot.jobs.first)
        #expect(job.projectId == project.projectId)
        #expect(job.goal == goal)
        #expect(job.priority == .high)
        #expect(job.status == .queued)
    }

    @Test
    func localMemoryFocusedProjectBriefPrefersExplicitlyMentionedProject() async throws {
        let manager = SupervisorManager.makeForTesting()
        let selectedRoot = try makeProjectRoot(named: "supervisor-memory-selected-project")
        let focusedRoot = try makeProjectRoot(named: "supervisor-memory-focused-project")
        defer { try? FileManager.default.removeItem(at: selectedRoot) }
        defer { try? FileManager.default.removeItem(at: focusedRoot) }

        var selectedProject = makeProjectEntry(root: selectedRoot, displayName: "Alpha Console")
        selectedProject.currentStateSummary = "selected-project-state"
        selectedProject.nextStepSummary = "selected-project-next"

        var focusedProject = makeProjectEntry(root: focusedRoot, displayName: "亮亮")
        focusedProject.currentStateSummary = "focused-project-state"
        focusedProject.nextStepSummary = "focused-project-next"
        focusedProject.blockerSummary = "focused-project-blocker"

        let focusedCtx = AXProjectContext(root: focusedRoot)
        AXRecentContextStore.appendUserMessage(
            ctx: focusedCtx,
            text: "请先审查项目记忆",
            createdAt: Date(timeIntervalSince1970: 1_773_600_000).timeIntervalSince1970
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: focusedCtx,
            text: "当前需要先梳理模块边界",
            createdAt: Date(timeIntervalSince1970: 1_773_600_001).timeIntervalSince1970
        )

        let appModel = AppModel()
        appModel.registry = registry(with: [selectedProject, focusedProject])
        appModel.selectedProjectId = selectedProject.projectId
        manager.setAppModel(appModel)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "审查亮亮项目的上下文记忆，给出最具体的执行方案"
        )

        #expect(localMemory.contains("[focused_project_execution_brief]"))
        #expect(localMemory.contains("focus_source: explicit_user_mention"))
        #expect(localMemory.contains("project: 亮亮 (\(focusedProject.projectId))"))
        #expect(localMemory.contains("current_state: focused-project-state"))
        #expect(localMemory.contains("next_step: focused-project-next"))
        #expect(localMemory.contains("blocker: focused-project-blocker"))
        #expect(localMemory.contains("recent_relevant_messages:"))
        #expect(localMemory.contains("当前需要先梳理模块边界"))
    }

    @Test
    func localMemoryFocusedProjectBriefIncludesWorkflowDetails() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-execution-brief")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        AXRecentContextStore.appendUserMessage(
            ctx: ctx,
            text: "先梳理模块边界",
            createdAt: Date(timeIntervalSince1970: 1_773_600_100).timeIntervalSince1970
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: ctx,
            text: "随后输出重构分层方案",
            createdAt: Date(timeIntervalSince1970: 1_773_600_101).timeIntervalSince1970
        )

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"亮亮","goal":"梳理项目结构并给出重构建议","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "给亮亮建一个任务：梳理项目结构并给出重构建议"
        )

        let projectCtx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: projectCtx).jobs.first)
        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"亮亮","job_id":"\#(job.jobId)","plan_id":"plan-liang-structure-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"整理现有模块图","kind":"write_memory","status":"running"},{"step_id":"step-002","title":"输出重构分层方案","kind":"write_memory","status":"pending"},{"step_id":"step-003","title":"确认历史阻塞项","kind":"ask_user","status":"blocked"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划，给亮亮补一版结构化计划"
        )
        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 写入计划：plan-liang-structure-v1"))

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "审查亮亮项目的上下文记忆，给出最具体的执行方案"
        )

        #expect(localMemory.contains("[focused_project_execution_brief]"))
        #expect(localMemory.contains("active_job_goal: 梳理项目结构并给出重构建议"))
        #expect(localMemory.contains("active_plan_id: plan-liang-structure-v1"))
        #expect(localMemory.contains("next_pending_steps:"))
        #expect(localMemory.contains("step-002"))
        #expect(localMemory.contains("attention_steps:"))
        #expect(localMemory.contains("step-001"))
        #expect(localMemory.contains("step-003"))
        #expect(localMemory.contains("recent_relevant_messages:"))
        #expect(localMemory.contains("先梳理模块边界"))
        #expect(localMemory.contains("随后输出重构分层方案"))
    }

    @Test
    func localMemoryFocusedProjectBriefIncludesReviewAnchors() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-review-anchor")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        let spec = SupervisorProjectSpecCapsuleBuilder.build(
            projectId: project.projectId,
            goal: "把 supervisor 的 review 机制做成高质量但保留自由度",
            mvpDefinition: "review 必须能防跑偏、看质量，并在需要时提出更好的路径",
            nonGoals: ["不要把 supervisor 做成僵硬 checklist agent"],
            approvedTechStack: ["SwiftUI", "Hub-governed memory"],
            milestoneMap: [
                SupervisorProjectSpecMilestone(
                    milestoneId: "m1",
                    title: "落协议与 prompt",
                    status: .active
                )
            ]
        )
        try SupervisorProjectSpecCapsuleStore.save(spec, for: ctx)

        let decision = SupervisorDecisionTrackBuilder.build(
            decisionId: "decision-review-style",
            projectId: project.projectId,
            category: .scopeFreeze,
            status: .approved,
            statement: "Supervisor review 必须保留自由度，但不能牺牲 goal alignment 和 evidence-based judgement.",
            source: "user_confirmed_protocol",
            reversible: true,
            approvalRequired: false,
            auditRef: "audit-review-style",
            createdAtMs: 1_773_700_000_000
        )
        _ = try SupervisorDecisionTrackStore.upsert(decision, for: ctx)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "审查亮亮项目的上下文记忆，给出最具体的执行方案"
        )

        #expect(localMemory.contains("[focused_project_execution_brief]"))
        #expect(localMemory.contains("done_definition: review 必须能防跑偏、看质量，并在需要时提出更好的路径"))
        #expect(localMemory.contains("constraints:"))
        #expect(localMemory.contains("non_goals: 不要把 supervisor 做成僵硬 checklist agent"))
        #expect(localMemory.contains("approved_decisions:"))
        #expect(localMemory.contains("scope_freeze=Supervisor review 必须保留自由度"))
        #expect(localMemory.contains("governance:"))
        #expect(localMemory.contains("latest_review_note:"))
        #expect(localMemory.contains("latest_review_note=(none)"))
        #expect(localMemory.contains("latest_guidance_injection:"))
        #expect(localMemory.contains("latest_guidance_injection=(none)"))
        #expect(localMemory.contains("pending_ack_guidance:"))
        #expect(localMemory.contains("pending_ack_guidance=(none)"))
        #expect(localMemory.contains("constraints=non_goals=不要把 supervisor 做成僵硬 checklist agent"))
        #expect(localMemory.contains("approved_decisions=scope_freeze=Supervisor review 必须保留自由度"))
    }

    @Test
    func captureSupervisorReviewNotePersistsAnchoredStrategicReview() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-review-note-capture")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        let spec = SupervisorProjectSpecCapsuleBuilder.build(
            projectId: project.projectId,
            goal: "让 supervisor review 既高质量又保留自由度",
            mvpDefinition: "review 时先锚定目标/约束，再基于证据判断，并且只在必要时 brainstorm 新路径",
            nonGoals: ["不要把 review 做成僵硬 checklist"],
            approvedTechStack: ["SwiftUI", "Hub memory"],
            milestoneMap: [
                SupervisorProjectSpecMilestone(
                    milestoneId: "m1",
                    title: "落 review note 主链",
                    status: .active
                )
            ]
        )
        try SupervisorProjectSpecCapsuleStore.save(spec, for: ctx)

        let decision = SupervisorDecisionTrackBuilder.build(
            decisionId: "decision-review-note-style",
            projectId: project.projectId,
            category: .scopeFreeze,
            status: .approved,
            statement: "如果当前路径证据充分且仍对齐目标，优先低 churn 继续推进；若发现更优路径，再做有理由的 replan。",
            source: "user_confirmed_protocol",
            reversible: true,
            approvalRequired: false,
            auditRef: "audit-review-note-style",
            createdAtMs: 1_773_710_000_000
        )
        _ = try SupervisorDecisionTrackStore.upsert(decision, for: ctx)

        manager.captureSupervisorReviewNoteForTesting(
            userMessage: "审查亮亮项目的上下文记忆，brainstorm 更好的执行方案，但不要跑偏",
            response: """
            当前路径基本成立，但有一条更稳的推进方式。
            1. 先冻结目标、done 定义和约束，避免 review 过程中 scope creep。
            2. 再把 focused brief 里的 approved decisions 和 constraints 提升为 review anchor。
            3. 最后再补轻量 brainstorm，而不是直接推翻现有路径。
            """,
            triggerSource: "user_turn"
        )

        let snapshot = SupervisorReviewNoteStore.load(for: ctx)
        let note = try #require(snapshot.notes.first)
        #expect(note.projectId == project.projectId)
        #expect(note.trigger == .manualRequest)
        #expect(note.reviewLevel == .r2Strategic)
        #expect(note.verdict == .betterPathFound)
        #expect(note.targetRole == .coder)
        #expect(note.deliveryMode == .replanRequest)
        #expect(note.ackRequired)
        #expect(note.anchorGoal == "让 supervisor review 既高质量又保留自由度")
        #expect(note.anchorDoneDefinition == "review 时先锚定目标/约束，再基于证据判断，并且只在必要时 brainstorm 新路径")
        #expect(note.anchorConstraints.contains(where: { $0.contains("non_goal=不要把 review 做成僵硬 checklist") }))
        #expect(note.recommendedActions.count >= 3)
        #expect(note.summary.contains("当前路径基本成立"))

        let guidanceSnapshot = SupervisorGuidanceInjectionStore.load(for: ctx)
        let guidance = try #require(guidanceSnapshot.items.first)
        #expect(guidance.reviewId == note.reviewId)
        #expect(guidance.projectId == project.projectId)
        #expect(guidance.targetRole == .coder)
        #expect(guidance.deliveryMode == .replanRequest)
        #expect(guidance.interventionMode == .replanNextSafePoint)
        #expect(guidance.safePointPolicy == .nextStepBoundary)
        #expect(guidance.ackStatus == .pending)
        #expect(guidance.ackRequired)
        #expect(guidance.guidanceText.contains("verdict=better_path_found"))
    }

    @Test
    func localMemoryFocusedProjectBriefIncludesLatestReviewNoteDigest() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-latest-review-note")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        let spec = SupervisorProjectSpecCapsuleBuilder.build(
            projectId: project.projectId,
            goal: "让 supervisor review note 进入 focused brief",
            mvpDefinition: "latest review note 要能被后续 supervisor/coder 直接消费",
            nonGoals: ["不要让 review note 只存在 raw log"],
            approvedTechStack: ["SwiftUI", "Hub memory"],
            milestoneMap: [
                SupervisorProjectSpecMilestone(
                    milestoneId: "m1",
                    title: "接入 latest review note",
                    status: .active
                )
            ]
        )
        try SupervisorProjectSpecCapsuleStore.save(spec, for: ctx)

        manager.captureSupervisorReviewNoteForTesting(
            userMessage: "审查亮亮项目的上下文记忆，给出具体执行方案，但不要跑偏",
            response: """
            当前路径成立，但有一条更稳的推进方式。
            1. 先把 latest review note 放进 focused brief。
            2. 再让 coder 默认读取最新 verdict 和 recommended actions。
            """,
            triggerSource: "user_turn"
        )

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "继续审查亮亮项目的上下文记忆，并输出下一步执行方案"
        )

        #expect(localMemory.contains("latest_review_note:"))
        #expect(localMemory.contains("trigger: manual_request"))
        #expect(localMemory.contains("verdict: better_path_found"))
        #expect(localMemory.contains("delivery: coder/replan_request ack_required=true"))
        #expect(localMemory.contains("recommended_actions: 先把 latest review note 放进 focused brief。 | 再让 coder 默认读取最新 verdict 和 recommended actions。"))
        #expect(localMemory.contains("latest_review_note=verdict=better_path_found level=r2_strategic delivery=replan_request ack_required=true"))
        #expect(localMemory.contains("latest_guidance_injection:"))
        #expect(localMemory.contains("intervention_mode: replan_next_safe_point"))
        #expect(localMemory.contains("safe_point_policy: next_step_boundary"))
        #expect(localMemory.contains("ack_status: pending"))
        #expect(localMemory.contains("pending_ack_guidance:"))
        #expect(localMemory.contains("pending_ack_guidance=ack_status=pending ack_required=true ack_note=(none) delivery=replan_request intervention=replan_next_safe_point safe_point=next_step_boundary"))
    }

    @Test
    func localMemoryFocusedProjectBriefIncludesGuidanceAckNoteDigest() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-guidance-ack-note")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-brief-ack-note-1",
                reviewId: "review-brief-ack-note-1",
                projectId: project.projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "改成更稳的 replan 路线。",
                ackStatus: .rejected,
                ackRequired: true,
                ackNote: "Need extra evidence before moving the migration boundary.",
                injectedAtMs: 1_773_384_100_000,
                ackUpdatedAtMs: 1_773_384_100_100,
                auditRef: "audit-guidance-brief-ack-note-1"
            ),
            for: ctx
        )

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "继续审查亮亮项目的上下文记忆，并输出下一步执行方案"
        )

        #expect(localMemory.contains("latest_guidance_injection:"))
        #expect(localMemory.contains("ack_note: Need extra evidence before moving the migration boundary."))
        #expect(localMemory.contains("latest_guidance_injection=ack_status=rejected ack_required=true ack_note=Need extra evidence before moving the migration boundary."))
    }

    @Test
    func explicitWorkflowRequestUpsertsPlanAndUpdatesJobState() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-upsert-plan")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"修复 browser runtime smoke 并重跑证据","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务，修复 browser runtime smoke 并重跑证据"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            我会把执行路径写成结构化计划。
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"检查 browser runtime 当前状态","kind":"call_skill","status":"pending","skill_id":"browser.runtime.inspect"},{"step_id":"step-002","title":"重跑 smoke 并回收证据","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划，补 browser runtime smoke 的执行步骤"
        )

        #expect(rendered.contains("我会把执行路径写成结构化计划。"))
        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 写入计划：plan-browser-smoke-v1（job=\(job.jobId), steps=2）"))
        #expect(!rendered.contains("[UPSERT_PLAN]"))

        let planSnapshot = SupervisorProjectPlanStore.load(for: ctx)
        #expect(planSnapshot.plans.count == 1)
        let plan = try #require(planSnapshot.plans.first)
        #expect(plan.planId == "plan-browser-smoke-v1")
        #expect(plan.jobId == job.jobId)
        #expect(plan.projectId == project.projectId)
        #expect(plan.status == .planning)
        #expect(plan.steps.count == 2)
        #expect(plan.steps[0].stepId == "step-001")
        #expect(plan.steps[0].kind == .callSkill)
        #expect(plan.steps[0].status == .pending)
        #expect(plan.steps[0].skillId == "browser.runtime.inspect")
        #expect(plan.steps[1].stepId == "step-002")
        #expect(plan.steps[1].skillId == "browser.runtime.smoke")

        let updatedJob = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        #expect(updatedJob.activePlanId == plan.planId)
        #expect(updatedJob.status == .planning)
        #expect(manager.currentTask?.id == job.jobId)
        #expect(manager.currentTask?.status == SupervisorJobStatus.planning.rawValue)

        let rawEntries = try readRawLogEntries(at: ctx.rawLogURL)
        let rawPlan = try #require(rawEntries.last(where: { ($0["type"] as? String) == "supervisor_plan" }))
        #expect(rawPlan["action"] as? String == "create")
        #expect(rawPlan["plan_id"] as? String == plan.planId)
        #expect(rawPlan["job_id"] as? String == job.jobId)
        #expect(rawPlan["step_count"] as? Int == 2)
        #expect(rawPlan["trigger_source"] as? String == "user_turn")

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续执行当前项目")
        #expect(localMemory.contains("[supervisor_workflow]"))
        #expect(localMemory.contains("plan-browser-smoke-v1"))
        #expect(localMemory.contains("browser.runtime.smoke"))
        #expect(localMemory.contains("step-001"))
    }

    @Test
    func explicitWorkflowRequestDispatchesLowRiskSkillAndWritesCompletion() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-success")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"导出 project snapshot","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-project-snapshot-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"读取当前 project snapshot","kind":"call_skill","status":"pending","skill_id":"project.snapshot"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"project.snapshot","payload":{}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 project snapshot 技能"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：project.snapshot"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let callSnapshot = SupervisorProjectSkillCallStore.load(for: ctx)
        let call = try #require(callSnapshot.calls.first)
        #expect(call.skillId == "project.snapshot")
        #expect(call.status == .completed)
        #expect(call.toolName == ToolName.project_snapshot.rawValue)
        let resultEvidenceRef = try #require(call.resultEvidenceRef)
        #expect(resultEvidenceRef.contains("local://supervisor_skill_results/"))

        let evidence = try #require(SupervisorSkillResultEvidenceStore.load(requestId: call.requestId, for: ctx))
        #expect(evidence.skillId == "project.snapshot")
        #expect(evidence.status == SupervisorSkillCallStatus.completed.rawValue)
        #expect(evidence.resultEvidenceRef == resultEvidenceRef)
        #expect(evidence.rawOutputChars > 0)
        #expect(!evidence.rawOutputPreview.isEmpty)
        #expect(evidence.rawOutputRef == "\(resultEvidenceRef)#raw_output")

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)

        let updatedJob = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        #expect(updatedJob.status == .completed)

        let rawEntries = try readRawLogEntries(at: ctx.rawLogURL)
        #expect(rawEntries.contains(where: {
            ($0["type"] as? String) == "supervisor_skill_call" && ($0["action"] as? String) == "dispatch"
        }))
        #expect(rawEntries.contains(where: {
            ($0["type"] as? String) == "supervisor_skill_call" && ($0["action"] as? String) == SupervisorSkillCallStatus.completed.rawValue
        }))
        #expect(rawEntries.contains(where: {
            ($0["type"] as? String) == "supervisor_skill_result"
                && ($0["status"] as? String) == SupervisorSkillCallStatus.completed.rawValue
                && ($0["result_evidence_ref"] as? String) == resultEvidenceRef
        }))
        #expect(rawEntries.contains(where: {
            ($0["type"] as? String) == "tool" && ($0["action"] as? String) == ToolName.project_snapshot.rawValue
        }))

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续执行当前项目")
        #expect(localMemory.contains("active_skill_result_ref: \(resultEvidenceRef)"))

    }

    @Test
    func highRiskSkillStopsAtAwaitingAuthorizationAndCanBeCanceled() throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-awaiting-auth")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"运行 browser smoke","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-v2","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        #expect(rendered.contains("当前需要本地审批后才能继续"))

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "browser.runtime.smoke")
        #expect(call.status == .awaitingAuthorization)
        #expect(call.denyCode == "local_approval_required")
        #expect(manager.pendingSupervisorSkillApprovals.count == 1)
        #expect(manager.pendingSupervisorSkillApprovals.first?.requestId == call.requestId)

        let waitingPlan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(waitingPlan.steps[0].status == .awaitingAuthorization)
        #expect(waitingPlan.status == .awaitingAuthorization)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .awaitingAuthorization)

        let canceledRendered = manager.processSupervisorResponseForTesting(
            #"""
            [CANCEL_SKILL]{"project_ref":"我的世界还原项目","request_id":"\#(call.requestId)","reason":"用户取消"}[/CANCEL_SKILL]
            """#,
            userMessage: "请取消这个技能调用"
        )

        #expect(canceledRendered.contains("✅ 已取消项目 \(project.displayName) 的技能调用：browser.runtime.smoke"))

        let canceledCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(canceledCall.status == .canceled)
        #expect(canceledCall.resultSummary.contains("用户取消"))

        let canceledPlan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(canceledPlan.steps[0].status == .canceled)
        #expect(canceledPlan.status == .canceled)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .canceled)

        let rawEntries = try readRawLogEntries(at: ctx.rawLogURL)
        #expect(rawEntries.contains(where: {
            ($0["type"] as? String) == "supervisor_skill_call" && ($0["action"] as? String) == "awaiting_authorization"
        }))
        #expect(rawEntries.contains(where: {
            ($0["type"] as? String) == "supervisor_skill_call" && ($0["action"] as? String) == "cancel"
        }))
    }

    @Test
    func approvedLocalSupervisorSkillApprovalResumesAwaitingHighRiskSkill() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-local-approval-resume")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .deviceBrowserControl)
            #expect(call.args["action"]?.stringValue == "open_url")
            #expect(call.args["url"]?.stringValue == "https://example.com")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "browser smoke completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"运行 browser smoke","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            .settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_500_000)
            )
        try AXProjectStore.saveConfig(config, for: ctx)

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeSupervisorTrustedAutomationPermissionReadiness()
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-local-approval-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        let approval = try #require(manager.pendingSupervisorSkillApprovals.first)
        #expect(approval.skillId == "browser.runtime.smoke")
        #expect(approval.toolName == ToolName.deviceBrowserControl.rawValue)

        manager.approvePendingSupervisorSkillApproval(approval)
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .completed)
        #expect(call.toolName == ToolName.deviceBrowserControl.rawValue)
        #expect(call.resultSummary.contains("browser smoke completed"))
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
    }

    @Test
    func governedAutoApprovalLetsSupervisorExecuteHighRiskLocalSkillWithoutPendingApproval() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-auto-approved")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .deviceBrowserControl)
            #expect(call.args["action"]?.stringValue == "open_url")
            #expect(call.args["url"]?.stringValue == "https://example.com")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "browser smoke completed via governed auto approval"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"运行 browser smoke","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            .settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_500_200)
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)
        try AXProjectStore.saveConfig(config, for: ctx)
        let reloadedConfig = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(reloadedConfig.governedAutoApproveLocalToolCalls == true)
        #expect(
            xtProjectGovernedAutoApprovalConfigured(
                projectRoot: root,
                config: reloadedConfig
            )
        )

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeSupervisorTrustedAutomationPermissionReadiness()
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-auto-approved-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        #expect(!rendered.contains("当前需要本地审批后才能继续"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .completed)
        #expect(call.toolName == ToolName.deviceBrowserControl.rawValue)
        #expect(call.resultSummary.contains("browser smoke completed via governed auto approval"))
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
    }

    @Test
    func governedAutoApprovalLetsSupervisorExecuteRepoWriteFileSkill() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-repo-write-file")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"写入受治理文件","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            .settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_800_300)
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)
        try AXProjectStore.saveConfig(config, for: ctx)

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-repo-write-file-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"写入受治理文件","kind":"call_skill","status":"pending","skill_id":"repo.write.file"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"repo.write.file","payload":{"path":"Sources/Generated/hello.txt","content":"hello from supervisor"}}[/CALL_SKILL]
            """#,
            userMessage: "请写入文件"
        )

        #expect(!rendered.contains("当前需要本地审批后才能继续"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "repo.write.file")
        #expect(call.status == .completed)
        #expect(call.toolName == ToolName.write_file.rawValue)
        #expect(call.resultSummary.contains("write_file completed: Sources/Generated/hello.txt"))

        let target = root.appendingPathComponent("Sources/Generated/hello.txt")
        let text = try String(contentsOf: target, encoding: .utf8)
        #expect(text == "hello from supervisor")

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
    }

    @Test
    func governedAutoApprovalLetsSupervisorExecuteRepoTestRunSkill() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-repo-test-run")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .run_command)
            #expect(call.args["command"]?.stringValue == "swift test --filter SupervisorCommandGuardTests")
            #expect(call.args["timeout_sec"]?.stringValue == "120")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "exit: 0\nPASS"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"运行受治理测试命令","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            .settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_800_350)
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)
        try AXProjectStore.saveConfig(config, for: ctx)

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-repo-test-run-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行受治理测试命令","kind":"call_skill","status":"pending","skill_id":"repo.test.run"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"repo.test.run","payload":{"command":"swift test --filter SupervisorCommandGuardTests","timeout_sec":120}}[/CALL_SKILL]
            """#,
            userMessage: "请执行测试"
        )

        #expect(!rendered.contains("当前需要本地审批后才能继续"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "repo.test.run")
        #expect(call.status == .completed)
        #expect(call.toolName == ToolName.run_command.rawValue)
        #expect(call.resultSummary.contains("run_command completed: swift test --filter SupervisorCommandGuardTests"))
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
    }

    @Test
    func governedAutoApprovalLetsSupervisorExecuteRepoBuildRunSkill() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-repo-build-run")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .run_command)
            #expect(call.args["command"]?.stringValue == "swift build")
            #expect(call.args["timeout_sec"]?.stringValue == "180")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "exit: 0\nBUILD SUCCEEDED"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"运行受治理构建命令","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            .settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_800_360)
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)
        try AXProjectStore.saveConfig(config, for: ctx)

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-repo-build-run-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行受治理构建命令","kind":"call_skill","status":"pending","skill_id":"repo.build.run"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"repo.build.run","payload":{"command":"swift build","timeout_sec":180}}[/CALL_SKILL]
            """#,
            userMessage: "请执行构建"
        )

        #expect(!rendered.contains("当前需要本地审批后才能继续"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "repo.build.run")
        #expect(call.status == .completed)
        #expect(call.toolName == ToolName.run_command.rawValue)
        #expect(call.resultSummary.contains("run_command completed: swift build"))
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
    }

    @Test
    func governedAutoApprovalLetsSupervisorExecuteRepoGitApplySkill() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-repo-git-apply")
        defer { try? FileManager.default.removeItem(at: root) }

        let patch = """
        diff --git a/README.md b/README.md
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -old
        +new
        """ + "\n"

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .git_apply)
            #expect(call.args["patch"]?.stringValue == patch)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "exit: 0\npatch applied"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"应用受治理补丁","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            .settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_800_370)
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)
        try AXProjectStore.saveConfig(config, for: ctx)

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-repo-git-apply-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"应用受治理补丁","kind":"call_skill","status":"pending","skill_id":"repo.git.apply"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"repo.git.apply","payload":{"patch":"\#(jsonEscapedString(patch))"}}[/CALL_SKILL]
            """#,
            userMessage: "请应用补丁"
        )

        #expect(!rendered.contains("当前需要本地审批后才能继续"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "repo.git.apply")
        #expect(call.status == .completed)
        #expect(call.toolName == ToolName.git_apply.rawValue)
        #expect(call.resultSummary.contains("git_apply completed: patch_chars=\(patch.count)"))
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
    }

    @Test
    func repoTestRunRejectsUnsafeCommandOutsideGovernedAllowlist() throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-repo-test-run-blocked")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"运行不安全测试命令","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-repo-test-run-blocked-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行不安全测试命令","kind":"call_skill","status":"pending","skill_id":"repo.test.run"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"repo.test.run","payload":{"command":"rm -rf . && swift test"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行测试"
        )

        #expect(rendered.contains("payload.command_not_allowed"))

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "repo.test.run")
        #expect(call.status == .blocked)
        #expect(call.denyCode == "payload.command_not_allowed")
        #expect(call.resultSummary.contains("governed allowlist"))
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .blocked)
        #expect(plan.status == .blocked)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .blocked)
    }

    @Test
    func deniedLocalSupervisorSkillApprovalBlocksAwaitingHighRiskSkill() throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-local-approval-deny")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"运行 browser smoke","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-local-deny-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        let approval = try #require(manager.pendingSupervisorSkillApprovals.first)
        manager.denyPendingSupervisorSkillApproval(approval)

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .blocked)
        #expect(call.denyCode == "local_approval_denied")
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .blocked)
        #expect(plan.status == .blocked)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .blocked)
    }

    @Test
    func webSearchSkillMapsToGovernedNetworkToolAndAppearsInWorkflowMemory() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-web-search")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"检索最新浏览器安全修复线索","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-web-search-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索浏览器安全修复线索","kind":"call_skill","status":"pending","skill_id":"web.search"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"web.search","payload":{"query":"browser runtime smoke fix","max_results":3}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 web search 技能"
        )

        #expect(rendered.contains("正在向 Hub 申请 web.fetch 授权"))

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "web.search")
        #expect(call.toolName == ToolName.web_search.rawValue)
        #expect(call.status == .awaitingAuthorization)
        #expect(call.denyCode == "grant_required")

        let waitingPlan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(waitingPlan.steps[0].status == .awaitingAuthorization)
        #expect(waitingPlan.status == .awaitingAuthorization)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .awaitingAuthorization)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续执行当前项目")
        #expect(localMemory.contains("[supervisor_workflow]"))
        #expect(localMemory.contains("active_skill_id: web.search"))
        #expect(localMemory.contains("active_skill_tool_name: web_search"))
        #expect(localMemory.contains("active_skill_status: awaiting_authorization"))
    }

    @Test
    func findSkillsSkillMapsToCatalogToolAndCompletes() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-find-skills")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .skills_search)
            #expect(call.args["query"]?.stringValue == "browser")
            #expect(call.args["source_filter"]?.stringValue == "builtin:catalog")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: ToolExecutor.structuredOutput(
                    summary: [
                        "tool": .string(call.tool.rawValue),
                        "ok": .bool(true),
                        "results_count": .number(1),
                    ],
                    body: "1. Agent Browser [agent-browser]"
                )
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"搜索适合浏览器自动化的 skill","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-find-skills-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索浏览器自动化 skill","kind":"call_skill","status":"pending","skill_id":"find-skills"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"find-skills","payload":{"query":"browser","source_filter":"builtin:catalog"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 find-skills 技能"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：find-skills"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "find-skills")
        #expect(call.toolName == ToolName.skills_search.rawValue)
        #expect(call.status == .completed)

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
    }

    @Test
    func manifestDrivenGovernedDispatchRoutesUnknownWrapperSkill() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-generic-wrapper-skill")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try appendManifestDrivenSkillFixture(
            hubBaseDir: fixture.hubBaseDir,
            projectID: project.projectId,
            skillID: "catalog.lookup.wrapper",
            packageSHA256: "2020202020202020202020202020202020202020202020202020202020202020",
            canonicalManifestSHA256: "2121212121212121212121212121212121212121212121212121212121212121",
            manifest: [
                "skill_id": "catalog.lookup.wrapper",
                "description": "Wrapper over governed skill search.",
                "capabilities_required": ["skills.search"],
                "risk_level": "low",
                "requires_grant": false,
                "side_effect_class": "read_only",
                "timeout_ms": 10000,
                "max_retries": 1,
                "governed_dispatch": [
                    "tool": ToolName.skills_search.rawValue,
                    "passthrough_args": ["query", "source_filter", "limit"],
                    "arg_aliases": [
                        "limit": ["max_results"],
                    ],
                    "required_any": [["query"]],
                ],
            ]
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .skills_search)
            #expect(call.args["query"]?.stringValue == "browser automation")
            #expect(call.args["source_filter"]?.stringValue == "builtin:catalog")
            #expect(call.args["limit"]?.stringValue == "4")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: ToolExecutor.structuredOutput(
                    summary: [
                        "tool": .string(call.tool.rawValue),
                        "ok": .bool(true),
                        "results_count": .number(1),
                    ],
                    body: "1. Agent Browser [agent-browser]"
                )
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"搜索受治理 skill wrapper","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-generic-wrapper-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"查找 browser skill","kind":"call_skill","status":"pending","skill_id":"catalog.lookup.wrapper"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"catalog.lookup.wrapper","payload":{"query":"browser automation","source_filter":"builtin:catalog","max_results":4}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 wrapper skill"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：catalog.lookup.wrapper"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "catalog.lookup.wrapper")
        #expect(call.toolName == ToolName.skills_search.rawValue)
        #expect(call.status == .completed)
    }

    @Test
    func manifestDrivenGovernedDispatchVariantRoutesUnknownWrapperSkillReadAction() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-generic-variant-wrapper-skill")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try appendManifestDrivenSkillFixture(
            hubBaseDir: fixture.hubBaseDir,
            projectID: project.projectId,
            skillID: "browser.reader.wrapper",
            packageSHA256: "3030303030303030303030303030303030303030303030303030303030303030",
            canonicalManifestSHA256: "3131313131313131313131313131313131313131313131313131313131313131",
            manifest: [
                "skill_id": "browser.reader.wrapper",
                "description": "Wrapper over governed browser read.",
                "capabilities_required": ["browser.read", "web.fetch"],
                "risk_level": "high",
                "requires_grant": true,
                "side_effect_class": "external_side_effect",
                "timeout_ms": 15000,
                "max_retries": 1,
                "governed_dispatch_variants": [
                    [
                        "actions": ["read", "fetch"],
                        "action_arg": "",
                        "action_map": [:],
                        "dispatch": [
                            "tool": ToolName.browser_read.rawValue,
                            "passthrough_args": ["url", "grant_id", "max_bytes"],
                            "required_any": [["url"]],
                        ],
                    ],
                ],
            ]
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .browser_read)
            #expect(call.args["url"]?.stringValue == "https://example.com/docs")
            #expect(call.args["grant_id"]?.stringValue == "grant-read-1")
            #expect(call.args["max_bytes"]?.stringValue == "8192")
            #expect(call.args["action"] == nil)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "browser reader wrapper completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"读取文档页面","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-generic-variant-wrapper-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"读取 governed 页面","kind":"call_skill","status":"pending","skill_id":"browser.reader.wrapper"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.reader.wrapper","payload":{"action":"read","url":"https://example.com/docs","grant_id":"grant-read-1","max_bytes":8192}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser reader wrapper"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：browser.reader.wrapper"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "browser.reader.wrapper")
        #expect(call.toolName == ToolName.browser_read.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("browser reader wrapper completed"))
    }

    @Test
    func selfImprovingAgentMapsToRetrospectiveMemorySnapshotAndCompletes() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-self-improving-agent")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .memory_snapshot)
            #expect(call.args["mode"]?.stringValue == XTMemoryUseMode.supervisorOrchestration.rawValue)
            #expect(call.args["focus"]?.stringValue == "grant reliability")
            #expect(call.args["limit"]?.stringValue == "3")
            let retrospective: Bool
            if case .bool(let value)? = call.args["retrospective"] {
                retrospective = value
            } else {
                retrospective = false
            }
            #expect(retrospective)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: ToolExecutor.structuredOutput(
                    summary: [
                        "tool": .string(call.tool.rawValue),
                        "ok": .bool(true),
                        "analysis_profile": .string("self_improvement"),
                        "focus": .string("grant reliability"),
                        "recommendation_count": .number(2),
                    ],
                    body: "Self Improvement Report\nRecommendations:\n1. Preflight web.fetch\n2. Tighten skill contracts"
                )
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"复盘最近 grant 卡点","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-self-improving-agent-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"生成监督复盘报告","kind":"call_skill","status":"pending","skill_id":"self-improving-agent"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"self-improving-agent","payload":{"focus":"grant reliability","limit":3}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 self-improving-agent 技能"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：self-improving-agent"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "self-improving-agent")
        #expect(call.toolName == ToolName.memory_snapshot.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("2 recommendations"))

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
    }

    @Test
    func agentBrowserSkillMapsToGovernedBrowserRuntimeAndCompletes() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-agent-browser-open")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .deviceBrowserControl)
            #expect(call.args["action"]?.stringValue == "open_url")
            #expect(call.args["url"]?.stringValue == "https://example.com/login")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "agent browser open completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"打开受治理浏览器登录页","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            .settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_501_000)
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)
        try AXProjectStore.saveConfig(config, for: ctx)

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeSupervisorTrustedAutomationPermissionReadiness()
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-agent-browser-open-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"打开受治理浏览器登录页","kind":"call_skill","status":"pending","skill_id":"agent-browser"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"agent-browser","payload":{"action":"open","url":"https://example.com/login"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 agent-browser 技能"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：agent-browser"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "agent-browser")
        #expect(call.toolName == ToolName.deviceBrowserControl.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("agent browser open completed"))

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
    }

    @Test
    func agentBrowserExtractWaitsForHubGrantAndResumes() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorHubGrantPreflight: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-agent-browser-extract")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorNetworkAccessRequestOverrideForTesting { _, _, _ in
            HubIPCClient.NetworkAccessResult(
                state: .queued,
                source: "test",
                reasonCode: "queued",
                remainingSeconds: nil,
                grantRequestId: "grant-agent-browser-1"
            )
        }
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .deviceBrowserControl)
            #expect(call.args["action"]?.stringValue == "extract")
            #expect(call.args["url"]?.stringValue == "https://example.com/dashboard")
            #expect(call.args["grant_id"]?.stringValue == "grant-agent-browser-1")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "agent browser extract completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"提取控制台页面关键信息","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            .settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_501_200)
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)
        try AXProjectStore.saveConfig(config, for: ctx)

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeSupervisorTrustedAutomationPermissionReadiness()
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-agent-browser-extract-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"提取页面关键信息","kind":"call_skill","status":"pending","skill_id":"agent-browser"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"agent-browser","payload":{"action":"extract","url":"https://example.com/dashboard"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 agent-browser extract"
        )

        #expect(rendered.contains("正在向 Hub 申请 web.fetch 授权"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let queuedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(queuedCall.skillId == "agent-browser")
        #expect(queuedCall.toolName == ToolName.deviceBrowserControl.rawValue)
        #expect(queuedCall.status == .awaitingAuthorization)
        #expect(queuedCall.requiredCapability == "web.fetch")
        #expect(queuedCall.grantRequestId == "grant-agent-browser-1")

        let pendingGrant = SupervisorManager.SupervisorPendingGrant(
            id: "grant:grant-agent-browser-1",
            dedupeKey: "grant:grant-agent-browser-1",
            grantRequestId: "grant-agent-browser-1",
            requestId: "request-agent-browser-1",
            projectId: project.projectId,
            projectName: project.displayName,
            capability: "web.fetch",
            modelId: "",
            reason: "supervisor skill agent-browser",
            requestedTtlSec: 900,
            requestedTokenCap: 0,
            createdAt: Date().timeIntervalSince1970,
            actionURL: nil,
            priorityRank: 1,
            priorityReason: "涉及联网提取能力，需先确认访问范围。",
            nextAction: "批准后自动恢复 skill"
        )
        await manager.completePendingHubGrantActionForTesting(
            grant: pendingGrant,
            approve: true,
            result: HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .approved,
                source: "test",
                grantRequestId: "grant-agent-browser-1",
                grantId: "grant-agent-browser-1",
                expiresAtMs: (Date().timeIntervalSince1970 + 900) * 1000.0,
                reasonCode: nil
            )
        )

        await manager.waitForSupervisorSkillDispatchForTesting()

        let resumedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(resumedCall.status == .completed)
        #expect(resumedCall.grantRequestId == "grant-agent-browser-1")
        #expect(resumedCall.grantId == "grant-agent-browser-1")
        #expect(resumedCall.toolName == ToolName.deviceBrowserControl.rawValue)
        #expect(resumedCall.resultSummary.contains("agent browser extract completed"))

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
    }

    @Test
    func summarizeSkillWithURLWaitsForHubGrant() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorHubGrantPreflight: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-summarize-url")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"总结浏览器 grant 方案","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-summarize-url-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"总结 grant 方案页面","kind":"call_skill","status":"pending","skill_id":"summarize"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"summarize","payload":{"url":"https://example.com/grants","focus":"grant policy"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 summarize 技能"
        )

        #expect(rendered.contains("正在向 Hub 申请 web.fetch 授权"))

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "summarize")
        #expect(call.toolName == ToolName.summarize.rawValue)
        #expect(call.status == .awaitingAuthorization)
        #expect(call.requiredCapability == "web.fetch")

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .awaitingAuthorization)
        #expect(plan.status == .awaitingAuthorization)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .awaitingAuthorization)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续执行当前项目")
        #expect(localMemory.contains("active_skill_id: summarize"))
        #expect(localMemory.contains("active_skill_tool_name: summarize"))
        #expect(localMemory.contains("active_skill_status: awaiting_authorization"))
    }

    @Test
    func officialCodeReviewSkillStatusVariantMapsToGitStatus() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-code-review-status")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try appendManifestDrivenSkillFixture(
            hubBaseDir: fixture.hubBaseDir,
            projectID: project.projectId,
            skillID: "code-review",
            packageSHA256: "2020202020202020202020202020202020202020202020202020202020202020",
            canonicalManifestSHA256: "2121212121212121212121212121212121212121212121212121212121212121",
            manifest: try loadOfficialAgentSkillManifestFixture(skillID: "code-review")
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .git_status)
            #expect(call.args.isEmpty)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "code review status completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"查看仓库当前改动","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-code-review-status-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"查看仓库状态","kind":"call_skill","status":"pending","skill_id":"code-review"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"code-review","payload":{"action":"status"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 code-review status"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：code-review"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "code-review")
        #expect(call.toolName == ToolName.git_status.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("code review status completed"))
    }

    @Test
    func officialCodeReviewSkillStagedDiffVariantMapsToGitDiffCached() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-code-review-staged-diff")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try appendManifestDrivenSkillFixture(
            hubBaseDir: fixture.hubBaseDir,
            projectID: project.projectId,
            skillID: "code-review",
            packageSHA256: "2222222022222220222222202222222022222220222222202222222022222220",
            canonicalManifestSHA256: "2323232023232320232323202323232023232320232323202323232023232320",
            manifest: try loadOfficialAgentSkillManifestFixture(skillID: "code-review")
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .git_diff)
            let cached: Bool
            if case .bool(let value)? = call.args["cached"] {
                cached = value
            } else {
                cached = false
            }
            #expect(cached)
            #expect(call.args["action"] == nil)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "code review staged diff completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"查看 staged diff","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-code-review-staged-diff-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"查看 staged diff","kind":"call_skill","status":"pending","skill_id":"code-review"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"code-review","payload":{"action":"staged_diff"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 code-review staged_diff"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：code-review"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "code-review")
        #expect(call.toolName == ToolName.git_diff.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("code review staged diff completed"))
    }

    @Test
    func officialCodeReviewSkillReadVariantMapsToReadFile() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-code-review-read")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try appendManifestDrivenSkillFixture(
            hubBaseDir: fixture.hubBaseDir,
            projectID: project.projectId,
            skillID: "code-review",
            packageSHA256: "2424242024242420242424202424242024242420242424202424242024242420",
            canonicalManifestSHA256: "2525252025252520252525202525252025252520252525202525252025252520",
            manifest: try loadOfficialAgentSkillManifestFixture(skillID: "code-review")
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .read_file)
            #expect(call.args["path"]?.stringValue == "Sources/App.swift")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "code review read completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"读取关键文件","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-code-review-read-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"读取关键文件","kind":"call_skill","status":"pending","skill_id":"code-review"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"code-review","payload":{"action":"read","file":"Sources/App.swift"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 code-review read"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：code-review"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "code-review")
        #expect(call.toolName == ToolName.read_file.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("code review read completed"))
    }

    @Test
    func officialTavilyWebsearchSkillMapsToGovernedWebSearch() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-tavily-websearch")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try appendManifestDrivenSkillFixture(
            hubBaseDir: fixture.hubBaseDir,
            projectID: project.projectId,
            skillID: "tavily-websearch",
            packageSHA256: "2626262026262620262626202626262026262620262626202626262026262620",
            canonicalManifestSHA256: "2727272027272720272727202727272027272720272727202727272027272720",
            manifest: try loadOfficialAgentSkillManifestFixture(skillID: "tavily-websearch")
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .web_search)
            #expect(call.args["query"]?.stringValue == "latest swift macros")
            #expect(call.args["grant_id"]?.stringValue == "grant-search-1")
            #expect(call.args["max_results"]?.stringValue == "5")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "tavily websearch completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"联网搜索最新 Swift 宏资料","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-tavily-websearch-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"联网搜索最新 Swift 宏资料","kind":"call_skill","status":"pending","skill_id":"tavily-websearch"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"tavily-websearch","payload":{"q":"latest swift macros","grant_id":"grant-search-1","limit":5}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 tavily-websearch"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：tavily-websearch"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "tavily-websearch")
        #expect(call.toolName == ToolName.web_search.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("tavily websearch completed"))
    }

    @Test
    func officialSkillCreatorListVariantMapsToListDir() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-creator-list")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try appendManifestDrivenSkillFixture(
            hubBaseDir: fixture.hubBaseDir,
            projectID: project.projectId,
            skillID: "skill-creator",
            packageSHA256: "2828282028282820282828202828282028282820282828202828282028282820",
            canonicalManifestSHA256: "2929292029292920292929202929292029292920292929202929292029292920",
            manifest: try loadOfficialAgentSkillManifestFixture(skillID: "skill-creator")
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .list_dir)
            #expect(call.args["path"]?.stringValue == "official-agent-skills")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "skill creator list completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"查看当前 skill 目录","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-skill-creator-list-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"查看 skill 目录","kind":"call_skill","status":"pending","skill_id":"skill-creator"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"skill-creator","payload":{"action":"list","dir":"official-agent-skills"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 skill-creator list"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：skill-creator"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "skill-creator")
        #expect(call.toolName == ToolName.list_dir.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("skill creator list completed"))
    }

    @Test
    func officialSkillCreatorWriteVariantMapsToWriteFile() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-creator-write")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try appendManifestDrivenSkillFixture(
            hubBaseDir: fixture.hubBaseDir,
            projectID: project.projectId,
            skillID: "skill-creator",
            packageSHA256: "3030302030303020303030203030302030303020303030203030302030303020",
            canonicalManifestSHA256: "3131312031313120313131203131312031313120313131203131312031313120",
            manifest: try loadOfficialAgentSkillManifestFixture(skillID: "skill-creator")
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .write_file)
            #expect(call.args["path"]?.stringValue == "official-agent-skills/demo-skill/SKILL.md")
            #expect(call.args["content"]?.stringValue == "# Demo Skill")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "skill creator write completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"写入 skill 源文件","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            .settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_800_500)
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)
        try AXProjectStore.saveConfig(config, for: ctx)

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-skill-creator-write-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"写入 skill 源文件","kind":"call_skill","status":"pending","skill_id":"skill-creator"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"skill-creator","payload":{"action":"write","path":"official-agent-skills/demo-skill/SKILL.md","text":"# Demo Skill"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 skill-creator write"
        )

        #expect(!rendered.contains("当前需要本地审批后才能继续"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "skill-creator")
        #expect(call.toolName == ToolName.write_file.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("skill creator write completed"))
    }

    @Test
    func officialAgentBackupCreateVariantMapsToGovernedRunCommand() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-agent-backup-create")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try appendManifestDrivenSkillFixture(
            hubBaseDir: fixture.hubBaseDir,
            projectID: project.projectId,
            skillID: "agent-backup",
            packageSHA256: "3232322032323220323232203232322032323220323232203232322032323220",
            canonicalManifestSHA256: "3333332033333320333333203333332033333320333333203333332033333320",
            manifest: try loadOfficialAgentSkillManifestFixture(skillID: "agent-backup")
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .run_command)
            let command = call.args["command"]?.stringValue ?? ""
            #expect(command.contains("mkdir -p .ax-backups"))
            #expect(command.contains("/usr/bin/tar -czf"))
            #expect(command.contains("--exclude .git"))
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "agent backup create completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"创建本地项目备份","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            .settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_800_700)
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)
        try AXProjectStore.saveConfig(config, for: ctx)

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-agent-backup-create-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"创建本地项目备份","kind":"call_skill","status":"pending","skill_id":"agent-backup"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"agent-backup","payload":{"action":"create"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 agent-backup create"
        )

        #expect(!rendered.contains("当前需要本地审批后才能继续"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "agent-backup")
        #expect(call.toolName == ToolName.run_command.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("agent backup create completed"))
    }

    @Test
    func officialSkillVetterManifestVariantMapsToReadFile() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-vetter-manifest")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try appendManifestDrivenSkillFixture(
            hubBaseDir: fixture.hubBaseDir,
            projectID: project.projectId,
            skillID: "skill-vetter",
            packageSHA256: "3434342034343420343434203434342034343420343434203434342034343420",
            canonicalManifestSHA256: "3535352035353520353535203535352035353520353535203535352035353520",
            manifest: try loadOfficialAgentSkillManifestFixture(skillID: "skill-vetter")
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .read_file)
            #expect(call.args["path"]?.stringValue == "official-agent-skills/agent-browser/skill.json")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "skill vetter manifest read completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"读取 skill manifest","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-skill-vetter-manifest-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"读取目标 skill manifest","kind":"call_skill","status":"pending","skill_id":"skill-vetter"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"skill-vetter","payload":{"action":"manifest","manifest_path":"official-agent-skills/agent-browser/skill.json"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 skill-vetter manifest"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：skill-vetter"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "skill-vetter")
        #expect(call.toolName == ToolName.read_file.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("skill vetter manifest read completed"))
    }

    @Test
    func officialSkillVetterExecScanVariantMapsToSearch() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-vetter-scan-exec")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try appendManifestDrivenSkillFixture(
            hubBaseDir: fixture.hubBaseDir,
            projectID: project.projectId,
            skillID: "skill-vetter",
            packageSHA256: "3636362036363620363636203636362036363620363636203636362036363620",
            canonicalManifestSHA256: "3737372037373720373737203737372037373720373737203737372037373720",
            manifest: try loadOfficialAgentSkillManifestFixture(skillID: "skill-vetter")
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .search)
            #expect(call.args["path"]?.stringValue == "official-agent-skills")
            let pattern = call.args["pattern"]?.stringValue ?? ""
            #expect(pattern.contains("child_process"))
            #expect(pattern.contains("subprocess"))
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "skill vetter scan exec completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"扫描 skill 执行风险","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-skill-vetter-scan-exec-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"扫描命令执行风险模式","kind":"call_skill","status":"pending","skill_id":"skill-vetter"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"skill-vetter","payload":{"action":"scan_exec","dir":"official-agent-skills","glob":"**/*.{js,ts,py,swift,md,json}"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 skill-vetter scan_exec"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：skill-vetter"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "skill-vetter")
        #expect(call.toolName == ToolName.search.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("skill vetter scan exec completed"))
    }

    @Test
    func officialSkillVetterReviewRecordVariantMapsToAgentImportRecord() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-vetter-review-record")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try appendManifestDrivenSkillFixture(
            hubBaseDir: fixture.hubBaseDir,
            projectID: project.projectId,
            skillID: "skill-vetter",
            packageSHA256: "3838382038383820383838203838382038383820383838203838382038383820",
            canonicalManifestSHA256: "3939392039393920393939203939392039393920393939203939392039393920",
            manifest: try loadOfficialAgentSkillManifestFixture(skillID: "skill-vetter")
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .agentImportRecord)
            #expect(call.args["staging_id"]?.stringValue == "stage-123")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "skill vetter review record completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"读取 Hub 导入审计记录","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-skill-vetter-review-record-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"读取 Hub 导入审计记录","kind":"call_skill","status":"pending","skill_id":"skill-vetter"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"skill-vetter","payload":{"action":"review_record","staging_id":"stage-123"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 skill-vetter review_record"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：skill-vetter"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "skill-vetter")
        #expect(call.toolName == ToolName.agentImportRecord.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("skill vetter review record completed"))
    }

    @Test
    func officialSkillVetterReviewRecordVariantPassesSelectorAndSkillScope() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-vetter-review-selector")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try appendManifestDrivenSkillFixture(
            hubBaseDir: fixture.hubBaseDir,
            projectID: project.projectId,
            skillID: "skill-vetter",
            packageSHA256: "4138382038383820383838203838382038383820383838203838382038383820",
            canonicalManifestSHA256: "4239392039393920393939203939392039393920393939203939392039393920",
            manifest: try loadOfficialAgentSkillManifestFixture(skillID: "skill-vetter")
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .agentImportRecord)
            #expect(call.args["selector"]?.stringValue == "latest_for_skill")
            #expect(call.args["skill_id"]?.stringValue == "agent-browser")
            #expect(call.args["project_id"]?.stringValue == project.projectId)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "skill vetter review latest record completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"读取最新技能导入审计记录","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-skill-vetter-review-selector-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"读取最新技能导入审计记录","kind":"call_skill","status":"pending","skill_id":"skill-vetter"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"skill-vetter","payload":{"action":"review_record","selector":"latest_for_skill","skill_id":"agent-browser","project_id":"\#(project.projectId)"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 skill-vetter review_record latest_for_skill"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：skill-vetter"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "skill-vetter")
        #expect(call.toolName == ToolName.agentImportRecord.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("skill vetter review latest record completed"))
    }

    @Test
    func approvedHubGrantResumesAwaitingSupervisorNetworkSkill() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorHubGrantPreflight: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-web-search-grant-resume")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorNetworkAccessRequestOverrideForTesting { _, _, _ in
            HubIPCClient.NetworkAccessResult(
                state: .queued,
                source: "test",
                reasonCode: "queued",
                remainingSeconds: nil,
                grantRequestId: "grant-web-search-1"
            )
        }
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .web_search)
            #expect(call.args["grant_id"]?.stringValue == "grant-web-search-1")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: ToolExecutor.structuredOutput(
                    summary: [
                        "tool": .string(call.tool.rawValue),
                        "ok": .bool(true),
                        "grant_id": .string(call.args["grant_id"]?.stringValue ?? "")
                    ],
                    body: "web search completed"
                )
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"搜索 browser runtime 修复方案","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-web-search-resume-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索 browser runtime 修复方案","kind":"call_skill","status":"pending","skill_id":"web.search"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"web.search","payload":{"query":"browser runtime smoke fix","max_results":3}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 web search 技能"
        )

        await manager.waitForSupervisorSkillDispatchForTesting()

        let queuedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(queuedCall.status == .awaitingAuthorization)
        #expect(queuedCall.grantRequestId == "grant-web-search-1")
        #expect(queuedCall.requiredCapability == "web.fetch")

        let pendingGrant = SupervisorManager.SupervisorPendingGrant(
            id: "grant:grant-web-search-1",
            dedupeKey: "grant:grant-web-search-1",
            grantRequestId: "grant-web-search-1",
            requestId: "request-web-search-1",
            projectId: project.projectId,
            projectName: project.displayName,
            capability: "web.fetch",
            modelId: "",
            reason: "supervisor skill web.search",
            requestedTtlSec: 900,
            requestedTokenCap: 0,
            createdAt: Date().timeIntervalSince1970,
            actionURL: nil,
            priorityRank: 1,
            priorityReason: "涉及联网能力，需先确认来源与访问范围。",
            nextAction: "批准后自动恢复 skill"
        )
        await manager.completePendingHubGrantActionForTesting(
            grant: pendingGrant,
            approve: true,
            result: HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .approved,
                source: "test",
                grantRequestId: "grant-web-search-1",
                grantId: "grant-web-search-1",
                expiresAtMs: (Date().timeIntervalSince1970 + 900) * 1000.0,
                reasonCode: nil
            )
        )

        await manager.waitForSupervisorSkillDispatchForTesting()

        let resumedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(resumedCall.status == .completed)
        #expect(resumedCall.grantRequestId == "grant-web-search-1")
        #expect(resumedCall.grantId == "grant-web-search-1")
        #expect(resumedCall.toolName == ToolName.web_search.rawValue)

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
    }

    @Test
    func deniedHubGrantBlocksAwaitingSupervisorNetworkSkill() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorHubGrantPreflight: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-web-search-grant-deny")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorNetworkAccessRequestOverrideForTesting { _, _, _ in
            HubIPCClient.NetworkAccessResult(
                state: .queued,
                source: "test",
                reasonCode: "queued",
                remainingSeconds: nil,
                grantRequestId: "grant-web-search-deny-1"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"搜索 browser runtime 修复方案","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-web-search-deny-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索 browser runtime 修复方案","kind":"call_skill","status":"pending","skill_id":"web.search"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"web.search","payload":{"query":"browser runtime smoke fix","max_results":3}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 web search 技能"
        )

        await manager.waitForSupervisorSkillDispatchForTesting()

        let pendingGrant = SupervisorManager.SupervisorPendingGrant(
            id: "grant:grant-web-search-deny-1",
            dedupeKey: "grant:grant-web-search-deny-1",
            grantRequestId: "grant-web-search-deny-1",
            requestId: "request-web-search-deny-1",
            projectId: project.projectId,
            projectName: project.displayName,
            capability: "web.fetch",
            modelId: "",
            reason: "supervisor skill web.search",
            requestedTtlSec: 900,
            requestedTokenCap: 0,
            createdAt: Date().timeIntervalSince1970,
            actionURL: nil,
            priorityRank: 1,
            priorityReason: "涉及联网能力，需先确认来源与访问范围。",
            nextAction: "拒绝后必须阻断 skill"
        )
        await manager.completePendingHubGrantActionForTesting(
            grant: pendingGrant,
            approve: false,
            result: HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .denied,
                source: "test",
                grantRequestId: "grant-web-search-deny-1",
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "denied"
            )
        )

        let blockedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(blockedCall.status == .blocked)
        #expect(blockedCall.denyCode == "grant_denied")
        #expect(blockedCall.grantRequestId == "grant-web-search-deny-1")

        let blockedPlan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(blockedPlan.steps[0].status == .blocked)
        #expect(blockedPlan.status == .blocked)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .blocked)
    }

    @Test
    func skillCallbackAutoFollowUpRunsSupervisorTurn() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-skill-callback-event-loop")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "skill_callback")
            #expect(userMessage.contains("trigger=skill_callback"))
            #expect(userMessage.contains("status=completed"))
            #expect(userMessage.contains("next_pending_steps:"))
            #expect(userMessage.contains("step-002"))
            return #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"处理 skill callback 后的下一步","priority":"normal","source":"skill_callback","current_owner":"supervisor"}[/CREATE_JOB]"#
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"导出 project snapshot","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-project-snapshot-event-loop-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"读取当前 project snapshot","kind":"call_skill","status":"pending","skill_id":"project.snapshot"},{"step_id":"step-002","title":"写入 follow-up 摘要","kind":"write_memory","status":"pending"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"project.snapshot","payload":{}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 project snapshot 技能"
        )

        await manager.waitForSupervisorSkillDispatchForTesting()
        await manager.waitForSupervisorEventLoopForTesting()

        let jobs = SupervisorProjectJobStore.load(for: ctx).jobs
        #expect(jobs.count == 2)
        let followUp = try #require(jobs.first(where: { $0.goal == "处理 skill callback 后的下一步" }))
        #expect(followUp.source == .skillCallback)
        #expect(followUp.currentOwner == "supervisor")
    }

    @Test
    func grantResolutionAutoFollowUpRunsSupervisorTurn() async throws {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorHubGrantPreflight: true,
            enableSupervisorEventLoopAutoFollowUp: true
        )
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-grant-resolution-event-loop")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorNetworkAccessRequestOverrideForTesting { _, _, _ in
            HubIPCClient.NetworkAccessResult(
                state: .queued,
                source: "test",
                reasonCode: "queued",
                remainingSeconds: nil,
                grantRequestId: "grant-web-search-event-loop"
            )
        }
        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "grant_resolution")
            #expect(userMessage.contains("trigger=grant_resolution"))
            #expect(userMessage.contains("reason_code=grant_denied"))
            #expect(userMessage.contains("attention_steps:"))
            #expect(userMessage.contains("step-001"))
            return #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"处理 grant resolution 后的下一步","priority":"high","source":"grant_resolution","current_owner":"supervisor"}[/CREATE_JOB]"#
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"搜索 browser runtime 修复方案","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-web-search-event-loop-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索 browser runtime 修复方案","kind":"call_skill","status":"pending","skill_id":"web.search"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"web.search","payload":{"query":"browser runtime smoke fix","max_results":3}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 web search 技能"
        )

        await manager.waitForSupervisorSkillDispatchForTesting()

        let pendingGrant = SupervisorManager.SupervisorPendingGrant(
            id: "grant:grant-web-search-event-loop",
            dedupeKey: "grant:grant-web-search-event-loop",
            grantRequestId: "grant-web-search-event-loop",
            requestId: "request-web-search-event-loop",
            projectId: project.projectId,
            projectName: project.displayName,
            capability: "web.fetch",
            modelId: "",
            reason: "supervisor skill web.search",
            requestedTtlSec: 900,
            requestedTokenCap: 0,
            createdAt: Date().timeIntervalSince1970,
            actionURL: nil,
            priorityRank: 1,
            priorityReason: "涉及联网能力，需先确认来源与访问范围。",
            nextAction: "拒绝后必须阻断 skill"
        )
        await manager.completePendingHubGrantActionForTesting(
            grant: pendingGrant,
            approve: false,
            result: HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .denied,
                source: "test",
                grantRequestId: "grant-web-search-event-loop",
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "grant_denied"
            )
        )

        await manager.waitForSupervisorEventLoopForTesting()

        let jobs = SupervisorProjectJobStore.load(for: ctx).jobs
        #expect(jobs.count == 2)
        let followUp = try #require(jobs.first(where: { $0.goal == "处理 grant resolution 后的下一步" }))
        #expect(followUp.source == .grantResolution)
        #expect(followUp.priority == .high)
    }

    @Test
    func approvalResolutionAutoFollowUpRunsSupervisorTurn() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-approval-resolution-event-loop")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "approval_resolution")
            #expect(userMessage.contains("trigger=approval_resolution"))
            #expect(userMessage.contains("reason_code=local_approval_denied"))
            #expect(userMessage.contains("attention_steps:"))
            #expect(userMessage.contains("step-001"))
            return #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"处理 approval resolution 后的下一步","priority":"high","source":"approval_resolution","current_owner":"supervisor"}[/CREATE_JOB]"#
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"运行 browser smoke","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-approval-event-loop-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        let approval = try #require(manager.pendingSupervisorSkillApprovals.first)
        manager.denyPendingSupervisorSkillApproval(approval)
        await manager.waitForSupervisorEventLoopForTesting()

        let jobs = SupervisorProjectJobStore.load(for: ctx).jobs
        #expect(jobs.count == 2)
        let followUp = try #require(jobs.first(where: { $0.goal == "处理 approval resolution 后的下一步" }))
        #expect(followUp.source == .approvalResolution)
        #expect(followUp.priority == .high)
    }

    @Test
    func guidanceAckRejectedAutoFollowUpRunsSupervisorTurn() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        let root = try makeProjectRoot(named: "supervisor-guidance-ack-event-loop")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "guidance_ack")
            #expect(userMessage.contains("trigger=guidance_ack"))
            #expect(userMessage.contains("ack_status=rejected"))
            #expect(userMessage.contains("ack_note=Conflicts with the approved migration boundary."))
            #expect(userMessage.contains("attention_steps:"))
            #expect(userMessage.contains("step-001"))
            return #"[CREATE_JOB]{"project_ref":"亮亮","goal":"处理 guidance ack follow-up","priority":"high","current_owner":"supervisor"}[/CREATE_JOB]"#
        }

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"亮亮","goal":"推进 review guidance 闭环","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"亮亮","job_id":"\#(job.jobId)","plan_id":"plan-guidance-ack-loop-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"消化 supervisor guidance","kind":"write_memory","status":"running"},{"step_id":"step-002","title":"按 guidance 调整计划","kind":"write_memory","status":"pending"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rejected = SupervisorGuidanceInjectionBuilder.build(
            injectionId: "guidance-ack-rejected-loop-1",
            reviewId: "review-ack-rejected-loop-1",
            projectId: project.projectId,
            targetRole: .coder,
            deliveryMode: .replanRequest,
            interventionMode: .replanNextSafePoint,
            safePointPolicy: .nextStepBoundary,
            guidanceText: "改成更稳的 replan 路线。",
            ackStatus: .rejected,
            ackRequired: true,
            ackNote: "Conflicts with the approved migration boundary.",
            injectedAtMs: 1_773_385_000_000,
            ackUpdatedAtMs: 1_773_385_000_100,
            auditRef: "audit-guidance-ack-rejected-loop-1"
        )
        try SupervisorGuidanceInjectionStore.upsert(rejected, for: ctx)

        manager.handleEvent(.supervisorGuidanceAck(rejected))
        await manager.waitForSupervisorEventLoopForTesting()

        let jobs = SupervisorProjectJobStore.load(for: ctx).jobs
        #expect(jobs.count == 2)
        let followUp = try #require(jobs.first(where: { $0.goal == "处理 guidance ack follow-up" }))
        #expect(followUp.priority == .high)

        let rawEntries = try readRawLogEntries(at: ctx.rawLogURL)
        let rawJob = try #require(rawEntries.last(where: {
            ($0["type"] as? String) == "supervisor_job" &&
            ($0["goal"] as? String) == "处理 guidance ack follow-up"
        }))
        #expect(rawJob["trigger_source"] as? String == "guidance_ack")
    }

    @Test
    func guidanceAckAcceptedDoesNotRunSupervisorTurn() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        let root = try makeProjectRoot(named: "supervisor-guidance-ack-accepted")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        manager.setSupervisorEventLoopResponseOverrideForTesting { _, _ in
            #"[CREATE_JOB]{"project_ref":"亮亮","goal":"unexpected guidance ack follow-up","priority":"high","current_owner":"supervisor"}[/CREATE_JOB]"#
        }

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"亮亮","goal":"推进 review guidance 闭环","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let accepted = SupervisorGuidanceInjectionBuilder.build(
            injectionId: "guidance-ack-accepted-loop-1",
            reviewId: "review-ack-accepted-loop-1",
            projectId: project.projectId,
            targetRole: .coder,
            deliveryMode: .priorityInsert,
            interventionMode: .suggestNextSafePoint,
            safePointPolicy: .nextToolBoundary,
            guidanceText: "先读 diff 再继续。",
            ackStatus: .accepted,
            ackRequired: true,
            ackNote: "Applying at next tool boundary.",
            injectedAtMs: 1_773_386_000_000,
            ackUpdatedAtMs: 1_773_386_000_100,
            auditRef: "audit-guidance-ack-accepted-loop-1"
        )
        try SupervisorGuidanceInjectionStore.upsert(accepted, for: ctx)

        manager.handleEvent(.supervisorGuidanceAck(accepted))
        await manager.waitForSupervisorEventLoopForTesting()

        let jobs = SupervisorProjectJobStore.load(for: ctx).jobs
        #expect(jobs.count == 1)
        #expect(!jobs.contains(where: { $0.goal == "unexpected guidance ack follow-up" }))
    }

    @Test
    func naturalBriefReplyUsesFocusedProjectStatusAndNextStep() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-brief")
        defer { try? FileManager.default.removeItem(at: root) }

        var project = makeProjectEntry(root: root, displayName: "亮亮")
        project.currentStateSummary = "自动流程正在等待 staging 验证结果"
        project.blockerSummary = "staging 回执还没回来"
        project.nextStepSummary = "确认 staging 结果后推进 release 决策"

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "grant-brief-1",
                    dedupeKey: "grant-brief-1",
                    grantRequestId: "grant-brief-1",
                    requestId: "req-brief-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    capability: "web.fetch",
                    modelId: "",
                    reason: "need fetch approval",
                    requestedTtlSec: 900,
                    requestedTokenCap: 0,
                    createdAt: Date().timeIntervalSince1970,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "network",
                    nextAction: "approve"
                )
            ]
        )

        let rendered = try #require(
            manager.directSupervisorReplyIfApplicableForTesting("简单说下亮亮现在怎么样，卡在哪，下一步怎么走")
        )

        #expect(rendered.contains("我来简短说一下《亮亮》"))
        #expect(rendered.contains("现在状态：阻塞中。"))
        #expect(rendered.contains("当前卡点：staging 回执还没回来。"))
        #expect(rendered.contains("还有 1 个待授权项卡在路上。"))
        #expect(rendered.contains("我建议下一步先确认 staging 结果后推进 release 决策。"))
    }

    @Test
    func naturalLanguageGuidanceAckAcceptsFocusedPendingGuidance() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-guidance-ack")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-natural-ack-1",
                reviewId: "review-natural-ack-1",
                projectId: project.projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "先把 release 风险和 staging 证据对齐，再决定是否推进。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_386_100_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-natural-ack-1"
            ),
            for: ctx
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("这个建议可以，就按这个做")
        )

        #expect(rendered.contains("继续推进"))
        let updated = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(updated.injectionId == "guidance-natural-ack-1")
        #expect(updated.ackStatus == .accepted)
        #expect(updated.ackNote.contains("这个建议可以，就按这个做"))
    }

    @Test
    func naturalLanguageGuidanceAckDefersFocusedPendingGuidanceFromColloquialPhrase() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-guidance-defer")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-natural-defer-1",
                reviewId: "review-natural-defer-1",
                projectId: project.projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "先把发版窗口和监控噪音拆开，再决定是否继续推进。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_386_200_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-natural-defer-1"
            ),
            for: ctx
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("这个方案先缓一缓，晚点再说")
        )

        #expect(rendered.contains("标成暂缓"))
        let updated = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(updated.injectionId == "guidance-natural-defer-1")
        #expect(updated.ackStatus == .deferred)
        #expect(updated.ackNote.contains("这个方案先缓一缓，晚点再说"))
    }

    @Test
    func naturalLanguageGuidanceAckRejectsFocusedPendingGuidanceFromColloquialPhrase() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-guidance-reject")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-natural-reject-1",
                reviewId: "review-natural-reject-1",
                projectId: project.projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "先按现在的迁移边界推进，然后再补证据。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_386_300_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-natural-reject-1"
            ),
            for: ctx
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("这个路子不对，换条路重新想方案")
        )

        #expect(rendered.contains("标成拒绝"))
        let updated = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(updated.injectionId == "guidance-natural-reject-1")
        #expect(updated.ackStatus == .rejected)
        #expect(updated.ackNote.contains("这个路子不对，换条路重新想方案"))
    }

    @Test
    func naturalLanguageGuidanceAckAcceptsContextualEllipsisAfterRecentGuidanceReply() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-guidance-context-accept")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.messages = [
            SupervisorMessage(
                id: "assistant-guidance-context-1",
                role: .assistant,
                content: "当前有一条待确认 guidance：先把 release 风险和 staging 证据对齐，再决定是否推进。",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        ]

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-natural-context-accept-1",
                reviewId: "review-natural-context-accept-1",
                projectId: project.projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "先把 release 风险和 staging 证据对齐，再决定是否推进。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_386_350_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-natural-context-accept-1"
            ),
            for: ctx
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("可以")
        )

        #expect(rendered.contains("继续推进"))
        let updated = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(updated.ackStatus == .accepted)
        #expect(updated.ackNote == "可以")
    }

    @Test
    func naturalLanguageGuidanceAckDefersContextualEllipsisAfterRecentGuidanceReply() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-guidance-context-defer")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.messages = [
            SupervisorMessage(
                id: "assistant-guidance-context-2",
                role: .assistant,
                content: "这条 guidance 需要你确认一下：先把发版窗口和监控噪音拆开，再决定是否继续推进。",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        ]

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-natural-context-defer-1",
                reviewId: "review-natural-context-defer-1",
                projectId: project.projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "先把发版窗口和监控噪音拆开，再决定是否继续推进。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_386_360_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-natural-context-defer-1"
            ),
            for: ctx
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("先缓一缓")
        )

        #expect(rendered.contains("标成暂缓"))
        let updated = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(updated.ackStatus == .deferred)
        #expect(updated.ackNote == "先缓一缓")
    }

    @Test
    func naturalLanguageGrantApprovalStartsHubGrantAction() async throws {
        actor ApprovalCapture {
            private(set) var grantIDs: [String] = []

            func record(_ grantID: String) {
                grantIDs.append(grantID)
            }

            func count() -> Int {
                grantIDs.count
            }
        }

        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-grant-approve")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let capture = ApprovalCapture()
        manager.installPendingHubGrantApproveOverrideForTesting { grantRequestId, _, _, _, _ in
            await capture.record(grantRequestId)
            return HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .approved,
                source: "test",
                grantRequestId: grantRequestId,
                grantId: "grant-live-1",
                expiresAtMs: nil,
                reasonCode: nil
            )
        }
        manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "grant-natural-1",
                    dedupeKey: "grant-natural-1",
                    grantRequestId: "grant-natural-1",
                    requestId: "req-natural-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    capability: "web.fetch",
                    modelId: "",
                    reason: "need web access",
                    requestedTtlSec: 900,
                    requestedTokenCap: 0,
                    createdAt: Date().timeIntervalSince1970,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "network",
                    nextAction: "approve"
                )
            ]
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("批准这个授权")
        )

        #expect(rendered.contains("开始处理《亮亮》这笔联网访问（web_fetch） Hub 授权"))
        for _ in 0..<40 {
            if await capture.count() == 1 {
                break
            }
            await Task.yield()
        }
        #expect(await capture.count() == 1)
    }

    @Test
    func naturalLanguageGrantApprovalUsesRecentGrantContextForEllipsis() async throws {
        actor ApprovalCapture {
            private(set) var grantIDs: [String] = []

            func record(_ grantID: String) {
                grantIDs.append(grantID)
            }

            func count() -> Int {
                grantIDs.count
            }
        }

        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-grant-context-approve")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.messages = [
            SupervisorMessage(
                id: "system-grant-context-1",
                role: .system,
                content: "当前有一笔待授权的 Hub grant：亮亮 / 联网访问（web_fetch）。",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        ]

        let capture = ApprovalCapture()
        manager.installPendingHubGrantApproveOverrideForTesting { grantRequestId, _, _, _, _ in
            await capture.record(grantRequestId)
            return HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .approved,
                source: "test",
                grantRequestId: grantRequestId,
                grantId: "grant-live-context-1",
                expiresAtMs: nil,
                reasonCode: nil
            )
        }
        manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "grant-natural-context-1",
                    dedupeKey: "grant-natural-context-1",
                    grantRequestId: "grant-natural-context-1",
                    requestId: "req-natural-context-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    capability: "web.fetch",
                    modelId: "",
                    reason: "need web access",
                    requestedTtlSec: 900,
                    requestedTokenCap: 0,
                    createdAt: Date().timeIntervalSince1970,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "network",
                    nextAction: "approve"
                )
            ]
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("批了吧")
        )

        #expect(rendered.contains("开始处理《亮亮》这笔联网访问（web_fetch） Hub 授权"))
        for _ in 0..<40 {
            if await capture.count() == 1 {
                break
            }
            await Task.yield()
        }
        #expect(await capture.count() == 1)
    }

    @Test
    func naturalLanguageGrantDenialUsesRecentGrantContextForEllipsis() async throws {
        actor DenialCapture {
            private(set) var grantIDs: [String] = []

            func record(_ grantID: String) {
                grantIDs.append(grantID)
            }

            func count() -> Int {
                grantIDs.count
            }
        }

        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-grant-context-deny")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.messages = [
            SupervisorMessage(
                id: "system-grant-context-2",
                role: .system,
                content: "当前有一笔待授权的 Hub grant：亮亮 / 联网访问（web_fetch）。",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        ]

        let capture = DenialCapture()
        manager.installPendingHubGrantDenyOverrideForTesting { grantRequestId, _, _ in
            await capture.record(grantRequestId)
            return HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .denied,
                source: "test",
                grantRequestId: grantRequestId,
                grantId: "grant-live-context-2",
                expiresAtMs: nil,
                reasonCode: nil
            )
        }
        manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "grant-natural-context-2",
                    dedupeKey: "grant-natural-context-2",
                    grantRequestId: "grant-natural-context-2",
                    requestId: "req-natural-context-2",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    capability: "web.fetch",
                    modelId: "",
                    reason: "need web access",
                    requestedTtlSec: 900,
                    requestedTokenCap: 0,
                    createdAt: Date().timeIntervalSince1970,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "network",
                    nextAction: "approve"
                )
            ]
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("先别批")
        )

        #expect(rendered.contains("先拦下《亮亮》这笔联网访问（web_fetch） Hub 授权"))
        for _ in 0..<40 {
            if await capture.count() == 1 {
                break
            }
            await Task.yield()
        }
        #expect(await capture.count() == 1)
    }

    @Test
    func naturalLanguageGrantApprovalAcceptsDemonstrativeColloquialPhrase() async throws {
        actor ApprovalCapture {
            private(set) var grantIDs: [String] = []

            func record(_ grantID: String) {
                grantIDs.append(grantID)
            }

            func count() -> Int {
                grantIDs.count
            }
        }

        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-grant-approve-demonstrative")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let capture = ApprovalCapture()
        manager.installPendingHubGrantApproveOverrideForTesting { grantRequestId, _, _, _, _ in
            await capture.record(grantRequestId)
            return HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .approved,
                source: "test",
                grantRequestId: grantRequestId,
                grantId: "grant-live-2",
                expiresAtMs: nil,
                reasonCode: nil
            )
        }
        manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "grant-natural-2",
                    dedupeKey: "grant-natural-2",
                    grantRequestId: "grant-natural-2",
                    requestId: "req-natural-2",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    capability: "web.fetch",
                    modelId: "",
                    reason: "need web access",
                    requestedTtlSec: 900,
                    requestedTokenCap: 0,
                    createdAt: Date().timeIntervalSince1970,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "network",
                    nextAction: "approve"
                )
            ]
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("这个你直接批了吧")
        )

        #expect(rendered.contains("开始处理《亮亮》这笔联网访问（web_fetch） Hub 授权"))
        for _ in 0..<40 {
            if await capture.count() == 1 {
                break
            }
            await Task.yield()
        }
        #expect(await capture.count() == 1)
    }

    @Test
    func naturalLanguageGrantDenialAcceptsColloquialPhrase() async throws {
        actor DenialCapture {
            private(set) var grantIDs: [String] = []

            func record(_ grantID: String) {
                grantIDs.append(grantID)
            }

            func count() -> Int {
                grantIDs.count
            }
        }

        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-grant-deny")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let capture = DenialCapture()
        manager.installPendingHubGrantDenyOverrideForTesting { grantRequestId, _, _ in
            await capture.record(grantRequestId)
            return HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .denied,
                source: "test",
                grantRequestId: grantRequestId,
                grantId: "grant-live-3",
                expiresAtMs: nil,
                reasonCode: nil
            )
        }
        manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "grant-natural-3",
                    dedupeKey: "grant-natural-3",
                    grantRequestId: "grant-natural-3",
                    requestId: "req-natural-3",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    capability: "web.fetch",
                    modelId: "",
                    reason: "need web access",
                    requestedTtlSec: 900,
                    requestedTokenCap: 0,
                    createdAt: Date().timeIntervalSince1970,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "network",
                    nextAction: "approve"
                )
            ]
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("这个联网权限先别批，先拦下")
        )

        #expect(rendered.contains("先拦下《亮亮》这笔联网访问（web_fetch） Hub 授权"))
        for _ in 0..<40 {
            if await capture.count() == 1 {
                break
            }
            await Task.yield()
        }
        #expect(await capture.count() == 1)
    }

    @Test
    func continueIntentBootstrapsFocusedProjectWorkflowFromConcreteMemory() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-continue-bootstrap")
        defer { try? FileManager.default.removeItem(at: root) }

        var project = makeProjectEntry(root: root, displayName: "亮亮")
        project.currentStateSummary = "模块边界已初步摸清，但结构整理还没落盘"
        project.nextStepSummary = "梳理项目结构并给出重构建议"
        project.blockerSummary = "缺一版明确的分层切割方案"

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("继续推进亮亮项目")
        )

        #expect(rendered.contains("把下一步起成一个受治理 workflow"))
        #expect(rendered.contains("任务目标：梳理项目结构并给出重构建议"))
        #expect(rendered.contains("1. 审查项目上下文记忆并确认当前事实（completed）"))
        #expect(rendered.contains("2. 梳理项目结构并给出重构建议（pending）"))

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        #expect(jobSnapshot.jobs.count == 1)

        let job = try #require(jobSnapshot.jobs.first)
        #expect(job.projectId == project.projectId)
        #expect(job.goal == "梳理项目结构并给出重构建议")
        #expect(job.priority == .high)
        #expect(job.source == .supervisor)
        #expect(job.status == .running)
        #expect(manager.currentTask?.id == job.jobId)

        let planSnapshot = SupervisorProjectPlanStore.load(for: ctx)
        #expect(planSnapshot.plans.count == 1)

        let plan = try #require(planSnapshot.plans.first)
        #expect(plan.jobId == job.jobId)
        #expect(plan.projectId == project.projectId)
        #expect(plan.status == .active)
        #expect(plan.steps.count == 3)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.steps[1].status == .pending)
        #expect(plan.steps[1].title == "梳理项目结构并给出重构建议")
    }

    @Test
    func continueIntentDoesNotDuplicateActiveWorkflowAndStillAllowsGovernedPlanUpdate() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-continue-existing-workflow")
        defer { try? FileManager.default.removeItem(at: root) }

        var project = makeProjectEntry(root: root, displayName: "亮亮")
        project.nextStepSummary = "梳理项目结构并给出重构建议"

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"亮亮","goal":"梳理项目结构并给出重构建议","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "给亮亮建一个任务：梳理项目结构并给出重构建议"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let existingJob = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)

        #expect(manager.directSupervisorActionIfApplicableForTesting("继续推进亮亮项目") == nil)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.count == 1)

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"亮亮","job_id":"\#(existingJob.jobId)","plan_id":"plan-liang-continue-v2","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"审查当前执行上下文","kind":"write_memory","status":"completed"},{"step_id":"step-002","title":"梳理项目结构并给出重构建议","kind":"write_memory","status":"pending"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "继续推进亮亮项目"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 写入计划：plan-liang-continue-v2"))
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.count == 1)
        #expect(SupervisorProjectPlanStore.load(for: ctx).plans.count == 1)
    }

    @Test
    func continueIntentDoesNotBootstrapWithoutFocusedProject() throws {
        let manager = SupervisorManager.makeForTesting()
        let alphaRoot = try makeProjectRoot(named: "supervisor-continue-no-focus-alpha")
        let betaRoot = try makeProjectRoot(named: "supervisor-continue-no-focus-beta")
        defer { try? FileManager.default.removeItem(at: alphaRoot) }
        defer { try? FileManager.default.removeItem(at: betaRoot) }

        var alpha = makeProjectEntry(root: alphaRoot, displayName: "Alpha Console")
        alpha.nextStepSummary = "补齐 Alpha 的重构计划"
        var beta = makeProjectEntry(root: betaRoot, displayName: "Beta Studio")
        beta.nextStepSummary = "补齐 Beta 的运行验证"

        let appModel = AppModel()
        appModel.registry = registry(with: [alpha, beta])
        manager.setAppModel(appModel)

        #expect(manager.directSupervisorActionIfApplicableForTesting("继续推进") == nil)

        let alphaCtx = try #require(appModel.projectContext(for: alpha.projectId))
        let betaCtx = try #require(appModel.projectContext(for: beta.projectId))
        #expect(SupervisorProjectJobStore.load(for: alphaCtx).jobs.isEmpty)
        #expect(SupervisorProjectJobStore.load(for: betaCtx).jobs.isEmpty)
    }

    @Test
    func malformedCreateJobPayloadFailsClosedWithoutCreatingJob() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-create-job-invalid")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let rendered = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        #expect(rendered.contains("❌ CREATE_JOB 标签解析失败："))
        #expect(!rendered.contains("[CREATE_JOB]"))
        #expect(manager.currentTask == nil)
        #expect(manager.messages.isEmpty)

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let snapshot = SupervisorProjectJobStore.load(for: ctx)
        #expect(snapshot.jobs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: ctx.rawLogURL.path))
    }

    @Test
    func malformedUpsertPlanPayloadFailsClosedWithoutCreatingPlan() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-upsert-plan-invalid")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"准备写计划","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"[UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"job-1","plan_id":}[/UPSERT_PLAN]"#,
            userMessage: "请更新计划"
        )

        #expect(rendered.contains("❌ UPSERT_PLAN 标签解析失败："))
        #expect(!rendered.contains("[UPSERT_PLAN]"))

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let planSnapshot = SupervisorProjectPlanStore.load(for: ctx)
        #expect(planSnapshot.plans.isEmpty)
    }

    @Test
    func nonUserTriggerAllowsGovernedCreateJobAndFallsBackToTriggerSource() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-create-job-heartbeat")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        manager.setAppModel(appModel)

        let rendered = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"继续自动排队后续验证","priority":"normal","current_owner":"supervisor"}[/CREATE_JOB]"#,
            userMessage: "heartbeat refresh",
            triggerSource: "heartbeat"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 创建任务：继续自动排队后续验证（priority=normal）"))

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let snapshot = SupervisorProjectJobStore.load(for: ctx)
        let job = try #require(snapshot.jobs.first)
        #expect(job.source == .heartbeat)
        #expect(job.priority == .normal)
        #expect(manager.currentTask?.id == job.jobId)
    }

    @Test
    func assignModelTagAcceptsChineseRoleAlias() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-command-guard")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        manager.setAppModel(appModel)

        let rendered = manager.processSupervisorResponseForTesting(
            "[ASSIGN_MODEL]\(project.displayName)|开发者|openai/gpt-5.3-codex[/ASSIGN_MODEL]",
            userMessage: "把 \(project.displayName) 的开发者模型改为 openai/gpt-5.3-codex"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 设置 编程助手 模型：openai/gpt-5.3-codex"))

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(config.modelOverride(for: .coder) == "openai/gpt-5.3-codex")
    }

    @Test
    func naturalLanguageModelSwitchUsesShorthandAndDefaultsToCoder() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-language-switch")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.modelsState = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "openai/gpt-5.3-codex",
                    name: "GPT 5.3 Codex",
                    backend: "remote",
                    quant: "n/a",
                    contextLength: 200_000,
                    paramsB: 0,
                    roles: nil,
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: nil,
                    note: nil
                )
            ],
            updatedAt: Date().timeIntervalSince1970
        )
        manager.setAppModel(appModel)

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("把我的世界这个项目的模型换成5.3")
        )

        #expect(rendered.contains("已经把《我的世界还原项目》的 coder 模型切到 openai/gpt-5.3-codex"))
        #expect(rendered.contains("我默认按 coder 处理"))

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(config.modelOverride(for: .coder) == "openai/gpt-5.3-codex")
    }

    @Test
    func sharedRoleResolverSupportsCommonChineseAliases() {
        #expect(AXRole.resolveModelAssignmentToken("开发者") == .coder)
        #expect(AXRole.resolveModelAssignmentToken("审查") == .reviewer)
        #expect(AXRole.resolveModelAssignmentToken("顾问") == .advisor)
    }

    private func registry(with projects: [AXProjectEntry]) -> AXProjectRegistry {
        AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projects.first?.projectId,
            projects: projects
        )
    }

    private func makeProjectEntry(root: URL, displayName: String) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: displayName,
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=stable",
            currentStateSummary: "运行中",
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: Date().timeIntervalSince1970
        )
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt-\(name)-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func readRawLogEntries(at url: URL) throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let raw = try String(contentsOf: url, encoding: .utf8)
        return try raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                let data = Data(line.utf8)
                let object = try JSONSerialization.jsonObject(with: data)
                return try #require(object as? [String: Any])
            }
    }

    private func jsonEscapedString(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "\\":
                escaped += "\\\\"
            case "\"":
                escaped += "\\\""
            case "\n":
                escaped += "\\n"
            case "\r":
                escaped += "\\r"
            case "\t":
                escaped += "\\t"
            default:
                escaped.append(character)
            }
        }
        return escaped
    }
}

private struct SupervisorSkillRegistryFixture {
    let root: URL
    let hubBaseDir: URL

    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt-supervisor-skill-registry-\(UUID().uuidString)",
            isDirectory: true
        )
        hubBaseDir = root.appendingPathComponent("hub", isDirectory: true)
        try? FileManager.default.createDirectory(at: hubBaseDir, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func writeHubSkillsStore(projectID: String) throws {
        let storeDir = hubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

        let index = #"""
        {
          "schema_version": "skills_store_index.v1",
          "updated_at_ms": 77,
          "skills": [
            {
              "skill_id": "project.snapshot",
              "name": "Project Snapshot",
              "version": "1.0.0",
              "description": "Read the governed project snapshot.",
              "publisher_id": "publisher.project",
              "source_id": "builtin:catalog",
              "package_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Read the governed project snapshot.\",\"risk_level\":\"low\",\"requires_grant\":false,\"timeout_ms\":15000,\"max_retries\":0}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "repo.write.file",
              "name": "Repo Write File",
              "version": "1.0.0",
              "description": "Write a file inside the governed project root.",
              "publisher_id": "publisher.repo",
              "source_id": "builtin:catalog",
              "package_sha256": "6868686868686868686868686868686868686868686868686868686868686868",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "6969696969696969696969696969696969696969696969696969696969696969",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Write a file inside the governed project root.\",\"risk_level\":\"medium\",\"requires_grant\":false,\"timeout_ms\":15000,\"max_retries\":0}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "repo.test.run",
              "name": "Repo Test Run",
              "version": "1.0.0",
              "description": "Run governed repo test commands from an allowlisted command family.",
              "publisher_id": "publisher.repo",
              "source_id": "builtin:catalog",
              "package_sha256": "7070707070707070707070707070707070707070707070707070707070707070",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "7171717171717171717171717171717171717171717171717171717171717171",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Run governed repo test commands from an allowlisted command family.\",\"risk_level\":\"medium\",\"requires_grant\":false,\"timeout_ms\":120000,\"max_retries\":0}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "repo.build.run",
              "name": "Repo Build Run",
              "version": "1.0.0",
              "description": "Run governed repo build commands from an allowlisted command family.",
              "publisher_id": "publisher.repo",
              "source_id": "builtin:catalog",
              "package_sha256": "7272727272727272727272727272727272727272727272727272727272727272",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "7373737373737373737373737373737373737373737373737373737373737373",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Run governed repo build commands from an allowlisted command family.\",\"risk_level\":\"medium\",\"requires_grant\":false,\"timeout_ms\":180000,\"max_retries\":0}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "repo.git.apply",
              "name": "Repo Git Apply",
              "version": "1.0.0",
              "description": "Apply a governed unified diff patch after precheck validation.",
              "publisher_id": "publisher.repo",
              "source_id": "builtin:catalog",
              "package_sha256": "7474747474747474747474747474747474747474747474747474747474747474",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "7575757575757575757575757575757575757575757575757575757575757575",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Apply a governed unified diff patch after precheck validation.\",\"risk_level\":\"medium\",\"requires_grant\":false,\"timeout_ms\":120000,\"max_retries\":0}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "find-skills",
              "name": "Find Skills",
              "version": "1.1.0",
              "description": "Discover governed Agent skills from X-Hub.",
              "publisher_id": "xhub.official",
              "source_id": "builtin:catalog",
              "package_sha256": "8181818181818181818181818181818181818181818181818181818181818181",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "8282828282828282828282828282828282828282828282828282828282828282",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Discover governed Agent skills from X-Hub.\",\"risk_level\":\"low\",\"requires_grant\":false,\"side_effect_class\":\"read_only\",\"timeout_ms\":10000,\"max_retries\":1}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "agent-browser",
              "name": "Agent Browser",
              "version": "1.0.0",
              "description": "Governed browser automation for navigation, extraction, and credential-aware interaction.",
              "publisher_id": "xhub.official",
              "source_id": "builtin:catalog",
              "package_sha256": "9191919191919191919191919191919191919191919191919191919191919191",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "9292929292929292929292929292929292929292929292929292929292929292",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Governed browser automation for navigation, extraction, and credential-aware interaction.\",\"capabilities_required\":[\"browser.read\",\"device.browser.control\",\"web.fetch\"],\"risk_level\":\"high\",\"requires_grant\":true,\"side_effect_class\":\"external_side_effect\",\"timeout_ms\":45000,\"max_retries\":2}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "self-improving-agent",
              "name": "Self Improving Agent",
              "version": "1.0.0",
              "description": "Supervisor retrospective pack that turns recent failures and governance findings into actionable fixes.",
              "publisher_id": "xhub.official",
              "source_id": "builtin:catalog",
              "package_sha256": "9393939393939393939393939393939393939393939393939393939393939393",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "9494949494949494949494949494949494949494949494949494949494949494",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Supervisor retrospective pack that turns recent failures and governance findings into actionable fixes.\",\"risk_level\":\"low\",\"requires_grant\":false,\"side_effect_class\":\"read_only\",\"timeout_ms\":15000,\"max_retries\":1}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "summarize",
              "name": "Summarize",
              "version": "1.1.0",
              "description": "Summarize webpages, PDFs, and long documents through governed runtime tools.",
              "publisher_id": "xhub.official",
              "source_id": "builtin:catalog",
              "package_sha256": "8383838383838383838383838383838383838383838383838383838383838383",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "8484848484848484848484848484848484848484848484848484848484848484",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Summarize webpages, PDFs, and long documents through governed runtime tools.\",\"risk_level\":\"medium\",\"requires_grant\":false,\"side_effect_class\":\"read_only\",\"timeout_ms\":30000,\"max_retries\":1}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "browser.runtime.smoke",
              "name": "Browser Runtime Smoke",
              "version": "2.0.0",
              "description": "Open the governed browser runtime and capture smoke evidence.",
              "publisher_id": "publisher.browser",
              "source_id": "builtin:catalog",
              "package_sha256": "9999999999999999999999999999999999999999999999999999999999999999",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Open the governed browser runtime and capture smoke evidence.\",\"risk_level\":\"high\",\"requires_grant\":true,\"timeout_ms\":45000,\"max_retries\":1}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "web.fetch",
              "name": "Web Fetch",
              "version": "1.0.0",
              "description": "Fetch a governed web resource through the Hub boundary.",
              "publisher_id": "publisher.web",
              "source_id": "builtin:catalog",
              "package_sha256": "1212121212121212121212121212121212121212121212121212121212121212",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "1313131313131313131313131313131313131313131313131313131313131313",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Fetch a governed web resource through the Hub boundary.\",\"risk_level\":\"high\",\"requires_grant\":true,\"timeout_ms\":30000,\"max_retries\":1}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "web.search",
              "name": "Web Search",
              "version": "1.0.0",
              "description": "Search the web through the governed network route.",
              "publisher_id": "publisher.web",
              "source_id": "builtin:catalog",
              "package_sha256": "1414141414141414141414141414141414141414141414141414141414141414",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "1515151515151515151515151515151515151515151515151515151515151515",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Search the web through the governed network route.\",\"risk_level\":\"high\",\"requires_grant\":true,\"timeout_ms\":30000,\"max_retries\":1}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "browser.read",
              "name": "Browser Read",
              "version": "1.0.0",
              "description": "Read a governed browser page through the Hub network boundary.",
              "publisher_id": "publisher.browser",
              "source_id": "builtin:catalog",
              "package_sha256": "1616161616161616161616161616161616161616161616161616161616161616",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "1717171717171717171717171717171717171717171717171717171717171717",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Read a governed browser page through the Hub network boundary.\",\"risk_level\":\"high\",\"requires_grant\":true,\"timeout_ms\":30000,\"max_retries\":1}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            }
          ]
        }
        """#
        try index.write(to: storeDir.appendingPathComponent("skills_store_index.json"), atomically: true, encoding: .utf8)

        let pins = """
        {
          "schema_version": "skills_pins.v1",
          "updated_at_ms": 77,
          "memory_core_pins": [],
          "global_pins": [],
          "project_pins": [
            {
              "project_id": "\(projectID)",
              "skill_id": "project.snapshot",
              "package_sha256": "7777777777777777777777777777777777777777777777777777777777777777"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "repo.write.file",
              "package_sha256": "6868686868686868686868686868686868686868686868686868686868686868"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "repo.test.run",
              "package_sha256": "7070707070707070707070707070707070707070707070707070707070707070"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "repo.build.run",
              "package_sha256": "7272727272727272727272727272727272727272727272727272727272727272"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "repo.git.apply",
              "package_sha256": "7474747474747474747474747474747474747474747474747474747474747474"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "find-skills",
              "package_sha256": "8181818181818181818181818181818181818181818181818181818181818181"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "agent-browser",
              "package_sha256": "9191919191919191919191919191919191919191919191919191919191919191"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "self-improving-agent",
              "package_sha256": "9393939393939393939393939393939393939393939393939393939393939393"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "summarize",
              "package_sha256": "8383838383838383838383838383838383838383838383838383838383838383"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "browser.runtime.smoke",
              "package_sha256": "9999999999999999999999999999999999999999999999999999999999999999"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "web.fetch",
              "package_sha256": "1212121212121212121212121212121212121212121212121212121212121212"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "web.search",
              "package_sha256": "1414141414141414141414141414141414141414141414141414141414141414"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "browser.read",
              "package_sha256": "1616161616161616161616161616161616161616161616161616161616161616"
            }
          ]
        }
        """
        try pins.write(to: storeDir.appendingPathComponent("skills_pins.json"), atomically: true, encoding: .utf8)

        let revocations = """
        {
          "schema_version": "xhub.skill_revocations.v1",
          "updated_at_ms": 77,
          "revoked_sha256": [],
          "revoked_skill_ids": [],
          "revoked_publishers": []
        }
        """
        try revocations.write(to: storeDir.appendingPathComponent("skill_revocations.json"), atomically: true, encoding: .utf8)
    }
}

private func appendManifestDrivenSkillFixture(
    hubBaseDir: URL,
    projectID: String,
    skillID: String,
    packageSHA256: String,
    canonicalManifestSHA256: String,
    manifest: [String: Any]
) throws {
    let storeDir = hubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
    let indexURL = storeDir.appendingPathComponent("skills_store_index.json")
    let pinsURL = storeDir.appendingPathComponent("skills_pins.json")

    var indexRoot = try loadJSONObject(at: indexURL)
    var skills = indexRoot["skills"] as? [[String: Any]] ?? []
    let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    let manifestText = String(decoding: manifestData, as: UTF8.self)
    skills.append([
        "skill_id": skillID,
        "name": skillID,
        "version": "1.0.0",
        "description": "Manifest-driven wrapper test skill.",
        "publisher_id": "xhub.test",
        "source_id": "builtin:catalog",
        "package_sha256": packageSHA256,
        "abi_compat_version": "skills_abi_compat.v1",
        "compatibility_state": "supported",
        "canonical_manifest_sha256": canonicalManifestSHA256,
        "install_hint": "",
        "manifest_json": manifestText,
        "mapping_aliases_used": [],
        "defaults_applied": [],
    ])
    indexRoot["skills"] = skills
    try writeJSONObject(indexRoot, to: indexURL)

    var pinsRoot = try loadJSONObject(at: pinsURL)
    var projectPins = pinsRoot["project_pins"] as? [[String: Any]] ?? []
    projectPins.append([
        "project_id": projectID,
        "skill_id": skillID,
        "package_sha256": packageSHA256,
    ])
    pinsRoot["project_pins"] = projectPins
    try writeJSONObject(pinsRoot, to: pinsURL)
}

private func loadOfficialAgentSkillManifestFixture(skillID: String) throws -> [String: Any] {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = repoRoot
        .appendingPathComponent("official-agent-skills", isDirectory: true)
        .appendingPathComponent(skillID, isDirectory: true)
        .appendingPathComponent("skill.json")
    return try loadJSONObject(at: url)
}

private func loadJSONObject(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CocoaError(.coderReadCorrupt)
    }
    return object
}

private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
}

private func makeSupervisorTrustedAutomationPermissionReadiness() -> AXTrustedAutomationPermissionOwnerReadiness {
    AXTrustedAutomationPermissionOwnerReadiness(
        schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
        ownerID: "owner-local",
        ownerType: "xterminal_app",
        bundleID: "com.xterminal.app",
        installState: "ready",
        mode: "managed_or_prompted",
        accessibility: .granted,
        automation: .granted,
        screenRecording: .granted,
        fullDiskAccess: .missing,
        inputMonitoring: .missing,
        canPromptUser: true,
        managedByMDM: false,
        overallState: "ready",
        openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map(\.openSettingsAction),
        auditRef: "audit-supervisor-local-approval-ready"
    )
}
