import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    var blockedCapabilityCount: Int {
        hubLaunchStatus?.degraded.blockedCapabilities.count ?? 0
    }

    var settingsIssueCount: Int {
        var count = blockedCapabilityCount
        if !grpc.lastError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            count += 1
        }
        if rustLocalMLAuthorityMode {
            let snapshot = rustLocalMLExecutionReadinessSnapshot
            if snapshot.updatedAtMs > 0 && snapshot.enabled && !snapshot.ready {
                count += 1
            }
        } else if !store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            count += 1
        }
        if !grpcDeniedAttempts.attempts.isEmpty {
            count += 1
        }
        if !operatorChannelProviderReadinessError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            count += 1
        }
        return count
    }

    var readyRuntimeProviderCount: Int {
        if let monitor = store.aiRuntimeStatusSnapshot?.monitorSnapshot {
            return monitor.providers.filter(\.ok).count
        }
        return store.aiRuntimeStatusSnapshot?.providers.values.filter(\.ok).count ?? 0
    }

    var totalRuntimeProviderCount: Int {
        if let monitor = store.aiRuntimeStatusSnapshot?.monitorSnapshot {
            return monitor.providers.count
        }
        return store.aiRuntimeStatusSnapshot?.providers.count ?? 0
    }

    var loadedRuntimeInstanceCount: Int {
        store.aiRuntimeStatusSnapshot?.monitorSnapshot?.loadedInstances.count ?? 0
    }

    var rustLocalMLAuthorityMode: Bool {
        store.rustLocalMLExecutionAuthorityActiveForUI || rustLocalMLExecutionReadinessSnapshot.enabled
    }

    var runtimeReadyForUI: Bool {
        if rustLocalMLAuthorityMode {
            return rustLocalMLExecutionReadinessSnapshot.ready
        }
        guard let status = store.aiRuntimeStatusSnapshot else { return false }
        return status.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
    }

    var runtimeAuthorityTint: Color {
        if rustLocalMLAuthorityMode {
            let snapshot = rustLocalMLExecutionReadinessSnapshot
            if snapshot.ready { return .green }
            if snapshot.enabled { return .orange }
            return snapshot.ok ? .secondary : .red
        }
        return runtimeReadyForUI ? .green : .orange
    }

    var runtimeAuthorityDetailText: String {
        if rustLocalMLAuthorityMode {
            let snapshot = rustLocalMLExecutionReadinessSnapshot
            if snapshot.updatedAtMs <= 0 {
                return "等待 Rust readiness 刷新"
            }
            let proxy = snapshot.commandProxyReady ? "command proxy ready" : "command proxy pending"
            let blocker = snapshot.blocker.trimmingCharacters(in: .whitespacesAndNewlines)
            if !blocker.isEmpty {
                return "Rust authority · \(snapshot.authorityText) · blocker=\(blocker)"
            }
            return "Rust authority · \(snapshot.authorityText) · \(proxy)"
        }
        if totalRuntimeProviderCount > 0 {
            return "\(readyRuntimeProviderCount)/\(totalRuntimeProviderCount) 个 provider 就绪"
        }
        return "等待 provider 心跳"
    }

    var runtimeDoctorDetailText: String {
        if rustLocalMLAuthorityMode {
            let snapshot = rustLocalMLExecutionReadinessSnapshot
            if snapshot.updatedAtMs <= 0 {
                return "Swift shell 正在等待 Rust /runtime/ml-execution/readiness。"
            }
            let parts = [
                "schema=\(snapshot.schemaVersion.isEmpty ? "unknown" : snapshot.schemaVersion)",
                "authority=\(snapshot.authorityText)",
                "engine=\(snapshot.engineText)",
                "command_proxy=\(snapshot.commandProxyReady ? "ready" : "not_ready")",
                "python=\(snapshot.pythonAvailable ? "available" : "missing")"
            ]
            return parts.joined(separator: "\n")
        }
        return store.aiRuntimeDoctorSummaryText
    }

    var rustLocalMLReadinessClipboardText: String {
        let snapshot = rustLocalMLExecutionReadinessSnapshot
        guard snapshot.updatedAtMs > 0 else {
            return "rust_local_ml_readiness=not_loaded"
        }
        return [
            "schema_version=\(snapshot.schemaVersion)",
            "ok=\(snapshot.ok)",
            "enabled=\(snapshot.enabled)",
            "ready=\(snapshot.ready)",
            "authority=\(snapshot.authorityText)",
            "execution_authority_in_rust=\(snapshot.executionAuthorityInRust)",
            "engine=\(snapshot.engineText)",
            "command_proxy_ready=\(snapshot.commandProxyReady)",
            "blocker=\(snapshot.blocker)",
            "runtime_base_dir=\(snapshot.runtimeBaseDir)",
            "script_path=\(snapshot.scriptPath)",
            "python_available=\(snapshot.pythonAvailable)",
            "python_executable=\(snapshot.pythonExecutable)"
        ].joined(separator: "\n")
    }

    var quotaPoolCount: Int {
        providerKeyDerivedSnapshot.quotaPools.count
    }

    var operatorReadyCount: Int {
        operatorChannelProviderReadiness.filter(\.ready).count
    }

    var runtimeHeartbeatText: String {
        if rustLocalMLAuthorityMode {
            let snapshot = rustLocalMLExecutionReadinessSnapshot
            if snapshot.ready { return "Rust Ready" }
            if snapshot.enabled {
                return "Rust Blocked"
            }
            if snapshot.updatedAtMs > 0 { return "Rust Disabled" }
            return "等待 Rust"
        }
        guard let status = store.aiRuntimeStatusSnapshot else {
            return "等待心跳"
        }
        return status.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ? "在线" : "心跳过期"
    }

    var hubStatusPresentation: HubStatusPresentation {
        HubStatusPresentationSupport.make(
            snapshot: hubLaunchStatus,
            grpcIsRunning: grpc.isRunning,
            grpcStatusText: grpc.statusText
        )
    }

    var hubStatusDetailText: String {
        let detail = hubStatusPresentation.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "等待 Hub 状态同步" : detail
    }

    var hubStatusBadgeText: String {
        guard hubStatusPresentation.needsActionHint else {
            return hubStatusPresentation.title
        }
        return "\(hubStatusPresentation.title) · \(hubStatusPresentation.actionTitle)"
    }

    var hubStatusActionSummaryText: String {
        guard hubStatusPresentation.needsActionHint else {
            return hubStatusDetailText
        }
        return "\(hubStatusDetailText) · 下一步：\(hubStatusPresentation.actionTitle)"
    }

    var headerLaunchTint: Color {
        hubStatusPresentation.tint
    }

    var headerMetrics: [HubSettingsMetric] {
        [
            HubSettingsMetric(
                title: "Hub 状态",
                value: hubStatusPresentation.title,
                detail: settingsIssueCount > 0 ? "\(settingsIssueCount) 个待处理问题 · \(hubStatusActionSummaryText)" : hubStatusActionSummaryText,
                tint: headerLaunchTint
            ),
            HubSettingsMetric(
                title: "XT 设备",
                value: "\(grpc.allowedClients.count)",
                detail: grpcDeniedAttempts.attempts.isEmpty ? "没有新的拒绝记录" : "最近有 \(grpcDeniedAttempts.attempts.count) 条拒绝记录",
                tint: .teal
            ),
            HubSettingsMetric(
                title: "远端模型",
                value: "\(activeRemoteModelCount)",
                detail: "\(providerKeyDerivedSnapshot.totalAccounts) 个 key · \(quotaPoolCount) 个额度池",
                tint: .indigo
            ),
            cliproxyOAuthHeaderMetric,
            HubSettingsMetric(
                title: rustLocalMLAuthorityMode ? "本地执行内核" : "本地运行时",
                value: runtimeHeartbeatText,
                detail: runtimeAuthorityDetailText,
                tint: runtimeAuthorityTint
            )
        ]
    }

    var routingSummaryText: String {
        let defaults = store.routingSettings.hubDefaultModelIdByTaskKind
            .values
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        let overrides = store.routingSettings.devicePreferredModelIdByTaskKind
            .values
            .reduce(0) { partialResult, deviceMap in
                partialResult + deviceMap.values.filter {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }.count
            }

        if defaults == 0 && overrides == 0 {
            return "当前没有显式任务路由映射，Hub 会按默认模型解析。"
        }
        return "Hub 默认映射 \(defaults) 条，终端覆写 \(overrides) 条。这里只在你想强制指定任务模型时才需要展开。"
    }

    var modelHealthAutoScanSummaryText: String {
        [
            autoScanScheduleSummaryText(
                label: "本地",
                schedule: store.localModelHealthAutoScanSchedule,
                nextRunText: nextLocalModelHealthAutoScanText()
            ),
            autoScanScheduleSummaryText(
                label: "远端",
                schedule: store.remoteKeyHealthAutoScanSchedule,
                nextRunText: nextRemoteKeyHealthAutoScanText()
            )
        ]
        .joined(separator: " · ")
    }

    var integrationsAuxSummaryText: String {
        let operatorSummary = operatorChannelProviderReadiness.isEmpty
            ? "Operator 待检测"
            : "Operator \(operatorReadyCount)/\(operatorChannelProviderReadiness.count) 就绪"
        return [
            operatorSummary,
            "\(skillsIndex.skills.count) 个 skills",
            "日历 \(store.calendarStatus)",
            "浮窗 \(store.floatingMode.title)"
        ]
        .joined(separator: " · ") + "。这些都属于低频维护项，默认折叠更利于扫读。"
    }

    var diagnosticsLaunchSummaryText: String {
        var parts: [String] = [hubStatusPresentation.title]
        if blockedCapabilityCount > 0 {
            parts.append("\(blockedCapabilityCount) 项 capability 受阻")
        }
        if hubStatusPresentation.needsActionHint {
            parts.append("下一步：\(hubStatusPresentation.actionTitle)")
        }
        let rootCauseText = settingsSummarySnippet(renderRootCauseText(hubLaunchStatus?.rootCause), limit: 110)
        if !rootCauseText.isEmpty {
            parts.append(rootCauseText)
        } else {
            parts.append("这里可查看 root cause、provider 摘要和 launch history。")
        }
        return parts.joined(separator: " · ")
    }

    var diagnosticsNetworkSummaryText: String {
        var parts: [String] = []
        if store.pendingNetworkRequests.isEmpty {
            parts.append("当前没有待授权网络请求")
        } else {
            parts.append("\(store.pendingNetworkRequests.count) 个网络请求待处理")
        }
        parts.append(networkPolicies.isEmpty ? "没有项目级网络策略" : "\(networkPolicies.count) 条项目级网络策略")
        parts.append(store.bridge.bridgeStatusText)
        return parts.joined(separator: " · ")
    }

    var diagnosticsAdvancedSummaryText: String {
        if rustLocalMLAuthorityMode {
            let constitutionVersion = axConstitutionVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            return [
                "本地模型执行由 Rust 接管",
                runtimeHeartbeatText,
                rustLocalMLExecutionReadinessSnapshot.commandProxyText,
                constitutionVersion.isEmpty ? "宪章版本未读取" : "宪章 \(constitutionVersion)"
            ]
            .joined(separator: " · ")
        }
        let pythonText = settingsCompactPathDisplay(store.aiRuntimePython)
        let constitutionVersion = axConstitutionVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            store.aiRuntimeAutoStart ? "运行时自动启动" : "运行时手动启动",
            pythonText.isEmpty ? "Python 走自动发现" : "Python \(pythonText)",
            constitutionVersion.isEmpty ? "宪章版本未读取" : "宪章 \(constitutionVersion)"
        ]
        .joined(separator: " · ")
    }

    private func autoScanScheduleSummaryText(
        label: String,
        schedule: ModelHealthAutoScanSchedule,
        nextRunText: String?
    ) -> String {
        let modeText: String
        switch schedule.mode {
        case .disabled:
            modeText = "关闭"
        case .interval:
            modeText = "每 \(schedule.intervalHours) 小时"
        case .dailyTime:
            modeText = "每日 \(formattedClockTime(minuteOfDay: schedule.dailyMinuteOfDay))"
        }

        if let nextRunText, !nextRunText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(label) \(modeText) · 下次 \(nextRunText)"
        }
        return "\(label) \(modeText)"
    }

    private func formattedClockTime(minuteOfDay: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: clockDate(for: minuteOfDay))
    }

    func settingsSummarySnippet(_ raw: String, limit: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > limit else { return trimmed }
        let prefix = String(trimmed.prefix(max(0, limit - 1))).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + "…"
    }

    private func settingsCompactPathDisplay(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let url = URL(fileURLWithPath: trimmed)
        let last = url.lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent
        if parent.isEmpty {
            return last
        }
        return "\(parent)/\(last)"
    }


    func launchStateLabel(_ state: HubLaunchState?) -> String {
        switch state {
        case .bootStart:
            return HubUIStrings.Settings.Diagnostics.stateBootStart
        case .envValidate:
            return HubUIStrings.Settings.Diagnostics.stateEnvValidate
        case .startGRPCServer, .waitGRPCReady:
            return HubUIStrings.Settings.Diagnostics.statePrepareGRPC
        case .startBridge, .waitBridgeReady:
            return HubUIStrings.Settings.Diagnostics.statePrepareBridge
        case .startRuntime, .waitRuntimeReady:
            return HubUIStrings.Settings.Diagnostics.statePrepareRuntime
        case .serving:
            return HubUIStrings.Settings.Diagnostics.stateServing
        case .degradedServing:
            return HubUIStrings.Settings.Diagnostics.stateDegradedServing
        case .failed:
            return HubUIStrings.Settings.Diagnostics.stateFailed
        case nil:
            return HubUIStrings.Settings.Diagnostics.stateUnknown
        }
    }

    var currentLaunchStateLabel: String {
        hubStatusPresentation.title
    }
}
