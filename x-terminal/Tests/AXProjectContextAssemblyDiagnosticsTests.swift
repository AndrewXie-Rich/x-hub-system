import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct AXProjectContextAssemblyDiagnosticsTests {
    @Test
    func doctorSummaryUsesLatestCoderUsageExplainability() throws {
        let root = try makeProjectRoot(named: "project-context-diag")
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 20.0,
                "role": "coder",
                "stage": "chat_plan",
                "memory_v1_source": "hub_memory_v1_grpc",
                "recent_project_dialogue_profile": "standard_12_pairs",
                "recent_project_dialogue_selected_pairs": 12,
                "recent_project_dialogue_floor_pairs": 8,
                "recent_project_dialogue_floor_satisfied": true,
                "recent_project_dialogue_source": "recent_context",
                "recent_project_dialogue_low_signal_dropped": 1,
                "project_context_depth": "balanced",
                "effective_project_serving_profile": "m2_plan_review",
                "workflow_present": true,
                "execution_evidence_present": false,
                "review_guidance_present": true,
                "cross_link_hints_selected": 0,
                "personal_memory_excluded_reason": "project_ai_default_scopes_to_project_memory_only",
            ],
            for: ctx
        )
        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 30.0,
                "role": "coder",
                "stage": "chat_plan",
                "memory_v1_source": "local_project_memory_v1",
                "recent_project_dialogue_profile": "extended_40_pairs",
                "recent_project_dialogue_selected_pairs": 18,
                "recent_project_dialogue_floor_pairs": 8,
                "recent_project_dialogue_floor_satisfied": true,
                "recent_project_dialogue_source": "xt_cache",
                "recent_project_dialogue_low_signal_dropped": 3,
                "project_context_depth": "full",
                "effective_project_serving_profile": "m4_full_scan",
                "workflow_present": true,
                "execution_evidence_present": true,
                "review_guidance_present": true,
                "cross_link_hints_selected": 2,
                "personal_memory_excluded_reason": "project_ai_default_scopes_to_project_memory_only",
            ],
            for: ctx
        )

        let summary = AXProjectContextAssemblyDiagnosticsStore.doctorSummary(for: ctx)

        #expect(summary.latestEvent?.memoryV1Source == "local_project_memory_v1")
        #expect(summary.latestEvent?.recentProjectDialogueProfile == "extended_40_pairs")
        #expect(summary.latestEvent?.recentProjectDialogueFloorSatisfied == true)
        #expect(summary.detailLines.contains("project_context_diagnostics_source=latest_coder_usage"))
        #expect(summary.detailLines.contains("recent_project_dialogue_selected_pairs=18"))
        #expect(summary.detailLines.contains("recent_project_dialogue_floor_satisfied=true"))
        #expect(summary.detailLines.contains("project_context_depth=full"))
        #expect(summary.detailLines.contains("effective_project_serving_profile=m4_full_scan"))
    }

    @Test
    func doctorSummaryFallsBackToConfigWhenNoUsageExplainabilityExists() throws {
        let root = try makeProjectRoot(named: "project-context-config-fallback")
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let config = AXProjectConfig.default(forProjectRoot: root)
            .settingProjectContextAssembly(
                projectRecentDialogueProfile: .deep20Pairs,
                projectContextDepthProfile: .deep
            )

        let summary = AXProjectContextAssemblyDiagnosticsStore.doctorSummary(
            for: ctx,
            config: config
        )

        #expect(summary.latestEvent == nil)
        #expect(summary.detailLines.contains("project_context_diagnostics_source=config_only"))
        #expect(summary.detailLines.contains("configured_recent_project_dialogue_profile=deep_20_pairs"))
        #expect(summary.detailLines.contains("configured_project_context_depth=deep"))
        #expect(summary.detailLines.contains("project_context_diagnostics=no_recent_coder_usage"))
    }
}

private func makeProjectRoot(named name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("xt-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
