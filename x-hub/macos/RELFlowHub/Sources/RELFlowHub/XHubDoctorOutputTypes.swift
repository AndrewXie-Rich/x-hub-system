import Foundation
import RELFlowHubCore

enum XHubDoctorBundleKind: String, Codable, CaseIterable, Sendable {
    case pairedSurfaceReadiness = "paired_surface_readiness"
    case providerRuntimeReadiness = "provider_runtime_readiness"
    case channelOnboardingReadiness = "channel_onboarding_readiness"
    case packageLifecycleReadiness = "package_lifecycle_readiness"
    case automationReadiness = "automation_readiness"
}

enum XHubDoctorSurface: String, Codable, CaseIterable, Sendable {
    case xtUI = "xt_ui"
    case xtExport = "xt_export"
    case hubUI = "hub_ui"
    case hubCLI = "hub_cli"
    case api = "api"
}

enum XHubDoctorProducer: String, Codable, CaseIterable, Sendable {
    case xTerminal = "x_terminal"
    case xHub = "x_hub"
    case xhubCLI = "xhub_cli"
}

enum XHubDoctorOverallState: String, Codable, CaseIterable, Sendable {
    case ready = "ready"
    case degraded = "degraded"
    case blocked = "blocked"
    case inProgress = "in_progress"
    case notSupported = "not_supported"
}

enum XHubDoctorCheckStatus: String, Codable, CaseIterable, Sendable {
    case pass = "pass"
    case fail = "fail"
    case warn = "warn"
    case skip = "skip"
}

enum XHubDoctorSeverity: String, Codable, CaseIterable, Sendable {
    case info = "info"
    case warning = "warning"
    case error = "error"
    case critical = "critical"
}

enum XHubDoctorNextStepKind: String, Codable, CaseIterable, Sendable {
    case openRepairSurface = "open_repair_surface"
    case reviewPairing = "review_pairing"
    case chooseModel = "choose_model"
    case reviewPermissions = "review_permissions"
    case repairRuntime = "repair_runtime"
    case inspectDiagnostics = "inspect_diagnostics"
    case repairSkills = "repair_skills"
    case startFirstTask = "start_first_task"
    case waitForRecovery = "wait_for_recovery"
}

enum XHubDoctorStepOwner: String, Codable, CaseIterable, Sendable {
    case user = "user"
    case humanOperator = "operator"
    case xtRuntime = "xt_runtime"
    case hubRuntime = "hub_runtime"
}

struct XHubDoctorOutputSummary: Codable, Equatable, Sendable {
    var headline: String
    var passed: Int
    var failed: Int
    var warned: Int
    var skipped: Int

    enum CodingKeys: String, CodingKey {
        case headline
        case passed
        case failed
        case warned
        case skipped
    }
}

struct XHubDoctorOutputCheckResult: Identifiable, Codable, Equatable, Sendable {
    var checkID: String
    var checkKind: String
    var status: XHubDoctorCheckStatus
    var severity: XHubDoctorSeverity
    var blocking: Bool
    var headline: String
    var message: String
    var nextStep: String
    var repairDestinationRef: String?
    var detailLines: [String]
    var observedAtMs: Int64

    var id: String { checkID }

    enum CodingKeys: String, CodingKey {
        case checkID = "check_id"
        case checkKind = "check_kind"
        case status
        case severity
        case blocking
        case headline
        case message
        case nextStep = "next_step"
        case repairDestinationRef = "repair_destination_ref"
        case detailLines = "detail_lines"
        case observedAtMs = "observed_at_ms"
    }
}

struct XHubDoctorOutputNextStep: Identifiable, Codable, Equatable, Sendable {
    var stepID: String
    var kind: XHubDoctorNextStepKind
    var label: String
    var owner: XHubDoctorStepOwner
    var blocking: Bool
    var destinationRef: String
    var instruction: String

    var id: String { stepID }

    enum CodingKeys: String, CodingKey {
        case stepID = "step_id"
        case kind
        case label
        case owner
        case blocking
        case destinationRef = "destination_ref"
        case instruction
    }
}

struct XHubDoctorOutputRouteSnapshot: Codable, Equatable, Sendable {
    var transportMode: String
    var routeLabel: String
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String

    enum CodingKeys: String, CodingKey {
        case transportMode = "transport_mode"
        case routeLabel = "route_label"
        case pairingPort = "pairing_port"
        case grpcPort = "grpc_port"
        case internetHost = "internet_host"
    }
}

struct XHubDoctorOutputReport: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xhub.doctor_output.v1"
    static let currentContractVersion = "2026-03-20"

    var schemaVersion: String
    var contractVersion: String
    var reportID: String
    var bundleKind: XHubDoctorBundleKind
    var producer: XHubDoctorProducer
    var surface: XHubDoctorSurface
    var overallState: XHubDoctorOverallState
    var summary: XHubDoctorOutputSummary
    var readyForFirstTask: Bool
    var checks: [XHubDoctorOutputCheckResult]
    var nextSteps: [XHubDoctorOutputNextStep]
    var routeSnapshot: XHubDoctorOutputRouteSnapshot?
    var generatedAtMs: Int64
    var reportPath: String
    var sourceReportSchemaVersion: String
    var sourceReportPath: String
    var currentFailureCode: String
    var currentFailureIssue: String?
    var consumedContracts: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case contractVersion = "contract_version"
        case reportID = "report_id"
        case bundleKind = "bundle_kind"
        case producer
        case surface
        case overallState = "overall_state"
        case summary
        case readyForFirstTask = "ready_for_first_task"
        case checks
        case nextSteps = "next_steps"
        case routeSnapshot = "route_snapshot"
        case generatedAtMs = "generated_at_ms"
        case reportPath = "report_path"
        case sourceReportSchemaVersion = "source_report_schema_version"
        case sourceReportPath = "source_report_path"
        case currentFailureCode = "current_failure_code"
        case currentFailureIssue = "current_failure_issue"
        case consumedContracts = "consumed_contracts"
    }
}
