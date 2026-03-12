import Foundation

// Shared skills filesystem logic used by both UI-driven flows and background pipelines.
// Keep this file AppKit-free so it can be called from async/background contexts.
enum AXSkillsLibrary {
    static let skillsDirDefaultsKey = "xterminal_skills_dir"

    static func resolveSkillsDirectory() -> URL? {
        let envKeys = ["XTERMINAL_SKILLS_DIR"]
        for key in envKeys {
            let env = (ProcessInfo.processInfo.environment[key] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !env.isEmpty {
                let u = URL(fileURLWithPath: NSString(string: env).expandingTildeInPath)
                if FileManager.default.fileExists(atPath: u.path) {
                    return u
                }
            }
        }

        if let stored = UserDefaults.standard.string(forKey: skillsDirDefaultsKey),
           !stored.isEmpty {
            let u = URL(fileURLWithPath: NSString(string: stored).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: u.path) {
                return u
            }
        }

        // Dev builds may place the app bundle under `x-terminal/build` or repo-level `build`.
        let bundleDir = Bundle.main.bundleURL.deletingLastPathComponent()
        let repoRoot = bundleDir.deletingLastPathComponent()
        let devCandidates = [
            repoRoot.appendingPathComponent("skills", isDirectory: true),
            repoRoot.appendingPathComponent("x-terminal", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true),
        ]
        for candidate in devCandidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        let supportBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let support = supportBase
            .appendingPathComponent("X-Terminal", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        if FileManager.default.fileExists(atPath: support.path) {
            return support
        }
        return nil
    }

    static func ensureSkillsDirectory() -> URL? {
        if let existing = resolveSkillsDirectory() {
            return existing
        }
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("X-Terminal", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            return support
        } catch {
            return nil
        }
    }

    static func projectsRoot(skillsDir: URL) -> URL {
        skillsDir.appendingPathComponent("_projects", isDirectory: true)
    }

    static func globalRoot(skillsDir: URL) -> URL {
        skillsDir.appendingPathComponent("_global", isDirectory: true)
    }

    static func projectSkillsDir(projectId: String, projectName: String, skillsDir: URL) -> URL? {
        let root = projectsRoot(skillsDir: skillsDir)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let suffix = String(projectId.prefix(8))
        if let existing = findProjectDir(in: root, suffix: suffix) {
            return existing
        }

        let safeName = sanitizePathComponent(projectName)
        let dirName = safeName.isEmpty ? "project-\(suffix)" : "\(safeName)-\(suffix)"
        let dir = root.appendingPathComponent(dirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Candidate Promotion (filesystem-only)

    static func promoteCandidate(_ cand: AXSkillCandidate, skillsDir: URL) -> String? {
        guard let projectDir = projectSkillsDir(projectId: cand.projectId, projectName: cand.projectName, skillsDir: skillsDir) else {
            return nil
        }
        let modulePrefix = normalizedModulePrefix(cand.module) ?? normalizedModulePrefix(inferModuleFromTitle(cand.title))
        // Prefer user-readable unicode folder names; fall back to ASCII slug if needed.
        let rawTitle = cand.title.isEmpty ? "skill" : cand.title
        let topicTitle = stripLeadingModuleHint(rawTitle)
        let preferred = sanitizePathComponent(truncateInline(topicTitle, max: 48))
        var baseName = preferred.isEmpty ? slugify(topicTitle) : preferred
        baseName = normalizeSkillNameComponent(baseName)
        let prefixed = applyModulePrefix(modulePrefix, baseName: baseName)
        let skillName = uniqueSkillName(prefixed, in: projectDir)
        let skillDir = projectDir.appendingPathComponent(skillName, isDirectory: true)
        let refsDir = skillDir.appendingPathComponent("references", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let skillTitle = cand.title.isEmpty ? skillName : cand.title
        let desc = truncateInline(cand.summary.isEmpty ? cand.title : cand.summary, max: 120)
        let scope = (cand.module ?? "system").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let skillMD = """
---
name: \(skillName)
description: \(desc)
scope: \(scope.isEmpty ? "system" : scope)
touches_paths:
  - <repo-rel-path>
entrypoints:
  - <entry-file-or-dir>
common_ops:
  build:
    - <command-or-script>
  run:
    - <command-or-script>
  debug:
    - <command-or-script>
---

# \(skillTitle)

## Overview
\(cand.summary.isEmpty ? "由候选自动生成，待补充细节。" : cand.summary)

## 何时使用
- 当需要处理“\(skillTitle)”相关改动或排查时

## 快速流程
1) 阅读 references/flow.md
2) 按 references/files.md 的指引修改
3) 视情况更新 references/ui.md

## 参考文件
- references/flow.md
- references/files.md
- references/ui.md
"""
        try? skillMD.data(using: .utf8)?.write(to: skillDir.appendingPathComponent("SKILL.md"), options: .atomic)

        let flow = """
# Flow
- 来源项目：\(cand.projectName)
- 候选摘要：\(cand.summary.isEmpty ? cand.title : cand.summary)
"""
        let files = """
# Files
- 待补充：关键文件路径与模块说明
"""
        let ui = """
# UI
- 待补充：相关页面与交互说明
"""
        try? flow.data(using: .utf8)?.write(to: refsDir.appendingPathComponent("flow.md"), options: .atomic)
        try? files.data(using: .utf8)?.write(to: refsDir.appendingPathComponent("files.md"), options: .atomic)
        try? ui.data(using: .utf8)?.write(to: refsDir.appendingPathComponent("ui.md"), options: .atomic)

        updateProjectSkillsIndex(projectDir: projectDir, skillName: skillName, summary: desc)
        updateGlobalSkillsIndex(skillsDir: skillsDir, projectDir: projectDir, projectName: cand.projectName)
        return skillName
    }

    static func updateProjectSkillsIndex(projectDir: URL, skillName: String, summary: String) {
        let indexURL = projectDir.appendingPathComponent("skills-index.md")
        // Use placeholders in indexes so they are portable when packaged/shared.
        let projectDirName = projectDir.lastPathComponent
        let entryPath = "<skills_dir>/_projects/\(projectDirName)/\(skillName)"
        let entry = "- \(skillName) — \(summary)（路径：\(entryPath)）"
        let existing = (try? String(contentsOf: indexURL, encoding: .utf8)) ?? ""
        let legacyAbs = projectDir.appendingPathComponent(skillName).path
        if existing.contains(legacyAbs) { return }
        if existing.contains("\n- \(skillName) —") || existing.hasPrefix("- \(skillName) —") { return }

        let header = "# Skills Index (project)\n\n"
        let out: String
        if existing.isEmpty {
            out = header + entry + "\n"
        } else if existing.contains("# Skills Index (project)") {
            out = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + entry + "\n"
        } else {
            // Keep existing content; append entry without forcing a new header to avoid polluting custom indexes.
            out = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + entry + "\n"
        }
        try? out.data(using: .utf8)?.write(to: indexURL, options: .atomic)
    }

    static func updateGlobalSkillsIndex(skillsDir: URL, projectDir: URL, projectName: String) {
        // Best-effort: keep a global pointer list under memory-core.
        let indexURL = skillsDir
            .appendingPathComponent("memory-core", isDirectory: true)
            .appendingPathComponent("references", isDirectory: true)
            .appendingPathComponent("skills-index.md")
        let projectDirName = projectDir.lastPathComponent
        let entryPath = "<skills_dir>/_projects/\(projectDirName)/skills-index.md"
        let entry = "- \(projectName) — 项目技能索引（路径：\(entryPath)）"
        let existing = (try? String(contentsOf: indexURL, encoding: .utf8)) ?? ""
        let legacyAbs = projectDir.appendingPathComponent("skills-index.md").path
        if existing.contains(legacyAbs) { return }
        if existing.contains("_projects/\(projectDirName)/skills-index.md") { return }

        let header = "# Skills Index (auto)\n\n"
        let projectSection = "## Projects (auto)\n"
        let out: String
        if existing.isEmpty {
            out = header + projectSection + entry + "\n"
        } else if existing.contains("# Skills Index (auto)") {
            if existing.contains("## Projects (auto)") {
                out = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + entry + "\n"
            } else {
                out = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + projectSection + entry + "\n"
            }
        } else {
            out = existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + header + projectSection + entry + "\n"
        }
        try? out.data(using: .utf8)?.write(to: indexURL, options: .atomic)
    }

    // MARK: - Helpers

    private static func slugify(_ s: String) -> String {
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
        return trimmed.isEmpty ? "skill-\(Int(Date().timeIntervalSince1970))" : trimmed
    }

    private static func normalizedModulePrefix(_ module: String?) -> String? {
        let m = (module ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["hub", "coder", "system", "shared"].contains(m) {
            return m + "-"
        }
        return nil
    }

    private static func inferModuleFromTitle(_ title: String) -> String? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("hub:") || t.hasPrefix("hub：") || t.hasPrefix("hub-") { return "hub" }
        if t.hasPrefix("coder:") || t.hasPrefix("coder：") || t.hasPrefix("coder-") { return "coder" }
        if t.hasPrefix("system:") || t.hasPrefix("system：") || t.hasPrefix("system-") { return "system" }
        if t.hasPrefix("shared:") || t.hasPrefix("shared：") || t.hasPrefix("shared-") { return "shared" }
        return nil
    }

    private static func stripLeadingModuleHint(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Accept both ASCII ':' and Chinese '：'.
        let prefixes = [
            "hub:", "hub：",
            "coder:", "coder：",
            "system:", "system：",
            "shared:", "shared：",
        ]
        for p in prefixes where lower.hasPrefix(p) {
            let idx = trimmed.index(trimmed.startIndex, offsetBy: p.count)
            return String(trimmed[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Also accept already-namespaced skill titles like "hub-foo".
        let dashPrefixes = ["hub-", "coder-", "system-", "shared-"]
        for p in dashPrefixes where lower.hasPrefix(p) {
            let idx = trimmed.index(trimmed.startIndex, offsetBy: p.count)
            return String(trimmed[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static func normalizeSkillNameComponent(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        // Avoid spaces in folder names; keeps grep-friendly skill names.
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        t = t.replacingOccurrences(of: " ", with: "-")
        while t.contains("--") { t = t.replacingOccurrences(of: "--", with: "-") }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return t
    }

    private static func applyModulePrefix(_ modulePrefix: String?, baseName: String) -> String {
        var base = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "skill-\(Int(Date().timeIntervalSince1970))" }
        guard let modulePrefix else { return base }

        let lower = base.lowercased()
        if lower.hasPrefix(modulePrefix) { return base }
        // If base already has a different module prefix, keep it as-is to avoid double-prefix.
        let known = ["hub-", "coder-", "system-", "shared-"]
        if known.contains(where: { lower.hasPrefix($0) }) { return base }
        return modulePrefix + base
    }

    private static func uniqueSkillName(_ base: String, in skillsDir: URL) -> String {
        var name = base
        var idx = 2
        while FileManager.default.fileExists(atPath: skillsDir.appendingPathComponent(name).path) {
            name = "\(base)-\(idx)"
            idx += 1
        }
        return name
    }

    private static func truncateInline(_ s: String, max: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= max { return t }
        let idx = t.index(t.startIndex, offsetBy: max)
        return String(t[..<idx])
    }

    private static func sanitizePathComponent(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        let forbidden = CharacterSet(charactersIn: "/\\:?*|\"<>")
        var out = ""
        for scalar in t.unicodeScalars {
            if forbidden.contains(scalar) {
                out.append("-")
            } else {
                out.append(Character(scalar))
            }
        }
        t = out
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : t
    }

    private static func findProjectDir(in root: URL, suffix: String) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for item in items where item.hasDirectoryPath {
            if item.lastPathComponent.hasSuffix("-\(suffix)") || item.lastPathComponent == "project-\(suffix)" {
                return item
            }
        }
        return nil
    }
}
