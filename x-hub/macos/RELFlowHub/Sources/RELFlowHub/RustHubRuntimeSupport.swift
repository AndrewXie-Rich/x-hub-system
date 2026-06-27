import Foundation
import RELFlowHubCore

struct RustHubEmbeddedPackageInfo: Equatable, Sendable {
    var rootPath: String
    var xhubdPath: String
    var runnerPath: String
    var manifestPath: String
    var exists: Bool
    var valid: Bool
    var sourcePackageDir: String
    var embeddedAtUTC: String

    static let empty = RustHubEmbeddedPackageInfo(
        rootPath: "",
        xhubdPath: "",
        runnerPath: "",
        manifestPath: "",
        exists: false,
        valid: false,
        sourcePackageDir: "",
        embeddedAtUTC: ""
    )
}

struct RustHubRuntimeSnapshot: Equatable, Sendable {
    var embeddedPackage: RustHubEmbeddedPackageInfo
    var activePackage: RustHubEmbeddedPackageInfo
    var selectedPackage: RustHubEmbeddedPackageInfo
    var healthOK: Bool
    var ready: Bool
    var version: String
    var mode: String
    var grpcCompat: String
    var httpAddr: String
    var dbPath: String
    var productKernelSchemaVersion: String
    var productName: String
    var productBoundary: String
    var kernelName: String
    var shellName: String
    var productKernelOK: Bool
    var crossNetworkReady: Bool
    var domainPublicEndpointReady: Bool
    var authoritySummary: String
    var detail: String
    var updatedAtMs: Int64

    static let empty = RustHubRuntimeSnapshot(
        embeddedPackage: .empty,
        activePackage: .empty,
        selectedPackage: .empty,
        healthOK: false,
        ready: false,
        version: "",
        mode: "",
        grpcCompat: "",
        httpAddr: "",
        dbPath: "",
        productKernelSchemaVersion: "",
        productName: "",
        productBoundary: "",
        kernelName: "",
        shellName: "",
        productKernelOK: false,
        crossNetworkReady: false,
        domainPublicEndpointReady: false,
        authoritySummary: "Shadow / 未接管",
        detail: "",
        updatedAtMs: 0
    )

    var embeddedStatusText: String {
        if embeddedPackage.valid { return "已内置" }
        if embeddedPackage.exists { return "包不完整" }
        return "未内置"
    }

    var activeStatusText: String {
        if activePackage.valid { return "已激活" }
        if activePackage.exists { return "active root 不完整" }
        return "未激活"
    }

    var selectedRootText: String {
        if selectedPackage.valid {
            return activePackage.valid ? "Active root" : "Embedded fallback"
        }
        return "未就绪"
    }

    var daemonStatusText: String {
        if ready { return "Ready" }
        if healthOK { return "Health OK" }
        return "未连接"
    }

    var modeText: String {
        mode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : mode
    }

    var versionText: String {
        version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : version
    }

    var endpointText: String {
        if !httpAddr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return httpAddr
        }
        return RustHubRuntimeSupport.defaultHTTPBaseURL
    }
}

struct RustLocalMLExecutionReadinessSnapshot: Equatable, Sendable {
    var schemaVersion: String
    var ok: Bool
    var enabled: Bool
    var ready: Bool
    var authority: String
    var executionAuthorityInRust: Bool
    var bridgeHTTP: Bool
    var engine: String
    var runtimeBaseDir: String
    var runtimeBaseDirExists: Bool
    var scriptPath: String
    var scriptExists: Bool
    var pythonAvailable: Bool
    var pythonExecutable: String
    var commandProxyReady: Bool
    var blocker: String
    var updatedAtMs: Int64

    static let empty = RustLocalMLExecutionReadinessSnapshot(
        schemaVersion: "",
        ok: false,
        enabled: false,
        ready: false,
        authority: "",
        executionAuthorityInRust: false,
        bridgeHTTP: false,
        engine: "",
        runtimeBaseDir: "",
        runtimeBaseDirExists: false,
        scriptPath: "",
        scriptExists: false,
        pythonAvailable: false,
        pythonExecutable: "",
        commandProxyReady: false,
        blocker: "",
        updatedAtMs: 0
    )

    var statusText: String {
        if ready { return "Ready" }
        if enabled {
            let reason = blocker.trimmingCharacters(in: .whitespacesAndNewlines)
            return reason.isEmpty ? "Blocked" : "Blocked: \(reason)"
        }
        if ok { return "Disabled" }
        return "Unavailable"
    }

    var authorityText: String {
        let normalized = authority.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "unknown" : normalized
    }

    var engineText: String {
        let normalized = engine.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "unknown" : normalized
    }

    var commandProxyText: String {
        commandProxyReady ? "Ready" : "Not ready"
    }

    var pythonText: String {
        let normalized = pythonExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "not resolved" : normalized
    }
}

struct RustHubRemoteEntryClassification: Equatable, Sendable {
    var kind: String
    var scope: String
    var stable: Bool
    var encryptedPrivateCandidate: Bool
    var reasonCode: String

    static let empty = RustHubRemoteEntryClassification(
        kind: "",
        scope: "",
        stable: false,
        encryptedPrivateCandidate: false,
        reasonCode: ""
    )
}

