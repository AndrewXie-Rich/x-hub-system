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

        pendingByModelId[model.id] = PendingCommand(
            reqId: reqId,
            action: action,
            requestedAt: Date().timeIntervalSince1970
        )
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
}
