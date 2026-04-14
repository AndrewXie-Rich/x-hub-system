import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
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
    func governanceSurfaceEntriesExposeTrustPinRunnerCompatibilityAndPreflight() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        try fixture.writeHubSkillsStoreForGovernanceSurface()

        let snapshot = AXSkillsLibrary.compatibilityDoctorSnapshot(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            skillsDir: fixture.skillsDir,
            hubBaseDir: fixture.hubBaseDir
        )

        let items = snapshot.governanceSurfaceEntries
        #expect(items.count == 3)

        let supported = try #require(items.first(where: { $0.skillID == "find-skills" }))
        #expect(supported.trustRootValue.contains("official trust root"))
        #expect(supported.pinnedVersionValue.contains("pinned=global"))
        #expect(supported.runnerRequirementValue.contains("runtime=text"))
        #expect(supported.compatibilityStatusValue.contains("supported | verified"))
        #expect(supported.preflightResultValue == "passed")

        let partial = try #require(items.first(where: { $0.skillID == "skill.demo" }))
        #expect(partial.compatibilityStatusValue.contains("partial"))
        #expect(partial.preflightResultValue.contains("quarantined"))
        #expect(partial.note.contains("aliases=skill_id<-id"))
        #expect(partial.note.contains("quality doctor=passed smoke=missing"))

        let grantRequired = try #require(items.first(where: { $0.skillID == "agent-browser" }))
        #expect(grantRequired.preflightResultValue.contains("grant required before run"))
        #expect(grantRequired.trustRootValue.contains("official trust root"))
        #expect(grantRequired.runnerRequirementValue.contains("cmd=cat SKILL.md"))
    }

    @Test
    func projectAwareGovernanceSurfaceEntriesExposeFourStateReadinessAndUnblockActions() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        try fixture.writeHubSkillsStoreForGovernanceSurface()

        let snapshot = AXSkillsLibrary.compatibilityDoctorSnapshot(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            skillsDir: fixture.skillsDir,
            hubBaseDir: fixture.hubBaseDir
        )

        let projectRoot = fixture.root.appendingPathComponent("governance-surface-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let config = AXProjectConfig.default(forProjectRoot: projectRoot)
            .settingToolPolicy(profile: ToolProfile.full.rawValue)
            .settingProjectGovernance(executionTier: .a4OpenClaw)

        let items = snapshot.governanceSurfaceEntries(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: projectRoot,
            config: config,
            hubBaseDir: fixture.hubBaseDir
        )

        let ready = try #require(items.first(where: { $0.skillID == "find-skills" }))
        #expect(ready.discoverabilityState == "discoverable")
        #expect(ready.installabilityState == "installable")
        #expect(ready.requestabilityState == "requestable")
        #expect(ready.executionReadiness == XTSkillExecutionReadinessState.ready.rawValue)
        #expect(ready.whyNotRunnable.isEmpty)

        let installableOnly = try #require(items.first(where: { $0.skillID == "agent-browser" }))
        #expect(installableOnly.installabilityState == "installable")
        #expect(installableOnly.requestabilityState == "installable_only")
        #expect(installableOnly.executionReadiness == XTSkillExecutionReadinessState.notInstalled.rawValue)
        #expect(installableOnly.whyNotRunnable.contains("not resolved"))
        #expect(installableOnly.unblockActions.contains("install_baseline"))

        let quarantined = try #require(items.first(where: { $0.skillID == "skill.demo" }))
        #expect(quarantined.executionReadiness == XTSkillExecutionReadinessState.quarantined.rawValue)
        #expect(quarantined.whyNotRunnable.contains("quarantined"))
        #expect(quarantined.unblockActions.contains("open_skill_governance_surface"))
    }

    @Test
    func officialSkillBlockerSummariesExposeWhyNotRunnableAndUnblockActions() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        try fixture.writeHubSkillsStoreForGovernanceSurface()

        let snapshot = AXSkillsLibrary.compatibilityDoctorSnapshot(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            skillsDir: fixture.skillsDir,
            hubBaseDir: fixture.hubBaseDir
        )

        let blocker = try #require(
            snapshot.officialPackageLifecycleTopBlockerSummaries.first(where: { $0.title == "Agent Browser" })
        )
        #expect(blocker.whyNotRunnable.contains("grant chain"))
        #expect(blocker.unblockActions.contains("request_hub_grant"))
        #expect(blocker.unblockActions.contains("refresh_resolved_cache"))
    }

    @Test
    func supervisorSkillPreflightGateDistinguishesPassGrantAndQuarantine() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        try fixture.writeHubSkillsStoreForGovernanceSurface()
        let projectRoot = fixture.root.appendingPathComponent("preflight-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let defaultConfig = AXProjectConfig.default(forProjectRoot: projectRoot)
        let grantConfig = AXProjectConfig.default(forProjectRoot: projectRoot)
            .settingToolPolicy(profile: ToolProfile.full.rawValue)
            .settingProjectGovernance(executionTier: .a3DeliverAuto)

        let supported = SupervisorSkillPreflightGate.evaluate(
            skillId: "find-skills",
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: projectRoot,
            config: defaultConfig,
            hubBaseDir: fixture.hubBaseDir
        )
        #expect(supported.decision == .pass)
        #expect(supported.denyCode.isEmpty)
        #expect(supported.readiness?.executionReadiness == XTSkillExecutionReadinessState.ready.rawValue)

        let quarantined = SupervisorSkillPreflightGate.evaluate(
            skillId: "skill.demo",
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: projectRoot,
            config: defaultConfig,
            hubBaseDir: fixture.hubBaseDir
        )
        #expect(quarantined.decision == .blocked)
        #expect(quarantined.denyCode == "preflight_quarantined")
        #expect(quarantined.summary.contains("quarantined"))
        #expect(quarantined.readiness?.executionReadiness == XTSkillExecutionReadinessState.quarantined.rawValue)

        let grantRequired = SupervisorSkillPreflightGate.evaluate(
            skillId: "repo.pr.create",
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: projectRoot,
            config: grantConfig,
            hubBaseDir: fixture.hubBaseDir
        )
        #expect(grantRequired.decision == .grantRequired)
        #expect(grantRequired.denyCode == "grant_required")
        #expect(grantRequired.readiness?.executionReadiness == XTSkillExecutionReadinessState.grantRequired.rawValue)

        let explicitGrant = SupervisorSkillPreflightGate.evaluate(
            skillId: "repo.pr.create",
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: projectRoot,
            config: grantConfig,
            hasExplicitGrant: true,
            hubBaseDir: fixture.hubBaseDir
        )
        #expect(explicitGrant.decision == .pass)
        #expect(explicitGrant.denyCode.isEmpty)
        #expect(explicitGrant.readiness?.executionReadiness == XTSkillExecutionReadinessState.grantRequired.rawValue)
    }

    @Test
    func supervisorSkillPreflightGateTreatsLocalApprovalAsPassUntilUserApproves() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        try fixture.writeHubSkillsStoreForSupervisorRegistry()

        let projectRoot = fixture.root.appendingPathComponent("preflight-local-approval", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let config = AXProjectConfig.default(forProjectRoot: projectRoot)
            .settingProjectGovernance(executionTier: .a2RepoAuto)
            .settingToolPolicy(profile: ToolProfile.coding.rawValue)

        let verdict = SupervisorSkillPreflightGate.evaluate(
            skillId: "process.start",
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: projectRoot,
            config: config,
            hubBaseDir: fixture.hubBaseDir
        )

        #expect(verdict.decision == .pass)
        #expect(verdict.requiresLocalApprovalBeforeRun)
        #expect(verdict.denyCode.isEmpty)
        #expect(verdict.readiness?.executionReadiness == XTSkillExecutionReadinessState.localApprovalRequired.rawValue)
        #expect(verdict.summary.contains("approval floor"))
    }

    @Test
    func supervisorSkillPreflightGatePromotesPolicyClampedAgentBrowserReadActionIntoGrantRequired() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        try fixture.writeHubSkillsStoreForSupervisorRegistry()

        let projectRoot = fixture.root.appendingPathComponent("preflight-policy-clamped-browser-read", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let config = AXProjectConfig.default(forProjectRoot: projectRoot)
            .settingProjectGovernance(executionTier: .a4OpenClaw)
            .settingToolPolicy(profile: ToolProfile.full.rawValue)

        let verdict = SupervisorSkillPreflightGate.evaluate(
            skillId: "agent-browser",
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            toolCall: ToolCall(
                tool: .browser_read,
                args: ["url": .string("https://example.com")]
            ),
            projectRoot: projectRoot,
            config: config,
            hubBaseDir: fixture.hubBaseDir
        )

        #expect(verdict.decision == .grantRequired)
        #expect(verdict.denyCode == "grant_required")
        #expect(verdict.readiness?.executionReadiness == XTSkillExecutionReadinessState.grantRequired.rawValue)
        #expect(verdict.readiness?.reasonCode.contains("grant floor") == true)
        #expect(verdict.readiness?.unblockActions.contains("request_hub_grant") == true)
    }

    @Test
    func skillExecutionReadinessUsesHubDisconnectedWhenHubBridgeIsOnlyMissingSurface() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        let projectRoot = fixture.root.appendingPathComponent("hub-disconnected-readiness", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let readiness = AXSkillsLibrary.skillExecutionReadiness(
            skillId: "find-skills",
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: projectRoot,
            config: .default(forProjectRoot: projectRoot),
            hubBaseDir: fixture.hubBaseDir
        )

        #expect(readiness.executionReadiness == XTSkillExecutionReadinessState.hubDisconnected.rawValue)
        #expect(readiness.denyCode == "hub_disconnected")
        #expect(readiness.reasonCode == "hub connectivity unavailable")
        #expect(readiness.unblockActions == ["reconnect_hub"])
        #expect(readiness.requiredRuntimeSurfaces.contains("hub_bridge_network"))
    }

    @Test
    func skillExecutionReadinessFailsClosedForMissingLocalVisionRuntime() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        let projectRoot = fixture.root.appendingPathComponent("local-vision-runtime-missing", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try writeLocalAISkillStore(
            hubBaseDir: fixture.hubBaseDir,
            projectID: fixture.projectID,
            skillID: "local-vision-reader",
            capabilitiesRequired: ["ai.vision.local"]
        )

        let readiness = AXSkillsLibrary.skillExecutionReadiness(
            skillId: "local-vision-reader",
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: projectRoot,
            config: .default(forProjectRoot: projectRoot),
            hubBaseDir: fixture.hubBaseDir
        )

        #expect(readiness.executionReadiness == XTSkillExecutionReadinessState.runtimeUnavailable.rawValue)
        #expect(readiness.capabilityFamilies.contains("ai.vision.local"))
        #expect(readiness.intentFamilies.contains("ai.vision.local"))
        #expect(readiness.requiredRuntimeSurfaces == ["local_vision_runtime"])
        #expect(readiness.unblockActions.contains("open_model_settings"))
        #expect(readiness.reasonCode.contains("local_vision_runtime"))
    }

    @Test
    func skillExecutionReadinessBecomesReadyWhenMatchingLocalVisionModelExists() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        let projectRoot = fixture.root.appendingPathComponent("local-vision-runtime-ready", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try writeLocalAISkillStore(
            hubBaseDir: fixture.hubBaseDir,
            projectID: fixture.projectID,
            skillID: "local-vision-reader",
            capabilitiesRequired: ["ai.vision.local"]
        )
        try writeLocalModelStateSnapshot(
            baseDir: fixture.hubBaseDir,
            models: [
                HubModel(
                    id: "qwen2-vl-ocr",
                    name: "Qwen2 VL OCR",
                    backend: "mlx",
                    quant: "4bit",
                    contextLength: 8192,
                    paramsB: 7.0,
                    state: .available,
                    modelPath: "/models/qwen2-vl-ocr",
                    taskKinds: ["vision_understand", "ocr"]
                )
            ]
        )

        let readiness = AXSkillsLibrary.skillExecutionReadiness(
            skillId: "local-vision-reader",
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: projectRoot,
            config: .default(forProjectRoot: projectRoot),
            hubBaseDir: fixture.hubBaseDir
        )

        #expect(readiness.executionReadiness == XTSkillExecutionReadinessState.ready.rawValue)
        #expect(readiness.runnableNow)
        #expect(readiness.requiredRuntimeSurfaces == ["local_vision_runtime"])
        #expect(readiness.unblockActions == ["retry_dispatch"])
    }

    @Test
    func skillExecutionReadinessHonorsLaunchStatusBlockForLocalEmbeddingRuntime() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        let projectRoot = fixture.root.appendingPathComponent("local-embedding-runtime-blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try writeLocalAISkillStore(
            hubBaseDir: fixture.hubBaseDir,
            projectID: fixture.projectID,
            skillID: "local-embedding-reader",
            capabilitiesRequired: ["ai.embed.local"]
        )
        try writeLocalModelStateSnapshot(
            baseDir: fixture.hubBaseDir,
            models: [
                HubModel(
                    id: "qwen3-embedding",
                    name: "Qwen3 Embedding",
                    backend: "mlx",
                    quant: "4bit",
                    contextLength: 4096,
                    paramsB: 0.6,
                    state: .available,
                    modelPath: "/models/qwen3-embedding",
                    taskKinds: ["embedding"],
                    outputModalities: ["embedding"]
                )
            ]
        )
        try writeHubLaunchStatusSnapshot(
            baseDir: fixture.hubBaseDir,
            blockedCapabilities: ["ai.embed.local"]
        )

        let readiness = AXSkillsLibrary.skillExecutionReadiness(
            skillId: "local-embedding-reader",
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: projectRoot,
            config: .default(forProjectRoot: projectRoot),
            hubBaseDir: fixture.hubBaseDir
        )

        #expect(readiness.executionReadiness == XTSkillExecutionReadinessState.runtimeUnavailable.rawValue)
        #expect(readiness.requiredRuntimeSurfaces == ["local_embedding_runtime"])
        #expect(readiness.unblockActions.contains("open_model_settings"))
        #expect(readiness.reasonCode.contains("local_embedding_runtime"))
    }

    @Test
    func supervisorSkillRegistrySnapshotIncludesRunnableLocalWrapperBuiltins() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        try writeLocalModelStateSnapshot(
            baseDir: fixture.hubBaseDir,
            models: [
                HubModel(
                    id: "qwen3-embed-4b",
                    name: "Qwen3 Embed 4B",
                    backend: "mlx",
                    quant: "",
                    contextLength: 8_192,
                    paramsB: 4.0,
                    state: .available,
                    modelPath: "/models/qwen3-embed-4b",
                    taskKinds: ["embedding"],
                    outputModalities: ["embedding"],
                    offlineReady: true
                ),
                HubModel(
                    id: "whisper-large-v3",
                    name: "Whisper Large V3",
                    backend: "mlx",
                    quant: "",
                    contextLength: 4_096,
                    paramsB: 1.5,
                    state: .loaded,
                    modelPath: "/models/whisper-large-v3",
                    taskKinds: ["speech_to_text"],
                    inputModalities: ["audio"],
                    offlineReady: true
                ),
                HubModel(
                    id: "qwen2-vl-ocr",
                    name: "Qwen2 VL OCR",
                    backend: "mlx",
                    quant: "",
                    contextLength: 8_192,
                    paramsB: 7.0,
                    state: .loaded,
                    modelPath: "/models/qwen2-vl-ocr",
                    taskKinds: ["vision_understand", "ocr"],
                    inputModalities: ["image"],
                    offlineReady: true
                ),
                HubModel(
                    id: "kokoro-tts",
                    name: "Kokoro TTS",
                    backend: "mlx",
                    quant: "",
                    contextLength: 4_096,
                    paramsB: 0.8,
                    state: .available,
                    modelPath: "/models/kokoro-tts",
                    taskKinds: ["text_to_speech"],
                    outputModalities: ["audio"],
                    offlineReady: true
                ),
            ]
        )

        let snapshot = try #require(
            AXSkillsLibrary.supervisorSkillRegistrySnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                hubBaseDir: fixture.hubBaseDir
            )
        )

        for skillId in ["local-embeddings", "local-transcribe", "local-vision", "local-ocr", "local-tts"] {
            let item = try #require(snapshot.items.first(where: { $0.skillId == skillId }))
            #expect(item.policyScope == "xt_builtin")
            #expect(item.publisherID == "xt_builtin")
            #expect(item.governedDispatch?.tool == ToolName.run_local_task.rawValue)
            #expect(item.governedDispatchNotes.contains(where: { $0.contains("XT binds the best runnable Hub local") }))
        }
    }

    @Test
    func resolvedSkillsCacheSnapshotIncludesRunnableLocalWrapperBuiltins() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        let projectRoot = fixture.root.appendingPathComponent("resolved-skill-cache-local-wrappers", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try writeLocalModelStateSnapshot(
            baseDir: fixture.hubBaseDir,
            models: [
                HubModel(
                    id: "qwen2-vl-instruct",
                    name: "Qwen2 VL Instruct",
                    backend: "mlx",
                    quant: "",
                    contextLength: 16_384,
                    paramsB: 7.0,
                    state: .loaded,
                    modelPath: "/models/qwen2-vl-instruct",
                    taskKinds: ["vision_understand"],
                    inputModalities: ["image"],
                    offlineReady: true
                )
            ]
        )

        let snapshot = try #require(
            AXSkillsLibrary.resolvedSkillsCacheSnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                projectRoot: projectRoot,
                config: .default(forProjectRoot: projectRoot),
                hubBaseDir: fixture.hubBaseDir
            )
        )

        #expect(snapshot.source.contains("+xt_builtin"))
        let vision = try #require(snapshot.items.first(where: { $0.skillId == "local-vision" }))
        #expect(vision.sourceId == "xt_builtin")
        #expect(vision.pinScope == "xt_builtin")
        #expect(vision.governedDispatch?.tool == ToolName.run_local_task.rawValue)
        #expect(snapshot.items.contains(where: { $0.skillId == "local-ocr" }) == false)
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
        #expect(git.intentFamilies == ["repo.read"])
        #expect(git.capabilityFamilies == ["repo.read"])
        #expect(git.capabilityProfiles == ["observe_only"])
        #expect(git.grantFloor == XTSkillGrantFloor.none.rawValue)
        #expect(git.approvalFloor == XTSkillApprovalFloor.none.rawValue)
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
        #expect(agentBrowser.intentFamilies.contains("browser.observe"))
        #expect(agentBrowser.intentFamilies.contains("browser.interact"))
        #expect(agentBrowser.capabilityFamilies.contains("browser.observe"))
        #expect(agentBrowser.capabilityFamilies.contains("browser.interact"))
        #expect(agentBrowser.capabilityProfiles.contains(XTSkillCapabilityProfileID.browserResearch.rawValue))
        #expect(agentBrowser.capabilityProfiles.contains(XTSkillCapabilityProfileID.browserOperator.rawValue))
        #expect(agentBrowser.grantFloor == XTSkillGrantFloor.privileged.rawValue)
        #expect(agentBrowser.approvalFloor == XTSkillApprovalFloor.ownerConfirmation.rawValue)
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
        #expect(builtinProcessStart.intentFamilies == ["repo.verify"])
        #expect(builtinProcessStart.capabilityFamilies == ["repo.verify"])
        #expect(
            builtinProcessStart.capabilityProfiles == [
                XTSkillCapabilityProfileID.observeOnly.rawValue,
                XTSkillCapabilityProfileID.codingExecute.rawValue,
            ]
        )
        #expect(builtinProcessStart.grantFloor == XTSkillGrantFloor.none.rawValue)
        #expect(builtinProcessStart.approvalFloor == XTSkillApprovalFloor.localApproval.rawValue)
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
        HubIPCClient.installResolvedSkillsOverrideForTesting { _ in
            HubIPCClient.ResolvedSkillsResult(
                ok: false,
                source: "hub_runtime_grpc",
                skills: [],
                reasonCode: "compat_test_force_local_fixture"
            )
        }
        defer { HubIPCClient.resetResolvedSkillsOverrideForTesting() }

        let manager = SupervisorManager.makeForTesting()
        manager.setAppModel(appModel)

        let memory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续执行当前项目")
        let registrySnapshot = await manager.supervisorSkillRegistrySnapshotForTesting("继续执行当前项目")
        let resolvedCache = XTResolvedSkillsCacheStore.activeSnapshot(
            for: AXProjectContext(root: projectRoot)
        )

        #expect(memory.contains("skills_registry:"))
        #expect(memory.contains("supervisor_global_skills_registry:"))
        #expect(memory.contains("grant=yes"))
        #expect(memory.contains("guarded-automation"))
        #expect(memory.contains("supervisor-voice"))
        #expect(memory.contains("agent-browser"))
        #expect(memory.contains("browser.runtime.smoke"))
        #expect(memory.contains("repo.git.status"))
        #expect(memory.contains("process.logs"))
        #expect(memory.contains("preferred_for: trusted_automation_readiness, governed_browser_actions"))
        #expect(memory.contains("preferred_for: supervisor_playback_status, preview, speak, stop"))
        #expect(memory.contains("dispatch=project_snapshot"))
        #expect(memory.contains("dispatch=supervisor.voice.playback"))
        #expect(memory.contains("dispatch=git_status"))
        #expect(memory.contains("dispatch=device.browser.control"))
        #expect(memory.contains("dispatch=process_logs"))
        #expect(memory.contains("payload: fixed=action=open_url"))
        #expect(memory.contains("required_any=url"))
        #expect(memory.contains("args=url"))
        #expect(memory.contains("variant: actions=open/open_url/navigate/goto/visit -> device.browser.control"))
        #expect(memory.contains("variant: actions=snapshot/inspect/extract -> device.browser.control"))
        #expect(memory.contains("project=Supervisor Global"))
        #expect(memory.contains("request-skill-enable"))
        #expect((registrySnapshot?.items.count ?? 0) > 0)
        #expect(registrySnapshot?.items.count == resolvedCache?.items.count)
        #expect(registrySnapshot?.items.contains(where: { $0.skillId == "supervisor-voice" }) == true)
        #expect(registrySnapshot?.items.contains(where: { $0.skillId == "guarded-automation" }) == true)
        #expect(registrySnapshot?.items.contains(where: { $0.skillId == "process.start" }) == true)
        #expect((resolvedCache?.items.count ?? 0) > 0)
        #expect(resolvedCache?.items.contains(where: { $0.skillId == "supervisor-voice" }) == true)
        #expect(resolvedCache?.items.contains(where: { $0.skillId == "guarded-automation" }) == true)
        #expect(resolvedCache?.items.contains(where: { $0.skillId == "process.start" }) == true)
    }

    @MainActor
    @Test
    func supervisorMemoryWithoutFocusedProjectFallsBackToGlobalSkillRegistry() async throws {
        let manager = SupervisorManager.makeForTesting()

        let memory = await manager.buildSupervisorLocalMemoryV1ForTesting("查 PPT 相关 skill")
        let snapshot = await manager.supervisorSkillRegistrySnapshotForTesting("查 PPT 相关 skill")

        let resolved = try #require(snapshot)
        #expect(resolved.projectId == "supervisor-global")
        #expect(resolved.projectName == "Supervisor Global")
        #expect(resolved.memorySource == "supervisor_global_skill_registry")
        #expect(resolved.items.contains(where: { $0.skillId == "find-skills" }))
        #expect(resolved.items.contains(where: { $0.skillId == "request-skill-enable" }))
        #expect(memory.contains("skills_registry:"))
        #expect(memory.contains("project=Supervisor Global"))
        #expect(memory.contains("find-skills"))
        #expect(memory.contains("request-skill-enable"))
        #expect(memory.contains("dispatch=skills.search"))
        #expect(memory.contains("dispatch=skills.pin"))
        #expect(memory.contains("preferred_for: governed_skill_discovery"))
        #expect(memory.contains("aliases=skill find, find skills, skills.search"))
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
        #expect(snapshot.profileEpoch.isEmpty == false)
        #expect(snapshot.trustRootSetHash.isEmpty == false)
        #expect(snapshot.revocationEpoch.isEmpty == false)
        #expect(snapshot.officialChannelSnapshotID.isEmpty == false)
        #expect(snapshot.runtimeSurfaceHash.isEmpty == false)
        #expect(snapshot.auditRef == "audit-xt-w3-34-i-resolved-skills-12345678")
        #expect(snapshot.grantSnapshotRef == "grant-chain:12345678:refresh_required")
        #expect(snapshot.items.count == 16)
        #expect(!snapshot.items.contains(where: { $0.skillId == "email.send.auto" }))

        let repo = try #require(snapshot.items.first(where: { $0.skillId == "repo.git.status" }))
        #expect(repo.intentFamilies == ["repo.read"])
        #expect(repo.capabilityFamilies == ["repo.read"])
        #expect(repo.capabilityProfiles == ["observe_only"])
        #expect(repo.grantFloor == XTSkillGrantFloor.none.rawValue)
        #expect(repo.approvalFloor == XTSkillApprovalFloor.none.rawValue)
        #expect(repo.packageSHA256 == "1111111111111111111111111111111111111111111111111111111111111111")
        #expect(repo.canonicalManifestSHA256 == "2222222222222222222222222222222222222222222222222222222222222222")
        #expect(repo.pinScope == "global")
        #expect(repo.riskLevel == "low")
        #expect(repo.requiresGrant == false)
        #expect(repo.timeoutMs == 15_000)

        let browser = try #require(snapshot.items.first(where: { $0.skillId == "browser.runtime.smoke" }))
        #expect(browser.pinScope == "project")
        #expect(browser.capabilityProfiles.contains(XTSkillCapabilityProfileID.browserResearch.rawValue))
        #expect(browser.grantFloor == XTSkillGrantFloor.privileged.rawValue)
        #expect(browser.riskLevel == "high")
        #expect(browser.requiresGrant)
        #expect(browser.maxRetries == 2)

        let agentBrowser = try #require(snapshot.items.first(where: { $0.skillId == "agent-browser" }))
        #expect(agentBrowser.pinScope == "project")
        #expect(agentBrowser.intentFamilies.contains("browser.observe"))
        #expect(agentBrowser.capabilityProfiles.contains(XTSkillCapabilityProfileID.browserOperator.rawValue))
        #expect(agentBrowser.approvalFloor == XTSkillApprovalFloor.ownerConfirmation.rawValue)
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
            Issue.record("unexpected failure: \(String(describing: failure.reasonCode))")
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
            Issue.record("unexpected failure: \(String(describing: failure.reasonCode))")
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
    func capabilityFamiliesDeriveFromRunLocalTaskTaskKinds() {
        #expect(
            XTSkillCapabilityProfileSupport.capabilityFamilies(
                for: .run_local_task,
                args: ["task_kind": .string("embedding")]
            ) == ["ai.embed.local"]
        )
        #expect(
            XTSkillCapabilityProfileSupport.capabilityFamilies(
                for: .run_local_task,
                args: ["task_kind": .string("ocr")]
            ) == ["ai.vision.local"]
        )
        #expect(
            XTSkillCapabilityProfileSupport.capabilityFamilies(
                for: .run_local_task,
                args: ["task_kind": .string("text_to_speech")]
            ) == ["ai.audio.tts.local"]
        )
    }

    @Test
    func projectSkillRouterMapsRunLocalTaskSkillToToolCall() throws {
        var embeddingSkill = makeRouterRegistryItem(
            skillId: "local.embed.skill",
            packageSHA256: "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
            policyScope: "project",
            officialPackage: true,
            capabilityFamilies: ["ai.embed.local"],
            capabilityProfiles: [XTSkillCapabilityProfileID.observeOnly.rawValue]
        )
        embeddingSkill.intentFamilies = ["ai.embed.local"]
        embeddingSkill.capabilitiesRequired = ["ai.embed.local"]
        embeddingSkill.governedDispatch = SupervisorGovernedSkillDispatch(
            tool: ToolName.run_local_task.rawValue,
            fixedArgs: [
                "task_kind": .string("embedding"),
                "preferred_model_id": .string("qwen3-embed-4b")
            ],
            passthroughArgs: ["text", "query", "texts"],
            argAliases: [:],
            requiredAny: [["text", "query", "texts"]],
            exactlyOneOf: []
        )

        let snapshot = SupervisorSkillRegistrySnapshot(
            schemaVersion: SupervisorSkillRegistrySnapshot.currentSchemaVersion,
            projectId: "project-router-local-ai",
            projectName: "Router Local AI",
            updatedAtMs: 1,
            memorySource: "test",
            items: [embeddingSkill],
            auditRef: "audit-router-local-ai"
        )

        let result = XTProjectSkillRouter.map(
            call: GovernedSkillCall(
                id: "skill-local-embed-1",
                skill_id: "local.embed.skill",
                payload: [
                    "text": .string("hello local embeddings")
                ]
            ),
            projectId: "project-router-local-ai",
            projectName: "Router Local AI",
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

        #expect(mapped.skillId == "local.embed.skill")
        #expect(mapped.intentFamilies == ["ai.embed.local"])
        #expect(mapped.capabilityFamilies == ["ai.embed.local"])
        #expect(mapped.toolCall.id == "skill-local-embed-1")
        #expect(mapped.toolCall.tool == .run_local_task)
        #expect(mapped.toolCall.args["task_kind"]?.stringValue == "embedding")
        #expect(mapped.toolCall.args["preferred_model_id"]?.stringValue == "qwen3-embed-4b")
        #expect(mapped.toolCall.args["text"]?.stringValue == "hello local embeddings")
    }

    @Test
    func projectSkillRouterAutoInjectsPreferredLocalTaskBindingWhenWrapperOmitsModelArgs() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        try writeLocalModelStateSnapshot(
            baseDir: fixture.hubBaseDir,
            models: [
                HubModel(
                    id: "qwen2-vl-instruct",
                    name: "Qwen2 VL Instruct",
                    backend: "mlx",
                    quant: "",
                    contextLength: 16_384,
                    paramsB: 0,
                    roles: nil,
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: "/models/qwen2-vl-instruct",
                    note: nil,
                    taskKinds: ["vision_understand"],
                    offlineReady: true
                )
            ]
        )

        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        var visionSkill = makeRouterRegistryItem(
            skillId: "local-vision",
            packageSHA256: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
            policyScope: "project",
            officialPackage: true,
            capabilityFamilies: ["ai.vision.local"],
            capabilityProfiles: [XTSkillCapabilityProfileID.observeOnly.rawValue]
        )
        visionSkill.intentFamilies = ["ai.vision.local"]
        visionSkill.capabilitiesRequired = ["ai.vision.local"]
        visionSkill.governedDispatch = SupervisorGovernedSkillDispatch(
            tool: ToolName.run_local_task.rawValue,
            fixedArgs: [
                "task_kind": .string("vision_understand")
            ],
            passthroughArgs: ["image_path", "text"],
            argAliases: [:],
            requiredAny: [["model_id", "preferred_model_id"], ["image_path"]],
            exactlyOneOf: []
        )

        let snapshot = SupervisorSkillRegistrySnapshot(
            schemaVersion: SupervisorSkillRegistrySnapshot.currentSchemaVersion,
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            updatedAtMs: 1,
            memorySource: "test",
            items: [visionSkill],
            auditRef: "audit-router-local-vision"
        )

        let result = XTProjectSkillRouter.map(
            call: GovernedSkillCall(
                id: "skill-local-vision-1",
                skill_id: "local-vision",
                payload: [
                    "image_path": .string("/tmp/diagram.png"),
                    "text": .string("describe this architecture diagram"),
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

        #expect(mapped.toolCall.tool == .run_local_task)
        #expect(mapped.toolCall.args["task_kind"]?.stringValue == "vision_understand")
        #expect(mapped.toolCall.args["preferred_model_id"]?.stringValue == "qwen2-vl-instruct")
        #expect(mapped.toolCall.args["image_path"]?.stringValue == "/tmp/diagram.png")
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
        #expect(AXSkillsLibrary.canonicalSupervisorSkillID("skill find") == "find-skills")
        #expect(AXSkillsLibrary.canonicalSupervisorSkillID("find skills") == "find-skills")
        #expect(AXSkillsLibrary.canonicalSupervisorSkillID("enable skill") == "request-skill-enable")
        #expect(AXSkillsLibrary.canonicalSupervisorSkillID("ocr") == "local-ocr")
        #expect(AXSkillsLibrary.canonicalSupervisorSkillID("transcribe") == "local-transcribe")
        #expect(AXSkillsLibrary.canonicalSupervisorSkillID("tts") == "local-tts")
        #expect(AXSkillsLibrary.canonicalSupervisorSkillID("embedding") == "local-embeddings")
        #expect(mapped.skillId == "guarded-automation")
        #expect(mapped.toolCall.tool == .deviceBrowserControl)
        #expect(mapped.toolCall.args["action"]?.stringValue == "open_url")
        #expect(mapped.toolCall.args["url"]?.stringValue == "https://example.com/alias")
        #expect(mapped.toolCall.args["grant_id"]?.stringValue == "grant-guarded-alias-1")
    }

    @Test
    func projectSkillRouterFallsBackByIntentFamiliesWhenSkillIdMissing() throws {
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
                id: "skill-intent-fallback-1",
                skill_id: "",
                intent_families: ["repo.read"],
                payload: [:]
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

        #expect(mapped.requestedSkillId == nil)
        #expect(mapped.skillId == "repo.git.status")
        #expect(mapped.intentFamilies.contains("repo.read"))
        #expect(mapped.routingReasonCode == "intent_family_fallback")
        #expect(mapped.routingExplanation?.contains("repo.read") == true)
        #expect(mapped.toolCall.tool == .git_status)
    }

    @Test
    func projectSkillRouterIntentFallbackPrefersRunnableOverBlockedProjectScopedCandidate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-router-intent-selection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let projectId = "project-router"
        let projectName = "Router Project"
        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingProjectGovernance(executionTier: .a2RepoAuto)
            .settingToolPolicy(profile: ToolProfile.coding.rawValue)

        let snapshot = SupervisorSkillRegistrySnapshot(
            schemaVersion: SupervisorSkillRegistrySnapshot.currentSchemaVersion,
            projectId: projectId,
            projectName: projectName,
            updatedAtMs: 1,
            memorySource: "test",
            items: [
                makeRouterRegistryItem(
                    skillId: "repo.read.project-blocked",
                    packageSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    policyScope: "project",
                    officialPackage: true,
                    capabilityFamilies: ["repo.read"],
                    capabilityProfiles: ["coding_execute"]
                ),
                makeRouterRegistryItem(
                    skillId: "repo.git.status",
                    packageSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    policyScope: "xt_builtin",
                    officialPackage: false,
                    capabilityFamilies: ["repo.read"],
                    capabilityProfiles: ["observe_only"]
                )
            ],
            auditRef: "audit-router-selection"
        )

        let result = XTProjectSkillRouter.map(
            call: GovernedSkillCall(
                id: "skill-intent-ready-1",
                skill_id: "",
                intent_families: ["repo.read"],
                payload: [:]
            ),
            projectId: projectId,
            projectName: projectName,
            registrySnapshot: snapshot,
            projectRoot: root,
            config: config,
            hubBaseDir: root
        )

        let mapped: XTProjectMappedSkillDispatch
        switch result {
        case .success(let dispatch):
            mapped = dispatch
        case .failure(let failure):
            Issue.record("unexpected failure: \(failure.reasonCode)")
            throw failure
        }

        #expect(mapped.skillId == "repo.git.status")
        #expect(mapped.routingReasonCode == "intent_family_fallback")
        #expect(mapped.routingExplanation?.contains("readiness=ready") == true)
    }

    @Test
    func projectSkillRouterIntentFallbackPrefersOfficialThenPackageSHALexically() throws {
        let snapshot = SupervisorSkillRegistrySnapshot(
            schemaVersion: SupervisorSkillRegistrySnapshot.currentSchemaVersion,
            projectId: "project-router-2",
            projectName: "Router Project 2",
            updatedAtMs: 1,
            memorySource: "test",
            items: [
                makeRouterRegistryItem(
                    skillId: "repo.search.community",
                    packageSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    policyScope: "global",
                    officialPackage: false,
                    capabilityFamilies: ["repo.read"],
                    capabilityProfiles: ["observe_only"]
                ),
                makeRouterRegistryItem(
                    skillId: "repo.search.official.b",
                    packageSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    policyScope: "global",
                    officialPackage: true,
                    capabilityFamilies: ["repo.read"],
                    capabilityProfiles: ["observe_only"]
                ),
                makeRouterRegistryItem(
                    skillId: "repo.search.official.a",
                    packageSHA256: "9999999999999999999999999999999999999999999999999999999999999999",
                    policyScope: "global",
                    officialPackage: true,
                    capabilityFamilies: ["repo.read"],
                    capabilityProfiles: ["observe_only"]
                )
            ],
            auditRef: "audit-router-selection-2"
        )

        let result = XTProjectSkillRouter.map(
            call: GovernedSkillCall(
                id: "skill-intent-ready-2",
                skill_id: "",
                intent_families: ["repo.read"],
                payload: [:]
            ),
            projectId: "project-router-2",
            projectName: "Router Project 2",
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

        #expect(mapped.skillId == "repo.search.official.a")
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
        #expect(guidance.contains("valid governed registry"))
        #expect(guidance.contains("XT builtin governed skills"))
        #expect(guidance.contains("routing, and payload hints to shape `payload` and choose a stable `skill_id`"))
        #expect(guidance.contains("Treat `routing: prefers_builtin=...` and `routing: entrypoints=...` as skill-family metadata."))
        #expect(guidance.contains("If the user explicitly names a registered wrapper or entrypoint skill_id, keep that exact registered `skill_id` in `skill_calls`"))
        #expect(guidance.contains("If the user asks only for a capability and the family advertises `routing: prefers_builtin=...`, choose the preferred builtin"))
        #expect(guidance.contains("If `skills_registry` contains `local-ocr`, prefer it for OCR, screenshot text extraction, and image-to-text requests"))
        #expect(guidance.contains("If `skills_registry` contains `local-vision`, prefer it for screenshot, diagram, and image-understanding requests"))
        #expect(guidance.contains("If `skills_registry` contains `local-transcribe`, prefer it for audio transcription and speech-to-text work"))
        #expect(guidance.contains("If `skills_registry` contains `local-tts`, prefer it when the user explicitly wants spoken output or an audio artifact"))
        #expect(guidance.contains("If `skills_registry` contains `local-embeddings`, prefer it for embedding, retrieval-indexing, or vectorization work"))
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
        #expect(rules.contains("source=xt_builtin_skill_registry"))
        #expect(rules.contains("scope=xt_builtin"))
        #expect(rules.contains("Treat `routing: prefers_builtin=...` and `routing: entrypoints=...` as skill-family metadata when choosing `skill_id`."))
        #expect(rules.contains("If the user explicitly names a registered wrapper or entrypoint skill, keep that exact registered `skill_id`"))
        #expect(rules.contains("If the user asks only for a capability and the family marks a preferred builtin, choose the preferred builtin"))
        #expect(rules.contains("Do not emit duplicate sibling `skill_calls` for one intent"))
        #expect(rules.contains("If `local-ocr` is present in `skills_registry`, use it for OCR and image-to-text requests"))
        #expect(rules.contains("If `local-vision` is present in `skills_registry`, use it for image understanding requests"))
        #expect(rules.contains("If `local-transcribe` is present in `skills_registry`, use it for audio transcription and speech-to-text requests"))
        #expect(rules.contains("If `local-tts` is present in `skills_registry`, use it for explicit spoken-output or audio artifact requests"))
        #expect(rules.contains("If `local-embeddings` is present in `skills_registry`, use it for embedding or vectorization requests"))
    }

    @MainActor
    @Test
    func projectSkillProgressLineDescribesLocalOCRWrapper() throws {
        let session = ChatSessionModel()
        let line = session.projectSkillProgressLineForTesting(
            dispatch: XTProjectMappedSkillDispatch(
                skillId: "local-ocr",
                toolCall: ToolCall(
                    id: "skill-progress-local-ocr-1",
                    tool: .run_local_task,
                    args: [
                        "task_kind": .string("ocr"),
                        "model_id": .string("ocr-model"),
                        "image_path": .string("/tmp/mock.png"),
                    ]
                ),
                toolName: ToolName.run_local_task.rawValue
            )
        )

        #expect(line.contains("local-ocr"))
        #expect(line.contains("提取图片里的文字"))
    }

    @Test
    func resolvedSkillsCacheStorePersistsAndExpiresFailClosed() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.writeHubSkillsStoreForSupervisorRegistry()
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

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
        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: context, nowMs: 70_001) == nil)
    }

    @Test
    func resolvedSkillsCacheStorePersistsBuiltinFallbackWhenHubSnapshotUnavailable() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let projectRoot = fixture.root.appendingPathComponent("resolved-cache-missing-hub", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let context = AXProjectContext(root: projectRoot)

        let snapshot = try #require(
            XTResolvedSkillsCacheStore.refreshFromHub(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                context: context,
                hubBaseDir: fixture.hubBaseDir,
                ttlMs: 120_000,
                nowMs: 2_000
            )
        )

        #expect(snapshot.source == "hub_resolved_skills_snapshot+xt_builtin")
        #expect(snapshot.hubIndexUpdatedAtMs == 0)
        #expect(snapshot.items.contains(where: { $0.sourceId == "xt_builtin" }))
        #expect(snapshot.items.contains(where: { $0.skillId == "guarded-automation" }))
        #expect(XTResolvedSkillsCacheStore.load(for: context)?.resolvedSnapshotId == snapshot.resolvedSnapshotId)
        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: context, nowMs: 2_001) == nil)
        #expect(FileManager.default.fileExists(atPath: context.resolvedSkillsCacheURL.path))
    }

    @Test
    func resolvedSkillsCacheStoreInvalidatesSnapshotWhenProfileEpochChanges() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.writeHubSkillsStoreForSupervisorRegistry()
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let projectRoot = fixture.root.appendingPathComponent("resolved-cache-profile-epoch", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let context = AXProjectContext(root: projectRoot)

        let snapshot = try #require(
            XTResolvedSkillsCacheStore.refreshFromHub(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                context: context,
                hubBaseDir: fixture.hubBaseDir,
                ttlMs: 120_000,
                nowMs: 3_000
            )
        )

        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: context, nowMs: 3_001)?.resolvedSnapshotId == snapshot.resolvedSnapshotId)

        let updatedConfig = try AXProjectStore.loadOrCreateConfig(for: context)
            .settingToolPolicy(profile: ToolProfile.coding.rawValue)
        try AXProjectStore.saveConfig(updatedConfig, for: context)

        #expect(XTResolvedSkillsCacheStore.activeSnapshot(for: context, nowMs: 3_001) == nil)
    }

    @Test
    func projectEffectiveSkillProfileSnapshotFailsClosedForUnknownLegacyToolProfileAtOpenClawCeiling() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        let projectRoot = fixture.root.appendingPathComponent("profile-fail-closed", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let config = AXProjectConfig.default(forProjectRoot: projectRoot)
            .settingProjectGovernance(executionTier: .a4OpenClaw)
            .settingToolPolicy(profile: "mystery-profile-token")

        let snapshot = AXSkillsLibrary.projectEffectiveSkillProfileSnapshot(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: projectRoot,
            config: config,
            hubBaseDir: fixture.hubBaseDir
        )

        #expect(ToolPolicy.parseProfile("mystery-profile-token") == .minimal)
        #expect(config.toolProfile == ToolProfile.minimal.rawValue)
        #expect(snapshot.executionTier == AXProjectExecutionTier.a4OpenClaw.rawValue)
        #expect(snapshot.legacyToolProfile == ToolProfile.minimal.rawValue)
        #expect(
            snapshot.discoverableProfiles == [
                XTSkillCapabilityProfileID.observeOnly.rawValue,
                XTSkillCapabilityProfileID.skillManagement.rawValue,
            ]
        )
        #expect(snapshot.discoverableProfiles.contains(XTSkillCapabilityProfileID.browserOperator.rawValue) == false)
        #expect(snapshot.ceilingCapabilityFamilies.contains("skills.manage"))
        #expect(snapshot.runnableNowProfiles.contains(XTSkillCapabilityProfileID.browserOperator.rawValue) == false)
    }

    @Test
    func projectEffectiveSkillProfileSnapshotDoesNotBlockRunnableObserveOnlyProfileWhenHubOnlySkillIsDisconnected() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        let projectRoot = fixture.root.appendingPathComponent("profile-hub-disconnected", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let snapshot = AXSkillsLibrary.projectEffectiveSkillProfileSnapshot(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: projectRoot,
            config: .default(forProjectRoot: projectRoot),
            hubBaseDir: fixture.hubBaseDir
        )

        #expect(snapshot.runnableNowProfiles.contains(XTSkillCapabilityProfileID.observeOnly.rawValue))
        #expect(snapshot.blockedProfiles.contains(where: { $0.profileID == XTSkillCapabilityProfileID.observeOnly.rawValue }) == false)
    }

    @Test
    func projectAwareGovernanceSurfaceTreatsPureGovernedWebSearchWrapperAsGrantRequestable() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        try fixture.writeHubSkillsStoreForGovernedNetworkWrapper()

        let snapshot = AXSkillsLibrary.compatibilityDoctorSnapshot(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            skillsDir: fixture.skillsDir,
            hubBaseDir: fixture.hubBaseDir
        )

        let projectRoot = fixture.root.appendingPathComponent("governed-websearch-surface", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let config = AXProjectConfig.default(forProjectRoot: projectRoot)
            .settingProjectGovernance(executionTier: .a4OpenClaw)
            .settingToolPolicy(profile: ToolProfile.full.rawValue)

        let items = snapshot.governanceSurfaceEntries(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: projectRoot,
            config: config,
            hubBaseDir: fixture.hubBaseDir
        )

        let wrapper = try #require(items.first(where: { $0.skillID == "tavily-websearch" }))
        #expect(wrapper.requestabilityState == "requestable")
        #expect(wrapper.executionReadiness == XTSkillExecutionReadinessState.grantRequired.rawValue)
        #expect(wrapper.stateLabel == "grant required")
        #expect(wrapper.whyNotRunnable.contains("grant floor"))
        #expect(wrapper.unblockActions.contains("request_hub_grant"))
        #expect(wrapper.tone == .warning)
    }

    @Test
    func projectEffectiveSkillProfileSnapshotPromotesPureGovernedWebSearchWrapperIntoGrantRequiredProfiles() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        try fixture.writeHubSkillsStoreForGovernedNetworkWrapper()

        let projectRoot = fixture.root.appendingPathComponent("governed-websearch-profile-snapshot", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let config = AXProjectConfig.default(forProjectRoot: projectRoot)
            .settingProjectGovernance(executionTier: .a4OpenClaw)
            .settingToolPolicy(profile: ToolProfile.full.rawValue)

        let snapshot = AXSkillsLibrary.projectEffectiveSkillProfileSnapshot(
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            projectRoot: projectRoot,
            config: config,
            hubBaseDir: fixture.hubBaseDir
        )

        #expect(snapshot.grantRequiredProfiles.contains(XTSkillCapabilityProfileID.observeOnly.rawValue))
        #expect(snapshot.requestableProfiles.contains(XTSkillCapabilityProfileID.observeOnly.rawValue))
        #expect(snapshot.blockedProfiles.contains(where: {
            $0.profileID == XTSkillCapabilityProfileID.observeOnly.rawValue
                && $0.state == XTSkillExecutionReadinessState.policyClamped.rawValue
        }) == false)
    }

    @Test
    func projectSkillRouterIntentFallbackTreatsPureGovernedWebSearchWrapperAsRequestable() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        try fixture.writeHubSkillsStoreForGovernedNetworkWrapper()

        let snapshot = try #require(
            AXSkillsLibrary.supervisorSkillRegistrySnapshot(
                projectId: fixture.projectID,
                projectName: fixture.projectName,
                hubBaseDir: fixture.hubBaseDir
            )
        )

        let projectRoot = fixture.root.appendingPathComponent("governed-websearch-router", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let config = AXProjectConfig.default(forProjectRoot: projectRoot)
            .settingProjectGovernance(executionTier: .a4OpenClaw)
            .settingToolPolicy(profile: ToolProfile.full.rawValue)

        let result = XTProjectSkillRouter.map(
            call: GovernedSkillCall(
                id: "skill-governed-websearch-router-1",
                skill_id: "",
                intent_families: ["web.search_live"],
                payload: ["query": .string("OpenAI GPT-5.4 release notes")]
            ),
            projectId: fixture.projectID,
            projectName: fixture.projectName,
            registrySnapshot: snapshot,
            projectRoot: projectRoot,
            config: config,
            hubBaseDir: fixture.hubBaseDir
        )

        let mapped: XTProjectMappedSkillDispatch
        switch result {
        case .success(let dispatch):
            mapped = dispatch
        case .failure(let failure):
            Issue.record("unexpected failure: \(failure.reasonCode)")
            throw failure
        }

        #expect(mapped.skillId == "tavily-websearch")
        #expect(mapped.routingReasonCode == "intent_family_fallback")
        #expect(mapped.routingExplanation?.contains("web.search_live") == true)
        #expect(mapped.routingExplanation?.contains("readiness=grant_required") == true)
        #expect(mapped.toolCall.tool == .web_search)
        #expect(mapped.toolCall.args["query"]?.stringValue == "OpenAI GPT-5.4 release notes")
    }

    @MainActor
    @Test
    func chatSessionProjectSkillActivityReadinessUsesEffectiveGrantRequiredTruthForPureGovernedWebWrapper() throws {
        let fixture = SkillsCompatibilityFixture()
        defer { fixture.cleanup() }

        let projectRoot = fixture.root.appendingPathComponent("governed-websearch-chat-readiness", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let ctx = AXProjectContext(root: projectRoot)
        let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
        try fixture.writeHubSkillsStoreForGovernedNetworkWrapper(projectID: projectId)
        HubPaths.setPinnedBaseDirOverride(fixture.hubBaseDir)
        defer { HubPaths.clearPinnedBaseDirOverride() }
        let config = AXProjectConfig.default(forProjectRoot: projectRoot)
            .settingProjectGovernance(executionTier: .a4OpenClaw)
            .settingToolPolicy(profile: ToolProfile.full.rawValue)
        let session = ChatSessionModel()

        let readiness = session.projectSkillExecutionReadinessForTesting(
            ctx: ctx,
            dispatch: XTProjectMappedSkillDispatch(
                skillId: "tavily-websearch",
                toolCall: ToolCall(
                    id: "skill-governed-websearch-chat-1",
                    tool: .web_search,
                    args: ["query": .string("OpenAI GPT-5.4 release notes")]
                ),
                toolName: ToolName.web_search.rawValue
            ),
            config: config
        )

        #expect(readiness?.executionReadiness == XTSkillExecutionReadinessState.grantRequired.rawValue)
        #expect(readiness?.denyCode == "grant_required")
        #expect(readiness?.reasonCode.contains("grant floor") == true)
        #expect(readiness?.unblockActions.contains("request_hub_grant") == true)
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

private func makeRouterRegistryItem(
    skillId: String,
    packageSHA256: String,
    policyScope: String,
    officialPackage: Bool,
    capabilityFamilies: [String],
    capabilityProfiles: [String]
) -> SupervisorSkillRegistryItem {
    SupervisorSkillRegistryItem(
        skillId: skillId,
        displayName: skillId,
        description: "router test",
        intentFamilies: ["repo.read"],
        capabilityFamilies: capabilityFamilies,
        capabilityProfiles: capabilityProfiles,
        grantFloor: XTSkillGrantFloor.none.rawValue,
        approvalFloor: XTSkillApprovalFloor.none.rawValue,
        packageSHA256: packageSHA256,
        publisherID: officialPackage ? "xhub.official" : "publisher.community",
        sourceID: officialPackage ? "official:catalog" : "local:upload",
        officialPackage: officialPackage,
        capabilitiesRequired: ["repo.read"],
        governedDispatch: SupervisorGovernedSkillDispatch(
            tool: ToolName.git_status.rawValue,
            fixedArgs: [:],
            passthroughArgs: [],
            argAliases: [:],
            requiredAny: [],
            exactlyOneOf: []
        ),
        governedDispatchVariants: [],
        governedDispatchNotes: [],
        inputSchemaRef: "schema://\(skillId).input",
        outputSchemaRef: "schema://\(skillId).output",
        sideEffectClass: "read_only",
        riskLevel: .low,
        requiresGrant: false,
        policyScope: policyScope,
        timeoutMs: 5_000,
        maxRetries: 0,
        available: true
    )
}

private func writeLocalAISkillStore(
    hubBaseDir: URL,
    projectID: String,
    skillID: String,
    capabilitiesRequired: [String]
) throws {
    let storeDir = hubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
    try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

    let packageSHA256 = String(repeating: "a", count: 64)
    let manifestSHA256 = String(repeating: "b", count: 64)
    let index: [String: Any] = [
        "schema_version": "skills_store_index.v1",
        "updated_at_ms": 88,
        "skills": [
            [
                "skill_id": skillID,
                "name": skillID,
                "version": "1.0.0",
                "description": "Local AI runtime test skill.",
                "publisher_id": "xhub.official",
                "source_id": "builtin:catalog",
                "package_sha256": packageSHA256,
                "abi_compat_version": "skills_abi_compat.v1",
                "compatibility_state": "supported",
                "canonical_manifest_sha256": manifestSHA256,
                "install_hint": "Open model settings and enable a matching local model.",
                "capabilities_required": capabilitiesRequired
            ]
        ]
    ]
    let pins: [String: Any] = [
        "schema_version": "skills_pins.v1",
        "updated_at_ms": 88,
        "memory_core_pins": [],
        "global_pins": [],
        "project_pins": [
            [
                "project_id": projectID,
                "skill_id": skillID,
                "package_sha256": packageSHA256
            ]
        ]
    ]

    try JSONSerialization.data(withJSONObject: index, options: [.prettyPrinted, .sortedKeys]).write(
        to: storeDir.appendingPathComponent("skills_store_index.json"),
        options: .atomic
    )
    try JSONSerialization.data(withJSONObject: pins, options: [.prettyPrinted, .sortedKeys]).write(
        to: storeDir.appendingPathComponent("skills_pins.json"),
        options: .atomic
    )
}

private func writeLocalModelStateSnapshot(
    baseDir: URL,
    models: [HubModel]
) throws {
    let snapshot = ModelStateSnapshot(
        models: models,
        updatedAt: Date().timeIntervalSince1970
    )
    let data = try JSONEncoder().encode(snapshot)
    try data.write(to: baseDir.appendingPathComponent("models_state.json"), options: .atomic)
}

private func writeHubLaunchStatusSnapshot(
    baseDir: URL,
    blockedCapabilities: [String]
) throws {
    let snapshot = XTHubLaunchStatusSnapshot(
        state: blockedCapabilities.isEmpty ? "ready" : "degraded",
        degraded: .init(
            blockedCapabilities: blockedCapabilities,
            isDegraded: !blockedCapabilities.isEmpty
        ),
        rootCause: .init(
            component: "local_runtime",
            detail: blockedCapabilities.isEmpty ? "ready" : "blocked capabilities for test",
            errorCode: blockedCapabilities.isEmpty ? "" : "capability_blocked"
        )
    )
    let data = try JSONEncoder().encode(snapshot)
    try data.write(to: baseDir.appendingPathComponent("hub_launch_status.json"), options: .atomic)
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

    func writeHubSkillsStoreForGovernanceSurface() throws {
        let storeDir = hubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

        let index = """
        {
          "schema_version": "skills_store_index.v1",
          "updated_at_ms": 42,
          "skills": [
            {
              "skill_id": "find-skills",
              "name": "Find Skills",
              "version": "1.0.0",
              "publisher_id": "xhub.official",
              "source_id": "builtin:catalog",
              "package_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              "install_hint": "Install from the Agent Baseline menu.",
              "capabilities_required": ["skills.search"],
              "risk_level": "low",
              "requires_grant": false,
              "trust_tier": "governed_package",
              "package_state": "active",
              "revoke_state": "active",
              "support_tier": "official",
              "entrypoint_runtime": "text",
              "entrypoint_command": "cat",
              "entrypoint_args": ["SKILL.md"],
              "compatibility_envelope": {
                "compatibility_state": "verified",
                "runtime_hosts": ["hub_runtime", "xt_runtime"],
                "protocol_versions": ["skills_abi_compat.v1"]
              },
              "quality_evidence_status": {
                "doctor": "passed",
                "smoke": "passed"
              },
              "artifact_integrity": {
                "package_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
                "manifest_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "package_format": "tar.gz",
                "package_size_bytes": 1024,
                "file_hash_count": 2,
                "signature": {
                  "algorithm": "ed25519",
                  "present": true,
                  "trusted_publisher": true
                }
              },
              "signature_verified": true,
              "signature_bypassed": false,
              "mapping_aliases_used": [],
              "defaults_applied": []
            },
            {
              "skill_id": "skill.demo",
              "name": "Demo Skill",
              "version": "2.0.0",
              "publisher_id": "publisher.demo",
              "source_id": "local:upload",
              "package_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "partial",
              "canonical_manifest_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
              "install_hint": "Review the mapping before enabling.",
              "capabilities_required": ["repo.read.status"],
              "risk_level": "medium",
              "requires_grant": false,
              "trust_tier": "governed_package",
              "package_state": "quarantined",
              "revoke_state": "active",
              "support_tier": "community",
              "entrypoint_runtime": "node",
              "entrypoint_command": "node",
              "entrypoint_args": ["index.js"],
              "compatibility_envelope": {
                "compatibility_state": "partial",
                "runtime_hosts": ["hub_runtime"]
              },
              "quality_evidence_status": {
                "doctor": "passed",
                "smoke": "missing"
              },
              "artifact_integrity": {
                "package_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
                "manifest_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                "package_format": "tar.gz",
                "package_size_bytes": 2048,
                "file_hash_count": 4,
                "signature": {
                  "algorithm": "ed25519",
                  "present": true,
                  "trusted_publisher": false
                }
              },
              "signature_verified": false,
              "signature_bypassed": false,
              "mapping_aliases_used": ["skill_id<-id"],
              "defaults_applied": ["network_policy.direct_network_forbidden"]
            },
            {
              "skill_id": "agent-browser",
              "name": "Agent Browser",
              "version": "1.0.0",
              "publisher_id": "xhub.official",
              "source_id": "builtin:catalog",
              "package_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
              "install_hint": "Enable through governed grant flow before browser-heavy tasks.",
              "capabilities_required": ["browser.read", "device.browser.control", "web.fetch"],
              "risk_level": "high",
              "requires_grant": true,
              "trust_tier": "governed_package",
              "package_state": "discovered",
              "revoke_state": "active",
              "support_tier": "official",
              "entrypoint_runtime": "text",
              "entrypoint_command": "cat",
              "entrypoint_args": ["SKILL.md"],
              "compatibility_envelope": {
                "compatibility_state": "verified",
                "runtime_hosts": ["hub_runtime", "xt_runtime"]
              },
              "quality_evidence_status": {
                "doctor": "passed",
                "smoke": "passed"
              },
              "artifact_integrity": {
                "package_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
                "manifest_sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                "package_format": "tar.gz",
                "package_size_bytes": 4096,
                "file_hash_count": 2,
                "signature": {
                  "algorithm": "ed25519",
                  "present": true,
                  "trusted_publisher": true
                }
              },
              "signature_verified": true,
              "signature_bypassed": false,
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
          "updated_at_ms": 42,
          "memory_core_pins": [],
          "global_pins": [
            {
              "skill_id": "find-skills",
              "package_sha256": "1111111111111111111111111111111111111111111111111111111111111111"
            },
            {
              "skill_id": "skill.demo",
              "package_sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
            }
          ],
          "project_pins": []
        }
        """
        try pins.write(to: storeDir.appendingPathComponent("skills_pins.json"), atomically: true, encoding: .utf8)

        let trusted = """
        {
          "schema_version": "xhub.trusted_publishers.v1",
          "updated_at_ms": 42,
          "publishers": [
            { "publisher_id": "xhub.official", "enabled": true },
            { "publisher_id": "publisher.demo", "enabled": false }
          ]
        }
        """
        try trusted.write(to: storeDir.appendingPathComponent("trusted_publishers.json"), atomically: true, encoding: .utf8)

        let revocations = """
        {
          "schema_version": "xhub.skill_revocations.v1",
          "updated_at_ms": 42,
          "revoked_sha256": [],
          "revoked_skill_ids": [],
          "revoked_publishers": []
        }
        """
        try revocations.write(to: storeDir.appendingPathComponent("skill_revocations.json"), atomically: true, encoding: .utf8)

        let lifecycle = """
        {
          "schema_version": "xhub.official_skill_package_lifecycle_snapshot.v1",
          "updated_at_ms": 42,
          "totals": {
            "packages_total": 3,
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
              "package_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
              "skill_id": "find-skills",
              "name": "Find Skills",
              "version": "1.0.0",
              "risk_level": "low",
              "requires_grant": false,
              "package_state": "active",
              "overall_state": "ready",
              "blocking_failures": 0,
              "transition_count": 1,
              "updated_at_ms": 42,
              "last_transition_at_ms": 42,
              "last_ready_at_ms": 42,
              "last_blocked_at_ms": 0
            },
            {
              "package_sha256": "3333333333333333333333333333333333333333333333333333333333333333",
              "skill_id": "agent-browser",
              "name": "Agent Browser",
              "version": "1.0.0",
              "risk_level": "high",
              "requires_grant": true,
              "package_state": "discovered",
              "overall_state": "blocked",
              "blocking_failures": 1,
              "transition_count": 1,
              "updated_at_ms": 42,
              "last_transition_at_ms": 42,
              "last_ready_at_ms": 0,
              "last_blocked_at_ms": 42
            }
          ]
        }
        """
        try lifecycle.write(to: storeDir.appendingPathComponent("official_skill_package_lifecycle.json"), atomically: true, encoding: .utf8)
    }

    func writeHubSkillsStoreForGovernedNetworkWrapper(projectID: String? = nil) throws {
        let resolvedProjectID = (projectID ?? self.projectID).trimmingCharacters(in: .whitespacesAndNewlines)
        let storeDir = hubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

        let index = #"""
        {
          "schema_version": "skills_store_index.v1",
          "updated_at_ms": 64,
          "skills": [
            {
              "skill_id": "tavily-websearch",
              "name": "Tavily Websearch",
              "version": "1.0.0",
              "description": "Governed web search wrapper.",
              "publisher_id": "xhub.official",
              "source_id": "builtin:catalog",
              "package_sha256": "abababababababababababababababababababababababababababababababab",
              "abi_compat_version": "skills_abi_compat.v1",
              "compatibility_state": "supported",
              "canonical_manifest_sha256": "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd",
              "install_hint": "Request a governed web grant before dispatch.",
              "intent_families": ["web.search_live", "web.fetch_live"],
              "capabilities_required": ["web.search", "web.fetch"],
              "capability_families": ["web.live"],
              "capability_profiles": ["observe_only", "browser_research"],
              "grant_floor": "privileged",
              "approval_floor": "none",
              "risk_level": "high",
              "requires_grant": true,
              "trust_tier": "governed_package",
              "package_state": "active",
              "revoke_state": "active",
              "support_tier": "official",
              "entrypoint_runtime": "text",
              "entrypoint_command": "cat",
              "entrypoint_args": ["SKILL.md"],
              "manifest_json": "{\"description\":\"Governed web search wrapper.\",\"capabilities_required\":[\"web.search\",\"web.fetch\"],\"governed_dispatch\":{\"tool\":\"web_search\",\"fixed_args\":{},\"passthrough_args\":[\"query\",\"grant_id\",\"timeout_sec\",\"max_results\",\"max_bytes\"],\"required_any\":[[\"query\"]],\"exactly_one_of\":[]},\"capability_families\":[\"web.live\"],\"capability_profiles\":[\"observe_only\",\"browser_research\"],\"grant_floor\":\"privileged\",\"approval_floor\":\"none\",\"risk_level\":\"high\",\"requires_grant\":true,\"side_effect_class\":\"external_side_effect\",\"input_schema_ref\":\"schema://tavily-websearch.input\",\"output_schema_ref\":\"schema://tavily-websearch.output\",\"timeout_ms\":20000,\"max_retries\":1}",
              "compatibility_envelope": {
                "compatibility_state": "verified",
                "runtime_hosts": ["hub_runtime", "xt_runtime"],
                "protocol_versions": ["skills_abi_compat.v1"]
              },
              "quality_evidence_status": {
                "doctor": "passed",
                "smoke": "passed"
              },
              "artifact_integrity": {
                "package_sha256": "abababababababababababababababababababababababababababababababab",
                "manifest_sha256": "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd",
                "package_format": "tar.gz",
                "package_size_bytes": 4096,
                "file_hash_count": 2,
                "signature": {
                  "algorithm": "ed25519",
                  "present": true,
                  "trusted_publisher": true
                }
              },
              "signature_verified": true,
              "signature_bypassed": false,
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
          "updated_at_ms": 64,
          "memory_core_pins": [],
          "global_pins": [],
          "project_pins": [
            {
              "project_id": "\(resolvedProjectID)",
              "skill_id": "tavily-websearch",
              "package_sha256": "abababababababababababababababababababababababababababababababab"
            }
          ]
        }
        """
        try pins.write(to: storeDir.appendingPathComponent("skills_pins.json"), atomically: true, encoding: .utf8)

        let trusted = """
        {
          "schema_version": "xhub.trusted_publishers.v1",
          "updated_at_ms": 64,
          "publishers": [
            { "publisher_id": "xhub.official", "enabled": true }
          ]
        }
        """
        try trusted.write(to: storeDir.appendingPathComponent("trusted_publishers.json"), atomically: true, encoding: .utf8)

        let revocations = """
        {
          "schema_version": "xhub.skill_revocations.v1",
          "updated_at_ms": 64,
          "revoked_sha256": [],
          "revoked_skill_ids": [],
          "revoked_publishers": []
        }
        """
        try revocations.write(to: storeDir.appendingPathComponent("skill_revocations.json"), atomically: true, encoding: .utf8)

        let lifecycle = """
        {
          "schema_version": "xhub.official_skill_package_lifecycle_snapshot.v1",
          "updated_at_ms": 64,
          "totals": {
            "packages_total": 1,
            "ready_total": 0,
            "degraded_total": 0,
            "blocked_total": 1,
            "not_installed_total": 0,
            "not_supported_total": 0,
            "revoked_total": 0,
            "active_total": 1
          },
          "packages": [
            {
              "package_sha256": "abababababababababababababababababababababababababababababababab",
              "skill_id": "tavily-websearch",
              "name": "Tavily Websearch",
              "version": "1.0.0",
              "risk_level": "high",
              "requires_grant": true,
              "package_state": "active",
              "overall_state": "blocked",
              "blocking_failures": 1,
              "transition_count": 1,
              "updated_at_ms": 64,
              "last_transition_at_ms": 64,
              "last_ready_at_ms": 0,
              "last_blocked_at_ms": 64
            }
          ]
        }
        """
        try lifecycle.write(to: storeDir.appendingPathComponent("official_skill_package_lifecycle.json"), atomically: true, encoding: .utf8)
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

    func makeRouterRegistryItem(
        skillId: String,
        packageSHA256: String,
        policyScope: String,
        officialPackage: Bool,
        capabilityFamilies: [String],
        capabilityProfiles: [String]
    ) -> SupervisorSkillRegistryItem {
        SupervisorSkillRegistryItem(
            skillId: skillId,
            displayName: skillId,
            description: "router test",
            intentFamilies: ["repo.read"],
            capabilityFamilies: capabilityFamilies,
            capabilityProfiles: capabilityProfiles,
            grantFloor: XTSkillGrantFloor.none.rawValue,
            approvalFloor: XTSkillApprovalFloor.none.rawValue,
            packageSHA256: packageSHA256,
            publisherID: officialPackage ? "xhub.official" : "publisher.community",
            sourceID: officialPackage ? "official:catalog" : "local:upload",
            officialPackage: officialPackage,
            capabilitiesRequired: ["repo.read"],
            governedDispatch: SupervisorGovernedSkillDispatch(
                tool: ToolName.git_status.rawValue,
                fixedArgs: [:],
                passthroughArgs: [],
                argAliases: [:],
                requiredAny: [],
                exactlyOneOf: []
            ),
            governedDispatchVariants: [],
            governedDispatchNotes: [],
            inputSchemaRef: "schema://\(skillId).input",
            outputSchemaRef: "schema://\(skillId).output",
            sideEffectClass: "read_only",
            riskLevel: .low,
            requiresGrant: false,
            policyScope: policyScope,
            timeoutMs: 5_000,
            maxRetries: 0,
            available: true
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
