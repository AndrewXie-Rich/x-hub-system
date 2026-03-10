import Foundation

// MARK: - Memory System Data Models

/// 完整的记忆系统
struct Memory: Codable, Equatable {
    var userContext: UserContext
    var history: History
    var facts: [Fact]

    init() {
        self.userContext = UserContext()
        self.history = History()
        self.facts = []
    }
}

// MARK: - User Context

/// 用户上下文信息
struct UserContext: Codable, Equatable {
    var work: WorkContext
    var personal: PersonalContext
    var focus: [String]
    var preferences: [String: String]

    init() {
        self.work = WorkContext()
        self.personal = PersonalContext()
        self.focus = []
        self.preferences = [:]
    }
}

/// 工作相关上下文
struct WorkContext: Codable, Equatable {
    var currentProjects: [String]
    var technologies: [String]
    var roles: [String]
    var goals: [String]

    init() {
        self.currentProjects = []
        self.technologies = []
        self.roles = []
        self.goals = []
    }
}

/// 个人信息上下文
struct PersonalContext: Codable, Equatable {
    var name: String?
    var timezone: String?
    var language: String?
    var interests: [String]

    init() {
        self.name = nil
        self.timezone = nil
        self.language = nil
        self.interests = []
    }
}

// MARK: - History

/// 历史记录
struct History: Codable, Equatable {
    var recent: [HistoryItem]      // 最近 10 条
    var earlier: [HistoryItem]     // 早期 20 条
    var longTerm: [HistoryItem]    // 长期 30 条

    init() {
        self.recent = []
        self.earlier = []
        self.longTerm = []
    }

    /// 添加历史记录项
    mutating func addItem(_ item: HistoryItem) {
        // 添加到 recent
        recent.insert(item, at: 0)

        // 如果 recent 超过 10 条，移动到 earlier
        if recent.count > 10 {
            let moved = recent.removeLast()
            earlier.insert(moved, at: 0)
        }

        // 如果 earlier 超过 20 条，移动到 longTerm
        if earlier.count > 20 {
            let moved = earlier.removeLast()
            longTerm.insert(moved, at: 0)
        }

        // 如果 longTerm 超过 30 条，删除最旧的
        if longTerm.count > 30 {
            longTerm.removeLast()
        }
    }

    /// 获取所有历史记录
    func allItems() -> [HistoryItem] {
        return recent + earlier + longTerm
    }

    /// 搜索历史记录
    func search(query: String) -> [HistoryItem] {
        let lowercaseQuery = query.lowercased()
        return allItems().filter { item in
            item.summary.lowercased().contains(lowercaseQuery) ||
            item.keywords.contains { $0.lowercased().contains(lowercaseQuery) }
        }
    }
}

/// 历史记录项
struct HistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var summary: String
    var keywords: [String]
    var timestamp: Date
    var importance: Double  // 0.0 - 1.0

    init(summary: String, keywords: [String] = [], importance: Double = 0.5) {
        self.id = UUID()
        self.summary = summary
        self.keywords = keywords
        self.timestamp = Date()
        self.importance = importance
    }
}

// MARK: - Facts

/// 事实库
struct Fact: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    var confidence: Double         // 0.0 - 1.0
    var source: String
    var category: FactCategory
    var tags: [String]
    var createdAt: Date
    var lastVerified: Date
    var verificationCount: Int

    init(
        content: String,
        confidence: Double = 0.7,
        source: String,
        category: FactCategory = .general,
        tags: [String] = []
    ) {
        self.id = UUID()
        self.content = content
        self.confidence = confidence
        self.source = source
        self.category = category
        self.tags = tags
        self.createdAt = Date()
        self.lastVerified = Date()
        self.verificationCount = 1
    }

    /// 更新置信度
    mutating func updateConfidence(delta: Double) {
        confidence = max(0.0, min(1.0, confidence + delta))
        lastVerified = Date()
        verificationCount += 1
    }

    /// 是否过期（超过 30 天未验证）
    func isExpired() -> Bool {
        let daysSinceVerification = Date().timeIntervalSince(lastVerified) / 86400
        return daysSinceVerification > 30
    }

    /// 是否应该保留（置信度 > 0.7）
    func shouldRetain() -> Bool {
        return confidence > 0.7
    }
}

