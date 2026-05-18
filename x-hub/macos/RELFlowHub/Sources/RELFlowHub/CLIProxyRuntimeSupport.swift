import Foundation
import Security
import RELFlowHubCore

enum CLIProxyRuntimeSupport {
    static let executableName = "cli-proxy-api"
    static let configName = "config.yaml"
    private static let runtimeSearchRootName = "CLIProxyAPI-main"
    private static let runtimeSearchRelativePath = "source/CLIProxyAPI-main"
    private static let settingsFileName = "hub_cliproxy_runtime.json"
    private static let probeTimeoutSec: TimeInterval = 1.6

    private static let retainedProcessLock = NSLock()
    nonisolated(unsafe) private static var retainedProcesses: [RetainedLaunch] = []

    struct Settings: Codable, Equatable, Sendable {
        var packageDirectoryPath: String
        var preferDetectedPackage: Bool
        var useLocalModel: Bool

        init(
            packageDirectoryPath: String = "",
            preferDetectedPackage: Bool = true,
            useLocalModel: Bool = true
        ) {
            self.packageDirectoryPath = Self.normalizedPath(packageDirectoryPath)
            self.preferDetectedPackage = preferDetectedPackage
            self.useLocalModel = useLocalModel
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            packageDirectoryPath = Self.normalizedPath(
                (try? container.decode(String.self, forKey: .packageDirectoryPath)) ?? ""
            )
            preferDetectedPackage = (try? container.decode(Bool.self, forKey: .preferDetectedPackage)) ?? true
            useLocalModel = (try? container.decode(Bool.self, forKey: .useLocalModel)) ?? true
        }

        func normalized() -> Settings {
            Settings(
                packageDirectoryPath: packageDirectoryPath,
                preferDetectedPackage: preferDetectedPackage,
                useLocalModel: useLocalModel
            )
        }

        private static func normalizedPath(_ rawValue: String) -> String {
            rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    enum PackageStatus: String, Equatable, Sendable {
        case detected
        case notFound
        case missingExecutable
        case missingConfig
    }

    enum ManagementStatus: Equatable, Sendable {
        case unknown
        case waitingForKey
        case keyValid(authCount: Int)
        case keyInvalid
        case unavailable
        case error(String)
    }

    struct Probe: Equatable, Sendable {
        var explicitPackageDirectoryPath: String
        var detectedPackageDirectoryPath: String
        var resolvedPackageDirectoryPath: String
        var binaryPath: String
        var configPath: String
        var packageStatus: PackageStatus
        var usedDetectedPackage: Bool
        var serviceRunning: Bool
        var managementStatus: ManagementStatus
        var probedAtMs: Int64

        init(
            explicitPackageDirectoryPath: String = "",
            detectedPackageDirectoryPath: String = "",
            resolvedPackageDirectoryPath: String = "",
            binaryPath: String = "",
            configPath: String = "",
            packageStatus: PackageStatus = .notFound,
            usedDetectedPackage: Bool = false,
            serviceRunning: Bool = false,
            managementStatus: ManagementStatus = .unknown,
            probedAtMs: Int64 = 0
        ) {
            self.explicitPackageDirectoryPath = explicitPackageDirectoryPath
            self.detectedPackageDirectoryPath = detectedPackageDirectoryPath
            self.resolvedPackageDirectoryPath = resolvedPackageDirectoryPath
            self.binaryPath = binaryPath
            self.configPath = configPath
            self.packageStatus = packageStatus
            self.usedDetectedPackage = usedDetectedPackage
            self.serviceRunning = serviceRunning
            self.managementStatus = managementStatus
            self.probedAtMs = probedAtMs
        }
    }

    struct LaunchResult: Equatable, Sendable {
        var pid: Int32
        var alreadyRunning: Bool
        var healthConfirmed: Bool
        var usedPackageDirectoryPath: String
    }

    enum ConfigRecommendationKind: String, CaseIterable, Identifiable, Sendable {
        case bindLocalHost
        case keepManagementLocalOnly
        case keepControlPanelEnabled
        case disablePanelAutoUpdate
        case disableUsageStatistics
        case disableLoggingToFile

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bindLocalHost:
                return "只监听本机"
            case .keepManagementLocalOnly:
                return "管理端仅限本机"
            case .keepControlPanelEnabled:
                return "保留控制台面板"
            case .disablePanelAutoUpdate:
                return "关闭面板自动更新"
            case .disableUsageStatistics:
                return "关闭使用统计"
            case .disableLoggingToFile:
                return "关闭文件日志"
            }
        }