struct RustHubRemoteEntryCandidate: Equatable, Identifiable, Sendable {
    var routeKind: String
    var source: String
    var host: String
    var publicBaseURL: String
    var usable: Bool
    var requiresSamePrivateNetwork: Bool
    var requiresMTLS: Bool
    var classification: RustHubRemoteEntryClassification

    var id: String {
        "\(routeKind)::\(source)::\(host)"
    }

    var isNoDomainPrivateNetwork: Bool {
        routeKind == "no_domain_private_network" && usable
    }
}

struct RustHubRemoteEntryCandidates: Equatable, Sendable {
    var schemaVersion: String
    var ok: Bool
    var source: String
    var recommendedSetup: String
    var preferred: RustHubRemoteEntryCandidate?
    var candidates: [RustHubRemoteEntryCandidate]
    var updatedAtMs: Int64

    static let empty = RustHubRemoteEntryCandidates(
        schemaVersion: "",
        ok: false,
        source: "",
        recommendedSetup: "",
        preferred: nil,
        candidates: [],
        updatedAtMs: 0
    )

    var preferredNoDomainPrivateHost: String? {
        candidates.first(where: { $0.isNoDomainPrivateNetwork })?.host
            ?? (preferred?.isNoDomainPrivateNetwork == true ? preferred?.host : nil)
    }
}

enum RustHubRuntimeSupport {
    private static let httpAccessKeyCacheTTL: TimeInterval = 5
    private static let httpAccessKeyCacheLock = NSLock()
    nonisolated(unsafe) private static var cachedHTTPAccessKeyEntry: (checkedAt: TimeInterval, value: String?)?

    static let defaultHost = "127.0.0.1"
    static let defaultHTTPPort = 50151
    static let defaultHTTPBaseURL = "http://127.0.0.1:50151"
    private static let alwaysClampedNodeAuthorityKeys = [
        "XHUB_RUST_MEMORY_WRITER_AUTHORITY",
        "XHUB_RUST_MEMORY_WRITE_AUTHORITY",
        "XHUB_RUST_MEMORY_PRODUCTION_AUTHORITY",
        "XHUB_RUST_SKILLS_EXECUTION_AUTHORITY",
        "XHUB_RUST_SKILLS_PRODUCTION_EXECUTION",
        "XHUB_RUST_SKILLS_EXECUTION_PRODUCTION",
        "XHUB_RUST_SKILLS_RUNNER_PRODUCTION_AUTHORITY"
    ]
    private static let falseRemovableNodeAuthorityKeys = [
        "XHUB_RUST_SCHEDULER_AUTHORITY",
        "XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY",
        "XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION",
        "XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER",
        "XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY",
        "XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY",
        "XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION",
        "XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER",
        "XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY",
        "XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER",
        "XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER"
    ]
    private static let nodeProductionPassthroughKeys = [
        "XHUB_RUST_HUB_ROOT",
        "XHUB_RUST_HUB_RUNNER",
        "XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY",
        "XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION",
        "XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER",
        "XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY",
        "XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP",
        "XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL",
        "XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY",
        "XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH",
        "XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_FALLBACK_ON_ERROR",
        "XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY",
        "XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION",
        "XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER",
        "XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY",
        "XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP",
        "XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL",
        "XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY",
        "XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH",
        "XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR",
        "XHUB_RUST_SCHEDULER_STATUS_READ",
        "XHUB_RUST_SCHEDULER_STATUS_HTTP",
        "XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL",
        "XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP",
        "XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP_BASE_URL",
        "XHUB_RUST_SCHEDULER_AUTHORITY",
        "XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY",
        "XHUB_RUST_SCHEDULER_AUTHORITY_HTTP",
        "XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL",
        "XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER",
        "XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER"
    ]

    static func embeddedPackageRoot(bundle: Bundle = .main) -> URL? {
        guard let resources = bundle.resourceURL else { return nil }
        return resources.appendingPathComponent("rust-hub", isDirectory: true)
    }

