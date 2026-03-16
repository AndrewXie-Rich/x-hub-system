import Foundation

enum AXProjectStore {
    static func loadOrCreateConfig(for ctx: AXProjectContext) throws -> AXProjectConfig {
        try ctx.ensureDirs()

        if FileManager.default.fileExists(atPath: ctx.configURL.path) {
            let data = try Data(contentsOf: ctx.configURL)
            if let cfg = try? JSONDecoder().decode(AXProjectConfig.self, from: data) {
                var out = cfg
                out.schemaVersion = AXProjectConfig.currentSchemaVersion

                let filtered = AXProjectStackDetector.filterApplicableVerifyCommands(out.verifyCommands, forProjectRoot: ctx.root)
                if filtered != out.verifyCommands {
                    out.verifyCommands = filtered
                }

                // Auto-match when verify commands are missing or were filtered out as inapplicable.
                if out.verifyCommands.isEmpty {
                    let recommended = AXProjectStackDetector.recommendedVerifyCommands(forProjectRoot: ctx.root)
                    out.verifyCommands = recommended
                }

                if out != cfg {
                    let backup = ctx.xterminalDir.appendingPathComponent("config.autofix_\(Int(Date().timeIntervalSince1970)).json")
                    try? FileManager.default.copyItem(at: ctx.configURL, to: backup)
                    try? saveConfig(out, for: ctx)
                }

                return out
            }
            // Preserve broken config.
            let backup = ctx.xterminalDir.appendingPathComponent("config.broken_\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: ctx.configURL, to: backup)
        }

        let fresh = AXProjectConfig.default(forProjectRoot: ctx.root)
        try saveConfig(fresh, for: ctx)
        return fresh
    }

    static func saveConfig(_ cfg: AXProjectConfig, for ctx: AXProjectContext) throws {
        try ctx.ensureDirs()
        var cur = cfg
        cur.schemaVersion = AXProjectConfig.currentSchemaVersion
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(cur)
        try writeAtomic(data: data, to: ctx.configURL)
    }

    @discardableResult
    static func upsertAutomationRecipe(
        _ recipe: AXAutomationRecipeRuntimeBinding,
        activate: Bool = false,
        for ctx: AXProjectContext
    ) throws -> AXAutomationRecipeRuntimeBinding {
        var config = try loadOrCreateConfig(for: ctx)
        let stored = config.upsertAutomationRecipe(recipe, activate: activate)
        try saveConfig(config, for: ctx)
        appendRawLog(
            [
                "type": "automation_recipe",
                "action": "upsert",
                "recipe_id": stored.recipeID,
                "recipe_ref": stored.ref,
                "lifecycle_state": stored.lifecycleState.rawValue,
                "active_recipe_ref": config.activeAutomationRecipeRef,
                "timestamp_ms": Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            ],
            for: ctx
        )
        return stored
    }

    static func loadMemoryIfPresent(for ctx: AXProjectContext) -> AXMemory? {
        if FileManager.default.fileExists(atPath: ctx.memoryJSONURL.path) {
            guard let data = try? Data(contentsOf: ctx.memoryJSONURL),
                  var memory = try? JSONDecoder().decode(AXMemory.self, from: data) else {
                return nil
            }
            memory = AXMemoryModulePrefixer.normalizeIfNeeded(memory, projectRoot: ctx.root)
            return memory
        }

        if FileManager.default.fileExists(atPath: ctx.memoryMarkdownURL.path) {
            let legacyText = (try? String(contentsOf: ctx.memoryMarkdownURL, encoding: .utf8)) ?? ""
            let legacyTrimmed = legacyText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !legacyTrimmed.isEmpty,
                  var parsed = parseLegacyMemoryMarkdown(
                    legacyText,
                    projectName: ctx.projectName(),
                    projectRoot: ctx.root.path
                  ) else {
                return nil
            }
            parsed = AXMemoryModulePrefixer.normalizeIfNeeded(parsed, projectRoot: ctx.root)
            return parsed
        }

        return nil
    }

    static func loadOrCreateMemory(for ctx: AXProjectContext) throws -> AXMemory {
        try ctx.ensureDirs()

        if FileManager.default.fileExists(atPath: ctx.memoryJSONURL.path) {
            let data = try Data(contentsOf: ctx.memoryJSONURL)
            do {
                var mem = try JSONDecoder().decode(AXMemory.self, from: data)
                // Monorepo post-processing: retrofit historical items with module prefixes.
                let normalized = AXMemoryModulePrefixer.normalizeIfNeeded(mem, projectRoot: ctx.root)
                if normalized != mem {
                    mem = normalized
                    try? saveMemory(mem, for: ctx)
                }
                // If memory is empty but we have turns, seed minimal context.
                if mem.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, mem.requirements.isEmpty {
                    if let seed = lastUserTurnText(ctx: ctx) {
                        mem.goal = seed
                        mem.requirements = [seed]
                        try? saveMemory(mem, for: ctx)
                    }
                }
                return mem
            } catch {
                // If decode fails, preserve the broken file and start fresh.
                let backup = ctx.xterminalDir.appendingPathComponent("ax_memory.broken_\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: ctx.memoryJSONURL, to: backup)
                return AXMemory.new(projectName: ctx.projectName(), projectRoot: ctx.root.path)
            }
        }

        // Legacy/migration: some projects may already have a hand-written AX_MEMORY.md but no ax_memory.json yet.
        // Avoid silently overwriting that markdown on first run; instead back it up and best-effort parse it.
        if FileManager.default.fileExists(atPath: ctx.memoryMarkdownURL.path) {
            let legacyText = (try? String(contentsOf: ctx.memoryMarkdownURL, encoding: .utf8)) ?? ""
            let legacyTrimmed = legacyText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !legacyTrimmed.isEmpty {
                let ts = Int(Date().timeIntervalSince1970)
                let backup = ctx.xterminalDir.appendingPathComponent("AX_MEMORY.legacy_\(ts).md")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try? writeAtomic(data: Data(legacyText.utf8), to: backup)
                }

                if var parsed = parseLegacyMemoryMarkdown(legacyText, projectName: ctx.projectName(), projectRoot: ctx.root.path) {
                    parsed = AXMemoryModulePrefixer.normalizeIfNeeded(parsed, projectRoot: ctx.root)
                    try saveMemory(parsed, for: ctx)
                    return parsed
                }
            }
        }

        let fresh = AXMemory.new(projectName: ctx.projectName(), projectRoot: ctx.root.path)
        try saveMemory(fresh, for: ctx)
        return fresh
    }

    private static func lastUserTurnText(ctx: AXProjectContext) -> String? {
        guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path) else { return nil }
        guard let data = try? Data(contentsOf: ctx.rawLogURL), let s = String(data: data, encoding: .utf8) else { return nil }
        var last: String? = nil
        for line in s.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let ld = line.data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any] else { continue }
            guard (obj["type"] as? String) == "turn" else { continue }
            let u = (obj["user"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !u.isEmpty {
                last = u
            }
        }
        return last
    }

