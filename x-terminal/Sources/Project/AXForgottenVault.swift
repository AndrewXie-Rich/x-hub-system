import Foundation

// Project-level cold storage for "complete context", designed to stay out of default prompting.
// Writes are best-effort and must never block core chat/memory flows.
enum AXForgottenVault {
    // Keep L0 index small for fast grep/open; older entries automatically sink to L1.
    private static let maxL0Entries = 200

    static func autoArchiveTurn(ctx: AXProjectContext, turn: AXConversationTurn, delta: AXMemoryDelta) {
        guard shouldArchive(turn: turn, delta: delta) else { return }

        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        guard let skillsDir = AXSkillsLibrary.ensureSkillsDirectory(),
              let projectDir = AXSkillsLibrary.projectSkillsDir(projectId: projectId, projectName: ctx.projectName(), skillsDir: skillsDir) else {
            return
        }

        let vaultDir = projectDir.appendingPathComponent("forgotten-vault", isDirectory: true)
        let refsDir = vaultDir.appendingPathComponent("references", isDirectory: true)
        let deepDir = refsDir.appendingPathComponent("_deep", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
        } catch {
            return
        }

        ensureSkeleton(vaultDir: vaultDir, projectDir: projectDir, projectName: ctx.projectName())

        let title = archiveTitle(turn: turn, delta: delta)
        let module = inferModule(turn: turn, delta: delta)
        var keywords = archiveKeywords(turn: turn, delta: delta)
        keywords = withModuleKeyword(module, keywords: keywords)

        let ts = Date(timeIntervalSince1970: turn.createdAt)
        let fileStamp = compactTimestamp(ts)
        let slug = fileSlug(title)
        let fileBase = "\(fileStamp)-\(slug)"
        let fileName = uniqueFileName(base: fileBase, ext: "md", in: refsDir)
        let entryURL = refsDir.appendingPathComponent(fileName)

        let content = renderEntry(
            projectName: ctx.projectName(),
            projectId: projectId,
            createdAt: turn.createdAt,
            title: title,
            module: module,
            keywords: keywords,
            rawLogPath: ctx.rawLogURL.path,
            user: turn.user,
            assistant: turn.assistant,
            delta: delta
        )
        do {
            try XTStoreWriteSupport.writeUTF8Text(content, to: entryURL)
        } catch {
            return
        }

        let rel = "references/\(fileName)"
        appendIndexLine(
            indexURL: refsDir.appendingPathComponent("index.md"),
            line: indexLine(ts: ts, title: title, keywords: keywords, relPath: rel)
        )

        // Keep L0 small; sink older entries into L1.
        maybeSinkL0ToDeep(refsDir: refsDir)
    }

    // MARK: - Skeleton

    private static func ensureSkeleton(vaultDir: URL, projectDir: URL, projectName: String) {
        // Ensure SKILL.md exists so this folder behaves like a skill.
        let skillMDURL = vaultDir.appendingPathComponent("SKILL.md")
        if !FileManager.default.fileExists(atPath: skillMDURL.path) {
            let md = """
            ---
            name: forgotten-vault
            description: 本项目的遗忘内容库（冷存）。保存完整上下文但默认不加载；需要回溯时通过索引精准打开对应记录。
            scope: system
            touches_paths:
              - <skills_dir>/_projects/<project>/forgotten-vault/**
            entrypoints:
              - <skills_dir>/_projects/<project>/forgotten-vault/references/index.md
              - <skills_dir>/_projects/<project>/forgotten-vault/references/_deep/index.md
            common_ops:
              inspect:
                - Open references/index.md; if needed open references/_deep/index.md
            ---

            # Forgotten Vault（项目级）

            ## 默认原则
            - Vault 默认全自动写入：非平凡对话会自动归档到 L0；你有空再整理与下沉。
            - 默认不进入主上下文；仅当“回溯触发词”出现时才按索引精准打开。

            ## 分层结构
            - L0：`references/index.md` + `references/<...>.md`
            - L1：`references/_deep/index.md` + `references/_deep/<...>.md`

            ## 入口
            - L0 索引：`references/index.md`
            - L1 索引：`references/_deep/index.md`
            """
            try? XTStoreWriteSupport.writeUTF8Text(md, to: skillMDURL)
        }

        let refsDir = vaultDir.appendingPathComponent("references", isDirectory: true)
        let deepDir = refsDir.appendingPathComponent("_deep", isDirectory: true)
        try? FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)

