import Foundation

@MainActor
protocol SupervisorProjectRuntimeHosting: AnyObject {
    var activeProjects: [ProjectModel] { get }
    var taskAssignerForRuntime: TaskAssigner? { get }

    func addActiveProjectIfNeeded(_ project: ProjectModel)

    func onProjectCreated(_ project: ProjectModel) async
    func onProjectDeleted(_ project: ProjectModel) async
    func onProjectStarted(_ project: ProjectModel) async
    func onProjectPaused(_ project: ProjectModel) async
    func onProjectResumed(_ project: ProjectModel) async
    func onProjectCompleted(_ project: ProjectModel) async
    func onProjectArchived(_ project: ProjectModel) async
    func onProjectExecutionStarted(_ project: ProjectModel, model: ModelInfo) async
    func suggestModelUpgrade(for project: ProjectModel) async
}
