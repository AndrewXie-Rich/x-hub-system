import Foundation

// MARK: - Virtual Path Mapper

/// 虚拟路径映射器
class VirtualPathMapper {
    private static let sandboxBaseDirEnvKey = "XTERMINAL_SANDBOX_BASE_DIR"

    // MARK: - Properties

    /// 虚拟路径前缀
    private let virtualWorkspace = "/mnt/user-data/workspace"
    private let virtualUploads = "/mnt/user-data/uploads"
    private let virtualOutputs = "/mnt/user-data/outputs"

    /// 真实路径
    private let realWorkspace: URL
    private let realUploads: URL
    private let realOutputs: URL

    /// 项目 ID
    private let projectId: UUID

    // MARK: - Initialization

    init(projectId: UUID) throws {
        self.projectId = projectId

        // 构建真实路径。若 App Support 不可写（如受限环境），自动回退到可写目录。
        let baseDir = Self.resolveWritableBaseDirectory()
        let projectDir = baseDir
            .appendingPathComponent("projects")
            .appendingPathComponent(projectId.uuidString)

        self.realWorkspace = projectDir.appendingPathComponent("workspace")
        self.realUploads = projectDir.appendingPathComponent("uploads")
        self.realOutputs = projectDir.appendingPathComponent("outputs")

        // 确保目录存在
        try createDirectoriesIfNeeded()
    }

    // MARK: - Path Conversion

    /// 转换为虚拟路径
    func toVirtual(_ realPath: String) -> String {
        let realURL = URL(fileURLWithPath: realPath)
        let realPathStr = realURL.standardized.path

        // 检查是否在 workspace 中
        if realPathStr.hasPrefix(realWorkspace.path) {
            let relativePath = String(realPathStr.dropFirst(realWorkspace.path.count))
            return virtualWorkspace + relativePath
        }

        // 检查是否在 uploads 中
        if realPathStr.hasPrefix(realUploads.path) {
            let relativePath = String(realPathStr.dropFirst(realUploads.path.count))
            return virtualUploads + relativePath
        }

        // 检查是否在 outputs 中
        if realPathStr.hasPrefix(realOutputs.path) {
            let relativePath = String(realPathStr.dropFirst(realOutputs.path.count))
            return virtualOutputs + relativePath
        }

        // 不在沙箱内，返回原路径
        return realPath
    }

    /// 转换为真实路径
    func toReal(_ virtualPath: String) -> String {
        // 标准化虚拟路径
        let normalizedPath = normalizePath(virtualPath)

        // 检查是否是 workspace 路径
        if normalizedPath.hasPrefix(virtualWorkspace) {
            let relativePath = String(normalizedPath.dropFirst(virtualWorkspace.count))
            return realWorkspace.appendingPathComponent(relativePath).path
        }

        // 检查是否是 uploads 路径
        if normalizedPath.hasPrefix(virtualUploads) {
            let relativePath = String(normalizedPath.dropFirst(virtualUploads.count))
            return realUploads.appendingPathComponent(relativePath).path
        }

        // 检查是否是 outputs 路径
        if normalizedPath.hasPrefix(virtualOutputs) {
            let relativePath = String(normalizedPath.dropFirst(virtualOutputs.count))
            return realOutputs.appendingPathComponent(relativePath).path
        }

        // 如果是相对路径，默认放在 workspace 中
        if !normalizedPath.hasPrefix("/") {
            return realWorkspace.appendingPathComponent(normalizedPath).path
        }

        // 其他情况，返回原路径（可能会被安全检查拦截）
        return normalizedPath
    }

    // MARK: - Path Validation

    /// 验证虚拟路径是否有效
    func isValidVirtualPath(_ path: String) -> Bool {
        let normalizedPath = normalizePath(path)

        // 检查是否以允许的虚拟路径前缀开头
        return normalizedPath.hasPrefix(virtualWorkspace) ||
               normalizedPath.hasPrefix(virtualUploads) ||
               normalizedPath.hasPrefix(virtualOutputs)
    }

