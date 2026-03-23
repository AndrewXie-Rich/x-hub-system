import Foundation

struct AXProjectModelRouteMemory: Equatable {
    var role: AXRole
    var lastHealthyRemoteModelId: String
    var consecutiveRemoteFallbackCount: Int
    var lastRequestedModelId: String
    var lastActualModelId: String
    var lastFailureReasonCode: String
    var lastExecutionPath: String
    var lastObservedAt: Double

    var shouldSuggestLocalModeNotice: Bool {
        consecutiveRemoteFallbackCount >= 2
    }
}

struct AXProjectPreferredModelRouteDecision: Equatable {
    var preferredModelId: String?
    var configuredModelId: String?
    var rememberedRemoteModelId: String?
    var preferredLocalModelId: String?
    var usedRememberedRemoteModel: Bool
    var forceLocalExecution: Bool
    var reasonCode: String?
}

struct AXProjectModelSelectionGuidance: Equatable {
    var warningText: String
    var recommendedModelId: String?
    var recommendationText: String?
    var recommendationKind: AXProjectModelSelectionRecommendationKind = .switchRecommended
}

enum AXProjectModelSelectionRecommendationKind: Equatable {
    case switchRecommended
    case continueWithoutSwitch
}

enum AXProjectModelRouteMemoryStore {
    private static let localLockConsecutiveFallbackThreshold = 3
    private static let localLockFreshnessWindowSec: Double = 6 * 60 * 60

    private struct UsageRecord {
        var role: AXRole
        var createdAt: Double
        var requestedModelId: String
        var actualModelId: String
        var executionPath: String
        var fallbackReasonCode: String
    }

