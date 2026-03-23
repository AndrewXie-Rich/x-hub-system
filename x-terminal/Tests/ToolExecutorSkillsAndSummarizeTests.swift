import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct ToolExecutorSkillsAndSummarizeTests {

    @Test
    func skillsSearchFallsBackToLocalHubIndex() async throws {
        let fixture = ToolExecutorProjectFixture(name: "skills-search-local-index")
        defer { fixture.cleanup() }

        let hubBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-hub-skills-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: hubBase) }
        try writeLocalHubSkillsIndex(baseDir: hubBase)

        HubPaths.setPinnedBaseDirOverride(hubBase)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .skills_search,
                args: [
                    "query": .string("summarize"),
                    "source_filter": .string("builtin:catalog"),
                    "limit": .number(5),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["tool"]) == ToolName.skills_search.rawValue)
        #expect(jsonString(summary["source"]) == "local_hub_index")
        #expect((jsonNumber(summary["results_count"]) ?? 0) >= 1)
        let first = try #require(
            jsonArray(summary["results"])?.first(where: { row in
                jsonString(jsonObject(row)?["skill_id"]) == "summarize"
            })
        )
        #expect(jsonString(jsonObject(first)?["risk_level"]) == "medium")
        #expect(jsonBool(jsonObject(first)?["requires_grant"]) == false)
        #expect(jsonString(jsonObject(first)?["side_effect_class"]) == "read_only")
        #expect(toolBody(result.output).contains("Summarize [summarize]"))
        #expect(toolBody(result.output).contains("risk=medium grant=no side_effect=read_only"))
    }

    @Test
    func agentImportRecordReturnsStructuredHubReview() async throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-import-record-review")
        defer { fixture.cleanup() }

        HubIPCClient.installAgentImportRecordOverrideForTesting { lookup in
            #expect(lookup.stagingId == "stage-123")
            #expect(lookup.selector == nil)
            #expect(lookup.skillId == nil)
            #expect(lookup.projectId == nil)
            return HubIPCClient.AgentImportRecordResult(
                ok: true,
                source: "hub_runtime_grpc",
                selector: nil,
                stagingId: lookup.stagingId,
                status: "staged_with_warnings",
                auditRef: "audit-stage-123",
                schemaVersion: "xhub.agent_import_record.v1",
                skillId: "agent-browser",
                projectId: nil,
                recordJSON: #"""
                {
                  "staging_id": "stage-123",
                  "status": "staged_with_warnings",
                  "audit_ref": "audit-stage-123",
                  "requested_by": "xt-ui",
                  "note": "ui_import:agent-browser",
                  "vetter_status": "warn_only",
                  "vetter_critical_count": 0,
                  "vetter_warn_count": 2,
                  "vetter_audit_ref": "vet-audit-123",
                  "vetter_report_ref": "skills_store/agent_imports/reports/stage-123.json",
                  "promotion_blocked_reason": "",
                  "findings": [
                    { "code": "warn-dynamic", "detail": "dynamic dispatch requires review" }
                  ],
                  "import_manifest": {
                    "skill_id": "agent-browser",
                    "display_name": "Agent Browser",
                    "preflight_status": "passed",
                    "risk_level": "high",
                    "policy_scope": "project",
                    "requires_grant": true,
                    "normalized_capabilities": ["browser.read", "browser.write"]
                  }
                }
                """#,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetAgentImportRecordOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .agentImportRecord,
                args: [
                    "staging_id": .string("stage-123"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["tool"]) == ToolName.agentImportRecord.rawValue)
        #expect(jsonString(summary["source"]) == "hub_runtime_grpc")
        #expect(jsonString(summary["staging_id"]) == "stage-123")
        #expect(jsonString(summary["skill_id"]) == "agent-browser")
        #expect(jsonString(summary["vetter_status"]) == "warn_only")
        #expect(jsonNumber(summary["vetter_warn_count"]) == 2)
        #expect(jsonString(summary["vetter_report_ref"]) == "skills_store/agent_imports/reports/stage-123.json")

        let body = toolBody(result.output)
        #expect(body.contains("vetter: warn_only"))
        #expect(body.contains("vetter_report_ref: skills_store/agent_imports/reports/stage-123.json"))
        #expect(body.contains("findings (1):"))
    }

    @Test
    func agentImportRecordDefaultsToLatestProjectSelector() async throws {
        let fixture = ToolExecutorProjectFixture(name: "agent-import-record-selector")
        defer { fixture.cleanup() }

        let projectID = AXProjectRegistryStore.projectId(forRoot: fixture.root)
        #expect(!projectID.isEmpty)

        HubIPCClient.installAgentImportRecordOverrideForTesting { lookup in
            #expect(lookup.stagingId == nil)
            #expect(lookup.selector == "latest_for_project")
            #expect(lookup.skillId == nil)
            #expect(lookup.projectId == projectID)
            return HubIPCClient.AgentImportRecordResult(
                ok: true,
                source: "hub_runtime_grpc",
                selector: lookup.selector,
                stagingId: "stage-latest-project",
                status: "staged",
                auditRef: "audit-stage-latest-project",
                schemaVersion: "xhub.agent_import_record.v1",
                skillId: "summarize",
                projectId: lookup.projectId,
                recordJSON: """
                {
                  "staging_id": "stage-latest-project",
                  "status": "staged",
                  "audit_ref": "audit-stage-latest-project",
                  "project_id": "\(projectID)",
                  "vetter_status": "passed",
                  "vetter_critical_count": 0,
                  "vetter_warn_count": 0,
                  "import_manifest": {
                    "skill_id": "summarize",
                    "display_name": "Summarize",
                    "preflight_status": "passed",
                    "risk_level": "low",
                    "policy_scope": "project",
                    "requires_grant": false,
                    "normalized_capabilities": ["document.summarize"]
                  }
                }
                """,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetAgentImportRecordOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .agentImportRecord,
                args: [:]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["selector"]) == "latest_for_project")
        #expect(jsonString(summary["project_id"]) == projectID)
        #expect(jsonString(summary["skill_id"]) == "summarize")
        #expect(jsonString(summary["staging_id"]) == "stage-latest-project")
    }

    @Test
    func supervisorVoicePlaybackDefaultsToStatusAndReturnsStructuredSummary() async throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-voice-status")
        defer { fixture.cleanup() }

        await MainActor.run {
            SupervisorManager.shared.installSupervisorVoiceSkillActionOverrideForTesting { action, text in
                #expect(action == "status")
                #expect(text == nil)
                return makeSupervisorVoiceSkillResult(
                    action: action,
                    ok: true,
                    reasonCode: "status_ready",
                    detail: "",
                    resolvedSource: .systemSpeech,
                    activityState: .idle,
                    actualSource: nil
                )
            }
        }
        defer {
            Task { @MainActor in
                SupervisorManager.shared.resetSupervisorVoiceSkillActionOverrideForTesting()
            }
        }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .supervisorVoicePlayback,
                args: [:]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["tool"]) == ToolName.supervisorVoicePlayback.rawValue)
        #expect(jsonBool(summary["ok"]) == true)
        #expect(jsonString(summary["action"]) == "status")
        #expect(jsonString(summary["reason"]) == "status_ready")
        #expect(jsonString(summary["resolved_source"]) == VoicePlaybackSource.systemSpeech.rawValue)
        #expect(jsonString(summary["activity_state"]) == VoicePlaybackActivityState.idle.rawValue)
        #expect(jsonString(summary["actual_source"]) == nil)
        #expect(jsonString(summary["engine_name"]) == "macos_system_speech")
        #expect(jsonString(summary["speaker_id"]) == "")

        let body = toolBody(result.output)
        #expect(body.contains("Supervisor 语音状态已就绪。"))
        #expect(body.contains("实际输出：系统语音"))
        #expect(body.contains("原因：status_ready"))
    }

    @Test
    func supervisorVoicePlaybackTreatsInlineTextAsSpeak() async throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-voice-speak")
        defer { fixture.cleanup() }

        await MainActor.run {
            SupervisorManager.shared.installSupervisorVoiceSkillActionOverrideForTesting { action, text in
                #expect(action == "speak")
                #expect(text == "Ship the checkpoint update.")
                return makeSupervisorVoiceSkillResult(
                    action: action,
                    ok: true,
                    reasonCode: "playback_completed",
                    detail: "Played through the preferred Hub voice pack.",
                    resolvedSource: .hubVoicePack,
                    resolvedHubVoicePackID: "voice-pack-supervisor",
                    activityState: .played,
                    actualSource: .hubVoicePack
                )
            }
        }
        defer {
            Task { @MainActor in
                SupervisorManager.shared.resetSupervisorVoiceSkillActionOverrideForTesting()
            }
        }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .supervisorVoicePlayback,
                args: [
                    "text": .string("Ship the checkpoint update."),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["action"]) == "speak")
        #expect(jsonString(summary["reason"]) == "playback_completed")
        #expect(jsonString(summary["resolved_source"]) == VoicePlaybackSource.hubVoicePack.rawValue)
        #expect(jsonString(summary["resolved_hub_voice_pack_id"]) == "voice-pack-supervisor")
        #expect(jsonNumber(summary["input_chars"]) == 27)
        #expect(jsonString(summary["voice_name"]) == "Supervisor Voice")
        #expect(jsonString(summary["engine_name"]) == "kokoro")
        #expect(jsonString(summary["speaker_id"]) == "zh_warm_f1")
        #expect(jsonBool(summary["native_tts_used"]) == true)
        #expect(jsonString(summary["fallback_reason_code"]) == "")

        let body = toolBody(result.output)
        #expect(body.contains("Supervisor 语音播放已完成。"))
        #expect(body.contains("文本：Ship the checkpoint update."))
        #expect(body.contains("实际语音包：voice-pack-supervisor"))
        #expect(body.contains("原因：playback_completed"))
        #expect(body.contains("引擎：kokoro"))
        #expect(body.contains("说话人：zh_warm_f1"))
        #expect(body.contains("执行模式：原生 TTS"))
    }

    @Test
    func supervisorVoicePlaybackValidatesSpeakPayload() async throws {
        let fixture = ToolExecutorProjectFixture(name: "supervisor-voice-validate")
        defer { fixture.cleanup() }

        let missingTextResult = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .supervisorVoicePlayback,
                args: [
                    "action": .string("speak"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!missingTextResult.ok)
        let missingTextSummary = try #require(toolSummaryObject(missingTextResult.output))
        #expect(jsonString(missingTextSummary["reason"]) == "missing_text")

        let tooLongText = String(repeating: "a", count: 321)
        let longTextResult = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .supervisorVoicePlayback,
                args: [
                    "action": .string("speak"),
                    "text": .string(tooLongText),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!longTextResult.ok)
        let longTextSummary = try #require(toolSummaryObject(longTextResult.output))
        #expect(jsonString(longTextSummary["reason"]) == "text_too_long")
        #expect(jsonNumber(longTextSummary["input_chars"]) == 321)
    }

    @Test
    func summarizeProducesGovernedBulletSummaryFromInlineText() async throws {
        let fixture = ToolExecutorProjectFixture(name: "summarize-inline")
        defer { fixture.cleanup() }

        let text = """
        Incident report: browser runtime failed to load the secure page after a connector change.
        Impact: login automation was blocked for the release checklist.
        Risk: temporary fallback scripts might bypass the governed grant boundary and expose tokens.
        Action: require governed browser.read, rotate the temporary credentials, and rerun smoke evidence.
        """

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .summarize,
                args: [
                    "text": .string(text),
                    "focus": .string("risk"),
                    "format": .string("bullets"),
                    "max_chars": .number(420),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["tool"]) == ToolName.summarize.rawValue)
        #expect(jsonString(summary["source_kind"]) == "text")
        #expect(jsonString(summary["format"]) == "bullets")
        #expect(jsonBool(summary["source_truncated"]) == false)
        #expect((jsonNumber(summary["summary_chars"]) ?? 0) > 0)

        let body = toolBody(result.output)
        #expect(body.contains("Title: inline_text"))
        #expect(body.contains("Risk: temporary fallback scripts"))
        #expect(body.contains("- "))
    }

    @Test
    func summarizeReadsLocalProjectFile() async throws {
        let fixture = ToolExecutorProjectFixture(name: "summarize-path")
        defer { fixture.cleanup() }

        let fileURL = fixture.root.appendingPathComponent("NOTES.md")
        try """
        Release Notes

        The hub memory path is now the default source for supervisor recall.
        Operators can still choose a local overlay for sensitive experiments.
        The next milestone is wiring summarize and find-skills into governed runtime tools.
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .summarize,
                args: [
                    "path": .string("NOTES.md"),
                    "max_chars": .number(360),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["source_kind"]) == "path")
        #expect(jsonString(summary["source_title"]) == "NOTES.md")
        #expect(toolBody(result.output).contains("NOTES.md:"))
        #expect(toolBody(result.output).contains("hub memory path is now the default source for supervisor recall"))
    }

    private func writeLocalHubSkillsIndex(baseDir: URL) throws {
        let storeDir = baseDir.appendingPathComponent("skills_store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let index = #"""
        {
          "schema_version": "skills_store_index.v1",
          "updated_at_ms": 2468,
          "skills": [
            {
              "skill_id": "find-skills",
              "name": "Find Skills",
              "version": "1.1.0",
              "description": "Discover governed Agent skills from X-Hub.",
              "publisher_id": "xhub.official",
              "capabilities_required": ["skills.search"],
              "source_id": "builtin:catalog",
              "package_sha256": "1111111111111111111111111111111111111111111111111111111111111111",
              "install_hint": "Pin from the Agent Baseline.",
              "risk_level": "low",
              "requires_grant": false,
              "side_effect_class": "read_only"
            },
            {
              "skill_id": "summarize",
              "name": "Summarize",
              "version": "1.1.0",
              "description": "Summarize webpages, PDFs, and long documents through governed runtime tools.",
              "publisher_id": "xhub.official",
              "capabilities_required": ["document.summarize"],
              "source_id": "builtin:catalog",
              "package_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
              "install_hint": "Pin from the Agent Baseline.",
              "risk_level": "medium",
              "requires_grant": false,
              "side_effect_class": "read_only"
            }
          ]
        }
        """#
        try index.write(to: storeDir.appendingPathComponent("skills_store_index.json"), atomically: true, encoding: .utf8)
    }
}

private func makeSupervisorVoiceSkillResult(
    action: String,
    ok: Bool,
    reasonCode: String,
    detail: String,
    resolvedSource: VoicePlaybackSource,
    resolvedHubVoicePackID: String = "",
    activityState: VoicePlaybackActivityState,
    actualSource: VoicePlaybackSource?
) -> SupervisorManager.SupervisorVoiceSkillExecutionResult {
    let preferences = VoiceRuntimePreferences.default()
    let resolution = VoicePlaybackResolution(
        requestedPreference: preferences.playbackPreference,
        resolvedSource: resolvedSource,
        preferredHubVoicePackID: preferences.preferredHubVoicePackID,
        resolvedHubVoicePackID: resolvedHubVoicePackID,
        reasonCode: resolvedSource == .hubVoicePack ? "preferred_hub_voice_pack_ready" : "preferred_system_speech",
        fallbackFrom: nil
    )
    let activity = VoicePlaybackActivity(
        state: activityState,
        configuredResolution: resolution,
        actualSource: actualSource,
        reasonCode: reasonCode,
        detail: detail,
        provider: resolvedSource == .hubVoicePack ? "hub_voice" : "system_speech",
        modelID: resolvedSource == .hubVoicePack ? "voice-pack-supervisor" : "",
        engineName: resolvedSource == .hubVoicePack ? "kokoro" : "macos_system_speech",
        speakerId: resolvedSource == .hubVoicePack ? "zh_warm_f1" : "",
        deviceBackend: resolvedSource == .hubVoicePack ? "hub_voice_pack" : "macos_speech",
        nativeTTSUsed: resolvedSource == .hubVoicePack ? true : nil,
        fallbackMode: "",
        fallbackReasonCode: "",
        audioFormat: "pcm16",
        voiceName: "Supervisor Voice",
        updatedAt: 123.0
    )
    return SupervisorManager.SupervisorVoiceSkillExecutionResult(
        action: action,
        ok: ok,
        reasonCode: reasonCode,
        detail: detail,
        playbackPreference: preferences.playbackPreference.rawValue,
        persona: preferences.persona.rawValue,
        timbre: preferences.timbre.rawValue,
        speechRateMultiplier: Double(preferences.speechRateMultiplier),
        localeIdentifier: preferences.localeIdentifier,
        resolution: resolution,
        activity: activity
    )
}
