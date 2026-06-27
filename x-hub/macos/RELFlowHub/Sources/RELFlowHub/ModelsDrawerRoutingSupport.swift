import SwiftUI
import RELFlowHubCore

extension ModelsDrawer {
    func currentRouteDecision(for taskType: HubTaskType) -> HubTaskRouteDecision {
        HubTaskRoutingPolicy.decision(
            taskType: taskType,
            models: modelStore.snapshot.models,
            preferredModelId: effectivePreferredModelId(for: taskType),
            allowAutoLoad: routeAllowAutoLoad
        )
    }

    func effectivePreferredModelId(for taskType: HubTaskType) -> String {
        (store.routingPreferredModelIdByTask[taskType.rawValue] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func routePreferenceLabel(for taskType: HubTaskType) -> String {
        let modelId = effectivePreferredModelId(for: taskType)
        guard !modelId.isEmpty else {
            return "\(taskType.label): Auto"
        }
        let modelName = modelStore.snapshot.models.first(where: { $0.id == modelId })?.name
            ?? remoteModels.first(where: { $0.id == modelId })?.nestedDisplayName
            ?? modelId
        return "\(taskType.label): \(modelName)"
    }

    func routePreferenceShortLabel(for taskType: HubTaskType) -> String {
        let modelId = effectivePreferredModelId(for: taskType)
        guard !modelId.isEmpty else { return "Auto" }
        return modelStore.snapshot.models.first(where: { $0.id == modelId })?.name
            ?? remoteModels.first(where: { $0.id == modelId })?.nestedDisplayName
            ?? modelId
    }

    func routeTaskSystemName(_ taskType: HubTaskType) -> String {
        switch taskType {
        case .supervisor:
            return "point.topleft.down.curvedto.point.bottomright.up"
        case .coder:
            return "chevron.left.forwardslash.chevron.right"
        case .reviewer:
            return "checkmark.seal"
        }
    }

    func routeTaskPurposeText(_ taskType: HubTaskType) -> String {
        switch taskType {
        case .supervisor:
            return "规划、调度、拆解"
        case .coder:
            return "代码、执行、低延迟"
        case .reviewer:
            return "审查、校验、质量优先"
        }
    }

    func routeRecommendationDetail(_ decision: HubTaskRouteDecision) -> String {
        guard !decision.modelId.isEmpty else {
            return "没有可路由模型；先添加本地模型或远程模型。"
        }
        let provider = modelStore.snapshot.models
            .first(where: { $0.id == decision.modelId })
            .map(providerTitle(for:)) ?? "Hub"
        let auto = decision.willAutoLoad ? " · 需要自动加载" : ""
        return "\(provider) · \(routeReasonText(decision.reason))\(auto)"
    }

    func routeMatrixRow(
        id: String,
        title: String,
        decision: HubTaskRouteDecision
    ) -> ModelsDrawerRouteMatrixRow {
        guard !decision.modelId.isEmpty else {
            return ModelsDrawerRouteMatrixRow(
                id: id,
                title: title,
                modelName: "未路由",
                provider: "",
                statusText: "Blocked",
                statusColor: .orange,
                reason: routeReasonText(decision.reason)
            )
        }

        let model = modelStore.snapshot.models.first(where: { $0.id == decision.modelId })
        return ModelsDrawerRouteMatrixRow(
            id: id,
            title: title,
            modelName: decision.modelName,
            provider: model.map(providerTitle(for:)) ?? "Hub",
            statusText: decision.willAutoLoad ? "Auto" : modelStateText(decision.modelState ?? .available),
            statusColor: decision.willAutoLoad ? .indigo : modelStateColor(decision.modelState ?? .available),
            reason: routeReasonText(decision.reason)
        )
    }

    func bestModelRouteRow(
        id: String,
        title: String,
        models: [HubModel],
        reason: String
    ) -> ModelsDrawerRouteMatrixRow {
        guard let model = models.first else {
            return ModelsDrawerRouteMatrixRow(
                id: id,
                title: title,
                modelName: "未匹配",
                provider: "",
                statusText: "None",
                statusColor: .secondary,
                reason: "没有匹配能力"
            )
        }
        return ModelsDrawerRouteMatrixRow(
            id: id,
            title: title,
            modelName: model.name,
            provider: providerTitle(for: model),
            statusText: modelStateText(model.state),
            statusColor: modelStateColor(model.state),
            reason: reason
        )
    }

    func runRouteCheck(task: HubTaskType, decision: HubTaskRouteDecision) {
        let modelId = decision.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else { return }
        routeCheckModelId = modelId
        routeCheckTaskId = task.rawValue

        if let remote = remoteEntry(forModelId: modelId) {
            routeCheckFeedback = "已发起 \(task.label) 的 \(decision.modelName.isEmpty ? modelId : decision.modelName) 远程连通性测试。"
            store.testRemoteModelConnectivity(remote)
            return
        }

        if let model = modelStore.snapshot.models.first(where: { $0.id == modelId }),
           LocalModelRuntimeActionPlanner.isRemoteModel(model) {
            routeCheckFeedback = "找不到 \(task.label) 使用的 \(model.name) 远程模型配置，不能发起连接测试。"
            return
        }

        routeCheckFeedback = "已发起 \(task.label) 的 \(decision.modelName.isEmpty ? modelId : decision.modelName) 本地轻量预检。"
        store.quickCheckLocalModelHealth(for: [modelId])
    }

    func remoteEntry(forModelId modelId: String) -> RemoteModelEntry? {
        let normalized = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if let cached = remoteModels.first(where: { remoteModelMatches($0, modelId: normalized) }) {
            return cached
        }
        return RemoteModelStorage.load().models.first(where: { remoteModelMatches($0, modelId: normalized) })
    }

    func remoteModelMatches(_ entry: RemoteModelEntry, modelId: String) -> Bool {
        let normalized = modelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return entry.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
            || entry.effectiveProviderModelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
            || entry.nestedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
    }

    func libraryTrialStatus(for item: ModelsDrawerLibraryItem) -> ModelTrialStatus? {
        if let remoteEntry = item.remoteEntry {
            return store.remoteModelTrialStatus(for: remoteEntry.id)
        }
        return item.isLocal
            ? store.localModelTrialStatus(for: item.modelId)
            : store.remoteModelTrialStatus(for: item.modelId)
    }

    func routeTrialStatus(for decision: HubTaskRouteDecision) -> ModelTrialStatus? {
        let modelId = decision.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else { return nil }
        if let remote = remoteModels.first(where: { remoteModelMatches($0, modelId: modelId) }) {
            return store.remoteModelTrialStatus(for: remote.id)
        }
        if let model = modelStore.snapshot.models.first(where: { $0.id == modelId }),
           LocalModelRuntimeActionPlanner.isRemoteModel(model) {
            return store.remoteModelTrialStatus(for: modelId)
        }
        return store.localModelTrialStatus(for: modelId)
    }

    func routeReasonText(_ reason: String) -> String {
        switch reason {
        case "preferred_model": return "用户指定"
        case "task_match_loaded", "role_match_loaded": return "任务匹配且已就绪"
        case "task_match_autoload", "role_match_autoload": return "任务匹配，可自动加载"
        case "fallback_loaded": return "回退到已就绪模型"
        case "fallback_autoload": return "回退到可自动加载模型"
        case "no_models_registered": return "没有注册模型"
        case "model_not_loaded": return "没有已加载模型"
        default: return reason
        }
    }
}
