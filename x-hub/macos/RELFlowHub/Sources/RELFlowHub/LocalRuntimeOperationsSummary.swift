import Foundation
import RELFlowHubCore

struct LocalRuntimeOperationsSummary: Equatable {
    struct ProviderRow: Identifiable, Equatable {
        var providerID: String
        var stateLabel: String
        var queueSummary: String
        var detailSummary: String

        var id: String { providerID }
    }

    struct InstanceRow: Identifiable, Equatable {
        var providerID: String
        var modelID: String
        var modelName: String
        var instanceKey: String
        var shortInstanceKey: String
        var taskSummary: String
        var loadSummary: String
        var detailSummary: String
        var isCurrentTarget: Bool
        var currentTargetSummary: String
        var canUnload: Bool
        var canEvict: Bool

        var id: String { instanceKey }
    }

    var runtimeSummary: String
    var queueSummary: String
    var loadedSummary: String
    var monitorStale: Bool
    var providerRows: [ProviderRow]
    var instanceRows: [InstanceRow]
}

enum LocalRuntimeOperationsSummaryBuilder {
    static func build(
        status: AIRuntimeStatus?,
        models: [HubModel],
        currentTargetsByModelID: [String: LocalModelRuntimeRequestContext],
        ttl: Double = 3.0,
        now: Date = Date()
    ) -> LocalRuntimeOperationsSummary {
        let monitor = status?.monitorSnapshot
        let monitorStale = !(status?.isAlive(ttl: ttl) ?? false)
        let modelByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        let providerRows = buildProviderRows(status: status, monitor: monitor, monitorStale: monitorStale)
        let instanceRows = buildInstanceRows(
            status: status,
            monitor: monitor,
            modelByID: modelByID,
            currentTargetsByModelID: currentTargetsByModelID,
            now: now
        )
        let runtimeSummary = buildRuntimeSummary(status: status, providerRows: providerRows, monitorStale: monitorStale)
        let queueSummary = buildQueueSummary(monitor: monitor)
        let loadedSummary = instanceRows.isEmpty
            ? HubUIStrings.Models.OperationsSummary.noLoadedInstances
            : HubUIStrings.Models.OperationsSummary.loadedInstances(instanceRows.count)
        return LocalRuntimeOperationsSummary(
            runtimeSummary: runtimeSummary,
            queueSummary: queueSummary,
            loadedSummary: loadedSummary,
            monitorStale: monitorStale,
            providerRows: providerRows,
            instanceRows: instanceRows
        )
    }

    private static func buildProviderRows(
        status: AIRuntimeStatus?,
        monitor: AIRuntimeMonitorSnapshot?,
        monitorStale: Bool
    ) -> [LocalRuntimeOperationsSummary.ProviderRow] {
        if let monitor {
            return monitor.providers.map { provider in
                LocalRuntimeOperationsSummary.ProviderRow(
                    providerID: provider.provider,
                    stateLabel: providerStateLabel(provider: provider, monitorStale: monitorStale),
                    queueSummary: providerQueueSummary(provider),
                    detailSummary: providerDetailSummary(provider)
                )
            }
        }

        let statuses = status?.providers.values.sorted { $0.provider < $1.provider } ?? []
        return statuses.map { provider in
            LocalRuntimeOperationsSummary.ProviderRow(
                providerID: provider.provider,
                stateLabel: provider.ok ? (monitorStale ? "stale" : "ready") : "down",
                queueSummary: HubUIStrings.Models.OperationsSummary.queueUnavailable,
                detailSummary: HubUIStrings.Models.OperationsSummary.providerLoadedTasks(
                    loadedCount: provider.loadedInstances.count,
                    taskKinds: taskKindsText(provider.availableTaskKinds)
                )
            )
        }
    }

