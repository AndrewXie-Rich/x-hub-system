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
}
