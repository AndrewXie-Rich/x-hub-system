import Foundation

enum XTAgentImportPreflightStatus: String, Codable, Sendable {
    case pending
    case passed
    case failed
    case quarantined
}

struct XTAgentSkillImportFinding: Codable, Equatable, Sendable {
    var code: String
    var detail: String
}

struct XTAgentSkillImportManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.agent_skill_import_manifest.v1"
    static let legacySchemaVersion = "xt.openclaw_skill_import_manifest.v1"

    var schemaVersion: String
    var source: String
    var sourceRef: String
    var skillId: String
    var displayName: String
    var kind: String
    var upstreamPackageRef: String
    var normalizedCapabilities: [String]
    var requiresGrant: Bool
    var riskLevel: String
    var policyScope: String
    var sandboxClass: String
    var promptMutationAllowed: Bool
    var installProvenance: String
    var preflightStatus: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case source
        case sourceRef = "source_ref"
        case skillId = "skill_id"
        case displayName = "display_name"
        case kind
        case upstreamPackageRef = "upstream_package_ref"
        case normalizedCapabilities = "normalized_capabilities"
        case requiresGrant = "requires_grant"
        case riskLevel = "risk_level"
        case policyScope = "policy_scope"
        case sandboxClass = "sandbox_class"
        case promptMutationAllowed = "prompt_mutation_allowed"
        case installProvenance = "install_provenance"
        case preflightStatus = "preflight_status"
    }
}

struct XTAgentSkillImportPreflightReport: Codable, Equatable, Sendable {
    var manifest: XTAgentSkillImportManifest
    var findings: [XTAgentSkillImportFinding]
}

struct XTAgentSkillScanInputFile: Codable, Equatable, Sendable {
    var path: String
    var content: String
}

struct XTAgentSkillScanInputPayload: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.agent_skill_scan_input.v1"
    static let legacySchemaVersion = "xt.openclaw_skill_scan_input.v1"

    var schemaVersion: String
    var files: [XTAgentSkillScanInputFile]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case files
    }
}

enum XTAgentDirectLocalExecutionDecision: String, Codable, Sendable {
    case allow
    case deny
}

struct XTAgentDirectLocalExecutionVerdict: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.agent_direct_local_execution_gate.v1"
    static let legacySchemaVersion = "xt.openclaw_direct_local_execution_gate.v1"

    var schemaVersion: String
    var skillId: String
    var decision: String
    var developerMode: Bool
    var reasonCode: String
    var detail: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case skillId = "skill_id"
        case decision
        case developerMode = "developer_mode"
        case reasonCode = "reason_code"
        case detail
    }
}

enum XTAgentSkillImportNormalizer {
    static func normalize(skillMarkdownURL: URL, repoRoot: URL) -> XTAgentSkillImportPreflightReport {
        let resolvedRepoRoot = repoRoot.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedSkillURL = skillMarkdownURL.standardizedFileURL.resolvingSymlinksInPath()
        let rawSkillURL = skillMarkdownURL.standardizedFileURL
        let skillDirectory = rawSkillURL.deletingLastPathComponent()
        let slug = normalizedSlug(skillDirectory.lastPathComponent)
        let fileText = (try? String(contentsOf: rawSkillURL, encoding: .utf8)) ?? ""
        let frontmatter = parseFrontmatter(fileText)
        let mapping = inferredMapping(slug: slug, frontmatter: frontmatter)

        var findings: [XTAgentSkillImportFinding] = []
        if !resolvedSkillURL.path.hasPrefix(resolvedRepoRoot.path + "/") && resolvedSkillURL != resolvedRepoRoot {
            findings.append(
                XTAgentSkillImportFinding(
                    code: "symlink_escape",
                    detail: "resolved skill path escapes declared repo root"
                )
            )
        }
        if worldWritable(url: rawSkillURL) || worldWritable(url: skillDirectory) {
            findings.append(
                XTAgentSkillImportFinding(
                    code: "world_writable_path",
                    detail: "skill file or containing directory is world-writable"
                )
            )
        }

        let bodyText = fileText.lowercased()
        if bodyText.contains("prompt mutation")
            || bodyText.contains("hook")
            || bodyText.contains("dangerously-skip-permissions")
            || bodyText.contains("--yolo") {
            findings.append(
                XTAgentSkillImportFinding(
                    code: "unsafe_upstream_behavior",
                    detail: "upstream skill references prompt mutation or unrestricted execution hints"
                )
            )
        }

        let sourceRef = relativePath(of: rawSkillURL, under: resolvedRepoRoot) ?? rawSkillURL.lastPathComponent
        let packageRefPath = relativePath(of: skillDirectory, under: resolvedRepoRoot) ?? skillDirectory.lastPathComponent
        let preflightStatus = resolvedPreflightStatus(findings: findings)

        let manifest = XTAgentSkillImportManifest(
            schemaVersion: XTAgentSkillImportManifest.currentSchemaVersion,
            source: "agent",
            sourceRef: sourceRef,
            skillId: mapping.skillId,
            displayName: firstNonEmpty(frontmatter["name"], skillDirectory.lastPathComponent),
            kind: "skill",
            upstreamPackageRef: "local://\(packageRefPath)",
            normalizedCapabilities: mapping.capabilities,
            requiresGrant: mapping.requiresGrant,
            riskLevel: mapping.riskLevel,
            policyScope: "project",
            sandboxClass: mapping.sandboxClass,
            promptMutationAllowed: false,
            installProvenance: "local_import",
            preflightStatus: preflightStatus.rawValue
        )
        return XTAgentSkillImportPreflightReport(
            manifest: manifest,
            findings: findings
        )
    }

