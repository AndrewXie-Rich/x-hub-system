import Foundation
import CryptoKit
import RELFlowHubCore

extension HubDiagnosticsBundleExporter {
    static func localRuntimeBenchModelBlock(
        model: HubModel,
        requestContext: LocalModelRuntimeRequestContext,
        benchResult: ModelBenchResult?,
        explanation: LocalModelBenchMonitorExplanation?,
        capabilityCard: LocalModelBenchCapabilityCard
    ) -> String {
        var lines: [String] = []
        lines.append("model_id=\(model.id)")
        lines.append("model_name=\((model.name.isEmpty ? model.id : model.name))")
        lines.append("provider=\(LocalModelRuntimeActionPlanner.providerID(for: model))")
        lines.append("target=\(requestContext.uiSummary)")
        lines.append("target_detail=\(requestContext.technicalSummary)")
        lines.append("target_load=\(requestContext.technicalLoadProfileSummary.isEmpty ? "none" : requestContext.technicalLoadProfileSummary)")
        lines.append("target_profile=\(shortHash(requestContext.preferredBenchHash))")
        if let benchResult {
            lines.append(
                "bench_task=\(benchResult.taskKind.isEmpty ? "unknown" : benchResult.taskKind) verdict=\(benchResult.verdict.isEmpty ? (benchResult.ok ? "ready" : "failed") : benchResult.verdict) reason=\(benchResult.reasonCode.isEmpty ? "none" : benchResult.reasonCode) fallback=\(benchResult.fallbackMode.isEmpty ? "none" : benchResult.fallbackMode)"
            )
            lines.append("bench_load=\(benchLoadSummary(benchResult))")
            lines.append("bench_matches_target=\(requestContext.matchesBenchResult(benchResult) ? "1" : "0")")
        } else {
            lines.append("bench_task=none verdict=none reason=none fallback=none")
            lines.append("bench_load=none")
            lines.append("bench_matches_target=0")
        }
        if let explanation {
            lines.append("bench_explanation=\(explanation.headline)")
            if !explanation.detailLines.isEmpty {
                lines.append("bench_explanation_details:\n" + explanation.detailLines.joined(separator: "\n"))
            }
        } else {
            lines.append("bench_explanation=\(exportStrings.none)")
        }
        lines.append("capability_headline=\(capabilityCard.headline)")
        lines.append("capability_tone=\(capabilityCard.tone.rawValue)")
        lines.append("capability_summary=\(capabilityCard.summary)")
        if capabilityCard.badges.isEmpty {
            lines.append("capability_badges=\(exportStrings.none)")
        } else {
            lines.append(
                "capability_badges=" + capabilityCard.badges.map { badge in
                    "\(badge.title){\(badge.tone.rawValue)}"
                }.joined(separator: ", ")
            )
        }
        if capabilityCard.insights.isEmpty {
            lines.append("capability_insights=\(exportStrings.none)")
        } else {
            lines.append(
                "capability_insights:\n" + capabilityCard.insights.map { insight in
                    "\(insight.label)=\(insight.value)"
                }.joined(separator: "\n")
            )
        }
        if capabilityCard.notes.isEmpty {
            lines.append("capability_notes=\(exportStrings.none)")
        } else {
            lines.append("capability_notes:\n" + capabilityCard.notes.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    static func localRuntimeOperationsSummary(
        status: AIRuntimeStatus?,
        models: [HubModel],
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot,
        targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot
    ) -> LocalRuntimeOperationsSummary {
        let localModels = localRuntimeModels(models)
        let currentTargetsByModelID = localRuntimeCurrentTargetsByModelID(
            status: status,
            models: localModels,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreferencesSnapshot: targetPreferencesSnapshot
        )
        return LocalRuntimeOperationsSummaryBuilder.build(
            status: status,
            models: localModels,
            currentTargetsByModelID: currentTargetsByModelID
        )
    }

    static func localRuntimeOperationsExport(
        summary: LocalRuntimeOperationsSummary,
        status: AIRuntimeStatus?,
        models: [HubModel],
        currentTargetsByModelID: [String: LocalModelRuntimeRequestContext]
    ) -> LocalRuntimeOperationsExport {
        let modelByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        let currentTargetRows = models.map { model in
            currentTargetExport(
                model: model,
                requestContext: currentTargetsByModelID[model.id]
            )
        }
        let targetRowsByModelID = Dictionary(
            uniqueKeysWithValues: currentTargetRows.map { ($0.modelID, $0) }
        )
        let summaryRowsByInstanceKey = Dictionary(
            uniqueKeysWithValues: summary.instanceRows.map { ($0.instanceKey, $0) }
        )
        let loadedInstanceRows = localRuntimeLoadedInstances(status: status).map { instance in
            let summaryRow = summaryRowsByInstanceKey[instance.instanceKey]
            let model = modelByID[instance.modelId]
            let modelName = displayModelName(modelID: instance.modelId, model: model)
            let providerID = summaryRow?.providerID ?? localRuntimeProviderID(from: instance.instanceKey)
            return LocalRuntimeOperationsExport.LoadedInstanceRow(
                providerID: providerID,
                modelID: instance.modelId,
                modelName: modelName,
                instanceKey: instance.instanceKey,
                shortInstanceKey: summaryRow?.shortInstanceKey ?? localRuntimeShortInstanceKey(instance.instanceKey),
                taskSummary: summaryRow?.taskSummary ?? localRuntimeTaskSummary(instance.taskKinds),
                loadSummary: summaryRow?.loadSummary ?? localRuntimeLoadSummary(instance),
                detailSummary: summaryRow?.detailSummary ?? providerID,
                isCurrentTarget: summaryRow?.isCurrentTarget ?? false,
                currentTargetSummary: summaryRow?.currentTargetSummary ?? "",
                canUnload: summaryRow?.canUnload ?? LocalRuntimeProviderPolicy.supportsUnload(
                    providerID: providerID,
                    taskKinds: instance.taskKinds,
                    providerStatus: status?.providerStatus(providerID),
                    residencyScope: instance.residencyScope,
                    residency: instance.residency
                ),
                canEvict: summaryRow?.canEvict ?? false,
                loadedInstance: instance,
                currentTarget: targetRowsByModelID[instance.modelId]
            )
        }
        return LocalRuntimeOperationsExport(
            runtimeSummary: summary.runtimeSummary,
            queueSummary: summary.queueSummary,
            loadedSummary: summary.loadedSummary,
            monitorStale: summary.monitorStale,
            providers: summary.providerRows.map {
                LocalRuntimeOperationsExport.ProviderRow(
                    providerID: $0.providerID,
                    stateLabel: $0.stateLabel,
                    queueSummary: $0.queueSummary,
                    detailSummary: $0.detailSummary
                )
            },
            currentTargets: currentTargetRows,
            loadedInstances: loadedInstanceRows
        )
    }

    private static func currentTargetExport(
        model: HubModel,
        requestContext: LocalModelRuntimeRequestContext?
    ) -> LocalRuntimeOperationsExport.CurrentTargetRow {
        let resolvedContext = requestContext ?? LocalModelRuntimeRequestContext(
            providerID: LocalModelRuntimeActionPlanner.providerID(for: model),
            modelID: model.id,
            deviceID: "",
            instanceKey: "",
            loadProfileHash: "",
            predictedLoadProfileHash: "",
            effectiveContextLength: 0,
            loadProfileOverride: nil,
            effectiveLoadProfile: nil,
            source: "unknown"
        )
        return LocalRuntimeOperationsExport.CurrentTargetRow(
            modelID: model.id,
            modelName: displayModelName(modelID: model.id, model: model),
            providerID: resolvedContext.providerID,
            target: resolvedContext,
            uiSummary: resolvedContext.uiSummary,
            technicalSummary: resolvedContext.technicalSummary,
            loadSummary: resolvedContext.technicalLoadProfileSummary,
            preferredBenchHash: resolvedContext.preferredBenchHash
        )
    }

    static func localRuntimeCurrentTargetsByModelID(
        status: AIRuntimeStatus?,
        models: [HubModel],
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot,
        targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot
    ) -> [String: LocalModelRuntimeRequestContext] {
        Dictionary(
            uniqueKeysWithValues: models.map { model in
                let targetPreference = targetPreferencesSnapshot.preferences.first(where: { $0.modelId == model.id })
                let requestContext = LocalModelRuntimeRequestContextResolver.resolve(
                    model: model,
                    runtimeStatus: status,
                    pairedProfilesSnapshot: pairedProfilesSnapshot,
                    targetPreference: targetPreference
                )
                return (model.id, requestContext)
            }
        )
    }

    static func localRuntimeModels(_ models: [HubModel]) -> [HubModel] {
        models
            .filter { !LocalModelRuntimeActionPlanner.isRemoteModel($0) }
            .sorted {
                let lhsName = displayModelName(modelID: $0.id, model: $0)
                let rhsName = displayModelName(modelID: $1.id, model: $1)
                let nameOrder = lhsName.localizedCaseInsensitiveCompare(rhsName)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
            }
    }

    private static func localRuntimeLoadedInstances(status: AIRuntimeStatus?) -> [AIRuntimeLoadedInstance] {
        if let monitor = status?.monitorSnapshot, !monitor.loadedInstances.isEmpty {
            return monitor.loadedInstances.sorted(by: localRuntimeIsNewerLoadedInstance)
        }
        let rows = status?.providers.values.flatMap(\.loadedInstances) ?? []
        var deduped: [AIRuntimeLoadedInstance] = []
        var seen = Set<String>()
        for row in rows.sorted(by: localRuntimeIsNewerLoadedInstance) {
            guard seen.insert(row.instanceKey).inserted else { continue }
            deduped.append(row)
        }
        return deduped
    }

    private static func localRuntimeIsNewerLoadedInstance(
        _ lhs: AIRuntimeLoadedInstance,
        _ rhs: AIRuntimeLoadedInstance
    ) -> Bool {
        if lhs.lastUsedAt == rhs.lastUsedAt {
            if lhs.loadedAt == rhs.loadedAt {
                return lhs.instanceKey < rhs.instanceKey
            }
            return lhs.loadedAt > rhs.loadedAt
        }
        return lhs.lastUsedAt > rhs.lastUsedAt
    }

    private static func localRuntimeProviderID(from instanceKey: String) -> String {
        let token = instanceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prefix = token.split(separator: ":").first, !prefix.isEmpty else {
            return ""
        }
        return String(prefix)
    }

    private static func localRuntimeShortInstanceKey(_ instanceKey: String) -> String {
        let token = instanceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "" }
        let suffix = String(token.split(separator: ":").last ?? Substring(token))
        return String(suffix.prefix(8))
    }

    private static func localRuntimeTaskSummary(_ taskKinds: [String]) -> String {
        let normalized = LocalModelCapabilityDefaults.normalizedStringList(taskKinds, fallback: [])
        guard !normalized.isEmpty else { return exportStrings.unknown }
        return normalized.map { LocalTaskRoutingCatalog.shortTitle(for: $0) }.joined(separator: ", ")
    }

    private static func localRuntimeLoadSummary(_ instance: AIRuntimeLoadedInstance) -> String {
        var parts: [String] = []
        if instance.currentContextLength > 0 {
            parts.append(exportStrings.runtimeLoadContext(instance.currentContextLength))
        }
        if instance.maxContextLength > instance.currentContextLength,
           instance.maxContextLength > 0 {
            parts.append(exportStrings.runtimeLoadMaxContext(instance.maxContextLength))
        }
        if let ttl = instance.ttl ?? instance.loadConfig?.ttl {
            parts.append(exportStrings.runtimeLoadTTL(ttl))
        }
        if let parallel = instance.loadConfig?.parallel {
            parts.append(exportStrings.runtimeLoadParallel(parallel))
        }
        if let imageMaxDimension = instance.loadConfig?.vision?.imageMaxDimension {
            parts.append(exportStrings.runtimeLoadImageMaxDimension(imageMaxDimension))
        }
        let hash = shortHash(instance.loadConfigHash)
        if hash != "none" {
            parts.append(exportStrings.runtimeLoadConfigHash(hash))
        }
        return exportStrings.runtimeLoadSummary(parts)
    }

    private static func displayModelName(modelID: String, model: HubModel?) -> String {
        let resolved = model?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return resolved.isEmpty ? modelID : resolved
    }

    static func runtimeOpsSummaryBlock(_ summary: LocalRuntimeOperationsSummary) -> String {
        var lines: [String] = []
        lines.append("runtime_summary=\(summary.runtimeSummary)")
        lines.append("queue_summary=\(summary.queueSummary)")
        lines.append("loaded_summary=\(summary.loadedSummary)")
        lines.append("monitor_stale=\(summary.monitorStale ? "1" : "0")")
        lines.append("providers:")
        if summary.providerRows.isEmpty {
            lines.append(exportStrings.none)
        } else {
            lines.append(contentsOf: summary.providerRows.map { row in
                "provider=\(row.providerID) state=\(row.stateLabel) queue=\(row.queueSummary) detail=\(row.detailSummary)"
            })
        }
        return lines.joined(separator: "\n")
    }

    static func runtimeOpsInstanceLine(_ row: LocalRuntimeOperationsSummary.InstanceRow) -> String {
        var parts: [String] = [
            "model_id=\(row.modelID)",
            "model_name=\(row.modelName)",
            "provider=\(row.providerID)",
            "instance_ref=\(row.shortInstanceKey.isEmpty ? row.instanceKey : row.shortInstanceKey)",
            "tasks=\(row.taskSummary)",
            "load=\(row.loadSummary)",
            "detail=\(row.detailSummary)",
        ]
        if row.isCurrentTarget, !row.currentTargetSummary.isEmpty {
            parts.append("current_target=\(row.currentTargetSummary)")
        }
        return parts.joined(separator: " ")
    }

    static func localRuntimeConsoleCurrentTargetLine(
        _ row: LocalRuntimeOperationsExport.CurrentTargetRow,
        providerDiagnosis: AIRuntimeProviderDiagnosis?
    ) -> String {
        var parts: [String] = [
            "model_id=\(row.modelID)",
            "model_name=\(row.modelName)",
            "provider=\(row.providerID)",
            "route=\(localRuntimeConsoleTargetRoute(row.target))",
            "target=\(row.uiSummary.isEmpty ? exportStrings.none : row.uiSummary)",
            "detail=\(row.technicalSummary.isEmpty ? exportStrings.none : row.technicalSummary)",
            "load=\(row.loadSummary.isEmpty ? "none" : row.loadSummary)",
            "profile=\(shortHash(row.preferredBenchHash))",
            "provider_state=\(providerDiagnosis?.state.rawValue ?? "unknown")",
            "fallback=\(providerDiagnosis?.fallbackUsed == true ? "1" : "0")",
        ]
        if let hint = localRuntimeConsoleTargetHint(
            requestContext: row.target,
            providerDiagnosis: providerDiagnosis
        ) {
            parts.append("hint=\(hint)")
        }
        return parts.joined(separator: " ")
    }

    static func localRuntimeConsoleActiveTaskLine(
        _ task: AIRuntimeMonitorActiveTask,
        model: HubModel?,
        providerDiagnosis: AIRuntimeProviderDiagnosis?,
        queuedTaskCount: Int
    ) -> String {
        let modelName = displayModelName(modelID: task.modelId, model: model)
        let shortInstanceKey = localRuntimeShortInstanceKey(task.instanceKey)
        var parts: [String] = [
            "provider=\(task.provider)",
            "task_kind=\(task.taskKind.isEmpty ? "unknown" : task.taskKind)",
            "model_id=\(task.modelId.isEmpty ? "(none)" : task.modelId)",
            "model_name=\(modelName)",
            "request_id=\(task.requestId.isEmpty ? "(none)" : task.requestId)",
            "device_id=\(task.deviceId.isEmpty ? "(none)" : task.deviceId)",
            "lease_id=\(task.leaseId.isEmpty ? "(none)" : task.leaseId)",
            "instance_ref=\(shortInstanceKey.isEmpty ? "(none)" : shortInstanceKey)",
            "age_sec=\(localRuntimeTaskAgeSeconds(task.startedAt))",
            "summary=\(localRuntimeConsoleActiveTaskSummary(task, providerDiagnosis: providerDiagnosis, queuedTaskCount: queuedTaskCount))",
        ]
        if !task.loadConfigHash.isEmpty {
            parts.append("profile=\(shortHash(task.loadConfigHash))")
        }
        if let hint = localRuntimeConsoleActiveTaskHint(
            task,
            providerDiagnosis: providerDiagnosis,
            queuedTaskCount: queuedTaskCount
        ) {
            parts.append("hint=\(hint)")
        }
        return parts.joined(separator: " ")
    }

    private static func localRuntimeConsoleTargetRoute(_ requestContext: LocalModelRuntimeRequestContext) -> String {
        let source = requestContext.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if source.hasPrefix("selected_") || !requestContext.instanceKey.isEmpty {
            return "pinned"
        }
        return "automatic"
    }

    private static func localRuntimeConsoleTargetHint(
        requestContext: LocalModelRuntimeRequestContext,
        providerDiagnosis: AIRuntimeProviderDiagnosis?
    ) -> String? {
        if let providerDiagnosis {
            switch providerDiagnosis.state {
            case .down:
                return HubUIStrings.Models.Runtime.Target.providerDownHint
            case .stale:
                return HubUIStrings.Models.Runtime.Target.staleHint
            case .ready:
                break
            }
            if providerDiagnosis.fallbackUsed {
                return HubUIStrings.Models.Runtime.Target.fallbackHint
            }
        } else {
            return HubUIStrings.Models.Runtime.Target.noProviderPathHint
        }

        let source = requestContext.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if source == "model_default" {
            return HubUIStrings.Models.Runtime.Target.defaultRouteHint
        }
        if source == "loaded_instance_latest" {
            return HubUIStrings.Models.Runtime.Target.latestInstanceHint
        }
        return nil
    }

    private static func localRuntimeConsoleActiveTaskSummary(
        _ task: AIRuntimeMonitorActiveTask,
        providerDiagnosis: AIRuntimeProviderDiagnosis?,
        queuedTaskCount: Int
    ) -> String {
        var parts: [String] = [HubUIStrings.Models.Runtime.Task.summary(provider: task.provider.uppercased())]
        if !task.deviceId.isEmpty {
            parts.append(HubUIStrings.Models.Runtime.Task.deviceOnline)
        }
        if !task.instanceKey.isEmpty {
            parts.append(HubUIStrings.Models.Runtime.Task.residentInstance)
        }
        let ageSeconds = localRuntimeTaskAgeSeconds(task.startedAt)
        if ageSeconds >= 900 {
            parts.append(HubUIStrings.Models.Runtime.Task.runningLong)
        } else if ageSeconds >= 180 {
            parts.append(HubUIStrings.Models.Runtime.Task.watchSuggested)
        }
        if queuedTaskCount > 0 {
            parts.append(HubUIStrings.Models.Runtime.Task.queuedBehind(queuedTaskCount))
        }
        if providerDiagnosis?.fallbackUsed == true {
            parts.append(HubUIStrings.Models.Runtime.Task.fallbackUsed)
        }
        return exportStrings.activeTaskSummary(parts)
    }

    private static func localRuntimeConsoleActiveTaskHint(
        _ task: AIRuntimeMonitorActiveTask,
        providerDiagnosis: AIRuntimeProviderDiagnosis?,
        queuedTaskCount: Int
    ) -> String? {
        if providerDiagnosis?.state == .down {
            return HubUIStrings.Models.Runtime.Task.providerDownHint
        }
        if providerDiagnosis?.state == .stale {
            return HubUIStrings.Models.Runtime.Task.staleHint
        }
        let ageSeconds = localRuntimeTaskAgeSeconds(task.startedAt)
        if ageSeconds >= 900 {
            return HubUIStrings.Models.Runtime.Task.longRunningHint
        }
        if queuedTaskCount > 0 {
            return HubUIStrings.Models.Runtime.Task.queuedHint(queuedTaskCount)
        }
        if providerDiagnosis?.fallbackUsed == true {
            return HubUIStrings.Models.Runtime.Task.fallbackHint
        }
        return nil
    }

    private static func localRuntimeTaskAgeSeconds(_ startedAt: Double) -> Int {
        guard startedAt > 0 else { return 0 }
        return max(0, Int(Date().timeIntervalSince1970 - startedAt))
    }

    private static func benchLoadSummary(_ benchResult: ModelBenchResult) -> String {
        var parts: [String] = []
        if let effectiveContextLength = benchResult.effectiveContextLength, effectiveContextLength > 0 {
            parts.append(exportStrings.benchContext(effectiveContextLength))
        }
        let profile = shortHash(benchResult.loadProfileHash)
        if profile != "none" {
            parts.append(exportStrings.benchProfile(profile))
        }
        return exportStrings.benchLoadSummary(parts)
    }

    private static func shortHash(_ value: String) -> String {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "none" }
        return String(token.prefix(8))
    }
}
