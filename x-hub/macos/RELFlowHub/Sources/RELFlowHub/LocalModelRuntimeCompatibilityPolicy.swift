import Foundation
import RELFlowHubCore

struct LocalModelRuntimeCompatibilityIssue: Equatable {
    var code: String
    var summary: String
    var detail: String

    var userMessage: String {
        joinedMessage(summary: summary, detail: detail)
    }
}

private func joinedMessage(summary: String, detail: String) -> String {
    let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSummary.isEmpty else { return trimmedDetail }
    guard !trimmedDetail.isEmpty else { return trimmedSummary }
    let separator = trimmedSummary.hasSuffix("。")
        || trimmedSummary.hasSuffix(".")
        || trimmedSummary.hasSuffix("！")
        || trimmedSummary.hasSuffix("？")
        ? ""
        : " "
    return "\(trimmedSummary)\(separator)\(trimmedDetail)"
}

private final class LocalModelRuntimeCompatibilityCacheEntry: NSObject {
    let issue: LocalModelRuntimeCompatibilityIssue?
    let cachedAt: TimeInterval

    init(issue: LocalModelRuntimeCompatibilityIssue?, cachedAt: TimeInterval) {
        self.issue = issue
        self.cachedAt = cachedAt
    }
}

enum LocalModelRuntimeCompatibilityPolicy {
    nonisolated(unsafe) private static let cache = NSCache<NSString, LocalModelRuntimeCompatibilityCacheEntry>()
    private static let cacheTTLSeconds: TimeInterval = 8.0

    static func importWarning(
        modelPath: String,
        backend: String,
        taskKinds: [String] = [],
        executionProviderID: String? = nil,
        catalogSnapshot: ModelCatalogSnapshot? = nil,
        providerPackSnapshot: LocalProviderPackRegistrySnapshot? = nil,
        helperBinaryPath: String? = nil,
        probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig? = nil,
        pythonPath: String? = nil
    ) -> String? {
        importIssue(
            modelPath: modelPath,
            backend: backend,
            taskKinds: taskKinds,
            executionProviderID: executionProviderID,
            catalogSnapshot: catalogSnapshot,
            providerPackSnapshot: providerPackSnapshot,
            helperBinaryPath: helperBinaryPath,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        )?.userMessage
    }

    static func blockedActionMessage(
        action: String,
        model: HubModel,
        catalogSnapshot: ModelCatalogSnapshot? = nil,
        providerPackSnapshot: LocalProviderPackRegistrySnapshot? = nil,
        helperBinaryPath: String? = nil,
        probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig? = nil,
        pythonPath: String? = nil
    ) -> String? {
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedAction == "load" || normalizedAction == "warmup" else {
            return nil
        }
        let executionProviderID = LocalModelExecutionProviderResolver.preferredRuntimeProviderID(for: model)
        guard let issue = blockingIssue(
            modelPath: model.modelPath ?? "",
            backend: model.backend,
            taskKinds: model.taskKinds,
            executionProviderID: executionProviderID,
            catalogSnapshot: catalogSnapshot,
            providerPackSnapshot: providerPackSnapshot,
            helperBinaryPath: helperBinaryPath,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ) else {
            return nil
        }
        let strings = HubUIStrings.Models.RuntimeCompatibility.self
        let actionTitle = normalizedAction == "warmup" ? strings.warmupAction : strings.loadAction
        return strings.blockedAction(actionTitle: actionTitle, userMessage: issue.userMessage)
    }

