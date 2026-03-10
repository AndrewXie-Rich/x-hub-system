import Dispatch
import Foundation

struct AXCurationSuggestion: Identifiable, Codable, Equatable {
    var id: String
    var projectId: String
    var projectName: String
    // Optional module bucket for monorepo projects: "hub" | "coder" | "system" | "shared".
    var module: String?

    // Currently only one type is used; keep as string for forward compatibility.
    // Examples: promote_skill, merge_skills, sink_vault, extract_key_paths
    var type: String

    var title: String
    var summary: String

    // Evidence pointers (relative paths under the project's forgotten-vault skill).
    // Example: references/20260206-...md or references/_deep/20250101-...md
    var refs: [String]

    var createdAt: Double
    var status: String
    var confidence: Double?

    init(
        id: String = UUID().uuidString,
        projectId: String,
        projectName: String,
        module: String? = nil,
        type: String,
        title: String,
        summary: String,
        refs: [String],
        createdAt: Double = Date().timeIntervalSince1970,
        status: String = "pending",
        confidence: Double? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.projectName = projectName
        self.module = module
        self.type = type
        self.title = title
        self.summary = summary
        self.refs = refs
        self.createdAt = createdAt
        self.status = status
        self.confidence = confidence
    }
}

enum AXCurationSuggestionStore {
    private static let queue = DispatchQueue(label: "xterminal.curation_suggestion_store")

    static func suggestionsURL(for ctx: AXProjectContext) -> URL {
        ctx.xterminalDir.appendingPathComponent("curation_suggestions.json")
    }

    static func loadSuggestions(for ctx: AXProjectContext) -> [AXCurationSuggestion] {
        queue.sync {
            loadSuggestionsUnlocked(for: ctx)
        }
    }

    static func saveSuggestions(_ list: [AXCurationSuggestion], for ctx: AXProjectContext) {
        queue.sync {
            saveSuggestionsUnlocked(list, for: ctx)
        }
    }

    static func pendingSuggestions(for ctx: AXProjectContext) -> [AXCurationSuggestion] {
        queue.sync {
            loadSuggestionsUnlocked(for: ctx).filter { $0.status == "pending" }
        }
    }

    @discardableResult
    static func appendSuggestions(_ incoming: [AXCurationSuggestion], for ctx: AXProjectContext) -> Int {
        guard !incoming.isEmpty else { return 0 }
        return queue.sync {
            var existing = loadSuggestionsUnlocked(for: ctx)
            var added = 0
            for s in incoming {
                if !shouldInsert(s, existing: existing) { continue }
                existing.append(s)
                added += 1
            }
            if added > 0 {
                saveSuggestionsUnlocked(existing, for: ctx)
            }
            return added
        }
    }

    static func updateSuggestion(id: String, status: String, for ctx: AXProjectContext) {
        queue.sync {
            var list = loadSuggestionsUnlocked(for: ctx)
            guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
            list[idx].status = status
            saveSuggestionsUnlocked(list, for: ctx)
        }
    }

