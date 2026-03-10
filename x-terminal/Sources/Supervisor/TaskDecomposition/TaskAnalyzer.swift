import Foundation

/// 任务分析器 - 负责分析任务描述并提取关键信息
@MainActor
class TaskAnalyzer {

    // MARK: - 关键词字典

    /// 任务类型关键词映射
    private let typeKeywords: [DecomposedTaskType: [String]] = [
        .development: ["开发", "实现", "编写", "创建", "构建", "添加", "develop", "implement", "write", "create", "build", "add", "code"],
        .testing: ["测试", "验证", "检查", "test", "verify", "check", "validate", "qa"],
        .documentation: ["文档", "说明", "注释", "document", "doc", "comment", "readme", "guide"],
        .research: ["研究", "调研", "分析", "探索", "research", "investigate", "analyze", "explore", "study"],
        .bugfix: ["修复", "修改", "解决", "bug", "fix", "repair", "resolve", "issue", "problem"],
        .refactoring: ["重构", "优化", "改进", "refactor", "optimize", "improve", "restructure"],
        .deployment: ["部署", "发布", "上线", "deploy", "release", "publish", "launch"],
        .review: ["审查", "评审", "检视", "review", "inspect", "examine"],
        .design: ["设计", "规划", "架构", "design", "plan", "architecture", "ui", "ux"],
        .planning: ["计划", "规划", "安排", "plan", "schedule", "organize"]
    ]

    /// 复杂度关键词
    private let complexityIndicators: [String: DecomposedTaskComplexity] = [
        "简单": .simple,
        "容易": .simple,
        "快速": .trivial,
        "小": .simple,
        "simple": .simple,
        "easy": .simple,
        "quick": .trivial,
        "small": .simple,

        "中等": .moderate,
        "一般": .moderate,
        "moderate": .moderate,
        "medium": .moderate,
        "normal": .moderate,

        "复杂": .complex,
        "困难": .complex,
        "大": .complex,
        "complex": .complex,
        "difficult": .complex,
        "large": .complex,
        "hard": .complex,

        "非常复杂": .veryComplex,
        "极其困难": .veryComplex,
        "巨大": .veryComplex,
        "very complex": .veryComplex,
        "extremely": .veryComplex,
        "huge": .veryComplex
    ]

    /// 风险关键词
    private let riskIndicators: [String: RiskLevel] = [
        "关键": .critical,
        "核心": .high,
        "重要": .high,
        "紧急": .high,
        "critical": .critical,
        "important": .high,
        "urgent": .high,
        "core": .high,

        "风险": .medium,
        "注意": .medium,
        "小心": .medium,
        "risk": .medium,
        "careful": .medium,
        "caution": .medium
    ]

    /// 动词列表
    private let commonVerbs = [
        "开发", "实现", "编写", "创建", "构建", "添加", "修复", "修改", "解决",
        "测试", "验证", "检查", "优化", "改进", "重构", "部署", "发布", "设计",
        "develop", "implement", "write", "create", "build", "add", "fix", "modify",
        "solve", "test", "verify", "check", "optimize", "improve", "refactor",
        "deploy", "release", "design", "update", "remove", "delete", "integrate"
    ]

    // MARK: - 公共方法

    /// 分析任务描述
    func analyze(_ description: String) async -> TaskAnalysis {
        let normalized = description.lowercased()

        // 1. 提取关键词
        let keywords = extractKeywords(normalized)

        // 2. 识别动词
        let verbs = identifyVerbs(normalized)

        // 3. 识别对象
        let objects = identifyObjects(normalized, verbs: verbs)

        // 4. 识别约束条件
        let constraints = identifyConstraints(normalized)

        // 5. 识别任务类型
        let type = identifyDecomposedTaskType(keywords, verbs: verbs)

        // 6. 评估复杂度
        let complexity = assessComplexity(description, keywords: keywords, verbs: verbs)

        // 7. 估算工作量
        let effort = estimateEffort(complexity, description: description)

        // 8. 识别所需技能
        let skills = identifyRequiredSkills(type, keywords: keywords)

        // 9. 评估风险等级
        let risk = assessRisk(keywords, complexity: complexity)

        // 10. 建议子任务
        let subtasks = suggestSubtasks(description, type: type, complexity: complexity)

        // 11. 识别潜在依赖
        let dependencies = identifyPotentialDependencies(description, subtasks: subtasks)

        return TaskAnalysis(
            originalDescription: description,
            keywords: keywords,
            verbs: verbs,
            objects: objects,
            constraints: constraints,
            type: type,
            complexity: complexity,
            estimatedEffort: effort,
            requiredSkills: skills,
            riskLevel: risk,
            suggestedSubtasks: subtasks,
            potentialDependencies: dependencies
        )
    }

    // MARK: - 私有方法

