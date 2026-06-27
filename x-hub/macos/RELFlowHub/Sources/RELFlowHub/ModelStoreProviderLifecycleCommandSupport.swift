import Foundation
import RELFlowHubCore

extension ModelStore {
    func enqueueLegacyModelCommand(
        action: String,
        model: HubModel,
        runtimeStatus: AIRuntimeStatus?,
        targetPreferenceOverride: LocalModelRuntimeTargetPreference?
    ) {
        let base = SharedPaths.ensureHubDirectory()
        let dir = base.appendingPathComponent("model_commands", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let reqId = UUID().uuidString
        let requestContext = localRuntimeRequestContext(
            for: model,
            runtimeStatus: runtimeStatus,
            targetPreference: targetPreferenceOverride
        )
        let baseCommand: [String: Any] = [
            "type": "model_command",
            "req_id": reqId,
            "action": action,
            "model_id": model.id,
            "requested_at": Date().timeIntervalSince1970,
        ]
        let cmd = Self.legacyModelCommandPayload(
            action: action,
            requestContext: requestContext,
            baseCommand: baseCommand
        )

        let tmp = dir.appendingPathComponent(".cmd_\(UUID().uuidString).tmp")
        let out = dir.appendingPathComponent("cmd_\(UUID().uuidString).json")
        if let data = try? JSONSerialization.data(withJSONObject: cmd, options: []) {
            try? data.write(to: tmp, options: .atomic)
            try? FileManager.default.moveItem(at: tmp, to: out)
        }

        // Track pending so the UI doesn't optimistically lie about loaded state.
        pendingByModelId[model.id] = PendingCommand(reqId: reqId, action: action, requestedAt: Date().timeIntervalSince1970)
    }

    nonisolated static func legacyModelCommandPayload(
        action: String,
        requestContext: LocalModelRuntimeRequestContext,
        baseCommand: [String: Any]
    ) -> [String: Any] {
        var command = requestContext.applying(to: baseCommand)
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedAction == "sleep" || normalizedAction == "unload" else {
            return command
        }

        // Model-row sleep/unload is model-scoped. Dropping route-specific targeting
        // avoids "unload succeeded but old instance still loaded" when the selected
        // route/profile no longer matches the resident MLX instance identity.
        let scopedKeys = [
            "device_id",
            "instance_key",
            "load_profile_hash",
            "load_config_hash",
            "effective_context_length",
            "current_context_length",
            "load_profile_override",
        ]
        for key in scopedKeys {
            command.removeValue(forKey: key)
        }
        return command
    }

    func enqueueProviderLifecycleCommand(
        action: String,
        model: HubModel,
        targetPreferenceOverride: LocalModelRuntimeTargetPreference?
    ) {
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        guard let launchConfig = HubStore.shared.localRuntimeCommandLaunchConfig(
            preferredProviderID: providerID
        ) else {
            recordImmediateFailure(
                action: lifecycleDisplayAction(action),
                modelId: model.id,
                msg: LocalRuntimeCommandError.runtimeLaunchConfigUnavailable.localizedDescription
            )
            return
        }

        let requestContext = localRuntimeRequestContext(
            for: model,
            runtimeStatus: AIRuntimeStatusStorage.load(),
            targetPreference: targetPreferenceOverride
        )
        let baseRequest: [String: Any] = [
            "action": action,
            "provider": providerID,
            "model_id": model.id,
        ]
        let request = requestContext.applying(to: baseRequest)
        guard JSONSerialization.isValidJSONObject(request),
              let requestData = try? JSONSerialization.data(withJSONObject: request, options: []) else {
            recordImmediateFailure(
                action: lifecycleDisplayAction(action),
                modelId: model.id,
                msg: LocalRuntimeCommandError.invalidRequestPayload.localizedDescription
            )
            return
        }

        let requestID = UUID().uuidString
        let uiAction = lifecycleDisplayAction(action)
        pendingByModelId[model.id] = PendingCommand(
            reqId: requestID,
            action: uiAction,
            requestedAt: Date().timeIntervalSince1970
        )

        Task.detached(priority: .userInitiated) { [requestData, launchConfig] in
            do {
                let payloadData = try LocalRuntimeCommandRunner.run(
                    command: "manage-local-model",
                    requestData: requestData,
                    launchConfig: launchConfig,
                    timeoutSec: 60.0
                )
                await MainActor.run {
                    self.finishProviderLifecycleCommand(
                        payloadData: payloadData,
                        modelId: model.id,
                        action: uiAction,
                        requestID: requestID
                    )
                }
            } catch {
                await MainActor.run {
                    self.finishProviderLifecycleCommandWithError(
                        error.localizedDescription,
                        modelId: model.id,
                        action: uiAction,
                        requestID: requestID
                    )
                }
            }
        }
    }


    private func finishProviderLifecycleCommand(
        payloadData: Data,
        modelId: String,
        action: String,
        requestID: String
    ) {
        let payload = (try? JSONSerialization.jsonObject(with: payloadData, options: [])) as? [String: Any] ?? [:]
        let ok = payload["ok"] as? Bool ?? false
        let message = lifecycleStatusLine(payload, action: action)
        let finishedAt = Date().timeIntervalSince1970
        if ok {
            applySuccessfulLocalLifecycleAction(
                action: action,
                modelId: modelId,
                finishedAt: finishedAt
            )
        }
        refresh()
        lastResultByModelId[modelId] = ModelCommandResult(
            type: "model_result",
            reqId: requestID,
            action: action,
            modelId: modelId,
            ok: ok,
            msg: message,
            finishedAt: finishedAt
        )
        if let pending = pendingByModelId[modelId], pending.reqId == requestID {
            pendingByModelId.removeValue(forKey: modelId)
        }
    }

    private func finishProviderLifecycleCommandWithError(
        _ message: String,
        modelId: String,
        action: String,
        requestID: String
    ) {
        let actionTitle = localizedLifecycleActionTitle(action)
        successfulLocalLifecycleActionsByModelId.removeValue(forKey: modelId)
        refresh()
        lastResultByModelId[modelId] = ModelCommandResult(
            type: "model_result",
            reqId: requestID,
            action: action,
            modelId: modelId,
            ok: false,
            msg: message.isEmpty
                ? HubUIStrings.Models.Runtime.ActionPlanner.lifecycleFailed(actionTitle)
                : HubUIStrings.Models.Runtime.ActionPlanner.lifecycleFailed(actionTitle: actionTitle, detail: message),
            finishedAt: Date().timeIntervalSince1970
        )
        if let pending = pendingByModelId[modelId], pending.reqId == requestID {
            pendingByModelId.removeValue(forKey: modelId)
        }
    }


    private func lifecycleDisplayAction(_ action: String) -> String {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "warmup_local_model":
            return "warmup"
        case "unload_local_model":
            return "unload"
        case "evict_local_instance":
            return "evict"
        default:
            return normalized.isEmpty ? "action" : normalized
        }
    }

