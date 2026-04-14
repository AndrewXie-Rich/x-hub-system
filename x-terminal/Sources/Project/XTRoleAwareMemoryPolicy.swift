import Foundation

enum XTSupervisorReviewMemoryDepthProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact
    case planReview = "plan_review"
    case deepDive = "deep_dive"
    case fullScan = "full_scan"
    case auto

    static let defaultProfile: XTSupervisorReviewMemoryDepthProfile = .auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact:
            return "Compact"
        case .planReview:
            return "Plan Review"
        case .deepDive:
            return "Deep Dive"
        case .fullScan:
            return "Full Scan"
        case .auto:
            return "Auto"
        }
    }

    var summary: String {
        switch self {
        case .compact:
            return "只保留轻量治理视图，优先 continuity 和当前重点。"
        case .planReview:
            return "适合常规 review，带当前锚点、冲突和必要引用。"
        case .deepDive:
            return "适合 drift / blocker / strategic review，带更厚的证据和 lineage。"
        case .fullScan:
            return "适合 portfolio reprioritize / rescue / critical pre-done。"
        case .auto:
            return "由 runtime 根据 S-tier、trigger 和当前风险决定实际深度。"
        }
    }

    var servingProfile: XTMemoryServingProfile? {
        switch self {
        case .compact:
            return .m1Execute
        case .planReview:
            return .m2PlanReview
        case .deepDive:
            return .m3DeepDive
        case .fullScan:
            return .m4FullScan
        case .auto:
            return nil
        }
    }

    static func from(servingProfile: XTMemoryServingProfile) -> XTSupervisorReviewMemoryDepthProfile {
        switch servingProfile {
        case .m0Heartbeat, .m1Execute:
            return .compact
        case .m2PlanReview:
            return .planReview
        case .m3DeepDive:
            return .deepDive
        case .m4FullScan:
            return .fullScan
        }
    }
}

enum XTMemoryAssemblyRole: String, Codable, Sendable {
    case projectAI = "project_ai"
    case supervisor
}

// Compatibility alias for older tests and presentation code that still
// reference the pre-rename role type.
typealias XTRoleAwareMemoryRole = XTMemoryAssemblyRole

enum XTSupervisorMemoryAssemblyPurpose: String, Codable, CaseIterable, Identifiable, Sendable {
    case conversation
    case projectAssist = "project_assist"
    case governanceReview = "governance_review"
    case portfolioReview = "portfolio_review"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .conversation:
            return "Conversation"
        case .projectAssist:
            return "Project Assist"
        case .governanceReview:
            return "Governance Review"
        case .portfolioReview:
            return "Portfolio Review"
        }
    }
}

struct XTMemoryAssemblyResolution: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xhub.memory_assembly_resolution.v1"

    var schemaVersion: String
    var role: XTMemoryAssemblyRole
    var dominantMode: String?
    var trigger: String
    var configuredDepth: String
    var recommendedDepth: String
    var effectiveDepth: String
    var ceilingFromTier: String
    var ceilingHit: Bool
    var selectedSlots: [String]
    var selectedPlanes: [String]
    var selectedServingObjects: [String]
    var excludedBlocks: [String]
    var budgetSummary: String?
    var auditRef: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case role
        case dominantMode = "dominant_mode"
        case trigger
        case configuredDepth = "configured_depth"
        case recommendedDepth = "recommended_depth"
        case effectiveDepth = "effective_depth"
        case ceilingFromTier = "ceiling_from_tier"
        case ceilingHit = "ceiling_hit"
        case selectedSlots = "selected_slots"
        case selectedPlanes = "selected_planes"
        case selectedServingObjects = "selected_serving_objects"
        case excludedBlocks = "excluded_blocks"
        case budgetSummary = "budget_summary"
        case auditRef = "audit_ref"
    }

    init(
        role: XTMemoryAssemblyRole,
        dominantMode: String? = nil,
        trigger: String,
        configuredDepth: String,
        recommendedDepth: String,
        effectiveDepth: String,
        ceilingFromTier: String,
        ceilingHit: Bool,
        selectedSlots: [String] = [],
        selectedPlanes: [String] = [],
        selectedServingObjects: [String] = [],
        excludedBlocks: [String] = [],
        budgetSummary: String? = nil,
        auditRef: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.role = role
        self.dominantMode = dominantMode
        self.trigger = trigger
        self.configuredDepth = configuredDepth
        self.recommendedDepth = recommendedDepth
        self.effectiveDepth = effectiveDepth
        self.ceilingFromTier = ceilingFromTier
        self.ceilingHit = ceilingHit
        self.selectedSlots = selectedSlots
        self.selectedPlanes = selectedPlanes
        self.selectedServingObjects = selectedServingObjects
        self.excludedBlocks = excludedBlocks
        self.budgetSummary = budgetSummary
        self.auditRef = auditRef
    }
}

struct XTProjectMemoryPolicySnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xhub.project_memory_policy.v1"

    var schemaVersion: String
    var configuredRecentProjectDialogueProfile: AXProjectRecentDialogueProfile
    var configuredProjectContextDepth: AXProjectContextDepthProfile
    var recommendedRecentProjectDialogueProfile: AXProjectRecentDialogueProfile
    var recommendedProjectContextDepth: AXProjectContextDepthProfile
    var effectiveRecentProjectDialogueProfile: AXProjectRecentDialogueProfile
    var effectiveProjectContextDepth: AXProjectContextDepthProfile
    var aTierMemoryCeiling: XTMemoryServingProfile
    var auditRef: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case configuredRecentProjectDialogueProfile = "configured_recent_project_dialogue_profile"
        case configuredProjectContextDepth = "configured_project_context_depth"
        case recommendedRecentProjectDialogueProfile = "recommended_recent_project_dialogue_profile"
        case recommendedProjectContextDepth = "recommended_project_context_depth"
        case effectiveRecentProjectDialogueProfile = "effective_recent_project_dialogue_profile"
        case effectiveProjectContextDepth = "effective_project_context_depth"
        case aTierMemoryCeiling = "a_tier_memory_ceiling"
        case auditRef = "audit_ref"
    }

    init(
        configuredRecentProjectDialogueProfile: AXProjectRecentDialogueProfile,
        configuredProjectContextDepth: AXProjectContextDepthProfile,
        recommendedRecentProjectDialogueProfile: AXProjectRecentDialogueProfile,
        recommendedProjectContextDepth: AXProjectContextDepthProfile,
        effectiveRecentProjectDialogueProfile: AXProjectRecentDialogueProfile,
        effectiveProjectContextDepth: AXProjectContextDepthProfile,
        aTierMemoryCeiling: XTMemoryServingProfile,
        auditRef: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.configuredRecentProjectDialogueProfile = configuredRecentProjectDialogueProfile
        self.configuredProjectContextDepth = configuredProjectContextDepth
        self.recommendedRecentProjectDialogueProfile = recommendedRecentProjectDialogueProfile
        self.recommendedProjectContextDepth = recommendedProjectContextDepth
        self.effectiveRecentProjectDialogueProfile = effectiveRecentProjectDialogueProfile
        self.effectiveProjectContextDepth = effectiveProjectContextDepth
        self.aTierMemoryCeiling = aTierMemoryCeiling
        self.auditRef = auditRef
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ceilingRaw = try container.decode(String.self, forKey: .aTierMemoryCeiling)
        self.init(
            configuredRecentProjectDialogueProfile: try container.decode(
                AXProjectRecentDialogueProfile.self,
                forKey: .configuredRecentProjectDialogueProfile
            ),
            configuredProjectContextDepth: try container.decode(
                AXProjectContextDepthProfile.self,
                forKey: .configuredProjectContextDepth
            ),
            recommendedRecentProjectDialogueProfile: try container.decode(
                AXProjectRecentDialogueProfile.self,
                forKey: .recommendedRecentProjectDialogueProfile
            ),
            recommendedProjectContextDepth: try container.decode(
                AXProjectContextDepthProfile.self,
                forKey: .recommendedProjectContextDepth
            ),
            effectiveRecentProjectDialogueProfile: try container.decode(
                AXProjectRecentDialogueProfile.self,
                forKey: .effectiveRecentProjectDialogueProfile
            ),
            effectiveProjectContextDepth: try container.decode(
                AXProjectContextDepthProfile.self,
                forKey: .effectiveProjectContextDepth
            ),
            aTierMemoryCeiling: XTMemoryServingProfile.parse(ceilingRaw) ?? .m2PlanReview,
            auditRef: try container.decodeIfPresent(String.self, forKey: .auditRef)
        )
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(
            configuredRecentProjectDialogueProfile,
            forKey: .configuredRecentProjectDialogueProfile
        )
        try container.encode(configuredProjectContextDepth, forKey: .configuredProjectContextDepth)
        try container.encode(
            recommendedRecentProjectDialogueProfile,
            forKey: .recommendedRecentProjectDialogueProfile
        )
        try container.encode(recommendedProjectContextDepth, forKey: .recommendedProjectContextDepth)
        try container.encode(
            effectiveRecentProjectDialogueProfile,
            forKey: .effectiveRecentProjectDialogueProfile
        )
        try container.encode(effectiveProjectContextDepth, forKey: .effectiveProjectContextDepth)
        try container.encode(aTierMemoryCeiling.rawValue, forKey: .aTierMemoryCeiling)
        try container.encodeIfPresent(auditRef, forKey: .auditRef)
    }
}

struct XTSupervisorMemoryPolicySnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xhub.supervisor_memory_policy.v1"

    var schemaVersion: String
    var configuredSupervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile
    var configuredReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile
    var recommendedSupervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile
    var recommendedReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile
    var effectiveSupervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile
    var effectiveReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile
    var sTierReviewMemoryCeiling: XTMemoryServingProfile
    var auditRef: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case configuredSupervisorRecentRawContextProfile = "configured_supervisor_recent_raw_context_profile"
        case configuredReviewMemoryDepth = "configured_review_memory_depth"
        case recommendedSupervisorRecentRawContextProfile = "recommended_supervisor_recent_raw_context_profile"
        case recommendedReviewMemoryDepth = "recommended_review_memory_depth"
        case effectiveSupervisorRecentRawContextProfile = "effective_supervisor_recent_raw_context_profile"
        case effectiveReviewMemoryDepth = "effective_review_memory_depth"
        case sTierReviewMemoryCeiling = "s_tier_review_memory_ceiling"
        case auditRef = "audit_ref"
    }

    init(
        configuredSupervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile,
        configuredReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile,
        recommendedSupervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile,
        recommendedReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile,
        effectiveSupervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile,
        effectiveReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile,
        sTierReviewMemoryCeiling: XTMemoryServingProfile,
        auditRef: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.configuredSupervisorRecentRawContextProfile = configuredSupervisorRecentRawContextProfile
        self.configuredReviewMemoryDepth = configuredReviewMemoryDepth
        self.recommendedSupervisorRecentRawContextProfile = recommendedSupervisorRecentRawContextProfile
        self.recommendedReviewMemoryDepth = recommendedReviewMemoryDepth
        self.effectiveSupervisorRecentRawContextProfile = effectiveSupervisorRecentRawContextProfile
        self.effectiveReviewMemoryDepth = effectiveReviewMemoryDepth
        self.sTierReviewMemoryCeiling = sTierReviewMemoryCeiling
        self.auditRef = auditRef
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ceilingRaw = try container.decode(String.self, forKey: .sTierReviewMemoryCeiling)
        self.init(
            configuredSupervisorRecentRawContextProfile: try container.decode(
                XTSupervisorRecentRawContextProfile.self,
                forKey: .configuredSupervisorRecentRawContextProfile
            ),
            configuredReviewMemoryDepth: try container.decode(
                XTSupervisorReviewMemoryDepthProfile.self,
                forKey: .configuredReviewMemoryDepth
            ),
            recommendedSupervisorRecentRawContextProfile: try container.decode(
                XTSupervisorRecentRawContextProfile.self,
                forKey: .recommendedSupervisorRecentRawContextProfile
            ),
            recommendedReviewMemoryDepth: try container.decode(
                XTSupervisorReviewMemoryDepthProfile.self,
                forKey: .recommendedReviewMemoryDepth
            ),
            effectiveSupervisorRecentRawContextProfile: try container.decode(
                XTSupervisorRecentRawContextProfile.self,
                forKey: .effectiveSupervisorRecentRawContextProfile
            ),
            effectiveReviewMemoryDepth: try container.decode(
                XTSupervisorReviewMemoryDepthProfile.self,
                forKey: .effectiveReviewMemoryDepth
            ),
            sTierReviewMemoryCeiling: XTMemoryServingProfile.parse(ceilingRaw) ?? .m2PlanReview,
            auditRef: try container.decodeIfPresent(String.self, forKey: .auditRef)
        )
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(
            configuredSupervisorRecentRawContextProfile,
            forKey: .configuredSupervisorRecentRawContextProfile
        )
        try container.encode(configuredReviewMemoryDepth, forKey: .configuredReviewMemoryDepth)
        try container.encode(
            recommendedSupervisorRecentRawContextProfile,
            forKey: .recommendedSupervisorRecentRawContextProfile
        )
        try container.encode(recommendedReviewMemoryDepth, forKey: .recommendedReviewMemoryDepth)
        try container.encode(
            effectiveSupervisorRecentRawContextProfile,
            forKey: .effectiveSupervisorRecentRawContextProfile
        )
        try container.encode(effectiveReviewMemoryDepth, forKey: .effectiveReviewMemoryDepth)
        try container.encode(sTierReviewMemoryCeiling.rawValue, forKey: .sTierReviewMemoryCeiling)
        try container.encodeIfPresent(auditRef, forKey: .auditRef)
    }
}