    static func directLocalExecutionVerdict(
        report: XTAgentSkillImportPreflightReport,
        developerMode: Bool
    ) -> XTAgentDirectLocalExecutionVerdict {
        let resolvedStatus = normalizedPreflightStatus(report.manifest.preflightStatus)
        if resolvedStatus == .quarantined || resolvedStatus == .failed {
            return XTAgentDirectLocalExecutionVerdict(
                schemaVersion: XTAgentDirectLocalExecutionVerdict.currentSchemaVersion,
                skillId: report.manifest.skillId,
                decision: XTAgentDirectLocalExecutionDecision.deny.rawValue,
                developerMode: developerMode,
                reasonCode: "preflight_quarantined",
                detail: "direct local execution denied: preflight status=\(resolvedStatus.rawValue)"
            )
        }

        if report.manifest.requiresGrant || riskLevelRequiresHubGovernance(report.manifest.riskLevel) {
            return XTAgentDirectLocalExecutionVerdict(
                schemaVersion: XTAgentDirectLocalExecutionVerdict.currentSchemaVersion,
                skillId: report.manifest.skillId,
                decision: XTAgentDirectLocalExecutionDecision.deny.rawValue,
                developerMode: developerMode,
                reasonCode: "requires_hub_governance",
                detail: "direct local execution denied: risk=\(report.manifest.riskLevel) requires_grant=\(report.manifest.requiresGrant)"
            )
        }

        if !developerMode {
            return XTAgentDirectLocalExecutionVerdict(
                schemaVersion: XTAgentDirectLocalExecutionVerdict.currentSchemaVersion,
                skillId: report.manifest.skillId,
                decision: XTAgentDirectLocalExecutionDecision.deny.rawValue,
                developerMode: developerMode,
                reasonCode: "hub_stage_required",
                detail: "direct local execution denied outside developer_mode; stage via Hub skills_store instead"
            )
        }

        return XTAgentDirectLocalExecutionVerdict(
            schemaVersion: XTAgentDirectLocalExecutionVerdict.currentSchemaVersion,
            skillId: report.manifest.skillId,
            decision: XTAgentDirectLocalExecutionDecision.allow.rawValue,
            developerMode: developerMode,
            reasonCode: "developer_mode_low_risk_only",
            detail: "direct local execution allowed only for low/medium-risk developer-mode imports"
        )
    }

    static func buildScanInput(
        skillDirectoryURL: URL,
        maxFiles: Int = 500,
        maxBytes: Int = 2 * 1024 * 1024
    ) -> XTAgentSkillScanInputPayload {
        let root = skillDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        )

