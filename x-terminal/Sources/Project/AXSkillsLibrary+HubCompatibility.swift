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

struct AXSkillsDoctorSnapshot: Codable, Equatable, Sendable {
    static let empty = AXSkillsDoctorSnapshot(
        hubIndexAvailable: false,
        installedSkillCount: 0,
        openClawCompatibleCount: 0,
        partialCompatibilityCount: 0,
        revokedMatchCount: 0,
        trustEnabledPublisherCount: 0,
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
    var openClawCompatibleCount: Int
    var partialCompatibilityCount: Int
    var revokedMatchCount: Int
    var trustEnabledPublisherCount: Int
    var projectIndexEntries: [AXSkillsIndexReference]
    var globalIndexEntries: [AXSkillsIndexReference]
    var conflictWarnings: [String]
    var installedSkills: [AXHubSkillCompatibilityEntry]
    var statusKind: AXSkillsCompatibilityStatusKind
    var statusLine: String
    var compatibilityExplain: String
}

extension AXSkillsLibrary {
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

        let openClawCompatibleCount = installedSkills.filter { !$0.abiCompatVersion.isEmpty }.count
        let partialCompatibilityCount = installedSkills.filter { $0.compatibilityState == .partial }.count
        let revokedMatchCount = installedSkills.filter(\.revoked).count
        let projectIndexEntries = loadProjectIndexEntries(skillsDir: resolvedSkillsDir, projectId: projectId, projectName: projectName)
        let globalIndexEntries = loadGlobalIndexEntries(skillsDir: resolvedSkillsDir)
        let conflictWarnings = compatibilityConflicts(for: relevantPins)
        let statusKind: AXSkillsCompatibilityStatusKind
        if !hubIndex.available {
            statusKind = .unavailable
        } else if revokedMatchCount > 0 {
            statusKind = .blocked
        } else if partialCompatibilityCount > 0 {
            statusKind = .partial
        } else {
            statusKind = .supported
        }

        let statusLine: String
        switch statusKind {
        case .unavailable:
            statusLine = "skills?"
        case .blocked:
            statusLine = "skills! \(openClawCompatibleCount)/\(installedSkills.count)"
        case .partial:
            statusLine = "skills~ \(openClawCompatibleCount)/\(installedSkills.count)"
        case .supported:
            statusLine = "skills \(openClawCompatibleCount)/\(installedSkills.count)"
        }

        let explain = renderCompatibilityExplainability(
            statusKind: statusKind,
            installedSkills: installedSkills,
            trustedPublisherCount: trusted.publishers.filter(\.enabled).count,
            projectIndexEntries: projectIndexEntries,
            globalIndexEntries: globalIndexEntries,
            conflictWarnings: conflictWarnings
        )

        return AXSkillsDoctorSnapshot(
            hubIndexAvailable: hubIndex.available,
            installedSkillCount: installedSkills.count,
            openClawCompatibleCount: openClawCompatibleCount,
            partialCompatibilityCount: partialCompatibilityCount,
            revokedMatchCount: revokedMatchCount,
            trustEnabledPublisherCount: trusted.publishers.filter(\.enabled).count,
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
            var publisherID: String
            var sourceID: String
            var packageSHA256: String
            var abiCompatVersion: String
            var compatibilityState: AXSkillCompatibilityState
            var canonicalManifestSHA256: String
            var installHint: String
            var mappingAliasesUsed: [String]
            var defaultsApplied: [String]

            enum CodingKeys: String, CodingKey {
                case skillID = "skill_id"
                case name
                case version
                case publisherID = "publisher_id"
                case sourceID = "source_id"
                case packageSHA256 = "package_sha256"
                case abiCompatVersion = "abi_compat_version"
                case compatibilityState = "compatibility_state"
                case canonicalManifestSHA256 = "canonical_manifest_sha256"
                case installHint = "install_hint"
                case mappingAliasesUsed = "mapping_aliases_used"
                case defaultsApplied = "defaults_applied"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                skillID = (try? container.decode(String.self, forKey: .skillID)) ?? ""
                name = (try? container.decode(String.self, forKey: .name)) ?? skillID
                version = (try? container.decode(String.self, forKey: .version)) ?? ""
                publisherID = (try? container.decode(String.self, forKey: .publisherID)) ?? ""
                sourceID = (try? container.decode(String.self, forKey: .sourceID)) ?? ""
                packageSHA256 = ((try? container.decode(String.self, forKey: .packageSHA256)) ?? "").lowercased()
                abiCompatVersion = (try? container.decode(String.self, forKey: .abiCompatVersion)) ?? ""
                compatibilityState = (try? container.decode(AXSkillCompatibilityState.self, forKey: .compatibilityState)) ?? .unknown
                canonicalManifestSHA256 = ((try? container.decode(String.self, forKey: .canonicalManifestSHA256)) ?? "").lowercased()
                installHint = (try? container.decode(String.self, forKey: .installHint)) ?? ""
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
        trustedPublisherCount: Int,
        projectIndexEntries: [AXSkillsIndexReference],
        globalIndexEntries: [AXSkillsIndexReference],
        conflictWarnings: [String]
    ) -> String {
        var lines: [String] = []
        switch statusKind {
        case .unavailable:
            lines.append("skills compatibility unavailable: hub skills_store_index.json not found")
        case .blocked:
            lines.append("OpenClaw compatible skill installed, but revocation or trust blockers remain visible")
        case .partial:
            lines.append("OpenClaw compatible skill installed with alias/default compatibility mapping")
        case .supported:
            lines.append("OpenClaw compatible skill installed under Hub canonical manifest gates")
        }
        lines.append("installed=\(installedSkills.count) trusted_publishers=\(trustedPublisherCount) project_index=\(projectIndexEntries.count) global_index=\(globalIndexEntries.count)")

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
}
