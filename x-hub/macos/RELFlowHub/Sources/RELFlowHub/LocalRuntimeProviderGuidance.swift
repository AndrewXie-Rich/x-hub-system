import Foundation

struct LocalPythonRuntimeCandidateStatus: Equatable {
    var path: String
    var version: String
    var readyProviders: [String]
    var score: Int
    var environmentPythonPathEntries: [String] = []

    var normalizedPath: String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    var readySummary: String {
        let normalized = readyProviders
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? "none" : normalized.joined(separator: ",")
    }

    func supports(providerID: String) -> Bool {
        let normalizedProvider = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedProvider.isEmpty else { return false }
        return readyProviders.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedProvider }
    }
}

enum LocalRuntimeProviderGuidance {
    static func pythonCandidatesSummary(
        selectedPythonPath: String,
        preferredProviderPaths: [String: String] = [:],
        candidates: [LocalPythonRuntimeCandidateStatus],
        limit: Int = 6
    ) -> String {
        var lines: [String] = []
        let normalizedSelected = normalizedPath(selectedPythonPath)
        lines.append(HubUIStrings.Models.Runtime.ProviderGuidance.selectedPython(normalizedSelected))

        for providerID in preferredProviderPaths.keys.sorted() {
            let path = normalizedPath(preferredProviderPaths[providerID] ?? "")
            guard !path.isEmpty else { continue }
            lines.append(HubUIStrings.Models.Runtime.ProviderGuidance.autoProviderPython(providerID: providerID, path: path))
        }

        lines.append(HubUIStrings.Models.Runtime.ProviderGuidance.candidatesHeader)
        if candidates.isEmpty {
            lines.append(HubUIStrings.Models.Runtime.ProviderGuidance.candidateEmpty)
            return lines.joined(separator: "\n")
        }

        for candidate in candidates.prefix(max(1, limit)) {
            let version = candidate.version.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(HubUIStrings.Models.Runtime.ProviderGuidance.candidateLine(
                path: candidate.normalizedPath,
                version: version.isEmpty ? HubUIStrings.Models.Runtime.ProviderGuidance.unknown : version,
                ready: candidate.readySummary,
                score: candidate.score
            ))
        }
        return lines.joined(separator: "\n")
    }

    static func providerHint(
        providerID: String,
        reasonCode: String,
        importError: String,
        runtimeResolutionState: String = "",
        runtimeSource: String = "",
        runtimeSourcePath: String = "",
        runtimeReasonCode: String = "",
        runtimeHint: String = "",
        fallbackUsed: Bool = false,
        selectedPythonPath: String,
        preferredPythonPath: String?,
        candidates: [LocalPythonRuntimeCandidateStatus]
    ) -> String {
        let normalizedProvider = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalizedProvider {
        case "transformers", "mlx_vlm", "llama.cpp":
            return transformersHint(
                providerID: normalizedProvider,
                providerDisplayName: providerDisplayName(for: normalizedProvider),
                reasonCode: reasonCode,
                importError: importError,
                runtimeResolutionState: runtimeResolutionState,
                runtimeSource: runtimeSource,
                runtimeSourcePath: runtimeSourcePath,
                runtimeReasonCode: runtimeReasonCode,
                runtimeHint: runtimeHint,
                fallbackUsed: fallbackUsed,
                selectedPythonPath: selectedPythonPath,
                preferredPythonPath: preferredPythonPath,
                candidates: candidates
            )
        case "mlx":
            return mlxHint(importError: importError, selectedPythonPath: selectedPythonPath)
        default:
            return genericHint(
                providerID: normalizedProvider,
                reasonCode: reasonCode,
                importError: importError
            )
        }
    }

