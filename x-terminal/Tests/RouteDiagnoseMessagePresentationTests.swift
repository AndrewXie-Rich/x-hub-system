import Foundation
import Testing
@testable import XTerminal

struct RouteDiagnoseMessagePresentationTests {
    @Test
    func matchesAssistantRouteDiagnoseMessage() {
        let message = AXChatMessage(
            role: .assistant,
            content: """
Project route diagnose: coder
当前配置：openai/gpt-5.4
"""
        )

        #expect(RouteDiagnoseMessagePresentation.matches(message))
    }

    @Test
    func ignoresRegularAssistantMessage() {
        let message = AXChatMessage(
            role: .assistant,
            content: "项目接续摘要（本地整理，不额外调用远端模型）"
        )

        #expect(!RouteDiagnoseMessagePresentation.matches(message))
    }

    @Test
    func recommendationUsesProjectRouteGuidanceWhenAvailable() throws {
        let root = try makeProjectRoot(named: "route-diagnose-recommendation")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        appendUsage(
            createdAt: 100,
            requestedModelId: "openai/gpt-4.1",
            actualModelId: "openai/gpt-4.1",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            for: ctx
        )
        appendUsage(
            createdAt: 200,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")
        let settings = XTerminalSettings.default()
        let models = [
            makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
            makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded),
            makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
        ]
        let recommendation = try #require(
            RouteDiagnoseMessagePresentation.recommendation(
                config: config,
                settings: settings,
                ctx: ctx,
                modelsState: ModelStateSnapshot(models: models, updatedAt: 300)
            )
        )

        #expect(recommendation.modelId == "openai/gpt-4.1")
        #expect(recommendation.message.contains("openai/gpt-4.1"))

