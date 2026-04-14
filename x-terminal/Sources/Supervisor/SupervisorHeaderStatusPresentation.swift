import Foundation

enum SupervisorHeaderStatusTone: String, Equatable {
    case neutral
    case success
    case caution
    case warning
    case danger
}

struct SupervisorHeaderStatusBadge: Equatable {
    var text: String
    var tone: SupervisorHeaderStatusTone
    var helpText: String?
}

struct SupervisorHeaderStatusPresentation: Equatable {
    var text: String
    var tone: SupervisorHeaderStatusTone
    var detailBadge: SupervisorHeaderStatusBadge?
}

enum SupervisorHeaderStatusResolver {
    static func map(
        snapshot: AXRoleExecutionSnapshot,
        hubInteractive: Bool,
        latestRuntimeActivityText: String? = nil
    ) -> SupervisorHeaderStatusPresentation {
        let detailBadge = SupervisorVoiceDispatchPresentationResolver
            .map(latestRuntimeActivityText: latestRuntimeActivityText)
            .map { voiceDispatch in
                SupervisorHeaderStatusBadge(
                    text: voiceDispatch.text,
                    tone: voiceDispatch.headerTone,
                    helpText: voiceDispatch.helpText
                )
            }

        if snapshot.executionPath == "no_record" && !hubInteractive {
            return SupervisorHeaderStatusPresentation(
                text: "Hub 离线",
                tone: .danger,
                detailBadge: detailBadge
            )
        }

        return SupervisorHeaderStatusPresentation(
            text: statusText(snapshot: snapshot),
            tone: statusTone(snapshot: snapshot),
            detailBadge: detailBadge
        )
    }

    private static func statusText(
        snapshot: AXRoleExecutionSnapshot
    ) -> String {
        switch snapshot.executionPath {
        case "remote_model":
            return "远端"
        case "direct_provider":
            return "直连"
        case "hub_downgraded_to_local":
            return "已降级"
        case "local_fallback_after_remote_error":
            return "已回退"
        case "local_runtime":
            return "本地"
        case "local_preflight", "local_direct_reply", "local_direct_action", "hub_brief_projection":
            return "控制"
        case "remote_error":
            return "失败"
        default:
            return snapshot.hasRecord ? "已观测" : "待开始"
        }
    }

    private static func statusTone(
        snapshot: AXRoleExecutionSnapshot
    ) -> SupervisorHeaderStatusTone {
        switch snapshot.executionPath {
        case "remote_model", "direct_provider":
            return .success
        case "hub_downgraded_to_local", "local_fallback_after_remote_error":
            return .warning
        case "local_runtime":
            return .caution
        case "local_preflight", "local_direct_reply", "local_direct_action", "hub_brief_projection":
            return .caution
        case "remote_error":
            return .danger
        default:
            return .neutral
        }
    }
}
