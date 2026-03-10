# Phase 3 实施计划 - 全面补齐短板

**规划日期**: 2026-02-27
**更新日期**: 2026-02-28
**基于**: DeerFlow 对比分析
**优先级**: 高
**预计工作量**: 120-150 小时

---

> 说明（2026-02-28）：本文件保留为“早期 Phase 3 规划基线”。当前执行优先级、排程、验收与门禁以 `x-terminal/work-orders/` 下工单和 `DOC_STATUS_DASHBOARD.md` 为准。

## 🎯 Phase 3 目标

基于与 DeerFlow 的对比分析，Phase 3 将**全面补齐所有短板**：

1. **持久化记忆系统** (30%) - 补齐 AI 能力短板
2. **沙箱执行系统** (25%) - 提升安全性和隔离性
3. **工具生态系统** (25%) - 增强扩展性
4. **技能系统** (15%) - 提升功能丰富度
5. **中间件架构** (5%) - 优化系统架构

这些功能将使 X-Terminal 从 56/75 分提升到 70+/75 分，全面超越 DeerFlow。

---

## 📋 功能清单

### 1. 持久化记忆系统 (30%)

#### 1.1 记忆数据模型
**文件**: `Memory.swift` (预计 200 行)

**数据结构**:
```swift
// 用户上下文
struct UserContext: Codable {
    var work: WorkContext          // 工作相关
    var personal: PersonalContext  // 个人信息
    var focus: [String]            // 当前关注点
}

// 历史记录
struct History: Codable {
    var recent: [HistoryItem]      // 最近 10 条
    var earlier: [HistoryItem]     // 早期 20 条
    var longTerm: [HistoryItem]    // 长期 30 条
}

// 事实库
struct Fact: Codable, Identifiable {
    let id: UUID
    var content: String
    var confidence: Double         // 0.0 - 1.0
    var source: String
    var createdAt: Date
    var lastVerified: Date
}

// 完整记忆
struct Memory: Codable {
    var userContext: UserContext
    var history: History
    var facts: [Fact]              // 最多 100 个，置信度 > 0.7
}
```

**功能**:
- ✅ 结构化记忆存储
- ✅ 置信度评分系统
- ✅ 自动过期和清理
- ✅ JSON 持久化

---

#### 1.2 记忆管理器
**文件**: `MemoryManager.swift` (预计 300 行)

**核心功能**:
```swift
@MainActor
class MemoryManager: ObservableObject {
    // 属性
    @Published var memory: Memory
    private let fileURL: URL
    private var updateQueue: DispatchQueue
    private var pendingUpdates: Set<UUID> = []

    // 初始化
    init(projectId: UUID)

    // 记忆操作
    func loadMemory() async throws
    func saveMemory() async throws

    // 记忆提取
    func extractMemory(from messages: [Message]) async
    func updateFacts(_ newFacts: [Fact]) async
    func addHistory(_ item: HistoryItem) async

    // 记忆查询
    func searchFacts(query: String) -> [Fact]
    func getRelevantContext(for task: String) -> String

    // 记忆维护
    func cleanupExpiredFacts() async
    func consolidateHistory() async
    func updateConfidence(factId: UUID, delta: Double) async
}
```

**实现要点**:
- ✅ 防抖更新机制 (30 秒)
- ✅ 原子文件操作
- ✅ 缓存失效机制
- ✅ 线程安全

---

#### 1.3 LLM 驱动的记忆提取
**文件**: `MemoryExtractor.swift` (预计 250 行)

**核心功能**:
```swift
@MainActor
class MemoryExtractor {
    // LLM 配置
    private let llmRouter: LLMRouter
    private let extractionPrompt: String

    // 提取记忆
    func extractFromConversation(_ messages: [Message]) async -> ExtractedMemory

    // 提取事实
    func extractFacts(_ text: String) async -> [Fact]

    // 评估置信度
    func assessConfidence(_ fact: Fact, context: [Message]) async -> Double

    // 更新上下文
    func updateContext(_ context: UserContext, from messages: [Message]) async -> UserContext
}

struct ExtractedMemory {
    let facts: [Fact]
    let contextUpdates: [String: Any]
    let historyItems: [HistoryItem]
}
```

**提取策略**:
- ✅ 基于 LLM 的智能提取
- ✅ 关键信息识别
- ✅ 置信度自动评估
- ✅ 去重和合并

---

#### 1.4 记忆注入系统
**文件**: `MemoryInjector.swift` (预计 150 行)

**核心功能**:
```swift
@MainActor
class MemoryInjector {
    // 注入记忆到上下文
    func injectMemory(_ memory: Memory, into context: String) -> String

    // 选择相关记忆
    func selectRelevantMemory(_ memory: Memory, for task: String) -> Memory

    // 格式化记忆
    func formatMemory(_ memory: Memory) -> String
}
```

**注入策略**:
- ✅ 相关性过滤
- ✅ 优先级排序
- ✅ 令牌限制控制
- ✅ 格式化输出

---

### 2. 沙箱执行系统 (25%)

#### 2.1 沙箱提供者接口
**文件**: `SandboxProvider.swift` (预计 200 行)

**核心接口**:
```swift
protocol SandboxProvider {
    // 环境管理
    func initialize() async throws
    func cleanup() async throws

    // 命令执行
    func execute(command: String, timeout: TimeInterval) async throws -> ExecutionResult

    // 文件操作
    func readFile(path: String) async throws -> String
    func writeFile(path: String, content: String) async throws
    func listFiles(path: String) async throws -> [FileInfo]
    func deleteFile(path: String) async throws

    // 路径映射
    func toVirtualPath(_ realPath: String) -> String
    func toRealPath(_ virtualPath: String) -> String
}

struct ExecutionResult {
    let stdout: String
    let stderr: String
    let exitCode: Int
    let duration: TimeInterval
}

struct FileInfo {
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool
    let modifiedAt: Date
}
```

