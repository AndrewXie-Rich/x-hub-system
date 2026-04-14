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
        #expect(summary.contains("Secret Vault"))
        #expect(summary.contains("凭据"))
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
    func systemMetaQueryBypassesHubBriefGuard() throws {
        let manager = SupervisorManager.makeForTesting()

        let rendered = manager.fallbackSupervisorResponseForTesting("你对这套系统有什么建议")

        #expect(!rendered.contains("Hub Brief"))
    }

    @Test
    func callGlobalSkillExecutesFindSkillsWithoutFocusedProject() async throws {
        let manager = SupervisorManager.makeForTesting()
        final class ObservedCallBox: @unchecked Sendable {
            var value: ToolCall?
        }
        let observedCall = ObservedCallBox()

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            observedCall.value = call
            #expect(call.tool == .skills_search)
            #expect(call.args["query"]?.stringValue == "ppt")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: ToolExecutor.structuredOutput(
                    summary: [
                        "tool": .string(ToolName.skills_search.rawValue),
                        "ok": .bool(true),
                        "results_count": .number(1),
                    ],
                    body: """
                    1. PPT Helper [ppt-helper] v1.0.0
                       publisher=xhub.official source=official:stable
                       risk=low grant=no side_effect=read_only
                       caps: slides.read
                    """
                )
            )
        }

        let rendered = manager.processSupervisorResponseForTesting(
            """
            我先查一下当前可用的 PPT 技能。
            [CALL_GLOBAL_SKILL]{"skill_id":"find-skills","payload":{"query":"ppt"}}[/CALL_GLOBAL_SKILL]
            """,
            userMessage: "查 PPT 相关有哪些可用 skill"
        )

        #expect(rendered.contains("✅ 已为 Supervisor 排队全局技能调用：find-skills"))
        #expect(!rendered.contains("[CALL_GLOBAL_SKILL]"))

        await manager.waitForSupervisorSkillDispatchForTesting()

        #expect(observedCall.value?.tool == .skills_search)
        #expect(manager.messages.contains(where: {
            $0.content.contains("全局技能调用完成：find-skills")
                && $0.content.contains("PPT Helper [ppt-helper]")
        }))
    }

    @Test
    func globalFindSkillsThenEnableRequestUsesExactPackageAndSurfacesReviewGuidance() async throws {
        actor ObservedCalls {
            private var calls: [ToolCall] = []

            func record(_ call: ToolCall) {
                calls.append(call)
            }

            func snapshot() -> [ToolCall] {
                calls
            }
        }

        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let observedCalls = ObservedCalls()
        let packageSHA = "9191919191919191919191919191919191919191919191919191919191919191"

        HubIPCClient.installSkillPinOverrideForTesting { request in
            #expect(request.scope == "global")
            #expect(request.skillId == "agent-browser")
            #expect(request.packageSHA256 == packageSHA)
            #expect(request.projectId == nil)
            #expect(request.note == "supervisor-global-enable")
            return HubIPCClient.SkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: request.scope,
                userId: "user-supervisor",
                projectId: request.projectId ?? "",
                skillId: request.skillId,
                packageSHA256: request.packageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "official_skill_review_blocked"
            )
        }
        defer { HubIPCClient.resetSkillPinOverrideForTesting() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, root in
            await observedCalls.record(call)
            switch call.tool {
            case .skills_search:
                #expect(call.args["query"]?.stringValue == "browser automation")
                #expect(call.args["source_filter"]?.stringValue == "builtin:catalog")
                #expect(call.args["limit"]?.stringValue == "1")
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: ToolExecutor.structuredOutput(
                        summary: [
                            "tool": .string(ToolName.skills_search.rawValue),
                            "ok": .bool(true),
                            "results_count": .number(1),
                        ],
                        body: """
                        1. Agent Browser [agent-browser] v1.0.0
                           publisher=xhub.official source=builtin:catalog package_sha256=\(packageSHA)
                           risk=high grant=yes side_effect=external_side_effect
                           caps: browser.read, device.browser.control, web.fetch
                        """
                    )
                )
            case .skills_pin:
                return try await ToolExecutor.execute(call: call, projectRoot: root)
            default:
                Issue.record("unexpected global tool: \(call.tool.rawValue)")
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: "unexpected global tool"
                )
            }
        }

        let discoveryRendered = manager.processSupervisorResponseForTesting(
            """
            我先查一下 browser automation 相关的官方技能。
            [CALL_GLOBAL_SKILL]{"skill_id":"find-skills","payload":{"query":"browser automation","source_filter":"builtin:catalog","max_results":1}}[/CALL_GLOBAL_SKILL]
            """,
            userMessage: "先查 browser automation 相关 skill"
        )

        #expect(discoveryRendered.contains("✅ 已为 Supervisor 排队全局技能调用：find-skills"))
        #expect(!discoveryRendered.contains("[CALL_GLOBAL_SKILL]"))

        await manager.waitForSupervisorSkillDispatchForTesting()

        #expect(manager.messages.contains(where: {
            $0.content.contains("全局技能调用完成：find-skills")
                && $0.content.contains("Agent Browser [agent-browser]")
                && $0.content.contains("package_sha256=\(packageSHA)")
        }))

        let enableRendered = manager.processSupervisorResponseForTesting(
            """
            我会按刚才查到的精确 skill_id 和 package_sha256 发起 Hub 可用性申请。
            [CALL_GLOBAL_SKILL]{"skill_id":"request-skill-enable","payload":{"skill_id":"agent-browser","package_sha256":"\(packageSHA)","note":"supervisor-global-enable"}}[/CALL_GLOBAL_SKILL]
            """,
            userMessage: "那就申请 agent-browser"
        )

        #expect(enableRendered.contains("✅ 已为 Supervisor 排队全局技能调用"))
        #expect(enableRendered.contains("request-skill-enable"))
        #expect(!enableRendered.contains("[CALL_GLOBAL_SKILL]"))

        await manager.waitForSupervisorSkillDispatchForTesting()

        let calls = await observedCalls.snapshot()
        #expect(calls.count == 2)
        #expect(calls[0].tool == .skills_search)
        #expect(calls[1].tool == .skills_pin)
        #expect(calls[1].args["skill_id"]?.stringValue == "agent-browser")
        #expect(calls[1].args["package_sha256"]?.stringValue == packageSHA)
        #expect(calls[1].args["scope"]?.stringValue == nil)
        #expect(calls[1].args["project_id"]?.stringValue == nil)

        #expect(manager.messages.contains(where: {
            $0.content.contains("全局技能调用失败：request-skill-enable")
                && $0.content.contains("Hub 已自动审查该官方技能包")
                && $0.content.contains("doctor")
                && $0.content.contains("lifecycle")
        }))
    }

    @Test
    func globalEnableRequestAcceptsEnableThisFollowup() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        final class ObservedCallBox: @unchecked Sendable {
            var value: ToolCall?
        }
        let observedCall = ObservedCallBox()
        let packageSHA = "9292929292929292929292929292929292929292929292929292929292929292"

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            observedCall.value = call
            #expect(call.tool == .skills_pin)
            #expect(call.args["skill_id"]?.stringValue == "agent-browser")
            #expect(call.args["package_sha256"]?.stringValue == packageSHA)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: ToolExecutor.structuredOutput(
                    summary: [
                        "tool": .string(ToolName.skills_pin.rawValue),
                        "ok": .bool(true),
                        "scope": .string("global"),
                        "skill_id": .string("agent-browser"),
                        "package_sha256": .string(packageSHA),
                    ],
                    body: "Hub 已通过审查并启用技能：agent-browser@929292929292（global）"
                )
            )
        }

        let rendered = manager.processSupervisorResponseForTesting(
            """
            我会直接提交启用申请。
            [CALL_GLOBAL_SKILL]{"skill_id":"request-skill-enable","payload":{"skill_id":"agent-browser","package_sha256":"\(packageSHA)","note":"supervisor-global-enable"}}[/CALL_GLOBAL_SKILL]
            """,
            userMessage: "启用这个"
        )

        #expect(rendered.contains("✅ 已为 Supervisor 排队全局技能调用：request-skill-enable"))
        #expect(!rendered.contains("[CALL_GLOBAL_SKILL]"))

        await manager.waitForSupervisorSkillDispatchForTesting()

        #expect(observedCall.value?.tool == .skills_pin)
        #expect(manager.messages.contains(where: {
            $0.content.contains("全局技能调用完成：request-skill-enable")
                && $0.content.contains("agent-browser@929292929292")
        }))
    }

    @Test
    func descriptiveQuestionWithHyphenatedSkillIdStillStripsGlobalEnableTag() throws {
        let manager = SupervisorManager.makeForTesting()
        final class ObservedCallBox: @unchecked Sendable {
            var value: ToolCall?
        }
        let observedCall = ObservedCallBox()

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            observedCall.value = call
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "unexpected global call"
            )
        }

        let rendered = manager.processSupervisorResponseForTesting(
            """
            这是一个候选技能说明。
            [CALL_GLOBAL_SKILL]{"skill_id":"request-skill-enable","payload":{"skill_id":"agent-browser","package_sha256":"9393939393939393939393939393939393939393939393939393939393939393","note":"supervisor-global-enable"}}[/CALL_GLOBAL_SKILL]
            """,
            userMessage: "agent-browser 是什么"
        )

        #expect(rendered.contains("这是一个候选技能说明"))
        #expect(!rendered.contains("已为 Supervisor 排队全局技能调用"))
        #expect(!rendered.contains("[CALL_GLOBAL_SKILL]"))
        #expect(observedCall.value?.tool == nil)
        #expect(manager.messages.isEmpty)
    }

    @Test
    func projectSkillDispatchAcceptsUseThisSkillFollowup() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-project-use-this-skill")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        final class ObservedCallBox: @unchecked Sendable {
            var value: ToolCall?
        }
        let observedCall = ObservedCallBox()

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            observedCall.value = call
            #expect(call.tool == .skills_search)
            #expect(call.args["query"]?.stringValue == "browser")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: ToolExecutor.structuredOutput(
                    summary: [
                        "tool": .string(ToolName.skills_search.rawValue),
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-use-this-skill-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索浏览器自动化 skill","kind":"call_skill","status":"pending","skill_id":"find-skills"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"find-skills","payload":{"query":"browser","source_filter":"builtin:catalog"}}[/CALL_SKILL]
            """#,
            userMessage: "用这个 skill"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：find-skills"))
        #expect(!rendered.contains("[CALL_SKILL]"))

        await manager.waitForSupervisorSkillDispatchForTesting()

        #expect(observedCall.value?.tool == .skills_search)
        #expect(manager.messages.contains(where: {
            $0.content.contains("已为项目 \(project.displayName) 排队技能调用：find-skills")
        }))
    }

    @Test
    func descriptiveProjectQuestionAboutSkillStillStripsCallSkillTag() throws {
        let manager = SupervisorManager.makeForTesting()
        final class ObservedCallBox: @unchecked Sendable {
            var value: ToolCall?
        }
        let observedCall = ObservedCallBox()

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            observedCall.value = call
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "unexpected skill call"
            )
        }

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            这是候选技能说明。
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"job-1","step_id":"step-1","skill_id":"find-skills","payload":{"query":"browser","source_filter":"builtin:catalog"}}[/CALL_SKILL]
            """#,
            userMessage: "这个 skill 是做什么用的"
        )

        #expect(rendered.contains("这是候选技能说明。"))
        #expect(!rendered.contains("已为项目"))
        #expect(!rendered.contains("[CALL_SKILL]"))
        #expect(observedCall.value?.tool == nil)
        #expect(manager.messages.isEmpty)
    }

    @Test
    func defaultProjectCreationWithoutPendingIntakePromptsForGoal() throws {
        let manager = SupervisorManager.makeForTesting()

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("按默认方案建项目")
        )

        #expect(rendered.contains("还没给项目名"))
        #expect(rendered.contains("新建项目，名字叫 俄罗斯方块"))
    }

    @Test
    func executionIntakeDefaultProjectCreationCarriesGoalAcrossTurnsAndBootstrapsWorkOrder() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "supervisor-execution-intake-bootstrap")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let intakeReply = try #require(
            manager.directSupervisorReplyIfApplicableForTesting(
                "我要做个贪食蛇游戏，你能做个详细工单发给project AI去推进吗"
            )
        )
        #expect(intakeReply.contains("按默认方案建项目"))
        #expect(intakeReply.contains("贪食蛇"))

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting("按默认方案建项目")
        )
        #expect(creationReply.contains("贪食蛇游戏"))
        #expect(creationReply.contains("第一版详细工单"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "贪食蛇游戏")
        #expect(project.currentStateSummary?.contains("默认方案已锁定") == true)
        #expect(project.nextStepSummary?.contains("页面骨架") == true)

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let memory = try #require(AXProjectStore.loadMemoryIfPresent(for: ctx))
        #expect(memory.goal.contains("贪食蛇"))
        #expect(memory.nextSteps.first?.contains("页面骨架") == true)

        let capsule = try #require(SupervisorProjectSpecCapsuleStore.load(for: ctx))
        #expect(capsule.goal.contains("贪食蛇"))
        #expect(capsule.mvpDefinition.contains("方向键控制"))

        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        let job = try #require(jobSnapshot.jobs.first)
        #expect(job.currentOwner == "coder")
        #expect(job.goal.contains("贪食蛇"))

        let planSnapshot = SupervisorProjectPlanStore.load(for: ctx)
        let plan = try #require(planSnapshot.plans.first)
        #expect(plan.currentOwner == "coder")
        #expect(plan.steps.count == 5)
        #expect(plan.steps[1].title.contains("游戏骨架"))
        #expect(plan.steps[2].title.contains("核心玩法"))

        #expect(manager.messages.contains(where: { $0.content.contains("第一版工单挂给 Project AI") }))
    }

    @Test
    func liXiangPhraseCarriesGoalAcrossTurnsAndBootstrapsProjectCreation() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "supervisor-li-xiang-bootstrap")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let intakeReply = try #require(
            manager.directSupervisorReplyIfApplicableForTesting(
                "我要做个贪食蛇游戏，你能做个详细工单发给project AI去推进吗"
            )
        )
        #expect(intakeReply.contains("按默认方案建项目"))

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting("那就立项吧")
        )
        #expect(creationReply.contains("贪食蛇游戏"))
        #expect(creationReply.contains("创建完成后"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "贪食蛇游戏")

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        #expect(jobSnapshot.jobs.count == 1)
        #expect(manager.messages.contains(where: { $0.content.contains("第一版工单挂给 Project AI") }))
    }

    @Test
    func explicitProjectCreationPromptCarriesAcrossTurnsAndCreatesProjectInDefaultProjectsDirectory() async throws {
        let manager = SupervisorManager.makeForTesting()
        let registryBase = try makeProjectRoot(named: "supervisor-default-projects-base")
        defer { try? FileManager.default.removeItem(at: registryBase) }

        let envKey = "XTERMINAL_PROJECT_REGISTRY_BASE_DIR"
        let originalEnv = currentEnvironmentValue(envKey)
        setenv(envKey, registryBase.path, 1)
        defer {
            if let originalEnv {
                setenv(envKey, originalEnv, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)

        let promptReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting("你先建一个项目吧")
        )
        #expect(promptReply.contains("还没给项目名"))
        #expect(promptReply.contains("新建项目，名字叫 俄罗斯方块"))

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting("就是前面说的俄罗斯方块")
        )
        #expect(creationReply.contains("俄罗斯方块"))
        #expect(creationReply.contains("创建完成后"))
        #expect(!creationReply.contains("目录选好后"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "俄罗斯方块")
        #expect(project.rootPath.hasPrefix(registryBase.appendingPathComponent("Projects", isDirectory: true).path))
        #expect(URL(fileURLWithPath: project.rootPath, isDirectory: true).lastPathComponent.hasPrefix("俄罗斯方块"))
        #expect(project.currentStateSummary?.contains("默认方案已锁定") == true)

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        let job = try #require(jobSnapshot.jobs.first)
        #expect(job.goal.contains("俄罗斯方块"))

        #expect(manager.messages.contains(where: { $0.content.contains("第一版工单挂给 Project AI") }))
    }

    @Test
    func explicitProjectCreationRequestWithInlineGoalCreatesProjectInSingleTurn() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "supervisor-inline-goal-project-creation")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "帮我做个俄罗斯方块网页游戏，然后直接立项"
            )
        )
        #expect(creationReply.contains("俄罗斯方块"))
        #expect(creationReply.contains("创建完成后"))
        #expect(!creationReply.contains("还缺一个明确交付目标"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName.contains("俄罗斯方块"))

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        #expect(jobSnapshot.jobs.count == 1)
        #expect(manager.messages.contains(where: { $0.content.contains("第一版工单挂给 Project AI") }))
    }

    @Test
    func explicitProjectCreationRequestWithCreateFirstWordOrderCreatesProjectInSingleTurn() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "supervisor-inline-goal-create-first-project-creation")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "直接立项，帮我做个俄罗斯方块网页游戏"
            )
        )
        #expect(creationReply.contains("俄罗斯方块"))
        #expect(creationReply.contains("创建完成后"))
        #expect(!creationReply.contains("还缺一个明确交付目标"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let ctx = try #require(appModel.projectContext(for: appModel.registry.projects[0].projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        #expect(jobSnapshot.jobs.count == 1)
    }

    @Test
    func explicitProjectCreationRequestWithInlineEngineeringGoalCreatesProjectInSingleTurn() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "supervisor-inline-engineering-goal-project-creation")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "把 heartbeat review 这一块收口，然后直接立项"
            )
        )
        #expect(creationReply.contains("创建完成后"))
        #expect(!creationReply.contains("还缺一个明确交付目标"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        let job = try #require(jobSnapshot.jobs.first)
        #expect(job.goal.contains("heartbeat") || job.goal.contains("review") || job.goal.contains("收口"))
        #expect(manager.messages.contains(where: { $0.content.contains("第一版工单挂给 Project AI") }))
    }

    @Test
    func explicitNamedProjectCreationWithMinimumRunnableGoalCreatesProjectInSingleTurn() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "supervisor-inline-minimum-runnable-project-creation")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "新建项目，名字叫 坦克大战。第一版先做成最小可运行版本。"
            )
        )
        #expect(creationReply.contains("坦克大战"))
        #expect(creationReply.contains("最小可运行"))
        #expect(!creationReply.contains("默认 MVP"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "坦克大战")

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        let job = try #require(jobSnapshot.jobs.first)
        #expect(job.goal.contains("最小可运行"))
        #expect(!job.goal.contains("默认 MVP"))
    }

    @Test
    func namedProjectCreationWithoutInlineGoalCreatesProjectBeforeAskingForGoal() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "supervisor-create-before-goal")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting("新建项目，名字叫 坦克大战")
        )
        #expect(creationReply.contains("我先把《坦克大战》建起来"))
        #expect(!creationReply.contains("还缺一个明确交付目标"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "坦克大战")

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        let planSnapshot = SupervisorProjectPlanStore.load(for: ctx)
        #expect(jobSnapshot.jobs.isEmpty)
        #expect(planSnapshot.plans.isEmpty)
        #expect(manager.messages.contains(where: { $0.content.contains("✅ 已先创建项目：《坦克大战》") }))
        #expect(manager.messages.contains(where: { $0.content.contains("现在还差一句交付目标") }))
    }

    @Test
    func colloquialNamedProjectCreationWithoutInlineGoalCreatesProjectBeforeAskingForGoal() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "supervisor-create-before-goal-colloquial")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting("帮我起个新项目，叫 坦克大战")
        )
        #expect(creationReply.contains("我先把《坦克大战》建起来"))
        #expect(!creationReply.contains("还缺一个明确交付目标"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "坦克大战")

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        let planSnapshot = SupervisorProjectPlanStore.load(for: ctx)
        #expect(jobSnapshot.jobs.isEmpty)
        #expect(planSnapshot.plans.isEmpty)
        #expect(manager.messages.contains(where: { $0.content.contains("✅ 已先创建项目：《坦克大战》") }))
        #expect(manager.messages.contains(where: { $0.content.contains("现在还差一句交付目标") }))
    }

    @Test
    func colloquialRecoveredProposalProjectCreationWithDefaultMVPSignalCreatesImmediately() async throws {
        let manager = SupervisorManager.makeForTesting()
        let registryBase = try makeProjectRoot(named: "supervisor-default-mvp-recovered-proposal-colloquial")
        defer { try? FileManager.default.removeItem(at: registryBase) }

        let envKey = "XTERMINAL_PROJECT_REGISTRY_BASE_DIR"
        let originalEnv = currentEnvironmentValue(envKey)
        setenv(envKey, registryBase.path, 1)
        defer {
            if let originalEnv {
                setenv(envKey, originalEnv, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.messages.append(
            SupervisorMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: """
我更推荐第二种，原因很简单：更可追溯，也更不容易把旧的脏上下文继续带进去。
你前面要做的是**坦克大战网页游戏**，我这边默认理解为：
- 项目名：**坦克大战网页游戏**
- 形态：**完整版单机 Web 版**

如果你决定拆成新盘，你只要回我一句：
- `新建独立项目`
或
- `直接重命名`
我就按这个方向继续给你下一步。
""",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        )

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting("帮我起个新项目，叫做 坦克大战。默认 MVP 就行。")
        )
        #expect(creationReply.contains("坦克大战"))
        #expect(creationReply.contains("默认 MVP"))
        #expect(creationReply.contains("创建完成后"))
        #expect(!creationReply.contains("还缺一个明确交付目标"))
        #expect(!creationReply.contains("坦克大战网页游戏"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "坦克大战")

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        #expect(jobSnapshot.jobs.count == 1)
    }

    @Test
    func goalFollowUpBootstrapsExistingProjectWithoutCreatingSecondProject() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "supervisor-goal-follow-up-bootstrap")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        _ = try #require(
            manager.directSupervisorActionIfApplicableForTesting("新建项目，名字叫 坦克大战")
        )
        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        let followUpReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting("我要用默认的MVP。")
        )
        #expect(followUpReply.contains("《坦克大战》已经建好了"))
        #expect(followUpReply.contains("默认 MVP"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "坦克大战")

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        let planSnapshot = SupervisorProjectPlanStore.load(for: ctx)
        #expect(jobSnapshot.jobs.count == 1)
        #expect(planSnapshot.plans.count == 1)
        #expect(manager.messages.contains(where: { $0.content.contains("第一版工单挂给 Project AI") }))
    }

    @Test
    func minimumRunnableVersionFollowUpBootstrapsExistingProjectWithoutCreatingSecondProject() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "supervisor-goal-follow-up-minimum-runnable")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        _ = try #require(
            manager.directSupervisorActionIfApplicableForTesting("新建项目，名字叫 坦克大战")
        )
        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        let followUpReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting("第一版先做成最小可运行版本。")
        )
        #expect(followUpReply.contains("《坦克大战》已经建好了"))
        #expect(followUpReply.contains("最小可运行"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "坦克大战")

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        let planSnapshot = SupervisorProjectPlanStore.load(for: ctx)
        let job = try #require(jobSnapshot.jobs.first)
        #expect(job.goal.contains("最小可运行"))
        #expect(planSnapshot.plans.count == 1)
        #expect(manager.messages.contains(where: { $0.content.contains("第一版工单挂给 Project AI") }))
    }

    @Test
    func mixedLanguageCreateProjectPhrasePromptsForGoal() throws {
        let manager = SupervisorManager.makeForTesting()

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("创建一个project")
        )

        #expect(rendered.contains("还没给项目名"))
        #expect(rendered.contains("新建项目，名字叫 俄罗斯方块"))
    }

    @Test
    func negativeProjectCreationInstructionWithInlineGoalDoesNotAutoCreate() throws {
        let manager = SupervisorManager.makeForTesting()

        let rendered = manager.directSupervisorActionIfApplicableForTesting(
            "先别立项，我想做个俄罗斯方块网页游戏"
        )

        #expect(rendered == nil)
    }

    @Test
    func createProjectDiagnosticQuestionDoesNotTriggerCreateAction() throws {
        let manager = SupervisorManager.makeForTesting()

        let rendered = manager.directSupervisorActionIfApplicableForTesting("为什么创建不了项目")

        #expect(rendered == nil)
    }

    @Test
    func createProjectDiagnosticQuestionReturnsActionableReply() throws {
        let manager = SupervisorManager.makeForTesting()

        let rendered = try #require(
            manager.directSupervisorReplyIfApplicableForTesting("为什么创建不了项目")
        )

        #expect(rendered.contains("这类句子我会先当成诊断"))
        #expect(rendered.contains("诊断码：create_context_missing"))
        #expect(rendered.contains("立项"))
        #expect(rendered.contains("创建一个project"))
        #expect(rendered.contains("新建项目，名字叫 俄罗斯方块"))
    }

    @Test
    func createProjectDiagnosticReplyUsesPendingIntakeContextWhenAvailable() throws {
        let manager = SupervisorManager.makeForTesting()

        let intakeReply = try #require(
            manager.directSupervisorReplyIfApplicableForTesting(
                "我要做个贪食蛇游戏，你能做个详细工单发给project AI去推进吗"
            )
        )
        #expect(intakeReply.contains("按默认方案建项目"))

        let rendered = try #require(
            manager.directSupervisorReplyIfApplicableForTesting("为什么我说立项它还是没反应")
        )

        #expect(rendered.contains("诊断码：create_trigger_required_pending_intake"))
        #expect(rendered.contains("贪食蛇游戏"))
        #expect(rendered.contains("立项"))
        #expect(rendered.contains("创建一个project"))
        #expect(rendered.contains("第一版工单"))
    }

    @Test
    func projectCreationStatusPresentationShowsAwaitingGoalAfterBareCreateRequest() throws {
        let manager = SupervisorManager.makeForTesting()

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("创建一个project")
        )
        #expect(rendered.contains("还没给项目名"))

        let presentation = try #require(
            manager.supervisorProjectCreationStatusPresentationForTesting()
        )

        #expect(presentation.reasonCode == "create_goal_missing")
        #expect(presentation.headlineText == "项目创建缺目标")
        #expect(presentation.detailText.contains("项目名"))
        #expect(presentation.detailText.contains("明确交付目标"))
        #expect(presentation.metadataText.contains("新建项目，名字叫 俄罗斯方块"))
        #expect(presentation.recommendedCommands == ["新建项目，名字叫 俄罗斯方块", "帮我做个俄罗斯方块网页游戏，然后立项"])
    }

    @Test
    func createProjectDiagnosticReplyExplainsProjectAlreadyExistsWhenAwaitingGoal() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "supervisor-create-diagnostic-awaiting-goal")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        _ = try #require(
            manager.directSupervisorActionIfApplicableForTesting("新建项目，名字叫 坦克大战")
        )
        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        let rendered = try #require(
            manager.directSupervisorReplyIfApplicableForTesting("为什么创建不了项目")
        )

        #expect(rendered.contains("项目已经先创建好了"))
        #expect(rendered.contains("诊断码：create_goal_missing"))
        #expect(rendered.contains("已创建项目：坦克大战"))
        #expect(rendered.contains("我要用默认的MVP"))
        #expect(!rendered.contains("新建项目，名字叫 俄罗斯方块"))
    }

    @Test
    func projectCreationStatusPresentationShowsCreatedProjectAwaitingGoalAfterNamedCreate() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "supervisor-status-created-awaiting-goal")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        _ = try #require(
            manager.directSupervisorActionIfApplicableForTesting("新建项目，名字叫 坦克大战")
        )
        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        let presentation = try #require(
            manager.supervisorProjectCreationStatusPresentationForTesting()
        )

        #expect(presentation.reasonCode == "create_goal_missing")
        #expect(presentation.headlineText == "项目已创建待补目标")
        #expect(presentation.detailText.contains("《坦克大战》已经创建完成"))
        #expect(presentation.metadataText.contains("我要用默认的MVP"))
        #expect(presentation.projectNameText == "坦克大战")
        #expect(presentation.recommendedCommands == ["我要用默认的MVP", "第一版先做成最小可运行版本"])
    }

    @Test
    func projectCreationStatusPresentationRecoversRecentProposalWithoutCurrentUserMessage() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.messages.append(
            SupervisorMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: """
现在真正的卡点不是想法，而是**系统里还没有这个项目**。
你前面要做的是**俄罗斯方块**，我这边默认理解为：
- 项目名：**俄罗斯方块**
- 形态：**完整版单机 Web 版**
- 下一步：**先建项目，再补 job + initial plan**

如果你现在是要我继续推进，你下一句只要回：
**就按这个建**
我就接着往下走。
""",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        )

        let presentation = try #require(
            manager.supervisorProjectCreationStatusPresentationForTesting()
        )

        #expect(presentation.reasonCode == "create_trigger_required_recovered_proposal")
        #expect(presentation.headlineText == "项目创建待确认")
        #expect(presentation.detailText.contains("俄罗斯方块"))
        #expect(presentation.projectNameText == "俄罗斯方块")
        #expect(presentation.goalText == "俄罗斯方块")
        #expect(presentation.trackText == "完整版单机 Web 版")
        #expect(presentation.recommendedCommands == ["立项", "创建一个project", "就按这个建"])
    }

    @Test
    func negativeCreateProjectInstructionDoesNotTriggerCreateAction() throws {
        let manager = SupervisorManager.makeForTesting()

        let rendered = manager.directSupervisorActionIfApplicableForTesting("先别创建项目")

        #expect(rendered == nil)
    }

    @Test
    func executionIntakeConfirmationPhraseCreatesProjectAndBootstrapsWorkOrder() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "supervisor-execution-intake-confirmation")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let intakeReply = try #require(
            manager.directSupervisorReplyIfApplicableForTesting(
                "帮我做个俄罗斯方块游戏，先按默认骨架起起来"
            )
        )
        #expect(intakeReply.contains("按默认方案建项目"))

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting("就按这个建")
        )
        #expect(creationReply.contains("俄罗斯方块"))
        #expect(creationReply.contains("创建完成后"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName.contains("俄罗斯方块"))

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        #expect(jobSnapshot.jobs.count == 1)
        #expect(manager.messages.contains(where: { $0.content.contains("第一版工单挂给 Project AI") }))
    }

    @Test
    func explicitCreateProjectTagInitializesProjectMemoryBoundary() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "supervisor-create-project-boundary")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        let rendered = manager.processSupervisorResponseForTesting(
            """
            我先把项目建起来。
            [CREATE_PROJECT]俄罗斯方块[/CREATE_PROJECT]
            """,
            userMessage: "请创建项目 俄罗斯方块"
        )

        #expect(rendered.contains("✅ 正在创建项目：俄罗斯方块"))

        for _ in 0..<20 {
            if let project = appModel.registry.projects.first,
               let ctx = appModel.projectContext(for: project.projectId),
               AXProjectStore.loadMemoryIfPresent(for: ctx) != nil {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let memory = try #require(AXProjectStore.loadMemoryIfPresent(for: ctx))

        #expect(project.displayName == "俄罗斯方块")
        #expect(config.preferHubMemory)
        #expect(memory.projectName == "俄罗斯方块")
        #expect(FileManager.default.fileExists(atPath: ctx.memoryJSONURL.path))
        #expect(FileManager.default.fileExists(atPath: ctx.memoryMarkdownURL.path))
    }

    @Test
    func projectCreationConfirmationPhraseRecoversRecentAssistantProposalAndCreatesProject() async throws {
        let manager = SupervisorManager.makeForTesting()
        let registryBase = try makeProjectRoot(named: "supervisor-recovered-proposal-projects-base")
        defer { try? FileManager.default.removeItem(at: registryBase) }

        let envKey = "XTERMINAL_PROJECT_REGISTRY_BASE_DIR"
        let originalEnv = currentEnvironmentValue(envKey)
        setenv(envKey, registryBase.path, 1)
        defer {
            if let originalEnv {
                setenv(envKey, originalEnv, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.messages.append(
            SupervisorMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: """
现在真正的卡点不是想法，而是**系统里还没有这个项目**。
你前面要做的是**俄罗斯方块**，我这边默认理解为：
- 项目名：**俄罗斯方块**
- 形态：**完整版单机 Web 版**
- 下一步：**先建项目，再补 job + initial plan**

如果你现在是要我继续推进，你下一句只要回：
**就按这个建**
我就接着往下走。
""",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        )

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting("就按这个建")
        )
        #expect(creationReply.contains("俄罗斯方块"))
        #expect(creationReply.contains("创建完成后"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "俄罗斯方块")
        #expect(project.rootPath.hasPrefix(registryBase.appendingPathComponent("Projects", isDirectory: true).path))

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        #expect(jobSnapshot.jobs.count == 1)
    }

    @Test
    func chuangLiYiGeXiangMuRecoversRecentAssistantProposalAndCreatesProject() async throws {
        let manager = SupervisorManager.makeForTesting()
        let registryBase = try makeProjectRoot(named: "supervisor-chuangli-projects-base")
        defer { try? FileManager.default.removeItem(at: registryBase) }

        let envKey = "XTERMINAL_PROJECT_REGISTRY_BASE_DIR"
        let originalEnv = currentEnvironmentValue(envKey)
        setenv(envKey, registryBase.path, 1)
        defer {
            if let originalEnv {
                setenv(envKey, originalEnv, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.messages.append(
            SupervisorMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: """
现在真正的卡点不是想法，而是**系统里还没有这个项目**。
你前面要做的是**俄罗斯方块**，我这边默认理解为：
- 项目名：**俄罗斯方块**
- 形态：**完整版单机 Web 版**
- 下一步：**先建项目，再补 job + initial plan**

如果你现在是要我继续推进，你下一句只要回：
**就按这个建**
我就接着往下走。
""",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        )

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting("那就创立一个项目")
        )
        #expect(creationReply.contains("俄罗斯方块"))
        #expect(creationReply.contains("创建完成后"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "俄罗斯方块")
        #expect(project.rootPath.hasPrefix(registryBase.appendingPathComponent("Projects", isDirectory: true).path))

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        #expect(jobSnapshot.jobs.count == 1)
    }

    @Test
    func xinJianDuLiXiangMuRecoversRecentAssistantProposalAndCreatesProject() async throws {
        let manager = SupervisorManager.makeForTesting()
        let registryBase = try makeProjectRoot(named: "supervisor-new-independent-projects-base")
        defer { try? FileManager.default.removeItem(at: registryBase) }

        let envKey = "XTERMINAL_PROJECT_REGISTRY_BASE_DIR"
        let originalEnv = currentEnvironmentValue(envKey)
        setenv(envKey, registryBase.path, 1)
        defer {
            if let originalEnv {
                setenv(envKey, originalEnv, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.messages.append(
            SupervisorMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: """
我更推荐第二种，原因很简单：更可追溯，也更不容易把旧的脏上下文继续带进去。
你前面要做的是**坦克大战网页游戏**，我这边默认理解为：
- 项目名：**坦克大战网页游戏**
- 形态：**完整版单机 Web 版**

如果你决定拆成新盘，你只要回我一句：
- `新建独立项目`
或
- `直接重命名`
我就按这个方向继续给你下一步。
""",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        )

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting("新建独立项目")
        )
        #expect(creationReply.contains("坦克大战"))
        #expect(creationReply.contains("创建完成后"))
        #expect(!creationReply.contains("还缺一个明确交付目标"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName.contains("坦克大战"))
    }

    @Test
    func explicitProjectCreationWithProjectNameOverrideUsesRecoveredProposalGoal() async throws {
        let manager = SupervisorManager.makeForTesting()
        let registryBase = try makeProjectRoot(named: "supervisor-project-name-override-projects-base")
        defer { try? FileManager.default.removeItem(at: registryBase) }

        let envKey = "XTERMINAL_PROJECT_REGISTRY_BASE_DIR"
        let originalEnv = currentEnvironmentValue(envKey)
        setenv(envKey, registryBase.path, 1)
        defer {
            if let originalEnv {
                setenv(envKey, originalEnv, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.messages.append(
            SupervisorMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: """
我更推荐第二种，原因很简单：更可追溯，也更不容易把旧的脏上下文继续带进去。
你前面要做的是**坦克大战网页游戏**，我这边默认理解为：
- 项目名：**坦克大战网页游戏**
- 形态：**完整版单机 Web 版**

如果你决定拆成新盘，你只要回我一句：
- `新建独立项目`
或
- `直接重命名`
我就按这个方向继续给你下一步。
""",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        )

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting("新建项目，名字叫 坦克大战")
        )
        #expect(creationReply.contains("坦克大战"))
        #expect(creationReply.contains("创建完成后"))
        #expect(!creationReply.contains("还缺一个明确交付目标"))
        #expect(creationReply.contains("坦克大战网页游戏"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "坦克大战")

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        #expect(jobSnapshot.jobs.count == 1)
    }

    @Test
    func explicitProjectCreationWithDefaultMVPSignalAndNameOverrideCreatesProjectInSingleTurn() async throws {
        let manager = SupervisorManager.makeForTesting()
        let registryBase = try makeProjectRoot(named: "supervisor-default-mvp-projects-base")
        defer { try? FileManager.default.removeItem(at: registryBase) }

        let envKey = "XTERMINAL_PROJECT_REGISTRY_BASE_DIR"
        let originalEnv = currentEnvironmentValue(envKey)
        setenv(envKey, registryBase.path, 1)
        defer {
            if let originalEnv {
                setenv(envKey, originalEnv, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "你建立一个项目，名字就叫 坦克大战。我要用默认的MVP。"
            )
        )
        #expect(creationReply.contains("坦克大战"))
        #expect(creationReply.contains("默认 MVP"))
        #expect(creationReply.contains("创建完成后"))
        #expect(!creationReply.contains("还缺一个明确交付目标"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "坦克大战")

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        #expect(jobSnapshot.jobs.count == 1)
    }

    @Test
    func recoveredProposalContextStillAllowsSingleTurnProjectCreationWithDefaultMVPSignal() async throws {
        let manager = SupervisorManager.makeForTesting()
        let registryBase = try makeProjectRoot(named: "supervisor-default-mvp-recovered-proposal")
        defer { try? FileManager.default.removeItem(at: registryBase) }

        let envKey = "XTERMINAL_PROJECT_REGISTRY_BASE_DIR"
        let originalEnv = currentEnvironmentValue(envKey)
        setenv(envKey, registryBase.path, 1)
        defer {
            if let originalEnv {
                setenv(envKey, originalEnv, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.messages.append(
            SupervisorMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: """
我更推荐第二种，原因很简单：更可追溯，也更不容易把旧的脏上下文继续带进去。
你前面要做的是**坦克大战网页游戏**，我这边默认理解为：
- 项目名：**坦克大战网页游戏**
- 形态：**完整版单机 Web 版**

如果你决定拆成新盘，你只要回我一句：
- `新建独立项目`
或
- `直接重命名`
我就按这个方向继续给你下一步。
""",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        )

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "你建立一个项目，名字就叫 坦克大战。我要用默认的MVP。"
            )
        )
        #expect(creationReply.contains("坦克大战"))
        #expect(creationReply.contains("默认 MVP"))
        #expect(creationReply.contains("创建完成后"))
        #expect(!creationReply.contains("还缺一个明确交付目标"))
        #expect(!creationReply.contains("坦克大战网页游戏"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        #expect(appModel.registry.projects.count == 1)
        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "坦克大战")

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let jobSnapshot = SupervisorProjectJobStore.load(for: ctx)
        #expect(jobSnapshot.jobs.count == 1)
    }

    @Test
    func explicitProjectCreationWithMarkdownWrappedNameSanitizesDisplayNameAndDirectory() async throws {
        let manager = SupervisorManager.makeForTesting()
        let registryBase = try makeProjectRoot(named: "supervisor-default-mvp-projects-base-markdown")
        defer { try? FileManager.default.removeItem(at: registryBase) }

        let envKey = "XTERMINAL_PROJECT_REGISTRY_BASE_DIR"
        let originalEnv = currentEnvironmentValue(envKey)
        setenv(envKey, registryBase.path, 1)
        defer {
            if let originalEnv {
                setenv(envKey, originalEnv, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)

        let creationReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "你建立一个项目，名字就叫 `坦克大战`。我要用默认的MVP。"
            )
        )
        #expect(creationReply.contains("坦克大战"))
        #expect(!creationReply.contains("`坦克大战`"))

        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        let project = try #require(appModel.registry.projects.first)
        #expect(project.displayName == "坦克大战")
        #expect(project.rootPath.contains("`坦克大战`") == false)
        #expect(project.rootPath.hasSuffix("/坦克大战") == true)
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
    func stepLockedRescueRejectsSingleStepPlan() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-step-locked-rescue-single-step")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s4TightSupervision
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let createRendered = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"亮亮","goal":"救火修复 browser runtime","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "给亮亮建一个任务：救火修复 browser runtime"
        )
        #expect(createRendered.contains("✅ 已为项目 亮亮 创建任务：救火修复 browser runtime"))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            我会先写入一版 step_locked_rescue 救火计划。
            [UPSERT_PLAN]{"project_ref":"亮亮","job_id":"\#(job.jobId)","plan_id":"plan-rescue-single-step-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"直接修掉 browser runtime","kind":"call_skill","status":"pending","skill_id":"agent-browser"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划，给亮亮补一版救火计划"
        )

        #expect(rendered.contains("step_locked_rescue"))
        #expect(rendered.contains("计划至少需要 2 个步骤"))
        #expect(SupervisorProjectPlanStore.load(for: ctx).plans.isEmpty)
    }

    @Test
    func stepLockedRescueAutoChainsDependenciesAndBackfillsDetails() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-step-locked-rescue-normalize")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s4TightSupervision
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let createRendered = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"亮亮","goal":"逐步修复 browser runtime","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "给亮亮建一个任务：逐步修复 browser runtime"
        )
        #expect(createRendered.contains("✅ 已为项目 亮亮 创建任务：逐步修复 browser runtime"))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            我会先写入一版逐步 rescue 计划。
            [UPSERT_PLAN]{"project_ref":"亮亮","job_id":"\#(job.jobId)","plan_id":"plan-rescue-ordered-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"采集当前 browser runtime 失败证据","kind":"call_skill","status":"running","skill_id":"agent-browser"},{"step_id":"step-002","title":"根据失败证据生成修复动作","kind":"write_memory","status":"pending"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划，给亮亮补一版逐步救火计划"
        )

        #expect(rendered.contains("✅ 已为项目 亮亮 写入计划：plan-rescue-ordered-v1"))
        #expect(rendered.contains("depth=step_locked_rescue"))
        #expect(rendered.contains("auto_normalized="))

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps.count == 2)
        #expect(plan.steps[0].detail == "采集当前 browser runtime 失败证据")
        #expect(plan.steps[1].detail == "根据失败证据生成修复动作")
        #expect(plan.steps[1].dependsOn == ["step-001"])

        let rawEntries = try readRawLogEntries(at: ctx.rawLogURL)
        let rawPlan = try #require(rawEntries.last(where: { ($0["type"] as? String) == "supervisor_plan" }))
        #expect(rawPlan["effective_work_order_depth"] as? String == "step_locked_rescue")
        #expect(rawPlan["effective_supervisor_tier"] as? String == "s4_tight_supervision")
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

        #expect(localMemory.contains("[PORTFOLIO_BRIEF]"))
        #expect(localMemory.contains("[FOCUSED_PROJECT_ANCHOR_PACK]"))
        #expect(localMemory.contains("[LONGTERM_OUTLINE]"))
        #expect(localMemory.contains("[DELTA_FEED]"))
        #expect(localMemory.contains("focus_source: explicit_user_mention"))
        #expect(localMemory.contains("project: 亮亮 ("))
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

        #expect(localMemory.contains("[FOCUSED_PROJECT_ANCHOR_PACK]"))
        #expect(localMemory.contains("[LONGTERM_OUTLINE]"))
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

        #expect(localMemory.contains("[FOCUSED_PROJECT_ANCHOR_PACK]"))
        #expect(localMemory.contains("[LONGTERM_OUTLINE]"))
        #expect(localMemory.contains("done_definition: review 必须能防跑偏、看质量，并在需要时提出更好的路径"))
        #expect(localMemory.contains("constraints:"))
        #expect(localMemory.contains("non_goals: 不要把 supervisor 做成僵硬 checklist agent"))
        #expect(localMemory.contains("approved_decisions:"))
        #expect(localMemory.contains("scope_freeze=Supervisor review 必须保留自由度"))
        #expect(localMemory.contains("longterm_outline:"))
        #expect(localMemory.contains("strategic_milestones:"))
        #expect(localMemory.contains("approved_tech_stack: SwiftUI | Hub-governed memory"))
        #expect(localMemory.contains("governance:"))
        #expect(localMemory.contains("latest_review_note:"))
        #expect(localMemory.contains("latest_review_note=(none)"))
        #expect(localMemory.contains("latest_guidance_injection:"))
        #expect(localMemory.contains("latest_guidance_injection=(none)"))
        #expect(localMemory.contains("pending_ack_guidance:"))
        #expect(localMemory.contains("pending_ack_guidance=(none)"))
        #expect(localMemory.contains("constraints=non_goals=不要把 supervisor 做成僵硬 checklist agent"))
        #expect(localMemory.contains("approved_decisions=scope_freeze=Supervisor review 必须保留自由度"))
        #expect(localMemory.contains("longterm_outline=project: 亮亮 ("))
    }

    @Test
    func localMemoryFocusedProjectBriefIncludesAdaptiveGovernanceRuntimeLines() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-adaptive-governance")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "审查亮亮项目的上下文记忆，给出最具体的执行方案"
        )

        #expect(localMemory.contains("runtime_surface: configured=manual effective=manual"))
        #expect(localMemory.contains("execution_tier: configured=a3_deliver_auto effective=a3_deliver_auto"))
        #expect(localMemory.contains("supervisor_tier: configured=s2_periodic_review baseline_recommended=s3_strategic_coach recommended=s3_strategic_coach effective=s3_strategic_coach"))
        #expect(localMemory.contains("work_order_depth: recommended=execution_ready effective=execution_ready adaptation_mode=raise_only"))
        #expect(localMemory.contains("project_ai_strength: band=unknown"))
        #expect(localMemory.contains("project_ai_strength_reasons: recent project evidence is still sparse"))
        #expect(localMemory.contains("governance=exec=a3_deliver_auto supervisor=s2_periodic_review->s3_strategic_coach depth=execution_ready strength=unknown"))
        #expect(!localMemory.contains("autonomy: configured="))
    }

    @Test
    func localMemoryNormalizesLegacyAutonomyConstraintNotesWithoutFakeDelta() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-legacy-constraint-normalization")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        manager.captureSupervisorReviewNoteForTesting(
            userMessage: "审查亮亮项目当前状态",
            response: """
            当前路径正常，继续按现有约束推进。
            1. 保持当前执行边界。
            2. 继续沿着已确认步骤推进。
            """,
            triggerSource: "user_turn"
        )

        let latest = try #require(SupervisorReviewNoteStore.latest(for: ctx))
        var legacyCompatNote = latest
        legacyCompatNote.anchorConstraints = latest.anchorConstraints.map { item in
            item.replacingOccurrences(of: "surface=", with: "autonomy=")
        }
        try SupervisorReviewNoteStore.upsert(legacyCompatNote, for: ctx)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续执行当前项目")

        #expect(localMemory.contains("constraints=surface=manual->manual | override=none"))
        #expect(!localMemory.contains("constraints/guardrails changed since last review"))
        #expect(!localMemory.contains("before=autonomy=manual->manual"))
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
        #expect(note.memoryCursor?.contains("review:") == true)
        #expect(note.projectStateHash?.contains("sha256:") == true)
        #expect(note.portfolioStateHash?.contains("sha256:") == true)

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
    func captureSupervisorReviewNoteCarriesAdaptiveGovernanceAndWorkOrderRef() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-review-note-adaptive-governance")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"亮亮","goal":"补齐 review follow-up","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "给亮亮建一个任务：补齐 review follow-up"
        )
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            我会先写入一版 execution-ready 计划。
            [UPSERT_PLAN]{"project_ref":"亮亮","job_id":"\#(job.jobId)","plan_id":"plan-review-follow-up-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"读取当前 review anchor","kind":"write_memory","status":"running"},{"step_id":"step-002","title":"生成后续执行方案","kind":"write_memory","status":"pending"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划，给亮亮补一版 execution-ready 计划"
        )

        manager.captureSupervisorReviewNoteForTesting(
            userMessage: "审查亮亮项目的上下文记忆，给出更稳的执行方案",
            response: """
            当前方向可以继续，但需要更明确的执行工单。
            1. 先固定 review anchor。
            2. 再按现有计划逐步补强执行细节。
            """,
            triggerSource: "user_turn"
        )

        let note = try #require(SupervisorReviewNoteStore.load(for: ctx).notes.first)
        #expect(note.effectiveSupervisorTier == .s3StrategicCoach)
        #expect(note.effectiveWorkOrderDepth == .executionReady)
        #expect(note.projectAIStrengthBand == .unknown)
        #expect(note.workOrderRef == "plan:plan-review-follow-up-v1")

        let guidance = try #require(SupervisorGuidanceInjectionStore.load(for: ctx).items.first)
        #expect(guidance.effectiveSupervisorTier == .s3StrategicCoach)
        #expect(guidance.effectiveWorkOrderDepth == .executionReady)
        #expect(guidance.workOrderRef == "plan:plan-review-follow-up-v1")
        #expect(guidance.guidanceText.contains("effective_work_order_depth=execution_ready"))
        #expect(guidance.guidanceText.contains("work_order_ref=plan:plan-review-follow-up-v1"))
    }

    @Test
    func captureSupervisorReviewNoteExecutionReadyPrependsStructuredWorkOrderActions() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-review-note-execution-ready-actions")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"亮亮","goal":"补齐 review work order","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "给亮亮建一个任务：补齐 review work order"
        )
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            我会先写入一版 execution-ready 计划。
            [UPSERT_PLAN]{"project_ref":"亮亮","job_id":"\#(job.jobId)","plan_id":"plan-review-work-order-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"固定 review anchor","kind":"write_memory","status":"running"},{"step_id":"step-002","title":"生成具体 follow-up 工单","kind":"write_memory","status":"pending"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划，给亮亮补一版 execution-ready 计划"
        )

        manager.captureSupervisorReviewNoteForTesting(
            userMessage: "审查亮亮项目的上下文记忆，给出更稳的执行方案",
            response: """
            当前方向可以继续。
            1. 继续推进当前路径。
            2. 补一下后续计划。
            """,
            triggerSource: "user_turn"
        )

        let note = try #require(SupervisorReviewNoteStore.load(for: ctx).notes.first)
        #expect(note.effectiveWorkOrderDepth == .executionReady)
        #expect(note.recommendedActions.first?.contains("execution-ready 工单") == true)
        #expect(note.recommendedActions.first?.contains("step-002") == true)
        #expect(note.recommendedActions.contains(where: { $0.contains("plan-review-work-order-v1") }))

        let guidance = try #require(SupervisorGuidanceInjectionStore.load(for: ctx).items.first)
        #expect(guidance.guidanceText.contains("actions="))
        #expect(guidance.guidanceText.contains("execution-ready 工单"))
    }

    @Test
    func captureSupervisorReviewNoteStepLockedRescuePrependsSingleUnblockDiscipline() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-review-note-step-locked-actions")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s4TightSupervision
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"亮亮","goal":"救火修复 browser runtime","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "给亮亮建一个任务：救火修复 browser runtime"
        )
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            我会先写入一版 rescue 计划。
            [UPSERT_PLAN]{"project_ref":"亮亮","job_id":"\#(job.jobId)","plan_id":"plan-browser-rescue-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"回收 browser runtime 失败证据","kind":"call_skill","status":"blocked","skill_id":"agent-browser"},{"step_id":"step-002","title":"按证据生成修复动作","kind":"write_memory","status":"pending"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划，给亮亮补一版救火计划"
        )

        manager.captureSupervisorReviewNoteForTesting(
            userMessage: "审查亮亮项目的上下文记忆，给出救火方案",
            response: """
            当前方向可以继续。
            1. 继续推进当前路径。
            2. 补一下后续计划。
            """,
            triggerSource: "user_turn"
        )

        let note = try #require(SupervisorReviewNoteStore.load(for: ctx).notes.first)
        #expect(note.effectiveWorkOrderDepth == .stepLockedRescue)
        #expect(note.recommendedActions.first?.contains("step_locked_rescue") == true)
        #expect(note.recommendedActions.first?.contains("step-001") == true)
        #expect(note.recommendedActions.contains(where: { $0.contains("depends_on") || $0.contains("验证/回滚检查点") }))

        let guidance = try #require(SupervisorGuidanceInjectionStore.load(for: ctx).items.first)
        #expect(guidance.guidanceText.contains("step_locked_rescue"))
        #expect(guidance.guidanceText.contains("只推进"))
    }

    @Test
    func captureSupervisorReviewNoteStrongProjectKeepsAnchoredExecutionActionsFlexible() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-review-note-strong-flexible-actions")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)
        try seedStrongProjectAIStrengthEvidence(ctx: ctx, projectID: project.projectId)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"亮亮","goal":"补齐 review work order","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "给亮亮建一个任务：补齐 review work order"
        )
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            我会先写入一版 execution-ready 计划。
            [UPSERT_PLAN]{"project_ref":"亮亮","job_id":"\#(job.jobId)","plan_id":"plan-review-work-order-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"固定 review anchor","kind":"write_memory","status":"running"},{"step_id":"step-002","title":"生成具体 follow-up 工单","kind":"write_memory","status":"pending"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划，给亮亮补一版 execution-ready 计划"
        )

        manager.captureSupervisorReviewNoteForTesting(
            userMessage: "审查亮亮项目的上下文记忆，给出更稳的执行方案",
            response: """
            当前方向可以继续。
            1. 先固定 step-001 review anchor，并把 step-002 的输入输出约束补齐。
            2. 再推进 step-002 生成具体 follow-up 工单，回执里带上 plan-review-work-order-v1 的更新摘要。
            """,
            triggerSource: "user_turn"
        )

        let note = try #require(SupervisorReviewNoteStore.load(for: ctx).notes.first)
        #expect(note.projectAIStrengthBand == .strong)
        #expect(note.effectiveWorkOrderDepth == .executionReady)
        #expect(note.recommendedActions.first?.contains("step-001") == true)
        #expect(note.recommendedActions.contains(where: { $0.contains("step-002") }))
        #expect(note.recommendedActions.contains(where: { $0.contains("plan-review-work-order-v1") }))
        #expect(!note.recommendedActions.contains(where: { $0.contains("execution-ready 工单") }))

        let guidance = try #require(SupervisorGuidanceInjectionStore.load(for: ctx).items.first)
        #expect(guidance.guidanceText.contains("step-001"))
        #expect(guidance.guidanceText.contains("plan-review-work-order-v1"))
        #expect(!guidance.guidanceText.contains("execution-ready 工单"))
    }

    @Test
    func captureSupervisorReviewNoteFlagsUnderfedStrategicMemory() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-review-note-memory-underfed")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeSupervisorMemoryAssemblySnapshot(
                projectID: project.projectId,
                profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                contextRefsSelected: 0,
                evidenceItemsSelected: 0,
                omittedSections: [
                    "focused_project_anchor_pack",
                    "longterm_outline",
                    "evidence_pack",
                ],
                truncatedLayers: ["l1_canonical"]
            )
        )

        manager.captureSupervisorReviewNoteForTesting(
            userMessage: "审查亮亮项目的上下文记忆，直接做战略纠偏",
            response: """
            当前路径可能需要调整。
            1. 先重新审查最近的实现方向。
            2. 再决定是否重写执行计划。
            """,
            triggerSource: "user_turn"
        )

        let ctx = AXProjectContext(root: root)
        let snapshot = SupervisorReviewNoteStore.load(for: ctx)
        let note = try #require(snapshot.notes.first)
        #expect(note.summary.contains("当前 strategic memory 供给不足"))
        #expect(note.summary.contains("不适合直接做战略纠偏"))
        #expect(note.recommendedActions.contains(where: { $0.contains("先补齐长期目标和完成标准、关键决策原因、当前卡点与已试动作、以及可作为依据的日志或结果") }))
        #expect(note.recommendedActions.contains(where: { $0.contains("先把当前项目的深度记忆拉到至少 m3") }))
        #expect(note.recommendedActions.contains(where: { $0.contains("先补你认可的日志、回执、实验结果这些依据") }))
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
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)
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
        #expect(localMemory.contains("memory_cursor: review:"))
        #expect(localMemory.contains("project_state_hash: sha256:"))
        #expect(localMemory.contains("portfolio_state_hash: sha256:"))
        #expect(localMemory.contains("trigger: manual_request"))
        #expect(localMemory.contains("verdict: better_path_found"))
        #expect(localMemory.contains("delivery: coder/replan_request ack_required=true"))
        #expect(localMemory.contains("effective_work_order_depth: execution_ready"))
        #expect(localMemory.contains("work_order_ref:"))
        #expect(localMemory.contains("recommended_actions: 先把 latest review note 放进 focused brief。 | 再让 coder 默认读取最新 verdict 和 recommended actions。"))
        #expect(localMemory.contains("latest_review_note=cursor=review:"))
        #expect(localMemory.contains("verdict=better_path_found level=r2_strategic delivery=replan_request ack_required=true"))
        #expect(localMemory.contains("depth=execution_ready"))
        #expect(localMemory.contains("latest_guidance_injection:"))
        #expect(localMemory.contains("intervention_mode: replan_next_safe_point"))
        #expect(localMemory.contains("safe_point_policy: next_step_boundary"))
        #expect(localMemory.contains("ack_status: pending"))
        #expect(localMemory.contains("effective_work_order_depth: execution_ready"))
        #expect(localMemory.contains("pending_ack_guidance:"))
        #expect(localMemory.contains("pending_ack_guidance=ack_status=pending ack_required=true ack_note=(none) delivery=replan_request intervention=replan_next_safe_point safe_point=next_step_boundary depth=execution_ready"))
    }

    @Test
    func localMemoryDeltaFeedIncludesCursorHashesAndStructuredItems() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-delta-feed-structured")
        defer { try? FileManager.default.removeItem(at: root) }

        var project = makeProjectEntry(root: root, displayName: "亮亮")
        project.currentStateSummary = "旧状态：先收口 review anchor"
        project.nextStepSummary = "旧步骤：冻结目标和约束"
        project.blockerSummary = ""

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        let spec = SupervisorProjectSpecCapsuleBuilder.build(
            projectId: project.projectId,
            goal: "让 delta feed 能准确说明上次 review 后的变化",
            mvpDefinition: "delta feed 要给出 cursor/hash/materialized delta items",
            nonGoals: ["不要只给散乱 recent events"],
            approvedTechStack: ["SwiftUI", "Hub memory"],
            milestoneMap: [
                SupervisorProjectSpecMilestone(
                    milestoneId: "m1",
                    title: "先做结构化 delta feed",
                    status: .active
                )
            ]
        )
        try SupervisorProjectSpecCapsuleStore.save(spec, for: ctx)

        manager.captureSupervisorReviewNoteForTesting(
            userMessage: "审查亮亮项目的上下文记忆，并给出执行方案",
            response: """
            当前路径成立。
            1. 先冻结 review anchor。
            2. 然后只在发生 material changes 时重播背景。
            """,
            triggerSource: "user_turn"
        )

        project.currentStateSummary = "新状态：delta feed 已切到 cursor/hash"
        project.nextStepSummary = "新步骤：补 delta_items 和 guidance delta"
        project.blockerSummary = "需要验证 no_material_change 分支"
        appModel.registry = registry(with: [project])

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "继续审查亮亮项目的上下文记忆，并判断上次 review 之后发生了什么变化"
        )

        #expect(localMemory.contains("[DELTA_FEED]"))
        #expect(localMemory.contains("cursor_from: review:"))
        #expect(localMemory.contains("cursor_to: memory_build:"))
        #expect(localMemory.contains("project_state_hash_before: sha256:"))
        #expect(localMemory.contains("project_state_hash_after: sha256:"))
        #expect(localMemory.contains("portfolio_state_hash_before: sha256:"))
        #expect(localMemory.contains("portfolio_state_hash_after: sha256:"))
        #expect(localMemory.contains("delta_items:"))
        #expect(localMemory.contains("[progress_delta] current_state: before=旧状态：先收口 review anchor after=新状态：delta feed 已切到 cursor/hash"))
        #expect(localMemory.contains("[progress_delta] next_step: before=旧步骤：冻结目标和约束 after=新步骤：补 delta_items 和 guidance delta"))
        #expect(localMemory.contains("[blocker_delta] blocker: before=(none) after=需要验证 no_material_change 分支"))
    }

    @Test
    func localMemoryIncludesConflictSetContextRefsAndEvidencePack() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-serving-objects")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        let spec = SupervisorProjectSpecCapsuleBuilder.build(
            projectId: project.projectId,
            goal: "让 supervisor memory serving object 能稳定支撑战略纠偏",
            mvpDefinition: "冲突、来源索引、证据包都能直接喂给 supervisor",
            nonGoals: ["不要退回成只看最近消息的短记忆"],
            approvedTechStack: ["SwiftUI", "Hub memory"],
            milestoneMap: [
                SupervisorProjectSpecMilestone(
                    milestoneId: "m1",
                    title: "补齐 serving objects",
                    status: .active
                )
            ]
        )
        try SupervisorProjectSpecCapsuleStore.save(spec, for: ctx)

        let decision = SupervisorDecisionTrackBuilder.build(
            decisionId: "decision-memory-anchor",
            projectId: project.projectId,
            category: .scopeFreeze,
            status: .approved,
            statement: "先以长期 anchor 和 approved decisions 为准，再决定是否 replan。",
            source: "user_confirmed_protocol",
            reversible: true,
            approvalRequired: false,
            auditRef: "audit-memory-anchor",
            createdAtMs: 1_773_720_000_000
        )
        _ = try SupervisorDecisionTrackStore.upsert(decision, for: ctx)

        manager.captureSupervisorReviewNoteForTesting(
            userMessage: "审查亮亮项目的上下文记忆，并给我更稳的下一步",
            response: """
            当前方向基本对，但最新 guidance 需要把 replan 明确化。
            1. 先确认长期 anchor 与 approved decision 不被 recent noise 覆盖。
            2. 再按 latest review note 的建议调整执行顺序。
            """,
            triggerSource: "user_turn"
        )

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "继续审查亮亮项目的上下文记忆，并判断是否需要战略纠偏"
        )

        #expect(localMemory.contains("[CONFLICT_SET]"))
        #expect(localMemory.contains("conflict_kind: decision_vs_guidance"))
        #expect(localMemory.contains("resolution_status: pending_guidance_ack"))
        #expect(localMemory.contains("[CONTEXT_REFS]"))
        #expect(localMemory.contains("source_scope=spec_capsule"))
        #expect(localMemory.contains("source_scope=decision_track"))
        #expect(localMemory.contains("source_scope=review_note"))
        #expect(localMemory.contains("source_scope=guidance_injection"))
        #expect(localMemory.contains("[EVIDENCE_PACK]"))
        #expect(localMemory.contains("selected_items:"))
        #expect(localMemory.contains("why_included=latest_supervisor_verdict"))
        #expect(localMemory.contains("why_included=active_guidance_guardrail_pending_ack"))
        #expect(localMemory.contains("guidance=当前方向基本对，但最新 guidance 需要把 replan 明确化。"))
        #expect(!localMemory.contains("guidance=verdict="))
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
        #expect(localMemory.contains("guidance_summary: 改成更稳的 replan 路线。"))
        #expect(localMemory.contains("latest_guidance_injection=ack_status=rejected ack_required=true ack_note=Need extra evidence before moving the migration boundary."))
        #expect(localMemory.contains("guidance_summary=改成更稳的 replan 路线。"))
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
        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 写入计划：plan-browser-smoke-v1"))
        #expect(rendered.contains("job=\(job.jobId), steps=2"))
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
        #expect(plan.steps[0].skillId == "guarded-automation")
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
        #expect(localMemory.contains("guarded-automation"))
        #expect(localMemory.contains("browser.runtime.smoke"))
        #expect(localMemory.contains("step-001"))
    }

    @Test
    func executionReadyPlanBackfillsDetailForUnknownProjectAI() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-upsert-plan-unknown-detail-floor")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"亮亮","goal":"补一版执行计划","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "给亮亮建一个任务：补一版执行计划"
        )
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            我会先把路径写成 execution-ready 计划。
            [UPSERT_PLAN]{"project_ref":"亮亮","job_id":"\#(job.jobId)","plan_id":"plan-liang-execution-ready-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"固定 review anchor","kind":"write_memory","status":"running"},{"step_id":"step-002","title":"生成具体 follow-up 工单","kind":"write_memory","status":"pending"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划，给亮亮补一版 execution-ready 计划"
        )

        #expect(rendered.contains("depth=execution_ready"))
        #expect(rendered.contains("auto_normalized="))
        #expect(rendered.contains("detail_from_title:step-001"))
        #expect(rendered.contains("detail_from_title:step-002"))

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].detail == "固定 review anchor")
        #expect(plan.steps[1].detail == "生成具体 follow-up 工单")
    }

    @Test
    func strongProjectExecutionReadyPlanKeepsConciseSpecificStepsWithoutDetailBackfill() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-upsert-plan-strong-concise-detail")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)
        try seedStrongProjectAIStrengthEvidence(ctx: ctx, projectID: project.projectId)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"亮亮","goal":"补一版执行计划","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "给亮亮建一个任务：补一版执行计划"
        )
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            我会先把路径写成 execution-ready 计划。
            [UPSERT_PLAN]{"project_ref":"亮亮","job_id":"\#(job.jobId)","plan_id":"plan-liang-execution-ready-strong-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"固定 review anchor 并确认输入边界","kind":"write_memory","status":"running"},{"step_id":"step-002","title":"生成具体 follow-up 工单并带回 plan 更新摘要","kind":"write_memory","status":"pending","depends_on":["step-001"],"failure_policy":"replan"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划，给亮亮补一版 execution-ready 计划"
        )

        #expect(rendered.contains("depth=execution_ready"))
        #expect(!rendered.contains("auto_normalized="))

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].detail.isEmpty)
        #expect(plan.steps[1].detail.isEmpty)
        #expect(plan.steps[1].dependsOn == ["step-001"])
        #expect(plan.steps[1].failurePolicy == .replan)

        let rawEntries = try readRawLogEntries(at: ctx.rawLogURL)
        let rawPlan = try #require(rawEntries.last(where: { ($0["type"] as? String) == "supervisor_plan" }))
        #expect(rawPlan["project_ai_strength_band"] as? String == AXProjectAIStrengthBand.strong.rawValue)
        #expect(rawPlan["effective_work_order_depth"] as? String == AXProjectSupervisorWorkOrderDepth.executionReady.rawValue)
        #expect((rawPlan["plan_normalization_notes"] as? [String])?.isEmpty == true)
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

        #expect(rendered.contains("已为项目 \(project.displayName) 登记技能调用：browser.runtime.smoke"))
        #expect(rendered.contains("当前需要本地审批后才能继续"))
        #expect(!rendered.contains(root.lastPathComponent))

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
    func quarantinedSkillFailsClosedBeforeAuthorizationAndSurfacesRepairableActivity() throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-preflight-quarantine")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try writeOfficialSkillLifecycleFixture(
            hubBaseDir: fixture.hubBaseDir,
            packages: [
                [
                    "package_sha256": "9999999999999999999999999999999999999999999999999999999999999999",
                    "skill_id": "browser.runtime.smoke",
                    "name": "Browser Runtime Smoke",
                    "version": "2.0.0",
                    "risk_level": "high",
                    "requires_grant": true,
                    "package_state": "quarantined",
                    "overall_state": "blocked",
                    "blocking_failures": 1,
                    "transition_count": 1,
                    "updated_at_ms": 88,
                    "last_transition_at_ms": 88,
                    "last_ready_at_ms": 0,
                    "last_blocked_at_ms": 88
                ]
            ]
        )
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-preflight-quarantine-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        #expect(rendered.contains("preflight_quarantined"))
        #expect(rendered.contains("quarantine"))
        #expect(!rendered.contains(root.lastPathComponent))

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .blocked)
        #expect(call.denyCode == "preflight_quarantined")
        #expect(call.policySource == "skill_preflight")
        #expect(call.resultSummary.contains("quarantined"))
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)

        let blockedPlan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(blockedPlan.steps[0].status == .blocked)

        manager.refreshRecentSupervisorSkillActivitiesNow()
        let activity = try #require(manager.recentSupervisorSkillActivities.first(where: { $0.requestId == call.requestId }))
        let actions = SupervisorCardActionResolver.recentSkillActivityActions(activity)
        #expect(actions.map(\.label).contains("查看技能治理"))
    }

    @Test
    func missingHubSkillRegistrySurfacesBlockedSkillActivityWithStableReason() throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-registry-unavailable")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-registry-unavailable-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        #expect(rendered.contains("skill_registry_unavailable"))
        #expect(rendered.contains("Hub skill registry 当前不可用"))
        #expect(!rendered.contains(root.lastPathComponent))

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .blocked)
        #expect(call.skillId == "browser.runtime.smoke")
        #expect(call.denyCode == "skill_registry_unavailable")
        #expect(call.resultSummary.contains("Hub skill registry 当前不可用"))
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)

        let blockedPlan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(blockedPlan.steps[0].status == .blocked)
        #expect(blockedPlan.status == .blocked)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .blocked)
    }

    @Test
    func unregisteredSkillSurfacesBlockedSkillActivityWithStableReason() throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-not-registered")
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
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"运行未知 skill","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-skill-not-registered-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行未知 skill","kind":"call_skill","status":"pending","skill_id":"browser.runtime.unknown"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.unknown","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行未知 browser 技能"
        )

        #expect(rendered.contains("skill_not_registered"))
        #expect(rendered.contains("不在当前 project scope 的 Hub registry"))
        #expect(!rendered.contains(root.lastPathComponent))

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .blocked)
        #expect(call.skillId == "browser.runtime.unknown")
        #expect(call.denyCode == "skill_not_registered")
        #expect(call.resultSummary.contains("不在当前 project scope 的 Hub registry"))
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)

        let blockedPlan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(blockedPlan.steps[0].status == .blocked)
        #expect(blockedPlan.status == .blocked)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .blocked)
    }

    @Test
    func missingMultimodalWrapperSuggestsGlobalDiscoverAndEnableFlow() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-missing-multimodal-wrapper")
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
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"理解图片内容","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-missing-local-vision-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"用图片理解 wrapper 看图","kind":"call_skill","status":"pending","skill_id":"local-vision"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"local-vision","payload":{"image_path":"./tmp/example.png"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 local-vision 技能"
        )

        #expect(rendered.contains("skill_not_registered"))
        #expect(rendered.contains("local-vision"))
        #expect(rendered.contains("CALL_GLOBAL_SKILL"))
        #expect(rendered.contains("find-skills"))
        #expect(rendered.contains("request-skill-enable"))
        #expect(rendered.contains("package_sha256"))
        #expect(rendered.contains("multimodal"))

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .blocked)
        #expect(call.skillId == "local-vision")
        #expect(call.denyCode == "skill_not_registered")
        #expect(call.resultSummary.contains("当前项目还没有 `local-vision`"))
        #expect(call.resultSummary.contains("find-skills"))
        #expect(call.resultSummary.contains("request-skill-enable"))
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)
    }

    @Test
    func hiddenProjectInternalCancelSkillWorksWithoutExplicitProjectRef() throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-hidden-project-internal-cancel")
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-hidden-cancel-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .awaitingAuthorization)

        let now = Date(timeIntervalSince1970: 1_773_384_300).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CANCEL_SKILL]{"request_id":"\#(call.requestId)","reason":"系统取消隐藏项目技能调用"}[/CANCEL_SKILL]
            """#,
            userMessage: "trigger=approval_resolution",
            triggerSource: "approval_resolution"
        )

        #expect(rendered.contains("✅ 已取消项目 \(project.displayName) 的技能调用：browser.runtime.smoke"))
        #expect(!rendered.contains(root.lastPathComponent))

        let canceledCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(canceledCall.status == .canceled)
        #expect(canceledCall.resultSummary.contains("系统取消隐藏项目技能调用"))

        let canceledPlan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(canceledPlan.steps[0].status == .canceled)
        #expect(canceledPlan.status == .canceled)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .canceled)
    }

    @Test
    func hiddenProjectInternalMemoryAssemblyUsesKnownProjects() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-hidden-project-memory-assembly")
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-hidden-memory-assembly-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let now = Date(timeIntervalSince1970: 1_773_384_360).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        let userMessage = """
        trigger=grant_resolution
        project_ref=\(project.displayName)
        project_id=\(project.projectId)
        job_id=\(job.jobId)
        plan_id=plan-hidden-memory-assembly-v1
        step_id=step-001
        reason_code=grant_denied
        """
        let snapshot = await manager.buildSupervisorMemoryAssemblySnapshotForTesting(
            userMessage,
            triggerSource: "grant_resolution"
        )
        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            userMessage,
            triggerSource: "grant_resolution"
        )

        #expect(snapshot?.focusedProjectId == project.projectId)
        #expect(localMemory.contains("运行 browser runtime smoke"))
        #expect(localMemory.contains("step-001"))
        #expect(!localMemory.contains(root.lastPathComponent))
    }

    @Test
    func hiddenProjectInternalReviewNoteCaptureUsesKnownProjects() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-hidden-project-review-note")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        let now = Date(timeIntervalSince1970: 1_773_384_420).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        manager.captureSupervisorReviewNoteForTesting(
            userMessage: """
            trigger=grant_resolution
            project_ref=\(project.displayName)
            project_id=\(project.projectId)
            reason_code=grant_denied
            """,
            response: """
            当前路径需要一次更细的补救 review。
            1. 先确认 grant 失败后的替代方案。
            2. 再给 project AI 下发下一步工单。
            """,
            triggerSource: "grant_resolution"
        )

        let note = try #require(SupervisorReviewNoteStore.load(for: ctx).notes.first)
        #expect(note.projectId == project.projectId)
        #expect(note.summary.contains("补救 review"))
    }

    @Test
    func approvalResolutionFollowUpMessageIncludesAuthorizationAndResolutionModes() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-approval-resolution-message")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let summary = "本地审批已被你拒绝，这次受治理技能调用不会继续执行。"
        var record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-approval-resolution-message-1",
            projectId: project.projectId,
            jobId: "job-approval-resolution-message-1",
            planId: "plan-approval-resolution-message-1",
            stepId: "step-001",
            skillId: "browser.runtime.smoke",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .blocked,
            payload: ["url": .string("https://example.com")],
            currentOwner: "supervisor",
            resultSummary: summary,
            denyCode: "local_approval_denied",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_900_000_030_000,
            updatedAtMs: 1_900_000_030_100,
            auditRef: "audit-skill-approval-resolution-message-1"
        )
        record.readiness = XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: project.projectId,
            skillId: record.skillId,
            packageSHA256: "pkg-approval-resolution-message-1",
            publisherID: "xt_builtin",
            policyScope: "xt_builtin",
            intentFamilies: ["browser.observe", "browser.interact"],
            capabilityFamilies: ["browser.observe", "browser.interact"],
            capabilityProfiles: ["observe_only", "browser_operator"],
            discoverabilityState: "discoverable",
            installabilityState: "installable",
            pinState: "xt_builtin",
            resolutionState: "resolved",
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            runnableNow: false,
            denyCode: "local_approval_required",
            reasonCode: "requires local approval before browser interact can continue",
            grantFloor: XTSkillGrantFloor.none.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            requiredGrantCapabilities: [],
            requiredRuntimeSurfaces: ["managed_browser_runtime"],
            stateLabel: "local_approval_required",
            installHint: "",
            unblockActions: ["request_local_approval"],
            auditRef: "audit-readiness-approval-resolution-message-1",
            doctorAuditRef: "",
            vetterAuditRef: "",
            resolvedSnapshotId: "snapshot-approval-resolution-message-1",
            grantSnapshotRef: ""
        )

        let message = manager.approvalResolutionFollowUpMessageForTesting(
            record: record,
            project: project,
            reasonCode: record.denyCode,
            summary: summary
        )

        #expect(message.contains("trigger=approval_resolution"))
        #expect(message.contains("authorization_mode=local_approval"))
        #expect(message.contains("resolution_mode=denied"))
        #expect(message.contains("reason_code=local_approval_denied"))
        #expect(message.contains("summary=\(summary)"))
    }

    @Test
    func grantResolutionFollowUpMessageIncludesAuthorizationAndResolutionModes() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-grant-resolution-message")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let summary = "Hub 授权已被你拒绝，这次受治理技能调用不会继续执行。"
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-grant-resolution-message-1",
            projectId: project.projectId,
            jobId: "job-grant-resolution-message-1",
            planId: "plan-grant-resolution-message-1",
            stepId: "step-001",
            skillId: "web.search",
            toolName: ToolName.web_fetch.rawValue,
            status: .blocked,
            payload: ["query": .string("browser runtime smoke fix")],
            currentOwner: "supervisor",
            resultSummary: summary,
            denyCode: "grant_denied",
            resultEvidenceRef: nil,
            requiredCapability: "web.fetch",
            grantRequestId: "grant-web-fetch-message-1",
            grantId: nil,
            createdAtMs: 1_900_000_031_000,
            updatedAtMs: 1_900_000_031_100,
            auditRef: "audit-skill-grant-resolution-message-1"
        )

        let message = manager.grantResolutionFollowUpMessageForTesting(
            record: record,
            project: project,
            reasonCode: record.denyCode,
            summary: summary
        )

        #expect(message.contains("trigger=grant_resolution"))
        #expect(message.contains("authorization_mode=hub_grant"))
        #expect(message.contains("resolution_mode=denied"))
        #expect(message.contains("reason_code=grant_denied"))
        #expect(message.contains("summary=\(summary)"))
    }

    @Test
    func guardedAutomationAliasCanonicalizesBeforeAwaitingApproval() throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-guarded-automation-alias")
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
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"检查 trusted automation 并打开控制台","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-guarded-automation-alias-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"用 trusted automation 打开控制台","kind":"call_skill","status":"pending","skill_id":"trusted-automation"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"trusted-automation","payload":{"action":"open","url":"https://example.com/console"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 trusted automation"
        )

        #expect(rendered.contains("已为项目 \(project.displayName) 登记技能调用：trusted-automation -> guarded-automation · action=open"))
        #expect(rendered.contains("当前需要本地审批后才能继续"))

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "guarded-automation")
        #expect(call.requestedSkillId == "trusted-automation")
        #expect(call.status == .awaitingAuthorization)
        #expect(call.toolName == ToolName.deviceBrowserControl.rawValue)
        #expect(call.denyCode == "local_approval_required")
        #expect(call.routingReasonCode == "requested_alias_normalized")
        #expect(call.routingExplanation?.contains("alias trusted-automation normalized to guarded-automation") == true)
        #expect(manager.pendingSupervisorSkillApprovals.count == 1)
        #expect(manager.pendingSupervisorSkillApprovals.first?.skillId == "guarded-automation")
        #expect(manager.pendingSupervisorSkillApprovals.first?.routingReasonCode == "requested_alias_normalized")
        #expect(manager.pendingSupervisorSkillApprovals.first?.routingExplanation?.contains("alias trusted-automation normalized to guarded-automation") == true)

        let rawEntries = try readRawLogEntries(at: ctx.rawLogURL)
        let rawAwaitingAuthorization = try #require(rawEntries.last(where: {
            ($0["type"] as? String) == "supervisor_skill_call" &&
            ($0["action"] as? String) == "awaiting_authorization"
        }))
        #expect(rawAwaitingAuthorization["requested_skill_id"] as? String == "trusted-automation")
        #expect(rawAwaitingAuthorization["skill_id"] as? String == "guarded-automation")
        #expect(rawAwaitingAuthorization["routing_reason_code"] as? String == "requested_alias_normalized")
        let routingExplanation = try #require(rawAwaitingAuthorization["routing_explanation"] as? String)
        #expect(routingExplanation.contains("alias trusted-automation normalized to guarded-automation"))
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
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

        #expect(manager.messages.contains(where: {
            $0.content.contains("已批准项目 \(project.displayName) 的技能调用：browser.runtime.smoke") &&
                !$0.content.contains(root.lastPathComponent)
        }))

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
    func approvedLocalSupervisorSkillApprovalResumeFailureUsesFriendlyProjectName() throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-local-approval-resume-mapping-failure")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try appendManifestDrivenSkillFixture(
            hubBaseDir: fixture.hubBaseDir,
            projectID: project.projectId,
            skillID: "browser.local.wrapper",
            packageSHA256: "5656565656565656565656565656565656565656565656565656565656565656",
            canonicalManifestSHA256: "5757575757575757575757575757575757575757575757575757575757575757",
            manifest: [
                "skill_id": "browser.local.wrapper",
                "description": "Wrapper over governed local browser control.",
                "risk_level": "high",
                "requires_grant": true,
                "side_effect_class": "external_side_effect",
                "timeout_ms": 15000,
                "max_retries": 1,
                "governed_dispatch": [
                    "tool": ToolName.deviceBrowserControl.rawValue,
                    "fixed_args": [
                        "action": "open_url",
                    ],
                    "passthrough_args": ["url"],
                    "required_any": [["url"]],
                ],
            ]
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"运行本地 browser wrapper","priority":"high"}[/CREATE_JOB]"#,
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
            )
        try AXProjectStore.saveConfig(config, for: ctx)

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeSupervisorTrustedAutomationPermissionReadiness()
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-local-wrapper-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行本地 browser wrapper","kind":"call_skill","status":"pending","skill_id":"browser.local.wrapper"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.local.wrapper","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser local wrapper"
        )

        let original = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        var mutated = original
        mutated.payload = [:]
        try SupervisorProjectSkillCallStore.upsert(mutated, for: ctx)

        manager.refreshPendingSupervisorSkillApprovalsNow()
        let approval = try #require(manager.pendingSupervisorSkillApprovals.first(where: { $0.requestId == original.requestId }))
        manager.approvePendingSupervisorSkillApproval(approval)

        #expect(manager.messages.contains(where: {
            $0.content.contains("无法恢复项目 \(project.displayName) 的技能调用：browser.local.wrapper") &&
                !$0.content.contains(root.lastPathComponent)
        }))

        let updatedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first(where: {
            $0.requestId == original.requestId
        }))
        #expect(updatedCall.status == .blocked)
        #expect(updatedCall.denyCode == "skill_mapping_missing")

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .blocked)
        #expect(plan.status == .blocked)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .blocked)
    }

    @Test
    func approveSupervisorSkillActivityWorksWhenProjectOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-approve-activity-hidden-project")
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
                output: "browser smoke completed from recent activity"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"运行 hidden browser smoke","priority":"high"}[/CREATE_JOB]"#,
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
            )
        try AXProjectStore.saveConfig(config, for: ctx)

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeSupervisorTrustedAutomationPermissionReadiness()
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-approve-activity-hidden-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        let original = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        manager.refreshRecentSupervisorSkillActivitiesNow()
        let activity = try #require(manager.recentSupervisorSkillActivities.first(where: { $0.requestId == original.requestId }))

        let now = Date(timeIntervalSince1970: 1_773_383_900).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        manager.approveSupervisorSkillActivity(activity)
        await manager.waitForSupervisorSkillDispatchForTesting()

        #expect(manager.messages.contains(where: {
            $0.content.contains("已批准项目 \(project.displayName) 的技能调用：browser.runtime.smoke") &&
                !$0.content.contains(root.lastPathComponent)
        }))

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("browser smoke completed from recent activity"))

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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
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

        #expect(manager.messages.contains(where: {
            $0.content.contains("已拒绝项目 \(project.displayName) 的技能调用：browser.runtime.smoke")
        }) == false)

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .blocked)
        #expect(call.denyCode == "local_approval_denied")
        #expect(call.resultSummary.contains("本地审批已被你拒绝"))
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

        #expect(rendered.contains("已为项目 \(project.displayName) 登记技能调用：web.search"))
        #expect(rendered.contains("正在向 Hub 申请联网访问授权"))
        #expect(!rendered.contains(root.lastPathComponent))

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
        #expect(localMemory.contains("active_skill_execution_readiness: grant_required"))
        #expect(localMemory.contains("active_skill_requested_capability_families:"))
        #expect(localMemory.contains("active_skill_unblock_actions:"))
    }

    @Test
    func denyingGrantRequiredPendingSkillApprovalUsesGrantDeniedOutcome() throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-deny-grant-required-skill")
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-web-search-deny-grant-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索浏览器安全修复线索","kind":"call_skill","status":"pending","skill_id":"web.search"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"web.search","payload":{"query":"browser runtime smoke fix","max_results":3}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 web search 技能"
        )

        let approval = try #require(manager.pendingSupervisorSkillApprovals.first)
        manager.denyPendingSupervisorSkillApproval(approval)

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .blocked)
        #expect(call.denyCode == "grant_denied")
        #expect(call.resultSummary.contains("Hub 授权已被你拒绝"))
        #expect(call.resultSummary.contains("联网访问"))
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .blocked)
        #expect(plan.status == .blocked)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .blocked)
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
    func retrySupervisorSkillActivityUsesFriendlyProjectNameWhenRequeued() async throws {
        actor ExecutionCapture {
            private var attempt = 0

            func run(_ call: ToolCall) -> ToolResult {
                attempt += 1
                if attempt == 1 {
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: false,
                        output: "skills search failed"
                    )
                }
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: "skills search retry completed"
                )
            }
        }

        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-find-skills-retry-friendly-name")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let capture = ExecutionCapture()
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .skills_search)
            return await capture.run(call)
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"重试搜索 skill","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-find-skills-retry-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索 skill","kind":"call_skill","status":"pending","skill_id":"find-skills"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"find-skills","payload":{"query":"browser","source_filter":"builtin:catalog"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 find-skills 技能"
        )
        await manager.waitForSupervisorSkillDispatchForTesting()

        let firstCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(firstCall.status == .failed)

        manager.refreshRecentSupervisorSkillActivitiesNow()
        let activity = try #require(manager.recentSupervisorSkillActivities.first(where: { $0.requestId == firstCall.requestId }))
        manager.retrySupervisorSkillActivity(activity)

        #expect(manager.messages.contains(where: {
            $0.content.contains("已为项目 \(project.displayName) 重新排队技能调用：find-skills") &&
                !$0.content.contains(root.lastPathComponent)
        }))

        await manager.waitForSupervisorSkillDispatchForTesting()

        let calls = SupervisorProjectSkillCallStore.load(for: ctx).calls
        let latest = try #require(calls.max(by: { $0.createdAtMs < $1.createdAtMs }))
        #expect(latest.requestId != firstCall.requestId)
        #expect(latest.status == .completed)
        #expect(latest.resultSummary.contains("skills search retry completed"))
    }

    @Test
    func retrySupervisorSkillActivityUsesFriendlyProjectNameWhenRemapFails() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-find-skills-retry-remap-failure")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .skills_search)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: "skills search failed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"重试搜索 skill remap failure","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-find-skills-retry-remap-failure-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索 skill","kind":"call_skill","status":"pending","skill_id":"find-skills"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"find-skills","payload":{"query":"browser","source_filter":"builtin:catalog"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 find-skills 技能"
        )
        await manager.waitForSupervisorSkillDispatchForTesting()

        let original = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(original.status == .failed)

        var mutated = original
        mutated.payload = [:]
        try SupervisorProjectSkillCallStore.upsert(mutated, for: ctx)

        manager.refreshRecentSupervisorSkillActivitiesNow()
        let activity = try #require(manager.recentSupervisorSkillActivities.first(where: { $0.requestId == original.requestId }))
        manager.retrySupervisorSkillActivity(activity)

        #expect(manager.messages.contains(where: {
            $0.content.contains("无法重试项目 \(project.displayName) 的技能调用：find-skills") &&
                !$0.content.contains(root.lastPathComponent)
        }))

        let calls = SupervisorProjectSkillCallStore.load(for: ctx).calls
        #expect(calls.count == 2)
        let latest = try #require(calls.max(by: { $0.createdAtMs < $1.createdAtMs }))
        #expect(latest.requestId != original.requestId)
        #expect(latest.status == .blocked)
        #expect(latest.denyCode == "skill_mapping_missing")
    }

    @Test
    func retrySupervisorSkillActivityWorksWhenProjectOutsideJurisdictionView() async throws {
        actor ExecutionCapture {
            private var attempt = 0

            func run(_ call: ToolCall) -> ToolResult {
                attempt += 1
                if attempt == 1 {
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: false,
                        output: "skills search failed"
                    )
                }
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: "skills search retry completed"
                )
            }
        }

        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-find-skills-retry-hidden-project")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let capture = ExecutionCapture()
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .skills_search)
            return await capture.run(call)
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"重试隐藏项目 skill","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-find-skills-retry-hidden-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索 skill","kind":"call_skill","status":"pending","skill_id":"find-skills"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"find-skills","payload":{"query":"browser","source_filter":"builtin:catalog"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 find-skills 技能"
        )
        await manager.waitForSupervisorSkillDispatchForTesting()

        let original = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(original.status == .failed)

        manager.refreshRecentSupervisorSkillActivitiesNow()
        let activity = try #require(manager.recentSupervisorSkillActivities.first(where: { $0.requestId == original.requestId }))

        let now = Date(timeIntervalSince1970: 1_773_384_000).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        manager.retrySupervisorSkillActivity(activity)

        #expect(manager.messages.contains(where: {
            $0.content.contains("已为项目 \(project.displayName) 重新排队技能调用：find-skills") &&
                !$0.content.contains(root.lastPathComponent)
        }))

        await manager.waitForSupervisorSkillDispatchForTesting()

        let calls = SupervisorProjectSkillCallStore.load(for: ctx).calls
        let latest = try #require(calls.max(by: { $0.createdAtMs < $1.createdAtMs }))
        #expect(latest.requestId != original.requestId)
        #expect(latest.status == .completed)
        #expect(latest.resultSummary.contains("skills search retry completed"))
    }

    @Test
    func retrySupervisorSkillActivityFailsClosedAgainWhenSkillRemainsQuarantined() async throws {
        actor ExecutionCounter {
            private var count = 0

            func record() {
                count += 1
            }

            func value() -> Int {
                count
            }
        }

        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-skill-retry-preflight-quarantine")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        try writeOfficialSkillLifecycleFixture(
            hubBaseDir: fixture.hubBaseDir,
            packages: [
                [
                    "package_sha256": "9999999999999999999999999999999999999999999999999999999999999999",
                    "skill_id": "browser.runtime.smoke",
                    "name": "Browser Runtime Smoke",
                    "version": "2.0.0",
                    "risk_level": "high",
                    "requires_grant": true,
                    "package_state": "quarantined",
                    "overall_state": "blocked",
                    "blocking_failures": 1,
                    "transition_count": 1,
                    "updated_at_ms": 88,
                    "last_transition_at_ms": 88,
                    "last_ready_at_ms": 0,
                    "last_blocked_at_ms": 88
                ]
            ]
        )
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let executionCounter = ExecutionCounter()
        manager.setSupervisorToolExecutorOverrideForTesting { _, _ in
            await executionCounter.record()
            return ToolResult(
                id: "unexpected-quarantine-execution",
                tool: .project_snapshot,
                ok: false,
                output: "unexpected execution"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"重试 quarantine skill","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-retry-quarantine-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        let original = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(original.status == .blocked)
        #expect(original.denyCode == "preflight_quarantined")

        manager.refreshRecentSupervisorSkillActivitiesNow()
        let activity = try #require(manager.recentSupervisorSkillActivities.first(where: { $0.requestId == original.requestId }))
        manager.retrySupervisorSkillActivity(activity)
        await manager.waitForSupervisorSkillDispatchForTesting()

        let calls = SupervisorProjectSkillCallStore.load(for: ctx).calls
        #expect(calls.count == 2)
        let latest = try #require(calls.max(by: { $0.createdAtMs < $1.createdAtMs }))
        #expect(latest.requestId != original.requestId)
        #expect(latest.status == .blocked)
        #expect(latest.denyCode == "preflight_quarantined")
        #expect(latest.policySource == "skill_preflight")
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)
        #expect(manager.messages.contains(where: { $0.content.contains("preflight_quarantined") }))
        #expect(await executionCounter.value() == 0)
    }

    @Test
    func pendingSupervisorSkillApprovalStateRetainsHiddenProjectsAfterJurisdictionRefresh() throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-pending-approval-hidden-refresh")
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-hidden-approval-refresh-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        #expect(manager.pendingSupervisorSkillApprovals.count == 1)

        let now = Date(timeIntervalSince1970: 1_773_384_050).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        manager.refreshPendingSupervisorSkillApprovalsNow()

        #expect(manager.pendingSupervisorSkillApprovals.count == 1)
        #expect(manager.pendingSupervisorSkillApprovals.first?.projectId == project.projectId)
        #expect(manager.pendingSupervisorSkillApprovals.first?.projectName == project.displayName)
    }

    @Test
    func recentSupervisorSkillActivitiesRetainHiddenProjectsAfterJurisdictionRefresh() async throws {
        actor ExecutionCapture {
            func run(_ call: ToolCall) -> ToolResult {
                ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: "skills search failed"
                )
            }
        }

        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-recent-activity-hidden-refresh")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let capture = ExecutionCapture()
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .skills_search)
            return await capture.run(call)
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"重试隐藏 recent activity","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-find-skills-hidden-recent-refresh-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索 skill","kind":"call_skill","status":"pending","skill_id":"find-skills"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"find-skills","payload":{"query":"browser","source_filter":"builtin:catalog"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 find-skills 技能"
        )
        await manager.waitForSupervisorSkillDispatchForTesting()

        let original = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(original.status == .failed)

        let now = Date(timeIntervalSince1970: 1_773_384_150).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        manager.refreshRecentSupervisorSkillActivitiesNow()

        let activity = try #require(manager.recentSupervisorSkillActivities.first(where: { $0.requestId == original.requestId }))
        #expect(activity.projectId == project.projectId)
        #expect(activity.projectName == project.displayName)
        #expect(activity.status == SupervisorSkillCallStatus.failed.rawValue)
    }

    @Test
    func pendingHubGrantStateRetainsHiddenProjectsAfterJurisdictionRefresh() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-pending-grant-hidden-refresh")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "外出采购项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let snapshot = HubIPCClient.PendingGrantSnapshot(
            source: "hub_runtime_grpc",
            updatedAtMs: 1_773_384_200_000,
            items: [
                HubIPCClient.PendingGrantItem(
                    grantRequestId: "grant-hidden-refresh-1",
                    requestId: "req-hidden-refresh-1",
                    deviceId: "device_xt_001",
                    userId: "user-1",
                    appId: "x-terminal",
                    projectId: project.projectId,
                    capability: "web.fetch",
                    modelId: "",
                    reason: "remote grocery workflow",
                    requestedTtlSec: 900,
                    requestedTokenCap: 0,
                    status: "pending",
                    decision: "queued",
                    createdAtMs: 1_773_384_150_000,
                    decidedAtMs: 0
                )
            ]
        )
        manager.setPendingGrantSnapshotForTesting(
            snapshot,
            now: Date(timeIntervalSince1970: 1_773_384_200)
        )

        #expect(manager.pendingHubGrants.count == 1)
        #expect(manager.pendingHubGrants.first?.projectId == project.projectId)

        let now = Date(timeIntervalSince1970: 1_773_384_201).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        manager.setPendingGrantSnapshotForTesting(
            snapshot,
            now: Date(timeIntervalSince1970: 1_773_384_201)
        )

        #expect(manager.pendingHubGrants.count == 1)
        #expect(manager.pendingHubGrants.first?.projectId == project.projectId)
        #expect(manager.pendingHubGrants.first?.projectName == project.displayName)
    }

    @Test
    func frontstagePendingHubGrantBoardSuppressesHiddenProjectsOutsideJurisdictionView() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-frontstage-pending-grant-hidden")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "外出采购项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let snapshot = HubIPCClient.PendingGrantSnapshot(
            source: "hub_runtime_grpc",
            updatedAtMs: 1_773_384_260_000,
            items: [
                HubIPCClient.PendingGrantItem(
                    grantRequestId: "grant-frontstage-hidden-1",
                    requestId: "req-frontstage-hidden-1",
                    deviceId: "device_xt_001",
                    userId: "user-1",
                    appId: "x-terminal",
                    projectId: project.projectId,
                    capability: "web.fetch",
                    modelId: "",
                    reason: "remote grocery workflow",
                    requestedTtlSec: 900,
                    requestedTokenCap: 0,
                    status: "pending",
                    decision: "queued",
                    createdAtMs: 1_773_384_250_000,
                    decidedAtMs: 0
                )
            ]
        )
        manager.setPendingGrantSnapshotForTesting(
            snapshot,
            now: Date(timeIntervalSince1970: 1_773_384_260)
        )

        let now = Date(timeIntervalSince1970: 1_773_384_261).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        manager.setPendingGrantSnapshotForTesting(
            snapshot,
            now: Date(timeIntervalSince1970: 1_773_384_261)
        )

        #expect(manager.pendingHubGrants.count == 1)
        #expect(manager.frontstagePendingHubGrants.isEmpty)

        let board = SupervisorViewRuntimePresentationSupport.pendingHubGrantBoardPresentation(
            supervisor: manager,
            hubInteractive: false,
            focusedRowAnchor: nil
        )
        #expect(board.rows.isEmpty)
        #expect(board.title == "Hub 待处理授权：0")
    }

    @Test
    func frontstageSkillBoardsSuppressHiddenProjectsOutsideJurisdictionView() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-frontstage-skill-hidden")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let nowMs = Int64(1_773_384_300_000)
        try SupervisorProjectSkillCallStore.upsert(
            SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "skill-hidden-frontstage-1",
                projectId: project.projectId,
                jobId: "job-hidden-frontstage-1",
                planId: "plan-hidden-frontstage-1",
                stepId: "step-hidden-frontstage-1",
                skillId: "browser.runtime.smoke",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .awaitingAuthorization,
                payload: ["url": .string("https://example.com")],
                currentOwner: "supervisor",
                resultSummary: "waiting for local governed approval",
                denyCode: "",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: nowMs,
                updatedAtMs: nowMs,
                auditRef: "audit-skill-hidden-frontstage-1"
            ),
            for: ctx
        )

        let now = Date(timeIntervalSince1970: 1_773_384_301).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        manager.refreshPendingSupervisorSkillApprovalsNow()

        #expect(manager.pendingSupervisorSkillApprovals.count == 1)
        #expect(manager.recentSupervisorSkillActivities.count == 1)
        #expect(manager.frontstagePendingSupervisorSkillApprovals.isEmpty)
        #expect(manager.frontstageRecentSupervisorSkillActivities.isEmpty)

        let approvalBoard = SupervisorViewRuntimePresentationSupport.pendingSkillApprovalBoardPresentation(
            supervisor: manager,
            focusedRowAnchor: nil
        )
        #expect(approvalBoard.rows.isEmpty)
        #expect(approvalBoard.title == "待审批技能：0")

        let activityBoard = SupervisorViewRuntimePresentationSupport.recentSkillActivityBoardPresentation(
            supervisor: manager
        )
        #expect(activityBoard.items.isEmpty)
        #expect(activityBoard.title == "最近技能活动：0")
    }

    @Test
    func proactiveVoicePendingHubGrantAnnouncementSuppressesHiddenProjectOutsideJurisdictionView() async throws {
        var spoken: [String] = []
        let controller = SupervisorConversationSessionController.makeForTesting(
            route: .systemSpeechCompatibility,
            wakeMode: .pushToTalk,
            nowProvider: { Date() }
        )
        let transcriber = SupervisorCommandGuardMockVoiceStreamingTranscriber()
        let voiceCoordinator = VoiceSessionCoordinator(
            transcriber: transcriber,
            preferences: .default()
        )
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer,
            conversationSessionController: controller,
            voiceSessionCoordinator: voiceCoordinator
        )

        let root = try makeProjectRoot(named: "supervisor-voice-hidden-grant-frontstage")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "外出采购项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        var settings = appModel.settingsStore.settings
        settings.voice.wakeMode = .wakePhrase
        settings.voice.preferredRoute = .systemSpeechCompatibility
        appModel.settingsStore.settings = settings
        manager.setAppModel(appModel)
        await voiceCoordinator.refreshRouteAvailability()
        await voiceCoordinator.refreshAuthorizationStatus(requestIfNeeded: false)

        try await waitUntil("voice route ready for hidden grant suppression", timeoutMs: 5_000) {
            manager.voiceRouteDecision.route == .systemSpeechCompatibility
        }

        let now = Date(timeIntervalSince1970: 1_773_384_340).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        manager.setPendingHubGrantsForTesting(
            [],
            source: "test",
            announceNewArrivals: true,
            now: Date(timeIntervalSince1970: 1_773_384_340)
        )

        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "grant-hidden-voice-1",
                    dedupeKey: "grant-hidden-voice-1",
                    grantRequestId: "grant-hidden-voice-1",
                    requestId: "req-hidden-voice-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    capability: "web.fetch",
                    modelId: "",
                    reason: "remote grocery workflow",
                    requestedTtlSec: 900,
                    requestedTokenCap: 0,
                    createdAt: 1_773_384_341,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "new request",
                    nextAction: "review"
                )
            ],
            source: "test",
            announceNewArrivals: true,
            now: Date(timeIntervalSince1970: 1_773_384_341)
        )

        #expect(manager.pendingHubGrants.count == 1)
        #expect(manager.frontstagePendingHubGrants.isEmpty)
        #expect(spoken.isEmpty)
        #expect(!manager.messages.contains(where: { $0.content.contains(project.displayName) }))
    }

    @Test
    func proactiveVoicePendingSkillApprovalAnnouncementSuppressesHiddenProjectOutsideJurisdictionView() async throws {
        var spoken: [String] = []
        let controller = SupervisorConversationSessionController.makeForTesting(
            route: .systemSpeechCompatibility,
            wakeMode: .pushToTalk,
            nowProvider: { Date() }
        )
        let transcriber = SupervisorCommandGuardMockVoiceStreamingTranscriber()
        let voiceCoordinator = VoiceSessionCoordinator(
            transcriber: transcriber,
            preferences: .default()
        )
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer,
            conversationSessionController: controller,
            voiceSessionCoordinator: voiceCoordinator
        )

        let root = try makeProjectRoot(named: "supervisor-voice-hidden-skill-approval-frontstage")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        var settings = appModel.settingsStore.settings
        settings.voice.wakeMode = .wakePhrase
        settings.voice.preferredRoute = .systemSpeechCompatibility
        appModel.settingsStore.settings = settings
        manager.setAppModel(appModel)
        await voiceCoordinator.refreshRouteAvailability()
        await voiceCoordinator.refreshAuthorizationStatus(requestIfNeeded: false)

        try await waitUntil("voice route ready for hidden approval suppression", timeoutMs: 5_000) {
            manager.voiceRouteDecision.route == .systemSpeechCompatibility
        }

        let now = Date(timeIntervalSince1970: 1_773_384_360).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        manager.refreshPendingSupervisorSkillApprovalsNow()

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let nowMs = Int64(1_773_384_361_000)
        try SupervisorProjectSkillCallStore.upsert(
            SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "skill-hidden-voice-approval-1",
                projectId: project.projectId,
                jobId: "job-hidden-voice-approval-1",
                planId: "plan-hidden-voice-approval-1",
                stepId: "step-hidden-voice-approval-1",
                skillId: "browser.runtime.smoke",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .awaitingAuthorization,
                payload: ["url": .string("https://example.com")],
                currentOwner: "supervisor",
                resultSummary: "waiting for local governed approval",
                denyCode: "",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: nowMs,
                updatedAtMs: nowMs,
                auditRef: "audit-skill-hidden-voice-approval-1"
            ),
            for: ctx
        )

        manager.refreshPendingSupervisorSkillApprovalsNow()

        #expect(manager.pendingSupervisorSkillApprovals.count == 1)
        #expect(manager.frontstagePendingSupervisorSkillApprovals.isEmpty)
        #expect(spoken.isEmpty)
        #expect(!manager.messages.contains(where: { $0.content.contains(project.displayName) }))
    }

    @Test
    func frontstageEventLoopStatusAndInfrastructureSummarySuppressHiddenProjectsOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )
        manager.setSupervisorEventLoopResponseOverrideForTesting { _, _ in "" }

        let root = try makeProjectRoot(named: "supervisor-frontstage-event-loop-hidden")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_380).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
            project_id=\(project.projectId)
            project_ref=\(project.displayName)
            summary=hidden event loop callback
            next_safe_action=open_ui_review
            """,
            triggerSource: "skill_callback",
            dedupeKey: "hidden_event_loop_frontstage_status"
        )
        await manager.waitForSupervisorEventLoopForTesting()

        #expect(manager.recentSupervisorEventLoopActivitiesForTesting().count == 1)
        #expect(manager.frontstageRecentSupervisorEventLoopActivities.isEmpty)
        #expect(manager.supervisorEventLoopStatusLine == "idle · recent activity")
        #expect(manager.frontstageSupervisorEventLoopStatusLine == "idle")

        let eventLoopBoard = SupervisorViewRuntimePresentationSupport.eventLoopBoardPresentation(
            supervisor: manager
        )
        #expect(eventLoopBoard.rows.isEmpty)
        #expect(eventLoopBoard.statusLine == "idle")

        let infrastructureFeed = SupervisorViewRuntimePresentationSupport.infrastructureFeedPresentation(
            supervisor: manager,
            appModel: appModel
        )
        #expect(infrastructureFeed.items.allSatisfy { $0.kind != .eventLoop })
        #expect(!infrastructureFeed.summaryLine.localizedCaseInsensitiveContains("recent activity"))
        #expect(!infrastructureFeed.summaryLine.localizedCaseInsensitiveContains("queued"))
        #expect(!infrastructureFeed.summaryLine.localizedCaseInsensitiveContains("running"))
    }

    @Test
    func frontstageProjectNotificationOverviewReaggregatesVisibleHistoryOutsideJurisdictionView() throws {
        let manager = SupervisorManager.makeForTesting()

        let hiddenRoot = try makeProjectRoot(named: "supervisor-frontstage-notification-hidden")
        defer { try? FileManager.default.removeItem(at: hiddenRoot) }
        let visibleRoot = try makeProjectRoot(named: "supervisor-frontstage-notification-visible")
        defer { try? FileManager.default.removeItem(at: visibleRoot) }

        let hiddenProject = makeProjectEntry(root: hiddenRoot, displayName: "我的世界还原项目")
        let visibleProject = makeProjectEntry(root: visibleRoot, displayName: "发布阻塞项目")

        let appModel = AppModel()
        appModel.registry = registry(with: [hiddenProject, visibleProject])
        appModel.selectedProjectId = hiddenProject.projectId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_420).timeIntervalSince1970
        let blockedEntry = AXProjectEntry(
            projectId: visibleProject.projectId,
            rootPath: visibleProject.rootPath,
            displayName: visibleProject.displayName,
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "blocked",
            currentStateSummary: "等待 require-real 样本",
            nextStepSummary: "补齐 RR02",
            blockerSummary: "Missing require-real sample",
            lastSummaryAt: now,
            lastEventAt: now
        )

        manager.handleEvent(.projectCreated(hiddenProject))
        manager.handleEvent(.projectUpdated(blockedEntry))

        #expect(manager.supervisorProjectNotificationSnapshot.deliveredBadges == 1)
        #expect(manager.supervisorProjectNotificationSnapshot.deliveredBriefs == 1)

        let hiddenNow = Date(timeIntervalSince1970: 1_773_384_421).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: hiddenNow)
            .upserting(
                projectId: hiddenProject.projectId,
                displayName: hiddenProject.displayName,
                role: .triageOnly,
                now: hiddenNow
            )
            .upserting(
                projectId: visibleProject.projectId,
                displayName: visibleProject.displayName,
                role: .triageOnly,
                now: hiddenNow
            )
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        let frontstageSnapshot = manager.frontstageSupervisorProjectNotificationSnapshot
        #expect(frontstageSnapshot.deliveredInterrupts == 0)
        #expect(frontstageSnapshot.deliveredBriefs == 1)
        #expect(frontstageSnapshot.deliveredBadges == 0)
        #expect(frontstageSnapshot.mutedLogs == 0)
        #expect(frontstageSnapshot.suppressedDuplicates == 0)

        let overview = SupervisorViewRuntimePresentationSupport.portfolioOverviewPresentation(
            supervisor: manager
        )
        #expect(overview.projectNotificationLine?.contains("brief=1") == true)
        #expect(overview.projectNotificationLine?.contains("badge=0") == true)
        #expect(overview.projectNotificationLine?.contains("interrupt=0") == true)
    }

    @Test
    func hiddenSessionActivityDoesNotLeakOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-hidden-session-activity")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "隐藏会话项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_430).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        let sessionManager = AXSessionManager.shared
        let session = sessionManager.createSession(
            projectId: project.projectId,
            title: "隐藏项目会话",
            directory: root.path
        )
        defer { sessionManager.deleteSession(session.id) }

        manager.clearMessages()
        let baselineEventCount = manager.recentEventsForTesting().count

        var updatedSession = session
        updatedSession.title = "隐藏项目会话-更新"
        updatedSession.updatedAt = now + 1
        sessionManager.updateSession(updatedSession)

        manager.handleEvent(.sessionCreated(session))
        manager.handleEvent(.sessionUpdated(updatedSession))
        manager.handleEvent(.messageCreated(session.id, AXChatMessage(role: .user, content: "hello hidden session")))
        manager.handleEvent(
            .toolCallCreated(
                session.id,
                ToolCall(
                    id: "tool-hidden-session-1",
                    tool: .run_command,
                    args: ["cmd": .string("echo hi")]
                )
            )
        )

        #expect(manager.messages.isEmpty)
        let newEvents = Array(manager.recentEventsForTesting().dropFirst(baselineEventCount))
        #expect(newEvents.isEmpty)

        let memory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续")
        #expect(!memory.contains("隐藏项目会话"))
        #expect(!memory.contains(session.id))
    }

    @Test
    func explicitHiddenProjectMemoryIncludesRecentEventsWithoutFrontstageLeak() async throws {
        let manager = SupervisorManager.makeForTesting()
        HubIPCClient.installSupervisorRemoteContinuityOverrideForTesting { _ in
            HubIPCClient.SupervisorRemoteContinuityResult(
                ok: false,
                source: "xt_cache",
                workingEntries: [],
                cacheHit: false,
                reasonCode: "remote_route_not_preferred"
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let visibleRoot = try makeProjectRoot(named: "supervisor-visible-hidden-recent-events")
        let hiddenRoot = try makeProjectRoot(named: "supervisor-hidden-recent-events")
        defer { try? FileManager.default.removeItem(at: visibleRoot) }
        defer { try? FileManager.default.removeItem(at: hiddenRoot) }

        let visibleProject = makeProjectEntry(root: visibleRoot, displayName: "可见项目")
        let hiddenProject = makeProjectEntry(root: hiddenRoot, displayName: "隐藏会话项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [visibleProject, hiddenProject])
        appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_432).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(
                projectId: hiddenProject.projectId,
                displayName: hiddenProject.displayName,
                role: .triageOnly,
                now: now
            )
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        let sessionManager = AXSessionManager.shared
        let session = sessionManager.createSession(
            projectId: hiddenProject.projectId,
            title: "隐藏项目会话",
            directory: hiddenRoot.path
        )
        defer { sessionManager.deleteSession(session.id) }

        var updatedSession = session
        updatedSession.title = "隐藏项目会话-更新"
        updatedSession.updatedAt = now + 1
        sessionManager.updateSession(updatedSession)

        manager.handleEvent(.sessionCreated(session))
        manager.handleEvent(.sessionUpdated(updatedSession))
        manager.handleEvent(.messageCreated(session.id, AXChatMessage(role: .user, content: "hello hidden session")))
        manager.handleEvent(
            .toolCallCreated(
                session.id,
                ToolCall(
                    id: "tool-hidden-session-2",
                    tool: .run_command,
                    args: ["cmd": .string("echo hi")]
                )
            )
        )

        let frontstageMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续")
        let frontstageObservations = extractTaggedSection(frontstageMemory, tag: "L2_OBSERVATIONS") ?? ""
        #expect(!frontstageMemory.contains("隐藏项目会话-更新"))
        #expect(!frontstageMemory.contains(session.id))
        #expect(!frontstageObservations.contains("隐藏项目会话-更新"))
        #expect(!frontstageObservations.contains("执行工具：run_command"))

        let explicitMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("请继续隐藏会话项目")
        let explicitObservations = extractTaggedSection(explicitMemory, tag: "L2_OBSERVATIONS") ?? ""
        #expect(explicitMemory.contains("recent_events:"))
        #expect(explicitMemory.contains("更新了会话：隐藏项目会话-更新"))
        #expect(explicitMemory.contains("执行工具：run_command"))
        #expect(explicitObservations.contains("更新了会话：隐藏项目会话-更新"))
        #expect(explicitObservations.contains("执行工具：run_command"))
    }

    @Test
    func explicitHiddenProjectDialogueWindowIncludesRecentContextRecoveryWithoutFrontstageLeak() async throws {
        let manager = SupervisorManager.makeForTesting()
        HubIPCClient.installSupervisorRemoteContinuityOverrideForTesting { _ in
            HubIPCClient.SupervisorRemoteContinuityResult(
                ok: false,
                source: "xt_cache",
                workingEntries: [],
                cacheHit: false,
                reasonCode: "remote_route_not_preferred"
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let visibleRoot = try makeProjectRoot(named: "supervisor-visible-hidden-dialogue-window")
        let hiddenRoot = try makeProjectRoot(named: "supervisor-hidden-dialogue-window")
        defer { try? FileManager.default.removeItem(at: visibleRoot) }
        defer { try? FileManager.default.removeItem(at: hiddenRoot) }

        let visibleProject = makeProjectEntry(root: visibleRoot, displayName: "可见项目")
        let hiddenProject = makeProjectEntry(root: hiddenRoot, displayName: "隐藏对话项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [visibleProject, hiddenProject])
        appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_435).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(
                projectId: hiddenProject.projectId,
                displayName: hiddenProject.displayName,
                role: .triageOnly,
                now: now
            )
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        let hiddenCtx = AXProjectContext(root: hiddenRoot)
        AXRecentContextStore.appendUserMessage(
            ctx: hiddenCtx,
            text: "隐藏项目用户提问：请检查最近的卡点",
            createdAt: now + 1
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: hiddenCtx,
            text: "隐藏项目助手回复：最近卡在构建脚本签名校验",
            createdAt: now + 2
        )

        let frontstageMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续")
        let frontstageDialogueWindow = extractTaggedSection(frontstageMemory, tag: "DIALOGUE_WINDOW") ?? ""
        let frontstageSnapshot = await manager.buildSupervisorMemoryAssemblySnapshotForTesting("继续")
        #expect(!frontstageDialogueWindow.contains("隐藏项目用户提问"))
        #expect(!frontstageDialogueWindow.contains("隐藏项目助手回复"))
        #expect(!frontstageDialogueWindow.contains("focused_project_recent_dialogue_recovery:"))
        #expect(frontstageSnapshot?.scopedPromptRecoveryMode == nil)
        #expect(frontstageSnapshot?.normalizedScopedPromptRecoverySections.isEmpty == true)

        let explicitMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("请继续隐藏对话项目")
        let explicitDialogueWindow = extractTaggedSection(explicitMemory, tag: "DIALOGUE_WINDOW") ?? ""
        let explicitSnapshot = await manager.buildSupervisorMemoryAssemblySnapshotForTesting("请继续隐藏对话项目")
        #expect(explicitDialogueWindow.contains("focused_project_recent_dialogue_recovery:"))
        #expect(explicitDialogueWindow.contains("focus_project=隐藏对话项目"))
        #expect(explicitDialogueWindow.contains("source=project_recent_context"))
        #expect(explicitDialogueWindow.contains("隐藏项目用户提问：请检查最近的卡点"))
        #expect(explicitDialogueWindow.contains("隐藏项目助手回复：最近卡在构建脚本签名校验"))
        #expect(explicitSnapshot?.scopedPromptRecoveryMode == "explicit_hidden_project_focus")
        #expect(explicitSnapshot?.normalizedScopedPromptRecoverySections.contains("l1_canonical.focused_project_anchor_pack") == true)
        #expect(explicitSnapshot?.normalizedScopedPromptRecoverySections.contains("l2_observations.project_recent_events") == true)
        #expect(explicitSnapshot?.normalizedScopedPromptRecoverySections.contains("l3_working_set.project_activity_memory") == true)
        #expect(explicitSnapshot?.normalizedScopedPromptRecoverySections.contains("dialogue_window.project_recent_context") == true)
    }

    @Test
    func explicitHiddenProjectMemoryIncludesNotificationHistoryWithoutFrontstageLeak() async throws {
        let manager = SupervisorManager.makeForTesting()
        HubIPCClient.installSupervisorRemoteContinuityOverrideForTesting { _ in
            HubIPCClient.SupervisorRemoteContinuityResult(
                ok: false,
                source: "xt_cache",
                workingEntries: [],
                cacheHit: false,
                reasonCode: "remote_route_not_preferred"
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let visibleRoot = try makeProjectRoot(named: "supervisor-visible-hidden-notification-memory")
        let hiddenRoot = try makeProjectRoot(named: "supervisor-hidden-notification-memory")
        defer { try? FileManager.default.removeItem(at: visibleRoot) }
        defer { try? FileManager.default.removeItem(at: hiddenRoot) }

        let visibleProject = makeProjectEntry(root: visibleRoot, displayName: "可见项目")
        let hiddenProject = makeProjectEntry(root: hiddenRoot, displayName: "隐藏通知项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [visibleProject, hiddenProject])
        appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        manager.setAppModel(appModel)

        manager.handleEvent(.projectCreated(hiddenProject))

        let now = Date(timeIntervalSince1970: 1_773_384_440).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(
                projectId: hiddenProject.projectId,
                displayName: hiddenProject.displayName,
                role: .triageOnly,
                now: now
            )
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        #expect(manager.frontstageSupervisorProjectNotificationSnapshot.hasActivity == false)

        let frontstageMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续")
        #expect(!frontstageMemory.contains("badge_only:delivered:隐藏通知项目"))
        #expect(!frontstageMemory.contains("通道：badge_only"))

        let explicitMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("请继续隐藏通知项目")
        #expect(explicitMemory.contains("recent_project_notifications:"))
        #expect(explicitMemory.contains("通道：badge_only"))
        #expect(explicitMemory.contains("状态：delivered"))
        #expect(explicitMemory.contains("回执："))
    }

    @Test
    func explicitHiddenProjectMemoryIncludesRuntimeActivitiesWithoutFrontstageLeak() async throws {
        let manager = SupervisorManager.makeForTesting()
        HubIPCClient.installSupervisorRemoteContinuityOverrideForTesting { _ in
            HubIPCClient.SupervisorRemoteContinuityResult(
                ok: false,
                source: "xt_cache",
                workingEntries: [],
                cacheHit: false,
                reasonCode: "remote_route_not_preferred"
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let visibleRoot = try makeProjectRoot(named: "supervisor-visible-hidden-runtime-activity")
        let hiddenRoot = try makeProjectRoot(named: "supervisor-hidden-runtime-activity")
        defer { try? FileManager.default.removeItem(at: visibleRoot) }
        defer { try? FileManager.default.removeItem(at: hiddenRoot) }

        let visibleProject = makeProjectEntry(root: visibleRoot, displayName: "可见项目")
        let hiddenProject = makeProjectEntry(root: hiddenRoot, displayName: "隐藏运行活动项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [visibleProject, hiddenProject])
        appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_460).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(
                projectId: hiddenProject.projectId,
                displayName: hiddenProject.displayName,
                role: .triageOnly,
                now: now
            )
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        manager.setRuntimeActivityEntriesForTesting(
            [
                SupervisorManager.RuntimeActivityEntry(
                    id: "runtime-hidden-activity-1",
                    createdAt: now + 1,
                    text: "hidden runtime heartbeat recovered",
                    projectId: hiddenProject.projectId,
                    projectName: hiddenProject.displayName,
                    requiresKnownProjectMatch: false
                ),
                SupervisorManager.RuntimeActivityEntry(
                    id: "runtime-visible-activity-1",
                    createdAt: now,
                    text: "visible runtime lane healthy",
                    projectId: visibleProject.projectId,
                    projectName: visibleProject.displayName,
                    requiresKnownProjectMatch: false
                )
            ]
        )

        #expect(manager.frontstageRuntimeActivityEntries.count == 1)
        #expect(manager.frontstageRuntimeActivityEntries.first?.projectId == visibleProject.projectId)

        let frontstageMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续")
        #expect(!frontstageMemory.contains("hidden runtime heartbeat recovered"))

        let explicitMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("请继续隐藏运行活动项目")
        #expect(explicitMemory.contains("recent_runtime_activities:"))
        #expect(explicitMemory.contains("hidden runtime heartbeat recovered"))
    }

    @Test
    func explicitHiddenProjectMemoryIncludesActionLedgerWithoutFrontstageLeak() async throws {
        let manager = SupervisorManager.makeForTesting()
        HubIPCClient.installSupervisorRemoteContinuityOverrideForTesting { _ in
            HubIPCClient.SupervisorRemoteContinuityResult(
                ok: false,
                source: "xt_cache",
                workingEntries: [],
                cacheHit: false,
                reasonCode: "remote_route_not_preferred"
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let visibleRoot = try makeProjectRoot(named: "supervisor-visible-hidden-action-ledger")
        let hiddenRoot = try makeProjectRoot(named: "supervisor-hidden-action-ledger")
        defer { try? FileManager.default.removeItem(at: visibleRoot) }
        defer { try? FileManager.default.removeItem(at: hiddenRoot) }

        let visibleProject = makeProjectEntry(root: visibleRoot, displayName: "可见项目")
        let hiddenProject = makeProjectEntry(root: hiddenRoot, displayName: "隐藏动作台账项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [visibleProject, hiddenProject])
        appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_470).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(
                projectId: hiddenProject.projectId,
                displayName: hiddenProject.displayName,
                role: .triageOnly,
                now: now
            )
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        manager.setActionLedgerEntriesForTesting(
            [
                (
                    id: "hidden-action-ledger-1",
                    createdAt: now + 1,
                    action: "assign_model",
                    targetRef: hiddenProject.displayName,
                    projectId: hiddenProject.projectId,
                    projectName: hiddenProject.displayName,
                    role: "coder",
                    modelId: "openai/gpt-5.4",
                    status: "queued",
                    reasonCode: "manual_switch_hidden",
                    detail: "hidden action ledger detail",
                    verifiedAt: nil,
                    triggerSource: "user_turn"
                ),
                (
                    id: "visible-action-ledger-1",
                    createdAt: now,
                    action: "assign_model",
                    targetRef: visibleProject.displayName,
                    projectId: visibleProject.projectId,
                    projectName: visibleProject.displayName,
                    role: "coder",
                    modelId: "openai/gpt-5.4",
                    status: "queued",
                    reasonCode: "manual_switch_visible",
                    detail: "visible action ledger detail",
                    verifiedAt: nil,
                    triggerSource: "user_turn"
                )
            ]
        )

        let frontstageMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续")
        #expect(!frontstageMemory.contains(hiddenProject.displayName))
        #expect(!frontstageMemory.contains("manual_switch_hidden"))

        let explicitMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("请继续隐藏动作台账项目")
        #expect(explicitMemory.contains("[action_ledger]"))
        #expect(explicitMemory.contains(hiddenProject.displayName))
        #expect(explicitMemory.contains("manual_switch_hidden"))
    }

    @Test
    func hiddenProjectActionFeedStaysOutOfFrontstageButReturnsForExplicitFocusAndExpandedJurisdiction() async throws {
        let manager = SupervisorManager.makeForTesting()
        HubIPCClient.installSupervisorRemoteContinuityOverrideForTesting { _ in
            HubIPCClient.SupervisorRemoteContinuityResult(
                ok: false,
                source: "xt_cache",
                workingEntries: [],
                cacheHit: false,
                reasonCode: "remote_route_not_preferred"
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }
        let visibleRootA = try makeProjectRoot(named: "supervisor-visible-project-action-a")
        let visibleRootB = try makeProjectRoot(named: "supervisor-visible-project-action-b")
        let hiddenRoot = try makeProjectRoot(named: "supervisor-hidden-project-action")
        defer { try? FileManager.default.removeItem(at: visibleRootA) }
        defer { try? FileManager.default.removeItem(at: visibleRootB) }
        defer { try? FileManager.default.removeItem(at: hiddenRoot) }

        let visibleProjectA = makeProjectEntry(root: visibleRootA, displayName: "可见项目A")
        let visibleProjectB = makeProjectEntry(root: visibleRootB, displayName: "可见项目B")
        let hiddenProject = makeProjectEntry(root: hiddenRoot, displayName: "隐藏动作项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [visibleProjectA, visibleProjectB, hiddenProject])
        appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_435).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(
                projectId: hiddenProject.projectId,
                displayName: hiddenProject.displayName,
                role: .triageOnly,
                now: now
            )
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        let hiddenEvent = SupervisorProjectActionEvent(
            eventId: "event-hidden-project-action-1",
            projectId: hiddenProject.projectId,
            projectName: hiddenProject.displayName,
            eventType: .progressed,
            severity: .briefCard,
            actionTitle: "隐藏动作项目完成内测并准备发版",
            actionSummary: "隐藏动作项目完成内测，等待发版窗口",
            whyItMatters: "这是隐藏项目的最新推进结果",
            nextAction: "提交发版申请",
            occurredAt: now + 2
        )
        let visibleEvent = SupervisorProjectActionEvent(
            eventId: "event-visible-project-action-1",
            projectId: visibleProjectA.projectId,
            projectName: visibleProjectA.displayName,
            eventType: .progressed,
            severity: .briefCard,
            actionTitle: "可见项目A补齐 smoke case",
            actionSummary: "可见项目A补齐 smoke case 并等待 review",
            whyItMatters: "这是可见项目的推进摘要",
            nextAction: "安排代码评审",
            occurredAt: now + 1
        )
        manager.setSupervisorRecentProjectActionEventsForTesting([hiddenEvent, visibleEvent])

        #expect(manager.supervisorRecentProjectActionEvents.count == 1)
        #expect(manager.supervisorRecentProjectActionEvents.first?.projectId == visibleProjectA.projectId)

        let frontstageMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续")
        #expect(frontstageMemory.contains(visibleEvent.actionSummary))
        #expect(!frontstageMemory.contains(hiddenEvent.actionSummary))

        let explicitHiddenMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("请继续隐藏动作项目")
        #expect(explicitHiddenMemory.contains(hiddenEvent.actionTitle))
        #expect(explicitHiddenMemory.contains(hiddenEvent.nextAction))

        let expandedJurisdiction = SupervisorJurisdictionRegistry.ownerAll(
            for: [visibleProjectA, visibleProjectB, hiddenProject],
            now: now + 30
        )
        _ = manager.applySupervisorJurisdictionRegistry(
            expandedJurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        #expect(manager.supervisorRecentProjectActionEvents.count == 2)
        #expect(manager.supervisorRecentProjectActionEvents.contains { $0.projectId == hiddenProject.projectId })
    }

    @Test
    func explicitHiddenProjectMemoryIncludesGovernanceQueuesWithoutFrontstageLeak() async throws {
        let manager = SupervisorManager.makeForTesting()
        HubIPCClient.installSupervisorRemoteContinuityOverrideForTesting { _ in
            HubIPCClient.SupervisorRemoteContinuityResult(
                ok: false,
                source: "xt_cache",
                workingEntries: [],
                cacheHit: false,
                reasonCode: "remote_route_not_preferred"
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }
        let visibleRoot = try makeProjectRoot(named: "supervisor-visible-governance-memory")
        let hiddenRoot = try makeProjectRoot(named: "supervisor-hidden-governance-memory")
        defer { try? FileManager.default.removeItem(at: visibleRoot) }
        defer { try? FileManager.default.removeItem(at: hiddenRoot) }

        let visibleProject = makeProjectEntry(root: visibleRoot, displayName: "可见项目")
        let hiddenProject = makeProjectEntry(root: hiddenRoot, displayName: "隐藏治理项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [visibleProject, hiddenProject])
        appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_450).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(
                projectId: hiddenProject.projectId,
                displayName: hiddenProject.displayName,
                role: .triageOnly,
                now: now
            )
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        manager.setPendingHubGrantsForTesting(
            [
                makePendingHubGrant(
                    id: "grant-hidden-governance-1",
                    requestId: "req-hidden-governance-1",
                    project: hiddenProject,
                    capability: "web.fetch",
                    reason: "need web access for hidden governance path",
                    createdAt: 1_773_384_451
                )
            ]
        )

        let ctx = try #require(appModel.projectContext(for: hiddenProject.projectId))
        let nowMs = Int64(1_773_384_452_000)
        try SupervisorProjectSkillCallStore.upsert(
            SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "skill-hidden-governance-1",
                projectId: hiddenProject.projectId,
                jobId: "job-hidden-governance-1",
                planId: "plan-hidden-governance-1",
                stepId: "step-hidden-governance-1",
                skillId: "browser.runtime.smoke",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .awaitingAuthorization,
                payload: ["url": .string("https://example.com/hidden-governance")],
                currentOwner: "supervisor",
                resultSummary: "waiting for local governed approval",
                denyCode: "",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: nowMs,
                updatedAtMs: nowMs,
                auditRef: "audit-skill-hidden-governance-1"
            ),
            for: ctx
        )
        manager.refreshPendingSupervisorSkillApprovalsNow()

        #expect(manager.frontstagePendingHubGrants.isEmpty)
        #expect(manager.frontstagePendingSupervisorSkillApprovals.isEmpty)

        let frontstageMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续")
        #expect(!frontstageMemory.contains("grant-hidden-governance-1"))
        #expect(!frontstageMemory.contains("skill-hidden-governance-1"))

        let explicitMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("请继续隐藏治理项目")
        #expect(explicitMemory.contains("pending_hub_grants:"))
        #expect(explicitMemory.contains("授权单号：grant-hidden-governance-1"))
        #expect(explicitMemory.contains("pending_skill_approvals:"))
        #expect(explicitMemory.contains("请求单号：skill-hidden-governance-1"))
    }

    @Test
    func explicitHiddenProjectMemoryIncludesRecentSkillActivitiesWithoutFrontstageLeak() async throws {
        let manager = SupervisorManager.makeForTesting()
        HubIPCClient.installSupervisorRemoteContinuityOverrideForTesting { _ in
            HubIPCClient.SupervisorRemoteContinuityResult(
                ok: false,
                source: "xt_cache",
                workingEntries: [],
                cacheHit: false,
                reasonCode: "remote_route_not_preferred"
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let visibleRoot = try makeProjectRoot(named: "supervisor-visible-hidden-skill-activity")
        let hiddenRoot = try makeProjectRoot(named: "supervisor-hidden-skill-activity")
        defer { try? FileManager.default.removeItem(at: visibleRoot) }
        defer { try? FileManager.default.removeItem(at: hiddenRoot) }

        let visibleProject = makeProjectEntry(root: visibleRoot, displayName: "可见项目")
        let hiddenProject = makeProjectEntry(root: hiddenRoot, displayName: "隐藏技能活动项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [visibleProject, hiddenProject])
        appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_470).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(
                projectId: hiddenProject.projectId,
                displayName: hiddenProject.displayName,
                role: .triageOnly,
                now: now
            )
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        let ctx = try #require(appModel.projectContext(for: hiddenProject.projectId))
        let nowMs = Int64(1_773_384_471_000)
        try SupervisorProjectSkillCallStore.upsert(
            SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "skill-hidden-activity-1",
                projectId: hiddenProject.projectId,
                jobId: "job-hidden-activity-1",
                planId: "plan-hidden-activity-1",
                stepId: "step-hidden-activity-1",
                skillId: "summarize",
                toolName: ToolName.summarize.rawValue,
                status: .completed,
                payload: ["url": .string("https://example.com/hidden-activity")],
                currentOwner: "supervisor",
                resultSummary: "hidden summary capture completed",
                denyCode: "",
                resultEvidenceRef: "evidence-hidden-activity-1",
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: nowMs,
                updatedAtMs: nowMs,
                auditRef: "audit-skill-hidden-activity-1"
            ),
            for: ctx
        )
        manager.refreshPendingSupervisorSkillApprovalsNow()

        #expect(manager.recentSupervisorSkillActivities.count == 1)
        #expect(manager.frontstageRecentSupervisorSkillActivities.isEmpty)

        let frontstageMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续")
        #expect(!frontstageMemory.contains("skill-hidden-activity-1"))
        #expect(!frontstageMemory.contains("hidden summary capture completed"))

        let explicitMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("请继续隐藏技能活动项目")
        #expect(explicitMemory.contains("recent_skill_activities:"))
        #expect(explicitMemory.contains("请求单号：skill-hidden-activity-1"))
        #expect(explicitMemory.contains("hidden summary capture completed"))
    }

    @Test
    func explicitHiddenProjectMemoryIncludesRecentEventLoopActivitiesWithoutFrontstageLeak() async throws {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )
        HubIPCClient.installSupervisorRemoteContinuityOverrideForTesting { _ in
            HubIPCClient.SupervisorRemoteContinuityResult(
                ok: false,
                source: "xt_cache",
                workingEntries: [],
                cacheHit: false,
                reasonCode: "remote_route_not_preferred"
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }
        manager.setSupervisorEventLoopResponseOverrideForTesting { _, _ in "" }

        let visibleRoot = try makeProjectRoot(named: "supervisor-visible-hidden-event-loop")
        let hiddenRoot = try makeProjectRoot(named: "supervisor-hidden-event-loop")
        defer { try? FileManager.default.removeItem(at: visibleRoot) }
        defer { try? FileManager.default.removeItem(at: hiddenRoot) }

        let visibleProject = makeProjectEntry(root: visibleRoot, displayName: "可见项目")
        let hiddenProject = makeProjectEntry(root: hiddenRoot, displayName: "隐藏事件循环项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [visibleProject, hiddenProject])
        appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_480).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(
                projectId: hiddenProject.projectId,
                displayName: hiddenProject.displayName,
                role: .triageOnly,
                now: now
            )
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
            project_id=\(hiddenProject.projectId)
            project_ref=\(hiddenProject.displayName)
            summary=hidden event loop callback
            next_safe_action=open_ui_review
            """,
            triggerSource: "skill_callback",
            dedupeKey: "hidden_event_loop_memory"
        )
        await manager.waitForSupervisorEventLoopForTesting()

        #expect(manager.recentSupervisorEventLoopActivitiesForTesting().count == 1)
        #expect(manager.frontstageRecentSupervisorEventLoopActivities.isEmpty)

        let frontstageMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续")
        #expect(!frontstageMemory.contains("hidden event loop callback"))

        let explicitMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("请继续隐藏事件循环项目")
        #expect(explicitMemory.contains("recent_event_loop_activities:"))
        #expect(explicitMemory.contains("hidden event loop callback"))
        #expect(explicitMemory.contains("触发：技能回调"))
    }

    @Test
    func explicitHiddenProjectMemoryIncludesRecentIncidentsWithoutFrontstageLeak() async throws {
        let manager = SupervisorManager.makeForTesting()
        HubIPCClient.installSupervisorRemoteContinuityOverrideForTesting { _ in
            HubIPCClient.SupervisorRemoteContinuityResult(
                ok: false,
                source: "xt_cache",
                workingEntries: [],
                cacheHit: false,
                reasonCode: "remote_route_not_preferred"
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let visibleRoot = try makeProjectRoot(named: "supervisor-visible-hidden-incident-memory")
        let hiddenRoot = try makeProjectRoot(named: "supervisor-hidden-incident-memory")
        defer { try? FileManager.default.removeItem(at: visibleRoot) }
        defer { try? FileManager.default.removeItem(at: hiddenRoot) }

        let visibleProject = makeProjectEntry(root: visibleRoot, displayName: "可见项目")
        let hiddenProject = AXProjectEntry(
            projectId: "12345678-1234-1234-1234-1234567890ab",
            rootPath: hiddenRoot.path,
            displayName: "隐藏事故项目",
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
        let appModel = AppModel()
        appModel.registry = registry(with: [visibleProject, hiddenProject])
        appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_490).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(
                projectId: hiddenProject.projectId,
                displayName: hiddenProject.displayName,
                role: .triageOnly,
                now: now
            )
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        manager.setSupervisorIncidentLedgerForTesting(
            [
                SupervisorLaneIncident(
                    id: "incident-hidden-memory-1",
                    laneID: "lane-hidden-incident-1",
                    taskID: UUID(),
                    projectID: UUID(uuidString: hiddenProject.projectId)!,
                    incidentCode: "runtime_error",
                    eventType: "supervisor.incident.runtime_error.handled",
                    denyCode: "runtime_error",
                    severity: .critical,
                    category: .runtime,
                    autoResolvable: false,
                    requiresUserAck: true,
                    proposedAction: .pauseLane,
                    detectedAtMs: Int64(now * 1000.0),
                    handledAtMs: Int64((now + 1) * 1000.0),
                    takeoverLatencyMs: 1200,
                    auditRef: "audit-hidden-incident-memory-1",
                    detail: "hidden incident detail",
                    status: .handled
                )
            ]
        )

        let frontstageMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续")
        #expect(!frontstageMemory.contains("hidden incident detail"))
        #expect(!frontstageMemory.contains("audit-hidden-incident-memory-1"))

        let explicitMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("请继续隐藏事故项目")
        #expect(explicitMemory.contains("recent_incidents:"))
        #expect(explicitMemory.contains("hidden incident detail"))
        #expect(explicitMemory.contains("audit-hidden-incident-memory-1"))
        #expect(explicitMemory.contains("事件：runtime_error"))
    }

    @Test
    func hiddenSupervisorIncidentDoesNotLeakOutsideJurisdictionView() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-hidden-incident")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = AXProjectEntry(
            projectId: "12345678-1234-1234-1234-1234567890ab",
            rootPath: root.path,
            displayName: "隐藏事故项目",
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
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_440).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        manager.clearMessages()
        let baselineEventCount = manager.recentEventsForTesting().count

        let incident = SupervisorLaneIncident(
            id: "incident-hidden-jurisdiction",
            laneID: "lane-hidden-1",
            taskID: UUID(),
            projectID: UUID(uuidString: project.projectId)!,
            incidentCode: "runtime_error",
            eventType: "supervisor.incident.runtime_error.handled",
            denyCode: "runtime_error",
            severity: .critical,
            category: .runtime,
            autoResolvable: false,
            requiresUserAck: true,
            proposedAction: .pauseLane,
            detectedAtMs: Int64(now * 1000.0),
            handledAtMs: Int64((now + 1) * 1000.0),
            takeoverLatencyMs: 1000,
            auditRef: "audit-hidden-incident",
            detail: "hidden incident detail",
            status: .handled
        )

        manager.handleEvent(.supervisorIncident(incident))

        #expect(manager.supervisorIncidentLedger.count == 1)
        #expect(manager.messages.isEmpty)
        let newEvents = Array(manager.recentEventsForTesting().dropFirst(baselineEventCount))
        #expect(newEvents.isEmpty)
    }

    @Test
    func visibleSupervisorIncidentUsesHumanizedFrontstageCopy() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-visible-incident-copy")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = AXProjectEntry(
            projectId: "87654321-4321-4321-4321-ba0987654321",
            rootPath: root.path,
            displayName: "前台事故项目",
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=blocked",
            currentStateSummary: "等待恢复",
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: Date().timeIntervalSince1970
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_440).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .owner, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        manager.clearMessages()
        let baselineEventCount = manager.recentEventsForTesting().count

        let incident = SupervisorLaneIncident(
            id: "incident-visible-copy",
            laneID: "lane-visible-1",
            taskID: UUID(),
            projectID: UUID(uuidString: project.projectId)!,
            incidentCode: "runtime_error",
            eventType: "supervisor.incident.runtime_error.handled",
            denyCode: "remote_export_blocked",
            severity: .critical,
            category: .runtime,
            autoResolvable: false,
            requiresUserAck: true,
            proposedAction: .pauseLane,
            detectedAtMs: Int64(now * 1000.0),
            handledAtMs: Int64((now + 1) * 1000.0),
            takeoverLatencyMs: 1000,
            auditRef: "audit-visible-incident-copy",
            detail: "visible incident detail",
            status: .handled
        )

        manager.handleEvent(.supervisorIncident(incident))

        #expect(manager.messages.contains(where: { message in
            message.role == .system &&
                message.content.contains("运行时错误（runtime_error）") &&
                message.content.contains("暂停当前泳道（pause_lane）") &&
                message.content.contains("项目：前台事故项目") &&
                !message.content.contains("deny=") &&
                !message.content.contains("project=")
        }))

        let newEvents = Array(manager.recentEventsForTesting().dropFirst(baselineEventCount))
        #expect(newEvents.contains(where: { event in
            event.contains("运行时错误（runtime_error）") &&
                event.contains("暂停当前泳道（pause_lane）") &&
                event.contains("项目：前台事故项目") &&
                !event.contains("deny=") &&
                !event.contains("project=")
        }))
    }

    @Test
    func frontstageSupervisorIncidentPresentationFormatsNotificationBodyInChinese() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-visible-incident-notification")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = AXProjectEntry(
            projectId: "13572468-2468-2468-2468-135724681357",
            rootPath: root.path,
            displayName: "通知事故项目",
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=blocked",
            currentStateSummary: "需要处理",
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: Date().timeIntervalSince1970
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_440).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .owner, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        let incident = SupervisorLaneIncident(
            id: "incident-visible-notification",
            laneID: "lane-visible-2",
            taskID: UUID(),
            projectID: UUID(uuidString: project.projectId)!,
            incidentCode: "runtime_error",
            eventType: "supervisor.incident.runtime_error.handled",
            denyCode: "remote_export_blocked",
            severity: .critical,
            category: .runtime,
            autoResolvable: false,
            requiresUserAck: true,
            proposedAction: .notifyUser,
            detectedAtMs: Int64(now * 1000.0),
            handledAtMs: Int64((now + 1) * 1000.0),
            takeoverLatencyMs: nil,
            auditRef: "audit-visible-incident-notification",
            detail: "visible incident detail",
            status: .handled
        )

        let presentation = manager.frontstageSupervisorIncidentPresentation(incident)

        #expect(presentation.title == "🚧 通知事故项目 泳道需要处理")
        #expect(presentation.notificationBody.contains("项目=通知事故项目"))
        #expect(presentation.notificationBody.contains("泳道=lane-visible-2"))
        #expect(
            presentation.notificationBody.contains(
                "摘要=运行时错误（runtime_error） → 通知用户（notify_user） · 阻断原因：Hub remote export gate 阻断了远端请求（remote_export_blocked） · 接管耗时：未知"
            )
        )
        #expect(presentation.notificationBody.contains("级别=关键（critical）"))
        #expect(presentation.notificationBody.contains("状态=已处理（handled）"))
        #expect(presentation.notificationBody.contains("需确认=是"))
        #expect(presentation.notificationBody.contains("审计=audit-visible-incident-notification"))
        #expect(!presentation.notificationBody.contains("动作="))
        #expect(!presentation.notificationBody.contains("拒绝原因="))
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
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

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：agent-browser -> guarded-automation · action=open"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "guarded-automation")
        #expect(call.toolName == ToolName.deviceBrowserControl.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("agent browser open completed"))

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].skillId == "guarded-automation")
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
    }

    @Test
    func agentBrowserMissingSourceShowsRoutedFailureSummary() throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-agent-browser-missing-source")
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-agent-browser-missing-source-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"提取页面关键信息","kind":"call_skill","status":"pending","skill_id":"agent-browser"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"agent-browser","payload":{"action":"extract"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 agent-browser extract"
        )

        #expect(rendered.contains("agent-browser -> guarded-automation · action=extract"))
        #expect(rendered.contains("payload.required_args_missing"))

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "guarded-automation")
        #expect(call.requestedSkillId == "agent-browser")
        #expect(call.status == .blocked)
        #expect(call.denyCode == "payload.required_args_missing")
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)
    }

    @Test
    func browserOpenWrapperPrefersGuardedAutomationBuiltinAndInjectsOpenAction() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-browser-open-wrapper")
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
                output: "browser open wrapper completed"
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-open-wrapper-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"打开受治理浏览器登录页","kind":"call_skill","status":"pending","skill_id":"browser.open"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let planBeforeCall = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(planBeforeCall.steps[0].skillId == "guarded-automation")

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.open","payload":{"url":"https://example.com/login"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser.open 技能"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：browser.open -> guarded-automation · action=open"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "guarded-automation")
        #expect(call.requestedSkillId == "browser.open")
        #expect(call.payload["action"]?.stringValue == "open")
        #expect(call.payload["url"]?.stringValue == "https://example.com/login")
        #expect(call.toolName == ToolName.deviceBrowserControl.rawValue)
        #expect(call.status == .completed)
        #expect(call.routingReasonCode == "preferred_builtin_selected")
        #expect(call.routingExplanation?.contains("requested entrypoint browser.open converged to preferred builtin guarded-automation") == true)
        #expect(call.resultSummary.contains("browser open wrapper completed"))

        let evidence = try #require(SupervisorSkillResultEvidenceStore.load(requestId: call.requestId, for: ctx))
        #expect(evidence.requestedSkillId == "browser.open")
        #expect(evidence.routingReasonCode == "preferred_builtin_selected")
        #expect(evidence.routingExplanation?.contains("requested entrypoint browser.open converged to preferred builtin guarded-automation") == true)

        let rawEntries = try readRawLogEntries(at: ctx.rawLogURL)
        let rawDispatch = try #require(rawEntries.last(where: {
            ($0["type"] as? String) == "supervisor_skill_call" &&
            ($0["action"] as? String) == "dispatch"
        }))
        #expect(rawDispatch["requested_skill_id"] as? String == "browser.open")
        #expect(rawDispatch["skill_id"] as? String == "guarded-automation")
        #expect(rawDispatch["routing_reason_code"] as? String == "preferred_builtin_selected")
        let dispatchRoutingExplanation = try #require(rawDispatch["routing_explanation"] as? String)
        #expect(dispatchRoutingExplanation.contains("requested entrypoint browser.open converged to preferred builtin guarded-automation"))

        let rawResult = try #require(rawEntries.last(where: {
            ($0["type"] as? String) == "supervisor_skill_result" &&
            ($0["status"] as? String) == SupervisorSkillCallStatus.completed.rawValue
        }))
        #expect(rawResult["requested_skill_id"] as? String == "browser.open")
        #expect(rawResult["skill_id"] as? String == "guarded-automation")
        #expect(rawResult["routing_reason_code"] as? String == "preferred_builtin_selected")
    }

    @Test
    func browserRuntimeInspectWrapperPrefersGuardedAutomationBuiltinAndInjectsSnapshotAction() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-browser-inspect-wrapper")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .deviceBrowserControl)
            #expect(call.args["action"]?.stringValue == "snapshot")
            #expect(call.args["url"]?.stringValue == "https://example.com/dashboard")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "browser inspect wrapper completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"检查 browser runtime 当前状态","priority":"high"}[/CREATE_JOB]"#,
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-inspect-wrapper-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"检查 browser runtime 当前状态","kind":"call_skill","status":"pending","skill_id":"browser.runtime.inspect"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let planBeforeCall = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(planBeforeCall.steps[0].skillId == "guarded-automation")

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.inspect","payload":{"url":"https://example.com/dashboard"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser.runtime.inspect 技能"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：browser.runtime.inspect -> guarded-automation · action=snapshot"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "guarded-automation")
        #expect(call.payload["action"]?.stringValue == "snapshot")
        #expect(call.payload["url"]?.stringValue == "https://example.com/dashboard")
        #expect(call.toolName == ToolName.deviceBrowserControl.rawValue)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("browser inspect wrapper completed"))
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
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

        #expect(rendered.contains("正在向 Hub 申请联网访问授权"))
        await manager.waitForSupervisorSkillDispatchForTesting()

        let queuedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(queuedCall.skillId == "guarded-automation")
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
            reason: "supervisor skill guarded-automation",
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

        #expect(manager.messages.contains(where: {
            $0.content.contains(
                "已为项目 \(project.displayName) 取得 Hub 授权并恢复技能调用：agent-browser -> guarded-automation · action=extract"
            )
        }))

        await manager.waitForSupervisorSkillDispatchForTesting()

        let resumedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(resumedCall.status == .completed)
        #expect(resumedCall.grantRequestId == "grant-agent-browser-1")
        #expect(resumedCall.grantId == "grant-agent-browser-1")
        #expect(resumedCall.toolName == ToolName.deviceBrowserControl.rawValue)
        #expect(resumedCall.resultSummary.contains("agent browser extract completed"))

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].skillId == "guarded-automation")
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

        #expect(rendered.contains("正在向 Hub 申请联网访问授权"))

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
        #expect(localMemory.contains("active_skill_execution_readiness: grant_required"))
        #expect(localMemory.contains("active_skill_requested_capability_families:"))
        #expect(localMemory.contains("active_skill_unblock_actions:"))
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
    func officialTavilyWebsearchWithoutGrantWaitsForHubGrant() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-tavily-websearch-awaiting-grant")
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-tavily-websearch-awaiting-grant-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"联网搜索最新 Swift 宏资料","kind":"call_skill","status":"pending","skill_id":"tavily-websearch"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"tavily-websearch","payload":{"q":"latest swift macros","limit":5}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 tavily-websearch"
        )

        #expect(rendered.contains("已为项目 \(project.displayName) 登记技能调用：tavily-websearch"))
        #expect(rendered.contains("正在向 Hub 申请联网访问授权"))
        #expect(!rendered.contains("preflight 未通过"))

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.skillId == "tavily-websearch")
        #expect(call.toolName == ToolName.web_search.rawValue)
        #expect(call.status == .awaitingAuthorization)
        #expect(call.denyCode == "grant_required")
        #expect(call.requiredCapability == "web.fetch")

        let waitingPlan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(waitingPlan.steps[0].status == .awaitingAuthorization)
        #expect(waitingPlan.status == .awaitingAuthorization)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .awaitingAuthorization)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续执行当前项目")
        #expect(localMemory.contains("active_skill_id: tavily-websearch"))
        #expect(localMemory.contains("active_skill_tool_name: web_search"))
        #expect(localMemory.contains("active_skill_status: awaiting_authorization"))
        #expect(localMemory.contains("active_skill_execution_readiness: grant_required"))
        #expect(localMemory.contains("active_skill_requested_capability_families:"))
        #expect(localMemory.contains("active_skill_unblock_actions:"))
    }

    @Test
    func approvedHubGrantResumesAwaitingOfficialTavilyWebsearchSkill() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorHubGrantPreflight: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-tavily-websearch-grant-resume")
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

        manager.setSupervisorNetworkAccessRequestOverrideForTesting { _, _, _ in
            HubIPCClient.NetworkAccessResult(
                state: .queued,
                source: "test",
                reasonCode: "queued",
                remainingSeconds: nil,
                grantRequestId: "grant-tavily-search-1"
            )
        }
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .web_search)
            #expect(call.args["query"]?.stringValue == "latest swift macros")
            #expect(call.args["grant_id"]?.stringValue == "grant-tavily-search-1")
            #expect(call.args["max_results"]?.stringValue == "5")
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
                    body: "tavily websearch resumed completed"
                )
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-tavily-websearch-resume-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"联网搜索最新 Swift 宏资料","kind":"call_skill","status":"pending","skill_id":"tavily-websearch"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"tavily-websearch","payload":{"q":"latest swift macros","limit":5}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 tavily-websearch"
        )

        await manager.waitForSupervisorSkillDispatchForTesting()

        let queuedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(queuedCall.status == .awaitingAuthorization)
        #expect(queuedCall.grantRequestId == "grant-tavily-search-1")
        #expect(queuedCall.requiredCapability == "web.fetch")

        let pendingGrant = SupervisorManager.SupervisorPendingGrant(
            id: "grant:grant-tavily-search-1",
            dedupeKey: "grant:grant-tavily-search-1",
            grantRequestId: "grant-tavily-search-1",
            requestId: "request-tavily-search-1",
            projectId: project.projectId,
            projectName: project.displayName,
            capability: "web.fetch",
            modelId: "",
            reason: "supervisor skill tavily-websearch",
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
                grantRequestId: "grant-tavily-search-1",
                grantId: "grant-tavily-search-1",
                expiresAtMs: (Date().timeIntervalSince1970 + 900) * 1000.0,
                reasonCode: nil
            )
        )

        await manager.waitForSupervisorSkillDispatchForTesting()

        let resumedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(resumedCall.status == .completed)
        #expect(resumedCall.grantRequestId == "grant-tavily-search-1")
        #expect(resumedCall.grantId == "grant-tavily-search-1")
        #expect(resumedCall.toolName == ToolName.web_search.rawValue)
        #expect(resumedCall.resultSummary.contains("tavily websearch resumed completed"))

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
    }

    @Test
    func approvedHubGrantWithoutGrantIdUsesSyntheticExecutionGrantToken() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorHubGrantPreflight: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-tavily-websearch-synthetic-grant")
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

        let requestScopedGrantId = "grant-tavily-search-synthetic-1"
        manager.setSupervisorNetworkAccessRequestOverrideForTesting { _, _, _ in
            HubIPCClient.NetworkAccessResult(
                state: .queued,
                source: "test",
                reasonCode: "queued",
                remainingSeconds: nil,
                grantRequestId: requestScopedGrantId
            )
        }
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .web_search)
            #expect(call.args["query"]?.stringValue == "latest swift macros")
            let injectedGrantId = call.args["grant_id"]?.stringValue ?? ""
            #expect(injectedGrantId.isEmpty == false)
            #expect(injectedGrantId != requestScopedGrantId)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: ToolExecutor.structuredOutput(
                    summary: [
                        "tool": .string(call.tool.rawValue),
                        "ok": .bool(true),
                        "grant_id": .string(injectedGrantId),
                    ],
                    body: "tavily websearch resumed with synthetic execution grant"
                )
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-tavily-websearch-synthetic-grant-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"联网搜索最新 Swift 宏资料","kind":"call_skill","status":"pending","skill_id":"tavily-websearch"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"tavily-websearch","payload":{"q":"latest swift macros","limit":5}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 tavily-websearch"
        )

        await manager.waitForSupervisorSkillDispatchForTesting()

        let queuedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(queuedCall.status == .awaitingAuthorization)
        #expect(queuedCall.grantRequestId == requestScopedGrantId)
        #expect(queuedCall.grantId == nil)

        let pendingGrant = SupervisorManager.SupervisorPendingGrant(
            id: "grant:\(requestScopedGrantId)",
            dedupeKey: "grant:\(requestScopedGrantId)",
            grantRequestId: requestScopedGrantId,
            requestId: "request-tavily-search-synthetic-1",
            projectId: project.projectId,
            projectName: project.displayName,
            capability: "web.fetch",
            modelId: "",
            reason: "supervisor skill tavily-websearch",
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
                grantRequestId: requestScopedGrantId,
                grantId: nil,
                expiresAtMs: (Date().timeIntervalSince1970 + 900) * 1000.0,
                reasonCode: nil
            )
        )

        await manager.waitForSupervisorSkillDispatchForTesting()

        let resumedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(resumedCall.status == .completed)
        #expect(resumedCall.grantRequestId == requestScopedGrantId)
        #expect(resumedCall.grantId?.isEmpty == false)
        #expect((resumedCall.grantId ?? "") != requestScopedGrantId)
        #expect(resumedCall.toolName == ToolName.web_search.rawValue)
        #expect(resumedCall.resultSummary.contains("tavily websearch resumed with synthetic execution grant"))
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
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
    func hiddenProjectSkillQueueMessageDoesNotLeakOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-skill-vetter-hidden-queue")
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
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "hidden skill queue completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"扫描 hidden skill 执行风险","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-skill-vetter-hidden-queue-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"扫描 hidden 命令执行风险模式","kind":"call_skill","status":"pending","skill_id":"skill-vetter"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let now = Date(timeIntervalSince1970: 1_773_384_300).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)
        manager.clearMessages()

        let rendered = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"skill-vetter","payload":{"action":"scan_exec","dir":"official-agent-skills","glob":"**/*.{js,ts,py,swift,md,json}"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 hidden skill-vetter scan_exec"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 排队技能调用：skill-vetter"))
        #expect(manager.messages.contains(where: {
            $0.content.contains("✅ 已为项目 \(project.displayName) 排队技能调用：skill-vetter")
        }) == false)

        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("hidden skill queue completed"))
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
    func approvedHubGrantWithoutGrantIdUsesSyntheticExecutionGrantTokenForBuiltinWebSearch() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorHubGrantPreflight: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-call-web-search-synthetic-grant")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let requestScopedGrantId = "grant-web-search-synthetic-1"
        manager.setSupervisorNetworkAccessRequestOverrideForTesting { _, _, _ in
            HubIPCClient.NetworkAccessResult(
                state: .queued,
                source: "test",
                reasonCode: "queued",
                remainingSeconds: nil,
                grantRequestId: requestScopedGrantId
            )
        }
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .web_search)
            #expect(call.args["query"]?.stringValue == "browser runtime smoke fix")
            let injectedGrantId = call.args["grant_id"]?.stringValue ?? ""
            #expect(injectedGrantId.isEmpty == false)
            #expect(injectedGrantId != requestScopedGrantId)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: ToolExecutor.structuredOutput(
                    summary: [
                        "tool": .string(call.tool.rawValue),
                        "ok": .bool(true),
                        "grant_id": .string(injectedGrantId),
                    ],
                    body: "builtin web search resumed with synthetic execution grant"
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-web-search-synthetic-grant-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索 browser runtime 修复方案","kind":"call_skill","status":"pending","skill_id":"web.search"}]}[/UPSERT_PLAN]
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
        #expect(queuedCall.grantRequestId == requestScopedGrantId)
        #expect(queuedCall.grantId == nil)
        #expect(queuedCall.requiredCapability == "web.fetch")

        let pendingGrant = SupervisorManager.SupervisorPendingGrant(
            id: "grant:\(requestScopedGrantId)",
            dedupeKey: "grant:\(requestScopedGrantId)",
            grantRequestId: requestScopedGrantId,
            requestId: "request-web-search-synthetic-1",
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
                grantRequestId: requestScopedGrantId,
                grantId: nil,
                expiresAtMs: (Date().timeIntervalSince1970 + 900) * 1000.0,
                reasonCode: nil
            )
        )

        await manager.waitForSupervisorSkillDispatchForTesting()

        let resumedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(resumedCall.status == .completed)
        #expect(resumedCall.grantRequestId == requestScopedGrantId)
        #expect(resumedCall.grantId?.isEmpty == false)
        #expect((resumedCall.grantId ?? "") != requestScopedGrantId)
        #expect(resumedCall.toolName == ToolName.web_search.rawValue)
        #expect(resumedCall.resultSummary.contains("builtin web search resumed with synthetic execution grant"))

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
    }

    @Test
    func approvedHubGrantResumeMessageDoesNotLeakWhenProjectOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorHubGrantPreflight: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-grant-approval-hidden-resume")
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
                grantRequestId: "grant-web-search-hidden-resume"
            )
        }
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .web_search)
            #expect(call.args["query"]?.stringValue == "hidden browser runtime smoke fix")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "hidden grant resume completed"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"搜索 hidden browser runtime 修复方案","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-web-search-hidden-resume-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索 hidden browser runtime 修复方案","kind":"call_skill","status":"pending","skill_id":"web.search"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"web.search","payload":{"query":"hidden browser runtime smoke fix","max_results":3}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 hidden web search 技能"
        )

        await manager.waitForSupervisorSkillDispatchForTesting()

        let now = Date(timeIntervalSince1970: 1_773_384_350).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)
        manager.clearMessages()

        let pendingGrant = SupervisorManager.SupervisorPendingGrant(
            id: "grant:grant-web-search-hidden-resume",
            dedupeKey: "grant:grant-web-search-hidden-resume",
            grantRequestId: "grant-web-search-hidden-resume",
            requestId: "request-web-search-hidden-resume",
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
            nextAction: "批准后恢复 hidden skill"
        )
        await manager.completePendingHubGrantActionForTesting(
            grant: pendingGrant,
            approve: true,
            result: HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .approved,
                source: "test",
                grantRequestId: "grant-web-search-hidden-resume",
                grantId: "grant-live-hidden-resume",
                expiresAtMs: nil,
                reasonCode: nil
            )
        )

        #expect(manager.messages.contains(where: {
            $0.content.contains("已为项目 \(project.displayName) 取得 Hub 授权并恢复技能调用：web.search")
        }) == false)

        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("hidden grant resume completed"))
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
            #expect(userMessage.contains("review_trigger=periodic_pulse"))
            #expect(userMessage.contains("review_level_hint=r1_pulse"))
            #expect(userMessage.contains("review_run_kind=event_driven"))
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

        let reviewSnapshot = SupervisorReviewNoteStore.load(for: ctx)
        let review = try #require(reviewSnapshot.notes.first)
        #expect(review.trigger == .periodicPulse)
        #expect(review.reviewLevel == .r1Pulse)
        #expect(review.targetRole == .supervisor)
        #expect(review.deliveryMode == .contextAppend)
        #expect(!review.ackRequired)
        #expect(review.summary.contains("已为项目"))

        let guidanceSnapshot = SupervisorGuidanceInjectionStore.load(for: ctx)
        #expect(guidanceSnapshot.items.isEmpty)
    }

    @Test
    func skillCallbackAutoFollowUpRunsWhenProjectOutsideJurisdictionView() async throws {
        actor ToolExecutionGate {
            private var open = false

            func waitUntilOpen() async {
                while !open {
                    await Task.yield()
                }
            }

            func release() {
                open = true
            }
        }

        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-skill-callback-hidden-success")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let gate = ToolExecutionGate()
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .project_snapshot)
            await gate.waitUntilOpen()
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "snapshot export completed after jurisdiction refresh"
            )
        }
        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "skill_callback")
            #expect(userMessage.contains("trigger=skill_callback"))
            #expect(userMessage.contains("project_ref=\(project.displayName)"))
            #expect(userMessage.contains("status=completed"))
            #expect(userMessage.contains("review_trigger=periodic_pulse"))
            #expect(userMessage.contains("review_level_hint=r1_pulse"))
            #expect(userMessage.contains("review_run_kind=event_driven"))
            #expect(userMessage.contains("next_pending_steps:"))
            #expect(userMessage.contains("step-002"))
            #expect(!userMessage.contains(root.lastPathComponent))
            return #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"hidden skill callback pulse follow-up","priority":"normal","source":"skill_callback","current_owner":"supervisor"}[/CREATE_JOB]"#
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"导出 hidden project snapshot","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-project-snapshot-hidden-success-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"读取 hidden project snapshot","kind":"call_skill","status":"pending","skill_id":"project.snapshot"},{"step_id":"step-002","title":"写入 hidden follow-up 摘要","kind":"write_memory","status":"pending"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"project.snapshot","payload":{}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 project snapshot 技能"
        )

        for _ in 0..<12 {
            await Task.yield()
        }

        let now = Date(timeIntervalSince1970: 1_773_384_250).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        await gate.release()
        await manager.waitForSupervisorSkillDispatchForTesting()
        await manager.waitForSupervisorEventLoopForTesting()

        let jobs = SupervisorProjectJobStore.load(for: ctx).jobs
        let followUp = try #require(jobs.first(where: { $0.goal == "hidden skill callback pulse follow-up" }))
        #expect(followUp.source == .skillCallback)
        #expect(followUp.currentOwner == "supervisor")

        let reviewSnapshot = SupervisorReviewNoteStore.load(for: ctx)
        let review = try #require(reviewSnapshot.notes.first)
        #expect(review.trigger == .periodicPulse)
        #expect(review.reviewLevel == .r1Pulse)
        #expect(review.targetRole == .supervisor)
        #expect(review.deliveryMode == .contextAppend)
        #expect(!review.ackRequired)

        let guidanceSnapshot = SupervisorGuidanceInjectionStore.load(for: ctx)
        #expect(guidanceSnapshot.items.isEmpty)
    }

    @Test
    func skillCallbackFailureFollowUpUsesBlockerReviewTrigger() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-skill-callback-failure-review")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .project_snapshot)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: "snapshot export failed"
            )
        }
        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "skill_callback")
            #expect(userMessage.contains("status=failed"))
            #expect(userMessage.contains("review_trigger=blocker_detected"))
            #expect(userMessage.contains("review_level_hint=r2_strategic"))
            #expect(userMessage.contains("review_run_kind=event_driven"))
            #expect(userMessage.contains("attention_steps:"))
            #expect(userMessage.contains("step-001"))
            return #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"处理失败 skill callback","priority":"high","source":"skill_callback","current_owner":"supervisor"}[/CREATE_JOB]"#
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"导出 project snapshot","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-project-snapshot-failure-review-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"读取当前 project snapshot","kind":"call_skill","status":"pending","skill_id":"project.snapshot"}]}[/UPSERT_PLAN]
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
        let followUp = try #require(jobs.first(where: { $0.goal == "处理失败 skill callback" }))
        #expect(followUp.source == .skillCallback)

        let reviewSnapshot = SupervisorReviewNoteStore.load(for: ctx)
        let review = try #require(reviewSnapshot.notes.first)
        #expect(review.trigger == .blockerDetected)
        #expect(review.reviewLevel == .r2Strategic)
        #expect(review.targetRole == .supervisor)
        #expect(review.deliveryMode == .contextAppend)
        #expect(!review.ackRequired)

        let guidanceSnapshot = SupervisorGuidanceInjectionStore.load(for: ctx)
        #expect(guidanceSnapshot.items.isEmpty)
    }

    @Test
    func skillCallbackFailureFollowUpRunsWhenProjectOutsideJurisdictionView() async throws {
        actor ToolExecutionGate {
            private var open = false

            func waitUntilOpen() async {
                while !open {
                    await Task.yield()
                }
            }

            func release() {
                open = true
            }
        }

        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-skill-callback-hidden-failure-review")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let gate = ToolExecutionGate()
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .project_snapshot)
            await gate.waitUntilOpen()
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: "snapshot export failed after jurisdiction refresh"
            )
        }
        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "skill_callback")
            #expect(userMessage.contains("trigger=skill_callback"))
            #expect(userMessage.contains("project_ref=\(project.displayName)"))
            #expect(userMessage.contains("status=failed"))
            #expect(userMessage.contains("review_trigger=blocker_detected"))
            #expect(userMessage.contains("review_level_hint=r2_strategic"))
            #expect(userMessage.contains("review_run_kind=event_driven"))
            #expect(userMessage.contains("attention_steps:"))
            #expect(userMessage.contains("step-001"))
            #expect(!userMessage.contains(root.lastPathComponent))
            return #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"处理隐藏项目 skill callback","priority":"high","source":"skill_callback","current_owner":"supervisor"}[/CREATE_JOB]"#
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"导出 hidden project snapshot","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-project-snapshot-hidden-failure-review-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"读取 hidden project snapshot","kind":"call_skill","status":"pending","skill_id":"project.snapshot"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"project.snapshot","payload":{}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 project snapshot 技能"
        )

        for _ in 0..<12 {
            await Task.yield()
        }

        let now = Date(timeIntervalSince1970: 1_773_384_300).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        await gate.release()
        await manager.waitForSupervisorSkillDispatchForTesting()
        await manager.waitForSupervisorEventLoopForTesting()

        let jobs = SupervisorProjectJobStore.load(for: ctx).jobs
        let followUp = try #require(jobs.first(where: { $0.goal == "处理隐藏项目 skill callback" }))
        #expect(followUp.source == .skillCallback)
        #expect(followUp.currentOwner == "supervisor")

        let reviewSnapshot = SupervisorReviewNoteStore.load(for: ctx)
        let review = try #require(reviewSnapshot.notes.first)
        #expect(review.trigger == .blockerDetected)
        #expect(review.reviewLevel == .r2Strategic)
        #expect(review.targetRole == .supervisor)
        #expect(review.deliveryMode == .contextAppend)
        #expect(!review.ackRequired)

        let guidanceSnapshot = SupervisorGuidanceInjectionStore.load(for: ctx)
        #expect(guidanceSnapshot.items.isEmpty)
    }

    @Test
    func skillCallbackWithUIReviewConcernRoutesToUIReviewAndSignalsSafeNextAction() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-ui-review-safe-next-action")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)
        try AXProjectStore.saveConfig(config, for: ctx)

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeSupervisorTrustedAutomationPermissionReadiness()
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let uiReviewSnapshot = XTUIReviewAgentEvidenceSnapshot(
            schemaVersion: XTUIReviewAgentEvidenceSnapshot.currentSchemaVersion,
            reviewID: "review-ui-safe-1",
            projectID: project.projectId,
            bundleID: "bundle-ui-safe-1",
            auditRef: "audit-ui-safe-1",
            reviewRef: "local://.xterminal/ui_review/reviews/review-ui-safe-1.json",
            bundleRef: "local://.xterminal/ui_observation/bundles/bundle-ui-safe-1.json",
            updatedAtMs: 3_000,
            verdict: .attentionNeeded,
            confidence: .medium,
            sufficientEvidence: true,
            objectiveReady: false,
            issueCodes: ["critical_action_not_visible"],
            summary: "Primary CTA is missing, so the next step should return to the UI review workspace before continuing.",
            artifactRefs: ["screenshot_ref=local://.xterminal/ui_observation/artifacts/bundle-ui-safe-1/full.png"],
            artifactPaths: ["/tmp/bundle-ui-safe-1/full.png"],
            checks: ["critical_action=fail :: Expected CTA is missing from the current page."],
            trend: ["status=regressed"],
            comparison: ["added_issues=critical_action_not_visible"],
            recentHistory: ["review_id=review-ui-safe-0 verdict=ready"]
        )
        try XTUIReviewAgentEvidenceStore.write(uiReviewSnapshot, for: ctx)
        let uiReviewEvidenceRef = XTUIReviewAgentEvidenceStore.reviewRef(reviewID: uiReviewSnapshot.reviewID)

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .deviceBrowserControl)
            #expect(call.args["action"]?.stringValue == "snapshot")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: """
                {"ok":true,"ui_review_agent_evidence_ref":"\(uiReviewEvidenceRef)","ui_review_summary":"Critical CTA missing","ui_review_issue_codes":["critical_action_not_visible"]}
                """
            )
        }
        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "skill_callback")
            #expect(userMessage.contains("ui_review_agent_evidence_ref=\(uiReviewEvidenceRef)"))
            #expect(userMessage.contains("ui_review_verdict=attention_needed"))
            #expect(userMessage.contains("ui_review_issue_codes=critical_action_not_visible"))
            #expect(userMessage.contains("ui_review_repair_action=repair_primary_cta_visibility"))
            #expect(userMessage.contains("ui_review_repair_focus=critical_action"))
            #expect(userMessage.contains("ui_review_repair_summary=Repair primary CTA visibility before continuing browser automation."))
            #expect(userMessage.contains("ui_review_trend=status=regressed"))
            #expect(userMessage.contains("next_safe_action=open_ui_review"))
            return ""
        }

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"检查 browser runtime 当前状态","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-ui-review-safe-next-action-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"检查 browser runtime 当前状态","kind":"call_skill","status":"pending","skill_id":"browser.runtime.inspect"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.inspect","payload":{"url":"https://example.com/dashboard"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser.runtime.inspect 技能"
        )

        await manager.waitForSupervisorSkillDispatchForTesting()
        await manager.waitForSupervisorEventLoopForTesting()

        manager.refreshRecentSupervisorSkillActivitiesNow()
        let activity = try #require(manager.recentSupervisorSkillActivities.first)
        let activityURL = try #require(activity.actionURL)
        let activityRoute = try #require(URL(string: activityURL).flatMap(XTDeepLinkParser.parse))

        #expect(
            activityRoute == .project(
                XTDeepLinkProjectRoute(
                    projectId: project.projectId,
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: nil,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false,
                    governanceDestination: .uiReview
                )
            )
        )

        let eventLoopActivity = try #require(manager.recentSupervisorEventLoopActivities.first)
        #expect(eventLoopActivity.triggerSummary.contains("Repair primary CTA visibility before continuing browser automation."))
        #expect(eventLoopActivity.policySummary.contains("repair=repair_primary_cta_visibility@critical_action"))
        let eventLoopAction = try #require(SupervisorEventLoopActionPresentation.action(for: eventLoopActivity))
        let eventLoopRoute = try #require(URL(string: eventLoopAction.url).flatMap(XTDeepLinkParser.parse))

        #expect(eventLoopAction.label == "打开 UI 审查")
        #expect(
            eventLoopRoute == .project(
                XTDeepLinkProjectRoute(
                    projectId: project.projectId,
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: nil,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false,
                    governanceDestination: .uiReview
                )
            )
        )

        let guidance = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(guidance.targetRole == .projectChat)
        #expect(guidance.deliveryMode == .stopSignal)
        #expect(guidance.interventionMode == .stopImmediately)
        #expect(guidance.safePointPolicy == .immediate)
        #expect(guidance.ackRequired)
        #expect(guidance.workOrderRef == "plan:plan-ui-review-safe-next-action-v1")
        #expect(guidance.guidanceText.contains("repair_action=repair_primary_cta_visibility"))
        #expect(guidance.guidanceText.contains("ui_review_ref=\(uiReviewEvidenceRef)"))
        #expect(guidance.guidanceText.contains("next_safe_action=open_ui_review"))

        let now = Date(timeIntervalSince1970: 1_773_500_000).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .owner, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)
        let drillDown = manager.buildSupervisorProjectDrillDown(
            for: project,
            requestedScope: .capsuleOnly,
            recentMessageLimit: 0
        )
        #expect(drillDown.pendingAckGuidance?.injectionId == guidance.injectionId)
        #expect(drillDown.latestGuidance?.injectionId == guidance.injectionId)

        let storedRecord = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        manager.persistSupervisorUIReviewRepairGuidanceForTesting(
            record: storedRecord,
            project: project,
            ctx: ctx,
            status: storedRecord.status,
            reason: storedRecord.resultSummary
        )
        manager.persistSupervisorUIReviewRepairGuidanceForTesting(
            record: storedRecord,
            project: project,
            ctx: ctx,
            status: storedRecord.status,
            reason: storedRecord.resultSummary
        )
        let guidanceSnapshot = SupervisorGuidanceInjectionStore.load(for: ctx)
        #expect(guidanceSnapshot.items.count == 1)
        #expect(guidanceSnapshot.items.first?.injectionId == guidance.injectionId)
    }

    @Test
    func skillCallbackWithUIReviewConcernRunsWhenProjectOutsideJurisdictionView() async throws {
        actor ToolExecutionGate {
            private var entered = false
            private var open = false

            func enterAndWait() async {
                entered = true
                while !open {
                    await Task.yield()
                }
            }

            func waitUntilEntered() async {
                while !entered {
                    await Task.yield()
                }
            }

            func release() {
                open = true
            }
        }

        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-ui-review-hidden-project")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
            )
            .settingGovernedAutoApproveLocalToolCalls(enabled: true)
        try AXProjectStore.saveConfig(config, for: ctx)

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeSupervisorTrustedAutomationPermissionReadiness()
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let uiReviewSnapshot = XTUIReviewAgentEvidenceSnapshot(
            schemaVersion: XTUIReviewAgentEvidenceSnapshot.currentSchemaVersion,
            reviewID: "review-ui-hidden-1",
            projectID: project.projectId,
            bundleID: "bundle-ui-hidden-1",
            auditRef: "audit-ui-hidden-1",
            reviewRef: "local://.xterminal/ui_review/reviews/review-ui-hidden-1.json",
            bundleRef: "local://.xterminal/ui_observation/bundles/bundle-ui-hidden-1.json",
            updatedAtMs: 3_200,
            verdict: .attentionNeeded,
            confidence: .medium,
            sufficientEvidence: true,
            objectiveReady: false,
            issueCodes: ["critical_action_not_visible"],
            summary: "Primary CTA is missing after the hidden-project jurisdiction refresh.",
            artifactRefs: ["screenshot_ref=local://.xterminal/ui_observation/artifacts/bundle-ui-hidden-1/full.png"],
            artifactPaths: ["/tmp/bundle-ui-hidden-1/full.png"],
            checks: ["critical_action=fail :: Expected CTA is missing from the current page."],
            trend: ["status=regressed"],
            comparison: ["added_issues=critical_action_not_visible"],
            recentHistory: ["review_id=review-ui-hidden-0 verdict=ready"]
        )
        try XTUIReviewAgentEvidenceStore.write(uiReviewSnapshot, for: ctx)
        let uiReviewEvidenceRef = XTUIReviewAgentEvidenceStore.reviewRef(reviewID: uiReviewSnapshot.reviewID)

        let gate = ToolExecutionGate()
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .deviceBrowserControl)
            #expect(call.args["action"]?.stringValue == "snapshot")
            await gate.enterAndWait()
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: """
                {"ok":true,"ui_review_agent_evidence_ref":"\(uiReviewEvidenceRef)","ui_review_summary":"Critical CTA missing","ui_review_issue_codes":["critical_action_not_visible"]}
                """
            )
        }
        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "skill_callback")
            #expect(userMessage.contains("project_ref=\(project.displayName)"))
            #expect(userMessage.contains("ui_review_agent_evidence_ref=\(uiReviewEvidenceRef)"))
            #expect(userMessage.contains("ui_review_verdict=attention_needed"))
            #expect(userMessage.contains("ui_review_issue_codes=critical_action_not_visible"))
            #expect(userMessage.contains("ui_review_repair_action=repair_primary_cta_visibility"))
            #expect(userMessage.contains("next_safe_action=open_ui_review"))
            #expect(!userMessage.contains(root.lastPathComponent))
            return ""
        }

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"检查 hidden browser runtime 当前状态","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-ui-review-hidden-project-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"检查 hidden browser runtime 当前状态","kind":"call_skill","status":"pending","skill_id":"browser.runtime.inspect"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.inspect","payload":{"url":"https://example.com/dashboard"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser.runtime.inspect 技能"
        )

        await gate.waitUntilEntered()

        let now = Date(timeIntervalSince1970: 1_773_500_100).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        await gate.release()
        await manager.waitForSupervisorSkillDispatchForTesting()
        await manager.waitForSupervisorEventLoopForTesting()

        manager.refreshRecentSupervisorSkillActivitiesNow()
        let activity = try #require(manager.recentSupervisorSkillActivities.first(where: { $0.projectId == project.projectId }))
        let activityURL = try #require(activity.actionURL)
        let activityRoute = try #require(URL(string: activityURL).flatMap(XTDeepLinkParser.parse))
        #expect(
            activityRoute == .project(
                XTDeepLinkProjectRoute(
                    projectId: project.projectId,
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: nil,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false,
                    governanceDestination: .uiReview
                )
            )
        )

        let eventLoopActivity = try #require(manager.recentSupervisorEventLoopActivities.first)
        #expect(eventLoopActivity.triggerSummary.contains("Repair primary CTA visibility before continuing browser automation."))
        #expect(eventLoopActivity.policySummary.contains("repair=repair_primary_cta_visibility@critical_action"))

        let guidance = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(guidance.targetRole == .projectChat)
        #expect(guidance.deliveryMode == .stopSignal)
        #expect(guidance.interventionMode == .stopImmediately)
        #expect(guidance.safePointPolicy == .immediate)
        #expect(guidance.ackRequired)
        #expect(guidance.guidanceText.contains("ui_review_ref=\(uiReviewEvidenceRef)"))
        #expect(guidance.guidanceText.contains("next_safe_action=open_ui_review"))
    }

    @Test
    func skillCallbackTerminalCompletionUsesPreDoneReviewTrigger() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-skill-callback-pre-done-review")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .project_snapshot)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "snapshot export completed"
            )
        }
        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "skill_callback")
            #expect(userMessage.contains("status=completed"))
            #expect(userMessage.contains("review_trigger=pre_done_summary"))
            #expect(userMessage.contains("review_level_hint=r3_rescue"))
            #expect(userMessage.contains("review_run_kind=event_driven"))
            #expect(userMessage.contains("active_plan_status=completed"))
            #expect(userMessage.contains("next_pending_steps:"))
            return #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"处理 pre-done review 后的下一步","priority":"high","source":"skill_callback","current_owner":"supervisor"}[/CREATE_JOB]"#
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"导出最终 project snapshot","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-project-snapshot-pre-done-review-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"导出最终 project snapshot","kind":"call_skill","status":"pending","skill_id":"project.snapshot"}]}[/UPSERT_PLAN]
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
        let followUp = try #require(jobs.first(where: { $0.goal == "处理 pre-done review 后的下一步" }))
        #expect(followUp.source == .skillCallback)

        let reviewSnapshot = SupervisorReviewNoteStore.load(for: ctx)
        let review = try #require(reviewSnapshot.notes.first)
        #expect(review.trigger == .preDoneSummary)
        #expect(review.reviewLevel == .r3Rescue)
        #expect(review.targetRole == .coder)
        #expect(review.deliveryMode == .contextAppend)

        let guidanceSnapshot = SupervisorGuidanceInjectionStore.load(for: ctx)
        let guidance = try #require(guidanceSnapshot.items.first)
        #expect(guidance.targetRole == .coder)
        #expect(guidance.deliveryMode == .contextAppend)
    }

    @Test
    func skillCallbackTerminalCompletionRunsWhenProjectOutsideJurisdictionView() async throws {
        actor ToolExecutionGate {
            private var entered = false
            private var open = false

            func enterAndWait() async {
                entered = true
                while !open {
                    await Task.yield()
                }
            }

            func waitUntilEntered() async {
                while !entered {
                    await Task.yield()
                }
            }

            func release() {
                open = true
            }
        }

        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-skill-callback-hidden-pre-done-review")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let gate = ToolExecutionGate()
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .project_snapshot)
            await gate.enterAndWait()
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "snapshot export completed after hidden-jurisdiction refresh"
            )
        }
        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "skill_callback")
            #expect(userMessage.contains("project_ref=\(project.displayName)"))
            #expect(userMessage.contains("status=completed"))
            #expect(userMessage.contains("review_trigger=pre_done_summary"))
            #expect(userMessage.contains("review_level_hint=r3_rescue"))
            #expect(userMessage.contains("review_run_kind=event_driven"))
            #expect(userMessage.contains("active_plan_status=completed"))
            #expect(userMessage.contains("next_pending_steps:"))
            #expect(!userMessage.contains(root.lastPathComponent))
            return #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"处理隐藏项目 pre-done review","priority":"high","source":"skill_callback","current_owner":"supervisor"}[/CREATE_JOB]"#
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"导出 hidden 最终 project snapshot","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-project-snapshot-hidden-pre-done-review-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"导出 hidden 最终 project snapshot","kind":"call_skill","status":"pending","skill_id":"project.snapshot"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"project.snapshot","payload":{}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 project snapshot 技能"
        )

        await gate.waitUntilEntered()

        let now = Date(timeIntervalSince1970: 1_773_500_200).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        await gate.release()
        await manager.waitForSupervisorSkillDispatchForTesting()
        await manager.waitForSupervisorEventLoopForTesting()

        let jobs = SupervisorProjectJobStore.load(for: ctx).jobs
        let followUp = try #require(jobs.first(where: { $0.goal == "处理隐藏项目 pre-done review" }))
        #expect(followUp.source == .skillCallback)
        #expect(followUp.currentOwner == "supervisor")

        let reviewSnapshot = SupervisorReviewNoteStore.load(for: ctx)
        let review = try #require(reviewSnapshot.notes.first)
        #expect(review.trigger == .preDoneSummary)
        #expect(review.reviewLevel == .r3Rescue)
        #expect(review.targetRole == .coder)
        #expect(review.deliveryMode == .contextAppend)

        let guidanceSnapshot = SupervisorGuidanceInjectionStore.load(for: ctx)
        let guidance = try #require(guidanceSnapshot.items.first)
        #expect(guidance.targetRole == .coder)
        #expect(guidance.deliveryMode == .contextAppend)
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
            #expect(userMessage.contains("authorization_mode=hub_grant"))
            #expect(userMessage.contains("resolution_mode=denied"))
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
    func grantResolutionAutoFollowUpRunsWhenProjectOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorHubGrantPreflight: true,
            enableSupervisorEventLoopAutoFollowUp: true
        )
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-grant-resolution-hidden-project")
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
                grantRequestId: "grant-web-search-hidden-event-loop"
            )
        }
        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "grant_resolution")
            #expect(userMessage.contains("trigger=grant_resolution"))
            #expect(userMessage.contains("project_ref=\(project.displayName)"))
            #expect(userMessage.contains("authorization_mode=hub_grant"))
            #expect(userMessage.contains("resolution_mode=denied"))
            #expect(userMessage.contains("reason_code=grant_denied"))
            #expect(!userMessage.contains(root.lastPathComponent))
            return #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"hidden grant resolution follow-up","priority":"high","source":"grant_resolution","current_owner":"supervisor"}[/CREATE_JOB]"#
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-web-search-hidden-event-loop-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索 browser runtime 修复方案","kind":"call_skill","status":"pending","skill_id":"web.search"}]}[/UPSERT_PLAN]
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

        let now = Date(timeIntervalSince1970: 1_773_384_300).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        let pendingGrant = SupervisorManager.SupervisorPendingGrant(
            id: "grant:grant-web-search-hidden-event-loop",
            dedupeKey: "grant:grant-web-search-hidden-event-loop",
            grantRequestId: "grant-web-search-hidden-event-loop",
            requestId: "request-web-search-hidden-event-loop",
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
                grantRequestId: "grant-web-search-hidden-event-loop",
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "grant_denied"
            )
        )

        await manager.waitForSupervisorEventLoopForTesting()

        let jobs = SupervisorProjectJobStore.load(for: ctx).jobs
        #expect(jobs.count == 2)
        let followUp = try #require(jobs.first(where: { $0.goal == "hidden grant resolution follow-up" }))
        #expect(followUp.source == .grantResolution)
        #expect(followUp.priority == .high)
    }

    @Test
    func heartbeatGovernedReviewRunsWhenProjectOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)

        let root = try makeProjectRoot(named: "supervisor-heartbeat-hidden-review")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .periodic,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 60,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: false,
            eventReviewTriggers: []
        )
        try AXProjectStore.saveConfig(config, for: ctx)
        _ = try SupervisorReviewScheduleStore.touchHeartbeat(
            for: ctx,
            config: config,
            nowMs: 1_773_384_000_000
        )

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "heartbeat")
            #expect(userMessage.contains("trigger=heartbeat"))
            #expect(userMessage.contains("project_ref=\(project.displayName)"))
            #expect(userMessage.contains("review_trigger=periodic_pulse"))
            #expect(!userMessage.contains(root.lastPathComponent))
            return #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"hidden heartbeat review follow-up","priority":"normal","source":"heartbeat","current_owner":"supervisor"}[/CREATE_JOB]"#
        }

        let now = Date(timeIntervalSince1970: 1_773_384_500).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        manager.emitHeartbeatCycleForTesting(force: true, reason: "timer")
        await manager.waitForSupervisorEventLoopForTesting()

        let jobs = SupervisorProjectJobStore.load(for: ctx).jobs
        let followUp = try #require(jobs.first(where: { $0.goal == "hidden heartbeat review follow-up" }))
        #expect(followUp.source == .heartbeat)
        #expect(followUp.priority == .normal)
    }

    @Test
    func grantApprovalResumeUsesFriendlyProjectName() async throws {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorHubGrantPreflight: true
        )
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-grant-approval-resume-friendly-name")
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
                grantRequestId: "grant-web-search-friendly-resume"
            )
        }
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .web_search)
            #expect(call.args["query"]?.stringValue == "browser runtime smoke fix")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "web search resumed with approved grant"
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-web-search-friendly-resume-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"搜索 browser runtime 修复方案","kind":"call_skill","status":"pending","skill_id":"web.search"}]}[/UPSERT_PLAN]
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
            id: "grant:grant-web-search-friendly-resume",
            dedupeKey: "grant:grant-web-search-friendly-resume",
            grantRequestId: "grant-web-search-friendly-resume",
            requestId: "request-web-search-friendly-resume",
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
            nextAction: "批准后恢复 skill"
        )
        await manager.completePendingHubGrantActionForTesting(
            grant: pendingGrant,
            approve: true,
            result: HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .approved,
                source: "test",
                grantRequestId: "grant-web-search-friendly-resume",
                grantId: "grant-live-friendly-resume",
                expiresAtMs: nil,
                reasonCode: nil
            )
        )

        #expect(manager.messages.contains(where: {
            $0.content.contains("已为项目 \(project.displayName) 取得 Hub 授权并恢复技能调用：web.search") &&
                !$0.content.contains(root.lastPathComponent)
        }))

        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("web search resumed with approved grant"))

        let plan = try #require(SupervisorProjectPlanStore.load(for: ctx).plans.first)
        #expect(plan.steps[0].status == .completed)
        #expect(plan.status == .completed)
        #expect(SupervisorProjectJobStore.load(for: ctx).jobs.first?.status == .completed)
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
            #expect(userMessage.contains("project_ref=\(project.displayName)"))
            #expect(userMessage.contains("authorization_mode=local_approval"))
            #expect(userMessage.contains("resolution_mode=denied"))
            #expect(userMessage.contains("reason_code=local_approval_denied"))
            #expect(userMessage.contains("attention_steps:"))
            #expect(userMessage.contains("step-001"))
            #expect(!userMessage.contains(root.lastPathComponent))
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
    func approvalResolutionAutoFollowUpRunsWhenProjectOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-approval-resolution-hidden-project")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "approval_resolution")
            #expect(userMessage.contains("trigger=approval_resolution"))
            #expect(userMessage.contains("project_ref=\(project.displayName)"))
            #expect(userMessage.contains("authorization_mode=local_approval"))
            #expect(userMessage.contains("resolution_mode=denied"))
            #expect(userMessage.contains("reason_code=local_approval_denied"))
            #expect(!userMessage.contains(root.lastPathComponent))
            return #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"hidden approval resolution follow-up","priority":"high","source":"approval_resolution","current_owner":"supervisor"}[/CREATE_JOB]"#
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-approval-hidden-event-loop-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        let now = Date(timeIntervalSince1970: 1_773_384_000).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        let approval = try #require(manager.pendingSupervisorSkillApprovals.first)
        manager.denyPendingSupervisorSkillApproval(approval)
        await manager.waitForSupervisorEventLoopForTesting()

        let jobs = SupervisorProjectJobStore.load(for: ctx).jobs
        #expect(jobs.count == 2)
        let followUp = try #require(jobs.first(where: { $0.goal == "hidden approval resolution follow-up" }))
        #expect(followUp.source == .approvalResolution)
        #expect(followUp.priority == .high)
    }

    @Test
    func denySupervisorSkillActivityRunsApprovalResolutionFollowUpWhenProjectOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-deny-activity-hidden-project")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "approval_resolution")
            #expect(userMessage.contains("trigger=approval_resolution"))
            #expect(userMessage.contains("project_ref=\(project.displayName)"))
            #expect(userMessage.contains("authorization_mode=local_approval"))
            #expect(userMessage.contains("resolution_mode=denied"))
            #expect(userMessage.contains("reason_code=local_approval_denied"))
            #expect(!userMessage.contains(root.lastPathComponent))
            return #"[CREATE_JOB]{"project_ref":"我的世界还原项目","goal":"hidden recent activity deny follow-up","priority":"high","source":"approval_resolution","current_owner":"supervisor"}[/CREATE_JOB]"#
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
            [UPSERT_PLAN]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-deny-activity-hidden-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"我的世界还原项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        let original = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        manager.refreshRecentSupervisorSkillActivitiesNow()
        let activity = try #require(manager.recentSupervisorSkillActivities.first(where: { $0.requestId == original.requestId }))

        let now = Date(timeIntervalSince1970: 1_773_384_100).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)
        manager.clearMessages()

        manager.denySupervisorSkillActivity(activity)
        await manager.waitForSupervisorEventLoopForTesting()

        #expect(manager.messages.contains(where: {
            $0.content.contains(project.displayName) && !$0.content.contains(root.lastPathComponent)
        }) == false)

        let jobs = SupervisorProjectJobStore.load(for: ctx).jobs
        #expect(jobs.count == 2)
        let followUp = try #require(jobs.first(where: { $0.goal == "hidden recent activity deny follow-up" }))
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
    func guidanceAckRejectedAutoFollowUpRunsWhenProjectOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        let root = try makeProjectRoot(named: "supervisor-guidance-ack-hidden-project")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "guidance_ack")
            #expect(userMessage.contains("trigger=guidance_ack"))
            #expect(userMessage.contains("project_ref=\(project.displayName)"))
            #expect(userMessage.contains("ack_status=rejected"))
            #expect(!userMessage.contains(root.lastPathComponent))
            return #"[CREATE_JOB]{"project_ref":"亮亮","goal":"hidden guidance ack follow-up","priority":"high","current_owner":"supervisor"}[/CREATE_JOB]"#
        }

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"亮亮","goal":"推进 review guidance 闭环","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"亮亮","job_id":"\#(job.jobId)","plan_id":"plan-guidance-ack-hidden-loop-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"消化 supervisor guidance","kind":"write_memory","status":"running"},{"step_id":"step-002","title":"按 guidance 调整计划","kind":"write_memory","status":"pending"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let now = Date(timeIntervalSince1970: 1_773_385_500).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        let rejected = SupervisorGuidanceInjectionBuilder.build(
            injectionId: "guidance-ack-rejected-hidden-loop-1",
            reviewId: "review-ack-rejected-hidden-loop-1",
            projectId: project.projectId,
            targetRole: .coder,
            deliveryMode: .replanRequest,
            interventionMode: .replanNextSafePoint,
            safePointPolicy: .nextStepBoundary,
            guidanceText: "改成更稳的 replan 路线。",
            ackStatus: .rejected,
            ackRequired: true,
            ackNote: "Conflicts with the approved migration boundary.",
            injectedAtMs: 1_773_385_500_000,
            ackUpdatedAtMs: 1_773_385_500_100,
            auditRef: "audit-guidance-ack-rejected-hidden-loop-1"
        )
        try SupervisorGuidanceInjectionStore.upsert(rejected, for: ctx)

        manager.handleEvent(.supervisorGuidanceAck(rejected))
        await manager.waitForSupervisorEventLoopForTesting()

        let jobs = SupervisorProjectJobStore.load(for: ctx).jobs
        #expect(jobs.count == 2)
        let followUp = try #require(jobs.first(where: { $0.goal == "hidden guidance ack follow-up" }))
        #expect(followUp.priority == .high)
        #expect(manager.recentEventsForTesting().contains { $0.contains("项目 \(project.displayName) 指导确认：已拒绝") })
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
    func naturalBriefReplyFailsClosedAndSurfacesRepairSignalWhenActionableSignalExists() throws {
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

        #expect(rendered.contains("⚠️ Hub Brief 暂不可用 · 亮亮"))
        #expect(rendered.contains("按当前 fail-closed 规则，我先不在 XT 本地即兴拼接 Supervisor brief。"))
        #expect(rendered.contains("Hub 待处理授权"))
        #expect(rendered.contains("你现在可以先：查看授权板"))
        #expect(rendered.contains("staging 回执还没回来") == false)
    }

    @Test
    func naturalBriefReplyUsesFocusPointerProjectWhenGlobalHomeIsSelected() throws {
        let manager = SupervisorManager.makeForTesting()
        let rootA = try makeProjectRoot(named: "supervisor-natural-brief-focus-pointer-a")
        let rootB = try makeProjectRoot(named: "supervisor-natural-brief-focus-pointer-b")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        var projectA = makeProjectEntry(root: rootA, displayName: "亮亮")
        projectA.currentStateSummary = "自动流程正在等待 staging 验证结果"
        projectA.blockerSummary = "staging 回执还没回来"
        projectA.nextStepSummary = "确认 staging 结果后推进 release 决策"

        let projectB = makeProjectEntry(root: rootB, displayName: "阿杰")

        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        manager.setAppModel(appModel)

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        manager.setSupervisorFocusPointerStateForTesting(
            SupervisorFocusPointerState(
                schemaVersion: SupervisorFocusPointerState.currentSchemaVersion,
                updatedAtMs: nowMs,
                currentProjectId: projectA.projectId,
                currentProjectAliases: [projectA.displayName, projectA.projectId],
                currentProjectUpdatedAtMs: nowMs,
                currentPersonName: nil,
                currentPersonUpdatedAtMs: nil,
                currentCommitmentId: nil,
                currentCommitmentUpdatedAtMs: nil,
                currentTopicDigest: "project_first: 这个项目现在状态怎么样？",
                lastTurnMode: .projectFirst,
                lastSeenDeltaCursor: "memory_build:\(nowMs)"
            )
        )

        let rendered = try #require(
            manager.directSupervisorReplyIfApplicableForTesting("这个项目现在状态怎么样")
        )

        #expect(rendered.contains("⚠️ Hub Brief 暂不可用 · 亮亮"))
        #expect(!rendered.contains("⚠️ Hub Brief 需要项目绑定"))
    }

    @Test
    func casualMetaQuestionDoesNotGetHijackedByProjectBriefShortcut() throws {
        let manager = SupervisorManager.makeForTesting()
        let rendered = manager.directSupervisorReplyIfApplicableForTesting("你在这套系统里感觉如何")
        #expect(rendered == nil)
    }

    @Test
    func casualChatQuestionDoesNotGetHijackedEvenWhenProjectIsSelected() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-casual-chat-not-brief")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let rendered = manager.directSupervisorReplyIfApplicableForTesting("你最近怎么样")
        #expect(rendered == nil)
    }

    @Test
    func underfedStrategicReviewRequestPromptsForNaturalFactCollection() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-underfed-follow-up")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeSupervisorMemoryAssemblySnapshot(
                projectID: project.projectId,
                profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                contextRefsSelected: 0,
                evidenceItemsSelected: 0,
                omittedSections: [
                    "focused_project_anchor_pack",
                    "longterm_outline",
                    "evidence_pack",
                ],
                truncatedLayers: ["l1_canonical"]
            )
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "审查亮亮项目的上下文记忆，直接做战略纠偏"
            )
        )

        #expect(rendered.contains("《亮亮》当前项目背景还不够完整"))
        #expect(rendered.contains("我们一项一项补"))
        #expect(rendered.contains("长期目标和完成标准分别是什么"))
        #expect(rendered.contains("你可以直接说：目标是……，完成标准是……"))
        #expect(rendered.contains("后面我还会继续补：关键决策和原因"))
    }

    @Test
    func underfedStrategicReviewPromptRequiresProjectWhenNoFocusIsResolved() throws {
        let manager = SupervisorManager.makeForTesting()
        let rootA = try makeProjectRoot(named: "supervisor-underfed-follow-up-project-a")
        let rootB = try makeProjectRoot(named: "supervisor-underfed-follow-up-project-b")
        defer { try? FileManager.default.removeItem(at: rootA) }
        defer { try? FileManager.default.removeItem(at: rootB) }

        let projectA = makeProjectEntry(root: rootA, displayName: "亮亮")
        let projectB = makeProjectEntry(root: rootB, displayName: "Hub Runtime")
        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        manager.setAppModel(appModel)
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeSupervisorMemoryAssemblySnapshot(
                projectID: projectA.projectId,
                profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                contextRefsSelected: 0,
                evidenceItemsSelected: 0,
                omittedSections: [
                    "focused_project_anchor_pack",
                    "longterm_outline",
                    "evidence_pack",
                ],
                truncatedLayers: ["l1_canonical"]
            )
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "直接做战略纠偏，帮我判断方向"
            )
        )

        #expect(rendered.contains("先告诉我你要纠偏哪个项目"))
        #expect(rendered.contains("长期目标和完成标准分别是什么"))
        #expect(rendered.contains("某某项目，目标是……，完成标准是……"))
    }

    @Test
    func underfedStrategicReviewFollowUpStillAllowsNaturalMemoryPatchFacts() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-underfed-follow-up-patch")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeSupervisorMemoryAssemblySnapshot(
                projectID: project.projectId,
                profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                contextRefsSelected: 0,
                evidenceItemsSelected: 0,
                omittedSections: [
                    "focused_project_anchor_pack",
                    "longterm_outline",
                    "evidence_pack",
                ],
                truncatedLayers: ["l1_canonical"]
            )
        )

        let followUp = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "先审查亮亮项目的上下文记忆，再决定要不要纠偏"
            )
        )
        #expect(followUp.contains("我先不直接做战略纠偏"))

        let patchReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "目标是让 supervisor 在耳机里自然汇报项目状态，完成标准是能连续播报并接收一句话授权"
            )
        )

        #expect(patchReply.contains("项目 anchor"))
        #expect(patchReply.contains("下一项我还要补"))
        #expect(patchReply.contains("我们为什么走当前这条路径？关键决策和原因是什么？"))
        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let capsule = try #require(SupervisorProjectSpecCapsuleStore.load(for: ctx))
        #expect(capsule.goal.contains("耳机里自然汇报项目状态"))
        #expect(capsule.mvpDefinition.contains("连续播报并接收一句话授权"))
    }

    @Test
    func underfedStrategicReviewFollowUpDoesNotHijackCasualChat() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-underfed-follow-up-casual-chat")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeSupervisorMemoryAssemblySnapshot(
                projectID: project.projectId,
                profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                contextRefsSelected: 0,
                evidenceItemsSelected: 0,
                omittedSections: [
                    "focused_project_anchor_pack",
                    "longterm_outline",
                    "evidence_pack",
                ],
                truncatedLayers: ["l1_canonical"]
            )
        )

        let followUp = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "审查亮亮项目的上下文记忆，直接做战略纠偏"
            )
        )
        #expect(followUp.contains("我们一项一项补"))

        let casual = manager.directSupervisorActionIfApplicableForTesting(
            "不用当成项目回答，你对这套系统有什么建议，详细说说"
        )

        #expect(casual == nil)
        #expect(manager.supervisorPendingMemoryFactFollowUpQuestion.contains("长期目标和完成标准"))
    }

    @Test
    func underfedStrategicReviewFollowUpRepromptsOnExplicitContinue() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-underfed-follow-up-continue")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeSupervisorMemoryAssemblySnapshot(
                projectID: project.projectId,
                profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                contextRefsSelected: 0,
                evidenceItemsSelected: 0,
                omittedSections: [
                    "focused_project_anchor_pack",
                    "longterm_outline",
                    "evidence_pack",
                ],
                truncatedLayers: ["l1_canonical"]
            )
        )

        _ = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "审查亮亮项目的上下文记忆，直接做战略纠偏"
            )
        )

        let reprompt = try #require(
            manager.directSupervisorActionIfApplicableForTesting("继续")
        )

        #expect(reprompt.contains("我们一项一项补"))
        #expect(reprompt.contains("长期目标和完成标准分别是什么"))
    }

    @Test
    func underfedStrategicReviewFollowUpCarriesProjectAcrossTurnsWithoutSelection() throws {
        let manager = SupervisorManager.makeForTesting()
        let rootA = try makeProjectRoot(named: "supervisor-underfed-follow-up-carry-a")
        let rootB = try makeProjectRoot(named: "supervisor-underfed-follow-up-carry-b")
        defer { try? FileManager.default.removeItem(at: rootA) }
        defer { try? FileManager.default.removeItem(at: rootB) }

        let projectA = makeProjectEntry(root: rootA, displayName: "亮亮")
        let projectB = makeProjectEntry(root: rootB, displayName: "Hub Runtime")
        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        manager.setAppModel(appModel)
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeSupervisorMemoryAssemblySnapshot(
                projectID: projectA.projectId,
                profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                contextRefsSelected: 0,
                evidenceItemsSelected: 0,
                omittedSections: [
                    "focused_project_anchor_pack",
                    "longterm_outline",
                    "evidence_pack",
                ],
                truncatedLayers: ["l1_canonical"]
            )
        )

        let followUp = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "审查亮亮项目的上下文记忆，再决定要不要纠偏"
            )
        )
        #expect(followUp.contains("《亮亮》当前项目背景还不够完整"))

        let goalReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "目标是让 supervisor 用耳机持续汇报项目，完成标准是能语音接收一句话授权"
            )
        )
        #expect(goalReply.contains("项目 anchor"))
        #expect(goalReply.contains("下一项我还要补"))
        #expect(goalReply.contains("关键决策和原因是什么"))

        let decisionReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "我们决定先走 Hub 通道，原因是权限和审计统一"
            )
        )
        #expect(decisionReply.contains("关键路径决策我已经记下了"))
        #expect(decisionReply.contains("现在卡在哪里"))

        let completionReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "现在卡在 voice wake 误触发太多，已经试过调阈值，下一步是先把唤醒日志打通，证据是 staging smoke 已稳定通过 12 次"
            )
        )
        #expect(completionReply.contains("这轮关键背景我已经先补进《亮亮》了"))
        #expect(completionReply.contains("你现在可以直接再让我审查一次方向"))

        let ctxA = try #require(appModel.projectContext(for: projectA.projectId))
        let capsule = try #require(SupervisorProjectSpecCapsuleStore.load(for: ctxA))
        #expect(capsule.goal.contains("用耳机持续汇报项目"))
        let decision = try #require(SupervisorDecisionTrackStore.load(for: ctxA).events.first)
        #expect(decision.statement.contains("Hub 通道"))
        let updatedProject = try #require(appModel.registry.project(for: projectA.projectId))
        #expect(updatedProject.blockerSummary?.contains("voice wake 误触发太多") == true)
        #expect(updatedProject.nextStepSummary == "先把唤醒日志打通")
        let evidence = try #require(SupervisorSelectedEvidencePinStore.latest(for: ctxA))
        #expect(evidence.summary.contains("staging smoke"))

        let ctxB = AXProjectContext(root: rootB)
        #expect(SupervisorProjectSpecCapsuleStore.load(for: ctxB) == nil)
        #expect(SupervisorDecisionTrackStore.load(for: ctxB).events.isEmpty)
    }

    @Test
    func underfedStrategicReviewMixedFactUtteranceBypassesDirectBriefShortcut() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-underfed-follow-up-mixed-facts")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeSupervisorMemoryAssemblySnapshot(
                projectID: project.projectId,
                profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                contextRefsSelected: 0,
                evidenceItemsSelected: 0,
                omittedSections: [
                    "focused_project_anchor_pack",
                    "longterm_outline",
                    "evidence_pack",
                ],
                truncatedLayers: ["l1_canonical"]
            )
        )

        let prompt = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "审查亮亮项目的上下文记忆，直接做战略纠偏"
            )
        )
        #expect(prompt.contains("我们一项一项补"))

        let mixedFacts = "目标是让 supervisor 用耳机持续汇报项目，完成标准是能一句话授权；我们决定先走 Hub 通道，原因是权限和审计统一；现在卡在 voice wake 误触发太多，已经试过调阈值，下一步是先把唤醒日志打通；证据是 staging smoke 已稳定通过 12 次"

        #expect(manager.directSupervisorReplyIfApplicableForTesting(mixedFacts) == nil)

        let completionReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting(mixedFacts)
        )

        #expect(completionReply.contains("这轮关键背景我已经先补进《亮亮》了"))
        #expect(completionReply.contains("你现在可以直接再让我审查一次方向"))
    }

    @Test
    func naturalLanguageMemoryPatchUpsertsLongtermProjectAnchor() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-patch-longterm")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "这个项目的目标是让 supervisor 能在耳机里主动汇报，完成标准是能连续语音播报状态并接收一句话授权，先不做视频通话，必须用 SwiftUI、gRPC"
            )
        )

        #expect(rendered.contains("项目 anchor"))

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let capsule = try #require(SupervisorProjectSpecCapsuleStore.load(for: ctx))
        #expect(capsule.goal.contains("耳机里主动汇报"))
        #expect(capsule.mvpDefinition.contains("连续语音播报状态"))
        #expect(capsule.nonGoals.contains("视频通话"))
        #expect(capsule.approvedTechStack.contains("SwiftUI"))
        #expect(capsule.approvedTechStack.contains("gRPC"))
    }

    @Test
    func naturalLanguageMemoryPatchWritesDecisionLineageAndSelectedEvidence() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-patch-decision")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "我们决定先把 Slack、WhatsApp、Feishu 接在 Hub 端，不走 X-terminal 直连，原因是权限和审计统一，证据是 openclaw 这套路由已经验证过"
            )
        )

        #expect(rendered.contains("关键路径决策我已经记下了"))
        #expect(rendered.contains("优先证据"))

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let decisionEvent = try #require(SupervisorDecisionTrackStore.load(for: ctx).events.first)
        #expect(decisionEvent.status == .approved)
        #expect(decisionEvent.statement.contains("Hub 端"))
        #expect(decisionEvent.source.contains("权限和审计统一"))
        #expect(!decisionEvent.evidenceRefs.isEmpty)

        let evidence = try #require(SupervisorSelectedEvidencePinStore.latest(for: ctx))
        #expect(evidence.summary.contains("openclaw"))
    }

    @Test
    func structuredWorkflowPayloadDoesNotSurfaceAsRepeatedNaturalMemoryPatchReply() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-structured-workflow-payload-memory-guard")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let payload = """
自动继续当前 governed workflow。
trigger=automation_safe_point
project_ref=\(project.displayName)
project_id=\(project.projectId)
job_id=job-001
plan_id=plan-001
step_id=step-001
request_id=req-001
skill_id=repo.write
workflow_focus:
active_job_goal=默认方案与验收口径
active_job_status=running
active_plan_id=plan-001
active_plan_status=running
active_plan_steps:
1. step-001 | completed | write_memory | 锁定默认方案与验收口径
2. step-002 | pending | launch_run | 搭建最小可运行骨架
3. step-003 | pending | write_memory | 回写结果
next_pending_steps:
2. step-002 | pending | launch_run | 搭建最小可运行骨架
attention_steps:
(none)
"""

        #expect(manager.directSupervisorActionIfApplicableForTesting(payload) == nil)
    }

    @Test
    func repeatedNaturalMemoryPatchDoesNotRepeatSameDecisionConfirmation() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-patch-decision-dedupe")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let text = "我们决定先走 Hub 通道，原因是权限和审计统一，证据是 openclaw 这套路由已经验证过"

        let firstReply = try #require(
            manager.directSupervisorActionIfApplicableForTesting(text)
        )
        #expect(firstReply.contains("关键路径决策我已经记下了"))

        let secondReply = manager.directSupervisorActionIfApplicableForTesting(text)
        #expect(secondReply == nil)

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let decisions = SupervisorDecisionTrackStore.load(for: ctx).events
        #expect(decisions.count == 1)
        let evidencePins = SupervisorSelectedEvidencePinStore.load(for: ctx).pins
        #expect(evidencePins.count == 1)
    }

    @Test
    func naturalLanguageMemoryPatchUpdatesBlockerLineageFromColloquialFacts() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-patch-blocker")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting(
                "现在卡在 voice wake 误触发太多，已经试过调阈值、重建 session，下一步是先把唤醒链路日志打通"
            )
        )

        #expect(rendered.contains("当前卡点我已经记进项目现状了"))

        let updated = try #require(appModel.registry.project(for: project.projectId))
        #expect(updated.blockerSummary?.contains("voice wake 误触发太多") == true)
        #expect(updated.blockerSummary?.contains("调阈值") == true)
        #expect(updated.nextStepSummary == "先把唤醒链路日志打通")
    }

    @Test
    func naturalLanguageSelectedEvidenceFeedsFocusedMemoryAssembly() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-patch-evidence-assembly")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.directSupervisorActionIfApplicableForTesting(
            "证据是 staging smoke 已稳定通过 12 次，这个要作为后续纠偏的依据"
        )

        let snapshot = await manager.buildSupervisorMemoryAssemblySnapshotForTesting(
            "审查亮亮项目的上下文记忆，给出最具体的执行方案"
        )

        #expect(snapshot?.focusedProjectId == project.projectId)
        #expect(snapshot?.selectedSections.contains("evidence_pack") == true)
        #expect(snapshot?.evidenceItemsSelected ?? 0 > 0)
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

        #expect(rendered.contains("我先按这个方向处理"))
        #expect(!rendered.contains("收到，我会按《"))
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

        #expect(rendered.contains("我先放一放"))
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

        #expect(rendered.contains("先不按这个方向走"))
        let updated = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(updated.injectionId == "guidance-natural-reject-1")
        #expect(updated.ackStatus == .rejected)
        #expect(updated.ackNote.contains("这个路子不对，换条路重新想方案"))
    }

    @Test
    func naturalLanguageGuidanceAckReplyHumanizesStructuredGuidanceText() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-guidance-structured-ack")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "Release Runtime")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-natural-structured-ack-1",
                reviewId: "review-natural-structured-ack-1",
                projectId: project.projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: #"""
                verdict=watch
                summary=当前没有待处理的 Hub 授权。
                effective_supervisor_tier=s3_strategic_coach
                effective_work_order_depth=execution_ready
                work_order_ref=plan:plan-release-runtime-v1
                actions=检查授权面板 | 保持当前 runtime
                """#,
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_386_320_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-natural-structured-ack-1"
            ),
            for: ctx
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("这个方案可以，就按这个方案走")
        )

        #expect(rendered.contains("当前没有待处理的 Hub 授权。"))
        #expect(rendered.contains("我先按这个方向处理"))
        #expect(!rendered.contains("verdict="))
        #expect(!rendered.contains("effective_supervisor_tier"))
        #expect(!rendered.contains("actions="))
        #expect(!rendered.contains("收到，我会按《Release Runtime》这条指导继续推进"))
    }

    @Test
    func naturalLanguageGuidanceAckAmbiguityReplyHumanizesPollutedStructuredGuidanceText() throws {
        let manager = SupervisorManager.makeForTesting()
        let rootA = try makeProjectRoot(named: "supervisor-guidance-ambiguity-a")
        let rootB = try makeProjectRoot(named: "supervisor-guidance-ambiguity-b")
        defer { try? FileManager.default.removeItem(at: rootA) }
        defer { try? FileManager.default.removeItem(at: rootB) }

        let projectA = makeProjectEntry(root: rootA, displayName: "Release Runtime")
        let projectB = makeProjectEntry(root: rootB, displayName: "Hub 授权")
        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        manager.setAppModel(appModel)

        let ctxA = try #require(appModel.projectContext(for: projectA.projectId))
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-ambiguity-structured-1",
                reviewId: "review-ambiguity-structured-1",
                projectId: projectA.projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "收到，我会按《Release Runtime》这条指导继续推进：verdict=watchsummary=当前没有待处理的 Hub 授权。effective_supervisor_tier=s3_strategic_coacheffective_work_order_depth=execution_readywork_order_ref=plan:plan-release-runtime-v1",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_386_330_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-ambiguity-structured-1"
            ),
            for: ctxA
        )

        let ctxB = try #require(appModel.projectContext(for: projectB.projectId))
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-ambiguity-structured-2",
                reviewId: "review-ambiguity-structured-2",
                projectId: projectB.projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: #"""
                verdict=watch
                summary=先把授权弹窗噪音收口，再决定是否继续推进。
                effective_supervisor_tier=s2_pathfinder
                effective_work_order_depth=execution_ready
                work_order_ref=plan:plan-hub-auth-v1
                """#,
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_386_331_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-ambiguity-structured-2"
            ),
            for: ctxB
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("这个方案可以，就按这个方案走")
        )

        #expect(rendered.contains("当前有多条待确认 guidance"))
        #expect(rendered.contains("当前没有待处理的 Hub 授权。"))
        #expect(rendered.contains("先把授权弹窗噪音收口，再决定是否继续推进。"))
        #expect(!rendered.contains("verdict="))
        #expect(!rendered.contains("effective_supervisor_tier"))
        #expect(!rendered.contains("收到，我会按《Release Runtime》这条指导继续推进"))
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

        #expect(rendered.contains("我先按这个方向处理"))
        #expect(!rendered.contains("收到，我会按《"))
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

        #expect(rendered.contains("我先放一放"))
        let updated = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(updated.ackStatus == .deferred)
        #expect(updated.ackNote == "先缓一缓")
    }

    @Test
    func naturalLanguageGuidanceAckContextDoesNotCarryAcrossInterveningUserTurn() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-guidance-context-expire-turn")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        let now = Date().timeIntervalSince1970
        manager.messages = [
            SupervisorMessage(
                id: "assistant-guidance-old-context",
                role: .assistant,
                content: "当前有一条待确认 guidance：先把 release 风险和 staging 证据对齐，再决定是否推进。",
                isVoice: false,
                timestamp: now - 20
            ),
            SupervisorMessage(
                id: "user-unrelated-follow-up",
                role: .user,
                content: "顺便说下现在项目进度",
                isVoice: false,
                timestamp: now - 10
            ),
            SupervisorMessage(
                id: "assistant-unrelated-follow-up",
                role: .assistant,
                content: "现在状态还是阻塞中，主要卡在 staging 回执。",
                isVoice: false,
                timestamp: now - 5
            )
        ]

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-natural-context-expire-turn-1",
                reviewId: "review-natural-context-expire-turn-1",
                projectId: project.projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "先把 release 风险和 staging 证据对齐，再决定是否推进。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_386_365_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-natural-context-expire-turn-1"
            ),
            for: ctx
        )

        #expect(manager.directSupervisorActionIfApplicableForTesting("可以") == nil)
        let updated = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(updated.ackStatus == .pending)
    }

    @Test
    func guidanceAckDirectActionUserTurnDoesNotCreateReviewNote() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-guidance-ack-no-review-note")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "Release Runtime")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-ack-no-review-note-1",
                reviewId: "review-ack-no-review-note-1",
                projectId: project.projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: #"""
                verdict=watch
                summary=当前没有待处理的 Hub 授权。
                effective_supervisor_tier=s3_strategic_coach
                effective_work_order_depth=execution_ready
                work_order_ref=plan:plan-release-runtime-v1
                """#,
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_386_332_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-ack-no-review-note-1"
            ),
            for: ctx
        )

        manager.sendMessage("这个方案可以，就按这个方案走", fromVoice: false)

        try await waitUntil("guidance ack committed without review note", timeoutMs: 5_000) {
            let guidance = SupervisorGuidanceInjectionStore.latest(for: ctx)
            return guidance?.ackStatus == .accepted &&
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                        $0.content.contains("当前没有待处理的 Hub 授权。")
                })
        }

        let guidance = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(guidance.ackStatus == .accepted)
        #expect(SupervisorReviewNoteStore.load(for: ctx).notes.isEmpty)
        #expect(manager.messages.contains(where: {
            $0.role == .assistant &&
                !$0.content.contains("verdict=") &&
                !$0.content.contains("effective_supervisor_tier") &&
                $0.content.contains("当前没有待处理的 Hub 授权。")
        }))
    }

    @Test
    func naturalLanguageLocalSkillApprovalApprovesPendingSkillCall() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-natural-local-skill-approval")
        defer { try? FileManager.default.removeItem(at: root) }

        let friendlyName = "耳机外出项目"
        let project = makeProjectEntry(root: root, displayName: friendlyName)
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
            #"[CREATE_JOB]{"project_ref":"耳机外出项目","goal":"运行 browser smoke","priority":"high"}[/CREATE_JOB]"#,
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
            )
        try AXProjectStore.saveConfig(config, for: ctx)

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeSupervisorTrustedAutomationPermissionReadiness()
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"耳机外出项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-natural-approval-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"耳机外出项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        #expect(manager.pendingSupervisorSkillApprovals.count == 1)

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("批准这个技能调用")
        )

        #expect(rendered.contains("开始批准《\(friendlyName)》的技能调用了：browser.runtime.smoke"))
        #expect(!rendered.contains(root.lastPathComponent))

        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("browser smoke completed"))
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)
    }

    @Test
    func naturalLanguageLocalSkillApprovalRejectsContextualEllipsisAfterRecentPendingPrompt() throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-natural-local-skill-context-deny")
        defer { try? FileManager.default.removeItem(at: root) }

        let friendlyName = "耳机外出项目"
        let project = makeProjectEntry(root: root, displayName: friendlyName)
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"耳机外出项目","goal":"运行 browser smoke","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"耳机外出项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-natural-context-deny-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"耳机外出项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        #expect(manager.pendingSupervisorSkillApprovals.count == 1)
        manager.messages = [
            SupervisorMessage(
                id: "assistant-local-approval-context",
                role: .assistant,
                content: "《\(friendlyName)》有一条待处理的本地技能调用：browser.runtime.smoke。当前需要本地审批后才能继续。",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        ]

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("不行")
        )

        #expect(rendered.contains("先拦下《\(friendlyName)》的技能调用：browser.runtime.smoke"))
        #expect(!rendered.contains(root.lastPathComponent))

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .blocked)
        #expect(call.denyCode == "local_approval_denied")
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)
    }

    @Test
    func grantPendingSkillContextPhrasesTriggerContextualDenyDecision() {
        let manager = SupervisorManager.makeForTesting()
        manager.messages = [
            SupervisorMessage(
                id: "assistant-hub-grant-context",
                role: .assistant,
                content: "《耳机外出项目》有一条技能授权待处理：web.search。当前需要先到 Hub 授权面板处理，或者按阻塞提示处理。",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        ]

        #expect(
            manager.hasRecentSupervisorPendingSkillApprovalContextForTesting("不行")
        )
        #expect(
            manager.pendingSupervisorSkillApprovalDecisionForTesting("不行") == false
        )
    }

    @Test
    func naturalLanguageGrantRequiredSkillApprovalReturnsUnifiedGrantGuidance() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-natural-grant-required-skill-approve")
        defer { try? FileManager.default.removeItem(at: root) }

        let friendlyName = "耳机外出项目"
        let project = makeProjectEntry(root: root, displayName: friendlyName)
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let createdAtMs: Int64 = 1_900_000_010_000
        let ctx = try createPendingLocalSkillApprovalRecord(
            manager: manager,
            appModel: appModel,
            project: project,
            root: root,
            planID: "plan-browser-smoke-natural-grant-approve-v1",
            createdAtMs: createdAtMs
        )

        var call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        call.resultSummary = "waiting for Hub grant before governed execution can resume"
        call.denyCode = "grant_required"
        call.readiness = XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: project.projectId,
            skillId: call.skillId,
            packageSHA256: "pkg-grant-required-1",
            publisherID: "xt_builtin",
            policyScope: "xt_builtin",
            intentFamilies: ["browser.observe", "browser.interact"],
            capabilityFamilies: ["browser.observe", "browser.interact"],
            capabilityProfiles: ["observe_only", "browser_operator"],
            discoverabilityState: "discoverable",
            installabilityState: "installable",
            pinState: "xt_builtin",
            resolutionState: "resolved",
            executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
            runnableNow: false,
            denyCode: "grant_required",
            reasonCode: "grant floor privileged requires hub grant",
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
            requiredGrantCapabilities: ["browser.interact"],
            requiredRuntimeSurfaces: ["managed_browser_runtime"],
            stateLabel: "awaiting_hub_grant",
            installHint: "",
            unblockActions: ["request_hub_grant"],
            auditRef: "audit-readiness-\(call.requestId)",
            doctorAuditRef: "",
            vetterAuditRef: "",
            resolvedSnapshotId: "snapshot-\(call.requestId)",
            grantSnapshotRef: "grant-\(call.requestId)"
        )
        call.deltaApproval = XTSkillProfileDeltaApproval(
            schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
            requestId: call.requestId,
            projectId: project.projectId,
            projectName: project.displayName,
            requestedSkillId: call.skillId,
            effectiveSkillId: call.skillId,
            toolName: call.toolName,
            currentRunnableProfiles: ["observe_only"],
            requestedProfiles: ["observe_only", "browser_operator"],
            deltaProfiles: ["browser_operator"],
            currentRunnableCapabilityFamilies: ["browser.observe"],
            requestedCapabilityFamilies: ["browser.observe", "browser.interact"],
            deltaCapabilityFamilies: ["browser.interact"],
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
            requestedTTLSeconds: 900,
            reason: "browser control touches live admin surface",
            summary: "当前可直接运行：observe_only；本次请求：observe_only, browser_operator；新增放开：browser_operator；grant=privileged；approval=hub_grant",
            disposition: "pending",
            auditRef: "audit-delta-\(call.requestId)"
        )
        call.updatedAtMs = createdAtMs + 1
        try SupervisorProjectSkillCallStore.upsert(call, for: ctx)
        manager.refreshPendingSupervisorSkillApprovalsNow()

        #expect(manager.pendingSupervisorSkillApprovals.count == 1)

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("批准这个技能调用")
        )

        #expect(rendered.contains("《\(friendlyName)》这条技能授权待处理项当前还不能直接放行"))
        #expect(rendered.contains("browser.runtime.smoke"))
        #expect(rendered.contains("能力增量：新增放开：browser_operator"))
        #expect(rendered.contains("授权门槛：高权限 grant · 审批门槛：Hub grant"))
        #expect(rendered.contains("先完成 Hub grant，再恢复这次受治理技能调用"))
        #expect(!rendered.contains(root.lastPathComponent))

        let updatedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(updatedCall.status == .awaitingAuthorization)
        #expect(updatedCall.denyCode == "grant_required")
        #expect(manager.pendingSupervisorSkillApprovals.count == 1)
    }

    @Test
    func naturalLanguageBlockedSkillApprovalKeepsPendingCallBlockedAndDoesNotDispatch() async throws {
        actor ExecutionCapture {
            private(set) var count: Int = 0

            func record() {
                count += 1
            }
        }

        let capture = ExecutionCapture()
        let manager = SupervisorManager.makeForTesting()
        manager.setSupervisorToolExecutorOverrideForTesting { _, _ in
            await capture.record()
            return ToolResult(
                id: "unexpected-blocked-dispatch",
                tool: .deviceBrowserControl,
                ok: true,
                output: "unexpected blocked dispatch"
            )
        }

        let root = try makeProjectRoot(named: "supervisor-natural-blocked-skill-approve")
        defer { try? FileManager.default.removeItem(at: root) }

        let friendlyName = "耳机外出项目"
        let project = makeProjectEntry(root: root, displayName: friendlyName)
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let createdAtMs: Int64 = 1_900_000_020_000
        let ctx = try createPendingLocalSkillApprovalRecord(
            manager: manager,
            appModel: appModel,
            project: project,
            root: root,
            planID: "plan-browser-smoke-natural-blocked-approve-v1",
            createdAtMs: createdAtMs
        )

        var call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        call.resultSummary = "waiting for governance unblock before execution can resume"
        call.readiness = XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: project.projectId,
            skillId: call.skillId,
            packageSHA256: "pkg-blocked-1",
            publisherID: "xt_builtin",
            policyScope: "xt_builtin",
            intentFamilies: ["browser.observe", "browser.interact"],
            capabilityFamilies: ["browser.observe", "browser.interact"],
            capabilityProfiles: ["observe_only", "browser_operator"],
            discoverabilityState: "discoverable",
            installabilityState: "installable",
            pinState: "xt_builtin",
            resolutionState: "resolved",
            executionReadiness: XTSkillExecutionReadinessState.policyClamped.rawValue,
            runnableNow: false,
            denyCode: "policy_clamped",
            reasonCode: "current governance tier does not allow browser_interact",
            grantFloor: XTSkillGrantFloor.none.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            requiredGrantCapabilities: [],
            requiredRuntimeSurfaces: ["managed_browser_runtime"],
            stateLabel: "policy_clamped",
            installHint: "",
            unblockActions: ["review_runtime_surface_policy", "request_policy_elevation"],
            auditRef: "audit-blocked-readiness-\(call.requestId)",
            doctorAuditRef: "",
            vetterAuditRef: "",
            resolvedSnapshotId: "snapshot-\(call.requestId)",
            grantSnapshotRef: ""
        )
        call.deltaApproval = XTSkillProfileDeltaApproval(
            schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
            requestId: call.requestId,
            projectId: project.projectId,
            projectName: project.displayName,
            requestedSkillId: call.skillId,
            effectiveSkillId: call.skillId,
            toolName: call.toolName,
            currentRunnableProfiles: ["observe_only"],
            requestedProfiles: ["observe_only", "browser_operator"],
            deltaProfiles: ["browser_operator"],
            currentRunnableCapabilityFamilies: ["browser.observe"],
            requestedCapabilityFamilies: ["browser.observe", "browser.interact"],
            deltaCapabilityFamilies: ["browser.interact"],
            grantFloor: XTSkillGrantFloor.none.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            requestedTTLSeconds: 900,
            reason: "browser control touches live admin surface",
            summary: "当前可直接运行：observe_only；本次请求：observe_only, browser_operator；新增放开：browser_operator；grant=none；approval=local_approval",
            disposition: "pending",
            auditRef: "audit-blocked-delta-\(call.requestId)"
        )
        call.updatedAtMs = createdAtMs + 1
        try SupervisorProjectSkillCallStore.upsert(call, for: ctx)
        manager.refreshPendingSupervisorSkillApprovalsNow()

        #expect(manager.pendingSupervisorSkillApprovals.count == 1)

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("批准这个技能调用")
        )

        #expect(rendered.contains("《\(friendlyName)》这条技能治理待处理项当前还不能直接放行"))
        #expect(rendered.contains("browser.runtime.smoke"))
        #expect(rendered.contains("执行就绪：受治理档位限制"))
        #expect(rendered.contains("请先按阻塞提示处理，我再继续往下推进"))
        #expect(!rendered.contains(root.lastPathComponent))

        try await Task.sleep(nanoseconds: 300_000_000)

        let updatedCall = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(updatedCall.status == .awaitingAuthorization)
        #expect(updatedCall.denyCode.isEmpty)
        #expect(manager.pendingSupervisorSkillApprovals.count == 1)
        #expect(await capture.count == 0)
    }

    @Test
    func voiceTranscriptLocalSkillApprovalApprovesPendingSkillCall() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-voice-local-skill-approval")
        defer { try? FileManager.default.removeItem(at: root) }

        let friendlyName = "耳机外出项目"
        let project = makeProjectEntry(root: root, displayName: friendlyName)
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
            #"[CREATE_JOB]{"project_ref":"耳机外出项目","goal":"运行 browser smoke","priority":"high"}[/CREATE_JOB]"#,
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
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
            )
        try AXProjectStore.saveConfig(config, for: ctx)

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeSupervisorTrustedAutomationPermissionReadiness()
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"耳机外出项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-voice-approval-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"耳机外出项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        #expect(manager.pendingSupervisorSkillApprovals.count == 1)

        manager.sendMessage("批准这个技能调用", fromVoice: true)

        try await waitUntil("voice local skill approval committed", timeoutMs: 5_000) {
            let call = SupervisorProjectSkillCallStore.load(for: ctx).calls.first
            return manager.messages.contains(where: {
                $0.role == .assistant &&
                    $0.content.contains("开始批准《\(friendlyName)》的技能调用了：browser.runtime.smoke") &&
                    !$0.content.contains(root.lastPathComponent)
            }) &&
            manager.messages.contains(where: {
                $0.role == .user && $0.isVoice && $0.content == "批准这个技能调用"
            }) &&
            manager.pendingSupervisorSkillApprovals.isEmpty &&
            call?.status == .completed
        }

        await manager.waitForSupervisorSkillDispatchForTesting()

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .completed)
        #expect(call.resultSummary.contains("browser smoke completed"))
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)
        #expect(spoken.contains(where: { $0.contains(friendlyName) }))
        #expect(spoken.allSatisfy { !$0.contains(root.lastPathComponent) })
    }

    @Test
    func voiceTranscriptLocalSkillApprovalRejectsContextualEllipsisAfterRecentPendingPrompt() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let root = try makeProjectRoot(named: "supervisor-voice-local-skill-context-deny")
        defer { try? FileManager.default.removeItem(at: root) }

        let friendlyName = "耳机外出项目"
        let project = makeProjectEntry(root: root, displayName: friendlyName)
        try fixture.writeHubSkillsStore(projectID: project.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"耳机外出项目","goal":"运行 browser smoke","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"耳机外出项目","job_id":"\#(job.jobId)","plan_id":"plan-browser-smoke-voice-context-deny-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"耳机外出项目","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"browser.runtime.smoke","payload":{"url":"https://example.com"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 browser smoke 技能"
        )

        #expect(manager.pendingSupervisorSkillApprovals.count == 1)
        manager.messages = [
            SupervisorMessage(
                id: "assistant-local-approval-voice-context",
                role: .assistant,
                content: "《\(friendlyName)》有一条待处理的本地技能调用：browser.runtime.smoke。当前需要本地审批后才能继续。",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        ]

        manager.sendMessage("不行", fromVoice: true)

        try await waitUntil("voice local skill denial committed", timeoutMs: 5_000) {
            let call = SupervisorProjectSkillCallStore.load(for: ctx).calls.first
            return manager.messages.contains(where: {
                $0.role == .assistant &&
                    $0.content.contains("先拦下《\(friendlyName)》的技能调用：browser.runtime.smoke") &&
                    !$0.content.contains(root.lastPathComponent)
            }) &&
            manager.messages.contains(where: {
                $0.role == .user && $0.isVoice && $0.content == "不行"
            }) &&
            manager.pendingSupervisorSkillApprovals.isEmpty &&
            call?.status == .blocked
        }

        let call = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(call.status == .blocked)
        #expect(call.denyCode == "local_approval_denied")
        #expect(manager.pendingSupervisorSkillApprovals.isEmpty)
        #expect(spoken.contains(where: { $0.contains(friendlyName) }))
        #expect(spoken.allSatisfy { !$0.contains(root.lastPathComponent) })
    }

    @Test
    func proactiveVoiceLocalSkillApprovalAnnouncementAnchorsApprovalAcrossMultiplePendingCalls() async throws {
        var spoken: [String] = []
        let controller = SupervisorConversationSessionController.makeForTesting(
            route: .systemSpeechCompatibility,
            wakeMode: .pushToTalk,
            nowProvider: { Date() }
        )
        let transcriber = SupervisorCommandGuardMockVoiceStreamingTranscriber()
        let voiceCoordinator = VoiceSessionCoordinator(
            transcriber: transcriber,
            preferences: .default()
        )
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer,
            conversationSessionController: controller,
            voiceSessionCoordinator: voiceCoordinator
        )
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let rootA = try makeProjectRoot(named: "supervisor-voice-local-approval-context-a")
        let rootB = try makeProjectRoot(named: "supervisor-voice-local-approval-context-b")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        let projectA = makeProjectEntry(root: rootA, displayName: "耳机外出项目")
        let projectB = makeProjectEntry(root: rootB, displayName: "机器人采购项目")
        try fixture.writeHubSkillsStore(projectID: projectA.projectId)
        try fixture.writeHubSkillsStore(projectID: projectB.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, projectRoot in
            #expect(call.tool == ToolName.deviceBrowserControl)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "browser smoke completed for \(projectRoot.lastPathComponent)"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        appModel.selectedProjectId = projectA.projectId
        var settings = appModel.settingsStore.settings
        settings.voice.wakeMode = .pushToTalk
        settings.voice.preferredRoute = .systemSpeechCompatibility
        appModel.settingsStore.settings = settings
        manager.setAppModel(appModel)
        await voiceCoordinator.refreshRouteAvailability()
        await voiceCoordinator.refreshAuthorizationStatus(requestIfNeeded: false)

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeSupervisorTrustedAutomationPermissionReadiness()
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        try await waitUntil("voice route ready", timeoutMs: 5_000) {
            manager.voiceRouteDecision.route == .systemSpeechCompatibility
        }

        func createPendingLocalApproval(
            for project: AXProjectEntry,
            root: URL,
            planID: String
        ) throws {
            let ctx = try #require(appModel.projectContext(for: project.projectId))
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config
                .settingTrustedAutomationBinding(
                    mode: .trustedAutomation,
                    deviceId: "device_xt_001",
                    deviceToolGroups: ["device.browser.control"],
                    workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
                )
                .settingRuntimeSurfacePolicy(
                    mode: .trustedOpenClawMode,
                    updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
                )
            try AXProjectStore.saveConfig(config, for: ctx)

            _ = manager.processSupervisorResponseForTesting(
                #"[CREATE_JOB]{"project_ref":"\#(project.displayName)","goal":"运行 browser smoke","priority":"high"}[/CREATE_JOB]"#,
                userMessage: "请创建任务"
            )
            let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
            _ = manager.processSupervisorResponseForTesting(
                #"""
                [UPSERT_PLAN]{"project_ref":"\#(project.displayName)","job_id":"\#(job.jobId)","plan_id":"\#(planID)","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
                """#,
                userMessage: "请更新计划"
            )
            let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            let requestId = "skill-\(nowMs)-\(String(UUID().uuidString.lowercased().prefix(8)))"
            try SupervisorProjectSkillCallStore.upsert(
                SupervisorSkillCallRecord(
                    schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                    requestId: requestId,
                    projectId: project.projectId,
                    jobId: job.jobId,
                    planId: planID,
                    stepId: "step-001",
                    skillId: "browser.runtime.smoke",
                    toolName: ToolName.deviceBrowserControl.rawValue,
                    status: .awaitingAuthorization,
                    payload: ["url": .string("https://example.com")],
                    currentOwner: "supervisor",
                    resultSummary: "waiting for local governed approval",
                    denyCode: "",
                    resultEvidenceRef: nil,
                    requiredCapability: nil,
                    grantRequestId: nil,
                    grantId: nil,
                    createdAtMs: nowMs,
                    updatedAtMs: nowMs,
                    auditRef: "audit-\(requestId)"
                ),
                for: ctx
            )
            manager.refreshPendingSupervisorSkillApprovalsNow()
        }

        try createPendingLocalApproval(
            for: projectA,
            root: rootA,
            planID: "plan-browser-smoke-voice-context-a"
        )

        try createPendingLocalApproval(
            for: projectB,
            root: rootB,
            planID: "plan-browser-smoke-voice-context-b"
        )

        try await waitUntil("two pending local approvals present", timeoutMs: 5_000) {
            manager.pendingSupervisorSkillApprovals.count == 2
        }

        settings.voice.wakeMode = .wakePhrase
        appModel.settingsStore.settings = settings

        try await waitUntil("first proactive local approval alert emitted", timeoutMs: 5_000) {
            manager.messages.contains(where: {
                $0.role == SupervisorMessage.SupervisorRole.assistant &&
                    $0.content.contains("《\(projectA.displayName)》现在有一条待处理的本地技能调用：browser.runtime.smoke") &&
                    !$0.content.contains(rootA.lastPathComponent)
            }) &&
            spoken.contains(where: {
                $0.contains(projectA.displayName) &&
                    $0.contains("本地技能调用")
            }) &&
            manager.conversationSessionSnapshot.wakeMode == VoiceWakeMode.wakePhrase
        }

        appModel.selectedProjectId = projectB.projectId

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("批准这个技能调用")
        )
        #expect(rendered.contains("开始批准《\(projectA.displayName)》的技能调用了：browser.runtime.smoke"))
        #expect(!rendered.contains(rootA.lastPathComponent))

        await manager.waitForSupervisorSkillDispatchForTesting()

        let ctxA = try #require(appModel.projectContext(for: projectA.projectId))
        let ctxB = try #require(appModel.projectContext(for: projectB.projectId))
        let callA = try #require(SupervisorProjectSkillCallStore.load(for: ctxA).calls.first)
        let callB = try #require(SupervisorProjectSkillCallStore.load(for: ctxB).calls.first)
        #expect(callA.status == .completed)
        #expect(callA.resultSummary.contains("browser smoke completed"))
        #expect(callB.status == .awaitingAuthorization)
        #expect(!manager.messages.contains(where: {
            $0.role == SupervisorMessage.SupervisorRole.assistant &&
                $0.content.contains("当前有多条待处理的本地技能调用")
        }))
        #expect(manager.pendingSupervisorSkillApprovals.count == 1)
        #expect(manager.pendingSupervisorSkillApprovals.first?.projectId == projectB.projectId)
    }

    @Test
    func proactiveVoiceLocalSkillApprovalAnnouncementExplicitProjectMentionOverridesRecentContext() async throws {
        var spoken: [String] = []
        let controller = SupervisorConversationSessionController.makeForTesting(
            route: .systemSpeechCompatibility,
            wakeMode: .pushToTalk,
            nowProvider: { Date() }
        )
        let transcriber = SupervisorCommandGuardMockVoiceStreamingTranscriber()
        let voiceCoordinator = VoiceSessionCoordinator(
            transcriber: transcriber,
            preferences: .default()
        )
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer,
            conversationSessionController: controller,
            voiceSessionCoordinator: voiceCoordinator
        )
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let rootA = try makeProjectRoot(named: "supervisor-voice-local-approval-explicit-project-a")
        let rootB = try makeProjectRoot(named: "supervisor-voice-local-approval-explicit-project-b")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        let projectA = makeProjectEntry(root: rootA, displayName: "耳机外出项目")
        let projectB = makeProjectEntry(root: rootB, displayName: "机器人采购项目")
        try fixture.writeHubSkillsStore(projectID: projectA.projectId)
        try fixture.writeHubSkillsStore(projectID: projectB.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, projectRoot in
            #expect(call.tool == ToolName.deviceBrowserControl)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "browser smoke completed for \(projectRoot.lastPathComponent)"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        appModel.selectedProjectId = projectA.projectId
        var settings = appModel.settingsStore.settings
        settings.voice.wakeMode = .pushToTalk
        settings.voice.preferredRoute = .systemSpeechCompatibility
        appModel.settingsStore.settings = settings
        manager.setAppModel(appModel)
        await voiceCoordinator.refreshRouteAvailability()
        await voiceCoordinator.refreshAuthorizationStatus(requestIfNeeded: false)

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeSupervisorTrustedAutomationPermissionReadiness()
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        try await waitUntil("voice route ready", timeoutMs: 5_000) {
            manager.voiceRouteDecision.route == .systemSpeechCompatibility
        }

        func createPendingLocalApproval(
            for project: AXProjectEntry,
            root: URL,
            planID: String
        ) throws {
            let ctx = try #require(appModel.projectContext(for: project.projectId))
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config
                .settingTrustedAutomationBinding(
                    mode: .trustedAutomation,
                    deviceId: "device_xt_001",
                    deviceToolGroups: ["device.browser.control"],
                    workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
                )
                .settingRuntimeSurfacePolicy(
                    mode: .trustedOpenClawMode,
                    updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
                )
            try AXProjectStore.saveConfig(config, for: ctx)

            _ = manager.processSupervisorResponseForTesting(
                #"[CREATE_JOB]{"project_ref":"\#(project.displayName)","goal":"运行 browser smoke","priority":"high"}[/CREATE_JOB]"#,
                userMessage: "请创建任务"
            )
            let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
            _ = manager.processSupervisorResponseForTesting(
                #"""
                [UPSERT_PLAN]{"project_ref":"\#(project.displayName)","job_id":"\#(job.jobId)","plan_id":"\#(planID)","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"browser.runtime.smoke"}]}[/UPSERT_PLAN]
                """#,
                userMessage: "请更新计划"
            )
            let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            let requestId = "skill-\(nowMs)-\(String(UUID().uuidString.lowercased().prefix(8)))"
            try SupervisorProjectSkillCallStore.upsert(
                SupervisorSkillCallRecord(
                    schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                    requestId: requestId,
                    projectId: project.projectId,
                    jobId: job.jobId,
                    planId: planID,
                    stepId: "step-001",
                    skillId: "browser.runtime.smoke",
                    toolName: ToolName.deviceBrowserControl.rawValue,
                    status: .awaitingAuthorization,
                    payload: ["url": .string("https://example.com")],
                    currentOwner: "supervisor",
                    resultSummary: "waiting for local governed approval",
                    denyCode: "",
                    resultEvidenceRef: nil,
                    requiredCapability: nil,
                    grantRequestId: nil,
                    grantId: nil,
                    createdAtMs: nowMs,
                    updatedAtMs: nowMs,
                    auditRef: "audit-\(requestId)"
                ),
                for: ctx
            )
            manager.refreshPendingSupervisorSkillApprovalsNow()
        }

        try createPendingLocalApproval(
            for: projectA,
            root: rootA,
            planID: "plan-browser-smoke-voice-explicit-project-a"
        )

        try createPendingLocalApproval(
            for: projectB,
            root: rootB,
            planID: "plan-browser-smoke-voice-explicit-project-b"
        )

        try await waitUntil("two pending local approvals present", timeoutMs: 5_000) {
            manager.pendingSupervisorSkillApprovals.count == 2
        }

        settings.voice.wakeMode = .wakePhrase
        appModel.settingsStore.settings = settings

        try await waitUntil("first proactive local approval alert emitted", timeoutMs: 5_000) {
            manager.messages.contains(where: {
                $0.role == SupervisorMessage.SupervisorRole.assistant &&
                    $0.content.contains("《\(projectA.displayName)》现在有一条待处理的本地技能调用：browser.runtime.smoke") &&
                    !$0.content.contains(rootA.lastPathComponent)
            }) &&
            spoken.contains(where: {
                $0.contains(projectA.displayName) &&
                    $0.contains("本地技能调用")
            })
        }

        appModel.selectedProjectId = projectA.projectId

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("批准\(projectB.displayName)这个技能调用")
        )
        #expect(rendered.contains("开始批准《\(projectB.displayName)》的技能调用了：browser.runtime.smoke"))
        #expect(!rendered.contains(rootB.lastPathComponent))

        await manager.waitForSupervisorSkillDispatchForTesting()

        let ctxA = try #require(appModel.projectContext(for: projectA.projectId))
        let ctxB = try #require(appModel.projectContext(for: projectB.projectId))
        let callA = try #require(SupervisorProjectSkillCallStore.load(for: ctxA).calls.first)
        let callB = try #require(SupervisorProjectSkillCallStore.load(for: ctxB).calls.first)
        #expect(callA.status == .awaitingAuthorization)
        #expect(callB.status == .completed)
        #expect(callB.resultSummary.contains("browser smoke completed"))
        #expect(manager.pendingSupervisorSkillApprovals.count == 1)
        #expect(manager.pendingSupervisorSkillApprovals.first?.projectId == projectA.projectId)
    }

    @Test
    func naturalLanguageLocalSkillApprovalOrdinalSelectionOverridesAmbientFocus() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let rootA = try makeProjectRoot(named: "supervisor-local-approval-ordinal-a")
        let rootB = try makeProjectRoot(named: "supervisor-local-approval-ordinal-b")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        let projectA = makeProjectEntry(root: rootA, displayName: "耳机外出项目")
        let projectB = makeProjectEntry(root: rootB, displayName: "机器人采购项目")
        try fixture.writeHubSkillsStore(projectID: projectA.projectId)
        try fixture.writeHubSkillsStore(projectID: projectB.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, projectRoot in
            #expect(call.tool == .deviceBrowserControl)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "browser smoke completed for \(projectRoot.lastPathComponent)"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        appModel.selectedProjectId = projectA.projectId
        manager.setAppModel(appModel)

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeSupervisorTrustedAutomationPermissionReadiness()
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let ctxA = try createPendingLocalSkillApprovalRecord(
            manager: manager,
            appModel: appModel,
            project: projectA,
            root: rootA,
            planID: "plan-browser-smoke-ordinal-a",
            createdAtMs: 1_900_000_000_100
        )
        let ctxB = try createPendingLocalSkillApprovalRecord(
            manager: manager,
            appModel: appModel,
            project: projectB,
            root: rootB,
            planID: "plan-browser-smoke-ordinal-b",
            createdAtMs: 1_900_000_000_200
        )

        #expect(manager.pendingSupervisorSkillApprovals.count == 2)

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("批准第二个技能调用")
        )
        #expect(rendered.contains("开始批准《\(projectB.displayName)》的技能调用了：browser.runtime.smoke"))
        #expect(!rendered.contains(rootB.lastPathComponent))

        await manager.waitForSupervisorSkillDispatchForTesting()

        let callA = try #require(SupervisorProjectSkillCallStore.load(for: ctxA).calls.first)
        let callB = try #require(SupervisorProjectSkillCallStore.load(for: ctxB).calls.first)
        #expect(callA.status == .awaitingAuthorization)
        #expect(callB.status == .completed)
        #expect(callB.resultSummary.contains("browser smoke completed"))
        #expect(manager.pendingSupervisorSkillApprovals.count == 1)
        #expect(manager.pendingSupervisorSkillApprovals.first?.projectId == projectA.projectId)
    }

    @Test
    func naturalLanguageLocalSkillApprovalProjectAliasFragmentOverridesAmbientFocus() async throws {
        let manager = SupervisorManager.makeForTesting()
        let fixture = SupervisorSkillRegistryFixture()
        defer { fixture.cleanup() }

        let rootA = try makeProjectRoot(named: "supervisor-local-approval-alias-a")
        let rootB = try makeProjectRoot(named: "supervisor-local-approval-alias-b")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        let projectA = makeProjectEntry(root: rootA, displayName: "耳机外出项目")
        let projectB = makeProjectEntry(root: rootB, displayName: "机器人采购项目")
        try fixture.writeHubSkillsStore(projectID: projectA.projectId)
        try fixture.writeHubSkillsStore(projectID: projectB.projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        manager.setSupervisorToolExecutorOverrideForTesting { call, projectRoot in
            #expect(call.tool == .deviceBrowserControl)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "browser smoke completed for \(projectRoot.lastPathComponent)"
            )
        }

        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        appModel.selectedProjectId = projectA.projectId
        manager.setAppModel(appModel)

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeSupervisorTrustedAutomationPermissionReadiness()
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let ctxA = try createPendingLocalSkillApprovalRecord(
            manager: manager,
            appModel: appModel,
            project: projectA,
            root: rootA,
            planID: "plan-browser-smoke-alias-a",
            createdAtMs: 1_900_000_000_300
        )
        let ctxB = try createPendingLocalSkillApprovalRecord(
            manager: manager,
            appModel: appModel,
            project: projectB,
            root: rootB,
            planID: "plan-browser-smoke-alias-b",
            createdAtMs: 1_900_000_000_400
        )

        #expect(manager.pendingSupervisorSkillApprovals.count == 2)

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("批准采购那个技能调用")
        )
        #expect(rendered.contains("开始批准《\(projectB.displayName)》的技能调用了：browser.runtime.smoke"))
        #expect(!rendered.contains(rootB.lastPathComponent))

        await manager.waitForSupervisorSkillDispatchForTesting()

        let callA = try #require(SupervisorProjectSkillCallStore.load(for: ctxA).calls.first)
        let callB = try #require(SupervisorProjectSkillCallStore.load(for: ctxB).calls.first)
        #expect(callA.status == .awaitingAuthorization)
        #expect(callB.status == .completed)
        #expect(callB.resultSummary.contains("browser smoke completed"))
        #expect(manager.pendingSupervisorSkillApprovals.count == 1)
        #expect(manager.pendingSupervisorSkillApprovals.first?.projectId == projectA.projectId)
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

        #expect(rendered.contains("开始处理《亮亮》的联网访问 Hub 授权"))
        #expect(rendered.contains("授权范围：TTL 15 分钟"))
        for _ in 0..<40 {
            if await capture.count() == 1 {
                break
            }
            await Task.yield()
        }
        #expect(await capture.count() == 1)
    }

    @Test
    func naturalLanguageGrantApprovalUsesFriendlyProjectNameFromPendingSnapshotNormalization() async throws {
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
        let root = try makeProjectRoot(named: "supervisor-natural-grant-snapshot-normalization")
        defer { try? FileManager.default.removeItem(at: root) }

        let friendlyName = "外出采购项目"
        let project = makeProjectEntry(root: root, displayName: friendlyName)
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
                grantId: "grant-live-snapshot-1",
                expiresAtMs: nil,
                reasonCode: nil
            )
        }
        manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
        manager.setPendingGrantSnapshotForTesting(
            HubIPCClient.PendingGrantSnapshot(
                source: "hub_runtime_grpc",
                updatedAtMs: Date().timeIntervalSince1970 * 1000.0,
                items: [
                    HubIPCClient.PendingGrantItem(
                        grantRequestId: "grant-snapshot-1",
                        requestId: "req-snapshot-1",
                        deviceId: "device_xt_001",
                        userId: "user-1",
                        appId: "x-terminal",
                        projectId: project.projectId,
                        capability: "web.fetch",
                        modelId: "",
                        reason: "buy groceries from remote workflow",
                        requestedTtlSec: 900,
                        requestedTokenCap: 0,
                        status: "pending",
                        decision: "queued",
                        createdAtMs: Date().timeIntervalSince1970 * 1000.0,
                        decidedAtMs: 0
                    )
                ]
            )
        )

        #expect(manager.pendingHubGrants.count == 1)
        #expect(manager.pendingHubGrants.first?.projectName == friendlyName)
        #expect(manager.pendingHubGrants.first?.projectName.contains(root.lastPathComponent) == false)

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("批准这个授权")
        )

        #expect(rendered.contains("开始处理《\(friendlyName)》的联网访问 Hub 授权"))
        #expect(rendered.contains("授权范围：TTL 15 分钟"))
        #expect(!rendered.contains(root.lastPathComponent))
        for _ in 0..<40 {
            if await capture.count() == 1 {
                break
            }
            await Task.yield()
        }
        #expect(await capture.count() == 1)
    }

    @Test
    func naturalLanguageGrantContextExpiresAfterCarryWindow() async throws {
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
        let root = try makeProjectRoot(named: "supervisor-natural-grant-context-expire-time")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        let now = Date().timeIntervalSince1970
        manager.messages = [
            SupervisorMessage(
                id: "system-grant-stale-context",
                role: .system,
                content: "当前有一笔待授权的 Hub 授权：亮亮 / 联网访问。",
                isVoice: false,
                timestamp: now - 600
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
                grantId: "grant-live-context-stale",
                expiresAtMs: nil,
                reasonCode: nil
            )
        }
        manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "grant-natural-context-stale",
                    dedupeKey: "grant-natural-context-stale",
                    grantRequestId: "grant-natural-context-stale",
                    requestId: "req-natural-context-stale",
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

        #expect(manager.directSupervisorActionIfApplicableForTesting("批了吧") == nil)
        #expect(await capture.count() == 0)
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
                content: "当前有一笔待授权的 Hub 授权：亮亮 / 联网访问。",
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

        #expect(rendered.contains("开始处理《亮亮》的联网访问 Hub 授权"))
        #expect(rendered.contains("授权范围：TTL 15 分钟"))
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
                content: "当前有一笔待授权的 Hub 授权：亮亮 / 联网访问。",
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

        #expect(rendered.contains("先拦下《亮亮》的联网访问 Hub 授权"))
        #expect(rendered.contains("授权范围：TTL 15 分钟"))
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

        #expect(rendered.contains("开始处理《亮亮》的联网访问 Hub 授权"))
        #expect(rendered.contains("授权范围：TTL 15 分钟"))
        for _ in 0..<40 {
            if await capture.count() == 1 {
                break
            }
            await Task.yield()
        }
        #expect(await capture.count() == 1)
    }

    @Test
    func naturalLanguageGrantApprovalExplicitHiddenProjectStillResolvesOutsideJurisdictionView() async throws {
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
        let root = try makeProjectRoot(named: "supervisor-natural-grant-approve-hidden-project")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_600).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        let capture = ApprovalCapture()
        manager.installPendingHubGrantApproveOverrideForTesting { grantRequestId, _, _, _, _ in
            await capture.record(grantRequestId)
            return HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .approved,
                source: "test",
                grantRequestId: grantRequestId,
                grantId: "grant-hidden-live-1",
                expiresAtMs: nil,
                reasonCode: nil
            )
        }
        manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
        manager.setPendingHubGrantsForTesting(
            [
                makePendingHubGrant(
                    id: "grant-hidden-approve-1",
                    requestId: "req-hidden-approve-1",
                    project: project,
                    capability: "web.fetch",
                    reason: "need web access for hidden release path",
                    createdAt: 1_900_000_500
                )
            ]
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("批准亮亮这个授权")
        )

        #expect(rendered.contains("开始处理《亮亮》的联网访问 Hub 授权"))
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

        #expect(rendered.contains("先拦下《亮亮》的联网访问 Hub 授权"))
        #expect(rendered.contains("授权范围：TTL 15 分钟"))
        for _ in 0..<40 {
            if await capture.count() == 1 {
                break
            }
            await Task.yield()
        }
        #expect(await capture.count() == 1)
    }

    @Test
    func naturalLanguageGrantApprovalOrdinalSelectionOverridesAmbientFocus() async throws {
        actor ApprovalCapture {
            private(set) var grantIDs: [String] = []

            func record(_ grantID: String) {
                grantIDs.append(grantID)
            }

            func count() -> Int {
                grantIDs.count
            }

            func last() -> String? {
                grantIDs.last
            }
        }

        let manager = SupervisorManager.makeForTesting()
        let rootA = try makeProjectRoot(named: "supervisor-natural-grant-ordinal-a")
        let rootB = try makeProjectRoot(named: "supervisor-natural-grant-ordinal-b")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        let projectA = makeProjectEntry(root: rootA, displayName: "耳机外出项目")
        let projectB = makeProjectEntry(root: rootB, displayName: "机器人采购项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        appModel.selectedProjectId = projectA.projectId
        manager.setAppModel(appModel)

        let capture = ApprovalCapture()
        manager.installPendingHubGrantApproveOverrideForTesting { grantRequestId, _, _, _, _ in
            await capture.record(grantRequestId)
            return HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .approved,
                source: "test",
                grantRequestId: grantRequestId,
                grantId: "grant-live-ordinal",
                expiresAtMs: nil,
                reasonCode: nil
            )
        }
        manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
        manager.setPendingHubGrantsForTesting(
            [
                makePendingHubGrant(
                    id: "grant-ordinal-a",
                    requestId: "req-ordinal-a",
                    project: projectA,
                    capability: "web.fetch",
                    reason: "need web access for headset route",
                    createdAt: 1_900_000_100
                ),
                makePendingHubGrant(
                    id: "grant-ordinal-b",
                    requestId: "req-ordinal-b",
                    project: projectB,
                    capability: "web.fetch",
                    reason: "buy groceries from remote workflow",
                    createdAt: 1_900_000_200
                )
            ]
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("批准第二个授权")
        )

        #expect(rendered.contains("开始处理《\(projectB.displayName)》的联网访问 Hub 授权"))
        for _ in 0..<40 {
            if await capture.count() == 1 {
                break
            }
            await Task.yield()
        }
        #expect(await capture.count() == 1)
        #expect(await capture.last() == "grant-ordinal-b")
    }

    @Test
    func naturalLanguageGrantApprovalProjectAliasFragmentOverridesAmbientFocus() async throws {
        actor ApprovalCapture {
            private(set) var grantIDs: [String] = []

            func record(_ grantID: String) {
                grantIDs.append(grantID)
            }

            func count() -> Int {
                grantIDs.count
            }

            func last() -> String? {
                grantIDs.last
            }
        }

        let manager = SupervisorManager.makeForTesting()
        let rootA = try makeProjectRoot(named: "supervisor-natural-grant-alias-a")
        let rootB = try makeProjectRoot(named: "supervisor-natural-grant-alias-b")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        let projectA = makeProjectEntry(root: rootA, displayName: "耳机外出项目")
        let projectB = makeProjectEntry(root: rootB, displayName: "机器人采购项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        appModel.selectedProjectId = projectA.projectId
        manager.setAppModel(appModel)

        let capture = ApprovalCapture()
        manager.installPendingHubGrantApproveOverrideForTesting { grantRequestId, _, _, _, _ in
            await capture.record(grantRequestId)
            return HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .approved,
                source: "test",
                grantRequestId: grantRequestId,
                grantId: "grant-live-alias",
                expiresAtMs: nil,
                reasonCode: nil
            )
        }
        manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
        manager.setPendingHubGrantsForTesting(
            [
                makePendingHubGrant(
                    id: "grant-alias-a",
                    requestId: "req-alias-a",
                    project: projectA,
                    capability: "web.fetch",
                    reason: "need web access for headset route",
                    createdAt: 1_900_000_300
                ),
                makePendingHubGrant(
                    id: "grant-alias-b",
                    requestId: "req-alias-b",
                    project: projectB,
                    capability: "web.fetch",
                    reason: "buy groceries from remote workflow",
                    createdAt: 1_900_000_400
                )
            ]
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("批准采购那个授权")
        )

        #expect(rendered.contains("开始处理《\(projectB.displayName)》的联网访问 Hub 授权"))
        for _ in 0..<40 {
            if await capture.count() == 1 {
                break
            }
            await Task.yield()
        }
        #expect(await capture.count() == 1)
        #expect(await capture.last() == "grant-alias-b")
    }

    @Test
    func continueIntentBootstrapsFocusedProjectWorkflowFromConcreteMemory() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-continue-bootstrap")
        defer { try? FileManager.default.removeItem(at: root) }

        var project = makeProjectEntry(root: root, displayName: "亮亮")
        project.currentStateSummary = "模块边界已初步摸清，但结构整理还没落盘"
        project.nextStepSummary = "梳理项目结构并给出重构建议"
        project.blockerSummary = "grant_required"

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("继续推进亮亮项目")
        )

        #expect(rendered.contains("把下一步起成一个受治理 workflow"))
        #expect(rendered.contains("任务目标：梳理项目结构并给出重构建议"))
        #expect(rendered.contains("当前阻塞：Hub 授权未完成（grant_required）"))
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
    func continueIntentExplicitHiddenProjectStillBootstrapsWorkflowOutsideJurisdictionView() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-continue-hidden-project")
        defer { try? FileManager.default.removeItem(at: root) }

        var project = makeProjectEntry(root: root, displayName: "亮亮")
        project.currentStateSummary = "结构梳理还没正式落盘"
        project.nextStepSummary = "梳理项目结构并给出重构建议"
        project.blockerSummary = "缺一版明确的分层切割方案"

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_610).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("继续推进亮亮项目")
        )

        #expect(rendered.contains("把下一步起成一个受治理 workflow"))
        #expect(rendered.contains("任务目标：梳理项目结构并给出重构建议"))

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        #expect(job.projectId == project.projectId)
        #expect(job.goal == "梳理项目结构并给出重构建议")
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
    func hiddenProjectAssignModelMessageDoesNotLeakOutsideJurisdictionView() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-assign-model-hidden-project")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "我的世界还原项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_420).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)
        manager.clearMessages()

        let rendered = manager.processSupervisorResponseForTesting(
            "[ASSIGN_MODEL]\(project.displayName)|开发者|openai/gpt-5.3-codex[/ASSIGN_MODEL]",
            userMessage: "把 \(project.displayName) 的开发者模型改为 openai/gpt-5.3-codex"
        )

        #expect(rendered.contains("✅ 已为项目 \(project.displayName) 设置 编程助手 模型：openai/gpt-5.3-codex"))
        #expect(manager.messages.contains(where: {
            $0.content.contains("✅ 已为项目 \(project.displayName) 设置 编程助手 模型：openai/gpt-5.3-codex")
        }) == false)

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(config.modelOverride(for: .coder) == "openai/gpt-5.3-codex")
    }

    @Test
    func assignModelAllOnlyTouchesVisibleProjectsInCurrentJurisdictionView() throws {
        let manager = SupervisorManager.makeForTesting()
        let visibleRoot = try makeProjectRoot(named: "supervisor-assign-model-all-visible-project")
        defer { try? FileManager.default.removeItem(at: visibleRoot) }
        let hiddenRoot = try makeProjectRoot(named: "supervisor-assign-model-all-hidden-project")
        defer { try? FileManager.default.removeItem(at: hiddenRoot) }

        let visibleProject = makeProjectEntry(root: visibleRoot, displayName: "可见项目")
        let hiddenProject = makeProjectEntry(root: hiddenRoot, displayName: "隐藏项目")
        let appModel = AppModel()
        appModel.registry = registry(with: [visibleProject, hiddenProject])
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_430).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: hiddenProject.projectId, displayName: hiddenProject.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)
        manager.clearMessages()

        let rendered = manager.processSupervisorResponseForTesting(
            "[ASSIGN_MODEL_ALL]开发者|openai/gpt-5.3-codex[/ASSIGN_MODEL_ALL]",
            userMessage: "把当前可见项目的开发者模型都改为 openai/gpt-5.3-codex"
        )

        #expect(rendered.contains("✅ 已为全部 1 个项目设置 编程助手 模型：openai/gpt-5.3-codex"))
        #expect(!rendered.contains(hiddenProject.displayName))
        #expect(manager.messages.contains(where: { $0.content.contains(hiddenProject.displayName) }) == false)

        let visibleCtx = try #require(appModel.projectContext(for: visibleProject.projectId))
        let visibleConfig = try AXProjectStore.loadOrCreateConfig(for: visibleCtx)
        #expect(visibleConfig.modelOverride(for: .coder) == "openai/gpt-5.3-codex")

        let hiddenCtx = try #require(appModel.projectContext(for: hiddenProject.projectId))
        let hiddenConfig = try AXProjectStore.loadOrCreateConfig(for: hiddenCtx)
        #expect(hiddenConfig.modelOverride(for: .coder) == nil)
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

    @Test
    func directRepoReadRequestReadsSelectedProjectFiles() async throws {
        let manager = SupervisorManager.makeForTesting()
        let containerRoot = try makeProjectRoot(named: "supervisor-direct-repo-read")
        defer { try? FileManager.default.removeItem(at: containerRoot) }

        let root = containerRoot.appendingPathComponent("x-hub-system", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("docs", isDirectory: true),
            withIntermediateDirectories: true
        )

        try """
        # X Hub README

        Hub overview paragraph.
        """.write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # X Memory

        Memory contract paragraph.
        """.write(
            to: root.appendingPathComponent("X_MEMORY.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # Working Index

        Current chain paragraph.
        """.write(
            to: root.appendingPathComponent("docs", isDirectory: true).appendingPathComponent("WORKING_INDEX.md"),
            atomically: true,
            encoding: .utf8
        )

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let rendered = try #require(
            await manager.directSupervisorRepoInspectionReplyForTesting(
                "读一下 1. x-hub-system/README.md 2. x-hub-system/X_MEMORY.md 3. x-hub-system/docs/WORKING_INDEX.md"
            )
        )

        #expect(rendered.contains("我已经直接读取《亮亮》里的 3 个文件"))
        #expect(rendered.contains("[x-hub-system/README.md]"))
        #expect(rendered.contains("# X Hub README"))
        #expect(rendered.contains("# X Memory"))
        #expect(rendered.contains("# Working Index"))
    }

    @Test
    func directRepoReadRequestFailsClosedWhenProjectSelectionIsAmbiguous() async throws {
        let manager = SupervisorManager.makeForTesting()
        let rootA = try makeProjectRoot(named: "supervisor-direct-repo-read-ambiguous-a")
        let rootB = try makeProjectRoot(named: "supervisor-direct-repo-read-ambiguous-b")
        defer { try? FileManager.default.removeItem(at: rootA) }
        defer { try? FileManager.default.removeItem(at: rootB) }

        let projectA = makeProjectEntry(root: rootA, displayName: "Alpha Console")
        let projectB = makeProjectEntry(root: rootB, displayName: "Beta Studio")
        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        manager.setAppModel(appModel)

        let rendered = try #require(
            await manager.directSupervisorRepoInspectionReplyForTesting("读一下 README.md")
        )

        #expect(rendered.contains("当前项目不唯一"))
        #expect(rendered.contains(projectA.displayName))
        #expect(rendered.contains(projectB.displayName))
    }

    @Test
    func directRepoReadIntentDoesNotHijackUpdateReviewRequests() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-direct-repo-read-review-intent")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let rendered = await manager.directSupervisorRepoInspectionReplyForTesting(
            "看下 README.md 是否需要更新"
        )

        #expect(rendered == nil)
    }

    @Test
    func directRepoReadExplicitHiddenProjectStillWorksOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-direct-repo-read-hidden-project")
        defer { try? FileManager.default.removeItem(at: root) }

        try """
        # Hidden Repo README

        Hidden repo details.
        """.write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_620).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        let rendered = try #require(
            await manager.directSupervisorRepoInspectionReplyForTesting("读一下亮亮的 README.md")
        )

        #expect(rendered.contains("我已经直接读取《亮亮》里的 1 个文件"))
        #expect(rendered.contains("[README.md]"))
        #expect(rendered.contains("# Hidden Repo README"))
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

    private func currentEnvironmentValue(_ key: String) -> String? {
        guard let value = getenv(key) else { return nil }
        return String(cString: value)
    }

    private func createPendingLocalSkillApprovalRecord(
        manager: SupervisorManager,
        appModel: AppModel,
        project: AXProjectEntry,
        root: URL,
        planID: String,
        createdAtMs: Int64,
        skillID: String = "browser.runtime.smoke"
    ) throws -> AXProjectContext {
        guard let ctx = appModel.projectContext(for: project.projectId) else {
            throw CocoaError(.fileNoSuchFile)
        }

        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
            )
            .settingRuntimeSurfacePolicy(
                mode: .trustedOpenClawMode,
                updatedAt: freshTrustedRuntimeSurfaceUpdatedAt()
            )
        try AXProjectStore.saveConfig(config, for: ctx)

        let escapedProjectName = jsonEscapedString(project.displayName)
        let escapedPlanID = jsonEscapedString(planID)
        let escapedSkillID = jsonEscapedString(skillID)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"\#(escapedProjectName)","goal":"运行 browser smoke","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )
        guard let job = SupervisorProjectJobStore.load(for: ctx).jobs.first else {
            throw CocoaError(.coderInvalidValue)
        }

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"\#(escapedProjectName)","job_id":"\#(job.jobId)","plan_id":"\#(escapedPlanID)","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"运行 browser runtime smoke","kind":"call_skill","status":"pending","skill_id":"\#(escapedSkillID)"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        let requestId = "skill-\(createdAtMs)-\(String(UUID().uuidString.lowercased().prefix(8)))"
        try SupervisorProjectSkillCallStore.upsert(
            SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: requestId,
                projectId: project.projectId,
                jobId: job.jobId,
                planId: planID,
                stepId: "step-001",
                skillId: skillID,
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .awaitingAuthorization,
                payload: ["url": .string("https://example.com")],
                currentOwner: "supervisor",
                resultSummary: "waiting for local governed approval",
                denyCode: "",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: createdAtMs,
                updatedAtMs: createdAtMs,
                auditRef: "audit-\(requestId)"
            ),
            for: ctx
        )
        manager.refreshPendingSupervisorSkillApprovalsNow()
        return ctx
    }

    private func makePendingHubGrant(
        id: String,
        requestId: String,
        project: AXProjectEntry,
        capability: String,
        reason: String,
        createdAt: TimeInterval
    ) -> SupervisorManager.SupervisorPendingGrant {
        SupervisorManager.SupervisorPendingGrant(
            id: id,
            dedupeKey: id,
            grantRequestId: id,
            requestId: requestId,
            projectId: project.projectId,
            projectName: project.displayName,
            capability: capability,
            modelId: "",
            reason: reason,
            requestedTtlSec: 900,
            requestedTokenCap: 0,
            createdAt: createdAt,
            actionURL: nil,
            priorityRank: 1,
            priorityReason: "network",
            nextAction: "approve"
        )
    }

    private func freshTrustedRuntimeSurfaceUpdatedAt(offsetSec: TimeInterval = -60) -> Date {
        Date().addingTimeInterval(offsetSec)
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

    private func seedStrongProjectAIStrengthEvidence(
        ctx: AXProjectContext,
        projectID: String
    ) throws {
        try ctx.ensureDirs()

        try writeJSONLines(
            [
                [
                    "type": "project_skill_call",
                    "request_id": "req-strong-004",
                    "skill_id": "agent-browser",
                    "tool_name": "device.browser.control",
                    "status": "completed",
                    "created_at": 400,
                    "resolution_source": "test",
                    "tool_args": ["action": "snapshot"],
                    "result_summary": "captured the latest page state",
                    "detail": "latest browser page observation completed"
                ],
                [
                    "type": "project_skill_call",
                    "request_id": "req-strong-003",
                    "skill_id": "summarize",
                    "tool_name": "summarize",
                    "status": "completed",
                    "created_at": 300,
                    "resolution_source": "test",
                    "tool_args": ["source": "artifact://latest-review"],
                    "result_summary": "summarized review anchor",
                    "detail": "review anchor summary completed"
                ],
                [
                    "type": "project_skill_call",
                    "request_id": "req-strong-002",
                    "skill_id": "repo.test.run",
                    "tool_name": "repo.test.run",
                    "status": "completed",
                    "created_at": 200,
                    "resolution_source": "test",
                    "tool_args": ["command": "swift test --filter SupervisorReviewPolicyEngineTests"],
                    "result_summary": "tests passed",
                    "detail": "targeted supervisor tests passed"
                ],
                [
                    "type": "project_skill_call",
                    "request_id": "req-strong-001",
                    "skill_id": "repo.write.file",
                    "tool_name": "repo.write.file",
                    "status": "completed",
                    "created_at": 100,
                    "resolution_source": "test",
                    "tool_args": ["path": "Sources/Supervisor/SupervisorManager.swift"],
                    "result_summary": "updated runtime governance logic",
                    "detail": "patched supervisor runtime relaxation logic"
                ],
            ],
            to: ctx.rawLogURL
        )

        try writeJSONLines(
            [
                [
                    "type": "ai_usage",
                    "role": AXRole.coder.rawValue,
                    "created_at": 500,
                    "stage": "assist",
                    "requested_model_id": "openai/gpt-5.4",
                    "actual_model_id": "openai/gpt-5.4",
                    "runtime_provider": "Hub",
                    "execution_path": "remote_model"
                ],
                [
                    "type": "ai_usage",
                    "role": AXRole.reviewer.rawValue,
                    "created_at": 450,
                    "stage": "review",
                    "requested_model_id": "openai/gpt-5.4",
                    "actual_model_id": "openai/gpt-5.4",
                    "runtime_provider": "Hub",
                    "execution_path": "remote_model"
                ],
            ],
            to: ctx.usageLogURL
        )

        let review = XTUIReviewRecord(
            schemaVersion: XTUIReviewRecord.currentSchemaVersion,
            reviewID: "uir-strong-flex-ready",
            projectID: projectID,
            bundleID: "bundle-strong-flex-ready",
            bundleRef: "local://.xterminal/ui_observation/bundles/bundle-strong-flex-ready.json",
            surfaceType: .browserPage,
            probeDepth: .deep,
            objective: "browser_page_actionability",
            verdict: .ready,
            confidence: .high,
            sufficientEvidence: true,
            objectiveReady: true,
            interactiveTargetCount: 3,
            criticalActionExpected: true,
            criticalActionVisible: true,
            issueCodes: [],
            checks: [
                XTUIReviewCheck(
                    code: "interactive_target_present",
                    status: .pass,
                    detail: "Interactive targets and primary action are both visible."
                )
            ],
            summary: "ready; confidence=high; execution-ready browser evidence is stable",
            createdAtMs: 700_000,
            auditRef: "audit-ui-review-strong-flex"
        )
        _ = try XTUIReviewStore.writeReview(review, for: ctx)
    }

    private func writeJSONLines(
        _ objects: [[String: Any]],
        to url: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let lines = try objects.map { object -> String in
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            guard let line = String(data: data, encoding: .utf8) else {
                throw CocoaError(.coderInvalidValue)
            }
            return line
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func waitUntil(
        _ label: String,
        timeoutMs: UInt64 = 2_000,
        intervalMs: UInt64 = 50,
        condition: @escaping @MainActor @Sendable () -> Bool
    ) async throws {
        let attempts = max(1, Int(timeoutMs / intervalMs))
        for _ in 0..<attempts {
            if await MainActor.run(body: condition) {
                return
            }
            try await Task.sleep(nanoseconds: intervalMs * 1_000_000)
        }
        Issue.record("Timed out waiting for \(label)")
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

private func writeOfficialSkillLifecycleFixture(
    hubBaseDir: URL,
    packages: [[String: Any]],
    updatedAtMs: Int64 = 88
) throws {
    let storeDir = hubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
    try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

    let payload: [String: Any] = [
        "schema_version": "xhub.official_skill_package_lifecycle_snapshot.v1",
        "updated_at_ms": updatedAtMs,
        "totals": [
            "packages_total": packages.count,
            "ready_total": 0,
            "degraded_total": 0,
            "blocked_total": packages.count,
            "not_installed_total": 0,
            "not_supported_total": 0,
            "revoked_total": 0,
            "active_total": 0,
        ],
        "packages": packages,
    ]
    try writeJSONObject(
        payload,
        to: storeDir.appendingPathComponent("official_skill_package_lifecycle.json")
    )
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

private func extractTaggedSection(_ text: String, tag: String) -> String? {
    let startToken = "[\(tag)]"
    let endToken = "[/\(tag)]"
    guard let start = text.range(of: startToken),
          let end = text.range(of: endToken, range: start.upperBound..<text.endIndex) else {
        return nil
    }
    return String(text[start.upperBound..<end.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func makeSupervisorMemoryAssemblySnapshot(
    projectID: String,
    reviewLevelHint: SupervisorReviewLevel = .r2Strategic,
    requestedProfile: String = XTMemoryServingProfile.m3DeepDive.rawValue,
    profileFloor: String = XTMemoryServingProfile.m3DeepDive.rawValue,
    resolvedProfile: String = XTMemoryServingProfile.m3DeepDive.rawValue,
    contextRefsSelected: Int = 2,
    evidenceItemsSelected: Int = 2,
    omittedSections: [String] = [],
    truncatedLayers: [String] = []
) -> SupervisorMemoryAssemblySnapshot {
    SupervisorMemoryAssemblySnapshot(
        source: "unit_test",
        resolutionSource: "unit_test",
        updatedAt: 1_773_000_000,
        reviewLevelHint: reviewLevelHint.rawValue,
        requestedProfile: requestedProfile,
        profileFloor: profileFloor,
        resolvedProfile: resolvedProfile,
        attemptedProfiles: [requestedProfile, resolvedProfile],
        progressiveUpgradeCount: 0,
        focusedProjectId: projectID,
        selectedSections: [
            "portfolio_brief",
            "focused_project_anchor_pack",
            "longterm_outline",
            "delta_feed",
            "conflict_set",
            "context_refs",
            "evidence_pack",
        ],
        omittedSections: omittedSections,
        contextRefsSelected: contextRefsSelected,
        contextRefsOmitted: max(0, 2 - contextRefsSelected),
        evidenceItemsSelected: evidenceItemsSelected,
        evidenceItemsOmitted: max(0, 2 - evidenceItemsSelected),
        budgetTotalTokens: 1_800,
        usedTotalTokens: 1_080,
        truncatedLayers: truncatedLayers,
        freshness: "fresh_local_ipc",
        cacheHit: false,
        denyCode: nil,
        downgradeCode: resolvedProfile == profileFloor ? nil : "budget_guardrail",
        reasonCode: nil,
        compressionPolicy: "progressive_disclosure"
    )
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

private final class SupervisorCommandGuardMockVoiceStreamingTranscriber: VoiceStreamingTranscriber {
    let routeMode: VoiceRouteMode
    private(set) var authorizationStatus: VoiceTranscriberAuthorizationStatus
    private(set) var engineHealth: VoiceEngineHealth
    private(set) var healthReasonCode: String?
    private(set) var isRunning: Bool = false

    init(
        routeMode: VoiceRouteMode = .systemSpeechCompatibility,
        authorizationStatus: VoiceTranscriberAuthorizationStatus = .authorized,
        engineHealth: VoiceEngineHealth = .ready,
        healthReasonCode: String? = nil
    ) {
        self.routeMode = routeMode
        self.authorizationStatus = authorizationStatus
        self.engineHealth = engineHealth
        self.healthReasonCode = healthReasonCode
    }

    func requestAuthorization() async -> VoiceTranscriberAuthorizationStatus {
        authorizationStatus
    }

    func refreshEngineHealth() async -> VoiceEngineHealth {
        engineHealth
    }

    func startTranscribing(
        onChunk: @escaping (VoiceTranscriptChunk) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        guard authorizationStatus.isAuthorized else {
            throw VoiceTranscriberError.notAuthorized
        }
        isRunning = true
    }

    func stopTranscribing() {
        isRunning = false
    }
}
