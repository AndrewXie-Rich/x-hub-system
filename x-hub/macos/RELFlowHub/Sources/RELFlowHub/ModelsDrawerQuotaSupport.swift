import Foundation
import SwiftUI
import RELFlowHubCore

extension ModelsDrawer {
    func portfolioQuotaSignal(_ pools: [ModelsDrawerResourcePoolSummary]) -> (text: String, tint: Color) {
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

    func usageWindowDisplay(_ window: ProviderKeyUsageWindow) -> ModelsDrawerUsageWindowDisplay {
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

    func quotaTint(for pool: ModelsDrawerResourcePoolSummary) -> Color {
        if pool.isLocal { return .green }
        guard let first = pool.usageWindows.first else {
            return pool.quotaText == "未知" ? .secondary : pool.statusColor
        }
        return providerKeyUsageWindowTint(first)
    }

    func providerDisplayUsageWindows(for pools: [ProviderKeyPoolSnapshot]) -> [ProviderKeyUsageWindow] {
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

    func providerKeyUsageWindowPercentText(_ window: ProviderKeyUsageWindow) -> String {
        String(format: "%.1f%%", providerKeyUsageWindowPercent(window))
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

    private func formattedDrawerTime(_ timestampMs: Int64) -> String {
        guard timestampMs > 0 else { return "未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0))
    }
}
