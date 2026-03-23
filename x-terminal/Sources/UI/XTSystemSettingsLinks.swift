import Foundation
import AppKit

enum XTSystemSettingsPrivacyTarget: Equatable {
    case calendar
    case microphone
    case speechRecognition
    case voiceCapture

    var urlCandidates: [String] {
        switch self {
        case .calendar:
            return privacyCandidates(token: "Privacy_Calendars")
        case .microphone:
            return privacyCandidates(token: "Privacy_Microphone")
        case .speechRecognition:
            return privacyCandidates(token: "Privacy_SpeechRecognition")
        case .voiceCapture:
            return privacyCandidates(token: "Privacy_SpeechRecognition")
                + privacyCandidates(token: "Privacy_Microphone")
        }
    }

    private func privacyCandidates(token: String) -> [String] {
        [
            "x-apple.systempreferences:com.apple.preference.security?\(token)",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(token)",
            "x-apple.systempreferences:com.apple.PrivacySecurity.extension?\(token)",
        ]
    }
}

enum XTVoicePermissionRepairTargetResolver {
    static func resolve(
        microphone: VoiceTranscriberAuthorizationStatus,
        speechRecognition: VoiceTranscriberAuthorizationStatus
    ) -> XTSystemSettingsPrivacyTarget {
        let microphoneBlocked = microphone == .denied || microphone == .restricted
        let speechBlocked = speechRecognition == .denied || speechRecognition == .restricted

        if microphoneBlocked && speechBlocked {
            return .voiceCapture
        }
        if microphoneBlocked {
            return .microphone
        }
        if speechBlocked {
            return .speechRecognition
        }
        return .voiceCapture
    }
}

enum XTSystemSettingsLinks {
    static func openAccessibilityPrivacy() {
        openFirst([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.PrivacySecurity.extension?Privacy_Accessibility",
        ])
    }

    static func openAutomationPrivacy() {
        openFirst([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
            "x-apple.systempreferences:com.apple.PrivacySecurity.extension?Privacy_Automation",
        ])
    }

    static func openScreenRecordingPrivacy() {
        openFirst([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.PrivacySecurity.extension?Privacy_ScreenCapture",
        ])
    }

    static func openFullDiskAccessPrivacy() {
        openFirst([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.PrivacySecurity.extension?Privacy_AllFiles",
        ])
    }

    static func openInputMonitoringPrivacy() {
        openFirst([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.PrivacySecurity.extension?Privacy_ListenEvent",
        ])
    }

    static func openMicrophonePrivacy() {
        openPrivacy(.microphone)
    }

    static func openCalendarPrivacy() {
        openPrivacy(.calendar)
    }

    static func openSpeechRecognitionPrivacy() {
        openPrivacy(.speechRecognition)
    }

    static func openVoiceCapturePrivacy() {
        openPrivacy(.voiceCapture)
    }

    static func recommendedVoiceCaptureTarget() -> XTSystemSettingsPrivacyTarget {
        let snapshot = VoicePermissionSnapshotInspector.current()
        return XTVoicePermissionRepairTargetResolver.resolve(
            microphone: snapshot.microphone,
            speechRecognition: snapshot.speechRecognition
        )
    }

    static func buttonLabel(for target: XTSystemSettingsPrivacyTarget) -> String {
        switch target {
        case .calendar:
            return "打开日历权限"
        case .microphone:
            return "打开麦克风权限"
        case .speechRecognition:
            return "打开语音识别权限"
        case .voiceCapture:
            return "打开语音权限"
        }
    }

    static func openPrivacyAction(_ action: String) {
        switch action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case AXTrustedAutomationPermissionKey.accessibility.openSettingsAction:
            openAccessibilityPrivacy()
        case AXTrustedAutomationPermissionKey.automation.openSettingsAction:
            openAutomationPrivacy()
        case AXTrustedAutomationPermissionKey.screenRecording.openSettingsAction:
            openScreenRecordingPrivacy()
        case AXTrustedAutomationPermissionKey.fullDiskAccess.openSettingsAction:
            openFullDiskAccessPrivacy()
        case AXTrustedAutomationPermissionKey.inputMonitoring.openSettingsAction:
            openInputMonitoringPrivacy()
        default:
            openSystemSettings()
        }
    }

    static func label(forOpenSettingsAction action: String) -> String {
        switch action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case AXTrustedAutomationPermissionKey.accessibility.openSettingsAction:
            return "Open Accessibility"
        case AXTrustedAutomationPermissionKey.automation.openSettingsAction:
            return "Open Automation"
        case AXTrustedAutomationPermissionKey.screenRecording.openSettingsAction:
            return "Open Screen Recording"
        case AXTrustedAutomationPermissionKey.fullDiskAccess.openSettingsAction:
            return "Open Full Disk Access"
        case AXTrustedAutomationPermissionKey.inputMonitoring.openSettingsAction:
            return "Open Input Monitoring"
        default:
            return "Open System Settings"
        }
    }

    static func openSystemSettings() {
        let sys = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        if FileManager.default.fileExists(atPath: sys.path) {
            NSWorkspace.shared.open(sys)
            return
        }
        let legacy = URL(fileURLWithPath: "/System/Applications/System Preferences.app")
        if FileManager.default.fileExists(atPath: legacy.path) {
            NSWorkspace.shared.open(legacy)
            return
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.open(app)
        }
    }

    static func openPrivacy(_ target: XTSystemSettingsPrivacyTarget) {
        openFirst(target.urlCandidates)
    }

    private static func openFirst(_ candidates: [String]) {
        for text in candidates {
            if let url = URL(string: text), NSWorkspace.shared.open(url) {
                return
            }
        }
        openSystemSettings()
    }
}
