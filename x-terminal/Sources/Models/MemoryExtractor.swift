import Foundation

// MARK: - Memory Extractor

/// LLM 驱动的记忆提取器
@MainActor
class MemoryExtractor {
    // MARK: - Properties

    private let llmRouter: LLMRouter
    private let extractionPrompt: String

    // MARK: - Initialization

    init(llmRouter: LLMRouter) {
        self.llmRouter = llmRouter
        self.extractionPrompt = Self.buildExtractionPrompt()
    }

    // MARK: - Extraction Methods

    /// 从对话中提取记忆
    func extractFromConversation(_ messages: [AXChatMessage]) async -> ExtractedMemory {
        // 构建对话上下文
        let conversationText = buildConversationText(from: messages)

        // 提取事实
        let facts = await extractFacts(conversationText)

        // 提取上下文更新
        let contextUpdates = await extractContextUpdates(conversationText)

        // 提取历史项
        let historyItems = await extractHistoryItems(conversationText)

        return ExtractedMemory(
            facts: facts,
            contextUpdates: contextUpdates,
            historyItems: historyItems
        )
    }

    /// 提取事实
    func extractFacts(_ text: String) async -> [Fact] {
        let prompt = """
        请从以下对话中提取关键事实。每个事实应该是：
        1. 明确且可验证的信息
        2. 对未来对话有参考价值
        3. 不是临时性的信息

        对话内容：
        \(text)

        请以 JSON 数组格式返回事实，每个事实包含：
        - content: 事实内容
        - confidence: 置信度 (0.0-1.0)
        - category: 类别 (general/technical/personal/project/preference/workflow)
        - tags: 标签数组

        示例：
        [
          {
            "content": "用户偏好使用 Swift 进行 iOS 开发",
            "confidence": 0.9,
            "category": "preference",
            "tags": ["Swift", "iOS", "开发"]
          }
        ]
        """

        do {
            let response = try await sendMessage(prompt)
            return try parseFacts(from: response)
        } catch {
            print("提取事实失败: \(error)")
            return []
        }
    }

    /// 评估置信度
    func assessConfidence(_ fact: Fact, context: [AXChatMessage]) async -> Double {
        let conversationText = buildConversationText(from: context)

        let prompt = """
        请评估以下事实的置信度（0.0-1.0）：

        事实：\(fact.content)

        对话上下文：
        \(conversationText)

        评估标准：
        - 1.0: 明确陈述的事实
        - 0.8-0.9: 强烈暗示的信息
        - 0.6-0.7: 推断的信息
        - 0.4-0.5: 不确定的信息
        - 0.0-0.3: 可能错误的信息

        请只返回一个数字（0.0-1.0）。
        """

        do {
            let response = try await sendMessage(prompt)
            if let confidence = Double(response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)) {
                return max(0.0, min(1.0, confidence))
            }
        } catch {
            print("评估置信度失败: \(error)")
        }

