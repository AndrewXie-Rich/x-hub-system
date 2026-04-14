import Foundation
import CryptoKit
import RELFlowHubCore

// Export a small, shareable diagnostics bundle for debugging startup/runtime issues.
//
// Goals:
// - Make failures attributable: include launch attribution (hub_launch_status.json) + key heartbeats/logs.
// - Default safe: redact tokens/secrets and avoid exporting raw token stores.
// - Low friction: write to /tmp/RELFlowHub so users can easily attach/share.
enum HubDiagnosticsBundleExporter {
    private static let exportStrings = HubUIStrings.Settings.Diagnostics.Export.self

    struct ExportResult: Sendable {
        var archivePath: String
        var manifestPath: String
        var missingFiles: [String]
    }

    struct UnifiedDoctorReportsResult: Sendable {
        var runtimeReportPath: String
        var channelOnboardingReportPath: String
        var localServiceSnapshotPath: String
        var localServiceRecoveryGuidancePath: String
    }

    private struct ExportedFileEntry: Codable, Sendable {
        var name: String
        var sourcePath: String
        var bytes: Int
        var sha256: String
        var truncated: Bool
        var redacted: Bool

        enum CodingKeys: String, CodingKey {
            case name
            case sourcePath = "source_path"
            case bytes
            case sha256
            case truncated
            case redacted
        }
    }

    private struct Manifest: Codable, Sendable {
        var schemaVersion: String
        var exportedAtMs: Int64

        var appBundleId: String
        var appVersion: String
        var appBuild: String
        var appPath: String

        var osVersion: String
        var pid: Int32
        var sandboxed: Bool

        var hubBaseDir: String
        var config: [String: String]

