//
//  MultiProjectManager.swift
//  XTerminal
//
//

import Foundation
import Combine

/// 多项目管理器
/// 负责管理所有项目的生命周期、状态和协调
@MainActor
class MultiProjectManager: ObservableObject {
    // MARK: - Published Properties

    /// 所有项目
    @Published var projects: [ProjectModel] = []

    /// 活跃的项目（正在运行）
    @Published var activeProjects: [ProjectModel] = []

    /// 暂停的项目
    @Published var pausedProjects: [ProjectModel] = []

    /// 已完成的项目
    @Published var completedProjects: [ProjectModel] = []

    /// 已归档的项目
    @Published var archivedProjects: [ProjectModel] = []

    /// 当前选中的项目
    @Published var selectedProject: ProjectModel?

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private let runtimeHost: any SupervisorProjectRuntimeHosting
    private let sandboxManager: SandboxManager

    // MARK: - Initialization

    init(runtimeHost: any SupervisorProjectRuntimeHosting, sandboxManager: SandboxManager) {
        self.runtimeHost = runtimeHost
        self.sandboxManager = sandboxManager
        setupObservers()
    }

    convenience init(runtimeHost: any SupervisorProjectRuntimeHosting) {
        self.init(runtimeHost: runtimeHost, sandboxManager: SandboxManager.shared)
    }

    // MARK: - Public Methods

    /// 创建新项目
    func createProject(_ config: ProjectConfig) async -> ProjectModel {
        let project = ProjectModel(
            id: UUID(),
            name: config.name,
            taskDescription: config.taskDescription,
            taskIcon: config.taskIcon,
            status: .pending,
            modelName: config.modelName,
            isLocalModel: config.isLocalModel,
            registeredProjectBinding: config.registeredProjectBinding,
            executionTier: config.executionTier,
            supervisorInterventionTier: config.supervisorInterventionTier,
            reviewPolicyMode: config.reviewPolicyMode,
            progressHeartbeatSeconds: config.progressHeartbeatSeconds,
            reviewPulseSeconds: config.reviewPulseSeconds,
            brainstormReviewSeconds: config.brainstormReviewSeconds,
            eventDrivenReviewEnabled: config.eventDrivenReviewEnabled,
            eventReviewTriggers: config.eventReviewTriggers,
            budget: config.budget
        )

        projects.append(project)

        // Best effort: prepare the sandbox early so first execution has no cold-start penalty.
        _ = await ensureSandboxReady(for: project.id)

        // 通知 Supervisor
        await runtimeHost.onProjectCreated(project)

        // 自动开始项目（如果设置了自动启动）
        if config.autoStart {
            await startProject(project.id)
        }

        return project
    }

    /// 删除项目
    func deleteProject(_ id: UUID) async {
        guard let project = findProject(id) else { return }

        // 如果项目正在运行，先暂停
        if project.status == .running {
            await pauseProject(id)
        }

        // 从所有列表中移除
        projects.removeAll { $0.id == id }
        activeProjects.removeAll { $0.id == id }
        pausedProjects.removeAll { $0.id == id }
        completedProjects.removeAll { $0.id == id }
        archivedProjects.removeAll { $0.id == id }

        // 通知 Supervisor
        await runtimeHost.onProjectDeleted(project)

        do {
            try await sandboxManager.destroySandbox(for: id)
        } catch {
            print("Sandbox cleanup failed for project \(id): \(error)")
        }
    }

    /// 开始项目
    func startProject(_ id: UUID) async {
        guard let project = findProject(id) else { return }
        _ = await ensureSandboxReady(for: id)

        project.status = .running
        project.startTime = Date()

        // 添加到活跃列表
        if !activeProjects.contains(where: { $0.id == id }) {
            activeProjects.append(project)
        }

        // 从暂停列表移除
        pausedProjects.removeAll { $0.id == id }

        // 通知 Supervisor 开始调度
        await runtimeHost.onProjectStarted(project)
    }

    /// 暂停项目
    func pauseProject(_ id: UUID) async {
        guard let project = findProject(id) else { return }

        project.status = .paused
        project.pauseTime = Date()

        // 添加到暂停列表
        if !pausedProjects.contains(where: { $0.id == id }) {
            pausedProjects.append(project)
        }

        // 从活跃列表移除
        activeProjects.removeAll { $0.id == id }

        // 通知 Supervisor
        await runtimeHost.onProjectPaused(project)
    }

