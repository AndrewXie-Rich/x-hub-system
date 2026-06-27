import Foundation
import RELFlowHubCore

extension XHubDoctorOutputReport {
    static func hubRuntimeReadinessBundle(
        status: AIRuntimeStatus?,
        blockedCapabilities: [String] = [],
        outputPath: String = XHubDoctorOutputStore.defaultHubReportURL().path,
        surface: XHubDoctorSurface = .hubUI,
        statusURL: URL = AIRuntimeStatusStorage.url(),
        generatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0),
        hostMetrics: XHubLocalRuntimeHostMetricsSnapshot? = XHubLocalRuntimeHostMetricsSampler.capture()
    ) -> XHubDoctorOutputReport {
        let ttl = 3.0
        let runtimeAlive = status?.isAlive(ttl: ttl) ?? false
        let providerDiagnoses = status?.providerDiagnoses(ttl: ttl) ?? []
        let readyProviders = providerDiagnoses
            .filter { $0.state == .ready }
            .map(\.provider)
            .sorted()
        let downProviders = providerDiagnoses
            .filter { $0.state != .ready }
            .map(\.provider)
            .sorted()
        let capabilityDiagnoses = status?.localCapabilityDiagnoses(
            ttl: ttl,
            blockedCapabilities: blockedCapabilities
        ) ?? []
        let managedServiceEvidence = XHubLocalServiceDiagnostics.providerEvidence(
            status: status,
            ttl: ttl
        )
        let blockedCapabilityIDs = blockedCapabilities
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        let monitorSnapshot = status?.monitorSnapshot

        let heartbeatCheck = buildHeartbeatCheck(
            runtimeAlive: runtimeAlive,
            status: status,
            statusURL: statusURL,
            observedAtMs: generatedAtMs
        )
        let providerCheck = buildProviderCheck(
            runtimeAlive: runtimeAlive,
            providerDiagnoses: providerDiagnoses,
            readyProviders: readyProviders,
            downProviders: downProviders,
            managedServiceEvidence: managedServiceEvidence,
            observedAtMs: generatedAtMs
        )
        let capabilityCheck = buildCapabilityCheck(
            runtimeAlive: runtimeAlive,
            blockedCapabilityIDs: blockedCapabilityIDs,
            capabilityDiagnoses: capabilityDiagnoses,
            observedAtMs: generatedAtMs
        )
        let monitorCheck = buildMonitorCheck(
            runtimeAlive: runtimeAlive,
            monitorSnapshot: monitorSnapshot,
            hostMetrics: hostMetrics,
            observedAtMs: generatedAtMs
        )

        let checks = [heartbeatCheck, providerCheck, capabilityCheck, monitorCheck]
        let readyForFirstTask = runtimeAlive && !readyProviders.isEmpty
        let overallState = normalizedOverallState(for: checks)
        let nextSteps = normalizedNextSteps(for: checks, readyForFirstTask: readyForFirstTask)
        let currentIssue = primaryIssue(in: checks)
        let sourceSchemaVersion = resolvedSourceSchemaVersion(status: status)

        return XHubDoctorOutputReport(
            schemaVersion: currentSchemaVersion,
            contractVersion: currentContractVersion,
            reportID: "xhub-doctor-hub-\(surface.rawValue)-\(generatedAtMs)",
            bundleKind: .providerRuntimeReadiness,
            producer: .xHub,
            surface: surface,
            overallState: overallState,
            summary: XHubDoctorOutputSummary(
                headline: summaryHeadline(
                    overallState: overallState,
                    readyForFirstTask: readyForFirstTask,
                    checks: checks
                ),
                checks: checks
            ),
            readyForFirstTask: readyForFirstTask,
            checks: checks,
            nextSteps: nextSteps,
            routeSnapshot: nil,
            generatedAtMs: generatedAtMs,
            reportPath: outputPath,
            sourceReportSchemaVersion: sourceSchemaVersion,
            sourceReportPath: HubDiagnosticsBundleExporter.redactTextForSharing(statusURL.path),
            currentFailureCode: currentIssue.code,
            currentFailureIssue: currentIssue.issue,
            consumedContracts: normalizedConsumedContracts(status: status)
        )
    }

    static func hubChannelOnboardingReadinessBundle(
        readinessRows: [HubOperatorChannelOnboardingDeliveryReadiness],
        runtimeRows: [HubOperatorChannelProviderRuntimeStatus],
        liveTestReports: [HubOperatorChannelLiveTestEvidenceReport] = [],
        sourceStatus: String = "ok",
        fetchErrors: [String] = [],
        sourceReportPath: String = "hub://admin/operator-channels",
        outputPath: String = XHubDoctorOutputStore.defaultHubChannelOnboardingReportURL().path,
        surface: XHubDoctorSurface = .hubUI,
        generatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)
    ) -> XHubDoctorOutputReport {
        let runtimeCheck = buildChannelRuntimeCheck(
            sourceStatus: sourceStatus,
            fetchErrors: fetchErrors,
            runtimeRows: runtimeRows,
            observedAtMs: generatedAtMs
        )
        let deliveryCheck = buildChannelDeliveryCheck(
            sourceStatus: sourceStatus,
            fetchErrors: fetchErrors,
            readinessRows: readinessRows,
            observedAtMs: generatedAtMs
        )
        let liveTestCheck = buildChannelLiveTestCheck(
            sourceStatus: sourceStatus,
            fetchErrors: fetchErrors,
            liveTestReports: liveTestReports,
            observedAtMs: generatedAtMs
        )
        let checks = [runtimeCheck, deliveryCheck, liveTestCheck]
        let overallState = normalizedOverallState(for: checks)
        let currentIssue = primaryIssue(in: checks)

        return XHubDoctorOutputReport(
            schemaVersion: currentSchemaVersion,
            contractVersion: currentContractVersion,
            reportID: "xhub-doctor-channel-\(surface.rawValue)-\(generatedAtMs)",
            bundleKind: .channelOnboardingReadiness,
            producer: .xHub,
            surface: surface,
            overallState: overallState,
            summary: XHubDoctorOutputSummary(
                headline: channelOnboardingSummaryHeadline(
                    overallState: overallState,
                    checks: checks
                ),
                checks: checks
            ),
            readyForFirstTask: !checks.contains(where: { $0.status == .fail && $0.blocking }),
            checks: checks,
            nextSteps: channelOnboardingNextSteps(for: checks),
            routeSnapshot: nil,
            generatedAtMs: generatedAtMs,
            reportPath: outputPath,
            sourceReportSchemaVersion: "xt_w3_24_operator_channel_live_test_evidence.v1",
            sourceReportPath: HubDiagnosticsBundleExporter.redactTextForSharing(sourceReportPath),
            currentFailureCode: currentIssue.code,
            currentFailureIssue: currentIssue.issue,
            consumedContracts: channelOnboardingConsumedContracts(liveTestReports: liveTestReports)
        )
    }
}