    static func load(forProjectId projectId: String?, role: AXRole) -> AXProjectModelRouteMemory? {
        let trimmedProjectId = (projectId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProjectId.isEmpty else { return nil }
        guard let entry = AXProjectRegistryStore.load().project(for: trimmedProjectId) else { return nil }
        let root = URL(fileURLWithPath: entry.rootPath, isDirectory: true)
        return load(for: AXProjectContext(root: root), role: role)
    }

    static func load(for ctx: AXProjectContext, role: AXRole) -> AXProjectModelRouteMemory? {
        let records = usageRecords(for: ctx, role: role)
        guard !records.isEmpty else { return nil }

        var lastHealthyRemoteModelId = ""
        for record in records.reversed() {
            if record.executionPath == "remote_model",
               !record.actualModelId.isEmpty {
                lastHealthyRemoteModelId = record.actualModelId
                break
            }
        }

        let recent = records.last!
        var consecutiveFallbacks = 0
        for record in records.reversed() {
            guard isRemoteFailure(record) else { break }
            consecutiveFallbacks += 1
        }

        return AXProjectModelRouteMemory(
            role: role,
            lastHealthyRemoteModelId: lastHealthyRemoteModelId,
            consecutiveRemoteFallbackCount: consecutiveFallbacks,
            lastRequestedModelId: recent.requestedModelId,
            lastActualModelId: recent.actualModelId,
            lastFailureReasonCode: recent.fallbackReasonCode,
            lastExecutionPath: recent.executionPath,
            lastObservedAt: recent.createdAt
        )
    }

    static func resolvePreferredModel(
        configuredModelId rawConfiguredModelId: String?,
        role: AXRole,
        ctx: AXProjectContext?,
        snapshot: ModelStateSnapshot,
        localSnapshot: ModelStateSnapshot? = nil
    ) -> AXProjectPreferredModelRouteDecision {
        let configuredModelId = HubAIClient.normalizeConfiguredModelID(
            rawConfiguredModelId,
            availableModels: snapshot.models
        )
        let configuredAssessment = HubModelSelectionAdvisor.assess(
            requestedId: configuredModelId,
            snapshot: snapshot
        )
        let routeMemory = ctx.flatMap { load(for: $0, role: role) }
        let rememberedRemoteModelId = HubAIClient.normalizeConfiguredModelID(
            routeMemory?.lastHealthyRemoteModelId,
            availableModels: snapshot.models
        )
        let rememberedAssessment = HubModelSelectionAdvisor.assess(
            requestedId: rememberedRemoteModelId,
            snapshot: snapshot
        )

        guard let configuredModelId, !configuredModelId.isEmpty else {
            return AXProjectPreferredModelRouteDecision(
                preferredModelId: configuredModelId,
                configuredModelId: configuredModelId,
                rememberedRemoteModelId: rememberedRemoteModelId,
                preferredLocalModelId: nil,
                usedRememberedRemoteModel: false,
                forceLocalExecution: false,
                reasonCode: nil
            )
        }

        if configuredAssessment?.isExactMatchLoaded == true {
            return AXProjectPreferredModelRouteDecision(
                preferredModelId: configuredModelId,
                configuredModelId: configuredModelId,
                rememberedRemoteModelId: rememberedRemoteModelId,
                preferredLocalModelId: nil,
                usedRememberedRemoteModel: false,
                forceLocalExecution: false,
                reasonCode: nil
            )
        }

        if rememberedAssessment?.isExactMatchLoaded == true,
           modelIDsDiffer(rememberedRemoteModelId, configuredModelId) {
            return AXProjectPreferredModelRouteDecision(
                preferredModelId: rememberedRemoteModelId,
                configuredModelId: configuredModelId,
                rememberedRemoteModelId: rememberedRemoteModelId,
                preferredLocalModelId: nil,
                usedRememberedRemoteModel: true,
                forceLocalExecution: false,
                reasonCode: "project_last_remote_success_loaded"
            )
        }

        if configuredAssessment?.nonInteractiveExactMatch != nil {
            return AXProjectPreferredModelRouteDecision(
                preferredModelId: nil,
                configuredModelId: configuredModelId,
                rememberedRemoteModelId: rememberedRemoteModelId,
                preferredLocalModelId: nil,
                usedRememberedRemoteModel: false,
                forceLocalExecution: false,
                reasonCode: "project_configured_model_retrieval_only"
            )
        }

        if let localLock = resolveLocalLock(
            routeMemory: routeMemory,
            configuredAssessment: configuredAssessment,
            rememberedAssessment: rememberedAssessment,
            snapshot: snapshot,
            localSnapshot: localSnapshot
        ) {
            return AXProjectPreferredModelRouteDecision(
                preferredModelId: localLock.modelId,
                configuredModelId: configuredModelId,
                rememberedRemoteModelId: rememberedRemoteModelId,
                preferredLocalModelId: localLock.modelId,
                usedRememberedRemoteModel: false,
                forceLocalExecution: true,
                reasonCode: localLock.reasonCode
            )
        }

        if configuredAssessment?.exactMatch != nil {
            return AXProjectPreferredModelRouteDecision(
                preferredModelId: configuredModelId,
                configuredModelId: configuredModelId,
                rememberedRemoteModelId: rememberedRemoteModelId,
                preferredLocalModelId: nil,
                usedRememberedRemoteModel: false,
                forceLocalExecution: false,
                reasonCode: nil
            )
        }

        if rememberedAssessment?.exactMatch != nil,
           modelIDsDiffer(rememberedRemoteModelId, configuredModelId) {
            return AXProjectPreferredModelRouteDecision(
                preferredModelId: rememberedRemoteModelId,
                configuredModelId: configuredModelId,
                rememberedRemoteModelId: rememberedRemoteModelId,
                preferredLocalModelId: nil,
                usedRememberedRemoteModel: true,
                forceLocalExecution: false,
                reasonCode: "project_last_remote_success_inventory"
            )
        }

        return AXProjectPreferredModelRouteDecision(
            preferredModelId: configuredModelId,
            configuredModelId: configuredModelId,
            rememberedRemoteModelId: rememberedRemoteModelId,
            preferredLocalModelId: nil,
            usedRememberedRemoteModel: false,
            forceLocalExecution: false,
            reasonCode: nil
        )
    }

    static func heartbeatNotice(
        for project: AXProjectEntry,
        role: AXRole = .coder,
        snapshot: ModelStateSnapshot? = nil,
        localSnapshot: ModelStateSnapshot? = nil,
        now: Double = Date().timeIntervalSince1970
    ) -> String? {
        let rawRoot = project.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawRoot.isEmpty else { return nil }
        let ctx = AXProjectContext(root: URL(fileURLWithPath: rawRoot, isDirectory: true))
        guard let routeMemory = load(for: ctx, role: role),
              routeMemory.shouldSuggestLocalModeNotice else { return nil }

        let resolvedSnapshot = snapshot ?? loadHeartbeatModelsSnapshot()
        let configuredModelId = heartbeatConfiguredModelId(
            ctx: ctx,
            role: role,
            routeMemory: routeMemory,
            snapshot: resolvedSnapshot
        )
        let rememberedRemoteModelId = heartbeatRememberedRemoteModelId(
            routeMemory: routeMemory,
            snapshot: resolvedSnapshot
        )
        let configuredAssessment = resolvedSnapshot.flatMap {
            HubModelSelectionAdvisor.assess(
                requestedId: configuredModelId,
                snapshot: $0
            )
        }
        let rememberedAssessment = resolvedSnapshot.flatMap {
            HubModelSelectionAdvisor.assess(
                requestedId: rememberedRemoteModelId,
                snapshot: $0
            )
        }

        if configuredAssessment?.isExactMatchLoaded == true {
            return nil
        }

        let requested = configuredModelId.isEmpty
            ? routeMemory.lastRequestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
            : configuredModelId
        let remembered = rememberedRemoteModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = routeMemory.lastFailureReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestText = requested.isEmpty ? "远端模型" : requested
        let reasonText = reason.isEmpty ? "" : "（原因：\(reason)）"
        let actionHint = heartbeatActionHint(
            project: project,
            ctx: ctx,
            routeMemory: routeMemory,
            requestText: requestText
        )

        if rememberedAssessment?.isExactMatchLoaded == true,
           modelIDsDiffer(remembered, requestText),
           !remembered.isEmpty {
            return "模型路由：\(project.displayName) 当前配置的 `\(requestText)` 还不能直接执行；XT 现在会先试这个项目上次稳定的远端 `\(remembered)`，避免继续直接掉到本地。\(heartbeatRememberedRemoteActionHint(project: project, requestText: requestText, rememberedText: remembered))"
        }

        if shouldForceLocalExecution(routeMemory: routeMemory, now: now) {
            let localModel = heartbeatPreferredLocalModelLabel(
                routeMemory: routeMemory,
                snapshot: resolvedSnapshot,
                localSnapshot: localSnapshot
            )
            let localText = localModel.isEmpty || localModel == "本地模型" ? "本地模型" : "`\(localModel)`"
            return "模型路由：\(project.displayName) 已切到本地模式；`\(requestText)` 最近连续 \(routeMemory.consecutiveRemoteFallbackCount) 次未稳定命中\(reasonText)，当前先锁定 \(localText) 执行。建议检查 Hub 配置后再恢复远端。\(actionHint)"
        }
        return "模型路由：\(project.displayName) 最近已连续 \(routeMemory.consecutiveRemoteFallbackCount) 次切到本地；`\(requestText)` 未稳定命中\(reasonText)，建议检查 Hub 配置后再重试。\(actionHint)"
    }

    static func selectionGuidance(
        configuredModelId rawConfiguredModelId: String?,
        role: AXRole,
        ctx: AXProjectContext?,
        snapshot: ModelStateSnapshot,
        localSnapshot: ModelStateSnapshot? = nil
    ) -> AXProjectModelSelectionGuidance? {
        guard let ctx else { return nil }

        let configuredModelId = HubAIClient.normalizeConfiguredModelID(
            rawConfiguredModelId,
            availableModels: snapshot.models
        )
        let configuredAssessment = HubModelSelectionAdvisor.assess(
            requestedId: configuredModelId,
            snapshot: snapshot
        )
        let routeMemory = load(for: ctx, role: role)
        let rememberedRemoteModelId = HubAIClient.normalizeConfiguredModelID(
            routeMemory?.lastHealthyRemoteModelId,
            availableModels: snapshot.models
        )
        let rememberedAssessment = HubModelSelectionAdvisor.assess(
            requestedId: rememberedRemoteModelId,
            snapshot: snapshot
        )

        if let routeMemory,
           shouldPreferLocalLock(
                configuredAssessment: configuredAssessment,
                rememberedAssessment: rememberedAssessment
           ),
           shouldForceLocalExecution(routeMemory: routeMemory, now: Date().timeIntervalSince1970) {
            let requestedModel = configuredModelId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? configuredModelId!.trimmingCharacters(in: .whitespacesAndNewlines)
                : routeMemory.lastRequestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
            let localModel = resolvedPreferredLocalModelLabel(
                routeMemory: routeMemory,
                snapshot: snapshot,
                localSnapshot: localSnapshot
            )
            let reason = routeMemory.lastFailureReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let reasonText = reason.isEmpty ? "" : "（最近原因：\(reason)）"
            let requestedText = requestedModel.isEmpty ? "当前远端模型" : requestedModel
            let suggestedRemote: String? = {
                guard let raw = configuredAssessment?.loadedCandidates.first?.id else { return nil }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }()
            let recommendationText: String? = {
                guard let suggestedRemote,
                      !suggestedRemote.isEmpty,
                      modelIDsDiffer(suggestedRemote, requestedText) else {
                    return nil
                }
                return "如果你现在就要继续，可改用当前已加载的可执行模型 `\(suggestedRemote)`，避免先锁本地；等 `\(requestedText)` 在 Hub 恢复后再切回来。"
            }()
            return AXProjectModelSelectionGuidance(
                warningText: "这个项目最近连续 \(routeMemory.consecutiveRemoteFallbackCount) 次没有稳定命中 `\(requestedText)`\(reasonText)，XT 现在会先锁到本地 `\(localModel)`。如果你要恢复远端，先去 Hub -> Models 确认 `\(requestedText)` 已加载，再重试。",
                recommendedModelId: suggestedRemote,
                recommendationText: recommendationText
            )
        }

        if rememberedAssessment?.isExactMatchLoaded == true,
           modelIDsDiffer(rememberedRemoteModelId, configuredModelId),
           let configured = configuredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty,
           let remembered = rememberedRemoteModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remembered.isEmpty {
            return AXProjectModelSelectionGuidance(
                warningText: "当前配置的 `\(configured)` 还不能直接执行；XT 下次会先试这个项目上次稳定的远端 `\(remembered)`，避免直接掉到本地。",
                recommendedModelId: remembered,
                recommendationText: "这个项目上次稳定跑通的是 `\(remembered)`。如果你现在只是继续工作，不用手动切模型；XT 下次会先试它。只有你想把它固定成当前配置时，再手动切。",
                recommendationKind: .continueWithoutSwitch
            )
        }

        if let blocked = configuredAssessment?.nonInteractiveExactMatch,
           let configured = configuredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            let suggestedRemote: String? = {
                guard let raw = configuredAssessment?.loadedCandidates.first?.id else { return nil }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }()
            let reason = blocked.interactiveRoutingDisabledReason
                ?? "这个模型属于非对话能力，会由 Supervisor 按需调用，不作为当前角色的对话模型。"
            let recommendationText: String? = {
                guard let suggestedRemote, !suggestedRemote.isEmpty else { return nil }
                return "把当前角色切到 `\(suggestedRemote)` 最稳；`\(blocked.id)` 仍会继续留给对应的 Supervisor 能力链路按需使用。"
            }()
            return AXProjectModelSelectionGuidance(
                warningText: "当前配置的 `\(configured)` 是非对话模型。\(reason)",
                recommendedModelId: suggestedRemote,
                recommendationText: recommendationText
            )
        }

        return nil
    }

