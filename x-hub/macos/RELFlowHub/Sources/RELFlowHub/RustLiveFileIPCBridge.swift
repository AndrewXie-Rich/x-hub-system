import Foundation
import Darwin
import RELFlowHubCore

final class RustLiveFileIPCBridge: @unchecked Sendable {
    struct LiveStatus: @unchecked Sendable {
        var raw: [String: Any]
        var baseDir: URL
        var eventsDir: URL
        var responsesDir: URL
        var updatedAt: TimeInterval
    }

    private struct Endpoint: Sendable {
        var role: String
        var baseDir: URL
        var eventsDir: URL
        var responsesDir: URL
        var statusFile: URL
    }

    private struct ForwardedRequest: Sendable {
        var reqId: String
        var responsesDir: URL
        var forwardedAt: TimeInterval
    }

    private static let defaultStatusTTL: TimeInterval = 5
    private static let liveStatusCacheTTL: TimeInterval = 1
    private static let forwardedResponseTTL: TimeInterval = 90
    private static let endpointFailureBackoff: TimeInterval = 60
    private static let httpFallbackCacheTTL: TimeInterval = 2
    private static let aliasHeartbeatMinWriteInterval: TimeInterval = 2
    private static let compatibilityIdleScanInterval: TimeInterval = 1.5
    private static let compatibilityBusyScanInterval: TimeInterval = 3
    private static let primaryEventIdleScanInterval: TimeInterval = 0.7
    private static let primaryEventBusyScanInterval: TimeInterval = 0.25
    private static let eventDirectoryMissingBackoff: TimeInterval = 3
    private static let ignoredEventFileBackoff: TimeInterval = 10 * 60
    private static let compatibilityEventReplayWindow: TimeInterval = 6 * 60 * 60
    private static let maxCompatibilityEventFilesPerEndpoint = 12
    private static let maxCompatibilityDirectoryEntriesPerScan = 512
    private static let maxEventFileBytes = 4 * 1024 * 1024
    private static let startupEnvironment = ProcessInfo.processInfo.environment
    private static let rustKernelEventTypes: Set<String> = [
        "project_sync",
        "project_canonical_memory",
        "device_canonical_memory",
        "memory_context",
        "memory_retrieval",
        "local_task_execute",
    ]

    private let primaryEndpoint: Endpoint
    private let compatibilityEndpoints: [Endpoint]
    private let allEndpoints: [Endpoint]
    private let localBaseDirPaths: Set<String>
    private let statusTTL: TimeInterval
    private let liveBaseDirCandidates: [URL]
    private let liveStatusOverride: ((TimeInterval) -> LiveStatus?)?
    private let httpLiveStatusOverride: ((TimeInterval) -> LiveStatus?)?
    private let runCompatibilityWorkInline: Bool
    private let httpBaseURLString: String
    private let stateLock = NSLock()
    private let compatibilityQueue = DispatchQueue(label: "xhub.rust-live-file-ipc.compat", qos: .utility)
    private var forwardedRequests: [String: ForwardedRequest] = [:]
    private var disabledEndpointUntil: [String: TimeInterval] = [:]
    private var compatibilityWorkInFlight = false
    private var aliasHeartbeatWrittenAt: [String: TimeInterval] = [:]
    private var lastCompatibilityDropboxScanAt: TimeInterval = 0
    private var lastCompatibilityDropboxWorkCount = 0
    private var lastPrimaryEventScanAt: TimeInterval = 0
    private var lastPrimaryEventForwardedCount = 0
    private var missingEventDirectoryBackoffUntil: [String: TimeInterval] = [:]
    private var ignoredEventFileBackoffUntil: [String: TimeInterval] = [:]
    private var liveStatusCacheCheckedAt: TimeInterval = 0
    private var liveStatusCache: LiveStatus?
    private var httpFallbackCheckedAt: TimeInterval = 0
    private var httpFallbackStatus: LiveStatus?