---

#### 2.2 本地沙箱实现
**文件**: `LocalSandboxProvider.swift` (预计 300 行)

**核心功能**:
```swift
@MainActor
class LocalSandboxProvider: SandboxProvider {
    // 属性
    private let workspaceURL: URL
    private let uploadsURL: URL
    private let outputsURL: URL
    private let pathMapper: VirtualPathMapper

    // 初始化
    init(projectId: UUID) throws

    // 命令执行
    func execute(command: String, timeout: TimeInterval) async throws -> ExecutionResult {
        // 使用 Process 执行命令
        // 设置工作目录为 workspace
        // 应用超时限制
        // 捕获 stdout/stderr
    }

    // 文件操作
    func readFile(path: String) async throws -> String {
        let realPath = toRealPath(path)
        return try String(contentsOf: URL(fileURLWithPath: realPath))
    }

    func writeFile(path: String, content: String) async throws {
        let realPath = toRealPath(path)
        try content.write(to: URL(fileURLWithPath: realPath), atomically: true, encoding: .utf8)
    }
}
```

**实现要点**:
- ✅ 隔离的工作目录
- ✅ 虚拟路径映射
- ✅ 命令超时控制
- ✅ 资源限制

---

#### 2.3 虚拟路径映射
**文件**: `VirtualPathMapper.swift` (预计 150 行)

**核心功能**:
```swift
class VirtualPathMapper {
    // 虚拟路径前缀
    private let virtualWorkspace = "/mnt/user-data/workspace"
    private let virtualUploads = "/mnt/user-data/uploads"
    private let virtualOutputs = "/mnt/user-data/outputs"

    // 真实路径
    private let realWorkspace: URL
    private let realUploads: URL
    private let realOutputs: URL

    // 路径转换
    func toVirtual(_ realPath: String) -> String {
        // 将真实路径转换为虚拟路径
    }

    func toReal(_ virtualPath: String) -> String {
        // 将虚拟路径转换为真实路径
    }

    // 路径验证
    func isValidVirtualPath(_ path: String) -> Bool
    func isWithinSandbox(_ realPath: String) -> Bool
}
```

**映射规则**:
```
虚拟路径                          真实路径
/mnt/user-data/workspace    →    ~/Library/Application Support/X-Terminal/projects/{id}/workspace
/mnt/user-data/uploads      →    ~/Library/Application Support/X-Terminal/projects/{id}/uploads
/mnt/user-data/outputs      →    ~/Library/Application Support/X-Terminal/projects/{id}/outputs
```

---

#### 2.4 沙箱管理器
**文件**: `SandboxManager.swift` (预计 200 行)

**核心功能**:
```swift
@MainActor
class SandboxManager: ObservableObject {
    // 属性
    @Published var activeSandboxes: [UUID: SandboxProvider] = [:]
    private let providerType: SandboxProviderType

    // 沙箱生命周期
    func createSandbox(for projectId: UUID) async throws -> SandboxProvider
    func getSandbox(for projectId: UUID) -> SandboxProvider?
    func destroySandbox(for projectId: UUID) async throws

    // 批量操作
    func cleanupInactiveSandboxes() async
    func destroyAllSandboxes() async
}

enum SandboxProviderType {
    case local
    case docker  // 未来扩展
    case kubernetes  // 未来扩展
}
```

---

### 3. 工具生态系统 (25%)

#### 3.1 工具注册表
**文件**: `ToolRegistry.swift` (预计 250 行)

**核心功能**:
```swift
@MainActor
class ToolRegistry: ObservableObject {
    // 属性
    @Published var registeredTools: [String: Tool] = [:]
    @Published var toolCategories: [ToolCategory] = []

    // 工具注册
    func register(_ tool: Tool) throws
    func unregister(_ toolId: String)
    func getTool(_ toolId: String) -> Tool?

    // 工具查询
    func searchTools(query: String) -> [Tool]
    func getToolsByCategory(_ category: ToolCategory) -> [Tool]
    func getAllTools() -> [Tool]

    // 工具验证
    func validateTool(_ tool: Tool) -> Bool
    func checkDependencies(_ tool: Tool) -> [String]
}

// 工具协议
protocol Tool {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var category: ToolCategory { get }
    var version: String { get }
    var parameters: [ToolParameter] { get }

    func execute(parameters: [String: Any]) async throws -> ToolResult
    func validate(parameters: [String: Any]) -> Bool
}

// 工具类别
enum ToolCategory: String, Codable {
    case fileSystem = "文件系统"
    case network = "网络"
    case database = "数据库"
    case ai = "AI"
    case development = "开发"
    case system = "系统"
    case custom = "自定义"
}

// 工具参数
struct ToolParameter: Codable {
    let name: String
    let type: ParameterType
    let required: Bool
    let description: String
    let defaultValue: Any?
}

// 工具结果
struct ToolResult {
    let success: Bool
    let data: Any?
    let error: Error?
    let duration: TimeInterval
}
```

**功能**:
- ✅ 工具注册和管理
- ✅ 工具分类和查询
- ✅ 参数验证
- ✅ 依赖检查

---

#### 3.2 内置工具集
**文件**: `BuiltInTools.swift` (预计 400 行)