    static func selectionWarningText(
        configuredModelId rawConfiguredModelId: String?,
        role: AXRole,
        ctx: AXProjectContext?,
        snapshot: ModelStateSnapshot,
        localSnapshot: ModelStateSnapshot? = nil
    ) -> String? {
        selectionGuidance(
            configuredModelId: rawConfiguredModelId,
            role: role,
            ctx: ctx,
            snapshot: snapshot,
            localSnapshot: localSnapshot
        )?.warningText
    }

    private static func usageRecords(for ctx: AXProjectContext, role: AXRole) -> [UsageRecord] {
        guard FileManager.default.fileExists(atPath: ctx.usageLogURL.path),
              let data = try? Data(contentsOf: ctx.usageLogURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        var records: [UsageRecord] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let record = usageRecord(from: obj),
                  record.role == role else {
                continue
            }
            records.append(record)
        }
        return records.sorted { $0.createdAt < $1.createdAt }
    }

    private static func usageRecord(from obj: [String: Any]) -> UsageRecord? {
        guard text(obj["type"]) == "ai_usage",
              let role = AXRole(rawValue: text(obj["role"])) else {
            return nil
        }

        return UsageRecord(
            role: role,
            createdAt: number(obj["created_at"]),
            requestedModelId: firstNonEmptyString(
                text(obj["requested_model_id"]),
                text(obj["preferred_model_id"]),
                text(obj["model_id"])
            ),
            actualModelId: firstNonEmptyString(
                text(obj["actual_model_id"]),
                text(obj["resolved_model_id"])
            ),
            executionPath: text(obj["execution_path"]),
            fallbackReasonCode: firstNonEmptyString(
                text(obj["fallback_reason_code"]),
                text(obj["failure_reason_code"])
            )
        )
    }

