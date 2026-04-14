import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import XTerminal

@Suite(.serialized)
struct AXSkillsRemoteRegistryTests {
    @Test
    func remoteResolvedSkillsCacheBuildsPreferredRegistryAndRouterMapping() async throws {
        let fixture = try RemoteSkillFixture(skillID: "summarize")
        defer { fixture.cleanup() }

        try fixture.writeRemoteHubEnv()
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }
        let manifestJSON = try fixture.officialSkillManifestJSON()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        HubIPCClient.installResolvedSkillsOverrideForTesting { projectId in
            #expect(projectId == fixture.projectID)
            return HubIPCClient.ResolvedSkillsResult(
                ok: true,
                source: "hub_runtime_grpc",
                skills: [fixture.remoteResolvedSkillEntry()],
                reasonCode: nil
            )
        }
        HubIPCClient.installSkillManifestOverrideForTesting { packageSHA256 in
            #expect(packageSHA256 == fixture.packageSHA256)
            return HubIPCClient.SkillManifestResult(
                ok: true,
                source: "hub_runtime_grpc",
                packageSHA256: packageSHA256,
                manifestJSON: manifestJSON,
                reasonCode: nil
            )
        }
        defer {
            HubIPCClient.resetResolvedSkillsOverrideForTesting()
            HubIPCClient.resetSkillManifestOverrideForTesting()
        }

