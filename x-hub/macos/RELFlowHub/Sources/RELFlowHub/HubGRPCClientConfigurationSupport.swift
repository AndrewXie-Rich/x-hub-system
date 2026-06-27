import Foundation
import AppKit
import RELFlowHubCore

@MainActor
extension HubGRPCServerSupport {
    // For local control-plane calls (e.g. pairing approvals). Keep token private to Hub.
    func localAdminToken() -> String {
        HubGRPCTokens.getOrCreateAdminToken()
    }

    func regenerateClientToken() {
        let tok = HubGRPCTokens.regenerateClientToken()

        // Keep the default entry in hub_grpc_clients.json in sync.
        createClientsTemplateIfMissing()
        var snap = loadClientsSnapshot()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        var updated = false
        for i in snap.clients.indices {
            if snap.clients[i].deviceId == "terminal_device" {
                snap.clients[i].token = tok
                snap.clients[i].enabled = true
                snap.clients[i].createdAtMs = nowMs
                updated = true
            }
        }
        if !updated {
            snap.clients.append(
                HubGRPCClientEntry(
                    deviceId: "terminal_device",
                    userId: "",
                    name: HubUIStrings.Settings.GRPC.Runtime.defaultTerminalName,
                    token: tok,
                    enabled: true,
                    createdAtMs: nowMs,
                    capabilities: HubGRPCClientsStore.defaultCapabilities(),
                    allowedCidrs: HubGRPCClientsStore.defaultAllowedCidrs()
                )
            )
        }
        snap.updatedAtMs = nowMs
        saveClientsSnapshot(snap)
        restart()
    }

    func regenerateAdminToken() {
        _ = HubGRPCTokens.regenerateAdminToken()
        restart()
    }

    func openLog() {
        let base = SharedPaths.ensureHubDirectory()
        let logURL = base.appendingPathComponent("hub_grpc.log")
        NSWorkspace.shared.open(logURL)
    }