    /// 恢复项目
    func resumeProject(_ id: UUID) async {
        guard let project = findProject(id) else { return }
        _ = await ensureSandboxReady(for: id)

        project.status = .running
        project.resumeTime = Date()

        // 添加到活跃列表
        if !activeProjects.contains(where: { $0.id == id }) {
            activeProjects.append(project)
        }

        // 从暂停列表移除
        pausedProjects.removeAll { $0.id == id }

        // 通知 Supervisor
        await runtimeHost.onProjectResumed(project)
    }

    /// 完成项目
    func completeProject(_ id: UUID) async {
        guard let project = findProject(id) else { return }

        project.status = .completed
        project.completionTime = Date()

        // 添加到完成列表
        if !completedProjects.contains(where: { $0.id == id }) {
            completedProjects.append(project)
        }

        // 从活跃列表移除
        activeProjects.removeAll { $0.id == id }

        // 通知 Supervisor
        await runtimeHost.onProjectCompleted(project)
    }

    /// 归档项目
    func archiveProject(_ id: UUID) async {
        guard let project = findProject(id) else { return }

        project.status = .archived
        project.archiveTime = Date()

        // 添加到归档列表
        if !archivedProjects.contains(where: { $0.id == id }) {
            archivedProjects.append(project)
        }

        // 从其他列表移除
        activeProjects.removeAll { $0.id == id }
        pausedProjects.removeAll { $0.id == id }
        completedProjects.removeAll { $0.id == id }

        // 通知 Supervisor
        await runtimeHost.onProjectArchived(project)
    }

    /// 选择项目
    func selectProject(_ project: ProjectModel) {
        selectedProject = project
    }

    /// 批量操作：暂停所有活跃项目
    func pauseAllActiveProjects() async {
        for project in activeProjects {
            await pauseProject(project.id)
        }
    }

    /// 批量操作：恢复所有暂停的项目
    func resumeAllPausedProjects() async {
        for project in pausedProjects {
            await resumeProject(project.id)
        }
    }

    /// 批量操作：归档所有已完成的项目
    func archiveAllCompletedProjects() async {
        for project in completedProjects {
            await archiveProject(project.id)
        }
    }

    /// 根据条件筛选项目
    func filterProjects(by predicate: (ProjectModel) -> Bool) -> [ProjectModel] {
        return projects.filter(predicate)
    }

    /// 按优先级排序项目
    func sortProjectsByPriority() -> [ProjectModel] {
        return projects.sorted { $0.priority > $1.priority }
    }

    /// 获取项目统计信息
    func getStatistics() -> ProjectStatistics {
        return ProjectStatistics(
            total: projects.count,
            active: activeProjects.count,
            paused: pausedProjects.count,
            completed: completedProjects.count,
            archived: archivedProjects.count,
            totalCost: projects.reduce(0) { $0 + $1.costTracker.totalCost },
            totalTokens: projects.reduce(0) { $0 + $1.costTracker.totalTokens }
        )
    }

    // MARK: - Private Methods

    private func findProject(_ id: UUID) -> ProjectModel? {
        return projects.first { $0.id == id }
    }

    private func setupObservers() {
        // 监听项目状态变化
        for project in projects {
            project.$status
                .sink { [weak self] newStatus in
                    self?.handleProjectStatusChange(project, newStatus: newStatus)
                }
                .store(in: &cancellables)
        }
    }

    private func handleProjectStatusChange(_ project: ProjectModel, newStatus: ProjectStatus) {
        // 根据状态变化更新列表
        switch newStatus {
        case .running:
            if !activeProjects.contains(where: { $0.id == project.id }) {
                activeProjects.append(project)
            }
            pausedProjects.removeAll { $0.id == project.id }

        case .paused:
            if !pausedProjects.contains(where: { $0.id == project.id }) {
                pausedProjects.append(project)
            }
            activeProjects.removeAll { $0.id == project.id }

        case .completed:
            if !completedProjects.contains(where: { $0.id == project.id }) {
                completedProjects.append(project)
            }
            activeProjects.removeAll { $0.id == project.id }
            pausedProjects.removeAll { $0.id == project.id }

        case .archived:
            if !archivedProjects.contains(where: { $0.id == project.id }) {
                archivedProjects.append(project)
            }
            activeProjects.removeAll { $0.id == project.id }
            pausedProjects.removeAll { $0.id == project.id }
            completedProjects.removeAll { $0.id == project.id }

        default:
            break
        }
    }