    private static func isRemoteFailure(_ record: UsageRecord) -> Bool {
        guard !record.requestedModelId.isEmpty else { return false }
        switch record.executionPath {
        case "hub_downgraded_to_local", "local_fallback_after_remote_error", "remote_error":
            return true
        default:
            return false
        }
    }

    private static func text(_ raw: Any?) -> String {
        (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func number(_ raw: Any?) -> Double {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        return 0
    }

    private static func firstNonEmptyString(_ values: String...) -> String {
        values.first { !$0.isEmpty } ?? ""
    }

    private static func loadHeartbeatModelsSnapshot() -> ModelStateSnapshot? {
        let url = HubPaths.modelsStateURL()
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ModelStateSnapshot.self, from: data) else {
            return nil
        }
        return decoded
    }

    private static func heartbeatConfiguredModelId(
        ctx: AXProjectContext,
        role: AXRole,
        routeMemory: AXProjectModelRouteMemory,
        snapshot: ModelStateSnapshot?
    ) -> String {
        let configuredFromProject = loadConfigIfPresent(for: ctx)?
            .modelOverride(for: role)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackRequested = routeMemory.lastRequestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = configuredFromProject.isEmpty ? fallbackRequested : configuredFromProject
        guard !candidate.isEmpty, let snapshot else { return candidate }
        return HubAIClient.normalizeConfiguredModelID(
            candidate,
            availableModels: snapshot.models
        ) ?? candidate
    }

    private static func heartbeatRememberedRemoteModelId(
        routeMemory: AXProjectModelRouteMemory,
        snapshot: ModelStateSnapshot?
    ) -> String {
        let remembered = routeMemory.lastHealthyRemoteModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remembered.isEmpty, let snapshot else { return remembered }
        return HubAIClient.normalizeConfiguredModelID(
            remembered,
            availableModels: snapshot.models
        ) ?? remembered
    }

    private static func heartbeatPreferredLocalModelLabel(
        routeMemory: AXProjectModelRouteMemory,
        snapshot: ModelStateSnapshot?,
        localSnapshot: ModelStateSnapshot?
    ) -> String {
        guard let snapshot else {
            let localModel = routeMemory.lastActualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
            return localModel.isEmpty ? "本地模型" : localModel
        }
        return resolvedPreferredLocalModelLabel(
            routeMemory: routeMemory,
            snapshot: snapshot,
            localSnapshot: localSnapshot ?? snapshot
        )
    }

    private static func loadConfigIfPresent(for ctx: AXProjectContext) -> AXProjectConfig? {
        guard FileManager.default.fileExists(atPath: ctx.configURL.path),
              let data = try? Data(contentsOf: ctx.configURL),
              var config = try? JSONDecoder().decode(AXProjectConfig.self, from: data) else {
            return nil
        }
        config.schemaVersion = AXProjectConfig.currentSchemaVersion
        return config
    }

    private static func resolveLocalLock(
        routeMemory: AXProjectModelRouteMemory?,
        configuredAssessment: HubModelAvailabilityAssessment?,
        rememberedAssessment: HubModelAvailabilityAssessment?,
        snapshot: ModelStateSnapshot,
        localSnapshot: ModelStateSnapshot?,
        now: Double = Date().timeIntervalSince1970
    ) -> (modelId: String, reasonCode: String)? {
        guard let routeMemory,
              shouldPreferLocalLock(
                configuredAssessment: configuredAssessment,
                rememberedAssessment: rememberedAssessment
              ),
              shouldForceLocalExecution(routeMemory: routeMemory, now: now) else {
            return nil
        }

        let resolvedLocalSnapshot = localSnapshot ?? snapshot
        let recentActualModelId = routeMemory.lastActualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let recentLocalModel = loadedLocalModel(
            matching: recentActualModelId,
            in: resolvedLocalSnapshot
        ) {
            return (
                recentLocalModel.id.trimmingCharacters(in: .whitespacesAndNewlines),
                "project_remote_fallback_lock_local_recent_actual"
            )
        }

        if let loadedLocalModel = firstLoadedLocalModel(in: resolvedLocalSnapshot) {
            return (
                loadedLocalModel.id.trimmingCharacters(in: .whitespacesAndNewlines),
                "project_remote_fallback_lock_local_loaded"
            )
        }

        return nil
    }

    private static func shouldForceLocalExecution(
        routeMemory: AXProjectModelRouteMemory,
        now: Double
    ) -> Bool {
        guard routeMemory.consecutiveRemoteFallbackCount >= localLockConsecutiveFallbackThreshold else {
            return false
        }
        guard isLocalExecutionPath(routeMemory.lastExecutionPath) else {
            return false
        }
        guard routeMemory.lastObservedAt > 0 else {
            return false
        }
        return (now - routeMemory.lastObservedAt) <= localLockFreshnessWindowSec
    }

    private static func shouldPreferLocalLock(
        configuredAssessment: HubModelAvailabilityAssessment?,
        rememberedAssessment: HubModelAvailabilityAssessment?
    ) -> Bool {
        if configuredAssessment?.isExactMatchLoaded == true {
            return false
        }
        if rememberedAssessment?.isExactMatchLoaded == true {
            return false
        }
        return true
    }

    private static func firstLoadedLocalModel(in snapshot: ModelStateSnapshot) -> HubModel? {
        HubModelSelectionAdvisor.loadedModels(in: snapshot).first(where: isLocalModel)
    }

    private static func loadedLocalModel(
        matching rawModelId: String,
        in snapshot: ModelStateSnapshot
    ) -> HubModel? {
        let modelId = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else { return nil }

        let normalizedModelId = HubAIClient.normalizeConfiguredModelID(
            modelId,
            availableModels: snapshot.models
        ) ?? modelId
        return HubModelSelectionAdvisor.loadedModels(in: snapshot).first { model in
            guard isLocalModel(model) else { return false }
            let candidate = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
            return candidate.caseInsensitiveCompare(normalizedModelId) == .orderedSame
        }
    }

    private static func isLocalExecutionPath(_ raw: String) -> Bool {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "hub_downgraded_to_local", "local_fallback_after_remote_error", "local_runtime":
            return true
        default:
            return false
        }
    }