**核心工具**:
```swift
// 1. 文件系统工具
class FileReadTool: Tool {
    func execute(parameters: [String: Any]) async throws -> ToolResult
}

class FileWriteTool: Tool {
    func execute(parameters: [String: Any]) async throws -> ToolResult
}

class FileSearchTool: Tool {
    func execute(parameters: [String: Any]) async throws -> ToolResult
}

// 2. 网络工具
class HTTPRequestTool: Tool {
    func execute(parameters: [String: Any]) async throws -> ToolResult
}

class WebScrapeTool: Tool {
    func execute(parameters: [String: Any]) async throws -> ToolResult
}

// 3. 开发工具
class GitTool: Tool {
    func execute(parameters: [String: Any]) async throws -> ToolResult
}

class CodeAnalysisTool: Tool {
    func execute(parameters: [String: Any]) async throws -> ToolResult
}

// 4. AI 工具
class EmbeddingTool: Tool {
    func execute(parameters: [String: Any]) async throws -> ToolResult
}

class SummarizationTool: Tool {
    func execute(parameters: [String: Any]) async throws -> ToolResult
}

// 5. 系统工具
class ProcessTool: Tool {
    func execute(parameters: [String: Any]) async throws -> ToolResult
}

class EnvironmentTool: Tool {
    func execute(parameters: [String: Any]) async throws -> ToolResult
}
```

**工具列表** (15+ 个内置工具):
- ✅ 文件读取/写入/搜索
- ✅ HTTP 请求/Web 抓取
- ✅ Git 操作
- ✅ 代码分析
- ✅ 文本嵌入/摘要
- ✅ 进程管理
- ✅ 环境变量

---

#### 3.3 MCP 协议支持
**文件**: `MCPIntegration.swift` (预计 350 行)

**核心功能**:
```swift
@MainActor
class MCPIntegration: ObservableObject {
    // 属性
    @Published var mcpServers: [MCPServer] = []
    @Published var mcpTools: [MCPTool] = []

    // 服务器管理
    func connectServer(_ config: MCPServerConfig) async throws
    func disconnectServer(_ serverId: String) async
    func listServers() -> [MCPServer]

    // 工具发现
    func discoverTools(_ serverId: String) async throws -> [MCPTool]
    func refreshTools() async

    // 工具执行
    func executeMCPTool(_ toolId: String, parameters: [String: Any]) async throws -> ToolResult
}

// MCP 服务器配置
struct MCPServerConfig: Codable {
    let id: String
    let name: String
    let endpoint: URL
    let apiKey: String?
    let timeout: TimeInterval
}

// MCP 服务器
struct MCPServer: Identifiable, Codable {
    let id: String
    let name: String
    let endpoint: URL
    var status: ServerStatus
    var tools: [MCPTool]
}

// MCP 工具
struct MCPTool: Tool {
    let id: String
    let name: String
    let description: String
    let category: ToolCategory
    let version: String
    let parameters: [ToolParameter]
    let serverId: String

    func execute(parameters: [String: Any]) async throws -> ToolResult
}
```

**功能**:
- ✅ MCP 服务器连接
- ✅ 工具自动发现
- ✅ 远程工具执行
- ✅ 错误处理和重试

---

#### 3.4 工具管理器
**文件**: `ToolManager.swift` (预计 300 行)

**核心功能**:
```swift
@MainActor
class ToolManager: ObservableObject {
    // 属性
    @Published var toolRegistry: ToolRegistry
    @Published var mcpIntegration: MCPIntegration
    @Published var executionHistory: [ToolExecution] = []

    // 初始化
    init()

    // 工具执行
    func executeTool(_ toolId: String, parameters: [String: Any]) async throws -> ToolResult

    // 批量执行
    func executeTools(_ executions: [ToolExecution]) async throws -> [ToolResult]

    // 工具推荐
    func recommendTools(for task: String) async -> [Tool]

    // 执行历史
    func getExecutionHistory(limit: Int) -> [ToolExecution]
    func clearHistory()
}

// 工具执行记录
struct ToolExecution: Identifiable, Codable {
    let id: UUID
    let toolId: String
    let parameters: [String: Any]
    let result: ToolResult
    let timestamp: Date
    let duration: TimeInterval
}
```

**功能**:
- ✅ 统一工具执行接口
- ✅ 批量工具执行
- ✅ 工具推荐
- ✅ 执行历史追踪

---

### 4. 技能系统 (15%)

#### 4.1 技能数据模型
**文件**: `Skill.swift` (预计 200 行)

**核心结构**:
```swift
// 技能定义
struct Skill: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var category: SkillCategory
    var version: String
    var author: String

    // 技能配置
    var prompt: String              // 系统提示词
    var tools: [String]             // 所需工具
    var parameters: [SkillParameter] // 输入参数
    var examples: [SkillExample]    // 使用示例

    // 元数据
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
}

// 技能类别
enum SkillCategory: String, Codable {
    case research = "研究"
    case generation = "生成"
    case analysis = "分析"
    case automation = "自动化"
    case development = "开发"
    case custom = "自定义"
}

// 技能参数
struct SkillParameter: Codable {
    let name: String
    let type: String
    let required: Bool
    let description: String
    let defaultValue: String?
}

// 技能示例
struct SkillExample: Codable {
    let title: String
    let input: [String: String]
    let expectedOutput: String
}
```

**功能**:
- ✅ 技能定义结构
- ✅ 技能分类
- ✅ 参数配置
- ✅ 示例管理

---

#### 4.2 技能管理器
**文件**: `SkillManager.swift` (预计 350 行)

