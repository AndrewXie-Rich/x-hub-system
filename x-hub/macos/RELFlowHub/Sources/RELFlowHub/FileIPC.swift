import Foundation
import Darwin
import RELFlowHubCore

// File-based IPC for sandboxed builds.
// Clients write one JSON file per request into a dropbox directory.
// Hub polls and processes files, then deletes them.

struct HubStatus: Codable {
    var pid: Int32
    var startedAt: Double
    var updatedAt: Double
    var ipcMode: String
    var ipcPath: String
    var baseDir: String
    var protocolVersion: Int

    // Debug/diagnostics so clients can tell which Hub build is writing the heartbeat.
    var appVersion: String
    var appBuild: String
    var appPath: String

    // AI readiness snapshot for clients (e.g. FA Tracker) to gate AI UI.
    var aiReady: Bool
    var loadedModelCount: Int
    var modelsUpdatedAt: Double
}

private struct FileIPCInternalStatus: Codable {
    var pid: Int32
    var startedAt: Double
    var updatedAt: Double
    var lastHeartbeatAt: Double
    var lastDrainAt: Double
    var lastDrainFilesSeen: Int
}

final class FileIPC: @unchecked Sendable {
    private let store: HubStore
    private let baseDir: URL
    private let eventsDir: URL
    private let responsesDir: URL
    private let statusFile: URL
    private let internalStatusFile: URL

    // Use GCD timers on a global queue; a private serial queue can still be starved
    // under certain AppKit event-tracking / app-nap scenarios.
    private let pollQueue = DispatchQueue.global(qos: .utility)
    private let heartbeatQueue = DispatchQueue.global(qos: .utility)
    private var pollTimer: DispatchSourceTimer?
    private var heartbeatTimer: DispatchSourceTimer?
    private let startedAt = Date().timeIntervalSince1970

    init(store: HubStore) {
        self.store = store

        // Preferred shared base dir for the whole REL Flow Hub suite.
        //
        // - In signed/distributed builds, App Group gives us a stable cross-app directory.
        // - In dev/ad-hoc builds, SharedPaths.appGroupDirectory() returns nil to avoid TCC spam,
        //   and we fall back to the app container / home-based directory.
        let group = SharedPaths.appGroupDirectory()
        let container = SharedPaths.containerDataDirectory()?.appendingPathComponent("RELFlowHub", isDirectory: true)
        self.baseDir = group ?? container ?? SharedPaths.ensureHubDirectory()
        self.eventsDir = baseDir.appendingPathComponent("ipc_events", isDirectory: true)
        self.responsesDir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        self.statusFile = baseDir.appendingPathComponent("hub_status.json")
        self.internalStatusFile = baseDir.appendingPathComponent("file_ipc_status.json")

        writeInternalStatus(lastHeartbeatAt: 0, lastDrainAt: 0, lastDrainFilesSeen: 0)
    }

    private func secureDirectory(_ dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rc = dir.path.withCString { ptr in
            Darwin.chmod(ptr, mode_t(0o700))
        }
        guard rc == 0 else {
            throw NSError(
                domain: "relflowhub.fileipc",
                code: 1,
                userInfo: [
                    "path": dir.path,
                    "label": "chmod_dir",
                    "errno": errno,
                ]
            )
        }
    }

    private func secureFile(_ url: URL) throws {
        let rc = url.path.withCString { ptr in
            Darwin.chmod(ptr, mode_t(0o600))
        }
        guard rc == 0 else {
            throw NSError(
                domain: "relflowhub.fileipc",
                code: 2,
                userInfo: [
                    "path": url.path,
                    "label": "chmod_file",
                    "errno": errno,
                ]
            )
        }
    }

