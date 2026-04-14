import Foundation

@MainActor
extension ProjectModel {
    var configuredCoderModelId: String {
        configuredModelId(for: .coder) ?? currentModel.id
    }

    var configuredCoderModelInfo: ModelInfo {
        configuredModelInfo(for: .coder)
    }

    func configuredModelId(for role: AXRole) -> String? {
        let persisted = persistedProjectConfig?.modelOverride(for: role)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !persisted.isEmpty {
            return persisted
        }

        let current = currentModel.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty ? nil : current
    }

    func configuredModelInfo(for role: AXRole) -> ModelInfo {
        let configured = configuredModelId(for: role)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !configured.isEmpty else { return currentModel }
        if configured == currentModel.id.trimmingCharacters(in: .whitespacesAndNewlines) {
            return currentModel
        }
        return XTModelCatalog.modelInfo(
            for: configured,
            preferLocalHint: configured.lowercased().contains("local")
                || configured.lowercased().contains("mlx")
        )
    }

    private var persistedProjectConfig: AXProjectConfig? {
        guard let ctx = persistedProjectContext else { return nil }
        return try? AXProjectStore.loadOrCreateConfig(for: ctx)
    }

    private var persistedProjectContext: AXProjectContext? {
        let rootPath = registeredProjectRootPath?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rootPath.isEmpty else { return nil }
        return AXProjectContext(root: URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL)
    }
}
