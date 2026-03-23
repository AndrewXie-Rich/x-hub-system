import Foundation
import Combine

// MARK: - Memory Manager

/// 记忆管理器
@MainActor
class MemoryManager: ObservableObject {
    // MARK: - Published Properties

    @Published var memory: Memory
    @Published var isLoading: Bool = false
    @Published var lastError: Error?

    // MARK: - Private Properties

    private let projectId: UUID
    private let fileURL: URL
    private var updateQueue: DispatchQueue
    private var pendingUpdates: Set<UUID> = []
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 30.0  // 30 秒防抖

    // MARK: - Initialization

    init(projectId: UUID) {
        self.projectId = projectId
        self.memory = Memory()

        // 构建文件路径
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let projectDir = appSupport
            .appendingPathComponent("XTerminal")
            .appendingPathComponent("projects")
            .appendingPathComponent(projectId.uuidString)
        self.fileURL = projectDir.appendingPathComponent("memory.json")

        // 创建更新队列
        self.updateQueue = DispatchQueue(
            label: "com.xterminal.memory.\(projectId.uuidString)",
            qos: .utility
        )

        // 确保目录存在
        try? FileManager.default.createDirectory(
            at: projectDir,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Memory Operations

    /// 加载记忆
    func loadMemory() async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            // 检查文件是否存在
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                // 文件不存在，使用默认记忆
                memory = Memory()
                return
            }

            // 读取文件
            let data = try Data(contentsOf: fileURL)

            // 解码
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            memory = try decoder.decode(Memory.self, from: data)

            // 清理过期事实
            memory.cleanupFacts()

        } catch {
            lastError = error
            throw MemoryError.decodingFailed
        }
    }

    /// 保存记忆
    func saveMemory() async throws {
        do {
            // 编码
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(memory)

            // 原子写入
            try XTStoreWriteSupport.writeSnapshotData(data, to: fileURL)

        } catch {
            lastError = error
            throw MemoryError.encodingFailed
        }
    }

    /// 防抖保存
    func debouncedSave() {
        // 取消之前的定时器
        debounceTimer?.invalidate()

        // 创建新的定时器
        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: debounceInterval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                try? await self?.saveMemory()
            }
        }
    }

    /// 立即保存（跳过防抖）
    func saveImmediately() async throws {
        debounceTimer?.invalidate()
        try await saveMemory()
    }

    // MARK: - Memory Updates

    /// 更新事实
    func updateFacts(_ newFacts: [Fact]) async {
        for fact in newFacts {
            try? memory.addFact(fact)
        }
        debouncedSave()
    }

    /// 添加单个事实
    func addFact(_ fact: Fact) async throws {
        try memory.addFact(fact)
        debouncedSave()
    }

    /// 移除事实
    func removeFact(_ factId: UUID) async {
        memory.removeFact(factId)
        debouncedSave()
    }

    /// 更新事实置信度
    func updateConfidence(factId: UUID, delta: Double) async {
        if let index = memory.facts.firstIndex(where: { $0.id == factId }) {
            memory.facts[index].updateConfidence(delta: delta)
            debouncedSave()
        }
    }

    /// 添加历史记录
    func addHistory(_ item: HistoryItem) async {
        memory.history.addItem(item)
        debouncedSave()
    }

    /// 更新用户上下文
    func updateUserContext(_ context: UserContext) async {
        memory.userContext = context
        debouncedSave()
    }

    /// 更新工作上下文
    func updateWorkContext(_ work: WorkContext) async {
        memory.userContext.work = work
        debouncedSave()
    }

    /// 更新个人上下文
    func updatePersonalContext(_ personal: PersonalContext) async {
        memory.userContext.personal = personal
        debouncedSave()
    }

    /// 更新关注点
    func updateFocus(_ focus: [String]) async {
        memory.userContext.focus = focus
        debouncedSave()
    }

    /// 更新偏好设置
    func updatePreferences(_ preferences: [String: String]) async {
        memory.userContext.preferences = preferences
        debouncedSave()
    }

    // MARK: - Memory Queries

    /// 搜索事实
    func searchFacts(query: String) -> [Fact] {
        return memory.searchFacts(query: query)
    }

    /// 按类别获取事实
    func getFacts(by category: FactCategory) -> [Fact] {
        return memory.getFacts(by: category)
    }

    /// 获取高置信度事实
    func getHighConfidenceFacts(threshold: Double = 0.9) -> [Fact] {
        return memory.getHighConfidenceFacts(threshold: threshold)
    }

    /// 搜索历史记录
    func searchHistory(query: String) -> [HistoryItem] {
        return memory.history.search(query: query)
    }

    /// 获取相关上下文
    func getRelevantContext(for task: String) -> String {
        var context = ""

        // 1. 搜索相关事实
        let relevantFacts = searchFacts(query: task)
        if !relevantFacts.isEmpty {
            context += "## 相关事实\n\n"
            for fact in relevantFacts.prefix(5) {
                context += "- \(fact.content) (置信度: \(String(format: "%.0f%%", fact.confidence * 100)))\n"
            }
            context += "\n"
        }

        // 2. 搜索相关历史
        let relevantHistory = searchHistory(query: task)
        if !relevantHistory.isEmpty {
            context += "## 相关历史\n\n"
            for item in relevantHistory.prefix(3) {
                context += "- \(item.summary)\n"
            }
            context += "\n"
        }

        // 3. 添加用户上下文
        if !memory.userContext.work.currentProjects.isEmpty {
            context += "## 当前项目\n\n"
            for project in memory.userContext.work.currentProjects {
                context += "- \(project)\n"
            }
            context += "\n"
        }

        if !memory.userContext.work.technologies.isEmpty {
            context += "## 技术栈\n\n"
            context += memory.userContext.work.technologies.joined(separator: ", ")
            context += "\n\n"
        }

        if !memory.userContext.focus.isEmpty {
            context += "## 当前关注\n\n"
            for focus in memory.userContext.focus {
                context += "- \(focus)\n"
            }
            context += "\n"
        }

        return context
    }

    // MARK: - Memory Maintenance

    /// 清理过期事实
    func cleanupExpiredFacts() async {
        let beforeCount = memory.facts.count
        memory.cleanupFacts()
        let afterCount = memory.facts.count

        if beforeCount != afterCount {
            print("清理了 \(beforeCount - afterCount) 个过期或低置信度的事实")
            debouncedSave()
        }
    }

    /// 整理历史记录
    func consolidateHistory() async {
        // 历史记录会自动整理，这里只是触发保存
        debouncedSave()
    }

    /// 导出记忆
    func exportMemory() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(memory)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 导入记忆
    func importMemory(from jsonString: String) async throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw MemoryError.invalidData
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        memory = try decoder.decode(Memory.self, from: data)

        try await saveImmediately()
    }

    /// 重置记忆
    func resetMemory() async throws {
        memory = Memory()
        try await saveImmediately()
    }

    /// 获取统计信息
    func getStatistics() -> MemoryStatistics {
        return memory.getStatistics()
    }

    // MARK: - Batch Operations

    /// 批量添加事实
    func batchAddFacts(_ facts: [Fact]) async {
        var addedCount = 0
        for fact in facts {
            if (try? memory.addFact(fact)) != nil {
                addedCount += 1
            }
        }
        print("批量添加了 \(addedCount) 个事实")
        debouncedSave()
    }

    /// 批量更新置信度
    func batchUpdateConfidence(_ updates: [UUID: Double]) async {
        for (factId, delta) in updates {
            if let index = memory.facts.firstIndex(where: { $0.id == factId }) {
                memory.facts[index].updateConfidence(delta: delta)
            }
        }
        debouncedSave()
    }

    /// 批量移除事实
    func batchRemoveFacts(_ factIds: [UUID]) async {
        for factId in factIds {
            memory.removeFact(factId)
        }
        debouncedSave()
    }

    // MARK: - Cleanup

    deinit {
        debounceTimer?.invalidate()
    }
}

