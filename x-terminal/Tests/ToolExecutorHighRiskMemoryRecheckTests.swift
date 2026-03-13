import Foundation
import Testing
@testable import XTerminal

struct ToolExecutorHighRiskMemoryRecheckTests {

    @Test
    func overwriteWriteFileFailsClosedWhenInjectedFreshHubRecheckFails() async throws {
        let fixture = ToolExecutorProjectFixture(name: "write-file-overwrite-fresh-recheck")
        defer { fixture.cleanup() }

        let target = fixture.root.appendingPathComponent("README.md")
        try "old".write(to: target, atomically: true, encoding: .utf8)

        let config = AXProjectConfig.default(forProjectRoot: fixture.root)
        let result = await ToolExecutor.deniedHighRiskMemoryRecheckResultIfNeeded(
            call: ToolCall(
                tool: .write_file,
                args: [
                    "path": .string("README.md"),
                    "content": .string("new")
                ]
            ),
            projectRoot: fixture.root,
            config: config,
            resolutionOverride: failingResolution()
        )

        let denied = try #require(result)
        #expect(denied.ok == false)
        let summary = try #require(toolSummaryObject(denied.output))
        #expect(jsonString(summary["deny_code"]) == XTMemoryUseDenyCode.memorySnapshotStaleForHighRiskAct.rawValue)
        #expect(jsonString(summary["memory_mode"]) == XTMemoryUseMode.toolActHighRisk.rawValue)
        #expect(toolBody(denied.output).contains("high_risk_fresh_recheck_required"))
        #expect(try String(contentsOf: target) == "old")
    }

    @Test
    func creatingNewFileDoesNotTriggerFreshHubRecheckGate() async throws {
        let fixture = ToolExecutorProjectFixture(name: "write-file-create-no-fresh-recheck")
        defer { fixture.cleanup() }

        let config = AXProjectConfig.default(forProjectRoot: fixture.root)
        let denied = await ToolExecutor.deniedHighRiskMemoryRecheckResultIfNeeded(
            call: ToolCall(
                tool: .write_file,
                args: [
                    "path": .string("README.md"),
                    "content": .string("hello")
                ]
            ),
            projectRoot: fixture.root,
            config: config,
            resolutionOverride: failingResolution()
        )

        #expect(denied == nil)
    }

    @Test
    func creatingNewFileStillWorksWithoutFreshHubRecheck() async throws {
        let fixture = ToolExecutorProjectFixture(name: "write-file-create-actual")
        defer { fixture.cleanup() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .write_file,
                args: [
                    "path": .string("README.md"),
                    "content": .string("hello")
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok == true)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("README.md").path))
    }

    @Test
    func dangerousRunCommandFailsClosedWhenInjectedFreshHubRecheckFails() async throws {
        let fixture = ToolExecutorProjectFixture(name: "run-command-fresh-recheck")
        defer { fixture.cleanup() }

        let config = AXProjectConfig.default(forProjectRoot: fixture.root)
        let result = await ToolExecutor.deniedHighRiskMemoryRecheckResultIfNeeded(
            call: ToolCall(
                tool: .run_command,
                args: ["command": .string("git push origin main")]
            ),
            projectRoot: fixture.root,
            config: config,
            resolutionOverride: failingResolution()
        )

        let denied = try #require(result)
        #expect(denied.ok == false)
        let summary = try #require(toolSummaryObject(denied.output))
        #expect(jsonString(summary["deny_code"]) == XTMemoryUseDenyCode.memorySnapshotStaleForHighRiskAct.rawValue)
        #expect(jsonString(summary["memory_mode"]) == XTMemoryUseMode.toolActHighRisk.rawValue)
        #expect(jsonString(summary["memory_freshness"]) == "unavailable")
    }

    private func failingResolution() -> HubIPCClient.MemoryContextResolutionResult {
        HubIPCClient.MemoryContextResolutionResult(
            response: nil,
            source: "test_override",
            resolvedMode: .toolActHighRisk,
            requestedProfile: XTMemoryServingProfile.m1Execute.rawValue,
            attemptedProfiles: [XTMemoryServingProfile.m1Execute.rawValue],
            freshness: "unavailable",
            cacheHit: false,
            denyCode: XTMemoryUseDenyCode.memorySnapshotStaleForHighRiskAct.rawValue,
            downgradeCode: nil,
            reasonCode: "test_memory_recheck_failed"
        )
    }
}
