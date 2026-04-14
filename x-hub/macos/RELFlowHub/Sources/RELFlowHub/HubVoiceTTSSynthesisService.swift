import Foundation
import RELFlowHubCore

enum HubVoiceTTSSynthesisService {
    private static let supportedTaskKind = "text_to_speech"
    private static let ttsCapability = "ai.audio.tts.local"
    private static let ttsAuditSchemaVersion = "xhub.local_tts_audit.v1"
    private static let ttsAuditLogFilename = "voice_tts_audit.log"
    typealias ModelResolver = (String) -> HubModel?
    typealias LaunchConfigResolver = (String) -> LocalRuntimeCommandLaunchConfig?
    typealias RuntimeCommandRunner = (
        String,
        Data,
        LocalRuntimeCommandLaunchConfig,
        TimeInterval
    ) throws -> Data
    typealias TTSAuditSink = (String) -> Void
    private static let overrideLock = NSLock()
    nonisolated(unsafe) private static var modelResolverOverride: ModelResolver?
    nonisolated(unsafe) private static var launchConfigResolverOverride: LaunchConfigResolver?
    nonisolated(unsafe) private static var runtimeCommandRunnerOverride: RuntimeCommandRunner?
    nonisolated(unsafe) private static var ttsAuditSinkOverride: TTSAuditSink?

    static func isPlaybackAvailable(preferredModelID: String) -> Bool {
        guard let model = resolveModel(preferredModelID: preferredModelID) else {
            return false
        }
        guard isEligibleVoicePackModel(model) else {
            return false
        }
        let providerID = LocalModelExecutionProviderResolver.preferredRuntimeProviderID(for: model)
        return loadLaunchConfig(preferredProviderID: providerID) != nil
    }

    static func playbackReadiness(
        _ payload: IPCVoiceTTSReadinessRequestPayload
    ) -> IPCVoiceTTSReadinessResult {
        let preferredModelID = payload.preferredModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preferredModelID.isEmpty else {
            return IPCVoiceTTSReadinessResult(
                ok: false,
                source: "hub_ipc",
                reasonCode: "voice_tts_missing_model_id",
                detail: "preferred_model_id is required"
            )
        }

        guard let model = resolveModel(preferredModelID: preferredModelID) else {
            return IPCVoiceTTSReadinessResult(
                ok: false,
                source: "hub_ipc",
                modelID: preferredModelID,
                reasonCode: "voice_tts_model_not_found",
                detail: "preferred voice pack model is not registered in Hub"
            )
        }

        guard isEligibleVoicePackModel(model) else {
            return IPCVoiceTTSReadinessResult(
                ok: false,
                source: "hub_ipc",
                modelID: model.id,
                reasonCode: "voice_tts_model_ineligible",
                detail: "preferred model is not a local text_to_speech voice pack"
            )
        }

        let providerID = LocalModelExecutionProviderResolver.preferredRuntimeProviderID(for: model)
        guard loadLaunchConfig(preferredProviderID: providerID) != nil else {
            return IPCVoiceTTSReadinessResult(
                ok: false,
                source: "hub_ipc",
                provider: providerID,
                modelID: model.id,
                reasonCode: "voice_tts_runtime_launch_config_unavailable",
                detail: "local runtime command launch configuration is unavailable"
            )
        }

        return IPCVoiceTTSReadinessResult(
            ok: true,
            source: "hub_ipc",
            provider: providerID,
            modelID: model.id,
            reasonCode: "voice_tts_ready",
            detail: "preferred voice pack can be synthesized via local Hub runtime"
        )
    }

