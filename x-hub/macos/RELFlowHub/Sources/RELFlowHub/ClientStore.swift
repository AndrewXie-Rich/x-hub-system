import Foundation
import SwiftUI
import RELFlowHubCore

@MainActor
final class ClientStore: ObservableObject {
    static let shared = ClientStore()

    @Published private(set) var clients: [HubClientHeartbeat] = []

    // If a client doesn't refresh its heartbeat within this window, it's considered disconnected.
    // This makes satellites disappear shortly after an app quits.
    private let presenceTTL: Double = 12.0

    // Best-effort cleanup: delete very old heartbeat files so the directory doesn't accumulate.
    private let pruneTTL: Double = 180.0

    private var timer: Timer?
    private let refreshQueue = DispatchQueue(label: "xhub.client-store.refresh", qos: .utility)
    private var refreshInFlight: Bool = false

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true

        let pruneTTL = self.pruneTTL
        refreshQueue.async { [weak self] in
            let snapshot = Self.loadClients(pruneTTL: pruneTTL)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.clients = snapshot
                self.refreshInFlight = false
            }
        }
    }

    func liveClients(now: Double = Date().timeIntervalSince1970) -> [HubClientHeartbeat] {
        clients.filter { Self.ageSeconds($0, now: now) < presenceTTL }
    }

    func activeCount(now: Double = Date().timeIntervalSince1970) -> Int {
        liveClients(now: now).count
    }

    nonisolated private static func loadClients(pruneTTL: Double) -> [HubClientHeartbeat] {
        let decoder = JSONDecoder()
        let now = Date().timeIntervalSince1970
        var latestByAppID: [String: HubClientHeartbeat] = [:]

        for dir in ClientStorage.readDirectoryCandidates() {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                continue
            }

            for url in files {
                if url.pathExtension.lowercased() != "json" { continue }
                guard let data = try? Data(contentsOf: url),
                      let obj = try? decoder.decode(HubClientHeartbeat.self, from: data) else {
                    continue
                }

                let age = ageSeconds(obj, now: now)
                if age > pruneTTL {
                    // Stale file from a long-gone app; remove it so it doesn't look "connected" forever.
                    try? FileManager.default.removeItem(at: url)
                    continue
                }

                let key = obj.appId.trimmingCharacters(in: .whitespacesAndNewlines)
                if let existing = latestByAppID[key], existing.updatedAt >= obj.updatedAt {
                    continue
                }
                latestByAppID[key] = obj
            }
        }

        return latestByAppID.values.sorted {
            let lhsName = $0.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            let rhsName = $1.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            let ordered = lhsName.localizedCaseInsensitiveCompare(rhsName)
            if ordered != .orderedSame {
                return ordered == .orderedAscending
            }
            return $0.appId.localizedCaseInsensitiveCompare($1.appId) == .orderedAscending
        }
    }

    nonisolated private static func ageSeconds(_ hb: HubClientHeartbeat, now: Double) -> Double {
        // If a client writes an invalid/future timestamp, don't let it appear connected forever.
        if hb.updatedAt > now + 2.0 {
            return Double.greatestFiniteMagnitude
        }
        return max(0.0, now - hb.updatedAt)
    }
}
