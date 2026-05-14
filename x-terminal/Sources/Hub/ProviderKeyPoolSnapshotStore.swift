import Foundation

final class ProviderKeyPoolSnapshotStore: @unchecked Sendable {
    static let shared = ProviderKeyPoolSnapshotStore()

    private let lock = NSLock()
    private var poolByProvider: [String: HubProviderKeysClient.ProviderPool] = [:]
    private var poolByModelLookup: [String: HubProviderKeysClient.ProviderPool] = [:]

    private init() {}

    func record(pool: HubProviderKeysClient.ProviderPool, modelId: String) {
        lock.lock()
        defer { lock.unlock() }

        let provider = pool.provider
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !provider.isEmpty {
            poolByProvider[provider] = pool
        }
        for lookupKey in ProviderKeySelectionSupport.modelLookupKeys(modelId) {
            poolByModelLookup[lookupKey] = pool
        }
    }

    func pool(forProvider provider: String) -> HubProviderKeysClient.ProviderPool? {
        lock.lock()
        defer { lock.unlock() }

        let normalizedProvider = provider
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedProvider.isEmpty else { return nil }
        return poolByProvider[normalizedProvider]
    }

    func pool(forModelId modelId: String) -> HubProviderKeysClient.ProviderPool? {
        lock.lock()
        defer { lock.unlock() }

        for lookupKey in ProviderKeySelectionSupport.modelLookupKeys(modelId) {
            if let pool = poolByModelLookup[lookupKey] {
                return pool
            }
        }
        let provider = ProviderKeySelectionSupport.inferProvider(fromModelId: modelId)
        guard !provider.isEmpty else { return nil }
        return poolByProvider[provider]
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        poolByProvider = [:]
        poolByModelLookup = [:]
    }
}
