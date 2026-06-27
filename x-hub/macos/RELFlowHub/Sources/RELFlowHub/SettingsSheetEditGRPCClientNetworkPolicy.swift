import SwiftUI
import AppKit
import RELFlowHubCore

extension EditGRPCClientSheet {
var allowedCidrsConfigIsValid: Bool {
        // Empty allowed_cidrs means "allow any source IP" on the server, which is only intended when
        // allowAnySourceIP is enabled. In restricted mode, enforce at least one rule so the UI intent matches reality.
        if allowAnySourceIP { return true }
        return !orderedAllowedCidrs(allowedCidrs).isEmpty
    }


    var allowedCidrsCustomItems: [String] {
        let norm = Self.normalizeAllowedCidrs(allowedCidrs)
        return norm.filter { v in
            let lower = v.lowercased()
            return lower != "private" && lower != "loopback"
        }
    }

    func bindingAllowedCidrRule(_ rule: String) -> Binding<Bool> {
        let key = rule.lowercased()
        return Binding(
            get: { Self.normalizeAllowedCidrs(allowedCidrs).contains(where: { $0.lowercased() == key }) },
            set: { on in
                if on { addAllowedCidrValue(key) } else { removeAllowedCidrValue(key) }
            }
        )
    }

    func addAllowedCidrsFromText(_ text: String) {
        let parts = text
            .split(whereSeparator: { ch in
                ch == "," || ch == "\n" || ch == ";" || ch == "\t"
            })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }
        for p in parts {
            addAllowedCidrValue(p)
        }
        addCidrText = ""
    }

    func addAllowedCidrValue(_ value: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        // Treat allow-all aliases as "Any" mode for clarity.
        let lower = cleaned.lowercased()
        if lower == "any" || lower == "*" {
            allowAnySourceIP = true
            return
        }
        allowAnySourceIP = false

        var cur = Self.normalizeAllowedCidrs(allowedCidrs)
        let canon: String = {
            if lower == "localhost" { return "loopback" }
            if lower == "loopback" { return "loopback" }
            if lower == "private" { return "private" }
            return cleaned
        }()
        if cur.contains(where: { $0.lowercased() == canon.lowercased() }) {
            allowedCidrs = orderedAllowedCidrs(cur)
            return
        }
        cur.append(canon)
        allowedCidrs = orderedAllowedCidrs(cur)
        allowedCidrsBackup = orderedAllowedCidrs(cur)
    }

    func removeAllowedCidrValue(_ value: String) {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        var cur = Self.normalizeAllowedCidrs(allowedCidrs)
        cur.removeAll { $0.lowercased() == key }
        allowedCidrs = orderedAllowedCidrs(cur)
        allowedCidrsBackup = orderedAllowedCidrs(cur)
    }

    func orderedAllowedCidrs(_ list: [String]) -> [String] {
        Self.orderedAllowedCidrs(list)
    }

    static func orderedAllowedCidrs(_ list: [String]) -> [String] {
        let clean = Self.normalizeAllowedCidrs(list)
        if clean.isEmpty { return [] }

        // Keep stable order but pull well-known rules to the front.
        let order = ["private", "loopback"]
        var out: [String] = []
        for k in order {
            if clean.contains(where: { $0.lowercased() == k }) { out.append(k) }
        }
        out.append(contentsOf: clean.filter { v in
            let lower = v.lowercased()
            return !order.contains(lower)
        })
        return out
    }

    static func normalizeAllowedCidrs(_ list: [String]) -> [String] {
        let raw = list
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if raw.contains(where: { s in
            let lower = s.lowercased()
            return lower == "any" || lower == "*"
        }) {
            return []
        }

        // De-dup while preserving order.
        var seen = Set<String>()
        var out: [String] = []
        for s in raw {
            let lower = s.lowercased()
            let canon: String = {
                if lower == "localhost" { return "loopback" }
                if lower == "loopback" { return "loopback" }
                if lower == "private" { return "private" }
                return s
            }()
            let key = canon.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(canon)
        }
        return out
    }
}
