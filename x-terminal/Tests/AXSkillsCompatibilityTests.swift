import Foundation
import Testing
@testable import XTerminal

struct AXSkillsCompatibilityTests {

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
        #expect(snapshot.items.count == 2)
        #expect(!snapshot.items.contains(where: { $0.skillId == "email.send.auto" }))

        let git = try #require(snapshot.items.first(where: { $0.skillId == "repo.git.status" }))
        #expect(git.displayName == "Git Status")
        #expect(git.riskLevel == .low)
        #expect(git.requiresGrant == false)
        #expect(git.sideEffectClass == "read_only")
        #expect(git.policyScope == "global")
        #expect(git.timeoutMs == 15_000)
        #expect(git.maxRetries == 0)

        let browser = try #require(snapshot.items.first(where: { $0.skillId == "browser.runtime.smoke" }))
        #expect(browser.riskLevel == .high)
        #expect(browser.requiresGrant)
        #expect(browser.sideEffectClass == "external_side_effect")
        #expect(browser.policyScope == "project")
        #expect(browser.timeoutMs == 45_000)
        #expect(browser.maxRetries == 2)
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

        #expect(memory.contains("skills_registry:"))
        #expect(memory.contains("repo.git.status"))
        #expect(memory.contains("browser.runtime.smoke"))
        #expect(memory.contains("grant=yes"))
        #expect(registrySnapshot?.items.count == 2)
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
              "manifest_json": "{\"description\":\"Read git working tree status for the active project.\",\"capabilities_required\":[\"repo.read.status\"],\"risk_level\":\"low\",\"input_schema_ref\":\"schema://repo.git.status.input\",\"output_schema_ref\":\"schema://repo.git.status.output\",\"timeout_ms\":15000,\"max_retries\":0}",
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
              "manifest_json": "{\"description\":\"Open the governed browser runtime and capture smoke evidence.\",\"capabilities_required\":[\"web.navigate\"],\"risk_level\":\"high\",\"input_schema_ref\":\"schema://browser.runtime.smoke.input\",\"output_schema_ref\":\"schema://browser.runtime.smoke.output\",\"timeout_ms\":45000,\"max_retries\":2}",
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