    private static func transformersHint(
        providerID: String,
        providerDisplayName: String,
        reasonCode: String,
        importError: String,
        runtimeResolutionState: String,
        runtimeSource: String,
        runtimeSourcePath: String,
        runtimeReasonCode: String,
        runtimeHint: String,
        fallbackUsed: Bool,
        selectedPythonPath: String,
        preferredPythonPath: String?,
        candidates: [LocalPythonRuntimeCandidateStatus]
    ) -> String {
        let normalizedReason = reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedImportError = importError.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRuntimeState = runtimeResolutionState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedRuntimeSource = runtimeSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedRuntimeSourcePath = normalizedPath(runtimeSourcePath)
        let normalizedRuntimeReason = runtimeReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRuntimeHint = runtimeHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelected = normalizedPath(selectedPythonPath)
        let normalizedPreferred = normalizedPath(preferredPythonPath ?? "")
        let providerCandidateLabel = providerProbeLabel(for: providerID)
        let bestSupporting = candidates.first(where: { $0.supports(providerID: providerID) })

        var parts: [String] = []
        if normalizedRuntimeSource == "xhub_local_service" {
            switch normalizedRuntimeReason {
            case "xhub_local_service_config_missing":
                parts.append(providerManagedServiceConfigMissing(providerDisplayName))
            case "xhub_local_service_starting":
                parts.append(providerManagedServiceStarting(providerDisplayName))
            case "xhub_local_service_not_ready":
                parts.append(providerManagedServiceNotReady(providerDisplayName))
            case "xhub_local_service_unreachable":
                parts.append(providerManagedServiceUnreachable(providerDisplayName))
            default:
                parts.append(providerManagedServiceDefault(providerDisplayName))
            }
            if !normalizedRuntimeHint.isEmpty {
                parts.append(normalizedRuntimeHint)
            }
            if !normalizedRuntimeSourcePath.isEmpty {
                parts.append(HubUIStrings.Models.Runtime.ProviderGuidance.localServiceEndpoint(normalizedRuntimeSourcePath))
            }
            return parts.joined(separator: " ")
        }
        if normalizedRuntimeSource == "helper_binary_bridge" {
            switch normalizedRuntimeReason {
            case "helper_binary_missing":
                parts.append(providerHelperMissing(providerDisplayName))
            case "helper_local_service_disabled":
                parts.append(providerHelperLocalServiceDisabled(providerDisplayName))
            case "helper_service_down",
                "helper_probe_failed",
                "helper_probe_timeout",
                "helper_server_down",
                "helper_server_unreachable",
                "helper_server_start_failed":
                parts.append(providerHelperUnavailable(providerDisplayName))
            default:
                parts.append(providerHelperDefault(providerDisplayName))
            }
            if !normalizedRuntimeHint.isEmpty {
                parts.append(normalizedRuntimeHint)
            }
            if !normalizedRuntimeSourcePath.isEmpty {
                parts.append(HubUIStrings.Models.Runtime.ProviderGuidance.helperPath(normalizedRuntimeSourcePath))
            }
            return parts.joined(separator: " ")
        }

        switch normalizedImportError {
        case "missing_module:torch":
            parts.append(providerMissingTorch(providerDisplayName))
        case "missing_module:transformers":
            parts.append(providerMissingTransformers(providerDisplayName))
        case "missing_module:pillow":
            parts.append(providerMissingPillow(providerDisplayName))
        default:
            if !normalizedImportError.isEmpty {
                parts.append(
                    providerUnavailableLocalized(
                        providerDisplayName,
                        detail: LocalModelRuntimeErrorPresentation.humanized(normalizedImportError)
                    )
                )
            } else if normalizedReason == "no_registered_models" {
                parts.append(providerNoRegisteredModels(providerDisplayName))
            } else if normalizedReason == "no_supported_models" {
                parts.append(providerNoSupportedModels(providerDisplayName))
            } else if !normalizedReason.isEmpty {
                parts.append(providerUnavailableReason(providerDisplayName, reason: normalizedReason))
            } else {
                parts.append(providerUnavailable(providerDisplayName))
            }
        }

        if normalizedRuntimeState == "user_runtime_fallback" || fallbackUsed {
            let sourceLabel = HubUIStrings.Models.Runtime.ProviderGuidance.runtimeSourceLabel(normalizedRuntimeSource)
            if !normalizedRuntimeHint.isEmpty {
                parts.append(normalizedRuntimeHint)
            } else if !normalizedRuntimeSourcePath.isEmpty {
                parts.append(providerCurrentSource(providerDisplayName, sourceLabel: sourceLabel, path: normalizedRuntimeSourcePath))
            } else {
                parts.append(providerRunningOn(providerDisplayName, sourceLabel: sourceLabel))
            }
        } else if normalizedRuntimeState == "runtime_missing", !normalizedRuntimeHint.isEmpty {
            parts.append(normalizedRuntimeHint)
        }

        if normalizedRuntimeReason == "native_dependency_error" {
            parts.append(HubUIStrings.Models.Runtime.ProviderGuidance.nativeDependencyError)
        }

        if !normalizedSelected.isEmpty {
            parts.append(HubUIStrings.Models.Runtime.ProviderGuidance.currentRuntimePython(normalizedSelected))
        }

        if let bestSupporting {
            let version = bestSupporting.version.trimmingCharacters(in: .whitespacesAndNewlines)
            let bestText = HubUIStrings.Models.Runtime.ProviderGuidance.candidateDescriptor(
                path: bestSupporting.normalizedPath,
                version: version.isEmpty ? HubUIStrings.Models.Runtime.ProviderGuidance.unknownASCII : version,
                ready: bestSupporting.readySummary
            )
            if !normalizedPreferred.isEmpty, normalizedPreferred == bestSupporting.normalizedPath, normalizedPreferred != normalizedSelected {
                parts.append(betterLocalPython(providerName: providerCandidateLabel, candidate: bestText))
            } else if bestSupporting.normalizedPath != normalizedSelected {
                parts.append(discoveredSupportingPython(providerName: providerCandidateLabel, candidate: bestText))
            }
        } else if !candidates.isEmpty {
            let bestCandidate = candidates[0]
            let version = bestCandidate.version.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(scannedCandidates(candidates.count, providerName: providerCandidateLabel))
            parts.append(HubUIStrings.Models.Runtime.ProviderGuidance.bestCandidate(
                HubUIStrings.Models.Runtime.ProviderGuidance.candidateDescriptor(
                    path: bestCandidate.normalizedPath,
                    version: version.isEmpty ? HubUIStrings.Models.Runtime.ProviderGuidance.unknownASCII : version,
                    ready: bestCandidate.readySummary
                )
            ))
            parts.append(HubUIStrings.Models.Runtime.ProviderGuidance.autoDiscoverLocalVenv)
        } else {
            parts.append(noProviderCandidates(providerName: providerCandidateLabel))
        }

        return parts.joined(separator: " ")
    }

