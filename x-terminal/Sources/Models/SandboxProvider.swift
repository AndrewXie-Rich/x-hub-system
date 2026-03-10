import Foundation

// MARK: - Sandbox Provider Protocol

/// 沙箱提供者协议
@MainActor
protocol SandboxProvider {
    // MARK: - Environment Management

    /// 初始化沙箱环境
    func initialize() async throws

    /// 清理沙箱环境
    func cleanup() async throws

    /// 检查沙箱是否已初始化
    var isInitialized: Bool { get }

    // MARK: - Command Execution

    /// 执行命令
    /// - Parameters:
    ///   - command: 要执行的命令
    ///   - timeout: 超时时间（秒）
    /// - Returns: 执行结果
    func execute(command: String, timeout: TimeInterval) async throws -> ExecutionResult

    /// 批量执行命令
    /// - Parameters:
    ///   - commands: 命令列表
    ///   - timeout: 每个命令的超时时间
    /// - Returns: 执行结果列表
    func executeMultiple(commands: [String], timeout: TimeInterval) async throws -> [ExecutionResult]

    // MARK: - File Operations

    /// 读取文件
    /// - Parameter path: 文件路径（虚拟路径）
    /// - Returns: 文件内容
    func readFile(path: String) async throws -> String

    /// 写入文件
    /// - Parameters:
    ///   - path: 文件路径（虚拟路径）
    ///   - content: 文件内容
    func writeFile(path: String, content: String) async throws

    /// 列出文件
    /// - Parameter path: 目录路径（虚拟路径）
    /// - Returns: 文件信息列表
    func listFiles(path: String) async throws -> [FileInfo]

    /// 删除文件
    /// - Parameter path: 文件路径（虚拟路径）
    func deleteFile(path: String) async throws

    /// 创建目录
    /// - Parameter path: 目录路径（虚拟路径）
    func createDirectory(path: String) async throws

    /// 检查文件是否存在
    /// - Parameter path: 文件路径（虚拟路径）
    /// - Returns: 是否存在
    func fileExists(path: String) async throws -> Bool

    // MARK: - Path Mapping

    /// 转换为虚拟路径
    /// - Parameter realPath: 真实路径
    /// - Returns: 虚拟路径
    func toVirtualPath(_ realPath: String) -> String

    /// 转换为真实路径
    /// - Parameter virtualPath: 虚拟路径
    /// - Returns: 真实路径
    func toRealPath(_ virtualPath: String) -> String

    // MARK: - Resource Management

    /// 获取工作目录
    var workingDirectory: String { get }

    /// 获取上传目录
    var uploadsDirectory: String { get }

    /// 获取输出目录
    var outputsDirectory: String { get }

    /// 获取资源使用情况
    func getResourceUsage() async throws -> ResourceUsage
}

// MARK: - Execution Result

/// 命令执行结果
struct ExecutionResult: Codable, Equatable {
    /// 标准输出
    let stdout: String

    /// 标准错误
    let stderr: String

    /// 退出码
    let exitCode: Int

    /// 执行时长（秒）
    let duration: TimeInterval

    /// 执行时间戳
    let timestamp: Date

    /// 是否成功
    var isSuccess: Bool {
        return exitCode == 0
    }

    /// 是否有错误输出
    var hasError: Bool {
        return !stderr.isEmpty || exitCode != 0
    }

    /// 完整输出
    var fullOutput: String {
        var output = ""
        if !stdout.isEmpty {
            output += "STDOUT:\n\(stdout)\n"
        }
        if !stderr.isEmpty {
            output += "STDERR:\n\(stderr)\n"
        }
        output += "Exit Code: \(exitCode)\n"
        output += "Duration: \(String(format: "%.2f", duration))s\n"
        return output
    }

    init(
        stdout: String = "",
        stderr: String = "",
        exitCode: Int = 0,
        duration: TimeInterval = 0,
        timestamp: Date = Date()
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.duration = duration
        self.timestamp = timestamp
    }
}

// MARK: - File Info

/// 文件信息
struct FileInfo: Identifiable, Codable, Equatable {
    /// 文件 ID
    let id: UUID

