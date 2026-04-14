import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class HubVoiceTTSSynthesisServiceTests: XCTestCase {
    override func tearDown() {
        HubVoiceTTSSynthesisService.resetTestingOverrides()
        super.tearDown()
    }

    func testPlaybackAvailabilityRequiresEligibleVoicePackAndLaunchConfig() {
        let model = HubModel(
            id: "hub.voice.zh.warm",
            name: "Warm Chinese",
            backend: "transformers",
            quant: "fp16",
            contextLength: 4096,
            paramsB: 0.08,
            state: .available,
            modelPath: "/tmp/hub.voice.zh.warm",
            taskKinds: ["text_to_speech"],
            inputModalities: ["text"],
            outputModalities: ["audio"]
        )

        HubVoiceTTSSynthesisService.installTestingOverrides(
            modelResolver: { id in
                id == model.id ? model : nil
            },
            launchConfigResolver: { _ in
                LocalRuntimeCommandLaunchConfig(
                    executable: "/usr/bin/python3",
                    argumentsPrefix: ["runtime.py"],
                    environment: [:],
                    baseDirPath: "/tmp"
                )
            }
        )

        XCTAssertTrue(
            HubVoiceTTSSynthesisService.isPlaybackAvailable(preferredModelID: model.id)
        )

        HubVoiceTTSSynthesisService.installTestingOverrides(
            modelResolver: { id in
                id == model.id ? model : nil
            },
            launchConfigResolver: { _ in nil }
        )

        XCTAssertFalse(
            HubVoiceTTSSynthesisService.isPlaybackAvailable(preferredModelID: model.id)
        )
    }

    func testPlaybackReadinessReturnsConcreteReasonWhenLaunchConfigIsMissing() {
        let model = HubModel(
            id: "hub.voice.zh.warm",
            name: "Warm Chinese",
            backend: "transformers",
            quant: "fp16",
            contextLength: 4096,
            paramsB: 0.08,
            state: .available,
            modelPath: "/tmp/hub.voice.zh.warm",
            taskKinds: ["text_to_speech"],
            inputModalities: ["text"],
            outputModalities: ["audio"]
        )

        HubVoiceTTSSynthesisService.installTestingOverrides(
            modelResolver: { id in
                id == model.id ? model : nil
            },
            launchConfigResolver: { _ in nil }
        )

        let result = HubVoiceTTSSynthesisService.playbackReadiness(
            IPCVoiceTTSReadinessRequestPayload(preferredModelID: model.id)
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.source, "hub_ipc")
        XCTAssertEqual(result.modelID, model.id)
        XCTAssertEqual(result.reasonCode, "voice_tts_runtime_launch_config_unavailable")
    }

    func testSynthesizeBuildsRuntimeRequestAndMapsAudioResponse() throws {
        let model = HubModel(
            id: "hub.voice.zh.warm",
            name: "Warm Chinese",
            backend: "transformers",
            quant: "fp16",
            contextLength: 4096,
            paramsB: 0.08,
            state: .available,
            modelPath: "/tmp/hub.voice.zh.warm",
            taskKinds: ["text_to_speech"],
            inputModalities: ["text"],
            outputModalities: ["audio"]
        )
        let expectedLaunchConfig = LocalRuntimeCommandLaunchConfig(
            executable: "/usr/bin/python3",
            argumentsPrefix: ["runtime.py"],
            environment: ["PYTHONPATH": "/tmp/python_service"],
            baseDirPath: "/tmp"
        )
        var auditLines: [String] = []

        HubVoiceTTSSynthesisService.installTestingOverrides(
            modelResolver: { id in
                id == model.id ? model : nil
            },
            launchConfigResolver: { providerID in
                XCTAssertEqual(providerID, "transformers")
                return expectedLaunchConfig
            },
            runtimeCommandRunner: { command, requestData, launchConfig, timeoutSec in
                XCTAssertEqual(command, "run-local-task")
                XCTAssertEqual(launchConfig.executable, expectedLaunchConfig.executable)
                XCTAssertEqual(launchConfig.argumentsPrefix, expectedLaunchConfig.argumentsPrefix)
                XCTAssertEqual(launchConfig.environment, expectedLaunchConfig.environment)
                XCTAssertEqual(launchConfig.baseDirPath, expectedLaunchConfig.baseDirPath)
                XCTAssertEqual(timeoutSec, 45.0, accuracy: 0.001)

                let request = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: requestData, options: []) as? [String: Any]
                )
                XCTAssertEqual(request["provider"] as? String, "transformers")
                XCTAssertEqual(request["model_id"] as? String, model.id)
                XCTAssertEqual(request["task_kind"] as? String, "text_to_speech")
                XCTAssertEqual(request["text"] as? String, "Phoenix 项目目前卡在授权。")
                XCTAssertEqual(request["allow_daemon_proxy"] as? Bool, false)
                XCTAssertEqual(request["allow_tts_system_fallback"] as? Bool, true)

                let options = try XCTUnwrap(request["options"] as? [String: Any])
                XCTAssertEqual(options["locale"] as? String, "zh-CN")
                XCTAssertEqual(options["voice_color"] as? String, "warm")
                XCTAssertEqual(try XCTUnwrap(options["speech_rate"] as? Double), 1.1, accuracy: 0.000_1)

                let response: [String: Any] = [
                    "ok": true,
                    "provider": "transformers",
                    "model_id": model.id,
                    "task_kind": "text_to_speech",
                    "audio_path": "/tmp/generated_voice.aiff",
                    "engine_name": "kokoro",
                    "speaker_id": "zh_warm_f1",
                    "native_tts_used": false,
                    "fallback_reason_code": "system_voice_compatibility_fallback",
                    "detail": "system voice compatibility generated clip",
                ]
                return try JSONSerialization.data(withJSONObject: response, options: [])
            },
            ttsAuditSink: { auditLines.append($0) }
        )

        let result = HubVoiceTTSSynthesisService.synthesize(
            IPCVoiceTTSRequestPayload(
                preferredModelID: model.id,
                text: "Phoenix 项目目前卡在授权。",
                localeIdentifier: "zh-CN",
                voiceColor: "warm",
                speechRate: 1.1
            )
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.source, "local_runtime_command")
        XCTAssertEqual(result.provider, "transformers")
        XCTAssertEqual(result.modelID, model.id)
        XCTAssertEqual(result.taskKind, "text_to_speech")
        XCTAssertEqual(result.audioFilePath, "/tmp/generated_voice.aiff")
        XCTAssertEqual(result.engineName, "kokoro")
        XCTAssertEqual(result.speakerId, "zh_warm_f1")
        XCTAssertEqual(result.nativeTTSUsed, false)
        XCTAssertEqual(result.fallbackReasonCode, "system_voice_compatibility_fallback")
        XCTAssertEqual(result.ttsAudit?.schemaVersion, "xhub.local_tts_audit.v1")
        XCTAssertEqual(result.ttsAudit?.capability, "ai.audio.tts.local")
        XCTAssertEqual(result.ttsAudit?.sourceKind, "fallback_output")
        XCTAssertEqual(result.ttsAudit?.outputRefKind, "audio_path")
        XCTAssertEqual(result.ttsAudit?.requestedModelID, model.id)
        XCTAssertEqual(result.ttsAuditLine, "tts_audit status=ok provider=transformers model=\(model.id) source=fallback_output route=local_runtime_command output=audio_path fallback=system_voice_compatibility_fallback deny=none")
        XCTAssertEqual(auditLines, [result.ttsAuditLine!])
    }

    func testSynthesizeRejectsIneligibleModelBeforeCallingRuntime() {
        let model = HubModel(
            id: "hub.voice.bad",
            name: "Not Voice",
            backend: "transformers",
            quant: "fp16",
            contextLength: 4096,
            paramsB: 0.08,
            state: .available,
            modelPath: "/tmp/hub.voice.bad",
            taskKinds: ["embedding"],
            inputModalities: ["text"],
            outputModalities: ["embedding"]
        )

        var runtimeCallCount = 0
        var auditLines: [String] = []
        HubVoiceTTSSynthesisService.installTestingOverrides(
            modelResolver: { id in
                id == model.id ? model : nil
            },
            launchConfigResolver: { _ in
                LocalRuntimeCommandLaunchConfig(
                    executable: "/usr/bin/python3",
                    argumentsPrefix: ["runtime.py"],
                    environment: [:],
                    baseDirPath: "/tmp"
                )
            },
            runtimeCommandRunner: { _, _, _, _ in
                runtimeCallCount += 1
                return Data()
            },
            ttsAuditSink: { auditLines.append($0) }
        )

        let result = HubVoiceTTSSynthesisService.synthesize(
            IPCVoiceTTSRequestPayload(
                preferredModelID: model.id,
                text: "hello",
                localeIdentifier: nil,
                voiceColor: nil,
                speechRate: nil
            )
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.reasonCode, "voice_tts_model_ineligible")
        XCTAssertEqual(runtimeCallCount, 0)
        XCTAssertEqual(result.ttsAudit?.sourceKind, "failed")
        XCTAssertEqual(result.ttsAudit?.outputRefKind, "none")
        XCTAssertEqual(result.ttsAudit?.requestedModelID, model.id)
        XCTAssertEqual(result.ttsAuditLine, "tts_audit status=failed provider=transformers model=\(model.id) source=failed route=hub_ipc output=none fallback=none deny=none")
        XCTAssertEqual(auditLines, [result.ttsAuditLine!])
    }
}