    /// 验证真实路径是否在沙箱内
    func isWithinSandbox(_ realPath: String) -> Bool {
        let realURL = URL(fileURLWithPath: realPath)
        let realPathStr = realURL.standardized.path

        // 检查是否在允许的目录中
        return realPathStr.hasPrefix(realWorkspace.path) ||
               realPathStr.hasPrefix(realUploads.path) ||
               realPathStr.hasPrefix(realOutputs.path)
    }

    /// 验证路径是否安全（不包含危险模式）
    func isSafePath(_ path: String) -> Bool {
        let normalizedPath = normalizePath(path)

        // 检查危险模式
        let dangerousPatterns = [
            "..",           // 父目录引用
            "~",            // 用户目录
            "/etc",         // 系统配置
            "/var",         // 系统变量
            "/usr",         // 系统程序
            "/bin",         // 系统二进制
            "/sbin",        // 系统管理二进制
            "/System",      // macOS 系统目录
            "/Library",     // macOS 库目录（除了 Application Support）
            "/Applications" // macOS 应用目录
        ]

        for pattern in dangerousPatterns {
            if normalizedPath.contains(pattern) {
                return false
            }
        }

        return true
    }

    /// 验证并转换路径
    func validateAndConvert(_ virtualPath: String) throws -> String {
        // 1. 检查路径安全性
        guard isSafePath(virtualPath) else {
            throw SandboxError.invalidPath("路径包含危险模式: \(virtualPath)")
        }

        // 2. 转换为真实路径
        let realPath = toReal(virtualPath)

        // 3. 检查是否在沙箱内
        guard isWithinSandbox(realPath) else {
            throw SandboxError.pathOutsideSandbox(realPath)
        }

        return realPath
    }

    // MARK: - Path Utilities

    /// 标准化路径
    private func normalizePath(_ path: String) -> String {
        // 移除多余的斜杠
        var normalized = path.replacingOccurrences(of: "//+", with: "/", options: .regularExpression)

        // 移除末尾的斜杠（除非是根路径）
        if normalized.count > 1 && normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }

