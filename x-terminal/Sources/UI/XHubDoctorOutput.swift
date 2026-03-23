import Foundation

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
    var projectContextSummary: XHubDoctorOutputProjectContextSummary?
    var memoryRouteTruthSnapshot: XHubDoctorOutputMemoryRouteTruthSnapshot?
    var durableCandidateMirrorSnapshot: XHubDoctorOutputDurableCandidateMirrorSnapshot?
    var localStoreWriteSnapshot: XHubDoctorOutputLocalStoreWriteSnapshot?
    var observedAtMs: Int64

    var id: String { checkID }

    init(
        checkID: String,
        checkKind: String,
        status: XHubDoctorCheckStatus,
        severity: XHubDoctorSeverity,
        blocking: Bool,
        headline: String,
        message: String,
        nextStep: String,
        repairDestinationRef: String?,
        detailLines: [String],
        projectContextSummary: XHubDoctorOutputProjectContextSummary? = nil,
        observedAtMs: Int64,
        memoryRouteTruthSnapshot: XHubDoctorOutputMemoryRouteTruthSnapshot? = nil,
        durableCandidateMirrorSnapshot: XHubDoctorOutputDurableCandidateMirrorSnapshot? = nil,
        localStoreWriteSnapshot: XHubDoctorOutputLocalStoreWriteSnapshot? = nil
    ) {
        self.checkID = checkID
        self.checkKind = checkKind
        self.status = status
        self.severity = severity
        self.blocking = blocking
        self.headline = headline
        self.message = message
        self.nextStep = nextStep
        self.repairDestinationRef = repairDestinationRef
        self.detailLines = detailLines
        self.projectContextSummary = projectContextSummary
        self.memoryRouteTruthSnapshot = memoryRouteTruthSnapshot
        self.durableCandidateMirrorSnapshot = durableCandidateMirrorSnapshot
        self.localStoreWriteSnapshot = localStoreWriteSnapshot
        self.observedAtMs = observedAtMs
    }

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
        case projectContextSummary = "project_context_summary"
        case memoryRouteTruthSnapshot = "memory_route_truth_snapshot"
        case durableCandidateMirrorSnapshot = "durable_candidate_mirror_snapshot"
        case localStoreWriteSnapshot = "local_store_write_snapshot"
        case observedAtMs = "observed_at_ms"
    }
}

struct XHubDoctorOutputDurableCandidateMirrorSnapshot: Codable, Equatable, Sendable {
    var status: String
    var target: String
    var attempted: Bool
    var errorCode: String?
    var localStoreRole: String

    enum CodingKeys: String, CodingKey {
        case status
        case target
        case attempted
        case errorCode = "error_code"
        case localStoreRole = "local_store_role"
    }
}

struct XHubDoctorOutputLocalStoreWriteSnapshot: Codable, Equatable, Sendable {
    var personalMemoryIntent: String?
    var crossLinkIntent: String?
    var personalReviewIntent: String?

    enum CodingKeys: String, CodingKey {
        case personalMemoryIntent = "personal_memory_intent"
        case crossLinkIntent = "cross_link_intent"
        case personalReviewIntent = "personal_review_intent"
    }
}

struct XHubDoctorOutputProjectContextSummary: Codable, Equatable, Sendable {
    var sourceKind: String
    var sourceBadge: String
    var projectLabel: String?
    var statusLine: String
    var dialogueMetric: String
    var depthMetric: String
    var coverageMetric: String?
    var boundaryMetric: String?
    var dialogueLine: String
    var depthLine: String
    var coverageLine: String?
    var boundaryLine: String?

    enum CodingKeys: String, CodingKey {
        case sourceKind = "source_kind"
        case sourceBadge = "source_badge"
        case projectLabel = "project_label"
        case statusLine = "status_line"
        case dialogueMetric = "dialogue_metric"
        case depthMetric = "depth_metric"
        case coverageMetric = "coverage_metric"
        case boundaryMetric = "boundary_metric"
        case dialogueLine = "dialogue_line"
        case depthLine = "depth_line"
        case coverageLine = "coverage_line"
        case boundaryLine = "boundary_line"
    }
}