    private static func parseLegacyMemoryMarkdown(_ text: String, projectName: String, projectRoot: String) -> AXMemory? {
        struct Acc {
            var current: String? = nil
            var sections: [String: [String]] = [:]
        }

        var acc = Acc()
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("## ") {
                let sec = line.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                acc.current = sec
                continue
            }
            guard let cur = acc.current else { continue }
            acc.sections[cur, default: []].append(line)
        }

        func cleanedLines(_ name: String) -> [String] {
            let lines = acc.sections[name] ?? []
            return lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { $0 != "- (none)" && $0 != "(none)" && $0 != "(empty)" }
        }

        func parseGoal() -> String {
            let lines = cleanedLines("Goal")
            if lines.isEmpty { return "" }
            // If the goal is a bullet, strip the leading marker for readability.
            if lines.count == 1, lines[0].hasPrefix("- ") {
                return String(lines[0].dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return lines.map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }.joined(separator: "\n")
        }

        func parseList(_ name: String) -> [String] {
            let lines = cleanedLines(name)
            if lines.isEmpty { return [] }
            let bullets = lines.compactMap { l -> String? in
                guard l.hasPrefix("- ") else { return nil }
                let t = String(l.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            if !bullets.isEmpty { return bullets }
            return lines
        }

        var mem = AXMemory.new(projectName: projectName, projectRoot: projectRoot)
        mem.goal = parseGoal()
        mem.requirements = parseList("Requirements")
        mem.currentState = parseList("Current State")
        mem.decisions = parseList("Decisions")
        mem.nextSteps = parseList("Next Steps")
        mem.openQuestions = parseList("Open Questions")
        mem.risks = parseList("Risks")
        mem.recommendations = parseList("Recommendations")
        mem.updatedAt = Date().timeIntervalSince1970

        let emptyGoal = mem.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let emptyLists = mem.requirements.isEmpty &&
            mem.currentState.isEmpty &&
            mem.decisions.isEmpty &&
            mem.nextSteps.isEmpty &&
            mem.openQuestions.isEmpty &&
            mem.risks.isEmpty &&
            mem.recommendations.isEmpty
        if emptyGoal && emptyLists { return nil }
        return mem
    }

    static func saveMemory(_ mem: AXMemory, for ctx: AXProjectContext) throws {
        try ctx.ensureDirs()
        var cur = mem
        cur.schemaVersion = AXMemory.currentSchemaVersion
        cur.updatedAt = Date().timeIntervalSince1970

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(cur)
        try writeAtomic(data: data, to: ctx.memoryJSONURL)

        let md = AXMemoryMarkdown.render(cur)
        try writeAtomic(data: Data(md.utf8), to: ctx.memoryMarkdownURL)

        let digest = statusDigest(for: cur)
        let stateSummary = firstNonEmpty(cur.currentState)
        let nextSummary = firstNonEmpty(cur.nextSteps)
        var blockerSummary = firstNonEmpty(cur.openQuestions)
        if blockerSummary.isEmpty {
            blockerSummary = firstNonEmpty(cur.risks)
        }
        let statusUpdate = AXProjectRegistryStore.updateStatusDigest(
            forRoot: ctx.root,
            digest: digest,
            lastSummaryAt: cur.updatedAt,
            currentState: stateSummary,
            nextStep: nextSummary,
            blocker: blockerSummary
        )

        if let entry = statusUpdate.entry {
            HubIPCClient.syncProject(entry)
            if statusUpdate.created {
                Task { @MainActor in
                    AXEventBus.shared.publish(.projectCreated(entry))
                }
            } else if statusUpdate.changed {
                Task { @MainActor in
                    AXEventBus.shared.publish(.projectUpdated(entry))
                }
            }
        }

        let config = try? loadOrCreateConfig(for: ctx)
        HubIPCClient.syncProjectCanonicalMemory(
            ctx: ctx,
            memory: cur,
            config: config
        )
    }

    static func appendRawLog(_ entry: [String: Any], for ctx: AXProjectContext) {
        try? ctx.ensureDirs()
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: []) else { return }
        appendJSONLLine(data, to: ctx.rawLogURL)
    }

    static func appendUsage(_ entry: [String: Any], for ctx: AXProjectContext) {
        try? ctx.ensureDirs()
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: []) else { return }
        appendJSONLLine(data, to: ctx.usageLogURL)
        AXModelRouteDiagnosticsStore.appendUsageIfNeeded(entry, for: ctx)
    }

