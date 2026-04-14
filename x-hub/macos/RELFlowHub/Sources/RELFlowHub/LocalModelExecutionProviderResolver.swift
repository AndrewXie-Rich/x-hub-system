import Foundation
import RELFlowHubCore

enum LocalModelExecutionProviderResolver {
    private static let helperBridgeTaskKinds: Set<String> = [
        "vision_understand",
        "ocr",
    ]
    private static let alwaysExplicitRuntimeProviderIDs: Set<String> = [
        "llama.cpp",
    ]

    static func preferredRuntimeProviderID(
        for model: HubModel,
        helperBinaryPath: String = LocalHelperBridgeDiscovery.discoverHelperBinary()
    ) -> String {
        preferredRuntimeProviderID(
            backend: model.backend,
            runtimeProviderID: model.runtimeProviderID,
            modelPath: model.modelPath ?? "",
            taskKinds: model.taskKinds,
            helperBinaryPath: helperBinaryPath
        )
    }

    static func preferredRuntimeProviderID(
        for entry: ModelCatalogEntry,
        helperBinaryPath: String = LocalHelperBridgeDiscovery.discoverHelperBinary()
    ) -> String {
        preferredRuntimeProviderID(
            backend: entry.backend,
            runtimeProviderID: entry.runtimeProviderID,
            modelPath: entry.modelPath,
            taskKinds: entry.taskKinds,
            helperBinaryPath: helperBinaryPath
        )
    }

    static func suggestedRuntimeProviderID(
        backend: String,
        modelPath: String,
        taskKinds: [String],
        helperBinaryPath: String = LocalHelperBridgeDiscovery.discoverHelperBinary()
    ) -> String? {
        let preferred = preferredRuntimeProviderID(
            backend: backend,
            runtimeProviderID: nil,
            modelPath: modelPath,
            taskKinds: taskKinds,
            helperBinaryPath: helperBinaryPath
        )
        let normalizedBackendValue = normalizedBackend(backend)
        if preferred == normalizedBackendValue,
           !alwaysExplicitRuntimeProviderIDs.contains(preferred) {
            return nil
        }
        return preferred
    }

    static func backfilled(
        _ model: HubModel,
        helperBinaryPath: String = LocalHelperBridgeDiscovery.discoverHelperBinary()
    ) -> HubModel {
        let preferred = preferredRuntimeProviderID(for: model, helperBinaryPath: helperBinaryPath)
        let normalizedCurrent = normalizedProvider(model.runtimeProviderID)
        let normalizedBackendValue = normalizedBackend(model.backend)
        if preferred == normalizedBackendValue {
            if alwaysExplicitRuntimeProviderIDs.contains(preferred) {
                if normalizedCurrent == preferred {
                    return model
                }
                var updated = model
                updated.runtimeProviderID = preferred
                return updated
            }
            if normalizedCurrent.isEmpty {
                return model
            }
            var updated = model
            updated.runtimeProviderID = nil
            return updated
        }
        if preferred == normalizedCurrent {
            return model
        }
        var updated = model
        updated.runtimeProviderID = preferred
        return updated
    }

    static func backfilled(
        _ entry: ModelCatalogEntry,
        helperBinaryPath: String = LocalHelperBridgeDiscovery.discoverHelperBinary()
    ) -> ModelCatalogEntry {
        let preferred = preferredRuntimeProviderID(for: entry, helperBinaryPath: helperBinaryPath)
        let normalizedCurrent = normalizedProvider(entry.runtimeProviderID)
        let normalizedBackendValue = normalizedBackend(entry.backend)
        if preferred == normalizedBackendValue {
            if alwaysExplicitRuntimeProviderIDs.contains(preferred) {
                if normalizedCurrent == preferred {
                    return entry
                }
                var updated = entry
                updated.runtimeProviderID = preferred
                return updated
            }
            if normalizedCurrent.isEmpty {
                return entry
            }
            var updated = entry
            updated.runtimeProviderID = nil
            return updated
        }
        if preferred == normalizedCurrent {
            return entry
        }
        var updated = entry
        updated.runtimeProviderID = preferred
        return updated
    }

    private static func preferredRuntimeProviderID(
        backend: String,
        runtimeProviderID: String?,
        modelPath: String,
        taskKinds: [String],
        helperBinaryPath: String
    ) -> String {
        let explicit = normalizedProvider(runtimeProviderID)
        if !explicit.isEmpty {
            return explicit
        }
        if shouldUseMLXVLMRuntimeProvider(
            backend: backend,
            modelPath: modelPath,
            taskKinds: taskKinds,
            helperBinaryPath: helperBinaryPath
        ) {
            return "mlx_vlm"
        }
        return normalizedBackend(backend)
    }

    private static func shouldUseMLXVLMRuntimeProvider(
        backend: String,
        modelPath: String,
        taskKinds: [String],
        helperBinaryPath: String
    ) -> Bool {
        guard normalizedBackend(backend) == "mlx" else {
            return false
        }
        guard !modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard !helperBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let normalizedTaskKinds = Set(
            taskKinds
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        return !normalizedTaskKinds.isDisjoint(with: helperBridgeTaskKinds)
    }

    private static func normalizedBackend(_ raw: String) -> String {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return token.isEmpty ? "unknown" : token
    }

    private static func normalizedProvider(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