struct XHubDoctorOutputMemoryRouteTruthSnapshot: Codable, Equatable, Sendable {
    var projectionSource: String
    var completeness: String
    var requestSnapshot: XHubDoctorOutputMemoryRouteRequestSnapshot
    var resolutionChain: [XHubDoctorOutputMemoryRouteResolutionNode]
    var winningProfile: XHubDoctorOutputMemoryRouteWinningProfile
    var winningBinding: XHubDoctorOutputMemoryRouteWinningBinding
    var routeResult: XHubDoctorOutputMemoryRouteResult
    var constraintSnapshot: XHubDoctorOutputMemoryRouteConstraintSnapshot

    enum CodingKeys: String, CodingKey {
        case projectionSource = "projection_source"
        case completeness
        case requestSnapshot = "request_snapshot"
        case resolutionChain = "resolution_chain"
        case winningProfile = "winning_profile"
        case winningBinding = "winning_binding"
        case routeResult = "route_result"
        case constraintSnapshot = "constraint_snapshot"
    }
}

struct XHubDoctorOutputMemoryRouteRequestSnapshot: Codable, Equatable, Sendable {
    var jobType: String
    var mode: String
    var projectIDPresent: String
    var sensitivity: String
    var trustLevel: String
    var budgetClass: String
    var remoteAllowedByPolicy: String
    var killSwitchState: String

    enum CodingKeys: String, CodingKey {
        case jobType = "job_type"
        case mode
        case projectIDPresent = "project_id_present"
        case sensitivity
        case trustLevel = "trust_level"
        case budgetClass = "budget_class"
        case remoteAllowedByPolicy = "remote_allowed_by_policy"
        case killSwitchState = "kill_switch_state"
    }
}

struct XHubDoctorOutputMemoryRouteResolutionNode: Codable, Equatable, Sendable {
    var scopeKind: String
    var scopeRefRedacted: String
    var matched: String
    var profileID: String
    var selectionStrategy: String
    var skipReason: String

    enum CodingKeys: String, CodingKey {
        case scopeKind = "scope_kind"
        case scopeRefRedacted = "scope_ref_redacted"
        case matched
        case profileID = "profile_id"
        case selectionStrategy = "selection_strategy"
        case skipReason = "skip_reason"
    }
}

struct XHubDoctorOutputMemoryRouteWinningProfile: Codable, Equatable, Sendable {
    var resolvedProfileID: String
    var scopeKind: String
    var scopeRefRedacted: String
    var selectionStrategy: String
    var policyVersion: String
    var disabled: String

    enum CodingKeys: String, CodingKey {
        case resolvedProfileID = "resolved_profile_id"
        case scopeKind = "scope_kind"
        case scopeRefRedacted = "scope_ref_redacted"
        case selectionStrategy = "selection_strategy"
        case policyVersion = "policy_version"
        case disabled
    }
}

struct XHubDoctorOutputMemoryRouteWinningBinding: Codable, Equatable, Sendable {
    var bindingKind: String
    var bindingKey: String
    var provider: String
    var modelID: String
    var selectedByUser: String

    enum CodingKeys: String, CodingKey {
        case bindingKind = "binding_kind"
        case bindingKey = "binding_key"
        case provider
        case modelID = "model_id"
        case selectedByUser = "selected_by_user"
    }
}

struct XHubDoctorOutputMemoryRouteResult: Codable, Equatable, Sendable {
    var routeSource: String
    var routeReasonCode: String
    var fallbackApplied: String
    var fallbackReason: String
    var remoteAllowed: String
    var auditRef: String
    var denyCode: String

    enum CodingKeys: String, CodingKey {
        case routeSource = "route_source"
        case routeReasonCode = "route_reason_code"
        case fallbackApplied = "fallback_applied"
        case fallbackReason = "fallback_reason"
        case remoteAllowed = "remote_allowed"
        case auditRef = "audit_ref"
        case denyCode = "deny_code"
    }
}

struct XHubDoctorOutputMemoryRouteConstraintSnapshot: Codable, Equatable, Sendable {
    var remoteAllowedAfterUserPref: String
    var remoteAllowedAfterPolicy: String
    var budgetClass: String
    var budgetBlocked: String
    var policyBlockedRemote: String

