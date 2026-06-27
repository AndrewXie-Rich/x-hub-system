import Foundation
import CryptoKit
import RELFlowHubCore

extension HubDiagnosticsBundleExporter {
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

    struct ExportedFileEntry: Codable, Sendable {
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

    struct Manifest: Codable, Sendable {
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

    struct LocalRuntimeMonitorSnapshotEnvelope: Codable, Sendable {
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

    struct LocalRuntimeOperationsExport: Codable, Sendable {
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

    struct XHubLocalServiceSnapshotEnvelope: Codable, Sendable {
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

    struct XHubLocalServiceSnapshotPrimaryIssue: Codable, Sendable {
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

    struct XHubLocalServiceSnapshotDoctorProjection: Codable, Sendable {
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

    struct XHubLocalServiceRecoveryGuidanceEnvelope: Codable, Sendable {
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

    struct OperatorChannelLiveTestEvidenceEnvelope: Codable, Sendable {
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

    struct OperatorChannelFetchResult<Value: Sendable>: Sendable {
        var loaded: Bool
        var value: Value
        var errorDescription: String
    }

    struct OperatorChannelLiveTestSnapshot: Sendable {
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

    enum FileKind {
        case json
        case log
        case text
    }

    struct InputFile {
        var name: String
        var url: URL
        var fallbackURL: URL?
        var kind: FileKind
        var optional: Bool
        var redact: Bool
        var tailBytes: Int
    }
}