struct XTProjectMemoryPolicy: Equatable, Sendable {
    var trigger: String
    var configuredRecentProjectDialogueProfile: AXProjectRecentDialogueProfile
    var recommendedRecentProjectDialogueProfile: AXProjectRecentDialogueProfile
    var effectiveRecentProjectDialogueProfile: AXProjectRecentDialogueProfile
    var configuredProjectContextDepth: AXProjectContextDepthProfile
    var recommendedProjectContextDepth: AXProjectContextDepthProfile
    var effectiveProjectContextDepth: AXProjectContextDepthProfile
    var aTierMemoryCeiling: XTMemoryServingProfile
    var ceilingHit: Bool
    var effectiveServingProfile: XTMemoryServingProfile
    var resolution: XTMemoryAssemblyResolution

    var snapshot: XTProjectMemoryPolicySnapshot {
        XTProjectMemoryPolicySnapshot(
            configuredRecentProjectDialogueProfile: configuredRecentProjectDialogueProfile,
            configuredProjectContextDepth: configuredProjectContextDepth,
            recommendedRecentProjectDialogueProfile: recommendedRecentProjectDialogueProfile,
            recommendedProjectContextDepth: recommendedProjectContextDepth,
            effectiveRecentProjectDialogueProfile: effectiveRecentProjectDialogueProfile,
            effectiveProjectContextDepth: effectiveProjectContextDepth,
            aTierMemoryCeiling: aTierMemoryCeiling,
            auditRef: resolution.auditRef
        )
    }

    var promptContinuityContract: XTPromptContinuityContract {
        XTPromptContinuityContract(
            promptFloorTurns: AXProjectRecentDialogueProfile.hardFloorPairs * 2,
            promptTargetTurns: effectiveRecentProjectDialogueProfile.windowCeilingPairs.map { $0 * 2 },
            xtLocalWindowTurnLimit: XTMemoryHotWindowContract.default.turnLimit,
            xtLocalWindowStorageRole: XTMemoryHotWindowContract.default.storageRole
        )
    }
}

struct XTSupervisorMemoryPolicy: Equatable, Sendable {
    var assemblyPurpose: XTSupervisorMemoryAssemblyPurpose
    var dominantMode: SupervisorTurnMode
    var trigger: String
    var configuredSupervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile
    var recommendedSupervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile
    var effectiveSupervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile
    var configuredReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile
    var recommendedReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile
    var effectiveReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile
    var sTierReviewMemoryCeiling: XTMemoryServingProfile
    var purposeScopedReviewMemoryCap: XTMemoryServingProfile?
    var purposeCapApplied: Bool
    var minimumRequiredReviewServingProfile: XTMemoryServingProfile
    var ceilingHit: Bool
    var effectiveServingProfile: XTMemoryServingProfile
    var resolution: XTMemoryAssemblyResolution

    var snapshot: XTSupervisorMemoryPolicySnapshot {
        XTSupervisorMemoryPolicySnapshot(
            configuredSupervisorRecentRawContextProfile: configuredSupervisorRecentRawContextProfile,
            configuredReviewMemoryDepth: configuredReviewMemoryDepth,
            recommendedSupervisorRecentRawContextProfile: recommendedSupervisorRecentRawContextProfile,
            recommendedReviewMemoryDepth: recommendedReviewMemoryDepth,
            effectiveSupervisorRecentRawContextProfile: effectiveSupervisorRecentRawContextProfile,
            effectiveReviewMemoryDepth: effectiveReviewMemoryDepth,
            sTierReviewMemoryCeiling: sTierReviewMemoryCeiling,
            auditRef: resolution.auditRef
        )
    }

    var promptContinuityContract: XTPromptContinuityContract {
        XTPromptContinuityContract(
            promptFloorTurns: XTSupervisorRecentRawContextProfile.hardFloorPairs * 2,
            promptTargetTurns: effectiveSupervisorRecentRawContextProfile.windowCeilingPairs.map { $0 * 2 },
            xtLocalWindowTurnLimit: XTMemoryHotWindowContract.default.turnLimit,
            xtLocalWindowStorageRole: XTMemoryHotWindowContract.default.storageRole
        )
    }
}

struct XTPromptContinuityContract: Equatable, Sendable {
    var promptFloorTurns: Int
    var promptTargetTurns: Int?
    var xtLocalWindowTurnLimit: Int
    var xtLocalWindowStorageRole: XTMemoryLocalStorageRole

    var promptFloorSeparatedFromLocalHotWindow: Bool {
        true
    }
}

