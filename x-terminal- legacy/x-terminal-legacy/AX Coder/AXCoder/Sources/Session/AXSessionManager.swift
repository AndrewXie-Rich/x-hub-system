import Foundation
import Combine

@MainActor
final class AXSessionManager: ObservableObject {
    static let shared = AXSessionManager()
    
    @Published var sessions: [AXSessionInfo] = []
    @Published var activeSessionId: String?
    
    private let eventBus = AXEventBus.shared
    private var cancellables = Set<AnyCancellable>()
    private let sessionsStoreKey = "xterminal_sessions"
    private let legacySessionsStoreKey = "axcoder_sessions"
    
    private init() {
        loadSessions()
        setupEventListeners()
    }
    
    private func setupEventListeners() {
        eventBus.eventPublisher
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)
    }
    
    private func handleEvent(_ event: AXEvent) {
        switch event {
        case .sessionCreated(let info):
            if !sessions.contains(where: { $0.id == info.id }) {
                sessions.append(info)
                saveSessions()
            }
        case .sessionUpdated(let info):
            if let index = sessions.firstIndex(where: { $0.id == info.id }) {
                sessions[index] = info
                saveSessions()
            }
        case .sessionDeleted(let id):
            sessions.removeAll { $0.id == id }
            saveSessions()
        default:
            break
        }
    }
    
    func createSession(
        projectId: String,
        title: String? = nil,
        parentId: String? = nil
    ) -> AXSessionInfo {
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970
        let session = AXSessionInfo(
            id: id,
            projectId: projectId,
            title: title ?? "New Session",
            directory: "",
            parentId: parentId,
            createdAt: now,
            updatedAt: now,
            version: "1.0",
            summary: nil
        )
        
        saveSession(session)
        eventBus.publish(.sessionCreated(session))
        return session
    }
    
    func forkSession(_ sessionId: String, messageId: String? = nil) -> AXSessionInfo? {
        guard let original = sessions.first(where: { $0.id == sessionId }) else {
            return nil
        }
        
        let newTitle = getForkedTitle(original.title)
        let newSession = createSession(
            projectId: original.projectId,
            title: newTitle,
            parentId: original.id
        )
        
        copyMessages(from: sessionId, to: newSession.id, until: messageId)
        
        return newSession
    }
    
    private func getForkedTitle(_ title: String) -> String {
        let pattern = #"^(.+) \(fork #(\d+)\)$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: title.utf16.count)
        
        if let match = regex?.firstMatch(in: title, range: range),
           let baseRange = Range(match.range(at: 1), in: title),
           let numRange = Range(match.range(at: 2), in: title),
           let num = Int(title[numRange]) {
            let base = String(title[baseRange])
            return "\(base) (fork #\(num + 1))"
        }
        
        return "\(title) (fork #1)"
    }
    
    func revertSession(
        _ sessionId: String,
        to messageId: String,
        partId: String? = nil
    ) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            return false
        }
        
        var session = sessions[index]
        
        deleteMessagesAfter(sessionId: sessionId, messageId: messageId)
        
        session.updatedAt = Date().timeIntervalSince1970
        sessions[index] = session
        saveSession(session)
        eventBus.publish(.sessionUpdated(session))
        
        return true
    }
    
    func compactSession(_ sessionId: String) async {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            return
        }
        
        var session = sessions[index]
        
        session.updatedAt = Date().timeIntervalSince1970
        sessions[index] = session
        eventBus.publish(.sessionUpdated(session))
        
        await performCompaction(sessionId: sessionId)
        
        let summary = generateSessionSummary(sessionId: sessionId)
        session.summary = summary
        session.updatedAt = Date().timeIntervalSince1970
        sessions[index] = session
        saveSession(session)
        eventBus.publish(.sessionUpdated(session))
    }
    
    private func performCompaction(sessionId: String) async {
    }
    
    private func generateSessionSummary(sessionId: String) -> AXSessionSummary {
        return AXSessionSummary(
            additions: 0,
            deletions: 0,
            files: 0,
            diffs: []
        )
    }
    
    func deleteSession(_ sessionId: String) {
        guard sessions.contains(where: { $0.id == sessionId }) else {
            return
        }
        
        deleteSessionData(sessionId: sessionId)
        
        sessions.removeAll { $0.id == sessionId }
        eventBus.publish(.sessionDeleted(sessionId))
    }
    
    func updateSession(_ session: AXSessionInfo) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else {
            return
        }
        
        sessions[index] = session
        saveSession(session)
        eventBus.publish(.sessionUpdated(session))
    }
    
    private func loadSessions() {
        let defaults = UserDefaults.standard
        let data = defaults.data(forKey: sessionsStoreKey) ?? defaults.data(forKey: legacySessionsStoreKey)
        guard let data,
              let decoded = try? JSONDecoder().decode([AXSessionInfo].self, from: data) else {
            return
        }
        sessions = decoded
        defaults.set(data, forKey: sessionsStoreKey)
    }
    
    private func saveSessions() {
        guard let encoded = try? JSONEncoder().encode(sessions) else {
            return
        }
        UserDefaults.standard.set(encoded, forKey: sessionsStoreKey)
        UserDefaults.standard.set(encoded, forKey: legacySessionsStoreKey)
    }
    
    private func saveSession(_ session: AXSessionInfo) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        saveSessions()
    }
    
    private func copyMessages(from: String, to: String, until: String?) {
    }
    
    private func deleteMessagesAfter(sessionId: String, messageId: String) {
    }
    
    private func deleteSessionData(sessionId: String) {
    }
}