**核心功能**:
```swift
@MainActor
class SkillManager: ObservableObject {
    // 属性
    @Published var skills: [Skill] = []
    @Published var activeSkill: Skill?

    // 技能加载
    func loadSkill(from path: String) throws -> Skill
    func loadSkillFromYAML(_ yaml: String) throws -> Skill
    func saveSkill(_ skill: Skill, to path: String) throws

    // 技能管理
    func registerSkill(_ skill: Skill)
    func unregisterSkill(_ skillId: UUID)
    func getSkill(_ skillId: UUID) -> Skill?

    // 技能执行
    func executeSkill(_ skillId: UUID, parameters: [String: String]) async throws -> SkillResult

    // 技能搜索
    func searchSkills(query: String) -> [Skill]
    func getSkillsByCategory(_ category: SkillCategory) -> [Skill]
}

// 技能结果
struct SkillResult {
    let success: Bool
    let output: String
    let artifacts: [Artifact]
    let duration: TimeInterval
    let error: Error?
}

// 工件
struct Artifact: Identifiable, Codable {
    let id: UUID
    let type: ArtifactType
    let content: String
    let metadata: [String: String]
}

enum ArtifactType: String, Codable {
    case text = "文本"
    case code = "代码"
    case image = "图片"
    case document = "文档"
}
```

**功能**:
- ✅ 技能加载和保存
- ✅ YAML 格式支持
- ✅ 技能执行
- ✅ 工件管理

---

#### 4.3 内置技能集
**文件**: `BuiltInSkills.swift` (预计 300 行)

**核心技能**:
```swift
// 1. 深度研究技能
let deepResearchSkill = Skill(
    name: "深度研究",
    description: "对特定主题进行深入研究和分析",
    category: .research,
    prompt: """
    你是一个专业的研究助手。请对给定的主题进行深入研究：
    1. 收集相关信息
    2. 分析关键点
    3. 总结发现
    4. 提供建议
    """,
    tools: ["web_search", "web_scrape", "summarization"]
)

// 2. 代码生成技能
let codeGenerationSkill = Skill(
    name: "代码生成",
    description: "根据需求生成高质量代码",
    category: .generation,
    prompt: """
    你是一个专业的代码生成助手。请根据需求生成代码：
    1. 理解需求
    2. 设计架构
    3. 编写代码
    4. 添加注释
    5. 编写测试
    """,
    tools: ["code_analysis", "file_write"]
)

// 3. 数据分析技能
let dataAnalysisSkill = Skill(
    name: "数据分析",
    description: "分析数据并生成报告",
    category: .analysis,
    prompt: """
    你是一个专业的数据分析师。请分析数据：
    1. 加载数据
    2. 清洗数据
    3. 统计分析
    4. 可视化
    5. 生成报告
    """,
    tools: ["file_read", "summarization"]
)

// 4. 文档生成技能
let documentationSkill = Skill(
    name: "文档生成",
    description: "自动生成项目文档",
    category: .generation,
    prompt: """
    你是一个专业的技术文档编写者。请生成文档：
    1. 分析代码结构
    2. 提取关键信息
    3. 编写文档
    4. 添加示例
    """,
    tools: ["code_analysis", "file_read", "file_write"]
)

// 5. 自动化测试技能
let autoTestSkill = Skill(
    name: "自动化测试",
    description: "生成和执行自动化测试",
    category: .automation,
    prompt: """
    你是一个专业的测试工程师。请进行自动化测试：
    1. 分析代码
    2. 设计测试用例
    3. 编写测试代码
    4. 执行测试
    5. 生成报告
    """,
    tools: ["code_analysis", "file_write", "process"]
)
```

**技能列表** (10+ 个内置技能):
- ✅ 深度研究
- ✅ 代码生成
- ✅ 数据分析
- ✅ 文档生成
- ✅ 自动化测试
- ✅ Bug 修复
- ✅ 性能优化
- ✅ 安全审计
- ✅ API 设计
- ✅ 数据库设计

---

#### 4.4 技能创建器
**文件**: `SkillCreator.swift` (预计 250 行)

**核心功能**:
```swift
@MainActor
class SkillCreator: ObservableObject {
    // 创建技能
    func createSkill(from template: SkillTemplate) -> Skill

    // 技能模板
    func getTemplates() -> [SkillTemplate]
    func createTemplate(_ template: SkillTemplate)

    // 技能验证
    func validateSkill(_ skill: Skill) -> [ValidationError]

    // 技能导出
    func exportToYAML(_ skill: Skill) -> String
    func exportToJSON(_ skill: Skill) -> String
}

// 技能模板
struct SkillTemplate: Codable {
    let name: String
    let category: SkillCategory
    let promptTemplate: String
    let requiredTools: [String]
    let parameters: [SkillParameter]
}
```

**功能**:
- ✅ 技能创建向导
- ✅ 模板系统
- ✅ 技能验证
- ✅ 导出功能

---

### 5. 中间件架构 (5%)

#### 5.1 中间件系统
**文件**: `Middleware.swift` (预计 300 行)

**核心功能**:
```swift
// 中间件协议
protocol Middleware {
    var name: String { get }
    var priority: Int { get }

    func process(context: MiddlewareContext) async throws -> MiddlewareContext
}

// 中间件上下文
struct MiddlewareContext {
    var request: Request
    var response: Response?
    var metadata: [String: Any]
    var error: Error?
}

// 中间件链
@MainActor
class MiddlewareChain: ObservableObject {
    // 属性
    private var middlewares: [Middleware] = []

    // 添加中间件
    func add(_ middleware: Middleware)
    func remove(_ name: String)

    // 执行中间件链
    func execute(context: MiddlewareContext) async throws -> MiddlewareContext
}

// 内置中间件
class LoggingMiddleware: Middleware {
    func process(context: MiddlewareContext) async throws -> MiddlewareContext
}

class AuthenticationMiddleware: Middleware {
    func process(context: MiddlewareContext) async throws -> MiddlewareContext
}

class RateLimitMiddleware: Middleware {
    func process(context: MiddlewareContext) async throws -> MiddlewareContext
}

class CachingMiddleware: Middleware {
    func process(context: MiddlewareContext) async throws -> MiddlewareContext
}

class ErrorHandlingMiddleware: Middleware {
    func process(context: MiddlewareContext) async throws -> MiddlewareContext
}
```

