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

    func start() throws {
        let path = socketPath()

        // Ensure parent directory exists (especially important under App Sandbox).
        do {
            let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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

        func makeErr(_ code: Int, _ label: String) -> NSError {
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

        listenFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw makeErr(1, "socket") }

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
            let err = makeErr(3, "bind")
            close(listenFD)
            listenFD = -1
            unlink(path)
            throw err
        }

        guard listen(listenFD, 16) == 0 else {
            let err = makeErr(4, "listen")
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

        listenFD = -1
    }


    private func acceptOnce() {
        var addr = sockaddr()
        var len: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
        let fd = Darwin.accept(listenFD, &addr, &len)
        if fd < 0 { return }

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
