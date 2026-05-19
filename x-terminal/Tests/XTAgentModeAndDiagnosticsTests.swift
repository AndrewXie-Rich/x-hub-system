import Foundation
import Testing
@testable import XTerminal

struct XTAgentModeAndDiagnosticsTests {
    @Test
    func exploreModeDeniesRepoMutationEvenWhenProjectPolicyAllowsWrite() async {
        let fixture = ToolExecutorProjectFixture(name: "agent-mode-explore-deny-write")
        defer { fixture.cleanup() }

        let config = AXProjectConfig
            .default(forProjectRoot: fixture.root)
            .settingProjectGovernance(
                executionTier: .a2RepoAuto,
                supervisorInterventionTier: .s2PeriodicReview
            )
            .settingToolPolicy(profile: ToolProfile.coding.rawValue)
        let call = ToolCall(
            tool: .write_file,
            args: [
                "path": .string("README.md"),
                "content": .string("hello"),
                "agent_mode": .string("explore"),
            ]
        )

        let decision = await xtToolAuthorizationDecision(
            call: call,
            config: config,
            projectRoot: fixture.root
        )

        #expect(decision.disposition == .deny)
        #expect(decision.denyCode == "agent_mode_contract_denied")
        #expect(decision.policySource == "agent_mode_contract")
        #expect(decision.policyReason == "mode_disallows_write")
    }

    @Test
    func debugModeAllowsProjectDiagnostics() async {
        let fixture = ToolExecutorProjectFixture(name: "agent-mode-debug-diagnostics")
        defer { fixture.cleanup() }

        let config = AXProjectConfig
            .default(forProjectRoot: fixture.root)
            .settingProjectGovernance(
                executionTier: .a2RepoAuto,
                supervisorInterventionTier: .s2PeriodicReview
            )
        let call = ToolCall(
            tool: .projectDiagnostics,
            args: ["agent_mode": .string("debug")]
        )

        let decision = await xtToolAuthorizationDecision(
            call: call,
            config: config,
            projectRoot: fixture.root
        )

        #expect(decision.disposition == .allow)
    }

    @Test
    func projectDiagnosticsPersistsStructuredSwiftBuildFailure() async throws {
        let fixture = ToolExecutorProjectFixture(name: "project-diagnostics-swift-failure")
        defer { fixture.cleanup() }

        try """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "BrokenDiagFixture",
            targets: [
                .executableTarget(name: "BrokenDiagFixture", path: "Sources")
            ]
        )
        """.write(to: fixture.root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let sources = fixture.root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        @main
        struct Main {
            static func main() {
                let value: Int = "not an int"
                print(value)
            }
        }
        """.write(to: sources.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

        let ctx = AXProjectContext(root: fixture.root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config
            .settingHubMemoryPreference(enabled: false)
            .settingProjectGovernance(
                executionTier: .a2RepoAuto,
                supervisorInterventionTier: .s2PeriodicReview
            )
        try AXProjectStore.saveConfig(config, for: ctx)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .projectDiagnostics,
                args: [
                    "kind": .string("check"),
                    "agent_mode": .string("debug"),
                    "timeout_sec": .number(120),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["schema_version"]) == "xt.project_diagnostics_result.v1")
        #expect(jsonString(summary["language"]) == "swift")
        #expect(jsonBool(summary["is_green"]) == false)
        #expect(jsonString(summary["run_id"])?.hasPrefix("diag-") == true)
        #expect(FileManager.default.fileExists(atPath: ctx.latestDiagnosticsURL.path))
    }
}
