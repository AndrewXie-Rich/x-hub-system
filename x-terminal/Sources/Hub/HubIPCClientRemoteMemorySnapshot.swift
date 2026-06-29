import Foundation

private enum HubIPCClientRemoteMemorySnapshotStorage {
    static let cache = HubRemoteMemorySnapshotCache(ttlSeconds: 15.0)
}

extension HubIPCClient {
    static func invalidateProjectRemoteMemorySnapshotCache(
        projectId: String?,
        reason: XTMemoryRemoteSnapshotInvalidationReason
    ) async {
        await HubIPCClientRemoteMemorySnapshotStorage.cache.invalidate(
            projectId: projectId,
            hubProfileID: currentHubCacheScopeID(),
            reason: reason
        )
    }

    static func invalidateSupervisorRemoteMemorySnapshotCache(
        reason: XTMemoryRemoteSnapshotInvalidationReason
    ) async {
        await HubIPCClientRemoteMemorySnapshotStorage.cache.invalidate(
            key: HubRemoteMemorySnapshotCache.Key(
                hubProfileID: currentHubCacheScopeID(),
                mode: XTMemoryUseMode.supervisorOrchestration.rawValue,
                projectId: nil
            ),
            reason: reason
        )
    }

    static func invalidateAllRemoteMemorySnapshotCaches(
        reason: XTMemoryRemoteSnapshotInvalidationReason
    ) async {
        await HubIPCClientRemoteMemorySnapshotStorage.cache.invalidateAll(reason: reason)
    }

    static func invalidateSupervisorMemoryCache(
        reason: XTMemoryRemoteSnapshotInvalidationReason
    ) async {
        await invalidateSupervisorRemoteMemorySnapshotCache(reason: reason)
    }

    static func noteRemoteMemoryGrantStateChanged(
        projectId: String?
    ) async {
        await noteSupervisorRemoteMemoryGrantStateChanged()
        await noteProjectRemoteMemoryGrantStateChanged(projectId: projectId)
    }

    static func refreshProjectRemoteMemorySnapshotCache(projectId: String?) async {
        await invalidateProjectRemoteMemorySnapshotCache(projectId: projectId, reason: .manualRefresh)
    }

    static func refreshSupervisorRemoteMemorySnapshotCache() async {
        await invalidateSupervisorRemoteMemorySnapshotCache(reason: .manualRefresh)
    }

    static func noteProjectRemoteMemoryGrantStateChanged(projectId: String?) async {
        await invalidateProjectRemoteMemorySnapshotCache(projectId: projectId, reason: .grantStateChanged)
    }

    static func noteProjectRemoteMemoryRouteOrModelPreferenceChanged(projectId: String?) async {
        await invalidateProjectRemoteMemorySnapshotCache(
            projectId: projectId,
            reason: .routeOrModelPreferenceChanged
        )
    }

    static func noteProjectRemoteMemoryHeartbeatAnomalyEscalated(projectId: String?) async {
        await invalidateProjectRemoteMemorySnapshotCache(
            projectId: projectId,
            reason: .heartbeatAnomalyEscalated
        )
    }

    static func noteSupervisorRemoteMemoryGrantStateChanged() async {
        await invalidateSupervisorRemoteMemorySnapshotCache(reason: .grantStateChanged)
    }

    static func noteSupervisorRemoteMemoryRouteOrModelPreferenceChanged() async {
        await invalidateSupervisorRemoteMemorySnapshotCache(reason: .routeOrModelPreferenceChanged)
    }

    static func noteSupervisorRemoteMemoryHeartbeatAnomalyEscalated() async {
        await invalidateSupervisorRemoteMemorySnapshotCache(reason: .heartbeatAnomalyEscalated)
    }


