import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    func providerKeyVendorHeatCard(_ vendor: ProviderKeyVendorInventorySummary) -> some View {
        let canonicalVendorKey = providerKeyCanonicalVendorKey(vendor.vendorKey)
        let isHighlighted = highlightedProviderKeyVendorKey == canonicalVendorKey
        let detailBinding = expansionBinding(vendor.id, in: $expandedProviderKeyVendorIDs)
        let usageFraction = providerKeyUsageFraction(
            used: vendor.totalDailyTokensUsed,
            cap: vendor.totalDailyTokenCap
        )
        let coverageFraction = providerKeyUsageFraction(
            used: vendor.assignedDailyTokenBudget,
            cap: vendor.totalDailyTokenCap
        )
        let usageTint = providerKeyUsageHeatTint(
            fraction: usageFraction,
            hasBlockingRisk: vendor.blockedAccounts > 0
        )
        let coverageTint: Color = vendor.allocationHeadroom < 0
            ? .red
            : (coverageFraction >= 0.85 ? .orange : .purple)
        let readinessFraction = vendor.totalAccounts > 0
            ? Double(vendor.readyAccounts) / Double(max(1, vendor.totalAccounts))
            : 0
        let remainingValue = vendor.totalDailyTokenCap > 0
            ? HubUIStrings.Settings.ProviderKeys.tokenCount(vendor.totalDailyTokensRemaining)
            : HubUIStrings.Settings.ProviderKeys.tokenCount(vendor.totalDailyTokensUsed)
        let headroomTint: Color = {
            guard vendor.totalDailyTokenCap > 0 else { return .gray }
            if vendor.allocationHeadroom < 0 { return .red }
            if vendor.allocationHeadroom <= max(Int64(50_000), vendor.totalDailyTokenCap / 10) { return .orange }
            return .green
        }()

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(vendor.displayName)
                            .font(.callout.weight(.semibold))

                        Text("\(vendor.readyAccounts)/\(vendor.totalAccounts) Ready")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(vendor.blockedAccounts > 0 ? Color.orange : Color.green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background((vendor.blockedAccounts > 0 ? Color.orange : Color.green).opacity(0.12))
                            .clipShape(Capsule())

                        if vendor.hotPoolCount > 0 {
                            Text("\(vendor.hotPoolCount) 热点池")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        if vendor.oversubscribedFamilyCount > 0 {
                            Text("\(vendor.oversubscribedFamilyCount) 超配家族")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    Text(providerKeyVendorSummaryText(vendor))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("库存热度")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(usageFraction > 0 ? "\(Int(usageFraction * 100))%" : "低")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(usageTint)
                }
            }

            HStack(spacing: 8) {
                providerKeyLedgerMetricTile(
                    title: "剩余库存",
                    value: remainingValue,
                    detail: vendor.totalDailyTokenCap > 0
                        ? "今日总上限 \(HubUIStrings.Settings.ProviderKeys.tokenCount(vendor.totalDailyTokenCap))"
                        : "仅统计到今日已用",
                    tint: usageTint
                )
                providerKeyLedgerMetricTile(
                    title: "覆盖预算",
                    value: vendor.assignedDailyTokenBudget > 0
                        ? HubUIStrings.Settings.ProviderKeys.tokenCount(vendor.assignedDailyTokenBudget)
                        : (vendor.coveredConsumerCount > 0 ? "弹性" : "未覆盖"),
                    detail: vendor.coveredUnlimitedConsumerCount > 0
                        ? "\(vendor.coveredConsumerCount) 个 consumer · 弹性 \(vendor.coveredUnlimitedConsumerCount)"
                        : "\(vendor.coveredConsumerCount) 个 consumer",
                    tint: coverageTint
                )
            }

            HStack(spacing: 8) {
                providerKeyLedgerMetricTile(
                    title: "家族今日已用",
                    value: HubUIStrings.Settings.ProviderKeys.tokenCount(vendor.observedFamilyTokensUsed),
                    detail: vendor.totalTokensUsed > 0
                        ? "累计 \(HubUIStrings.Settings.ProviderKeys.tokenCount(vendor.totalTokensUsed))"
                        : "\(vendor.coveredFamilyCount) 个家族账本",
                    tint: .teal
                )
                providerKeyLedgerMetricTile(
                    title: "预算缓冲",
                    value: vendor.totalDailyTokenCap > 0
                        ? providerKeySignedTokenCount(vendor.allocationHeadroom)
                        : "\(vendor.coveredUserCount) 个用户",
                    detail: vendor.totalDailyTokenCap > 0
                        ? "上游 cap - 下游覆盖预算"
                        : "\(vendor.coveredUserCount) 个用户主体 / \(vendor.poolCount) 个池",
                    tint: headroomTint
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("额度热力")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(vendor.totalDailyTokenCap > 0
                        ? "\(HubUIStrings.Settings.ProviderKeys.tokenCount(vendor.totalDailyTokensUsed)) / \(HubUIStrings.Settings.ProviderKeys.tokenCount(vendor.totalDailyTokenCap))"
                        : HubUIStrings.Settings.ProviderKeys.tokenCount(vendor.totalDailyTokensUsed))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                providerKeyHeatStrip(value: usageFraction, tint: usageTint)

                HStack {
                    Text("覆盖压力")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(vendor.totalDailyTokenCap > 0
                        ? "\(HubUIStrings.Settings.ProviderKeys.tokenCount(vendor.assignedDailyTokenBudget)) / \(HubUIStrings.Settings.ProviderKeys.tokenCount(vendor.totalDailyTokenCap))"
                        : (vendor.assignedDailyTokenBudget > 0 ? HubUIStrings.Settings.ProviderKeys.tokenCount(vendor.assignedDailyTokenBudget) : "弹性"))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                providerKeyHeatStrip(value: coverageFraction, tint: coverageTint)

                HStack {
                    Text("可用度")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(vendor.readyAccounts) / \(vendor.totalAccounts)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                providerKeyHeatStrip(value: readinessFraction, tint: vendor.blockedAccounts > 0 ? .orange : .green)
            }

            providerKeyVendorCoverageSpotlights(vendor)

            DisclosureGroup(isExpanded: detailBinding) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("这里继续展开到每个池子 / 每把 key，可直接看剩余额度、下次刷新、恢复时间和失败原因。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if vendor.pools.isEmpty {
                        Text("当前厂家还没有可展示的物理池。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vendor.pools) { pool in
                            providerKeyPoolCard(pool)
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("池子与单 Key 明细")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(providerKeyVendorPoolDisclosureSummary(vendor))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .background(isHighlighted ? usageTint.opacity(0.12) : usageTint.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isHighlighted ? usageTint.opacity(0.52) : usageTint.opacity(0.16),
                    lineWidth: isHighlighted ? 1.6 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .id(providerKeyVendorAnchorID(canonicalVendorKey))
    }

    @ViewBuilder
    private func providerKeyVendorCoverageSpotlights(
        _ vendor: ProviderKeyVendorInventorySummary
    ) -> some View {
        if !vendor.spotlightUsers.isEmpty || !vendor.spotlightConsumers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("下游分配热点")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(vendor.coveredUserCount) 个用户 / \(vendor.coveredConsumerCount) 个 consumer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !vendor.spotlightUsers.isEmpty && !vendor.spotlightConsumers.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        providerKeyVendorUserSpotlightPanel(vendor)
                        providerKeyVendorConsumerSpotlightPanel(vendor)
                    }
                } else if !vendor.spotlightUsers.isEmpty {
                    providerKeyVendorUserSpotlightPanel(vendor)
                } else {
                    providerKeyVendorConsumerSpotlightPanel(vendor)
                }

                Text("锁定用户会把当前厂家与该用户视角叠起来；管理 consumer 可直接去调 XT 或 Terminal 配额。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func providerKeyVendorUserSpotlightPanel(
        _ vendor: ProviderKeyVendorInventorySummary
    ) -> some View {
        let hiddenCount = max(0, vendor.coveredUserCount - vendor.spotlightUsers.count)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("重点用户")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(vendor.spotlightUsers.count) / \(vendor.coveredUserCount)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            ForEach(vendor.spotlightUsers) { spotlight in
                providerKeyVendorUserSpotlightRow(spotlight, vendor: vendor)
            }

            if hiddenCount > 0 {
                Text("另外 \(hiddenCount) 个用户主体在下方用户台账。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.indigo.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func providerKeyVendorUserSpotlightRow(
        _ spotlight: ProviderKeyVendorUserSpotlight,
        vendor: ProviderKeyVendorInventorySummary
    ) -> some View {
        let user = spotlight.user
        let userTint = providerKeyUserAtRisk(user) ? Color.orange : providerKeyUserTint(user)
        let identitySummary = providerKeyBudgetUserIdentitySummary(user)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(user.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(user.groupingKind.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(userTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(userTint.opacity(0.12))
                    .clipShape(Capsule())

                if providerKeyUserAtRisk(user) {
                    Text("预算吃紧")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 6)

                Button("锁定用户") {
                    focusProviderKeyVendorUser(user, vendor: vendor)
                }
                .buttonStyle(.borderless)
                .font(.caption2.weight(.semibold))
            }

            if !identitySummary.isEmpty {
                Text(identitySummary)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 6) {
                providerKeyVendorSpotlightMetric(
                    "命中已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(spotlight.vendorObservedDailyTokensUsed))",
                    tint: .teal
                )
                providerKeyVendorSpotlightMetric(
                    "总剩余 \(providerKeyUserRemainingBudgetPreviewText(user))",
                    tint: providerKeyUserAtRisk(user) ? .orange : .green
                )
                providerKeyVendorSpotlightMetric(
                    "\(user.consumerCount) 个 consumer",
                    tint: userTint
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(userTint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func providerKeyVendorConsumerSpotlightPanel(
        _ vendor: ProviderKeyVendorInventorySummary
    ) -> some View {
        let hiddenCount = max(0, vendor.coveredConsumerCount - vendor.spotlightConsumers.count)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("热点 Consumer")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(vendor.spotlightConsumers.count) / \(vendor.coveredConsumerCount)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            ForEach(vendor.spotlightConsumers) { spotlight in
                providerKeyVendorConsumerSpotlightRow(spotlight)
            }

            if hiddenCount > 0 {
                Text("另外 \(hiddenCount) 个 consumer 在下方统一消费者台账。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.teal.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func providerKeyVendorConsumerSpotlightRow(
        _ spotlight: ProviderKeyVendorConsumerSpotlight
    ) -> some View {
        let consumer = spotlight.consumer
        let consumerTint = providerKeyConsumerAtRisk(consumer) ? Color.orange : providerKeyConsumerKindColor(consumer.consumerKind)
        let referenceSummary = providerKeyBudgetClientReferenceSummary(consumer)
        let activitySummary = providerKeyBudgetClientActivitySummary(consumer)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(consumer.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(consumer.kindTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(consumerTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(consumerTint.opacity(0.12))
                    .clipShape(Capsule())

                if providerKeyConsumerAtRisk(consumer) {
                    Text("逼近上限")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 6)

                Button(consumer.managementTitle) {
                    presentRemoteQuotaConsumerManager(consumer)
                }
                .buttonStyle(.borderless)
                .font(.caption2.weight(.semibold))
            }

            if !referenceSummary.isEmpty {
                Text(referenceSummary)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 6) {
                providerKeyVendorSpotlightMetric(
                    "命中已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(spotlight.vendorObservedDailyTokensUsed))",
                    tint: .teal
                )
                providerKeyVendorSpotlightMetric(
                    consumer.dailyTokenLimit > 0
                        ? "总剩余 \(providerKeyConsumerRemainingBudgetPreviewText(consumer))"
                        : "弹性预算",
                    tint: providerKeyConsumerAtRisk(consumer) ? .orange : .green
                )
                providerKeyVendorSpotlightMetric(
                    consumer.dailyTokenLimit > 0
                        ? "预算 \(HubUIStrings.Settings.ProviderKeys.tokenCount(consumer.dailyTokenLimit))"
                        : "由上游库存约束",
                    tint: consumerTint
                )
            }

            if !activitySummary.isEmpty {
                Text(activitySummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(consumerTint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
