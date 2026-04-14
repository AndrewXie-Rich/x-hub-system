import Foundation
import RELFlowHubCore

enum HubLocalTaskExecutionService {
    private static let supportedSchemaVersion = "xhub.local_task_ipc.v1"
    private static let runtimeSource = "local_runtime_command"

    typealias ModelResolver = (String) -> HubModel?
    typealias LaunchConfigResolver = (String) -> LocalRuntimeCommandLaunchConfig?
    typealias CompatibilityMessageEvaluator = (HubModel, String) -> String?
    typealias RuntimeStatusResolver = () -> AIRuntimeStatus?
    typealias RuntimeCommandRunner = (
        String,
        Data,
        LocalRuntimeCommandLaunchConfig,
        TimeInterval
    ) throws -> Data

    private static let overrideLock = NSLock()
    nonisolated(unsafe) private static var modelResolverOverride: ModelResolver?
    nonisolated(unsafe) private static var launchConfigResolverOverride: LaunchConfigResolver?
    nonisolated(unsafe) private static var compatibilityMessageOverride: CompatibilityMessageEvaluator?
    nonisolated(unsafe) private static var runtimeStatusResolverOverride: RuntimeStatusResolver?
    nonisolated(unsafe) private static var runtimeCommandRunnerOverride: RuntimeCommandRunner?

    static func execute(_ payload: IPCLocalTaskRequestPayload) -> IPCLocalTaskResult {
        let schemaVersion = normalized(payload.schemaVersion) ?? supportedSchemaVersion
        guard schemaVersion == supportedSchemaVersion else {
            return failureResult(
                reasonCode: "local_task_schema_unsupported",
                detail: "unsupported schema_version \(schemaVersion)"
            )
        }

        let taskKind = normalizedTaskKind(payload.taskKind)
        guard !taskKind.isEmpty else {
            return failureResult(
                reasonCode: "local_task_missing_task_kind",
                detail: "task_kind is required"
            )
        }
        guard LocalTaskRoutingCatalog.supportedTaskKinds.contains(taskKind) else {
            return failureResult(
                taskKind: taskKind,
                reasonCode: "local_task_unsupported_task_kind",
                detail: "task_kind \(taskKind) is not supported by Hub local IPC"
            )
        }

        let requestedModelID = normalized(payload.modelID) ?? ""
        guard !requestedModelID.isEmpty else {
            return failureResult(
                taskKind: taskKind,
                reasonCode: "local_task_missing_model_id",
                detail: "model_id is required"
            )
        }

        guard let model = resolveModel(modelID: requestedModelID) else {
            return failureResult(
                modelID: requestedModelID,
                taskKind: taskKind,
                reasonCode: "local_task_model_not_found",
                detail: "model_id is not registered in Hub"
            )
        }

        guard !LocalModelRuntimeActionPlanner.isRemoteModel(model) else {
            return failureResult(
                provider: LocalModelExecutionProviderResolver.preferredRuntimeProviderID(for: model),
                modelID: model.id,
                taskKind: taskKind,
                reasonCode: "local_task_model_ineligible",
                detail: "requested model is remote or non-local and cannot run on local task IPC"
            )
        }

        let modelTaskKinds = Set(
            model.taskKinds
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        guard modelTaskKinds.contains(taskKind) else {
            return failureResult(
                provider: LocalModelExecutionProviderResolver.preferredRuntimeProviderID(for: model),
                modelID: model.id,
                taskKind: taskKind,
                reasonCode: "local_task_model_task_unsupported",
                detail: "requested model does not advertise task_kind \(taskKind)"
            )
        }

        let providerID = LocalModelExecutionProviderResolver.preferredRuntimeProviderID(for: model)
        guard let launchConfig = loadLaunchConfig(preferredProviderID: providerID) else {
            return failureResult(
                provider: providerID,
                modelID: model.id,
                taskKind: taskKind,
                reasonCode: "local_task_runtime_launch_config_unavailable",
                detail: "local runtime command launch configuration is unavailable"
            )
        }

        if let compatibilityMessage = blockedCompatibilityMessage(model: model, providerID: providerID) {
            return failureResult(
                provider: providerID,
                modelID: model.id,
                taskKind: taskKind,
                reasonCode: "local_task_runtime_incompatible",
                detail: compatibilityMessage
            )
        }

        let requestObject = makeRuntimeRequest(
            providerID: providerID,
            model: model,
            taskKind: taskKind,
            payload: payload
        )
        guard JSONSerialization.isValidJSONObject(requestObject),
              let requestData = try? JSONSerialization.data(withJSONObject: requestObject, options: []) else {
            return failureResult(
                provider: providerID,
                modelID: model.id,
                taskKind: taskKind,
                reasonCode: "local_task_invalid_request_payload",
                detail: "local task runtime request encoding failed"
            )
        }

        do {
            let responseData = try runRuntimeCommand(
                command: "run-local-task",
                requestData: requestData,
                launchConfig: launchConfig,
                timeoutSec: clampedTimeout(payload.timeoutSec)
            )
            return mapRuntimeResponse(
                responseData,
                fallbackProviderID: providerID,
                fallbackModelID: model.id,
                fallbackTaskKind: taskKind
            )
        } catch {
            return failureResult(
                provider: providerID,
                modelID: model.id,
                taskKind: taskKind,
                reasonCode: "local_task_runtime_failed",
                runtimeSource: runtimeSource,
                error: error.localizedDescription,
                detail: String(describing: error)
            )
        }
    }

    private static func resolveModel(modelID: String) -> HubModel? {
        let normalizedID = normalized(modelID) ?? ""
        guard !normalizedID.isEmpty else { return nil }
        if let override = withOverrides({ modelResolverOverride }) {
            return override(normalizedID)
        }
        return ModelStateStorage.load().models.first { $0.id == normalizedID }
    }

    private static func loadLaunchConfig(preferredProviderID: String) -> LocalRuntimeCommandLaunchConfig? {
        if let override = withOverrides({ launchConfigResolverOverride }) {
            return override(preferredProviderID)
        }
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                HubStore.shared.localRuntimeCommandLaunchConfig(
                    preferredProviderID: preferredProviderID
                )
            }
        }