enum XTRoleAwareMemoryPolicyResolver {
    static func resolveProject(
        config: AXProjectConfig,
        governance: AXProjectResolvedGovernanceState?,
        userText: String,
        shouldExpandRecent: Bool,
        executionEvidencePresent: Bool,
        reviewGuidancePresent: Bool,
        automationCurrentStepPresent: Bool = false,
        automationCurrentStepState: String? = nil,
        automationVerificationPresent: Bool = false,
        automationVerificationAttentionPresent: Bool = false,
        automationBlockerPresent: Bool = false,
        automationRetryReasonPresent: Bool = false,
        automationRecoveryStatePresent: Bool = false,
        automationRecoveryReason: String? = nil,
        automationRecoveryDecision: String? = nil
    ) -> XTProjectMemoryPolicy {
        let trigger = projectTrigger(
            userText: userText,
            shouldExpandRecent: shouldExpandRecent,
            executionEvidencePresent: executionEvidencePresent,
            reviewGuidancePresent: reviewGuidancePresent,
            automationCurrentStepPresent: automationCurrentStepPresent,
            automationCurrentStepState: automationCurrentStepState,
            automationVerificationAttentionPresent: automationVerificationAttentionPresent,
            automationBlockerPresent: automationBlockerPresent,
            automationRetryReasonPresent: automationRetryReasonPresent,
            automationRecoveryStatePresent: automationRecoveryStatePresent,
            automationRecoveryReason: automationRecoveryReason,
            automationRecoveryDecision: automationRecoveryDecision
        )
        let configuredRecent = config.projectRecentDialogueProfile
        let recommendedRecent = recommendedProjectRecentDialogueProfile(
            trigger: trigger,
            executionEvidencePresent: executionEvidencePresent,
            reviewGuidancePresent: reviewGuidancePresent
        )
        let effectiveRecent = configuredRecent == .autoMax
            ? recommendedRecent
            : configuredRecent

        let executionTier = governance?.effectiveBundle.executionTier ?? config.executionTier
        let configuredDepth = config.projectContextDepthProfile
        let recommendedDepth = recommendedProjectContextDepth(
            executionTier: executionTier,
            trigger: trigger,
            executionEvidencePresent: executionEvidencePresent,
            reviewGuidancePresent: reviewGuidancePresent
        )
        let desiredServingProfile = resolvedProjectDesiredServingProfile(
            configuredDepth: configuredDepth,
            recommendedDepth: recommendedDepth,
            userText: userText
        )
        let ceiling = governance?.projectMemoryCeiling ?? executionTier.defaultProjectMemoryCeiling
        let effectiveServingProfile = min(desiredServingProfile, ceiling)
        let effectiveDepth = AXProjectContextDepthProfile.from(servingProfile: effectiveServingProfile)
        let ceilingHit = effectiveServingProfile.rank < desiredServingProfile.rank
        let selectedServingObjects = selectedProjectServingObjects(
            effectiveDepth: effectiveDepth,
            executionEvidencePresent: executionEvidencePresent,
            reviewGuidancePresent: reviewGuidancePresent,
            automationCurrentStepPresent: automationCurrentStepPresent,
            automationVerificationPresent: automationVerificationPresent,
            automationBlockerPresent: automationBlockerPresent,
            automationRetryReasonPresent: automationRetryReasonPresent
        )

        return XTProjectMemoryPolicy(
            trigger: trigger,
            configuredRecentProjectDialogueProfile: configuredRecent,
            recommendedRecentProjectDialogueProfile: recommendedRecent,
            effectiveRecentProjectDialogueProfile: effectiveRecent,
            configuredProjectContextDepth: configuredDepth,
            recommendedProjectContextDepth: recommendedDepth,
            effectiveProjectContextDepth: effectiveDepth,
            aTierMemoryCeiling: ceiling,
            ceilingHit: ceilingHit,
            effectiveServingProfile: effectiveServingProfile,
            resolution: XTMemoryAssemblyResolution(
                role: .projectAI,
                trigger: trigger,
                configuredDepth: configuredDepth.rawValue,
                recommendedDepth: recommendedDepth.rawValue,
                effectiveDepth: effectiveDepth.rawValue,
                ceilingFromTier: ceiling.rawValue,
                ceilingHit: ceilingHit,
                selectedSlots: selectedServingObjects,
                selectedPlanes: selectedProjectPlanes(
                    effectiveDepth: effectiveDepth,
                    executionEvidencePresent: executionEvidencePresent,
                    reviewGuidancePresent: reviewGuidancePresent,
                    automationCurrentStepPresent: automationCurrentStepPresent,
                    automationVerificationPresent: automationVerificationPresent,
                    automationBlockerPresent: automationBlockerPresent,
                    automationRetryReasonPresent: automationRetryReasonPresent
                ),
                selectedServingObjects: selectedServingObjects,
                excludedBlocks: excludedProjectBlocks(
                    effectiveDepth: effectiveDepth,
                    executionEvidencePresent: executionEvidencePresent,
                    reviewGuidancePresent: reviewGuidancePresent
                )
            )
        )
    }

