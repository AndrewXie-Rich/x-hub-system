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

struct AXHubSkillCompatibilityEnvelope: Codable, Equatable, Sendable {
    var compatibilityState: String
    var runtimeHosts: [String]
    var protocolVersions: [String]
    var minHubVersion: String
    var minXTVersion: String
    var lastVerifiedAtMs: Int64

    init(
        compatibilityState: String = "",
        runtimeHosts: [String] = [],
        protocolVersions: [String] = [],
        minHubVersion: String = "",
        minXTVersion: String = "",
        lastVerifiedAtMs: Int64 = 0
    ) {
        self.compatibilityState = compatibilityState
        self.runtimeHosts = runtimeHosts
        self.protocolVersions = protocolVersions
        self.minHubVersion = minHubVersion
        self.minXTVersion = minXTVersion
        self.lastVerifiedAtMs = lastVerifiedAtMs
    }

    enum CodingKeys: String, CodingKey {
        case compatibilityState = "compatibility_state"
        case runtimeHosts = "runtime_hosts"
        case protocolVersions = "protocol_versions"
        case minHubVersion = "min_hub_version"
        case minXTVersion = "min_xt_version"
        case lastVerifiedAtMs = "last_verified_at_ms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        compatibilityState = (try? container.decode(String.self, forKey: .compatibilityState)) ?? ""
        runtimeHosts = (try? container.decode([String].self, forKey: .runtimeHosts)) ?? []
        protocolVersions = (try? container.decode([String].self, forKey: .protocolVersions)) ?? []
        minHubVersion = (try? container.decode(String.self, forKey: .minHubVersion)) ?? ""
        minXTVersion = (try? container.decode(String.self, forKey: .minXTVersion)) ?? ""
        lastVerifiedAtMs = max(0, (try? container.decode(Int64.self, forKey: .lastVerifiedAtMs)) ?? 0)
    }
}

struct AXHubSkillQualityEvidenceStatus: Codable, Equatable, Sendable {
    var replay: String
    var fuzz: String
    var doctor: String
    var smoke: String

    init(
        replay: String = "",
        fuzz: String = "",
        doctor: String = "",
        smoke: String = ""
    ) {
        self.replay = replay
        self.fuzz = fuzz
        self.doctor = doctor
        self.smoke = smoke
    }

    enum CodingKeys: String, CodingKey {
        case replay
        case fuzz
        case doctor
        case smoke
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        replay = (try? container.decode(String.self, forKey: .replay)) ?? ""
        fuzz = (try? container.decode(String.self, forKey: .fuzz)) ?? ""
        doctor = (try? container.decode(String.self, forKey: .doctor)) ?? ""
        smoke = (try? container.decode(String.self, forKey: .smoke)) ?? ""
    }
}

struct AXHubSkillArtifactSignature: Codable, Equatable, Sendable {
    var algorithm: String
    var present: Bool
    var trustedPublisher: Bool

    init(
        algorithm: String = "",
        present: Bool = false,
        trustedPublisher: Bool = false
    ) {
        self.algorithm = algorithm
        self.present = present
        self.trustedPublisher = trustedPublisher
    }

    enum CodingKeys: String, CodingKey {
        case algorithm
        case present
        case trustedPublisher = "trusted_publisher"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        algorithm = (try? container.decode(String.self, forKey: .algorithm)) ?? ""
        present = (try? container.decode(Bool.self, forKey: .present)) ?? false
        trustedPublisher = (try? container.decode(Bool.self, forKey: .trustedPublisher)) ?? false
    }
}

struct AXHubSkillArtifactIntegrity: Codable, Equatable, Sendable {
    var packageSHA256: String
    var manifestSHA256: String
    var packageFormat: String
    var packageSizeBytes: Int64
    var fileHashCount: Int
    var signature: AXHubSkillArtifactSignature

    init(
        packageSHA256: String = "",
        manifestSHA256: String = "",
        packageFormat: String = "",
        packageSizeBytes: Int64 = 0,
        fileHashCount: Int = 0,
        signature: AXHubSkillArtifactSignature = .init()
    ) {
        self.packageSHA256 = packageSHA256
        self.manifestSHA256 = manifestSHA256
        self.packageFormat = packageFormat
        self.packageSizeBytes = packageSizeBytes
        self.fileHashCount = fileHashCount
        self.signature = signature
    }

    enum CodingKeys: String, CodingKey {
        case packageSHA256 = "package_sha256"
        case manifestSHA256 = "manifest_sha256"
        case packageFormat = "package_format"
        case packageSizeBytes = "package_size_bytes"
        case fileHashCount = "file_hash_count"
        case signature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packageSHA256 = ((try? container.decode(String.self, forKey: .packageSHA256)) ?? "").lowercased()
        manifestSHA256 = ((try? container.decode(String.self, forKey: .manifestSHA256)) ?? "").lowercased()
        packageFormat = (try? container.decode(String.self, forKey: .packageFormat)) ?? ""
        packageSizeBytes = max(0, (try? container.decode(Int64.self, forKey: .packageSizeBytes)) ?? 0)
        fileHashCount = max(0, (try? container.decode(Int.self, forKey: .fileHashCount)) ?? 0)
        signature = (try? container.decode(AXHubSkillArtifactSignature.self, forKey: .signature)) ?? .init()
    }
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
    var intentFamilies: [String]
    var capabilityFamilies: [String]
    var capabilityProfiles: [String]
    var grantFloor: String
    var approvalFloor: String
    var capabilitiesRequired: [String]
    var riskLevel: String
    var requiresGrant: Bool
    var trustTier: String
    var packageState: String
    var revokeState: String
    var supportTier: String
    var entrypointRuntime: String
    var entrypointCommand: String
    var entrypointArgs: [String]
    var compatibilityEnvelope: AXHubSkillCompatibilityEnvelope
    var qualityEvidenceStatus: AXHubSkillQualityEvidenceStatus
    var artifactIntegrity: AXHubSkillArtifactIntegrity
    var signatureVerified: Bool
    var signatureBypassed: Bool
    var mappingAliasesUsed: [String]
    var defaultsApplied: [String]
    var pinnedScopes: [String]
    var activePinnedScopes: [String]
    var inactivePinnedScopes: [String]
    var publisherTrusted: Bool
    var revoked: Bool

    var id: String { packageSHA256 }

    init(
        skillID: String,
        name: String,
        version: String,
        publisherID: String,
        sourceID: String,
        packageSHA256: String,
        abiCompatVersion: String,
        compatibilityState: AXSkillCompatibilityState,
        canonicalManifestSHA256: String,
        installHint: String,
        intentFamilies: [String] = [],
        capabilityFamilies: [String] = [],
        capabilityProfiles: [String] = [],
        grantFloor: String = XTSkillGrantFloor.none.rawValue,
        approvalFloor: String = XTSkillApprovalFloor.none.rawValue,
        capabilitiesRequired: [String] = [],
        riskLevel: String = "",
        requiresGrant: Bool = false,
        trustTier: String = "",
        packageState: String = "",
        revokeState: String = "",
        supportTier: String = "",
        entrypointRuntime: String = "",
        entrypointCommand: String = "",
        entrypointArgs: [String] = [],
        compatibilityEnvelope: AXHubSkillCompatibilityEnvelope = .init(),
        qualityEvidenceStatus: AXHubSkillQualityEvidenceStatus = .init(),
        artifactIntegrity: AXHubSkillArtifactIntegrity = .init(),
        signatureVerified: Bool = false,
        signatureBypassed: Bool = false,
        mappingAliasesUsed: [String],
        defaultsApplied: [String],
        pinnedScopes: [String],
        activePinnedScopes: [String] = [],
        inactivePinnedScopes: [String] = [],
        publisherTrusted: Bool = false,
        revoked: Bool
    ) {
        self.skillID = skillID
        self.name = name
        self.version = version
        self.publisherID = publisherID
        self.sourceID = sourceID
        self.packageSHA256 = packageSHA256
        self.abiCompatVersion = abiCompatVersion
        self.compatibilityState = compatibilityState
        self.canonicalManifestSHA256 = canonicalManifestSHA256
        self.installHint = installHint
        self.intentFamilies = intentFamilies
        self.capabilityFamilies = capabilityFamilies
        self.capabilityProfiles = capabilityProfiles
        self.grantFloor = grantFloor
        self.approvalFloor = approvalFloor
        self.capabilitiesRequired = capabilitiesRequired
        self.riskLevel = riskLevel
        self.requiresGrant = requiresGrant
        self.trustTier = trustTier
        self.packageState = packageState
        self.revokeState = revokeState
        self.supportTier = supportTier
        self.entrypointRuntime = entrypointRuntime
        self.entrypointCommand = entrypointCommand
        self.entrypointArgs = entrypointArgs
        self.compatibilityEnvelope = compatibilityEnvelope
        self.qualityEvidenceStatus = qualityEvidenceStatus
        self.artifactIntegrity = artifactIntegrity
        self.signatureVerified = signatureVerified
        self.signatureBypassed = signatureBypassed
        self.mappingAliasesUsed = mappingAliasesUsed
        self.defaultsApplied = defaultsApplied
        self.pinnedScopes = pinnedScopes
        self.activePinnedScopes = activePinnedScopes
        self.inactivePinnedScopes = inactivePinnedScopes
        self.publisherTrusted = publisherTrusted
        self.revoked = revoked
    }
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
    var whyNotRunnable: String
    var unblockActions: [String]

    var id: String { packageSHA256 }

    init(
        packageSHA256: String,
        title: String,
        subtitle: String,
        stateLabel: String,
        summaryLine: String,
        timelineLine: String,
        whyNotRunnable: String = "",
        unblockActions: [String] = []
    ) {
        self.packageSHA256 = packageSHA256
        self.title = title
        self.subtitle = subtitle
        self.stateLabel = stateLabel
        self.summaryLine = summaryLine
        self.timelineLine = timelineLine
        self.whyNotRunnable = whyNotRunnable
        self.unblockActions = unblockActions
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

    private func officialPackageLifecycleWhyNotRunnable(
        _ item: AXOfficialSkillPackageLifecycleEntry
    ) -> String {
        let packageState = item.packageState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if packageState == "revoked" {
            return "package revoked by Hub governance"
        }

        let overall = item.overallState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch overall {
        case "blocked" where item.requiresGrant:
            return "grant chain is still blocking this official package"
        case "blocked":
            return "package failed official readiness checks"
        case "not_supported":
            return "current XT / Hub runtime does not support this package"
        case "not_installed":
            return "package has not been resolved into the current availability set"
        case "degraded":
            return "package is degraded and should not be treated as runnable_now"
        default:
            return "official package is not runnable_now"
        }
    }

    private func officialPackageLifecycleUnblockActions(
        _ item: AXOfficialSkillPackageLifecycleEntry
    ) -> [String] {
        let packageState = item.packageState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if packageState == "revoked" {
            return ["open_skill_governance_surface", "refresh_resolved_cache"]
        }

        let overall = item.overallState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch overall {
        case "blocked" where item.requiresGrant:
            return ["request_hub_grant", "open_skill_governance_surface", "refresh_resolved_cache"]
        case "blocked", "degraded":
            return ["open_skill_governance_surface", "refresh_resolved_cache"]
        case "not_supported":
            return ["open_project_settings", "open_skill_governance_surface"]
        case "not_installed":
            return ["install_baseline", "pin_package_project", "pin_package_global"]
        default:
            return []
        }
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
                    timelineLine: officialPackageLifecycleProblemTimelineLine(item),
                    whyNotRunnable: officialPackageLifecycleWhyNotRunnable(item),
                    unblockActions: officialPackageLifecycleUnblockActions(item)
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
    var publisherID: String
    var sourceId: String
    var pinScope: String
    var capabilitiesRequired: [String]
    var intentFamilies: [String]
    var capabilityFamilies: [String]
    var capabilityProfiles: [String]
    var grantFloor: String
    var approvalFloor: String
    var riskLevel: String
    var requiresGrant: Bool
    var sideEffectClass: String
    var governedDispatch: SupervisorGovernedSkillDispatch?
    var governedDispatchVariants: [SupervisorGovernedSkillDispatchVariant]
    var governedDispatchNotes: [String]
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
        case publisherID = "publisher_id"
        case sourceId = "source_id"
        case pinScope = "pin_scope"
        case capabilitiesRequired = "capabilities_required"
        case intentFamilies = "intent_families"
        case capabilityFamilies = "capability_families"
        case capabilityProfiles = "capability_profiles"
        case grantFloor = "grant_floor"
        case approvalFloor = "approval_floor"
        case riskLevel = "risk_level"
        case requiresGrant = "requires_grant"
        case sideEffectClass = "side_effect_class"
        case governedDispatch = "governed_dispatch"
        case governedDispatchVariants = "governed_dispatch_variants"
        case governedDispatchNotes = "governed_dispatch_notes"
        case inputSchemaRef = "input_schema_ref"
        case outputSchemaRef = "output_schema_ref"
        case timeoutMs = "timeout_ms"
        case maxRetries = "max_retries"
    }
}

extension XTResolvedSkillCacheItem {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skillId = try container.decode(String.self, forKey: .skillId)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        packageSHA256 = ((try? container.decode(String.self, forKey: .packageSHA256)) ?? "").lowercased()
        canonicalManifestSHA256 = ((try? container.decode(String.self, forKey: .canonicalManifestSHA256)) ?? "").lowercased()
        publisherID = try container.decode(String.self, forKey: .publisherID)
        sourceId = try container.decode(String.self, forKey: .sourceId)
        pinScope = try container.decode(String.self, forKey: .pinScope)
        capabilitiesRequired = try container.decodeIfPresent([String].self, forKey: .capabilitiesRequired) ?? []
        intentFamilies = try container.decodeIfPresent([String].self, forKey: .intentFamilies) ?? []
        capabilityFamilies = try container.decodeIfPresent([String].self, forKey: .capabilityFamilies) ?? []
        capabilityProfiles = try container.decodeIfPresent([String].self, forKey: .capabilityProfiles) ?? []
        grantFloor = try container.decodeIfPresent(String.self, forKey: .grantFloor) ?? XTSkillGrantFloor.none.rawValue
        approvalFloor = try container.decodeIfPresent(String.self, forKey: .approvalFloor) ?? XTSkillApprovalFloor.none.rawValue
        riskLevel = try container.decodeIfPresent(String.self, forKey: .riskLevel) ?? ""
        requiresGrant = try container.decodeIfPresent(Bool.self, forKey: .requiresGrant) ?? false
        sideEffectClass = try container.decodeIfPresent(String.self, forKey: .sideEffectClass) ?? ""
        governedDispatch = try container.decodeIfPresent(SupervisorGovernedSkillDispatch.self, forKey: .governedDispatch)
        governedDispatchVariants = try container.decodeIfPresent([SupervisorGovernedSkillDispatchVariant].self, forKey: .governedDispatchVariants) ?? []
        governedDispatchNotes = try container.decodeIfPresent([String].self, forKey: .governedDispatchNotes) ?? []
        inputSchemaRef = try container.decodeIfPresent(String.self, forKey: .inputSchemaRef) ?? ""
        outputSchemaRef = try container.decodeIfPresent(String.self, forKey: .outputSchemaRef) ?? ""
        timeoutMs = try container.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 30_000
        maxRetries = try container.decodeIfPresent(Int.self, forKey: .maxRetries) ?? 1
    }
}

struct XTResolvedSkillsCacheSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.resolved_skills_cache.v2"

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
    var profileEpoch: String
    var trustRootSetHash: String
    var revocationEpoch: String
    var officialChannelSnapshotID: String
    var runtimeSurfaceHash: String
    var remoteStateDirPath: String?
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
        case profileEpoch = "profile_epoch"
        case trustRootSetHash = "trust_root_set_hash"
        case revocationEpoch = "revocation_epoch"
        case officialChannelSnapshotID = "official_channel_snapshot_id"
        case runtimeSurfaceHash = "runtime_surface_hash"
        case remoteStateDirPath = "remote_state_dir_path"
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

    static let defaultAgentBaselineBundles: [AXDefaultAgentBaselineBundle] = [
        AXDefaultAgentBaselineBundle(
            bundleID: "coding-core",
            displayName: "Coding Core",
            summary: "Discovery plus governed reading/summarization for baseline code and document inspection.",
            skillIDs: ["find-skills", "summarize"],
            capabilityFamilies: ["skills.discover", "repo.read"],
            capabilityProfiles: ["observe_only"]
        ),
        AXDefaultAgentBaselineBundle(
            bundleID: "browser-research",
            displayName: "Browser Research",
            summary: "Governed browser observation and interaction pack for live web work under Hub control.",
            skillIDs: ["agent-browser"],
            capabilityFamilies: ["web.live", "browser.observe", "browser.interact", "browser.secret_fill"],
            capabilityProfiles: ["observe_only", "browser_research", "browser_operator", "browser_operator_with_secrets"]
        ),
        AXDefaultAgentBaselineBundle(
            bundleID: "supervisor-retrospective",
            displayName: "Supervisor Retrospective",
            summary: "Supervisor-oriented retrospective and workflow inspection bundle.",
            skillIDs: ["self-improving-agent"],
            capabilityFamilies: ["memory.inspect", "supervisor.orchestrate"],
            capabilityProfiles: ["observe_only"]
        ),
    ]

    static func canonicalCapabilitySemantics(
        skillId: String,
        capabilitiesRequired: [String],
        declaredIntentFamilies: [String] = [],
        declaredCapabilityFamilies: [String] = [],
        declaredCapabilityProfiles: [String] = [],
        declaredGrantFloor: String = "",
        declaredApprovalFloor: String = ""
    ) -> AXSkillCanonicalCapabilitySemantics {
        let normalized = normalizedCapabilitySemantics(
            skillId: skillId,
            capabilitiesRequired: capabilitiesRequired,
            declaredIntentFamilies: declaredIntentFamilies,
            declaredCapabilityFamilies: declaredCapabilityFamilies,
            declaredCapabilityProfiles: declaredCapabilityProfiles,
            declaredGrantFloor: declaredGrantFloor,
            declaredApprovalFloor: declaredApprovalFloor
        )
        return AXSkillCanonicalCapabilitySemantics(
            intentFamilies: normalized.intentFamilies,
            capabilityFamilies: normalized.capabilityFamilies,
            capabilityProfiles: normalized.capabilityProfiles,
            grantFloor: normalized.grantFloor,
            approvalFloor: normalized.approvalFloor
        )
    }

    static func canonicalSupervisorSkillID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        switch trimmed.lowercased() {
        case "find-skills", "find.skills", "find_skills", "find skills", "skill-find", "skill.find", "skill_find", "skill find", "skills.search", "skills_search":
            return "find-skills"
        case "local-embeddings", "local.embeddings", "local_embeddings", "local.embedding", "local_embedding", "local embedding", "embedding", "embeddings", "vector.embed", "vector_embed":
            return "local-embeddings"
        case "local-transcribe", "local.transcribe", "local_transcribe", "local transcribe", "transcribe", "transcription", "speech-to-text", "speech_to_text", "speech to text", "stt":
            return "local-transcribe"
        case "local-vision", "local.vision", "local_vision", "local vision", "vision", "vision-understand", "vision_understand", "vision understand":
            return "local-vision"
        case "local-ocr", "local.ocr", "local_ocr", "local ocr", "ocr", "image-ocr", "image_ocr", "image ocr":
            return "local-ocr"
        case "local-tts", "local.tts", "local_tts", "local tts", "tts", "text-to-speech", "text_to_speech", "text to speech", "speech-synthesis", "speech_synthesis", "speech synthesis":
            return "local-tts"
        case "supervisor-voice", "supervisor.voice", "supervisor_voice":
            return "supervisor-voice"
        case "guarded-automation", "guarded.automation", "guarded_automation", "trusted-automation", "trusted_automation":
            return "guarded-automation"
        case "request-skill-enable", "request.skill.enable", "request_skill_enable", "request skill enable", "enable-skill", "enable.skill", "enable_skill", "enable skill":
            return "request-skill-enable"
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

    private struct BuiltinLocalTaskWrapperSpec {
        var skillId: String
        var displayName: String
        var description: String
        var taskKind: String
        var capability: String
        var sideEffectClass: String
        var riskLevel: SupervisorSkillRiskLevel
        var timeoutMs: Int
        var maxRetries: Int
    }

    private static let builtinLocalTaskWrapperSpecs: [BuiltinLocalTaskWrapperSpec] = [
        BuiltinLocalTaskWrapperSpec(
            skillId: "local-embeddings",
            displayName: "Local Embeddings",
            description: "Run Hub local embedding generation through XT governed dispatch when a runnable embedding model is available.",
            taskKind: "embedding",
            capability: "ai.embed.local",
            sideEffectClass: "read_only",
            riskLevel: .low,
            timeoutMs: 15_000,
            maxRetries: 0
        ),
        BuiltinLocalTaskWrapperSpec(
            skillId: "local-transcribe",
            displayName: "Local Transcribe",
            description: "Run Hub local speech-to-text through XT governed dispatch when a runnable transcription model is available.",
            taskKind: "speech_to_text",
            capability: "ai.audio.local",
            sideEffectClass: "read_only",
            riskLevel: .medium,
            timeoutMs: 45_000,
            maxRetries: 0
        ),
        BuiltinLocalTaskWrapperSpec(
            skillId: "local-vision",
            displayName: "Local Vision",
            description: "Run Hub local image understanding through XT governed dispatch when a runnable multimodal vision model is available.",
            taskKind: "vision_understand",
            capability: "ai.vision.local",
            sideEffectClass: "read_only",
            riskLevel: .medium,
            timeoutMs: 45_000,
            maxRetries: 0
        ),
        BuiltinLocalTaskWrapperSpec(
            skillId: "local-ocr",
            displayName: "Local OCR",
            description: "Run Hub local OCR through XT governed dispatch when a runnable OCR-capable vision model is available.",
            taskKind: "ocr",
            capability: "ai.vision.local",
            sideEffectClass: "read_only",
            riskLevel: .medium,
            timeoutMs: 45_000,
            maxRetries: 0
        ),
        BuiltinLocalTaskWrapperSpec(
            skillId: "local-tts",
            displayName: "Local TTS",
            description: "Run Hub local text-to-speech through XT governed dispatch when a runnable local TTS model is available.",
            taskKind: "text_to_speech",
            capability: "ai.audio.tts.local",
            sideEffectClass: "local_side_effect",
            riskLevel: .low,
            timeoutMs: 45_000,
            maxRetries: 0
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
        let trustedPublisherIDs = Set(
            trusted.publishers
                .filter(\.enabled)
                .map(\.publisherID)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let relevantPins = relevantPinScopes(pins: pins, projectId: projectId)
        let pinnedScopesBySkill = Dictionary(grouping: relevantPins, by: \.skillID)
            .mapValues { pins in
                Array(Set(pins.map(\.scope))).sorted()
            }
        let activePinnedScopesBySkillPackage = Dictionary(grouping: relevantPins) { pin in
            skillPackagePinKey(skillID: pin.skillID, packageSHA256: pin.packageSHA256)
        }
        .mapValues { pins in
            normalizePinScopes(pins.map(\.scope))
        }

        let installedSkills = hubIndex.skills.map { skill in
            let isRevoked = revocations.revokedSHA256.contains(skill.packageSHA256)
                || revocations.revokedSkillIDs.contains(skill.skillID)
                || revocations.revokedPublisherIDs.contains(skill.publisherID)
            let allPinnedScopes = normalizePinScopes(pinnedScopesBySkill[skill.skillID] ?? [])
            let activePinnedScopes = activePinnedScopesBySkillPackage[
                skillPackagePinKey(skillID: skill.skillID, packageSHA256: skill.packageSHA256)
            ] ?? []
            let inactivePinnedScopes = normalizePinScopes(
                allPinnedScopes.filter { !activePinnedScopes.contains($0) }
            )
            let manifestHints = parseSupervisorSkillManifestHints(
                skill.manifestJSON,
                fallbackSkillId: skill.skillID,
                fallbackDescription: firstNonEmptySkillText(skill.description, skill.installHint, skill.name),
                capabilityFallback: skill.capabilitiesRequired
            )
            let semanticCapabilities = manifestHints.capabilitiesRequired.isEmpty
                ? skill.capabilitiesRequired
                : manifestHints.capabilitiesRequired
            let derivedSemantics = normalizedCapabilitySemantics(
                skillId: skill.skillID,
                capabilitiesRequired: semanticCapabilities,
                declaredIntentFamilies: skill.intentFamilies,
                declaredCapabilityFamilies: skill.capabilityFamilies,
                declaredCapabilityProfiles: skill.capabilityProfiles,
                declaredGrantFloor: skill.grantFloor,
                declaredApprovalFloor: skill.approvalFloor
            )
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
                intentFamilies: derivedSemantics.intentFamilies,
                capabilityFamilies: derivedSemantics.capabilityFamilies,
                capabilityProfiles: derivedSemantics.capabilityProfiles,
                grantFloor: derivedSemantics.grantFloor,
                approvalFloor: derivedSemantics.approvalFloor,
                capabilitiesRequired: semanticCapabilities,
                riskLevel: skill.riskLevel,
                requiresGrant: skill.requiresGrant,
                trustTier: skill.trustTier,
                packageState: skill.packageState,
                revokeState: skill.revokeState,
                supportTier: skill.supportTier,
                entrypointRuntime: skill.entrypointRuntime,
                entrypointCommand: skill.entrypointCommand,
                entrypointArgs: skill.entrypointArgs,
                compatibilityEnvelope: skill.compatibilityEnvelope,
                qualityEvidenceStatus: skill.qualityEvidenceStatus,
                artifactIntegrity: skill.artifactIntegrity,
                signatureVerified: skill.signatureVerified,
                signatureBypassed: skill.signatureBypassed,
                mappingAliasesUsed: skill.mappingAliasesUsed,
                defaultsApplied: skill.defaultsApplied,
                pinnedScopes: allPinnedScopes,
                activePinnedScopes: activePinnedScopes,
                inactivePinnedScopes: inactivePinnedScopes,
                publisherTrusted: trustedPublisherIDs.contains(skill.publisherID),
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
            var intentFamilies: [String]
            var capabilityFamilies: [String]
            var capabilityProfiles: [String]
            var grantFloor: String
            var approvalFloor: String
            var capabilitiesRequired: [String]
            var riskLevel: String
            var requiresGrant: Bool
            var trustTier: String
            var packageState: String
            var revokeState: String
            var supportTier: String
            var entrypointRuntime: String
            var entrypointCommand: String
            var entrypointArgs: [String]
            var compatibilityEnvelope: AXHubSkillCompatibilityEnvelope
            var qualityEvidenceStatus: AXHubSkillQualityEvidenceStatus
            var artifactIntegrity: AXHubSkillArtifactIntegrity
            var signatureVerified: Bool
            var signatureBypassed: Bool
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
                case intentFamilies = "intent_families"
                case capabilityFamilies = "capability_families"
                case capabilityProfiles = "capability_profiles"
                case grantFloor = "grant_floor"
                case approvalFloor = "approval_floor"
                case capabilitiesRequired = "capabilities_required"
                case riskLevel = "risk_level"
                case requiresGrant = "requires_grant"
                case trustTier = "trust_tier"
                case packageState = "package_state"
                case revokeState = "revoke_state"
                case supportTier = "support_tier"
                case entrypointRuntime = "entrypoint_runtime"
                case entrypointCommand = "entrypoint_command"
                case entrypointArgs = "entrypoint_args"
                case compatibilityEnvelope = "compatibility_envelope"
                case qualityEvidenceStatus = "quality_evidence_status"
                case artifactIntegrity = "artifact_integrity"
                case signatureVerified = "signature_verified"
                case signatureBypassed = "signature_bypassed"
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
                intentFamilies = (try? container.decode([String].self, forKey: .intentFamilies)) ?? []
                capabilityFamilies = (try? container.decode([String].self, forKey: .capabilityFamilies)) ?? []
                capabilityProfiles = (try? container.decode([String].self, forKey: .capabilityProfiles)) ?? []
                grantFloor = (try? container.decode(String.self, forKey: .grantFloor)) ?? XTSkillGrantFloor.none.rawValue
                approvalFloor = (try? container.decode(String.self, forKey: .approvalFloor)) ?? XTSkillApprovalFloor.none.rawValue
                capabilitiesRequired = (try? container.decode([String].self, forKey: .capabilitiesRequired)) ?? []
                riskLevel = (try? container.decode(String.self, forKey: .riskLevel)) ?? ""
                requiresGrant = (try? container.decode(Bool.self, forKey: .requiresGrant)) ?? false
                trustTier = (try? container.decode(String.self, forKey: .trustTier)) ?? ""
                packageState = (try? container.decode(String.self, forKey: .packageState)) ?? ""
                revokeState = (try? container.decode(String.self, forKey: .revokeState)) ?? ""
                supportTier = (try? container.decode(String.self, forKey: .supportTier)) ?? ""
                entrypointRuntime = (try? container.decode(String.self, forKey: .entrypointRuntime)) ?? ""
                entrypointCommand = (try? container.decode(String.self, forKey: .entrypointCommand)) ?? ""
                entrypointArgs = (try? container.decode([String].self, forKey: .entrypointArgs)) ?? []
                compatibilityEnvelope = (try? container.decode(
                    AXHubSkillCompatibilityEnvelope.self,
                    forKey: .compatibilityEnvelope
                )) ?? .init()
                qualityEvidenceStatus = (try? container.decode(
                    AXHubSkillQualityEvidenceStatus.self,
                    forKey: .qualityEvidenceStatus
                )) ?? .init()
                artifactIntegrity = (try? container.decode(
                    AXHubSkillArtifactIntegrity.self,
                    forKey: .artifactIntegrity
                )) ?? .init()
                signatureVerified = (try? container.decode(Bool.self, forKey: .signatureVerified)) ?? false
                signatureBypassed = (try? container.decode(Bool.self, forKey: .signatureBypassed)) ?? false
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

    private static func skillPackagePinKey(skillID: String, packageSHA256: String) -> String {
        "\(skillID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())::\(packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private static func normalizePinScopes(_ scopes: [String]) -> [String] {
        let priority: [String: Int] = [
            "memory_core": 0,
            "global": 1,
            "project": 2,
        ]
        return Array(
            Set(
                scopes
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { lhs, rhs in
            let leftPriority = priority[lhs, default: 99]
            let rightPriority = priority[rhs, default: 99]
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            return lhs < rhs
        }
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
        let builtinItems = builtinSupervisorRegistryItems(hubBaseDir: resolvedHubBaseDir)
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
            builtinItems: builtinItems
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
                return builtinItems.isEmpty ? "hub_skill_registry" : "hub_skill_registry+xt_builtin"
            }
            return builtinItems.isEmpty ? "hub_skill_registry_unavailable" : "xt_builtin_skill_registry"
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

    static func preferredSupervisorSkillRegistrySnapshot(
        projectId: String,
        projectName: String? = nil,
        projectRoot: URL,
        hubBaseDir: URL? = nil
    ) -> SupervisorSkillRegistrySnapshot? {
        let context = AXProjectContext(root: projectRoot)
        if let activeCache = XTResolvedSkillsCacheStore.activeSnapshot(for: context) {
            return supervisorSkillRegistrySnapshot(
                fromResolvedCache: activeCache
            )
        }
        return supervisorSkillRegistrySnapshot(
            projectId: projectId,
            projectName: projectName,
            hubBaseDir: hubBaseDir
        )
    }

    static func persistedRemoteResolvedSkillsCacheSnapshot(
        projectId: String,
        projectName: String? = nil,
        projectRoot: URL,
        config: AXProjectConfig? = nil,
        hubBaseDir: URL? = nil
    ) -> XTResolvedSkillsCacheSnapshot? {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return nil }

        let context = AXProjectContext(root: projectRoot)
        guard XTResolvedSkillsCacheStore.activeSnapshot(for: context) == nil,
              let snapshot = XTResolvedSkillsCacheStore.load(for: context) else {
            return nil
        }
        guard snapshot.projectId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedProjectId else {
            return nil
        }
        guard snapshot.remoteStateDirPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        let epochState = resolvedSkillsCacheEpochState(
            projectId: normalizedProjectId,
            projectName: projectName,
            projectRoot: projectRoot,
            config: config,
            hubBaseDir: hubBaseDir ?? HubPaths.baseDir()
        )
        guard snapshot.profileEpoch == epochState.profileEpoch,
              snapshot.trustRootSetHash == epochState.trustRootSetHash,
              snapshot.revocationEpoch == epochState.revocationEpoch,
              snapshot.officialChannelSnapshotID == epochState.officialChannelSnapshotID,
              snapshot.runtimeSurfaceHash == epochState.runtimeSurfaceHash else {
            return nil
        }

        return XTResolvedSkillsCacheSnapshot(
            schemaVersion: snapshot.schemaVersion,
            projectId: snapshot.projectId,
            projectName: firstNonEmptySkillText(projectName ?? "", snapshot.projectName ?? ""),
            resolvedSnapshotId: snapshot.resolvedSnapshotId,
            source: snapshot.source,
            grantSnapshotRef: snapshot.grantSnapshotRef,
            auditRef: snapshot.auditRef,
            resolvedAtMs: snapshot.resolvedAtMs,
            expiresAtMs: snapshot.expiresAtMs,
            hubIndexUpdatedAtMs: snapshot.hubIndexUpdatedAtMs,
            profileEpoch: snapshot.profileEpoch,
            trustRootSetHash: snapshot.trustRootSetHash,
            revocationEpoch: snapshot.revocationEpoch,
            officialChannelSnapshotID: snapshot.officialChannelSnapshotID,
            runtimeSurfaceHash: snapshot.runtimeSurfaceHash,
            remoteStateDirPath: snapshot.remoteStateDirPath,
            items: snapshot.items
        )
    }

    static func supervisorGlobalSkillRegistrySnapshot(
        hubBaseDir: URL? = nil
    ) -> SupervisorSkillRegistrySnapshot {
        let resolvedHubBaseDir = hubBaseDir ?? HubPaths.baseDir()
        let indexURL = resolvedHubBaseDir
            .appendingPathComponent("skills_store", isDirectory: true)
            .appendingPathComponent("skills_store_index.json")
        let hubIndex = loadHubSkillsIndex(url: indexURL)
        let updatedAtMs = hubIndex.available ? loadHubSkillsIndexUpdatedAtMs(url: indexURL) : 0
        return SupervisorSkillRegistrySnapshot(
            schemaVersion: SupervisorSkillRegistrySnapshot.currentSchemaVersion,
            projectId: "supervisor-global",
            projectName: "Supervisor Global",
            updatedAtMs: max(0, updatedAtMs),
            memorySource: "supervisor_global_skill_registry",
            items: supervisorGlobalRegistryItems(),
            auditRef: "audit-xt-supervisor-global-skill-registry"
        )
    }

    static func supervisorSkillRegistrySnapshot(
        fromResolvedCache snapshot: XTResolvedSkillsCacheSnapshot
    ) -> SupervisorSkillRegistrySnapshot {
        SupervisorSkillRegistrySnapshot(
            schemaVersion: SupervisorSkillRegistrySnapshot.currentSchemaVersion,
            projectId: snapshot.projectId,
            projectName: snapshot.projectName,
            updatedAtMs: snapshot.resolvedAtMs,
            memorySource: snapshot.source,
            items: snapshot.items
                .map(supervisorSkillRegistryItem(cacheItem:))
                .sorted { lhs, rhs in
                    let leftScope = skillPinnedScopePriority(lhs.policyScope)
                    let rightScope = skillPinnedScopePriority(rhs.policyScope)
                    if leftScope != rightScope {
                        return leftScope > rightScope
                    }
                    return lhs.skillId.localizedCaseInsensitiveCompare(rhs.skillId) == .orderedAscending
                },
            auditRef: snapshot.auditRef
        )
    }

    static func resolvedSkillsCacheSnapshot(
        projectId: String,
        projectName: String? = nil,
        projectRoot: URL? = nil,
        config: AXProjectConfig? = nil,
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
        let builtinCacheItems = builtinResolvedSkillCacheItems(hubBaseDir: resolvedHubBaseDir)

        let hubIndex = loadHubSkillsIndex(url: indexURL)
        guard hubIndex.available || !builtinCacheItems.isEmpty else { return nil }

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
            let semanticCapabilities = hints.capabilitiesRequired.isEmpty
                ? skill.capabilitiesRequired
                : hints.capabilitiesRequired
            let derivedSemantics = normalizedCapabilitySemantics(
                skillId: skill.skillID,
                capabilitiesRequired: semanticCapabilities,
                declaredIntentFamilies: skill.intentFamilies,
                declaredCapabilityFamilies: skill.capabilityFamilies,
                declaredCapabilityProfiles: skill.capabilityProfiles,
                declaredGrantFloor: skill.grantFloor,
                declaredApprovalFloor: skill.approvalFloor
            )
            return XTResolvedSkillCacheItem(
                skillId: skill.skillID,
                displayName: firstNonEmptySkillText(skill.name, skill.skillID),
                description: hints.description,
                packageSHA256: sha,
                canonicalManifestSHA256: skill.canonicalManifestSHA256,
                publisherID: skill.publisherID,
                sourceId: skill.sourceID,
                pinScope: pin.scope,
                capabilitiesRequired: semanticCapabilities,
                intentFamilies: derivedSemantics.intentFamilies,
                capabilityFamilies: derivedSemantics.capabilityFamilies,
                capabilityProfiles: derivedSemantics.capabilityProfiles,
                grantFloor: derivedSemantics.grantFloor,
                approvalFloor: derivedSemantics.approvalFloor,
                riskLevel: hints.riskLevel.rawValue,
                requiresGrant: hints.requiresGrant,
                sideEffectClass: hints.sideEffectClass,
                governedDispatch: hints.governedDispatch,
                governedDispatchVariants: hints.governedDispatchVariants,
                governedDispatchNotes: hints.governedDispatchNotes,
                inputSchemaRef: hints.inputSchemaRef.isEmpty ? "schema://\(skill.skillID).input" : hints.inputSchemaRef,
                outputSchemaRef: hints.outputSchemaRef.isEmpty ? "schema://\(skill.skillID).output" : hints.outputSchemaRef,
                timeoutMs: max(1_000, hints.timeoutMs),
                maxRetries: max(0, hints.maxRetries)
            )
        }
        let items = mergedResolvedSkillCacheItems(
            hubItems: hubItems,
            builtinItems: builtinCacheItems
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
        let epochState = resolvedSkillsCacheEpochState(
            projectId: normalizedProjectId,
            projectName: projectName,
            projectRoot: projectRoot,
            config: config,
            hubBaseDir: resolvedHubBaseDir
        )

        return XTResolvedSkillsCacheSnapshot(
            schemaVersion: XTResolvedSkillsCacheSnapshot.currentSchemaVersion,
            projectId: normalizedProjectId,
            projectName: projectName,
            resolvedSnapshotId: "xt-resolved-skills-\(projectSuffix)-\(resolvedAt)",
            source: builtinCacheItems.isEmpty ? "hub_resolved_skills_snapshot" : "hub_resolved_skills_snapshot+xt_builtin",
            grantSnapshotRef: grantSnapshotRef,
            auditRef: "audit-xt-w3-34-i-resolved-skills-\(projectSuffix)",
            resolvedAtMs: resolvedAt,
            expiresAtMs: resolvedAt + normalizedTTL,
            hubIndexUpdatedAtMs: max(0, loadHubSkillsIndexUpdatedAtMs(url: indexURL)),
            profileEpoch: epochState.profileEpoch,
            trustRootSetHash: epochState.trustRootSetHash,
            revocationEpoch: epochState.revocationEpoch,
            officialChannelSnapshotID: epochState.officialChannelSnapshotID,
            runtimeSurfaceHash: epochState.runtimeSurfaceHash,
            remoteStateDirPath: nil,
            items: items
        )
    }

    static func resolvedSkillsCacheSnapshot(
        projectId: String,
        projectName: String? = nil,
        resolvedSkills: [HubIPCClient.ResolvedSkillEntry],
        manifestJSONBySHA: [String: String],
        source: String,
        projectRoot: URL? = nil,
        config: AXProjectConfig? = nil,
        hubBaseDir: URL? = nil,
        remoteStateDirPath: String? = nil,
        ttlMs: Int64 = 15 * 60 * 1000,
        nowMs: Int64? = nil
    ) -> XTResolvedSkillsCacheSnapshot? {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return nil }

        let resolvedHubBaseDir = hubBaseDir ?? HubPaths.baseDir()
        let builtinCacheItems = builtinResolvedSkillCacheItems(hubBaseDir: resolvedHubBaseDir)
        let effectiveNow = nowMs ?? Int64(Date().timeIntervalSince1970 * 1000.0)
        let normalizedProjectName = projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRemoteStateDirPath: String? = {
            let trimmed = (remoteStateDirPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return NSString(string: trimmed).expandingTildeInPath
        }()
        let epochState = resolvedSkillsCacheEpochState(
            projectId: normalizedProjectId,
            projectName: normalizedProjectName,
            projectRoot: projectRoot,
            config: config,
            hubBaseDir: resolvedHubBaseDir
        )

        let hubItems = resolvedSkills.compactMap { entry -> XTResolvedSkillCacheItem? in
            let skill = entry.skill
            let skillID = skill.skillID.trimmingCharacters(in: .whitespacesAndNewlines)
            let packageSHA256 = skill.packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !skillID.isEmpty, !packageSHA256.isEmpty else { return nil }

            let rawManifest = manifestJSONBySHA[packageSHA256] ?? ""
            let hints = parseSupervisorSkillManifestHints(
                rawManifest,
                fallbackSkillId: skillID,
                fallbackDescription: firstNonEmptySkillText(skill.description, skill.installHint, skill.name),
                capabilityFallback: skill.capabilitiesRequired
            )
            let semanticCapabilities = hints.capabilitiesRequired.isEmpty
                ? skill.capabilitiesRequired
                : hints.capabilitiesRequired
            let derivedSemantics = normalizedCapabilitySemantics(
                skillId: skillID,
                capabilitiesRequired: semanticCapabilities,
                declaredIntentFamilies: [],
                declaredCapabilityFamilies: [],
                declaredCapabilityProfiles: [],
                declaredGrantFloor: "",
                declaredApprovalFloor: ""
            )

            return XTResolvedSkillCacheItem(
                skillId: skillID,
                displayName: firstNonEmptySkillText(skill.name, skillID),
                description: hints.description,
                packageSHA256: packageSHA256,
                canonicalManifestSHA256: sha256Hex(rawManifest),
                publisherID: skill.publisherID,
                sourceId: skill.sourceID,
                pinScope: entry.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                capabilitiesRequired: semanticCapabilities,
                intentFamilies: derivedSemantics.intentFamilies,
                capabilityFamilies: derivedSemantics.capabilityFamilies,
                capabilityProfiles: derivedSemantics.capabilityProfiles,
                grantFloor: derivedSemantics.grantFloor,
                approvalFloor: derivedSemantics.approvalFloor,
                riskLevel: normalizedRiskLevel(skill.riskLevel)?.rawValue ?? hints.riskLevel.rawValue,
                requiresGrant: skill.requiresGrant || hints.requiresGrant,
                sideEffectClass: firstNonEmptySkillText(skill.sideEffectClass, hints.sideEffectClass),
                governedDispatch: hints.governedDispatch,
                governedDispatchVariants: hints.governedDispatchVariants,
                governedDispatchNotes: hints.governedDispatchNotes,
                inputSchemaRef: hints.inputSchemaRef.isEmpty ? "schema://\(skillID).input" : hints.inputSchemaRef,
                outputSchemaRef: hints.outputSchemaRef.isEmpty ? "schema://\(skillID).output" : hints.outputSchemaRef,
                timeoutMs: max(1_000, hints.timeoutMs),
                maxRetries: max(0, hints.maxRetries)
            )
        }

        let items = mergedResolvedSkillCacheItems(
            hubItems: hubItems,
            builtinItems: builtinCacheItems
        )
        .sorted { lhs, rhs in
            let leftScope = skillPinnedScopePriority(lhs.pinScope)
            let rightScope = skillPinnedScopePriority(rhs.pinScope)
            if leftScope != rightScope {
                return leftScope > rightScope
            }
            return lhs.skillId.localizedCaseInsensitiveCompare(rhs.skillId) == .orderedAscending
        }

        guard !items.isEmpty else { return nil }

        let sourcePrefix = normalizedSourceToken(source).isEmpty
            ? "hub_runtime_grpc_resolved_skills_snapshot"
            : "\(normalizedSourceToken(source))_resolved_skills_snapshot"
        let sourceValue = builtinCacheItems.isEmpty
            ? sourcePrefix
            : "\(sourcePrefix)+xt_builtin"

        return XTResolvedSkillsCacheSnapshot(
            schemaVersion: XTResolvedSkillsCacheSnapshot.currentSchemaVersion,
            projectId: normalizedProjectId,
            projectName: normalizedProjectName,
            resolvedSnapshotId: "xt-remote-resolved-skills-\(String(normalizedProjectId.suffix(8)))-\(effectiveNow)",
            source: sourceValue,
            grantSnapshotRef: "grant-chain:\(String(normalizedProjectId.suffix(8))):refresh_required",
            auditRef: "audit-xt-remote-resolved-skills-\(String(normalizedProjectId.suffix(8)))",
            resolvedAtMs: effectiveNow,
            expiresAtMs: effectiveNow + max(1_000, ttlMs),
            hubIndexUpdatedAtMs: 0,
            profileEpoch: epochState.profileEpoch,
            trustRootSetHash: epochState.trustRootSetHash,
            revocationEpoch: epochState.revocationEpoch,
            officialChannelSnapshotID: epochState.officialChannelSnapshotID,
            runtimeSurfaceHash: epochState.runtimeSurfaceHash,
            remoteStateDirPath: normalizedRemoteStateDirPath,
            items: items
        )
    }

    static func projectEffectiveSkillProfileSnapshot(
        projectId: String,
        projectName: String? = nil,
        projectRoot: URL,
        config: AXProjectConfig? = nil,
        hubBaseDir: URL? = nil
    ) -> XTProjectEffectiveSkillProfileSnapshot {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedConfig = config ?? .default(forProjectRoot: projectRoot)
        let resolvedHubBaseDir = hubBaseDir ?? HubPaths.baseDir()
        let baseState = projectSkillProfileBaseState(
            projectId: normalizedProjectId,
            projectName: projectName,
            projectRoot: projectRoot,
            config: resolvedConfig,
            hubBaseDir: resolvedHubBaseDir
        )
        let storeDir = resolvedHubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
        let indexURL = storeDir.appendingPathComponent("skills_store_index.json")
        let revocationsURL = storeDir.appendingPathComponent("skill_revocations.json")
        let hubIndex = loadHubSkillsIndex(url: indexURL)
        let revocations = loadSkillRevocations(url: revocationsURL)
        let context = AXProjectContext(root: projectRoot)
        let activeResolvedSnapshot = XTResolvedSkillsCacheStore.activeSnapshot(for: context)
            ?? persistedRemoteResolvedSkillsCacheSnapshot(
                projectId: normalizedProjectId,
                projectName: projectName,
                projectRoot: projectRoot,
                config: resolvedConfig,
                hubBaseDir: resolvedHubBaseDir
            )
        let registrySnapshot = activeResolvedSnapshot.map {
            supervisorSkillRegistrySnapshot(fromResolvedCache: $0)
        } ?? preferredSupervisorSkillRegistrySnapshot(
            projectId: normalizedProjectId,
            projectName: projectName,
            projectRoot: projectRoot,
            hubBaseDir: resolvedHubBaseDir
        )
        let epochState = resolvedSkillsCacheEpochState(
            projectId: normalizedProjectId,
            projectName: projectName,
            projectRoot: projectRoot,
            config: resolvedConfig,
            hubBaseDir: resolvedHubBaseDir
        )

        var installableProfiles: [String] = builtinSupervisorRegistryItems(hubBaseDir: resolvedHubBaseDir)
            .flatMap(\.capabilityProfiles)
        for skill in hubIndex.skills {
            let sha = skill.packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isRevoked = revocations.revokedSHA256.contains(sha)
                || revocations.revokedSkillIDs.contains(skill.skillID)
                || revocations.revokedPublisherIDs.contains(skill.publisherID)
            guard !isRevoked else { continue }
            guard skill.compatibilityState != .unsupported else { continue }
            guard skill.abiCompatVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { continue }
            let packageState = skill.packageState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard packageState != "quarantined" else { continue }
            let doctorState = skill.qualityEvidenceStatus.doctor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard doctorState != "failed" else { continue }
            let hints = parseSupervisorSkillManifestHints(
                skill.manifestJSON,
                fallbackSkillId: skill.skillID,
                fallbackDescription: firstNonEmptySkillText(skill.description, skill.installHint, skill.name),
                capabilityFallback: skill.capabilitiesRequired
            )
            let semanticCapabilities = hints.capabilitiesRequired.isEmpty
                ? skill.capabilitiesRequired
                : hints.capabilitiesRequired
            let derived = normalizedCapabilitySemantics(
                skillId: skill.skillID,
                capabilitiesRequired: semanticCapabilities,
                declaredIntentFamilies: skill.intentFamilies,
                declaredCapabilityFamilies: skill.capabilityFamilies,
                declaredCapabilityProfiles: skill.capabilityProfiles,
                declaredGrantFloor: skill.grantFloor,
                declaredApprovalFloor: skill.approvalFloor
            )
            installableProfiles.append(contentsOf: derived.capabilityProfiles)
        }
        installableProfiles = XTSkillCapabilityProfileSupport.orderedProfiles(
            installableProfiles.filter { baseState.discoverableProfiles.contains($0) }
        )

        var runnableProfiles: [String] = []
        var requestableProfiles: [String] = []
        var grantRequiredProfiles: [String] = []
        var approvalRequiredProfiles: [String] = []
        var runnableCapabilityFamilies: [String] = []
        var blockedProfilesByID: [String: XTProjectEffectiveSkillBlockedProfile] = [:]

        for item in registrySnapshot?.items ?? [] {
            let baseReadiness = skillExecutionReadiness(
                skillId: item.skillId,
                projectId: normalizedProjectId,
                projectName: projectName,
                projectRoot: projectRoot,
                config: resolvedConfig,
                registryItem: item,
                hubBaseDir: resolvedHubBaseDir
            )
            let readiness = XTSkillCapabilityProfileSupport.effectiveReadinessForRequestScopedGrantOverride(
                readiness: baseReadiness,
                registryItem: item
            )
            let readinessState = XTSkillCapabilityProfileSupport.readinessState(from: readiness.executionReadiness)
            let profiles = readiness.capabilityProfiles.filter { baseState.discoverableProfiles.contains($0) }

            switch readinessState {
            case .ready:
                runnableProfiles.append(contentsOf: profiles)
                requestableProfiles.append(contentsOf: profiles)
                runnableCapabilityFamilies.append(contentsOf: readiness.capabilityFamilies)
            case .grantRequired:
                grantRequiredProfiles.append(contentsOf: profiles)
                requestableProfiles.append(contentsOf: profiles)
            case .localApprovalRequired:
                approvalRequiredProfiles.append(contentsOf: profiles)
                requestableProfiles.append(contentsOf: profiles)
            case .degraded:
                requestableProfiles.append(contentsOf: profiles)
                for profile in profiles {
                    blockedProfilesByID[profile] = XTProjectEffectiveSkillBlockedProfile(
                        profileID: profile,
                        reasonCode: readiness.reasonCode,
                        state: readiness.executionReadiness,
                        source: readiness.requiredRuntimeSurfaces.first ?? readiness.policyScope,
                        unblockActions: readiness.unblockActions
                    )
                }
            case .policyClamped, .runtimeUnavailable, .hubDisconnected, .quarantined, .revoked, .unsupported:
                for profile in profiles {
                    blockedProfilesByID[profile] = XTProjectEffectiveSkillBlockedProfile(
                        profileID: profile,
                        reasonCode: readiness.reasonCode,
                        state: readiness.executionReadiness,
                        source: readiness.requiredRuntimeSurfaces.first ?? readiness.policyScope,
                        unblockActions: readiness.unblockActions
                    )
                }
            case .notInstalled, .none:
                break
            }
        }

        runnableProfiles = XTSkillCapabilityProfileSupport.orderedProfiles(runnableProfiles)
        requestableProfiles = XTSkillCapabilityProfileSupport.orderedProfiles(requestableProfiles)
        grantRequiredProfiles = XTSkillCapabilityProfileSupport.orderedProfiles(grantRequiredProfiles)
        approvalRequiredProfiles = XTSkillCapabilityProfileSupport.orderedProfiles(approvalRequiredProfiles)
        runnableCapabilityFamilies = XTSkillCapabilityProfileSupport.orderedCapabilityFamilies(runnableCapabilityFamilies)

        let activeProfileSet = Set(
            requestableProfiles + runnableProfiles + grantRequiredProfiles + approvalRequiredProfiles
        )
        for profile in baseState.discoverableProfiles where !activeProfileSet.contains(profile) {
            if blockedProfilesByID[profile] != nil {
                continue
            }
            blockedProfilesByID[profile] = XTProjectEffectiveSkillBlockedProfile(
                profileID: profile,
                reasonCode: installableProfiles.contains(profile)
                    ? "profile_not_resolved"
                    : "profile_not_installable",
                state: XTSkillExecutionReadinessState.notInstalled.rawValue,
                source: installableProfiles.contains(profile) ? "hub_skill_registry" : "hub_catalog",
                unblockActions: XTSkillCapabilityProfileSupport.unblockActions(
                    for: .notInstalled,
                    approvalFloor: XTSkillApprovalFloor.none.rawValue,
                    requiredRuntimeSurfaces: []
                )
            )
        }

        for profile in activeProfileSet {
            blockedProfilesByID.removeValue(forKey: profile)
        }

        let blockedProfiles = XTSkillCapabilityProfileSupport.orderedProfiles(
            Array(blockedProfilesByID.keys)
        )
        .compactMap { blockedProfilesByID[$0] }

        return XTProjectEffectiveSkillProfileSnapshot(
            schemaVersion: XTProjectEffectiveSkillProfileSnapshot.currentSchemaVersion,
            projectId: normalizedProjectId,
            projectName: baseState.projectName,
            source: hubIndex.available ? "xt_project_governance+hub_skill_registry" : "xt_project_governance+xt_builtin",
            executionTier: baseState.executionTier.rawValue,
            runtimeSurfaceMode: baseState.effectiveRuntimeSurface.effectiveMode.rawValue,
            hubOverrideMode: baseState.effectiveRuntimeSurface.hubOverrideMode.rawValue,
            legacyToolProfile: baseState.legacyToolProfile,
            discoverableProfiles: baseState.discoverableProfiles,
            installableProfiles: installableProfiles,
            requestableProfiles: requestableProfiles,
            runnableNowProfiles: runnableProfiles,
            grantRequiredProfiles: grantRequiredProfiles,
            approvalRequiredProfiles: approvalRequiredProfiles,
            blockedProfiles: blockedProfiles,
            ceilingCapabilityFamilies: baseState.ceilingCapabilityFamilies,
            runnableCapabilityFamilies: runnableCapabilityFamilies,
            localAutoApproveEnabled: baseState.localAutoApproveEnabled,
            trustedAutomationReady: baseState.trustedAutomationStatus.trustedAutomationReady,
            profileEpoch: epochState.profileEpoch,
            trustRootSetHash: epochState.trustRootSetHash,
            revocationEpoch: epochState.revocationEpoch,
            officialChannelSnapshotID: epochState.officialChannelSnapshotID,
            runtimeSurfaceHash: epochState.runtimeSurfaceHash,
            auditRef: "audit-xt-skill-profile-\(String(normalizedProjectId.suffix(8)))"
        )
    }

    static func skillExecutionReadiness(
        skillId: String,
        projectId: String,
        projectName: String? = nil,
        projectRoot: URL,
        config: AXProjectConfig? = nil,
        registryItem: SupervisorSkillRegistryItem? = nil,
        hubBaseDir: URL? = nil
    ) -> XTSkillExecutionReadiness {
        let canonicalSkillId = canonicalSupervisorSkillID(skillId)
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedConfig = config ?? .default(forProjectRoot: projectRoot)
        let resolvedHubBaseDir = hubBaseDir ?? HubPaths.baseDir()
        let baseState = projectSkillProfileBaseState(
            projectId: normalizedProjectId,
            projectName: projectName,
            projectRoot: projectRoot,
            config: resolvedConfig,
            hubBaseDir: resolvedHubBaseDir
        )
        let doctorSnapshot = compatibilityDoctorSnapshot(
            projectId: normalizedProjectId,
            projectName: projectName,
            hubBaseDir: resolvedHubBaseDir
        )
        let context = AXProjectContext(root: projectRoot)
        let resolvedSnapshot = XTResolvedSkillsCacheStore.activeSnapshot(for: context)
            ?? persistedRemoteResolvedSkillsCacheSnapshot(
                projectId: normalizedProjectId,
                projectName: projectName,
                projectRoot: projectRoot,
                config: resolvedConfig,
                hubBaseDir: resolvedHubBaseDir
            )
            ?? resolvedSkillsCacheSnapshot(
                projectId: normalizedProjectId,
                projectName: projectName,
                projectRoot: projectRoot,
                config: resolvedConfig,
                hubBaseDir: resolvedHubBaseDir
            )
        let globalRegistryFallbackItem = supervisorGlobalSkillRegistrySnapshot(
            hubBaseDir: resolvedHubBaseDir
        ).items.first(where: {
            canonicalSupervisorSkillID($0.skillId) == canonicalSkillId
        })
        let resolvedRegistryItem = registryItem ?? preferredSupervisorSkillRegistrySnapshot(
            projectId: normalizedProjectId,
            projectName: projectName,
            projectRoot: projectRoot,
            hubBaseDir: resolvedHubBaseDir
        )?.items.first(where: {
            canonicalSupervisorSkillID($0.skillId) == canonicalSkillId
        }) ?? globalRegistryFallbackItem
        let resolvedCacheItem = selectedResolvedSkillItem(skillId: canonicalSkillId, snapshot: resolvedSnapshot)
        let installedSkill = selectedInstalledSkill(skillId: canonicalSkillId, snapshot: doctorSnapshot)

        let capabilitySemantics = normalizedCapabilitySemantics(
            skillId: canonicalSkillId,
            capabilitiesRequired: installedSkill?.capabilitiesRequired
                ?? resolvedRegistryItem?.capabilitiesRequired
                ?? [],
            declaredIntentFamilies: resolvedCacheItem?.intentFamilies
                ?? installedSkill?.intentFamilies
                ?? resolvedRegistryItem?.intentFamilies
                ?? [],
            declaredCapabilityFamilies: resolvedCacheItem?.capabilityFamilies
                ?? installedSkill?.capabilityFamilies
                ?? resolvedRegistryItem?.capabilityFamilies
                ?? [],
            declaredCapabilityProfiles: resolvedCacheItem?.capabilityProfiles
                ?? installedSkill?.capabilityProfiles
                ?? resolvedRegistryItem?.capabilityProfiles
                ?? [],
            declaredGrantFloor: resolvedCacheItem?.grantFloor
                ?? installedSkill?.grantFloor
                ?? resolvedRegistryItem?.grantFloor
                ?? "",
            declaredApprovalFloor: resolvedCacheItem?.approvalFloor
                ?? installedSkill?.approvalFloor
                ?? resolvedRegistryItem?.approvalFloor
                ?? ""
        )

        let policyScope = firstNonEmptySkillText(
            resolvedCacheItem?.pinScope ?? "",
            resolvedRegistryItem?.policyScope ?? "",
            installedSkill?.activePinnedScopes.first ?? "",
            installedSkill?.pinnedScopes.first ?? "",
            resolvedRegistryItem == nil ? "" : "xt_builtin"
        )
        let virtualGlobalRegistryAvailability = {
            guard resolvedCacheItem == nil,
                  installedSkill == nil,
                  let resolvedRegistryItem else { return false }
            let sourceID = resolvedRegistryItem.sourceID
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let normalizedPolicyScope = policyScope
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard sourceID == "xt_builtin" else { return false }
            return normalizedPolicyScope == "global" || normalizedPolicyScope == "memory_core"
        }()
        let packageSHA256 = firstNonEmptySkillText(
            resolvedCacheItem?.packageSHA256 ?? "",
            installedSkill?.packageSHA256 ?? "",
            resolvedRegistryItem?.packageSHA256 ?? "",
            policyScope == "xt_builtin" ? syntheticBuiltinSHA256(seed: canonicalSkillId + "::package") : ""
        )
        let publisherID = firstNonEmptySkillText(
            resolvedCacheItem?.publisherID ?? "",
            installedSkill?.publisherID ?? "",
            resolvedRegistryItem?.publisherID ?? "",
            policyScope == "xt_builtin" ? "xt_builtin" : ""
        )
        let installHint = firstNonEmptySkillText(
            installedSkill?.installHint ?? "",
            resolvedCacheItem?.description ?? "",
            resolvedRegistryItem?.description ?? ""
        )
        let grantFloor = capabilitySemantics.grantFloor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? XTSkillGrantFloor.none.rawValue
            : capabilitySemantics.grantFloor
        let approvalFloor = capabilitySemantics.approvalFloor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? XTSkillApprovalFloor.none.rawValue
            : capabilitySemantics.approvalFloor
        let requiredRuntimeSurfaces = XTSkillCapabilityProfileSupport.requiredRuntimeSurfaces(
            for: capabilitySemantics.capabilityFamilies
        )
        let missingRuntimeSurfaces = requiredRuntimeSurfaces.filter { surface in
            !runtimeSurfaceFamilyReady(
                surface,
                executionTier: baseState.executionTier,
                effectiveRuntimeSurface: baseState.effectiveRuntimeSurface,
                trustedAutomationStatus: baseState.trustedAutomationStatus,
                hubAvailable: doctorSnapshot.hubIndexAvailable,
                hubBaseDir: resolvedHubBaseDir
            )
        }
        let onlyHubBridgeDisconnected = !missingRuntimeSurfaces.isEmpty
            && missingRuntimeSurfaces.allSatisfy { surface in
                surface.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "hub_bridge_network"
            }
        let policyClamped = !Set(capabilitySemantics.capabilityFamilies)
            .isSubset(of: Set(baseState.ceilingCapabilityFamilies))
            || !Set(capabilitySemantics.capabilityProfiles)
                .isSubset(of: Set(baseState.discoverableProfiles))

        let packageState = installedSkill?.packageState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let installabilityState: String = {
            if policyScope == "xt_builtin" { return "installable" }
            if installedSkill?.compatibilityState == .unsupported {
                return "unsupported"
            }
            if packageState == "quarantined" {
                return "vetter_blocked"
            }
            if installedSkill?.qualityEvidenceStatus.doctor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "failed" {
                return "doctor_blocked"
            }
            if installedSkill != nil || resolvedCacheItem != nil || virtualGlobalRegistryAvailability {
                return "installable"
            }
            return "not_uploadable"
        }()
        let discoverabilityState: String = {
            if installedSkill?.revoked == true { return "revoked" }
            if resolvedRegistryItem != nil || resolvedCacheItem != nil || policyScope == "xt_builtin" {
                return "discoverable"
            }
            return "hidden"
        }()
        let pinState: String = {
            switch policyScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "project":
                return "pinned_project"
            case "global":
                return "pinned_global"
            case "memory_core":
                return "pinned_memory_core"
            case "xt_builtin":
                return "xt_builtin"
            default:
                return "unpinned"
            }
        }()
        let resolutionState: String = {
            if installedSkill?.revoked == true {
                return "revoked"
            }
            if resolvedCacheItem != nil || policyScope == "xt_builtin" || virtualGlobalRegistryAvailability {
                return "resolved"
            }
            if installabilityState == "installable" {
                return "missing_package"
            }
            return "blocked"
        }()

        let grantRequired = grantFloor != XTSkillGrantFloor.none.rawValue
        let localApprovalRequired = XTSkillCapabilityProfileSupport.localApprovalRequired(
            approvalFloor: approvalFloor,
            localAutoApproveEnabled: baseState.localAutoApproveEnabled
        )
        let degraded = installedSkill?.compatibilityState == .partial
            || installedSkill?.qualityEvidenceStatus.doctor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "partial"
            || installedSkill?.qualityEvidenceStatus.smoke.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "partial"

        let readinessState: XTSkillExecutionReadinessState = {
            if installedSkill?.revoked == true || packageState == "revoked" {
                return .revoked
            }
            if packageState == "quarantined" {
                return .quarantined
            }
            if installabilityState == "unsupported" {
                return .unsupported
            }
            if resolvedCacheItem == nil && policyScope != "xt_builtin" && !virtualGlobalRegistryAvailability {
                return .notInstalled
            }
            if policyClamped {
                return .policyClamped
            }
            if !missingRuntimeSurfaces.isEmpty {
                if onlyHubBridgeDisconnected {
                    return .hubDisconnected
                }
                return .runtimeUnavailable
            }
            if grantRequired {
                return .grantRequired
            }
            if localApprovalRequired {
                return .localApprovalRequired
            }
            if degraded {
                return .degraded
            }
            return .ready
        }()

        let denyCode: String = {
            switch readinessState {
            case .ready:
                return ""
            case .grantRequired:
                return "grant_required"
            case .localApprovalRequired:
                return "local_approval_required"
            case .policyClamped:
                return "skill_policy_clamped"
            case .runtimeUnavailable:
                return "runtime_surface_not_ready"
            case .hubDisconnected:
                return "hub_disconnected"
            case .quarantined:
                return "preflight_quarantined"
            case .revoked:
                return "preflight_revoked"
            case .notInstalled:
                return "skill_not_installed"
            case .unsupported:
                return "skill_unsupported"
            case .degraded:
                return "skill_degraded"
            }
        }()

        let reasonCode: String = {
            switch readinessState {
            case .ready:
                return "ready"
            case .grantRequired:
                return "grant floor \(grantFloor) still pending"
            case .localApprovalRequired:
                return "approval floor \(approvalFloor) requires local confirmation"
            case .policyClamped:
                return "project profile ceiling excludes requested capability"
            case .runtimeUnavailable:
                return "runtime surfaces missing: \(missingRuntimeSurfaces.joined(separator: ", "))"
            case .hubDisconnected:
                return "hub connectivity unavailable"
            case .quarantined:
                return "skill package quarantined"
            case .revoked:
                return "skill package revoked"
            case .notInstalled:
                return "skill package not resolved into current project registry"
            case .unsupported:
                return "skill package unsupported"
            case .degraded:
                return "skill package degraded"
            }
        }()

        let requiredGrantCapabilities = XTSkillCapabilityProfileSupport.normalizedStrings(
            grantRequired
                ? ((installedSkill?.capabilitiesRequired.isEmpty == false
                    ? installedSkill?.capabilitiesRequired
                    : resolvedRegistryItem?.capabilitiesRequired) ?? capabilitySemantics.capabilityFamilies)
                : []
        )

        return XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: normalizedProjectId,
            skillId: canonicalSkillId,
            packageSHA256: packageSHA256,
            publisherID: publisherID,
            policyScope: policyScope,
            intentFamilies: capabilitySemantics.intentFamilies,
            capabilityFamilies: capabilitySemantics.capabilityFamilies,
            capabilityProfiles: capabilitySemantics.capabilityProfiles,
            discoverabilityState: discoverabilityState,
            installabilityState: installabilityState,
            pinState: pinState,
            resolutionState: resolutionState,
            executionReadiness: readinessState.rawValue,
            runnableNow: readinessState == .ready,
            denyCode: denyCode,
            reasonCode: reasonCode,
            grantFloor: grantFloor,
            approvalFloor: approvalFloor,
            requiredGrantCapabilities: requiredGrantCapabilities,
            requiredRuntimeSurfaces: requiredRuntimeSurfaces,
            stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(readinessState.rawValue),
            installHint: installHint,
            unblockActions: XTSkillCapabilityProfileSupport.unblockActions(
                for: readinessState,
                approvalFloor: approvalFloor,
                requiredRuntimeSurfaces: requiredRuntimeSurfaces
            ),
            auditRef: "audit-xt-skill-readiness-\(String((normalizedProjectId + canonicalSkillId).suffix(12)))",
            doctorAuditRef: doctorSnapshot.officialChannelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ""
                : "doctor:\(doctorSnapshot.officialChannelID)",
            vetterAuditRef: packageState == "quarantined" ? "vetter:quarantined" : "",
            resolvedSnapshotId: resolvedSnapshot?.resolvedSnapshotId ?? "",
            grantSnapshotRef: resolvedSnapshot?.grantSnapshotRef ?? ""
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
            let intentFamilies = fallbackIntentFamilies(
                skillId: spec.0,
                capabilitiesRequired: spec.3
            )
            let capabilityFamilies = fallbackCapabilityFamilies(
                intentFamilies: intentFamilies,
                capabilitiesRequired: spec.3
            )
            let capabilityProfiles = XTSkillCapabilityProfileSupport.capabilityProfiles(for: capabilityFamilies)
            return SupervisorSkillRegistryItem(
                skillId: spec.0,
                displayName: spec.1,
                description: spec.2,
                intentFamilies: intentFamilies,
                capabilityFamilies: capabilityFamilies,
                capabilityProfiles: capabilityProfiles,
                grantFloor: XTSkillCapabilityProfileSupport.grantFloor(
                    for: capabilityFamilies,
                    requiresGrant: nativeSupervisorRequiresGrant(skillId: spec.0),
                    riskLevel: spec.6.rawValue
                ),
                approvalFloor: XTSkillCapabilityProfileSupport.approvalFloor(for: capabilityFamilies),
                packageSHA256: syntheticBuiltinSHA256(seed: spec.0 + "::package"),
                publisherID: "xt_builtin",
                sourceID: "xt_builtin",
                officialPackage: false,
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

    private static func builtinSupervisorRegistryItems(
        hubBaseDir: URL
    ) -> [SupervisorSkillRegistryItem] {
        nativeSupervisorRegistryItems() + builtinRunnableLocalTaskWrapperRegistryItems(hubBaseDir: hubBaseDir)
    }

    private static func supervisorGlobalRegistryItems() -> [SupervisorSkillRegistryItem] {
        let findSkillsIntents = fallbackIntentFamilies(
            skillId: "find-skills",
            capabilitiesRequired: ["skills.search"]
        )
        let findSkillsFamilies = fallbackCapabilityFamilies(
            intentFamilies: findSkillsIntents,
            capabilitiesRequired: ["skills.search"]
        )
        let requestEnableIntents = fallbackIntentFamilies(
            skillId: "request-skill-enable",
            capabilitiesRequired: ["skills.pin"]
        )
        let requestEnableFamilies = fallbackCapabilityFamilies(
            intentFamilies: requestEnableIntents,
            capabilitiesRequired: ["skills.pin"]
        )

        return [
            SupervisorSkillRegistryItem(
                skillId: "find-skills",
                displayName: "Find Skills",
                description: "Search the governed Hub skill catalog before proposing install, import, or enable flows.",
                intentFamilies: findSkillsIntents,
                capabilityFamilies: findSkillsFamilies,
                capabilityProfiles: XTSkillCapabilityProfileSupport.capabilityProfiles(for: findSkillsFamilies),
                grantFloor: XTSkillCapabilityProfileSupport.grantFloor(
                    for: findSkillsFamilies,
                    requiresGrant: false,
                    riskLevel: SupervisorSkillRiskLevel.low.rawValue
                ),
                approvalFloor: XTSkillCapabilityProfileSupport.approvalFloor(for: findSkillsFamilies),
                packageSHA256: syntheticBuiltinSHA256(seed: "find-skills::package"),
                publisherID: "xt_builtin",
                sourceID: "xt_builtin",
                officialPackage: false,
                capabilitiesRequired: ["skills.search"],
                governedDispatch: SupervisorGovernedSkillDispatch(
                    tool: ToolName.skills_search.rawValue,
                    fixedArgs: [:],
                    passthroughArgs: ["query", "source_filter", "limit"],
                    argAliases: [
                        "source_filter": ["source"],
                        "limit": ["max_results"],
                    ],
                    requiredAny: [["query"]],
                    exactlyOneOf: []
                ),
                governedDispatchVariants: [],
                governedDispatchNotes: [
                    "Use this first for capability discovery when no focused project is selected.",
                    "If you later request enablement, preserve the exact skill_id and package_sha256 from the discovery result instead of inventing identifiers."
                ],
                inputSchemaRef: "schema://find-skills.input",
                outputSchemaRef: "schema://find-skills.output",
                sideEffectClass: "read_only",
                riskLevel: .low,
                requiresGrant: false,
                policyScope: "global",
                timeoutMs: 12_000,
                maxRetries: 0,
                available: true
            ),
            SupervisorSkillRegistryItem(
                skillId: "request-skill-enable",
                displayName: "Request Skill Enable",
                description: "Submit a governed Hub availability request for a previously discovered skill package using its exact skill_id and package_sha256.",
                intentFamilies: requestEnableIntents,
                capabilityFamilies: requestEnableFamilies,
                capabilityProfiles: XTSkillCapabilityProfileSupport.capabilityProfiles(for: requestEnableFamilies),
                grantFloor: XTSkillCapabilityProfileSupport.grantFloor(
                    for: requestEnableFamilies,
                    requiresGrant: false,
                    riskLevel: SupervisorSkillRiskLevel.medium.rawValue
                ),
                approvalFloor: XTSkillCapabilityProfileSupport.approvalFloor(for: requestEnableFamilies),
                packageSHA256: syntheticBuiltinSHA256(seed: "request-skill-enable::package"),
                publisherID: "xt_builtin",
                sourceID: "xt_builtin",
                officialPackage: false,
                capabilitiesRequired: ["skills.pin"],
                governedDispatch: SupervisorGovernedSkillDispatch(
                    tool: ToolName.skills_pin.rawValue,
                    fixedArgs: [:],
                    passthroughArgs: ["skill_id", "package_sha256", "scope", "project_id", "note"],
                    argAliases: [
                        "package_sha256": ["sha256"],
                    ],
                    requiredAny: [["skill_id"], ["package_sha256"]],
                    exactlyOneOf: []
                ),
                governedDispatchVariants: [],
                governedDispatchNotes: [
                    "Only use this after find-skills returns a concrete package_sha256 for the requested skill.",
                    "When no project is focused, omitting scope/project_id defaults the request to global Hub availability."
                ],
                inputSchemaRef: "schema://request-skill-enable.input",
                outputSchemaRef: "schema://request-skill-enable.output",
                sideEffectClass: "hub_skill_enable_request",
                riskLevel: .medium,
                requiresGrant: false,
                policyScope: "global",
                timeoutMs: 15_000,
                maxRetries: 0,
                available: true
            )
        ]
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

    private static func builtinResolvedSkillCacheItems(
        hubBaseDir: URL
    ) -> [XTResolvedSkillCacheItem] {
        builtinSupervisorRegistryItems(hubBaseDir: hubBaseDir).map { item in
            XTResolvedSkillCacheItem(
                skillId: item.skillId,
                displayName: item.displayName,
                description: item.description,
                packageSHA256: syntheticBuiltinSHA256(seed: item.skillId + "::package"),
                canonicalManifestSHA256: syntheticBuiltinSHA256(seed: item.skillId + "::manifest"),
                publisherID: "xt_builtin",
                sourceId: "xt_builtin",
                pinScope: item.policyScope,
                capabilitiesRequired: item.capabilitiesRequired,
                intentFamilies: item.intentFamilies,
                capabilityFamilies: item.capabilityFamilies,
                capabilityProfiles: item.capabilityProfiles,
                grantFloor: item.grantFloor,
                approvalFloor: item.approvalFloor,
                riskLevel: item.riskLevel.rawValue,
                requiresGrant: item.requiresGrant,
                sideEffectClass: item.sideEffectClass,
                governedDispatch: item.governedDispatch,
                governedDispatchVariants: item.governedDispatchVariants,
                governedDispatchNotes: item.governedDispatchNotes,
                inputSchemaRef: item.inputSchemaRef,
                outputSchemaRef: item.outputSchemaRef,
                timeoutMs: item.timeoutMs,
                maxRetries: item.maxRetries
            )
        }
    }

    private static func builtinRunnableLocalTaskWrapperRegistryItems(
        hubBaseDir: URL
    ) -> [SupervisorSkillRegistryItem] {
        guard let snapshot = loadLocalModelStateSnapshot(hubBaseDir: hubBaseDir) else {
            return []
        }
        let blockedCapabilities = blockedHubCapabilities(hubBaseDir: hubBaseDir)
        return builtinLocalTaskWrapperSpecs.compactMap { spec in
            let capabilityAliases = localAIKillSwitchAliases(for: spec.capability)
            guard !capabilityAliases.contains(where: { blockedCapabilities.contains($0) }) else {
                return nil
            }
            let resolution = HubModelSelectionAdvisor.resolveLocalTaskModel(
                taskKind: spec.taskKind,
                snapshot: snapshot
            )
            guard resolution.resolvedModel != nil,
                  let governedDispatch = fallbackGovernedDispatch(skillId: spec.skillId) else {
                return nil
            }

            let capabilitiesRequired = [spec.capability]
            let intentFamilies = fallbackIntentFamilies(
                skillId: spec.skillId,
                capabilitiesRequired: capabilitiesRequired
            )
            let capabilityFamilies = fallbackCapabilityFamilies(
                intentFamilies: intentFamilies,
                capabilitiesRequired: capabilitiesRequired
            )
            let capabilityProfiles = XTSkillCapabilityProfileSupport.capabilityProfiles(for: capabilityFamilies)

            return SupervisorSkillRegistryItem(
                skillId: spec.skillId,
                displayName: spec.displayName,
                description: spec.description,
                intentFamilies: intentFamilies,
                capabilityFamilies: capabilityFamilies,
                capabilityProfiles: capabilityProfiles,
                grantFloor: XTSkillCapabilityProfileSupport.grantFloor(
                    for: capabilityFamilies,
                    requiresGrant: false,
                    riskLevel: spec.riskLevel.rawValue
                ),
                approvalFloor: XTSkillCapabilityProfileSupport.approvalFloor(for: capabilityFamilies),
                packageSHA256: syntheticBuiltinSHA256(seed: spec.skillId + "::package"),
                publisherID: "xt_builtin",
                sourceID: "xt_builtin",
                officialPackage: false,
                capabilitiesRequired: capabilitiesRequired,
                governedDispatch: governedDispatch,
                governedDispatchVariants: [],
                governedDispatchNotes: fallbackGovernedDispatchNotes(skillId: spec.skillId),
                inputSchemaRef: "schema://\(spec.skillId).input",
                outputSchemaRef: "schema://\(spec.skillId).output",
                sideEffectClass: spec.sideEffectClass,
                riskLevel: spec.riskLevel,
                requiresGrant: false,
                policyScope: "xt_builtin",
                timeoutMs: spec.timeoutMs,
                maxRetries: spec.maxRetries,
                available: true
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
            return ["restart_on_exit is honored only when the A-Tier allows managed process auto-restart."]
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

    private static func sha256Hex(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedSourceToken(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    struct XTResolvedSkillsCacheEpochState {
        var profileEpoch: String
        var trustRootSetHash: String
        var revocationEpoch: String
        var officialChannelSnapshotID: String
        var runtimeSurfaceHash: String
    }

    private struct XTProjectSkillProfileBaseState {
        var projectId: String
        var projectName: String
        var config: AXProjectConfig
        var executionTier: AXProjectExecutionTier
        var effectiveRuntimeSurface: AXProjectRuntimeSurfaceEffectivePolicy
        var trustedAutomationStatus: AXTrustedAutomationProjectStatus
        var legacyToolProfile: String
        var discoverableProfiles: [String]
        var ceilingProfiles: [String]
        var ceilingCapabilityFamilies: [String]
        var localAutoApproveEnabled: Bool
        var runtimeSurfaceHash: String
        var profileEpoch: String
    }

    private struct XTNormalizedCapabilitySemantics {
        var intentFamilies: [String]
        var capabilityFamilies: [String]
        var capabilityProfiles: [String]
        var grantFloor: String
        var approvalFloor: String
    }

    private static func normalizedCapabilitySemantics(
        skillId: String,
        capabilitiesRequired: [String],
        declaredIntentFamilies: [String],
        declaredCapabilityFamilies: [String],
        declaredCapabilityProfiles: [String],
        declaredGrantFloor: String,
        declaredApprovalFloor: String
    ) -> XTNormalizedCapabilitySemantics {
        let hasCanonicalSemantics = !declaredIntentFamilies.isEmpty
            || !declaredCapabilityFamilies.isEmpty
            || !declaredCapabilityProfiles.isEmpty
        let intentFamilies = !declaredIntentFamilies.isEmpty
            ? XTSkillCapabilityProfileSupport.normalizedStrings(declaredIntentFamilies)
            : fallbackIntentFamilies(skillId: skillId, capabilitiesRequired: capabilitiesRequired)
        let capabilityFamilies = !declaredCapabilityFamilies.isEmpty
            ? XTSkillCapabilityProfileSupport.orderedCapabilityFamilies(declaredCapabilityFamilies)
            : fallbackCapabilityFamilies(intentFamilies: intentFamilies, capabilitiesRequired: capabilitiesRequired)
        let capabilityProfiles = !declaredCapabilityProfiles.isEmpty
            ? XTSkillCapabilityProfileSupport.orderedProfiles(declaredCapabilityProfiles)
            : XTSkillCapabilityProfileSupport.capabilityProfiles(for: capabilityFamilies)
        let normalizedDeclaredGrantFloor = declaredGrantFloor.trimmingCharacters(in: .whitespacesAndNewlines)
        let grantFloor = normalizedDeclaredGrantFloor.isEmpty
            || (!hasCanonicalSemantics && normalizedDeclaredGrantFloor == XTSkillGrantFloor.none.rawValue)
            ? XTSkillCapabilityProfileSupport.grantFloor(
                for: capabilityFamilies,
                requiresGrant: false,
                riskLevel: ""
            )
            : normalizedDeclaredGrantFloor
        let normalizedDeclaredApprovalFloor = declaredApprovalFloor.trimmingCharacters(in: .whitespacesAndNewlines)
        let approvalFloor = normalizedDeclaredApprovalFloor.isEmpty
            || (!hasCanonicalSemantics && normalizedDeclaredApprovalFloor == XTSkillApprovalFloor.none.rawValue)
            ? XTSkillCapabilityProfileSupport.approvalFloor(for: capabilityFamilies)
            : normalizedDeclaredApprovalFloor
        return XTNormalizedCapabilitySemantics(
            intentFamilies: intentFamilies,
            capabilityFamilies: capabilityFamilies,
            capabilityProfiles: capabilityProfiles,
            grantFloor: grantFloor,
            approvalFloor: approvalFloor
        )
    }

    private static func fallbackIntentFamilies(
        skillId: String,
        capabilitiesRequired: [String]
    ) -> [String] {
        var intents: [String] = []
        let normalizedSkillId = canonicalSupervisorSkillID(skillId).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalizedSkillId {
        case "find-skills":
            intents.append("skills.discover")
        case "request-skill-enable":
            intents.append("skills.manage")
        case "supervisor-voice":
            intents.append("voice.playback")
        case "self-improving-agent":
            intents.append(contentsOf: ["memory.inspect", "supervisor.orchestrate"])
        case "agent-browser":
            intents.append(contentsOf: ["browser.observe", "browser.interact", "browser.secret_fill", "web.fetch_live"])
        default:
            break
        }

        for rawCapability in capabilitiesRequired {
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

    private static func fallbackCapabilityFamilies(
        intentFamilies: [String],
        capabilitiesRequired: [String]
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

        for rawCapability in capabilitiesRequired {
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
                || capability.hasPrefix("web.live") {
                families.append("web.live")
            }
            if capability.hasPrefix("browser.read") || capability.hasPrefix("browser.observe") {
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

    private static let localAIRuntimeSurfaceOrder: [String] = [
        "local_text_generation_runtime",
        "local_embedding_runtime",
        "local_speech_to_text_runtime",
        "local_text_to_speech_runtime",
        "local_vision_runtime",
    ]

    private static func runtimeSurfaceHash(
        projectRoot: URL,
        config: AXProjectConfig,
        hubBaseDir: URL
    ) -> String {
        let effectiveRuntimeSurface = config.effectiveRuntimeSurfacePolicy()
        let trustedAutomationStatus = config.trustedAutomationStatus(forProjectRoot: projectRoot)
        return XTSkillCapabilityProfileSupport.hashString([
            "configured_mode=\(config.runtimeSurfaceMode.rawValue)",
            "effective_mode=\(effectiveRuntimeSurface.effectiveMode.rawValue)",
            "hub_override=\(effectiveRuntimeSurface.hubOverrideMode.rawValue)",
            "allow_device_tools=\(effectiveRuntimeSurface.allowDeviceTools)",
            "allow_browser_runtime=\(effectiveRuntimeSurface.allowBrowserRuntime)",
            "allow_connector_actions=\(effectiveRuntimeSurface.allowConnectorActions)",
            "allow_extensions=\(effectiveRuntimeSurface.allowExtensions)",
            "trusted_automation_ready=\(trustedAutomationStatus.trustedAutomationReady)",
            "trusted_automation_permission_owner_ready=\(trustedAutomationStatus.permissionOwnerReady)",
            "trusted_automation_state=\(trustedAutomationStatus.state.rawValue)",
        ] + localAIRuntimeSurfaceHashLines(hubBaseDir: hubBaseDir))
    }

    private static func projectSkillProfileBaseState(
        projectId: String,
        projectName: String?,
        projectRoot: URL,
        config: AXProjectConfig,
        hubBaseDir: URL
    ) -> XTProjectSkillProfileBaseState {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedProjectName = projectName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? projectName!.trimmingCharacters(in: .whitespacesAndNewlines)
            : normalizedProjectId
        let executionTier = config.executionTier
        let effectiveRuntimeSurface = config.effectiveRuntimeSurfacePolicy()
        let trustedAutomationStatus = config.trustedAutomationStatus(forProjectRoot: projectRoot)
        let ceilingProfiles = XTSkillCapabilityProfileSupport.profileCeiling(for: executionTier)
        let allowedTools = ToolPolicy.sortedTools(
            ToolPolicy.effectiveAllowedTools(
                profileRaw: config.toolProfile,
                allowTokens: config.toolAllow,
                denyTokens: config.toolDeny
            )
        )
        let localFamilies = XTSkillCapabilityProfileSupport.orderedCapabilityFamilies(
            allowedTools.flatMap { XTSkillCapabilityProfileSupport.capabilityFamilies(for: $0) }
        )
        let localProfiles = XTSkillCapabilityProfileSupport.capabilityProfiles(for: localFamilies)
        let requestedProfiles = XTSkillCapabilityProfileSupport.orderedProfiles(
            XTSkillCapabilityProfileSupport.legacyRequestedProfiles(toolProfileRaw: config.toolProfile) + localProfiles
        )
        var discoverableProfiles = XTSkillCapabilityProfileSupport.orderedProfiles(
            requestedProfiles.filter { ceilingProfiles.contains($0) }
        )
        if discoverableProfiles.isEmpty, ceilingProfiles.contains(XTSkillCapabilityProfileID.observeOnly.rawValue) {
            discoverableProfiles = [XTSkillCapabilityProfileID.observeOnly.rawValue]
        }
        let profileEpoch = XTSkillCapabilityProfileSupport.hashString(
            config.skillProfileEpochInputSummary(projectRoot: projectRoot)
        )
        return XTProjectSkillProfileBaseState(
            projectId: normalizedProjectId,
            projectName: resolvedProjectName,
            config: config,
            executionTier: executionTier,
            effectiveRuntimeSurface: effectiveRuntimeSurface,
            trustedAutomationStatus: trustedAutomationStatus,
            legacyToolProfile: XTSkillCapabilityProfileSupport.legacyToolProfileToken(config.toolProfile),
            discoverableProfiles: discoverableProfiles,
            ceilingProfiles: ceilingProfiles,
            ceilingCapabilityFamilies: XTSkillCapabilityProfileSupport.ceilingCapabilityFamilies(for: ceilingProfiles),
            localAutoApproveEnabled: config.governedAutoApproveLocalToolCalls,
            runtimeSurfaceHash: runtimeSurfaceHash(projectRoot: projectRoot, config: config, hubBaseDir: hubBaseDir),
            profileEpoch: profileEpoch
        )
    }

    static func resolvedSkillsCacheEpochState(
        projectId: String,
        projectName: String?,
        projectRoot: URL?,
        config: AXProjectConfig?,
        hubBaseDir: URL
    ) -> XTResolvedSkillsCacheEpochState {
        let storeDir = hubBaseDir.appendingPathComponent("skills_store", isDirectory: true)
        let trustedPublishersURL = storeDir.appendingPathComponent("trusted_publishers.json")
        let revocationsURL = storeDir.appendingPathComponent("skill_revocations.json")
        let officialChannelDir = storeDir
            .appendingPathComponent("official_channels", isDirectory: true)
            .appendingPathComponent("official-stable", isDirectory: true)
        let officialChannelStateURL = officialChannelDir.appendingPathComponent("channel_state.json")

        let trusted = loadTrustedPublishers(url: trustedPublishersURL)
        let revocations = loadSkillRevocations(url: revocationsURL)
        let officialChannel = loadOfficialSkillChannelState(
            baseURL: officialChannelDir,
            stateURL: officialChannelStateURL
        )

        let trustRootSetHash = XTSkillCapabilityProfileSupport.hashString(
            trusted.publishers
                .filter(\.enabled)
                .map(\.publisherID)
                .map { "publisher=\($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
                .sorted()
        )
        let revocationEpoch = XTSkillCapabilityProfileSupport.hashString(
            revocations.revokedSHA256.map { "sha=\($0)" }
                + revocations.revokedSkillIDs.map { "skill=\($0)" }
                + revocations.revokedPublisherIDs.map { "publisher=\($0)" }
        )
        let officialChannelSnapshotID = {
            let channelID = officialChannel.channelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !channelID.isEmpty else { return "official_channel:unavailable" }
            return [
                channelID,
                officialChannel.status.trimmingCharacters(in: .whitespacesAndNewlines),
                String(max(0, officialChannel.updatedAtMs)),
                String(max(0, officialChannel.skillCount)),
            ]
            .joined(separator: ":")
        }()

        guard let projectRoot else {
            let fallbackHash = XTSkillCapabilityProfileSupport.hashString([
                "project_id=\(projectId)",
                "project_name=\((projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines))",
                "project_root=missing",
            ] + localAIRuntimeSurfaceHashLines(hubBaseDir: hubBaseDir))
            return XTResolvedSkillsCacheEpochState(
                profileEpoch: fallbackHash,
                trustRootSetHash: trustRootSetHash,
                revocationEpoch: revocationEpoch,
                officialChannelSnapshotID: officialChannelSnapshotID,
                runtimeSurfaceHash: fallbackHash
            )
        }

        let resolvedConfig = config ?? .default(forProjectRoot: projectRoot)
        return XTResolvedSkillsCacheEpochState(
            profileEpoch: XTSkillCapabilityProfileSupport.hashString(
                resolvedConfig.skillProfileEpochInputSummary(projectRoot: projectRoot)
            ),
            trustRootSetHash: trustRootSetHash,
            revocationEpoch: revocationEpoch,
            officialChannelSnapshotID: officialChannelSnapshotID,
            runtimeSurfaceHash: runtimeSurfaceHash(projectRoot: projectRoot, config: resolvedConfig, hubBaseDir: hubBaseDir)
        )
    }

    private static func selectedResolvedSkillItem(
        skillId: String,
        snapshot: XTResolvedSkillsCacheSnapshot?
    ) -> XTResolvedSkillCacheItem? {
        let canonicalSkillId = canonicalSupervisorSkillID(skillId)
        return snapshot?.items.first(where: {
            canonicalSupervisorSkillID($0.skillId) == canonicalSkillId
        })
    }

    private static func selectedInstalledSkill(
        skillId: String,
        snapshot: AXSkillsDoctorSnapshot
    ) -> AXHubSkillCompatibilityEntry? {
        let canonicalSkillId = canonicalSupervisorSkillID(skillId)
        let candidates = snapshot.installedSkills.filter {
            canonicalSupervisorSkillID($0.skillID) == canonicalSkillId
        }
        guard !candidates.isEmpty else { return nil }
        return candidates.sorted { lhs, rhs in
            let leftPriority = skillPinnedScopePriority(lhs.activePinnedScopes.first ?? lhs.pinnedScopes.first ?? "")
            let rightPriority = skillPinnedScopePriority(rhs.activePinnedScopes.first ?? rhs.pinnedScopes.first ?? "")
            if leftPriority != rightPriority {
                return leftPriority > rightPriority
            }
            return lhs.packageSHA256 < rhs.packageSHA256
        }.first
    }

    private static func runtimeSurfaceFamilyReady(
        _ surface: String,
        executionTier: AXProjectExecutionTier,
        effectiveRuntimeSurface: AXProjectRuntimeSurfaceEffectivePolicy,
        trustedAutomationStatus: AXTrustedAutomationProjectStatus,
        hubAvailable: Bool,
        hubBaseDir: URL
    ) -> Bool {
        let normalizedSurface = surface.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalizedSurface {
        case "xt_builtin", "supervisor_runtime", "project_local_fs":
            return true
        case "project_local_runtime":
            return executionTier >= .a2RepoAuto
        case "local_text_generation_runtime",
             "local_embedding_runtime",
             "local_speech_to_text_runtime",
             "local_text_to_speech_runtime",
             "local_vision_runtime":
            return localAIRuntimeSurfaceReady(normalizedSurface, hubBaseDir: hubBaseDir)
        case "hub_bridge_network":
            return hubAvailable
        case "managed_browser_runtime":
            return effectiveRuntimeSurface.allowBrowserRuntime
        case "trusted_device_runtime":
            return effectiveRuntimeSurface.allowDeviceTools && trustedAutomationStatus.trustedAutomationReady
        case "connector_runtime":
            return effectiveRuntimeSurface.allowConnectorActions
        default:
            return false
        }
    }

    private static func localAIRuntimeSurfaceHashLines(hubBaseDir: URL) -> [String] {
        let snapshot = loadLocalModelStateSnapshot(hubBaseDir: hubBaseDir)
        let blockedCapabilities = blockedHubCapabilities(hubBaseDir: hubBaseDir)
        var lines: [String] = [
            "local_models_updated_at=\(snapshot?.updatedAt ?? 0)",
            "local_model_count=\(snapshot?.models.count ?? 0)",
            "blocked_capabilities=\(blockedCapabilities.sorted().joined(separator: ","))",
        ]
        for surface in localAIRuntimeSurfaceOrder {
            lines.append(
                "surface_\(surface)=\(localAIRuntimeSurfaceReady(surface, snapshot: snapshot, blockedCapabilities: blockedCapabilities))"
            )
        }
        return lines
    }

    private static func localAIRuntimeSurfaceReady(
        _ surface: String,
        hubBaseDir: URL
    ) -> Bool {
        let snapshot = loadLocalModelStateSnapshot(hubBaseDir: hubBaseDir)
        let blockedCapabilities = blockedHubCapabilities(hubBaseDir: hubBaseDir)
        return localAIRuntimeSurfaceReady(
            surface,
            snapshot: snapshot,
            blockedCapabilities: blockedCapabilities
        )
    }

    private static func localAIRuntimeSurfaceReady(
        _ surface: String,
        snapshot: ModelStateSnapshot?,
        blockedCapabilities: Set<String>
    ) -> Bool {
        guard let capability = localAICapabilityForRuntimeSurface(surface) else {
            return false
        }
        let capabilityAliases = localAIKillSwitchAliases(for: capability)
        if capabilityAliases.contains(where: { blockedCapabilities.contains($0) }) {
            return false
        }
        guard let snapshot else {
            return false
        }
        return snapshot.models.contains { model in
            modelSupportsLocalAIRuntimeSurface(model, surface: surface)
        }
    }

    private static func loadLocalModelStateSnapshot(
        hubBaseDir: URL
    ) -> ModelStateSnapshot? {
        let url = hubBaseDir.appendingPathComponent("models_state.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ModelStateSnapshot.self, from: data)
    }

    private static func blockedHubCapabilities(
        hubBaseDir: URL
    ) -> Set<String> {
        let snapshot = XTHubLaunchStatusStore.load(baseDir: hubBaseDir)
        return Set(
            (snapshot?.blockedCapabilities ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    private static func localAICapabilityForRuntimeSurface(
        _ surface: String
    ) -> String? {
        switch surface {
        case "local_text_generation_runtime":
            return "ai.generate.local"
        case "local_embedding_runtime":
            return "ai.embed.local"
        case "local_speech_to_text_runtime":
            return "ai.audio.local"
        case "local_text_to_speech_runtime":
            return "ai.audio.tts.local"
        case "local_vision_runtime":
            return "ai.vision.local"
        default:
            return nil
        }
    }

    private static func localAIKillSwitchAliases(
        for capability: String
    ) -> [String] {
        switch capability {
        case "ai.audio.tts.local":
            return ["ai.audio.tts.local", "ai.audio.local"]
        default:
            return [capability]
        }
    }

    private static func modelSupportsLocalAIRuntimeSurface(
        _ model: HubModel,
        surface: String
    ) -> Bool {
        let taskKinds = Set(model.taskKinds.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        let inputModalities = Set(model.inputModalities.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        let outputModalities = Set(model.outputModalities.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })

        switch surface {
        case "local_text_generation_runtime":
            return model.supportsInteractiveTextGeneration
        case "local_embedding_runtime":
            return model.isEmbeddingModel || outputModalities.contains("embedding")
        case "local_speech_to_text_runtime":
            return taskKinds.contains("speech_to_text") || inputModalities.contains("audio")
        case "local_text_to_speech_runtime":
            return model.isTextToSpeechModel || outputModalities.contains("audio")
        case "local_vision_runtime":
            return taskKinds.contains("vision_understand")
                || taskKinds.contains("ocr")
                || inputModalities.contains("image")
        default:
            return false
        }
    }

    private static func supervisorSkillRegistryItem(
        cacheItem: XTResolvedSkillCacheItem
    ) -> SupervisorSkillRegistryItem {
        let riskLevel = normalizedRiskLevel(cacheItem.riskLevel)
            ?? SupervisorSkillRiskLevel(
                rawValue: cacheItem.riskLevel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
            ?? .medium
        return SupervisorSkillRegistryItem(
            skillId: cacheItem.skillId,
            displayName: firstNonEmptySkillText(cacheItem.displayName, cacheItem.skillId),
            description: cacheItem.description,
            intentFamilies: cacheItem.intentFamilies,
            capabilityFamilies: cacheItem.capabilityFamilies,
            capabilityProfiles: cacheItem.capabilityProfiles,
            grantFloor: cacheItem.grantFloor,
            approvalFloor: cacheItem.approvalFloor,
            packageSHA256: cacheItem.packageSHA256,
            publisherID: cacheItem.publisherID,
            sourceID: cacheItem.sourceId,
            officialPackage: cacheItem.publisherID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "xhub.official"
                || cacheItem.sourceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains("official"),
            capabilitiesRequired: cacheItem.capabilitiesRequired,
            governedDispatch: cacheItem.governedDispatch,
            governedDispatchVariants: cacheItem.governedDispatchVariants,
            governedDispatchNotes: cacheItem.governedDispatchNotes,
            inputSchemaRef: cacheItem.inputSchemaRef,
            outputSchemaRef: cacheItem.outputSchemaRef,
            sideEffectClass: cacheItem.sideEffectClass,
            riskLevel: riskLevel,
            requiresGrant: cacheItem.requiresGrant,
            policyScope: cacheItem.pinScope,
            timeoutMs: max(1_000, cacheItem.timeoutMs),
            maxRetries: max(0, cacheItem.maxRetries),
            available: true
        )
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
        let semanticCapabilities = manifestHints.capabilitiesRequired.isEmpty
            ? skill.capabilitiesRequired
            : manifestHints.capabilitiesRequired
        let derivedSemantics = normalizedCapabilitySemantics(
            skillId: skill.skillID,
            capabilitiesRequired: semanticCapabilities,
            declaredIntentFamilies: skill.intentFamilies,
            declaredCapabilityFamilies: skill.capabilityFamilies,
            declaredCapabilityProfiles: skill.capabilityProfiles,
            declaredGrantFloor: skill.grantFloor,
            declaredApprovalFloor: skill.approvalFloor
        )
        return SupervisorSkillRegistryItem(
            skillId: skill.skillID,
            displayName: firstNonEmptySkillText(skill.name, skill.skillID),
            description: manifestHints.description,
            intentFamilies: derivedSemantics.intentFamilies,
            capabilityFamilies: derivedSemantics.capabilityFamilies,
            capabilityProfiles: derivedSemantics.capabilityProfiles,
            grantFloor: derivedSemantics.grantFloor,
            approvalFloor: derivedSemantics.approvalFloor,
            packageSHA256: skill.packageSHA256,
            publisherID: skill.publisherID,
            sourceID: skill.sourceID,
            officialPackage: skill.publisherID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "xhub.official"
                || skill.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains("official"),
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
        case "local-embeddings", "local.embeddings", "local_embeddings":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.run_local_task.rawValue,
                fixedArgs: ["task_kind": .string("embedding")],
                passthroughArgs: ["model_id", "preferred_model_id", "text", "texts", "query", "documents", "input", "options", "device_id", "timeout_sec"],
                argAliases: [
                    "model_id": ["model"],
                    "text": ["content", "value"],
                    "texts": ["inputs", "rows"],
                ],
                requiredAny: [["text", "texts", "query", "documents"]],
                exactlyOneOf: []
            )
        case "local-transcribe", "local.transcribe", "local_transcribe":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.run_local_task.rawValue,
                fixedArgs: ["task_kind": .string("speech_to_text")],
                passthroughArgs: ["model_id", "preferred_model_id", "audio_path", "language", "input", "options", "device_id", "timeout_sec"],
                argAliases: [
                    "model_id": ["model"],
                    "audio_path": ["path", "file"],
                ],
                requiredAny: [["audio_path"]],
                exactlyOneOf: []
            )
        case "local-vision", "local.vision", "local_vision":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.run_local_task.rawValue,
                fixedArgs: ["task_kind": .string("vision_understand")],
                passthroughArgs: ["model_id", "preferred_model_id", "image_path", "image_paths", "image", "multimodal_messages", "text", "prompt", "input", "options", "device_id", "timeout_sec"],
                argAliases: [
                    "model_id": ["model"],
                    "image_path": ["path", "file"],
                    "image_paths": ["files"],
                    "text": ["content", "value"],
                ],
                requiredAny: [["image_path", "image_paths", "image", "multimodal_messages"]],
                exactlyOneOf: []
            )
        case "local-ocr", "local.ocr", "local_ocr":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.run_local_task.rawValue,
                fixedArgs: ["task_kind": .string("ocr")],
                passthroughArgs: ["model_id", "preferred_model_id", "image_path", "image_paths", "image", "multimodal_messages", "prompt", "language", "input", "options", "device_id", "timeout_sec"],
                argAliases: [
                    "model_id": ["model"],
                    "image_path": ["path", "file"],
                    "image_paths": ["files"],
                ],
                requiredAny: [["image_path", "image_paths", "image", "multimodal_messages"]],
                exactlyOneOf: []
            )
        case "local-tts", "local.tts", "local_tts":
            return SupervisorGovernedSkillDispatch(
                tool: ToolName.run_local_task.rawValue,
                fixedArgs: ["task_kind": .string("text_to_speech")],
                passthroughArgs: ["model_id", "preferred_model_id", "text", "prompt", "voice", "speaker", "voice_name", "output_path", "format", "input", "options", "device_id", "timeout_sec"],
                argAliases: [
                    "model_id": ["model"],
                    "text": ["content", "value"],
                    "speaker": ["speaker_id"],
                ],
                requiredAny: [["text", "prompt"]],
                exactlyOneOf: []
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
        case "local-embeddings", "local.embeddings", "local_embeddings":
            return [
                "Routes through run_local_task with task_kind=embedding.",
                "Prefer this for vector embedding, retrieval preparation, and semantic indexing instead of collapsing the request into text generation.",
                "If model_id/preferred_model_id is omitted, XT binds the best runnable Hub local embedding model for this task kind."
            ]
        case "local-transcribe", "local.transcribe", "local_transcribe":
            return [
                "Routes through run_local_task with task_kind=speech_to_text.",
                "Use for local audio transcription when the caller has an explicit audio path.",
                "If model_id/preferred_model_id is omitted, XT binds the best runnable Hub local speech-to-text model for this task kind."
            ]
        case "local-vision", "local.vision", "local_vision":
            return [
                "Routes through run_local_task with task_kind=vision_understand.",
                "Use for image understanding; keep OCR-only extraction on the dedicated local-ocr wrapper.",
                "If model_id/preferred_model_id is omitted, XT binds the best runnable Hub local vision model for this task kind."
            ]
        case "local-ocr", "local.ocr", "local_ocr":
            return [
                "Routes through run_local_task with task_kind=ocr.",
                "Use for screenshot or document text extraction rather than generic image narration.",
                "If model_id/preferred_model_id is omitted, XT binds the best runnable Hub local OCR model for this task kind."
            ]
        case "local-tts", "local.tts", "local_tts":
            return [
                "Routes through run_local_task with task_kind=text_to_speech.",
                "Use for generic local speech synthesis; keep Supervisor playback control on supervisor-voice.",
                "If model_id/preferred_model_id is omitted, XT binds the best runnable Hub local TTS model for this task kind."
            ]
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
