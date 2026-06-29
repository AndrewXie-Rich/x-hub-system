import SwiftUI
import AppKit
import RELFlowHubCore

struct ModelsDrawer: View {
    @EnvironmentObject var store: HubStore
    @ObservedObject var modelStore = ModelStore.shared
    @State var remoteModels: [RemoteModelEntry] = []
    @State private var providerKeySnapshot: ModelsDrawerProviderKeySnapshot = .empty
    @State private var localModelSnapshot: ModelsDrawerLocalModelSnapshot = .empty
    @State private var remoteDrawerGroupSnapshot: [RemoteDrawerGroup] = []
    @State private var showDiscoverModels: Bool = false
    @State private var showAddModel: Bool = false
    @State private var showAddRemoteModel: Bool = false
    @State var routeAllowAutoLoad: Bool = true
    @State var routeCheckFeedback: String = ""
    @State var routeCheckModelId: String = ""
    @State var routeCheckTaskId: String = ""
    @State private var libraryFilter: ModelsDrawerLibraryFilter = .all
    @State private var librarySearch: String = ""
    @State private var modelLibraryExpanded: Bool = false
    @State private var resourcePoolSnapshot: [ModelsDrawerResourcePoolSummary] = []
    @State private var libraryItemSnapshot: [ModelsDrawerLibraryItem] = []
    @State private var filteredLibraryItemSnapshot: [ModelsDrawerLibraryItem] = []
    @State private var routeMatrixRowSnapshot: [ModelsDrawerRouteMatrixRow] = []
    @State private var routeControlRowSnapshot: [ModelsDrawerTaskRouteControlSnapshot] = []
    @State private var roleRouteSummarySnapshot: [ModelsDrawerRoleRouteSummary] = []
    @State private var importSourceRemovalTarget: ModelsDrawerImportSourceRemovalTarget? = nil
    @State private var importSourceActionText: String = ""
    @State private var importSourceErrorText: String = ""
    @State private var remoteModelRemovalTarget: ModelsDrawerRemoteModelRemovalTarget? = nil
    @State private var remoteModelActionText: String = ""
    @State private var remoteModelErrorText: String = ""
    @State private var remoteModelsReloadTask: Task<Void, Never>? = nil
    @State private var providerKeyReloadTask: Task<Void, Never>? = nil

    var localModels: [HubModel] {
        localModelSnapshot.models
    }

    private var remoteGroups: [RemoteDrawerGroup] {
        remoteDrawerGroupSnapshot
    }

    var quotaPools: [ProviderQuotaPoolSnapshot] {
        providerKeySnapshot.quotaPools
    }

    var localLoadedCount: Int {
        localModelSnapshot.loadedCount
    }

    private var remoteLoadedCount: Int {
        remoteGroups.reduce(0) { $0 + $1.loadedCount }
    }

    private var remoteAvailableCount: Int {
        remoteGroups.reduce(0) { $0 + $1.availableCount }
    }

    private var remoteNeedsSetupCount: Int {
        remoteGroups.reduce(0) { $0 + $1.needsSetupCount }
    }

    var runtimeAlive: Bool {
        store.aiRuntimeStatusSnapshot?.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false
    }

    private var runtimeReadyProviderCount: Int {
        if let monitor = store.aiRuntimeStatusSnapshot?.monitorSnapshot {
            return monitor.providers.filter(\.ok).count
        }
        return store.aiRuntimeStatusSnapshot?.providers.values.filter(\.ok).count ?? 0
    }

    private var runtimeTotalProviderCount: Int {
        if let monitor = store.aiRuntimeStatusSnapshot?.monitorSnapshot {
            return monitor.providers.count
        }
        return store.aiRuntimeStatusSnapshot?.providers.count ?? 0
    }

    private var runtimeLoadedInstanceCount: Int {
        store.aiRuntimeStatusSnapshot?.monitorSnapshot?.loadedInstances.count ?? 0
    }

    var body: some View {
        drawerWithLifecycle
    }

