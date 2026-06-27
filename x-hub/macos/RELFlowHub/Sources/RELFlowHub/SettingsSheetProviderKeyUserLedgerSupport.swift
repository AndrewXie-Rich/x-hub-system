import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func providerKeyUserLedgerSummary(
        _ users: [RemoteQuotaCenterUserProjection]
    ) -> String {
        let standaloneCount = users.filter(\.isStandaloneConsumer).count
        let riskCount = users.filter(providerKeyUserAtRisk(_:)).count
        var parts: [String] = ["共 \(users.count) 个用户主体"]
        if riskCount > 0 {
            parts.append("\(riskCount) 个存在预算风险")
        }
        if standaloneCount > 0 {
            parts.append("\(standaloneCount) 个未绑定 user_id，已按单 consumer 独立记账")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyUserTint(
        _ user: RemoteQuotaCenterUserProjection
    ) -> Color {
        if user.isStandaloneConsumer {
            return .gray
        }
        return user.terminalConsumerCount > 0 && user.xtConsumerCount > 0 ? .blue : .indigo
    }

    func providerKeyUserAtRisk(
        _ user: RemoteQuotaCenterUserProjection
    ) -> Bool {
        if user.consumers.contains(where: providerKeyConsumerAtRisk(_:)) {
            return true
        }
        guard user.allocatedDailyTokenBudget > 0 else { return false }
        return user.remainingDailyTokenBudget <= max(Int64(5_000), user.allocatedDailyTokenBudget / 10)
    }

    func providerKeyBudgetUserIdentitySummary(
        _ user: RemoteQuotaCenterUserProjection
    ) -> String {
        var parts: [String] = []
        switch user.groupingKind {
        case .userID:
            parts.append("user_id \(user.groupingValue)")
        case .standaloneConsumer:
            parts.append("未设置 user_id，按单个 consumer 独立记账")
        }
        if !user.appIds.isEmpty {
            parts.append("app \(providerKeyPreviewList(user.appIds))")
        }
        return parts.joined(separator: " • ")
    }

    func providerKeyBudgetUserScopeSummary(
        _ user: RemoteQuotaCenterUserProjection
    ) -> String {
        var parts: [String] = []
        if !user.familyDisplayNames.isEmpty {
            parts.append("家族 \(providerKeyPreviewList(user.familyDisplayNames))")
        } else {
            parts.append("当前还没有解析到模型家族")
        }
        parts.append("\(user.consumerCount) 个消费者")
        if user.connectedConsumerCount > 0 {
            parts.append("在线 \(user.connectedConsumerCount)")
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyBudgetUserConsumerPreview(
        _ user: RemoteQuotaCenterUserProjection
    ) -> String {
        let preview = user.consumers.prefix(3).map { consumer in
            "\(consumer.name)(\(consumer.kindTitle))"
        }
        guard !preview.isEmpty else { return "" }
        let suffix = user.consumerCount > preview.count
            ? " 等另外 \(user.consumerCount - preview.count) 个"
            : ""
        return "消费者：\(preview.joined(separator: "、"))\(suffix)"
    }

    func providerKeyPreviewList(
        _ values: [String],
        maxCount: Int = 3
    ) -> String {
        let trimmed = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return "" }
        let preview = Array(trimmed.prefix(maxCount))
        let suffix = trimmed.count > preview.count ? " 等 \(trimmed.count) 项" : ""
        return preview.joined(separator: " / ") + suffix
    }
}
