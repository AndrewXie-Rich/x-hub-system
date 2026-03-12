//
//  ProjectModel.swift
//  XTerminal
//
//

import Foundation
import SwiftUI
import Combine

/// 项目状态
enum ProjectStatus: String, Codable {
    case pending    // 待开始
    case running    // 运行中
    case paused     // 已暂停
    case blocked    // 被阻塞
    case completed  // 已完成
    case archived   // 已归档

    var color: Color {
        switch self {
        case .pending: return .gray
        case .running: return .green
        case .paused: return .yellow
        case .blocked: return .red
        case .completed: return .blue
        case .archived: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .running: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .blocked: return "exclamationmark.triangle.fill"
        case .completed: return "checkmark.circle.fill"
        case .archived: return "archivebox.fill"
        }
    }

    var text: String {
        switch self {
        case .pending: return "待开始"
        case .running: return "运行中"
        case .paused: return "已暂停"
        case .blocked: return "被阻塞"
        case .completed: return "已完成"
        case .archived: return "已归档"
        }
    }
}

/// 自主性级别
enum AutonomyLevel: Int, Codable, CaseIterable {
    case manual = 1      // 完全手动
    case assisted = 2    // 辅助模式
    case semiAuto = 3    // 半自动
    case auto = 4        // 自动
    case fullAuto = 5    // 完全自动

    var description: String {
        switch self {
        case .manual: return "完全手动"
        case .assisted: return "辅助模式"
        case .semiAuto: return "半自动"
        case .auto: return "自动"
        case .fullAuto: return "完全自动"
        }
    }

    var stars: String {
        String(repeating: "●", count: rawValue) + String(repeating: "○", count: 5 - rawValue)
    }
}

/// 项目模型
@MainActor
class ProjectModel: ObservableObject, Identifiable {
    // MARK: - Basic Properties

    let id: UUID
    @Published var name: String
    @Published var taskDescription: String
    @Published var taskIcon: String
    @Published var status: ProjectStatus

    // MARK: - Model & Configuration

    @Published var currentModel: ModelInfo
    @Published var autonomyLevel: AutonomyLevel
    @Published var priority: Int = 0

    // MARK: - Budget & Cost

    @Published var budget: Budget
    @Published var costTracker: CostTracker

    // MARK: - Collaboration

    @Published var dependencies: [UUID] = []        // 依赖的项目
    @Published var dependents: [UUID] = []          // 依赖此项目的项目
    @Published var sharedKnowledge: [KnowledgeItem] = []
    @Published var collaboratingProjects: [UUID] = []

    // MARK: - Session & Messages

    @Published var session: ChatSessionModel
    @Published var messageCount: Int = 0
    @Published var pendingApprovals: Int = 0

    // MARK: - Phase 2: Task Queue

    @Published var taskQueue: [DecomposedTask] = []

    // MARK: - Timestamps

    @Published var createdAt: Date
    @Published var startTime: Date?
    @Published var pauseTime: Date?
    @Published var resumeTime: Date?
    @Published var completionTime: Date?
    @Published var archiveTime: Date?

    // MARK: - Computed Properties

    var statusColor: Color { status.color }
    var primaryStatusIcon: String { status.icon }
    var primaryStatusColor: Color { status.color }

    var primaryStatusText: String {
        if pendingApprovals > 0 {
            return "待授权: \(pendingApprovals)"
        }
        return status.text
    }

