import Foundation

enum RouteDiagnoseMessagePresentation {
    enum RepairAction: Equatable {
        case connectHubAndDiagnose
        case reconnectHubAndDiagnose
        case openChooseModel
        case openHubRecovery
        case openHubConnectionLog
    }

    enum RailFeedbackTrigger {
        case inlineModelPickerOpened
        case repairSurfaceOpened(RepairAction)
        case modelSettingsOpened
        case diagnosticsOpened
        case connectivityRepairFinished(
            action: RepairAction,
            report: HubRemoteConnectReport?
        )
    }

    struct RailFeedbackPlan: Equatable {
        var notice: XTSettingsChangeNotice?
        var shouldHighlight: Bool
    }

    static let coderHeading = "Project route diagnose: coder"

    static func matches(_ message: AXChatMessage) -> Bool {
        message.role == .assistant && matches(content: message.content)
    }

    static func matches(content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix(coderHeading)
    }

    static func recommendation(
        config: AXProjectConfig?,
        settings: XTerminalSettings,
        ctx: AXProjectContext,
        modelsState: ModelStateSnapshot
    ) -> HubModelPickerRecommendationState? {
        let configuredModelId = normalizedModelId(
            config?.modelOverride(for: .coder)
                ?? settings.assignment(for: .coder).model
        )
        guard let guidance = AXProjectModelRouteMemoryStore.selectionGuidance(
            configuredModelId: configuredModelId,
            role: .coder,
            ctx: ctx,
            snapshot: modelsState
        ),
        let recommendedModelId = normalizedModelId(guidance.recommendedModelId) else {
            return nil
        }

        let message = normalizedModelId(guidance.recommendationText) ?? guidance.warningText
        return HubModelPickerRecommendationState(
            modelId: recommendedModelId,
            message: message
        )
    }

    static func actionTitle(
        for recommendation: HubModelPickerRecommendationState,
        models: [HubModel]
    ) -> String {
        "改用 \(displayLabel(for: recommendation.modelId, models: models))"
    }

    static func repairAction(
        latestEvent: AXModelRouteDiagnosticEvent?,
        hubConnected: Bool,
        hubRemoteConnected: Bool,
        hasRecommendation: Bool
    ) -> RepairAction? {
        guard shouldOfferConnectivityRepair(latestEvent: latestEvent) else {
            if shouldOfferChooseModelRepair(latestEvent: latestEvent, hasRecommendation: hasRecommendation) {
                return .openChooseModel
            }
            if shouldOfferHubRecoveryRepair(latestEvent: latestEvent) {
                return .openHubRecovery
            }
            if shouldOfferHubConnectionLogRepair(latestEvent: latestEvent) {
                return .openHubConnectionLog
            }
            return nil
        }
        guard !hubConnected else {
            return nil
        }
        return hubRemoteConnected ? .reconnectHubAndDiagnose : .connectHubAndDiagnose
    }

    static func title(
        for action: RepairAction,
        inProgress: Bool
    ) -> String {
        switch action {
        case .connectHubAndDiagnose:
            return inProgress ? "连接中..." : "连接 Hub 并重诊断"
        case .reconnectHubAndDiagnose:
            return inProgress ? "重连中..." : "重连并重诊断"
        case .openChooseModel:
            return "检查已加载远端"
        case .openHubRecovery:
            return "检查 Hub Recovery"
        case .openHubConnectionLog:
            return "查看 Hub 日志"
        }
    }

    static func helperText(for action: RepairAction) -> String {
        switch action {
        case .connectHubAndDiagnose:
            return "这更像是 Hub 连接或 runtime 还没就绪。先补连通，再自动回到当前项目重跑一次路由诊断。"
        case .reconnectHubAndDiagnose:
            return "这更像是远端链路或 runtime 状态异常。先重连，再自动重跑一次当前项目的路由诊断。"
        case .openChooseModel:
            return "这更像是目标远端模型没加载，或当前配置还不在可直接执行的列表里。先到 Choose Model 检查已加载远端。"
        case .openHubRecovery:
            return "这更像是 Hub 的 remote export gate、配额或恢复链路拦住了 paid 路由。先到 Hub Recovery 看失败码和修复提示。"
        case .openHubConnectionLog:
            return "这更像是 Hub 侧把远端请求降到了本地。先看 Hub 日志和最近连接状态，再决定是否继续追 Hub 端降级原因。"
        }
    }