**中间件列表** (8+ 个):
- ✅ 日志记录
- ✅ 认证授权
- ✅ 速率限制
- ✅ 缓存
- ✅ 错误处理
- ✅ 请求验证
- ✅ 响应转换
- ✅ 性能监控

---

### 6. 集成工作

#### 6.1 ProjectModel 扩展
**文件**: `ProjectModel.swift` (修改)

**新增属性**:
```swift
// Phase 3: Memory System
@Published var memoryManager: MemoryManager?

// Phase 3: Sandbox System
@Published var sandbox: SandboxProvider?

// Phase 3: Tool System
@Published var toolManager: ToolManager?

// Phase 3: Skill System
@Published var skillManager: SkillManager?

// Phase 3: Middleware
@Published var middlewareChain: MiddlewareChain?
```

**新增方法**:
```swift
// 初始化记忆系统
func initializeMemory() async throws {
    memoryManager = MemoryManager(projectId: id)
    try await memoryManager?.loadMemory()
}

// 初始化沙箱
func initializeSandbox() async throws {
    sandbox = try await SandboxManager.shared.createSandbox(for: id)
}

// 初始化工具系统
func initializeTools() async throws {
    toolManager = ToolManager()
    await toolManager?.loadBuiltInTools()
}

// 初始化技能系统
func initializeSkills() async throws {
    skillManager = SkillManager()
    await skillManager?.loadBuiltInSkills()
}

// 初始化中间件
func initializeMiddleware() {
    middlewareChain = MiddlewareChain()
    middlewareChain?.setupDefaultMiddlewares()
}

// 执行命令
func executeCommand(_ command: String) async throws -> ExecutionResult {
    guard let sandbox = sandbox else {
        throw SandboxError.notInitialized
    }
    return try await sandbox.execute(command: command, timeout: 60)
}

// 执行工具
func executeTool(_ toolId: String, parameters: [String: Any]) async throws -> ToolResult {
    guard let toolManager = toolManager else {
        throw ToolError.notInitialized
    }
    return try await toolManager.executeTool(toolId, parameters: parameters)
}

// 执行技能
func executeSkill(_ skillId: UUID, parameters: [String: String]) async throws -> SkillResult {
    guard let skillManager = skillManager else {
        throw SkillError.notInitialized
    }
    return try await skillManager.executeSkill(skillId, parameters: parameters)
}
```

---

#### 6.2 SupervisorOrchestrator 扩展
**文件**: `SupervisorOrchestrator.swift` (修改)

**新增组件**:
```swift
// Phase 3: Memory System
lazy var memoryExtractor = MemoryExtractor(llmRouter: supervisor.llmRouter)

// Phase 3: Sandbox System
lazy var sandboxManager = SandboxManager.shared

// Phase 3: Tool System
lazy var globalToolRegistry = ToolRegistry.shared

// Phase 3: Skill System
lazy var globalSkillManager = SkillManager.shared
```

**新增方法**:
```swift
// 提取并更新记忆
func updateProjectMemory(_ project: ProjectModel) async {
    guard let memoryManager = project.memoryManager else { return }

    let messages = project.session.messages
    let extracted = await memoryExtractor.extractFromConversation(messages)

    await memoryManager.updateFacts(extracted.facts)
    // ... 更新其他记忆
}

// 获取记忆上下文
func getMemoryContext(for project: ProjectModel, task: String) -> String? {
    return project.memoryManager?.getRelevantContext(for: task)
}

// 推荐工具
func recommendTools(for task: String) async -> [Tool] {
    return await globalToolRegistry.recommendTools(for: task)
}

// 推荐技能
func recommendSkills(for task: String) async -> [Skill] {
    return await globalSkillManager.searchSkills(query: task)
}

// 执行工具链
func executeToolChain(_ tools: [String], parameters: [[String: Any]]) async throws -> [ToolResult] {
    var results: [ToolResult] = []
    for (index, toolId) in tools.enumerated() {
        let params = parameters[index]
        let result = try await globalToolRegistry.executeTool(toolId, parameters: params)
        results.append(result)
    }
    return results
}
```

---

## 📊 工作量估算

### 1. 记忆系统 (30%)

| 组件 | 文件 | 预计代码量 | 预计时间 |
|------|------|------------|----------|
| 记忆数据模型 | Memory.swift | 200 行 | 2-3 小时 |
| 记忆管理器 | MemoryManager.swift | 300 行 | 6-8 小时 |
| LLM 记忆提取 | MemoryExtractor.swift | 250 行 | 8-10 小时 |
| 记忆注入系统 | MemoryInjector.swift | 150 行 | 3-4 小时 |
| **小计** | **4 个文件** | **~900 行** | **19-25 小时** |

---

### 2. 沙箱系统 (25%)

| 组件 | 文件 | 预计代码量 | 预计时间 |
|------|------|------------|----------|
| 沙箱接口 | SandboxProvider.swift | 200 行 | 3-4 小时 |
| 本地沙箱 | LocalSandboxProvider.swift | 300 行 | 8-10 小时 |
| 路径映射 | VirtualPathMapper.swift | 150 行 | 3-4 小时 |
| 沙箱管理器 | SandboxManager.swift | 200 行 | 4-5 小时 |
| **小计** | **4 个文件** | **~850 行** | **18-23 小时** |

---

### 3. 工具生态系统 (25%)

| 组件 | 文件 | 预计代码量 | 预计时间 |
|------|------|------------|----------|
| 工具注册表 | ToolRegistry.swift | 250 行 | 4-5 小时 |
| 内置工具集 | BuiltInTools.swift | 400 行 | 8-10 小时 |
| MCP 协议支持 | MCPIntegration.swift | 350 行 | 8-10 小时 |
| 工具管理器 | ToolManager.swift | 300 行 | 6-8 小时 |
| **小计** | **4 个文件** | **~1,300 行** | **26-33 小时** |

