import Foundation
import RELFlowHubCore

struct XHubLocalServiceProviderEvidence: Codable, Equatable, Sendable {
    var providerID: String
    var providerState: AIRuntimeProviderReadinessState
    var providerReasonCode: String
    var runtimeSource: String
    var runtimeResolutionState: String
    var runtimeReasonCode: String
    var serviceState: String
    var serviceBaseURL: String
    var runtimeSourcePath: String
    var runtimeVersion: String
    var executionMode: String
    var packEngine: String
    var packVersion: String
    var supportedDomains: [String]
    var availableTaskKinds: [String]
    var loadedModels: [String]
    var loadedModelCount: Int
    var ready: Bool
    var activeTaskCount: Int
    var queuedTaskCount: Int
    var loadedInstanceCount: Int
    var lifecycleMode: String
    var managedServiceState: AIRuntimeManagedServiceState?

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case providerState = "provider_state"
        case providerReasonCode = "provider_reason_code"
        case runtimeSource = "runtime_source"
        case runtimeResolutionState = "runtime_resolution_state"
        case runtimeReasonCode = "runtime_reason_code"
        case serviceState = "service_state"
        case serviceBaseURL = "service_base_url"
        case runtimeSourcePath = "runtime_source_path"
        case runtimeVersion = "runtime_version"
        case executionMode = "execution_mode"
        case packEngine = "pack_engine"
        case packVersion = "pack_version"
        case supportedDomains = "supported_domains"
        case availableTaskKinds = "available_task_kinds"
        case loadedModels = "loaded_models"
        case loadedModelCount = "loaded_model_count"
        case ready
        case activeTaskCount = "active_task_count"
        case queuedTaskCount = "queued_task_count"
        case loadedInstanceCount = "loaded_instance_count"
        case lifecycleMode = "lifecycle_mode"
        case managedServiceState = "managed_service_state"
    }
}

struct XHubLocalServicePrimaryIssue: Equatable, Sendable {
    var reasonCode: String
    var headline: String
    var message: String
    var nextStep: String
}

enum XHubLocalServiceDiagnostics {
    static func primaryServiceEvidence(
        in evidence: [XHubLocalServiceProviderEvidence]
    ) -> XHubLocalServiceProviderEvidence? {
        evidence
            .filter { !$0.ready }
            .sorted(by: serviceIssueSortKey)
            .first
    }