    static func synthesize(_ payload: IPCVoiceTTSRequestPayload) -> IPCVoiceTTSResult {
        let preferredModelID = payload.preferredModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !preferredModelID.isEmpty else {
            return finalizeResult(
                IPCVoiceTTSResult(
                ok: false,
                source: "hub_ipc",
                taskKind: supportedTaskKind,
                reasonCode: "voice_tts_missing_model_id",
                detail: "preferred_model_id is required"
                ),
                payload: payload,
                requestedModelID: preferredModelID,
                resolvedModelIDHint: nil
            )
        }

        guard !text.isEmpty else {
            return finalizeResult(
                IPCVoiceTTSResult(
                ok: false,
                source: "hub_ipc",
                modelID: preferredModelID,
                taskKind: supportedTaskKind,
                reasonCode: "voice_tts_empty_text",
                detail: "text is required"
                ),
                payload: payload,
                requestedModelID: preferredModelID,
                resolvedModelIDHint: preferredModelID
            )
        }

        guard let model = resolveModel(preferredModelID: preferredModelID) else {
            return finalizeResult(
                IPCVoiceTTSResult(
                ok: false,
                source: "hub_ipc",
                modelID: preferredModelID,
                taskKind: supportedTaskKind,
                reasonCode: "voice_tts_model_not_found",
                detail: "preferred voice pack model is not registered in Hub"
                ),
                payload: payload,
                requestedModelID: preferredModelID,
                resolvedModelIDHint: preferredModelID
            )
        }

        guard isEligibleVoicePackModel(model) else {
            return finalizeResult(
                IPCVoiceTTSResult(
                ok: false,
                source: "hub_ipc",
                modelID: model.id,
                taskKind: supportedTaskKind,
                reasonCode: "voice_tts_model_ineligible",
                detail: "preferred model is not a local text_to_speech voice pack"
                ),
                payload: payload,
                requestedModelID: preferredModelID,
                resolvedModelIDHint: model.id
            )
        }

        let providerID = LocalModelExecutionProviderResolver.preferredRuntimeProviderID(for: model)
        guard let launchConfig = loadLaunchConfig(preferredProviderID: providerID) else {
            return finalizeResult(
                IPCVoiceTTSResult(
                ok: false,
                source: "hub_ipc",
                provider: providerID,
                modelID: model.id,
                taskKind: supportedTaskKind,
                reasonCode: "voice_tts_runtime_launch_config_unavailable",
                detail: "local runtime command launch configuration is unavailable"
                ),
                payload: payload,
                requestedModelID: preferredModelID,
                resolvedModelIDHint: model.id
            )
        }

        let request = makeRuntimeRequest(
            providerID: providerID,
            modelID: model.id,
            payload: payload
        )
        guard JSONSerialization.isValidJSONObject(request),
              let requestData = try? JSONSerialization.data(withJSONObject: request, options: []) else {
            return finalizeResult(
                IPCVoiceTTSResult(
                ok: false,
                source: "hub_ipc",
                provider: providerID,
                modelID: model.id,
                taskKind: supportedTaskKind,
                reasonCode: "voice_tts_invalid_request_payload",
                detail: "voice TTS runtime request encoding failed"
                ),
                payload: payload,
                requestedModelID: preferredModelID,
                resolvedModelIDHint: model.id
            )
        }

        do {
            let responseData = try runRuntimeCommand(
                command: "run-local-task",
                requestData: requestData,
                launchConfig: launchConfig,
                timeoutSec: 45.0
            )
            return finalizeResult(
                mapRuntimeResponse(
                    responseData,
                    fallbackProviderID: providerID,
                    fallbackModelID: model.id
                ),
                payload: payload,
                requestedModelID: preferredModelID,
                resolvedModelIDHint: model.id
            )
        } catch {
            return finalizeResult(
                IPCVoiceTTSResult(
                ok: false,
                source: "local_runtime_command",
                provider: providerID,
                modelID: model.id,
                taskKind: supportedTaskKind,
                reasonCode: "voice_tts_runtime_failed",
                error: error.localizedDescription,
                detail: String(describing: error)
                ),
                payload: payload,
                requestedModelID: preferredModelID,
                resolvedModelIDHint: model.id
            )
        }
    }

    private static func resolveModel(preferredModelID: String) -> HubModel? {
        let normalizedID = preferredModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { return nil }
        if let override = withOverrides({ modelResolverOverride }) {
            return override(normalizedID)
        }
        return ModelStateStorage.load().models.first { $0.id == normalizedID }
    }

    private static func isEligibleVoicePackModel(_ model: HubModel) -> Bool {
        guard model.taskKinds.contains(supportedTaskKind) else {
            return false
        }
        return !LocalModelRuntimeActionPlanner.isRemoteModel(model)
    }

