import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func providerKeyDisplayUsageWindows(_ account: ProviderKeyAccount) -> [ProviderKeyUsageWindow] {
        let windows = account.quota.usageWindows
        guard !windows.isEmpty else { return [] }

        let rateLimitWindows = windows.filter {
            $0.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "rate_limit"
        }
        let preferredRateLimitWindows = rateLimitWindows.filter {
            $0.limitWindowSeconds == 5 * 60 * 60 || $0.limitWindowSeconds == 7 * 24 * 60 * 60
        }
        let selected: [ProviderKeyUsageWindow]
        if !preferredRateLimitWindows.isEmpty {
            selected = preferredRateLimitWindows
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

    func providerKeyPoolDisplayUsageWindows(_ pool: ProviderKeyPoolSnapshot) -> [ProviderKeyUsageWindow] {
        var groupedWindows: [String: ProviderKeyUsageWindow] = [:]

        for member in pool.members {
            for window in providerKeyDisplayUsageWindows(member.account) {
                let groupKey = providerKeyUsageWindowGroupKey(window)
                var normalizedWindow = window
                normalizedWindow.key = "pool:\(pool.id):\(groupKey)"

                guard var existingWindow = groupedWindows[groupKey] else {
                    groupedWindows[groupKey] = normalizedWindow
                    continue
                }

                var selectedWindow = providerKeyMoreConstrainedUsageWindow(
                    existingWindow,
                    normalizedWindow
                )
                selectedWindow.key = "pool:\(pool.id):\(groupKey)"
                selectedWindow.limited = existingWindow.limited || normalizedWindow.limited || selectedWindow.limited
                selectedWindow.resetAtMs = providerKeyEarliestPositiveTimestamp(
                    existingWindow.resetAtMs,
                    normalizedWindow.resetAtMs
                )
                selectedWindow.updatedAtMs = max(existingWindow.updatedAtMs, normalizedWindow.updatedAtMs)
                existingWindow = selectedWindow
                groupedWindows[groupKey] = existingWindow
            }
        }

        return groupedWindows.values.sorted {
            let lhsRank = providerKeyUsageWindowRank($0)
            let rhsRank = providerKeyUsageWindowRank($1)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if $0.limitWindowSeconds != $1.limitWindowSeconds {
                return $0.limitWindowSeconds < $1.limitWindowSeconds
            }
            return $0.key < $1.key
        }
    }

    func providerKeyUsageWindowGroupKey(_ window: ProviderKeyUsageWindow) -> String {
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

    func providerKeyMoreConstrainedUsageWindow(
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

    func providerKeyEarliestPositiveTimestamp(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        if lhs <= 0 { return max(0, rhs) }
        if rhs <= 0 { return lhs }
        return min(lhs, rhs)
    }

    func providerKeyUsageWindowRank(_ window: ProviderKeyUsageWindow) -> Int {
        switch window.limitWindowSeconds {
        case 5 * 60 * 60:
            return 0
        case 7 * 24 * 60 * 60:
            return 1
        default:
            return 10
        }
    }

    func providerKeyUsageWindowTitle(_ window: ProviderKeyUsageWindow) -> String {
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

    func providerKeyUsageWindowPercent(_ window: ProviderKeyUsageWindow) -> Double {
        let percent = window.usedPercent > 0
            ? window.usedPercent
            : Double(max(0, min(10_000, window.usedBasisPoints))) / 100.0
        return max(0, min(100, percent))
    }

    func providerKeyUsageWindowPercentText(_ window: ProviderKeyUsageWindow) -> String {
        String(format: "%.1f%%", providerKeyUsageWindowPercent(window))
    }

    func providerKeyUsageWindowResetText(_ window: ProviderKeyUsageWindow) -> String {
        guard window.resetAtMs > 0 else { return "" }
        return "重置 \(formattedProviderKeyImportSourceTime(window.resetAtMs))"
    }

    func providerKeyUsageWindowTint(_ window: ProviderKeyUsageWindow) -> Color {
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
}
