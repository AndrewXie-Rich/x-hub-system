import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct XHubDoctorOutputTests {
    @Test
    func mapsXTUnifiedDoctorReportToGenericDoctorBundle() {
        let xtReport = sampleXTUnifiedDoctorReport(
            sourceReportPath: "/tmp/xt_unified_doctor_report.json"
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: "/tmp/xhub_doctor_output_xt.json"
        )

        #expect(bundle.schemaVersion == XHubDoctorOutputReport.currentSchemaVersion)
        #expect(bundle.contractVersion == XHubDoctorOutputReport.currentContractVersion)
        #expect(bundle.bundleKind == .pairedSurfaceReadiness)
        #expect(bundle.producer == .xTerminal)
        #expect(bundle.surface == .xtUI)
        #expect(bundle.reportID == "xhub-doctor-xt-xt_ui-1741300000")
        #expect(bundle.overallState == .degraded)
        #expect(bundle.summary.headline == "Pairing ok, but model route needs repair")
        #expect(bundle.summary.passed == 1)
        #expect(bundle.summary.failed == 1)
        #expect(bundle.summary.warned == 1)
        #expect(bundle.summary.skipped == 0)
        #expect(bundle.readyForFirstTask == false)
        #expect(bundle.currentFailureCode == "hub_unreachable")
        #expect(bundle.currentFailureIssue == UITroubleshootIssue.hubUnreachable.rawValue)
        #expect(bundle.routeSnapshot?.routeLabel == "paired-local")
        #expect(bundle.routeSnapshot?.internetHostKind == "raw_ip")
        #expect(bundle.routeSnapshot?.internetHostScope == "loopback")
        #expect(bundle.routeSnapshot?.remoteEntryPosture == "temporary_raw_ip_entry")
        #expect(bundle.routeSnapshot?.remoteEntrySummaryLine == "临时 raw IP 入口 · 回环地址 · host=127.0.0.1")
        #expect(bundle.reportPath == "/tmp/xhub_doctor_output_xt.json")
        #expect(bundle.sourceReportSchemaVersion == XTUnifiedDoctorReport.currentSchemaVersion)
        #expect(bundle.sourceReportPath == "/tmp/xt_unified_doctor_report.json")
        #expect(bundle.consumedContracts == ["xt.ui_surface_state_contract.v1", XTUnifiedDoctorReportContract.frozen.schemaVersion])
        #expect(bundle.checks.count == 3)
        #expect(bundle.checks[0].status == .pass)
        #expect(bundle.checks[1].status == .fail)
        #expect(bundle.checks[1].blocking == true)
        #expect(bundle.checks[1].repairDestinationRef == UITroubleshootDestination.xtChooseModel.rawValue)
        #expect(bundle.checks[1].memoryRouteTruthSnapshot == nil)
        #expect(bundle.checks[2].status == .warn)
        #expect(bundle.checks[2].projectContextSummary == nil)
        #expect(bundle.checks[2].durableCandidateMirrorSnapshot == nil)
        #expect(bundle.checks[2].localStoreWriteSnapshot == nil)
        #expect(bundle.checks[2].skillDoctorTruthSnapshot == nil)
        #expect(bundle.checks[0].freshPairReconnectSmokeSnapshot == nil)
        #expect(bundle.nextSteps.count == 2)
        #expect(bundle.nextSteps[0].kind == .chooseModel)
        #expect(bundle.nextSteps[0].owner == .user)
        #expect(bundle.nextSteps[1].kind == .waitForRecovery)
        #expect(bundle.nextSteps[1].owner == .xtRuntime)
    }

    @Test
    func writesMachineReadableGenericDoctorReport() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-doctor-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: tempRoot)
        let xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        let report = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: reportURL.path
        )

        XHubDoctorOutputStore.writeReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(XHubDoctorOutputReport.self, from: data)

        #expect(decoded.schemaVersion == XHubDoctorOutputReport.currentSchemaVersion)
        #expect(decoded.reportPath == reportURL.path)
        #expect(decoded.sourceReportPath == "/tmp/xt_unified_doctor_report.json")
        #expect(decoded.checks.map(\.status) == [.pass, .fail, .warn])
        #expect(decoded.nextSteps.map(\.kind) == [.chooseModel, .waitForRecovery])
    }

    @Test
    func exportsSkillDoctorTruthSnapshotFromSkillsSection() throws {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections.append(
            XTUnifiedDoctorSection(
                kind: .skillsCompatibilityReadiness,
                state: .diagnosticRequired,
                headline: "Skills need governance repair",
                summary: "Typed skill doctor truth found blocked governed skills.",
                nextStep: "Review the blocked skills before treating them as runnable.",
                repairEntry: .xtDiagnostics,
                detailLines: [
                    "skill_doctor_truth_present=true",
                    "skill_readiness_blocked_skills=1"
                ],
                skillDoctorTruthProjection: sampleSkillDoctorTruthProjection()
            )
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: "/tmp/xhub_doctor_output_xt_skill_doctor.json"
        )

        let check = try #require(bundle.checks.first {
            $0.checkID == XTUnifiedDoctorSectionKind.skillsCompatibilityReadiness.rawValue
        })
        let snapshot = try #require(check.skillDoctorTruthSnapshot)
        #expect(snapshot.effectiveProfileSnapshot.projectId == "project-alpha")
        #expect(snapshot.effectiveProfileSnapshot.runnableNowProfiles == ["observe_only"])
        #expect(snapshot.grantRequiredSkillCount == 1)
        #expect(snapshot.approvalRequiredSkillCount == 1)
        #expect(snapshot.blockedSkillCount == 1)
        #expect(snapshot.blockedSkillPreview.first?.skillID == "delivery-runner")
    }

    @Test
    func exportsHubMemoryPromptProjectionFromSessionRuntimeSection() throws {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime carries Hub prompt projection",
            summary: "Doctor can inspect the Hub prompt projection used by the latest coder turn.",
            nextStep: "Inspect runtime truth coverage before blaming continuity gaps on XT-only state.",
            repairEntry: .xtDiagnostics,
            detailLines: ["runtime_state=ready"],
            hubMemoryPromptProjection: HubMemoryPromptProjectionSnapshot(
                projectionSource: "hub_generate_done_metadata",
                canonicalItemCount: 4,
                workingSetTurnCount: 8,
                runtimeTruthItemCount: 3,
                runtimeTruthSourceKinds: ["guidance_injection", "automation_checkpoint", "heartbeat_projection"]
            )
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: "/tmp/xhub_doctor_output_xt_memory_prompt_projection.json"
        )

        let check = try #require(bundle.checks.first {
            $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue
        })
        let projection = try #require(check.hubMemoryPromptProjection)
        #expect(projection.projectionSource == "hub_generate_done_metadata")
        #expect(projection.canonicalItemCount == 4)
        #expect(projection.workingSetTurnCount == 8)
        #expect(projection.runtimeTruthItemCount == 3)
        #expect(projection.runtimeTruthSourceKinds == ["guidance_injection", "automation_checkpoint", "heartbeat_projection"])
    }

    @Test
    func writesMachineReadableGenericDoctorReportWithHeartbeatGovernanceRecoveryExplainability() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-doctor-output-heartbeat-shown-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: tempRoot)
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is healthy and carries structured heartbeat governance truth.",
            nextStep: "Continue into the active project.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready"
            ],
            heartbeatGovernanceProjection: sampleHeartbeatGovernanceProjection()
        )

        let report = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: reportURL.path
        )
        XHubDoctorOutputStore.writeReport(report, to: reportURL)

        let decoded = try #require(XHubDoctorOutputStore.loadReport(from: reportURL))
        let check = try #require(decoded.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue })
        let snapshot = try #require(check.heartbeatGovernanceSnapshot)
        let recovery = try #require(snapshot.recoveryDecision)

        #expect(snapshot.digestVisibility == XTHeartbeatDigestVisibilityDecision.shown.rawValue)
        #expect(snapshot.digestReasonCodes.contains("weak_done_claim"))
        #expect(recovery.action == HeartbeatRecoveryAction.queueStrategicReview.rawValue)
        #expect(recovery.actionDisplayText == "排队治理复盘")
        #expect(recovery.urgencyDisplayText == "紧急处理")
        #expect(recovery.reasonDisplayText == "heartbeat 或 lane 信号要求先做治理复盘")
        #expect(recovery.systemNextStepDisplayText == "系统会先基于事件触发 · pre-done 信号排队一次救援复盘，并在下一个 safe point 注入 guidance")
        #expect(recovery.sourceSignalDisplayTexts == ["异常 完成声明证据偏弱", "复盘候选 pre-done 信号 / 一次救援复盘 / 事件触发"])
        #expect(recovery.anomalyTypeDisplayTexts == ["完成声明证据偏弱"])
        #expect(recovery.queuedReviewTrigger == SupervisorReviewTrigger.preDoneSummary.rawValue)
        #expect(recovery.queuedReviewTriggerDisplayText == "pre-done 信号")
        #expect(recovery.queuedReviewLevelDisplayText == "一次救援复盘")
        #expect(recovery.queuedReviewRunKindDisplayText == "事件触发")
        #expect(recovery.doctorExplainabilityText?.contains("救援复盘") == true)
        #expect(recovery.doctorExplainabilityText?.contains("紧急处理") == true)
    }

    @Test
    func writesMachineReadableGenericDoctorReportWithSuppressedHeartbeatGovernanceSnapshot() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-doctor-output-heartbeat-suppressed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: tempRoot)
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is healthy and carries suppressed heartbeat governance truth.",
            nextStep: "Continue watching for a higher-signal project delta.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready"
            ],
            heartbeatGovernanceProjection: sampleSuppressedHeartbeatGovernanceProjection()
        )

        let report = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: reportURL.path
        )
        XHubDoctorOutputStore.writeReport(report, to: reportURL)

        let decoded = try #require(XHubDoctorOutputStore.loadReport(from: reportURL))
        let check = try #require(decoded.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue })
        let snapshot = try #require(check.heartbeatGovernanceSnapshot)

        #expect(snapshot.digestVisibility == XTHeartbeatDigestVisibilityDecision.suppressed.rawValue)
        #expect(snapshot.digestReasonCodes == ["stable_runtime_update_suppressed"])
        #expect(snapshot.digestVisibilityDisplayText == "当前压制")
        #expect(snapshot.digestReasonDisplayTexts == ["当前只是稳定运行更新，暂不打扰用户"])
        #expect(snapshot.digestSystemNextStepText.contains("有实质变化再生成用户 digest"))
        #expect(snapshot.recoveryDecision == nil)
    }

    @Test
    func exportsProjectAndSupervisorRemoteSnapshotCacheSnapshots() throws {
        let xtReport = XTUnifiedDoctorReport(
            schemaVersion: XTUnifiedDoctorReport.currentSchemaVersion,
            generatedAtMs: 1_741_300_000,
            overallState: .ready,
            overallSummary: "Session runtime is ready",
            readyForFirstTask: true,
            currentFailureCode: "",
            currentFailureIssue: nil,
            configuredModelRoles: 1,
            availableModelCount: 1,
            loadedModelCount: 1,
            currentSessionID: "session-cache-1",
            currentRoute: XTUnifiedDoctorRouteSnapshot(
                transportMode: "disconnected",
                routeLabel: "disconnected",
                pairingPort: 50052,
                grpcPort: 50051,
                internetHost: ""
            ),
            sections: [
                XTUnifiedDoctorSection(
                    kind: .sessionRuntimeReadiness,
                    state: .ready,
                    headline: "Session runtime is ready",
                    summary: "Project and supervisor memory are available.",
                    nextStep: "Start the task.",
                    repairEntry: .xtDiagnostics,
                    detailLines: [
                        "project_memory_v1_source=hub_snapshot_plus_local_overlay",
                        "memory_v1_freshness=ttl_cache",
                        "memory_v1_cache_hit=true",
                        "memory_v1_remote_snapshot_cache_scope=mode=project_chat project_id=proj-alpha",
                        "memory_v1_remote_snapshot_cached_at_ms=1774000000000",
                        "memory_v1_remote_snapshot_age_ms=6000",
                        "memory_v1_remote_snapshot_ttl_remaining_ms=9000",
                        "memory_source=hub",
                        "memory_freshness=ttl_cache",
                        "memory_cache_hit=true",
                        "remote_snapshot_cache_scope=mode=supervisor_orchestration project_id=(none)",
                        "remote_snapshot_cached_at_ms=1774000005000",
                        "remote_snapshot_age_ms=3000",
                        "remote_snapshot_ttl_remaining_ms=12000"
                    ]
                )
            ],
            consumedContracts: ["xt.ui_surface_state_contract.v1", XTUnifiedDoctorReportContract.frozen.schemaVersion],
            reportPath: "/tmp/xt_unified_doctor_report_cache.json"
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: "/tmp/xhub_doctor_output_xt_cache.json"
        )

        let check = try #require(bundle.checks.first)
        #expect(check.projectRemoteSnapshotCacheSnapshot?.source == "hub_snapshot_plus_local_overlay")
        #expect(check.projectRemoteSnapshotCacheSnapshot?.freshness == "ttl_cache")
        #expect(check.projectRemoteSnapshotCacheSnapshot?.cacheHit == true)
        #expect(check.projectRemoteSnapshotCacheSnapshot?.scope == "mode=project_chat project_id=proj-alpha")
        #expect(check.projectRemoteSnapshotCacheSnapshot?.cachedAtMs == 1_774_000_000_000)
        #expect(check.projectRemoteSnapshotCacheSnapshot?.ageMs == 6_000)
        #expect(check.projectRemoteSnapshotCacheSnapshot?.ttlRemainingMs == 9_000)
        #expect(check.projectRemoteSnapshotCacheSnapshot?.upstreamTruthClass == "hub_durable_truth")
        #expect(check.projectRemoteSnapshotCacheSnapshot?.cacheRole == "xt_remote_snapshot_ttl_cache")
        #expect(check.projectRemoteSnapshotCacheSnapshot?.provenanceLabel == "hub_durable_truth_via_xt_ttl_cache")
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.source == "hub")
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.freshness == "ttl_cache")
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.cacheHit == true)
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.scope == "mode=supervisor_orchestration project_id=(none)")
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.cachedAtMs == 1_774_000_005_000)
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.ageMs == 3_000)
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.ttlRemainingMs == 12_000)
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.upstreamTruthClass == "hub_durable_truth")
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.cacheRole == "xt_remote_snapshot_ttl_cache")
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.provenanceLabel == "hub_durable_truth_via_xt_ttl_cache")
    }

    @Test
    func prefersStructuredRemoteSnapshotCacheProjectionsOverDetailLineFallback() throws {
        let projectProjection = try #require(
            XTUnifiedDoctorRemoteSnapshotCacheProjection(
                source: "hub_snapshot_plus_local_overlay",
                freshness: "ttl_cache",
                cacheHit: true,
                scope: "mode=project_chat project_id=proj-structured",
                cachedAtMs: 1_774_100_000_000,
                ageMs: 2_000,
                ttlRemainingMs: 13_000
            )
        )
        let supervisorProjection = try #require(
            XTUnifiedDoctorRemoteSnapshotCacheProjection(
                source: "hub",
                freshness: "fresh_local_ipc",
                cacheHit: false,
                scope: "mode=supervisor_orchestration project_id=(none)",
                cachedAtMs: 1_774_100_005_000,
                ageMs: 1_000,
                ttlRemainingMs: 14_000
            )
        )
        let xtReport = XTUnifiedDoctorReport(
            schemaVersion: XTUnifiedDoctorReport.currentSchemaVersion,
            generatedAtMs: 1_741_300_000,
            overallState: .ready,
            overallSummary: "Session runtime is ready",
            readyForFirstTask: true,
            currentFailureCode: "",
            currentFailureIssue: nil,
            configuredModelRoles: 1,
            availableModelCount: 1,
            loadedModelCount: 1,
            currentSessionID: "session-cache-2",
            currentRoute: XTUnifiedDoctorRouteSnapshot(
                transportMode: "paired",
                routeLabel: "paired-local",
                pairingPort: 50052,
                grpcPort: 50051,
                internetHost: ""
            ),
            sections: [
                XTUnifiedDoctorSection(
                    kind: .sessionRuntimeReadiness,
                    state: .ready,
                    headline: "Session runtime is ready",
                    summary: "Structured remote snapshot cache projections should win.",
                    nextStep: "Start the task.",
                    repairEntry: .xtDiagnostics,
                    detailLines: [
                        "project_memory_v1_source=detail_line_only",
                        "memory_v1_freshness=stale",
                        "memory_v1_cache_hit=false",
                        "memory_v1_remote_snapshot_cache_scope=mode=detail_line project_id=proj-legacy",
                        "memory_v1_remote_snapshot_cached_at_ms=1774000000000",
                        "memory_v1_remote_snapshot_age_ms=9999",
                        "memory_v1_remote_snapshot_ttl_remaining_ms=1",
                        "memory_source=detail_supervisor",
                        "memory_freshness=detail_freshness",
                        "memory_cache_hit=true",
                        "remote_snapshot_cache_scope=mode=detail_line project_id=(none)",
                        "remote_snapshot_cached_at_ms=1774000005000",
                        "remote_snapshot_age_ms=8888",
                        "remote_snapshot_ttl_remaining_ms=2"
                    ],
                    projectRemoteSnapshotCacheProjection: projectProjection,
                    supervisorRemoteSnapshotCacheProjection: supervisorProjection
                )
            ],
            consumedContracts: ["xt.ui_surface_state_contract.v1", XTUnifiedDoctorReportContract.frozen.schemaVersion],
            reportPath: "/tmp/xt_unified_doctor_report_cache_structured.json"
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: "/tmp/xhub_doctor_output_xt_cache_structured.json"
        )

        let check = try #require(bundle.checks.first)
        #expect(check.projectRemoteSnapshotCacheSnapshot?.source == "hub_snapshot_plus_local_overlay")
        #expect(check.projectRemoteSnapshotCacheSnapshot?.freshness == "ttl_cache")
        #expect(check.projectRemoteSnapshotCacheSnapshot?.cacheHit == true)
        #expect(check.projectRemoteSnapshotCacheSnapshot?.scope == "mode=project_chat project_id=proj-structured")
        #expect(check.projectRemoteSnapshotCacheSnapshot?.cachedAtMs == 1_774_100_000_000)
        #expect(check.projectRemoteSnapshotCacheSnapshot?.ageMs == 2_000)
        #expect(check.projectRemoteSnapshotCacheSnapshot?.ttlRemainingMs == 13_000)
        #expect(check.projectRemoteSnapshotCacheSnapshot?.upstreamTruthClass == "hub_durable_truth")
        #expect(check.projectRemoteSnapshotCacheSnapshot?.cacheRole == "xt_remote_snapshot_ttl_cache")
        #expect(check.projectRemoteSnapshotCacheSnapshot?.provenanceLabel == "hub_durable_truth_via_xt_ttl_cache")
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.source == "hub")
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.freshness == "fresh_local_ipc")
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.cacheHit == false)
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.scope == "mode=supervisor_orchestration project_id=(none)")
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.cachedAtMs == 1_774_100_005_000)
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.ageMs == 1_000)
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.ttlRemainingMs == 14_000)
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.upstreamTruthClass == "hub_durable_truth")
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.cacheRole == "xt_remote_snapshot_ttl_cache")
        #expect(check.supervisorRemoteSnapshotCacheSnapshot?.provenanceLabel == "hub_durable_truth_fresh_fetch")
    }

    @Test
    func projectsProjectAutomationContinuitySnapshotFromRecoveryAwareDetailLines() throws {
        let verificationContract = XTAutomationVerificationContract(
            expectedState: "post_change_verification_passes",
            verifyMethod: "project_verify_commands",
            retryPolicy: "retry_failed_verify_commands_within_budget",
            holdPolicy: "hold_for_retry_or_replan",
            evidenceRequired: true,
            triggerActionIDs: ["action-verify"],
            verifyCommands: ["swift test --filter SmokeTests"]
        )
        let retryVerificationContract = XTAutomationVerificationContract(
            expectedState: "post_change_verification_passes",
            verifyMethod: "project_verify_commands_override",
            retryPolicy: "manual_retry_or_replan",
            holdPolicy: "hold_for_retry_or_replan",
            evidenceRequired: false,
            triggerActionIDs: ["retry-action-verify"],
            verifyCommands: ["swift test --filter RetrySmokeTests"]
        )
        let xtReport = XTUnifiedDoctorReport(
            schemaVersion: XTUnifiedDoctorReport.currentSchemaVersion,
            generatedAtMs: 1_741_300_000,
            overallState: .ready,
            overallSummary: "Session runtime is ready",
            readyForFirstTask: true,
            currentFailureCode: "",
            currentFailureIssue: nil,
            configuredModelRoles: 1,
            availableModelCount: 1,
            loadedModelCount: 1,
            currentSessionID: "session-automation-memory-1",
            currentRoute: XTUnifiedDoctorRouteSnapshot(
                transportMode: "paired",
                routeLabel: "paired-local",
                pairingPort: 50052,
                grpcPort: 50051,
                internetHost: ""
            ),
            sections: [
                XTUnifiedDoctorSection(
                    kind: .sessionRuntimeReadiness,
                    state: .ready,
                    headline: "Session runtime is ready",
                    summary: "Recovery-aware project continuity is present.",
                    nextStep: "Resume the active run.",
                    repairEntry: .xtDiagnostics,
                    detailLines: [
                        "project_memory_v1_source=hub_snapshot_plus_local_overlay",
                        "project_memory_v1_source_class=hub_snapshot_plus_local_overlay",
                        "memory_v1_freshness=ttl_cache",
                        "memory_v1_cache_hit=true",
                        "memory_v1_remote_snapshot_cache_scope=mode=project_chat project_id=proj-alpha",
                        "memory_v1_remote_snapshot_cached_at_ms=1774000000000",
                        "memory_v1_remote_snapshot_age_ms=6000",
                        "memory_v1_remote_snapshot_ttl_remaining_ms=9000",
                        "project_memory_automation_context_source=checkpoint+execution_report+retry_package",
                        "project_memory_automation_run_id=run-step-memory-1",
                        "project_memory_automation_run_state=blocked",
                        "project_memory_automation_attempt=2",
                        "project_memory_automation_retry_after_seconds=45",
                        "project_memory_automation_recovery_selection=latest_recoverable_unsuperseded",
                        "project_memory_automation_recovery_reason=latest_visible_retry_wait",
                        "project_memory_automation_recovery_decision=hold",
                        "project_memory_automation_recovery_hold_reason=retry_after_not_elapsed",
                        "project_memory_automation_recovery_retry_after_remaining_seconds=25",
                        "project_memory_automation_current_step_id=step-verify",
                        "project_memory_automation_current_step_title=Verify focused smoke tests",
                        "project_memory_automation_current_step_state=retry_wait",
                        #"project_memory_automation_verification_contract_json={"expected_state":"post_change_verification_passes","verify_method":"project_verify_commands","retry_policy":"retry_failed_verify_commands_within_budget","hold_policy":"hold_for_retry_or_replan","evidence_required":true,"trigger_action_ids":["action-verify"],"verify_commands":["swift test --filter SmokeTests"]}"#,
                        "project_memory_automation_verification_present=true",
                        "project_memory_automation_blocker_present=true",
                        "project_memory_automation_retry_reason_present=true",
                        #"project_memory_automation_retry_verification_contract_json={"expected_state":"post_change_verification_passes","verify_method":"project_verify_commands_override","retry_policy":"manual_retry_or_replan","hold_policy":"hold_for_retry_or_replan","evidence_required":false,"trigger_action_ids":["retry-action-verify"],"verify_commands":["swift test --filter RetrySmokeTests"]}"#
                    ]
                )
            ],
            consumedContracts: ["xt.ui_surface_state_contract.v1", XTUnifiedDoctorReportContract.frozen.schemaVersion],
            reportPath: "/tmp/xhub_doctor_output_project_automation_continuity.json"
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: "/tmp/xhub_doctor_output_project_automation_continuity_bundle.json"
        )

        let check = try #require(bundle.checks.first)
        #expect(check.projectAutomationContinuitySnapshot?.continuitySourceClass == "local_runtime_rehydration_with_hub_durable_truth_via_xt_ttl_cache")
        #expect(check.projectAutomationContinuitySnapshot?.automationContextSource == "checkpoint+execution_report+retry_package")
        #expect(check.projectAutomationContinuitySnapshot?.memorySource == "hub_snapshot_plus_local_overlay")
        #expect(check.projectAutomationContinuitySnapshot?.memorySourceClass == "hub_snapshot_plus_local_overlay")
        #expect(check.projectAutomationContinuitySnapshot?.memoryFreshness == "ttl_cache")
        #expect(check.projectAutomationContinuitySnapshot?.memoryCacheHit == true)
        #expect(check.projectAutomationContinuitySnapshot?.remoteSnapshotProvenanceLabel == "hub_durable_truth_via_xt_ttl_cache")
        #expect(check.projectAutomationContinuitySnapshot?.runID == "run-step-memory-1")
        #expect(check.projectAutomationContinuitySnapshot?.runState == "blocked")
        #expect(check.projectAutomationContinuitySnapshot?.attempt == 2)
        #expect(check.projectAutomationContinuitySnapshot?.retryAfterSeconds == 45)
        #expect(check.projectAutomationContinuitySnapshot?.recoverySelection == "latest_recoverable_unsuperseded")
        #expect(check.projectAutomationContinuitySnapshot?.recoveryReason == "latest_visible_retry_wait")
        #expect(check.projectAutomationContinuitySnapshot?.recoveryDecision == "hold")
        #expect(check.projectAutomationContinuitySnapshot?.recoveryHoldReason == "retry_after_not_elapsed")
        #expect(check.projectAutomationContinuitySnapshot?.recoveryRetryAfterRemainingSeconds == 25)
        #expect(check.projectAutomationContinuitySnapshot?.currentStepID == "step-verify")
        #expect(check.projectAutomationContinuitySnapshot?.currentStepTitle == "Verify focused smoke tests")
        #expect(check.projectAutomationContinuitySnapshot?.currentStepState == "retry_wait")
        #expect(check.projectAutomationContinuitySnapshot?.verificationContract == verificationContract)
        #expect(check.projectAutomationContinuitySnapshot?.retryVerificationContract == retryVerificationContract)
        #expect(check.projectAutomationContinuitySnapshot?.verificationPresent == true)
        #expect(check.projectAutomationContinuitySnapshot?.blockerPresent == true)
        #expect(check.projectAutomationContinuitySnapshot?.retryReasonPresent == true)
    }

    @Test
    func projectsLocalFallbackContinuityClassWhenHubSnapshotIsAbsent() throws {
        let xtReport = XTUnifiedDoctorReport(
            schemaVersion: XTUnifiedDoctorReport.currentSchemaVersion,
            generatedAtMs: 1_741_300_000,
            overallState: .ready,
            overallSummary: "Session runtime is ready",
            readyForFirstTask: true,
            currentFailureCode: "",
            currentFailureIssue: nil,
            configuredModelRoles: 1,
            availableModelCount: 1,
            loadedModelCount: 1,
            currentSessionID: "session-automation-memory-2",
            currentRoute: XTUnifiedDoctorRouteSnapshot(
                transportMode: "local",
                routeLabel: "local-only",
                pairingPort: 50052,
                grpcPort: 50051,
                internetHost: ""
            ),
            sections: [
                XTUnifiedDoctorSection(
                    kind: .sessionRuntimeReadiness,
                    state: .ready,
                    headline: "Session runtime is ready",
                    summary: "Local fallback continuity is present.",
                    nextStep: "Resume with local fallback.",
                    repairEntry: .xtDiagnostics,
                    detailLines: [
                        "project_memory_v1_source=local_fallback",
                        "project_memory_v1_source_class=local_fallback",
                        "project_memory_automation_context_source=checkpoint",
                        "project_memory_automation_run_id=run-local-fallback-1"
                    ]
                )
            ],
            consumedContracts: ["xt.ui_surface_state_contract.v1", XTUnifiedDoctorReportContract.frozen.schemaVersion],
            reportPath: "/tmp/xhub_doctor_output_project_automation_local_fallback.json"
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: "/tmp/xhub_doctor_output_project_automation_local_fallback_bundle.json"
        )

        let check = try #require(bundle.checks.first)
        #expect(check.projectRemoteSnapshotCacheSnapshot == nil)
        #expect(check.projectAutomationContinuitySnapshot?.continuitySourceClass == "local_runtime_rehydration_with_xt_local_fallback")
        #expect(check.projectAutomationContinuitySnapshot?.automationContextSource == "checkpoint")
        #expect(check.projectAutomationContinuitySnapshot?.memorySource == "local_fallback")
        #expect(check.projectAutomationContinuitySnapshot?.memorySourceClass == "local_fallback")
        #expect(check.projectAutomationContinuitySnapshot?.remoteSnapshotProvenanceLabel == nil)
        #expect(check.projectAutomationContinuitySnapshot?.runID == "run-local-fallback-1")
    }

    @Test
    func mapsFirstPairCompletionProofIntoGenericDoctorBundle() {
        var xtReport = sampleXTUnifiedDoctorReport(
            sourceReportPath: "/tmp/xt_unified_doctor_report.json"
        )
        xtReport.firstPairCompletionProofSnapshot = sampleFirstPairCompletionProofSnapshot(
            readiness: .localReady,
            remoteShadowSmokeStatus: .notRun,
            remoteShadowSmokePassed: false
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: "/tmp/xhub_doctor_output_xt.json"
        )

        #expect(bundle.firstPairCompletionProofSnapshot?.readiness == XTPairedRouteReadiness.localReady.rawValue)
        #expect(bundle.firstPairCompletionProofSnapshot?.sameLanVerified == true)
        #expect(bundle.firstPairCompletionProofSnapshot?.stableRemoteRoutePresent == true)
        #expect(bundle.firstPairCompletionProofSnapshot?.remoteShadowSmokeStatus == XTFirstPairRemoteShadowSmokeStatus.notRun.rawValue)
        #expect(bundle.firstPairCompletionProofSnapshot?.remoteShadowSmokePassed == false)
        #expect(bundle.firstPairCompletionProofSnapshot?.remoteShadowSmokeSource == nil)
    }

    @Test
    func writesXTFirstPairCompletionProofSidecarWhenStructuredSnapshotIsPresent() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-doctor-output-first-pair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.firstPairCompletionProofSnapshot = sampleFirstPairCompletionProofSnapshot(
            readiness: .remoteDegraded,
            remoteShadowSmokeStatus: .failed,
            remoteShadowSmokePassed: false
        )

        let reportURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: tempRoot)
        let bundle = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: reportURL.path
        )
        XHubDoctorOutputStore.writeReport(bundle, to: reportURL)

        let sidecarURL = XHubDoctorOutputStore.defaultXTFirstPairCompletionProofURL(workspaceRoot: tempRoot)
        let data = try Data(contentsOf: sidecarURL)
        let decoded = try JSONDecoder().decode(XHubDoctorOutputFirstPairCompletionProofSnapshot.self, from: data)

        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))
        #expect(decoded.readiness == XTPairedRouteReadiness.remoteDegraded.rawValue)
        #expect(decoded.cachedReconnectSmokePassed == true)
        #expect(decoded.remoteShadowSmokeStatus == XTFirstPairRemoteShadowSmokeStatus.failed.rawValue)
        #expect(decoded.remoteShadowSmokePassed == false)
        #expect(decoded.remoteShadowSmokeSource == XTRemoteShadowReconnectSmokeSource.dedicatedStableRemoteProbe.rawValue)
        #expect(decoded.remoteShadowRoute == HubRemoteRoute.internet.rawValue)
        #expect(decoded.remoteShadowReasonCode == "grpc_unavailable")
        #expect(decoded.remoteShadowSummary == "stable remote route shadow verification failed.")
    }

    @Test
    func writesXTPairedRouteSetSidecarWhenStructuredSnapshotIsPresent() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-doctor-output-paired-route-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.pairedRouteSetSnapshot = samplePairedRouteSetSnapshot(
            readiness: .localReady,
            readinessReasonCode: "local_pairing_ready_remote_unverified",
            summaryLine: "当前已完成同网首配，但正式异网入口仍未完成验证。"
        )

        let reportURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: tempRoot)
        let bundle = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: reportURL.path
        )
        XHubDoctorOutputStore.writeReport(bundle, to: reportURL)

        let sidecarURL = XHubDoctorOutputStore.defaultXTPairedRouteSetURL(workspaceRoot: tempRoot)
        let data = try Data(contentsOf: sidecarURL)
        let decoded = try JSONDecoder().decode(XHubDoctorOutputPairedRouteSetSnapshot.self, from: data)

        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))
        #expect(decoded.schemaVersion == XTPairedRouteSetSnapshot.currentSchemaVersion)
        #expect(decoded.readiness == XTPairedRouteReadiness.localReady.rawValue)
        #expect(decoded.readinessReasonCode == "local_pairing_ready_remote_unverified")
        #expect(decoded.summaryLine == "当前已完成同网首配，但正式异网入口仍未完成验证。")
        #expect(decoded.stableRemoteRoute?.host == "hub.tailnet.example")
        #expect(decoded.stableRemoteRoute?.routeKind == XTPairedRouteTargetKind.internet.rawValue)
        #expect(decoded.cachedReconnectSmokeStatus == "succeeded")
        #expect(decoded.cachedReconnectSmokeSummary == "same-LAN cached reconnect succeeded")
    }

    @Test
    func writesXTConnectivityIncidentSidecarWhenStructuredSnapshotIsPresent() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-doctor-output-connectivity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.connectivityIncidentSnapshot = XTHubConnectivityIncidentSnapshot(
            incidentState: .blocked,
            reasonCode: "pairing_approval_timeout",
            summaryLine: "saved remote route is blocked by pairing/identity repair; waiting for repair.",
            trigger: .networkChanged,
            decisionReasonCode: "remote_route_blocked_waiting_for_repair",
            pairedRouteReadiness: .remoteBlocked,
            stableRemoteRouteHost: "hub.tailnet.example",
            currentFailureCode: "pairing_approval_timeout",
            currentPath: XTHubConnectivityIncidentPathSnapshot(
                HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: true,
                    usesCellular: false,
                    isExpensive: false,
                    isConstrained: false
                )
            ),
            lastUpdatedAtMs: 1_741_300_016_000
        )

        let reportURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: tempRoot)
        let bundle = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: reportURL.path
        )
        XHubDoctorOutputStore.writeReport(bundle, to: reportURL)

        let sidecarURL = XHubDoctorOutputStore.defaultXTConnectivityIncidentSnapshotURL(workspaceRoot: tempRoot)
        let loaded = XHubDoctorOutputStore.loadXTConnectivityIncidentSnapshot(workspaceRoot: tempRoot)

        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))
        #expect(loaded?.incidentState == "blocked")
        #expect(loaded?.reasonCode == "pairing_approval_timeout")
        #expect(loaded?.decisionReasonCode == "remote_route_blocked_waiting_for_repair")
        #expect(loaded?.pairedRouteReadiness == "remote_blocked")
        #expect(loaded?.stableRemoteRouteHost == "hub.tailnet.example")
    }

    @Test
    func writesXTConnectivityIncidentHistorySidecarAndDedupesEquivalentSnapshots() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-doctor-output-connectivity-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: tempRoot)

        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.connectivityIncidentSnapshot = XTHubConnectivityIncidentSnapshot(
            incidentState: .retrying,
            reasonCode: "grpc_unavailable",
            summaryLine: "remote route not active; retrying degraded remote route ...",
            trigger: .backgroundKeepalive,
            decisionReasonCode: "retry_degraded_remote_route",
            pairedRouteReadiness: .remoteDegraded,
            stableRemoteRouteHost: "hub.tailnet.example",
            currentFailureCode: "grpc_unavailable",
            currentPath: XTHubConnectivityIncidentPathSnapshot(
                HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: false,
                    usesCellular: true,
                    isExpensive: true,
                    isConstrained: false
                )
            ),
            lastUpdatedAtMs: 1_741_300_017_000
        )
        XHubDoctorOutputStore.writeReport(
            XHubDoctorOutputReport.xtReadinessBundle(from: xtReport, outputPath: reportURL.path),
            to: reportURL
        )

        xtReport.connectivityIncidentSnapshot?.trigger = .networkChanged
        xtReport.connectivityIncidentSnapshot?.summaryLine = "remote route still degraded; retry continues."
        xtReport.connectivityIncidentSnapshot?.lastUpdatedAtMs = 1_741_300_018_000
        XHubDoctorOutputStore.writeReport(
            XHubDoctorOutputReport.xtReadinessBundle(from: xtReport, outputPath: reportURL.path),
            to: reportURL
        )

        xtReport.connectivityIncidentSnapshot = XTHubConnectivityIncidentSnapshot(
            incidentState: .none,
            reasonCode: "remote_route_active",
            summaryLine: "validated remote route is active; no connectivity repair is needed.",
            trigger: .backgroundKeepalive,
            decisionReasonCode: "remote_route_already_active",
            pairedRouteReadiness: .remoteReady,
            stableRemoteRouteHost: "hub.tailnet.example",
            currentFailureCode: nil,
            currentPath: XTHubConnectivityIncidentPathSnapshot(
                HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: false,
                    usesCellular: true,
                    isExpensive: true,
                    isConstrained: false
                )
            ),
            lastUpdatedAtMs: 1_741_300_019_000
        )
        XHubDoctorOutputStore.writeReport(
            XHubDoctorOutputReport.xtReadinessBundle(from: xtReport, outputPath: reportURL.path),
            to: reportURL
        )

        let sidecarURL = XHubDoctorOutputStore.defaultXTConnectivityIncidentHistoryURL(workspaceRoot: tempRoot)
        let history = XHubDoctorOutputStore.loadXTConnectivityIncidentHistory(workspaceRoot: tempRoot)

        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))
        #expect(history?.schemaVersion == XHubDoctorOutputConnectivityIncidentHistoryReport.currentSchemaVersion)
        #expect(history?.entries.count == 2)
        #expect(history?.entries.first?.incidentState == "retrying")
        #expect(history?.entries.first?.trigger == XTHubConnectivityDecisionTrigger.networkChanged.rawValue)
        #expect(history?.entries.first?.summaryLine == "remote route still degraded; retry continues.")
        #expect(history?.entries.first?.lastUpdatedAtMs == 1_741_300_018_000)
        #expect(history?.entries.last?.incidentState == "none")
        #expect(history?.entries.last?.reasonCode == "remote_route_active")
    }

    @Test
    func copiesXTConnectivityRepairLedgerAlongsideArbitraryDoctorExportOutput() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-doctor-output-connectivity-repair-\(UUID().uuidString)", isDirectory: true)
        let outputDir = tempRoot.appendingPathComponent("doctor_bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let waitingIncident = XTHubConnectivityIncidentSnapshot(
            incidentState: .waiting,
            reasonCode: "local_pairing_ready",
            summaryLine: "waiting to return to LAN or add a formal remote route.",
            trigger: .backgroundKeepalive,
            decisionReasonCode: "waiting_for_same_lan_or_formal_remote_route",
            pairedRouteReadiness: .localReady,
            stableRemoteRouteHost: nil,
            currentFailureCode: nil,
            currentPath: nil,
            lastUpdatedAtMs: 1_741_300_040_000
        )
        XTConnectivityRepairLedgerStore.append(
            XTConnectivityRepairLedgerStore.deferredEntry(
                trigger: .backgroundKeepalive,
                incidentSnapshot: waitingIncident
            )!,
            workspaceRoot: tempRoot
        )

        let recoveredIncident = XTHubConnectivityIncidentSnapshot(
            incidentState: .none,
            reasonCode: "remote_route_active",
            summaryLine: "validated remote route is active; no connectivity repair is needed.",
            trigger: .backgroundKeepalive,
            decisionReasonCode: "remote_route_already_active",
            pairedRouteReadiness: .remoteReady,
            stableRemoteRouteHost: "hub.tailnet.example",
            currentFailureCode: nil,
            currentPath: nil,
            lastUpdatedAtMs: 1_741_300_041_000
        )
        XTConnectivityRepairLedgerStore.append(
            XTConnectivityRepairLedgerStore.outcomeEntry(
                trigger: .backgroundKeepalive,
                owner: .xtRuntime,
                allowBootstrap: false,
                decisionReasonCode: "retry_degraded_remote_route",
                report: HubRemoteConnectReport(
                    ok: true,
                    route: .internet,
                    summary: "remote route verified",
                    logLines: [],
                    reasonCode: nil
                ),
                incidentSnapshot: recoveredIncident,
                recordedAtMs: 1_741_300_041_000
            ),
            workspaceRoot: tempRoot
        )

        let sourceReportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let outputReportURL = outputDir.appendingPathComponent("xhub_doctor_output_xt.json")
        let xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: sourceReportURL.path)
        let bundle = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: outputReportURL.path,
            surface: .xtExport
        )

        XHubDoctorOutputStore.writeReport(bundle, to: outputReportURL, xtWorkspaceRoot: tempRoot)

        let sidecarURL = XHubDoctorOutputStore.xtConnectivityRepairLedgerURL(alongside: outputReportURL)
        let copiedLedger = XHubDoctorOutputStore.loadXTConnectivityRepairLedger(alongside: outputReportURL)

        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))
        #expect(copiedLedger?.schemaVersion == XTConnectivityRepairLedgerSnapshot.currentSchemaVersion)
        #expect(copiedLedger?.entries.count == 2)
        #expect(copiedLedger?.entries.first?.action == .waitForRouteReady)
        #expect(copiedLedger?.entries.first?.result == .deferred)
        #expect(copiedLedger?.entries.last?.action == .remoteReconnect)
        #expect(copiedLedger?.entries.last?.result == .succeeded)
        #expect(copiedLedger?.entries.last?.finalRoute == HubRemoteRoute.internet.rawValue)
    }

    @Test
    func decodesLegacyRouteSnapshotWithoutStructuredHostFields() throws {
        let legacyJSON = """
        {
          "transport_mode": "grpc",
          "route_label": "paired-remote",
          "pairing_port": 50054,
          "grpc_port": 50053,
          "internet_host": "hub.example.com"
        }
        """

        let snapshot = try JSONDecoder().decode(
            XHubDoctorOutputRouteSnapshot.self,
            from: Data(legacyJSON.utf8)
        )

        #expect(snapshot.internetHostKind == "stable_named")
        #expect(snapshot.internetHostScope == nil)
        #expect(snapshot.remoteEntryPosture == "stable_named_entry")
        #expect(snapshot.remoteEntrySummaryLine == "正式异网入口 · host=hub.example.com")
    }

    @Test
    func preservesVoicePlaybackDoctorDetailsInGenericBundle() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections.append(
            XTUnifiedDoctorSection(
                kind: .voicePlaybackReadiness,
                state: .inProgress,
                headline: "首选 Hub 语音包暂未就绪",
                summary: "由于所选 Hub 语音包当前不在 Hub Library 中，Supervisor 播报暂时回退到了系统语音。",
                nextStep: "把首选语音包下载或导入到 Hub，或者把播放来源切回自动。",
                repairEntry: .homeSupervisor,
                detailLines: [
                    "requested_playback_source=hub_voice_pack",
                    "resolved_playback_source=system_speech",
                    "preferred_voice_pack_id=hub.voice.zh.warm",
                    "fallback_from=hub_voice_pack"
                ]
            )
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.voicePlaybackReadiness.rawValue }

        #expect(check?.status == .warn)
        #expect(check?.message.contains("回退到了系统语音") == true)
        #expect(check?.detailLines.contains("preferred_voice_pack_id=hub.voice.zh.warm") == true)
        #expect(check?.detailLines.contains("fallback_from=hub_voice_pack") == true)
    }

    @Test
    func preservesWakeAndTalkPermissionDoctorDetailsInGenericBundle() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections.append(
            XTUnifiedDoctorSection(
                kind: .wakeProfileReadiness,
                state: .permissionDenied,
                headline: "唤醒配置被语音识别权限阻塞",
                summary: "在 macOS 系统设置里授予语音识别权限之前，唤醒和实时收音会继续保持关闭。",
                nextStep: "请先在 macOS 系统设置中授予语音识别权限，然后刷新语音运行时。",
                repairEntry: .systemPermissions,
                detailLines: [
                    "microphone_authorization=authorized",
                    "speech_recognition_authorization=denied"
                ]
            )
        )
        xtReport.sections.append(
            XTUnifiedDoctorSection(
                kind: .talkLoopReadiness,
                state: .permissionDenied,
                headline: "对话链路被语音识别权限阻塞",
                summary: "在 macOS 系统设置里恢复语音识别权限之前，连续语音对话仍然不可用。",
                nextStep: "请先在 macOS 系统设置中授予语音识别权限，然后刷新语音运行时。",
                repairEntry: .systemPermissions,
                detailLines: [
                    "microphone_authorization=authorized",
                    "speech_recognition_authorization=denied"
                ]
            )
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let wakeCheck = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.wakeProfileReadiness.rawValue }
        let talkCheck = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.talkLoopReadiness.rawValue }
        let wakeStep = bundle.nextSteps.first { $0.stepID == XTUnifiedDoctorSectionKind.wakeProfileReadiness.rawValue }

        #expect(wakeCheck?.status == .fail)
        #expect(wakeCheck?.severity == .critical)
        #expect(wakeCheck?.repairDestinationRef == UITroubleshootDestination.systemPermissions.rawValue)
        #expect(wakeCheck?.detailLines.contains("speech_recognition_authorization=denied") == true)
        #expect(talkCheck?.status == .fail)
        #expect(talkCheck?.severity == .critical)
        #expect(wakeStep?.kind == .reviewPermissions)
        #expect(wakeStep?.destinationRef == UITroubleshootDestination.systemPermissions.rawValue)
    }

    @Test
    func projectsFreshPairReconnectSmokeSnapshotFromHubReachabilityDetailLines() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[0] = XTUnifiedDoctorSection(
            kind: .hubReachability,
            state: .diagnosticRequired,
            headline: "首次配对已完成，但缓存路由验证失败",
            summary: "最近一次手动一键连接后的缓存路由验证失败。",
            nextStep: "修复远端入口后重试。",
            repairEntry: .xtPairHub,
            detailLines: [
                "transport=grpc",
                "route=internet",
                "fresh_pair_reconnect_smoke status=failed source=manual_one_click_setup route=none triggered_at_ms=1741300010000 completed_at_ms=1741300011000",
                "fresh_pair_reconnect_smoke_reason=grpc_unavailable",
                "fresh_pair_reconnect_smoke_summary=grpc_unavailable"
            ]
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.hubReachability.rawValue }

        #expect(check?.freshPairReconnectSmokeSnapshot?.source == XTFreshPairReconnectSmokeSource.manualOneClickSetup.rawValue)
        #expect(check?.freshPairReconnectSmokeSnapshot?.status == XTFreshPairReconnectSmokeStatus.failed.rawValue)
        #expect(check?.freshPairReconnectSmokeSnapshot?.route == HubRemoteRoute.none.rawValue)
        #expect(check?.freshPairReconnectSmokeSnapshot?.reasonCode == "grpc_unavailable")
        #expect(check?.freshPairReconnectSmokeSnapshot?.summary == "grpc_unavailable")
    }

    @Test
    func projectsPairedRouteSetSnapshotIntoGenericDoctorBundle() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.pairedRouteSetSnapshot = XTPairedRouteSetSnapshot(
            readiness: .remoteReady,
            readinessReasonCode: "cached_remote_reconnect_smoke_verified",
            summaryLine: "正式异网入口已验证，切网后可继续重连。",
            hubInstanceID: "hub_test_123",
            activeRoute: XTPairedRouteTargetSnapshot(
                routeKind: .internet,
                host: "hub.tailnet.example",
                pairingPort: 50052,
                grpcPort: 50051,
                hostKind: "stable_named",
                source: .activeConnection
            ),
            lanRoute: XTPairedRouteTargetSnapshot(
                routeKind: .lan,
                host: "192.168.0.10",
                pairingPort: 50052,
                grpcPort: 50051,
                hostKind: "raw_ip",
                source: .cachedProfileHost
            ),
            stableRemoteRoute: XTPairedRouteTargetSnapshot(
                routeKind: .internet,
                host: "hub.tailnet.example",
                pairingPort: 50052,
                grpcPort: 50051,
                hostKind: "stable_named",
                source: .cachedProfileInternetHost
            ),
            lastKnownGoodRoute: XTPairedRouteTargetSnapshot(
                routeKind: .internet,
                host: "hub.tailnet.example",
                pairingPort: 50052,
                grpcPort: 50051,
                hostKind: "stable_named",
                source: .freshPairReconnectSmoke
            ),
            cachedReconnectSmokeStatus: "succeeded",
            cachedReconnectSmokeReasonCode: nil,
            cachedReconnectSmokeSummary: "remote reconnect succeeded"
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)

        #expect(bundle.pairedRouteSetSnapshot?.schemaVersion == XTPairedRouteSetSnapshot.currentSchemaVersion)
        #expect(bundle.pairedRouteSetSnapshot?.readiness == "remote_ready")
        #expect(bundle.pairedRouteSetSnapshot?.readinessReasonCode == "cached_remote_reconnect_smoke_verified")
        #expect(bundle.pairedRouteSetSnapshot?.summaryLine == "正式异网入口已验证，切网后可继续重连。")
        #expect(bundle.pairedRouteSetSnapshot?.stableRemoteRoute?.host == "hub.tailnet.example")
        #expect(bundle.pairedRouteSetSnapshot?.stableRemoteRoute?.routeKind == "internet")
        #expect(bundle.pairedRouteSetSnapshot?.stableRemoteRoute?.source == "cached_profile_internet_host")
        #expect(bundle.pairedRouteSetSnapshot?.cachedReconnectSmokeStatus == "succeeded")
    }

    @Test
    func projectsConnectivityIncidentSnapshotIntoGenericDoctorBundle() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.connectivityIncidentSnapshot = XTHubConnectivityIncidentSnapshot(
            incidentState: .waiting,
            reasonCode: "local_pairing_ready",
            summaryLine: "current network is not same-LAN; waiting to return to LAN or add a formal remote route.",
            trigger: .backgroundKeepalive,
            decisionReasonCode: "waiting_for_same_lan_or_formal_remote_route",
            pairedRouteReadiness: .localReady,
            stableRemoteRouteHost: nil,
            currentFailureCode: nil,
            currentPath: XTHubConnectivityIncidentPathSnapshot(
                HubNetworkPathFingerprint(
                    statusKey: "satisfied",
                    usesWiFi: false,
                    usesWiredEthernet: false,
                    usesCellular: true,
                    isExpensive: true,
                    isConstrained: false
                )
            ),
            lastUpdatedAtMs: 1_741_300_015_000,
            selectedRoute: .managedTunnelFallback,
            candidatesTried: [.stableNamedRemote, .managedTunnelFallback],
            handoffReason: "stable_named_remote_cooldown",
            cooldownApplied: true,
            routeStatuses: [
                XTHubConnectivityRouteStatusSnapshot(
                    route: .stableNamedRemote,
                    healthScore: 24,
                    cooldownUntilMs: 1_741_300_045_000,
                    recentSuccessCount: 0,
                    recentFailureCount: 2
                ),
                XTHubConnectivityRouteStatusSnapshot(
                    route: .managedTunnelFallback,
                    healthScore: 86,
                    cooldownUntilMs: nil,
                    recentSuccessCount: 2,
                    recentFailureCount: 0
                )
            ]
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)

        #expect(bundle.connectivityIncidentSnapshot?.schemaVersion == XTHubConnectivityIncidentSnapshot.currentSchemaVersion)
        #expect(bundle.connectivityIncidentSnapshot?.incidentState == "waiting")
        #expect(bundle.connectivityIncidentSnapshot?.reasonCode == "local_pairing_ready")
        #expect(bundle.connectivityIncidentSnapshot?.decisionReasonCode == "waiting_for_same_lan_or_formal_remote_route")
        #expect(bundle.connectivityIncidentSnapshot?.pairedRouteReadiness == "local_ready")
        #expect(bundle.connectivityIncidentSnapshot?.currentPath?.statusKey == "satisfied")
        #expect(bundle.connectivityIncidentSnapshot?.currentPath?.usesCellular == true)
        #expect(bundle.connectivityIncidentSnapshot?.lastUpdatedAtMs == 1_741_300_015_000)
        #expect(bundle.connectivityIncidentSnapshot?.selectedRoute == "managed_tunnel_fallback")
        #expect(bundle.connectivityIncidentSnapshot?.candidatesTried == ["stable_named_remote", "managed_tunnel_fallback"])
        #expect(bundle.connectivityIncidentSnapshot?.handoffReason == "stable_named_remote_cooldown")
        #expect(bundle.connectivityIncidentSnapshot?.cooldownApplied == true)
        #expect(bundle.connectivityIncidentSnapshot?.routeStatuses?.first?.route == "stable_named_remote")
        #expect(bundle.connectivityIncidentSnapshot?.routeStatuses?.first?.cooldownUntilMs == 1_741_300_045_000)
    }

    @Test
    func preservesSupervisorVoiceSmokePhaseDetailsInGenericBundle() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections.append(
            XTUnifiedDoctorSection(
                kind: .voicePlaybackReadiness,
                state: .diagnosticRequired,
                headline: "Supervisor 语音自检显示：Hub 简报播报阶段未通过",
                summary: "最近一次 Supervisor 语音自检卡在Hub 简报播报阶段：授权批准回调未记录。listening did not resume",
                nextStep: "先在 XT Diagnostics 重跑 Supervisor 语音自检；如果仍卡在 Hub 简报播报阶段，再核对 brief projection、TTS 播报和播报后恢复监听的链路。",
                repairEntry: .xtDiagnostics,
                detailLines: [
                    "voice_smoke_status=fail",
                    "voice_smoke_checks=7/9",
                    "voice_smoke_phase=brief_playback",
                    "voice_smoke_phase_status=failed",
                    "voice_smoke_failed_phase=brief_playback",
                    "voice_smoke_failed_check=brief_resumed_listening",
                    "voice_smoke_failed_detail=listening did not resume"
                ]
            )
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.voicePlaybackReadiness.rawValue }

        #expect(check?.status == .fail)
        #expect(check?.severity == .error)
        #expect(check?.message.contains("Hub 简报播报阶段") == true)
        #expect(check?.detailLines.contains("voice_smoke_phase=brief_playback") == true)
        #expect(check?.detailLines.contains("voice_smoke_phase_status=failed") == true)
        #expect(check?.detailLines.contains("voice_smoke_failed_check=brief_resumed_listening") == true)
    }

    @Test
    func preservesStructuredProjectContextSummaryInGenericBundle() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is healthy and ready for project execution.",
            nextStep: "Open the active project and start the next task.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready",
                "project_context_diagnostics_source=latest_coder_usage",
                "project_context_project=Snake",
                "recent_project_dialogue_profile=extended_40_pairs",
                "recent_project_dialogue_selected_pairs=18",
                "recent_project_dialogue_floor_pairs=8",
                "recent_project_dialogue_floor_satisfied=true",
                "recent_project_dialogue_source=xt_cache",
                "recent_project_dialogue_low_signal_dropped=3",
                "project_context_depth=full",
                "effective_project_serving_profile=m4_full_scan",
                "workflow_present=true",
                "execution_evidence_present=true",
                "review_guidance_present=false",
                "cross_link_hints_selected=2",
                "project_memory_selected_planes=project_dialogue_plane,project_anchor_plane,evidence_plane",
                "personal_memory_excluded_reason=project_ai_default_scopes_to_project_memory_only",
                "project_memory_issue_codes=memory_resolution_projection_drift",
                "project_memory_readiness_ready=false",
                "project_memory_readiness_status_line=attention:memory_resolution_projection_drift",
                "project_memory_readiness_issue_codes=memory_resolution_projection_drift",
                "project_memory_readiness_top_issue_code=memory_resolution_projection_drift",
                "project_memory_readiness_top_issue_summary=Project memory explainability 与实际 served prompt 不一致"
            ]
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.status == .pass)
        #expect(check?.projectContextSummary?.sourceKind == "latest_coder_usage")
        #expect(check?.projectContextSummary?.sourceBadge == "Latest Usage")
        #expect(check?.projectContextSummary?.projectLabel == "Snake")
        #expect(check?.projectContextSummary?.dialogueMetric.contains("40 pairs") == true)
        #expect(check?.projectContextSummary?.depthMetric.contains("Full") == true)
        #expect(check?.projectContextSummary?.coverageMetric == "wf yes · ev yes · gd no · xlink 2")
        #expect(check?.projectContextSummary?.boundaryMetric == "personal excluded")
        #expect(check?.projectContextSummary?.boundaryLine?.contains("project_ai_default_scopes_to_project_memory_only") == true)
        #expect(check?.projectContextSummary?.planeLine == "Active Planes：项目对话面、项目锚点面和证据面")
        #expect(check?.projectMemoryReadiness?.ready == false)
        #expect(check?.projectMemoryReadiness?.issueCodes == ["memory_resolution_projection_drift"])
        #expect(check?.detailLines.contains("project_memory_issue_codes=memory_resolution_projection_drift") == true)
    }

    @Test
    func mapsMachineReadableProjectAndSupervisorMemoryPoliciesFromDetailLines() {
        let projectPolicy = XTProjectMemoryPolicySnapshot(
            configuredRecentProjectDialogueProfile: .deep20Pairs,
            configuredProjectContextDepth: .full,
            recommendedRecentProjectDialogueProfile: .extended40Pairs,
            recommendedProjectContextDepth: .deep,
            effectiveRecentProjectDialogueProfile: .extended40Pairs,
            effectiveProjectContextDepth: .deep,
            aTierMemoryCeiling: .m3DeepDive
        )
        let projectResolution = XTMemoryAssemblyResolution(
            role: .projectAI,
            trigger: "guided_execution",
            configuredDepth: AXProjectContextDepthProfile.full.rawValue,
            recommendedDepth: AXProjectContextDepthProfile.deep.rawValue,
            effectiveDepth: AXProjectContextDepthProfile.deep.rawValue,
            ceilingFromTier: XTMemoryServingProfile.m3DeepDive.rawValue,
            ceilingHit: true,
            selectedSlots: [
                "recent_project_dialogue_window",
                "focused_project_anchor_pack",
                "active_workflow",
                "selected_cross_link_hints",
                "guidance",
            ],
            selectedPlanes: [
                "project_dialogue_plane",
                "project_anchor_plane",
                "workflow_plane",
                "cross_link_plane",
                "guidance_plane",
            ],
            selectedServingObjects: [
                "recent_project_dialogue_window",
                "focused_project_anchor_pack",
                "active_workflow",
                "selected_cross_link_hints",
                "guidance",
            ],
            excludedBlocks: ["assistant_plane", "personal_memory", "portfolio_brief"]
        )
        let supervisorPolicy = XTSupervisorMemoryPolicySnapshot(
            configuredSupervisorRecentRawContextProfile: .autoMax,
            configuredReviewMemoryDepth: .auto,
            recommendedSupervisorRecentRawContextProfile: .extended40Pairs,
            recommendedReviewMemoryDepth: .deepDive,
            effectiveSupervisorRecentRawContextProfile: .extended40Pairs,
            effectiveReviewMemoryDepth: .deepDive,
            sTierReviewMemoryCeiling: .m4FullScan
        )
        let supervisorResolution = XTMemoryAssemblyResolution(
            role: .supervisor,
            dominantMode: SupervisorTurnMode.projectFirst.rawValue,
            trigger: "heartbeat_no_progress_review",
            configuredDepth: XTSupervisorReviewMemoryDepthProfile.auto.rawValue,
            recommendedDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
            effectiveDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
            ceilingFromTier: XTMemoryServingProfile.m4FullScan.rawValue,
            ceilingHit: false,
            selectedSlots: [
                "recent_raw_dialogue_window",
                "portfolio_brief",
                "focused_project_anchor_pack",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack",
            ],
            selectedPlanes: ["continuity_lane", "project_plane", "cross_link_plane"],
            selectedServingObjects: [
                "recent_raw_dialogue_window",
                "portfolio_brief",
                "focused_project_anchor_pack",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack",
            ],
            excludedBlocks: []
        )
        let governanceRuntimeReadiness = governanceRuntimeReadinessSnapshot(
            runtimeReady: false,
            state: .blocked,
            missingReasonCodes: ["trusted_automation_not_ready", "permission_owner_not_ready"],
            summaryLine: "A4 Agent 已配置，但 runtime ready 还没完成。",
            missingSummaryLine: "缺口：受治理自动化未就绪 / 权限宿主未就绪"
        )

        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is healthy and carries machine-readable memory policy truth.",
            nextStep: "Continue into the active project.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready",
                "project_context_diagnostics_source=latest_coder_usage",
                "project_context_project=Snake",
                "recent_project_dialogue_profile=extended_40_pairs",
                "recent_project_dialogue_selected_pairs=18",
                "recent_project_dialogue_floor_pairs=8",
                "recent_project_dialogue_floor_satisfied=true",
                "recent_project_dialogue_source=xt_cache",
                "recent_project_dialogue_low_signal_dropped=3",
                "project_context_depth=deep",
                "effective_project_serving_profile=m3_deep_dive",
                "workflow_present=true",
                "execution_evidence_present=false",
                "review_guidance_present=true",
                "cross_link_hints_selected=2",
                "personal_memory_excluded_reason=project_ai_default_scopes_to_project_memory_only",
                "project_memory_policy_json=\(compactJSONString(projectPolicy))",
                "project_memory_readiness_ready=false",
                "project_memory_readiness_status_line=attention:project_memory_usage_missing",
                "project_memory_readiness_issue_codes=project_memory_usage_missing",
                "project_memory_readiness_top_issue_code=project_memory_usage_missing",
                "project_memory_readiness_top_issue_summary=尚未捕获 Project AI 的最近一次 memory 装配真相",
                "project_memory_assembly_resolution_json=\(compactJSONString(projectResolution))",
                "supervisor_memory_policy_json=\(compactJSONString(supervisorPolicy))",
                "supervisor_memory_assembly_resolution_json=\(compactJSONString(supervisorResolution))",
            ] + governanceRuntimeReadiness.detailLines()
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.projectGovernanceRuntimeReadiness == governanceRuntimeReadiness)
        #expect(check?.projectMemoryPolicy?.schemaVersion == XTProjectMemoryPolicySnapshot.currentSchemaVersion)
        #expect(check?.projectMemoryReadiness?.ready == false)
        #expect(check?.projectMemoryReadiness?.issueCodes == ["project_memory_usage_missing"])
        #expect(check?.projectMemoryPolicy?.effectiveProjectContextDepth == .deep)
        #expect(check?.projectMemoryAssemblyResolution?.selectedServingObjects.contains("guidance") == true)
        #expect(check?.projectMemoryAssemblyResolution?.excludedBlocks.contains("assistant_plane") == true)
        #expect(check?.supervisorMemoryPolicy?.schemaVersion == XTSupervisorMemoryPolicySnapshot.currentSchemaVersion)
        #expect(check?.supervisorMemoryPolicy?.effectiveReviewMemoryDepth == .deepDive)
        #expect(check?.supervisorMemoryAssemblyResolution?.selectedPlanes == ["continuity_lane", "project_plane", "cross_link_plane"])
        #expect(check?.supervisorMemoryAssemblyResolution?.selectedServingObjects.contains("evidence_pack") == true)
    }

    @Test
    func prefersStructuredMemoryPolicyProjectionsOverDetailLineFallback() {
        let legacyProjectPolicy = XTProjectMemoryPolicySnapshot(
            configuredRecentProjectDialogueProfile: .floor8Pairs,
            configuredProjectContextDepth: .balanced,
            recommendedRecentProjectDialogueProfile: .floor8Pairs,
            recommendedProjectContextDepth: .balanced,
            effectiveRecentProjectDialogueProfile: .floor8Pairs,
            effectiveProjectContextDepth: .balanced,
            aTierMemoryCeiling: .m2PlanReview
        )
        let structuredProjectPolicy = XTProjectMemoryPolicySnapshot(
            configuredRecentProjectDialogueProfile: .deep20Pairs,
            configuredProjectContextDepth: .full,
            recommendedRecentProjectDialogueProfile: .extended40Pairs,
            recommendedProjectContextDepth: .deep,
            effectiveRecentProjectDialogueProfile: .extended40Pairs,
            effectiveProjectContextDepth: .deep,
            aTierMemoryCeiling: .m3DeepDive
        )
        let legacyProjectResolution = XTMemoryAssemblyResolution(
            role: .projectAI,
            trigger: "legacy_balanced",
            configuredDepth: AXProjectContextDepthProfile.balanced.rawValue,
            recommendedDepth: AXProjectContextDepthProfile.balanced.rawValue,
            effectiveDepth: AXProjectContextDepthProfile.balanced.rawValue,
            ceilingFromTier: XTMemoryServingProfile.m2PlanReview.rawValue,
            ceilingHit: false,
            selectedSlots: ["recent_project_dialogue_window"],
            selectedPlanes: ["project_dialogue_plane"],
            selectedServingObjects: ["recent_project_dialogue_window"],
            excludedBlocks: ["execution_evidence"]
        )
        let structuredProjectResolution = XTMemoryAssemblyResolution(
            role: .projectAI,
            trigger: "guided_execution",
            configuredDepth: AXProjectContextDepthProfile.full.rawValue,
            recommendedDepth: AXProjectContextDepthProfile.deep.rawValue,
            effectiveDepth: AXProjectContextDepthProfile.deep.rawValue,
            ceilingFromTier: XTMemoryServingProfile.m3DeepDive.rawValue,
            ceilingHit: true,
            selectedSlots: ["recent_project_dialogue_window", "focused_project_anchor_pack", "guidance"],
            selectedPlanes: ["project_dialogue_plane", "project_anchor_plane", "guidance_plane"],
            selectedServingObjects: ["recent_project_dialogue_window", "focused_project_anchor_pack", "guidance"],
            excludedBlocks: ["assistant_plane"]
        )
        let legacySupervisorPolicy = XTSupervisorMemoryPolicySnapshot(
            configuredSupervisorRecentRawContextProfile: .standard12Pairs,
            configuredReviewMemoryDepth: .compact,
            recommendedSupervisorRecentRawContextProfile: .standard12Pairs,
            recommendedReviewMemoryDepth: .compact,
            effectiveSupervisorRecentRawContextProfile: .standard12Pairs,
            effectiveReviewMemoryDepth: .compact,
            sTierReviewMemoryCeiling: .m1Execute
        )
        let structuredSupervisorPolicy = XTSupervisorMemoryPolicySnapshot(
            configuredSupervisorRecentRawContextProfile: .autoMax,
            configuredReviewMemoryDepth: .auto,
            recommendedSupervisorRecentRawContextProfile: .extended40Pairs,
            recommendedReviewMemoryDepth: .deepDive,
            effectiveSupervisorRecentRawContextProfile: .extended40Pairs,
            effectiveReviewMemoryDepth: .deepDive,
            sTierReviewMemoryCeiling: .m4FullScan
        )
        let legacySupervisorResolution = XTMemoryAssemblyResolution(
            role: .supervisor,
            dominantMode: SupervisorTurnMode.personalFirst.rawValue,
            trigger: "legacy_compact_review",
            configuredDepth: XTSupervisorReviewMemoryDepthProfile.compact.rawValue,
            recommendedDepth: XTSupervisorReviewMemoryDepthProfile.compact.rawValue,
            effectiveDepth: XTSupervisorReviewMemoryDepthProfile.compact.rawValue,
            ceilingFromTier: XTMemoryServingProfile.m1Execute.rawValue,
            ceilingHit: false,
            selectedSlots: ["recent_raw_dialogue_window"],
            selectedPlanes: ["continuity_lane"],
            selectedServingObjects: ["recent_raw_dialogue_window"],
            excludedBlocks: ["portfolio_brief"]
        )
        let structuredSupervisorResolution = XTMemoryAssemblyResolution(
            role: .supervisor,
            dominantMode: SupervisorTurnMode.projectFirst.rawValue,
            trigger: "heartbeat_no_progress_review",
            configuredDepth: XTSupervisorReviewMemoryDepthProfile.auto.rawValue,
            recommendedDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
            effectiveDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
            ceilingFromTier: XTMemoryServingProfile.m4FullScan.rawValue,
            ceilingHit: false,
            selectedSlots: ["recent_raw_dialogue_window", "focused_project_anchor_pack", "delta_feed", "evidence_pack"],
            selectedPlanes: ["continuity_lane", "project_plane", "cross_link_plane"],
            selectedServingObjects: ["recent_raw_dialogue_window", "focused_project_anchor_pack", "delta_feed", "evidence_pack"],
            excludedBlocks: []
        )
        let legacyGovernanceRuntimeReadiness = governanceRuntimeReadinessSnapshot(
            runtimeReady: false,
            state: .blocked,
            missingReasonCodes: ["trusted_automation_not_ready"],
            summaryLine: "A4 Agent 已配置，但 runtime ready 还没完成。",
            missingSummaryLine: "缺口：受治理自动化未就绪"
        )
        let structuredGovernanceRuntimeReadiness = governanceRuntimeReadinessSnapshot(
            trustedAutomationState: AXTrustedAutomationProjectState.active.rawValue,
            runtimeReady: true,
            state: .ready,
            missingReasonCodes: [],
            summaryLine: "A4 Agent 已配置，runtime ready 已就绪。"
        )

        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime carries structured memory policy truth.",
            nextStep: "Continue into the active project.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready",
                "project_memory_policy_json=\(compactJSONString(legacyProjectPolicy))",
                "project_memory_assembly_resolution_json=\(compactJSONString(legacyProjectResolution))",
                "supervisor_memory_policy_json=\(compactJSONString(legacySupervisorPolicy))",
                "supervisor_memory_assembly_resolution_json=\(compactJSONString(legacySupervisorResolution))",
            ] + legacyGovernanceRuntimeReadiness.detailLines(),
            projectGovernanceRuntimeReadinessProjection: structuredGovernanceRuntimeReadiness,
            projectMemoryPolicyProjection: structuredProjectPolicy,
            projectMemoryAssemblyResolutionProjection: structuredProjectResolution,
            supervisorMemoryPolicyProjection: structuredSupervisorPolicy,
            supervisorMemoryAssemblyResolutionProjection: structuredSupervisorResolution
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.projectGovernanceRuntimeReadiness == structuredGovernanceRuntimeReadiness)
        #expect(check?.projectMemoryPolicy == structuredProjectPolicy)
        #expect(check?.projectMemoryAssemblyResolution == structuredProjectResolution)
        #expect(check?.supervisorMemoryPolicy == structuredSupervisorPolicy)
        #expect(check?.supervisorMemoryAssemblyResolution == structuredSupervisorResolution)
    }

    @Test
    func prefersStructuredSupervisorGuidanceContinuityProjectionOverDetailLineFallback() {
        let legacyGuidanceDetailLines = [
            "supervisor_review_guidance_carrier_present=true",
            "supervisor_memory_latest_review_note_available=true",
            "supervisor_memory_latest_review_note_actualized=true",
            "supervisor_memory_latest_guidance_available=true",
            "supervisor_memory_latest_guidance_actualized=true",
            "supervisor_memory_latest_guidance_ack_status=pending",
            "supervisor_memory_latest_guidance_ack_required=true",
            "supervisor_memory_latest_guidance_delivery_mode=context_append",
            "supervisor_memory_latest_guidance_intervention_mode=suggest_next_safe_point",
            "supervisor_memory_latest_guidance_safe_point_policy=next_tool_boundary",
            "supervisor_memory_pending_ack_guidance_available=false",
            "supervisor_memory_pending_ack_guidance_actualized=false",
            "Review / Guidance：latest review carried · latest guidance carried [ack=pending · required · safe_point=next_tool_boundary]"
        ]
        let structuredGuidanceProjection = XTUnifiedDoctorSupervisorGuidanceContinuityProjection(
            reviewGuidanceCarrierPresent: true,
            latestReviewNoteAvailable: true,
            latestReviewNoteActualized: true,
            latestGuidanceAvailable: true,
            latestGuidanceActualized: true,
            latestGuidanceAckStatus: SupervisorGuidanceAckStatus.accepted.rawValue,
            latestGuidanceAckRequired: true,
            latestGuidanceDeliveryMode: SupervisorGuidanceDeliveryMode.priorityInsert.rawValue,
            latestGuidanceInterventionMode: SupervisorGuidanceInterventionMode.suggestNextSafePoint.rawValue,
            latestGuidanceSafePointPolicy: SupervisorGuidanceSafePointPolicy.checkpointBoundary.rawValue,
            pendingAckGuidanceAvailable: true,
            pendingAckGuidanceActualized: true,
            pendingAckGuidanceAckStatus: SupervisorGuidanceAckStatus.deferred.rawValue,
            pendingAckGuidanceAckRequired: true,
            pendingAckGuidanceDeliveryMode: SupervisorGuidanceDeliveryMode.replanRequest.rawValue,
            pendingAckGuidanceInterventionMode: SupervisorGuidanceInterventionMode.replanNextSafePoint.rawValue,
            pendingAckGuidanceSafePointPolicy: SupervisorGuidanceSafePointPolicy.nextStepBoundary.rawValue,
            renderedRefs: ["latest_review_note", "latest_guidance", "pending_ack_guidance"],
            summaryLine: "Review / Guidance：latest review carried · latest guidance carried [ack=accepted · required · safe_point=checkpoint_boundary] · pending guidance carried [ack=deferred · required · safe_point=next_step_boundary]"
        )

        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime carries structured supervisor guidance continuity truth.",
            nextStep: "Continue into the active project.",
            repairEntry: .xtDiagnostics,
            detailLines: ["runtime_state=ready"] + legacyGuidanceDetailLines,
            supervisorGuidanceContinuityProjection: structuredGuidanceProjection
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.supervisorGuidanceContinuitySnapshot == structuredGuidanceProjection)
    }

    @Test
    func prefersStructuredSupervisorReviewTriggerProjectionOverDetailLineFallback() {
        let legacyReviewTriggerDetailLines = [
            "supervisor_review_policy_mode=hybrid",
            "supervisor_review_event_driven_enabled=true",
            "supervisor_review_event_follow_up_cadence_label=cadence=active · blocker cooldown≈300s",
            "supervisor_review_mandatory_triggers=blocker_detected,plan_drift,pre_done_summary",
            "supervisor_review_effective_event_triggers=blocker_detected,plan_drift,pre_done_summary",
            "supervisor_review_derived_triggers=manual_request,user_override,periodic_pulse,no_progress_window",
            "supervisor_review_active_candidate_available=true",
            "supervisor_review_active_candidate_trigger=blocker_detected",
            "supervisor_review_active_candidate_run_kind=event_driven",
            "supervisor_review_active_candidate_level=r2_strategic",
            "supervisor_review_active_candidate_priority=310",
            "supervisor_review_active_candidate_policy_reason=event_trigger=blocker_detected quality=weak anomalies=none repeat=0 depth=execution_ready",
            "supervisor_review_active_candidate_queued=true",
            "supervisor_review_queued_trigger=blocker_detected",
            "supervisor_review_queued_run_kind=event_driven",
            "supervisor_review_queued_level=r2_strategic",
            "supervisor_review_latest_review_source=review_note_store",
            "supervisor_review_latest_review_trigger=pre_done_summary",
            "supervisor_review_latest_review_level=r3_rescue",
            "supervisor_review_latest_review_at_ms=1773900300000",
            "Review Trigger：当前候选 blocker_detected / r2_strategic / event_driven · 已进入治理排队 · review_policy=hybrid · event_driven=true · latest_review=pre_done_summary"
        ]
        let structuredReviewTriggerProjection = XTUnifiedDoctorSupervisorReviewTriggerProjection(
            reviewPolicyMode: AXProjectReviewPolicyMode.aggressive.rawValue,
            eventDrivenReviewEnabled: true,
            eventFollowUpCadenceLabel: "cadence=tight · blocker cooldown≈120s",
            mandatoryReviewTriggers: [
                AXProjectReviewTrigger.blockerDetected.rawValue,
                AXProjectReviewTrigger.preHighRiskAction.rawValue,
                AXProjectReviewTrigger.preDoneSummary.rawValue
            ],
            effectiveEventReviewTriggers: [
                AXProjectReviewTrigger.blockerDetected.rawValue,
                AXProjectReviewTrigger.preHighRiskAction.rawValue,
                AXProjectReviewTrigger.preDoneSummary.rawValue
            ],
            derivedReviewTriggers: [
                SupervisorReviewTrigger.manualRequest.rawValue,
                SupervisorReviewTrigger.userOverride.rawValue,
                SupervisorReviewTrigger.periodicPulse.rawValue,
                SupervisorReviewTrigger.noProgressWindow.rawValue
            ],
            activeCandidateAvailable: true,
            activeCandidateTrigger: SupervisorReviewTrigger.preDoneSummary.rawValue,
            activeCandidateRunKind: SupervisorReviewRunKind.eventDriven.rawValue,
            activeCandidateReviewLevel: SupervisorReviewLevel.r3Rescue.rawValue,
            activeCandidatePriority: 340,
            activeCandidatePolicyReason: "heartbeat_anomaly=weak_done_claim quality=weak anomalies=weak_done_claim repeat=0 depth=step_locked_rescue",
            activeCandidateQueued: true,
            queuedReviewTrigger: SupervisorReviewTrigger.preDoneSummary.rawValue,
            queuedReviewRunKind: SupervisorReviewRunKind.eventDriven.rawValue,
            queuedReviewLevel: SupervisorReviewLevel.r3Rescue.rawValue,
            latestReviewSource: "review_note_store",
            latestReviewTrigger: SupervisorReviewTrigger.blockerDetected.rawValue,
            latestReviewLevel: SupervisorReviewLevel.r2Strategic.rawValue,
            latestReviewAtMs: 1_773_900_900_000,
            lastPulseReviewAtMs: 1_773_900_300_000,
            lastBrainstormReviewAtMs: 1_773_899_700_000,
            summaryLine: "Review Trigger：当前候选 pre_done_summary / r3_rescue / event_driven · 已进入治理排队 · review_policy=aggressive · event_driven=true · latest_review=blocker_detected"
        )

        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime carries structured supervisor review trigger truth.",
            nextStep: "Continue into the active project.",
            repairEntry: .xtDiagnostics,
            detailLines: ["runtime_state=ready"] + legacyReviewTriggerDetailLines,
            supervisorReviewTriggerProjection: structuredReviewTriggerProjection
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.supervisorReviewTriggerSnapshot == structuredReviewTriggerProjection)
    }

    @Test
    func prefersStructuredSupervisorSafePointTimelineProjectionOverDetailLineFallback() {
        let legacySafePointDetailLines = [
            "supervisor_safe_point_pending_guidance_available=true",
            "supervisor_safe_point_pending_guidance_injection_id=guidance-next-step-legacy",
            "supervisor_safe_point_pending_guidance_delivery_mode=replan_request",
            "supervisor_safe_point_pending_guidance_intervention_mode=replan_next_safe_point",
            "supervisor_safe_point_pending_guidance_safe_point_policy=next_step_boundary",
            "supervisor_safe_point_live_state_source=pending_tool_approval",
            "supervisor_safe_point_flow_step=1",
            "supervisor_safe_point_tool_results_count=0",
            "supervisor_safe_point_verify_run_index=0",
            "supervisor_safe_point_finalize_only=false",
            "supervisor_safe_point_checkpoint_reached=false",
            "supervisor_safe_point_prompt_visible_now=false",
            "supervisor_safe_point_visible_from_pre_run_memory=false",
            "supervisor_safe_point_pause_recorded=false",
            "supervisor_safe_point_deliverable_now=false",
            "supervisor_safe_point_should_pause_tool_batch_after_boundary=false",
            "supervisor_safe_point_delivery_state=waiting_next_step_boundary",
            "supervisor_safe_point_execution_gate=normal",
            "Safe Point：pending guidance 等待下一步边界 · execution_gate=normal"
        ]
        let structuredSafePointProjection = XTUnifiedDoctorSupervisorSafePointTimelineProjection(
            pendingGuidanceAvailable: true,
            pendingGuidanceInjectionId: "guidance-next-tool-structured",
            pendingGuidanceDeliveryMode: SupervisorGuidanceDeliveryMode.priorityInsert.rawValue,
            pendingGuidanceInterventionMode: SupervisorGuidanceInterventionMode.suggestNextSafePoint.rawValue,
            pendingGuidanceSafePointPolicy: SupervisorGuidanceSafePointPolicy.nextToolBoundary.rawValue,
            liveStateSource: "pending_tool_approval",
            flowStep: 1,
            toolResultsCount: 1,
            verifyRunIndex: 0,
            finalizeOnly: false,
            checkpointReached: false,
            promptVisibleNow: false,
            visibleFromPreRunMemory: false,
            pauseRecorded: false,
            deliverableNow: true,
            shouldPauseToolBatchAfterBoundary: true,
            deliveryState: "deliverable_now",
            executionGate: "normal",
            summaryLine: "Safe Point：pending guidance 当前可立即投递 · execution_gate=normal · pause_after_tool_boundary"
        )

        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime carries structured supervisor safe-point timing truth.",
            nextStep: "Continue into the active project.",
            repairEntry: .xtDiagnostics,
            detailLines: ["runtime_state=ready"] + legacySafePointDetailLines,
            supervisorSafePointTimelineProjection: structuredSafePointProjection
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.supervisorSafePointTimelineSnapshot == structuredSafePointProjection)
    }

    @Test
    func prefersStructuredProjectContextPresentationOverDetailLineFallback() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is healthy and carries structured project context.",
            nextStep: "Continue into the active project.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready"
            ],
            projectContextPresentation: AXProjectContextAssemblyPresentation(
                sourceKind: .latestCoderUsage,
                projectLabel: "Structured Snake",
                sourceBadge: "Latest Usage",
                statusLine: "Structured source report projection.",
                dialogueMetric: "Extended 40 Pairs · 40 pairs",
                depthMetric: "Full · m4_full_scan",
                dialogueLine: "Structured dialogue line",
                depthLine: "Structured depth line",
                coverageMetric: "wf yes · ev yes · gd no · xlink 2",
                coverageLine: "Structured coverage line",
                boundaryMetric: "personal excluded",
                boundaryLine: "Boundary：personal memory excluded · project_ai_default_scopes_to_project_memory_only",
                planeLine: "Active Planes：项目对话面、项目锚点面和证据面",
                assemblyLine: "Actual Assembly：最近项目对话、项目锚点和执行证据",
                omissionLine: "Omitted Blocks：活动工作流和Supervisor 指导",
                budgetLine: "Budget：source Hub 快照 + 本地 overlay · used 512 tok · budget 2048 tok",
                userSourceBadge: "实际运行",
                userStatusLine: "结构化 source report 直出。",
                userDialogueMetric: "Extended 40 Pairs · 40 pairs",
                userDepthMetric: "Full",
                userCoverageSummary: "已带工作流、执行证据、关联线索",
                userBoundarySummary: "默认不读取你的个人记忆",
                userPlaneSummary: "实际启用项目对话面、项目锚点面和证据面",
                userAssemblySummary: "实际带入最近项目对话、项目锚点和执行证据",
                userOmissionSummary: "本轮未带活动工作流和Supervisor 指导",
                userBudgetSummary: "source Hub 快照 + 本地 overlay · used 512 tok · budget 2048 tok",
                userDialogueLine: "Structured user dialogue line",
                userDepthLine: "Structured user depth line"
            )
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.projectContextSummary?.projectLabel == "Structured Snake")
        #expect(check?.projectContextSummary?.statusLine == "Structured source report projection.")
        #expect(check?.projectContextSummary?.dialogueLine == "Structured dialogue line")
        #expect(check?.projectContextSummary?.depthLine == "Structured depth line")
        #expect(check?.projectContextSummary?.coverageMetric == "wf yes · ev yes · gd no · xlink 2")
        #expect(check?.projectContextSummary?.planeLine == "Active Planes：项目对话面、项目锚点面和证据面")
        #expect(check?.projectContextSummary?.assemblyLine == "Actual Assembly：最近项目对话、项目锚点和执行证据")
        #expect(check?.projectContextSummary?.omissionLine == "Omitted Blocks：活动工作流和Supervisor 指导")
        #expect(check?.projectContextSummary?.budgetLine == "Budget：source Hub 快照 + 本地 overlay · used 512 tok · budget 2048 tok")
    }

    @Test
    func writesHeartbeatGovernanceDetailLinesIntoMachineReadableGenericReport() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-doctor-output-heartbeat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is healthy and carries heartbeat governance explainability.",
            nextStep: "Continue into the active project.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready",
                "heartbeat_quality_band=weak",
                "heartbeat_project_phase=release",
                "heartbeat_execution_status=done_candidate",
                "heartbeat_risk_tier=high",
                "heartbeat_effective_cadence progress=180s pulse=600s brainstorm=1200s",
                "heartbeat_effective_cadence_reasons progress=adjusted_for_project_phase_release pulse=adjusted_for_project_phase_release,tightened_for_done_candidate_status brainstorm=adjusted_for_project_phase_release",
                "heartbeat_next_review_due kind=review_pulse due=true at_ms=1741299980000 reasons=pulse_review_window_elapsed",
                "heartbeat_recovery action=repair_route urgency=active reason=route_flaky_requires_repair requires_user=false blocked_lanes=1 stalled_lanes=0 failed_lanes=0 recovering_lanes=0",
                "heartbeat_recovery_signals sources=anomaly:route_flaky,lane_blocked_reason:route_origin_unavailable,lane_blocked_count:1 anomalies=route_flaky blocked_reasons=route_origin_unavailable",
                "heartbeat_recovery_summary=Repair route or runtime dispatch readiness before attempting resume.",
                "heartbeat_recovery_review trigger=blocker_detected level=r2_strategic run_kind=event_driven"
            ]
        )

        let reportURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: tempRoot)
        let report = XHubDoctorOutputReport.xtReadinessBundle(
            from: xtReport,
            outputPath: reportURL.path
        )

        XHubDoctorOutputStore.writeReport(report, to: reportURL)

        let decoded = try JSONDecoder().decode(
            XHubDoctorOutputReport.self,
            from: Data(contentsOf: reportURL)
        )
        let check = decoded.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.status == .pass)
        #expect(check?.detailLines.contains("heartbeat_quality_band=weak") == true)
        #expect(check?.detailLines.contains("heartbeat_project_phase=release") == true)
        #expect(check?.detailLines.contains("heartbeat_execution_status=done_candidate") == true)
        #expect(check?.detailLines.contains("heartbeat_risk_tier=high") == true)
        #expect(check?.detailLines.contains(where: {
            $0.contains("heartbeat_effective_cadence progress=180s pulse=600s brainstorm=1200s")
        }) == true)
        #expect(check?.detailLines.contains(where: {
            $0.contains("heartbeat_next_review_due kind=review_pulse") && $0.contains("due=true")
        }) == true)
        #expect(check?.heartbeatGovernanceSnapshot?.latestQualityBand == HeartbeatQualityBand.weak.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.projectPhase == HeartbeatProjectPhase.release.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.executionStatus == HeartbeatExecutionStatus.doneCandidate.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.riskTier == HeartbeatRiskTier.high.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.reviewPulse.effectiveSeconds == 600)
        #expect(check?.heartbeatGovernanceSnapshot?.reviewPulse.recommendedSeconds == nil)
        #expect(check?.heartbeatGovernanceSnapshot?.nextReviewDue.kind == SupervisorCadenceDimension.reviewPulse.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.nextReviewDue.due == true)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.action == HeartbeatRecoveryAction.repairRoute.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.actionDisplayText == "修复 route / dispatch")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.urgencyDisplayText == "主动处理")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.reasonDisplayText == "route 波动，需要先修复")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.sourceSignalDisplayTexts == ["异常 route 波动", "阻塞原因 route 源不可用", "阻塞 lane 1 条"])
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.anomalyTypeDisplayTexts == ["route 波动"])
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.blockedLaneReasonDisplayTexts == ["route 源不可用"])
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.queuedReviewLevel == SupervisorReviewLevel.r2Strategic.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.queuedReviewTriggerDisplayText == "blocker 触发")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.queuedReviewLevelDisplayText == "一次战略复盘")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.queuedReviewRunKindDisplayText == "事件触发")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.doctorExplainabilityText?.contains("修复当前 route / dispatch 健康") == true)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.doctorExplainabilityText?.contains("主动处理") == true)
    }

    @Test
    func projectsHeartbeatGovernanceSnapshotFromStructuredSessionReadinessProjection() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is healthy and carries structured heartbeat governance truth.",
            nextStep: "Continue into the active project.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready"
            ],
            heartbeatGovernanceProjection: sampleHeartbeatGovernanceProjection()
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.heartbeatGovernanceSnapshot?.projectId == "project-alpha")
        #expect(check?.heartbeatGovernanceSnapshot?.projectName == "Alpha")
        #expect(check?.heartbeatGovernanceSnapshot?.latestQualityBand == HeartbeatQualityBand.weak.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.latestQualityBandDisplayText == "偏弱")
        #expect(check?.heartbeatGovernanceSnapshot?.weakReasonDisplayTexts == ["证据偏弱", "完成把握偏低", "Project memory 需要关注"])
        #expect(check?.heartbeatGovernanceSnapshot?.openAnomalyDisplayTexts == ["完成声明证据偏弱"])
        #expect(check?.heartbeatGovernanceSnapshot?.projectPhaseDisplayText == "发布")
        #expect(check?.heartbeatGovernanceSnapshot?.executionStatusDisplayText == "完成候选")
        #expect(check?.heartbeatGovernanceSnapshot?.riskTierDisplayText == "高")
        #expect(check?.heartbeatGovernanceSnapshot?.projectMemoryReady == false)
        #expect(check?.heartbeatGovernanceSnapshot?.projectMemoryIssueCodes == ["project_memory_usage_missing"])
        #expect(check?.heartbeatGovernanceSnapshot?.projectMemoryTopIssueSummary?.contains("最近一次 memory 装配真相") == true)
        #expect(check?.heartbeatGovernanceSnapshot?.digestVisibility == XTHeartbeatDigestVisibilityDecision.shown.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.digestReasonCodes.contains("weak_done_claim") == true)
        #expect(check?.heartbeatGovernanceSnapshot?.digestReasonCodes.contains("project_memory_attention") == true)
        #expect(check?.heartbeatGovernanceSnapshot?.digestVisibilityDisplayText == "显示给用户")
        #expect(check?.heartbeatGovernanceSnapshot?.digestReasonDisplayTexts == ["完成声明证据偏弱", "heartbeat 质量偏弱", "当前有待执行复盘候选", "Project memory 需要关注"])
        #expect(check?.heartbeatGovernanceSnapshot?.digestWhatChangedText.contains("完成声明证据偏弱") == true)
        #expect(check?.heartbeatGovernanceSnapshot?.digestSystemNextStepText == "Ship release once final review clears")
        #expect(check?.heartbeatGovernanceSnapshot?.reviewPulse.configuredSeconds == 1_200)
        #expect(check?.heartbeatGovernanceSnapshot?.reviewPulse.recommendedSeconds == 600)
        #expect(check?.heartbeatGovernanceSnapshot?.reviewPulse.effectiveSeconds == 600)
        #expect(check?.heartbeatGovernanceSnapshot?.reviewPulse.dimensionDisplayText == "脉冲复盘")
        #expect(check?.heartbeatGovernanceSnapshot?.reviewPulse.effectiveReasonDisplayTexts == ["因项目进入 release 阶段而收紧到更密的交付节奏", "因进入 done candidate 而进一步收紧完成前复核"])
        #expect(check?.heartbeatGovernanceSnapshot?.reviewPulse.nextDueReasonDisplayTexts == ["脉冲复盘窗口已到"])
        #expect(check?.heartbeatGovernanceSnapshot?.nextReviewDue.kind == SupervisorCadenceDimension.reviewPulse.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.nextReviewDue.due == true)
        #expect(check?.heartbeatGovernanceSnapshot?.nextReviewDue.kindDisplayText == "脉冲复盘")
        #expect(check?.heartbeatGovernanceSnapshot?.nextReviewDue.reasonDisplayTexts == ["脉冲复盘窗口已到"])
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.action == HeartbeatRecoveryAction.queueStrategicReview.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.actionDisplayText == "排队治理复盘")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.urgencyDisplayText == "紧急处理")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.reasonDisplayText == "heartbeat 或 lane 信号要求先做治理复盘")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.systemNextStepDisplayText == "系统会先基于事件触发 · pre-done 信号排队一次救援复盘，并在下一个 safe point 注入 guidance")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.sourceSignalDisplayTexts == ["异常 完成声明证据偏弱", "复盘候选 pre-done 信号 / 一次救援复盘 / 事件触发"])
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.anomalyTypeDisplayTexts == ["完成声明证据偏弱"])
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.queuedReviewTrigger == SupervisorReviewTrigger.preDoneSummary.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.queuedReviewTriggerDisplayText == "pre-done 信号")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.queuedReviewLevelDisplayText == "一次救援复盘")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.queuedReviewRunKindDisplayText == "事件触发")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.doctorExplainabilityText?.contains("救援复盘") == true)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.doctorExplainabilityText?.contains("紧急处理") == true)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.doctorExplainabilityText?.contains("Queue a deeper governance review") == false)
    }

    @Test
    func projectsSuppressedHeartbeatGovernanceSnapshotFromStructuredSessionReadinessProjection() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is healthy and carries suppressed heartbeat governance truth.",
            nextStep: "Continue watching for a higher-signal project delta.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready"
            ],
            heartbeatGovernanceProjection: sampleSuppressedHeartbeatGovernanceProjection()
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.heartbeatGovernanceSnapshot?.projectId == "project-beta")
        #expect(check?.heartbeatGovernanceSnapshot?.projectName == "Beta")
        #expect(check?.heartbeatGovernanceSnapshot?.latestQualityBand == HeartbeatQualityBand.usable.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.latestQualityBandDisplayText == "可用")
        #expect(check?.heartbeatGovernanceSnapshot?.digestVisibility == XTHeartbeatDigestVisibilityDecision.suppressed.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.digestReasonCodes == ["stable_runtime_update_suppressed"])
        #expect(check?.heartbeatGovernanceSnapshot?.digestVisibilityDisplayText == "当前压制")
        #expect(check?.heartbeatGovernanceSnapshot?.digestReasonDisplayTexts == ["当前只是稳定运行更新，暂不打扰用户"])
        #expect(check?.heartbeatGovernanceSnapshot?.digestWhatChangedText == "Validation remains on track")
        #expect(check?.heartbeatGovernanceSnapshot?.digestWhyImportantText.contains("digest 被压制") == true)
        #expect(check?.heartbeatGovernanceSnapshot?.digestSystemNextStepText.contains("有实质变化再生成用户 digest") == true)
        #expect(check?.heartbeatGovernanceSnapshot?.reviewPulse.effectiveSeconds == 1_200)
        #expect(check?.heartbeatGovernanceSnapshot?.nextReviewDue.kind == SupervisorCadenceDimension.reviewPulse.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.nextReviewDue.due == false)
        #expect(check?.heartbeatGovernanceSnapshot?.nextReviewDue.kindDisplayText == "脉冲复盘")
        #expect(check?.heartbeatGovernanceSnapshot?.nextReviewDue.reasonDisplayTexts == ["当前脉冲窗口尚未走完"])
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision == nil)
    }

    @Test
    func projectsGrantFollowUpHeartbeatGovernanceSnapshotFromStructuredSessionReadinessProjection() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is paused on a governed grant follow-up.",
            nextStep: "Wait for the required grant follow-up to clear.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready"
            ],
            heartbeatGovernanceProjection: sampleGrantFollowUpHeartbeatGovernanceProjection()
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.heartbeatGovernanceSnapshot?.projectId == "project-grant")
        #expect(check?.heartbeatGovernanceSnapshot?.digestVisibility == XTHeartbeatDigestVisibilityDecision.shown.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.digestReasonCodes == ["recovery_decision_active"])
        #expect(check?.heartbeatGovernanceSnapshot?.digestSystemNextStepText.contains("grant 跟进") == true)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.action == HeartbeatRecoveryAction.requestGrantFollowUp.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.reasonCode == "grant_follow_up_required")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.requiresUserAction == true)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.blockedLaneReasons == [LaneBlockedReason.grantPending.rawValue])
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.systemNextStepDisplayText == "系统会先发起所需 grant 跟进，待放行后再继续恢复执行")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.doctorExplainabilityText?.contains("grant 跟进") == true)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.doctorExplainabilityText?.contains("需要用户动作") == true)
    }

    @Test
    func projectsReplayFollowUpHeartbeatGovernanceSnapshotFromStructuredSessionReadinessProjection() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is paused on a replayable follow-up chain.",
            nextStep: "Wait for the pending follow-up replay to finish.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready"
            ],
            heartbeatGovernanceProjection: sampleReplayFollowUpHeartbeatGovernanceProjection()
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.heartbeatGovernanceSnapshot?.projectId == "project-replay")
        #expect(check?.heartbeatGovernanceSnapshot?.digestVisibility == XTHeartbeatDigestVisibilityDecision.shown.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.digestReasonCodes == ["recovery_decision_active"])
        #expect(check?.heartbeatGovernanceSnapshot?.digestSystemNextStepText.contains("重放挂起的 follow-up") == true)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.action == HeartbeatRecoveryAction.replayFollowUp.rawValue)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.reasonCode == "restart_drain_requires_follow_up_replay")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.requiresUserAction == false)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.blockedLaneReasons == [LaneBlockedReason.restartDrain.rawValue])
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.systemNextStepDisplayText == "系统会在当前 drain 收口后，重放挂起的 follow-up / 续跑链，再确认执行是否恢复")
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.doctorExplainabilityText?.contains("重放挂起的 follow-up") == true)
        #expect(check?.heartbeatGovernanceSnapshot?.recoveryDecision?.doctorExplainabilityText?.contains("等待 drain 恢复") == true)
    }

    @Test
    func projectsDurableCandidateMirrorSnapshotFromStructuredSessionReadinessProjection() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is healthy and carries durable candidate mirror evidence.",
            nextStep: "Continue into the first task.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready"
            ],
            durableCandidateMirrorProjection: XTUnifiedDoctorDurableCandidateMirrorProjection(
                status: .mirroredToHub,
                target: XTSupervisorDurableCandidateMirror.mirrorTarget,
                attempted: true,
                errorCode: nil,
                localStoreRole: XTSupervisorDurableCandidateMirror.localStoreRole
            )
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.durableCandidateMirrorSnapshot?.status == SupervisorDurableCandidateMirrorStatus.mirroredToHub.rawValue)
        #expect(check?.durableCandidateMirrorSnapshot?.target == XTSupervisorDurableCandidateMirror.mirrorTarget)
        #expect(check?.durableCandidateMirrorSnapshot?.attempted == true)
        #expect(check?.durableCandidateMirrorSnapshot?.errorCode == nil)
        #expect(check?.durableCandidateMirrorSnapshot?.localStoreRole == XTSupervisorDurableCandidateMirror.localStoreRole)
    }

    @Test
    func fallsBackToDurableCandidateMirrorDetailLineWhenStructuredProjectionIsMissing() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is healthy and only has migration detail lines for mirror evidence.",
            nextStep: "Continue into the first task.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready",
                "durable_candidate_mirror status=local_only target=\(XTSupervisorDurableCandidateMirror.mirrorTarget) attempted=true reason=remote_route_not_preferred local_store_role=\(XTSupervisorDurableCandidateMirror.localStoreRole)"
            ]
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.durableCandidateMirrorSnapshot?.status == SupervisorDurableCandidateMirrorStatus.localOnly.rawValue)
        #expect(check?.durableCandidateMirrorSnapshot?.attempted == true)
        #expect(check?.durableCandidateMirrorSnapshot?.errorCode == "remote_route_not_preferred")
        #expect(check?.durableCandidateMirrorSnapshot?.localStoreRole == XTSupervisorDurableCandidateMirror.localStoreRole)
    }

    @Test
    func projectsLocalStoreWriteSnapshotFromStructuredSessionReadinessProjection() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is healthy and carries XT local-store provenance.",
            nextStep: "Continue into the first task.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready"
            ],
            localStoreWriteProjection: XTUnifiedDoctorLocalStoreWriteProjection(
                personalMemoryIntent: SupervisorPersonalMemoryStoreWriteIntent.manualEditBufferCommit.rawValue,
                crossLinkIntent: SupervisorCrossLinkStoreWriteIntent.afterTurnCacheRefresh.rawValue,
                personalReviewIntent: SupervisorPersonalReviewNoteStoreWriteIntent.derivedRefresh.rawValue
            )
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.localStoreWriteSnapshot?.personalMemoryIntent == SupervisorPersonalMemoryStoreWriteIntent.manualEditBufferCommit.rawValue)
        #expect(check?.localStoreWriteSnapshot?.crossLinkIntent == SupervisorCrossLinkStoreWriteIntent.afterTurnCacheRefresh.rawValue)
        #expect(check?.localStoreWriteSnapshot?.personalReviewIntent == SupervisorPersonalReviewNoteStoreWriteIntent.derivedRefresh.rawValue)
    }

    @Test
    func fallsBackToLocalStoreWriteDetailLineWhenStructuredProjectionIsMissing() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is healthy and only has migration detail lines for XT local-store provenance.",
            nextStep: "Continue into the first task.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready",
                "xt_local_store_writes personal_memory=\(SupervisorPersonalMemoryStoreWriteIntent.manualEditBufferCommit.rawValue) cross_link=\(SupervisorCrossLinkStoreWriteIntent.afterTurnCacheRefresh.rawValue) personal_review=\(SupervisorPersonalReviewNoteStoreWriteIntent.derivedRefresh.rawValue)"
            ]
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.localStoreWriteSnapshot?.personalMemoryIntent == SupervisorPersonalMemoryStoreWriteIntent.manualEditBufferCommit.rawValue)
        #expect(check?.localStoreWriteSnapshot?.crossLinkIntent == SupervisorCrossLinkStoreWriteIntent.afterTurnCacheRefresh.rawValue)
        #expect(check?.localStoreWriteSnapshot?.personalReviewIntent == SupervisorPersonalReviewNoteStoreWriteIntent.derivedRefresh.rawValue)
    }

    @Test
    func preservesSupervisorTurnContextDetailLineInGenericBundle() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[2] = XTUnifiedDoctorSection(
            kind: .sessionRuntimeReadiness,
            state: .ready,
            headline: "Session runtime is ready",
            summary: "Session runtime is healthy and carries supervisor turn-context assembly evidence.",
            nextStep: "Continue into the current supervisor turn.",
            repairEntry: .xtDiagnostics,
            detailLines: [
                "runtime_state=ready",
                "supervisor_turn_context turn_mode=hybrid dominant_plane=assistant_plane+project_plane supporting_planes=cross_link_plane,portfolio_brief continuity_depth=full assistant_depth=medium project_depth=medium cross_link_depth=full selected_slots=dialogue_window,personal_capsule,focused_project_capsule,portfolio_brief,cross_link_refs,evidence_pack"
            ]
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue }

        #expect(check?.status == .pass)
        #expect(check?.detailLines.contains(where: {
            $0.hasPrefix("supervisor_turn_context ")
                && $0.contains("turn_mode=hybrid")
                && $0.contains("dominant_plane=assistant_plane+project_plane")
                && $0.contains("selected_slots=dialogue_window,personal_capsule,focused_project_capsule,portfolio_brief,cross_link_refs,evidence_pack")
        }) == true)
    }

    @Test
    func projectsMemoryRouteTruthSnapshotFromModelRouteDiagnostics() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[1] = XTUnifiedDoctorSection(
            kind: .modelRouteReadiness,
            state: .ready,
            headline: "Model route is ready, but recent project routes degraded",
            summary: "XT can see the assigned models, but recent project requests still degraded during execution.",
            nextStep: "Open the affected project and inspect route diagnostics.",
            repairEntry: .xtChooseModel,
            detailLines: [
                "configured_models=1",
                "recent_route_events_24h=2",
                "recent_route_failures_24h=1",
                "recent_remote_retry_recoveries_24h=1",
                "route_event_1=project=Smoke Project role=coder path=local_fallback_after_remote_error remote_retry=hub.model.remote->hub.model.backup retry_reason=remote_timeout requested=hub.model.remote actual=mlx.qwen reason=remote_unreachable provider=mlx",
                "route_event_2=project=Smoke Project role=supervisor path=remote_model requested=hub.model.supervisor actual=hub.model.supervisor provider=openai"
            ]
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let check = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.modelRouteReadiness.rawValue }
        let snapshot = check?.memoryRouteTruthSnapshot

        #expect(check?.status == .pass)
        #expect(snapshot?.projectionSource == "xt_model_route_diagnostics_detail_lines")
        #expect(snapshot?.completeness == "partial_xt_projection")
        #expect(snapshot?.requestSnapshot.projectIDPresent == "true")
        #expect(snapshot?.resolutionChain.count == 5)
        #expect(snapshot?.winningBinding.provider == "mlx")
        #expect(snapshot?.winningBinding.modelID == "mlx.qwen")
        #expect(snapshot?.routeResult.routeSource == "local_fallback_after_remote_error")
        #expect(snapshot?.routeResult.routeReasonCode == "remote_unreachable")
        #expect(snapshot?.routeResult.fallbackApplied == "true")
        #expect(snapshot?.routeResult.fallbackReason == "remote_unreachable")
        #expect(snapshot?.routeResult.auditRef == "route_event_1")
        #expect(snapshot?.constraintSnapshot.remoteAllowedAfterPolicy == "unknown")
    }

    @Test
    func prefersStructuredMemoryRouteProjectionOverDetailLineFallback() {
        var xtReport = sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json")
        xtReport.sections[1] = XTUnifiedDoctorSection(
            kind: .modelRouteReadiness,
            state: .ready,
            headline: "Model route is ready, but recent project routes degraded",
            summary: "XT can see assigned models, and the section carries structured route truth.",
            nextStep: "Inspect route diagnostics.",
            repairEntry: .xtChooseModel,
            detailLines: [
                "configured_models=1",
                "recent_route_events_24h=1",
                "recent_route_failures_24h=1"
            ],
            memoryRouteTruthProjection: AXModelRouteTruthProjection(
                projectionSource: "xt_model_route_diagnostics_summary",
                completeness: "partial_xt_projection",
                requestSnapshot: AXModelRouteTruthRequestSnapshot(
                    jobType: "unknown",
                    mode: "unknown",
                    projectIDPresent: "true",
                    sensitivity: "unknown",
                    trustLevel: "unknown",
                    budgetClass: "unknown",
                    remoteAllowedByPolicy: "unknown",
                    killSwitchState: "unknown"
                ),
                resolutionChain: [
                    AXModelRouteTruthResolutionNode(
                        scopeKind: "project",
                        scopeRefRedacted: "unknown",
                        matched: "unknown",
                        profileID: "unknown",
                        selectionStrategy: "unknown",
                        skipReason: "upstream_route_truth_unavailable_in_xt_export"
                    )
                ],
                winningProfile: AXModelRouteTruthWinningProfile(
                    resolvedProfileID: "unknown",
                    scopeKind: "unknown",
                    scopeRefRedacted: "unknown",
                    selectionStrategy: "unknown",
                    policyVersion: "unknown",
                    disabled: "unknown"
                ),
                winningBinding: AXModelRouteTruthWinningBinding(
                    bindingKind: "unknown",
                    bindingKey: "unknown",
                    provider: "Hub (Local)",
                    modelID: "qwen3-14b-mlx",
                    selectedByUser: "unknown"
                ),
                routeResult: AXModelRouteTruthRouteResult(
                    routeSource: "hub_downgraded_to_local",
                    routeReasonCode: "downgrade_to_local",
                    fallbackApplied: "true",
                    fallbackReason: "downgrade_to_local",
                    remoteAllowed: "unknown",
                    auditRef: "project-alpha:coder:1741300020000:hub_downgraded_to_local:openai/gpt-5.4:qwen3-14b-mlx",
                    denyCode: "unknown"
                ),
                constraintSnapshot: AXModelRouteTruthConstraintSnapshot(
                    remoteAllowedAfterUserPref: "unknown",
                    remoteAllowedAfterPolicy: "unknown",
                    budgetClass: "unknown",
                    budgetBlocked: "unknown",
                    policyBlockedRemote: "unknown"
                )
            )
        )

        let bundle = XHubDoctorOutputReport.xtReadinessBundle(from: xtReport)
        let snapshot = bundle.checks.first { $0.checkID == XTUnifiedDoctorSectionKind.modelRouteReadiness.rawValue }?.memoryRouteTruthSnapshot

        #expect(snapshot?.projectionSource == "xt_model_route_diagnostics_summary")
        #expect(snapshot?.winningBinding.provider == "Hub (Local)")
        #expect(snapshot?.winningBinding.modelID == "qwen3-14b-mlx")
        #expect(snapshot?.routeResult.routeSource == "hub_downgraded_to_local")
        #expect(snapshot?.routeResult.routeReasonCode == "downgrade_to_local")
        #expect(snapshot?.routeResult.auditRef.contains("project-alpha") == true)
    }

    @Test
    func genericDoctorStoreFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-doctor-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            XTStoreWriteSupport.resetWriteBehaviorForTesting()
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let reportURL = XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: tempRoot)
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{\"stale\":true}\n".utf8).write(to: reportURL)

        let capture = XHubDoctorOutputWriteCapture()
        let report = XHubDoctorOutputReport.xtReadinessBundle(
            from: sampleXTUnifiedDoctorReport(sourceReportPath: "/tmp/xt_unified_doctor_report.json"),
            outputPath: reportURL.path
        )

        XTStoreWriteSupport.installWriteAttemptOverrideForTesting { data, url, options in
            capture.appendWriteOption(options)
            if options.contains(.atomic) {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: url, options: options)
        }

        XHubDoctorOutputStore.writeReport(report, to: reportURL)

        let decoded = try JSONDecoder().decode(
            XHubDoctorOutputReport.self,
            from: Data(contentsOf: reportURL)
        )
        let options = capture.writeOptionsSnapshot()

        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(decoded.reportPath == reportURL.path)
    }

    @Test
    func loadsHubDoctorReportFromHubBaseDir() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-hub-doctor-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let reportURL = XHubDoctorOutputStore.defaultHubReportURL(baseDir: tempBase)
        let report = sampleHubDoctorOutputReport(outputPath: reportURL.path)
        XHubDoctorOutputStore.writeReport(report, to: reportURL)

        let decoded = XHubDoctorOutputStore.loadHubReport(baseDir: tempBase)

        #expect(decoded?.bundleKind == .providerRuntimeReadiness)
        #expect(decoded?.currentFailureCode == "xhub_local_service_unreachable")
        #expect(decoded?.checks.first?.detailLines.contains("managed_service_ready_count=0") == true)
    }

    @Test
    func loadsHubLocalServiceSnapshotFromHubBaseDir() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-hub-local-service-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let snapshotURL = XHubDoctorOutputStore.defaultHubLocalServiceSnapshotURL(baseDir: tempBase)
        let data = try JSONEncoder().encode(sampleHubLocalServiceSnapshotReport())
        try data.write(to: snapshotURL, options: .atomic)

        let decoded = XHubDoctorOutputStore.loadHubLocalServiceSnapshot(baseDir: tempBase)

        #expect(decoded?.schemaVersion == "xhub_local_service_snapshot_export.v1")
        #expect(decoded?.doctorProjection?.currentFailureCode == "xhub_local_service_unreachable")
        #expect(decoded?.primaryIssue?.reasonCode == "xhub_local_service_unreachable")
        #expect(decoded?.preferredDetailLines().contains(where: { $0.contains("endpoint=http://127.0.0.1:50171") }) == true)
    }

    @Test
    func loadsHubLocalServiceRecoveryGuidanceFromHubBaseDir() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-hub-local-service-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let guidanceURL = XHubDoctorOutputStore.defaultHubLocalServiceRecoveryGuidanceURL(baseDir: tempBase)
        let data = try JSONEncoder().encode(sampleHubLocalServiceRecoveryGuidanceReport())
        try data.write(to: guidanceURL, options: .atomic)

        let decoded = XHubDoctorOutputStore.loadHubLocalServiceRecoveryGuidance(baseDir: tempBase)

        #expect(decoded?.schemaVersion == "xhub_local_service_recovery_guidance_export.v1")
        #expect(decoded?.currentFailureCode == "xhub_local_service_unreachable")
        #expect(decoded?.actionCategory == "inspect_health_payload")
        #expect(decoded?.installHint.contains("/health") == true)
        #expect(decoded?.topRecommendedActionSummary.contains("Inspect the local /health payload") == true)
    }

    @Test
    func loadsHubLocalRuntimeMonitorSnapshotFromHubBaseDir() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("xhub-hub-local-runtime-monitor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let snapshotURL = XHubDoctorOutputStore.defaultHubLocalRuntimeMonitorSnapshotURL(baseDir: tempBase)
        let data = try JSONEncoder().encode(sampleHubLocalRuntimeMonitorSnapshotReport())
        try data.write(to: snapshotURL, options: .atomic)

        let decoded = XHubDoctorOutputStore.loadHubLocalRuntimeMonitorSnapshot(baseDir: tempBase)

        #expect(decoded?.schemaVersion == "xhub_local_runtime_monitor_export.v1")
        #expect(decoded?.runtimeOperations?.loadedSummary == "1 个已加载实例")
        #expect(
            decoded?.preferredLoadConfigLine() ==
                "current_target=bge-small provider=transformers load_summary=ctx=8192 · ttl=600s · par=2 · id=diag-a"
        )
        #expect(
            decoded?.preferredDetailLines().contains(where: {
                $0.contains("host_load_severity=high")
                    && $0.contains("cpu_percent=91.5")
            }) == true
        )
        #expect(
            decoded?.preferredDetailLines().contains(where: {
                $0.contains("current_target=bge-small")
                    && $0.contains("ttl=600s")
                    && $0.contains("par=2")
            }) == true
        )
    }
}

private final class XHubDoctorOutputWriteCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var writeOptions: [Data.WritingOptions] = []

    func appendWriteOption(_ option: Data.WritingOptions) {
        lock.lock()
        defer { lock.unlock() }
        writeOptions.append(option)
    }

    func writeOptionsSnapshot() -> [Data.WritingOptions] {
        lock.lock()
        defer { lock.unlock() }
        return writeOptions
    }
}

private func sampleXTUnifiedDoctorReport(sourceReportPath: String) -> XTUnifiedDoctorReport {
    XTUnifiedDoctorReport(
        schemaVersion: XTUnifiedDoctorReport.currentSchemaVersion,
        generatedAtMs: 1_741_300_000,
        overallState: .diagnosticRequired,
        overallSummary: "Pairing ok, but model route needs repair",
        readyForFirstTask: false,
        currentFailureCode: "hub_unreachable",
        currentFailureIssue: .hubUnreachable,
        configuredModelRoles: 4,
        availableModelCount: 1,
        loadedModelCount: 1,
        currentSessionID: "session-1",
        currentRoute: XTUnifiedDoctorRouteSnapshot(
            transportMode: "local",
            routeLabel: "paired-local",
            pairingPort: 50052,
            grpcPort: 50051,
            internetHost: "127.0.0.1"
        ),
        sections: [
            XTUnifiedDoctorSection(
                kind: .hubReachability,
                state: .ready,
                headline: "Hub reachability is ready",
                summary: "Hub pairing and gRPC are reachable.",
                nextStep: "Proceed to the first task.",
                repairEntry: .homeSupervisor,
                detailLines: ["route=paired-local"]
            ),
            XTUnifiedDoctorSection(
                kind: .modelRouteReadiness,
                state: .diagnosticRequired,
                headline: "Model route is unavailable",
                summary: "No governed model route is available for the current task.",
                nextStep: "Choose a supported model in XT Settings and re-run diagnostics.",
                repairEntry: .xtChooseModel,
                detailLines: ["configured_models=0"]
            ),
            XTUnifiedDoctorSection(
                kind: .sessionRuntimeReadiness,
                state: .inProgress,
                headline: "Session runtime is recovering",
                summary: "Runtime recovery is still in progress.",
                nextStep: "Wait for recovery to finish, then re-run diagnostics.",
                repairEntry: .xtDiagnostics,
                detailLines: ["runtime_state=recovering"]
            )
        ],
        consumedContracts: ["xt.ui_surface_state_contract.v1", XTUnifiedDoctorReportContract.frozen.schemaVersion],
        reportPath: sourceReportPath
    )
}

