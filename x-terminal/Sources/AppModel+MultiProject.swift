//
//  AppModel+MultiProject.swift
//  XTerminal
//
//  多项目管理扩展
//

import Foundation

enum AppModelProjectCreationError: LocalizedError {
    case failedToMaterializeRegisteredBoundary

    var errorDescription: String? {
        switch self {
        case .failedToMaterializeRegisteredBoundary:
            return "未能初始化真实项目边界与 project memory。"
        }
    }
}

@MainActor
final class XTLegacySupervisorRuntimeContext: SupervisorProjectRuntimeHosting {
    let supervisor: SupervisorModel
    let orchestrator: SupervisorOrchestrator
    let monitor: ExecutionMonitor

    init(
        supervisor: SupervisorModel,
        orchestrator: SupervisorOrchestrator,
        monitor: ExecutionMonitor
    ) {
        self.supervisor = supervisor
        self.orchestrator = orchestrator
        self.monitor = monitor
    }

    var activeProjects: [ProjectModel] {
        supervisor.activeProjects
    }

    var taskAssignerForRuntime: TaskAssigner? {
        orchestrator.taskAssigner
    }

    func addActiveProjectIfNeeded(_ project: ProjectModel) {
        supervisor.addActiveProjectIfNeeded(project)
    }

    func onProjectCreated(_ project: ProjectModel) async {
        await supervisor.onProjectCreated(project)
    }

    func onProjectDeleted(_ project: ProjectModel) async {
        await supervisor.onProjectDeleted(project)
    }

    func onProjectStarted(_ project: ProjectModel) async {
        await supervisor.onProjectStarted(project)
    }

    func onProjectPaused(_ project: ProjectModel) async {
        await supervisor.onProjectPaused(project)
    }

    func onProjectResumed(_ project: ProjectModel) async {
        await supervisor.onProjectResumed(project)
    }

    func onProjectCompleted(_ project: ProjectModel) async {
        await supervisor.onProjectCompleted(project)
    }

    func onProjectArchived(_ project: ProjectModel) async {
        await supervisor.onProjectArchived(project)
    }

    func onProjectExecutionStarted(_ project: ProjectModel, model: ModelInfo) async {
        await supervisor.onProjectExecutionStarted(project, model: model)
    }

    func suggestModelUpgrade(for project: ProjectModel) async {
        await supervisor.suggestModelUpgrade(for: project)
    }
}

/// AppModel 的多项目管理扩展
@MainActor
extension AppModel {
    // MARK: - Multi-Project Support

    /// 旧多项目管理器（懒加载）
    private static var _multiProjectManager: MultiProjectManager?
    private static var _legacySupervisorRuntimeContext: XTLegacySupervisorRuntimeContext?

    var legacyMultiProjectManager: MultiProjectManager {
        if Self._multiProjectManager == nil {
            Self._multiProjectManager = MultiProjectManager(
                runtimeHost: ensureLegacySupervisorRuntimeContext()
            )
        }
        return Self._multiProjectManager!
    }

    @available(*, deprecated, message: "Use legacyMultiProjectManager")
    var multiProjectManager: MultiProjectManager {
        legacyMultiProjectManager
    }

    var legacySupervisorRuntimeContextIfLoaded: XTLegacySupervisorRuntimeContext? {
        Self._legacySupervisorRuntimeContext
    }

    func ensureLegacySupervisorRuntimeContext() -> XTLegacySupervisorRuntimeContext {
        if let runtime = Self._legacySupervisorRuntimeContext {
            return runtime
        }
        let runtime = makeLegacySupervisorRuntimeContext()
        Self._legacySupervisorRuntimeContext = runtime
        return runtime
    }

