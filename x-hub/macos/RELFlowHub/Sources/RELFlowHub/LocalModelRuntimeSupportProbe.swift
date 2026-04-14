import Foundation
import RELFlowHubCore

private final class LocalModelRuntimeSupportProbeCacheEntry: NSObject {
    let issue: LocalModelRuntimeCompatibilityIssue?
    let cachedAt: TimeInterval

    init(issue: LocalModelRuntimeCompatibilityIssue?, cachedAt: TimeInterval) {
        self.issue = issue
        self.cachedAt = cachedAt
    }
}

struct LocalModelNonPythonExecutionCoverage {
    let coversAllRequestedTaskKinds: Bool
    let helperBackedTaskKinds: Set<String>
    let helperBinaryPath: String
}

enum LocalModelRuntimeSupportProbe {
    nonisolated(unsafe) private static let cache = NSCache<NSString, LocalModelRuntimeSupportProbeCacheEntry>()
    private static let cacheTTLSeconds: TimeInterval = 8.0
    // Keep this aligned with TransformersProvider._helper_bridge_executable_task_kinds().
    private static let transformersHelperBridgeTaskKinds: Set<String> = [
        "text_generate",
        "embedding",
        "vision_understand",
        "ocr",
    ]
    private static let transformersSystemFallbackTaskKinds: Set<String> = [
        "text_to_speech",
    ]
    private static let ttsSystemFallbackEnableEnvKey = "XHUB_TRANSFORMERS_ALLOW_TTS_SYSTEM_FALLBACK"
    private static let ttsSystemFallbackBinaryEnvKey = "XHUB_TRANSFORMERS_TTS_SAY_BINARY"
    private static let probeScript = #"""
import importlib.util
import json
import os
import sys

VISION_TASKS = {"vision_understand", "ocr"}

model_path = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
task_kinds = [token.strip().lower() for token in (sys.argv[2] if len(sys.argv) > 2 else "").split(",") if token.strip()]

def emit(code, summary, detail="", blocking=True):
    print("code=" + str(code or "").strip())
    print("summary=" + str(summary or "").strip())
    if detail:
        print("detail=" + str(detail or "").strip())
    print("blocking=" + ("1" if blocking else "0"))
    sys.exit(0)

if not model_path:
    emit("missing_model_path", "\#(HubUIStrings.Models.RuntimeError.missingModelPath)", blocking=True)

if importlib.util.find_spec("transformers") is None:
    emit(
        "missing_module:transformers",
        "\#(HubUIStrings.Models.RuntimeError.missingTransformers)",
        "\#(HubUIStrings.Models.RuntimeError.detailMissingTransformers)",
        True,
    )

needs_torch = bool(task_kinds)
if needs_torch and importlib.util.find_spec("torch") is None:
    emit(
        "missing_module:torch",
        "\#(HubUIStrings.Models.RuntimeError.missingTorch)",
        "\#(HubUIStrings.Models.RuntimeError.detailMissingTorch)",
        True,
    )

if any(task in VISION_TASKS for task in task_kinds) and importlib.util.find_spec("PIL") is None:
    emit(
        "missing_module:pillow",
        "\#(HubUIStrings.Models.RuntimeError.missingPillow)",
        "\#(HubUIStrings.Models.RuntimeError.detailMissingPillow)",
        True,
    )

config_path = os.path.join(model_path, "config.json")
if not os.path.exists(config_path):
    emit(
        "missing_config",
        "\#(HubUIStrings.Models.RuntimeError.missingConfig)",
        "",
        True,
    )

with open(config_path, "r", encoding="utf-8") as handle:
    config = json.load(handle)

try:
    import transformers
    from transformers.models.auto.configuration_auto import CONFIG_MAPPING
except Exception as exc:
    emit(
        "transformers_import_failed",
        "\#(HubUIStrings.Models.RuntimeError.transformersImportFailed)",
        f"{type(exc).__name__}: {exc}",
        True,
    )

transformers_version = str(getattr(transformers, "__version__", "") or "").strip()
model_type_rows = [
    ("config.model_type", str(config.get("model_type") or "").strip()),
]

text_config = config.get("text_config") if isinstance(config.get("text_config"), dict) else {}
vision_config = config.get("vision_config") if isinstance(config.get("vision_config"), dict) else {}
for label, obj in (("text_config.model_type", text_config), ("vision_config.model_type", vision_config)):
    if isinstance(obj, dict):
        value = str(obj.get("model_type") or "").strip()
        if value:
            model_type_rows.append((label, value))

seen_model_types = set()
for label, model_type in model_type_rows:
    if not model_type or model_type in seen_model_types:
        continue
    seen_model_types.add(model_type)
    try:
        CONFIG_MAPPING[model_type]
    except Exception:
        detail = f"\#(HubUIStrings.Models.RuntimeError.detectedInPrefix){label}。"
        if transformers_version:
            detail += f"\#(HubUIStrings.Models.RuntimeError.currentTransformersPrefix){transformers_version}。"
        emit(
            f"unsupported_model_type:{model_type}",
            f"\#(HubUIStrings.Models.RuntimeError.unsupportedModelType("{model_type}"))",
            detail,
            True,
        )

processor_files = [
    "processor_config.json",
    "preprocessor_config.json",
    "feature_extractor_config.json",
    "video_preprocessor_config.json",
]
needs_processor_probe = any(task in {"vision_understand", "ocr", "speech_to_text"} for task in task_kinds) or any(
    os.path.exists(os.path.join(model_path, name)) for name in processor_files
)

if needs_processor_probe:
    try:
        from transformers import AutoProcessor
        AutoProcessor.from_pretrained(
            model_path,
            local_files_only=True,
            trust_remote_code=False,
        )
    except Exception as exc:
        emit(
            f"processor_init_failed:{type(exc).__name__}",
            "\#(HubUIStrings.Models.RuntimeError.processorInitFailed)",
            str(exc)[:220],
            True,
        )

emit("ok", "ok", "", False)
"""#

    static func issue(
        modelPath: String,
        backend: String,
        taskKinds: [String],
        catalogSnapshot: ModelCatalogSnapshot? = nil,
        providerPackSnapshot: LocalProviderPackRegistrySnapshot? = nil,
        helperBinaryPath: String? = nil,
        launchConfig: LocalRuntimePythonProbeLaunchConfig? = nil,
        pythonPath: String?
    ) -> LocalModelRuntimeCompatibilityIssue? {
        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBackend = backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard supportsProbe(for: normalizedBackend), !trimmedPath.isEmpty else {
            return nil
        }
        let normalizedTaskKinds = taskKinds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let nonPythonCoverage = nonPythonExecutionCoverage(
            for: normalizedBackend,
            taskKinds: normalizedTaskKinds,
            catalogSnapshot: catalogSnapshot,
            providerPackSnapshot: providerPackSnapshot,
            helperBinaryPath: helperBinaryPath
        )
        if let nonPythonCoverage,
           nonPythonCoverage.coversAllRequestedTaskKinds {
            if !nonPythonCoverage.helperBackedTaskKinds.isEmpty {
                return helperBridgeIssue(
                    providerID: normalizedBackend,
                    helperBinaryPath: nonPythonCoverage.helperBinaryPath
                )
            }
            return nil
        }
        let cacheKey = [
            trimmedPath,
            normalizedBackend,
            "python_probe",
            launchConfig?.resolvedPythonPath ?? "",
            launchConfig?.environment["PYTHONPATH"] ?? "",
            normalizedTaskKinds.joined(separator: ","),
            nonPythonExecutionCacheSignature(),
        ].joined(separator: "|") as NSString
        let now = Date().timeIntervalSince1970
        if let cached = cache.object(forKey: cacheKey),
           now - cached.cachedAt <= cacheTTLSeconds {
            return cached.issue
        }
        let resolvedLaunch = launchConfig ?? fallbackLaunchConfig(pythonPath: pythonPath)
        guard let resolvedLaunch else { return nil }
        let resolvedCacheKey = [
            trimmedPath,
            normalizedBackend,
            "python_probe",
            resolvedLaunch.resolvedPythonPath,
            resolvedLaunch.environment["PYTHONPATH"] ?? "",
            normalizedTaskKinds.joined(separator: ","),
            nonPythonExecutionCacheSignature(),
        ].joined(separator: "|") as NSString
        if cacheKey != resolvedCacheKey,
           let cached = cache.object(forKey: resolvedCacheKey),
           now - cached.cachedAt <= cacheTTLSeconds {
            return cached.issue
        }
        let issue = uncachedIssue(
            modelPath: trimmedPath,
            taskKinds: normalizedTaskKinds,
            launchConfig: resolvedLaunch
        )
        let entry = LocalModelRuntimeSupportProbeCacheEntry(issue: issue, cachedAt: now)
        cache.setObject(entry, forKey: resolvedCacheKey)
        if cacheKey != resolvedCacheKey {
            cache.setObject(entry, forKey: cacheKey)
        }
        return issue
    }

    static func nonPythonExecutionCacheSignature(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        [
            environment[ttsSystemFallbackEnableEnvKey] ?? "",
            environment[ttsSystemFallbackBinaryEnvKey] ?? "",
        ].joined(separator: "^")
    }

    static func nonPythonExecutionCoverage(
        for providerID: String,
        taskKinds: [String],
        catalogSnapshot: ModelCatalogSnapshot?,
        providerPackSnapshot: LocalProviderPackRegistrySnapshot?,
        helperBinaryPath: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> LocalModelNonPythonExecutionCoverage? {
        let normalizedProviderID = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedProviderID.isEmpty else {
            return nil
        }
        let requestedTaskKinds = Set(
            taskKinds
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        let normalizedHelperBinaryPath = normalizedPath(helperBinaryPath ?? "")
        let effectivePack = LocalProviderPackRegistry.effectivePack(
            providerID: normalizedProviderID,
            existing: providerPackSnapshot,
            catalog: catalogSnapshot ?? ModelCatalogStorage.load(),
            helperBinaryPath: normalizedHelperBinaryPath
        )
        let executionMode = effectivePack?.runtimeRequirements.executionMode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        switch normalizedProviderID {
        case "mlx_vlm", "llama.cpp":
            if !executionMode.isEmpty, executionMode != "helper_binary_bridge" {
                return nil
            }
            return LocalModelNonPythonExecutionCoverage(
                coversAllRequestedTaskKinds: true,
                helperBackedTaskKinds: requestedTaskKinds.isEmpty ? ["__all__"] : requestedTaskKinds,
                helperBinaryPath: resolvedHelperBinaryPath(
                    configuredPath: effectivePack?.runtimeRequirements.helperBinary ?? "",
                    fallbackPath: normalizedHelperBinaryPath
                )
            )
        case "transformers":
            guard !requestedTaskKinds.isEmpty else {
                return nil
            }
            var helperBackedTaskKinds: Set<String> = []
            var resolvedHelperBinary = ""
            if executionMode == "helper_binary_bridge" {
                helperBackedTaskKinds = requestedTaskKinds.intersection(transformersHelperBridgeTaskKinds)
                if !helperBackedTaskKinds.isEmpty {
                    resolvedHelperBinary = resolvedHelperBinaryPath(
                        configuredPath: effectivePack?.runtimeRequirements.helperBinary ?? "",
                        fallbackPath: normalizedHelperBinaryPath
                    )
                }
            }
            var coveredTaskKinds = helperBackedTaskKinds
            if ttsSystemFallbackAvailable(environment: environment, fileManager: fileManager) {
                coveredTaskKinds.formUnion(
                    requestedTaskKinds.intersection(transformersSystemFallbackTaskKinds)
                )
            }
            guard !coveredTaskKinds.isEmpty else {
                return nil
            }
            return LocalModelNonPythonExecutionCoverage(
                coversAllRequestedTaskKinds: coveredTaskKinds == requestedTaskKinds,
                helperBackedTaskKinds: helperBackedTaskKinds,
                helperBinaryPath: resolvedHelperBinary
            )
        default:
            return nil
        }
    }

    private static func ttsSystemFallbackAvailable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> Bool {
        guard ttsSystemFallbackAllowed(environment: environment) else {
            return false
        }
        return !ttsSystemFallbackBinaryPath(environment: environment, fileManager: fileManager).isEmpty
    }

    private static func ttsSystemFallbackAllowed(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let token = (environment[ttsSystemFallbackEnableEnvKey] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !token.isEmpty else {
            return true
        }
        return ["1", "true", "yes", "on"].contains(token)
    }

    private static func ttsSystemFallbackBinaryPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String {
        let requestedBinary = (environment[ttsSystemFallbackBinaryEnvKey] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !requestedBinary.isEmpty {
            return resolvedExecutablePath(
                requestedBinary,
                environment: environment,
                fileManager: fileManager
            )
        }
        let systemBinary = "/usr/bin/say"
        if fileManager.isExecutableFile(atPath: systemBinary) {
            return systemBinary
        }
        return resolvedExecutablePath(
            "say",
            environment: environment,
            fileManager: fileManager
        )
    }

    private static func resolvedExecutablePath(
        _ candidate: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String {
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCandidate.isEmpty else {
            return ""
        }
        if trimmedCandidate.contains("/") || trimmedCandidate.hasPrefix(".") {
            let normalizedCandidate = normalizedPath(trimmedCandidate)
            return fileManager.isExecutableFile(atPath: normalizedCandidate) ? normalizedCandidate : ""
        }
        let pathValue = (environment["PATH"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pathValue.isEmpty else {
            return ""
        }
        for directory in pathValue
            .split(separator: ":")
            .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
            where !directory.isEmpty {
            let executablePath = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(trimmedCandidate)
                .path
            let normalizedExecutablePath = normalizedPath(executablePath)
            if fileManager.isExecutableFile(atPath: normalizedExecutablePath) {
                return normalizedExecutablePath
            }
        }
        return ""
    }

    private static func uncachedIssue(
        modelPath: String,
        taskKinds: [String],
        launchConfig: LocalRuntimePythonProbeLaunchConfig
    ) -> LocalModelRuntimeCompatibilityIssue? {
        let result = runCapture(
            launchConfig.executable,
            launchConfig.argumentsPrefix + ["-c", probeScript, modelPath, taskKinds.joined(separator: ",")],
            env: launchConfig.environment,
            timeoutSec: 6.0
        )
        let output = [result.out, result.err]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !output.isEmpty else { return nil }

        let fields = parseFields(output)
        let code = (fields["code"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code != "ok" else { return nil }

        let summary = (fields["summary"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = (fields["detail"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let blocking = (fields["blocking"] ?? "1").trimmingCharacters(in: .whitespacesAndNewlines) != "0"
        guard blocking else { return nil }
        let humanizedSummary = LocalModelRuntimeErrorPresentation.humanized(code, detail: detail)
        let normalizedSummary = !humanizedSummary.isEmpty ? humanizedSummary : summary
        let normalizedDetail = LocalModelRuntimeErrorPresentation.detailHint(for: code, detail: detail)

        return LocalModelRuntimeCompatibilityIssue(
            code: code,
            summary: normalizedSummary,
            detail: normalizedDetail
        )
    }

    private static func fallbackLaunchConfig(pythonPath: String?) -> LocalRuntimePythonProbeLaunchConfig? {
        let pythonPath = pythonPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pythonPath.isEmpty else { return nil }
        let launch = pythonLaunch(pythonPath)
        guard !launch.executable.isEmpty else { return nil }
        return LocalRuntimePythonProbeLaunchConfig(
            executable: launch.executable,
            argumentsPrefix: launch.argumentsPrefix,
            environment: probeEnv(),
            resolvedPythonPath: launch.resolvedPythonPath
        )
    }

    private static func pythonLaunch(_ pythonPath: String) -> (executable: String, argumentsPrefix: [String], resolvedPythonPath: String) {
        let trimmed = pythonPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", [], "") }
        if trimmed.contains("/") {
            let normalized = (trimmed as NSString).expandingTildeInPath
            guard FileManager.default.isExecutableFile(atPath: normalized) else {
                return ("", [], "")
            }
            return (normalized, [], normalized)
        }
        return ("/usr/bin/env", [trimmed], trimmed)
    }

    private static func parseFields(_ output: String) -> [String: String] {
        var out: [String: String] = [:]
        for rawLine in output.split(whereSeparator: \.isNewline).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            out[key] = value
        }
        return out
    }

    private static func probeEnv() -> [String: String] {
        [
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_DATASETS_OFFLINE": "1",
            "TOKENIZERS_PARALLELISM": "false",
        ]
    }

    private static func supportsProbe(for providerID: String) -> Bool {
        switch providerID {
        case "transformers", "mlx_vlm", "llama.cpp":
            return true
        default:
            return false
        }
    }

    private static func resolvedHelperBinaryPath(
        configuredPath: String,
        fallbackPath: String
    ) -> String {
        let normalizedConfigured = normalizedPath(configuredPath)
        if !normalizedConfigured.isEmpty {
            return normalizedConfigured
        }
        if !fallbackPath.isEmpty {
            return fallbackPath
        }
        return normalizedPath(LocalHelperBridgeDiscovery.discoverHelperBinary())
    }

    private static func normalizedPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    private static func helperBridgeIssue(
        providerID: String,
        helperBinaryPath: String
    ) -> LocalModelRuntimeCompatibilityIssue? {
        let helperPath = normalizedPath(helperBinaryPath)
        guard !helperPath.isEmpty,
              FileManager.default.isExecutableFile(atPath: helperPath) else {
            let providerName = providerDisplayName(for: providerID)
            return LocalModelRuntimeCompatibilityIssue(
                code: "helper_binary_missing",
                summary: "\(providerName) 已配置为使用本地辅助运行时，但 helper 二进制文件缺失。",
                detail: ""
            )
        }
        return nil
    }

    private static func providerDisplayName(for providerID: String) -> String {
        switch providerID {
        case "mlx_vlm":
            return "MLX VLM"
        case "llama.cpp":
            return "llama.cpp"
        default:
            return providerID.isEmpty ? "Provider" : providerID
        }
    }

    private static func runCapture(
        _ executable: String,
        _ arguments: [String],
        env: [String: String],
        timeoutSec: Double
    ) -> (code: Int32, out: String, err: String) {
        ProcessCaptureSupport.runCapture(
            executable,
            arguments,
            env: env,
            timeoutSec: timeoutSec
        )
    }
}