        var detail: String {
            switch self {
            case .bindLocalHost:
                return "把 host 固定到 127.0.0.1，避免把 CLIProxy 服务暴露到局域网。"
            case .keepManagementLocalOnly:
                return "remote-management.allow-remote 保持 false，避免远端管理入口额外暴露。"
            case .keepControlPanelEnabled:
                return "保留 management.html，Hub 发起 OAuth 和人工排障都要用到。"
            case .disablePanelAutoUpdate:
                return "禁用 management 面板的 GitHub 周期更新，减少后台轮询和网络扰动。"
            case .disableUsageStatistics:
                return "关闭 CLIProxy 内置使用统计聚合，维持更轻的常驻开销。"
            case .disableLoggingToFile:
                return "关闭轮转文件日志，避免常驻写盘。"
            }
        }

        var recommendedValueDisplay: String {
            switch self {
            case .bindLocalHost:
                return "127.0.0.1"
            case .keepManagementLocalOnly, .disableUsageStatistics, .disableLoggingToFile:
                return "false"
            case .keepControlPanelEnabled:
                return "false"
            case .disablePanelAutoUpdate:
                return "true"
            }
        }
    }

    struct ConfigRecommendation: Identifiable, Equatable, Sendable {
        var kind: ConfigRecommendationKind
        var satisfied: Bool
        var currentValueDisplay: String
        var recommendedValueDisplay: String

        var id: String { kind.id }
    }

    struct ConfigAudit: Equatable, Sendable {
        var configPath: String
        var recommendations: [ConfigRecommendation]
        var inspectedAtMs: Int64

        static let empty = ConfigAudit(
            configPath: "",
            recommendations: [],
            inspectedAtMs: 0
        )

        var unresolvedRecommendations: [ConfigRecommendation] {
            recommendations.filter { !$0.satisfied }
        }

        var unresolvedCount: Int {
            unresolvedRecommendations.count
        }

        var satisfiedCount: Int {
            recommendations.count - unresolvedCount
        }
    }

    struct ConfigPatchResult: Equatable, Sendable {
        var configPath: String
        var backupPath: String
        var updatedKinds: [ConfigRecommendationKind]

        var changedCount: Int {
            updatedKinds.count
        }
    }

    struct ManagementKeyRotationResult: Equatable, Sendable {
        var newKey: String
        var configPath: String
        var backupPath: String
    }

    enum SupportError: LocalizedError {
        case packageNotFound
        case missingExecutable
        case missingConfig
        case processLaunchFailed(String)
        case exitedBeforeReady
        case configReadFailed(String)
        case configWriteFailed(String)
        case keyGenerationFailed(String)

        var errorDescription: String? {
            switch self {
            case .packageNotFound:
                return "还没有找到可用的 CLIProxy 发行包目录。"
            case .missingExecutable:
                return "CLIProxy 目录里缺少 cli-proxy-api 可执行文件。"
            case .missingConfig:
                return "CLIProxy 目录里缺少 config.yaml。"
            case .processLaunchFailed(let detail):
                return detail.isEmpty ? "CLIProxy 启动失败。" : "CLIProxy 启动失败：\(detail)"
            case .exitedBeforeReady:
                return "CLIProxy 进程很快退出了，请检查 config.yaml 或本机运行环境。"
            case .configReadFailed(let detail):
                return detail.isEmpty ? "CLIProxy config.yaml 读取失败。" : "CLIProxy config.yaml 读取失败：\(detail)"
            case .configWriteFailed(let detail):
                return detail.isEmpty ? "CLIProxy config.yaml 写入失败。" : "CLIProxy config.yaml 写入失败：\(detail)"
            case .keyGenerationFailed(let detail):
                return detail.isEmpty ? "CLIProxy management key 生成失败。" : "CLIProxy management key 生成失败：\(detail)"
            }
        }
    }

    private struct ResolvedPackage {
        var explicitURL: URL?
        var detectedURL: URL?
        var resolvedURL: URL?
        var usedDetected: Bool
    }

    private struct HTTPResult {
        var statusCode: Int
        var data: Data
    }

    private enum BoolConfigState: Equatable {
        case value(Bool)
        case commented(Bool)
        case missing
    }

    private struct RetainedLaunch {
        var process: Process
        var sink: FileHandle
    }

    static func loadSettings() -> Settings {
        let url = settingsURL()
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return settings.normalized()
    }

