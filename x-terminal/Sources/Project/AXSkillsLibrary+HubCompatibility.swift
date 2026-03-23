import Foundation
import CryptoKit

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

struct AXBuiltinGovernedSkillSummary: Identifiable, Codable, Equatable, Sendable {
    var skillID: String
    var displayName: String
    var summary: String
    var capabilitiesRequired: [String]
    var sideEffectClass: String
    var riskLevel: String
    var policyScope: String

    var id: String { skillID }

    enum CodingKeys: String, CodingKey {
        case skillID = "skill_id"
        case displayName = "display_name"
        case summary
        case capabilitiesRequired = "capabilities_required"
        case sideEffectClass = "side_effect_class"
        case riskLevel = "risk_level"
        case policyScope = "policy_scope"
    }
}

struct AXOfficialSkillPackageLifecycleEntry: Identifiable, Codable, Equatable, Sendable {
    var packageSHA256: String
    var skillID: String
    var name: String
    var version: String
    var riskLevel: String
    var requiresGrant: Bool
    var packageState: String
    var overallState: String
    var blockingFailures: Int
    var transitionCount: Int
    var updatedAtMs: Int64
    var lastTransitionAtMs: Int64
    var lastReadyAtMs: Int64
    var lastBlockedAtMs: Int64

    var id: String { packageSHA256 }

    enum CodingKeys: String, CodingKey {
        case packageSHA256 = "package_sha256"
        case skillID = "skill_id"
        case name
        case version
        case riskLevel = "risk_level"
        case requiresGrant = "requires_grant"
        case packageState = "package_state"
        case overallState = "overall_state"
        case blockingFailures = "blocking_failures"
        case transitionCount = "transition_count"
        case updatedAtMs = "updated_at_ms"
        case lastTransitionAtMs = "last_transition_at_ms"
        case lastReadyAtMs = "last_ready_at_ms"
        case lastBlockedAtMs = "last_blocked_at_ms"
    }

    init(
        packageSHA256: String,
        skillID: String,
        name: String,
        version: String,
        riskLevel: String,
        requiresGrant: Bool,
        packageState: String,
        overallState: String,
        blockingFailures: Int,
        transitionCount: Int,
        updatedAtMs: Int64,
        lastTransitionAtMs: Int64,
        lastReadyAtMs: Int64,
        lastBlockedAtMs: Int64
    ) {
        self.packageSHA256 = packageSHA256
        self.skillID = skillID
        self.name = name
        self.version = version
        self.riskLevel = riskLevel
        self.requiresGrant = requiresGrant
        self.packageState = packageState
        self.overallState = overallState
        self.blockingFailures = blockingFailures
        self.transitionCount = transitionCount
        self.updatedAtMs = updatedAtMs
        self.lastTransitionAtMs = lastTransitionAtMs
        self.lastReadyAtMs = lastReadyAtMs
        self.lastBlockedAtMs = lastBlockedAtMs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packageSHA256 = ((try? container.decode(String.self, forKey: .packageSHA256)) ?? "").lowercased()
        skillID = (try? container.decode(String.self, forKey: .skillID)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? skillID
        version = (try? container.decode(String.self, forKey: .version)) ?? ""
        riskLevel = (try? container.decode(String.self, forKey: .riskLevel)) ?? ""
        requiresGrant = (try? container.decode(Bool.self, forKey: .requiresGrant)) ?? false
        packageState = (try? container.decode(String.self, forKey: .packageState)) ?? ""
        overallState = (try? container.decode(String.self, forKey: .overallState)) ?? ""
        blockingFailures = max(0, (try? container.decode(Int.self, forKey: .blockingFailures)) ?? 0)
        transitionCount = max(0, (try? container.decode(Int.self, forKey: .transitionCount)) ?? 0)
        updatedAtMs = max(0, (try? container.decode(Int64.self, forKey: .updatedAtMs)) ?? 0)
        lastTransitionAtMs = max(0, (try? container.decode(Int64.self, forKey: .lastTransitionAtMs)) ?? 0)
        lastReadyAtMs = max(0, (try? container.decode(Int64.self, forKey: .lastReadyAtMs)) ?? 0)
        lastBlockedAtMs = max(0, (try? container.decode(Int64.self, forKey: .lastBlockedAtMs)) ?? 0)
    }
}

struct AXOfficialSkillBlockerSummaryItem: Identifiable, Equatable, Sendable {
    var packageSHA256: String
    var title: String
    var subtitle: String
    var stateLabel: String
    var summaryLine: String
    var timelineLine: String

    var id: String { packageSHA256 }
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
    var builtinGovernedSkills: [AXBuiltinGovernedSkillSummary] = []
    var projectIndexEntries: [AXSkillsIndexReference]
    var globalIndexEntries: [AXSkillsIndexReference]
    var conflictWarnings: [String]
    var installedSkills: [AXHubSkillCompatibilityEntry]
    var statusKind: AXSkillsCompatibilityStatusKind
    var statusLine: String
    var compatibilityExplain: String
    var officialChannelID: String = ""
    var officialChannelStatus: String = ""
    var officialChannelUpdatedAtMs: Int64 = 0
    var officialChannelLastSuccessAtMs: Int64 = 0
    var officialChannelSkillCount: Int = 0
    var officialChannelErrorCode: String = ""
    var officialChannelMaintenanceEnabled: Bool = false
    var officialChannelMaintenanceIntervalMs: Int64 = 0
    var officialChannelMaintenanceLastRunAtMs: Int64 = 0
    var officialChannelMaintenanceSourceKind: String = ""
    var officialChannelLastTransitionAtMs: Int64 = 0
    var officialChannelLastTransitionKind: String = ""
    var officialChannelLastTransitionSummary: String = ""
    var officialPackageLifecycleSchemaVersion: String = ""
    var officialPackageLifecycleUpdatedAtMs: Int64 = 0
    var officialPackageLifecyclePackagesTotal: Int = 0
    var officialPackageLifecycleReadyTotal: Int = 0
    var officialPackageLifecycleDegradedTotal: Int = 0
    var officialPackageLifecycleBlockedTotal: Int = 0
    var officialPackageLifecycleNotInstalledTotal: Int = 0
    var officialPackageLifecycleNotSupportedTotal: Int = 0
    var officialPackageLifecycleRevokedTotal: Int = 0
    var officialPackageLifecycleActiveTotal: Int = 0
    var officialPackageLifecyclePackages: [AXOfficialSkillPackageLifecycleEntry] = []

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

    var builtinGovernedSkillCount: Int {
        builtinGovernedSkills.count
    }

    var builtinGovernedSkillIDs: [String] {
        builtinGovernedSkills.map(\.skillID).sorted()
    }