    enum CodingKeys: String, CodingKey {
        case remoteAllowedAfterUserPref = "remote_allowed_after_user_pref"
        case remoteAllowedAfterPolicy = "remote_allowed_after_policy"
        case budgetClass = "budget_class"
        case budgetBlocked = "budget_blocked"
        case policyBlockedRemote = "policy_blocked_remote"
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

struct XHubLocalServiceSnapshotPrimaryIssue: Codable, Equatable, Sendable {
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

struct XHubLocalServiceSnapshotDoctorProjection: Codable, Equatable, Sendable {
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

struct XHubLocalServiceProviderEvidence: Codable, Equatable, Sendable {
    var providerID: String
    var serviceState: String
    var runtimeReasonCode: String
    var serviceBaseURL: String
    var executionMode: String
    var loadedInstanceCount: Int
    var queuedTaskCount: Int
    var ready: Bool

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case serviceState = "service_state"
        case runtimeReasonCode = "runtime_reason_code"
        case serviceBaseURL = "service_base_url"
        case executionMode = "execution_mode"
        case loadedInstanceCount = "loaded_instance_count"
        case queuedTaskCount = "queued_task_count"
        case ready
    }
}

struct XHubLocalServiceSnapshotReport: Codable, Equatable, Sendable {
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

struct XHubLocalServiceRecoveryGuidanceAction: Codable, Equatable, Sendable {
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

struct XHubLocalServiceRecoveryGuidanceFAQItem: Codable, Equatable, Sendable {
    var faqID: String
    var question: String
    var answer: String

    enum CodingKeys: String, CodingKey {
        case faqID = "faq_id"
        case question
        case answer
    }
}

struct XHubLocalServiceRecoveryGuidanceReport: Codable, Equatable, Sendable {
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
    var recommendedActions: [XHubLocalServiceRecoveryGuidanceAction]
    var supportFAQ: [XHubLocalServiceRecoveryGuidanceFAQItem]

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

struct XHubLocalRuntimeMonitorCurrentTargetEvidence: Codable, Equatable, Sendable {
    var modelID: String
    var modelName: String
    var providerID: String
    var uiSummary: String
    var technicalSummary: String
    var loadSummary: String

    enum CodingKeys: String, CodingKey {
        case modelID = "model_id"
        case modelName = "model_name"
        case providerID = "provider_id"
        case uiSummary = "ui_summary"
        case technicalSummary = "technical_summary"
        case loadSummary = "load_summary"
    }
}

struct XHubLocalRuntimeMonitorLoadedInstanceEvidence: Codable, Equatable, Sendable {
    var providerID: String
    var modelID: String
    var modelName: String
    var loadSummary: String
    var detailSummary: String
    var currentTargetSummary: String

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case modelID = "model_id"
        case modelName = "model_name"
        case loadSummary = "load_summary"
        case detailSummary = "detail_summary"
        case currentTargetSummary = "current_target_summary"
    }
}

struct XHubLocalRuntimeMonitorOperationsReport: Codable, Equatable, Sendable {
    var runtimeSummary: String
    var queueSummary: String
    var loadedSummary: String
    var currentTargets: [XHubLocalRuntimeMonitorCurrentTargetEvidence]
    var loadedInstances: [XHubLocalRuntimeMonitorLoadedInstanceEvidence]

    enum CodingKeys: String, CodingKey {
        case runtimeSummary = "runtime_summary"
        case queueSummary = "queue_summary"
        case loadedSummary = "loaded_summary"
        case currentTargets = "current_targets"
        case loadedInstances = "loaded_instances"
    }
}

struct XHubLocalRuntimeMonitorSnapshotReport: Codable, Equatable, Sendable {
    var schemaVersion: String
    var generatedAtMs: Int64
    var statusSource: String
    var runtimeAlive: Bool
    var monitorSummary: String
    var runtimeOperations: XHubLocalRuntimeMonitorOperationsReport?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case statusSource = "status_source"
        case runtimeAlive = "runtime_alive"
        case monitorSummary = "monitor_summary"
        case runtimeOperations = "runtime_operations"
    }
}

struct XHubDoctorOutputReport: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xhub.doctor_output.v1"
    static let currentContractVersion = "2026-03-23"

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

