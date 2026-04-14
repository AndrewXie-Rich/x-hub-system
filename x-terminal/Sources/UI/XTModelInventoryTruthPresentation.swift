import Foundation
import SwiftUI

enum XTModelInventoryTruthState: String, Equatable, Sendable {
    case inventoryReady = "inventory_ready"
    case localOnlyReady = "local_only_ready"
    case remoteOnlyReady = "remote_only_ready"
    case snapshotMissing = "snapshot_missing"
    case noInteractiveLoaded = "no_interactive_loaded"
    case runtimeHeartbeatStale = "runtime_heartbeat_stale"
    case noReadyProvider = "no_ready_provider"
    case providerPartialReadiness = "provider_partial_readiness"
}

enum XTModelInventoryTruthTone: Equatable, Sendable {
    case neutral
    case caution
    case critical
}

struct XTModelInventoryTruthPresentation: Equatable, Sendable {
    var state: XTModelInventoryTruthState
    var tone: XTModelInventoryTruthTone
    var headline: String
    var summary: String
    var detail: String
    var remoteInteractiveLoadedCount: Int
    var localInteractiveLoadedCount: Int
    var supportLoadedCount: Int

    var requiresAttention: Bool {
        switch state {
        case .inventoryReady, .localOnlyReady:
            return false
        case .remoteOnlyReady, .snapshotMissing, .noInteractiveLoaded, .runtimeHeartbeatStale, .noReadyProvider, .providerPartialReadiness:
            return true
        }
    }

    var showsStatusCard: Bool {
        state != .inventoryReady
    }

