import Foundation

enum AXMemoryMarkdown {
    static func render(_ mem: AXMemory) -> String {
        var out: [String] = []
        out.append("# X-Terminal Memory")
        out.append("")
        out.append("- project: \(mem.projectName)")
        out.append("- root: `\(mem.projectRoot)`")
        out.append("- updatedAt: \(iso(mem.updatedAt))")
        out.append("")

        out.append("## How To Start（读法）")
        out.append("- 先读本文件拿到 Goal/State/Next。")
        out.append("- 接手/崩溃恢复：再读最近上下文（`.xterminal/AX_RECENT.md`，建议至少最近 12 轮；来源：`.xterminal/recent_context.json`）。")
        if let skillsDir = AXSkillsLibrary.resolveSkillsDirectory() {
            let url = skillsDir
                .appendingPathComponent("memory-core", isDirectory: true)
                .appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: url.path) {
                out.append("- 再读 memory-core：`\(url.path)`（或用顶部 Edit Skill 按钮打开）")
            } else {
                out.append("- 再读 memory-core（用顶部 Edit Skill 按钮打开）")
            }
        } else {
            out.append("- 再读 memory-core（用顶部 Edit Skill 按钮打开）")
        }

        let rootURL = URL(fileURLWithPath: mem.projectRoot)
        let projectId = AXProjectRegistryStore.projectId(forRoot: rootURL)
        if let skillsDir = AXSkillsLibrary.ensureSkillsDirectory(),
           let projectDir = AXSkillsLibrary.projectSkillsDir(projectId: projectId, projectName: mem.projectName, skillsDir: skillsDir) {
            out.append("- 本项目 Skills Index：`\((projectDir.appendingPathComponent("skills-index.md")).path)`")
            out.append("- Forgotten Vault (L0)：`\((projectDir.appendingPathComponent("forgotten-vault", isDirectory: true).appendingPathComponent("references", isDirectory: true).appendingPathComponent("index.md")).path)`")
            out.append("- Forgotten Vault (L1)：`\((projectDir.appendingPathComponent("forgotten-vault", isDirectory: true).appendingPathComponent("references", isDirectory: true).appendingPathComponent("_deep", isDirectory: true).appendingPathComponent("index.md")).path)`")
        } else {
            out.append("- skills_dir 不可用：请在 Settings/Import Skills 配置技能库目录，或设置环境变量 `XTERMINAL_SKILLS_DIR`。")
        }

        out.append("- 回溯触发词（如“之前说过/我记得/旧方案”）出现时：先查 Vault 索引，再按需打开命中记录；Vault 默认不加载。")
        out.append("")

        out.append("## Key Paths（入口路径）")
        out.append(bullets(keyPaths(projectRoot: rootURL)))
        out.append("")

        out.append("## Goal")
        out.append(mem.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(empty)" : mem.goal)
        out.append("")

        out.append("## Requirements")
        out.append(bullets(mem.requirements))
        out.append("")

        out.append("## Current State")
        out.append(bullets(mem.currentState))
        out.append("")

        out.append("## Decisions")
        out.append(bullets(mem.decisions))
        out.append("")

        out.append("## Next Steps")
        out.append(bullets(mem.nextSteps))
        out.append("")

        out.append("## Open Questions")
        out.append(bullets(mem.openQuestions))
        out.append("")

        out.append("## Risks")
        out.append(bullets(mem.risks))
        out.append("")

        if !mem.recommendations.isEmpty {
            out.append("## Recommendations")
            out.append(bullets(mem.recommendations))
            out.append("")
        }

        return out.joined(separator: "\n")
    }

    private static func keyPaths(projectRoot: URL) -> [String] {
        var out: [String] = []

        let dataDir = projectRoot.appendingPathComponent(".xterminal", isDirectory: true)
        out.append("Project memory: `\(dataDir.appendingPathComponent("AX_MEMORY.md").path)`")
        out.append("Project memory JSON: `\(dataDir.appendingPathComponent("ax_memory.json").path)`")
        out.append("Recent context (crash-safe): `\(dataDir.appendingPathComponent("AX_RECENT.md").path)`")
        out.append("Recent context JSON: `\(dataDir.appendingPathComponent("recent_context.json").path)`")
        out.append("Pending actions (crash-safe): `\(dataDir.appendingPathComponent("pending_actions.json").path)`")
        out.append("Raw log: `\(dataDir.appendingPathComponent("raw_log.jsonl").path)`")
        out.append("Usage log: `\(dataDir.appendingPathComponent("usage.jsonl").path)`")
        out.append("Skill candidates: `\(dataDir.appendingPathComponent("skill_candidates.json").path)`")
        out.append("Curation suggestions: `\(dataDir.appendingPathComponent("curation_suggestions.json").path)`")
        out.append("Project config: `\(dataDir.appendingPathComponent("config.json").path)`")

        let candidates: [String] = [
            "Package.swift",
            "Sources",
            "Tests",
            "README.md",
            "package.json",
            "pnpm-lock.yaml",
            "yarn.lock",
            "src",
            "pyproject.toml",
            "requirements.txt",
            "tools/build_hub_app.command",
            "x-terminal/x-terminal-legacy/X-Terminal/tools/build_x_terminal_app.command",
        ]
        for rel in candidates {
            let url = projectRoot.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: url.path) {
                out.append("Entry: `\(url.path)`")
            }
        }

        if out.count > 20 {
            out = Array(out.prefix(20))
        }
        return out
    }

    private static func bullets(_ items: [String]) -> String {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if cleaned.isEmpty {
            return "- (none)"
        }
        return cleaned.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func iso(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
}
