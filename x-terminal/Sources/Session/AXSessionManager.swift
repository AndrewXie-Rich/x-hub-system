import Combine
import Foundation

@MainActor
final class AXSessionManager: ObservableObject {
    static let shared = AXSessionManager()

    @Published var sessions: [AXSessionInfo] = []
    @Published var activeSessionId: String?

    private let eventBus = AXEventBus.shared
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private let sessionsStoreKey = "xterminal_sessions"
    private let legacySessionsStoreKey = "xterminal_sessions"

    init(userDefaults: UserDefaults = .standard, observeEvents: Bool = true) {
        self.userDefaults = userDefaults
        loadSessions()
        if observeEvents {
            setupEventListeners()
        }
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
                sessions.append(backfilledSession(info))
                saveSessions()
            }
        case .sessionUpdated(let info):
            if let index = sessions.firstIndex(where: { $0.id == info.id }) {
                sessions[index] = backfilledSession(info)
                saveSessions()
            }
        case .sessionDeleted(let id):
            sessions.removeAll { $0.id == id }
            if activeSessionId == id {
                activeSessionId = nil
            }
            saveSessions()
        default:
            break
        }
    }

    func session(for sessionId: String) -> AXSessionInfo? {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            return nil
        }
        return refreshedSession(at: index)
    }

    func primarySession(for projectId: String) -> AXSessionInfo? {
        let matchingIndices = sessions.indices.filter { sessions[$0].projectId == projectId }
        return matchingIndices
            .map { refreshedSession(at: $0) }
            .sorted { lhs, rhs in
                let lhsRank = lhs.parentId == nil ? 0 : 1
                let rhsRank = rhs.parentId == nil ? 0 : 1
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id < rhs.id
            }
            .first
    }

    @discardableResult
    func ensurePrimarySession(
        projectId: String,
        title: String,
        directory: String
    ) -> AXSessionInfo {
        if var existing = primarySession(for: projectId) {
            let normalizedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
            var changed = false

            if shouldBackfillTitle(existing.title) {
                let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedTitle.isEmpty && existing.title != trimmedTitle {
                    existing.title = trimmedTitle
                    changed = true
                }
            }

            if !normalizedDirectory.isEmpty && existing.directory != normalizedDirectory {
                existing.directory = normalizedDirectory
                changed = true
            }

            let backfilled = backfilledSession(existing)
            if backfilled != existing {
                existing = backfilled
                changed = true
            }

            activeSessionId = existing.id
            if changed {
                updateSession(existing)
            }
            return session(for: existing.id) ?? existing
        }

        let created = createSession(projectId: projectId, title: title, directory: directory)
        activeSessionId = created.id
        return created
    }

    func createSession(
        projectId: String,
        title: String? = nil,
        directory: String = "",
        parentId: String? = nil
    ) -> AXSessionInfo {
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = AXSessionInfo(
            id: id,
            projectId: projectId,
            title: (trimmedTitle?.isEmpty == false) ? trimmedTitle! : "New Session",
            directory: directory.trimmingCharacters(in: .whitespacesAndNewlines),
            parentId: parentId,
            createdAt: now,
            updatedAt: now,
            version: "1.0",
            summary: nil,
            runtime: .idle(at: now)
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
            directory: original.directory,
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
        sessions[index] = backfilledSession(session)
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
        sessions[index] = backfilledSession(session)
        eventBus.publish(.sessionUpdated(session))

        await performCompaction(sessionId: sessionId)

        let summary = generateSessionSummary(sessionId: sessionId)
        session.summary = summary
        session.updatedAt = Date().timeIntervalSince1970
        sessions[index] = backfilledSession(session)
        saveSession(session)
        eventBus.publish(.sessionUpdated(session))
    }

    @discardableResult
    func updateRuntime(
        sessionId: String,
        at timestamp: Double = Date().timeIntervalSince1970,
        _ mutate: (inout AXSessionRuntimeSnapshot) -> Void
    ) -> AXSessionInfo? {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            return nil
        }

        var session = backfilledSession(sessions[index])
        var runtime = session.runtime ?? .idle(at: timestamp)
        runtime = runtime.normalized(at: timestamp)
        mutate(&runtime)
        runtime.schemaVersion = AXSessionRuntimeSnapshot.currentSchemaVersion
        runtime.updatedAt = max(runtime.updatedAt, timestamp)
        runtime.pendingToolCallCount = max(0, runtime.pendingToolCallCount)
        session.runtime = runtime
        session.updatedAt = max(session.updatedAt, runtime.updatedAt)
        sessions[index] = session
        saveSessions()
        eventBus.publish(.sessionUpdated(session))
        return session
    }

    private func performCompaction(sessionId: String) async {
    }

    private func generateSessionSummary(sessionId: String) -> AXSessionSummary {
        AXSessionSummary(
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
        if activeSessionId == sessionId {
            activeSessionId = nil
        }
        eventBus.publish(.sessionDeleted(sessionId))
    }

    func updateSession(_ session: AXSessionInfo) {
        guard sessions.contains(where: { $0.id == session.id }) else {
            return
        }

        let normalized = backfilledSession(session)
        saveSession(normalized)
        eventBus.publish(.sessionUpdated(normalized))
    }

    private func loadSessions() {
        let data = userDefaults.data(forKey: sessionsStoreKey) ?? userDefaults.data(forKey: legacySessionsStoreKey)
        guard let data,
              let decoded = try? JSONDecoder().decode([AXSessionInfo].self, from: data) else {
            return
        }

        let normalized = decoded.map(backfilledPersistedSession)
        sessions = normalized
        if normalized != decoded {
            saveSessions()
        } else {
            userDefaults.set(data, forKey: sessionsStoreKey)
            userDefaults.set(data, forKey: legacySessionsStoreKey)
        }
    }

    private func saveSessions() {
        guard let encoded = try? JSONEncoder().encode(sessions) else {
            return
        }
        userDefaults.set(encoded, forKey: sessionsStoreKey)
        userDefaults.set(encoded, forKey: legacySessionsStoreKey)
    }

    private func saveSession(_ session: AXSessionInfo) {
        let normalized = backfilledSession(session)
        if let index = sessions.firstIndex(where: { $0.id == normalized.id }) {
            sessions[index] = normalized
        } else {
            sessions.append(normalized)
        }
        saveSessions()
    }

    private func backfilledSession(_ session: AXSessionInfo) -> AXSessionInfo {
        var normalized = session
        let runtime = (session.runtime ?? .idle(at: session.updatedAt))
            .normalized(at: session.updatedAt)
            .stabilized()
        normalized.runtime = runtime
        normalized.updatedAt = max(session.updatedAt, runtime.updatedAt)
        return normalized
    }

    private func backfilledPersistedSession(_ session: AXSessionInfo) -> AXSessionInfo {
        var normalized = session
        let runtime = (session.runtime ?? .idle(at: session.updatedAt))
            .restoredFromPersistence()
        normalized.runtime = runtime
        normalized.updatedAt = max(session.updatedAt, runtime.updatedAt)
        return normalized
    }

    private func refreshedSession(at index: Int) -> AXSessionInfo {
        let existing = sessions[index]
        let normalized = backfilledSession(existing)
        if normalized != existing {
            sessions[index] = normalized
            saveSessions()
            eventBus.publish(.sessionUpdated(normalized))
        }
        return normalized
    }

    private func shouldBackfillTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "New Session"
    }

    private func copyMessages(from: String, to: String, until: String?) {
    }

    private func deleteMessagesAfter(sessionId: String, messageId: String) {
    }

    private func deleteSessionData(sessionId: String) {
    }
}