    init(
        appBaseDir: URL,
        appEventsDir: URL,
        appResponsesDir: URL,
        appStatusFile: URL,
        statusTTL: TimeInterval = RustLiveFileIPCBridge.defaultStatusTTL,
        compatBaseDirs: [URL]? = nil,
        liveBaseDirCandidates: () -> [URL] = {
            RustLiveFileIPCBridge.defaultLiveBaseDirCandidates()
        },
        liveStatusOverride: ((TimeInterval) -> LiveStatus?)? = nil,
        httpLiveStatusOverride: ((TimeInterval) -> LiveStatus?)? = nil,
        runCompatibilityWorkInline: Bool = false
    ) {
        let normalizedAppBase = appBaseDir.standardizedFileURL
        let primaryEndpoint = Endpoint(
            role: "primary",
            baseDir: normalizedAppBase,
            eventsDir: appEventsDir.standardizedFileURL,
            responsesDir: appResponsesDir.standardizedFileURL,
            statusFile: appStatusFile.standardizedFileURL
        )
        let compatibilityBaseDirs = compatBaseDirs
            ?? RustLiveFileIPCBridge.defaultCompatibilityBaseDirCandidates(appBaseDir: normalizedAppBase)
        let compatibilityEndpoints = RustLiveFileIPCBridge.compatibilityEndpoints(
            appBaseDir: normalizedAppBase,
            baseDirs: compatibilityBaseDirs
        )
        let allEndpoints = [primaryEndpoint] + compatibilityEndpoints
        self.primaryEndpoint = primaryEndpoint
        self.compatibilityEndpoints = compatibilityEndpoints
        self.allEndpoints = allEndpoints
        self.localBaseDirPaths = Set(allEndpoints.map(\.baseDir.path))
        self.statusTTL = statusTTL
        self.liveBaseDirCandidates = RustLiveFileIPCBridge.normalizedBaseDirCandidates(liveBaseDirCandidates())
        self.liveStatusOverride = liveStatusOverride
        self.httpLiveStatusOverride = httpLiveStatusOverride
        self.runCompatibilityWorkInline = runCompatibilityWorkInline
        self.httpBaseURLString = RustLiveFileIPCBridge.defaultHTTPBaseURL()
    }