private func sampleSkillDoctorTruthProjection() -> XTUnifiedDoctorSkillDoctorTruthProjection {
    XTUnifiedDoctorSkillDoctorTruthProjection(
        effectiveProfileSnapshot: sampleEffectiveSkillProfileSnapshot(),
        governanceEntries: [
            sampleSkillGovernanceEntry(
                skillID: "find-skills",
                executionReadiness: XTSkillExecutionReadinessState.ready.rawValue,
                capabilityProfiles: ["observe_only"],
                capabilityFamilies: ["skills.discover"]
            ),
            sampleSkillGovernanceEntry(
                skillID: "tavily-websearch",
                executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
                whyNotRunnable: "grant floor readonly still pending",
                grantFloor: XTSkillGrantFloor.readonly.rawValue,
                approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
                capabilityProfiles: ["browser_research"],
                capabilityFamilies: ["web.live"],
                unblockActions: ["request_hub_grant"]
            ),
            sampleSkillGovernanceEntry(
                skillID: "browser-operator",
                executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
                whyNotRunnable: "local approval still pending",
                grantFloor: XTSkillGrantFloor.none.rawValue,
                approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
                capabilityProfiles: ["browser_operator"],
                capabilityFamilies: ["browser.interact"],
                unblockActions: ["request_local_approval"]
            ),
            sampleSkillGovernanceEntry(
                skillID: "delivery-runner",
                executionReadiness: XTSkillExecutionReadinessState.policyClamped.rawValue,
                whyNotRunnable: "project capability bundle blocks repo.delivery",
                grantFloor: XTSkillGrantFloor.privileged.rawValue,
                approvalFloor: XTSkillApprovalFloor.hubGrantPlusLocalApproval.rawValue,
                capabilityProfiles: ["delivery"],
                capabilityFamilies: ["repo.delivery"],
                unblockActions: ["raise_execution_tier"]
            )
        ]
    )
}

