import Dispatch
import Foundation

struct AXSkillCandidate: Identifiable, Codable, Equatable {
    var id: String
    var projectId: String
    var projectName: String
    // Optional module bucket for monorepo projects: "hub" | "coder" | "system" | "shared".
    // Keep nil for single-module projects to avoid noisy prefixes in skill names.
    var module: String?
    var title: String
    var summary: String
    var source: String
    var createdAt: Double
    var status: String
    var skillName: String?
    var confidence: Double?
    var promotedBy: String?

    init(
        id: String = UUID().uuidString,
        projectId: String,
        projectName: String,
        module: String? = nil,
        title: String,
        summary: String,
        source: String,
        createdAt: Double = Date().timeIntervalSince1970,
        status: String = "pending",
        skillName: String? = nil,
        confidence: Double? = nil,
        promotedBy: String? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.projectName = projectName
        self.module = module
        self.title = title
        self.summary = summary
        self.source = source
        self.createdAt = createdAt
        self.status = status
        self.skillName = skillName
        self.confidence = confidence
        self.promotedBy = promotedBy
    }
}

enum AXSkillCandidateStore {
    private static let queue = DispatchQueue(label: "xterminal.skill_candidate_store")

    static func candidatesURL(for ctx: AXProjectContext) -> URL {
        ctx.xterminalDir.appendingPathComponent("skill_candidates.json")
    }

    static func titleKey(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func loadCandidates(for ctx: AXProjectContext) -> [AXSkillCandidate] {
        queue.sync {
            loadCandidatesUnlocked(for: ctx)
        }
    }

    static func saveCandidates(_ candidates: [AXSkillCandidate], for ctx: AXProjectContext) {
        queue.sync {
            saveCandidatesUnlocked(candidates, for: ctx)
        }
    }

    @discardableResult
    static func appendCandidates(_ incoming: [AXSkillCandidate], for ctx: AXProjectContext) -> Int {
        guard !incoming.isEmpty else { return 0 }
        return queue.sync {
            var existing = loadCandidatesUnlocked(for: ctx)
            var added = 0
            for cand in incoming {
                if !shouldInsert(cand, existing: existing) { continue }
                existing.append(cand)
                added += 1
            }
            if added > 0 {
                saveCandidatesUnlocked(existing, for: ctx)
            }
            return added
        }
    }

    static func updateCandidate(
        id: String,
        status: String,
        skillName: String?,
        promotedBy: String? = nil,
        for ctx: AXProjectContext
    ) {
        queue.sync {
            var list = loadCandidatesUnlocked(for: ctx)
            guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
            list[idx].status = status
            list[idx].skillName = skillName
            if let promotedBy {
                list[idx].promotedBy = promotedBy
            }
            saveCandidatesUnlocked(list, for: ctx)
        }
    }

    static func pendingCandidates(for ctx: AXProjectContext) -> [AXSkillCandidate] {
        queue.sync {
            loadCandidatesUnlocked(for: ctx).filter { $0.status == "pending" }
        }
    }

    static func scanCandidates(ctx: AXProjectContext, since: Double) -> Int {
        guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path),
              let data = try? Data(contentsOf: ctx.rawLogURL),
              let s = String(data: data, encoding: .utf8) else {
            return 0
        }
        var found: [AXSkillCandidate] = []
        for line in s.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let ld = line.data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any] else { continue }
            guard (obj["type"] as? String) == "turn" else { continue }
            let ts = (obj["created_at"] as? Double) ?? 0
            if ts < since { continue }
            let u = (obj["user"] as? String) ?? ""
            let a = (obj["assistant"] as? String) ?? ""
            let turn = AXConversationTurn(createdAt: ts, user: u, assistant: a)
            let detected = AXSkillCandidateDetector.detect(turn: turn, delta: nil, ctx: ctx, source: "daily_scan")
            if !detected.isEmpty {
                found.append(contentsOf: detected)
            }
        }
        return appendCandidates(found, for: ctx)
    }

    private static func loadCandidatesUnlocked(for ctx: AXProjectContext) -> [AXSkillCandidate] {
        let url = candidatesURL(for: ctx)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([AXSkillCandidate].self, from: data)) ?? []
    }

    private static func saveCandidatesUnlocked(_ candidates: [AXSkillCandidate], for ctx: AXProjectContext) {
        try? ctx.ensureDirs()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(candidates) else { return }
        try? XTStoreWriteSupport.writeSnapshotData(data, to: candidatesURL(for: ctx))
    }

    private static func shouldInsert(_ cand: AXSkillCandidate, existing: [AXSkillCandidate]) -> Bool {
        let key = titleKey(cand.title)
        if key.isEmpty { return false }
        for item in existing {
            let existingKey = titleKey(item.title)
            if existingKey == key {
                return false
            }
        }
        return true
    }
}

