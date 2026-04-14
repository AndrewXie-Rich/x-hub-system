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
    var intentFamilies: [String]
    var capabilityProfileHints: [String]
    var approvalFloorHint: String
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
        case intentFamilies = "intent_families"
        case capabilityProfileHints = "capability_profile_hints"
        case approvalFloorHint = "approval_floor_hint"
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

enum XTAgentSkillImportReviewFormatter {
    static func formatHubRecordReview(
        recordJSON: String?,
        fallbackStagingId: String,
        fallbackSkillId: String
    ) -> String {
        let raw = (recordJSON ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return "staging_id: \(fallbackStagingId)\nskill_id: \(fallbackSkillId)\n\nHub did not return structured review JSON."
        }

        let manifest = root["import_manifest"] as? [String: Any]
        let findings = root["findings"] as? [[String: Any]] ?? []

        var lines: [String] = []
        appendLine(into: &lines, label: "staging_id", value: stringValue(root["staging_id"]) ?? fallbackStagingId)
        appendLine(into: &lines, label: "status", value: stringValue(root["status"]))
        appendLine(into: &lines, label: "audit_ref", value: stringValue(root["audit_ref"]))
        appendLine(into: &lines, label: "requested_by", value: stringValue(root["requested_by"]))
        appendLine(into: &lines, label: "note", value: stringValue(root["note"]))
        appendLine(into: &lines, label: "skill_id", value: stringValue(manifest?["skill_id"]) ?? fallbackSkillId)
        appendLine(into: &lines, label: "display_name", value: stringValue(manifest?["display_name"]))
        appendLine(into: &lines, label: "preflight", value: stringValue(manifest?["preflight_status"]))
        appendLine(into: &lines, label: "vetter", value: stringValue(root["vetter_status"]))
        appendCountLine(
            into: &lines,
            label: "vetter_counts",
            critical: intValue(root["vetter_critical_count"]),
            warning: intValue(root["vetter_warn_count"])
        )
        appendLine(into: &lines, label: "vetter_audit_ref", value: stringValue(root["vetter_audit_ref"]))
        appendLine(into: &lines, label: "vetter_report_ref", value: stringValue(root["vetter_report_ref"]))
        appendLine(into: &lines, label: "risk", value: stringValue(manifest?["risk_level"]))
        appendLine(into: &lines, label: "scope", value: stringValue(manifest?["policy_scope"]))
        appendLine(into: &lines, label: "requires_grant", value: boolStringValue(manifest?["requires_grant"]))
        appendLine(into: &lines, label: "blocked_reason", value: stringValue(root["promotion_blocked_reason"]))
        appendLine(into: &lines, label: "enabled_package", value: shortSHA(stringValue(root["enabled_package_sha256"])))
        appendLine(into: &lines, label: "enabled_scope", value: stringValue(root["enabled_scope"]))

        let trustRoot = importTrustRoot(root: root)
        let pinnedVersion = importPinnedVersion(root: root)
        let runnerRequirement = importRunnerRequirement(manifest: manifest)
        let compatibilityStatus = importCompatibilityStatus(root: root, manifest: manifest)
        let preflightResult = importPreflightResult(root: root, manifest: manifest)
        let intentFamilies = stringArrayValue(manifest?["intent_families"])
        let capabilityProfileHints = stringArrayValue(manifest?["capability_profile_hints"])
        let approvalFloorHint = nonEmptyString(stringValue(manifest?["approval_floor_hint"]))
        let canonicalDerivation = root["canonical_capability_derivation"] as? [String: Any]
        let hintValidation = root["capability_hint_validation"] as? [String: Any]

        lines.append("")
        lines.append("governance:")
        lines.append("- trust_root: \(trustRoot)")
        lines.append("- pinned_version: \(pinnedVersion)")
        lines.append("- runner_requirement: \(runnerRequirement)")
        lines.append("- compatibility_status: \(compatibilityStatus)")
        lines.append("- preflight_result: \(preflightResult)")
        if !intentFamilies.isEmpty {
            lines.append("- intent_families: \(intentFamilies.joined(separator: ", "))")
        }
        if !capabilityProfileHints.isEmpty {
            lines.append("- capability_profile_hints: \(capabilityProfileHints.joined(separator: ", "))")
        }
        if let approvalFloorHint {
            lines.append("- approval_floor_hint: \(approvalFloorHint)")
        }
        if let canonicalDerivation {
            let canonicalIntents = stringArrayValue(canonicalDerivation["intent_families"])
            let canonicalProfiles = stringArrayValue(canonicalDerivation["capability_profiles"])
            let canonicalApprovalFloor = nonEmptyString(stringValue(canonicalDerivation["approval_floor"]))
            if !canonicalIntents.isEmpty {
                lines.append("- canonical_intent_families: \(canonicalIntents.joined(separator: ", "))")
            }
            if !canonicalProfiles.isEmpty {
                lines.append("- canonical_capability_profiles: \(canonicalProfiles.joined(separator: ", "))")
            }
            if let canonicalApprovalFloor {
                lines.append("- canonical_approval_floor: \(canonicalApprovalFloor)")
            }
        }
        if let hintValidation {
            let checked = boolStringValue(hintValidation["checked"]) ?? "false"
            let failClosed = boolStringValue(hintValidation["fail_closed"]) ?? "false"
            let mismatches = (hintValidation["mismatches"] as? [[String: Any]] ?? [])
                .compactMap { nonEmptyString(stringValue($0["field"])) }
            lines.append("- hint_validation: checked=\(checked) fail_closed=\(failClosed) mismatches=\(mismatches.count)")
            if !mismatches.isEmpty {
                lines.append("- hint_mismatches: \(mismatches.joined(separator: ", "))")
            }
        }

        let capabilities = stringArrayValue(manifest?["normalized_capabilities"])
        if !capabilities.isEmpty {
            lines.append("capabilities: \(capabilities.joined(separator: ", "))")
        }

        if !findings.isEmpty {
            lines.append("")
            lines.append("findings (\(findings.count)):")
            for finding in findings.prefix(6) {
                let code = stringValue(finding["code"]) ?? "finding"
                let detail = stringValue(finding["detail"]) ?? stringValue(finding["reason"]) ?? ""
                lines.append("- \(code): \(detail)")
            }
        }

        if lines.isEmpty {
            return raw
        }
        return lines.joined(separator: "\n")
    }

