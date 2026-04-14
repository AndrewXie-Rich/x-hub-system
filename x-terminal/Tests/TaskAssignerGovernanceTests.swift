import Foundation
import Testing
@testable import XTerminal

@MainActor
struct TaskAssignerGovernanceTests {
    @Test
    func evaluateCapabilityPrefersGovernanceTiersOverMisleadingLegacyCompatShadow() {
        let assigner = TaskAssigner()
        let task = DecomposedTask(
            description: "Ship a risky deploy pipeline change",
            type: .deployment,
            complexity: .complex,
            estimatedEffort: 14_400,
            priority: 9
        )

        let governancePreferred = ProjectModel(
            name: "Governance Preferred",
            taskDescription: "Uses explicit A/S governance",
            modelName: "claude-sonnet-4.6",
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )
        governancePreferred.autonomyLevel = .manual

        let misleadingLegacy = ProjectModel(
            name: "Legacy Misleading",
            taskDescription: "Has an inflated legacy compat shadow",
            modelName: "claude-sonnet-4.6",
            executionTier: .a1Plan,
            supervisorInterventionTier: .s1MilestoneReview
        )
        misleadingLegacy.autonomyLevel = .fullAuto

        let preferredScore = assigner.evaluateCapability(governancePreferred, for: task)
        let misleadingScore = assigner.evaluateCapability(misleadingLegacy, for: task)

        #expect(preferredScore > misleadingScore)
    }

    @Test
    func evaluateCapabilityRewardsStrongerSupervisorTierForHighRiskTasks() {
        let assigner = TaskAssigner()
        let task = DecomposedTask(
            description: "Coordinate production rollout and rollback gate",
            type: .deployment,
            complexity: .veryComplex,
            estimatedEffort: 28_800,
            priority: 10
        )

        let tighterReview = ProjectModel(
            name: "Tighter Review",
            taskDescription: "High-risk delivery project",
            modelName: "claude-sonnet-4.6",
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s4TightSupervision
        )

        let weakerReview = ProjectModel(
            name: "Weaker Review",
            taskDescription: "Same A-Tier, weaker S-Tier review",
            modelName: "claude-sonnet-4.6",
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s1MilestoneReview
        )

        let strongerScore = assigner.evaluateCapability(tighterReview, for: task)
        let weakerScore = assigner.evaluateCapability(weakerReview, for: task)

        #expect(strongerScore > weakerScore)
    }

    @Test
    func evaluateCapabilityUsesConfiguredCoderModelInsteadOfLegacyCurrentModelShadow() throws {
        let assigner = TaskAssigner()
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("task_assigner_route_truth_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let ctx = AXProjectContext(root: rootURL)
        var cfg = AXProjectConfig.default(forProjectRoot: rootURL)
        cfg = cfg.settingModelOverride(role: .coder, modelId: "claude-opus-4.6")
        try AXProjectStore.saveConfig(cfg, for: ctx)

        let task = DecomposedTask(
            description: "Ship a risky deploy pipeline change",
            type: .deployment,
            complexity: .complex,
            estimatedEffort: 14_400,
            priority: 9
        )

        let overrideBacked = ProjectModel(
            name: "Override Backed",
            taskDescription: "Uses explicit coder override",
            modelName: "local-small",
            isLocalModel: true,
            registeredProjectBinding: ProjectRegistryBinding(
                projectId: AXProjectRegistryStore.projectId(forRoot: rootURL),
                rootPath: rootURL.path,
                displayName: "Override Backed"
            ),
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )
        overrideBacked.currentModel = XTModelCatalog.modelInfo(for: "local-small", preferLocalHint: true)

        let staleOnly = ProjectModel(
            name: "Stale Only",
            taskDescription: "No persisted coder override",
            modelName: "local-small",
            isLocalModel: true,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )
        staleOnly.currentModel = XTModelCatalog.modelInfo(for: "local-small", preferLocalHint: true)

        let overrideScore = assigner.evaluateCapability(overrideBacked, for: task)
        let staleScore = assigner.evaluateCapability(staleOnly, for: task)

        #expect(overrideBacked.configuredCoderModelId == "claude-opus-4.6")
        #expect(overrideScore > staleScore)
    }
}
