import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    func providerKeyOverviewGrid(
        _ overview: RemoteQuotaCenterOverview,
        scopeOverview: ProviderKeyScopeOverview
    ) -> some View {
        let upstreamUsage = providerKeyUsageFraction(
            used: overview.totalDailyTokensUsed,
            cap: overview.totalDailyTokenCap
        )
        let upstreamTint: Color = upstreamUsage >= 0.85 ? .orange : .blue
        let allocatedTint: Color = scopeOverview.allocatedDailyTokenBudget > 0 ? .purple : .gray
        let observedTint: Color = scopeOverview.observedConsumerTokensUsed > 0 ? .teal : .gray
        let downstreamRemaining = max(Int64(0), scopeOverview.allocatedDailyTokenBudget - scopeOverview.observedConsumerTokensUsed)
        let downstreamRemainingTint: Color = scopeOverview.allocatedDailyTokenBudget > 0
            ? (downstreamRemaining <= max(Int64(50_000), scopeOverview.allocatedDailyTokenBudget / 10) ? .orange : .green)
            : .gray
        let allocationHeadroom = overview.totalDailyTokenCap > 0
            ? overview.totalDailyTokenCap - scopeOverview.allocatedDailyTokenBudget
            : 0
        let riskTint: Color = scopeOverview.oversubscribedFamilyCount > 0
            ? .red
            : (overview.blockedKeys > 0 ? .orange : .green)
        let downstreamRemainingValue: String = {
            guard scopeOverview.allocatedDailyTokenBudget > 0 else {
                return scopeOverview.unlimitedBudgetConsumerCount > 0 ? "弹性" : "0"
            }
            let base = HubUIStrings.Settings.ProviderKeys.tokenCount(downstreamRemaining)
            return scopeOverview.unlimitedBudgetConsumerCount > 0 ? "\(base) +" : base
        }()
        let unlimitedBudgetSuffix = scopeOverview.unlimitedBudgetConsumerCount > 0
            ? " · 未设上限 \(scopeOverview.unlimitedBudgetConsumerCount)"
            : ""

        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 150), spacing: 8, alignment: .top),
                GridItem(.flexible(minimum: 150), spacing: 8, alignment: .top),
                GridItem(.flexible(minimum: 150), spacing: 8, alignment: .top)
            ],
            spacing: 8
        ) {
            providerKeyOverviewCard(
                title: "上游剩余库存",
                value: overview.totalDailyTokenCap > 0
                    ? HubUIStrings.Settings.ProviderKeys.tokenCount(overview.totalDailyTokensRemaining)
                    : HubUIStrings.Settings.ProviderKeys.tokenCount(overview.totalDailyTokensUsed),
                detail: overview.totalDailyTokenCap > 0
                    ? "今日已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(overview.totalDailyTokensUsed)) / \(HubUIStrings.Settings.ProviderKeys.tokenCount(overview.totalDailyTokenCap))"
                    : "尚未拿到统一 cap，已识别额度 \(overview.knownQuotaKeys)/\(overview.totalKeys) 个 key",
                tint: upstreamTint
            )

            providerKeyOverviewCard(
                title: "下游已分配",
                value: scopeOverview.allocatedDailyTokenBudget > 0
                    ? HubUIStrings.Settings.ProviderKeys.tokenCount(scopeOverview.allocatedDailyTokenBudget)
                    : "弹性分配",
                detail: scopeOverview.allocatedDailyTokenBudget > 0
                    ? (
                        {
                            if let focusedUser = scopeOverview.focusedUser,
                               let focusedVendor = scopeOverview.focusedVendorDisplayName {
                                return "\(focusedUser.displayName) 在 \(focusedVendor) 视角下的覆盖预算\(unlimitedBudgetSuffix)"
                            }
                            if let focusedVendor = scopeOverview.focusedVendorDisplayName {
                                return "\(focusedVendor) 相关固定 daily budget 合计\(unlimitedBudgetSuffix)"
                            }
                            if let focusedUser = scopeOverview.focusedUser {
                                return "\(focusedUser.displayName) 当前覆盖预算\(unlimitedBudgetSuffix)"
                            }
                            return "当前全局固定 daily budget 合计\(unlimitedBudgetSuffix)"
                        }()
                    )
                    : (scopeOverview.unlimitedBudgetConsumerCount > 0 ? "当前视角主要受上游库存约束" : "当前主要受上游库存约束"),
                tint: allocatedTint
            )

            providerKeyOverviewCard(
                title: "下游今日已用",
                value: HubUIStrings.Settings.ProviderKeys.tokenCount(scopeOverview.observedConsumerTokensUsed),
                detail: overview.totalDailyTokensUsed > 0
                    ? (
                        {
                            if let focusedUser = scopeOverview.focusedUser,
                               let focusedVendor = scopeOverview.focusedVendorDisplayName {
                                return "\(focusedUser.displayName) 在 \(focusedVendor) 视角下已用，对比上游总账 \(HubUIStrings.Settings.ProviderKeys.tokenCount(overview.totalDailyTokensUsed))"
                            }
                            if let focusedVendor = scopeOverview.focusedVendorDisplayName {
                                return "\(focusedVendor) 相关下游已用，对比上游总账 \(HubUIStrings.Settings.ProviderKeys.tokenCount(overview.totalDailyTokensUsed))"
                            }
                            if scopeOverview.focusedUser == nil {
                                return "上游账本已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(overview.totalDailyTokensUsed))"
                            }
                            return "当前用户已用，对比上游总账 \(HubUIStrings.Settings.ProviderKeys.tokenCount(overview.totalDailyTokensUsed))"
                        }()
                    )
                    : "来自 XT / Terminal 消费者账本",
                tint: observedTint
            )

            providerKeyOverviewCard(
                title: "下游剩余预算",
                value: downstreamRemainingValue,
                detail: scopeOverview.allocatedDailyTokenBudget > 0
                    ? (
                        scopeOverview.unlimitedBudgetConsumerCount > 0
                            ? "固定预算剩余 + 弹性额度"
                            : "按当前视角的已分配预算减去今日已用"
                    )
                    : "无固定 hard cap",
                tint: downstreamRemainingTint
            )

            providerKeyOverviewCard(
                title: "覆盖主体",
                value: "\(scopeOverview.userCount) 用户 / \(scopeOverview.consumerCount) 消费者",
                detail: "XT \(scopeOverview.xtConsumerCount) · Terminal \(scopeOverview.terminalConsumerCount) · 在线 \(scopeOverview.connectedConsumerCount)",
                tint: .indigo
            )

            providerKeyOverviewCard(
                title: "风险态势",
                value: overview.totalDailyTokenCap > 0
                    ? providerKeySignedTokenCount(allocationHeadroom)
                    : "\(scopeOverview.oversubscribedFamilyCount) 个家族风险",
                detail: scopeOverview.allocatedDailyTokenBudget > 0
                    ? "当前视角缓冲 · 超配家族 \(scopeOverview.oversubscribedFamilyCount) · 阻塞 key \(overview.blockedKeys)"
                    : "家族池 \(overview.quotaPoolCount) · 物理池 \(overview.keyPoolCount) · Ready key \(overview.readyKeys)",
                tint: riskTint
            )
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    func providerKeyScopeControlCard(
        users: [RemoteQuotaCenterUserProjection],
        vendors: [ProviderKeyVendorInventorySummary]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("运营视角")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("可叠加用户视角和厂家视角。切到某个厂家后，趋势、家族、用户和消费者台账会一起收窄到相关流量；物理 key 池仍保持全局。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Picker("用户视角", selection: $remoteQuotaFocusedUserGroupingKey) {
                        Text("全局用户").tag("")
                        ForEach(users) { user in
                            Text(providerKeyFocusUserTitle(user)).tag(user.groupingKey)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(users.isEmpty)

                    Picker("厂家视角", selection: $remoteQuotaFocusedVendorKey) {
                        Text("全部厂家").tag("")
                        ForEach(vendors) { vendor in
                            Text(providerKeyFocusVendorTitle(vendor))
                                .tag(providerKeyCanonicalVendorKey(vendor.vendorKey))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(vendors.isEmpty)
                    .onChange(of: remoteQuotaFocusedVendorKey) { newValue in
                        let normalized = providerKeyCanonicalVendorKey(newValue)
                        guard !normalized.isEmpty else {
                            highlightedProviderKeyVendorKey = nil
                            return
                        }
                        highlightedProviderKeyVendorKey = normalized
                        if let focusedVendor = providerKeyFocusedVendor(vendors) {
                            expandedProviderKeyVendorIDs.insert(focusedVendor.id)
                        }
                    }

                    if !remoteQuotaFocusedUserGroupingKey.isEmpty || providerKeyHasFocusedVendor {
                        Button("清除视角") {
                            remoteQuotaFocusedUserGroupingKey = ""
                            remoteQuotaFocusedVendorKey = ""
                            highlightedProviderKeyVendorKey = nil
                        }
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                    }
                }
            }

            if providerKeyFocusedUser(users) != nil || providerKeyHasFocusedVendor {
                HStack(spacing: 8) {
                    if let focusedUser = providerKeyFocusedUser(users) {
                        Text("当前用户")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(providerKeyFocusUserTitle(focusedUser))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.teal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.teal.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    if let focusedVendor = providerKeyFocusedVendor(vendors) {
                        Text("当前厂家")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(providerKeyFocusVendorTitle(focusedVendor))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.indigo.opacity(0.12))
                            .clipShape(Capsule())
                    } else if providerKeyHasFocusedVendor {
                        Text("当前厂家")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(providerKeyVendorDisplayName(providerKeyNormalizedFocusedVendorKey))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.indigo.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.blue.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.blue.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func providerKeyOverviewCard(
        title: String,
        value: String,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.14),
                            tint.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
