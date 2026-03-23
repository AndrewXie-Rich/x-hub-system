import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct XTUnifiedDoctorReportTests {
    @Test
    func distinguishesPairingOkButModelRouteUnavailable() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        #expect(report.section(.pairingValidity)?.state == .ready)
        #expect(report.section(.modelRouteReadiness)?.state == .diagnosticRequired)
        #expect(report.section(.modelRouteReadiness)?.headline == "配对已通，但模型路由不可用")
        #expect(report.readyForFirstTask == false)
    }

    @Test
    func distinguishesModelRouteOkButBridgeUnavailable() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        #expect(report.section(.modelRouteReadiness)?.state == .ready)
        #expect(report.section(.bridgeToolReadiness)?.state == .diagnosticRequired)
        #expect(report.section(.bridgeToolReadiness)?.headline == "模型路由已通，但桥接 / 工具链路不可用")
    }

    @Test
    func bridgeSectionSurfacesLastEnableDeliveryFailure() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false,
                bridgeLastError: "bridge_enable_command_write_failed=POSIXError: No space left on device",
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        let section = report.section(.bridgeToolReadiness)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.summary.contains("bridge enable 请求也在链路恢复前失败了") == true)
        #expect(section?.detailLines.contains(where: { $0.contains("bridge_last_error=") }) == true)
    }

    @Test
    func distinguishesBridgeOkButRuntimeNotRecoverable() {
        let model = sampleModel(id: "hub.model.supervisor")
        let runtime = AXSessionRuntimeSnapshot(
            schemaVersion: AXSessionRuntimeSnapshot.currentSchemaVersion,
            state: .failed_recoverable,
            runID: "run-1",
            updatedAt: Date().timeIntervalSince1970,
            startedAt: Date().timeIntervalSince1970 - 20,
            completedAt: nil,
            lastRuntimeSummary: "tool batch failed",
            lastToolBatchIDs: ["batch-1"],
            pendingToolCallCount: 0,
            lastFailureCode: "runtime_recoverability_lost",
            resumeToken: nil,
            recoverable: false
        )
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: runtime,
                sessionID: "session-1",
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        #expect(report.section(.bridgeToolReadiness)?.state == .ready)
        #expect(report.section(.sessionRuntimeReadiness)?.state == .diagnosticRequired)
        #expect(report.section(.sessionRuntimeReadiness)?.headline == "Bridge 已通，但会话运行时不可恢复")
    }

    @Test
    func sessionRuntimeSectionIncludesProjectContextDiagnosticsWhenAvailable() {
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=latest_coder_usage",
                "project_context_project=Snake",
                "recent_project_dialogue_profile=extended_40_pairs",
                "recent_project_dialogue_floor_satisfied=true",
                "project_context_depth=full",
                "effective_project_serving_profile=m4_full_scan"
            ]
        )
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                projectContextDiagnostics: diagnostics
            )
        )

        let section = report.section(.sessionRuntimeReadiness)
        #expect(section?.state == .ready)
        #expect(section?.detailLines.contains("project_context_project=Snake") == true)
        #expect(section?.detailLines.contains("recent_project_dialogue_profile=extended_40_pairs") == true)
        #expect(section?.detailLines.contains("project_context_depth=full") == true)
        #expect(section?.projectContextPresentation?.sourceKind == .latestCoderUsage)
        #expect(section?.projectContextPresentation?.projectLabel == "Snake")
        #expect(section?.projectContextPresentation?.dialogueMetric.contains("40 pairs") == true)
        #expect(section?.projectContextPresentation?.depthMetric.contains("Full") == true)
    }

    @Test
    func sessionRuntimeSectionIncludesDurableCandidateMirrorProjectionWhenAvailable() {
        let model = sampleModel(id: "hub.model.coder")
        let mirrorSnapshot = makeSupervisorMemoryAssemblySnapshot(
            durableCandidateMirrorStatus: .localOnly,
            durableCandidateMirrorTarget: XTSupervisorDurableCandidateMirror.mirrorTarget,
            durableCandidateMirrorAttempted: true,
            durableCandidateMirrorErrorCode: "remote_route_not_preferred",
            durableCandidateLocalStoreRole: XTSupervisorDurableCandidateMirror.localStoreRole
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                supervisorMemoryAssemblySnapshot: mirrorSnapshot
            )
        )

        let section = report.section(.sessionRuntimeReadiness)
        #expect(section?.state == .ready)
        #expect(section?.detailLines.contains(where: {
            $0.contains("durable_candidate_mirror status=local_only")
                && $0.contains("reason=remote_route_not_preferred")
                && $0.contains("local_store_role=\(XTSupervisorDurableCandidateMirror.localStoreRole)")
        }) == true)
        #expect(section?.durableCandidateMirrorProjection?.status == .localOnly)
        #expect(section?.durableCandidateMirrorProjection?.target == XTSupervisorDurableCandidateMirror.mirrorTarget)
        #expect(section?.durableCandidateMirrorProjection?.attempted == true)
        #expect(section?.durableCandidateMirrorProjection?.errorCode == "remote_route_not_preferred")
        #expect(section?.durableCandidateMirrorProjection?.localStoreRole == XTSupervisorDurableCandidateMirror.localStoreRole)
    }

    @Test
    func builderPublishesFrozenSourceReportContractInConsumedContracts() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        #expect(report.consumedContracts.contains(XTUnifiedDoctorReportContract.frozen.schemaVersion))
        #expect(!report.consumedContracts.contains(XTUnifiedDoctorReport.currentSchemaVersion))
    }

    @Test
    func writesMachineReadableReportWithSkillsSection() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let model = sampleModel(id: "hub.model.coder")
        var skills = readySkillsSnapshot()
        skills.installedSkillCount = 1
        skills.compatibleSkillCount = 1
        skills.statusLine = "skills 1/1"

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: skills,
                reportPath: reportURL.path
            )
        )
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: data)

        #expect(decoded.schemaVersion == XTUnifiedDoctorReport.currentSchemaVersion)
        #expect(decoded.reportPath == reportURL.path)
        #expect(decoded.section(.skillsCompatibilityReadiness) != nil)
        #expect(decoded.section(.wakeProfileReadiness) != nil)
        #expect(decoded.section(.talkLoopReadiness) != nil)
        #expect(decoded.sections.count == XTUnifiedDoctorSectionKind.allCases.count)
    }

    @Test
    func fallsBackToNonAtomicOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let capture = XTUnifiedDoctorStoreTestCapture()
        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{\"stale\":true}\n".utf8).write(to: reportURL)

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [sampleModel(id: "hub.model.coder").id],
                models: [sampleModel(id: "hub.model.coder")],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                reportPath: reportURL.path
            )
        )

        XTUnifiedDoctorStore.installWriteAttemptOverrideForTesting { data, url, options in
            capture.appendWriteOption(options)
            if options.contains(.atomic) {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: url, options: options)
        }
        XTUnifiedDoctorStore.installLogSinkForTesting { line in
            capture.appendLogLine(line)
        }
        defer { XTUnifiedDoctorStore.resetWriteBehaviorForTesting() }

        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let decoded = try JSONDecoder().decode(
            XTUnifiedDoctorReport.self,
            from: Data(contentsOf: reportURL)
        )
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(capture.logLinesSnapshot().isEmpty)
        #expect(decoded.reportPath == reportURL.path)
    }

    @Test
    func suppressesRepeatedWriteFailureLogsDuringCooldown() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let capture = XTUnifiedDoctorStoreTestCapture()
        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [sampleModel(id: "hub.model.coder").id],
                models: [sampleModel(id: "hub.model.coder")],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                reportPath: reportURL.path
            )
        )

        XTUnifiedDoctorStore.installNowProviderForTesting {
            Date(timeIntervalSince1970: 1_741_300_000)
        }
        XTUnifiedDoctorStore.installWriteAttemptOverrideForTesting { _, _, options in
            capture.appendWriteOption(options)
            throw NSError(domain: NSPOSIXErrorDomain, code: 28)
        }
        XTUnifiedDoctorStore.installLogSinkForTesting { line in
            capture.appendLogLine(line)
        }
        defer { XTUnifiedDoctorStore.resetWriteBehaviorForTesting() }

        XTUnifiedDoctorStore.writeReport(report, to: reportURL)
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let logLines = capture.logLinesSnapshot()
        #expect(logLines.count == 1)
        #expect(logLines[0].contains("XTUnifiedDoctor write report failed"))
        #expect(capture.writeOptionsSnapshot().count == 2)
    }

    @Test
    func skillsSectionRequiresDefaultBaselineWhenMissing() {
        let model = sampleModel(id: "hub.model.coder")
        var skills = readySkillsSnapshot()
        skills.statusKind = .partial
        skills.missingBaselineSkillIDs = ["find-skills", "agent-browser"]
        skills.baselineRecommendedSkills = [
            AXDefaultAgentBaselineSkill(skillID: "find-skills", displayName: "Find Skills", summary: ""),
            AXDefaultAgentBaselineSkill(skillID: "agent-browser", displayName: "Agent Browser", summary: ""),
            AXDefaultAgentBaselineSkill(skillID: "self-improving-agent", displayName: "Self Improving Agent", summary: ""),
            AXDefaultAgentBaselineSkill(skillID: "summarize", displayName: "Summarize", summary: ""),
        ]
        skills.statusLine = "skills~ 0/0 b2/4"
        skills.compatibilityExplain = "baseline_missing=find-skills,agent-browser"

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: skills
            )
        )

        let section = report.section(.skillsCompatibilityReadiness)
        #expect(report.readyForFirstTask == true)
        #expect(report.overallSummary != "配对、模型路由、工具链路和会话运行时已在同一路径验证通过")
        #expect(report.overallSummary.contains("仍需修复") == true)
        #expect(section?.state == .inProgress)
        #expect(section?.headline == "Default Agent 基线还不完整")
        #expect(section?.nextStep.contains("find-skills") == true)
        #expect(section?.nextStep.contains("agent-browser") == true)
    }

    @Test
    func skillsSectionShowsLocalDevPublisherCoverageWhenActive() {
        let model = sampleModel(id: "hub.model.coder")
        var skills = readySkillsSnapshot()
        skills.installedSkillCount = 4
        skills.compatibleSkillCount = 4
        skills.baselineRecommendedSkills = defaultBaselineSkills()
        skills.installedSkills = defaultBaselineSkillEntries(publisherID: AXSkillsDoctorSnapshot.localDevPublisherID)
        skills.statusLine = "skills 4/4 b4/4"

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: skills
            )
        )

        let section = report.section(.skillsCompatibilityReadiness)
        #expect(section?.state == .ready)
        #expect(section?.detailLines.contains("active_publishers=xhub.local.dev") == true)
        #expect(section?.detailLines.contains("local_dev_publisher_active=yes") == true)
        #expect(section?.detailLines.contains("baseline_publishers=xhub.local.dev") == true)
        #expect(section?.detailLines.contains("baseline_local_dev=4/4") == true)
    }

    @Test
    func skillsSectionKeepsBuiltinGovernedSkillsVisibleWhenHubIndexIsUnavailable() {
        let model = sampleModel(id: "hub.model.coder")
        var skills = readySkillsSnapshot()
        skills.hubIndexAvailable = false
        skills.statusKind = .unavailable
        skills.statusLine = "skills?"
        skills.compatibilityExplain = "skills compatibility unavailable"
        skills.builtinGovernedSkills = defaultBuiltinGovernedSkills()

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: skills
            )
        )

        let section = report.section(.skillsCompatibilityReadiness)
        #expect(section?.detailLines.contains("xt_builtin_governed_skills=1") == true)
        #expect(section?.detailLines.contains("xt_builtin_governed_preview=supervisor-voice") == true)
        #expect(section?.detailLines.contains("xt_builtin_supervisor_voice=available") == true)
        #expect(section?.summary.contains("built-in governed skills 仍可用") == true)
    }

    @Test
    func modelRouteSectionSurfacesRecentProjectIncidentsWithoutPretendingHubIsMissing() {
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXModelRouteDiagnosticsSummary(
            recentEventCount: 1,
            recentFailureCount: 1,
            recentRemoteRetryRecoveryCount: 0,
            latestEvent: AXModelRouteDiagnosticEvent(
                schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
                createdAt: 1_741_300_020,
                projectId: "project-alpha",
                projectDisplayName: "Alpha",
                role: "coder",
                stage: "chat_plan",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "qwen3-14b-mlx",
                runtimeProvider: "Hub (Local)",
                executionPath: "hub_downgraded_to_local",
                fallbackReasonCode: "downgrade_to_local",
                remoteRetryAttempted: false,
                remoteRetryFromModelId: "",
                remoteRetryToModelId: "",
                remoteRetryReasonCode: ""
            ),
            detailLines: [
                "recent_route_events_24h=1",
                "recent_route_failures_24h=1",
                "route_event_1=project=Alpha role=coder path=hub_downgraded_to_local requested=openai/gpt-5.4 actual=qwen3-14b-mlx reason=downgrade_to_local provider=Hub (Local)"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                modelRouteDiagnostics: diagnostics
            )
        )

        let section = report.section(.modelRouteReadiness)
        #expect(section?.state == .ready)
        #expect(section?.headline == "Model route is ready, but recent project routes degraded")
        #expect(section?.detailLines.contains("recent_route_failures_24h=1") == true)
        #expect(section?.detailLines.contains(where: { $0.contains("hub_downgraded_to_local") }) == true)
        #expect(section?.memoryRouteTruthProjection?.projectionSource == "xt_model_route_diagnostics_summary")
        #expect(section?.memoryRouteTruthProjection?.routeResult.routeSource == "hub_downgraded_to_local")
        #expect(section?.memoryRouteTruthProjection?.winningBinding.modelID == "qwen3-14b-mlx")
    }

    @Test
    func writesStructuredMemoryRouteProjectionIntoMachineReadableReport() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXModelRouteDiagnosticsSummary(
            recentEventCount: 1,
            recentFailureCount: 1,
            recentRemoteRetryRecoveryCount: 0,
            latestEvent: AXModelRouteDiagnosticEvent(
                schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
                createdAt: 1_741_300_020,
                projectId: "project-alpha",
                projectDisplayName: "Alpha",
                role: "coder",
                stage: "chat_plan",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "qwen3-14b-mlx",
                runtimeProvider: "Hub (Local)",
                executionPath: "hub_downgraded_to_local",
                fallbackReasonCode: "downgrade_to_local",
                remoteRetryAttempted: false,
                remoteRetryFromModelId: "",
                remoteRetryToModelId: "",
                remoteRetryReasonCode: ""
            ),
            detailLines: [
                "recent_route_events_24h=1",
                "recent_route_failures_24h=1"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                reportPath: reportURL.path,
                modelRouteDiagnostics: diagnostics
            )
        )
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: data)
        let projection = decoded.section(.modelRouteReadiness)?.memoryRouteTruthProjection

        #expect(projection?.projectionSource == "xt_model_route_diagnostics_summary")
        #expect(projection?.routeResult.routeSource == "hub_downgraded_to_local")
        #expect(projection?.routeResult.routeReasonCode == "downgrade_to_local")
        #expect(projection?.winningBinding.provider == "Hub (Local)")
    }

    @Test
    func writesStructuredProjectContextPresentationIntoMachineReadableReport() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=latest_coder_usage",
                "project_context_project=Structured Project",
                "recent_project_dialogue_profile=extended_40_pairs",
                "recent_project_dialogue_selected_pairs=18",
                "recent_project_dialogue_floor_pairs=8",
                "recent_project_dialogue_floor_satisfied=true",
                "recent_project_dialogue_source=xt_cache",
                "recent_project_dialogue_low_signal_dropped=1",
                "project_context_depth=full",
                "effective_project_serving_profile=m4_full_scan",
                "workflow_present=true",
                "execution_evidence_present=true",
                "review_guidance_present=false",
                "cross_link_hints_selected=2"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                reportPath: reportURL.path,
                projectContextDiagnostics: diagnostics
            )
        )
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: data)
        let presentation = decoded.section(.sessionRuntimeReadiness)?.projectContextPresentation

        #expect(presentation?.sourceKind == .latestCoderUsage)
        #expect(presentation?.projectLabel == "Structured Project")
        #expect(presentation?.sourceBadge == "Latest Usage")
        #expect(presentation?.dialogueMetric.contains("40 pairs") == true)
        #expect(presentation?.depthMetric.contains("Full") == true)
        #expect(presentation?.coverageMetric == "wf yes · ev yes · gd no · xlink 2")
    }

    @Test
    func writesStructuredDurableCandidateMirrorProjectionIntoMachineReadableReport() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let model = sampleModel(id: "hub.model.coder")
        let mirrorSnapshot = makeSupervisorMemoryAssemblySnapshot(
            durableCandidateMirrorStatus: .mirroredToHub,
            durableCandidateMirrorTarget: XTSupervisorDurableCandidateMirror.mirrorTarget,
            durableCandidateMirrorAttempted: true,
            durableCandidateMirrorErrorCode: nil,
            durableCandidateLocalStoreRole: XTSupervisorDurableCandidateMirror.localStoreRole
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                reportPath: reportURL.path,
                supervisorMemoryAssemblySnapshot: mirrorSnapshot
            )
        )
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: data)
        let projection = decoded.section(.sessionRuntimeReadiness)?.durableCandidateMirrorProjection

        #expect(projection?.status == .mirroredToHub)
        #expect(projection?.target == XTSupervisorDurableCandidateMirror.mirrorTarget)
        #expect(projection?.attempted == true)
        #expect(projection?.errorCode == nil)
        #expect(projection?.localStoreRole == XTSupervisorDurableCandidateMirror.localStoreRole)
    }

    @Test
    func voicePlaybackSectionSurfacesHubVoicePackFallbackDetails() {
        let model = sampleModel(id: "hub.model.coder")
        var preferences = VoiceRuntimePreferences.default()
        preferences.playbackPreference = .hubVoicePack
        preferences.preferredHubVoicePackID = "hub.voice.zh.warm"

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                voicePreferences: preferences
            )
        )

        let section = report.section(.voicePlaybackReadiness)
        #expect(section?.state == .inProgress)
        #expect(section?.headline == "首选 Hub 语音包暂未就绪")
        #expect(section?.detailLines.contains("requested_playback_source=hub_voice_pack") == true)
        #expect(section?.detailLines.contains("resolved_playback_source=system_speech") == true)
        #expect(section?.detailLines.contains("preferred_voice_pack_id=hub.voice.zh.warm") == true)
        #expect(section?.detailLines.contains("fallback_from=hub_voice_pack") == true)
    }

    @Test
    func doctorIncludesPermissionSpecificWakeAndTalkVoiceSections() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                voiceAuthorizationStatus: .denied,
                voicePermissionSnapshot: VoicePermissionSnapshot(
                    microphone: .authorized,
                    speechRecognition: .denied
                )
            )
        )

        let wakeSection = report.section(.wakeProfileReadiness)
        let talkSection = report.section(.talkLoopReadiness)

        #expect(report.readyForFirstTask == true)
        #expect(report.overallSummary.contains("唤醒配置就绪 仍需修复") == true)
        #expect(report.overallSummary.contains("唤醒配置被语音识别权限阻塞") == true)
        #expect(wakeSection?.state == .permissionDenied)
        #expect(wakeSection?.headline == "唤醒配置被语音识别权限阻塞")
        #expect(wakeSection?.nextStep == "请先在 macOS 系统设置中授予语音识别权限，然后刷新语音运行时。")
        #expect(talkSection?.state == .permissionDenied)
        #expect(talkSection?.headline == "对话链路被语音识别权限阻塞")
        #expect(talkSection?.nextStep == "请先在 macOS 系统设置中授予语音识别权限，然后刷新语音运行时。")
    }
}