    /// 提取关键词
    private func extractKeywords(_ text: String) -> [String] {
        // 分词
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        // 过滤停用词
        let stopWords = Set(["的", "了", "和", "与", "或", "在", "是", "有", "为", "以",
                            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for"])

        let filtered = words.filter { word in
            word.count > 1 && !stopWords.contains(word)
        }

        // 去重并排序
        return Array(Set(filtered)).sorted()
    }

    /// 识别动词
    private func identifyVerbs(_ text: String) -> [String] {
        return commonVerbs.filter { verb in
            text.contains(verb)
        }
    }

    /// 识别对象
    private func identifyObjects(_ text: String, verbs: [String]) -> [String] {
        var objects: [String] = []

        // 查找文件扩展名
        let fileExtensions = [".swift", ".js", ".ts", ".py", ".java", ".go", ".rs", ".cpp", ".h"]
        for ext in fileExtensions {
            if text.contains(ext) {
                objects.append("file" + ext)
            }
        }

        // 查找常见对象
        let commonObjects = ["api", "ui", "database", "model", "view", "controller",
                           "service", "component", "module", "function", "class",
                           "接口", "界面", "数据库", "模型", "视图", "控制器",
                           "服务", "组件", "模块", "函数", "类"]

        for obj in commonObjects {
            if text.contains(obj) {
                objects.append(obj)
            }
        }

        return Array(Set(objects))
    }

    /// 识别约束条件
    private func identifyConstraints(_ text: String) -> [String] {
        var constraints: [String] = []

        // 时间约束
        let timePatterns = ["今天", "明天", "本周", "下周", "紧急", "尽快",
                          "today", "tomorrow", "this week", "next week", "urgent", "asap"]
        for pattern in timePatterns {
            if text.contains(pattern) {
                constraints.append("时间约束: \(pattern)")
            }
        }

        // 质量约束
        let qualityPatterns = ["高质量", "完美", "优化", "性能", "安全",
                             "high quality", "perfect", "optimized", "performance", "secure"]
        for pattern in qualityPatterns {
            if text.contains(pattern) {
                constraints.append("质量约束: \(pattern)")
            }
        }

        // 范围约束
        let scopePatterns = ["只", "仅", "不包括", "排除", "限制",
                           "only", "just", "exclude", "limit"]
        for pattern in scopePatterns {
            if text.contains(pattern) {
                constraints.append("范围约束: \(pattern)")
            }
        }

        return constraints
    }

    /// 识别任务类型
    private func identifyDecomposedTaskType(_ keywords: [String], verbs: [String]) -> DecomposedTaskType {
        var scores: [DecomposedTaskType: Int] = [:]

        // 基于关键词评分
        for (type, typeKeywords) in typeKeywords {
            let matchCount = keywords.filter { keyword in
                typeKeywords.contains { $0.contains(keyword) || keyword.contains($0) }
            }.count
            scores[type] = matchCount
        }

        // 基于动词评分
        for verb in verbs {
            for (type, typeKeywords) in typeKeywords {
                if typeKeywords.contains(verb) {
                    scores[type, default: 0] += 2 // 动词权重更高
                }
            }
        }

        // 返回得分最高的类型
        if let bestType = scores.max(by: { $0.value < $1.value })?.key, scores[bestType]! > 0 {
            return bestType
        }

        return .development // 默认类型
    }

    /// 评估复杂度
    private func assessComplexity(_ description: String, keywords: [String], verbs: [String]) -> DecomposedTaskComplexity {
        var score = 0
        let normalized = description.lowercased()

        // 1. 检查显式复杂度指示
        for (indicator, complexity) in complexityIndicators {
            if normalized.contains(indicator) {
                return complexity
            }
        }

        // 2. 基于描述长度
        let wordCount = description.components(separatedBy: .whitespacesAndNewlines).count
        score += wordCount / 10

        // 3. 基于关键词数量
        score += keywords.count

        // 4. 基于动词数量（多个动作通常意味着更复杂）
        score += verbs.count * 2

        // 5. 检查复杂性指标
        let complexityMarkers = ["多个", "所有", "整个", "完整", "系统", "架构",
                               "multiple", "all", "entire", "complete", "system", "architecture"]
        for marker in complexityMarkers {
            if normalized.contains(marker) {
                score += 3
            }
        }

        // 6. 检查技术难度指标
        let technicalMarkers = ["算法", "优化", "性能", "并发", "分布式", "安全",
                              "algorithm", "optimization", "performance", "concurrent", "distributed", "security"]
        for marker in technicalMarkers {
            if normalized.contains(marker) {
                score += 2
            }
        }

        // 根据分数返回复杂度
        switch score {
        case 0...2:
            return .trivial
        case 3...5:
            return .simple
        case 6...10:
            return .moderate
        case 11...15:
            return .complex
        default:
            return .veryComplex
        }
    }

    /// 估算工作量
    private func estimateEffort(_ complexity: DecomposedTaskComplexity, description: String) -> TimeInterval {
        var baseEffort = complexity.estimatedHours

        // 根据描述调整
        let normalized = description.lowercased()

        // 增加工作量的因素
        if normalized.contains("完整") || normalized.contains("complete") {
            baseEffort *= 1.5
        }
        if normalized.contains("测试") || normalized.contains("test") {
            baseEffort *= 1.2
        }
        if normalized.contains("文档") || normalized.contains("document") {
            baseEffort *= 1.1
        }

        // 减少工作量的因素
        if normalized.contains("简单") || normalized.contains("simple") {
            baseEffort *= 0.8
        }
        if normalized.contains("快速") || normalized.contains("quick") {
            baseEffort *= 0.7
        }

        return baseEffort
    }

    /// 识别所需技能
    private func identifyRequiredSkills(_ type: DecomposedTaskType, keywords: [String]) -> [String] {
        var skills: Set<String> = []

        // 基于任务类型的基础技能
        switch type {
        case .development:
            skills.insert("编程")
        case .testing:
            skills.insert("测试")
        case .documentation:
            skills.insert("文档编写")
        case .research:
            skills.insert("研究分析")
        case .bugfix:
            skills.insert("调试")
        case .refactoring:
            skills.insert("代码重构")
        case .deployment:
            skills.insert("部署运维")
        case .review:
            skills.insert("代码审查")
        case .design:
            skills.insert("设计")
        case .planning:
            skills.insert("项目管理")
        }

        // 基于关键词的技术栈
        let techStack: [String: String] = [
            "swift": "Swift",
            "swiftui": "SwiftUI",
            "python": "Python",
            "javascript": "JavaScript",
            "typescript": "TypeScript",
            "react": "React",
            "vue": "Vue",
            "api": "API开发",
            "database": "数据库",
            "ui": "UI设计",
            "backend": "后端开发",
            "frontend": "前端开发"
        ]

        for keyword in keywords {
            for (key, skill) in techStack {
                if keyword.contains(key) {
                    skills.insert(skill)
                }
            }
        }

        return Array(skills).sorted()
    }

    /// 评估风险等级
    private func assessRisk(_ keywords: [String], complexity: DecomposedTaskComplexity) -> RiskLevel {
        // 检查显式风险指示
        for keyword in keywords {
            for (indicator, risk) in riskIndicators {
                if keyword.contains(indicator) {
                    return risk
                }
            }
        }

        // 基于复杂度
        switch complexity {
        case .trivial, .simple:
            return .low
        case .moderate:
            return .medium
        case .complex:
            return .high
        case .veryComplex:
            return .critical
        }
    }

    /// 建议子任务
    private func suggestSubtasks(_ description: String, type: DecomposedTaskType, complexity: DecomposedTaskComplexity) -> [String] {
        var subtasks: [String] = []

        // 如果复杂度低，不需要拆分
        if complexity < .complex {
            return []
        }

        let normalized = description.lowercased()

        // 基于任务类型的标准子任务
        switch type {
        case .development:
            subtasks.append("设计方案")
            subtasks.append("实现核心功能")
            if normalized.contains("测试") || normalized.contains("test") {
                subtasks.append("编写测试")
            }
            if normalized.contains("文档") || normalized.contains("document") {
                subtasks.append("编写文档")
            }

        case .testing:
            subtasks.append("编写测试用例")
            subtasks.append("执行测试")
            subtasks.append("修复发现的问题")

        case .bugfix:
            subtasks.append("重现问题")
            subtasks.append("定位根本原因")
            subtasks.append("实现修复")
            subtasks.append("验证修复")

        case .refactoring:
            subtasks.append("分析现有代码")
            subtasks.append("设计重构方案")
            subtasks.append("实施重构")
            subtasks.append("验证功能完整性")

        default:
            // 通用拆分
            if complexity >= .complex {
                subtasks.append("需求分析")
                subtasks.append("方案设计")
                subtasks.append("实施开发")
                subtasks.append("测试验证")
            }
        }

        return subtasks
    }

    /// 识别潜在依赖
    private func identifyPotentialDependencies(_ description: String, subtasks: [String]) -> [String] {
        var dependencies: [String] = []
        let normalized = description.lowercased()

        // 检查依赖关键词
        let dependencyPatterns = [
            "依赖", "需要", "基于", "在...之后", "完成...后",
            "depend", "require", "need", "based on", "after"
        ]

        for pattern in dependencyPatterns {
            if normalized.contains(pattern) {
                dependencies.append("检测到依赖关键词: \(pattern)")
            }
        }

        // 基于子任务的隐式依赖
        if subtasks.contains("设计方案") && subtasks.contains("实现核心功能") {
            dependencies.append("实现核心功能 依赖于 设计方案")
        }
        if subtasks.contains("编写测试") {
            dependencies.append("编写测试 依赖于 实现完成")
        }

        return dependencies
    }
}