    private static func providerDisplayName(for providerID: String) -> String {
        switch providerID {
        case "mlx_vlm":
            return "MLX VLM"
        case "transformers":
            return "Transformers"
        case "llama.cpp":
            return "llama.cpp"
        default:
            return providerID.isEmpty ? "Provider" : providerID
        }
    }

    private static func providerProbeLabel(for providerID: String) -> String {
        switch providerID {
        case "transformers":
            return "transformers"
        case "mlx_vlm":
            return "MLX VLM"
        default:
            return providerDisplayName(for: providerID)
        }
    }

    private static func providerManagedServiceConfigMissing(_ providerName: String) -> String {
        "\(providerName) 已配置为使用 Hub 托管的本地运行时服务，但当前还没有配置 service endpoint。"
    }

    private static func providerManagedServiceStarting(_ providerName: String) -> String {
        "\(providerName) 已配置为使用 Hub 托管的本地运行时服务，但服务仍在启动中。"
    }

    private static func providerManagedServiceNotReady(_ providerName: String) -> String {
        "\(providerName) 已配置为使用 Hub 托管的本地运行时服务，但服务虽然有响应，还没进入 ready 状态。"
    }

    private static func providerManagedServiceUnreachable(_ providerName: String) -> String {
        "\(providerName) 已配置为使用 Hub 托管的本地运行时服务，但当前无法访问这个服务。"
    }

    private static func providerManagedServiceDefault(_ providerName: String) -> String {
        "\(providerName) 已配置为使用 Hub 托管的本地运行时服务。"
    }

    private static func providerHelperMissing(_ providerName: String) -> String {
        "\(providerName) 已配置为使用本地辅助运行时，但 helper 二进制文件缺失。"
    }

    private static func providerHelperLocalServiceDisabled(_ providerName: String) -> String {
        "\(providerName) 已配置为使用本地辅助运行时，但 LM Studio Local Service 当前是关闭的。"
    }

    private static func providerHelperUnavailable(_ providerName: String) -> String {
        "\(providerName) 已配置为使用本地辅助运行时，但辅助服务当前不可用。"
    }

    private static func providerHelperDefault(_ providerName: String) -> String {
        "\(providerName) 已配置为使用本地辅助运行时。"
    }

