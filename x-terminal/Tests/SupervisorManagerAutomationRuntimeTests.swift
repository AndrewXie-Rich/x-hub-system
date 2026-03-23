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

        let root = try makeRegistryVisibleProjectRoot()
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

        let root = try makeRegistryVisibleProjectRoot()
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
    func automationCtxRuntimeSystemMessagesUseFriendlyProjectDisplayName() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Supervisor 耳机项目"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_150,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_150,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        manager.clearMessages()

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_151)),
            emitSystemMessage: true
        )
        _ = try manager.cancelAutomationRun(
            for: ctx,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-friendly-name-cancel",
            now: Date(timeIntervalSince1970: 1_773_200_152),
            emitSystemMessage: true
        )

        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("automation 已准备：\(friendlyName) -> \(prepared.launchRef)") &&
                !$0.content.contains(root.lastPathComponent)
        }))
        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("automation 已取消：\(friendlyName) -> \(prepared.launchRef)") &&
                !$0.content.contains(root.lastPathComponent)
        }))
    }

    @Test
    func automationSafePointSystemMessageUsesFriendlyProjectDisplayName() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "亮亮"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_180,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_180,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        appModel.selectedProjectId = projectId
        manager.setAppModel(appModel)
        manager.clearMessages()

        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-friendly-safe-point-1",
                reviewId: "review-friendly-safe-point-1",
                projectId: projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .checkpointBoundary,
                guidanceText: "先暂停，让 supervisor 再看一遍。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_200_180_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-friendly-safe-point-1"
            ),
            for: ctx
        )

        let prepared = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_181)),
            emitSystemMessage: true
        )

        try await waitUntil("friendly project safe point hold") {
            manager.automationCurrentCheckpoint?.runID == prepared.launchRef &&
            manager.automationCurrentCheckpoint?.state == .blocked
        }

        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("automation 在 safe point 暂停") &&
                $0.content.contains("项目: \(friendlyName)") &&
                !$0.content.contains("项目: \(root.lastPathComponent)")
        }))
    }

    @Test
    func automationAutomaticSelfIterateSystemMessageUsesFriendlyProjectDisplayName() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
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
        try armRepoAutomationGovernance(for: ctx)

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

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "亮亮"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_190,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_190,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        appModel.selectedProjectId = projectId
        manager.setAppModel(appModel)
        manager.clearMessages()

        _ = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_191)),
            emitSystemMessage: true
        )

        try await waitUntil("friendly project automatic self iterate system message", timeoutMs: 10_000) {
            manager.messages.contains(where: {
                $0.role == .system && $0.content.contains("automation 自动迭代已继续")
            })
        }

        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("automation 自动迭代已继续") &&
                $0.content.contains("项目: \(friendlyName)") &&
                !$0.content.contains("项目: \(root.lastPathComponent)")
        }))
    }

    @Test
    func managerProjectEntryWrappersResolveContextAndPrepareRun() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
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

            let root = try makeRegistryVisibleProjectRoot()
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
    @MainActor
    func heartbeatAutoProgressKickstartsPausedReadyProject() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
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
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )

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

        let root = try makeRegistryVisibleProjectRoot()
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

        let root = try makeRegistryVisibleProjectRoot()
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
    func externalTriggerFailureSystemMessageUsesFriendlyProjectDisplayName() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "外出采购项目"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_950,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_950,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        manager.clearMessages()

        let result = manager.ingestAutomationExternalTrigger(
            SupervisorManager.SupervisorAutomationExternalTriggerIngress(
                projectId: projectId,
                triggerId: "webhook/not_allowed",
                triggerType: .webhook,
                source: .github,
                payloadRef: "local://trigger-payload/not-allowed",
                dedupeKey: "sha256:not-allowed-001",
                receivedAt: Date(timeIntervalSince1970: 1_773_200_951),
                ingressChannel: "test_webhook_bridge"
            ),
            emitSystemMessage: true
        )

        #expect(result.decision == .failClosed)
        #expect(result.reasonCode == "trigger_ingress_not_allowed")
        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("automation 外部触发未执行：\(friendlyName) -> webhook/not_allowed (trigger_ingress_not_allowed)") &&
                !$0.content.contains(root.lastPathComponent)
        }))
    }

    @Test
    func scheduleServiceStartsRunOncePerWindowAndReopensOnNextWindow() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
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
    @MainActor
    func hubConnectorIngressSnapshotFailClosesUnsupportedSourceAndRoutesDeclaredWebhook() throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
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
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )
        manager.clearMessages()

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
        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("Discord") &&
                $0.content.contains("失败闭锁")
        }))
        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("GitHub") &&
                $0.content.contains("已转入 XT automation")
        }))
        #expect(spoken.contains(where: {
            $0.contains("Discord") &&
                $0.contains("失败闭锁")
        }))
        #expect(spoken.contains(where: {
            $0.contains("GitHub") &&
                $0.contains("远程入口")
        }))

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
    @MainActor
    func hubConnectorIngressSnapshotHoldsBusyProjectAndAnnouncesBrief() throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
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
            updatedAt: 1_773_202_100,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )
        manager.clearMessages()

        let prepared = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_202_100)),
            emitSystemMessage: false
        )
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
        #expect(manager.automationCurrentCheckpoint?.state == .queued)

        let snapshot = HubIPCClient.ConnectorIngressSnapshot(
            source: "hub_runtime_grpc",
            updatedAtMs: 1_773_202_110_000,
            items: [
                HubIPCClient.ConnectorIngressReceipt(
                    receiptId: "hub-slack-hold-001",
                    requestId: "req-hub-slack-hold-001",
                    projectId: project.projectId,
                    connector: "slack",
                    targetId: "dm-9",
                    ingressType: "connector_event",
                    channelScope: "dm",
                    sourceId: "user-9",
                    messageId: "msg-slack-hold-001",
                    dedupeKey: "sha256:hub-slack-hold-001",
                    receivedAtMs: 1_773_202_105_000,
                    eventSequence: 21,
                    deliveryState: "accepted",
                    runtimeState: "queued"
                )
            ]
        )

        let results = manager.serviceHubConnectorIngressReceiptsForTesting(
            snapshot,
            now: Date(timeIntervalSince1970: 1_773_202_110)
        )
        #expect(results.count == 1)
        #expect(results.first?.decision == .hold)
        #expect(results.first?.reasonCode == "automation_active_run_present")
        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("Slack") &&
                $0.content.contains("暂缓")
        }))
        #expect(spoken.contains(where: {
            $0.contains("Slack") &&
                $0.contains("暂缓")
        }))

        let routeRows = try rawLogEntries(for: ctx).filter {
            ($0["type"] as? String) == "automation_external_trigger_route"
        }
        #expect(routeRows.contains {
            ($0["ingress_channel"] as? String) == "hub_connector_receipt_snapshot"
                && ($0["decision"] as? String) == "hold"
                && ($0["reason_code"] as? String) == "automation_active_run_present"
        })
    }

    @Test
    func operatorChannelXTCommandPrepareDeployPlanUsesPrepareOnlyPathAndPersistsResult() async throws {
        try await Self.gate.run {
            var spoken: [String] = []
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer
            )
            manager.resetAutomationRuntimeState()

            let originalMode = HubAIClient.transportMode()
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_operator_channel_test_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            HubAIClient.setTransportMode(.fileIPC)
            HubPaths.setPinnedBaseDirOverride(hubBase)

            let root = try makeRegistryVisibleProjectRoot()
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubPaths.clearPinnedBaseDirOverride()
                manager.resetAutomationRuntimeState()
                try? FileManager.default.removeItem(at: root)
                try? FileManager.default.removeItem(at: hubBase)
            }

            let ctx = AXProjectContext(root: root)
            _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
            try armTrustedAutomation(for: ctx)
            let project = makeProjectEntry(root: root)
            let appModel = AppModel()
            appModel.registry = AXProjectRegistry(
                version: AXProjectRegistry.currentVersion,
                updatedAt: 1_773_202_300,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: false,
                lastSelectedProjectId: project.projectId,
                projects: [project]
            )
            manager.setAppModel(appModel)
            manager.clearMessages()

            let snapshot = HubIPCClient.OperatorChannelXTCommandSnapshot(
                source: "hub_runtime_grpc",
                updatedAtMs: 1_773_202_301_000,
                items: [
                    HubIPCClient.OperatorChannelXTCommandItem(
                        commandId: "cmd-op-1",
                        requestId: "req-op-1",
                        actionName: "deploy.plan",
                        bindingId: "binding-op-1",
                        routeId: "route-op-1",
                        scopeType: "project",
                        scopeId: project.projectId,
                        projectId: project.projectId,
                        provider: "slack",
                        accountId: "ops-slack",
                        conversationId: "C123",
                        threadKey: "1710000000.0001",
                        actorRef: "xhub.im_identity_binding.v1:slack/U123",
                        resolvedDeviceId: "device_xt_001",
                        preferredDeviceId: "device_xt_001",
                        note: "",
                        createdAtMs: 1_773_202_300_500,
                        auditRef: "audit-op-1"
                    )
                ]
            )

            let results = manager.serviceOperatorChannelXTCommandsForTesting(
                snapshot,
                now: Date(timeIntervalSince1970: 1_773_202_302)
            )
            #expect(results.count == 1)
            let first = try #require(results.first)
            #expect(first.commandId == "cmd-op-1")
            #expect(first.status == "prepared")
            #expect(first.actionName == "deploy.plan")
            #expect(first.projectId == project.projectId)
            let runId = try #require(first.runId.isEmpty ? nil : first.runId)
            #expect(manager.automationPreparedRun?.launchRef == runId)
            #expect(manager.automationCurrentCheckpoint?.state == .queued)

            let stored = await HubIPCClient.requestOperatorChannelXTCommandResults(projectId: project.projectId, limit: 10)
            #expect(stored?.items.first?.commandId == "cmd-op-1")
            #expect(stored?.items.first?.status == "prepared")

            let commandRows = try rawLogEntries(for: ctx).filter {
                ($0["type"] as? String) == "operator_channel_xt_command"
            }
            #expect(commandRows.contains {
                ($0["phase"] as? String) == "prepared"
                    && ($0["command_id"] as? String) == "cmd-op-1"
                    && ($0["run_id"] as? String) == runId
            })
            #expect(manager.messages.contains(where: {
                $0.role == .system &&
                    $0.content.contains("Slack") &&
                    $0.content.contains("已准备执行")
            }))
            #expect(spoken.contains(where: {
                $0.contains("Slack") &&
                    $0.contains("XT 指令")
            }))
        }
    }

    @Test
    func operatorChannelXTCommandFailsClosedWhenProjectBindingDoesNotMatchRoutedDevice() async throws {
        try await Self.gate.run {
            var spoken: [String] = []
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer
            )
            manager.resetAutomationRuntimeState()

            let root = try makeProjectRoot()
            defer {
                manager.resetAutomationRuntimeState()
                try? FileManager.default.removeItem(at: root)
            }

            let ctx = AXProjectContext(root: root)
            _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
            try armTrustedAutomation(for: ctx)
            let project = makeProjectEntry(root: root)
            let appModel = AppModel()
            appModel.registry = AXProjectRegistry(
                version: AXProjectRegistry.currentVersion,
                updatedAt: 1_773_202_400,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: false,
                lastSelectedProjectId: project.projectId,
                projects: [project]
            )
            manager.setAppModel(appModel)
            manager.clearMessages()

            let snapshot = HubIPCClient.OperatorChannelXTCommandSnapshot(
                source: "hub_runtime_grpc",
                updatedAtMs: 1_773_202_401_000,
                items: [
                    HubIPCClient.OperatorChannelXTCommandItem(
                        commandId: "cmd-op-mismatch",
                        requestId: "req-op-mismatch",
                        actionName: "deploy.plan",
                        bindingId: "binding-op-1",
                        routeId: "route-op-1",
                        scopeType: "project",
                        scopeId: project.projectId,
                        projectId: project.projectId,
                        provider: "slack",
                        accountId: "ops-slack",
                        conversationId: "C123",
                        threadKey: "1710000000.0002",
                        actorRef: "xhub.im_identity_binding.v1:slack/U123",
                        resolvedDeviceId: "device_xt_999",
                        preferredDeviceId: "device_xt_999",
                        note: "",
                        createdAtMs: 1_773_202_400_500,
                        auditRef: "audit-op-mismatch"
                    )
                ]
            )

            let first = manager.executeOperatorChannelXTCommandForTesting(
                snapshot.items[0],
                project: project,
                now: Date(timeIntervalSince1970: 1_773_202_402)
            )
            #expect(first.status == "failed")
            #expect(first.denyCode == "trusted_automation_project_not_bound")
            #expect(first.runId.isEmpty)
            #expect(manager.automationPreparedRun == nil)

            let commandRows = try rawLogEntries(for: ctx).filter {
                ($0["type"] as? String) == "operator_channel_xt_command"
            }
            #expect(commandRows.contains {
                ($0["phase"] as? String) == "failed"
                    && ($0["command_id"] as? String) == "cmd-op-mismatch"
                    && ($0["deny_code"] as? String) == "trusted_automation_project_not_bound"
            })
            #expect(manager.messages.contains(where: {
                $0.role == .system &&
                    $0.content.contains("失败闭锁") &&
                    $0.content.contains("trusted_automation_project_not_bound")
            }))
            #expect(spoken.contains(where: {
                $0.contains("Slack") &&
                    $0.contains("失败闭锁")
            }))
        }
    }

    @Test
    func naturalLanguageAutomationStatusAndCancelMapToRuntimeCommands() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

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
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_203_000))
        )
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
        #expect(manager.automationCurrentCheckpoint?.state == .queued)

        let statusText = try #require(
            manager.directSupervisorActionIfApplicableForTesting("亮亮的自动流程现在怎么样")
        )
        #expect(statusText.contains("🤖 Automation Runtime 状态"))
        #expect(statusText.contains("项目: \(project.displayName)"))
        #expect(statusText.contains("last_launch: \(prepared.launchRef)"))

        let cancelText = try #require(
            manager.directSupervisorActionIfApplicableForTesting("先暂停亮亮的自动流程")
        )
        #expect(cancelText.contains("🛑 automation 已取消"))
        #expect(cancelText.contains("run_id: \(prepared.launchRef)"))
    }

    @Test
    func naturalLanguageAutomationCancelPrependsProjectScopedGovernanceBriefForPendingGrant() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

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
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "automation-cancel-grant-1",
                    dedupeKey: "automation-cancel-grant-1",
                    grantRequestId: "automation-cancel-grant-1",
                    requestId: "req-automation-cancel-grant-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
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

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_203_050))
        )
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)

        let cancelText = try #require(
            manager.directSupervisorActionIfApplicableForTesting("先暂停亮亮的自动流程")
        )

        #expect(cancelText.contains("🧭 Supervisor Brief · 亮亮"))
        #expect(cancelText.contains("Hub 待处理授权"))
        #expect(cancelText.contains("查看：查看授权板"))
        #expect(cancelText.contains("🛑 automation 已取消"))
        #expect(cancelText.contains("run_id: \(prepared.launchRef)"))
    }

    @Test
    func automationStatusPrependsProjectScopedGovernanceBriefForPendingGrant() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

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
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "automation-status-grant-1",
                    dedupeKey: "automation-status-grant-1",
                    grantRequestId: "automation-status-grant-1",
                    requestId: "req-automation-status-grant-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
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

        let statusText = try #require(
            manager.performAutomationRuntimeCommand("/automation status \(project.projectId)")
        )

        #expect(statusText.contains("🧭 Supervisor Brief · 亮亮"))
        #expect(statusText.contains("Hub 待处理授权"))
        #expect(statusText.contains("查看：查看授权板"))
        #expect(statusText.contains("🤖 Automation Runtime 状态"))
        #expect(statusText.contains("项目: \(project.displayName)"))
    }

    @Test
    func automationStatusDoesNotLeakGovernanceBriefFromOtherProject() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let rootA = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: rootA)
        }

        let ctxA = AXProjectContext(root: rootA)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctxA)

        var projectA = makeProjectEntry(root: rootA)
        projectA.displayName = "Alpha"
        let projectB = AXProjectEntry(
            projectId: "project-beta-governance-only",
            rootPath: rootA.appendingPathComponent("beta-governance-only").path,
            displayName: "Beta",
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 1,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectA.projectId,
            projects: [projectA, projectB]
        )
        appModel.selectedProjectId = projectA.projectId
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "automation-status-other-project-grant-1",
                    dedupeKey: "automation-status-other-project-grant-1",
                    grantRequestId: "automation-status-other-project-grant-1",
                    requestId: "req-automation-status-other-project-grant-1",
                    projectId: projectB.projectId,
                    projectName: projectB.displayName,
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

        let statusText = try #require(
            manager.performAutomationRuntimeCommand("/automation status \(projectA.projectId)")
        )

        #expect(statusText.contains("🤖 Automation Runtime 状态"))
        #expect(statusText.contains("项目: \(projectA.displayName)"))
        #expect(statusText.contains("🧭 Supervisor Brief") == false)
        #expect(statusText.contains("查看：查看授权板") == false)
    }

    @Test
    func automationRecoverPrependsProjectScopedGovernanceBriefForPendingSkillApproval() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

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
        manager.setAppModel(appModel)
        manager.setPendingSupervisorSkillApprovalsForTesting(
            [
                SupervisorManager.SupervisorPendingSkillApproval(
                    id: "automation-recover-approval-1",
                    requestId: "automation-recover-approval-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    jobId: "job-1",
                    planId: "plan-1",
                    stepId: "step-1",
                    skillId: "agent-browser",
                    toolName: "browser.open",
                    tool: nil,
                    toolSummary: "打开浏览器查看失败后的页面状态",
                    reason: "需要人工确认恢复前的页面操作",
                    createdAt: 1_000,
                    actionURL: nil,
                    routingReasonCode: nil,
                    routingExplanation: nil
                )
            ]
        )

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_203_060))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 120,
            auditRef: "audit-xt-auto-recover-governance-brief",
            now: Date(timeIntervalSince1970: 1_773_203_061)
        )

        let recoveryText = try #require(
            manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)")
        )

        #expect(recoveryText.contains("🧭 Supervisor Brief · 亮亮"))
        #expect(recoveryText.contains("待审批技能"))
        #expect(recoveryText.contains("查看：查看技能审批"))
        #expect(recoveryText.contains("♻️ automation 恢复判定"))
        #expect(recoveryText.contains("run_id: \(prepared.launchRef)"))
        #expect(recoveryText.contains("decision: resume"))
    }

    @Test
    func automationRecoverDoesNotLeakGovernanceBriefFromOtherProject() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let rootA = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: rootA)
        }

        let ctxA = AXProjectContext(root: rootA)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctxA)

        var projectA = makeProjectEntry(root: rootA)
        projectA.displayName = "Alpha"
        let projectB = AXProjectEntry(
            projectId: "project-beta-recover-governance-only",
            rootPath: rootA.appendingPathComponent("beta-recover-governance-only").path,
            displayName: "Beta",
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 1,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectA.projectId,
            projects: [projectA, projectB]
        )
        appModel.selectedProjectId = projectA.projectId
        manager.setAppModel(appModel)
        manager.setPendingSupervisorSkillApprovalsForTesting(
            [
                SupervisorManager.SupervisorPendingSkillApproval(
                    id: "automation-recover-other-project-approval-1",
                    requestId: "automation-recover-other-project-approval-1",
                    projectId: projectB.projectId,
                    projectName: projectB.displayName,
                    jobId: "job-1",
                    planId: "plan-1",
                    stepId: "step-1",
                    skillId: "agent-browser",
                    toolName: "browser.open",
                    tool: nil,
                    toolSummary: "打开浏览器查看失败后的页面状态",
                    reason: "需要人工确认恢复前的页面操作",
                    createdAt: 1_000,
                    actionURL: nil,
                    routingReasonCode: nil,
                    routingExplanation: nil
                )
            ]
        )

        let prepared = try manager.prepareAutomationRun(
            for: ctxA,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_203_060))
        )
        _ = try manager.advanceAutomationRun(
            for: ctxA,
            to: .blocked,
            retryAfterSeconds: 120,
            auditRef: "audit-xt-auto-recover-governance-no-leak",
            now: Date(timeIntervalSince1970: 1_773_203_061)
        )

        let recoveryText = try #require(
            manager.performAutomationRuntimeCommand("/automation recover \(projectA.projectId)")
        )

        #expect(recoveryText.contains("♻️ automation 恢复判定"))
        #expect(recoveryText.contains("run_id: \(prepared.launchRef)"))
        #expect(recoveryText.contains("decision: resume"))
        #expect(recoveryText.contains("🧭 Supervisor Brief") == false)
        #expect(recoveryText.contains("查看：查看技能审批") == false)
    }

    @Test
    func automationStartPrependsProjectScopedGovernanceBriefForPendingGrant() throws {
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
                automation: .granted,
                screenRecording: .missing,
                fullDiskAccess: .missing,
                inputMonitoring: .missing,
                canPromptUser: true,
                managedByMDM: false,
                overallState: "ready",
                openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
                auditRef: "audit-xt-auto-start-governance-brief"
            )
        }

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        try armTrustedAutomation(for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

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
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "automation-start-grant-1",
                    dedupeKey: "automation-start-grant-1",
                    grantRequestId: "automation-start-grant-1",
                    requestId: "req-automation-start-grant-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
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

        let startText = try #require(
            manager.performAutomationRuntimeCommand("/automation start \(project.projectId)")
        )

        #expect(startText.contains("🧭 Supervisor Brief · 亮亮"))
        #expect(startText.contains("Hub 待处理授权"))
        #expect(startText.contains("查看：查看授权板"))
        #expect(startText.contains("✅ automation 已启动准备"))
        #expect(startText.contains("项目: \(project.displayName)"))
    }

    @Test
    func automationStartDoesNotLeakGovernanceBriefFromOtherProject() throws {
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
                automation: .granted,
                screenRecording: .missing,
                fullDiskAccess: .missing,
                inputMonitoring: .missing,
                canPromptUser: true,
                managedByMDM: false,
                overallState: "ready",
                openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
                auditRef: "audit-xt-auto-start-governance-no-leak"
            )
        }

        let rootA = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
            try? FileManager.default.removeItem(at: rootA)
        }

        let ctxA = AXProjectContext(root: rootA)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctxA)
        try armTrustedAutomation(for: ctxA)

        var projectA = makeProjectEntry(root: rootA)
        projectA.displayName = "Alpha"
        let projectB = AXProjectEntry(
            projectId: "project-beta-governance-only",
            rootPath: rootA.appendingPathComponent("beta-governance-only").path,
            displayName: "Beta",
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 1,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectA.projectId,
            projects: [projectA, projectB]
        )
        appModel.selectedProjectId = projectA.projectId
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "automation-start-other-project-grant-1",
                    dedupeKey: "automation-start-other-project-grant-1",
                    grantRequestId: "automation-start-other-project-grant-1",
                    requestId: "req-automation-start-other-project-grant-1",
                    projectId: projectB.projectId,
                    projectName: projectB.displayName,
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

        let startText = try #require(
            manager.performAutomationRuntimeCommand("/automation start \(projectA.projectId)")
        )

        #expect(startText.contains("✅ automation 已启动准备"))
        #expect(startText.contains("项目: \(projectA.displayName)"))
        #expect(startText.contains("🧭 Supervisor Brief") == false)
        #expect(startText.contains("查看：查看授权板") == false)
    }

    @Test
    func automationSelfIterateStatusPrependsProjectScopedGovernanceBriefForPendingSkillApproval() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

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
        manager.setAppModel(appModel)
        manager.setPendingSupervisorSkillApprovalsForTesting(
            [
                SupervisorManager.SupervisorPendingSkillApproval(
                    id: "automation-self-iterate-approval-1",
                    requestId: "automation-self-iterate-approval-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    jobId: "job-1",
                    planId: "plan-1",
                    stepId: "step-1",
                    skillId: "agent-browser",
                    toolName: "browser.open",
                    tool: nil,
                    toolSummary: "打开浏览器查看当前自动化页面状态",
                    reason: "需要人工确认后再继续",
                    createdAt: 1_000,
                    actionURL: nil,
                    routingReasonCode: nil,
                    routingExplanation: nil
                )
            ]
        )

        let statusText = try #require(
            manager.performAutomationRuntimeCommand("/automation self-iterate status \(project.projectId)")
        )

        #expect(statusText.contains("🧭 Supervisor Brief · 亮亮"))
        #expect(statusText.contains("待审批技能"))
        #expect(statusText.contains("查看：查看技能审批"))
        #expect(statusText.contains("🧠 automation self-iterate 状态"))
        #expect(statusText.contains("self_iterate_mode: disabled"))
    }

    @Test
    func automationSelfIterateCommandsUpdateProjectConfigAndSelectedSnapshot() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
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
    func automationStartRunExecutesRecipeActionGraphInBackground() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        try armRepoAutomationGovernance(for: ctx)

        let prepared = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_203_100)),
            emitSystemMessage: false
        )
        #expect(prepared.currentCheckpoint.state == .queued)

        try await waitUntil("automation action graph delivered") {
            manager.automationCurrentCheckpoint?.state == .delivered
        }

        #expect(manager.automationLatestExecutionReport?.executedActionCount == 1)
        #expect(manager.automationLatestExecutionReport?.finalState == .delivered)
        let handoffPath = try #require(manager.automationLatestExecutionReport?.handoffArtifactPath)
        #expect(handoffPath.contains("build/reports/xt_automation_run_handoff_"))
    }

    @Test
    func automationExecutionSystemSummaryPrependsProjectScopedGovernanceBriefForPendingGrant() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        try armRepoAutomationGovernance(for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

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
        manager.setAppModel(appModel)
        manager.clearMessages()
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "automation-execution-grant-1",
                    dedupeKey: "automation-execution-grant-1",
                    grantRequestId: "automation-execution-grant-1",
                    requestId: "req-automation-execution-grant-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
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

        _ = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_203_101)),
            emitSystemMessage: true
        )

        try await waitUntil(
            "automation action graph delivered for execution summary",
            timeoutMs: 10_000
        ) {
            manager.automationLatestExecutionReport?.finalState == .delivered
        }

        #expect(
            manager.messages.contains(where: {
                $0.role == .system &&
                    $0.content.contains("🧭 Supervisor Brief · 亮亮") &&
                    $0.content.contains("Hub 待处理授权") &&
                    $0.content.contains("查看：查看授权板") &&
                    $0.content.contains("⚙️ automation 自动执行完成")
            })
        )
    }

    @Test
    func automationStartSafePointHoldPausesBeforeExecutorAndRunsSupervisorFollowUp() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        manager.resetAutomationRuntimeState()
        actor FollowUpFlag {
            private var hit = false
            func mark() { hit = true }
            func value() -> Bool { hit }
        }
        let followUpFlag = FollowUpFlag()

        let root = try makeRegistryVisibleProjectRoot()
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
        try await waitUntil("app model selected project for safe point hold") {
            appModel.projectContext?.root == root
        }
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )

        let counter = ToolCallCounter()
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, rootURL in
                await counter.increment(call.tool)
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "root=\(rootURL.path)")
            }
        )
        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            await followUpFlag.mark()
            #expect(triggerSource == "automation_safe_point")
            #expect(userMessage.contains("trigger=automation_safe_point"))
            #expect(userMessage.contains("requested_state=running"))
            #expect(userMessage.contains("injection_id=guidance-auto-safe-point-start-1"))
            return """
            1. 先确认为什么要在当前 safe point 暂停。
            2. 对照 guidance 判断是否需要重排 action graph。
            3. 给 coder 一个可执行的下一步。
            """
        }

        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-auto-safe-point-start-1",
                reviewId: "review-auto-safe-point-start-1",
                projectId: project.projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .checkpointBoundary,
                guidanceText: "执行 action graph 前先停下，让 supervisor 重审方案。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_200_700_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-auto-safe-point-start-1"
            ),
            for: ctx
        )

        let prepared = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_701)),
            emitSystemMessage: false
        )

        try await waitUntil("automation safe point hold before execution") {
            manager.automationCurrentCheckpoint?.runID == prepared.launchRef &&
            manager.automationCurrentCheckpoint?.state == .blocked
        }
        await manager.waitForSupervisorEventLoopForTesting()

        #expect(await counter.count(for: .project_snapshot) == 0)
        #expect(await followUpFlag.value())
        #expect(manager.automationLatestExecutionReport == nil)

        let rows = try rawLogEntries(for: ctx)
        #expect(rows.contains {
            ($0["type"] as? String) == "automation_safe_point_hold" &&
            ($0["run_id"] as? String) == prepared.launchRef &&
            ($0["requested_state"] as? String) == XTAutomationRunState.running.rawValue &&
            ($0["injection_id"] as? String) == "guidance-auto-safe-point-start-1"
        })
        #expect(rows.contains {
            ($0["type"] as? String) == "automation_execution" &&
            ($0["phase"] as? String) == "started" &&
            ($0["run_id"] as? String) == prepared.launchRef
        } == false)
        #expect(manager.messages.contains {
            $0.role == .assistant && $0.content.contains("先确认为什么要在当前 safe point 暂停")
        })
    }

    @Test
    func automationSafePointHoldAfterExecutionRunsSupervisorFollowUp() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        manager.resetAutomationRuntimeState()
        actor FollowUpFlag {
            private var hit = false
            func mark() { hit = true }
            func value() -> Bool { hit }
        }
        let followUpFlag = FollowUpFlag()

        let root = try makeRegistryVisibleProjectRoot()
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
        try await waitUntil("app model selected project for post execution hold") {
            appModel.projectContext?.root == root
        }
        manager.setAppModel(appModel)

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            await followUpFlag.mark()
            #expect(triggerSource == "automation_safe_point")
            #expect(userMessage.contains("requested_state=delivered"))
            #expect(userMessage.contains("injection_id=guidance-auto-safe-point-finish-1"))
            return """
            1. 先审查这次 automation 产物是否已经满足 done definition。
            2. 如果 guidance 要求延后交付，就重新决定下一步是复核、replan 还是放行。
            3. 输出给 coder 的具体执行建议。
            """
        }

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_800))
        )
        let running = try manager.advanceAutomationRun(
            for: ctx,
            to: .running,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-running-before-post-safe-point",
            now: Date(timeIntervalSince1970: 1_773_200_801),
            emitSystemMessage: false
        )
        #expect(running.state == .running)

        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-auto-safe-point-finish-1",
                reviewId: "review-auto-safe-point-finish-1",
                projectId: project.projectId,
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                interventionMode: .suggestNextSafePoint,
                safePointPolicy: .checkpointBoundary,
                guidanceText: "动作跑完了，但先别交付，给 supervisor 一次 review 窗口。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_200_800_500,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-auto-safe-point-finish-1"
            ),
            for: ctx
        )

        let finalCheckpoint = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-post-safe-point-delivered",
            now: Date(timeIntervalSince1970: 1_773_200_802),
            emitSystemMessage: false
        )
        #expect(finalCheckpoint.state == .blocked)
        await manager.waitForSupervisorEventLoopForTesting()

        #expect(await followUpFlag.value())

        let rows = try rawLogEntries(for: ctx)
        #expect(rows.contains {
            ($0["type"] as? String) == "automation_safe_point_hold" &&
            ($0["run_id"] as? String) == prepared.launchRef &&
            ($0["requested_state"] as? String) == XTAutomationRunState.delivered.rawValue &&
            ($0["injection_id"] as? String) == "guidance-auto-safe-point-finish-1"
        })
        #expect(manager.messages.contains {
            $0.role == .assistant && $0.content.contains("先审查这次 automation 产物是否已经满足 done definition")
        })
    }

    @Test
    func automationStartCommandPublishesVerifyAndDiffStatusForMutationRun() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
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
        try armRepoAutomationGovernance(for: ctx)

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

        let root = try makeRegistryVisibleProjectRoot()
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
        try armRepoAutomationGovernance(for: ctx)

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
        try armRepoAutomationGovernance(for: ctx)
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

        let root = try makeRegistryVisibleProjectRoot()
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
        try armRepoAutomationGovernance(for: ctx)

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

        let root = try makeRegistryVisibleProjectRoot()
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
        try armRepoAutomationGovernance(for: ctx)

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
        #expect(restartedManager.automationStatusLine.contains("受阻"))

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
        try armRepoAutomationGovernance(for: ctx)
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

    private func armRepoAutomationGovernance(for ctx: AXProjectContext) throws {
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)
    }

    private func makeProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-supervisor-manager-automation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeRegistryVisibleProjectRoot() throws -> URL {
        // Keep a non-ephemeral prefix so registry-backed selection paths can still see the test project.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-operator-channel-runtime-\(UUID().uuidString)", isDirectory: true)
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
