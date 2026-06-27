import SwiftUI
import AppKit
import RELFlowHubCore

extension SettingsSheetView {
func renderRootCauseText(_ rc: HubLaunchRootCause?) -> String {
        guard let rc else { return "" }
        return HubUIStrings.Settings.Diagnostics.rootCauseSummary(
            component: rc.component.rawValue,
            code: rc.errorCode,
            detail: rc.detail
        )
    }

    func renderLaunchHistory(_ launches: [HubLaunchStatusSnapshot], limit: Int = 12) -> String {
        let maxN = max(1, min(50, limit))
        let rows = launches.prefix(maxN).map { s in
            let ts = s.updatedAtMs > 0 ? formatEpochMs(s.updatedAtMs) : HubUIStrings.Settings.Diagnostics.unknownTime
            let state = s.state.rawValue
            let degraded = s.degraded.isDegraded ? "1" : "0"
            let id = s.launchId.trimmingCharacters(in: .whitespacesAndNewlines)
            let root = renderRootCauseText(s.rootCause).replacingOccurrences(of: "\n", with: " | ")
            let rootText = root.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : root
            let blocked = s.degraded.blockedCapabilities
            let blockedText = blocked.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : blocked.joined(separator: ",")
            return HubUIStrings.Settings.Diagnostics.launchHistoryEntry(
                timestamp: ts,
                state: state,
                degraded: degraded,
                launchID: id,
                root: rootText,
                blocked: blockedText
            )
        }
        return rows.joined(separator: HubUIStrings.Settings.Diagnostics.launchHistorySeparator)
    }

    func copyLaunchHistoryToClipboard(snapshot: HubLaunchHistorySnapshot) {
        let updated = snapshot.updatedAtMs > 0 ? formatEpochMs(snapshot.updatedAtMs) : HubUIStrings.Settings.Diagnostics.unknownTime
        let header = HubUIStrings.Settings.Diagnostics.launchHistoryHeader(updated: updated, maxEntries: snapshot.maxEntries)
        let body = renderLaunchHistory(snapshot.launches, limit: snapshot.maxEntries)
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(header + "\n\n" + body)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func renderLaunchSteps(_ steps: [HubLaunchStep]) -> String {
        let out = steps.map { st in
            HubUIStrings.Settings.Diagnostics.launchStepLine(
                elapsedMs: st.elapsedMs,
                state: st.state.rawValue,
                ok: st.ok,
                code: st.errorCode,
                hint: st.errorHint
            )
        }
        return out.joined(separator: "\n")
    }

    func copyLaunchRootCauseAndBlockedToClipboard(snapshot: HubLaunchStatusSnapshot?) {
        let state = snapshot?.state.rawValue ?? "unknown"
        let root = renderRootCauseText(snapshot?.rootCause)
        let blocked = snapshot?.degraded.blockedCapabilities ?? []

        var lines: [String] = []
        lines.append(HubUIStrings.Settings.Diagnostics.Export.stateLine(state))
        if let id = snapshot?.launchId.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.launchIDLine(id))
        }
        if let snapshot, snapshot.updatedAtMs > 0 {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.updatedAtLine(formatEpochMs(snapshot.updatedAtMs)))
        }
        lines.append(HubUIStrings.Settings.Diagnostics.Export.rootCauseBlock(root.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : root))
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.blockedCapabilitiesBlock(
                blocked.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : blocked.joined(separator: "\n")
            )
        )
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.remoteAccessBlock(
                remoteAccessDiagnosticsSummaryForClipboard()
            )
        )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n\n"), forType: .string)
    }

    func copyIssueSnippetToClipboard(snapshot: HubLaunchStatusSnapshot?) {
        let state = snapshot?.state.rawValue ?? "unknown"
        let root = renderRootCauseText(snapshot?.rootCause)
        let blocked = snapshot?.degraded.blockedCapabilities ?? []
        let rtErr = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtStatus = store.aiRuntimeStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtDoctor = store.aiRuntimeDoctorSummaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtInstallHints = store.aiRuntimeInstallHintsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtProviders = store.aiRuntimeProviderSummaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtPythonCandidates = store.aiRuntimePythonCandidatesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtMonitor = store.aiRuntimeStatusSnapshot?.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var lines: [String] = []
        lines.append(HubUIStrings.Settings.Diagnostics.Export.stateLine(state))
        if let id = snapshot?.launchId.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.launchIDLine(id))
        }
        if let snapshot, snapshot.updatedAtMs > 0 {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.updatedAtLine(formatEpochMs(snapshot.updatedAtMs)))
        }
        lines.append(HubUIStrings.Settings.Diagnostics.Export.rootCauseBlock(root.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : root))
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.blockedCapabilitiesBlock(
                blocked.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : blocked.joined(separator: "\n")
            )
        )
        if !rtStatus.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeStatusBlock(rtStatus))
        }
        if !rtDoctor.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeDoctorBlock(rtDoctor))
        }
        if !rtInstallHints.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeInstallHintsBlock(rtInstallHints))
        }
        if let guidance = xhubLocalServiceRecoveryGuidance {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.localServiceRecoveryBlock(guidance.clipboardText))
        }
        if !rtProviders.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeProvidersBlock(rtProviders))
        }
        if !rtPythonCandidates.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimePythonCandidatesBlock(rtPythonCandidates))
        }
        if !rtMonitor.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeMonitorBlock(rtMonitor))
        }
        if !rtErr.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeLastErrorBlock(rtErr))
        }
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.remoteAccessBlock(
                remoteAccessDiagnosticsSummaryForClipboard()
            )
        )
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.unifiedDoctorReportBlock(
                unifiedDoctorReportSummaryForClipboard()
            )
        )
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.diagnosticsBundleBlock(
                diagnosticsBundleArchivePath.isEmpty ? HubUIStrings.Settings.Diagnostics.missingField : diagnosticsBundleArchivePath
            )
        )

        let out = HubDiagnosticsBundleExporter.redactTextForSharing(lines.joined(separator: "\n\n"))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }
}
