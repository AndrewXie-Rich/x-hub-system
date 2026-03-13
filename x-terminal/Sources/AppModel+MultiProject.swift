//
//  AppModel+MultiProject.swift
//  XTerminal
//
//  多项目管理扩展
//

import Foundation

/// AppModel 的多项目管理扩展
@MainActor
extension AppModel {
    // MARK: - Multi-Project Support

    /// 多项目管理器（懒加载）
    private static var _multiProjectManager: MultiProjectManager?
    private static var _supervisor: SupervisorModel?

    var multiProjectManager: MultiProjectManager {
        if Self._multiProjectManager == nil {
            // 先创建 supervisor，因为 multiProjectManager 需要它
            if Self._supervisor == nil {
                Self._supervisor = SupervisorModel()
            }
            Self._multiProjectManager = MultiProjectManager(supervisor: Self._supervisor!)
        }
        return Self._multiProjectManager!
    }

    /// Supervisor 模型（懒加载）
    var supervisor: SupervisorModel {
        if Self._supervisor == nil {
            Self._supervisor = SupervisorModel()
        }
        return Self._supervisor!
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
        executionTier: AXProjectExecutionTier = .a3DeliverAuto,
        supervisorInterventionTier: AXProjectSupervisorInterventionTier? = nil,
        reviewPolicyMode: AXProjectReviewPolicyMode? = nil,
        progressHeartbeatSeconds: Int? = nil,
        reviewPulseSeconds: Int? = nil,
        brainstormReviewSeconds: Int? = nil,
        eventDrivenReviewEnabled: Bool? = nil
    ) async -> ProjectModel {
        let config = ProjectConfig(
            name: name,
            taskDescription: taskDescription,
            modelName: modelName,
            autonomyLevel: .fromExecutionTier(executionTier),
            executionTier: executionTier,
            supervisorInterventionTier: supervisorInterventionTier,
            reviewPolicyMode: reviewPolicyMode,
            progressHeartbeatSeconds: progressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            eventDrivenReviewEnabled: eventDrivenReviewEnabled
        )

        return await multiProjectManager.createProject(config)
    }

    /// 删除项目
    func deleteMultiProject(_ projectId: UUID) async {
        await multiProjectManager.deleteProject(projectId)
    }

    /// 开始项目
    func startMultiProject(_ projectId: UUID) async {
        await multiProjectManager.startProject(projectId)
    }

    /// 暂停项目
    func pauseMultiProject(_ projectId: UUID) async {
        await multiProjectManager.pauseProject(projectId)
    }

    /// 恢复项目
    func resumeMultiProject(_ projectId: UUID) async {
        await multiProjectManager.resumeProject(projectId)
    }

    /// 完成项目
    func completeMultiProject(_ projectId: UUID) async {
        await multiProjectManager.completeProject(projectId)
    }
}