// MARK: - Memory Manager Extensions

extension MemoryManager {
    /// 格式化记忆摘要
    func formatMemorySummary() -> String {
        let stats = getStatistics()
        var summary = "# 记忆摘要\n\n"

        summary += "## 统计信息\n\n"
        summary += "- 总事实数: \(stats.totalFacts)\n"
        summary += "- 平均置信度: \(String(format: "%.0f%%", stats.averageConfidence * 100))\n"
        summary += "- 历史记录数: \(stats.historyItemCount)\n"
        summary += "- 最后更新: \(formatDate(stats.lastUpdated))\n\n"

        if !stats.factsByCategory.isEmpty {
            summary += "## 事实分类\n\n"
            for (category, count) in stats.factsByCategory.sorted(by: { $0.value > $1.value }) {
                summary += "- \(category.rawValue): \(count)\n"
            }
            summary += "\n"
        }

        if !memory.userContext.work.currentProjects.isEmpty {
            summary += "## 当前项目\n\n"
            for project in memory.userContext.work.currentProjects {
                summary += "- \(project)\n"
            }
            summary += "\n"
        }

        if !memory.userContext.focus.isEmpty {
            summary += "## 当前关注\n\n"
            for focus in memory.userContext.focus {
                summary += "- \(focus)\n"
            }
            summary += "\n"
        }

        return summary
    }

    /// 格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// MARK: - Singleton (Optional)

extension MemoryManager {
    /// 全局共享实例（可选）
    private static var sharedInstances: [UUID: MemoryManager] = [:]

    static func shared(for projectId: UUID) -> MemoryManager {
        if let existing = sharedInstances[projectId] {
            return existing
        }

        let manager = MemoryManager(projectId: projectId)
        sharedInstances[projectId] = manager
        return manager
    }

    static func removeShared(for projectId: UUID) {
        sharedInstances.removeValue(forKey: projectId)
    }
}
