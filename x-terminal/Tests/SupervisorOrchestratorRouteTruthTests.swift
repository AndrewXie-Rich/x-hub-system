import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorOrchestratorRouteTruthTests {

    @Test
    func executeProjectUsesConfiguredCoderRouteEvenWhenCurrentModelShadowIsStale() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_orchestrator_route_truth_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let ctx = AXProjectContext(root: rootURL)
        var cfg = AXProjectConfig.default(forProjectRoot: rootURL)
        cfg = cfg.settingModelOverride(role: .coder, modelId: "claude-opus-4.6")
        try AXProjectStore.saveConfig(cfg, for: ctx)

        let project = ProjectModel(
            name: "Route Truth Project",
            taskDescription: "Critical implementation work",
            modelName: "local-small",
            isLocalModel: true,
            registeredProjectBinding: ProjectRegistryBinding(
                projectId: AXProjectRegistryStore.projectId(forRoot: rootURL),
                rootPath: rootURL.path,
                displayName: "Route Truth Project"
            ),
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            budget: Budget(daily: 50, monthly: 500)
        )
        project.currentModel = XTModelCatalog.modelInfo(for: "local-small", preferLocalHint: true)

        let allocatedModel = XTModelCatalog.modelInfo(for: "claude-opus-4.6")
        let allocation = ProjectAllocation(
            project: project,
            model: allocatedModel,
            priority: 10,
            estimatedDuration: 3_600,
            requiresExclusive: false
        )
        let runtimeHost = SupervisorOrchestratorRuntimeHostSpy()
        let orchestrator = SupervisorOrchestrator(runtimeHost: runtimeHost)

        await orchestrator.executeProject(allocation)

        #expect(project.configuredCoderModelId == "claude-opus-4.6")
        #expect(project.status == .running)
        #expect(project.currentModel.id == "local-small")
        #expect(runtimeHost.startedProjectIDs == [project.id])
        #expect(runtimeHost.startedModelIDs == ["claude-opus-4.6"])
    }
}

@MainActor
private final class SupervisorOrchestratorRuntimeHostSpy: SupervisorProjectRuntimeHosting {
    var activeProjects: [ProjectModel] = []
    var taskAssignerForRuntime: TaskAssigner? = nil
    var startedProjectIDs: [UUID] = []
    var startedModelIDs: [String] = []

    func addActiveProjectIfNeeded(_ project: ProjectModel) {
        guard !activeProjects.contains(where: { $0.id == project.id }) else { return }
        activeProjects.append(project)
    }

    func onProjectCreated(_ project: ProjectModel) async {}
    func onProjectDeleted(_ project: ProjectModel) async {}
    func onProjectStarted(_ project: ProjectModel) async {}
    func onProjectPaused(_ project: ProjectModel) async {}
    func onProjectResumed(_ project: ProjectModel) async {}
    func onProjectCompleted(_ project: ProjectModel) async {}
    func onProjectArchived(_ project: ProjectModel) async {}

    func onProjectExecutionStarted(_ project: ProjectModel, model: ModelInfo) async {
        startedProjectIDs.append(project.id)
        startedModelIDs.append(model.id)
    }

    func suggestModelUpgrade(for project: ProjectModel) async {}
}
