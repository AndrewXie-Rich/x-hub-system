import Testing
@testable import XTerminal

struct ToolExecutorSessionToolsTests {

    @MainActor
    @Test
    func sessionResumeAndListEmitStructuredState() async throws {
        let fixture = ToolExecutorProjectFixture(name: "session-runtime")
        defer { fixture.cleanup() }

        let resume = try await ToolExecutor.execute(
            call: ToolCall(tool: .session_resume, args: [:]),
            projectRoot: fixture.root
        )

        #expect(resume.ok)
        let resumeSummary = toolSummaryObject(resume.output)
        #expect(resumeSummary != nil)
        guard let resumeSummary else { return }

        let sessionID = jsonString(resumeSummary["session_id"])
        #expect(sessionID != nil)
        #expect(jsonString(resumeSummary["state_after"]) == AXSessionRuntimeState.planning.rawValue)
        #expect(jsonNumber(resumeSummary["pending_tool_call_count"]) == 0)

        let listed = try await ToolExecutor.execute(
            call: ToolCall(tool: .session_list, args: ["limit": .number(5)]),
            projectRoot: fixture.root
        )

        #expect(listed.ok)
        let listSummary = toolSummaryObject(listed.output)
        #expect(listSummary != nil)
        guard let listSummary else { return }

        #expect(jsonNumber(listSummary["session_count"]) == 1)
        let sessions = jsonArray(listSummary["sessions"])
        #expect(sessions?.count == 1)
        let firstSession = sessions?.first.flatMap(jsonObject)
        #expect(jsonString(firstSession?["id"]) == sessionID)
        #expect(jsonBool(firstSession?["is_active"]) == true)
        #expect(toolBody(listed.output).contains(sessionID ?? ""))
    }

    @MainActor
    @Test
    func sessionCompactAndProjectSnapshotReflectCurrentProject() async throws {
        let fixture = ToolExecutorProjectFixture(name: "project-snapshot")
        defer { fixture.cleanup() }

        let resumed = try await ToolExecutor.execute(
            call: ToolCall(tool: .session_resume, args: [:]),
            projectRoot: fixture.root
        )
        let resumedSummary = toolSummaryObject(resumed.output)
        guard let resumedSummary,
              let sessionID = jsonString(resumedSummary["session_id"]) else {
            #expect(false)
            return
        }

        let compacted = try await ToolExecutor.execute(
            call: ToolCall(tool: .session_compact, args: ["session_id": .string(sessionID)]),
            projectRoot: fixture.root
        )

        #expect(compacted.ok)
        let compactSummary = toolSummaryObject(compacted.output)
        #expect(compactSummary != nil)
        guard let compactSummary else { return }

        #expect(jsonString(compactSummary["session_id"]) == sessionID)
        let compactMeta = jsonObject(compactSummary["summary"])
        #expect(jsonNumber(compactMeta?["files"]) == 0)
        #expect(jsonNumber(compactMeta?["additions"]) == 0)
        #expect(jsonNumber(compactMeta?["deletions"]) == 0)

        let snapshot = try await ToolExecutor.execute(
            call: ToolCall(tool: .project_snapshot, args: [:]),
            projectRoot: fixture.root
        )

        #expect(snapshot.ok)
        let snapshotSummary = toolSummaryObject(snapshot.output)
        #expect(snapshotSummary != nil)
        guard let snapshotSummary else { return }

        #expect(jsonString(snapshotSummary["tool_profile"]) == ToolPolicy.defaultProfile.rawValue)
        let session = jsonObject(snapshotSummary["session"])
        #expect(jsonString(session?["id"]) == sessionID)
        let effectiveTools = jsonArray(snapshotSummary["effective_tools"])
        #expect(effectiveTools?.contains(where: { jsonString($0) == ToolName.project_snapshot.rawValue }) == true)
    }
}