private extension XHubDoctorOutputSummary {
    init(headline: String, checks: [XHubDoctorOutputCheckResult]) {
        self.init(
            headline: headline,
            passed: checks.filter { $0.status == .pass }.count,
            failed: checks.filter { $0.status == .fail }.count,
            warned: checks.filter { $0.status == .warn }.count,
            skipped: checks.filter { $0.status == .skip }.count
        )
    }
}

private enum XHubDoctorOutputDestination {
    static let doctor = "hub://settings/doctor"
    static let diagnostics = "hub://settings/diagnostics"
    static let operatorChannels = "hub://settings/operator_channels"
}

private func buildHeartbeatCheck(
    runtimeAlive: Bool,
    status: AIRuntimeStatus?,
    statusURL: URL,
    observedAtMs: Int64
) -> XHubDoctorOutputCheckResult {
    let strings = HubUIStrings.Settings.Diagnostics.DoctorOutput.self
    let detailLines = [
        "status_source=\(HubDiagnosticsBundleExporter.redactTextForSharing(statusURL.path))",
        "runtime_pid=\(status?.pid ?? 0)",
        "status_schema_version=\(status?.schemaVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")",
    ]

    if runtimeAlive {
        return XHubDoctorOutputCheckResult(
            checkID: "runtime_heartbeat_ok",
            checkKind: "runtime_heartbeat",
            status: .pass,
            severity: .info,
            blocking: false,
            headline: strings.heartbeatOKHeadline,
            message: strings.heartbeatOKMessage,
            nextStep: strings.heartbeatOKNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.doctor,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    return XHubDoctorOutputCheckResult(
        checkID: "runtime_heartbeat_stale",
        checkKind: "runtime_heartbeat",
        status: .fail,
        severity: .critical,
        blocking: true,
        headline: strings.heartbeatStaleHeadline,
        message: strings.heartbeatStaleMessage,
        nextStep: strings.heartbeatStaleNextStep,
        repairDestinationRef: XHubDoctorOutputDestination.diagnostics,
        detailLines: detailLines,
        observedAtMs: observedAtMs
    )
}

private func buildProviderCheck(
    runtimeAlive: Bool,
    providerDiagnoses: [AIRuntimeProviderDiagnosis],
    readyProviders: [String],
    downProviders: [String],
    managedServiceEvidence: [XHubLocalServiceProviderEvidence],
    observedAtMs: Int64
) -> XHubDoctorOutputCheckResult {
    let strings = HubUIStrings.Settings.Diagnostics.DoctorOutput.self
    let providerLines = providerDiagnoses.map { diagnosis in
        "provider=\(diagnosis.provider) state=\(diagnosis.state.rawValue) reason=\(diagnosis.reasonCode.isEmpty ? "none" : diagnosis.reasonCode) runtime_source=\(diagnosis.runtimeSource.isEmpty ? "unknown" : diagnosis.runtimeSource) fallback=\(diagnosis.fallbackUsed ? "1" : "0")"
    }
    let detailLines = [
        "ready_providers=\(readyProviders.isEmpty ? "none" : readyProviders.joined(separator: ","))",
        "provider_count=\(providerDiagnoses.count)",
        "managed_service_provider_count=\(managedServiceEvidence.count)",
        "managed_service_ready_count=\(managedServiceEvidence.filter(\.ready).count)",
    ] + providerLines + managedServiceEvidence.map { XHubLocalServiceDiagnostics.detailLine(for: $0) }

    guard runtimeAlive else {
        return XHubDoctorOutputCheckResult(
            checkID: "provider_readiness_skipped",
            checkKind: "provider_readiness",
            status: .skip,
            severity: .info,
            blocking: false,
            headline: strings.providerReadinessSkippedHeadline,
            message: strings.providerReadinessSkippedMessage,
            nextStep: strings.providerReadinessSkippedNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.diagnostics,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    if readyProviders.isEmpty,
       let primaryServiceIssue = XHubLocalServiceDiagnostics.primaryIssue(in: managedServiceEvidence) {
        return XHubDoctorOutputCheckResult(
            checkID: primaryServiceIssue.reasonCode,
            checkKind: "provider_readiness",
            status: .fail,
            severity: .error,
            blocking: true,
            headline: primaryServiceIssue.headline,
            message: primaryServiceIssue.message,
            nextStep: primaryServiceIssue.nextStep,
            repairDestinationRef: XHubDoctorOutputDestination.diagnostics,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    if readyProviders.isEmpty {
        return XHubDoctorOutputCheckResult(
            checkID: "no_ready_provider",
            checkKind: "provider_readiness",
            status: .fail,
            severity: .error,
            blocking: true,
            headline: strings.noReadyProviderHeadline,
            message: strings.noReadyProviderMessage,
            nextStep: strings.noReadyProviderNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.diagnostics,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    if !downProviders.isEmpty {
        return XHubDoctorOutputCheckResult(
            checkID: "provider_partial_readiness",
            checkKind: "provider_readiness",
            status: .warn,
            severity: .warning,
            blocking: false,
            headline: strings.providerPartialHeadline,
            message: strings.providerPartialMessage,
            nextStep: strings.providerPartialNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.doctor,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    return XHubDoctorOutputCheckResult(
        checkID: "provider_readiness_ok",
        checkKind: "provider_readiness",
        status: .pass,
        severity: .info,
        blocking: false,
        headline: strings.providerReadyHeadline,
        message: strings.providerReadyMessage,
        nextStep: strings.providerReadyNextStep,
        repairDestinationRef: XHubDoctorOutputDestination.doctor,
        detailLines: detailLines,
        observedAtMs: observedAtMs
    )
}

private func buildCapabilityCheck(
    runtimeAlive: Bool,
    blockedCapabilityIDs: [String],
    capabilityDiagnoses: [AIRuntimeLocalCapabilityDiagnosis],
    observedAtMs: Int64
) -> XHubDoctorOutputCheckResult {
    let strings = HubUIStrings.Settings.Diagnostics.DoctorOutput.self
    let capabilityLines = capabilityDiagnoses.map { capability in
        "capability=\(capability.capabilityKey) state=\(capability.state.rawValue) providers=\(capability.providerIDs.isEmpty ? "none" : capability.providerIDs.joined(separator: ",")) detail=\(capability.detail)"
    }
    let detailLines = [
        "blocked_capabilities=\(blockedCapabilityIDs.isEmpty ? "none" : blockedCapabilityIDs.joined(separator: ","))",
    ] + capabilityLines

    guard runtimeAlive else {
        return XHubDoctorOutputCheckResult(
            checkID: "capability_gates_skipped",
            checkKind: "capability_gates",
            status: .skip,
            severity: .info,
            blocking: false,
            headline: strings.capabilitySkippedHeadline,
            message: strings.capabilitySkippedMessage,
            nextStep: strings.capabilitySkippedNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.doctor,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    if !blockedCapabilityIDs.isEmpty {
        return XHubDoctorOutputCheckResult(
            checkID: "blocked_capabilities_present",
            checkKind: "capability_gates",
            status: .warn,
            severity: .warning,
            blocking: false,
            headline: strings.capabilityWarnHeadline,
            message: strings.capabilityWarnMessage,
            nextStep: strings.capabilityWarnNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.doctor,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    return XHubDoctorOutputCheckResult(
        checkID: "capability_gates_clear",
        checkKind: "capability_gates",
        status: .pass,
        severity: .info,
        blocking: false,
        headline: strings.capabilityOKHeadline,
        message: strings.capabilityOKMessage,
        nextStep: strings.capabilityOKNextStep,
        repairDestinationRef: XHubDoctorOutputDestination.doctor,
        detailLines: detailLines,
        observedAtMs: observedAtMs
    )
}

private func buildMonitorCheck(
    runtimeAlive: Bool,
    monitorSnapshot: AIRuntimeMonitorSnapshot?,
    hostMetrics: XHubLocalRuntimeHostMetricsSnapshot?,
    observedAtMs: Int64
) -> XHubDoctorOutputCheckResult {
    let strings = HubUIStrings.Settings.Diagnostics.DoctorOutput.self
    var detailLines: [String] = []
    if let hostMetrics {
        detailLines.append(
            contentsOf: hostMetrics.detailLines.compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        )
    }
    if let monitorSnapshot {
        detailLines.append("monitor_provider_count=\(monitorSnapshot.providers.count)")
        detailLines.append("monitor_active_task_count=\(monitorSnapshot.queue.activeTaskCount)")
        detailLines.append("monitor_queued_task_count=\(monitorSnapshot.queue.queuedTaskCount)")
        detailLines.append("monitor_loaded_instance_count=\(monitorSnapshot.loadedInstances.count)")
        detailLines.append("monitor_last_error_count=\(monitorSnapshot.lastErrors.count)")
        detailLines.append("monitor_recent_bench_result_count=\(monitorSnapshot.recentBenchResults.count)")
        detailLines.append(
            contentsOf: monitorSnapshot.recentBenchResults.prefix(5).map { result in
                monitorRecentBenchDetailLine(result)
            }
        )
        detailLines.append(
            contentsOf: monitorSnapshot.lastErrors.map { error in
                "provider=\(error.provider) code=\(error.code) severity=\(error.severity) message=\(error.message)"
            }
        )
    } else {
        detailLines.append("monitor_snapshot=none")
    }

    guard runtimeAlive else {
        return XHubDoctorOutputCheckResult(
            checkID: "runtime_monitor_skipped",
            checkKind: "runtime_monitor",
            status: .skip,
            severity: .info,
            blocking: false,
            headline: strings.monitorSkippedHeadline,
            message: strings.monitorSkippedMessage,
            nextStep: strings.monitorSkippedNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.diagnostics,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    guard let monitorSnapshot else {
        return XHubDoctorOutputCheckResult(
            checkID: "monitor_snapshot_missing",
            checkKind: "runtime_monitor",
            status: .warn,
            severity: .warning,
            blocking: false,
            headline: strings.monitorMissingHeadline,
            message: strings.monitorMissingMessage,
            nextStep: strings.monitorMissingNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.diagnostics,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    if !monitorSnapshot.lastErrors.isEmpty {
        return XHubDoctorOutputCheckResult(
            checkID: "monitor_errors_present",
            checkKind: "runtime_monitor",
            status: .warn,
            severity: .warning,
            blocking: false,
            headline: strings.monitorErrorsHeadline,
            message: strings.monitorErrorsMessage,
            nextStep: strings.monitorErrorsNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.diagnostics,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    return XHubDoctorOutputCheckResult(
        checkID: "runtime_monitor_ok",
        checkKind: "runtime_monitor",
        status: .pass,
        severity: .info,
        blocking: false,
        headline: strings.monitorOKHeadline,
        message: strings.monitorOKMessage,
        nextStep: strings.monitorOKNextStep,
        repairDestinationRef: XHubDoctorOutputDestination.diagnostics,
        detailLines: detailLines,
        observedAtMs: observedAtMs
    )
}

private func buildChannelRuntimeCheck(
    sourceStatus: String,
    fetchErrors: [String],
    runtimeRows: [HubOperatorChannelProviderRuntimeStatus],
    observedAtMs: Int64
) -> XHubDoctorOutputCheckResult {
    let strings = HubUIStrings.Settings.Diagnostics.DoctorOutput.self
    let normalizedSourceStatus = sourceStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let sortedRows = runtimeRows.sorted {
        $0.provider.localizedCaseInsensitiveCompare($1.provider) == .orderedAscending
    }
    let detailLines = [
        "source_status=\(normalizedSourceStatus.isEmpty ? "unknown" : normalizedSourceStatus)",
        "runtime_provider_count=\(sortedRows.count)",
        "fetch_error_count=\(fetchErrors.count)",
    ] + fetchErrors.map { "fetch_error=\($0)" } + sortedRows.map { row in
        "provider=\(row.provider) runtime_state=\(row.runtimeState) command_entry_ready=\(row.commandEntryReady ? "1" : "0") delivery_ready=\(row.deliveryReady ? "1" : "0") release_blocked=\(row.releaseBlocked ? "1" : "0") require_real_evidence=\(row.requireRealEvidence ? "1" : "0") last_error_code=\(row.lastErrorCode.isEmpty ? "none" : row.lastErrorCode)"
    }

    if normalizedSourceStatus == "unavailable" && sortedRows.isEmpty {
        return XHubDoctorOutputCheckResult(
            checkID: "channel_status_unavailable",
            checkKind: "channel_runtime",
            status: .fail,
            severity: .critical,
            blocking: true,
            headline: strings.channelSourceUnavailableHeadline,
            message: strings.channelSourceUnavailableMessage,
            nextStep: strings.channelSourceUnavailableNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.operatorChannels,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    guard !sortedRows.isEmpty else {
        return XHubDoctorOutputCheckResult(
            checkID: "channel_runtime_missing",
            checkKind: "channel_runtime",
            status: .warn,
            severity: .warning,
            blocking: false,
            headline: strings.channelRuntimeMissingHeadline,
            message: strings.channelRuntimeMissingMessage,
            nextStep: strings.channelRuntimeMissingNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.operatorChannels,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    let failingRows = sortedRows.filter { row in
        !row.commandEntryReady
            || ["disabled", "not_configured", "blocked", "error", "degraded"].contains(row.normalizedRuntimeState)
    }
    if let firstFailure = failingRows.first {
        return XHubDoctorOutputCheckResult(
            checkID: "channel_runtime_not_ready",
            checkKind: "channel_runtime",
            status: .fail,
            severity: .error,
            blocking: true,
            headline: strings.channelRuntimeBlockedHeadline,
            message: strings.channelRuntimeBlockedMessage,
            nextStep: firstFailure.repairHints.first ?? strings.channelRuntimeBlockedNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.operatorChannels,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    let warningRows = sortedRows.filter { row in
        row.releaseBlocked || row.requireRealEvidence || !row.deliveryReady
    }
    if let firstWarning = warningRows.first {
        return XHubDoctorOutputCheckResult(
            checkID: "channel_runtime_partially_ready",
            checkKind: "channel_runtime",
            status: .warn,
            severity: .warning,
            blocking: false,
            headline: strings.channelRuntimeWarnHeadline,
            message: strings.channelRuntimeWarnMessage,
            nextStep: firstWarning.repairHints.first ?? strings.channelRuntimeWarnNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.operatorChannels,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    return XHubDoctorOutputCheckResult(
        checkID: "channel_runtime_ok",
        checkKind: "channel_runtime",
        status: .pass,
        severity: .info,
        blocking: false,
        headline: strings.channelRuntimeOKHeadline,
        message: strings.channelRuntimeOKMessage,
        nextStep: strings.channelRuntimeOKNextStep,
        repairDestinationRef: XHubDoctorOutputDestination.operatorChannels,
        detailLines: detailLines,
        observedAtMs: observedAtMs
    )
}

private func buildChannelDeliveryCheck(
    sourceStatus: String,
    fetchErrors: [String],
    readinessRows: [HubOperatorChannelOnboardingDeliveryReadiness],
    observedAtMs: Int64
) -> XHubDoctorOutputCheckResult {
    let strings = HubUIStrings.Settings.Diagnostics.DoctorOutput.self
    let normalizedSourceStatus = sourceStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let sortedRows = readinessRows.sorted {
        $0.provider.localizedCaseInsensitiveCompare($1.provider) == .orderedAscending
    }
    let detailLines = [
        "source_status=\(normalizedSourceStatus.isEmpty ? "unknown" : normalizedSourceStatus)",
        "delivery_provider_count=\(sortedRows.count)",
        "fetch_error_count=\(fetchErrors.count)",
    ] + fetchErrors.map { "fetch_error=\($0)" } + sortedRows.map { row in
        "provider=\(row.provider) ready=\(row.ready ? "1" : "0") reply_enabled=\(row.replyEnabled ? "1" : "0") credentials_configured=\(row.credentialsConfigured ? "1" : "0") deny_code=\(row.denyCode.isEmpty ? "none" : row.denyCode)"
    }

    if normalizedSourceStatus == "unavailable" && sortedRows.isEmpty {
        return XHubDoctorOutputCheckResult(
            checkID: "channel_delivery_skipped",
            checkKind: "channel_delivery",
            status: .skip,
            severity: .info,
            blocking: false,
            headline: strings.channelDeliverySkippedHeadline,
            message: strings.channelDeliverySkippedMessage,
            nextStep: strings.channelDeliverySkippedNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.operatorChannels,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    guard !sortedRows.isEmpty else {
        return XHubDoctorOutputCheckResult(
            checkID: "channel_delivery_missing",
            checkKind: "channel_delivery",
            status: .warn,
            severity: .warning,
            blocking: false,
            headline: strings.channelDeliveryMissingHeadline,
            message: strings.channelDeliveryMissingMessage,
            nextStep: strings.channelDeliveryMissingNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.operatorChannels,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    let failingRows = sortedRows.filter { !$0.ready }
    if let firstFailure = failingRows.first {
        let remediationHint = firstFailure.remediationHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextStep = firstFailure.repairHints.first
            ?? (remediationHint.isEmpty ? strings.channelDeliveryBlockedNextStep : remediationHint)
        return XHubDoctorOutputCheckResult(
            checkID: "channel_delivery_not_ready",
            checkKind: "channel_delivery",
            status: .fail,
            severity: .error,
            blocking: true,
            headline: strings.channelDeliveryBlockedHeadline,
            message: strings.channelDeliveryBlockedMessage,
            nextStep: nextStep,
            repairDestinationRef: XHubDoctorOutputDestination.operatorChannels,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    let warningRows = sortedRows.filter { !$0.replyEnabled || !$0.credentialsConfigured }
    if !warningRows.isEmpty {
        return XHubDoctorOutputCheckResult(
            checkID: "channel_delivery_partially_ready",
            checkKind: "channel_delivery",
            status: .warn,
            severity: .warning,
            blocking: false,
            headline: strings.channelDeliveryWarnHeadline,
            message: strings.channelDeliveryWarnMessage,
            nextStep: warningRows.first?.repairHints.first ?? strings.channelDeliveryWarnNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.operatorChannels,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    return XHubDoctorOutputCheckResult(
        checkID: "channel_delivery_ok",
        checkKind: "channel_delivery",
        status: .pass,
        severity: .info,
        blocking: false,
        headline: strings.channelDeliveryOKHeadline,
        message: strings.channelDeliveryOKMessage,
        nextStep: strings.channelDeliveryOKNextStep,
        repairDestinationRef: XHubDoctorOutputDestination.operatorChannels,
        detailLines: detailLines,
        observedAtMs: observedAtMs
    )
}

private func buildChannelLiveTestCheck(
    sourceStatus: String,
    fetchErrors: [String],
    liveTestReports: [HubOperatorChannelLiveTestEvidenceReport],
    observedAtMs: Int64
) -> XHubDoctorOutputCheckResult {
    let strings = HubUIStrings.Settings.Diagnostics.DoctorOutput.self
    let normalizedSourceStatus = sourceStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let sortedReports = liveTestReports.sorted {
        $0.provider.localizedCaseInsensitiveCompare($1.provider) == .orderedAscending
    }
    let detailLines = [
        "source_status=\(normalizedSourceStatus.isEmpty ? "unknown" : normalizedSourceStatus)",
        "live_test_report_count=\(sortedReports.count)",
        "fetch_error_count=\(fetchErrors.count)",
    ] + fetchErrors.map { "fetch_error=\($0)" } + sortedReports.map { report in
        let heartbeatVisibilityStatus = report.checks.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "heartbeat_governance_visible"
        })?.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "none"
        return "provider=\(report.provider) derived_status=\(report.derivedStatus) operator_verdict=\(report.operatorVerdict) live_test_success=\(report.liveTestSuccess ? "1" : "0") heartbeat_governance_visible=\(heartbeatVisibilityStatus.isEmpty ? "none" : heartbeatVisibilityStatus) required_next_step=\(report.requiredNextStep.isEmpty ? "none" : report.requiredNextStep)"
    }

    guard !sortedReports.isEmpty else {
        return XHubDoctorOutputCheckResult(
            checkID: "channel_live_test_missing",
            checkKind: "channel_live_test",
            status: .warn,
            severity: .warning,
            blocking: false,
            headline: strings.channelLiveTestMissingHeadline,
            message: strings.channelLiveTestMissingMessage,
            nextStep: strings.channelLiveTestMissingNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.operatorChannels,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    if let attentionReport = sortedReports.first(where: {
        $0.derivedStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "attention"
    }) {
        let heartbeatVisibilityMissing = attentionReport.checks.contains(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "heartbeat_governance_visible"
                && $0.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fail"
        })
        return XHubDoctorOutputCheckResult(
            checkID: heartbeatVisibilityMissing
                ? "channel_live_test_heartbeat_visibility_missing"
                : "channel_live_test_attention",
            checkKind: "channel_live_test",
            status: .warn,
            severity: .warning,
            blocking: false,
            headline: heartbeatVisibilityMissing
                ? strings.channelLiveTestHeartbeatVisibilityMissingHeadline
                : strings.channelLiveTestAttentionHeadline,
            message: heartbeatVisibilityMissing
                ? strings.channelLiveTestHeartbeatVisibilityMissingMessage
                : strings.channelLiveTestAttentionMessage,
            nextStep: attentionReport.requiredNextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (heartbeatVisibilityMissing
                    ? strings.channelLiveTestHeartbeatVisibilityMissingNextStep
                    : strings.channelLiveTestAttentionNextStep)
                : attentionReport.requiredNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.operatorChannels,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    if let pendingReport = sortedReports.first(where: {
        $0.derivedStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "pending"
    }) {
        return XHubDoctorOutputCheckResult(
            checkID: "channel_live_test_pending",
            checkKind: "channel_live_test",
            status: .warn,
            severity: .warning,
            blocking: false,
            headline: strings.channelLiveTestPendingHeadline,
            message: strings.channelLiveTestPendingMessage,
            nextStep: pendingReport.requiredNextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? strings.channelLiveTestPendingNextStep
                : pendingReport.requiredNextStep,
            repairDestinationRef: XHubDoctorOutputDestination.operatorChannels,
            detailLines: detailLines,
            observedAtMs: observedAtMs
        )
    }

    return XHubDoctorOutputCheckResult(
        checkID: "channel_live_test_ok",
        checkKind: "channel_live_test",
        status: .pass,
        severity: .info,
        blocking: false,
        headline: strings.channelLiveTestOKHeadline,
        message: strings.channelLiveTestOKMessage,
        nextStep: strings.channelLiveTestOKNextStep,
        repairDestinationRef: XHubDoctorOutputDestination.operatorChannels,
        detailLines: detailLines,
        observedAtMs: observedAtMs
    )
}

private func monitorRecentBenchDetailLine(_ result: ModelBenchResult) -> String {
    let summary = result.routeTraceSummary
    let provider = result.providerID.isEmpty ? "unknown" : result.providerID
    let taskKind = {
        let traceTaskKind = summary?.selectedTaskKind.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !traceTaskKind.isEmpty {
            return traceTaskKind
        }
        let benchTaskKind = result.taskKind.trimmingCharacters(in: .whitespacesAndNewlines)
        return benchTaskKind.isEmpty ? "unknown" : benchTaskKind
    }()
    let executionPath = {
        let value = summary?.executionPath.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "unknown" : value
    }()
    let fallbackMode = {
        let routeFallback = summary?.fallbackMode.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !routeFallback.isEmpty {
            return routeFallback
        }
        let benchFallback = result.fallbackMode.trimmingCharacters(in: .whitespacesAndNewlines)
        return benchFallback.isEmpty ? "none" : benchFallback
    }()
    let blockedReason = {
        let value = summary?.blockedReasonCode.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "none" : value
    }()
    let imageCount = max(summary?.imageCount ?? 0, summary?.resolvedImageCount ?? 0)
    return "provider=\(provider) task_kind=\(taskKind) execution_path=\(executionPath) fallback_mode=\(fallbackMode) image_count=\(imageCount) blocked_reason=\(blockedReason) result_ok=\(result.ok ? "1" : "0")"
}

private func normalizedOverallState(for checks: [XHubDoctorOutputCheckResult]) -> XHubDoctorOverallState {
    if checks.contains(where: { $0.status == .fail && $0.blocking }) {
        return .blocked
    }
    if checks.contains(where: { $0.status == .warn }) {
        return .degraded
    }
    return .ready
}

private func summaryHeadline(
    overallState: XHubDoctorOverallState,
    readyForFirstTask: Bool,
    checks: [XHubDoctorOutputCheckResult]
) -> String {
    let strings = HubUIStrings.Settings.Diagnostics.DoctorOutput.self
    switch overallState {
    case .ready:
        return readyForFirstTask ? strings.summaryReadyFirstTask : strings.summaryReady
    case .degraded:
        return readyForFirstTask
            ? strings.summaryDegradedReady
            : strings.summaryDegraded
    case .blocked:
        if let fail = checks.first(where: { $0.status == .fail }) {
            return fail.headline
        }
        return strings.summaryBlocked
    case .inProgress:
        return strings.summaryRecovering
    case .notSupported:
        return strings.summaryNotSupported
    }
}

private func channelOnboardingSummaryHeadline(
    overallState: XHubDoctorOverallState,
    checks: [XHubDoctorOutputCheckResult]
) -> String {
    let strings = HubUIStrings.Settings.Diagnostics.DoctorOutput.self
    switch overallState {
    case .ready:
        return strings.channelSummaryReady
    case .degraded:
        return strings.channelSummaryDegraded
    case .blocked:
        return checks.first(where: { $0.status == .fail })?.headline ?? strings.channelSummaryBlocked
    case .inProgress:
        return strings.summaryRecovering
    case .notSupported:
        return strings.summaryNotSupported
    }
}

private func primaryIssue(
    in checks: [XHubDoctorOutputCheckResult]
) -> (code: String, issue: String?) {
    if let failure = checks.first(where: { $0.status == .fail }) {
        return (failure.checkID, failure.checkKind)
    }
    if let warning = checks.first(where: { $0.status == .warn }) {
        return (warning.checkID, warning.checkKind)
    }
    return ("", nil)
}

private func resolvedSourceSchemaVersion(status: AIRuntimeStatus?) -> String {
    let token = status?.schemaVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return token.isEmpty ? "xhub.local_runtime_status.v2" : token
}

private func normalizedNextSteps(
    for checks: [XHubDoctorOutputCheckResult],
    readyForFirstTask: Bool
) -> [XHubDoctorOutputNextStep] {
    let strings = HubUIStrings.Settings.Diagnostics.DoctorOutput.self
    var steps: [XHubDoctorOutputNextStep] = []

    if let blockingFailure = checks.first(where: { $0.status == .fail && $0.blocking }) {
        let repairInstruction = blockingFailure.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        let repairDestination = blockingFailure.repairDestinationRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let runtimeScopedFailure = blockingFailure.checkKind == "provider_readiness"
            && blockingFailure.checkID.hasPrefix("xhub_local_service_")
        steps.append(
            XHubDoctorOutputNextStep(
                stepID: "repair_runtime",
                kind: .repairRuntime,
                label: runtimeScopedFailure ? strings.repairLocalService : strings.repairRuntime,
                owner: .user,
                blocking: true,
                destinationRef: repairDestination.isEmpty ? XHubDoctorOutputDestination.diagnostics : repairDestination,
                instruction: repairInstruction.isEmpty
                    ? strings.defaultRepairInstruction
                    : repairInstruction
            )
        )
    }

    if checks.contains(where: { $0.checkKind == "capability_gates" && $0.status == .warn }) ||
        checks.contains(where: { $0.checkKind == "runtime_monitor" && $0.status == .warn }) {
        steps.append(
            XHubDoctorOutputNextStep(
                stepID: "inspect_diagnostics",
                kind: .inspectDiagnostics,
                label: strings.inspectDiagnostics,
                owner: .user,
                blocking: false,
                destinationRef: XHubDoctorOutputDestination.diagnostics,
                instruction: strings.inspectDiagnosticsInstruction
            )
        )
    }

    if readyForFirstTask && !checks.contains(where: { $0.status == .fail && $0.blocking }) {
        steps.append(
            XHubDoctorOutputNextStep(
                stepID: "start_first_task",
                kind: .startFirstTask,
                label: strings.startFirstTask,
                owner: .user,
                blocking: false,
                destinationRef: XHubDoctorOutputDestination.doctor,
                instruction: strings.startFirstTaskInstruction
            )
        )
    }

    return steps
}

private func channelOnboardingNextSteps(
    for checks: [XHubDoctorOutputCheckResult]
) -> [XHubDoctorOutputNextStep] {
    let strings = HubUIStrings.Settings.Diagnostics.DoctorOutput.self
    var steps: [XHubDoctorOutputNextStep] = []

    if let blockingFailure = checks.first(where: { $0.status == .fail && $0.blocking }) {
        steps.append(
            XHubDoctorOutputNextStep(
                stepID: "open_operator_channel_repair_surface",
                kind: .openRepairSurface,
                label: strings.openOperatorChannelsRepairSurface,
                owner: .user,
                blocking: true,
                destinationRef: XHubDoctorOutputDestination.operatorChannels,
                instruction: blockingFailure.nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? strings.channelDefaultRepairInstruction
                    : blockingFailure.nextStep
            )
        )
    }

    if checks.contains(where: { $0.status == .warn }) {
        steps.append(
            XHubDoctorOutputNextStep(
                stepID: "inspect_operator_channel_diagnostics",
                kind: .inspectDiagnostics,
                label: strings.inspectDiagnostics,
                owner: .user,
                blocking: false,
                destinationRef: XHubDoctorOutputDestination.diagnostics,
                instruction: strings.channelInspectDiagnosticsInstruction
            )
        )
    }

    if steps.isEmpty {
        steps.append(
            XHubDoctorOutputNextStep(
                stepID: "review_operator_channels",
                kind: .openRepairSurface,
                label: strings.reviewOperatorChannels,
                owner: .user,
                blocking: false,
                destinationRef: XHubDoctorOutputDestination.operatorChannels,
                instruction: strings.channelReviewOperatorChannelsInstruction
            )
        )
    }

    return steps
}

private func normalizedConsumedContracts(status: AIRuntimeStatus?) -> [String] {
    var contracts = ["xhub.doctor_output_contract.v1"]
    let statusSchema = status?.schemaVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !statusSchema.isEmpty {
        contracts.append(statusSchema)
    } else {
        contracts.append("xhub.local_runtime_status.v2")
    }
    let monitorSchema = status?.monitorSnapshot?.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !monitorSchema.isEmpty {
        contracts.append(monitorSchema)
    }
    return Array(Set(contracts)).sorted()
}

private func channelOnboardingConsumedContracts(
    liveTestReports: [HubOperatorChannelLiveTestEvidenceReport]
) -> [String] {
    let liveTestSchemas = liveTestReports
        .map { $0.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return Array(Set(["xhub.doctor_output_contract.v1"] + liveTestSchemas)).sorted()
}