    @discardableResult
    private func ensureSandboxReady(for projectId: UUID) async -> Bool {
        do {
            _ = try await sandboxManager.createSandbox(for: projectId)
            return true
        } catch {
            print("Sandbox setup failed for project \(projectId): \(error)")
            return false
        }
    }
}

// MARK: - Supporting Types

/// 项目配置
struct ProjectConfig {
    let name: String
    let taskDescription: String
    let taskIcon: String
    let modelName: String
    let isLocalModel: Bool
    let autonomyLevel: AutonomyLevel
    let registeredProjectBinding: ProjectRegistryBinding?
    let executionTier: AXProjectExecutionTier
    let supervisorInterventionTier: AXProjectSupervisorInterventionTier
    let reviewPolicyMode: AXProjectReviewPolicyMode
    let progressHeartbeatSeconds: Int
    let reviewPulseSeconds: Int
    let brainstormReviewSeconds: Int
    let eventDrivenReviewEnabled: Bool
    let eventReviewTriggers: [AXProjectReviewTrigger]
    let budget: Budget
    let autoStart: Bool

    init(
        name: String,
        taskDescription: String,
        taskIcon: String = "doc.text",
        modelName: String = "llama-3-70b-local",
        isLocalModel: Bool = true,
        autonomyLevel: AutonomyLevel = .manual,
        registeredProjectBinding: ProjectRegistryBinding? = nil,
        executionTier: AXProjectExecutionTier? = nil,
        supervisorInterventionTier: AXProjectSupervisorInterventionTier? = nil,
        reviewPolicyMode: AXProjectReviewPolicyMode? = nil,
        progressHeartbeatSeconds: Int? = nil,
        reviewPulseSeconds: Int? = nil,
        brainstormReviewSeconds: Int? = nil,
        eventDrivenReviewEnabled: Bool? = nil,
        eventReviewTriggers: [AXProjectReviewTrigger]? = nil,
        budget: Budget = Budget(daily: 10.0, monthly: 300.0),
        autoStart: Bool = false
    ) {
        let resolvedExecutionTier = executionTier ?? AXProjectExecutionTier.fromLegacyAutonomyLevel(autonomyLevel)
        let governance = AXProjectGovernanceBundle.recommended(
            for: resolvedExecutionTier,
            supervisorInterventionTier: supervisorInterventionTier
        )
        self.name = name
        self.taskDescription = taskDescription
        self.taskIcon = taskIcon
        self.modelName = modelName
        self.isLocalModel = isLocalModel
        self.autonomyLevel = .fromExecutionTier(resolvedExecutionTier)
        self.registeredProjectBinding = registeredProjectBinding
        self.executionTier = resolvedExecutionTier
        self.supervisorInterventionTier = governance.supervisorInterventionTier
        self.reviewPolicyMode = reviewPolicyMode ?? governance.reviewPolicyMode
        self.progressHeartbeatSeconds = progressHeartbeatSeconds ?? governance.schedule.progressHeartbeatSeconds
        self.reviewPulseSeconds = reviewPulseSeconds ?? governance.schedule.reviewPulseSeconds
        self.brainstormReviewSeconds = brainstormReviewSeconds ?? governance.schedule.brainstormReviewSeconds
        self.eventDrivenReviewEnabled = eventDrivenReviewEnabled ?? governance.schedule.eventDrivenReviewEnabled
        self.eventReviewTriggers = AXProjectReviewTrigger.normalizedList(
            eventReviewTriggers ?? governance.schedule.eventReviewTriggers
        )
        self.budget = budget
        self.autoStart = autoStart
    }
}

/// 项目统计信息
struct ProjectStatistics {
    let total: Int
    let active: Int
    let paused: Int
    let completed: Int
    let archived: Int
    let totalCost: Double
    let totalTokens: Int
}

/// 预算
struct Budget: Codable {
    var daily: Double
    var monthly: Double
    var used: Double = 0.0

    var dailyRemaining: Double {
        max(0, daily - used)
    }

    var monthlyRemaining: Double {
        max(0, monthly - used)
    }

    var dailyPercentage: Double {
        guard daily > 0 else { return 0 }
        return (used / daily) * 100
    }

    var monthlyPercentage: Double {
        guard monthly > 0 else { return 0 }
        return (used / monthly) * 100
    }
}