    static func focusContext(
        for action: RepairAction,
        latestEvent: AXModelRouteDiagnosticEvent?,
        recommendation: HubModelPickerRecommendationState? = nil
    ) -> XTSectionFocusContext? {
        switch action {
        case .openChooseModel:
            return XTSectionFocusContext(
                title: "路由诊断：检查已加载远端",
                detail: focusDetail(
                    latestEvent: latestEvent,
                    fallback: "优先确认目标远端是否已经 loaded；如果只是想先继续，改到一个已加载远端更稳。"
                )
            )
        case .openHubRecovery:
            return XTSectionFocusContext(
                title: "路由诊断：检查 Hub Recovery",
                detail: focusDetail(
                    latestEvent: latestEvent,
                    fallback: "这更像是 remote export gate、配额或 paid route 恢复问题；先看失败码和恢复入口。"
                )
            )
        case .openHubConnectionLog:
            return XTSectionFocusContext(
                title: "路由诊断：查看 Hub 日志",
                detail: focusDetail(
                    latestEvent: latestEvent,
                    fallback: "这更像是 Hub 侧把远端请求降到了本地；先看最近连接日志和降级线索。"
                )
            )
        case .connectHubAndDiagnose, .reconnectHubAndDiagnose:
            return nil
        }
    }

    static func diagnosticsContext(
        latestEvent: AXModelRouteDiagnosticEvent?
    ) -> XTSectionFocusContext {
        XTSectionFocusContext(
            title: "路由诊断：查看 XT Diagnostics",
            detail: focusDetail(
                latestEvent: latestEvent,
                fallback: "先核对当前 route event、transport、模型可见性和最近连接状态。"
            )
        )
    }

    static func modelSettingsContext(
        latestEvent: AXModelRouteDiagnosticEvent?
    ) -> XTSectionFocusContext {
        XTSectionFocusContext(
            title: "路由诊断：检查 coder 模型设置",
            detail: focusDetail(
                latestEvent: latestEvent,
                fallback: "如果你想固定当前项目的 coder 默认模型，可在这里直接切换。"
            )
        )
    }

    static func diagnosticsFailureContext(
        for action: RepairAction,
        report: HubRemoteConnectReport?,
        latestEvent: AXModelRouteDiagnosticEvent?
    ) -> XTSectionFocusContext {
        let title: String
        switch action {
        case .connectHubAndDiagnose:
            title = "连接修复失败：查看 XT Diagnostics"
        case .reconnectHubAndDiagnose:
            title = "重连修复失败：查看 XT Diagnostics"
        case .openChooseModel, .openHubRecovery, .openHubConnectionLog:
            title = "路由诊断：查看 XT Diagnostics"
        }

        let reportReason = normalizedModelId(report?.reasonCode) ?? normalizedModelId(report?.summary)
        let eventText = normalizedModelId(latestEvent?.diagnosticLine(includeProject: false))
        let parts = [
            reportReason.map { "repair_reason=\($0)" },
            eventText.map { "route_event=\($0)" }
        ].compactMap { $0 }
        let detail = parts.isEmpty ? "连接修复没有成功，先看 XT Diagnostics 里的最新 route event 和连接状态。" : parts.joined(separator: "；")
        return XTSectionFocusContext(title: title, detail: detail)
    }

    static func connectivityRepairNotice(
        for action: RepairAction,
        report: HubRemoteConnectReport?
    ) -> XTSettingsChangeNotice? {
        switch action {
        case .connectHubAndDiagnose, .reconnectHubAndDiagnose:
            break
        case .openChooseModel, .openHubRecovery, .openHubConnectionLog:
            return nil
        }

        guard let report else {
            let title: String
            switch action {
            case .connectHubAndDiagnose:
                title = "连接流程已结束"
            case .reconnectHubAndDiagnose:
                title = "重连流程已结束"
            case .openChooseModel, .openHubRecovery, .openHubConnectionLog:
                title = "修复流程已结束"
            }

            return XTSettingsChangeNotice(
                title: title,
                detail: "没有拿到额外的 Hub 修复报告，但已重新对当前项目跑了一次路由诊断。"
            )
        }

        if report.ok {
            let title: String
            switch action {
            case .connectHubAndDiagnose:
                title = "Hub 已连接并已重诊断"
            case .reconnectHubAndDiagnose:
                title = "Hub 已重连并已重诊断"
            case .openChooseModel, .openHubRecovery, .openHubConnectionLog:
                title = "修复已完成"
            }

            let summary = report.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = summary.isEmpty
                ? "连接修复已完成，并重新对当前项目跑了一次路由诊断。"
                : "连接修复已完成，并重新对当前项目跑了一次路由诊断。\(summary)"
            return XTSettingsChangeNotice(title: title, detail: detail)
        }

        let title: String
        switch action {
        case .connectHubAndDiagnose:
            title = "连接修复未完成"
        case .reconnectHubAndDiagnose:
            title = "重连修复未完成"
        case .openChooseModel, .openHubRecovery, .openHubConnectionLog:
            title = "修复未完成"
        }

        let summary = report.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = summary.isEmpty
            ? "我已自动把焦点切到 XT Diagnostics，先看最新 route event、连通性和失败原因。"
            : "我已自动把焦点切到 XT Diagnostics。\(summary)"
        return XTSettingsChangeNotice(title: title, detail: detail)
    }

