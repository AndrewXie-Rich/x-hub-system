import Foundation
import Testing
@testable import XTerminal

struct LaneAllocatorRouteTruthTests {

    @MainActor
    @Test
    func configuredCoderModelInfoPreservesCurrentModelMetadataWhenNoOverrideExists() {
        let project = ProjectModel(
            name: "Hub Project",
            taskDescription: "Remote managed work",
            modelName: "placeholder-model"
        )
        project.currentModel = ModelInfo(
            id: "hub-custom-gpt54",
            name: "hub-custom-gpt54",
            displayName: "Hub Custom GPT 5.4",
            type: .hubPaid,
            capability: .expert,
            speed: .medium,
            costPerMillionTokens: 8.0,
            memorySize: nil,
            suitableFor: ["critical", "long_context"],
            badge: nil,
            badgeColor: nil
        )

        #expect(project.configuredCoderModelId == "hub-custom-gpt54")
        #expect(project.configuredCoderModelInfo == project.currentModel)
        #expect(project.configuredCoderModelInfo.capability == .expert)
        #expect(project.configuredCoderModelInfo.suitableFor.contains("long_context"))
    }

    @MainActor
    @Test
    func laneAllocatorUsesConfiguredCoderModelInsteadOfStaleCurrentModel() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lane_allocator_route_truth_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let ctx = AXProjectContext(root: rootURL)
        var cfg = AXProjectConfig.default(forProjectRoot: rootURL)
        cfg = cfg.settingModelOverride(role: .coder, modelId: "claude-opus-4.6")
        try AXProjectStore.saveConfig(cfg, for: ctx)

        let boundProject = ProjectModel(
            name: "Bound Project",
            taskDescription: "Critical rollout work",
            modelName: "local-small",
            isLocalModel: true,
            autonomyLevel: .manual,
            registeredProjectBinding: ProjectRegistryBinding(
                projectId: AXProjectRegistryStore.projectId(forRoot: rootURL),
                rootPath: rootURL.path,
                displayName: "Bound Project"
            ),
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            budget: Budget(daily: 50, monthly: 500)
        )
        boundProject.currentModel = XTModelCatalog.modelInfo(for: "local-small", preferLocalHint: true)

        let competitor = ProjectModel(
            name: "Competitor",
            taskDescription: "Critical rollout work",
            modelName: "claude-sonnet-4.6",
            autonomyLevel: .manual,
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            budget: Budget(daily: 50, monthly: 500)
        )
        competitor.currentModel = XTModelCatalog.modelInfo(for: "claude-sonnet-4.6")

        let laneTask = DecomposedTask(
            description: "Ship the production release safely",
            type: .deployment,
            complexity: .complex,
            estimatedEffort: 7_200,
            priority: 9
        )

        let lanePlan = SupervisorLanePlan(
            laneID: "lane-route-truth",
            goal: laneTask.description,
            dependsOn: [],
            riskTier: .high,
            budgetClass: .premium,
            createChildProject: false,
            expectedArtifacts: ["release_plan"],
            dodChecklist: ["rollback_ready"],
            source: .inferred,
            metadata: [:],
            task: laneTask
        )

        let lane = MaterializedLane(
            plan: lanePlan,
            mode: .softSplit,
            task: laneTask,
            targetProject: nil,
            lineageOperations: [],
            decisionReasons: ["route_truth_test"],
            explain: "route truth lane"
        )

        let allocator = LaneAllocator()
        let result = allocator.allocate(lanes: [lane], projects: [competitor, boundProject])
        let assignment = try #require(result.assignments.first)

        #expect(boundProject.configuredCoderModelId == "claude-opus-4.6")
        #expect(boundProject.configuredCoderModelInfo.capability == .expert)
        #expect(boundProject.currentModel.capability != .expert)
        #expect(assignment.project.id == boundProject.id)
        #expect(assignment.agentProfile.contains("trusted_high"))
    }
}