    func lifecycleStatusLine(_ payload: [String: Any], action: String) -> String {
        let ok = payload["ok"] as? Bool ?? false
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let verb = localizedLifecycleActionTitle(normalizedAction)

        if ok {
            if normalizedAction == "warmup", payload["alreadyLoaded"] as? Bool == true {
                return HubUIStrings.Models.Runtime.ActionPlanner.lifecycleAlreadyLoaded(verb)
            }
            return HubUIStrings.Models.Runtime.ActionPlanner.lifecycleCompleted(verb)
        }

        let detail = LocalModelRuntimeErrorPresentation.humanized(
            (payload["errorDetail"] as? String ?? payload["error"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return detail.isEmpty
            ? HubUIStrings.Models.Runtime.ActionPlanner.lifecycleFailed(verb)
            : HubUIStrings.Models.Runtime.ActionPlanner.lifecycleFailed(actionTitle: verb, detail: detail)
    }

    private func localizedBenchVerdict(_ verdict: String) -> String {
        HubUIStrings.Models.Review.Bench.localizedVerdict(verdict)
    }

    private func localizedLifecycleActionTitle(_ action: String) -> String {
        switch action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "warmup", "warmup_local_model":
            return HubUIStrings.Models.Runtime.ActionPlanner.warmup
        case "unload", "unload_local_model":
            return HubUIStrings.Models.Runtime.ActionPlanner.unload
        case "evict", "evict_local_instance":
            return HubUIStrings.Models.Runtime.ActionPlanner.evict
        default:
            return action.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        }
    }

    func lifecycleFailureReasonCode(_ payload: [String: Any]) -> String? {
        let candidates = [
            payload["error"] as? String,
            payload["reasonCode"] as? String,
            payload["reason_code"] as? String,
            payload["runtimeReasonCode"] as? String,
            payload["runtime_reason_code"] as? String,
        ]
        for candidate in candidates {
            let token = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                return token
            }
        }
        return nil
    }

}
