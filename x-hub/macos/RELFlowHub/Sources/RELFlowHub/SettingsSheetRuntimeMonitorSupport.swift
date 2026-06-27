import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    func formatEpochSeconds(_ seconds: Double) -> String {
        guard seconds > 0 else { return HubUIStrings.Settings.RuntimeMonitor.unknown }
        return formatEpochMs(Int64(seconds * 1000.0))
    }

    func formatRuntimeMemoryBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .memory)
    }

    func runtimeMonitorTaskKindsText(_ values: [String]) -> String {
        HubUIStrings.Settings.RuntimeMonitor.taskKinds(values)
    }

    func runtimeMonitorMemoryText(_ provider: AIRuntimeMonitorProvider) -> String {
        return HubUIStrings.Settings.RuntimeMonitor.memorySummary(
            memoryState: provider.memoryState,
            current: formatRuntimeMemoryBytes(provider.activeMemoryBytes),
            peak: formatRuntimeMemoryBytes(provider.peakMemoryBytes)
        )
    }

    @ViewBuilder
    func runtimeMonitorMetricCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    func runtimeMonitorProviderCard(_ provider: AIRuntimeMonitorProvider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(provider.provider.uppercased())
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(HubUIStrings.Settings.RuntimeMonitor.providerStatus(ok: provider.ok))
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((provider.ok ? Color.green : Color.red).opacity(0.14))
                    .clipShape(Capsule())
                if provider.queuedTaskCount > 0 {
                    Text(HubUIStrings.Settings.RuntimeMonitor.queuedCount(provider.queuedTaskCount))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Text(
                HubUIStrings.Settings.RuntimeMonitor.reasonBackend(
                    reason: provider.reasonCode.isEmpty ? HubUIStrings.Settings.RuntimeMonitor.none : provider.reasonCode,
                    backend: provider.deviceBackend.isEmpty ? HubUIStrings.Settings.RuntimeMonitor.unknown : provider.deviceBackend
                )
            )
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(
                HubUIStrings.Settings.RuntimeMonitor.taskKindsSummary(
                    real: runtimeMonitorTaskKindsText(provider.realTaskKinds),
                    fallback: runtimeMonitorTaskKindsText(provider.fallbackTaskKinds),
                    unavailable: runtimeMonitorTaskKindsText(provider.unavailableTaskKinds)
                )
            )
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(
                HubUIStrings.Settings.RuntimeMonitor.providerLoadSummary(
                    activeTaskCount: provider.activeTaskCount,
                    concurrencyLimit: provider.concurrencyLimit,
                    queuedTaskCount: provider.queuedTaskCount,
                    loadedInstanceCount: provider.loadedInstanceCount,
                    loadedModelCount: provider.loadedModelCount
                )
            )
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(
                HubUIStrings.Settings.RuntimeMonitor.queueSummary(
                    mode: provider.queueMode.isEmpty ? HubUIStrings.Settings.RuntimeMonitor.unknown : provider.queueMode,
                    oldestWaiterAgeMs: provider.oldestWaiterAgeMs,
                    contentionCount: provider.contentionCount,
                    memory: runtimeMonitorMemoryText(provider)
                )
            )
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !provider.lastIdleEvictionReason.isEmpty || !provider.importError.isEmpty {
                Text(
                    HubUIStrings.Settings.RuntimeMonitor.idleEvictionSummary(
                        policy: provider.idleEvictionPolicy.isEmpty ? HubUIStrings.Settings.RuntimeMonitor.unknown : provider.idleEvictionPolicy,
                        lastEviction: provider.lastIdleEvictionReason.isEmpty ? HubUIStrings.Settings.RuntimeMonitor.none : provider.lastIdleEvictionReason,
                        importError: provider.importError.isEmpty ? HubUIStrings.Settings.RuntimeMonitor.none : provider.importError
                    )
                )
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            let providerHint = (store.aiRuntimeProviderHelpTextByProvider[provider.provider] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !providerHint.isEmpty {
                Text(providerHint)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func runtimeMonitorActiveTaskLine(_ task: AIRuntimeMonitorActiveTask) -> String {
        HubUIStrings.Settings.RuntimeMonitor.activeTaskLine(
            provider: task.provider,
            taskKind: task.taskKind,
            modelID: task.modelId,
            requestID: task.requestId,
            deviceID: task.deviceId,
            instanceKey: task.instanceKey,
            loadConfigHash: task.loadConfigHash,
            currentContextLength: task.currentContextLength,
            maxContextLength: task.maxContextLength > task.currentContextLength ? task.maxContextLength : nil,
            leaseTtlSec: task.leaseTtlSec
        )
    }

    func runtimeMonitorLoadedInstanceLine(_ instance: AIRuntimeLoadedInstance) -> String {
        HubUIStrings.Settings.RuntimeMonitor.loadedInstanceLine(
            modelID: instance.modelId,
            taskKinds: runtimeMonitorTaskKindsText(instance.taskKinds),
            instanceKey: instance.instanceKey,
            loadConfigHash: instance.loadConfigHash,
            currentContextLength: instance.currentContextLength,
            maxContextLength: instance.maxContextLength,
            ttl: instance.ttl ?? instance.loadConfig?.ttl,
            residency: instance.residency,
            backend: instance.deviceBackend,
            lastUsedAt: formatEpochSeconds(instance.lastUsedAt)
        )
    }

    func runtimeMonitorLoadedInstanceLine(_ row: LocalRuntimeOperationsSummary.InstanceRow) -> String {
        HubUIStrings.Settings.RuntimeMonitor.loadedInstanceRowLine(
            modelID: row.modelID,
            modelName: row.modelName,
            providerID: row.providerID,
            instanceKey: row.shortInstanceKey.isEmpty ? row.instanceKey : row.shortInstanceKey,
            taskSummary: row.taskSummary,
            loadSummary: row.loadSummary,
            detailSummary: row.detailSummary,
            currentTargetSummary: row.isCurrentTarget ? row.currentTargetSummary : nil
        )
    }

    func runtimeMonitorCurrentTargetLine(
        model: HubModel,
        requestContext: LocalModelRuntimeRequestContext
    ) -> String {
        let modelName = model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model.id : model.name
        return HubUIStrings.Settings.RuntimeMonitor.currentTargetLine(
            modelID: model.id,
            modelName: modelName,
            providerID: requestContext.providerID,
            target: requestContext.uiSummary,
            detail: requestContext.technicalSummary
        )
    }

    func runtimeMonitorErrorLine(_ error: AIRuntimeMonitorLastError) -> String {
        HubUIStrings.Settings.RuntimeMonitor.errorLine(
            provider: error.provider,
            severity: error.severity,
            code: error.code,
            message: error.message
        )
    }
}
