import Foundation

enum AXSkillCompatibilityState: String, Codable, CaseIterable, Sendable {
    case supported
    case partial
    case unsupported
    case unknown
}

enum AXSkillsCompatibilityStatusKind: String, Codable, Sendable {
    case unavailable
    case supported
    case partial
    case blocked
}

struct AXSkillsIndexReference: Identifiable, Codable, Equatable, Sendable {
    var scope: String
    var title: String
    var path: String
    var summary: String

    var id: String { "\(scope)::\(title)::\(path)" }
}

struct AXHubSkillCompatibilityEntry: Identifiable, Codable, Equatable, Sendable {
    var skillID: String
    var name: String
    var version: String
    var publisherID: String
    var sourceID: String
    var packageSHA256: String
    var abiCompatVersion: String
    var compatibilityState: AXSkillCompatibilityState
    var canonicalManifestSHA256: String
    var installHint: String
    var mappingAliasesUsed: [String]
    var defaultsApplied: [String]
    var pinnedScopes: [String]
    var revoked: Bool

    var id: String { packageSHA256 }
}

struct AXDefaultAgentBaselineSkill: Identifiable, Codable, Equatable, Sendable {
    var skillID: String
    var displayName: String
    var summary: String

    var id: String { skillID }

    enum CodingKeys: String, CodingKey {
        case skillID = "skill_id"
        case displayName = "display_name"
        case summary
    }
}

struct AXSkillsDoctorSnapshot: Codable, Equatable, Sendable {
    static let empty = AXSkillsDoctorSnapshot(
        hubIndexAvailable: false,
        installedSkillCount: 0,
        compatibleSkillCount: 0,
        partialCompatibilityCount: 0,
        revokedMatchCount: 0,
        trustEnabledPublisherCount: 0,
        baselineRecommendedSkills: [],
        missingBaselineSkillIDs: [],
        projectIndexEntries: [],
        globalIndexEntries: [],
        conflictWarnings: [],
        installedSkills: [],
        statusKind: .unavailable,
        statusLine: "skills?",
        compatibilityExplain: "skills compatibility unavailable"
    )

    var hubIndexAvailable: Bool
    var installedSkillCount: Int
    var compatibleSkillCount: Int
    var partialCompatibilityCount: Int
    var revokedMatchCount: Int
    var trustEnabledPublisherCount: Int
    var baselineRecommendedSkills: [AXDefaultAgentBaselineSkill] = []
    var missingBaselineSkillIDs: [String] = []
    var projectIndexEntries: [AXSkillsIndexReference]
    var globalIndexEntries: [AXSkillsIndexReference]
    var conflictWarnings: [String]
    var installedSkills: [AXHubSkillCompatibilityEntry]
    var statusKind: AXSkillsCompatibilityStatusKind
    var statusLine: String
    var compatibilityExplain: String

    static let localDevPublisherID = "xhub.local.dev"

