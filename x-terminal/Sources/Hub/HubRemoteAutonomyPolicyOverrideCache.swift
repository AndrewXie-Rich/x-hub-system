import Foundation

actor HubRemoteAutonomyPolicyOverrideCache {
    struct Key: Hashable, Sendable {
        var projectId: String?
        var limit: Int

        init(projectId: String?, limit: Int) {
            let trimmedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedProjectId, !trimmedProjectId.isEmpty {
                self.projectId = trimmedProjectId
            } else {
                self.projectId = nil
            }
            self.limit = max(1, min(500, limit))
        }
    }

    private struct Entry: Sendable {
        var snapshot: HubIPCClient.AutonomyPolicyOverridesSnapshot
        var expiresAt: Date
    }

    private let ttlSeconds: TimeInterval
    private var entries: [Key: Entry] = [:]

    init(ttlSeconds: Double = 3.0) {
        self.ttlSeconds = max(1.0, ttlSeconds)
    }

    func snapshot(for key: Key, now: Date = Date()) -> HubIPCClient.AutonomyPolicyOverridesSnapshot? {
        purgeExpiredEntries(now: now)
        guard let entry = entries[key], entry.expiresAt > now else {
            entries[key] = nil
            return nil
        }
        return entry.snapshot
    }

    func store(_ snapshot: HubIPCClient.AutonomyPolicyOverridesSnapshot, for key: Key, now: Date = Date()) {
        purgeExpiredEntries(now: now)
        entries[key] = Entry(snapshot: snapshot, expiresAt: now.addingTimeInterval(ttlSeconds))
    }

    func invalidate(projectId: String?) {
        let keyProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyProjectId == nil || keyProjectId?.isEmpty == true {
            entries.removeAll(keepingCapacity: true)
            return
        }
        entries = entries.filter { $0.key.projectId != keyProjectId }
    }

    func invalidate(key: Key) {
        entries[key] = nil
    }

    private func purgeExpiredEntries(now: Date) {
        entries = entries.filter { $0.value.expiresAt > now }
    }
}
