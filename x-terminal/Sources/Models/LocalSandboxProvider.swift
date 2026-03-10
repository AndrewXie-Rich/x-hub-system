import Foundation

// MARK: - Local Sandbox Provider

/// 本地沙箱提供者
@MainActor
class LocalSandboxProvider: SandboxProvider {
    // MARK: - Properties

    private let projectId: UUID
    private let pathMapper: VirtualPathMapper
    private let configuration: SandboxConfiguration
    private var status: SandboxStatus = .uninitialized
    private var activeProcesses: [Process] = []

    // MARK: - SandboxProvider Protocol Properties

    var isInitialized: Bool {
        return status == .ready || status == .busy
    }

    var workingDirectory: String {
        return pathMapper.workspaceVirtualPath
    }

    var uploadsDirectory: String {
        return pathMapper.uploadsVirtualPath
    }

    var outputsDirectory: String {
        return pathMapper.outputsVirtualPath
    }

    // MARK: - Initialization

    init(projectId: UUID, configuration: SandboxConfiguration = .default) throws {
        self.projectId = projectId
        self.configuration = configuration
        self.pathMapper = try VirtualPathMapper(projectId: projectId)
    }

    // MARK: - Environment Management

    func initialize() async throws {
        guard status == .uninitialized else {
            throw SandboxError.alreadyInitialized
        }

        status = .initializing

        do {
            // 验证目录存在
            let fileManager = FileManager.default
            let workspacePath = pathMapper.workspaceRealPath
            let uploadsPath = pathMapper.uploadsRealPath
            let outputsPath = pathMapper.outputsRealPath

            guard fileManager.fileExists(atPath: workspacePath) else {
                throw SandboxError.initializationFailed("Workspace 目录不存在")
            }

            guard fileManager.fileExists(atPath: uploadsPath) else {
                throw SandboxError.initializationFailed("Uploads 目录不存在")
            }

            guard fileManager.fileExists(atPath: outputsPath) else {
                throw SandboxError.initializationFailed("Outputs 目录不存在")
            }

            status = .ready
        } catch {
            status = .error
            throw SandboxError.initializationFailed(error.localizedDescription)
        }
    }

    func cleanup() async throws {
        guard isInitialized else {
            return
        }

        status = .cleaning

        // 终止所有活动进程
        for process in activeProcesses {
            if process.isRunning {
                process.terminate()
            }
        }
        activeProcesses.removeAll()

        // 清理临时文件（可选）
        // try pathMapper.clearDirectory(pathMapper.workspaceVirtualPath)

        status = .terminated
    }

    // MARK: - Command Execution

