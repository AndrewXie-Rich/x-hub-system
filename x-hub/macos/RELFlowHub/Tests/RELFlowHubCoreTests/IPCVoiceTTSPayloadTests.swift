import XCTest
@testable import RELFlowHubCore

final class IPCVoiceTTSPayloadTests: XCTestCase {
    func testVoiceTTSReadinessRequestPayloadEncodesSnakeCaseKeys() throws {
        let payload = IPCVoiceTTSReadinessRequestPayload(
            preferredModelID: "voice-pack-kokoro"
        )

        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        )

        XCTAssertEqual(json["preferred_model_id"] as? String, "voice-pack-kokoro")
    }

    func testVoiceTTSRequestPayloadEncodesSnakeCaseKeys() throws {
        let payload = IPCVoiceTTSRequestPayload(
            preferredModelID: "voice-pack-kokoro",
            text: "project status normal",
            localeIdentifier: "en-US",
            voiceColor: "warm",
            speechRate: 1.1
        )

        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        )

        XCTAssertEqual(json["preferred_model_id"] as? String, "voice-pack-kokoro")
        XCTAssertEqual(json["text"] as? String, "project status normal")
        XCTAssertEqual(json["locale_identifier"] as? String, "en-US")
        XCTAssertEqual(json["voice_color"] as? String, "warm")
        XCTAssertEqual(try XCTUnwrap(json["speech_rate"] as? Double), 1.1, accuracy: 0.000_1)
    }

    func testVoiceTTSResponseDecodesSnakeCaseKeys() throws {
        let raw: [String: Any] = [
            "type": "voice_tts_synthesize_ack",
            "req_id": "req-voice-1",
            "ok": false,
            "id": "voice-pack-kokoro",
            "error": "text_to_speech_runtime_unavailable",
            "voice_tts": [
                "ok": false,
                "source": "local_runtime_command",
                "provider": "transformers",
                "model_id": "voice-pack-kokoro",
                "task_kind": "text_to_speech",
                "audio_file_path": "/tmp/voice.wav",
                "audio_format": "aiff",
                "voice_name": "Eddy (Chinese (China mainland))",
                "device_backend": "system_voice_compatibility",
                "fallback_mode": "system_voice_compatibility",
                "reason_code": "text_to_speech_runtime_unavailable",
                "runtime_reason_code": "text_to_speech_runtime_unavailable",
                "error": "task_not_implemented:transformers:text_to_speech",
                "detail": "runtime unavailable",
                "tts_audit": [
                    "schema_version": "xhub.local_tts_audit.v1",
                    "ok": false,
                    "task_kind": "text_to_speech",
                    "request_id": "",
                    "capability": "ai.audio.tts.local",
                    "provider": "transformers",
                    "requested_model_id": "voice-pack-kokoro",
                    "model_id": "voice-pack-kokoro",
                    "resolved_model_id": "voice-pack-kokoro",
                    "route_source": "local_runtime_command",
                    "source_kind": "failed",
                    "output_ref_kind": "audio_path",
                    "engine_name": "kokoro",
                    "speaker_id": "bf_emma",
                    "native_tts_used": false,
                    "fallback_used": true,
                    "fallback_mode": "system_voice_compatibility",
                    "fallback_reason_code": "native_dependency_error",
                    "deny_code": "",
                    "raw_deny_code": "",
                    "locale": "en-US",
                    "voice_color": "warm",
                    "speech_rate": 1.1
                ],
                "tts_audit_line": "tts_audit status=failed provider=transformers model=voice-pack-kokoro source=failed route=local_runtime_command output=audio_path fallback=native_dependency_error deny=none",
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: raw, options: [])
        let response = try JSONDecoder().decode(IPCResponse.self, from: data)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.type, "voice_tts_synthesize_ack")
        XCTAssertEqual(response.reqId, "req-voice-1")
        XCTAssertEqual(response.id, "voice-pack-kokoro")
        XCTAssertEqual(response.voiceTTS?.provider, "transformers")
        XCTAssertEqual(response.voiceTTS?.modelID, "voice-pack-kokoro")
        XCTAssertEqual(response.voiceTTS?.taskKind, "text_to_speech")
        XCTAssertEqual(response.voiceTTS?.audioFilePath, "/tmp/voice.wav")
        XCTAssertEqual(response.voiceTTS?.audioFormat, "aiff")
        XCTAssertEqual(response.voiceTTS?.voiceName, "Eddy (Chinese (China mainland))")
        XCTAssertEqual(response.voiceTTS?.deviceBackend, "system_voice_compatibility")
        XCTAssertEqual(response.voiceTTS?.fallbackMode, "system_voice_compatibility")
        XCTAssertEqual(response.voiceTTS?.reasonCode, "text_to_speech_runtime_unavailable")
        XCTAssertEqual(response.voiceTTS?.runtimeReasonCode, "text_to_speech_runtime_unavailable")
        XCTAssertEqual(response.voiceTTS?.error, "task_not_implemented:transformers:text_to_speech")
        XCTAssertEqual(response.voiceTTS?.detail, "runtime unavailable")
        XCTAssertEqual(response.voiceTTS?.ttsAudit?.schemaVersion, "xhub.local_tts_audit.v1")
        XCTAssertEqual(response.voiceTTS?.ttsAudit?.capability, "ai.audio.tts.local")
        XCTAssertEqual(response.voiceTTS?.ttsAudit?.requestedModelID, "voice-pack-kokoro")
        XCTAssertEqual(response.voiceTTS?.ttsAudit?.sourceKind, "failed")
        XCTAssertEqual(response.voiceTTS?.ttsAudit?.outputRefKind, "audio_path")
        XCTAssertEqual(response.voiceTTS?.ttsAudit?.fallbackReasonCode, "native_dependency_error")
        XCTAssertEqual(response.voiceTTS?.ttsAuditLine, "tts_audit status=failed provider=transformers model=voice-pack-kokoro source=failed route=local_runtime_command output=audio_path fallback=native_dependency_error deny=none")
    }

    func testVoiceTTSReadinessResponseDecodesSnakeCaseKeys() throws {
        let raw: [String: Any] = [
            "type": "voice_tts_readiness_ack",
            "req_id": "req-voice-ready-1",
            "ok": false,
            "id": "voice-pack-kokoro",
            "error": "voice_tts_runtime_launch_config_unavailable",
            "voice_tts_readiness": [
                "ok": false,
                "source": "hub_ipc",
                "provider": "transformers",
                "model_id": "voice-pack-kokoro",
                "reason_code": "voice_tts_runtime_launch_config_unavailable",
                "detail": "local runtime command launch configuration is unavailable",
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: raw, options: [])
        let response = try JSONDecoder().decode(IPCResponse.self, from: data)

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.type, "voice_tts_readiness_ack")
        XCTAssertEqual(response.reqId, "req-voice-ready-1")
        XCTAssertEqual(response.id, "voice-pack-kokoro")
        XCTAssertEqual(response.voiceTTSReadiness?.provider, "transformers")
        XCTAssertEqual(response.voiceTTSReadiness?.modelID, "voice-pack-kokoro")
        XCTAssertEqual(response.voiceTTSReadiness?.reasonCode, "voice_tts_runtime_launch_config_unavailable")
        XCTAssertEqual(response.voiceTTSReadiness?.detail, "local runtime command launch configuration is unavailable")
    }
}