    static func defaultUserHomeDirectory() -> URL {
        let userName = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !userName.isEmpty {
            let realHome = URL(fileURLWithPath: "/Users").appendingPathComponent(userName, isDirectory: true)
            if FileManager.default.fileExists(atPath: realHome.path) {
                return realHome
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func activePackageRoot(homeDirectory: URL = defaultUserHomeDirectory()) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/AX/rust-hub/current", isDirectory: true)
    }

    static func appContainerActivePackageRoot(homeDirectory: URL = defaultUserHomeDirectory()) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Containers/com.rel.flowhub/Data/RELFlowHub/rust-hub/current", isDirectory: true)
    }

    static func sandboxHomeActivePackageRoot(
        containerHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        containerHomeDirectory
            .appendingPathComponent("RELFlowHub/rust-hub/current", isDirectory: true)
    }

    static func activePackageRoots(
        homeDirectory: URL = defaultUserHomeDirectory(),
        containerHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        uniqueURLs(
            environmentContainerActivePackageRoots(environment: environment) + [
            sandboxHomeActivePackageRoot(containerHomeDirectory: containerHomeDirectory),
            appContainerActivePackageRoot(homeDirectory: homeDirectory),
            activePackageRoot(homeDirectory: homeDirectory)
            ]
        )
    }

    static func environmentContainerActivePackageRoots(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        ["HOME", "CFFIXED_USER_HOME"].compactMap { key in
            let value = (environment[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return URL(fileURLWithPath: value, isDirectory: true)
                .appendingPathComponent("RELFlowHub/rust-hub/current", isDirectory: true)
        }
    }

    static func embeddedPackageInfo(bundle: Bundle = .main) -> RustHubEmbeddedPackageInfo {
        embeddedPackageInfo(root: embeddedPackageRoot(bundle: bundle))
    }

    static func activePackageInfo(homeDirectory: URL = defaultUserHomeDirectory()) -> RustHubEmbeddedPackageInfo {
        activePackageInfo(roots: activePackageRoots(homeDirectory: homeDirectory))
    }

    static func activePackageInfo(roots: [URL]) -> RustHubEmbeddedPackageInfo {
        let infos = roots.map { embeddedPackageInfo(root: $0) }
        if let valid = infos.first(where: { $0.valid }) {
            return valid
        }
        return infos.first(where: { $0.exists }) ?? .empty
    }

    static func selectedPackageInfo(bundle: Bundle = .main) -> RustHubEmbeddedPackageInfo {
        preferredPackageInfo(
            embeddedPackage: embeddedPackageInfo(bundle: bundle),
            activePackage: activePackageInfo()
        )
    }

    static func embeddedPackageInfo(root: URL?) -> RustHubEmbeddedPackageInfo {
        guard let root else { return .empty }
        let xhubdURL = root.appendingPathComponent("bin/xhubd")
        let runnerURL = root.appendingPathComponent("tools/run_rust_hub.command")
        let manifestURL = root.appendingPathComponent("embedded_manifest.json")
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: root.path)
        let valid = exists
            && fm.fileExists(atPath: xhubdURL.path)
            && fm.fileExists(atPath: runnerURL.path)

        var sourcePackageDir = ""
        var embeddedAtUTC = ""
        if let data = try? Data(contentsOf: manifestURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            sourcePackageDir = stringValue(object["source_package_dir"])
            embeddedAtUTC = stringValue(object["embedded_at_utc"])
        }

        return RustHubEmbeddedPackageInfo(
            rootPath: root.path,
            xhubdPath: xhubdURL.path,
            runnerPath: runnerURL.path,
            manifestPath: manifestURL.path,
            exists: exists,
            valid: valid,
            sourcePackageDir: sourcePackageDir,
            embeddedAtUTC: embeddedAtUTC
        )
    }

    static func nodeSidecarBaseEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var out = environment
        let allowProductionPassthrough = productionPassthroughEnabled(environment)
        for key in alwaysClampedNodeAuthorityKeys {
            out.removeValue(forKey: key)
        }
        for key in falseRemovableNodeAuthorityKeys {
            if !allowProductionPassthrough || isFalseAuthorityValue(out[key]) {
                out.removeValue(forKey: key)
            }
        }
        return out
    }

    static func nodeSidecarEnvironmentAdditions(
        bundle: Bundle = .main,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let embedded = embeddedPackageInfo(bundle: bundle)
        let active = activePackageInfo()
        return nodeSidecarEnvironmentAdditions(
            selectedPackage: preferredPackageInfo(embeddedPackage: embedded, activePackage: active),
            baseEnvironment: baseEnvironment
        )
    }

    static func preferredPackageInfo(
        embeddedPackage: RustHubEmbeddedPackageInfo,
        activePackage: RustHubEmbeddedPackageInfo
    ) -> RustHubEmbeddedPackageInfo {
        activePackage.valid ? activePackage : embeddedPackage
    }

    static func nodeSidecarEnvironmentAdditions(
        embeddedPackage info: RustHubEmbeddedPackageInfo,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        nodeSidecarEnvironmentAdditions(selectedPackage: info, baseEnvironment: baseEnvironment)
    }

    private static func nodeSidecarEnvironmentAdditions(
        selectedPackage info: RustHubEmbeddedPackageInfo,
        baseEnvironment: [String: String]
    ) -> [String: String] {
        guard info.valid else { return [:] }
        let allowProductionPassthrough = productionPassthroughEnabled(baseEnvironment)
        let rootPath = rustHubRootPath(
            selectedPackage: info,
            baseEnvironment: baseEnvironment,
            allowProductionPassthrough: allowProductionPassthrough
        )
        var out = [
            "XHUB_RUST_HUB_EMBEDDED": "1",
            "XHUB_RUST_HUB_ROOT": rootPath,
            "XHUB_RUST_HUB_RUNNER": allowProductionPassthrough
                ? (nonEmptyEnvironmentValue(baseEnvironment, "XHUB_RUST_HUB_RUNNER")
                    ?? rustHubRunnerPath(rootPath: rootPath, selectedRunnerPath: info.runnerPath))
                : rustHubRunnerPath(rootPath: rootPath, selectedRunnerPath: info.runnerPath),
            "XHUB_RUST_HUB_HOST": defaultHost,
            "XHUB_RUST_HUB_HTTP_PORT": String(defaultHTTPPort),
            "XHUB_RUST_HUB_HTTP_BASE_URL": defaultHTTPBaseURL
        ]
        if let accessKey = httpAccessKey(
            environment: baseEnvironment,
            activePackageRoots: [URL(fileURLWithPath: rootPath, isDirectory: true)]
        ) {
            out["XHUB_RUST_HTTP_ACCESS_KEY"] = accessKey
            out["XHUB_RUST_HUB_ACCESS_KEY"] = accessKey
            out.removeValue(forKey: "XHUB_RUST_HTTP_ACCESS_KEY_FILE")
            out.removeValue(forKey: "XHUB_RUST_HUB_ACCESS_KEY_FILE")
        }
        if allowProductionPassthrough {
            for key in nodeProductionPassthroughKeys {
                guard !alwaysClampedNodeAuthorityKeys.contains(key) else { continue }
                guard key != "XHUB_RUST_HUB_ROOT", key != "XHUB_RUST_HUB_RUNNER" else { continue }
                if let value = nonEmptyEnvironmentValue(baseEnvironment, key) {
                    out[key] = value
                }
            }
        }
        return out
    }

    private static func rustHubRootPath(
        selectedPackage info: RustHubEmbeddedPackageInfo,
        baseEnvironment: [String: String],
        allowProductionPassthrough: Bool
    ) -> String {
        guard allowProductionPassthrough,
              let candidateRoot = nonEmptyEnvironmentValue(baseEnvironment, "XHUB_RUST_HUB_ROOT") else {
            return info.rootPath
        }
        let candidate = embeddedPackageInfo(root: URL(fileURLWithPath: candidateRoot, isDirectory: true))
        return candidate.valid ? candidate.rootPath : info.rootPath
    }

    private static func productionPassthroughEnabled(_ environment: [String: String]) -> Bool {
        switch (environment["XHUB_ENABLE_RUST_AUTHORITY_CUTOVER"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }

    private static func nonEmptyEnvironmentValue(_ environment: [String: String], _ key: String) -> String? {
        let trimmed = (environment[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isFalseAuthorityValue(_ value: String?) -> Bool {
        switch (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "0", "false", "no", "n", "off":
            return true
        default:
            return false
        }
    }

    private static func rustHubRunnerPath(rootPath: String, selectedRunnerPath: String) -> String {
        if rootPath.isEmpty { return selectedRunnerPath }
        return URL(fileURLWithPath: rootPath)
            .appendingPathComponent("tools/run_rust_hub.command")
            .path
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var out: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                out.append(url)
            }
        }
        return out
    }

    static func localSnapshot(bundle: Bundle = .main) -> RustHubRuntimeSnapshot {
        let embedded = embeddedPackageInfo(bundle: bundle)
        let active = activePackageInfo()
        var snapshot = RustHubRuntimeSnapshot.empty
        snapshot.embeddedPackage = embedded
        snapshot.activePackage = active
        snapshot.selectedPackage = preferredPackageInfo(embeddedPackage: embedded, activePackage: active)
        snapshot.updatedAtMs = nowMs()
        return snapshot
    }

    static func loadSnapshot(bundle: Bundle = .main) async -> RustHubRuntimeSnapshot {
        let embedded = embeddedPackageInfo(bundle: bundle)
        let active = activePackageInfo()
        let selected = preferredPackageInfo(embeddedPackage: embedded, activePackage: active)
        let productKernel = jsonObject(from: await fetchData(path: "/product/kernel", authorize: true))
        if isProductKernelContract(productKernel) {
            var snapshot = makeSnapshot(
                embeddedPackage: embedded,
                activePackage: active,
                health: [:],
                readiness: [:],
                productKernel: productKernel
            )
            snapshot.selectedPackage = selected
            snapshot.updatedAtMs = nowMs()
            return snapshot
        }

        async let healthData = fetchData(path: "/health", authorize: false)
        async let readyData = fetchData(path: "/ready", authorize: true)
        let health = jsonObject(from: await healthData)
        let readiness = jsonObject(from: await readyData)

        var snapshot = makeSnapshot(
            embeddedPackage: embedded,
            activePackage: active,
            health: health,
            readiness: readiness
        )
        snapshot.selectedPackage = selected
        snapshot.updatedAtMs = nowMs()
        return snapshot
    }

    static func loadRemoteEntryCandidates() async -> RustHubRemoteEntryCandidates {
        makeRemoteEntryCandidates(
            object: jsonObject(from: await fetchData(path: "/network/remote-entry-candidates", authorize: true))
        )
    }

    static func loadLocalMLExecutionReadiness() async -> RustLocalMLExecutionReadinessSnapshot {
        makeLocalMLExecutionReadiness(
            object: jsonObject(from: await fetchData(path: "/runtime/ml-execution/readiness", authorize: true))
        )
    }

    static func loadLocalModelRepairPlan(
        taskKind: String? = nil,
        runtimeBaseDir: URL = SharedPaths.ensureHubDirectory(),
        baseURL: String = defaultHTTPBaseURL
    ) async -> RustLocalModelRepairPlan? {
        guard let url = localModelRepairPlanURL(
            taskKind: taskKind,
            runtimeBaseDir: runtimeBaseDir,
            baseURL: baseURL
        ) else {
            return nil
        }
        guard let data = await fetchData(url: url, authorize: true) else {
            return nil
        }
        return RustLocalModelRepairPlanSupport.decode(data: data)
    }

    static func applyLocalModelRepair(
        plan: RustLocalModelRepairPlan,
        runtimeBaseDir: URL = SharedPaths.ensureHubDirectory(),
        baseURL: String = defaultHTTPBaseURL
    ) async -> RustLocalModelRepairApplyResult? {
        guard let url = localModelRepairApplyURL(baseURL: baseURL),
              let body = localModelRepairApplyRequestBody(
                plan: plan,
                runtimeBaseDir: runtimeBaseDir
              ) else {
            return nil
        }
        guard let data = await postJSONData(url: url, body: body, authorize: true) else {
            return nil
        }
        return RustLocalModelRepairApplySupport.decode(data: data)
    }

    static func loadLocalModelRepairJobs(
        limit: Int = 10,
        runtimeBaseDir: URL = SharedPaths.ensureHubDirectory(),
        baseURL: String = defaultHTTPBaseURL
    ) async -> RustLocalModelRepairJobsSnapshot {
        guard let url = localModelRepairJobsURL(
            limit: limit,
            runtimeBaseDir: runtimeBaseDir,
            baseURL: baseURL
        ) else {
            return .empty
        }
        guard let data = await fetchData(url: url, authorize: true),
              let snapshot = RustLocalModelRepairApplySupport.decodeJobs(data: data) else {
            return .empty
        }
        return snapshot
    }

    static func runLocalModelRepairExecutor(
        runtimeBaseDir: URL = SharedPaths.ensureHubDirectory(),
        allowNetwork: Bool = true,
        timeoutMs: Int = 600_000,
        requestedBy: String = "swift_hub_settings"
    ) async -> RustLocalModelRepairExecutorResult? {
        let package = selectedPackageInfo()
        guard package.valid else { return nil }
        let arguments = [
            "model",
            "repair-executor",
            "--runtime-base-dir",
            runtimeBaseDir.standardizedFileURL.path,
            "--allow-network",
            allowNetwork ? "true" : "false",
            "--timeout-ms",
            "\(max(1_000, timeoutMs))",
            "--requested-by",
            requestedBy
        ]
        guard let data = await runXHubdJSON(
            executablePath: package.xhubdPath,
            arguments: arguments,
            timeoutMs: max(1_000, timeoutMs) + 5_000
        ) else {
            return nil
        }
        return RustLocalModelRepairApplySupport.decodeExecutor(data: data)
    }

    static func localModelRepairPlanURL(
        taskKind: String? = nil,
        runtimeBaseDir: URL = SharedPaths.ensureHubDirectory(),
        baseURL: String = defaultHTTPBaseURL
    ) -> URL? {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { return nil }
        let normalizedBase = trimmedBase.hasSuffix("/") ? String(trimmedBase.dropLast()) : trimmedBase
        guard var components = URLComponents(string: normalizedBase + "/model/repair-plan") else {
            return nil
        }
        var queryItems = [
            URLQueryItem(name: "runtime_base_dir", value: runtimeBaseDir.standardizedFileURL.path)
        ]
        let normalizedTaskKind = (taskKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedTaskKind.isEmpty {
            queryItems.append(URLQueryItem(name: "task_kind", value: normalizedTaskKind))
        }
        components.queryItems = queryItems
        return components.url
    }

    static func localModelRepairApplyURL(
        baseURL: String = defaultHTTPBaseURL
    ) -> URL? {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { return nil }
        let normalizedBase = trimmedBase.hasSuffix("/") ? String(trimmedBase.dropLast()) : trimmedBase
        return URL(string: normalizedBase + "/model/repair-apply")
    }

    static func localModelRepairJobsURL(
        limit: Int = 10,
        runtimeBaseDir: URL = SharedPaths.ensureHubDirectory(),
        baseURL: String = defaultHTTPBaseURL
    ) -> URL? {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { return nil }
        let normalizedBase = trimmedBase.hasSuffix("/") ? String(trimmedBase.dropLast()) : trimmedBase
        guard var components = URLComponents(string: normalizedBase + "/model/repair-jobs") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "runtime_base_dir", value: runtimeBaseDir.standardizedFileURL.path),
            URLQueryItem(name: "limit", value: "\(max(1, min(50, limit)))")
        ]
        return components.url
    }

    static func localModelRepairApplyRequestBody(
        plan: RustLocalModelRepairPlan,
        confirm: Bool = true,
        dryRun: Bool = false,
        requestedBy: String = "swift_hub_settings",
        runtimeBaseDir: URL = SharedPaths.ensureHubDirectory()
    ) -> Data? {
        guard plan.isActionableRepair else { return nil }
        let action = plan.resolved.action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !action.isEmpty else { return nil }
        let taskKind = firstNonEmpty(
            plan.target.taskKind,
            plan.resolved.taskKind
        )
        let providerID = firstNonEmpty(
            plan.target.providerID,
            plan.resolved.providerID
        )
        let token = firstNonEmpty(
            plan.confirmation.tokenHint,
            "confirm:\(action)"
        )
        let body: [String: Any] = [
            "action": action,
            "task_kind": taskKind,
            "provider_id": providerID,
            "confirm": confirm,
            "dry_run": dryRun,
            "confirmation_token": token,
            "requested_by": requestedBy,
            "runtime_base_dir": runtimeBaseDir.standardizedFileURL.path
        ]
        return try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    static func makeSnapshot(
        embeddedPackage: RustHubEmbeddedPackageInfo = .empty,
        activePackage: RustHubEmbeddedPackageInfo = .empty,
        health: [String: Any],
        readiness: [String: Any],
        productKernel: [String: Any] = [:]
    ) -> RustHubRuntimeSnapshot {
        var snapshot = RustHubRuntimeSnapshot.empty
        snapshot.embeddedPackage = embeddedPackage
        snapshot.activePackage = activePackage
        snapshot.selectedPackage = preferredPackageInfo(embeddedPackage: embeddedPackage, activePackage: activePackage)
        snapshot.healthOK = boolValue(health["ok"])
        snapshot.ready = boolValue(readiness["ready"])
        snapshot.version = stringValue(readiness["version"]).isEmpty
            ? stringValue(health["version"])
            : stringValue(readiness["version"])
        snapshot.mode = stringValue(readiness["mode"]).isEmpty
            ? stringValue(health["mode"])
            : stringValue(readiness["mode"])
        snapshot.grpcCompat = stringValue(health["grpc_compat"])
        snapshot.httpAddr = stringValue(readiness["http_addr"]).isEmpty
            ? stringValue(health["http_addr"])
            : stringValue(readiness["http_addr"])
        snapshot.dbPath = stringValue(health["db_path"])
        applyFallbackProductKernelDefaults(health: health, readiness: readiness, snapshot: &snapshot)
        snapshot.authoritySummary = authoritySummary(readiness: readiness)
        snapshot.detail = detailSummary(health: health, readiness: readiness, package: snapshot.selectedPackage)
        if isProductKernelContract(productKernel) {
            applyProductKernel(productKernel, snapshot: &snapshot)
        }
        snapshot.updatedAtMs = nowMs()
        return snapshot
    }

    static func makeRemoteEntryCandidates(object: [String: Any]) -> RustHubRemoteEntryCandidates {
        guard !object.isEmpty else { return .empty }
        let candidates = (object["candidates"] as? [[String: Any]] ?? [])
            .map(remoteEntryCandidate)
            .filter { !$0.host.isEmpty || !$0.publicBaseURL.isEmpty }
        let preferredObject = object["preferred"] as? [String: Any] ?? [:]
        let preferred = preferredObject.isEmpty ? nil : remoteEntryCandidate(preferredObject)
        let normalizedPreferred: RustHubRemoteEntryCandidate?
        if let preferred, !preferred.host.isEmpty || !preferred.publicBaseURL.isEmpty {
            normalizedPreferred = preferred
        } else {
            normalizedPreferred = nil
        }
        return RustHubRemoteEntryCandidates(
            schemaVersion: stringValue(object["schema_version"]),
            ok: boolValue(object["ok"]),
            source: stringValue(object["source"]),
            recommendedSetup: stringValue(object["recommended_setup"]),
            preferred: normalizedPreferred,
            candidates: candidates,
            updatedAtMs: nowMs()
        )
    }

    static func makeLocalMLExecutionReadiness(
        object: [String: Any]
    ) -> RustLocalMLExecutionReadinessSnapshot {
        guard !object.isEmpty else { return .empty }
        return RustLocalMLExecutionReadinessSnapshot(
            schemaVersion: stringValue(object["schema_version"]),
            ok: boolValue(object["ok"]),
            enabled: boolValue(object["enabled"]),
            ready: boolValue(object["ready"]),
            authority: stringValue(object["authority"]),
            executionAuthorityInRust: boolValue(object["execution_authority_in_rust"]),
            bridgeHTTP: boolValue(object["bridge_http"]),
            engine: stringValue(object["engine"]),
            runtimeBaseDir: stringValue(object["runtime_base_dir"]),
            runtimeBaseDirExists: boolValue(object["runtime_base_dir_exists"]),
            scriptPath: stringValue(object["script_path"]),
            scriptExists: boolValue(object["script_exists"]),
            pythonAvailable: boolValue(object["python_available"]),
            pythonExecutable: stringValue(object["python_executable"]),
            commandProxyReady: boolValue(object["command_proxy_ready"]),
            blocker: stringValue(object["blocker"]),
            updatedAtMs: nowMs()
        )
    }

    private static func fetchData(path: String, authorize: Bool = true) async -> Data? {
        guard let url = URL(string: defaultHTTPBaseURL + path) else { return nil }
        return await fetchData(url: url, authorize: authorize)
    }

    private static func fetchData(url: URL, authorize: Bool = true) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        if authorize, let accessKey = cachedHTTPAccessKey() {
            request.setValue("Bearer \(accessKey)", forHTTPHeaderField: "Authorization")
            request.setValue(accessKey, forHTTPHeaderField: "X-XHub-Access-Key")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private static func postJSONData(url: URL, body: Data, authorize: Bool = true) async -> Data? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 2.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        if authorize, let accessKey = cachedHTTPAccessKey() {
            request.setValue("Bearer \(accessKey)", forHTTPHeaderField: "Authorization")
            request.setValue(accessKey, forHTTPHeaderField: "X-XHub-Access-Key")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private static func runXHubdJSON(
        executablePath: String,
        arguments: [String],
        timeoutMs: Int
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                let tempRoot = FileManager.default.temporaryDirectory
                let stdoutURL = tempRoot.appendingPathComponent("xhub-repair-executor-\(UUID().uuidString).out")
                let stderrURL = tempRoot.appendingPathComponent("xhub-repair-executor-\(UUID().uuidString).err")
                FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
                FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
                guard let stdoutHandle = try? FileHandle(forWritingTo: stdoutURL),
                      let stderrHandle = try? FileHandle(forWritingTo: stderrURL) else {
                    continuation.resume(returning: nil)
                    return
                }
                defer {
                    try? stdoutHandle.close()
                    try? stderrHandle.close()
                    try? FileManager.default.removeItem(at: stdoutURL)
                    try? FileManager.default.removeItem(at: stderrURL)
                }
                process.standardOutput = stdoutHandle
                process.standardError = stderrHandle
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let deadline = Date().addingTimeInterval(Double(max(1_000, timeoutMs)) / 1000.0)
                while process.isRunning {
                    if Date() >= deadline {
                        process.terminate()
                        Thread.sleep(forTimeInterval: 0.2)
                        continuation.resume(returning: nil)
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.2)
                }
                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: try? Data(contentsOf: stdoutURL))
            }
        }
    }

    static func cachedHTTPAccessKey(now: TimeInterval = Date().timeIntervalSince1970) -> String? {
        httpAccessKeyCacheLock.lock()
        if let entry = cachedHTTPAccessKeyEntry,
           (now - entry.checkedAt) >= 0,
           (now - entry.checkedAt) <= httpAccessKeyCacheTTL {
            let value = entry.value
            httpAccessKeyCacheLock.unlock()
            return value
        }
        httpAccessKeyCacheLock.unlock()

        let value = httpAccessKey(
            environment: ProcessInfo.processInfo.environment,
            activePackageRoots: activePackageRoots()
        )
        httpAccessKeyCacheLock.lock()
        cachedHTTPAccessKeyEntry = (checkedAt: now, value: value)
        httpAccessKeyCacheLock.unlock()
        return value
    }

    static func httpAccessKey(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        activePackageRoots: [URL] = activePackageRoots()
    ) -> String? {
        for key in ["XHUB_RUST_HTTP_ACCESS_KEY", "XHUB_RUST_HUB_ACCESS_KEY"] {
            if let value = nonEmptyEnvironmentValue(environment, key) {
                return value
            }
        }

        for key in ["XHUB_RUST_HTTP_ACCESS_KEY_FILE", "XHUB_RUST_HUB_ACCESS_KEY_FILE"] {
            guard let path = nonEmptyEnvironmentValue(environment, key) else { continue }
            if let value = readAccessKeyFile(URL(fileURLWithPath: path)) {
                return value
            }
        }

        let candidateFiles = activePackageRoots.flatMap { root in
            [
                root.appendingPathComponent("secrets/xhubd_http_access_key"),
                root.appendingPathComponent("secrets/xhubd_domain_access_key"),
                root.appendingPathComponent("secrets/xhubd_lan_access_key"),
                root.appendingPathComponent("config/xhubd_http_access_key"),
                root.appendingPathComponent("config/xhubd_domain_access_key"),
                root.appendingPathComponent("config/xhubd_lan_access_key")
            ]
        }
        for file in candidateFiles {
            if let value = readAccessKeyFile(file) {
                return value
            }
        }
        return nil
    }

    private static func readAccessKeyFile(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func jsonObject(from data: Data?) -> [String: Any] {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func isProductKernelContract(_ object: [String: Any]) -> Bool {
        stringValue(object["schema_version"]) == "xhub.product_kernel.v1"
    }

    private static func applyFallbackProductKernelDefaults(
        health: [String: Any],
        readiness: [String: Any],
        snapshot: inout RustHubRuntimeSnapshot
    ) {
        guard boolValue(health["ok"]) || boolValue(readiness["ok"]) || boolValue(readiness["ready"]) else {
            return
        }
        snapshot.productName = "X-Hub"
        snapshot.productBoundary = "rust_product_kernel_swift_shell"
        snapshot.kernelName = "rust"
        snapshot.shellName = "swift"
        let capabilities = readiness["capabilities"] as? [String: Any] ?? [:]
        snapshot.crossNetworkReady = boolValue(capabilities["cross_network_ready"])
        snapshot.domainPublicEndpointReady = boolValue(capabilities["domain_public_endpoint_ready"])
    }

    private static func applyProductKernel(_ object: [String: Any], snapshot: inout RustHubRuntimeSnapshot) {
        let product = object["product"] as? [String: Any] ?? [:]
        let kernel = object["kernel"] as? [String: Any] ?? [:]
        let shell = object["shell"] as? [String: Any] ?? [:]
        let network = object["network"] as? [String: Any] ?? [:]
        let storage = object["storage"] as? [String: Any] ?? [:]
        let authority = object["authority"] as? [String: Any] ?? [:]

        snapshot.productKernelSchemaVersion = stringValue(object["schema_version"])
        snapshot.productKernelOK = boolValue(object["ok"])
        snapshot.healthOK = boolValue(object["ok"])
        snapshot.ready = boolValue(object["ready"])
        snapshot.productName = stringValue(product["name"])
        snapshot.productBoundary = stringValue(product["boundary"])
        snapshot.kernelName = stringValue(kernel["name"])
        snapshot.shellName = stringValue(shell["name"])
        snapshot.version = stringValue(kernel["version"])
        snapshot.mode = stringValue(kernel["mode"])
        snapshot.httpAddr = stringValue(kernel["http_addr"])
        snapshot.dbPath = stringValue(storage["db_path"])
        snapshot.crossNetworkReady = boolValue(network["cross_network_ready"])
        snapshot.domainPublicEndpointReady = boolValue(network["domain_public_endpoint_ready"])
        snapshot.authoritySummary = productKernelAuthoritySummary(authority: authority)
        snapshot.detail = productKernelDetailSummary(productKernel: object, package: snapshot.selectedPackage)
    }

    private static func productKernelAuthoritySummary(authority: [String: Any]) -> String {
        var parts = ["Rust kernel", "Swift shell"]
        if boolValue(authority["provider_route_in_rust"]) && boolValue(authority["model_route_in_rust"]) {
            parts.append("Route authority")
        }
        if boolValue(authority["scheduler_in_rust"]) { parts.append("Scheduler") }
        if boolValue(authority["memory_writer_in_rust"]) { parts.append("Memory writer") }
        if boolValue(authority["skills_execution_in_rust"]) { parts.append("Skill exec") }
        if boolValue(authority["xt_file_ipc_in_rust"]) { parts.append("XT IPC") }
        if boolValue(authority["local_ml_execution_in_rust"]) { parts.append("Local ML") }
        return parts.joined(separator: " / ")
    }

    private static func productKernelDetailSummary(
        productKernel: [String: Any],
        package: RustHubEmbeddedPackageInfo
    ) -> String {
        var parts: [String] = []
        parts.append(package.valid ? "package ready" : "package fallback")
        parts.append(boolValue(productKernel["ready"]) ? "kernel ready" : "kernel not ready")
        let network = productKernel["network"] as? [String: Any] ?? [:]
        if boolValue(network["domain_public_endpoint_ready"]) {
            parts.append("domain ready")
        } else if boolValue(network["cross_network_ready"]) {
            parts.append("cross-network ready")
        }
        return parts.joined(separator: " · ")
    }

    private static func authoritySummary(readiness: [String: Any]) -> String {
        let memory = readiness["memory"] as? [String: Any] ?? [:]
        let skills = readiness["skills"] as? [String: Any] ?? [:]
        let capabilities = readiness["capabilities"] as? [String: Any] ?? [:]
        let memoryWriter = boolValue(memory["canonical_writer_in_rust"])
        let skillExecutor = boolValue(skills["execution_authority_in_rust"])
        let xtCompat = stringValue(capabilities["xt_classic_hub_compat_authority"])
        let xtStatus = stringValue(capabilities["xt_classic_hub_status_writer_authority"])

        var parts: [String] = []
        parts.append(memoryWriter ? "Memory writer" : "Memory shadow")
        parts.append(skillExecutor ? "Skill exec" : "Skill policy gate")
        if !xtCompat.isEmpty { parts.append("XT \(xtCompat)") }
        if !xtStatus.isEmpty { parts.append("Status \(xtStatus)") }
        return parts.joined(separator: " / ")
    }

    private static func remoteEntryCandidate(_ object: [String: Any]) -> RustHubRemoteEntryCandidate {
        let classification = object["classification"] as? [String: Any] ?? [:]
        return RustHubRemoteEntryCandidate(
            routeKind: stringValue(object["route_kind"]),
            source: stringValue(object["source"]),
            host: stringValue(object["host"]),
            publicBaseURL: stringValue(object["public_base_url"]),
            usable: boolValue(object["usable"]),
            requiresSamePrivateNetwork: boolValue(object["requires_same_private_network"]),
            requiresMTLS: boolValue(object["requires_mtls"]),
            classification: RustHubRemoteEntryClassification(
                kind: stringValue(classification["kind"]),
                scope: stringValue(classification["scope"]),
                stable: boolValue(classification["stable"]),
                encryptedPrivateCandidate: boolValue(classification["encrypted_private_candidate"]),
                reasonCode: stringValue(classification["reason_code"])
            )
        )
    }

    private static func detailSummary(
        health: [String: Any],
        readiness: [String: Any],
        package: RustHubEmbeddedPackageInfo
    ) -> String {
        var parts: [String] = []
        if package.valid {
            parts.append("embedded package ready")
        } else if package.exists {
            parts.append("embedded package incomplete")
        } else {
            parts.append("embedded package missing")
        }
        let checks = readiness["checks"] as? [[String: Any]] ?? []
        let failedBlocking = checks.filter { boolValue($0["blocking"]) && !boolValue($0["ok"]) }
        if failedBlocking.isEmpty {
            if boolValue(readiness["ready"]) {
                parts.append("readiness checks passed")
            }
        } else {
            let names = failedBlocking.map { stringValue($0["name"]) }.filter { !$0.isEmpty }
            parts.append("blocking: \(names.joined(separator: ", "))")
        }
        let grpcCompat = stringValue(health["grpc_compat"])
        if !grpcCompat.isEmpty {
            parts.append("grpc \(grpcCompat)")
        }
        return parts.joined(separator: " · ")
    }

    private static func stringValue(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue
        default:
            return ""
        }
    }

    private static func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["1", "true", "yes", "y", "on"].contains(normalized)
        default:
            return false
        }
    }

    private static func firstNonEmpty(_ values: String...) -> String {
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
