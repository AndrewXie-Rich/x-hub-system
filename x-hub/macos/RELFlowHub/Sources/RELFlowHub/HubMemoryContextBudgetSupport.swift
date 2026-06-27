import Foundation
import RELFlowHubCore

extension HubMemoryContextBuilder {
    static func normalizedBudgets(
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

    static func normalizedServingProfile(_ raw: String?) -> String? {
        let trimmed = normalized(raw).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    static func supervisorServingGovernor(
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

    static func supervisorServingGovernorSection(
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

    static func servingProfileSection(_ servingProfile: String?) -> String {
        guard let servingProfile, !servingProfile.isEmpty else { return "" }
        return """
[SERVING_PROFILE]
profile_id: \(servingProfile)
[/SERVING_PROFILE]
"""
    }

    static func longtermDisclosure(for mode: String) -> LongtermDisclosure {
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

    static func longtermDisclosureSection(_ disclosure: LongtermDisclosure) -> String {
        """
[LONGTERM_MEMORY]
longterm_mode=\(disclosure.longtermMode)
retrieval_available=\(disclosure.retrievalAvailable ? "true" : "false")
fulltext_not_loaded=\(disclosure.fulltextNotLoaded ? "true" : "false")
[/LONGTERM_MEMORY]
"""
    }

    static func supervisorServingObjectBudgets(
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

    static func namedSection(_ tag: String, body: String) -> String {
        let normalizedBody = normalized(body)
        guard !normalizedBody.isEmpty else { return "" }
        return """
[\(tag)]
\(normalizedBody)
[/\(tag)]
"""
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
}
