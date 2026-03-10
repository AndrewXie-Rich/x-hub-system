import Foundation

/// Counts-only integrations via AppleScript (Apple Events).
///
/// This is an offline fallback for cases where reading Dock badges via Accessibility
/// is not possible (e.g. Dock AX hierarchy changes on newer macOS versions).
///
/// NOTE: In App Sandbox this requires the `com.apple.security.automation.apple-events`
/// entitlement and will prompt the user for Automation permission.
@MainActor
enum AppleScriptCountsReader {
    struct Result {
        var ok: Bool
        var count: Int
        var debug: String
    }

    static func mailUnreadCount() -> Result {
        // Prefer a simple unread count from the Inbox.
        // If that fails (multi-account setups), fall back to summing account inboxes.
        let script = """
tell application "Mail"
    set theCount to 0
    try
        set theCount to unread count of inbox
    on error
        try
            repeat with a in every account
                try
                    set theCount to theCount + unread count of inbox of a
                end try
            end repeat
        end try
    end try
    return theCount
end tell
"""
        return runInt(script: script, label: "mail_applescript")
    }

    static func messagesUnreadCount() -> Result {
        // Messages AppleScript support varies by macOS version and can be unreliable.
        // Keep this best-effort and avoid syntax that collides with the built-in `count` command.
        let script = """
tell application "Messages"
    set c to 0
    try
        set c to count of (every text chat whose unread is true)
    end try
    return c
end tell
"""
        return runInt(script: script, label: "messages_applescript")
    }

    private static func runInt(script: String, label: String) -> Result {
        let src = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else {
            return Result(ok: false, count: 0, debug: "\(label):empty_script")
        }

        guard let ascr = NSAppleScript(source: src) else {
            return Result(ok: false, count: 0, debug: "\(label):init_failed")
        }

        var err: NSDictionary?
        let out = ascr.executeAndReturnError(&err)
        if let err {
            let msg = (err[NSAppleScript.errorMessage] as? String) ?? "(no message)"
            let num = (err[NSAppleScript.errorNumber] as? Int) ?? 0
            return Result(ok: false, count: 0, debug: "\(label):err=\(num) \(msg)")
        }

        // Descriptor could be int or a string.
        let n: Int? = {
            // Most scripts return a 32-bit integer.
            if out.descriptorType == typeSInt32 {
                return Int(out.int32Value)
            }
            if let s = out.stringValue {
                return Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return nil
        }()

        if let n {
            return Result(ok: true, count: max(0, n), debug: "\(label):ok")
        }
        return Result(ok: false, count: 0, debug: "\(label):bad_return_type")
    }
}