    static func providerEvidence(
        status: AIRuntimeStatus?,
        ttl: Double = 3.0
    ) -> [XHubLocalServiceProviderEvidence] {
        guard let status else { return [] }

        let diagnoses = status.providerDiagnoses(ttl: ttl)
        let diagnosisByProvider = Dictionary(
            uniqueKeysWithValues: diagnoses.map { ($0.provider, $0) }
        )
        let providerStatusByProvider = status.providers
        let packByProvider = Dictionary(
            uniqueKeysWithValues: status.providerPacks.map { ($0.providerId, $0) }
        )
        let monitorByProvider = Dictionary(
            uniqueKeysWithValues: (status.monitorSnapshot?.providers ?? []).map { ($0.provider, $0) }
        )

        let providerIDs = Set(diagnoses.compactMap { diagnosis in
            isXHubLocalServiceProvider(
                runtimeSource: diagnosis.runtimeSource,
                executionMode: packByProvider[diagnosis.provider]?.runtimeRequirements.executionMode ?? "",
                monitorRuntimeSource: monitorByProvider[diagnosis.provider]?.runtimeSource ?? ""
            ) ? diagnosis.provider : nil
        })
        .union(status.providerPacks.compactMap { pack in
            pack.runtimeRequirements.executionMode == "xhub_local_service" ? pack.providerId : nil
        })
        .union((status.monitorSnapshot?.providers ?? []).compactMap { provider in
            provider.runtimeSource == "xhub_local_service" ? provider.provider : nil
        })

        return providerIDs.sorted().map { providerID in
            let diagnosis = diagnosisByProvider[providerID]
            let pack = packByProvider[providerID]
            let monitor = monitorByProvider[providerID]
            let runtimeSource = normalized(diagnosis?.runtimeSource ?? monitor?.runtimeSource ?? "")
            let runtimeReasonCode = normalizedReasonCode(
                diagnosis?.runtimeReasonCode ?? monitor?.runtimeReasonCode ?? diagnosis?.providerReasonCodeFallback ?? ""
            )
            let runtimeSourcePath = diagnosis?.runtimeSourcePath.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let packServiceBaseURL = pack?.runtimeRequirements.serviceBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let serviceBaseURL = resolvedServiceBaseURL(
                packServiceBaseURL: packServiceBaseURL,
                runtimeSourcePath: runtimeSourcePath
            )
            let providerState = diagnosis?.state ?? .down
            let availableTaskKinds = diagnosis?.availableTaskKinds ?? monitor?.availableTaskKinds ?? []
            let loadedModels = diagnosis?.loadedModels ?? []
            let managedServiceState = providerStatusByProvider[providerID]?.managedServiceState ?? diagnosis?.managedServiceState

            return XHubLocalServiceProviderEvidence(
                providerID: providerID,
                providerState: providerState,
                providerReasonCode: normalizedReasonCode(diagnosis?.reasonCode ?? ""),
                runtimeSource: runtimeSource,
                runtimeResolutionState: normalized(diagnosis?.runtimeResolutionState ?? monitor?.runtimeResolutionState ?? ""),
                runtimeReasonCode: runtimeReasonCode,
                serviceState: serviceState(
                    runtimeReasonCode: runtimeReasonCode,
                    providerState: providerState
                ),
                serviceBaseURL: serviceBaseURL,
                runtimeSourcePath: runtimeSourcePath,
                runtimeVersion: diagnosis?.runtimeVersion.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                executionMode: normalized(pack?.runtimeRequirements.executionMode ?? ""),
                packEngine: pack?.engine.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                packVersion: pack?.version.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                supportedDomains: pack?.supportedDomains ?? [],
                availableTaskKinds: availableTaskKinds,
                loadedModels: loadedModels,
                loadedModelCount: diagnosis?.loadedModelCount ?? loadedModels.count,
                ready: providerState == .ready,
                activeTaskCount: max(0, monitor?.activeTaskCount ?? 0),
                queuedTaskCount: max(0, monitor?.queuedTaskCount ?? 0),
                loadedInstanceCount: max(0, monitor?.loadedInstanceCount ?? 0),
                lifecycleMode: normalized(monitor?.lifecycleMode ?? ""),
                managedServiceState: managedServiceState
            )
        }
    }