    static func xtReadinessBundle(
        from report: XTUnifiedDoctorReport,
        outputPath: String = XHubDoctorOutputStore.defaultXTReportURL().path,
        surface: XHubDoctorSurface = .xtUI
    ) -> XHubDoctorOutputReport {
        let checks = report.sections.map { XHubDoctorOutputCheckResult(section: $0, observedAtMs: report.generatedAtMs) }
        let nextSteps = report.sections.compactMap { XHubDoctorOutputNextStep(section: $0) }
        return XHubDoctorOutputReport(
            schemaVersion: currentSchemaVersion,
            contractVersion: currentContractVersion,
            reportID: "xhub-doctor-xt-\(surface.rawValue)-\(report.generatedAtMs)",
            bundleKind: .pairedSurfaceReadiness,
            producer: .xTerminal,
            surface: surface,
            overallState: XHubDoctorOverallState(surfaceState: report.overallState),
            summary: XHubDoctorOutputSummary(headline: report.overallSummary, checks: checks),
            readyForFirstTask: report.readyForFirstTask,
            checks: checks,
            nextSteps: nextSteps,
            routeSnapshot: XHubDoctorOutputRouteSnapshot(report.currentRoute),
            generatedAtMs: report.generatedAtMs,
            reportPath: outputPath,
            sourceReportSchemaVersion: report.schemaVersion,
            sourceReportPath: report.reportPath,
            currentFailureCode: report.currentFailureCode,
            currentFailureIssue: report.currentFailureIssue?.rawValue,
            consumedContracts: report.consumedContracts
        )
    }
}

enum XHubDoctorOutputStore {
    private static let hubReportFileName = "xhub_doctor_output_hub.json"
    private static let hubLocalServiceSnapshotFileName = "xhub_local_service_snapshot.redacted.json"
    private static let hubLocalRuntimeMonitorSnapshotFileName = "local_runtime_monitor_snapshot.redacted.json"
    private static let hubLocalServiceRecoveryGuidanceFileName =
        "xhub_local_service_recovery_guidance.redacted.json"

    static func defaultXTReportURL(workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()) -> URL {
        workspaceRoot
            .appendingPathComponent(".axcoder", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent("xhub_doctor_output_xt.json")
    }

    static func defaultHubReportURL(baseDir: URL = HubPaths.baseDir()) -> URL {
        baseDir.appendingPathComponent(hubReportFileName)
    }

    static func defaultHubLocalServiceSnapshotURL(baseDir: URL = HubPaths.baseDir()) -> URL {
        baseDir.appendingPathComponent(hubLocalServiceSnapshotFileName)
    }

    static func defaultHubLocalRuntimeMonitorSnapshotURL(baseDir: URL = HubPaths.baseDir()) -> URL {
        baseDir.appendingPathComponent(hubLocalRuntimeMonitorSnapshotFileName)
    }

    static func defaultHubLocalServiceRecoveryGuidanceURL(baseDir: URL = HubPaths.baseDir()) -> URL {
        baseDir.appendingPathComponent(hubLocalServiceRecoveryGuidanceFileName)
    }

    static func loadReport(from url: URL) -> XHubDoctorOutputReport? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XHubDoctorOutputReport.self, from: data)
    }

    static func loadHubReport(baseDir: URL = HubPaths.baseDir()) -> XHubDoctorOutputReport? {
        loadReport(from: defaultHubReportURL(baseDir: baseDir))
    }

    static func loadHubLocalServiceSnapshot(baseDir: URL = HubPaths.baseDir()) -> XHubLocalServiceSnapshotReport? {
        let url = defaultHubLocalServiceSnapshotURL(baseDir: baseDir)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XHubLocalServiceSnapshotReport.self, from: data)
    }

    static func loadHubLocalRuntimeMonitorSnapshot(
        baseDir: URL = HubPaths.baseDir()
    ) -> XHubLocalRuntimeMonitorSnapshotReport? {
        let url = defaultHubLocalRuntimeMonitorSnapshotURL(baseDir: baseDir)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XHubLocalRuntimeMonitorSnapshotReport.self, from: data)
    }

    static func loadHubLocalServiceRecoveryGuidance(
        baseDir: URL = HubPaths.baseDir()
    ) -> XHubLocalServiceRecoveryGuidanceReport? {
        let url = defaultHubLocalServiceRecoveryGuidanceURL(baseDir: baseDir)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XHubLocalServiceRecoveryGuidanceReport.self, from: data)
    }

    static func writeReport(_ report: XHubDoctorOutputReport, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return }
        if existingReportMatches(data, at: url) {
            return
        }
        try? XTStoreWriteSupport.writeSnapshotData(data, to: url)
    }

    private static func existingReportMatches(_ data: Data, at url: URL) -> Bool {
        guard let existing = try? Data(contentsOf: url) else { return false }
        return existing == data
    }
}