        var files: [XTAgentSkillScanInputFile] = []
        var totalBytes = 0
        while let next = enumerator?.nextObject() as? URL {
            let name = next.lastPathComponent
            if name.hasPrefix(".") && name.lowercased() != "skill.md" {
                enumerator?.skipDescendants()
                continue
            }
            if name == "node_modules" {
                enumerator?.skipDescendants()
                continue
            }
            let values = try? next.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                continue
            }
            guard scanInputEligible(url: next) else { continue }
            guard let relative = relativePath(of: next, under: root), relative != "." else { continue }
            guard let content = try? String(contentsOf: next, encoding: .utf8) else { continue }
            totalBytes += content.lengthOfBytes(using: .utf8)
            if totalBytes > maxBytes || files.count >= maxFiles {
                break
            }
            files.append(XTAgentSkillScanInputFile(path: relative, content: content))
        }

        files.sort { lhs, rhs in
            lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
        return XTAgentSkillScanInputPayload(
            schemaVersion: XTAgentSkillScanInputPayload.currentSchemaVersion,
            files: files
        )
    }

    private struct InferredMapping {
        var skillId: String
        var capabilities: [String]
        var riskLevel: String
        var requiresGrant: Bool
        var sandboxClass: String
    }

    private static func inferredMapping(slug: String, frontmatter: [String: String]) -> InferredMapping {
        let description = firstNonEmpty(frontmatter["description"]).lowercased()
        if slug == "coding-agent" || description.contains("delegate coding tasks") {
            return InferredMapping(
                skillId: "coder.run.command",
                capabilities: ["repo.exec.agent"],
                riskLevel: "medium",
                requiresGrant: false,
                sandboxClass: "governed_project_local"
            )
        }
        if slug.contains("browser") {
            return InferredMapping(
                skillId: "browser.runtime.smoke",
                capabilities: ["web.navigate"],
                riskLevel: "high",
                requiresGrant: true,
                sandboxClass: "governed_device_local"
            )
        }
        if slug.contains("email") || description.contains("email") {
            return InferredMapping(
                skillId: "connectors.email.send",
                capabilities: ["connectors.email.send"],
                riskLevel: "high",
                requiresGrant: true,
                sandboxClass: "hub_connector_governed"
            )
        }
        return InferredMapping(
            skillId: "agent.\(slug)",
            capabilities: [],
            riskLevel: "low",
            requiresGrant: false,
            sandboxClass: "governed_project_local"
        )
    }

    private static func resolvedPreflightStatus(
        findings: [XTAgentSkillImportFinding]
    ) -> XTAgentImportPreflightStatus {
        let criticalFindingCodes = Set(["symlink_escape", "world_writable_path", "unsafe_upstream_behavior"])
        if findings.contains(where: { criticalFindingCodes.contains($0.code) }) {
            return .quarantined
        }
        return findings.isEmpty ? .passed : .pending
    }

    private static func normalizedPreflightStatus(_ raw: String) -> XTAgentImportPreflightStatus {
        XTAgentImportPreflightStatus(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .pending
    }

    private static func riskLevelRequiresHubGovernance(_ raw: String) -> Bool {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high", "critical":
            return true
        default:
            return false
        }
    }

    private static func parseFrontmatter(_ text: String) -> [String: String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else { return [:] }
        let remainder = String(normalized.dropFirst(4))
        guard let closingRange = remainder.range(of: "\n---") else { return [:] }
        let block = String(remainder[..<closingRange.lowerBound])
        var values: [String: String] = [:]
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            guard let colon = raw.firstIndex(of: ":") else { continue }
            let key = raw[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            let value = raw[raw.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty {
                values[key] = value
            }
        }
        return values
    }

    private static func worldWritable(url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let rawPermissions = attributes[.posixPermissions] as? NSNumber else {
            return false
        }
        return (rawPermissions.intValue & 0o002) != 0
    }

    private static func relativePath(of url: URL, under root: URL) -> String? {
        let resolvedURL = url.standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard resolvedURL == resolvedRoot || resolvedURL.hasPrefix(resolvedRoot + "/") else {
            return nil
        }
        if resolvedURL == resolvedRoot {
            return "."
        }
        return String(resolvedURL.dropFirst(resolvedRoot.count + 1))
    }

    private static func normalizedSlug(_ raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mappedScalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(mappedScalars)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "skill" : collapsed
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private static func scanInputEligible(url: URL) -> Bool {
        let lower = url.lastPathComponent.lowercased()
        if lower == "skill.md" || lower == "package.json" || lower == "agent.plugin.json" || lower == "openclaw.plugin.json" {
            return true
        }
        switch url.pathExtension.lowercased() {
        case "js", "ts", "mjs", "cjs", "mts", "cts", "jsx", "tsx", "py", "sh", "bash", "zsh", "md", "json", "yaml", "yml":
            return true
        default:
            return false
        }
    }
}

typealias XTOpenClawImportPreflightStatus = XTAgentImportPreflightStatus
typealias XTOpenClawSkillImportFinding = XTAgentSkillImportFinding
typealias XTOpenClawSkillImportManifest = XTAgentSkillImportManifest
typealias XTOpenClawSkillImportPreflightReport = XTAgentSkillImportPreflightReport
typealias XTOpenClawSkillScanInputFile = XTAgentSkillScanInputFile
typealias XTOpenClawSkillScanInputPayload = XTAgentSkillScanInputPayload
typealias XTOpenClawDirectLocalExecutionDecision = XTAgentDirectLocalExecutionDecision
typealias XTOpenClawDirectLocalExecutionVerdict = XTAgentDirectLocalExecutionVerdict
typealias XTOpenClawSkillImportNormalizer = XTAgentSkillImportNormalizer