    private static func importIssue(
        modelPath: String,
        backend: String,
        taskKinds: [String],
        executionProviderID: String?,
        catalogSnapshot: ModelCatalogSnapshot?,
        providerPackSnapshot: LocalProviderPackRegistrySnapshot?,
        helperBinaryPath: String?,
        probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig?,
        pythonPath: String?
    ) -> LocalModelRuntimeCompatibilityIssue? {
        cachedIssue(
            mode: "import",
            modelPath: modelPath,
            backend: backend,
            taskKinds: taskKinds,
            executionProviderID: executionProviderID,
            catalogSnapshot: catalogSnapshot,
            providerPackSnapshot: providerPackSnapshot,
            helperBinaryPath: helperBinaryPath,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ) {
            let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else { return nil }
            let normalizedBackend = backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedExecutionProvider = (
                executionProviderID ?? normalizedBackend
            ).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let modelURL = URL(fileURLWithPath: trimmedPath, isDirectory: true)
            let folderIntegrityIssue = LocalModelFolderIntegrityPolicy.issue(modelPath: trimmedPath)
            if normalizedExecutionProvider == "mlx" {
                let mlxIssue = mlxCompatibilityIssue(modelURL: modelURL)
                if let combined = mergedFolderIntegrityIssue(
                    issue: mlxIssue,
                    folderIntegrityIssue: folderIntegrityIssue
                ) {
                    return combined
                }
            } else if let folderIntegrityIssue {
                return LocalModelRuntimeCompatibilityIssue(
                    code: folderIntegrityIssue.code,
                    summary: folderIntegrityIssue.summary,
                    detail: folderIntegrityIssue.detail
                )
            }
            if let runtimeIssue = LocalModelRuntimeSupportProbe.issue(
                modelPath: trimmedPath,
                backend: normalizedExecutionProvider,
                taskKinds: taskKinds,
                catalogSnapshot: catalogSnapshot,
                providerPackSnapshot: providerPackSnapshot,
                helperBinaryPath: helperBinaryPath,
                launchConfig: probeLaunchConfig,
                pythonPath: pythonPath
            ) {
                return runtimeIssue
            }
            let nonPythonExecutionCoverage = LocalModelRuntimeSupportProbe.nonPythonExecutionCoverage(
                for: normalizedExecutionProvider,
                taskKinds: taskKinds,
                catalogSnapshot: catalogSnapshot,
                providerPackSnapshot: providerPackSnapshot,
                helperBinaryPath: helperBinaryPath
            )
            if normalizedExecutionProvider == "transformers",
               normalizedExecutionProvider == normalizedBackend,
               nonPythonExecutionCoverage?.coversAllRequestedTaskKinds != true,
               let warning = transformersRuntimeWarning(modelURL: modelURL) {
                return warning
            }
            guard normalizedExecutionProvider == "mlx" else { return nil }
            return mlxCompatibilityIssue(modelURL: modelURL)
        }
    }

    private static func blockingIssue(
        modelPath: String,
        backend: String,
        taskKinds: [String],
        executionProviderID: String?,
        catalogSnapshot: ModelCatalogSnapshot?,
        providerPackSnapshot: LocalProviderPackRegistrySnapshot?,
        helperBinaryPath: String?,
        probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig?,
        pythonPath: String?
    ) -> LocalModelRuntimeCompatibilityIssue? {
        cachedIssue(
            mode: "blocking",
            modelPath: modelPath,
            backend: backend,
            taskKinds: taskKinds,
            executionProviderID: executionProviderID,
            catalogSnapshot: catalogSnapshot,
            providerPackSnapshot: providerPackSnapshot,
            helperBinaryPath: helperBinaryPath,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        ) {
            let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else { return nil }
            let normalizedBackend = backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedExecutionProvider = (
                executionProviderID ?? normalizedBackend
            ).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let folderIntegrityIssue = LocalModelFolderIntegrityPolicy.issue(modelPath: trimmedPath)
            if normalizedExecutionProvider == "mlx" {
                let modelURL = URL(fileURLWithPath: trimmedPath, isDirectory: true)
                let mlxIssue = mlxCompatibilityIssue(modelURL: modelURL)
                if let combined = mergedFolderIntegrityIssue(
                    issue: mlxIssue,
                    folderIntegrityIssue: folderIntegrityIssue
                ) {
                    return combined
                }
            } else if let folderIntegrityIssue {
                return LocalModelRuntimeCompatibilityIssue(
                    code: folderIntegrityIssue.code,
                    summary: folderIntegrityIssue.summary,
                    detail: folderIntegrityIssue.detail
                )
            }
            if let runtimeIssue = LocalModelRuntimeSupportProbe.issue(
                modelPath: trimmedPath,
                backend: normalizedExecutionProvider,
                taskKinds: taskKinds,
                catalogSnapshot: catalogSnapshot,
                providerPackSnapshot: providerPackSnapshot,
                helperBinaryPath: helperBinaryPath,
                launchConfig: probeLaunchConfig,
                pythonPath: pythonPath
            ) {
                return runtimeIssue
            }
            guard normalizedExecutionProvider == "mlx" else { return nil }
            let modelURL = URL(fileURLWithPath: trimmedPath, isDirectory: true)
            return mlxCompatibilityIssue(modelURL: modelURL)
        }
    }

