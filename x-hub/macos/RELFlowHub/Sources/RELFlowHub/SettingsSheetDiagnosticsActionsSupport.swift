import AppKit
import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    func formatEpochMs(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        let f = DateFormatter()
        f.dateFormat = HubUIStrings.Formatting.dateTimeWithSeconds
        return f.string(from: d)
    }

    func copyLocalProviderSummaryToClipboard(snapshot: HubLaunchStatusSnapshot?) {
        let blocked = snapshot?.degraded.blockedCapabilities ?? []
        let rtStatus = (rustLocalMLAuthorityMode ? runtimeHeartbeatText : store.aiRuntimeStatusText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let doctor = runtimeDoctorDetailText.trimmingCharacters(in: .whitespacesAndNewlines)
        let installHints = store.aiRuntimeInstallHintsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerSummary = store.aiRuntimeProviderSummaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let pythonCandidates = store.aiRuntimePythonCandidatesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let monitorSummary = store.aiRuntimeStatusSnapshot?.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var lines: [String] = []
        if !rtStatus.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeStatusBlock(rtStatus))
        }
        if !doctor.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeDoctorBlock(doctor))
        }
        if rustLocalMLAuthorityMode {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeDoctorBlock(rustLocalMLReadinessClipboardText))
        }
        if !rustLocalMLAuthorityMode && !installHints.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeInstallHintsBlock(installHints))
        }
        if let guidance = xhubLocalServiceRecoveryGuidance {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.localServiceRecoveryBlock(guidance.clipboardText))
        }
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.blockedCapabilitiesBlock(
                blocked.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : blocked.joined(separator: "\n")
            )
        )
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.providerSummaryBlock(
                providerSummary.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : providerSummary
            )
        )
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.remoteAccessBlock(
                remoteAccessDiagnosticsSummaryForClipboard()
            )
        )
        if !pythonCandidates.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.pythonCandidatesBlock(pythonCandidates))
        }
        if !monitorSummary.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeMonitorBlock(monitorSummary))
        }

        let out = HubDiagnosticsBundleExporter.redactTextForSharing(lines.joined(separator: "\n\n"))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyRuntimeMonitorSummaryToClipboard(status: AIRuntimeStatus) {
        let text = status.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(text)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyRuntimeMonitorActiveTasksToClipboard(monitor: AIRuntimeMonitorSnapshot) {
        let body = monitor.activeTasks.isEmpty
            ? HubUIStrings.Settings.RuntimeMonitor.noneField
            : monitor.activeTasks.map(runtimeMonitorActiveTaskLine).joined(separator: "\n")
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(
            HubUIStrings.Settings.Diagnostics.Export.activeTasksBlock(body)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyRuntimeMonitorLoadedInstancesToClipboard(summary: LocalRuntimeOperationsSummary) {
        let body = summary.instanceRows.isEmpty
            ? HubUIStrings.Settings.RuntimeMonitor.noneField
            : summary.instanceRows.map(runtimeMonitorLoadedInstanceLine).joined(separator: "\n")
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(
            HubUIStrings.Settings.Diagnostics.Export.loadedInstancesBlock(body)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyRuntimeMonitorCurrentTargetsToClipboard(
        _ currentTargets: [(HubModel, LocalModelRuntimeRequestContext)]
    ) {
        let body = currentTargets.isEmpty
            ? HubUIStrings.Settings.RuntimeMonitor.noneField
            : currentTargets.map { runtimeMonitorCurrentTargetLine(model: $0.0, requestContext: $0.1) }.joined(separator: "\n")
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(
            HubUIStrings.Settings.Diagnostics.Export.currentTargetsBlock(body)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyRuntimeMonitorErrorsToClipboard(monitor: AIRuntimeMonitorSnapshot) {
        let body = monitor.lastErrors.isEmpty
            ? HubUIStrings.Settings.RuntimeMonitor.noneField
            : monitor.lastErrors.map(runtimeMonitorErrorLine).joined(separator: "\n")
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(
            HubUIStrings.Settings.Diagnostics.Export.lastErrorsBlock(body)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyRuntimePythonCandidatesToClipboard() {
        let body = store.aiRuntimePythonCandidatesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(
            HubUIStrings.Settings.Diagnostics.Export.pythonCandidatesBlock(
                body.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : body
            )
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyXHubLocalServiceRecoveryToClipboard(_ guidance: XHubLocalServiceRecoveryGuidance) {
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(guidance.clipboardText)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyLocalRuntimeRepairSummary(_ summary: LocalRuntimeRepairSurfaceSummary) {
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(summary.clipboardText)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func localServiceRecoverySeverityColor(_ severity: String) -> Color {
        switch severity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high":
            return .red
        case "medium":
            return .orange
        default:
            return .secondary
        }
    }

    func reloadAXConstitutionStatus() {
        axConstitutionErrorText = ""
        axConstitutionVersion = ""
        axConstitutionEnabledClauseIds = []

        let url = store.axConstitutionURL()
        guard let data = try? Data(contentsOf: url) else {
            // Missing is common before the first runtime start.
            return
        }
        do {
            let raw = try JSONSerialization.jsonObject(with: data, options: [])
            guard let obj = raw as? [String: Any] else {
                axConstitutionErrorText = HubUIStrings.Settings.Advanced.Constitution.invalidJSONShape
                return
            }
            if let v = obj["version"] as? String {
                axConstitutionVersion = v
            } else {
                axConstitutionVersion = ""
            }

            var enabled: [String] = []
            if let clauses = obj["clauses"] as? [Any] {
                for item in clauses {
                    guard let c = item as? [String: Any] else { continue }
                    guard let cid = c["id"] as? String else { continue }
                    if (c["default"] as? Bool) == true {
                        enabled.append(cid)
                    }
                }
            }
            enabled.sort()
            axConstitutionEnabledClauseIds = enabled
        } catch {
            axConstitutionErrorText = error.localizedDescription
        }
    }

    func copyAXConstitutionSummaryToClipboard() {
        let url = store.axConstitutionURL()
        let ver = axConstitutionVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let enabled = axConstitutionEnabledClauseIds

        var lines: [String] = []
        lines.append(HubUIStrings.Settings.Advanced.Constitution.summaryPath(url.path))
        lines.append(
            HubUIStrings.Settings.Advanced.Constitution.summaryVersion(
                ver.isEmpty ? HubUIStrings.Settings.Advanced.Constitution.unknown : ver
            )
        )
        lines.append(
            HubUIStrings.Settings.Advanced.Constitution.summaryEnabledDefaultClauses(
                enabled.isEmpty ? HubUIStrings.Settings.Advanced.Constitution.none : enabled.joined(separator: ",")
            )
        )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @MainActor
    func exportDiagnosticsBundleAsync() async {
        if diagnosticsBundleIsExporting { return }
        diagnosticsBundleIsExporting = true
        diagnosticsBundleError = ""
        diagnosticsBundleArchivePath = ""
        diagnosticsBundleManifestPath = ""
        diagnosticsBundleMissingFiles = []
        defer { diagnosticsBundleIsExporting = false }

        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port

        do {
            let res: HubDiagnosticsBundleExporter.ExportResult = try await Task.detached(priority: .utility) {
                try await HubDiagnosticsBundleExporter.exportDiagnosticsBundle(
                    redactTokens: true,
                    operatorChannelAdminToken: adminToken,
                    operatorChannelGRPCPort: grpcPort
                )
            }.value

            diagnosticsBundleArchivePath = res.archivePath
            diagnosticsBundleManifestPath = res.manifestPath
            diagnosticsBundleMissingFiles = res.missingFiles

            // Copy the archive path for quick sharing in GitHub issues/Slack.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(res.archivePath, forType: .string)
        } catch {
            diagnosticsBundleError = error.localizedDescription
        }
    }

    @MainActor
    func exportUnifiedDoctorReportAsync() async {
        if unifiedDoctorReportIsExporting { return }
        unifiedDoctorReportIsExporting = true
        unifiedDoctorReportError = ""
        unifiedDoctorReportPath = ""
        unifiedDoctorChannelReportPath = ""
        defer { unifiedDoctorReportIsExporting = false }

        let blockedCapabilities = hubLaunchStatus?.degraded.blockedCapabilities ?? []
        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port
        let result: HubDiagnosticsBundleExporter.UnifiedDoctorReportsResult = await Task.detached(priority: .utility) {
            await HubDiagnosticsBundleExporter.exportUnifiedDoctorReports(
                status: AIRuntimeStatusStorage.load(),
                blockedCapabilities: blockedCapabilities,
                statusURL: AIRuntimeStatusStorage.url(),
                operatorChannelAdminToken: adminToken,
                operatorChannelGRPCPort: grpcPort,
                surface: .hubUI
            )
        }.value

        unifiedDoctorReportPath = result.runtimeReportPath
        unifiedDoctorChannelReportPath = result.channelOnboardingReportPath

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(unifiedDoctorReportSummaryForClipboard(), forType: .string)
    }

}
