import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct SupervisorDoctorTests {

    @Test
    func allowlistEmptyBlocksAndReturnsActionableSuggestion() {
        var config = SupervisorDoctorConfig.conservativeDefault()
        config.dmPolicy = "allowlist"
        config.allowFrom = []

        let workspace = URL(fileURLWithPath: "/tmp/xterminal_doctor_test", isDirectory: true)
        let input = SupervisorDoctorInputBundle(
            workspaceRoot: workspace,
            config: config,
            configSource: "unit_test",
            secretsPlan: SupervisorSecretsDryRunPlan(
                allowedRoots: [workspace.appendingPathComponent(".axcoder/secrets").path],
                allowedModes: ["0600"],
                items: []
            ),
            secretsPlanSource: "unit_test",
            reportURL: workspace.appendingPathComponent("doctor_report.json"),
            memoryAssemblySnapshot: nil
        )

        let report = SupervisorDoctorChecker.run(input: input)

        #expect(report.ok == false)
        #expect(report.findings.contains(where: { $0.code == "dm_allowlist_empty" }))
        #expect(report.suggestions.contains(where: { $0.findingCode == "dm_allowlist_empty" && !$0.actions.isEmpty }))
    }

    @Test
    func secretsOutOfScopePathIsBlocked() {
        let workspace = URL(fileURLWithPath: "/tmp/xterminal_doctor_test", isDirectory: true)
        let safeRoot = workspace.appendingPathComponent(".axcoder/secrets", isDirectory: true).path
        let plan = SupervisorSecretsDryRunPlan(
            allowedRoots: [safeRoot],
            allowedModes: ["0600"],
            items: [
                .init(
                    name: "prod token",
                    targetPath: "/etc/xterminal/secret.env",
                    requiredVariables: ["API_TOKEN"],
                    providedVariables: ["API_TOKEN"],
                    mode: "0600"
                )
            ]
        )

        let input = SupervisorDoctorInputBundle(
            workspaceRoot: workspace,
            config: .conservativeDefault(),
            configSource: "unit_test",
            secretsPlan: plan,
            secretsPlanSource: "unit_test",
            reportURL: workspace.appendingPathComponent("doctor_report.json"),
            memoryAssemblySnapshot: nil
        )

        let report = SupervisorDoctorChecker.run(input: input)

        #expect(report.ok == false)
        #expect(report.summary.secretsPathOutOfScopeCount == 1)
        #expect(report.findings.contains(where: { $0.code == "secrets_target_path_out_of_scope" }))
    }

    @Test
    func missingReportNeverPassesReleaseGate() {
        let decision = SupervisorDoctorGateEvaluator.evaluate(report: nil)
        #expect(decision.pass == false)
        #expect(decision.releaseBlockedByDoctorWithoutReport == 1)
        #expect(decision.reason == "missing_supervisor_doctor_report")
    }

    @Test
    func runAndPersistWritesSecretsDryRunCompatReport() throws {
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xterminal_doctor_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let reportURL = workspace.appendingPathComponent(".axcoder/reports/supervisor_doctor_report.json")
        let plan = SupervisorSecretsDryRunPlan(
            allowedRoots: [workspace.appendingPathComponent(".axcoder/secrets").path],
            allowedModes: ["0600"],
            items: [
                .init(
                    name: "api",
                    targetPath: "/etc/xterminal/token.env",
                    requiredVariables: ["API_TOKEN", "API_REGION"],
                    providedVariables: ["API_TOKEN"],
                    mode: "0644"
                )
            ]
        )
        let input = SupervisorDoctorInputBundle(
            workspaceRoot: workspace,
            config: .conservativeDefault(),
            configSource: "unit_test",
            secretsPlan: plan,
            secretsPlanSource: "unit_test",
            reportURL: reportURL,
            memoryAssemblySnapshot: nil
        )

        let report = SupervisorDoctorChecker.runAndPersist(input: input)
        #expect(report.ok == false)

        let compatURL = reportURL.deletingLastPathComponent().appendingPathComponent("secrets-dry-run-report.json")
        #expect(FileManager.default.fileExists(atPath: compatURL.path))

        let data = try Data(contentsOf: compatURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((json?["dry_run"] as? Bool) == true)
        #expect((json?["target_path_out_of_scope_count"] as? Int) == 1)
        #expect((json?["missing_variables_count"] as? Int) == 1)
        #expect((json?["permission_boundary_error_count"] as? Int) == 1)

        let doctorCompatURL = reportURL.deletingLastPathComponent().appendingPathComponent("doctor-report.json")
        #expect(FileManager.default.fileExists(atPath: doctorCompatURL.path))
        let doctorData = try Data(contentsOf: doctorCompatURL)
        let doctorJSON = try JSONSerialization.jsonObject(with: doctorData) as? [String: Any]
        let doctorSection = doctorJSON?["doctor"] as? [String: Any]
        #expect((doctorSection?["dmPolicy"] as? String) == "allowlist")
        #expect((doctorSection?["allowFrom"] as? [String])?.isEmpty == false)
        #expect((doctorSection?["ws_origin"] as? String)?.isEmpty == false)
        #expect((doctorSection?["shared_token_auth"] as? Bool) == true)
        #expect((doctorSection?["non_message_ingress_policy_coverage"] as? Int) == 1)
        #expect((doctorSection?["unauthorized_flood_drop_count"] as? Int) == 45)
    }

    @Test
    func writeReportFallsBackToNonAtomicOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xterminal_doctor_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let capture = SupervisorDoctorReportWriterTestCapture()
        let reportURL = workspace.appendingPathComponent(".axcoder/reports/supervisor_doctor_report.json")
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{\"stale\":true}\n".utf8).write(to: reportURL)

        let report = SupervisorDoctorChecker.run(input: makeInput(snapshot: nil))

        SupervisorDoctorChecker.installReportWriteAttemptOverrideForTesting { data, url, options in
            capture.appendWriteOption(options)
            if options.contains(.atomic) {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: url, options: options)
        }
        SupervisorDoctorChecker.installReportLogSinkForTesting { line in
            capture.appendLogLine(line)
        }
        defer { SupervisorDoctorChecker.resetReportWriteBehaviorForTesting() }

        SupervisorDoctorChecker.writeReport(report, to: reportURL)

        let decoded = try JSONDecoder().decode(
            SupervisorDoctorReport.self,
            from: Data(contentsOf: reportURL)
        )
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(capture.logLinesSnapshot().isEmpty)
        #expect(decoded.schemaVersion == SupervisorDoctorChecker.schemaVersion)
    }

    @Test
    func runAndPersistSuppressesRepeatedCompatWriteFailureLogsDuringCooldown() throws {
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xterminal_doctor_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let capture = SupervisorDoctorReportWriterTestCapture()
        let input = SupervisorDoctorInputBundle(
            workspaceRoot: workspace,
            config: .conservativeDefault(),
            configSource: "unit_test",
            secretsPlan: SupervisorSecretsDryRunPlan(
                allowedRoots: [workspace.appendingPathComponent(".axcoder/secrets").path],
                allowedModes: ["0600"],
                items: []
            ),
            secretsPlanSource: "unit_test",
            reportURL: workspace.appendingPathComponent(".axcoder/reports/supervisor_doctor_report.json"),
            memoryAssemblySnapshot: nil
        )

        SupervisorDoctorChecker.installReportNowProviderForTesting {
            Date(timeIntervalSince1970: 1_773_000_000)
        }
        SupervisorDoctorChecker.installReportWriteAttemptOverrideForTesting { _, _, options in
            capture.appendWriteOption(options)
            throw NSError(domain: NSPOSIXErrorDomain, code: 28)
        }
        SupervisorDoctorChecker.installReportLogSinkForTesting { line in
            capture.appendLogLine(line)
        }
        defer { SupervisorDoctorChecker.resetReportWriteBehaviorForTesting() }

        _ = SupervisorDoctorChecker.runAndPersist(input: input)
        _ = SupervisorDoctorChecker.runAndPersist(input: input)

        let logLines = capture.logLinesSnapshot()
        #expect(logLines.count == 3)
        #expect(logLines.contains(where: { $0.contains("SupervisorDoctor write report failed") }))
        #expect(logLines.contains(where: { $0.contains("SupervisorDoctor write doctor compat report failed") }))
        #expect(logLines.contains(where: { $0.contains("SupervisorDoctor write secrets dry-run compat report failed") }))
        #expect(capture.writeOptionsSnapshot().count == 6)
    }

    @Test
    func memoryReviewFloorMissIsSurfacedAsBlockingFinding() {
        let snapshot = makeMemorySnapshot(
            profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
            resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue
        )
        let report = SupervisorDoctorChecker.run(input: makeInput(snapshot: snapshot))

        let finding = report.findings.first { $0.code == "memory_review_floor_not_met" }
        #expect(finding?.area == "memory_assembly")
        #expect(finding?.severity == .blocking)
        #expect(report.summary.memoryAssemblyBlockingCount == 1)
        #expect(report.summary.memoryAssemblyWarningCount == 0)
    }

    @Test
    func truncatedCoreMemoryLayerIsSurfacedAsWarning() {
        let snapshot = makeMemorySnapshot(
            truncatedLayers: ["l1_canonical"]
        )
        let report = SupervisorDoctorChecker.run(input: makeInput(snapshot: snapshot))

        let finding = report.findings.first { $0.code == "memory_core_layers_truncated" }
        #expect(finding?.area == "memory_assembly")
        #expect(finding?.severity == .warning)
        #expect(report.summary.memoryAssemblyBlockingCount == 0)
        #expect(report.summary.memoryAssemblyWarningCount == 1)
    }

    @Test
    func continuityFloorMissIsSurfacedWhenDialogueWindowIsPresent() {
        let snapshot = makeMemorySnapshot(
            selectedSections: [
                "dialogue_window",
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack",
            ],
            rawWindowSelectedPairs: 6,
            continuityFloorSatisfied: false,
            rawWindowSource: "mixed",
            lowSignalDroppedMessages: 2,
            continuityTraceLines: [
                "remote_continuity=ok cache_hit=false working_entries=14 assembled_source=mixed"
            ],
            lowSignalDropSampleLines: [
                "role=user reason=pure_ack_or_greeting text=你好"
            ]
        )
        let report = SupervisorDoctorChecker.run(input: makeInput(snapshot: snapshot))

        let finding = report.findings.first { $0.code == "memory_continuity_floor_not_met" }
        #expect(finding?.area == "memory_assembly")
        #expect(finding?.severity == .blocking)
        #expect(finding?.detail.contains("selected_pairs=6") == true)
        #expect(finding?.detail.contains("raw_source=mixed") == true)
    }

    @Test
    func canonicalSyncFailureForFocusedProjectBecomesMemoryAssemblyFinding() {
        let snapshot = makeMemorySnapshot()
        let syncSnapshot = HubIPCClient.CanonicalMemorySyncStatusSnapshot(
            schemaVersion: "canonical_memory_sync_status.v1",
            updatedAtMs: 1_773_000_010_000,
            items: [
                HubIPCClient.CanonicalMemorySyncStatusItem(
                    scopeKind: "project",
                    scopeId: "project-alpha",
                    displayName: "Alpha",
                    source: "file_ipc",
                    ok: false,
                    updatedAtMs: 1_773_000_010_000,
                    reasonCode: "project_canonical_memory_write_failed",
                    detail: "xterminal_project_memory_write_failed=NSError:No space left on device",
                    auditRefs: ["audit-project-alpha-1"],
                    evidenceRefs: ["canonical_memory_item:item-project-alpha-1"],
                    writebackRefs: ["canonical_memory_item:item-project-alpha-1"]
                )
            ]
        )

        let report = SupervisorDoctorChecker.run(
            input: makeInput(snapshot: snapshot, canonicalSyncSnapshot: syncSnapshot)
        )

        let finding = report.findings.first { $0.code == "memory_canonical_sync_delivery_failed" }
        #expect(finding?.area == "memory_assembly")
        #expect(finding?.severity == .blocking)
        #expect(finding?.detail.contains("scope=project") == true)
        #expect(finding?.detail.contains("audit_ref=audit-project-alpha-1") == true)
        #expect(finding?.detail.contains("evidence_ref=canonical_memory_item:item-project-alpha-1") == true)
        #expect(finding?.detail.contains("writeback_ref=canonical_memory_item:item-project-alpha-1") == true)
        #expect(report.summary.memoryAssemblyBlockingCount == 1)
    }

    @Test
    func missingScopedHiddenProjectRecoveryBecomesBlockingFindingWithActionableSuggestion() {
        let snapshot = makeMemorySnapshot(
            selectedSections: ["l1_canonical", "l2_observations", "l3_working_set", "dialogue_window"],
            scopedPromptRecoveryMode: "explicit_hidden_project_focus",
            scopedPromptRecoverySections: []
        )
        let report = SupervisorDoctorChecker.run(input: makeInput(snapshot: snapshot))

        let finding = report.findings.first { $0.code == "memory_scoped_hidden_project_recovery_missing" }
        #expect(finding?.area == "memory_assembly")
        #expect(finding?.severity == .blocking)
        #expect(finding?.priority == .p0)
        #expect(finding?.priorityReason.contains("hidden project") == true)
        #expect(finding?.actions.first?.contains("显式聚焦回合") == true)
        #expect(finding?.verifyHint?.contains("scopedPromptRecoverySections") == true)
        #expect(report.suggestions.contains(where: {
            $0.findingCode == "memory_scoped_hidden_project_recovery_missing"
                && $0.priority == .p0
                && ($0.actions.first?.contains("显式聚焦回合") == true)
        }))
    }

    @Test
    func legacyDoctorSummaryDecodesWithoutMemoryAssemblyFields() throws {
        let legacyJSON = """
        {
          "schemaVersion": "supervisor_doctor.v1",
          "generatedAtMs": 1773000000000,
          "workspaceRoot": "/tmp/xterminal_doctor_legacy",
          "configSource": "legacy",
          "secretsPlanSource": "legacy",
          "ok": false,
          "findings": [],
          "suggestions": [],
          "summary": {
            "doctorReportPresent": 1,
            "releaseBlockedByDoctorWithoutReport": 0,
            "blockingCount": 1,
            "warningCount": 2,
            "dmAllowlistRiskCount": 0,
            "wsAuthRiskCount": 1,
            "preAuthFloodBreakerRiskCount": 0,
            "secretsPathOutOfScopeCount": 0,
            "secretsMissingVariableCount": 0,
            "secretsPermissionBoundaryCount": 0
          }
        }
        """

        let report = try JSONDecoder().decode(
            SupervisorDoctorReport.self,
            from: Data(legacyJSON.utf8)
        )

        #expect(report.summary.memoryAssemblyBlockingCount == 0)
        #expect(report.summary.memoryAssemblyWarningCount == 0)
        #expect(report.summary.blockingCount == 1)
        #expect(report.summary.warningCount == 2)
    }

    @MainActor
    @Test
    func doctorSummaryIncludesCanonicalRetryFeedback() {
        let manager = SupervisorManager.makeForTesting()
        manager.setCanonicalMemoryRetryFeedbackForTesting(
            .init(
                statusLine: "canonical_sync_retry: failed ok=0 · failed=2",
                detailLine: "failed: device:supervisor-main(Supervisor) reason=device_canonical_memory_write_failed detail=broken pipe",
                metaLine: "attempt: 刚刚 · last_status: 刚刚",
                tone: .danger
            )
        )
        let report = SupervisorDoctorReport(
            schemaVersion: "xt.supervisor_doctor_report.v1",
            generatedAtMs: 100,
            workspaceRoot: "/tmp/workspace",
            configSource: "config.json",
            secretsPlanSource: "secrets.json",
            ok: true,
            findings: [],
            suggestions: [],
            summary: SupervisorDoctorSummary(
                doctorReportPresent: 1,
                releaseBlockedByDoctorWithoutReport: 0,
                blockingCount: 0,
                warningCount: 0,
                memoryAssemblyBlockingCount: 0,
                memoryAssemblyWarningCount: 0,
                dmAllowlistRiskCount: 0,
                wsAuthRiskCount: 0,
                preAuthFloodBreakerRiskCount: 0,
                secretsPathOutOfScopeCount: 0,
                secretsMissingVariableCount: 0,
                secretsPermissionBoundaryCount: 0
            )
        )

        let text = manager.renderDoctorSummaryForTesting(report)

        #expect(text.contains("canonical_sync_retry: failed ok=0 · failed=2"))
        #expect(text.contains("canonical_sync_retry_meta：attempt: 刚刚 · last_status: 刚刚"))
        #expect(text.contains("canonical_sync_retry_detail：failed: device:supervisor-main(Supervisor) reason=device_canonical_memory_write_failed detail=broken pipe"))
    }

    @MainActor
    @Test
    func doctorSummaryPrependsWorkbenchGovernanceBriefWhenPendingGrantExists() {
        let manager = SupervisorManager.makeForTesting()
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "doctor-brief-grant-1",
                    dedupeKey: "doctor-brief-grant-1",
                    grantRequestId: "doctor-brief-grant-1",
                    requestId: "req-doctor-brief-grant-1",
                    projectId: "project-release",
                    projectName: "Release Runtime",
                    capability: "device_authority",
                    modelId: "",
                    reason: "需要批准设备级权限后继续自动化",
                    requestedTtlSec: 3600,
                    requestedTokenCap: 12_000,
                    createdAt: 1_000,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "release_path",
                    nextAction: "打开授权并批准设备级权限"
                )
            ]
        )
        let report = SupervisorDoctorReport(
            schemaVersion: "xt.supervisor_doctor_report.v1",
            generatedAtMs: 100,
            workspaceRoot: "/tmp/workspace",
            configSource: "config.json",
            secretsPlanSource: "secrets.json",
            ok: true,
            findings: [],
            suggestions: [],
            summary: SupervisorDoctorSummary(
                doctorReportPresent: 1,
                releaseBlockedByDoctorWithoutReport: 0,
                blockingCount: 0,
                warningCount: 0,
                memoryAssemblyBlockingCount: 0,
                memoryAssemblyWarningCount: 0,
                dmAllowlistRiskCount: 0,
                wsAuthRiskCount: 0,
                preAuthFloodBreakerRiskCount: 0,
                secretsPathOutOfScopeCount: 0,
                secretsMissingVariableCount: 0,
                secretsPermissionBoundaryCount: 0
            )
        )

        let text = manager.renderDoctorSummaryForTesting(report)

        #expect(text.contains("🧭 Supervisor Brief · 当前工作台"))
        #expect(text.contains("Hub 待处理授权"))
        #expect(text.contains("查看：查看授权板"))
        #expect(text.contains("🩺 Supervisor Doctor 预检结果"))
    }

    @MainActor
    @Test
    func secretsDryRunSummaryPrependsWorkbenchGovernanceBriefWhenPendingSkillApprovalExists() {
        let manager = SupervisorManager.makeForTesting()
        manager.setPendingSupervisorSkillApprovalsForTesting(
            [
                SupervisorManager.SupervisorPendingSkillApproval(
                    id: "doctor-secrets-approval-1",
                    requestId: "doctor-secrets-approval-1",
                    projectId: "project-security",
                    projectName: "Security Runtime",
                    jobId: "job-1",
                    planId: "plan-1",
                    stepId: "step-1",
                    skillId: "secret-vault-browser-fill",
                    toolName: "browser.fill",
                    tool: nil,
                    toolSummary: "向浏览器页面填写凭据",
                    reason: "需要人工确认凭据写入动作",
                    createdAt: 1_000,
                    actionURL: nil,
                    routingReasonCode: nil,
                    routingExplanation: nil
                )
            ]
        )
        let report = SupervisorDoctorReport(
            schemaVersion: "xt.supervisor_doctor_report.v1",
            generatedAtMs: 100,
            workspaceRoot: "/tmp/workspace",
            configSource: "config.json",
            secretsPlanSource: "secrets.json",
            ok: false,
            findings: [],
            suggestions: [],
            summary: SupervisorDoctorSummary(
                doctorReportPresent: 1,
                releaseBlockedByDoctorWithoutReport: 0,
                blockingCount: 1,
                warningCount: 0,
                memoryAssemblyBlockingCount: 0,
                memoryAssemblyWarningCount: 0,
                dmAllowlistRiskCount: 0,
                wsAuthRiskCount: 0,
                preAuthFloodBreakerRiskCount: 0,
                secretsPathOutOfScopeCount: 1,
                secretsMissingVariableCount: 0,
                secretsPermissionBoundaryCount: 0
            )
        )

        let text = manager.renderSecretsDryRunSummaryForTesting(report)

        #expect(text.contains("🧭 Supervisor Brief · 当前工作台"))
        #expect(text.contains("待审批技能"))
        #expect(text.contains("查看：查看技能审批"))
        #expect(text.contains("🔐 Secrets dry-run 摘要"))
    }

    @MainActor
    @Test
    func secretsDryRunSummaryPrependsWorkbenchGovernanceBriefWhenPendingSkillGrantExists() {
        let manager = SupervisorManager.makeForTesting()
        manager.setPendingSupervisorSkillApprovalsForTesting(
            [
                SupervisorManager.SupervisorPendingSkillApproval(
                    id: "doctor-secrets-grant-1",
                    requestId: "doctor-secrets-grant-1",
                    projectId: "project-security",
                    projectName: "Security Runtime",
                    jobId: "job-1",
                    planId: "plan-1",
                    stepId: "step-1",
                    skillId: "agent-browser",
                    requestedSkillId: "browser.open",
                    toolName: ToolName.deviceBrowserControl.rawValue,
                    tool: .deviceBrowserControl,
                    toolSummary: "向浏览器页面填写凭据",
                    reason: "需要人工确认凭据写入动作",
                    createdAt: 1_000,
                    actionURL: nil,
                    routingReasonCode: nil,
                    routingExplanation: nil,
                    readiness: XTSkillExecutionReadiness(
                        schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
                        projectId: "project-security",
                        skillId: "agent-browser",
                        packageSHA256: String(repeating: "d", count: 64),
                        publisherID: "xhub.official",
                        policyScope: "hub_governed",
                        intentFamilies: ["browser.observe", "browser.interact"],
                        capabilityFamilies: ["browser.observe", "browser.interact"],
                        capabilityProfiles: ["observe_only", "browser_operator"],
                        discoverabilityState: "discoverable",
                        installabilityState: "installable",
                        pinState: "pinned",
                        resolutionState: "resolved",
                        executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
                        runnableNow: false,
                        denyCode: "grant_required",
                        reasonCode: "grant floor privileged requires hub grant",
                        grantFloor: XTSkillGrantFloor.privileged.rawValue,
                        approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
                        requiredGrantCapabilities: ["browser.interact"],
                        requiredRuntimeSurfaces: ["managed_browser_runtime"],
                        stateLabel: "awaiting_hub_grant",
                        installHint: "",
                        unblockActions: ["request_hub_grant"],
                        auditRef: "audit-doctor-secrets-grant-1",
                        doctorAuditRef: "",
                        vetterAuditRef: "",
                        resolvedSnapshotId: "snapshot-doctor-secrets-grant-1",
                        grantSnapshotRef: "grant-doctor-secrets-grant-1"
                    )
                )
            ]
        )
        let report = SupervisorDoctorReport(
            schemaVersion: "xt.supervisor_doctor_report.v1",
            generatedAtMs: 100,
            workspaceRoot: "/tmp/workspace",
            configSource: "config.json",
            secretsPlanSource: "secrets.json",
            ok: false,
            findings: [],
            suggestions: [],
            summary: SupervisorDoctorSummary(
                doctorReportPresent: 1,
                releaseBlockedByDoctorWithoutReport: 0,
                blockingCount: 1,
                warningCount: 0,
                memoryAssemblyBlockingCount: 0,
                memoryAssemblyWarningCount: 0,
                dmAllowlistRiskCount: 0,
                wsAuthRiskCount: 0,
                preAuthFloodBreakerRiskCount: 0,
                secretsPathOutOfScopeCount: 1,
                secretsMissingVariableCount: 0,
                secretsPermissionBoundaryCount: 0
            )
        )

        let text = manager.renderSecretsDryRunSummaryForTesting(report)

        #expect(text.contains("🧭 Supervisor Brief · 当前工作台"))
        #expect(text.contains("技能授权待处理"))
        #expect(text.contains("查看：查看技能授权"))
        #expect(text.contains("🔐 Secrets dry-run 摘要"))
    }

    @MainActor
    @Test
    func doctorSummaryIncludesDurableCandidateMirrorDetailWhenPresent() {
        let manager = SupervisorManager.makeForTesting()
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeMemorySnapshot(
                continuityTraceLines: [
                    "remote_continuity=ok cache_hit=false working_entries=18 assembled_source=mixed"
                ],
                durableCandidateMirrorStatus: .hubMirrorFailed,
                durableCandidateMirrorTarget: XTSupervisorDurableCandidateMirror.mirrorTarget,
                durableCandidateMirrorAttempted: true,
                durableCandidateMirrorErrorCode: "remote_route_not_preferred"
            )
        )
        let report = SupervisorDoctorReport(
            schemaVersion: "xt.supervisor_doctor_report.v1",
            generatedAtMs: 100,
            workspaceRoot: "/tmp/workspace",
            configSource: "config.json",
            secretsPlanSource: "secrets.json",
            ok: true,
            findings: [],
            suggestions: [],
            summary: SupervisorDoctorSummary(
                doctorReportPresent: 1,
                releaseBlockedByDoctorWithoutReport: 0,
                blockingCount: 0,
                warningCount: 0,
                memoryAssemblyBlockingCount: 0,
                memoryAssemblyWarningCount: 0,
                dmAllowlistRiskCount: 0,
                wsAuthRiskCount: 0,
                preAuthFloodBreakerRiskCount: 0,
                secretsPathOutOfScopeCount: 0,
                secretsMissingVariableCount: 0,
                secretsPermissionBoundaryCount: 0
            )
        )

        let text = manager.renderDoctorSummaryForTesting(report)

        #expect(text.contains("durable_candidate_mirror status=hub_mirror_failed"))
        #expect(text.contains("reason=remote_route_not_preferred"))
    }

    private func makeInput(
        snapshot: SupervisorMemoryAssemblySnapshot?,
        canonicalSyncSnapshot: HubIPCClient.CanonicalMemorySyncStatusSnapshot? = nil
    ) -> SupervisorDoctorInputBundle {
        let workspace = URL(fileURLWithPath: "/tmp/xterminal_doctor_memory_test", isDirectory: true)
        return SupervisorDoctorInputBundle(
            workspaceRoot: workspace,
            config: .conservativeDefault(),
            configSource: "unit_test",
            secretsPlan: SupervisorSecretsDryRunPlan(
                allowedRoots: [workspace.appendingPathComponent(".axcoder/secrets").path],
                allowedModes: ["0600"],
                items: []
            ),
            secretsPlanSource: "unit_test",
            reportURL: workspace.appendingPathComponent("doctor_report.json"),
            memoryAssemblySnapshot: snapshot,
            canonicalMemorySyncSnapshot: canonicalSyncSnapshot
        )
    }

    private func makeMemorySnapshot(
        reviewLevelHint: SupervisorReviewLevel = .r2Strategic,
        requestedProfile: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        profileFloor: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        resolvedProfile: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        focusedProjectId: String? = "project-alpha",
        selectedSections: [String] = [
            "portfolio_brief",
            "focused_project_anchor_pack",
            "longterm_outline",
            "delta_feed",
            "conflict_set",
            "context_refs",
            "evidence_pack",
        ],
        omittedSections: [String] = [],
        rawWindowSelectedPairs: Int = 12,
        continuityFloorSatisfied: Bool = true,
        rawWindowSource: String = "hub_thread",
        lowSignalDroppedMessages: Int = 0,
        continuityTraceLines: [String] = [],
        lowSignalDropSampleLines: [String] = [],
        contextRefsSelected: Int = 2,
        contextRefsOmitted: Int = 0,
        evidenceItemsSelected: Int = 2,
        evidenceItemsOmitted: Int = 0,
        truncatedLayers: [String] = [],
        scopedPromptRecoveryMode: String? = nil,
        scopedPromptRecoverySections: [String]? = nil,
        durableCandidateMirrorStatus: SupervisorDurableCandidateMirrorStatus = .notNeeded,
        durableCandidateMirrorTarget: String? = nil,
        durableCandidateMirrorAttempted: Bool = false,
        durableCandidateMirrorErrorCode: String? = nil,
        durableCandidateLocalStoreRole: String = XTSupervisorDurableCandidateMirror.localStoreRole
    ) -> SupervisorMemoryAssemblySnapshot {
        SupervisorMemoryAssemblySnapshot(
            source: "unit_test",
            resolutionSource: "unit_test",
            updatedAt: 1_773_000_000,
            reviewLevelHint: reviewLevelHint.rawValue,
            requestedProfile: requestedProfile,
            profileFloor: profileFloor,
            resolvedProfile: resolvedProfile,
            attemptedProfiles: [requestedProfile, resolvedProfile],
            progressiveUpgradeCount: 0,
            focusedProjectId: focusedProjectId,
            rawWindowSelectedPairs: rawWindowSelectedPairs,
            lowSignalDroppedMessages: lowSignalDroppedMessages,
            rawWindowSource: rawWindowSource,
            continuityFloorSatisfied: continuityFloorSatisfied,
            continuityTraceLines: continuityTraceLines,
            lowSignalDropSampleLines: lowSignalDropSampleLines,
            selectedSections: selectedSections,
            omittedSections: omittedSections,
            contextRefsSelected: contextRefsSelected,
            contextRefsOmitted: contextRefsOmitted,
            evidenceItemsSelected: evidenceItemsSelected,
            evidenceItemsOmitted: evidenceItemsOmitted,
            budgetTotalTokens: 1_800,
            usedTotalTokens: 1_120,
            truncatedLayers: truncatedLayers,
            freshness: "fresh_local_ipc",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "progressive_disclosure",
            durableCandidateMirrorStatus: durableCandidateMirrorStatus,
            durableCandidateMirrorTarget: durableCandidateMirrorTarget,
            durableCandidateMirrorAttempted: durableCandidateMirrorAttempted,
            durableCandidateMirrorErrorCode: durableCandidateMirrorErrorCode,
            durableCandidateLocalStoreRole: durableCandidateLocalStoreRole,
            scopedPromptRecoveryMode: scopedPromptRecoveryMode,
            scopedPromptRecoverySections: scopedPromptRecoverySections
        )
    }
}

private final class SupervisorDoctorReportWriterTestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var writeOptions: [Data.WritingOptions] = []
    private var logLines: [String] = []

    func appendWriteOption(_ option: Data.WritingOptions) {
        lock.lock()
        defer { lock.unlock() }
        writeOptions.append(option)
    }

    func appendLogLine(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        logLines.append(line)
    }

    func writeOptionsSnapshot() -> [Data.WritingOptions] {
        lock.lock()
        defer { lock.unlock() }
        return writeOptions
    }

    func logLinesSnapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return logLines
    }
}