    static func detailLine(for evidence: XHubLocalServiceProviderEvidence) -> String {
        let endpoint = evidence.serviceBaseURL.isEmpty
            ? (evidence.runtimeSourcePath.isEmpty ? "none" : evidence.runtimeSourcePath)
            : evidence.serviceBaseURL
        let runtimeReason = evidence.runtimeReasonCode.isEmpty ? "none" : evidence.runtimeReasonCode
        let providerReason = evidence.providerReasonCode.isEmpty ? "none" : evidence.providerReasonCode
        let executionMode = evidence.executionMode.isEmpty ? "unknown" : evidence.executionMode
        let domains = evidence.supportedDomains.isEmpty ? "none" : evidence.supportedDomains.joined(separator: ",")
        let tasks = evidence.availableTaskKinds.isEmpty ? "none" : evidence.availableTaskKinds.joined(separator: ",")
        let models = evidence.loadedModels.isEmpty ? "none" : evidence.loadedModels.joined(separator: ",")
        let packEngine = evidence.packEngine.isEmpty ? "unknown" : evidence.packEngine
        let packVersion = evidence.packVersion.isEmpty ? "unknown" : evidence.packVersion
        let managed = evidence.managedServiceState
        let processState = normalizedDetailValue(managed?.processState, fallback: "unknown")
        let pid = max(0, managed?.pid ?? 0)
        let bindHost = normalizedDetailValue(managed?.bindHost, fallback: "none")
        let bindPort = max(0, managed?.bindPort ?? 0)
        let attemptCount = max(0, managed?.startAttemptCount ?? 0)
        let probeHTTP = max(0, managed?.lastProbeHTTPStatus ?? 0)
        let lastProbeError = normalizedDetailValue(managed?.lastProbeError, fallback: "none")
        let lastStartError = normalizedDetailValue(managed?.lastStartError, fallback: "none")
        return "provider=\(evidence.providerID) service_state=\(evidence.serviceState) ready=\(evidence.ready ? "1" : "0") provider_state=\(evidence.providerState.rawValue) runtime_reason=\(runtimeReason) provider_reason=\(providerReason) endpoint=\(endpoint) execution_mode=\(executionMode) pack_engine=\(packEngine) pack_version=\(packVersion) domains=\(domains) tasks=\(tasks) loaded_models=\(models) loaded_model_count=\(evidence.loadedModelCount) active=\(evidence.activeTaskCount) queued=\(evidence.queuedTaskCount) loaded_instances=\(evidence.loadedInstanceCount) process_state=\(processState) pid=\(pid) bind_host=\(bindHost) bind_port=\(bindPort) start_attempt_count=\(attemptCount) last_probe_http_status=\(probeHTTP) last_probe_error=\(lastProbeError) last_start_error=\(lastStartError)"
    }

    static func primaryIssue(
        in evidence: [XHubLocalServiceProviderEvidence]
    ) -> XHubLocalServicePrimaryIssue? {
        guard let serviceIssue = primaryServiceEvidence(in: evidence) else {
            return nil
        }
        let strings = HubUIStrings.Models.Runtime.LocalServiceDiagnostics.self

        let endpoint = serviceIssue.serviceBaseURL.isEmpty
            ? (serviceIssue.runtimeSourcePath.isEmpty ? "the configured endpoint" : serviceIssue.runtimeSourcePath)
            : serviceIssue.serviceBaseURL

        switch serviceIssue.serviceState {
        case "missing_config":
            return XHubLocalServicePrimaryIssue(
                reasonCode: "xhub_local_service_config_missing",
                headline: strings.configMissingHeadline,
                message: strings.configMissingMessage,
                nextStep: strings.configMissingNextStep
            )
        case "unsafe_endpoint":
            return XHubLocalServicePrimaryIssue(
                reasonCode: "xhub_local_service_nonlocal_endpoint",
                headline: strings.nonlocalEndpointHeadline,
                message: strings.nonlocalEndpointMessage,
                nextStep: strings.nonlocalEndpointNextStep
            )
        case "unreachable":
            let managedHint = managedServiceFailureHint(serviceIssue.managedServiceState)
            let message = {
                let suffix = managedHint.messageSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
                let base = strings.unreachableBase(endpoint)
                return suffix.isEmpty ? base : "\(base)\n\(suffix)"
            }()
            return XHubLocalServicePrimaryIssue(
                reasonCode: "xhub_local_service_unreachable",
                headline: strings.unreachableHeadline,
                message: message,
                nextStep: managedHint.nextStep.isEmpty
                    ? strings.unreachableDefaultNextStep
                    : managedHint.nextStep
            )
        case "starting":
            return XHubLocalServicePrimaryIssue(
                reasonCode: "xhub_local_service_starting",
                headline: strings.startingHeadline,
                message: strings.startingMessage,
                nextStep: strings.startingNextStep
            )
        case "not_ready":
            return XHubLocalServicePrimaryIssue(
                reasonCode: "xhub_local_service_not_ready",
                headline: strings.notReadyHeadline,
                message: strings.notReadyMessage,
                nextStep: strings.notReadyNextStep
            )
        case "service_hosted_runtime_missing":
            return XHubLocalServicePrimaryIssue(
                reasonCode: "xhub_local_service_internal_runtime_missing",
                headline: strings.serviceHostedRuntimeMissingHeadline,
                message: strings.serviceHostedRuntimeMissingMessage,
                nextStep: strings.serviceHostedRuntimeMissingNextStep
            )
        default:
            return XHubLocalServicePrimaryIssue(
                reasonCode: serviceIssue.runtimeReasonCode.isEmpty ? "xhub_local_service_state_unknown" : serviceIssue.runtimeReasonCode,
                headline: strings.unknownStateHeadline,
                message: strings.unknownStateMessage,
                nextStep: strings.unknownStateNextStep
            )
        }
    }

