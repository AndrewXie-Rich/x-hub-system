import Foundation
import CryptoKit
import RELFlowHubCore

struct LocalModelRuntimeRequestContext: Codable, Equatable, Sendable {
    var providerID: String
    var modelID: String
    var deviceID: String
    var instanceKey: String
    var loadProfileHash: String
    var predictedLoadProfileHash: String
    var effectiveContextLength: Int
    var loadProfileOverride: LocalModelLoadProfileOverride?
    var effectiveLoadProfile: LocalModelLoadProfile? = nil
    var source: String

    var preferredBenchHash: String {
        let resolved = loadProfileHash.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolved.isEmpty {
            return resolved
        }
        return predictedLoadProfileHash.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var shortSourceLabel: String {
        HubUIStrings.Models.Runtime.RequestContext.sourceLabel(source)
    }

    var uiSummary: String {
        var parts: [String] = [HubUIStrings.Models.Runtime.RequestContext.target(displayIdentityLabel)]
        parts.append(contentsOf: uiLoadProfileSummaryParts)
        if !instanceKey.isEmpty {
            parts.append(HubUIStrings.Models.Runtime.RequestContext.resident)
        }
        return HubUIStrings.Formatting.middleDotSeparated(parts)
    }

    var technicalSummary: String {
        var parts: [String] = [shortSourceLabel]
        if !deviceID.isEmpty {
            parts.append("device=\(deviceID)")
        }
        parts.append(contentsOf: technicalLoadProfileSummaryParts)
        if !loadProfileHash.isEmpty {
            parts.append("hash=\(shortHash(loadProfileHash))")
        } else if !predictedLoadProfileHash.isEmpty {
            parts.append("predicted=\(shortHash(predictedLoadProfileHash))")
        }
        if !instanceKey.isEmpty {
            parts.append("instance=\(shortInstanceLabel(instanceKey))")
        }
        return HubUIStrings.Formatting.middleDotSeparated(parts)
    }

    var uiLoadProfileSummary: String {
        HubUIStrings.Formatting.middleDotSeparated(uiLoadProfileSummaryParts)
    }

    var technicalLoadProfileSummary: String {
        HubUIStrings.Formatting.middleDotSeparated(technicalLoadProfileSummaryParts)
    }

    func applying(to request: [String: Any]) -> [String: Any] {
        var out = request
        if !deviceID.isEmpty {
            out["device_id"] = deviceID
        }
        if !instanceKey.isEmpty {
            out["instance_key"] = instanceKey
        }
        if !loadProfileHash.isEmpty {
            out["load_profile_hash"] = loadProfileHash
            out["load_config_hash"] = loadProfileHash
        }
        if effectiveContextLength > 0 {
            out["effective_context_length"] = effectiveContextLength
            out["current_context_length"] = effectiveContextLength
        }
        if let loadProfileOverride, !loadProfileOverride.isEmpty {
            out["load_profile_override"] = loadProfileOverride.requestPayload
        }
        return out
    }

    func matchesBenchResult(_ result: ModelBenchResult) -> Bool {
        let wantedHash = preferredBenchHash
        let rowHash = result.loadProfileHash.trimmingCharacters(in: .whitespacesAndNewlines)
        if !wantedHash.isEmpty, !rowHash.isEmpty {
            return wantedHash == rowHash
        }
        if effectiveContextLength > 0,
           let rowContext = result.effectiveContextLength,
           rowContext > 0 {
            return effectiveContextLength == rowContext
        }
        return true
    }

    private var displayIdentityLabel: String {
        let device = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !device.isEmpty {
            return device
        }
        return shortSourceLabel.lowercased()
    }

    private func shortHash(_ value: String) -> String {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "" }
        return String(token.prefix(8))
    }

