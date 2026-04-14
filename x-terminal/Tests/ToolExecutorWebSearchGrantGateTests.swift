import Testing
@testable import XTerminal

struct ToolExecutorWebSearchGrantGateTests {
    private func enableNetworkToolProfile(for fixture: ToolExecutorProjectFixture) throws {
        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingToolPolicy(profile: ToolProfile.full.rawValue)
        try AXProjectStore.saveConfig(config, for: ctx)
    }

    @Test
    func webSearchFailsClosedWithoutGrantAndKeepsStructuredHeader() async throws {
        let fixture = ToolExecutorProjectFixture(name: "web-search")
        defer { fixture.cleanup() }
        try enableNetworkToolProfile(for: fixture)

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
        try enableNetworkToolProfile(for: fixture)

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

    @Test
    func grantRequestIdIsNotAcceptedAsExecutableGrantToken() async throws {
        let fixture = ToolExecutorProjectFixture(name: "web-search-request-id-not-executable")
        defer { fixture.cleanup() }
        try enableNetworkToolProfile(for: fixture)

        let grantRequestId = "grant-request-web-1"
        let executionGrantId = try #require(
            await ToolExecutor.activateHighRiskGrantForSupervisor(
                projectRoot: fixture.root,
                capability: "web.fetch",
                grantRequestId: grantRequestId,
                fallbackSeconds: 180
            )
        )
        #expect(executionGrantId.isEmpty == false)
        #expect(executionGrantId != grantRequestId)

        let requestScopedOnly = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .web_search,
                args: [
                    "query": .string("OpenAI API pricing"),
                    "grant_request_id": .string(grantRequestId),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(requestScopedOnly.ok == false)
        #expect(toolBody(requestScopedOnly.output).contains("high_risk_denied"))
        #expect(toolBody(requestScopedOnly.output).contains("high_risk_grant_missing"))
        #expect(!toolBody(requestScopedOnly.output).contains(grantRequestId))

        let executableGrant = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .web_search,
                args: [
                    "query": .string("OpenAI API pricing"),
                    "grant_id": .string(executionGrantId),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(executableGrant.ok == false)
        #expect(toolBody(executableGrant.output).contains("high_risk_denied"))
        #expect(toolBody(executableGrant.output).contains("high_risk_bridge_disabled"))
        #expect(toolBody(executableGrant.output).contains(executionGrantId))
        #expect(!toolBody(executableGrant.output).contains("high_risk_grant_invalid"))
    }
}