    func execute(command: String, timeout: TimeInterval) async throws -> ExecutionResult {
        guard isInitialized else {
            throw SandboxError.notInitialized
        }

        // 验证超时时间
        let actualTimeout = min(timeout, configuration.maxTimeout)

        // 检查命令是否被禁止
        try validateCommand(command)

        // 设置状态为忙碌
        let previousStatus = status
        status = .busy
        defer { status = previousStatus }

        let startTime = Date()

        do {
            // 创建进程
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]

            // 设置工作目录
            process.currentDirectoryURL = URL(fileURLWithPath: pathMapper.workspaceRealPath)

            // 设置环境变量
            var environment = ProcessInfo.processInfo.environment
            environment.merge(configuration.environmentVariables) { _, new in new }
            process.environment = environment

            // 创建管道
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // 启动进程
            try process.run()
            activeProcesses.append(process)

            // 等待进程完成或超时
            let completed = await waitForProcess(process, timeout: actualTimeout)

            // 读取输出
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            // 移除进程
            activeProcesses.removeAll { $0 === process }

            // 检查是否超时
            if !completed {
                process.terminate()
                throw SandboxError.commandTimeout
            }

            let duration = Date().timeIntervalSince(startTime)

            return ExecutionResult(
                stdout: stdout,
                stderr: stderr,
                exitCode: Int(process.terminationStatus),
                duration: duration
            )

        } catch let error as SandboxError {
            throw error
        } catch {
            throw SandboxError.commandExecutionFailed(error.localizedDescription)
        }
    }

    func executeMultiple(commands: [String], timeout: TimeInterval) async throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []

        for command in commands {
            let result = try await execute(command: command, timeout: timeout)
            results.append(result)

            // 如果命令失败，停止执行后续命令
            if !result.isSuccess {
                break
            }
        }

        return results
    }

    // MARK: - File Operations

    func readFile(path: String) async throws -> String {
        guard isInitialized else {
            throw SandboxError.notInitialized
        }

        do {
            let realPath = try pathMapper.validateAndConvert(path)

            guard FileManager.default.fileExists(atPath: realPath) else {
                throw SandboxError.fileNotFound(path)
            }

            let content = try String(contentsOfFile: realPath, encoding: .utf8)
            return content

        } catch let error as SandboxError {
            throw error
        } catch {
            throw SandboxError.fileReadFailed(error.localizedDescription)
        }
    }

    func writeFile(path: String, content: String) async throws {
        guard isInitialized else {
            throw SandboxError.notInitialized
        }

        do {
            let realPath = try pathMapper.validateAndConvert(path)

            // 确保父目录存在
            let parentDir = (realPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: parentDir,
                withIntermediateDirectories: true
            )

            // 写入文件
            try content.write(toFile: realPath, atomically: true, encoding: .utf8)

        } catch let error as SandboxError {
            throw error
        } catch {
            throw SandboxError.fileWriteFailed(error.localizedDescription)
        }
    }

    func listFiles(path: String) async throws -> [FileInfo] {
        guard isInitialized else {
            throw SandboxError.notInitialized
        }

        do {
            let realPath = try pathMapper.validateAndConvert(path)
            let fileManager = FileManager.default

            guard fileManager.fileExists(atPath: realPath) else {
                throw SandboxError.fileNotFound(path)
            }

            let contents = try fileManager.contentsOfDirectory(atPath: realPath)
            var fileInfos: [FileInfo] = []

            for item in contents {
                let itemPath = (realPath as NSString).appendingPathComponent(item)
                let attributes = try fileManager.attributesOfItem(atPath: itemPath)

                let fileInfo = FileInfo(
                    name: item,
                    path: pathMapper.toVirtual(itemPath),
                    size: attributes[.size] as? Int64 ?? 0,
                    isDirectory: (attributes[.type] as? FileAttributeType) == .typeDirectory,
                    isSymbolicLink: (attributes[.type] as? FileAttributeType) == .typeSymbolicLink,
                    modifiedAt: attributes[.modificationDate] as? Date ?? Date(),
                    createdAt: attributes[.creationDate] as? Date ?? Date(),
                    permissions: String(format: "%o", (attributes[.posixPermissions] as? Int) ?? 0)
                )

                fileInfos.append(fileInfo)
            }

            return fileInfos.sorted { $0.name < $1.name }

        } catch let error as SandboxError {
            throw error
        } catch {
            throw SandboxError.fileReadFailed(error.localizedDescription)
        }
    }

    func deleteFile(path: String) async throws {
        guard isInitialized else {
            throw SandboxError.notInitialized
        }

        do {
            let realPath = try pathMapper.validateAndConvert(path)

            guard FileManager.default.fileExists(atPath: realPath) else {
                throw SandboxError.fileNotFound(path)
            }

            try FileManager.default.removeItem(atPath: realPath)

        } catch let error as SandboxError {
            throw error
        } catch {
            throw SandboxError.fileWriteFailed(error.localizedDescription)
        }
    }

    func createDirectory(path: String) async throws {
        guard isInitialized else {
            throw SandboxError.notInitialized
        }

        do {
            let realPath = try pathMapper.validateAndConvert(path)

            try FileManager.default.createDirectory(
                atPath: realPath,
                withIntermediateDirectories: true
            )

        } catch let error as SandboxError {
            throw error
        } catch {
            throw SandboxError.directoryCreationFailed(error.localizedDescription)
        }
    }

    func fileExists(path: String) async throws -> Bool {
        guard isInitialized else {
            throw SandboxError.notInitialized
        }

        let realPath = try pathMapper.validateAndConvert(path)
        return FileManager.default.fileExists(atPath: realPath)
    }

    // MARK: - Path Mapping

    func toVirtualPath(_ realPath: String) -> String {
        return pathMapper.toVirtual(realPath)
    }

    func toRealPath(_ virtualPath: String) -> String {
        return pathMapper.toReal(virtualPath)
    }

    // MARK: - Resource Management

    func getResourceUsage() async throws -> ResourceUsage {
        guard isInitialized else {
            throw SandboxError.notInitialized
        }

        // 获取 CPU 使用率
        let cpuUsage = getCPUUsage()

        // 获取内存使用量
        let memoryUsage = getMemoryUsage()

        // 获取磁盘使用量
        let diskUsage = try getDiskUsage()

        // 获取进程数量
        let processCount = activeProcesses.count

        return ResourceUsage(
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            diskUsage: diskUsage,
            processCount: processCount
        )
    }

    // MARK: - Private Helper Methods

    /// 等待进程完成
    private func waitForProcess(_ process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 秒
        }

        return !process.isRunning
    }

    /// 验证命令
    private func validateCommand(_ command: String) throws {
        // 检查是否在黑名单中
        for blockedCommand in configuration.blockedCommands {
            if command.contains(blockedCommand) {
                throw SandboxError.permissionDenied("命令被禁止: \(blockedCommand)")
            }
        }

        // 如果有白名单，检查是否在白名单中
        if !configuration.allowedCommands.isEmpty {
            let commandName = command.components(separatedBy: " ").first ?? ""
            if !configuration.allowedCommands.contains(commandName) {
                throw SandboxError.permissionDenied("命令不在白名单中: \(commandName)")
            }
        }
    }

    /// 获取 CPU 使用率
    private func getCPUUsage() -> Double {
        var usage: Double = 0.0

        for process in activeProcesses {
            if process.isRunning {
                // 简单估算：每个运行的进程占用 10% CPU
                usage += 10.0
            }
        }

        return min(usage, 100.0)
    }

    /// 获取内存使用量
    private func getMemoryUsage() -> Int64 {
        var usage: Int64 = 0

        for process in activeProcesses {
            if process.isRunning {
                // 简单估算：每个进程占用 50MB
                usage += 50 * 1024 * 1024
            }
        }

        return usage
    }

    /// 获取磁盘使用量
    private func getDiskUsage() throws -> Int64 {
        var totalSize: Int64 = 0

        // 计算 workspace 大小
        totalSize += try pathMapper.getDirectorySize(pathMapper.workspaceVirtualPath)

        // 计算 uploads 大小
        totalSize += try pathMapper.getDirectorySize(pathMapper.uploadsVirtualPath)

        // 计算 outputs 大小
        totalSize += try pathMapper.getDirectorySize(pathMapper.outputsVirtualPath)

        return totalSize
    }
}

