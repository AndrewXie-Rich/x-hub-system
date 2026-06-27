import Foundation
import RELFlowHubCore

enum XHubDoctorOutputStore {
    private static let hubReportFileName = "xhub_doctor_output_hub.json"
    private static let hubLocalServiceSnapshotFileName = "xhub_local_service_snapshot.redacted.json"
    private static let hubLocalRuntimeMonitorSnapshotFileName = "local_runtime_monitor_snapshot.redacted.json"
    private static let hubLocalServiceRecoveryGuidanceFileName = "xhub_local_service_recovery_guidance.redacted.json"
    private static let hubChannelOnboardingReportFileName = "xhub_doctor_output_channel_onboarding.redacted.json"

    static func defaultHubReportURL(baseDir: URL = SharedPaths.ensureHubDirectory()) -> URL {
        baseDir.appendingPathComponent(hubReportFileName)
    }

    static func defaultHubLocalServiceSnapshotURL(baseDir: URL = SharedPaths.ensureHubDirectory()) -> URL {
        baseDir.appendingPathComponent(hubLocalServiceSnapshotFileName)
    }

    static func defaultHubLocalRuntimeMonitorSnapshotURL(baseDir: URL = SharedPaths.ensureHubDirectory()) -> URL {
        baseDir.appendingPathComponent(hubLocalRuntimeMonitorSnapshotFileName)
    }

    static func defaultHubLocalServiceRecoveryGuidanceURL(baseDir: URL = SharedPaths.ensureHubDirectory()) -> URL {
        baseDir.appendingPathComponent(hubLocalServiceRecoveryGuidanceFileName)
    }

    static func defaultHubChannelOnboardingReportURL(baseDir: URL = SharedPaths.ensureHubDirectory()) -> URL {
        baseDir.appendingPathComponent(hubChannelOnboardingReportFileName)
    }

    @discardableResult
    static func writeCurrentHubRuntimeReadinessReport(
        status: AIRuntimeStatus? = AIRuntimeStatusStorage.load(),
        blockedCapabilities: [String] = HubLaunchStatusStorage.load()?.degraded.blockedCapabilities ?? [],
        outputURL: URL = XHubDoctorOutputStore.defaultHubReportURL(),
        surface: XHubDoctorSurface = .hubUI,
        statusURL: URL = AIRuntimeStatusStorage.url()
    ) -> XHubDoctorOutputReport {
        let hostMetrics = XHubLocalRuntimeHostMetricsSampler.capture()
        let report = XHubDoctorOutputReport.hubRuntimeReadinessBundle(
            status: status,
            blockedCapabilities: blockedCapabilities,
            outputPath: outputURL.path,
            surface: surface,
            statusURL: statusURL,
            hostMetrics: hostMetrics
        )
        writeReport(report, to: outputURL)
        writeHubLocalServiceSnapshot(
            status: status,
            statusURL: statusURL,
            outputURL: companionHubLocalServiceSnapshotURL(for: outputURL)
        )
        writeHubLocalRuntimeMonitorSnapshot(
            status: status,
            statusURL: statusURL,
            outputURL: companionHubLocalRuntimeMonitorSnapshotURL(for: outputURL),
            hostMetrics: hostMetrics
        )
        writeHubLocalServiceRecoveryGuidance(
            status: status,
            blockedCapabilities: blockedCapabilities,
            statusURL: statusURL,
            outputURL: companionHubLocalServiceRecoveryGuidanceURL(for: outputURL)
        )
        return report
    }

    static func writeReport(_ report: XHubDoctorOutputReport, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? encoder.encode(report),
              let text = String(data: raw, encoding: .utf8) else {
            return
        }
        let data = Data((text + "\n").utf8)
        writeData(data, to: url)
    }

    static func writeHubLocalServiceSnapshot(
        status: AIRuntimeStatus? = AIRuntimeStatusStorage.load(),
        statusURL: URL = AIRuntimeStatusStorage.url(),
        outputURL: URL = defaultHubLocalServiceSnapshotURL()
    ) {
        let data = HubDiagnosticsBundleExporter.xhubLocalServiceSnapshotExportData(
            status: status,
            statusURL: statusURL
        ) ?? Data("""
        {"schema_version":"xhub_local_service_snapshot_export.v1","runtime_alive":false,"provider_count":0,"ready_provider_count":0,"providers":[]}
        """.utf8)
        writeData(data, to: outputURL)
    }

