import Foundation
import Dispatch
import Darwin
import RELFlowHubCore

// Minimal AF_UNIX JSONL server.
// This is intentionally tiny and offline-only.
final class UnixSocketServer: @unchecked Sendable {
    private let store: HubStore
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var clientSources: [Int32: DispatchSourceRead] = [:]
    private var clientBuffers: [Int32: Data] = [:]
    private var activeSocketPath: String?

    private let queue = DispatchQueue(label: "com.rel.flowhub.unixsocket")
    private let maxBufferedBytesPerClient = 1_048_576 // 1MB
    private let maxLineBytes = 262_144 // 256KB

    init(store: HubStore) {
        self.store = store
    }

    deinit {
        stop()
    }

    private func socketPath() -> String {
        return SharedPaths.ipcSocketPath()
    }

    private func makeSocketError(_ code: Int, _ label: String, path: String) -> NSError {
        let e = errno
        let msg = String(cString: strerror(e))
        return NSError(
            domain: "relflowhub.socket",
            code: code,
            userInfo: [
                "label": label,
                "errno": e,
                "error": msg,
                "path": path,
            ]
        )
    }

    private func secureDirectory(_ dir: URL, path: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rc = dir.path.withCString { ptr in
            Darwin.chmod(ptr, mode_t(0o700))
        }
        guard rc == 0 else {
            throw makeSocketError(10, "chmod_parent", path: path)
        }
    }

    private func secureSocketFile(path: String) throws {
        let rc = path.withCString { ptr in
            Darwin.chmod(ptr, mode_t(0o600))
        }
        guard rc == 0 else {
            throw makeSocketError(11, "chmod_socket", path: path)
        }
    }