private func sampleEffectiveSkillProfileSnapshot() -> XTProjectEffectiveSkillProfileSnapshot {
    XTProjectEffectiveSkillProfileSnapshot(
        schemaVersion: XTProjectEffectiveSkillProfileSnapshot.currentSchemaVersion,
        projectId: "project-alpha",
        projectName: "Alpha",
        source: "xt_project_governance+hub_skill_registry",
        executionTier: "a4_openclaw",
        runtimeSurfaceMode: "paired_hub",
        hubOverrideMode: "inherit",
        legacyToolProfile: "openclaw",
        discoverableProfiles: [
            "observe_only",
            "browser_research",
            "browser_operator",
            "delivery"
        ],
        installableProfiles: [
            "observe_only",
            "browser_research",
            "browser_operator",
            "delivery"
        ],
        requestableProfiles: [
            "observe_only",
            "browser_research",
            "browser_operator"
        ],
        runnableNowProfiles: [
            "observe_only"
        ],
        grantRequiredProfiles: [
            "browser_research"
        ],
        approvalRequiredProfiles: [
            "browser_operator"
        ],
        blockedProfiles: [
            XTProjectEffectiveSkillBlockedProfile(
                profileID: "delivery",
                reasonCode: "policy_clamped",
                state: XTSkillExecutionReadinessState.policyClamped.rawValue,
                source: "project_governance",
                unblockActions: ["raise_execution_tier"]
            )
        ],
        ceilingCapabilityFamilies: [
            "skills.discover",
            "web.live",
            "browser.interact"
        ],
        runnableCapabilityFamilies: [
            "skills.discover"
        ],
        localAutoApproveEnabled: false,
        trustedAutomationReady: true,
        profileEpoch: "epoch-1",
        trustRootSetHash: "trust-root-1",
        revocationEpoch: "revocation-1",
        officialChannelSnapshotID: "channel-1",
        runtimeSurfaceHash: "surface-1",
        auditRef: "audit-xt-skill-profile-alpha"
    )
}

