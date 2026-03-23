import Foundation
import Testing
@testable import XTerminal

struct XTSystemSettingsPrivacyTargetTests {

    @Test
    func calendarCandidatesIncludeLegacyAndExtensionForms() {
        let candidates = XTSystemSettingsPrivacyTarget.calendar.urlCandidates

        #expect(candidates.count == 3)
        #expect(candidates[0] == "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        #expect(candidates[1] == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars")
        #expect(candidates[2] == "x-apple.systempreferences:com.apple.PrivacySecurity.extension?Privacy_Calendars")
    }

    @Test
    func voiceCaptureCandidatesPreferSpeechRecognitionBeforeMicrophone() {
        let candidates = XTSystemSettingsPrivacyTarget.voiceCapture.urlCandidates

        #expect(candidates.count == 6)
        #expect(candidates.first?.contains("Privacy_SpeechRecognition") == true)
        #expect(candidates[2].contains("Privacy_SpeechRecognition"))
        #expect(candidates[3].contains("Privacy_Microphone"))
        #expect(candidates.last?.contains("Privacy_Microphone") == true)
    }

    @Test
    func microphoneCandidatesIncludeLegacyAndExtensionForms() {
        let candidates = XTSystemSettingsPrivacyTarget.microphone.urlCandidates

        #expect(candidates.count == 3)
        #expect(candidates[0] == "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        #expect(candidates[1] == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone")
        #expect(candidates[2] == "x-apple.systempreferences:com.apple.PrivacySecurity.extension?Privacy_Microphone")
    }
}