    private func peerMatchesCurrentUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard Darwin.getpeereid(fd, &uid, &gid) == 0 else { return false }
        return uid == Darwin.geteuid()
    }

    func start() throws {
        let path = socketPath()

        // Ensure parent directory exists (especially important under App Sandbox).
        do {
            let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
            try secureDirectory(dir, path: path)
        } catch {
            throw NSError(
                domain: "relflowhub.socket",
                code: 10,
                userInfo: [
                    "label": "mkdir",
                    "path": path,
                    "error": String(describing: error),
                ]
            )
        }

        // Remove existing socket file.
        unlink(path)

        listenFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw makeSocketError(1, "socket", path: path) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let bytes = Array(path.utf8) + [0]
        if bytes.count > maxLen {
            throw NSError(domain: "socket", code: 2)
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: maxLen) { buf in
                for i in 0..<bytes.count {
                    buf[i] = bytes[i]
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindRC = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(listenFD, sa, addrLen)
            }
        }
        guard bindRC == 0 else {
            let err = makeSocketError(3, "bind", path: path)
            close(listenFD)
            listenFD = -1
            unlink(path)
            throw err
        }

        do {
            try secureSocketFile(path: path)
        } catch {
            close(listenFD)
            listenFD = -1
            unlink(path)
            throw error
        }

        guard listen(listenFD, 16) == 0 else {
            let err = makeSocketError(4, "listen", path: path)
            close(listenFD)
            listenFD = -1
            unlink(path)
            throw err
        }

        let src = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
        src.setEventHandler { [weak self] in
            self?.acceptOnce()
        }
        src.setCancelHandler { [fd = listenFD] in
            if fd >= 0 { close(fd) }
        }
        listenSource = src
        activeSocketPath = path
        src.resume()

        // UI state is updated by HubStore after start() returns.
    }

    func stop() {
        if let src = listenSource {
            src.cancel() // cancelHandler closes listenFD
        } else if listenFD >= 0 {
            close(listenFD)
        }
        listenSource = nil

        for (_, src) in clientSources {
            src.cancel() // cancelHandler closes each client fd
        }
        clientSources.removeAll()
        clientBuffers.removeAll()

        if let path = activeSocketPath {
            unlink(path)
        }
        activeSocketPath = nil
        listenFD = -1
    }


    private func acceptOnce() {
        var addr = sockaddr()
        var len: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
        let fd = Darwin.accept(listenFD, &addr, &len)
        if fd < 0 { return }
        guard peerMatchesCurrentUser(fd) else {
            close(fd)
            return
        }

        clientBuffers[fd] = Data()

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in
            self?.readFromClient(fd)
        }
        src.setCancelHandler {
            close(fd)
        }
        clientSources[fd] = src
        src.resume()
    }

    private func readFromClient(_ fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = Darwin.read(fd, &buf, buf.count)
        if n <= 0 {
            cleanupClient(fd)
            return
        }
        if clientBuffers[fd] == nil {
            clientBuffers[fd] = Data()
        }
        clientBuffers[fd]?.append(contentsOf: buf[0..<n])
        if (clientBuffers[fd]?.count ?? 0) > maxBufferedBytesPerClient {
            writeResponse(fd, IPCResponse(type: "error", reqId: nil, ok: false, id: nil, error: "buffer_too_large"))
            cleanupClient(fd)
            return
        }
        drainLines(fd)
    }

    private func drainLines(_ fd: Int32) {
        guard var data = clientBuffers[fd] else { return }
        while true {
            guard let idx = data.firstIndex(of: 0x0A) else { break } // '\n'
            if idx > maxLineBytes {
                writeResponse(fd, IPCResponse(type: "error", reqId: nil, ok: false, id: nil, error: "line_too_long"))
                cleanupClient(fd)
                return
            }
            let lineData = data.prefix(upTo: idx)
            data.removeSubrange(..<data.index(after: idx))
            if let s = String(data: lineData, encoding: .utf8) {
                handleLine(fd, s)
            }
        }
        clientBuffers[fd] = data
    }

    private func handleLine(_ fd: Int32, _ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        guard let raw = trimmed.data(using: .utf8) else { return }

        let decoder = JSONDecoder()
        do {
            let req = try decoder.decode(IPCRequest.self, from: raw)
            handleRequest(fd, req)
        } catch {
            writeResponse(fd, IPCResponse(type: "error", reqId: nil, ok: false, id: nil, error: "invalid_json"))
        }
    }

    private func handleRequest(_ fd: Int32, _ req: IPCRequest) {
        let typ = req.type
        if typ == "ping" {
            writeResponse(fd, IPCResponse(type: "pong", reqId: req.reqId, ok: true, id: nil, error: nil))
            return
        }
        if typ == "push_notification" {
            if var n = req.notification {
                if n.id.isEmpty { n.id = UUID().uuidString }
                let n2 = n
                Task { @MainActor in
                    self.store.push(n2)
                }
                writeResponse(fd, IPCResponse(type: "push_ack", reqId: req.reqId, ok: true, id: n.id, error: nil))
                return
            }
            writeResponse(fd, IPCResponse(type: "push_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_notification"))
            return
        }
        if typ == "project_sync" {
            if let p = req.project {
                _ = HubProjectRegistryStorage.upsert(p)
                writeResponse(fd, IPCResponse(type: "project_ack", reqId: req.reqId, ok: true, id: p.projectId, error: nil))
                return
            }
            writeResponse(fd, IPCResponse(type: "project_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_project"))
            return
        }
        if typ == "project_canonical_memory" {
            guard let payload = req.projectCanonicalMemory else {
                writeResponse(fd, IPCResponse(type: "project_canonical_memory_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_project_canonical_memory"))
                return
            }
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
            writeResponse(fd, IPCResponse(type: "project_canonical_memory_ack", reqId: req.reqId, ok: true, id: payload.projectId, error: nil))
            return
        }
        if typ == "device_canonical_memory" {
            guard let payload = req.deviceCanonicalMemory else {
                writeResponse(fd, IPCResponse(type: "device_canonical_memory_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_device_canonical_memory"))
                return
            }
            let snapshot = HubDeviceCanonicalMemorySnapshot(
                supervisorId: payload.supervisorId,
                displayName: payload.displayName ?? payload.supervisorId,
                updatedAt: payload.updatedAt ?? Date().timeIntervalSince1970,
                items: payload.items.map { row in
                    HubDeviceCanonicalMemoryItem(key: row.key, value: row.value)
                }
            )
            _ = HubDeviceCanonicalMemoryStorage.upsert(snapshot)
            writeResponse(fd, IPCResponse(type: "device_canonical_memory_ack", reqId: req.reqId, ok: true, id: payload.supervisorId, error: nil))
            return
        }
        if typ == "need_network" {
            if let n = req.network {
                Task { @MainActor in
                    let decision = self.store.handleNetworkRequest(n)
                    switch decision {
                    case .queued:
                        writeResponse(fd, IPCResponse(type: "need_network_ack", reqId: req.reqId, ok: true, id: n.id, error: nil))
                    case .autoApproved:
                        writeResponse(fd, IPCResponse(type: "need_network_ack", reqId: req.reqId, ok: true, id: n.id, error: "auto_approved"))
                    case .denied(let reason):
                        writeResponse(fd, IPCResponse(type: "need_network_ack", reqId: req.reqId, ok: false, id: n.id, error: reason))
                    }
                }
                return
            }
            writeResponse(fd, IPCResponse(type: "need_network_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_network_request"))
            return
        }
        if typ == "memory_context" {
            guard let payload = req.memoryContext else {
                writeResponse(fd, IPCResponse(type: "memory_context_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_memory_context"))
                return
            }
            let built = HubMemoryContextBuilder.build(from: payload)
            writeResponse(fd, IPCResponse(type: "memory_context_ack", reqId: req.reqId, ok: true, id: nil, error: nil, memoryContext: built))
            return
        }
        if typ == "memory_retrieval" {
            guard let payload = req.memoryRetrieval else {
                writeResponse(fd, IPCResponse(type: "memory_retrieval_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_memory_retrieval"))
                return
            }
            let built = HubMemoryRetrievalBuilder.build(from: payload)
            writeResponse(fd, IPCResponse(type: "memory_retrieval_ack", reqId: req.reqId, ok: true, id: nil, error: nil, memoryRetrieval: built))
            return
        }
        if typ == "voice_wake_profile_get" {
            guard let payload = req.voiceWakeProfileRequest else {
                writeResponse(fd, IPCResponse(type: "voice_wake_profile_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_voice_wake_profile_request"))
                return
            }
            let profile = HubVoiceWakeProfileStorage.fetch(desiredWakeMode: payload.desiredWakeMode)
            writeResponse(fd, IPCResponse(type: "voice_wake_profile_ack", reqId: req.reqId, ok: true, id: profile.profileID, error: nil, voiceWakeProfile: profile))
            return
        }
        if typ == "voice_wake_profile_set" {
            guard let payload = req.voiceWakeProfile else {
                writeResponse(fd, IPCResponse(type: "voice_wake_profile_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_voice_wake_profile"))
                return
            }
            let profile = HubVoiceWakeProfileStorage.update(profile: payload)
            writeResponse(fd, IPCResponse(type: "voice_wake_profile_ack", reqId: req.reqId, ok: true, id: profile.profileID, error: nil, voiceWakeProfile: profile))
            return
        }
        if typ == "secret_vault_list" {
            guard let payload = req.secretVaultList else {
                writeResponse(fd, IPCResponse(type: "secret_vault_list_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_secret_vault_list"))
                return
            }
            let snapshot = HubSecretVaultStorage.list(payload: payload)
            writeResponse(fd, IPCResponse(type: "secret_vault_list_ack", reqId: req.reqId, ok: true, id: nil, error: nil, secretVaultSnapshot: snapshot))
            return
        }
        if typ == "secret_vault_create" {
            guard let payload = req.secretVaultCreate else {
                writeResponse(fd, IPCResponse(type: "secret_vault_create_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_secret_vault_create"))
                return
            }
            let result = HubSecretVaultStorage.create(payload: payload)
            writeResponse(
                fd,
                IPCResponse(
                    type: "secret_vault_create_ack",
                    reqId: req.reqId,
                    ok: result.ok,
                    id: result.item?.itemID,
                    error: result.ok ? nil : result.reasonCode,
                    secretVaultItem: result.item
                )
            )
            return
        }
        if typ == "secret_vault_begin_use" {
            guard let payload = req.secretVaultUse else {
                writeResponse(fd, IPCResponse(type: "secret_vault_use_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_secret_vault_use"))
                return
            }
            let result = HubSecretVaultStorage.beginUse(payload: payload)
            writeResponse(
                fd,
                IPCResponse(
                    type: "secret_vault_use_ack",
                    reqId: req.reqId,
                    ok: result.ok,
                    id: result.leaseID ?? result.itemID,
                    error: result.ok ? nil : result.reasonCode,
                    secretVaultUse: result
                )
            )
            return
        }
        if typ == "secret_vault_redeem_use" {
            guard let payload = req.secretVaultRedeem else {
                writeResponse(fd, IPCResponse(type: "secret_vault_redeem_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_secret_vault_redeem"))
                return
            }
            let result = HubSecretVaultStorage.redeemUseToken(
                payload.useToken,
                projectID: payload.projectID
            )
            writeResponse(
                fd,
                IPCResponse(
                    type: "secret_vault_redeem_ack",
                    reqId: req.reqId,
                    ok: result.ok,
                    id: result.leaseID ?? result.itemID,
                    error: result.ok ? nil : result.reasonCode,
                    secretVaultRedeem: IPCSecretVaultRedeemResult(
                        ok: result.ok,
                        source: result.source,
                        leaseID: result.leaseID,
                        itemID: result.itemID,
                        plaintext: result.plaintext,
                        reasonCode: result.reasonCode
                    )
                )
            )
            return
        }
        if typ == "supervisor_incident_audit" {
            guard let payload = req.supervisorIncident else {
                writeResponse(fd, IPCResponse(type: "supervisor_incident_audit_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_supervisor_incident"))
                return
            }
            Task { @MainActor in
                let ok = self.store.appendSupervisorIncidentAudit(payload)
                writeResponse(
                    fd,
                    IPCResponse(
                        type: "supervisor_incident_audit_ack",
                        reqId: req.reqId,
                        ok: ok,
                        id: payload.auditRef,
                        error: ok ? nil : "audit_write_failed"
                    )
                )
            }
            return
        }
        if typ == "supervisor_project_action_audit" {
            guard let payload = req.supervisorProjectAction else {
                writeResponse(fd, IPCResponse(type: "supervisor_project_action_audit_ack", reqId: req.reqId, ok: false, id: nil, error: "missing_supervisor_project_action"))
                return
            }
            Task { @MainActor in
                let ok = self.store.appendSupervisorProjectActionAudit(payload)
                writeResponse(
                    fd,
                    IPCResponse(
                        type: "supervisor_project_action_audit_ack",
                        reqId: req.reqId,
                        ok: ok,
                        id: payload.auditRef,
                        error: ok ? nil : "audit_write_failed"
                    )
                )
            }
            return
        }
        writeResponse(fd, IPCResponse(type: "error", reqId: req.reqId, ok: false, id: nil, error: "unknown_type"))
    }

    private func writeResponse(_ fd: Int32, _ resp: IPCResponse) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(resp) else { return }
        var out = data
        out.append(0x0A)
        _ = out.withUnsafeBytes { p in
            Darwin.write(fd, p.baseAddress, out.count)
        }
    }

    private func cleanupClient(_ fd: Int32) {
        if let src = clientSources[fd] {
            src.cancel()
        }
        clientSources.removeValue(forKey: fd)
        clientBuffers.removeValue(forKey: fd)
    }
}
