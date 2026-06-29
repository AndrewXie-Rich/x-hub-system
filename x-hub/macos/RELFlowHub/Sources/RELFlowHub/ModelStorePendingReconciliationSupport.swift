import Foundation

extension ModelStore {
    func reconcilePendingWithState() {
        if pendingByModelId.isEmpty { return }
        var toRemove: [String] = []
        for (mid, p) in pendingByModelId {
            guard let m = snapshot.models.first(where: { $0.id == mid }) else {
                // Model removed.
                toRemove.append(mid)
                continue
            }
            let st = m.state
            switch p.action {
            case "load":
                if st == .loaded { toRemove.append(mid) }
            case "warmup":
                if st == .loaded { toRemove.append(mid) }
            case "unload":
                if st == .available { toRemove.append(mid) }
            case "sleep":
                if st == .sleeping { toRemove.append(mid) }
            default:
                break
            }
        }
        for mid in toRemove {
            pendingByModelId.removeValue(forKey: mid)
        }
    }
}
