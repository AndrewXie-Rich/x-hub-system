import Foundation
import RELFlowHubCore

enum HubMemoryContextBuilder {
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

}