    private static func buildInstanceRows(
        status: AIRuntimeStatus?,
        monitor: AIRuntimeMonitorSnapshot?,
        modelByID: [String: HubModel],
        currentTargetsByModelID: [String: LocalModelRuntimeRequestContext],
        now: Date
    ) -> [LocalRuntimeOperationsSummary.InstanceRow] {
        let loadedInstances = flattenedLoadedInstances(status: status, monitor: monitor)
        return loadedInstances.map { instance in
            let model = modelByID[instance.modelId]
            let providerID = model.map(LocalModelRuntimeActionPlanner.providerID(for:)) ?? providerIDFromInstanceKey(instance.instanceKey)
            let providerStatus = status?.providerStatus(providerID)
            let currentTarget = currentTargetsByModelID[instance.modelId]
            let isCurrentTarget = currentTarget.map { matches(instance: instance, requestContext: $0) } ?? false
            return LocalRuntimeOperationsSummary.InstanceRow(
                providerID: providerID,
                modelID: instance.modelId,
                modelName: model?.name ?? instance.modelId,
                instanceKey: instance.instanceKey,
                shortInstanceKey: shortInstanceKey(instance.instanceKey),
                taskSummary: taskKindsText(instance.taskKinds),
                loadSummary: loadSummary(instance),
                detailSummary: detailSummary(instance, providerID: providerID, now: now),
                isCurrentTarget: isCurrentTarget,
                currentTargetSummary: isCurrentTarget ? (currentTarget?.shortSourceLabel ?? HubUIStrings.Models.OperationsSummary.currentTarget) : "",
                canUnload: LocalRuntimeProviderPolicy.supportsUnload(
                    providerID: providerID,
                    taskKinds: instance.taskKinds,
                    providerStatus: providerStatus,
                    residencyScope: instance.residencyScope,
                    residency: instance.residency
                ),
                canEvict: providerStatus?.supportsLifecycleAction(.evictLocalInstance) ?? false
            )
        }
    }

    private static func buildRuntimeSummary(
        status: AIRuntimeStatus?,
        providerRows: [LocalRuntimeOperationsSummary.ProviderRow],
        monitorStale: Bool
    ) -> String {
        guard let status else {
            return HubUIStrings.Models.OperationsSummary.runtimeUnavailable
        }
        if monitorStale {
            return HubUIStrings.Models.OperationsSummary.runtimeHeartbeatExpired
        }
        let readyProviders = status.readyProviderIDs()
        if !readyProviders.isEmpty {
            return HubUIStrings.Models.OperationsSummary.runtimeReady(readyProviders.joined(separator: ", "))
        }
        if !providerRows.isEmpty {
            return HubUIStrings.Models.OperationsSummary.runtimeOnlineProviderUnavailable
        }
        return HubUIStrings.Models.OperationsSummary.runtimeUnavailable
    }

    private static func buildQueueSummary(monitor: AIRuntimeMonitorSnapshot?) -> String {
        guard let monitor else {
            return HubUIStrings.Models.OperationsSummary.queueUnavailable
        }
        return HubUIStrings.Models.OperationsSummary.queueSummary(
            active: monitor.queue.activeTaskCount,
            queued: monitor.queue.queuedTaskCount,
            waitMs: monitor.queue.maxOldestWaitMs
        )
    }

    private static func providerStateLabel(
        provider: AIRuntimeMonitorProvider,
        monitorStale: Bool
    ) -> String {
        if monitorStale {
            return "stale"
        }
        if !provider.ok {
            return "down"
        }
        if provider.fallbackUsed {
            return "fallback"
        }
        if provider.activeTaskCount > 0 || provider.queuedTaskCount > 0 {
            return "busy"
        }
        return "ready"
    }

    private static func providerQueueSummary(_ provider: AIRuntimeMonitorProvider) -> String {
        HubUIStrings.Models.OperationsSummary.providerQueueSummary(
            active: provider.activeTaskCount,
            queued: provider.queuedTaskCount
        )
    }

    private static func providerDetailSummary(_ provider: AIRuntimeMonitorProvider) -> String {
        HubUIStrings.Models.OperationsSummary.providerDetailSummary(
            loadedCount: provider.loadedInstanceCount,
            fallbackTasks: taskKindsText(provider.fallbackTaskKinds)
        )
    }

    private static func flattenedLoadedInstances(
        status: AIRuntimeStatus?,
        monitor: AIRuntimeMonitorSnapshot?
    ) -> [AIRuntimeLoadedInstance] {
        if let monitor, !monitor.loadedInstances.isEmpty {
            return monitor.loadedInstances.sorted(by: isNewerLoadedInstance)
        }
        let rows = status?.providers.values.flatMap(\.loadedInstances) ?? []
        var deduped: [AIRuntimeLoadedInstance] = []
        var seen = Set<String>()
        for row in rows.sorted(by: isNewerLoadedInstance) {
            guard seen.insert(row.instanceKey).inserted else { continue }
            deduped.append(row)
        }
        return deduped
    }

