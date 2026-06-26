import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    var modelResourcePoolsSection: some View {
        let pools = modelResourcePools
        Section("资源池总览") {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        modelResourcePoolsHeadline(pools)
                        Spacer(minLength: 12)
                        modelResourcePoolsHeaderControls(pools)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        modelResourcePoolsHeadline(pools)
                        modelResourcePoolsHeaderControls(pools)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(pools) { pool in
                        modelResourcePoolCard(pool)
                    }
                }

                Text("第一屏只回答“哪个池子能用、还剩多少、能跑哪些模型”。账号、消费者、物理 key 和配额链路放在下面的高级配额运营里。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modelResourcePoolsHeadline(_ pools: [ModelResourcePoolSummary]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("可用模型资源池")
                .font(.headline)
            Text(modelResourcePoolsSummaryText(pools))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modelResourcePoolsHeaderControls(_ pools: [ModelResourcePoolSummary]) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(modelResourcePoolsBadgeText(pools))
                .font(.caption.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(modelResourcePoolsTint(pools).opacity(0.12))
                .foregroundStyle(modelResourcePoolsTint(pools))
                .clipShape(Capsule())

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    localModelEntryActions()
                }

                VStack(alignment: .trailing, spacing: 8) {
                    localModelEntryActions()
                }
            }
        }
    }

    @ViewBuilder
    private func localModelEntryActions() -> some View {
        Button {
            showDiscoverModels = true
        } label: {
            settingsActionChipLabel(title: "发现本地模型", systemName: "magnifyingglass", tint: .indigo)
        }
        .buttonStyle(.plain)

        Button {
            showAddModel = true
        } label: {
            settingsActionChipLabel(title: "添加本地模型", systemName: "plus", tint: .green)
        }
        .buttonStyle(.plain)
    }

    private func modelResourcePoolCard(_ pool: ModelResourcePoolSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(pool.tint.opacity(0.14))
                    Image(systemName: pool.systemName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(pool.tint)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(pool.title)
                            .font(.headline)
                        Text(pool.statusText)
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(pool.tint.opacity(0.12))
                            .foregroundStyle(pool.tint)
                            .clipShape(Capsule())
                    }
                    Text(pool.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(pool.badgeText)
                    .font(.caption.monospaced())
                    .foregroundStyle(pool.tint)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118), spacing: 8, alignment: .top)],
                alignment: .leading,
                spacing: 8
            ) {
                modelResourcePoolMetric(title: "账号", value: pool.accountText, tint: pool.tint)
                modelResourcePoolMetric(title: "额度", value: pool.quotaText, tint: modelResourcePoolQuotaTint(pool))
                modelResourcePoolMetric(title: "模型", value: pool.modelText, tint: .indigo)
            }

            if !pool.usageWindows.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(pool.usageWindows.enumerated()), id: \.offset) { _, window in
                        modelResourcePoolQuotaRow(window)
                    }
                }
            }

            modelResourcePoolModelChips(pool)

            Text(pool.detailText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .opacity(0.35)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    modelResourcePoolActions(pool)
                }
                VStack(alignment: .leading, spacing: 8) {
                    modelResourcePoolActions(pool)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pool.tint.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(pool.tint.opacity(0.20), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func modelResourcePoolMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func modelResourcePoolQuotaRow(_ window: ProviderKeyUsageWindow) -> some View {
        let tint = providerKeyUsageWindowTint(window)
        let percent = providerKeyUsageWindowPercent(window)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(providerKeyUsageWindowTitle(window))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(providerKeyUsageWindowPercentText(window))
                    .font(.caption2.monospaced())
                    .foregroundStyle(tint)
            }
            ProgressView(value: min(1.0, max(0.0, percent / 100.0)))
                .tint(tint)
            let resetText = providerKeyUsageWindowResetText(window)
            if !resetText.isEmpty {
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func modelResourcePoolModelChips(_ pool: ModelResourcePoolSummary) -> some View {
        if pool.models.isEmpty {
            Text("还没有编入可展示模型")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 6, alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(pool.models, id: \.self) { model in
                    Text(model)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(pool.tint.opacity(0.10))
                        .foregroundStyle(pool.tint)
                        .clipShape(Capsule())
                }
                if pool.hiddenModelCount > 0 {
                    Text("+\(pool.hiddenModelCount)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.10))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func modelResourcePoolActions(_ pool: ModelResourcePoolSummary) -> some View {
        if pool.kind == .local {
            Button {
                modelCatalogDetailsExpanded = true
                store.scanAllLocalModelHealth()
            } label: {
                settingsActionChipLabel(
                    title: store.localModelHealthScanInFlight ? "扫描中" : "扫描健康",
                    systemName: "waveform.path.ecg",
                    tint: .teal,
                    disabled: store.localModelHealthScanInFlight || localCatalogModels.isEmpty
                )
            }
            .buttonStyle(.plain)
            .disabled(store.localModelHealthScanInFlight || localCatalogModels.isEmpty)
        } else {
            Button {
                reloadProviderKeySnapshot(rebuildProjection: providerQuotaOperationsExpanded)
            } label: {
                settingsActionChipLabel(title: "刷新额度", systemName: "arrow.clockwise", tint: .blue)
            }
            .buttonStyle(.plain)

            Button {
                showAddRemoteModel = true
            } label: {
                settingsActionChipLabel(title: "添加模型", systemName: "plus", tint: .indigo)
            }
            .buttonStyle(.plain)

            Button {
                focusProviderKeyVendor(pool.vendorKey, displayName: pool.title)
            } label: {
                settingsActionChipLabel(title: "管理账号", systemName: "person.badge.key", tint: .orange)
            }
            .buttonStyle(.plain)
        }
    }

    var modelResourcePools: [ModelResourcePoolSummary] {
        [localModelResourcePool()] + providerModelResourcePools()
    }

    private func localModelResourcePool() -> ModelResourcePoolSummary {
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
        } else if runtimeHeartbeatText != "在线" {
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

    private func providerModelResourcePools() -> [ModelResourcePoolSummary] {
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

    private func providerModelResourcePool(
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

    func modelResourcePoolsSummaryText(_ pools: [ModelResourcePoolSummary]) -> String {
        let readyCount = pools.filter { $0.statusText == "Ready" || $0.statusText == "可按需加载" }.count
        let attentionCount = pools.filter { pool in
            pool.statusText == "阻断" || pool.statusText == "冷却" || pool.statusText == "Runtime 待恢复" || pool.statusText == "待接账号"
        }.count
        return "\(pools.count) 个资源池 · \(readyCount) 个可用 · \(attentionCount) 个需要关注"
    }

    func modelResourcePoolsBadgeText(_ pools: [ModelResourcePoolSummary]) -> String {
        let readyCount = pools.filter { $0.statusText == "Ready" || $0.statusText == "可按需加载" }.count
        return "\(readyCount)/\(pools.count) 可用"
    }

    func modelResourcePoolsTint(_ pools: [ModelResourcePoolSummary]) -> Color {
        if pools.contains(where: { $0.statusText == "阻断" }) {
            return .red
        }
        if pools.contains(where: { $0.statusText == "冷却" || $0.statusText == "Runtime 待恢复" || $0.statusText == "待接账号" }) {
            return .orange
        }
        return .green
    }

    func modelResourcePoolQuotaTint(_ pool: ModelResourcePoolSummary) -> Color {
        if let window = pool.usageWindows.first {
            return providerKeyUsageWindowTint(window)
        }
        return pool.tint
    }

    private func modelResourcePoolUsageWindows(accounts: [ProviderKeyAccount]) -> [ProviderKeyUsageWindow] {
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

    private func modelResourceWindowIsMoreConstrained(
        _ lhs: ProviderKeyUsageWindow,
        than rhs: ProviderKeyUsageWindow
    ) -> Bool {
        if lhs.limited != rhs.limited {
            return lhs.limited
        }
        return providerKeyUsageWindowPercent(lhs) > providerKeyUsageWindowPercent(rhs)
    }

    private func modelResourceProviderModelNames(
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

    private func modelResourcePoolPreviewModels(_ rawModels: [String]) -> (visible: [String], hidden: Int) {
        let models = modelResourceUniqueStrings(rawModels)
            .map(modelResourceCompactModelName(_:))
        let visible = Array(models.prefix(6))
        return (visible, max(0, models.count - visible.count))
    }

    private func modelResourcePoolVendorKey(supplierKey: String, provider: String) -> String {
        let supplier = supplierKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !supplier.isEmpty {
            return providerKeyCanonicalVendorKey(supplier)
        }
        return providerKeyCanonicalVendorKey(provider)
    }

    private func modelResourceAccountVendorKey(
        _ account: ProviderKeyAccount,
        supplierKeyByAccountKey: [String: String]
    ) -> String {
        let supplierKey = supplierKeyByAccountKey[account.accountKey] ?? account.provider
        return modelResourcePoolVendorKey(supplierKey: supplierKey, provider: account.provider)
    }

    private func modelResourceRemoteVendorKey(_ model: RemoteModelEntry) -> String {
        providerKeyCanonicalVendorKey(RemoteProviderEndpoints.canonicalBackend(model.backend))
    }

    private func modelResourceAccountModelNames(
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

    private func modelResourceVendorUsesStrictModelFamilies(_ vendorKey: String) -> Bool {
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

    private func modelResourceModelVendorKey(_ rawModelID: String) -> String {
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

    private func modelResourcePoolDisplayName(
        vendorKey: String,
        pools: [ProviderKeyPoolSnapshot]
    ) -> String {
        let display = pools
            .map(\.supplierDisplayName)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return display ?? providerKeyVendorDisplayName(vendorKey)
    }

    private func modelResourcePoolSystemName(_ vendorKey: String) -> String {
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

    private func modelResourcePoolVendorSort(_ lhs: String, _ rhs: String) -> Bool {
        let order = ["openai", "claude", "gemini", "kimi"]
        let lhsIndex = order.firstIndex(of: providerKeyCanonicalVendorKey(lhs)) ?? Int.max
        let rhsIndex = order.firstIndex(of: providerKeyCanonicalVendorKey(rhs)) ?? Int.max
        if lhsIndex != rhsIndex {
            return lhsIndex < rhsIndex
        }
        return providerKeyVendorDisplayName(lhs).localizedCaseInsensitiveCompare(providerKeyVendorDisplayName(rhs)) == .orderedAscending
    }

    private func modelResourceCompactModelName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 26 else { return trimmed }
        return String(trimmed.prefix(24)) + "..."
    }

    private func modelResourceUniqueStrings(_ values: [String]) -> [String] {
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

    private func modelResourceNonEmptyParts(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

}
