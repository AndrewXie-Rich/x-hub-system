import Foundation
import RELFlowHubCore

enum HubMemoryContextBuilder {
    private struct Budget {
        var totalTokens: Int
        var l0Tokens: Int
        var l1Tokens: Int
        var l2Tokens: Int
        var l3Tokens: Int
        var l4Tokens: Int
    }

    private struct RedactionCounters {
        var redactedItems: Int = 0
        var privateDrops: Int = 0
    }

    private struct ClipResult {
        var text: String
        var truncated: Bool
    }

    private struct ServingObjectCompressionResult {
        var text: String
        var truncated: Bool
    }

    private struct PrivateTagSanitizeResult {
        var text: String
        var hadPrivate: Bool
        var malformed: Bool
        var redactedCount: Int
    }

    private struct ProjectFallback {
        var canonical: String
        var observations: String
        var hasStoredCanonical: Bool
    }

    private struct LongtermDisclosure {
        var longtermMode: String
        var retrievalAvailable: Bool
        var fulltextNotLoaded: Bool
    }

    private enum SupervisorReviewLevelHint: String {
        case r1Pulse = "r1_pulse"
        case r2Strategic = "r2_strategic"
        case r3Rescue = "r3_rescue"
    }

    private enum SupervisorServingProfileHint: String {
        case m0Heartbeat = "m0_heartbeat"
        case m1Execute = "m1_execute"
        case m2PlanReview = "m2_plan_review"
        case m3DeepDive = "m3_deep_dive"
        case m4FullScan = "m4_full_scan"

        var rank: Int {
            switch self {
            case .m0Heartbeat:
                return 0
            case .m1Execute:
                return 1
            case .m2PlanReview:
                return 2
            case .m3DeepDive:
                return 3
            case .m4FullScan:
                return 4
            }
        }
    }

    private struct SupervisorServingObjectBudgets {
        var dialogueWindowTokens: Int
        var portfolioBriefTokens: Int
        var focusedProjectAnchorPackTokens: Int
        var longtermOutlineTokens: Int
        var deltaFeedTokens: Int
        var conflictSetTokens: Int
        var contextRefsTokens: Int
        var evidencePackTokens: Int
    }

    private struct SupervisorServingGovernor {
        var reviewLevelHint: SupervisorReviewLevelHint
        var profileFloor: SupervisorServingProfileHint
        var minimumPack: [String]
        var compressionPolicy: String
        var objectFloorTokens: SupervisorServingObjectBudgets
    }

    private struct ContextRefLine {
        var refId: String
        var refKind: String
        var title: String
        var sourceScope: String
        var tokenCostHint: String
        var freshnessHint: String

        func render(includeTokenCostHint: Bool, includeFreshnessHint: Bool) -> String {
            var fields = [
                "- ref_id=\(refId)",
                "ref_kind=\(refKind)",
                "title=\(title)",
                "source_scope=\(sourceScope)",
            ]
            if includeTokenCostHint {
                fields.append("token_cost_hint=\(tokenCostHint)")
            }
            if includeFreshnessHint {
                fields.append("freshness_hint=\(freshnessHint)")
            }
            return fields.joined(separator: " ")
        }
    }

    private struct EvidencePackItem {
        var refId: String
        var title: String
        var sourceScope: String
        var freshness: String
        var whyIncluded: String
        var excerpt: String

        func render(includeFreshness: Bool, includeExcerpt: Bool) -> String {
            var fields = [
                "- ref_id=\(refId)",
                "title=\(title)",
                "source_scope=\(sourceScope)",
            ]
            if includeFreshness {
                fields.append("freshness=\(freshness)")
            }
            fields.append("why_included=\(whyIncluded)")
            if includeExcerpt {
                fields.append("excerpt=\(excerpt)")
            }
            return fields.joined(separator: " ")
        }
    }

    private struct EvidencePackBody {
        var evidenceGoal: String
        var items: [EvidencePackItem]
        var truncatedItems: Int
        var redactedItems: Int
        var auditRef: String
    }

    private struct LabeledBlock {
        var key: String
        var valueLines: [String]
        var inline: Bool

        func render() -> String {
            if inline {
                return "\(key): \(valueLines.first ?? "")"
            }
            return """
\(key):
\(valueLines.isEmpty ? "(none)" : valueLines.joined(separator: "\n"))
"""
        }
    }

    static func build(from req: IPCMemoryContextRequestPayload) -> IPCMemoryContextResponsePayload {
        let servingProfile = normalizedServingProfile(req.servingProfile)
        let budgets = normalizedBudgets(req.budgets, servingProfile: servingProfile)
        let mode = normalized(req.mode).lowercased()
        let disclosure = longtermDisclosure(for: mode)
        let supervisorGovernor = supervisorServingGovernor(
            req: req,
            mode: mode,
            servingProfile: servingProfile
        )
        var counters = RedactionCounters()
        var truncatedLayers: [String] = []

        let latestUserSeed = sanitized(req.latestUser, counters: &counters)
        let latestUser = latestUserSeed.isEmpty ? "(none)" : latestUserSeed

        let fallback = projectFallback(req: req)
        let canonicalSeed = mergedProjectText(
            primary: fallback.hasStoredCanonical ? fallback.canonical : normalized(req.canonicalText),
            secondary: fallback.hasStoredCanonical ? normalized(req.canonicalText) : fallback.canonical
        )
        let observationsSeed = mergedProjectText(
            primary: normalized(req.observationsText),
            secondary: fallback.observations
        )
        let dialogueWindowSeed = normalized(req.dialogueWindowText)
        let workingSeed = normalized(req.workingSetText)
        let rawSeed = firstNonEmpty(req.rawEvidenceText, rawEvidenceFallback(mode: mode))
        let servingObjectBudgets = supervisorServingObjectBudgets(
            req: req,
            budgets: budgets,
            mode: mode,
            governor: supervisorGovernor
        )
        let portfolioBrief = compressPortfolioBriefObject(
            sanitized(req.portfolioBriefText, counters: &counters),
            budgetTokens: servingObjectBudgets.portfolioBriefTokens
        )
        if portfolioBrief.truncated { truncatedLayers.append("l1_canonical") }
        let deltaFeed = compressDeltaFeedObject(
            sanitized(req.deltaFeedText, counters: &counters),
            budgetTokens: servingObjectBudgets.deltaFeedTokens
        )
        if deltaFeed.truncated { truncatedLayers.append("l2_observations") }
        let conflictSet = compressConflictSetObject(
            sanitized(req.conflictSetText, counters: &counters),
            budgetTokens: servingObjectBudgets.conflictSetTokens
        )
        if conflictSet.truncated { truncatedLayers.append("l2_observations") }
        let dialogueWindow = compressDialogueWindowObject(
            sanitized(dialogueWindowSeed, counters: &counters),
            budgetTokens: servingObjectBudgets.dialogueWindowTokens
        )
        if dialogueWindow.truncated { truncatedLayers.append("l3_working_set") }
        let focusedProjectAnchorPack = compressFocusedProjectAnchorPackObject(
            sanitized(req.focusedProjectAnchorPackText, counters: &counters),
            budgetTokens: servingObjectBudgets.focusedProjectAnchorPackTokens
        )
        if focusedProjectAnchorPack.truncated { truncatedLayers.append("l3_working_set") }
        let longtermOutline = compressLongtermOutlineObject(
            sanitized(req.longtermOutlineText, counters: &counters),
            budgetTokens: servingObjectBudgets.longtermOutlineTokens
        )
        if longtermOutline.truncated { truncatedLayers.append("l1_canonical") }

        let constitutionSeed = firstNonEmpty(
            req.constitutionHint,
            loadConstitutionOneLiner(latestUser: latestUser)
        )
        let l0 = clip(
            constitutionSeed.isEmpty ? defaultConstitution(latestUser: latestUser) : constitutionSeed,
            budgetTokens: budgets.l0Tokens,
            preferTail: false
        )
        if l0.truncated { truncatedLayers.append("l0_constitution") }

        let l1 = clip(
            sanitized(canonicalSeed, counters: &counters),
            budgetTokens: max(
                40,
                budgets.l1Tokens
                    - servingObjectBudgets.portfolioBriefTokens
                    - servingObjectBudgets.longtermOutlineTokens
            ),
            preferTail: true
        )
        if l1.truncated { truncatedLayers.append("l1_canonical") }

        let l2 = clip(
            sanitized(observationsSeed, counters: &counters),
            budgetTokens: max(
                40,
                budgets.l2Tokens
                    - servingObjectBudgets.deltaFeedTokens
                    - servingObjectBudgets.conflictSetTokens
            ),
            preferTail: true
        )
        if l2.truncated { truncatedLayers.append("l2_observations") }

        let l3 = clip(
            sanitized(workingSeed, counters: &counters),
            budgetTokens: max(
                0,
                budgets.l3Tokens
                    - servingObjectBudgets.dialogueWindowTokens
                    - servingObjectBudgets.focusedProjectAnchorPackTokens
            ),
            preferTail: true
        )
        if l3.truncated { truncatedLayers.append("l3_working_set") }

        let latestUserBudget = max(64, min(220, budgets.l4Tokens / 2))
        let contextRefs = compressContextRefsObject(
            sanitized(req.contextRefsText, counters: &counters),
            budgetTokens: servingObjectBudgets.contextRefsTokens
        )
        if contextRefs.truncated { truncatedLayers.append("l4_raw_evidence") }
        let evidencePack = compressEvidencePackObject(
            sanitized(req.evidencePackText, counters: &counters),
            budgetTokens: servingObjectBudgets.evidencePackTokens
        )
        if evidencePack.truncated { truncatedLayers.append("l4_raw_evidence") }
        let l4LatestUser = clip(
            latestUser,
            budgetTokens: latestUserBudget,
            preferTail: false
        )
        let l4LatestTokens = estimateTokens(l4LatestUser.text)
        let l4Overhead = estimateTokens("tool_results:\nlatest_user:")
        let l4RawBudget = max(
            0,
            budgets.l4Tokens
                - l4LatestTokens
                - l4Overhead
                - servingObjectBudgets.contextRefsTokens
                - servingObjectBudgets.evidencePackTokens
        )
        let l4Raw = clip(
            sanitized(rawSeed, counters: &counters),
            budgetTokens: l4RawBudget,
            preferTail: true
        )
        if l4Raw.truncated || l4LatestUser.truncated { truncatedLayers.append("l4_raw_evidence") }

        let l0Text = nonEmptyOrNone(l0.text)
        let l1Text = nonEmptyOrNone(l1.text)
        let l2Text = nonEmptyOrNone(l2.text)
        let l3Text = nonEmptyOrNone(l3.text)
        let l4RawText = nonEmptyOrNone(l4Raw.text)
        let l4LatestUserText = nonEmptyOrNone(l4LatestUser.text)
        let dialogueWindowText = normalized(dialogueWindow.text)
        let portfolioBriefText = normalized(portfolioBrief.text)
        let focusedProjectAnchorPackText = normalized(focusedProjectAnchorPack.text)
        let longtermOutlineText = normalized(longtermOutline.text)
        let deltaFeedText = normalized(deltaFeed.text)
        let conflictSetText = normalized(conflictSet.text)
        let contextRefsText = normalized(contextRefs.text)
        let evidencePackText = normalized(evidencePack.text)
        let servingProfileSection = servingProfileSection(servingProfile)
        let servingGovernorSection = supervisorServingGovernorSection(supervisorGovernor)
        let longtermDisclosureSection = longtermDisclosureSection(disclosure)
        let dialogueWindowSection = namedSection("DIALOGUE_WINDOW", body: dialogueWindowText)
        let portfolioBriefSection = namedSection("PORTFOLIO_BRIEF", body: portfolioBriefText)
        let focusedProjectAnchorPackSection = namedSection("FOCUSED_PROJECT_ANCHOR_PACK", body: focusedProjectAnchorPackText)
        let longtermOutlineSection = namedSection("LONGTERM_OUTLINE", body: longtermOutlineText)
        let deltaFeedSection = namedSection("DELTA_FEED", body: deltaFeedText)
        let conflictSetSection = namedSection("CONFLICT_SET", body: conflictSetText)
        let contextRefsSection = namedSection("CONTEXT_REFS", body: contextRefsText)
        let evidencePackSection = namedSection("EVIDENCE_PACK", body: evidencePackText)

        let memoryText = """
[MEMORY_V1]
\(servingProfileSection.isEmpty ? "" : "\(servingProfileSection)\n")
\(servingGovernorSection.isEmpty ? "" : "\(servingGovernorSection)\n")
\(longtermDisclosureSection)
\(dialogueWindowSection.isEmpty ? "" : "\n\(dialogueWindowSection)")
\(portfolioBriefSection.isEmpty ? "" : "\n\(portfolioBriefSection)")
\(focusedProjectAnchorPackSection.isEmpty ? "" : "\n\(focusedProjectAnchorPackSection)")
\(longtermOutlineSection.isEmpty ? "" : "\n\(longtermOutlineSection)")
\(deltaFeedSection.isEmpty ? "" : "\n\(deltaFeedSection)")
\(conflictSetSection.isEmpty ? "" : "\n\(conflictSetSection)")
\(contextRefsSection.isEmpty ? "" : "\n\(contextRefsSection)")
\(evidencePackSection.isEmpty ? "" : "\n\(evidencePackSection)")

[L0_CONSTITUTION]
\(l0Text)
[/L0_CONSTITUTION]

[L1_CANONICAL]
\(l1Text)
[/L1_CANONICAL]

[L2_OBSERVATIONS]
\(l2Text)
[/L2_OBSERVATIONS]

[L3_WORKING_SET]
\(l3Text)
[/L3_WORKING_SET]

[L4_RAW_EVIDENCE]
tool_results:
\(l4RawText)
latest_user:
\(l4LatestUserText)
[/L4_RAW_EVIDENCE]
[/MEMORY_V1]
"""

        let l1Used = estimateTokens(l1Text) + estimateTokens(portfolioBriefText) + estimateTokens(longtermOutlineText)
        let l2Used = estimateTokens(l2Text) + estimateTokens(deltaFeedText) + estimateTokens(conflictSetText)
        let l3Used = estimateTokens(dialogueWindowText) + estimateTokens(l3Text) + estimateTokens(focusedProjectAnchorPackText)
        let l4Used = estimateTokens("tool_results:\n\(l4RawText)\nlatest_user:\n\(l4LatestUserText)")
            + estimateTokens(contextRefsText)
            + estimateTokens(evidencePackText)
        let layerUsage: [IPCMemoryContextLayerUsage] = [
            IPCMemoryContextLayerUsage(layer: "l0_constitution", usedTokens: estimateTokens(l0Text), budgetTokens: budgets.l0Tokens),
            IPCMemoryContextLayerUsage(layer: "l1_canonical", usedTokens: l1Used, budgetTokens: budgets.l1Tokens),
            IPCMemoryContextLayerUsage(layer: "l2_observations", usedTokens: l2Used, budgetTokens: budgets.l2Tokens),
            IPCMemoryContextLayerUsage(layer: "l3_working_set", usedTokens: l3Used, budgetTokens: budgets.l3Tokens),
            IPCMemoryContextLayerUsage(
                layer: "l4_raw_evidence",
                usedTokens: l4Used,
                budgetTokens: budgets.l4Tokens
            ),
        ]
        let usedTotal = layerUsage.reduce(0) { $0 + max(0, $1.usedTokens) }

        let truncatedText = truncatedLayers.isEmpty ? "none" : truncatedLayers.joined(separator: ",")
        HubDiagnostics.log(
            "memory_context.build mode=\(mode.isEmpty ? "project" : mode) " +
            "used=\(usedTotal)/\(budgets.totalTokens) truncated=\(truncatedText) " +
            "redacted=\(counters.redactedItems) private=\(counters.privateDrops)"
        )

        return IPCMemoryContextResponsePayload(
            text: memoryText,
            source: "hub_memory_v1",
            resolvedProfile: servingProfile,
            longtermMode: disclosure.longtermMode,
            retrievalAvailable: disclosure.retrievalAvailable,
            fulltextNotLoaded: disclosure.fulltextNotLoaded,
            budgetTotalTokens: budgets.totalTokens,
            usedTotalTokens: usedTotal,
            layerUsage: layerUsage,
            truncatedLayers: truncatedLayers,
            redactedItems: counters.redactedItems,
            privateDrops: counters.privateDrops
        )
    }