    func quotaConfigURL() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent("hub_quotas.json")
    }

    func clientsConfigURL() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent("hub_grpc_clients.json")
    }

    func pairedTerminalLocalModelProfilesConfigURL() -> URL {
        HubPairedTerminalLocalModelProfilesStorage.url()
    }

    func createQuotaTemplateIfMissing() {
        let url = quotaConfigURL()
        if FileManager.default.fileExists(atPath: url.path) {
            return
        }
        let template: [String: Any] = [
            "default_daily_token_cap": 0,
            "devices": [
                "terminal_device": ["daily_token_cap": 50_000],
            ],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: template, options: [.prettyPrinted]),
           let s = String(data: data, encoding: .utf8),
           let out = (s + "\n").data(using: .utf8) {
            try? out.write(to: url, options: .atomic)
        }
    }

    func openQuotaConfig() {
        createQuotaTemplateIfMissing()
        NSWorkspace.shared.open(quotaConfigURL())
    }

    func createClientsTemplateIfMissing() {
        if didEnsureClientsTemplate {
            return
        }
        let existing = loadClientsSnapshot()
        if !existing.clients.isEmpty {
            didEnsureClientsTemplate = true
            return
        }

        // Keep default client token stable across restarts (Keychain).
        let tok = HubGRPCTokens.getOrCreateClientToken()
        let snap = HubGRPCClientsStore.defaultSnapshot(defaultToken: tok)
        saveClientsSnapshot(snap)
    }

    func loadClientsSnapshot() -> HubGRPCClientsSnapshot {
        guard let candidate = resolvedClientsConfigReadCandidate() else {
            cachedClientsSnapshot = .empty()
            cachedClientsSnapshotFingerprint = ""
            return .empty()
        }
        if candidate.fingerprint == cachedClientsSnapshotFingerprint {
            return cachedClientsSnapshot
        }
        guard let data = try? Data(contentsOf: candidate.url),
              let obj = try? JSONDecoder().decode(HubGRPCClientsSnapshot.self, from: data) else {
            cachedClientsSnapshot = .empty()
            cachedClientsSnapshotFingerprint = candidate.fingerprint
            return .empty()
        }
        cachedClientsSnapshot = obj
        cachedClientsSnapshotFingerprint = candidate.fingerprint
        return obj
    }

    func saveClientsSnapshot(_ snap: HubGRPCClientsSnapshot) {
        var cur = snap
        if cur.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cur.schemaVersion = "hub_grpc_clients.v1"
        }
        if cur.updatedAtMs <= 0 {
            cur.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        }

        let url = clientsConfigURL()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data0 = try? enc.encode(cur),
              let s = String(data: data0, encoding: .utf8),
              let out = (s + "\n").data(using: .utf8) else {
            return
        }
        try? out.write(to: url, options: .atomic)
        // Contains bearer tokens; keep owner-readable only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        didEnsureClientsTemplate = true
        cachedClientsSnapshot = cur
        cachedClientsSnapshotFingerprint = clientsConfigFingerprint(for: url) ?? ""
    }

    private func clientsConfigReadCandidates() -> [URL] {
        var out: [URL] = []
        var seen: Set<String> = []

        func append(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return }
            out.append(url)
        }

        if let group = SharedPaths.appGroupDirectory() {
            append(group.appendingPathComponent("hub_grpc_clients.json"))
        }
        for base in SharedPaths.hubDirectoryCandidates() {
            append(base.appendingPathComponent("hub_grpc_clients.json"))
        }

        return out
    }

    private func resolvedClientsConfigReadCandidate() -> (url: URL, fingerprint: String)? {
        var bestURL: URL?
        var bestDate: Date = .distantPast
        var bestFingerprint: String = ""

        for url in clientsConfigReadCandidates() {
            guard let fingerprint = clientsConfigFingerprint(for: url) else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let modifiedAt = values?.contentModificationDate ?? .distantPast
            if bestURL == nil || modifiedAt >= bestDate {
                bestURL = url
                bestDate = modifiedAt
                bestFingerprint = fingerprint
            }
        }

        guard let bestURL else { return nil }
        return (bestURL, bestFingerprint)
    }

    private func clientsConfigFingerprint(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modifiedAt = values.contentModificationDate else {
            return FileManager.default.fileExists(atPath: url.path) ? url.standardizedFileURL.path : nil
        }
        let fileSize = values.fileSize ?? 0
        return "\(url.standardizedFileURL.path)#\(modifiedAt.timeIntervalSince1970)#\(fileSize)"
    }

    func openClientsConfig() {
        createClientsTemplateIfMissing()
        NSWorkspace.shared.open(clientsConfigURL())
    }

    func createPairedTerminalLocalModelProfilesTemplateIfMissing() {
        let url = pairedTerminalLocalModelProfilesConfigURL()
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(HubPairedTerminalLocalModelProfilesSnapshot.self, from: data),
           decoded.schemaVersion == "hub.paired_terminal_local_model_profiles.v1" {
            return
        }
        HubPairedTerminalLocalModelProfilesStorage.save(.empty())
    }

    func openPairedTerminalLocalModelProfilesConfig() {
        createPairedTerminalLocalModelProfilesTemplateIfMissing()
        NSWorkspace.shared.open(pairedTerminalLocalModelProfilesConfigURL())
    }

    func pairedTerminalLocalModelProfile(deviceId: String, modelId: String) -> HubPairedTerminalLocalModelProfile? {
        HubPairedTerminalLocalModelProfilesStorage.profile(deviceId: deviceId, modelId: modelId)
    }

    func upsertPairedTerminalLocalModelProfile(_ profile: HubPairedTerminalLocalModelProfile) {
        HubPairedTerminalLocalModelProfilesStorage.upsert(profile)
        refresh()
    }

    func removePairedTerminalLocalModelProfile(deviceId: String, modelId: String) {
        HubPairedTerminalLocalModelProfilesStorage.remove(deviceId: deviceId, modelId: modelId)
        refresh()
    }

    @discardableResult
    func createClient(name: String) -> HubGRPCClientEntry {
        createClientsTemplateIfMissing()
        var snap = loadClientsSnapshot()

        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanedName.isEmpty ? HubUIStrings.Settings.GRPC.Runtime.defaultLANClientName : cleanedName

        // Generate a stable device_id for quota/policy. Keep it URL/filesystem friendly.
        let rawId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let deviceId = "dev_" + String(rawId.prefix(12))
        let token = HubGRPCClientsStore.generateToken(prefix: "axhub_client_")
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        let entry = HubGRPCClientEntry(
            deviceId: deviceId,
            userId: "",
            name: displayName,
            token: token,
            enabled: true,
            createdAtMs: nowMs,
            // Safe default: local-only + memory/events. Paid/network require explicit enable.
            capabilities: HubGRPCClientsStore.defaultCapabilities(),
            // Safe default: bind token to LAN (private RFC1918) + loopback.
            allowedCidrs: HubGRPCClientsStore.defaultAllowedCidrs()
        )

        snap.clients.append(entry)
        snap.updatedAtMs = nowMs
        saveClientsSnapshot(snap)
        refresh()
        return entry
    }

    func upsertClient(_ entry: HubGRPCClientEntry) {
        createClientsTemplateIfMissing()
        var snap = loadClientsSnapshot()
        let did = entry.deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !did.isEmpty else { return }

        var replaced = false
        for i in snap.clients.indices {
            if snap.clients[i].deviceId == did {
                snap.clients[i] = entry
                replaced = true
            }
        }
        if !replaced {
            snap.clients.append(entry)
        }

        snap.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        saveClientsSnapshot(snap)
        refresh()
    }

    func currentLANDefaultAllowedCidrs() -> [String] {
        Self.defaultLANAllowedCidrs()
    }

    func adoptCurrentLANDefaults(deviceId: String) {
        createClientsTemplateIfMissing()
        var snap = loadClientsSnapshot()
        let did = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !did.isEmpty else { return }

        let defaults = Self.defaultLANAllowedCidrs()
        guard !defaults.isEmpty else { return }

        var changed = false
        for i in snap.clients.indices where snap.clients[i].deviceId == did {
            let normalizedCurrent = Self.orderedAllowedCidrs(Self.normalizeAllowedCidrs(snap.clients[i].allowedCidrs))
            if normalizedCurrent != defaults {
                snap.clients[i].allowedCidrs = defaults
                changed = true
            }
        }

        guard changed else { return }
        snap.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        saveClientsSnapshot(snap)
        refresh()
    }

    func setClientEnabled(deviceId: String, enabled: Bool) {
        createClientsTemplateIfMissing()
        var snap = loadClientsSnapshot()
        let did = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !did.isEmpty else { return }
        var changed = false
        for i in snap.clients.indices {
            if snap.clients[i].deviceId == did {
                if snap.clients[i].enabled != enabled {
                    snap.clients[i].enabled = enabled
                    changed = true
                }
            }
        }
        guard changed else { return }
        snap.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        saveClientsSnapshot(snap)
        refresh()
    }

    func removeClient(deviceId: String) {
        createClientsTemplateIfMissing()
        let did = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !did.isEmpty else { return }
        // Keep the Hub's built-in local/default terminal path intact.
        guard did != "terminal_device" else { return }

        var snap = loadClientsSnapshot()
        let originalCount = snap.clients.count
        snap.clients.removeAll { $0.deviceId == did }
        guard snap.clients.count != originalCount else { return }

        snap.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        saveClientsSnapshot(snap)
        HubPairedTerminalLocalModelProfilesStorage.removeAll(deviceId: did)
        refresh()
    }

    func addAllowedCidr(deviceId: String, value: String) {
        createClientsTemplateIfMissing()
        var snap = loadClientsSnapshot()
        let did = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !did.isEmpty, !raw.isEmpty else { return }

        var changed = false
        for i in snap.clients.indices {
            if snap.clients[i].deviceId != did { continue }

            // Empty = allow-any source IP. Don't change semantics in this helper.
            if snap.clients[i].allowedCidrs.isEmpty { return }

            var cur = Self.normalizeAllowedCidrs(snap.clients[i].allowedCidrs)
            let canon = Self.canonicalAllowedCidrValue(raw)
            if canon.isEmpty { return }
            if cur.contains(where: { $0.lowercased() == canon.lowercased() }) { return }
            cur.append(canon)
            snap.clients[i].allowedCidrs = Self.orderedAllowedCidrs(cur)
            changed = true
        }

        guard changed else { return }
        snap.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        saveClientsSnapshot(snap)
        refresh()
    }

    @discardableResult
    func rotateClientToken(deviceId: String) -> String? {
        createClientsTemplateIfMissing()
        var snap = loadClientsSnapshot()
        let did = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !did.isEmpty else { return nil }
        let newToken: String = {
            if did == "terminal_device" {
                // Keep Keychain token in sync for the default client.
                return HubGRPCTokens.regenerateClientToken()
            }
            return HubGRPCClientsStore.generateToken(prefix: "axhub_client_")
        }()
        var changed = false
        for i in snap.clients.indices {
            if snap.clients[i].deviceId == did {
                snap.clients[i].token = newToken
                snap.clients[i].createdAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
                changed = true
            }
        }
        guard changed else { return nil }
        snap.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        saveClientsSnapshot(snap)
        refresh()
        return newToken
    }

    private static func canonicalAllowedCidrValue(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "" }
        let lower = cleaned.lowercased()
        if lower == "localhost" { return "loopback" }
        if lower == "loopback" { return "loopback" }
        if lower == "private" { return "private" }
        return cleaned
    }

    private static func normalizeAllowedCidrs(_ list: [String]) -> [String] {
        let raw = list
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Any/* means "allow any source IP" (represented as empty list).
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
            let canon = canonicalAllowedCidrValue(s)
            let key = canon.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(canon)
        }
        return out
    }

    private static func orderedAllowedCidrs(_ list: [String]) -> [String] {
        let clean = normalizeAllowedCidrs(list)
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
}
