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