    static func writeHubLocalRuntimeMonitorSnapshot(
        status: AIRuntimeStatus? = AIRuntimeStatusStorage.load(),
        statusURL: URL = AIRuntimeStatusStorage.url(),
        outputURL: URL = defaultHubLocalRuntimeMonitorSnapshotURL(),
        hostMetrics: XHubLocalRuntimeHostMetricsSnapshot? = XHubLocalRuntimeHostMetricsSampler.capture()
    ) {
        let data = HubDiagnosticsBundleExporter.localRuntimeMonitorSnapshotExportData(
            status: status,
            statusURL: statusURL,
            hostMetrics: hostMetrics
        ) ?? Data("""
        {"schema_version":"xhub_local_runtime_monitor_export.v1","runtime_alive":false,"monitor_snapshot":null,"host_metrics":null}
        """.utf8)
        writeData(data, to: outputURL)
    }

    static func writeHubLocalServiceRecoveryGuidance(
        status: AIRuntimeStatus? = AIRuntimeStatusStorage.load(),
        blockedCapabilities: [String] = HubLaunchStatusStorage.load()?.degraded.blockedCapabilities ?? [],
        statusURL: URL = AIRuntimeStatusStorage.url(),
        outputURL: URL = defaultHubLocalServiceRecoveryGuidanceURL()
    ) {
        let data = HubDiagnosticsBundleExporter.xhubLocalServiceRecoveryGuidanceExportData(
            status: status,
            blockedCapabilities: blockedCapabilities,
            statusURL: statusURL
        ) ?? Data("""
        {"schema_version":"xhub_local_service_recovery_guidance_export.v1","runtime_alive":false,"guidance_present":false,"provider_count":0,"ready_provider_count":0,"recommended_actions":[],"support_faq":[]}
        """.utf8)
        writeData(data, to: outputURL)
    }

    @discardableResult
    static func writeHubChannelOnboardingReadinessReport(
        readinessRows: [HubOperatorChannelOnboardingDeliveryReadiness],
        runtimeRows: [HubOperatorChannelProviderRuntimeStatus],
        liveTestReports: [HubOperatorChannelLiveTestEvidenceReport] = [],
        sourceStatus: String = "ok",
        fetchErrors: [String] = [],
        adminBaseURL: String = "",
        outputURL: URL = defaultHubChannelOnboardingReportURL(),
        surface: XHubDoctorSurface = .hubUI
    ) -> XHubDoctorOutputReport {
        let sourceReportPath: String = {
            let normalized = adminBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return "hub://admin/operator-channels" }
            return normalized + "/admin/operator-channels"
        }()
        let report = XHubDoctorOutputReport.hubChannelOnboardingReadinessBundle(
            readinessRows: readinessRows,
            runtimeRows: runtimeRows,
            liveTestReports: liveTestReports,
            sourceStatus: sourceStatus,
            fetchErrors: fetchErrors,
            sourceReportPath: sourceReportPath,
            outputPath: outputURL.path,
            surface: surface
        )
        writeReport(report, to: outputURL)
        return report
    }

    private static func existingReportMatches(_ data: Data, at url: URL) -> Bool {
        guard let existing = try? Data(contentsOf: url) else { return false }
        return existing == data
    }

    private static func companionHubLocalServiceSnapshotURL(for reportURL: URL) -> URL {
        reportURL
            .deletingLastPathComponent()
            .appendingPathComponent(hubLocalServiceSnapshotFileName)
    }

    private static func companionHubLocalRuntimeMonitorSnapshotURL(for reportURL: URL) -> URL {
        reportURL
            .deletingLastPathComponent()
            .appendingPathComponent(hubLocalRuntimeMonitorSnapshotFileName)
    }

    private static func companionHubLocalServiceRecoveryGuidanceURL(for reportURL: URL) -> URL {
        reportURL
            .deletingLastPathComponent()
            .appendingPathComponent(hubLocalServiceRecoveryGuidanceFileName)
    }

    private static func writeData(_ data: Data, to url: URL) {
        if existingReportMatches(data, at: url) {
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            try? data.write(to: url)
        }
    }
}