private final class XTUnifiedDoctorStoreTestCapture: @unchecked Sendable {
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

private func makeDoctorInput(
    localConnected: Bool,
    remoteConnected: Bool,
    configuredModelIDs: [String],
    models: [HubModel],
    bridgeAlive: Bool,
    bridgeEnabled: Bool,
    bridgeLastError: String = "",
    sessionRuntime: AXSessionRuntimeSnapshot?,
    sessionID: String? = nil,
    skillsSnapshot: AXSkillsDoctorSnapshot,
    voicePreferences: VoiceRuntimePreferences = .default(),
    voiceAuthorizationStatus: VoiceTranscriberAuthorizationStatus = .undetermined,
    voicePermissionSnapshot: VoicePermissionSnapshot = .unknown,
    reportPath: String = "/tmp/xt_unified_doctor_report.json",
    modelRouteDiagnostics: AXModelRouteDiagnosticsSummary = .empty,
    projectContextDiagnostics: AXProjectContextAssemblyDiagnosticsSummary = .empty,
    supervisorMemoryAssemblySnapshot: SupervisorMemoryAssemblySnapshot? = nil
) -> XTUnifiedDoctorInput {
    XTUnifiedDoctorInput(
        generatedAt: Date(timeIntervalSince1970: 1_741_300_000),
        localConnected: localConnected,
        remoteConnected: remoteConnected,
        remoteRoute: .none,
        linking: false,
        pairingPort: 50052,
        grpcPort: 50051,
        internetHost: localConnected ? "10.0.0.8" : "hub.example.test",
        configuredModelIDs: configuredModelIDs,
        totalModelRoles: AXRole.allCases.count,
        failureCode: "",
        runtime: .empty,
        runtimeStatus: AIRuntimeStatus(
            pid: 42,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: true,
            runtimeVersion: "test-runtime",
            importError: nil,
            activeMemoryBytes: nil,
            peakMemoryBytes: nil,
            loadedModelCount: models.filter { $0.state == .loaded }.count
        ),
        modelsState: ModelStateSnapshot(models: models, updatedAt: Date().timeIntervalSince1970),
        bridgeAlive: bridgeAlive,
        bridgeEnabled: bridgeEnabled,
        bridgeLastError: bridgeLastError,
        sessionID: sessionID,
        sessionTitle: sessionID == nil ? nil : "Doctor Session",
        sessionRuntime: sessionRuntime,
        voiceAuthorizationStatus: voiceAuthorizationStatus,
        voicePermissionSnapshot: voicePermissionSnapshot,
        voicePreferences: voicePreferences,
        skillsSnapshot: skillsSnapshot,
        reportPath: reportPath,
        modelRouteDiagnostics: modelRouteDiagnostics,
        projectContextDiagnostics: projectContextDiagnostics,
        supervisorMemoryAssemblySnapshot: supervisorMemoryAssemblySnapshot
    )
}

private func makeSupervisorMemoryAssemblySnapshot(
    durableCandidateMirrorStatus: SupervisorDurableCandidateMirrorStatus = .notNeeded,
    durableCandidateMirrorTarget: String? = nil,
    durableCandidateMirrorAttempted: Bool = false,
    durableCandidateMirrorErrorCode: String? = nil,
    durableCandidateLocalStoreRole: String = XTSupervisorDurableCandidateMirror.localStoreRole
) -> SupervisorMemoryAssemblySnapshot {
    SupervisorMemoryAssemblySnapshot(
        source: "xt_unified_doctor_test",
        resolutionSource: "xt_doctor_projection",
        updatedAt: 1_741_300_000,
        reviewLevelHint: "strategic",
        requestedProfile: "project_ai_default",
        profileFloor: "project_ai_default",
        resolvedProfile: "project_ai_default",
        attemptedProfiles: ["project_ai_default"],
        progressiveUpgradeCount: 0,
        focusedProjectId: "project-alpha",
        selectedSections: ["focused_project_anchor_pack"],
        omittedSections: [],
        contextRefsSelected: 1,
        contextRefsOmitted: 0,
        evidenceItemsSelected: 1,
        evidenceItemsOmitted: 0,
        budgetTotalTokens: 1_024,
        usedTotalTokens: 512,
        truncatedLayers: [],
        freshness: "fresh_local_ipc",
        cacheHit: true,
        denyCode: nil,
        downgradeCode: nil,
        reasonCode: nil,
        compressionPolicy: "progressive_disclosure",
        durableCandidateMirrorStatus: durableCandidateMirrorStatus,
        durableCandidateMirrorTarget: durableCandidateMirrorTarget,
        durableCandidateMirrorAttempted: durableCandidateMirrorAttempted,
        durableCandidateMirrorErrorCode: durableCandidateMirrorErrorCode,
        durableCandidateLocalStoreRole: durableCandidateLocalStoreRole
    )
}

private func sampleModel(id: String) -> HubModel {
    HubModel(
        id: id,
        name: id,
        backend: "mlx",
        quant: "4bit",
        contextLength: 32768,
        paramsB: 7.0,
        roles: ["coder"],
        state: .loaded,
        memoryBytes: 1_024,
        tokensPerSec: 42,
        modelPath: "/models/\(id)",
        note: nil
    )
}

private func readySkillsSnapshot() -> AXSkillsDoctorSnapshot {
    AXSkillsDoctorSnapshot(
        hubIndexAvailable: true,
        installedSkillCount: 0,
        compatibleSkillCount: 0,
        partialCompatibilityCount: 0,
        revokedMatchCount: 0,
        trustEnabledPublisherCount: 1,
        projectIndexEntries: [],
        globalIndexEntries: [],
        conflictWarnings: [],
        installedSkills: [],
        statusKind: .supported,
        statusLine: "skills 0/0",
        compatibilityExplain: "skills compatibility ready"
    )
}

private func defaultBaselineSkills() -> [AXDefaultAgentBaselineSkill] {
    [
        AXDefaultAgentBaselineSkill(skillID: "find-skills", displayName: "Find Skills", summary: ""),
        AXDefaultAgentBaselineSkill(skillID: "agent-browser", displayName: "Agent Browser", summary: ""),
        AXDefaultAgentBaselineSkill(skillID: "self-improving-agent", displayName: "Self Improving Agent", summary: ""),
        AXDefaultAgentBaselineSkill(skillID: "summarize", displayName: "Summarize", summary: ""),
    ]
}

private func defaultBaselineSkillEntries(publisherID: String) -> [AXHubSkillCompatibilityEntry] {
    [
        AXHubSkillCompatibilityEntry(
            skillID: "find-skills",
            name: "Find Skills",
            version: "1.1.0",
            publisherID: publisherID,
            sourceID: "builtin:catalog",
            packageSHA256: "a100000000000000000000000000000000000000000000000000000000000001",
            abiCompatVersion: "skills_abi_compat.v1",
            compatibilityState: .supported,
            canonicalManifestSHA256: "b100000000000000000000000000000000000000000000000000000000000001",
            installHint: "",
            mappingAliasesUsed: [],
            defaultsApplied: [],
            pinnedScopes: ["project"],
            revoked: false
        ),
        AXHubSkillCompatibilityEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            version: "1.0.0",
            publisherID: publisherID,
            sourceID: "builtin:catalog",
            packageSHA256: "a100000000000000000000000000000000000000000000000000000000000002",
            abiCompatVersion: "skills_abi_compat.v1",
            compatibilityState: .supported,
            canonicalManifestSHA256: "b100000000000000000000000000000000000000000000000000000000000002",
            installHint: "",
            mappingAliasesUsed: [],
            defaultsApplied: [],
            pinnedScopes: ["project"],
            revoked: false
        ),
        AXHubSkillCompatibilityEntry(
            skillID: "self-improving-agent",
            name: "Self Improving Agent",
            version: "1.0.0",
            publisherID: publisherID,
            sourceID: "builtin:catalog",
            packageSHA256: "a100000000000000000000000000000000000000000000000000000000000003",
            abiCompatVersion: "skills_abi_compat.v1",
            compatibilityState: .supported,
            canonicalManifestSHA256: "b100000000000000000000000000000000000000000000000000000000000003",
            installHint: "",
            mappingAliasesUsed: [],
            defaultsApplied: [],
            pinnedScopes: ["project"],
            revoked: false
        ),
        AXHubSkillCompatibilityEntry(
            skillID: "summarize",
            name: "Summarize",
            version: "1.1.0",
            publisherID: publisherID,
            sourceID: "builtin:catalog",
            packageSHA256: "a100000000000000000000000000000000000000000000000000000000000004",
            abiCompatVersion: "skills_abi_compat.v1",
            compatibilityState: .supported,
            canonicalManifestSHA256: "b100000000000000000000000000000000000000000000000000000000000004",
            installHint: "",
            mappingAliasesUsed: [],
            defaultsApplied: [],
            pinnedScopes: ["project"],
            revoked: false
        ),
    ]
}

private func defaultBuiltinGovernedSkills() -> [AXBuiltinGovernedSkillSummary] {
    [
        AXBuiltinGovernedSkillSummary(
            skillID: "supervisor-voice",
            displayName: "Supervisor Voice",
            summary: "Inspect, preview, speak, or stop the Supervisor playback path.",
            capabilitiesRequired: ["supervisor.voice.playback"],
            sideEffectClass: "local_side_effect",
            riskLevel: "low",
            policyScope: "xt_builtin"
        )
    ]
}
