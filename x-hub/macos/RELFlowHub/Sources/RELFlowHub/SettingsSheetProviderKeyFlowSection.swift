import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    func providerKeyFlowSection(
        flowChains: [ProviderKeyFlowChainSummary],
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            providerKeyLedgerSectionHeader(
                title: "配额流向地图",
                summary: {
                    if let focusedVendor, let focusedUser {
                        return "把 \(focusedVendor.displayName) 的上游库存、\(focusedUser.displayName) 的用户预算，以及它下面的终端 consumer 放在同一张链路图里。"
                    }
                    if let focusedVendor {
                        return "直接看 \(focusedVendor.displayName) 的库存主要流向了哪些用户和终端，便于判断还能继续发给谁。"
                    }
                    if let focusedUser {
                        return "直接看 \(focusedUser.displayName) 当前把预算拆给了哪些 XT / Terminal，以及这些 consumer 主要命中了哪些厂家。"
                    }
                    return "把上游厂家库存、下游用户预算和最终 consumer 放在同一张关系图里，回答额度现在流向了谁、谁还剩多少。"
                }()
            )

            if flowChains.isEmpty {
                Text("当前还没有足够清晰的厂家-用户-consumer 链路。先给 XT 或普通 terminal 挂上远端额度，或等产生一点真实用量后这里会更直观。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 280), spacing: 10, alignment: .top),
                        GridItem(.flexible(minimum: 280), spacing: 10, alignment: .top),
                    ],
                    spacing: 10
                ) {
                    ForEach(flowChains) { chain in
                        providerKeyFlowChainCard(chain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func providerKeyFlowChainCard(
        _ chain: ProviderKeyFlowChainSummary
    ) -> some View {
        let vendorUsageFraction = providerKeyUsageFraction(
            used: chain.vendor.totalDailyTokensUsed,
            cap: chain.vendor.totalDailyTokenCap
        )
        let vendorTint = providerKeyUsageHeatTint(
            fraction: vendorUsageFraction,
            hasBlockingRisk: chain.vendor.blockedAccounts > 0
        )
        let userTint = providerKeyUserAtRisk(chain.user) ? Color.orange : providerKeyUserTint(chain.user)
        let consumerTint = providerKeyConsumerAtRisk(chain.consumer) ? Color.orange : providerKeyConsumerKindColor(chain.consumer.consumerKind)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(chain.vendor.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Text(chain.linkKind.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(chain.linkKind.tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(chain.linkKind.tint.opacity(0.12))
                    .clipShape(Capsule())

                if providerKeyVendorAtRisk(chain.vendor) || providerKeyUserAtRisk(chain.user) || providerKeyConsumerAtRisk(chain.consumer) {
                    Text("需关注")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 6)

                Text("命中已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(chain.vendorObservedDailyTokensUsed))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(vendorTint)
            }

            providerKeyFlowNodeRow(
                title: "上游厂家",
                name: chain.vendor.displayName,
                detail: chain.vendor.totalDailyTokenCap > 0
                    ? "库存剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(chain.vendor.totalDailyTokensRemaining)) / \(HubUIStrings.Settings.ProviderKeys.tokenCount(chain.vendor.totalDailyTokenCap)) · 覆盖预算 \(HubUIStrings.Settings.ProviderKeys.tokenCount(chain.vendor.assignedDailyTokenBudget))"
                    : "已观测今日已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(chain.vendor.totalDailyTokensUsed)) · \(chain.vendor.poolCount) 个池 / \(chain.vendor.totalAccounts) 把 key",
                tint: vendorTint,
                systemName: "shippingbox.fill"
            )

            providerKeyFlowArrow(tint: vendorTint)

            providerKeyFlowNodeRow(
                title: "用户预算",
                name: chain.user.displayName,
                detail: "总剩余 \(providerKeyUserRemainingBudgetPreviewText(chain.user)) · 今日已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(chain.user.observedDailyTokensUsed)) · \(chain.user.consumerCount) 个 consumer",
                tint: userTint,
                systemName: chain.user.isStandaloneConsumer ? "person.crop.circle.badge.questionmark" : "person.crop.circle.fill"
            )

            providerKeyFlowArrow(tint: userTint)

            providerKeyFlowNodeRow(
                title: chain.consumer.kindTitle,
                name: chain.consumer.name,
                detail: chain.consumer.dailyTokenLimit > 0
                    ? "剩余 \(providerKeyConsumerRemainingBudgetPreviewText(chain.consumer)) · 今日已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(chain.consumer.dailyTokenUsed)) · 预算 \(HubUIStrings.Settings.ProviderKeys.tokenCount(chain.consumer.dailyTokenLimit))"
                    : "弹性预算 · 今日已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(chain.consumer.dailyTokenUsed)) · 主要受上游库存约束",
                tint: consumerTint,
                systemName: chain.consumer.isTerminalAccess ? "terminal.fill" : "display.2"
            )

            HStack(spacing: 6) {
                providerKeyVendorSpotlightMetric("命中家族 \(chain.matchedFamilyCount) 个", tint: chain.linkKind.tint)
                providerKeyVendorSpotlightMetric(
                    chain.consumer.connected ? "在线" : "未在线",
                    tint: chain.consumer.connected ? .green : .gray
                )
                if chain.vendor.hotPoolCount > 0 {
                    providerKeyVendorSpotlightMetric("\(chain.vendor.hotPoolCount) 个热点池", tint: .orange)
                }
            }

            let activitySummary = providerKeyBudgetClientActivitySummary(chain.consumer)
            if !activitySummary.isEmpty {
                Text(activitySummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("锁定链路") {
                    focusProviderKeyVendorUser(chain.user, vendor: chain.vendor)
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))

                Button(chain.consumer.managementTitle) {
                    presentRemoteQuotaConsumerManager(chain.consumer)
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            vendorTint.opacity(0.14),
                            chain.linkKind.tint.opacity(0.08),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(vendorTint.opacity(0.20), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func providerKeyFlowNodeRow(
        title: String,
        name: String,
        detail: String,
        tint: Color,
        systemName: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: systemName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func providerKeyFlowArrow(
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(tint.opacity(0.24))
                .frame(width: 2, height: 10)
            Image(systemName: "arrow.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint.opacity(0.8))
            Capsule()
                .fill(tint.opacity(0.24))
                .frame(width: 2, height: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
    }
}