    var lastActivityTime: String {
        let now = Date()
        let lastActivity = resumeTime ?? startTime ?? createdAt
        let interval = now.timeIntervalSince(lastActivity)

        if interval < 60 {
            return "刚刚"
        } else if interval < 3600 {
            return "\(Int(interval / 60))分钟前"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))小时前"
        } else {
            return "\(Int(interval / 86400))天前"
        }
    }

    var isBlocked: Bool {
        status == .blocked
    }

    var blockedDuration: TimeInterval {
        guard isBlocked, let pauseTime = pauseTime else { return 0 }
        return Date().timeIntervalSince(pauseTime)
    }

    var totalDuration: TimeInterval {
        guard let start = startTime else { return 0 }
        let end = completionTime ?? Date()
        return end.timeIntervalSince(start)
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        taskDescription: String,
        taskIcon: String = "doc.text",
        status: ProjectStatus = .pending,
        modelName: String,
        isLocalModel: Bool = false,
        autonomyLevel: AutonomyLevel = .assisted,
        budget: Budget = Budget(daily: 10.0, monthly: 300.0)
    ) {
        self.id = id
        self.name = name
        self.taskDescription = taskDescription
        self.taskIcon = taskIcon
        self.status = status
        self.currentModel = ModelInfo(
            id: modelName,
            name: modelName,
            displayName: modelName,
            type: isLocalModel ? .local : .hubPaid,
            capability: .intermediate,
            speed: .medium,
            costPerMillionTokens: isLocalModel ? nil : 3.0,
            memorySize: isLocalModel ? "40GB" : nil,
            suitableFor: ["通用任务"],
            badge: nil,
            badgeColor: nil
        )
        self.autonomyLevel = autonomyLevel
        self.budget = budget
        self.costTracker = CostTracker()
        self.session = ChatSessionModel()
        self.createdAt = Date()
    }

    // MARK: - Public Methods

    func open() {
        // 打开项目详情
        print("Opening project: \(name)")
    }

    func pause() {
        status = .paused
        pauseTime = Date()
    }

    func resume() {
        status = .running
        resumeTime = Date()
    }

    func complete() {
        status = .completed
        completionTime = Date()
    }

    func archive() {
        status = .archived
        archiveTime = Date()
    }

    func showSettings() {
        // 显示设置界面
        print("Showing settings for: \(name)")
    }

    func delete() {
        // 删除项目
        print("Deleting project: \(name)")
    }

    func changeModel(to newModel: ModelInfo) async {
        // 记录模型切换
        let oldModel = currentModel
        currentModel = newModel

        // 添加系统消息
        let message = "模型已切换: \(oldModel.displayName) → \(newModel.displayName)"
        print(message)
    }

    func updatePriority(_ newPriority: Int) {
        priority = newPriority
    }

    func addDependency(_ projectId: UUID) {
        if !dependencies.contains(projectId) {
            dependencies.append(projectId)
        }
    }

    func removeDependency(_ projectId: UUID) {
        dependencies.removeAll { $0 == projectId }
    }

    func addDependent(_ projectId: UUID) {
        if !dependents.contains(projectId) {
            dependents.append(projectId)
        }
    }

    func removeDependent(_ projectId: UUID) {
        dependents.removeAll { $0 == projectId }
    }

    func shareKnowledge(_ knowledge: KnowledgeItem) {
        sharedKnowledge.append(knowledge)
    }

    func startCollaboration(with projectId: UUID) {
        if !collaboratingProjects.contains(projectId) {
            collaboratingProjects.append(projectId)
        }
    }

    func endCollaboration(with projectId: UUID) {
        collaboratingProjects.removeAll { $0 == projectId }
    }
}

// MARK: - Supporting Types

/// 知识项
struct KnowledgeItem: Identifiable, Codable {
    let id: UUID
    let type: KnowledgeType
    let title: String
    let content: String
    let createdAt: Date
    let tags: [String]

    init(
        id: UUID = UUID(),
        type: KnowledgeType,
        title: String,
        content: String,
        tags: [String] = []
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.content = content
        self.createdAt = Date()
        self.tags = tags
    }
}

/// 知识类型
enum KnowledgeType: String, Codable {
    case api            // API 定义
    case dataModel      // 数据模型
    case codePattern    // 代码模式
    case configuration  // 配置信息
    case documentation  // 文档
    case solution       // 解决方案
}