/// 事实类别
enum FactCategory: String, Codable, CaseIterable {
    case general = "通用"
    case technical = "技术"
    case personal = "个人"
    case project = "项目"
    case preference = "偏好"
    case workflow = "工作流"
}

// MARK: - Memory Statistics

/// 记忆统计信息
struct MemoryStatistics: Codable {
    var totalFacts: Int
    var factsByCategory: [FactCategory: Int]
    var averageConfidence: Double
    var historyItemCount: Int
    var lastUpdated: Date

    init(memory: Memory) {
        self.totalFacts = memory.facts.count

        // 按类别统计事实
        var categoryCount: [FactCategory: Int] = [:]
        for fact in memory.facts {
            categoryCount[fact.category, default: 0] += 1
        }
        self.factsByCategory = categoryCount

        // 计算平均置信度
        if memory.facts.isEmpty {
            self.averageConfidence = 0.0
        } else {
            let totalConfidence = memory.facts.reduce(0.0) { $0 + $1.confidence }
            self.averageConfidence = totalConfidence / Double(memory.facts.count)
        }

        self.historyItemCount = memory.history.allItems().count
        self.lastUpdated = Date()
    }
}

// MARK: - Memory Errors

/// 记忆系统错误
enum MemoryError: Error, LocalizedError {
    case fileNotFound
    case invalidData
    case encodingFailed
    case decodingFailed
    case confidenceTooLow
    case factLimitExceeded

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "记忆文件未找到"
        case .invalidData:
            return "无效的记忆数据"
        case .encodingFailed:
            return "记忆编码失败"
        case .decodingFailed:
            return "记忆解码失败"
        case .confidenceTooLow:
            return "置信度过低，无法添加事实"
        case .factLimitExceeded:
            return "事实数量超过限制（最多 100 个）"
        }
    }
}

// MARK: - Helper Extensions

extension Memory {
    /// 添加事实
    mutating func addFact(_ fact: Fact) throws {
        // 检查置信度
        guard fact.confidence > 0.7 else {
            throw MemoryError.confidenceTooLow
        }

        // 检查数量限制
        guard facts.count < 100 else {
            throw MemoryError.factLimitExceeded
        }

        // 检查是否已存在相似事实
        if let existingIndex = facts.firstIndex(where: { $0.content == fact.content }) {
            // 更新现有事实的置信度
            facts[existingIndex].updateConfidence(delta: 0.1)
        } else {
            // 添加新事实
            facts.append(fact)
        }
    }

    /// 移除事实
    mutating func removeFact(_ factId: UUID) {
        facts.removeAll { $0.id == factId }
    }

    /// 清理过期和低置信度的事实
    mutating func cleanupFacts() {
        facts.removeAll { fact in
            fact.isExpired() || !fact.shouldRetain()
        }
    }

    /// 搜索事实
    func searchFacts(query: String) -> [Fact] {
        let lowercaseQuery = query.lowercased()
        return facts.filter { fact in
            fact.content.lowercased().contains(lowercaseQuery) ||
            fact.tags.contains { $0.lowercased().contains(lowercaseQuery) }
        }
    }

    /// 按类别获取事实
    func getFacts(by category: FactCategory) -> [Fact] {
        return facts.filter { $0.category == category }
    }

    /// 获取高置信度事实
    func getHighConfidenceFacts(threshold: Double = 0.9) -> [Fact] {
        return facts.filter { $0.confidence >= threshold }
    }

    /// 获取统计信息
    func getStatistics() -> MemoryStatistics {
        return MemoryStatistics(memory: self)
    }
}
