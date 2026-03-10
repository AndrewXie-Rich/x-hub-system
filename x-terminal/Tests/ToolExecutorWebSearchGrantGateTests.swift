import Testing
@testable import XTerminal

struct ToolExecutorWebSearchGrantGateTests {

    @Test
    func webSearchFailsClosedWithoutGrantAndKeepsStructuredHeader() async throws {
        let fixture = ToolExecutorProjectFixture(name: "web-search")
        defer { fixture.cleanup() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(tool: .web_search, args: ["query": .string("OpenAI API pricing")]),
            projectRoot: fixture.root
        )

        #expect(result.ok == false)
        let summary = toolSummaryObject(result.output)
        #expect(summary != nil)
        guard let summary else { return }

        #expect(jsonString(summary["tool"]) == ToolName.web_search.rawValue)
        #expect(jsonString(summary["query"]) == "OpenAI API pricing")
        #expect(jsonString(summary["grant_id"]) == nil)
        #expect((jsonString(summary["reason"]) ?? "").contains("high_risk_denied"))
        #expect(toolBody(result.output).contains("high_risk_denied"))
        #expect(toolBody(result.output).contains("capability_web_fetch"))
    }

    @Test
    func browserReadRejectsMissingURLWithStructuredFailure() async throws {
        let fixture = ToolExecutorProjectFixture(name: "browser-read")
        defer { fixture.cleanup() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(tool: .browser_read, args: [:]),
            projectRoot: fixture.root
        )

        #expect(result.ok == false)
        let summary = toolSummaryObject(result.output)
        #expect(summary != nil)
        guard let summary else { return }

        #expect(jsonString(summary["tool"]) == ToolName.browser_read.rawValue)
        #expect(jsonString(summary["reason"]) == "missing_url")
        #expect(toolBody(result.output) == "missing_url")
    }
}