extension XHubLocalServiceSnapshotReport {
    func preferredDetailLines(limit: Int = 2) -> [String] {
        let readyProviders = providers
            .filter(\.ready)
            .map(\.providerID)
            .sorted()
        let providerLines = providers.map { provider in
            let runtimeReason = provider.runtimeReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let endpoint = provider.serviceBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let executionMode = provider.executionMode.trimmingCharacters(in: .whitespacesAndNewlines)
            return "provider=\(provider.providerID) service_state=\(provider.serviceState) ready=\(provider.ready ? "1" : "0") runtime_reason=\(runtimeReason.isEmpty ? "none" : runtimeReason) endpoint=\(endpoint.isEmpty ? "none" : endpoint) execution_mode=\(executionMode.isEmpty ? "unknown" : executionMode) loaded_instances=\(max(0, provider.loadedInstanceCount)) queued=\(max(0, provider.queuedTaskCount))"
        }
        let summaryLines = [
            "ready_providers=\(readyProviders.isEmpty ? "none" : readyProviders.joined(separator: ","))",
            "managed_service_ready_count=\(max(0, readyProviderCount))",
            "provider_count=\(max(0, providerCount))",
            "managed_service_provider_count=\(max(0, providerCount))",
        ]
        let preferredLines = providerLines.isEmpty
            ? summaryLines
            : [summaryLines[0], providerLines[0]] + Array(summaryLines.dropFirst())
        return Array(preferredLines.prefix(max(0, limit)))
    }
}

extension XHubLocalServiceRecoveryGuidanceReport {
    var primaryFailureCode: String {
        let failureCode = currentFailureCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !failureCode.isEmpty {
            return failureCode
        }
        return primaryIssue?.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var topRecommendedActionSummary: String {
        guard let action = recommendedActions.sorted(by: { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }).first else {
            return ""
        }

        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = action.commandOrReference.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return ref
        }
        if ref.isEmpty || title.contains(ref) {
            return title
        }
        return "\(title) | \(ref)"
    }

    var topSupportFAQSummary: String {
        guard let item = supportFAQ.first else { return "" }
        let question = item.question.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = item.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (question.isEmpty, answer.isEmpty) {
        case (false, false):
            return "Q: \(question) A: \(answer)"
        case (false, true):
            return "Q: \(question)"
        case (true, false):
            return "A: \(answer)"
        default:
            return ""
        }
    }

    func preferredDetailLines(limit: Int = 2) -> [String] {
        let serviceBaseLine = [
            "managed_service_ready_count=\(max(0, readyProviderCount))",
            "provider_count=\(max(0, providerCount))",
            "service_base_url=\(serviceBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "none" : serviceBaseURL)",
            "managed_process_state=\(managedProcessState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : managedProcessState)",
            "managed_start_attempt_count=\(max(0, managedStartAttemptCount))",
        ].joined(separator: " ")
        let blockedLine: String? = {
            guard !blockedCapabilities.isEmpty else { return nil }
            return "blocked_capabilities=\(blockedCapabilities.joined(separator: ","))"
        }()
        let errorLine: String? = {
            let lastStartError = managedLastStartError.trimmingCharacters(in: .whitespacesAndNewlines)
            let lastProbeError = managedLastProbeError.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lastStartError.isEmpty || !lastProbeError.isEmpty else { return nil }
            return "managed_last_start_error=\(lastStartError.isEmpty ? "none" : lastStartError) managed_last_probe_error=\(lastProbeError.isEmpty ? "none" : lastProbeError)"
        }()

        let candidates = [serviceBaseLine, blockedLine, errorLine]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(candidates.prefix(max(0, limit)))
    }
}

extension XHubLocalRuntimeMonitorSnapshotReport {
    func preferredLoadConfigLine() -> String? {
        if let target = runtimeOperations?.currentTargets.first {
            let loadSummary = target.loadSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !loadSummary.isEmpty else { return nil }
            let provider = target.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
            return "current_target=\(target.modelID) provider=\(provider.isEmpty ? "unknown" : provider) load_summary=\(loadSummary)"
        }
        if let instance = runtimeOperations?.loadedInstances.first {
            let loadSummary = instance.loadSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !loadSummary.isEmpty else { return nil }
            let provider = instance.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
            return "loaded_instance=\(instance.modelID) provider=\(provider.isEmpty ? "unknown" : provider) load_summary=\(loadSummary)"
        }
        return nil
    }