        let actionTitle = RouteDiagnoseMessagePresentation.actionTitle(
            for: recommendation,
            models: models
        )
        #expect(actionTitle.contains("改用"))
        #expect(actionTitle.contains("GPT 4.1"))
    }

    @Test
    func repairActionSuggestsReconnectForConnectivityIncidentOnRemoteRoute() {
        let action = RouteDiagnoseMessagePresentation.repairAction(
            latestEvent: makeEvent(
                executionPath: "remote_error",
                fallbackReasonCode: "grpc_route_unavailable"
            ),
            hubConnected: false,
            hubRemoteConnected: true,
            hasRecommendation: false
        )

        #expect(action == .reconnectHubAndDiagnose)
        #expect(
            RouteDiagnoseMessagePresentation.title(
                for: .reconnectHubAndDiagnose,
                inProgress: false
            ) == "重连并重诊断"
        )
    }

    @Test
    func repairActionSuggestsConnectForConnectivityIncidentWhenHubIsOffline() {
        let action = RouteDiagnoseMessagePresentation.repairAction(
            latestEvent: makeEvent(
                executionPath: "remote_error",
                fallbackReasonCode: "runtime_not_running"
            ),
            hubConnected: false,
            hubRemoteConnected: false,
            hasRecommendation: false
        )

        #expect(action == .connectHubAndDiagnose)
        #expect(
            RouteDiagnoseMessagePresentation.helperText(for: .connectHubAndDiagnose)
                .contains("自动回到当前项目重跑一次路由诊断")
        )
    }

    @Test
    func repairActionSuggestsChooseModelForModelMissingWithoutRecommendation() {
        let action = RouteDiagnoseMessagePresentation.repairAction(
            latestEvent: makeEvent(
                executionPath: "local_fallback_after_remote_error",
                fallbackReasonCode: "model_not_found"
            ),
            hubConnected: false,
            hubRemoteConnected: true,
            hasRecommendation: false
        )
        #expect(action == .openChooseModel)
        #expect(
            RouteDiagnoseMessagePresentation.title(
                for: .openChooseModel,
                inProgress: false
            ) == "检查已加载远端"
        )
    }

    @Test
    func repairActionSkipsChooseModelWhenRecommendationAlreadyExists() {
        let modelMissing = RouteDiagnoseMessagePresentation.repairAction(
            latestEvent: makeEvent(
                executionPath: "local_fallback_after_remote_error",
                fallbackReasonCode: "model_not_found"
            ),
            hubConnected: false,
            hubRemoteConnected: true,
            hasRecommendation: true
        )
        #expect(modelMissing == nil)
    }

    @Test
    func repairActionSuggestsHubConnectionLogForDowngradeIncident() {
        let action = RouteDiagnoseMessagePresentation.repairAction(
            latestEvent: makeEvent(
                executionPath: "hub_downgraded_to_local",
                fallbackReasonCode: "downgrade_to_local"
            ),
            hubConnected: false,
            hubRemoteConnected: true,
            hasRecommendation: false
        )
        #expect(action == .openHubConnectionLog)
        #expect(
            RouteDiagnoseMessagePresentation.helperText(for: .openHubConnectionLog)
                .contains("Hub 侧把远端请求降到了本地")
        )
    }

    @Test
    func repairActionSuggestsHubRecoveryForRemoteExportBlocked() {
        let action = RouteDiagnoseMessagePresentation.repairAction(
            latestEvent: makeEvent(
                executionPath: "hub_downgraded_to_local",
                fallbackReasonCode: "remote_export_blocked"
            ),
            hubConnected: false,
            hubRemoteConnected: true,
            hasRecommendation: false
        )
        #expect(action == .openHubRecovery)
        #expect(
            RouteDiagnoseMessagePresentation.title(
                for: .openHubRecovery,
                inProgress: false
            ) == "检查 Hub Recovery"
        )
    }

    @Test
    func repairActionSkipsConnectivityFixWhenLocalHubAlreadyConnected() {
        let localHubOnly = RouteDiagnoseMessagePresentation.repairAction(
            latestEvent: makeEvent(
                executionPath: "remote_error",
                fallbackReasonCode: "grpc_route_unavailable"
            ),
            hubConnected: true,
            hubRemoteConnected: false,
            hasRecommendation: false
        )
        #expect(localHubOnly == nil)
    }

    @Test
    func focusContextForChooseModelIncludesLatestRouteDetails() throws {
        let context = try #require(
            RouteDiagnoseMessagePresentation.focusContext(
                for: .openChooseModel,
                latestEvent: makeEvent(
                    executionPath: "local_fallback_after_remote_error",
                    fallbackReasonCode: "model_not_found"
                )
            )
        )

        #expect(context.title == "路由诊断：检查已加载远端")
        #expect(context.detail?.contains("requested=openai/gpt-5.4") == true)
        #expect(context.detail?.contains("actual=openai/gpt-5.4") == true)
        #expect(context.detail?.contains("reason=model_not_found") == true)
    }

    @Test
    func focusContextReturnsNilForConnectivityRepair() {
        let context = RouteDiagnoseMessagePresentation.focusContext(
            for: .connectHubAndDiagnose,
            latestEvent: makeEvent(
                executionPath: "remote_error",
                fallbackReasonCode: "runtime_not_running"
            )
        )

        #expect(context == nil)
    }

    @Test
    func diagnosticsContextUsesFallbackWhenNoLatestEvent() {
        let context = RouteDiagnoseMessagePresentation.diagnosticsContext(
            latestEvent: nil
        )

        #expect(context.title == "路由诊断：查看 XT Diagnostics")
        #expect(context.detail == "先核对当前 route event、transport、模型可见性和最近连接状态。")
    }

    @Test
    func modelSettingsContextUsesLatestRouteDetails() {
        let context = RouteDiagnoseMessagePresentation.modelSettingsContext(
            latestEvent: makeEvent(
                executionPath: "local_fallback_after_remote_error",
                fallbackReasonCode: "model_not_found"
            )
        )

        #expect(context.title == "路由诊断：检查 coder 模型设置")
        #expect(context.detail?.contains("requested=openai/gpt-5.4") == true)
        #expect(context.detail?.contains("reason=model_not_found") == true)
    }

    @Test
    func diagnosticsFailureContextIncludesRepairReasonAndRouteEvent() {
        let context = RouteDiagnoseMessagePresentation.diagnosticsFailureContext(
            for: .reconnectHubAndDiagnose,
            report: HubRemoteConnectReport(
                ok: false,
                route: .internet,
                summary: "remote tunnel timeout",
                logLines: [],
                reasonCode: "grpc_route_unavailable"
            ),
            latestEvent: makeEvent(
                executionPath: "remote_error",
                fallbackReasonCode: "grpc_route_unavailable"
            )
        )

        #expect(context.title == "重连修复失败：查看 XT Diagnostics")
        #expect(context.detail?.contains("repair_reason=grpc_route_unavailable") == true)
        #expect(context.detail?.contains("route_event=role=coder") == true)
        #expect(context.detail?.contains("reason=grpc_route_unavailable") == true)
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_route_diagnose_message_\(name)_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func appendUsage(
        createdAt: Double,
        requestedModelId: String,
        actualModelId: String,
        executionPath: String,
        fallbackReasonCode: String,
        for ctx: AXProjectContext
    ) {
        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": createdAt,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": requestedModelId,
                "actual_model_id": actualModelId,
                "runtime_provider": actualModelId.contains("mlx") ? "Hub (Local)" : "Hub (Remote)",
                "execution_path": executionPath,
                "fallback_reason_code": fallbackReasonCode,
            ],
            for: ctx
        )
    }

    private func makeModel(
        id: String,
        name: String,
        state: HubModelState,
        backend: String = "openai",
        modelPath: String? = nil
    ) -> HubModel {
        HubModel(
            id: id,
            name: name,
            backend: backend,
            quant: "",
            contextLength: 128_000,
            paramsB: 0,
            roles: nil,
            state: state,
            memoryBytes: nil,
            tokensPerSec: nil,
            modelPath: modelPath,
            note: nil
        )
    }

    private func makeEvent(
        executionPath: String,
        fallbackReasonCode: String
    ) -> AXModelRouteDiagnosticEvent {
        AXModelRouteDiagnosticEvent(
            schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
            createdAt: 100,
            projectId: "project-1",
            projectDisplayName: "Project 1",
            role: "coder",
            stage: "chat",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            runtimeProvider: "Hub (Remote)",
            executionPath: executionPath,
            fallbackReasonCode: fallbackReasonCode,
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: ""
        )
    }
}