private func sampleSkillGovernanceEntry(
    skillID: String,
    executionReadiness: String,
    whyNotRunnable: String = "",
    grantFloor: String = XTSkillGrantFloor.none.rawValue,
    approvalFloor: String = XTSkillApprovalFloor.none.rawValue,
    capabilityProfiles: [String],
    capabilityFamilies: [String],
    unblockActions: [String] = []
) -> AXSkillGovernanceSurfaceEntry {
    let readinessState = XTSkillCapabilityProfileSupport.readinessState(from: executionReadiness)
    let tone: AXSkillGovernanceTone = {
        switch readinessState {
        case .ready:
            return .ready
        case .grantRequired, .localApprovalRequired, .degraded:
            return .warning
        default:
            return .blocked
        }
    }()

    return AXSkillGovernanceSurfaceEntry(
        skillID: skillID,
        name: skillID,
        version: "1.0.0",
        riskLevel: "medium",
        packageSHA256: "sha-\(skillID)",
        publisherID: "publisher.test",
        sourceID: "source.test",
        policyScope: "project",
        tone: tone,
        stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(executionReadiness),
        intentFamilies: ["test.intent"],
        capabilityFamilies: capabilityFamilies,
        capabilityProfiles: capabilityProfiles,
        grantFloor: grantFloor,
        approvalFloor: approvalFloor,
        discoverabilityState: "discoverable",
        installabilityState: "installable",
        requestabilityState: "requestable",
        executionReadiness: executionReadiness,
        whyNotRunnable: whyNotRunnable,
        unblockActions: unblockActions,
        trustRootValue: "trusted",
        pinnedVersionValue: "1.0.0",
        runnerRequirementValue: "xt_builtin",
        compatibilityStatusValue: "compatible",
        preflightResultValue: "ready",
        note: "",
        installHint: ""
    )
}

