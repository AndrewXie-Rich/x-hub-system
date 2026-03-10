import Foundation
import AppKit
import ApplicationServices

/// Reads Dock badge counts via Accessibility.
///
/// This is the only reliable fully-offline option for third-party apps like Slack,
/// and it also keeps Mail/Messages "counts-only" without touching their data stores.
///
/// Requires the user to grant Accessibility permission to RELFlowHub.
@MainActor
enum DockBadgeReader {
    struct Result {
        var ok: Bool
        var count: Int
        var debug: String
    }

    static func ensureAccessibilityTrusted(prompt: Bool) -> Bool {
        if prompt {
            // Avoid Swift concurrency warnings about the global var constant.
            let opts = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        return AXIsProcessTrusted()
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

        // Find the corresponding Dock item.
        guard let item = findDockItem(root: dock, wantName: wantName, wantBundleId: bundleId, wantURL: wantURL, depth: 0, maxDepth: 24) else {
            let urlStr = wantURL?.standardizedFileURL.path ?? "(nil)"
            let runStr = (running != nil) ? "true" : "false"
            let childCount = copyChildren(dock).count
            let sample = probeDockTitles(root: dock, maxItems: 6).joined(separator: ";")
            let suffix = sample.isEmpty ? "" : " sample=\(sample)"

            let attrs = dockAttributeNames(dock).prefix(18).joined(separator: ",")
            let attrsSuffix = attrs.isEmpty ? "" : " attrs=\(attrs)"

            return Result(ok: true, count: 0, debug: "dock_item_not_found:name=\(wantName) running=\(runStr) url=\(urlStr) dockChildren=\(childCount)\(suffix)\(attrsSuffix)")
        }

        // Probe the item subtree because some OS versions attach the badge to a child element.
        if let found = findBadgeText(in: item, maxDepth: 10) {
            let trimmed = found.trimmingCharacters(in: .whitespacesAndNewlines)
            if let n = Int(trimmed) {
                return Result(ok: true, count: max(0, n), debug: "badge_text:\(trimmed)")
            }
            if let n = firstInt(in: trimmed) {
                return Result(ok: true, count: max(0, n), debug: "badge_parse:\(trimmed)")
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
        // The Dock's AX hierarchy has changed across macOS releases.
        // Besides the standard kAXChildrenAttribute, some OS versions expose lists under
        // attributes like AXDockItemList / AXRows / AXVisibleChildren.
        // Keep this conservative (few attrs) to avoid heavy enumeration.
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

            // Some attributes return a single AXUIElement, others an array.
            if CFGetTypeID(cf) == AXUIElementGetTypeID() {
                out.append(unsafeDowncast(cf, to: AXUIElement.self))
            } else if let arr = cf as? [AXUIElement] {
                out.append(contentsOf: arr)
            }
        }
        return out
    }

    private static func dockAttributeNames(_ el: AXUIElement) -> [String] {
        var v: CFArray?
        let err = AXUIElementCopyAttributeNames(el, &v)
        if err != .success {
            return ["(attrNamesErr=\(err.rawValue))"]
        }
        guard let arr = v as? [String] else {
            return []
        }
        return arr
    }

    private static func probeDockTitles(root: AXUIElement, maxItems: Int) -> [String] {
        // Best-effort: sample a few element titles/descriptions to help debug
        // Dock AX hierarchy changes.
        var out: [String] = []
        out.reserveCapacity(min(12, maxItems))

        var q: [(AXUIElement, Int)] = [(root, 0)]
        var seen: Set<Int> = []

        func key(_ el: AXUIElement) -> Int {
            // Hash the raw pointer identity.
            let ptr = Unmanaged.passUnretained(el as AnyObject).toOpaque()
            return Int(bitPattern: ptr)
        }

        while let (el, depth) = q.first {
            q.removeFirst()
            if out.count >= maxItems { break }
            let k = key(el)
            if seen.contains(k) { continue }
            seen.insert(k)

            if let t = copyStringAttr(el, kAXTitleAttribute as String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !t.isEmpty {
                out.append("title=\(t)")
            } else if let d = copyStringAttr(el, kAXDescriptionAttribute as String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !d.isEmpty {
                out.append("desc=\(d)")
            }

            if depth < 6 {
                let kids = copyChildren(el)
                for c in kids {
                    q.append((c, depth + 1))
                }
            }
        }
        return out
    }

    private static func findBadgeText(in el: AXUIElement, maxDepth: Int) -> String? {
        // Prefer explicit badge value.
        if let badge = copyStringAttr(el, "AXBadgeValue"), !badge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return badge
        }
        // Status label often contains the badge count as a number.
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

        // Prefer matching by identifier if available.
        if let ident = copyStringAttr(root, kAXIdentifierAttribute as String), ident == wantBundleId {
            return root
        }

        // Some OS versions expose bundle id explicitly.
        if let bid = copyStringAttr(root, "AXBundleIdentifier"), bid == wantBundleId {
            return root
        }

        // Some identifiers embed the bundle id.
        if let ident = copyStringAttr(root, kAXIdentifierAttribute as String), ident.contains(wantBundleId) {
            return root
        }

        // Match by URL when available (more robust than localized names).
        if let wantURL {
            if let u = copyURLAttr(root, "AXURL") {
                let a = u.standardizedFileURL.path
                let b = wantURL.standardizedFileURL.path
                if !a.isEmpty, a == b {
                    return root
                }
            }
        }

        // Then try matching by title/description (case-insensitive, and allow partial matches).
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