    private func shortInstanceLabel(_ value: String) -> String {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "" }
        if let last = token.split(separator: ":").last, !last.isEmpty {
            return String(String(last).prefix(8))
        }
        return shortHash(token)
    }

    private var displayLoadProfile: LocalModelLoadProfile? {
        if let effectiveLoadProfile {
            return effectiveLoadProfile
        }
        if let loadProfileOverride, !loadProfileOverride.isEmpty {
            let baseContextLength = max(512, effectiveContextLength > 0 ? effectiveContextLength : 8192)
            return loadProfileOverride.applied(to: LocalModelLoadProfile(contextLength: baseContextLength))
        }
        if effectiveContextLength > 0 {
            return LocalModelLoadProfile(contextLength: effectiveContextLength)
        }
        return nil
    }

    private var uiLoadProfileSummaryParts: [String] {
        loadProfileSummaryParts(technical: false, includeIdentifier: false)
    }

    private var technicalLoadProfileSummaryParts: [String] {
        loadProfileSummaryParts(technical: true, includeIdentifier: true)
    }

    private func loadProfileSummaryParts(
        technical: Bool,
        includeIdentifier: Bool
    ) -> [String] {
        let profile = displayLoadProfile
        let contextValue = max(
            0,
            effectiveContextLength > 0
                ? effectiveContextLength
                : (profile?.contextLength ?? 0)
        )
        var parts: [String] = []
        if contextValue > 0 {
            parts.append(technical ? "ctx=\(contextValue)" : "ctx \(contextValue)")
        }
        if let ttl = profile?.ttl {
            parts.append(technical ? "ttl=\(ttl)s" : "ttl \(ttl)s")
        }
        if let parallel = profile?.parallel {
            parts.append(technical ? "par=\(parallel)" : "par \(parallel)")
        }
        if includeIdentifier,
           let identifier = profile?.identifier,
           !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(technical ? "id=\(identifier)" : "id \(identifier)")
        }
        if let imageMaxDimension = profile?.vision?.imageMaxDimension {
            parts.append(technical ? "img=\(imageMaxDimension)" : "img \(imageMaxDimension)")
        }
        return parts
    }
}

enum LocalModelRuntimeRequestContextResolver {
    static let defaultPairedDeviceID = "terminal_device"

