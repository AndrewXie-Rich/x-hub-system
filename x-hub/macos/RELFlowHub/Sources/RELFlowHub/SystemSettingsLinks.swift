import Foundation
import AppKit

/// Best-effort deep-links into macOS System Settings pages.
/// Apple changes these identifiers across OS releases, so we try a few.
enum SystemSettingsLinks {
    static func openAccessibilityPrivacy() {
        openFirst([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.PrivacySecurity.extension?Privacy_Accessibility",
        ])
    }

    static func openCalendarPrivacy() {
        openFirst([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.PrivacySecurity.extension?Privacy_Calendars",
        ])
    }

    static func openSystemSettings() {
        let sys = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        if FileManager.default.fileExists(atPath: sys.path) {
            NSWorkspace.shared.open(sys)
            return
        }
        // Legacy name.
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
        for s in candidates {
            if let u = URL(string: s), NSWorkspace.shared.open(u) {
                return
            }
        }
        openSystemSettings()
    }
}