    static func build(
        snapshot: ModelStateSnapshot,
        doctorReport: XHubDoctorOutputReport? = nil,
        runtimeMonitor: XHubLocalRuntimeMonitorSnapshotReport? = nil,
        runtimeStatus: AIRuntimeStatus? = nil
    ) -> XTModelInventoryTruthPresentation {
        let interactiveLoaded = snapshot.models.filter { $0.state == .loaded && $0.isSelectableForInteractiveRouting }
        let remoteLoaded = interactiveLoaded.filter { !$0.isLocalModel }
        let localLoaded = interactiveLoaded.filter(\.isLocalModel)
        let supportLoadedCount = snapshot.models.filter { $0.state == .loaded && !$0.isSelectableForInteractiveRouting }.count

        let failureCode = normalized(doctorReport?.currentFailureCode)
        let failureCheck = doctorReport?.checks.first {
            normalized($0.checkID) == failureCode
        }
        let failureHeadline = normalized(failureCheck?.headline)
        let failureMessage = normalized(failureCheck?.message)
        let failureNextStep = normalized(failureCheck?.nextStep)
            ?? normalized(doctorReport?.nextSteps.first(where: { $0.blocking })?.instruction)
            ?? normalized(doctorReport?.nextSteps.first?.instruction)
        let runtimeSummary = normalized(runtimeMonitor?.runtimeOperations?.runtimeSummary)
        let queueSummary = normalized(runtimeMonitor?.runtimeOperations?.queueSummary)
        let loadedSummary = normalized(runtimeMonitor?.runtimeOperations?.loadedSummary)
        let runtimeStatusSummary = runtimeStatus?.providerReadinessSummary
        let runtimeStatusLoadedSummary = runtimeStatus?.loadedInstanceDisplaySummary
        let runtimeStatusIssue = runtimeStatus?.firstUnavailableProviderSummary

        func detailLine(_ fallback: String) -> String {
            var parts: [String] = []
            if let failureMessage {
                parts.append(failureMessage)
            }
            if let failureNextStep {
                parts.append("下一步：\(failureNextStep)")
            }
            if let runtimeStatusIssue {
                parts.append("状态：\(runtimeStatusIssue)")
            }

            var runtimeParts: [String] = []
            if let runtimeSummary {
                runtimeParts.append(runtimeSummary)
            } else if let runtimeStatusSummary {
                runtimeParts.append(runtimeStatusSummary)
            }
            if let loadedSummary {
                runtimeParts.append(loadedSummary)
            } else if let runtimeStatusLoadedSummary {
                runtimeParts.append(runtimeStatusLoadedSummary)
            }
            if let queueSummary {
                runtimeParts.append(queueSummary)
            }
            if !runtimeParts.isEmpty {
                parts.append("运行时：\(runtimeParts.joined(separator: " · "))")
            }

            if parts.isEmpty {
                parts.append(fallback)
            }
            return parts.joined(separator: " ")
        }

        if failureCode == XTModelInventoryTruthState.runtimeHeartbeatStale.rawValue {
            let summary: String
            if interactiveLoaded.isEmpty {
                summary = "本地运行时心跳已过期，XT 现在拿不到可信的本地模型清单。"
            } else if localLoaded.isEmpty {
                summary = "远端模型还能看到，但本地运行时心跳已过期，本地兜底当前不可信。"
            } else {
                summary = "当前还能看到本地模型，但运行时心跳已过期，这份清单不应继续当成可信状态。"
            }
            return XTModelInventoryTruthPresentation(
                state: .runtimeHeartbeatStale,
                tone: .critical,
                headline: failureHeadline ?? "运行时心跳已过期",
                summary: summary,
                detail: detailLine("去 Hub 设置里重启运行时组件，然后刷新模型列表。"),
                remoteInteractiveLoadedCount: remoteLoaded.count,
                localInteractiveLoadedCount: localLoaded.count,
                supportLoadedCount: supportLoadedCount
            )
        }

        if failureCode == XTModelInventoryTruthState.noReadyProvider.rawValue {
            let summary: String
            if interactiveLoaded.isEmpty {
                summary = "Hub 现在没有任何就绪的本地模型服务，所以 XT 还没有可用的本地对话模型。"
            } else if localLoaded.isEmpty {
                summary = "远端模型还能用，但本地模型服务当前全部未就绪，本地兜底不可用。"
            } else {
                summary = "当前虽能看到模型目录，但 Hub 报告没有任何就绪的本地模型服务，本地模型不应当成可立即可用。"
            }
            return XTModelInventoryTruthPresentation(
                state: .noReadyProvider,
                tone: .critical,
                headline: failureHeadline ?? "没有可用的本地模型服务",
                summary: summary,
                detail: detailLine("检查本地模型服务包和导入失败原因，然后重启或刷新运行时。"),
                remoteInteractiveLoadedCount: remoteLoaded.count,
                localInteractiveLoadedCount: localLoaded.count,
                supportLoadedCount: supportLoadedCount
            )
        }

        if failureCode == XTModelInventoryTruthState.providerPartialReadiness.rawValue {
            let summary: String
            if interactiveLoaded.isEmpty {
                summary = "Hub 只拿到部分本地模型服务状态，就绪情况还不完整，当前模型列表可能缺项。"
            } else {
                summary = "本地模型服务只有一部分已就绪，当前模型目录可能不完整。"
            }
            return XTModelInventoryTruthPresentation(
                state: .providerPartialReadiness,
                tone: .caution,
                headline: failureHeadline ?? "本地模型服务就绪情况不完整",
                summary: summary,
                detail: detailLine("如果你需要更完整的本地能力覆盖，请检查还没起来的本地模型服务。"),
                remoteInteractiveLoadedCount: remoteLoaded.count,
                localInteractiveLoadedCount: localLoaded.count,
                supportLoadedCount: supportLoadedCount
            )
        }

        if let runtimeStatus, runtimeStatus.hasProviderInventory, !runtimeStatus.isAlive(ttl: 3.0) {
            let summary: String
            if interactiveLoaded.isEmpty {
                summary = "本地运行时心跳已过期，XT 现在拿不到可信的本地 provider 状态。"
            } else if localLoaded.isEmpty {
                summary = "远端模型还能看到，但本地运行时心跳已过期，本地兜底当前不可信。"
            } else {
                summary = "当前还能看到本地模型，但本地 provider 心跳已过期，这份运行时状态不应继续当成可信状态。"
            }
            return XTModelInventoryTruthPresentation(
                state: .runtimeHeartbeatStale,
                tone: .critical,
                headline: failureHeadline ?? "运行时心跳已过期",
                summary: summary,
                detail: detailLine("去 Hub 设置里重启运行时组件，然后刷新模型列表。"),
                remoteInteractiveLoadedCount: remoteLoaded.count,
                localInteractiveLoadedCount: localLoaded.count,
                supportLoadedCount: supportLoadedCount
            )
        }

        if let runtimeStatus, runtimeStatus.hasNoReadyProviders {
            let summary: String
            if interactiveLoaded.isEmpty {
                summary = "Hub 现在没有任何就绪的本地 provider，所以 XT 还没有可用的本地对话模型。"
            } else if localLoaded.isEmpty {
                summary = "远端模型还能用，但本地 provider 当前全部未就绪，本地兜底不可用。"
            } else {
                summary = "当前虽能看到模型目录，但 Hub 报告本地 provider 全部未就绪，本地模型不应当成可立即可用。"
            }
            return XTModelInventoryTruthPresentation(
                state: .noReadyProvider,
                tone: .critical,
                headline: failureHeadline ?? "没有可用的本地 provider",
                summary: summary,
                detail: detailLine("检查 provider pack、helper 服务或 Python runtime 缺依赖后，再刷新运行时。"),
                remoteInteractiveLoadedCount: remoteLoaded.count,
                localInteractiveLoadedCount: localLoaded.count,
                supportLoadedCount: supportLoadedCount
            )
        }

        if let runtimeStatus, runtimeStatus.hasPartialReadyProviders {
            let summary: String
            if interactiveLoaded.isEmpty {
                summary = "Hub 只拿到部分本地 provider 的就绪状态，当前模型列表可能缺项。"
            } else {
                summary = "本地 provider 只有一部分已就绪，当前模型目录和能力覆盖可能不完整。"
            }
            return XTModelInventoryTruthPresentation(
                state: .providerPartialReadiness,
                tone: .caution,
                headline: failureHeadline ?? "本地 provider 就绪情况不完整",
                summary: summary,
                detail: detailLine("如果你需要更完整的本地能力覆盖，请检查还没起来的 provider pack 和 runtime。"),
                remoteInteractiveLoadedCount: remoteLoaded.count,
                localInteractiveLoadedCount: localLoaded.count,
                supportLoadedCount: supportLoadedCount
            )
        }

        if snapshot.models.isEmpty {
            return XTModelInventoryTruthPresentation(
                state: .snapshotMissing,
                tone: .caution,
                headline: "还没拿到模型清单",
                summary: "当前还没有拿到 Hub 模型快照。",
                detail: "先刷新模型列表；如果仍为空，去 Supervisor 控制中心 · AI 模型确认模型是否真的进入真实可执行列表。",
                remoteInteractiveLoadedCount: 0,
                localInteractiveLoadedCount: 0,
                supportLoadedCount: 0
            )
        }

        if interactiveLoaded.isEmpty {
            let detail: String
            if supportLoadedCount > 0 {
                detail = "当前模型清单已同步，但已加载的是辅助模型，不是可直接对话的模型；先在 Supervisor 控制中心 · AI 模型里至少确认 1 个对话模型进入真实可执行列表。"
            } else {
                detail = "当前模型清单已同步，但没有已加载的可对话模型；先在 Supervisor 控制中心 · AI 模型里至少确认 1 个对话模型进入真实可执行列表。"
            }
            return XTModelInventoryTruthPresentation(
                state: .noInteractiveLoaded,
                tone: .caution,
                headline: "还没有可对话模型",
                summary: "Hub 已返回模型清单，但当前没有已加载的可对话模型。",
                detail: detail,
                remoteInteractiveLoadedCount: 0,
                localInteractiveLoadedCount: 0,
                supportLoadedCount: supportLoadedCount
            )
        }

        if remoteLoaded.isEmpty {
            return XTModelInventoryTruthPresentation(
                state: .localOnlyReady,
                tone: .neutral,
                headline: "当前走纯本地",
                summary: "现在只有本地对话模型已就绪，这本身是正常的纯本地姿态。",
                detail: "不配置云端服务或 API key，也可以继续聊天、项目推进和本地工具链。只有你需要远端 GPT 或其它云能力时，才需要再补远端模型、授权或连接。",
                remoteInteractiveLoadedCount: 0,
                localInteractiveLoadedCount: localLoaded.count,
                supportLoadedCount: supportLoadedCount
            )
        }

        if localLoaded.isEmpty {
            return XTModelInventoryTruthPresentation(
                state: .remoteOnlyReady,
                tone: .caution,
                headline: "当前没有本地兜底",
                summary: "现在没有本地对话模型兜底。",
                detail: "远端失联时弹性会更差；如果你希望保留本地兜底，建议至少保留 1 个本地对话模型。",
                remoteInteractiveLoadedCount: remoteLoaded.count,
                localInteractiveLoadedCount: 0,
                supportLoadedCount: supportLoadedCount
            )
        }

        var parts = [
            "远端对话 \(remoteLoaded.count) 个",
            "本地对话 \(localLoaded.count) 个"
        ]
        if supportLoadedCount > 0 {
            parts.append("辅助模型 \(supportLoadedCount) 个")
        }

        return XTModelInventoryTruthPresentation(
            state: .inventoryReady,
            tone: .neutral,
            headline: "模型目录已同步",
            summary: "XT 当前看到的是 Hub 返回的真实模型视图：\(parts.joined(separator: "，"))。",
            detail: "如果某台已配对 Terminal 需要独立的本地加载参数覆盖，请去 Hub 的设备编辑页调整该设备的本地模型覆盖。",
            remoteInteractiveLoadedCount: remoteLoaded.count,
            localInteractiveLoadedCount: localLoaded.count,
            supportLoadedCount: supportLoadedCount
        )
    }