    private static func isNewerLoadedInstance(_ lhs: AIRuntimeLoadedInstance, _ rhs: AIRuntimeLoadedInstance) -> Bool {
        if lhs.lastUsedAt == rhs.lastUsedAt {
            if lhs.loadedAt == rhs.loadedAt {
                return lhs.instanceKey < rhs.instanceKey
            }
            return lhs.loadedAt > rhs.loadedAt
        }
        return lhs.lastUsedAt > rhs.lastUsedAt
    }

    private static func taskKindsText(_ taskKinds: [String]) -> String {
        let normalized = LocalModelCapabilityDefaults.normalizedStringList(taskKinds, fallback: [])
        guard !normalized.isEmpty else { return HubUIStrings.Models.OperationsSummary.unknown }
        return normalized.map { LocalTaskRoutingCatalog.shortTitle(for: $0) }.joined(separator: ", ")
    }

    private static func loadSummary(_ instance: AIRuntimeLoadedInstance) -> String {
        var parts: [String] = []
        if instance.currentContextLength > 0 {
            parts.append("ctx \(instance.currentContextLength)")
        }
        if instance.maxContextLength > instance.currentContextLength,
           instance.maxContextLength > 0 {
            parts.append("max \(instance.maxContextLength)")
        }
        if let ttl = instance.ttl ?? instance.loadConfig?.ttl {
            parts.append("ttl \(ttl)s")
        }
        if let parallel = instance.loadConfig?.parallel {
            parts.append("par \(parallel)")
        }
        if let imageMaxDimension = instance.loadConfig?.vision?.imageMaxDimension {
            parts.append("img \(imageMaxDimension)")
        }
        let hash = shortHash(instance.loadConfigHash)
        if !hash.isEmpty {
            parts.append(HubUIStrings.Models.OperationsSummary.loadConfig(hash))
        }
        return parts.isEmpty ? HubUIStrings.Models.OperationsSummary.defaultLoadConfig : HubUIStrings.Formatting.middleDotSeparated(parts)
    }

    private static func detailSummary(
        _ instance: AIRuntimeLoadedInstance,
        providerID: String,
        now: Date
    ) -> String {
        var parts: [String] = [providerID]
        if !instance.residency.isEmpty {
            parts.append(instance.residency)
        }
        if !instance.deviceBackend.isEmpty {
            parts.append(instance.deviceBackend)
        }
        if let identifier = instance.loadConfig?.identifier,
           !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(HubUIStrings.Models.OperationsSummary.detailConfig(identifier))
        }
        let age = relativeAgeText(since: instance.lastUsedAt, now: now)
        if !age.isEmpty {
            parts.append(age)
        }
        return HubUIStrings.Formatting.middleDotSeparated(parts)
    }

    private static func relativeAgeText(since seconds: Double, now: Date) -> String {
        guard seconds > 0 else { return "" }
        let delta = max(0, Int(now.timeIntervalSince1970 - seconds))
        if delta < 5 {
            return HubUIStrings.Models.OperationsSummary.justNow
        }
        if delta < 60 {
            return HubUIStrings.Models.OperationsSummary.secondsAgo(delta)
        }
        if delta < 3600 {
            return HubUIStrings.Models.OperationsSummary.minutesAgo(delta / 60)
        }
        if delta < 86_400 {
            return HubUIStrings.Models.OperationsSummary.hoursAgo(delta / 3600)
        }
        return HubUIStrings.Models.OperationsSummary.daysAgo(delta / 86_400)
    }

    private static func providerIDFromInstanceKey(_ instanceKey: String) -> String {
        let token = instanceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = token.split(separator: ":").first else {
            return ""
        }
        return String(first)
    }

    private static func shortInstanceKey(_ instanceKey: String) -> String {
        let token = instanceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "" }
        let suffix = String(token.split(separator: ":").last ?? Substring(token))
        return String(suffix.prefix(8))
    }

    private static func shortHash(_ value: String) -> String {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "" }
        return String(token.prefix(8))
    }

    private static func matches(
        instance: AIRuntimeLoadedInstance,
        requestContext: LocalModelRuntimeRequestContext
    ) -> Bool {
        let wantedInstance = requestContext.instanceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !wantedInstance.isEmpty {
            return wantedInstance == instance.instanceKey
        }
        let wantedHash = requestContext.preferredBenchHash.trimmingCharacters(in: .whitespacesAndNewlines)
        if !wantedHash.isEmpty,
           !instance.loadConfigHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return wantedHash == instance.loadConfigHash
        }
        if requestContext.effectiveContextLength > 0,
           instance.currentContextLength > 0 {
            return requestContext.effectiveContextLength == instance.currentContextLength
        }
        return false
    }
}