        let snapshot = try #require(
            await fixture.withAXHubStateDir {
                await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                    projectId: fixture.projectID,
                    projectName: fixture.projectName,
                    context: fixture.context,
                    hubBaseDir: fixture.hubBaseDir,
                    ttlMs: 120_000,
                    nowMs: nowMs,
                    force: true
                )
            }
        )

        #expect(snapshot.source == "hub_runtime_grpc_resolved_skills_snapshot+xt_builtin")
        #expect(snapshot.projectId == fixture.projectID)
        #expect(snapshot.items.contains(where: { $0.skillId == "summarize" }))
        let summarizeCache = try #require(snapshot.items.first(where: { $0.skillId == "summarize" }))
        #expect(summarizeCache.pinScope == "project")
        #expect(summarizeCache.governedDispatch?.tool == ToolName.summarize.rawValue)
        #expect(summarizeCache.capabilitiesRequired.contains("document.summarize"))
        #expect(summarizeCache.canonicalManifestSHA256.count == 64)

        let registry = try #require(
            AXSkillsLibrary.preferredSupervisorSkillRegistrySnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                projectRoot: fixture.projectRoot,
                hubBaseDir: fixture.hubBaseDir
            )
        )
        #expect(registry.memorySource == snapshot.source)
        let summarizeRegistry = try #require(registry.items.first(where: { $0.skillId == "summarize" }))
        #expect(summarizeRegistry.governedDispatch?.tool == ToolName.summarize.rawValue)
        #expect(summarizeRegistry.capabilitiesRequired.contains("document.summarize"))

        let routing = XTProjectSkillRouter.map(
            call: GovernedSkillCall(
                id: "remote-summarize-1",
                skill_id: "summarize",
                payload: ["text": .string("remote cache routing")]
            ),
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: fixture.projectRoot,
            config: .default(forProjectRoot: fixture.projectRoot),
            hubBaseDir: fixture.hubBaseDir
        )

        let mapped: XTProjectMappedSkillDispatch
        switch routing {
        case .success(let dispatch):
            mapped = dispatch
        case .failure(let failure):
            Issue.record("unexpected failure: \(failure.reasonCode)")
            throw failure
        }

        #expect(mapped.skillId == "summarize")
        #expect(mapped.toolCall.tool == .summarize)
        #expect(mapped.toolCall.args["text"]?.stringValue == "remote cache routing")

        let readiness = AXSkillsLibrary.skillExecutionReadiness(
            skillId: "summarize",
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: fixture.projectRoot,
            config: .default(forProjectRoot: fixture.projectRoot),
            hubBaseDir: fixture.hubBaseDir
        )
        #expect(readiness.packageSHA256 == fixture.packageSHA256)
        #expect(readiness.executionReadiness != XTSkillExecutionReadinessState.notInstalled.rawValue)
    }

    @Test
    func projectRouterMapsExpiredPersistedRemoteSnapshotWhenActiveCacheIsCold() async throws {
        let fixture = try RemoteSkillFixture(skillID: "summarize")
        defer { fixture.cleanup() }

        try fixture.writeRemoteHubEnv()
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }
        let manifestJSON = try fixture.officialSkillManifestJSON()

        HubIPCClient.installResolvedSkillsOverrideForTesting { projectId in
            #expect(projectId == fixture.projectID)
            return HubIPCClient.ResolvedSkillsResult(
                ok: true,
                source: "hub_runtime_grpc",
                skills: [fixture.remoteResolvedSkillEntry()],
                reasonCode: nil
            )
        }
        HubIPCClient.installSkillManifestOverrideForTesting { packageSHA256 in
            #expect(packageSHA256 == fixture.packageSHA256)
            return HubIPCClient.SkillManifestResult(
                ok: true,
                source: "hub_runtime_grpc",
                packageSHA256: packageSHA256,
                manifestJSON: manifestJSON,
                reasonCode: nil
            )
        }
        defer {
            HubIPCClient.resetResolvedSkillsOverrideForTesting()
            HubIPCClient.resetSkillManifestOverrideForTesting()
        }

        let expiredSnapshot = try #require(
            await fixture.withAXHubStateDir {
                await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                    projectId: fixture.projectID,
                    projectName: fixture.projectName,
                    context: fixture.context,
                    hubBaseDir: fixture.hubBaseDir,
                    ttlMs: 1,
                    nowMs: 1,
                    force: true
                )
            }
        )
        #expect(expiredSnapshot.items.contains(where: { $0.skillId == "summarize" }))
        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context) == nil)

        let routing = await fixture.withoutAXHubStateDir {
            XTProjectSkillRouter.map(
                call: GovernedSkillCall(
                    id: "project-router-cold-remote-1",
                    skill_id: "summarize",
                    payload: ["text": .string("expired persisted remote registry")]
                ),
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                projectRoot: fixture.projectRoot,
                config: .default(forProjectRoot: fixture.projectRoot),
                hubBaseDir: fixture.hubBaseDir
            )
        }

        let mapped: XTProjectMappedSkillDispatch
        switch routing {
        case .success(let dispatch):
            mapped = dispatch
        case .failure(let failure):
            Issue.record("unexpected failure: \(failure.reasonCode)")
            throw failure
        }

        #expect(mapped.skillId == "summarize")
        #expect(mapped.toolCall.tool == .summarize)
        #expect(mapped.toolCall.args["text"]?.stringValue == "expired persisted remote registry")
        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context) == nil)
    }

    @Test
    func localHubBaseDirOverrideSkipsImplicitRemoteResolvedSkillsRefreshWithoutExplicitStateDir() async throws {
        let fixture = try RemoteSkillFixture(skillID: "summarize")
        defer { fixture.cleanup() }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        let localPackageSHA256 = "8181818181818181818181818181818181818181818181818181818181818181"
        try fixture.writeLocalHubSkillsStore(
            skillID: "find-skills",
            displayName: "Find Skills",
            packageSHA256: localPackageSHA256,
            manifestJSON: #"""
            {
              "skill_id": "find-skills",
              "description": "Search the governed Hub skill catalog before proposing install, import, or enable flows.",
              "capabilities_required": ["skills.search"],
              "risk_level": "low",
              "requires_grant": false,
              "side_effect_class": "read_only",
              "governed_dispatch": {
                "tool": "skills_search",
                "fixed_args": {},
                "passthrough_args": ["query", "source_filter", "limit"],
                "arg_aliases": {
                  "source_filter": ["source"],
                  "limit": ["max_results"]
                },
                "required_any": [["query"]],
                "exactly_one_of": []
              }
            }
            """#
        )

        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let remoteOnlySHA256 = "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd"
        HubIPCClient.installResolvedSkillsOverrideForTesting { projectId in
            #expect(projectId == fixture.projectID)
            return HubIPCClient.ResolvedSkillsResult(
                ok: true,
                source: "hub_runtime_grpc",
                skills: [
                    fixture.remoteResolvedSkillEntry(
                        skillID: "remote-only-skill",
                        name: "Remote Only Skill",
                        description: "Should never leak into a local hub override snapshot.",
                        capabilitiesRequired: ["repo.read"],
                        packageSHA256: remoteOnlySHA256,
                        riskLevel: "low"
                    )
                ],
                reasonCode: nil
            )
        }
        HubIPCClient.installSkillManifestOverrideForTesting { packageSHA256 in
            #expect(packageSHA256 == remoteOnlySHA256)
            return HubIPCClient.SkillManifestResult(
                ok: true,
                source: "hub_runtime_grpc",
                packageSHA256: packageSHA256,
                manifestJSON: #"""
                {
                  "skill_id": "remote-only-skill",
                  "description": "Should never leak into a local hub override snapshot.",
                  "capabilities_required": ["repo.read"],
                  "risk_level": "low",
                  "requires_grant": false,
                  "side_effect_class": "read_only",
                  "governed_dispatch": {
                    "tool": "git_status",
                    "fixed_args": {},
                    "passthrough_args": [],
                    "arg_aliases": {},
                    "required_any": [],
                    "exactly_one_of": []
                  }
                }
                """#,
                reasonCode: nil
            )
        }
        defer {
            HubIPCClient.resetResolvedSkillsOverrideForTesting()
            HubIPCClient.resetSkillManifestOverrideForTesting()
        }

        let snapshot = try #require(
            await fixture.withoutAXHubStateDir {
                await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                    projectId: fixture.projectID,
                    projectName: fixture.projectName,
                    context: fixture.context,
                    hubBaseDir: fixture.hubBaseDir,
                    ttlMs: 120_000,
                    nowMs: nowMs,
                    force: true
                )
            }
        )

        #expect(snapshot.source == "hub_resolved_skills_snapshot+xt_builtin")
        #expect(snapshot.hubIndexUpdatedAtMs == 77)
        #expect(snapshot.items.contains(where: { $0.skillId == "find-skills" }))
        #expect(snapshot.items.contains(where: { $0.skillId == "remote-only-skill" }) == false)

        let registry = try #require(
            AXSkillsLibrary.preferredSupervisorSkillRegistrySnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                projectRoot: fixture.projectRoot,
                hubBaseDir: fixture.hubBaseDir
            )
        )
        #expect(registry.memorySource == snapshot.source)
        #expect(registry.items.contains(where: { $0.skillId == "find-skills" }))
        #expect(registry.items.contains(where: { $0.skillId == "remote-only-skill" }) == false)

        let readiness = AXSkillsLibrary.skillExecutionReadiness(
            skillId: "find-skills",
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: fixture.projectRoot,
            config: .default(forProjectRoot: fixture.projectRoot),
            hubBaseDir: fixture.hubBaseDir
        )
        #expect(readiness.executionReadiness == XTSkillExecutionReadinessState.ready.rawValue)
        #expect(readiness.packageSHA256 == localPackageSHA256)
    }

    @Test
    func skillsPinSuccessForProjectScopeForcesRemoteResolvedSkillsCacheRefresh() async throws {
        let fixture = try RemoteSkillFixture(skillID: "summarize")
        defer { fixture.cleanup() }

        try fixture.writeRemoteHubEnv()
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }
        let manifestJSON = try fixture.officialSkillManifestJSON()

        HubIPCClient.installSkillPinOverrideForTesting { request in
            #expect(request.scope == "project")
            #expect(request.skillId == "summarize")
            #expect(request.packageSHA256 == fixture.packageSHA256)
            #expect(request.projectId == fixture.projectID)
            return HubIPCClient.SkillPinResult(
                ok: true,
                source: "hub_runtime_grpc",
                scope: request.scope,
                userId: "user-remote",
                projectId: request.projectId ?? "",
                skillId: request.skillId,
                packageSHA256: request.packageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 9_999,
                reasonCode: nil
            )
        }
        HubIPCClient.installResolvedSkillsOverrideForTesting { projectId in
            #expect(projectId == fixture.projectID)
            return HubIPCClient.ResolvedSkillsResult(
                ok: true,
                source: "hub_runtime_grpc",
                skills: [fixture.remoteResolvedSkillEntry()],
                reasonCode: nil
            )
        }
        HubIPCClient.installSkillManifestOverrideForTesting { packageSHA256 in
            #expect(packageSHA256 == fixture.packageSHA256)
            return HubIPCClient.SkillManifestResult(
                ok: true,
                source: "hub_runtime_grpc",
                packageSHA256: packageSHA256,
                manifestJSON: manifestJSON,
                reasonCode: nil
            )
        }
        defer {
            HubIPCClient.resetSkillPinOverrideForTesting()
            HubIPCClient.resetResolvedSkillsOverrideForTesting()
            HubIPCClient.resetSkillManifestOverrideForTesting()
        }

        XTResolvedSkillsCacheStore.clear(for: fixture.context)
        #expect(XTResolvedSkillsCacheStore.load(for: fixture.context) == nil)

        let result = try await fixture.withAXHubStateDir {
            try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .skills_pin,
                    args: [
                        "skill_id": .string("summarize"),
                        "package_sha256": .string(fixture.packageSHA256),
                        "scope": .string("project"),
                    ]
                ),
                projectRoot: fixture.projectRoot
            )
        }

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["project_id"]) == fixture.projectID)
        #expect(jsonString(summary["skill_id"]) == "summarize")
        #expect(jsonString(summary["package_sha256"]) == fixture.packageSHA256)

        let active = try #require(
            XTResolvedSkillsCacheStore.activeSnapshot(
                for: fixture.context,
                nowMs: 10_000
            )
        )
        #expect(active.items.contains(where: { $0.skillId == "summarize" }))

        let registry = try #require(
            AXSkillsLibrary.preferredSupervisorSkillRegistrySnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                projectRoot: fixture.projectRoot,
                hubBaseDir: fixture.hubBaseDir
            )
        )
        #expect(registry.items.contains(where: { $0.skillId == "summarize" }))
    }

    @MainActor
    @Test
    func supervisorRetryRefreshesRemoteResolvedSkillsCacheWhenCacheWasCleared() async throws {
        actor ExecutionCapture {
            private var attempt = 0

            func run(_ call: ToolCall) -> ToolResult {
                attempt += 1
                if attempt == 1 {
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: false,
                        output: "remote summarize failed"
                    )
                }
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: "remote summarize retry completed"
                )
            }
        }

        let fixture = try RemoteSkillFixture(skillID: "summarize")
        defer { fixture.cleanup() }

        try fixture.writeRemoteHubEnv()
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }
        let manifestJSON = try fixture.officialSkillManifestJSON()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        HubIPCClient.installResolvedSkillsOverrideForTesting { projectId in
            #expect(projectId == fixture.projectID)
            return HubIPCClient.ResolvedSkillsResult(
                ok: true,
                source: "hub_runtime_grpc",
                skills: [fixture.remoteResolvedSkillEntry()],
                reasonCode: nil
            )
        }
        HubIPCClient.installSkillManifestOverrideForTesting { packageSHA256 in
            #expect(packageSHA256 == fixture.packageSHA256)
            return HubIPCClient.SkillManifestResult(
                ok: true,
                source: "hub_runtime_grpc",
                packageSHA256: packageSHA256,
                manifestJSON: manifestJSON,
                reasonCode: nil
            )
        }
        defer {
            HubIPCClient.resetResolvedSkillsOverrideForTesting()
            HubIPCClient.resetSkillManifestOverrideForTesting()
        }

        let snapshot = try #require(
            await fixture.withAXHubStateDir {
                await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                    projectId: fixture.projectID,
                    projectName: fixture.projectName,
                    context: fixture.context,
                    hubBaseDir: fixture.hubBaseDir,
                    ttlMs: 120_000,
                    nowMs: nowMs,
                    force: true
                )
            }
        )
        #expect(snapshot.items.contains(where: { $0.skillId == "summarize" }))

        let manager = SupervisorManager.makeForTesting()
        let capture = ExecutionCapture()
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .summarize)
            #expect(call.args["text"]?.stringValue == "retry remote governed summarize")
            return await capture.run(call)
        }

        let project = makeProjectEntry(root: fixture.projectRoot, displayName: fixture.projectName)
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"\#(fixture.projectName)","goal":"远端 summarize 重试","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"\#(fixture.projectName)","job_id":"\#(job.jobId)","plan_id":"plan-remote-summarize-retry-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"远端 summarize","kind":"call_skill","status":"pending","skill_id":"summarize"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"\#(fixture.projectName)","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"summarize","payload":{"text":"retry remote governed summarize"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 summarize 技能"
        )
        await manager.waitForSupervisorSkillDispatchForTesting()

        let original = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(original.status == .failed)

        XTResolvedSkillsCacheStore.clear(for: fixture.context)
        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context) == nil)

        manager.refreshRecentSupervisorSkillActivitiesNow()
        let activity = try #require(
            manager.recentSupervisorSkillActivities.first(where: { $0.requestId == original.requestId })
        )
        #expect(activity.tool == .summarize)
        #expect(activity.toolSummary.contains("retry remote governed summarize"))
        manager.retrySupervisorSkillActivity(activity)
        await manager.waitForSupervisorSkillDispatchForTesting()

        let calls = SupervisorProjectSkillCallStore.load(for: ctx).calls
        let latest = try #require(calls.max(by: { $0.createdAtMs < $1.createdAtMs }))
        #expect(latest.requestId != original.requestId)
        #expect(latest.status == .completed)
        #expect(latest.resultSummary.contains("remote summarize retry completed"))
        #expect(latest.denyCode.isEmpty)
    }

    @MainActor
    @Test
    func supervisorInitialRemoteSkillDispatchRefreshesExpiredPersistedRemoteSnapshot() async throws {
        let fixture = try RemoteSkillFixture(skillID: "summarize")
        defer { fixture.cleanup() }

        try fixture.writeRemoteHubEnv()
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }
        let manifestJSON = try fixture.officialSkillManifestJSON()

        HubIPCClient.installResolvedSkillsOverrideForTesting { projectId in
            #expect(projectId == fixture.projectID)
            return HubIPCClient.ResolvedSkillsResult(
                ok: true,
                source: "hub_runtime_grpc",
                skills: [fixture.remoteResolvedSkillEntry()],
                reasonCode: nil
            )
        }
        HubIPCClient.installSkillManifestOverrideForTesting { packageSHA256 in
            #expect(packageSHA256 == fixture.packageSHA256)
            return HubIPCClient.SkillManifestResult(
                ok: true,
                source: "hub_runtime_grpc",
                packageSHA256: packageSHA256,
                manifestJSON: manifestJSON,
                reasonCode: nil
            )
        }
        defer {
            HubIPCClient.resetResolvedSkillsOverrideForTesting()
            HubIPCClient.resetSkillManifestOverrideForTesting()
        }

        let expiredSnapshot = try #require(
            await fixture.withAXHubStateDir {
                await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                    projectId: fixture.projectID,
                    projectName: fixture.projectName,
                    context: fixture.context,
                    hubBaseDir: fixture.hubBaseDir,
                    ttlMs: 1,
                    nowMs: 1,
                    force: true
                )
            }
        )
        #expect(expiredSnapshot.items.contains(where: { $0.skillId == "summarize" }))
        let loaded = try #require(XTResolvedSkillsCacheStore.load(for: fixture.context))
        #expect(loaded.items.contains(where: { $0.skillId == "summarize" }))
        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context) == nil)

        let preferred = try #require(
            AXSkillsLibrary.preferredSupervisorSkillRegistrySnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                projectRoot: fixture.projectRoot,
                hubBaseDir: fixture.hubBaseDir
            )
        )
        #expect(preferred.items.contains(where: { $0.skillId == "summarize" }) == false)

        let manager = SupervisorManager.makeForTesting()
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .summarize)
            #expect(call.args["text"]?.stringValue == "cold remote skill bootstrap")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "remote summarize completed from expired persisted snapshot"
            )
        }

        let project = makeProjectEntry(root: fixture.projectRoot, displayName: fixture.projectName)
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"\#(fixture.projectName)","goal":"远端 summarize 冷缓存首调","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"\#(fixture.projectName)","job_id":"\#(job.jobId)","plan_id":"plan-remote-summarize-cold-start-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"远端 summarize","kind":"call_skill","status":"pending","skill_id":"summarize"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"\#(fixture.projectName)","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"summarize","payload":{"text":"cold remote skill bootstrap"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 summarize 技能"
        )
        await manager.waitForSupervisorSkillDispatchForTesting()

        let record = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(record.status == .completed)
        #expect(record.resultSummary.contains("remote summarize completed from expired persisted snapshot"))
        #expect(record.denyCode.isEmpty)

        let active = try #require(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context))
        #expect(active.items.contains(where: { $0.skillId == "summarize" }))
    }

    @MainActor
    @Test
    func projectSkillMappingRefreshesExpiredPersistedRemoteSnapshotWithoutEnv() async throws {
        let fixture = try RemoteSkillFixture(skillID: "summarize")
        defer { fixture.cleanup() }

        try fixture.writeRemoteHubEnv()
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }
        let manifestJSON = try fixture.officialSkillManifestJSON()

        HubIPCClient.installResolvedSkillsOverrideForTesting { projectId in
            #expect(projectId == fixture.projectID)
            return HubIPCClient.ResolvedSkillsResult(
                ok: true,
                source: "hub_runtime_grpc",
                skills: [fixture.remoteResolvedSkillEntry()],
                reasonCode: nil
            )
        }
        HubIPCClient.installSkillManifestOverrideForTesting { packageSHA256 in
            #expect(packageSHA256 == fixture.packageSHA256)
            return HubIPCClient.SkillManifestResult(
                ok: true,
                source: "hub_runtime_grpc",
                packageSHA256: packageSHA256,
                manifestJSON: manifestJSON,
                reasonCode: nil
            )
        }
        defer {
            HubIPCClient.resetResolvedSkillsOverrideForTesting()
            HubIPCClient.resetSkillManifestOverrideForTesting()
        }

        _ = try #require(
            await fixture.withAXHubStateDir {
                await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                    projectId: fixture.projectID,
                    projectName: fixture.projectName,
                    context: fixture.context,
                    hubBaseDir: fixture.hubBaseDir,
                    ttlMs: 1,
                    nowMs: 1,
                    force: true
                )
            }
        )
        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context) == nil)

        let session = ChatSessionModel()
        let mappedCalls = await fixture.withoutAXHubStateDir {
            await session.mappedProjectSkillToolCallsForTesting(
                skillCalls: [
                    GovernedSkillCall(
                        id: "project-ai-cold-remote-1",
                        skill_id: "summarize",
                        payload: ["text": .string("project ai refreshes expired remote snapshot")]
                    )
                ],
                ctx: fixture.context
            )
        }

        let toolCalls: [ToolCall]
        switch mappedCalls {
        case .success(let calls):
            toolCalls = calls
        case .failure(let error):
            Issue.record("unexpected mapping failure: \(error.message)")
            throw error
        }

        #expect(toolCalls.count == 1)
        #expect(toolCalls.first?.tool == .summarize)
        #expect(toolCalls.first?.args["text"]?.stringValue == "project ai refreshes expired remote snapshot")

        let active = try #require(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context))
        #expect(active.items.contains(where: { $0.skillId == "summarize" }))
    }

    @MainActor
    @Test
    func projectSkillReadinessRefreshesExpiredPersistedRemoteSnapshotWithoutEnv() async throws {
        let fixture = try RemoteSkillFixture(skillID: "summarize")
        defer { fixture.cleanup() }

        try fixture.writeRemoteHubEnv()
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }
        let manifestJSON = try fixture.officialSkillManifestJSON()

        HubIPCClient.installResolvedSkillsOverrideForTesting { projectId in
            #expect(projectId == fixture.projectID)
            return HubIPCClient.ResolvedSkillsResult(
                ok: true,
                source: "hub_runtime_grpc",
                skills: [fixture.remoteResolvedSkillEntry()],
                reasonCode: nil
            )
        }
        HubIPCClient.installSkillManifestOverrideForTesting { packageSHA256 in
            #expect(packageSHA256 == fixture.packageSHA256)
            return HubIPCClient.SkillManifestResult(
                ok: true,
                source: "hub_runtime_grpc",
                packageSHA256: packageSHA256,
                manifestJSON: manifestJSON,
                reasonCode: nil
            )
        }
        defer {
            HubIPCClient.resetResolvedSkillsOverrideForTesting()
            HubIPCClient.resetSkillManifestOverrideForTesting()
        }

        _ = try #require(
            await fixture.withAXHubStateDir {
                await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                    projectId: fixture.projectID,
                    projectName: fixture.projectName,
                    context: fixture.context,
                    hubBaseDir: fixture.hubBaseDir,
                    ttlMs: 1,
                    nowMs: 1,
                    force: true
                )
            }
        )
        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context) == nil)

        let session = ChatSessionModel()
        let readiness = await fixture.withoutAXHubStateDir {
            session.projectSkillExecutionReadinessForTesting(
                ctx: fixture.context,
                dispatch: XTProjectMappedSkillDispatch(
                    skillId: "summarize",
                    toolCall: ToolCall(
                        id: "project-readiness-cold-remote-1",
                        tool: .summarize,
                        args: ["text": .string("readiness refresh")]
                    ),
                    toolName: ToolName.summarize.rawValue
                ),
                config: .default(forProjectRoot: fixture.projectRoot)
            )
        }

        #expect(readiness?.packageSHA256 == fixture.packageSHA256)
        #expect(readiness?.executionReadiness == XTSkillExecutionReadinessState.ready.rawValue)

        let active = try #require(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context))
        #expect(active.items.contains(where: { $0.skillId == "summarize" }))
    }

    @MainActor
    @Test
    func projectSkillActivityRetryRefreshesRemoteResolvedSkillsCacheWhenCacheWasCleared() async throws {
        let fixture = try RemoteSkillFixture(skillID: "summarize")
        defer { fixture.cleanup() }

        try fixture.writeRemoteHubEnv()
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }
        let manifestJSON = try fixture.officialSkillManifestJSON()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        HubIPCClient.installResolvedSkillsOverrideForTesting { projectId in
            #expect(projectId == fixture.projectID)
            return HubIPCClient.ResolvedSkillsResult(
                ok: true,
                source: "hub_runtime_grpc",
                skills: [fixture.remoteResolvedSkillEntry()],
                reasonCode: nil
            )
        }
        HubIPCClient.installSkillManifestOverrideForTesting { packageSHA256 in
            #expect(packageSHA256 == fixture.packageSHA256)
            return HubIPCClient.SkillManifestResult(
                ok: true,
                source: "hub_runtime_grpc",
                packageSHA256: packageSHA256,
                manifestJSON: manifestJSON,
                reasonCode: nil
            )
        }
        defer {
            HubIPCClient.resetResolvedSkillsOverrideForTesting()
            HubIPCClient.resetSkillManifestOverrideForTesting()
        }

        let snapshot = try #require(
            await fixture.withAXHubStateDir {
                await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                    projectId: fixture.projectID,
                    projectName: fixture.projectName,
                    context: fixture.context,
                    hubBaseDir: fixture.hubBaseDir,
                    ttlMs: 120_000,
                    nowMs: nowMs,
                    force: true
                )
            }
        )
        #expect(snapshot.items.contains(where: { $0.skillId == "summarize" }))

        let requestID = "project-activity-remote-retry-1"
        let toolArgs: [String: JSONValue] = [
            "text": .string("project activity retry remote summarize")
        ]
        AXProjectStore.appendRawLog(
            [
                "type": "project_skill_call",
                "created_at": Date().timeIntervalSince1970,
                "status": "failed",
                "request_id": requestID,
                "skill_id": "summarize",
                "requested_skill_id": "summarize",
                "intent_families": ["summarize"],
                "capability_families": ["document.read", "document.summarize"],
                "capability_profiles": ["document.read", "document.summarize"],
                "tool_name": ToolName.summarize.rawValue,
                "tool_args": [
                    "text": "project activity retry remote summarize"
                ],
                "routing_reason_code": "intent_family_fallback",
                "routing_explanation": "根据 intent family summarize 路由到 summarize。",
                "hub_state_dir_path": fixture.stateDir.path,
                "grant_floor": XTSkillGrantFloor.none.rawValue,
                "approval_floor": XTSkillApprovalFloor.none.rawValue,
                "result_summary": "initial governed summarize failure"
            ],
            for: fixture.context
        )

        let reconstructed = try #require(
            AXProjectSkillActivityStore.dispatchesByRequestID(
                ctx: fixture.context,
                toolCalls: [
                    ToolCall(
                        id: requestID,
                        tool: .summarize,
                        args: toolArgs
                    )
                ]
            )[requestID]
        )
        #expect(reconstructed.requestedSkillId == "summarize")
        #expect(reconstructed.routingReasonCode == "intent_family_fallback")
        #expect(reconstructed.routingExplanation == "根据 intent family summarize 路由到 summarize。")
        #expect(reconstructed.grantFloor == XTSkillGrantFloor.none.rawValue)
        #expect(reconstructed.approvalFloor == XTSkillApprovalFloor.none.rawValue)
        #expect(reconstructed.hubStateDirPath == fixture.stateDir.path)

        let session = ChatSessionModel()
        session.ensureLoaded(ctx: fixture.context)
        let item = try #require(
            AXProjectSkillActivityStore.loadRecentActivities(
                ctx: fixture.context,
                limit: 4
            ).first(where: { $0.requestID == requestID })
        )

        XTResolvedSkillsCacheStore.clear(for: fixture.context)
        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context) == nil)

        let retryPrefix = "retry_\(requestID)_"
        try await fixture.withoutAXHubStateDir {
            session.retryProjectSkillActivity(
                item,
                router: LLMRouter(settingsStore: SettingsStore())
            )
            try await waitUntil(timeoutMs: 8_000) {
                session.isSending == false
            }
        }

        let active = try #require(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context))
        #expect(active.items.contains(where: { $0.skillId == "summarize" }))

        let recent = AXProjectSkillActivityStore.loadRecentActivities(ctx: fixture.context, limit: 12)
        let retried = try #require(
            recent.first(where: { $0.requestID.hasPrefix(retryPrefix) })
        )
        #expect(retried.status == "completed")
        #expect(retried.skillID == "summarize")
        #expect(retried.requestedSkillID == "summarize")
        #expect(retried.routingReasonCode == "intent_family_fallback")
        #expect(retried.hubStateDirPath == fixture.stateDir.path)
    }

    @MainActor
    @Test
    func projectPendingApprovalRestorePreheatsRemoteResolvedSkillsCacheAndApproveExecutesWhenCacheWasCleared() async throws {
        let fixture = try RemoteSkillFixture(skillID: "remote.process.start")
        defer { fixture.cleanup() }

        try fixture.writeRemoteHubEnv()
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }
        let manifestJSON = #"""
        {
          "skill_id": "remote.process.start",
          "description": "Governed remote process start wrapper for project pending approval restore tests.",
          "capabilities_required": ["process.manage", "process.autorestart"],
          "risk_level": "medium",
          "requires_grant": false,
          "side_effect_class": "local_side_effect",
          "governed_dispatch": {
            "tool": "process_start",
            "fixed_args": {},
            "passthrough_args": ["command", "name", "cwd"],
            "arg_aliases": {},
            "required_any": [["command"]],
            "exactly_one_of": []
          }
        }
        """#
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        HubIPCClient.installResolvedSkillsOverrideForTesting { projectId in
            #expect(projectId == fixture.projectID)
            return HubIPCClient.ResolvedSkillsResult(
                ok: true,
                source: "hub_runtime_grpc",
                skills: [
                    fixture.remoteResolvedSkillEntry(
                        skillID: "remote.process.start",
                        name: "Remote Process Start",
                        description: "Governed remote process start wrapper for project pending approval restore tests.",
                        capabilitiesRequired: ["process.manage", "process.autorestart"],
                        riskLevel: "medium"
                    )
                ],
                reasonCode: nil
            )
        }
        HubIPCClient.installSkillManifestOverrideForTesting { packageSHA256 in
            #expect(packageSHA256 == fixture.packageSHA256)
            return HubIPCClient.SkillManifestResult(
                ok: true,
                source: "hub_runtime_grpc",
                packageSHA256: packageSHA256,
                manifestJSON: manifestJSON,
                reasonCode: nil
            )
        }
        defer {
            HubIPCClient.resetResolvedSkillsOverrideForTesting()
            HubIPCClient.resetSkillManifestOverrideForTesting()
        }

        let snapshot = try #require(
            await fixture.withAXHubStateDir {
                await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                    projectId: fixture.projectID,
                    projectName: fixture.projectName,
                    context: fixture.context,
                    hubBaseDir: fixture.hubBaseDir,
                    ttlMs: 120_000,
                    nowMs: nowMs,
                    force: true
                )
            }
        )
        #expect(snapshot.items.contains(where: { $0.skillId == "remote.process.start" }))

        var config = try AXProjectStore.loadOrCreateConfig(for: fixture.context)
        config = config
            .settingProjectGovernance(executionTier: .a2RepoAuto)
            .settingToolPolicy(profile: ToolProfile.coding.rawValue)
            .settingGovernedAutoApproveLocalToolCalls(enabled: false)
        try AXProjectStore.saveConfig(config, for: fixture.context)

        let requestID = "project-pending-approval-remote-process-1"
        let toolCall = ToolCall(
            id: requestID,
            tool: .process_start,
            args: [
                "command": .string("printf 'project pending approval remote process\\n'"),
                "name": .string("project-pending-approval-remote-process")
            ]
        )
        AXProjectStore.appendRawLog(
            [
                "type": "project_skill_call",
                "created_at": Date().timeIntervalSince1970,
                "status": "awaiting_approval",
                "request_id": requestID,
                "skill_id": "remote.process.start",
                "requested_skill_id": "remote.process.start",
                "intent_families": ["process.manage"],
                "capability_families": ["process.manage", "process.autorestart"],
                "capability_profiles": ["process.manage", "process.autorestart"],
                "tool_name": ToolName.process_start.rawValue,
                "tool_args": [
                    "command": "printf 'project pending approval remote process\\n'",
                    "name": "project-pending-approval-remote-process"
                ],
                "routing_reason_code": "intent_family_fallback",
                "routing_explanation": "根据 intent family process.manage 路由到 remote.process.start。",
                "hub_state_dir_path": fixture.stateDir.path,
                "execution_readiness": XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
                "approval_summary": "当前可直接运行：无；本次请求：process.manage, process.autorestart；新增放开：process.manage, process.autorestart；grant=none；approval=local_approval",
                "current_runnable_profiles": [],
                "requested_profiles": ["process.manage", "process.autorestart"],
                "delta_profiles": ["process.manage", "process.autorestart"],
                "current_runnable_capability_families": [],
                "requested_capability_families": ["process.manage", "process.autorestart"],
                "delta_capability_families": ["process.manage", "process.autorestart"],
                "grant_floor": XTSkillGrantFloor.none.rawValue,
                "approval_floor": XTSkillApprovalFloor.localApproval.rawValue
            ],
            for: fixture.context
        )

        let seedSession = ChatSessionModel()
        seedSession.persistPendingToolApprovalForTesting(
            ctx: fixture.context,
            calls: [toolCall],
            reason: "awaiting_project_skill_local_approval",
            userText: "restore pending governed project skill approval"
        )
        ChatSessionModel.installToolExecutionOverrideForTesting { call, _ in
            guard call.id == requestID else { return nil }
            #expect(call.tool == .process_start)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "process_start completed: project-pending-approval-remote-process pid=123 cwd=."
            )
        }
        defer { ChatSessionModel.resetToolExecutionOverrideForTesting() }
        ChatSessionModel.installApprovedPendingToolFinalizeOverrideForTesting {
            "approved governed pending skill completed"
        }
        defer { ChatSessionModel.resetApprovedPendingToolFinalizeOverrideForTesting() }

        XTResolvedSkillsCacheStore.clear(for: fixture.context)
        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context) == nil)

        let restoredSession = ChatSessionModel()
        try await fixture.withoutAXHubStateDir {
            restoredSession.ensureLoaded(ctx: fixture.context)
            #expect(restoredSession.pendingToolCalls.count == 1)
            #expect(restoredSession.pendingToolCalls.first?.id == requestID)

            let pendingItem = try #require(
                restoredSession.pendingProjectSkillActivityItems()[requestID]
            )
            #expect(pendingItem.hubStateDirPath == fixture.stateDir.path)
            #expect(pendingItem.executionReadiness == XTSkillExecutionReadinessState.localApprovalRequired.rawValue)

            let preheated = try #require(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context))
            #expect(preheated.items.contains(where: { $0.skillId == "remote.process.start" }))

            restoredSession.approvePendingTool(
                requestID: requestID,
                router: LLMRouter(settingsStore: SettingsStore())
            )
            try await waitUntil(timeoutMs: 8_000) {
                let latestStatus = AXProjectSkillActivityStore.loadRecentActivities(
                    ctx: fixture.context,
                    limit: 12
                ).first(where: { $0.requestID == requestID })?.status
                return latestStatus == "completed" && restoredSession.isSending == false
            }
        }

        let active = try #require(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context))
        #expect(active.items.contains(where: { $0.skillId == "remote.process.start" }))

        let recent = AXProjectSkillActivityStore.loadRecentActivities(ctx: fixture.context, limit: 12)
        let completed = try #require(
            recent.first(where: { $0.requestID == requestID })
        )
        #expect(completed.status == "completed")
        #expect(completed.skillID == "remote.process.start")
        #expect(completed.hubStateDirPath == fixture.stateDir.path)
        #expect(completed.resultSummary.contains("process_start completed"))
    }

    @MainActor
    @Test
    func supervisorGrantResumeRefreshesRemoteResolvedSkillsCacheWhenCacheWasCleared() async throws {
        let fixture = try RemoteSkillFixture(skillID: "web.search")
        defer { fixture.cleanup() }

        try fixture.writeRemoteHubEnv()
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }
        let manifestJSON = #"""
        {
          "skill_id": "web.search",
          "description": "Governed remote web search wrapper for grant resume tests.",
          "capabilities_required": ["web.fetch"],
          "risk_level": "high",
          "requires_grant": true,
          "side_effect_class": "network",
          "governed_dispatch": {
            "tool": "web_search",
            "fixed_args": {},
            "passthrough_args": ["query", "max_results"],
            "arg_aliases": {
              "max_results": ["limit"]
            },
            "required_any": [["query"]],
            "exactly_one_of": []
          }
        }
        """#
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        HubIPCClient.installResolvedSkillsOverrideForTesting { projectId in
            #expect(projectId == fixture.projectID)
            return HubIPCClient.ResolvedSkillsResult(
                ok: true,
                source: "hub_runtime_grpc",
                skills: [
                    fixture.remoteResolvedSkillEntry(
                        skillID: "web.search",
                        name: "Remote Web Search",
                        description: "Governed remote web search wrapper for grant resume tests.",
                        capabilitiesRequired: ["web.fetch"],
                        riskLevel: "high"
                    )
                ],
                reasonCode: nil
            )
        }
        HubIPCClient.installSkillManifestOverrideForTesting { packageSHA256 in
            #expect(packageSHA256 == fixture.packageSHA256)
            return HubIPCClient.SkillManifestResult(
                ok: true,
                source: "hub_runtime_grpc",
                packageSHA256: packageSHA256,
                manifestJSON: manifestJSON,
                reasonCode: nil
            )
        }
        defer {
            HubIPCClient.resetResolvedSkillsOverrideForTesting()
            HubIPCClient.resetSkillManifestOverrideForTesting()
        }

        let snapshot = try #require(
            await fixture.withAXHubStateDir {
                await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                    projectId: fixture.projectID,
                    projectName: fixture.projectName,
                    context: fixture.context,
                    hubBaseDir: fixture.hubBaseDir,
                    ttlMs: 120_000,
                    nowMs: nowMs,
                    force: true
                )
            }
        )
        #expect(snapshot.items.contains(where: { $0.skillId == "web.search" }))

        let manager = SupervisorManager.makeForTesting(
            enableSupervisorHubGrantPreflight: true
        )
        manager.setSupervisorNetworkAccessRequestOverrideForTesting { _, _, _ in
            HubIPCClient.NetworkAccessResult(
                state: .queued,
                source: "test",
                reasonCode: "queued",
                remainingSeconds: nil,
                grantRequestId: "grant-web-search-remote-resume"
            )
        }
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .web_search)
            #expect(call.args["query"]?.stringValue == "browser runtime smoke fix")
            #expect(call.args["grant_id"]?.stringValue == "grant-live-remote-resume")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "remote web search resumed with approved grant"
            )
        }

        let project = makeProjectEntry(root: fixture.projectRoot, displayName: fixture.projectName)
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"\#(fixture.projectName)","goal":"远端 web search grant resume","priority":"high"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let ctx = try #require(appModel.projectContext(for: project.projectId))
        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"\#(fixture.projectName)","job_id":"\#(job.jobId)","plan_id":"plan-remote-web-search-grant-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"远端 web search","kind":"call_skill","status":"pending","skill_id":"web.search"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"\#(fixture.projectName)","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"web.search","payload":{"query":"browser runtime smoke fix","max_results":3}}[/CALL_SKILL]
            """#,
            userMessage: "请执行 web search 技能"
        )
        await manager.waitForSupervisorSkillDispatchForTesting()

        let pendingRecord = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(pendingRecord.status == .awaitingAuthorization)
        #expect(pendingRecord.grantRequestId == "grant-web-search-remote-resume")

        XTResolvedSkillsCacheStore.clear(for: fixture.context)
        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context) == nil)

        let pendingGrant = SupervisorManager.SupervisorPendingGrant(
            id: "grant:grant-web-search-remote-resume",
            dedupeKey: "grant:grant-web-search-remote-resume",
            grantRequestId: "grant-web-search-remote-resume",
            requestId: "request-web-search-remote-resume",
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
            nextAction: "批准后恢复远端 skill"
        )
        await manager.completePendingHubGrantActionForTesting(
            grant: pendingGrant,
            approve: true,
            result: HubIPCClient.PendingGrantActionResult(
                ok: true,
                decision: .approved,
                source: "test",
                grantRequestId: "grant-web-search-remote-resume",
                grantId: "grant-live-remote-resume",
                expiresAtMs: nil,
                reasonCode: nil
            )
        )
        await manager.waitForSupervisorSkillDispatchForTesting()

        let resumed = try #require(
            SupervisorProjectSkillCallStore.load(for: ctx).calls.first(where: { $0.requestId == pendingRecord.requestId })
        )
        #expect(resumed.status == .completed)
        #expect(resumed.resultSummary.contains("remote web search resumed with approved grant"))
        #expect(resumed.denyCode.isEmpty)
    }

    @MainActor
    @Test
    func supervisorLocalApprovalResumeRefreshesRemoteResolvedSkillsCacheWhenCacheWasCleared() async throws {
        let fixture = try RemoteSkillFixture(skillID: "remote.process.start")
        defer { fixture.cleanup() }

        try fixture.writeRemoteHubEnv()
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }
        let manifestJSON = #"""
        {
          "skill_id": "remote.process.start",
          "description": "Governed remote process start wrapper for local approval resume tests.",
          "capabilities_required": ["process.manage", "process.autorestart"],
          "risk_level": "medium",
          "requires_grant": false,
          "side_effect_class": "local_side_effect",
          "governed_dispatch": {
            "tool": "process_start",
            "fixed_args": {},
            "passthrough_args": ["command", "name", "cwd"],
            "arg_aliases": {},
            "required_any": [["command"]],
            "exactly_one_of": []
          }
        }
        """#
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        HubIPCClient.installResolvedSkillsOverrideForTesting { projectId in
            #expect(projectId == fixture.projectID)
            return HubIPCClient.ResolvedSkillsResult(
                ok: true,
                source: "hub_runtime_grpc",
                skills: [
                    fixture.remoteResolvedSkillEntry(
                        skillID: "remote.process.start",
                        name: "Remote Process Start",
                        description: "Governed remote process start wrapper for local approval resume tests.",
                        capabilitiesRequired: ["process.manage", "process.autorestart"],
                        riskLevel: "medium"
                    )
                ],
                reasonCode: nil
            )
        }
        HubIPCClient.installSkillManifestOverrideForTesting { packageSHA256 in
            #expect(packageSHA256 == fixture.packageSHA256)
            return HubIPCClient.SkillManifestResult(
                ok: true,
                source: "hub_runtime_grpc",
                packageSHA256: packageSHA256,
                manifestJSON: manifestJSON,
                reasonCode: nil
            )
        }
        defer {
            HubIPCClient.resetResolvedSkillsOverrideForTesting()
            HubIPCClient.resetSkillManifestOverrideForTesting()
        }

        let manager = SupervisorManager.makeForTesting()
        manager.setSupervisorToolExecutorOverrideForTesting { call, _ in
            #expect(call.tool == .process_start)
            #expect(call.args["command"]?.stringValue == "npm test")
            #expect(call.args["name"]?.stringValue == "remote-smoke")
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: "remote process start resumed after local approval"
            )
        }

        let project = makeProjectEntry(root: fixture.projectRoot, displayName: fixture.projectName)
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        let ctx = try #require(appModel.projectContext(for: project.projectId))
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingProjectGovernance(executionTier: .a2RepoAuto)
            .settingToolPolicy(profile: ToolProfile.coding.rawValue)
        try AXProjectStore.saveConfig(config, for: ctx)
        let snapshot = try #require(
            await fixture.withAXHubStateDir {
                await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                    projectId: fixture.projectID,
                    projectName: fixture.projectName,
                    context: fixture.context,
                    hubBaseDir: fixture.hubBaseDir,
                    ttlMs: 120_000,
                    nowMs: nowMs,
                    force: true
                )
            }
        )
        #expect(snapshot.items.contains(where: { $0.skillId == "remote.process.start" }))

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"\#(fixture.projectName)","goal":"远端 process start local approval resume","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"\#(fixture.projectName)","job_id":"\#(job.jobId)","plan_id":"plan-remote-process-start-local-approval-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"远端 process start","kind":"call_skill","status":"pending","skill_id":"remote.process.start"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"\#(fixture.projectName)","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"remote.process.start","payload":{"command":"npm test","name":"remote-smoke"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行远端 process start 技能"
        )
        await manager.waitForSupervisorSkillDispatchForTesting()

        manager.refreshPendingSupervisorSkillApprovalsNow()
        let pendingRecord = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        #expect(pendingRecord.status == .awaitingAuthorization)
        #expect(pendingRecord.requiredCapability == nil)
        #expect(
            pendingRecord.readiness?.executionReadiness
                == XTSkillExecutionReadinessState.localApprovalRequired.rawValue
        )

        XTResolvedSkillsCacheStore.clear(for: fixture.context)
        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: fixture.context) == nil)

        manager.refreshPendingSupervisorSkillApprovalsNow()
        let approval = try #require(
            manager.pendingSupervisorSkillApprovals.first(where: { $0.requestId == pendingRecord.requestId })
        )
        #expect(approval.tool == .process_start)
        let activity = try #require(
            manager.recentSupervisorSkillActivities.first(where: { $0.requestId == pendingRecord.requestId })
        )
        #expect(activity.tool == .process_start)
        #expect(activity.toolCall?.args["command"]?.stringValue == "npm test")
        #expect(activity.toolCall?.args["name"]?.stringValue == "remote-smoke")
        manager.approvePendingSupervisorSkillApproval(approval)
        await manager.waitForSupervisorSkillDispatchForTesting()

        let resumed = try #require(
            SupervisorProjectSkillCallStore.load(for: ctx).calls.first(where: { $0.requestId == pendingRecord.requestId })
        )
        #expect(resumed.status == .completed)
        #expect(resumed.resultSummary.contains("remote process start resumed after local approval"))
        #expect(resumed.denyCode.isEmpty)
    }

    @MainActor
    @Test
    func supervisorPendingApprovalDoesNotMisuseLocalApproveWhenReadinessRequiresGrant() async throws {
        let fixture = try RemoteSkillFixture(skillID: "remote.process.start")
        defer { fixture.cleanup() }

        try fixture.writeRemoteHubEnv()
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }
        let manifestJSON = #"""
        {
          "skill_id": "remote.process.start",
          "description": "Governed remote process start wrapper for grant gating tests.",
          "capabilities_required": ["process.manage", "process.autorestart"],
          "risk_level": "medium",
          "requires_grant": false,
          "side_effect_class": "local_side_effect",
          "governed_dispatch": {
            "tool": "process_start",
            "fixed_args": {},
            "passthrough_args": ["command", "name", "cwd"],
            "arg_aliases": {},
            "required_any": [["command"]],
            "exactly_one_of": []
          }
        }
        """#
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        HubIPCClient.installResolvedSkillsOverrideForTesting { projectId in
            #expect(projectId == fixture.projectID)
            return HubIPCClient.ResolvedSkillsResult(
                ok: true,
                source: "hub_runtime_grpc",
                skills: [
                    fixture.remoteResolvedSkillEntry(
                        skillID: "remote.process.start",
                        name: "Remote Process Start",
                        description: "Governed remote process start wrapper for grant gating tests.",
                        capabilitiesRequired: ["process.manage", "process.autorestart"],
                        riskLevel: "medium"
                    )
                ],
                reasonCode: nil
            )
        }
        HubIPCClient.installSkillManifestOverrideForTesting { packageSHA256 in
            #expect(packageSHA256 == fixture.packageSHA256)
            return HubIPCClient.SkillManifestResult(
                ok: true,
                source: "hub_runtime_grpc",
                packageSHA256: packageSHA256,
                manifestJSON: manifestJSON,
                reasonCode: nil
            )
        }
        defer {
            HubIPCClient.resetResolvedSkillsOverrideForTesting()
            HubIPCClient.resetSkillManifestOverrideForTesting()
        }

        final class DispatchFlag: @unchecked Sendable {
            var didRun = false
        }
        let dispatchFlag = DispatchFlag()

        let manager = SupervisorManager.makeForTesting()
        manager.setSupervisorToolExecutorOverrideForTesting { _, _ in
            dispatchFlag.didRun = true
            return ToolResult(
                id: UUID().uuidString,
                tool: .process_start,
                ok: true,
                output: "unexpected local resume"
            )
        }

        let project = makeProjectEntry(root: fixture.projectRoot, displayName: fixture.projectName)
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        let ctx = try #require(appModel.projectContext(for: project.projectId))
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingProjectGovernance(executionTier: .a2RepoAuto)
            .settingToolPolicy(profile: ToolProfile.coding.rawValue)
        try AXProjectStore.saveConfig(config, for: ctx)

        _ = try #require(
            await fixture.withAXHubStateDir {
                await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                    projectId: fixture.projectID,
                    projectName: fixture.projectName,
                    context: fixture.context,
                    hubBaseDir: fixture.hubBaseDir,
                    ttlMs: 120_000,
                    nowMs: nowMs,
                    force: true
                )
            }
        )

        _ = manager.processSupervisorResponseForTesting(
            #"[CREATE_JOB]{"project_ref":"\#(fixture.projectName)","goal":"grant-gated remote process start","priority":"normal"}[/CREATE_JOB]"#,
            userMessage: "请创建任务"
        )

        let job = try #require(SupervisorProjectJobStore.load(for: ctx).jobs.first)
        _ = manager.processSupervisorResponseForTesting(
            #"""
            [UPSERT_PLAN]{"project_ref":"\#(fixture.projectName)","job_id":"\#(job.jobId)","plan_id":"plan-remote-process-start-grant-v1","current_owner":"supervisor","steps":[{"step_id":"step-001","title":"远端 process start","kind":"call_skill","status":"pending","skill_id":"remote.process.start"}]}[/UPSERT_PLAN]
            """#,
            userMessage: "请更新计划"
        )

        _ = manager.processSupervisorResponseForTesting(
            #"""
            [CALL_SKILL]{"project_ref":"\#(fixture.projectName)","job_id":"\#(job.jobId)","step_id":"step-001","skill_id":"remote.process.start","payload":{"command":"npm test","name":"remote-smoke"}}[/CALL_SKILL]
            """#,
            userMessage: "请执行远端 process start 技能"
        )
        await manager.waitForSupervisorSkillDispatchForTesting()

        var pendingRecord = try #require(SupervisorProjectSkillCallStore.load(for: ctx).calls.first)
        var mutatedReadiness = try #require(pendingRecord.readiness)
        mutatedReadiness.executionReadiness = XTSkillExecutionReadinessState.grantRequired.rawValue
        mutatedReadiness.denyCode = "grant_required"
        mutatedReadiness.reasonCode = "grant floor privileged requires hub grant"
        mutatedReadiness.approvalFloor = XTSkillApprovalFloor.hubGrant.rawValue
        mutatedReadiness.requiredGrantCapabilities = ["process.manage"]
        mutatedReadiness.unblockActions = ["request_hub_grant"]
        mutatedReadiness.grantSnapshotRef = "grant-\(pendingRecord.requestId)"
        pendingRecord.readiness = mutatedReadiness
        pendingRecord.requiredCapability = nil
        try SupervisorProjectSkillCallStore.upsert(pendingRecord, for: ctx)

        manager.refreshPendingSupervisorSkillApprovalsNow()
        let approval = try #require(
            manager.pendingSupervisorSkillApprovals.first(where: { $0.requestId == pendingRecord.requestId })
        )

        manager.approvePendingSupervisorSkillApproval(approval)

        let persisted = try #require(
            SupervisorProjectSkillCallStore.load(for: ctx).calls.first(where: { $0.requestId == pendingRecord.requestId })
        )
        #expect(dispatchFlag.didRun == false)
        #expect(persisted.status == .awaitingAuthorization)
        #expect(
            persisted.readiness?.executionReadiness
                == XTSkillExecutionReadinessState.grantRequired.rawValue
        )
        #expect(manager.messages.contains(where: {
            $0.content.contains("当前正在等待 Hub 授权")
        }))
    }
}

private struct RemoteSkillFixture {
    let root: URL
    let hubBaseDir: URL
    let stateDir: URL
    let projectRoot: URL
    let context: AXProjectContext
    let projectID: String
    let projectName = "Remote Skill Project"
    let skillID: String
    let packageSHA256: String

    init(skillID: String) throws {
        self.skillID = skillID
        self.packageSHA256 = "abababababababababababababababababababababababababababababababab"
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-remote-skills-\(UUID().uuidString)", isDirectory: true)
        self.hubBaseDir = root.appendingPathComponent("hub", isDirectory: true)
        self.stateDir = root.appendingPathComponent("axhub", isDirectory: true)
        self.projectRoot = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: hubBaseDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        self.context = AXProjectContext(root: projectRoot)
        self.projectID = AXProjectRegistryStore.projectId(forRoot: projectRoot)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func writeRemoteHubEnv() throws {
        let hubEnv = """
        export HUB_CLIENT_TOKEN='token-remote-tests'
        export HUB_HOST='127.0.0.1'
        export HUB_PORT='50051'
        """
        try hubEnv.write(
            to: stateDir.appendingPathComponent("hub.env"),
            atomically: true,
            encoding: .utf8
        )
    }

    func withAXHubStateDir<T>(
        _ body: () async throws -> T
    ) async rethrows -> T {
        let key = "AXHUBCTL_STATE_DIR"
        let previous = getenv(key).flatMap { String(validatingUTF8: $0) }
        setenv(key, stateDir.path, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        return try await body()
    }

    func withoutAXHubStateDir<T>(
        _ body: () async throws -> T
    ) async rethrows -> T {
        let key = "AXHUBCTL_STATE_DIR"
        let previous = getenv(key).flatMap { String(validatingUTF8: $0) }
        unsetenv(key)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        return try await body()
    }

    func remoteResolvedSkillEntry(
        skillID: String? = nil,
        name: String = "Summarize",
        description: String = "Governed summarize wrapper for remote registry tests.",
        capabilitiesRequired: [String] = ["document.read", "document.summarize"],
        packageSHA256: String? = nil,
        riskLevel: String = "medium"
    ) -> HubIPCClient.ResolvedSkillEntry {
        HubIPCClient.ResolvedSkillEntry(
            scope: "project",
            skill: HubIPCClient.SkillCatalogEntry(
                skillID: skillID ?? self.skillID,
                name: name,
                version: "1.1.0",
                description: description,
                publisherID: "xhub.official",
                capabilitiesRequired: capabilitiesRequired,
                sourceID: "builtin:catalog",
                packageSHA256: packageSHA256 ?? self.packageSHA256,
                installHint: "Install from the default Agent Baseline.",
                riskLevel: riskLevel,
                requiresGrant: false,
                sideEffectClass: "read_only"
            )
        )
    }

    func writeLocalHubSkillsStore(
        skillID: String,
        displayName: String,
        packageSHA256: String,
        manifestJSON: String
    ) throws {
        let storeDir = hubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

        let index = #"""
        {
          "schema_version": "skills_store_index.v1",
          "updated_at_ms": 77,
          "skills": [
            {
              "skill_id": "\#(skillID)",
              "name": "\#(displayName)",
              "version": "1.1.0",
              "description": "Local Hub fixture skill for resolved cache boundary tests.",
              "publisher_id": "xhub.official",
              "source_id": "builtin:catalog",
              "package_sha256": "\#(packageSHA256)",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "efefefefefefefefefefefefefefefefefefefefefefefefefefefefefefefef",
              "install_hint": "",
              "manifest_json": \#(manifestJSON.debugDescription),
              "mapping_aliases_used": [],
              "defaults_applied": []
            }
          ]
        }
        """#
        try index.write(
            to: storeDir.appendingPathComponent("skills_store_index.json"),
            atomically: true,
            encoding: .utf8
        )

        let pins = #"""
        {
          "schema_version": "skills_pins.v1",
          "updated_at_ms": 77,
          "memory_core_pins": [],
          "global_pins": [],
          "project_pins": [
            {
              "project_id": "\#(projectID)",
              "skill_id": "\#(skillID)",
              "package_sha256": "\#(packageSHA256)"
            }
          ]
        }
        """#
        try pins.write(
            to: storeDir.appendingPathComponent("skills_pins.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    func officialSkillManifestJSON() throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDir.deletingLastPathComponent().deletingLastPathComponent()
        let manifestURL = repoRoot
            .appendingPathComponent("official-agent-skills", isDirectory: true)
            .appendingPathComponent(skillID, isDirectory: true)
            .appendingPathComponent("skill.json")
        return try String(contentsOf: manifestURL, encoding: .utf8)
    }
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

private func waitUntil(
    timeoutMs: UInt64,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    Issue.record("condition not met within \(timeoutMs) ms")
    throw CancellationError()
}