    func preferredDetailLines(limit: Int = 2) -> [String] {
        var lines: [String] = []
        let trimmedLoadedSummary = runtimeOperations?.loadedSummary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedLoadedSummary.isEmpty {
            lines.append("runtime_loaded_summary=\(trimmedLoadedSummary)")
        }
        if let loadConfigLine = preferredLoadConfigLine() {
            lines.append(loadConfigLine)
        }

        if lines.isEmpty {
            let fallback = monitorSummary
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            lines.append(contentsOf: fallback.prefix(max(0, limit)))
        }

        var unique: [String] = []
        for line in lines where !unique.contains(line) {
            unique.append(line)
        }
        return Array(unique.prefix(max(0, limit)))
    }
}

private extension XHubDoctorOutputSummary {
    init(headline: String, checks: [XHubDoctorOutputCheckResult]) {
        self.init(
            headline: headline,
            passed: checks.filter { $0.status == .pass }.count,
            failed: checks.filter { $0.status == .fail }.count,
            warned: checks.filter { $0.status == .warn }.count,
            skipped: checks.filter { $0.status == .skip }.count
        )
    }
}

private extension XHubDoctorOutputCheckResult {
    init(section: XTUnifiedDoctorSection, observedAtMs: Int64) {
        let status = XHubDoctorCheckStatus(surfaceState: section.state)
        self.init(
            checkID: section.kind.rawValue,
            checkKind: section.kind.rawValue,
            status: status,
            severity: XHubDoctorSeverity(surfaceState: section.state),
            blocking: status == .fail,
            headline: section.headline,
            message: section.summary,
            nextStep: section.nextStep,
            repairDestinationRef: section.repairEntry.rawValue,
            detailLines: section.detailLines,
            projectContextSummary: XHubDoctorOutputProjectContextSummary(section: section),
            observedAtMs: observedAtMs,
            memoryRouteTruthSnapshot: XHubDoctorOutputMemoryRouteTruthSnapshot(section: section),
            durableCandidateMirrorSnapshot: XHubDoctorOutputDurableCandidateMirrorSnapshot(section: section),
            localStoreWriteSnapshot: XHubDoctorOutputLocalStoreWriteSnapshot(section: section)
        )
    }
}

private extension XHubDoctorOutputProjectContextSummary {
    init?(section: XTUnifiedDoctorSection) {
        guard section.kind == .sessionRuntimeReadiness else {
            return nil
        }
        if let presentation = section.projectContextPresentation {
            self.init(presentation)
            return
        }
        guard let presentation = AXProjectContextAssemblyPresentation.from(detailLines: section.detailLines) else {
            return nil
        }
        self.init(presentation)
    }

    init(_ presentation: AXProjectContextAssemblyPresentation) {
        self.init(
            sourceKind: presentation.sourceKind.rawValue,
            sourceBadge: presentation.sourceBadge,
            projectLabel: presentation.projectLabel,
            statusLine: presentation.statusLine,
            dialogueMetric: presentation.dialogueMetric,
            depthMetric: presentation.depthMetric,
            coverageMetric: presentation.coverageMetric,
            boundaryMetric: presentation.boundaryMetric,
            dialogueLine: presentation.dialogueLine,
            depthLine: presentation.depthLine,
            coverageLine: presentation.coverageLine,
            boundaryLine: presentation.boundaryLine
        )
    }
}

private extension XHubDoctorOutputMemoryRouteTruthSnapshot {
    init?(section: XTUnifiedDoctorSection) {
        guard section.kind == .modelRouteReadiness else {
            return nil
        }
        if let projection = section.memoryRouteTruthProjection {
            self.init(projection: projection)
            return
        }
        guard let projection = AXModelRouteTruthProjection(doctorDetailLines: section.detailLines) else {
            return nil
        }
        self.init(projection: projection)
    }