        return normalized
    }

    /// 获取相对路径
    func getRelativePath(from base: String, to target: String) -> String {
        let baseComponents = base.split(separator: "/")
        let targetComponents = target.split(separator: "/")

        // 找到公共前缀
        var commonCount = 0
        for (baseComp, targetComp) in zip(baseComponents, targetComponents) {
            if baseComp == targetComp {
                commonCount += 1
            } else {
                break
            }
        }

        // 构建相对路径
        let upCount = baseComponents.count - commonCount
        let upPath = Array(repeating: "..", count: upCount).joined(separator: "/")

        let downPath = targetComponents.dropFirst(commonCount).joined(separator: "/")

        if upPath.isEmpty {
            return downPath
        } else if downPath.isEmpty {
            return upPath
        } else {
            return upPath + "/" + downPath
        }
    }

    /// 连接路径
    func joinPaths(_ components: String...) -> String {
        return components
            .filter { !$0.isEmpty }
            .joined(separator: "/")
            .replacingOccurrences(of: "//+", with: "/", options: .regularExpression)
    }

    /// 获取父目录
    func getParentDirectory(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.deletingLastPathComponent().path
    }

    /// 获取文件名
    func getFileName(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent
    }

    /// 获取文件扩展名
    func getFileExtension(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.pathExtension
    }

    // MARK: - Directory Management

    /// 创建必要的目录
    private func createDirectoriesIfNeeded() throws {
        let fileManager = FileManager.default

        // 创建 workspace 目录
        if !fileManager.fileExists(atPath: realWorkspace.path) {
            try fileManager.createDirectory(
                at: realWorkspace,
                withIntermediateDirectories: true
            )
        }

        // 创建 uploads 目录
        if !fileManager.fileExists(atPath: realUploads.path) {
            try fileManager.createDirectory(
                at: realUploads,
                withIntermediateDirectories: true
            )
        }

        // 创建 outputs 目录
        if !fileManager.fileExists(atPath: realOutputs.path) {
            try fileManager.createDirectory(
                at: realOutputs,
                withIntermediateDirectories: true
            )
        }
    }

    private static func resolveWritableBaseDirectory() -> URL {
        let fm = FileManager.default
        for candidate in candidateBaseDirectories() {
            if canUseBaseDirectory(candidate, fileManager: fm) {
                return candidate
            }
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("XTerminalSandbox", isDirectory: true)
    }

    private static func candidateBaseDirectories() -> [URL] {
        var out: [URL] = []
        let env = (ProcessInfo.processInfo.environment[sandboxBaseDirEnvKey] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !env.isEmpty {
            let expanded = NSString(string: env).expandingTildeInPath
            out.append(URL(fileURLWithPath: expanded, isDirectory: true))
        }

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            out.append(appSupport.appendingPathComponent("XTerminal", isDirectory: true))
        }

        out.append(
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("XTerminalSandbox", isDirectory: true)
        )
        return out
    }

    private static func canUseBaseDirectory(_ dir: URL, fileManager: FileManager) -> Bool {
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let probe = dir.appendingPathComponent(".write_probe_\(UUID().uuidString)")
            try Data("ok".utf8).write(to: probe, options: .atomic)
            try? fileManager.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    /// 获取目录大小
    func getDirectorySize(_ path: String) throws -> Int64 {
        let realPath = try validateAndConvert(path)
        let fileManager = FileManager.default

        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(atPath: realPath) {
            for case let file as String in enumerator {
                let filePath = (realPath as NSString).appendingPathComponent(file)
                if let attributes = try? fileManager.attributesOfItem(atPath: filePath) {
                    totalSize += attributes[.size] as? Int64 ?? 0
                }
            }
        }

        return totalSize
    }

    /// 清空目录
    func clearDirectory(_ path: String) throws {
        let realPath = try validateAndConvert(path)
        let fileManager = FileManager.default

        if let enumerator = fileManager.enumerator(atPath: realPath) {
            for case let file as String in enumerator {
                let filePath = (realPath as NSString).appendingPathComponent(file)
                try? fileManager.removeItem(atPath: filePath)
            }
        }
    }

    // MARK: - Path Information

    /// 获取路径信息
    func getPathInfo(_ path: String) throws -> PathInfo {
        let realPath = try validateAndConvert(path)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: realPath) else {
            throw SandboxError.fileNotFound(path)
        }

        let attributes = try fileManager.attributesOfItem(atPath: realPath)

        return PathInfo(
            virtualPath: path,
            realPath: realPath,
            size: attributes[.size] as? Int64 ?? 0,
            isDirectory: (attributes[.type] as? FileAttributeType) == .typeDirectory,
            isSymbolicLink: (attributes[.type] as? FileAttributeType) == .typeSymbolicLink,
            modifiedAt: attributes[.modificationDate] as? Date ?? Date(),
            createdAt: attributes[.creationDate] as? Date ?? Date(),
            permissions: String(format: "%o", (attributes[.posixPermissions] as? Int) ?? 0)
        )
    }

    // MARK: - Workspace Paths

    /// 获取 workspace 虚拟路径
    var workspaceVirtualPath: String {
        return virtualWorkspace
    }

    /// 获取 uploads 虚拟路径
    var uploadsVirtualPath: String {
        return virtualUploads
    }

    /// 获取 outputs 虚拟路径
    var outputsVirtualPath: String {
        return virtualOutputs
    }

    /// 获取 workspace 真实路径
    var workspaceRealPath: String {
        return realWorkspace.path
    }

    /// 获取 uploads 真实路径
    var uploadsRealPath: String {
        return realUploads.path
    }

    /// 获取 outputs 真实路径
    var outputsRealPath: String {
        return realOutputs.path
    }
}

// MARK: - Path Info

