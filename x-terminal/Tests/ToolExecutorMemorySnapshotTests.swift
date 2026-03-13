import Foundation
import Testing
@testable import XTerminal

struct ToolExecutorMemorySnapshotTests {

    @Test
    func renderMemorySnapshotOutputEmitsMachineReadableHeader() {
        let response = HubIPCClient.MemoryContextResponsePayload(
            text: "[MEMORY_V1]\n[L1_CANONICAL]\nKeep release scope frozen.\n[/L1_CANONICAL]\n[/MEMORY_V1]",
            source: "hub_remote_snapshot",
            resolvedMode: XTMemoryUseMode.projectChat.rawValue,
            freshness: "fresh_remote",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            budgetTotalTokens: 1600,
            usedTotalTokens: 120,
            layerUsage: [
                HubIPCClient.MemoryContextLayerUsage(layer: "l1_canonical", usedTokens: 60, budgetTokens: 400),
                HubIPCClient.MemoryContextLayerUsage(layer: "l3_working_set", usedTokens: 60, budgetTokens: 500),
            ],
            truncatedLayers: ["l4_raw_evidence"],
            redactedItems: 1,
            privateDrops: 2
        )

        let output = ToolExecutor.renderMemorySnapshotOutput(
            response: response,
            projectId: "project-memory",
            mode: "project"
        )

        let summary = toolSummaryObject(output)
        #expect(summary != nil)
        guard let summary else { return }

        #expect(jsonString(summary["tool"]) == ToolName.memory_snapshot.rawValue)
        #expect(jsonString(summary["project_id"]) == "project-memory")
        #expect(jsonString(summary["mode"]) == "project")
        #expect(jsonString(summary["source"]) == "hub_remote_snapshot")
        #expect(jsonString(summary["resolved_mode"]) == XTMemoryUseMode.projectChat.rawValue)
        #expect(jsonString(summary["freshness"]) == "fresh_remote")
        #expect(jsonBool(summary["cache_hit"]) == false)
        #expect(jsonNumber(summary["budget_total_tokens"]) == 1600)
        #expect(jsonNumber(summary["used_total_tokens"]) == 120)
        #expect(jsonNumber(summary["redacted_items"]) == 1)
        #expect(jsonNumber(summary["private_drops"]) == 2)
        #expect(jsonArray(summary["truncated_layers"])?.contains(where: { jsonString($0) == "l4_raw_evidence" }) == true)
        #expect(toolBody(output).contains("Keep release scope frozen."))
    }

    @Test
    func memorySnapshotRejectsUnknownMode() async throws {
        let fixture = ToolExecutorProjectFixture(name: "memory-snapshot-invalid-mode")
        defer { fixture.cleanup() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(tool: .memory_snapshot, args: ["mode": .string("not_a_real_mode")]),
            projectRoot: fixture.root
        )

        #expect(result.ok == false)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["deny_code"]) == XTMemoryUseDenyCode.memoryModeContractMissing.rawValue)
        #expect(jsonString(summary["reason"]) == XTMemoryUseDenyCode.memoryModeContractMissing.rawValue)
        #expect(toolBody(result.output) == XTMemoryUseDenyCode.memoryModeContractMissing.rawValue)
    }

    @Test
    func retrospectiveMemorySnapshotBuildsSelfImprovementReportFromLocalArtifacts() async throws {
        let fixture = ToolExecutorProjectFixture(name: "memory-snapshot-retrospective")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        var memory = AXMemory.new(projectName: "memory-snapshot-retrospective", projectRoot: fixture.root.path)
        memory.goal = "Ship governed browser automation without grant stalls."
        memory.nextSteps = ["Wire agent-browser extract grant preflight."]
        memory.risks = ["Supervisor can stall if web.fetch approval is requested too late."]
        try AXProjectStore.saveMemory(memory, for: ctx)

        let nowMs = Int64(1_773_600_000_000)
        let job = SupervisorJobRecord(
            schemaVersion: SupervisorJobRecord.currentSchemaVersion,
            jobId: "job-retro-001",
            projectId: AXProjectRegistryStore.projectId(forRoot: fixture.root),
            goal: "Stabilize grant reliability",
            priority: .high,
            status: .running,
            source: .supervisor,
            currentOwner: "supervisor",
            activePlanId: "plan-retro-001",
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            auditRef: "audit-job-retro-001"
        )
        try SupervisorProjectJobStore.append(job, for: ctx)

        let plan = SupervisorPlanRecord(
            schemaVersion: SupervisorPlanRecord.currentSchemaVersion,
            planId: "plan-retro-001",
            jobId: job.jobId,
            projectId: job.projectId,
            status: .blocked,
            currentOwner: "supervisor",
            steps: [
                SupervisorPlanStepRecord(
                    schemaVersion: SupervisorPlanStepRecord.currentSchemaVersion,
                    stepId: "step-retro-001",
                    title: "Resume browser extract after grant",
                    kind: .callSkill,
                    status: .awaitingAuthorization,
                    skillId: "agent-browser",
                    currentOwner: "supervisor",
                    detail: "waiting on web.fetch approval",
                    orderIndex: 0,
                    updatedAtMs: nowMs
                )
            ],
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            auditRef: "audit-plan-retro-001"
        )
        try SupervisorProjectPlanStore.upsert(plan, for: ctx)

        let skillCall = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "request-retro-001",
            projectId: job.projectId,
            jobId: job.jobId,
            planId: plan.planId,
            stepId: "step-retro-001",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .awaitingAuthorization,
            payload: ["action": .string("extract"), "url": .string("https://example.com/dashboard")],
            currentOwner: "supervisor",
            resultSummary: "waiting for grant",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: "web.fetch",
            grantRequestId: "grant-retro-001",
            grantId: nil,
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            auditRef: "audit-skill-retro-001"
        )
        try SupervisorProjectSkillCallStore.upsert(skillCall, for: ctx)

