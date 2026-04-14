import Foundation
import Testing
@testable import XTerminal

struct SupervisorConversationRepairActionPlannerTests {
    @Test
    func xtChooseModelMapsToSupervisorControlCenterModelTab() {
        let plan = SupervisorConversationRepairActionPlanner.plan(for: .xtChooseModel)

        #expect(
            plan == SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 AI 模型设置",
                action: .openSupervisorControlCenter(sheet: .modelSettings)
            )
        )
    }

    @Test
    func xtDiagnosticsMapsToSettingsDiagnosticsSection() {
        let plan = SupervisorConversationRepairActionPlanner.plan(for: .xtDiagnostics)

        #expect(
            plan == SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 XT Diagnostics",
                action: .openXTSettings(sectionId: "diagnostics")
            )
        )
    }

    @Test
    func systemPermissionsMapsToVoiceCapturePrivacyAction() {
        let plan = SupervisorConversationRepairActionPlanner.plan(for: .systemPermissions)

        #expect(
            plan == SupervisorConversationRepairActionPlan(
                buttonTitle: "打开语音权限",
                action: .openSystemPrivacy(target: .voiceCapture)
            )
        )
    }

    @Test
    func systemPermissionsCanMapToMicrophonePrivacyAction() {
        let plan = SupervisorConversationRepairActionPlanner.plan(
            for: .systemPermissions,
            systemSettingsTarget: .microphone
        )

        #expect(
            plan == SupervisorConversationRepairActionPlan(
                buttonTitle: "打开麦克风权限",
                action: .openSystemPrivacy(target: .microphone)
            )
        )
    }

    @Test
    func systemPermissionsCanMapToSpeechRecognitionPrivacyAction() {
        let plan = SupervisorConversationRepairActionPlanner.plan(
            for: .systemPermissions,
            systemSettingsTarget: .speechRecognition
        )

        #expect(
            plan == SupervisorConversationRepairActionPlan(
                buttonTitle: "打开语音识别权限",
                action: .openSystemPrivacy(target: .speechRecognition)
            )
        )
    }

    @Test
    func hubPairingMapsToHubSetupPairProgress() {
        let plan = SupervisorConversationRepairActionPlanner.plan(for: .hubPairing)

        #expect(
            plan == SupervisorConversationRepairActionPlan(
                buttonTitle: "打开连接进度",
                action: .openHubSetup(sectionId: "pair_progress")
            )
        )
    }

    @Test
    func hubModelsMapsToHubChooseModelSectionWithClearerLabel() {
        let plan = SupervisorConversationRepairActionPlanner.plan(for: .hubModels)

        #expect(
            plan == SupervisorConversationRepairActionPlan(
                buttonTitle: "打开 Hub 模型与付费访问",
                action: .openHubSetup(sectionId: "choose_model")
            )
        )
    }

    @Test
    func homeSupervisorMapsToFocusSupervisorAction() {
        let plan = SupervisorConversationRepairActionPlanner.plan(for: .homeSupervisor)

        #expect(
            plan == SupervisorConversationRepairActionPlan(
                buttonTitle: "回到 Supervisor",
                action: .focusSupervisor
            )
        )
    }
}
