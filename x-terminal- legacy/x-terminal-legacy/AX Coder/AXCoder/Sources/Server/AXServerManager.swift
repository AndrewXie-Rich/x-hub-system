import Foundation
import Network

@MainActor
final class AXServerManager: ObservableObject {
    static let shared = AXServerManager()
    
    @Published var isRunning: Bool = false
    @Published var port: Int = 8080
    @Published var connectedClients: [String] = []
    
    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]
    private let eventBus = AXEventBus.shared
    
    private init() {}
    
    func startServer() async throws {
        guard !isRunning else { return }
        
        let config = NWParameters.tcp
        config.allowLocalEndpointReuse = true
        config.allowFastOpen = true
        
        listener = try NWListener(using: config, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
        
        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }
        
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in
                    self?.isRunning = true
                    print("X-Terminal Server started on port \(self?.port ?? 8080)")
                }
            case .failed(let error):
                Task { @MainActor in
                    self?.isRunning = false
                    print("Server failed: \(error)")
                }
            default:
                break
            }
        }
        
        listener?.start(queue: .main)
    }
    
    func stopServer() {
        guard isRunning else { return }
        
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        
        isRunning = false
        connectedClients.removeAll()
        
        print("X-Terminal Server stopped")
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
