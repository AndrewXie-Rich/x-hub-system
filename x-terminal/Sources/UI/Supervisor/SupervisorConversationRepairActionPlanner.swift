import Foundation

enum SupervisorConversationRepairAction: Equatable {
    case openXTSettings(sectionId: String)
    case openHubSetup(sectionId: String)
    case openSystemPrivacy(target: XTSystemSettingsPrivacyTarget)
    case focusSupervisor
}

struct SupervisorConversationRepairActionPlan: Equatable {
    var buttonTitle: String
    var action: SupervisorConversationRepairAction
}

enum SupervisorConversationRepairActionPlanner {
    static func plan(
        for destination: UITroubleshootDestination,
        systemSettingsTarget: XTSystemSettingsPrivacyTarget = .voiceCapture
    ) -> SupervisorConversationRepairActionPlan {
        switch destination {
        case .xtPairHub:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 Pair Hub",
                action: .openXTSettings(sectionId: "pair_hub")
            )
        case .xtChooseModel:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 XT AI 模型",
                action: .openXTSettings(sectionId: "choose_model")
            )
        case .xtDiagnostics:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 XT Diagnostics",
                action: .openXTSettings(sectionId: "diagnostics")
            )
        case .hubPairing:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 Pair Progress",
                action: .openHubSetup(sectionId: "pair_progress")
            )
        case .hubLAN:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 Hub LAN (gRPC)",
                action: .openHubSetup(sectionId: "pair_progress")
            )
        case .hubModels:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 Hub 模型与付费访问",
                action: .openHubSetup(sectionId: "choose_model")
            )
        case .hubGrants, .hubSecurity, .hubDiagnostics:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 Hub Troubleshoot",
                action: .openHubSetup(sectionId: "troubleshoot")
            )
        case .systemPermissions:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: XTSystemSettingsLinks.buttonLabel(for: systemSettingsTarget),
                action: .openSystemPrivacy(target: systemSettingsTarget)
            )
        case .homeSupervisor:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: "回到 Supervisor",
                action: .focusSupervisor
            )
        }
    }
}