    private static func loadLaunchConfig(preferredProviderID: String) -> LocalRuntimeCommandLaunchConfig? {
        if let override = withOverrides({ launchConfigResolverOverride }) {
            return override(preferredProviderID)
        }
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                HubStore.shared.localRuntimeCommandLaunchConfig(
                    preferredProviderID: preferredProviderID
                )
            }
        }

        var launchConfig: LocalRuntimeCommandLaunchConfig?
        DispatchQueue.main.sync {
            launchConfig = MainActor.assumeIsolated {
                HubStore.shared.localRuntimeCommandLaunchConfig(
                    preferredProviderID: preferredProviderID
                )
            }
        }
        return launchConfig
    }

    private static func runRuntimeCommand(
        command: String,
        requestData: Data,
        launchConfig: LocalRuntimeCommandLaunchConfig,
        timeoutSec: TimeInterval
    ) throws -> Data {
        if let override = withOverrides({ runtimeCommandRunnerOverride }) {
            return try override(command, requestData, launchConfig, timeoutSec)
        }
        return try LocalRuntimeCommandRunner.run(
            command: command,
            requestData: requestData,
            launchConfig: launchConfig,
            timeoutSec: timeoutSec
        )
    }

    private static func makeRuntimeRequest(
        providerID: String,
        modelID: String,
        payload: IPCVoiceTTSRequestPayload
    ) -> [String: Any] {
        var options: [String: Any] = [:]
        if let locale = normalized(payload.localeIdentifier) {
            options["locale"] = locale
        }
        if let voiceColor = normalized(payload.voiceColor) {
            options["voice_color"] = voiceColor
        }
        if let speechRate = payload.speechRate, speechRate.isFinite {
            options["speech_rate"] = max(0.5, min(2.0, speechRate))
        }

        var request: [String: Any] = [
            "provider": providerID,
            "model_id": modelID,
            "task_kind": supportedTaskKind,
            "text": payload.text.trimmingCharacters(in: .whitespacesAndNewlines),
            "allow_daemon_proxy": false,
            "allow_tts_system_fallback": true,
        ]
        if !options.isEmpty {
            request["options"] = options
        }
        return request
    }

    private static func mapRuntimeResponse(
        _ data: Data,
        fallbackProviderID: String,
        fallbackModelID: String
    ) -> IPCVoiceTTSResult {
        guard let payload = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
            return IPCVoiceTTSResult(
                ok: false,
                source: "local_runtime_command",
                provider: fallbackProviderID,
                modelID: fallbackModelID,
                taskKind: supportedTaskKind,
                reasonCode: "voice_tts_invalid_runtime_response",
                detail: "runtime response JSON decoding failed"
            )
        }

        let ok = payload["ok"] as? Bool ?? false
        let provider = normalized(
            payload["provider"] as? String
        ) ?? fallbackProviderID
        let modelID = normalized(
            payload["modelId"] as? String
                ?? payload["model_id"] as? String
        ) ?? fallbackModelID
        let taskKind = normalized(
            payload["taskKind"] as? String
                ?? payload["task_kind"] as? String
        ) ?? supportedTaskKind
        let audioFilePath = normalized(
            payload["audioFilePath"] as? String
                ?? payload["audio_file_path"] as? String
                ?? payload["audioPath"] as? String
                ?? payload["audio_path"] as? String
                ?? payload["outputFilePath"] as? String
                ?? payload["output_file_path"] as? String
        )
        let audioFormat = normalized(
            payload["audioFormat"] as? String
                ?? payload["audio_format"] as? String
        )
        let voiceName = normalized(
            payload["voiceName"] as? String
                ?? payload["voice_name"] as? String
        )
        let engineName = normalized(
            payload["engineName"] as? String
                ?? payload["engine_name"] as? String
        )
        let speakerId = normalized(
            payload["speakerId"] as? String
                ?? payload["speaker_id"] as? String
        )
        let deviceBackend = normalized(
            payload["deviceBackend"] as? String
                ?? payload["device_backend"] as? String
        )
        let nativeTTSUsed = boolValue(
            payload["nativeTTSUsed"]
                ?? payload["native_tts_used"]
        )
        let fallbackMode = normalized(
            payload["fallbackMode"] as? String
                ?? payload["fallback_mode"] as? String
        )
        let fallbackReasonCode = normalized(
            payload["fallbackReasonCode"] as? String
                ?? payload["fallback_reason_code"] as? String
        )
        let reasonCode = normalized(
            payload["reasonCode"] as? String
                ?? payload["reason_code"] as? String
        )
        let runtimeReasonCode = normalized(
            payload["runtimeReasonCode"] as? String
                ?? payload["runtime_reason_code"] as? String
        )
        let error = normalized(payload["error"] as? String)
        let detail = normalized(
            payload["detail"] as? String
                ?? payload["message"] as? String
        )

        return IPCVoiceTTSResult(
            ok: ok && audioFilePath != nil,
            source: "local_runtime_command",
            provider: provider,
            modelID: modelID,
            taskKind: taskKind,
            audioFilePath: audioFilePath,
            audioFormat: audioFormat,
            voiceName: voiceName,
            engineName: engineName,
            speakerId: speakerId,
            deviceBackend: deviceBackend,
            nativeTTSUsed: nativeTTSUsed,
            fallbackMode: fallbackMode,
            fallbackReasonCode: fallbackReasonCode,
            reasonCode: reasonCode,
            runtimeReasonCode: runtimeReasonCode,
            error: error,
            detail: detail
        )
    }

    private static func finalizeResult(
        _ result: IPCVoiceTTSResult,
        payload: IPCVoiceTTSRequestPayload,
        requestedModelID: String,
        resolvedModelIDHint: String?
    ) -> IPCVoiceTTSResult {
        let audit = buildTTSAuditRecord(
            result: result,
            payload: payload,
            requestedModelID: requestedModelID,
            resolvedModelIDHint: resolvedModelIDHint
        )
        let auditLine = buildTTSAuditLine(audit)
        appendTTSAuditLine(auditLine)

        var finalized = result
        finalized.ttsAudit = audit
        finalized.ttsAuditLine = auditLine
        return finalized
    }

    private static func buildTTSAuditRecord(
        result: IPCVoiceTTSResult,
        payload: IPCVoiceTTSRequestPayload,
        requestedModelID: String,
        resolvedModelIDHint: String?
    ) -> IPCVoiceTTSAudit {
        let normalizedProvider = normalized(result.provider) ?? "transformers"
        let normalizedRequestedModelID = normalized(requestedModelID) ?? ""
        let normalizedResolvedModelID = normalized(result.modelID)
            ?? normalized(resolvedModelIDHint)
            ?? normalizedRequestedModelID
        let normalizedFallbackMode = normalized(result.fallbackMode) ?? ""
        let normalizedFallbackReasonCode = normalized(result.fallbackReasonCode) ?? ""
        let fallbackUsed = !normalizedFallbackMode.isEmpty || !normalizedFallbackReasonCode.isEmpty
        let normalizedAudioPath = normalized(result.audioFilePath) ?? ""
        let outputRefKind = normalizedAudioPath.isEmpty ? "none" : "audio_path"

        let sourceKind: String = {
            guard result.ok else { return "failed" }
            if fallbackUsed {
                return "fallback_output"
            }
            if result.nativeTTSUsed == true {
                return "native_tts"
            }
            if outputRefKind == "audio_path" {
                return "audio_path"
            }
            return "unknown"
        }()

        return IPCVoiceTTSAudit(
            schemaVersion: ttsAuditSchemaVersion,
            ok: result.ok,
            taskKind: normalized(result.taskKind) ?? supportedTaskKind,
            requestID: "",
            capability: ttsCapability,
            provider: normalizedProvider,
            requestedModelID: normalizedRequestedModelID,
            modelID: normalized(result.modelID) ?? normalizedResolvedModelID,
            resolvedModelID: normalizedResolvedModelID,
            routeSource: normalized(result.source) ?? "hub_ipc",
            sourceKind: sourceKind,
            outputRefKind: outputRefKind,
            engineName: normalized(result.engineName) ?? "",
            speakerId: normalized(result.speakerId) ?? "",
            nativeTTSUsed: result.nativeTTSUsed,
            fallbackUsed: fallbackUsed,
            fallbackMode: normalizedFallbackMode,
            fallbackReasonCode: normalizedFallbackReasonCode,
            denyCode: "",
            rawDenyCode: "",
            locale: normalizedLocale(payload.localeIdentifier),
            voiceColor: normalizedVoiceColor(payload.voiceColor),
            speechRate: normalizedSpeechRate(payload.speechRate)
        )
    }

    private static func buildTTSAuditLine(_ record: IPCVoiceTTSAudit) -> String {
        let fallbackToken = normalized(record.fallbackReasonCode) ?? normalized(record.fallbackMode) ?? "none"
        let modelToken = normalized(record.modelID) ?? normalized(record.resolvedModelID) ?? "(none)"
        let routeToken = normalized(record.routeSource) ?? "default"
        let outputToken = normalized(record.outputRefKind) ?? "none"
        let sourceToken = normalized(record.sourceKind) ?? "unknown"
        let statusToken = record.ok ? "ok" : "failed"
        let providerToken = normalized(record.provider) ?? "transformers"
        let denyToken = normalized(record.denyCode) ?? normalized(record.rawDenyCode) ?? "none"
        return [
            "tts_audit",
            "status=\(statusToken)",
            "provider=\(providerToken)",
            "model=\(modelToken)",
            "source=\(sourceToken)",
            "route=\(routeToken)",
            "output=\(outputToken)",
            "fallback=\(fallbackToken)",
            "deny=\(denyToken)",
        ].joined(separator: " ")
    }

    private static func appendTTSAuditLine(_ line: String) {
        let normalizedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLine.isEmpty else { return }

        if let override = withOverrides({ ttsAuditSinkOverride }) {
            override(normalizedLine)
            return
        }

        let base = SharedPaths.ensureHubDirectory()
        let url = base.appendingPathComponent(ttsAuditLogFilename)
        let ts = ISO8601DateFormatter().string(from: Date())
        let payload = "[\(ts)] \(normalizedLine)\n"
        guard let data = payload.data(using: .utf8) else { return }

        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let fileHandle = try FileHandle(forWritingTo: url)
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: data)
                try fileHandle.close()
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            HubDiagnostics.log("voice_tts_audit_append_failed error=\(error.localizedDescription)")
        }
    }

    private static func normalizedLocale(_ text: String?) -> String {
        let trimmed = normalized(text) ?? ""
        return trimmed.replacingOccurrences(of: "_", with: "-")
    }

    private static func normalizedVoiceColor(_ text: String?) -> String {
        let trimmed = normalized(text)?.lowercased() ?? ""
        return trimmed.isEmpty ? "neutral" : trimmed
    }

    private static func normalizedSpeechRate(_ value: Double?) -> Double {
        let rate = value ?? 1.0
        return max(0.6, min(1.8, rate.isFinite ? rate : 1.0))
    }

    private static func normalized(_ text: String?) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func boolValue(_ any: Any?) -> Bool? {
        switch any {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            let token = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch token {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func withOverrides<T>(_ body: () -> T) -> T {
        overrideLock.lock()
        defer { overrideLock.unlock() }
        return body()
    }

    static func installTestingOverrides(
        modelResolver: ModelResolver? = nil,
        launchConfigResolver: LaunchConfigResolver? = nil,
        runtimeCommandRunner: RuntimeCommandRunner? = nil,
        ttsAuditSink: TTSAuditSink? = nil
    ) {
        withOverrides {
            modelResolverOverride = modelResolver
            launchConfigResolverOverride = launchConfigResolver
            runtimeCommandRunnerOverride = runtimeCommandRunner
            ttsAuditSinkOverride = ttsAuditSink
        }
    }

    static func resetTestingOverrides() {
        withOverrides {
            modelResolverOverride = nil
            launchConfigResolverOverride = nil
            runtimeCommandRunnerOverride = nil
            ttsAuditSinkOverride = nil
        }
    }
}