---

### 4. 技能系统 (15%)

| 组件 | 文件 | 预计代码量 | 预计时间 |
|------|------|------------|----------|
| 技能数据模型 | Skill.swift | 200 行 | 2-3 小时 |
| 技能管理器 | SkillManager.swift | 350 行 | 6-8 小时 |
| 内置技能集 | BuiltInSkills.swift | 300 行 | 6-8 小时 |
| 技能创建器 | SkillCreator.swift | 250 行 | 4-5 小时 |
| **小计** | **4 个文件** | **~1,100 行** | **18-24 小时** |

---

### 5. 中间件架构 (5%)

| 组件 | 文件 | 预计代码量 | 预计时间 |
|------|------|------------|----------|
| 中间件系统 | Middleware.swift | 300 行 | 6-8 小时 |
| **小计** | **1 个文件** | **~300 行** | **6-8 小时** |

---

### 6. 集成和测试

| 任务 | 预计时间 |
|------|----------|
| ProjectModel 集成 | 4-5 小时 |
| SupervisorOrchestrator 集成 | 4-5 小时 |
| UI 集成 | 6-8 小时 |
| 单元测试 | 8-10 小时 |
| 集成测试 | 6-8 小时 |
| 文档编写 | 4-5 小时 |
| **小计** | **32-41 小时** |

---

### 总工作量

| 模块 | 文件数 | 代码量 | 时间 |
|------|--------|--------|------|
| 记忆系统 | 4 | ~900 行 | 19-25 小时 |
| 沙箱系统 | 4 | ~850 行 | 18-23 小时 |
| 工具生态 | 4 | ~1,300 行 | 26-33 小时 |
| 技能系统 | 4 | ~1,100 行 | 18-24 小时 |
| 中间件 | 1 | ~300 行 | 6-8 小时 |
| 集成测试 | - | - | 32-41 小时 |
| **总计** | **17 个文件** | **~4,450 行** | **119-154 小时** |

**预计总时间**: 120-150 小时 (约 15-19 个工作日)

---

## 🎯 里程碑

### Milestone 1: 记忆系统 (20%)
**目标**: 完成持久化记忆系统
**交付物**:
- Memory.swift
- MemoryManager.swift
- MemoryExtractor.swift
- MemoryInjector.swift
- 基础单元测试

**预计时间**: 19-25 小时

---

### Milestone 2: 沙箱系统 (15%)
**目标**: 完成沙箱执行系统
**交付物**:
- SandboxProvider.swift
- LocalSandboxProvider.swift
- VirtualPathMapper.swift
- SandboxManager.swift
- 沙箱测试

**预计时间**: 18-23 小时

---

### Milestone 3: 工具生态系统 (25%)
**目标**: 完成工具注册和管理
**交付物**:
- ToolRegistry.swift
- BuiltInTools.swift
- MCPIntegration.swift
- ToolManager.swift
- 工具测试

**预计时间**: 26-33 小时

---

### Milestone 4: 技能系统 (20%)
**目标**: 完成技能管理和执行
**交付物**:
- Skill.swift
- SkillManager.swift
- BuiltInSkills.swift
- SkillCreator.swift
- 技能测试

**预计时间**: 18-24 小时

---

### Milestone 5: 中间件架构 (5%)
**目标**: 完成中间件系统
**交付物**:
- Middleware.swift
- 内置中间件
- 中间件测试

**预计时间**: 6-8 小时

---

### Milestone 6: 集成和测试 (15%)
**目标**: 完成系统集成和测试
**交付物**:
- ProjectModel 集成
- SupervisorOrchestrator 集成
- UI 集成
- 完整测试
- 文档

**预计时间**: 32-41 小时

---

## 🔧 技术决策（节选）

### 记忆系统

**存储方式**: JSON 文件
- ✅ 简单易用
- ✅ 人类可读
- ✅ 易于调试
- ⚠️ 性能有限 (可接受)

**更新策略**: 防抖队列
- ✅ 减少 I/O 操作
- ✅ 避免频繁更新
- ✅ 30 秒默认延迟

**LLM 提取**: 使用项目配置的模型
- ✅ 复用现有配置
- ✅ 成本可控
- ✅ 质量保证

---

### 沙箱系统

**初期实现**: 仅本地沙箱
- ✅ 实现简单
- ✅ 无需额外依赖
- ✅ 满足基本需求
- ⚠️ 隔离性有限 (可接受)

**未来扩展**: Docker 支持
- 预留接口
- 可选功能
- 按需实现

**路径映射**: 虚拟路径系统
- ✅ 透明映射
- ✅ 安全隔离
- ✅ 易于迁移

---

## 🚀 实施顺序

### 第一周: 记忆系统 (Day 1-3)

**Day 1: 记忆数据模型**
1. 创建 Memory.swift
2. 定义数据结构 (UserContext, History, Fact)
3. 实现 Codable 协议
4. 编写基础测试

**Day 2: 记忆管理器**
1. 创建 MemoryManager.swift
2. 实现文件 I/O 操作
3. 实现防抖更新机制
4. 实现记忆查询功能
5. 编写管理器测试

**Day 3: LLM 记忆提取和注入**
1. 创建 MemoryExtractor.swift
2. 设计提取 Prompt
3. 实现提取逻辑和置信度评估
4. 创建 MemoryInjector.swift
5. 实现记忆注入和格式化
6. 编写提取和注入测试

---

### 第二周: 沙箱系统 (Day 4-6)

**Day 4: 沙箱接口和路径映射**
1. 创建 SandboxProvider.swift
2. 定义协议接口和数据结构
3. 创建 VirtualPathMapper.swift
4. 实现路径转换和验证
5. 编写路径映射测试