    private static func isLocalModel(_ model: HubModel) -> Bool {
        let modelPath = (model.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !modelPath.isEmpty {
            return true
        }
        return model.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mlx"
    }

    private static func resolvedPreferredLocalModelLabel(
        routeMemory: AXProjectModelRouteMemory,
        snapshot: ModelStateSnapshot,
        localSnapshot: ModelStateSnapshot?
    ) -> String {
        let preferred = routeMemory.lastActualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSnapshot = localSnapshot ?? snapshot
        if let loaded = loadedLocalModel(matching: preferred, in: resolvedSnapshot) {
            let modelId = loaded.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if !modelId.isEmpty { return modelId }
        }
        if let loaded = firstLoadedLocalModel(in: resolvedSnapshot) {
            let modelId = loaded.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if !modelId.isEmpty { return modelId }
        }
        return preferred.isEmpty ? "本地模型" : preferred
    }

    private static func heartbeatActionHint(
        project: AXProjectEntry,
        ctx: AXProjectContext,
        routeMemory: AXProjectModelRouteMemory,
        requestText: String
    ) -> String {
        let latestEvent = AXModelRouteDiagnosticsStore.recentEvents(for: ctx, limit: 1).first
        let normalizedReason = normalizedFailureReasonCode(
            latestEvent?.fallbackReasonCode ?? routeMemory.lastFailureReasonCode
        )
        let executionPath = (latestEvent?.executionPath ?? routeMemory.lastExecutionPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRequest = requestText.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedModel = trimmedRequest.isEmpty ? "当前远端模型" : trimmedRequest
        let routeDiagnoseStep = heartbeatRouteDiagnoseStep(project: project)

        switch normalizedReason {
        case "downgrade_to_local", "remote_export_blocked":
            return "\(routeDiagnoseStep) 如果仍看到 `\(normalizedReason)`，再去 `XT Settings -> Diagnostics` 看最近 route event，并到 `Hub -> Models` / Hub 审计确认 `\(requestedModel)`。"
        case "model_not_found", "remote_model_not_found":
            return "\(routeDiagnoseStep) 再到 `Hub -> Models` 确认 `\(requestedModel)` 已加载；如果只是想先继续，先看这轮是否已提示会自动改试上次稳定远端。只有要强制验证指定模型时，再手动切。"
        case "response_timeout", "grpc_route_unavailable", "runtime_not_running", "request_write_failed":
            return "\(routeDiagnoseStep) 再去 `XT Settings -> Diagnostics` 看最近 route event，并检查 Hub 连接与 runtime 状态。"
        default:
            switch executionPath {
            case "hub_downgraded_to_local":
                return "\(routeDiagnoseStep) 这更像是 Hub 侧把远端请求降到了本地；继续查 `XT Settings -> Diagnostics` 和 Hub 审计。"
            case "local_fallback_after_remote_error", "remote_error":
                return "\(routeDiagnoseStep) 再去 `XT Settings -> Diagnostics` 看最近 route event，并检查 `Hub -> Models` 里 `\(requestedModel)` 的可执行状态。"
            default:
                return "\(routeDiagnoseStep) 如果仍复现，再去 `XT Settings -> Diagnostics` 看最近 route event。"
            }
        }
    }

    private static func heartbeatRememberedRemoteActionHint(
        project: AXProjectEntry,
        requestText: String,
        rememberedText: String
    ) -> String {
        "\(heartbeatRouteDiagnoseStep(project: project)) 如果你现在只是想继续，不用手动切模型；XT 会先试 `\(rememberedText)`。等 `\(requestText)` 在 Hub 恢复后，再考虑切回。"
    }

    private static func heartbeatRouteDiagnoseStep(
        project: AXProjectEntry
    ) -> String {
        "下一步：可直接点这条心跳提醒进入 `\(project.displayName)` 的路由诊断；如果你是手动排查，就进入项目后运行 `/route diagnose`。"
    }

    private static func normalizedFailureReasonCode(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func modelIDsDiffer(_ lhs: String?, _ rhs: String?) -> Bool {
        let left = (lhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let right = (rhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.caseInsensitiveCompare(right) != .orderedSame
    }
}
