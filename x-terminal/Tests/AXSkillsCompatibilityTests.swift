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
        #expect(snapshot.openClawCompatibleCount == 2)
        #expect(snapshot.partialCompatibilityCount == 1)
        #expect(snapshot.revokedMatchCount == 1)
        #expect(snapshot.trustEnabledPublisherCount == 1)
        #expect(snapshot.projectIndexEntries.count == 1)
        #expect(snapshot.globalIndexEntries.count == 1)
        #expect(snapshot.statusKind == .blocked)
        #expect(snapshot.conflictWarnings.contains(where: { $0.contains("skill.demo") }))
        #expect(snapshot.compatibilityExplain.contains("OpenClaw compatible skill installed"))

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
              "abi_compat_version": "openclaw_skill_abi_compat.v1",
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
              "abi_compat_version": "openclaw_skill_abi_compat.v1",
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

        let projectDir = skillsDir.appendingPathComponent("_projects/\(projectName)-12345678", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try "# Skills Index (project)\n\n- Demo Skill — 项目绑定（路径：<skills_dir>/_projects/\(projectName)-12345678/demo-skill）\n"
            .write(to: projectDir.appendingPathComponent("skills-index.md"), atomically: true, encoding: .utf8)
    }
}
