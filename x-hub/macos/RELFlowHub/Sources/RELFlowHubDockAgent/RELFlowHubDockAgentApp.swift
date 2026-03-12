import AppKit
import Foundation
import ApplicationServices
import RELFlowHubCore

private func writeStatusForHubBestEffort(autoStartInstalled: Bool, autoStartLoaded: Bool) {
    guard let paths = HubIPC.findHubPaths() else { return }
    let ver = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
    let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
    let appPath = Bundle.main.bundleURL.path
    let ax = AXIsProcessTrusted()

    let st = DockAgentStatus(
        updatedAt: Date().timeIntervalSince1970,
        pid: getpid(),
        appVersion: ver,
        appBuild: build,
        appPath: appPath,
        axTrusted: ax,
        autoStartInstalled: autoStartInstalled,
        autoStartLoaded: autoStartLoaded
    )
    let url = paths.baseDir.appendingPathComponent("dock_agent_status.json")
    if let data = try? JSONEncoder().encode(st) {
        try? data.write(to: url, options: .atomic)
    }
}

// A tiny AppKit-based agent (LSUIElement=true) so we can request Accessibility permission.
// We implement an explicit NSApplication main because `@main` on an NSApplicationDelegate
// alone does not start the AppKit run loop.

@main
struct RELFlowHubDockAgentMain {
    static func main() {
        // Support one-shot management commands invoked by the Hub UI.
        // This keeps the Hub sandboxed (it just opens this app), while the non-sandboxed
        // Dock Agent performs LaunchAgent install/uninstall.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--install-launchagent") {
            let st = DockAgentAutoStart.installAndLoad()
            writeStatusForHubBestEffort(autoStartInstalled: st.installed, autoStartLoaded: st.loaded)
            print("dockagent autostart install installed=\(st.installed) loaded=\(st.loaded) plist=\(st.plistPath) dbg=\(st.debug)")
            exit(0)
        }
        if args.contains("--uninstall-launchagent") {
            let st = DockAgentAutoStart.unloadAndRemove()
            writeStatusForHubBestEffort(autoStartInstalled: st.installed, autoStartLoaded: st.loaded)
            print("dockagent autostart uninstall installed=\(st.installed) loaded=\(st.loaded) plist=\(st.plistPath) dbg=\(st.debug)")
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = RELFlowHubDockAgentApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class RELFlowHubDockAgentApp: NSObject, NSApplicationDelegate {
    private var pollTimer: Timer?
    private var promptedAX: Bool = false

    private let pollIntervalSec: Double = 60.0

    // Apps we can read counts from via Dock badges.
    private let targets: [(source: String, bundleId: String, dedupeKey: String)] = [
        ("Slack", "com.tinyspeck.slackmacgap", "slack_updates"),
        ("Mail", "com.apple.mail", "mail_unread"),
        ("Messages", "com.apple.MobileSMS", "messages_unread"),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let ver = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "(unknown)"
        log("start pid=\(getpid()) v=\(ver)")

        // Poll on a timer so this can run as a LaunchAgent.
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollIntervalSec, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        tick()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func tick() {
        // Write a small status file into the Hub base directory so the Hub can show
        // Dock Agent health and auto-start state in Doctor.
        writeStatusFileBestEffort()

        // Ensure Accessibility permission. Prompt only once; avoid spamming prompts.
        if !DockAX.ensureTrusted(prompt: !promptedAX) {
            promptedAX = true
            log("AXTrusted=false (grant Accessibility to X-Hub Dock Agent.app)")
            return
        }
        promptedAX = true

        guard let paths = HubIPC.findHubPaths() else {
            log("Hub IPC not found (hub_status.json missing). Is X-Hub running?")
            return
        }

        for t in targets {
            let r = DockBadgeReader.badgeCountForBundleId(t.bundleId)
            if !r.ok {
                log("\(t.source): error \(r.debug)")
                continue
            }
            // Always push; Hub will dedupe and apply baseline logic.
            let body: String = {
                // Slack sometimes uses a dot badge for "has activity" with no numeric count.
                if t.dedupeKey == "slack_updates", r.debug.hasPrefix("badge_dot") {
                    return "1 update"
                }
                return "\(max(0, r.count)) unread"
            }()
            HubIPC.pushCountsOnly(
                ipcEventsDir: paths.ipcEventsDir,
                source: t.source,
                bundleId: t.bundleId,
                body: body,
                dedupeKey: t.dedupeKey,
                debug: r.debug
            )
            log("push \(t.source) body=\(body) dbg=\(r.debug)")
        }
    }

    private func writeStatusFileBestEffort() {
        guard let paths = HubIPC.findHubPaths() else { return }

        let ver = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        let appPath = Bundle.main.bundleURL.path

        let ax = AXIsProcessTrusted()
        let asSt = DockAgentAutoStart.status()

        let st = DockAgentStatus(
            updatedAt: Date().timeIntervalSince1970,
            pid: getpid(),
            appVersion: ver,
            appBuild: build,
            appPath: appPath,
            axTrusted: ax,
            autoStartInstalled: asSt.installed,
            autoStartLoaded: asSt.loaded
        )
        let url = paths.baseDir.appendingPathComponent("dock_agent_status.json")
        if let data = try? JSONEncoder().encode(st) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func log(_ s: String) {
        let home = SharedPaths.realHomeDirectory()
        let dir = home.appendingPathComponent("RELFlowHub", isDirectory: true)
        let url = dir.appendingPathComponent("dock_agent.log")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(s)\n"
        if let data = line.data(using: .utf8) {
            if let fh = try? FileHandle(forWritingTo: url) {
                try? fh.seekToEnd()
                try? fh.write(contentsOf: data)
                try? fh.close()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}

// MARK: - Hub IPC

private enum HubIPC {
    private struct HubStatus: Codable {
        var updatedAt: Double
        var ipcPath: String
        var baseDir: String

        enum CodingKeys: String, CodingKey {
            case updatedAt
            case ipcPath
            case baseDir
        }
    }

    struct HubPaths {
        var baseDir: URL
        var ipcEventsDir: URL
    }

    static func findHubPaths() -> HubPaths? {
        let home = SharedPaths.realHomeDirectory()
        // IMPORTANT: Avoid directly probing the App Group path on ad-hoc / unsigned builds.
        // On some macOS versions this can trigger repeated "would like to access data from other apps" prompts.
        let group = SharedPaths.appGroupDirectory()
        let tmp = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("RELFlowHub", isDirectory: true)
        let tmp2 = URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent("RELFlowHub", isDirectory: true)
        let candidates: [URL] = [
            // Signed builds: App Group base dir.
            group,
            // Preferred shared tmp contract.
            tmp,
            tmp2,
            // Sandboxed Hub default.
            home.appendingPathComponent("Library/Containers/com.rel.flowhub/Data/RELFlowHub", isDirectory: true),
            // Legacy/dev fallback.
            home.appendingPathComponent("RELFlowHub", isDirectory: true),
        ].compactMap { $0 }

        var best: (st: HubStatus, base: URL, ipc: URL)?
        for base in candidates {
            let f = base.appendingPathComponent("hub_status.json")
            guard FileManager.default.fileExists(atPath: f.path),
                  let data = try? Data(contentsOf: f),
                  let st = try? JSONDecoder().decode(HubStatus.self, from: data) else {
                continue
            }
            let baseDir = URL(fileURLWithPath: st.baseDir, isDirectory: true)
            let ipcDir = URL(fileURLWithPath: st.ipcPath, isDirectory: true)
            if best == nil || st.updatedAt > best!.st.updatedAt {
                best = (st, baseDir, ipcDir)
            }
        }
        guard let best else { return nil }
        return HubPaths(baseDir: best.base, ipcEventsDir: best.ipc)
    }

    static func pushCountsOnly(ipcEventsDir: URL, source: String, bundleId: String, body: String, dedupeKey: String, debug: String) {
        let now = Date().timeIntervalSince1970
        let action = "relflowhub://openapp?bundle_id=\(bundleId)"
        let n = HubNotification(
            id: UUID().uuidString,
            source: source,
            title: source,
            body: body,
            createdAt: now,
            dedupeKey: dedupeKey,
            actionURL: action,
            snoozedUntil: nil,
            unread: true
        )
        let req = IPCRequest(type: "push_notification", reqId: UUID().uuidString, notification: n)

        do {
            try FileManager.default.createDirectory(at: ipcEventsDir, withIntermediateDirectories: true)
            let file = ipcEventsDir.appendingPathComponent("dock_\(Int(now))_\(UUID().uuidString).json")
            let data = try JSONEncoder().encode(req)
            try data.write(to: file, options: .atomic)
        } catch {
            // Best effort; drop.
        }
    }
}

private struct DockAgentStatus: Codable {
    var updatedAt: Double
    var pid: Int32
    var appVersion: String
    var appBuild: String
    var appPath: String
    var axTrusted: Bool
    var autoStartInstalled: Bool
    var autoStartLoaded: Bool
}

// MARK: - Accessibility helpers

private enum DockAX {
    @MainActor
    static func ensureTrusted(prompt: Bool) -> Bool {
        if prompt {
            NSApp.activate(ignoringOtherApps: true)
            let opts = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        return AXIsProcessTrusted()
    }
}

// MARK: - Dock badge reader (non-sandboxed)

private enum DockBadgeReader {
    struct Result {
        var ok: Bool
        var count: Int
        var debug: String
    }

    static func badgeCountForBundleId(_ bundleId: String) -> Result {
        guard !bundleId.isEmpty else {
            return Result(ok: false, count: 0, debug: "empty_bundle_id")
        }

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
        let wantName = running?.localizedName ?? displayNameForBundleId(bundleId) ?? bundleId
        let wantURL = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)

        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return Result(ok: false, count: 0, debug: "dock_not_running")
        }
        let dock = AXUIElementCreateApplication(dockApp.processIdentifier)

        guard let item = findDockItem(root: dock, wantName: wantName, wantBundleId: bundleId, wantURL: wantURL, depth: 0, maxDepth: 24) else {
            let urlStr = wantURL?.standardizedFileURL.path ?? "(nil)"
            let runStr = (running != nil) ? "true" : "false"
            let childCount = copyChildren(dock).count
            return Result(ok: true, count: 0, debug: "dock_item_not_found:name=\(wantName) running=\(runStr) url=\(urlStr) dockChildren=\(childCount)")
        }

        if let found = findBadgeText(in: item, maxDepth: 10) {
            let trimmed = found.trimmingCharacters(in: .whitespacesAndNewlines)
            if let n = Int(trimmed) {
                return Result(ok: true, count: max(0, n), debug: "badge_text:\(trimmed)")
            }
            if let n = firstInt(in: trimmed) {
                return Result(ok: true, count: max(0, n), debug: "badge_parse:\(trimmed)")
            }

            // Some apps (notably Slack) can show a dot badge to indicate activity.
            let dots: Set<String> = ["•", "●", "∙", "·"]
            if dots.contains(trimmed) {
                return Result(ok: true, count: 1, debug: "badge_dot:\(trimmed)")
            }

            return Result(ok: true, count: 0, debug: "badge_text_no_int:\(trimmed)")
        }

        return Result(ok: true, count: 0, debug: "no_badge_found")
    }

    private static func displayNameForBundleId(_ bundleId: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        if let b = Bundle(url: url) {
            let dn = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let dn, !dn.isEmpty { return dn }
            let bn = (b.object(forInfoDictionaryKey: "CFBundleName") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let bn, !bn.isEmpty { return bn }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private static func firstInt(in s: String) -> Int? {
        var digits = ""
        for ch in s {
            if ch.isNumber {
                digits.append(ch)
            } else if !digits.isEmpty {
                break
            }
        }
        return digits.isEmpty ? nil : Int(digits)
    }

    private static func copyStringAttr(_ el: AXUIElement, _ name: String) -> String? {
        var v: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, name as CFString, &v)
        if err != .success {
            return nil
        }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    private static func copyURLAttr(_ el: AXUIElement, _ name: String) -> URL? {
        var v: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, name as CFString, &v)
        if err != .success {
            return nil
        }
        if let u = v as? URL { return u }
        if let s = v as? String { return URL(fileURLWithPath: s) }
        if let cf = v { return (cf as? NSURL) as URL? }
        return nil
    }

    private static func copyChildren(_ el: AXUIElement) -> [AXUIElement] {
        let attrs: [String] = [
            kAXChildrenAttribute as String,
            kAXVisibleChildrenAttribute as String,
            kAXRowsAttribute as String,
            "AXDockItemList",
            "AXContents",
        ]
        var out: [AXUIElement] = []
        out.reserveCapacity(16)
        for a in attrs {
            var v: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(el, a as CFString, &v)
            if err != .success { continue }
            guard let cf = v else { continue }
            if CFGetTypeID(cf) == AXUIElementGetTypeID() {
                out.append(unsafeDowncast(cf, to: AXUIElement.self))
            } else if let arr = cf as? [AXUIElement] {
                out.append(contentsOf: arr)
            }
        }
        return out
    }

    private static func findBadgeText(in el: AXUIElement, maxDepth: Int) -> String? {
        if let badge = copyStringAttr(el, "AXBadgeValue"), !badge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return badge
        }
        if let status = copyStringAttr(el, "AXStatusLabel"), !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return status
        }

        if maxDepth <= 0 { return nil }
        for c in copyChildren(el) {
            if let s = findBadgeText(in: c, maxDepth: maxDepth - 1) {
                return s
            }
        }
        return nil
    }

    private static func findDockItem(root: AXUIElement, wantName: String, wantBundleId: String, wantURL: URL?, depth: Int, maxDepth: Int) -> AXUIElement? {
        if depth > maxDepth { return nil }

        if let ident = copyStringAttr(root, kAXIdentifierAttribute as String), ident == wantBundleId {
            return root
        }
        if let bid = copyStringAttr(root, "AXBundleIdentifier"), bid == wantBundleId {
            return root
        }
        if let ident = copyStringAttr(root, kAXIdentifierAttribute as String), ident.contains(wantBundleId) {
            return root
        }

        if let wantURL {
            if let u = copyURLAttr(root, "AXURL") {
                let a = u.standardizedFileURL.path
                let b = wantURL.standardizedFileURL.path
                if !a.isEmpty, a == b {
                    return root
                }
            }
        }

        let wantLower = wantName.lowercased()
        if let title = copyStringAttr(root, kAXTitleAttribute as String) {
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                let tl = t.lowercased()
                if tl == wantLower || tl.contains(wantLower) {
                    return root
                }
            }
        }
        if let desc = copyStringAttr(root, kAXDescriptionAttribute as String) {
            let d = desc.trimmingCharacters(in: .whitespacesAndNewlines)
            if !d.isEmpty {
                let dl = d.lowercased()
                if dl == wantLower || dl.contains(wantLower) {
                    return root
                }
            }
        }

        for c in copyChildren(root) {
            if let hit = findDockItem(root: c, wantName: wantName, wantBundleId: wantBundleId, wantURL: wantURL, depth: depth + 1, maxDepth: maxDepth) {
                return hit
            }
        }
        return nil
    }
}