    /// 文件名
    let name: String

    /// 文件路径（虚拟路径）
    let path: String

    /// 文件大小（字节）
    let size: Int64

    /// 是否为目录
    let isDirectory: Bool

    /// 是否为符号链接
    let isSymbolicLink: Bool

    /// 修改时间
    let modifiedAt: Date

    /// 创建时间
    let createdAt: Date

    /// 文件权限
    let permissions: String

    /// 文件扩展名
    var fileExtension: String {
        return (name as NSString).pathExtension
    }

    /// 格式化的文件大小
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    init(
        name: String,
        path: String,
        size: Int64,
        isDirectory: Bool,
        isSymbolicLink: Bool = false,
        modifiedAt: Date,
        createdAt: Date,
        permissions: String = "rw-r--r--"
    ) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.permissions = permissions
    }
}

// MARK: - Resource Usage

/// 资源使用情况
struct ResourceUsage: Codable {
    /// CPU 使用率（百分比）
    let cpuUsage: Double

    /// 内存使用量（字节）
    let memoryUsage: Int64

    /// 磁盘使用量（字节）
    let diskUsage: Int64

    /// 进程数量
    let processCount: Int

    /// 采样时间
    let timestamp: Date

    /// 格式化的内存使用量
    var formattedMemory: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: memoryUsage)
    }

    /// 格式化的磁盘使用量
    var formattedDisk: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: diskUsage)
    }

    init(
        cpuUsage: Double = 0.0,
        memoryUsage: Int64 = 0,
        diskUsage: Int64 = 0,
        processCount: Int = 0,
        timestamp: Date = Date()
    ) {
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.diskUsage = diskUsage
        self.processCount = processCount
        self.timestamp = timestamp
    }
}

// MARK: - Sandbox Errors

/// 沙箱错误
enum SandboxError: Error, LocalizedError {
    case notInitialized
    case alreadyInitialized
    case initializationFailed(String)
    case cleanupFailed(String)
    case commandExecutionFailed(String)
    case commandTimeout
    case fileNotFound(String)
    case fileReadFailed(String)
    case fileWriteFailed(String)
    case directoryCreationFailed(String)
    case invalidPath(String)
    case pathOutsideSandbox(String)
    case permissionDenied(String)
    case resourceLimitExceeded(String)
    case unsupportedOperation(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "沙箱未初始化"
        case .alreadyInitialized:
            return "沙箱已经初始化"
        case .initializationFailed(let reason):
            return "沙箱初始化失败: \(reason)"
        case .cleanupFailed(let reason):
            return "沙箱清理失败: \(reason)"
        case .commandExecutionFailed(let reason):
            return "命令执行失败: \(reason)"
        case .commandTimeout:
            return "命令执行超时"
        case .fileNotFound(let path):
            return "文件未找到: \(path)"
        case .fileReadFailed(let reason):
            return "文件读取失败: \(reason)"
        case .fileWriteFailed(let reason):
            return "文件写入失败: \(reason)"
        case .directoryCreationFailed(let reason):
            return "目录创建失败: \(reason)"
        case .invalidPath(let path):
            return "无效的路径: \(path)"
        case .pathOutsideSandbox(let path):
            return "路径在沙箱外部: \(path)"
        case .permissionDenied(let operation):
            return "权限被拒绝: \(operation)"
        case .resourceLimitExceeded(let resource):
            return "资源限制超出: \(resource)"
        case .unsupportedOperation(let operation):
            return "不支持的操作: \(operation)"
        }
    }
}

// MARK: - Sandbox Configuration

/// 沙箱配置
struct SandboxConfiguration: Codable {
    /// 默认超时时间（秒）
    var defaultTimeout: TimeInterval = 60.0

    /// 最大超时时间（秒）
    var maxTimeout: TimeInterval = 300.0

    /// 最大内存限制（字节）
    var maxMemory: Int64 = 1024 * 1024 * 1024  // 1GB

    /// 最大磁盘使用（字节）
    var maxDiskUsage: Int64 = 10 * 1024 * 1024 * 1024  // 10GB

    /// 最大进程数
    var maxProcesses: Int = 10

