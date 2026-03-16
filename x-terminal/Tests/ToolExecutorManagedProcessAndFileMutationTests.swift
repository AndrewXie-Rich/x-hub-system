import Foundation
import Testing
@testable import XTerminal

struct ToolExecutorManagedProcessAndFileMutationTests {

    @Test
    func moveAndDeletePathSucceedWithinA2RepoAuto() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-file-mutation")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingHubMemoryPreference(enabled: false)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let source = fixture.root.appendingPathComponent("Sources/Legacy.swift")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "legacy".write(to: source, atomically: true, encoding: .utf8)

        let moveResult = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .move_path,
                args: [
                    "from": .string("Sources/Legacy.swift"),
                    "to": .string("Sources/Renamed.swift"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(moveResult.ok)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Sources/Renamed.swift").path))
        let moveSummary = try #require(toolSummaryObject(moveResult.output))
        #expect(jsonString(moveSummary["from"]) == "Sources/Legacy.swift")
        #expect(jsonString(moveSummary["to"]) == "Sources/Renamed.swift")

        let deleteResult = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .delete_path,
                args: ["path": .string("Sources/Renamed.swift")]
            ),
            projectRoot: fixture.root
        )

        #expect(deleteResult.ok)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Sources/Renamed.swift").path))
        let deleteSummary = try #require(toolSummaryObject(deleteResult.output))
        #expect(jsonString(deleteSummary["path"]) == "Sources/Renamed.swift")
        #expect(jsonBool(deleteSummary["deleted"]) == true)
    }

    @Test
    func managedProcessLifecycleRunsWithinA2RepoAuto() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-managed-process")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingHubMemoryPreference(enabled: false)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let processId = "devserver"
        let startResult = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .process_start,
                args: [
                    "process_id": .string(processId),
                    "name": .string("Dev Server"),
                    "command": .string("printf 'ready\\n'; while true; do printf 'tick\\n'; sleep 0.1; done"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(startResult.ok)
        let startSummary = try #require(toolSummaryObject(startResult.output))
        let startedProcess = try #require(jsonObject(startSummary["process"]))
        #expect(jsonString(startedProcess["process_id"]) == processId)
        #expect(jsonString(startedProcess["status"]) == XTManagedProcessState.running.rawValue)

        try? await Task.sleep(nanoseconds: 400_000_000)

        let statusResult = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .process_status,
                args: ["process_id": .string(processId)]
            ),
            projectRoot: fixture.root
        )

        #expect(statusResult.ok)
        let statusSummary = try #require(toolSummaryObject(statusResult.output))
        let processes = try #require(jsonArray(statusSummary["processes"]))
        #expect(processes.count == 1)
        let statusObject = try #require(jsonObject(processes[0]))
        #expect(jsonString(statusObject["process_id"]) == processId)

        let logsResult = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .process_logs,
                args: [
                    "process_id": .string(processId),
                    "tail_lines": .number(20),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(logsResult.ok)
        let logsBody = toolBody(logsResult.output)
        #expect(logsBody.contains("ready"))
        #expect(logsBody.contains("tick"))

        let stopResult = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .process_stop,
                args: ["process_id": .string(processId)]
            ),
            projectRoot: fixture.root
        )

        #expect(stopResult.ok)
        let stopSummary = try #require(toolSummaryObject(stopResult.output))
        let stoppedProcess = try #require(jsonObject(stopSummary["process"]))
        #expect(jsonString(stoppedProcess["process_id"]) == processId)
        #expect(jsonString(stoppedProcess["status"]) == XTManagedProcessState.exited.rawValue)
    }
}
