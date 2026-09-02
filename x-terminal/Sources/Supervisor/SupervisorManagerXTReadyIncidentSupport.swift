import Foundation

extension SupervisorManager {
    private static let xtReadyRequiredIncidentCodes: [String] = [
        LaneBlockedReason.grantPending.rawValue,
        LaneBlockedReason.awaitingInstruction.rawValue,
        LaneBlockedReason.runtimeError.rawValue,
    ]

    private static let xtReadyDefaultInjectSpecs: [XTReadyIncidentInjectSpec] = [
        XTReadyIncidentInjectSpec(
            laneID: "lane-2",
            incidentCode: LaneBlockedReason.grantPending.rawValue
        ),
        XTReadyIncidentInjectSpec(
            laneID: "lane-3",
            incidentCode: LaneBlockedReason.awaitingInstruction.rawValue
        ),
        XTReadyIncidentInjectSpec(
            laneID: "lane-4",
            incidentCode: LaneBlockedReason.runtimeError.rawValue
        ),
    ]

    private static let xtReadyExpectedEventTypes: [String: String] = [
        LaneBlockedReason.grantPending.rawValue: "supervisor.incident.grant_pending.handled",
        LaneBlockedReason.awaitingInstruction.rawValue: "supervisor.incident.awaiting_instruction.handled",
        LaneBlockedReason.runtimeError.rawValue: "supervisor.incident.runtime_error.handled",
    ]

    private static let xtReadyMaxTakeoverLatencyMs: Int64 = 2_000

    func parseXTReadyIncidentInjectSpecs(from command: String) -> [XTReadyIncidentInjectSpec] {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()

        let prefixes = ["/xt-ready incidents inject", "xt-ready incidents inject"]
        var args = ""
        for prefix in prefixes {
            if lowered.hasPrefix(prefix) {
                args = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        if args.isEmpty {
            return Self.xtReadyDefaultInjectSpecs
        }

        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))
        let tokens = args
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var specs: [XTReadyIncidentInjectSpec] = []
        for token in tokens {
            let normalized = token.lowercased()
            if normalized == "default" {
                specs.append(contentsOf: Self.xtReadyDefaultInjectSpecs)
                continue
            }

            let pair = normalized.replacingOccurrences(of: "=", with: ":")
            let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }

            let laneID = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let code = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !laneID.isEmpty, !code.isEmpty else { continue }
            specs.append(XTReadyIncidentInjectSpec(laneID: laneID, incidentCode: code))
        }

