import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    var rustLocalModelRepairApplyFeedback: some View {
        let error = rustLocalModelRepairApplyErrorText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !error.isEmpty {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        } else if rustLocalModelRepairExecutorInFlight {
            Label(HubUIStrings.Models.Runtime.LocalServiceRecovery.rustRepairExecutorRunning, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.blue)
        } else if let job = rustLocalModelRepairJobsSnapshot.latestJob,
                  ["queued_waiting_executor", "running_install_provider_pack"].contains(job.status) {
            Label(
                HubUIStrings.Models.Runtime.LocalServiceRecovery.rustRepairJobStatus(
                    jobID: job.jobID,
                    status: job.status
                ),
                systemImage: job.status == "running_install_provider_pack" ? "arrow.triangle.2.circlepath" : "clock"
            )
            .font(.caption)
            .foregroundStyle(.blue)
            .textSelection(.enabled)
        } else if let result = rustLocalModelRepairExecutorResult {
            Label(
                HubUIStrings.Models.Runtime.LocalServiceRecovery.rustRepairExecutorFinished(
                    status: result.status,
                    ok: result.ok
                ),
                systemImage: result.ok ? "checkmark.seal" : "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(result.ok ? .blue : .orange)
            .textSelection(.enabled)
        } else if let job = rustLocalModelRepairJobsSnapshot.latestJob {
            Label(
                HubUIStrings.Models.Runtime.LocalServiceRecovery.rustRepairJobStatus(
                    jobID: job.jobID,
                    status: job.status
                ),
                systemImage: job.status == "applied_pending_runtime_restart" ? "checkmark.seal" : "clock"
            )
            .font(.caption)
            .foregroundStyle(job.status == "failed" ? .orange : .secondary)
            .textSelection(.enabled)
        } else if let result = rustLocalModelRepairApplyResult {
            let text = result.accepted
                ? HubUIStrings.Models.Runtime.LocalServiceRecovery.rustRepairApplyQueued(
                    jobID: result.jobID,
                    executorReady: result.jobPolicy.executorReady
                )
                : HubUIStrings.Models.Runtime.LocalServiceRecovery.rustRepairApplyRejected(status: result.status)
            Label(text, systemImage: result.accepted ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(result.accepted ? .blue : .orange)
                .textSelection(.enabled)
        }
    }

    var runtimeMonitorSection: some View {
        Section(HubUIStrings.Settings.RuntimeMonitor.sectionTitle) {
            if let summary = effectiveRuntimeRepairSurfaceSummary {
                LocalRuntimeRepairEntryCard(
                    summary: summary,
                    onCopySummary: { copyLocalRuntimeRepairSummary(summary) },
                    onOpenLog: { store.openAIRuntimeLog() },
                    queueRepairTitle: (rustLocalModelRepairApplyInFlight || rustLocalModelRepairExecutorInFlight)
                        ? HubUIStrings.Models.Runtime.LocalServiceRecovery.queueRustRepairInFlightAction
                        : HubUIStrings.Models.Runtime.LocalServiceRecovery.queueRustRepairAction,
                    onQueueRepair: rustLocalModelRepairPlan?.isActionableRepair == true
                        && !rustLocalModelRepairExecutorInFlight
                        ? { presentRustLocalModelRepairApplyDialog() }
                        : nil
                )
            }

            rustLocalModelRepairApplyFeedback

            modelConcurrencyPolicyControls

            if let status = store.aiRuntimeStatusSnapshot,
               let monitor = status.monitorSnapshot {
                let runtimeOpsSummary = LocalRuntimeOperationsSummaryBuilder.build(
                    status: status,
                    models: modelStore.snapshot.models,
                    currentTargetsByModelID: modelStore.currentLocalRuntimeRequestContextByModelId
                )
                let currentTargets = modelStore.snapshot.models.compactMap { model -> (HubModel, LocalModelRuntimeRequestContext)? in
                    guard let requestContext = modelStore.currentLocalRuntimeRequestContextByModelId[model.id] else {
                        return nil
                    }
                    return (model, requestContext)
                }
                .sorted {
                    let lhsName = ($0.0.name.isEmpty ? $0.0.id : $0.0.name)
                    let rhsName = ($1.0.name.isEmpty ? $1.0.id : $1.0.name)
                    let nameOrder = lhsName.localizedCaseInsensitiveCompare(rhsName)
                    if nameOrder != .orderedSame {
                        return nameOrder == .orderedAscending
                    }
                    return $0.0.id.localizedCaseInsensitiveCompare($1.0.id) == .orderedAscending
                }
                VStack(alignment: .leading, spacing: 12) {
                    if !status.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) {
                        Text(HubUIStrings.Settings.RuntimeMonitor.staleHeartbeat)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        runtimeMonitorMetricCard(
                            title: HubUIStrings.Settings.RuntimeMonitor.Metric.providersTitle,
                            value: HubUIStrings.Settings.RuntimeMonitor.Metric.providersValue(
                                ready: monitor.providers.filter(\.ok).count,
                                total: monitor.providers.count
                            ),
                            detail: HubUIStrings.Settings.RuntimeMonitor.Metric.providersDetail(
                                hasProviders: !monitor.providers.isEmpty
                            )
                        )
                        runtimeMonitorMetricCard(
                            title: HubUIStrings.Settings.RuntimeMonitor.Metric.queueTitle,
                            value: HubUIStrings.Settings.RuntimeMonitor.Metric.queueValue(
                                active: monitor.queue.activeTaskCount,
                                queued: monitor.queue.queuedTaskCount
                            ),
                            detail: HubUIStrings.Settings.RuntimeMonitor.Metric.queueDetail(
                                busy: monitor.queue.providersBusyCount,
                                maxOldestWaitMs: monitor.queue.maxOldestWaitMs
                            )
                        )
                        runtimeMonitorMetricCard(
                            title: HubUIStrings.Settings.RuntimeMonitor.Metric.instancesTitle,
                            value: HubUIStrings.Settings.RuntimeMonitor.Metric.instancesValue(monitor.loadedInstances.count),
                            detail: HubUIStrings.Settings.RuntimeMonitor.Metric.instancesDetail(
                                taskCount: monitor.activeTasks.count
                            )
                        )
                        runtimeMonitorMetricCard(
                            title: HubUIStrings.Settings.RuntimeMonitor.Metric.fallbackTitle,
                            value: HubUIStrings.Settings.RuntimeMonitor.Metric.fallbackValue(
                                providerCount: monitor.fallbackCounters.fallbackReadyProviderCount
                            ),
                            detail: HubUIStrings.Settings.RuntimeMonitor.Metric.fallbackDetail(
                                taskCount: monitor.fallbackCounters.fallbackReadyTaskCount
                            )
                        )
                        runtimeMonitorMetricCard(
                            title: HubUIStrings.Settings.RuntimeMonitor.Metric.errorsTitle,
                            value: "\(monitor.lastErrors.count)",
                            detail: HubUIStrings.Settings.RuntimeMonitor.Metric.errorsDetail(
                                hasErrors: !monitor.lastErrors.isEmpty
                            )
                        )
                        runtimeMonitorMetricCard(
                            title: HubUIStrings.Settings.RuntimeMonitor.Metric.updatedAtTitle,
                            value: formatEpochSeconds(monitor.updatedAt),
                            detail: HubUIStrings.Settings.RuntimeMonitor.updatedAtDetail
                        )
                    }

                    Text(HubUIStrings.Settings.RuntimeMonitor.metricsExplainer)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        HubNeutralActionChipButton(
                            title: HubUIStrings.Settings.RuntimeMonitor.copySummary,
                            systemName: "doc.on.doc",
                            width: nil,
                            help: nil
                        ) {
                            copyRuntimeMonitorSummaryToClipboard(status: status)
                        }
                        if !monitor.activeTasks.isEmpty {
                            HubNeutralActionChipButton(
                                title: HubUIStrings.Settings.RuntimeMonitor.copyActiveTasks,
                                systemName: "list.bullet.rectangle",
                                width: nil,
                                help: nil
                            ) {
                                copyRuntimeMonitorActiveTasksToClipboard(monitor: monitor)
                            }
                        }
                        if !monitor.loadedInstances.isEmpty {
                            HubNeutralActionChipButton(
                                title: HubUIStrings.Settings.RuntimeMonitor.copyLoadedInstances,
                                systemName: "shippingbox",
                                width: nil,
                                help: nil
                            ) {
                                copyRuntimeMonitorLoadedInstancesToClipboard(summary: runtimeOpsSummary)
                            }
                        }
                        if !currentTargets.isEmpty {
                            HubNeutralActionChipButton(
                                title: HubUIStrings.Settings.RuntimeMonitor.copyCurrentTargets,
                                systemName: "scope",
                                width: nil,
                                help: nil
                            ) {
                                copyRuntimeMonitorCurrentTargetsToClipboard(currentTargets)
                            }
                        }
                        if !monitor.lastErrors.isEmpty {
                            HubNeutralActionChipButton(
                                title: HubUIStrings.Settings.RuntimeMonitor.copyLastErrors,
                                systemName: "exclamationmark.bubble",
                                width: nil,
                                help: nil
                            ) {
                                copyRuntimeMonitorErrorsToClipboard(monitor: monitor)
                            }
                        }
                        HubNeutralActionChipButton(
                            title: HubUIStrings.Settings.RuntimeMonitor.openLog,
                            systemName: "doc.text.magnifyingglass",
                            width: nil,
                            help: nil
                        ) {
                            store.openAIRuntimeLog()
                        }
                        Spacer()
                    }

                    if monitor.providers.isEmpty {
                        Text(HubUIStrings.Settings.RuntimeMonitor.noProviderRecords)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(monitor.providers, id: \.provider) { provider in
                            runtimeMonitorProviderCard(provider)
                        }
                    }

                    DisclosureGroup(HubUIStrings.Settings.RuntimeMonitor.currentTargetsDisclosure(currentTargets.count)) {
                        if currentTargets.isEmpty {
                            Text(HubUIStrings.Settings.RuntimeMonitor.currentTargetsEmpty)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(currentTargets.enumerated()), id: \.offset) { entry in
                                    let model = entry.element.0
                                    let requestContext = entry.element.1
                                    Text(runtimeMonitorCurrentTargetLine(model: model, requestContext: requestContext))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }

                    DisclosureGroup(HubUIStrings.Settings.RuntimeMonitor.activeTasksDisclosure(monitor.activeTasks.count)) {
                        if monitor.activeTasks.isEmpty {
                            Text(HubUIStrings.Settings.RuntimeMonitor.activeTasksEmpty)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            let activeTasks = Array(monitor.activeTasks.enumerated())
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(activeTasks, id: \.offset) { entry in
                                    let task = entry.element
                                    Text(runtimeMonitorActiveTaskLine(task))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }

                    DisclosureGroup(
                        HubUIStrings.Settings.RuntimeMonitor.loadedInstancesDisclosure(runtimeOpsSummary.instanceRows.count)
                    ) {
                        if runtimeOpsSummary.instanceRows.isEmpty {
                            Text(HubUIStrings.Settings.RuntimeMonitor.loadedInstancesEmpty)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(runtimeOpsSummary.instanceRows) { row in
                                    Text(runtimeMonitorLoadedInstanceLine(row))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }

                    DisclosureGroup(HubUIStrings.Settings.RuntimeMonitor.lastErrorsDisclosure(monitor.lastErrors.count)) {
                        if monitor.lastErrors.isEmpty {
                            Text(HubUIStrings.Settings.RuntimeMonitor.lastErrorsEmpty)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            let lastErrors = Array(monitor.lastErrors.enumerated())
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(lastErrors, id: \.offset) { entry in
                                    let error = entry.element
                                    Text(runtimeMonitorErrorLine(error))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            } else {
                Text(HubUIStrings.Settings.RuntimeMonitor.waitingForHeartbeat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    HubNeutralActionChipButton(
                        title: HubUIStrings.Settings.RuntimeMonitor.copyProviderSummary,
                        systemName: "doc.on.doc",
                        width: nil,
                        help: nil
                    ) {
                        copyLocalProviderSummaryToClipboard(snapshot: hubLaunchStatus)
                    }
                    HubNeutralActionChipButton(
                        title: HubUIStrings.Settings.RuntimeMonitor.openLog,
                        systemName: "doc.text.magnifyingglass",
                        width: nil,
                        help: nil
                    ) {
                        store.openAIRuntimeLog()
                    }
                    Spacer()
                }
            }
        }
    }

    var modelConcurrencyPolicyControls: some View {
        let policy = store.modelConcurrencyPolicy
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("模型并发策略", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("policy=\(policy.localDefaultConcurrencyLimit)/\(policy.paidModelGlobalConcurrencyLimit)/\(policy.paidModelPerProjectConcurrencyLimit)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Stepper(
                "本地模型默认并发：\(policy.localDefaultConcurrencyLimit)",
                value: Binding(
                    get: { store.modelConcurrencyPolicy.localDefaultConcurrencyLimit },
                    set: { store.setLocalModelDefaultConcurrencyLimit($0) }
                ),
                in: 1...64
            )
            Stepper(
                "付费模型全局并发：\(policy.paidModelGlobalConcurrencyLimit)",
                value: Binding(
                    get: { store.modelConcurrencyPolicy.paidModelGlobalConcurrencyLimit },
                    set: { store.setPaidModelGlobalConcurrencyLimit($0) }
                ),
                in: 1...64
            )
            Stepper(
                "付费模型每项目并发：\(policy.paidModelPerProjectConcurrencyLimit)",
                value: Binding(
                    get: { store.modelConcurrencyPolicy.paidModelPerProjectConcurrencyLimit },
                    set: { store.setPaidModelPerProjectConcurrencyLimit($0) }
                ),
                in: 1...16
            )
            Stepper(
                "付费模型队列上限：\(policy.paidModelQueueLimit)",
                value: Binding(
                    get: { store.modelConcurrencyPolicy.paidModelQueueLimit },
                    set: { store.setPaidModelQueueLimit($0) }
                ),
                in: 1...4096,
                step: 8
            )
            Stepper(
                "付费模型排队超时：\(policy.paidModelQueueTimeoutMs / 1000)s",
                value: Binding(
                    get: { store.modelConcurrencyPolicy.paidModelQueueTimeoutMs },
                    set: { store.setPaidModelQueueTimeoutMs($0) }
                ),
                in: 1_000...300_000,
                step: 1_000
            )

            Text("本地模型调度会在下一次任务读取新策略；付费模型 gRPC 队列会随 Hub 服务重启后使用新策略。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

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
