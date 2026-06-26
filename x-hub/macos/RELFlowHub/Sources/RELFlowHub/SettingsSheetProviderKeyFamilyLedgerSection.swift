import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    func providerKeyQuotaFamilyCard(_ family: ProviderKeyFamilyInventorySummary) -> some View {
        let poolTint = providerKeyPoolStateColor(family.quotaPool.state)
        let inventoryValue = family.combinedDailyTokenCap > 0
            ? HubUIStrings.Settings.ProviderKeys.tokenCount(family.combinedDailyTokensRemaining)
            : HubUIStrings.Settings.ProviderKeys.tokenCount(family.combinedDailyTokensUsed)
        let inventoryDetail = family.combinedDailyTokenCap > 0
            ? "剩余 / 上限 \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.combinedDailyTokenCap))"
            : "仅观测到今日已用"
        let assignedValue = family.assignedDailyTokenBudget > 0
            ? HubUIStrings.Settings.ProviderKeys.tokenCount(family.assignedDailyTokenBudget)
            : (family.assignedClientCount > 0 ? "不限" : "未分配")
        let assignedDetail = family.assignedClientCount > 0
            ? (
                family.unlimitedBudgetConsumerCount > 0
                    ? "\(family.coveredUserCount) 个用户 / \(family.assignedClientCount) 个消费者 · 弹性 \(family.unlimitedBudgetConsumerCount)"
                    : "\(family.coveredUserCount) 个用户 / \(family.assignedClientCount) 个消费者"
            )
            : "当前没有消费者"
        let observedDetail = family.connectedAssignedConsumerCount > 0
            ? "在线 \(family.connectedAssignedConsumerCount) 个消费者"
            : "来自当前视角消费账本"

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(family.displayName)
                            .font(.callout.weight(.semibold))

                        Text(providerKeyPoolStateText(family.quotaPool.state))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(poolTint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(poolTint.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(
                        HubUIStrings.Settings.ProviderKeys.familyQuotaPoolSummary(
                            sources: family.quotaPool.totalSources,
                            dedicated: family.quotaPool.dedicatedSources,
                            shared: family.quotaPool.sharedSources,
                            total: family.quotaPool.totalAccounts,
                            ready: family.quotaPool.readyAccounts,
                            cooldown: family.quotaPool.cooldownAccounts,
                            blocked: family.quotaPool.blockedAccounts,
                            stale: family.quotaPool.staleAccounts
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(providerKeyFamilyRetrySummary(family))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 8) {
                providerKeyLedgerMetricTile(
                    title: "上游库存",
                    value: inventoryValue,
                    detail: inventoryDetail,
                    tint: poolTint
                )
                providerKeyLedgerMetricTile(
                    title: "覆盖预算",
                    value: assignedValue,
                    detail: assignedDetail,
                    tint: .purple
                )
                providerKeyLedgerMetricTile(
                    title: "今日用量",
                    value: HubUIStrings.Settings.ProviderKeys.tokenCount(family.observedDailyTokensUsed),
                    detail: observedDetail,
                    tint: .teal
                )
            }

            if family.combinedDailyTokenCap > 0 {
                ProgressView(value: Double(family.combinedDailyTokensUsed), total: Double(family.combinedDailyTokenCap))
                    .progressViewStyle(.linear)
                    .tint(poolTint)
            }

            Text(providerKeyFamilyQuotaSummary(family))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(providerKeyFamilyBudgetSummary(family))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if family.isOversubscribed {
                Text("覆盖预算超过当前已知上游上限，建议给这个池补 key 或下调对应消费者预算。")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let clientsPreview = providerKeyFamilyClientPreview(family)
            if !clientsPreview.isEmpty {
                Text(clientsPreview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(poolTint.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(poolTint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
