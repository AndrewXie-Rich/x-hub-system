import Foundation

extension SupervisorManager {
    func normalizedModelIdentity(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "（已加载，名称：", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "）", with: "")
    }

    func currentHubTransportSummary() -> String {
        let mode = HubAIClient.transportMode()
        let decision = HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: true)
        return "\(mode.rawValue) - \(supervisorRouteDecisionText(decision))"
    }

    func resolvedPreferredSupervisorModelID(configuredModelId: String? = nil) -> String? {
        let configured = configuredModelId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? configuredModelId
            : currentPreferredModelID(for: .supervisor)
        let snapshot = ModelStateSnapshot(
            models: supervisorModelInventory(),
            updatedAt: appModel?.modelsState.updatedAt ?? Date().timeIntervalSince1970
        )
        return HubAIClient.sanitizedInteractiveGenerateModelID(
            configured,
            snapshot: snapshot,
            taskType: "supervisor"
        )
    }

    func supervisorRetrievalModelSummary() -> String? {
        let retrievalModels = supervisorModelInventory().filter(\.isEmbeddingModel)
        guard !retrievalModels.isEmpty else { return nil }

        let ordered = retrievalModels.sorted { lhs, rhs in
            if lhs.state != rhs.state { return lhs.state == .loaded }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }

        let listed = ordered.prefix(3).map { model in
            "\(model.id) (\(model.state == .loaded ? "loaded" : "available"))"
        }
        guard !listed.isEmpty else { return nil }
        let suffix = ordered.count > listed.count ? " +\(ordered.count - listed.count) more" : ""
        return listed.joined(separator: ", ") + suffix
    }

    func currentSupervisorModelRouteSummary() -> String {
        currentConfiguredSupervisorModelRouteSummary()
    }

    func contextualSupervisorModelRouteSummary(
        userMessage: String,
        projects: [AXProjectEntry]
    ) -> String {
        let configuredSummary = currentConfiguredSupervisorModelRouteSummary()
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return configuredSummary }

        guard let routeContext = resolvedSupervisorModelRouteContext(
            userMessage: trimmed,
            projects: projects
        ) else {
            return configuredSummary
        }
        let intentSummary = currentSupervisorTaskIntentSummary(for: routeContext)
        return "\(configuredSummary) | \(intentSummary)"
    }

    func currentConfiguredSupervisorModelRouteSummary() -> String {
        guard let preferred = currentPreferredModelID(for: .supervisor) else {
            return "未绑定固定 model id，当前按默认 Hub 路由执行。"
        }
        if let matched = supervisorModelInventory().first(where: {
            $0.id.compare(preferred, options: .caseInsensitive) == .orderedSame
        }) {
            if !matched.isSelectableForInteractiveRouting {
                let disabledReason = matched.interactiveRoutingDisabledReason ?? "当前 Supervisor 对话不会直接使用这个模型。"
                if let resolved = resolvedPreferredSupervisorModelID(configuredModelId: preferred),
                   !resolved.isEmpty {
                    return "\(matched.id)（非对话模型，名称：\(matched.name)；\(disabledReason) 当前 Supervisor 对话会改用 \(resolved)）"
                }
                return "\(matched.id)（非对话模型，名称：\(matched.name)；\(disabledReason) 当前 Supervisor 对话会回到默认 Hub 路由）"
            }
            let stateText: String
            switch matched.state {
            case .loaded:
                stateText = "已加载"
            case .available:
                stateText = "可用"
            case .sleeping:
                stateText = "休眠"
            }
            return "\(matched.id)（\(stateText)，名称：\(matched.name)）"
        }
        return "\(preferred)（当前 Hub 模型清单里暂未看到这个 id）"
    }
}