    private static func providerMissingTorch(_ providerName: String) -> String {
        "\(providerName) 当前不可用，因为当前 Python 运行时缺少 torch。"
    }

    private static func providerMissingTransformers(_ providerName: String) -> String {
        "\(providerName) 当前不可用，因为当前 Python 运行时缺少 transformers。"
    }

    private static func providerMissingPillow(_ providerName: String) -> String {
        "\(providerName) 的视觉或音频预处理当前不可用，因为当前 Python 运行时缺少 Pillow。"
    }

    private static func providerNoRegisteredModels(_ providerName: String) -> String {
        "\(providerName) 已运行，但目前还没有登记任何本地模型。"
    }

    private static func providerNoSupportedModels(_ providerName: String) -> String {
        "\(providerName) 已运行，但当前已登记的本地模型还没有暴露受支持的任务。"
    }

    private static func providerUnavailable(_ providerName: String) -> String {
        "\(providerName) 当前不可用。"
    }

    private static func providerUnavailableLocalized(_ providerName: String, detail: String) -> String {
        "\(providerName) 当前不可用：\(detail)。"
    }

    private static func providerUnavailableReason(_ providerName: String, reason: String) -> String {
        "\(providerName) 当前不可用（\(reason)）。"
    }

    private static func providerCurrentSource(_ providerName: String, sourceLabel: String, path: String) -> String {
        "当前 \(providerName) 运行时来源：\(sourceLabel)（\(path)）。"
    }

    private static func providerRunningOn(_ providerName: String, sourceLabel: String) -> String {
        "\(providerName) 当前运行在 \(sourceLabel)，而不是 Hub 托管的运行时包。"
    }

    private static func betterLocalPython(providerName: String, candidate: String) -> String {
        "Hub 找到了一个对 \(providerName) 更合适的本地 Python：\(candidate)。下次请求 \(providerName) 预热或加载时，Hub 会自动切换；你也可以现在直接重启 AI Runtime。"
    }

    private static func discoveredSupportingPython(providerName: String, candidate: String) -> String {
        "发现可支持 \(providerName) 的本地 Python：\(candidate)。"
    }

    private static func scannedCandidates(_ count: Int, providerName: String) -> String {
        "Hub 已扫描 \(count) 个本地 Python 候选，但目前都不支持 \(providerName)。"
    }

    private static func noProviderCandidates(providerName: String) -> String {
        "Hub 没有找到可用于探测 \(providerName) 的本地 Python 候选。"
    }

    private static func mlxHint(importError: String, selectedPythonPath: String) -> String {
        let normalizedImportError = importError.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelected = normalizedPath(selectedPythonPath)
        var parts: [String] = [HubUIStrings.Models.Runtime.ProviderGuidance.mlxUnavailable]
        if !normalizedImportError.isEmpty {
            parts.append(HubUIStrings.Models.Runtime.ProviderGuidance.reason(
                LocalModelRuntimeErrorPresentation.humanized(normalizedImportError)
            ))
        }
        if !normalizedSelected.isEmpty {
            parts.append(HubUIStrings.Models.Runtime.ProviderGuidance.currentRuntimePython(normalizedSelected))
        }
        parts.append(HubUIStrings.Models.Runtime.ProviderGuidance.mlxRequirements)
        return parts.joined(separator: " ")
    }

    private static func genericHint(
        providerID: String,
        reasonCode: String,
        importError: String
    ) -> String {
        let normalizedProvider = providerID.isEmpty ? "provider" : providerID
        let normalizedImportError = importError.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReason = reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedImportError.isEmpty {
            return HubUIStrings.Models.Runtime.ProviderGuidance.genericUnavailable(
                providerID: normalizedProvider,
                detail: LocalModelRuntimeErrorPresentation.humanized(normalizedImportError)
            )
        }
        if !normalizedReason.isEmpty {
            return HubUIStrings.Models.Runtime.ProviderGuidance.genericUnavailableReason(
                providerID: normalizedProvider,
                reason: normalizedReason
            )
        }
        return HubUIStrings.Models.Runtime.ProviderGuidance.genericUnavailableBare(providerID: normalizedProvider)
    }

    private static func normalizedPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("://") {
            return trimmed
        }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL.path
    }
}
