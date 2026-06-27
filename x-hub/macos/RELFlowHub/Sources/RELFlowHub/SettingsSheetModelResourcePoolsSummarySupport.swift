import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func modelResourcePoolsSummaryText(_ pools: [ModelResourcePoolSummary]) -> String {
        let readyCount = pools.filter { $0.statusText == "Ready" || $0.statusText == "可按需加载" }.count
        let attentionCount = pools.filter { pool in
            pool.statusText == "阻断" || pool.statusText == "冷却" || pool.statusText == "Runtime 待恢复" || pool.statusText == "待接账号"
        }.count
        return "\(pools.count) 个资源池 · \(readyCount) 个可用 · \(attentionCount) 个需要关注"
    }

    func modelResourcePoolsBadgeText(_ pools: [ModelResourcePoolSummary]) -> String {
        let readyCount = pools.filter { $0.statusText == "Ready" || $0.statusText == "可按需加载" }.count
        return "\(readyCount)/\(pools.count) 可用"
    }

    func modelResourcePoolsTint(_ pools: [ModelResourcePoolSummary]) -> Color {
        if pools.contains(where: { $0.statusText == "阻断" }) {
            return .red
        }
        if pools.contains(where: { $0.statusText == "冷却" || $0.statusText == "Runtime 待恢复" || $0.statusText == "待接账号" }) {
            return .orange
        }
        return .green
    }

    func modelResourcePoolQuotaTint(_ pool: ModelResourcePoolSummary) -> Color {
        if let window = pool.usageWindows.first {
            return providerKeyUsageWindowTint(window)
        }
        return pool.tint
    }
}
