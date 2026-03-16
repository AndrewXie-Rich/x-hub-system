import Foundation
import Testing
@testable import XTerminal

@MainActor
struct ProjectModelGovernanceBindingTests {

    @Test
    func governanceContextPrefersResolvedProjectContext() {
        let project = ProjectModel(
            name: "Governed Project",
            taskDescription: "Validate governance binding",
            modelName: "claude-opus-4.6",
            registeredProjectBinding: ProjectRegistryBinding(
                projectId: "project-alpha",
                rootPath: "/tmp/fallback-root",
                displayName: "Alpha"
            )
        )
        let resolvedRoot = URL(fileURLWithPath: "/tmp/resolved-root", isDirectory: true)
        var requestedProjectId: String?

        let ctx = project.governanceActivityContext { projectId in
            requestedProjectId = projectId
            return AXProjectContext(root: resolvedRoot)
        }

        #expect(requestedProjectId == "project-alpha")
        #expect(ctx?.root.standardizedFileURL.path == resolvedRoot.standardizedFileURL.path)
    }

    @Test
    func governanceContextFallsBackToStoredRootPathWhenResolverMisses() {
        let fallbackRoot = URL(
            fileURLWithPath: "/tmp/project-model-governance-binding-fallback",
            isDirectory: true
        )
        let project = ProjectModel(
            name: "Governed Project",
            taskDescription: "Validate governance binding fallback",
            modelName: "claude-opus-4.6",
            registeredProjectBinding: ProjectRegistryBinding(
                projectId: "project-beta",
                rootPath: fallbackRoot.path,
                displayName: "Beta"
            )
        )

        let ctx = project.governanceActivityContext { _ in
            nil
        }

        #expect(ctx?.root.standardizedFileURL.path == fallbackRoot.standardizedFileURL.path)
    }

    @Test
    func explicitExecutionTierKeepsLegacyAutonomyShadowAligned() {
        let project = ProjectModel(
            name: "Aligned Project",
            taskDescription: "Execution tier should drive shadow autonomy",
            modelName: "claude-opus-4.6",
            autonomyLevel: .manual,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s3StrategicCoach
        )

        #expect(project.executionTier == .a4OpenClaw)
        #expect(project.autonomyLevel == .fullAuto)
    }

    @Test
    func governanceContextIsNilForUnboundProjectCard() {
        let project = ProjectModel(
            name: "Unbound Project",
            taskDescription: "No registry binding available",
            modelName: "claude-opus-4.6"
        )

        let ctx = project.governanceActivityContext { _ in
            AXProjectContext(root: URL(fileURLWithPath: "/tmp/should-not-resolve", isDirectory: true))
        }

        #expect(ctx == nil)
        #expect(!project.isBoundToRegisteredProject)
    }

    @Test
    func boundProjectResolvesStoredGovernanceInsteadOfCardDraft() throws {
        let root = try makeProjectRoot(named: "project-model-governance-resolution")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true
        )
        config = config.settingAutonomyPolicy(
            mode: .trustedOpenClawMode,
            ttlSeconds: 600,
            updatedAt: Date()
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let project = ProjectModel(
            name: "Bound Project",
            taskDescription: "Use bound project governance",
            modelName: "claude-opus-4.6",
            registeredProjectBinding: ProjectRegistryBinding(
                projectId: projectId,
                rootPath: root.path,
                displayName: "Bound"
            ),
            executionTier: .a1Plan,
            supervisorInterventionTier: .s1MilestoneReview,
            reviewPolicyMode: .milestoneOnly,
            progressHeartbeatSeconds: 3600,
            reviewPulseSeconds: 0,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: false
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [
                AXProjectEntry(
                    projectId: projectId,
                    rootPath: root.path,
                    displayName: "Bound",
                    lastOpenedAt: Date().timeIntervalSince1970,
                    manualOrderIndex: 0,
                    pinned: false,
                    statusDigest: nil,
                    currentStateSummary: nil,
                    nextStepSummary: nil,
                    blockerSummary: nil,
                    lastSummaryAt: nil,
                    lastEventAt: nil
                )
            ]
        )

        let resolved = try #require(appModel.resolvedProjectGovernance(for: project))
        #expect(resolved.configuredBundle.executionTier == .a4OpenClaw)
        #expect(resolved.configuredBundle.supervisorInterventionTier == .s3StrategicCoach)
        #expect(resolved.configuredBundle.reviewPolicyMode == .hybrid)
        #expect(resolved.effectiveAutonomy.effectiveMode == .trustedOpenClawMode)
    }

    @Test
    func boundProjectUsesLegacyAutonomyLevelWhileStoredConfigStillInCompatMode() throws {
        let root = try makeProjectRoot(named: "project-model-governance-legacy-level")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingAutonomyPolicy(
            mode: .guided,
            ttlSeconds: 600,
            updatedAt: Date()
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let project = ProjectModel(
            name: "Compat Project",
            taskDescription: "Legacy level should still participate in resolver",
            modelName: "claude-opus-4.6",
            autonomyLevel: .fullAuto,
            registeredProjectBinding: ProjectRegistryBinding(
                projectId: projectId,
                rootPath: root.path,
                displayName: "Compat"
            )
        )

        let appModel = AppModel()
        let resolved = try #require(appModel.resolvedProjectGovernance(for: project))

        #expect(resolved.compatSource == .legacyAutonomyLevel)
        #expect(resolved.configuredBundle.executionTier == .a4OpenClaw)
    }

    @Test
    func boundProjectKeepsDefaultConservativeGovernanceInsteadOfProjectCardShadow() throws {
        let root = try makeProjectRoot(named: "project-model-governance-default-conservative")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let config = AXProjectConfig.default(forProjectRoot: root)
        try AXProjectStore.saveConfig(config, for: ctx)

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let project = ProjectModel(
            name: "Default Conservative Project",
            taskDescription: "Stored config should stay fail-closed",
            modelName: "claude-opus-4.6",
            autonomyLevel: .fullAuto,
            registeredProjectBinding: ProjectRegistryBinding(
                projectId: projectId,
                rootPath: root.path,
                displayName: "Default Conservative"
            )
        )

        let appModel = AppModel()
        let resolved = try #require(appModel.resolvedProjectGovernance(for: project))

        #expect(resolved.compatSource == .defaultConservative)
        #expect(resolved.configuredBundle.executionTier == .a0Observe)
        #expect(resolved.configuredBundle.supervisorInterventionTier == .s0SilentAudit)
    }

    @Test
    func boundProjectDoesNotLetLegacyLevelOverrideExplicitDualDialGovernance() throws {
        let root = try makeProjectRoot(named: "project-model-governance-explicit-wins")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a1Plan,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .periodic,
            progressHeartbeatSeconds: 1200,
            reviewPulseSeconds: 3600,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: false
        )
        config = config.settingAutonomyPolicy(
            mode: .guided,
            ttlSeconds: 600,
            updatedAt: Date()
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let project = ProjectModel(
            name: "Explicit Project",
            taskDescription: "Dual dial must stay authoritative",
            modelName: "claude-opus-4.6",
            autonomyLevel: .fullAuto,
            registeredProjectBinding: ProjectRegistryBinding(
                projectId: projectId,
                rootPath: root.path,
                displayName: "Explicit"
            )
        )

        let appModel = AppModel()
        let resolved = try #require(appModel.resolvedProjectGovernance(for: project))

        #expect(resolved.compatSource == .explicitDualDial)
        #expect(resolved.configuredBundle.executionTier == .a1Plan)
        #expect(resolved.configuredBundle.supervisorInterventionTier == .s2PeriodicReview)
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