        return fact.confidence
    }

    /// 更新上下文
    func updateContext(_ context: UserContext, from messages: [AXChatMessage]) async -> UserContext {
        var updatedContext = context
        let conversationText = buildConversationText(from: messages)

        let prompt = """
        请从以下对话中提取用户上下文信息：

        对话内容：
        \(conversationText)

        请以 JSON 格式返回上下文更新，包含：
        - work: { currentProjects: [], technologies: [], roles: [], goals: [] }
        - personal: { name: "", timezone: "", language: "", interests: [] }
        - focus: []
        - preferences: {}

        只返回在对话中明确提到的信息，未提到的字段使用空值。
        """

        do {
            let response = try await sendMessage(prompt)
            if let updates = try? parseContextUpdates(from: response) {
                updatedContext = mergeContextUpdates(context, updates: updates)
            }
        } catch {
            print("更新上下文失败: \(error)")
        }

        return updatedContext
    }

    // MARK: - Private Extraction Methods

    /// 使用当前路由发送单轮 prompt，并拼接流式输出。
    private func sendMessage(_ prompt: String, role: AXRole = .advisor) async throws -> String {
        let provider = llmRouter.provider(for: role)
        let req = LLMRequest(
            role: role,
            messages: [LLMMessage(role: "user", content: prompt)],
            maxTokens: 1200,
            temperature: 0.2,
            topP: 0.95,
            taskType: llmRouter.taskType(for: role),
            preferredModelId: llmRouter.preferredModelIdForHub(for: role),
            projectId: nil,
            sessionId: nil
        )

        var out = ""
        for try await ev in provider.stream(req) {
            switch ev {
            case .delta(let t):
                out += t
            case .done(let ok, let reason, _):
                if !ok {
                    throw NSError(
                        domain: "xterminal.memory.extractor",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "LLM request failed: \(reason)"]
                    )
                }
            }
        }
        return out
    }

    /// 提取上下文更新
    private func extractContextUpdates(_ text: String) async -> [String: Any] {
        let prompt = """
        请从以下对话中提取用户上下文更新：

        对话内容：
        \(text)

        请以 JSON 格式返回，包含：
        - currentProjects: 当前项目列表
        - technologies: 使用的技术栈
        - focus: 当前关注点
        - preferences: 用户偏好

        只提取明确提到的信息。
        """

        do {
            let response = try await sendMessage(prompt)
            return try parseContextUpdates(from: response)
        } catch {
            print("提取上下文更新失败: \(error)")
            return [:]
        }
    }

    /// 提取历史项
    private func extractHistoryItems(_ text: String) async -> [HistoryItem] {
        let prompt = """
        请从以下对话中提取重要的历史记录项：

        对话内容：
        \(text)

        请以 JSON 数组格式返回，每项包含：
        - summary: 简短摘要（1-2 句话）
        - keywords: 关键词数组
        - importance: 重要性 (0.0-1.0)

        示例：
        [
          {
            "summary": "用户请求实现用户认证功能",
            "keywords": ["认证", "用户", "功能"],
            "importance": 0.8
          }
        ]
        """

        do {
            let response = try await sendMessage(prompt)
            return try parseHistoryItems(from: response)
        } catch {
            print("提取历史项失败: \(error)")
            return []
        }
    }

    // MARK: - Helper Methods

    /// 构建对话文本
    private func buildConversationText(from messages: [AXChatMessage]) -> String {
        // 只取最近的 10 条消息
        let recentMessages = messages.suffix(10)

        var text = ""
        for message in recentMessages {
            let role = message.role == .user ? "用户" : "助手"
            text += "\(role): \(message.content)\n\n"
        }

        return text
    }

    /// 解析事实
    private func parseFacts(from response: String) throws -> [Fact] {
        // 提取 JSON 部分
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8) else {
            return []
        }

        struct FactJSON: Codable {
            let content: String
            let confidence: Double
            let category: String
            let tags: [String]
        }

        let decoder = JSONDecoder()
        let factJSONs = try decoder.decode([FactJSON].self, from: data)

        return factJSONs.map { factJSON in
            let category = FactCategory(rawValue: factJSON.category) ?? .general
            return Fact(
                content: factJSON.content,
                confidence: factJSON.confidence,
                source: "LLM提取",
                category: category,
                tags: factJSON.tags
            )
        }
    }

    /// 解析上下文更新
    private func parseContextUpdates(from response: String) throws -> [String: Any] {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8) else {
            return [:]
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json ?? [:]
    }

    /// 解析历史项
    private func parseHistoryItems(from response: String) throws -> [HistoryItem] {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8) else {
            return []
        }

        struct HistoryJSON: Codable {
            let summary: String
            let keywords: [String]
            let importance: Double
        }

        let decoder = JSONDecoder()
        let historyJSONs = try decoder.decode([HistoryJSON].self, from: data)

        return historyJSONs.map { historyJSON in
            HistoryItem(
                summary: historyJSON.summary,
                keywords: historyJSON.keywords,
                importance: historyJSON.importance
            )
        }
    }

    /// 提取 JSON 字符串
    private func extractJSON(from text: String) -> String? {
        // 尝试找到 JSON 数组或对象
        if let range = text.range(of: #"\[[\s\S]*\]"#, options: .regularExpression) {
            return String(text[range])
        }
        if let range = text.range(of: #"\{[\s\S]*\}"#, options: .regularExpression) {
            return String(text[range])
        }
        return nil
    }

    /// 合并上下文更新
    private func mergeContextUpdates(_ context: UserContext, updates: [String: Any]) -> UserContext {
        var merged = context

        // 更新工作上下文
        if let currentProjects = updates["currentProjects"] as? [String], !currentProjects.isEmpty {
            merged.work.currentProjects = Array(Set(merged.work.currentProjects + currentProjects))
        }

        if let technologies = updates["technologies"] as? [String], !technologies.isEmpty {
            merged.work.technologies = Array(Set(merged.work.technologies + technologies))
        }

        if let roles = updates["roles"] as? [String], !roles.isEmpty {
            merged.work.roles = Array(Set(merged.work.roles + roles))
        }

        if let goals = updates["goals"] as? [String], !goals.isEmpty {
            merged.work.goals = Array(Set(merged.work.goals + goals))
        }

        // 更新个人上下文
        if let name = updates["name"] as? String, !name.isEmpty {
            merged.personal.name = name
        }

        if let timezone = updates["timezone"] as? String, !timezone.isEmpty {
            merged.personal.timezone = timezone
        }

        if let language = updates["language"] as? String, !language.isEmpty {
            merged.personal.language = language
        }

        if let interests = updates["interests"] as? [String], !interests.isEmpty {
            merged.personal.interests = Array(Set(merged.personal.interests + interests))
        }

        // 更新关注点
        if let focus = updates["focus"] as? [String], !focus.isEmpty {
            merged.focus = focus
        }

        // 更新偏好
        if let preferences = updates["preferences"] as? [String: String] {
            merged.preferences.merge(preferences) { _, new in new }
        }

        return merged
    }

    /// 构建提取提示词
    private static func buildExtractionPrompt() -> String {
        return """
        你是一个专业的记忆提取助手。你的任务是从对话中提取关键信息，包括：

        1. **事实 (Facts)**：明确的、可验证的信息
           - 用户偏好
           - 技术选择
           - 项目信息
           - 工作流程

        2. **上下文 (Context)**：用户的背景信息
           - 当前项目
           - 使用的技术
           - 角色和目标
           - 个人信息

        3. **历史 (History)**：重要的对话记录
           - 关键决策
           - 重要讨论
           - 问题和解决方案

        提取原则：
        - 只提取明确提到的信息
        - 评估信息的置信度
        - 去除临时性信息
        - 保持信息的准确性
        """
    }
}