    static func build(
        snapshot: ModelStateSnapshot,
        hubBaseDir: URL
    ) -> XTModelInventoryTruthPresentation {
        build(
            snapshot: snapshot,
            doctorReport: XHubDoctorOutputStore.loadHubReport(baseDir: hubBaseDir),
            runtimeMonitor: XHubDoctorOutputStore.loadHubLocalRuntimeMonitorSnapshot(baseDir: hubBaseDir),
            runtimeStatus: loadRuntimeStatus(baseDir: hubBaseDir)
        )
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func loadRuntimeStatus(baseDir: URL) -> AIRuntimeStatus? {
        AIRuntimeStatus.load(from: baseDir.appendingPathComponent("ai_runtime_status.json"))
    }
}

struct XTModelInventoryTruthCard: View {
    let presentation: XTModelInventoryTruthPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.headline)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)

            Text(presentation.summary)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !presentation.detail.isEmpty {
                Text(presentation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(stroke, lineWidth: 1)
        )
    }

    private var accent: Color {
        switch presentation.tone {
        case .neutral:
            return .accentColor
        case .caution:
            return .orange
        case .critical:
            return .red
        }
    }

    private var fill: Color {
        switch presentation.tone {
        case .neutral:
            return Color.accentColor.opacity(0.08)
        case .caution:
            return Color.orange.opacity(0.08)
        case .critical:
            return Color.red.opacity(0.08)
        }
    }

    private var stroke: Color {
        switch presentation.tone {
        case .neutral:
            return Color.accentColor.opacity(0.22)
        case .caution:
            return Color.orange.opacity(0.22)
        case .critical:
            return Color.red.opacity(0.22)
        }
    }
}