**Day 5: 本地沙箱实现**
1. 创建 LocalSandboxProvider.swift
2. 实现命令执行 (Process)
3. 实现文件操作
4. 实现超时控制
5. 编写沙箱测试

**Day 6: 沙箱管理器**
1. 创建 SandboxManager.swift
2. 实现沙箱生命周期管理
3. 实现批量操作
4. 集成到 ProjectModel
5. 编写管理器测试

---

### 第三周: 工具生态系统 (Day 7-10)

**Day 7: 工具注册表**
1. 创建 ToolRegistry.swift
2. 定义 Tool 协议
3. 实现工具注册和查询
4. 实现工具验证
5. 编写注册表测试

**Day 8-9: 内置工具集**
1. 创建 BuiltInTools.swift
2. 实现文件系统工具 (3个)
3. 实现网络工具 (2个)
4. 实现开发工具 (2个)
5. 实现 AI 工具 (2个)
6. 实现系统工具 (2个)
7. 编写工具测试

**Day 10: MCP 协议支持**
1. 创建 MCPIntegration.swift
2. 实现服务器连接
3. 实现工具发现
4. 实现远程工具执行
5. 编写 MCP 测试

---

### 第四周: 技能系统 (Day 11-13)

**Day 11: 技能数据模型和管理器**
1. 创建 Skill.swift
2. 定义技能数据结构
3. 创建 SkillManager.swift
4. 实现技能加载和保存
5. 实现 YAML 解析
6. 编写基础测试

**Day 12: 内置技能集**
1. 创建 BuiltInSkills.swift
2. 实现深度研究技能
3. 实现代码生成技能
4. 实现数据分析技能
5. 实现文档生成技能
6. 实现自动化测试技能
7. 实现其他 5+ 技能
8. 编写技能测试

**Day 13: 技能创建器和工具管理器**
1. 创建 SkillCreator.swift
2. 实现技能创建向导
3. 实现模板系统
4. 创建 ToolManager.swift
5. 实现统一工具执行接口
6. 编写测试

---

### 第五周: 中间件和集成 (Day 14-16)

**Day 14: 中间件架构**
1. 创建 Middleware.swift
2. 定义中间件协议
3. 实现中间件链
4. 实现 8+ 内置中间件
5. 编写中间件测试

**Day 15: 系统集成**
1. 扩展 ProjectModel (5个新方法)
2. 扩展 SupervisorOrchestrator (5个新方法)
3. 更新 UI 组件
4. 编写集成测试

**Day 16: UI 集成**
1. 创建工具管理视图
2. 创建技能管理视图
3. 创建记忆查看器
4. 创建沙箱控制台
5. 更新项目详情视图

---

### 第六周: 测试和文档 (Day 17-19)

**Day 17: 单元测试**
1. 记忆系统测试
2. 沙箱系统测试
3. 工具系统测试
4. 技能系统测试
5. 中间件测试

**Day 18: 集成测试**
1. 端到端测试
2. 性能测试
3. 压力测试
4. Bug 修复

**Day 19: 文档和交付**
1. 编写 API 文档
2. 编写使用指南
3. 更新 README
4. 创建示例代码
5. 最终测试和交付

---

## 🔧 技术决策

### 记忆系统

**存储方式**: JSON 文件
- ✅ 简单易用
- ✅ 人类可读
- ✅ 易于调试
- ⚠️ 性能有限 (可接受)

**更新策略**: 防抖队列
- ✅ 减少 I/O 操作
- ✅ 避免频繁更新
- ✅ 30 秒默认延迟

**LLM 提取**: 使用项目配置的模型
- ✅ 复用现有配置
- ✅ 成本可控
- ✅ 质量保证

---

### 沙箱系统

**初期实现**: 仅本地沙箱
- ✅ 实现简单
- ✅ 无需额外依赖
- ✅ 满足基本需求
- ⚠️ 隔离性有限 (可接受)

**未来扩展**: Docker 支持
- 预留接口
- 可选功能
- 按需实现

**路径映射**: 虚拟路径系统
- ✅ 透明映射
- ✅ 安全隔离
- ✅ 易于迁移

---

### 工具生态系统

**工具注册**: 协议驱动
- ✅ 类型安全
- ✅ 易于扩展
- ✅ 统一接口

**MCP 支持**: 标准协议
- ✅ 社区兼容
- ✅ 动态加载
- ✅ 远程执行

**内置工具**: 15+ 工具
- ✅ 覆盖常用场景
- ✅ 开箱即用
- ✅ 高质量实现

---

### 技能系统

**技能格式**: YAML + Markdown
- ✅ 人类可读
- ✅ 易于编辑
- ✅ 版本控制友好

**技能执行**: LLM 驱动
- ✅ 灵活强大
- ✅ 上下文感知
- ✅ 自然语言交互

**内置技能**: 10+ 技能
- ✅ 覆盖主要场景
- ✅ 可定制
- ✅ 可扩展

---

### 中间件架构

**设计模式**: 责任链模式
- ✅ 关注点分离
- ✅ 易于组合
- ✅ 可配置

**内置中间件**: 8+ 中间件
- ✅ 日志记录
- ✅ 认证授权
- ✅ 速率限制
- ✅ 缓存
- ✅ 错误处理

---

## 📝 成功标准

### 记忆系统

- ✅ 能够从对话中提取关键信息
- ✅ 能够持久化存储记忆
- ✅ 能够查询相关记忆
- ✅ 能够注入记忆到上下文
- ✅ 置信度评分准确
- ✅ 防抖机制工作正常

---

### 沙箱系统

- ✅ 能够执行 bash 命令
- ✅ 能够读写文件
- ✅ 虚拟路径映射正确
- ✅ 命令超时控制有效
- ✅ 工作目录隔离
- ✅ 资源清理完整