    static func buildMemoryContextFromRemoteSnapshot(
        snapshot: HubRemoteMemorySnapshotResult,
        payload: MemoryContextPayload
    ) -> MemoryContextResponsePayload {
        let servingProfile = normalized(payload.servingProfile)
        let reviewLevelHint = normalizedReviewLevelHint(payload.reviewLevelHint)
        let useMode = XTMemoryUseMode.parse(payload.mode) ?? .projectChat
        let disclosure = resolveMemoryLongtermDisclosure(
            useMode: useMode,
            retrievalAvailable: defaultRetrievalAvailability(for: useMode)
        )
        let localCanonical = XTMemorySanitizer.sanitizeText(payload.canonicalText, maxChars: 3_200, lineCap: 36) ?? ""
        let localObservations = XTMemorySanitizer.sanitizeText(payload.observationsText, maxChars: 1_800, lineCap: 24) ?? ""
        let localWorking = XTMemorySanitizer.sanitizeText(payload.workingSetText, maxChars: 2_600, lineCap: 28) ?? ""
        let dialogueWindow = XTMemorySanitizer.sanitizeText(payload.dialogueWindowText, maxChars: 4_800, lineCap: 80) ?? ""
        let portfolioBrief = XTMemorySanitizer.sanitizeText(payload.portfolioBriefText, maxChars: 900, lineCap: 16) ?? ""
        let focusedProjectAnchorPack = XTMemorySanitizer.sanitizeText(payload.focusedProjectAnchorPackText, maxChars: 1_400, lineCap: 24) ?? ""
        let longtermOutline = XTMemorySanitizer.sanitizeText(payload.longtermOutlineText, maxChars: 1_200, lineCap: 20) ?? ""
        let deltaFeed = XTMemorySanitizer.sanitizeText(payload.deltaFeedText, maxChars: 700, lineCap: 14) ?? ""
        let conflictSet = XTMemorySanitizer.sanitizeText(payload.conflictSetText, maxChars: 700, lineCap: 16) ?? ""
        let contextRefs = XTMemorySanitizer.sanitizeText(payload.contextRefsText, maxChars: 900, lineCap: 16) ?? ""
        let evidencePack = XTMemorySanitizer.sanitizeText(payload.evidencePackText, maxChars: 1_200, lineCap: 18) ?? ""
        let rawEvidence = XTMemorySanitizer.sanitizeRawEvidenceSummary(payload.rawEvidenceText, maxChars: 1_100, lineCap: 18) ?? ""
        let constitution = XTMemorySanitizer.sanitizeText(payload.constitutionHint, maxChars: 320, lineCap: 6)
            ?? "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"

        let remoteCanonical = XTMemorySanitizer.sanitizeText(snapshot.canonicalEntries.joined(separator: "\n"), maxChars: 3_200, lineCap: 36) ?? ""
        let remoteRoleProjection = XTProjectTranscriptProjection.build(
            projectId: payload.projectId ?? "",
            projectName: payload.displayName ?? payload.projectId ?? "",
            hubMessages: snapshot.roleTurnMessages
        ).promptBlock(maxRecentLines: 8, maxLineChars: 220)
        let remoteWorkingSource = remoteRoleProjection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? snapshot.workingEntries.joined(separator: "\n")
            : remoteRoleProjection
        let remoteWorking = XTMemorySanitizer.sanitizeText(remoteWorkingSource, maxChars: 2_400, lineCap: 24) ?? ""

        let mergedCanonical = mergedMemoryLayer(localPrimary: localCanonical, remoteSecondary: remoteCanonical)
        let mergedWorking = mergedMemoryLayer(localPrimary: localWorking, remoteSecondary: remoteWorking)
        let servingProfileSection = memoryServingProfileSection(servingProfile)
        let servingGovernorSection = memoryServingGovernorSection(
            useMode: useMode,
            servingProfile: servingProfile,
            reviewLevelHint: reviewLevelHint,
            hasFocusedProjectAnchor: !focusedProjectAnchorPack.isEmpty
        )
        let dialogueWindowSection = namedMemorySection("DIALOGUE_WINDOW", body: dialogueWindow)
        let portfolioBriefSection = namedMemorySection("PORTFOLIO_BRIEF", body: portfolioBrief)
        let focusedProjectAnchorPackSection = namedMemorySection("FOCUSED_PROJECT_ANCHOR_PACK", body: focusedProjectAnchorPack)
        let longtermOutlineSection = namedMemorySection("LONGTERM_OUTLINE", body: longtermOutline)
        let deltaFeedSection = namedMemorySection("DELTA_FEED", body: deltaFeed)
        let conflictSetSection = namedMemorySection("CONFLICT_SET", body: conflictSet)
        let contextRefsSection = namedMemorySection("CONTEXT_REFS", body: contextRefs)
        let evidencePackSection = namedMemorySection("EVIDENCE_PACK", body: evidencePack)

        let finalText = ensureMemoryLongtermDisclosureText(
            """
[MEMORY_V1]
\(servingProfileSection.isEmpty ? "" : "\(servingProfileSection)\n")
\(servingGovernorSection.isEmpty ? "" : "\(servingGovernorSection)\n")
\(dialogueWindowSection.isEmpty ? "" : "\(dialogueWindowSection)\n")
\(portfolioBriefSection.isEmpty ? "" : "\(portfolioBriefSection)\n")
\(focusedProjectAnchorPackSection.isEmpty ? "" : "\(focusedProjectAnchorPackSection)\n")
\(longtermOutlineSection.isEmpty ? "" : "\(longtermOutlineSection)\n")
\(deltaFeedSection.isEmpty ? "" : "\(deltaFeedSection)\n")
\(conflictSetSection.isEmpty ? "" : "\(conflictSetSection)\n")
\(contextRefsSection.isEmpty ? "" : "\(contextRefsSection)\n")
\(evidencePackSection.isEmpty ? "" : "\(evidencePackSection)\n")
[L0_CONSTITUTION]
\(constitution.isEmpty ? "(none)" : constitution)
[/L0_CONSTITUTION]

[L1_CANONICAL]
\(mergedCanonical.isEmpty ? "(none)" : mergedCanonical)
[/L1_CANONICAL]

[L2_OBSERVATIONS]
\(localObservations.isEmpty ? "(none)" : localObservations)
[/L2_OBSERVATIONS]

[L3_WORKING_SET]
\(mergedWorking.isEmpty ? "(none)" : mergedWorking)
[/L3_WORKING_SET]

[L4_RAW_EVIDENCE]
\(rawEvidence.isEmpty ? "(none)" : rawEvidence)
latest_user:
\(payload.latestUser)
[/L4_RAW_EVIDENCE]
[/MEMORY_V1]
""",
            disclosure: disclosure
        )

        let l0Used = TokenEstimator.estimateTokens(constitution)
        let l1Used = TokenEstimator.estimateTokens(mergedCanonical)
            + TokenEstimator.estimateTokens(portfolioBrief)
            + TokenEstimator.estimateTokens(longtermOutline)
        let l2Used = TokenEstimator.estimateTokens(localObservations)
            + TokenEstimator.estimateTokens(deltaFeed)
            + TokenEstimator.estimateTokens(conflictSet)
        let l3Used = TokenEstimator.estimateTokens(dialogueWindow)
            + TokenEstimator.estimateTokens(mergedWorking)
            + TokenEstimator.estimateTokens(focusedProjectAnchorPack)
        let l4Used = TokenEstimator.estimateTokens(rawEvidence + "\n" + payload.latestUser)
            + TokenEstimator.estimateTokens(contextRefs)
            + TokenEstimator.estimateTokens(evidencePack)
        let usedTotal = max(0, l0Used + l1Used + l2Used + l3Used + l4Used)

        let b = payload.budgets
        let configuredBudget: Int
        if let v = b?.totalTokens {
            configuredBudget = v
        } else if let v = b?.l0Tokens {
            configuredBudget = v
        } else if let v = b?.l1Tokens {
            configuredBudget = v
        } else if let v = b?.l2Tokens {
            configuredBudget = v
        } else if let v = b?.l3Tokens {
            configuredBudget = v
        } else if let v = b?.l4Tokens {
            configuredBudget = v
        } else {
            configuredBudget = 1600
        }
        let budgetTotal = max(usedTotal, configuredBudget)

        let layerUsage = [
            MemoryContextLayerUsage(layer: "l0_constitution", usedTokens: l0Used, budgetTokens: payload.budgets?.l0Tokens ?? max(80, l0Used)),
            MemoryContextLayerUsage(layer: "l1_canonical", usedTokens: l1Used, budgetTokens: payload.budgets?.l1Tokens ?? max(220, l1Used)),
            MemoryContextLayerUsage(layer: "l2_observations", usedTokens: l2Used, budgetTokens: payload.budgets?.l2Tokens ?? max(220, l2Used)),
            MemoryContextLayerUsage(layer: "l3_working_set", usedTokens: l3Used, budgetTokens: payload.budgets?.l3Tokens ?? max(300, l3Used)),
            MemoryContextLayerUsage(layer: "l4_raw_evidence", usedTokens: l4Used, budgetTokens: payload.budgets?.l4Tokens ?? max(300, l4Used)),
        ]

        return MemoryContextResponsePayload(
            text: finalText,
            source: snapshot.source,
            resolvedMode: payload.mode,
            resolvedProfile: servingProfile,
            longtermMode: disclosure.longtermMode,
            retrievalAvailable: disclosure.retrievalAvailable,
            fulltextNotLoaded: disclosure.fulltextNotLoaded,
            freshness: nil,
            cacheHit: nil,
            denyCode: nil,
            downgradeCode: nil,
            budgetTotalTokens: budgetTotal,
            usedTotalTokens: usedTotal,
            layerUsage: layerUsage,
            truncatedLayers: [],
            redactedItems: 0,
            privateDrops: 0
        )
    }