// MARK: - Extracted Memory

/// 提取的记忆
struct ExtractedMemory {
    let facts: [Fact]
    let contextUpdates: [String: Any]
    let historyItems: [HistoryItem]

    var isEmpty: Bool {
        return facts.isEmpty && contextUpdates.isEmpty && historyItems.isEmpty
    }

    var summary: String {
        var text = "提取结果：\n"
        text += "- 事实: \(facts.count) 个\n"
        text += "- 上下文更新: \(contextUpdates.count) 项\n"
        text += "- 历史记录: \(historyItems.count) 条\n"
        return text
    }
}

// MARK: - Memory Extraction Strategy

/// 记忆提取策略
enum MemoryExtractionStrategy {
    case aggressive     // 积极提取，置信度阈值较低
    case balanced       // 平衡提取，默认策略
    case conservative   // 保守提取，只提取高置信度信息

    var confidenceThreshold: Double {
        switch self {
        case .aggressive: return 0.6
        case .balanced: return 0.7
        case .conservative: return 0.8
        }
    }

    var maxFactsPerExtraction: Int {
        switch self {
        case .aggressive: return 20
        case .balanced: return 10
        case .conservative: return 5
        }
    }
}

// MARK: - Memory Extractor Extensions

extension MemoryExtractor {
    /// 使用策略提取记忆
    func extractWithStrategy(
        _ messages: [AXChatMessage],
        strategy: MemoryExtractionStrategy = .balanced
    ) async -> ExtractedMemory {
        let extracted = await extractFromConversation(messages)

        // 根据策略过滤事实
        let filteredFacts = extracted.facts.filter { fact in
            fact.confidence >= strategy.confidenceThreshold
        }.prefix(strategy.maxFactsPerExtraction)

        return ExtractedMemory(
            facts: Array(filteredFacts),
            contextUpdates: extracted.contextUpdates,
            historyItems: extracted.historyItems
        )
    }

    /// 增量提取（只提取新消息）
    func extractIncremental(
        _ newMessages: [AXChatMessage],
        since lastExtraction: Date
    ) async -> ExtractedMemory {
        // 过滤出新消息
        let recentMessages = newMessages.filter { message in
            Date(timeIntervalSince1970: message.createdAt) > lastExtraction
        }

        guard !recentMessages.isEmpty else {
            return ExtractedMemory(facts: [], contextUpdates: [:], historyItems: [])
        }

        return await extractFromConversation(recentMessages)
    }

    /// 批量提取（处理多个对话）
    func batchExtract(_ conversations: [[AXChatMessage]]) async -> [ExtractedMemory] {
        var results: [ExtractedMemory] = []

        for messages in conversations {
            let extracted = await extractFromConversation(messages)
            results.append(extracted)
        }

        return results
    }

    /// 合并提取结果
    func mergeExtractions(_ extractions: [ExtractedMemory]) -> ExtractedMemory {
        var allFacts: [Fact] = []
        var allContextUpdates: [String: Any] = [:]
        var allHistoryItems: [HistoryItem] = []

        for extraction in extractions {
            allFacts.append(contentsOf: extraction.facts)
            allContextUpdates.merge(extraction.contextUpdates) { _, new in new }
            allHistoryItems.append(contentsOf: extraction.historyItems)
        }

        // 去重事实
        let uniqueFacts = Array(Set(allFacts.map { $0.content })).compactMap { content in
            allFacts.first { $0.content == content }
        }

        return ExtractedMemory(
            facts: uniqueFacts,
            contextUpdates: allContextUpdates,
            historyItems: allHistoryItems
        )
    }
}