    init(projection: AXModelRouteTruthProjection) {
        self.init(
            projectionSource: projection.projectionSource,
            completeness: projection.completeness,
            requestSnapshot: XHubDoctorOutputMemoryRouteRequestSnapshot(projection.requestSnapshot),
            resolutionChain: projection.resolutionChain.map(XHubDoctorOutputMemoryRouteResolutionNode.init),
            winningProfile: XHubDoctorOutputMemoryRouteWinningProfile(projection.winningProfile),
            winningBinding: XHubDoctorOutputMemoryRouteWinningBinding(projection.winningBinding),
            routeResult: XHubDoctorOutputMemoryRouteResult(projection.routeResult),
            constraintSnapshot: XHubDoctorOutputMemoryRouteConstraintSnapshot(projection.constraintSnapshot)
        )
    }
}

private extension XHubDoctorOutputDurableCandidateMirrorSnapshot {
    init?(section: XTUnifiedDoctorSection) {
        guard section.kind == .sessionRuntimeReadiness else {
            return nil
        }
        if let projection = section.durableCandidateMirrorProjection {
            self.init(projection)
            return
        }
        guard let projection = XTUnifiedDoctorDurableCandidateMirrorProjection.from(
            detailLines: section.detailLines
        ) else {
            return nil
        }
        self.init(projection)
    }

    init(_ projection: XTUnifiedDoctorDurableCandidateMirrorProjection) {
        self.init(
            status: projection.status.rawValue,
            target: projection.target,
            attempted: projection.attempted,
            errorCode: projection.errorCode,
            localStoreRole: projection.localStoreRole
        )
    }
}

private extension XHubDoctorOutputLocalStoreWriteSnapshot {
    init?(section: XTUnifiedDoctorSection) {
        guard section.kind == .sessionRuntimeReadiness else {
            return nil
        }
        if let projection = section.localStoreWriteProjection {
            self.init(projection)
            return
        }
        guard let projection = XTUnifiedDoctorLocalStoreWriteProjection.from(
            detailLines: section.detailLines
        ) else {
            return nil
        }
        self.init(projection)
    }

    init(_ projection: XTUnifiedDoctorLocalStoreWriteProjection) {
        self.init(
            personalMemoryIntent: projection.personalMemoryIntent,
            crossLinkIntent: projection.crossLinkIntent,
            personalReviewIntent: projection.personalReviewIntent
        )
    }
}

private extension XHubDoctorOutputNextStep {
    init?(section: XTUnifiedDoctorSection) {
        let status = XHubDoctorCheckStatus(surfaceState: section.state)
        let instruction = section.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status != .pass, !instruction.isEmpty else { return nil }
        self.init(
            stepID: section.kind.rawValue,
            kind: xHubDoctorNextStepKind(for: section.repairEntry, state: section.state),
            label: section.repairEntry.label,
            owner: xHubDoctorStepOwner(for: section.repairEntry, state: section.state),
            blocking: status == .fail,
            destinationRef: section.repairEntry.rawValue,
            instruction: instruction
        )
    }
}

private extension XHubDoctorOutputRouteSnapshot {
    init(_ route: XTUnifiedDoctorRouteSnapshot) {
        self.init(
            transportMode: route.transportMode,
            routeLabel: route.routeLabel,
            pairingPort: route.pairingPort,
            grpcPort: route.grpcPort,
            internetHost: route.internetHost
        )
    }
}

private extension XHubDoctorOutputMemoryRouteRequestSnapshot {
    init(_ projection: AXModelRouteTruthRequestSnapshot) {
        self.init(
            jobType: projection.jobType,
            mode: projection.mode,
            projectIDPresent: projection.projectIDPresent,
            sensitivity: projection.sensitivity,
            trustLevel: projection.trustLevel,
            budgetClass: projection.budgetClass,
            remoteAllowedByPolicy: projection.remoteAllowedByPolicy,
            killSwitchState: projection.killSwitchState
        )
    }
}

private extension XHubDoctorOutputMemoryRouteResolutionNode {
    init(_ projection: AXModelRouteTruthResolutionNode) {
        self.init(
            scopeKind: projection.scopeKind,
            scopeRefRedacted: projection.scopeRefRedacted,
            matched: projection.matched,
            profileID: projection.profileID,
            selectionStrategy: projection.selectionStrategy,
            skipReason: projection.skipReason
        )
    }
}

