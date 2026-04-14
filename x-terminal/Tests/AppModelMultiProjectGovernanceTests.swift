import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct AppModelMultiProjectGovernanceTests {
    @Test
    func projectScopedSettingsWritesDoNotBleedIntoCurrentlySelectedProject() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_project_scoped_settings_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let rootA = workspace.appendingPathComponent("project-a", isDirectory: true)
        let rootB = workspace.appendingPathComponent("project-b", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        let ctxA = AXProjectContext(root: rootA)
        let ctxB = AXProjectContext(root: rootB)

        var configA = try AXProjectStore.loadOrCreateConfig(for: ctxA)
        configA = configA.settingProjectGovernance(
            executionTier: .a1Plan,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .milestoneOnly
        )
        configA = configA.settingHubMemoryPreference(enabled: true)
        try AXProjectStore.saveConfig(configA, for: ctxA)

        var configB = try AXProjectStore.loadOrCreateConfig(for: ctxB)
        configB = configB.settingProjectGovernance(
            executionTier: .a0Observe,
            supervisorInterventionTier: .s0SilentAudit,
            reviewPolicyMode: .milestoneOnly
        )
        configB = configB.settingHubMemoryPreference(enabled: true)
        try AXProjectStore.saveConfig(configB, for: ctxB)

        let appModel = AppModel()
        appModel.projectContext = ctxA
        appModel.projectConfig = configA

        appModel.setProjectGovernance(
            for: ctxB,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s4TightSupervision,
            reviewPolicyMode: .aggressive,
            progressHeartbeatSeconds: 300,
            reviewPulseSeconds: 600,
            brainstormReviewSeconds: 900,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.failureStreak, .preHighRiskAction]
        )
        appModel.setProjectRuntimeSurfacePolicy(
            for: ctxB,
            ttlSeconds: 1800,
            hubOverrideMode: .clampManual
        )
        appModel.setProjectHubMemoryPreference(for: ctxB, enabled: false)
        appModel.setProjectRoleModel(for: ctxB, role: .coder, modelId: "openai/gpt-5.4")

        let reloadedA = try AXProjectStore.loadOrCreateConfig(for: ctxA)
        let reloadedB = try AXProjectStore.loadOrCreateConfig(for: ctxB)

        #expect(appModel.projectContext?.root.standardizedFileURL == ctxA.root.standardizedFileURL)
        #expect(appModel.projectConfig == configA)
        #expect(reloadedA == configA)
        #expect(reloadedA.modelOverride(for: .coder) == nil)

        #expect(reloadedB.executionTier == .a4OpenClaw)
        #expect(reloadedB.supervisorInterventionTier == .s4TightSupervision)
        #expect(reloadedB.reviewPolicyMode == .aggressive)
        #expect(reloadedB.progressHeartbeatSeconds == 300)
        #expect(reloadedB.reviewPulseSeconds == 600)
        #expect(reloadedB.brainstormReviewSeconds == 900)
        #expect(reloadedB.eventDrivenReviewEnabled)
        #expect(reloadedB.eventReviewTriggers == [.failureStreak, .preHighRiskAction])
        #expect(reloadedB.runtimeSurfaceTTLSeconds == 1800)
        #expect(reloadedB.runtimeSurfaceHubOverrideMode == .clampManual)
        #expect(reloadedB.preferHubMemory == false)
        #expect(reloadedB.modelOverride(for: .coder) == "openai/gpt-5.4")
    }

    @Test
    func projectConfigSnapshotForProjectIdDoesNotReuseCurrentProjectCache() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_project_config_snapshot_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let rootA = workspace.appendingPathComponent("project-a", isDirectory: true)
        let rootB = workspace.appendingPathComponent("project-b", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        let ctxA = AXProjectContext(root: rootA)
        let ctxB = AXProjectContext(root: rootB)

        let projectIdA = AXProjectRegistryStore.projectId(forRoot: rootA)
        let projectIdB = AXProjectRegistryStore.projectId(forRoot: rootB)

        let entryA = AXProjectEntry(
            projectId: projectIdA,
            rootPath: rootA.path,
            displayName: "Alpha",
            lastOpenedAt: 1,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        let entryB = AXProjectEntry(
            projectId: projectIdB,
            rootPath: rootB.path,
            displayName: "Beta",
            lastOpenedAt: 2,
            manualOrderIndex: 1,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        var configA = try AXProjectStore.loadOrCreateConfig(for: ctxA)
        configA = configA.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")
        try AXProjectStore.saveConfig(configA, for: ctxA)

        var configB = try AXProjectStore.loadOrCreateConfig(for: ctxB)
        configB = configB.settingModelOverride(role: .coder, modelId: "qwen3-14b-mlx")
        try AXProjectStore.saveConfig(configB, for: ctxB)

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 3,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectIdA,
            projects: [entryA, entryB]
        )
        appModel.selectedProjectId = projectIdA
        appModel.projectContext = ctxA
        appModel.projectConfig = configA

        let currentSnapshot = appModel.projectConfigSnapshot(for: projectIdA)
        let scopedSnapshot = appModel.projectConfigSnapshot(for: projectIdB)

        #expect(currentSnapshot == configA)
        #expect(scopedSnapshot == configB)
        #expect(scopedSnapshot?.modelOverride(for: .coder) == "qwen3-14b-mlx")
        #expect(appModel.projectConfig == configA)
        #expect(appModel.projectContext?.root.standardizedFileURL == ctxA.root.standardizedFileURL)
    }

    @Test
    func doctorProjectSelectionUsesPreferredProjectInsteadOfCurrentProjectCache() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_doctor_project_selection_preferred_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let rootA = workspace.appendingPathComponent("project-a", isDirectory: true)
        let rootB = workspace.appendingPathComponent("project-b", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        let ctxA = AXProjectContext(root: rootA)
        let ctxB = AXProjectContext(root: rootB)
        let projectIdA = AXProjectRegistryStore.projectId(forRoot: rootA)
        let projectIdB = AXProjectRegistryStore.projectId(forRoot: rootB)

        let entryA = AXProjectEntry(
            projectId: projectIdA,
            rootPath: rootA.path,
            displayName: "Alpha",
            lastOpenedAt: 1,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        let entryB = AXProjectEntry(
            projectId: projectIdB,
            rootPath: rootB.path,
            displayName: "Beta",
            lastOpenedAt: 2,
            manualOrderIndex: 1,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        var configA = try AXProjectStore.loadOrCreateConfig(for: ctxA)
        configA = configA.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")
        try AXProjectStore.saveConfig(configA, for: ctxA)

        var configB = try AXProjectStore.loadOrCreateConfig(for: ctxB)
        configB = configB.settingModelOverride(role: .coder, modelId: "qwen3-14b-mlx")
        try AXProjectStore.saveConfig(configB, for: ctxB)

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 3,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectIdA,
            projects: [entryA, entryB]
        )
        appModel.selectedProjectId = projectIdA
        appModel.projectContext = ctxA
        appModel.projectConfig = configA

        let selection = appModel.doctorProjectSelection(preferredProjectId: projectIdB)

        #expect(selection.projectId == projectIdB)
        #expect(selection.projectLabel == "Beta")
        #expect(selection.context?.root.standardizedFileURL == ctxB.root.standardizedFileURL)
        #expect(selection.config == configB)
        #expect(appModel.projectContext?.root.standardizedFileURL == ctxA.root.standardizedFileURL)
        #expect(appModel.projectConfig == configA)
    }

    @Test
    func doctorProjectSelectionFallsBackToSelectedProjectRuleWhenPreferredProjectIsMissing() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_doctor_project_selection_selected_fallback_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let rootA = workspace.appendingPathComponent("project-a", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)

        let ctxA = AXProjectContext(root: rootA)
        let projectIdA = AXProjectRegistryStore.projectId(forRoot: rootA)

        let entryA = AXProjectEntry(
            projectId: projectIdA,
            rootPath: rootA.path,
            displayName: "Alpha",
            lastOpenedAt: 1,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        var configA = try AXProjectStore.loadOrCreateConfig(for: ctxA)
        configA = configA.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")
        try AXProjectStore.saveConfig(configA, for: ctxA)

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 2,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectIdA,
            projects: [entryA]
        )
        appModel.selectedProjectId = projectIdA
        appModel.projectContext = ctxA
        appModel.projectConfig = configA

        let selection = appModel.doctorProjectSelection(preferredProjectId: "missing-project")

        #expect(selection.projectId == projectIdA)
        #expect(selection.projectLabel == "Alpha")
        #expect(selection.context?.root.standardizedFileURL == ctxA.root.standardizedFileURL)
        #expect(selection.config == configA)
    }

    @Test
    func doctorProjectMemoryAdvisoryUsesPreferredProjectSelection() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_doctor_project_memory_advisory_preferred_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let rootA = workspace.appendingPathComponent("project-a", isDirectory: true)
        let rootB = workspace.appendingPathComponent("project-b", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        let ctxA = AXProjectContext(root: rootA)
        let projectIdA = AXProjectRegistryStore.projectId(forRoot: rootA)
        let projectIdB = AXProjectRegistryStore.projectId(forRoot: rootB)

        let entryA = AXProjectEntry(
            projectId: projectIdA,
            rootPath: rootA.path,
            displayName: "Alpha",
            lastOpenedAt: 1,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        let entryB = AXProjectEntry(
            projectId: projectIdB,
            rootPath: rootB.path,
            displayName: "Beta",
            lastOpenedAt: 2,
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
            updatedAt: 3,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectIdA,
            projects: [entryA, entryB]
        )
        appModel.selectedProjectId = projectIdA
        appModel.projectContext = ctxA
        appModel.projectConfig = try AXProjectStore.loadOrCreateConfig(for: ctxA)

        let advisory = appModel.doctorProjectMemoryAdvisory(preferredProjectId: projectIdB)

        #expect(advisory.projectId == projectIdB)
        #expect(advisory.projectLabel == "Beta")
        #expect(advisory.readiness?.ready == false)
        #expect(advisory.readiness?.topIssue?.code == "project_memory_usage_missing")
        #expect(advisory.readiness?.topIssue?.summary.contains("Project AI") == true)
    }

    @Test
    func multiProjectManagerCreateProjectDefaultsToConservativeGovernanceWithoutLegacyOrExplicitTier() async {
        let manager = MultiProjectManager(runtimeHost: SupervisorModel())
        let project = await manager.createProject(
            ProjectConfig(
                name: "Conservative Default",
                taskDescription: "No explicit governance should stay fail-closed.",
                modelName: "claude-sonnet-4.6"
            )
        )

        #expect(project.executionTier == .a0Observe)
        #expect(project.supervisorInterventionTier == .s0SilentAudit)
        #expect(project.reviewPolicyMode == .milestoneOnly)
        #expect(project.progressHeartbeatSeconds == AXProjectExecutionTier.a0Observe.defaultProgressHeartbeatSeconds)
        #expect(project.reviewPulseSeconds == 0)
        #expect(project.brainstormReviewSeconds == 0)
        #expect(project.eventDrivenReviewEnabled == false)
        #expect(project.eventReviewTriggers == [.manualRequest])
        #expect(project.autonomyLevel == .manual)
    }

    @Test
    func multiProjectManagerCreateProjectFollowsExplicitGovernanceInsteadOfLegacyCompatShadow() async {
        let manager = MultiProjectManager(runtimeHost: SupervisorModel())
        let project = await manager.createProject(
            ProjectConfig(
                name: "Governance First",
                taskDescription: "Verify explicit governance wins over the stale legacy compat shadow.",
                modelName: "claude-sonnet-4.6",
                autonomyLevel: .manual,
                executionTier: .a4OpenClaw,
                supervisorInterventionTier: .s4TightSupervision,
                reviewPolicyMode: .aggressive,
                progressHeartbeatSeconds: 300,
                reviewPulseSeconds: 600,
                brainstormReviewSeconds: 900,
                eventDrivenReviewEnabled: true,
                eventReviewTriggers: [.failureStreak, .planDrift, .preDoneSummary]
            )
        )

        #expect(project.executionTier == .a4OpenClaw)
        #expect(project.supervisorInterventionTier == .s4TightSupervision)
        #expect(project.reviewPolicyMode == .aggressive)
        #expect(project.progressHeartbeatSeconds == 300)
        #expect(project.reviewPulseSeconds == 600)
        #expect(project.brainstormReviewSeconds == 900)
        #expect(project.eventDrivenReviewEnabled)
        #expect(project.eventReviewTriggers == [.failureStreak, .planDrift, .preDoneSummary])
        #expect(project.autonomyLevel == .fullAuto)
    }

    @Test
    func appModelCreateMultiProjectPreservesBindingAndGovernanceDials() async throws {
        AppModel.resetSharedMultiProjectRuntimeForTesting()
        defer { AppModel.resetSharedMultiProjectRuntimeForTesting() }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_appmodel_multi_project_governance_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let entry = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Bound Governance Project",
            lastOpenedAt: 1_773_557_400,
            manualOrderIndex: 0,
            pinned: true,
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
            updatedAt: 1_773_557_401,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: entry.projectId,
            projects: [entry]
        )

        let project = try await appModel.createMultiProject(
            name: "Bound Multi Project",
            taskDescription: "Ensure AppModel forwards governance and project binding.",
            modelName: "claude-opus-4.6",
            registeredProjectId: entry.projectId,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s4TightSupervision,
            reviewPolicyMode: .aggressive,
            progressHeartbeatSeconds: 420,
            reviewPulseSeconds: 840,
            brainstormReviewSeconds: 1260,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .preHighRiskAction, .preDoneSummary]
        )

        let binding = try #require(project.registeredProjectBinding)
        #expect(binding.projectId == entry.projectId)
        #expect(binding.rootPath == entry.rootPath)
        #expect(binding.displayName == entry.displayName)
        #expect(project.executionTier == .a3DeliverAuto)
        #expect(project.supervisorInterventionTier == .s4TightSupervision)
        #expect(project.reviewPolicyMode == .aggressive)
        #expect(project.progressHeartbeatSeconds == 420)
        #expect(project.reviewPulseSeconds == 840)
        #expect(project.brainstormReviewSeconds == 1260)
        #expect(project.eventDrivenReviewEnabled)
        #expect(project.eventReviewTriggers == [.blockerDetected, .preHighRiskAction, .preDoneSummary])
        #expect(project.autonomyLevel == .auto)
    }

    @Test
    func appModelCreateMultiProjectMaterializesRegisteredBoundaryWhenRequested() async throws {
        AppModel.resetSharedMultiProjectRuntimeForTesting()
        defer { AppModel.resetSharedMultiProjectRuntimeForTesting() }

        let registryBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_appmodel_materialize_boundary_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: registryBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: registryBase) }

        let envKey = "XTERMINAL_PROJECT_REGISTRY_BASE_DIR"
        let originalEnv = currentEnvironmentValue(envKey)
        setenv(envKey, registryBase.path, 1)
        defer {
            if let originalEnv {
                setenv(envKey, originalEnv, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let appModel = AppModel()
        let project = try await appModel.createMultiProject(
            name: "Voice Supervisor",
            taskDescription: "做一个带语音汇报和授权的 supervisor 控制台",
            modelName: "openai/gpt-5.4",
            materializeRegisteredProjectIfNeeded: true,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .aggressive,
            progressHeartbeatSeconds: 300,
            reviewPulseSeconds: 600,
            brainstormReviewSeconds: 900,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.failureStreak, .planDrift]
        )

        let binding = try #require(project.registeredProjectBinding)
        #expect(appModel.registry.projects.count == 1)
        #expect(binding.displayName == "Voice Supervisor")
        #expect(binding.rootPath.hasPrefix(registryBase.appendingPathComponent("Projects", isDirectory: true).path))

        let ctx = AXProjectContext(root: URL(fileURLWithPath: binding.rootPath, isDirectory: true))
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let memory = try #require(AXProjectStore.loadMemoryIfPresent(for: ctx))

        #expect(config.executionTier == .a4OpenClaw)
        #expect(config.supervisorInterventionTier == .s3StrategicCoach)
        #expect(config.reviewPolicyMode == .aggressive)
        #expect(config.progressHeartbeatSeconds == 300)
        #expect(config.reviewPulseSeconds == 600)
        #expect(config.brainstormReviewSeconds == 900)
        #expect(config.eventDrivenReviewEnabled)
        #expect(config.eventReviewTriggers == [.failureStreak, .planDrift])
        #expect(config.modelOverride(for: .coder) == "openai/gpt-5.4")
        #expect(memory.projectName == "Voice Supervisor")
        #expect(memory.goal == "做一个带语音汇报和授权的 supervisor 控制台")
        #expect(memory.requirements == ["做一个带语音汇报和授权的 supervisor 控制台"])
        #expect(memory.currentState.first == "项目已创建，等待第一轮执行。")
        #expect(memory.nextSteps.first == "确认首轮计划并开始推进。")
    }

    @Test
    func appModelManualRepairRepairsHistoricalProjectBoundaryWithoutTouchingLastOpenedAt() throws {
        AppModel.resetSharedMultiProjectRuntimeForTesting()
        defer { AppModel.resetSharedMultiProjectRuntimeForTesting() }

        let registryBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_appmodel_historical_boundary_repair_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: registryBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: registryBase) }

        let envKey = "XTERMINAL_PROJECT_REGISTRY_BASE_DIR"
        let originalEnv = currentEnvironmentValue(envKey)
        setenv(envKey, registryBase.path, 1)
        defer {
            if let originalEnv {
                setenv(envKey, originalEnv, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let root = registryBase.appendingPathComponent("legacy-project", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let entry = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Legacy Project",
            lastOpenedAt: 1_700_000_123,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        AXProjectRegistryStore.save(
            AXProjectRegistry(
                version: AXProjectRegistry.currentVersion,
                updatedAt: 1_700_000_124,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: true,
                lastSelectedProjectId: nil,
                projects: [entry]
            )
        )

        let appModel = AppModel(
            loadPersistedProjectRegistry: true,
            persistProjectRegistryChanges: false
        )
        appModel.repairHistoricalProjectBoundariesNow(reason: "test_startup_deferred_manual")
        let ctx = AXProjectContext(root: root)
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let memory = try #require(AXProjectStore.loadMemoryIfPresent(for: ctx))
        let repairedEntry = try #require(appModel.registry.project(for: entry.projectId))

        #expect(config.preferHubMemory)
        #expect(memory.projectName == "legacy-project")
        #expect(FileManager.default.fileExists(atPath: ctx.configURL.path))
        #expect(FileManager.default.fileExists(atPath: ctx.memoryJSONURL.path))
        #expect(FileManager.default.fileExists(atPath: ctx.memoryMarkdownURL.path))
        #expect(repairedEntry.lastOpenedAt == entry.lastOpenedAt)
        #expect(appModel.historicalProjectBoundaryRepairStatusLine.contains("historical_project_boundary_repair=repaired"))
        #expect(appModel.historicalProjectBoundaryRepairStatusLine.contains("reason=test_startup_deferred_manual"))
        #expect(appModel.historicalProjectBoundaryRepairStatusLine.contains("repaired_config=1"))
        #expect(appModel.historicalProjectBoundaryRepairStatusLine.contains("repaired_memory=1"))
    }

    @Test
    func appModelRepairHistoricalProjectBoundariesNowRepairsMissingBoundaryAndPublishesManualSummary() throws {
        AppModel.resetSharedMultiProjectRuntimeForTesting()
        defer { AppModel.resetSharedMultiProjectRuntimeForTesting() }

        let registryBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_appmodel_manual_boundary_repair_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: registryBase, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: registryBase) }

        let envKey = "XTERMINAL_PROJECT_REGISTRY_BASE_DIR"
        let originalEnv = currentEnvironmentValue(envKey)
        setenv(envKey, registryBase.path, 1)
        defer {
            if let originalEnv {
                setenv(envKey, originalEnv, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let root = registryBase.appendingPathComponent("manual-repair-project", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.loadOrCreateConfig(for: ctx)
        _ = try AXProjectStore.loadOrCreateMemory(for: ctx)

        let entry = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Manual Repair Project",
            lastOpenedAt: 1_700_100_123,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        AXProjectRegistryStore.save(
            AXProjectRegistry(
                version: AXProjectRegistry.currentVersion,
                updatedAt: 1_700_100_124,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: true,
                lastSelectedProjectId: nil,
                projects: [entry]
            )
        )

        let appModel = AppModel(
            loadPersistedProjectRegistry: true,
            persistProjectRegistryChanges: false
        )

        try FileManager.default.removeItem(at: ctx.configURL)
        try FileManager.default.removeItem(at: ctx.memoryJSONURL)
        try FileManager.default.removeItem(at: ctx.memoryMarkdownURL)

        appModel.repairHistoricalProjectBoundariesNow(reason: "test_manual")

        let repairedEntry = try #require(appModel.registry.project(for: entry.projectId))
        #expect(FileManager.default.fileExists(atPath: ctx.configURL.path))
        #expect(FileManager.default.fileExists(atPath: ctx.memoryJSONURL.path))
        #expect(FileManager.default.fileExists(atPath: ctx.memoryMarkdownURL.path))
        #expect(repairedEntry.lastOpenedAt == entry.lastOpenedAt)
        #expect(appModel.historicalProjectBoundaryRepairStatusLine.contains("historical_project_boundary_repair=repaired"))
        #expect(appModel.historicalProjectBoundaryRepairStatusLine.contains("reason=test_manual"))
        #expect(appModel.historicalProjectBoundaryRepairStatusLine.contains("repaired_config=1"))
        #expect(appModel.historicalProjectBoundaryRepairStatusLine.contains("repaired_memory=1"))
    }

    @Test
    func ensureRegisteredProjectBoundaryInitializesMemoryForImportedRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_appmodel_import_boundary_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        let entry = try #require(
            appModel.ensureRegisteredProjectBoundary(
                at: root,
                preferredDisplayName: "Imported Root",
                initializeMemoryBoundary: true
            )
        )

        let ctx = AXProjectContext(root: root)
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let memory = try #require(AXProjectStore.loadMemoryIfPresent(for: ctx))

        #expect(entry.displayName == "Imported Root")
        #expect(config.preferHubMemory)
        #expect(memory.projectName == root.lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: ctx.memoryJSONURL.path))
        #expect(FileManager.default.fileExists(atPath: ctx.memoryMarkdownURL.path))
    }

    @Test
    func ensureRegisteredProjectBoundaryFailsClosedWhenRootCannotBeMaterialized() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_appmodel_invalid_boundary_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let invalidRoot = workspace.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: invalidRoot)

        let appModel = AppModel()
        let previousRegistry = appModel.registry

        let entry = appModel.ensureRegisteredProjectBoundary(
            at: invalidRoot,
            preferredDisplayName: "Should Fail",
            initializeMemoryBoundary: true
        )

        #expect(entry == nil)
        #expect(appModel.registry == previousRegistry)
    }

    @Test
    func appModelCreateMultiProjectFailsClosedWhenMaterializedBoundaryCannotBeCreated() async throws {
        AppModel.resetSharedMultiProjectRuntimeForTesting()
        defer { AppModel.resetSharedMultiProjectRuntimeForTesting() }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_appmodel_invalid_registry_base_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let invalidBase = workspace.appendingPathComponent("registry-file")
        try Data("file".utf8).write(to: invalidBase)

        let envKey = "XTERMINAL_PROJECT_REGISTRY_BASE_DIR"
        let originalEnv = currentEnvironmentValue(envKey)
        setenv(envKey, invalidBase.path, 1)
        defer {
            if let originalEnv {
                setenv(envKey, originalEnv, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let appModel = AppModel()

        do {
            _ = try await appModel.createMultiProject(
                name: "Should Fail",
                taskDescription: "boundary should fail closed",
                modelName: "openai/gpt-5.4",
                materializeRegisteredProjectIfNeeded: true
            )
            Issue.record("Expected project creation to fail closed when boundary materialization fails.")
        } catch {
            #expect(error as? AppModelProjectCreationError == .failedToMaterializeRegisteredBoundary)
        }

        #expect(appModel.registry.projects.isEmpty)
        #expect(appModel.legacyMultiProjectManager.projects.isEmpty)
    }

    @Test
    func applyProjectGovernanceTemplatePersistsGovernanceTemplateRawLogType() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_appmodel_governance_template_log_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let appModel = AppModel()
        appModel.projectContext = ctx
        appModel.projectConfig = try AXProjectStore.loadOrCreateConfig(for: ctx)

        appModel.applyProjectGovernanceTemplate(.feature)

        let rows = try rawLogEntries(for: ctx)
        let row = try #require(rows.last(where: { ($0["type"] as? String) == "project_governance_template" }))
        #expect(row["legacy_type"] as? String == "project_autonomy_profile")
        #expect(row["template"] as? String == AXProjectGovernanceTemplate.feature.rawValue)
        #expect(row["profile"] as? String == AXProjectGovernanceTemplate.feature.rawValue)
        #expect(row["execution_tier"] as? String == AXProjectExecutionTier.a2RepoAuto.rawValue)
        #expect(row["supervisor_intervention_tier"] as? String == AXProjectSupervisorInterventionTier.s2PeriodicReview.rawValue)
        #expect(row["project_recent_dialogue_profile"] as? String == AXProjectRecentDialogueProfile.standard12Pairs.rawValue)
        #expect(row["project_context_depth_profile"] as? String == AXProjectContextDepthProfile.balanced.rawValue)
    }
}

private func rawLogEntries(for ctx: AXProjectContext) throws -> [[String: Any]] {
    guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path) else { return [] }
    let data = try Data(contentsOf: ctx.rawLogURL)
    let lines = String(decoding: data, as: UTF8.self)
        .split(separator: "\n")
        .map(String.init)

    return try lines.map { line in
        let rowData = try #require(line.data(using: .utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: rowData) as? [String: Any])
        return object
    }
}

private func currentEnvironmentValue(_ key: String) -> String? {
    guard let value = getenv(key) else { return nil }
    return String(cString: value)
}