    private static func memoryServingProfileSection(_ servingProfile: String?) -> String {
        let normalizedProfile = normalized(servingProfile) ?? ""
        guard !normalizedProfile.isEmpty else { return "" }
        return """
[SERVING_PROFILE]
profile_id: \(normalizedProfile)
[/SERVING_PROFILE]
"""
    }

    private static func memoryServingGovernorSection(
        useMode: XTMemoryUseMode,
        servingProfile: String?,
        reviewLevelHint: String?,
        hasFocusedProjectAnchor: Bool = false
    ) -> String {
        guard useMode == .supervisorOrchestration else { return "" }

        let normalizedProfile = XTMemoryServingProfile.parse(servingProfile) ?? .m1Execute
        let normalizedReviewLevel = parseSupervisorReviewLevelHint(reviewLevelHint)
            ?? defaultSupervisorReviewLevelHint(for: normalizedProfile)
        let profileFloor = minimumSupervisorServingProfile(
            for: normalizedReviewLevel,
            hasFocusedProjectAnchor: hasFocusedProjectAnchor
        )
        let minimumPack = orderedSupervisorMinimumPack(
            servingProfile: normalizedProfile,
            reviewLevelHint: normalizedReviewLevel,
            hasFocusedProjectAnchor: hasFocusedProjectAnchor
        )
        let compressionPolicy: String
        switch normalizedReviewLevel {
        case .r1Pulse:
            compressionPolicy = "protect_anchor_then_delta_then_portfolio"
        case .r2Strategic:
            compressionPolicy = hasFocusedProjectAnchor
                ? "protect_anchor_longterm_decision_blocker_and_evidence_first"
                : "protect_anchor_conflict_longterm_then_refs"
        case .r3Rescue:
            compressionPolicy = "protect_anchor_conflict_and_evidence_first"
        }

        return """
[SERVING_GOVERNOR]
review_level_hint: \(normalizedReviewLevel.rawValue)
profile_floor: \(profileFloor.rawValue)
minimum_pack: \(minimumPack.joined(separator: ", "))
compression_policy: \(compressionPolicy)
[/SERVING_GOVERNOR]
"""
    }

