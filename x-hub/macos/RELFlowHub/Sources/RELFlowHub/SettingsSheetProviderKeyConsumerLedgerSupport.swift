import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func providerKeyFilteredConsumers(
        _ projection: RemoteQuotaCenterProjection,
        focusedVendorFamilyKeys: Set<String>
    ) -> [RemoteQuotaCenterClientProjection] {
        let scopedUsers = providerKeyScopedUsers(projection.users)
        let scopedConsumerIDs = Set(scopedUsers.flatMap { $0.consumers.map(\.id) })
        let baseConsumers: [RemoteQuotaCenterClientProjection]
        if providerKeyFocusedUser(projection.users) != nil, !scopedConsumerIDs.isEmpty {
            baseConsumers = projection.consumers.filter { scopedConsumerIDs.contains($0.id) }
        } else {
            baseConsumers = projection.consumers
        }

        let vendorScopedConsumers = providerKeyVendorScopedConsumers(
            baseConsumers,
            focusedVendorFamilyKeys: focusedVendorFamilyKeys
        )

        return vendorScopedConsumers.filter { consumer in
            switch remoteQuotaConsumerFilter {
            case .all:
                return true
            case .xt:
                return consumer.consumerKind == .pairedXT
            case .terminal:
                return consumer.consumerKind == .terminalAccess
            case .risk:
                return providerKeyConsumerAtRisk(consumer)
            }
        }
    }

    func providerKeyConsumerFilterSummary(
        _ consumers: [RemoteQuotaCenterClientProjection],
        totalConsumers: Int,
        focusedUser: RemoteQuotaCenterUserProjection?
    ) -> String {
        let xtCount = consumers.filter { $0.consumerKind == .pairedXT }.count
        let terminalCount = consumers.filter { $0.consumerKind == .terminalAccess }.count

        switch remoteQuotaConsumerFilter {
        case .all:
            if let focusedUser {
                return "当前显示 \(focusedUser.displayName) 相关的全部 \(consumers.count)/\(totalConsumers) 个消费者，其中 XT \(xtCount) 个，Terminal \(terminalCount) 个。"
            }
            return "显示全部 \(consumers.count) 个消费者，其中 XT \(xtCount) 个，Terminal \(terminalCount) 个。"
        case .xt:
            return "显示 \(consumers.count)/\(totalConsumers) 个 XT 消费者。"
        case .terminal:
            return "显示 \(consumers.count)/\(totalConsumers) 个普通 terminal access key 消费者。"
        case .risk:
            return consumers.isEmpty
                ? "当前没有逼近上限或出现阻断的消费者。"
                : "风险视图共 \(consumers.count) 个，按剩余额度偏低、已触顶或有阻断记录筛出。"
        }
    }

    func providerKeyConsumerKindColor(
        _ kind: RemoteQuotaCenterConsumerKind
    ) -> Color {
        switch kind {
        case .pairedXT:
            return .indigo
        case .terminalAccess:
            return .teal
        }
    }

    func providerKeyConsumerAtRisk(
        _ consumer: RemoteQuotaCenterClientProjection
    ) -> Bool {
        if let status = consumer.deviceStatus, status.blockedToday > 0 {
            return true
        }
        guard consumer.dailyTokenLimit > 0 else { return false }
        if consumer.dailyTokenUsed >= consumer.dailyTokenLimit {
            return true
        }
        return consumer.remainingDailyTokenBudget <= max(Int64(5_000), consumer.dailyTokenLimit / 10)
    }

    func providerKeyBudgetClientReferenceSummary(
        _ clientProjection: RemoteQuotaCenterClientProjection
    ) -> String {
        var parts: [String] = []
        if clientProjection.isTerminalAccess {
            parts.append("key \(clientProjection.referenceID)")
        } else {
            parts.append("device \(clientProjection.deviceId)")
        }
        if !clientProjection.appId.isEmpty {
            parts.append("app \(clientProjection.appId)")
        }
        if !clientProjection.userId.isEmpty {
            parts.append("user \(clientProjection.userId)")
        }
        return parts.joined(separator: " • ")
    }
}
