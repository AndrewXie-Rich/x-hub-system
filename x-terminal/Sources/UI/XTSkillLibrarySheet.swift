import SwiftUI
import Foundation

struct XTSkillLibrarySheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            TextField("搜索 skill 名称、scope、摘要", text: $query)
                .textFieldStyle(.roundedBorder)

            if !appModel.lastImportedAgentSkillStatusLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(appModel.lastImportedAgentSkillStatusLine)
                    .font(UIThemeTokens.monoFont())
                    .foregroundStyle(appModel.agentSkillImportBusy ? .orange : .secondary)
                    .textSelection(.enabled)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    localSkillsSection

                    if !appModel.skillsCompatibilitySnapshot.governanceSurfaceEntries.isEmpty {
                        XTSkillGovernanceSurfaceView(
                            items: filteredGovernanceEntries,
                            title: "当前 governed skills 真相"
                        )
                    }

                    if !appModel.skillsCompatibilitySnapshot.builtinGovernedSkills.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("XT 内建 skills 只读")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text("XT builtin governed skills 不应在这里直接改包体；如果要改行为，应改 XT 源码或 fork 成本地 skill。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            XTBuiltinGovernedSkillsListView(
                                items: filteredBuiltinSkills
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(minWidth: 760, idealWidth: 860, maxWidth: 940, minHeight: 520, idealHeight: 700)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Skill Library")
                    .font(.title3.weight(.semibold))

                Text("先看当前有哪些 skill 可编辑、哪些 governed skill 已经可 discover / install / request / run，再决定下一步。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button("Open Existing Skill…") {
                    appModel.openSkillEditor()
                }

                Button("Import Skills or Packages…") {
                    appModel.importSkills()
                }

                Button("Review Import") {
                    appModel.reviewLastImportedSkill()
                }
                .disabled(!appModel.canReviewLastImportedAgentSkill)

                Button("Enable Import") {
                    appModel.enableLastImportedSkill()
                }
                .disabled(!appModel.canEnableLastImportedAgentSkill)

                Button("Open Index") {
                    appModel.openCurrentSkillsIndex()
                }

                Button("Close") {
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var localSkillsSection: some View {
        let sections = filteredLocalSections
        VStack(alignment: .leading, spacing: 10) {
            Text("本地可编辑 skills")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("这里列的是本地 skill 源文件。除了直接编辑 `SKILL.md` / `skill.json`，现在也能在这里直接补 manifest、duplicate、remove，并把当前 manifest / governed compatibility 问题拉出来看明细。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if sections.isEmpty {
                Text("当前没有扫到可编辑的本地 skill。可以先点上面的 `Import Skills or Packages…`，或者用 `Open Existing Skill…` 直接打开一个现有 skill。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            Text("\(section.entries.count)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        ForEach(section.entries) { entry in
                            localSkillRow(entry)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func localSkillRow(_ entry: LocalSkillEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.caption.weight(.semibold))
                    Text(entry.scopeSummary)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Button("Edit SKILL.md") {
                            appModel.openWorkspaceURL(entry.skillMarkdownURL)
                        }
                        .buttonStyle(.borderless)
    
                        if let manifestURL = entry.manifestURL {
                            Button("Edit skill.json") {
                                appModel.openWorkspaceURL(manifestURL)
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Button("Create skill.json") {
                                appModel.createLocalSkillManifest(at: entry.folderURL)
                            }
                            .buttonStyle(.borderless)
                        }

                        Button("Open Folder") {
                            appModel.openWorkspaceURL(entry.folderURL)
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack(spacing: 8) {
                        Button("Rename Folder") {
                            appModel.renameLocalSkill(at: entry.folderURL)
                        }
                        .buttonStyle(.borderless)

                        Button("Duplicate") {
                            appModel.duplicateLocalSkill(at: entry.folderURL)
                        }
                        .buttonStyle(.borderless)

                        Button("Reveal Issues") {
                            appModel.presentSkillLibraryAlert(
                                title: "Skill Report · \(entry.displayName)",
                                message: entry.issueReport
                            )
                        }
                        .buttonStyle(.borderless)

                        Button("Remove") {
                            appModel.removeLocalSkill(at: entry.folderURL)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }
            }

            if !entry.summary.isEmpty {
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(entry.packageSummary)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

            if !entry.governedSummary.isEmpty {
                Text(entry.governedSummary)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(entry.issueSummary)
                .font(.caption2.monospaced())
                .foregroundStyle(entry.issueSeverity.tint)

            Text(entry.folderURL.path)
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var filteredLocalSections: [LocalSkillSection] {
        localSkillSections
            .map { section in
                LocalSkillSection(
                    id: section.id,
                    title: section.title,
                    entries: section.entries.filter(matchesQuery(_:))
                )
            }
            .filter { !$0.entries.isEmpty }
    }

    private var localSkillSections: [LocalSkillSection] {
        guard let skillsDir = AXSkillsLibrary.resolveSkillsDirectory() else { return [] }

        var sections: [LocalSkillSection] = []
        let rootEntries = loadRootImportedSkills(skillsDir: skillsDir)
        if !rootEntries.isEmpty {
            sections.append(
                LocalSkillSection(
                    id: "imported",
                    title: "Imported / Staging",
                    entries: rootEntries
                )
            )
        }

        let globalEntries = loadNestedSkillEntries(
            root: skillsDir.appendingPathComponent("_global", isDirectory: true),
            scopeLabel: "global"
        )
        if !globalEntries.isEmpty {
            sections.append(
                LocalSkillSection(
                    id: "global",
                    title: "Global",
                    entries: globalEntries
                )
            )
        }

        if let projectSection = currentProjectSkillSection(skillsDir: skillsDir) {
            sections.insert(projectSection, at: 0)
        }

        return sections
    }

    private func currentProjectSkillSection(skillsDir: URL) -> LocalSkillSection? {
        guard let projectId = appModel.selectedProjectId,
              projectId != AXProjectRegistry.globalHomeId else { return nil }
        let projectName = appModel.registry.projects.first(where: { $0.projectId == projectId })?.displayName
        guard let projectRoot = existingProjectSkillsDir(
            projectId: projectId,
            projectName: projectName,
            skillsDir: skillsDir
        ) else {
            return nil
        }

        let entries = loadNestedSkillEntries(root: projectRoot, scopeLabel: "project")
        guard !entries.isEmpty else { return nil }
        let trimmedProjectName = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = trimmedProjectName.isEmpty
            ? "Current Project"
            : "Current Project · \(trimmedProjectName)"
        return LocalSkillSection(id: "project", title: title, entries: entries)
    }

    private func loadRootImportedSkills(skillsDir: URL) -> [LocalSkillEntry] {
        let reserved: Set<String> = [
            "_projects",
            "_global",
            "memory-core",
            ".xterminal",
        ]
        let items = (try? FileManager.default.contentsOfDirectory(
            at: skillsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return items
            .filter { $0.hasDirectoryPath }
            .filter { !reserved.contains($0.lastPathComponent) }
            .compactMap { makeLocalSkillEntry(folderURL: $0, scopeLabel: "imported") }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func loadNestedSkillEntries(root: URL, scopeLabel: String) -> [LocalSkillEntry] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return items
            .filter { $0.hasDirectoryPath }
            .compactMap { makeLocalSkillEntry(folderURL: $0, scopeLabel: scopeLabel) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func makeLocalSkillEntry(folderURL: URL, scopeLabel: String) -> LocalSkillEntry? {
        let skillMarkdownURL = folderURL.appendingPathComponent("SKILL.md")
        guard FileManager.default.fileExists(atPath: skillMarkdownURL.path) else { return nil }
        let manifestURL = folderURL.appendingPathComponent("skill.json")
        let skillText = (try? String(contentsOf: skillMarkdownURL, encoding: .utf8)) ?? ""
        let frontmatter = parseFrontmatter(skillText)
        let manifestSnapshot = loadManifestSnapshot(
            manifestURL: FileManager.default.fileExists(atPath: manifestURL.path) ? manifestURL : nil
        )
        let resolvedDisplayName = firstNonEmpty(
            manifestSnapshot.displayName,
            frontmatter["name"],
            folderURL.lastPathComponent
        ) ?? folderURL.lastPathComponent
        let resolvedSkillID = firstNonEmpty(
            manifestSnapshot.skillID,
            frontmatter["skill_id"],
            folderURL.lastPathComponent
        ) ?? folderURL.lastPathComponent
        let resolvedVersion = firstNonEmpty(manifestSnapshot.version, frontmatter["version"]) ?? ""
        let issueAssessment = assessLocalSkillIssues(
            folderURL: folderURL,
            scopeLabel: scopeLabel,
            skillID: resolvedSkillID,
            displayName: resolvedDisplayName,
            version: resolvedVersion,
            hasManifest: FileManager.default.fileExists(atPath: manifestURL.path),
            manifestParseError: manifestSnapshot.parseError
        )
        return LocalSkillEntry(
            folderURL: folderURL,
            skillMarkdownURL: skillMarkdownURL,
            manifestURL: FileManager.default.fileExists(atPath: manifestURL.path) ? manifestURL : nil,
            displayName: resolvedDisplayName,
            scopeLabel: scopeLabel,
            skillID: resolvedSkillID,
            version: resolvedVersion,
            summary: extractSkillSummary(skillMarkdownURL: skillMarkdownURL),
            governedSummary: issueAssessment.governedSummary,
            issueSummary: issueAssessment.issueSummary,
            issueReport: issueAssessment.report,
            issueSeverity: issueAssessment.severity
        )
    }

    private func extractSkillSummary(skillMarkdownURL: URL) -> String {
        guard let text = try? String(contentsOf: skillMarkdownURL, encoding: .utf8) else {
            return ""
        }
        var inFrontMatter = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            if raw.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                inFrontMatter.toggle()
                continue
            }
            if inFrontMatter,
               raw.lowercased().hasPrefix("description:") {
                return raw
                    .dropFirst("description:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !inFrontMatter {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("# ") {
                    return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return ""
    }

    private func parseFrontmatter(_ text: String) -> [String: String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else { return [:] }
        let remainder = String(normalized.dropFirst(4))
        guard let closingRange = remainder.range(of: "\n---\n") else { return [:] }
        let block = remainder[..<closingRange.lowerBound]
        var out: [String: String] = [:]
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            guard let separator = raw.firstIndex(of: ":") else { continue }
            let key = raw[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = raw[raw.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            out[key] = value
        }
        return out
    }

    private func loadManifestSnapshot(manifestURL: URL?) -> LocalSkillManifestSnapshot {
        guard let manifestURL else { return .init() }
        do {
            let data = try Data(contentsOf: manifestURL)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return LocalSkillManifestSnapshot(parseError: "skill.json is not a JSON object.")
            }
            return LocalSkillManifestSnapshot(
                skillID: stringValue(root["skill_id"]) ?? stringValue(root["id"]) ?? "",
                displayName: stringValue(root["display_name"]) ?? stringValue(root["name"]) ?? "",
                version: stringValue(root["version"]) ?? "",
                parseError: nil
            )
        } catch {
            return LocalSkillManifestSnapshot(parseError: error.localizedDescription)
        }
    }

    private func assessLocalSkillIssues(
        folderURL: URL,
        scopeLabel: String,
        skillID: String,
        displayName: String,
        version: String,
        hasManifest: Bool,
        manifestParseError: String?
    ) -> LocalSkillIssueAssessment {
        let canonicalSkillID = AXSkillsLibrary.canonicalSupervisorSkillID(skillID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let match = appModel.skillsCompatibilitySnapshot.installedSkills.first { item in
            AXSkillsLibrary.canonicalSupervisorSkillID(item.skillID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == canonicalSkillID
        }

        var issues: [String] = []
        var governedSummary = ""

        if !hasManifest {
            issues.append("Missing skill.json; package manifest / ABI metadata is not available for local editing.")
        }

        if let manifestParseError = trimmedNonEmpty(manifestParseError) {
            issues.append("skill.json parse failed: \(manifestParseError)")
        }

        if hasManifest && canonicalSkillID.isEmpty {
            issues.append("skill.json is missing skill_id.")
        }

        let matchingWarnings = appModel.skillsCompatibilitySnapshot.conflictWarnings.filter { warning in
            warningMatchesLocalSkill(
                warning,
                canonicalSkillID: canonicalSkillID,
                folderName: folderURL.lastPathComponent
            )
        }
        issues.append(contentsOf: matchingWarnings.prefix(3))

        if let match {
            let state = match.revoked ? "revoked" : match.compatibilityState.rawValue
            let publisher = trimmedNonEmpty(match.publisherID) ?? "unknown"
            let risk = trimmedNonEmpty(match.riskLevel) ?? "unknown"
            let abi = trimmedNonEmpty(match.abiCompatVersion) ?? "missing"
            governedSummary = "governed=\(state) · publisher=\(publisher) · risk=\(risk) · abi=\(abi)"

            if match.revoked {
                issues.append("Current governed snapshot marks this skill revoked.")
            } else if match.compatibilityState == .unsupported {
                issues.append("Current governed snapshot marks this skill unsupported on this XT / Hub runtime.")
            } else if match.compatibilityState == .partial {
                issues.append("Current governed snapshot marks this skill partially compatible.")
            }

            if trimmedNonEmpty(match.installHint) != nil,
               match.compatibilityState != .supported || match.revoked {
                issues.append("Install hint: \(match.installHint)")
            }
        } else if scopeLabel == "imported" {
            governedSummary = "governed=not enabled yet"
            issues.append("Imported locally, but not enabled into the current governed registry yet.")
        } else {
            governedSummary = "governed=not linked in current snapshot"
        }

        let severity: LocalSkillIssueSeverity
        if issues.contains(where: { issue in
            let normalized = issue.lowercased()
            return normalized.contains("parse failed")
                || normalized.contains("revoked")
                || normalized.contains("unsupported")
        }) {
            severity = .blocked
        } else if issues.isEmpty {
            severity = .none
        } else {
            severity = .warning
        }

        let issueSummary: String
        if issues.isEmpty {
            issueSummary = "issues: none detected"
        } else {
            let level = severity == .blocked ? "blocker" : "warning"
            issueSummary = "issues: \(issues.count) \(level)\(issues.count == 1 ? "" : "s")"
        }

        var reportLines: [String] = [
            "display_name: \(displayName)",
            "skill_id: \(trimmedNonEmpty(skillID) ?? folderURL.lastPathComponent)",
            "scope: \(scopeLabel)",
            "package: \(hasManifest ? "SKILL.md + skill.json" : "SKILL.md only")",
            "folder: \(folderURL.path)"
        ]
        if let version = trimmedNonEmpty(version) {
            reportLines.append("version: \(version)")
        }
        if !governedSummary.isEmpty {
            reportLines.append(governedSummary)
        }
        reportLines.append("")
        if issues.isEmpty {
            reportLines.append("No blocking manifest / compatibility issues detected in the current snapshot.")
        } else {
            reportLines.append("issues (\(issues.count)):")
            reportLines.append(contentsOf: issues.map { "- \($0)" })
        }

        return LocalSkillIssueAssessment(
            governedSummary: governedSummary,
            issueSummary: issueSummary,
            report: reportLines.joined(separator: "\n"),
            severity: severity
        )
    }

    private func warningMatchesLocalSkill(
        _ warning: String,
        canonicalSkillID: String,
        folderName: String
    ) -> Bool {
        let normalized = warning.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let canonicalFolder = AXSkillsLibrary.canonicalSupervisorSkillID(folderName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return (!canonicalSkillID.isEmpty && normalized.contains(canonicalSkillID))
            || (!canonicalFolder.isEmpty && normalized.contains(canonicalFolder))
            || normalized.contains(folderName.lowercased())
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value = trimmedNonEmpty(value) {
                return value
            }
        }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private func existingProjectSkillsDir(
        projectId: String,
        projectName: String?,
        skillsDir: URL
    ) -> URL? {
        let root = skillsDir.appendingPathComponent("_projects", isDirectory: true)
        let suffix = String(projectId.prefix(8))
        let items = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        if let existing = items.first(where: {
            $0.hasDirectoryPath &&
            ($0.lastPathComponent.hasSuffix("-\(suffix)") || $0.lastPathComponent == "project-\(suffix)")
        }) {
            return existing
        }

        guard let projectName else { return nil }
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let forbidden = CharacterSet(charactersIn: "/\\:?*|\"<>")
        var safeName = ""
        for scalar in trimmedName.unicodeScalars {
            if forbidden.contains(scalar) {
                safeName.append("-")
            } else {
                safeName.append(Character(scalar))
            }
        }
        safeName = safeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeName.isEmpty else { return nil }
        let fallback = root.appendingPathComponent("\(safeName)-\(suffix)", isDirectory: true)
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    private func matchesQuery(_ entry: LocalSkillEntry) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return entry.displayName.lowercased().contains(needle)
            || entry.scopeLabel.lowercased().contains(needle)
            || entry.summary.lowercased().contains(needle)
            || entry.folderURL.path.lowercased().contains(needle)
    }

    private var filteredBuiltinSkills: [AXBuiltinGovernedSkillSummary] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return appModel.skillsCompatibilitySnapshot.builtinGovernedSkills }
        return appModel.skillsCompatibilitySnapshot.builtinGovernedSkills.filter { item in
            item.skillID.lowercased().contains(needle)
                || item.displayName.lowercased().contains(needle)
                || item.summary.lowercased().contains(needle)
        }
    }

    private var filteredGovernanceEntries: [AXSkillGovernanceSurfaceEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return appModel.skillsCompatibilitySnapshot.governanceSurfaceEntries }
        return appModel.skillsCompatibilitySnapshot.governanceSurfaceEntries.filter { item in
            item.skillID.lowercased().contains(needle)
                || item.name.lowercased().contains(needle)
                || item.note.lowercased().contains(needle)
                || item.whyNotRunnable.lowercased().contains(needle)
                || item.installHint.lowercased().contains(needle)
        }
    }
}

private struct LocalSkillSection: Identifiable {
    var id: String
    var title: String
    var entries: [LocalSkillEntry]
}

private struct LocalSkillEntry: Identifiable {
    var folderURL: URL
    var skillMarkdownURL: URL
    var manifestURL: URL?
    var displayName: String
    var scopeLabel: String
    var skillID: String
    var version: String
    var summary: String
    var governedSummary: String
    var issueSummary: String
    var issueReport: String
    var issueSeverity: LocalSkillIssueSeverity

    var id: String { folderURL.path }

    var scopeSummary: String {
        let normalizedSkillID = skillID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSkillID.isEmpty else { return scopeLabel }
        return "\(scopeLabel) · \(normalizedSkillID)"
    }

    var packageSummary: String {
        var parts = [manifestURL == nil ? "package=SKILL.md only" : "package=SKILL.md + skill.json"]
        let normalizedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedVersion.isEmpty {
            parts.append("version=\(normalizedVersion)")
        }
        return parts.joined(separator: " · ")
    }
}

private struct LocalSkillManifestSnapshot {
    var skillID: String = ""
    var displayName: String = ""
    var version: String = ""
    var parseError: String? = nil
}

private struct LocalSkillIssueAssessment {
    var governedSummary: String
    var issueSummary: String
    var report: String
    var severity: LocalSkillIssueSeverity
}

private enum LocalSkillIssueSeverity {
    case none
    case warning
    case blocked

    var tint: Color {
        switch self {
        case .none:
            return .secondary
        case .warning:
            return .orange
        case .blocked:
            return .red
        }
    }
}
