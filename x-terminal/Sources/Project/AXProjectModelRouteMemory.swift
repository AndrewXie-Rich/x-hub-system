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
        for project: AXProjectEntry
    ) -> String? {
        let rawRoot = project.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawRoot.isEmpty else { return nil }
        let ctx = AXProjectContext(root: URL(fileURLWithPath: rawRoot, isDirectory: true))
        guard let routeMemory = load(for: ctx, role: .coder),
              routeMemory.shouldSuggestLocalModeNotice else { return nil }

        let requested = routeMemory.lastRequestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let localModel = routeMemory.lastActualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = routeMemory.lastFailureReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestText = requested.isEmpty ? "远端模型" : requested
        let reasonText = reason.isEmpty ? "" : "（原因：\(reason)）"
        let localText = localModel.isEmpty ? "本地模型" : "`\(localModel)`"
        if shouldForceLocalExecution(routeMemory: routeMemory, now: Date().timeIntervalSince1970) {
            return "模型路由：\(project.displayName) 已切到本地模式；`\(requestText)` 最近连续 \(routeMemory.consecutiveRemoteFallbackCount) 次未稳定命中\(reasonText)，当前先锁定 \(localText) 执行。建议检查 Hub 配置后再恢复远端。"
        }
        return "模型路由：\(project.displayName) 最近已连续 \(routeMemory.consecutiveRemoteFallbackCount) 次切到本地；`\(requestText)` 未稳定命中\(reasonText)，建议检查 Hub 配置后再重试。"
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

    private static func modelIDsDiffer(_ lhs: String?, _ rhs: String?) -> Bool {
        let left = (lhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let right = (rhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.caseInsensitiveCompare(right) != .orderedSame
    }
}
