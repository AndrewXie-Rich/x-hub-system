import Foundation
import RELFlowHubCore

struct LocalModelImportBackendDetection: Equatable {
    var backend: String
    var sourceSummary: String
}

struct LocalModelImportCapabilityDetection: Equatable {
    var modelFormat: String
    var taskKinds: [String]
    var inputModalities: [String]
    var outputModalities: [String]
    var processorRequirements: ModelProcessorRequirements
    var sourceSummary: String
}

struct LocalModelImportRuntimeReadiness: Equatable {
    var providerID: String
    var canLoadNow: Bool
    var packState: String
    var packReasonCode: String
    var runtimeResolutionState: String
    var runtimeReasonCode: String
    var statusSummary: String
    var issueText: String

    static func empty(providerID: String) -> LocalModelImportRuntimeReadiness {
        LocalModelImportRuntimeReadiness(
            providerID: providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            canLoadNow: false,
            packState: "",
            packReasonCode: "",
            runtimeResolutionState: "",
            runtimeReasonCode: "",
            statusSummary: "",
            issueText: ""
        )
    }
}

enum LocalModelImportDetector {
    static func detectBackend(
        for directory: URL,
        manifest: XHubLocalModelManifest? = nil,
        config: [String: Any]? = nil
    ) -> LocalModelImportBackendDetection {
        if let manifestBackend = normalizeBackend(manifest?.backend),
           supportedBackends.contains(manifestBackend) {
            return LocalModelImportBackendDetection(
                backend: manifestBackend,
                sourceSummary: "backend manifest"
            )
        }

        let lowerFolderName = directory.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fileNames = lowercasedDirectoryEntries(at: directory)

        if hasGGUFModelSignal(fileNames) {
            return LocalModelImportBackendDetection(
                backend: "llama.cpp",
                sourceSummary: "backend gguf signature"
            )
        }

        if fileNames.contains("weights.npz")
            || fileNames.contains("params.json")
            || fileNames.contains("consolidated.safetensors.index.json") {
            return LocalModelImportBackendDetection(
                backend: "mlx",
                sourceSummary: "backend folder signature"
            )
        }

        if lowerFolderName.contains("mlx"),
           (fileNames.contains("model.safetensors.index.json")
                || fileNames.contains("consolidated.safetensors.index.json")
                || fileNames.contains("weights.npz")
                || fileNames.contains("params.json")) {
            return LocalModelImportBackendDetection(
                backend: "mlx",
                sourceSummary: "backend mlx folder heuristic"
            )
        }

        if hasTransformersProcessorSignal(fileNames) || hasExplicitTransformersMultimodalSignal(config) {
            return LocalModelImportBackendDetection(
                backend: "transformers",
                sourceSummary: hasTransformersProcessorSignal(fileNames)
                    ? "backend processor signature"
                    : "backend config heuristic"
            )
        }

        if lowerFolderName.contains("mlx") {
            return LocalModelImportBackendDetection(
                backend: "mlx",
                sourceSummary: "backend name heuristic"
            )
        }

        if hasExplicitMLXConfigSignal(config) {
            return LocalModelImportBackendDetection(
                backend: "mlx",
                sourceSummary: "backend config heuristic"
            )
        }

        if fileNames.contains("config.json") {
            return LocalModelImportBackendDetection(
                backend: "transformers",
                sourceSummary: "backend config fallback"
            )
        }

        return LocalModelImportBackendDetection(
            backend: "mlx",
            sourceSummary: "backend default"
        )
    }

    private static let supportedBackends: Set<String> = ["mlx", "transformers", "llama.cpp"]