    static func actionOpenedNotice(
        for action: RepairAction
    ) -> XTSettingsChangeNotice? {
        switch action {
        case .openChooseModel:
            return XTSettingsChangeNotice(
                title: "已打开 Choose Model",
                detail: "先确认目标远端是否已经 loaded；如果只是想继续推进，先切到一个已加载候选最稳。"
            )
        case .openHubRecovery:
            return XTSettingsChangeNotice(
                title: "已打开 Hub Recovery",
                detail: "先看失败码、恢复链路和 paid route 相关提示，再决定是不是继续追 Hub 端降级原因。"
            )
        case .openHubConnectionLog:
            return XTSettingsChangeNotice(
                title: "已打开 Hub 日志",
                detail: "先核对最近连接状态、远端请求是否被降到本地，以及对应的失败码或恢复线索。"
            )
        case .connectHubAndDiagnose, .reconnectHubAndDiagnose:
            return nil
        }
    }

    static func modelSettingsOpenedNotice() -> XTSettingsChangeNotice {
        XTSettingsChangeNotice(
            title: "已打开 coder 模型设置",
            detail: "先确认当前项目 override 和全局默认是不是一致；如果目标模型没 loaded，运行时仍可能回退到本地。"
        )
    }

    static func diagnosticsOpenedNotice() -> XTSettingsChangeNotice {
        XTSettingsChangeNotice(
            title: "已打开 XT Diagnostics",
            detail: "先核对最近 route event、连通性、模型可见性和失败原因，再决定是改模型还是修 Hub。"
        )
    }

    static func railFeedbackPlan(
        for trigger: RailFeedbackTrigger
    ) -> RailFeedbackPlan {
        let notice: XTSettingsChangeNotice? = {
            switch trigger {
            case .inlineModelPickerOpened:
                return nil
            case .repairSurfaceOpened(let action):
                return actionOpenedNotice(for: action)
            case .modelSettingsOpened:
                return modelSettingsOpenedNotice()
            case .diagnosticsOpened:
                return diagnosticsOpenedNotice()
            case .connectivityRepairFinished(let action, let report):
                return connectivityRepairNotice(for: action, report: report)
            }
        }()

        return RailFeedbackPlan(
            notice: notice,
            shouldHighlight: notice != nil
        )
    }

    static func displayLabel(
        for modelId: String,
        models: [HubModel]
    ) -> String {
        let trimmedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelId.isEmpty else { return modelId }

        if let model = models.first(where: {
            $0.id.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmedModelId) == .orderedSame
        }) {
            let display = model.capabilityPresentationModel.displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty, display.count <= 24 {
                return display
            }
        }

        let catalogDisplay = XTModelCatalog.modelInfo(for: trimmedModelId).displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !catalogDisplay.isEmpty, catalogDisplay.count <= 24 {
            return catalogDisplay
        }

        return trimmedModelId
    }

    private static func normalizedModelId(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func focusDetail(
        latestEvent: AXModelRouteDiagnosticEvent?,
        fallback: String
    ) -> String {
        guard let latestEvent else { return fallback }

        var parts: [String] = []
        if let requested = normalizedModelId(latestEvent.requestedModelId) {
            parts.append("requested=\(requested)")
        }
        if let actual = normalizedModelId(latestEvent.actualModelId) {
            parts.append("actual=\(actual)")
        }
        if let reason = normalizedModelId(latestEvent.fallbackReasonCode) {
            parts.append("reason=\(reason)")
        }
        let summary = parts.joined(separator: "；")
        return summary.isEmpty ? fallback : "\(summary)。\(fallback)"
    }

    private static func shouldOfferConnectivityRepair(
        latestEvent: AXModelRouteDiagnosticEvent?
    ) -> Bool {
        guard let latestEvent else { return false }

        switch normalizedReasonCode(latestEvent.fallbackReasonCode) {
        case "response_timeout", "grpc_route_unavailable", "runtime_not_running", "request_write_failed":
            return true
        default:
            return false
        }
    }

    private static func shouldOfferChooseModelRepair(
        latestEvent: AXModelRouteDiagnosticEvent?,
        hasRecommendation: Bool
    ) -> Bool {
        guard let latestEvent, !hasRecommendation else { return false }
        switch normalizedReasonCode(latestEvent.fallbackReasonCode) {
        case "model_not_found", "remote_model_not_found":
            return true
        default:
            return false
        }
    }

    private static func shouldOfferHubRecoveryRepair(
        latestEvent: AXModelRouteDiagnosticEvent?
    ) -> Bool {
        guard let latestEvent else { return false }
        switch normalizedReasonCode(latestEvent.fallbackReasonCode) {
        case "remote_export_blocked":
            return true
        default:
            return false
        }
    }

    private static func shouldOfferHubConnectionLogRepair(
        latestEvent: AXModelRouteDiagnosticEvent?
    ) -> Bool {
        guard let latestEvent else { return false }
        switch normalizedReasonCode(latestEvent.fallbackReasonCode) {
        case "downgrade_to_local":
            return true
        default:
            break
        }
        return latestEvent.executionPath.trimmingCharacters(in: .whitespacesAndNewlines) == "hub_downgraded_to_local"
    }

    private static func normalizedReasonCode(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
