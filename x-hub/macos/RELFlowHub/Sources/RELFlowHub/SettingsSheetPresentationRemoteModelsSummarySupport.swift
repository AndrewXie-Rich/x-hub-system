import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
var activeRemoteModelCount: Int {
        remoteModels.filter { $0.enabled }.count
    }


    var loadedRemoteModelCount: Int {
        remoteModelGroups.reduce(0) { $0 + $1.loadedCount }
    }

    var availableRemoteModelCount: Int {
        remoteModelGroups.reduce(0) { $0 + $1.availableCount }
    }

    var needsSetupRemoteModelCount: Int {
        remoteModelGroups.reduce(0) { $0 + $1.needsSetupCount }
    }

    var remoteModelGroupCount: Int {
        remoteModelGroups.count
    }

    private var remoteModelEndpointHostCount: Int {
        Set(remoteModels.compactMap { remoteModelEndpointHost($0) }).count
    }

    var remoteModelsSectionSummaryText: String {
        guard !remoteModels.isEmpty else {
            return "先接入可执行的 provider / model，再用这里统一管理远端文本、多模态和专用入口。"
        }

        var parts: [String] = ["\(remoteModelGroupCount) 个组"]
        parts.append("\(loadedRemoteModelCount) 已加载")
        if availableRemoteModelCount > 0 {
            parts.append("\(availableRemoteModelCount) 可执行")
        }
        if needsSetupRemoteModelCount > 0 {
            parts.append("\(needsSetupRemoteModelCount) 待补齐")
        }
        if remoteModelEndpointHostCount > 0 {
            parts.append("\(remoteModelEndpointHostCount) 个 host")
        }
        return parts.joined(separator: " · ")
    }

    var remoteModelsAttentionBannerText: String? {
        guard !remoteModels.isEmpty else { return nil }
        if needsSetupRemoteModelCount > 0 {
            return "当前还有 \(needsSetupRemoteModelCount) 个远端模型待补齐 auth / 兼容 / provider 健康，修完后才适合给 XT 稳定路由。"
        }
        if loadedRemoteModelCount == 0 && availableRemoteModelCount > 0 {
            return "当前没有已加载远端模型，但已有 \(availableRemoteModelCount) 个入口可直接执行。需要时可以在下面按组加载。"
        }
        if loadedRemoteModelCount > 0 {
            return "当前已有 \(loadedRemoteModelCount) 个远端模型处于加载态，可直接复用；其余模型按需加载即可。"
        }
        return nil
    }

    var remoteModelsOverviewBadgeText: String {
        if remoteModels.isEmpty {
            return "未配置"
        }
        if needsSetupRemoteModelCount > 0 {
            return "\(needsSetupRemoteModelCount) 待补齐"
        }
        if loadedRemoteModelCount > 0 {
            return "\(loadedRemoteModelCount) 已加载"
        }
        if availableRemoteModelCount > 0 {
            return "\(availableRemoteModelCount) 可执行"
        }
        return "待加载"
    }

    var remoteModelsOverviewTint: Color {
        if needsSetupRemoteModelCount > 0 {
            return .orange
        }
        if loadedRemoteModelCount > 0 {
            return .green
        }
        if availableRemoteModelCount > 0 {
            return .indigo
        }
        return .secondary
    }

    var remoteModelsOverviewMetrics: [HubSettingsMetric] {
        [
            HubSettingsMetric(
                title: "模型组",
                value: "\(remoteModelGroupCount)",
                detail: remoteModelGroupCount == 0 ? "还没有聚合出的远端执行组" : "按 provider / key 聚合后的入口",
                tint: remoteModelGroupCount > 0 ? .indigo : .secondary
            ),
            HubSettingsMetric(
                title: "已加载",
                value: "\(loadedRemoteModelCount)",
                detail: remoteModels.isEmpty ? "等待配置远端模型" : "当前可直接复用的远端入口",
                tint: loadedRemoteModelCount > 0 ? .green : .secondary
            ),
            HubSettingsMetric(
                title: "可执行",
                value: "\(availableRemoteModelCount)",
                detail: remoteModels.isEmpty ? "等待 provider / auth" : "已通过基础执行前置条件",
                tint: availableRemoteModelCount > 0 ? .blue : .secondary
            ),
            HubSettingsMetric(
                title: "执行面",
                value: remoteModelEndpointHostCount == 0 ? "未接入" : "\(remoteModelEndpointHostCount) host",
                detail: remoteModels.isEmpty ? "还没有远端 endpoint" : "启用 \(activeRemoteModelCount) 个入口 · 待补齐 \(needsSetupRemoteModelCount)",
                tint: remoteModelEndpointHostCount > 0 ? .purple : .secondary
            )
        ]
    }

    var remoteModelsAttentionBannerTint: Color {
        if needsSetupRemoteModelCount > 0 {
            return .orange
        }
        if loadedRemoteModelCount > 0 {
            return .green
        }
        return .blue
    }

    var remoteModelsAttentionBannerSystemName: String {
        if needsSetupRemoteModelCount > 0 {
            return "exclamationmark.triangle"
        }
        if loadedRemoteModelCount > 0 {
            return "checkmark.seal"
        }
        return "sparkles"
    }
}