    @discardableResult
    static func saveSettings(_ settings: Settings) -> Bool {
        let normalized = settings.normalized()
        guard let data = try? JSONEncoder().encode(normalized) else {
            return false
        }
        do {
            try data.write(to: settingsURL(), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func detectPackageDirectoryURL(searchRoots: [URL]? = nil) -> URL? {
        let roots = searchRoots ?? defaultSearchRoots()
        var candidates: [URL] = []
        for root in roots {
            candidates.append(contentsOf: packageCandidates(in: root))
        }

        candidates.sort { lhs, rhs in
            let lhsDate = modificationDate(for: lhs)
            let rhsDate = modificationDate(for: rhs)
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.path < rhs.path
        }

        return candidates.first
    }

    static func packageDirectoryURL(for settings: Settings) -> URL? {
        resolvePackage(settings.normalized()).resolvedURL
    }

    static func configURL(for settings: Settings) -> URL? {
        packageDirectoryURL(for: settings)?.appendingPathComponent(configName)
    }

    static func launchCommandSummary(for settings: Settings) -> String {
        var parts = ["./\(executableName)", "--config", configName]
        if settings.useLocalModel {
            parts.append("--local-model")
        }
        return parts.joined(separator: " ")
    }

    static func auditConfig(settings: Settings) -> ConfigAudit {
        let normalizedSettings = settings.normalized()
        let configPath = configURL(for: normalizedSettings)?.path ?? ""
        guard let configURL = configURL(for: normalizedSettings),
              let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return ConfigAudit(
                configPath: configPath,
                recommendations: [],
                inspectedAtMs: currentTimestampMs()
            )
        }

        let hostValue = hostConfigValue(in: content)
        let allowRemote = boolConfigState(in: content, key: "allow-remote")
        let disableControlPanel = boolConfigState(in: content, key: "disable-control-panel")
        let disablePanelAutoUpdate = boolConfigState(in: content, key: "disable-auto-update-panel")
        let usageStatistics = boolConfigState(in: content, key: "usage-statistics-enabled")
        let loggingToFile = boolConfigState(in: content, key: "logging-to-file")

        let recommendations: [ConfigRecommendation] = [
            ConfigRecommendation(
                kind: .bindLocalHost,
                satisfied: hostSatisfiesRecommendation(hostValue),
                currentValueDisplay: hostValueDisplay(hostValue),
                recommendedValueDisplay: ConfigRecommendationKind.bindLocalHost.recommendedValueDisplay
            ),
            ConfigRecommendation(
                kind: .keepManagementLocalOnly,
                satisfied: boolState(allowRemote, equals: false),
                currentValueDisplay: boolStateDisplay(allowRemote),
                recommendedValueDisplay: ConfigRecommendationKind.keepManagementLocalOnly.recommendedValueDisplay
            ),
            ConfigRecommendation(
                kind: .keepControlPanelEnabled,
                satisfied: boolState(disableControlPanel, equals: false),
                currentValueDisplay: boolStateDisplay(disableControlPanel),
                recommendedValueDisplay: ConfigRecommendationKind.keepControlPanelEnabled.recommendedValueDisplay
            ),
            ConfigRecommendation(
                kind: .disablePanelAutoUpdate,
                satisfied: boolState(disablePanelAutoUpdate, equals: true),
                currentValueDisplay: boolStateDisplay(disablePanelAutoUpdate),
                recommendedValueDisplay: ConfigRecommendationKind.disablePanelAutoUpdate.recommendedValueDisplay
            ),
            ConfigRecommendation(
                kind: .disableUsageStatistics,
                satisfied: boolState(usageStatistics, equals: false),
                currentValueDisplay: boolStateDisplay(usageStatistics),
                recommendedValueDisplay: ConfigRecommendationKind.disableUsageStatistics.recommendedValueDisplay
            ),
            ConfigRecommendation(
                kind: .disableLoggingToFile,
                satisfied: boolState(loggingToFile, equals: false),
                currentValueDisplay: boolStateDisplay(loggingToFile),
                recommendedValueDisplay: ConfigRecommendationKind.disableLoggingToFile.recommendedValueDisplay
            ),
        ]

        return ConfigAudit(
            configPath: configURL.path,
            recommendations: recommendations,
            inspectedAtMs: currentTimestampMs()
        )
    }

    static func applyRecommendedConfigFixes(settings: Settings) throws -> ConfigPatchResult {
        let normalizedSettings = settings.normalized()
        guard let configURL = configURL(for: normalizedSettings) else {
            throw SupportError.missingConfig
        }
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw SupportError.missingConfig
        }

        let originalContent: String
        do {
            originalContent = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            throw SupportError.configReadFailed(error.localizedDescription)
        }

        var updatedContent = originalContent
        var updatedKinds: [ConfigRecommendationKind] = []

        updatedContent = applyConfigChange(
            kind: .bindLocalHost,
            content: updatedContent,
            updatedKinds: &updatedKinds
        ) { content in
            setConfigLine(
                in: content,
                exactPattern: #"(?m)^host:\s*.*$"#,
                desiredLine: #"host: "127.0.0.1""#,
                prependIfMissing: true
            )
        }

        updatedContent = applyConfigChange(
            kind: .keepManagementLocalOnly,
            content: updatedContent,
            updatedKinds: &updatedKinds
        ) { content in
            setConfigLine(
                in: content,
                exactPattern: #"(?m)^\s*allow-remote:\s*.*$"#,
                desiredLine: #"  allow-remote: false"#,
                insertAfterPattern: #"(?m)^remote-management:\s*$"#
            )
        }

        updatedContent = applyConfigChange(
            kind: .keepControlPanelEnabled,
            content: updatedContent,
            updatedKinds: &updatedKinds
        ) { content in
            setConfigLine(
                in: content,
                exactPattern: #"(?m)^\s*disable-control-panel:\s*.*$"#,
                desiredLine: #"  disable-control-panel: false"#,
                insertAfterPattern: #"(?m)^\s*secret-key:\s*.*$"#
            )
        }

        updatedContent = applyConfigChange(
            kind: .disablePanelAutoUpdate,
            content: updatedContent,
            updatedKinds: &updatedKinds
        ) { content in
            setConfigLine(
                in: content,
                exactPattern: #"(?m)^\s*disable-auto-update-panel:\s*.*$"#,
                desiredLine: #"  disable-auto-update-panel: true"#,
                commentedPattern: #"(?m)^\s*#\s*disable-auto-update-panel:\s*.*$"#,
                insertAfterPattern: #"(?m)^\s*disable-control-panel:\s*.*$"#
            )
        }

        updatedContent = applyConfigChange(
            kind: .disableUsageStatistics,
            content: updatedContent,
            updatedKinds: &updatedKinds
        ) { content in
            setConfigLine(
                in: content,
                exactPattern: #"(?m)^usage-statistics-enabled:\s*.*$"#,
                desiredLine: #"usage-statistics-enabled: false"#,
                insertAfterPattern: #"(?m)^error-logs-max-files:\s*.*$"#
            )
        }

        updatedContent = applyConfigChange(
            kind: .disableLoggingToFile,
            content: updatedContent,
            updatedKinds: &updatedKinds
        ) { content in
            setConfigLine(
                in: content,
                exactPattern: #"(?m)^logging-to-file:\s*.*$"#,
                desiredLine: #"logging-to-file: false"#,
                insertAfterPattern: #"(?m)^commercial-mode:\s*.*$"#
            )
        }

        guard updatedContent != originalContent else {
            return ConfigPatchResult(
                configPath: configURL.path,
                backupPath: "",
                updatedKinds: []
            )
        }

        let backupURL = configURL.deletingLastPathComponent()
            .appendingPathComponent("\(configName).hub-backup-\(currentTimestampMs())")
        do {
            try originalContent.write(to: backupURL, atomically: true, encoding: .utf8)
            try updatedContent.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw SupportError.configWriteFailed(error.localizedDescription)
        }

        return ConfigPatchResult(
            configPath: configURL.path,
            backupPath: backupURL.path,
            updatedKinds: updatedKinds
        )
    }

    static func rotateManagementKey(settings: Settings) throws -> ManagementKeyRotationResult {
        let normalizedSettings = settings.normalized()
        guard let configURL = configURL(for: normalizedSettings) else {
            throw SupportError.missingConfig
        }
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw SupportError.missingConfig
        }

        let originalContent: String
        do {
            originalContent = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            throw SupportError.configReadFailed(error.localizedDescription)
        }

        let newKey: String
        do {
            newKey = try generateManagementKey()
        } catch {
            throw error
        }

        let updatedContent = setRemoteManagementNestedLine(
            in: originalContent,
            key: "secret-key",
            desiredLine: #"  secret-key: "\#(newKey)""#
        )

        guard updatedContent != originalContent else {
            throw SupportError.configWriteFailed("未能写入新的 secret-key。")
        }

        let backupURL = configURL.deletingLastPathComponent()
            .appendingPathComponent("\(configName).hub-key-rotation-\(currentTimestampMs())")
        do {
            try originalContent.write(to: backupURL, atomically: true, encoding: .utf8)
            try updatedContent.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw SupportError.configWriteFailed(error.localizedDescription)
        }

        return ManagementKeyRotationResult(
            newKey: newKey,
            configPath: configURL.path,
            backupPath: backupURL.path
        )
    }