    var activePublisherIDs: [String] {
        Array(
            Set(
                installedSkills
                    .map(\.publisherID)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }

    var activeSourceIDs: [String] {
        Array(
            Set(
                installedSkills
                    .map(\.sourceID)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }

    var localDevPublisherActive: Bool {
        activePublisherIDs.contains(Self.localDevPublisherID)
    }

    var baselineResolvedCount: Int {
        max(0, baselineRecommendedSkills.count - missingBaselineSkillIDs.count)
    }

    var baselinePublisherIDs: [String] {
        Array(
            Set(
                baselineInstalledSkillsForPublisherRollup
                    .map(\.publisherID)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }

    var baselineLocalDevSkillCount: Int {
        let ids = Set(
            baselineInstalledSkillsForPublisherRollup
                .filter { $0.publisherID.trimmingCharacters(in: .whitespacesAndNewlines) == Self.localDevPublisherID }
                .map(\.skillID)
        )
        return ids.count
    }

    private var baselineInstalledSkillsForPublisherRollup: [AXHubSkillCompatibilityEntry] {
        let baselineSkillIDs = Set(baselineRecommendedSkills.map(\.skillID))
        guard !baselineSkillIDs.isEmpty else { return [] }

        let baselineInstalled = installedSkills.filter { baselineSkillIDs.contains($0.skillID) }
        let pinnedBaselineInstalled = baselineInstalled.filter { !$0.pinnedScopes.isEmpty }
        return pinnedBaselineInstalled.isEmpty ? baselineInstalled : pinnedBaselineInstalled
    }
}

struct XTResolvedSkillCacheItem: Identifiable, Codable, Equatable, Sendable {
    var skillId: String
    var displayName: String
    var description: String
    var packageSHA256: String
    var canonicalManifestSHA256: String
    var sourceId: String
    var pinScope: String
    var riskLevel: String
    var requiresGrant: Bool
    var sideEffectClass: String
    var inputSchemaRef: String
    var outputSchemaRef: String
    var timeoutMs: Int
    var maxRetries: Int

    var id: String { "\(skillId)::\(packageSHA256)" }

    enum CodingKeys: String, CodingKey {
        case skillId = "skill_id"
        case displayName = "display_name"
        case description
        case packageSHA256 = "package_sha256"
        case canonicalManifestSHA256 = "canonical_manifest_sha256"
        case sourceId = "source_id"
        case pinScope = "pin_scope"
        case riskLevel = "risk_level"
        case requiresGrant = "requires_grant"
        case sideEffectClass = "side_effect_class"
        case inputSchemaRef = "input_schema_ref"
        case outputSchemaRef = "output_schema_ref"
        case timeoutMs = "timeout_ms"
        case maxRetries = "max_retries"
    }
}

struct XTResolvedSkillsCacheSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.resolved_skills_cache.v1"

    var schemaVersion: String
    var projectId: String
    var projectName: String?
    var resolvedSnapshotId: String
    var source: String
    var grantSnapshotRef: String
    var auditRef: String
    var resolvedAtMs: Int64
    var expiresAtMs: Int64
    var hubIndexUpdatedAtMs: Int64
    var items: [XTResolvedSkillCacheItem]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case projectName = "project_name"
        case resolvedSnapshotId = "resolved_snapshot_id"
        case source
        case grantSnapshotRef = "grant_snapshot_ref"
        case auditRef = "audit_ref"
        case resolvedAtMs = "resolved_at_ms"
        case expiresAtMs = "expires_at_ms"
        case hubIndexUpdatedAtMs = "hub_index_updated_at_ms"
        case items
    }
}

extension AXSkillsLibrary {
    static let defaultAgentBaselineSkills: [AXDefaultAgentBaselineSkill] = [
        AXDefaultAgentBaselineSkill(
            skillID: "find-skills",
            displayName: "Find Skills",
            summary: "Official discovery wrapper over Hub skills.search."
        ),
        AXDefaultAgentBaselineSkill(
            skillID: "agent-browser",
            displayName: "Agent Browser",
            summary: "Governed browser automation for navigation, screenshots, extraction, and Secret Vault-aware credential handling."
        ),
        AXDefaultAgentBaselineSkill(
            skillID: "self-improving-agent",
            displayName: "Self Improving Agent",
            summary: "Supervisor retrospective pack for learning from failures under governance."
        ),
        AXDefaultAgentBaselineSkill(
            skillID: "summarize",
            displayName: "Summarize",
            summary: "Governed summarize wrapper for webpages, PDFs, and long documents."
        ),
    ]

    static func compatibilityDoctorSnapshot(
        projectId: String? = nil,
        projectName: String? = nil,
        skillsDir: URL? = nil,
        hubBaseDir: URL? = nil
    ) -> AXSkillsDoctorSnapshot {
        let resolvedSkillsDir = skillsDir ?? resolveSkillsDirectory()
        let resolvedHubBaseDir = hubBaseDir ?? HubPaths.baseDir()
        let storeDir = resolvedHubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
        let indexURL = storeDir.appendingPathComponent("skills_store_index.json")
        let pinsURL = storeDir.appendingPathComponent("skills_pins.json")
        let trustedPublishersURL = storeDir.appendingPathComponent("trusted_publishers.json")
        let revocationsURL = storeDir.appendingPathComponent("skill_revocations.json")

        let hubIndex = loadHubSkillsIndex(url: indexURL)
        let pins = loadHubSkillsPins(url: pinsURL)
        let trusted = loadTrustedPublishers(url: trustedPublishersURL)
        let revocations = loadSkillRevocations(url: revocationsURL)
        let relevantPins = relevantPinScopes(pins: pins, projectId: projectId)
        let pinnedScopesBySkill = Dictionary(grouping: relevantPins, by: \.skillID)
            .mapValues { pins in
                Array(Set(pins.map(\.scope))).sorted()
            }

        let installedSkills = hubIndex.skills.map { skill in
            let isRevoked = revocations.revokedSHA256.contains(skill.packageSHA256)
                || revocations.revokedSkillIDs.contains(skill.skillID)
                || revocations.revokedPublisherIDs.contains(skill.publisherID)
            return AXHubSkillCompatibilityEntry(
                skillID: skill.skillID,
                name: skill.name,
                version: skill.version,
                publisherID: skill.publisherID,
                sourceID: skill.sourceID,
                packageSHA256: skill.packageSHA256,
                abiCompatVersion: skill.abiCompatVersion,
                compatibilityState: skill.compatibilityState,
                canonicalManifestSHA256: skill.canonicalManifestSHA256,
                installHint: skill.installHint,
                mappingAliasesUsed: skill.mappingAliasesUsed,
                defaultsApplied: skill.defaultsApplied,
                pinnedScopes: pinnedScopesBySkill[skill.skillID] ?? [],
                revoked: isRevoked
            )
        }
        .sorted { lhs, rhs in
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            let versionOrder = lhs.version.localizedCaseInsensitiveCompare(rhs.version)
            if versionOrder != .orderedSame {
                return versionOrder == .orderedAscending
            }
            return lhs.packageSHA256 < rhs.packageSHA256
        }

        let compatibleSkillCount = installedSkills.filter { !$0.abiCompatVersion.isEmpty }.count
        let partialCompatibilityCount = installedSkills.filter { $0.compatibilityState == .partial }.count
        let revokedMatchCount = installedSkills.filter(\.revoked).count
        let installedSkillIDs = Set(installedSkills.map(\.skillID))
        let missingBaselineSkillIDs = defaultAgentBaselineSkills
            .map(\.skillID)
            .filter { !installedSkillIDs.contains($0) }
        let projectIndexEntries = loadProjectIndexEntries(skillsDir: resolvedSkillsDir, projectId: projectId, projectName: projectName)
        let globalIndexEntries = loadGlobalIndexEntries(skillsDir: resolvedSkillsDir)
        let conflictWarnings = compatibilityConflicts(for: relevantPins)
        let statusKind: AXSkillsCompatibilityStatusKind
        if !hubIndex.available {
            statusKind = .unavailable
        } else if revokedMatchCount > 0 {
            statusKind = .blocked
        } else if partialCompatibilityCount > 0 || !missingBaselineSkillIDs.isEmpty {
            statusKind = .partial
        } else {
            statusKind = .supported
        }

        let baseStatusLine: String
        let baselineInstalledCount = defaultAgentBaselineSkills.count - missingBaselineSkillIDs.count
        let baselineSuffix = defaultAgentBaselineSkills.isEmpty
            ? ""
            : " b\(baselineInstalledCount)/\(defaultAgentBaselineSkills.count)"
        switch statusKind {
        case .unavailable:
            baseStatusLine = "skills?"
        case .blocked:
            baseStatusLine = "skills! \(compatibleSkillCount)/\(installedSkills.count)\(baselineSuffix)"
        case .partial:
            baseStatusLine = "skills~ \(compatibleSkillCount)/\(installedSkills.count)\(baselineSuffix)"
        case .supported:
            baseStatusLine = "skills \(compatibleSkillCount)/\(installedSkills.count)\(baselineSuffix)"
        }

        let draftSnapshot = AXSkillsDoctorSnapshot(
            hubIndexAvailable: hubIndex.available,
            installedSkillCount: installedSkills.count,
            compatibleSkillCount: compatibleSkillCount,
            partialCompatibilityCount: partialCompatibilityCount,
            revokedMatchCount: revokedMatchCount,
            trustEnabledPublisherCount: trusted.publishers.filter(\.enabled).count,
            baselineRecommendedSkills: defaultAgentBaselineSkills,
            missingBaselineSkillIDs: missingBaselineSkillIDs,
            projectIndexEntries: projectIndexEntries,
            globalIndexEntries: globalIndexEntries,
            conflictWarnings: conflictWarnings,
            installedSkills: installedSkills,
            statusKind: statusKind,
            statusLine: baseStatusLine,
            compatibilityExplain: ""
        )
        let statusLine = draftSnapshot.localDevPublisherActive ? "\(baseStatusLine) dev" : baseStatusLine

        let explain = renderCompatibilityExplainability(
            statusKind: statusKind,
            installedSkills: installedSkills,
            baselineRecommendedSkills: defaultAgentBaselineSkills,
            missingBaselineSkillIDs: missingBaselineSkillIDs,
            trustedPublisherCount: trusted.publishers.filter(\.enabled).count,
            projectIndexEntries: projectIndexEntries,
            globalIndexEntries: globalIndexEntries,
            conflictWarnings: conflictWarnings,
            activePublisherIDs: draftSnapshot.activePublisherIDs,
            activeSourceIDs: draftSnapshot.activeSourceIDs,
            localDevPublisherActive: draftSnapshot.localDevPublisherActive,
            baselinePublisherIDs: draftSnapshot.baselinePublisherIDs,
            baselineLocalDevSkillCount: draftSnapshot.baselineLocalDevSkillCount
        )

        return AXSkillsDoctorSnapshot(
            hubIndexAvailable: hubIndex.available,
            installedSkillCount: installedSkills.count,
            compatibleSkillCount: compatibleSkillCount,
            partialCompatibilityCount: partialCompatibilityCount,
            revokedMatchCount: revokedMatchCount,
            trustEnabledPublisherCount: trusted.publishers.filter(\.enabled).count,
            baselineRecommendedSkills: defaultAgentBaselineSkills,
            missingBaselineSkillIDs: missingBaselineSkillIDs,
            projectIndexEntries: projectIndexEntries,
            globalIndexEntries: globalIndexEntries,
            conflictWarnings: conflictWarnings,
            installedSkills: installedSkills,
            statusKind: statusKind,
            statusLine: statusLine,
            compatibilityExplain: explain
        )
    }

    private struct HubSkillsIndexSnapshot: Codable {
        struct Skill: Codable {
            var skillID: String
            var name: String
            var version: String
            var description: String
            var publisherID: String
            var sourceID: String
            var packageSHA256: String
            var abiCompatVersion: String
            var compatibilityState: AXSkillCompatibilityState
            var canonicalManifestSHA256: String
            var installHint: String
            var capabilitiesRequired: [String]
            var manifestJSON: String
            var mappingAliasesUsed: [String]
            var defaultsApplied: [String]

            enum CodingKeys: String, CodingKey {
                case skillID = "skill_id"
                case name
                case version
                case description
                case publisherID = "publisher_id"
                case sourceID = "source_id"
                case packageSHA256 = "package_sha256"
                case abiCompatVersion = "abi_compat_version"
                case compatibilityState = "compatibility_state"
                case canonicalManifestSHA256 = "canonical_manifest_sha256"
                case installHint = "install_hint"
                case capabilitiesRequired = "capabilities_required"
                case manifestJSON = "manifest_json"
                case mappingAliasesUsed = "mapping_aliases_used"
                case defaultsApplied = "defaults_applied"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                skillID = (try? container.decode(String.self, forKey: .skillID)) ?? ""
                name = (try? container.decode(String.self, forKey: .name)) ?? skillID
                version = (try? container.decode(String.self, forKey: .version)) ?? ""
                description = (try? container.decode(String.self, forKey: .description)) ?? ""
                publisherID = (try? container.decode(String.self, forKey: .publisherID)) ?? ""
                sourceID = (try? container.decode(String.self, forKey: .sourceID)) ?? ""
                packageSHA256 = ((try? container.decode(String.self, forKey: .packageSHA256)) ?? "").lowercased()
                abiCompatVersion = (try? container.decode(String.self, forKey: .abiCompatVersion)) ?? ""
                compatibilityState = (try? container.decode(AXSkillCompatibilityState.self, forKey: .compatibilityState)) ?? .unknown
                canonicalManifestSHA256 = ((try? container.decode(String.self, forKey: .canonicalManifestSHA256)) ?? "").lowercased()
                installHint = (try? container.decode(String.self, forKey: .installHint)) ?? ""
                capabilitiesRequired = (try? container.decode([String].self, forKey: .capabilitiesRequired)) ?? []
                manifestJSON = (try? container.decode(String.self, forKey: .manifestJSON)) ?? ""
                mappingAliasesUsed = (try? container.decode([String].self, forKey: .mappingAliasesUsed)) ?? []
                defaultsApplied = (try? container.decode([String].self, forKey: .defaultsApplied)) ?? []
            }
        }

        var schemaVersion: String
        var updatedAtMs: Int64
        var skills: [Skill]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case skills
        }
    }

    private struct HubSkillsPinsSnapshot: Codable {
        init(memoryCorePins: [Pin], globalPins: [Pin], projectPins: [Pin]) {
            self.memoryCorePins = memoryCorePins
            self.globalPins = globalPins
            self.projectPins = projectPins
        }
        struct Pin: Codable {
            var skillID: String
            var packageSHA256: String
            var projectID: String?
            var scope: String = ""

            enum CodingKeys: String, CodingKey {
                case skillID = "skill_id"
                case packageSHA256 = "package_sha256"
                case projectID = "project_id"
            }
        }

        var memoryCorePins: [Pin]
        var globalPins: [Pin]
        var projectPins: [Pin]

        enum CodingKeys: String, CodingKey {
            case memoryCorePins = "memory_core_pins"
            case globalPins = "global_pins"
            case projectPins = "project_pins"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            memoryCorePins = ((try? container.decode([Pin].self, forKey: .memoryCorePins)) ?? []).map {
                Pin(skillID: $0.skillID, packageSHA256: $0.packageSHA256.lowercased(), projectID: nil, scope: "memory_core")
            }
            globalPins = ((try? container.decode([Pin].self, forKey: .globalPins)) ?? []).map {
                Pin(skillID: $0.skillID, packageSHA256: $0.packageSHA256.lowercased(), projectID: nil, scope: "global")
            }
            projectPins = ((try? container.decode([Pin].self, forKey: .projectPins)) ?? []).map {
                Pin(skillID: $0.skillID, packageSHA256: $0.packageSHA256.lowercased(), projectID: $0.projectID, scope: "project")
            }
        }
    }

    private struct TrustedPublishersSnapshot: Codable {
        struct Publisher: Codable {
            var publisherID: String
            var enabled: Bool

            enum CodingKeys: String, CodingKey {
                case publisherID = "publisher_id"
                case enabled
            }
        }

        var publishers: [Publisher]
    }

    private struct SkillRevocationsSnapshot: Codable {
        init(revokedSHA256: [String], revokedSkillIDs: [String], revokedPublisherIDs: [String]) {
            self.revokedSHA256 = revokedSHA256
            self.revokedSkillIDs = revokedSkillIDs
            self.revokedPublisherIDs = revokedPublisherIDs
        }
        var revokedSHA256: [String]
        var revokedSkillIDs: [String]
        var revokedPublisherIDs: [String]

        enum CodingKeys: String, CodingKey {
            case revokedSHA256 = "revoked_sha256"
            case revokedSkillIDs = "revoked_skill_ids"
            case revokedPublisherIDs = "revoked_publishers"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            revokedSHA256 = ((try? container.decode([String].self, forKey: .revokedSHA256)) ?? []).map { $0.lowercased() }
            revokedSkillIDs = (try? container.decode([String].self, forKey: .revokedSkillIDs)) ?? []
            revokedPublisherIDs = (try? container.decode([String].self, forKey: .revokedPublisherIDs)) ?? []
        }
    }

    private static func loadHubSkillsIndex(url: URL) -> (available: Bool, skills: [HubSkillsIndexSnapshot.Skill]) {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(HubSkillsIndexSnapshot.self, from: data) else {
            return (false, [])
        }
        return (true, snapshot.skills)
    }

    private static func loadHubSkillsPins(url: URL) -> HubSkillsPinsSnapshot {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(HubSkillsPinsSnapshot.self, from: data) else {
            return HubSkillsPinsSnapshot(memoryCorePins: [], globalPins: [], projectPins: [])
        }
        return snapshot
    }

    private static func loadTrustedPublishers(url: URL) -> TrustedPublishersSnapshot {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(TrustedPublishersSnapshot.self, from: data) else {
            return TrustedPublishersSnapshot(publishers: [])
        }
        return snapshot
    }

    private static func loadSkillRevocations(url: URL) -> SkillRevocationsSnapshot {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(SkillRevocationsSnapshot.self, from: data) else {
            return SkillRevocationsSnapshot(revokedSHA256: [], revokedSkillIDs: [], revokedPublisherIDs: [])
        }
        return snapshot
    }

    private static func relevantPinScopes(pins: HubSkillsPinsSnapshot, projectId: String?) -> [HubSkillsPinsSnapshot.Pin] {
        let projectPins = pins.projectPins.filter { pin in
            guard let projectId else { return false }
            return pin.projectID == projectId
        }
        return pins.memoryCorePins + pins.globalPins + projectPins
    }

    static func projectSkillsIndexURLIfExists(projectId: String, projectName: String?, skillsDir: URL) -> URL? {
        guard let projectDir = existingProjectSkillsDir(projectId: projectId, projectName: projectName, skillsDir: skillsDir) else {
            return nil
        }
        let url = projectDir.appendingPathComponent("skills-index.md")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func globalSkillsIndexURLIfExists(skillsDir: URL) -> URL? {
        let url = skillsDir
            .appendingPathComponent("memory-core", isDirectory: true)
            .appendingPathComponent("references", isDirectory: true)
            .appendingPathComponent("skills-index.md")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func loadProjectIndexEntries(skillsDir: URL?, projectId: String?, projectName: String?) -> [AXSkillsIndexReference] {
        guard let skillsDir, let projectId else { return [] }
        guard let projectDir = existingProjectSkillsDir(projectId: projectId, projectName: projectName, skillsDir: skillsDir) else {
            return []
        }
        return parseIndexMarkdown(url: projectDir.appendingPathComponent("skills-index.md"), scope: "project")
    }

    private static func loadGlobalIndexEntries(skillsDir: URL?) -> [AXSkillsIndexReference] {
        guard let skillsDir else { return [] }
        let indexURL = skillsDir
            .appendingPathComponent("memory-core", isDirectory: true)
            .appendingPathComponent("references", isDirectory: true)
            .appendingPathComponent("skills-index.md")
        return parseIndexMarkdown(url: indexURL, scope: "global")
    }

    private static func existingProjectSkillsDir(projectId: String, projectName: String?, skillsDir: URL) -> URL? {
        let root = skillsDir.appendingPathComponent("_projects", isDirectory: true)
        let suffix = String(projectId.prefix(8))
        if let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for item in items where item.hasDirectoryPath {
                let name = item.lastPathComponent
                if name.hasSuffix("-\(suffix)") || name == "project-\(suffix)" {
                    return item
                }
            }
        }

        let safeName = sanitizeProjectDirName(projectName)
        guard !safeName.isEmpty else { return nil }
        let fallback = root.appendingPathComponent("\(safeName)-\(suffix)", isDirectory: true)
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    private static func sanitizeProjectDirName(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let forbidden = CharacterSet(charactersIn: "/\\:?*|\"<>")
        var out = ""
        for scalar in trimmed.unicodeScalars {
            if forbidden.contains(scalar) {
                out.append("-")
            } else {
                out.append(Character(scalar))
            }
        }
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseIndexMarkdown(url: URL, scope: String) -> [AXSkillsIndexReference] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { rawLine -> AXSkillsIndexReference? in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
                let payload = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !payload.isEmpty else { return nil }
                let extractedPath = extractIndexPath(from: payload)
                let title = payload
                    .components(separatedBy: "—")
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? payload
                let summary = payload == title ? "" : payload.replacingOccurrences(of: title, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return AXSkillsIndexReference(scope: scope, title: title, path: extractedPath, summary: summary)
            }
    }

    private static func extractIndexPath(from payload: String) -> String {
        let markers = ["路径：", "path:", "path=", "Path:"]
        for marker in markers {
            guard let range = payload.range(of: marker) else { continue }
            let suffix = payload[range.upperBound...]
            let path = suffix
                .trimmingCharacters(in: CharacterSet(charactersIn: " ）)】]`"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return path
            }
        }
        if let range = payload.range(of: "<skills_dir>") {
            let suffix = payload[range.lowerBound...]
            let path = suffix
                .split(whereSeparator: { $0.isWhitespace || $0 == "）" || $0 == ")" || $0 == "】" || $0 == "]" })
                .first
                .map(String.init) ?? ""
            if !path.isEmpty {
                return path
            }
        }
        return ""
    }

    private static func compatibilityConflicts(for pins: [HubSkillsPinsSnapshot.Pin]) -> [String] {
        let grouped = Dictionary(grouping: pins, by: \.skillID)
        return grouped.compactMap { skillID, scopedPins in
            let packageSet = Set(scopedPins.map(\.packageSHA256).filter { !$0.isEmpty })
            guard packageSet.count > 1 else { return nil }
            let scopes = Set(scopedPins.map(\.scope)).sorted().joined(separator: ",")
            return "pin_conflict: \(skillID) -> \(packageSet.count) package variants across \(scopes)"
        }
        .sorted()
    }

    private static func renderCompatibilityExplainability(
        statusKind: AXSkillsCompatibilityStatusKind,
        installedSkills: [AXHubSkillCompatibilityEntry],
        baselineRecommendedSkills: [AXDefaultAgentBaselineSkill],
        missingBaselineSkillIDs: [String],
        trustedPublisherCount: Int,
        projectIndexEntries: [AXSkillsIndexReference],
        globalIndexEntries: [AXSkillsIndexReference],
        conflictWarnings: [String],
        activePublisherIDs: [String],
        activeSourceIDs: [String],
        localDevPublisherActive: Bool,
        baselinePublisherIDs: [String],
        baselineLocalDevSkillCount: Int
    ) -> String {
        var lines: [String] = []
        switch statusKind {
        case .unavailable:
            lines.append("skills compatibility unavailable: hub skills_store_index.json not found")
        case .blocked:
            lines.append("compatible skill installed, but revocation or trust blockers remain visible")
        case .partial:
            lines.append("compatible skill installed with alias/default compatibility mapping")
        case .supported:
            lines.append("compatible skill installed under Hub canonical manifest gates")
        }
        lines.append("installed=\(installedSkills.count) trusted_publishers=\(trustedPublisherCount) project_index=\(projectIndexEntries.count) global_index=\(globalIndexEntries.count)")
        lines.append(activePublisherIDs.isEmpty ? "active_publishers=none" : "active_publishers=\(activePublisherIDs.joined(separator: ","))")
        lines.append(activeSourceIDs.isEmpty ? "active_sources=none" : "active_sources=\(activeSourceIDs.joined(separator: ","))")
        lines.append("local_dev_publisher_active=\(localDevPublisherActive ? "yes" : "no")")
        if !baselineRecommendedSkills.isEmpty {
            lines.append("baseline=\(baselineRecommendedSkills.count - missingBaselineSkillIDs.count)/\(baselineRecommendedSkills.count)")
            lines.append(baselinePublisherIDs.isEmpty ? "baseline_publishers=none" : "baseline_publishers=\(baselinePublisherIDs.joined(separator: ","))")
            lines.append("baseline_local_dev=\(baselineLocalDevSkillCount)/\(baselineRecommendedSkills.count)")
            if !missingBaselineSkillIDs.isEmpty {
                lines.append("baseline_missing=\(missingBaselineSkillIDs.joined(separator: ","))")
            }
        }

        if let first = installedSkills.first {
            let scopes = first.pinnedScopes.isEmpty ? "unpinned" : first.pinnedScopes.joined(separator: ",")
            lines.append("top_skill=\(first.name)@\(first.version) state=\(first.compatibilityState.rawValue) scopes=\(scopes)")
            if !first.mappingAliasesUsed.isEmpty {
                lines.append("mapping_aliases=\(first.mappingAliasesUsed.joined(separator: ","))")
            }
            if !first.defaultsApplied.isEmpty {
                lines.append("defaults_applied=\(first.defaultsApplied.joined(separator: ","))")
            }
        }

        if !conflictWarnings.isEmpty {
            lines.append(contentsOf: conflictWarnings.prefix(3))
        }

        return lines.joined(separator: "\n")
    }

    static func supervisorSkillRegistrySnapshot(
        projectId: String,
        projectName: String? = nil,
        hubBaseDir: URL? = nil
    ) -> SupervisorSkillRegistrySnapshot? {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return nil }

        let resolvedHubBaseDir = hubBaseDir ?? HubPaths.baseDir()
        let storeDir = resolvedHubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
        let indexURL = storeDir.appendingPathComponent("skills_store_index.json")
        let pinsURL = storeDir.appendingPathComponent("skills_pins.json")
        let revocationsURL = storeDir.appendingPathComponent("skill_revocations.json")

        let hubIndex = loadHubSkillsIndex(url: indexURL)
        let pins = loadHubSkillsPins(url: pinsURL)
        let revocations = loadSkillRevocations(url: revocationsURL)
        let relevantPins = relevantPinScopes(pins: pins, projectId: normalizedProjectId)
        let selectedPins = selectedResolvedPinsForSupervisorRegistry(relevantPins)
        let skillPairs: [(String, HubSkillsIndexSnapshot.Skill)] = hubIndex.skills.compactMap { skill in
            let sha = skill.packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !sha.isEmpty else { return nil }
            return (sha, skill)
        }
        let skillBySHA = Dictionary(uniqueKeysWithValues: skillPairs)

        let items = selectedPins.compactMap { pin -> SupervisorSkillRegistryItem? in
            let sha = pin.packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let skill = skillBySHA[sha] else { return nil }
            let revoked = revocations.revokedSHA256.contains(sha)
                || revocations.revokedSkillIDs.contains(skill.skillID)
                || revocations.revokedPublisherIDs.contains(skill.publisherID)
            guard !revoked else { return nil }
            guard !skill.abiCompatVersion.isEmpty else { return nil }
            guard skill.compatibilityState != .unsupported else { return nil }
            return supervisorSkillRegistryItem(skill: skill, scope: pin.scope)
        }
        .sorted { lhs, rhs in
            let leftScope = skillPinnedScopePriority(lhs.policyScope)
            let rightScope = skillPinnedScopePriority(rhs.policyScope)
            if leftScope != rightScope {
                return leftScope > rightScope
            }
            return lhs.skillId.localizedCaseInsensitiveCompare(rhs.skillId) == .orderedAscending
        }

        let updatedAtMs = max(0, hubIndex.skills.map(\.version).isEmpty ? 0 : loadHubSkillsIndexUpdatedAtMs(url: indexURL))
        let source = hubIndex.available ? "hub_skill_registry" : "hub_skill_registry_unavailable"
        return SupervisorSkillRegistrySnapshot(
            schemaVersion: SupervisorSkillRegistrySnapshot.currentSchemaVersion,
            projectId: normalizedProjectId,
            projectName: projectName,
            updatedAtMs: updatedAtMs,
            memorySource: source,
            items: items,
            auditRef: "audit-xt-w3-32-skill-registry-\(String(normalizedProjectId.suffix(8)))"
        )
    }

    static func resolvedSkillsCacheSnapshot(
        projectId: String,
        projectName: String? = nil,
        hubBaseDir: URL? = nil,
        ttlMs: Int64 = 15 * 60 * 1000,
        nowMs: Int64? = nil
    ) -> XTResolvedSkillsCacheSnapshot? {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return nil }

        let resolvedHubBaseDir = hubBaseDir ?? HubPaths.baseDir()
        let storeDir = resolvedHubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
        let indexURL = storeDir.appendingPathComponent("skills_store_index.json")
        let pinsURL = storeDir.appendingPathComponent("skills_pins.json")
        let revocationsURL = storeDir.appendingPathComponent("skill_revocations.json")

        let hubIndex = loadHubSkillsIndex(url: indexURL)
        guard hubIndex.available else { return nil }

        let pins = loadHubSkillsPins(url: pinsURL)
        let revocations = loadSkillRevocations(url: revocationsURL)
        let relevantPins = relevantPinScopes(pins: pins, projectId: normalizedProjectId)
        let selectedPins = selectedResolvedPinsForSupervisorRegistry(relevantPins)
        let skillPairs: [(String, HubSkillsIndexSnapshot.Skill)] = hubIndex.skills.compactMap { skill in
            let sha = skill.packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !sha.isEmpty else { return nil }
            return (sha, skill)
        }
        let skillBySHA = Dictionary(uniqueKeysWithValues: skillPairs)

        let items = selectedPins.compactMap { pin -> XTResolvedSkillCacheItem? in
            let sha = pin.packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let skill = skillBySHA[sha] else { return nil }
            let revoked = revocations.revokedSHA256.contains(sha)
                || revocations.revokedSkillIDs.contains(skill.skillID)
                || revocations.revokedPublisherIDs.contains(skill.publisherID)
            guard !revoked else { return nil }
            guard !skill.abiCompatVersion.isEmpty else { return nil }
            guard skill.compatibilityState != .unsupported else { return nil }
            let hints = parseSupervisorSkillManifestHints(
                skill.manifestJSON,
                fallbackDescription: firstNonEmptySkillText(skill.description, skill.installHint, skill.name),
                capabilityFallback: skill.capabilitiesRequired
            )
            return XTResolvedSkillCacheItem(
                skillId: skill.skillID,
                displayName: firstNonEmptySkillText(skill.name, skill.skillID),
                description: hints.description,
                packageSHA256: sha,
                canonicalManifestSHA256: skill.canonicalManifestSHA256,
                sourceId: skill.sourceID,
                pinScope: pin.scope,
                riskLevel: hints.riskLevel.rawValue,
                requiresGrant: hints.requiresGrant,
                sideEffectClass: hints.sideEffectClass,
                inputSchemaRef: hints.inputSchemaRef.isEmpty ? "schema://\(skill.skillID).input" : hints.inputSchemaRef,
                outputSchemaRef: hints.outputSchemaRef.isEmpty ? "schema://\(skill.skillID).output" : hints.outputSchemaRef,
                timeoutMs: max(1_000, hints.timeoutMs),
                maxRetries: max(0, hints.maxRetries)
            )
        }
        .sorted { lhs, rhs in
            let leftScope = skillPinnedScopePriority(lhs.pinScope)
            let rightScope = skillPinnedScopePriority(rhs.pinScope)
            if leftScope != rightScope {
                return leftScope > rightScope
            }
            return lhs.skillId.localizedCaseInsensitiveCompare(rhs.skillId) == .orderedAscending
        }

        let resolvedAt = max(0, nowMs ?? Int64(Date().timeIntervalSince1970 * 1000.0))
        let normalizedTTL = max(60_000, ttlMs)
        let projectSuffix = String(normalizedProjectId.suffix(8))
        let grantSnapshotRef = items.contains(where: { $0.requiresGrant })
            ? "grant-chain:\(projectSuffix):refresh_required"
            : "grant-chain:\(projectSuffix):not_required"

        return XTResolvedSkillsCacheSnapshot(
            schemaVersion: XTResolvedSkillsCacheSnapshot.currentSchemaVersion,
            projectId: normalizedProjectId,
            projectName: projectName,
            resolvedSnapshotId: "xt-resolved-skills-\(projectSuffix)-\(resolvedAt)",
            source: "hub_resolved_skills_snapshot",
            grantSnapshotRef: grantSnapshotRef,
            auditRef: "audit-xt-w3-34-i-resolved-skills-\(projectSuffix)",
            resolvedAtMs: resolvedAt,
            expiresAtMs: resolvedAt + normalizedTTL,
            hubIndexUpdatedAtMs: max(0, loadHubSkillsIndexUpdatedAtMs(url: indexURL)),
            items: items
        )
    }

    private struct SupervisorSkillManifestHints {
        var description: String
        var capabilitiesRequired: [String]
        var governedDispatch: SupervisorGovernedSkillDispatch?
        var inputSchemaRef: String
        var outputSchemaRef: String
        var sideEffectClass: String
        var riskLevel: SupervisorSkillRiskLevel
        var requiresGrant: Bool
        var timeoutMs: Int
        var maxRetries: Int
    }

    private static func selectedResolvedPinsForSupervisorRegistry(
        _ pins: [HubSkillsPinsSnapshot.Pin]
    ) -> [HubSkillsPinsSnapshot.Pin] {
        let grouped = Dictionary(grouping: pins, by: \.skillID)
        return grouped.compactMap { _, scopedPins in
            scopedPins
                .sorted { lhs, rhs in
                    let leftScope = skillPinnedScopePriority(lhs.scope)
                    let rightScope = skillPinnedScopePriority(rhs.scope)
                    if leftScope != rightScope {
                        return leftScope > rightScope
                    }
                    return lhs.packageSHA256 < rhs.packageSHA256
                }
                .first
        }
    }

    private static func supervisorSkillRegistryItem(
        skill: HubSkillsIndexSnapshot.Skill,
        scope: String
    ) -> SupervisorSkillRegistryItem {
        let manifestHints = parseSupervisorSkillManifestHints(
            skill.manifestJSON,
            fallbackDescription: firstNonEmptySkillText(skill.description, skill.installHint, skill.name),
            capabilityFallback: skill.capabilitiesRequired
        )
        return SupervisorSkillRegistryItem(
            skillId: skill.skillID,
            displayName: firstNonEmptySkillText(skill.name, skill.skillID),
            description: manifestHints.description,
            capabilitiesRequired: manifestHints.capabilitiesRequired,
            governedDispatch: manifestHints.governedDispatch,
            inputSchemaRef: manifestHints.inputSchemaRef.isEmpty ? "schema://\(skill.skillID).input" : manifestHints.inputSchemaRef,
            outputSchemaRef: manifestHints.outputSchemaRef.isEmpty ? "schema://\(skill.skillID).output" : manifestHints.outputSchemaRef,
            sideEffectClass: manifestHints.sideEffectClass,
            riskLevel: manifestHints.riskLevel,
            requiresGrant: manifestHints.requiresGrant,
            policyScope: scope,
            timeoutMs: max(1_000, manifestHints.timeoutMs),
            maxRetries: max(0, manifestHints.maxRetries),
            available: true
        )
    }

    private static func parseSupervisorSkillManifestHints(
        _ rawManifest: String,
        fallbackDescription: String,
        capabilityFallback: [String]
    ) -> SupervisorSkillManifestHints {
        let manifest = jsonObject(from: rawManifest)
        let capabilities = stringArrayValue(
            manifest["capabilities_required"],
            fallback: capabilityFallback
        )
        let explicitRisk = stringValue(manifest["risk_level"])
        let inferredRisk = normalizedRiskLevel(explicitRisk) ?? inferredRiskLevel(capabilities: capabilities)
        let explicitGrant = boolValue(manifest["requires_grant"])
        let sideEffectClass = inferredSideEffectClass(
            explicit: stringValue(manifest["side_effect_class"]),
            capabilities: capabilities,
            riskLevel: inferredRisk
        )
        return SupervisorSkillManifestHints(
            description: firstNonEmptySkillText(
                stringValue(manifest["description"]),
                fallbackDescription
            ),
            capabilitiesRequired: capabilities,
            governedDispatch: parseSupervisorGovernedDispatch(
                manifest["governed_dispatch"],
                skillId: stringValue(manifest["skill_id"])
            ) ?? fallbackGovernedDispatch(
                skillId: stringValue(manifest["skill_id"])
            ),
            inputSchemaRef: stringValue(manifest["input_schema_ref"]),
            outputSchemaRef: stringValue(manifest["output_schema_ref"]),
            sideEffectClass: sideEffectClass,
            riskLevel: inferredRisk,
            requiresGrant: explicitGrant ?? (inferredRisk == .high || inferredRisk == .critical),
            timeoutMs: intValue(manifest["timeout_ms"], fallback: 30_000),
            maxRetries: intValue(manifest["max_retries"], fallback: 1)
        )
    }

    private static func jsonObject(from raw: String) -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    private static func stringValue(_ raw: Any?) -> String {
        guard let raw else { return "" }
        if let string = raw as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(describing: raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stringArrayValue(_ raw: Any?, fallback: [String]) -> [String] {
        if let array = raw as? [String] {
            let cleaned = array
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        if let array = raw as? [Any] {
            let cleaned = array
                .map { stringValue($0) }
                .filter { !$0.isEmpty }
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return fallback
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func boolValue(_ raw: Any?) -> Bool? {
        switch raw {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes", "y", "on"].contains(normalized) {
                return true
            }
            if ["0", "false", "no", "n", "off"].contains(normalized) {
                return false
            }
            return nil
        default:
            return nil
        }
    }

    private static func intValue(_ raw: Any?, fallback: Int) -> Int {
        switch raw {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback
        default:
            return fallback
        }
    }

    private static func parseSupervisorGovernedDispatch(
        _ raw: Any?,
        skillId: String
    ) -> SupervisorGovernedSkillDispatch? {
        guard let object = raw as? [String: Any] else { return nil }
        let tool = stringValue(object["tool"])
        guard !tool.isEmpty else { return nil }
        return SupervisorGovernedSkillDispatch(
            tool: tool,
            fixedArgs: jsonObjectValue(object["fixed_args"]),
            passthroughArgs: stringArrayValue(object["passthrough_args"], fallback: []),
            argAliases: stringArrayMap(object["arg_aliases"]),
            requiredAny: stringMatrixValue(object["required_any"]),
            exactlyOneOf: stringMatrixValue(object["exactly_one_of"])
        )
    }

    private static func fallbackGovernedDispatch(skillId: String) -> SupervisorGovernedSkillDispatch? {
        switch skillId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "find-skills":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.skills_search.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["query", "source_filter", "project_id", "limit"],
                argAliases: ["source_filter": ["source"], "limit": ["max_results"]],
                requiredAny: [["query"]],
                exactlyOneOf: []
            )
        case "self-improving-agent":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.memory_snapshot.rawValue,
                fixedArgs: [
                    "mode": .string(XTMemoryUseMode.supervisorOrchestration.rawValue),
                    "retrospective": .bool(true),
                ],
                passthroughArgs: ["focus", "limit", "include_doctor", "include_incidents", "include_skill_calls", "include_plan", "include_memory"],
                argAliases: [:],
                requiredAny: [],
                exactlyOneOf: []
            )
        case "summarize", "document.summarize", "document_summarize":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.summarize.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["url", "path", "text", "focus", "format", "grant_id", "timeout_sec", "max_bytes", "max_chars"],
                argAliases: ["text": ["content", "value"]],
                requiredAny: [],
                exactlyOneOf: [["url", "path", "text"]]
            )
        default:
            return nil
        }
    }

    private static func jsonObjectValue(_ raw: Any?) -> [String: JSONValue] {
        guard let object = raw as? [String: Any] else { return [:] }
        var result: [String: JSONValue] = [:]
        for (key, value) in object {
            result[key] = jsonValue(value)
        }
        return result
    }

    private static func jsonValue(_ raw: Any?) -> JSONValue {
        switch raw {
        case let value as JSONValue:
            return value
        case let value as String:
            return .string(value)
        case let value as Bool:
            return .bool(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            return .number(value.doubleValue)
        case let value as [String: Any]:
            return .object(value.mapValues { jsonValue($0) })
        case let value as [Any]:
            return .array(value.map { jsonValue($0) })
        default:
            return .null
        }
    }

    private static func stringArrayMap(_ raw: Any?) -> [String: [String]] {
        guard let object = raw as? [String: Any] else { return [:] }
        var result: [String: [String]] = [:]
        for (key, value) in object {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty else { continue }
            let normalizedValues = stringArrayValue(value, fallback: [])
            if !normalizedValues.isEmpty {
                result[normalizedKey] = normalizedValues
            }
        }
        return result
    }

    private static func stringMatrixValue(_ raw: Any?) -> [[String]] {
        guard let rows = raw as? [Any] else { return [] }
        return rows.compactMap { row in
            let values = stringArrayValue(row, fallback: [])
            return values.isEmpty ? nil : values
        }
    }

    private static func normalizedRiskLevel(_ raw: String) -> SupervisorSkillRiskLevel? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "low":
            return .low
        case "medium", "moderate":
            return .medium
        case "high":
            return .high
        case "critical":
            return .critical
        default:
            return nil
        }
    }

    private static func inferredRiskLevel(capabilities: [String]) -> SupervisorSkillRiskLevel {
        let normalized = capabilities.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if normalized.contains(where: isHighRiskCapability) {
            return .high
        }
        if normalized.contains(where: { cap in
            cap.hasPrefix("browser.") || cap.hasPrefix("email.") || cap.hasPrefix("repo.")
        }) {
            return .medium
        }
        return .low
    }

    private static func inferredSideEffectClass(
        explicit: String,
        capabilities: [String],
        riskLevel: SupervisorSkillRiskLevel
    ) -> String {
        let explicitValue = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitValue.isEmpty {
            return explicitValue
        }
        let normalized = capabilities.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if normalized.isEmpty {
            return riskLevel == .low ? "read_only" : "external_side_effect"
        }
        if normalized.allSatisfy({
            $0.contains("status") || $0.contains("read") || $0.contains("list") || $0.contains("search")
        }) {
            return "read_only"
        }
        if normalized.contains(where: isHighRiskCapability) {
            return "external_side_effect"
        }
        if normalized.contains(where: { $0.hasPrefix("repo.") || $0.hasPrefix("filesystem.") || $0.hasPrefix("fs.") }) {
            return "project_write"
        }
        return riskLevel == .low ? "read_only" : "project_write"
    }

    private static func isHighRiskCapability(_ capability: String) -> Bool {
        let cap = capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return cap.hasPrefix("connector.")
            || cap.hasPrefix("connectors.")
            || cap.hasPrefix("web.")
            || cap.hasPrefix("network.")
            || cap == "ai.generate.paid"
            || cap == "ai.generate.remote"
            || cap.hasPrefix("payment.")
            || cap.hasPrefix("payments.")
            || cap.hasPrefix("shell.")
            || cap.hasPrefix("filesystem.")
            || cap.hasPrefix("fs.")
    }

    private static func skillPinnedScopePriority(_ scope: String) -> Int {
        switch scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "memory_core":
            return 3
        case "global":
            return 2
        case "project":
            return 1
        default:
            return 0
        }
    }

    private static func firstNonEmptySkillText(_ candidates: String...) -> String {
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private static func loadHubSkillsIndexUpdatedAtMs(url: URL) -> Int64 {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return 0
        }
        return Int64((object["updated_at_ms"] as? NSNumber)?.int64Value ?? 0)
    }
}
