import Foundation
import AppKit

@MainActor
enum AppInstallDoctor {
    private static let allowNonApplicationsKey = "relflowhub_allow_run_outside_applications"
    private static let canonicalAppBundleName = "X-Hub.app"
    private static let canonicalApplicationsPath = "/Applications/X-Hub.app"

    static func shouldWarn(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        let standardizedURL = bundleURL.standardizedFileURL
        let p = standardizedURL.path

        // Allow dev workflows to run the current build product without nagging.
        if standardizedURL.lastPathComponent == canonicalAppBundleName,
           p.contains("/build/\(canonicalAppBundleName)") {
            return false
        }

        // Allow users to explicitly opt out (dev/testing).
        if UserDefaults.standard.bool(forKey: allowNonApplicationsKey) { return false }

        // App Translocation (quarantine) breaks stable permissions and makes paths confusing.
        if p.contains("/AppTranslocation/") { return true }

        // Running from a DMG mount is a common cause of repeated TCC prompts.
        if p.hasPrefix("/Volumes/") { return true }

        // Prefer the canonical app name in /Applications (or ~/Applications) so
        // TCC permissions and helper process paths remain stable.
        if isCanonicalApplicationsInstall(standardizedURL) { return false }

        return true
    }

    static func showInstallAlertIfNeeded() {
        guard shouldWarn() else { return }

        let p = Bundle.main.bundleURL.path
        HubDiagnostics.log("app.install_doctor alert_shown path=\(p)")

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = HubUIStrings.InstallDoctor.title
        alert.informativeText = HubUIStrings.InstallDoctor.currentLocation(p)

        // Prefer offering to open the installed copy if it exists.
        let installedURL = installedCopyURL(bundleId: Bundle.main.bundleIdentifier ?? "")
        if let installedURL, installedURL.standardizedFileURL.path != Bundle.main.bundleURL.standardizedFileURL.path {
            alert.addButton(withTitle: HubUIStrings.InstallDoctor.openInstalledCopy)
        } else {
            alert.addButton(withTitle: HubUIStrings.InstallDoctor.openApplications)
        }
        alert.addButton(withTitle: HubUIStrings.InstallDoctor.revealCurrentApp)
        alert.addButton(withTitle: HubUIStrings.InstallDoctor.quit)

        let r = alert.runModal()
        switch r {
        case .alertFirstButtonReturn:
            HubDiagnostics.log("app.install_doctor choice=primary")
            if let installedURL, installedURL.standardizedFileURL.path != Bundle.main.bundleURL.standardizedFileURL.path {
                NSWorkspace.shared.open(installedURL)
                NSApp.terminate(nil)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
            }
        case .alertSecondButtonReturn:
            HubDiagnostics.log("app.install_doctor choice=reveal_current")
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        default:
            HubDiagnostics.log("app.install_doctor choice=quit")
            NSApp.terminate(nil)
        }
    }

    private static func installedCopyURL(bundleId: String) -> URL? {
        guard !bundleId.isEmpty else { return nil }

        // Fast path: LaunchServices lookup.
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let standardizedURL = u.standardizedFileURL
            if isCanonicalApplicationsInstall(standardizedURL) {
                return standardizedURL
            }
        }

        // Conservative fallback: canonical install name only. The historical
        // RELFlowHub.app path is intentionally not treated as an installed copy.
        let candidates = [
            URL(fileURLWithPath: canonicalApplicationsPath),
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func isCanonicalApplicationsInstall(_ url: URL) -> Bool {
        guard url.lastPathComponent == canonicalAppBundleName else { return false }

        let p = url.path
        if p == canonicalApplicationsPath { return true }

        let homeApps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        return p == (homeApps as NSString).appendingPathComponent(canonicalAppBundleName)
    }
}