    /// 是否允许网络访问
    var allowNetworkAccess: Bool = true

    /// 是否允许文件系统访问
    var allowFileSystemAccess: Bool = true

    /// 允许的命令白名单（空表示允许所有）
    var allowedCommands: [String] = []

    /// 禁止的命令黑名单
    var blockedCommands: [String] = ["rm -rf /", "dd", "mkfs"]

    /// 环境变量
    var environmentVariables: [String: String] = [:]

    /// 工作目录名称
    var workspaceDirName: String = "workspace"

    /// 上传目录名称
    var uploadsDirName: String = "uploads"

    /// 输出目录名称
    var outputsDirName: String = "outputs"

    static var `default`: SandboxConfiguration {
        return SandboxConfiguration()
    }
}

// MARK: - Sandbox Provider Type

/// 沙箱提供者类型
enum SandboxProviderType: String, Codable, CaseIterable {
    case local = "本地沙箱"
    case docker = "Docker 容器"
    case kubernetes = "Kubernetes Pod"

    var description: String {
        return self.rawValue
    }

    var isAvailable: Bool {
        switch self {
        case .local:
            return true
        case .docker:
            // 检查 Docker 是否可用
            return false  // TODO: 实现 Docker 检测
        case .kubernetes:
            // 检查 Kubernetes 是否可用
            return false  // TODO: 实现 K8s 检测
        }
    }
}

// MARK: - Sandbox Status

/// 沙箱状态
enum SandboxStatus: String, Codable {
    case uninitialized = "未初始化"
    case initializing = "初始化中"
    case ready = "就绪"
    case busy = "忙碌"
    case error = "错误"
    case cleaning = "清理中"
    case terminated = "已终止"

    var isActive: Bool {
        return self == .ready || self == .busy
    }

    var canExecute: Bool {
        return self == .ready
    }
}

// MARK: - Command Options

/// 命令执行选项
struct CommandOptions {
    /// 超时时间（秒）
    var timeout: TimeInterval = 60.0

    /// 工作目录（虚拟路径）
    var workingDirectory: String?

    /// 环境变量
    var environmentVariables: [String: String] = [:]

    /// 是否捕获标准输出
    var captureStdout: Bool = true

    /// 是否捕获标准错误
    var captureStderr: Bool = true

    /// 是否合并标准输出和标准错误
    var mergeOutput: Bool = false

    /// 输入数据
    var input: String?

    static var `default`: CommandOptions {
        return CommandOptions()
    }
}

// MARK: - Sandbox Provider Extensions

extension SandboxProvider {
    /// 执行命令（使用默认超时）
    func execute(command: String) async throws -> ExecutionResult {
        return try await execute(command: command, timeout: 60.0)
    }

    /// 批量执行命令（使用默认超时）
    func executeMultiple(commands: [String]) async throws -> [ExecutionResult] {
        return try await executeMultiple(commands: commands, timeout: 60.0)
    }

    /// 读取文本文件
    func readTextFile(path: String) async throws -> String {
        return try await readFile(path: path)
    }

    /// 写入文本文件
    func writeTextFile(path: String, content: String) async throws {
        try await writeFile(path: path, content: content)
    }

    /// 检查目录是否存在
    func directoryExists(path: String) async throws -> Bool {
        guard try await fileExists(path: path) else {
            return false
        }
        let files = try await listFiles(path: path)
        return !files.isEmpty || path.hasSuffix("/")
    }

    /// 获取文件大小
    func getFileSize(path: String) async throws -> Int64 {
        let files = try await listFiles(path: (path as NSString).deletingLastPathComponent)
        let fileName = (path as NSString).lastPathComponent
        guard let file = files.first(where: { $0.name == fileName }) else {
            throw SandboxError.fileNotFound(path)
        }
        return file.size
    }

    /// 复制文件
    func copyFile(from source: String, to destination: String) async throws {
        let content = try await readFile(path: source)
        try await writeFile(path: destination, content: content)
    }

    /// 移动文件
    func moveFile(from source: String, to destination: String) async throws {
        try await copyFile(from: source, to: destination)
        try await deleteFile(path: source)
    }
}