---

### 工具生态系统

- ✅ 工具注册和查询正常
- ✅ 15+ 内置工具可用
- ✅ MCP 协议支持完整
- ✅ 工具执行稳定
- ✅ 错误处理完善
- ✅ 性能满足要求

---

### 技能系统

- ✅ 技能加载和保存正常
- ✅ YAML 解析正确
- ✅ 10+ 内置技能可用
- ✅ 技能执行稳定
- ✅ 工件管理完善
- ✅ 技能创建器可用

---

### 中间件架构

- ✅ 中间件链执行正确
- ✅ 8+ 内置中间件可用
- ✅ 中间件组合灵活
- ✅ 错误处理完善
- ✅ 性能影响可控

---

### 集成

- ✅ ProjectModel 集成无缝
- ✅ SupervisorOrchestrator 集成正确
- ✅ UI 显示所有新功能
- ✅ 编译无错误
- ✅ 测试覆盖率 > 70%

---

## ⚠️ 风险和挑战

### 技术风险

1. **LLM 提取准确性**
   - 风险: LLM 提取的记忆可能不准确
   - 缓解: 置信度评分 + 人工审核

2. **沙箱安全性**
   - 风险: 本地沙箱隔离性有限
   - 缓解: 路径验证 + 资源限制

3. **性能问题**
   - 风险: 记忆提取和工具执行可能较慢
   - 缓解: 防抖机制 + 异步处理 + 缓存

4. **MCP 兼容性**
   - 风险: MCP 协议实现可能不完整
   - 缓解: 参考标准实现 + 充分测试

5. **工具稳定性**
   - 风险: 第三方工具可能不稳定
   - 缓解: 错误处理 + 超时控制 + 降级策略

---

### 实施风险

1. **工作量估算**
   - 风险: 实际工作量可能超出预期 (120-150小时)
   - 缓解: 分阶段实施 + 灵活调整 + 优先级排序

2. **集成复杂度**
   - 风险: 与现有系统集成可能遇到问题
   - 缓解: 预留接口 + 充分测试 + 渐进式集成

3. **测试覆盖**
   - 风险: 测试覆盖可能不足
   - 缓解: TDD 开发 + 自动化测试 + 代码审查

4. **文档完整性**
   - 风险: 文档可能不够详细
   - 缓解: 边开发边写文档 + 代码注释 + 示例代码

---

## 🎊 Phase 3 完成后的效果

### 新增能力

1. **持久化记忆** (⭐⭐ → ⭐⭐⭐⭐⭐)
   - AI 能记住用户偏好
   - AI 能记住项目上下文
   - AI 能记住历史对话
   - LLM 驱动的智能提取
   - 置信度评分系统

2. **安全执行** (⭐ → ⭐⭐⭐⭐)
   - 隔离的工作目录
   - 虚拟路径系统
   - 命令超时控制
   - 资源限制

3. **丰富工具** (⭐⭐ → ⭐⭐⭐⭐⭐)
   - 15+ 内置工具
   - MCP 协议支持
   - 动态工具加载
   - 社区工具集成

4. **技能系统** (⭐ → ⭐⭐⭐⭐⭐)
   - 10+ 内置技能
   - YAML 配置
   - 技能创建器
   - 工件管理

5. **中间件架构** (新增)
   - 8+ 内置中间件
   - 责任链模式
   - 灵活组合
   - 关注点分离

6. **更智能的 AI**
   - 基于记忆的个性化
   - 上下文感知的响应
   - 更准确的建议
   - 工具和技能推荐

---

### 竞争力提升

**与 DeerFlow 对比**:

| 维度 | Phase 2 | Phase 3 | DeerFlow |
|------|---------|---------|----------|
| 记忆系统 | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 沙箱执行 | ⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 工具生态 | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 技能系统 | ⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 任务分解 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| 任务分配 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| 执行监控 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| UI/UX | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **总分** | **56/75** | **70/75** | **66/75** |

**差距变化**:
- Phase 2: 落后 10 分 (56 vs 66)
- Phase 3: 领先 4 分 (70 vs 66) ✨

**核心优势**:
- ✅ 保持原生 macOS 体验
- ✅ 保持任务分解/分配/监控优势
- ✅ 补齐记忆系统短板
- ✅ 补齐沙箱执行短板
- ✅ 补齐工具生态短板
- ✅ 补齐技能系统短板
- ✅ 新增中间件架构优势

---

## 📞 准备开始

Phase 3 的全面计划已经完成，现在可以开始实施了！

### 建议的第一步

**创建记忆数据模型 (Memory.swift)**，这是整个记忆系统的基础。

### 实施策略

**推荐**: 按照里程碑顺序实施
1. Milestone 1: 记忆系统 (3天)
2. Milestone 2: 沙箱系统 (3天)
3. Milestone 3: 工具生态系统 (4天)
4. Milestone 4: 技能系统 (3天)
5. Milestone 5: 中间件架构 (1天)
6. Milestone 6: 集成和测试 (5天)

**总计**: 19 个工作日

### 关键里程碑

- **Week 1 结束**: 记忆系统完成
- **Week 2 结束**: 沙箱系统完成
- **Week 3 结束**: 工具生态系统完成
- **Week 4 结束**: 技能系统完成
- **Week 5 结束**: 中间件和集成完成
- **Week 6 结束**: 测试和文档完成

**准备好开始了吗？** 🚀

---

**Phase 3 实施计划 - 全面补齐短板**
**日期**: 2026-02-27
**状态**: 📋 规划完成
**预计工作量**: 120-150 小时
**预计完成**: 15-19 个工作日
**目标**: 从 56/75 分提升到 70/75 分，超越 DeerFlow