    private static func cachedIssue(
        mode: String,
        modelPath: String,
        backend: String,
        taskKinds: [String],
        executionProviderID: String?,
        catalogSnapshot: ModelCatalogSnapshot?,
        providerPackSnapshot: LocalProviderPackRegistrySnapshot?,
        helperBinaryPath: String?,
        probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig?,
        pythonPath: String?,
        compute: () -> LocalModelRuntimeCompatibilityIssue?
    ) -> LocalModelRuntimeCompatibilityIssue? {
        let cacheKey = compatibilityCacheKey(
            mode: mode,
            modelPath: modelPath,
            backend: backend,
            taskKinds: taskKinds,
            executionProviderID: executionProviderID,
            catalogSnapshot: catalogSnapshot,
            providerPackSnapshot: providerPackSnapshot,
            helperBinaryPath: helperBinaryPath,
            probeLaunchConfig: probeLaunchConfig,
            pythonPath: pythonPath
        )
        let now = Date().timeIntervalSince1970
        if let cached = cache.object(forKey: cacheKey),
           now - cached.cachedAt <= cacheTTLSeconds {
            return cached.issue
        }
        let issue = compute()
        cache.setObject(
            LocalModelRuntimeCompatibilityCacheEntry(issue: issue, cachedAt: now),
            forKey: cacheKey
        )
        return issue
    }