    private func writeProtectedData(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
            try secureFile(url)
        } catch {
            return
        }
    }

    private func writeProtectedData(_ data: Data, tmp: URL, out: URL) {
        do {
            try? FileManager.default.removeItem(at: tmp)
            try data.write(to: tmp, options: .atomic)
            try secureFile(tmp)
            if FileManager.default.fileExists(atPath: out.path) {
                try? FileManager.default.removeItem(at: out)
            }
            try FileManager.default.moveItem(at: tmp, to: out)
            try secureFile(out)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    private func isTrustedInboundEventFile(_ url: URL) -> Bool {
        var st = stat()
        let rc = url.path.withCString { ptr in
            Darwin.lstat(ptr, &st)
        }
        guard rc == 0 else { return false }
        guard (st.st_mode & S_IFMT) == S_IFREG else { return false }
        return st.st_uid == Darwin.geteuid()
    }

    func start() throws {
        try secureDirectory(baseDir)
        try secureDirectory(eventsDir)
        try secureDirectory(responsesDir)

        // Poll new event files.
        let poll = DispatchSource.makeTimerSource(queue: pollQueue)
        poll.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(350))
        poll.setEventHandler { [weak self] in self?.drainOnce() }
        poll.resume()
        pollTimer = poll

        // Heartbeat for clients to detect hub.
        let hb = DispatchSource.makeTimerSource(queue: heartbeatQueue)
        hb.schedule(deadline: .now() + .milliseconds(100), repeating: .seconds(1))
        hb.setEventHandler { [weak self] in self?.writeHeartbeat() }
        hb.resume()
        heartbeatTimer = hb

        writeHeartbeat()
        writeInternalStatus(lastHeartbeatAt: Date().timeIntervalSince1970, lastDrainAt: 0, lastDrainFilesSeen: 0)
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    func ipcPathText() -> String {
        eventsDir.path
    }

    private func writeHeartbeat() {
        // Read from disk so this works even if main-actor stores/timers are stalled.
        let ms = ModelStateStorage.load()
        let loaded = ms.models.filter { $0.state == .loaded }.count

        // Mark AI ready only when a real runtime is alive; avoids "loaded" UI lying.
        let rt = AIRuntimeStatusStorage.load()
        let runtimeAlive = (rt?.isAlive(ttl: 3.0) ?? false) && (rt?.hasReadyProvider(ttl: 3.0) ?? false)

        let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let appBuild = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        let appPath = Bundle.main.bundleURL.path

        let st = HubStatus(
            pid: getpid(),
            startedAt: startedAt,
            updatedAt: Date().timeIntervalSince1970,
            ipcMode: "file",
            ipcPath: eventsDir.path,
            baseDir: baseDir.path,
            protocolVersion: 1,
            appVersion: appVersion,
            appBuild: appBuild,
            appPath: appPath,
            aiReady: runtimeAlive && loaded > 0,
            loadedModelCount: loaded,
            modelsUpdatedAt: ms.updatedAt
        )
        if let data = try? JSONEncoder().encode(st) {
            writeProtectedData(data, to: statusFile)
        }

        writeInternalStatus(lastHeartbeatAt: Date().timeIntervalSince1970, lastDrainAt: 0, lastDrainFilesSeen: -1)
    }

    private func drainOnce() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: eventsDir, includingPropertiesForKeys: nil) else {
            return
        }
        if files.isEmpty { return }

        writeInternalStatus(lastHeartbeatAt: 0, lastDrainAt: Date().timeIntervalSince1970, lastDrainFilesSeen: files.count)

        // Cap work per tick so we don't block the main thread if an agent bursts.
        // We'll catch up in subsequent ticks.
        let batch = Array(files.prefix(64))

        let decoder = JSONDecoder()
        for url in batch {
            // Only process json files.
            if url.pathExtension.lowercased() != "json" {
                continue
            }
            guard isTrustedInboundEventFile(url) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            guard let data = try? Data(contentsOf: url) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            defer {
                try? FileManager.default.removeItem(at: url)
            }
            guard let req = try? decoder.decode(IPCRequest.self, from: data) else {
                continue
            }
            handle(req)
        }
    }

    private func handle(_ req: IPCRequest) {
        if req.type == "push_notification" {
            if let n = req.notification {
                Task { @MainActor in
                    self.store.push(n)
                }
            }
            return
        }
        if req.type == "project_sync" {
            if let p = req.project {
                _ = HubProjectRegistryStorage.upsert(p)
            }
            return
        }
        if req.type == "project_canonical_memory" {
            if let payload = req.projectCanonicalMemory {
                let snapshot = HubProjectCanonicalMemorySnapshot(
                    projectId: payload.projectId,
                    projectRoot: payload.projectRoot ?? "",
                    displayName: payload.displayName ?? payload.projectId,
                    updatedAt: payload.updatedAt ?? Date().timeIntervalSince1970,
                    items: payload.items.map { row in
                        HubProjectCanonicalMemoryItem(key: row.key, value: row.value)
                    }
                )
                _ = HubProjectCanonicalMemoryStorage.upsert(snapshot)
            }
            return
        }
        if req.type == "device_canonical_memory" {
            if let payload = req.deviceCanonicalMemory {
                let snapshot = HubDeviceCanonicalMemorySnapshot(
                    supervisorId: payload.supervisorId,
                    displayName: payload.displayName ?? payload.supervisorId,
                    updatedAt: payload.updatedAt ?? Date().timeIntervalSince1970,
                    items: payload.items.map { row in
                        HubDeviceCanonicalMemoryItem(key: row.key, value: row.value)
                    }
                )
                _ = HubDeviceCanonicalMemoryStorage.upsert(snapshot)
            }
            return
        }
        if req.type == "need_network" {
            if let n = req.network {
                let rid = (req.reqId ?? n.id).trimmingCharacters(in: .whitespacesAndNewlines)
                Task { @MainActor in
                    let decision = self.store.handleNetworkRequest(n)
                    if !rid.isEmpty {
                        self.writeResponse(reqId: rid, decision: decision, networkId: n.id)
                    }
                }
            }
            return
        }
        if req.type == "memory_context" {
            let rid = (req.reqId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rid.isEmpty else { return }
            guard let payload = req.memoryContext else {
                writeResponse(IPCResponse(type: "memory_context_ack", reqId: rid, ok: false, id: nil, error: "missing_memory_context"))
                return
            }
            let built = HubMemoryContextBuilder.build(from: payload)
            writeResponse(IPCResponse(type: "memory_context_ack", reqId: rid, ok: true, id: nil, error: nil, memoryContext: built))
            return
        }
        if req.type == "memory_retrieval" {
            let rid = (req.reqId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rid.isEmpty else { return }
            guard let payload = req.memoryRetrieval else {
                writeResponse(IPCResponse(type: "memory_retrieval_ack", reqId: rid, ok: false, id: nil, error: "missing_memory_retrieval"))
                return
            }
            let built = HubMemoryRetrievalBuilder.build(from: payload)
            writeResponse(IPCResponse(type: "memory_retrieval_ack", reqId: rid, ok: true, id: nil, error: nil, memoryRetrieval: built))
            return
        }
        if req.type == "voice_wake_profile_get" {
            let rid = (req.reqId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rid.isEmpty else { return }
            guard let payload = req.voiceWakeProfileRequest else {
                writeResponse(IPCResponse(type: "voice_wake_profile_ack", reqId: rid, ok: false, id: nil, error: "missing_voice_wake_profile_request"))
                return
            }
            let profile = HubVoiceWakeProfileStorage.fetch(desiredWakeMode: payload.desiredWakeMode)
            writeResponse(IPCResponse(type: "voice_wake_profile_ack", reqId: rid, ok: true, id: profile.profileID, error: nil, voiceWakeProfile: profile))
            return
        }
        if req.type == "voice_wake_profile_set" {
            let rid = (req.reqId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rid.isEmpty else { return }
            guard let payload = req.voiceWakeProfile else {
                writeResponse(IPCResponse(type: "voice_wake_profile_ack", reqId: rid, ok: false, id: nil, error: "missing_voice_wake_profile"))
                return
            }
            let profile = HubVoiceWakeProfileStorage.update(profile: payload)
            writeResponse(IPCResponse(type: "voice_wake_profile_ack", reqId: rid, ok: true, id: profile.profileID, error: nil, voiceWakeProfile: profile))
            return
        }
        if req.type == "secret_vault_list" {
            let rid = (req.reqId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rid.isEmpty else { return }
            guard let payload = req.secretVaultList else {
                writeResponse(IPCResponse(type: "secret_vault_list_ack", reqId: rid, ok: false, id: nil, error: "missing_secret_vault_list"))
                return
            }
            let snapshot = HubSecretVaultStorage.list(payload: payload, baseDir: baseDir)
            writeResponse(IPCResponse(type: "secret_vault_list_ack", reqId: rid, ok: true, id: nil, error: nil, secretVaultSnapshot: snapshot))
            return
        }
        if req.type == "secret_vault_create" {
            let rid = (req.reqId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rid.isEmpty else { return }
            writeResponse(IPCResponse(type: "secret_vault_create_ack", reqId: rid, ok: false, id: nil, error: "secret_vault_secure_capture_requires_socket_ipc"))
            return
        }
        if req.type == "secret_vault_begin_use" {
            let rid = (req.reqId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rid.isEmpty else { return }
            guard let payload = req.secretVaultUse else {
                writeResponse(IPCResponse(type: "secret_vault_use_ack", reqId: rid, ok: false, id: nil, error: "missing_secret_vault_use"))
                return
            }
            let result = HubSecretVaultStorage.beginUse(payload: payload, baseDir: baseDir)
            writeResponse(
                IPCResponse(
                    type: "secret_vault_use_ack",
                    reqId: rid,
                    ok: result.ok,
                    id: result.leaseID ?? result.itemID,
                    error: result.ok ? nil : result.reasonCode,
                    secretVaultUse: result
                )
            )
            return
        }
        if req.type == "secret_vault_redeem_use" {
            let rid = (req.reqId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rid.isEmpty else { return }
            writeResponse(
                IPCResponse(
                    type: "secret_vault_redeem_ack",
                    reqId: rid,
                    ok: false,
                    id: nil,
                    error: "secret_vault_redeem_requires_socket_ipc"
                )
            )
            return
        }
        if req.type == "supervisor_incident_audit" {
            guard let payload = req.supervisorIncident else { return }
            Task { @MainActor in
                _ = self.store.appendSupervisorIncidentAudit(payload)
            }
            return
        }
        if req.type == "supervisor_project_action_audit" {
            guard let payload = req.supervisorProjectAction else { return }
            Task { @MainActor in
                _ = self.store.appendSupervisorProjectActionAudit(payload)
            }
            return
        }
        // ping is handled via heartbeat file.
    }

    private func writeResponse(reqId: String, decision: HubStore.NetworkDecision, networkId: String) {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return }

        let resp: IPCResponse = {
            switch decision {
            case .queued:
                return IPCResponse(type: "need_network_ack", reqId: rid, ok: true, id: networkId, error: nil)
            case .autoApproved:
                // Match UnixSocketServer: ok=true and error="auto_approved" to indicate the Hub already granted networking.
                return IPCResponse(type: "need_network_ack", reqId: rid, ok: true, id: networkId, error: "auto_approved")
            case .denied(let reason):
                return IPCResponse(type: "need_network_ack", reqId: rid, ok: false, id: networkId, error: reason)
            }
        }()

        writeResponse(resp)
    }

    private func writeResponse(_ resp: IPCResponse) {
        let rid = (resp.reqId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return }

        let tmp = responsesDir.appendingPathComponent(".resp_\(rid).tmp")
        let out = responsesDir.appendingPathComponent("resp_\(rid).json")
        if let data = try? JSONEncoder().encode(resp) {
            writeProtectedData(data, tmp: tmp, out: out)
        }
    }

    private func writeInternalStatus(lastHeartbeatAt: Double, lastDrainAt: Double, lastDrainFilesSeen: Int) {
        // Merge with previous state so we don't wipe fields when updating only one side.
        var cur: FileIPCInternalStatus? = nil
        if let data = try? Data(contentsOf: internalStatusFile),
           let obj = try? JSONDecoder().decode(FileIPCInternalStatus.self, from: data) {
            cur = obj
        }
        let now = Date().timeIntervalSince1970
        var st = cur ?? FileIPCInternalStatus(
            pid: getpid(),
            startedAt: startedAt,
            updatedAt: now,
            lastHeartbeatAt: 0,
            lastDrainAt: 0,
            lastDrainFilesSeen: 0
        )
        st.pid = getpid()
        st.startedAt = startedAt
        st.updatedAt = now
        if lastHeartbeatAt > 0 { st.lastHeartbeatAt = lastHeartbeatAt }
        if lastDrainAt > 0 { st.lastDrainAt = lastDrainAt }
        if lastDrainFilesSeen >= 0 { st.lastDrainFilesSeen = lastDrainFilesSeen }

        if let data = try? JSONEncoder().encode(st) {
            writeProtectedData(data, to: internalStatusFile)
        }
    }
}