    static func detectCapabilities(
        for directory: URL,
        backend: String,
        manifest: XHubLocalModelManifest? = nil,
        config: [String: Any]? = nil
    ) -> LocalModelImportCapabilityDetection? {
        guard let normalizedBackend = normalizeBackend(backend) else {
            return nil
        }

        if let manifest,
           normalizeBackend(manifest.backend) == normalizedBackend {
            return LocalModelImportCapabilityDetection(
                modelFormat: manifest.modelFormat,
                taskKinds: manifest.taskKinds,
                inputModalities: manifest.inputModalities,
                outputModalities: manifest.outputModalities,
                processorRequirements: manifest.processorRequirements,
                sourceSummary: XHubLocalModelManifestLoader.fileName
            )
        }

        switch normalizedBackend {
        case "mlx":
            let modelFormat = LocalModelCapabilityDefaults.defaultModelFormat(forBackend: normalizedBackend)
            let taskKinds = LocalModelCapabilityDefaults.defaultTaskKinds(forBackend: normalizedBackend)
            return LocalModelImportCapabilityDetection(
                modelFormat: modelFormat,
                taskKinds: taskKinds,
                inputModalities: LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: taskKinds),
                outputModalities: LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: taskKinds),
                processorRequirements: LocalModelCapabilityDefaults.defaultProcessorRequirements(
                    backend: normalizedBackend,
                    modelFormat: modelFormat,
                    taskKinds: taskKinds
                ),
                sourceSummary: "inferred: mlx"
            )
        case "llama.cpp":
            return inferGGUFCapabilities(for: directory)
        case "transformers":
            return inferTransformersCapabilities(for: directory, config: config)
        default:
            return nil
        }
    }

    static func detectRuntimeReadiness(
        for providerID: String,
        runtimeStatus: AIRuntimeStatus?,
        importWarning: String = "",
        providerHint: String = "",
        autoRecoveryAvailable: Bool = false
    ) -> LocalModelImportRuntimeReadiness {
        let normalizedProvider = normalizeBackend(providerID) ?? ""
        guard !normalizedProvider.isEmpty else {
            return .empty(providerID: providerID)
        }

        let providerStatus = runtimeStatus?.providerStatus(normalizedProvider)
        let packStatus = runtimeStatus?.providerPackStatus(normalizedProvider)

        let packSummary = humanizedPackSummary(packStatus, providerStatus: providerStatus)
        let runtimeSummary = humanizedRuntimeSummary(providerStatus)
        let summaryParts = [packSummary, runtimeSummary].filter { !$0.isEmpty }
        var issueParts = mergedIssueParts(importWarning: importWarning, providerHint: providerHint)

        if issueParts.isEmpty, let packIssue = packIssueText(providerID: normalizedProvider, packStatus: packStatus) {
            issueParts.append(packIssue)
        }
        if autoRecoveryAvailable,
           let providerStatus,
           !providerStatus.ok {
            issueParts.append(
                HubUIStrings.Models.AddLocal.Readiness.autoRecoveryHint(normalizedProvider)
            )
        }

        return LocalModelImportRuntimeReadiness(
            providerID: normalizedProvider,
            canLoadNow: providerStatus?.ok ?? false,
            packState: packStatus?.packState ?? providerStatus?.packState ?? "",
            packReasonCode: packStatus?.reasonCode ?? providerStatus?.packReasonCode ?? "",
            runtimeResolutionState: providerStatus?.runtimeResolutionState ?? "",
            runtimeReasonCode: providerStatus?.runtimeReasonCode ?? "",
            statusSummary: HubUIStrings.Formatting.middleDotSeparated(summaryParts),
            issueText: issueParts.joined(separator: "\n\n")
        )
    }

    private static func lowercasedDirectoryEntries(at directory: URL) -> Set<String> {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return Set(entries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    }

    private static func normalizeBackend(_ raw: String?) -> String? {
        let token = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return token.isEmpty ? nil : token
    }

    private static func hasTransformersProcessorSignal(_ fileNames: Set<String>) -> Bool {
        fileNames.contains("processor_config.json")
            || fileNames.contains("preprocessor_config.json")
            || fileNames.contains("feature_extractor_config.json")
            || fileNames.contains("video_preprocessor_config.json")
    }

    private static func hasGGUFModelSignal(_ fileNames: Set<String>) -> Bool {
        fileNames.contains { $0.hasSuffix(".gguf") }
    }

    private static func hasExplicitMLXConfigSignal(_ config: [String: Any]?) -> Bool {
        guard let config else { return false }
        if let modelType = config["model_type"] as? String, modelType.lowercased().contains("mlx") {
            return true
        }
        return false
    }

    private static func hasExplicitTransformersMultimodalSignal(_ config: [String: Any]?) -> Bool {
        guard let config else { return false }
        if config["vision_config"] is [String: Any] {
            return true
        }
        let modelType = stringValue(config["model_type"]).lowercased()
        let architectures = stringList(config["architectures"]).joined(separator: " ").lowercased()
        let haystack = [modelType, architectures].joined(separator: " ")
        return containsAny(
            haystack,
            keywords: [
                "glm4v",
                "qwen2_vl",
                "qwen3_vl",
                "qwen3vl",
                "llava",
                "pixtral",
                "mistral3",
                "blip",
                "siglip",
                "florence",
                "pix2struct",
                "vision",
            ]
        )
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

    private static func inferTransformersCapabilities(
        for directory: URL,
        config: [String: Any]?
    ) -> LocalModelImportCapabilityDetection? {
        let folderName = directory.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileNames = lowercasedDirectoryEntries(at: directory)
        let architectures = stringList(config?["architectures"]).joined(separator: " ").lowercased()
        let modelType = stringValue(config?["model_type"]).lowercased()
        let nameSignal = folderName.lowercased()
        let haystack = [architectures, modelType, nameSignal].joined(separator: " ")
        let modelFormat = LocalModelCapabilityDefaults.defaultModelFormat(forBackend: "transformers")

        if containsAny(haystack, keywords: ["text-to-speech", "text_to_speech", "kokoro", "melo", "parler", "vits", "bark", "speechsynth", "speech_t5", "tts"]) {
            return LocalModelImportCapabilityDetection(
                modelFormat: modelFormat,
                taskKinds: ["text_to_speech"],
                inputModalities: ["text"],
                outputModalities: ["audio"],
                processorRequirements: ModelProcessorRequirements(
                    tokenizerRequired: true,
                    processorRequired: false,
                    featureExtractorRequired: false
                ),
                sourceSummary: "inferred: config/tts"
            )
        }

        if containsAny(haystack, keywords: ["whisper", "wav2vec", "hubert", "speech", "asr", "ctc"]) {
            return LocalModelImportCapabilityDetection(
                modelFormat: modelFormat,
                taskKinds: ["speech_to_text"],
                inputModalities: ["audio"],
                outputModalities: ["text", "segments"],
                processorRequirements: ModelProcessorRequirements(
                    tokenizerRequired: false,
                    processorRequired: true,
                    featureExtractorRequired: true
                ),
                sourceSummary: "inferred: config/audio"
            )
        }

        if containsAny(haystack, keywords: ["trocr", "donut", "ocr"]) {
            return LocalModelImportCapabilityDetection(
                modelFormat: modelFormat,
                taskKinds: ["ocr"],
                inputModalities: ["image"],
                outputModalities: ["text", "spans"],
                processorRequirements: ModelProcessorRequirements(
                    tokenizerRequired: true,
                    processorRequired: true,
                    featureExtractorRequired: true
                ),
                sourceSummary: "inferred: config/ocr"
            )
        }

        if hasExplicitTransformersMultimodalSignal(config)
            || (hasTransformersProcessorSignal(fileNames) && containsAny(haystack, keywords: [
                "glm4v",
                "qwen2_vl",
                "qwen3_vl",
                "qwen3vl",
                "llava",
                "pixtral",
                "mistral3",
                "blip",
                "siglip",
                "florence",
                "pix2struct",
                "vision",
                "vl",
            ])) {
            return LocalModelImportCapabilityDetection(
                modelFormat: modelFormat,
                taskKinds: ["vision_understand", "ocr"],
                inputModalities: ["image"],
                outputModalities: ["text", "spans"],
                processorRequirements: ModelProcessorRequirements(
                    tokenizerRequired: true,
                    processorRequired: true,
                    featureExtractorRequired: true
                ),
                sourceSummary: "inferred: config/vision"
            )
        }

        if containsAny(haystack, keywords: ["bge", "gte", "e5", "mpnet", "sentence", "jina", "embed"]) {
            return LocalModelImportCapabilityDetection(
                modelFormat: modelFormat,
                taskKinds: ["embedding"],
                inputModalities: ["text"],
                outputModalities: ["embedding"],
                processorRequirements: ModelProcessorRequirements(
                    tokenizerRequired: true,
                    processorRequired: false,
                    featureExtractorRequired: false
                ),
                sourceSummary: "inferred: config/embedding"
            )
        }

        return nil
    }

    private static func inferGGUFCapabilities(
        for directory: URL
    ) -> LocalModelImportCapabilityDetection {
        let folderName = directory.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fileNames = lowercasedDirectoryEntries(at: directory)
        let ggufNames = fileNames.filter { $0.hasSuffix(".gguf") }
        let haystack = ([folderName] + ggufNames).joined(separator: " ")
        let modelFormat = "gguf"

        if containsAny(haystack, keywords: ["bge", "gte", "e5", "jina", "embed", "embedding"]) {
            let taskKinds = ["embedding"]
            return LocalModelImportCapabilityDetection(
                modelFormat: modelFormat,
                taskKinds: taskKinds,
                inputModalities: LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: taskKinds),
                outputModalities: LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: taskKinds),
                processorRequirements: LocalModelCapabilityDefaults.defaultProcessorRequirements(
                    backend: "llama.cpp",
                    modelFormat: modelFormat,
                    taskKinds: taskKinds
                ),
                sourceSummary: "inferred: gguf/embedding"
            )
        }

        if containsAny(haystack, keywords: ["llava", "vision", "qwen2-vl", "qwen3-vl", "minicpm-v", "pixtral", "ocr", "vl"]) {
            let taskKinds = ["vision_understand", "ocr"]
            return LocalModelImportCapabilityDetection(
                modelFormat: modelFormat,
                taskKinds: taskKinds,
                inputModalities: ["image"],
                outputModalities: ["text", "spans"],
                processorRequirements: LocalModelCapabilityDefaults.defaultProcessorRequirements(
                    backend: "llama.cpp",
                    modelFormat: modelFormat,
                    taskKinds: taskKinds
                ),
                sourceSummary: "inferred: gguf/vision"
            )
        }

        let taskKinds = ["text_generate"]
        return LocalModelImportCapabilityDetection(
            modelFormat: modelFormat,
            taskKinds: taskKinds,
            inputModalities: LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: taskKinds),
            outputModalities: LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: taskKinds),
            processorRequirements: LocalModelCapabilityDefaults.defaultProcessorRequirements(
                backend: "llama.cpp",
                modelFormat: modelFormat,
                taskKinds: taskKinds
            ),
            sourceSummary: "inferred: gguf/text"
        )
    }

    private static func humanizedPackSummary(
        _ packStatus: AIRuntimeProviderPackStatus?,
        providerStatus: AIRuntimeProviderStatus?
    ) -> String {
        let strings = HubUIStrings.Models.AddLocal.Readiness.self
        if let packStatus {
            if !packStatus.installed {
                return strings.packNotInstalled
            }
            if !packStatus.enabled || packStatus.packState == "disabled" {
                return strings.packDisabled
            }
            return strings.packReady
        }

        if let providerStatus {
            if providerStatus.packInstalled == false {
                return strings.packNotInstalled
            }
            if providerStatus.packEnabled == false, !providerStatus.packState.isEmpty {
                return strings.packDisabled
            }
            if !providerStatus.packState.isEmpty || !providerStatus.packVersion.isEmpty {
                return strings.packReady
            }
        }

        return strings.packUnknown
    }

    private static func humanizedRuntimeSummary(_ providerStatus: AIRuntimeProviderStatus?) -> String {
        let strings = HubUIStrings.Models.AddLocal.Readiness.self
        guard let providerStatus else {
            return strings.runtimeUnknown
        }
        if providerStatus.runtimeSource == "xhub_local_service" {
            if providerStatus.ok {
                return strings.runtimeHubLocalService
            }
            switch providerStatus.runtimeReasonCode {
            case "xhub_local_service_config_missing":
                return strings.runtimeHubLocalServiceConfigMissing
            case "xhub_local_service_starting":
                return strings.runtimeHubLocalServiceStarting
            case "xhub_local_service_unreachable",
                "xhub_local_service_not_ready":
                return strings.runtimeHubLocalServiceUnavailable
            default:
                return strings.runtimeHubLocalServiceUnavailable
            }
        }
        if providerStatus.runtimeSource == "helper_binary_bridge" {
            if providerStatus.ok {
                return strings.runtimeLocalHelper
            }
            switch providerStatus.runtimeReasonCode {
            case "helper_binary_missing":
                return strings.runtimeLocalHelperMissing
            case "helper_local_service_disabled",
                "helper_service_down",
                "helper_probe_timeout",
                "helper_probe_failed",
                "helper_server_down",
                "helper_server_unreachable",
                "helper_server_start_failed":
                return strings.runtimeLocalHelperUnavailable
            default:
                return strings.runtimeLocalHelperUnavailable
            }
        }
        if providerStatus.ok {
            if providerStatus.runtimeResolutionState == "user_runtime_fallback" || providerStatus.fallbackUsed {
                return strings.runtimeUserPython
            }
            if providerStatus.reasonCode == "fallback_ready" {
                return strings.runtimeFallbackOnly
            }
            return strings.runtimeReady
        }
        if providerStatus.runtimeReasonCode == "native_dependency_error" {
            return strings.runtimeNativeDependencyBlocked
        }
        if providerStatus.runtimeResolutionState == "runtime_missing" {
            return strings.runtimeMissing
        }
        if let importError = providerStatus.importError,
           !importError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return strings.runtimeUnavailable
        }
        return strings.runtimeUnavailable
    }

    private static func packIssueText(
        providerID: String,
        packStatus: AIRuntimeProviderPackStatus?
    ) -> String? {
        let strings = HubUIStrings.Models.AddLocal.Readiness.self
        guard let packStatus else { return nil }
        if !packStatus.installed {
            return strings.packNotInstalledIssue(providerID)
        }
        if !packStatus.enabled || packStatus.packState == "disabled" {
            return strings.packDisabledIssue(providerID)
        }
        return nil
    }

    private static func mergedIssueParts(importWarning: String, providerHint: String) -> [String] {
        let strings = HubUIStrings.Models.AddLocal.Readiness.self
        let normalizedImport = importWarning.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProvider = providerHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedImport.isEmpty {
            return normalizedProvider.isEmpty ? [] : [normalizedProvider]
        }
        if normalizedProvider.isEmpty {
            return [normalizedImport]
        }

        let lowerImport = normalizedImport.lowercased()
        let lowerProvider = normalizedProvider.lowercased()
        if lowerProvider.contains(lowerImport) {
            return [normalizedProvider]
        }
        if lowerImport.contains(lowerProvider) {
            return [normalizedImport]
        }
        return [normalizedImport, strings.runtimeHint(normalizedProvider)]
    }
}
