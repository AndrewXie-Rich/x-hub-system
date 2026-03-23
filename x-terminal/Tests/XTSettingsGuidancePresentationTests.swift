import Foundation
import Testing
@testable import XTerminal

struct XTSettingsGuidancePresentationTests {

    @Test
    func tightenedPrivacyModeClampsRecentRawContextCeilingToStandardOrLower() {
        #expect(XTPrivacyMode.tightenedContext.effectiveRecentRawContextProfile(.autoMax) == .standard12Pairs)
        #expect(XTPrivacyMode.tightenedContext.effectiveRecentRawContextProfile(.extended40Pairs) == .standard12Pairs)
        #expect(XTPrivacyMode.tightenedContext.effectiveRecentRawContextProfile(.deep20Pairs) == .standard12Pairs)
        #expect(XTPrivacyMode.tightenedContext.effectiveRecentRawContextProfile(.standard12Pairs) == .standard12Pairs)
        #expect(XTPrivacyMode.tightenedContext.effectiveRecentRawContextProfile(.floor8Pairs) == .floor8Pairs)
    }

    @Test
    func modelGuidanceSummarizesLoadedInteractiveAndSupportModels() {
        let presentation = XTModelGuidancePresentation.build(
            settings: .default(),
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", backend: "openai", state: .loaded),
                    makeModel(
                        id: "qwen3-14b-mlx",
                        backend: "mlx",
                        state: .loaded,
                        modelPath: "/models/qwen3"
                    ),
                    makeModel(
                        id: "mlx-community/qwen3-embedding-0.6b-4bit",
                        backend: "mlx",
                        state: .loaded,
                        modelPath: "/models/embedding",
                        taskKinds: ["embedding"]
                    )
                ],
                updatedAt: 42
            )
        )

        #expect(presentation.inventorySummary.contains("远端 1 个"))
        #expect(presentation.inventorySummary.contains("本地 1 个"))
        #expect(presentation.inventorySummary.contains("辅助模型 1 个"))
        #expect(presentation.items.contains(where: { $0.id == "coder" }))
        #expect(presentation.items.contains(where: { $0.id == "supervisor" }))
        #expect(presentation.items.contains(where: { $0.id == "support_models" }))
    }

    @Test
    func securityRuntimeGuidanceExplainsSandboxAutomationAndPrivacy() {
        let presentation = XTSecurityRuntimeGuidancePresentation.build(
            sandboxMode: .sandbox,
            workMode: .governedAutomation,
            privacyMode: .tightenedContext
        )

        let rendered = presentation.items
            .map { "\($0.title): \($0.detail)" }
            .joined(separator: "\n")

        #expect(rendered.contains("当前默认走沙箱执行"))
        #expect(rendered.contains("项目聊天里的会话开关"))
        #expect(rendered.contains("A-tier、S-tier、授权、runtime readiness 和 fail-closed gate"))
        #expect(rendered.contains("收紧模式"))
    }

    @Test
    func recentRawContextNoticeExplainsEffectiveClampWhenPrivacyIsTightened() {
        let notice = XTSettingsChangeNoticeBuilder.supervisorRecentRawContext(
            profile: .extended40Pairs,
            privacyMode: .tightenedContext
        )

        #expect(notice.title == "最近原始上下文已更新")
        #expect(notice.detail.contains("Extended"))
        #expect(notice.detail.contains("Standard"))
        #expect(notice.detail.contains("实际按"))
    }

    @Test
    func sandboxModeNoticeExplainsGuardrails() {
        let notice = XTSettingsChangeNoticeBuilder.defaultToolSandboxMode(.sandbox)

        #expect(notice.title == "默认工具路径已更新")
        #expect(notice.detail.contains("Sandbox"))
        #expect(notice.detail.contains("fail-closed gate"))
    }

    @Test
    func globalRoleModelNoticeConfirmsLoadedInteractiveModel() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", backend: "openai", state: .loaded)
            ],
            updatedAt: 42
        )

        let notice = XTSettingsChangeNoticeBuilder.globalRoleModel(
            role: .coder,
            modelId: "openai/gpt-5.4",
            snapshot: snapshot
        )

        #expect(notice.title == "\(AXRole.coder.displayName) 模型已更新")
        #expect(notice.detail.contains("已加载"))
        #expect(notice.detail.contains("远端模型"))
    }

    @Test
    func globalRoleModelNoticeWarnsWhenModelIsMissingFromInventory() {
        let notice = XTSettingsChangeNoticeBuilder.globalRoleModel(
            role: .supervisor,
            modelId: "openai/gpt-5.9",
            snapshot: .empty()
        )

        #expect(notice.title == "\(AXRole.supervisor.displayName) 模型已更新")
        #expect(notice.detail.contains("没有精确匹配"))
        #expect(notice.detail.contains("刷新模型列表"))
    }

    @Test
    func projectRoleModelNoticeExplainsInheritedGlobalWhenOverrideIsCleared() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", backend: "openai", state: .loaded)
            ],
            updatedAt: 42
        )

        let notice = XTSettingsChangeNoticeBuilder.projectRoleModel(
            projectName: "Alpha",
            role: .coder,
            modelId: nil,
            inheritedModelId: "openai/gpt-5.4",
            snapshot: snapshot
        )

        #expect(notice.title == "项目模型已更新")
        #expect(notice.detail.contains("已清空 Alpha 的 \(AXRole.coder.displayName) 项目覆盖"))
        #expect(notice.detail.contains("回到全局模型"))
        #expect(notice.detail.contains("已加载"))
    }

    @Test
    func projectRoleModelBatchNoticeSummarizesChangedProjectCount() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", backend: "openai", state: .loaded)
            ],
            updatedAt: 42
        )

        let notice = XTSettingsChangeNoticeBuilder.projectRoleModelBatch(
            role: .reviewer,
            modelId: "openai/gpt-5.4",
            changedProjectCount: 2,
            totalProjectCount: 5,
            snapshot: snapshot
        )

        #expect(notice.title == "批量应用已完成")
        #expect(notice.detail.contains("2/5"))
        #expect(notice.detail.contains("openai/gpt-5.4"))
        #expect(notice.detail.contains("已加载"))
    }

    private func makeModel(
        id: String,
        backend: String,
        state: HubModelState,
        modelPath: String? = nil,
        taskKinds: [String]? = nil
    ) -> HubModel {
        HubModel(
            id: id,
            name: id,
            backend: backend,
            quant: "bf16",
            contextLength: 8_192,
            paramsB: 14,
            state: state,
            modelPath: modelPath,
            taskKinds: taskKinds
        )
    }
}