    private var drawerBase: some View {
        let pools = self.resourcePoolSnapshot
        let libraryItems = self.filteredLibraryItemSnapshot

        return VStack(alignment: .leading, spacing: 0) {
            self.drawerHeader

            Divider()
                .opacity(0.35)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    self.portfolioOverviewPanel(pools: pools)

                    self.resourcePoolsSection(pools)

                    self.taskRouteMatrixSection

                    self.localRuntimeAndModelsSection

                    self.modelLibrarySection(libraryItems)

                    self.remoteModelSourcesSection

                    self.importSourceCleanupSection
                }
                .padding(14)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 2)
        .padding(10)
    }

    private var drawerWithSheets: some View {
        drawerBase
        .sheet(isPresented: $showDiscoverModels) {
            DiscoverModelsSheet()
        }
        .sheet(isPresented: $showAddModel) {
            AddModelSheet()
        }
        .sheet(isPresented: $showAddRemoteModel) {
            AddRemoteModelSheet { entries in
                for entry in entries {
                    _ = RemoteModelStorage.upsert(entry)
                }
                reloadRemoteModels()
                ModelStore.shared.refresh()
            }
        }
    }

    private var drawerWithRemovalAlerts: some View {
        drawerWithSheets
        .alert(
            self.importSourceRemovalTitle(importSourceRemovalTarget),
            isPresented: Binding(
                get: { importSourceRemovalTarget != nil },
                set: { newValue in
                    if !newValue {
                        importSourceRemovalTarget = nil
                    }
                }
            ),
            presenting: importSourceRemovalTarget
        ) { target in
            Button(self.importSourceRemovalConfirmTitle(target), role: .destructive) {
                self.removeImportSource(target)
            }
            Button("取消", role: .cancel) {
                importSourceRemovalTarget = nil
            }
        } message: { target in
            Text(self.importSourceRemovalMessage(target))
        }
        .alert(
            self.remoteModelRemovalTitle(remoteModelRemovalTarget),
            isPresented: Binding(
                get: { remoteModelRemovalTarget != nil },
                set: { newValue in
                    if !newValue {
                        remoteModelRemovalTarget = nil
                    }
                }
            ),
            presenting: remoteModelRemovalTarget
        ) { target in
            Button(self.remoteModelRemovalConfirmTitle(target), role: .destructive) {
                self.removeRemoteModels(target)
            }
            Button("取消", role: .cancel) {
                remoteModelRemovalTarget = nil
            }
        } message: { target in
            Text(self.remoteModelRemovalMessage(target))
        }
    }

    private var drawerWithLifecycle: some View {
        drawerWithRemovalAlerts
        .onAppear {
            refreshLocalModelSnapshot()
            reloadRemoteModels(initial: true)
            reloadProviderKeySnapshot()
        }
        .onDisappear {
            remoteModelsReloadTask?.cancel()
            remoteModelsReloadTask = nil
            providerKeyReloadTask?.cancel()
            providerKeyReloadTask = nil
        }
        .onChange(of: modelStore.snapshot.updatedAt) { _ in
            refreshLocalModelSnapshot()
            reloadRemoteModels()
        }
        .onChange(of: store.aiRuntimeStatusSnapshot?.updatedAt ?? 0) { _ in
            rebuildDrawerDerivedSnapshots()
        }
        .onChange(of: store.routingPreferredModelIdByTask) { _ in
            rebuildDrawerDerivedSnapshots()
        }
        .onChange(of: libraryFilter) { _ in
            rebuildFilteredLibrarySnapshot()
        }
        .onChange(of: librarySearch) { _ in
            rebuildFilteredLibrarySnapshot()
        }
        .onChange(of: store.remoteKeyHealthSnapshot.updatedAt) { _ in
            refreshRemoteDrawerGroups()
        }
        .onReceive(Timer.publish(every: 30.0, on: .main, in: .common).autoconnect()) { _ in
            reloadProviderKeySnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: .relflowhubRemoteModelsChanged)) { _ in
            reloadRemoteModels()
        }
        .onReceive(NotificationCenter.default.publisher(for: .relflowhubRemoteKeyHealthChanged)) { _ in
            refreshRemoteDrawerGroups()
            reloadProviderKeySnapshot()
        }
    }

    private var drawerHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("模型控制中心")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                HStack(spacing: 7) {
                    drawerStatusPill(
                        "\(localModels.count + remoteModels.count) 模型",
                        systemName: "square.stack.3d.up",
                        tint: .indigo
                    )
                    drawerStatusPill(
                        providerKeySnapshot.readyAccounts > 0 ? "\(providerKeySnapshot.readyAccounts) Key 可用" : "Key 未配置",
                        systemName: "key.horizontal",
                        tint: providerKeySnapshot.readyAccounts > 0 ? .green : .secondary
                    )
                    drawerStatusPill(
                        runtimeAlive ? "运行时在线" : "运行时待恢复",
                        systemName: runtimeAlive ? "bolt.fill" : "bolt.slash",
                        tint: runtimeAlive ? .green : .orange
                    )
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                drawerIconOnlyButton("刷新", systemName: "arrow.clockwise") {
                    modelStore.refresh()
                    reloadRemoteModels()
                    reloadProviderKeySnapshot()
                }

                drawerIconOnlyButton("设置", systemName: "gearshape") {
                    HubSettingsWindowPresenter.shared.show(store: store)
                }

                drawerIconOnlyButton("关闭", systemName: "xmark") {
                    store.showModelsDrawer = false
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var resourcePoolSummaries: [ModelsDrawerResourcePoolSummary] {
        var pools: [ModelsDrawerResourcePoolSummary] = [localResourcePoolSummary]
        pools.append(contentsOf: remoteResourcePoolSummaries)
        return pools
    }

    private var localResourcePoolSummary: ModelsDrawerResourcePoolSummary {
        let statusText: String
        let statusColor: Color
        if localModels.isEmpty {
            statusText = "未导入"
            statusColor = .secondary
        } else if runtimeAlive && localLoadedCount > 0 {
            statusText = "运行中"
            statusColor = .green
        } else if runtimeAlive {
            statusText = "可用"
            statusColor = .indigo
        } else {
            statusText = "待恢复"
            statusColor = .orange
        }

        let topModels = Array(localModels.map(\.name).prefix(4))
        let subtitle = [
            "\(localModels.count) 个本地模型",
            runtimeTotalProviderCount > 0 ? "\(runtimeReadyProviderCount)/\(runtimeTotalProviderCount) 运行时" : "等待运行时",
            runtimeLoadedInstanceCount > 0 ? "\(runtimeLoadedInstanceCount) 常驻实例" : ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")

        return ModelsDrawerResourcePoolSummary(
            id: "local",
            title: "本地",
            subtitle: subtitle.isEmpty ? "本地模型资源池" : subtitle,
            statusText: statusText,
            statusColor: statusColor,
            systemName: "internaldrive.fill",
            modelText: localModels.isEmpty ? "0" : "\(localLoadedCount)/\(localModels.count)",
            accountText: runtimeTotalProviderCount == 0 ? "0" : "\(runtimeReadyProviderCount)/\(runtimeTotalProviderCount)",
            quotaText: "本机",
            models: topModels,
            usageWindows: [],
            detailText: localResourcePoolDetailText,
            isLocal: true
        )
    }

    private var remoteResourcePoolSummaries: [ModelsDrawerResourcePoolSummary] {
        let modelsByProvider = Dictionary(grouping: remoteModels) {
            RemoteModelPresentationSupport.backendLabel(for: $0)
        }
        let poolsByProvider = Dictionary(grouping: providerKeySnapshot.keyPools) {
            providerPoolDisplayName($0)
        }
        let providerNames = Array(Set(modelsByProvider.keys).union(poolsByProvider.keys))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        return providerNames.map { providerName in
            let models = modelsByProvider[providerName] ?? []
            let keyPools = poolsByProvider[providerName] ?? []
            let states = models.map(RemoteModelPresentationSupport.state(for:))
            let loaded = states.filter { $0 == .loaded }.count
            let available = states.filter { $0 == .available }.count
            let needsSetup = states.filter { $0 == .needsSetup }.count
            let readyAccounts = keyPools.reduce(0) { $0 + $1.readyAccounts }
            let totalAccounts = keyPools.reduce(0) { $0 + $1.totalAccounts }
            let blockedAccounts = keyPools.reduce(0) { $0 + $1.blockedAccounts + $1.cooldownAccounts }
            let usageWindows = providerDisplayUsageWindows(for: keyPools)

            let statusText: String
            let statusColor: Color
            if loaded > 0 || (available > 0 && readyAccounts > 0) {
                statusText = loaded > 0 ? "可用" : "待加载"
                statusColor = loaded > 0 ? .green : .indigo
            } else if needsSetup > 0 || blockedAccounts > 0 {
                statusText = "需处理"
                statusColor = .orange
            } else if totalAccounts > 0 {
                statusText = "待编目"
                statusColor = .indigo
            } else {
                statusText = "未配置"
                statusColor = .secondary
            }

            let quotaText: String = {
                if let first = usageWindows.first {
                    return providerKeyUsageWindowPercentText(first)
                }
                let cap = keyPools.reduce(Int64(0)) { $0 + max(Int64(0), $1.totalDailyTokenCap) }
                let used = keyPools.reduce(Int64(0)) { $0 + max(Int64(0), $1.totalDailyTokensUsed) }
                guard cap > 0 else { return keyPools.contains(where: \.hasQuotaData) ? "已同步" : "未知" }
                return String(format: "%.0f%%", min(100.0, max(0.0, Double(used) / Double(cap) * 100.0)))
            }()

            let subtitleParts = [
                totalAccounts > 0 ? "\(readyAccounts)/\(totalAccounts) Key" : "",
                models.isEmpty ? "" : "\(models.count) 模型",
                loaded > 0 ? "\(loaded) 已启用" : "",
                needsSetup > 0 ? "\(needsSetup) 需配置" : ""
            ].filter { !$0.isEmpty }

            return ModelsDrawerResourcePoolSummary(
                id: "remote:\(providerName.lowercased())",
                title: providerName,
                subtitle: subtitleParts.isEmpty ? "远程模型资源池" : subtitleParts.joined(separator: " · "),
                statusText: statusText,
                statusColor: statusColor,
                systemName: "cloud.fill",
                modelText: models.isEmpty ? "0" : "\(loaded + available)/\(models.count)",
                accountText: totalAccounts == 0 ? "0" : "\(readyAccounts)/\(totalAccounts)",
                quotaText: quotaText,
                models: Array(models.map(\.nestedDisplayName).prefix(4)),
                usageWindows: usageWindows,
                detailText: remoteResourcePoolDetailText(
                    providerName: providerName,
                    keyPools: keyPools,
                    models: models,
                    needsSetup: needsSetup
                ),
                isLocal: false
            )
        }
    }

    private var routeMatrixRows: [ModelsDrawerRouteMatrixRow] {
        let models = modelStore.snapshot.models
        var rows: [ModelsDrawerRouteMatrixRow] = []

        rows.append(bestModelRouteRow(
            id: "local_private",
            title: "隐私任务",
            models: localModels.filter(\.offlineReady),
            reason: "优先本机执行，输入不离开本地"
        ))
        rows.append(bestModelRouteRow(
            id: "long_context",
            title: "长上下文",
            models: models.sorted { $0.maxContextLength > $1.maxContextLength },
            reason: "优先上下文窗口最大的可用模型"
        ))
        rows.append(bestModelRouteRow(
            id: "vision",
            title: "视觉/OCR",
            models: models.filter { modelSupportsVision($0) },
            reason: "优先支持图像或 OCR 的模型"
        ))
        rows.append(bestModelRouteRow(
            id: "fast",
            title: "快速问答",
            models: localModels.sorted { lhs, rhs in
                let lt = lhs.tokensPerSec ?? 0
                let rt = rhs.tokensPerSec ?? 0
                if lt != rt { return lt > rt }
                return lhs.paramsB < rhs.paramsB
            },
            reason: "优先低延迟和低成本"
        ))

        return rows
    }

    private var roleRouteSummaries: [ModelsDrawerRoleRouteSummary] {
        HubTaskType.allCases.map { task in
            let decision = currentRouteDecision(for: task)
            let hasRoute = !decision.modelId.isEmpty
            let statusText = hasRoute
                ? (decision.willAutoLoad ? "按需加载" : modelStateText(decision.modelState ?? .available))
                : "未路由"
            let statusColor = hasRoute
                ? (decision.willAutoLoad ? Color.indigo : modelStateColor(decision.modelState ?? .available))
                : Color.orange

            return ModelsDrawerRoleRouteSummary(
                id: task.rawValue,
                title: task.label,
                systemName: routeTaskSystemName(task),
                modelName: hasRoute ? decision.modelName : "暂无可用模型",
                statusText: statusText,
                statusColor: statusColor,
                detail: hasRoute ? routeRecommendationDetail(decision) : routeReasonText(decision.reason)
            )
        }
    }

    private var routeControlRows: [ModelsDrawerTaskRouteControlSnapshot] {
        let options = modelStore.snapshot.models.map {
            ModelsDrawerRouteModelOption(id: $0.id, title: $0.name)
        }

        return HubTaskType.allCases.map { task in
            let decision = currentRouteDecision(for: task)
            let preferredModelId = effectivePreferredModelId(for: task)
            let tint = decision.modelId.isEmpty
                ? Color.orange
                : modelStateColor(decision.modelState ?? .available)

            return ModelsDrawerTaskRouteControlSnapshot(
                id: task.rawValue,
                task: task,
                decision: decision,
                preferredModelId: preferredModelId,
                tint: tint,
                systemName: routeTaskSystemName(task),
                purposeText: routeTaskPurposeText(task),
                detailText: routeRecommendationDetail(decision),
                stateText: modelStateText(decision.modelState ?? .available),
                preferenceLabel: routePreferenceShortLabel(for: task),
                availableModels: options
            )
        }
    }

    private var libraryItems: [ModelsDrawerLibraryItem] {
        let localItems = localModels.map { model in
            ModelsDrawerLibraryItem(
                id: "local:\(model.id)",
                title: model.name,
                provider: providerTitle(for: model),
                detail: compactModelDetail(model),
                statusText: modelStateText(model.state),
                statusColor: modelStateColor(model.state),
                tags: modelTags(model),
                isLocal: true,
                isReady: true,
                modelId: model.id,
                remoteEntry: nil
            )
        }
        let remoteItems = remoteModels.map { entry in
            let state = RemoteModelPresentationSupport.state(for: entry)
            return ModelsDrawerLibraryItem(
                id: "remote:\(entry.id)",
                title: entry.nestedDisplayName,
                provider: RemoteModelPresentationSupport.backendLabel(for: entry),
                detail: remoteLibraryDetail(entry),
                statusText: remoteModelStateText(state),
                statusColor: remoteModelStateColor(state),
                tags: remoteModelTags(entry),
                isLocal: false,
                isReady: state != .needsSetup,
                modelId: entry.id,
                remoteEntry: entry
            )
        }
        return (remoteItems + localItems).sorted {
            if $0.isReady != $1.isReady { return $0.isReady && !$1.isReady }
            if $0.isLocal != $1.isLocal { return !$0.isLocal && $1.isLocal }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func filteredLibraryItems(from items: [ModelsDrawerLibraryItem]) -> [ModelsDrawerLibraryItem] {
        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            switch libraryFilter {
            case .all:
                break
            case .remote:
                guard !item.isLocal else { return false }
            case .local:
                guard item.isLocal else { return false }
            case .ready:
                guard item.isReady else { return false }
            case .needsSetup:
                guard !item.isReady else { return false }
            }

            guard !query.isEmpty else { return true }
            return item.title.lowercased().contains(query)
                || item.provider.lowercased().contains(query)
                || item.detail.lowercased().contains(query)
                || item.tags.joined(separator: " ").lowercased().contains(query)
        }
    }

    private func portfolioOverviewPanel(pools: [ModelsDrawerResourcePoolSummary]) -> some View {
        let quotaSignal = portfolioQuotaSignal(pools)
        let usablePools = pools.filter { pool in
            ["可用", "运行中", "待加载"].contains(pool.statusText)
        }.count

        return ModelsDrawerPortfolioOverviewPanel(
            quotaSignalText: quotaSignal.text,
            quotaSignalTint: quotaSignal.tint,
            usablePoolCount: usablePools,
            poolCount: pools.count,
            readyAccountCount: providerKeySnapshot.readyAccounts,
            totalAccountCount: providerKeySnapshot.totalAccounts,
            runtimeLoadedInstanceCount: runtimeLoadedInstanceCount,
            roleSummaries: roleRouteSummarySnapshot
        )
    }

    @ViewBuilder
    private var importSourceCleanupSection: some View {
        let sources = sortedImportSources
        let issueCount = sources.filter(isImportSourceIssue).count
        let shouldShow = !sources.isEmpty
            || !importSourceActionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !importSourceErrorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if shouldShow {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: "来源清理",
                    subtitle: "过期 URL、缺失目录、同步失败或不再续费的账号池，可以直接从这里清掉。"
                )

                drawerPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            drawerStatusPill(
                                issueCount > 0 ? "\(issueCount) 需处理" : "来源正常",
                                systemName: issueCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                                tint: issueCount > 0 ? .orange : .green
                            )
                            drawerStatusPill(
                                "\(sources.count) 来源",
                                systemName: "tray.and.arrow.down",
                                tint: sources.isEmpty ? .secondary : .teal
                            )

                            Spacer()

                            ModelsDrawerActionChip(
                                title: "管理全部",
                                systemName: "gearshape",
                                tint: .secondary
                            ) {
                                store.openProviderKeysSettings()
                                HubSettingsWindowPresenter.shared.show(store: store)
                            }
                        }

                        if !importSourceActionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ModelsDrawerNoticeLine(
                                systemName: "checkmark.circle.fill",
                                text: importSourceActionText,
                                tint: .green
                            )
                        }

                        if !importSourceErrorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ModelsDrawerNoticeLine(
                                systemName: "exclamationmark.triangle.fill",
                                text: importSourceErrorText,
                                tint: .red
                            )
                        }

                        if sources.isEmpty {
                            emptyStateLine("没有剩余导入源。远程模型和账号池会按当前库存继续显示。")
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(sources.prefix(5).enumerated()), id: \.element.id) { index, source in
                                    if index > 0 { Divider().opacity(0.24) }
                                    importSourceCleanupRow(source)
                                        .padding(.vertical, 8)
                                }
                            }

                            if sources.count > 5 {
                                Text("还有 \(sources.count - 5) 个来源，打开设置可查看全部。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func importSourceCleanupRow(_ source: ProviderKeyImportSourceStatus) -> some View {
        let color = importSourceStateColor(source)
        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(importSourceTitle(source))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(importSourceStateText(source))
                        .font(.caption2.monospaced())
                        .foregroundStyle(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(importSourceSummary(source))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let error = importSourceErrorDescription(source) {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(color)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Menu {
                Button("只移除来源记录") {
                    requestImportSourceRemoval(source, removeOwnedAccounts: false)
                }

                Button("移除来源和账号", role: .destructive) {
                    requestImportSourceRemoval(source, removeOwnedAccounts: true)
                }
                .disabled(source.ownedAccountCount == 0)
            } label: {
                ModelsDrawerActionChipLabel(
                    title: "清理",
                    systemName: "trash",
                    tint: source.state == "ready" ? .secondary : color,
                    disabled: false
                )
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var sortedImportSources: [ProviderKeyImportSourceStatus] {
        providerKeySnapshot.importSources.sorted { lhs, rhs in
            let lhsRank = importSourceSortRank(lhs)
            let rhsRank = importSourceSortRank(rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.updatedAtMs != rhs.updatedAtMs { return lhs.updatedAtMs > rhs.updatedAtMs }
            return importSourceTitle(lhs).localizedCaseInsensitiveCompare(importSourceTitle(rhs)) == .orderedAscending
        }
    }

    private func importSourceSortRank(_ source: ProviderKeyImportSourceStatus) -> Int {
        switch source.state {
        case "sync_failed":
            return 0
        case "missing":
            return 1
        case "ready":
            return source.ownedAccountCount == 0 ? 2 : 4
        default:
            return 3
        }
    }

    private func isImportSourceIssue(_ source: ProviderKeyImportSourceStatus) -> Bool {
        source.state != "ready" || source.ownedAccountCount == 0 || source.lastErrorCount > 0
    }

    private func importSourceTitle(_ source: ProviderKeyImportSourceStatus) -> String {
        let ref = importSourceDisplayName(source)
        switch source.kind {
        case "auth_dir":
            return "Auth 目录 · \(ref)"
        case "config_path":
            return "配置文件 · \(ref)"
        case "cliproxy_oauth":
            return "CLIProxy OAuth · \(ref)"
        default:
            return "\(source.kind) · \(ref)"
        }
    }

    private func importSourceDisplayName(_ source: ProviderKeyImportSourceStatus) -> String {
        if source.kind == "cliproxy_oauth",
           let url = URL(string: source.sourceRef),
           let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty {
            if let port = url.port {
                return "\(host):\(port)"
            }
            return host
        }
        let url = URL(fileURLWithPath: source.sourceRef, isDirectory: source.kind == "auth_dir")
        let last = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return last.isEmpty ? source.sourceRef : last
    }

    private func importSourceStateText(_ source: ProviderKeyImportSourceStatus) -> String {
        switch source.state {
        case "ready":
            return source.ownedAccountCount == 0 ? "空来源" : "正常"
        case "missing":
            return "路径缺失"
        case "sync_failed":
            return "同步失败"
        default:
            return "待处理"
        }
    }

    private func importSourceStateColor(_ source: ProviderKeyImportSourceStatus) -> Color {
        switch source.state {
        case "ready":
            return source.ownedAccountCount == 0 ? .secondary : .green
        case "missing":
            return .orange
        case "sync_failed":
            return .red
        default:
            return .secondary
        }
    }

    private func importSourceSummary(_ source: ProviderKeyImportSourceStatus) -> String {
        var parts: [String] = []
        if source.lastSyncAtMs > 0 {
            parts.append("上次同步 \(formattedImportSourceTime(source.lastSyncAtMs))")
        } else {
            parts.append("还没有成功同步记录")
        }
        parts.append("账号 \(source.ownedAccountCount)")
        parts.append("导入 \(source.lastImportedCount)")
        if source.lastErrorCount > 0 {
            parts.append("错误 \(source.lastErrorCount)")
        }
        return parts.joined(separator: " · ")
    }

    private func importSourceErrorDescription(_ source: ProviderKeyImportSourceStatus) -> String? {
        guard let raw = source.lastErrors.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            if source.state == "ready", source.ownedAccountCount == 0 {
                return "这个来源当前没有持有账号，可以清理掉旧记录。"
            }
            return nil
        }
        let normalized = raw.lowercased()
        if normalized.hasPrefix("source_path_missing") {
            return "源路径已经不存在。恢复路径后刷新，或直接清理这个来源。"
        }
        if normalized.contains("management key") {
            return "管理 key 不可用。若不再使用这个来源，可以清理。"
        }
        if normalized.hasPrefix("unsupported_toml_config") {
            return "配置结构不受支持。可以改配置后重新导入，或清理旧来源。"
        }
        if normalized.contains("save_failed") {
            return "Hub 本地状态保存失败，请确认目录可写后重试。"
        }
        return raw
    }

    private func formattedImportSourceTime(_ timestampMs: Int64) -> String {
        guard timestampMs > 0 else { return "未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0))
    }

    private func requestImportSourceRemoval(
        _ source: ProviderKeyImportSourceStatus,
        removeOwnedAccounts: Bool
    ) {
        importSourceRemovalTarget = ModelsDrawerImportSourceRemovalTarget(
            source: source,
            removeOwnedAccounts: removeOwnedAccounts
        )
    }

    private func removeImportSource(_ target: ModelsDrawerImportSourceRemovalTarget) {
        importSourceRemovalTarget = nil
        let result = ProviderKeyStorage.removeImportSource(
            target.source,
            removeOwnedAccounts: target.removeOwnedAccounts
        )

        if result.ok {
            let accountText = target.removeOwnedAccounts
                ? "移除账号 \(result.removedAccountCount)，保留共享账号 \(result.detachedAccountCount)"
                : "保留账号 \(result.detachedAccountCount)"
            importSourceActionText = "已清理 \(importSourceDisplayName(target.source))：\(accountText)。"
            importSourceErrorText = ""
        } else {
            importSourceActionText = ""
            importSourceErrorText = "清理失败：\(result.errors.joined(separator: ", "))"
        }

        reloadProviderKeySnapshot()
        modelStore.refresh()
    }

    private func importSourceRemovalTitle(
        _ target: ModelsDrawerImportSourceRemovalTarget?
    ) -> String {
        guard let target else { return "清理来源" }
        return target.removeOwnedAccounts ? "移除来源和账号" : "移除来源记录"
    }

    private func importSourceRemovalConfirmTitle(
        _ target: ModelsDrawerImportSourceRemovalTarget
    ) -> String {
        target.removeOwnedAccounts ? "移除来源和账号" : "移除来源记录"
    }

    private func importSourceRemovalMessage(
        _ target: ModelsDrawerImportSourceRemovalTarget
    ) -> String {
        let name = importSourceDisplayName(target.source)
        if target.removeOwnedAccounts {
            return "将移除 \(name) 这个来源，并删除只属于它的 \(target.source.ownedAccountCount) 个账号。被其他来源共同持有的账号会保留。"
        }
        return "将移除 \(name) 这个来源记录，账号会保留在 Hub 中继续用于路由。"
    }

    private func resourcePoolsSection(_ pools: [ModelsDrawerResourcePoolSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "模型资源池",
                subtitle: "按厂商和本地运行时聚合，先看能不能用，再看具体模型。"
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 260), spacing: 10, alignment: .top),
                    GridItem(.flexible(minimum: 260), spacing: 10, alignment: .top)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(pools) { pool in
                    resourcePoolRow(pool)
                }
            }
        }
    }

    private func resourcePoolRow(_ pool: ModelsDrawerResourcePoolSummary) -> some View {
        ModelsDrawerResourcePoolRow(
            pool: pool,
            quotaTint: quotaTint(for: pool),
            usageWindows: Array(pool.usageWindows.prefix(2)).map(usageWindowDisplay),
            onDiscoverLocalModels: {
                showDiscoverModels = true
            },
            onAddLocalModel: {
                showAddModel = true
            },
            onAddRemoteModel: {
                showAddRemoteModel = true
            }
        )
    }

    @ViewBuilder
    private var remoteModelSourcesSection: some View {
        let groups = remoteGroups
        let shouldShow = !groups.isEmpty
            || !remoteModelActionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !remoteModelErrorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if shouldShow {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: "远程模型来源",
                    subtitle: "按 Key 和 Endpoint 聚合模型目录；过期或不再续费的来源可以整组停用或移除。"
                )

                drawerPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            drawerStatusPill(
                                "\(groups.count) 组",
                                systemName: "cloud.fill",
                                tint: groups.isEmpty ? .secondary : .blue
                            )
                            drawerStatusPill(
                                "\(remoteModels.count) 远程模型",
                                systemName: "square.stack.3d.up",
                                tint: remoteModels.isEmpty ? .secondary : .indigo
                            )
                            drawerStatusPill(
                                remoteNeedsSetupCount > 0 ? "\(remoteNeedsSetupCount) 需配置" : "配置完整",
                                systemName: remoteNeedsSetupCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                                tint: remoteNeedsSetupCount > 0 ? .orange : .green
                            )

                            Spacer()

                            ModelsDrawerActionChip(
                                title: "添加远程模型",
                                systemName: "plus",
                                tint: .indigo
                            ) {
                                showAddRemoteModel = true
                            }
                        }

                        if !remoteModelActionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ModelsDrawerNoticeLine(
                                systemName: "checkmark.circle.fill",
                                text: remoteModelActionText,
                                tint: .green
                            )
                        }

                        if !remoteModelErrorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ModelsDrawerNoticeLine(
                                systemName: "exclamationmark.triangle.fill",
                                text: remoteModelErrorText,
                                tint: .red
                            )
                        }

                        if groups.isEmpty {
                            emptyStateLine("没有远程模型来源。添加远程模型后，这里会显示可管理的目录组。")
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(groups.prefix(6).enumerated()), id: \.element.id) { index, group in
                                    if index > 0 { Divider().opacity(0.24) }
                                    remoteModelSourceGroupRow(group)
                                        .padding(.vertical, 8)
                                }
                            }

                            if groups.count > 6 {
                                Text("还有 \(groups.count - 6) 组来源，可在模型库搜索具体模型。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func remoteModelSourceGroupRow(_ group: RemoteDrawerGroup) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(group.statusColor.opacity(0.12))
                Image(systemName: "cloud.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(group.statusColor)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(group.statusText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(group.statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(group.statusColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text([group.summary, group.detail ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                ModelsDrawerChipList(
                    chips: Array(group.models.map(\.title).prefix(4)),
                    tint: group.statusColor
                )
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ModelsDrawerIconButton(
                    title: "启用这组",
                    systemName: "play",
                    disabled: group.loadableModelIDs.isEmpty
                ) {
                    setRemoteModelsEnabled(group.loadableModelIDs, enabled: true)
                }

                ModelsDrawerIconButton(
                    title: "停用这组",
                    systemName: "pause",
                    disabled: group.enabledModelIDs.isEmpty
                ) {
                    setRemoteModelsEnabled(group.enabledModelIDs, enabled: false)
                }

                Menu {
                    Button("移除这组模型", role: .destructive) {
                        requestRemoteModelGroupRemoval(group)
                    }
                    .disabled(group.models.isEmpty)
                } label: {
                    ModelsDrawerActionChipLabel(
                        title: "移除",
                        systemName: "trash",
                        tint: .red,
                        disabled: group.models.isEmpty
                    )
                }
                .menuStyle(.borderlessButton)
            }
            .fixedSize()
        }
    }

    private func requestRemoteModelGroupRemoval(_ group: RemoteDrawerGroup) {
        remoteModelRemovalTarget = ModelsDrawerRemoteModelRemovalTarget(
            title: group.title,
            modelIDs: group.models.map(\.id),
            keyReference: group.keyReference,
            isGroup: true
        )
    }

    private func requestRemoteModelRemoval(_ entry: RemoteModelEntry) {
        remoteModelRemovalTarget = ModelsDrawerRemoteModelRemovalTarget(
            title: entry.nestedDisplayName,
            modelIDs: [entry.id],
            keyReference: RemoteModelStorage.keyReference(for: entry),
            isGroup: false
        )
    }

    private func removeRemoteModels(_ target: ModelsDrawerRemoteModelRemovalTarget) {
        remoteModelRemovalTarget = nil
        let ids = target.modelIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !ids.isEmpty else {
            remoteModelActionText = ""
            remoteModelErrorText = "没有可移除的远程模型。"
            return
        }

        let snapshot = RemoteModelStorage.remove(ids: ids)
        clearRoutingPreferencesForRemovedRemoteModels(ids)
        remoteModels = Self.sortedRemoteModels(snapshot.models)
        refreshRemoteDrawerGroups()
        store.pruneRemoteKeyHealthForCurrentRemoteModels()
        modelStore.refresh()
        reloadProviderKeySnapshot()

        remoteModelActionText = target.isGroup
            ? "已移除 \(target.title) 的 \(ids.count) 个远程模型。"
            : "已移除远程模型 \(target.title)。"
        remoteModelErrorText = ""
    }

    private func clearRoutingPreferencesForRemovedRemoteModels(_ ids: [String]) {
        let removedIDs = Set(
            ids
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        guard !removedIDs.isEmpty else { return }

        for (taskType, modelID) in store.routingPreferredModelIdByTask {
            let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if removedIDs.contains(normalized) {
                store.setRoutingPreferredModel(taskType: taskType, modelId: nil)
            }
        }

        if removedIDs.contains(routeCheckModelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            routeCheckFeedback = ""
            routeCheckModelId = ""
            routeCheckTaskId = ""
        }
    }

    private func remoteModelRemovalTitle(
        _ target: ModelsDrawerRemoteModelRemovalTarget?
    ) -> String {
        guard let target else { return "移除远程模型" }
        return target.isGroup ? "移除远程模型来源" : "移除远程模型"
    }

    private func remoteModelRemovalConfirmTitle(
        _ target: ModelsDrawerRemoteModelRemovalTarget
    ) -> String {
        target.isGroup ? "移除这组模型" : "移除模型"
    }

    private func remoteModelRemovalMessage(
        _ target: ModelsDrawerRemoteModelRemovalTarget
    ) -> String {
        if target.isGroup {
            return "将从 Hub 模型目录移除 \(target.title) 这组 \(target.modelCount) 个远程模型。若这组 key 不再被其它模型引用，Hub 会同步清理对应密钥引用。"
        }
        return "将从 Hub 模型目录移除 \(target.title)。这不会删除 Provider Key 账号池；需要清账号时请用上方来源清理。"
    }

    private var taskRouteMatrixSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "任务路由",
                subtitle: "Supervisor、Coder、Reviewer 可分别绑定模型；测试只做轻量预检或远程连通性。"
            )

            drawerPanel {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 0) {
                        ForEach(Array(routeControlRowSnapshot.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider().opacity(0.28) }
                            taskRouteControlRow(row)
                                .padding(.vertical, 9)
                        }
                    }

                    if !routeMatrixRowSnapshot.isEmpty {
                        Divider().opacity(0.35)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("自动策略观察")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(minimum: 128), spacing: 10, alignment: .top),
                                    GridItem(.flexible(minimum: 180), spacing: 10, alignment: .top)
                                ],
                                alignment: .leading,
                                spacing: 10
                            ) {
                                ForEach(routeMatrixRowSnapshot) { row in
                                    routeMatrixCell(row)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var localRuntimeAndModelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "本地模型",
                subtitle: "只展示已导入、可按需加载和已载入状态；发现和添加入口保留在本地资源池。"
            )

            drawerPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        drawerStatusPill(
                            runtimeAlive ? "运行时在线" : "运行时待恢复",
                            systemName: runtimeAlive ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            tint: runtimeAlive ? .green : .orange
                        )
                        drawerStatusPill(
                            "\(localModels.count) 模型",
                            systemName: "internaldrive",
                            tint: .indigo
                        )
                        drawerStatusPill(
                            "\(runtimeLoadedInstanceCount) 常驻",
                            systemName: "memorychip",
                            tint: runtimeLoadedInstanceCount > 0 ? .green : .secondary
                        )
                        Spacer()
                    }

                    if localModels.isEmpty {
                        emptyStateLine("还没有本地模型。发现或添加后，这里会显示可本地承接的模型。")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(localModels.prefix(4).enumerated()), id: \.element.id) { index, model in
                                if index > 0 { Divider().opacity(0.28) }
                                compactLocalModelRow(model)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
        }
    }

    private func modelLibrarySection(_ items: [ModelsDrawerLibraryItem]) -> some View {
        drawerPanel {
            DisclosureGroup(isExpanded: $modelLibraryExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        TextField("搜索模型", text: $librarySearch)
                            .textFieldStyle(.roundedBorder)

                        Picker("筛选", selection: $libraryFilter) {
                            ForEach(ModelsDrawerLibraryFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 300)
                    }

                    if items.isEmpty {
                        emptyStateLine("没有匹配的模型。")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(items.prefix(18).enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().opacity(0.24) }
                                modelLibraryRow(item)
                                    .padding(.vertical, 8)
                            }

                            if items.count > 18 {
                                Text("还有 \(items.count - 18) 个模型，继续用搜索或筛选缩小范围。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                            }
                        }
                    }
                }
                .padding(.top, 12)
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "books.vertical")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("模型库")
                            .font(.subheadline.weight(.semibold))
                        Text("库存列表默认收起，路由和资源池优先展示。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(items.count)/\(libraryItemSnapshot.count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func taskRouteControlRow(_ row: ModelsDrawerTaskRouteControlSnapshot) -> some View {
        return ModelsDrawerTaskRouteControlRow(
            task: row.task,
            decision: row.decision,
            preferredModelId: row.preferredModelId,
            tint: row.tint,
            systemName: row.systemName,
            purposeText: row.purposeText,
            detailText: row.detailText,
            stateText: row.stateText,
            preferenceLabel: row.preferenceLabel,
            availableModels: row.availableModels,
            routeCheckFeedback: routeCheckFeedback,
            routeCheckModelId: routeCheckModelId,
            routeCheckTaskId: routeCheckTaskId,
            trialStatus: routeTrialStatus(for: row.decision),
            onSetPreferred: { modelId in
                store.setRoutingPreferredModel(taskType: row.task.rawValue, modelId: modelId)
                routeCheckFeedback = ""
                routeCheckModelId = ""
                routeCheckTaskId = ""
            },
            onTest: {
                runRouteCheck(task: row.task, decision: row.decision)
            }
        )
    }

    private func routeMatrixCell(_ row: ModelsDrawerRouteMatrixRow) -> some View {
        ModelsDrawerRouteMatrixCell(row: row)
    }

    private func compactLocalModelRow(_ model: HubModel) -> some View {
        ModelsDrawerLocalModelRow(
            model: model,
            stateText: modelStateText(model.state),
            stateColor: modelStateColor(model.state),
            detail: compactModelDetail(model),
            tags: modelTags(model),
            trialStatus: store.localModelTrialStatus(for: model.id),
            healthScanInProgress: store.isLocalModelHealthScanInProgress(for: model.id),
            onQuickCheck: {
                store.quickCheckLocalModelHealth(for: [model.id])
            },
            onPinForTask: { task in
                store.setRoutingPreferredModel(taskType: task.rawValue, modelId: model.id)
                routeCheckFeedback = ""
                routeCheckModelId = ""
                routeCheckTaskId = ""
            }
        )
    }

    private func modelLibraryRow(_ item: ModelsDrawerLibraryItem) -> some View {
        ModelsDrawerLibraryRow(
            item: item,
            trialStatus: libraryTrialStatus(for: item),
            onPinForTask: { task in
                store.setRoutingPreferredModel(taskType: task.rawValue, modelId: item.modelId)
                routeCheckFeedback = ""
                routeCheckModelId = ""
                routeCheckTaskId = ""
            },
            onTest: {
                if let remoteEntry = item.remoteEntry {
                    store.testRemoteModelConnectivity(remoteEntry)
                } else {
                    store.quickCheckLocalModelHealth(for: [item.modelId])
                }
            },
            onSetRemoteEnabled: { enabled in
                if let remoteEntry = item.remoteEntry {
                    setRemoteModelsEnabled([remoteEntry.id], enabled: enabled)
                }
            },
            onRemoveRemoteModel: {
                if let remoteEntry = item.remoteEntry {
                    requestRemoteModelRemoval(remoteEntry)
                }
            }
        )
    }

    private func drawerPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ModelsDrawerPanel(content: content)
    }

    private func drawerStatusPill(_ title: String, systemName: String, tint: Color) -> some View {
        ModelsDrawerStatusPill(title: title, systemName: systemName, tint: tint)
    }

    private func drawerIconOnlyButton(_ title: String, systemName: String, action: @escaping () -> Void) -> some View {
        ModelsDrawerIconOnlyButton(title: title, systemName: systemName, action: action)
    }

    private func emptyStateLine(_ text: String) -> some View {
        ModelsDrawerEmptyStateLine(text: text)
    }

    private static func sortedRemoteModels(_ models: [RemoteModelEntry]) -> [RemoteModelEntry] {
        RemoteModelPresentationSupport.sorted(models)
    }

    private func refreshLocalModelSnapshot() {
        let startedAt = HubPerformanceTrace.now()
        let next = ModelsDrawerLocalModelSnapshot.build(from: modelStore.snapshot.models)
        assignIfChanged(&localModelSnapshot, next)
        HubPerformanceTrace.logSlow(
            "models.drawer.local_snapshot",
            startedAt: startedAt,
            thresholdMs: 16,
            details: "models=\(modelStore.snapshot.models.count)"
        )
        rebuildDrawerDerivedSnapshots()
    }

    private func refreshRemoteDrawerGroups() {
        let startedAt = HubPerformanceTrace.now()
        let next = remoteDrawerGroups(from: remoteModels)
        assignIfChanged(&remoteDrawerGroupSnapshot, next)
        HubPerformanceTrace.logSlow(
            "models.drawer.remote_groups",
            startedAt: startedAt,
            thresholdMs: 20,
            details: "remote_models=\(remoteModels.count) groups=\(remoteDrawerGroupSnapshot.count)"
        )
        rebuildDrawerDerivedSnapshots()
    }

    private func reloadRemoteModels(initial: Bool = false) {
        remoteModelsReloadTask?.cancel()
        remoteModelsReloadTask = Task { @MainActor in
            let startedAt = HubPerformanceTrace.now()
            let loaded = await Task.detached(priority: .userInitiated) {
                RemoteModelPresentationSupport.sorted(RemoteModelStorage.load().models)
            }.value
            guard !Task.isCancelled else { return }
            assignIfChanged(&remoteModels, loaded)
            let groups = remoteDrawerGroups(from: loaded)
            assignIfChanged(&remoteDrawerGroupSnapshot, groups)
            HubPerformanceTrace.logSlow(
                "models.drawer.reload_remote",
                startedAt: startedAt,
                thresholdMs: initial ? 80 : 50,
                details: "initial=\(initial ? 1 : 0) remote_models=\(loaded.count) groups=\(groups.count)"
            )
            rebuildDrawerDerivedSnapshots()
            remoteModelsReloadTask = nil
        }
    }

    private func reloadProviderKeySnapshot() {
        if store.remoteKeyHealthScanInFlight,
           store.remoteKeyHealthActiveScanMode == .full {
            return
        }
        providerKeyReloadTask?.cancel()
        providerKeyReloadTask = Task { @MainActor in
            let startedAt = HubPerformanceTrace.now()
            let loaded = await Task.detached(priority: .userInitiated) {
                RemoteProviderKeyBootstrapper.bootstrapIfNeeded()
                return ModelsDrawerProviderKeySnapshot.build(from: ProviderKeyStorage.load())
            }.value
            guard !Task.isCancelled else { return }
            assignIfChanged(&providerKeySnapshot, loaded)
            HubPerformanceTrace.logSlow(
                "models.drawer.reload_provider_keys",
                startedAt: startedAt,
                thresholdMs: 80,
                details: "key_pools=\(loaded.keyPools.count) quota_pools=\(loaded.quotaPools.count)"
            )
            rebuildDrawerDerivedSnapshots()
            providerKeyReloadTask = nil
        }
    }

    private func rebuildDrawerDerivedSnapshots() {
        let totalStartedAt = HubPerformanceTrace.now()

        let poolsStartedAt = HubPerformanceTrace.now()
        let pools = resourcePoolSummaries
        HubPerformanceTrace.logSlow(
            "models.drawer.derive_resource_pools",
            startedAt: poolsStartedAt,
            thresholdMs: 12,
            details: "pools=\(pools.count) local=\(localModels.count) remote=\(remoteModels.count)"
        )

        let libraryStartedAt = HubPerformanceTrace.now()
        let items = libraryItems
        HubPerformanceTrace.logSlow(
            "models.drawer.derive_library_items",
            startedAt: libraryStartedAt,
            thresholdMs: 18,
            details: "items=\(items.count) local=\(localModels.count) remote=\(remoteModels.count)"
        )

        let routeStartedAt = HubPerformanceTrace.now()
        let routeControls = routeControlRows
        let routeRows = routeMatrixRows
        let roleSummaries = roleRouteSummaries
        HubPerformanceTrace.logSlow(
            "models.drawer.derive_route_matrix",
            startedAt: routeStartedAt,
            thresholdMs: 12,
            details: "controls=\(routeControls.count) rows=\(routeRows.count) roles=\(roleSummaries.count) models=\(modelStore.snapshot.models.count)"
        )

        assignIfChanged(&resourcePoolSnapshot, pools)
        assignIfChanged(&libraryItemSnapshot, items)
        assignIfChanged(&routeControlRowSnapshot, routeControls)
        assignIfChanged(&routeMatrixRowSnapshot, routeRows)
        assignIfChanged(&roleRouteSummarySnapshot, roleSummaries)
        rebuildFilteredLibrarySnapshot(baseItems: items)

        HubPerformanceTrace.logSlow(
            "models.drawer.derive_total",
            startedAt: totalStartedAt,
            thresholdMs: 35,
            details: "pools=\(pools.count) items=\(items.count) routes=\(routeRows.count)"
        )
    }

    private func rebuildFilteredLibrarySnapshot(baseItems: [ModelsDrawerLibraryItem]? = nil) {
        let startedAt = HubPerformanceTrace.now()
        let items = filteredLibraryItems(from: baseItems ?? libraryItemSnapshot)
        assignIfChanged(&filteredLibraryItemSnapshot, items)
        HubPerformanceTrace.logSlow(
            "models.drawer.filter_library_items",
            startedAt: startedAt,
            thresholdMs: 10,
            details: "items=\(items.count) base=\((baseItems ?? libraryItemSnapshot).count)"
        )
    }

    private func assignIfChanged<Value: Equatable>(_ state: inout Value, _ next: Value) {
        if state != next {
            state = next
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String) -> some View {
        ModelsDrawerSectionHeader(title: title, subtitle: subtitle)
    }

    private func setRemoteModelsEnabled(_ modelIDs: [String], enabled: Bool) {
        let ids = Set(modelIDs)
        guard !ids.isEmpty else { return }
        var snapshot = RemoteModelStorage.load()
        var changed = false
        for index in snapshot.models.indices where ids.contains(snapshot.models[index].id) {
            if enabled {
                var candidate = snapshot.models[index]
                candidate.enabled = true
                guard RemoteModelStorage.isExecutionReadyRemoteModel(candidate) else { continue }
            }
            if snapshot.models[index].enabled != enabled {
                snapshot.models[index].enabled = enabled
                changed = true
            }
        }
        guard changed else { return }
        RemoteModelStorage.save(snapshot)
        reloadRemoteModels()
        modelStore.refresh()
    }

}