        var launchConfig: LocalRuntimeCommandLaunchConfig?
        DispatchQueue.main.sync {
            launchConfig = MainActor.assumeIsolated {
                HubStore.shared.localRuntimeCommandLaunchConfig(
                    preferredProviderID: preferredProviderID
                )
            }
        }
        return launchConfig
    }

    private static func blockedCompatibilityMessage(
        model: HubModel,
        providerID: String
    ) -> String? {
        if let override = withOverrides({ compatibilityMessageOverride }) {
            return override(model, providerID)
        }

        let probeLaunchConfig = loadProbeLaunchConfig(preferredProviderID: providerID)
        let pythonPath = loadPythonPath(preferredProviderID: providerID)
        return LocalModelRuntimeCompatibilityPolicy.blockedActionMessage(
            action: "load",
            model: model,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        )
    }

    private static func loadProbeLaunchConfig(
        preferredProviderID: String
    ) -> LocalRuntimePythonProbeLaunchConfig? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                HubStore.shared.localRuntimePythonProbeLaunchConfig(
                    preferredProviderID: preferredProviderID
                )
            }
        }

        var probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig?
        DispatchQueue.main.sync {
            probeLaunchConfig = MainActor.assumeIsolated {
                HubStore.shared.localRuntimePythonProbeLaunchConfig(
                    preferredProviderID: preferredProviderID
                )
            }
        }
        return probeLaunchConfig
    }

    private static func loadPythonPath(preferredProviderID: String) -> String? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                HubStore.shared.preferredLocalProviderPythonPath(
                    preferredProviderID: preferredProviderID
                )
            }
        }

        var pythonPath: String?
        DispatchQueue.main.sync {
            pythonPath = MainActor.assumeIsolated {
                HubStore.shared.preferredLocalProviderPythonPath(
                    preferredProviderID: preferredProviderID
                )
            }
        }
        return pythonPath
    }

    private static func resolveRuntimeStatus() -> AIRuntimeStatus? {
        if let override = withOverrides({ runtimeStatusResolverOverride }) {
            return override()
        }
        return AIRuntimeStatusStorage.load()
    }

    private static func makeRuntimeRequest(
        providerID: String,
        model: HubModel,
        taskKind: String,
        payload: IPCLocalTaskRequestPayload
    ) -> [String: Any] {
        var request: [String: Any] = [:]
        for (key, value) in payload.parameters {
            request[key] = value.foundationValue
        }

        request["provider"] = providerID
        request["model_id"] = model.id
        request["task_kind"] = taskKind
        request["allow_daemon_proxy"] = false

        let normalizedDeviceID = normalized(payload.deviceID)
        let targetPreference = normalizedDeviceID.map {
            LocalModelRuntimeTargetPreference(
                modelId: model.id,
                targetKind: .pairedDevice,
                deviceId: $0
            )
        }
        var context = LocalModelRuntimeRequestContextResolver.resolve(
            model: model,
            runtimeStatus: resolveRuntimeStatus(),
            targetPreference: targetPreference
        )
        if let normalizedDeviceID, context.deviceID.isEmpty {
            context.deviceID = normalizedDeviceID
        }
        return context.applying(to: request)
    }

    private static func runRuntimeCommand(
        command: String,
        requestData: Data,
        launchConfig: LocalRuntimeCommandLaunchConfig,
        timeoutSec: TimeInterval
    ) throws -> Data {
        if let override = withOverrides({ runtimeCommandRunnerOverride }) {
            return try override(command, requestData, launchConfig, timeoutSec)
        }
        return try LocalRuntimeCommandRunner.run(
            command: command,
            requestData: requestData,
            launchConfig: launchConfig,
            timeoutSec: timeoutSec
        )
    }

    private static func mapRuntimeResponse(
        _ data: Data,
        fallbackProviderID: String,
        fallbackModelID: String,
        fallbackTaskKind: String
    ) -> IPCLocalTaskResult {
        guard let rawPayload = try? JSONDecoder().decode([String: IPCJSONValue].self, from: data) else {
            return failureResult(
                provider: fallbackProviderID,
                modelID: fallbackModelID,
                taskKind: fallbackTaskKind,
                reasonCode: "local_task_invalid_runtime_response",
                runtimeSource: runtimeSource,
                detail: "runtime response JSON decoding failed"
            )
        }

        let ok = rawPayload["ok"]?.boolValue ?? false
        let provider = normalized(
            rawPayload["provider"]?.stringValue
        ) ?? fallbackProviderID
        let modelID = normalized(
            rawPayload["modelId"]?.stringValue
                ?? rawPayload["model_id"]?.stringValue
        ) ?? fallbackModelID
        let taskKind = normalizedTaskKind(
            rawPayload["taskKind"]?.stringValue
                ?? rawPayload["task_kind"]?.stringValue
                ?? fallbackTaskKind
        )
        let reasonCode = normalized(
            rawPayload["reasonCode"]?.stringValue
                ?? rawPayload["reason_code"]?.stringValue
                ?? rawPayload["error"]?.stringValue
        )
        let runtimeReasonCode = normalized(
            rawPayload["runtimeReasonCode"]?.stringValue
                ?? rawPayload["runtime_reason_code"]?.stringValue
        )
        let error = normalized(rawPayload["error"]?.stringValue)
        let detail = normalized(
            rawPayload["detail"]?.stringValue
                ?? rawPayload["message"]?.stringValue
        )

        return IPCLocalTaskResult(
            ok: ok,
            source: "hub_ipc",
            runtimeSource: runtimeSource,
            provider: provider,
            modelID: modelID,
            taskKind: taskKind,
            reasonCode: reasonCode,
            runtimeReasonCode: runtimeReasonCode,
            error: error,
            detail: detail,
            payload: rawPayload
        )
    }

    private static func failureResult(
        provider: String? = nil,
        modelID: String? = nil,
        taskKind: String? = nil,
        reasonCode: String,
        runtimeSource: String? = nil,
        error: String? = nil,
        detail: String? = nil
    ) -> IPCLocalTaskResult {
        IPCLocalTaskResult(
            ok: false,
            source: "hub_ipc",
            runtimeSource: runtimeSource,
            provider: provider,
            modelID: modelID,
            taskKind: taskKind,
            reasonCode: reasonCode,
            runtimeReasonCode: nil,
            error: error,
            detail: detail,
            payload: [:]
        )
    }

    private static func clampedTimeout(_ raw: Double?) -> TimeInterval {
        guard let raw, raw.isFinite else { return 45.0 }
        return max(3.0, min(90.0, raw))
    }

    private static func normalized(_ raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalizedTaskKind(_ raw: String?) -> String {
        normalized(raw)?.lowercased() ?? ""
    }

    private static func withOverrides<T>(_ body: () -> T) -> T {
        overrideLock.lock()
        defer { overrideLock.unlock() }
        return body()
    }

    static func installTestingOverrides(
        modelResolver: ModelResolver? = nil,
        launchConfigResolver: LaunchConfigResolver? = nil,
        compatibilityMessageEvaluator: CompatibilityMessageEvaluator? = nil,
        runtimeStatusResolver: RuntimeStatusResolver? = nil,
        runtimeCommandRunner: RuntimeCommandRunner? = nil
    ) {
        overrideLock.lock()
        defer { overrideLock.unlock() }
        modelResolverOverride = modelResolver
        launchConfigResolverOverride = launchConfigResolver
        compatibilityMessageOverride = compatibilityMessageEvaluator
        runtimeStatusResolverOverride = runtimeStatusResolver
        runtimeCommandRunnerOverride = runtimeCommandRunner
    }

    static func resetTestingOverrides() {
        installTestingOverrides()
    }
}