    private static func normalizedBudgets(
        _ raw: IPCMemoryContextBudgets?,
        servingProfile: String?
    ) -> Budget {
        let defaults = defaultBudgets(for: servingProfile)
        let defaultTotal = defaults.totalTokens
        let defaultL0 = defaults.l0Tokens
        let defaultL1 = defaults.l1Tokens
        let defaultL2 = defaults.l2Tokens
        let defaultL3 = defaults.l3Tokens
        let defaultL4 = defaults.l4Tokens

        var total = clamp(raw?.totalTokens ?? defaultTotal, min: 400, max: 16_000)
        let l0 = clamp(raw?.l0Tokens ?? defaultL0, min: 24, max: 1_500)
        var l1 = clamp(raw?.l1Tokens ?? defaultL1, min: 40, max: 4_000)
        var l2 = clamp(raw?.l2Tokens ?? defaultL2, min: 40, max: 4_000)
        var l3 = clamp(raw?.l3Tokens ?? defaultL3, min: 80, max: 6_000)
        var l4 = clamp(raw?.l4Tokens ?? defaultL4, min: 60, max: 6_000)

        let sum = l0 + l1 + l2 + l3 + l4
        if sum > total {
            let fixed = l0
            let variable = max(1, sum - fixed)
            let room = max(160, total - fixed)
            let scale = Double(room) / Double(variable)
            l1 = max(40, Int(Double(l1) * scale))
            l2 = max(40, Int(Double(l2) * scale))
            l3 = max(80, Int(Double(l3) * scale))
            l4 = max(60, room - l1 - l2 - l3)
        }

        let newSum = l0 + l1 + l2 + l3 + l4
        if newSum > total {
            let overflow = newSum - total
            l3 = max(80, l3 - overflow)
        } else if newSum < total {
            l3 += (total - newSum)
        }

        total = max(total, l0 + l1 + l2 + l3 + l4)
        return Budget(totalTokens: total, l0Tokens: l0, l1Tokens: l1, l2Tokens: l2, l3Tokens: l3, l4Tokens: l4)
    }

    private static func defaultBudgets(for servingProfile: String?) -> Budget {
        switch servingProfile {
        case "m0_heartbeat":
            return Budget(totalTokens: 960, l0Tokens: 60, l1Tokens: 260, l2Tokens: 140, l3Tokens: 340, l4Tokens: 160)
        case "m2_plan_review":
            return Budget(totalTokens: 3_000, l0Tokens: 80, l1Tokens: 860, l2Tokens: 620, l3Tokens: 920, l4Tokens: 520)
        case "m3_deep_dive":
            return Budget(totalTokens: 5_200, l0Tokens: 90, l1Tokens: 1_500, l2Tokens: 1_120, l3Tokens: 1_700, l4Tokens: 790)
        case "m4_full_scan":
            return Budget(totalTokens: 8_000, l0Tokens: 110, l1Tokens: 2_200, l2Tokens: 1_900, l3Tokens: 2_650, l4Tokens: 1_140)
        default:
            return Budget(totalTokens: 1_700, l0Tokens: 70, l1Tokens: 420, l2Tokens: 240, l3Tokens: 560, l4Tokens: 410)
        }
    }

