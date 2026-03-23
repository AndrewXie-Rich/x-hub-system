import Foundation
import Testing
@testable import XTerminal

struct AXSkillsCompatibilityTests {

    @Test
    func supervisorSkillRegistryItemDecodesLegacySnapshotWithoutDispatchNotes() throws {
        let data = Data(
            #"""
            {
              "skill_id": "find-skills",
              "display_name": "Find Skills",
              "description": "Discover governed Agent skills.",
              "capabilities_required": ["skills.search"],
              "governed_dispatch": {
                "tool": "skills.search",
                "fixed_args": {},
                "passthrough_args": ["query"],
                "arg_aliases": {},
                "required_any": [["query"]],
                "exactly_one_of": []
              },
              "input_schema_ref": "schema://find-skills.input",
              "output_schema_ref": "schema://find-skills.output",
              "side_effect_class": "read_only",
              "risk_level": "low",
              "requires_grant": false,
              "policy_scope": "project",
              "timeout_ms": 10000,
              "max_retries": 1,
              "available": true
            }
            """#.utf8
        )

        let decoded = try JSONDecoder().decode(SupervisorSkillRegistryItem.self, from: data)

        #expect(decoded.skillId == "find-skills")
        #expect(decoded.governedDispatch?.tool == ToolName.skills_search.rawValue)
        #expect(decoded.governedDispatchVariants.isEmpty)
        #expect(decoded.governedDispatchNotes.isEmpty)
    }

    @Test
    func compatibilityDoctorSnapshotReadsHubStoreAndIndexes() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        try fixture.writeHubSkillsStore()
        try fixture.writeLocalIndexes()

        let snapshot = AXSkillsLibrary.compatibilityDoctorSnapshot(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            skillsDir: fixture.skillsDir,
            hubBaseDir: fixture.hubBaseDir
        )

        #expect(snapshot.hubIndexAvailable)
        #expect(snapshot.installedSkillCount == 2)
        #expect(snapshot.compatibleSkillCount == 2)
        #expect(snapshot.partialCompatibilityCount == 1)
        #expect(snapshot.revokedMatchCount == 1)
        #expect(snapshot.trustEnabledPublisherCount == 1)
        #expect(snapshot.projectIndexEntries.count == 1)
        #expect(snapshot.globalIndexEntries.count == 1)
        #expect(snapshot.statusKind == .blocked)
        #expect(snapshot.conflictWarnings.contains(where: { $0.contains("skill.demo") }))
        #expect(snapshot.compatibilityExplain.contains("compatible skill installed"))
        #expect(snapshot.officialChannelStatus == "healthy")
        #expect(snapshot.officialChannelMaintenanceEnabled)
        #expect(snapshot.officialChannelMaintenanceSourceKind == "persisted")
        #expect(snapshot.officialPackageLifecyclePackagesTotal == 2)
        #expect(snapshot.officialPackageLifecycleReadyTotal == 1)
        #expect(snapshot.officialPackageLifecycleBlockedTotal == 1)
        #expect(snapshot.officialPackageLifecycleActiveTotal == 1)
        #expect(snapshot.officialChannelSummaryLine.contains("pkg=2"))
        #expect(snapshot.officialChannelSummaryLine.contains("blocked=1"))
        #expect(snapshot.officialChannelDetailLine.contains("problem_skills=skill.secondary"))
        #expect(snapshot.officialChannelDetailLine.contains("Top blockers: Secondary Skill (skill.secondary) [blocked]"))
        #expect(snapshot.officialChannelTopBlockersLine == "Top blockers: Secondary Skill (skill.secondary) [blocked]")
        #expect(snapshot.officialPackageLifecycleTopBlockerSummaries.count == 1)
        #expect(snapshot.officialPackageLifecycleTopBlockerSummaries[0].title == "Secondary Skill")
        #expect(snapshot.officialPackageLifecycleTopBlockerSummaries[0].subtitle == "skill.secondary")
        #expect(snapshot.officialPackageLifecycleTopBlockerSummaries[0].stateLabel == "blocked")
        #expect(snapshot.officialPackageLifecycleTopBlockerSummaries[0].summaryLine.contains("version=2.0.0"))
        #expect(snapshot.officialPackageLifecycleTopBlockerSummaries[0].summaryLine.contains("risk=medium"))
        #expect(snapshot.officialPackageLifecycleTopBlockerSummaries[0].summaryLine.contains("grant=none"))
        #expect(snapshot.officialPackageLifecycleTopBlockerSummaries[0].timelineLine.contains("last_blocked="))
        #expect(snapshot.compatibilityExplain.contains("official_channel=official healthy"))

        let primary = snapshot.installedSkills.first { $0.skillID == "skill.demo" }
        #expect(primary != nil)
        #expect(primary?.compatibilityState == .partial)
        #expect(primary?.pinnedScopes.contains("global") == true)
        #expect(primary?.pinnedScopes.contains("project") == true)
    }

    @Test
    func compatibilityDoctorSnapshotFailsClosedWhenHubIndexMissing() {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        let snapshot = AXSkillsLibrary.compatibilityDoctorSnapshot(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            skillsDir: fixture.skillsDir,
            hubBaseDir: fixture.hubBaseDir
        )

        #expect(snapshot.hubIndexAvailable == false)
        #expect(snapshot.installedSkillCount == 0)
        #expect(snapshot.statusKind == .unavailable)
        #expect(snapshot.statusLine == "skills?")
        #expect(snapshot.builtinGovernedSkillCount > 0)
        #expect(snapshot.builtinSupervisorVoiceAvailable)
        #expect(snapshot.compatibilityExplain.contains("xt_builtin_supervisor_voice=available"))
    }

    @Test
    func compatibilityDoctorSnapshotRanksTopBlockersByActionabilityRiskAndFailures() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        try fixture.writeHubSkillsStore()
        try fixture.writeOfficialLifecycleSnapshot(
            """
            {
              "schema_version": "xhub.official_skill_package_lifecycle_snapshot.v1",
              "updated_at_ms": 9,
              "totals": {
                "packages_total": 4,
                "ready_total": 1,
                "degraded_total": 0,
                "blocked_total": 2,
                "not_installed_total": 0,
                "not_supported_total": 0,
                "revoked_total": 1,
                "active_total": 1
              },
              "packages": [
                {
                  "package_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                  "skill_id": "skill.demo",
                  "name": "Demo Skill",
                  "version": "1.0.0",
                  "risk_level": "low",
                  "requires_grant": false,
                  "package_state": "active",
                  "overall_state": "ready",
                  "blocking_failures": 0,
                  "transition_count": 1,
                  "updated_at_ms": 7,
                  "last_transition_at_ms": 7,
                  "last_ready_at_ms": 7,
                  "last_blocked_at_ms": 0
                },
                {
                  "package_sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                  "skill_id": "skill.secondary",
                  "name": "Secondary Skill",
                  "version": "2.0.0",
                  "risk_level": "medium",
                  "requires_grant": false,
                  "package_state": "discovered",
                  "overall_state": "blocked",
                  "blocking_failures": 1,
                  "transition_count": 2,
                  "updated_at_ms": 7,
                  "last_transition_at_ms": 7,
                  "last_ready_at_ms": 0,
                  "last_blocked_at_ms": 7
                },
                {
                  "package_sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                  "skill_id": "agent-browser",
                  "name": "Agent Browser",
                  "version": "3.0.0",
                  "risk_level": "high",
                  "requires_grant": true,
                  "package_state": "ready",
                  "overall_state": "blocked",
                  "blocking_failures": 2,
                  "transition_count": 5,
                  "updated_at_ms": 9,
                  "last_transition_at_ms": 9,
                  "last_ready_at_ms": 0,
                  "last_blocked_at_ms": 9
                },
                {
                  "package_sha256": "9999999999999999999999999999999999999999999999999999999999999999",
                  "skill_id": "calendar-sync",
                  "name": "Calendar Skill",
                  "version": "1.5.0",
                  "risk_level": "high",
                  "requires_grant": false,
                  "package_state": "revoked",
                  "overall_state": "blocked",
                  "blocking_failures": 1,
                  "transition_count": 4,
                  "updated_at_ms": 8,
                  "last_transition_at_ms": 8,
                  "last_ready_at_ms": 0,
                  "last_blocked_at_ms": 8
                }
              ]
            }
            """
        )

        let snapshot = AXSkillsLibrary.compatibilityDoctorSnapshot(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            skillsDir: fixture.skillsDir,
            hubBaseDir: fixture.hubBaseDir
        )

        #expect(snapshot.officialChannelDetailLine.contains("problem_skills=agent-browser,calendar-sync,skill.secondary"))
        #expect(snapshot.officialChannelTopBlockersLine == "Top blockers: Agent Browser (agent-browser) [blocked]; Calendar Skill (calendar-sync) [revoked]; Secondary Skill (skill.secondary) [blocked]")
        #expect(snapshot.officialPackageLifecycleTopBlockerSummaries.prefix(3).map(\.title) == [
            "Agent Browser",
            "Calendar Skill",
            "Secondary Skill"
        ])
        #expect(snapshot.officialPackageLifecycleTopBlockerSummaries.prefix(3).map(\.stateLabel) == [
            "blocked",
            "revoked",
            "blocked"
        ])
    }

    @Test
    func supervisorSkillRegistrySnapshotBuildsProjectScopedAvailableSkills() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        try fixture.writeHubSkillsStoreForSupervisorRegistry()

        let snapshot = try #require(
            AXSkillsLibrary.supervisorSkillRegistrySnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                hubBaseDir: fixture.hubBaseDir
            )
        )

        #expect(snapshot.schemaVersion == SupervisorSkillRegistrySnapshot.currentSchemaVersion)
        #expect(snapshot.projectId == fixture.projectID)
        #expect(snapshot.projectName == fixture.projectName)
        #expect(snapshot.updatedAtMs == 42)
        #expect(snapshot.memorySource == "hub_skill_registry+xt_builtin")
        #expect(snapshot.items.count == 16)
        #expect(!snapshot.items.contains(where: { $0.skillId == "email.send.auto" }))

        let git = try #require(snapshot.items.first(where: { $0.skillId == "repo.git.status" }))
        #expect(git.displayName == "Git Status")
        #expect(git.capabilitiesRequired == ["repo.read.status"])
        #expect(git.riskLevel == .low)
        #expect(git.requiresGrant == false)
        #expect(git.sideEffectClass == "read_only")
        #expect(git.policyScope == "global")
        #expect(git.timeoutMs == 15_000)
        #expect(git.maxRetries == 0)
        #expect(git.governedDispatch?.tool == ToolName.git_status.rawValue)

        let browser = try #require(snapshot.items.first(where: { $0.skillId == "browser.runtime.smoke" }))
        #expect(browser.capabilitiesRequired == ["web.navigate"])
        #expect(browser.riskLevel == .high)
        #expect(browser.requiresGrant)
        #expect(browser.sideEffectClass == "external_side_effect")
        #expect(browser.policyScope == "project")
        #expect(browser.timeoutMs == 45_000)
        #expect(browser.maxRetries == 2)
        #expect(browser.governedDispatch?.tool == ToolName.deviceBrowserControl.rawValue)

        let agentBrowser = try #require(snapshot.items.first(where: { $0.skillId == "agent-browser" }))
        #expect(agentBrowser.capabilitiesRequired == ["browser.read", "device.browser.control", "web.fetch"])
        #expect(agentBrowser.riskLevel == .high)
        #expect(agentBrowser.requiresGrant)
        #expect(agentBrowser.governedDispatch == nil)
        #expect(agentBrowser.governedDispatchVariants.count == 6)
        let readVariant = try #require(agentBrowser.governedDispatchVariants.first(where: { $0.actions.contains("read") }))
        #expect(readVariant.dispatch.tool == ToolName.browser_read.rawValue)
        #expect(readVariant.actionArg.isEmpty)
        #expect(agentBrowser.governedDispatchNotes.contains(where: { $0.contains("device.browser.control") }))
        #expect(agentBrowser.governedDispatchNotes.contains(where: { $0.contains("browser_read") }))

        let builtinDelete = try #require(snapshot.items.first(where: { $0.skillId == "repo.delete.path" }))
        #expect(builtinDelete.policyScope == "xt_builtin")
        #expect(builtinDelete.capabilitiesRequired == ["repo.delete_move"])
        #expect(builtinDelete.governedDispatch?.tool == ToolName.delete_path.rawValue)
        #expect(builtinDelete.riskLevel == .medium)

        let builtinProcessStart = try #require(snapshot.items.first(where: { $0.skillId == "process.start" }))
        #expect(builtinProcessStart.policyScope == "xt_builtin")
        #expect(builtinProcessStart.capabilitiesRequired == ["process.manage", "process.autorestart"])
        #expect(builtinProcessStart.governedDispatch?.tool == ToolName.process_start.rawValue)
        #expect(builtinProcessStart.governedDispatchNotes.contains(where: { $0.contains("restart_on_exit") }))

        let builtinVoice = try #require(snapshot.items.first(where: { $0.skillId == "supervisor-voice" }))
        #expect(builtinVoice.policyScope == "xt_builtin")
        #expect(builtinVoice.capabilitiesRequired == ["supervisor.voice.playback"])
        #expect(builtinVoice.governedDispatch?.tool == ToolName.supervisorVoicePlayback.rawValue)
        #expect(builtinVoice.sideEffectClass == "local_side_effect")
        #expect(builtinVoice.riskLevel == .low)
        #expect(!builtinVoice.requiresGrant)
        #expect(builtinVoice.governedDispatchNotes.contains(where: { $0.contains("text/content/value") }))

        let builtinGuardedAutomation = try #require(snapshot.items.first(where: { $0.skillId == "guarded-automation" }))
        #expect(builtinGuardedAutomation.policyScope == "xt_builtin")
        #expect(builtinGuardedAutomation.capabilitiesRequired == ["project.snapshot", "browser.read", "device.browser.control"])
        #expect(builtinGuardedAutomation.governedDispatch?.tool == ToolName.project_snapshot.rawValue)
        #expect(builtinGuardedAutomation.governedDispatchVariants.count == 7)
        #expect(builtinGuardedAutomation.riskLevel == .high)
        #expect(builtinGuardedAutomation.requiresGrant)
        #expect(builtinGuardedAutomation.sideEffectClass == "external_side_effect")
        let guardedOpenVariant = try #require(
            builtinGuardedAutomation.governedDispatchVariants.first(where: { $0.actions.contains("open") })
        )
        #expect(guardedOpenVariant.dispatch.tool == ToolName.deviceBrowserControl.rawValue)
        #expect(
            builtinGuardedAutomation.governedDispatchNotes.contains(where: {
                $0.localizedCaseInsensitiveContains("trusted automation")
            })
        )

        let builtinGitCommit = try #require(snapshot.items.first(where: { $0.skillId == "repo.git.commit" }))
        #expect(builtinGitCommit.policyScope == "xt_builtin")
        #expect(builtinGitCommit.capabilitiesRequired == ["git.commit"])
        #expect(builtinGitCommit.governedDispatch?.tool == ToolName.git_commit.rawValue)

        let builtinCITrigger = try #require(snapshot.items.first(where: { $0.skillId == "repo.ci.trigger" }))
        #expect(builtinCITrigger.policyScope == "xt_builtin")
        #expect(builtinCITrigger.capabilitiesRequired == ["ci.trigger"])
        #expect(builtinCITrigger.governedDispatch?.tool == ToolName.ci_trigger.rawValue)
        #expect(builtinCITrigger.governedDispatchNotes.contains(where: { $0.contains("provider=github") }))
    }

    @MainActor
    @Test
    func supervisorMemoryIncludesFocusedSkillRegistrySummary() async throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.writeHubSkillsStoreForSupervisorRegistry()

        let projectRoot = fixture.root.appendingPathComponent("project-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let project = AXProjectEntry(
            projectId: fixture.projectID,
            rootPath: projectRoot.path,
            displayName: fixture.projectName,
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
        appModel.registry = fixture.registry(with: [project])
        appModel.selectedProjectId = project.projectId

        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let manager = SupervisorManager.makeForTesting()
        manager.setAppModel(appModel)

        let memory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续执行当前项目")
        let registrySnapshot = await manager.supervisorSkillRegistrySnapshotForTesting("继续执行当前项目")
        let resolvedCache = XTResolvedSkillsCacheStore.activeSnapshot(
            for: AXProjectContext(root: projectRoot)
        )

        #expect(memory.contains("skills_registry:"))
        #expect(memory.contains("repo.git.status"))
        #expect(memory.contains("browser.runtime.smoke"))
        #expect(memory.contains("agent-browser"))
        #expect(memory.contains("grant=yes"))
        #expect(memory.contains("caps: repo.read.status"))
        #expect(memory.contains("caps: web.navigate"))
        #expect(memory.contains("guarded-automation"))
        #expect(memory.contains("supervisor-voice"))
        #expect(memory.contains("preferred_for: trusted_automation_readiness, governed_browser_actions"))
        #expect(memory.contains("preferred_for: supervisor_playback_status, preview, speak, stop"))
        #expect(memory.contains("dispatch=git_status"))
        #expect(memory.contains("dispatch=device.browser.control"))
        #expect(memory.contains("payload: fixed=action=open_url"))
        #expect(memory.contains("required_any=url"))
        #expect(memory.contains("args=url"))
        #expect(memory.contains("variant: actions=open/open_url/navigate/goto/visit -> device.browser.control"))
        #expect(memory.contains("variant: actions=snapshot/inspect/extract -> device.browser.control"))
        #expect(registrySnapshot?.items.count == 16)
        #expect(registrySnapshot?.items.contains(where: { $0.skillId == "supervisor-voice" }) == true)
        #expect(registrySnapshot?.items.contains(where: { $0.skillId == "guarded-automation" }) == true)
        #expect(resolvedCache?.items.count == 16)
        #expect(resolvedCache?.items.contains(where: { $0.skillId == "supervisor-voice" }) == true)
        #expect(resolvedCache?.items.contains(where: { $0.skillId == "guarded-automation" }) == true)
    }

    @Test
    func resolvedSkillsCacheSnapshotBuildsPinnedNonRevokedHubItems() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.writeHubSkillsStoreForSupervisorRegistry()

        let snapshot = try #require(
            AXSkillsLibrary.resolvedSkillsCacheSnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                hubBaseDir: fixture.hubBaseDir,
                ttlMs: 120_000,
                nowMs: 1_000
            )
        )

        #expect(snapshot.schemaVersion == XTResolvedSkillsCacheSnapshot.currentSchemaVersion)
        #expect(snapshot.projectId == fixture.projectID)
        #expect(snapshot.projectName == fixture.projectName)
        #expect(snapshot.source == "hub_resolved_skills_snapshot+xt_builtin")
        #expect(snapshot.resolvedSnapshotId == "xt-resolved-skills-12345678-1000")
        #expect(snapshot.resolvedAtMs == 1_000)
        #expect(snapshot.expiresAtMs == 121_000)
        #expect(snapshot.hubIndexUpdatedAtMs == 42)
        #expect(snapshot.auditRef == "audit-xt-w3-34-i-resolved-skills-12345678")
        #expect(snapshot.grantSnapshotRef == "grant-chain:12345678:refresh_required")
        #expect(snapshot.items.count == 16)
        #expect(!snapshot.items.contains(where: { $0.skillId == "email.send.auto" }))

        let repo = try #require(snapshot.items.first(where: { $0.skillId == "repo.git.status" }))
        #expect(repo.packageSHA256 == "1111111111111111111111111111111111111111111111111111111111111111")
        #expect(repo.canonicalManifestSHA256 == "2222222222222222222222222222222222222222222222222222222222222222")
        #expect(repo.pinScope == "global")
        #expect(repo.riskLevel == "low")
        #expect(repo.requiresGrant == false)
        #expect(repo.timeoutMs == 15_000)

        let browser = try #require(snapshot.items.first(where: { $0.skillId == "browser.runtime.smoke" }))
        #expect(browser.pinScope == "project")
        #expect(browser.riskLevel == "high")
        #expect(browser.requiresGrant)
        #expect(browser.maxRetries == 2)

        let agentBrowser = try #require(snapshot.items.first(where: { $0.skillId == "agent-browser" }))
        #expect(agentBrowser.pinScope == "project")
        #expect(agentBrowser.riskLevel == "high")
        #expect(agentBrowser.requiresGrant)

        let builtinProcessLogs = try #require(snapshot.items.first(where: { $0.skillId == "process.logs" }))
        #expect(builtinProcessLogs.pinScope == "xt_builtin")
        #expect(builtinProcessLogs.sourceId == "xt_builtin")
        #expect(builtinProcessLogs.riskLevel == "low")
        #expect(!builtinProcessLogs.requiresGrant)

        let builtinVoice = try #require(snapshot.items.first(where: { $0.skillId == "supervisor-voice" }))
        #expect(builtinVoice.pinScope == "xt_builtin")
        #expect(builtinVoice.sourceId == "xt_builtin")
        #expect(builtinVoice.riskLevel == "low")
        #expect(!builtinVoice.requiresGrant)
        #expect(builtinVoice.sideEffectClass == "local_side_effect")

        let builtinGuardedAutomation = try #require(snapshot.items.first(where: { $0.skillId == "guarded-automation" }))
        #expect(builtinGuardedAutomation.pinScope == "xt_builtin")
        #expect(builtinGuardedAutomation.sourceId == "xt_builtin")
        #expect(builtinGuardedAutomation.riskLevel == "high")
        #expect(builtinGuardedAutomation.requiresGrant)
        #expect(builtinGuardedAutomation.sideEffectClass == "external_side_effect")

        let builtinPR = try #require(snapshot.items.first(where: { $0.skillId == "repo.pr.create" }))
        #expect(builtinPR.pinScope == "xt_builtin")
        #expect(builtinPR.sourceId == "xt_builtin")
        #expect(builtinPR.riskLevel == "high")
        #expect(!builtinPR.requiresGrant)
    }

    @Test
    func projectSkillRouterMapsInstalledAgentBrowserVariantToToolCall() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.writeHubSkillsStoreForSupervisorRegistry()

        let snapshot = try #require(
            AXSkillsLibrary.supervisorSkillRegistrySnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                hubBaseDir: fixture.hubBaseDir
            )
        )

        let result = XTProjectSkillRouter.map(
            call: GovernedSkillCall(
                id: "skill-read-1",
                skill_id: "agent-browser",
                payload: [
                    "action": .string("read"),
                    "url": .string("https://example.com"),
                    "grant_id": .string("grant-123")
                ]
            ),
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            registrySnapshot: snapshot
        )

        let mapped: XTProjectMappedSkillDispatch
        switch result {
        case .success(let dispatch):
            mapped = dispatch
        case .failure(let failure):
            Issue.record("unexpected failure: \(failure.reasonCode)")
            throw failure
        }

        #expect(mapped.skillId == "agent-browser")
        #expect(mapped.toolCall.id == "skill-read-1")
        #expect(mapped.toolCall.tool == .browser_read)
        #expect(mapped.toolCall.args["url"]?.stringValue == "https://example.com")
        #expect(mapped.toolCall.args["grant_id"]?.stringValue == "grant-123")
    }

    @Test
    func projectSkillRouterMapsBuiltinProcessStartSkillToToolCall() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.writeHubSkillsStoreForSupervisorRegistry()

        let snapshot = try #require(
            AXSkillsLibrary.supervisorSkillRegistrySnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                hubBaseDir: fixture.hubBaseDir
            )
        )

        let result = XTProjectSkillRouter.map(
            call: GovernedSkillCall(
                id: "skill-process-1",
                skill_id: "process.start",
                payload: [
                    "id": .string("web"),
                    "name": .string("Web"),
                    "command": .string("npm run dev"),
                    "cwd": .string("frontend"),
                    "restart_on_exit": .bool(true),
                ]
            ),
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            registrySnapshot: snapshot
        )

        let mapped: XTProjectMappedSkillDispatch
        switch result {
        case .success(let dispatch):
            mapped = dispatch
        case .failure(let failure):
            Issue.record("unexpected failure: \(failure.reasonCode)")
            throw failure
        }

        #expect(mapped.skillId == "process.start")
        #expect(mapped.toolCall.tool == .process_start)
        #expect(mapped.toolCall.args["process_id"]?.stringValue == "web")
        #expect(mapped.toolCall.args["name"]?.stringValue == "Web")
        #expect(mapped.toolCall.args["command"]?.stringValue == "npm run dev")
        #expect(mapped.toolCall.args["cwd"]?.stringValue == "frontend")
        #expect(jsonBool(mapped.toolCall.args["restart_on_exit"]) == true)
    }

    @Test
    func projectSkillRouterMapsBuiltinGuardedAutomationVariantToToolCall() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.writeHubSkillsStoreForSupervisorRegistry()

        let snapshot = try #require(
            AXSkillsLibrary.supervisorSkillRegistrySnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                hubBaseDir: fixture.hubBaseDir
            )
        )

        let result = XTProjectSkillRouter.map(
            call: GovernedSkillCall(
                id: "skill-guarded-automation-1",
                skill_id: "guarded-automation",
                payload: [
                    "action": .string("open"),
                    "url": .string("https://example.com/dashboard"),
                    "grant_id": .string("grant-guarded-1"),
                ]
            ),
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            registrySnapshot: snapshot
        )

        let mapped: XTProjectMappedSkillDispatch
        switch result {
        case .success(let dispatch):
            mapped = dispatch
        case .failure(let failure):
            Issue.record("unexpected failure: \(failure.reasonCode)")
            throw failure
        }

        #expect(mapped.skillId == "guarded-automation")
        #expect(mapped.toolCall.tool == .deviceBrowserControl)
        #expect(mapped.toolCall.args["action"]?.stringValue == "open_url")
        #expect(mapped.toolCall.args["url"]?.stringValue == "https://example.com/dashboard")
        #expect(mapped.toolCall.args["grant_id"]?.stringValue == "grant-guarded-1")
    }

    @Test
    func projectSkillRouterCanonicalizesBuiltinGuardedAutomationAlias() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.writeHubSkillsStoreForSupervisorRegistry()

        let snapshot = try #require(
            AXSkillsLibrary.supervisorSkillRegistrySnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                hubBaseDir: fixture.hubBaseDir
            )
        )

        let result = XTProjectSkillRouter.map(
            call: GovernedSkillCall(
                id: "skill-guarded-automation-alias-1",
                skill_id: "trusted-automation",
                payload: [
                    "action": .string("open"),
                    "url": .string("https://example.com/alias"),
                    "grant_id": .string("grant-guarded-alias-1"),
                ]
            ),
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            registrySnapshot: snapshot
        )

        let mapped: XTProjectMappedSkillDispatch
        switch result {
        case .success(let dispatch):
            mapped = dispatch
        case .failure(let failure):
            Issue.record("unexpected failure: \(failure.reasonCode)")
            throw failure
        }

        #expect(AXSkillsLibrary.canonicalSupervisorSkillID("trusted-automation") == "guarded-automation")
        #expect(AXSkillsLibrary.canonicalSupervisorSkillID("supervisor.voice") == "supervisor-voice")
        #expect(mapped.skillId == "guarded-automation")
        #expect(mapped.toolCall.tool == .deviceBrowserControl)
        #expect(mapped.toolCall.args["action"]?.stringValue == "open_url")
        #expect(mapped.toolCall.args["url"]?.stringValue == "https://example.com/alias")
        #expect(mapped.toolCall.args["grant_id"]?.stringValue == "grant-guarded-alias-1")
    }

    @Test
    func projectSkillRouterFailsClosedForUnregisteredSkill() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.writeHubSkillsStoreForSupervisorRegistry()

        let snapshot = try #require(
            AXSkillsLibrary.supervisorSkillRegistrySnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                hubBaseDir: fixture.hubBaseDir
            )
        )

        let result = XTProjectSkillRouter.map(
            call: GovernedSkillCall(
                id: "skill-missing-1",
                skill_id: "skill-does-not-exist",
                payload: [:]
            ),
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            registrySnapshot: snapshot
        )

        switch result {
        case .success(let dispatch):
            Issue.record("unexpected dispatch: \(dispatch.toolName)")
        case .failure(let failure):
            #expect(failure.reasonCode == "skill_not_registered")
        }
    }

    @MainActor
    @Test
    func projectSkillRoutingPromptGuidanceMentionsInstalledSkillsAndSkillCalls() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.writeHubSkillsStoreForSupervisorRegistry()

        let snapshot = try #require(
            AXSkillsLibrary.supervisorSkillRegistrySnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                hubBaseDir: fixture.hubBaseDir
            )
        )
        let session = ChatSessionModel()
        let guidance = session.projectSkillRoutingPromptGuidanceForTesting(
            snapshot: snapshot
        )

        #expect(guidance.contains("prefer `skill_calls` over raw `tool_calls`"))
        #expect(guidance.contains("skills_registry:"))
        #expect(guidance.contains("routing, and payload hints to shape `payload` and choose a stable `skill_id`"))
        #expect(guidance.contains("Treat `routing: prefers_builtin=...` and `routing: entrypoints=...` as skill-family metadata."))
        #expect(guidance.contains("If the user explicitly names a registered wrapper or entrypoint skill_id, keep that exact registered `skill_id` in `skill_calls`"))
        #expect(guidance.contains("If the user asks only for a capability and the family advertises `routing: prefers_builtin=...`, choose the preferred builtin"))
        #expect(guidance.contains("repo.git.status"))
        #expect(guidance.contains("agent-browser"))
        #expect(guidance.contains("grant=yes"))
    }

    @MainActor
    @Test
    func projectSkillProgressLineMentionsSkillContext() throws {
        let session = ChatSessionModel()
        let line = session.projectSkillProgressLineForTesting(
            dispatch: XTProjectMappedSkillDispatch(
                skillId: "agent-browser",
                toolCall: ToolCall(
                    id: "skill-progress-1",
                    tool: .browser_read,
                    args: ["url": .string("https://example.com")]
                ),
                toolName: ToolName.browser_read.rawValue
            )
        )

        #expect(line.contains("agent-browser"))
        #expect(line.contains("读取网页内容"))
    }

    @MainActor
    @Test
    func projectToolLoopResponseRulesMentionRoutedSkillFamilies() {
        let session = ChatSessionModel()
        let rules = session.projectToolLoopResponseRulesForTesting()

        #expect(rules.contains("Prefer `skill_calls` when the work matches an installed governed skill in `skills_registry`."))
        #expect(rules.contains("Only use `skill_id` values that appear in the current project's `skills_registry` snapshot."))
        #expect(rules.contains("Treat `routing: prefers_builtin=...` and `routing: entrypoints=...` as skill-family metadata when choosing `skill_id`."))
        #expect(rules.contains("If the user explicitly names a registered wrapper or entrypoint skill, keep that exact registered `skill_id`"))
        #expect(rules.contains("If the user asks only for a capability and the family marks a preferred builtin, choose the preferred builtin"))
        #expect(rules.contains("Do not emit duplicate sibling `skill_calls` for one intent"))
    }

    @Test
    func resolvedSkillsCacheStorePersistsAndExpiresFailClosed() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.writeHubSkillsStoreForSupervisorRegistry()

        let projectRoot = fixture.root.appendingPathComponent("resolved-cache-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let context = AXProjectContext(root: projectRoot)

        let snapshot = try #require(
            XTResolvedSkillsCacheStore.refreshFromHub(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                context: context,
                hubBaseDir: fixture.hubBaseDir,
                ttlMs: 500,
                nowMs: 10_000
            )
        )

        #expect(FileManager.default.fileExists(atPath: context.resolvedSkillsCacheURL.path))
        #expect(snapshot.resolvedAtMs == 10_000)
        #expect(snapshot.expiresAtMs == 70_000)
        #expect(XTResolvedSkillsCacheStore.load(for: context)?.resolvedSnapshotId == snapshot.resolvedSnapshotId)
        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: context, nowMs: 10_001)?.resolvedSnapshotId == snapshot.resolvedSnapshotId)
        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: context, nowMs: 70_001) == nil)
    }

    @Test
    func resolvedSkillsCacheStoreDoesNotWriteWhenHubSnapshotUnavailable() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        let projectRoot = fixture.root.appendingPathComponent("resolved-cache-missing-hub", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let context = AXProjectContext(root: projectRoot)

        let snapshot = XTResolvedSkillsCacheStore.refreshFromHub(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            context: context,
            hubBaseDir: fixture.hubBaseDir,
            ttlMs: 120_000,
            nowMs: 2_000
        )

        #expect(snapshot == nil)
        #expect(XTResolvedSkillsCacheStore.load(for: context) == nil)
        #expect(FileManager.default.fileExists(atPath: context.resolvedSkillsCacheURL.path) == false)
    }

    @Test
    func compatibilityDoctorSnapshotFlagsMissingDefaultAgentBaseline() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.writeHubSkillsStoreForBaselineMissing()

        let snapshot = AXSkillsLibrary.compatibilityDoctorSnapshot(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            skillsDir: fixture.skillsDir,
            hubBaseDir: fixture.hubBaseDir
        )

        #expect(snapshot.hubIndexAvailable)
        #expect(snapshot.statusKind == .partial)
        #expect(snapshot.missingBaselineSkillIDs.count == 4)
        #expect(snapshot.missingBaselineSkillIDs.contains("find-skills"))
        #expect(snapshot.missingBaselineSkillIDs.contains("agent-browser"))
        #expect(snapshot.missingBaselineSkillIDs.contains("self-improving-agent"))
        #expect(snapshot.missingBaselineSkillIDs.contains("summarize"))
        #expect(snapshot.statusLine.contains("b0/4"))
        #expect(snapshot.compatibilityExplain.contains("baseline_missing=find-skills"))
    }

    @Test
    func compatibilityDoctorSnapshotReportsLocalDevPublisherCoverage() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.writeHubSkillsStoreForLocalDevBaseline()

        let snapshot = AXSkillsLibrary.compatibilityDoctorSnapshot(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            skillsDir: fixture.skillsDir,
            hubBaseDir: fixture.hubBaseDir
        )

        #expect(snapshot.statusKind == .supported)
        #expect(snapshot.localDevPublisherActive)
        #expect(snapshot.activePublisherIDs == ["xhub.local.dev"])
        #expect(snapshot.baselinePublisherIDs == ["xhub.local.dev"])
        #expect(snapshot.baselineLocalDevSkillCount == 4)
        #expect(snapshot.statusLine.contains("dev"))
        #expect(snapshot.compatibilityExplain.contains("active_publishers=xhub.local.dev"))
        #expect(snapshot.compatibilityExplain.contains("local_dev_publisher_active=yes"))
        #expect(snapshot.compatibilityExplain.contains("baseline_local_dev=4/4"))
        #expect(snapshot.compatibilityExplain.contains("baseline_publishers=xhub.local.dev"))
    }
}

private struct SkillsCompatibilityFixture {
    let root: URL
    let hubBaseDir: URL
    let skillsDir: URL
    let projectID = "project-alpha-12345678"
    let projectName = "Alpha Demo"

    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("xterminal-skills-compat-\(UUID().uuidString)", isDirectory: true)
        hubBaseDir = root.appendingPathComponent("hub", isDirectory: true)
        skillsDir = root.appendingPathComponent("skills", isDirectory: true)
        try? FileManager.default.createDirectory(at: hubBaseDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func writeOfficialLifecycleSnapshot(_ snapshot: String) throws {
        let storeDir = hubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        try snapshot.write(
            to: storeDir.appendingPathComponent("official_skill_package_lifecycle.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    func writeHubSkillsStore() throws {
        let storeDir = hubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

        let index = """
        {
          "schema_version": "skills_store_index.v1",
          "updated_at_ms": 1,
          "skills": [
            {
              "skill_id": "skill.demo",
              "name": "Demo Skill",
              "version": "1.0.0",
              "publisher_id": "publisher.demo",
              "source_id": "local:upload",
              "package_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "partial",
              "canonical_manifest_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
              "install_hint": "npm install",
              "mapping_aliases_used": ["skill_id<-id"],
              "defaults_applied": ["network_policy.direct_network_forbidden"]
            },
            {
              "skill_id": "skill.secondary",
              "name": "Secondary Skill",
              "version": "2.0.0",
              "publisher_id": "publisher.secondary",
              "source_id": "builtin:catalog",
              "package_sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
              "install_hint": "",
              "mapping_aliases_used": [],
              "defaults_applied": []
            }
          ]
        }
        """
        try index.write(to: storeDir.appendingPathComponent("skills_store_index.json"), atomically: true, encoding: .utf8)

        let pins = """
        {
          "schema_version": "skills_pins.v1",
          "updated_at_ms": 1,
          "memory_core_pins": [],
          "global_pins": [
            {
              "skill_id": "skill.demo",
              "package_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            }
          ],
          "project_pins": [
            {
              "project_id": "\(projectID)",
              "skill_id": "skill.demo",
              "package_sha256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
            }
          ]
        }
        """
        try pins.write(to: storeDir.appendingPathComponent("skills_pins.json"), atomically: true, encoding: .utf8)

        let trusted = """
        {
          "schema_version": "xhub.trusted_publishers.v1",
          "updated_at_ms": 1,
          "publishers": [
            { "publisher_id": "publisher.demo", "enabled": true },
            { "publisher_id": "publisher.disabled", "enabled": false }
          ]
        }
        """
        try trusted.write(to: storeDir.appendingPathComponent("trusted_publishers.json"), atomically: true, encoding: .utf8)

        let revocations = """
        {
          "schema_version": "xhub.skill_revocations.v1",
          "updated_at_ms": 1,
          "revoked_sha256": ["cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"],
          "revoked_skill_ids": [],
          "revoked_publishers": []
        }
        """
        try revocations.write(to: storeDir.appendingPathComponent("skill_revocations.json"), atomically: true, encoding: .utf8)

        let officialChannelDir = storeDir
            .appendingPathComponent("official_channels", isDirectory: true)
            .appendingPathComponent("official-stable", isDirectory: true)
        try FileManager.default.createDirectory(at: officialChannelDir, withIntermediateDirectories: true)

        let channelState = """
        {
          "schema_version": "xhub.official_skill_channel_state.v1",
          "channel_id": "official-stable",
          "status": "healthy",
          "updated_at_ms": 5,
          "last_success_at_ms": 4,
          "skill_count": 2,
          "error_code": ""
        }
        """
        try channelState.write(to: officialChannelDir.appendingPathComponent("channel_state.json"), atomically: true, encoding: .utf8)

        let maintenance = """
        {
          "schema_version": "xhub.official_skill_channel_maintenance_status.v1",
          "channel_id": "official-stable",
          "maintenance_enabled": true,
          "maintenance_interval_ms": 300000,
          "maintenance_last_run_at_ms": 6,
          "maintenance_source_kind": "persisted",
          "last_transition_at_ms": 6,
          "last_transition_kind": "current_snapshot_repaired",
          "last_transition_summary": "current snapshot restored via persisted"
        }
        """
        try maintenance.write(to: officialChannelDir.appendingPathComponent("maintenance_status.json"), atomically: true, encoding: .utf8)

        let lifecycle = """
        {
          "schema_version": "xhub.official_skill_package_lifecycle_snapshot.v1",
          "updated_at_ms": 7,
          "totals": {
            "packages_total": 2,
            "ready_total": 1,
            "degraded_total": 0,
            "blocked_total": 1,
            "not_installed_total": 0,
            "not_supported_total": 0,
            "revoked_total": 0,
            "active_total": 1
          },
          "packages": [
            {
              "package_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              "skill_id": "skill.demo",
              "name": "Demo Skill",
              "version": "1.0.0",
              "risk_level": "low",
              "requires_grant": false,
              "package_state": "active",
              "overall_state": "ready",
              "blocking_failures": 0,
              "transition_count": 1,
              "updated_at_ms": 7,
              "last_transition_at_ms": 7,
              "last_ready_at_ms": 7,
              "last_blocked_at_ms": 0
            },
            {
              "package_sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
              "skill_id": "skill.secondary",
              "name": "Secondary Skill",
              "version": "2.0.0",
              "risk_level": "medium",
              "requires_grant": false,
              "package_state": "discovered",
              "overall_state": "blocked",
              "blocking_failures": 1,
              "transition_count": 2,
              "updated_at_ms": 7,
              "last_transition_at_ms": 7,
              "last_ready_at_ms": 0,
              "last_blocked_at_ms": 7
            }
          ]
        }
        """
        try lifecycle.write(to: storeDir.appendingPathComponent("official_skill_package_lifecycle.json"), atomically: true, encoding: .utf8)
    }

    func writeLocalIndexes() throws {
        let globalIndexDir = skillsDir.appendingPathComponent("memory-core/references", isDirectory: true)
        try FileManager.default.createDirectory(at: globalIndexDir, withIntermediateDirectories: true)
        try "# Skills Index (auto)\n\n- Demo Skill — 全局可用（路径：<skills_dir>/_global/demo-skill）\n"
            .write(to: globalIndexDir.appendingPathComponent("skills-index.md"), atomically: true, encoding: .utf8)

        let projectDir = try #require(
            AXSkillsLibrary.projectSkillsDir(
                projectId: projectID,
                projectName: projectName,
                skillsDir: skillsDir
            )
        )
        try "# Skills Index (project)\n\n- Demo Skill — 项目绑定（路径：<skills_dir>/_projects/\(projectName)-12345678/demo-skill）\n"
            .write(to: projectDir.appendingPathComponent("skills-index.md"), atomically: true, encoding: .utf8)
    }

    func writeHubSkillsStoreForSupervisorRegistry() throws {
        let storeDir = hubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

        let index = #"""
        {
          "schema_version": "skills_store_index.v1",
          "updated_at_ms": 42,
          "skills": [
            {
              "skill_id": "repo.git.status",
              "name": "Git Status",
              "version": "1.0.0",
              "description": "Read git working tree status for the active project.",
              "publisher_id": "publisher.repo",
              "source_id": "builtin:catalog",
              "package_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Read git working tree status for the active project.\",\"capabilities_required\":[\"repo.read.status\"],\"governed_dispatch\":{\"tool\":\"git_status\"},\"risk_level\":\"low\",\"input_schema_ref\":\"schema://repo.git.status.input\",\"output_schema_ref\":\"schema://repo.git.status.output\",\"timeout_ms\":15000,\"max_retries\":0}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "browser.runtime.smoke",
              "name": "Browser Runtime Smoke",
              "version": "2.1.0",
              "description": "Open the governed browser runtime and capture smoke evidence.",
              "publisher_id": "publisher.browser",
              "source_id": "builtin:catalog",
              "package_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "4444444444444444444444444444444444444444444444444444444444444444",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Open the governed browser runtime and capture smoke evidence.\",\"capabilities_required\":[\"web.navigate\"],\"governed_dispatch\":{\"tool\":\"device.browser.control\",\"fixed_args\":{\"action\":\"open_url\"},\"passthrough_args\":[\"url\"],\"required_any\":[[\"url\"]]},\"risk_level\":\"high\",\"input_schema_ref\":\"schema://browser.runtime.smoke.input\",\"output_schema_ref\":\"schema://browser.runtime.smoke.output\",\"timeout_ms\":45000,\"max_retries\":2}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "agent-browser",
              "name": "Agent Browser",
              "version": "1.0.0",
              "description": "Governed browser automation package.",
              "publisher_id": "publisher.browser",
              "source_id": "builtin:catalog",
              "package_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Governed browser automation package.\",\"capabilities_required\":[\"browser.read\",\"device.browser.control\",\"web.fetch\"],\"risk_level\":\"high\",\"requires_grant\":true,\"side_effect_class\":\"external_side_effect\",\"timeout_ms\":45000,\"max_retries\":2}",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "email.send.auto",
              "name": "Auto Email",
              "version": "3.0.0",
              "description": "Send email automatically.",
              "publisher_id": "publisher.mail",
              "source_id": "builtin:catalog",
              "package_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "6666666666666666666666666666666666666666666666666666666666666666",
              "install_hint": "",
              "manifest_json": "{\"description\":\"Send email automatically.\",\"capabilities_required\":[\"connectors.email.send\"],\"risk_level\":\"high\"}",
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
          "updated_at_ms": 42,
          "memory_core_pins": [],
          "global_pins": [
            {
              "skill_id": "repo.git.status",
              "package_sha256": "1111111111111111111111111111111111111111111111111111111111111111"
            },
            {
              "skill_id": "email.send.auto",
              "package_sha256": "5555555555555555555555555555555555555555555555555555555555555555"
            }
          ],
          "project_pins": [
            {
              "project_id": "\(projectID)",
              "skill_id": "browser.runtime.smoke",
              "package_sha256": "3333333333333333333333333333333333333333333333333333333333333333"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "agent-browser",
              "package_sha256": "7777777777777777777777777777777777777777777777777777777777777777"
            }
          ]
        }
        """
        try pins.write(to: storeDir.appendingPathComponent("skills_pins.json"), atomically: true, encoding: .utf8)

        let revocations = """
        {
          "schema_version": "xhub.skill_revocations.v1",
          "updated_at_ms": 42,
          "revoked_sha256": ["5555555555555555555555555555555555555555555555555555555555555555"],
          "revoked_skill_ids": [],
          "revoked_publishers": []
        }
        """
        try revocations.write(to: storeDir.appendingPathComponent("skill_revocations.json"), atomically: true, encoding: .utf8)
    }

    func writeHubSkillsStoreForBaselineMissing() throws {
        let storeDir = hubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

        let index = """
        {
          "schema_version": "skills_store_index.v1",
          "updated_at_ms": 7,
          "skills": [
            {
              "skill_id": "repo.git.status",
              "name": "Git Status",
              "version": "1.0.0",
              "description": "Read git working tree status for the active project.",
              "publisher_id": "publisher.repo",
              "source_id": "builtin:catalog",
              "package_sha256": "7777777777777777777777777777777777777777777777777777777777777777",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "8888888888888888888888888888888888888888888888888888888888888888",
              "install_hint": "",
              "mapping_aliases_used": [],
              "defaults_applied": []
            }
          ]
        }
        """
        try index.write(to: storeDir.appendingPathComponent("skills_store_index.json"), atomically: true, encoding: .utf8)

        let pins = """
        {
          "schema_version": "skills_pins.v1",
          "updated_at_ms": 7,
          "memory_core_pins": [],
          "global_pins": [
            {
              "skill_id": "repo.git.status",
              "package_sha256": "7777777777777777777777777777777777777777777777777777777777777777"
            }
          ],
          "project_pins": []
        }
        """
        try pins.write(to: storeDir.appendingPathComponent("skills_pins.json"), atomically: true, encoding: .utf8)

        let trusted = """
        {
          "schema_version": "xhub.trusted_publishers.v1",
          "updated_at_ms": 7,
          "publishers": [
            { "publisher_id": "publisher.repo", "enabled": true }
          ]
        }
        """
        try trusted.write(to: storeDir.appendingPathComponent("trusted_publishers.json"), atomically: true, encoding: .utf8)

        let revocations = """
        {
          "schema_version": "xhub.skill_revocations.v1",
          "updated_at_ms": 7,
          "revoked_sha256": [],
          "revoked_skill_ids": [],
          "revoked_publishers": []
        }
        """
        try revocations.write(to: storeDir.appendingPathComponent("skill_revocations.json"), atomically: true, encoding: .utf8)
    }

    func writeHubSkillsStoreForLocalDevBaseline() throws {
        let storeDir = hubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

        let index = """
        {
          "schema_version": "skills_store_index.v1",
          "updated_at_ms": 9,
          "skills": [
            {
              "skill_id": "find-skills",
              "name": "Find Skills",
              "version": "1.1.0",
              "description": "Discover governed skills.",
              "publisher_id": "xhub.local.dev",
              "source_id": "builtin:catalog",
              "package_sha256": "9000000000000000000000000000000000000000000000000000000000000001",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "9100000000000000000000000000000000000000000000000000000000000001",
              "install_hint": "",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "agent-browser",
              "name": "Agent Browser",
              "version": "1.0.0",
              "description": "Governed browser automation.",
              "publisher_id": "xhub.local.dev",
              "source_id": "builtin:catalog",
              "package_sha256": "9000000000000000000000000000000000000000000000000000000000000002",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "9100000000000000000000000000000000000000000000000000000000000002",
              "install_hint": "",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "self-improving-agent",
              "name": "Self Improving Agent",
              "version": "1.0.0",
              "description": "Supervisor retrospective pack.",
              "publisher_id": "xhub.local.dev",
              "source_id": "builtin:catalog",
              "package_sha256": "9000000000000000000000000000000000000000000000000000000000000003",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "9100000000000000000000000000000000000000000000000000000000000003",
              "install_hint": "",
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "summarize",
              "name": "Summarize",
              "version": "1.1.0",
              "description": "Governed summarize wrapper.",
              "publisher_id": "xhub.local.dev",
              "source_id": "builtin:catalog",
              "package_sha256": "9000000000000000000000000000000000000000000000000000000000000004",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "9100000000000000000000000000000000000000000000000000000000000004",
              "install_hint": "",
              "mapping_aliases_used": [],
              "defaults_applied": []
            }
          ]
        }
        """
        try index.write(to: storeDir.appendingPathComponent("skills_store_index.json"), atomically: true, encoding: .utf8)

        let pins = """
        {
          "schema_version": "skills_pins.v1",
          "updated_at_ms": 9,
          "memory_core_pins": [],
          "global_pins": [],
          "project_pins": [
            {
              "project_id": "\(projectID)",
              "skill_id": "find-skills",
              "package_sha256": "9000000000000000000000000000000000000000000000000000000000000001"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "agent-browser",
              "package_sha256": "9000000000000000000000000000000000000000000000000000000000000002"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "self-improving-agent",
              "package_sha256": "9000000000000000000000000000000000000000000000000000000000000003"
            },
            {
              "project_id": "\(projectID)",
              "skill_id": "summarize",
              "package_sha256": "9000000000000000000000000000000000000000000000000000000000000004"
            }
          ]
        }
        """
        try pins.write(to: storeDir.appendingPathComponent("skills_pins.json"), atomically: true, encoding: .utf8)

        let trusted = """
        {
          "schema_version": "xhub.trusted_publishers.v1",
          "updated_at_ms": 9,
          "publishers": [
            { "publisher_id": "xhub.local.dev", "enabled": true }
          ]
        }
        """
        try trusted.write(to: storeDir.appendingPathComponent("trusted_publishers.json"), atomically: true, encoding: .utf8)

        let revocations = """
        {
          "schema_version": "xhub.skill_revocations.v1",
          "updated_at_ms": 9,
          "revoked_sha256": [],
          "revoked_skill_ids": [],
          "revoked_publishers": []
        }
        """
        try revocations.write(to: storeDir.appendingPathComponent("skill_revocations.json"), atomically: true, encoding: .utf8)
    }

    func registry(with projects: [AXProjectEntry]) -> AXProjectRegistry {
        AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projects.first?.projectId,
            projects: projects
        )
    }

    func makeProjectEntry(root: URL, displayName: String) -> AXProjectEntry {
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
}
