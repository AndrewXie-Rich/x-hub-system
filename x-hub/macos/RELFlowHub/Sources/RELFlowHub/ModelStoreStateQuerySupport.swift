import Foundation

extension ModelStore {
    func pendingAction(for modelId: String) -> String? {
        pendingByModelId[modelId]?.action
    }

    func lastError(for modelId: String) -> String? {
        guard let r = lastResultByModelId[modelId] else { return nil }
        if r.ok { return nil }
        return r.msg
    }
}