    private func makeLegacySupervisorRuntimeContext() -> XTLegacySupervisorRuntimeContext {
        let supervisor = SupervisorModel()
        let orchestrator = supervisor.orchestrator ?? SupervisorOrchestrator(runtimeHost: supervisor)
        supervisor.orchestrator = orchestrator
        return XTLegacySupervisorRuntimeContext(
            supervisor: supervisor,
            orchestrator: orchestrator,
            monitor: orchestrator.executionMonitor
        )
    }

    /// 是否启用多项目视图
    var isMultiProjectViewEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: "xterminal_multi_project_view_enabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "xterminal_multi_project_view_enabled")
            objectWillChange.send()
        }
    }

    /// 切换多项目视图
    func toggleMultiProjectView() {
        isMultiProjectViewEnabled.toggle()
    }

    /// 创建新项目
    func createMultiProject(
        name: String,
        taskDescription: String,
        modelName: String,
        registeredProjectId: String? = nil,
        materializeRegisteredProjectIfNeeded: Bool = false,
        executionTier: AXProjectExecutionTier = .a3DeliverAuto,
        supervisorInterventionTier: AXProjectSupervisorInterventionTier? = nil,
        reviewPolicyMode: AXProjectReviewPolicyMode? = nil,
        progressHeartbeatSeconds: Int? = nil,
        reviewPulseSeconds: Int? = nil,
        brainstormReviewSeconds: Int? = nil,
        eventDrivenReviewEnabled: Bool? = nil,
        eventReviewTriggers: [AXProjectReviewTrigger]? = nil,
        projectRecentDialogueProfile: AXProjectRecentDialogueProfile? = nil,
        projectContextDepthProfile: AXProjectContextDepthProfile? = nil
    ) async throws -> ProjectModel {
        let binding = registeredProjectId
            .flatMap { registry.project(for: $0) }
            .map {
                ProjectRegistryBinding(
                    projectId: $0.projectId,
                    rootPath: $0.rootPath,
                    displayName: $0.displayName
                )
            }
        let resolvedBinding: ProjectRegistryBinding?
        if let binding {
            let refreshedEntry = ensureRegisteredProjectBoundary(
                at: URL(fileURLWithPath: binding.rootPath, isDirectory: true),
                preferredDisplayName: binding.displayName,
                initializeMemoryBoundary: materializeRegisteredProjectIfNeeded
            )
            if let refreshedEntry {
                resolvedBinding = ProjectRegistryBinding(
                    projectId: refreshedEntry.projectId,
                    rootPath: refreshedEntry.rootPath,
                    displayName: refreshedEntry.displayName
                )
            } else if materializeRegisteredProjectIfNeeded {
                throw AppModelProjectCreationError.failedToMaterializeRegisteredBoundary
            } else {
                resolvedBinding = binding
            }
        } else if materializeRegisteredProjectIfNeeded {
            guard let materializedBinding = materializeProjectBoundaryForMultiProject(
                name: name,
                taskDescription: taskDescription,
                modelName: modelName,
                executionTier: executionTier,
                supervisorInterventionTier: supervisorInterventionTier,
                reviewPolicyMode: reviewPolicyMode,
                progressHeartbeatSeconds: progressHeartbeatSeconds,
                reviewPulseSeconds: reviewPulseSeconds,
                brainstormReviewSeconds: brainstormReviewSeconds,
                eventDrivenReviewEnabled: eventDrivenReviewEnabled,
                eventReviewTriggers: eventReviewTriggers,
                projectRecentDialogueProfile: projectRecentDialogueProfile,
                projectContextDepthProfile: projectContextDepthProfile
            ) else {
                throw AppModelProjectCreationError.failedToMaterializeRegisteredBoundary
            }
            resolvedBinding = materializedBinding
        } else {
            resolvedBinding = nil
        }
        let config = ProjectConfig(
            name: name,
            taskDescription: taskDescription,
            modelName: modelName,
            registeredProjectBinding: resolvedBinding,
            executionTier: executionTier,
            supervisorInterventionTier: supervisorInterventionTier,
            reviewPolicyMode: reviewPolicyMode,
            progressHeartbeatSeconds: progressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            eventDrivenReviewEnabled: eventDrivenReviewEnabled,
            eventReviewTriggers: eventReviewTriggers
        )

        return await legacyMultiProjectManager.createProject(config)
    }

    @discardableResult
    func ensureRegisteredProjectBoundary(
        at root: URL,
        preferredDisplayName: String? = nil,
        initializeMemoryBoundary: Bool = true,
        selectAfterUpsert: Bool = false
    ) -> AXProjectEntry? {
        let normalizedRoot = root.standardizedFileURL
        do {
            try FileManager.default.createDirectory(at: normalizedRoot, withIntermediateDirectories: true)
        } catch {
            print("Project boundary root creation failed for \(normalizedRoot.path): \(error)")
            return nil
        }

        let previousRegistry = registry
        var reg = registry
        let res = AXProjectRegistryStore.upsertProject(reg, root: normalizedRoot)
        reg = res.0
        var entry = res.1

        let preferred = (preferredDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = reg.projects.firstIndex(where: { $0.projectId == entry.projectId }) {
            if !preferred.isEmpty, reg.projects[idx].displayName != preferred {
                reg.projects[idx].displayName = preferred
            }
            entry = reg.projects[idx]
        }

        if selectAfterUpsert {
            reg.lastSelectedProjectId = entry.projectId
        }

        registry = reg
        AXProjectRegistryStore.save(reg)

        let ctx = AXProjectContext(root: normalizedRoot)
        do {
            _ = try AXProjectStore.loadOrCreateConfig(for: ctx)
            if initializeMemoryBoundary {
                _ = try AXProjectStore.loadOrCreateMemory(for: ctx)
            }
        } catch {
            registry = previousRegistry
            AXProjectRegistryStore.save(previousRegistry)
            print("Project boundary initialization failed for \(normalizedRoot.path): \(error)")
            return nil
        }

        if selectAfterUpsert {
            selectedProjectId = entry.projectId
        }

        return entry
    }

    private func materializeProjectBoundaryForMultiProject(
        name: String,
        taskDescription: String,
        modelName: String,
        executionTier: AXProjectExecutionTier,
        supervisorInterventionTier: AXProjectSupervisorInterventionTier?,
        reviewPolicyMode: AXProjectReviewPolicyMode?,
        progressHeartbeatSeconds: Int?,
        reviewPulseSeconds: Int?,
        brainstormReviewSeconds: Int?,
        eventDrivenReviewEnabled: Bool?,
        eventReviewTriggers: [AXProjectReviewTrigger]?,
        projectRecentDialogueProfile: AXProjectRecentDialogueProfile?,
        projectContextDepthProfile: AXProjectContextDepthProfile?
    ) -> ProjectRegistryBinding? {
        let preferredDisplayName = normalizedMaterializedProjectDisplayName(name)
        let root = defaultMaterializedProjectRootURL(for: preferredDisplayName)
        guard let entry = ensureRegisteredProjectBoundary(
            at: root,
            preferredDisplayName: preferredDisplayName,
            initializeMemoryBoundary: false
        ) else {
            return nil
        }

        let ctx = AXProjectContext(root: URL(fileURLWithPath: entry.rootPath, isDirectory: true))
        do {
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingProjectGovernance(
                executionTier: executionTier,
                supervisorInterventionTier: supervisorInterventionTier,
                reviewPolicyMode: reviewPolicyMode,
                progressHeartbeatSeconds: progressHeartbeatSeconds,
                reviewPulseSeconds: reviewPulseSeconds,
                brainstormReviewSeconds: brainstormReviewSeconds,
                eventDrivenReviewEnabled: eventDrivenReviewEnabled,
                eventReviewTriggers: eventReviewTriggers
            )
            config = config.settingProjectContextAssembly(
                projectRecentDialogueProfile: projectRecentDialogueProfile,
                projectContextDepthProfile: projectContextDepthProfile
            )
            config = config.settingRuntimeSurfacePolicy(
                mode: config.executionTier.defaultRuntimeSurfacePreset,
                updatedAt: Date()
            )
            let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedModelName.isEmpty {
                config.setModelOverride(role: .coder, modelId: trimmedModelName)
            }
            try AXProjectStore.saveConfig(config, for: ctx)

            var memory = AXProjectStore.loadMemoryIfPresent(for: ctx)
                ?? AXMemory.new(projectName: entry.displayName, projectRoot: ctx.root.path)
            let normalizedTaskDescription = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let initialGoal = normalizedTaskDescription.isEmpty ? preferredDisplayName : normalizedTaskDescription
            memory.projectName = entry.displayName
            memory.projectRoot = ctx.root.path
            if memory.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                memory.goal = initialGoal
            }
            if memory.requirements.isEmpty, !normalizedTaskDescription.isEmpty {
                memory.requirements = [normalizedTaskDescription]
            }
            if memory.currentState.isEmpty {
                memory.currentState = ["项目已创建，等待第一轮执行。"]
            }
            if memory.nextSteps.isEmpty {
                memory.nextSteps = ["确认首轮计划并开始推进。"]
            }
            try AXProjectStore.saveMemory(memory, for: ctx)
        } catch {
            rollbackMaterializedProjectBoundary(entry: entry, removeRoot: true)
            print("Multi-project materialization failed for \(entry.displayName): \(error)")
            return nil
        }

        return ProjectRegistryBinding(
            projectId: entry.projectId,
            rootPath: entry.rootPath,
            displayName: entry.displayName
        )
    }

    private func rollbackMaterializedProjectBoundary(entry: AXProjectEntry, removeRoot: Bool) {
        var reg = registry
        reg = AXProjectRegistryStore.removeProject(reg, projectId: entry.projectId)
        registry = reg
        AXProjectRegistryStore.save(reg)
        if selectedProjectId == entry.projectId {
            selectedProjectId = reg.lastSelectedProjectId
        }
        guard removeRoot else { return }
        let root = URL(fileURLWithPath: entry.rootPath, isDirectory: true)
        try? FileManager.default.removeItem(at: root)
    }

    private func normalizedMaterializedProjectDisplayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "新项目" : String(trimmed.prefix(80))
    }

    private func defaultMaterializedProjectRootURL(for projectName: String) -> URL {
        let fm = FileManager.default
        let projectsBase = AXProjectRegistryStore.baseDir()
            .appendingPathComponent("Projects", isDirectory: true)
        try? fm.createDirectory(at: projectsBase, withIntermediateDirectories: true)

        let invalidCharacters = CharacterSet(charactersIn: "/:\\\n\r\t")
        let parts = projectName.components(separatedBy: invalidCharacters)
        let compact = parts.joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let baseName = compact.isEmpty ? "新项目" : String(compact.prefix(80))

        var candidate = projectsBase.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = projectsBase.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    /// 删除项目
    func deleteMultiProject(_ projectId: UUID) async {
        await legacyMultiProjectManager.deleteProject(projectId)
    }

    /// 开始项目
    func startMultiProject(_ projectId: UUID) async {
        await legacyMultiProjectManager.startProject(projectId)
    }

    /// 暂停项目
    func pauseMultiProject(_ projectId: UUID) async {
        await legacyMultiProjectManager.pauseProject(projectId)
    }

    /// 恢复项目
    func resumeMultiProject(_ projectId: UUID) async {
        await legacyMultiProjectManager.resumeProject(projectId)
    }

    /// 完成项目
    func completeMultiProject(_ projectId: UUID) async {
        await legacyMultiProjectManager.completeProject(projectId)
    }
}

#if DEBUG
@MainActor
extension AppModel {
    static func resetSharedMultiProjectRuntimeForTesting() {
        _multiProjectManager = nil
        _legacySupervisorRuntimeContext = nil
    }
}
#endif