    static func probe(
        baseURL: String,
        managementKey: String,
        settings: Settings
    ) async -> Probe {
        let normalizedSettings = settings.normalized()
        let resolved = resolvePackage(normalizedSettings)
        let selectedURL = resolved.resolvedURL ?? resolved.explicitURL ?? resolved.detectedURL
        let status = packageStatus(for: selectedURL)

        var probe = Probe(
            explicitPackageDirectoryPath: resolved.explicitURL?.path ?? "",
            detectedPackageDirectoryPath: resolved.detectedURL?.path ?? "",
            resolvedPackageDirectoryPath: resolved.resolvedURL?.path ?? "",
            binaryPath: resolved.resolvedURL?.appendingPathComponent(executableName).path ?? "",
            configPath: resolved.resolvedURL?.appendingPathComponent(configName).path ?? "",
            packageStatus: status,
            usedDetectedPackage: resolved.usedDetected,
            serviceRunning: false,
            managementStatus: .unknown,
            probedAtMs: currentTimestampMs()
        )

        let normalizedBaseURL = CLIProxyOAuthSourceSupport.normalizedBaseURLString(baseURL)
        probe.serviceRunning = await healthzRunning(baseURL: normalizedBaseURL)
        guard probe.serviceRunning else {
            return probe
        }

        let trimmedKey = managementKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            probe.managementStatus = await probeManagementAvailabilityWithoutKey(baseURL: normalizedBaseURL)
        } else {
            probe.managementStatus = await probeManagementAvailabilityWithKey(
                baseURL: normalizedBaseURL,
                managementKey: trimmedKey
            )
        }

