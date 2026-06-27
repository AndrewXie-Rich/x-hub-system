import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func modelResourcePoolUsageWindows(accounts: [ProviderKeyAccount]) -> [ProviderKeyUsageWindow] {
        var selected: [Int: ProviderKeyUsageWindow] = [:]
        for account in accounts where account.enabled {
            for window in providerKeyDisplayUsageWindows(account) {
                let rank = providerKeyUsageWindowRank(window)
                if let existing = selected[rank] {
                    if modelResourceWindowIsMoreConstrained(window, than: existing) {
                        selected[rank] = window
                    }
                } else {
                    selected[rank] = window
                }
            }
        }
        return selected.values.sorted {
            let lhsRank = providerKeyUsageWindowRank($0)
            let rhsRank = providerKeyUsageWindowRank($1)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return $0.limitWindowSeconds < $1.limitWindowSeconds
        }
    }

    func modelResourceWindowIsMoreConstrained(
        _ lhs: ProviderKeyUsageWindow,
        than rhs: ProviderKeyUsageWindow
    ) -> Bool {
        if lhs.limited != rhs.limited {
            return lhs.limited
        }
        return providerKeyUsageWindowPercent(lhs) > providerKeyUsageWindowPercent(rhs)
    }

    func modelResourceProviderModelNames(
        vendorKey: String,
        pools: [ProviderKeyPoolSnapshot],
        accounts: [ProviderKeyAccount],
        remoteModels: [RemoteModelEntry]
    ) -> [String] {
        modelResourceUniqueStrings(
            remoteModels.map(\.nestedDisplayName)
                + modelResourceAccountModelNames(vendorKey: vendorKey, accounts: accounts)
                + pools.flatMap(\.supportedFamilyDisplayNames)
        )
    }

    func modelResourcePoolPreviewModels(_ rawModels: [String]) -> (visible: [String], hidden: Int) {
        let models = modelResourceUniqueStrings(rawModels)
            .map(modelResourceCompactModelName(_:))
        let visible = Array(models.prefix(6))
        return (visible, max(0, models.count - visible.count))
    }

    func modelResourcePoolVendorKey(supplierKey: String, provider: String) -> String {
        let supplier = supplierKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !supplier.isEmpty {
            return providerKeyCanonicalVendorKey(supplier)
        }
        return providerKeyCanonicalVendorKey(provider)
    }

    func modelResourceAccountVendorKey(
        _ account: ProviderKeyAccount,
        supplierKeyByAccountKey: [String: String]
    ) -> String {
        let supplierKey = supplierKeyByAccountKey[account.accountKey] ?? account.provider
        return modelResourcePoolVendorKey(supplierKey: supplierKey, provider: account.provider)
    }

    func modelResourceRemoteVendorKey(_ model: RemoteModelEntry) -> String {
        providerKeyCanonicalVendorKey(RemoteProviderEndpoints.canonicalBackend(model.backend))
    }

    func modelResourceAccountModelNames(
        vendorKey: String,
        accounts: [ProviderKeyAccount]
    ) -> [String] {
        let canonicalVendor = providerKeyCanonicalVendorKey(vendorKey)
        let shouldFilter = modelResourceVendorUsesStrictModelFamilies(canonicalVendor)

        return accounts.flatMap { account in
            account.models.filter { modelID in
                guard shouldFilter else { return true }
                let modelVendor = modelResourceModelVendorKey(modelID)
                guard !modelVendor.isEmpty else { return true }
                return providerKeyCanonicalVendorKey(modelVendor) == canonicalVendor
            }
        }
    }

    func modelResourceVendorUsesStrictModelFamilies(_ vendorKey: String) -> Bool {
        switch providerKeyCanonicalVendorKey(vendorKey) {
        case "openai",
             "claude",
             "gemini",
             "deepseek",
             "qwen",
             "glm",
             "kimi",
             "mistral",
             "xai":
            return true
        default:
            return false
        }
    }

    func modelResourceModelVendorKey(_ rawModelID: String) -> String {
        let normalized = rawModelID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return "" }
        let modelID = normalized
            .split(separator: "/")
            .last
            .map(String.init) ?? normalized

        if modelID.hasPrefix("gpt")
            || modelID.hasPrefix("o1")
            || modelID.hasPrefix("o3")
            || modelID.hasPrefix("o4")
            || modelID.hasPrefix("chatgpt") {
            return "openai"
        }
        if modelID.hasPrefix("claude") {
            return "claude"
        }
        if modelID.hasPrefix("gemini") {
            return "gemini"
        }
        if modelID.hasPrefix("deepseek") {
            return "deepseek"
        }
        if modelID.hasPrefix("qwen")
            || modelID.hasPrefix("qwq")
            || modelID.hasPrefix("qvq")
            || modelID.hasPrefix("tongyi") {
            return "qwen"
        }
        if modelID.hasPrefix("glm") || modelID.hasPrefix("zhipu") {
            return "glm"
        }
        if modelID.hasPrefix("kimi") || modelID.hasPrefix("moonshot") {
            return "kimi"
        }
        if modelID.hasPrefix("mistral") {
            return "mistral"
        }
        if modelID.hasPrefix("grok") || modelID.hasPrefix("xai") {
            return "xai"
        }
        return ""
    }

    func modelResourcePoolDisplayName(
        vendorKey: String,
        pools: [ProviderKeyPoolSnapshot]
    ) -> String {
        let display = pools
            .map(\.supplierDisplayName)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return display ?? providerKeyVendorDisplayName(vendorKey)
    }

    func modelResourcePoolSystemName(_ vendorKey: String) -> String {
        switch providerKeyCanonicalVendorKey(vendorKey) {
        case "openai":
            return "sparkles"
        case "claude":
            return "text.bubble.fill"
        case "gemini":
            return "diamond.fill"
        default:
            return "cloud.fill"
        }
    }

    func modelResourcePoolVendorSort(_ lhs: String, _ rhs: String) -> Bool {
        let order = ["openai", "claude", "gemini", "kimi"]
        let lhsIndex = order.firstIndex(of: providerKeyCanonicalVendorKey(lhs)) ?? Int.max
        let rhsIndex = order.firstIndex(of: providerKeyCanonicalVendorKey(rhs)) ?? Int.max
        if lhsIndex != rhsIndex {
            return lhsIndex < rhsIndex
        }
        return providerKeyVendorDisplayName(lhs).localizedCaseInsensitiveCompare(providerKeyVendorDisplayName(rhs)) == .orderedAscending
    }

    func modelResourceCompactModelName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 26 else { return trimmed }
        return String(trimmed.prefix(24)) + "..."
    }

    func modelResourceUniqueStrings(_ values: [String]) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for raw in values {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.lowercased()
            guard !trimmed.isEmpty, seen.insert(normalized).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }

    func modelResourceNonEmptyParts(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
