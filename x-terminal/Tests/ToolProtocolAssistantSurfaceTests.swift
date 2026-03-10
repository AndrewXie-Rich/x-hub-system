import Testing
@testable import XTerminal

struct ToolProtocolAssistantSurfaceTests {

    @Test
    func assistantSurfaceSpecsExposeOpenClawAlignedTools() {
        #expect(ToolPolicy.toolSpec(.session_list).contains("project_id"))
        #expect(ToolPolicy.toolSpec(.memory_snapshot).contains("mode"))
        #expect(ToolPolicy.toolSpec(.web_search).contains("grant_id"))
        #expect(ToolPolicy.toolSpec(.browser_read).contains("url"))
        #expect(ToolPolicy.toolSpec(.project_snapshot) == "- project_snapshot {}")
    }

    @Test
    func toolPolicyGroupsAndRiskIncludeNewSurface() {
        let allowed = ToolPolicy.effectiveAllowedTools(
            profileRaw: ToolProfile.minimal.rawValue,
            allowTokens: ["group:runtime", "group:network"],
            denyTokens: []
        )

        #expect(allowed.contains(.session_list))
        #expect(allowed.contains(.session_resume))
        #expect(allowed.contains(.session_compact))
        #expect(allowed.contains(.memory_snapshot))
        #expect(allowed.contains(.project_snapshot))
        #expect(allowed.contains(.web_search))
        #expect(allowed.contains(.browser_read))
        #expect(ToolPolicy.risk(for: ToolCall(tool: .session_resume, args: [:])) == .safe)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .memory_snapshot, args: [:])) == .safe)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .web_search, args: ["query": .string("OpenAI")])) == .safe)
    }
}