private func sampleFirstPairCompletionProofSnapshot(
    readiness: XTPairedRouteReadiness,
    remoteShadowSmokeStatus: XTFirstPairRemoteShadowSmokeStatus,
    remoteShadowSmokePassed: Bool
) -> XTFirstPairCompletionProofSnapshot {
    XTFirstPairCompletionProofSnapshot(
        generatedAtMs: 1_741_300_000,
        readiness: readiness,
        sameLanVerified: true,
        ownerLocalApprovalVerified: true,
        pairingMaterialIssued: true,
        cachedReconnectSmokePassed: true,
        stableRemoteRoutePresent: true,
        remoteShadowSmokePassed: remoteShadowSmokePassed,
        remoteShadowSmokeStatus: remoteShadowSmokeStatus,
        remoteShadowSmokeSource: remoteShadowSmokeStatus == .failed
            ? .dedicatedStableRemoteProbe
            : nil,
        remoteShadowTriggeredAtMs: remoteShadowSmokeStatus == .failed ? 1_741_300_100 : nil,
        remoteShadowCompletedAtMs: remoteShadowSmokeStatus == .failed ? 1_741_300_120 : nil,
        remoteShadowRoute: remoteShadowSmokeStatus == .failed ? .internet : nil,
        remoteShadowReasonCode: remoteShadowSmokeStatus == .failed ? "grpc_unavailable" : nil,
        remoteShadowSummary: remoteShadowSmokeStatus == .failed
            ? "stable remote route shadow verification failed."
            : nil,
        summaryLine: "first pair completion proof snapshot"
    )
}

