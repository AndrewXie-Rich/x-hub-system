import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    var providerKeySection: some View {
        let snapshot = providerKeySectionSnapshot
        let keyPools = snapshot.keyPools
        let users = snapshot.users
        let focusedUser = snapshot.focusedUser
        let vendorSummaries = snapshot.vendorSummaries
        let filteredVendors = snapshot.filteredVendors
        let filteredFamilies = snapshot.filteredFamilies
        let filteredUsers = snapshot.filteredUsers
        let filteredConsumers = snapshot.filteredConsumers
        let focusedVendor = snapshot.focusedVendor
        let flowChains = snapshot.flowChains
        let scopeOverview = snapshot.scopeOverview
        let riskVendorCount = snapshot.riskVendorCount
        let riskFamilyCount = snapshot.riskFamilyCount
        let overallTrendCard = snapshot.overallTrendCard
        let vendorTrendCards = snapshot.vendorTrendCards
        let familyTrendCards = snapshot.familyTrendCards
        let userTrendCards = snapshot.userTrendCards
        let consumerTrendCards = snapshot.consumerTrendCards
        let operationalTint = snapshot.operationalTint

        return Section(HubUIStrings.Settings.ProviderKeys.sectionTitle) {
            HStack {
                Text(HubUIStrings.Settings.ProviderKeys.title)
                Spacer()
                Button(HubUIStrings.Settings.ProviderKeys.refresh) {
                    reloadProviderKeySnapshot()
                }
            }

            if !remoteQuotaActionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                terminalAccessFeedbackBanner(
                    text: remoteQuotaActionText,
                    tint: .blue,
                    systemName: "slider.horizontal.3"
                )
            }

            if !remoteQuotaErrorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                terminalAccessFeedbackBanner(
                    text: remoteQuotaErrorText,
                    tint: .red,
                    systemName: "exclamationmark.triangle"
                )
            }

            settingsInlineDisclosureGroup(
                systemName: "person.badge.key.fill",
                title: "CLIProxy OAuth",
                summary: cliproxyOAuthDisclosureSummaryText,
                badge: providerOAuthExpanded ? "已展开" : cliproxyOAuthStatusBadgeText,
                tint: cliproxyOAuthOverviewNoticeTint,
                isExpanded: $providerOAuthExpanded
            ) {
                cliproxyOAuthSourceCard
            }

            if !providerKeySnapshot.importSources.isEmpty {
                settingsInlineDisclosureGroup(
                    systemName: "tray.and.arrow.down.fill",
                    title: "导入源",
                    summary: providerKeyImportSourcesSummaryText(providerKeySnapshot.importSources),
                    badge: providerImportSourcesExpanded ? "已展开" : "按需查看",
                    tint: .teal,
                    isExpanded: $providerImportSourcesExpanded
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(providerKeySnapshot.importSources) { source in
                            providerKeyImportSourceRow(source)
                        }
                    }
                }
            }

            if keyPools.isEmpty && providerKeySnapshot.importSources.isEmpty {
                Text(HubUIStrings.Settings.ProviderKeys.empty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                settingsOperationsPanelCard(
                    systemName: "shippingbox.and.arrow.forward",
                    title: "配额运营总览",
                    summary: providerKeyOperationalSummaryText(
                        scopeOverview: scopeOverview,
                        overview: snapshot.overview,
                        focusedUser: focusedUser,
                        focusedVendor: focusedVendor
                    ),
                    badge: providerKeyOperationalBadgeText(
                        focusedUser: focusedUser,
                        focusedVendor: focusedVendor
                    ),
                    tint: operationalTint
                ) {
                    HStack {
                        Text(HubUIStrings.Settings.ProviderKeys.globalStrategy)
                            .font(.caption)
                        Spacer()
                        Text(providerKeySnapshot.globalRoutingStrategy)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    providerKeyOverviewGrid(snapshot.overview, scopeOverview: scopeOverview)

                    providerKeyScopeControlCard(users: users, vendors: vendorSummaries)

                    terminalAccessFeedbackBanner(
                        text: providerKeyScopeSummary(
                            focusedUser: focusedUser,
                            focusedVendor: focusedVendor,
                            vendors: filteredVendors,
                            families: filteredFamilies,
                            users: filteredUsers,
                            consumers: filteredConsumers
                        ),
                        tint: focusedVendor != nil ? .indigo : (focusedUser == nil ? .blue : .teal),
                        systemName: focusedVendor != nil ? "building.2.crop.circle" : (focusedUser == nil ? "square.grid.2x2" : "person.crop.circle")
                    )

                    if riskVendorCount > 0 || riskFamilyCount > 0 {
                        terminalAccessFeedbackBanner(
                            text: "当前视角下 \(riskVendorCount) 家厂家、\(riskFamilyCount) 个家族存在明显风险，重点看超配、库存缓冲不足或 key 阻塞。",
                            tint: riskFamilyCount > 0 ? .red : .orange,
                            systemName: "exclamationmark.octagon"
                        )
                    }
                }

                settingsInlineDisclosureGroup(
                    systemName: "point.3.connected.trianglepath.dotted",
                    title: "配额流向地图",
                    summary: providerFlowExpanded
                        ? providerKeyFlowSummaryText(
                            flowChains: flowChains,
                            focusedUser: focusedUser,
                            focusedVendor: focusedVendor
                        )
                        : "按需展开后再计算厂家 -> 用户 -> consumer 的真实链路。",
                    badge: providerFlowExpanded
                        ? "已展开"
                        : "按需查看",
                    tint: focusedVendor != nil ? .indigo : (focusedUser != nil ? .teal : .blue),
                    isExpanded: $providerFlowExpanded
                ) {
                    providerKeyFlowSection(
                        flowChains: flowChains,
                        focusedUser: focusedUser,
                        focusedVendor: focusedVendor
                    )
                }

                settingsInlineDisclosureGroup(
                    systemName: "chart.line.uptrend.xyaxis",
                    title: "近 1 小时趋势",
                    summary: providerTrendExpanded
                        ? providerKeyTrendSummaryText(
                            focusedUser: focusedUser,
                            focusedVendor: focusedVendor,
                            overallTrendCard: overallTrendCard,
                            vendorTrendCards: vendorTrendCards,
                            familyTrendCards: familyTrendCards,
                            userTrendCards: userTrendCards,
                            consumerTrendCards: consumerTrendCards
                        )
                        : "按需展开后再生成 5m token 趋势图。",
                    badge: providerTrendExpanded
                        ? "已展开"
                        : "按需查看",
                    tint: focusedVendor != nil ? .orange : (focusedUser != nil ? .teal : .purple),
                    isExpanded: $providerTrendExpanded
                ) {
                    providerKeyTrendSection(
                        focusedUser: focusedUser,
                        focusedVendor: focusedVendor,
                        overallTrendCard: overallTrendCard,
                        vendorTrendCards: vendorTrendCards,
                        familyTrendCards: familyTrendCards,
                        userTrendCards: userTrendCards,
                        consumerTrendCards: consumerTrendCards
                    )
                }

                if !vendorSummaries.isEmpty {
                    settingsInlineDisclosureGroup(
                        systemName: "building.2.crop.circle.fill",
                        title: "厂家经营总账",
                        summary: providerKeyVendorLedgerSummaryText(
                            filteredVendors,
                            focusedUser: focusedUser,
                            focusedVendor: focusedVendor
                        ),
                        badge: providerVendorLedgerExpanded ? "已展开" : "\(filteredVendors.count)/\(vendorSummaries.count) 厂家",
                        tint: focusedVendor != nil ? .indigo : .blue,
                        isExpanded: $providerVendorLedgerExpanded
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            providerKeyLedgerSectionHeader(
                                title: "厂家经营总账",
                                summary: focusedUser == nil
                                    ? "按厂家同时看上游库存、下游覆盖预算、今日家族用量和影响用户数。这里回答哪家还能继续发额度，哪家已经快顶住了。"
                                    : "当前只显示与 \(focusedUser?.displayName ?? "") 相关的厂家。上游库存和 key 健康仍按厂家全局账展示，但覆盖预算与今日家族用量已经按该用户真实重算。"
                            )

                            Picker("厂家过滤", selection: $remoteQuotaVendorFilter) {
                                ForEach(RemoteQuotaVendorFilter.allCases) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(
                                providerKeyVendorFilterSummary(
                                    filteredVendors,
                                    totalVendors: vendorSummaries.count,
                                    focusedUser: focusedUser,
                                    focusedVendor: focusedVendor
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                            if filteredVendors.isEmpty {
                                Text("当前视角下没有匹配的厂家。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(filteredVendors) { vendor in
                                    self.providerKeyVendorHeatCard(vendor)
                                }
                            }
                        }
                    }
                }

                if snapshot.totalFamilyCount > 0 {
                    settingsInlineDisclosureGroup(
                        systemName: "shippingbox.circle.fill",
                        title: "库存总账",
                        summary: providerKeyFamilyLedgerSummaryText(
                            filteredFamilies,
                            focusedUser: focusedUser
                        ),
                        badge: providerFamilyLedgerExpanded ? "已展开" : "\(filteredFamilies.count)/\(snapshot.totalFamilyCount) 家族",
                        tint: focusedUser != nil ? .teal : .purple,
                        isExpanded: $providerFamilyLedgerExpanded
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            providerKeyLedgerSectionHeader(
                                title: "库存总账",
                                summary: focusedUser == nil
                                    ? "先按模型家族看上游库存、覆盖预算和今日实际用量。这里回答每家模型现在还剩多少库存。"
                                    : "当前只显示 \(focusedUser?.displayName ?? "") 可命中的家族。上游库存仍是家族全局池，但覆盖预算与今日用量已经按该用户真实重算。"
                            )

                            if filteredFamilies.isEmpty {
                                Text("当前视角下没有匹配的模型家族。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(filteredFamilies) { family in
                                    providerKeyQuotaFamilyCard(family)
                                }
                            }
                        }
                    }
                }

                settingsInlineDisclosureGroup(
                    systemName: "person.3.sequence.fill",
                    title: "用户台账",
                    summary: providerKeyUserLedgerDisclosureSummary(
                        filteredUsers,
                        totalUsers: users.count,
                        focusedUser: focusedUser
                    ),
                    badge: providerUserLedgerExpanded ? "已展开" : "\(filteredUsers.count)/\(users.count) 用户",
                    tint: focusedUser != nil ? .teal : .indigo,
                    isExpanded: $providerUserLedgerExpanded
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        providerKeyLedgerSectionHeader(
                            title: "用户台账",
                            summary: "这里按 user_id 汇总预算、用量和剩余；如果终端没绑 user_id，会按单个 consumer 单独记账，避免不同终端混账。"
                        )

                        if users.isEmpty {
                            Text("当前还没有任何用户获得远端付费模型预算。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("用户过滤", selection: $remoteQuotaUserFilter) {
                                ForEach(RemoteQuotaUserFilter.allCases) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(
                                providerKeyUserFilterSummary(
                                    filteredUsers,
                                    totalUsers: users.count,
                                    focusedUser: focusedUser
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                            if filteredUsers.isEmpty {
                                Text("当前视角下没有匹配的用户主体。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(filteredUsers) { user in
                                        providerKeyBudgetUserRow(user)
                                    }
                                }
                            }
                        }
                    }
                }
                .id(providerKeyUserLedgerAnchorID)

                settingsInlineDisclosureGroup(
                    systemName: "rectangle.3.group.bubble.left.fill",
                    title: "统一消费者台账",
                    summary: providerKeyConsumerLedgerDisclosureSummary(
                        filteredConsumers,
                        totalConsumers: snapshot.consumerLedgerTotalCount,
                        focusedUser: focusedUser
                    ),
                    badge: providerConsumerLedgerExpanded
                        ? "已展开"
                        : "\(filteredConsumers.count)/\(snapshot.consumerLedgerTotalCount) 消费者",
                    tint: focusedUser != nil ? .blue : .purple,
                    isExpanded: $providerConsumerLedgerExpanded
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        providerKeyLedgerSectionHeader(
                            title: "统一消费者台账",
                            summary: "把 XT 和普通 terminal access key 放在同一张账上，看每个用户下面每个 consumer 具体拿了多少预算、用了多少、还剩多少。"
                        )

                        if snapshot.totalConsumerCount == 0 {
                            Text("当前还没有任何 XT 或普通 terminal access key 获得远端付费模型预算。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("消费者过滤", selection: $remoteQuotaConsumerFilter) {
                                ForEach(RemoteQuotaConsumerFilter.allCases) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(
                                providerKeyConsumerFilterSummary(
                                    filteredConsumers,
                                    totalConsumers: snapshot.consumerLedgerTotalCount,
                                    focusedUser: focusedUser
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                            if filteredConsumers.isEmpty {
                                Text("当前视角下没有匹配的消费者。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(filteredConsumers) { client in
                                        providerKeyBudgetClientRow(client)
                                    }
                                }
                            }
                        }
                    }
                }
                .id(providerKeyConsumerLedgerAnchorID)

                if keyPools.isEmpty {
                    Text("当前还没有可路由的 Provider 账号，先修复上面的导入源即可。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    settingsInlineDisclosureGroup(
                        systemName: "key.radiowaves.forward.fill",
                        title: "物理 Key 池",
                        summary: providerKeyPhysicalPoolsSummaryText(keyPools),
                        badge: providerPhysicalPoolsExpanded ? "已展开" : "\(keyPools.count) 个池",
                        tint: .orange,
                        isExpanded: $providerPhysicalPoolsExpanded
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            providerKeyLedgerSectionHeader(
                                title: "物理 Key 池",
                                summary: focusedUser == nil
                                    ? "当你需要下钻到具体厂商 key 时，在这里看每个池子和每把 key 的健康、额度、冷却与重试。"
                                    : "物理 Key 池保持全局视角，方便你在按用户观察预算时，仍能直接回到具体厂商 key 排障。"
                            )

                            ForEach(keyPools) { pool in
                                providerKeyPoolCard(pool)
                            }
                        }
                    }

                    Text(
                        "共 \(snapshot.overview.quotaPoolCount) 个额度池 · \(keyPools.count) 个物理池 · \(providerKeyDerivedSnapshot.totalAccounts) 个 key · "
                            + "\(providerKeyDerivedSnapshot.readyAccounts) 个就绪 · "
                            + "\(providerKeyDerivedSnapshot.cooldownAccounts) 个冷却 · "
                            + "\(providerKeyDerivedSnapshot.blockedAccounts) 个阻塞"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .id(providerKeySectionAnchorID)
    }
}