        let idx0 = refsDir.appendingPathComponent("index.md")
        if !FileManager.default.fileExists(atPath: idx0.path) {
            let s = """
            # Forgotten Vault Index（项目级）

            深层入口：
            - L1：`references/_deep/index.md`

            每条 1 行，格式建议：
            - `<YYYYMMDD>-<topic> — <一句话摘要>（关键词：module:hub,a,b,c）（文件：references/<YYYYMMDD>-<topic>.md）`

            建议：
            - `module:hub|coder|system|shared` 作为第 1 个关键词，便于后续按模块回收/晋升。

            """
            try? XTStoreWriteSupport.writeUTF8Text(s, to: idx0)
        }

        let idx1 = deepDir.appendingPathComponent("index.md")
        if !FileManager.default.fileExists(atPath: idx1.path) {
            let s = """
            # Forgotten Vault Deep Index（L1）

            上层入口：
            - L0：`../index.md`

            每条 1 行，格式建议：
            - `<YYYYMMDD>-<topic> — <一句话摘要>（关键词：module:hub,a,b,c）（文件：references/_deep/<YYYYMMDD>-<topic>.md）`

            建议：
            - `module:hub|coder|system|shared` 作为第 1 个关键词，便于后续按模块回收/晋升。

            """
            try? XTStoreWriteSupport.writeUTF8Text(s, to: idx1)
        }

