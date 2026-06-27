import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func expansionBinding(
        _ id: String,
        in set: Binding<Set<String>>
    ) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { expanded in
                var values = set.wrappedValue
                if expanded {
                    values.insert(id)
                } else {
                    values.remove(id)
                }
                set.wrappedValue = values
            }
        )
    }

    func grpcClientDetailSummary(_ status: GRPCDeviceStatusEntry?) -> String {
        guard let status else {
            return "未收到设备状态快照"
        }

        var parts: [String] = [grpcClientPresencePillTitle(status)]
        if status.dailyTokenCap > 0 {
            parts.append("\(Int(max(0, status.dailyTokenUsed)))/\(Int(max(0, status.dailyTokenCap)))")
        } else if status.dailyTokenUsed > 0 {
            parts.append("今日已用 \(Int(max(0, status.dailyTokenUsed)))")
        }
        if status.requestsToday > 0 {
            parts.append("请求 \(status.requestsToday)")
        }
        if status.blockedToday > 0 {
            parts.append("阻断 \(status.blockedToday)")
        }
        return parts.joined(separator: " · ")
    }

    func terminalAccessDetailSummary(
        _ accessKey: HubTerminalAccessKey,
        remaining: Int64,
        hasSecret: Bool
    ) -> String {
        var parts: [String] = []
        if accessKey.lastUsedAtMs > 0 {
            parts.append("最近使用 \(formatEpochMs(accessKey.lastUsedAtMs))")
        }
        parts.append("轮换 \(accessKey.rotationCount)")
        parts.append("剩余 \(terminalAccessIntText(remaining))")
        parts.append(hasSecret ? "含最新 Secret" : "仅模板")
        return parts.joined(separator: " · ")
    }

    var cliproxyOAuthDisclosureSummaryText: String {
        let runtimeSegment = cliproxyRuntimeDisclosureSummarySegment.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [
            runtimeSegment,
            cliproxyOAuthOverviewSummaryText,
            cliproxyOAuthOverviewNoticeText
        ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return settingsSummarySnippet(
            HubUIStrings.Settings.RemoteModels.sectionSummary(parts),
            limit: 132
        )
    }

    var terminalAccessDraftSummaryText: String {
        let name = terminalAccessDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let userID = terminalAccessDraft.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let appID = terminalAccessDraft.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        parts.append(name.isEmpty ? "未命名 access key" : name)
        if !userID.isEmpty {
            parts.append("user \(userID)")
        }
        if !appID.isEmpty {
            parts.append("app \(appID)")
        }
        parts.append("预算 \(terminalAccessIntText(Int64(max(1, terminalAccessDraft.dailyTokenLimit))))/day")
        parts.append(terminalAccessDraft.ttlHours == 0 ? "不过期" : "TTL \(terminalAccessDraft.ttlHours)h")
        parts.append(terminalAccessDraft.allowPaidModels ? "付费模型开" : "付费模型关")
        parts.append(terminalAccessDraft.defaultWebFetchEnabled ? "web.fetch 开" : "web.fetch 关")
        return parts.joined(separator: " · ")
    }

    func terminalAccessLastSecretSummaryText(_ secret: HubTerminalAccessKeySecretEnvelope) -> String {
        let deliveryPack = secret.deliveryPack
        var parts: [String] = [secret.accessKey.resolvedName]
        if !deliveryPack.authDisplayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(deliveryPack.authDisplayText)
        }
        if !secret.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(settingsSummarySnippet(secret.openAIBaseURL, limit: 42))
        }
        parts.append("离开此页前请先完成分发")
        return parts.joined(separator: " · ")
    }
}