    private static func loadSuggestionsUnlocked(for ctx: AXProjectContext) -> [AXCurationSuggestion] {
        let url = suggestionsURL(for: ctx)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([AXCurationSuggestion].self, from: data)) ?? []
    }

    private static func saveSuggestionsUnlocked(_ list: [AXCurationSuggestion], for ctx: AXProjectContext) {
        try? ctx.ensureDirs()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(list) else { return }
        try? data.write(to: suggestionsURL(for: ctx), options: .atomic)
    }

    private static func shouldInsert(_ s: AXCurationSuggestion, existing: [AXCurationSuggestion]) -> Bool {
        let key = normalizeKey(s.type + ":" + s.title)
        if key.isEmpty { return false }
        for item in existing {
            let existingKey = normalizeKey(item.type + ":" + item.title)
            if existingKey == key {
                return false
            }
        }
        return true
    }

    private static func normalizeKey(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum AXVaultCurator {
    // Safety limits: keep this cheap, deterministic, and mostly index-based.
    private static let maxEntriesToConsider = 400
    private static let maxSuggestionsToAdd = 12
    private static let autoApplyThreshold = 0.93

    @discardableResult
    static func scanAndSuggest(ctx: AXProjectContext) -> Int {
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        guard let skillsDir = AXSkillsLibrary.ensureSkillsDirectory(),
              let projectDir = AXSkillsLibrary.projectSkillsDir(projectId: projectId, projectName: ctx.projectName(), skillsDir: skillsDir) else {
            return 0
        }

        let vaultDir = projectDir.appendingPathComponent("forgotten-vault", isDirectory: true)
        let refsDir = vaultDir.appendingPathComponent("references", isDirectory: true)
        let idx0 = refsDir.appendingPathComponent("index.md")
        let idx1 = refsDir.appendingPathComponent("_deep", isDirectory: true).appendingPathComponent("index.md")

        guard FileManager.default.fileExists(atPath: idx0.path) || FileManager.default.fileExists(atPath: idx1.path) else {
            return 0
        }

        let entries = (parseIndex(idx0, tier: "L0") + parseIndex(idx1, tier: "L1"))
            .suffix(maxEntriesToConsider)
        if entries.isEmpty { return 0 }

        // Group by normalized title; this yields conservative "repeated topic" signals.
        var groups: [String: [VaultIndexEntry]] = [:]
        for e in entries {
            let t = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if isTrivial(t) { continue }
            let key = normalizeForCompare(t)
            if key.isEmpty { continue }
            groups[key, default: []].append(e)
        }

        var suggestions: [AXCurationSuggestion] = []
        for (_, items) in groups {
            guard items.count >= 2 else { continue }
            let sample = items[items.count - 1]
            let refs = Array(items.suffix(6)).map { $0.relPath }
            let conf = confidenceForGroup(items)
            let module = dominantModule(items)
            let title = sample.title
            let summary = "Vault 中出现 \(items.count) 次，建议提炼为项目 skill；证据 refs: \(refs.prefix(3).joined(separator: ", "))"
            suggestions.append(
                AXCurationSuggestion(
                    projectId: projectId,
                    projectName: ctx.projectName(),
                    module: module,
                    type: "promote_skill",
                    title: title,
                    summary: summary,
                    refs: refs,
                    createdAt: Date().timeIntervalSince1970,
                    status: "pending",
                    confidence: conf
                )
            )
        }

        // Sort by (confidence, count) and cap.
        suggestions.sort { (a, b) in
            let ca = a.confidence ?? 0
            let cb = b.confidence ?? 0
            if ca == cb { return a.refs.count > b.refs.count }
            return ca > cb
        }
        if suggestions.count > maxSuggestionsToAdd {
            suggestions = Array(suggestions.prefix(maxSuggestionsToAdd))
        }

        let added = AXCurationSuggestionStore.appendSuggestions(suggestions, for: ctx)
        if added > 0 {
            AXProjectStore.appendRawLog(
                [
                    "type": "vault_curation",
                    "mode": "scan",
                    "created_at": Date().timeIntervalSince1970,
                    "suggestions_added": added,
                ],
                for: ctx
            )
        }

        // Auto-apply extremely high confidence items (rare).
        autoApplyHighConfidence(ctx: ctx)
        return added
    }

    static func autoApplyHighConfidence(ctx: AXProjectContext) {
        let pending = AXCurationSuggestionStore.pendingSuggestions(for: ctx)
        let high = pending.filter { ($0.confidence ?? 0) >= autoApplyThreshold && $0.type == "promote_skill" }
        guard !high.isEmpty else { return }
        for s in high {
            _ = applySuggestion(ctx: ctx, suggestionId: s.id, by: "auto")
        }
    }

    // Returns created skill name on success.
    @discardableResult
    static func applySuggestion(ctx: AXProjectContext, suggestionId: String, by: String) -> String? {
        var list = AXCurationSuggestionStore.loadSuggestions(for: ctx)
        guard let idx = list.firstIndex(where: { $0.id == suggestionId }) else { return nil }
        let s = list[idx]
        if s.status != "pending" { return nil }
        guard s.type == "promote_skill" else { return nil }

        guard let skillsDir = AXSkillsLibrary.ensureSkillsDirectory() else { return nil }
        let cand = AXSkillCandidate(
            projectId: s.projectId,
            projectName: s.projectName,
            module: s.module,
            title: s.title,
            summary: s.summary,
            source: "vault_curator",
            createdAt: Date().timeIntervalSince1970,
            status: "approved",
            skillName: nil,
            confidence: s.confidence,
            promotedBy: by
        )
        guard let skillName = AXSkillsLibrary.promoteCandidate(cand, skillsDir: skillsDir) else { return nil }

        // Write evidence links into the skill folder.
        if let projectDir = AXSkillsLibrary.projectSkillsDir(projectId: s.projectId, projectName: s.projectName, skillsDir: skillsDir) {
            let skillDir = projectDir.appendingPathComponent(skillName, isDirectory: true)
            let refsDir = skillDir.appendingPathComponent("references", isDirectory: true)
            try? FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)
            let vaultMD = refsDir.appendingPathComponent("vault.md")
            let body = """
# Vault Evidence
- Source: AXForgottenVault (project-level)
- SuggestionId: \(s.id)
- GeneratedBy: \(by)

## Refs
\(s.refs.map { "- \($0)" }.joined(separator: "\n"))
"""
            try? body.data(using: .utf8)?.write(to: vaultMD, options: .atomic)
        }

        list[idx].status = "applied"
        AXCurationSuggestionStore.saveSuggestions(list, for: ctx)

        AXProjectStore.appendRawLog(
            [
                "type": "vault_curation",
                "mode": "apply",
                "created_at": Date().timeIntervalSince1970,
                "suggestion_id": s.id,
                "skill_name": skillName,
                "applied_by": by,
                "confidence": s.confidence as Any,
            ],
            for: ctx
        )

        return skillName
    }

    static func dismissSuggestion(ctx: AXProjectContext, suggestionId: String) {
        AXCurationSuggestionStore.updateSuggestion(id: suggestionId, status: "dismissed", for: ctx)
        AXProjectStore.appendRawLog(
            [
                "type": "vault_curation",
                "mode": "dismiss",
                "created_at": Date().timeIntervalSince1970,
                "suggestion_id": suggestionId,
            ],
            for: ctx
        )
    }

    // MARK: - Index Parsing

    private struct VaultIndexEntry {
        var tier: String
        var title: String
        var relPath: String
        var module: String?
    }

    private static func parseIndex(_ url: URL, tier: String) -> [VaultIndexEntry] {
        guard FileManager.default.fileExists(atPath: url.path),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        var out: [VaultIndexEntry] = []
        for lineSub in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(lineSub)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("- ") else { continue }
            guard let rel = extractRelPath(fromIndexLine: trimmed) else { continue }
            let title = extractTitle(fromIndexLine: trimmed) ?? trimmed
            let module = extractModule(fromIndexLine: trimmed)
            out.append(VaultIndexEntry(tier: tier, title: title, relPath: rel, module: module))
        }
        return out
    }

    private static func extractRelPath(fromIndexLine line: String) -> String? {
        guard let start = line.range(of: "（文件：") else { return nil }
        guard let end = line.range(of: "）", range: start.upperBound..<line.endIndex) else { return nil }
        let raw = line[start.upperBound..<end.lowerBound]
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func extractTitle(fromIndexLine line: String) -> String? {
        guard let dash = line.range(of: "—") else { return nil }
        let after = line[dash.upperBound...]
        if let kw = after.range(of: "（关键词：") {
            return String(after[..<kw.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let file = after.range(of: "（文件：") {
            return String(after[..<file.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(after).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractModule(fromIndexLine line: String) -> String? {
        guard let start = line.range(of: "（关键词：") else { return nil }
        guard let end = line.range(of: "）", range: start.upperBound..<line.endIndex) else { return nil }
        let raw = String(line[start.upperBound..<end.lowerBound])
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        for p in parts {
            if p.hasPrefix("module:") {
                let v = String(p.dropFirst("module:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if ["hub", "coder", "system", "shared"].contains(v) {
                    return String(v)
                }
            }
        }
        return nil
    }

    private static func dominantModule(_ items: [VaultIndexEntry]) -> String? {
        var counts: [String: Int] = [:]
        for e in items {
            guard let m = e.module else { continue }
            counts[m, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Confidence

    private static func confidenceForGroup(_ items: [VaultIndexEntry]) -> Double {
        let n = items.count
        if n >= 4 { return 0.95 }
        if n == 3 { return 0.90 }
        // n == 2: only if the title looks durable.
        let t = (items.last?.title ?? "").lowercased()
        if containsDurableKeywords(t) { return 0.86 }
        return 0.75
    }

    private static func containsDurableKeywords(_ lower: String) -> Bool {
        let keywords = [
            "schema", "规范", "规则", "机制", "目录", "结构", "触发",
            "workflow", "索引", "导航", "策略", "权限", "路由", "模型"
        ]
        return keywords.contains(where: { lower.contains($0) })
    }

    private static func isTrivial(_ s: String) -> Bool {
        let norm = normalizeForCompare(s)
        if norm.isEmpty { return true }
        if norm.count <= 2 { return true }
        if trivialPhrases.contains(norm) { return true }
        return false
    }

    private static func normalizeForCompare(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let removeSet = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        let filtered = trimmed.unicodeScalars.filter { !removeSet.contains($0) }
        return String(String.UnicodeScalarView(filtered))
    }

    private static let trivialPhrases: Set<String> = [
        "继续", "继续吧", "继续推进", "继续下去", "继续下一步",
        "可以了", "可以", "好了", "好的", "行", "ok", "okay",
        "完成了吗", "完成了么", "好了么", "好了嘛",
        "开始", "开始吧", "下一步", "下一个",
        "谢谢", "收到", "知道了", "明白了"
    ]
}