    private static func normalizedServingProfile(_ raw: String?) -> String? {
        let trimmed = normalized(raw).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parsedSupervisorServingProfile(
        _ raw: String?
    ) -> SupervisorServingProfileHint {
        SupervisorServingProfileHint(rawValue: normalizedServingProfile(raw) ?? "")
            ?? .m1Execute
    }

    private static func normalizedSupervisorReviewLevelHint(
        _ raw: String?
    ) -> SupervisorReviewLevelHint? {
        SupervisorReviewLevelHint(rawValue: normalized(raw).lowercased())
    }

    private static func defaultSupervisorReviewLevel(
        for profile: SupervisorServingProfileHint
    ) -> SupervisorReviewLevelHint {
        switch profile {
        case .m3DeepDive, .m4FullScan:
            return .r3Rescue
        case .m2PlanReview:
            return .r2Strategic
        default:
            return .r1Pulse
        }
    }

    private static func minimumSupervisorServingProfile(
        for reviewLevelHint: SupervisorReviewLevelHint,
        hasFocusedProjectAnchor: Bool
    ) -> SupervisorServingProfileHint {
        switch reviewLevelHint {
        case .r1Pulse:
            return .m1Execute
        case .r2Strategic:
            return hasFocusedProjectAnchor ? .m3DeepDive : .m2PlanReview
        case .r3Rescue:
            return .m3DeepDive
        }
    }

    private static func supervisorServingGovernor(
        req: IPCMemoryContextRequestPayload,
        mode: String,
        servingProfile: String?
    ) -> SupervisorServingGovernor? {
        guard mode == "supervisor_orchestration" else { return nil }

        let resolvedProfile = parsedSupervisorServingProfile(servingProfile)
        let explicitReviewLevel = normalizedSupervisorReviewLevelHint(req.reviewLevelHint)
        let reviewLevelHint = explicitReviewLevel ?? defaultSupervisorReviewLevel(for: resolvedProfile)
        let hasFocusedProjectAnchor = !normalized(req.focusedProjectAnchorPackText).isEmpty
        let profileFloor = minimumSupervisorServingProfile(
            for: reviewLevelHint,
            hasFocusedProjectAnchor: hasFocusedProjectAnchor
        )
        let shouldApplyReviewPack = explicitReviewLevel != nil || resolvedProfile.rank >= profileFloor.rank
        let minimumPack = orderedSupervisorMinimumPack(
            servingProfile: resolvedProfile,
            reviewLevelHint: reviewLevelHint,
            applyReviewPack: shouldApplyReviewPack,
            hasFocusedProjectAnchor: hasFocusedProjectAnchor
        )
        let compressionPolicy: String
        switch reviewLevelHint {
        case .r1Pulse:
            compressionPolicy = "protect_anchor_then_delta_then_portfolio"
        case .r2Strategic:
            compressionPolicy = hasFocusedProjectAnchor
                ? "protect_anchor_longterm_decision_blocker_and_evidence_first"
                : "protect_anchor_conflict_longterm_then_refs"
        case .r3Rescue:
            compressionPolicy = "protect_anchor_conflict_and_evidence_first"
        }

        return SupervisorServingGovernor(
            reviewLevelHint: reviewLevelHint,
            profileFloor: profileFloor,
            minimumPack: minimumPack,
            compressionPolicy: compressionPolicy,
            objectFloorTokens: mergedSupervisorObjectBudgetFloors(
                servingProfile: resolvedProfile,
                reviewLevelHint: reviewLevelHint,
                applyReviewFloor: shouldApplyReviewPack,
                hasFocusedProjectAnchor: hasFocusedProjectAnchor
            )
        )
    }

    private static func minimumPackForSupervisorServingProfile(
        _ servingProfile: SupervisorServingProfileHint
    ) -> [String] {
        switch servingProfile {
        case .m0Heartbeat:
            return ["portfolio_brief", "delta_feed"]
        case .m1Execute:
            return ["portfolio_brief", "focused_project_anchor_pack", "delta_feed"]
        case .m2PlanReview:
            return [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs"
            ]
        case .m3DeepDive, .m4FullScan:
            return [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack"
            ]
        }
    }

    private static func minimumPackForSupervisorReviewLevel(
        _ reviewLevelHint: SupervisorReviewLevelHint,
        hasFocusedProjectAnchor: Bool
    ) -> [String] {
        switch reviewLevelHint {
        case .r1Pulse:
            return ["portfolio_brief", "focused_project_anchor_pack", "delta_feed"]
        case .r2Strategic:
            return hasFocusedProjectAnchor ? [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack"
            ] : [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs"
            ]
        case .r3Rescue:
            return [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack"
            ]
        }
    }

    private static func orderedSupervisorMinimumPack(
        servingProfile: SupervisorServingProfileHint,
        reviewLevelHint: SupervisorReviewLevelHint,
        applyReviewPack: Bool,
        hasFocusedProjectAnchor: Bool
    ) -> [String] {
        let profilePack = minimumPackForSupervisorServingProfile(servingProfile)
        guard applyReviewPack else { return profilePack }
        let reviewPack = minimumPackForSupervisorReviewLevel(
            reviewLevelHint,
            hasFocusedProjectAnchor: hasFocusedProjectAnchor
        )
        let reviewFloor = minimumSupervisorServingProfile(
            for: reviewLevelHint,
            hasFocusedProjectAnchor: hasFocusedProjectAnchor
        )
        let orderedPacks = reviewFloor.rank > servingProfile.rank
            ? [reviewPack, profilePack]
            : [profilePack, reviewPack]
        var seen = Set<String>()
        var ordered: [String] = []
        for pack in orderedPacks {
            for item in pack {
                guard seen.insert(item).inserted else { continue }
                ordered.append(item)
            }
        }
        return ordered
    }

    private static func supervisorServingGovernorSection(
        _ governor: SupervisorServingGovernor?
    ) -> String {
        guard let governor else { return "" }
        return """
[SERVING_GOVERNOR]
review_level_hint: \(governor.reviewLevelHint.rawValue)
profile_floor: \(governor.profileFloor.rawValue)
minimum_pack: \(governor.minimumPack.isEmpty ? "(none)" : governor.minimumPack.joined(separator: ", "))
compression_policy: \(governor.compressionPolicy)
[/SERVING_GOVERNOR]
"""
    }

    private static func servingProfileSection(_ servingProfile: String?) -> String {
        guard let servingProfile, !servingProfile.isEmpty else { return "" }
        return """
[SERVING_PROFILE]
profile_id: \(servingProfile)
[/SERVING_PROFILE]
"""
    }

    private static func longtermDisclosure(for mode: String) -> LongtermDisclosure {
        switch mode {
        case "project", "project_chat":
            return LongtermDisclosure(
                longtermMode: "progressive_disclosure",
                retrievalAvailable: true,
                fulltextNotLoaded: true
            )
        case "lane_handoff":
            return LongtermDisclosure(
                longtermMode: "denied",
                retrievalAvailable: false,
                fulltextNotLoaded: true
            )
        default:
            return LongtermDisclosure(
                longtermMode: "summary_only",
                retrievalAvailable: false,
                fulltextNotLoaded: true
            )
        }
    }

    private static func longtermDisclosureSection(_ disclosure: LongtermDisclosure) -> String {
        """
[LONGTERM_MEMORY]
longterm_mode=\(disclosure.longtermMode)
retrieval_available=\(disclosure.retrievalAvailable ? "true" : "false")
fulltext_not_loaded=\(disclosure.fulltextNotLoaded ? "true" : "false")
[/LONGTERM_MEMORY]
"""
    }

    private static func supervisorObjectBudgetFloors(
        for servingProfile: SupervisorServingProfileHint
    ) -> SupervisorServingObjectBudgets {
        switch servingProfile {
        case .m0Heartbeat:
            return SupervisorServingObjectBudgets(
                dialogueWindowTokens: 180,
                portfolioBriefTokens: 100,
                focusedProjectAnchorPackTokens: 0,
                longtermOutlineTokens: 0,
                deltaFeedTokens: 80,
                conflictSetTokens: 0,
                contextRefsTokens: 0,
                evidencePackTokens: 0
            )
        case .m1Execute:
            return SupervisorServingObjectBudgets(
                dialogueWindowTokens: 360,
                portfolioBriefTokens: 140,
                focusedProjectAnchorPackTokens: 220,
                longtermOutlineTokens: 0,
                deltaFeedTokens: 120,
                conflictSetTokens: 0,
                contextRefsTokens: 0,
                evidencePackTokens: 0
            )
        case .m2PlanReview:
            return SupervisorServingObjectBudgets(
                dialogueWindowTokens: 520,
                portfolioBriefTokens: 160,
                focusedProjectAnchorPackTokens: 260,
                longtermOutlineTokens: 140,
                deltaFeedTokens: 140,
                conflictSetTokens: 140,
                contextRefsTokens: 120,
                evidencePackTokens: 0
            )
        case .m3DeepDive:
            return SupervisorServingObjectBudgets(
                dialogueWindowTokens: 760,
                portfolioBriefTokens: 180,
                focusedProjectAnchorPackTokens: 320,
                longtermOutlineTokens: 160,
                deltaFeedTokens: 160,
                conflictSetTokens: 160,
                contextRefsTokens: 130,
                evidencePackTokens: 180
            )
        case .m4FullScan:
            return SupervisorServingObjectBudgets(
                dialogueWindowTokens: 1_040,
                portfolioBriefTokens: 220,
                focusedProjectAnchorPackTokens: 360,
                longtermOutlineTokens: 200,
                deltaFeedTokens: 220,
                conflictSetTokens: 180,
                contextRefsTokens: 160,
                evidencePackTokens: 220
            )
        }
    }

    private static func supervisorObjectBudgetFloors(
        for reviewLevelHint: SupervisorReviewLevelHint,
        hasFocusedProjectAnchor: Bool
    ) -> SupervisorServingObjectBudgets {
        switch reviewLevelHint {
        case .r1Pulse:
            return SupervisorServingObjectBudgets(
                dialogueWindowTokens: 360,
                portfolioBriefTokens: 140,
                focusedProjectAnchorPackTokens: 220,
                longtermOutlineTokens: 0,
                deltaFeedTokens: 120,
                conflictSetTokens: 0,
                contextRefsTokens: 0,
                evidencePackTokens: 0
            )
        case .r2Strategic:
            return hasFocusedProjectAnchor ? SupervisorServingObjectBudgets(
                dialogueWindowTokens: 520,
                portfolioBriefTokens: 180,
                focusedProjectAnchorPackTokens: 320,
                longtermOutlineTokens: 180,
                deltaFeedTokens: 150,
                conflictSetTokens: 180,
                contextRefsTokens: 150,
                evidencePackTokens: 180
            ) : SupervisorServingObjectBudgets(
                dialogueWindowTokens: 480,
                portfolioBriefTokens: 140,
                focusedProjectAnchorPackTokens: 240,
                longtermOutlineTokens: 140,
                deltaFeedTokens: 120,
                conflictSetTokens: 140,
                contextRefsTokens: 120,
                evidencePackTokens: 0
            )
        case .r3Rescue:
            return SupervisorServingObjectBudgets(
                dialogueWindowTokens: 560,
                portfolioBriefTokens: 140,
                focusedProjectAnchorPackTokens: 260,
                longtermOutlineTokens: 140,
                deltaFeedTokens: 120,
                conflictSetTokens: 160,
                contextRefsTokens: 130,
                evidencePackTokens: 180
            )
        }
    }

    private static func mergedSupervisorObjectBudgetFloors(
        servingProfile: SupervisorServingProfileHint,
        reviewLevelHint: SupervisorReviewLevelHint,
        applyReviewFloor: Bool,
        hasFocusedProjectAnchor: Bool
    ) -> SupervisorServingObjectBudgets {
        let profileFloors = supervisorObjectBudgetFloors(for: servingProfile)
        guard applyReviewFloor else { return profileFloors }
        let reviewFloors = supervisorObjectBudgetFloors(
            for: reviewLevelHint,
            hasFocusedProjectAnchor: hasFocusedProjectAnchor
        )
        return SupervisorServingObjectBudgets(
            dialogueWindowTokens: max(profileFloors.dialogueWindowTokens, reviewFloors.dialogueWindowTokens),
            portfolioBriefTokens: max(profileFloors.portfolioBriefTokens, reviewFloors.portfolioBriefTokens),
            focusedProjectAnchorPackTokens: max(
                profileFloors.focusedProjectAnchorPackTokens,
                reviewFloors.focusedProjectAnchorPackTokens
            ),
            longtermOutlineTokens: max(profileFloors.longtermOutlineTokens, reviewFloors.longtermOutlineTokens),
            deltaFeedTokens: max(profileFloors.deltaFeedTokens, reviewFloors.deltaFeedTokens),
            conflictSetTokens: max(profileFloors.conflictSetTokens, reviewFloors.conflictSetTokens),
            contextRefsTokens: max(profileFloors.contextRefsTokens, reviewFloors.contextRefsTokens),
            evidencePackTokens: max(profileFloors.evidencePackTokens, reviewFloors.evidencePackTokens)
        )
    }

    private static func capLayerObjectBudgets(
        primary: Int,
        secondary: Int,
        room: Int
    ) -> (Int, Int) {
        let boundedRoom = max(0, room)
        guard boundedRoom > 0 else { return (0, 0) }

        var first = max(0, primary)
        var second = max(0, secondary)
        let sum = first + second
        guard sum > boundedRoom else { return (first, second) }

        let scale = Double(boundedRoom) / Double(max(1, sum))
        first = min(boundedRoom, Int(Double(first) * scale))
        second = min(max(0, boundedRoom - first), Int(Double(second) * scale))

        let used = first + second
        let remainder = max(0, boundedRoom - used)
        if remainder > 0 {
            if primary >= secondary {
                first += remainder
            } else {
                second += remainder
            }
        }
        return (first, second)
    }

    private static func supervisorServingObjectBudgets(
        req: IPCMemoryContextRequestPayload,
        budgets: Budget,
        mode: String,
        governor: SupervisorServingGovernor?
    ) -> SupervisorServingObjectBudgets {
        guard mode == "supervisor_orchestration",
              let governor else {
            return SupervisorServingObjectBudgets(
                dialogueWindowTokens: 0,
                portfolioBriefTokens: 0,
                focusedProjectAnchorPackTokens: 0,
                longtermOutlineTokens: 0,
                deltaFeedTokens: 0,
                conflictSetTokens: 0,
                contextRefsTokens: 0,
                evidencePackTokens: 0
            )
        }

        let l1Room = max(0, budgets.l1Tokens - 40)
        let l2Room = max(0, budgets.l2Tokens - 40)
        let l3Room = max(0, budgets.l3Tokens - 80)
        let latestUserBudget = max(64, min(220, budgets.l4Tokens / 2))
        let l4Overhead = estimateTokens("tool_results:\nlatest_user:")
        let l4Room = max(0, budgets.l4Tokens - latestUserBudget - l4Overhead)

        let portfolioDesired = normalized(req.portfolioBriefText).isEmpty
            ? 0
            : min(max(governor.objectFloorTokens.portfolioBriefTokens, budgets.l1Tokens / 2), 520)
        let longtermDesired = normalized(req.longtermOutlineText).isEmpty
            ? 0
            : min(max(governor.objectFloorTokens.longtermOutlineTokens, budgets.l1Tokens / 4), 360)
        let (portfolio, longterm) = capLayerObjectBudgets(
            primary: portfolioDesired,
            secondary: longtermDesired,
            room: l1Room
        )

        let deltaDesired = normalized(req.deltaFeedText).isEmpty
            ? 0
            : min(max(governor.objectFloorTokens.deltaFeedTokens, budgets.l2Tokens / 2), 420)
        let conflictSetDesired = normalized(req.conflictSetText).isEmpty
            ? 0
            : min(max(governor.objectFloorTokens.conflictSetTokens, budgets.l2Tokens / 3), 320)
        let (delta, conflictSet) = capLayerObjectBudgets(
            primary: deltaDesired,
            secondary: conflictSetDesired,
            room: l2Room
        )

        let dialogueWindowDesired = normalized(req.dialogueWindowText).isEmpty
            ? 0
            : min(max(governor.objectFloorTokens.dialogueWindowTokens, budgets.l3Tokens / 2), max(0, l3Room))
        let anchorDesired = normalized(req.focusedProjectAnchorPackText).isEmpty
            ? 0
            : min(max(governor.objectFloorTokens.focusedProjectAnchorPackTokens, budgets.l3Tokens / 3), max(0, l3Room))
        // Recent raw dialogue is the continuity floor and must win over anchor-pack expansion
        // when L3 is tight. Anchor packs can degrade first; the raw floor should not.
        let dialogueWindow = min(max(0, dialogueWindowDesired), max(0, l3Room))
        let anchor = min(max(0, anchorDesired), max(0, l3Room - dialogueWindow))

        let contextRefsDesired = normalized(req.contextRefsText).isEmpty
            ? 0
            : min(max(governor.objectFloorTokens.contextRefsTokens, budgets.l4Tokens / 4), 260)
        let evidencePackDesired = normalized(req.evidencePackText).isEmpty
            ? 0
            : min(max(governor.objectFloorTokens.evidencePackTokens, budgets.l4Tokens / 3), 420)
        let (contextRefs, evidencePack) = capLayerObjectBudgets(
            primary: contextRefsDesired,
            secondary: evidencePackDesired,
            room: l4Room
        )

        return SupervisorServingObjectBudgets(
            dialogueWindowTokens: dialogueWindow,
            portfolioBriefTokens: portfolio,
            focusedProjectAnchorPackTokens: anchor,
            longtermOutlineTokens: longterm,
            deltaFeedTokens: delta,
            conflictSetTokens: conflictSet,
            contextRefsTokens: contextRefs,
            evidencePackTokens: evidencePack
        )
    }

    private static func namedSection(_ tag: String, body: String) -> String {
        let normalizedBody = normalized(body)
        guard !normalizedBody.isEmpty else { return "" }
        return """
[\(tag)]
\(normalizedBody)
[/\(tag)]
"""
    }

    private static func compressDialogueWindowObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }
        let keys = [
            "window_profile",
            "raw_window_floor_pairs",
            "raw_window_ceiling_pairs",
            "raw_window_selected_pairs",
            "eligible_messages",
            "low_signal_dropped_messages",
            "raw_window_source",
            "continuity_floor_satisfied",
            "truncation_after_floor",
            "current_turn_refs",
            "recent_user_intent",
            "recent_assistant_commitments",
            "raw_messages",
            "rolling_dialogue_digest",
            "focused_project_recent_dialogue_recovery",
        ]
        let parsed = parseKnownBlocks(clean, keys: keys)
        guard !parsed.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        let floorPairs = parsedInlineIntValue(parsed, key: "raw_window_floor_pairs") ?? 8
        let floorRawMessages = max(1, floorPairs * 2)

