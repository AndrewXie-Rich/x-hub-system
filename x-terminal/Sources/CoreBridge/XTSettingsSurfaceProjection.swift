import Combine
import Foundation

struct XTSettingsSurfaceProjectionSnapshot: Equatable {
    var settings: XTerminalSettings
    var modelsState: ModelStateSnapshot
    var hubBaseDir: URL?
    var hubConnected: Bool
    var hubRemoteConnected: Bool
    var hubRemoteLinking: Bool
    var hubRemoteRoute: HubRemoteRoute
    var hubRemoteSummary: String
    var hubRemotePaidAccessSnapshot: HubRemotePaidAccessSnapshot?
    var hubRemoteLog: String
    var hubRemoteLogOriginalUTF8Count: Int
    var hubRemoteLogIsTruncated: Bool
    var hubSetupDiscoverState: HubSetupStepState
    var hubSetupBootstrapState: HubSetupStepState
    var hubSetupConnectState: HubSetupStepState
    var hubSetupFailureCode: String
    var hubPortAutoDetectRunning: Bool
    var hubPortAutoDetectMessage: String
    var hubDiscoveredCandidates: [HubDiscoveredHubCandidateSummary]
    var hubPairingPort: Int
    var hubGrpcPort: Int
    var hubInternetHost: String
    var hubInviteToken: String
    var hubInviteAlias: String
    var hubInviteInstanceID: String
    var hubAxhubctlPath: String
    var serverRunning: Bool
    var localServerEnabled: Bool
    var localServerPort: Int
    var localServerLastError: String
    var unifiedDoctorReport: XTUnifiedDoctorReport
    var runtimeSnapshot: UIFailClosedRuntimeSnapshot
    var skillsCompatibilitySnapshot: AXSkillsDoctorSnapshot
    var officialSkillsRecheckStatusLine: String
    var historicalProjectBoundaryRepairStatusLine: String
    var supervisorVoiceSmokeRunning: Bool
    var supervisorVoiceSmokeStatusLine: String
    var supervisorVoiceSmokeDetailLine: String
    var supervisorVoiceSmokeLastPassed: Bool?
    var canOpenSupervisorVoiceSmokeReport: Bool
    var selectedProjectId: String?
    var selectedProjectName: String?
    var selectedProjectContext: AXProjectContext?
    var selectedProjectConfig: AXProjectConfig?
    var routeRepairLogLines: [String]
    var routeRepairLogTotalLineCount: Int
    var routeRepairLogDigest: AXRouteRepairLogDigest
    var currentProjectRouteWatchItem: AXRouteRepairProjectWatchItem?

    static let empty = XTSettingsSurfaceProjectionBuilder.build(from: .empty)

    var hubInteractive: Bool {
        hubConnected || hubRemoteConnected
    }
}

struct XTSettingsDiagnosticsProjectionInput: Encodable, Equatable, Sendable {
    var connectionStateLabel: String?
    var diagnosticsLines: [String]
    var routeRepairLogLines: [String]
    var hubRemoteLog: String

    enum CodingKeys: String, CodingKey {
        case connectionStateLabel = "connection_state_label"
        case diagnosticsLines = "diagnostics_lines"
        case routeRepairLogLines = "route_repair_log_lines"
        case hubRemoteLog = "hub_remote_log"
    }
}

struct XTSettingsDiagnosticsProjection: Codable, Equatable, Sendable {
    var connectionStateLabel: String
    var diagnosticsLines: [String]
    var routeRepairRecentLines: [String]
    var routeRepairTotalLineCount: Int
    var hubRemoteLogTail: XTSettingsHubRemoteLogTailProjection

    enum CodingKeys: String, CodingKey {
        case connectionStateLabel = "connection_state_label"
        case diagnosticsLines = "diagnostics_lines"
        case routeRepairRecentLines = "route_repair_recent_lines"
        case routeRepairTotalLineCount = "route_repair_total_line_count"
        case hubRemoteLogTail = "hub_remote_log_tail"
    }
}

struct XTSettingsHubRemoteLogTailProjection: Codable, Equatable, Sendable {
    var title: String
    var text: String
    var truncated: Bool
    var totalBytes: Int
    var displayedBytes: Int

    enum CodingKeys: String, CodingKey {
        case title
        case text
        case truncated
        case totalBytes = "total_bytes"
        case displayedBytes = "displayed_bytes"
    }
}