    var builtinSupervisorVoiceAvailable: Bool {
        builtinGovernedSkillIDs.contains("supervisor-voice")
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

    private var officialPackageLifecycleProblemPackages: [AXOfficialSkillPackageLifecycleEntry] {
        officialPackageLifecyclePackages.filter { item in
            let overall = item.overallState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let packageState = item.packageState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return overall == "blocked"
                || overall == "degraded"
                || overall == "not_installed"
                || overall == "not_supported"
                || packageState == "revoked"
        }
    }

    private var rankedOfficialPackageLifecycleProblemPackages: [AXOfficialSkillPackageLifecycleEntry] {
        officialPackageLifecycleProblemPackages.sorted { lhs, rhs in
            let leftSeverity = officialPackageLifecycleProblemSeverity(lhs)
            let rightSeverity = officialPackageLifecycleProblemSeverity(rhs)
            if leftSeverity != rightSeverity {
                return leftSeverity < rightSeverity
            }

            let leftFailures = max(0, lhs.blockingFailures)
            let rightFailures = max(0, rhs.blockingFailures)
            if leftFailures != rightFailures {
                return leftFailures > rightFailures
            }

            let leftRisk = officialPackageLifecycleProblemRiskPriority(lhs)
            let rightRisk = officialPackageLifecycleProblemRiskPriority(rhs)
            if leftRisk != rightRisk {
                return leftRisk > rightRisk
            }

            let leftRecency = officialPackageLifecycleProblemRecency(lhs)
            let rightRecency = officialPackageLifecycleProblemRecency(rhs)
            if leftRecency != rightRecency {
                return leftRecency > rightRecency
            }

            let leftSkillID = lhs.skillID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rightSkillID = rhs.skillID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if leftSkillID != rightSkillID {
                return leftSkillID < rightSkillID
            }

            return lhs.packageSHA256 < rhs.packageSHA256
        }
    }

    private func officialPackageLifecycleProblemSeverity(
        _ item: AXOfficialSkillPackageLifecycleEntry
    ) -> Int {
        let packageState = item.packageState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if packageState == "revoked" {
            return 1
        }

        let overall = item.overallState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if (overall == "blocked" || overall == "degraded"), item.requiresGrant {
            return 0
        }

        switch overall {
        case "blocked":
            return 2
        case "not_supported":
            return 3
        case "not_installed":
            return 4
        case "degraded":
            return 5
        default:
            return 6
        }
    }

    private func officialPackageLifecycleProblemRiskPriority(
        _ item: AXOfficialSkillPackageLifecycleEntry
    ) -> Int {
        switch item.riskLevel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "critical":
            return 4
        case "high":
            return 3
        case "medium":
            return 2
        case "low":
            return 1
        default:
            return 0
        }
    }

    private func officialPackageLifecycleProblemRecency(
        _ item: AXOfficialSkillPackageLifecycleEntry
    ) -> Int64 {
        max(max(item.lastBlockedAtMs, item.lastTransitionAtMs), item.updatedAtMs)
    }

    private func officialPackageLifecycleProblemStateLabel(
        _ item: AXOfficialSkillPackageLifecycleEntry
    ) -> String {
        let packageState = item.packageState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if packageState == "revoked" {
            return "revoked"
        }

        let overall = item.overallState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if overall.isEmpty {
            return "unknown"
        }
        return overall.replacingOccurrences(of: "_", with: " ")
    }

    private func officialPackageLifecycleProblemDisplayLabel(
        _ item: AXOfficialSkillPackageLifecycleEntry
    ) -> String {
        let name = officialPackageLifecycleDisplayTitle(item)
        let skillID = officialPackageLifecycleDisplaySubtitle(item)
        let state = officialPackageLifecycleProblemStateLabel(item)

        let subject: String
        if !name.isEmpty, !skillID.isEmpty {
            subject = "\(name) (\(skillID))"
        } else if !name.isEmpty {
            subject = name
        } else if !skillID.isEmpty {
            subject = skillID
        } else {
            subject = item.packageSHA256
        }

        return "\(subject) [\(state)]"
    }

    private func officialPackageLifecycleDisplayTitle(
        _ item: AXOfficialSkillPackageLifecycleEntry
    ) -> String {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }

        let skillID = item.skillID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !skillID.isEmpty {
            return skillID
        }

        return item.packageSHA256
    }

    private func officialPackageLifecycleDisplaySubtitle(
        _ item: AXOfficialSkillPackageLifecycleEntry
    ) -> String {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let skillID = item.skillID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !skillID.isEmpty else { return "" }
        guard name.caseInsensitiveCompare(skillID) != .orderedSame else { return "" }
        return skillID
    }

    private func officialPackageLifecycleProblemSummaryLine(
        _ item: AXOfficialSkillPackageLifecycleEntry
    ) -> String {
        var parts: [String] = []

        let version = item.version.trimmingCharacters(in: .whitespacesAndNewlines)
        if !version.isEmpty {
            parts.append("version=\(version)")
        }

        let packageState = item.packageState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !packageState.isEmpty {
            parts.append("package=\(packageState)")
        }

        let risk = item.riskLevel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !risk.isEmpty {
            parts.append("risk=\(risk)")
        }

        parts.append("grant=\(item.requiresGrant ? "required" : "none")")

        if item.blockingFailures > 0 {
            parts.append("failures=\(item.blockingFailures)")
        }
        if item.transitionCount > 0 {
            parts.append("transitions=\(item.transitionCount)")
        }

        return parts.joined(separator: " ")
    }

