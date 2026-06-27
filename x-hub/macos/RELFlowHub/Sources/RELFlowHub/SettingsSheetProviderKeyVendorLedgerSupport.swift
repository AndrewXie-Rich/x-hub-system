import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    func providerKeyVendorSpotlightMetric(
        _ title: String,
        tint: Color
    ) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
    }

    func providerKeyUserRemainingBudgetPreviewText(
        _ user: RemoteQuotaCenterUserProjection
    ) -> String {
        if user.allocatedDailyTokenBudget > 0 {
            let base = HubUIStrings.Settings.ProviderKeys.tokenCount(user.remainingDailyTokenBudget)
            return user.hasUnlimitedBudget ? "\(base) +" : base
        }
        return user.hasUnlimitedBudget ? "弹性" : "0"
    }

    func providerKeyConsumerRemainingBudgetPreviewText(
        _ consumer: RemoteQuotaCenterClientProjection
    ) -> String {
        consumer.dailyTokenLimit > 0
            ? HubUIStrings.Settings.ProviderKeys.tokenCount(consumer.remainingDailyTokenBudget)
            : "弹性"
    }

    @ViewBuilder
    func providerKeyHeatStrip(
        value: Double,
        tint: Color,
        segments: Int = 14
    ) -> some View {
        let normalized = max(0, min(1, value))
        HStack(spacing: 4) {
            ForEach(0..<segments, id: \.self) { index in
                let threshold = Double(index + 1) / Double(segments)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(threshold <= normalized ? tint.opacity(0.9) : tint.opacity(0.12))
                    .frame(maxWidth: .infinity, minHeight: 8, maxHeight: 8)
            }
        }
    }

    func providerKeyUsageHeatTint(
        fraction: Double,
        hasBlockingRisk: Bool
    ) -> Color {
        if hasBlockingRisk {
            return .red
        }
        switch fraction {
        case let value where value >= 0.9:
            return .orange
        case let value where value >= 0.65:
            return .yellow
        case let value where value > 0:
            return .blue
        default:
            return .green
        }
    }

    func providerKeyPoolNeedsAttention(
        _ pool: ProviderKeyPoolSnapshot
    ) -> Bool {
        if pool.blockedAccounts > 0 || pool.cooldownAccounts > 0 || !pool.issueSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return providerKeyUsageFraction(
            used: pool.totalDailyTokensUsed,
            cap: pool.totalDailyTokenCap
        ) >= 0.8
    }

    func providerKeySortVendorPools(
        _ lhs: ProviderKeyPoolSnapshot,
        _ rhs: ProviderKeyPoolSnapshot
    ) -> Bool {
        let leftHot = providerKeyPoolNeedsAttention(lhs)
        let rightHot = providerKeyPoolNeedsAttention(rhs)
        if leftHot != rightHot {
            return leftHot && !rightHot
        }
        if lhs.blockedAccounts != rhs.blockedAccounts {
            return lhs.blockedAccounts > rhs.blockedAccounts
        }
        if lhs.cooldownAccounts != rhs.cooldownAccounts {
            return lhs.cooldownAccounts > rhs.cooldownAccounts
        }
        if lhs.totalAccounts != rhs.totalAccounts {
            return lhs.totalAccounts > rhs.totalAccounts
        }
        return providerKeyPoolTitle(lhs).localizedCaseInsensitiveCompare(providerKeyPoolTitle(rhs)) == .orderedAscending
    }

    func providerKeyVendorPoolDisclosureSummary(
        _ vendor: ProviderKeyVendorInventorySummary
    ) -> String {
        var parts: [String] = [
            "\(vendor.pools.count) 个池",
            "\(vendor.totalAccounts) 把 key"
        ]

        if vendor.cooldownAccounts > 0 {
            parts.append("冷却 \(vendor.cooldownAccounts)")
        }
        if vendor.blockedAccounts > 0 {
            parts.append("阻断 \(vendor.blockedAccounts)")
        }

        let earliestRetryAtMs = vendor.pools
            .map(\.earliestRetryAtMs)
            .filter { $0 > 0 }
            .min() ?? 0
        if earliestRetryAtMs > 0 {
            parts.append("最早重试 \(formattedProviderKeyImportSourceTime(earliestRetryAtMs))")
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyDistinctPreviewStrings(
        _ values: [String]
    ) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.lowercased()
            guard !trimmed.isEmpty, seen.insert(normalized).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }

    func providerKeyCanonicalVendorKey(_ rawVendorKey: String) -> String {
        let normalized = rawVendorKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "chatgpt", "codex", "openai_compatible":
            return "openai"
        case "anthropic":
            return "claude"
        case "moonshot":
            return "kimi"
        default:
            return normalized
        }
    }

    func providerKeyVendorDisplayName(_ vendorKey: String) -> String {
        switch providerKeyCanonicalVendorKey(vendorKey) {
        case "openai":
            return "OpenAI / Codex"
        case "claude":
            return "Claude"
        case "gemini":
            return "Gemini"
        case "antigravity":
            return "Antigravity"
        case "kimi":
            return "Kimi"
        default:
            let normalized = providerKeyCanonicalVendorKey(vendorKey)
            return normalized.isEmpty ? "Unknown" : normalized.capitalized
        }
    }

    func providerKeyVendorSummaryText(
        _ vendor: ProviderKeyVendorInventorySummary
    ) -> String {
        var parts: [String] = []
        if !vendor.familyDisplayNames.isEmpty {
            parts.append("家族 \(providerKeyPreviewList(vendor.familyDisplayNames))")
        }
        if !vendor.providerHosts.isEmpty {
            parts.append("host \(providerKeyPreviewList(vendor.providerHosts, maxCount: 2))")
        } else if !vendor.providerDisplayNames.isEmpty {
            parts.append(providerKeyPreviewList(vendor.providerDisplayNames))
        }
        parts.append("\(vendor.coveredUserCount) 个用户 / \(vendor.coveredConsumerCount) 个 consumer")
        parts.append("\(vendor.poolCount) 个池 / \(vendor.totalAccounts) 把 key")
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    @ViewBuilder
    func providerKeyLedgerSectionHeader(
        title: String,
        summary: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    func providerKeyLedgerMetricTile(
        title: String,
        value: String,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
