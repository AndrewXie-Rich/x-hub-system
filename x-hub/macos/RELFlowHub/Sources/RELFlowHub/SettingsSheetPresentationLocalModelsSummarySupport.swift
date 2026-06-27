import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
var localCatalogModels: [HubModel] {
        localModelSnapshot.models
    }

    var localCatalogModelCount: Int {
        localCatalogModels.count
    }

    var loadedLocalModelCount: Int {
        localModelSnapshot.loadedCount
    }

    private var localModelHealthSummary: LocalModelHealthSectionSummaryPresentation? {
        LocalModelHealthSectionSummarySupport.presentation(
            models: localCatalogModels,
            healthSnapshot: store.localModelHealthSnapshot,
            scanningModelIDs: store.localModelHealthScanningModelIDs
        )
    }

    var localAvailableModelCount: Int {
        localModelHealthSummary?.availableCount ?? 0
    }

    private var localReviewModelCount: Int {
        localModelHealthSummary?.reviewCount ?? 0
    }

    private var localDiscouragedModelCount: Int {
        localModelHealthSummary?.discouragedCount ?? 0
    }

    private var localUnscannedModelCount: Int {
        localModelHealthSummary?.unscannedCount ?? 0
    }

    private var localScanningModelCount: Int {
        localModelHealthSummary?.scanningCount ?? 0
    }

    var localPendingModelCount: Int {
        localReviewModelCount + localDiscouragedModelCount + localUnscannedModelCount
    }


    var localModelsCapabilitySummaryText: String {
        guard localCatalogModelCount > 0 else {
            return "先扫描并导入本地模型。这里和付费模型并列管理本地文本、多模态、OCR 与 TTS 能力。"
        }

        var parts: [String] = ["\(localCatalogModelCount) 个模型", "\(loadedLocalModelCount) 已加载"]
        if let summary = localModelHealthSummary?.text,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(summary)
        }
        if rustLocalMLAuthorityMode {
            parts.append(runtimeHeartbeatText)
        } else if totalRuntimeProviderCount > 0 {
            parts.append("\(readyRuntimeProviderCount)/\(totalRuntimeProviderCount) 个 runtime provider 就绪")
        } else {
            parts.append("等待 runtime 心跳")
        }
        return parts.joined(separator: " · ")
    }

    var localModelsCapabilityBadgeText: String {
        guard localCatalogModelCount > 0 else { return "未发现" }
        if store.localModelHealthScanInFlight || localScanningModelCount > 0 {
            return "扫描中"
        }
        if !runtimeReadyForUI && loadedLocalModelCount == 0 {
            return "等待 runtime"
        }
        if loadedLocalModelCount > 0 {
            return "\(loadedLocalModelCount) 已加载"
        }
        if localAvailableModelCount > 0 {
            return "\(localAvailableModelCount) 可用"
        }
        if localPendingModelCount > 0 {
            return "\(localPendingModelCount) 待复核"
        }
        return "待准备"
    }

    var localModelsCapabilityTint: Color {
        guard localCatalogModelCount > 0 else { return .secondary }
        if !runtimeReadyForUI && loadedLocalModelCount == 0 {
            return .orange
        }
        if store.localModelHealthScanInFlight || localScanningModelCount > 0 {
            return .teal
        }
        if loadedLocalModelCount > 0 {
            return .green
        }
        if localAvailableModelCount > 0 {
            return .indigo
        }
        if localPendingModelCount > 0 {
            return .orange
        }
        return .secondary
    }

    var localModelsCapabilityMetrics: [HubSettingsMetric] {
        [
            HubSettingsMetric(
                title: "模型库",
                value: "\(localCatalogModelCount)",
                detail: localCatalogModelCount == 0 ? "当前没有本地模型" : "只统计本地模型，不含付费 / 远端入口",
                tint: localCatalogModelCount > 0 ? .indigo : .secondary
            ),
            HubSettingsMetric(
                title: "已加载",
                value: "\(loadedLocalModelCount)",
                detail: localCatalogModelCount == 0 ? "等待导入本地模型" : "当前可直接复用的本地加载态模型",
                tint: loadedLocalModelCount > 0 ? .green : .secondary
            ),
            HubSettingsMetric(
                title: "预检可用",
                value: "\(localAvailableModelCount)",
                detail: HubUIStrings.Settings.RemoteModels.sectionSummary([
                    localReviewModelCount > 0 ? "复核 \(localReviewModelCount)" : nil,
                    localDiscouragedModelCount > 0 ? "风险 \(localDiscouragedModelCount)" : nil,
                    localUnscannedModelCount > 0 ? "未扫描 \(localUnscannedModelCount)" : nil
                ].compactMap { $0 }.isEmpty
                    ? ["当前没有待复核或未扫描模型"]
                    : [
                        localReviewModelCount > 0 ? "复核 \(localReviewModelCount)" : nil,
                        localDiscouragedModelCount > 0 ? "风险 \(localDiscouragedModelCount)" : nil,
                        localUnscannedModelCount > 0 ? "未扫描 \(localUnscannedModelCount)" : nil
                    ].compactMap { $0 }),
                tint: localAvailableModelCount > 0 ? .blue : .secondary
            ),
            HubSettingsMetric(
                title: "Runtime",
                value: rustLocalMLAuthorityMode
                    ? runtimeHeartbeatText
                    : (totalRuntimeProviderCount == 0 ? "待连接" : "\(readyRuntimeProviderCount)/\(totalRuntimeProviderCount)"),
                detail: runtimeReadyForUI
                    ? "本地执行链路就绪，可继续承接本地任务"
                    : "本地执行链路未就绪，本地任务可能无法稳定执行",
                tint: runtimeReadyForUI ? .orange : .red
            )
        ]
    }

    var localModelsCapabilityNoticeText: String? {
        guard localCatalogModelCount > 0 else { return nil }
        if !runtimeReadyForUI {
            return "当前本地执行链路 \(runtimeHeartbeatText)，本地模型暂时不能稳定承接任务。先到“运行时基础设施”查看 Rust readiness 和 worker 快照。"
        }
        if localDiscouragedModelCount > 0 {
            return "当前有 \(localDiscouragedModelCount) 个本地模型被标记为高风险，先修复兼容、依赖或快速评审结果，再给 XT 默认路由。"
        }
        if localUnscannedModelCount > 0 {
            return "当前还有 \(localUnscannedModelCount) 个本地模型尚未做快速评审，建议先扫一轮再暴露给 XT。"
        }
        if loadedLocalModelCount == 0 && localAvailableModelCount > 0 {
            return "当前没有常驻本地模型，但已有 \(localAvailableModelCount) 个模型通过快速评审，可按需自动加载。"
        }
        if loadedLocalModelCount > 0 {
            return "当前已有 \(loadedLocalModelCount) 个本地模型处于加载态，可直接承接本地文本或多模态任务。"
        }
        return nil
    }

    var localModelsCapabilityNoticeTint: Color {
        if !runtimeReadyForUI {
            return .orange
        }
        if localDiscouragedModelCount > 0 || localUnscannedModelCount > 0 {
            return .orange
        }
        if loadedLocalModelCount > 0 {
            return .green
        }
        return .blue
    }

    var localModelsCapabilityNoticeSystemName: String {
        if !runtimeReadyForUI {
            return "exclamationmark.triangle"
        }
        if localDiscouragedModelCount > 0 || localUnscannedModelCount > 0 {
            return "shield.lefthalf.filled.badge.exclamationmark"
        }
        if loadedLocalModelCount > 0 {
            return "checkmark.seal"
        }
        return "sparkles"
    }
}