        return probe
    }

    static func startServer(
        baseURL: String,
        settings: Settings
    ) async throws -> LaunchResult {
        let normalizedBaseURL = CLIProxyOAuthSourceSupport.normalizedBaseURLString(baseURL)
        if await healthzRunning(baseURL: normalizedBaseURL) {
            return LaunchResult(
                pid: 0,
                alreadyRunning: true,
                healthConfirmed: true,
                usedPackageDirectoryPath: packageDirectoryURL(for: settings)?.path ?? ""
            )
        }

        let resolved = resolvePackage(settings.normalized())
        let packageURL = resolved.resolvedURL ?? resolved.explicitURL ?? resolved.detectedURL
        switch packageStatus(for: packageURL) {
        case .detected:
            break
        case .notFound:
            throw SupportError.packageNotFound
        case .missingExecutable:
            throw SupportError.missingExecutable
        case .missingConfig:
            throw SupportError.missingConfig
        }

        guard let packageURL else {
            throw SupportError.packageNotFound
        }

        let executableURL = packageURL.appendingPathComponent(executableName)
        let configURL = packageURL.appendingPathComponent(configName)
        let sinkURL = URL(fileURLWithPath: "/dev/null")
        let sink: FileHandle
        do {
            sink = try FileHandle(forWritingTo: sinkURL)
        } catch {
            throw SupportError.processLaunchFailed(error.localizedDescription)
        }

        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = packageURL
        process.standardOutput = sink
        process.standardError = sink

        var arguments = ["--config", configURL.path]
        if settings.useLocalModel {
            arguments.append("--local-model")
        }
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = SharedPaths.realHomeDirectory().path
        process.environment = environment

        do {
            try process.run()
        } catch {
            try? sink.close()
            throw SupportError.processLaunchFailed(error.localizedDescription)
        }

        retainLaunchedProcess(process, sink: sink)

        let confirmed = await waitForHealthyServer(
            baseURL: normalizedBaseURL,
            process: process,
            timeoutSec: 6.0
        )
        if !confirmed && !process.isRunning {
            throw SupportError.exitedBeforeReady
        }

        return LaunchResult(
            pid: process.processIdentifier,
            alreadyRunning: false,
            healthConfirmed: confirmed,
            usedPackageDirectoryPath: packageURL.path
        )
    }

    static func packageStatus(for url: URL?) -> PackageStatus {
        guard let url else { return .notFound }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .notFound
        }

        let executablePath = url.appendingPathComponent(executableName).path
        if !FileManager.default.isExecutableFile(atPath: executablePath) {
            return .missingExecutable
        }

        let configPath = url.appendingPathComponent(configName).path
        guard FileManager.default.fileExists(atPath: configPath) else {
            return .missingConfig
        }

        return .detected
    }

    private static func resolvePackage(_ settings: Settings) -> ResolvedPackage {
        let explicitURL = expandedDirectoryURL(for: settings.packageDirectoryPath)
        let detectedURL = detectPackageDirectoryURL()
        let explicitStatus = packageStatus(for: explicitURL)
        let detectedStatus = packageStatus(for: detectedURL)

        let explicitValid = explicitStatus == .detected
        let detectedValid = detectedStatus == .detected

        if settings.preferDetectedPackage {
            if detectedValid {
                return ResolvedPackage(
                    explicitURL: explicitURL,
                    detectedURL: detectedURL,
                    resolvedURL: detectedURL,
                    usedDetected: true
                )
            }
            if explicitValid {
                return ResolvedPackage(
                    explicitURL: explicitURL,
                    detectedURL: detectedURL,
                    resolvedURL: explicitURL,
                    usedDetected: false
                )
            }
            if explicitURL != nil {
                return ResolvedPackage(
                    explicitURL: explicitURL,
                    detectedURL: detectedURL,
                    resolvedURL: explicitURL,
                    usedDetected: false
                )
            }
            return ResolvedPackage(
                explicitURL: explicitURL,
                detectedURL: detectedURL,
                resolvedURL: detectedURL,
                usedDetected: detectedURL != nil
            )
        }

        if explicitValid {
            return ResolvedPackage(
                explicitURL: explicitURL,
                detectedURL: detectedURL,
                resolvedURL: explicitURL,
                usedDetected: false
            )
        }
        if detectedValid {
            return ResolvedPackage(
                explicitURL: explicitURL,
                detectedURL: detectedURL,
                resolvedURL: detectedURL,
                usedDetected: true
            )
        }
        if explicitURL != nil {
            return ResolvedPackage(
                explicitURL: explicitURL,
                detectedURL: detectedURL,
                resolvedURL: explicitURL,
                usedDetected: false
            )
        }
        return ResolvedPackage(
            explicitURL: explicitURL,
            detectedURL: detectedURL,
            resolvedURL: detectedURL,
            usedDetected: detectedURL != nil
        )
    }

    private static func expandedDirectoryURL(for rawPath: String) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        guard !expanded.isEmpty else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    private static func packageCandidates(in root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }

        var candidates: [URL] = []
        if packageStatus(for: root) == .detected {
            candidates.append(root)
        }

        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )) ?? []

        for child in children {
            guard isDirectory(child) else { continue }
            let name = child.lastPathComponent.lowercased()
            if !name.hasPrefix("cliproxyapi_") && packageStatus(for: child) != .detected {
                continue
            }
            if packageStatus(for: child) == .detected {
                candidates.append(child)
            }
        }

        return uniqueURLs(candidates)
    }

    private static func defaultSearchRoots() -> [URL] {
        var roots: [URL] = []

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        var currentURL: URL? = cwd
        for _ in 0..<8 {
            guard let current = currentURL else { break }
            roots.append(current.appendingPathComponent(runtimeSearchRelativePath, isDirectory: true))
            roots.append(current.appendingPathComponent(runtimeSearchRootName, isDirectory: true))

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            currentURL = parent
        }

        let home = SharedPaths.realHomeDirectory()
        roots.append(
            home.appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("AX", isDirectory: true)
                .appendingPathComponent("source", isDirectory: true)
                .appendingPathComponent(runtimeSearchRootName, isDirectory: true)
        )

        return uniqueURLs(roots)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private static func modificationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private static func uniqueURLs(_ values: [URL]) -> [URL] {
        var seen: Set<String> = []
        var ordered: [URL] = []
        for value in values {
            let path = value.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            ordered.append(value.standardizedFileURL)
        }
        return ordered
    }

    private static func healthzRunning(baseURL: String) async -> Bool {
        do {
            let result = try await rawRequest(
                baseURL: baseURL,
                path: "/healthz"
            )
            guard (200..<300).contains(result.statusCode) else {
                return false
            }
            return true
        } catch {
            return false
        }
    }

    private static func probeManagementAvailabilityWithoutKey(baseURL: String) async -> ManagementStatus {
        do {
            let result = try await rawRequest(
                baseURL: baseURL,
                path: "/v0/management/routing/strategy"
            )
            switch result.statusCode {
            case 200:
                return .keyValid(authCount: 0)
            case 401:
                return .waitingForKey
            case 404:
                return .unavailable
            default:
                return .error(compactHTTPDetail(statusCode: result.statusCode, data: result.data))
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func probeManagementAvailabilityWithKey(
        baseURL: String,
        managementKey: String
    ) async -> ManagementStatus {
        do {
            let result = try await rawRequest(
                baseURL: baseURL,
                path: "/v0/management/auth-files",
                managementKey: managementKey
            )
            switch result.statusCode {
            case 200:
                return .keyValid(authCount: authFileCount(from: result.data))
            case 401:
                let body = httpBodyText(result.data).lowercased()
                if body.contains("invalid management key") {
                    return .keyInvalid
                }
                return .waitingForKey
            case 404:
                return .unavailable
            default:
                return .error(compactHTTPDetail(statusCode: result.statusCode, data: result.data))
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func authFileCount(from data: Data) -> Int {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let payload = object as? [String: Any],
              let files = payload["files"] as? [Any] else {
            return 0
        }
        return files.count
    }

    private static func rawRequest(
        baseURL: String,
        path: String,
        managementKey: String? = nil
    ) async throws -> HTTPResult {
        guard let url = requestURL(baseURL: baseURL, path: path) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = probeTimeoutSec
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let managementKey,
           !managementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(managementKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return HTTPResult(statusCode: httpResponse.statusCode, data: data)
    }

    private static func requestURL(baseURL: String, path: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.path = joinedPath(components.path, path)
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func joinedPath(_ basePath: String, _ suffix: String) -> String {
        let trimmedBase = basePath.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let trimmedSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBase.isEmpty {
            return trimmedSuffix.hasPrefix("/") ? trimmedSuffix : "/" + trimmedSuffix
        }
        if trimmedSuffix.isEmpty {
            return trimmedBase
        }
        return trimmedBase + (trimmedSuffix.hasPrefix("/") ? trimmedSuffix : "/" + trimmedSuffix)
    }

    private static func compactHTTPDetail(statusCode: Int, data: Data) -> String {
        let body = httpBodyText(data)
        if body.isEmpty {
            return "status=\(statusCode)"
        }
        return "status=\(statusCode) \(body)"
    }

    private static func httpBodyText(_ data: Data) -> String {
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.count <= 120 {
            return raw
        }
        let prefix = raw.prefix(117)
        return "\(prefix)..."
    }

    private static func waitForHealthyServer(
        baseURL: String,
        process: Process,
        timeoutSec: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSec)
        while Date() < deadline {
            if await healthzRunning(baseURL: baseURL) {
                return true
            }
            if !process.isRunning {
                return false
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return await healthzRunning(baseURL: baseURL)
    }

    private static func retainLaunchedProcess(_ process: Process, sink: FileHandle) {
        retainedProcessLock.lock()
        defer { retainedProcessLock.unlock() }

        retainedProcesses = retainedProcesses.filter { retained in
            if retained.process.isRunning {
                return true
            }
            try? retained.sink.close()
            return false
        }

        retainedProcesses.append(RetainedLaunch(process: process, sink: sink))
        if retainedProcesses.count > 6 {
            let dropCount = retainedProcesses.count - 6
            let dropped = retainedProcesses.prefix(dropCount)
            for retained in dropped {
                if !retained.process.isRunning {
                    try? retained.sink.close()
                }
            }
            retainedProcesses.removeFirst(dropCount)
        }
    }

    private static func hostConfigValue(in content: String) -> String? {
        guard let raw = firstMatchGroup(in: content, pattern: #"(?m)^host:\s*(.*?)\s*(?:#.*)?$"#) else {
            return nil
        }
        return normalizedScalarValue(raw)
    }

    private static func hostSatisfiesRecommendation(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "127.0.0.1" || normalized == "localhost"
    }

    private static func hostValueDisplay(_ value: String?) -> String {
        guard let value else { return "未设置" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "空字符串" : trimmed
    }

    private static func boolConfigState(in content: String, key: String) -> BoolConfigState {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        if let raw = firstMatchGroup(
            in: content,
            pattern: #"(?m)^\s*"# + escapedKey + #":\s*(true|false)\b.*$"#
        ) {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return .value(normalized == "true")
        }
        if let raw = firstMatchGroup(
            in: content,
            pattern: #"(?m)^\s*#\s*"# + escapedKey + #":\s*(true|false)\b.*$"#
        ) {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return .commented(normalized == "true")
        }
        return .missing
    }

    private static func boolState(_ state: BoolConfigState, equals expected: Bool) -> Bool {
        switch state {
        case .value(let value):
            return value == expected
        case .commented, .missing:
            return false
        }
    }

    private static func boolStateDisplay(_ state: BoolConfigState) -> String {
        switch state {
        case .value(let value):
            return value ? "true" : "false"
        case .commented(let value):
            return value ? "# true" : "# false"
        case .missing:
            return "未设置"
        }
    }

    private static func setConfigLine(
        in content: String,
        exactPattern: String,
        desiredLine: String,
        commentedPattern: String? = nil,
        insertAfterPattern: String? = nil,
        prependIfMissing: Bool = false
    ) -> String {
        let (replacedExact, didReplaceExact) = replacingFirstMatch(
            in: content,
            pattern: exactPattern,
            with: desiredLine
        )
        if didReplaceExact {
            return replacedExact
        }

        if let commentedPattern {
            let (replacedComment, didReplaceComment) = replacingFirstMatch(
                in: replacedExact,
                pattern: commentedPattern,
                with: desiredLine
            )
            if didReplaceComment {
                return replacedComment
            }
        }

        if let insertAfterPattern {
            let insertion = "$0\n" + desiredLine
            let (insertedAfter, didInsertAfter) = replacingFirstMatch(
                in: replacedExact,
                pattern: insertAfterPattern,
                with: insertion
            )
            if didInsertAfter {
                return insertedAfter
            }
        }

        if prependIfMissing {
            return desiredLine + "\n" + replacedExact
        }

        if replacedExact.hasSuffix("\n") {
            return replacedExact + desiredLine + "\n"
        }
        return replacedExact + "\n" + desiredLine + "\n"
    }

    private static func setRemoteManagementNestedLine(
        in content: String,
        key: String,
        desiredLine: String
    ) -> String {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let exactPattern = #"(?m)^\s*"# + escapedKey + #":\s*.*$"#
        let commentedPattern = #"(?m)^\s*#\s*"# + escapedKey + #":\s*.*$"#

        let (replacedExact, didReplaceExact) = replacingFirstMatch(
            in: content,
            pattern: exactPattern,
            with: desiredLine
        )
        if didReplaceExact {
            return replacedExact
        }

        let (replacedComment, didReplaceComment) = replacingFirstMatch(
            in: replacedExact,
            pattern: commentedPattern,
            with: desiredLine
        )
        if didReplaceComment {
            return replacedComment
        }

        let (insertedAfterAllowRemote, didInsertAfterAllowRemote) = replacingFirstMatch(
            in: replacedComment,
            pattern: #"(?m)^\s*allow-remote:\s*.*$"#,
            with: "$0\n" + desiredLine
        )
        if didInsertAfterAllowRemote {
            return insertedAfterAllowRemote
        }

        let (insertedAfterHeader, didInsertAfterHeader) = replacingFirstMatch(
            in: replacedComment,
            pattern: #"(?m)^remote-management:\s*$"#,
            with: "$0\n" + desiredLine
        )
        if didInsertAfterHeader {
            return insertedAfterHeader
        }

        let suffix = replacedComment.hasSuffix("\n") ? "" : "\n"
        return replacedComment + suffix + "remote-management:\n" + desiredLine + "\n"
    }

    private static func applyConfigChange(
        kind: ConfigRecommendationKind,
        content: String,
        updatedKinds: inout [ConfigRecommendationKind],
        _ transform: (String) -> String
    ) -> String {
        let updated = transform(content)
        if updated != content {
            updatedKinds.append(kind)
        }
        return updated
    }

    private static func replacingFirstMatch(
        in content: String,
        pattern: String,
        with template: String
    ) -> (String, Bool) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (content, false)
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              let matchRange = Range(match.range, in: content) else {
            return (content, false)
        }
        let replacement = regex.replacementString(for: match, in: content, offset: 0, template: template)
        let updated = content.replacingCharacters(in: matchRange, with: replacement)
        return (updated, true)
    }

    private static func firstMatchGroup(
        in content: String,
        pattern: String,
        groupIndex: Int = 1
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              match.numberOfRanges > groupIndex,
              let valueRange = Range(match.range(at: groupIndex), in: content) else {
            return nil
        }
        return String(content[valueRange])
    }

    private static func normalizedScalarValue(_ rawValue: String) -> String {
        var trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            trimmed.removeFirst()
            trimmed.removeLast()
            return trimmed
        }
        if trimmed.hasPrefix("'"), trimmed.hasSuffix("'"), trimmed.count >= 2 {
            trimmed.removeFirst()
            trimmed.removeLast()
            return trimmed
        }
        return trimmed
    }

    private static func generateManagementKey(byteCount: Int = 24) throws -> String {
        let safeByteCount = max(16, byteCount)
        var bytes = [UInt8](repeating: 0, count: safeByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw SupportError.keyGenerationFailed("SecRandomCopyBytes status=\(status)")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func settingsURL() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent(settingsFileName)
    }

    private static func currentTimestampMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }
}
