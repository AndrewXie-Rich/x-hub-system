import Foundation
import Testing
@testable import XTerminal

struct XTAgentSkillImportNormalizerTests {
    @Test
    func hubRecordReviewSurfacesVetterFieldsAndCounts() {
        let review = XTAgentSkillImportReviewFormatter.formatHubRecordReview(
            recordJSON: """
            {
              "staging_id": "stage-123",
              "status": "reviewed",
              "audit_ref": "audit-9",
              "requested_by": "xt-ui",
              "note": "imported from local repo",
              "vetter_status": "blocked",
              "vetter_audit_ref": "vet-audit-1",
              "vetter_report_ref": "vet-report-2",
              "vetter_critical_count": 2,
              "vetter_warn_count": 3,
              "promotion_blocked_reason": "vetter_blocked",
              "enabled_package_sha256": "0123456789abcdef0123456789abcdef",
              "enabled_scope": "device",
              "import_manifest": {
                "skill_id": "agent-browser",
                "display_name": "Agent Browser",
                "preflight_status": "passed",
                "risk_level": "high",
                "policy_scope": "device",
                "requires_grant": true,
                "normalized_capabilities": ["web.fetch", "device.browser.control"],
                "intent_families": ["browser.observe", "browser.interact", "web.fetch_live"],
                "capability_profile_hints": ["observe_only", "browser_research", "browser_operator"],
                "approval_floor_hint": "local_approval"
              },
              "canonical_capability_derivation": {
                "intent_families": ["browser.observe", "browser.interact", "web.fetch_live"],
                "capability_profiles": ["observe_only", "browser_research", "browser_operator"],
                "approval_floor": "local_approval"
              },
              "capability_hint_validation": {
                "checked": true,
                "fail_closed": false,
                "mismatches": []
              },
              "findings": [
                { "code": "network_access", "detail": "uses outbound browser navigation" }
              ]
            }
            """,
            fallbackStagingId: "fallback-stage",
            fallbackSkillId: "fallback-skill"
        )

        #expect(review.contains("staging_id: stage-123"))
        #expect(review.contains("audit_ref: audit-9"))
        #expect(review.contains("requested_by: xt-ui"))
        #expect(review.contains("vetter: blocked"))
        #expect(review.contains("vetter_counts: critical=2 warn=3"))
        #expect(review.contains("vetter_audit_ref: vet-audit-1"))
        #expect(review.contains("vetter_report_ref: vet-report-2"))
        #expect(review.contains("enabled_package: 0123456789ab"))
        #expect(review.contains("enabled_scope: device"))
        #expect(review.contains("governance:"))
        #expect(review.contains("- trust_root: governed package promoted @0123456789ab"))
        #expect(review.contains("- pinned_version: @0123456789ab scope=device"))
        #expect(review.contains("- runner_requirement: Hub-governed import runner"))
        #expect(review.contains("- compatibility_status: pending verify | preflight=passed vetter=blocked"))
        #expect(review.contains("- preflight_result: grant required before enable | vetter_blocked"))
        #expect(review.contains("- intent_families: browser.observe, browser.interact, web.fetch_live"))
        #expect(review.contains("- capability_profile_hints: observe_only, browser_research, browser_operator"))
        #expect(review.contains("- approval_floor_hint: local_approval"))
        #expect(review.contains("- canonical_capability_profiles: observe_only, browser_research, browser_operator"))
        #expect(review.contains("- hint_validation: checked=true fail_closed=false mismatches=0"))
        #expect(review.contains("capabilities: web.fetch, device.browser.control"))
        #expect(review.contains("- network_access: uses outbound browser navigation"))
    }

    @Test
    func hubRecordReviewFallsBackWhenJSONMissing() {
        let review = XTAgentSkillImportReviewFormatter.formatHubRecordReview(
            recordJSON: "  ",
            fallbackStagingId: "fallback-stage",
            fallbackSkillId: "fallback-skill"
        )

        #expect(review.contains("staging_id: fallback-stage"))
        #expect(review.contains("skill_id: fallback-skill"))
        #expect(review.contains("Hub did not return structured review JSON."))
    }

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
        #expect(report.manifest.intentFamilies == ["repo.verify"])
        #expect(report.manifest.capabilityProfileHints == [
            XTSkillCapabilityProfileID.observeOnly.rawValue,
            XTSkillCapabilityProfileID.codingExecute.rawValue,
        ])
        #expect(report.manifest.approvalFloorHint == XTSkillApprovalFloor.localApproval.rawValue)
        #expect(report.manifest.riskLevel == "medium")
        #expect(report.manifest.requiresGrant == false)
        #expect(report.manifest.preflightStatus == XTAgentImportPreflightStatus.passed.rawValue)
    }

    @Test
    func normalizeCompanionManifestPreservesLocalVisionCapabilitySemantics() throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-import-local-vision")
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

        let report = XTAgentSkillImportNormalizer.normalize(
            skillMarkdownURL: skillDir.appendingPathComponent("SKILL.md"),
            repoRoot: repoRoot
        )

        #expect(report.findings.isEmpty)
        #expect(report.manifest.skillId == "vision.local.preview")
        #expect(report.manifest.displayName == "Local Vision Preview")
        #expect(report.manifest.normalizedCapabilities == ["ai.vision.local"])
        #expect(report.manifest.intentFamilies == ["ai.vision.local"])
        #expect(report.manifest.capabilityProfileHints == [
            XTSkillCapabilityProfileID.observeOnly.rawValue,
        ])
        #expect(report.manifest.approvalFloorHint == XTSkillApprovalFloor.none.rawValue)
        #expect(report.manifest.riskLevel == "low")
        #expect(report.manifest.requiresGrant == false)
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
        #expect(report.manifest.intentFamilies == ["web.fetch_live", "browser.observe"])
        #expect(report.manifest.capabilityProfileHints == [
            XTSkillCapabilityProfileID.observeOnly.rawValue,
            XTSkillCapabilityProfileID.browserResearch.rawValue,
        ])
        #expect(report.manifest.approvalFloorHint == XTSkillApprovalFloor.none.rawValue)

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

    private func sampleLocalVisionSkill() -> String {
        """
        ---
        name: local-vision
        description: 'Use local multimodal understanding with Hub-governed routing.'
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
