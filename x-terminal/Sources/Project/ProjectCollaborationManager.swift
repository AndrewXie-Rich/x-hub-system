//
//  ProjectCollaborationManager.swift
//  XTerminal
//
//

import Foundation

/// 项目协作管理器
/// 负责管理项目间的知识共享和协作
@MainActor
class ProjectCollaborationManager: ObservableObject {
    // MARK: - Published Properties

    @Published var collaborations: [Collaboration] = []
    @Published var knowledgeCache: [UUID: ProjectKnowledge] = [:]

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    /// 跨项目知识查询
    func queryKnowledge(
        from sourceProject: ProjectModel,
        query: String,
        for targetProject: ProjectModel
    ) async -> CollaborationResult {
        // 1. 分析查询意图
        let intent = await analyzeIntent(query)

        // 2. 从源项目提取相关知识
        let knowledge = await extractKnowledge(from: sourceProject, matching: intent)

        // 3. 格式化为目标项目可用的形式
        let formatted = formatForProject(knowledge, targetProject)

        // 4. 注入到目标项目上下文
        await injectKnowledge(formatted, into: targetProject)

        // 5. 记录协作关系
        recordCollaboration(from: sourceProject, to: targetProject, knowledge: formatted)

        return CollaborationResult(
            knowledge: formatted,
            tokensUsed: formatted.tokenCount,
            success: true
        )
    }

    /// 分析查询意图
    func analyzeIntent(_ query: String) async -> QueryIntent {
        let lowercased = query.lowercased()

        if lowercased.contains("api") || lowercased.contains("接口") || lowercased.contains("endpoint") {
            return QueryIntent(type: .apiDefinition, keywords: extractKeywords(query))
        } else if lowercased.contains("model") || lowercased.contains("模型") || lowercased.contains("数据结构") {
            return QueryIntent(type: .dataModel, keywords: extractKeywords(query))
        } else if lowercased.contains("pattern") || lowercased.contains("模式") || lowercased.contains("实现") {
            return QueryIntent(type: .codePattern, keywords: extractKeywords(query))
        } else if lowercased.contains("config") || lowercased.contains("配置") || lowercased.contains("设置") {
            return QueryIntent(type: .configuration, keywords: extractKeywords(query))
        } else {
            return QueryIntent(type: .general, keywords: extractKeywords(query))
        }
    }

    /// 提取关键词
    func extractKeywords(_ query: String) -> [String] {
        // 简化实现：分词并过滤停用词
        let words = query.components(separatedBy: .whitespacesAndNewlines)
        let stopWords = ["的", "是", "在", "有", "和", "了", "a", "the", "is", "in", "and"]
        return words.filter { !stopWords.contains($0.lowercased()) && $0.count > 1 }
    }

    /// 从项目提取知识
    func extractKnowledge(
        from project: ProjectModel,
        matching intent: QueryIntent
    ) async -> ProjectKnowledge {
        var knowledge = ProjectKnowledge()

        // 检查缓存
        if let cached = knowledgeCache[project.id] {
            knowledge = cached
        } else {
            // 从项目的共享知识中提取
            for item in project.sharedKnowledge {
                switch item.type {
                case .api:
                    if intent.type == .apiDefinition || intent.type == .general {
                        knowledge.apis.append(APIDefinition(
                            method: "GET",
                            path: "/api/\(item.title)",
                            parameters: [],
                            response: ResponseType(type: "Object", description: item.content),
                            description: item.content
                        ))
                    }

                case .dataModel:
                    if intent.type == .dataModel || intent.type == .general {
                        knowledge.models.append(DataModel(
                            name: item.title,
                            fields: [],
                            description: item.content
                        ))
                    }

                case .codePattern:
                    if intent.type == .codePattern || intent.type == .general {
                        knowledge.patterns.append(CodePattern(
                            name: item.title,
                            code: item.content,
                            description: item.content
                        ))
                    }

                case .configuration:
                    if intent.type == .configuration || intent.type == .general {
                        knowledge.configs.append(Configuration(
                            key: item.title,
                            value: item.content,
                            description: item.content
                        ))
                    }

                default:
                    break
                }
            }

            // 缓存知识
            knowledgeCache[project.id] = knowledge
        }

        // 根据关键词过滤
        return filterKnowledge(knowledge, keywords: intent.keywords)
    }

    /// 过滤知识
    func filterKnowledge(_ knowledge: ProjectKnowledge, keywords: [String]) -> ProjectKnowledge {
        guard !keywords.isEmpty else { return knowledge }

        var filtered = ProjectKnowledge()

        // 过滤 APIs
        filtered.apis = knowledge.apis.filter { api in
            keywords.contains { keyword in
                api.path.lowercased().contains(keyword.lowercased()) ||
                api.description.lowercased().contains(keyword.lowercased())
            }
        }

        // 过滤 Models
        filtered.models = knowledge.models.filter { model in
            keywords.contains { keyword in
                model.name.lowercased().contains(keyword.lowercased()) ||
                model.description.lowercased().contains(keyword.lowercased())
            }
        }

        // 过滤 Patterns
        filtered.patterns = knowledge.patterns.filter { pattern in
            keywords.contains { keyword in
                pattern.name.lowercased().contains(keyword.lowercased()) ||
                pattern.description.lowercased().contains(keyword.lowercased())
            }
        }

        // 过滤 Configs
        filtered.configs = knowledge.configs.filter { config in
            keywords.contains { keyword in
                config.key.lowercased().contains(keyword.lowercased()) ||
                config.description.lowercased().contains(keyword.lowercased())
            }
        }

        return filtered
    }

