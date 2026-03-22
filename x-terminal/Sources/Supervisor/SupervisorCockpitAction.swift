import Foundation

enum SupervisorCockpitAction: Equatable {
    case primary(PrimaryActionRailAction)
    case runtimeStage(SupervisorRuntimeStageItemPresentation)
}

enum SupervisorCockpitActionResolver {
    struct Context: Equatable {
        var inputText: String
        var reviewReportPath: String?
        var replayEvidencePath: String?
        var firstPendingGrantActionURL: String?
        var firstPendingSkillApprovalActionURL: String?
        var runtimeAccessSurfaceState: XTUISurfaceState?
        var directedUnblockBaton: DirectedUnblockBaton?
    }

    enum URLTarget: Equatable {
        case absolute(String)
        case filePath(String)
    }

    enum Effect: Equatable {
        case setInputText(String)
        case requestConversationFocus
        case refreshPendingHubGrants
        case refreshSupervisorDoctorReport
        case presentWindowSheet(SupervisorManager.SupervisorWindowSheet)
        case openURL(URLTarget)
        case openWindow(String)
        case setFocusedSplitLane(String)
    }

    struct Plan: Equatable {
        var effects: [Effect]
    }

    private static let defaultIntakeDraft =
        "请开始一个复杂任务：目标 / 约束 / 交付物 / 风险"
    private static let fallbackDirectedResumeDraft =
        "请先说明当前 blocker 和目标 lane，再决定是否继续当前任务。"

    static func resolve(
        _ action: SupervisorCockpitAction,
        context: Context
    ) -> Plan? {
        switch action {
        case .primary(let primaryAction):
            return resolveActionID(primaryAction.id, context: context)
        case .runtimeStage(let item):
            guard let actionID = normalizedScalar(item.actionID) else { return nil }
            return resolveActionID(actionID, context: context)
        }
    }

    private static func resolveActionID(
        _ actionID: String,
        context: Context
    ) -> Plan? {
        switch actionID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "submit_intake":
            return submitIntake(context: context)
        case "approve_risk":
            return Plan(effects: [.refreshPendingHubGrants])
        case "review_delivery":
            return reviewDelivery(context: context)
        case "resolve_access":
            return resolveAccess(context: context)
        case "directed_resume":
            return directedResume(context: context)
        default:
            return nil
        }
    }

    private static func submitIntake(context: Context) -> Plan {
        var effects: [Effect] = []
        if normalizedScalar(context.inputText) == nil {
            effects.append(.setInputText(defaultIntakeDraft))
        }
        effects.append(.requestConversationFocus)
        return Plan(effects: effects)
    }

    private static func reviewDelivery(context: Context) -> Plan {
        if let replayEvidencePath = normalizedScalar(context.replayEvidencePath) {
            return Plan(effects: [.openURL(.filePath(replayEvidencePath))])
        }
        if let reviewReportPath = normalizedScalar(context.reviewReportPath) {
            return Plan(effects: [.openURL(.filePath(reviewReportPath))])
        }
        return Plan(effects: [.refreshSupervisorDoctorReport])
    }

    private static func resolveAccess(context: Context) -> Plan {
        if let grantActionURL = normalizedScalar(context.firstPendingGrantActionURL) {
            return Plan(effects: [.openURL(.absolute(grantActionURL))])
        }
        if let approvalActionURL = normalizedScalar(context.firstPendingSkillApprovalActionURL) {
            return Plan(effects: [.openURL(.absolute(approvalActionURL))])
        }

        switch context.runtimeAccessSurfaceState {
        case .permissionDenied:
            return Plan(effects: [.presentWindowSheet(.modelSettings)])
        case .grantRequired:
            return Plan(effects: [.refreshPendingHubGrants, .openWindow("hub_setup")])
        default:
            return Plan(effects: [.openWindow("hub_setup")])
        }
    }

    private static func directedResume(context: Context) -> Plan {
        guard let baton = context.directedUnblockBaton else {
            return Plan(
                effects: [
                    .setInputText(fallbackDirectedResumeDraft),
                    .requestConversationFocus
                ]
            )
        }

        let laneID = normalizedScalar(baton.blockedLane)
        let draft = [
            "请只继续当前任务，不要扩 scope，不要 claim 新 lane。",
            laneID.map { "目标 lane=\($0)。" },
            "next_action=\(baton.nextAction)。",
            baton.mustNotDo.isEmpty ? nil : "must_not_do=\(baton.mustNotDo.joined(separator: ","))。",
            "基于现有 directed unblock baton 续推，并显式汇报 blocker 是否已解除。"
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        var effects: [Effect] = []
        if let laneID {
            effects.append(.setFocusedSplitLane(laneID))
        }
        effects.append(.setInputText(draft))
        effects.append(.requestConversationFocus)
        return Plan(effects: effects)
    }

    private static func normalizedScalar(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
