import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
var cliproxyOAuthStatusBadgeText: String {
        if cliproxyOAuthSyncing {
            return "同步中"
        }
        if cliproxyOAuthRefreshing {
            return "刷新中"
        }
        if let provider = cliproxyOAuthActiveProvider,
           !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(provider.title) 登录中"
        }
        if cliproxyOAuthSettings.autoSync {
            return "自动同步开"
        }
        return "手动同步"
    }

    var cliproxyOAuthStatusTint: Color {
        if cliproxyOAuthSyncing || cliproxyOAuthRefreshing {
            return .blue
        }
        if !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .orange
        }
        return cliproxyOAuthSettings.autoSync ? .green : .secondary
    }

    var cliproxyOAuthInventoryAuths: [CLIProxyOAuthSourceSupport.RemoteAuthFile] {
        cliproxyOAuthRemoteAuths.filter { !$0.runtimeOnly }
    }

    var cliproxyOAuthInventoryCount: Int {
        cliproxyOAuthInventoryAuths.count
    }

    var cliproxyOAuthRuntimeOnlyCount: Int {
        cliproxyOAuthRemoteAuths.filter(\.runtimeOnly).count
    }

    var cliproxyOAuthReadyCount: Int {
        cliproxyOAuthInventoryAuths.filter {
            cliproxyOAuthInventoryState($0) == .ready
        }.count
    }

    var cliproxyOAuthCoolingCount: Int {
        cliproxyOAuthInventoryAuths.filter {
            cliproxyOAuthInventoryState($0) == .cooling
        }.count
    }

    var cliproxyOAuthBlockedCount: Int {
        cliproxyOAuthInventoryAuths.filter {
            cliproxyOAuthInventoryState($0) == .blocked
        }.count
    }

    var cliproxyOAuthDisabledCount: Int {
        cliproxyOAuthInventoryAuths.filter {
            cliproxyOAuthInventoryState($0) == .disabled
        }.count
    }

    var cliproxyOAuthRefreshingCount: Int {
        cliproxyOAuthInventoryAuths.filter {
            cliproxyOAuthInventoryState($0) == .refreshing
        }.count
    }

    var cliproxyOAuthWaitingCount: Int {
        cliproxyOAuthInventoryAuths.filter {
            cliproxyOAuthInventoryState($0) == .waiting
        }.count
    }

    var cliproxyOAuthQuotaExceededCount: Int {
        cliproxyOAuthInventoryAuths.filter(\.quota.exceeded).count
    }

    var cliproxyOAuthProviderCount: Int {
        cliproxyOAuthProviderSummaries.count
    }

    var cliproxyOAuthNextRefreshAtMs: Int64 {
        cliproxyOAuthInventoryAuths
            .map(\.nextRefreshAtMs)
            .filter { $0 > 0 }
            .min() ?? 0
    }

    var cliproxyOAuthNextRecoverAtMs: Int64 {
        cliproxyOAuthInventoryAuths
            .compactMap { auth in
                minimumPositiveTimestamp(
                    auth.nextRetryAtMs,
                    auth.quota.nextRecoverAtMs
                )
            }
            .min() ?? 0
    }

    var cliproxyOAuthProviderSummaries: [CLIProxyOAuthProviderInventorySummary] {
        Dictionary(grouping: cliproxyOAuthInventoryAuths) { auth in
            cliproxyOAuthCanonicalProviderKey(auth.provider)
        }
        .map { providerKey, auths in
            CLIProxyOAuthProviderInventorySummary(
                providerKey: providerKey,
                displayName: cliproxyOAuthProviderDisplayName(providerKey),
                totalCount: auths.count,
                readyCount: auths.filter { cliproxyOAuthInventoryState($0) == .ready }.count,
                coolingCount: auths.filter { cliproxyOAuthInventoryState($0) == .cooling }.count,
                blockedCount: auths.filter { cliproxyOAuthInventoryState($0) == .blocked }.count,
                disabledCount: auths.filter { cliproxyOAuthInventoryState($0) == .disabled }.count,
                refreshingCount: auths.filter { cliproxyOAuthInventoryState($0) == .refreshing }.count,
                waitingCount: auths.filter { cliproxyOAuthInventoryState($0) == .waiting }.count
            )
        }
        .sorted { lhs, rhs in
            let leftOrder = cliproxyOAuthProviderSortIndex(lhs.providerKey)
            let rightOrder = cliproxyOAuthProviderSortIndex(rhs.providerKey)
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            if lhs.readyCount != rhs.readyCount {
                return lhs.readyCount > rhs.readyCount
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    var cliproxyOAuthProviderCoverageText: String {
        let names = cliproxyOAuthProviderSummaries.map(\.displayName)
        guard !names.isEmpty else {
            return "还没有 OAuth 厂家库存"
        }
        if names.count <= 3 {
            return names.joined(separator: " / ")
        }
        return names.prefix(3).joined(separator: " / ") + " +\(names.count - 3)"
    }

    var cliproxyOAuthOverviewSummaryText: String {
        var parts: [String] = []

        if cliproxyOAuthRemoteAuths.isEmpty {
            parts.append("当前还没有从 CLIProxy 拉到已认证账号")
        } else {
            parts.append("已发现 \(cliproxyOAuthRemoteAuths.count) 个认证文件")
            if cliproxyOAuthInventoryCount > 0 {
                parts.append("\(cliproxyOAuthInventoryCount) 个可并入 Hub")
            }
            if cliproxyOAuthRuntimeOnlyCount > 0 {
                parts.append("\(cliproxyOAuthRuntimeOnlyCount) 个 runtime-only")
            }
            if cliproxyOAuthProviderCount > 0 {
                parts.append("覆盖 \(cliproxyOAuthProviderCount) 家厂商")
            }
        }

        if cliproxyOAuthSettings.lastSyncAtMs > 0 {
            parts.append("上次同步 \(formattedProviderKeyImportSourceTime(cliproxyOAuthSettings.lastSyncAtMs))")
        } else if cliproxyOAuthLastRemoteFetchAtMs > 0 {
            parts.append("列表刷新 \(formattedProviderKeyImportSourceTime(cliproxyOAuthLastRemoteFetchAtMs))")
        } else if cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("填写 management key 后可自动并入 Hub 额度池")
        } else {
            parts.append("已连接 management key，等待第一次同步")
        }

        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    var cliproxyOAuthOverviewNoticeText: String {
        let trimmedError = cliproxyOAuthErrorText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedError.isEmpty {
            return trimmedError
        }

        if let provider = cliproxyOAuthActiveProvider,
           !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(provider.title) OAuth 正在等待浏览器完成登录，完成后 Hub 会自动导入凭证并并入额度池。"
        }

        if cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "新账号可直接走 Hub 原生 OAuth；只有导入旧 CLIProxy 账号时才需要 management key。"
        }

        if cliproxyOAuthRemoteAuths.isEmpty {
            return "CLIProxy 已接通，但还没有旧认证账号。新登录会直接进入 Hub Provider Key 额度池。"
        }

        if cliproxyOAuthInventoryCount == 0 && cliproxyOAuthRuntimeOnlyCount > 0 {
            return "当前拉到的账号全部是 runtime-only，暂时不会并入 Hub 额度池。"
        }

        if cliproxyOAuthBlockedCount > 0 {
            if cliproxyOAuthNextRecoverAtMs > 0 {
                return "当前有 \(cliproxyOAuthBlockedCount) 个账号阻断，最早 \(formattedProviderKeyImportSourceTime(cliproxyOAuthNextRecoverAtMs)) 可恢复或重试。"
            }
            return "当前有 \(cliproxyOAuthBlockedCount) 个账号阻断，建议去模型页看具体 provider / key 状态。"
        }

        if cliproxyOAuthCoolingCount > 0 {
            let limitedText = cliproxyOAuthQuotaExceededCount > 0
                ? "\(cliproxyOAuthQuotaExceededCount) 个已触发免费额度上限"
                : "\(cliproxyOAuthCoolingCount) 个正在冷却"
            if cliproxyOAuthNextRecoverAtMs > 0 {
                return "当前有 \(limitedText)，最早 \(formattedProviderKeyImportSourceTime(cliproxyOAuthNextRecoverAtMs)) 恢复。"
            }
            return "当前有 \(limitedText)，等待 CLIProxy 恢复可用额度。"
        }

        if cliproxyOAuthRefreshingCount > 0 || cliproxyOAuthWaitingCount > 0 {
            var parts: [String] = []
            if cliproxyOAuthRefreshingCount > 0 {
                parts.append("刷新中 \(cliproxyOAuthRefreshingCount)")
            }
            if cliproxyOAuthWaitingCount > 0 {
                parts.append("等待中 \(cliproxyOAuthWaitingCount)")
            }
            return "库存正在滚动维护：\(HubUIStrings.Settings.RemoteModels.sectionSummary(parts))。"
        }

        if cliproxyOAuthNextRefreshAtMs > 0 {
            return "库存当前可用，下次刷新 \(formattedProviderKeyImportSourceTime(cliproxyOAuthNextRefreshAtMs))。"
        }

        return "库存当前可用，可以继续给 XT 或普通 terminal 分配 Hub access key + URL。"
    }

    var cliproxyOAuthOverviewNoticeTint: Color {
        let trimmedRuntimeError = cliproxyRuntimeErrorText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRuntimeError.isEmpty {
            return .red
        }
        let trimmedError = cliproxyOAuthErrorText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedError.isEmpty {
            return .red
        }
        if cliproxyRuntimeLaunching || cliproxyRuntimeRefreshing {
            return .blue
        }
        if !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .blue
        }
        if cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || cliproxyOAuthRemoteAuths.isEmpty {
            return .indigo
        }
        if cliproxyOAuthBlockedCount > 0 {
            return .red
        }
        if cliproxyOAuthCoolingCount > 0 {
            return .orange
        }
        if cliproxyOAuthRefreshingCount > 0 || cliproxyOAuthWaitingCount > 0 {
            return .blue
        }
        return .green
    }

    var cliproxyOAuthOverviewNoticeSystemName: String {
        let trimmedError = cliproxyOAuthErrorText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedError.isEmpty {
            return "exclamationmark.triangle"
        }
        if !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "person.badge.key"
        }
        if cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || cliproxyOAuthRemoteAuths.isEmpty {
            return "info.circle"
        }
        if cliproxyOAuthBlockedCount > 0 {
            return "xmark.octagon"
        }
        if cliproxyOAuthCoolingCount > 0 {
            return "timer"
        }
        if cliproxyOAuthRefreshingCount > 0 || cliproxyOAuthWaitingCount > 0 {
            return "arrow.triangle.2.circlepath"
        }
        return "checkmark.seal"
    }

    var cliproxyOAuthOverviewMetrics: [HubSettingsMetric] {
        let refreshValue: String
        if cliproxyOAuthNextRefreshAtMs > 0 {
            refreshValue = formattedProviderKeyImportSourceTime(cliproxyOAuthNextRefreshAtMs)
        } else if cliproxyOAuthRefreshing || cliproxyOAuthSyncing {
            refreshValue = "进行中"
        } else if cliproxyOAuthSettings.lastSyncAtMs > 0 {
            refreshValue = "已同步"
        } else {
            refreshValue = "待同步"
        }

        let refreshDetail: String
        if cliproxyOAuthLastRemoteFetchAtMs > 0 {
            refreshDetail = "列表刷新 \(formattedProviderKeyImportSourceTime(cliproxyOAuthLastRemoteFetchAtMs))"
        } else if cliproxyOAuthSettings.lastSyncAtMs > 0 {
            refreshDetail = "上次同步 \(formattedProviderKeyImportSourceTime(cliproxyOAuthSettings.lastSyncAtMs))"
        } else {
            refreshDetail = "还没有 CLIProxy 远端拉取记录"
        }

        return [
            HubSettingsMetric(
                title: "可用账号",
                value: cliproxyOAuthInventoryCount == 0 ? "0" : "\(cliproxyOAuthReadyCount)/\(cliproxyOAuthInventoryCount)",
                detail: cliproxyOAuthRuntimeOnlyCount > 0
                    ? "另有 \(cliproxyOAuthRuntimeOnlyCount) 个 runtime-only 未并入 Hub"
                    : "已就绪 / 可导入的 CLIProxy 账号",
                tint: cliproxyOAuthReadyCount > 0 ? .green : .secondary
            ),
            HubSettingsMetric(
                title: "冷却 / 恢复",
                value: "\(cliproxyOAuthCoolingCount)",
                detail: cliproxyOAuthNextRecoverAtMs > 0
                    ? "最早恢复 \(formattedProviderKeyImportSourceTime(cliproxyOAuthNextRecoverAtMs))"
                    : "当前没有额度冷却",
                tint: cliproxyOAuthCoolingCount > 0 ? .orange : .green
            ),
            HubSettingsMetric(
                title: "阻断 / 停用",
                value: "\(cliproxyOAuthBlockedCount + cliproxyOAuthDisabledCount)",
                detail: HubUIStrings.Settings.RemoteModels.sectionSummary([
                    "阻断 \(cliproxyOAuthBlockedCount)",
                    "停用 \(cliproxyOAuthDisabledCount)"
                ]),
                tint: cliproxyOAuthBlockedCount > 0 ? .red : (cliproxyOAuthDisabledCount > 0 ? .gray : .green)
            ),
            HubSettingsMetric(
                title: "下次刷新",
                value: refreshValue,
                detail: refreshDetail,
                tint: cliproxyOAuthRefreshing || cliproxyOAuthSyncing ? .blue : .indigo
            ),
            HubSettingsMetric(
                title: "覆盖厂家",
                value: cliproxyOAuthProviderCount == 0 ? "未接入" : "\(cliproxyOAuthProviderCount)",
                detail: cliproxyOAuthProviderCoverageText,
                tint: cliproxyOAuthProviderCount > 0 ? .teal : .secondary
            )
        ]
    }

    var cliproxyOAuthHubRoutingStatusText: String {
        let snapshot = providerKeySnapshot
        let derived = providerKeyDerivedSnapshot
        guard snapshot.totalAccounts > 0 else {
            return "Hub 账号池为空：同步 CLIProxy OAuth 或发起 Hub OAuth 后会在这里显示可路由库存。"
        }

        let blockedLikeAccounts = derived.blockedAccounts
            + derived.disabledPoolAccounts
            + derived.staleAccounts
        let strategies = Array(Set(derived.keyPools.map(\.routingStrategy).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })).sorted()
        let strategyText = strategies.isEmpty
            ? snapshot.globalRoutingStrategy
            : strategies.joined(separator: " / ")

        return HubUIStrings.Settings.RemoteModels.sectionSummary([
            "Hub 账号池 \(derived.readyAccounts)/\(derived.totalAccounts) 可路由",
            "\(derived.keyPools.count) 个物理池",
            "\(derived.quotaPools.count) 个额度池",
            derived.cooldownAccounts > 0 ? "冷却 \(derived.cooldownAccounts)" : "",
            blockedLikeAccounts > 0 ? "阻断/停用/过期 \(blockedLikeAccounts)" : "",
            "策略 \(strategyText)"
        ])
    }

    var cliproxyOAuthHubRoutingStatusTint: Color {
        if providerKeyDerivedSnapshot.readyAccounts > 0 {
            return providerKeyDerivedSnapshot.cooldownAccounts > 0 ? .orange : .green
        }
        if providerKeyDerivedSnapshot.totalAccounts > 0 {
            return .red
        }
        return .indigo
    }

    var cliproxyOAuthHubRoutingStatusSystemName: String {
        if providerKeyDerivedSnapshot.readyAccounts > 0 {
            return "point.3.connected.trianglepath.dotted"
        }
        if providerKeyDerivedSnapshot.totalAccounts > 0 {
            return "exclamationmark.triangle"
        }
        return "tray.and.arrow.down"
    }

    func cliproxyOAuthSyncActionText(
        summary: CLIProxyOAuthSourceSupport.SyncSummary,
        snapshot: ProviderKeyStoreSnapshot,
        partial: Bool
    ) -> String {
        let blockedLikeAccounts = snapshot.blockedAccounts
            + snapshot.disabledPoolAccounts
            + snapshot.staleAccounts
        var parts = ["写入 \(summary.importedCount) 个账号"]
        if summary.prunedCount > 0 {
            parts.append("清理 \(summary.prunedCount) 个旧账号")
        }
        if snapshot.totalAccounts > 0 {
            parts.append("Hub 账号池 \(snapshot.readyAccounts)/\(snapshot.totalAccounts) 可路由")
        }
        if snapshot.keyPools.count > 0 {
            parts.append("\(snapshot.keyPools.count) 个物理池")
        }
        if snapshot.quotaPools.count > 0 {
            parts.append("\(snapshot.quotaPools.count) 个额度池")
        }
        if snapshot.cooldownAccounts > 0 {
            parts.append("冷却 \(snapshot.cooldownAccounts)")
        }
        if blockedLikeAccounts > 0 {
            parts.append("阻断/停用/过期 \(blockedLikeAccounts)")
        }
        if partial {
            parts.append("\(summary.errorMessages.count) 个同步失败")
            return "已部分同步：\(HubUIStrings.Settings.RemoteModels.sectionSummary(parts))，旧账号不会被误删。"
        }
        return "同步完成：\(HubUIStrings.Settings.RemoteModels.sectionSummary(parts))。"
    }

    var cliproxyOAuthHeaderMetric: HubSettingsMetric {
        let managementKey = cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if let provider = cliproxyOAuthActiveProvider,
           !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return HubSettingsMetric(
                title: "CLIProxy OAuth",
                value: "\(provider.title) 登录中",
                detail: "浏览器完成后会自动同步到 Hub",
                tint: .blue
            )
        }

        if cliproxyOAuthInventoryCount > 0 {
            return HubSettingsMetric(
                title: "CLIProxy OAuth",
                value: "\(cliproxyOAuthReadyCount)/\(cliproxyOAuthInventoryCount)",
                detail: HubUIStrings.Settings.RemoteModels.sectionSummary([
                    "\(cliproxyOAuthProviderCount) 家厂商",
                    cliproxyOAuthCoolingCount > 0 ? "冷却 \(cliproxyOAuthCoolingCount)" : "",
                    cliproxyOAuthBlockedCount > 0 ? "阻断 \(cliproxyOAuthBlockedCount)" : "",
                    cliproxyOAuthRuntimeOnlyCount > 0 ? "runtime-only \(cliproxyOAuthRuntimeOnlyCount)" : ""
                ]),
                tint: cliproxyOAuthBlockedCount > 0 ? .red : (cliproxyOAuthCoolingCount > 0 ? .orange : .green)
            )
        }

        if managementKey.isEmpty {
            return HubSettingsMetric(
                title: "CLIProxy OAuth",
                value: "未接入",
                detail: "接入后可把免费额度账号直接并入 Hub",
                tint: .gray
            )
        }

        if cliproxyOAuthRemoteAuths.isEmpty {
            return HubSettingsMetric(
                title: "CLIProxy OAuth",
                value: "待登录",
                detail: "CLIProxy 已连通，等待已认证账号",
                tint: .indigo
            )
        }

        return HubSettingsMetric(
            title: "CLIProxy OAuth",
            value: "0",
            detail: cliproxyOAuthRuntimeOnlyCount > 0
                ? "当前全是 runtime-only 账号"
                : "等待 CLIProxy 返回可导入账号",
            tint: .orange
        )
    }


    func minimumPositiveTimestamp(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let values = [lhs, rhs].filter { $0 > 0 }
        return values.min()
    }
}
