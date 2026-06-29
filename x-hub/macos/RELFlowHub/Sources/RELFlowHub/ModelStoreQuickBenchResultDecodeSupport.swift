import Foundation
import RELFlowHubCore

extension ModelStore {
    func decodeBenchResult(
        _ payloadData: Data,
        modelId: String,
        providerID: String,
        fallbackFixtureTitle: String
    ) -> ModelBenchResult {
        if let decoded = try? JSONDecoder().decode(ModelBenchResult.self, from: payloadData) {
            if !fallbackFixtureTitle.isEmpty, decoded.fixtureTitle.isEmpty {
                return ModelBenchResult(
                    resultID: decoded.resultID,
                    modelId: decoded.modelId,
                    providerID: decoded.providerID,
                    taskKind: decoded.taskKind,
                    loadProfileHash: decoded.loadProfileHash,
                    fixtureProfile: decoded.fixtureProfile,
                    fixtureTitle: fallbackFixtureTitle,
                    measuredAt: decoded.measuredAt,
                    runtimeVersion: decoded.runtimeVersion,
                    schemaVersion: decoded.schemaVersion,
                    resultKind: decoded.resultKind,
                    ok: decoded.ok,
                    reasonCode: decoded.reasonCode,
                    runtimeSource: decoded.runtimeSource,
                    runtimeSourcePath: decoded.runtimeSourcePath,
                    runtimeResolutionState: decoded.runtimeResolutionState,
                    runtimeReasonCode: decoded.runtimeReasonCode,
                    fallbackUsed: decoded.fallbackUsed,
                    runtimeHint: decoded.runtimeHint,
                    runtimeMissingRequirements: decoded.runtimeMissingRequirements,
                    runtimeMissingOptionalRequirements: decoded.runtimeMissingOptionalRequirements,
                    verdict: decoded.verdict,
                    fallbackMode: decoded.fallbackMode,
                    notes: decoded.notes,
                    coldStartMs: decoded.coldStartMs,
                    latencyMs: decoded.latencyMs,
                    peakMemoryBytes: decoded.peakMemoryBytes,
                    throughputValue: decoded.throughputValue,
                    throughputUnit: decoded.throughputUnit,
                    effectiveContextLength: decoded.effectiveContextLength,
                    promptTokens: decoded.promptTokens,
                    generationTokens: decoded.generationTokens,
                    promptTPS: decoded.promptTPS,
                    generationTPS: decoded.generationTPS
                )
            }
            return decoded
        }

        guard let raw = try? JSONSerialization.jsonObject(with: payloadData, options: []),
              let payload = raw as? [String: Any] else {
            return ModelBenchResult(
                modelId: modelId,
                providerID: providerID,
                taskKind: "",
                loadProfileHash: "",
                fixtureProfile: "",
                fixtureTitle: fallbackFixtureTitle,
                measuredAt: Date().timeIntervalSince1970,
                runtimeVersion: AIRuntimeStatusStorage.load()?.runtimeVersion,
                schemaVersion: ModelBenchResult.schemaVersion,
                resultKind: ModelBenchResult.quickBenchKind,
                ok: false,
                reasonCode: "bench_decode_failed",
                verdict: "",
                fallbackMode: "",
                notes: ["bench_decode_failed"]
            )
        }

        let taskKind = (payload["taskKind"] as? String ?? payload["task_kind"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let fixtureProfile = (payload["fixtureProfile"] as? String ?? payload["fixture_profile"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonCode = (payload["reasonCode"] as? String ?? payload["reason_code"] as? String ?? payload["error"] as? String ?? "bench_decode_failed")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ModelBenchResult(
            modelId: modelId,
            providerID: providerID,
            taskKind: taskKind,
            loadProfileHash: (payload["loadProfileHash"] as? String ?? payload["load_profile_hash"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            fixtureProfile: fixtureProfile,
            fixtureTitle: fallbackFixtureTitle,
            measuredAt: Date().timeIntervalSince1970,
            runtimeVersion: payload["runtimeVersion"] as? String ?? payload["runtime_version"] as? String,
            schemaVersion: ModelBenchResult.schemaVersion,
            resultKind: payload["resultKind"] as? String ?? payload["result_kind"] as? String ?? ModelBenchResult.quickBenchKind,
            ok: payload["ok"] as? Bool ?? false,
            reasonCode: reasonCode,
            runtimeSource: (payload["runtimeSource"] as? String ?? payload["runtime_source"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            runtimeSourcePath: (payload["runtimeSourcePath"] as? String ?? payload["runtime_source_path"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            runtimeResolutionState: (payload["runtimeResolutionState"] as? String ?? payload["runtime_resolution_state"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            runtimeReasonCode: (payload["runtimeReasonCode"] as? String ?? payload["runtime_reason_code"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            fallbackUsed: payload["fallbackUsed"] as? Bool ?? payload["fallback_used"] as? Bool ?? false,
            runtimeHint: (payload["runtimeHint"] as? String ?? payload["runtime_hint"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            runtimeMissingRequirements: payload["runtimeMissingRequirements"] as? [String]
                ?? payload["runtime_missing_requirements"] as? [String]
                ?? [],
            runtimeMissingOptionalRequirements: payload["runtimeMissingOptionalRequirements"] as? [String]
                ?? payload["runtime_missing_optional_requirements"] as? [String]
                ?? [],
            verdict: (payload["verdict"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            fallbackMode: (payload["fallbackMode"] as? String ?? payload["fallback_mode"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            notes: [reasonCode]
        )
    }
}
