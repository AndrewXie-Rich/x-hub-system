import CryptoKit
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
    func skillsPinDefaultsToGlobalScopeAndReturnsStructuredSummary() async throws {
        let fixture = ToolExecutorProjectFixture(name: "skills-pin-global")
        defer { fixture.cleanup() }

        HubIPCClient.installSkillPinOverrideForTesting { request in
            #expect(request.scope == "global")
            #expect(request.skillId == "find-skills")
            #expect(request.packageSHA256 == "abcdef1234567890")
            #expect(request.projectId == nil)
            #expect(request.note == "supervisor-global")
            return HubIPCClient.SkillPinResult(
                ok: true,
                source: "hub_runtime_grpc",
                scope: request.scope,
                userId: "user-1",
                projectId: request.projectId ?? "",
                skillId: request.skillId,
                packageSHA256: request.packageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 1_710_000_000_000,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetSkillPinOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .skills_pin,
                args: [
                    "skill_id": .string("find-skills"),
                    "package_sha256": .string("ABCDEF1234567890"),
                    "note": .string("supervisor-global"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["tool"]) == ToolName.skills_pin.rawValue)
        #expect(jsonString(summary["source"]) == "hub_runtime_grpc")
        #expect(jsonString(summary["scope"]) == "global")
        #expect(jsonString(summary["skill_id"]) == "find-skills")
        #expect(jsonString(summary["package_sha256"]) == "abcdef1234567890")
        #expect(jsonNumber(summary["updated_at_ms"]) == 1_710_000_000_000)
        #expect(toolBody(result.output).contains("Hub 已通过审查并启用技能：find-skills@abcdef123456"))
    }

    @Test
    func skillsPinReturnsHumanReadableOfficialReviewBlockedBody() async throws {
        let fixture = ToolExecutorProjectFixture(name: "skills-pin-official-review-blocked")
        defer { fixture.cleanup() }

        HubIPCClient.installSkillPinOverrideForTesting { request in
            HubIPCClient.SkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: request.scope,
                userId: "user-1",
                projectId: request.projectId ?? "",
                skillId: request.skillId,
                packageSHA256: request.packageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "official_skill_review_blocked"
            )
        }
        defer { HubIPCClient.resetSkillPinOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .skills_pin,
                args: [
                    "skill_id": .string("find-skills"),
                    "package_sha256": .string("abcdef1234567890"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason"]) == "official_skill_review_blocked")
        #expect(toolBody(result.output).contains("Hub 已自动审查该官方技能包"))
    }

    @Test
    func genericSkillRunnerRoutesThroughHubGateAndExecutesPackageEntrypoint() async throws {
        let fixture = ToolExecutorProjectFixture(name: "generic-skill-runner-approved")
        defer { fixture.cleanup() }
        let package = try SkillRunnerPackageFixture(skillID: "echo-skill")
        defer { package.cleanup() }

        let projectID = AXProjectRegistryStore.projectId(forRoot: fixture.root)
        let registry = try skillRunnerRegistrySnapshot(
            projectID: projectID,
            projectName: "Generic Runner Project",
            skillID: "echo-skill",
            packageSHA256: package.packageSHA256
        )
        let routing = XTProjectSkillRouter.map(
            call: GovernedSkillCall(
                id: "generic-runner-approved-1",
                skill_id: "echo-skill",
                payload: ["input": .string("runner input")]
            ),
            projectId: projectID,
            projectName: "Generic Runner Project",
            registrySnapshot: registry,
            projectRoot: fixture.root,
            config: .default(forProjectRoot: fixture.root)
        )

        let mapped: XTProjectMappedSkillDispatch
        switch routing {
        case .success(let dispatch):
            mapped = dispatch
        case .failure(let failure):
            Issue.record("unexpected skill runner mapping failure: \(failure.reasonCode)")
            throw failure
        }

        #expect(mapped.toolCall.tool == .skillsExecuteRunner)
        #expect(mapped.toolCall.args["skill_id"]?.stringValue == "echo-skill")
        #expect(mapped.toolCall.args["package_sha256"]?.stringValue == package.packageSHA256)
        #expect(mapped.toolCall.args["input"]?.stringValue == "runner input")

        let gate = SkillRunnerGateCapture(mode: .approve)
        installSkillRunnerOverrides(package: package, gate: gate)
        defer { resetSkillRunnerOverrides() }

        let result = try await ToolExecutor.execute(call: mapped.toolCall, projectRoot: fixture.root)

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["tool"]) == ToolName.skillsExecuteRunner.rawValue)
        #expect(jsonString(summary["skill_id"]) == "echo-skill")
        #expect(jsonString(summary["package_sha256"]) == package.packageSHA256)
        #expect(jsonString(summary["hub_gate_tool_name"]) == ToolName.skillsExecuteRunner.rawValue)
        #expect(jsonNumber(summary["exit_code"]) == 0)
        #expect(toolBody(result.output).contains("XT generic runner package executed"))

        let gateRequest = try #require(await gate.lastRequest())
        #expect(gateRequest.projectId == projectID)
        #expect(gateRequest.skillId == "echo-skill")
        #expect(gateRequest.packageSHA256 == package.packageSHA256)
        #expect(gateRequest.toolName == ToolName.skillsExecuteRunner.rawValue)
        #expect(gateRequest.execArgv == [
            "xt-skill-runner",
            "--skill-id",
            "echo-skill",
            "--package-sha256",
            package.packageSHA256,
        ])
        #expect(gateRequest.toolArgsHash.count == 64)
    }

    @Test
    func genericSkillRunnerIgnoresCallerSuppliedHubToolNameOverride() async throws {
        let fixture = ToolExecutorProjectFixture(name: "generic-skill-runner-canonical-tool")
        defer { fixture.cleanup() }
        let package = try SkillRunnerPackageFixture(skillID: "canonical-tool-skill")
        defer { package.cleanup() }

        let gate = SkillRunnerGateCapture(mode: .approve)
        installSkillRunnerOverrides(package: package, gate: gate)
        defer { resetSkillRunnerOverrides() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                id: "generic-runner-canonical-tool-1",
                tool: .skillsExecuteRunner,
                args: [
                    "skill_id": .string("canonical-tool-skill"),
                    "package_sha256": .string(package.packageSHA256),
                    "hub_tool_name": .string("process.start"),
                    "input": .string("runner input")
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["hub_gate_tool_name"]) == ToolName.skillsExecuteRunner.rawValue)
        let gateRequest = try #require(await gate.lastRequest())
        #expect(gateRequest.toolName == ToolName.skillsExecuteRunner.rawValue)
    }

    @Test
    func genericSkillRunnerFailsClosedWhenHubGateDenies() async throws {
        let fixture = ToolExecutorProjectFixture(name: "generic-skill-runner-denied")
        defer { fixture.cleanup() }
        let package = try SkillRunnerPackageFixture(skillID: "echo-skill")
        defer { package.cleanup() }

        let gate = SkillRunnerGateCapture(mode: .deny("revoked"))
        installSkillRunnerOverrides(package: package, gate: gate)
        defer { resetSkillRunnerOverrides() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                id: "generic-runner-denied-1",
                tool: .skillsExecuteRunner,
                args: [
                    "skill_id": .string("echo-skill"),
                    "package_sha256": .string(package.packageSHA256),
                    "input": .string("runner input")
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason"]) == "revoked")
        #expect(jsonString(summary["hub_tool_name"]) == ToolName.skillsExecuteRunner.rawValue)
        #expect(jsonString(summary["decision"]) == "deny")
        #expect(toolBody(result.output) == "revoked")
        #expect(!toolBody(result.output).contains("XT generic runner package executed"))
        #expect(await gate.requestCount() == 1)
    }

    @Test
    func genericSkillRunnerExecutesRealOfficialFindSkillsPackageArtifact() async throws {
        let fixture = ToolExecutorProjectFixture(name: "generic-skill-runner-official-find-skills")
        defer { fixture.cleanup() }
        let package = try OfficialSkillPackageFixture(skillID: "find-skills")

        let gate = SkillRunnerGateCapture(mode: .approve)
        installSkillRunnerOverrides(package: package, gate: gate)
        defer { resetSkillRunnerOverrides() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                id: "generic-runner-official-find-skills-1",
                tool: .skillsExecuteRunner,
                args: [
                    "skill_id": .string("find-skills"),
                    "package_sha256": .string(package.packageSHA256),
                    "input": .object(["query": .string("browser automation")])
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["skill_id"]) == "find-skills")
        #expect(jsonString(summary["package_sha256"]) == package.packageSHA256)
        #expect(jsonString(summary["entrypoint_command"]) == "cat")
        #expect(toolBody(result.output).contains("# Find Skills"))
        let gateRequest = try #require(await gate.lastRequest())
        #expect(gateRequest.execArgv == [
            "xt-skill-runner",
            "--skill-id",
            "find-skills",
            "--package-sha256",
            package.packageSHA256,
        ])
    }

    @Test
    func genericSkillRunnerPassesInputJSONToEntrypointStdin() async throws {
        let fixture = ToolExecutorProjectFixture(name: "generic-skill-runner-stdin")
        defer { fixture.cleanup() }
        let package = try SkillRunnerPackageFixture(skillID: "stdin-skill", stdinEntrypoint: true)
        defer { package.cleanup() }

        let gate = SkillRunnerGateCapture(mode: .approve)
        installSkillRunnerOverrides(package: package, gate: gate)
        defer { resetSkillRunnerOverrides() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                id: "generic-runner-stdin-1",
                tool: .skillsExecuteRunner,
                args: [
                    "skill_id": .string("stdin-skill"),
                    "package_sha256": .string(package.packageSHA256),
                    "payload": .object(["message": .string("stdin runner input")])
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        #expect(toolBody(result.output).contains(#""message":"stdin runner input""#))
    }

    @Test
    func genericSkillRunnerFailsClosedWhenInputExceedsBoundedContract() async throws {
        let fixture = ToolExecutorProjectFixture(name: "generic-skill-runner-large-input")
        defer { fixture.cleanup() }
        let package = try SkillRunnerPackageFixture(skillID: "large-input-skill", stdinEntrypoint: true)
        defer { package.cleanup() }

        let gate = SkillRunnerGateCapture(mode: .approve)
        installSkillRunnerOverrides(package: package, gate: gate)
        defer { resetSkillRunnerOverrides() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                id: "generic-runner-large-input-1",
                tool: .skillsExecuteRunner,
                args: [
                    "skill_id": .string("large-input-skill"),
                    "package_sha256": .string(package.packageSHA256),
                    "input": .string(String(repeating: "x", count: 70 * 1024))
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason"]) == "skill_runner_input_too_large")
        #expect(await gate.requestCount() == 0)
    }

    @Test
    func genericSkillRunnerTruncatesOversizedEntrypointOutput() async throws {
        let fixture = ToolExecutorProjectFixture(name: "generic-skill-runner-large-output")
        defer { fixture.cleanup() }
        let package = try SkillRunnerPackageFixture(
            skillID: "large-output-skill",
            skillText: String(repeating: "x", count: 600 * 1024)
        )
        defer { package.cleanup() }

        let gate = SkillRunnerGateCapture(mode: .approve)
        installSkillRunnerOverrides(package: package, gate: gate)
        defer { resetSkillRunnerOverrides() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                id: "generic-runner-large-output-1",
                tool: .skillsExecuteRunner,
                args: [
                    "skill_id": .string("large-output-skill"),
                    "package_sha256": .string(package.packageSHA256)
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonBool(summary["output_truncated"]) == true)
        #expect(toolBody(result.output).contains("[output truncated at"))
    }

    @Test
    func genericSkillRunnerDoesNotInheritHostEnvironment() async throws {
        let fixture = ToolExecutorProjectFixture(name: "generic-skill-runner-minimal-env")
        defer { fixture.cleanup() }
        let package = try SkillRunnerPackageFixture(
            skillID: "minimal-env-skill",
            command: "env",
            args: []
        )
        defer { package.cleanup() }

        let gate = SkillRunnerGateCapture(mode: .approve)
        installSkillRunnerOverrides(package: package, gate: gate)
        defer { resetSkillRunnerOverrides() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                id: "generic-runner-minimal-env-1",
                tool: .skillsExecuteRunner,
                args: [
                    "skill_id": .string("minimal-env-skill"),
                    "package_sha256": .string(package.packageSHA256)
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let body = toolBody(result.output)
        #expect(body.contains("XHUB_SKILL_ID=minimal-env-skill"))
        #expect(!body.contains("HOME="))
        #expect(!body.contains("HUB_CLIENT_TOKEN="))
    }

    @Test
    func genericSkillRunnerRejectsNodeEntrypointOutsidePackageRootBeforeGate() async throws {
        let fixture = ToolExecutorProjectFixture(name: "generic-skill-runner-node-escape")
        defer { fixture.cleanup() }
        let package = try SkillRunnerPackageFixture(
            skillID: "node-escape-skill",
            runtime: "node",
            command: "/tmp/outside-package.js",
            args: []
        )
        defer { package.cleanup() }

        let gate = SkillRunnerGateCapture(mode: .approve)
        installSkillRunnerOverrides(package: package, gate: gate)
        defer { resetSkillRunnerOverrides() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                id: "generic-runner-node-escape-1",
                tool: .skillsExecuteRunner,
                args: [
                    "skill_id": .string("node-escape-skill"),
                    "package_sha256": .string(package.packageSHA256)
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason"]) == "invalid_entrypoint")
        #expect(await gate.requestCount() == 0)
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
    func runLocalTaskExecutesEmbeddingViaHubAndReturnsStructuredSummary() async throws {
        let fixture = ToolExecutorProjectFixture(name: "run-local-task-embedding")
        defer { fixture.cleanup() }

        HubIPCClient.installLocalTaskExecutionOverrideForTesting { payload, timeoutSec in
            #expect(payload.taskKind == "embedding")
            #expect(payload.modelId == "qwen3-embed-4b")
            #expect(payload.parameters["text"]?.stringValue == "hello governed embeddings")
            #expect(timeoutSec == 15.0)
            return HubIPCClient.LocalTaskResult(
                ok: true,
                source: "local_ipc",
                runtimeSource: "local_runtime_command",
                provider: "mlx",
                modelId: payload.modelId,
                taskKind: payload.taskKind,
                reasonCode: "embedding_completed",
                payload: [
                    "vector_count": .number(1),
                    "dims": .number(1024),
                ]
            )
        }
        defer { HubIPCClient.resetLocalTaskExecutionOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .run_local_task,
                args: [
                    "task_kind": .string("embedding"),
                    "model_id": .string("qwen3-embed-4b"),
                    "text": .string("hello governed embeddings"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["tool"]) == ToolName.run_local_task.rawValue)
        #expect(jsonString(summary["task_kind"]) == "embedding")
        #expect(jsonString(summary["model_id"]) == "qwen3-embed-4b")
        #expect(jsonString(summary["provider"]) == "mlx")
        #expect(jsonString(summary["runtime_source"]) == "local_runtime_command")
        #expect(jsonNumber(summary["vector_count"]) == 1)
        #expect(jsonNumber(summary["dims"]) == 1024)
        #expect(jsonNumber(summary["timeout_sec"]) == 15.0)
        #expect(jsonArray(summary["parameter_keys"])?.compactMap(jsonString) == ["text"])
        #expect(toolBody(result.output).contains("本地模型任务已完成"))
        #expect(toolBody(result.output).contains("vector_count=1 dims=1024"))
    }

    @Test
    func runLocalTaskExecutesOCRViaHubAndReturnsTextBody() async throws {
        let fixture = ToolExecutorProjectFixture(name: "run-local-task-ocr")
        defer { fixture.cleanup() }

        HubIPCClient.installLocalTaskExecutionOverrideForTesting { payload, timeoutSec in
            #expect(payload.taskKind == "ocr")
            #expect(payload.modelId == "qwen2-vl-ocr")
            #expect(payload.parameters["image_path"]?.stringValue == "/tmp/invoice.png")
            #expect(timeoutSec == 45.0)
            return HubIPCClient.LocalTaskResult(
                ok: true,
                source: "local_ipc",
                runtimeSource: "local_runtime_command",
                provider: "transformers",
                modelId: payload.modelId,
                taskKind: payload.taskKind,
                reasonCode: "ocr_completed",
                payload: [
                    "text": .string("Invoice total: 128.50 USD"),
                    "route_trace": .object([
                        "execution_path": .string("mlx_vlm")
                    ]),
                ]
            )
        }
        defer { HubIPCClient.resetLocalTaskExecutionOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .run_local_task,
                args: [
                    "task_kind": .string("ocr"),
                    "model": .string("qwen2-vl-ocr"),
                    "image_path": .string("/tmp/invoice.png"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["task_kind"]) == "ocr")
        #expect(jsonString(summary["model_id"]) == "qwen2-vl-ocr")
        #expect(jsonString(summary["provider"]) == "transformers")
        #expect(jsonString(summary["execution_path"]) == "mlx_vlm")
        #expect(jsonNumber(summary["text_chars"]) == 25)
        #expect(toolBody(result.output).contains("Invoice total: 128.50 USD"))
    }

    @Test
    func runLocalTaskAutoBindsTaskCompatibleLocalModelWhenModelIDsAreOmitted() async throws {
        let fixture = ToolExecutorProjectFixture(name: "run-local-task-auto-bind")
        defer { fixture.cleanup() }

        let hubBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-hub-local-task-auto-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: hubBase) }
        try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
        try writeLocalTaskModelState(
            baseDir: hubBase,
            models: [
                makeLocalTaskModel(
                    id: "nomic-embed-text-v1",
                    backend: "transformers",
                    taskKinds: ["embedding"],
                    state: .available,
                    modelPath: "/models/nomic-embed-text-v1",
                    offlineReady: true
                )
            ]
        )

        HubPaths.setPinnedBaseDirOverride(hubBase)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        HubIPCClient.installLocalTaskExecutionOverrideForTesting { payload, timeoutSec in
            #expect(payload.taskKind == "embedding")
            #expect(payload.modelId == "nomic-embed-text-v1")
            #expect(payload.parameters["text"]?.stringValue == "bind the best local embedder")
            #expect(timeoutSec == 15.0)
            return HubIPCClient.LocalTaskResult(
                ok: true,
                source: "local_ipc",
                runtimeSource: "local_runtime_command",
                provider: "transformers",
                modelId: payload.modelId,
                taskKind: payload.taskKind,
                reasonCode: "embedding_completed",
                payload: [
                    "vector_count": .number(1),
                    "dims": .number(768),
                ]
            )
        }
        defer { HubIPCClient.resetLocalTaskExecutionOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .run_local_task,
                args: [
                    "task_kind": .string("embedding"),
                    "text": .string("bind the best local embedder"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["model_id"]) == "nomic-embed-text-v1")
        #expect(summary["requested_model_id"] == .null)
        #expect(summary["preferred_model_id"] == .null)
        #expect(jsonString(summary["model_resolution"]) == "task_kind_auto")
    }

    @Test
    func runLocalTaskAutoBindsSpeechToTextModelFromHubStateTruthWhenModelIDsAreOmitted() async throws {
        let fixture = ToolExecutorProjectFixture(name: "run-local-task-auto-bind-stt")
        defer { fixture.cleanup() }

        let hubBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-hub-local-task-stt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: hubBase) }
        try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
        try writeLocalTaskModelState(
            baseDir: hubBase,
            models: [
                makeLocalTaskModel(
                    id: "hf-whisper-tiny",
                    backend: "transformers",
                    taskKinds: ["speech_to_text"],
                    state: .available,
                    modelPath: "/models/hf-whisper-tiny",
                    offlineReady: true,
                    inputModalities: ["audio"],
                    outputModalities: ["text", "segments"]
                )
            ]
        )

        HubPaths.setPinnedBaseDirOverride(hubBase)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        HubIPCClient.installLocalTaskExecutionOverrideForTesting { payload, timeoutSec in
            #expect(payload.taskKind == "speech_to_text")
            #expect(payload.modelId == "hf-whisper-tiny")
            #expect(payload.parameters["audio_path"]?.stringValue == "/tmp/demo.wav")
            #expect(timeoutSec == 45.0)
            return HubIPCClient.LocalTaskResult(
                ok: true,
                source: "local_ipc",
                runtimeSource: "local_runtime_command",
                provider: "transformers",
                modelId: payload.modelId,
                taskKind: payload.taskKind,
                reasonCode: "transcription_completed",
                payload: [
                    "text": .string("hello from whisper tiny"),
                ]
            )
        }
        defer { HubIPCClient.resetLocalTaskExecutionOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .run_local_task,
                args: [
                    "task_kind": .string("speech_to_text"),
                    "audio_path": .string("/tmp/demo.wav"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["task_kind"]) == "speech_to_text")
        #expect(jsonString(summary["model_id"]) == "hf-whisper-tiny")
        #expect(summary["requested_model_id"] == .null)
        #expect(summary["preferred_model_id"] == .null)
        #expect(jsonString(summary["model_resolution"]) == "task_kind_auto")
        #expect(jsonString(summary["provider"]) == "transformers")
        #expect(jsonString(summary["runtime_source"]) == "local_runtime_command")
        #expect(jsonNumber(summary["timeout_sec"]) == 45.0)
        #expect(toolBody(result.output).contains("hello from whisper tiny"))
    }

    @Test
    func runLocalTaskFallsBackFromBrokenPreferredModelToRunnableTaskCandidate() async throws {
        let fixture = ToolExecutorProjectFixture(name: "run-local-task-preferred-fallback")
        defer { fixture.cleanup() }

        let hubBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-hub-local-task-preferred-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: hubBase) }
        try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
        try writeLocalTaskModelState(
            baseDir: hubBase,
            models: [
                makeLocalTaskModel(
                    id: "qwen-ocr-broken",
                    backend: "mlx",
                    taskKinds: ["ocr"],
                    state: .available,
                    modelPath: "/models/qwen-ocr-broken",
                    offlineReady: false
                ),
                makeLocalTaskModel(
                    id: "qwen-ocr-ready",
                    backend: "mlx",
                    taskKinds: ["ocr"],
                    state: .loaded,
                    modelPath: "/models/qwen-ocr-ready",
                    offlineReady: true
                ),
            ]
        )

        HubPaths.setPinnedBaseDirOverride(hubBase)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        HubIPCClient.installLocalTaskExecutionOverrideForTesting { payload, timeoutSec in
            #expect(payload.taskKind == "ocr")
            #expect(payload.modelId == "qwen-ocr-ready")
            #expect(payload.parameters["image_path"]?.stringValue == "/tmp/invoice.png")
            #expect(timeoutSec == 45.0)
            return HubIPCClient.LocalTaskResult(
                ok: true,
                source: "local_ipc",
                runtimeSource: "local_runtime_command",
                provider: "mlx",
                modelId: payload.modelId,
                taskKind: payload.taskKind,
                reasonCode: "ocr_completed",
                payload: [
                    "text": .string("fallback OCR text"),
                ]
            )
        }
        defer { HubIPCClient.resetLocalTaskExecutionOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .run_local_task,
                args: [
                    "task_kind": .string("ocr"),
                    "preferred_model_id": .string("qwen-ocr-broken"),
                    "image_path": .string("/tmp/invoice.png"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["model_id"]) == "qwen-ocr-ready")
        #expect(jsonString(summary["requested_model_id"]) == "qwen-ocr-broken")
        #expect(jsonString(summary["preferred_model_id"]) == "qwen-ocr-broken")
        #expect(jsonString(summary["model_resolution"]) == "preferred_model_fallback_task_kind")
    }

    @Test
    func runLocalTaskFailsClosedForUnsupportedTaskKind() async throws {
        let fixture = ToolExecutorProjectFixture(name: "run-local-task-unsupported")
        defer { fixture.cleanup() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .run_local_task,
                args: [
                    "task_kind": .string("image_generate"),
                    "model_id": .string("flux-1"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason"]) == "unsupported_task_kind")
        #expect(toolBody(result.output) == "unsupported_task_kind")
    }

    @Test
    func runLocalTaskFailsClosedForMissingModelID() async throws {
        let fixture = ToolExecutorProjectFixture(name: "run-local-task-missing-model")
        defer { fixture.cleanup() }

        let hubBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-hub-local-task-missing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: hubBase) }
        try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
        HubPaths.setPinnedBaseDirOverride(hubBase)
        defer { HubPaths.clearPinnedBaseDirOverride() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .run_local_task,
                args: [
                    "task_kind": .string("embedding"),
                    "text": .string("hello"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason"]) == "missing_model_id")
        #expect(jsonString(summary["task_kind"]) == "embedding")
        #expect(toolBody(result.output) == "missing_model_id")
    }

    @Test
    func runLocalTaskFailsClosedForMissingEmbeddingInput() async throws {
        let fixture = ToolExecutorProjectFixture(name: "run-local-task-missing-embedding-input")
        defer { fixture.cleanup() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .run_local_task,
                args: [
                    "task_kind": .string("embedding"),
                    "model_id": .string("qwen3-embed-4b"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason"]) == "missing_embedding_input")
        #expect(jsonString(summary["model_id"]) == "qwen3-embed-4b")
        #expect(toolBody(result.output) == "missing_embedding_input")
    }

    @Test
    func runLocalTaskFailsClosedForMissingAudioPath() async throws {
        let fixture = ToolExecutorProjectFixture(name: "run-local-task-missing-audio")
        defer { fixture.cleanup() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .run_local_task,
                args: [
                    "task_kind": .string("speech_to_text"),
                    "model_id": .string("whisper-large-v3"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason"]) == "missing_audio_path")
        #expect(toolBody(result.output) == "missing_audio_path")
    }

    @Test
    func runLocalTaskFailsClosedForMissingImageInput() async throws {
        let fixture = ToolExecutorProjectFixture(name: "run-local-task-missing-image")
        defer { fixture.cleanup() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .run_local_task,
                args: [
                    "task_kind": .string("vision_understand"),
                    "model_id": .string("qwen2-vl"),
                    "text": .string("describe the invoice"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason"]) == "missing_image_input")
        #expect(toolBody(result.output) == "missing_image_input")
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

private enum SkillRunnerGateMode {
    case approve
    case deny(String)
}

private actor SkillRunnerGateCapture {
    private let mode: SkillRunnerGateMode
    private var requests: [HubIPCClient.SkillRunnerGateRequestPayload] = []

    init(mode: SkillRunnerGateMode) {
        self.mode = mode
    }

    func evaluate(_ request: HubIPCClient.SkillRunnerGateRequestPayload) -> HubIPCClient.SkillRunnerGateResult {
        requests.append(request)
        switch mode {
        case .approve:
            return HubIPCClient.SkillRunnerGateResult(
                ok: true,
                source: "hub_runtime_grpc",
                skillId: request.skillId,
                packageSHA256: request.packageSHA256,
                toolName: request.toolName,
                decision: "approve",
                toolRequestId: "tool-request-1",
                grantId: "grant-1",
                executionId: "execution-1",
                denyCode: nil,
                resultJSON: #"{"ok":true}"#,
                executedAtMs: 1_710_000_000_001
            )
        case .deny(let code):
            return HubIPCClient.SkillRunnerGateResult(
                ok: false,
                source: "hub_runtime_grpc",
                skillId: request.skillId,
                packageSHA256: request.packageSHA256,
                toolName: request.toolName,
                decision: "deny",
                toolRequestId: "tool-request-1",
                grantId: "",
                executionId: "",
                denyCode: code,
                resultJSON: #"{"ok":false}"#,
                executedAtMs: 1_710_000_000_001
            )
        }
    }

    func lastRequest() -> HubIPCClient.SkillRunnerGateRequestPayload? {
        requests.last
    }

    func requestCount() -> Int {
        requests.count
    }
}

private struct SkillRunnerPackageFixture {
    let root: URL
    let packageData: Data
    let packageSHA256: String
    let manifestJSON: String

    init(
        skillID: String,
        skillText: String = "XT generic runner package executed\n",
        stdinEntrypoint: Bool = false,
        runtime: String = "text",
        command: String = "cat",
        args: [String]? = nil
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-skill-runner-package-\(UUID().uuidString)", isDirectory: true)
        let packageRoot = root.appendingPathComponent("package", isDirectory: true)
        let archiveURL = root.appendingPathComponent("skill.tgz")
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)

        let manifestJSON = Self.manifestJSON(
            skillID: skillID,
            stdinEntrypoint: stdinEntrypoint,
            runtime: runtime,
            command: command,
            args: args
        )
        try manifestJSON.write(
            to: packageRoot.appendingPathComponent("skill.json"),
            atomically: true,
            encoding: .utf8
        )
        try skillText.write(
            to: packageRoot.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let archive = try ProcessCapture.run(
            "/usr/bin/tar",
            ["-czf", archiveURL.path, "-C", packageRoot.path, "."],
            cwd: nil,
            timeoutSec: 20
        )
        guard archive.exitCode == 0 else {
            throw NSError(
                domain: "xterminal.tests.skill_runner",
                code: Int(archive.exitCode),
                userInfo: [NSLocalizedDescriptionKey: archive.combined]
            )
        }

        let packageData = try Data(contentsOf: archiveURL)
        self.root = root
        self.packageData = packageData
        self.packageSHA256 = skillRunnerTestSHA256Hex(packageData)
        self.manifestJSON = manifestJSON
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func manifestJSON(
        skillID: String,
        stdinEntrypoint: Bool,
        runtime: String,
        command: String,
        args: [String]?
    ) -> String {
        let resolvedArgs = args ?? (stdinEntrypoint ? [] : ["SKILL.md"])
        let argsData = (try? JSONEncoder().encode(resolvedArgs)) ?? Data("[]".utf8)
        let argsJSON = String(data: argsData, encoding: .utf8) ?? "[]"
        return #"""
        {
          "schema_version": "xhub.skill_manifest.v1",
          "skill_id": "\#(skillID)",
          "name": "Echo Skill",
          "version": "1.0.0",
          "description": "Fixture package for XT generic runner E2E.",
          "capabilities_required": ["repo.read"],
          "risk_level": "low",
          "requires_grant": false,
          "side_effect_class": "read_only",
          "entrypoint": {
            "runtime": "\#(runtime)",
            "command": "\#(command)",
            "args": \#(argsJSON)
          },
          "governed_dispatch": {
            "tool": "skills.execute.runner",
            "fixed_args": {},
            "passthrough_args": ["input", "payload", "timeout_sec"],
            "arg_aliases": {},
            "required_any": [],
            "exactly_one_of": []
          }
        }
        """#
    }
}

private struct OfficialSkillPackageFixture {
    let packageData: Data
    let packageSHA256: String
    let manifestJSON: String

    init(skillID: String) throws {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDir.deletingLastPathComponent().deletingLastPathComponent()
        let distRoot = repoRoot
            .appendingPathComponent("official-agent-skills", isDirectory: true)
            .appendingPathComponent("dist", isDirectory: true)
        let indexData = try Data(contentsOf: distRoot.appendingPathComponent("index.json"))
        guard let root = try JSONSerialization.jsonObject(with: indexData) as? [String: Any],
              let skills = root["skills"] as? [[String: Any]],
              let row = skills.first(where: { ($0["skill_id"] as? String) == skillID }),
              let packageSHA256 = row["package_sha256"] as? String,
              let packagePath = row["package_path"] as? String,
              let manifestPath = row["manifest_path"] as? String else {
            throw NSError(
                domain: "xterminal.tests.skill_runner",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "official skill artifact not found: \(skillID)"]
            )
        }

        let packageData = try Data(contentsOf: distRoot.appendingPathComponent(packagePath))
        let computedSHA256 = skillRunnerTestSHA256Hex(packageData)
        guard computedSHA256 == packageSHA256 else {
            throw NSError(
                domain: "xterminal.tests.skill_runner",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "official package hash mismatch: \(skillID)"]
            )
        }

        self.packageData = packageData
        self.packageSHA256 = packageSHA256
        self.manifestJSON = try String(
            contentsOf: distRoot.appendingPathComponent(manifestPath),
            encoding: .utf8
        )
    }
}

private func installSkillRunnerOverrides(
    package: SkillRunnerPackageFixture,
    gate: SkillRunnerGateCapture
) {
    installSkillRunnerOverrides(
        packageSHA256: package.packageSHA256,
        manifestJSON: package.manifestJSON,
        packageData: package.packageData,
        gate: gate
    )
}

private func installSkillRunnerOverrides(
    package: OfficialSkillPackageFixture,
    gate: SkillRunnerGateCapture
) {
    installSkillRunnerOverrides(
        packageSHA256: package.packageSHA256,
        manifestJSON: package.manifestJSON,
        packageData: package.packageData,
        gate: gate
    )
}

private func installSkillRunnerOverrides(
    packageSHA256 expectedPackageSHA256: String,
    manifestJSON: String,
    packageData: Data,
    gate: SkillRunnerGateCapture
) {
    HubIPCClient.installSkillManifestOverrideForTesting { packageSHA256 in
        #expect(packageSHA256 == expectedPackageSHA256)
        return HubIPCClient.SkillManifestResult(
            ok: true,
            source: "hub_runtime_grpc",
            packageSHA256: packageSHA256,
            manifestJSON: manifestJSON,
            reasonCode: nil
        )
    }
    HubIPCClient.installSkillPackageDownloadOverrideForTesting { packageSHA256 in
        #expect(packageSHA256 == expectedPackageSHA256)
        return HubIPCClient.SkillPackageDownloadResult(
            ok: true,
            source: "hub_runtime_grpc",
            packageSHA256: packageSHA256,
            data: packageData,
            reasonCode: nil
        )
    }
    HubIPCClient.installSkillRunnerGateOverrideForTesting { request in
        await gate.evaluate(request)
    }
}

private func resetSkillRunnerOverrides() {
    HubIPCClient.resetSkillManifestOverrideForTesting()
    HubIPCClient.resetSkillPackageDownloadOverrideForTesting()
    HubIPCClient.resetSkillRunnerGateOverrideForTesting()
}

private func skillRunnerRegistrySnapshot(
    projectID: String,
    projectName: String,
    skillID: String,
    packageSHA256: String
) throws -> SupervisorSkillRegistrySnapshot {
    let data = Data(
        #"""
        {
          "schema_version": "xt.supervisor_skill_registry_view.v1",
          "project_id": "\#(projectID)",
          "project_name": "\#(projectName)",
          "updated_at_ms": 1710000000000,
          "memory_source": "hub_runtime_grpc_resolved_skills_snapshot",
          "audit_ref": "audit-skill-runner-e2e",
          "items": [
            {
              "skill_id": "\#(skillID)",
              "display_name": "Echo Skill",
              "description": "Fixture package for XT generic runner E2E.",
              "intent_families": ["echo"],
              "capability_families": ["repo.read"],
              "capability_profiles": ["repo.read"],
              "grant_floor": "none",
              "approval_floor": "none",
              "package_sha256": "\#(packageSHA256)",
              "publisher_id": "xhub.official",
              "source_id": "builtin:catalog",
              "official_package": true,
              "capabilities_required": ["repo.read"],
              "governed_dispatch": {
                "tool": "skills.execute.runner",
                "fixed_args": {},
                "passthrough_args": ["input", "payload", "timeout_sec"],
                "arg_aliases": {},
                "required_any": [],
                "exactly_one_of": []
              },
              "input_schema_ref": "schema://echo-skill.input",
              "output_schema_ref": "schema://echo-skill.output",
              "side_effect_class": "read_only",
              "risk_level": "low",
              "requires_grant": false,
              "policy_scope": "project",
              "timeout_ms": 30000,
              "max_retries": 0,
              "available": true
            }
          ]
        }
        """#.utf8
    )
    return try JSONDecoder().decode(SupervisorSkillRegistrySnapshot.self, from: data)
}

private func skillRunnerTestSHA256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

private func writeLocalTaskModelState(
    baseDir: URL,
    models: [HubModel]
) throws {
    let snapshot = ModelStateSnapshot(
        models: models,
        updatedAt: Date().timeIntervalSince1970
    )
    let data = try JSONEncoder().encode(snapshot)
    try data.write(to: baseDir.appendingPathComponent("models_state.json"), options: .atomic)
}

private func makeLocalTaskModel(
    id: String,
    backend: String,
    taskKinds: [String],
    state: HubModelState,
    modelPath: String,
    offlineReady: Bool,
    inputModalities: [String] = [],
    outputModalities: [String] = []
) -> HubModel {
    HubModel(
        id: id,
        name: id,
        backend: backend,
        quant: "",
        contextLength: 16_384,
        paramsB: 0,
        roles: nil,
        state: state,
        memoryBytes: nil,
        tokensPerSec: nil,
        modelPath: modelPath,
        note: nil,
        taskKinds: taskKinds,
        inputModalities: inputModalities,
        outputModalities: outputModalities,
        offlineReady: offlineReady
    )
}
