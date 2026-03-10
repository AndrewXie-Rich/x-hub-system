import Foundation

// MARK: - Memory Injector

/// 记忆注入系统
@MainActor
class MemoryInjector {
    // MARK: - Properties

    private let maxTokens: Int
    private let relevanceThreshold: Double

    // MARK: - Initialization

    init(maxTokens: Int = 2000, relevanceThreshold: Double = 0.6) {
        self.maxTokens = maxTokens
        self.relevanceThreshold = relevanceThreshold
    }

    // MARK: - Injection Methods

    /// 注入记忆到上下文
    func injectMemory(_ memory: Memory, into context: String) -> String {
        var injectedContext = "# 记忆上下文\n\n"

        // 1. 注入用户上下文
        injectedContext += formatUserContext(memory.userContext)

        // 2. 注入高置信度事实
        let highConfidenceFacts = memory.getHighConfidenceFacts(threshold: 0.8)
        if !highConfidenceFacts.isEmpty {
            injectedContext += formatFacts(highConfidenceFacts)
        }

        // 3. 注入最近历史
        let recentHistory = Array(memory.history.recent.prefix(5))
        if !recentHistory.isEmpty {
            injectedContext += formatHistory(recentHistory)
        }

        // 4. 添加原始上下文
        injectedContext += "\n---\n\n"
        injectedContext += context

        // 5. 检查令牌限制
        return truncateToTokenLimit(injectedContext)
    }

    /// 选择相关记忆
    func selectRelevantMemory(_ memory: Memory, for task: String) -> Memory {
        var relevantMemory = Memory()

        // 1. 复制用户上下文
        relevantMemory.userContext = memory.userContext

        // 2. 选择相关事实
        let relevantFacts = memory.searchFacts(query: task)
            .filter { $0.confidence >= relevanceThreshold }
            .sorted { $0.confidence > $1.confidence }
            .prefix(10)
        relevantMemory.facts = Array(relevantFacts)

        // 3. 选择相关历史
        let relevantHistory = memory.history.search(query: task)
            .sorted { $0.importance > $1.importance }
            .prefix(5)
        for item in relevantHistory {
            relevantMemory.history.addItem(item)
        }

        return relevantMemory
    }

    /// 格式化记忆
    func formatMemory(_ memory: Memory) -> String {
        var formatted = ""

        // 用户上下文
        formatted += formatUserContext(memory.userContext)

        // 事实
        if !memory.facts.isEmpty {
            formatted += formatFacts(memory.facts)
        }

        // 历史
        let allHistory = memory.history.allItems()
        if !allHistory.isEmpty {
            formatted += formatHistory(allHistory)
        }

        return formatted
    }

    // MARK: - Formatting Methods

    /// 格式化用户上下文
    private func formatUserContext(_ context: UserContext) -> String {
        var formatted = "## 用户上下文\n\n"

        // 工作上下文
        if !context.work.currentProjects.isEmpty {
            formatted += "**当前项目**:\n"
            for project in context.work.currentProjects {
                formatted += "- \(project)\n"
            }
            formatted += "\n"
        }

        if !context.work.technologies.isEmpty {
            formatted += "**技术栈**: \(context.work.technologies.joined(separator: ", "))\n\n"
        }

        if !context.work.roles.isEmpty {
            formatted += "**角色**: \(context.work.roles.joined(separator: ", "))\n\n"
        }

        if !context.work.goals.isEmpty {
            formatted += "**目标**:\n"
            for goal in context.work.goals {
                formatted += "- \(goal)\n"
            }
            formatted += "\n"
        }

        // 个人上下文
        if let name = context.personal.name {
            formatted += "**姓名**: \(name)\n"
        }

        if let timezone = context.personal.timezone {
            formatted += "**时区**: \(timezone)\n"
        }

        if let language = context.personal.language {
            formatted += "**语言**: \(language)\n"
        }

        if !context.personal.interests.isEmpty {
            formatted += "**兴趣**: \(context.personal.interests.joined(separator: ", "))\n"
        }

        formatted += "\n"

        // 当前关注
        if !context.focus.isEmpty {
            formatted += "**当前关注**:\n"
            for focus in context.focus {
                formatted += "- \(focus)\n"
            }
            formatted += "\n"
        }

        // 偏好设置
        if !context.preferences.isEmpty {
            formatted += "**偏好设置**:\n"
            for (key, value) in context.preferences.sorted(by: { $0.key < $1.key }) {
                formatted += "- \(key): \(value)\n"
            }
            formatted += "\n"
        }

        return formatted
    }