// MARK: - Local Sandbox Provider Extensions

extension LocalSandboxProvider {
    /// 执行 shell 脚本
    func executeScript(_ script: String, timeout: TimeInterval = 60.0) async throws -> ExecutionResult {
        // 创建临时脚本文件
        let scriptPath = pathMapper.workspaceVirtualPath + "/temp_script.sh"
        try await writeFile(path: scriptPath, content: script)

        // 执行脚本
        let result = try await execute(command: "bash \(scriptPath)", timeout: timeout)

        // 删除临时文件
        try? await deleteFile(path: scriptPath)

        return result
    }

    /// 执行 Python 脚本
    func executePythonScript(_ script: String, timeout: TimeInterval = 60.0) async throws -> ExecutionResult {
        let scriptPath = pathMapper.workspaceVirtualPath + "/temp_script.py"
        try await writeFile(path: scriptPath, content: script)

        let result = try await execute(command: "python3 \(scriptPath)", timeout: timeout)

        try? await deleteFile(path: scriptPath)

        return result
    }

    /// 执行 Node.js 脚本
    func executeNodeScript(_ script: String, timeout: TimeInterval = 60.0) async throws -> ExecutionResult {
        let scriptPath = pathMapper.workspaceVirtualPath + "/temp_script.js"
        try await writeFile(path: scriptPath, content: script)

        let result = try await execute(command: "node \(scriptPath)", timeout: timeout)

        try? await deleteFile(path: scriptPath)

        return result
    }

    /// 批量读取文件
    func readFiles(_ paths: [String]) async throws -> [String: String] {
        var contents: [String: String] = [:]

        for path in paths {
            let content = try await readFile(path: path)
            contents[path] = content
        }

        return contents
    }