enum AXSkillCandidateDetector {
    static func detect(turn: AXConversationTurn, delta: AXMemoryDelta?, ctx: AXProjectContext, source: String) -> [AXSkillCandidate] {
        let items = collectItems(delta)
        let hasSignal = hasStrongSignal(turn.user) || hasStrongSignal(turn.assistant)
        if items.isEmpty && !hasSignal { return [] }

        let title = makeTitle(items: items, user: turn.user, assistant: turn.assistant)
        if isTrivial(title) { return [] }
        let summary = makeSummary(items: items, user: turn.user, assistant: turn.assistant)
        if isTrivial(summary) { return [] }
        let confidence = confidenceScore(items: items, user: turn.user, assistant: turn.assistant, hasSignal: hasSignal)
        let module = inferModuleIfMultiModuleProject(items: items, user: turn.user, assistant: turn.assistant, ctx: ctx)
        let cand = AXSkillCandidate(
            projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
            projectName: ctx.projectName(),
            module: module,
            title: title,
            summary: summary,
            source: source,
            createdAt: turn.createdAt,
            confidence: confidence
        )
        return [cand]
    }

    private static func collectItems(_ delta: AXMemoryDelta?) -> [String] {
        guard let delta else { return [] }
        let parts = delta.decisionsAdd + delta.requirementsAdd + delta.nextStepsAdd + delta.currentStateAdd
        let cleaned = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isTrivial($0) }
        return Array(cleaned.prefix(6))
    }

    private static func inferModuleIfMultiModuleProject(items: [String], user: String, assistant: String, ctx: AXProjectContext) -> String? {
        // If delta items already carry module prefixes, this is definitely a multi-module project.
        for s in items {
            if let m = moduleFromPrefix(s) {
                return m
            }
        }

        // Conservative gating: only emit module when this repo looks like a monorepo.
        if !looksMultiModuleRepo(ctx.root) {
            return nil
        }

        let t = (user + "\n" + assistant).lowercased()
        if t.contains("protocol/") || t.contains(" protocol ") { return "shared" }
        if t.contains("relflowhub/") || t.contains("relflowhub") || t.contains(" bridge") || t.contains("models_state") { return "hub" }
        if t.contains("ax coder/") || t.contains("xterminal") || t.contains("x-terminal/") || t.contains("xterminal") || t.contains("chatsessionmodel") { return "coder" }
        return "system"
    }

    private static func moduleFromPrefix(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Accept both ASCII ':' and Chinese '：'.
        if t.hasPrefix("hub:") || t.hasPrefix("hub：") { return "hub" }
        if t.hasPrefix("coder:") || t.hasPrefix("coder：") { return "coder" }
        if t.hasPrefix("shared:") || t.hasPrefix("shared：") { return "shared" }
        if t.hasPrefix("system:") || t.hasPrefix("system：") { return "system" }
        return nil
    }

    private static func looksMultiModuleRepo(_ root: URL) -> Bool {
        // Same conservative markers as AXMemoryModulePrefixer.
        let markers: [String] = [
            "RELFlowHub",
            "X-Terminal",
            "X-Terminal",
            "XTerminal",
            "protocol",
        ]
        var hits = 0
        for m in markers {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent(m).path) {
                hits += 1
            }
        }
        return hits >= 2
    }

    private static func hasStrongSignal(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        if isTrivial(t) { return false }
        let lower = t.lowercased()
        let keywords = [
            "实现", "新增", "支持", "接入", "集成", "添加", "修改",
            "更新", "重构", "优化", "修复", "适配", "迁移", "拆分",
            "合并", "配置", "权限", "网络", "审批", "模型", "路由"
        ]
        if lower.count >= 40 { return true }
        if keywords.contains(where: { lower.contains($0) }) && lower.count >= 6 { return true }
        if lower.contains(".swift") || lower.contains(".json") || lower.contains(".md") { return true }
        if lower.contains("ax coder") || lower.contains("x-terminal") || lower.contains("xterminal") || lower.contains("rel flow hub") || lower.contains("sources/") { return true }
        return false
    }

    // Confidence is used by the auto-promotion layer to decide whether to promote the skill without user confirmation.
    // Keep this conservative; false positives create noisy skills.
    private static func confidenceScore(items: [String], user: String, assistant: String, hasSignal: Bool) -> Double {
        let combined = (user + "\n" + assistant).lowercased()
        if explicitSkillRequest(combined) {
            return 0.99
        }

        var score = 0.0
        if hasSignal { score += 0.20 }
        if items.count >= 2 { score += 0.20 }
        if items.count >= 4 { score += 0.20 }
        if containsDurableKeywords(combined) { score += 0.20 }
        if containsFileRef(combined) { score += 0.10 }
        if hasStrongSignal(user) { score += 0.10 }
        if hasStrongSignal(assistant) { score += 0.05 }
        return min(0.95, score)
    }

    private static func explicitSkillRequest(_ lower: String) -> Bool {
        // "make this a skill" / "promote to skill" / "固化为 skill" etc.
        let patterns = [
            "做成skill", "做成 skill", "做成一个skill", "做成一个 skill",
            "晋升skill", "晋升 skill", "升级skill", "升级 skill",
            "写成skill", "写成 skill", "写进skill", "写进 skill",
            "固化为skill", "固化为 skill", "沉淀为skill", "沉淀为 skill",
            "skill化", "skills化", "skills 化", "skill 化",
        ]
        if patterns.contains(where: { lower.contains($0) }) { return true }
        return false
    }

    private static func containsFileRef(_ lower: String) -> Bool {
        if lower.contains(".swift") || lower.contains(".json") || lower.contains(".md") { return true }
        if lower.contains("sources/") || lower.contains("xterminal/") || lower.contains("xterminal/") { return true }
        return false
    }

    private static func containsDurableKeywords(_ lower: String) -> Bool {
        let keywords = [
            "schema", "规范", "规则", "机制", "目录", "结构", "触发",
            "workflow", "索引", "导航", "策略", "权限", "路由", "模型"
        ]
        return keywords.contains(where: { lower.contains($0) })
    }

    private static func makeTitle(items: [String], user: String, assistant: String) -> String {
        if let first = items.first, !first.isEmpty {
            return truncate(first, max: 64)
        }
        if let fromUser = firstLine(user), !fromUser.isEmpty {
            return truncate(fromUser, max: 64)
        }
        if let fromAssistant = firstLine(assistant), !fromAssistant.isEmpty {
            return truncate(fromAssistant, max: 64)
        }
        return "未命名技能候选"
    }

    private static func makeSummary(items: [String], user: String, assistant: String) -> String {
        if !items.isEmpty {
            return items.prefix(3).joined(separator: "；")
        }
        let u = firstLine(user) ?? ""
        let a = firstLine(assistant) ?? ""
        let joined = [u, a].filter { !$0.isEmpty }.joined(separator: " / ")
        return truncate(joined.isEmpty ? "候选来自对话内容" : joined, max: 160)
    }

    private static func firstLine(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let line = trimmed.split(separator: "\n").first {
            return String(line).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private static func truncate(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        let idx = s.index(s.startIndex, offsetBy: max)
        return String(s[..<idx])
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
        "完成了吗", "完成了么", "完成了吗", "好了么", "好了嘛",
        "开始", "开始吧", "下一步", "下一个", "继续", "继续做",
        "谢谢", "收到", "知道了", "明白了", "好的谢谢"
    ]
}

enum AXSkillAutoPromoter {
    // Conservative: only auto-promote when confidence is very high or user explicitly asked.
    static let autoPromoteThreshold = 0.90

    static func maybeAutoPromote(ctx: AXProjectContext, detected: [AXSkillCandidate]) {
        let eligible = detected.filter { shouldAutoPromote($0) }
        guard !eligible.isEmpty else { return }
        guard let skillsDir = AXSkillsLibrary.ensureSkillsDirectory() else { return }

        let existing = AXSkillCandidateStore.loadCandidates(for: ctx)
        for cand in eligible {
            let key = AXSkillCandidateStore.titleKey(cand.title)
            if key.isEmpty { continue }

            let record = existing.first(where: { AXSkillCandidateStore.titleKey($0.title) == key })
            if let record {
                if record.status == "approved" || record.status == "rejected" { continue }
                if let sn = record.skillName, !sn.isEmpty { continue }
            }

            guard let skillName = AXSkillsLibrary.promoteCandidate(cand, skillsDir: skillsDir) else { continue }

            if let record {
                AXSkillCandidateStore.updateCandidate(id: record.id, status: "approved", skillName: skillName, promotedBy: "auto", for: ctx)
            } else {
                var saved = cand
                saved.status = "approved"
                saved.skillName = skillName
                saved.promotedBy = "auto"
                _ = AXSkillCandidateStore.appendCandidates([saved], for: ctx)
            }

            AXProjectStore.appendRawLog(
                [
                    "type": "skill_promote",
                    "mode": "auto",
                    "created_at": Date().timeIntervalSince1970,
                    "title": cand.title,
                    "skill_name": skillName,
                    "confidence": cand.confidence as Any,
                ],
                for: ctx
            )
        }
    }

    private static func shouldAutoPromote(_ cand: AXSkillCandidate) -> Bool {
        let conf = cand.confidence ?? 0
        return conf >= autoPromoteThreshold
    }
}
