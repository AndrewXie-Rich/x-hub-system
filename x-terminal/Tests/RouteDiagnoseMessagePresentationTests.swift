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
    func matchesLocalizedRouteDiagnoseMessage() {
        let message = AXChatMessage(
            role: .assistant,
            content: """
项目路由诊断：coder
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
    func recommendationUsesProjectRouteGuidanceWhenRememberedRemoteIsPreferred() throws {
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
        #expect(recommendation.kind == .continueWithoutSwitch)
        #expect(recommendation.message.contains("openai/gpt-4.1"))

        let actionTitle = RouteDiagnoseMessagePresentation.actionTitle(
            for: recommendation,
            models: models
        )
        #expect(actionTitle.contains("固定成"))
        #expect(actionTitle.contains("GPT 4.1"))

        let englishActionTitle = RouteDiagnoseMessagePresentation.actionTitle(
            for: recommendation,
            models: models,
            language: .english
        )
        #expect(englishActionTitle == "Pin GPT 4.1")
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
        #expect(
            RouteDiagnoseMessagePresentation.helperText(
                for: .connectHubAndDiagnose,
                language: .english
            ).contains("automatically rerun route diagnosis")
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
            ) == "检查 Supervisor Control Center · AI 模型"
        )
        #expect(
            RouteDiagnoseMessagePresentation.helperText(for: .openChooseModel)
                .contains("只有你想固定当前配置时，再手动切")
        )
    }

    @Test
    func repairActionSuggestsChooseModelForPaidModelAccessBlocked() {
        let action = RouteDiagnoseMessagePresentation.repairAction(
            latestEvent: makeEvent(
                executionPath: "remote_error",
                fallbackReasonCode: "grant_required;deny_code=device_paid_model_not_allowed"
            ),
            hubConnected: false,
            hubRemoteConnected: true,
            hasRecommendation: false
        )

        #expect(action == .openChooseModel)
        #expect(
            RouteDiagnoseMessagePresentation.helperText(for: .openChooseModel)
                .contains("允许名单")
        )
        #expect(
            RouteDiagnoseMessagePresentation.helperText(for: .openChooseModel)
                .contains("预算")
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
            ) == "检查 Hub 诊断与恢复"
        )
    }

    @Test
    func repairActionSuggestsHubRecoveryForRemoteExportDenyCode() {
        let action = RouteDiagnoseMessagePresentation.repairAction(
            latestEvent: makeEvent(
                executionPath: "remote_error",
                fallbackReasonCode: "",
                denyCode: "device_remote_export_denied"
            ),
            hubConnected: false,
            hubRemoteConnected: true,
            hasRecommendation: false
        )

        #expect(action == .openHubRecovery)
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
    func repairActionSuggestsProjectGovernanceForSupervisorRouteBlockers() {
        let action = RouteDiagnoseMessagePresentation.repairAction(
            latestEvent: makeEvent(
                executionPath: "remote_error",
                fallbackReasonCode: "model_not_found"
            ),
            hubConnected: false,
            hubRemoteConnected: true,
            hasRecommendation: false,
            messageContent: supervisorRouteTruthMessage()
        )

        #expect(action == .openProjectGovernanceOverview)
        #expect(
            RouteDiagnoseMessagePresentation.title(
                for: .openProjectGovernanceOverview,
                inProgress: false
            ) == "检查 Project Governance"
        )
        #expect(
            RouteDiagnoseMessagePresentation.helperText(for: .openProjectGovernanceOverview)
                .contains("governance runtime readiness")
        )
    }

    @Test
    func repairActionSuggestsReconnectForSupervisorRouteRoutePlaneWhenHubIsOffline() {
        let action = RouteDiagnoseMessagePresentation.repairAction(
            latestEvent: makeEvent(
                executionPath: "remote_error",
                fallbackReasonCode: "model_not_found"
            ),
            hubConnected: false,
            hubRemoteConnected: true,
            hasRecommendation: false,
            messageContent: supervisorRouteRoutePlaneTruthMessage()
        )

        #expect(action == .reconnectHubAndDiagnose)
    }

    @Test
    func parsesSupervisorRouteExplainabilityFromRouteDiagnoseMessage() throws {
        let explainability = try #require(
            RouteDiagnoseMessagePresentation.supervisorRouteExplainability(
                from: supervisorRouteTruthMessage()
            )
        )

        #expect(explainability.runtimeReadinessSummary == "A4 Agent runtime readiness 仍有缺口。")
        #expect(explainability.blockedComponentKeys == [.grantReady])
        #expect(explainability.blockedComponents.count == 1)
        #expect(explainability.blockedComponents.first?.key == .grantReady)
        #expect(explainability.blockedComponents.first?.detail == "权限宿主未就绪")
        #expect(explainability.suggestedAction?.contains("grant 面未 ready") == true)
        #expect(explainability.auditRef == "audit-route-test-1")
        #expect(explainability.denyCode == "device_permission_owner_missing")
    }

    @Test
    func projectGovernanceContextIncludesParsedExplainability() {
        let context = RouteDiagnoseMessagePresentation.projectGovernanceContext(
            explainability: RouteDiagnoseMessagePresentation.supervisorRouteExplainability(
                from: supervisorRouteTruthMessage()
            )
        )

        #expect(context.title == "路由诊断：检查 Project Governance")
        #expect(context.detail?.contains("runtime readiness：A4 Agent runtime readiness 仍有缺口。") == true)
        #expect(context.detail?.contains("Supervisor 的 grant / governance 面还没就绪") == true)
        #expect(context.detail?.contains("阻塞平面：grant plane") == true)
        #expect(context.detail?.contains("grant plane：权限宿主未就绪") == true)
        #expect(context.detail?.contains("deny code：当前 XT 绑定缺少 permission owner（device_permission_owner_missing）") == true)
        #expect(context.detail?.contains("修复方向：先检查 trusted automation、permission owner、kill-switch、TTL 和当前项目绑定。") == true)
    }

    @Test
    func governanceHelperTextUsesHumanizedRepairHintWhenExplainabilityExists() throws {
        let explainability = try #require(
            RouteDiagnoseMessagePresentation.supervisorRouteExplainability(
                from: supervisorRouteTruthMessage()
            )
        )

        let helper = RouteDiagnoseMessagePresentation.helperText(
            for: .openProjectGovernanceOverview,
            explainability: explainability
        )

        #expect(helper.contains("Supervisor 的 grant / governance 面还没就绪") == true)
        #expect(helper.contains("修复方向：先检查 trusted automation、permission owner、kill-switch、TTL 和当前项目绑定。") == true)
    }

    @Test
    func governanceFocusContextCarriesExplainabilityDetails() throws {
        let explainability = try #require(
            RouteDiagnoseMessagePresentation.supervisorRouteExplainability(
                from: supervisorRouteTruthMessage()
            )
        )

        let context = try #require(
            RouteDiagnoseMessagePresentation.focusContext(
                for: .openProjectGovernanceOverview,
                latestEvent: nil,
                explainability: explainability
            )
        )

        #expect(context.title == "路由诊断：检查 Project Governance")
        #expect(context.detail?.contains("当前 XT 绑定缺少 permission owner（device_permission_owner_missing）") == true)
        #expect(context.detail?.contains("修复方向：先检查 trusted automation、permission owner、kill-switch、TTL 和当前项目绑定。") == true)
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

        #expect(context.title == "路由诊断：检查 Supervisor Control Center · AI 模型")
        #expect(context.detail?.contains("configured route=openai/gpt-5.4") == true)
        #expect(context.detail?.contains("actual route=Hub (Remote) -> openai/gpt-5.4 [local_fallback_after_remote_error]") == true)
        #expect(context.detail?.contains("fallback reason=目标模型当前不在可执行清单里（model_not_found）") == true)
    }

    @Test
    func focusContextForChooseModelHumanizesPaidModelBlockReason() throws {
        let context = try #require(
            RouteDiagnoseMessagePresentation.focusContext(
                for: .openChooseModel,
                latestEvent: makeEvent(
                    executionPath: "remote_error",
                    fallbackReasonCode: "device_paid_model_not_allowed;policy_mode=new_profile;device_name=Andrew;model_id=openai/gpt-5.4"
                )
            )
        )

        #expect(context.title == "路由诊断：检查 Supervisor Control Center · AI 模型")
        #expect(context.detail?.contains("fallback reason=当前模型不在这台设备的付费模型允许范围内（device_paid_model_not_allowed）") == true)
        #expect(context.detail?.contains("route state=当前付费模型资格或预算还没收敛，所以路由停在失败态。") == true)
    }

    @Test
    func focusContextForChooseModelUsesPassiveFallbackWhenRememberedRemoteWillBeAutoTried() throws {
        let context = try #require(
            RouteDiagnoseMessagePresentation.focusContext(
                for: .openChooseModel,
                latestEvent: nil,
                recommendation: HubModelPickerRecommendationState(
                    kind: .continueWithoutSwitch,
                    modelId: "openai/gpt-4.1",
                    message: "XT 会先自动改试 remembered remote。"
                )
            )
        )

        #expect(context.title == "路由诊断：检查 Supervisor Control Center · AI 模型")
        #expect(context.detail?.contains("不用手动切模型") == true)
        #expect(context.detail?.contains("自动改试上次稳定远端") == true)
    }

    @Test
    func focusContextForChooseModelResolvesEnglishFallbackCopy() throws {
        let context = try #require(
            RouteDiagnoseMessagePresentation.focusContext(
                for: .openChooseModel,
                latestEvent: nil,
                recommendation: HubModelPickerRecommendationState(
                    kind: .continueWithoutSwitch,
                    modelId: "openai/gpt-4.1",
                    message: "XT will retry the remembered remote."
                ),
                language: .english
            )
        )

        #expect(context.title == "Route Diagnose: Check Supervisor Control Center · AI Models")
        #expect(context.detail?.contains("do not need to switch manually") == true)
        #expect(context.detail?.contains("last stable remote model automatically") == true)
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

        #expect(context.title == "路由诊断：查看 XT 设置 → 诊断与核对")
        #expect(context.detail == "先核对当前路由事件、传输方式、模型可见性和最近连接状态。")
    }

    @Test
    func modelSettingsContextUsesLatestRouteDetails() {
        let context = RouteDiagnoseMessagePresentation.modelSettingsContext(
            latestEvent: makeEvent(
                executionPath: "local_fallback_after_remote_error",
                fallbackReasonCode: "model_not_found"
            )
        )

        #expect(context.title == "路由诊断：检查 Supervisor Control Center · AI 模型")
        #expect(context.detail?.contains("configured route=openai/gpt-5.4") == true)
        #expect(context.detail?.contains("fallback reason=目标模型当前不在可执行清单里（model_not_found）") == true)
        #expect(context.detail?.contains("真实可用视图") == true)
    }

    @Test
    func diagnosticsAndModelSettingsContextsCanCarryPairedDeviceBudgetTruth() {
        let paidAccessSnapshot = HubRemotePaidAccessSnapshot(
            trustProfilePresent: true,
            paidModelPolicyMode: "all_paid_models",
            dailyTokenLimit: 640,
            singleRequestTokenLimit: 256
        )
        let latestEvent = makeEvent(
            executionPath: "remote_error",
            fallbackReasonCode: "device_single_request_token_exceeded;policy_mode=new_profile;device_name=Andrew;model_id=openai/gpt-5.4"
        )

        let diagnostics = RouteDiagnoseMessagePresentation.diagnosticsContext(
            latestEvent: latestEvent,
            paidAccessSnapshot: paidAccessSnapshot
        )
        let modelSettings = RouteDiagnoseMessagePresentation.modelSettingsContext(
            latestEvent: latestEvent,
            paidAccessSnapshot: paidAccessSnapshot
        )

        #expect(diagnostics.detail?.contains("paired_device_truth=单次 256 tok · 当日 640 tok · 策略 全部付费模型") == true)
        #expect(modelSettings.detail?.contains("paired_device_truth=单次 256 tok · 当日 640 tok · 策略 全部付费模型") == true)
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

        #expect(context.title == "重连修复失败：查看 XT 设置 → 诊断与核对")
        #expect(context.detail?.contains("repair_reason=grpc_route_unavailable") == true)
        #expect(context.detail?.contains("route_event=role=coder") == true)
        #expect(context.detail?.contains("reason=grpc_route_unavailable") == true)
    }

    @Test
    func connectivityRepairNoticeUsesReconnectSuccessCopy() throws {
        let notice = try #require(
            RouteDiagnoseMessagePresentation.connectivityRepairNotice(
                for: .reconnectHubAndDiagnose,
                report: HubRemoteConnectReport(
                    ok: true,
                    route: .internet,
                    summary: "remote route restored",
                    logLines: [],
                    reasonCode: nil
                )
            )
        )

        #expect(notice.title == "Hub 已重连并已重诊断")
        #expect(notice.detail.contains("连接修复已完成"))
        #expect(notice.detail.contains("remote route restored"))
    }

    @Test
    func connectivityRepairNoticeUsesDiagnosticsFailureCopyWhenSummaryIsEmpty() throws {
        let notice = try #require(
            RouteDiagnoseMessagePresentation.connectivityRepairNotice(
                for: .connectHubAndDiagnose,
                report: HubRemoteConnectReport(
                    ok: false,
                    route: .none,
                    summary: "   ",
                    logLines: [],
                    reasonCode: "runtime_not_running"
                )
            )
        )

        #expect(notice.title == "连接修复未完成")
        #expect(notice.detail == "我已自动把焦点切到 XT 设置 → 诊断与核对，先看最新路由事件、连通性和失败原因。")
    }

    @Test
    func connectivityRepairNoticeUsesCompletionCopyWhenReportIsMissing() throws {
        let notice = try #require(
            RouteDiagnoseMessagePresentation.connectivityRepairNotice(
                for: .reconnectHubAndDiagnose,
                report: nil
            )
        )

        #expect(notice.title == "重连流程已结束")
        #expect(notice.detail.contains("重新对当前项目跑了一次路由诊断"))
    }

    @Test
    func actionOpenedNoticeMatchesRepairEntryPoints() throws {
        let chooseModel = try #require(
            RouteDiagnoseMessagePresentation.actionOpenedNotice(for: .openChooseModel)
        )
        #expect(chooseModel.title == "已打开 Supervisor Control Center · AI 模型")
        #expect(chooseModel.detail.contains("已经加载"))
        #expect(chooseModel.detail.contains("不一定需要立刻手动切模型"))

        let governance = try #require(
            RouteDiagnoseMessagePresentation.actionOpenedNotice(for: .openProjectGovernanceOverview)
        )
        #expect(governance.title == "已打开 Project Governance")
        #expect(governance.detail.contains("blocked planes"))

        let recovery = try #require(
            RouteDiagnoseMessagePresentation.actionOpenedNotice(for: .openHubRecovery)
        )
        #expect(recovery.title == "已打开 Hub 诊断与恢复")
        #expect(recovery.detail.contains("付费远端"))

        let log = try #require(
            RouteDiagnoseMessagePresentation.actionOpenedNotice(for: .openHubConnectionLog)
        )
        #expect(log.title == "已打开 Hub 日志")
        #expect(log.detail.contains("降到本地"))

        #expect(
            RouteDiagnoseMessagePresentation.actionOpenedNotice(for: .connectHubAndDiagnose) == nil
        )
    }

    @Test
    func directSettingsEntryNoticesExplainNextCheck() {
        let modelSettings = RouteDiagnoseMessagePresentation.modelSettingsOpenedNotice()
        #expect(modelSettings.title == "已打开 Supervisor Control Center · AI 模型")
        #expect(modelSettings.detail.contains("当前项目单独设置"))
        #expect(modelSettings.detail.contains("全局默认"))
        #expect(modelSettings.detail.contains("真实可用模型视图"))

        let diagnostics = RouteDiagnoseMessagePresentation.diagnosticsOpenedNotice()
        #expect(diagnostics.title == "已打开 XT 设置 → 诊断与核对")
        #expect(diagnostics.detail.contains("路由事件"))
        #expect(diagnostics.detail.contains("修 Hub"))
    }

    @Test
    func railFeedbackPlanKeepsInlineModelPickerQuiet() {
        let plan = RouteDiagnoseMessagePresentation.railFeedbackPlan(
            for: .inlineModelPickerOpened
        )

        #expect(plan.notice == nil)
        #expect(plan.shouldHighlight == false)
    }

    @Test
    func railFeedbackPlanHighlightsRepairSurfaceEntriesOnlyWhenTheyOpenAnotherSurface() throws {
        let chooseModel = RouteDiagnoseMessagePresentation.railFeedbackPlan(
            for: .repairSurfaceOpened(.openChooseModel)
        )
        #expect(try #require(chooseModel.notice).title == "已打开 Supervisor Control Center · AI 模型")
        #expect(chooseModel.shouldHighlight)

        let governance = RouteDiagnoseMessagePresentation.railFeedbackPlan(
            for: .repairSurfaceOpened(.openProjectGovernanceOverview)
        )
        #expect(try #require(governance.notice).title == "已打开 Project Governance")
        #expect(governance.shouldHighlight)

        let recovery = RouteDiagnoseMessagePresentation.railFeedbackPlan(
            for: .repairSurfaceOpened(.openHubRecovery)
        )
        #expect(try #require(recovery.notice).title == "已打开 Hub 诊断与恢复")
        #expect(recovery.shouldHighlight)

        let log = RouteDiagnoseMessagePresentation.railFeedbackPlan(
            for: .repairSurfaceOpened(.openHubConnectionLog)
        )
        #expect(try #require(log.notice).title == "已打开 Hub 日志")
        #expect(log.shouldHighlight)

        let connect = RouteDiagnoseMessagePresentation.railFeedbackPlan(
            for: .repairSurfaceOpened(.connectHubAndDiagnose)
        )
        #expect(connect.notice == nil)
        #expect(connect.shouldHighlight == false)
    }

    @Test
    func railFeedbackPlanHighlightsDirectSettingsEntries() throws {
        let modelSettings = RouteDiagnoseMessagePresentation.railFeedbackPlan(
            for: .modelSettingsOpened
        )
        #expect(try #require(modelSettings.notice).title == "已打开 Supervisor Control Center · AI 模型")
        #expect(modelSettings.shouldHighlight)

        let diagnostics = RouteDiagnoseMessagePresentation.railFeedbackPlan(
            for: .diagnosticsOpened
        )
        #expect(try #require(diagnostics.notice).title == "已打开 XT 设置 → 诊断与核对")
        #expect(diagnostics.shouldHighlight)
    }

    @Test
    func railFeedbackPlanWrapsConnectivityRepairCompletionCopy() throws {
        let success = RouteDiagnoseMessagePresentation.railFeedbackPlan(
            for: .connectivityRepairFinished(
                action: .reconnectHubAndDiagnose,
                report: HubRemoteConnectReport(
                    ok: true,
                    route: .internet,
                    summary: "remote route restored",
                    logLines: [],
                    reasonCode: nil
                )
            )
        )
        #expect(try #require(success.notice).title == "Hub 已重连并已重诊断")
        #expect(success.shouldHighlight)

        let completion = RouteDiagnoseMessagePresentation.railFeedbackPlan(
            for: .connectivityRepairFinished(
                action: .connectHubAndDiagnose,
                report: nil
            )
        )
        #expect(try #require(completion.notice).title == "连接流程已结束")
        #expect(completion.shouldHighlight)
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
        fallbackReasonCode: String,
        denyCode: String? = nil
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
            denyCode: denyCode,
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: ""
        )
    }

    private func supervisorRouteTruthMessage() -> String {
        """
项目路由诊断：coder

Supervisor 路由诊断：
- 决策=fail_closed
- deny_code=device_permission_owner_missing
- audit_ref=audit-route-test-1
- runtime readiness=A4 Agent runtime readiness 仍有缺口。
- 阻塞平面=grant_ready
- grant plane：权限宿主未就绪
- 建议动作：更像 Supervisor 的治理 / grant 面未 ready；先检查 trusted automation、permission owner、kill-switch 和当前 project 绑定。
"""
    }

    private func supervisorRouteRoutePlaneTruthMessage() -> String {
        """
项目路由诊断：coder

Supervisor 路由诊断：
- 决策=fail_closed
- deny_code=preferred_device_offline
- audit_ref=audit-route-test-2
- runtime readiness=A4 Agent runtime readiness 仍有缺口。
- 阻塞平面=route_ready
- route plane：首选 XT 设备当前离线
- 建议动作：更像 Supervisor 到 XT / runner 的路由面未 ready；先检查 XT 是否在线、preferred device 是否仍可达，以及 project scope 是否一致。
"""
    }
}
