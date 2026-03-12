import Foundation
import Testing
@testable import XTerminal

struct XTAgentSkillImportNormalizerTests {
    @Test
    func normalizeCodingAgentSkillMapsToGovernedCoderSkill() throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-import-normalize")
        defer { fixture.cleanup() }

        let repoRoot = fixture.root.appendingPathComponent("agent-main", isDirectory: true)
        let skillDir = repoRoot.appendingPathComponent("skills/coding-agent", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try sampleCodingAgentSkill().write(
            to: skillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let report = XTAgentSkillImportNormalizer.normalize(
            skillMarkdownURL: skillDir.appendingPathComponent("SKILL.md"),
            repoRoot: repoRoot
        )

        #expect(report.findings.isEmpty)
        #expect(report.manifest.schemaVersion == XTAgentSkillImportManifest.currentSchemaVersion)
        #expect(report.manifest.source == "agent")
        #expect(report.manifest.sourceRef == "skills/coding-agent/SKILL.md")
        #expect(report.manifest.skillId == "coder.run.command")
        #expect(report.manifest.displayName == "coding-agent")
        #expect(report.manifest.normalizedCapabilities == ["repo.exec.agent"])
        #expect(report.manifest.riskLevel == "medium")
        #expect(report.manifest.requiresGrant == false)
        #expect(report.manifest.preflightStatus == XTAgentImportPreflightStatus.passed.rawValue)
    }

    @Test
    func worldWritableSkillPathQuarantinesImport() throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-import-world-writable")
        defer { fixture.cleanup() }

        let repoRoot = fixture.root.appendingPathComponent("agent-main", isDirectory: true)
        let skillDir = repoRoot.appendingPathComponent("skills/coding-agent", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let skillURL = skillDir.appendingPathComponent("SKILL.md")
        try sampleCodingAgentSkill().write(to: skillURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: skillURL.path)

        let report = XTAgentSkillImportNormalizer.normalize(
            skillMarkdownURL: skillURL,
            repoRoot: repoRoot
        )

        #expect(report.manifest.preflightStatus == XTAgentImportPreflightStatus.quarantined.rawValue)
        #expect(report.findings.contains(where: { $0.code == "world_writable_path" }))
    }

    @Test
    func symlinkEscapeQuarantinesImport() throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-import-symlink-escape")
        let externalFixture = ToolExecutorProjectFixture(name: "agent-import-external")
        defer {
            fixture.cleanup()
            externalFixture.cleanup()
        }

        let repoRoot = fixture.root.appendingPathComponent("agent-main", isDirectory: true)
        let linkedDir = repoRoot.appendingPathComponent("skills/linked-agent", isDirectory: true)
        try FileManager.default.createDirectory(at: linkedDir.deletingLastPathComponent(), withIntermediateDirectories: true)

        let externalSkillDir = externalFixture.root.appendingPathComponent("external-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: externalSkillDir, withIntermediateDirectories: true)
        let externalSkillURL = externalSkillDir.appendingPathComponent("SKILL.md")
        try sampleCodingAgentSkill().write(to: externalSkillURL, atomically: true, encoding: .utf8)

        try FileManager.default.createSymbolicLink(
            at: linkedDir,
            withDestinationURL: externalSkillDir
        )

        let report = XTAgentSkillImportNormalizer.normalize(
            skillMarkdownURL: linkedDir.appendingPathComponent("SKILL.md"),
            repoRoot: repoRoot
        )

        #expect(report.manifest.preflightStatus == XTAgentImportPreflightStatus.quarantined.rawValue)
        #expect(report.findings.contains(where: { $0.code == "symlink_escape" }))
    }

    @Test
    func unsafeUpstreamBehaviorQuarantinesImport() throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-import-unsafe-upstream")
        defer { fixture.cleanup() }

        let repoRoot = fixture.root.appendingPathComponent("agent-main", isDirectory: true)
        let skillDir = repoRoot.appendingPathComponent("skills/coding-agent", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try sampleUnsafeSkill().write(
            to: skillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let report = XTAgentSkillImportNormalizer.normalize(
            skillMarkdownURL: skillDir.appendingPathComponent("SKILL.md"),
            repoRoot: repoRoot
        )

        #expect(report.manifest.preflightStatus == XTAgentImportPreflightStatus.quarantined.rawValue)
        #expect(report.findings.contains(where: { $0.code == "unsafe_upstream_behavior" }))
    }

    @Test
    func directLocalExecutionDeniedOutsideDeveloperMode() throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-import-gate-normal")
        defer { fixture.cleanup() }

        let report = try codingAgentReport(fixture: fixture)
        let verdict = XTAgentSkillImportNormalizer.directLocalExecutionVerdict(
            report: report,
            developerMode: false
        )

        #expect(verdict.schemaVersion == XTAgentDirectLocalExecutionVerdict.currentSchemaVersion)
        #expect(verdict.skillId == "coder.run.command")
        #expect(verdict.decision == XTAgentDirectLocalExecutionDecision.deny.rawValue)
        #expect(verdict.reasonCode == "hub_stage_required")
    }

    @Test
    func developerModeAllowsMediumRiskDirectLocalExecution() throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-import-gate-dev")
        defer { fixture.cleanup() }

        let report = try codingAgentReport(fixture: fixture)
        let verdict = XTAgentSkillImportNormalizer.directLocalExecutionVerdict(
            report: report,
            developerMode: true
        )

        #expect(verdict.decision == XTAgentDirectLocalExecutionDecision.allow.rawValue)
        #expect(verdict.reasonCode == "developer_mode_low_risk_only")
    }

