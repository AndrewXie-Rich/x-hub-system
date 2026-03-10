import Foundation

enum NotificationSupport {
    // When running via `swift run` (SwiftPM executable), the process is not an app bundle.
    // On some macOS versions, calling UNUserNotificationCenter.current() will assert+abort.
    static var isAvailable: Bool {
        // Require an actual .app bundle.
        if Bundle.main.bundleURL.pathExtension.lowercased() != "app" {
            return false
        }
        guard let bid = Bundle.main.bundleIdentifier, !bid.isEmpty else {
            return false
        }
        return true
    }
}

