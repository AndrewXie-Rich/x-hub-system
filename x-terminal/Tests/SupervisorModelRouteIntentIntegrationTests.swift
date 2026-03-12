import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorModelRouteIntentIntegrationTests {
    private func makeProject(
        id: String,
        root: URL,
        displayName: String,
        now: Double = Date().timeIntervalSince1970
    ) -> AXProjectEntry {
        AXProjectEntry(
            projectId: id,
            rootPath: root.path,
            displayName: displayName,
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: now,
            lastEventAt: now
        )
    }

    @Test
    func routeSummaryUsesTaskIntentAndProjectHintsForCoderWork() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-route-intent-coder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-coder")
        try AXProjectStore.saveConfig(config, for: ctx)

        let project = makeProject(id: "proj_alpha", root: root, displayName: "Alpha")
        let manager = SupervisorManager.makeForTesting()
        let summary = manager.currentSupervisorModelRouteSummaryForTesting(
            "把 Alpha 项目的代码修一下并直接改代码",
            projects: [project]
        )

        #expect(summary.contains("task-intent role=coder"))
        #expect(summary.contains("preferred_classes=[paid_coder, local_codegen]"))
        #expect(summary.contains("grant=project_policy_required"))
        #expect(summary.contains("project=Alpha"))
        #expect(summary.contains("project_hints=[openai/gpt-coder]"))
        #expect(summary.contains("hub_resolves_concrete_model=true"))
    }

    @Test
    func routeSummaryEscalatesHighRiskOpsWorkToHubGate() {
        let manager = SupervisorManager.makeForTesting()
        let summary = manager.currentSupervisorModelRouteSummaryForTesting(
            "帮我 rollout 到 production，并检查 grant 和权限问题"
        )

        #expect(summary.contains("task-intent role=ops"))
        #expect(summary.contains("grant=hub_policy_required"))
        #expect(summary.contains("hub_gate=required"))
        #expect(summary.contains("signals=["))
    }

    @Test
    func systemPromptIncludesTaskIntentRouteSummary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-route-intent-doc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProject(id: "proj_docs", root: root, displayName: "Docs")
        let manager = SupervisorManager.makeForTesting()
        let prompt = manager.buildSupervisorSystemPromptForTesting(
            "给 Docs 项目写 README 文档",
            projects: [project],
            preferredModel: "openai/gpt-5.3-codex"
        )

        #expect(prompt.contains("Preferred supervisor model id: openai/gpt-5.3-codex"))
        #expect(prompt.contains("Supervisor model route summary:"))
        #expect(prompt.contains("task-intent role=doc"))
        #expect(prompt.contains("preferred_classes=[local_writer, paid_writer]"))
    }
}
