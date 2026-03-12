import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorManagerAutomationRuntimeTests {
    private static let gate = TrustedAutomationPermissionTestGate.shared

    actor ToolCallCounter {
        private var counts: [ToolName: Int] = [:]

        func increment(_ tool: ToolName) {
            counts[tool, default: 0] += 1
        }

        func count(for tool: ToolName) -> Int {
            counts[tool, default: 0]
        }
    }

    @Test
    func managerPrepareAdvanceAndRecoverAutomationRunUpdatesPublishedState() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_000))
        )
        #expect(manager.automationPreparedRun?.launchRef == prepared.launchRef)
        #expect(prepared.lineage.rootRunID == prepared.launchRef)
        #expect(prepared.lineage.parentRunID.isEmpty)
        #expect(prepared.lineage.retryDepth == 0)
        #expect(manager.automationCurrentCheckpoint?.state == .queued)
        #expect(manager.automationStatusLine.contains(prepared.launchRef))

        let blocked = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 120,
            auditRef: "audit-xt-auto-manager-blocked",
            now: Date(timeIntervalSince1970: 1_773_200_001)
        )
        #expect(blocked.state == .blocked)
        #expect(manager.automationCurrentCheckpoint?.state == .blocked)

        let recovery = try manager.recoverLatestAutomationRun(
            for: ctx,
            checkpointAgeSeconds: 60,
            auditRef: "audit-xt-auto-manager-recover"
        )
        let recovered = try #require(recovery)
        #expect(recovered.decision == .resume)
        #expect(manager.automationRecoveryDecision?.decision == .resume)
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
        #expect(manager.automationStatusLine.contains("resume"))
    }

    @Test
    func managerCancelAutomationRunMarksSuppressedRecovery() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_100))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 90,
            auditRef: "audit-xt-auto-manager-blocked-2",
            now: Date(timeIntervalSince1970: 1_773_200_101)
        )

        let cancelled = try manager.cancelAutomationRun(
            for: ctx,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-manager-cancel",
            now: Date(timeIntervalSince1970: 1_773_200_102)
        )

        #expect(cancelled.decision == .suppressed)
        #expect(cancelled.holdReason == "manual_cancelled")
        #expect(manager.automationRecoveryDecision?.decision == .suppressed)
        #expect(manager.automationStatusLine.contains("manual_cancelled"))
    }

    @Test
    func managerProjectEntryWrappersResolveContextAndPrepareRun() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let project = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: root.lastPathComponent,
            lastOpenedAt: 1_773_200_200,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let prepared = try manager.prepareAutomationRun(
            for: project,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_200))
        )

        #expect(prepared.currentCheckpoint.state == .queued)
        #expect(manager.automationPreparedRun?.launchRef == prepared.launchRef)
    }

    @Test
    func automationCommandsRouteToManagerRuntimeEntryPoints() async throws {
        try await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetAutomationRuntimeState()
            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                AXTrustedAutomationPermissionOwnerReadiness(
                    schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
                    ownerID: "owner-xt",
                    ownerType: "xterminal_app",
                    bundleID: "com.xterminal.app",
                    installState: "ready",
                    mode: "managed_or_prompted",
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    fullDiskAccess: .missing,
                    inputMonitoring: .missing,
                    canPromptUser: true,
                    managedByMDM: false,
                    overallState: "partial",
                    openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
                    auditRef: "audit-xt-auto-manager-command"
                )
            }

            let root = try makeProjectRoot()
            defer {
                manager.resetAutomationRuntimeState()
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                try? FileManager.default.removeItem(at: root)
            }

            let ctx = AXProjectContext(root: root)
            _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
            try armTrustedAutomation(for: ctx)
            let project = makeProjectEntry(root: root)
            let appModel = AppModel()
            appModel.registry = AXProjectRegistry(
                version: AXProjectRegistry.currentVersion,
                updatedAt: Date().timeIntervalSince1970,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: false,
                lastSelectedProjectId: nil,
                projects: [project]
            )
            manager.setAppModel(appModel)

            let startText = try #require(manager.performAutomationRuntimeCommand("/automation start \(project.projectId)"))
            #expect(startText.contains("run_id:"))
            #expect(manager.automationCurrentCheckpoint?.state == .queued)

            let statusText = try #require(manager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
            #expect(statusText.contains("state: queued"))
            #expect(statusText.contains(project.projectId))
            #expect(statusText.contains("required_device_tool_groups: device.ui.observe,device.ui.act"))

            let advancedText = try #require(manager.performAutomationRuntimeCommand("/automation advance blocked \(project.projectId)"))
            #expect(advancedText.contains("state: blocked"))
            #expect(manager.automationCurrentCheckpoint?.state == .blocked)

            let recoveryText = try #require(manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)"))
            #expect(recoveryText.contains("decision: resume"))
            #expect(manager.automationRecoveryDecision?.decision == .resume)

            let cancelText = try #require(manager.performAutomationRuntimeCommand("/automation cancel \(project.projectId)"))
            #expect(cancelText.contains("manual_cancelled"))
            #expect(manager.automationRecoveryDecision?.decision == .suppressed)
        }
    }

    @Test
    func heartbeatAutoProgressKickstartsPausedReadyProject() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Heartbeat Kickstart",
            lastOpenedAt: 1_773_201_400,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "paused",
            currentStateSummary: "暂停中",
            nextStepSummary: "启动自动项目快照",
            blockerSummary: nil,
            lastSummaryAt: 1_773_201_000,
            lastEventAt: 1_773_201_000
        )
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let actions = manager.runHeartbeatAutoProgressForTesting(
            now: Date(timeIntervalSince1970: 1_773_201_500)
        )
        #expect(actions.count == 1)
        #expect(actions[0].contains("主动启动"))
        #expect(actions[0].contains("Heartbeat Kickstart"))

        try await waitUntil("heartbeat kickstart launch ref persisted") {
            let config = try? AXProjectStore.loadOrCreateConfig(for: ctx)
            let runID = config?.lastAutomationLaunchRef.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !runID.isEmpty
        }
    }

    @Test
    func heartbeatAutoProgressRecoversBlockedAutomationRun() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_201_600))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 30,
            auditRef: "audit-xt-auto-heartbeat-blocked",
            now: Date(timeIntervalSince1970: 1_773_201_601)
        )

        let actions = manager.runHeartbeatAutoProgressForTesting(
            now: Date(timeIntervalSince1970: 1_773_201_700)
        )

        #expect(actions.count == 1)
        #expect(actions[0].contains("主动恢复"))
        #expect(actions[0].contains(project.displayName))
        #expect(manager.automationRecoveryDecision?.decision == .resume)
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
    }

    @Test
    func externalTriggerIngressStartsRunAndFailClosesReplayAndCooldown() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeLiveIngressRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_900,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let first = manager.ingestAutomationExternalTrigger(
            SupervisorManager.SupervisorAutomationExternalTriggerIngress(
                projectId: project.projectId,
                triggerId: "webhook/github_pr",
                triggerType: .webhook,
                source: .github,
                payloadRef: "local://trigger-payload/webhook-001",
                dedupeKey: "sha256:webhook-evt-001",
                receivedAt: Date(timeIntervalSince1970: 1_773_200_900),
                ingressChannel: "test_webhook_bridge"
            )
        )

        #expect(first.decision == .run)
        #expect(first.reasonCode == "trigger_route_allowed")
        #expect(manager.automationCurrentCheckpoint?.state == .queued)
        let firstRunId = try #require(first.runId)
        let routeRowsAfterFirst = try rawLogEntries(for: ctx).filter {
            ($0["type"] as? String) == "automation_external_trigger_route"
        }
        #expect(routeRowsAfterFirst.contains {
            ($0["trigger_id"] as? String) == "webhook/github_pr"
                && ($0["decision"] as? String) == "run"
                && ($0["run_id"] as? String) == firstRunId
        })

        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: firstRunId,
            auditRef: "audit-xt-auto-external-webhook-delivered",
            now: Date(timeIntervalSince1970: 1_773_200_901)
        )

        let cooldown = manager.ingestAutomationExternalTrigger(
            SupervisorManager.SupervisorAutomationExternalTriggerIngress(
                projectId: project.projectId,
                triggerId: "webhook/github_pr",
                triggerType: .webhook,
                source: .github,
                payloadRef: "local://trigger-payload/webhook-002",
                dedupeKey: "sha256:webhook-evt-002",
                receivedAt: Date(timeIntervalSince1970: 1_773_200_910),
                ingressChannel: "test_webhook_bridge"
            )
        )
        #expect(cooldown.decision == .drop)
        #expect(cooldown.reasonCode == "trigger_cooldown_active")

        let replay = manager.ingestAutomationExternalTrigger(
            SupervisorManager.SupervisorAutomationExternalTriggerIngress(
                projectId: project.projectId,
                triggerId: "webhook/github_pr",
                triggerType: .webhook,
                source: .github,
                payloadRef: "local://trigger-payload/webhook-003",
                dedupeKey: "sha256:webhook-evt-001",
                receivedAt: Date(timeIntervalSince1970: 1_773_200_940),
                ingressChannel: "test_webhook_bridge"
            )
        )
        #expect(replay.decision == .drop)
        #expect(replay.reasonCode == "external_trigger_replay_detected")

        let routeRows = try rawLogEntries(for: ctx).filter {
            ($0["type"] as? String) == "automation_external_trigger_route"
        }
        #expect(routeRows.contains {
            ($0["trigger_id"] as? String) == "webhook/github_pr"
                && ($0["decision"] as? String) == "drop"
                && ($0["reason_code"] as? String) == "trigger_cooldown_active"
        })
        #expect(routeRows.contains {
            ($0["trigger_id"] as? String) == "webhook/github_pr"
                && ($0["decision"] as? String) == "drop"
                && ($0["reason_code"] as? String) == "external_trigger_replay_detected"
        })
    }

    @Test
    func scheduleServiceStartsRunOncePerWindowAndReopensOnNextWindow() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeScheduledLiveIngressRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_201_000,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let firstWindowAt = Date(timeIntervalSince1970: 1_773_201_000)
        let firstResults = manager.serviceAutomationScheduleTriggers(now: firstWindowAt)
        #expect(firstResults.count == 1)
        #expect(firstResults.first?.decision == .run)
        #expect(firstResults.first?.triggerId == "schedule/nightly")
        let firstRunId = try #require(firstResults.first?.runId)

        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: firstRunId,
            auditRef: "audit-xt-auto-schedule-delivered-1",
            now: Date(timeIntervalSince1970: 1_773_201_001)
        )

        let sameWindowResults = manager.serviceAutomationScheduleTriggers(
            now: Date(timeIntervalSince1970: 1_773_201_000 + 60 * 60)
        )
        #expect(sameWindowResults.isEmpty)

        let nextWindowResults = manager.serviceAutomationScheduleTriggers(
            now: Date(timeIntervalSince1970: 1_773_201_000 + 24 * 60 * 60 + 5)
        )
        #expect(nextWindowResults.count == 1)
        #expect(nextWindowResults.first?.decision == .run)
        let nextRunId = try #require(nextWindowResults.first?.runId)
        #expect(nextRunId != firstRunId)
    }

    @Test
    func hubConnectorIngressSnapshotFailClosesUnsupportedSourceAndRoutesDeclaredWebhook() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeLiveIngressRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_202_000,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let snapshot = HubIPCClient.ConnectorIngressSnapshot(
            source: "hub_runtime_grpc",
            updatedAtMs: 1_773_202_060_000,
            items: [
                HubIPCClient.ConnectorIngressReceipt(
                    receiptId: "hub-unsupported-001",
                    requestId: "req-hub-unsupported-001",
                    projectId: project.projectId,
                    connector: "discord",
                    targetId: "room-1",
                    ingressType: "connector_event",
                    channelScope: "dm",
                    sourceId: "user-1",
                    messageId: "msg-unsupported-001",
                    dedupeKey: "sha256:hub-unsupported-001",
                    receivedAtMs: 1_773_202_010_000,
                    eventSequence: 17,
                    deliveryState: "accepted",
                    runtimeState: "queued"
                ),
                HubIPCClient.ConnectorIngressReceipt(
                    receiptId: "hub-webhook-001",
                    requestId: "req-hub-webhook-001",
                    projectId: project.projectId,
                    connector: "github",
                    targetId: "repo-1",
                    ingressType: "webhook",
                    channelScope: "repo",
                    sourceId: "pr-42",
                    messageId: "msg-webhook-001",
                    dedupeKey: "sha256:hub-webhook-001",
                    receivedAtMs: 1_773_202_020_000,
                    eventSequence: 18,
                    deliveryState: "accepted",
                    runtimeState: "queued"
                )
            ]
        )

        let firstPass = manager.serviceHubConnectorIngressReceiptsForTesting(
            snapshot,
            now: Date(timeIntervalSince1970: 1_773_202_060)
        )
        #expect(firstPass.count == 2)
        #expect(firstPass.first?.decision == .failClosed)
        #expect(firstPass.first?.reasonCode == "hub_ingress_source_unsupported")
        #expect(firstPass.last?.decision == .run)
        #expect(firstPass.last?.triggerId == "webhook/github_pr")
        let runId = try #require(firstPass.last?.runId)
        #expect(manager.automationCurrentCheckpoint?.state == .queued)

        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: runId,
            auditRef: "audit-xt-auto-hub-connector-delivered",
            now: Date(timeIntervalSince1970: 1_773_202_061)
        )

        let secondPass = manager.serviceHubConnectorIngressReceiptsForTesting(
            snapshot,
            now: Date(timeIntervalSince1970: 1_773_202_090)
        )
        #expect(secondPass.isEmpty)

        let routeRows = try rawLogEntries(for: ctx).filter {
            ($0["type"] as? String) == "automation_external_trigger_route"
        }
        #expect(routeRows.contains {
            ($0["ingress_channel"] as? String) == "hub_connector_receipt_snapshot"
                && ($0["decision"] as? String) == "fail_closed"
                && ($0["reason_code"] as? String) == "hub_ingress_source_unsupported"
        })
        #expect(routeRows.contains {
            ($0["ingress_channel"] as? String) == "hub_connector_receipt_snapshot"
                && ($0["trigger_id"] as? String) == "webhook/github_pr"
                && ($0["decision"] as? String) == "run"
                && ($0["run_id"] as? String) == runId
        })
    }

    @Test
    func automationSelfIterateCommandsUpdateProjectConfigAndSelectedSnapshot() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        appModel.projectContext = ctx
        appModel.projectConfig = try AXProjectStore.loadOrCreateConfig(for: ctx)
        manager.setAppModel(appModel)

        let enableText = try #require(manager.performAutomationRuntimeCommand("/automation self-iterate on \(project.projectId)"))
        #expect(enableText.contains("self_iterate_mode: enabled"))
        #expect(appModel.projectConfig?.automationSelfIterateEnabled == true)

        let maxText = try #require(manager.performAutomationRuntimeCommand("/automation self-iterate max 3 \(project.projectId)"))
        #expect(maxText.contains("self_iterate_max_auto_retry_depth: 3"))
        #expect(appModel.projectConfig?.automationMaxAutoRetryDepth == 3)

        let statusText = try #require(manager.performAutomationRuntimeCommand("/automation self-iterate status \(project.projectId)"))
        #expect(statusText.contains("behavior: bounded_auto_retry_only"))

        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(reloaded.automationSelfIterateEnabled == true)
        #expect(reloaded.automationMaxAutoRetryDepth == 3)

        let disableText = try #require(manager.performAutomationRuntimeCommand("/automation self-iterate off \(project.projectId)"))
        #expect(disableText.contains("self_iterate_mode: disabled"))
        #expect(appModel.projectConfig?.automationSelfIterateEnabled == false)
    }

    @Test
    func automationStartCommandExecutesRecipeActionGraphInBackground() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        try await waitUntil("app model selected project for hydration") {
            appModel.projectContext?.root == root
        }
        manager.setAppModel(appModel)

        let startText = try #require(manager.performAutomationRuntimeCommand("/automation start \(project.projectId)"))
        #expect(startText.contains("run_id:"))

        try await waitUntil("automation action graph delivered") {
            manager.automationCurrentCheckpoint?.state == .delivered
        }

        #expect(manager.automationLatestExecutionReport?.executedActionCount == 1)
        #expect(manager.automationLatestExecutionReport?.finalState == .delivered)
        let statusText = try #require(manager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
        #expect(statusText.contains("last_execution_state: delivered"))
        #expect(statusText.contains("last_execution_actions: 1/1"))
        #expect(statusText.contains("last_execution_handoff: build/reports/xt_automation_run_handoff_"))
    }

    @Test
    func automationStartCommandPublishesVerifyAndDiffStatusForMutationRun() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }
        try markAsSwiftPackage(root)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.verifyCommands = ["swift test --filter SmokeTests"]
        config.verifyAfterChanges = true
        try AXProjectStore.saveConfig(config, for: ctx)

        _ = try AXProjectStore.upsertAutomationRecipe(makeMutationRecipe(), activate: true, for: ctx)
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, _ in
                switch call.tool {
                case .write_file:
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
                case .git_diff:
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: true,
                        output: """
                        diff --git a/README.md b/README.md
                        @@ -0,0 +1 @@
                        +hello
                        """
                    )
                case .run_command:
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "exit: 0\nSmokeTests passed")
                default:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                }
            }
        )

        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let startText = try #require(manager.performAutomationRuntimeCommand("/automation start \(project.projectId)"))
        #expect(startText.contains("run_id:"))

        try await waitUntil("automation mutation run delivered") {
            manager.automationCurrentCheckpoint?.state == .delivered
        }

        let report = try #require(manager.automationLatestExecutionReport)
        #expect(report.finalState == .delivered)
        #expect(report.verificationReport?.passedCommandCount == 1)
        #expect(report.workspaceDiffReport?.fileCount == 1)
        let handoffPath = try #require(report.handoffArtifactPath)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(handoffPath).path))

        let statusText = try #require(manager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
        #expect(statusText.contains("last_execution_handoff: \(handoffPath)"))
        #expect(statusText.contains("last_execution_verify: 1/1"))
        #expect(statusText.contains("last_execution_diff: 1 files"))
        #expect(statusText.contains("last_execution_diff_detail: diff_captured:1_files"))
    }

    @Test
    func automationRecoverSchedulesRetryRunFromVerificationHandoff() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }
        try markAsSwiftPackage(root)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.verifyCommands = ["swift test --filter SmokeTests"]
        config.verifyAfterChanges = true
        try AXProjectStore.saveConfig(config, for: ctx)

        _ = try AXProjectStore.upsertAutomationRecipe(makeMutationRecipe(), activate: true, for: ctx)
        let counter = ToolCallCounter()
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, _ in
                switch call.tool {
                case .write_file:
                    await counter.increment(.write_file)
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
                case .project_snapshot:
                    await counter.increment(.project_snapshot)
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "root=/tmp/project")
                case .git_diff:
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: true,
                        output: """
                        diff --git a/README.md b/README.md
                        @@ -0,0 +1 @@
                        +hello
                        """
                    )
                case .run_command:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "exit: 1\nSmokeTests failed")
                default:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                }
            }
        )

        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        manager.setAppModel(appModel)

        _ = try #require(manager.performAutomationRuntimeCommand("/automation start \(project.projectId)"))

        try await waitUntil("initial verify-failed run blocked") {
            manager.automationCurrentCheckpoint?.state == .blocked
                && manager.automationLatestExecutionReport?.holdReason == "automation_verify_failed"
        }

        let initialReport = try #require(manager.automationLatestExecutionReport)
        let sourceRunID = initialReport.runID
        let sourceHandoff = try #require(initialReport.handoffArtifactPath)
        let sourceLineage = try #require(initialReport.lineage)
        #expect(sourceLineage.rootRunID == sourceRunID)
        #expect(sourceLineage.parentRunID.isEmpty)
        #expect(sourceLineage.retryDepth == 0)

        let recoveryText = try #require(manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)"))
        #expect(recoveryText.contains("decision: resume"))
        #expect(recoveryText.contains("retry_strategy: verify_failed_retry"))
        #expect(recoveryText.contains("retry_attempt_from_run: \(sourceRunID)"))
        #expect(recoveryText.contains("last_retry_source_handoff: \(sourceHandoff)"))

        try await waitUntil("retry run prepared") {
            let retryRunID = manager.automationPreparedRun?.launchRef ?? ""
            return !retryRunID.isEmpty && retryRunID != sourceRunID
        }

        let retryPackage = try #require(manager.automationLatestRetryPackage)
        let retryRunID = try #require(manager.automationPreparedRun?.launchRef)
        let retryLineage = try #require(retryPackage.lineage)
        #expect(retryPackage.sourceRunID == sourceRunID)
        #expect(retryPackage.sourceHandoffArtifactPath == sourceHandoff)
        #expect(retryLineage.lineageID == sourceLineage.lineageID)
        #expect(retryLineage.rootRunID == sourceRunID)
        #expect(retryLineage.parentRunID == sourceRunID)
        #expect(retryLineage.retryDepth == 1)
        #expect(retryPackage.retryStrategy == "verify_failed_retry")
        #expect(retryPackage.planningMode == "verify_only_retry")
        #expect(retryPackage.runtimePatchOverlay != nil)
        #expect(retryPackage.revisedActionGraph?.count == 2)
        #expect(retryPackage.revisedVerifyCommands == ["swift test --filter SmokeTests"])
        #expect(retryPackage.planningArtifactPath?.isEmpty == false)
        #expect(retryPackage.recipeProposalArtifactPath?.isEmpty == false)
        #expect(retryPackage.retryRunID == retryRunID)
        #expect(retryPackage.additionalEvidenceRefs.contains(sourceHandoff))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(retryPackage.retryArtifactPath).path))
        let planningArtifactPath = try #require(retryPackage.planningArtifactPath)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(planningArtifactPath).path))
        let recipeProposalArtifactPath = try #require(retryPackage.recipeProposalArtifactPath)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(recipeProposalArtifactPath).path))

        try await waitUntil("retry verify-failed run blocked") {
            manager.automationCurrentCheckpoint?.runID == retryRunID
                && manager.automationCurrentCheckpoint?.state == .blocked
        }

        let statusText = try #require(manager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
        #expect(statusText.contains("retry_attempt_from_run: \(sourceRunID)"))
        #expect(statusText.contains("retry_strategy: verify_failed_retry"))
        #expect(statusText.contains("retry_planning_mode: verify_only_retry"))
        #expect(statusText.contains("retry_lineage: \(retryLineage.lineageID)"))
        #expect(statusText.contains("retry_depth: 1"))
        #expect(statusText.contains("retry_revised_verify_commands: swift test --filter SmokeTests"))
        #expect(statusText.contains("retry_runtime_patch_overlay_keys: action_graph,verify_commands"))
        #expect(statusText.contains("retry_recipe_proposal_artifact: \(recipeProposalArtifactPath)"))
        #expect(statusText.contains("retry_planning_artifact: \(planningArtifactPath)"))
        #expect(statusText.contains("last_retry_source_handoff: \(sourceHandoff)"))
        #expect(statusText.contains("retry_run_id: \(retryRunID)"))
        #expect(await counter.count(for: .write_file) == 1)
        #expect(await counter.count(for: .project_snapshot) >= 1)
    }

    @Test
    func automationRecoverBuildsPatchCheckRetryPackage() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeGitApplyRecipe(), activate: true, for: ctx)
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, _ in
                switch call.tool {
                case .git_apply_check:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "exit: 1\npatch does not apply")
                default:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                }
            }
        )

        _ = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_700))
        )

        try await waitUntil("initial patch-check-failed run blocked") {
            manager.automationCurrentCheckpoint?.state == .blocked
                && manager.automationLatestExecutionReport?.holdReason == "automation_patch_check_failed"
        }

        let sourceRunID = try #require(manager.automationLatestExecutionReport?.runID)
        let sourceHandoff = try #require(manager.automationLatestExecutionReport?.handoffArtifactPath)

        let recovery = try manager.recoverLatestAutomationRun(
            for: ctx,
            checkpointAgeSeconds: 0,
            auditRef: "audit-xt-auto-manager-patch-recover"
        )
        let recovered = try #require(recovery)
        #expect(recovered.decision == .resume)

        try await waitUntil("patch retry run prepared") {
            let retryRunID = manager.automationPreparedRun?.launchRef ?? ""
            return !retryRunID.isEmpty && retryRunID != sourceRunID
        }

        let retryPackage = try #require(manager.automationLatestRetryPackage)
        #expect(retryPackage.sourceRunID == sourceRunID)
        #expect(retryPackage.sourceHandoffArtifactPath == sourceHandoff)
        #expect(retryPackage.retryStrategy == "patch_check_retry")
        #expect(retryPackage.retryReason == "automation_patch_check_failed")
        #expect(retryPackage.additionalEvidenceRefs.contains("retry://hold_reason/automation_patch_check_failed"))
        #expect(retryPackage.additionalEvidenceRefs.contains(sourceHandoff))
    }

    @Test
    func automationSelfIterateAutoRetriesBlockedRunWithinBudget() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }
        try markAsSwiftPackage(root)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.verifyCommands = ["swift test --filter SmokeTests"]
        config.verifyAfterChanges = true
        config.automationSelfIterateEnabled = true
        config.automationMaxAutoRetryDepth = 1
        try AXProjectStore.saveConfig(config, for: ctx)

        _ = try AXProjectStore.upsertAutomationRecipe(makeMutationRecipe(), activate: true, for: ctx)
        let counter = ToolCallCounter()
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, _ in
                switch call.tool {
                case .write_file:
                    await counter.increment(.write_file)
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
                case .project_snapshot:
                    await counter.increment(.project_snapshot)
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "root=/tmp/project")
                case .git_diff:
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: true,
                        output: """
                        diff --git a/README.md b/README.md
                        @@ -0,0 +1 @@
                        +hello
                        """
                    )
                case .run_command:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "exit: 1\nSmokeTests failed")
                default:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                }
            }
        )

        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let startText = try #require(manager.performAutomationRuntimeCommand("/automation start \(project.projectId)"))
        #expect(startText.contains("run_id:"))

        try await waitUntil("automatic self-iterate retry launch") {
            let retryRunID = manager.automationLatestRetryPackage?.retryRunID ?? ""
            return !retryRunID.isEmpty
                && manager.automationRetryTriggerForTesting() == "automatic"
        }

        let sourceRunID = try #require(manager.automationLatestRetryPackage?.sourceRunID)
        let retryRunID = try #require(manager.automationLatestRetryPackage?.retryRunID)
        let retryLineage = try #require(manager.automationLatestRetryPackage?.lineage)
        #expect(sourceRunID != retryRunID)
        #expect(manager.automationLatestRetryPackage?.retryStrategy == "verify_failed_retry")
        #expect(manager.automationLatestRetryPackage?.planningMode == "verify_only_retry")
        #expect(retryLineage.rootRunID == sourceRunID)
        #expect(retryLineage.parentRunID == sourceRunID)
        #expect(retryLineage.retryDepth == 1)
        #expect(manager.automationLatestRetryPackage?.planningArtifactPath?.isEmpty == false)
        #expect(manager.automationLatestRetryPackage?.recipeProposalArtifactPath?.isEmpty == false)
        #expect(manager.automationLatestRetryPackage?.runtimePatchOverlay != nil)
        #expect(manager.automationLatestRetryPackage?.additionalEvidenceRefs.contains("retry://trigger/automatic") == true)
        #expect(manager.automationLatestRetryPackage?.additionalEvidenceRefs.contains("retry://depth/1") == true)

        try await waitUntil("automatic self-iterate retry finishes blocked") {
            manager.automationCurrentCheckpoint?.runID == retryRunID
                && manager.automationCurrentCheckpoint?.state == .blocked
                && manager.automationLatestExecutionReport?.runID == retryRunID
        }

        try await waitUntil("automatic self-iterate budget exhausts after retry") {
            manager.automationStatusLine.contains("auto_retry_budget_exhausted")
        }

        let statusText = try #require(manager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
        #expect(statusText.contains("self_iterate_mode: enabled"))
        #expect(statusText.contains("self_iterate_max_auto_retry_depth: 1"))
        #expect(statusText.contains("retry_trigger: automatic"))
        #expect(statusText.contains("retry_planning_mode: verify_only_retry"))
        #expect(statusText.contains("retry_runtime_patch_overlay_keys: action_graph,verify_commands"))
        #expect(statusText.contains("retry_recipe_proposal_artifact:"))
        #expect(statusText.contains("retry_planning_artifact:"))
        #expect(statusText.contains("retry_run_id: \(retryRunID)"))
        #expect(await counter.count(for: .write_file) == 1)
        #expect(await counter.count(for: .project_snapshot) >= 1)
    }

    @Test
    func automationStatusHydratesExecutionAndRetryFromDiskAfterRestart() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }
        try markAsSwiftPackage(root)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.verifyCommands = ["swift test --filter SmokeTests"]
        config.verifyAfterChanges = true
        try AXProjectStore.saveConfig(config, for: ctx)

        _ = try AXProjectStore.upsertAutomationRecipe(makeMutationRecipe(), activate: true, for: ctx)
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, _ in
                switch call.tool {
                case .write_file:
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
                case .project_snapshot:
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "root=/tmp/project")
                case .git_diff:
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: true,
                        output: """
                        diff --git a/README.md b/README.md
                        @@ -0,0 +1 @@
                        +hello
                        """
                    )
                case .run_command:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "exit: 1\nSmokeTests failed")
                default:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                }
            }
        )

        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        manager.setAppModel(appModel)

        _ = try #require(manager.performAutomationRuntimeCommand("/automation start \(project.projectId)"))

        try await waitUntil("initial verify-failed run blocked for hydration") {
            manager.automationCurrentCheckpoint?.state == .blocked
                && manager.automationLatestExecutionReport?.holdReason == "automation_verify_failed"
        }

        let sourceRunID = try #require(manager.automationLatestExecutionReport?.runID)
        let sourceHandoff = try #require(manager.automationLatestExecutionReport?.handoffArtifactPath)

        _ = try #require(manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)"))

        try await waitUntil("retry run blocked for hydration") {
            let retryRunID = manager.automationPreparedRun?.launchRef ?? ""
            return !retryRunID.isEmpty
                && retryRunID != sourceRunID
                && manager.automationCurrentCheckpoint?.runID == retryRunID
                && manager.automationCurrentCheckpoint?.state == .blocked
        }

        let retryRunID = try #require(manager.automationPreparedRun?.launchRef)
        let retryReport = try #require(manager.automationLatestExecutionReport)
        let retryHandoff = try #require(retryReport.handoffArtifactPath)
        let retryLineage = try #require(retryReport.lineage)

        let restartedManager = SupervisorManager.makeForTesting()
        restartedManager.resetAutomationRuntimeState()
        restartedManager.setAppModel(appModel)
        restartedManager.syncAutomationRuntimeSnapshot(forSelectedProject: project)

        try await waitUntil("restarted manager hydrates selected project runtime without status command") {
            restartedManager.automationCurrentCheckpoint?.runID == retryRunID
                && restartedManager.automationLatestExecutionReport?.runID == retryRunID
                && restartedManager.automationLatestRetryPackage?.retryRunID == retryRunID
        }

        #expect(restartedManager.automationStatusLine.contains(retryRunID))
        #expect(restartedManager.automationStatusLine.contains("blocked"))

        let statusText = try #require(restartedManager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
        #expect(statusText.contains("last_execution_state: blocked"))
        #expect(statusText.contains("last_execution_handoff: \(retryHandoff)"))
        #expect(statusText.contains("last_execution_verify_hold_reason: automation_verify_failed"))
        #expect(statusText.contains("retry_attempt_from_run: \(sourceRunID)"))
        #expect(statusText.contains("retry_strategy: verify_failed_retry"))
        #expect(statusText.contains("retry_planning_mode: verify_only_retry"))
        #expect(statusText.contains("last_execution_lineage: \(retryLineage.lineageID)"))
        #expect(statusText.contains("last_execution_parent_run: \(sourceRunID)"))
        #expect(statusText.contains("retry_lineage: \(retryLineage.lineageID)"))
        #expect(statusText.contains("retry_runtime_patch_overlay_keys: action_graph,verify_commands"))
        #expect(statusText.contains("retry_recipe_proposal_artifact:"))
        #expect(statusText.contains("retry_planning_artifact:"))
        #expect(statusText.contains("last_retry_source_handoff: \(sourceHandoff)"))
        #expect(statusText.contains("retry_run_id: \(retryRunID)"))

        #expect(restartedManager.automationCurrentCheckpoint?.runID == retryRunID)
        #expect(restartedManager.automationCurrentCheckpoint?.state == .blocked)
        #expect(restartedManager.automationLatestExecutionReport?.runID == retryRunID)
        #expect(restartedManager.automationLatestExecutionReport?.handoffArtifactPath == retryHandoff)
        #expect(restartedManager.automationLatestExecutionReport?.lineage?.parentRunID == sourceRunID)
        #expect(restartedManager.automationLatestExecutionReport?.lineage?.retryDepth == 1)
        #expect(restartedManager.automationLatestRetryPackage?.retryRunID == retryRunID)
        #expect(restartedManager.automationLatestRetryPackage?.sourceRunID == sourceRunID)
        #expect(restartedManager.automationLatestRetryPackage?.lineage?.lineageID == retryLineage.lineageID)
        #expect(restartedManager.automationLatestRetryPackage?.lineage?.retryDepth == 1)
        #expect(restartedManager.automationLatestRetryPackage?.planningMode == "verify_only_retry")
        #expect(restartedManager.automationLatestRetryPackage?.planningArtifactPath?.isEmpty == false)
        #expect(restartedManager.automationLatestRetryPackage?.recipeProposalArtifactPath?.isEmpty == false)
        #expect(restartedManager.automationLatestRetryPackage?.runtimePatchOverlay != nil)
    }

    @Test
    func retryPackageHydratesRecipeProposalArtifactWithoutPlanningArtifact() throws {
        let root = try makeProjectRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        let project = makeProjectEntry(root: root)
        let sourceRunID = "run-source-001"
        let retryRunID = "run-retry-001"
        let lineage = XTAutomationRunLineage(
            lineageID: "lineage-test-001",
            rootRunID: sourceRunID,
            parentRunID: sourceRunID,
            retryDepth: 1
        )
        let proposalArtifact = XTAutomationRecipeProposalArtifact(
            schemaVersion: XTAutomationRecipeProposalArtifact.currentSchemaVersion,
            generatedAt: 1_773_200_850,
            projectID: project.projectId,
            lineage: lineage,
            sourceRunID: sourceRunID,
            sourceHandoffArtifactPath: "build/reports/xt_automation_run_handoff_source.v1.json",
            sourcePlanningArtifactPath: nil,
            baseRecipeRef: "xt-auto-resume-failed-action@v1",
            retryStrategy: "action_failure_retry",
            retryReason: "automation_action_failed",
            proposalMode: "resume_from_failed_action",
            proposalSummary: "resume from the first failed action only",
            runtimePatchOverlay: XTAutomationRuntimePatchOverlay(
                mergePatch: [
                    "action_graph": .array([
                        .object([
                            "action_id": .string("resume_failed_action"),
                            "title": .string("Resume failed action"),
                            "tool": .string(ToolName.run_command.rawValue),
                            "args": .object([
                                "command": .string("false")
                            ]),
                            "continue_on_failure": .bool(false),
                            "success_body_contains": .string(""),
                            "requires_verification": .bool(false)
                        ])
                    ]),
                    "verify_commands": .array([
                        .string("swift test --filter RetryOnly")
                    ])
                ]
            ),
            proposedActionGraph: [],
            proposedVerifyCommands: [],
            suggestedNextActions: ["rerun failed command"],
            additionalEvidenceRefs: ["retry://proposal_mode/resume_from_failed_action"]
        )
        let proposalPath = try #require(
            xtAutomationPersistRetryRecipeProposalArtifact(
                proposalArtifact,
                ctx: ctx
            )
        )

        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": 1_773_200_851,
                "source_run_id": sourceRunID,
                "retry_run_id": retryRunID,
                "lineage_id": lineage.lineageID,
                "root_run_id": lineage.rootRunID,
                "parent_run_id": lineage.parentRunID,
                "retry_depth": lineage.retryDepth,
                "retry_strategy": "action_failure_retry",
                "retry_reason": "automation_action_failed",
                "source_handoff_artifact_path": proposalArtifact.sourceHandoffArtifactPath,
                "recipe_proposal_artifact_path": proposalPath,
                "retry_trigger": "manual"
            ],
            for: ctx
        )

        let loaded = try #require(
            xtAutomationLoadRetryPackage(
                forRetryRunID: retryRunID,
                projectID: project.projectId,
                ctx: ctx
            )
        )
        #expect(loaded.recipeProposalArtifactPath == proposalPath)
        #expect(loaded.planningArtifactPath == nil)
        #expect(loaded.planningMode == "resume_from_failed_action")
        #expect(loaded.planningSummary == "resume from the first failed action only")
        #expect(loaded.runtimePatchOverlay != nil)
        #expect(loaded.revisedActionGraph?.count == 1)
        #expect(loaded.revisedActionGraph?.first?.tool == .run_command)
        #expect(loaded.revisedVerifyCommands == ["swift test --filter RetryOnly"])
        #expect(loaded.lineage?.lineageID == lineage.lineageID)
        #expect(loaded.lineage?.parentRunID == sourceRunID)
        #expect(loaded.lineage?.retryDepth == 1)
    }

    @Test
    func automationRecoverResumesFromFailedActionInsteadOfReplayingSuccessfulPrefix() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeResumeFromFailedActionRecipe(), activate: true, for: ctx)

        let counter = ToolCallCounter()
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, _ in
                switch call.tool {
                case .write_file:
                    await counter.increment(.write_file)
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
                case .run_command:
                    await counter.increment(.run_command)
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "exit: 1\nstep failed")
                default:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                }
            }
        )

        _ = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_800))
        )

        try await waitUntil("initial action-failed run blocked") {
            manager.automationCurrentCheckpoint?.state == .blocked
                && manager.automationLatestExecutionReport?.holdReason == "automation_action_failed"
        }

        let sourceRunID = try #require(manager.automationLatestExecutionReport?.runID)
        let recovery = try manager.recoverLatestAutomationRun(
            for: ctx,
            checkpointAgeSeconds: 0,
            auditRef: "audit-xt-auto-manager-action-recover"
        )
        let recovered = try #require(recovery)
        #expect(recovered.decision == .resume)

        try await waitUntil("resume-from-failed-action retry blocked") {
            let retryRunID = manager.automationPreparedRun?.launchRef ?? ""
            return !retryRunID.isEmpty
                && retryRunID != sourceRunID
                && manager.automationCurrentCheckpoint?.runID == retryRunID
                && manager.automationCurrentCheckpoint?.state == .blocked
        }

        let retryPackage = try #require(manager.automationLatestRetryPackage)
        #expect(retryPackage.retryStrategy == "action_failure_retry")
        #expect(retryPackage.planningMode == "resume_from_failed_action")
        #expect(retryPackage.runtimePatchOverlay != nil)
        #expect(retryPackage.revisedActionGraph?.count == 1)
        #expect(retryPackage.revisedActionGraph?.first?.tool == .run_command)
        #expect(retryPackage.planningArtifactPath?.isEmpty == false)
        #expect(retryPackage.recipeProposalArtifactPath?.isEmpty == false)
        #expect(await counter.count(for: .write_file) == 1)
        #expect(await counter.count(for: .run_command) == 2)
    }

    private func armTrustedAutomation(for ctx: AXProjectContext) throws {
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "device_xt_001",
            deviceToolGroups: ["device.ui.step"],
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
        )
        try AXProjectStore.saveConfig(config, for: ctx)
    }

    private func makeProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-supervisor-manager-automation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeProjectEntry(root: URL) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: root.lastPathComponent,
            lastOpenedAt: 1_773_200_200,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
    }

    private func makeRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-pr-review",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "nightly triage + code review + summary delivery",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:schedule/nightly",
                "xt.automation_trigger_envelope.v1:webhook/github_pr"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l2,
            laneStrategy: .adaptive,
            requiredToolGroups: ["group:full", "group:device_automation"],
            requiredDeviceToolGroups: ["device.ui.step"],
            requiresTrustedAutomation: true,
            trustedDeviceID: "device://trusted/project-a",
            workspaceBindingHash: "sha256:workspace-binding-project-a",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_200_000_000,
            lastEditAuditRef: "audit-xt-auto-manager-bind-001",
            lastLaunchRef: ""
        )
    }

    private func makeAutoExecutableRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-project-snapshot",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "capture project snapshot automatically",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:manual/retry"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            actionGraph: [
                XTAutomationRecipeAction(
                    title: "Project snapshot",
                    tool: .project_snapshot,
                    args: [:],
                    successBodyContains: "root="
                )
            ],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_200_500_000,
            lastEditAuditRef: "audit-xt-auto-manager-bind-002",
            lastLaunchRef: ""
        )
    }

    private func makeMutationRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-mutation-verify",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "write change and verify automatically",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:manual/retry"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            actionGraph: [
                XTAutomationRecipeAction(
                    title: "Write README",
                    tool: .write_file,
                    args: [
                        "path": .string("README.md"),
                        "content": .string("hello")
                    ]
                )
            ],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_200_600_000,
            lastEditAuditRef: "audit-xt-auto-manager-bind-003",
            lastLaunchRef: ""
        )
    }

    private func makeLiveIngressRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-live-ingress",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "ingest webhook and connector events into automation runtime",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:webhook/github_pr",
                "xt.automation_trigger_envelope.v1:connector_event/slack_dm"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_200_900_000,
            lastEditAuditRef: "audit-xt-auto-manager-bind-live-ingress",
            lastLaunchRef: ""
        )
    }

    private func makeScheduledLiveIngressRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-scheduled-live-ingress",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "drive scheduled automation directly from supervisor poll runtime",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:schedule/nightly"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_201_000_000,
            lastEditAuditRef: "audit-xt-auto-manager-bind-scheduled-live-ingress",
            lastLaunchRef: ""
        )
    }

    private func makeGitApplyRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-git-apply-recover",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "apply patch with precheck",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:manual/retry"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            actionGraph: [
                XTAutomationRecipeAction(
                    title: "Apply README patch",
                    tool: .git_apply,
                    args: [
                        "patch": .string("--- a/README.md\n+++ b/README.md\n@@\n-old\n+new\n")
                    ]
                )
            ],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_200_700_000,
            lastEditAuditRef: "audit-xt-auto-manager-bind-004",
            lastLaunchRef: ""
        )
    }

    private func makeResumeFromFailedActionRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-resume-failed-action",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "resume from failed action instead of replaying successful prefix",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:manual/retry"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            actionGraph: [
                XTAutomationRecipeAction(
                    title: "Write README",
                    tool: .write_file,
                    args: [
                        "path": .string("README.md"),
                        "content": .string("hello")
                    ]
                ),
                XTAutomationRecipeAction(
                    title: "Run failing step",
                    tool: .run_command,
                    args: [
                        "command": .string("false"),
                        "timeout_sec": .number(10)
                    ]
                )
            ],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_200_800_000,
            lastEditAuditRef: "audit-xt-auto-manager-bind-005",
            lastLaunchRef: ""
        )
    }

    private func rawLogEntries(for ctx: AXProjectContext) throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path) else { return [] }
        let data = try Data(contentsOf: ctx.rawLogURL)
        guard let text = String(data: data, encoding: .utf8) else {
            struct RawLogDecodeError: Error {}
            throw RawLogDecodeError()
        }
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return nil
            }
            return object
        }
    }

    private func makeRequest(now: Date) -> XTAutomationRunRequest {
        XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "schedule/nightly",
                    triggerType: .schedule,
                    source: .timer,
                    payloadRef: "local://trigger-payload/20260310-101",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: "sha256:schedule-nightly-manager"
                )
            ],
            blockedTaskID: "XT-W3-25-C",
            upstreamDependencyIDs: ["Hub-Wx"],
            now: now
        )
    }

    private func makeManualRequest(now: Date) -> XTAutomationRunRequest {
        XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "manual/retry",
                    triggerType: .manual,
                    source: .hub,
                    payloadRef: "local://trigger-payload/manual-retry",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: "manual|project-a|\(Int(now.timeIntervalSince1970))"
                )
            ],
            blockedTaskID: "XT-W3-25-C",
            upstreamDependencyIDs: ["Hub-Wx"],
            now: now
        )
    }

    private func waitUntil(
        _ label: String,
        timeoutMs: UInt64 = 2_000,
        intervalMs: UInt64 = 50,
        condition: @escaping @MainActor @Sendable () -> Bool
    ) async throws {
        let attempts = max(1, Int(timeoutMs / intervalMs))
        for _ in 0..<attempts {
            if await MainActor.run(body: condition) {
                return
            }
            try await Task.sleep(nanoseconds: intervalMs * 1_000_000)
        }
        Issue.record("Timed out waiting for \(label)")
    }

    private func markAsSwiftPackage(_ root: URL) throws {
        let packageURL = root.appendingPathComponent("Package.swift")
        let package = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "Fixture",
            targets: [
                .target(name: "Fixture")
            ]
        )
        """
        try package.write(to: packageURL, atomically: true, encoding: .utf8)
    }
}