    @discardableResult
    func publishAliasHeartbeat(
        fallbackStatus: HubStatus,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool {
        guard let live = resolveLiveStatus(now: now) else {
            return false
        }

        let endpoints = writableEndpoints(now: now).filter { !samePath(live.baseDir, $0.baseDir) }
        var wrote = false
        for endpoint in endpoints where endpoint.role == "primary" {
            if publishAliasHeartbeat(to: endpoint, live: live, fallbackStatus: fallbackStatus, now: now) {
                wrote = true
            } else {
                markEndpointWriteFailure(endpoint, now: now)
            }
        }

        let compatibility = endpoints.filter {
            $0.role != "primary" && aliasHeartbeatWriteIntervalDue(to: $0, now: now)
        }
        if !compatibility.isEmpty {
            scheduleCompatibilityWork { [weak self] in
                guard let self else { return }
                for endpoint in compatibility {
                    if !self.publishAliasHeartbeat(to: endpoint, live: live, fallbackStatus: fallbackStatus, now: now) {
                        self.markEndpointWriteFailure(endpoint, now: now)
                    }
                }
            }
        }
        return wrote
    }

    @discardableResult
    func bridgeDropboxes(
        maxFiles: Int = 64,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool {
        pruneForwardedRequests(now: now)
        guard let live = resolveLiveStatus(now: now) else {
            return false
        }

        let endpoints = writableEndpoints(now: now).filter { !samePath(live.baseDir, $0.baseDir) }
        var bridged = false
        for endpoint in endpoints where endpoint.role == "primary" {
            _ = mirrorForwardedResponses(from: live, to: endpoint)
            if shouldRunPrimaryEventScan(now: now) {
                let forwarded = forwardKernelEvents(from: endpoint, to: live, maxFiles: maxFiles, now: now)
                recordPrimaryEventScan(forwardedCount: forwarded, now: now)
            }
            bridged = true
        }

        let compatibility = endpoints.filter { $0.role != "primary" }
        if !compatibility.isEmpty {
            if shouldRunCompatibilityDropboxScan(now: now) {
                scheduleCompatibilityWork { [weak self] in
                    guard let self else { return }
                    var workCount = 0
                    for endpoint in compatibility {
                        workCount += self.mirrorForwardedResponses(from: live, to: endpoint)
                        workCount += self.forwardKernelEvents(
                            from: endpoint,
                            to: live,
                            maxFiles: min(maxFiles, Self.maxCompatibilityEventFilesPerEndpoint),
                            now: now
                        )
                    }
                    self.recordCompatibilityDropboxScan(workCount: workCount, now: now)
                }
            }
            bridged = true
        }
        return bridged
    }

    static func defaultLiveBaseDirCandidates(environment: [String: String]? = nil) -> [URL] {
        let environment = environment ?? startupEnvironment
        var candidates: [URL] = []
        var seen: Set<String> = []

        func appendPath(_ raw: String?) {
            let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let expanded = NSString(string: trimmed).expandingTildeInPath
            appendURL(URL(fileURLWithPath: expanded, isDirectory: true))
        }

        func appendURL(_ url: URL) {
            let normalized = url.standardizedFileURL
            guard seen.insert(normalized.path).inserted else { return }
            candidates.append(normalized)
        }

        for key in [
            "XHUB_RUST_XT_FILE_IPC_BASE_DIR",
            "XHUB_RUST_XT_CLASSIC_HUB_BASE_DIR",
            "REL_FLOW_HUB_BASE_DIR",
        ] {
            appendPath(environment[key])
        }

        let homes = [
            SharedPaths.realHomeDirectory(),
            SharedPaths.guessedRealUserHomeDirectory(),
            FileManager.default.homeDirectoryForCurrentUser,
        ].compactMap { $0 }

        for home in homes {
            appendURL(home.appendingPathComponent("RELFlowHub", isDirectory: true))
            appendURL(home.appendingPathComponent("XHub", isDirectory: true))
        }

        appendURL(URL(fileURLWithPath: "/private/tmp/RELFlowHub", isDirectory: true))
        appendURL(URL(fileURLWithPath: "/private/tmp/XHub", isDirectory: true))
        return candidates
    }

    private static func normalizedBaseDirCandidates(_ urls: [URL]) -> [URL] {
        var candidates: [URL] = []
        var seen: Set<String> = []
        for url in urls {
            let normalized = url.standardizedFileURL
            guard seen.insert(normalized.path).inserted else { continue }
            candidates.append(normalized)
        }
        return candidates
    }

    static func defaultCompatibilityBaseDirCandidates(
        appBaseDir: URL,
        environment: [String: String]? = nil
    ) -> [URL] {
        let environment = environment ?? startupEnvironment
        var candidates: [URL] = []
        var seen: Set<String> = [appBaseDir.standardizedFileURL.path]

        func appendURL(_ url: URL, requireExisting: Bool = false) {
            let normalized = url.standardizedFileURL
            guard seen.insert(normalized.path).inserted else { return }
            if requireExisting {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    return
                }
            }
            candidates.append(normalized)
        }

        func appendPath(_ raw: String?, requireExisting: Bool = false) {
            let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let expanded = NSString(string: trimmed).expandingTildeInPath
            appendURL(URL(fileURLWithPath: expanded, isDirectory: true), requireExisting: requireExisting)
        }

        if let raw = environment["XHUB_SWIFT_SHELL_COMPAT_BASE_DIRS"] {
            for path in raw.split(separator: ":", omittingEmptySubsequences: true) {
                appendPath(String(path))
            }
        }

        if let group = SharedPaths.appGroupDirectory() {
            appendURL(group)
        }

        let homes = [
            SharedPaths.realHomeDirectory(),
            SharedPaths.guessedRealUserHomeDirectory(),
            FileManager.default.homeDirectoryForCurrentUser,
        ].compactMap { $0 }
        for home in homes {
            let legacyGroup = home
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Group Containers", isDirectory: true)
                .appendingPathComponent(SummaryStorage.appGroupId, isDirectory: true)
            appendURL(legacyGroup, requireExisting: true)
        }

        return candidates
    }

    private static func compatibilityEndpoints(appBaseDir: URL, baseDirs: [URL]) -> [Endpoint] {
        var endpoints: [Endpoint] = []
        var seen: Set<String> = [appBaseDir.standardizedFileURL.path]
        for baseDir in baseDirs {
            let base = baseDir.standardizedFileURL
            guard seen.insert(base.path).inserted else { continue }
            endpoints.append(
                Endpoint(
                    role: "compat",
                    baseDir: base,
                    eventsDir: base.appendingPathComponent("ipc_events", isDirectory: true),
                    responsesDir: base.appendingPathComponent("ipc_responses", isDirectory: true),
                    statusFile: base.appendingPathComponent("hub_status.json")
                )
            )
        }
        return endpoints
    }

    private func resolveLiveStatus(now: TimeInterval) -> LiveStatus? {
        if let liveStatusOverride {
            return liveStatusOverride(now)
        }

        if let cached = cachedLiveStatus(now: now) {
            return cached
        }

        for candidate in liveBaseDirCandidates {
            if let status = readLiveStatus(candidate: candidate, now: now) {
                guard !isLocalEndpoint(status.baseDir) else {
                    continue
                }
                cacheLiveStatus(status, checkedAt: now)
                return status
            }
        }
        let status = resolveHTTPHealthLiveStatus(now: now)
        if let status {
            cacheLiveStatus(status, checkedAt: now)
        }
        return status
    }

    private func readLiveStatus(candidate: URL, now: TimeInterval) -> LiveStatus? {
        let statusURL = candidate.appendingPathComponent("hub_status.json")
        guard let data = try? Data(contentsOf: statusURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let updatedAt = doubleValue(raw["updatedAt"]),
              updatedAt > 0,
              (now - updatedAt) >= 0,
              (now - updatedAt) <= statusTTL else {
            return nil
        }

        let statusBaseDir = stringValue(raw["baseDir"])
        let baseDir = statusBaseDir.isEmpty
            ? candidate.standardizedFileURL
            : URL(fileURLWithPath: NSString(string: statusBaseDir).expandingTildeInPath, isDirectory: true).standardizedFileURL
        let statusIPCPath = stringValue(raw["ipcPath"])
        let eventsDir = statusIPCPath.isEmpty
            ? baseDir.appendingPathComponent("ipc_events", isDirectory: true)
            : URL(fileURLWithPath: NSString(string: statusIPCPath).expandingTildeInPath, isDirectory: true).standardizedFileURL
        return LiveStatus(
            raw: raw,
            baseDir: baseDir,
            eventsDir: eventsDir,
            responsesDir: baseDir.appendingPathComponent("ipc_responses", isDirectory: true),
            updatedAt: updatedAt
        )
    }

    private func resolveHTTPHealthLiveStatus(now: TimeInterval) -> LiveStatus? {
        let cached = cachedHTTPFallbackStatus(now: now)
        if let cached {
            return cached
        }
        if recentlyCheckedHTTPFallback(now: now) {
            return nil
        }

        let status: LiveStatus?
        if let httpLiveStatusOverride {
            status = httpLiveStatusOverride(now)
        } else {
            status = fetchHTTPHealthLiveStatus(now: now)
        }

        if let status, !isLocalEndpoint(status.baseDir) {
            setHTTPFallbackStatus(status, checkedAt: now)
        } else {
            setHTTPFallbackStatus(nil, checkedAt: now)
        }
        return status
    }

    private func fetchHTTPHealthLiveStatus(now: TimeInterval) -> LiveStatus? {
        guard let url = URL(string: httpBaseURL().appending("/health")) else {
            return nil
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.25
        config.timeoutIntervalForResource = 0.25
        let session = URLSession(configuration: config)
        let semaphore = DispatchSemaphore(value: 0)
        let box = HTTPResponseBox()

        let task = session.dataTask(with: url) { data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (object["ok"] as? Bool) == true else {
                return
            }
            box.object = object
        }
        task.resume()
        if semaphore.wait(timeout: .now() + .milliseconds(300)) == .timedOut {
            task.cancel()
            session.invalidateAndCancel()
            return nil
        }
        session.finishTasksAndInvalidate()

        guard let health = box.object,
              let liveBase = httpFallbackLiveBaseDir() else {
            return nil
        }

        let eventsDir = liveBase.appendingPathComponent("ipc_events", isDirectory: true)
        let httpAddr = stringValue(health["http_addr"]).isEmpty
            ? "127.0.0.1:50151"
            : stringValue(health["http_addr"])
        let raw: [String: Any] = [
            "updatedAt": now,
            "ipcMode": "file",
            "ipcPath": eventsDir.path,
            "baseDir": liveBase.path,
            "protocolVersion": 1,
            "aiReady": true,
            "loadedModelCount": 0,
            "modelsUpdatedAt": now,
            "rustHub": [
                "schema_version": "xhub.rust_hub.xt_classic_status.v1",
                "authority": "swift_shell_http_health_fallback",
                "http_addr": httpAddr,
            ],
        ]
        return LiveStatus(
            raw: raw,
            baseDir: liveBase,
            eventsDir: eventsDir,
            responsesDir: liveBase.appendingPathComponent("ipc_responses", isDirectory: true),
            updatedAt: now
        )
    }

    private func httpBaseURL() -> String {
        httpBaseURLString
    }

    private static func defaultHTTPBaseURL(environment: [String: String]? = nil) -> String {
        let environment = environment ?? startupEnvironment
        let raw = (environment["XHUB_RUST_HUB_HTTP_BASE_URL"] ?? environment["XHUB_RUST_HUB_BASE_URL"] ?? "http://127.0.0.1:50151")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "http://127.0.0.1:50151" : raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func httpFallbackLiveBaseDir() -> URL? {
        liveBaseDirCandidates.first { !isLocalEndpoint($0) }
    }

    private func publishAliasHeartbeat(
        to endpoint: Endpoint,
        live: LiveStatus,
        fallbackStatus: HubStatus,
        now: TimeInterval
    ) -> Bool {
        guard aliasHeartbeatWriteIntervalDue(to: endpoint, now: now) else {
            return true
        }

        var object = live.raw
        object["updatedAt"] = now
        object["ipcMode"] = "file"
        object["ipcPath"] = live.eventsDir.path
        object["baseDir"] = live.baseDir.path
        object["protocolVersion"] = intValue(object["protocolVersion"]) ?? fallbackStatus.protocolVersion
        object["appVersion"] = fallbackStatus.appVersion
        object["appBuild"] = fallbackStatus.appBuild
        object["appPath"] = fallbackStatus.appPath
        if object["pid"] == nil { object["pid"] = fallbackStatus.pid }
        if object["startedAt"] == nil { object["startedAt"] = fallbackStatus.startedAt }
        if object["aiReady"] == nil { object["aiReady"] = fallbackStatus.aiReady }
        if object["loadedModelCount"] == nil { object["loadedModelCount"] = fallbackStatus.loadedModelCount }
        if object["modelsUpdatedAt"] == nil { object["modelsUpdatedAt"] = fallbackStatus.modelsUpdatedAt }
        object["swiftShellBridge"] = [
            "schema_version": "xhub.swift_shell.file_ipc_bridge.v1",
            "mode": "app_group_alias",
            "app_base_dir": primaryEndpoint.baseDir.path,
            "compat_base_dir": endpoint.baseDir.path,
            "endpoint_role": endpoint.role,
            "rust_live_base_dir": live.baseDir.path,
        ]

        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return false
        }
        let wrote = endpoint.role == "primary"
            ? writeProtectedData(data, to: endpoint.statusFile)
            : writeProtectedHeartbeatData(data, to: endpoint.statusFile)
        if wrote {
            recordAliasHeartbeatWrite(to: endpoint, now: now)
        }
        return wrote
    }

    private func writableEndpoints(now: TimeInterval) -> [Endpoint] {
        stateLock.lock()
        let disabled = disabledEndpointUntil
        stateLock.unlock()
        return allEndpoints.filter { endpoint in
            (disabled[endpoint.baseDir.path] ?? 0) <= now
        }
    }

    private func isLocalEndpoint(_ baseDir: URL) -> Bool {
        localBaseDirPaths.contains(baseDir.standardizedFileURL.path)
    }

    private func markEndpointWriteFailure(_ endpoint: Endpoint, now: TimeInterval) {
        stateLock.lock()
        disabledEndpointUntil[endpoint.baseDir.path] = now + Self.endpointFailureBackoff
        stateLock.unlock()
    }

    private func forwardKernelEvents(from endpoint: Endpoint, to live: LiveStatus, maxFiles: Int, now: TimeInterval) -> Int {
        var forwardedCount = 0
        for url in eventCandidates(
            in: endpoint.eventsDir,
            maxFiles: maxFiles,
            endpointRole: endpoint.role,
            now: now
        ) {
            guard let fileSize = trustedRegularFileSize(url) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            guard fileSize <= Self.maxEventFileBytes,
                  let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let type = stringValue(object["type"])
            guard Self.rustKernelEventTypes.contains(type) else {
                if endpoint.role != "primary" {
                    recordIgnoredEventFile(url, now: now)
                }
                continue
            }

            do {
                try FileManager.default.createDirectory(at: live.eventsDir, withIntermediateDirectories: true)
                let out = uniqueDestination(
                    in: live.eventsDir,
                    preferredName: url.lastPathComponent,
                    now: now
                )
                let tmp = live.eventsDir.appendingPathComponent(".swift_bridge_\(UUID().uuidString).tmp")
                try data.write(to: tmp, options: .atomic)
                try secureFile(tmp)
                try FileManager.default.moveItem(at: tmp, to: out)
                try secureFile(out)
                if let reqId = safeReqId(object) {
                    let key = forwardedRequestKey(reqId: reqId, responsesDir: endpoint.responsesDir)
                    stateLock.lock()
                    forwardedRequests[key] = ForwardedRequest(
                        reqId: reqId,
                        responsesDir: endpoint.responsesDir,
                        forwardedAt: now
                    )
                    stateLock.unlock()
                }
                forwardedCount += 1
                try? FileManager.default.removeItem(at: url)
            } catch {
                continue
            }
        }
        return forwardedCount
    }

    private func eventCandidates(
        in directory: URL,
        maxFiles: Int,
        endpointRole: String,
        now: TimeInterval
    ) -> [URL] {
        guard maxFiles > 0 else {
            return []
        }
        guard !eventDirectoryMissingBackoffActive(directory, now: now) else {
            return []
        }
        guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
              ) else {
            recordMissingEventDirectory(directory, now: now)
            return []
        }
        clearMissingEventDirectory(directory)

        let ignoredBackoff = endpointRole == "primary" ? [:] : ignoredEventFileBackoffSnapshot()
        var newlyIgnoredPaths: [String] = []
        var candidates: [URL] = []
        var inspected = 0
        for case let url as URL in enumerator {
            inspected += 1
            if endpointRole != "primary",
               inspected > Self.maxCompatibilityDirectoryEntriesPerScan {
                break
            }
            guard url.pathExtension.caseInsensitiveCompare("json") == .orderedSame else {
                continue
            }
            let path = url.standardizedFileURL.path
            if (ignoredBackoff[path] ?? 0) > now {
                continue
            }
            if endpointRole != "primary",
               !compatibilityEventFreshEnough(url, now: now) {
                newlyIgnoredPaths.append(path)
                continue
            }
            candidates.append(url)
            if candidates.count >= maxFiles {
                break
            }
        }
        recordIgnoredEventFilePaths(newlyIgnoredPaths, now: now)
        return candidates
    }

    private func aliasHeartbeatWriteIntervalDue(to endpoint: Endpoint, now: TimeInterval) -> Bool {
        stateLock.lock()
        let lastWrittenAt = aliasHeartbeatWrittenAt[endpoint.baseDir.path] ?? 0
        stateLock.unlock()

        guard lastWrittenAt > 0 else { return true }
        let age = now - lastWrittenAt
        return age < 0 || age >= Self.aliasHeartbeatMinWriteInterval
    }

    private func recordAliasHeartbeatWrite(to endpoint: Endpoint, now: TimeInterval) {
        stateLock.lock()
        aliasHeartbeatWrittenAt[endpoint.baseDir.path] = now
        stateLock.unlock()
    }

    private func eventDirectoryMissingBackoffActive(_ directory: URL, now: TimeInterval) -> Bool {
        stateLock.lock()
        let until = missingEventDirectoryBackoffUntil[directory.standardizedFileURL.path] ?? 0
        stateLock.unlock()
        return until > now
    }

    private func recordMissingEventDirectory(_ directory: URL, now: TimeInterval) {
        stateLock.lock()
        missingEventDirectoryBackoffUntil[directory.standardizedFileURL.path] = now + Self.eventDirectoryMissingBackoff
        stateLock.unlock()
    }

    private func clearMissingEventDirectory(_ directory: URL) {
        stateLock.lock()
        missingEventDirectoryBackoffUntil.removeValue(forKey: directory.standardizedFileURL.path)
        stateLock.unlock()
    }

    private func ignoredEventFileBackoffActive(_ url: URL, now: TimeInterval) -> Bool {
        stateLock.lock()
        let until = ignoredEventFileBackoffUntil[url.standardizedFileURL.path] ?? 0
        stateLock.unlock()
        return until > now
    }

    private func ignoredEventFileBackoffSnapshot() -> [String: TimeInterval] {
        stateLock.lock()
        let snapshot = ignoredEventFileBackoffUntil
        stateLock.unlock()
        return snapshot
    }

    private func recordIgnoredEventFile(_ url: URL, now: TimeInterval) {
        stateLock.lock()
        ignoredEventFileBackoffUntil[url.standardizedFileURL.path] = now + Self.ignoredEventFileBackoff
        stateLock.unlock()
    }

    private func recordIgnoredEventFilePaths(_ paths: [String], now: TimeInterval) {
        guard !paths.isEmpty else { return }
        stateLock.lock()
        let until = now + Self.ignoredEventFileBackoff
        for path in paths {
            ignoredEventFileBackoffUntil[path] = until
        }
        stateLock.unlock()
    }

    private func compatibilityEventFreshEnough(_ url: URL, now: TimeInterval) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 else {
            return true
        }
        let age = now - modifiedAt
        return age < 0 || age <= Self.compatibilityEventReplayWindow
    }

    private func mirrorForwardedResponses(from live: LiveStatus, to endpoint: Endpoint) -> Int {
        stateLock.lock()
        let requests = forwardedRequests.values.filter { samePath($0.responsesDir, endpoint.responsesDir) }
        stateLock.unlock()
        guard !requests.isEmpty else { return 0 }
        try? FileManager.default.createDirectory(at: endpoint.responsesDir, withIntermediateDirectories: true)

        var mirroredCount = 0
        for request in requests {
            let source = live.responsesDir.appendingPathComponent("resp_\(request.reqId).json")
            let destination = endpoint.responsesDir.appendingPathComponent("resp_\(request.reqId).json")
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            if FileManager.default.fileExists(atPath: destination.path) {
                continue
            }
            do {
                let data = try Data(contentsOf: source)
                let tmp = endpoint.responsesDir.appendingPathComponent(".resp_\(request.reqId).swift_bridge.tmp")
                try data.write(to: tmp, options: .atomic)
                try secureFile(tmp)
                try FileManager.default.moveItem(at: tmp, to: destination)
                try secureFile(destination)
                mirroredCount += 1
            } catch {
                continue
            }
        }
        return mirroredCount
    }

    private func pruneForwardedRequests(now: TimeInterval) {
        stateLock.lock()
        forwardedRequests = forwardedRequests.filter { _, request in
            (now - request.forwardedAt) <= Self.forwardedResponseTTL
        }
        disabledEndpointUntil = disabledEndpointUntil.filter { _, disabledUntil in
            disabledUntil > now
        }
        missingEventDirectoryBackoffUntil = missingEventDirectoryBackoffUntil.filter { _, backoffUntil in
            backoffUntil > now
        }
        ignoredEventFileBackoffUntil = ignoredEventFileBackoffUntil.filter { _, backoffUntil in
            backoffUntil > now
        }
        stateLock.unlock()
    }

    private func scheduleCompatibilityWork(_ work: @escaping @Sendable () -> Void) {
        if runCompatibilityWorkInline {
            work()
            return
        }

        stateLock.lock()
        guard !compatibilityWorkInFlight else {
            stateLock.unlock()
            return
        }
        compatibilityWorkInFlight = true
        stateLock.unlock()

        compatibilityQueue.async { [weak self] in
            guard let self else { return }
            work()
            self.stateLock.lock()
            self.compatibilityWorkInFlight = false
            self.stateLock.unlock()
        }
    }

    private func shouldRunCompatibilityDropboxScan(now: TimeInterval) -> Bool {
        if runCompatibilityWorkInline {
            return true
        }

        stateLock.lock()
        let lastScanAt = lastCompatibilityDropboxScanAt
        let workCount = lastCompatibilityDropboxWorkCount
        let interval = workCount > 0
            ? Self.compatibilityBusyScanInterval
            : Self.compatibilityIdleScanInterval
        if lastScanAt > 0,
           (now - lastScanAt) >= 0,
           (now - lastScanAt) < interval {
            stateLock.unlock()
            return false
        }
        lastCompatibilityDropboxScanAt = now
        stateLock.unlock()
        return true
    }

    private func shouldRunPrimaryEventScan(now: TimeInterval) -> Bool {
        if runCompatibilityWorkInline {
            return true
        }

        stateLock.lock()
        let lastScanAt = lastPrimaryEventScanAt
        let forwardedCount = lastPrimaryEventForwardedCount
        let interval = forwardedCount > 0
            ? Self.primaryEventBusyScanInterval
            : Self.primaryEventIdleScanInterval
        if lastScanAt > 0,
           (now - lastScanAt) >= 0,
           (now - lastScanAt) < interval {
            stateLock.unlock()
            return false
        }
        lastPrimaryEventScanAt = now
        stateLock.unlock()
        return true
    }

    private func recordPrimaryEventScan(forwardedCount: Int, now: TimeInterval) {
        stateLock.lock()
        lastPrimaryEventScanAt = now
        lastPrimaryEventForwardedCount = forwardedCount
        stateLock.unlock()
    }

    private func recordCompatibilityDropboxScan(workCount: Int, now: TimeInterval) {
        stateLock.lock()
        lastCompatibilityDropboxScanAt = now
        lastCompatibilityDropboxWorkCount = workCount
        stateLock.unlock()
    }

    private func cachedLiveStatus(now: TimeInterval) -> LiveStatus? {
        stateLock.lock()
        let checkedAt = liveStatusCacheCheckedAt
        let cached = liveStatusCache
        stateLock.unlock()
        guard let cached,
              (now - checkedAt) >= 0,
              (now - checkedAt) <= Self.liveStatusCacheTTL,
              (now - cached.updatedAt) >= 0,
              (now - cached.updatedAt) <= statusTTL,
              !isLocalEndpoint(cached.baseDir) else {
            return nil
        }
        return cached
    }

    private func cacheLiveStatus(_ status: LiveStatus, checkedAt: TimeInterval) {
        stateLock.lock()
        liveStatusCache = status
        liveStatusCacheCheckedAt = checkedAt
        stateLock.unlock()
    }

    private func cachedHTTPFallbackStatus(now: TimeInterval) -> LiveStatus? {
        stateLock.lock()
        let checkedAt = httpFallbackCheckedAt
        let cached = httpFallbackStatus
        stateLock.unlock()
        guard let cached, (now - checkedAt) <= Self.httpFallbackCacheTTL else {
            return nil
        }
        return cached
    }

    private func recentlyCheckedHTTPFallback(now: TimeInterval) -> Bool {
        stateLock.lock()
        let checkedAt = httpFallbackCheckedAt
        stateLock.unlock()
        return (now - checkedAt) <= Self.httpFallbackCacheTTL
    }

    private func setHTTPFallbackStatus(_ status: LiveStatus?, checkedAt: TimeInterval) {
        stateLock.lock()
        httpFallbackStatus = status
        httpFallbackCheckedAt = checkedAt
        stateLock.unlock()
    }

    private func writeProtectedData(_ data: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            try secureFile(url)
            return true
        } catch {
            return false
        }
    }