        // Ensure project skills-index contains forgotten-vault.
        let desc = "遗忘内容库（完整上下文冷存 + L0/L1 索引）"
        AXSkillsLibrary.updateProjectSkillsIndex(projectDir: projectDir, skillName: "forgotten-vault", summary: desc)
    }

    // MARK: - Index + Sinking

    private static func appendIndexLine(indexURL: URL, line: String) {
        let existing = (try? String(contentsOf: indexURL, encoding: .utf8)) ?? ""
        if existing.contains(line) { return }
        let out: String
        if existing.isEmpty {
            out = "# Forgotten Vault Index\n\n" + line + "\n"
        } else {
            out = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + line + "\n"
        }
        try? XTStoreWriteSupport.writeUTF8Text(out, to: indexURL)
    }

    private static func maybeSinkL0ToDeep(refsDir: URL) {
        let idx0 = refsDir.appendingPathComponent("index.md")
        let deepDir = refsDir.appendingPathComponent("_deep", isDirectory: true)
        let idx1 = deepDir.appendingPathComponent("index.md")
        guard let text = try? String(contentsOf: idx0, encoding: .utf8) else { return }

        var header: [String] = []
        var entries: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("- ") {
                entries.append(raw)
            } else {
                header.append(raw)
            }
        }

        if entries.count <= maxL0Entries { return }
        let sinkCount = max(0, entries.count - maxL0Entries)
        if sinkCount == 0 { return }

        let toSink = Array(entries.prefix(sinkCount))
        entries.removeFirst(sinkCount)

        var deepAppend: [String] = []
        for line in toSink {
            guard let rel = extractRelPath(fromIndexLine: line) else { continue }
            guard rel.hasPrefix("references/") && !rel.hasPrefix("references/_deep/") else { continue }
            let fileName = String(rel.dropFirst("references/".count))
            let src = refsDir.appendingPathComponent(fileName)
            let dest = deepDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: src.path), !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.moveItem(at: src, to: dest)
            }
            let updated = line.replacingOccurrences(of: rel, with: "references/_deep/\(fileName)")
            deepAppend.append(updated)
        }

        // Rewrite L0 index.
        let out0 = (header + entries).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        try? XTStoreWriteSupport.writeUTF8Text(out0, to: idx0)

        // Append to L1 index.
        let existing1 = (try? String(contentsOf: idx1, encoding: .utf8)) ?? ""
        let out1: String
        if existing1.isEmpty {
            out1 = "# Forgotten Vault Deep Index（L1）\n\n" + deepAppend.joined(separator: "\n") + "\n"
        } else {
            out1 = existing1.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + deepAppend.joined(separator: "\n") + "\n"
        }
        try? XTStoreWriteSupport.writeUTF8Text(out1, to: idx1)
    }

    private static func extractRelPath(fromIndexLine line: String) -> String? {
        guard let start = line.range(of: "（文件：") else { return nil }
        guard let end = line.range(of: "）", range: start.upperBound..<line.endIndex) else { return nil }
        let raw = line[start.upperBound..<end.lowerBound]
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    // MARK: - Rendering

    private static func renderEntry(
        projectName: String,
        projectId: String,
        createdAt: Double,
        title: String,
        module: String,
        keywords: [String],
        rawLogPath: String,
        user: String,
        assistant: String,
        delta: AXMemoryDelta
    ) -> String {
        let d = Date(timeIntervalSince1970: createdAt)
        let iso = iso8601(d)
        let kws = keywords.joined(separator: ", ")
        let deltaLines = deltaSnippets(delta).map { "- \($0)" }.joined(separator: "\n")

        return """
# \(title)

- Project: \(projectName)
- ProjectId: \(projectId)
- CreatedAt: \(iso) (\(createdAt))
- Module: \(module)
- Reason: auto_archive_turn
- Keywords: \(kws.isEmpty ? "(none)" : kws)
- RawLog: \(rawLogPath) (find: created_at=\(createdAt))

## Memory Delta（摘要）
\(deltaLines.isEmpty ? "- (none)" : deltaLines)

## User
\(user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(empty)" : user)

## Assistant
\(assistant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(empty)" : assistant)
"""
    }

    private static func indexLine(ts: Date, title: String, keywords: [String], relPath: String) -> String {
        let stamp = humanTimestamp(ts)
        let short = truncateInline(title, max: 60)
        let kw = keywords.prefix(5).joined(separator: ",")
        let kwPart = kw.isEmpty ? "" : "（关键词：\(kw)）"
        return "- \(stamp) — \(short)\(kwPart)（文件：\(relPath)）"
    }

    // MARK: - Policy

    private static func shouldArchive(turn: AXConversationTurn, delta: AXMemoryDelta) -> Bool {
        let u = turn.user.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = turn.assistant.trimmingCharacters(in: .whitespacesAndNewlines)
        let deltaItems = deltaSnippets(delta)
        if !deltaItems.isEmpty { return true }
        if hasStrongSignal(u) || hasStrongSignal(a) { return true }
        if isTrivial(u) && isTrivial(a) { return false }
        // Default: archive if there's at least some content.
        return !(u.isEmpty && a.isEmpty)
    }

    private static func archiveTitle(turn: AXConversationTurn, delta: AXMemoryDelta) -> String {
        let items = deltaSnippets(delta)
        if let first = items.first, !first.isEmpty {
            return truncateInline(first, max: 80)
        }
        if let line = firstLine(turn.user) {
            return truncateInline(line, max: 80)
        }
        if let line = firstLine(turn.assistant) {
            return truncateInline(line, max: 80)
        }
        return "Auto Archived Turn"
    }

    private static func archiveKeywords(turn: AXConversationTurn, delta: AXMemoryDelta) -> [String] {
        var out: [String] = []
        let items = deltaSnippets(delta)
        for s in items.prefix(6) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            out.append(truncateInline(t, max: 24))
        }

        let t = (turn.user + "\n" + turn.assistant).lowercased()
        let keywords = [
            "memory", "skill", "skills", "vault", "forgotten",
            "模型", "路由", "网络", "权限", "审批", "keychain",
            "hub", "bridge", "ax coder", "x-terminal", "xterminal", "rel flow hub"
        ]
        for k in keywords where t.contains(k) {
            out.append(k)
        }

        // De-dup.
        var seen: Set<String> = []
        var uniq: [String] = []
        for k in out {
            let n = k.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if n.isEmpty || seen.contains(n) { continue }
            seen.insert(n)
            uniq.append(k)
        }
        return Array(uniq.prefix(10))
    }

    private static func withModuleKeyword(_ module: String, keywords: [String]) -> [String] {
        let m = module.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tag = m.isEmpty ? "module:system" : "module:\(m)"
        var out: [String] = [tag]
        for k in keywords {
            let kk = k.trimmingCharacters(in: .whitespacesAndNewlines)
            if kk.isEmpty { continue }
            if kk.lowercased() == tag { continue }
            out.append(kk)
        }
        return Array(out.prefix(10))
    }

    private static func inferModule(turn: AXConversationTurn, delta: AXMemoryDelta) -> String {
        // 1) Prefer explicit module prefixes from memory deltas.
        let items =
            delta.requirementsAdd +
            delta.currentStateAdd +
            delta.decisionsAdd +
            delta.nextStepsAdd +
            delta.openQuestionsAdd +
            delta.risksAdd +
            delta.recommendationsAdd
        for s in items {
            if let m = moduleFromPrefix(s) { return m }
        }

        // 2) Heuristic from text/path hints.
        let t = (turn.user + "\n" + turn.assistant).lowercased()
        if t.contains("protocol/") { return "shared" }
        if t.contains("relflowhub/") || t.contains("bridge") || t.contains("models_state") { return "hub" }
        if t.contains("ax coder/") || t.contains("xterminal") || t.contains("x-terminal/") || t.contains("xterminal") || t.contains("chatsessionmodel") { return "coder" }
        return "system"
    }

    private static func moduleFromPrefix(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("hub:") { return "hub" }
        if t.hasPrefix("coder:") { return "coder" }
        if t.hasPrefix("shared:") { return "shared" }
        if t.hasPrefix("system:") { return "system" }
        return nil
    }

    private static func deltaSnippets(_ d: AXMemoryDelta) -> [String] {
        var out: [String] = []
        if let g = d.goalUpdate?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
            out.append("Goal: \(g)")
        }
        out.append(contentsOf: d.requirementsAdd.map { "Req+: \($0)" })
        out.append(contentsOf: d.currentStateAdd.map { "State+: \($0)" })
        out.append(contentsOf: d.decisionsAdd.map { "Decision+: \($0)" })
        out.append(contentsOf: d.nextStepsAdd.map { "Next+: \($0)" })
        out.append(contentsOf: d.openQuestionsAdd.map { "Q+: \($0)" })
        out.append(contentsOf: d.risksAdd.map { "Risk+: \($0)" })

        out.append(contentsOf: d.requirementsRemove.map { "Req-: \($0)" })
        out.append(contentsOf: d.currentStateRemove.map { "State-: \($0)" })
        out.append(contentsOf: d.nextStepsRemove.map { "Next-: \($0)" })
        out.append(contentsOf: d.openQuestionsRemove.map { "Q-: \($0)" })
        out.append(contentsOf: d.risksRemove.map { "Risk-: \($0)" })

        let cleaned = out
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isTrivial($0) }
        return Array(cleaned.prefix(24))
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
        if lower.count >= 80 { return true }
        if keywords.contains(where: { lower.contains($0) }) && lower.count >= 6 { return true }
        if lower.contains(".swift") || lower.contains(".json") || lower.contains(".md") { return true }
        return false
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
        "谢谢", "收到", "知道了", "明白了", "好的谢谢"
    ]

    // MARK: - Utils

    private static func firstLine(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let line = trimmed.split(separator: "\n").first {
            return String(line).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private static func truncateInline(_ s: String, max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= max { return t }
        let idx = t.index(t.startIndex, offsetBy: max)
        return String(t[..<idx])
    }

    private static func compactTimestamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: d)
    }

    private static func humanTimestamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    private static func iso8601(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    private static func fileSlug(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let lower = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = ""
        var lastDash = false
        for uni in lower.unicodeScalars {
            if allowed.contains(uni) {
                out.unicodeScalars.append(uni)
                lastDash = false
            } else {
                if !lastDash {
                    out.append("-")
                    lastDash = true
                }
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "turn" : trimmed
    }

    private static func uniqueFileName(base: String, ext: String, in dir: URL) -> String {
        var name = "\(base).\(ext)"
        var idx = 2
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
            name = "\(base)-\(idx).\(ext)"
            idx += 1
        }
        return name
    }
}
