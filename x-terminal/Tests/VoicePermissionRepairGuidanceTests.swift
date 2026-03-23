import Foundation
import Testing
@testable import XTerminal

struct VoicePermissionRepairGuidanceTests {

    @Test
    func speechRecognitionOnlyGuidanceIsSpecific() {
        let guidance = VoicePermissionRepairGuidance.build(
            snapshot: VoicePermissionSnapshot(
                microphone: .authorized,
                speechRecognition: .denied
            ),
            fallbackAuthorizationStatus: .denied
        )

        #expect(guidance.blockedSurfaceLabel == "语音识别权限")
        #expect(guidance.nextStep == "请先在 macOS 系统设置中授予语音识别权限，然后刷新语音运行时。")
    }

    @Test
    func microphoneOnlyGuidanceIsSpecific() {
        let guidance = VoicePermissionRepairGuidance.build(
            snapshot: VoicePermissionSnapshot(
                microphone: .restricted,
                speechRecognition: .authorized
            ),
            fallbackAuthorizationStatus: .restricted
        )

        #expect(guidance.blockedSurfaceLabel == "麦克风权限")
        #expect(guidance.settingsGuidance == "请先在 macOS 系统设置中授予麦克风权限，再重试语音采集。")
    }

    @Test
    func combinedGuidanceFallsBackToBothPermissions() {
        let guidance = VoicePermissionRepairGuidance.build(
            snapshot: VoicePermissionSnapshot(
                microphone: .denied,
                speechRecognition: .denied
            ),
            fallbackAuthorizationStatus: .denied
        )

        #expect(guidance.blockedSurfaceLabel == "麦克风或语音识别权限")
        #expect(guidance.nextStep == "请先在 macOS 系统设置中授予麦克风和语音识别权限，然后刷新语音运行时。")
    }
}