        var candidates: [(String, Int, [String: Int], [LabeledBlock])] = []

        var supportTrimmed = parsed
        var supportTrimmedFields: [String: Int] = [:]
        trimBlockLines(
            &supportTrimmed,
            key: "current_turn_refs",
            maxLines: 2,
            counterKey: "current_turn_refs_items",
            counts: &supportTrimmedFields
        )
        trimBlockLines(
            &supportTrimmed,
            key: "recent_user_intent",
            maxLines: 2,
            counterKey: "recent_user_intent_items",
            counts: &supportTrimmedFields
        )
        trimBlockLines(
            &supportTrimmed,
            key: "recent_assistant_commitments",
            maxLines: 2,
            counterKey: "recent_assistant_commitments_items",
            counts: &supportTrimmedFields
        )
        dropBlock(
            &supportTrimmed,
            key: "rolling_dialogue_digest",
            counterKey: "rolling_dialogue_digest",
            counts: &supportTrimmedFields
        )
        dropBlock(
            &supportTrimmed,
            key: "focused_project_recent_dialogue_recovery",
            counterKey: "focused_project_recent_dialogue_recovery",
            counts: &supportTrimmedFields
        )
        updateDialogueWindowSummary(
            &supportTrimmed,
            floorPairs: floorPairs,
            markTruncated: !supportTrimmedFields.isEmpty
        )
        candidates.append((
            "drop_supporting_context_before_raw_floor",
            totalDroppedCount(supportTrimmedFields),
            supportTrimmedFields,
            supportTrimmed
        ))

        var floorTrimmed = supportTrimmed
        var floorTrimmedFields = supportTrimmedFields
        trimBlockLinesFromTail(
            &floorTrimmed,
            key: "raw_messages",
            maxLines: floorRawMessages,
            counterKey: "raw_messages_items",
            counts: &floorTrimmedFields
        )
        updateDialogueWindowSummary(
            &floorTrimmed,
            floorPairs: floorPairs,
            markTruncated: !floorTrimmedFields.isEmpty
        )
        candidates.append((
            "keep_recent_raw_floor",
            totalDroppedCount(floorTrimmedFields),
            floorTrimmedFields,
            floorTrimmed
        ))

        var coreFloor = floorTrimmed
        var coreFloorFields = floorTrimmedFields
        keepOnlyBlocks(
            &coreFloor,
            keys: [
                "window_profile",
                "raw_window_floor_pairs",
                "raw_window_ceiling_pairs",
                "raw_window_selected_pairs",
                "eligible_messages",
                "low_signal_dropped_messages",
                "raw_window_source",
                "continuity_floor_satisfied",
                "truncation_after_floor",
                "raw_messages",
            ],
            counts: &coreFloorFields
        )
        updateDialogueWindowSummary(
            &coreFloor,
            floorPairs: floorPairs,
            markTruncated: !coreFloorFields.isEmpty
        )
        candidates.append((
            "keep_core_metadata_and_recent_raw_floor",
            totalDroppedCount(coreFloorFields),
            coreFloorFields,
            coreFloor
        ))

