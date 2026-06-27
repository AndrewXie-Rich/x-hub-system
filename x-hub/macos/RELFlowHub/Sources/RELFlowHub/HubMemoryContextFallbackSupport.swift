import Foundation
import RELFlowHubCore

extension HubMemoryContextBuilder {
    static func projectFallback(req: IPCMemoryContextRequestPayload) -> ProjectFallback {
        let reg = HubProjectRegistryStorage.load()
        let pid = normalized(req.projectId)
        let root = normalized(req.projectRoot)
        let display = normalized(req.displayName)

        let stored = HubProjectCanonicalMemoryStorage.lookup(
            projectId: pid,
            projectRoot: root,
            displayName: display
        )
        let storedCanonical = storedCanonicalText(snapshot: stored)
        var observationLines: [String] = []
        if let stored {
            observationLines.append(
                """
hub_project_memory_updated_at: \(Int(stored.updatedAt))
hub_project_memory_items: \(stored.items.count)
"""
            )
        }

        let matched: HubProjectSnapshot? = {
            guard !reg.projects.isEmpty else { return nil }
            if !pid.isEmpty, let p = reg.projects.first(where: { $0.projectId == pid }) {
                return p
            }
            if !root.isEmpty, let p = reg.projects.first(where: { normalized($0.rootPath) == root }) {
                return p
            }
            if !display.isEmpty,
               let p = reg.projects.first(where: {
                   normalized($0.displayName).localizedCaseInsensitiveCompare(display) == .orderedSame
               }) {
                return p
            }
            return nil
        }()

        if let p = matched {
            let obs = """
hub_registry_updated_at: \(Int(reg.updatedAt))
project_updated_at: \(Int(p.updatedAt ?? 0))
last_summary_at: \(Int(p.lastSummaryAt ?? 0))
last_event_at: \(Int(p.lastEventAt ?? 0))
"""
            if !obs.isEmpty {
                observationLines.append(obs)
            }
        }

        let registryCanonical: String = {
            guard let p = matched else { return "" }
            let status = normalized(p.statusDigest)
            return """
project: \(p.displayName)
project_id: \(p.projectId)
root_path: \(p.rootPath)
status: \(status.isEmpty ? "(none)" : status)
"""
        }()

        return ProjectFallback(
            canonical: firstNonEmpty(storedCanonical, registryCanonical),
            observations: observationLines
                .map(normalized)
                .filter { !$0.isEmpty }
                .joined(separator: "\n"),
            hasStoredCanonical: !storedCanonical.isEmpty
        )
    }

    static func mergedProjectText(primary: String, secondary: String) -> String {
        let first = normalized(primary)
        let second = normalized(secondary)
        if first.isEmpty { return second }
        if second.isEmpty { return first }
        if first == second { return first }
        return """
\(first)

\(second)
"""
    }

    static func rawEvidenceFallback(mode: String) -> String {
        let ms = ModelStateStorage.load()
        guard !ms.models.isEmpty else { return "" }

        let sorted = ms.models.sorted { a, b in
            if a.state != b.state {
                if a.state == .loaded { return true }
                if b.state == .loaded { return false }
            }
            return a.id.localizedCaseInsensitiveCompare(b.id) == .orderedAscending
        }

        let cap = mode == "supervisor" ? 16 : 8
        let lines = sorted.prefix(cap).map { m in
            let roles = (m.roles ?? []).joined(separator: ",")
            let roleText = roles.isEmpty ? "" : " roles=\(roles)"
            return "- \(m.id) [\(m.state.rawValue)] ctx=\(m.contextLength) backend=\(m.backend)\(roleText)"
        }.joined(separator: "\n")

        return """
models_state_updated_at: \(Int(ms.updatedAt))
\(lines)
"""
    }

    static func loadConstitutionOneLiner(latestUser: String) -> String {
        if shouldUseConciseConstitutionForLowRiskRequest(latestUser) {
            return HubUIStrings.Memory.Constitution.conciseOneLiner
        }

        let fallback = defaultConstitution(latestUser: latestUser)
        let url = SharedPaths.ensureHubDirectory()
            .appendingPathComponent("memory", isDirectory: true)
            .appendingPathComponent("ax_constitution.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let one = obj["one_liner"] as? [String: Any] else {
            return fallback
        }

        let zh = normalized(one["zh"] as? String)
        if !zh.isEmpty { return normalizeConstitution(zh) }
        let en = normalized(one["en"] as? String)
        if !en.isEmpty { return normalizeConstitution(en) }
        return fallback
    }

    static func defaultConstitution(latestUser: String) -> String {
        if shouldUseConciseConstitutionForLowRiskRequest(latestUser) {
            return HubUIStrings.Memory.Constitution.conciseOneLiner
        }
        return HubUIStrings.Memory.Constitution.defaultOneLiner
    }

    private static func storedCanonicalText(snapshot: HubProjectCanonicalMemorySnapshot?) -> String {
        guard let snapshot else { return "" }
        return snapshot.items
            .map { item in
                let key = normalized(item.key)
                let value = normalized(item.value)
                guard !key.isEmpty, !value.isEmpty else { return "" }
                return "\(key) = \(value)"
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func normalizeConstitution(_ raw: String) -> String {
        let t = normalized(raw)
        guard !t.isEmpty else {
            return HubUIStrings.Memory.Constitution.defaultOneLiner
        }

        let legacy = HubUIStrings.Memory.Constitution.legacyOneLiner
        var out = (t == legacy)
            ? HubUIStrings.Memory.Constitution.defaultOneLiner
            : t

        let lower = out.lowercased()
        let zhRiskFocused = HubUIStrings.Memory.Constitution.zhRiskFocusedTokens.contains { token in
            out.contains(token)
        }
        let enRiskFocused =
            lower.contains("high-risk") ||
            lower.contains("compliance") ||
            lower.contains("legal") ||
            lower.contains("privacy") ||
            lower.contains("safety") ||
            lower.contains("harm") ||
            lower.contains("refuse")

        let zhHasCarveout = HubUIStrings.Memory.Constitution.zhCarveoutTokens.contains { token in
            out.contains(token)
        }
        let enHasCarveout =
            lower.contains("only for high-risk") ||
            lower.contains("normal coding") ||
            lower.contains("creative requests") ||
            lower.contains("respond directly") ||
            lower.contains("answer normal")

        if zhRiskFocused && !zhHasCarveout {
            out += HubUIStrings.Memory.Constitution.missingCarveoutSuffix
        } else if enRiskFocused && !enHasCarveout {
            out += " Explain first only for high-risk or irreversible actions; answer normal coding/creative requests directly."
        }
        return out
    }

    private static func shouldUseConciseConstitutionForLowRiskRequest(_ userText: String) -> Bool {
        let t = normalized(userText).lowercased()
        if t.isEmpty { return false }

        let codingSignals = HubUIStrings.Memory.Constitution.lowRiskCodingSignals
        let riskSignals = HubUIStrings.Memory.Constitution.lowRiskRiskSignals
        let hasCoding = codingSignals.contains(where: { t.contains($0) })
        let hasRisk = riskSignals.contains(where: { t.contains($0) })
        return hasCoding && !hasRisk
    }
}
