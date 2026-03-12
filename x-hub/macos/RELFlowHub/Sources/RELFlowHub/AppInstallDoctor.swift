import Foundation
import AppKit

@MainActor
enum AppInstallDoctor {
    private static let allowNonApplicationsKey = "relflowhub_allow_run_outside_applications"

    static func shouldWarn(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        // Allow dev workflows to run from the repo build directory without nagging.
        let p = bundleURL.path
        if p.contains("/build/X-Hub.app") || p.contains("/build/RELFlowHub.app") { return false }

        // Allow users to explicitly opt out (dev/testing).
        if UserDefaults.standard.bool(forKey: allowNonApplicationsKey) { return false }

        // App Translocation (quarantine) breaks stable permissions and makes paths confusing.
        if p.contains("/AppTranslocation/") { return true }

        // Running from a DMG mount is a common cause of repeated TCC prompts.
        if p.hasPrefix("/Volumes/") { return true }

        // Prefer /Applications (or ~/Applications) so TCC permissions remain stable.
        let homeApps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        if p.hasPrefix("/Applications/") || p.hasPrefix(homeApps + "/") { return false }

        return true
    }

    static func showInstallAlertIfNeeded() {
        guard shouldWarn() else { return }

        let p = Bundle.main.bundleURL.path

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Install X-Hub in Applications"
        alert.informativeText = "X-Hub is running from:\n\n\(p)\n\nFor stable Calendar/Accessibility permissions (avoid repeated prompts), drag X-Hub.app (and X-Hub Dock Agent.app / X-Hub Bridge.app) into /Applications, then relaunch from there."

        // Prefer offering to open the installed copy if it exists.
        let installedURL = installedCopyURL(bundleId: Bundle.main.bundleIdentifier ?? "")
        if let installedURL, installedURL.standardizedFileURL.path != Bundle.main.bundleURL.standardizedFileURL.path {
            alert.addButton(withTitle: "Open Installed Copy")
        } else {
            alert.addButton(withTitle: "Open Applications")
        }
        alert.addButton(withTitle: "Reveal This App")
        alert.addButton(withTitle: "Quit")

        let r = alert.runModal()
        switch r {
        case .alertFirstButtonReturn:
            if let installedURL, installedURL.standardizedFileURL.path != Bundle.main.bundleURL.standardizedFileURL.path {
                NSWorkspace.shared.open(installedURL)
                NSApp.terminate(nil)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        default:
            NSApp.terminate(nil)
        }
    }

    private static func installedCopyURL(bundleId: String) -> URL? {
        guard !bundleId.isEmpty else { return nil }

        // Fast path: LaunchServices lookup.
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return u
        }

        // Conservative fallback: common install name.
        let candidates = [
            URL(fileURLWithPath: "/Applications/X-Hub.app"),
            URL(fileURLWithPath: "/Applications/RELFlowHub.app"),
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
