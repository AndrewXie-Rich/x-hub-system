import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
var modelResourcePools: [ModelResourcePoolSummary] {
        [localModelResourcePool()] + providerModelResourcePools()
    }

    func localModelResourcePool() -> ModelResourcePoolSummary {
        let models = localCatalogModels.sorted { lhs, rhs in
            if lhs.state != rhs.state {
                return lhs.state == .loaded
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        let modelNames = modelResourcePoolPreviewModels(
            models.map { model in
                let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? model.id : name
            }
        )
        let loadedCount = loadedLocalModelCount
        let statusText: String
        let tint: Color
        if localCatalogModelCount == 0 {
            statusText = "未导入"
            tint = .secondary
        } else if loadedCount > 0 {
            statusText = "Ready"
            tint = .green
        } else if localAvailableModelCount > 0 {
            statusText = "可按需加载"
            tint = .teal
        } else if !runtimeReadyForUI {
            statusText = "Runtime 待恢复"
            tint = .orange
        } else {
            statusText = "待预检"
            tint = .indigo
        }

        return ModelResourcePoolSummary(
            id: "local",
            kind: .local,
            vendorKey: "local",
            title: "Local",
            subtitle: "本地模型池，不消耗付费账号额度，适合摘要、离线任务和低风险默认路由。",
            statusText: statusText,
            badgeText: localCatalogModelCount == 0 ? "未配置" : "\(loadedCount)/\(localCatalogModelCount) loaded",
            systemName: "desktopcomputer",
            tint: tint,
            accountText: runtimeHeartbeatText,
            quotaText: "免付费额度",
            modelText: localCatalogModelCount == 0 ? "未导入" : "\(localCatalogModelCount) 个模型",
            detailText: localCatalogModelCount == 0
                ? "先发现或添加本地模型，Hub 会把可用任务类型、上下文和运行时状态编进资源池。"
                : "\(localAvailableModelCount) 个预检可用 · \(localPendingModelCount) 个待复核 · \(loadedRuntimeInstanceCount) 个驻留实例",
            models: modelNames.visible,
            hiddenModelCount: modelNames.hidden,
            usageWindows: []
        )
    }

    func providerModelResourcePools() -> [ModelResourcePoolSummary] {
        let pools = providerKeyDerivedSnapshot.keyPools
        let groupedPools = Dictionary(grouping: pools) { pool in
            modelResourcePoolVendorKey(
                supplierKey: pool.supplierKey,
                provider: pool.provider
            )
        }
        let supplierKeyByAccountKey = Dictionary(
            uniqueKeysWithValues: pools.flatMap { pool in
                pool.members.map { member in
                    (member.account.accountKey, pool.supplierKey)
                }
            }
        )
        let groupedAccounts = Dictionary(grouping: providerKeySnapshot.allAccounts) { account in
            modelResourceAccountVendorKey(account, supplierKeyByAccountKey: supplierKeyByAccountKey)
        }
        let groupedRemoteModels = Dictionary(grouping: remoteModels) { model in
            modelResourceRemoteVendorKey(model)
        }
        let vendorKeys = Set(groupedPools.keys)
            .union(groupedAccounts.keys)
            .union(groupedRemoteModels.keys)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 != "local" }

        return vendorKeys
            .sorted(by: modelResourcePoolVendorSort(_:_:))
            .map { vendorKey in
                providerModelResourcePool(
                    vendorKey: vendorKey,
                    pools: groupedPools[vendorKey] ?? [],
                    accounts: groupedAccounts[vendorKey] ?? [],
                    remoteModels: groupedRemoteModels[vendorKey] ?? []
                )
            }
    }

    func providerModelResourcePool(
        vendorKey: String,
        pools: [ProviderKeyPoolSnapshot],
        accounts: [ProviderKeyAccount],
        remoteModels: [RemoteModelEntry]
    ) -> ModelResourcePoolSummary {
        let title = modelResourcePoolDisplayName(vendorKey: vendorKey, pools: pools)
        let totalAccounts = max(accounts.count, pools.reduce(0) { $0 + $1.totalAccounts })
        let readyAccounts = pools.isEmpty
            ? accounts.filter { $0.enabled && $0.errorState.status == "healthy" }.count
            : pools.reduce(0) { $0 + $1.readyAccounts }
        let cooldownAccounts = pools.reduce(0) { $0 + $1.cooldownAccounts }
        let blockedAccounts = pools.reduce(0) { $0 + $1.blockedAccounts }
        let disabledAccounts = pools.reduce(0) { $0 + $1.disabledAccounts }
        let usageWindows = modelResourcePoolUsageWindows(accounts: accounts)
        let allModelNames = modelResourceProviderModelNames(
            vendorKey: vendorKey,
            pools: pools,
            accounts: accounts,
            remoteModels: remoteModels
        )
        let preview = modelResourcePoolPreviewModels(allModelNames)
        let totalDailyCap = pools.reduce(Int64(0)) { $0 + $1.totalDailyTokenCap }
        let totalDailyRemaining = pools.reduce(Int64(0)) { $0 + $1.totalDailyTokensRemaining }

        let statusText: String
        let tint: Color
        if readyAccounts > 0 {
            statusText = "Ready"
            tint = (blockedAccounts > 0 || cooldownAccounts > 0) ? .orange : .green
        } else if blockedAccounts > 0 {
            statusText = "阻断"
            tint = .red
        } else if cooldownAccounts > 0 {
            statusText = "冷却"
            tint = .orange
        } else if totalAccounts == 0 && !remoteModels.isEmpty {
            statusText = "待接账号"
            tint = .orange
        } else if totalAccounts == 0 {
            statusText = "未配置"
            tint = .secondary
        } else if disabledAccounts >= totalAccounts {
            statusText = "已禁用"
            tint = .secondary
        } else {
            statusText = "待恢复"
            tint = .orange
        }

        let quotaText: String = {
            if let firstWindow = usageWindows.first {
                return "\(providerKeyUsageWindowPercentText(firstWindow)) 已用"
            }
            if totalDailyCap > 0 {
                return "剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(totalDailyRemaining))"
            }
            return totalAccounts > 0 ? "等待刷新" : "无账号"
        }()

        let detailParts = modelResourceNonEmptyParts([
            totalAccounts > 0 ? "\(readyAccounts)/\(totalAccounts) 个账号可用" : "",
            cooldownAccounts > 0 ? "\(cooldownAccounts) 个冷却" : "",
            blockedAccounts > 0 ? "\(blockedAccounts) 个阻断" : "",
            remoteModels.isEmpty ? "" : "\(remoteModels.count) 个远端模型已编目",
            totalDailyCap > 0 ? "daily 剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(totalDailyRemaining))" : ""
        ])

        return ModelResourcePoolSummary(
            id: "provider::\(vendorKey)",
            kind: .provider,
            vendorKey: vendorKey,
            title: title,
            subtitle: "厂商账号池，统一承载账号额度、可执行模型和默认路由候选。",
            statusText: statusText,
            badgeText: totalAccounts > 0 ? "\(readyAccounts)/\(totalAccounts) ready" : "未接账号",
            systemName: modelResourcePoolSystemName(vendorKey),
            tint: tint,
            accountText: totalAccounts > 0 ? "\(readyAccounts)/\(totalAccounts) 可用" : "未配置",
            quotaText: quotaText,
            modelText: allModelNames.isEmpty ? "未编目" : "\(allModelNames.count) 个模型",
            detailText: detailParts.isEmpty ? "先导入账号或添加远端模型，Hub 才能把这个厂商编入资源池。" : detailParts.joined(separator: " · "),
            models: preview.visible,
            hiddenModelCount: preview.hidden,
            usageWindows: usageWindows
        )
    }
}
