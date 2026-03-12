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
        #expect(result.includedRelativePaths == ["dist/main.js", "package.json", "SKILL.md"])

        let manifestData = try #require(result.manifestJSON.data(using: .utf8))
        let manifest = try #require(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        #expect(manifest["schema_version"] as? String == "xhub.skill_manifest.v1")
        #expect(manifest["skill_id"] as? String == report.manifest.skillId)
        #expect(manifest["version"] as? String == "1.2.3")
        #expect(manifest["description"] as? String == "Delegate coding tasks to governed agents.")

        let entrypoint = try #require(manifest["entrypoint"] as? [String: Any])
        #expect(entrypoint["runtime"] as? String == "node")
        #expect(entrypoint["command"] as? String == "node")
        #expect(entrypoint["args"] as? [String] == ["dist/main.js"])

        let files = try #require(manifest["files"] as? [[String: Any]])
        #expect(files.count == 3)
        #expect(files.contains(where: { ($0["path"] as? String) == "SKILL.md" }))
        #expect(files.contains(where: { ($0["path"] as? String) == "dist/main.js" }))
        #expect(files.contains(where: { ($0["path"] as? String) == "package.json" }))
        #expect(files.contains(where: { (($0["path"] as? String) ?? "").contains("node_modules") }) == false)

        let cleanupPath = result.cleanupDirectoryURL.path
        XTAgentSkillPackageBuilder.cleanup(result)
        #expect(FileManager.default.fileExists(atPath: cleanupPath) == false)
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
}
