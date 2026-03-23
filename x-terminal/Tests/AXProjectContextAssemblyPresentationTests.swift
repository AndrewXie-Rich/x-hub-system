import Foundation
import Testing
@testable import XTerminal

struct AXProjectContextAssemblyPresentationTests {
    @Test
    func latestCoderUsagePresentationExplainsRuntimeAssembly() throws {
        let summary = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=latest_coder_usage",
                "project_context_project=Snake",
                "project_memory_v1_source=hub_memory_v1_grpc",
                "recent_project_dialogue_profile=extended_40_pairs",
                "recent_project_dialogue_selected_pairs=18",
                "recent_project_dialogue_floor_pairs=8",
                "recent_project_dialogue_floor_satisfied=true",
                "recent_project_dialogue_source=xt_cache",
                "recent_project_dialogue_low_signal_dropped=3",
                "project_context_depth=full",
                "effective_project_serving_profile=m4_full_scan",
                "workflow_present=true",
                "execution_evidence_present=true",
                "review_guidance_present=false",
                "cross_link_hints_selected=2",
                "personal_memory_excluded_reason=project_ai_default_scopes_to_project_memory_only"
            ]
        )

        let presentation = try #require(AXProjectContextAssemblyPresentation.from(summary: summary))

        #expect(presentation.sourceKind == .latestCoderUsage)
        #expect(presentation.sourceBadge == "Latest Usage")
        #expect(presentation.projectLabel == "Snake")
        #expect(presentation.dialogueMetric.contains("Extended"))
        #expect(presentation.dialogueMetric.contains("selected 18p"))
        #expect(presentation.depthMetric.contains("Full"))
        #expect(presentation.depthMetric.contains("m4_full_scan"))
        #expect(presentation.depthMetric.contains("Hub 快照 + 本地 overlay"))
        #expect(presentation.coverageMetric == "wf yes · ev yes · gd no · xlink 2")
        #expect(presentation.boundaryMetric == "personal excluded")
        #expect(presentation.dialogueLine.contains("floor 8 已满足"))
        #expect(presentation.recentDialogueSource == "xt_cache")
        #expect(presentation.recentDialogueSourceLabel == "本地缓存")
        #expect(presentation.recentDialogueSourceClass == "local_cache")
        #expect(presentation.memorySource == "hub_memory_v1_grpc")
        #expect(presentation.memorySourceLabel == "Hub 快照 + 本地 overlay")
        #expect(presentation.memorySourceClass == "hub_snapshot_plus_local_overlay")
        #expect(presentation.depthLine.contains("Hub 快照 + 本地 overlay"))
        #expect(presentation.userSourceBadge == "实际运行")
        #expect(presentation.userDialogueMetric == "Extended · 40 pairs")
        #expect(presentation.userDepthMetric == "Full")
        #expect(presentation.userCoverageSummary == "已带工作流、执行证据和关联线索")
        #expect(presentation.userBoundarySummary == "默认不读取你的个人记忆")
        #expect(presentation.userDialogueLine.contains("本轮实际选中 18 组对话"))
    }

    @Test
    func configOnlyPresentationExplainsBaselineBeforeRuntimeUsage() throws {
        let summary = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=config_only",
                "project_context_project=Bright",
                "configured_recent_project_dialogue_profile=deep_20_pairs",
                "configured_project_context_depth=deep",
                "project_context_diagnostics=no_recent_coder_usage"
            ]
        )

        let presentation = try #require(AXProjectContextAssemblyPresentation.from(summary: summary))

        #expect(presentation.sourceKind == .configOnly)
        #expect(presentation.sourceBadge == "Config Only")
        #expect(presentation.projectLabel == "Bright")
        #expect(presentation.dialogueMetric.contains("Deep"))
        #expect(presentation.dialogueMetric.contains("20 pairs"))
        #expect(presentation.depthMetric == "Deep")
        #expect(presentation.coverageMetric == nil)
        #expect(presentation.boundaryMetric == nil)
        #expect(presentation.statusLine.contains("配置基线"))
        #expect(presentation.userSourceBadge == "配置基线")
        #expect(presentation.userStatusLine.contains("还没有实际运行记录"))
        #expect(presentation.userDialogueLine.contains("如果现在开始执行"))
    }
}