    /// 格式化事实
    private func formatFacts(_ facts: [Fact]) -> String {
        var formatted = "## 相关事实\n\n"

        // 按类别分组
        let groupedFacts = Dictionary(grouping: facts) { $0.category }

        for category in FactCategory.allCases {
            guard let categoryFacts = groupedFacts[category], !categoryFacts.isEmpty else {
                continue
            }

            formatted += "**\(category.rawValue)**:\n"
            for fact in categoryFacts.sorted(by: { $0.confidence > $1.confidence }) {
                let confidencePercent = Int(fact.confidence * 100)
                formatted += "- \(fact.content) (\(confidencePercent)%)\n"
            }
            formatted += "\n"
        }

        return formatted
    }

    /// 格式化历史
    private func formatHistory(_ history: [HistoryItem]) -> String {
        var formatted = "## 相关历史\n\n"

        for item in history.sorted(by: { $0.timestamp > $1.timestamp }) {
            let dateStr = formatDate(item.timestamp)
            formatted += "- [\(dateStr)] \(item.summary)\n"
            if !item.keywords.isEmpty {
                formatted += "  标签: \(item.keywords.joined(separator: ", "))\n"
            }
        }
        formatted += "\n"

        return formatted
    }

    /// 格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Token Management

    /// 截断到令牌限制
    private func truncateToTokenLimit(_ text: String) -> String {
        // 简单的令牌估算：1 token ≈ 4 字符（中文）或 1 单词（英文）
        let estimatedTokens = estimateTokens(text)

        if estimatedTokens <= maxTokens {
            return text
        }

        // 需要截断
        let ratio = Double(maxTokens) / Double(estimatedTokens)
        let targetLength = Int(Double(text.count) * ratio * 0.9) // 留 10% 余量

        let truncated = String(text.prefix(targetLength))
        return truncated + "\n\n[... 内容已截断以适应令牌限制 ...]"
    }

    /// 估算令牌数
    private func estimateTokens(_ text: String) -> Int {
        // 简单估算：
        // - 中文字符: 1 字符 ≈ 1 token
        // - 英文单词: 1 单词 ≈ 1 token
        // - 标点符号: 忽略

        let chineseCharCount = text.filter { char in
            let scalar = char.unicodeScalars.first!
            return scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
        }.count

        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let englishWordCount = words.count

        return chineseCharCount + englishWordCount
    }

    // MARK: - Advanced Injection

    /// 智能注入（根据任务类型选择记忆）
    func smartInject(_ memory: Memory, for task: String, taskType: DecomposedTaskType) -> String {
        var injectedContext = "# 记忆上下文\n\n"

        // 根据任务类型选择相关记忆
        switch taskType {
        case .development:
            injectedContext += injectForDevelopment(memory, task: task)
        case .testing:
            injectedContext += injectForTesting(memory, task: task)
        case .bugfix:
            injectedContext += injectForBugFix(memory, task: task)
        case .refactoring:
            injectedContext += injectForRefactoring(memory, task: task)
        case .documentation:
            injectedContext += injectForDocumentation(memory, task: task)
        case .research:
            injectedContext += injectForResearch(memory, task: task)
        case .design:
            injectedContext += injectForDesign(memory, task: task)
        case .deployment:
            injectedContext += injectForDeployment(memory, task: task)
        case .review:
            injectedContext += injectForReview(memory, task: task)
        case .planning:
            injectedContext += formatMemory(selectRelevantMemory(memory, for: task))
        }

        return truncateToTokenLimit(injectedContext)
    }

