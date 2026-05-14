import Foundation

final class ProviderKeySelectionSnapshotStore: @unchecked Sendable {
    static let shared = ProviderKeySelectionSnapshotStore()

    private let lock = NSLock()
    private var decisionByProvider: [String: ProviderKeySelectionDecision] = [:]
    private var decisionByModelLookup: [String: ProviderKeySelectionDecision] = [:]

    private init() {}

    func record(decision: ProviderKeySelectionDecision, modelId: String) {
        lock.lock()
        defer { lock.unlock() }

        let provider = decision.requestedProvider
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !provider.isEmpty {
            decisionByProvider[provider] = decision
        }
        for lookupKey in ProviderKeySelectionSupport.modelLookupKeys(modelId) {
            decisionByModelLookup[lookupKey] = decision
        }
    }

    func decision(forProvider provider: String) -> ProviderKeySelectionDecision? {
        lock.lock()
        defer { lock.unlock() }

        let normalizedProvider = provider
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedProvider.isEmpty else { return nil }
        return decisionByProvider[normalizedProvider]
    }

    func decision(forModelId modelId: String) -> ProviderKeySelectionDecision? {
        lock.lock()
        defer { lock.unlock() }

        for lookupKey in ProviderKeySelectionSupport.modelLookupKeys(modelId) {
            if let decision = decisionByModelLookup[lookupKey] {
                return decision
            }
        }
        let provider = ProviderKeySelectionSupport.inferProvider(fromModelId: modelId)
        guard !provider.isEmpty else { return nil }
        return decisionByProvider[provider]
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        decisionByProvider = [:]
        decisionByModelLookup = [:]
    }
}
