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

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        let dir = ClientStorage.dir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            clients = []
            return
        }
        let decoder = JSONDecoder()
        var out: [HubClientHeartbeat] = []
        let now = Date().timeIntervalSince1970
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

            out.append(obj)
        }
        out.sort { $0.appName < $1.appName }
        clients = out
    }

    func liveClients(now: Double = Date().timeIntervalSince1970) -> [HubClientHeartbeat] {
        clients.filter { ageSeconds($0, now: now) < presenceTTL }
    }

    func activeCount(now: Double = Date().timeIntervalSince1970) -> Int {
        liveClients(now: now).count
    }

    private func ageSeconds(_ hb: HubClientHeartbeat, now: Double) -> Double {
        // If a client writes an invalid/future timestamp, don't let it appear connected forever.
        if hb.updatedAt > now + 2.0 {
            return Double.greatestFiniteMagnitude
        }
        return max(0.0, now - hb.updatedAt)
    }
}