    static func resolveSupervisor(
        configuredSupervisorRecentRawContextProfile: XTSupervisorRecentRawContextProfile,
        configuredReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile = .defaultProfile,
        reviewLevelHint: SupervisorReviewLevel,
        dominantMode: SupervisorTurnMode,
        focusedProjectSelected: Bool,
        crossLinkContextAvailable: Bool = false,
        userMessage: String,
        triggerSource: String? = nil,
        governanceReviewTrigger: SupervisorReviewTrigger? = nil,
        governanceReviewRunKind: SupervisorReviewRunKind? = nil,
        reviewMemoryCeiling: XTMemoryServingProfile?,
        privacyMode: XTPrivacyMode,
        assemblyPurpose: XTSupervisorMemoryAssemblyPurpose? = nil
    ) -> XTSupervisorMemoryPolicy {
        let trigger = supervisorTrigger(
            triggerSource: triggerSource,
            governanceReviewTrigger: governanceReviewTrigger,
            governanceReviewRunKind: governanceReviewRunKind,
            userMessage: userMessage,
            reviewLevelHint: reviewLevelHint,
            dominantMode: dominantMode
        )
        let resolvedAssemblyPurpose = assemblyPurpose ?? defaultSupervisorAssemblyPurpose(
            reviewLevelHint: reviewLevelHint,
            dominantMode: dominantMode,
            focusedProjectSelected: focusedProjectSelected,
            trigger: trigger
        )
        let recommendedRecentRaw = recommendedSupervisorRecentRawContextProfile(
            reviewLevelHint: reviewLevelHint,
            dominantMode: dominantMode,
            trigger: trigger
        )
        let privacyAdjustedConfiguredRecent = privacyMode.effectiveRecentRawContextProfile(
            configuredSupervisorRecentRawContextProfile
        )
        let effectiveRecentRaw = privacyAdjustedConfiguredRecent == .autoMax
            ? recommendedRecentRaw
            : privacyAdjustedConfiguredRecent

        let ceiling = reviewMemoryCeiling ?? defaultSupervisorReviewMemoryCeiling(
            reviewLevelHint: reviewLevelHint,
            dominantMode: dominantMode,
            userMessage: userMessage
        )
        let purposeScopedCap = purposeScopedSupervisorReviewMemoryCap(
            resolvedAssemblyPurpose
        )
        let effectiveCeiling = purposeScopedCap.map { min(ceiling, $0) } ?? ceiling
        let minimumRequiredProfile = min(
            minimumSupervisorServingFloor(
                reviewLevelHint: reviewLevelHint,
                focusedProjectSelected: focusedProjectSelected
            ),
            effectiveCeiling
        )
        let recommendedReviewDepth = recommendedSupervisorReviewMemoryDepth(
            assemblyPurpose: resolvedAssemblyPurpose,
            reviewLevelHint: reviewLevelHint,
            dominantMode: dominantMode,
            trigger: trigger,
            ceiling: effectiveCeiling
        )
        let desiredReviewServingProfile = resolvedSupervisorDesiredServingProfile(
            configuredReviewMemoryDepth: configuredReviewMemoryDepth,
            recommendedReviewMemoryDepth: recommendedReviewDepth,
            minimumRequiredProfile: minimumRequiredProfile,
            userMessage: userMessage
        )
        let purposeClampedDesiredReviewServingProfile = purposeScopedCap.map {
            min(desiredReviewServingProfile, $0)
        } ?? desiredReviewServingProfile
        let effectiveServingProfile = min(
            max(purposeClampedDesiredReviewServingProfile, minimumRequiredProfile),
            effectiveCeiling
        )
        let effectiveReviewDepth = XTSupervisorReviewMemoryDepthProfile.from(servingProfile: effectiveServingProfile)
        let ceilingHit = ceiling.rank < desiredReviewServingProfile.rank
        let purposeCapApplied = purposeScopedCap != nil
            && effectiveCeiling.rank < desiredReviewServingProfile.rank
            && effectiveCeiling.rank < ceiling.rank
        let selectedServingObjects = selectedSupervisorServingObjects(
            assemblyPurpose: resolvedAssemblyPurpose,
            effectiveServingProfile: effectiveServingProfile,
            focusedProjectSelected: focusedProjectSelected,
            dominantMode: dominantMode,
            crossLinkContextAvailable: crossLinkContextAvailable
        )

        return XTSupervisorMemoryPolicy(
            assemblyPurpose: resolvedAssemblyPurpose,
            dominantMode: dominantMode,
            trigger: trigger,
            configuredSupervisorRecentRawContextProfile: configuredSupervisorRecentRawContextProfile,
            recommendedSupervisorRecentRawContextProfile: recommendedRecentRaw,
            effectiveSupervisorRecentRawContextProfile: effectiveRecentRaw,
            configuredReviewMemoryDepth: configuredReviewMemoryDepth,
            recommendedReviewMemoryDepth: recommendedReviewDepth,
            effectiveReviewMemoryDepth: effectiveReviewDepth,
            sTierReviewMemoryCeiling: ceiling,
            purposeScopedReviewMemoryCap: purposeScopedCap,
            purposeCapApplied: purposeCapApplied,
            minimumRequiredReviewServingProfile: minimumRequiredProfile,
            ceilingHit: ceilingHit,
            effectiveServingProfile: effectiveServingProfile,
            resolution: XTMemoryAssemblyResolution(
                role: .supervisor,
                dominantMode: dominantMode.rawValue,
                trigger: trigger,
                configuredDepth: configuredReviewMemoryDepth.rawValue,
                recommendedDepth: recommendedReviewDepth.rawValue,
                effectiveDepth: effectiveReviewDepth.rawValue,
                ceilingFromTier: ceiling.rawValue,
                ceilingHit: ceilingHit,
                selectedSlots: selectedServingObjects,
                selectedPlanes: selectedSupervisorPlanes(for: dominantMode),
                selectedServingObjects: selectedServingObjects,
                excludedBlocks: excludedSupervisorBlocks(
                    assemblyPurpose: resolvedAssemblyPurpose,
                    focusedProjectSelected: focusedProjectSelected,
                    privacyMode: privacyMode
                )
            )
        )
    }

    private static func projectTrigger(
        userText: String,
        shouldExpandRecent: Bool,
        executionEvidencePresent: Bool,
        reviewGuidancePresent: Bool,
        automationCurrentStepPresent: Bool,
        automationCurrentStepState: String?,
        automationVerificationAttentionPresent: Bool,
        automationBlockerPresent: Bool,
        automationRetryReasonPresent: Bool,
        automationRecoveryStatePresent: Bool,
        automationRecoveryReason: String?,
        automationRecoveryDecision: String?
    ) -> String {
        let recoverySignalPresent = automationRecoveryStatePresent
            || normalizedProjectAutomationSignal(automationRecoveryReason) != nil
            || normalizedProjectAutomationSignal(automationRecoveryDecision) != nil
        let stepSignalPresent = automationCurrentStepPresent
            || normalizedProjectAutomationSignal(automationCurrentStepState) != nil

        if XTMemoryServingProfileSelector.fullScanRequestSignals(userText) {
            return "manual_full_scan_request"
        }
        if XTMemoryServingProfileSelector.reviewPlanRequestSignals(userText) {
            return "manual_review_request"
        }
        if shouldExpandRecent {
            return "resume_from_checkpoint"
        }
        if automationRetryReasonPresent {
            return "retry_execution"
        }
        if automationBlockerPresent {
            return "persistent_blocker"
        }
        if automationVerificationAttentionPresent {
            return "verification_gap"
        }
        if reviewGuidancePresent && executionEvidencePresent {
            return "review_guidance_follow_up"
        }
        if reviewGuidancePresent {
            return "guided_execution"
        }
        if recoverySignalPresent {
            return "restart_recovery"
        }
        if stepSignalPresent {
            return "execution_step_follow_up"
        }
        if executionEvidencePresent {
            return "evidence_backed_execution"
        }
        return "normal_reply"
    }

