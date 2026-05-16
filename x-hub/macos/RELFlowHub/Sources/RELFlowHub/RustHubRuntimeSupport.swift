import Foundation

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
            "XHUB_RUST_HUB_HTTP_BASE_URL": defaultHTTPBaseURL,
            "XHUB_RUST_HTTP_ACCESS_KEY_FILE": URL(fileURLWithPath: rootPath, isDirectory: true)
                .appendingPathComponent("secrets/xhubd_http_access_key")
                .path
        ]
        if let explicitAccessKeyFile = nonEmptyEnvironmentValue(baseEnvironment, "XHUB_RUST_HTTP_ACCESS_KEY_FILE") {
            out["XHUB_RUST_HTTP_ACCESS_KEY_FILE"] = explicitAccessKeyFile
        }
        if let explicitHubAccessKeyFile = nonEmptyEnvironmentValue(baseEnvironment, "XHUB_RUST_HUB_ACCESS_KEY_FILE") {
            out["XHUB_RUST_HUB_ACCESS_KEY_FILE"] = explicitHubAccessKeyFile
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

    private static func fetchData(path: String, authorize: Bool = true) async -> Data? {
        guard let url = URL(string: defaultHTTPBaseURL + path) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        if authorize, let accessKey = httpAccessKey() {
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
                root.appendingPathComponent("secrets/xhubd_lan_access_key")
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

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