        let reportsDir = fixture.root
            .appendingPathComponent(".axcoder", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)

        let doctor = SupervisorDoctorReport(
            schemaVersion: "doctor_report.v1",
            generatedAtMs: nowMs,
            workspaceRoot: fixture.root.path,
            configSource: "test",
            secretsPlanSource: "test",
            ok: false,
            findings: [
                SupervisorDoctorFinding(
                    code: "ws_origin_missing",
                    area: "websocket",
                    severity: .blocking,
                    priority: .p0,
                    title: "Allowed origins are missing",
                    detail: "websocket ingress is not restricted",
                    priorityReason: "production ingress must be constrained",
                    actions: ["Set webSocket.allowedOrigins in doctor_config.json."],
                    verifyHint: "doctor -> ws_origin_missing disappears"
                )
            ],
            suggestions: [
                SupervisorDoctorSuggestionCard(
                    findingCode: "ws_origin_missing",
                    priority: .p0,
                    title: "Constrain websocket origins",
                    why: "Avoid uncontrolled ingress into supervisor actions.",
                    actions: ["Set webSocket.allowedOrigins in doctor_config.json."],
                    verifyHint: "doctor -> ws_origin_missing disappears"
                )
            ],
            summary: SupervisorDoctorSummary(
                doctorReportPresent: 1,
                releaseBlockedByDoctorWithoutReport: 0,
                blockingCount: 1,
                warningCount: 0,
                dmAllowlistRiskCount: 0,
                wsAuthRiskCount: 1,
                preAuthFloodBreakerRiskCount: 0,
                secretsPathOutOfScopeCount: 0,
                secretsMissingVariableCount: 0,
                secretsPermissionBoundaryCount: 0
            )
        )
        let doctorData = try JSONEncoder().encode(doctor)
        try doctorData.write(to: reportsDir.appendingPathComponent("supervisor_doctor_report.json"), options: .atomic)

        let incidents = #"""
        {
          "schema_version": "xt_ready_incident_events.v1",
          "generated_at_ms": 1773600000000,
          "source": "test",
          "summary": {
            "high_risk_lane_without_grant": 0,
            "unaudited_auto_resolution": 0,
            "high_risk_bypass_count": 0,
            "blocked_event_miss_rate": 0,
            "non_message_ingress_policy_coverage": 1
          },
          "events": [
            {
              "event_type": "supervisor.incident.grant_pending.handled",
              "incident_code": "grant_pending",
              "lane_id": "lane-1",
              "detected_at_ms": 1773600000000,
              "handled_at_ms": 1773600000100,
              "deny_code": "grant_pending",
              "audit_event_type": "supervisor.incident.handled",
              "audit_ref": "audit-incident-1",
              "takeover_latency_ms": 100
            }
          ]
        }
        """#
        try incidents.write(to: reportsDir.appendingPathComponent("xt_ready_incident_events.runtime.json"), atomically: true, encoding: .utf8)

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .memory_snapshot,
                args: [
                    "mode": .string(XTMemoryUseMode.supervisorOrchestration.rawValue),
                    "retrospective": .bool(true),
                    "focus": .string("grant reliability"),
                    "limit": .number(3),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["tool"]) == ToolName.memory_snapshot.rawValue)
        #expect(jsonString(summary["analysis_profile"]) == "self_improvement")
        #expect(jsonString(summary["focus"]) == "grant reliability")
        #expect(jsonNumber(summary["awaiting_authorization_skill_call_count"]) == 1)
        #expect(jsonNumber(summary["doctor_blocking_count"]) == 1)
        #expect(jsonArray(summary["incident_missing_codes"])?.contains(where: { jsonString($0) == "awaiting_instruction" }) == true)
        #expect(jsonArray(summary["incident_missing_codes"])?.contains(where: { jsonString($0) == "runtime_error" }) == true)
        #expect((jsonNumber(summary["recommendation_count"]) ?? 0) >= 3)

        let body = toolBody(result.output)
        #expect(body.contains("Self Improvement Report"))
        #expect(body.contains("goal: Ship governed browser automation without grant stalls."))
        #expect(body.contains("skill agent-browser [awaiting_authorization]"))
        #expect(body.contains("doctor ws_origin_missing [blocking]"))
        #expect(body.contains("Restore XT-ready incident coverage"))
    }
}