enum XTSettingsDiagnosticsProjectionInputBuilder {
    static func build(from snapshot: XTSettingsCenterSnapshot) -> XTSettingsDiagnosticsProjectionInput {
        XTSettingsDiagnosticsProjectionInput(
            connectionStateLabel: connectionStateLabel(from: snapshot),
            diagnosticsLines: [],
            routeRepairLogLines: snapshot.routeRepairLogLines,
            hubRemoteLog: snapshot.hubRemoteLog
        )
    }

    static func jsonString(
        for input: XTSettingsDiagnosticsProjectionInput,
        encoder: JSONEncoder = JSONEncoder()
    ) -> String? {
        guard let data = try? encoder.encode(input) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func buildProjection(
        from input: XTSettingsDiagnosticsProjectionInput
    ) -> XTSettingsDiagnosticsProjection {
        let logProjection = XTSettingsSurfaceProjectionBuilder.projectedHubRemoteLog(input.hubRemoteLog)
        return XTSettingsDiagnosticsProjection(
            connectionStateLabel: normalizedNonEmpty(input.connectionStateLabel) ?? "未连接",
            diagnosticsLines: Array(input.diagnosticsLines.suffix(120)),
            routeRepairRecentLines: XTSettingsSurfaceProjectionBuilder.projectedRouteRepairLogLines(
                input.routeRepairLogLines
            ),
            routeRepairTotalLineCount: input.routeRepairLogLines.count,
            hubRemoteLogTail: XTSettingsHubRemoteLogTailProjection(
                title: "Hub Remote Log",
                text: logProjection.displayText,
                truncated: logProjection.truncated,
                totalBytes: logProjection.originalUTF8Count,
                displayedBytes: logProjection.displayText.utf8.count
            )
        )
    }

    private static func connectionStateLabel(from snapshot: XTSettingsCenterSnapshot) -> String {
        if snapshot.hubConnected || snapshot.hubRemoteConnected { return "已连接" }
        if snapshot.hubRemoteLinking { return "连接中" }
        return "未连接"
    }

    private static func normalizedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum XTSettingsSurfaceProjectionBuilder {
    static let hubRemoteLogDisplayCharacterLimit = 16_000
    static let routeRepairLogDisplayLineLimit = 80

    static func build(
        from snapshot: XTSettingsCenterSnapshot,
        diagnosticsProjection: XTSettingsDiagnosticsProjection? = nil
    ) -> XTSettingsSurfaceProjectionSnapshot {
        let logProjection = diagnosticsProjection.map {
            (
                displayText: $0.hubRemoteLogTail.text,
                originalUTF8Count: $0.hubRemoteLogTail.totalBytes,
                truncated: $0.hubRemoteLogTail.truncated
            )
        } ?? projectedHubRemoteLog(snapshot.hubRemoteLog)
        let visibleRouteRepairLogLines = diagnosticsProjection?.routeRepairRecentLines
            ?? projectedRouteRepairLogLines(snapshot.routeRepairLogLines)
        let routeRepairLogTotalLineCount = diagnosticsProjection?.routeRepairTotalLineCount
            ?? snapshot.routeRepairLogLines.count

        return XTSettingsSurfaceProjectionSnapshot(
            settings: snapshot.settings,
            modelsState: snapshot.modelsState,
            hubBaseDir: snapshot.hubBaseDir,
            hubConnected: snapshot.hubConnected,
            hubRemoteConnected: snapshot.hubRemoteConnected,
            hubRemoteLinking: snapshot.hubRemoteLinking,
            hubRemoteRoute: snapshot.hubRemoteRoute,
            hubRemoteSummary: snapshot.hubRemoteSummary,
            hubRemotePaidAccessSnapshot: snapshot.hubRemotePaidAccessSnapshot,
            hubRemoteLog: logProjection.displayText,
            hubRemoteLogOriginalUTF8Count: logProjection.originalUTF8Count,
            hubRemoteLogIsTruncated: logProjection.truncated,
            hubSetupDiscoverState: snapshot.hubSetupDiscoverState,
            hubSetupBootstrapState: snapshot.hubSetupBootstrapState,
            hubSetupConnectState: snapshot.hubSetupConnectState,
            hubSetupFailureCode: snapshot.hubSetupFailureCode,
            hubPortAutoDetectRunning: snapshot.hubPortAutoDetectRunning,
            hubPortAutoDetectMessage: snapshot.hubPortAutoDetectMessage,
            hubDiscoveredCandidates: snapshot.hubDiscoveredCandidates,
            hubPairingPort: snapshot.hubPairingPort,
            hubGrpcPort: snapshot.hubGrpcPort,
            hubInternetHost: snapshot.hubInternetHost,
            hubInviteToken: snapshot.hubInviteToken,
            hubInviteAlias: snapshot.hubInviteAlias,
            hubInviteInstanceID: snapshot.hubInviteInstanceID,
            hubAxhubctlPath: snapshot.hubAxhubctlPath,
            serverRunning: snapshot.serverRunning,
            localServerEnabled: snapshot.localServerEnabled,
            localServerPort: snapshot.localServerPort,
            localServerLastError: snapshot.localServerLastError,
            unifiedDoctorReport: snapshot.unifiedDoctorReport,
            runtimeSnapshot: snapshot.runtimeSnapshot,
            skillsCompatibilitySnapshot: snapshot.skillsCompatibilitySnapshot,
            officialSkillsRecheckStatusLine: snapshot.officialSkillsRecheckStatusLine,
            historicalProjectBoundaryRepairStatusLine: snapshot.historicalProjectBoundaryRepairStatusLine,
            supervisorVoiceSmokeRunning: snapshot.supervisorVoiceSmokeRunning,
            supervisorVoiceSmokeStatusLine: snapshot.supervisorVoiceSmokeStatusLine,
            supervisorVoiceSmokeDetailLine: snapshot.supervisorVoiceSmokeDetailLine,
            supervisorVoiceSmokeLastPassed: snapshot.supervisorVoiceSmokeLastPassed,
            canOpenSupervisorVoiceSmokeReport: snapshot.canOpenSupervisorVoiceSmokeReport,
            selectedProjectId: snapshot.selectedProjectId,
            selectedProjectName: snapshot.selectedProjectName,
            selectedProjectContext: snapshot.selectedProjectContext,
            selectedProjectConfig: snapshot.selectedProjectConfig,
            routeRepairLogLines: visibleRouteRepairLogLines,
            routeRepairLogTotalLineCount: routeRepairLogTotalLineCount,
            routeRepairLogDigest: snapshot.routeRepairLogDigest,
            currentProjectRouteWatchItem: snapshot.currentProjectRouteWatchItem
        )
    }

    static func buildFast(
        from snapshot: XTSettingsCenterSnapshot,
        preservingDiagnosticsFrom previous: XTSettingsSurfaceProjectionSnapshot?
    ) -> XTSettingsSurfaceProjectionSnapshot {
        let diagnosticsProjection = previous.map {
            XTSettingsDiagnosticsProjection(
                connectionStateLabel: "",
                diagnosticsLines: [],
                routeRepairRecentLines: $0.routeRepairLogLines,
                routeRepairTotalLineCount: $0.routeRepairLogTotalLineCount,
                hubRemoteLogTail: XTSettingsHubRemoteLogTailProjection(
                    title: "Hub Remote Log",
                    text: $0.hubRemoteLog,
                    truncated: $0.hubRemoteLogIsTruncated,
                    totalBytes: $0.hubRemoteLogOriginalUTF8Count,
                    displayedBytes: $0.hubRemoteLog.utf8.count
                )
            )
        } ?? XTSettingsDiagnosticsProjection(
            connectionStateLabel: "",
            diagnosticsLines: [],
            routeRepairRecentLines: [],
            routeRepairTotalLineCount: snapshot.routeRepairLogLines.count,
            hubRemoteLogTail: XTSettingsHubRemoteLogTailProjection(
                title: "Hub Remote Log",
                text: "",
                truncated: false,
                totalBytes: 0,
                displayedBytes: 0
            )
        )
        return build(from: snapshot, diagnosticsProjection: diagnosticsProjection)
    }

    static func projectedHubRemoteLog(
        _ rawLog: String
    ) -> (displayText: String, originalUTF8Count: Int, truncated: Bool) {
        let originalUTF8Count = rawLog.utf8.count
        guard originalUTF8Count > hubRemoteLogDisplayCharacterLimit else {
            return (rawLog, originalUTF8Count, false)
        }

        let suffix = String(rawLog.suffix(hubRemoteLogDisplayCharacterLimit))
        return (
            "...已截断较早日志，仅显示最近 \(hubRemoteLogDisplayCharacterLimit) 个字符。\n\n\(suffix)",
            originalUTF8Count,
            true
        )
    }

    static func projectedRouteRepairLogLines(_ lines: [String]) -> [String] {
        guard lines.count > routeRepairLogDisplayLineLimit else { return lines }
        return Array(lines.suffix(routeRepairLogDisplayLineLimit))
    }
}

@MainActor
final class XTSettingsSurfaceProjectionStore: ObservableObject {
    @Published private(set) var snapshot: XTSettingsSurfaceProjectionSnapshot

    init(snapshot: XTSettingsSurfaceProjectionSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func update(_ nextSnapshot: XTSettingsSurfaceProjectionSnapshot) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }
}
