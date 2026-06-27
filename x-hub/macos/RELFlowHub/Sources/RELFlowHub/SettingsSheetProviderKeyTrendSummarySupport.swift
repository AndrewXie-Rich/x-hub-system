import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func providerKeyUsageFraction(used: Int64, cap: Int64) -> Double {
        guard cap > 0 else { return 0 }
        let normalizedUsed = max(Double(used), 0)
        let normalizedCap = max(Double(cap), 1)
        return max(0, min(1, normalizedUsed / normalizedCap))
    }

    func providerKeySignedTokenCount(_ value: Int64) -> String {
        let magnitude = HubUIStrings.Settings.ProviderKeys.tokenCount(abs(value))
        if value > 0 { return "+\(magnitude)" }
        if value < 0 { return "-\(magnitude)" }
        return magnitude
    }

    func providerKeyTrendWindowSummary(
        _ aggregate: RemoteQuotaTrendAggregate
    ) -> String {
        let bucketMinutes = max(Int64(1), aggregate.bucketMs / (60 * 1000))
        let windowMinutes = max(Int64(1), aggregate.windowMs / (60 * 1000))
        if windowMinutes >= 60 {
            return "1h / \(bucketMinutes)m"
        }
        return "\(windowMinutes)m / \(bucketMinutes)m"
    }

    func providerKeyTrendMomentumText(
        _ aggregate: RemoteQuotaTrendAggregate
    ) -> String {
        if aggregate.recentTokens15m <= 0 && aggregate.previousTokens15m <= 0 {
            return "近 30 分钟基本无明显远端流量。"
        }
        if aggregate.previousTokens15m <= 0 {
            return "最近 15 分钟刚开始放量。"
        }
        guard let momentum = aggregate.momentumRatio else {
            return "最近 30 分钟流量稳定。"
        }
        let percent = Int((abs(momentum) * 100).rounded())
        if percent < 8 {
            return "较前 15 分钟基本持平。"
        }
        if momentum > 0 {
            return "较前 15 分钟提升 \(percent)%。"
        }
        return "较前 15 分钟回落 \(percent)%。"
    }

    func providerKeyTrendMomentumColor(
        _ aggregate: RemoteQuotaTrendAggregate
    ) -> Color {
        guard let momentum = aggregate.momentumRatio else {
            return aggregate.recentTokens15m > 0 ? .teal : .secondary
        }
        if abs(momentum) < 0.08 {
            return .secondary
        }
        return momentum > 0 ? .orange : .teal
    }

    func providerKeyTimestampSummary(_ timestampMs: Int64, prefix: String) -> String? {
        guard timestampMs > 0 else { return nil }
        return "\(prefix) \(formattedProviderKeyImportSourceTime(timestampMs))"
    }
}