    static func parseSupervisorReviewLevelHint(
        _ raw: String?
    ) -> SupervisorReviewLevel? {
        guard let normalizedRaw = normalizedReviewLevelHint(raw) else { return nil }
        return SupervisorReviewLevel(rawValue: normalizedRaw)
    }

    private static func defaultSupervisorReviewLevelHint(
        for servingProfile: XTMemoryServingProfile
    ) -> SupervisorReviewLevel {
        switch servingProfile {
        case .m3DeepDive, .m4FullScan:
            return .r3Rescue
        case .m2PlanReview:
            return .r2Strategic
        default:
            return .r1Pulse
        }
    }

    static func minimumSupervisorServingProfile(
        for reviewLevelHint: SupervisorReviewLevel,
        hasFocusedProjectAnchor: Bool
    ) -> XTMemoryServingProfile {
        switch reviewLevelHint {
        case .r1Pulse:
            return .m1Execute
        case .r2Strategic:
            return hasFocusedProjectAnchor ? .m3DeepDive : .m2PlanReview
        case .r3Rescue:
            return .m3DeepDive
        }
    }

    private static func orderedSupervisorMinimumPack(
        servingProfile: XTMemoryServingProfile,
        reviewLevelHint: SupervisorReviewLevel,
        hasFocusedProjectAnchor: Bool
    ) -> [String] {
        let profilePack = minimumPackForSupervisorServingProfile(servingProfile)
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

    private static func minimumPackForSupervisorServingProfile(
        _ servingProfile: XTMemoryServingProfile
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
        _ reviewLevelHint: SupervisorReviewLevel,
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

    private static func namedMemorySection(_ tag: String, body: String) -> String {
        let normalizedBody = normalized(body) ?? ""
        guard !normalizedBody.isEmpty else { return "" }
        return """
[\(tag)]
\(normalizedBody)
[/\(tag)]
"""
    }

    private static func mergedMemoryLayer(localPrimary: String, remoteSecondary: String) -> String {
        let local = localPrimary.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = remoteSecondary.trimmingCharacters(in: .whitespacesAndNewlines)
        if local.isEmpty { return remote }
        if remote.isEmpty { return local }
        return """
\(local)

[hub_remote]
\(remote)
"""
    }

    struct RemoteMemorySnapshotFetchResult {
        var snapshot: HubRemoteMemorySnapshotResult
        var cacheHit: Bool
        var cacheMetadata: HubRemoteMemorySnapshotCache.Metadata?
    }

    private static func remoteMemorySnapshotWorkingLimit(
        for mode: XTMemoryUseMode
    ) -> Int {
        switch mode {
        case .supervisorOrchestration:
            return 80
        default:
            return 12
        }
    }

    static func fetchRemoteMemorySnapshot(
        mode: XTMemoryUseMode,
        projectId: String?,
        bypassCache: Bool,
        timeoutSec: Double
    ) async -> RemoteMemorySnapshotFetchResult {
        let cacheKey = HubRemoteMemorySnapshotCache.Key(
            hubProfileID: currentHubCacheScopeID(),
            mode: mode.rawValue,
            projectId: normalized(projectId)
        )
        let posture = XTMemoryRoleScopedRouter.remoteSnapshotCachePosture(for: mode)
        if !bypassCache, let cached = await HubIPCClientRemoteMemorySnapshotStorage.cache.snapshotRecord(for: cacheKey) {
            return RemoteMemorySnapshotFetchResult(
                snapshot: cached.snapshot,
                cacheHit: true,
                cacheMetadata: cached.metadata
            )
        }

        let fetchStartedAt = Date()
        let remote: HubRemoteMemorySnapshotResult
        if let override = remoteMemorySnapshotOverride() {
            remote = await override(mode, projectId, bypassCache, timeoutSec)
        } else {
            remote = await HubPairingCoordinator.shared.fetchRemoteMemorySnapshot(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                mode: mode.rawValue,
                projectId: normalized(projectId),
                canonicalLimit: 24,
                workingLimit: remoteMemorySnapshotWorkingLimit(for: mode),
                timeoutSec: timeoutSec,
                allowClientKitInstallRetry: false
            )
        }
        let cacheMetadata: HubRemoteMemorySnapshotCache.Metadata?
        if remote.ok {
            cacheMetadata = await HubIPCClientRemoteMemorySnapshotStorage.cache.store(
                remote,
                for: cacheKey,
                posture: posture,
                now: fetchStartedAt
            )
        } else {
            await HubIPCClientRemoteMemorySnapshotStorage.cache.invalidate(key: cacheKey, reason: .remoteFetchFailed)
            cacheMetadata = nil
        }
        return RemoteMemorySnapshotFetchResult(
            snapshot: remote,
            cacheHit: false,
            cacheMetadata: cacheMetadata
        )
    }

    private static func currentHubCacheScopeID() -> String {
        XTHubProfilesStorage.activeCacheScopeID()
    }

}
