import Foundation
import RELFlowHubCore

typealias RoutingSettings = LocalTaskRoutingSettings

enum RoutingSettingsStorage {
    static let fileName = "routing_settings.json"

    static func url() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    static func load() -> RoutingSettings {
        let u = url()
        guard let data = try? Data(contentsOf: u) else {
            return RoutingSettings()
        }
        if let obj = try? JSONDecoder().decode(RoutingSettings.self, from: data) {
            return obj
        }
        // Back-compat: allow dict-only format.
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var out = RoutingSettings()
            if let m = dict["preferredModelIdByTask"] as? [String: Any] {
                var mm: [String: String] = [:]
                for (k, v) in m {
                    let kk = String(k).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let vv = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !kk.isEmpty {
                        mm[kk] = vv
                    }
                }
                out.preferredModelIdByTask = mm
            } else if let m = dict["preferred_model_id_by_task"] as? [String: Any] {
                var mm: [String: String] = [:]
                for (k, v) in m {
                    let kk = String(k).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let vv = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !kk.isEmpty, !vv.isEmpty {
                        mm[kk] = vv
                    }
                }
                out.preferredModelIdByTask = mm
            }
            return out
        }
        return RoutingSettings()
    }

    static func save(_ st: RoutingSettings) {
        var cur = st
        cur.updatedAt = Date().timeIntervalSince1970
        let u = url()
        do {
            let data = try JSONEncoder().encode(cur)
            try data.write(to: u, options: .atomic)
        } catch {
            // Best-effort.
        }
    }
}