    private func officialPackageLifecycleProblemTimelineLine(
        _ item: AXOfficialSkillPackageLifecycleEntry
    ) -> String {
        let formatter = ISO8601DateFormatter()
        var parts: [String] = []

        if item.lastBlockedAtMs > 0 {
            let iso = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(item.lastBlockedAtMs) / 1000.0))
            parts.append("last_blocked=\(iso)")
        }

        if item.lastTransitionAtMs > 0 {
            let iso = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(item.lastTransitionAtMs) / 1000.0))
            parts.append("last_transition=\(iso)")
        }

        if item.updatedAtMs > 0 {
            let iso = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(item.updatedAtMs) / 1000.0))
            parts.append("updated=\(iso)")
        }

        return parts.joined(separator: " ")
    }

    var officialPackageLifecycleProblemSkillIDs: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in rankedOfficialPackageLifecycleProblemPackages {
            let skillID = item.skillID.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = skillID.lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            out.append(skillID)
            if out.count >= 4 {
                break
            }
        }
        return out
    }

    var officialPackageLifecycleTopBlockerLabels: [String] {
        rankedOfficialPackageLifecycleProblemPackages
            .prefix(3)
            .map { officialPackageLifecycleProblemDisplayLabel($0) }
    }

    var officialPackageLifecycleTopBlockerSummaries: [AXOfficialSkillBlockerSummaryItem] {
        rankedOfficialPackageLifecycleProblemPackages
            .prefix(5)
            .map { item in
                AXOfficialSkillBlockerSummaryItem(
                    packageSHA256: item.packageSHA256,
                    title: officialPackageLifecycleDisplayTitle(item),
                    subtitle: officialPackageLifecycleDisplaySubtitle(item),
                    stateLabel: officialPackageLifecycleProblemStateLabel(item),
                    summaryLine: officialPackageLifecycleProblemSummaryLine(item),
                    timelineLine: officialPackageLifecycleProblemTimelineLine(item)
                )
            }
    }

    var officialChannelTopBlockersLine: String {
        let labels = officialPackageLifecycleTopBlockerLabels
        guard !labels.isEmpty else { return "" }

        var line = "Top blockers: \(labels.joined(separator: "; "))"
        let remainingCount = max(0, rankedOfficialPackageLifecycleProblemPackages.count - labels.count)
        if remainingCount > 0 {
            line += " +\(remainingCount) more"
        }
        return line
    }

    var officialPackageLifecycleRollupLine: String {
        let packagesTotal = max(0, officialPackageLifecyclePackagesTotal)
        guard packagesTotal > 0 else { return "" }

        var parts = ["pkg=\(packagesTotal)"]
        if officialPackageLifecycleReadyTotal > 0 {
            parts.append("ready=\(max(0, officialPackageLifecycleReadyTotal))")
        }
        if officialPackageLifecycleDegradedTotal > 0 {
            parts.append("degraded=\(max(0, officialPackageLifecycleDegradedTotal))")
        }
        if officialPackageLifecycleBlockedTotal > 0 {
            parts.append("blocked=\(max(0, officialPackageLifecycleBlockedTotal))")
        }
        if officialPackageLifecycleNotInstalledTotal > 0 {
            parts.append("not_installed=\(max(0, officialPackageLifecycleNotInstalledTotal))")
        }
        if officialPackageLifecycleNotSupportedTotal > 0 {
            parts.append("not_supported=\(max(0, officialPackageLifecycleNotSupportedTotal))")
        }
        if officialPackageLifecycleRevokedTotal > 0 {
            parts.append("revoked=\(max(0, officialPackageLifecycleRevokedTotal))")
        }
        if officialPackageLifecycleActiveTotal > 0 {
            parts.append("active=\(max(0, officialPackageLifecycleActiveTotal))")
        }
        return parts.joined(separator: " ")
    }

    var officialChannelSummaryLine: String {
        let status = officialChannelStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        let lifecycle = officialPackageLifecycleRollupLine

        guard !status.isEmpty else { return lifecycle }

        let count = max(0, officialChannelSkillCount)
        let autoSuffix: String
        if officialChannelMaintenanceEnabled {
            let sourceKind = officialChannelMaintenanceSourceKind.trimmingCharacters(in: .whitespacesAndNewlines)
            autoSuffix = sourceKind.isEmpty ? " auto=on" : " auto=\(sourceKind)"
        } else {
            autoSuffix = ""
        }

        var base = "official \(status) skills=\(count)\(autoSuffix)"
        if !lifecycle.isEmpty {
            base += " \(lifecycle)"
        }

        let error = officialChannelErrorCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !error.isEmpty, status == "failed" || status == "missing" else { return base }
        return "\(base) err=\(error)"
    }

    var officialChannelDetailLine: String {
        let formatter = ISO8601DateFormatter()
        var parts: [String] = []

        let lastSuccessAtMs = max(0, officialChannelLastSuccessAtMs)
        if lastSuccessAtMs > 0 {
            let iso = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(lastSuccessAtMs) / 1000.0))
            parts.append("last_success=\(iso)")
        }

        let maintenanceLastRunAtMs = max(0, officialChannelMaintenanceLastRunAtMs)
        if maintenanceLastRunAtMs > 0 {
            let iso = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(maintenanceLastRunAtMs) / 1000.0))
            parts.append("last_run=\(iso)")
        }

        let maintenanceIntervalMs = max(0, officialChannelMaintenanceIntervalMs)
        if maintenanceIntervalMs > 0 {
            parts.append("every=\(max(1, maintenanceIntervalMs / 1000))s")
        }

        let lifecycle = officialPackageLifecycleRollupLine
        if !lifecycle.isEmpty {
            parts.append(lifecycle)
        }

        let lifecycleUpdatedAtMs = max(0, officialPackageLifecycleUpdatedAtMs)
        if lifecycleUpdatedAtMs > 0 {
            let iso = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(lifecycleUpdatedAtMs) / 1000.0))
            parts.append("pkg_updated=\(iso)")
        }

        let problemSkills = officialPackageLifecycleProblemSkillIDs
        if !problemSkills.isEmpty {
            parts.append("problem_skills=\(problemSkills.joined(separator: ","))")
        }

        let topBlockers = officialChannelTopBlockersLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !topBlockers.isEmpty {
            parts.append(topBlockers)
        }

        let transitionSummary = officialChannelLastTransitionSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transitionSummary.isEmpty {
            parts.append("transition=\(transitionSummary)")
        }

        return parts.joined(separator: " ")
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

    static func canonicalSupervisorSkillID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        switch trimmed.lowercased() {
        case "supervisor-voice", "supervisor.voice", "supervisor_voice":
            return "supervisor-voice"
        case "guarded-automation", "guarded.automation", "guarded_automation", "trusted-automation", "trusted_automation":
            return "guarded-automation"
        default:
            return trimmed
        }
    }

    private static let nativeSupervisorSkillSpecs: [(String, String, String, [String], SupervisorGovernedSkillDispatch, String, SupervisorSkillRiskLevel, Int, Int)] = [
        (
            "repo.delete.path",
            "Repo Delete Path",
            "Delete a governed file or directory within the project root.",
            ["repo.delete_move"],
            SupervisorGovernedSkillDispatch(
                tool: ToolName.delete_path.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["path", "recursive", "force"],
                argAliases: ["path": ["target"]],
                requiredAny: [["path"]],
                exactlyOneOf: []
            ),
            "repo_mutation",
            .medium,
            10_000,
            0
        ),
        (
            "repo.move.path",
            "Repo Move Path",
            "Move or rename a governed file or directory within the project root.",
            ["repo.delete_move"],
            SupervisorGovernedSkillDispatch(
                tool: ToolName.move_path.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["from", "to", "overwrite", "create_dirs"],
                argAliases: [
                    "from": ["source", "src"],
                    "to": ["destination", "dest", "new_path"],
                ],
                requiredAny: [["from"], ["to"]],
                exactlyOneOf: []
            ),
            "repo_mutation",
            .medium,
            10_000,
            0
        ),
        (
            "process.start",
            "Process Start",
            "Start a governed managed process inside the project root.",
            ["process.manage", "process.autorestart"],
            SupervisorGovernedSkillDispatch(
                tool: ToolName.process_start.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["command", "name", "process_id", "cwd", "env", "restart_on_exit"],
                argAliases: ["process_id": ["id"]],
                requiredAny: [["command"]],
                exactlyOneOf: []
            ),
            "managed_process_mutation",
            .medium,
            15_000,
            0
        ),
        (
            "process.status",
            "Process Status",
            "Read the state of managed processes for the project.",
            ["process.manage"],
            SupervisorGovernedSkillDispatch(
                tool: ToolName.process_status.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["process_id", "include_exited"],
                argAliases: ["process_id": ["id"]],
                requiredAny: [],
                exactlyOneOf: []
            ),
            "read_only",
            .low,
            8_000,
            0
        ),
        (
            "process.logs",
            "Process Logs",
            "Read recent logs from a managed process.",
            ["process.manage"],
            SupervisorGovernedSkillDispatch(
                tool: ToolName.process_logs.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["process_id", "tail_lines", "max_bytes"],
                argAliases: ["process_id": ["id"]],
                requiredAny: [["process_id"]],
                exactlyOneOf: []
            ),
            "read_only",
            .low,
            8_000,
            0
        ),
        (
            "process.stop",
            "Process Stop",
            "Stop a governed managed process.",
            ["process.manage"],
            SupervisorGovernedSkillDispatch(
                tool: ToolName.process_stop.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["process_id", "force"],
                argAliases: ["process_id": ["id"]],
                requiredAny: [["process_id"]],
                exactlyOneOf: []
            ),
            "managed_process_mutation",
            .medium,
            10_000,
            0
        ),
        (
            "supervisor-voice",
            "Supervisor Voice",
            "Inspect, preview, speak, or stop the Supervisor playback path using the current XT voice settings.",
            ["supervisor.voice.playback"],
            SupervisorGovernedSkillDispatch(
                tool: ToolName.supervisorVoicePlayback.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["action", "text"],
                argAliases: [
                    "action": ["mode", "operation"],
                    "text": ["content", "value"],
                ],
                requiredAny: [],
                exactlyOneOf: []
            ),
            "local_side_effect",
            .low,
            12_000,
            0
        ),
        (
            "guarded-automation",
            "Guarded Automation",
            "Inspect trusted automation readiness and, when explicitly requested, route governed browser automation through the same XT runtime gates.",
            ["project.snapshot", "browser.read", "device.browser.control"],
            SupervisorGovernedSkillDispatch(
                tool: ToolName.project_snapshot.rawValue,
                fixedArgs: [:],
                passthroughArgs: [],
                argAliases: [:],
                requiredAny: [],
                exactlyOneOf: []
            ),
            "external_side_effect",
            .high,
            45_000,
            1
        ),
        (
            "repo.git.commit",
            "Git Commit",
            "Create a governed git commit in the active repository.",
            ["git.commit"],
            SupervisorGovernedSkillDispatch(
                tool: ToolName.git_commit.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["message", "all", "allow_empty", "paths"],
                argAliases: [:],
                requiredAny: [["message"]],
                exactlyOneOf: []
            ),
            "repo_mutation",
            .medium,
            20_000,
            0
        ),
        (
            "repo.git.push",
            "Git Push",
            "Push governed git changes to a configured remote.",
            ["git.push"],
            SupervisorGovernedSkillDispatch(
                tool: ToolName.git_push.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["remote", "branch", "set_upstream"],
                argAliases: [:],
                requiredAny: [],
                exactlyOneOf: []
            ),
            "remote_side_effect",
            .high,
            60_000,
            0
        ),
        (
            "repo.pr.create",
            "PR Create",
            "Create a governed pull request via GitHub CLI.",
            ["pr.create"],
            SupervisorGovernedSkillDispatch(
                tool: ToolName.pr_create.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["title", "body", "base", "head", "draft", "fill", "labels", "reviewers"],
                argAliases: [:],
                requiredAny: [],
                exactlyOneOf: []
            ),
            "remote_side_effect",
            .high,
            60_000,
            0
        ),
        (
            "repo.ci.read",
            "CI Read",
            "Read recent CI workflow runs via GitHub CLI.",
            ["ci.read"],
            SupervisorGovernedSkillDispatch(
                tool: ToolName.ci_read.rawValue,
                fixedArgs: ["provider": .string("github")],
                passthroughArgs: ["workflow", "branch", "commit", "limit"],
                argAliases: [:],
                requiredAny: [],
                exactlyOneOf: []
            ),
            "read_only",
            .low,
            30_000,
            0
        ),
        (
            "repo.ci.trigger",
            "CI Trigger",
            "Trigger a CI workflow via GitHub CLI.",
            ["ci.trigger"],
            SupervisorGovernedSkillDispatch(
                tool: ToolName.ci_trigger.rawValue,
                fixedArgs: ["provider": .string("github")],
                passthroughArgs: ["workflow", "ref", "inputs"],
                argAliases: [:],
                requiredAny: [["workflow"]],
                exactlyOneOf: []
            ),
            "remote_side_effect",
            .high,
            30_000,
            0
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
        let officialChannelDir = storeDir
            .appendingPathComponent("official_channels", isDirectory: true)
            .appendingPathComponent("official-stable", isDirectory: true)
        let officialChannelStateURL = officialChannelDir.appendingPathComponent("channel_state.json")
        let officialChannelMaintenanceURL = officialChannelDir.appendingPathComponent("maintenance_status.json")
        let officialPackageLifecycleURL = storeDir.appendingPathComponent("official_skill_package_lifecycle.json")

        let hubIndex = loadHubSkillsIndex(url: indexURL)
        let pins = loadHubSkillsPins(url: pinsURL)
        let trusted = loadTrustedPublishers(url: trustedPublishersURL)
        let revocations = loadSkillRevocations(url: revocationsURL)
        let officialChannelState = loadOfficialSkillChannelState(baseURL: officialChannelDir, stateURL: officialChannelStateURL)
        let officialChannelMaintenance = loadOfficialSkillChannelMaintenanceStatus(url: officialChannelMaintenanceURL)
        let officialPackageLifecycle = loadOfficialSkillPackageLifecycle(url: officialPackageLifecycleURL)
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
        let builtinGovernedSkills = nativeBuiltinGovernedSkillSummaries()
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
            builtinGovernedSkills: builtinGovernedSkills,
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
            builtinGovernedSkills: builtinGovernedSkills,
            trustedPublisherCount: trusted.publishers.filter(\.enabled).count,
            projectIndexEntries: projectIndexEntries,
            globalIndexEntries: globalIndexEntries,
            conflictWarnings: conflictWarnings,
            activePublisherIDs: draftSnapshot.activePublisherIDs,
            activeSourceIDs: draftSnapshot.activeSourceIDs,
            localDevPublisherActive: draftSnapshot.localDevPublisherActive,
            baselinePublisherIDs: draftSnapshot.baselinePublisherIDs,
            baselineLocalDevSkillCount: draftSnapshot.baselineLocalDevSkillCount,
            officialChannelSummaryLine: draftSnapshot.officialChannelSummaryLine,
            officialChannelDetailLine: draftSnapshot.officialChannelDetailLine
        )

        var snapshot = AXSkillsDoctorSnapshot(
            hubIndexAvailable: hubIndex.available,
            installedSkillCount: installedSkills.count,
            compatibleSkillCount: compatibleSkillCount,
            partialCompatibilityCount: partialCompatibilityCount,
            revokedMatchCount: revokedMatchCount,
            trustEnabledPublisherCount: trusted.publishers.filter(\.enabled).count,
            baselineRecommendedSkills: defaultAgentBaselineSkills,
            missingBaselineSkillIDs: missingBaselineSkillIDs,
            builtinGovernedSkills: builtinGovernedSkills,
            projectIndexEntries: projectIndexEntries,
            globalIndexEntries: globalIndexEntries,
            conflictWarnings: conflictWarnings,
            installedSkills: installedSkills,
            statusKind: statusKind,
            statusLine: statusLine,
            compatibilityExplain: explain
        )
        snapshot.officialChannelID = officialChannelState.channelID
        snapshot.officialChannelStatus = officialChannelState.status
        snapshot.officialChannelUpdatedAtMs = officialChannelState.updatedAtMs
        snapshot.officialChannelLastSuccessAtMs = officialChannelState.lastSuccessAtMs
        snapshot.officialChannelSkillCount = officialChannelState.skillCount
        snapshot.officialChannelErrorCode = officialChannelState.errorCode
        snapshot.officialChannelMaintenanceEnabled = officialChannelMaintenance.maintenanceEnabled
        snapshot.officialChannelMaintenanceIntervalMs = officialChannelMaintenance.maintenanceIntervalMs
        snapshot.officialChannelMaintenanceLastRunAtMs = officialChannelMaintenance.maintenanceLastRunAtMs
        snapshot.officialChannelMaintenanceSourceKind = officialChannelMaintenance.maintenanceSourceKind
        snapshot.officialChannelLastTransitionAtMs = officialChannelMaintenance.lastTransitionAtMs
        snapshot.officialChannelLastTransitionKind = officialChannelMaintenance.lastTransitionKind
        snapshot.officialChannelLastTransitionSummary = officialChannelMaintenance.lastTransitionSummary
        snapshot.officialPackageLifecycleSchemaVersion = officialPackageLifecycle.schemaVersion
        snapshot.officialPackageLifecycleUpdatedAtMs = officialPackageLifecycle.updatedAtMs
        snapshot.officialPackageLifecyclePackagesTotal = officialPackageLifecycle.packagesTotal
        snapshot.officialPackageLifecycleReadyTotal = officialPackageLifecycle.readyTotal
        snapshot.officialPackageLifecycleDegradedTotal = officialPackageLifecycle.degradedTotal
        snapshot.officialPackageLifecycleBlockedTotal = officialPackageLifecycle.blockedTotal
        snapshot.officialPackageLifecycleNotInstalledTotal = officialPackageLifecycle.notInstalledTotal
        snapshot.officialPackageLifecycleNotSupportedTotal = officialPackageLifecycle.notSupportedTotal
        snapshot.officialPackageLifecycleRevokedTotal = officialPackageLifecycle.revokedTotal
        snapshot.officialPackageLifecycleActiveTotal = officialPackageLifecycle.activeTotal
        snapshot.officialPackageLifecyclePackages = officialPackageLifecycle.packages
        snapshot.compatibilityExplain = renderCompatibilityExplainability(
            statusKind: statusKind,
            installedSkills: installedSkills,
            baselineRecommendedSkills: defaultAgentBaselineSkills,
            missingBaselineSkillIDs: missingBaselineSkillIDs,
            builtinGovernedSkills: builtinGovernedSkills,
            trustedPublisherCount: trusted.publishers.filter(\.enabled).count,
            projectIndexEntries: projectIndexEntries,
            globalIndexEntries: globalIndexEntries,
            conflictWarnings: conflictWarnings,
            activePublisherIDs: snapshot.activePublisherIDs,
            activeSourceIDs: snapshot.activeSourceIDs,
            localDevPublisherActive: snapshot.localDevPublisherActive,
            baselinePublisherIDs: snapshot.baselinePublisherIDs,
            baselineLocalDevSkillCount: snapshot.baselineLocalDevSkillCount,
            officialChannelSummaryLine: snapshot.officialChannelSummaryLine,
            officialChannelDetailLine: snapshot.officialChannelDetailLine
        )
        return snapshot
    }

    private struct HubSkillsIndexSnapshot: Decodable {
        struct Skill: Decodable {
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

    private struct HubSkillsPinsSnapshot: Decodable {
        init(memoryCorePins: [Pin], globalPins: [Pin], projectPins: [Pin]) {
            self.memoryCorePins = memoryCorePins
            self.globalPins = globalPins
            self.projectPins = projectPins
        }
        struct Pin: Decodable {
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

    private struct TrustedPublishersSnapshot: Decodable {
        struct Publisher: Decodable {
            var publisherID: String
            var enabled: Bool

            enum CodingKeys: String, CodingKey {
                case publisherID = "publisher_id"
                case enabled
            }
        }

        var publishers: [Publisher]
    }

    private struct SkillRevocationsSnapshot: Decodable {
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

    private struct OfficialSkillChannelStateSnapshot: Decodable {
        var channelID: String
        var status: String
        var updatedAtMs: Int64
        var lastSuccessAtMs: Int64
        var skillCount: Int
        var errorCode: String

        enum CodingKeys: String, CodingKey {
            case channelID = "channel_id"
            case status
            case updatedAtMs = "updated_at_ms"
            case lastSuccessAtMs = "last_success_at_ms"
            case skillCount = "skill_count"
            case errorCode = "error_code"
        }
    }

    private struct OfficialSkillChannelMaintenanceSnapshot: Decodable {
        var maintenanceEnabled: Bool
        var maintenanceIntervalMs: Int64
        var maintenanceLastRunAtMs: Int64
        var maintenanceSourceKind: String
        var lastTransitionAtMs: Int64
        var lastTransitionKind: String
        var lastTransitionSummary: String

        enum CodingKeys: String, CodingKey {
            case maintenanceEnabled = "maintenance_enabled"
            case maintenanceIntervalMs = "maintenance_interval_ms"
            case maintenanceLastRunAtMs = "maintenance_last_run_at_ms"
            case maintenanceSourceKind = "maintenance_source_kind"
            case lastTransitionAtMs = "last_transition_at_ms"
            case lastTransitionKind = "last_transition_kind"
            case lastTransitionSummary = "last_transition_summary"
        }
    }

    private struct OfficialSkillPackageLifecycleSnapshot: Decodable {
        struct Totals: Decodable {
            var packagesTotal: Int
            var readyTotal: Int
            var degradedTotal: Int
            var blockedTotal: Int
            var notInstalledTotal: Int
            var notSupportedTotal: Int
            var revokedTotal: Int
            var activeTotal: Int

            enum CodingKeys: String, CodingKey {
                case packagesTotal = "packages_total"
                case readyTotal = "ready_total"
                case degradedTotal = "degraded_total"
                case blockedTotal = "blocked_total"
                case notInstalledTotal = "not_installed_total"
                case notSupportedTotal = "not_supported_total"
                case revokedTotal = "revoked_total"
                case activeTotal = "active_total"
            }
        }

        var schemaVersion: String
        var updatedAtMs: Int64
        var packagesTotal: Int
        var readyTotal: Int
        var degradedTotal: Int
        var blockedTotal: Int
        var notInstalledTotal: Int
        var notSupportedTotal: Int
        var revokedTotal: Int
        var activeTotal: Int
        var packages: [AXOfficialSkillPackageLifecycleEntry]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case totals
            case packages
        }

        init(
            schemaVersion: String = "",
            updatedAtMs: Int64 = 0,
            packagesTotal: Int = 0,
            readyTotal: Int = 0,
            degradedTotal: Int = 0,
            blockedTotal: Int = 0,
            notInstalledTotal: Int = 0,
            notSupportedTotal: Int = 0,
            revokedTotal: Int = 0,
            activeTotal: Int = 0,
            packages: [AXOfficialSkillPackageLifecycleEntry] = []
        ) {
            self.schemaVersion = schemaVersion
            self.updatedAtMs = updatedAtMs
            self.packagesTotal = packagesTotal
            self.readyTotal = readyTotal
            self.degradedTotal = degradedTotal
            self.blockedTotal = blockedTotal
            self.notInstalledTotal = notInstalledTotal
            self.notSupportedTotal = notSupportedTotal
            self.revokedTotal = revokedTotal
            self.activeTotal = activeTotal
            self.packages = packages
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = (try? container.decode(String.self, forKey: .schemaVersion)) ?? ""
            updatedAtMs = max(0, (try? container.decode(Int64.self, forKey: .updatedAtMs)) ?? 0)
            packages = (try? container.decode([AXOfficialSkillPackageLifecycleEntry].self, forKey: .packages)) ?? []
            let totals = try? container.decode(Totals.self, forKey: .totals)
            packagesTotal = max(0, totals?.packagesTotal ?? packages.count)
            readyTotal = max(0, totals?.readyTotal ?? 0)
            degradedTotal = max(0, totals?.degradedTotal ?? 0)
            blockedTotal = max(0, totals?.blockedTotal ?? 0)
            notInstalledTotal = max(0, totals?.notInstalledTotal ?? 0)
            notSupportedTotal = max(0, totals?.notSupportedTotal ?? 0)
            revokedTotal = max(0, totals?.revokedTotal ?? 0)
            activeTotal = max(0, totals?.activeTotal ?? 0)
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

    private static func loadOfficialSkillChannelState(
        baseURL: URL,
        stateURL: URL
    ) -> OfficialSkillChannelStateSnapshot {
        if let data = try? Data(contentsOf: stateURL),
           let snapshot = try? JSONDecoder().decode(OfficialSkillChannelStateSnapshot.self, from: data) {
            return OfficialSkillChannelStateSnapshot(
                channelID: snapshot.channelID.trimmingCharacters(in: .whitespacesAndNewlines),
                status: snapshot.status.trimmingCharacters(in: .whitespacesAndNewlines),
                updatedAtMs: max(0, snapshot.updatedAtMs),
                lastSuccessAtMs: max(0, snapshot.lastSuccessAtMs),
                skillCount: max(0, snapshot.skillCount),
                errorCode: snapshot.errorCode.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let currentDir = baseURL.appendingPathComponent("current", isDirectory: true)
        let lastKnownGoodDir = baseURL.appendingPathComponent("last_known_good", isDirectory: true)
        let currentHealthy = hasOfficialSkillSnapshotArtifacts(currentDir)
        let lastKnownGoodHealthy = hasOfficialSkillSnapshotArtifacts(lastKnownGoodDir)
        let inferredStatus: String
        if currentHealthy {
            inferredStatus = "healthy"
        } else if lastKnownGoodHealthy {
            inferredStatus = "stale"
        } else {
            inferredStatus = ""
        }

        return OfficialSkillChannelStateSnapshot(
            channelID: "official-stable",
            status: inferredStatus,
            updatedAtMs: 0,
            lastSuccessAtMs: 0,
            skillCount: 0,
            errorCode: ""
        )
    }

    private static func loadOfficialSkillChannelMaintenanceStatus(
        url: URL
    ) -> OfficialSkillChannelMaintenanceSnapshot {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(OfficialSkillChannelMaintenanceSnapshot.self, from: data) else {
            return OfficialSkillChannelMaintenanceSnapshot(
                maintenanceEnabled: false,
                maintenanceIntervalMs: 0,
                maintenanceLastRunAtMs: 0,
                maintenanceSourceKind: "",
                lastTransitionAtMs: 0,
                lastTransitionKind: "",
                lastTransitionSummary: ""
            )
        }
        return OfficialSkillChannelMaintenanceSnapshot(
            maintenanceEnabled: snapshot.maintenanceEnabled,
            maintenanceIntervalMs: max(0, snapshot.maintenanceIntervalMs),
            maintenanceLastRunAtMs: max(0, snapshot.maintenanceLastRunAtMs),
            maintenanceSourceKind: snapshot.maintenanceSourceKind.trimmingCharacters(in: .whitespacesAndNewlines),
            lastTransitionAtMs: max(0, snapshot.lastTransitionAtMs),
            lastTransitionKind: snapshot.lastTransitionKind.trimmingCharacters(in: .whitespacesAndNewlines),
            lastTransitionSummary: snapshot.lastTransitionSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func loadOfficialSkillPackageLifecycle(
        url: URL
    ) -> OfficialSkillPackageLifecycleSnapshot {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(OfficialSkillPackageLifecycleSnapshot.self, from: data) else {
            return OfficialSkillPackageLifecycleSnapshot()
        }
        return snapshot
    }

    private static func hasOfficialSkillSnapshotArtifacts(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent("index.json").path)
            && fm.fileExists(atPath: url.appendingPathComponent("trusted_publishers.json").path)
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
        builtinGovernedSkills: [AXBuiltinGovernedSkillSummary],
        trustedPublisherCount: Int,
        projectIndexEntries: [AXSkillsIndexReference],
        globalIndexEntries: [AXSkillsIndexReference],
        conflictWarnings: [String],
        activePublisherIDs: [String],
        activeSourceIDs: [String],
        localDevPublisherActive: Bool,
        baselinePublisherIDs: [String],
        baselineLocalDevSkillCount: Int,
        officialChannelSummaryLine: String,
        officialChannelDetailLine: String
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
        lines.append("xt_builtin_governed_skills=\(builtinGovernedSkills.count)")
        let builtinPreview = builtinGovernedSkills.prefix(5).map(\.skillID)
        lines.append(builtinPreview.isEmpty ? "xt_builtin_governed_preview=none" : "xt_builtin_governed_preview=\(builtinPreview.joined(separator: ","))")
        lines.append("xt_builtin_supervisor_voice=\(builtinGovernedSkills.contains(where: { $0.skillID == "supervisor-voice" }) ? "available" : "missing")")
        lines.append("local_dev_publisher_active=\(localDevPublisherActive ? "yes" : "no")")
        let officialSummary = officialChannelSummaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !officialSummary.isEmpty {
            lines.append("official_channel=\(officialSummary)")
        }
        let officialDetail = officialChannelDetailLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !officialDetail.isEmpty {
            lines.append("official_channel_detail=\(officialDetail)")
        }
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

        let hubItems = selectedPins.compactMap { pin -> SupervisorSkillRegistryItem? in
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
        let items = mergedSupervisorRegistryItems(
            hubItems: hubItems,
            builtinItems: nativeSupervisorRegistryItems()
        )
        .sorted { lhs, rhs in
            let leftScope = skillPinnedScopePriority(lhs.policyScope)
            let rightScope = skillPinnedScopePriority(rhs.policyScope)
            if leftScope != rightScope {
                return leftScope > rightScope
            }
            return lhs.skillId.localizedCaseInsensitiveCompare(rhs.skillId) == .orderedAscending
        }

        let updatedAtMs = max(0, hubIndex.skills.map(\.version).isEmpty ? 0 : loadHubSkillsIndexUpdatedAtMs(url: indexURL))
        let source: String = {
            if hubIndex.available {
                return nativeSupervisorRegistryItems().isEmpty ? "hub_skill_registry" : "hub_skill_registry+xt_builtin"
            }
            return nativeSupervisorRegistryItems().isEmpty ? "hub_skill_registry_unavailable" : "xt_builtin_skill_registry"
        }()
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

        let hubItems = selectedPins.compactMap { pin -> XTResolvedSkillCacheItem? in
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
                fallbackSkillId: skill.skillID,
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
        let items = mergedResolvedSkillCacheItems(
            hubItems: hubItems,
            builtinItems: nativeResolvedSkillCacheItems()
        )
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
            source: nativeResolvedSkillCacheItems().isEmpty ? "hub_resolved_skills_snapshot" : "hub_resolved_skills_snapshot+xt_builtin",
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
        var governedDispatchVariants: [SupervisorGovernedSkillDispatchVariant]
        var governedDispatchNotes: [String]
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

    private static func mergedSupervisorRegistryItems(
        hubItems: [SupervisorSkillRegistryItem],
        builtinItems: [SupervisorSkillRegistryItem]
    ) -> [SupervisorSkillRegistryItem] {
        var ordered: [SupervisorSkillRegistryItem] = []
        var seen = Set<String>()
        for item in hubItems + builtinItems {
            let normalized = item.skillId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(item)
        }
        return ordered
    }

    private static func mergedResolvedSkillCacheItems(
        hubItems: [XTResolvedSkillCacheItem],
        builtinItems: [XTResolvedSkillCacheItem]
    ) -> [XTResolvedSkillCacheItem] {
        var ordered: [XTResolvedSkillCacheItem] = []
        var seen = Set<String>()
        for item in hubItems + builtinItems {
            let normalized = item.skillId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(item)
        }
        return ordered
    }

    private static func nativeSupervisorRegistryItems() -> [SupervisorSkillRegistryItem] {
        nativeSupervisorSkillSpecs.map { spec in
            SupervisorSkillRegistryItem(
                skillId: spec.0,
                displayName: spec.1,
                description: spec.2,
                capabilitiesRequired: spec.3,
                governedDispatch: spec.4,
                governedDispatchVariants: nativeSupervisorDispatchVariants(skillId: spec.0),
                governedDispatchNotes: nativeSupervisorDispatchNotes(skillId: spec.0),
                inputSchemaRef: "schema://\(spec.0).input",
                outputSchemaRef: "schema://\(spec.0).output",
                sideEffectClass: spec.5,
                riskLevel: spec.6,
                requiresGrant: nativeSupervisorRequiresGrant(skillId: spec.0),
                policyScope: "xt_builtin",
                timeoutMs: spec.7,
                maxRetries: spec.8,
                available: true
            )
        }
    }

    private static func nativeBuiltinGovernedSkillSummaries() -> [AXBuiltinGovernedSkillSummary] {
        nativeSupervisorRegistryItems().map { item in
            AXBuiltinGovernedSkillSummary(
                skillID: item.skillId,
                displayName: item.displayName,
                summary: item.description,
                capabilitiesRequired: item.capabilitiesRequired,
                sideEffectClass: item.sideEffectClass,
                riskLevel: item.riskLevel.rawValue,
                policyScope: item.policyScope
            )
        }
    }

    private static func nativeResolvedSkillCacheItems() -> [XTResolvedSkillCacheItem] {
        nativeSupervisorRegistryItems().map { item in
            XTResolvedSkillCacheItem(
                skillId: item.skillId,
                displayName: item.displayName,
                description: item.description,
                packageSHA256: syntheticBuiltinSHA256(seed: item.skillId + "::package"),
                canonicalManifestSHA256: syntheticBuiltinSHA256(seed: item.skillId + "::manifest"),
                sourceId: "xt_builtin",
                pinScope: item.policyScope,
                riskLevel: item.riskLevel.rawValue,
                requiresGrant: item.requiresGrant,
                sideEffectClass: item.sideEffectClass,
                inputSchemaRef: item.inputSchemaRef,
                outputSchemaRef: item.outputSchemaRef,
                timeoutMs: item.timeoutMs,
                maxRetries: item.maxRetries
            )
        }
    }

    private static func nativeSupervisorDispatchNotes(skillId: String) -> [String] {
        switch skillId {
        case "guarded-automation":
            return [
                "Defaults to project snapshot / readiness inspection when no action is supplied; use it to verify trusted automation state before device work.",
                "actions=open/navigate/snapshot/extract/click/type/upload -> device.browser.control; actions=read/fetch -> browser_read."
            ]
        case "repo.move.path":
            return ["Use repo.move.path for both move and rename within the governed project root."]
        case "process.start":
            return ["restart_on_exit is honored only when the execution tier allows managed process auto-restart."]
        case "supervisor-voice":
            return ["Defaults to status when no action is supplied; if text/content/value is present, XT treats the request as speak."]
        case "repo.pr.create":
            return ["Requires GitHub CLI `gh` to be installed and authenticated for the active repository."]
        case "repo.ci.read", "repo.ci.trigger":
            return ["Currently implemented through GitHub CLI and therefore provider=github only."]
        default:
            return []
        }
    }

    private static func nativeSupervisorDispatchVariants(
        skillId: String
    ) -> [SupervisorGovernedSkillDispatchVariant] {
        switch skillId {
        case "guarded-automation":
            return [
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["status", "readiness", "context", "project_snapshot"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.project_snapshot.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: [],
                        argAliases: [:],
                        requiredAny: [],
                        exactlyOneOf: []
                    ),
                    actionArg: "",
                    actionMap: [:]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["open", "open_url", "navigate", "goto", "visit"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [["url"]],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "open": "open_url",
                        "open_url": "open_url",
                        "navigate": "navigate",
                        "goto": "navigate",
                        "visit": "navigate",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["snapshot", "inspect", "extract"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "session_id", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [["url", "session_id"]],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "snapshot": "snapshot",
                        "inspect": "snapshot",
                        "extract": "extract",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["click", "tap"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "session_id", "selector", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "click": "click",
                        "tap": "click",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["type", "fill", "input", "enter"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: [
                            "url", "session_id", "selector", "field_role",
                            "text", "content", "value",
                            "secret_item_id", "secret_scope", "secret_name", "secret_project_id",
                            "grant_id", "timeout_sec", "max_bytes"
                        ],
                        argAliases: [:],
                        requiredAny: [],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "type": "type",
                        "fill": "type",
                        "input": "type",
                        "enter": "type",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["upload", "attach"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "session_id", "selector", "path", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "upload": "upload",
                        "attach": "upload",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["read", "read_page", "read-page", "fetch"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.browser_read.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [["url"]],
                        exactlyOneOf: []
                    ),
                    actionArg: "",
                    actionMap: [:]
                ),
            ]
        default:
            return []
        }
    }

    private static func nativeSupervisorRequiresGrant(skillId: String) -> Bool {
        switch skillId {
        case "guarded-automation":
            return true
        default:
            return false
        }
    }

    private static func syntheticBuiltinSHA256(seed: String) -> String {
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func supervisorSkillRegistryItem(
        skill: HubSkillsIndexSnapshot.Skill,
        scope: String
    ) -> SupervisorSkillRegistryItem {
        let manifestHints = parseSupervisorSkillManifestHints(
            skill.manifestJSON,
            fallbackSkillId: skill.skillID,
            fallbackDescription: firstNonEmptySkillText(skill.description, skill.installHint, skill.name),
            capabilityFallback: skill.capabilitiesRequired
        )
        return SupervisorSkillRegistryItem(
            skillId: skill.skillID,
            displayName: firstNonEmptySkillText(skill.name, skill.skillID),
            description: manifestHints.description,
            capabilitiesRequired: manifestHints.capabilitiesRequired,
            governedDispatch: manifestHints.governedDispatch,
            governedDispatchVariants: manifestHints.governedDispatchVariants,
            governedDispatchNotes: manifestHints.governedDispatchNotes,
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
        fallbackSkillId: String,
        fallbackDescription: String,
        capabilityFallback: [String]
    ) -> SupervisorSkillManifestHints {
        let manifest = jsonObject(from: rawManifest)
        let resolvedSkillId = firstNonEmptySkillText(
            stringValue(manifest["skill_id"]),
            fallbackSkillId
        )
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
                skillId: resolvedSkillId
            ) ?? fallbackGovernedDispatch(
                skillId: resolvedSkillId
            ),
            governedDispatchVariants: parseSupervisorGovernedDispatchVariants(
                manifest["governed_dispatch_variants"],
                skillId: resolvedSkillId
            ).ifEmpty(
                fallback: fallbackGovernedDispatchVariants(skillId: resolvedSkillId)
            ),
            governedDispatchNotes: stringArrayValue(
                manifest["governed_dispatch_notes"],
                fallback: fallbackGovernedDispatchNotes(
                    skillId: resolvedSkillId
                )
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

    private static func parseSupervisorGovernedDispatchVariants(
        _ raw: Any?,
        skillId: String
    ) -> [SupervisorGovernedSkillDispatchVariant] {
        guard let rows = raw as? [Any] else { return [] }
        return rows.compactMap { row in
            guard let object = row as? [String: Any] else { return nil }
            let actions = stringArrayValue(object["actions"], fallback: [])
            guard !actions.isEmpty else { return nil }
            guard let dispatch = parseSupervisorGovernedDispatch(
                object["dispatch"] ?? object["governed_dispatch"],
                skillId: skillId
            ) else { return nil }
            return SupervisorGovernedSkillDispatchVariant(
                actions: actions,
                dispatch: dispatch,
                actionArg: {
                    if object.keys.contains("action_arg") {
                        return stringValue(object["action_arg"])
                    }
                    return "action"
                }(),
                actionMap: stringMapValue(object["action_map"])
            )
        }
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
        case "supervisor-voice", "supervisor.voice", "supervisor_voice":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.supervisorVoicePlayback.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["action", "text"],
                argAliases: [
                    "action": ["mode", "operation"],
                    "text": ["content", "value"],
                ],
                requiredAny: [],
                exactlyOneOf: []
            )
        case "guarded-automation", "guarded.automation", "guarded_automation", "trusted-automation", "trusted_automation":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.project_snapshot.rawValue,
                fixedArgs: [:],
                passthroughArgs: [],
                argAliases: [:],
                requiredAny: [],
                exactlyOneOf: []
            )
        case "repo.delete.path", "repo.delete.file", "repo.delete":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.delete_path.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["path", "recursive", "force"],
                argAliases: ["path": ["target"]],
                requiredAny: [["path"]],
                exactlyOneOf: []
            )
        case "repo.move.path", "repo.rename.path", "repo.move", "repo.rename":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.move_path.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["from", "to", "overwrite", "create_dirs"],
                argAliases: [
                    "from": ["source", "src"],
                    "to": ["destination", "dest", "new_path"],
                ],
                requiredAny: [["from"], ["to"]],
                exactlyOneOf: []
            )
        case "process.start":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.process_start.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["command", "name", "process_id", "cwd", "env", "restart_on_exit"],
                argAliases: ["process_id": ["id"]],
                requiredAny: [["command"]],
                exactlyOneOf: []
            )
        case "process.status":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.process_status.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["process_id", "include_exited"],
                argAliases: ["process_id": ["id"]],
                requiredAny: [],
                exactlyOneOf: []
            )
        case "process.logs":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.process_logs.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["process_id", "tail_lines", "max_bytes"],
                argAliases: ["process_id": ["id"]],
                requiredAny: [["process_id"]],
                exactlyOneOf: []
            )
        case "process.stop":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.process_stop.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["process_id", "force"],
                argAliases: ["process_id": ["id"]],
                requiredAny: [["process_id"]],
                exactlyOneOf: []
            )
        case "repo.git.commit":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.git_commit.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["message", "all", "allow_empty", "paths"],
                argAliases: [:],
                requiredAny: [["message"]],
                exactlyOneOf: []
            )
        case "repo.git.push":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.git_push.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["remote", "branch", "set_upstream"],
                argAliases: [:],
                requiredAny: [],
                exactlyOneOf: []
            )
        case "repo.pr.create", "repo.pull_request.create", "repo.pull-request.create":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.pr_create.rawValue,
                fixedArgs: [:],
                passthroughArgs: ["title", "body", "base", "head", "draft", "fill", "labels", "reviewers"],
                argAliases: [:],
                requiredAny: [],
                exactlyOneOf: []
            )
        case "repo.ci.read", "ci.read":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.ci_read.rawValue,
                fixedArgs: ["provider": .string("github")],
                passthroughArgs: ["workflow", "branch", "commit", "limit"],
                argAliases: [:],
                requiredAny: [],
                exactlyOneOf: []
            )
        case "repo.ci.trigger", "ci.trigger":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.ci_trigger.rawValue,
                fixedArgs: ["provider": .string("github")],
                passthroughArgs: ["workflow", "ref", "inputs"],
                argAliases: [:],
                requiredAny: [["workflow"]],
                exactlyOneOf: []
            )
        default:
            return nil
        }
    }

    private static func fallbackGovernedDispatchNotes(skillId: String) -> [String] {
        switch skillId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "agent-browser", "agent_browser", "agent.browser":
            return [
                "actions=open/navigate/snapshot/extract/click/type/upload -> device.browser.control",
                "actions=read/fetch -> browser_read; open/navigate/read/fetch require url; snapshot/extract accept url or session_id"
            ]
        case "supervisor-voice", "supervisor.voice", "supervisor_voice":
            return [
                "action=status returns the resolved playback route, selected voice pack, and the last real playback outcome",
                "action=preview plays the built-in preview line; action=speak uses text/content/value; action=stop interrupts active playback"
            ]
        case "guarded-automation", "guarded.automation", "guarded_automation", "trusted-automation", "trusted_automation":
            return [
                "Defaults to project_snapshot when no action is supplied; action=status/readiness/context also resolves to project_snapshot.",
                "actions=open/navigate/snapshot/extract/click/type/upload -> device.browser.control; actions=read/fetch -> browser_read."
            ]
        default:
            return []
        }
    }

    private static func fallbackGovernedDispatchVariants(skillId: String) -> [SupervisorGovernedSkillDispatchVariant] {
        switch skillId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "guarded-automation", "guarded.automation", "guarded_automation", "trusted-automation", "trusted_automation":
            return [
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["status", "readiness", "context", "project_snapshot"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.project_snapshot.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: [],
                        argAliases: [:],
                        requiredAny: [],
                        exactlyOneOf: []
                    ),
                    actionArg: "",
                    actionMap: [:]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["open", "open_url", "navigate", "goto", "visit"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [["url"]],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "open": "open_url",
                        "open_url": "open_url",
                        "navigate": "navigate",
                        "goto": "navigate",
                        "visit": "navigate",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["snapshot", "inspect", "extract"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "session_id", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [["url", "session_id"]],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "snapshot": "snapshot",
                        "inspect": "snapshot",
                        "extract": "extract",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["click", "tap"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "session_id", "selector", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "click": "click",
                        "tap": "click",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["type", "fill", "input", "enter"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: [
                            "url", "session_id", "selector", "field_role",
                            "text", "content", "value",
                            "secret_item_id", "secret_scope", "secret_name", "secret_project_id",
                            "grant_id", "timeout_sec", "max_bytes"
                        ],
                        argAliases: [:],
                        requiredAny: [],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "type": "type",
                        "fill": "type",
                        "input": "type",
                        "enter": "type",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["upload", "attach"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "session_id", "selector", "path", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "upload": "upload",
                        "attach": "upload",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["read", "read_page", "read-page", "fetch"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.browser_read.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [["url"]],
                        exactlyOneOf: []
                    ),
                    actionArg: "",
                    actionMap: [:]
                ),
            ]
        case "agent-browser", "agent_browser", "agent.browser":
            return [
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["open", "open_url", "navigate", "goto", "visit"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [["url"]],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "open": "open_url",
                        "open_url": "open_url",
                        "navigate": "navigate",
                        "goto": "navigate",
                        "visit": "navigate",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["snapshot", "inspect", "extract"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "session_id", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [["url", "session_id"]],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "snapshot": "snapshot",
                        "inspect": "snapshot",
                        "extract": "extract",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["click", "tap"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "session_id", "selector", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "click": "click",
                        "tap": "click",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["type", "fill", "input", "enter"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: [
                            "url", "session_id", "selector", "field_role",
                            "text", "content", "value",
                            "secret_item_id", "secret_scope", "secret_name", "secret_project_id",
                            "grant_id", "timeout_sec", "max_bytes"
                        ],
                        argAliases: [:],
                        requiredAny: [],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "type": "type",
                        "fill": "type",
                        "input": "type",
                        "enter": "type",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["upload", "attach"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.deviceBrowserControl.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "session_id", "selector", "path", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [],
                        exactlyOneOf: []
                    ),
                    actionArg: "action",
                    actionMap: [
                        "upload": "upload",
                        "attach": "upload",
                    ]
                ),
                SupervisorGovernedSkillDispatchVariant(
                    actions: ["read", "read_page", "read-page", "fetch"],
                    dispatch: SupervisorGovernedSkillDispatch(
                        tool: ToolName.browser_read.rawValue,
                        fixedArgs: [:],
                        passthroughArgs: ["url", "grant_id", "timeout_sec", "max_bytes"],
                        argAliases: [:],
                        requiredAny: [["url"]],
                        exactlyOneOf: []
                    ),
                    actionArg: "",
                    actionMap: [:]
                ),
            ]
        default:
            return []
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

    private static func stringMapValue(_ raw: Any?) -> [String: String] {
        guard let object = raw as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in object {
            let cleanedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedValue = stringValue(value)
            guard !cleanedKey.isEmpty, !cleanedValue.isEmpty else { continue }
            result[cleanedKey] = cleanedValue
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

private extension Array {
    func ifEmpty(fallback: @autoclosure () -> [Element]) -> [Element] {
        isEmpty ? fallback() : self
    }
}
