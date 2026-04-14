import Foundation

enum SupervisorConversationRepairAction: Equatable {
    case openXTSettings(sectionId: String)
    case openSupervisorControlCenter(sheet: SupervisorManager.SupervisorWindowSheet)
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
                buttonTitle: "打开连接 Hub",
                action: .openXTSettings(sectionId: "pair_hub")
            )
        case .xtChooseModel:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 AI 模型设置",
                action: .openSupervisorControlCenter(sheet: .modelSettings)
            )
        case .xtDiagnostics:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 XT Diagnostics",
                action: .openXTSettings(sectionId: "diagnostics")
            )
        case .hubPairing:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: "打开连接进度",
                action: .openHubSetup(sectionId: "pair_progress")
            )
        case .hubLAN:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 Hub 网络连接",
                action: .openHubSetup(sectionId: "pair_progress")
            )
        case .hubModels:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 Hub 模型与付费访问",
                action: .openHubSetup(sectionId: "choose_model")
            )
        case .hubGrants, .hubSecurity, .hubDiagnostics:
            return SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 Hub 排障",
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