    private static func normalizedProjectAutomationSignal(_ raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func recommendedProjectRecentDialogueProfile(
        trigger: String,
        executionEvidencePresent: Bool,
        reviewGuidancePresent: Bool
    ) -> AXProjectRecentDialogueProfile {
        switch trigger {
        case "manual_full_scan_request":
            return .extended40Pairs
        case "manual_review_request",
             "resume_from_checkpoint",
             "restart_recovery",
             "retry_execution",
             "persistent_blocker",
             "verification_gap",
             "review_guidance_follow_up",
             "guided_execution",
             "execution_step_follow_up":
            return .deep20Pairs
        default:
            if executionEvidencePresent && reviewGuidancePresent {
                return .deep20Pairs
            }
            return .standard12Pairs
        }
    }

    private static func recommendedProjectContextDepth(
        executionTier: AXProjectExecutionTier,
        trigger: String,
        executionEvidencePresent: Bool,
        reviewGuidancePresent: Bool
    ) -> AXProjectContextDepthProfile {
        var depth = defaultProjectContextDepth(for: executionTier)

        switch trigger {
        case "manual_full_scan_request":
            depth = .full
        case "manual_review_request", "resume_from_checkpoint":
            depth = deeperProjectContextDepth(from: depth)
        case "restart_recovery":
            depth = max(depth, .deep)
        case "retry_execution", "persistent_blocker":
            depth = deeperProjectContextDepth(from: depth)
        case "verification_gap":
            depth = max(depth, .deep)
        case "review_guidance_follow_up", "guided_execution", "execution_step_follow_up":
            depth = max(depth, .deep)
        default:
            if executionEvidencePresent && reviewGuidancePresent {
                depth = max(depth, .deep)
            } else if executionEvidencePresent && executionTier >= .a3DeliverAuto {
                depth = max(depth, .deep)
            }
        }

        return depth
    }

    private static func defaultProjectContextDepth(
        for executionTier: AXProjectExecutionTier
    ) -> AXProjectContextDepthProfile {
        switch executionTier {
        case .a0Observe:
            return .lean
        case .a1Plan, .a2RepoAuto:
            return .balanced
        case .a3DeliverAuto, .a4OpenClaw:
            return .deep
        }
    }

    private static func deeperProjectContextDepth(
        from profile: AXProjectContextDepthProfile
    ) -> AXProjectContextDepthProfile {
        switch profile {
        case .lean:
            return .balanced
        case .balanced:
            return .deep
        case .deep, .full, .auto:
            return .full
        }
    }

    private static func resolvedProjectDesiredServingProfile(
        configuredDepth: AXProjectContextDepthProfile,
        recommendedDepth: AXProjectContextDepthProfile,
        userText: String
    ) -> XTMemoryServingProfile {
        let base = configuredDepth.servingProfile
            ?? recommendedDepth.servingProfile
            ?? XTMemoryServingProfile.m2PlanReview
        let requested = explicitProjectRequestedServingProfile(userText: userText)
        if let requested {
            return max(base, requested)
        }
        return base
    }

    private static func explicitProjectRequestedServingProfile(
        userText: String
    ) -> XTMemoryServingProfile? {
        if XTMemoryServingProfileSelector.fullScanRequestSignals(userText) {
            return .m4FullScan
        }
        if XTMemoryServingProfileSelector.reviewPlanRequestSignals(userText) {
            return .m2PlanReview
        }
        return nil
    }

    private static func selectedProjectServingObjects(
        effectiveDepth: AXProjectContextDepthProfile,
        executionEvidencePresent: Bool,
        reviewGuidancePresent: Bool,
        automationCurrentStepPresent: Bool,
        automationVerificationPresent: Bool,
        automationBlockerPresent: Bool,
        automationRetryReasonPresent: Bool
    ) -> [String] {
        var objects = [
            "recent_project_dialogue_window",
            "focused_project_anchor_pack",
        ]
        if automationCurrentStepPresent {
            objects.append("current_step")
        }
        if automationVerificationPresent {
            objects.append("verification_state")
        }
        if automationBlockerPresent {
            objects.append("blocker_state")
        }
        if automationRetryReasonPresent {
            objects.append("retry_reason")
        }
        objects += [
            "active_workflow",
            "selected_cross_link_hints",
        ]
        if effectiveDepth >= .deep {
            objects.append("longterm_outline")
        }
        if executionEvidencePresent {
            objects.append("execution_evidence")
        }
        if reviewGuidancePresent {
            objects.append("guidance")
        }
        return objects
    }

    private static func selectedProjectPlanes(
        effectiveDepth: AXProjectContextDepthProfile,
        executionEvidencePresent: Bool,
        reviewGuidancePresent: Bool,
        automationCurrentStepPresent: Bool,
        automationVerificationPresent: Bool,
        automationBlockerPresent: Bool,
        automationRetryReasonPresent: Bool
    ) -> [String] {
        var planes = [
            "project_dialogue_plane",
            "project_anchor_plane",
        ]
        if automationCurrentStepPresent
            || automationVerificationPresent
            || automationBlockerPresent
            || automationRetryReasonPresent {
            planes.append("execution_state_plane")
        }
        planes += [
            "workflow_plane",
            "cross_link_plane",
        ]
        if effectiveDepth >= .deep {
            planes.append("longterm_plane")
        }
        if executionEvidencePresent {
            planes.append("evidence_plane")
        }
        if reviewGuidancePresent {
            planes.append("guidance_plane")
        }
        return planes
    }

    private static func excludedProjectBlocks(
        effectiveDepth: AXProjectContextDepthProfile,
        executionEvidencePresent: Bool,
        reviewGuidancePresent: Bool
    ) -> [String] {
        var blocks = [
            "assistant_plane",
            "personal_memory",
            "portfolio_brief",
        ]
        if effectiveDepth < .deep {
            blocks.append("longterm_outline")
        }
        if !executionEvidencePresent {
            blocks.append("execution_evidence")
        }
        if !reviewGuidancePresent {
            blocks.append("guidance")
        }
        return blocks
    }

    private static func supervisorTrigger(
        triggerSource: String?,
        governanceReviewTrigger: SupervisorReviewTrigger?,
        governanceReviewRunKind: SupervisorReviewRunKind?,
        userMessage: String,
        reviewLevelHint: SupervisorReviewLevel,
        dominantMode: SupervisorTurnMode
    ) -> String {
        if normalizedTriggerSource(triggerSource) == "heartbeat" {
            return heartbeatGovernanceResolutionTrigger(
                reviewTrigger: governanceReviewTrigger,
                runKind: governanceReviewRunKind
            )
        }
        return supervisorTrigger(
            userMessage: userMessage,
            reviewLevelHint: reviewLevelHint,
            dominantMode: dominantMode
        )
    }

    private static func supervisorTrigger(
        userMessage: String,
        reviewLevelHint: SupervisorReviewLevel,
        dominantMode: SupervisorTurnMode
    ) -> String {
        if dominantMode == .portfolioReview {
            return "portfolio_reprioritize"
        }
        if XTMemoryServingProfileSelector.fullScanRequestSignals(userMessage) {
            return "manual_full_scan_request"
        }
        switch reviewLevelHint {
        case .r3Rescue:
            return "pre_high_risk_action"
        case .r2Strategic:
            return "manual_request"
        case .r1Pulse:
            return "user_turn"
        }
    }

    private static func normalizedTriggerSource(_ raw: String?) -> String {
        raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func heartbeatGovernanceResolutionTrigger(
        reviewTrigger: SupervisorReviewTrigger?,
        runKind: SupervisorReviewRunKind?
    ) -> String {
        if let reviewTrigger {
            switch reviewTrigger {
            case .periodicHeartbeat:
                return "heartbeat_periodic_heartbeat_review"
            case .periodicPulse:
                return "heartbeat_periodic_pulse_review"
            case .failureStreak:
                return "heartbeat_failure_streak_review"
            case .noProgressWindow:
                return "heartbeat_no_progress_review"
            case .blockerDetected:
                return "heartbeat_blocker_review"
            case .planDrift:
                return "heartbeat_plan_drift_review"
            case .preHighRiskAction:
                return "heartbeat_pre_high_risk_review"
            case .preDoneSummary:
                return "heartbeat_pre_done_review"
            case .manualRequest:
                return "heartbeat_manual_review_request"
            case .userOverride:
                return "heartbeat_user_override_review"
            }
        }

        if let runKind {
            switch runKind {
            case .pulse:
                return "heartbeat_pulse_review"
            case .brainstorm:
                return "heartbeat_brainstorm_review"
            case .eventDriven:
                return "heartbeat_event_review"
            case .manual:
                return "heartbeat_manual_review"
            }
        }

        return "heartbeat_governance_review"
    }

    private static func defaultSupervisorAssemblyPurpose(
        reviewLevelHint: SupervisorReviewLevel,
        dominantMode: SupervisorTurnMode,
        focusedProjectSelected: Bool,
        trigger: String
    ) -> XTSupervisorMemoryAssemblyPurpose {
        if dominantMode == .portfolioReview {
            return .portfolioReview
        }
        if trigger == "manual_request" || trigger == "manual_full_scan_request" || reviewLevelHint != .r1Pulse {
            return .governanceReview
        }
        if focusedProjectSelected && (dominantMode == .projectFirst || dominantMode == .hybrid) {
            return .projectAssist
        }
        return .conversation
    }

    private static func recommendedSupervisorRecentRawContextProfile(
        reviewLevelHint: SupervisorReviewLevel,
        dominantMode: SupervisorTurnMode,
        trigger: String
    ) -> XTSupervisorRecentRawContextProfile {
        if trigger == "manual_full_scan_request" || dominantMode == .portfolioReview {
            return .extended40Pairs
        }
        switch reviewLevelHint {
        case .r3Rescue:
            return .extended40Pairs
        case .r2Strategic:
            return dominantMode == .hybrid ? .extended40Pairs : .deep20Pairs
        case .r1Pulse:
            return dominantMode == .hybrid ? .deep20Pairs : .standard12Pairs
        }
    }

    private static func defaultSupervisorReviewMemoryCeiling(
        reviewLevelHint: SupervisorReviewLevel,
        dominantMode: SupervisorTurnMode,
        userMessage: String
    ) -> XTMemoryServingProfile {
        if dominantMode == .portfolioReview || XTMemoryServingProfileSelector.fullScanRequestSignals(userMessage) {
            return .m4FullScan
        }
        switch reviewLevelHint {
        case .r1Pulse:
            return .m2PlanReview
        case .r2Strategic:
            return .m3DeepDive
        case .r3Rescue:
            return .m4FullScan
        }
    }

    private static func minimumSupervisorServingFloor(
        reviewLevelHint: SupervisorReviewLevel,
        focusedProjectSelected: Bool
    ) -> XTMemoryServingProfile {
        switch reviewLevelHint {
        case .r1Pulse:
            return .m1Execute
        case .r2Strategic:
            return focusedProjectSelected ? .m3DeepDive : .m2PlanReview
        case .r3Rescue:
            return .m3DeepDive
        }
    }

    private static func recommendedSupervisorReviewMemoryDepth(
        assemblyPurpose: XTSupervisorMemoryAssemblyPurpose,
        reviewLevelHint: SupervisorReviewLevel,
        dominantMode: SupervisorTurnMode,
        trigger: String,
        ceiling: XTMemoryServingProfile
    ) -> XTSupervisorReviewMemoryDepthProfile {
        switch assemblyPurpose {
        case .conversation:
            return .compact
        case .projectAssist:
            return ceiling >= .m2PlanReview ? .planReview : .compact
        case .governanceReview, .portfolioReview:
            break
        }
        if dominantMode == .portfolioReview && ceiling >= .m4FullScan {
            return .fullScan
        }
        if trigger == "manual_full_scan_request" {
            return ceiling >= .m4FullScan ? .fullScan : .deepDive
        }
        switch reviewLevelHint {
        case .r1Pulse:
            return .compact
        case .r2Strategic:
            return ceiling >= .m3DeepDive ? .deepDive : .planReview
        case .r3Rescue:
            return ceiling >= .m4FullScan ? .fullScan : .deepDive
        }
    }

    private static func resolvedSupervisorDesiredServingProfile(
        configuredReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile,
        recommendedReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile,
        minimumRequiredProfile: XTMemoryServingProfile,
        userMessage: String
    ) -> XTMemoryServingProfile {
        let base = configuredReviewMemoryDepth.servingProfile
            ?? recommendedReviewMemoryDepth.servingProfile
            ?? minimumRequiredProfile
        let requested = explicitSupervisorRequestedServingProfile(userMessage: userMessage)
        let desired = requested.map { max(base, $0) } ?? base
        return max(desired, minimumRequiredProfile)
    }

    private static func purposeScopedSupervisorReviewMemoryCap(
        _ assemblyPurpose: XTSupervisorMemoryAssemblyPurpose
    ) -> XTMemoryServingProfile? {
        switch assemblyPurpose {
        case .conversation:
            return .m1Execute
        case .projectAssist:
            return .m2PlanReview
        case .governanceReview, .portfolioReview:
            return nil
        }
    }

    private static func explicitSupervisorRequestedServingProfile(
        userMessage: String
    ) -> XTMemoryServingProfile? {
        if XTMemoryServingProfileSelector.fullScanRequestSignals(userMessage) {
            return .m4FullScan
        }
        return XTMemoryServingProfileSelector.preferredSupervisorProfile(userMessage: userMessage)
    }

    private static func selectedSupervisorPlanes(
        for dominantMode: SupervisorTurnMode
    ) -> [String] {
        switch dominantMode {
        case .personalFirst:
            return ["continuity_lane", "assistant_plane"]
        case .projectFirst:
            return ["continuity_lane", "project_plane", "cross_link_plane"]
        case .hybrid:
            return ["continuity_lane", "assistant_plane", "project_plane", "cross_link_plane"]
        case .portfolioReview:
            return ["continuity_lane", "project_plane", "cross_link_plane"]
        }
    }

    private static func selectedSupervisorServingObjects(
        assemblyPurpose: XTSupervisorMemoryAssemblyPurpose,
        effectiveServingProfile: XTMemoryServingProfile,
        focusedProjectSelected: Bool,
        dominantMode: SupervisorTurnMode,
        crossLinkContextAvailable: Bool
    ) -> [String] {
        var objects = ["recent_raw_dialogue_window"]
        switch assemblyPurpose {
        case .conversation:
            objects.append("context_refs")
        case .projectAssist:
            if focusedProjectSelected {
                objects.append("focused_project_anchor_pack")
            }
            objects += ["delta_feed", "context_refs"]
        case .governanceReview:
            objects.append("portfolio_brief")
            if focusedProjectSelected {
                objects.append("focused_project_anchor_pack")
            }
            objects += ["delta_feed", "conflict_set", "context_refs", "evidence_pack"]
        case .portfolioReview:
            objects += ["portfolio_brief", "delta_feed", "conflict_set", "context_refs", "evidence_pack"]
        }
        if effectiveServingProfile >= .m3DeepDive && !objects.contains("evidence_pack") {
            objects.append("evidence_pack")
        }
        if crossLinkContextAvailable {
            switch dominantMode {
            case .personalFirst, .projectFirst, .hybrid, .portfolioReview:
                if !objects.contains("cross_link_refs") {
                    objects.append("cross_link_refs")
                }
            }
        }
        return objects
    }

    private static func excludedSupervisorBlocks(
        assemblyPurpose: XTSupervisorMemoryAssemblyPurpose,
        focusedProjectSelected: Bool,
        privacyMode: XTPrivacyMode
    ) -> [String] {
        var blocks: [String] = []
        switch assemblyPurpose {
        case .conversation:
            blocks += ["portfolio_brief", "focused_project_anchor_pack", "conflict_set", "evidence_pack"]
        case .projectAssist:
            blocks.append("portfolio_brief")
            if !focusedProjectSelected {
                blocks.append("focused_project_anchor_pack")
            }
        case .governanceReview:
            if !focusedProjectSelected {
                blocks.append("focused_project_anchor_pack")
            }
        case .portfolioReview:
            blocks.append("focused_project_anchor_pack")
        }
        if privacyMode == .tightenedContext {
            blocks.append("verbatim_recent_raw_expansion")
        }
        return blocks
    }
}

extension XTMemoryServingProfile: Comparable {
    static func < (lhs: XTMemoryServingProfile, rhs: XTMemoryServingProfile) -> Bool {
        lhs.rank < rhs.rank
    }
}

extension AXProjectContextDepthProfile: Comparable {
    var servingProfile: XTMemoryServingProfile? {
        switch self {
        case .lean:
            return .m1Execute
        case .balanced:
            return .m2PlanReview
        case .deep:
            return .m3DeepDive
        case .full:
            return .m4FullScan
        case .auto:
            return nil
        }
    }

    static func from(servingProfile: XTMemoryServingProfile) -> AXProjectContextDepthProfile {
        switch servingProfile {
        case .m0Heartbeat, .m1Execute:
            return .lean
        case .m2PlanReview:
            return .balanced
        case .m3DeepDive:
            return .deep
        case .m4FullScan:
            return .full
        }
    }

    static func < (lhs: AXProjectContextDepthProfile, rhs: AXProjectContextDepthProfile) -> Bool {
        (lhs.servingProfile?.rank ?? XTMemoryServingProfile.m4FullScan.rank)
        < (rhs.servingProfile?.rank ?? XTMemoryServingProfile.m4FullScan.rank)
    }
}
