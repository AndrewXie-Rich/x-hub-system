import Foundation
import Network

@MainActor
final class AXServerManager: ObservableObject {
    static let shared = AXServerManager()
    
    @Published var isRunning: Bool = false
    @Published var port: Int = 8080
    @Published var lastError: String = ""
    @Published var connectedClients: [String] = []
    
    private let defaultPreferredPort: Int = 8080
    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]
    private let eventBus = AXEventBus.shared
    private let fallbackPortSpan: Int = 20
    
    private init() {}
    
    func startServer() async throws {
        guard !isRunning else { return }
        lastError = ""

        let preferred = max(1, min(65_535, defaultPreferredPort))
        let maxPort = min(65_535, preferred + fallbackPortSpan)
        let fallbackCandidates: [Int]
        if preferred < maxPort {
            fallbackCandidates = Array((preferred + 1)...maxPort)
        } else {
            fallbackCandidates = []
        }
        let candidates = [preferred] + fallbackCandidates

        var lastFailure: Error?
        for candidate in candidates {
            do {
                try await startListener(on: candidate, preferredPort: preferred)
                return
            } catch {
                lastFailure = error
                if isAddressInUse(error) {
                    continue
                }
                throw error
            }
        }

        let failure = lastFailure ?? POSIXError(.EADDRINUSE)
        let detail = "Failed to start local server after trying ports \(preferred)...\(maxPort): \(failure)"
        lastError = detail
        throw failure
    }
    
    func stopServer() {
        let wasRunning = isRunning
        
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        
        isRunning = false
        port = defaultPreferredPort
        connectedClients.removeAll()
        
        if wasRunning {
            print("X-Terminal Server stopped")
        }
    }

    func restartServer() async throws {
        stopServer()
        try await startServer()
    }

    private func startListener(on candidatePort: Int, preferredPort: Int) async throws {
        final class ResumeGuard: @unchecked Sendable {
            private let lock = NSLock()
            private var resumed = false

            func claim() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if resumed { return false }
                resumed = true
                return true
            }
        }

        let config = NWParameters.tcp
        config.allowLocalEndpointReuse = true
        config.allowFastOpen = true

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(candidatePort)) else {
            throw POSIXError(.EINVAL)
        }

        let listener = try NWListener(using: config, on: nwPort)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumeGuard = ResumeGuard()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    Task { @MainActor in
                        self?.isRunning = true
                        self?.port = candidatePort
                        self?.lastError = ""
                        if candidatePort == preferredPort {
                            print("X-Terminal Server started on port \(candidatePort)")
                        } else {
                            print("X-Terminal Server started on fallback port \(candidatePort) (preferred \(preferredPort) was busy)")
                        }
                    }
                    if resumeGuard.claim() {
                        cont.resume(returning: ())
                    }

                case .failed(let error):
                    Task { @MainActor in
                        self?.isRunning = false
                        if self?.listener === listener {
                            self?.listener = nil
                        }
                        let detail = "Server failed on port \(candidatePort): \(error)"
                        self?.lastError = detail
                        print(detail)
                    }
                    listener.cancel()
                    if resumeGuard.claim() {
                        cont.resume(throwing: error)
                    }

                default:
                    break
                }
            }

            listener.start(queue: .main)
        }
    }

    private func isAddressInUse(_ error: Error) -> Bool {
        if let nw = error as? NWError {
            if case .posix(let code) = nw {
                return code == .EADDRINUSE
            }
            return false
        }

        if let posix = error as? POSIXError {
            return posix.code == .EADDRINUSE
        }

        let text = String(describing: error).lowercased()
        return text.contains("address already in use")
    }
    
    private func handleConnection(_ connection: NWConnection) {
        let clientId = UUID().uuidString
        connections[clientId] = connection
        
        Task { @MainActor in
            if !connectedClients.contains(clientId) {
                connectedClients.append(clientId)
            }
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                print("Connection \(clientId) failed: \(error)")
                Task { @MainActor in
                    self?.connections.removeValue(forKey: clientId)
                    self?.connectedClients.removeAll { $0 == clientId }
                }
            case .ready:
                Task { @MainActor in
                    self?.receiveData(connection: connection, clientId: clientId)
                }
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func receiveData(connection: NWConnection, clientId: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                Task { @MainActor in
                    self?.handleRequest(data: data, connection: connection, clientId: clientId)
                }
            }
            
            if let error = error {
                print("Receive error: \(error)")
            }
            
            if !isComplete {
                Task { @MainActor in
                    self?.receiveData(connection: connection, clientId: clientId)
                }
            }
        }
    }
    
    private func handleRequest(data: Data, connection: NWConnection, clientId: String) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            return
        }
        
        print("Received request: \(requestString)")
        
        Task {
            let response = await processRequest(requestString)
            self.sendResponse(response: response, connection: connection)
        }
    }
    
    private func processRequest(_ request: String) async -> String {
        let components = request.components(separatedBy: " ")
        guard components.count >= 2 else {
            return "HTTP/1.1 400 Bad Request\r\n\r\n"
        }
        
        let method = components[0]
        let path = components[1]
        
        switch (method, path) {
        case ("GET", "/api/sessions"):
            return listSessions()
        case ("POST", let p) where p.hasPrefix("/api/sessions"):
            return createSession()
        case ("GET", let p) where p.hasPrefix("/api/sessions/"):
            let id = String(p.dropFirst("/api/sessions/".count))
            return getSession(id: id)
        case ("POST", let p) where p.hasPrefix("/api/sessions/") && p.contains("/fork"):
            let id = String(p.dropFirst("/api/sessions/".count)).components(separatedBy: "/fork")[0]
            return forkSession(id: id)
        case ("POST", let p) where p.hasPrefix("/api/sessions/") && p.contains("/revert"):
            let id = String(p.dropFirst("/api/sessions/".count)).components(separatedBy: "/revert")[0]
            return revertSession(id: id)
        case ("POST", let p) where p.hasPrefix("/api/sessions/") && p.contains("/compact"):
            let id = String(p.dropFirst("/api/sessions/".count)).components(separatedBy: "/compact")[0]
            await compactSession(id: id)
            return "HTTP/1.1 200 OK\r\n\r\n"
        case ("DELETE", let p) where p.hasPrefix("/api/sessions/"):
            let id = String(p.dropFirst("/api/sessions/".count))
            deleteSession(id: id)
            return "HTTP/1.1 200 OK\r\n\r\n"
        case ("GET", "/api/events"):
            return "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n"
        default:
            return "HTTP/1.1 404 Not Found\r\n\r\n"
        }
    }
    
    private func sendResponse(response: String, connection: NWConnection) {
        guard let data = response.data(using: .utf8) else {
            return
        }
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
        })
    }
    
    private func listSessions() -> String {
        let sessions = AXSessionManager.shared.sessions
        guard let data = try? JSONEncoder().encode(sessions),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "HTTP/1.1 500 Internal Server Error\r\n\r\n"
        }
        
        return """
        HTTP/1.1 200 OK
        Content-Type: application/json
        Content-Length: \(jsonString.count)

        \(jsonString)
        """
    }
    
    private func createSession() -> String {
        let session = AXSessionManager.shared.createSession(
            projectId: "default",
            title: "New Session"
        )
        
        guard let data = try? JSONEncoder().encode(session),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "HTTP/1.1 500 Internal Server Error\r\n\r\n"
        }
        
        return """
        HTTP/1.1 200 OK
        Content-Type: application/json
        Content-Length: \(jsonString.count)

        \(jsonString)
        """
    }
    
    private func getSession(id: String) -> String {
        guard let session = AXSessionManager.shared.sessions.first(where: { $0.id == id }),
              let data = try? JSONEncoder().encode(session),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "HTTP/1.1 404 Not Found\r\n\r\n"
        }
        
        return """
        HTTP/1.1 200 OK
        Content-Type: application/json
        Content-Length: \(jsonString.count)

        \(jsonString)
        """
    }
    
    private func forkSession(id: String) -> String {
        guard let newSession = AXSessionManager.shared.forkSession(id),
              let data = try? JSONEncoder().encode(newSession),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "HTTP/1.1 404 Not Found\r\n\r\n"
        }
        
        return """
        HTTP/1.1 200 OK
        Content-Type: application/json
        Content-Length: \(jsonString.count)

        \(jsonString)
        """
    }
    
    private func revertSession(id: String) -> String {
        let success = AXSessionManager.shared.revertSession(id, to: "0")
        
        return success ? "HTTP/1.1 200 OK\r\n\r\n" : "HTTP/1.1 404 Not Found\r\n\r\n"
    }
    
    private func compactSession(id: String) async {
        await AXSessionManager.shared.compactSession(id)
    }
    
    private func deleteSession(id: String) {
        AXSessionManager.shared.deleteSession(id)
    }
}
