import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct HubIPCClientVoiceTTSTests {
    private static let gate = HubGlobalStateTestGate.shared

    @Test
    func synthesizeVoiceViaLocalHubUsesFileIPCAndMapsAck() async throws {
        try await Self.gate.run {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_hub_voice_tts_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try writeTestHubStatus(base: base)
            try writeModelState(
                base: base,
                models: [
                    HubModel(
                        id: "hub.voice.zh.warm",
                        name: "Warm Chinese",
                        backend: "transformers",
                        quant: "fp16",
                        contextLength: 4096,
                        paramsB: 0.08,
                        state: .available,
                        memoryBytes: nil,
                        tokensPerSec: nil,
                        modelPath: "/models/hub.voice.zh.warm",
                        note: nil,
                        modelFormat: "safetensors",
                        taskKinds: ["text_to_speech"],
                        inputModalities: ["text"],
                        outputModalities: ["audio"]
                    ),
                ]
            )

            HubPaths.setPinnedBaseDirOverride(base)
            defer {
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: base)
            }

            let capture = VoiceRequestCapture()
            let writerTask = Task {
                let eventsDir = base.appendingPathComponent("ipc_events", isDirectory: true)
                let responsesDir = base.appendingPathComponent("ipc_responses", isDirectory: true)
                let deadline = Date().addingTimeInterval(2.0)

                while Date() < deadline {
                    let files = (try? FileManager.default.contentsOfDirectory(at: eventsDir, includingPropertiesForKeys: nil)) ?? []
                    if let requestURL = files.first(where: { $0.lastPathComponent.hasPrefix("xterminal_voice_tts_") }),
                       let data = try? Data(contentsOf: requestURL),
                       let request = try? JSONDecoder().decode(HubIPCClient.VoiceTTSIPCRequest.self, from: data) {
                        capture.set(request)
                        let response = HubIPCClient.VoiceTTSIPCResponse(
                            type: "voice_tts_synthesize_ack",
                            reqId: request.reqId,
                            ok: true,
                            id: request.voiceTTS.preferredModelId,
                            error: nil,
                            voiceTTS: HubIPCClient.VoiceTTSResult(
                                ok: true,
                                source: "local_runtime_command",
                                provider: "transformers",
                                modelId: request.voiceTTS.preferredModelId,
                                taskKind: "text_to_speech",
                                audioFilePath: "/tmp/generated_voice_clip.aiff",
                                engineName: "kokoro",
                                speakerId: "zh_warm_f1",
                                nativeTTSUsed: false,
                                fallbackReasonCode: "system_voice_compatibility_fallback",
                                reasonCode: "hub_voice_pack_played",
                                runtimeReasonCode: nil,
                                error: nil,
                                detail: "generated",
                                ttsAudit: HubIPCClient.VoiceTTSAudit(
                                    schemaVersion: "xhub.local_tts_audit.v1",
                                    ok: true,
                                    taskKind: "text_to_speech",
                                    requestId: "",
                                    capability: "ai.audio.tts.local",
                                    provider: "transformers",
                                    requestedModelId: request.voiceTTS.preferredModelId,
                                    modelId: request.voiceTTS.preferredModelId,
                                    resolvedModelId: request.voiceTTS.preferredModelId,
                                    routeSource: "local_runtime_command",
                                    sourceKind: "fallback_output",
                                    outputRefKind: "audio_path",
                                    engineName: "kokoro",
                                    speakerId: "zh_warm_f1",
                                    nativeTTSUsed: false,
                                    fallbackUsed: true,
                                    fallbackMode: "",
                                    fallbackReasonCode: "system_voice_compatibility_fallback",
                                    denyCode: "",
                                    rawDenyCode: "",
                                    locale: "zh-CN",
                                    voiceColor: "warm",
                                    speechRate: 1.1
                                ),
                                ttsAuditLine: "tts_audit status=ok provider=transformers model=hub.voice.zh.warm source=fallback_output route=local_runtime_command output=audio_path fallback=system_voice_compatibility_fallback deny=none"
                            )
                        )
                        let responseData = try? JSONEncoder().encode(response)
                        if let responseData {
                            let responseURL = responsesDir.appendingPathComponent("resp_\(request.reqId).json")
                            try? responseData.write(to: responseURL, options: .atomic)
                        }
                        return true
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                return false
            }

            let result = HubIPCClient.synthesizeVoiceViaLocalHub(
                preferredModelID: "hub.voice.zh.warm",
                text: "Phoenix 项目目前卡在授权。",
                localeIdentifier: "zh-CN",
                voiceColor: "warm",
                speechRate: 1.1,
                timeoutSec: 1.5
            )

            let writeFinished = await writerTask.value
            #expect(writeFinished)
            let request = try #require(capture.get())
            #expect(request.type == "voice_tts_synthesize")
            #expect(request.voiceTTS.preferredModelId == "hub.voice.zh.warm")
            #expect(request.voiceTTS.text == "Phoenix 项目目前卡在授权。")
            #expect(request.voiceTTS.localeIdentifier == "zh-CN")
            #expect(request.voiceTTS.voiceColor == "warm")
            #expect(request.voiceTTS.speechRate == 1.1)

            #expect(result.ok)
            #expect(result.source == "file_ipc")
            #expect(result.provider == "transformers")
            #expect(result.modelId == "hub.voice.zh.warm")
            #expect(result.taskKind == "text_to_speech")
            #expect(result.audioFilePath == "/tmp/generated_voice_clip.aiff")
            #expect(result.engineName == "kokoro")
            #expect(result.speakerId == "zh_warm_f1")
            #expect(result.nativeTTSUsed == false)
            #expect(result.fallbackReasonCode == "system_voice_compatibility_fallback")
            #expect(result.reasonCode == "hub_voice_pack_played")
            #expect(result.ttsAudit?.schemaVersion == "xhub.local_tts_audit.v1")
            #expect(result.ttsAudit?.capability == "ai.audio.tts.local")
            #expect(result.ttsAudit?.sourceKind == "fallback_output")
            #expect(result.ttsAuditLine == "tts_audit status=ok provider=transformers model=hub.voice.zh.warm source=fallback_output route=local_runtime_command output=audio_path fallback=system_voice_compatibility_fallback deny=none")
        }
    }

    @Test
    func localVoicePackAvailabilityRequiresRegisteredTextToSpeechModel() async throws {
        try await Self.gate.run {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_hub_voice_ready_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try writeTestHubStatus(base: base)
            try writeModelState(
                base: base,
                models: [
                    HubModel(
                        id: "hub.voice.zh.warm",
                        name: "Warm Chinese",
                        backend: "transformers",
                        quant: "fp16",
                        contextLength: 4096,
                        paramsB: 0.08,
                        state: .available,
                        memoryBytes: nil,
                        tokensPerSec: nil,
                        modelPath: "/models/hub.voice.zh.warm",
                        note: nil,
                        modelFormat: "safetensors",
                        taskKinds: ["text_to_speech"],
                        inputModalities: ["text"],
                        outputModalities: ["audio"]
                    ),
                    HubModel(
                        id: "hub.embedding.zh",
                        name: "Embedding",
                        backend: "transformers",
                        quant: "fp16",
                        contextLength: 4096,
                        paramsB: 0.6,
                        state: .available,
                        memoryBytes: nil,
                        tokensPerSec: nil,
                        modelPath: "/models/hub.embedding.zh",
                        note: nil,
                        modelFormat: "safetensors",
                        taskKinds: ["embedding"],
                        inputModalities: ["text"],
                        outputModalities: ["embedding"]
                    ),
                ]
            )

            HubPaths.setPinnedBaseDirOverride(base)
            defer {
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: base)
            }

            let capture = VoiceReadinessRequestCapture()
            let writerTask = Task {
                let eventsDir = base.appendingPathComponent("ipc_events", isDirectory: true)
                let responsesDir = base.appendingPathComponent("ipc_responses", isDirectory: true)
                let deadline = Date().addingTimeInterval(2.0)

                while Date() < deadline {
                    let files = (try? FileManager.default.contentsOfDirectory(at: eventsDir, includingPropertiesForKeys: nil)) ?? []
                    if let requestURL = files.first(where: { $0.lastPathComponent.hasPrefix("xterminal_voice_tts_readiness_") }),
                       let data = try? Data(contentsOf: requestURL),
                       let request = try? JSONDecoder().decode(HubIPCClient.VoiceTTSReadinessIPCRequest.self, from: data) {
                        capture.set(request)
                        let response = HubIPCClient.VoiceTTSReadinessIPCResponse(
                            type: "voice_tts_readiness_ack",
                            reqId: request.reqId,
                            ok: true,
                            id: request.voiceTTSReadiness.preferredModelId,
                            error: nil,
                            voiceTTSReadiness: HubIPCClient.VoiceTTSReadinessResult(
                                ok: true,
                                source: "hub_ipc",
                                provider: "transformers",
                                modelId: request.voiceTTSReadiness.preferredModelId,
                                reasonCode: "voice_tts_ready",
                                detail: "preferred voice pack can be synthesized via local Hub runtime"
                            )
                        )
                        let responseData = try? JSONEncoder().encode(response)
                        if let responseData {
                            let responseURL = responsesDir.appendingPathComponent("resp_\(request.reqId).json")
                            try? responseData.write(to: responseURL, options: .atomic)
                        }
                        return true
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                return false
            }

            #expect(
                HubIPCClient.isLocalHubVoicePackPlaybackAvailable(
                    preferredModelID: "hub.voice.zh.warm"
                )
            )
            let writeFinished = await writerTask.value
            #expect(writeFinished)
            let request = try #require(capture.get())
            #expect(request.type == "voice_tts_readiness")
            #expect(request.voiceTTSReadiness.preferredModelId == "hub.voice.zh.warm")
            #expect(
                !HubIPCClient.isLocalHubVoicePackPlaybackAvailable(
                    preferredModelID: "hub.embedding.zh"
                )
            )
            #expect(
                !HubIPCClient.isLocalHubVoicePackPlaybackAvailable(
                    preferredModelID: "missing.voice.pack"
                )
            )
        }
    }

    private func writeTestHubStatus(base: URL) throws {
        let eventsDir = base.appendingPathComponent("ipc_events", isDirectory: true)
        let responsesDir = base.appendingPathComponent("ipc_responses", isDirectory: true)
        try FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: responsesDir, withIntermediateDirectories: true)

        let status = HubStatus(
            pid: 42,
            startedAt: Date().timeIntervalSince1970,
            updatedAt: Date().timeIntervalSince1970,
            ipcMode: "file",
            ipcPath: eventsDir.path,
            baseDir: base.path,
            protocolVersion: 1,
            aiReady: true,
            loadedModelCount: 0,
            modelsUpdatedAt: Date().timeIntervalSince1970
        )
        let data = try JSONEncoder().encode(status)
        try data.write(to: base.appendingPathComponent("hub_status.json"), options: .atomic)
    }

    private func writeModelState(base: URL, models: [HubModel]) throws {
        let snapshot = ModelStateSnapshot(
            models: models,
            updatedAt: Date().timeIntervalSince1970
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: base.appendingPathComponent("models_state.json"), options: .atomic)
    }
}

private final class VoiceRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: HubIPCClient.VoiceTTSIPCRequest?

    func set(_ value: HubIPCClient.VoiceTTSIPCRequest) {
        lock.lock()
        request = value
        lock.unlock()
    }

    func get() -> HubIPCClient.VoiceTTSIPCRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

private final class VoiceReadinessRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: HubIPCClient.VoiceTTSReadinessIPCRequest?

    func set(_ value: HubIPCClient.VoiceTTSReadinessIPCRequest) {
        lock.lock()
        request = value
        lock.unlock()
    }

    func get() -> HubIPCClient.VoiceTTSReadinessIPCRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}
