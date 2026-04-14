import Foundation
import Testing
@testable import XTerminal

struct XTAgentSkillPackageBuilderTests {
    @Test
    func buildPackagesEligibleFilesAndManifest() throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-skill-package-builder")
        defer { fixture.cleanup() }

        let repoRoot = fixture.root.appendingPathComponent("agent-main", isDirectory: true)
        let skillDir = repoRoot.appendingPathComponent("skills/coding-agent", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: skillDir.appendingPathComponent("dist", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: skillDir.appendingPathComponent("node_modules/pkg", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: skillDir.appendingPathComponent(".hidden", isDirectory: true),
            withIntermediateDirectories: true
        )

        try sampleCodingAgentSkill().write(
            to: skillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"name":"coding-agent"}"#.write(
            to: skillDir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )
        try "export function run() { return 'ok'; }\n".write(
            to: skillDir.appendingPathComponent("dist/main.js"),
            atomically: true,
            encoding: .utf8
        )
        try "console.log('ignored');\n".write(
            to: skillDir.appendingPathComponent("node_modules/pkg/index.js"),
            atomically: true,
            encoding: .utf8
        )
        try "console.log('hidden');\n".write(
            to: skillDir.appendingPathComponent(".hidden/private.js"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0x89, 0x50, 0x4e, 0x47]).write(
            to: skillDir.appendingPathComponent("preview.png")
        )

        let report = XTAgentSkillImportNormalizer.normalize(
            skillMarkdownURL: skillDir.appendingPathComponent("SKILL.md"),
            repoRoot: repoRoot
        )
        let result = try XTAgentSkillPackageBuilder.build(
            skillDirectoryURL: skillDir,
            importReport: report
        )
        defer { XTAgentSkillPackageBuilder.cleanup(result) }

        #expect(FileManager.default.fileExists(atPath: result.packageURL.path))
        #expect(result.includedRelativePaths == ["dist/main.js", "package.json", "skill.json", "SKILL.md"])

        let manifestData = try #require(result.manifestJSON.data(using: .utf8))
        let manifest = try #require(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        #expect(manifest["schema_version"] as? String == "xhub.skill_manifest.v1")
        #expect(manifest["skill_id"] as? String == report.manifest.skillId)
        #expect(manifest["version"] as? String == "1.2.3")
        #expect(manifest["description"] as? String == "Delegate coding tasks to governed agents.")
        #expect(manifest["intent_families"] as? [String] == ["repo.verify"])
        #expect(manifest["capability_families"] as? [String] == ["repo.verify"])
        #expect(manifest["capability_profiles"] as? [String] == [
            XTSkillCapabilityProfileID.observeOnly.rawValue,
            XTSkillCapabilityProfileID.codingExecute.rawValue,
        ])
        #expect(manifest["grant_floor"] as? String == XTSkillGrantFloor.none.rawValue)
        #expect(manifest["approval_floor"] as? String == XTSkillApprovalFloor.localApproval.rawValue)
        #expect(manifest["risk_level"] as? String == "medium")
        #expect(manifest["requires_grant"] as? Bool == false)

        let entrypoint = try #require(manifest["entrypoint"] as? [String: Any])
        #expect(entrypoint["runtime"] as? String == "node")
        #expect(entrypoint["command"] as? String == "node")
        #expect(entrypoint["args"] as? [String] == ["dist/main.js"])

        let files = try #require(manifest["files"] as? [[String: Any]])
        #expect(files.count == 4)
        #expect(files.contains(where: { ($0["path"] as? String) == "SKILL.md" }))
        #expect(files.contains(where: { ($0["path"] as? String) == "dist/main.js" }))
        #expect(files.contains(where: { ($0["path"] as? String) == "package.json" }))
        #expect(files.contains(where: { ($0["path"] as? String) == "skill.json" }))
        #expect(files.contains(where: { (($0["path"] as? String) ?? "").contains("node_modules") }) == false)

        let extractDir = fixture.root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        let extractResult = try ProcessCapture.run(
            "/usr/bin/tar",
            ["-xzf", result.packageURL.path, "-C", extractDir.path],
            cwd: nil,
            timeoutSec: 10.0
        )
        #expect(extractResult.exitCode == 0)

        let packagedSkillManifestData = try Data(contentsOf: extractDir.appendingPathComponent("skill.json"))
        let packagedSkillManifest = try #require(
            JSONSerialization.jsonObject(with: packagedSkillManifestData) as? [String: Any]
        )
        #expect(packagedSkillManifest["skill_id"] as? String == report.manifest.skillId)
        #expect(packagedSkillManifest["files"] == nil)
        #expect(packagedSkillManifest["capability_families"] as? [String] == ["repo.verify"])
        #expect(packagedSkillManifest["approval_floor"] as? String == XTSkillApprovalFloor.localApproval.rawValue)

        let cleanupPath = result.cleanupDirectoryURL.path
        XTAgentSkillPackageBuilder.cleanup(result)
        #expect(FileManager.default.fileExists(atPath: cleanupPath) == false)
    }

    @Test
    func buildPreservesCompanionManifestFieldsForLocalVisionSkill() throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-skill-package-builder-local-vision")
        defer { fixture.cleanup() }

        let repoRoot = fixture.root.appendingPathComponent("agent-main", isDirectory: true)
        let skillDir = repoRoot.appendingPathComponent("skills/local-vision", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try sampleLocalVisionSkill().write(
            to: skillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try sampleLocalVisionSkillManifest().write(
            to: skillDir.appendingPathComponent("skill.json"),
            atomically: true,
            encoding: .utf8
        )
        try "print('ok')\n".write(
            to: skillDir.appendingPathComponent("main.py"),
            atomically: true,
            encoding: .utf8
        )

        let report = XTAgentSkillImportNormalizer.normalize(
            skillMarkdownURL: skillDir.appendingPathComponent("SKILL.md"),
            repoRoot: repoRoot
        )
        let result = try XTAgentSkillPackageBuilder.build(
            skillDirectoryURL: skillDir,
            importReport: report
        )
        defer { XTAgentSkillPackageBuilder.cleanup(result) }

        let manifestData = try #require(result.manifestJSON.data(using: .utf8))
        let manifest = try #require(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        #expect(manifest["skill_id"] as? String == "vision.local.preview")
        #expect(manifest["name"] as? String == "Local Vision Preview")
        #expect(manifest["capabilities_required"] as? [String] == ["ai.vision.local"])
        #expect(manifest["intent_families"] as? [String] == ["ai.vision.local"])
        #expect(manifest["capability_families"] as? [String] == ["ai.vision.local"])
        #expect(manifest["capability_profiles"] as? [String] == [XTSkillCapabilityProfileID.observeOnly.rawValue])
        #expect(manifest["approval_floor"] as? String == XTSkillApprovalFloor.none.rawValue)
        #expect(manifest["input_schema_ref"] as? String == "schema://vision.local.preview.input")
        #expect(manifest["files"] as? [[String: Any]] != nil)
    }

    private func sampleCodingAgentSkill() -> String {
        """
        ---
        name: coding-agent
        version: 1.2.3
        description: Delegate coding tasks to governed agents.
        ---

        # Coding Agent

        Use bash for coding work.
        """
    }

    private func sampleLocalVisionSkill() -> String {
        """
        ---
        name: local-vision
        description: Use Hub-governed local vision understanding.
        ---

        # Local Vision

        Inspect screenshots with the local vision runtime.
        """
    }

    private func sampleLocalVisionSkillManifest() -> String {
        """
        {
          "schema_version": "xhub.skill_manifest.v1",
          "skill_id": "vision.local.preview",
          "name": "Local Vision Preview",
          "version": "0.2.0",
          "description": "Use Hub-governed local vision understanding.",
          "entrypoint": {
            "runtime": "python",
            "command": "python3",
            "args": ["main.py"]
          },
          "capabilities_required": ["ai.vision.local"],
          "input_schema_ref": "schema://vision.local.preview.input"
        }
        """
    }
}
