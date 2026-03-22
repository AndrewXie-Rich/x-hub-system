import Foundation
import Testing
@testable import XTerminal

struct SupervisorConversationRepairActionPlannerTests {

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
                buttonTitle: "打开 Pair Progress",
                action: .openHubSetup(sectionId: "pair_progress")
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