private func samplePairedRouteSetSnapshot(
    readiness: XTPairedRouteReadiness,
    readinessReasonCode: String,
    summaryLine: String
) -> XTPairedRouteSetSnapshot {
    XTPairedRouteSetSnapshot(
        readiness: readiness,
        readinessReasonCode: readinessReasonCode,
        summaryLine: summaryLine,
        hubInstanceID: "hub-smoke-1",
        pairingProfileEpoch: 4,
        routePackVersion: "route-pack-2026-03-30",
        activeRoute: XTPairedRouteTargetSnapshot(
            routeKind: .lan,
            host: "10.0.0.8",
            pairingPort: 50052,
            grpcPort: 50051,
            hostKind: "private_ipv4",
            source: .activeConnection
        ),
        lanRoute: XTPairedRouteTargetSnapshot(
            routeKind: .lan,
            host: "10.0.0.8",
            pairingPort: 50052,
            grpcPort: 50051,
            hostKind: "private_ipv4",
            source: .cachedProfileHost
        ),
        stableRemoteRoute: XTPairedRouteTargetSnapshot(
            routeKind: .internet,
            host: "hub.tailnet.example",
            pairingPort: 50052,
            grpcPort: 50051,
            hostKind: "stable_named",
            source: .cachedProfileInternetHost
        ),
        lastKnownGoodRoute: XTPairedRouteTargetSnapshot(
            routeKind: .lan,
            host: "10.0.0.8",
            pairingPort: 50052,
            grpcPort: 50051,
            hostKind: "private_ipv4",
            source: .freshPairReconnectSmoke
        ),
        cachedReconnectSmokeStatus: "succeeded",
        cachedReconnectSmokeReasonCode: nil,
        cachedReconnectSmokeSummary: "same-LAN cached reconnect succeeded"
    )
}

private func compactJSONString<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    let data = try! encoder.encode(value)
    return String(data: data, encoding: .utf8)!
}

private func sampleHeartbeatGovernanceProjection() -> XTUnifiedDoctorHeartbeatGovernanceProjection {
    XTUnifiedDoctorHeartbeatGovernanceProjection(
        snapshot: XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: "project-alpha",
            projectName: "Alpha",
            statusDigest: "done candidate",
            currentStateSummary: "Validation is wrapping up for release",
            nextStepSummary: "Ship release once final review clears",
            blockerSummary: "Pending pre-done review",
            lastHeartbeatAtMs: 1_741_300_000_000,
            latestQualityBand: .weak,
            latestQualityScore: 38,
            weakReasons: ["evidence_weak", "completion_confidence_low"],
            openAnomalyTypes: [.weakDoneClaim],
            projectPhase: .release,
            executionStatus: .doneCandidate,
            riskTier: .high,
            cadence: SupervisorCadenceExplainability(
                progressHeartbeat: SupervisorCadenceDimensionExplainability(
                    dimension: .progressHeartbeat,
                    configuredSeconds: 600,
                    recommendedSeconds: 180,
                    effectiveSeconds: 180,
                    effectiveReasonCodes: ["adjusted_for_project_phase_release"],
                    nextDueAtMs: 1_741_300_120_000,
                    nextDueReasonCodes: ["waiting_for_heartbeat_window"],
                    isDue: false
                ),
                reviewPulse: SupervisorCadenceDimensionExplainability(
                    dimension: .reviewPulse,
                    configuredSeconds: 1_200,
                    recommendedSeconds: 600,
                    effectiveSeconds: 600,
                    effectiveReasonCodes: [
                        "adjusted_for_project_phase_release",
                        "tightened_for_done_candidate_status"
                    ],
                    nextDueAtMs: 1_741_299_980_000,
                    nextDueReasonCodes: ["pulse_review_window_elapsed"],
                    isDue: true
                ),
                brainstormReview: SupervisorCadenceDimensionExplainability(
                    dimension: .brainstormReview,
                    configuredSeconds: 2_400,
                    recommendedSeconds: 1_200,
                    effectiveSeconds: 1_200,
                    effectiveReasonCodes: ["adjusted_for_project_phase_release"],
                    nextDueAtMs: 1_741_300_240_000,
                    nextDueReasonCodes: ["waiting_for_brainstorm_window"],
                    isDue: false
                ),
                eventFollowUpCooldownSeconds: 90
            ),
            digestExplainability: XTHeartbeatDigestExplainability(
                visibility: .shown,
                reasonCodes: ["weak_done_claim", "quality_weak", "review_candidate_active"],
                whatChangedText: "项目已接近完成，但完成声明证据偏弱。",
                whyImportantText: "完成声明证据偏弱，系统不能把“快做完了”直接当成真实完成。",
                systemNextStepText: "Ship release once final review clears"
            ),
            recoveryDecision: HeartbeatRecoveryDecision(
                action: .queueStrategicReview,
                urgency: .urgent,
                reasonCode: "heartbeat_or_lane_signal_requires_governance_review",
                summary: "Queue a deeper governance review before resuming autonomous execution.",
                sourceSignals: [
                    "anomaly:weak_done_claim",
                    "review_candidate:pre_done_summary:r3_rescue:event_driven"
                ],
                anomalyTypes: [.weakDoneClaim],
                blockedLaneReasons: [],
                blockedLaneCount: 0,
                stalledLaneCount: 0,
                failedLaneCount: 0,
                recoveringLaneCount: 0,
                requiresUserAction: false,
                queuedReviewTrigger: .preDoneSummary,
                queuedReviewLevel: .r3Rescue,
                queuedReviewRunKind: .eventDriven
            ),
            projectMemoryReadiness: XTProjectMemoryAssemblyReadiness(
                ready: false,
                statusLine: "attention:project_memory_usage_missing",
                issues: [
                    XTProjectMemoryAssemblyIssue(
                        code: "project_memory_usage_missing",
                        severity: .warning,
                        summary: "尚未捕获 Project AI 的最近一次 memory 装配真相",
                        detail: "Doctor 当前只能看到配置基线，还没有 recent coder usage 来证明 Project AI 最近一轮真正吃到了哪些 memory objects / planes。"
                    )
                ]
            )
        )
    )
}

private func sampleSuppressedHeartbeatGovernanceProjection() -> XTUnifiedDoctorHeartbeatGovernanceProjection {
    XTUnifiedDoctorHeartbeatGovernanceProjection(
        snapshot: XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: "project-beta",
            projectName: "Beta",
            statusDigest: "stable",
            currentStateSummary: "Validation remains on track",
            nextStepSummary: "Wait for a meaningful project delta before notifying the user",
            blockerSummary: "",
            lastHeartbeatAtMs: 1_741_300_060_000,
            latestQualityBand: .usable,
            latestQualityScore: 82,
            weakReasons: [],
            openAnomalyTypes: [],
            projectPhase: .verify,
            executionStatus: .active,
            riskTier: .medium,
            cadence: SupervisorCadenceExplainability(
                progressHeartbeat: SupervisorCadenceDimensionExplainability(
                    dimension: .progressHeartbeat,
                    configuredSeconds: 600,
                    recommendedSeconds: 300,
                    effectiveSeconds: 300,
                    effectiveReasonCodes: ["adjusted_for_verification_phase"],
                    nextDueAtMs: 1_741_300_360_000,
                    nextDueReasonCodes: ["waiting_for_heartbeat_window"],
                    isDue: false
                ),
                reviewPulse: SupervisorCadenceDimensionExplainability(
                    dimension: .reviewPulse,
                    configuredSeconds: 1_200,
                    recommendedSeconds: 1_200,
                    effectiveSeconds: 1_200,
                    effectiveReasonCodes: ["configured_equals_recommended"],
                    nextDueAtMs: 1_741_300_900_000,
                    nextDueReasonCodes: ["waiting_for_pulse_window"],
                    isDue: false
                ),
                brainstormReview: SupervisorCadenceDimensionExplainability(
                    dimension: .brainstormReview,
                    configuredSeconds: 2_400,
                    recommendedSeconds: 2_400,
                    effectiveSeconds: 2_400,
                    effectiveReasonCodes: ["configured_equals_recommended"],
                    nextDueAtMs: 1_741_301_800_000,
                    nextDueReasonCodes: ["waiting_for_no_progress_window"],
                    isDue: false
                ),
                eventFollowUpCooldownSeconds: 600
            ),
            digestExplainability: XTHeartbeatDigestExplainability(
                visibility: .suppressed,
                reasonCodes: ["stable_runtime_update_suppressed"],
                whatChangedText: "Validation remains on track",
                whyImportantText: "当前没有新的高风险或高优先级治理信号，所以这条 digest 被压制。",
                systemNextStepText: "系统会继续观察当前项目，有实质变化再生成用户 digest。"
            ),
            recoveryDecision: nil
        )
    )
}

