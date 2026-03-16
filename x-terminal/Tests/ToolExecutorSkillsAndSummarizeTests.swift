import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct ToolExecutorSkillsAndSummarizeTests {

    @Test
    func skillsSearchFallsBackToLocalHubIndex() async throws {
        let fixture = ToolExecutorProjectFixture(name: "skills-search-local-index")
        defer { fixture.cleanup() }

        let hubBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-hub-skills-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: hubBase) }
        try writeLocalHubSkillsIndex(baseDir: hubBase)

        HubPaths.setPinnedBaseDirOverride(hubBase)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .skills_search,
                args: [
                    "query": .string("summarize"),
                    "source_filter": .string("builtin:catalog"),
                    "limit": .number(5),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["tool"]) == ToolName.skills_search.rawValue)
        #expect(jsonString(summary["source"]) == "local_hub_index")
        #expect(jsonNumber(summary["results_count"]) == 1)
        let first = try #require(jsonArray(summary["results"])?.first)
        #expect(jsonString(jsonObject(first)?["risk_level"]) == "medium")
        #expect(jsonBool(jsonObject(first)?["requires_grant"]) == false)
        #expect(jsonString(jsonObject(first)?["side_effect_class"]) == "read_only")
        #expect(toolBody(result.output).contains("Summarize [summarize]"))
        #expect(toolBody(result.output).contains("risk=medium grant=no side_effect=read_only"))
    }

    @Test
    func agentImportRecordReturnsStructuredHubReview() async throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-import-record-review")
        defer { fixture.cleanup() }

        HubIPCClient.installAgentImportRecordOverrideForTesting { lookup in
            #expect(lookup.stagingId == "stage-123")
            #expect(lookup.selector == nil)
            #expect(lookup.skillId == nil)
            #expect(lookup.projectId == nil)
            return HubIPCClient.AgentImportRecordResult(
                ok: true,
                source: "hub_runtime_grpc",
                selector: nil,
                stagingId: lookup.stagingId,
                status: "staged_with_warnings",
                auditRef: "audit-stage-123",
                schemaVersion: "xhub.agent_import_record.v1",
                skillId: "agent-browser",
                projectId: nil,
                recordJSON: #"""
                {
                  "staging_id": "stage-123",
                  "status": "staged_with_warnings",
                  "audit_ref": "audit-stage-123",
                  "requested_by": "xt-ui",
                  "note": "ui_import:agent-browser",
                  "vetter_status": "warn_only",
                  "vetter_critical_count": 0,
                  "vetter_warn_count": 2,
                  "vetter_audit_ref": "vet-audit-123",
                  "vetter_report_ref": "skills_store/agent_imports/reports/stage-123.json",
                  "promotion_blocked_reason": "",
                  "findings": [
                    { "code": "warn-dynamic", "detail": "dynamic dispatch requires review" }
                  ],
                  "import_manifest": {
                    "skill_id": "agent-browser",
                    "display_name": "Agent Browser",
                    "preflight_status": "passed",
                    "risk_level": "high",
                    "policy_scope": "project",
                    "requires_grant": true,
                    "normalized_capabilities": ["browser.read", "browser.write"]
                  }
                }
                """#,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetAgentImportRecordOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .agentImportRecord,
                args: [
                    "staging_id": .string("stage-123"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["tool"]) == ToolName.agentImportRecord.rawValue)
        #expect(jsonString(summary["source"]) == "hub_runtime_grpc")
        #expect(jsonString(summary["staging_id"]) == "stage-123")
        #expect(jsonString(summary["skill_id"]) == "agent-browser")
        #expect(jsonString(summary["vetter_status"]) == "warn_only")
        #expect(jsonNumber(summary["vetter_warn_count"]) == 2)
        #expect(jsonString(summary["vetter_report_ref"]) == "skills_store/agent_imports/reports/stage-123.json")

        let body = toolBody(result.output)
        #expect(body.contains("vetter: warn_only"))
        #expect(body.contains("vetter_report_ref: skills_store/agent_imports/reports/stage-123.json"))
        #expect(body.contains("findings (1):"))
    }

    @Test
    func agentImportRecordDefaultsToLatestProjectSelector() async throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-import-record-selector")
        defer { fixture.cleanup() }

        let projectID = AXProjectRegistryStore.projectId(forRoot: fixture.root)
        #expect(!projectID.isEmpty)

        HubIPCClient.installAgentImportRecordOverrideForTesting { lookup in
            #expect(lookup.stagingId == nil)
            #expect(lookup.selector == "latest_for_project")
            #expect(lookup.skillId == nil)
            #expect(lookup.projectId == projectID)
            return HubIPCClient.AgentImportRecordResult(
                ok: true,
                source: "hub_runtime_grpc",
                selector: lookup.selector,
                stagingId: "stage-latest-project",
                status: "staged",
                auditRef: "audit-stage-latest-project",
                schemaVersion: "xhub.agent_import_record.v1",
                skillId: "summarize",
                projectId: lookup.projectId,
                recordJSON: """
                {
                  "staging_id": "stage-latest-project",
                  "status": "staged",
                  "audit_ref": "audit-stage-latest-project",
                  "project_id": "\(projectID)",
                  "vetter_status": "passed",
                  "vetter_critical_count": 0,
                  "vetter_warn_count": 0,
                  "import_manifest": {
                    "skill_id": "summarize",
                    "display_name": "Summarize",
                    "preflight_status": "passed",
                    "risk_level": "low",
                    "policy_scope": "project",
                    "requires_grant": false,
                    "normalized_capabilities": ["document.summarize"]
                  }
                }
                """,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetAgentImportRecordOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .agentImportRecord,
                args: [:]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["selector"]) == "latest_for_project")
        #expect(jsonString(summary["project_id"]) == projectID)
        #expect(jsonString(summary["skill_id"]) == "summarize")
        #expect(jsonString(summary["staging_id"]) == "stage-latest-project")
    }

    @Test
    func summarizeProducesGovernedBulletSummaryFromInlineText() async throws {
        let fixture = ToolExecutorProjectFixture(name: "summarize-inline")
        defer { fixture.cleanup() }

        let text = """
        Incident report: browser runtime failed to load the secure page after a connector change.
        Impact: login automation was blocked for the release checklist.
        Risk: temporary fallback scripts might bypass the governed grant boundary and expose tokens.
        Action: require governed browser.read, rotate the temporary credentials, and rerun smoke evidence.
        """

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .summarize,
                args: [
                    "text": .string(text),
                    "focus": .string("risk"),
                    "format": .string("bullets"),
                    "max_chars": .number(420),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["tool"]) == ToolName.summarize.rawValue)
        #expect(jsonString(summary["source_kind"]) == "text")
        #expect(jsonString(summary["format"]) == "bullets")
        #expect(jsonBool(summary["source_truncated"]) == false)
        #expect((jsonNumber(summary["summary_chars"]) ?? 0) > 0)

        let body = toolBody(result.output)
        #expect(body.contains("Title: inline_text"))
        #expect(body.contains("Risk: temporary fallback scripts"))
        #expect(body.contains("- "))
    }

    @Test
    func summarizeReadsLocalProjectFile() async throws {
        let fixture = ToolExecutorProjectFixture(name: "summarize-path")
        defer { fixture.cleanup() }

        let fileURL = fixture.root.appendingPathComponent("NOTES.md")
        try """
        Release Notes

        The hub memory path is now the default source for supervisor recall.
        Operators can still choose a local overlay for sensitive experiments.
        The next milestone is wiring summarize and find-skills into governed runtime tools.
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .summarize,
                args: [
                    "path": .string("NOTES.md"),
                    "max_chars": .number(360),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["source_kind"]) == "path")
        #expect(jsonString(summary["source_title"]) == "NOTES.md")
        #expect(toolBody(result.output).contains("Release Notes"))
        #expect(toolBody(result.output).contains("governed runtime tools"))
    }

    private func writeLocalHubSkillsIndex(baseDir: URL) throws {
        let storeDir = baseDir.appendingPathComponent("skills_store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let index = #"""
        {
          "schema_version": "skills_store_index.v1",
          "updated_at_ms": 2468,
          "skills": [
            {
              "skill_id": "find-skills",
              "name": "Find Skills",
              "version": "1.1.0",
              "description": "Discover governed Agent skills from X-Hub.",
              "publisher_id": "xhub.official",
              "capabilities_required": ["skills.search"],
              "source_id": "builtin:catalog",
              "package_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
              "install_hint": "Pin from the Agent Baseline.",
              "risk_level": "low",
              "requires_grant": false,
              "side_effect_class": "read_only"
            },
            {
              "skill_id": "summarize",
              "name": "Summarize",
              "version": "1.1.0",
              "description": "Summarize webpages, PDFs, and long documents through governed runtime tools.",
              "publisher_id": "xhub.official",
              "capabilities_required": ["document.summarize"],
              "source_id": "builtin:catalog",
              "package_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
              "install_hint": "Pin from the Agent Baseline.",
              "risk_level": "medium",
              "requires_grant": false,
              "side_effect_class": "read_only"
            }
          ]
        }
        """#
        try index.write(to: storeDir.appendingPathComponent("skills_store_index.json"), atomically: true, encoding: .utf8)
    }
}
