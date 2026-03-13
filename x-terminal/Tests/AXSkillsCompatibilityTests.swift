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
        #expect(snapshot.memorySource == "hub_skill_registry")
        #expect(snapshot.items.count == 3)
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
        #expect(memory.contains("dispatch=git_status"))
        #expect(memory.contains("dispatch=device.browser.control"))
        #expect(memory.contains("payload: fixed=action=open_url"))
        #expect(memory.contains("required_any=url"))
        #expect(memory.contains("args=url"))
        #expect(memory.contains("variant: actions=open/open_url/navigate/goto/visit -> device.browser.control"))
        #expect(memory.contains("variant: actions=snapshot/inspect/extract -> device.browser.control"))
        #expect(!memory.contains("dispatch_note: actions=open/navigate/snapshot/extract/click/type/upload -> device.browser.control"))
        #expect(registrySnapshot?.items.count == 3)
        #expect(resolvedCache?.items.count == 3)
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
        #expect(snapshot.source == "hub_resolved_skills_snapshot")
        #expect(snapshot.resolvedSnapshotId == "xt-resolved-skills-12345678-1000")
        #expect(snapshot.resolvedAtMs == 1_000)
        #expect(snapshot.expiresAtMs == 121_000)
        #expect(snapshot.hubIndexUpdatedAtMs == 42)
        #expect(snapshot.auditRef == "audit-xt-w3-34-i-resolved-skills-12345678")
        #expect(snapshot.grantSnapshotRef == "grant-chain:12345678:refresh_required")
        #expect(snapshot.items.count == 3)
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