        return firstFittingServingObjectCandidate(
            candidates,
            budgetTokens: budgetTokens
        ) ?? clippedServingObjectFallback(
            renderBlocks(coreFloor),
            budgetTokens: budgetTokens,
            reason: "clip_core_recent_raw_floor",
            droppedItems: totalDroppedCount(coreFloorFields),
            droppedFields: coreFloorFields
        )
    }

    private static func compressPortfolioBriefObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }

        let keys = [
            "managed_projects",
            "active_projects",
            "blocked_projects",
            "focus_candidate_project",
            "priority_order",
            "top_blocked_projects",
        ]
        let parsed = parseKnownBlocks(clean, keys: keys)
        guard !parsed.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        var candidates: [(String, Int, [String: Int], [LabeledBlock])] = []

        var trimmed = parsed
        var droppedFields: [String: Int] = [:]
        let droppedPriority4 = trimBlockLines(&trimmed, key: "priority_order", maxLines: 4, counterKey: "priority_order_items", counts: &droppedFields)
        let droppedBlocked2 = trimBlockLines(&trimmed, key: "top_blocked_projects", maxLines: 2, counterKey: "top_blocked_projects_items", counts: &droppedFields)
        candidates.append(("drop_tail_items", droppedPriority4 + droppedBlocked2, droppedFields, trimmed))

        var tight = parsed
        var tightFields: [String: Int] = [:]
        let droppedPriority2 = trimBlockLines(&tight, key: "priority_order", maxLines: 2, counterKey: "priority_order_items", counts: &tightFields)
        let droppedBlocked1 = trimBlockLines(&tight, key: "top_blocked_projects", maxLines: 1, counterKey: "top_blocked_projects_items", counts: &tightFields)
        candidates.append(("drop_tail_items", droppedPriority2 + droppedBlocked1, tightFields, tight))

        var noBlocked = tight
        var noBlockedFields = tightFields
        dropBlock(&noBlocked, key: "top_blocked_projects", counterKey: "top_blocked_projects", counts: &noBlockedFields)
        candidates.append(("drop_tail_items_and_fields", droppedPriority2 + droppedBlocked1, noBlockedFields, noBlocked))

        var summaryOnly = parsed
        var summaryFields: [String: Int] = [:]
        keepOnlyBlocks(
            &summaryOnly,
            keys: [
                "managed_projects",
                "active_projects",
                "blocked_projects",
                "focus_candidate_project",
            ],
            counts: &summaryFields
        )
        candidates.append(("keep_summary_only", 0, summaryFields, summaryOnly))

        return firstFittingServingObjectCandidate(
            candidates,
            budgetTokens: budgetTokens
        ) ?? clippedServingObjectFallback(
            renderBlocks(summaryOnly),
            budgetTokens: budgetTokens,
            reason: "clip_summary_only",
            droppedItems: 0,
            droppedFields: summaryFields
        )
    }

    private static func compressFocusedProjectAnchorPackObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }

        let keys = [
            "focus_source",
            "project",
            "memory_source",
            "runtime_state",
            "goal",
            "done_definition",
            "constraints",
            "approved_decisions",
            "longterm_outline",
            "background_hints",
            "governance",
            "latest_review_note",
            "latest_guidance_injection",
            "pending_ack_guidance",
            "missing_anchor_fields",
            "current_state",
            "next_step",
            "blocker",
            "active_job_id",
            "active_job_goal",
            "active_job_status",
            "active_plan_id",
            "active_plan_status",
            "active_plan_steps",
            "next_pending_steps",
            "attention_steps",
            "active_skill_request_id",
            "active_skill_id",
            "active_skill_status",
            "active_skill_result_summary",
            "recent_relevant_messages",
        ]
        let parsed = parseKnownBlocks(clean, keys: keys)
        guard !parsed.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        var candidates: [(String, Int, [String: Int], [LabeledBlock])] = []

        var trimmed = parsed
        var trimmedFields: [String: Int] = [:]
        let trimmedItems =
            trimBlockLines(&trimmed, key: "constraints", maxLines: 3, counterKey: "constraints_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "approved_decisions", maxLines: 2, counterKey: "approved_decisions_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "longterm_outline", maxLines: 6, counterKey: "longterm_outline_lines", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "latest_review_note", maxLines: 4, counterKey: "latest_review_note_lines", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "latest_guidance_injection", maxLines: 4, counterKey: "latest_guidance_injection_lines", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "pending_ack_guidance", maxLines: 4, counterKey: "pending_ack_guidance_lines", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "active_plan_steps", maxLines: 3, counterKey: "active_plan_steps_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "next_pending_steps", maxLines: 2, counterKey: "next_pending_steps_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "attention_steps", maxLines: 2, counterKey: "attention_steps_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "recent_relevant_messages", maxLines: 2, counterKey: "recent_relevant_messages_items", counts: &trimmedFields)
        candidates.append(("trim_low_priority_blocks", trimmedItems, trimmedFields, trimmed))

        var reduced = trimmed
        var reducedFields = trimmedFields
        dropBlock(&reduced, key: "background_hints", counterKey: "background_hints", counts: &reducedFields)
        dropBlock(&reduced, key: "active_skill_request_id", counterKey: "active_skill_request_id", counts: &reducedFields)
        dropBlock(&reduced, key: "active_skill_id", counterKey: "active_skill_id", counts: &reducedFields)
        dropBlock(&reduced, key: "active_skill_status", counterKey: "active_skill_status", counts: &reducedFields)
        dropBlock(&reduced, key: "active_skill_result_summary", counterKey: "active_skill_result_summary", counts: &reducedFields)
        dropBlock(&reduced, key: "recent_relevant_messages", counterKey: "recent_relevant_messages", counts: &reducedFields)
        candidates.append(("trim_and_drop_low_priority_fields", trimmedItems, reducedFields, reduced))

        var coreish = reduced
        var coreishFields = reducedFields
        dropBlock(&coreish, key: "latest_guidance_injection", counterKey: "latest_guidance_injection", counts: &coreishFields)
        dropBlock(&coreish, key: "pending_ack_guidance", counterKey: "pending_ack_guidance", counts: &coreishFields)
        dropBlock(&coreish, key: "governance", counterKey: "governance", counts: &coreishFields)
        dropBlock(&coreish, key: "active_plan_steps", counterKey: "active_plan_steps", counts: &coreishFields)
        dropBlock(&coreish, key: "attention_steps", counterKey: "attention_steps", counts: &coreishFields)
        trimBlockLines(&coreish, key: "next_pending_steps", maxLines: 1, counterKey: "next_pending_steps_items", counts: &coreishFields)
        candidates.append(("drop_low_priority_fields", trimmedItems, coreishFields, coreish))

        var core = coreish
        var coreFields = coreishFields
        dropBlock(&core, key: "longterm_outline", counterKey: "longterm_outline", counts: &coreFields)
        dropBlock(&core, key: "latest_review_note", counterKey: "latest_review_note", counts: &coreFields)
        candidates.append(("drop_low_priority_fields", trimmedItems, coreFields, core))

        var coreOnly = parsed
        var coreOnlyFields: [String: Int] = [:]
        keepOnlyBlocks(
            &coreOnly,
            keys: [
                "focus_source",
                "project",
                "memory_source",
                "runtime_state",
                "goal",
                "done_definition",
                "constraints",
                "approved_decisions",
                "missing_anchor_fields",
                "current_state",
                "next_step",
                "blocker",
                "active_job_id",
                "active_job_goal",
                "active_job_status",
                "active_plan_id",
                "active_plan_status",
                "next_pending_steps",
            ],
            counts: &coreOnlyFields
        )
        trimBlockLines(&coreOnly, key: "constraints", maxLines: 2, counterKey: "constraints_items", counts: &coreOnlyFields)
        trimBlockLines(&coreOnly, key: "approved_decisions", maxLines: 1, counterKey: "approved_decisions_items", counts: &coreOnlyFields)
        trimBlockLines(&coreOnly, key: "next_pending_steps", maxLines: 1, counterKey: "next_pending_steps_items", counts: &coreOnlyFields)
        candidates.append(("keep_core_anchor_only", 0, coreOnlyFields, coreOnly))

        var minimalCore = parsed
        var minimalCoreFields: [String: Int] = [:]
        keepOnlyBlocks(
            &minimalCore,
            keys: [
                "project",
                "goal",
                "done_definition",
                "constraints",
                "approved_decisions",
                "current_state",
                "next_step",
                "blocker",
            ],
            counts: &minimalCoreFields
        )
        trimBlockLines(&minimalCore, key: "constraints", maxLines: 1, counterKey: "constraints_items", counts: &minimalCoreFields)
        trimBlockLines(&minimalCore, key: "approved_decisions", maxLines: 1, counterKey: "approved_decisions_items", counts: &minimalCoreFields)
        candidates.append(("keep_minimal_anchor_only", 0, minimalCoreFields, minimalCore))

        return firstFittingServingObjectCandidate(
            candidates,
            budgetTokens: budgetTokens
        ) ?? clippedServingObjectFallback(
            renderBlocks(minimalCore),
            budgetTokens: budgetTokens,
            reason: "clip_minimal_anchor_only",
            droppedItems: 0,
            droppedFields: minimalCoreFields
        )
    }

    private static func compressLongtermOutlineObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }

        let keys = [
            "project",
            "goal",
            "done_definition",
            "stable_constraints",
            "strategic_milestones",
            "durable_decisions",
            "background_memory",
            "source_tags",
        ]
        let parsed = parseKnownBlocks(clean, keys: keys)
        guard !parsed.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        var candidates: [(String, Int, [String: Int], [LabeledBlock])] = []

        var trimmed = parsed
        var trimmedFields: [String: Int] = [:]
        let trimmedItems =
            trimBlockLines(&trimmed, key: "stable_constraints", maxLines: 2, counterKey: "stable_constraints_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "strategic_milestones", maxLines: 2, counterKey: "strategic_milestones_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "durable_decisions", maxLines: 2, counterKey: "durable_decisions_items", counts: &trimmedFields)
        candidates.append(("drop_tail_items", trimmedItems, trimmedFields, trimmed))

        var compact = trimmed
        var compactFields = trimmedFields
        trimBlockLines(&compact, key: "stable_constraints", maxLines: 1, counterKey: "stable_constraints_items", counts: &compactFields)
        trimBlockLines(&compact, key: "strategic_milestones", maxLines: 1, counterKey: "strategic_milestones_items", counts: &compactFields)
        trimBlockLines(&compact, key: "durable_decisions", maxLines: 1, counterKey: "durable_decisions_items", counts: &compactFields)
        dropBlock(&compact, key: "source_tags", counterKey: "source_tags", counts: &compactFields)
        candidates.append(("drop_tail_items_and_fields", trimmedItems, compactFields, compact))

        var noBackground = compact
        var noBackgroundFields = compactFields
        dropBlock(&noBackground, key: "background_memory", counterKey: "background_memory", counts: &noBackgroundFields)
        candidates.append(("drop_low_priority_fields", trimmedItems, noBackgroundFields, noBackground))

        var coreOnly = parsed
        var coreOnlyFields: [String: Int] = [:]
        keepOnlyBlocks(
            &coreOnly,
            keys: [
                "project",
                "goal",
                "done_definition",
                "stable_constraints",
                "strategic_milestones",
            ],
            counts: &coreOnlyFields
        )
        trimBlockLines(&coreOnly, key: "stable_constraints", maxLines: 1, counterKey: "stable_constraints_items", counts: &coreOnlyFields)
        trimBlockLines(&coreOnly, key: "strategic_milestones", maxLines: 1, counterKey: "strategic_milestones_items", counts: &coreOnlyFields)
        candidates.append(("keep_core_longterm_only", 0, coreOnlyFields, coreOnly))

        var minimal = parsed
        var minimalFields: [String: Int] = [:]
        keepOnlyBlocks(
            &minimal,
            keys: ["project", "goal", "done_definition"],
            counts: &minimalFields
        )
        candidates.append(("keep_minimal_longterm_only", 0, minimalFields, minimal))

        return firstFittingServingObjectCandidate(
            candidates,
            budgetTokens: budgetTokens
        ) ?? clippedServingObjectFallback(
            renderBlocks(minimal),
            budgetTokens: budgetTokens,
            reason: "clip_minimal_longterm_only",
            droppedItems: 0,
            droppedFields: minimalFields
        )
    }

    private static func compressDeltaFeedObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }

        let keys = [
            "cursor_from",
            "cursor_to",
            "focus_project",
            "focus_project_id",
            "project_state_hash_before",
            "project_state_hash_after",
            "portfolio_state_hash_before",
            "portfolio_state_hash_after",
            "material_change_flags",
            "user_intent_hint",
            "delta_items",
            "focused_project_delta",
            "workflow_delta",
            "recent_project_actions",
            "recent_events",
            "recent_actions",
        ]
        let parsed = parseKnownBlocks(clean, keys: keys)
        guard !parsed.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        var candidates: [(String, Int, [String: Int], [LabeledBlock])] = []

        var trimmed = parsed
        var trimmedFields: [String: Int] = [:]
        let trimmedItems =
            trimBlockLines(&trimmed, key: "delta_items", maxLines: 4, counterKey: "delta_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "recent_project_actions", maxLines: 2, counterKey: "recent_project_actions", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "recent_events", maxLines: 2, counterKey: "recent_events", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "recent_actions", maxLines: 2, counterKey: "recent_actions", counts: &trimmedFields)
        candidates.append(("drop_tail_items", trimmedItems, trimmedFields, trimmed))

        var reduced = trimmed
        var reducedFields = trimmedFields
        dropBlock(&reduced, key: "recent_events", counterKey: "recent_events", counts: &reducedFields)
        dropBlock(&reduced, key: "recent_actions", counterKey: "recent_actions", counts: &reducedFields)
        candidates.append(("drop_tail_items_and_fields", trimmedItems, reducedFields, reduced))

        var coreish = reduced
        var coreishFields = reducedFields
        dropBlock(&coreish, key: "recent_project_actions", counterKey: "recent_project_actions", counts: &coreishFields)
        dropBlock(&coreish, key: "focused_project_delta", counterKey: "focused_project_delta", counts: &coreishFields)
        dropBlock(&coreish, key: "workflow_delta", counterKey: "workflow_delta", counts: &coreishFields)
        trimBlockLines(&coreish, key: "delta_items", maxLines: 3, counterKey: "delta_items", counts: &coreishFields)
        candidates.append(("drop_low_priority_fields", trimmedItems, coreishFields, coreish))

        var core = parsed
        var coreFields: [String: Int] = [:]
        keepOnlyBlocks(
            &core,
            keys: [
                "cursor_from",
                "cursor_to",
                "focus_project",
                "focus_project_id",
                "project_state_hash_before",
                "project_state_hash_after",
                "portfolio_state_hash_before",
                "portfolio_state_hash_after",
                "material_change_flags",
                "user_intent_hint",
                "delta_items",
            ],
            counts: &coreFields
        )
        trimBlockLines(&core, key: "delta_items", maxLines: 2, counterKey: "delta_items", counts: &coreFields)
        candidates.append(("keep_core_delta_only", 0, coreFields, core))

        var minimal = parsed
        var minimalFields: [String: Int] = [:]
        keepOnlyBlocks(
            &minimal,
            keys: [
                "cursor_from",
                "cursor_to",
                "focus_project_id",
                "project_state_hash_before",
                "project_state_hash_after",
                "portfolio_state_hash_before",
                "portfolio_state_hash_after",
                "material_change_flags",
                "delta_items",
            ],
            counts: &minimalFields
        )
        trimBlockLines(&minimal, key: "delta_items", maxLines: 1, counterKey: "delta_items", counts: &minimalFields)
        candidates.append(("keep_minimal_delta_only", 0, minimalFields, minimal))

        return firstFittingServingObjectCandidate(
            candidates,
            budgetTokens: budgetTokens
        ) ?? clippedServingObjectFallback(
            renderBlocks(minimal),
            budgetTokens: budgetTokens,
            reason: "clip_minimal_delta_only",
            droppedItems: 0,
            droppedFields: minimalFields
        )
    }

    private static func firstFittingServingObjectCandidate(
        _ candidates: [(String, Int, [String: Int], [LabeledBlock])],
        budgetTokens: Int
    ) -> ServingObjectCompressionResult? {
        for candidate in candidates {
            let text = compressionCandidate(
                reason: candidate.0,
                droppedItems: candidate.1,
                droppedFields: candidate.2,
                payload: renderBlocks(candidate.3)
            )
            if estimateTokens(text) <= budgetTokens {
                return ServingObjectCompressionResult(text: text, truncated: true)
            }
        }
        return nil
    }

    private static func clippedServingObjectFallback(
        _ payload: String,
        budgetTokens: Int,
        reason: String,
        droppedItems: Int,
        droppedFields: [String: Int]
    ) -> ServingObjectCompressionResult {
        let header = compressionHeader(
            reason: reason,
            droppedItems: droppedItems,
            droppedFields: droppedFields
        )
        let available = max(8, budgetTokens - estimateTokens(header) - 1)
        let clipped = clip(payload, budgetTokens: available, preferTail: false)
        let text = compressionCandidate(
            reason: reason,
            droppedItems: droppedItems,
            droppedFields: droppedFields,
            payload: clipped.text
        )
        return ServingObjectCompressionResult(text: text, truncated: true)
    }

    private static func parseKnownBlocks(
        _ text: String,
        keys: [String]
    ) -> [LabeledBlock] {
        let allowed = Set(keys)
        let lines = normalized(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var blocks: [LabeledBlock] = []
        var current: LabeledBlock?

        func flush() {
            if let current {
                blocks.append(current)
            }
        }

        for line in lines {
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
                if allowed.contains(key) {
                    flush()
                    let remainder = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    current = LabeledBlock(
                        key: key,
                        valueLines: remainder.isEmpty ? [] : [remainder],
                        inline: !remainder.isEmpty
                    )
                    continue
                }
            }
            if current == nil {
                continue
            }
            current?.inline = false
            current?.valueLines.append(line)
        }

        flush()
        return blocks
    }

    private static func renderBlocks(_ blocks: [LabeledBlock]) -> String {
        normalized(
            blocks.map { $0.render() }.joined(separator: "\n")
        )
    }

    private static func parsedInlineValue(
        _ blocks: [LabeledBlock],
        key: String
    ) -> String? {
        guard let block = blocks.first(where: { $0.key == key }) else { return nil }
        guard block.inline else { return nil }
        let value = block.valueLines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func parsedInlineIntValue(
        _ blocks: [LabeledBlock],
        key: String
    ) -> Int? {
        guard let raw = parsedInlineValue(blocks, key: key) else { return nil }
        return Int(raw)
    }

    private static func setInlineBlockValue(
        _ blocks: inout [LabeledBlock],
        key: String,
        value: String
    ) {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else { return }
        if let index = blocks.firstIndex(where: { $0.key == key }) {
            blocks[index].inline = true
            blocks[index].valueLines = [normalizedValue]
            return
        }
        blocks.append(
            LabeledBlock(
                key: key,
                valueLines: [normalizedValue],
                inline: true
            )
        )
    }

    private static func blockLineCount(
        _ blocks: [LabeledBlock],
        key: String
    ) -> Int {
        guard let block = blocks.first(where: { $0.key == key }) else { return 0 }
        return block.inline ? min(block.valueLines.count, 1) : block.valueLines.count
    }

    private static func updateDialogueWindowSummary(
        _ blocks: inout [LabeledBlock],
        floorPairs: Int,
        markTruncated: Bool
    ) {
        let rawMessageCount = blockLineCount(blocks, key: "raw_messages")
        let selectedPairs = Int(ceil(Double(max(0, rawMessageCount)) / 2.0))
        setInlineBlockValue(
            &blocks,
            key: "raw_window_selected_pairs",
            value: String(selectedPairs)
        )
        setInlineBlockValue(
            &blocks,
            key: "eligible_messages",
            value: String(rawMessageCount)
        )
        setInlineBlockValue(
            &blocks,
            key: "continuity_floor_satisfied",
            value: rawMessageCount >= floorPairs * 2 ? "true" : "false"
        )
        if markTruncated {
            setInlineBlockValue(
                &blocks,
                key: "truncation_after_floor",
                value: "true"
            )
        }
    }

    private static func totalDroppedCount(_ counts: [String: Int]) -> Int {
        counts.values.reduce(0, +)
    }

    @discardableResult
    private static func trimBlockLines(
        _ blocks: inout [LabeledBlock],
        key: String,
        maxLines: Int,
        counterKey: String,
        counts: inout [String: Int]
    ) -> Int {
        guard let index = blocks.firstIndex(where: { $0.key == key }) else { return 0 }
        guard !blocks[index].inline else { return 0 }
        let lines = blocks[index].valueLines
        guard lines.count > maxLines else { return 0 }
        let dropped = max(0, lines.count - maxLines)
        blocks[index].valueLines = Array(lines.prefix(maxLines))
        counts[counterKey, default: 0] += dropped
        return dropped
    }

    @discardableResult
    private static func trimBlockLinesFromTail(
        _ blocks: inout [LabeledBlock],
        key: String,
        maxLines: Int,
        counterKey: String,
        counts: inout [String: Int]
    ) -> Int {
        guard let index = blocks.firstIndex(where: { $0.key == key }) else { return 0 }
        guard !blocks[index].inline else { return 0 }
        let lines = blocks[index].valueLines
        guard lines.count > maxLines else { return 0 }
        let dropped = max(0, lines.count - maxLines)
        blocks[index].valueLines = Array(lines.suffix(maxLines))
        counts[counterKey, default: 0] += dropped
        return dropped
    }

    @discardableResult
    private static func trimBlockLines(
        _ blocks: inout [LabeledBlock],
        key: String,
        maxLines: Int,
        counterKey: String
    ) -> Int {
        var counts: [String: Int] = [:]
        return trimBlockLines(&blocks, key: key, maxLines: maxLines, counterKey: counterKey, counts: &counts)
    }

    private static func dropBlock(
        _ blocks: inout [LabeledBlock],
        key: String,
        counterKey: String,
        counts: inout [String: Int]
    ) {
        guard let index = blocks.firstIndex(where: { $0.key == key }) else { return }
        blocks.remove(at: index)
        counts[counterKey, default: 0] += 1
    }

    private static func keepOnlyBlocks(
        _ blocks: inout [LabeledBlock],
        keys: [String],
        counts: inout [String: Int]
    ) {
        let allowed = Set(keys)
        let removed = blocks.filter { !allowed.contains($0.key) }
        for block in removed {
            counts[block.key, default: 0] += 1
        }
        blocks = blocks.filter { allowed.contains($0.key) }
    }

    private static func compressConflictSetObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }

        let blocks = splitConflictBlocks(clean)
        guard !blocks.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        for keepCount in stride(from: blocks.count - 1, through: 1, by: -1) {
            let kept = Array(blocks.prefix(keepCount)).joined(separator: "\n")
            let candidate = compressionCandidate(
                reason: "drop_tail_conflicts",
                droppedItems: blocks.count - keepCount,
                droppedFields: [:],
                payload: kept
            )
            if estimateTokens(candidate) <= budgetTokens {
                return ServingObjectCompressionResult(text: candidate, truncated: true)
            }
        }

        let header = compressionHeader(
            reason: "drop_tail_conflicts_and_clip_conflict",
            droppedItems: max(0, blocks.count - 1),
            droppedFields: [:]
        )
        let available = max(8, budgetTokens - estimateTokens(header) - 1)
        let clipped = clip(blocks[0], budgetTokens: available, preferTail: false)
        let candidate = compressionCandidate(
            reason: "drop_tail_conflicts_and_clip_conflict",
            droppedItems: max(0, blocks.count - 1),
            droppedFields: [:],
            payload: clipped.text
        )
        return ServingObjectCompressionResult(
            text: candidate,
            truncated: true || clipped.truncated
        )
    }

    private static func compressContextRefsObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }

        let items = parseContextRefLines(clean)
        guard !items.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        let noFreshnessFields = ["freshness_hint": items.count]
        let noFreshness = items.map {
            $0.render(includeTokenCostHint: true, includeFreshnessHint: false)
        }.joined(separator: "\n")
        let noFreshnessCandidate = compressionCandidate(
            reason: "drop_low_priority_fields",
            droppedItems: 0,
            droppedFields: noFreshnessFields,
            payload: noFreshness
        )
        if estimateTokens(noFreshnessCandidate) <= budgetTokens {
            return ServingObjectCompressionResult(text: noFreshnessCandidate, truncated: true)
        }

        let compactFields = [
            "freshness_hint": items.count,
            "token_cost_hint": items.count,
        ]
        let compactLines = items.map {
            $0.render(includeTokenCostHint: false, includeFreshnessHint: false)
        }
        let compactPayload = compactLines.joined(separator: "\n")
        let compactCandidate = compressionCandidate(
            reason: "drop_low_priority_fields",
            droppedItems: 0,
            droppedFields: compactFields,
            payload: compactPayload
        )
        if estimateTokens(compactCandidate) <= budgetTokens {
            return ServingObjectCompressionResult(text: compactCandidate, truncated: true)
        }

        for keepCount in stride(from: compactLines.count, through: 1, by: -1) {
            let candidate = compressionCandidate(
                reason: "drop_low_priority_fields_and_tail_refs",
                droppedItems: compactLines.count - keepCount,
                droppedFields: [
                    "freshness_hint": keepCount,
                    "token_cost_hint": keepCount,
                ],
                payload: Array(compactLines.prefix(keepCount)).joined(separator: "\n")
            )
            if estimateTokens(candidate) <= budgetTokens {
                return ServingObjectCompressionResult(text: candidate, truncated: true)
            }
        }

        let header = compressionHeader(
            reason: "drop_low_priority_fields_and_clip_ref",
            droppedItems: max(0, compactLines.count - 1),
            droppedFields: compactFields
        )
        let available = max(8, budgetTokens - estimateTokens(header) - 1)
        let clipped = clip(compactLines[0], budgetTokens: available, preferTail: false)
        let candidate = compressionCandidate(
            reason: "drop_low_priority_fields_and_clip_ref",
            droppedItems: max(0, compactLines.count - 1),
            droppedFields: compactFields,
            payload: clipped.text
        )
        return ServingObjectCompressionResult(
            text: candidate,
            truncated: true || clipped.truncated
        )
    }

    private static func compressEvidencePackObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }

        guard let pack = parseEvidencePackBody(clean), !pack.items.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        let dropFreshnessFields = ["freshness": pack.items.count]
        let noFreshnessBody = renderEvidencePackBody(
            pack,
            items: pack.items,
            includeFreshness: false,
            includeExcerpt: true
        )
        let noFreshnessCandidate = compressionCandidate(
            reason: "drop_low_priority_fields",
            droppedItems: 0,
            droppedFields: dropFreshnessFields,
            payload: noFreshnessBody
        )
        if estimateTokens(noFreshnessCandidate) <= budgetTokens {
            return ServingObjectCompressionResult(text: noFreshnessCandidate, truncated: true)
        }

        let compactFields = [
            "freshness": pack.items.count,
            "excerpt": pack.items.count,
        ]
        let compactBody = renderEvidencePackBody(
            pack,
            items: pack.items,
            includeFreshness: false,
            includeExcerpt: false
        )
        let compactCandidate = compressionCandidate(
            reason: "drop_low_priority_fields",
            droppedItems: 0,
            droppedFields: compactFields,
            payload: compactBody
        )
        if estimateTokens(compactCandidate) <= budgetTokens {
            return ServingObjectCompressionResult(text: compactCandidate, truncated: true)
        }

        for keepCount in stride(from: pack.items.count, through: 1, by: -1) {
            let keptItems = Array(pack.items.prefix(keepCount))
            let candidate = compressionCandidate(
                reason: "drop_low_priority_fields_and_tail_evidence",
                droppedItems: pack.items.count - keepCount,
                droppedFields: [
                    "freshness": keepCount,
                    "excerpt": keepCount,
                ],
                payload: renderEvidencePackBody(
                    pack,
                    items: keptItems,
                    includeFreshness: false,
                    includeExcerpt: false
                )
            )
            if estimateTokens(candidate) <= budgetTokens {
                return ServingObjectCompressionResult(text: candidate, truncated: true)
            }
        }

        let compactFirst = pack.items[0].render(includeFreshness: false, includeExcerpt: false)
        let header = compressionHeader(
            reason: "drop_low_priority_fields_and_clip_evidence_item",
            droppedItems: max(0, pack.items.count - 1),
            droppedFields: compactFields
        )
        let skeleton = renderEvidencePackBody(
            pack,
            items: [],
            includeFreshness: false,
            includeExcerpt: false
        )
        let staticBudget = estimateTokens(header) + estimateTokens(skeleton.replacingOccurrences(of: "selected_items:", with: ""))
        let available = max(8, budgetTokens - staticBudget)
        let clipped = clip(compactFirst, budgetTokens: available, preferTail: false)
        let candidate = compressionCandidate(
            reason: "drop_low_priority_fields_and_clip_evidence_item",
            droppedItems: max(0, pack.items.count - 1),
            droppedFields: compactFields,
            payload: renderEvidencePackBody(
                pack,
                items: [
                    EvidencePackItem(
                        refId: "",
                        title: "",
                        sourceScope: "",
                        freshness: "",
                        whyIncluded: "",
                        excerpt: clipped.text
                    )
                ],
                includeFreshness: false,
                includeExcerpt: false,
                overrideFirstRenderedLine: clipped.text
            )
        )
        return ServingObjectCompressionResult(
            text: candidate,
            truncated: true || clipped.truncated
        )
    }

    private static func compressionHeader(
        reason: String,
        droppedItems: Int,
        droppedFields: [String: Int]
    ) -> String {
        """
compression_reason: \(reason)
dropped_items: \(max(0, droppedItems))
dropped_fields: \(droppedFieldsSummary(droppedFields))
"""
    }

    private static func compressionCandidate(
        reason: String,
        droppedItems: Int,
        droppedFields: [String: Int],
        payload: String
    ) -> String {
        let header = compressionHeader(
            reason: reason,
            droppedItems: droppedItems,
            droppedFields: droppedFields
        )
        let normalizedPayload = normalized(payload)
        guard !normalizedPayload.isEmpty else { return header }
        return "\(header)\n\(normalizedPayload)"
    }

    private static func droppedFieldsSummary(_ droppedFields: [String: Int]) -> String {
        let nonZero = droppedFields
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in lhs.key < rhs.key }
        guard !nonZero.isEmpty else { return "0" }
        return nonZero
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }

    private static func splitConflictBlocks(_ text: String) -> [String] {
        let lines = normalized(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var blocks: [String] = []
        var current: [String] = []

        for line in lines {
            if line.hasPrefix("- conflict_id:"), !current.isEmpty {
                blocks.append(normalized(current.joined(separator: "\n")))
                current = [line]
            } else {
                current.append(line)
            }
        }

        if !current.isEmpty {
            blocks.append(normalized(current.joined(separator: "\n")))
        }
        return blocks.filter { !$0.isEmpty }
    }

    private static func parseContextRefLines(_ text: String) -> [ContextRefLine] {
        normalized(text)
            .split(separator: "\n")
            .compactMap { parseContextRefLine(String($0)) }
    }

    private static func parseContextRefLine(_ line: String) -> ContextRefLine? {
        guard line.hasPrefix("- ref_id=") else { return nil }
        guard
            let refId = inlineField(line, after: "ref_id=", before: " ref_kind="),
            let refKind = inlineField(line, after: "ref_kind=", before: " title="),
            let title = inlineField(line, after: "title=", before: " source_scope="),
            let sourceScope = inlineField(line, after: "source_scope=", before: " token_cost_hint="),
            let tokenCostHint = inlineField(line, after: "token_cost_hint=", before: " freshness_hint="),
            let freshnessHint = inlineField(line, after: "freshness_hint=", before: nil)
        else {
            return nil
        }
        return ContextRefLine(
            refId: refId,
            refKind: refKind,
            title: title,
            sourceScope: sourceScope,
            tokenCostHint: tokenCostHint,
            freshnessHint: freshnessHint
        )
    }

    private static func parseEvidencePackBody(_ text: String) -> EvidencePackBody? {
        let lines = normalized(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var evidenceGoal = ""
        var items: [EvidencePackItem] = []
        var truncatedItems = 0
        var redactedItems = 0
        var auditRef = ""

        for line in lines {
            if line.hasPrefix("evidence_goal: ") {
                evidenceGoal = String(line.dropFirst("evidence_goal: ".count))
            } else if line.hasPrefix("- ref_id=") {
                if let item = parseEvidencePackItem(line) {
                    items.append(item)
                }
            } else if line.hasPrefix("truncated_items: ") {
                truncatedItems = Int(line.dropFirst("truncated_items: ".count)) ?? 0
            } else if line.hasPrefix("redacted_items: ") {
                redactedItems = Int(line.dropFirst("redacted_items: ".count)) ?? 0
            } else if line.hasPrefix("audit_ref: ") {
                auditRef = String(line.dropFirst("audit_ref: ".count))
            }
        }

        guard !evidenceGoal.isEmpty || !items.isEmpty || !auditRef.isEmpty else { return nil }
        return EvidencePackBody(
            evidenceGoal: evidenceGoal,
            items: items,
            truncatedItems: truncatedItems,
            redactedItems: redactedItems,
            auditRef: auditRef
        )
    }

    private static func parseEvidencePackItem(_ line: String) -> EvidencePackItem? {
        guard line.hasPrefix("- ref_id=") else { return nil }
        guard
            let refId = inlineField(line, after: "ref_id=", before: " title="),
            let title = inlineField(line, after: "title=", before: " source_scope="),
            let sourceScope = inlineField(line, after: "source_scope=", before: " freshness="),
            let freshness = inlineField(line, after: "freshness=", before: " why_included="),
            let whyIncluded = inlineField(line, after: "why_included=", before: " excerpt="),
            let excerpt = inlineField(line, after: "excerpt=", before: nil)
        else {
            return nil
        }
        return EvidencePackItem(
            refId: refId,
            title: title,
            sourceScope: sourceScope,
            freshness: freshness,
            whyIncluded: whyIncluded,
            excerpt: excerpt
        )
    }

    private static func renderEvidencePackBody(
        _ body: EvidencePackBody,
        items: [EvidencePackItem],
        includeFreshness: Bool,
        includeExcerpt: Bool,
        overrideFirstRenderedLine: String? = nil
    ) -> String {
        var lines: [String] = [
            "evidence_goal: \(body.evidenceGoal)",
            "selected_items:",
        ]

        if let overrideFirstRenderedLine {
            lines.append(overrideFirstRenderedLine)
            if items.count > 1 {
                lines.append(
                    contentsOf: items.dropFirst().map {
                        $0.render(includeFreshness: includeFreshness, includeExcerpt: includeExcerpt)
                    }
                )
            }
        } else {
            lines.append(
                contentsOf: items.map {
                    $0.render(includeFreshness: includeFreshness, includeExcerpt: includeExcerpt)
                }
            )
        }

        lines.append("truncated_items: \(body.truncatedItems)")
        lines.append("redacted_items: \(body.redactedItems)")
        lines.append("audit_ref: \(body.auditRef)")
        return normalized(lines.joined(separator: "\n"))
    }

    private static func inlineField(
        _ line: String,
        after startMarker: String,
        before endMarker: String?
    ) -> String? {
        guard let startRange = line.range(of: startMarker) else { return nil }
        let suffix = String(line[startRange.upperBound...])
        if let endMarker {
            guard let endRange = suffix.range(of: endMarker) else { return nil }
            return normalized(String(suffix[..<endRange.lowerBound]))
        }
        return normalized(suffix)
    }

    private static func clip(_ text: String, budgetTokens: Int, preferTail: Bool) -> ClipResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ClipResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ClipResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ClipResult(text: clean, truncated: false)
        }

        var lo = 0
        var hi = clean.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let cand = truncatedCandidate(clean, chars: mid, preferTail: preferTail)
            if estimateTokens(cand) <= budgetTokens {
                lo = mid
            } else {
                hi = mid - 1
            }
        }

        let out = truncatedCandidate(clean, chars: lo, preferTail: preferTail)
        return ClipResult(text: normalized(out), truncated: true)
    }

    private static func truncatedCandidate(_ text: String, chars: Int, preferTail: Bool) -> String {
        guard !text.isEmpty else { return "" }
        let n = max(0, min(chars, text.count))
        if n == 0 { return "…" }
        let chunk = preferTail ? suffix(text, n) : prefix(text, n)
        if n >= text.count { return chunk }
        return preferTail ? "…" + chunk : chunk + "…"
    }

    private static func prefix(_ text: String, _ chars: Int) -> String {
        guard chars > 0 else { return "" }
        if chars >= text.count { return text }
        let idx = text.index(text.startIndex, offsetBy: chars)
        return String(text[..<idx])
    }

    private static func suffix(_ text: String, _ chars: Int) -> String {
        guard chars > 0 else { return "" }
        if chars >= text.count { return text }
        let idx = text.index(text.endIndex, offsetBy: -chars)
        return String(text[idx...])
    }

    private static func estimateTokens(_ text: String) -> Int {
        if text.isEmpty { return 0 }
        var ascii = 0
        var nonAscii = 0
        for u in text.unicodeScalars {
            if u.isASCII {
                ascii += 1
            } else {
                nonAscii += 1
            }
        }
        let asciiTokens = Int(ceil(Double(ascii) / 4.0))
        let nonAsciiTokens = Int(ceil(Double(nonAscii) / 1.5))
        return max(0, asciiTokens + nonAsciiTokens)
    }

    private static func sanitized(_ raw: String?, counters: inout RedactionCounters) -> String {
        var text = normalized(raw)
        if text.isEmpty { return "" }

        let privateSanitized = stripPrivateTagsFailClosed(text, placeholder: "[private omitted]")
        text = privateSanitized.text
        if privateSanitized.redactedCount > 0 {
            counters.redactedItems += privateSanitized.redactedCount
            counters.privateDrops += privateSanitized.redactedCount
        }
        text = replacingRegex(
            text,
            pattern: "(?is)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----",
            with: "[redacted_private_key]",
            counters: &counters
        )
        text = replacingRegex(
            text,
            pattern: "sk-[A-Za-z0-9]{20,}",
            with: "[redacted_api_key]",
            counters: &counters
        )
        text = replacingRegex(
            text,
            pattern: "sk-ant-[A-Za-z0-9_-]{20,}",
            with: "[redacted_api_key]",
            counters: &counters
        )
        text = replacingRegex(
            text,
            pattern: "gh[pousr]_[A-Za-z0-9]{20,}",
            with: "[redacted_token]",
            counters: &counters
        )
        text = replacingRegex(
            text,
            pattern: "eyJ[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}",
            with: "[redacted_jwt]",
            counters: &counters
        )
        text = replacingRegex(
            text,
            pattern: "(?i)bearer\\s+[A-Za-z0-9._-]{16,}",
            with: "Bearer [redacted_token]",
            counters: &counters
        )
        text = replacingRegex(
            text,
            pattern: "(?i)(password|passwd|pwd|api[_-]?key|secret)\\s*[:=]\\s*[^\\s,;]{4,}",
            with: "$1=[redacted]",
            counters: &counters
        )

        return normalized(text)
    }

    private enum PrivateTagKind {
        case open
        case close
    }

    private struct PrivateTagToken {
        var kind: PrivateTagKind
        var end: Int
        var malformed: Bool
    }

    // State-machine parser for <private>...</private>, fail-closed on malformed tags.
    private static func stripPrivateTagsFailClosed(_ input: String, placeholder: String) -> PrivateTagSanitizeResult {
        let bytes = Array(input.utf8)
        guard !bytes.isEmpty else {
            return PrivateTagSanitizeResult(text: "", hadPrivate: false, malformed: false, redactedCount: 0)
        }
        let placeholderBytes = Array(placeholder.utf8)

        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)

        var i = 0
        var chunkStart = 0
        var depth = 0
        var hadPrivate = false
        var malformed = false
        var redactedCount = 0

        while i < bytes.count {
            if bytes[i] != 0x3c { // <
                i += 1
                continue
            }

            guard let token = parsePrivateTagToken(bytes, from: i) else {
                i += 1
                continue
            }

            hadPrivate = true
            if token.malformed { malformed = true }

            if depth == 0, i > chunkStart {
                output.append(contentsOf: bytes[chunkStart..<i])
            }

            switch token.kind {
            case .open:
                if depth > 0 { malformed = true }
                depth += 1
                if depth == 1 { redactedCount += 1 }
            case .close:
                if depth == 0 {
                    malformed = true
                    redactedCount += 1
                    output.append(contentsOf: placeholderBytes)
                } else {
                    depth -= 1
                    if depth == 0 {
                        output.append(contentsOf: placeholderBytes)
                    }
                }
            }

            i = token.end
            chunkStart = i
        }

        if depth == 0 {
            if chunkStart < bytes.count {
                output.append(contentsOf: bytes[chunkStart..<bytes.count])
            }
        } else {
            malformed = true
            output.append(contentsOf: placeholderBytes)
        }

        return PrivateTagSanitizeResult(
            text: String(decoding: output, as: UTF8.self),
            hadPrivate: hadPrivate,
            malformed: malformed,
            redactedCount: redactedCount
        )
    }

    private static func parsePrivateTagToken(_ bytes: [UInt8], from start: Int) -> PrivateTagToken? {
        guard start < bytes.count, bytes[start] == 0x3c else { // <
            return nil
        }

        let n = bytes.count
        var i = start + 1
        while i < n, isASCIIWhitespace(bytes[i]) { i += 1 }
        if i >= n { return nil }

        var kind: PrivateTagKind = .open
        if bytes[i] == 0x2f { // /
            kind = .close
            i += 1
            while i < n, isASCIIWhitespace(bytes[i]) { i += 1 }
        }

        guard startsWithPrivateKeyword(bytes, at: i) else { return nil }
        i += 7 // "private"

        if i < n {
            let next = bytes[i]
            let isBoundary = next == 0x3e || next == 0x2f || isASCIIWhitespace(next) // > or /
            if !isBoundary, isASCIIWord(next) {
                return nil
            }
        }

        var malformed = false
        var sawGt = false
        var tailHasNonWs = false
        while i < n {
            let c = bytes[i]
            if c == 0x3e { // >
                sawGt = true
                i += 1
                break
            }
            if c == 0x3c { malformed = true } // nested '<' in tag body
            if !isASCIIWhitespace(c) { tailHasNonWs = true }
            i += 1
        }

        if !sawGt { malformed = true }
        if tailHasNonWs { malformed = true }

        return PrivateTagToken(kind: kind, end: sawGt ? i : n, malformed: malformed)
    }

    private static func startsWithPrivateKeyword(_ bytes: [UInt8], at start: Int) -> Bool {
        let keyword: [UInt8] = [0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65] // "private"
        if start < 0 || start + keyword.count > bytes.count { return false }
        for j in 0..<keyword.count {
            if lowerASCII(bytes[start + j]) != keyword[j] {
                return false
            }
        }
        return true
    }

    private static func lowerASCII(_ b: UInt8) -> UInt8 {
        if b >= 0x41 && b <= 0x5a { // A-Z
            return b + 0x20
        }
        return b
    }

    private static func isASCIIWhitespace(_ b: UInt8) -> Bool {
        return b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d || b == 0x0c || b == 0x0b
    }

    private static func isASCIIWord(_ b: UInt8) -> Bool {
        return (
            (b >= 0x30 && b <= 0x39) ||
            (b >= 0x41 && b <= 0x5a) ||
            (b >= 0x61 && b <= 0x7a) ||
            b == 0x5f ||
            b == 0x2d
        )
    }

    private static func replacingRegex(
        _ input: String,
        pattern: String,
        with replacement: String,
        counters: inout RedactionCounters,
        countPrivateDrops: Bool = false
    ) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = re.numberOfMatches(in: input, options: [], range: range)
        guard matches > 0 else { return input }
        counters.redactedItems += matches
        if countPrivateDrops {
            counters.privateDrops += matches
        }
        return re.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: replacement)
    }

    private static func projectFallback(req: IPCMemoryContextRequestPayload) -> ProjectFallback {
        let reg = HubProjectRegistryStorage.load()
        let pid = normalized(req.projectId)
        let root = normalized(req.projectRoot)
        let display = normalized(req.displayName)

        let stored = HubProjectCanonicalMemoryStorage.lookup(
            projectId: pid,
            projectRoot: root,
            displayName: display
        )
        let storedCanonical = storedCanonicalText(snapshot: stored)
        var observationLines: [String] = []
        if let stored {
            observationLines.append(
                """
hub_project_memory_updated_at: \(Int(stored.updatedAt))
hub_project_memory_items: \(stored.items.count)
"""
            )
        }

        let matched: HubProjectSnapshot? = {
            guard !reg.projects.isEmpty else { return nil }
            if !pid.isEmpty, let p = reg.projects.first(where: { $0.projectId == pid }) {
                return p
            }
            if !root.isEmpty, let p = reg.projects.first(where: { normalized($0.rootPath) == root }) {
                return p
            }
            if !display.isEmpty,
               let p = reg.projects.first(where: {
                   normalized($0.displayName).localizedCaseInsensitiveCompare(display) == .orderedSame
               }) {
                return p
            }
            return nil
        }()

        if let p = matched {
            let obs = """
hub_registry_updated_at: \(Int(reg.updatedAt))
project_updated_at: \(Int(p.updatedAt ?? 0))
last_summary_at: \(Int(p.lastSummaryAt ?? 0))
last_event_at: \(Int(p.lastEventAt ?? 0))
"""
            if !obs.isEmpty {
                observationLines.append(obs)
            }
        }

        let registryCanonical: String = {
            guard let p = matched else { return "" }
            let status = normalized(p.statusDigest)
            return """
project: \(p.displayName)
project_id: \(p.projectId)
root_path: \(p.rootPath)
status: \(status.isEmpty ? "(none)" : status)
"""
        }()

        return ProjectFallback(
            canonical: firstNonEmpty(storedCanonical, registryCanonical),
            observations: observationLines
                .map(normalized)
                .filter { !$0.isEmpty }
                .joined(separator: "\n"),
            hasStoredCanonical: !storedCanonical.isEmpty
        )
    }

    private static func storedCanonicalText(snapshot: HubProjectCanonicalMemorySnapshot?) -> String {
        guard let snapshot else { return "" }
        return snapshot.items
            .map { item in
                let key = normalized(item.key)
                let value = normalized(item.value)
                guard !key.isEmpty, !value.isEmpty else { return "" }
                return "\(key) = \(value)"
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func mergedProjectText(primary: String, secondary: String) -> String {
        let first = normalized(primary)
        let second = normalized(secondary)
        if first.isEmpty { return second }
        if second.isEmpty { return first }
        if first == second { return first }
        return """
\(first)

\(second)
"""
    }

    private static func rawEvidenceFallback(mode: String) -> String {
        let ms = ModelStateStorage.load()
        guard !ms.models.isEmpty else { return "" }

        let sorted = ms.models.sorted { a, b in
            if a.state != b.state {
                if a.state == .loaded { return true }
                if b.state == .loaded { return false }
            }
            return a.id.localizedCaseInsensitiveCompare(b.id) == .orderedAscending
        }

        let cap = mode == "supervisor" ? 16 : 8
        let lines = sorted.prefix(cap).map { m in
            let roles = (m.roles ?? []).joined(separator: ",")
            let roleText = roles.isEmpty ? "" : " roles=\(roles)"
            return "- \(m.id) [\(m.state.rawValue)] ctx=\(m.contextLength) backend=\(m.backend)\(roleText)"
        }.joined(separator: "\n")

        return """
models_state_updated_at: \(Int(ms.updatedAt))
\(lines)
"""
    }

    private static func loadConstitutionOneLiner(latestUser: String) -> String {
        if shouldUseConciseConstitutionForLowRiskRequest(latestUser) {
            return HubUIStrings.Memory.Constitution.conciseOneLiner
        }

        let fallback = defaultConstitution(latestUser: latestUser)
        let url = SharedPaths.ensureHubDirectory()
            .appendingPathComponent("memory", isDirectory: true)
            .appendingPathComponent("ax_constitution.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let one = obj["one_liner"] as? [String: Any] else {
            return fallback
        }

        let zh = normalized(one["zh"] as? String)
        if !zh.isEmpty { return normalizeConstitution(zh) }
        let en = normalized(one["en"] as? String)
        if !en.isEmpty { return normalizeConstitution(en) }
        return fallback
    }

    private static func defaultConstitution(latestUser: String) -> String {
        if shouldUseConciseConstitutionForLowRiskRequest(latestUser) {
            return HubUIStrings.Memory.Constitution.conciseOneLiner
        }
        return HubUIStrings.Memory.Constitution.defaultOneLiner
    }

    private static func normalizeConstitution(_ raw: String) -> String {
        let t = normalized(raw)
        guard !t.isEmpty else {
            return HubUIStrings.Memory.Constitution.defaultOneLiner
        }

        let legacy = HubUIStrings.Memory.Constitution.legacyOneLiner
        var out = (t == legacy)
            ? HubUIStrings.Memory.Constitution.defaultOneLiner
            : t

        let lower = out.lowercased()
        let zhRiskFocused = HubUIStrings.Memory.Constitution.zhRiskFocusedTokens.contains { token in
            out.contains(token)
        }
        let enRiskFocused =
            lower.contains("high-risk") ||
            lower.contains("compliance") ||
            lower.contains("legal") ||
            lower.contains("privacy") ||
            lower.contains("safety") ||
            lower.contains("harm") ||
            lower.contains("refuse")

        let zhHasCarveout = HubUIStrings.Memory.Constitution.zhCarveoutTokens.contains { token in
            out.contains(token)
        }
        let enHasCarveout =
            lower.contains("only for high-risk") ||
            lower.contains("normal coding") ||
            lower.contains("creative requests") ||
            lower.contains("respond directly") ||
            lower.contains("answer normal")

        if zhRiskFocused && !zhHasCarveout {
            out += HubUIStrings.Memory.Constitution.missingCarveoutSuffix
        } else if enRiskFocused && !enHasCarveout {
            out += " Explain first only for high-risk or irreversible actions; answer normal coding/creative requests directly."
        }
        return out
    }

    private static func shouldUseConciseConstitutionForLowRiskRequest(_ userText: String) -> Bool {
        let t = normalized(userText).lowercased()
        if t.isEmpty { return false }

        let codingSignals = HubUIStrings.Memory.Constitution.lowRiskCodingSignals
        let riskSignals = HubUIStrings.Memory.Constitution.lowRiskRiskSignals
        let hasCoding = codingSignals.contains(where: { t.contains($0) })
        let hasRisk = riskSignals.contains(where: { t.contains($0) })
        return hasCoding && !hasRisk
    }

    private static func nonEmptyOrNone(_ text: String) -> String {
        let t = normalized(text)
        return t.isEmpty ? "(none)" : t
    }

    private static func firstNonEmpty(_ lhs: String?, _ rhs: String) -> String {
        let left = normalized(lhs)
        if !left.isEmpty { return left }
        return normalized(rhs)
    }

    private static func normalized(_ text: String?) -> String {
        guard let text else { return "" }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clamp(_ v: Int, min minValue: Int, max maxValue: Int) -> Int {
        if v < minValue { return minValue }
        if v > maxValue { return maxValue }
        return v
    }
}
