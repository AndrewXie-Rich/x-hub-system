import Foundation

extension SupervisorManager {
    func supervisorBriefProjectionBindingRequiredPresentation(
        projects: [AXProjectEntry]
    ) -> SupervisorBriefProjectionUnavailablePresentation {
        let header = "⚠️ Hub Brief 需要项目绑定"
        var lines = [
            header,
            "Hub 统一投影现在按项目生成；我需要你先选中项目，或者直接说项目名后再问一次状态。",
            "按当前 fail-closed 规则，我先不在 XT 本地即兴拼接 Supervisor brief。"
        ]
        let examples = projects
            .prefix(2)
            .map { "“\($0.displayName) 现在状态怎么样”" }
        if !examples.isEmpty {
            lines.append("你可以直接说：\(examples.joined(separator: " / "))。")
        }
        return SupervisorBriefProjectionUnavailablePresentation(
            text: lines.joined(separator: "\n"),
            script: [
                "要给你正式的 Hub 简报，我还需要先绑定项目。",
                examples.isEmpty
                    ? "你先选中项目，或者直接说项目名后再问一次状态。"
                    : "你先选中项目，或者直接说项目名，比如 \(examples[0])。"
            ],
            dedupeKey: "voice-query:hub-brief-binding-required:\(projects.count)"
        )
    }

    func supervisorBriefProjectionUnavailablePresentation(
        projectName: String,
        reasonCode: String?,
        localSignal: SupervisorGovernanceSignalVoicePresentation?,
        contextLines: [String] = [],
        contextScript: [String] = [],
        dedupePrefix: String = "voice-query"
    ) -> SupervisorBriefProjectionUnavailablePresentation {
        let displayProjectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "当前项目"
            : projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureSummary = supervisorBriefProjectionFailureSummary(reasonCode)
        let repairAction = supervisorBriefProjectionFailureRepairAction(reasonCode)
        let normalizedReason = HubRouteStateMachine.normalizedReasonToken(reasonCode) ?? "hub_brief_unavailable"
        let header = "⚠️ Hub Brief 暂不可用 · \(displayProjectName)"

        let sanitizedContextLines = contextLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var lines = [header] + sanitizedContextLines + [
            "这次没有拿到 Hub 统一投影：\(failureSummary)。",
            "按当前 fail-closed 规则，我先不在 XT 本地即兴拼接 Supervisor brief。"
        ]

        if let localSignal,
           !localSignal.headlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("XT 本地信号：\(localSignal.headlineText)。")
            let action = localSignal.actionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !action.isEmpty {
                lines.append("你现在可以先：\(action)。")
            } else {
                lines.append(repairAction)
            }
        } else {
            lines.append(repairAction)
        }

        let sanitizedContextScript = contextScript
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var script = sanitizedContextScript + [
            "Hub 简报当前不可用。\(failureSummary)。",
            repairAction
        ]
        if let localSignal,
           !localSignal.headlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let action = localSignal.actionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            script = sanitizedContextScript + [
                "Hub 简报当前不可用。\(failureSummary)。",
                !action.isEmpty
                    ? "XT 本地信号提示你先：\(action)。"
                    : repairAction
            ]
        }

        return SupervisorBriefProjectionUnavailablePresentation(
            text: lines.joined(separator: "\n"),
            script: script,
            dedupeKey: "\(dedupePrefix):hub-brief-unavailable:\(displayProjectName):\(normalizedReason)"
        )
    }

    func supervisorBriefProjectionFailureSummary(_ reasonCode: String?) -> String {
        switch HubRouteStateMachine.normalizedReasonToken(reasonCode) {
        case "synchronous_projection_fetch_required":
            return "当前这条本地直答链还没接上 Hub 简报投影查询"
        case "hub_env_missing":
            return "当前 Hub 配对或运行时档案不可用"
        case "supervisor_brief_projection_file_ipc_not_supported":
            return "当前仍在本地 file route，Hub brief 投影还没接上"
        case "client_kit_missing":
            return "Hub client kit 还没准备好"
        case "node_missing":
            return "Hub brief bridge 缺少 Node 运行时"
        case "grpc_route_unavailable",
             "grpc_unavailable",
             "remote_supervisor_brief_projection_failed",
             "supervisor_brief_projection_failed",
             "projection_unavailable":
            return "Hub 没有返回这次统一简报"
        default:
            if let token = HubRouteStateMachine.normalizedReasonToken(reasonCode) {
                if token.contains("timeout") || token.contains("connect") || token.contains("unavailable") {
                    return "Hub 路由当前不可达"
                }
                return "Hub brief 投影失败（\(token)）"
            }
            return "Hub 没有返回这次统一简报"
        }
    }

    func supervisorBriefProjectionFailureRepairAction(_ reasonCode: String?) -> String {
        switch HubRouteStateMachine.normalizedReasonToken(reasonCode) {
        case "synchronous_projection_fetch_required":
            return "等 Hub brief 投影查询链接上后再问一次状态；当前我不会在 XT 本地补写这份简报。"
        case "hub_env_missing":
            return "先修复 Hub 配对或运行 doctor / repair，再重新问一次状态。"
        case "supervisor_brief_projection_file_ipc_not_supported":
            return "先切回可用的 Hub pairing route，再重新问一次状态。"
        case "client_kit_missing", "node_missing":
            return "先修复 Hub 本地 runtime / bridge，再重新问一次状态。"
        default:
            return "先打开 Hub Diagnostics & Recovery 检查路由，再重新问一次状态。"
        }
    }
}
