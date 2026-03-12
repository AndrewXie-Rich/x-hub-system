import Foundation

actor HubRemoteMemorySnapshotCache {
    struct Key: Hashable, Sendable {
        var mode: String
        var projectId: String?

        init(mode: String, projectId: String?) {
            let trimmedMode = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.mode = trimmedMode.isEmpty ? "project" : trimmedMode

            let trimmedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedProjectId, !trimmedProjectId.isEmpty {
                self.projectId = trimmedProjectId
            } else {
                self.projectId = nil
            }
        }
    }

    private struct Entry: Sendable {
        var snapshot: HubRemoteMemorySnapshotResult
        var expiresAt: Date
    }

    private let ttlSeconds: TimeInterval
    private var entries: [Key: Entry] = [:]

    init(ttlSeconds: Double = 15.0) {
        self.ttlSeconds = max(1.0, ttlSeconds)
    }

    func snapshot(for key: Key, now: Date = Date()) -> HubRemoteMemorySnapshotResult? {
        purgeExpiredEntries(now: now)
        guard let entry = entries[key], entry.expiresAt > now else {
            entries[key] = nil
            return nil
        }
        guard entry.snapshot.ok else {
            entries[key] = nil
            return nil
        }
        return entry.snapshot
    }

    func store(_ snapshot: HubRemoteMemorySnapshotResult, for key: Key, now: Date = Date()) {
        purgeExpiredEntries(now: now)
        guard snapshot.ok else {
            entries[key] = nil
            return
        }
        entries[key] = Entry(snapshot: snapshot, expiresAt: now.addingTimeInterval(ttlSeconds))
    }

    func invalidate(projectId: String?) {
        let trimmedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedProjectId, !trimmedProjectId.isEmpty else {
            entries.removeAll(keepingCapacity: true)
            return
        }
        entries = entries.filter { $0.key.projectId != trimmedProjectId }
    }

    func invalidate(key: Key) {
        entries[key] = nil
    }

    private func purgeExpiredEntries(now: Date) {
        entries = entries.filter { $0.value.expiresAt > now }
    }
}
