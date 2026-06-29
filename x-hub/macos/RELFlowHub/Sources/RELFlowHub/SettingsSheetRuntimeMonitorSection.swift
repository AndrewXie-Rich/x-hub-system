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

            if rustLocalMLAuthorityMode {
                rustLocalMLRuntimeAuthorityMonitorCard
            }

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
                    if !status.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) && !runtimeReadyForUI {
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
                Text(
                    rustLocalMLAuthorityMode
                        ? "Rust 本地模型执行状态已由上方 readiness 投影给出；provider/queue 快照会在 xhubd-owned Python worker 上报后出现。"
                        : HubUIStrings.Settings.RuntimeMonitor.waitingForHeartbeat
                )
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
        .id(runtimeMonitorSectionAnchorID)
    }

    var rustLocalMLRuntimeAuthorityMonitorCard: some View {
        let snapshot = rustLocalMLExecutionReadinessSnapshot
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Rust local ML authority", systemImage: "cpu")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(snapshot.statusText)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(rustLocalMLExecutionReadinessTint.opacity(0.14))
                    .clipShape(Capsule())
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                runtimeMonitorMetricCard(
                    title: "Authority",
                    value: snapshot.authorityText,
                    detail: snapshot.executionAuthorityInRust ? "execution in Rust" : "not authority"
                )
                runtimeMonitorMetricCard(
                    title: "Command proxy",
                    value: snapshot.commandProxyText,
                    detail: snapshot.commandProxyReady ? "worker reachable" : "worker pending"
                )
                runtimeMonitorMetricCard(
                    title: "Engine",
                    value: snapshot.engineText,
                    detail: snapshot.bridgeHTTP ? "bridge_http=1" : "bridge_http=0"
                )
                runtimeMonitorMetricCard(
                    title: "Updated",
                    value: snapshot.updatedAtMs > 0 ? formatEpochMs(snapshot.updatedAtMs) : "pending",
                    detail: snapshot.schemaVersion.isEmpty ? "schema unknown" : snapshot.schemaVersion
                )
            }

            Text("Swift shell 只展示 Rust readiness；本页下方的 provider、queue、instance 是 Rust daemon 管理的本地 worker 运行快照。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                HubNeutralActionChipButton(
                    title: rustLocalMLExecutionReadinessRefreshing ? "刷新中" : HubUIStrings.Settings.Advanced.Runtime.refreshRustReadiness,
                    systemName: "arrow.clockwise",
                    width: nil,
                    help: nil
                ) {
                    refreshRustLocalMLExecutionReadiness(force: true)
                    refreshRustHubRuntimeSnapshot(force: true)
                }
                HubNeutralActionChipButton(
                    title: HubUIStrings.Settings.RuntimeMonitor.copyProviderSummary,
                    systemName: "doc.on.doc",
                    width: nil,
                    help: nil
                ) {
                    copyLocalProviderSummaryToClipboard(snapshot: hubLaunchStatus)
                }
                Spacer()
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
}