private extension XHubDoctorOutputMemoryRouteWinningProfile {
    init(_ projection: AXModelRouteTruthWinningProfile) {
        self.init(
            resolvedProfileID: projection.resolvedProfileID,
            scopeKind: projection.scopeKind,
            scopeRefRedacted: projection.scopeRefRedacted,
            selectionStrategy: projection.selectionStrategy,
            policyVersion: projection.policyVersion,
            disabled: projection.disabled
        )
    }
}

private extension XHubDoctorOutputMemoryRouteWinningBinding {
    init(_ projection: AXModelRouteTruthWinningBinding) {
        self.init(
            bindingKind: projection.bindingKind,
            bindingKey: projection.bindingKey,
            provider: projection.provider,
            modelID: projection.modelID,
            selectedByUser: projection.selectedByUser
        )
    }
}

private extension XHubDoctorOutputMemoryRouteResult {
    init(_ projection: AXModelRouteTruthRouteResult) {
        self.init(
            routeSource: projection.routeSource,
            routeReasonCode: projection.routeReasonCode,
            fallbackApplied: projection.fallbackApplied,
            fallbackReason: projection.fallbackReason,
            remoteAllowed: projection.remoteAllowed,
            auditRef: projection.auditRef,
            denyCode: projection.denyCode
        )
    }
}

private extension XHubDoctorOutputMemoryRouteConstraintSnapshot {
    init(_ projection: AXModelRouteTruthConstraintSnapshot) {
        self.init(
            remoteAllowedAfterUserPref: projection.remoteAllowedAfterUserPref,
            remoteAllowedAfterPolicy: projection.remoteAllowedAfterPolicy,
            budgetClass: projection.budgetClass,
            budgetBlocked: projection.budgetBlocked,
            policyBlockedRemote: projection.policyBlockedRemote
        )
    }
}

private extension XHubDoctorOverallState {
    init(surfaceState: XTUISurfaceState) {
        switch surfaceState {
        case .ready:
            self = .ready
        case .inProgress:
            self = .inProgress
        case .grantRequired, .permissionDenied, .blockedWaitingUpstream:
            self = .blocked
        case .releaseFrozen:
            self = .notSupported
        case .diagnosticRequired:
            self = .degraded
        }
    }
}

private extension XHubDoctorCheckStatus {
    init(surfaceState: XTUISurfaceState) {
        switch surfaceState {
        case .ready:
            self = .pass
        case .inProgress:
            self = .warn
        case .grantRequired, .permissionDenied, .blockedWaitingUpstream, .diagnosticRequired:
            self = .fail
        case .releaseFrozen:
            self = .skip
        }
    }
}

private extension XHubDoctorSeverity {
    init(surfaceState: XTUISurfaceState) {
        switch surfaceState {
        case .ready:
            self = .info
        case .inProgress, .releaseFrozen:
            self = .warning
        case .grantRequired, .blockedWaitingUpstream, .diagnosticRequired:
            self = .error
        case .permissionDenied:
            self = .critical
        }
    }
}

private func xHubDoctorNextStepKind(
    for destination: UITroubleshootDestination,
    state: XTUISurfaceState
) -> XHubDoctorNextStepKind {
    switch state {
    case .inProgress, .blockedWaitingUpstream:
        return .waitForRecovery
    case .releaseFrozen:
        return .openRepairSurface
    case .ready, .grantRequired, .permissionDenied, .diagnosticRequired:
        break
    }

    switch destination {
    case .xtPairHub, .hubPairing:
        return .reviewPairing
    case .xtChooseModel, .hubModels:
        return .chooseModel
    case .hubGrants, .hubSecurity, .systemPermissions:
        return .reviewPermissions
    case .xtDiagnostics, .hubDiagnostics:
        return .inspectDiagnostics
    case .homeSupervisor:
        return .startFirstTask
    }
}

private func xHubDoctorStepOwner(
    for destination: UITroubleshootDestination,
    state: XTUISurfaceState
) -> XHubDoctorStepOwner {
    switch state {
    case .inProgress:
        return .xtRuntime
    case .blockedWaitingUpstream:
        return .hubRuntime
    case .ready, .grantRequired, .permissionDenied, .releaseFrozen, .diagnosticRequired:
        break
    }

    switch destination {
    case .xtPairHub, .xtChooseModel, .xtDiagnostics, .hubPairing, .hubModels, .hubGrants, .hubSecurity, .hubDiagnostics, .systemPermissions, .homeSupervisor:
        return .user
    }
}