    private func writeProtectedHeartbeatData(_ data: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
            try secureFile(url)
            return true
        } catch {
            return false
        }
    }

    private func uniqueDestination(in directory: URL, preferredName: String, now: TimeInterval) -> URL {
        let preferred = directory.appendingPathComponent(preferredName)
        if !FileManager.default.fileExists(atPath: preferred.path) {
            return preferred
        }

        let base = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension
        let suffix = Int((now * 1000).rounded())
        let name = ext.isEmpty
            ? "\(base).swift_bridge.\(suffix)"
            : "\(base).swift_bridge.\(suffix).\(ext)"
        return directory.appendingPathComponent(name)
    }

    private func forwardedRequestKey(reqId: String, responsesDir: URL) -> String {
        "\(responsesDir.standardizedFileURL.path)\u{0}\(reqId)"
    }

    private func secureFile(_ url: URL) throws {
        let rc = url.path.withCString { ptr in
            Darwin.chmod(ptr, mode_t(0o600))
        }
        guard rc == 0 else {
            throw NSError(
                domain: "relflowhub.rust_live_file_ipc_bridge",
                code: 1,
                userInfo: ["path": url.path, "errno": errno]
            )
        }
    }

    private func trustedRegularFileSize(_ url: URL) -> Int64? {
        var st = stat()
        let rc = url.path.withCString { ptr in
            Darwin.lstat(ptr, &st)
        }
        guard rc == 0 else { return nil }
        guard (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        guard st.st_uid == Darwin.geteuid() else { return nil }
        return Int64(st.st_size)
    }

    private func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private func safeReqId(_ object: [String: Any]) -> String? {
        let raw = stringValue(object["reqId"]).isEmpty
            ? stringValue(object["req_id"])
            : stringValue(object["reqId"])
        guard !raw.isEmpty,
              raw.count <= 160,
              !raw.contains("/"),
              !raw.contains("\\"),
              !raw.contains("\0"),
              !raw.hasPrefix(".") else {
            return nil
        }
        return raw
    }

    private func stringValue(_ value: Any?) -> String {
        if let value = value as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let value = value {
            return String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Float { return Double(value) }
        if let value = value as? Int { return Double(value) }
        if let value = value as? Int64 { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}

private final class HTTPResponseBox: @unchecked Sendable {
    var object: [String: Any]?
}
