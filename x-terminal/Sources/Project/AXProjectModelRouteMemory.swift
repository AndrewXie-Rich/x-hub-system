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

        if isDirectlyRunnable(assessment: configuredAssessment) {
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

        if isDirectlyRunnable(assessment: rememberedAssessment),
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
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil,
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

        if isDirectlyRunnable(assessment: configuredAssessment) {
            return nil
        }

        let requested = configuredModelId.isEmpty
            ? routeMemory.lastRequestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
            : configuredModelId
        let remembered = rememberedRemoteModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestText = requested.isEmpty ? "远端模型" : requested
        let reasonText = parenthesizedRouteReason(
            routeMemory.lastFailureReasonCode,
            language: .defaultPreference,
            recent: false
        )
        let actionHint = heartbeatActionHint(
            project: project,
            ctx: ctx,
            routeMemory: routeMemory,
            requestText: requestText,
            paidAccessSnapshot: paidAccessSnapshot
        )

        if isDirectlyRunnable(assessment: rememberedAssessment),
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
        localSnapshot: ModelStateSnapshot? = nil,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil,
        language: XTInterfaceLanguage = .defaultPreference
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

        if isDirectlyRunnable(assessment: configuredAssessment) {
            return nil
        }

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
            let reasonText = parenthesizedRouteReason(
                routeMemory.lastFailureReasonCode,
                language: language,
                recent: true
            )
            let requestedText = requestedModel.isEmpty
                ? XTL10n.text(
                    language,
                    zhHans: "当前远端模型",
                    en: "the current remote model"
                )
                : requestedModel
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
                return XTL10n.text(
                    language,
                    zhHans: "如果你现在就要继续，可改用当前已加载的可执行模型 `\(suggestedRemote)`，避免先锁本地；等 `\(requestedText)` 在 Hub 恢复后再切回来。",
                    en: "If you want to continue right now, switch to the currently loaded runnable model `\(suggestedRemote)` so XT does not lock to local first. You can switch back after `\(requestedText)` is restored in Hub."
                )
            }()
            let guidance = AXProjectModelSelectionGuidance(
                warningText: XTL10n.text(
                    language,
                    zhHans: "这个项目最近连续 \(routeMemory.consecutiveRemoteFallbackCount) 次没有稳定命中 `\(requestedText)`\(reasonText)，XT 现在会先锁到本地 `\(localModel)`。如果你要恢复远端，先去 Supervisor Control Center · AI 模型确认 `\(requestedText)` 在真实可执行列表里，再重试。",
                    en: "This project has missed `\(requestedText)` \(routeMemory.consecutiveRemoteFallbackCount) times in a row\(reasonText), so XT will lock to the local model `\(localModel)` first. If you want to recover the remote route, confirm in Supervisor Control Center · AI Models that `\(requestedText)` is in the true runnable list, then retry."
                ),
                recommendedModelId: suggestedRemote,
                recommendationText: recommendationText
            )
            return guidanceWithPaidAccessRuntimeTruth(
                guidance,
                reasonCode: routeMemory.lastFailureReasonCode,
                paidAccessSnapshot: paidAccessSnapshot,
                language: language
            )
        }

        if isDirectlyRunnable(assessment: rememberedAssessment),
           modelIDsDiffer(rememberedRemoteModelId, configuredModelId),
           let configured = configuredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty,
           let remembered = rememberedRemoteModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remembered.isEmpty {
            let guidance = AXProjectModelSelectionGuidance(
                warningText: XTL10n.text(
                    language,
                    zhHans: "当前配置的 `\(configured)` 还不能直接执行；XT 下次会先试这个项目上次稳定的远端 `\(remembered)`，避免直接掉到本地。",
                    en: "The current model `\(configured)` is not directly runnable yet. On the next attempt, XT will try this project's last stable remote model `\(remembered)` first to avoid dropping straight to local."
                ),
                recommendedModelId: remembered,
                recommendationText: XTL10n.text(
                    language,
                    zhHans: "这个项目上次稳定跑通的是 `\(remembered)`。如果你现在只是继续工作，不用手动切模型；XT 下次会先试它。只有你想把它固定成当前配置时，再手动切。",
                    en: "The last stable remote model for this project was `\(remembered)`. If you are just continuing work, you do not need to switch manually. XT will try it first on the next attempt. Only switch manually if you want to pin it as the current configuration."
                ),
                recommendationKind: .continueWithoutSwitch
            )
            return guidanceWithPaidAccessRuntimeTruth(
                guidance,
                reasonCode: routeMemory?.lastFailureReasonCode,
                paidAccessSnapshot: paidAccessSnapshot,
                language: language
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
                ?? XTL10n.text(
                    language,
                    zhHans: "这个模型属于非对话能力，会由 Supervisor 按需调用，不作为当前角色的对话模型。",
                    en: "This model is reserved for non-chat capabilities. Supervisor may still call it when needed, but it should not be used as the active chat model for this role."
                )
            let recommendationText: String? = {
                guard let suggestedRemote, !suggestedRemote.isEmpty else { return nil }
                return XTL10n.text(
                    language,
                    zhHans: "把当前角色切到 `\(suggestedRemote)` 最稳；`\(blocked.id)` 仍会继续留给对应的 Supervisor 能力链路按需使用。",
                    en: "The safest path is to switch the current role to `\(suggestedRemote)`. `\(blocked.id)` can still stay available for the corresponding Supervisor capability path when needed."
                )
            }()
            return AXProjectModelSelectionGuidance(
                warningText: XTL10n.text(
                    language,
                    zhHans: "当前配置的 `\(configured)` 是非对话模型。\(reason)",
                    en: "The current model `\(configured)` is not an interactive chat model. \(reason)"
                ),
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
        localSnapshot: ModelStateSnapshot? = nil,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String? {
        selectionGuidance(
            configuredModelId: rawConfiguredModelId,
            role: role,
            ctx: ctx,
            snapshot: snapshot,
            localSnapshot: localSnapshot,
            paidAccessSnapshot: paidAccessSnapshot,
            language: language
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
                text(obj["failure_reason_code"]),
                text(obj["deny_code"])
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
        if isDirectlyRunnable(assessment: configuredAssessment) {
            return false
        }
        if isDirectlyRunnable(assessment: rememberedAssessment) {
            return false
        }
        return true
    }

    static func isDirectlyRunnable(assessment: HubModelAvailabilityAssessment?) -> Bool {
        guard let assessment else { return false }
        guard let exact = assessment.exactMatch else { return false }
        if exact.state == .loaded {
            return true
        }
        return isRemoteInteractiveModel(exact) && exact.state == .available
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

    private static func isRemoteInteractiveModel(_ model: HubModel) -> Bool {
        guard model.isSelectableForInteractiveRouting else { return false }
        return !isLocalModel(model)
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
        requestText: String,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil
    ) -> String {
        let latestEvent = AXModelRouteDiagnosticsStore.recentEvents(for: ctx, limit: 1).first
        let normalizedReason = normalizedFailureReasonCode(
            latestEvent?.effectiveFailureReasonCode ?? routeMemory.lastFailureReasonCode
        )
        let executionPath = (latestEvent?.executionPath ?? routeMemory.lastExecutionPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRequest = requestText.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedModel = trimmedRequest.isEmpty ? "当前远端模型" : trimmedRequest
        let routeDiagnoseStep = heartbeatRouteDiagnoseStep(project: project)

        switch normalizedReason {
        case "downgrade_to_local":
            return "\(routeDiagnoseStep) 如果仍看到 `downgrade_to_local`，再看 `XT Diagnostics` 的最近 route event，并优先去 Hub 审计确认是不是执行阶段把远端降到了本地。"
        case "remote_export_blocked",
             "device_remote_export_denied",
             "policy_remote_denied",
             "budget_remote_denied",
             "remote_disabled_by_user_pref":
            return "\(routeDiagnoseStep) 再看 `XT Diagnostics` 的最近 route event，并优先查 Hub export gate、设备 / 策略 / 预算边界与 Hub 审计；不要先急着改 XT 模型。"
        case "model_not_found", "remote_model_not_found":
            return "\(routeDiagnoseStep) 再到 `Supervisor Control Center · AI 模型` 确认 `\(requestedModel)` 已进入真实可执行列表；如果只是想先继续，先看这轮是否已提示会自动改试上次稳定远端。只有要强制验证指定模型时，再手动切。"
        case "device_paid_model_disabled",
             "device_paid_model_not_allowed",
             "device_daily_token_budget_exceeded",
             "device_single_request_token_exceeded",
             "legacy_grant_flow_required":
            let base = "\(routeDiagnoseStep) 再看设备信任、模型访问策略和预算边界；如果仍卡住，再结合 `XT Diagnostics` 和 Hub 审计确认 paid 远端是否真的放行。"
            guard let paidTruth = XTRouteTruthPresentation.pairedDeviceTruthText(
                routeReasonCode: normalizedReason,
                paidAccessSnapshot: paidAccessSnapshot,
                language: .defaultPreference
            ) else {
                return base
            }
            return "\(base) 当前设备真值：\(paidTruth)。"
        case "blocked_waiting_upstream",
             "provider_not_ready",
             "response_timeout",
             "grpc_route_unavailable",
             "runtime_not_running",
             "request_write_failed",
             "remote_timeout",
             "remote_unreachable":
            return "\(routeDiagnoseStep) 再看 `XT Diagnostics` 的最近 route event，并检查 Hub 连接与 runtime 状态。"
        default:
            switch executionPath {
            case "hub_downgraded_to_local":
                return "\(routeDiagnoseStep) 这更像是 Hub 侧把远端请求降到了本地；继续查 `XT Diagnostics` 和 Hub 审计。"
            case "local_fallback_after_remote_error", "remote_error":
                return "\(routeDiagnoseStep) 再看 `XT Diagnostics` 的最近 route event，并检查 `Supervisor Control Center · AI 模型` 里 `\(requestedModel)` 的真实可执行状态。"
            default:
                return "\(routeDiagnoseStep) 如果仍复现，再看 `XT Diagnostics` 的最近 route event。"
            }
        }
    }

    private static func guidanceWithPaidAccessRuntimeTruth(
        _ guidance: AXProjectModelSelectionGuidance,
        reasonCode: String?,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot?,
        language: XTInterfaceLanguage
    ) -> AXProjectModelSelectionGuidance {
        guard let paidTruth = XTRouteTruthPresentation.pairedDeviceTruthText(
            routeReasonCode: reasonCode,
            paidAccessSnapshot: paidAccessSnapshot,
            language: language
        ) else {
            return guidance
        }

        var enriched = guidance
        enriched.warningText += XTL10n.text(
            language,
            zhHans: " 当前设备真值：\(paidTruth)。",
            en: " Current device truth: \(paidTruth)."
        )
        return enriched
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
        let normalized = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        let segments = normalized
            .split(separator: ";", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        let candidates = [
            reasonFieldValue("fallback_reason_code", in: segments),
            reasonFieldValue("reason_code", in: segments),
            reasonFieldValue("reason", in: segments),
            reasonFieldValue("resolution_state", in: segments).flatMap { isGenericReasonToken($0) ? nil : $0 },
            reasonFieldValue("deny_code", in: segments).flatMap { isGenericReasonToken($0) ? nil : $0 },
            segments.first(where: { !$0.contains("=") && !isGenericReasonToken($0) }),
            reasonFieldValue("resolution_state", in: segments),
            reasonFieldValue("deny_code", in: segments),
            segments.first(where: { !$0.contains("=") }),
            normalized
        ]

        for candidate in candidates {
            let token = normalizedReasonSegment(candidate ?? "")
            if !token.isEmpty {
                return token
            }
        }
        return ""
    }

    private static func parenthesizedRouteReason(
        _ raw: String?,
        language: XTInterfaceLanguage,
        recent: Bool
    ) -> String {
        guard let reason = humanizedFailureReason(raw, language: language),
              !reason.isEmpty else {
            return ""
        }
        return XTL10n.text(
            language,
            zhHans: recent ? "（最近原因：\(reason)）" : "（原因：\(reason)）",
            en: recent ? " (recent reason: \(reason))" : " (reason: \(reason))"
        )
    }

    private static func humanizedFailureReason(
        _ raw: String?,
        language: XTInterfaceLanguage
    ) -> String? {
        let normalized = normalizedFailureReasonCode(raw)
        guard !normalized.isEmpty else { return nil }
        return XTRouteTruthPresentation.routeReasonDisplayText(raw, language: language)
            ?? XTRouteTruthPresentation.denyCodeText(raw, language: language)
            ?? normalized
    }

    private static func reasonFieldValue(_ key: String, in segments: [String]) -> String? {
        let prefix = "\(key)="
        guard let segment = segments.first(where: {
            $0.lowercased().hasPrefix(prefix.lowercased())
        }) else {
            return nil
        }
        let value = String(segment.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalizedReasonSegment(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func isGenericReasonToken(_ raw: String) -> Bool {
        switch normalizedReasonSegment(raw) {
        case "grant_required", "grant_pending", "permission_denied", "forbidden":
            return true
        default:
            return false
        }
    }

    private static func modelIDsDiffer(_ lhs: String?, _ rhs: String?) -> Bool {
        let left = (lhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let right = (rhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.caseInsensitiveCompare(right) != .orderedSame
    }
}
