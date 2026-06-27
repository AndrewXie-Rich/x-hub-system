import SwiftUI
import AppKit
import RELFlowHubCore

extension SettingsSheetView {
func exportDiagnosticsBundle() {
        Task { await exportDiagnosticsBundleAsync() }
    }

    func exportUnifiedDoctorReport() {
        Task { await exportUnifiedDoctorReportAsync() }
    }

    func openLaunchStatusFile(primary: URL, fallback: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: primary.path) {
            NSWorkspace.shared.activateFileViewerSelecting([primary])
            return
        }
        if fm.fileExists(atPath: fallback.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fallback])
            return
        }
        NSWorkspace.shared.open(primary.deletingLastPathComponent())
    }

    func pathLine(_ label: String, url: URL) -> String {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: url.path)
        return HubUIStrings.Settings.Diagnostics.pathLine(label: label, path: url.path, exists: exists)
    }

    func hubDoctorCompanionPaths(for reportPath: String) -> (snapshotPath: String, recoveryGuidancePath: String) {
        let normalized = reportPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return (
                snapshotPath: HubUIStrings.Settings.Diagnostics.missingField,
                recoveryGuidancePath: HubUIStrings.Settings.Diagnostics.missingField
            )
        }
        let baseURL = URL(fileURLWithPath: normalized, isDirectory: false).deletingLastPathComponent()
        return (
            snapshotPath: baseURL.appendingPathComponent("xhub_local_service_snapshot.redacted.json").path,
            recoveryGuidancePath: baseURL.appendingPathComponent("xhub_local_service_recovery_guidance.redacted.json").path
        )
    }

    func unifiedDoctorReportSummaryForClipboard() -> String {
        let companionPaths = hubDoctorCompanionPaths(for: unifiedDoctorReportPath)
        let companionSummary = HubUIStrings.Settings.Diagnostics.companionFiles(
            runtimeReportPath: unifiedDoctorReportPath.isEmpty ? HubUIStrings.Settings.Diagnostics.missingField : unifiedDoctorReportPath,
            snapshotPath: companionPaths.snapshotPath,
            recoveryGuidancePath: companionPaths.recoveryGuidancePath,
            channelOnboardingPath: unifiedDoctorChannelReportPath.isEmpty ? HubUIStrings.Settings.Diagnostics.missingField : unifiedDoctorChannelReportPath
        )
        return [
            companionSummary,
            HubUIStrings.Settings.Diagnostics.Export.remoteAccessBlock(remoteAccessDiagnosticsSummaryForClipboard()),
        ].joined(separator: "\n\n")
    }

    func remoteAccessDiagnosticsSummaryForClipboard() -> String {
        let health = grpcRemoteAccessHealthSummary
        let route = remoteRouteProbe.snapshot
        let host = grpc.xtTerminalInternetHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let routeAddresses = route.addresses.isEmpty
            ? HubUIStrings.Settings.Diagnostics.noneField
            : route.addresses.joined(separator: ", ")
        let securePackState = grpc.secureRemoteSetupPackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "unavailable"
            : "ready"

        let lines: [String] = [
            "external_host: \(host.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : host)",
            "grpc_auto_start: \(grpc.autoStart ? "on" : "off")",
            "grpc_serving: \(grpc.isServingAvailable ? "on" : "off")",
            "invite_token: \(grpc.hasExternalInviteToken ? "issued" : "missing")",
            "keep_system_awake: \(servingPower.keepSystemAwakeWhileServing ? "on" : "off")",
            "keep_display_awake: \(servingPower.keepDisplayAwakeWhileServing ? "on" : "off")",
            "health_status: \(health.badgeText)",
            "health_headline: \(health.headline)",
            "health_detail: \(health.detail)",
            "health_access_scope: \(health.accessScopeText)",
            "health_operator_hint: \(health.operatorHintText)",
            "route_status: \(route.statusText)",
            "route_detail: \(route.detailText)",
            "route_addresses: \(routeAddresses)",
            "secure_remote_setup_pack: \(securePackState)",
        ]
        return lines.joined(separator: "\n")
    }

    func unifiedDoctorRevealURLs() -> [URL] {
        var urls: [URL] = []
        let runtimePath = unifiedDoctorReportPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !runtimePath.isEmpty {
            urls.append(URL(fileURLWithPath: runtimePath))
        }
        let channelPath = unifiedDoctorChannelReportPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !channelPath.isEmpty {
            urls.append(URL(fileURLWithPath: channelPath))
        }
        return urls
    }
}
