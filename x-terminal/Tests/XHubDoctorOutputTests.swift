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
                "personal_memory_excluded_reason=project_ai_default_scopes_to_project_memory_only"
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
                userSourceBadge: "实际运行",
                userStatusLine: "结构化 source report 直出。",
                userDialogueMetric: "Extended 40 Pairs · 40 pairs",
                userDepthMetric: "Full",
                userCoverageSummary: "已带工作流、执行证据、关联线索",
                userBoundarySummary: "默认不读取你的个人记忆",
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