    private static func compatibilityCacheKey(
        mode: String,
        modelPath: String,
        backend: String,
        taskKinds: [String],
        executionProviderID: String?,
        catalogSnapshot: ModelCatalogSnapshot?,
        providerPackSnapshot: LocalProviderPackRegistrySnapshot?,
        helperBinaryPath: String?,
        probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig?,
        pythonPath: String?
    ) -> NSString {
        let normalizedTaskKinds = taskKinds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .sorted()
        let normalizedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBackend = backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedExecutionProvider = (
            executionProviderID ?? normalizedBackend
        ).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedPythonPath = (
            probeLaunchConfig?.resolvedPythonPath ?? pythonPath ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let pythonPathEnvironment = (
            probeLaunchConfig?.environment["PYTHONPATH"] ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHelperBinaryPath = (
            helperBinaryPath ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            mode,
            normalizedPath,
            normalizedBackend,
            normalizedExecutionProvider,
            resolvedPythonPath,
            pythonPathEnvironment,
            normalizedTaskKinds.joined(separator: ","),
            normalizedHelperBinaryPath,
            LocalModelRuntimeSupportProbe.nonPythonExecutionCacheSignature(),
            catalogSignature(catalogSnapshot),
            providerPackSignature(providerPackSnapshot),
        ].joined(separator: "|") as NSString
    }

    private static func catalogSignature(_ snapshot: ModelCatalogSnapshot?) -> String {
        guard let snapshot else { return "" }
        return snapshot.models
            .map { model in
                let providerID = (model.runtimeProviderID ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let taskKinds = LocalModelCapabilityDefaults.normalizedStringList(model.taskKinds, fallback: [])
                    .joined(separator: ",")
                return [
                    model.id.trimmingCharacters(in: .whitespacesAndNewlines),
                    model.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    providerID,
                    model.modelPath.trimmingCharacters(in: .whitespacesAndNewlines),
                    taskKinds,
                ].joined(separator: "^")
            }
            .sorted()
            .joined(separator: ";")
    }

    private static func providerPackSignature(_ snapshot: LocalProviderPackRegistrySnapshot?) -> String {
        guard let snapshot else { return "" }
        return snapshot.packs
            .map { pack in
                [
                    pack.providerId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    pack.runtimeRequirements.executionMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    pack.runtimeRequirements.helperBinary.trimmingCharacters(in: .whitespacesAndNewlines),
                    pack.note.trimmingCharacters(in: .whitespacesAndNewlines),
                ].joined(separator: "^")
            }
            .sorted()
            .joined(separator: ";")
    }

    private static func mergedFolderIntegrityIssue(
        issue: LocalModelRuntimeCompatibilityIssue?,
        folderIntegrityIssue: LocalModelFolderIntegrityIssue?
    ) -> LocalModelRuntimeCompatibilityIssue? {
        guard let issue else {
            if let folderIntegrityIssue {
                return LocalModelRuntimeCompatibilityIssue(
                    code: folderIntegrityIssue.code,
                    summary: folderIntegrityIssue.summary,
                    detail: folderIntegrityIssue.detail
                )
            }
            return nil
        }
        guard let folderIntegrityIssue else {
            return issue
        }

        var detailParts: [String] = []
        let normalizedDetail = issue.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedDetail.isEmpty {
            detailParts.append(normalizedDetail)
        }
        detailParts.append(HubUIStrings.Models.RuntimeCompatibility.directoryIntegrity(folderIntegrityIssue.userMessage))

        return LocalModelRuntimeCompatibilityIssue(
            code: "\(issue.code)+\(folderIntegrityIssue.code)",
            summary: issue.summary,
            detail: detailParts.joined(separator: " ")
        )
    }

    private static func mlxCompatibilityIssue(modelURL: URL) -> LocalModelRuntimeCompatibilityIssue? {
        let config = readJSON(modelURL.appendingPathComponent("config.json")) ?? [:]
        let preprocessor = readJSON(modelURL.appendingPathComponent("preprocessor_config.json")) ?? [:]
        let videoPreprocessorExists = FileManager.default.fileExists(
            atPath: modelURL.appendingPathComponent("video_preprocessor_config.json").path
        )

        let modelType = stringValue(config["model_type"]).lowercased()
        let architectures = stringList(config["architectures"]).joined(separator: " ").lowercased()
        let imageProcessorType = stringValue(preprocessor["image_processor_type"]).lowercased()
        let processorClass = stringValue(preprocessor["processor_class"]).lowercased()

        let multimodalKeywordMatched = containsAny(
            [modelType, architectures, imageProcessorType, processorClass].joined(separator: " "),
            keywords: [
                "glm4v",
                "qwen2_vl",
                "qwen3_vl",
                "qwen3vl",
                "pixtral",
                "mistral3",
                "llava",
                "florence",
                "blip",
                "siglip",
                "pix2struct",
                "vision",
            ]
        )
        let hasVisionConfig = config["vision_config"] is [String: Any]
        let hasImageProcessor = !imageProcessorType.isEmpty

        guard multimodalKeywordMatched || hasVisionConfig || videoPreprocessorExists || hasImageProcessor else {
            return nil
        }

        let detailParts = [
            !modelType.isEmpty ? HubUIStrings.Models.RuntimeCompatibility.modelType(modelType) : "",
            hasVisionConfig ? HubUIStrings.Models.RuntimeCompatibility.configHasVisionConfig : "",
            hasImageProcessor ? HubUIStrings.Models.RuntimeCompatibility.preprocessorExposesImageProcessor : "",
            videoPreprocessorExists ? HubUIStrings.Models.RuntimeCompatibility.videoPreprocessorExists : "",
        ].filter { !$0.isEmpty }

        return LocalModelRuntimeCompatibilityIssue(
            code: "mlx_multimodal_model_not_supported",
            summary: HubUIStrings.Models.RuntimeCompatibility.mlxMultimodalSummary,
            detail: detailParts.joined(separator: " ")
        )
    }

    private static func transformersRuntimeWarning(modelURL: URL) -> LocalModelRuntimeCompatibilityIssue? {
        let config = readJSON(modelURL.appendingPathComponent("config.json")) ?? [:]
        guard !config.isEmpty else { return nil }

        let modelType = stringValue(config["model_type"]).lowercased()
        let architectures = stringList(config["architectures"]).joined(separator: " ").lowercased()
        let declaredTransformersVersion = stringValue(config["transformers_version"])
        let hasVisionConfig = config["vision_config"] is [String: Any]
        let riskyModelTypes: Set<String> = ["glm4v", "qwen3_vl_moe", "mistral3"]
        let riskyArchitectures = ["glm4v", "qwen3vl", "mistral3"]
        let riskyModel = riskyModelTypes.contains(modelType)
            || riskyArchitectures.contains(where: { architectures.contains($0) })
        let needsNextGenTransformers = declaredTransformersVersion.hasPrefix("5.")
            || declaredTransformersVersion.lowercased().contains("rc")
            || declaredTransformersVersion.lowercased().contains("dev")

        guard riskyModel || (hasVisionConfig && needsNextGenTransformers) else {
            return nil
        }

        var detailParts: [String] = []
        if !modelType.isEmpty {
            detailParts.append(HubUIStrings.Models.RuntimeCompatibility.modelType(modelType))
        }
        if !declaredTransformersVersion.isEmpty {
            detailParts.append(HubUIStrings.Models.RuntimeCompatibility.transformersVersion(declaredTransformersVersion))
        }
        if riskyModel {
            detailParts.append(
                HubUIStrings.Models.RuntimeCompatibility.unsupportedModelType(
                    modelType.isEmpty ? "unknown" : modelType
                )
            )
        } else {
            detailParts.append(HubUIStrings.Models.RuntimeCompatibility.transformersHigherVersionRequired)
        }

        return LocalModelRuntimeCompatibilityIssue(
            code: "transformers_runtime_version_risk",
            summary: HubUIStrings.Models.RuntimeCompatibility.transformersRuntimeWarningSummary,
            detail: detailParts.joined(separator: " ")
        )
    }

    private static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    private static func stringValue(_ raw: Any?) -> String {
        (raw as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stringList(_ raw: Any?) -> [String] {
        guard let values = raw as? [Any] else { return [] }
        return values.compactMap { value in
            let token = stringValue(value)
            return token.isEmpty ? nil : token
        }
    }

    private static func containsAny(_ haystack: String, keywords: [String]) -> Bool {
        keywords.contains { haystack.contains($0) }
    }
}
