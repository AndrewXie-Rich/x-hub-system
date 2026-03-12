//
//  SupervisorModel.swift
//  XTerminal
//
//

import Foundation
import Combine

/// Supervisor 模型
/// 管理整个系统的 AI Supervisor
@MainActor
class SupervisorModel: ObservableObject {
    // MARK: - Published Properties

    @Published var modelName: String = "opus-4.6"
    @Published var isOnline: Bool = false
    @Published var memorySize: String = "0GB"

    @Published var managedProjects: [UUID] = []
    @Published var activeProjects: [ProjectModel] = []
    @Published var completedProjects: [ProjectModel] = []
    @Published var totalProjectsCount: Int = 0
    @Published var pendingApprovals: Int = 0
    @Published var needsAttention: Int = 0

    // MARK: - Dependencies

    var orchestrator: SupervisorOrchestrator!
    let chatSession: ChatSessionModel
    let context: AXProjectContext

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?

    // MARK: - Initialization

    init() {
        // 创建依赖
        self.context = AXProjectContext(root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        self.chatSession = ChatSessionModel()

        // 延迟初始化 orchestrator（需要 self）
        self.orchestrator = SupervisorOrchestrator(supervisor: self)

        // 设置定时更新
        setupAutoUpdate()

        // 初始化连接
        Task {
            await connectToHub()
        }
    }

    // MARK: - Public Methods

    /// 连接到 Hub
    func connectToHub() async {
        // 简化实现：模拟连接
        isOnline = true
        modelName = "opus-4.6"
        memorySize = "0GB"

        print("Supervisor connected to Hub")
    }

    /// 断开连接
    func disconnectFromHub() async {
        isOnline = false
        print("Supervisor disconnected from Hub")
    }

    /// 更新状态
    func updateStatus() async {
        // 从 Hub 获取最新状态
        // 简化实现：保持当前状态
        print("Supervisor status updated")
    }

    /// 发送消息
    func sendMessage(_ text: String) async {
        guard isOnline else {
            print("Supervisor is offline")
            return
        }

        // 处理快速命令
        if text.hasPrefix("/") {
            await handleQuickCommand(text)
            return
        }

        // 发送普通消息到 Supervisor
        print("Sending message to Supervisor: \(text)")

        // 实际实现需要调用 Hub API
        // 这里简化为打印
    }

    /// 处理快速命令
    func handleQuickCommand(_ command: String) async {
        let trimmed = command.trimmingCharacters(in: .whitespaces)

        switch trimmed {
        case "/status":
            await showStatus()

        case "/authorize":
            await showPendingApprovals()

        case "/memory":
            await showMemoryBrowser()

        case "/help":
            await showHelp()

        default:
            if trimmed.hasPrefix("/authorize ") {
                let projectName = String(trimmed.dropFirst("/authorize ".count))
                await authorizeProject(projectName)
            } else {
                print("Unknown command: \(command)")
            }
        }
    }

    /// 显示状态
    func showStatus() async {
        print("=== Supervisor Status ===")
        print("Model: \(modelName)")
        print("Online: \(isOnline)")
        print("Memory: \(memorySize)")
        print("Active Projects: \(activeProjects)/\(totalProjectsCount)")
        print("Pending Approvals: \(pendingApprovals)")
        print("Needs Attention: \(needsAttention)")
        print("Completed: \(completedProjects)")
    }

    /// 显示待审批
    func showPendingApprovals() async {
        print("=== Pending Approvals ===")
        print("Total: \(pendingApprovals)")
        // 实际实现需要显示详细列表
    }

    /// 显示记忆浏览器
    func showMemoryBrowser() async {
        print("=== Memory Browser ===")
        print("Total Memory: \(memorySize)")
        // 实际实现需要显示记忆内容
    }

    /// 显示帮助
    func showHelp() async {
        print("=== Supervisor Commands ===")
        print("/status - Show status")
        print("/authorize - Show pending approvals")
        print("/authorize <project> - Authorize project")
        print("/memory - Show memory browser")
        print("/help - Show this help")
    }

    /// 授权项目
    func authorizeProject(_ projectName: String) async {
        print("Authorizing project: \(projectName)")
        // 实际实现需要找到项目并授权
    }

    /// 授权项目（通过 ID）
    func authorizeProject(_ projectId: UUID) async {
        print("Authorizing project: \(projectId)")
        // 实际实现需要调用项目的授权方法
    }

    // MARK: - Project Lifecycle Events

    /// 项目创建事件
    func onProjectCreated(_ project: ProjectModel) async {
        managedProjects.append(project.id)
        totalProjectsCount += 1

        print("Supervisor: Project created - \(project.name)")

        // 通知编排器
        // 实际实现需要触发调度
    }

    /// 项目删除事件
    func onProjectDeleted(_ project: ProjectModel) async {
        managedProjects.removeAll { $0 == project.id }
        totalProjectsCount -= 1

        print("Supervisor: Project deleted - \(project.name)")
    }

    /// 项目开始事件
    func onProjectStarted(_ project: ProjectModel) async {
        if !activeProjects.contains(where: { $0.id == project.id }) {
            activeProjects.append(project)
        }

        print("Supervisor: Project started - \(project.name)")

        // 触发调度
        // 实际实现需要调用 orchestrator.scheduleProjects
    }

    /// 项目暂停事件
    func onProjectPaused(_ project: ProjectModel) async {
        activeProjects.removeAll { $0.id == project.id }

        print("Supervisor: Project paused - \(project.name)")
    }

    /// 项目恢复事件
    func onProjectResumed(_ project: ProjectModel) async {
        if !activeProjects.contains(where: { $0.id == project.id }) {
            activeProjects.append(project)
        }

        print("Supervisor: Project resumed - \(project.name)")
    }

    /// 项目完成事件
    func onProjectCompleted(_ project: ProjectModel) async {
        // 从活跃项目中移除
        activeProjects.removeAll { $0.id == project.id }

        // 添加到完成项目
        completedProjects.append(project)

        print("Supervisor: Project completed - \(project.name)")

        // 生成完成报告
        await generateCompletionReport(project)
    }

    /// 项目归档事件
    func onProjectArchived(_ project: ProjectModel) async {
        print("Supervisor: Project archived - \(project.name)")
    }

    /// 项目执行开始事件
    func onProjectExecutionStarted(_ project: ProjectModel, model: ModelInfo) async {
        print("Supervisor: Project execution started - \(project.name) with \(model.displayName)")
    }

    /// 建议模型升级
    func suggestModelUpgrade(for project: ProjectModel) async {
        print("Supervisor: Suggesting model upgrade for \(project.name)")

        // 实际实现需要：
        // 1. 分析当前模型性能
        // 2. 推荐更好的模型
        // 3. 估算成本差异
        // 4. 通知用户
    }

    // MARK: - Private Methods

    private func setupAutoUpdate() {
        // 每 30 秒更新一次状态
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateStatus()
            }
        }
    }

    private func generateCompletionReport(_ project: ProjectModel) async {
        print("=== Project Completion Report ===")
        print("Project: \(project.name)")
        print("Duration: \(formatDuration(project.totalDuration))")
        print("Messages: \(project.messageCount)")
        print("Cost: $\(String(format: "%.2f", project.costTracker.totalCost))")
        print("Tokens: \(project.costTracker.totalTokens)")
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    // MARK: - Deinit

    deinit {
        updateTimer?.invalidate()
    }
}

// MARK: - Preview Support

#if DEBUG
extension SupervisorModel {
    static var preview: SupervisorModel {
        let supervisor = SupervisorModel()
        supervisor.modelName = "opus-4.6"
        supervisor.isOnline = true
        supervisor.memorySize = "2.3GB"
        supervisor.totalProjectsCount = 10
        supervisor.pendingApprovals = 2
        supervisor.needsAttention = 1
        return supervisor
    }
}
#endif