    private static func appendLine(into lines: inout [String], label: String, value: String?) {
        let normalized = nonEmptyString(value)
        guard let normalized else { return }
        lines.append("\(label): \(normalized)")
    }

    private static func appendCountLine(
        into lines: inout [String],
        label: String,
        critical: Int?,
        warning: Int?
    ) {
        guard critical != nil || warning != nil else { return }
        let criticalCount = max(0, critical ?? 0)
        let warnCount = max(0, warning ?? 0)
        lines.append("\(label): critical=\(criticalCount) warn=\(warnCount)")
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func boolStringValue(_ value: Any?) -> String? {
        switch value {
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return number.boolValue ? "true" : "false"
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func stringArrayValue(_ value: Any?) -> [String] {
        guard let raw = value as? [Any] else { return [] }
        return raw.compactMap { item in
            nonEmptyString(stringValue(item))
        }
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func importTrustRoot(root: [String: Any]) -> String {
        if let enabledPackage = nonEmptyString(stringValue(root["enabled_package_sha256"])) {
            return "governed package promoted @\(String(enabledPackage.prefix(12)))"
        }
        return "pending Hub promotion"
    }

    private static func importPinnedVersion(root: [String: Any]) -> String {
        let enabledScope = nonEmptyString(stringValue(root["enabled_scope"])) ?? ""
        let enabledPackage = nonEmptyString(stringValue(root["enabled_package_sha256"])) ?? ""
        guard !enabledScope.isEmpty, !enabledPackage.isEmpty else {
            return "not pinned yet"
        }
        return "@\(String(enabledPackage.prefix(12))) scope=\(enabledScope)"
    }

    private static func importRunnerRequirement(manifest: [String: Any]?) -> String {
        let sandbox = nonEmptyString(stringValue(manifest?["sandbox_class"])) ?? ""
        if !sandbox.isEmpty {
            return "Hub-governed import runner | sandbox=\(sandbox)"
        }
        return "Hub-governed import runner"
    }

    private static func importCompatibilityStatus(
        root: [String: Any],
        manifest: [String: Any]?
    ) -> String {
        let preflight = nonEmptyString(stringValue(manifest?["preflight_status"])) ?? "unknown"
        let vetter = nonEmptyString(stringValue(root["vetter_status"])) ?? "pending"
        if preflight == "quarantined" || vetter == "critical" {
            return "quarantined | vetter=\(vetter)"
        }
        if vetter == "passed" {
            return "compatible for governed packaging"
        }
        return "pending verify | preflight=\(preflight) vetter=\(vetter)"
    }

    private static func importPreflightResult(
        root: [String: Any],
        manifest: [String: Any]?
    ) -> String {
        let preflight = nonEmptyString(stringValue(manifest?["preflight_status"])) ?? "unknown"
        let blockedReason = nonEmptyString(stringValue(root["promotion_blocked_reason"])) ?? ""
        let requiresGrant = boolStringValue(manifest?["requires_grant"]) == "true"

        if preflight == "quarantined" {
            return blockedReason.isEmpty ? "quarantined" : "quarantined | \(blockedReason)"
        }
        if requiresGrant {
            return blockedReason.isEmpty ? "grant required before enable" : "grant required before enable | \(blockedReason)"
        }
        if blockedReason.isEmpty {
            return preflight
        }
        return "\(preflight) | \(blockedReason)"
    }

    private static func shortSHA(_ value: String?) -> String? {
        let normalized = nonEmptyString(value)
        guard let normalized else { return nil }
        return String(normalized.prefix(12))
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
        let companionManifest = loadCompanionManifestMetadata(skillDirectory: skillDirectory)
        let mapping = inferredMapping(
            slug: slug,
            frontmatter: frontmatter,
            companionManifest: companionManifest
        )

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
        let intentFamilies = canonicalIntentFamilies(
            skillId: mapping.skillId,
            normalizedCapabilities: mapping.capabilities
        )
        let capabilityFamilies = canonicalCapabilityFamilies(
            intentFamilies: intentFamilies,
            normalizedCapabilities: mapping.capabilities
        )
        let capabilityProfileHints = XTSkillCapabilityProfileSupport.capabilityProfiles(
            for: capabilityFamilies
        )
        let approvalFloorHint = XTSkillCapabilityProfileSupport.approvalFloor(
            for: capabilityFamilies
        )

        let manifest = XTAgentSkillImportManifest(
            schemaVersion: XTAgentSkillImportManifest.currentSchemaVersion,
            source: "agent",
            sourceRef: sourceRef,
            skillId: mapping.skillId,
            displayName: firstNonEmpty(
                companionManifest?.displayName,
                frontmatter["name"],
                skillDirectory.lastPathComponent
            ),
            kind: "skill",
            upstreamPackageRef: "local://\(packageRefPath)",
            normalizedCapabilities: mapping.capabilities,
            intentFamilies: intentFamilies,
            capabilityProfileHints: capabilityProfileHints,
            approvalFloorHint: approvalFloorHint,
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

    private struct CompanionSkillManifestMetadata {
        var skillId: String
        var displayName: String
        var description: String
        var capabilities: [String]
        var riskLevel: String
        var requiresGrant: Bool?
    }

    private static func inferredMapping(
        slug: String,
        frontmatter: [String: String],
        companionManifest: CompanionSkillManifestMetadata?
    ) -> InferredMapping {
        let frontmatterCapabilities = stringArrayValue(
            frontmatter["capabilities_required"]
                ?? frontmatter["required_capabilities"]
                ?? frontmatter["capabilities"]
        )
        let description = firstNonEmpty(
            companionManifest?.description,
            frontmatter["description"]
        ).lowercased()
        let explicitSkillId = firstNonEmpty(
            companionManifest?.skillId,
            frontmatter["skill_id"],
            frontmatter["id"]
        )

        let companionCapabilities = companionManifest?.capabilities ?? []
        if !companionCapabilities.isEmpty || !explicitSkillId.isEmpty {
            let capabilities = companionCapabilities.isEmpty ? frontmatterCapabilities : companionCapabilities
            let riskLevel = firstNonEmpty(
                normalizedRiskLevel(companionManifest?.riskLevel),
                normalizedRiskLevel(frontmatter["risk_level"]),
                inferRiskLevel(capabilities: capabilities)
            )
            let requiresGrant = companionManifest?.requiresGrant
                ?? parseBool(frontmatter["requires_grant"])
                ?? inferRequiresGrant(capabilities: capabilities, riskLevel: riskLevel)
            let resolvedSkillId = firstNonEmpty(explicitSkillId, "agent.\(slug)")
            return InferredMapping(
                skillId: resolvedSkillId,
                capabilities: capabilities,
                riskLevel: riskLevel,
                requiresGrant: requiresGrant,
                sandboxClass: inferSandboxClass(
                    capabilities: capabilities,
                    skillId: resolvedSkillId,
                    description: description
                )
            )
        }

        if !frontmatterCapabilities.isEmpty {
            let resolvedSkillId = firstNonEmpty(explicitSkillId, "agent.\(slug)")
            let riskLevel = firstNonEmpty(
                normalizedRiskLevel(frontmatter["risk_level"]),
                inferRiskLevel(capabilities: frontmatterCapabilities)
            )
            return InferredMapping(
                skillId: resolvedSkillId,
                capabilities: frontmatterCapabilities,
                riskLevel: riskLevel,
                requiresGrant: parseBool(frontmatter["requires_grant"])
                    ?? inferRequiresGrant(capabilities: frontmatterCapabilities, riskLevel: riskLevel),
                sandboxClass: inferSandboxClass(
                    capabilities: frontmatterCapabilities,
                    skillId: resolvedSkillId,
                    description: description
                )
            )
        }

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

    static func canonicalIntentFamilies(
        skillId: String,
        normalizedCapabilities: [String]
    ) -> [String] {
        var intents: [String] = []
        let normalizedSkillId = AXSkillsLibrary.canonicalSupervisorSkillID(skillId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalizedSkillId {
        case "coder.run.command":
            intents.append("repo.verify")
        case "agent-browser":
            intents.append(contentsOf: ["browser.observe", "browser.interact", "browser.secret_fill", "web.fetch_live"])
        default:
            break
        }

        for rawCapability in normalizedCapabilities {
            let capability = rawCapability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !capability.isEmpty else { continue }

            if capability.hasPrefix("skills.search") || capability.hasPrefix("skills.discover") {
                intents.append("skills.discover")
            }
            if capability.hasPrefix("skills.pin")
                || capability.hasPrefix("skills.manage")
                || capability.hasPrefix("skills.install")
                || capability.hasPrefix("skills.enable")
                || capability.hasPrefix("skills.import") {
                intents.append("skills.manage")
            }
            if capability.hasPrefix("repo.read")
                || capability.hasPrefix("filesystem.read")
                || capability.hasPrefix("fs.read")
                || capability == "document.read"
                || capability == "git.status"
                || capability == "git.diff"
                || capability == "project.snapshot" {
                intents.append("repo.read")
            }
            if capability.hasPrefix("repo.write")
                || capability.hasPrefix("repo.mutate")
                || capability.hasPrefix("repo.modify")
                || capability.hasPrefix("repo.delete")
                || capability.hasPrefix("repo.move")
                || capability == "git.apply"
                || capability == "git.commit" {
                intents.append("repo.modify")
            }
            if capability.hasPrefix("repo.verify")
                || capability.hasPrefix("repo.test")
                || capability.hasPrefix("repo.build")
                || capability == "run_command"
                || capability == "repo.exec.agent"
                || capability.hasPrefix("process.") {
                intents.append("repo.verify")
            }
            if capability.hasPrefix("repo.delivery")
                || capability == "git.push"
                || capability == "pr.create"
                || capability == "ci.trigger" {
                intents.append("repo.deliver")
            }
            if capability.hasPrefix("web.search") {
                intents.append("web.search_live")
            }
            if capability.hasPrefix("web.fetch") || capability.hasPrefix("web.live") {
                intents.append("web.fetch_live")
            }
            if capability.hasPrefix("web.navigate") {
                intents.append(contentsOf: ["web.fetch_live", "browser.observe"])
            }
            if capability.hasPrefix("browser.read") || capability.hasPrefix("browser.observe") {
                intents.append("browser.observe")
            }
            if capability == "device.browser.control" || capability.hasPrefix("browser.interact") {
                intents.append(contentsOf: ["browser.observe", "browser.interact"])
            }
            if capability.hasPrefix("browser.secret_fill") {
                intents.append("browser.secret_fill")
            }
            if capability.hasPrefix("device.ui.observe") || capability.hasPrefix("device.screen.capture") {
                intents.append("device.observe")
            }
            if capability.hasPrefix("device.ui.act")
                || capability.hasPrefix("device.ui.step")
                || capability.hasPrefix("device.applescript")
                || capability.hasPrefix("device.clipboard.write") {
                intents.append("device.act")
            }
            if capability.hasPrefix("memory.snapshot")
                || capability.hasPrefix("memory.inspect")
                || capability == "project.snapshot" {
                intents.append("memory.inspect")
            }
            if capability.hasPrefix("ai.generate.local") {
                intents.append("ai.generate.local")
            }
            if capability.hasPrefix("ai.embed.local") {
                intents.append("ai.embed.local")
            }
            if capability.hasPrefix("ai.audio.tts.local") {
                intents.append("ai.audio.tts.local")
            }
            if capability.hasPrefix("ai.audio.local") {
                intents.append("ai.audio.local")
            }
            if capability.hasPrefix("ai.vision.local") {
                intents.append("ai.vision.local")
            }
            if capability.hasPrefix("supervisor.voice.playback") {
                intents.append("voice.playback")
            }
            if capability.hasPrefix("supervisor.orchestrate") {
                intents.append("supervisor.orchestrate")
            }
            if capability.hasPrefix("connector.") || capability.hasPrefix("connectors.") {
                intents.append("repo.deliver")
            }
        }

        return XTSkillCapabilityProfileSupport.normalizedStrings(intents)
    }

    static func canonicalCapabilityFamilies(
        intentFamilies: [String],
        normalizedCapabilities: [String]
    ) -> [String] {
        var families: [String] = []
        for rawIntent in intentFamilies {
            switch rawIntent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "skills.discover",
                 "skills.manage",
                 "repo.read",
                 "repo.verify",
                 "browser.observe",
                 "browser.interact",
                 "browser.secret_fill",
                 "device.observe",
                 "device.act",
                 "memory.inspect",
                 "ai.generate.local",
                 "ai.embed.local",
                 "ai.audio.local",
                 "ai.audio.tts.local",
                 "ai.vision.local",
                 "voice.playback",
                 "supervisor.orchestrate":
                families.append(rawIntent)
            case "repo.modify":
                families.append("repo.mutate")
            case "repo.deliver":
                families.append("repo.delivery")
            case "web.search_live", "web.fetch_live":
                families.append("web.live")
            default:
                break
            }
        }

        for rawCapability in normalizedCapabilities {
            let capability = rawCapability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !capability.isEmpty else { continue }

            if capability.hasPrefix("skills.search") || capability.hasPrefix("skills.discover") {
                families.append("skills.discover")
            }
            if capability.hasPrefix("skills.pin")
                || capability.hasPrefix("skills.manage")
                || capability.hasPrefix("skills.install")
                || capability.hasPrefix("skills.enable")
                || capability.hasPrefix("skills.import") {
                families.append("skills.manage")
            }
            if capability.hasPrefix("repo.read")
                || capability.hasPrefix("filesystem.read")
                || capability.hasPrefix("fs.read")
                || capability == "document.read"
                || capability == "git.status"
                || capability == "git.diff"
                || capability == "project.snapshot" {
                families.append("repo.read")
            }
            if capability.hasPrefix("repo.write")
                || capability.hasPrefix("repo.mutate")
                || capability.hasPrefix("repo.modify")
                || capability.hasPrefix("repo.delete")
                || capability.hasPrefix("repo.move")
                || capability == "git.apply"
                || capability == "git.commit" {
                families.append("repo.mutate")
            }
            if capability.hasPrefix("repo.verify")
                || capability.hasPrefix("repo.test")
                || capability.hasPrefix("repo.build")
                || capability == "run_command"
                || capability == "repo.exec.agent"
                || capability.hasPrefix("process.") {
                families.append("repo.verify")
            }
            if capability.hasPrefix("repo.delivery")
                || capability == "git.push"
                || capability == "pr.create"
                || capability == "ci.trigger" {
                families.append("repo.delivery")
            }
            if capability.hasPrefix("web.search")
                || capability.hasPrefix("web.fetch")
                || capability.hasPrefix("web.live")
                || capability.hasPrefix("web.navigate") {
                families.append("web.live")
            }
            if capability.hasPrefix("browser.read")
                || capability.hasPrefix("browser.observe")
                || capability.hasPrefix("web.navigate") {
                families.append("browser.observe")
            }
            if capability == "device.browser.control" || capability.hasPrefix("browser.interact") {
                families.append(contentsOf: ["browser.observe", "browser.interact"])
            }
            if capability.hasPrefix("browser.secret_fill") {
                families.append("browser.secret_fill")
            }
            if capability.hasPrefix("device.ui.observe") || capability.hasPrefix("device.screen.capture") {
                families.append("device.observe")
            }
            if capability.hasPrefix("device.ui.act")
                || capability.hasPrefix("device.ui.step")
                || capability.hasPrefix("device.applescript")
                || capability.hasPrefix("device.clipboard.write") {
                families.append("device.act")
            }
            if capability.hasPrefix("memory.snapshot")
                || capability.hasPrefix("memory.inspect")
                || capability == "project.snapshot" {
                families.append("memory.inspect")
            }
            if capability.hasPrefix("ai.generate.local") {
                families.append("ai.generate.local")
            }
            if capability.hasPrefix("ai.embed.local") {
                families.append("ai.embed.local")
            }
            if capability.hasPrefix("ai.audio.tts.local") {
                families.append("ai.audio.tts.local")
            }
            if capability.hasPrefix("ai.audio.local") {
                families.append("ai.audio.local")
            }
            if capability.hasPrefix("ai.vision.local") {
                families.append("ai.vision.local")
            }
            if capability.hasPrefix("supervisor.voice.playback") {
                families.append("voice.playback")
            }
            if capability.hasPrefix("supervisor.orchestrate") {
                families.append("supervisor.orchestrate")
            }
            if capability.hasPrefix("connector.") || capability.hasPrefix("connectors.") {
                families.append("connector.deliver")
            }
        }

        return XTSkillCapabilityProfileSupport.orderedCapabilityFamilies(families)
    }

    private static func loadCompanionManifestMetadata(skillDirectory: URL) -> CompanionSkillManifestMetadata? {
        let manifestURL = skillDirectory.appendingPathComponent("skill.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let skillId = firstNonEmpty(
            stringValue(root["skill_id"]),
            stringValue(root["id"])
        )
        let displayName = firstNonEmpty(
            stringValue(root["name"]),
            stringValue(root["title"])
        )
        let description = firstNonEmpty(
            stringValue(root["description"]),
            stringValue(root["summary"])
        )
        let capabilities = stringArrayValue(
            root["capabilities_required"]
                ?? root["required_capabilities"]
                ?? root["capabilities"]
        )
        let riskLevel = firstNonEmpty(
            normalizedRiskLevel(stringValue(root["risk_level"])),
            normalizedRiskLevel(stringValue(root["riskLevel"])),
            normalizedRiskLevel(stringValue(root["risk_profile"]))
        )
        let requiresGrant = boolValue(root["requires_grant"] ?? root["requiresGrant"])

        guard !skillId.isEmpty
            || !displayName.isEmpty
            || !description.isEmpty
            || !capabilities.isEmpty
            || !riskLevel.isEmpty
            || requiresGrant != nil else {
            return nil
        }

        return CompanionSkillManifestMetadata(
            skillId: skillId,
            displayName: displayName,
            description: description,
            capabilities: capabilities,
            riskLevel: riskLevel,
            requiresGrant: requiresGrant
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

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func stringArrayValue(_ value: Any?) -> [String] {
        switch value {
        case let array as [Any]:
            return XTSkillCapabilityProfileSupport.normalizedStrings(
                array.compactMap { item in
                    let raw: String
                    switch item {
                    case let string as String:
                        raw = string
                    case let number as NSNumber:
                        raw = number.stringValue
                    default:
                        raw = ""
                    }
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
            )
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            let body: String
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                body = String(trimmed.dropFirst().dropLast())
            } else {
                body = trimmed
            }
            return XTSkillCapabilityProfileSupport.normalizedStrings(
                body
                    .split(whereSeparator: { $0 == "," || $0 == "\n" })
                    .map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    }
                    .filter { !$0.isEmpty }
            )
        default:
            return []
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return parseBool(string)
        default:
            return nil
        }
    }

    private static func parseBool(_ raw: String?) -> Bool? {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return nil
        }
    }

    private static func normalizedRiskLevel(_ raw: String?) -> String {
        let token = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch token {
        case "moderate":
            return "medium"
        case "low", "medium", "high", "critical":
            return token
        default:
            return ""
        }
    }

    private static func inferRiskLevel(capabilities: [String]) -> String {
        let normalized = XTSkillCapabilityProfileSupport.normalizedStrings(
            capabilities.map { $0.lowercased() }
        )
        if normalized.contains(where: { capability in
            capability.hasPrefix("connector.")
                || capability.hasPrefix("connectors.")
                || capability.hasPrefix("web.")
                || capability.hasPrefix("network.")
                || capability.hasPrefix("ai.generate.paid")
                || capability.hasPrefix("ai.generate.remote")
                || capability.hasPrefix("payments.")
                || capability.hasPrefix("payment.")
                || capability.hasPrefix("shell.")
                || capability.hasPrefix("filesystem.")
                || capability.hasPrefix("fs.")
        }) {
            return "high"
        }
        if normalized.contains(where: { capability in
            capability.hasPrefix("browser.")
                || capability.hasPrefix("email.")
                || capability.hasPrefix("repo.")
        }) {
            return "medium"
        }
        return "low"
    }

    private static func inferRequiresGrant(capabilities: [String], riskLevel: String) -> Bool {
        if ["high", "critical"].contains(normalizedRiskLevel(riskLevel)) {
            return true
        }
        return capabilities.contains { capability in
            let normalized = capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.hasPrefix("connector.")
                || normalized.hasPrefix("connectors.")
                || normalized.hasPrefix("web.")
                || normalized.hasPrefix("network.")
                || normalized.hasPrefix("ai.generate.paid")
                || normalized.hasPrefix("ai.generate.remote")
                || normalized.hasPrefix("payments.")
                || normalized.hasPrefix("payment.")
                || normalized.hasPrefix("shell.")
                || normalized.hasPrefix("filesystem.")
                || normalized.hasPrefix("fs.")
        }
    }

    private static func inferSandboxClass(
        capabilities: [String],
        skillId: String,
        description: String
    ) -> String {
        let normalizedCapabilities = capabilities.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if normalizedCapabilities.contains(where: { $0.hasPrefix("connector.") || $0.hasPrefix("connectors.") }) {
            return "hub_connector_governed"
        }
        if normalizedCapabilities.contains(where: {
            $0.hasPrefix("web.")
                || $0.hasPrefix("browser.")
                || $0 == "device.browser.control"
                || $0 == "device.ui.act"
                || $0.hasPrefix("device.ui.")
                || $0.hasPrefix("device.applescript")
        }) {
            return "governed_device_local"
        }

        let normalizedSkillId = skillId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedSkillId.contains("browser") || description.contains("browser") {
            return "governed_device_local"
        }
        return "governed_project_local"
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
