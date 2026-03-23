import Foundation
import Testing
@testable import XTerminal

struct XTVoicePermissionRepairTargetResolverTests {

    @Test
    func microphoneDeniedMapsToMicrophoneTarget() {
        let target = XTVoicePermissionRepairTargetResolver.resolve(
            microphone: .denied,
            speechRecognition: .authorized
        )

        #expect(target == .microphone)
    }

    @Test
    func speechRecognitionDeniedMapsToSpeechRecognitionTarget() {
        let target = XTVoicePermissionRepairTargetResolver.resolve(
            microphone: .authorized,
            speechRecognition: .denied
        )

        #expect(target == .speechRecognition)
    }

    @Test
    func bothDeniedMapToCombinedVoiceCaptureTarget() {
        let target = XTVoicePermissionRepairTargetResolver.resolve(
            microphone: .restricted,
            speechRecognition: .denied
        )

        #expect(target == .voiceCapture)
    }

    @Test
    func healthyStatusesFallBackToCombinedVoiceCaptureTarget() {
        let target = XTVoicePermissionRepairTargetResolver.resolve(
            microphone: .authorized,
            speechRecognition: .undetermined
        )

        #expect(target == .voiceCapture)
    }
}