    private static func isXHubLocalServiceProvider(
        runtimeSource: String,
        executionMode: String,
        monitorRuntimeSource: String
    ) -> Bool {
        normalized(runtimeSource) == "xhub_local_service"
            || normalized(executionMode) == "xhub_local_service"
            || normalized(monitorRuntimeSource) == "xhub_local_service"
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedReasonCode(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolvedServiceBaseURL(
        packServiceBaseURL: String,
        runtimeSourcePath: String
    ) -> String {
        let configured = packServiceBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            return configured
        }
        let runtimePath = runtimeSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if runtimePath.hasPrefix("http://") || runtimePath.hasPrefix("https://") {
            return runtimePath
        }
        return ""
    }

    private static func serviceState(
        runtimeReasonCode: String,
        providerState: AIRuntimeProviderReadinessState
    ) -> String {
        switch normalizedReasonCode(runtimeReasonCode) {
        case "xhub_local_service_config_missing":
            return "missing_config"
        case "xhub_local_service_nonlocal_endpoint":
            return "unsafe_endpoint"
        case "xhub_local_service_unreachable":
            return "unreachable"
        case "xhub_local_service_starting":
            return "starting"
        case "xhub_local_service_not_ready":
            return "not_ready"
        case "xhub_local_service_ready":
            return "ready"
        case "missing_runtime":
            return "service_hosted_runtime_missing"
        default:
            return providerState == .ready ? "ready" : "unknown"
        }
    }

    private static func serviceIssueSortKey(
        _ lhs: XHubLocalServiceProviderEvidence,
        _ rhs: XHubLocalServiceProviderEvidence
    ) -> Bool {
        let lhsPriority = serviceIssuePriority(lhs.serviceState)
        let rhsPriority = serviceIssuePriority(rhs.serviceState)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return lhs.providerID < rhs.providerID
    }

    private static func serviceIssuePriority(_ serviceState: String) -> Int {
        switch serviceState {
        case "missing_config":
            return 0
        case "unsafe_endpoint":
            return 1
        case "unreachable":
            return 2
        case "starting":
            return 3
        case "not_ready":
            return 4
        case "service_hosted_runtime_missing":
            return 5
        case "unknown":
            return 6
        default:
            return 7
        }
    }

    private static func normalizedDetailValue(_ value: String?, fallback: String) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? fallback : normalized
    }

    private static func managedServiceFailureHint(
        _ managedState: AIRuntimeManagedServiceState?
    ) -> (messageSuffix: String, nextStep: String) {
        guard let managedState else {
            return ("", "")
        }
        let strings = HubUIStrings.Models.Runtime.LocalServiceDiagnostics.self
        let processState = managedState.processState.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastStartError = managedState.lastStartError.trimmingCharacters(in: .whitespacesAndNewlines)
        if processState == "launch_failed" {
            return (
                strings.launchFailedMessage(lastStartError),
                strings.launchFailedNextStep
            )
        }
        if lastStartError.hasPrefix("health_timeout:") {
            return (
                strings.healthTimeoutMessage,
                strings.healthTimeoutNextStep
            )
        }
        if managedState.startAttemptCount > 0 {
            return (
                strings.managedStartAttemptsMessage(managedState.startAttemptCount),
                strings.managedStartAttemptsNextStep
            )
        }
        return ("", "")
    }
}

private extension AIRuntimeProviderDiagnosis {
    var providerReasonCodeFallback: String {
        reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