    /// 为开发任务注入记忆
    private func injectForDevelopment(_ memory: Memory, task: String) -> String {
        var context = ""

        // 技术栈
        if !memory.userContext.work.technologies.isEmpty {
            context += "**技术栈**: \(memory.userContext.work.technologies.joined(separator: ", "))\n\n"
        }

        // 技术相关事实
        let technicalFacts = memory.getFacts(by: .technical)
            .filter { $0.confidence >= 0.8 }
        if !technicalFacts.isEmpty {
            context += formatFacts(technicalFacts)
        }

        // 偏好设置
        if !memory.userContext.preferences.isEmpty {
            context += "**开发偏好**:\n"
            for (key, value) in memory.userContext.preferences {
                context += "- \(key): \(value)\n"
            }
            context += "\n"
        }

        return context
    }

    /// 为测试任务注入记忆
    private func injectForTesting(_ memory: Memory, task: String) -> String {
        var context = ""

        // 工作流相关事实
        let workflowFacts = memory.getFacts(by: .workflow)
        if !workflowFacts.isEmpty {
            context += formatFacts(workflowFacts)
        }

        // 相关历史
        let testingHistory = memory.history.search(query: "测试")
        if !testingHistory.isEmpty {
            context += formatHistory(Array(testingHistory.prefix(3)))
        }

        return context
    }

    /// 为 Bug 修复注入记忆
    private func injectForBugFix(_ memory: Memory, task: String) -> String {
        var context = ""

        // 项目相关事实
        let projectFacts = memory.getFacts(by: .project)
        if !projectFacts.isEmpty {
            context += formatFacts(projectFacts)
        }

        // Bug 相关历史
        let bugHistory = memory.history.search(query: "bug")
        if !bugHistory.isEmpty {
            context += formatHistory(Array(bugHistory.prefix(5)))
        }

        return context
    }

    /// 为重构任务注入记忆
    private func injectForRefactoring(_ memory: Memory, task: String) -> String {
        var context = ""

        // 技术和工作流事实
        let relevantFacts = memory.facts.filter { fact in
            fact.category == .technical || fact.category == .workflow
        }
        if !relevantFacts.isEmpty {
            context += formatFacts(relevantFacts)
        }

        return context
    }

    /// 为文档任务注入记忆
    private func injectForDocumentation(_ memory: Memory, task: String) -> String {
        var context = ""

        // 项目信息
        if !memory.userContext.work.currentProjects.isEmpty {
            context += "**项目**: \(memory.userContext.work.currentProjects.joined(separator: ", "))\n\n"
        }

        // 所有相关事实
        let relevantFacts = memory.searchFacts(query: task)
        if !relevantFacts.isEmpty {
            context += formatFacts(Array(relevantFacts.prefix(15)))
        }

        return context
    }

    /// 为研究任务注入记忆
    private func injectForResearch(_ memory: Memory, task: String) -> String {
        var context = ""

        // 兴趣和关注点
        if !memory.userContext.personal.interests.isEmpty {
            context += "**兴趣**: \(memory.userContext.personal.interests.joined(separator: ", "))\n\n"
        }

        if !memory.userContext.focus.isEmpty {
            context += "**关注点**: \(memory.userContext.focus.joined(separator: ", "))\n\n"
        }

        // 相关历史
        let researchHistory = memory.history.search(query: task)
        if !researchHistory.isEmpty {
            context += formatHistory(Array(researchHistory.prefix(5)))
        }

        return context
    }

    /// 为设计任务注入记忆
    private func injectForDesign(_ memory: Memory, task: String) -> String {
        var context = ""

        // 偏好设置
        if !memory.userContext.preferences.isEmpty {
            context += "**设计偏好**:\n"
            for (key, value) in memory.userContext.preferences {
                context += "- \(key): \(value)\n"
            }
            context += "\n"
        }

        // 相关事实
        let relevantFacts = memory.searchFacts(query: task)
        if !relevantFacts.isEmpty {
            context += formatFacts(Array(relevantFacts.prefix(10)))
        }

        return context
    }