    static func resolve(
        model: HubModel,
        runtimeStatus: AIRuntimeStatus?,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot = HubPairedTerminalLocalModelProfilesStorage.load(),
        targetPreference: LocalModelRuntimeTargetPreference? = nil
    ) -> LocalModelRuntimeRequestContext {
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        let normalizedDefaultProfile = model.defaultLoadProfile.normalized(maxContextLength: model.maxContextLength)
        let pairedProfiles = pairedProfilesSnapshot.profiles.filter {
            $0.modelId == model.id && !$0.deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let preferredPairedProfile = preferredPairedProfile(from: pairedProfiles)
        let loadedInstances = loadedInstances(
            providerID: providerID,
            modelID: model.id,
            runtimeStatus: runtimeStatus
        )

        if let explicit = resolveExplicitPreference(
            targetPreference,
            model: model,
            providerID: providerID,
            normalizedDefaultProfile: normalizedDefaultProfile,
            maxContextLength: model.maxContextLength,
            pairedProfiles: pairedProfiles,
            loadedInstances: loadedInstances
        ) {
            return explicit
        }

        if let preferredPairedProfile {
            return requestContextForPairedProfile(
                providerID: providerID,
                modelID: model.id,
                normalizedDefaultProfile: normalizedDefaultProfile,
                maxContextLength: model.maxContextLength,
                pairedProfile: preferredPairedProfile,
                loadedInstances: loadedInstances,
                matchedLoadedSource: "loaded_instance_preferred_profile",
                unresolvedSource: preferredPairedProfile.deviceId == defaultPairedDeviceID
                    ? "paired_terminal_default"
                    : "paired_terminal_single"
            )
        }

        if loadedInstances.count == 1, let loaded = loadedInstances.first {
            return requestContextForLoadedInstance(
                providerID: providerID,
                modelID: model.id,
                loaded: loaded,
                source: "single_loaded_instance"
            )
        }

        if let loaded = loadedInstances.first {
            return requestContextForLoadedInstance(
                providerID: providerID,
                modelID: model.id,
                loaded: loaded,
                source: "loaded_instance_latest"
            )
        }

        return requestContextForDefaultProfile(
            providerID: providerID,
            modelID: model.id,
            normalizedDefaultProfile: normalizedDefaultProfile
        )
    }

    private static func preferredPairedProfile(
        from profiles: [HubPairedTerminalLocalModelProfile]
    ) -> HubPairedTerminalLocalModelProfile? {
        if let terminalProfile = profiles.first(where: { $0.deviceId == defaultPairedDeviceID }) {
            return terminalProfile
        }
        if profiles.count == 1 {
            return profiles.first
        }
        return nil
    }

    private static func loadedInstances(
        providerID: String,
        modelID: String,
        runtimeStatus: AIRuntimeStatus?
    ) -> [AIRuntimeLoadedInstance] {
        let rows = runtimeStatus?.providerStatus(providerID)?.loadedInstances ?? []
        return rows
            .filter { $0.modelId == modelID }
            .sorted {
                if $0.lastUsedAt == $1.lastUsedAt {
                    if $0.loadedAt == $1.loadedAt {
                        return $0.instanceKey < $1.instanceKey
                    }
                    return $0.loadedAt > $1.loadedAt
                }
                return $0.lastUsedAt > $1.lastUsedAt
            }
    }

    private static func resolveExplicitPreference(
        _ preference: LocalModelRuntimeTargetPreference?,
        model: HubModel,
        providerID: String,
        normalizedDefaultProfile: LocalModelLoadProfile,
        maxContextLength: Int,
        pairedProfiles: [HubPairedTerminalLocalModelProfile],
        loadedInstances: [AIRuntimeLoadedInstance]
    ) -> LocalModelRuntimeRequestContext? {
        guard let preference, preference.modelId == model.id, preference.isValid, let kind = preference.kind else {
            return nil
        }

        switch kind {
        case .pairedDevice:
            guard let pairedProfile = pairedProfiles.first(where: { $0.deviceId == preference.deviceId }) else {
                return nil
            }
            return requestContextForPairedProfile(
                providerID: providerID,
                modelID: model.id,
                normalizedDefaultProfile: normalizedDefaultProfile,
                maxContextLength: maxContextLength,
                pairedProfile: pairedProfile,
                loadedInstances: loadedInstances,
                matchedLoadedSource: pairedProfile.deviceId == defaultPairedDeviceID
                    ? "selected_paired_terminal"
                    : "selected_paired_device",
                unresolvedSource: pairedProfile.deviceId == defaultPairedDeviceID
                    ? "selected_paired_terminal"
                    : "selected_paired_device"
            )
        case .loadedInstance:
            guard let loaded = loadedInstances.first(where: { $0.instanceKey == preference.instanceKey }) else {
                return nil
            }
            return requestContextForLoadedInstance(
                providerID: providerID,
                modelID: model.id,
                loaded: loaded,
                source: "selected_loaded_instance"
            )
        }
    }

    private static func requestContextForPairedProfile(
        providerID: String,
        modelID: String,
        normalizedDefaultProfile: LocalModelLoadProfile,
        maxContextLength: Int,
        pairedProfile: HubPairedTerminalLocalModelProfile,
        loadedInstances: [AIRuntimeLoadedInstance],
        matchedLoadedSource: String,
        unresolvedSource: String
    ) -> LocalModelRuntimeRequestContext {
        let effectiveProfile = normalizedDefaultProfile.merged(
            with: pairedProfile.overrideProfile,
            maxContextLength: maxContextLength
        )
        let preferredHash = canonicalLoadProfileHash(effectiveProfile)

        if let matchingLoaded = loadedInstances.first(where: {
            !$0.loadProfileHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.loadProfileHash == preferredHash
        }) {
            return LocalModelRuntimeRequestContext(
                providerID: providerID,
                modelID: modelID,
                deviceID: pairedProfile.deviceId,
                instanceKey: matchingLoaded.instanceKey,
                loadProfileHash: matchingLoaded.loadProfileHash,
                predictedLoadProfileHash: preferredHash,
                effectiveContextLength: max(
                    matchingLoaded.effectiveContextLength,
                    effectiveProfile.contextLength
                ),
                loadProfileOverride: pairedProfile.overrideProfile,
                effectiveLoadProfile: matchingLoaded.effectiveLoadProfile ?? effectiveProfile,
                source: matchedLoadedSource
            )
        }

        return LocalModelRuntimeRequestContext(
            providerID: providerID,
            modelID: modelID,
            deviceID: pairedProfile.deviceId,
            instanceKey: "",
            loadProfileHash: "",
            predictedLoadProfileHash: preferredHash,
            effectiveContextLength: effectiveProfile.contextLength,
            loadProfileOverride: pairedProfile.overrideProfile,
            effectiveLoadProfile: effectiveProfile,
            source: unresolvedSource
        )
    }

    private static func requestContextForLoadedInstance(
        providerID: String,
        modelID: String,
        loaded: AIRuntimeLoadedInstance,
        source: String
    ) -> LocalModelRuntimeRequestContext {
        LocalModelRuntimeRequestContext(
            providerID: providerID,
            modelID: modelID,
            deviceID: "",
            instanceKey: loaded.instanceKey,
            loadProfileHash: loaded.loadProfileHash,
            predictedLoadProfileHash: loaded.loadProfileHash,
            effectiveContextLength: max(0, loaded.effectiveContextLength),
            loadProfileOverride: nil,
            effectiveLoadProfile: loaded.effectiveLoadProfile
                ?? {
                    guard loaded.effectiveContextLength > 0 else { return nil }
                    return LocalModelLoadProfile(contextLength: loaded.effectiveContextLength)
                }(),
            source: source
        )
    }

    private static func requestContextForDefaultProfile(
        providerID: String,
        modelID: String,
        normalizedDefaultProfile: LocalModelLoadProfile
    ) -> LocalModelRuntimeRequestContext {
        LocalModelRuntimeRequestContext(
            providerID: providerID,
            modelID: modelID,
            deviceID: "",
            instanceKey: "",
            loadProfileHash: "",
            predictedLoadProfileHash: canonicalLoadProfileHash(normalizedDefaultProfile),
            effectiveContextLength: normalizedDefaultProfile.contextLength,
            loadProfileOverride: nil,
            effectiveLoadProfile: normalizedDefaultProfile,
            source: "model_default"
        )
    }

    // Keep the JSON byte-for-byte stable with the Python runtime for the fields Hub models expose.
    static func canonicalLoadProfileHash(_ profile: LocalModelLoadProfile) -> String {
        let canonicalJSON = canonicalLoadProfileJSONString(profile)
        let digest = SHA256.hash(data: Data(canonicalJSON.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func canonicalLoadProfileJSONString(_ profile: LocalModelLoadProfile) -> String {
        var fields: [(String, String)] = [
            ("context_length", String(max(512, profile.contextLength))),
        ]
        if let gpuOffloadRatio = profile.gpuOffloadRatio {
            fields.append(("gpu_offload_ratio", String(gpuOffloadRatio)))
        }
        if let ropeFrequencyBase = profile.ropeFrequencyBase {
            fields.append(("rope_frequency_base", String(ropeFrequencyBase)))
        }
        if let ropeFrequencyScale = profile.ropeFrequencyScale {
            fields.append(("rope_frequency_scale", String(ropeFrequencyScale)))
        }
        if let evalBatchSize = profile.evalBatchSize {
            fields.append(("eval_batch_size", String(evalBatchSize)))
        }
        if let ttl = profile.ttl {
            fields.append(("ttl", String(ttl)))
        }
        if let parallel = profile.parallel {
            fields.append(("parallel", String(parallel)))
        }
        if let identifier = profile.identifier,
           let encodedIdentifier = jsonStringLiteral(identifier) {
            fields.append(("identifier", encodedIdentifier))
        }
        if let vision = profile.vision, !vision.isEmpty {
            fields.append(("vision", canonicalVisionLoadProfileJSONString(vision)))
        }
        let body = fields
            .sorted { $0.0 < $1.0 }
            .map { key, value in
                "\"\(key)\":\(value)"
            }
            .joined(separator: ",")
        return "{\(body)}"
    }

    private static func canonicalVisionLoadProfileJSONString(_ vision: LocalModelVisionLoadProfile) -> String {
        var fields: [(String, String)] = []
        if let imageMaxDimension = vision.imageMaxDimension {
            fields.append(("image_max_dimension", String(imageMaxDimension)))
        }
        let body = fields
            .sorted { $0.0 < $1.0 }
            .map { key, value in
                "\"\(key)\":\(value)"
            }
            .joined(separator: ",")
        return "{\(body)}"
    }

    private static func jsonStringLiteral(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return encoded
    }
}

private extension LocalModelLoadProfileOverride {
    var requestPayload: [String: Any] {
        var payload: [String: Any] = [:]
        if let contextLength {
            payload["context_length"] = max(512, contextLength)
        }
        if let gpuOffloadRatio {
            payload["gpu_offload_ratio"] = gpuOffloadRatio
        }
        if let ropeFrequencyBase {
            payload["rope_frequency_base"] = ropeFrequencyBase
        }
        if let ropeFrequencyScale {
            payload["rope_frequency_scale"] = ropeFrequencyScale
        }
        if let evalBatchSize {
            payload["eval_batch_size"] = evalBatchSize
        }
        if let ttl {
            payload["ttl"] = ttl
        }
        if let parallel {
            payload["parallel"] = parallel
        }
        if let identifier {
            let token = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                payload["identifier"] = token
            }
        }
        if let visionPayload = vision?.requestPayload, !visionPayload.isEmpty {
            payload["vision"] = visionPayload
        }
        return payload
    }
}

private extension LocalModelVisionLoadProfile {
    var requestPayload: [String: Any] {
        var payload: [String: Any] = [:]
        if let imageMaxDimension {
            payload["image_max_dimension"] = imageMaxDimension
        }
        return payload
    }
}
