import Foundation
import Testing
@testable import XTerminal

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
        #expect(toolBody(result.output).contains("Summarize [summarize]"))
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
              "install_hint": "Pin from the Agent Baseline."
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
              "install_hint": "Pin from the Agent Baseline."
            }
          ]
        }
        """#
        try index.write(to: storeDir.appendingPathComponent("skills_store_index.json"), atomically: true, encoding: .utf8)
    }
}