    /// 批量写入文件
    func writeFiles(_ files: [String: String]) async throws {
        for (path, content) in files {
            try await writeFile(path: path, content: content)
        }
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

    /// 搜索文件
    func searchFiles(in directory: String, pattern: String) async throws -> [String] {
        return try pathMapper.findFiles(in: directory, matching: pattern)
    }

    /// 获取目录树
    func getDirectoryTree(_ path: String = "/mnt/user-data/workspace") async throws -> String {
        let tree = try pathMapper.getDirectoryTree(path)
        return pathMapper.formatDirectoryTree(tree)
    }

    /// 压缩目录
    func compressDirectory(_ path: String, outputPath: String) async throws -> ExecutionResult {
        let realPath = try pathMapper.validateAndConvert(path)
        let realOutputPath = try pathMapper.validateAndConvert(outputPath)

        let command = "tar -czf \(realOutputPath) -C \(realPath) ."
        return try await execute(command: command, timeout: 120.0)
    }

    /// 解压文件
    func extractArchive(_ archivePath: String, to destination: String) async throws -> ExecutionResult {
        let realArchivePath = try pathMapper.validateAndConvert(archivePath)
        let realDestination = try pathMapper.validateAndConvert(destination)

        let command = "tar -xzf \(realArchivePath) -C \(realDestination)"
        return try await execute(command: command, timeout: 120.0)
    }

    /// 获取文件哈希
    func getFileHash(_ path: String, algorithm: String = "sha256") async throws -> String {
        let command = "\(algorithm)sum \(path) | awk '{print $1}'"
        let result = try await execute(command: command, timeout: 10.0)

        guard result.isSuccess else {
            throw SandboxError.commandExecutionFailed("无法计算文件哈希")
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 监控命令执行
    func executeWithMonitoring(
        command: String,
        timeout: TimeInterval,
        onOutput: @escaping (String) -> Void
    ) async throws -> ExecutionResult {
        // 简化版本：直接执行命令
        // TODO: 实现实时输出监控
        let result = try await execute(command: command, timeout: timeout)
        onOutput(result.stdout)
        return result
    }

    /// 获取沙箱统计信息
    func getStatistics() async throws -> SandboxStatistics {
        let resourceUsage = try await getResourceUsage()
        let workspaceSize = try pathMapper.getDirectorySize(pathMapper.workspaceVirtualPath)
        let uploadsSize = try pathMapper.getDirectorySize(pathMapper.uploadsVirtualPath)
        let outputsSize = try pathMapper.getDirectorySize(pathMapper.outputsVirtualPath)

        return SandboxStatistics(
            status: status,
            resourceUsage: resourceUsage,
            workspaceSize: workspaceSize,
            uploadsSize: uploadsSize,
            outputsSize: outputsSize,
            activeProcessCount: activeProcesses.count
        )
    }
}

// MARK: - Sandbox Statistics

/// 沙箱统计信息
struct SandboxStatistics {
    let status: SandboxStatus
    let resourceUsage: ResourceUsage
    let workspaceSize: Int64
    let uploadsSize: Int64
    let outputsSize: Int64
    let activeProcessCount: Int

    var totalSize: Int64 {
        return workspaceSize + uploadsSize + outputsSize
    }

    var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }

    var summary: String {
        var text = "沙箱统计信息\n"
        text += "状态: \(status.rawValue)\n"
        text += "CPU 使用率: \(String(format: "%.1f%%", resourceUsage.cpuUsage))\n"
        text += "内存使用: \(resourceUsage.formattedMemory)\n"
        text += "磁盘使用: \(formattedTotalSize)\n"
        text += "活动进程: \(activeProcessCount)\n"
        return text
    }
}

// MARK: - Command Builder

/// 命令构建器
struct CommandBuilder {
    private var components: [String] = []

    mutating func add(_ component: String) {
        components.append(component)
    }

    mutating func addFlag(_ flag: String) {
        components.append(flag)
    }

    mutating func addOption(_ option: String, value: String) {
        components.append("\(option) \(value)")
    }

    func build() -> String {
        return components.joined(separator: " ")
    }

    static func ls(path: String = ".", options: String = "-la") -> String {
        return "ls \(options) \(path)"
    }

    static func cat(path: String) -> String {
        return "cat \(path)"
    }

    static func grep(pattern: String, path: String, options: String = "") -> String {
        return "grep \(options) '\(pattern)' \(path)"
    }

    static func find(path: String = ".", name: String? = nil, type: String? = nil) -> String {
        var command = "find \(path)"
        if let name = name {
            command += " -name '\(name)'"
        }
        if let type = type {
            command += " -type \(type)"
        }
        return command
    }
}
