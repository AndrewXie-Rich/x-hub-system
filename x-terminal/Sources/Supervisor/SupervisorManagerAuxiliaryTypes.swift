import Foundation

extension SupervisorManager {
    struct CanonicalMemoryRetryScope {
        var scopeKind: String
        var scopeId: String
        var displayName: String
    }

    enum SupervisorCalendarReminderActionIntent {
        case snoozeAfterMinutes(Int)
        case remindBeforeMeeting(Int)
        case remindAtMeetingStart(interruptConversation: Bool)
    }

    enum HeartbeatRouteRepairNotificationDestination {
        case routeDiagnose
        case modelSettings
        case xtDiagnostics
        case hubRecovery
        case hubConnectionLog

        var notificationTitle: String {
            switch self {
            case .routeDiagnose:
                return "🧭 Supervisor 心跳：模型路由异常，点我直接诊断"
            case .modelSettings:
                return "🧭 Supervisor 心跳：模型路由异常，建议先看 AI 模型"
            case .xtDiagnostics:
                return "🧭 Supervisor 心跳：模型路由异常，建议先看 XT Diagnostics"
            case .hubRecovery:
                return "🧭 Supervisor 心跳：模型路由异常，建议先看 Hub Recovery"
            case .hubConnectionLog:
                return "🧭 Supervisor 心跳：模型路由异常，建议先看 Hub 日志"
            }
        }

        var operationHint: String {
            switch self {
            case .routeDiagnose:
                return "点开这条提醒会直接进入项目聊天，并自动展开一条路由诊断摘要（等价于先去项目里看 `/route diagnose`）。"
            case .modelSettings:
                return "点开这条提醒会直接进入 Supervisor Control Center · AI 模型，先核对当前可用远端模型和这次实际选型。"
            case .xtDiagnostics:
                return "点开这条提醒会直接进入 XT Diagnostics，先看 XT 侧路由、降级原因和本地执行诊断。"
            case .hubRecovery:
                return "点开这条提醒会直接进入 Hub Recovery，先看 Hub 配对、远端导出和远端可达性。"
            case .hubConnectionLog:
                return "点开这条提醒会直接进入 Hub 日志，先核对最近的连接、掉线和路由降级记录。"
            }
        }
    }

    enum HeartbeatAuthorizationNotificationDestination {
        case grant
        case approval
        case toolApproval

        var operationHint: String {
            switch self {
            case .grant:
                return "点开这条提醒会直接进入项目授权处理，优先确认缺少的 grant / capability。"
            case .approval:
                return "点开这条提醒会直接进入项目审批处理，优先确认当前等待的人工批准。"
            case .toolApproval:
                return "点开这条提醒会直接进入工具审批处理，优先确认当前待执行的工具动作。"
            }
        }

        var defaultRecommendation: String {
            switch self {
            case .grant:
                return "打开项目并批准缺少的授权后，再继续推进。"
            case .approval:
                return "打开项目并处理待批准项后，再继续推进。"
            case .toolApproval:
                return "打开项目并审批待执行工具动作后，再继续推进。"
            }
        }
    }

    struct VoiceAuthorizationPromptScopeSummary {
        var fields: [String: String]
        var freeformSegments: [String]

        func value(for key: String) -> String? {
            let token = fields[key.lowercased()]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return token.isEmpty ? nil : token
        }

        var project: String? { value(for: "project") }
        var capability: String? { value(for: "capability") }
        var source: String? { value(for: "source") }
        var reason: String? { value(for: "reason") }
        var goal: String? { value(for: "goal") }
        var rawScope: String? {
            if let first = freeformSegments.first {
                let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
            return value(for: "scope")
        }
    }
}
