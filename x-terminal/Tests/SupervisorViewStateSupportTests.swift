import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorViewStateSupportTests {

    @Test
    func selectedAutomationLastLaunchRefFallsBackToPersistedCheckpointTruth() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-supervisor-launch-ref-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(
            AXAutomationRecipeRuntimeBinding(
                recipeID: "recipe-runtime-fallback",
                lifecycleState: .ready,
                goal: "restore checkpoint truth",
                triggerRefs: [],
                deliveryTargets: ["supervisor_digest"],
                acceptancePackRef: "acceptance/runtime-fallback",
                actionGraph: [
                    XTAutomationRecipeAction(
                        title: "Inspect workspace",
                        tool: .read_file
                    )
                ],
                rolloutStatus: .active
            ),
            activate: true,
            for: ctx
        )

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: XTAutomationRunRequest(
                triggerSeeds: [
                    XTAutomationTriggerSeed(
                        triggerID: "manual/supervisor",
                        triggerType: .manual,
                        source: .hub,
                        payloadRef: "local://supervisor/test-launch-ref-fallback",
                        requiresGrant: false,
                        policyRef: "",
                        dedupeKey: "manual|launch-ref-fallback"
                    )
                ],
                now: Date(timeIntervalSince1970: 1_773_205_000)
            )
        )

        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.lastAutomationLaunchRef = ""
        try AXProjectStore.saveConfig(config, for: ctx)

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: "Launch Ref Drift",
            lastOpenedAt: 1_773_205_001,
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
            updatedAt: 1_773_205_002,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        appModel.selectedProjectId = projectId
        appModel.projectContext = ctx
        appModel.projectConfig = config
        manager.setAppModel(appModel)

        let selectedProject = SupervisorViewStateSupport.selectedAutomationProject(appModel: appModel)
        let launchRef = SupervisorViewStateSupport.selectedAutomationLastLaunchRef(
            appModel: appModel,
            supervisor: manager,
            selectedAutomationProject: selectedProject
        )

        #expect(launchRef == prepared.launchRef)
    }

    @Test
    func selectedAutomationLastLaunchRefIgnoresOlderConfigLaunchRefWhenNewerPersistedRunExists() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-supervisor-launch-ref-stale-valid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(
            AXAutomationRecipeRuntimeBinding(
                recipeID: "recipe-runtime-latest-truth",
                lifecycleState: .ready,
                goal: "prefer latest persisted run over stale config",
                triggerRefs: [],
                deliveryTargets: ["supervisor_digest"],
                acceptancePackRef: "acceptance/runtime-latest-truth",
                actionGraph: [
                    XTAutomationRecipeAction(
                        title: "Inspect workspace",
                        tool: .read_file
                    )
                ],
                rolloutStatus: .active
            ),
            activate: true,
            for: ctx
        )

        let delivered = try manager.prepareAutomationRun(
            for: ctx,
            request: XTAutomationRunRequest(
                triggerSeeds: [
                    XTAutomationTriggerSeed(
                        triggerID: "manual/supervisor",
                        triggerType: .manual,
                        source: .hub,
                        payloadRef: "local://supervisor/test-launch-ref-stale-valid-delivered",
                        requiresGrant: false,
                        policyRef: "",
                        dedupeKey: "manual|launch-ref-stale-valid-delivered"
                    )
                ],
                now: Date(timeIntervalSince1970: 1_773_205_010)
            )
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: delivered.launchRef,
            auditRef: "audit-xt-auto-view-launch-ref-delivered",
            now: Date(timeIntervalSince1970: 1_773_205_011)
        )

        let blocked = try manager.prepareAutomationRun(
            for: ctx,
            request: XTAutomationRunRequest(
                triggerSeeds: [
                    XTAutomationTriggerSeed(
                        triggerID: "manual/supervisor",
                        triggerType: .manual,
                        source: .hub,
                        payloadRef: "local://supervisor/test-launch-ref-stale-valid-blocked",
                        requiresGrant: false,
                        policyRef: "",
                        dedupeKey: "manual|launch-ref-stale-valid-blocked"
                    )
                ],
                now: Date(timeIntervalSince1970: 1_773_205_012)
            )
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            runID: blocked.launchRef,
            retryAfterSeconds: 0,
            auditRef: "audit-xt-auto-view-launch-ref-blocked",
            now: Date(timeIntervalSince1970: 1_773_205_013)
        )

        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.lastAutomationLaunchRef = delivered.launchRef
        try AXProjectStore.saveConfig(config, for: ctx)

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: "Launch Ref Stale Valid",
            lastOpenedAt: 1_773_205_014,
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
            updatedAt: 1_773_205_015,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        appModel.selectedProjectId = projectId
        appModel.projectContext = ctx
        appModel.projectConfig = config
        manager.setAppModel(appModel)

        let selectedProject = SupervisorViewStateSupport.selectedAutomationProject(appModel: appModel)
        let launchRef = SupervisorViewStateSupport.selectedAutomationLastLaunchRef(
            appModel: appModel,
            supervisor: manager,
            selectedAutomationProject: selectedProject
        )

        #expect(launchRef == blocked.launchRef)
    }

    @Test
    func refreshedAuditDrillDownSelectionRefreshesRecentSkillActivityDetail() {
        let currentActivity = recentSkillActivity(
            requestId: "req-refresh-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            status: .running,
            resultSummary: "still running",
            updatedAtMs: 2_000
        )
        let updatedActivity = recentSkillActivity(
            requestId: "req-refresh-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            status: .completed,
            resultSummary: "finished successfully",
            updatedAtMs: 9_000
        )
        let oldRecord = fullRecord(
            requestId: "req-refresh-1",
            projectName: "Project Alpha",
            latestStatus: "running",
            latestStatusLabel: "Running"
        )
        let newRecord = fullRecord(
            requestId: "req-refresh-1",
            projectName: "Project Alpha",
            latestStatus: "completed",
            latestStatusLabel: "Completed"
        )

        let currentSelection = SupervisorAuditDrillDownSelection.recentSkillActivity(
            currentActivity,
            fullRecord: oldRecord
        )
        let context = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: "official healthy",
            officialSkillsTransitionLine: "synced",
            officialSkillsDetailLine: "pkg=4 ready=4",
            officialSkillsTopBlockerSummaries: [],
            builtinGovernedSkills: [],
            managedSkillsStatusLine: "skills ok",
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentSupervisorSkillActivities: [updatedActivity],
            recentSupervisorEventLoopActivities: []
        )

        let refreshedSelection = SupervisorViewStateSupport.refreshedAuditDrillDownSelection(
            for: currentSelection.source,
            context: context
        ) { projectId, projectName, requestId in
            #expect(projectId == "project-alpha")
            #expect(projectName == "Project Alpha")
            #expect(requestId == "req-refresh-1")
            return newRecord
        }

        guard let refreshedSelection else {
            Issue.record("Expected refreshed audit drill-down selection")
            return
        }

        #expect(refreshedSelection.fullRecord == newRecord)
        #expect(refreshedSelection.presentation.statusLabel == "已完成")
        #expect(refreshedSelection.presentation.summary == "finished successfully")

        guard case .recentSkillActivity(let refreshedActivity) = refreshedSelection.source else {
            Issue.record("Expected recent skill activity source after refresh")
            return
        }
        #expect(refreshedActivity.status == "completed")
        #expect(refreshedActivity.resultSummary == "finished successfully")
        #expect(refreshedActivity.record.updatedAtMs == 9_000)
    }

    @Test
    func refreshedAuditDrillDownSelectionClearsMissingPendingGrant() {
        let currentSelection = SupervisorAuditDrillDownSelection.pendingHubGrant(
            pendingGrant(
                id: "grant-1",
                grantRequestId: "grant-req-1",
                requestId: "req-1"
            )
        )
        let context = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: "official healthy",
            officialSkillsTransitionLine: "synced",
            officialSkillsDetailLine: "pkg=4 ready=4",
            officialSkillsTopBlockerSummaries: [],
            builtinGovernedSkills: [],
            managedSkillsStatusLine: "skills ok",
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentSupervisorSkillActivities: [],
            recentSupervisorEventLoopActivities: []
        )

        let refreshedSelection = SupervisorViewStateSupport.refreshedAuditDrillDownSelection(
            currentSelection: currentSelection,
            context: context
        ) { _, _, _ in
            nil
        }

        #expect(refreshedSelection == nil)
    }

    @Test
    func refreshedAuditDrillDownSelectionHydratesPendingGrantGovernedContextFromRecentActivity() {
        let grant = pendingGrant(
            id: "grant-1",
            grantRequestId: "grant-req-1",
            requestId: "req-1"
        )
        let currentSelection = SupervisorAuditDrillDownSelection.pendingHubGrant(grant)
        let context = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: "official healthy",
            officialSkillsTransitionLine: "synced",
            officialSkillsDetailLine: "pkg=4 ready=4",
            officialSkillsTopBlockerSummaries: [],
            builtinGovernedSkills: [],
            managedSkillsStatusLine: "skills ok",
            eventLoopStatusLine: "idle",
            pendingHubGrants: [grant],
            pendingSupervisorSkillApprovals: [],
            recentSupervisorSkillActivities: [
                recentHubGrantActivity(
                    requestId: "req-1",
                    grantRequestId: "grant-req-1"
                )
            ],
            recentSupervisorEventLoopActivities: []
        )

        let refreshedSelection = SupervisorViewStateSupport.refreshedAuditDrillDownSelection(
            currentSelection: currentSelection,
            context: context
        ) { _, _, _ in
            nil
        }

        let refreshedPresentation = try? #require(refreshedSelection?.presentation)
        #expect(refreshedPresentation?.detail.contains("能力增量：新增放开：browser_operator") == true)
        #expect(refreshedPresentation?.sections[1].fields.contains(where: {
            $0.label == "执行就绪" && $0.value == "等待 Hub grant"
        }) == true)
    }

    @Test
    func refreshedAuditDrillDownSelectionRefreshesEventLoopDetailAndRelatedRecord() {
        let currentEvent = eventLoopActivity(
            id: "event-1",
            dedupeKey: "grant_resolution:req-loop-1",
            resultSummary: "waiting for resolution",
            updatedAt: 2_000
        )
        let updatedEvent = eventLoopActivity(
            id: "event-1",
            dedupeKey: "grant_resolution:req-loop-1",
            resultSummary: "resolved and continued",
            updatedAt: 9_000
        )
        let relatedSkill = recentSkillActivity(
            requestId: "req-loop-1",
            projectId: "project-beta",
            projectName: "Project Beta",
            status: .completed,
            resultSummary: "continued successfully",
            updatedAtMs: 9_100
        )
        let oldRecord = fullRecord(
            requestId: "req-loop-1",
            projectName: "Project Beta",
            latestStatus: "running",
            latestStatusLabel: "Running"
        )
        let newRecord = fullRecord(
            requestId: "req-loop-1",
            projectName: "Project Beta",
            latestStatus: "completed",
            latestStatusLabel: "Completed"
        )

        let currentSelection = SupervisorAuditDrillDownSelection.eventLoop(
            currentEvent,
            relatedSkillActivity: nil,
            fullRecord: oldRecord
        )
        let context = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: "official healthy",
            officialSkillsTransitionLine: "synced",
            officialSkillsDetailLine: "pkg=4 ready=4",
            officialSkillsTopBlockerSummaries: [],
            builtinGovernedSkills: [],
            managedSkillsStatusLine: "skills ok",
            eventLoopStatusLine: "running",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentSupervisorSkillActivities: [relatedSkill],
            recentSupervisorEventLoopActivities: [updatedEvent]
        )

        let refreshedSelection = SupervisorViewStateSupport.refreshedAuditDrillDownSelection(
            currentSelection: currentSelection,
            context: context
        ) { projectId, projectName, requestId in
            #expect(projectId == "project-beta")
            #expect(projectName == "Project Beta")
            #expect(requestId == "req-loop-1")
            return newRecord
        }

        guard let refreshedSelection else {
            Issue.record("Expected refreshed event-loop audit drill-down selection")
            return
        }

        #expect(refreshedSelection.fullRecord == newRecord)
        #expect(refreshedSelection.presentation.requestId == "req-loop-1")
        #expect(refreshedSelection.presentation.sections.contains(where: { section in
            section.title == "结果" && section.fields.contains(where: { field in
                field.label == "结果摘要" && field.value.contains("resolved and continued")
            })
        }))

        guard case .eventLoop(let refreshedActivity) = refreshedSelection.source else {
            Issue.record("Expected event loop source after refresh")
            return
        }
        #expect(refreshedActivity.resultSummary == "resolved and continued")
        #expect(refreshedActivity.updatedAt == 9_000)
    }

    private func fullRecord(
        requestId: String,
        projectName: String,
        latestStatus: String,
        latestStatusLabel: String
    ) -> SupervisorSkillFullRecord {
        SupervisorSkillFullRecord(
            requestID: requestId,
            projectName: projectName,
            title: "Supervisor skill \(latestStatusLabel.lowercased())",
            latestStatus: latestStatus,
            latestStatusLabel: latestStatusLabel,
            requestMetadata: [],
            approvalFields: [],
            governanceFields: [],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [],
            approvalHistory: [],
            timeline: [],
            supervisorEvidenceJSON: nil
        )
    }

    private func recentSkillActivity(
        requestId: String,
        projectId: String,
        projectName: String,
        status: SupervisorSkillCallStatus,
        resultSummary: String,
        updatedAtMs: Int64
    ) -> SupervisorManager.SupervisorRecentSkillActivity {
        SupervisorManager.SupervisorRecentSkillActivity(
            projectId: projectId,
            projectName: projectName,
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: requestId,
                projectId: projectId,
                jobId: "job-1",
                planId: "plan-1",
                stepId: "step-1",
                skillId: "agent-browser",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: status,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: resultSummary,
                denyCode: "",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: updatedAtMs,
                auditRef: "audit-1"
            ),
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open dashboard",
            actionURL: nil,
            governance: nil
        )
    }

    private func eventLoopActivity(
        id: String,
        dedupeKey: String,
        resultSummary: String,
        updatedAt: Double
    ) -> SupervisorManager.SupervisorEventLoopActivity {
        SupervisorManager.SupervisorEventLoopActivity(
            id: id,
            createdAt: 1_000,
            updatedAt: updatedAt,
            triggerSource: "grant_resolution",
            status: "completed",
            reasonCode: "resolved",
            dedupeKey: dedupeKey,
            projectId: "project-beta",
            projectName: "Project Beta",
            triggerSummary: "grant resolved",
            resultSummary: resultSummary,
            policySummary: "policy ok"
        )
    }

    private func pendingGrant(
        id: String,
        grantRequestId: String,
        requestId: String
    ) -> SupervisorManager.SupervisorPendingGrant {
        SupervisorManager.SupervisorPendingGrant(
            id: id,
            dedupeKey: "grant:\(grantRequestId)",
            grantRequestId: grantRequestId,
            requestId: requestId,
            projectId: "project-alpha",
            projectName: "Project Alpha",
            capability: "browser.control",
            modelId: "gpt-5.4",
            reason: "browser automation requested",
            requestedTtlSec: 600,
            requestedTokenCap: 4000,
            createdAt: 1_000,
            actionURL: nil,
            priorityRank: 1,
            priorityReason: "critical path",
            nextAction: "approve now"
        )
    }

    private func recentHubGrantActivity(
        requestId: String,
        grantRequestId: String
    ) -> SupervisorManager.SupervisorRecentSkillActivity {
        let deltaApproval = XTSkillProfileDeltaApproval(
            schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
            requestId: requestId,
            projectId: "project-alpha",
            projectName: "Project Alpha",
            requestedSkillId: "browser.open",
            effectiveSkillId: "guarded-automation",
            toolName: ToolName.deviceBrowserControl.rawValue,
            currentRunnableProfiles: ["observe_only"],
            requestedProfiles: ["observe_only", "browser_operator"],
            deltaProfiles: ["browser_operator"],
            currentRunnableCapabilityFamilies: ["repo.read"],
            requestedCapabilityFamilies: ["repo.read", "browser.interact"],
            deltaCapabilityFamilies: ["browser.interact"],
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
            requestedTTLSeconds: 600,
            reason: "browser automation requested",
            summary: "当前可直接运行：observe_only；本次请求：observe_only, browser_operator；新增放开：browser_operator",
            disposition: "pending",
            auditRef: "audit-delta-1"
        )
        let readiness = XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: "project-alpha",
            skillId: "guarded-automation",
            packageSHA256: "pkg-1",
            publisherID: "xt_builtin",
            policyScope: "xt_builtin",
            intentFamilies: ["browser.observe", "browser.interact"],
            capabilityFamilies: ["browser.observe", "browser.interact"],
            capabilityProfiles: ["observe_only", "browser_operator"],
            discoverabilityState: "discoverable",
            installabilityState: "installable",
            pinState: "xt_builtin",
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
            auditRef: "audit-readiness-1",
            doctorAuditRef: "",
            vetterAuditRef: "",
            resolvedSnapshotId: "snapshot-1",
            grantSnapshotRef: "grant-1"
        )
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: requestId,
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .awaitingAuthorization,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "grant_required",
            resultEvidenceRef: nil,
            profileDeltaRef: "delta://1",
            deltaApproval: deltaApproval,
            readinessRef: "readiness://1",
            readiness: readiness,
            requiredCapability: "browser.control",
            grantRequestId: grantRequestId,
            grantId: nil,
            hubStateDirPath: "/tmp/hub-state",
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-1"
        )

        return SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open dashboard",
            actionURL: nil,
            governance: nil
        )
    }
}