    /// 为部署任务注入记忆
    private func injectForDeployment(_ memory: Memory, task: String) -> String {
        var context = ""

        // 工作流事实
        let workflowFacts = memory.getFacts(by: .workflow)
        if !workflowFacts.isEmpty {
            context += formatFacts(workflowFacts)
        }

        // 部署相关历史
        let deployHistory = memory.history.search(query: "部署")
        if !deployHistory.isEmpty {
            context += formatHistory(Array(deployHistory.prefix(3)))
        }

        return context
    }

    /// 为审查任务注入记忆
    private func injectForReview(_ memory: Memory, task: String) -> String {
        var context = ""

        // 技术和偏好事实
        let relevantFacts = memory.facts.filter { fact in
            fact.category == .technical || fact.category == .preference
        }
        if !relevantFacts.isEmpty {
            context += formatFacts(relevantFacts)
        }

        return context
    }
}

// MARK: - Memory Injection Strategy

/// 记忆注入策略
enum MemoryInjectionStrategy {
    case minimal        // 最小注入，只包含最相关的信息
    case balanced       // 平衡注入，默认策略
    case comprehensive  // 全面注入，包含所有相关信息

    var maxTokens: Int {
        switch self {
        case .minimal: return 500
        case .balanced: return 2000
        case .comprehensive: return 4000
        }
    }

    var relevanceThreshold: Double {
        switch self {
        case .minimal: return 0.8
        case .balanced: return 0.6
        case .comprehensive: return 0.4
        }
    }
}

// MARK: - Memory Injector Extensions

extension MemoryInjector {
    /// 使用策略注入记忆
    func injectWithStrategy(
        _ memory: Memory,
        into context: String,
        strategy: MemoryInjectionStrategy
    ) -> String {
        let injector = MemoryInjector(
            maxTokens: strategy.maxTokens,
            relevanceThreshold: strategy.relevanceThreshold
        )
        return injector.injectMemory(memory, into: context)
    }

    /// 批量注入（为多个任务注入记忆）
    func batchInject(
        _ memory: Memory,
        for tasks: [String]
    ) -> [String: String] {
        var results: [String: String] = [:]

        for task in tasks {
            let relevantMemory = selectRelevantMemory(memory, for: task)
            let injected = formatMemory(relevantMemory)
            results[task] = injected
        }

        return results
    }

    /// 差异注入（只注入与上次不同的记忆）
    func differentialInject(
        _ currentMemory: Memory,
        previous: Memory,
        into context: String
    ) -> String {
        var injectedContext = "# 新增记忆\n\n"

        // 找出新增的事实
        let newFacts = currentMemory.facts.filter { currentFact in
            !previous.facts.contains { $0.id == currentFact.id }
        }

        if !newFacts.isEmpty {
            injectedContext += "## 新增事实\n\n"
            injectedContext += formatFacts(newFacts)
        }

        // 找出新增的历史
        let newHistory = currentMemory.history.recent.filter { currentItem in
            !previous.history.allItems().contains { $0.id == currentItem.id }
        }

        if !newHistory.isEmpty {
            injectedContext += "## 新增历史\n\n"
            injectedContext += formatHistory(newHistory)
        }

        // 添加原始上下文
        injectedContext += "\n---\n\n"
        injectedContext += context

        return truncateToTokenLimit(injectedContext)
    }

    /// 生成记忆摘要
    func generateMemorySummary(_ memory: Memory) -> String {
        let stats = memory.getStatistics()

        var summary = "# 记忆摘要\n\n"
        summary += "- 总事实数: \(stats.totalFacts)\n"
        summary += "- 平均置信度: \(String(format: "%.0f%%", stats.averageConfidence * 100))\n"
        summary += "- 历史记录数: \(stats.historyItemCount)\n"
        summary += "- 最后更新: \(formatDate(stats.lastUpdated))\n\n"

        if !memory.userContext.work.currentProjects.isEmpty {
            summary += "**当前项目**: \(memory.userContext.work.currentProjects.joined(separator: ", "))\n"
        }

        if !memory.userContext.focus.isEmpty {
            summary += "**当前关注**: \(memory.userContext.focus.joined(separator: ", "))\n"
        }

        return summary
    }
}