        if specs.isEmpty {
            return Self.xtReadyDefaultInjectSpecs
        }
        return specs
    }

    static func buildXTReadyIncidentEvents(
        from incidents: [SupervisorLaneIncident],
        limit: Int = 120
    ) -> [XTReadyIncidentEvent] {
        let required = Set(xtReadyRequiredIncidentCodes)
        return incidents
            .filter { required.contains($0.incidentCode) && $0.status == .handled }
            .sorted { lhs, rhs in
                let lt = lhs.handledAtMs ?? lhs.detectedAtMs
                let rt = rhs.handledAtMs ?? rhs.detectedAtMs
                if lt != rt {
                    return lt < rt
                }
                if lhs.incidentCode != rhs.incidentCode {
                    return lhs.incidentCode < rhs.incidentCode
                }
                return lhs.laneID < rhs.laneID
            }
            .suffix(max(1, limit))
            .map { incident in
                XTReadyIncidentEvent(
                    eventType: incident.eventType,
                    incidentCode: incident.incidentCode,
                    laneID: incident.laneID,
                    detectedAtMs: incident.detectedAtMs,
                    handledAtMs: incident.handledAtMs ?? incident.detectedAtMs,
                    denyCode: incident.denyCode,
                    auditEventType: "supervisor.incident.handled",
                    auditRef: incident.auditRef,
                    takeoverLatencyMs: incident.takeoverLatencyMs
                )
            }
    }

    static func missingXTReadyIncidentCodes(
        in events: [XTReadyIncidentEvent]
    ) -> [String] {
        let existing = Set(events.map(\.incidentCode))
        return xtReadyRequiredIncidentCodes.filter { !existing.contains($0) }
    }

    static func evaluateXTReadyIncidentReadiness(
        events: [XTReadyIncidentEvent]
    ) -> XTReadyIncidentReadiness {
        var issues: [String] = []

        for incidentCode in xtReadyRequiredIncidentCodes {
            guard let selected = selectBestXTReadyIncidentEvent(
                incidentCode: incidentCode,
                events: events
            ) else {
                issues.append("\(incidentCode):missing_incident")
                continue
            }

            let expectedEventType = xtReadyExpectedEventTypes[incidentCode] ?? ""
            if !expectedEventType.isEmpty, selected.eventType != expectedEventType {
                issues.append("\(incidentCode):event_type_mismatch")
            }
            if selected.denyCode != incidentCode {
                issues.append("\(incidentCode):deny_code_mismatch")
            }
            if selected.auditRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(incidentCode):audit_ref_missing")
            }
            guard let latency = resolvedTakeoverLatencyMs(for: selected) else {
                issues.append("\(incidentCode):takeover_latency_missing")
                continue
            }
            if latency > xtReadyMaxTakeoverLatencyMs {
                issues.append("\(incidentCode):takeover_latency_exceeded")
            }
        }

        return XTReadyIncidentReadiness(
            ready: issues.isEmpty,
            issues: issues
        )
    }

    func appendXTReadyIncidentDiagnosticContextLines(
        _ snapshot: XTReadyIncidentExportSnapshot,
        to lines: inout [String]
    ) {
        if let pairedRouteSetSnapshot = snapshot.pairedRouteSetSnapshot {
            let summaryLine = pairedRouteSetSnapshot.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summaryLine.isEmpty {
                lines.append("paired_route_status：\(summaryLine)")
            }
        }
        if let pairedRouteSnapshot = snapshot.pairedRouteSnapshot {
            let routeSummary = Self.xtReadyPairedRouteSummaryLine(pairedRouteSnapshot)
            if !routeSummary.isEmpty {
                lines.append("paired_route：\(routeSummary)")
            }
            lines.append("paired_remote_entry：\(pairedRouteSnapshot.remoteEntrySummaryLine)")
        }
        if let connectivityIncident = snapshot.connectivityIncidentSnapshot {
            let statusLine = Self.xtReadyConnectivityIncidentStatusLine(connectivityIncident)
            if !statusLine.isEmpty {
                lines.append("hub_connectivity_incident：\(statusLine)")
            }
            let summaryLine = connectivityIncident.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summaryLine.isEmpty {
                lines.append("hub_connectivity_incident_summary：\(summaryLine)")
            }
            if let pathLine = Self.xtReadyConnectivityIncidentPathLine(connectivityIncident) {
                lines.append("hub_connectivity_incident_path：\(pathLine)")
            }
        }
        if let connectivityIncidentHistory = snapshot.connectivityIncidentHistory,
           let historyLine = Self.xtReadyConnectivityIncidentHistoryLine(connectivityIncidentHistory) {
            lines.append("hub_connectivity_incident_history：\(historyLine)")
        }
        if let connectivityRepairLedger = snapshot.connectivityRepairLedger,
           let statusLine = Self.xtReadyConnectivityRepairStatusLine(connectivityRepairLedger) {
            lines.append("hub_connectivity_repair：\(statusLine)")
            if let detailLine = Self.xtReadyConnectivityRepairDetailLine(connectivityRepairLedger) {
                lines.append("hub_connectivity_repair_detail：\(detailLine)")
            }
        }
        if let freshPairReconnectSmoke = snapshot.freshPairReconnectSmokeSnapshot {
            lines.append("fresh_pair_reconnect_smoke：\(freshPairReconnectSmoke.status) · \(freshPairReconnectSmoke.source) · route=\(freshPairReconnectSmoke.route)")
            if let reasonCode = freshPairReconnectSmoke.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reasonCode.isEmpty {
                lines.append("fresh_pair_reconnect_smoke_reason：\(reasonCode)")
            }
            let summary = freshPairReconnectSmoke.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                lines.append("fresh_pair_reconnect_smoke_summary：\(summary)")
            }
        }
        if let firstPairCompletionProof = snapshot.firstPairCompletionProofSnapshot {
            lines.append(
                "first_pair_completion_proof：\(firstPairCompletionProof.readiness) · remote_shadow=\(firstPairCompletionProof.remoteShadowSmokeStatus)"
            )
            if let source = firstPairCompletionProof.remoteShadowSmokeSource?.trimmingCharacters(in: .whitespacesAndNewlines),
               !source.isEmpty {
                lines.append("first_pair_completion_proof_source：\(source)")
            }
            if let route = firstPairCompletionProof.remoteShadowRoute?.trimmingCharacters(in: .whitespacesAndNewlines),
               !route.isEmpty {
                lines.append("first_pair_completion_proof_route：\(route)")
            }
            if let reasonCode = firstPairCompletionProof.remoteShadowReasonCode?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reasonCode.isEmpty {
                lines.append("first_pair_completion_proof_reason：\(reasonCode)")
            }
            let summary = firstPairCompletionProof.remoteShadowSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? firstPairCompletionProof.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                lines.append("first_pair_completion_proof_summary：\(summary)")
            }
        }
        if let hubRuntime = snapshot.hubRuntimeDiagnosis {
            let hubState = hubRuntime.failureCode.isEmpty
                ? hubRuntime.overallState
                : "\(hubRuntime.overallState) · \(hubRuntime.failureCode)"
            lines.append("hub_runtime：\(hubState)")
            if !hubRuntime.headline.isEmpty,
               hubRuntime.overallState != XHubDoctorOverallState.ready.rawValue {
                lines.append("hub_runtime_issue：\(hubRuntime.headline)")
            }
            let loadConfigSummary = hubRuntime.loadConfigSummaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !loadConfigSummary.isEmpty {
                lines.append("hub_runtime_load_config：\(loadConfigSummary)")
            }
            let renderableDetailLines = hubRuntime.renderableDetailLines(limit: 2)
            if !renderableDetailLines.isEmpty {
                lines.append("hub_runtime_detail：\(renderableDetailLines.joined(separator: " || "))")
            }
            if !hubRuntime.nextStep.isEmpty,
               hubRuntime.overallState != XHubDoctorOverallState.ready.rawValue {
                lines.append("hub_runtime_next：\(hubRuntime.nextStep)")
            }
            if !hubRuntime.actionCategory.isEmpty,
               hubRuntime.overallState != XHubDoctorOverallState.ready.rawValue {
                lines.append("hub_runtime_action_category：\(hubRuntime.actionCategory)")
            }
            if !hubRuntime.installHint.isEmpty,
               hubRuntime.overallState != XHubDoctorOverallState.ready.rawValue {
                lines.append("hub_runtime_install_hint：\(hubRuntime.installHint)")
            }
            if !hubRuntime.recommendedAction.isEmpty,
               hubRuntime.overallState != XHubDoctorOverallState.ready.rawValue {
                lines.append("hub_runtime_recommended_action：\(hubRuntime.recommendedAction)")
            }
            if !hubRuntime.supportFAQSummary.isEmpty,
               hubRuntime.overallState != XHubDoctorOverallState.ready.rawValue {
                lines.append("hub_runtime_support_faq：\(hubRuntime.supportFAQSummary)")
            }
        }
        if let supervisorVoice = snapshot.supervisorVoiceDiagnosis {
            lines.append("supervisor_voice：\(supervisorVoice.status) · \(supervisorVoice.headline)")
            lines.append("supervisor_voice_freshness：\(supervisorVoice.isStale() ? "stale" : "fresh") · \(supervisorVoice.freshnessSummary())")
            if !supervisorVoice.message.isEmpty {
                lines.append("supervisor_voice_detail：\(supervisorVoice.message)")
            }
            let evidenceLines = supervisorVoice.renderableDetailLines(limit: 2)
            if !evidenceLines.isEmpty {
                lines.append("supervisor_voice_evidence：\(evidenceLines.joined(separator: " || "))")
            }
            if !supervisorVoice.nextStep.isEmpty {
                lines.append("supervisor_voice_next：\(supervisorVoice.nextStep)")
            }
        }
    }

    func appendXTReadyIncidentIssueLines(
        _ snapshot: XTReadyIncidentExportSnapshot,
        to lines: inout [String]
    ) {
        if snapshot.memoryAssemblyIssues.isEmpty {
            lines.append("memory_assembly_issues：none")
        } else {
            lines.append("memory_assembly_issues：\(snapshot.memoryAssemblyIssues.joined(separator: ","))")
        }
        if snapshot.memoryAssemblyDetailLines.isEmpty {
            lines.append("memory_assembly_detail：none")
        } else {
            lines.append("memory_assembly_detail：\(snapshot.memoryAssemblyDetailLines.prefix(2).joined(separator: " || "))")
        }
        if snapshot.strictE2EIssues.isEmpty {
            lines.append("strict_e2e_issues：none")
        } else {
            lines.append("strict_e2e_issues：\(snapshot.strictE2EIssues.joined(separator: ","))")
        }
    }

    private static func xtReadyPairedRouteSummaryLine(
        _ snapshot: XHubDoctorOutputRouteSnapshot
    ) -> String {
        var parts = [
            snapshot.routeLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            snapshot.transportMode.trimmingCharacters(in: .whitespacesAndNewlines)
        ].filter { !$0.isEmpty }
        if let host = snapshot.normalizedInternetHost {
            parts.append("host=\(host)")
        }
        return parts.joined(separator: " · ")
    }

    private static func xtReadyConnectivityIncidentStatusLine(
        _ snapshot: XHubDoctorOutputConnectivityIncidentSnapshot
    ) -> String {
        var parts = [
            snapshot.incidentState.trimmingCharacters(in: .whitespacesAndNewlines),
            snapshot.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines),
            "trigger=\(snapshot.trigger.trimmingCharacters(in: .whitespacesAndNewlines))"
        ].filter { !$0.isEmpty }
        if let readiness = snapshot.pairedRouteReadiness?.trimmingCharacters(in: .whitespacesAndNewlines),
           !readiness.isEmpty {
            parts.append("paired=\(readiness)")
        }
        if let host = snapshot.stableRemoteRouteHost?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty {
            parts.append("host=\(host)")
        }
        return parts.joined(separator: " · ")
    }

    private static func xtReadyConnectivityIncidentPathLine(
        _ snapshot: XHubDoctorOutputConnectivityIncidentSnapshot
    ) -> String? {
        guard let path = snapshot.currentPath else { return nil }
        return [
            "status=\(path.statusKey)",
            "wifi=\(path.usesWiFi ? "1" : "0")",
            "wired=\(path.usesWiredEthernet ? "1" : "0")",
            "cellular=\(path.usesCellular ? "1" : "0")",
            "expensive=\(path.isExpensive ? "1" : "0")",
            "constrained=\(path.isConstrained ? "1" : "0")"
        ].joined(separator: " ")
    }

    private static func xtReadyConnectivityIncidentHistoryLine(
        _ history: XHubDoctorOutputConnectivityIncidentHistoryReport
    ) -> String? {
        let recentEntries = Array(history.entries.suffix(3))
        guard !recentEntries.isEmpty else { return nil }
        let trail = recentEntries.map { entry in
            let state = entry.incidentState.trimmingCharacters(in: .whitespacesAndNewlines)
            let reason = entry.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reason.isEmpty else { return state }
            return "\(state)(\(reason))"
        }.joined(separator: " -> ")
        guard !trail.isEmpty else { return nil }
        return "recent=\(history.entries.count) · \(trail)"
    }

    private static func xtReadyConnectivityRepairStatusLine(
        _ ledger: XTConnectivityRepairLedgerSnapshot
    ) -> String? {
        guard let summary = XTConnectivityRepairLedgerStore.summary(ledger) else {
            return nil
        }
        return summary.statusLine
    }

    private static func xtReadyConnectivityRepairDetailLine(
        _ ledger: XTConnectivityRepairLedgerSnapshot
    ) -> String? {
        XTConnectivityRepairLedgerStore.summary(ledger)?.detailLine
    }

    private static func selectBestXTReadyIncidentEvent(
        incidentCode: String,
        events: [XTReadyIncidentEvent]
    ) -> XTReadyIncidentEvent? {
        let expectedEventType = xtReadyExpectedEventTypes[incidentCode] ?? ""
        let candidates = events.filter { $0.incidentCode == incidentCode }
        guard !candidates.isEmpty else { return nil }
        return candidates.max { lhs, rhs in
            let lScore = scoreXTReadyIncidentEvent(lhs, incidentCode: incidentCode, expectedEventType: expectedEventType)
            let rScore = scoreXTReadyIncidentEvent(rhs, incidentCode: incidentCode, expectedEventType: expectedEventType)
            if lScore != rScore {
                return lScore < rScore
            }
            if lhs.handledAtMs != rhs.handledAtMs {
                return lhs.handledAtMs < rhs.handledAtMs
            }
            return lhs.detectedAtMs < rhs.detectedAtMs
        }
    }

    private static func scoreXTReadyIncidentEvent(
        _ event: XTReadyIncidentEvent,
        incidentCode: String,
        expectedEventType: String
    ) -> Int {
        var score = 0
        if event.incidentCode == incidentCode { score += 2 }
        if event.denyCode == incidentCode { score += 2 }
        if !expectedEventType.isEmpty, event.eventType == expectedEventType { score += 2 }
        if !event.auditRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 2 }
        if let latency = resolvedTakeoverLatencyMs(for: event) {
            score += 1
            if latency <= xtReadyMaxTakeoverLatencyMs {
                score += 1
            }
        }
        return score
    }

    private static func resolvedTakeoverLatencyMs(
        for event: XTReadyIncidentEvent
    ) -> Int64? {
        if let direct = event.takeoverLatencyMs, direct >= 0 {
            return direct
        }
        if event.handledAtMs >= event.detectedAtMs {
            return event.handledAtMs - event.detectedAtMs
        }
        return nil
    }

    func autoExportXTReadyIncidentEventsIfNeeded() {
        guard isXTReadyIncidentAutoExportEnabled else {
            xtReadyIncidentAutoExportTask?.cancel()
            xtReadyIncidentAutoExportTask = nil
            xtReadyIncidentEventsAutoExportStatus = "disabled"
            return
        }

        let now = Date().timeIntervalSince1970
        guard now - lastXTReadyIncidentAutoExportAt >= xtReadyIncidentAutoExportMinIntervalSec else {
            return
        }
        lastXTReadyIncidentAutoExportAt = now

        xtReadyIncidentAutoExportTask?.cancel()
        xtReadyIncidentAutoExportTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            _ = self.exportXTReadyIncidentEventsReport()
            if !Task.isCancelled {
                self.xtReadyIncidentAutoExportTask = nil
            }
        }
    }

    private var isXTReadyIncidentAutoExportEnabled: Bool {
        let raw = (ProcessInfo.processInfo.environment["XTERMINAL_AUTO_EXPORT_XT_READY_INCIDENT_EVENTS"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if raw.isEmpty {
            return true
        }
        return !["0", "false", "off", "no", "n"].contains(raw)
    }

    static func evaluateSupervisorMemoryAssemblyReadiness(
        snapshot: SupervisorMemoryAssemblySnapshot?
    ) -> SupervisorMemoryAssemblyReadiness {
        SupervisorMemoryAssemblyDiagnostics.evaluate(
            snapshot: snapshot,
            canonicalSyncSnapshot: HubIPCClient.canonicalMemorySyncStatusSnapshot(limit: 120),
            rustGatewayShadowCompare: HubIPCClient.rustMemoryGatewayShadowCompareStatus()
        )
    }

    private static func xtReadyStrictIssueCodes(
        incidentReadiness: XTReadyIncidentReadiness,
        memoryReadiness: SupervisorMemoryAssemblyReadiness,
        hubRuntimeDiagnosis: XTHubRuntimeDiagnosisSnapshot? = nil
    ) -> [String] {
        var issues = incidentReadiness.issues + memoryReadiness.issueCodes.map { "memory:\($0)" }
        if let hubIssue = hubRuntimeDiagnosis?.strictIssueCode {
            issues.append("hub_runtime:\(hubIssue)")
        }
        return issues
    }

    private static func xtReadyHubRuntimeDiagnosisSnapshot(
        baseDir: URL = HubPaths.baseDir()
    ) -> XTHubRuntimeDiagnosisSnapshot? {
        let report = XHubDoctorOutputStore.loadHubReport(baseDir: baseDir)
        let localServiceSnapshot = XHubDoctorOutputStore.loadHubLocalServiceSnapshot(baseDir: baseDir)
        let localRuntimeMonitorSnapshot = XHubDoctorOutputStore.loadHubLocalRuntimeMonitorSnapshot(baseDir: baseDir)
        let recoveryGuidance = XHubDoctorOutputStore.loadHubLocalServiceRecoveryGuidance(baseDir: baseDir)

        let reportDiagnosis = report.flatMap { xtReadyHubRuntimeDiagnosisSnapshot(from: $0) }
        let snapshotDiagnosis = localServiceSnapshot.flatMap { xtReadyHubRuntimeDiagnosisSnapshot(from: $0) }
        let guidanceDiagnosis = recoveryGuidance.flatMap { xtReadyHubRuntimeDiagnosisSnapshot(from: $0) }

        let baseDiagnosis: XTHubRuntimeDiagnosisSnapshot?
        if let report, let localServiceSnapshot,
           localServiceSnapshot.generatedAtMs > report.generatedAtMs {
            baseDiagnosis = snapshotDiagnosis ?? reportDiagnosis
        } else {
            baseDiagnosis = reportDiagnosis ?? snapshotDiagnosis
        }
        let diagnosis = xtReadyMergedHubRuntimeDiagnosis(baseDiagnosis, guidance: guidanceDiagnosis)
        return xtReadyMergeHubRuntimeMonitorDetails(
            diagnosis,
            monitor: localRuntimeMonitorSnapshot
        )
    }

    static func xtReadySupervisorVoiceDiagnosisSnapshot(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> XTSupervisorVoiceDiagnosisSnapshot? {
        let reportURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: workspaceRoot)
        guard let report = XHubDoctorOutputStore.loadReport(from: reportURL) else {
            return nil
        }
        return xtReadySupervisorVoiceDiagnosisSnapshot(from: report)
    }

    private static func xtReadyFreshPairReconnectSmokeSnapshot(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> XTFreshPairReconnectSmokeDiagnosisSnapshot? {
        let reportURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: workspaceRoot)
        guard let report = XHubDoctorOutputStore.loadReport(from: reportURL) else {
            return nil
        }
        return xtReadyFreshPairReconnectSmokeSnapshot(from: report)
    }

    private static func xtReadyFirstPairCompletionProofSnapshot(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> XTFirstPairCompletionProofDiagnosisSnapshot? {
        let reportURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: workspaceRoot)
        guard let report = XHubDoctorOutputStore.loadReport(from: reportURL) else {
            return nil
        }
        return xtReadyFirstPairCompletionProofSnapshot(from: report)
    }

    private static func xtReadyPairedRouteSnapshot(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> XHubDoctorOutputRouteSnapshot? {
        let reportURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: workspaceRoot)
        guard let report = XHubDoctorOutputStore.loadReport(from: reportURL) else {
            return nil
        }
        return report.routeSnapshot
    }

    private static func xtReadyPairedRouteSetSnapshot(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> XHubDoctorOutputPairedRouteSetSnapshot? {
        let reportURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: workspaceRoot)
        guard let report = XHubDoctorOutputStore.loadReport(from: reportURL) else {
            return nil
        }
        return report.pairedRouteSetSnapshot
    }

    private static func xtReadySupervisorVoiceDiagnosisSnapshot(
        from report: XHubDoctorOutputReport
    ) -> XTSupervisorVoiceDiagnosisSnapshot? {
        guard let primaryCheck = xtReadySupervisorVoicePrimaryCheck(in: report) else {
            return nil
        }

        return XTSupervisorVoiceDiagnosisSnapshot(
            status: primaryCheck.status.rawValue,
            headline: primaryCheck.headline.trimmingCharacters(in: .whitespacesAndNewlines),
            message: primaryCheck.message.trimmingCharacters(in: .whitespacesAndNewlines),
            detailLines: primaryCheck.detailLines,
            nextStep: primaryCheck.nextStep.trimmingCharacters(in: .whitespacesAndNewlines),
            repairDestinationRef: primaryCheck.repairDestinationRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            actionURL: {
                let repairRef = primaryCheck.repairDestinationRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard let destination = UITroubleshootDestination(rawValue: repairRef) else { return nil }
                let detail = [
                    primaryCheck.message.trimmingCharacters(in: .whitespacesAndNewlines),
                    primaryCheck.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
                ]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                return troubleshootActionURL(
                    repairEntry: destination,
                    headline: primaryCheck.headline,
                    detail: detail,
                    detailLines: primaryCheck.detailLines
                )
            }(),
            generatedAtMs: primaryCheck.observedAtMs > 0 ? primaryCheck.observedAtMs : report.generatedAtMs
        )
    }

    private static func xtReadyFreshPairReconnectSmokeSnapshot(
        from report: XHubDoctorOutputReport
    ) -> XTFreshPairReconnectSmokeDiagnosisSnapshot? {
        let primaryCheck = report.checks.first { check in
            check.checkID == XTUnifiedDoctorSectionKind.hubReachability.rawValue
        } ?? report.checks.first { check in
            check.freshPairReconnectSmokeSnapshot != nil
        }
        guard let primaryCheck else {
            return nil
        }

        if let structured = primaryCheck.freshPairReconnectSmokeSnapshot {
            return XTFreshPairReconnectSmokeDiagnosisSnapshot(structured)
        }

        guard let legacy = XTFreshPairReconnectSmokeSnapshot.from(
            doctorDetailLines: primaryCheck.detailLines
        ) else {
            return nil
        }
        return XTFreshPairReconnectSmokeDiagnosisSnapshot(legacy)
    }

    private static func xtReadyFirstPairCompletionProofSnapshot(
        from report: XHubDoctorOutputReport
    ) -> XTFirstPairCompletionProofDiagnosisSnapshot? {
        guard let structured = report.firstPairCompletionProofSnapshot else {
            return nil
        }
        return XTFirstPairCompletionProofDiagnosisSnapshot(structured)
    }

    private static func xtReadyConnectivityIncidentSnapshot(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> XHubDoctorOutputConnectivityIncidentSnapshot? {
        XHubDoctorOutputStore.loadXTConnectivityIncidentSnapshot(workspaceRoot: workspaceRoot)
    }

    private static func xtReadyConnectivityIncidentHistory(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> XHubDoctorOutputConnectivityIncidentHistoryReport? {
        XHubDoctorOutputStore.loadXTConnectivityIncidentHistory(workspaceRoot: workspaceRoot)
    }

    private static func xtReadyConnectivityRepairLedger(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> XTConnectivityRepairLedgerSnapshot? {
        let snapshot = XTConnectivityRepairLedgerStore.loadSnapshot(workspaceRoot: workspaceRoot)
        return snapshot.entries.isEmpty ? nil : snapshot
    }

    private static func xtReadySupervisorVoicePrimaryCheck(
        in report: XHubDoctorOutputReport
    ) -> XHubDoctorOutputCheckResult? {
        let voiceCheckIDs = Set([
            XTUnifiedDoctorSectionKind.wakeProfileReadiness.rawValue,
            XTUnifiedDoctorSectionKind.talkLoopReadiness.rawValue,
            XTUnifiedDoctorSectionKind.voicePlaybackReadiness.rawValue
        ])
        let actionable = report.checks.filter { check in
            guard voiceCheckIDs.contains(check.checkID) else { return false }
            switch check.status {
            case .fail, .warn:
                return true
            case .pass, .skip:
                return false
            }
        }
        guard !actionable.isEmpty else { return nil }

        return actionable.min { lhs, rhs in
            let lhsPriority = xtReadySupervisorVoiceStatusPriority(lhs.status)
            let rhsPriority = xtReadySupervisorVoiceStatusPriority(rhs.status)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            let lhsOrder = xtReadySupervisorVoiceCheckOrder(lhs.checkID)
            let rhsOrder = xtReadySupervisorVoiceCheckOrder(rhs.checkID)
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.observedAtMs < rhs.observedAtMs
        }
    }

    private static func xtReadySupervisorVoiceStatusPriority(
        _ status: XHubDoctorCheckStatus
    ) -> Int {
        switch status {
        case .fail:
            return 0
        case .warn:
            return 1
        case .pass, .skip:
            return 2
        }
    }

    private static func xtReadySupervisorVoiceCheckOrder(_ checkID: String) -> Int {
        switch checkID {
        case XTUnifiedDoctorSectionKind.wakeProfileReadiness.rawValue:
            return 0
        case XTUnifiedDoctorSectionKind.talkLoopReadiness.rawValue:
            return 1
        case XTUnifiedDoctorSectionKind.voicePlaybackReadiness.rawValue:
            return 2
        default:
            return 99
        }
    }

    private static func xtReadyHubRuntimeDiagnosisSnapshot(
        from report: XHubDoctorOutputReport
    ) -> XTHubRuntimeDiagnosisSnapshot? {
        let failureCode = report.currentFailureCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryCheck = xtReadyHubRuntimePrimaryCheck(
            in: report,
            failureCode: failureCode
        )
        let headline = (
            primaryCheck?.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? primaryCheck?.headline
                : report.summary.headline
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextStep = (
            primaryCheck?.nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? primaryCheck?.nextStep
                : report.nextSteps.first?.instruction
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return XTHubRuntimeDiagnosisSnapshot(
            overallState: report.overallState.rawValue,
            readyForFirstTask: report.readyForFirstTask,
            failureCode: failureCode,
            headline: headline,
            detailLines: xtReadyHubRuntimeDetailLines(primaryCheck),
            nextStep: nextStep,
            repairDestinationRef: (
                primaryCheck?.repairDestinationRef?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? primaryCheck?.repairDestinationRef
                    : report.nextSteps.first?.destinationRef
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            generatedAtMs: report.generatedAtMs
        )
    }

    private static func xtReadyHubRuntimeDiagnosisSnapshot(
        from snapshot: XHubLocalServiceSnapshotReport
    ) -> XTHubRuntimeDiagnosisSnapshot? {
        guard snapshot.doctorProjection != nil
                || snapshot.primaryIssue != nil
                || !snapshot.providers.isEmpty else {
            return nil
        }

        let projection = snapshot.doctorProjection
        let primaryIssue = snapshot.primaryIssue
        let projectionFailureCode = projection?.currentFailureCode.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let projectionHeadline = projection?.headline.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let projectionNextStep = projection?.nextStep.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let primaryFailureCode = primaryIssue?.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let primaryHeadline = primaryIssue?.headline.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let primaryNextStep = primaryIssue?.nextStep.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let overallState = projection?.overallState.rawValue
            ?? (snapshot.runtimeAlive ? XHubDoctorOverallState.degraded.rawValue : XHubDoctorOverallState.blocked.rawValue)
        let failureCode = projectionFailureCode.isEmpty ? primaryFailureCode : projectionFailureCode
        let headline = projectionHeadline.isEmpty ? primaryHeadline : projectionHeadline
        let nextStep = projectionNextStep.isEmpty ? primaryNextStep : projectionNextStep

        return XTHubRuntimeDiagnosisSnapshot(
            overallState: overallState,
            readyForFirstTask: projection?.readyForFirstTask ?? false,
            failureCode: failureCode,
            headline: headline,
            detailLines: snapshot.preferredDetailLines(),
            nextStep: nextStep,
            repairDestinationRef: projection?.repairDestinationRef.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            generatedAtMs: snapshot.generatedAtMs
        )
    }

    private static func xtReadyHubRuntimeDiagnosisSnapshot(
        from guidance: XHubLocalServiceRecoveryGuidanceReport
    ) -> XTHubRuntimeDiagnosisSnapshot? {
        let failureCode = guidance.primaryFailureCode
        let actionCategory = guidance.actionCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let installHint = guidance.installHint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard guidance.guidancePresent
                || guidance.primaryIssue != nil
                || !failureCode.isEmpty
                || !actionCategory.isEmpty
                || !installHint.isEmpty else {
            return nil
        }

        let providerCheckStatus = XHubDoctorCheckStatus(
            rawValue: guidance.providerCheckStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let overallState: String
        if guidance.providerCheckBlocking {
            overallState = XHubDoctorOverallState.blocked.rawValue
        } else {
            switch providerCheckStatus {
            case .pass:
                overallState = failureCode.isEmpty ? XHubDoctorOverallState.ready.rawValue : XHubDoctorOverallState.degraded.rawValue
            case .warn, .fail:
                overallState = XHubDoctorOverallState.degraded.rawValue
            case .skip, .none:
                overallState = guidance.runtimeAlive
                    ? XHubDoctorOverallState.degraded.rawValue
                    : XHubDoctorOverallState.blocked.rawValue
            }
        }

        let primaryIssue = guidance.primaryIssue
        let headline = (
            primaryIssue?.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? primaryIssue?.headline
                : installHint
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let primaryNextStep = primaryIssue?.nextStep.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let recommendedAction = guidance.topRecommendedActionSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextStep = !primaryNextStep.isEmpty
            ? primaryNextStep
            : (!recommendedAction.isEmpty ? recommendedAction : installHint)
        let readyForFirstTask = !guidance.providerCheckBlocking
            && failureCode.isEmpty
            && providerCheckStatus == .pass
            && guidance.readyProviderCount > 0

        return XTHubRuntimeDiagnosisSnapshot(
            overallState: overallState,
            readyForFirstTask: readyForFirstTask,
            failureCode: failureCode,
            headline: headline,
            detailLines: guidance.preferredDetailLines(),
            nextStep: nextStep,
            actionCategory: actionCategory,
            installHint: installHint,
            recommendedAction: recommendedAction,
            supportFAQSummary: guidance.topSupportFAQSummary,
            repairDestinationRef: guidance.repairDestinationRef.trimmingCharacters(in: .whitespacesAndNewlines),
            generatedAtMs: guidance.generatedAtMs
        )
    }

    private static func xtReadyMergedHubRuntimeDiagnosis(
        _ base: XTHubRuntimeDiagnosisSnapshot?,
        guidance: XTHubRuntimeDiagnosisSnapshot?
    ) -> XTHubRuntimeDiagnosisSnapshot? {
        guard let guidance else { return base }
        guard var merged = base else { return guidance }

        let mergedFailureCode = merged.failureCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let guidanceFailureCode = guidance.failureCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let codesMatch = !guidanceFailureCode.isEmpty
            && (mergedFailureCode.isEmpty || mergedFailureCode == guidanceFailureCode)
        let guidanceIsNewerOrSame = guidance.generatedAtMs >= merged.generatedAtMs
        let shouldApplyGuidance = guidanceIsNewerOrSame || codesMatch || mergedFailureCode.isEmpty
        guard shouldApplyGuidance else { return merged }

        if mergedFailureCode.isEmpty, !guidanceFailureCode.isEmpty {
            merged.failureCode = guidanceFailureCode
        }
        if merged.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !guidance.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.headline = guidance.headline
        }
        if merged.nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !guidance.nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.nextStep = guidance.nextStep
        }
        if merged.detailLines.isEmpty, !guidance.detailLines.isEmpty {
            merged.detailLines = guidance.detailLines
        }
        if merged.actionCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !guidance.actionCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.actionCategory = guidance.actionCategory
        }
        if merged.installHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !guidance.installHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.installHint = guidance.installHint
        }
        if merged.recommendedAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !guidance.recommendedAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.recommendedAction = guidance.recommendedAction
        }
        if merged.supportFAQSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !guidance.supportFAQSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.supportFAQSummary = guidance.supportFAQSummary
        }
        if merged.repairDestinationRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !guidance.repairDestinationRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.repairDestinationRef = guidance.repairDestinationRef
        }
        merged.generatedAtMs = max(merged.generatedAtMs, guidance.generatedAtMs)
        return merged
    }

    private static func xtReadyMergeHubRuntimeMonitorDetails(
        _ diagnosis: XTHubRuntimeDiagnosisSnapshot?,
        monitor: XHubLocalRuntimeMonitorSnapshotReport?
    ) -> XTHubRuntimeDiagnosisSnapshot? {
        guard var diagnosis else { return nil }
        guard let monitor else { return diagnosis }

        let monitorLines = monitor.preferredDetailLines(limit: 2)
        let monitorLoadConfigLine = monitor.preferredLoadConfigLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if diagnosis.loadConfigSummaryLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !monitorLoadConfigLine.isEmpty {
            diagnosis.loadConfigSummaryLine = monitorLoadConfigLine
        }
        guard !monitorLines.isEmpty else {
            diagnosis.generatedAtMs = max(diagnosis.generatedAtMs, monitor.generatedAtMs)
            return diagnosis
        }

        var mergedLines = diagnosis.detailLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for line in monitorLines where !mergedLines.contains(line) {
            mergedLines.append(line)
        }
        diagnosis.detailLines = Array(mergedLines.prefix(4))
        diagnosis.generatedAtMs = max(diagnosis.generatedAtMs, monitor.generatedAtMs)
        return diagnosis
    }

    private static func xtReadyHubRuntimePrimaryCheck(
        in report: XHubDoctorOutputReport,
        failureCode: String
    ) -> XHubDoctorOutputCheckResult? {
        if !failureCode.isEmpty,
           let failureCheck = report.checks.first(where: { $0.checkID == failureCode }) {
            return failureCheck
        }
        if let blocking = report.checks.first(where: \.blocking) {
            return blocking
        }
        if let degraded = report.checks.first(where: { $0.status == .warn || $0.status == .fail }) {
            return degraded
        }
        return report.checks.first
    }

    private static func xtReadyHubRuntimeDetailLines(
        _ primaryCheck: XHubDoctorOutputCheckResult?
    ) -> [String] {
        guard let primaryCheck,
              primaryCheck.status != .pass else {
            return []
        }

        let normalized = primaryCheck.detailLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return [] }

        let preferred = normalized.filter { line in
            line.hasPrefix("ready_providers=")
                || line.hasPrefix("provider_count=")
                || line.hasPrefix("managed_service_provider_count=")
                || line.hasPrefix("managed_service_ready_count=")
                || line.contains("service_state=")
                || line.contains("runtime_reason=")
                || line.contains("endpoint=")
                || line.contains("execution_mode=")
                || line.contains("loaded_instances=")
                || line.contains("queued=")
        }

        let detailPool = preferred.isEmpty ? normalized : preferred
        let readyProvidersLine = detailPool.first(where: { $0.hasPrefix("ready_providers=") })
        let providerLine = detailPool.first(where: { $0.contains("service_state=") || $0.contains("endpoint=") })
        var prioritized: [String] = []
        if let readyProvidersLine {
            prioritized.append(readyProvidersLine)
        }
        if let providerLine, !prioritized.contains(providerLine) {
            prioritized.append(providerLine)
        }
        for line in detailPool where !prioritized.contains(line) {
            prioritized.append(line)
        }
        return Array(prioritized.prefix(2))
    }

    private static func xtReadyAutoExportStatus(
        ok: Bool,
        reason: String,
        strictIssues: [String]
    ) -> String {
        guard ok else {
            return "failed:\(reason)"
        }
        guard strictIssues.isEmpty else {
            return "strict_risk:\(strictIssues.joined(separator: ","))"
        }
        return "ok"
    }

    func exportXTReadyIncidentEventsReport(
        outputURL: URL? = nil,
        limit: Int = 120
    ) -> XTReadyIncidentEventsExportResult {
        let rows = Self.buildXTReadyIncidentEvents(from: supervisorIncidentLedger, limit: limit)
        let missing = Self.missingXTReadyIncidentCodes(in: rows)
        let readiness = Self.evaluateXTReadyIncidentReadiness(events: rows)
        let memoryReadiness = Self.evaluateSupervisorMemoryAssemblyReadiness(
            snapshot: supervisorMemoryAssemblySnapshot
        )
        let pairedRouteSetSnapshot = Self.xtReadyPairedRouteSetSnapshot()
        let pairedRouteSnapshot = Self.xtReadyPairedRouteSnapshot()
        let connectivityIncidentSnapshot = Self.xtReadyConnectivityIncidentSnapshot()
        let connectivityIncidentHistory = Self.xtReadyConnectivityIncidentHistory()
        let connectivityRepairLedger = Self.xtReadyConnectivityRepairLedger()
        let hubRuntimeDiagnosis = Self.xtReadyHubRuntimeDiagnosisSnapshot()
        let freshPairReconnectSmoke = Self.xtReadyFreshPairReconnectSmokeSnapshot()
        let firstPairCompletionProof = Self.xtReadyFirstPairCompletionProofSnapshot()
        let strictIssues = Self.xtReadyStrictIssueCodes(
            incidentReadiness: readiness,
            memoryReadiness: memoryReadiness,
            hubRuntimeDiagnosis: hubRuntimeDiagnosis
        )
        let mirrorState = Self.supervisorDurableCandidateMirrorExportState(
            snapshot: supervisorMemoryAssemblySnapshot
        )
        let destination = outputURL ?? defaultXTReadyIncidentEventsReportURL()
        let summary = XTReadyIncidentSummary(
            highRiskLaneWithoutGrant: 0,
            unauditedAutoResolution: 0,
            highRiskBypassCount: 0,
            blockedEventMissRate: 0,
            nonMessageIngressPolicyCoverage: rows.isEmpty ? 0 : 1,
            memoryAssemblyReady: memoryReadiness.ready,
            memoryAssemblyIssueCount: memoryReadiness.issues.count,
            memoryAssemblyRequestedProfile: supervisorMemoryAssemblySnapshot?.requestedProfile ?? "",
            memoryAssemblyResolvedProfile: supervisorMemoryAssemblySnapshot?.resolvedProfile ?? "",
            memoryAssemblyTruncatedLayerCount: supervisorMemoryAssemblySnapshot?.truncatedLayers.count ?? 0,
            durableCandidateMirrorStatus: mirrorState.status.rawValue,
            durableCandidateMirrorTarget: mirrorState.target,
            durableCandidateMirrorAttempted: mirrorState.attempted,
            durableCandidateMirrorErrorCode: mirrorState.errorCode,
            durableCandidateLocalStoreRole: mirrorState.localStoreRole,
            pairedRouteSetSnapshot: pairedRouteSetSnapshot,
            pairedRouteSnapshot: pairedRouteSnapshot,
            connectivityIncident: connectivityIncidentSnapshot,
            connectivityIncidentHistory: connectivityIncidentHistory,
            connectivityRepairLedger: connectivityRepairLedger,
            freshPairReconnectSmoke: freshPairReconnectSmoke,
            firstPairCompletionProof: firstPairCompletionProof
        )
        let payload = XTReadyIncidentEventsPayload(
            runId: "xt_ready_runtime_\(Int64((Date().timeIntervalSince1970 * 1000).rounded()))",
            schemaVersion: "xt_ready_incident_events.v1",
            generatedAtMs: Int64((Date().timeIntervalSince1970 * 1000).rounded()),
            source: "supervisor_manager",
            summary: summary,
            events: rows
        )

        do {
            try Self.writeXTReadyIncidentEventsPayload(payload, to: destination)
            let result = XTReadyIncidentEventsExportResult(
                ok: true,
                outputPath: destination.path,
                exportedEventCount: rows.count,
                missingIncidentCodes: missing,
                reason: "ok"
            )
            xtReadyIncidentEventsReportPath = result.outputPath
            xtReadyIncidentEventsAutoExportStatus = Self.xtReadyAutoExportStatus(
                ok: result.ok,
                reason: result.reason,
                strictIssues: strictIssues
            )
            return result
        } catch {
            let result = XTReadyIncidentEventsExportResult(
                ok: false,
                outputPath: destination.path,
                exportedEventCount: rows.count,
                missingIncidentCodes: missing,
                reason: "write_failed:\(error.localizedDescription)"
            )
            xtReadyIncidentEventsReportPath = result.outputPath
            xtReadyIncidentEventsAutoExportStatus = Self.xtReadyAutoExportStatus(
                ok: result.ok,
                reason: result.reason,
                strictIssues: strictIssues
            )
            return result
        }
    }

    private static func writeXTReadyIncidentEventsPayload(
        _ payload: XTReadyIncidentEventsPayload,
        to destination: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try writeXTReadyIncidentReportData(data, to: destination, options: .atomic)
        } catch {
            guard looksLikeXTReadyIncidentReportDiskSpaceExhaustion(error),
                  FileManager.default.fileExists(atPath: destination.path) else {
                throw error
            }
            try writeXTReadyIncidentReportData(data, to: destination, options: [])
        }
    }

    private static func writeXTReadyIncidentReportData(
        _ data: Data,
        to destination: URL,
        options: Data.WritingOptions
    ) throws {
        if let override = withXTReadyIncidentReportWriteTestingLock({
            xtReadyIncidentReportWriteAttemptOverrideForTesting
        }) {
            try override(data, destination, options)
            return
        }
        try data.write(to: destination, options: options)
    }

    private static func looksLikeXTReadyIncidentReportDiskSpaceExhaustion(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == 28 {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return looksLikeXTReadyIncidentReportDiskSpaceExhaustion(underlying)
        }
        return false
    }

    @discardableResult
    static func withXTReadyIncidentReportWriteTestingLock<T>(_ body: () -> T) -> T {
        xtReadyIncidentReportWriteTestingLock.lock()
        defer { xtReadyIncidentReportWriteTestingLock.unlock() }
        return body()
    }

    @discardableResult
    static func withSupervisorVoiceSkillActionTestingLock<T>(_ body: () -> T) -> T {
        supervisorVoiceSkillActionTestingLock.lock()
        defer { supervisorVoiceSkillActionTestingLock.unlock() }
        return body()
    }

    func xtReadyIncidentExportSnapshot(limit: Int = 120) -> XTReadyIncidentExportSnapshot {
        let rows = Self.buildXTReadyIncidentEvents(from: supervisorIncidentLedger, limit: limit)
        let missing = Self.missingXTReadyIncidentCodes(in: rows)
        let incidentReadiness = Self.evaluateXTReadyIncidentReadiness(events: rows)
        let memoryReadiness = Self.evaluateSupervisorMemoryAssemblyReadiness(
            snapshot: supervisorMemoryAssemblySnapshot
        )
        let pairedRouteSetSnapshot = Self.xtReadyPairedRouteSetSnapshot()
        let pairedRouteSnapshot = Self.xtReadyPairedRouteSnapshot()
        let connectivityIncidentSnapshot = Self.xtReadyConnectivityIncidentSnapshot()
        let connectivityIncidentHistory = Self.xtReadyConnectivityIncidentHistory()
        let connectivityRepairLedger = Self.xtReadyConnectivityRepairLedger()
        let hubRuntimeDiagnosis = Self.xtReadyHubRuntimeDiagnosisSnapshot()
        let freshPairReconnectSmoke = Self.xtReadyFreshPairReconnectSmokeSnapshot()
        let firstPairCompletionProof = Self.xtReadyFirstPairCompletionProofSnapshot()
        let supervisorVoiceDiagnosis = Self.xtReadySupervisorVoiceDiagnosisSnapshot()
        let strictIssues = Self.xtReadyStrictIssueCodes(
            incidentReadiness: incidentReadiness,
            memoryReadiness: memoryReadiness,
            hubRuntimeDiagnosis: hubRuntimeDiagnosis
        )
        let mirrorState = Self.supervisorDurableCandidateMirrorExportState(
            snapshot: supervisorMemoryAssemblySnapshot
        )
        let defaultPath = defaultXTReadyIncidentEventsReportURL().path
        return XTReadyIncidentExportSnapshot(
            autoExportEnabled: isXTReadyIncidentAutoExportEnabled,
            ledgerIncidentCount: supervisorIncidentLedger.count,
            requiredIncidentEventCount: rows.count,
            missingIncidentCodes: missing,
            memoryAssemblyReady: memoryReadiness.ready,
            memoryAssemblyIssues: memoryReadiness.issueCodes,
            memoryAssemblyDetailLines: Self.xtReadyMemoryAssemblyDetailLines(
                memoryReadiness,
                snapshot: supervisorMemoryAssemblySnapshot
            ),
            memoryAssemblyStatusLine: memoryReadiness.statusLine,
            durableCandidateMirrorStatus: mirrorState.status,
            durableCandidateMirrorTarget: mirrorState.target,
            durableCandidateMirrorAttempted: mirrorState.attempted,
            durableCandidateMirrorErrorCode: mirrorState.errorCode,
            durableCandidateLocalStoreRole: mirrorState.localStoreRole,
            strictE2EReady: strictIssues.isEmpty,
            strictE2EIssues: strictIssues,
            pairedRouteSetSnapshot: pairedRouteSetSnapshot,
            pairedRouteSnapshot: pairedRouteSnapshot,
            connectivityIncidentSnapshot: connectivityIncidentSnapshot,
            connectivityIncidentHistory: connectivityIncidentHistory,
            connectivityRepairLedger: connectivityRepairLedger,
            hubRuntimeDiagnosis: hubRuntimeDiagnosis,
            freshPairReconnectSmokeSnapshot: freshPairReconnectSmoke,
            firstPairCompletionProofSnapshot: firstPairCompletionProof,
            supervisorVoiceDiagnosis: supervisorVoiceDiagnosis,
            status: xtReadyIncidentEventsAutoExportStatus,
            reportPath: xtReadyIncidentEventsReportPath.isEmpty ? defaultPath : xtReadyIncidentEventsReportPath
        )
    }

    private static func xtReadyMemoryAssemblyDetailLines(
        _ memoryReadiness: SupervisorMemoryAssemblyReadiness,
        snapshot: SupervisorMemoryAssemblySnapshot?
    ) -> [String] {
        var lines: [String] = memoryReadiness.issues.prefix(2).compactMap { issue in
            let detailParts = issue.detail
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !detailParts.isEmpty else { return nil }
            return "\(issue.code): \(detailParts.prefix(2).joined(separator: " | "))"
        }
        if let snapshot,
           shouldSurfaceMemoryAssemblySnapshotDetails(snapshot) {
            lines.append(contentsOf: prioritizedMemoryAssemblySnapshotDetailLines(snapshot))
        }
        return Array(lines.prefix(4))
    }

    private static func supervisorDurableCandidateMirrorExportState(
        snapshot: SupervisorMemoryAssemblySnapshot?
    ) -> (
        status: SupervisorDurableCandidateMirrorStatus,
        target: String?,
        attempted: Bool,
        errorCode: String?,
        localStoreRole: String
    ) {
        guard let snapshot else {
            return (
                status: .notNeeded,
                target: nil,
                attempted: false,
                errorCode: nil,
                localStoreRole: XTSupervisorDurableCandidateMirror.localStoreRole
            )
        }
        return (
            status: snapshot.durableCandidateMirrorStatus,
            target: snapshot.durableCandidateMirrorTarget,
            attempted: snapshot.durableCandidateMirrorAttempted,
            errorCode: snapshot.durableCandidateMirrorErrorCode,
            localStoreRole: snapshot.durableCandidateLocalStoreRole
        )
    }

    private static func shouldSurfaceMemoryAssemblySnapshotDetails(
        _ snapshot: SupervisorMemoryAssemblySnapshot
    ) -> Bool {
        snapshot.rawWindowSource != "xt_cache"
            || snapshot.lowSignalDroppedMessages > 0
            || !snapshot.continuityFloorSatisfied
            || snapshot.rollingDigestPresent
            || !snapshot.lowSignalDropSampleLines.isEmpty
            || snapshot.durableCandidateMirrorAttempted
            || snapshot.durableCandidateMirrorStatus != .notNeeded
            || snapshot.localPersonalMemoryWriteIntent != nil
            || snapshot.localCrossLinkWriteIntent != nil
            || snapshot.localPersonalReviewWriteIntent != nil
            || snapshot.scopedPromptRecoveryHumanLine != nil
    }

    static func prioritizedMemoryAssemblySnapshotDetailLines(
        _ snapshot: SupervisorMemoryAssemblySnapshot
    ) -> [String] {
        let drillDownLines = snapshot.continuityDrillDownLines
        let continuityLine = drillDownLines.first { $0.hasPrefix("continuity ") }
        let scopedRecoveryLine = drillDownLines.first { $0.hasPrefix("scoped_prompt_recovery:") }
        let mirrorLine = drillDownLines.first { $0.hasPrefix("durable_candidate_mirror ") }
        let localWriteLine = drillDownLines.first { $0.hasPrefix("xt_local_store_writes ") }
        let remotePromptLine = drillDownLines.first { $0.hasPrefix("remote_prompt ") }
        let traceLine = drillDownLines.first { line in
            !line.hasPrefix("continuity ")
                && !line.hasPrefix("scoped_prompt_recovery:")
                && !line.hasPrefix("durable_candidate_mirror ")
                && !line.hasPrefix("xt_local_store_writes ")
                && !line.hasPrefix("remote_prompt ")
                && !line.hasPrefix("low_signal_samples:")
        }
        let lowSignalLine = drillDownLines.first { $0.hasPrefix("low_signal_samples:") }

        var lines: [String] = []
        func append(_ line: String?) {
            guard let trimmed = line?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  !lines.contains(trimmed) else {
                return
            }
            lines.append(trimmed)
        }

        append(continuityLine)
        append(scopedRecoveryLine)
        append(mirrorLine)
        append(localWriteLine)
        append(remotePromptLine)
        append(traceLine)
        append(lowSignalLine)

        for line in drillDownLines {
            append(line)
        }
        return lines
    }

    private func defaultXTReadyIncidentEventsReportURL() -> URL {
        let env = (ProcessInfo.processInfo.environment["XTERMINAL_XT_READY_INCIDENT_EVENTS_PATH"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !env.isEmpty {
            let expanded = NSString(string: env).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        let root = SupervisorDoctorChecker.defaultWorkspaceRoot()
        return root.appendingPathComponent(".axcoder/reports/xt_ready_incident_events.runtime.json")
    }

}