/// 成本追踪器
class CostTracker: ObservableObject {
    @Published var totalCost: Double = 0.0
    @Published var totalTokens: Int = 0
    @Published var costByModel: [String: Double] = [:]
    @Published var tokensByModel: [String: Int] = [:]

    func recordUsage(modelId: String, tokens: Int, cost: Double) {
        totalCost += cost
        totalTokens += tokens
        costByModel[modelId, default: 0] += cost
        tokensByModel[modelId, default: 0] += tokens
    }

    func reset() {
        totalCost = 0.0
        totalTokens = 0
        costByModel.removeAll()
        tokensByModel.removeAll()
    }

    func getCostForModel(_ modelId: String) -> Double {
        return costByModel[modelId] ?? 0.0
    }

    func getTokensForModel(_ modelId: String) -> Int {
        return tokensByModel[modelId] ?? 0
    }
}

/// 模型信息（简化版，完整版在 MODEL_SELECTOR_DESIGN.md）
struct ModelInfo: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let displayName: String
    let type: ModelType
    let capability: ModelCapability
    let speed: ModelSpeed
    let costPerMillionTokens: Double?
    let memorySize: String?
    let suitableFor: [String]
    let badge: String?
    let badgeColor: Color?

    var isLocal: Bool {
        type == .local
    }

    var costText: String {
        if let cost = costPerMillionTokens {
            return "$\(String(format: "%.2f", cost))/1M tokens"
        } else {
            return "免费"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, displayName, type, capability, speed
        case costPerMillionTokens, memorySize, suitableFor, badge
    }

    init(
        id: String,
        name: String,
        displayName: String,
        type: ModelType,
        capability: ModelCapability,
        speed: ModelSpeed,
        costPerMillionTokens: Double?,
        memorySize: String?,
        suitableFor: [String],
        badge: String?,
        badgeColor: Color?
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.type = type
        self.capability = capability
        self.speed = speed
        self.costPerMillionTokens = costPerMillionTokens
        self.memorySize = memorySize
        self.suitableFor = suitableFor
        self.badge = badge
        self.badgeColor = badgeColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        type = try container.decode(ModelType.self, forKey: .type)
        capability = try container.decode(ModelCapability.self, forKey: .capability)
        speed = try container.decode(ModelSpeed.self, forKey: .speed)
        costPerMillionTokens = try container.decodeIfPresent(Double.self, forKey: .costPerMillionTokens)
        memorySize = try container.decodeIfPresent(String.self, forKey: .memorySize)
        suitableFor = try container.decode([String].self, forKey: .suitableFor)
        badge = try container.decodeIfPresent(String.self, forKey: .badge)
        badgeColor = nil // Color 不支持 Codable，使用默认值
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(type, forKey: .type)
        try container.encode(capability, forKey: .capability)
        try container.encode(speed, forKey: .speed)
        try container.encodeIfPresent(costPerMillionTokens, forKey: .costPerMillionTokens)
        try container.encodeIfPresent(memorySize, forKey: .memorySize)
        try container.encode(suitableFor, forKey: .suitableFor)
        try container.encodeIfPresent(badge, forKey: .badge)
    }
}

enum ModelType: String, Codable {
    case local
    case hubPaid
}

enum ModelCapability: Int, Codable {
    case basic = 3
    case intermediate = 4
    case advanced = 5
    case expert = 6

    var stars: String {
        String(repeating: "⭐", count: rawValue)
    }
}

enum ModelSpeed: String, Codable {
    case ultraFast
    case fast
    case medium
    case slow

    var icon: String {
        switch self {
        case .ultraFast: return "bolt.fill"
        case .fast: return "bolt"
        case .medium: return "gauge.medium"
        case .slow: return "tortoise"
        }
    }

    var text: String {
        switch self {
        case .ultraFast: return "极快"
        case .fast: return "快速"
        case .medium: return "中速"
        case .slow: return "较慢"
        }
    }
}
