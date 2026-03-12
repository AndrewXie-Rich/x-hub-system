import Foundation
import AppKit

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

    private static func openFirst(_ candidates: [String]) {
        for text in candidates {
            if let url = URL(string: text), NSWorkspace.shared.open(url) {
                return
            }
        }
        openSystemSettings()
    }
}