    static func appendToolLog(
        action: String,
        input: [String: Any],
        output: String,
        ok: Bool,
        for ctx: AXProjectContext
    ) {
        let out = truncate(output, maxChars: 80_000)
        appendRawLog(
            [
                "type": "tool",
                "created_at": Date().timeIntervalSince1970,
                "action": action,
                "ok": ok,
                "input": input,
                "output": out,
            ],
            for: ctx
        )
    }

    static func usageSummary(for ctx: AXProjectContext) -> AXUsageSummary {
        guard FileManager.default.fileExists(atPath: ctx.usageLogURL.path) else {
            return .empty()
        }
        guard let data = try? Data(contentsOf: ctx.usageLogURL), let s = String(data: data, encoding: .utf8) else {
            return .empty()
        }

        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let todayStartTs = todayStart.timeIntervalSince1970

        var todayTokens = 0
        var totalTokens = 0
        var todayReq = 0
        var totalReq = 0

        for line in s.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let ld = line.data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any] else { continue }
            guard (obj["type"] as? String) == "ai_usage" else { continue }
            totalReq += 1
            let createdAt = (obj["created_at"] as? Double) ?? 0
            if createdAt >= todayStartTs { todayReq += 1 }

            let ptReal = intField(obj["prompt_tokens"])
            let otReal = intField(obj["output_tokens"])
            let ptEst = intField(obj["prompt_tokens_est"])
            let otEst = intField(obj["output_tokens_est"])

            let pt = (ptReal > 0) ? ptReal : ptEst
            let ot = (otReal > 0) ? otReal : otEst
            totalTokens += max(0, pt + ot)
            if createdAt >= todayStartTs { todayTokens += max(0, pt + ot) }
        }

        return AXUsageSummary(todayTokensEst: todayTokens, totalTokensEst: totalTokens, todayRequests: todayReq, totalRequests: totalReq)
    }

    private static func intField(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String, let i = Int(s) { return i }
        return 0
    }

    private static func appendJSONLLine(_ json: Data, to url: URL) {
        var line = json
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? line.write(to: url, options: .atomic)
            return
        }
        do {
            let fh = try FileHandle(forWritingTo: url)
            defer { try? fh.close() }
            try fh.seekToEnd()
            try fh.write(contentsOf: line)
        } catch {
            // Best-effort.
        }
    }

    private static func truncate(_ s: String, maxChars: Int) -> String {
        if s.count <= maxChars { return s }
        let idx = s.index(s.startIndex, offsetBy: maxChars)
        return String(s[..<idx]) + "\n\n[x-terminal] truncated"
    }

    private static func statusDigest(for mem: AXMemory) -> String {
        let goal = mem.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = firstNonEmpty(mem.currentState)
        let next = firstNonEmpty(mem.nextSteps)

        var parts: [String] = []
        if !state.isEmpty { parts.append(state) }
        if !next.isEmpty { parts.append(next) }
        if parts.isEmpty, !goal.isEmpty { parts.append(goal) }
        if parts.isEmpty { return "" }

        let joined = parts.joined(separator: " → ")
        return truncateInline(joined, maxChars: 160)
    }

    private static func firstNonEmpty(_ items: [String]) -> String {
        for s in items {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return ""
    }

    private static func truncateInline(_ s: String, maxChars: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= maxChars { return t }
        let idx = t.index(t.startIndex, offsetBy: maxChars)
        return String(t[..<idx])
    }

    private static func writeAtomic(data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tmp, to: url)
    }
}
