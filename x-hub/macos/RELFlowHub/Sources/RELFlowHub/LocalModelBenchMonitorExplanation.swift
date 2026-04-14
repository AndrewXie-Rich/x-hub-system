import Foundation
import RELFlowHubCore

struct LocalModelBenchMonitorExplanation: Equatable {
    enum Severity: String, Equatable {
        case neutral
        case info
        case warning
    }

    var headline: String
    var detailLines: [String]
    var severity: Severity
}

enum LocalModelBenchMonitorExplanationBuilder {
    static func build(
        model: HubModel,
        taskKind: String,
        requestContext: LocalModelRuntimeRequestContext?,
        benchResult: ModelBenchResult?,
        runtimeStatus: AIRuntimeStatus?
    ) -> LocalModelBenchMonitorExplanation? {
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let providerMonitor = runtimeStatus?.monitorSnapshot?.providers.first(where: { $0.provider == providerID })
        let providerStatus = runtimeStatus?.providerStatus(providerID)
        let providerErrors = runtimeStatus?.monitorSnapshot?.lastErrors.filter { $0.provider == providerID } ?? []
        let loadedInstances = providerStatus?.loadedInstances.filter { $0.modelId == model.id } ?? []
        let matchingActiveTasks = matchingActiveTasks(
            modelID: model.id,
            providerID: providerID,
            taskKind: normalizedTaskKind,
            requestContext: requestContext,
            runtimeStatus: runtimeStatus
        )

        let targetResident = matchesResidentTarget(
            requestContext: requestContext,
            loadedInstances: loadedInstances
        )
        let queueActive = (providerMonitor?.queuedTaskCount ?? 0) > 0
        let targetBusy = !matchingActiveTasks.isEmpty
        let benchFailed = benchResult.map { !$0.ok } ?? false
        let fallbackMode = (benchResult?.fallbackMode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let taskTitle = LocalTaskRoutingCatalog.title(for: normalizedTaskKind)
        let providerFallbackReady = providerMonitor?.fallbackTaskKinds.contains(normalizedTaskKind) == true
        let providerUnavailable = providerMonitor?.unavailableTaskKinds.contains(normalizedTaskKind) == true
        let strings = HubUIStrings.Models.Review.MonitorExplanation.self

        let headline: String
        let severity: LocalModelBenchMonitorExplanation.Severity
        if benchFailed {
            headline = strings.benchFailedHeadline
            severity = .warning
        } else if !fallbackMode.isEmpty {
            headline = strings.fallbackPathHeadline
            severity = .warning
        } else if queueActive {
            headline = strings.providerQueueBusyHeadline
            severity = .warning
        } else if targetBusy {
            headline = strings.targetBusyHeadline
            severity = .warning
        } else if providerUnavailable {
            headline = strings.providerUnavailableHeadline(taskTitle)
            severity = .warning
        } else if !targetResident {
            headline = strings.coldStartHeadline
            severity = .info
        } else if providerFallbackReady {
            headline = strings.fallbackReadyHeadline(taskTitle)
            severity = .info
        } else {
            headline = strings.runtimeReadyHeadline
            severity = .neutral
        }

        var detailLines: [String] = []
        if let benchResult, benchFailed {
            let reason = benchResult.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = LocalModelRuntimeErrorPresentation.humanized(reason)
            detailLines.append(strings.benchReason(message))
        }
        if let requestContext {
            let loadSummary = requestContext.technicalLoadProfileSummary
            if !loadSummary.isEmpty {
                detailLines.append(strings.targetLoad(loadSummary))
            }
        }
        if let benchResult {
            let loadSummary = benchLoadSummary(benchResult)
            if !loadSummary.isEmpty {
                if let requestContext, requestContext.matchesBenchResult(benchResult) {
                    detailLines.append(strings.benchLoadMatchesCurrent(loadSummary))
                } else {
                    detailLines.append(strings.latestBenchLoad(loadSummary))
                }
            }
        }
        if !fallbackMode.isEmpty {
            detailLines.append(strings.fallbackMode(fallbackMode))
        } else if providerFallbackReady {
            detailLines.append(strings.providerFallbackReady(taskTitle))
        } else if providerUnavailable {
            detailLines.append(strings.providerUnavailable(taskTitle))
        }
        if let providerMonitor, queueActive {
            let waitText = providerMonitor.oldestWaiterAgeMs > 0
                ? strings.oldestWait(providerMonitor.oldestWaiterAgeMs)
                : strings.queueActive
            detailLines.append(strings.queueSummary(waitingCount: providerMonitor.queuedTaskCount, waitText: waitText))
        }
        if targetBusy {
            detailLines.append(strings.targetBusy(matchingActiveTasks.count))
        }
        if targetResident {
            if let requestContext, !requestContext.instanceKey.isEmpty {
                detailLines.append(strings.residentInstance(shortInstanceLabel(requestContext.instanceKey)))
            } else {
                detailLines.append(strings.residentLoadConfig)
            }
        } else if let providerMonitor,
                  providerMonitor.lifecycleMode == "warmable" || (requestContext?.instanceKey.isEmpty == false) {
            detailLines.append(strings.residentColdStart)
        }
        if let providerMonitor, providerMonitor.memoryState != "unknown" {
            detailLines.append(
                strings.memory(
                    active: formatBytes(providerMonitor.activeMemoryBytes),
                    peak: formatBytes(providerMonitor.peakMemoryBytes)
                )
            )
        }
        if let lastError = providerErrors.first {
            let code = lastError.code.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = lastError.message.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = message.isEmpty ? "" : " (\(message))"
            detailLines.append(strings.providerError(code: code, suffix: suffix))
        }
        if let providerMonitor,
           providerMonitor.contentionCount > 0,
           !detailLines.contains(where: { $0.hasPrefix(strings.queuePrefix) }) {
            detailLines.append(strings.contentionCount(providerMonitor.contentionCount))
        }

        detailLines = normalizedDetailLines(detailLines)
        if detailLines.isEmpty {
            return nil
        }
        return LocalModelBenchMonitorExplanation(
            headline: headline,
            detailLines: Array(detailLines.prefix(6)),
            severity: severity
        )
    }

    private static func matchingActiveTasks(
        modelID: String,
        providerID: String,
        taskKind: String,
        requestContext: LocalModelRuntimeRequestContext?,
        runtimeStatus: AIRuntimeStatus?
    ) -> [AIRuntimeMonitorActiveTask] {
        let activeTasks = runtimeStatus?.monitorSnapshot?.activeTasks ?? []
        return activeTasks.filter { task in
            guard task.provider == providerID, task.modelId == modelID else { return false }
            if !taskKind.isEmpty, task.taskKind != taskKind {
                return false
            }
            guard let requestContext else { return true }
            if !requestContext.instanceKey.isEmpty {
                return task.instanceKey == requestContext.instanceKey
            }
            if !requestContext.preferredBenchHash.isEmpty,
               !task.loadProfileHash.isEmpty {
                return task.loadProfileHash == requestContext.preferredBenchHash
            }
            if !requestContext.deviceID.isEmpty,
               !task.deviceId.isEmpty {
                return task.deviceId == requestContext.deviceID
            }
            if requestContext.effectiveContextLength > 0,
               task.effectiveContextLength > 0 {
                return task.effectiveContextLength == requestContext.effectiveContextLength
            }
            return true
        }
    }

    private static func matchesResidentTarget(
        requestContext: LocalModelRuntimeRequestContext?,
        loadedInstances: [AIRuntimeLoadedInstance]
    ) -> Bool {
        guard let requestContext else { return false }
        if !requestContext.instanceKey.isEmpty {
            return loadedInstances.contains { $0.instanceKey == requestContext.instanceKey }
        }
        if !requestContext.preferredBenchHash.isEmpty {
            return loadedInstances.contains {
                !$0.loadProfileHash.isEmpty && $0.loadProfileHash == requestContext.preferredBenchHash
            }
        }
        if requestContext.effectiveContextLength > 0 {
            return loadedInstances.contains { $0.effectiveContextLength == requestContext.effectiveContextLength }
        }
        return false
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .memory)
    }

    private static func shortInstanceLabel(_ value: String) -> String {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return HubUIStrings.Models.Review.MonitorExplanation.unknown }
        if let last = token.split(separator: ":").last, !last.isEmpty {
            return String(String(last).prefix(8))
        }
        return String(token.prefix(8))
    }

    private static func benchLoadSummary(_ benchResult: ModelBenchResult) -> String {
        var parts: [String] = []
        if let effectiveContextLength = benchResult.effectiveContextLength, effectiveContextLength > 0 {
            parts.append("ctx=\(effectiveContextLength)")
        }
        let loadProfileHash = benchResult.loadProfileHash.trimmingCharacters(in: .whitespacesAndNewlines)
        if !loadProfileHash.isEmpty {
            parts.append("profile=\(String(loadProfileHash.prefix(8)))")
        }
        return HubUIStrings.Formatting.middleDotSeparated(parts)
    }

    private static func normalizedDetailLines(_ values: [String]) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for raw in values {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, seen.insert(token).inserted else { continue }
            out.append(token)
        }
        return out
    }
}