private func sampleGrantFollowUpHeartbeatGovernanceProjection() -> XTUnifiedDoctorHeartbeatGovernanceProjection {
    XTUnifiedDoctorHeartbeatGovernanceProjection(
        snapshot: XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: "project-grant",
            projectName: "Grant",
            statusDigest: "waiting for grant",
            currentStateSummary: "Automation is paused on repo write grant review",
            nextStepSummary: "Wait for the required grant follow-up before resuming",
            blockerSummary: "Repo write grant pending",
            lastHeartbeatAtMs: 1_741_300_090_000,
            latestQualityBand: .usable,
            latestQualityScore: 71,
            weakReasons: [],
            openAnomalyTypes: [],
            projectPhase: .build,
            executionStatus: .blocked,
            riskTier: .medium,
            cadence: SupervisorCadenceExplainability(
                progressHeartbeat: SupervisorCadenceDimensionExplainability(
                    dimension: .progressHeartbeat,
                    configuredSeconds: 300,
                    recommendedSeconds: 300,
                    effectiveSeconds: 300,
                    effectiveReasonCodes: ["configured_equals_recommended"],
                    nextDueAtMs: 1_741_300_390_000,
                    nextDueReasonCodes: ["waiting_for_heartbeat_window"],
                    isDue: false
                ),
                reviewPulse: SupervisorCadenceDimensionExplainability(
                    dimension: .reviewPulse,
                    configuredSeconds: 900,
                    recommendedSeconds: 900,
                    effectiveSeconds: 900,
                    effectiveReasonCodes: ["configured_equals_recommended"],
                    nextDueAtMs: 1_741_300_990_000,
                    nextDueReasonCodes: ["waiting_for_pulse_window"],
                    isDue: false
                ),
                brainstormReview: SupervisorCadenceDimensionExplainability(
                    dimension: .brainstormReview,
                    configuredSeconds: 1_800,
                    recommendedSeconds: 1_800,
                    effectiveSeconds: 1_800,
                    effectiveReasonCodes: ["configured_equals_recommended"],
                    nextDueAtMs: 1_741_301_890_000,
                    nextDueReasonCodes: ["waiting_for_no_progress_window"],
                    isDue: false
                ),
                eventFollowUpCooldownSeconds: 300
            ),
            digestExplainability: XTHeartbeatDigestExplainability(
                visibility: .shown,
                reasonCodes: ["recovery_decision_active"],
                whatChangedText: "当前项目没有新的高信号进展，但 grant 相关恢复动作已经激活。",
                whyImportantText: "系统已判断当前需要先补齐 grant 跟进，不能把状态当成正常推进。",
                systemNextStepText: "系统会先发起所需 grant 跟进，待放行后再继续恢复执行。"
            ),
            recoveryDecision: HeartbeatRecoveryDecision(
                action: .requestGrantFollowUp,
                urgency: .active,
                reasonCode: "grant_follow_up_required",
                summary: "Request the required grant follow-up before resuming autonomous execution.",
                sourceSignals: [
                    "lane_blocked_reason:grant_pending",
                    "lane_blocked_count:1"
                ],
                anomalyTypes: [],
                blockedLaneReasons: [.grantPending],
                blockedLaneCount: 1,
                stalledLaneCount: 0,
                failedLaneCount: 0,
                recoveringLaneCount: 0,
                requiresUserAction: true,
                queuedReviewTrigger: nil,
                queuedReviewLevel: nil,
                queuedReviewRunKind: nil
            )
        )
    )
}

private func sampleReplayFollowUpHeartbeatGovernanceProjection() -> XTUnifiedDoctorHeartbeatGovernanceProjection {
    XTUnifiedDoctorHeartbeatGovernanceProjection(
        snapshot: XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: "project-replay",
            projectName: "Replay",
            statusDigest: "queue stalled",
            currentStateSummary: "Execution queue is stalled during drain recovery",
            nextStepSummary: "Replay the pending follow-up after the drain completes",
            blockerSummary: "Drain replay pending",
            lastHeartbeatAtMs: 1_741_300_120_000,
            latestQualityBand: .weak,
            latestQualityScore: 54,
            weakReasons: [],
            openAnomalyTypes: [.queueStall],
            projectPhase: .verify,
            executionStatus: .blocked,
            riskTier: .medium,
            cadence: SupervisorCadenceExplainability(
                progressHeartbeat: SupervisorCadenceDimensionExplainability(
                    dimension: .progressHeartbeat,
                    configuredSeconds: 300,
                    recommendedSeconds: 300,
                    effectiveSeconds: 300,
                    effectiveReasonCodes: ["configured_equals_recommended"],
                    nextDueAtMs: 1_741_300_420_000,
                    nextDueReasonCodes: ["waiting_for_heartbeat_window"],
                    isDue: false
                ),
                reviewPulse: SupervisorCadenceDimensionExplainability(
                    dimension: .reviewPulse,
                    configuredSeconds: 900,
                    recommendedSeconds: 900,
                    effectiveSeconds: 900,
                    effectiveReasonCodes: ["configured_equals_recommended"],
                    nextDueAtMs: 1_741_301_020_000,
                    nextDueReasonCodes: ["waiting_for_pulse_window"],
                    isDue: false
                ),
                brainstormReview: SupervisorCadenceDimensionExplainability(
                    dimension: .brainstormReview,
                    configuredSeconds: 1_800,
                    recommendedSeconds: 1_800,
                    effectiveSeconds: 1_800,
                    effectiveReasonCodes: ["configured_equals_recommended"],
                    nextDueAtMs: 1_741_301_920_000,
                    nextDueReasonCodes: ["waiting_for_no_progress_window"],
                    isDue: false
                ),
                eventFollowUpCooldownSeconds: 300
            ),
            digestExplainability: XTHeartbeatDigestExplainability(
                visibility: .shown,
                reasonCodes: ["recovery_decision_active"],
                whatChangedText: "当前项目没有新的高信号进展，但 follow-up 恢复动作已经激活。",
                whyImportantText: "系统已判断当前要先重放挂起的续跑链，不能把状态当成正常推进。",
                systemNextStepText: "系统会在当前 drain 收口后，重放挂起的 follow-up / 续跑链，再确认执行是否恢复。"
            ),
            recoveryDecision: HeartbeatRecoveryDecision(
                action: .replayFollowUp,
                urgency: .active,
                reasonCode: "restart_drain_requires_follow_up_replay",
                summary: "Replay the pending follow-up or recovery chain after the current drain finishes.",
                sourceSignals: [
                    "anomaly:queue_stall",
                    "lane_blocked_reason:restart_drain",
                    "lane_blocked_count:1"
                ],
                anomalyTypes: [.queueStall],
                blockedLaneReasons: [.restartDrain],
                blockedLaneCount: 1,
                stalledLaneCount: 0,
                failedLaneCount: 0,
                recoveringLaneCount: 0,
                requiresUserAction: false,
                queuedReviewTrigger: .blockerDetected,
                queuedReviewLevel: .r2Strategic,
                queuedReviewRunKind: .eventDriven
            )
        )
    )
}

private func sampleHubDoctorOutputReport(outputPath: String) -> XHubDoctorOutputReport {
    XHubDoctorOutputReport(
        schemaVersion: XHubDoctorOutputReport.currentSchemaVersion,
        contractVersion: XHubDoctorOutputReport.currentContractVersion,
        reportID: "xhub-doctor-hub-hub_ui-1741300000",
        bundleKind: .providerRuntimeReadiness,
        producer: .xHub,
        surface: .hubUI,
        overallState: .blocked,
        summary: XHubDoctorOutputSummary(
            headline: "Hub-managed local service is unreachable",
            passed: 1,
            failed: 1,
            warned: 0,
            skipped: 0
        ),
        readyForFirstTask: false,
        checks: [
            XHubDoctorOutputCheckResult(
                checkID: "xhub_local_service_unreachable",
                checkKind: "provider_readiness",
                status: .fail,
                severity: .error,
                blocking: true,
                headline: "Hub-managed local service is unreachable",
                message: "Providers are pinned to xhub_local_service, but Hub cannot reach /health.",
                nextStep: "Start xhub_local_service or fix the configured endpoint, then refresh diagnostics.",
                repairDestinationRef: "hub://settings/diagnostics",
                detailLines: [
                    "ready_providers=none",
                    "managed_service_ready_count=0",
                    "provider=local-chat service_state=unreachable ready=0 runtime_reason=xhub_local_service_unreachable endpoint=http://127.0.0.1:50171 execution_mode=xhub_local_service loaded_instances=0 queued=1"
                ],
                projectContextSummary: nil,
                observedAtMs: 1_741_300_000
            )
        ],
        nextSteps: [
            XHubDoctorOutputNextStep(
                stepID: "provider_readiness",
                kind: .repairRuntime,
                label: "Repair Runtime",
                owner: .hubRuntime,
                blocking: true,
                destinationRef: "hub://settings/diagnostics",
                instruction: "Start xhub_local_service or fix the configured endpoint, then refresh diagnostics."
            )
        ],
        routeSnapshot: nil,
        generatedAtMs: 1_741_300_000,
        reportPath: outputPath,
        sourceReportSchemaVersion: "ai_runtime_status.v1",
        sourceReportPath: "/tmp/ai_runtime_status.json",
        currentFailureCode: "xhub_local_service_unreachable",
        currentFailureIssue: nil,
        consumedContracts: ["xhub.doctor_output.v1"]
    )
}

private func sampleHubLocalServiceSnapshotReport() -> XHubLocalServiceSnapshotReport {
    XHubLocalServiceSnapshotReport(
        schemaVersion: "xhub_local_service_snapshot_export.v1",
        generatedAtMs: 1_741_300_100,
        statusSource: "/tmp/ai_runtime_status.json",
        runtimeAlive: true,
        providerCount: 1,
        readyProviderCount: 0,
        primaryIssue: XHubLocalServiceSnapshotPrimaryIssue(
            reasonCode: "xhub_local_service_unreachable",
            headline: "Hub-managed local service is unreachable",
            message: "Providers are pinned to xhub_local_service, but Hub cannot reach /health.",
            nextStep: "Inspect the managed service snapshot and stderr log, fix the launch error, then refresh diagnostics."
        ),
        doctorProjection: XHubLocalServiceSnapshotDoctorProjection(
            overallState: .blocked,
            readyForFirstTask: false,
            currentFailureCode: "xhub_local_service_unreachable",
            currentFailureIssue: "provider_readiness",
            providerCheckStatus: .fail,
            providerCheckBlocking: true,
            headline: "Hub-managed local service is unreachable",
            message: "Providers are pinned to xhub_local_service, but Hub cannot reach /health.",
            nextStep: "Inspect the managed service snapshot and stderr log, fix the launch error, then refresh diagnostics.",
            repairDestinationRef: "hub://settings/diagnostics"
        ),
        providers: [
            XHubLocalServiceProviderEvidence(
                providerID: "local-chat",
                serviceState: "unreachable",
                runtimeReasonCode: "xhub_local_service_unreachable",
                serviceBaseURL: "http://127.0.0.1:50171",
                executionMode: "xhub_local_service",
                loadedInstanceCount: 0,
                queuedTaskCount: 1,
                ready: false
            )
        ]
    )
}

private func sampleHubLocalServiceRecoveryGuidanceReport() -> XHubLocalServiceRecoveryGuidanceReport {
    XHubLocalServiceRecoveryGuidanceReport(
        schemaVersion: "xhub_local_service_recovery_guidance_export.v1",
        generatedAtMs: 1_741_300_200,
        statusSource: "/tmp/ai_runtime_status.json",
        runtimeAlive: true,
        guidancePresent: true,
        providerCount: 1,
        readyProviderCount: 0,
        currentFailureCode: "xhub_local_service_unreachable",
        currentFailureIssue: "provider_readiness",
        providerCheckStatus: XHubDoctorCheckStatus.fail.rawValue,
        providerCheckBlocking: true,
        actionCategory: "inspect_health_payload",
        severity: "high",
        installHint: "Inspect the local /health payload and stderr log to confirm why xhub_local_service never reached ready.",
        repairDestinationRef: "hub://settings/diagnostics",
        serviceBaseURL: "http://127.0.0.1:50171",
        managedProcessState: "running",
        managedStartAttemptCount: 3,
        managedLastStartError: "",
        managedLastProbeError: "connect ECONNREFUSED 127.0.0.1:50171",
        blockedCapabilities: ["ai.embed.local"],
        primaryIssue: XHubLocalServiceSnapshotPrimaryIssue(
            reasonCode: "xhub_local_service_unreachable",
            headline: "Hub-managed local service is unreachable",
            message: "Providers are pinned to xhub_local_service, but Hub cannot reach /health.",
            nextStep: "Inspect the managed service snapshot and stderr log, fix the launch error, then refresh diagnostics."
        ),
        recommendedActions: [
            XHubLocalServiceRecoveryGuidanceAction(
                rank: 1,
                actionID: "inspect_health_payload",
                title: "Inspect the local /health payload",
                why: "The service process exists but never reported a ready health payload.",
                commandOrReference: "Open Hub Diagnostics and compare /health with stderr."
            ),
        ],
        supportFAQ: [
            XHubLocalServiceRecoveryGuidanceFAQItem(
                faqID: "faq-1",
                question: "Why does XT stay blocked after pairing succeeds?",
                answer: "Pairing only proves the surfaces can talk. Hub still blocks first-task readiness until the managed local runtime reaches ready."
            ),
        ]
    )
}

private func governanceRuntimeReadinessSnapshot(
    configuredExecutionTier: String = AXProjectExecutionTier.a4OpenClaw.rawValue,
    effectiveExecutionTier: String = AXProjectExecutionTier.a4OpenClaw.rawValue,
    configuredRuntimeSurfaceMode: String = AXProjectRuntimeSurfaceMode.trustedOpenClawMode.rawValue,
    effectiveRuntimeSurfaceMode: String = AXProjectRuntimeSurfaceMode.trustedOpenClawMode.rawValue,
    runtimeSurfaceOverrideMode: String = "none",
    trustedAutomationState: String = AXTrustedAutomationProjectState.blocked.rawValue,
    requiresA4RuntimeReady: Bool = true,
    runtimeReady: Bool,
    state: AXProjectGovernanceRuntimeReadinessState,
    missingReasonCodes: [String],
    summaryLine: String,
    missingSummaryLine: String? = nil,
    effectiveSurfaceCapabilities: [String]? = nil
) -> AXProjectGovernanceRuntimeReadinessSnapshot {
    let resolvedEffectiveSurfaceCapabilities: [String]
    if let effectiveSurfaceCapabilities {
        resolvedEffectiveSurfaceCapabilities = effectiveSurfaceCapabilities
    } else if let mode = AXProjectRuntimeSurfaceMode(rawValue: effectiveRuntimeSurfaceMode) {
        switch mode {
        case .manual:
            resolvedEffectiveSurfaceCapabilities = []
        case .guided:
            resolvedEffectiveSurfaceCapabilities = ["browser"]
        case .trustedOpenClawMode:
            resolvedEffectiveSurfaceCapabilities = ["device", "browser", "connector", "extension"]
        }
    } else {
        resolvedEffectiveSurfaceCapabilities = []
    }

    var detailLines = [
        "project_governance_runtime_readiness_schema_version=\(AXProjectGovernanceRuntimeReadinessSnapshot.currentSchemaVersion)",
        "project_governance_configured_execution_tier=\(configuredExecutionTier)",
        "project_governance_effective_execution_tier=\(effectiveExecutionTier)",
        "project_governance_configured_runtime_surface_mode=\(configuredRuntimeSurfaceMode)",
        "project_governance_effective_runtime_surface_mode=\(effectiveRuntimeSurfaceMode)",
        "project_governance_runtime_surface_override_mode=\(runtimeSurfaceOverrideMode)",
        "project_governance_trusted_automation_state=\(trustedAutomationState)",
        "project_governance_requires_a4_runtime_ready=\(requiresA4RuntimeReady)",
        "project_governance_runtime_ready=\(runtimeReady)",
        "project_governance_runtime_readiness_state=\(state.rawValue)",
        "project_governance_effective_surface_capabilities=\(resolvedEffectiveSurfaceCapabilities.joined(separator: ","))",
        "project_governance_runtime_readiness_summary=\(summaryLine)"
    ]
    if !missingReasonCodes.isEmpty {
        detailLines.append(
            "project_governance_missing_readiness=\(missingReasonCodes.joined(separator: ","))"
        )
    }
    if let missingSummaryLine, !missingSummaryLine.isEmpty {
        detailLines.append(
            "project_governance_runtime_readiness_missing_summary=\(missingSummaryLine)"
        )
    }
    return AXProjectGovernanceRuntimeReadinessSnapshot(detailLines: detailLines)!
}

private func sampleHubLocalRuntimeMonitorSnapshotReport() -> XHubLocalRuntimeMonitorSnapshotReport {
    XHubLocalRuntimeMonitorSnapshotReport(
        schemaVersion: "xhub_local_runtime_monitor_export.v1",
        generatedAtMs: 1_741_300_300,
        statusSource: "/tmp/ai_runtime_status.json",
        runtimeAlive: true,
        monitorSummary: "monitor_provider_count=1\nmonitor_active_task_count=1",
        hostMetrics: XHubLocalRuntimeHostMetricsReport(
            sampledAtMs: 1_741_300_300,
            sampleWindowMs: 5_000,
            cpuUsagePercent: 91.5,
            cpuCoreCount: 8,
            loadAverage1m: 7.2,
            loadAverage5m: 6.3,
            loadAverage15m: 5.9,
            normalizedLoadAverage1m: 0.9,
            memoryPressure: "high",
            memoryUsedBytes: 24_000_000_000,
            memoryAvailableBytes: 2_000_000_000,
            memoryCompressedBytes: 3_000_000_000,
            thermalState: "serious",
            severity: "high",
            summary: "host_load_severity=high cpu_percent=91.5 load_avg=7.20/6.30/5.90 normalized_1m=0.90 memory_pressure=high thermal_state=serious",
            detailLines: [
                "host_load_severity=high cpu_percent=91.5 load_avg=7.20/6.30/5.90 normalized_1m=0.90 memory_pressure=high thermal_state=serious",
                "host_memory_bytes used=24000000000 available=2000000000 compressed=3000000000",
                "host_cpu_context cpu_cores=8 sample_window_ms=5000"
            ]
        ),
        runtimeOperations: XHubLocalRuntimeMonitorOperationsReport(
            runtimeSummary: "provider=transformers state=fallback",
            queueSummary: "1 个执行中 · 2 个排队中",
            loadedSummary: "1 个已加载实例",
            currentTargets: [
                XHubLocalRuntimeMonitorCurrentTargetEvidence(
                    modelID: "bge-small",
                    modelName: "BGE Small",
                    providerID: "transformers",
                    uiSummary: "配对目标",
                    technicalSummary: "loaded_instance_preferred_profile",
                    loadSummary: "ctx=8192 · ttl=600s · par=2 · id=diag-a"
                )
            ],
            loadedInstances: [
                XHubLocalRuntimeMonitorLoadedInstanceEvidence(
                    providerID: "transformers",
                    modelID: "bge-small",
                    modelName: "BGE Small",
                    loadSummary: "ctx 8192 · ttl 600s · par 2 · 加载配置 diag-a",
                    detailSummary: "transformers · resident · mps · 配置 diag-a",
                    currentTargetSummary: "配对目标"
                )
            ]
        )
    )
}
