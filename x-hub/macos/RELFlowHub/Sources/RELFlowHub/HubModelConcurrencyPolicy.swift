import Foundation
import RELFlowHubCore

struct HubModelConcurrencyProviderPolicy: Codable, Equatable {
    var concurrencyLimit: Int?
    var taskLimits: [String: Int]

    init(concurrencyLimit: Int? = nil, taskLimits: [String: Int] = [:]) {
        self.concurrencyLimit = concurrencyLimit.flatMap { Self.normalizedLimit($0) }
        self.taskLimits = Self.normalizedTaskLimits(taskLimits)
    }

    func normalized() -> HubModelConcurrencyProviderPolicy {
        HubModelConcurrencyProviderPolicy(
            concurrencyLimit: concurrencyLimit.flatMap { Self.normalizedLimit($0) },
            taskLimits: Self.normalizedTaskLimits(taskLimits)
        )
    }

    private static func normalizedLimit(_ value: Int) -> Int? {
        guard value > 0 else { return nil }
        return min(64, max(1, value))
    }

    private static func normalizedTaskLimits(_ values: [String: Int]) -> [String: Int] {
        values.reduce(into: [:]) { partial, item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, item.value > 0 else { return }
            partial[key] = min(64, max(1, item.value))
        }
    }
}

struct HubModelConcurrencyPolicySnapshot: Codable, Equatable {
    static let schemaVersion = "xhub.model_concurrency_policy.v1"

    var schemaVersion: String
    var localDefaultConcurrencyLimit: Int
    var paidModelGlobalConcurrencyLimit: Int
    var paidModelPerProjectConcurrencyLimit: Int
    var paidModelQueueLimit: Int
    var paidModelQueueTimeoutMs: Int
    var providerPolicies: [String: HubModelConcurrencyProviderPolicy]
    var updatedAtMs: Int64

    init(
        schemaVersion: String = Self.schemaVersion,
        localDefaultConcurrencyLimit: Int = 1,
        paidModelGlobalConcurrencyLimit: Int = 6,
        paidModelPerProjectConcurrencyLimit: Int = 2,
        paidModelQueueLimit: Int = 128,
        paidModelQueueTimeoutMs: Int = 20_000,
        providerPolicies: [String: HubModelConcurrencyProviderPolicy] = [:],
        updatedAtMs: Int64 = HubModelConcurrencyPolicySnapshot.nowMs()
    ) {
        self.schemaVersion = schemaVersion
        self.localDefaultConcurrencyLimit = localDefaultConcurrencyLimit
        self.paidModelGlobalConcurrencyLimit = paidModelGlobalConcurrencyLimit
        self.paidModelPerProjectConcurrencyLimit = paidModelPerProjectConcurrencyLimit
        self.paidModelQueueLimit = paidModelQueueLimit
        self.paidModelQueueTimeoutMs = paidModelQueueTimeoutMs
        self.providerPolicies = providerPolicies
        self.updatedAtMs = updatedAtMs
    }

    static func `default`() -> HubModelConcurrencyPolicySnapshot {
        HubModelConcurrencyPolicySnapshot()
    }

    func normalized(updatingTimestamp: Bool = false) -> HubModelConcurrencyPolicySnapshot {
        var normalizedProviders: [String: HubModelConcurrencyProviderPolicy] = [:]
        for (provider, policy) in providerPolicies {
            let key = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            normalizedProviders[key] = policy.normalized()
        }
        return HubModelConcurrencyPolicySnapshot(
            schemaVersion: Self.schemaVersion,
            localDefaultConcurrencyLimit: min(64, max(1, localDefaultConcurrencyLimit)),
            paidModelGlobalConcurrencyLimit: min(64, max(1, paidModelGlobalConcurrencyLimit)),
            paidModelPerProjectConcurrencyLimit: min(16, max(1, paidModelPerProjectConcurrencyLimit)),
            paidModelQueueLimit: min(4096, max(1, paidModelQueueLimit)),
            paidModelQueueTimeoutMs: min(300_000, max(1_000, paidModelQueueTimeoutMs)),
            providerPolicies: normalizedProviders,
            updatedAtMs: updatingTimestamp ? Self.nowMs() : max(0, updatedAtMs)
        )
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

enum HubModelConcurrencyPolicyStorage {
    static let fileName = "model_concurrency_policy.json"

    static func url(baseDir: URL = SharedPaths.ensureHubDirectory()) -> URL {
        baseDir.appendingPathComponent(fileName)
    }

    static func load(baseDir: URL = SharedPaths.ensureHubDirectory()) -> HubModelConcurrencyPolicySnapshot {
        let target = url(baseDir: baseDir)
        guard let data = try? Data(contentsOf: target),
              let decoded = try? JSONDecoder().decode(HubModelConcurrencyPolicySnapshot.self, from: data) else {
            return .default()
        }
        return decoded.normalized()
    }

    static func save(
        _ snapshot: HubModelConcurrencyPolicySnapshot,
        baseDir: URL = SharedPaths.ensureHubDirectory()
    ) {
        let normalized = snapshot.normalized(updatingTimestamp: true)
        let target = url(baseDir: baseDir)
        do {
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(normalized)
            try data.write(to: target, options: .atomic)
        } catch {
            HubDiagnostics.log("model_concurrency_policy.save_failed path=\(target.path) error=\(error.localizedDescription)")
        }
    }
}