    /// 格式化知识
    func formatForProject(_ knowledge: ProjectKnowledge, _ project: ProjectModel) -> ProjectKnowledge {
        // 简化实现：直接返回
        // 实际可以根据目标项目的语言、框架等进行格式转换
        return knowledge
    }

    /// 注入知识到项目
    func injectKnowledge(_ knowledge: ProjectKnowledge, into project: ProjectModel) async {
        // 将知识转换为消息注入到项目的会话中
        var contextMessage = "📚 从其他项目获取的知识:\n\n"

        if !knowledge.apis.isEmpty {
            contextMessage += "## API 接口 (\(knowledge.apis.count) 个)\n\n"
            for api in knowledge.apis {
                contextMessage += "- \(api.method) \(api.path)\n"
                contextMessage += "  描述: \(api.description)\n\n"
            }
        }

        if !knowledge.models.isEmpty {
            contextMessage += "## 数据模型 (\(knowledge.models.count) 个)\n\n"
            for model in knowledge.models {
                contextMessage += "- \(model.name)\n"
                contextMessage += "  描述: \(model.description)\n\n"
            }
        }

        if !knowledge.patterns.isEmpty {
            contextMessage += "## 代码模式 (\(knowledge.patterns.count) 个)\n\n"
            for pattern in knowledge.patterns {
                contextMessage += "- \(pattern.name)\n"
                contextMessage += "  描述: \(pattern.description)\n\n"
            }
        }

        if !knowledge.configs.isEmpty {
            contextMessage += "## 配置信息 (\(knowledge.configs.count) 个)\n\n"
            for config in knowledge.configs {
                contextMessage += "- \(config.key): \(config.value)\n"
                contextMessage += "  描述: \(config.description)\n\n"
            }
        }

        // 注入到项目会话
        // 实际实现需要调用 ChatSessionModel 的方法
        print("Injecting knowledge into project \(project.name):")
        print(contextMessage)
    }

    /// 记录协作关系
    func recordCollaboration(
        from sourceProject: ProjectModel,
        to targetProject: ProjectModel,
        knowledge: ProjectKnowledge
    ) {
        let collaboration = Collaboration(
            id: UUID(),
            sourceProjectId: sourceProject.id,
            targetProjectId: targetProject.id,
            knowledge: knowledge,
            timestamp: Date()
        )

        collaborations.append(collaboration)

        // 更新项目的协作关系
        sourceProject.startCollaboration(with: targetProject.id)
        targetProject.startCollaboration(with: sourceProject.id)
    }

    /// 获取项目的协作历史
    func getCollaborationHistory(for projectId: UUID) -> [Collaboration] {
        return collaborations.filter {
            $0.sourceProjectId == projectId || $0.targetProjectId == projectId
        }
    }

    /// 清除缓存
    func clearCache() {
        knowledgeCache.removeAll()
    }

    /// 清除缓存（指定项目）
    func clearCache(for projectId: UUID) {
        knowledgeCache.removeValue(forKey: projectId)
    }
}

// MARK: - Supporting Types

/// 查询意图
struct QueryIntent {
    let type: QueryType
    let keywords: [String]
}

/// 查询类型
enum QueryType {
    case apiDefinition
    case dataModel
    case codePattern
    case configuration
    case general
}

/// 项目知识
struct ProjectKnowledge {
    var apis: [APIDefinition] = []
    var models: [DataModel] = []
    var patterns: [CodePattern] = []
    var configs: [Configuration] = []

    var isEmpty: Bool {
        apis.isEmpty && models.isEmpty && patterns.isEmpty && configs.isEmpty
    }

    var tokenCount: Int {
        apis.reduce(0) { $0 + $1.tokenCount } +
        models.reduce(0) { $0 + $1.tokenCount } +
        patterns.reduce(0) { $0 + $1.tokenCount } +
        configs.reduce(0) { $0 + $1.tokenCount }
    }
}

/// API 定义
struct APIDefinition {
    let method: String
    let path: String
    let parameters: [Parameter]
    let response: ResponseType
    let description: String

    var tokenCount: Int {
        (method + path + description).count / 4
    }
}

/// 参数
struct Parameter {
    let name: String
    let type: String
    let required: Bool
    let description: String
}

/// 响应类型
struct ResponseType {
    let type: String
    let description: String
}

/// 数据模型
struct DataModel {
    let name: String
    let fields: [Field]
    let description: String

    var tokenCount: Int {
        (name + description).count / 4 + fields.reduce(0) { $0 + ($1.name.count + $1.type.count) / 4 }
    }
}

/// 字段
struct Field {
    let name: String
    let type: String
    let optional: Bool
    let description: String
}

/// 代码模式
struct CodePattern {
    let name: String
    let code: String
    let description: String

    var tokenCount: Int {
        (name + code + description).count / 4
    }
}

/// 配置
struct Configuration {
    let key: String
    let value: String
    let description: String

    var tokenCount: Int {
        (key + value + description).count / 4
    }
}

/// 协作结果
struct CollaborationResult {
    let knowledge: ProjectKnowledge
    let tokensUsed: Int
    let success: Bool
}

/// 协作记录
struct Collaboration: Identifiable {
    let id: UUID
    let sourceProjectId: UUID
    let targetProjectId: UUID
    let knowledge: ProjectKnowledge
    let timestamp: Date
}
