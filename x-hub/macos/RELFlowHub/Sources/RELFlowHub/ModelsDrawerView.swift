import SwiftUI
import AppKit
import RELFlowHubCore

private struct ModelsDrawerLocalModelSnapshot {
    var models: [HubModel]
    var sections: [ModelLibrarySection]
    var loadedCount: Int

    static let empty = ModelsDrawerLocalModelSnapshot(
        models: [],
        sections: [],
        loadedCount: 0
    )

    static func build(from catalogModels: [HubModel]) -> ModelsDrawerLocalModelSnapshot {
        let models = LocalModelRuntimeActionPlanner.localModels(from: catalogModels)
        return ModelsDrawerLocalModelSnapshot(
            models: models,
            sections: ModelLibrarySectionPlanner.sections(from: models),
            loadedCount: models.filter { $0.state == .loaded }.count
        )
    }
}

private struct ModelsDrawerProviderKeySnapshot: Equatable {
    var totalAccounts: Int
    var readyAccounts: Int
    var blockedAccounts: Int
    var keyPools: [ProviderKeyPoolSnapshot]
    var quotaPools: [ProviderQuotaPoolSnapshot]

    static let empty = ModelsDrawerProviderKeySnapshot(
        totalAccounts: 0,
        readyAccounts: 0,
        blockedAccounts: 0,
        keyPools: [],
        quotaPools: []
    )

    static func build(from snapshot: ProviderKeyStoreSnapshot) -> ModelsDrawerProviderKeySnapshot {
        let derived = ProviderKeyStorage.derivedSnapshot(from: snapshot)
        return ModelsDrawerProviderKeySnapshot(
            totalAccounts: derived.totalAccounts,
            readyAccounts: derived.readyAccounts,
            blockedAccounts: derived.blockedAccounts,
            keyPools: derived.keyPools,
            quotaPools: derived.quotaPools
        )
    }
}

private enum ModelsDrawerLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case remote
    case local
    case ready
    case needsSetup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .remote: return "远程"
        case .local: return "本地"
        case .ready: return "可用"
        case .needsSetup: return "需配置"
        }
    }
}

struct ModelsDrawerResourcePoolSummary: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var statusText: String
    var statusColor: Color
    var systemName: String
    var modelText: String
    var accountText: String
    var quotaText: String
    var models: [String]
    var usageWindows: [ProviderKeyUsageWindow]
    var detailText: String
    var isLocal: Bool
}

struct ModelsDrawerRouteMatrixRow: Identifiable {
    var id: String
    var title: String
    var modelName: String
    var provider: String
    var statusText: String
    var statusColor: Color
    var reason: String
}

struct ModelsDrawerLibraryItem: Identifiable {
    var id: String
    var title: String
    var provider: String
    var detail: String
    var statusText: String
    var statusColor: Color
    var tags: [String]
    var isLocal: Bool
    var isReady: Bool
    var modelId: String
    var remoteEntry: RemoteModelEntry?
}

struct ModelsDrawer: View {
    @EnvironmentObject var store: HubStore
    @ObservedObject private var modelStore = ModelStore.shared
    @State private var remoteModels: [RemoteModelEntry] = []
    @State private var providerKeySnapshot: ModelsDrawerProviderKeySnapshot = .empty
    @State private var localModelSnapshot: ModelsDrawerLocalModelSnapshot = .empty
    @State private var remoteDrawerGroupSnapshot: [RemoteDrawerGroup] = []
    @State private var showDiscoverModels: Bool = false
    @State private var showAddModel: Bool = false
    @State private var showAddRemoteModel: Bool = false
    @State private var routeTask: HubTaskType = .supervisor
    @State private var routeAllowAutoLoad: Bool = true
    @State private var routeCheckFeedback: String = ""
    @State private var routeCheckModelId: String = ""
    @State private var libraryFilter: ModelsDrawerLibraryFilter = .all
    @State private var librarySearch: String = ""
    @State private var modelLibraryExpanded: Bool = false
    @State private var resourcePoolSnapshot: [ModelsDrawerResourcePoolSummary] = []
    @State private var libraryItemSnapshot: [ModelsDrawerLibraryItem] = []
    @State private var routeMatrixRowSnapshot: [ModelsDrawerRouteMatrixRow] = []
    @State private var remoteModelsReloadTask: Task<Void, Never>? = nil
    @State private var providerKeyReloadTask: Task<Void, Never>? = nil

    private var localModels: [HubModel] {
        localModelSnapshot.models
    }

    private var remoteGroups: [RemoteDrawerGroup] {
        remoteDrawerGroupSnapshot
    }

    private var quotaPools: [ProviderQuotaPoolSnapshot] {
        providerKeySnapshot.quotaPools
    }