    @Test
    func highRiskImportStillRequiresHubGovernanceInDeveloperMode() throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-import-gate-high-risk")
        defer { fixture.cleanup() }

        let repoRoot = fixture.root.appendingPathComponent("agent-main", isDirectory: true)
        let skillDir = repoRoot.appendingPathComponent("skills/browser-operator", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try sampleBrowserSkill().write(
            to: skillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let report = XTAgentSkillImportNormalizer.normalize(
            skillMarkdownURL: skillDir.appendingPathComponent("SKILL.md"),
            repoRoot: repoRoot
        )

        #expect(report.manifest.riskLevel == "high")
        #expect(report.manifest.requiresGrant)

        let verdict = XTAgentSkillImportNormalizer.directLocalExecutionVerdict(
            report: report,
            developerMode: true
        )

        #expect(verdict.decision == XTAgentDirectLocalExecutionDecision.deny.rawValue)
        #expect(verdict.reasonCode == "requires_hub_governance")
    }

    @Test
    func buildScanInputCapturesEligibleFilesAndSkipsHiddenPaths() throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-import-scan-input")
        defer { fixture.cleanup() }

        let skillDir = fixture.root.appendingPathComponent("skills/coding-agent", isDirectory: true)
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
        try "export const run = () => 'ok';\n".write(
            to: skillDir.appendingPathComponent("dist/main.js"),
            atomically: true,
            encoding: .utf8
        )
        try "eval('bad');\n".write(
            to: skillDir.appendingPathComponent("node_modules/pkg/index.js"),
            atomically: true,
            encoding: .utf8
        )
        try "eval('hidden');\n".write(
            to: skillDir.appendingPathComponent(".hidden/ignored.js"),
            atomically: true,
            encoding: .utf8
        )

        let payload = XTAgentSkillImportNormalizer.buildScanInput(skillDirectoryURL: skillDir)

        #expect(payload.schemaVersion == XTAgentSkillScanInputPayload.currentSchemaVersion)
        #expect(payload.files.contains(where: { $0.path == "SKILL.md" }))
        #expect(payload.files.contains(where: { $0.path == "dist/main.js" }))
        #expect(payload.files.contains(where: { $0.path.contains("node_modules") }) == false)
        #expect(payload.files.contains(where: { $0.path.contains(".hidden") }) == false)
    }

    @Test
    func quarantinedImportCannotRunDirectLocalEvenInDeveloperMode() throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-import-gate-quarantine")
        defer { fixture.cleanup() }

        let repoRoot = fixture.root.appendingPathComponent("agent-main", isDirectory: true)
        let skillDir = repoRoot.appendingPathComponent("skills/coding-agent", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try sampleUnsafeSkill().write(
            to: skillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let report = XTAgentSkillImportNormalizer.normalize(
            skillMarkdownURL: skillDir.appendingPathComponent("SKILL.md"),
            repoRoot: repoRoot
        )

        let verdict = XTAgentSkillImportNormalizer.directLocalExecutionVerdict(
            report: report,
            developerMode: true
        )

        #expect(verdict.decision == XTAgentDirectLocalExecutionDecision.deny.rawValue)
        #expect(verdict.reasonCode == "preflight_quarantined")
    }

    private func sampleCodingAgentSkill() -> String {
        """
        ---
        name: coding-agent
        description: 'Delegate coding tasks to Codex, Claude Code, or Pi agents via background process.'
        ---

        # Coding Agent

        Use bash for coding work.
        """
    }

    private func sampleUnsafeSkill() -> String {
        """
        ---
        name: coding-agent
        description: 'Delegate coding tasks to Codex.'
        ---

        # Coding Agent

        This skill uses prompt mutation hooks and can dangerously-skip-permissions.
        """
    }

    private func sampleBrowserSkill() -> String {
        """
        ---
        name: browser-operator
        description: 'Drive browser workflows for operator tasks.'
        ---

        # Browser Operator

        Open tabs and navigate pages.
        """
    }

    private func codingAgentReport(
        fixture: ToolExecutorProjectFixture
    ) throws -> XTAgentSkillImportPreflightReport {
        let repoRoot = fixture.root.appendingPathComponent("agent-main", isDirectory: true)
        let skillDir = repoRoot.appendingPathComponent("skills/coding-agent", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try sampleCodingAgentSkill().write(
            to: skillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        return XTAgentSkillImportNormalizer.normalize(
            skillMarkdownURL: skillDir.appendingPathComponent("SKILL.md"),
            repoRoot: repoRoot
        )
    }
}