/// 路径信息
struct PathInfo {
    let virtualPath: String
    let realPath: String
    let size: Int64
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let modifiedAt: Date
    let createdAt: Date
    let permissions: String

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - Path Mapper Extensions

extension VirtualPathMapper {
    /// 批量转换虚拟路径
    func toRealBatch(_ virtualPaths: [String]) -> [String] {
        return virtualPaths.map { toReal($0) }
    }

    /// 批量转换真实路径
    func toVirtualBatch(_ realPaths: [String]) -> [String] {
        return realPaths.map { toVirtual($0) }
    }

    /// 批量验证路径
    func validateBatch(_ virtualPaths: [String]) throws -> [String] {
        return try virtualPaths.map { try validateAndConvert($0) }
    }

    /// 查找文件
    func findFiles(in directory: String, matching pattern: String) throws -> [String] {
        let realPath = try validateAndConvert(directory)
        let fileManager = FileManager.default

        var matchingFiles: [String] = []

        if let enumerator = fileManager.enumerator(atPath: realPath) {
            for case let file as String in enumerator {
                if file.range(of: pattern, options: .regularExpression) != nil {
                    let virtualPath = toVirtual((realPath as NSString).appendingPathComponent(file))
                    matchingFiles.append(virtualPath)
                }
            }
        }

        return matchingFiles
    }

    /// 获取目录树
    func getDirectoryTree(_ path: String, maxDepth: Int = 3) throws -> DirectoryNode {
        let realPath = try validateAndConvert(path)
        let fileManager = FileManager.default

        func buildTree(at path: String, depth: Int) -> DirectoryNode {
            let name = (path as NSString).lastPathComponent
            let virtualPath = toVirtual(path)

            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: path, isDirectory: &isDir)

            if !isDir.boolValue || depth >= maxDepth {
                return DirectoryNode(name: name, path: virtualPath, isDirectory: isDir.boolValue, children: [])
            }

            var children: [DirectoryNode] = []
            if let contents = try? fileManager.contentsOfDirectory(atPath: path) {
                for item in contents.sorted() {
                    let itemPath = (path as NSString).appendingPathComponent(item)
                    let childNode = buildTree(at: itemPath, depth: depth + 1)
                    children.append(childNode)
                }
            }

            return DirectoryNode(name: name, path: virtualPath, isDirectory: true, children: children)
        }

        return buildTree(at: realPath, depth: 0)
    }

    /// 格式化目录树
    func formatDirectoryTree(_ node: DirectoryNode, prefix: String = "", isLast: Bool = true) -> String {
        var result = ""

        // 当前节点
        let connector = isLast ? "└── " : "├── "
        let icon = node.isDirectory ? "📁" : "📄"
        result += prefix + connector + icon + " " + node.name + "\n"

        // 子节点
        if !node.children.isEmpty {
            let childPrefix = prefix + (isLast ? "    " : "│   ")
            for (index, child) in node.children.enumerated() {
                let isLastChild = index == node.children.count - 1
                result += formatDirectoryTree(child, prefix: childPrefix, isLast: isLastChild)
            }
        }

        return result
    }
}

// MARK: - Directory Node

/// 目录节点
struct DirectoryNode {
    let name: String
    let path: String
    let isDirectory: Bool
    let children: [DirectoryNode]

    var fileCount: Int {
        if !isDirectory {
            return 1
        }
        return children.reduce(0) { $0 + $1.fileCount }
    }

    var directoryCount: Int {
        if !isDirectory {
            return 0
        }
        return 1 + children.reduce(0) { $0 + $1.directoryCount }
    }
}

// MARK: - Path Constants

extension VirtualPathMapper {
    /// 虚拟路径常量
    enum VirtualPath {
        static let workspace = "/mnt/user-data/workspace"
        static let uploads = "/mnt/user-data/uploads"
        static let outputs = "/mnt/user-data/outputs"
    }

    /// 路径分隔符
    static let separator = "/"

    /// 最大路径长度
    static let maxPathLength = 4096
}