    private var localLoadedCount: Int {
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

    private var runtimeAlive: Bool {
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
        let currentDecision = self.currentRouteDecision(for: routeTask)
        let pools = self.resourcePoolSnapshot
        let libraryItems = self.filteredLibraryItems(from: libraryItemSnapshot)

        VStack(alignment: .leading, spacing: 0) {
            self.drawerHeader

            Divider()
                .opacity(0.35)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    self.portfolioOverviewPanel(currentDecision: currentDecision, pools: pools)

                    self.resourcePoolsSection(pools)

                    self.taskRouteMatrixSection

                    self.localRuntimeAndModelsSection

                    self.modelLibrarySection(libraryItems)
                }
                .padding(14)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 2)
        .padding(10)
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
                        runtimeAlive ? "Runtime 在线" : "Runtime 待恢复",
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
            runtimeTotalProviderCount > 0 ? "\(runtimeReadyProviderCount)/\(runtimeTotalProviderCount) provider" : "等待 provider",
            runtimeLoadedInstanceCount > 0 ? "\(runtimeLoadedInstanceCount) 常驻实例" : ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")

        return ModelsDrawerResourcePoolSummary(
            id: "local",
            title: "Local",
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

    private func portfolioOverviewPanel(
        currentDecision decision: HubTaskRouteDecision,
        pools: [ModelsDrawerResourcePoolSummary]
    ) -> some View {
        let tint = decision.modelId.isEmpty ? Color.orange : modelStateColor(decision.modelState ?? .available)
        let quotaSignal = portfolioQuotaSignal(pools)
        let usablePools = pools.filter { pool in
            ["可用", "运行中", "待加载"].contains(pool.statusText)
        }.count

        return ModelsDrawerPortfolioOverviewPanel(
            routeTask: $routeTask,
            routeAllowAutoLoad: $routeAllowAutoLoad,
            decision: decision,
            tint: tint,
            routeDetail: routeRecommendationDetail(decision),
            quotaSignalText: quotaSignal.text,
            quotaSignalTint: quotaSignal.tint,
            usablePoolCount: usablePools,
            poolCount: pools.count,
            readyAccountCount: providerKeySnapshot.readyAccounts,
            totalAccountCount: providerKeySnapshot.totalAccounts,
            runtimeLoadedInstanceCount: runtimeLoadedInstanceCount,
            preferenceLabel: routePreferenceLabel(for: routeTask),
            availableModels: modelStore.snapshot.models,
            routeCheckFeedback: routeCheckFeedback,
            routeCheckModelId: routeCheckModelId,
            trialStatus: routeTrialStatus(for: decision),
            onTestRoute: {
                runRouteCheck(decision)
            },
            onPinRoute: {
                store.setRoutingPreferredModel(taskType: routeTask.rawValue, modelId: decision.modelId)
            },
            onSetPreferred: { modelId in
                store.setRoutingPreferredModel(taskType: routeTask.rawValue, modelId: modelId)
                routeCheckFeedback = ""
                routeCheckModelId = ""
            }
        )
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

    private var taskRouteMatrixSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "任务路由",
                subtitle: "Supervisor、Coder、Reviewer 可分别绑定模型；测试只做轻量预检或远程连通性。"
            )

            drawerPanel {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 0) {
                        ForEach(Array(HubTaskType.allCases.enumerated()), id: \.element.id) { index, task in
                            if index > 0 { Divider().opacity(0.28) }
                            taskRouteControlRow(task)
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
                subtitle: "只展示已导入、可按需加载和已载入状态；发现和添加入口保留在 Local 资源池。"
            )

            drawerPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        drawerStatusPill(
                            runtimeAlive ? "Runtime 在线" : "Runtime 待恢复",
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

    private func taskRouteControlRow(_ task: HubTaskType) -> some View {
        let decision = currentRouteDecision(for: task)
        let preferredModelId = effectivePreferredModelId(for: task)
        let tint = decision.modelId.isEmpty ? Color.orange : modelStateColor(decision.modelState ?? .available)

        return ModelsDrawerTaskRouteControlRow(
            task: task,
            decision: decision,
            preferredModelId: preferredModelId,
            tint: tint,
            systemName: routeTaskSystemName(task),
            purposeText: routeTaskPurposeText(task),
            detailText: routeRecommendationDetail(decision),
            stateText: modelStateText(decision.modelState ?? .available),
            preferenceLabel: routePreferenceShortLabel(for: task),
            availableModels: modelStore.snapshot.models,
            routeCheckFeedback: routeCheckFeedback,
            routeCheckModelId: routeCheckModelId,
            trialStatus: routeTrialStatus(for: decision),
            onSetPreferred: { modelId in
                store.setRoutingPreferredModel(taskType: task.rawValue, modelId: modelId)
                routeCheckFeedback = ""
                routeCheckModelId = ""
            },
            onTest: {
                runRouteCheck(decision)
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
            onPin: {
                store.setRoutingPreferredModel(taskType: routeTask.rawValue, modelId: model.id)
            }
        )
    }

    private func modelLibraryRow(_ item: ModelsDrawerLibraryItem) -> some View {
        ModelsDrawerLibraryRow(
            item: item,
            trialStatus: libraryTrialStatus(for: item),
            onPin: {
                store.setRoutingPreferredModel(taskType: routeTask.rawValue, modelId: item.modelId)
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

    private func portfolioQuotaSignal(_ pools: [ModelsDrawerResourcePoolSummary]) -> (text: String, tint: Color) {
        let windows = pools.flatMap { $0.usageWindows }
        if windows.contains(where: \.limited) {
            return ("受限", .red)
        }
        guard let hottest = windows.max(by: { providerKeyUsageWindowPercent($0) < providerKeyUsageWindowPercent($1) }) else {
            return (quotaPools.isEmpty ? "本机" : "待同步", quotaPools.isEmpty ? .green : .secondary)
        }
        let text = "\(providerKeyUsageWindowTitle(hottest)) \(providerKeyUsageWindowPercentText(hottest))"
        return (text, providerKeyUsageWindowTint(hottest))
    }

    private func usageWindowDisplay(_ window: ProviderKeyUsageWindow) -> ModelsDrawerUsageWindowDisplay {
        let percent = providerKeyUsageWindowPercent(window)
        return ModelsDrawerUsageWindowDisplay(
            id: window.key,
            title: providerKeyUsageWindowTitle(window),
            percentText: providerKeyUsageWindowPercentText(window),
            resetText: providerKeyUsageWindowResetText(window),
            progress: min(1.0, max(0.0, percent / 100.0)),
            tint: providerKeyUsageWindowTint(window)
        )
    }

    private func emptyStateLine(_ text: String) -> some View {
        ModelsDrawerEmptyStateLine(text: text)
    }

    private func currentRouteDecision(for taskType: HubTaskType) -> HubTaskRouteDecision {
        HubTaskRoutingPolicy.decision(
            taskType: taskType,
            models: modelStore.snapshot.models,
            preferredModelId: effectivePreferredModelId(for: taskType),
            allowAutoLoad: routeAllowAutoLoad
        )
    }

    private func effectivePreferredModelId(for taskType: HubTaskType) -> String {
        (store.routingPreferredModelIdByTask[taskType.rawValue] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func routePreferenceLabel(for taskType: HubTaskType) -> String {
        let modelId = effectivePreferredModelId(for: taskType)
        guard !modelId.isEmpty else {
            return "\(taskType.label): Auto"
        }
        let modelName = modelStore.snapshot.models.first(where: { $0.id == modelId })?.name
            ?? remoteModels.first(where: { $0.id == modelId })?.nestedDisplayName
            ?? modelId
        return "\(taskType.label): \(modelName)"
    }

    private func routePreferenceShortLabel(for taskType: HubTaskType) -> String {
        let modelId = effectivePreferredModelId(for: taskType)
        guard !modelId.isEmpty else { return "Auto" }
        return modelStore.snapshot.models.first(where: { $0.id == modelId })?.name
            ?? remoteModels.first(where: { $0.id == modelId })?.nestedDisplayName
            ?? modelId
    }

    private func routeTaskSystemName(_ taskType: HubTaskType) -> String {
        switch taskType {
        case .supervisor:
            return "point.topleft.down.curvedto.point.bottomright.up"
        case .coder:
            return "chevron.left.forwardslash.chevron.right"
        case .reviewer:
            return "checkmark.seal"
        }
    }

    private func routeTaskPurposeText(_ taskType: HubTaskType) -> String {
        switch taskType {
        case .supervisor:
            return "规划、调度、拆解"
        case .coder:
            return "代码、执行、低延迟"
        case .reviewer:
            return "审查、校验、质量优先"
        }
    }

    private func routeRecommendationDetail(_ decision: HubTaskRouteDecision) -> String {
        guard !decision.modelId.isEmpty else {
            return "没有可路由模型；先添加本地模型或远程模型。"
        }
        let provider = modelStore.snapshot.models
            .first(where: { $0.id == decision.modelId })
            .map(providerTitle(for:)) ?? "Hub"
        let auto = decision.willAutoLoad ? " · 需要自动加载" : ""
        return "\(provider) · \(routeReasonText(decision.reason))\(auto)"
    }

    private func routeMatrixRow(
        id: String,
        title: String,
        decision: HubTaskRouteDecision
    ) -> ModelsDrawerRouteMatrixRow {
        guard !decision.modelId.isEmpty else {
            return ModelsDrawerRouteMatrixRow(
                id: id,
                title: title,
                modelName: "未路由",
                provider: "",
                statusText: "Blocked",
                statusColor: .orange,
                reason: routeReasonText(decision.reason)
            )
        }

        let model = modelStore.snapshot.models.first(where: { $0.id == decision.modelId })
        return ModelsDrawerRouteMatrixRow(
            id: id,
            title: title,
            modelName: decision.modelName,
            provider: model.map(providerTitle(for:)) ?? "Hub",
            statusText: decision.willAutoLoad ? "Auto" : modelStateText(decision.modelState ?? .available),
            statusColor: decision.willAutoLoad ? .indigo : modelStateColor(decision.modelState ?? .available),
            reason: routeReasonText(decision.reason)
        )
    }

    private func bestModelRouteRow(
        id: String,
        title: String,
        models: [HubModel],
        reason: String
    ) -> ModelsDrawerRouteMatrixRow {
        guard let model = models.first else {
            return ModelsDrawerRouteMatrixRow(
                id: id,
                title: title,
                modelName: "未匹配",
                provider: "",
                statusText: "None",
                statusColor: .secondary,
                reason: "没有匹配能力"
            )
        }
        return ModelsDrawerRouteMatrixRow(
            id: id,
            title: title,
            modelName: model.name,
            provider: providerTitle(for: model),
            statusText: modelStateText(model.state),
            statusColor: modelStateColor(model.state),
            reason: reason
        )
    }

    private func runRouteCheck(_ decision: HubTaskRouteDecision) {
        let modelId = decision.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else { return }
        routeCheckModelId = modelId

        if let remote = remoteEntry(forModelId: modelId) {
            routeCheckFeedback = "已发起 \(decision.modelName.isEmpty ? modelId : decision.modelName) 远程连通性测试。"
            store.testRemoteModelConnectivity(remote)
            return
        }

        if let model = modelStore.snapshot.models.first(where: { $0.id == modelId }),
           LocalModelRuntimeActionPlanner.isRemoteModel(model) {
            routeCheckFeedback = "找不到 \(model.name) 的远程模型配置，不能发起连接测试。"
            return
        }

        routeCheckFeedback = "已发起 \(decision.modelName.isEmpty ? modelId : decision.modelName) 本地轻量预检。"
        store.quickCheckLocalModelHealth(for: [modelId])
    }

    private func remoteEntry(forModelId modelId: String) -> RemoteModelEntry? {
        let normalized = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if let cached = remoteModels.first(where: { remoteModelMatches($0, modelId: normalized) }) {
            return cached
        }
        return RemoteModelStorage.load().models.first(where: { remoteModelMatches($0, modelId: normalized) })
    }

    private func remoteModelMatches(_ entry: RemoteModelEntry, modelId: String) -> Bool {
        let normalized = modelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return entry.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
            || entry.effectiveProviderModelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
            || entry.nestedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
    }

    private func libraryTrialStatus(for item: ModelsDrawerLibraryItem) -> ModelTrialStatus? {
        if let remoteEntry = item.remoteEntry {
            return store.remoteModelTrialStatus(for: remoteEntry.id)
        }
        return item.isLocal
            ? store.localModelTrialStatus(for: item.modelId)
            : store.remoteModelTrialStatus(for: item.modelId)
    }

    private func routeTrialStatus(for decision: HubTaskRouteDecision) -> ModelTrialStatus? {
        let modelId = decision.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelId.isEmpty else { return nil }
        if let remote = remoteModels.first(where: { remoteModelMatches($0, modelId: modelId) }) {
            return store.remoteModelTrialStatus(for: remote.id)
        }
        if let model = modelStore.snapshot.models.first(where: { $0.id == modelId }),
           LocalModelRuntimeActionPlanner.isRemoteModel(model) {
            return store.remoteModelTrialStatus(for: modelId)
        }
        return store.localModelTrialStatus(for: modelId)
    }

    private var localResourcePoolDetailText: String {
        if localModels.isEmpty {
            return "本地模型会用于隐私任务、离线任务和低延迟任务。"
        }
        if !runtimeAlive {
            return "Runtime 未就绪，本地模型暂时只作为目录展示。"
        }
        if localLoadedCount > 0 {
            return "\(localLoadedCount) 个模型已经常驻，可以直接承接本地任务。"
        }
        return "本地模型已编目，可按任务需要自动加载。"
    }

    private func remoteResourcePoolDetailText(
        providerName: String,
        keyPools: [ProviderKeyPoolSnapshot],
        models: [RemoteModelEntry],
        needsSetup: Int
    ) -> String {
        if models.isEmpty && !keyPools.isEmpty {
            return "\(providerName) 账号已接入，但还没有编入可执行模型。"
        }
        if keyPools.isEmpty && !models.isEmpty {
            return "\(providerName) 模型已编目，但缺少可路由账号或 Key。"
        }
        if needsSetup > 0 {
            return "\(needsSetup) 个模型需要补齐 Key、Endpoint 或健康检查。"
        }
        if keyPools.contains(where: { $0.hasQuotaData }) {
            return "额度和 Key 健康已同步，Hub 可按资源池进行路由。"
        }
        return "已编入模型，额度窗口等待 provider 同步。"
    }

    private func providerPoolDisplayName(_ pool: ProviderKeyPoolSnapshot) -> String {
        let display = pool.providerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let provider = pool.provider.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.isEmpty { return "Remote" }
        switch provider.lowercased() {
        case "openai": return "OpenAI"
        case "anthropic": return "Anthropic"
        case "gemini", "google": return "Gemini"
        default: return provider.uppercased()
        }
    }

    private func providerTitle(for model: HubModel) -> String {
        if LocalModelRuntimeActionPlanner.isRemoteModel(model) {
            let backend = model.backend.trimmingCharacters(in: .whitespacesAndNewlines)
            switch backend.lowercased() {
            case "openai": return "OpenAI"
            case "anthropic": return "Anthropic"
            case "gemini", "google": return "Gemini"
            case "remote", "remote_catalog": return model.remoteEndpointHost ?? "Remote"
            default: return backend.isEmpty ? "Remote" : backend.uppercased()
            }
        }
        return "Local"
    }

    private func compactModelDetail(_ model: HubModel) -> String {
        let context = model.maxContextLength > model.contextLength
            ? "ctx \(model.contextLength)/\(model.maxContextLength)"
            : "ctx \(model.contextLength)"
        let perf = model.tokensPerSec.map { String(format: "%.1f tok/s", $0) } ?? ""
        let size = model.paramsB > 0 ? String(format: "%.1fB", model.paramsB) : ""
        return [model.backend, model.quant, size, context, perf]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.lowercased() != "unknown" }
            .joined(separator: " · ")
    }

    private func modelTags(_ model: HubModel) -> [String] {
        var tags: [String] = []
        tags.append(contentsOf: HubTaskRoutingPolicy.capabilityTags(for: model, limit: 3))
        if model.offlineReady { tags.append("本地") }
        if modelSupportsVision(model) { tags.append("视觉") }
        if model.maxContextLength >= 64_000 { tags.append("长上下文") }
        var seen = Set<String>()
        let uniqueTags = tags.filter { !$0.isEmpty && seen.insert($0).inserted }
        return Array(uniqueTags.prefix(4))
    }

    private func modelSupportsVision(_ model: HubModel) -> Bool {
        let tokens = model.inputModalities + model.outputModalities + model.taskKinds
        return tokens.contains { token in
            let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.contains("vision")
                || normalized.contains("image")
                || normalized.contains("ocr")
        }
    }

    private func modelStateText(_ state: HubModelState) -> String {
        switch state {
        case .loaded: return "Ready"
        case .available: return "Available"
        case .sleeping: return "Sleep"
        }
    }

    private func modelStateColor(_ state: HubModelState) -> Color {
        switch state {
        case .loaded: return .green
        case .available: return .indigo
        case .sleeping: return .orange
        }
    }

    private func remoteLibraryDetail(_ entry: RemoteModelEntry) -> String {
        let context = Self.remoteContextSummary(for: entry)
        let host = RemoteModelPresentationSupport.endpointHost(for: entry) ?? ""
        return [entry.effectiveProviderModelID, host, context]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func remoteModelTags(_ entry: RemoteModelEntry) -> [String] {
        var tags: [String] = []
        let modelID = entry.effectiveProviderModelID.lowercased()
        if modelID.contains("gpt") || modelID.contains("claude") || modelID.contains("gemini") {
            tags.append("推理")
        }
        if modelID.contains("coder") || modelID.contains("code") {
            tags.append("代码")
        }
        if modelID.contains("vision") || modelID.contains("image") {
            tags.append("视觉")
        }
        if max(entry.contextLength, entry.knownContextLength ?? 0) >= 64_000 {
            tags.append("长上下文")
        }
        if tags.isEmpty { tags.append("远程") }
        return Array(tags.prefix(4))
    }

    private func remoteModelStateText(_ state: RemoteModelLoadState) -> String {
        switch state {
        case .loaded: return "Ready"
        case .available: return "Available"
        case .needsSetup: return "Setup"
        }
    }

    private func remoteModelStateColor(_ state: RemoteModelLoadState) -> Color {
        switch state {
        case .loaded: return .green
        case .available: return .indigo
        case .needsSetup: return .orange
        }
    }

    private func routeReasonText(_ reason: String) -> String {
        switch reason {
        case "preferred_model": return "用户指定"
        case "task_match_loaded", "role_match_loaded": return "任务匹配且已就绪"
        case "task_match_autoload", "role_match_autoload": return "任务匹配，可自动加载"
        case "fallback_loaded": return "回退到已就绪模型"
        case "fallback_autoload": return "回退到可自动加载模型"
        case "no_models_registered": return "没有注册模型"
        case "model_not_loaded": return "没有已加载模型"
        default: return reason
        }
    }

    private func quotaTint(for pool: ModelsDrawerResourcePoolSummary) -> Color {
        if pool.isLocal { return .green }
        guard let first = pool.usageWindows.first else {
            return pool.quotaText == "未知" ? .secondary : pool.statusColor
        }
        return providerKeyUsageWindowTint(first)
    }

    private func providerDisplayUsageWindows(for pools: [ProviderKeyPoolSnapshot]) -> [ProviderKeyUsageWindow] {
        var grouped: [String: ProviderKeyUsageWindow] = [:]
        for pool in pools {
            for member in pool.members {
                for window in providerKeyDisplayUsageWindows(member.account) {
                    let groupKey = providerKeyUsageWindowGroupKey(window)
                    var normalized = window
                    normalized.key = "drawer:\(pool.poolID):\(groupKey)"
                    if let existing = grouped[groupKey] {
                        var selected = providerKeyMoreConstrainedUsageWindow(existing, normalized)
                        selected.key = "drawer:\(groupKey)"
                        selected.limited = existing.limited || normalized.limited || selected.limited
                        selected.resetAtMs = providerKeyEarliestPositiveTimestamp(existing.resetAtMs, normalized.resetAtMs)
                        selected.updatedAtMs = max(existing.updatedAtMs, normalized.updatedAtMs)
                        grouped[groupKey] = selected
                    } else {
                        grouped[groupKey] = normalized
                    }
                }
            }
        }

        return grouped.values.sorted {
            let lhsRank = providerKeyUsageWindowRank($0)
            let rhsRank = providerKeyUsageWindowRank($1)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if $0.limitWindowSeconds != $1.limitWindowSeconds {
                return $0.limitWindowSeconds < $1.limitWindowSeconds
            }
            return $0.key < $1.key
        }
    }

    private func providerKeyDisplayUsageWindows(_ account: ProviderKeyAccount) -> [ProviderKeyUsageWindow] {
        let windows = account.quota.usageWindows
        guard !windows.isEmpty else { return [] }

        let rateLimitWindows = windows.filter {
            $0.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "rate_limit"
        }
        let preferred = rateLimitWindows.filter {
            $0.limitWindowSeconds == 5 * 60 * 60 || $0.limitWindowSeconds == 7 * 24 * 60 * 60
        }
        let selected: [ProviderKeyUsageWindow]
        if !preferred.isEmpty {
            selected = preferred
        } else if !rateLimitWindows.isEmpty {
            selected = Array(rateLimitWindows.prefix(2))
        } else {
            selected = Array(windows.prefix(2))
        }

        return selected.sorted {
            let lhsRank = providerKeyUsageWindowRank($0)
            let rhsRank = providerKeyUsageWindowRank($1)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return $0.limitWindowSeconds < $1.limitWindowSeconds
        }
    }

    private func providerKeyUsageWindowGroupKey(_ window: ProviderKeyUsageWindow) -> String {
        let source = window.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let windowKey = window.windowKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedSource = source.isEmpty ? "usage" : source
        let normalizedWindowKey = windowKey.isEmpty ? "window" : windowKey
        if window.limitWindowSeconds > 0 {
            return "\(normalizedSource):\(normalizedWindowKey):\(window.limitWindowSeconds)"
        }
        let rawKey = window.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedSource):\(normalizedWindowKey):\(rawKey.isEmpty ? "unknown" : rawKey)"
    }

    private func providerKeyMoreConstrainedUsageWindow(
        _ lhs: ProviderKeyUsageWindow,
        _ rhs: ProviderKeyUsageWindow
    ) -> ProviderKeyUsageWindow {
        if lhs.limited != rhs.limited {
            return rhs.limited ? rhs : lhs
        }
        let lhsPercent = providerKeyUsageWindowPercent(lhs)
        let rhsPercent = providerKeyUsageWindowPercent(rhs)
        if lhsPercent != rhsPercent {
            return rhsPercent > lhsPercent ? rhs : lhs
        }
        if lhs.resetAtMs != rhs.resetAtMs {
            return providerKeyEarliestPositiveTimestamp(lhs.resetAtMs, rhs.resetAtMs) == rhs.resetAtMs ? rhs : lhs
        }
        return lhs.key <= rhs.key ? lhs : rhs
    }

    private func providerKeyEarliestPositiveTimestamp(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        if lhs <= 0 { return max(0, rhs) }
        if rhs <= 0 { return lhs }
        return min(lhs, rhs)
    }

    private func providerKeyUsageWindowRank(_ window: ProviderKeyUsageWindow) -> Int {
        switch window.limitWindowSeconds {
        case 5 * 60 * 60:
            return 0
        case 7 * 24 * 60 * 60:
            return 1
        default:
            return 10
        }
    }

    private func providerKeyUsageWindowTitle(_ window: ProviderKeyUsageWindow) -> String {
        switch window.limitWindowSeconds {
        case 5 * 60 * 60:
            return "5 小时额度"
        case 7 * 24 * 60 * 60:
            return "7 天额度"
        case let seconds where seconds >= 24 * 60 * 60:
            let days = max(1, Int((Double(seconds) / Double(24 * 60 * 60)).rounded()))
            return "\(days) 天额度"
        case let seconds where seconds >= 60 * 60:
            let hours = max(1, Int((Double(seconds) / Double(60 * 60)).rounded()))
            return "\(hours) 小时额度"
        default:
            let label = window.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? "额度窗口" : label
        }
    }

    private func providerKeyUsageWindowPercent(_ window: ProviderKeyUsageWindow) -> Double {
        let percent = window.usedPercent > 0
            ? window.usedPercent
            : Double(max(0, min(10_000, window.usedBasisPoints))) / 100.0
        return max(0, min(100, percent))
    }

    private func providerKeyUsageWindowPercentText(_ window: ProviderKeyUsageWindow) -> String {
        String(format: "%.1f%%", providerKeyUsageWindowPercent(window))
    }

    private func providerKeyUsageWindowResetText(_ window: ProviderKeyUsageWindow) -> String {
        guard window.resetAtMs > 0 else { return "" }
        return "重置 \(formattedDrawerTime(window.resetAtMs))"
    }

    private func providerKeyUsageWindowTint(_ window: ProviderKeyUsageWindow) -> Color {
        if window.limited {
            return .red
        }
        switch providerKeyUsageWindowPercent(window) {
        case let value where value >= 95:
            return .red
        case let value where value >= 80:
            return .orange
        case let value where value >= 45:
            return .yellow
        default:
            return .green
        }
    }

    private static func sortedRemoteModels(_ models: [RemoteModelEntry]) -> [RemoteModelEntry] {
        RemoteModelPresentationSupport.sorted(models)
    }

    private func refreshLocalModelSnapshot() {
        localModelSnapshot = ModelsDrawerLocalModelSnapshot.build(from: modelStore.snapshot.models)
        rebuildDrawerDerivedSnapshots()
    }

    private func refreshRemoteDrawerGroups() {
        remoteDrawerGroupSnapshot = remoteDrawerGroups(from: remoteModels)
        rebuildDrawerDerivedSnapshots()
    }

    private func reloadRemoteModels(initial: Bool = false) {
        remoteModelsReloadTask?.cancel()
        remoteModelsReloadTask = Task { @MainActor in
            let loaded = await Task.detached(priority: .userInitiated) {
                RemoteModelPresentationSupport.sorted(RemoteModelStorage.load().models)
            }.value
            guard !Task.isCancelled else { return }
            remoteModels = loaded
            let groups = remoteDrawerGroups(from: loaded)
            remoteDrawerGroupSnapshot = groups
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
            let loaded = await Task.detached(priority: .userInitiated) {
                RemoteProviderKeyBootstrapper.bootstrapIfNeeded()
                return ModelsDrawerProviderKeySnapshot.build(from: ProviderKeyStorage.load())
            }.value
            guard !Task.isCancelled else { return }
            providerKeySnapshot = loaded
            rebuildDrawerDerivedSnapshots()
            providerKeyReloadTask = nil
        }
    }

    private func rebuildDrawerDerivedSnapshots() {
        resourcePoolSnapshot = resourcePoolSummaries
        libraryItemSnapshot = libraryItems
        routeMatrixRowSnapshot = routeMatrixRows
    }

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String) -> some View {
        ModelsDrawerSectionHeader(title: title, subtitle: subtitle)
    }

    private func formattedDrawerTime(_ timestampMs: Int64) -> String {
        guard timestampMs > 0 else { return "未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0))
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

    private func remoteDrawerGroups(from models: [RemoteModelEntry]) -> [RemoteDrawerGroup] {
        RemoteModelPresentationSupport.groups(
            from: models,
            healthSnapshot: store.remoteKeyHealthSnapshot
        ).map { group in
            let drawerModels = group.models.map(Self.remoteDrawerModel(for:))
            return RemoteDrawerGroup(
                id: group.id,
                keyReference: group.keyReference,
                title: group.title,
                summary: remoteGroupSummary(group),
                detail: group.detail,
                statusText: remoteGroupStatusText(group),
                statusColor: remoteGroupStatusColor(group),
                availableCount: group.availableCount,
                needsSetupCount: group.needsSetupCount,
                enabledModelIDs: group.enabledModelIDs,
                loadableModelIDs: group.loadableModelIDs,
                models: drawerModels
            )
        }
    }

    private func remoteGroupSummary(_ group: RemoteModelGroupPlan) -> String {
        var parts = ["\(group.models.count) models"]
        if group.loadedCount > 0 {
            parts.append("\(group.loadedCount) loaded")
        }
        if group.availableCount > 0 {
            parts.append("\(group.availableCount) available")
        }
        if group.needsSetupCount > 0 {
            parts.append("\(group.needsSetupCount) needs setup")
        }
        return parts.joined(separator: " · ")
    }

    private func remoteGroupStatusText(_ group: RemoteModelGroupPlan) -> String {
        if group.loadedCount == group.models.count {
            return "Loaded"
        }
        if group.needsSetupCount == group.models.count {
            return "Needs Setup"
        }
        if group.availableCount == group.models.count {
            return "Available"
        }
        return "Mixed"
    }

    private func remoteGroupStatusColor(_ group: RemoteModelGroupPlan) -> Color {
        if group.loadedCount == group.models.count {
            return .green
        }
        if group.needsSetupCount == group.models.count {
            return .orange
        }
        return .secondary
    }

    private static func remoteDrawerModel(for entry: RemoteModelEntry) -> RemoteDrawerModel {
        let loadState = RemoteModelPresentationSupport.state(for: entry)
        let canLoad = loadState == .available
        let isLoaded = loadState == .loaded
        let statusText: String
        let statusColor: Color
        switch loadState {
        case .loaded:
            statusText = "Loaded"
            statusColor = .green
        case .available:
            statusText = "Available"
            statusColor = .secondary
        case .needsSetup:
            statusText = "Needs Setup"
            statusColor = .orange
        }

        return RemoteDrawerModel(
            entry: entry,
            title: entry.nestedDisplayName,
            subtitle: remoteModelSubtitle(for: entry),
            detail: remoteModelDetail(for: entry),
            statusText: statusText,
            statusColor: statusColor,
            isLoaded: isLoaded,
            canLoad: canLoad
        )
    }

    private static func remoteUpstreamTitle(for entry: RemoteModelEntry) -> String {
        entry.effectiveProviderModelID
    }

    private static func remoteModelSubtitle(for entry: RemoteModelEntry) -> String {
        let backend = RemoteModelPresentationSupport.backendLabel(for: entry)
        let context = remoteContextSummary(for: entry)
        return "\(entry.id) · \(backend) · \(context)"
    }

    private static func remoteModelDetail(for entry: RemoteModelEntry) -> String? {
        var parts: [String] = []

        if let host = RemoteModelPresentationSupport.endpointHost(for: entry), !host.isEmpty {
            parts.append(host)
        }

        let keyReference = RemoteModelStorage.keyReference(for: entry)
        if !keyReference.isEmpty {
            parts.append("Key \(keyReference)")
        }

        let note = (entry.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            parts.append(note)
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private static func remoteContextSummary(for entry: RemoteModelEntry) -> String {
        let configured = max(512, entry.contextLength)
        if let known = entry.knownContextLength, known > configured {
            return "ctx \(configured) / max \(known)"
        }
        return "ctx \(configured)"
    }
}

private struct RemoteDrawerGroup: Identifiable {
    let id: String
    let keyReference: String
    let title: String
    let summary: String
    let detail: String?
    let statusText: String
    let statusColor: Color
    let availableCount: Int
    let needsSetupCount: Int
    let enabledModelIDs: [String]
    let loadableModelIDs: [String]
    let models: [RemoteDrawerModel]

    var loadedCount: Int {
        models.filter(\.isLoaded).count
    }
}

private struct RemoteDrawerModel: Identifiable {
    let entry: RemoteModelEntry
    let title: String
    let subtitle: String
    let detail: String?
    let statusText: String
    let statusColor: Color
    let isLoaded: Bool
    let canLoad: Bool

    var id: String { entry.id }
}