        var exportedFiles: [ExportedFileEntry]
        var missingFiles: [String]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case exportedAtMs = "exported_at_ms"
            case appBundleId = "app_bundle_id"
            case appVersion = "app_version"
            case appBuild = "app_build"
            case appPath = "app_path"
            case osVersion = "os_version"
            case pid
            case sandboxed
            case hubBaseDir = "hub_base_dir"
            case config
            case exportedFiles = "exported_files"
            case missingFiles = "missing_files"
        }
    }

    private struct LocalRuntimeMonitorSnapshotEnvelope: Codable, Sendable {
        var schemaVersion: String
        var generatedAtMs: Int64
        var statusSource: String
        var runtimeAlive: Bool
        var statusSchemaVersion: String
        var monitorSummary: String
        var monitorSnapshot: AIRuntimeMonitorSnapshot?
        var runtimeOperations: LocalRuntimeOperationsExport?
        var hostMetrics: XHubLocalRuntimeHostMetricsSnapshot?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case generatedAtMs = "generated_at_ms"
            case statusSource = "status_source"
            case runtimeAlive = "runtime_alive"
            case statusSchemaVersion = "status_schema_version"
            case monitorSummary = "monitor_summary"
            case monitorSnapshot = "monitor_snapshot"
            case runtimeOperations = "runtime_operations"
            case hostMetrics = "host_metrics"
        }
    }

    private struct LocalRuntimeOperationsExport: Codable, Sendable {
        struct ProviderRow: Codable, Sendable {
            var providerID: String
            var stateLabel: String
            var queueSummary: String
            var detailSummary: String

            enum CodingKeys: String, CodingKey {
                case providerID = "provider_id"
                case stateLabel = "state_label"
                case queueSummary = "queue_summary"
                case detailSummary = "detail_summary"
            }
        }

        struct CurrentTargetRow: Codable, Sendable {
            var modelID: String
            var modelName: String
            var providerID: String
            var target: LocalModelRuntimeRequestContext
            var uiSummary: String
            var technicalSummary: String
            var loadSummary: String
            var preferredBenchHash: String

            enum CodingKeys: String, CodingKey {
                case modelID = "model_id"
                case modelName = "model_name"
                case providerID = "provider_id"
                case target
                case uiSummary = "ui_summary"
                case technicalSummary = "technical_summary"
                case loadSummary = "load_summary"
                case preferredBenchHash = "preferred_bench_hash"
            }
        }

        struct LoadedInstanceRow: Codable, Sendable {
            var providerID: String
            var modelID: String
            var modelName: String
            var instanceKey: String
            var shortInstanceKey: String
            var taskSummary: String
            var loadSummary: String
            var detailSummary: String
            var isCurrentTarget: Bool
            var currentTargetSummary: String
            var canUnload: Bool
            var canEvict: Bool
            var loadedInstance: AIRuntimeLoadedInstance
            var currentTarget: CurrentTargetRow?

            enum CodingKeys: String, CodingKey {
                case providerID = "provider_id"
                case modelID = "model_id"
                case modelName = "model_name"
                case instanceKey = "instance_key"
                case shortInstanceKey = "short_instance_key"
                case taskSummary = "task_summary"
                case loadSummary = "load_summary"
                case detailSummary = "detail_summary"
                case isCurrentTarget = "is_current_target"
                case currentTargetSummary = "current_target_summary"
                case canUnload = "can_unload"
                case canEvict = "can_evict"
                case loadedInstance = "loaded_instance"
                case currentTarget = "current_target"
            }
        }

        var runtimeSummary: String
        var queueSummary: String
        var loadedSummary: String
        var monitorStale: Bool
        var providers: [ProviderRow]
        var currentTargets: [CurrentTargetRow]
        var loadedInstances: [LoadedInstanceRow]

        enum CodingKeys: String, CodingKey {
            case runtimeSummary = "runtime_summary"
            case queueSummary = "queue_summary"
            case loadedSummary = "loaded_summary"
            case monitorStale = "monitor_stale"
            case providers
            case currentTargets = "current_targets"
            case loadedInstances = "loaded_instances"
        }
    }

    private struct XHubLocalServiceSnapshotEnvelope: Codable, Sendable {
        var schemaVersion: String
        var generatedAtMs: Int64
        var statusSource: String
        var runtimeAlive: Bool
        var providerCount: Int
        var readyProviderCount: Int
        var primaryIssue: XHubLocalServiceSnapshotPrimaryIssue?
        var doctorProjection: XHubLocalServiceSnapshotDoctorProjection?
        var providers: [XHubLocalServiceProviderEvidence]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case generatedAtMs = "generated_at_ms"
            case statusSource = "status_source"
            case runtimeAlive = "runtime_alive"
            case providerCount = "provider_count"
            case readyProviderCount = "ready_provider_count"
            case primaryIssue = "primary_issue"
            case doctorProjection = "doctor_projection"
            case providers
        }
    }

    private struct XHubLocalServiceSnapshotPrimaryIssue: Codable, Sendable {
        var reasonCode: String
        var headline: String
        var message: String
        var nextStep: String

        enum CodingKeys: String, CodingKey {
            case reasonCode = "reason_code"
            case headline
            case message
            case nextStep = "next_step"
        }
    }

    private struct XHubLocalServiceSnapshotDoctorProjection: Codable, Sendable {
        var overallState: XHubDoctorOverallState
        var readyForFirstTask: Bool
        var currentFailureCode: String
        var currentFailureIssue: String
        var providerCheckStatus: XHubDoctorCheckStatus
        var providerCheckBlocking: Bool
        var headline: String
        var message: String
        var nextStep: String
        var repairDestinationRef: String

        enum CodingKeys: String, CodingKey {
            case overallState = "overall_state"
            case readyForFirstTask = "ready_for_first_task"
            case currentFailureCode = "current_failure_code"
            case currentFailureIssue = "current_failure_issue"
            case providerCheckStatus = "provider_check_status"
            case providerCheckBlocking = "provider_check_blocking"
            case headline
            case message
            case nextStep = "next_step"
            case repairDestinationRef = "repair_destination_ref"
        }
    }

    private struct XHubLocalServiceRecoveryGuidanceEnvelope: Codable, Sendable {
        struct RecoveryAction: Codable, Sendable {
            var rank: Int
            var actionID: String
            var title: String
            var why: String
            var commandOrReference: String

            enum CodingKeys: String, CodingKey {
                case rank
                case actionID = "action_id"
                case title
                case why
                case commandOrReference = "command_or_ref"
            }
        }

        struct SupportFAQItem: Codable, Sendable {
            var faqID: String
            var question: String
            var answer: String

            enum CodingKeys: String, CodingKey {
                case faqID = "faq_id"
                case question
                case answer
            }
        }

        var schemaVersion: String
        var generatedAtMs: Int64
        var statusSource: String
        var runtimeAlive: Bool
        var guidancePresent: Bool
        var providerCount: Int
        var readyProviderCount: Int
        var currentFailureCode: String
        var currentFailureIssue: String
        var providerCheckStatus: String
        var providerCheckBlocking: Bool
        var actionCategory: String
        var severity: String
        var installHint: String
        var repairDestinationRef: String
        var serviceBaseURL: String
        var managedProcessState: String
        var managedStartAttemptCount: Int
        var managedLastStartError: String
        var managedLastProbeError: String
        var blockedCapabilities: [String]
        var primaryIssue: XHubLocalServiceSnapshotPrimaryIssue?
        var recommendedActions: [RecoveryAction]
        var supportFAQ: [SupportFAQItem]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case generatedAtMs = "generated_at_ms"
            case statusSource = "status_source"
            case runtimeAlive = "runtime_alive"
            case guidancePresent = "guidance_present"
            case providerCount = "provider_count"
            case readyProviderCount = "ready_provider_count"
            case currentFailureCode = "current_failure_code"
            case currentFailureIssue = "current_failure_issue"
            case providerCheckStatus = "provider_check_status"
            case providerCheckBlocking = "provider_check_blocking"
            case actionCategory = "action_category"
            case severity
            case installHint = "install_hint"
            case repairDestinationRef = "repair_destination_ref"
            case serviceBaseURL = "service_base_url"
            case managedProcessState = "managed_process_state"
            case managedStartAttemptCount = "managed_start_attempt_count"
            case managedLastStartError = "managed_last_start_error"
            case managedLastProbeError = "managed_last_probe_error"
            case blockedCapabilities = "blocked_capabilities"
            case primaryIssue = "primary_issue"
            case recommendedActions = "recommended_actions"
            case supportFAQ = "support_faq"
        }
    }

    private struct OperatorChannelLiveTestEvidenceEnvelope: Codable, Sendable {
        var schemaVersion: String
        var generatedAtMs: Int64
        var sourceStatus: String
        var adminBaseURL: String
        var fetchErrors: [String]
        var providerCount: Int
        var reports: [HubOperatorChannelLiveTestEvidenceReport]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case generatedAtMs = "generated_at_ms"
            case sourceStatus = "source_status"
            case adminBaseURL = "admin_base_url"
            case fetchErrors = "fetch_errors"
            case providerCount = "provider_count"
            case reports
        }
    }

    private struct OperatorChannelFetchResult<Value: Sendable>: Sendable {
        var loaded: Bool
        var value: Value
        var errorDescription: String
    }

    private struct OperatorChannelLiveTestSnapshot: Sendable {
        var sourceStatus: String
        var adminBaseURL: String
        var fetchErrors: [String]
        var readinessRows: [HubOperatorChannelOnboardingDeliveryReadiness]
        var runtimeRows: [HubOperatorChannelProviderRuntimeStatus]
        var reports: [HubOperatorChannelLiveTestEvidenceReport]

        var shouldExport: Bool {
            sourceStatus != "not_requested"
        }

        static let empty = OperatorChannelLiveTestSnapshot(
            sourceStatus: "not_requested",
            adminBaseURL: "",
            fetchErrors: [],
            readinessRows: [],
            runtimeRows: [],
            reports: []
        )
    }

    private enum FileKind {
        case json
        case log
        case text
    }

    private struct InputFile {
        var name: String
        var url: URL
        var fallbackURL: URL?
        var kind: FileKind
        var optional: Bool
        var redact: Bool
        var tailBytes: Int
    }

    static func exportDiagnosticsBundle(
        redactTokens: Bool = true,
        maxLogTailBytes: Int = 2_000_000
    ) throws -> ExportResult {
        try exportDiagnosticsBundleCore(
            redactTokens: redactTokens,
            maxLogTailBytes: maxLogTailBytes,
            operatorChannelLiveTestSnapshot: .empty
        )
    }

    static func exportDiagnosticsBundle(
        redactTokens: Bool = true,
        maxLogTailBytes: Int = 2_000_000,
        operatorChannelAdminToken: String,
        operatorChannelGRPCPort: Int
    ) async throws -> ExportResult {
        let operatorChannelLiveTestSnapshot = await loadOperatorChannelLiveTestSnapshot(
            adminToken: operatorChannelAdminToken,
            grpcPort: operatorChannelGRPCPort
        )
        return try exportDiagnosticsBundleCore(
            redactTokens: redactTokens,
            maxLogTailBytes: maxLogTailBytes,
            operatorChannelLiveTestSnapshot: operatorChannelLiveTestSnapshot
        )
    }

    static func exportUnifiedDoctorReports(
        status: AIRuntimeStatus? = AIRuntimeStatusStorage.load(),
        blockedCapabilities: [String] = HubLaunchStatusStorage.load()?.degraded.blockedCapabilities ?? [],
        statusURL: URL = AIRuntimeStatusStorage.url(),
        operatorChannelAdminToken: String,
        operatorChannelGRPCPort: Int,
        runtimeOutputURL: URL = XHubDoctorOutputStore.defaultHubReportURL(),
        channelOutputURL: URL = XHubDoctorOutputStore.defaultHubChannelOnboardingReportURL(),
        surface: XHubDoctorSurface = .hubUI
    ) async -> UnifiedDoctorReportsResult {
        let runtimeReport = XHubDoctorOutputStore.writeCurrentHubRuntimeReadinessReport(
            status: status,
            blockedCapabilities: blockedCapabilities,
            outputURL: runtimeOutputURL,
            surface: surface,
            statusURL: statusURL
        )
        let operatorChannelSnapshot = await loadOperatorChannelLiveTestSnapshot(
            adminToken: operatorChannelAdminToken,
            grpcPort: operatorChannelGRPCPort
        )
        let channelReport = XHubDoctorOutputStore.writeHubChannelOnboardingReadinessReport(
            readinessRows: operatorChannelSnapshot.readinessRows,
            runtimeRows: operatorChannelSnapshot.runtimeRows,
            liveTestReports: operatorChannelSnapshot.reports,
            sourceStatus: operatorChannelSnapshot.sourceStatus,
            fetchErrors: operatorChannelSnapshot.fetchErrors,
            adminBaseURL: operatorChannelSnapshot.adminBaseURL,
            outputURL: channelOutputURL,
            surface: surface
        )
        let runtimeBaseURL = runtimeOutputURL.deletingLastPathComponent()
        return UnifiedDoctorReportsResult(
            runtimeReportPath: runtimeReport.reportPath,
            channelOnboardingReportPath: channelReport.reportPath,
            localServiceSnapshotPath: runtimeBaseURL
                .appendingPathComponent("xhub_local_service_snapshot.redacted.json").path,
            localServiceRecoveryGuidancePath: runtimeBaseURL
                .appendingPathComponent("xhub_local_service_recovery_guidance.redacted.json").path
        )
    }

    private static func exportDiagnosticsBundleCore(
        redactTokens: Bool = true,
        maxLogTailBytes: Int = 2_000_000,
        operatorChannelLiveTestSnapshot: OperatorChannelLiveTestSnapshot
    ) throws -> ExportResult {
        let base = SharedPaths.ensureHubDirectory()
        // Prefer /tmp for easy sharing, but fall back to the Hub base dir for sandboxed builds
        // where global temp paths may not be writable.
        let outRoot: URL = {
            let candidates: [URL] = [
                URL(fileURLWithPath: "/tmp/RELFlowHub", isDirectory: true).appendingPathComponent("diagnostics_exports", isDirectory: true),
                base.appendingPathComponent("diagnostics_exports", isDirectory: true),
            ]
            for c in candidates {
                do {
                    try FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
                    return c
                } catch {
                    continue
                }
            }
            return base
        }()

        let ts = timestampForFileName()
        let bundleDir = outRoot.appendingPathComponent("xhub_diagnostics_\(ts)", isDirectory: true)
        let zipURL = outRoot.appendingPathComponent("xhub_diagnostics_\(ts).zip")
        let manifestURL = bundleDir.appendingPathComponent("manifest.json")
        // Persisted next to the zip so it's still accessible after we delete the staging folder.
        let manifestCopyURL = outRoot.appendingPathComponent("xhub_diagnostics_\(ts).manifest.json")

        // Create staging dir.
        try? FileManager.default.removeItem(at: bundleDir)
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)

        // IMPORTANT: do NOT export raw token stores. If needed, export redacted views instead.
        let inputs: [InputFile] = [
            InputFile(
                name: HubLaunchStatusStorage.fileName,
                url: HubLaunchStatusStorage.url(),
                fallbackURL: URL(fileURLWithPath: "/tmp/RELFlowHub", isDirectory: true).appendingPathComponent(HubLaunchStatusStorage.fileName),
                kind: .json,
                optional: true,
                redact: true,
                tailBytes: 0
            ),
            InputFile(
                name: HubLaunchHistoryStorage.fileName,
                url: HubLaunchHistoryStorage.url(),
                fallbackURL: URL(fileURLWithPath: "/tmp/RELFlowHub", isDirectory: true).appendingPathComponent(HubLaunchHistoryStorage.fileName),
                kind: .json,
                optional: true,
                redact: true,
                tailBytes: 0
            ),
            InputFile(name: "hub_status.json", url: base.appendingPathComponent("hub_status.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: "hub_debug.log", url: base.appendingPathComponent("hub_debug.log"), fallbackURL: nil, kind: .log, optional: true, redact: true, tailBytes: maxLogTailBytes),
            InputFile(name: "hub_grpc.log", url: base.appendingPathComponent("hub_grpc.log"), fallbackURL: nil, kind: .log, optional: true, redact: true, tailBytes: maxLogTailBytes),
            InputFile(name: "bridge_status.json", url: base.appendingPathComponent("bridge_status.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: "bridge_audit.log", url: base.appendingPathComponent("bridge_audit.log"), fallbackURL: nil, kind: .log, optional: true, redact: true, tailBytes: maxLogTailBytes),
            InputFile(name: "bridge_settings.redacted.json", url: base.appendingPathComponent("bridge_settings.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: "ai_runtime_status.json", url: base.appendingPathComponent("ai_runtime_status.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: "provider_pack_registry.redacted.json", url: base.appendingPathComponent("provider_pack_registry.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: "ai_runtime.log", url: base.appendingPathComponent("ai_runtime.log"), fallbackURL: nil, kind: .log, optional: true, redact: true, tailBytes: maxLogTailBytes),
            InputFile(name: "mlx_runtime_audit.log", url: base.appendingPathComponent("mlx_runtime_audit.log"), fallbackURL: nil, kind: .log, optional: true, redact: true, tailBytes: maxLogTailBytes),
            InputFile(name: "voice_tts_audit.log", url: base.appendingPathComponent("voice_tts_audit.log"), fallbackURL: nil, kind: .log, optional: true, redact: true, tailBytes: maxLogTailBytes),
            InputFile(
                name: "ax_constitution.redacted.json",
                url: base.appendingPathComponent("memory", isDirectory: true).appendingPathComponent("ax_constitution.json"),
                fallbackURL: nil,
                kind: .json,
                optional: true,
                redact: true,
                tailBytes: 0
            ),
            InputFile(name: "models_state.json", url: base.appendingPathComponent("models_state.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: "models_catalog.json", url: base.appendingPathComponent("models_catalog.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: ModelBenchStorage.fileName, url: ModelBenchStorage.url(), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: GRPCDeniedAttemptsStorage.fileName, url: GRPCDeniedAttemptsStorage.url(), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: GRPCDevicesStatusStorage.fileName, url: GRPCDevicesStatusStorage.url(), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: "file_ipc_status.json", url: base.appendingPathComponent("file_ipc_status.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),

            // Helpful for diagnosing pairing/auth mismatches; tokens are redacted.
            InputFile(
                name: "hub_grpc_clients.redacted.json",
                url: base.appendingPathComponent("hub_grpc_clients.json"),
                fallbackURL: nil,
                kind: .json,
                optional: true,
                redact: true,
                tailBytes: 0
            ),
        ]

        var exported: [ExportedFileEntry] = []
        var missing: [String] = []
        let runtimeStatusURL = AIRuntimeStatusStorage.url()
        let runtimeStatus = AIRuntimeStatusStorage.load()
        let blockedCapabilities = HubLaunchStatusStorage.load()?.degraded.blockedCapabilities ?? []

        for f in inputs {
            let fm = FileManager.default
            let src: URL? = {
                if fm.fileExists(atPath: f.url.path) { return f.url }
                if let fb = f.fallbackURL, fm.fileExists(atPath: fb.path) { return fb }
                return nil
            }()
            guard let src else {
                // Record missing files even if optional; bundle export is best-effort.
                missing.append(f.name)
                continue
            }
            let dst = bundleDir.appendingPathComponent(f.name)
            do {
                let (data, truncated) = try readForExport(url: src, kind: f.kind, tailBytes: f.tailBytes)
                let outData: Data
                if redactTokens && f.redact {
                    outData = redactDataForExport(data, kind: f.kind)
                } else {
                    outData = data
                }
                try writeDataAtomic(outData, to: dst)
                exported.append(
                    ExportedFileEntry(
                        name: f.name,
                        sourcePath: redactPathForManifest(src.path),
                        bytes: outData.count,
                        sha256: sha256Hex(outData),
                        truncated: truncated,
                        redacted: redactTokens && f.redact
                    )
                )
            } catch {
                // Best-effort: record as missing so the operator knows it failed to export.
                missing.append("\(f.name) (export_failed)")
            }
        }

        // DB integrity check report (text) so operators can quickly spot corruption/locking.
        do {
            let dbEntry = try exportDBIntegrityReport(base: base, to: bundleDir)
            exported.append(dbEntry)
        } catch {
            missing.append("db_integrity_check.txt (export_failed)")
        }

        // Provider-aware runtime summary so operators can see partial readiness without
        // opening multiple status files manually.
        do {
            let runtimeSummaryEntry = try exportLocalRuntimeProviderSummary(
                status: runtimeStatus,
                blockedCapabilities: blockedCapabilities,
                statusURL: runtimeStatusURL,
                to: bundleDir
            )
            exported.append(runtimeSummaryEntry)
        } catch {
            missing.append("local_runtime_provider_summary.txt (export_failed)")
        }

        do {
            let runtimeMonitorSummaryEntry = try exportLocalRuntimeMonitorSummary(
                status: runtimeStatus,
                statusURL: runtimeStatusURL,
                to: bundleDir
            )
            exported.append(runtimeMonitorSummaryEntry)
        } catch {
            missing.append("local_runtime_monitor_summary.txt (export_failed)")
        }

        do {
            let runtimeMonitorSnapshotEntry = try exportLocalRuntimeMonitorSnapshot(
                status: runtimeStatus,
                statusURL: runtimeStatusURL,
                to: bundleDir
            )
            exported.append(runtimeMonitorSnapshotEntry)
        } catch {
            missing.append("local_runtime_monitor_snapshot.redacted.json (export_failed)")
        }

        do {
            let managedServiceSnapshotEntry = try exportXHubLocalServiceSnapshot(
                status: runtimeStatus,
                statusURL: runtimeStatusURL,
                to: bundleDir
            )
            exported.append(managedServiceSnapshotEntry)
        } catch {
            missing.append("xhub_local_service_snapshot.redacted.json (export_failed)")
        }

        do {
            let managedServiceRecoveryEntry = try Self.exportXHubLocalServiceRecoveryGuidance(
                status: runtimeStatus,
                blockedCapabilities: blockedCapabilities,
                statusURL: runtimeStatusURL,
                to: bundleDir
            )
            exported.append(managedServiceRecoveryEntry)
        } catch {
            missing.append("xhub_local_service_recovery_guidance.redacted.json (export_failed)")
        }

        do {
            let runtimeBenchSummaryEntry = try exportLocalRuntimeBenchSummary(
                status: runtimeStatus,
                statusURL: runtimeStatusURL,
                benchURL: ModelBenchStorage.url(),
                to: bundleDir
            )
            exported.append(runtimeBenchSummaryEntry)
        } catch {
            missing.append("local_runtime_bench_summary.txt (export_failed)")
        }

        do {
            let doctorOutputEntry = try exportHubDoctorOutput(
                status: runtimeStatus,
                blockedCapabilities: blockedCapabilities,
                statusURL: runtimeStatusURL,
                to: bundleDir
            )
            exported.append(doctorOutputEntry)
        } catch {
            missing.append("xhub_doctor_output_hub.redacted.json (export_failed)")
        }

        if operatorChannelLiveTestSnapshot.shouldExport {
            do {
                let operatorChannelEntries = try exportOperatorChannelLiveTestEvidence(
                    snapshot: operatorChannelLiveTestSnapshot,
                    to: bundleDir
                )
                exported.append(contentsOf: operatorChannelEntries)
            } catch {
                missing.append("operator_channel_live_test_summary.txt (export_failed)")
                missing.append("operator_channel_live_test_evidence.redacted.json (export_failed)")
            }
            do {
                let onboardingReadinessEntry = try exportOperatorChannelOnboardingReadinessReport(
                    snapshot: operatorChannelLiveTestSnapshot,
                    to: bundleDir
                )
                exported.append(onboardingReadinessEntry)
            } catch {
                missing.append("xhub_doctor_output_channel_onboarding.redacted.json (export_failed)")
            }
        }

        // Write a small manifest for quick debugging without opening each file.
        let bid = Bundle.main.bundleIdentifier ?? ""
        let ver = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        let appPath = Bundle.main.bundleURL.path
        let manifest = Manifest(
            schemaVersion: "xhub_diagnostics_bundle.v1",
            exportedAtMs: nowMs(),
            appBundleId: bid,
            appVersion: ver,
            appBuild: build,
            appPath: redactPathForManifest(appPath),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            pid: getpid(),
            sandboxed: SharedPaths.isSandboxedProcess(),
            hubBaseDir: redactPathForManifest(base.path),
            config: [
                "redact_tokens": redactTokens ? "1" : "0",
                "max_log_tail_bytes": String(max(1, maxLogTailBytes)),
            ],
            exportedFiles: exported.sorted { $0.name < $1.name },
            missingFiles: missing.sorted()
        )
        var manifestCopyPath: String = ""
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data0 = try enc.encode(manifest)
            let data = (String(data: data0, encoding: .utf8) ?? "") + "\n"
            try writeDataAtomic(Data(data.utf8), to: manifestURL)
            try writeDataAtomic(Data(data.utf8), to: manifestCopyURL)
            manifestCopyPath = manifestCopyURL.path
        } catch {
            // ignore
        }

        // Create a single-file archive for easy sharing. If archiving fails (e.g. sandbox restrictions),
        // keep the folder and return its path so the user can compress/share manually.
        var archivePath = bundleDir.path
        do {
            try? FileManager.default.removeItem(at: zipURL)
            try createZipWithDitto(srcDir: bundleDir, dstZip: zipURL)
            try? FileManager.default.removeItem(at: bundleDir)
            archivePath = zipURL.path
        } catch {
            // Best-effort: record that archiving failed, but still return the folder path.
            missing.append("_archive.zip (zip_failed)")
        }

        return ExportResult(archivePath: archivePath, manifestPath: manifestCopyPath, missingFiles: missing.sorted())
    }

    // MARK: - Internals

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    private static func timestampForFileName() -> String {
        let d = Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: d)
    }

    private static func sha256Hex(_ data: Data) -> String {
        let h = SHA256.hash(data: data)
        return h.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func writeDataAtomic(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func readForExport(url: URL, kind: FileKind, tailBytes: Int) throws -> (data: Data, truncated: Bool) {
        let maxTail = max(0, tailBytes)
        if kind == .log && maxTail > 0 {
            return try tailFile(url: url, maxBytes: maxTail)
        }
        let data = try Data(contentsOf: url)
        return (data, false)
    }

    private static func tailFile(url: URL, maxBytes: Int) throws -> (data: Data, truncated: Bool) {
        let cap = max(256, maxBytes)
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        let end = try fh.seekToEnd()
        if end <= UInt64(cap) {
            try fh.seek(toOffset: 0)
            let data = try fh.readToEnd() ?? Data()
            return (data, false)
        }
        let start = end - UInt64(cap)
        try fh.seek(toOffset: start)
        let data = try fh.readToEnd() ?? Data()
        return (data, true)
    }

    private static func createZipWithDitto(srcDir: URL, dstZip: URL) throws {
        // `ditto -c -k --sequesterRsrc --keepParent <dir> <zip>` is the macOS-recommended way to zip folders.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", srcDir.path, dstZip.path]

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        try p.run()
        p.waitUntilExit()
        if p.terminationStatus == 0 {
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let msg = (String(data: data, encoding: .utf8) ?? "ditto exited \(p.terminationStatus)")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw NSError(
            domain: "HubDiagnosticsBundleExporter",
            code: Int(p.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "ditto failed" : msg]
        )
    }

    private struct SQLiteQuickCheckResult {
        var launchError: String
        var exitCode: Int32
        var elapsedMs: Int64
        var stdout: String
        var stderr: String
    }

    private static func exportDBIntegrityReport(base: URL, to bundleDir: URL) throws -> ExportedFileEntry {
        let db = base.appendingPathComponent("hub_grpc", isDirectory: true).appendingPathComponent("hub.sqlite3")
        let wal = URL(fileURLWithPath: db.path + "-wal")
        let shm = URL(fileURLWithPath: db.path + "-shm")
        let fm = FileManager.default

        func sizeOf(_ url: URL) -> Int64 {
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let n = attrs[.size] as? NSNumber else { return -1 }
            return n.int64Value
        }

        var lines: [String] = []
        lines.append("schema_version: xhub_db_integrity_report.v1")
        lines.append("checked_at_ms: \(nowMs())")
        lines.append("db_path: \(redactPathForManifest(db.path))")
        lines.append("db_exists: \(fm.fileExists(atPath: db.path) ? "1" : "0")")
        lines.append("db_bytes: \(sizeOf(db))")
        lines.append("wal_exists: \(fm.fileExists(atPath: wal.path) ? "1" : "0")")
        lines.append("wal_bytes: \(sizeOf(wal))")
        lines.append("shm_exists: \(fm.fileExists(atPath: shm.path) ? "1" : "0")")
        lines.append("shm_bytes: \(sizeOf(shm))")

        let qc = runSQLiteQuickCheck(dbPath: db.path)
        lines.append("sqlite3_launch_error: \(qc.launchError.isEmpty ? exportStrings.none : qc.launchError)")
        lines.append("sqlite3_exit_code: \(qc.exitCode)")
        lines.append("quick_check_elapsed_ms: \(qc.elapsedMs)")

        let out = qc.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = qc.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let outNorm = out.lowercased()
        let okLine = outNorm == "ok" || outNorm.hasSuffix("\nok")
        let checkOK = qc.launchError.isEmpty && qc.exitCode == 0 && okLine
        lines.append("quick_check_ok: \(checkOK ? "1" : "0")")
        lines.append("quick_check_stdout:\n" + (out.isEmpty ? exportStrings.empty : limitForReport(out)))
        lines.append("quick_check_stderr:\n" + (err.isEmpty ? exportStrings.empty : limitForReport(err)))

        let report = redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
        let data = Data(report.utf8)
        let dst = bundleDir.appendingPathComponent("db_integrity_check.txt")
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "db_integrity_check.txt",
            sourcePath: redactPathForManifest(db.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    static func localRuntimeProviderSummaryReport(
        status: AIRuntimeStatus?,
        blockedCapabilities: [String],
        statusURL: URL = AIRuntimeStatusStorage.url()
    ) -> String {
        let summary = status?.providerOperatorSummary(
            ttl: AIRuntimeStatus.recommendedHeartbeatTTL,
            blockedCapabilities: blockedCapabilities
        ) ?? "runtime_alive=0\nready_providers=none\nproviders:\ncapabilities:"
        let doctor = status?.providerDoctorText(
            ttl: AIRuntimeStatus.recommendedHeartbeatTTL,
            blockedCapabilities: blockedCapabilities
        ) ?? exportStrings.runtimeNotStarted
        let monitorSummary = status?.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? "runtime_alive=0\nmonitor_snapshot=none"

        var lines: [String] = []
        lines.append("schema_version: xhub_local_runtime_provider_summary.v2")
        lines.append("generated_at_ms: \(nowMs())")
        lines.append("status_source: \(redactPathForManifest(statusURL.path))")
        lines.append(
            "blocked_capabilities:\n" +
            (blockedCapabilities.isEmpty ? exportStrings.none : blockedCapabilities.joined(separator: "\n"))
        )
        lines.append("doctor:\n" + (doctor.isEmpty ? exportStrings.none : doctor))
        lines.append("operator_summary:\n" + summary)
        lines.append("runtime_monitor:\n" + monitorSummary)

        return redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
    }

    static func localRuntimeMonitorSummaryReport(
        status: AIRuntimeStatus?,
        models: [HubModel] = ModelStateStorage.load().models,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot = HubPairedTerminalLocalModelProfilesStorage.load(),
        targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot = LocalModelRuntimeTargetPreferencesStorage.load(),
        statusURL: URL = AIRuntimeStatusStorage.url()
    ) -> String {
        let summary = status?.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? "runtime_alive=0\nmonitor_snapshot=none"
        let runtimeOps = localRuntimeOperationsSummary(
            status: status,
            models: models,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreferencesSnapshot: targetPreferencesSnapshot
        )

        var lines: [String] = []
        lines.append("schema_version: xhub_local_runtime_monitor_summary.v1")
        lines.append("generated_at_ms: \(nowMs())")
        lines.append("status_source: \(redactPathForManifest(statusURL.path))")
        lines.append("monitor_summary:\n" + summary)
        lines.append("runtime_ops_summary:\n" + runtimeOpsSummaryBlock(runtimeOps))
        if runtimeOps.instanceRows.isEmpty {
            lines.append("loaded_instances:\n\(exportStrings.none)")
        } else {
            lines.append(
                "loaded_instances:\n" +
                runtimeOps.instanceRows.map(runtimeOpsInstanceLine).joined(separator: "\n")
            )
        }

        return redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
    }

    static func localRuntimeConsoleClipboardReport(
        status: AIRuntimeStatus?,
        models: [HubModel] = ModelStateStorage.load().models,
        currentTargetsByModelID: [String: LocalModelRuntimeRequestContext]? = nil,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot = HubPairedTerminalLocalModelProfilesStorage.load(),
        targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot = LocalModelRuntimeTargetPreferencesStorage.load(),
        statusURL: URL = AIRuntimeStatusStorage.url()
    ) -> String {
        let localModels = localRuntimeModels(models)
        let resolvedCurrentTargetsByModelID = currentTargetsByModelID ?? localRuntimeCurrentTargetsByModelID(
            status: status,
            models: localModels,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreferencesSnapshot: targetPreferencesSnapshot
        )
        let runtimeOps = LocalRuntimeOperationsSummaryBuilder.build(
            status: status,
            models: localModels,
            currentTargetsByModelID: resolvedCurrentTargetsByModelID
        )
        let runtimeOperations = localRuntimeOperationsExport(
            summary: runtimeOps,
            status: status,
            models: localModels,
            currentTargetsByModelID: resolvedCurrentTargetsByModelID
        )
        let providerDiagnoses = status?.providerDiagnoses(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? []
        let providerDiagnosisByID = Dictionary(uniqueKeysWithValues: providerDiagnoses.map { ($0.provider, $0) })
        let providerMonitorByID = Dictionary(uniqueKeysWithValues: (status?.monitorSnapshot?.providers ?? []).map { ($0.provider, $0) })
        let modelByID = Dictionary(uniqueKeysWithValues: localModels.map { ($0.id, $0) })
        let activeTasks = status?.monitorSnapshot?.activeTasks ?? []

        var lines: [String] = []
        lines.append("schema_version: xhub_local_runtime_console_clipboard.v1")
        lines.append("generated_at_ms: \(nowMs())")
        lines.append("status_source: \(redactPathForManifest(statusURL.path))")
        lines.append(
            "monitor_summary:\n" +
            (status?.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? "runtime_alive=0\nmonitor_snapshot=none")
        )
        lines.append("runtime_ops_summary:\n" + runtimeOpsSummaryBlock(runtimeOps))
        lines.append(
            "loaded_instances:\n" +
            (runtimeOps.instanceRows.isEmpty
                ? exportStrings.none
                : runtimeOps.instanceRows.map(runtimeOpsInstanceLine).joined(separator: "\n"))
        )
        lines.append(
            "current_targets:\n" +
            (runtimeOperations.currentTargets.isEmpty
                ? exportStrings.none
                : runtimeOperations.currentTargets.map {
                    localRuntimeConsoleCurrentTargetLine(
                        $0,
                        providerDiagnosis: providerDiagnosisByID[$0.providerID]
                    )
                }
                .joined(separator: "\n"))
        )
        lines.append(
            "active_tasks:\n" +
            (activeTasks.isEmpty
                ? exportStrings.none
                : activeTasks.map {
                    localRuntimeConsoleActiveTaskLine(
                        $0,
                        model: modelByID[$0.modelId],
                        providerDiagnosis: providerDiagnosisByID[$0.provider],
                        queuedTaskCount: providerMonitorByID[$0.provider]?.queuedTaskCount ?? 0
                    )
                }
                .joined(separator: "\n"))
        )

        return redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
    }

    static func localRuntimeMonitorSnapshotExportData(
        status: AIRuntimeStatus?,
        models: [HubModel] = ModelStateStorage.load().models,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot = HubPairedTerminalLocalModelProfilesStorage.load(),
        targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot = LocalModelRuntimeTargetPreferencesStorage.load(),
        statusURL: URL = AIRuntimeStatusStorage.url(),
        hostMetrics: XHubLocalRuntimeHostMetricsSnapshot? = XHubLocalRuntimeHostMetricsSampler.capture()
    ) -> Data? {
        let localModels = localRuntimeModels(models)
        let currentTargetsByModelID = localRuntimeCurrentTargetsByModelID(
            status: status,
            models: localModels,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreferencesSnapshot: targetPreferencesSnapshot
        )
        let runtimeOperationsSummary = LocalRuntimeOperationsSummaryBuilder.build(
            status: status,
            models: localModels,
            currentTargetsByModelID: currentTargetsByModelID
        )
        let envelope = LocalRuntimeMonitorSnapshotEnvelope(
            schemaVersion: "xhub_local_runtime_monitor_export.v1",
            generatedAtMs: nowMs(),
            statusSource: redactPathForManifest(statusURL.path),
            runtimeAlive: status?.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false,
            statusSchemaVersion: status?.schemaVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            monitorSummary: localRuntimeMonitorSummary(
                status: status,
                hostMetrics: hostMetrics
            ),
            monitorSnapshot: status?.monitorSnapshot,
            runtimeOperations: localRuntimeOperationsExport(
                summary: runtimeOperationsSummary,
                status: status,
                models: localModels,
                currentTargetsByModelID: currentTargetsByModelID
            ),
            hostMetrics: hostMetrics
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? enc.encode(envelope) else {
            return nil
        }
        return redactJsonBytes(raw) ?? raw
    }

    private static func localRuntimeMonitorSummary(
        status: AIRuntimeStatus?,
        hostMetrics: XHubLocalRuntimeHostMetricsSnapshot?
    ) -> String {
        let base = status?.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
            ?? "runtime_alive=0\nmonitor_snapshot=none"
        guard let hostMetrics else { return base }

        let metricLines = hostMetrics.detailLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !metricLines.isEmpty else { return base }
        return ([base] + metricLines).joined(separator: "\n")
    }

    static func xhubLocalServiceSnapshotExportData(
        status: AIRuntimeStatus?,
        statusURL: URL = AIRuntimeStatusStorage.url()
    ) -> Data? {
        let providers = XHubLocalServiceDiagnostics.providerEvidence(status: status, ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
        let primaryIssue = XHubLocalServiceDiagnostics.primaryIssue(in: providers).map {
            XHubLocalServiceSnapshotPrimaryIssue(
                reasonCode: $0.reasonCode,
                headline: $0.headline,
                message: $0.message,
                nextStep: $0.nextStep
            )
        }
        let doctorReport = XHubDoctorOutputReport.hubRuntimeReadinessBundle(
            status: status,
            blockedCapabilities: [],
            outputPath: "",
            surface: .xtExport,
            statusURL: statusURL
        )
        let doctorProjection = doctorReport.checks
            .first(where: { $0.checkKind == "provider_readiness" })
            .map { providerCheck in
                XHubLocalServiceSnapshotDoctorProjection(
                    overallState: doctorReport.overallState,
                    readyForFirstTask: doctorReport.readyForFirstTask,
                    currentFailureCode: doctorReport.currentFailureCode,
                    currentFailureIssue: doctorReport.currentFailureIssue ?? "",
                    providerCheckStatus: providerCheck.status,
                    providerCheckBlocking: providerCheck.blocking,
                    headline: providerCheck.headline,
                    message: providerCheck.message,
                    nextStep: providerCheck.nextStep,
                    repairDestinationRef: providerCheck.repairDestinationRef ?? ""
                )
            }
        let envelope = XHubLocalServiceSnapshotEnvelope(
            schemaVersion: "xhub_local_service_snapshot_export.v1",
            generatedAtMs: nowMs(),
            statusSource: redactPathForManifest(statusURL.path),
            runtimeAlive: status?.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false,
            providerCount: providers.count,
            readyProviderCount: providers.filter(\.ready).count,
            primaryIssue: primaryIssue,
            doctorProjection: doctorProjection,
            providers: providers
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? enc.encode(envelope) else {
            return nil
        }
        return redactJsonBytes(raw) ?? raw
    }

    static func xhubLocalServiceRecoveryGuidanceExportData(
        status: AIRuntimeStatus?,
        blockedCapabilities: [String] = [],
        statusURL: URL = AIRuntimeStatusStorage.url()
    ) -> Data? {
        let providers = XHubLocalServiceDiagnostics.providerEvidence(status: status, ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
        let guidance = XHubLocalServiceRecoveryGuidanceBuilder.build(
            status: status,
            blockedCapabilities: blockedCapabilities
        )
        let primaryIssue = guidance.map {
            XHubLocalServiceSnapshotPrimaryIssue(
                reasonCode: $0.primaryIssue.reasonCode,
                headline: $0.primaryIssue.headline,
                message: $0.primaryIssue.message,
                nextStep: $0.primaryIssue.nextStep
            )
        }
        let envelope = XHubLocalServiceRecoveryGuidanceEnvelope(
            schemaVersion: "xhub_local_service_recovery_guidance_export.v1",
            generatedAtMs: nowMs(),
            statusSource: redactPathForManifest(statusURL.path),
            runtimeAlive: status?.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false,
            guidancePresent: guidance != nil,
            providerCount: providers.count,
            readyProviderCount: providers.filter(\.ready).count,
            currentFailureCode: guidance?.currentFailureCode ?? "",
            currentFailureIssue: guidance?.currentFailureIssue ?? "",
            providerCheckStatus: guidance?.providerCheckStatus ?? "",
            providerCheckBlocking: guidance?.providerCheckBlocking ?? false,
            actionCategory: guidance?.actionCategory ?? "",
            severity: guidance?.severity ?? "",
            installHint: guidance?.installHint ?? "",
            repairDestinationRef: guidance?.repairDestinationRef ?? "",
            serviceBaseURL: guidance?.serviceBaseURL ?? "",
            managedProcessState: guidance?.managedProcessState ?? "",
            managedStartAttemptCount: guidance?.managedStartAttemptCount ?? 0,
            managedLastStartError: guidance?.managedLastStartError ?? "",
            managedLastProbeError: guidance?.managedLastProbeError ?? "",
            blockedCapabilities: blockedCapabilities,
            primaryIssue: primaryIssue,
            recommendedActions: (guidance?.recommendedActions ?? []).enumerated().map { index, action in
                XHubLocalServiceRecoveryGuidanceEnvelope.RecoveryAction(
                    rank: index + 1,
                    actionID: action.actionID,
                    title: action.title,
                    why: action.why,
                    commandOrReference: action.commandOrReference
                )
            },
            supportFAQ: (guidance?.supportFAQ ?? []).map { item in
                XHubLocalServiceRecoveryGuidanceEnvelope.SupportFAQItem(
                    faqID: item.faqID,
                    question: item.question,
                    answer: item.answer
                )
            }
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? enc.encode(envelope) else {
            return nil
        }
        return redactJsonBytes(raw) ?? raw
    }

    static func operatorChannelLiveTestEvidenceSummaryReport(
        reports: [HubOperatorChannelLiveTestEvidenceReport],
        sourceStatus: String = "ok",
        fetchErrors: [String] = [],
        adminBaseURL: String = "",
        generatedAtMs: Int64 = nowMs()
    ) -> String {
        let sortedReports = sortOperatorChannelLiveTestReports(reports)
        let normalizedErrors = operatorChannelUniqueNormalizedStrings(fetchErrors)
        var lines: [String] = []
        lines.append("schema_version: xhub_operator_channel_live_test_summary.v1")
        lines.append("generated_at_ms: \(generatedAtMs)")
        lines.append("source_status: \(sourceStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : sourceStatus)")
        lines.append("admin_base_url: \(adminBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? exportStrings.none : adminBaseURL)")
        lines.append(
            "fetch_errors:\n" +
            (normalizedErrors.isEmpty ? exportStrings.none : normalizedErrors.joined(separator: "\n"))
        )
        lines.append("provider_count: \(sortedReports.count)")
        if sortedReports.isEmpty {
            lines.append("providers:\n\(exportStrings.none)")
        } else {
            lines.append("providers:\n" + sortedReports.map(operatorChannelLiveTestSummaryBlock).joined(separator: "\n\n---\n\n"))
        }
        return redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
    }

    static func operatorChannelLiveTestEvidenceExportData(
        reports: [HubOperatorChannelLiveTestEvidenceReport],
        sourceStatus: String = "ok",
        fetchErrors: [String] = [],
        adminBaseURL: String = "",
        generatedAtMs: Int64 = nowMs()
    ) -> Data? {
        let envelope = OperatorChannelLiveTestEvidenceEnvelope(
            schemaVersion: "xhub_operator_channel_live_test_export.v1",
            generatedAtMs: generatedAtMs,
            sourceStatus: sourceStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : sourceStatus,
            adminBaseURL: adminBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            fetchErrors: operatorChannelUniqueNormalizedStrings(fetchErrors),
            providerCount: reports.count,
            reports: sortOperatorChannelLiveTestReports(reports)
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? enc.encode(envelope) else {
            return nil
        }
        return redactJsonBytes(raw) ?? raw
    }

    static func operatorChannelOnboardingReadinessExportData(
        readinessRows: [HubOperatorChannelOnboardingDeliveryReadiness],
        runtimeRows: [HubOperatorChannelProviderRuntimeStatus],
        liveTestReports: [HubOperatorChannelLiveTestEvidenceReport] = [],
        sourceStatus: String = "ok",
        fetchErrors: [String] = [],
        adminBaseURL: String = "",
        outputPath: String = XHubDoctorOutputStore.defaultHubChannelOnboardingReportURL().path,
        surface: XHubDoctorSurface = .hubUI,
        generatedAtMs: Int64 = nowMs()
    ) -> Data? {
        let report = XHubDoctorOutputReport.hubChannelOnboardingReadinessBundle(
            readinessRows: readinessRows,
            runtimeRows: runtimeRows,
            liveTestReports: liveTestReports,
            sourceStatus: sourceStatus,
            fetchErrors: fetchErrors,
            sourceReportPath: operatorChannelOnboardingSourcePath(adminBaseURL: adminBaseURL),
            outputPath: outputPath,
            surface: surface,
            generatedAtMs: generatedAtMs
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? enc.encode(report) else {
            return nil
        }
        return redactJsonBytes(raw) ?? raw
    }

    static func localRuntimeBenchSummaryReport(
        models: [HubModel],
        benchSnapshot: ModelsBenchSnapshot,
        status: AIRuntimeStatus?,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot = HubPairedTerminalLocalModelProfilesStorage.load(),
        targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot = LocalModelRuntimeTargetPreferencesStorage.load(),
        statusURL: URL = AIRuntimeStatusStorage.url(),
        benchURL: URL = ModelBenchStorage.url()
    ) -> String {
        var lines: [String] = []
        lines.append("schema_version: xhub_local_runtime_bench_summary.v1")
        lines.append("generated_at_ms: \(nowMs())")
        lines.append("status_source: \(redactPathForManifest(statusURL.path))")
        lines.append("bench_source: \(redactPathForManifest(benchURL.path))")
        lines.append("runtime_alive: \((status?.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false) ? "1" : "0")")

        let localModels = models
            .filter { !LocalModelRuntimeActionPlanner.isRemoteModel($0) }
            .sorted {
                let lhsName = ($0.name.isEmpty ? $0.id : $0.name).localizedCaseInsensitiveCompare($1.name.isEmpty ? $1.id : $1.name)
                if lhsName != .orderedSame {
                    return lhsName == .orderedAscending
                }
                return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
            }
        if localModels.isEmpty {
            lines.append("models:\n\(exportStrings.none)")
            return redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
        }

        var modelBlocks: [String] = []
        for model in localModels {
            let targetPreference = targetPreferencesSnapshot.preferences.first(where: { $0.modelId == model.id })
            let requestContext = LocalModelRuntimeRequestContextResolver.resolve(
                model: model,
                runtimeStatus: status,
                pairedProfilesSnapshot: pairedProfilesSnapshot,
                targetPreference: targetPreference
            )
            let allRows = benchSnapshot.results
                .filter { $0.modelId == model.id }
                .sorted {
                    if $0.measuredAt == $1.measuredAt {
                        return $0.id < $1.id
                    }
                    return $0.measuredAt > $1.measuredAt
                }
            let preferredBench = allRows.first(where: { requestContext.matchesBenchResult($0) }) ?? allRows.first
            let taskKind = preferredBench?.taskKind
                ?? LocalTaskRoutingCatalog.supportedDescriptors(in: model.taskKinds).first?.taskKind
                ?? model.taskKinds.first
                ?? ""
            let explanation = LocalModelBenchMonitorExplanationBuilder.build(
                model: model,
                taskKind: taskKind,
                requestContext: requestContext,
                benchResult: preferredBench,
                runtimeStatus: status
            )
            let capabilityCard = LocalModelBenchCapabilityCardBuilder.build(
                model: model,
                taskKind: taskKind,
                requestContext: requestContext,
                benchResult: preferredBench,
                explanation: explanation,
                runtimeStatus: status
            )
            modelBlocks.append(
                localRuntimeBenchModelBlock(
                    model: model,
                    requestContext: requestContext,
                    benchResult: preferredBench,
                    explanation: explanation,
                    capabilityCard: capabilityCard
                )
            )
        }

        lines.append("models:\n" + modelBlocks.joined(separator: "\n\n---\n\n"))
        return redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
    }

    static func localRuntimeBenchModelReport(
        model: HubModel,
        requestContext: LocalModelRuntimeRequestContext?,
        benchResult: ModelBenchResult?,
        runtimeStatus: AIRuntimeStatus?,
        generatedAtMs: Int64 = nowMs()
    ) -> String {
        let resolvedRequestContext = requestContext ?? LocalModelRuntimeRequestContextResolver.resolve(
            model: model,
            runtimeStatus: runtimeStatus
        )
        let taskKind = benchResult?.taskKind
            ?? LocalTaskRoutingCatalog.supportedDescriptors(in: model.taskKinds).first?.taskKind
            ?? model.taskKinds.first
            ?? ""
        let explanation = LocalModelBenchMonitorExplanationBuilder.build(
            model: model,
            taskKind: taskKind,
            requestContext: resolvedRequestContext,
            benchResult: benchResult,
            runtimeStatus: runtimeStatus
        )
        let capabilityCard = LocalModelBenchCapabilityCardBuilder.build(
            model: model,
            taskKind: taskKind,
            requestContext: resolvedRequestContext,
            benchResult: benchResult,
            explanation: explanation,
            runtimeStatus: runtimeStatus
        )

        let lines = [
            "schema_version: xhub_local_runtime_bench_model_report.v1",
            "generated_at_ms: \(generatedAtMs)",
            localRuntimeBenchModelBlock(
                model: model,
                requestContext: resolvedRequestContext,
                benchResult: benchResult,
                explanation: explanation,
                capabilityCard: capabilityCard
            )
        ]
        return redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
    }

    private static func exportLocalRuntimeProviderSummary(
        status: AIRuntimeStatus?,
        blockedCapabilities: [String],
        statusURL: URL,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let report = localRuntimeProviderSummaryReport(
            status: status,
            blockedCapabilities: blockedCapabilities,
            statusURL: statusURL
        )
        let data = Data(report.utf8)
        let dst = bundleDir.appendingPathComponent("local_runtime_provider_summary.txt")
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "local_runtime_provider_summary.txt",
            sourcePath: redactPathForManifest(statusURL.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func exportLocalRuntimeMonitorSummary(
        status: AIRuntimeStatus?,
        statusURL: URL,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let report = localRuntimeMonitorSummaryReport(status: status, statusURL: statusURL)
        let data = Data(report.utf8)
        let dst = bundleDir.appendingPathComponent("local_runtime_monitor_summary.txt")
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "local_runtime_monitor_summary.txt",
            sourcePath: redactPathForManifest(statusURL.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func exportLocalRuntimeMonitorSnapshot(
        status: AIRuntimeStatus?,
        statusURL: URL,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let data = localRuntimeMonitorSnapshotExportData(status: status, statusURL: statusURL)
            ?? Data("{\"schema_version\":\"xhub_local_runtime_monitor_export.v1\",\"runtime_alive\":false,\"monitor_snapshot\":null}\n".utf8)
        let dst = bundleDir.appendingPathComponent("local_runtime_monitor_snapshot.redacted.json")
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "local_runtime_monitor_snapshot.redacted.json",
            sourcePath: redactPathForManifest(statusURL.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func exportXHubLocalServiceSnapshot(
        status: AIRuntimeStatus?,
        statusURL: URL,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let data = xhubLocalServiceSnapshotExportData(status: status, statusURL: statusURL)
            ?? Data("{\"schema_version\":\"xhub_local_service_snapshot_export.v1\",\"runtime_alive\":false,\"provider_count\":0,\"ready_provider_count\":0,\"providers\":[]}\n".utf8)
        let dst = bundleDir.appendingPathComponent("xhub_local_service_snapshot.redacted.json")
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "xhub_local_service_snapshot.redacted.json",
            sourcePath: redactPathForManifest(statusURL.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func exportXHubLocalServiceRecoveryGuidance(
        status: AIRuntimeStatus?,
        blockedCapabilities: [String],
        statusURL: URL,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let data = xhubLocalServiceRecoveryGuidanceExportData(
            status: status,
            blockedCapabilities: blockedCapabilities,
            statusURL: statusURL
        )
            ?? Data("""
            {"schema_version":"xhub_local_service_recovery_guidance_export.v1","runtime_alive":false,"guidance_present":false,"provider_count":0,"ready_provider_count":0,"recommended_actions":[],"support_faq":[]}
            """.utf8)
        let dst = bundleDir.appendingPathComponent("xhub_local_service_recovery_guidance.redacted.json")
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "xhub_local_service_recovery_guidance.redacted.json",
            sourcePath: redactPathForManifest(statusURL.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func exportLocalRuntimeBenchSummary(
        status: AIRuntimeStatus?,
        statusURL: URL,
        benchURL: URL,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let report = localRuntimeBenchSummaryReport(
            models: ModelStateStorage.load().models,
            benchSnapshot: ModelBenchStorage.load(),
            status: status,
            statusURL: statusURL,
            benchURL: benchURL
        )
        let data = Data(report.utf8)
        let dst = bundleDir.appendingPathComponent("local_runtime_bench_summary.txt")
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "local_runtime_bench_summary.txt",
            sourcePath: redactPathForManifest(benchURL.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func exportHubDoctorOutput(
        status: AIRuntimeStatus?,
        blockedCapabilities: [String],
        statusURL: URL,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let dst = bundleDir.appendingPathComponent("xhub_doctor_output_hub.redacted.json")
        let report = XHubDoctorOutputReport.hubRuntimeReadinessBundle(
            status: status,
            blockedCapabilities: blockedCapabilities,
            outputPath: dst.path,
            surface: .hubUI,
            statusURL: statusURL
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let raw = try encoder.encode(report)
        let data = redactJsonBytes(raw)
            ?? Data(((String(data: raw, encoding: .utf8) ?? "") + "\n").utf8)
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "xhub_doctor_output_hub.redacted.json",
            sourcePath: redactPathForManifest(statusURL.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func exportOperatorChannelLiveTestEvidence(
        snapshot: OperatorChannelLiveTestSnapshot,
        to bundleDir: URL
    ) throws -> [ExportedFileEntry] {
        let summary = operatorChannelLiveTestEvidenceSummaryReport(
            reports: snapshot.reports,
            sourceStatus: snapshot.sourceStatus,
            fetchErrors: snapshot.fetchErrors,
            adminBaseURL: snapshot.adminBaseURL
        )
        let summaryData = Data(summary.utf8)
        let summaryURL = bundleDir.appendingPathComponent("operator_channel_live_test_summary.txt")
        try writeDataAtomic(summaryData, to: summaryURL)

        let jsonData = operatorChannelLiveTestEvidenceExportData(
            reports: snapshot.reports,
            sourceStatus: snapshot.sourceStatus,
            fetchErrors: snapshot.fetchErrors,
            adminBaseURL: snapshot.adminBaseURL
        )
            ?? Data("""
            {"schema_version":"xhub_operator_channel_live_test_export.v1","source_status":"\(snapshot.sourceStatus)","provider_count":0,"reports":[]}
            """.utf8)
        let jsonURL = bundleDir.appendingPathComponent("operator_channel_live_test_evidence.redacted.json")
        try writeDataAtomic(jsonData, to: jsonURL)

        let sourcePath = snapshot.adminBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "hub://admin/operator-channels/live-test/evidence"
            : snapshot.adminBaseURL + "/admin/operator-channels/live-test/evidence"

        return [
            ExportedFileEntry(
                name: "operator_channel_live_test_summary.txt",
                sourcePath: sourcePath,
                bytes: summaryData.count,
                sha256: sha256Hex(summaryData),
                truncated: false,
                redacted: true
            ),
            ExportedFileEntry(
                name: "operator_channel_live_test_evidence.redacted.json",
                sourcePath: sourcePath,
                bytes: jsonData.count,
                sha256: sha256Hex(jsonData),
                truncated: false,
                redacted: true
            ),
        ]
    }

    @discardableResult
    static func writeOperatorChannelOnboardingReadinessReport(
        readinessRows: [HubOperatorChannelOnboardingDeliveryReadiness],
        runtimeRows: [HubOperatorChannelProviderRuntimeStatus],
        liveTestReports: [HubOperatorChannelLiveTestEvidenceReport] = [],
        sourceStatus: String = "ok",
        fetchErrors: [String] = [],
        adminBaseURL: String = "",
        generatedAtMs: Int64 = nowMs(),
        to bundleDir: URL
    ) throws -> URL {
        let dst = bundleDir.appendingPathComponent("xhub_doctor_output_channel_onboarding.redacted.json")
        guard let data = operatorChannelOnboardingReadinessExportData(
            readinessRows: readinessRows,
            runtimeRows: runtimeRows,
            liveTestReports: liveTestReports,
            sourceStatus: sourceStatus,
            fetchErrors: fetchErrors,
            adminBaseURL: adminBaseURL,
            outputPath: dst.path,
            generatedAtMs: generatedAtMs
        ) else {
            throw CocoaError(.coderInvalidValue)
        }
        try writeDataAtomic(data, to: dst)
        return dst
    }

    private static func exportOperatorChannelOnboardingReadinessReport(
        snapshot: OperatorChannelLiveTestSnapshot,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let dst = try writeOperatorChannelOnboardingReadinessReport(
            readinessRows: snapshot.readinessRows,
            runtimeRows: snapshot.runtimeRows,
            liveTestReports: snapshot.reports,
            sourceStatus: snapshot.sourceStatus,
            fetchErrors: snapshot.fetchErrors,
            adminBaseURL: snapshot.adminBaseURL,
            to: bundleDir
        )
        let data = try Data(contentsOf: dst)
        return ExportedFileEntry(
            name: dst.lastPathComponent,
            sourcePath: operatorChannelOnboardingSourcePath(adminBaseURL: snapshot.adminBaseURL),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func localRuntimeBenchModelBlock(
        model: HubModel,
        requestContext: LocalModelRuntimeRequestContext,
        benchResult: ModelBenchResult?,
        explanation: LocalModelBenchMonitorExplanation?,
        capabilityCard: LocalModelBenchCapabilityCard
    ) -> String {
        var lines: [String] = []
        lines.append("model_id=\(model.id)")
        lines.append("model_name=\((model.name.isEmpty ? model.id : model.name))")
        lines.append("provider=\(LocalModelRuntimeActionPlanner.providerID(for: model))")
        lines.append("target=\(requestContext.uiSummary)")
        lines.append("target_detail=\(requestContext.technicalSummary)")
        lines.append("target_load=\(requestContext.technicalLoadProfileSummary.isEmpty ? "none" : requestContext.technicalLoadProfileSummary)")
        lines.append("target_profile=\(shortHash(requestContext.preferredBenchHash))")
        if let benchResult {
            lines.append(
                "bench_task=\(benchResult.taskKind.isEmpty ? "unknown" : benchResult.taskKind) verdict=\(benchResult.verdict.isEmpty ? (benchResult.ok ? "ready" : "failed") : benchResult.verdict) reason=\(benchResult.reasonCode.isEmpty ? "none" : benchResult.reasonCode) fallback=\(benchResult.fallbackMode.isEmpty ? "none" : benchResult.fallbackMode)"
            )
            lines.append("bench_load=\(benchLoadSummary(benchResult))")
            lines.append("bench_matches_target=\(requestContext.matchesBenchResult(benchResult) ? "1" : "0")")
        } else {
            lines.append("bench_task=none verdict=none reason=none fallback=none")
            lines.append("bench_load=none")
            lines.append("bench_matches_target=0")
        }
        if let explanation {
            lines.append("bench_explanation=\(explanation.headline)")
            if !explanation.detailLines.isEmpty {
                lines.append("bench_explanation_details:\n" + explanation.detailLines.joined(separator: "\n"))
            }
        } else {
            lines.append("bench_explanation=\(exportStrings.none)")
        }
        lines.append("capability_headline=\(capabilityCard.headline)")
        lines.append("capability_tone=\(capabilityCard.tone.rawValue)")
        lines.append("capability_summary=\(capabilityCard.summary)")
        if capabilityCard.badges.isEmpty {
            lines.append("capability_badges=\(exportStrings.none)")
        } else {
            lines.append(
                "capability_badges=" + capabilityCard.badges.map { badge in
                    "\(badge.title){\(badge.tone.rawValue)}"
                }.joined(separator: ", ")
            )
        }
        if capabilityCard.insights.isEmpty {
            lines.append("capability_insights=\(exportStrings.none)")
        } else {
            lines.append(
                "capability_insights:\n" + capabilityCard.insights.map { insight in
                    "\(insight.label)=\(insight.value)"
                }.joined(separator: "\n")
            )
        }
        if capabilityCard.notes.isEmpty {
            lines.append("capability_notes=\(exportStrings.none)")
        } else {
            lines.append("capability_notes:\n" + capabilityCard.notes.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    private static func loadOperatorChannelLiveTestSnapshot(
        adminToken: String,
        grpcPort: Int
    ) async -> OperatorChannelLiveTestSnapshot {
        let normalizedAdminToken = adminToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let adminBaseURL = operatorChannelAdminBaseURL(grpcPort: grpcPort)
        guard !normalizedAdminToken.isEmpty, grpcPort > 0 else {
            return OperatorChannelLiveTestSnapshot(
                sourceStatus: "skipped",
                adminBaseURL: adminBaseURL,
                fetchErrors: ["missing_admin_token_or_grpc_port"],
                readinessRows: [],
                runtimeRows: [],
                reports: []
            )
        }

        async let readinessResult: OperatorChannelFetchResult<[HubOperatorChannelOnboardingDeliveryReadiness]> =
            loadOperatorChannelFetchResult(label: "provider_readiness", defaultValue: []) {
                try await OperatorChannelsOnboardingHTTPClient.listProviderReadiness(
                    adminToken: normalizedAdminToken,
                    grpcPort: grpcPort
                )
            }
        async let runtimeResult: OperatorChannelFetchResult<[HubOperatorChannelProviderRuntimeStatus]> =
            loadOperatorChannelFetchResult(label: "provider_runtime_status", defaultValue: []) {
                try await OperatorChannelsOnboardingHTTPClient.listProviderRuntimeStatus(
                    adminToken: normalizedAdminToken,
                    grpcPort: grpcPort
                )
            }
        async let ticketResult: OperatorChannelFetchResult<[HubOperatorChannelOnboardingTicket]> =
            loadOperatorChannelFetchResult(label: "onboarding_tickets", defaultValue: []) {
                try await OperatorChannelsOnboardingHTTPClient.listTickets(
                    adminToken: normalizedAdminToken,
                    grpcPort: grpcPort
                )
            }

        let (readiness, runtime, ticketList) = await (readinessResult, runtimeResult, ticketResult)
        var fetchErrors = operatorChannelUniqueNormalizedStrings([
            readiness.errorDescription,
            runtime.errorDescription,
            ticketList.errorDescription,
        ])
        let anyLoaded = readiness.loaded || runtime.loaded || ticketList.loaded
        guard anyLoaded else {
            return OperatorChannelLiveTestSnapshot(
                sourceStatus: "unavailable",
                adminBaseURL: adminBaseURL,
                fetchErrors: fetchErrors,
                readinessRows: readiness.value,
                runtimeRows: runtime.value,
                reports: []
            )
        }

        let ticketIDsByProvider = preferredOperatorChannelTicketIDsByProvider(ticketList.value)
        var detailsByProvider: [String: HubOperatorChannelOnboardingTicketDetail] = [:]
        for provider in sortOperatorChannelProviderIDs(Array(ticketIDsByProvider.keys)) {
            guard let ticketID = ticketIDsByProvider[provider], !ticketID.isEmpty else { continue }
            do {
                detailsByProvider[provider] = try await OperatorChannelsOnboardingHTTPClient.getTicket(
                    ticketId: ticketID,
                    adminToken: normalizedAdminToken,
                    grpcPort: grpcPort
                )
            } catch {
                fetchErrors.append("ticket_detail[\(provider)]: \((error as NSError).localizedDescription)")
            }
        }
        fetchErrors = operatorChannelUniqueNormalizedStrings(fetchErrors)

        let providerIDs = operatorChannelReportProviderIDs(
            readinessRows: readiness.value,
            runtimeRows: runtime.value,
            tickets: ticketList.value
        )
        guard !providerIDs.isEmpty else {
            return OperatorChannelLiveTestSnapshot(
                sourceStatus: "empty",
                adminBaseURL: adminBaseURL,
                fetchErrors: fetchErrors,
                readinessRows: readiness.value,
                runtimeRows: runtime.value,
                reports: []
            )
        }

        var reports: [HubOperatorChannelLiveTestEvidenceReport] = []
        for provider in providerIDs {
            let readinessRow = readiness.value.first { operatorChannelNormalizedProvider($0.provider) == provider }
            let runtimeRow = runtime.value.first { operatorChannelNormalizedProvider($0.provider) == provider }
            let detail = detailsByProvider[provider]
            let performedAt = operatorChannelLiveTestPerformedAt(
                ticketDetail: detail,
                runtimeStatus: runtimeRow
            )
            let fallbackReport = HubOperatorChannelLiveTestEvidenceBuilder.build(
                provider: provider,
                summary: "",
                performedAt: performedAt,
                evidenceRefs: [],
                readiness: readinessRow,
                runtimeStatus: runtimeRow,
                ticketDetail: detail,
                adminBaseURL: adminBaseURL,
                outputPath: ""
            )

            var report = fallbackReport
            do {
                report = try await loadHubOperatorChannelLiveTestReport(
                    provider: provider,
                    ticketId: detail?.ticket.ticketId ?? "",
                    fallbackReport: fallbackReport,
                    performedAt: performedAt,
                    adminToken: normalizedAdminToken,
                    grpcPort: grpcPort
                )
            } catch {
                fetchErrors.append("live_test_evidence[\(provider)]: \((error as NSError).localizedDescription)")
            }
            reports.append(report)
        }

        return OperatorChannelLiveTestSnapshot(
            sourceStatus: "ok",
            adminBaseURL: adminBaseURL,
            fetchErrors: operatorChannelUniqueNormalizedStrings(fetchErrors),
            readinessRows: readiness.value,
            runtimeRows: runtime.value,
            reports: sortOperatorChannelLiveTestReports(reports)
        )
    }

    private static func loadOperatorChannelFetchResult<Value: Sendable>(
        label: String,
        defaultValue: Value,
        operation: @escaping @Sendable () async throws -> Value
    ) async -> OperatorChannelFetchResult<Value> {
        do {
            return OperatorChannelFetchResult(
                loaded: true,
                value: try await operation(),
                errorDescription: ""
            )
        } catch {
            return OperatorChannelFetchResult(
                loaded: false,
                value: defaultValue,
                errorDescription: "\(label): \((error as NSError).localizedDescription)"
            )
        }
    }

    private static func loadHubOperatorChannelLiveTestReport(
        provider: String,
        ticketId: String,
        fallbackReport: HubOperatorChannelLiveTestEvidenceReport,
        performedAt: Date,
        adminToken: String,
        grpcPort: Int
    ) async throws -> HubOperatorChannelLiveTestEvidenceReport {
        do {
            let serverReport = try await OperatorChannelsOnboardingHTTPClient.getLiveTestEvidenceReport(
                provider: provider,
                ticketId: ticketId,
                verdict: fallbackReport.operatorVerdict,
                summary: fallbackReport.summary,
                performedAt: performedAt,
                evidenceRefs: [],
                requiredNextStep: fallbackReport.requiredNextStep,
                adminToken: adminToken,
                grpcPort: grpcPort
            )
            return mergedOperatorChannelLiveTestReport(serverReport, fallback: fallbackReport)
        } catch {
            guard !OperatorChannelsOnboardingHTTPClient.supportsLegacyLiveTestEvidenceFallback(for: error) else {
                return fallbackReport
            }
            throw error
        }
    }

    private static func mergedOperatorChannelLiveTestReport(
        _ serverReport: HubOperatorChannelLiveTestEvidenceReport,
        fallback: HubOperatorChannelLiveTestEvidenceReport
    ) -> HubOperatorChannelLiveTestEvidenceReport {
        var merged = serverReport
        if merged.adminBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.adminBaseURL = fallback.adminBaseURL
        }
        if merged.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.summary = fallback.summary
        }
        if merged.requiredNextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.requiredNextStep = fallback.requiredNextStep
        }
        if merged.repairHints.isEmpty {
            merged.repairHints = fallback.repairHints
        }
        if merged.checks.isEmpty {
            merged.checks = fallback.checks
        }
        if merged.onboardingSnapshot == HubOperatorChannelLiveTestEvidenceOnboardingSnapshot(ticket: nil, latestDecision: nil, automationState: nil) {
            merged.onboardingSnapshot = fallback.onboardingSnapshot
        }
        return merged
    }

    private static func operatorChannelAdminBaseURL(grpcPort: Int) -> String {
        guard grpcPort > 0 else { return "" }
        return "http://127.0.0.1:\(OperatorChannelsOnboardingHTTPClient.pairingPort(grpcPort: grpcPort))"
    }

    private static func preferredOperatorChannelTicketIDsByProvider(
        _ tickets: [HubOperatorChannelOnboardingTicket]
    ) -> [String: String] {
        let grouped = Dictionary(grouping: tickets) { operatorChannelNormalizedProvider($0.provider) }
        var result: [String: String] = [:]
        for (provider, rows) in grouped {
            let normalizedProvider = operatorChannelNormalizedProvider(provider)
            guard !normalizedProvider.isEmpty else { continue }
            let selected = rows.sorted(by: preferredOperatorChannelTicketSort).first
            let ticketID = selected?.ticketId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !ticketID.isEmpty else { continue }
            result[normalizedProvider] = ticketID
        }
        return result
    }

    private static func preferredOperatorChannelTicketSort(
        _ lhs: HubOperatorChannelOnboardingTicket,
        _ rhs: HubOperatorChannelOnboardingTicket
    ) -> Bool {
        if lhs.isOpen != rhs.isOpen {
            return lhs.isOpen && !rhs.isOpen
        }
        if lhs.updatedAtMs != rhs.updatedAtMs {
            return lhs.updatedAtMs > rhs.updatedAtMs
        }
        if lhs.createdAtMs != rhs.createdAtMs {
            return lhs.createdAtMs > rhs.createdAtMs
        }
        return lhs.ticketId.localizedCaseInsensitiveCompare(rhs.ticketId) == .orderedAscending
    }

    private static func operatorChannelReportProviderIDs(
        readinessRows: [HubOperatorChannelOnboardingDeliveryReadiness],
        runtimeRows: [HubOperatorChannelProviderRuntimeStatus],
        tickets: [HubOperatorChannelOnboardingTicket]
    ) -> [String] {
        let providers = Set(
            readinessRows.map { operatorChannelNormalizedProvider($0.provider) }
            + runtimeRows.map { operatorChannelNormalizedProvider($0.provider) }
            + tickets.map { operatorChannelNormalizedProvider($0.provider) }
        )
        return sortOperatorChannelProviderIDs(providers.filter { !$0.isEmpty })
    }

    private static func sortOperatorChannelLiveTestReports(
        _ reports: [HubOperatorChannelLiveTestEvidenceReport]
    ) -> [HubOperatorChannelLiveTestEvidenceReport] {
        let order = Dictionary(uniqueKeysWithValues: HubOperatorChannelProviderSetupGuide.supportedProviders.enumerated().map { index, provider in
            (provider, index)
        })
        return reports.sorted { lhs, rhs in
            let lhsProvider = operatorChannelNormalizedProvider(lhs.provider)
            let rhsProvider = operatorChannelNormalizedProvider(rhs.provider)
            let lhsRank = order[lhsProvider] ?? Int.max
            let rhsRank = order[rhsProvider] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhsProvider.localizedCaseInsensitiveCompare(rhsProvider) == .orderedAscending
        }
    }

    private static func sortOperatorChannelProviderIDs<S: Sequence>(_ providers: S) -> [String] where S.Element == String {
        let order = Dictionary(uniqueKeysWithValues: HubOperatorChannelProviderSetupGuide.supportedProviders.enumerated().map { index, provider in
            (provider, index)
        })
        return Array(providers).sorted { lhs, rhs in
            let normalizedLHS = operatorChannelNormalizedProvider(lhs)
            let normalizedRHS = operatorChannelNormalizedProvider(rhs)
            let lhsRank = order[normalizedLHS] ?? Int.max
            let rhsRank = order[normalizedRHS] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return normalizedLHS.localizedCaseInsensitiveCompare(normalizedRHS) == .orderedAscending
        }
    }

    private static func operatorChannelLiveTestSummaryBlock(
        _ report: HubOperatorChannelLiveTestEvidenceReport
    ) -> String {
        var lines: [String] = []
        let provider = report.provider.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(
            "provider=\(provider.isEmpty ? exportStrings.unknown : provider) derived_status=\(report.derivedStatus.isEmpty ? "unknown" : report.derivedStatus) verdict=\(report.operatorVerdict.isEmpty ? "unknown" : report.operatorVerdict) live_test_success=\(report.liveTestSuccess ? "1" : "0")"
        )
        lines.append("summary=\(report.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? exportStrings.none : report.summary)")
        lines.append(
            "required_next_step=\(report.requiredNextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? exportStrings.none : report.requiredNextStep)"
        )
        let repairHints = operatorChannelUniqueNormalizedStrings(report.repairHints)
        lines.append("repair_hints=\(exportStrings.repairHintsSummary(repairHints))")
        if report.checks.isEmpty {
            lines.append("checks=\(exportStrings.none)")
        } else {
            lines.append(
                "checks:\n" +
                report.checks.map { check in
                    "\(check.name)=\(check.status)"
                }.joined(separator: "\n")
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func operatorChannelLiveTestPerformedAt(
        ticketDetail: HubOperatorChannelOnboardingTicketDetail?,
        runtimeStatus: HubOperatorChannelProviderRuntimeStatus?
    ) -> Date {
        let firstSmokeAt = Double(ticketDetail?.automationState?.firstSmoke?.updatedAtMs ?? 0) / 1000.0
        let runtimeUpdatedAt = Double(runtimeStatus?.updatedAtMs ?? 0) / 1000.0
        let ticketUpdatedAt = Double(ticketDetail?.ticket.updatedAtMs ?? 0) / 1000.0
        let bestTimestamp = max(firstSmokeAt, max(runtimeUpdatedAt, ticketUpdatedAt))
        guard bestTimestamp > 0 else { return Date() }
        return Date(timeIntervalSince1970: bestTimestamp)
    }

    private static func operatorChannelNormalizedProvider(_ provider: String) -> String {
        provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func operatorChannelOnboardingSourcePath(adminBaseURL: String) -> String {
        let normalized = adminBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "hub://admin/operator-channels" }
        return normalized + "/admin/operator-channels"
    }

    private static func operatorChannelUniqueNormalizedStrings(_ values: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for raw in values {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            guard seen.insert(value).inserted else { continue }
            out.append(value)
        }
        return out
    }

    private static func localRuntimeOperationsSummary(
        status: AIRuntimeStatus?,
        models: [HubModel],
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot,
        targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot
    ) -> LocalRuntimeOperationsSummary {
        let localModels = localRuntimeModels(models)
        let currentTargetsByModelID = localRuntimeCurrentTargetsByModelID(
            status: status,
            models: localModels,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreferencesSnapshot: targetPreferencesSnapshot
        )
        return LocalRuntimeOperationsSummaryBuilder.build(
            status: status,
            models: localModels,
            currentTargetsByModelID: currentTargetsByModelID
        )
    }

    private static func localRuntimeOperationsExport(
        summary: LocalRuntimeOperationsSummary,
        status: AIRuntimeStatus?,
        models: [HubModel],
        currentTargetsByModelID: [String: LocalModelRuntimeRequestContext]
    ) -> LocalRuntimeOperationsExport {
        let modelByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        let currentTargetRows = models.map { model in
            currentTargetExport(
                model: model,
                requestContext: currentTargetsByModelID[model.id]
            )
        }
        let targetRowsByModelID = Dictionary(
            uniqueKeysWithValues: currentTargetRows.map { ($0.modelID, $0) }
        )
        let summaryRowsByInstanceKey = Dictionary(
            uniqueKeysWithValues: summary.instanceRows.map { ($0.instanceKey, $0) }
        )
        let loadedInstanceRows = localRuntimeLoadedInstances(status: status).map { instance in
            let summaryRow = summaryRowsByInstanceKey[instance.instanceKey]
            let model = modelByID[instance.modelId]
            let modelName = displayModelName(modelID: instance.modelId, model: model)
            let providerID = summaryRow?.providerID ?? localRuntimeProviderID(from: instance.instanceKey)
            return LocalRuntimeOperationsExport.LoadedInstanceRow(
                providerID: providerID,
                modelID: instance.modelId,
                modelName: modelName,
                instanceKey: instance.instanceKey,
                shortInstanceKey: summaryRow?.shortInstanceKey ?? localRuntimeShortInstanceKey(instance.instanceKey),
                taskSummary: summaryRow?.taskSummary ?? localRuntimeTaskSummary(instance.taskKinds),
                loadSummary: summaryRow?.loadSummary ?? localRuntimeLoadSummary(instance),
                detailSummary: summaryRow?.detailSummary ?? providerID,
                isCurrentTarget: summaryRow?.isCurrentTarget ?? false,
                currentTargetSummary: summaryRow?.currentTargetSummary ?? "",
                canUnload: summaryRow?.canUnload ?? LocalRuntimeProviderPolicy.supportsUnload(
                    providerID: providerID,
                    taskKinds: instance.taskKinds,
                    providerStatus: status?.providerStatus(providerID),
                    residencyScope: instance.residencyScope,
                    residency: instance.residency
                ),
                canEvict: summaryRow?.canEvict ?? false,
                loadedInstance: instance,
                currentTarget: targetRowsByModelID[instance.modelId]
            )
        }
        return LocalRuntimeOperationsExport(
            runtimeSummary: summary.runtimeSummary,
            queueSummary: summary.queueSummary,
            loadedSummary: summary.loadedSummary,
            monitorStale: summary.monitorStale,
            providers: summary.providerRows.map {
                LocalRuntimeOperationsExport.ProviderRow(
                    providerID: $0.providerID,
                    stateLabel: $0.stateLabel,
                    queueSummary: $0.queueSummary,
                    detailSummary: $0.detailSummary
                )
            },
            currentTargets: currentTargetRows,
            loadedInstances: loadedInstanceRows
        )
    }

    private static func currentTargetExport(
        model: HubModel,
        requestContext: LocalModelRuntimeRequestContext?
    ) -> LocalRuntimeOperationsExport.CurrentTargetRow {
        let resolvedContext = requestContext ?? LocalModelRuntimeRequestContext(
            providerID: LocalModelRuntimeActionPlanner.providerID(for: model),
            modelID: model.id,
            deviceID: "",
            instanceKey: "",
            loadProfileHash: "",
            predictedLoadProfileHash: "",
            effectiveContextLength: 0,
            loadProfileOverride: nil,
            effectiveLoadProfile: nil,
            source: "unknown"
        )
        return LocalRuntimeOperationsExport.CurrentTargetRow(
            modelID: model.id,
            modelName: displayModelName(modelID: model.id, model: model),
            providerID: resolvedContext.providerID,
            target: resolvedContext,
            uiSummary: resolvedContext.uiSummary,
            technicalSummary: resolvedContext.technicalSummary,
            loadSummary: resolvedContext.technicalLoadProfileSummary,
            preferredBenchHash: resolvedContext.preferredBenchHash
        )
    }

    private static func localRuntimeCurrentTargetsByModelID(
        status: AIRuntimeStatus?,
        models: [HubModel],
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot,
        targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot
    ) -> [String: LocalModelRuntimeRequestContext] {
        Dictionary(
            uniqueKeysWithValues: models.map { model in
                let targetPreference = targetPreferencesSnapshot.preferences.first(where: { $0.modelId == model.id })
                let requestContext = LocalModelRuntimeRequestContextResolver.resolve(
                    model: model,
                    runtimeStatus: status,
                    pairedProfilesSnapshot: pairedProfilesSnapshot,
                    targetPreference: targetPreference
                )
                return (model.id, requestContext)
            }
        )
    }

    private static func localRuntimeModels(_ models: [HubModel]) -> [HubModel] {
        models
            .filter { !LocalModelRuntimeActionPlanner.isRemoteModel($0) }
            .sorted {
                let lhsName = displayModelName(modelID: $0.id, model: $0)
                let rhsName = displayModelName(modelID: $1.id, model: $1)
                let nameOrder = lhsName.localizedCaseInsensitiveCompare(rhsName)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
            }
    }

    private static func localRuntimeLoadedInstances(status: AIRuntimeStatus?) -> [AIRuntimeLoadedInstance] {
        if let monitor = status?.monitorSnapshot, !monitor.loadedInstances.isEmpty {
            return monitor.loadedInstances.sorted(by: localRuntimeIsNewerLoadedInstance)
        }
        let rows = status?.providers.values.flatMap(\.loadedInstances) ?? []
        var deduped: [AIRuntimeLoadedInstance] = []
        var seen = Set<String>()
        for row in rows.sorted(by: localRuntimeIsNewerLoadedInstance) {
            guard seen.insert(row.instanceKey).inserted else { continue }
            deduped.append(row)
        }
        return deduped
    }

    private static func localRuntimeIsNewerLoadedInstance(
        _ lhs: AIRuntimeLoadedInstance,
        _ rhs: AIRuntimeLoadedInstance
    ) -> Bool {
        if lhs.lastUsedAt == rhs.lastUsedAt {
            if lhs.loadedAt == rhs.loadedAt {
                return lhs.instanceKey < rhs.instanceKey
            }
            return lhs.loadedAt > rhs.loadedAt
        }
        return lhs.lastUsedAt > rhs.lastUsedAt
    }

    private static func localRuntimeProviderID(from instanceKey: String) -> String {
        let token = instanceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prefix = token.split(separator: ":").first, !prefix.isEmpty else {
            return ""
        }
        return String(prefix)
    }

    private static func localRuntimeShortInstanceKey(_ instanceKey: String) -> String {
        let token = instanceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "" }
        let suffix = String(token.split(separator: ":").last ?? Substring(token))
        return String(suffix.prefix(8))
    }

    private static func localRuntimeTaskSummary(_ taskKinds: [String]) -> String {
        let normalized = LocalModelCapabilityDefaults.normalizedStringList(taskKinds, fallback: [])
        guard !normalized.isEmpty else { return exportStrings.unknown }
        return normalized.map { LocalTaskRoutingCatalog.shortTitle(for: $0) }.joined(separator: ", ")
    }

    private static func localRuntimeLoadSummary(_ instance: AIRuntimeLoadedInstance) -> String {
        var parts: [String] = []
        if instance.currentContextLength > 0 {
            parts.append(exportStrings.runtimeLoadContext(instance.currentContextLength))
        }
        if instance.maxContextLength > instance.currentContextLength,
           instance.maxContextLength > 0 {
            parts.append(exportStrings.runtimeLoadMaxContext(instance.maxContextLength))
        }
        if let ttl = instance.ttl ?? instance.loadConfig?.ttl {
            parts.append(exportStrings.runtimeLoadTTL(ttl))
        }
        if let parallel = instance.loadConfig?.parallel {
            parts.append(exportStrings.runtimeLoadParallel(parallel))
        }
        if let imageMaxDimension = instance.loadConfig?.vision?.imageMaxDimension {
            parts.append(exportStrings.runtimeLoadImageMaxDimension(imageMaxDimension))
        }
        let hash = shortHash(instance.loadConfigHash)
        if hash != "none" {
            parts.append(exportStrings.runtimeLoadConfigHash(hash))
        }
        return exportStrings.runtimeLoadSummary(parts)
    }

    private static func displayModelName(modelID: String, model: HubModel?) -> String {
        let resolved = model?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return resolved.isEmpty ? modelID : resolved
    }

    private static func runtimeOpsSummaryBlock(_ summary: LocalRuntimeOperationsSummary) -> String {
        var lines: [String] = []
        lines.append("runtime_summary=\(summary.runtimeSummary)")
        lines.append("queue_summary=\(summary.queueSummary)")
        lines.append("loaded_summary=\(summary.loadedSummary)")
        lines.append("monitor_stale=\(summary.monitorStale ? "1" : "0")")
        lines.append("providers:")
        if summary.providerRows.isEmpty {
            lines.append(exportStrings.none)
        } else {
            lines.append(contentsOf: summary.providerRows.map { row in
                "provider=\(row.providerID) state=\(row.stateLabel) queue=\(row.queueSummary) detail=\(row.detailSummary)"
            })
        }
        return lines.joined(separator: "\n")
    }

    private static func runtimeOpsInstanceLine(_ row: LocalRuntimeOperationsSummary.InstanceRow) -> String {
        var parts: [String] = [
            "model_id=\(row.modelID)",
            "model_name=\(row.modelName)",
            "provider=\(row.providerID)",
            "instance_ref=\(row.shortInstanceKey.isEmpty ? row.instanceKey : row.shortInstanceKey)",
            "tasks=\(row.taskSummary)",
            "load=\(row.loadSummary)",
            "detail=\(row.detailSummary)",
        ]
        if row.isCurrentTarget, !row.currentTargetSummary.isEmpty {
            parts.append("current_target=\(row.currentTargetSummary)")
        }
        return parts.joined(separator: " ")
    }

    private static func localRuntimeConsoleCurrentTargetLine(
        _ row: LocalRuntimeOperationsExport.CurrentTargetRow,
        providerDiagnosis: AIRuntimeProviderDiagnosis?
    ) -> String {
        var parts: [String] = [
            "model_id=\(row.modelID)",
            "model_name=\(row.modelName)",
            "provider=\(row.providerID)",
            "route=\(localRuntimeConsoleTargetRoute(row.target))",
            "target=\(row.uiSummary.isEmpty ? exportStrings.none : row.uiSummary)",
            "detail=\(row.technicalSummary.isEmpty ? exportStrings.none : row.technicalSummary)",
            "load=\(row.loadSummary.isEmpty ? "none" : row.loadSummary)",
            "profile=\(shortHash(row.preferredBenchHash))",
            "provider_state=\(providerDiagnosis?.state.rawValue ?? "unknown")",
            "fallback=\(providerDiagnosis?.fallbackUsed == true ? "1" : "0")",
        ]
        if let hint = localRuntimeConsoleTargetHint(
            requestContext: row.target,
            providerDiagnosis: providerDiagnosis
        ) {
            parts.append("hint=\(hint)")
        }
        return parts.joined(separator: " ")
    }

    private static func localRuntimeConsoleActiveTaskLine(
        _ task: AIRuntimeMonitorActiveTask,
        model: HubModel?,
        providerDiagnosis: AIRuntimeProviderDiagnosis?,
        queuedTaskCount: Int
    ) -> String {
        let modelName = displayModelName(modelID: task.modelId, model: model)
        let shortInstanceKey = localRuntimeShortInstanceKey(task.instanceKey)
        var parts: [String] = [
            "provider=\(task.provider)",
            "task_kind=\(task.taskKind.isEmpty ? "unknown" : task.taskKind)",
            "model_id=\(task.modelId.isEmpty ? "(none)" : task.modelId)",
            "model_name=\(modelName)",
            "request_id=\(task.requestId.isEmpty ? "(none)" : task.requestId)",
            "device_id=\(task.deviceId.isEmpty ? "(none)" : task.deviceId)",
            "lease_id=\(task.leaseId.isEmpty ? "(none)" : task.leaseId)",
            "instance_ref=\(shortInstanceKey.isEmpty ? "(none)" : shortInstanceKey)",
            "age_sec=\(localRuntimeTaskAgeSeconds(task.startedAt))",
            "summary=\(localRuntimeConsoleActiveTaskSummary(task, providerDiagnosis: providerDiagnosis, queuedTaskCount: queuedTaskCount))",
        ]
        if !task.loadConfigHash.isEmpty {
            parts.append("profile=\(shortHash(task.loadConfigHash))")
        }
        if let hint = localRuntimeConsoleActiveTaskHint(
            task,
            providerDiagnosis: providerDiagnosis,
            queuedTaskCount: queuedTaskCount
        ) {
            parts.append("hint=\(hint)")
        }
        return parts.joined(separator: " ")
    }

    private static func localRuntimeConsoleTargetRoute(_ requestContext: LocalModelRuntimeRequestContext) -> String {
        let source = requestContext.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if source.hasPrefix("selected_") || !requestContext.instanceKey.isEmpty {
            return "pinned"
        }
        return "automatic"
    }

    private static func localRuntimeConsoleTargetHint(
        requestContext: LocalModelRuntimeRequestContext,
        providerDiagnosis: AIRuntimeProviderDiagnosis?
    ) -> String? {
        if let providerDiagnosis {
            switch providerDiagnosis.state {
            case .down:
                return HubUIStrings.Models.Runtime.Target.providerDownHint
            case .stale:
                return HubUIStrings.Models.Runtime.Target.staleHint
            case .ready:
                break
            }
            if providerDiagnosis.fallbackUsed {
                return HubUIStrings.Models.Runtime.Target.fallbackHint
            }
        } else {
            return HubUIStrings.Models.Runtime.Target.noProviderPathHint
        }

        let source = requestContext.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if source == "model_default" {
            return HubUIStrings.Models.Runtime.Target.defaultRouteHint
        }
        if source == "loaded_instance_latest" {
            return HubUIStrings.Models.Runtime.Target.latestInstanceHint
        }
        return nil
    }

    private static func localRuntimeConsoleActiveTaskSummary(
        _ task: AIRuntimeMonitorActiveTask,
        providerDiagnosis: AIRuntimeProviderDiagnosis?,
        queuedTaskCount: Int
    ) -> String {
        var parts: [String] = [HubUIStrings.Models.Runtime.Task.summary(provider: task.provider.uppercased())]
        if !task.deviceId.isEmpty {
            parts.append(HubUIStrings.Models.Runtime.Task.deviceOnline)
        }
        if !task.instanceKey.isEmpty {
            parts.append(HubUIStrings.Models.Runtime.Task.residentInstance)
        }
        let ageSeconds = localRuntimeTaskAgeSeconds(task.startedAt)
        if ageSeconds >= 900 {
            parts.append(HubUIStrings.Models.Runtime.Task.runningLong)
        } else if ageSeconds >= 180 {
            parts.append(HubUIStrings.Models.Runtime.Task.watchSuggested)
        }
        if queuedTaskCount > 0 {
            parts.append(HubUIStrings.Models.Runtime.Task.queuedBehind(queuedTaskCount))
        }
        if providerDiagnosis?.fallbackUsed == true {
            parts.append(HubUIStrings.Models.Runtime.Task.fallbackUsed)
        }
        return exportStrings.activeTaskSummary(parts)
    }

    private static func localRuntimeConsoleActiveTaskHint(
        _ task: AIRuntimeMonitorActiveTask,
        providerDiagnosis: AIRuntimeProviderDiagnosis?,
        queuedTaskCount: Int
    ) -> String? {
        if providerDiagnosis?.state == .down {
            return HubUIStrings.Models.Runtime.Task.providerDownHint
        }
        if providerDiagnosis?.state == .stale {
            return HubUIStrings.Models.Runtime.Task.staleHint
        }
        let ageSeconds = localRuntimeTaskAgeSeconds(task.startedAt)
        if ageSeconds >= 900 {
            return HubUIStrings.Models.Runtime.Task.longRunningHint
        }
        if queuedTaskCount > 0 {
            return HubUIStrings.Models.Runtime.Task.queuedHint(queuedTaskCount)
        }
        if providerDiagnosis?.fallbackUsed == true {
            return HubUIStrings.Models.Runtime.Task.fallbackHint
        }
        return nil
    }

    private static func localRuntimeTaskAgeSeconds(_ startedAt: Double) -> Int {
        guard startedAt > 0 else { return 0 }
        return max(0, Int(Date().timeIntervalSince1970 - startedAt))
    }

    private static func benchLoadSummary(_ benchResult: ModelBenchResult) -> String {
        var parts: [String] = []
        if let effectiveContextLength = benchResult.effectiveContextLength, effectiveContextLength > 0 {
            parts.append(exportStrings.benchContext(effectiveContextLength))
        }
        let profile = shortHash(benchResult.loadProfileHash)
        if profile != "none" {
            parts.append(exportStrings.benchProfile(profile))
        }
        return exportStrings.benchLoadSummary(parts)
    }

    private static func shortHash(_ value: String) -> String {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "none" }
        return String(token.prefix(8))
    }

    private static func runSQLiteQuickCheck(dbPath: String) -> SQLiteQuickCheckResult {
        let started = Date().timeIntervalSince1970
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = [
            "-readonly",
            "-batch",
            "-cmd", "PRAGMA busy_timeout=1500;",
            dbPath,
            "PRAGMA quick_check;"
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        do {
            try p.run()
            p.waitUntilExit()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            return SQLiteQuickCheckResult(
                launchError: "",
                exitCode: p.terminationStatus,
                elapsedMs: Int64((Date().timeIntervalSince1970 - started) * 1000.0),
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: String(data: errData, encoding: .utf8) ?? ""
            )
        } catch {
            return SQLiteQuickCheckResult(
                launchError: error.localizedDescription,
                exitCode: -1,
                elapsedMs: Int64((Date().timeIntervalSince1970 - started) * 1000.0),
                stdout: "",
                stderr: ""
            )
        }
    }

    private static func limitForReport(_ text: String, maxChars: Int = 8_000) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= maxChars {
            return t
        }
        return String(t.suffix(maxChars))
    }

    private static func redactDataForExport(_ data: Data, kind: FileKind) -> Data {
        if kind == .json {
            if let redactedJson = redactJsonBytes(data) {
                return redactedJson
            }
            // Fall back to text redaction.
        }
        guard let s = String(data: data, encoding: .utf8) else { return data }
        let out = redactTextSecrets(s)
        return Data(out.utf8)
    }

    private static func redactJsonBytes(_ data: Data) -> Data? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let redacted = redactJsonObject(obj)
        guard let out = try? JSONSerialization.data(withJSONObject: redacted, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: out, encoding: .utf8) else {
            return nil
        }
        return Data((s + "\n").utf8)
    }

    private static func redactJsonObject(_ obj: Any) -> Any {
        if let arr = obj as? [Any] {
            return arr.map { redactJsonObject($0) }
        }
        if let dict = obj as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict {
                let kl = k.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if shouldRedactJsonKey(kl) {
                    out[k] = "[REDACTED]"
                    continue
                }
                if let s = v as? String {
                    out[k] = redactTextSecrets(s)
                    continue
                }
                out[k] = redactJsonObject(v)
            }
            return out
        }
        if let s = obj as? String {
            return redactTextSecrets(s)
        }
        return obj
    }

    private static func shouldRedactJsonKey(_ lowerKey: String) -> Bool {
        if lowerKey == "token" { return true }
        if lowerKey == "client_token" { return true }
        if lowerKey == "admin_token" { return true }
        if lowerKey == "access_token" { return true }
        if lowerKey == "refresh_token" { return true }
        if lowerKey == "api_key" { return true }
        if lowerKey == "apikey" { return true }
        if lowerKey == "secret" { return true }
        if lowerKey == "password" { return true }
        if lowerKey.contains("authorization") { return true }
        if lowerKey.contains("cookie") { return true }
        if lowerKey.contains("password") { return true }
        if lowerKey.hasSuffix("_token") { return true }
        if lowerKey.hasSuffix("_secret") { return true }
        if lowerKey.contains("private_key") { return true }
        if lowerKey == "request_payload" { return true }
        if lowerKey == "payload" { return true }
        if lowerKey == "prompt" { return true }
        if lowerKey == "messages" { return true }
        if lowerKey == "input_path" { return true }
        if lowerKey == "file_path" { return true }
        if lowerKey == "image_path" { return true }
        if lowerKey == "audio_path" { return true }
        if lowerKey == "video_path" { return true }
        if lowerKey == "account_id" { return true }
        if lowerKey == "external_user_id" { return true }
        if lowerKey == "external_tenant_id" { return true }
        if lowerKey == "conversation_id" { return true }
        if lowerKey == "thread_key" { return true }
        if lowerKey == "first_message_preview" { return true }
        if lowerKey == "proposed_scope_id" { return true }
        if lowerKey == "scope_id" { return true }
        if lowerKey == "hub_user_id" { return true }
        if lowerKey == "approved_by_hub_user_id" { return true }
        if lowerKey == "preferred_device_id" { return true }
        if lowerKey == "project_id" { return true }
        if lowerKey == "binding_id" { return true }
        if lowerKey == "ack_outbox_item_id" { return true }
        if lowerKey == "smoke_outbox_item_id" { return true }
        if lowerKey == "provider_message_ref" { return true }
        if lowerKey == "identity_actor_ref" { return true }
        if lowerKey == "channel_binding_id" { return true }
        if lowerKey == "revoked_by_hub_user_id" { return true }
        if lowerKey == "audit_ref" { return true }
        if lowerKey == "last_request_id" { return true }
        return false
    }

    private static func redactPathForManifest(_ path: String) -> String {
        let s = path
        let home = SharedPaths.realHomeDirectory().path
        if !home.isEmpty, s.contains(home) {
            return s.replacingOccurrences(of: home, with: "/Users/USER")
        }
        return s
    }

    private static func redactTextSecrets(_ text: String) -> String {
        var out = text

        // User home path -> stable placeholder.
        let home = SharedPaths.realHomeDirectory().path
        if !home.isEmpty {
            out = out.replacingOccurrences(of: home, with: "/Users/USER")
        }

        // Common Hub tokens.
        out = out.replacingOccurrences(
            of: #"axhub_client_[A-Za-z0-9_\-]{10,}"#,
            with: "axhub_client_[REDACTED]",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"axhub_admin_[A-Za-z0-9_\-]{10,}"#,
            with: "axhub_admin_[REDACTED]",
            options: .regularExpression
        )

        // Generic bearer header.
        out = out.replacingOccurrences(
            of: #"(?i)\bBearer\s+[A-Za-z0-9_\-\.=]{12,}"#,
            with: "Bearer [REDACTED]",
            options: .regularExpression
        )

        // Common provider keys (defense-in-depth).
        out = out.replacingOccurrences(of: #"\bsk-[A-Za-z0-9]{20,}\b"#, with: "sk-[REDACTED]", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\bghp_[A-Za-z0-9]{36}\b"#, with: "ghp_[REDACTED]", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\bhf_[A-Za-z0-9]{20,}\b"#, with: "hf_[REDACTED]", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\bAIza[0-9A-Za-z_\-]{35}\b"#, with: "AIza[REDACTED]", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\bxox[baprs]-[0-9A-Za-z\-]{10,}\b"#, with: "xox*-REDACTED", options: .regularExpression)

        return out
    }

    static func redactTextForSharing(_ text: String) -> String {
        redactTextSecrets(text)
    }
}
