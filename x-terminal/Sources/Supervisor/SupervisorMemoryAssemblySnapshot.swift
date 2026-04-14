import Foundation

private func xtSupervisorMemoryCompactJSONString<T: Encodable>(_ value: T) -> String? {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(value),
          let text = String(data: data, encoding: .utf8) else {
        return nil
    }
    return text
}

struct SupervisorMemoryAssemblyCompactSummary: Codable, Equatable, Sendable {
    var headlineText: String
    var detailText: String?
    var helpText: String
}

struct SupervisorMemoryAssemblySnapshot: Equatable, Codable, Sendable {
    var source: String
    var resolutionSource: String?
    var updatedAt: TimeInterval
    var assemblyPurpose: String = ""
    var dominantMode: String? = nil
    var memoryResolutionTrigger: String = ""
    var triggerSource: String = ""
    var governanceReviewTrigger: String = ""
    var governanceReviewRunKind: String = ""
    var reviewLevelHint: String
    var requestedProfile: String
    var profileFloor: String
    var resolvedProfile: String
    var attemptedProfiles: [String]
    var progressiveUpgradeCount: Int
    var focusedProjectId: String?
    var configuredRawWindowProfile: String = ""
    var recommendedRawWindowProfile: String = ""
    var effectiveRawWindowProfile: String = ""
    var configuredReviewMemoryDepth: String = ""
    var recommendedReviewMemoryDepth: String = ""
    var effectiveReviewMemoryDepth: String = ""
    var sTierReviewMemoryCeiling: String = ""
    var reviewMemoryCeilingHit: Bool = false
    var purposeScopedReviewMemoryCap: String? = nil
    var purposeScopedReviewMemoryCapApplied: Bool = false
    var rawWindowProfile: String = XTSupervisorRecentRawContextProfile.defaultProfile.rawValue
    var rawWindowFloorPairs: Int = XTSupervisorRecentRawContextProfile.hardFloorPairs
    var rawWindowCeilingPairs: Int? = XTSupervisorRecentRawContextProfile.defaultProfile.windowCeilingPairs
    var rawWindowSelectedPairs: Int = 0
    var eligibleMessages: Int = 0
    var lowSignalDroppedMessages: Int = 0
    var rawWindowSource: String = "xt_cache"
    var rollingDigestPresent: Bool = false
    var continuityFloorSatisfied: Bool = false
    var truncationAfterFloor: Bool = false
    var continuityTraceLines: [String] = []
    var lowSignalDropSampleLines: [String] = []
    var selectedSections: [String]
    var omittedSections: [String]
    var servingObjectContract: [String] = []
    var contextRefsSelected: Int
    var contextRefsOmitted: Int
    var evidenceItemsSelected: Int
    var evidenceItemsOmitted: Int
    var budgetTotalTokens: Int?
    var usedTotalTokens: Int?
    var truncatedLayers: [String]
    var freshness: String?
    var cacheHit: Bool?
    var remoteSnapshotCacheScope: String? = nil
    var remoteSnapshotCachedAtMs: Int64? = nil
    var remoteSnapshotAgeMs: Int? = nil
    var remoteSnapshotTTLRemainingMs: Int? = nil
    var remoteSnapshotCachePosture: String? = nil
    var remoteSnapshotInvalidationReason: String? = nil
    var denyCode: String?
    var downgradeCode: String?
    var reasonCode: String?
    var compressionPolicy: String
    var durableCandidateMirrorStatus: SupervisorDurableCandidateMirrorStatus = .notNeeded
    var durableCandidateMirrorTarget: String? = nil
    var durableCandidateMirrorAttempted: Bool = false
    var durableCandidateMirrorErrorCode: String? = nil
    var durableCandidateLocalStoreRole: String = XTSupervisorDurableCandidateMirror.localStoreRole
    var localPersonalMemoryWriteIntent: String? = nil
    var localCrossLinkWriteIntent: String? = nil
    var localPersonalReviewWriteIntent: String? = nil
    var latestReviewNoteAvailable: Bool = false
    var latestGuidanceAvailable: Bool = false
    var latestGuidanceAckStatus: String = ""
    var latestGuidanceAckRequired: Bool? = nil
    var latestGuidanceDeliveryMode: String = ""
    var latestGuidanceInterventionMode: String = ""
    var latestGuidanceSafePointPolicy: String = ""
    var pendingAckGuidanceAvailable: Bool = false
    var pendingAckGuidanceAckStatus: String = ""
    var pendingAckGuidanceAckRequired: Bool? = nil
    var pendingAckGuidanceDeliveryMode: String = ""
    var pendingAckGuidanceInterventionMode: String = ""
    var pendingAckGuidanceSafePointPolicy: String = ""
    var remotePromptVariantLabel: String? = nil
    var remotePromptMode: String? = nil
    var remotePromptTokenEstimate: Int? = nil
    var remoteResponseTokenLimit: Int? = nil
    var remoteTotalTokenEstimate: Int? = nil
    var remoteSingleRequestBudget: Int? = nil
    var remoteSingleRequestBudgetSource: String? = nil
    var scopedPromptRecoveryMode: String? = nil
    var scopedPromptRecoverySections: [String]? = nil
    var supervisorMemoryPolicy: XTSupervisorMemoryPolicySnapshot? = nil
    var memoryAssemblyResolution: XTMemoryAssemblyResolution? = nil

    var sourceLabel: String {
        XTMemorySourceTruthPresentation.label(source)
    }

    var sourceClass: String {
        XTMemorySourceTruthPresentation.sourceClass(source)
    }

    var rawWindowSourceLabel: String {
        XTMemorySourceTruthPresentation.label(rawWindowSource)
    }

    var rawWindowSourceClass: String {
        XTMemorySourceTruthPresentation.sourceClass(rawWindowSource)
    }

    var normalizedScopedPromptRecoverySections: [String] {
        (scopedPromptRecoverySections ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static let reviewGuidanceCarrierSections: Set<String> = [
        "focused_project_anchor_pack",
        "context_refs",
        "evidence_pack"
    ]

    var reviewGuidanceCarrierPresent: Bool {
        !Set(selectedSections).isDisjoint(with: Self.reviewGuidanceCarrierSections)
    }

    var latestReviewNoteActualized: Bool {
        latestReviewNoteAvailable && reviewGuidanceCarrierPresent
    }

    var latestGuidanceActualized: Bool {
        latestGuidanceAvailable && reviewGuidanceCarrierPresent
    }

    var pendingAckGuidanceActualized: Bool {
        pendingAckGuidanceAvailable && reviewGuidanceCarrierPresent
    }

    var guidanceContinuityRenderedRefs: [String] {
        var refs: [String] = []
        if latestReviewNoteActualized {
            refs.append("latest_review_note")
        }
        if latestGuidanceActualized {
            refs.append("latest_guidance")
        }
        if pendingAckGuidanceActualized {
            refs.append("pending_ack_guidance")
        }
        return xtOrderedUniqueSupervisorExplainabilityValues(refs)
    }

    var scopedPromptRecoveryHumanLine: String? {
        let normalizedMode = scopedPromptRecoveryMode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedSections = normalizedScopedPromptRecoverySections
        guard !normalizedMode.isEmpty || !normalizedSections.isEmpty else { return nil }

        let modeLabel = scopedPromptRecoveryModeLabel(normalizedMode)
        let sectionsText = normalizedSections.isEmpty
            ? "已启用项目范围恢复"
            : "补回 \(normalizedSections.map(scopedPromptRecoverySectionLabel).joined(separator: "、"))"
        if modeLabel.isEmpty {
            return sectionsText
        }
        return "\(modeLabel)：\(sectionsText)"
    }

    var recentRawContextPolicyHumanLine: String? {
        let configured = XTSupervisorRecentRawContextProfile(rawValue: configuredRawWindowProfile)
        let recommended = XTSupervisorRecentRawContextProfile(rawValue: recommendedRawWindowProfile)
        let effective = XTSupervisorRecentRawContextProfile(rawValue: effectiveRawWindowProfile)
        guard configured != nil || recommended != nil || effective != nil else { return nil }
        return "Recent Raw Context：configured \(configured?.displayName ?? configuredRawWindowProfile) · recommended \(recommended?.displayName ?? recommendedRawWindowProfile) · effective \(effective?.displayName ?? effectiveRawWindowProfile)"
    }

    var assemblyPurposeHumanLine: String? {
        let purpose = XTSupervisorMemoryAssemblyPurpose(rawValue: assemblyPurpose)
        let cap = purposeScopedReviewMemoryCap?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard purpose != nil || !cap.isEmpty else { return nil }

        var parts = [
            "Assembly Purpose：\(purpose?.displayName ?? assemblyPurpose)"
        ]
        if !cap.isEmpty {
            parts.append("purpose cap \(cap)")
        }
        if purposeScopedReviewMemoryCapApplied {
            parts.append("purpose cap applied")
        }
        return parts.joined(separator: " · ")
    }

    var reviewMemoryDepthHumanLine: String? {
        let configured = XTSupervisorReviewMemoryDepthProfile(rawValue: configuredReviewMemoryDepth)
        let recommended = XTSupervisorReviewMemoryDepthProfile(rawValue: recommendedReviewMemoryDepth)
        let effective = XTSupervisorReviewMemoryDepthProfile(rawValue: effectiveReviewMemoryDepth)
        guard configured != nil || recommended != nil || effective != nil else { return nil }

        var parts = [
            "Review Memory Depth：configured \(configured?.displayName ?? configuredReviewMemoryDepth)",
            "recommended \(recommended?.displayName ?? recommendedReviewMemoryDepth)",
            "effective \(effective?.displayName ?? effectiveReviewMemoryDepth)",
            "ceiling \(sTierReviewMemoryCeiling)"
        ]
        if reviewMemoryCeilingHit {
            parts.append("ceiling hit")
        }
        return parts.joined(separator: " · ")
    }

    var guidanceContinuityHumanLine: String? {
        var parts: [String] = []
        if latestReviewNoteAvailable {
            parts.append("latest review \(latestReviewNoteActualized ? "carried" : "omitted")")
        }
        if latestGuidanceAvailable {
            parts.append(
                "latest guidance \(latestGuidanceActualized ? "carried" : "omitted")"
                    + guidanceAckStateSummary(
                        ackStatus: latestGuidanceAckStatus,
                        ackRequired: latestGuidanceAckRequired,
                        safePointPolicy: latestGuidanceSafePointPolicy
                    )
            )
        }
        if pendingAckGuidanceAvailable {
            parts.append(
                "pending guidance \(pendingAckGuidanceActualized ? "carried" : "omitted")"
                    + guidanceAckStateSummary(
                        ackStatus: pendingAckGuidanceAckStatus,
                        ackRequired: pendingAckGuidanceAckRequired,
                        safePointPolicy: pendingAckGuidanceSafePointPolicy
                    )
            )
        }
        guard !parts.isEmpty else { return nil }
        return "Review / Guidance：\(parts.joined(separator: " · "))"
    }

    var actualizedMemoryAssemblyResolution: XTMemoryAssemblyResolution? {
        guard var resolution = memoryAssemblyResolution else { return nil }

        let actualServingObjects = actualSupervisorServingObjects(
            from: selectedSections,
            fallback: resolution.selectedServingObjects
        )
        guard !actualServingObjects.isEmpty else { return resolution }

        let trackedServingObjects = relevantSupervisorExplainabilityServingObjects(
            contract: servingObjectContract
        )
        let trackedSet = Set(trackedServingObjects)
        let actualSet = Set(actualServingObjects)
        let staticExcluded = resolution.excludedBlocks.filter { !trackedSet.contains($0) }
        let actualExcluded = trackedServingObjects.filter { !actualSet.contains($0) }
        let actualSelectedPlanes = actualSupervisorSelectedPlanes(
            from: actualServingObjects,
            fallback: resolution.selectedPlanes
        )

        resolution.selectedPlanes = actualSelectedPlanes
        resolution.selectedSlots = actualServingObjects
        resolution.selectedServingObjects = actualServingObjects
        resolution.excludedBlocks = xtOrderedUniqueSupervisorExplainabilityValues(
            staticExcluded + actualExcluded
        )
        return resolution
    }

    var actualizedSelectedServingObjectLabels: [String] {
        guard let resolution = actualizedMemoryAssemblyResolution else { return [] }
        return xtOrderedUniqueSupervisorExplainabilityValues(
            resolution.selectedServingObjects.map(supervisorServingObjectHumanLabel)
        )
    }

    var actualizedExcludedBlockLabels: [String] {
        guard let resolution = actualizedMemoryAssemblyResolution else { return [] }
        return xtOrderedUniqueSupervisorExplainabilityValues(
            resolution.excludedBlocks.map(supervisorServingObjectHumanLabel)
        )
    }

    var actualizedSelectedServingObjectHumanLine: String? {
        let labels = actualizedSelectedServingObjectLabels
        guard !labels.isEmpty else { return nil }
        return "实际带入：\(labels.joined(separator: "、"))"
    }

    var actualizedExcludedBlockHumanLine: String? {
        let labels = actualizedExcludedBlockLabels
        guard !labels.isEmpty else { return nil }
        return "本轮缺口：\(labels.joined(separator: "、"))"
    }

    var compactSummary: SupervisorMemoryAssemblyCompactSummary {
        let configuredDepth = reviewDepthProfileLabel(
            configuredReviewMemoryDepth,
            fallback: configuredReviewMemoryDepth
        )
        let recommendedDepth = reviewDepthProfileLabel(
            recommendedReviewMemoryDepth,
            fallback: recommendedReviewMemoryDepth
        )
        let effectiveDepth = reviewDepthProfileLabel(
            effectiveReviewMemoryDepth,
            fallback: effectiveReviewMemoryDepth
        )
        let ceiling = servingProfileLabel(
            sTierReviewMemoryCeiling,
            fallback: sTierReviewMemoryCeiling
        )
        let rawContext = rawContextProfileLabel(
            effectiveRawWindowProfile,
            fallback: effectiveRawWindowProfile
        )
        let purpose = assemblyPurposeLabel(
            assemblyPurpose,
            fallback: assemblyPurpose
        )
        let focus = focusedProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let purposeCap = purposeScopedReviewMemoryCap.flatMap {
            servingProfileLabel($0, fallback: $0)
        }

        var detailParts = [
            "Recent Raw Context \(rawContext)",
            rawWindowSelectedPairs > 0 ? "\(rawWindowSelectedPairs) pairs" : nil,
            "configured/recommended \(configuredDepth)/\(recommendedDepth)",
            purpose.isEmpty ? nil : "purpose \(purpose)",
            purposeScopedReviewMemoryCapApplied
                ? "purpose cap \(purposeCap ?? purposeScopedReviewMemoryCap ?? "unknown")"
                : nil,
            reviewMemoryCeilingHit ? "ceiling hit" : nil,
            focus.isEmpty ? nil : "focus \(focus)"
        ].compactMap { $0 }

        if !continuityFloorSatisfied {
            detailParts.append("continuity floor pending")
        }
        if pendingAckGuidanceAvailable {
            detailParts.append(
                pendingAckGuidanceActualized
                    ? "pending guidance \(pendingAckGuidanceAckStatus.isEmpty ? "active" : pendingAckGuidanceAckStatus)"
                    : "pending guidance omitted"
            )
        } else if latestGuidanceAvailable && !latestGuidanceAckStatus.isEmpty {
            detailParts.append(
                latestGuidanceActualized
                    ? "guidance \(latestGuidanceAckStatus)"
                    : "guidance omitted"
            )
        }

        return SupervisorMemoryAssemblyCompactSummary(
            headlineText: "Review Memory · \(effectiveDepth) / ceiling \(ceiling)",
            detailText: detailParts.isEmpty ? nil : detailParts.joined(separator: " · "),
            helpText: [
                "这里显示的是最近一次真正装给 Supervisor 的 review-memory，不是静态配置。S-Tier 只提供 Supervisor 的 review-memory ceiling；Recent Raw Context 和 Review Memory Depth 仍由 role-aware resolver 按 review purpose 单独计算。",
                self.remoteSnapshotCacheHumanLine
            ]
            .compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        )
    }

    var governanceReviewHumanLine: String? {
        let purpose = XTSupervisorMemoryAssemblyPurpose(rawValue: assemblyPurpose)
        guard purpose == .governanceReview || purpose == .portfolioReview else { return nil }

        let normalizedTriggerSource = triggerSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReviewTrigger = governanceReviewTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRunKind = governanceReviewRunKind.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTriggerSource.isEmpty
                || !normalizedReviewTrigger.isEmpty
                || !normalizedRunKind.isEmpty else {
            return nil
        }

        var parts: [String] = []
        if !normalizedTriggerSource.isEmpty {
            parts.append("source \(governanceTriggerSourceLabel(normalizedTriggerSource))")
        }
        if !normalizedReviewTrigger.isEmpty {
            parts.append("trigger \(governanceReviewTriggerLabel(normalizedReviewTrigger))")
        }
        if !normalizedRunKind.isEmpty {
            parts.append("run kind \(governanceReviewRunKindLabel(normalizedRunKind))")
        }
        return parts.isEmpty ? nil : "Governance Review：\(parts.joined(separator: " · "))"
    }

    var statusLine: String {
        var parts = [
            "assembly req=\(requestedProfile)",
            "floor=\(profileFloor)",
            "resolved=\(resolvedProfile)",
            "raw=\(rawWindowSelectedPairs)/\(rawWindowFloorPairs)p"
        ]
        if let dominantMode, !dominantMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("mode=\(dominantMode)")
        }
        if progressiveUpgradeCount > 0 {
            parts.append("upgrades=\(progressiveUpgradeCount)")
        }
        if !truncatedLayers.isEmpty {
            parts.append("trunc=\(truncatedLayers.joined(separator: ","))")
        }
        if let denyCode, !denyCode.isEmpty {
            parts.append("deny=\(denyCode)")
        } else if let reasonCode, !reasonCode.isEmpty {
            parts.append("reason=\(reasonCode)")
        }
        return parts.joined(separator: " · ")
    }

    var detailLine: String {
        var parts: [String] = []
        if let focusedProjectId, !focusedProjectId.isEmpty {
            parts.append("focus=\(focusedProjectId)")
        } else {
            parts.append("focus=(none)")
        }
        var rawWindow = "raw_window=\(rawWindowProfile) \(rawWindowSelectedPairs)/\(rawWindowFloorPairs)p"
        if let rawWindowCeilingPairs {
            rawWindow += " ceil=\(rawWindowCeilingPairs)p"
        } else {
            rawWindow += " ceil=auto"
        }
        rawWindow += " src=\(rawWindowSource)"
        rawWindow += continuityFloorSatisfied ? " floor_ok=true" : " floor_ok=false"
        if lowSignalDroppedMessages > 0 {
            rawWindow += " low_signal_drop=\(lowSignalDroppedMessages)"
        }
        if truncationAfterFloor {
            rawWindow += " truncated_after_floor=true"
        }
        if rollingDigestPresent {
            rawWindow += " rolling_digest=true"
        }
        parts.append(rawWindow)
        if let assemblyPurposeHumanLine {
            parts.append(assemblyPurposeHumanLine)
        }
        if let recentRawContextPolicyHumanLine {
            parts.append(recentRawContextPolicyHumanLine)
        }
        if let reviewMemoryDepthHumanLine {
            parts.append(reviewMemoryDepthHumanLine)
        }
        if let guidanceContinuityHumanLine {
            parts.append(guidanceContinuityHumanLine)
        }
        parts.append(
            "sections=\(selectedSections.isEmpty ? "(none)" : selectedSections.joined(separator: ","))"
        )
        if !servingObjectContract.isEmpty {
            parts.append("contract=\(servingObjectContract.joined(separator: ","))")
        }
        if !omittedSections.isEmpty {
            parts.append("omitted=\(omittedSections.joined(separator: ","))")
        }
        parts.append("refs=\(contextRefsSelected)/\(contextRefsSelected + contextRefsOmitted)")
        parts.append("evidence=\(evidenceItemsSelected)/\(evidenceItemsSelected + evidenceItemsOmitted)")
        if let usedTotalTokens, let budgetTotalTokens, budgetTotalTokens > 0 {
            parts.append("tokens=\(usedTotalTokens)/\(budgetTotalTokens)")
        }
        if let remoteSnapshotCacheHumanLine = self.remoteSnapshotCacheHumanLine {
            parts.append(remoteSnapshotCacheHumanLine)
        }
        if durableCandidateMirrorAttempted || durableCandidateMirrorStatus != .notNeeded {
            var mirror = "mirror=\(durableCandidateMirrorStatus.rawValue)"
            if let durableCandidateMirrorErrorCode, !durableCandidateMirrorErrorCode.isEmpty {
                mirror += " reason=\(durableCandidateMirrorErrorCode)"
            }
            parts.append(mirror)
        }
        if let localStoreWriteLine {
            parts.append(localStoreWriteLine)
        }
        if let remotePromptBudgetSummaryLine {
            parts.append(remotePromptBudgetSummaryLine)
        }
        if let scopedPromptRecoveryHumanLine {
            parts.append(scopedPromptRecoveryHumanLine)
        }
        return parts.joined(separator: " · ")
    }

    var continuityDrillDownLines: [String] {
        var lines: [String] = []
        var summary = "continuity raw_source=\(rawWindowSource) raw_window=\(rawWindowSelectedPairs)/\(rawWindowFloorPairs)p"
        if let rawWindowCeilingPairs {
            summary += " ceil=\(rawWindowCeilingPairs)p"
        } else {
            summary += " ceil=auto"
        }
        summary += " profile=\(rawWindowProfile)"
        summary += " floor_ok=\(continuityFloorSatisfied ? "true" : "false")"
        summary += " eligible=\(eligibleMessages)"
        if lowSignalDroppedMessages > 0 {
            summary += " low_signal_drop=\(lowSignalDroppedMessages)"
        }
        if rollingDigestPresent {
            summary += " rolling_digest=true"
        }
        if truncationAfterFloor {
            summary += " truncated_after_floor=true"
        }
        lines.append(summary)
        lines.append("continuity_source_label=\(rawWindowSourceLabel)")
        lines.append("continuity_source_class=\(rawWindowSourceClass)")
        lines.append("memory_source=\(source)")
        lines.append("memory_source_label=\(sourceLabel)")
        lines.append("memory_source_class=\(sourceClass)")
        if let freshness, !freshness.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("memory_freshness=\(freshness)")
        }
        if let cacheHit {
            lines.append("memory_cache_hit=\(cacheHit)")
        }
        if let remoteSnapshotCacheScope,
           !remoteSnapshotCacheScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("remote_snapshot_cache_scope=\(remoteSnapshotCacheScope)")
        }
        if let remoteSnapshotCachedAtMs {
            lines.append("remote_snapshot_cached_at_ms=\(remoteSnapshotCachedAtMs)")
        }
        if let remoteSnapshotAgeMs {
            lines.append("remote_snapshot_age_ms=\(remoteSnapshotAgeMs)")
        }
        if let remoteSnapshotTTLRemainingMs {
            lines.append("remote_snapshot_ttl_remaining_ms=\(remoteSnapshotTTLRemainingMs)")
        }
        if let remoteSnapshotCachePosture,
           !remoteSnapshotCachePosture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("remote_snapshot_cache_posture=\(remoteSnapshotCachePosture)")
        }
        if let remoteSnapshotInvalidationReason,
           !remoteSnapshotInvalidationReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("remote_snapshot_invalidation_reason=\(remoteSnapshotInvalidationReason)")
        }
        if let dominantMode, !dominantMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("dominant_mode=\(dominantMode)")
        }
        if !assemblyPurpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("assembly_purpose=\(assemblyPurpose)")
        }
        if !memoryResolutionTrigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("memory_resolution_trigger=\(memoryResolutionTrigger)")
        }
        if !triggerSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("trigger_source=\(triggerSource)")
        }
        if !governanceReviewTrigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("governance_review_trigger=\(governanceReviewTrigger)")
        }
        if !governanceReviewRunKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("governance_review_run_kind=\(governanceReviewRunKind)")
        }
        lines.append("configured_supervisor_recent_raw_context_profile=\(configuredRawWindowProfile)")
        lines.append("recommended_supervisor_recent_raw_context_profile=\(recommendedRawWindowProfile)")
        lines.append("effective_supervisor_recent_raw_context_profile=\(effectiveRawWindowProfile)")
        lines.append("configured_review_memory_depth=\(configuredReviewMemoryDepth)")
        lines.append("recommended_review_memory_depth=\(recommendedReviewMemoryDepth)")
        lines.append("effective_review_memory_depth=\(effectiveReviewMemoryDepth)")
        lines.append("s_tier_review_memory_ceiling=\(sTierReviewMemoryCeiling)")
        lines.append("review_memory_ceiling_hit=\(reviewMemoryCeilingHit)")
        if let purposeScopedReviewMemoryCap,
           !purposeScopedReviewMemoryCap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("purpose_scoped_review_memory_cap=\(purposeScopedReviewMemoryCap)")
        }
        lines.append("purpose_scoped_review_memory_cap_applied=\(purposeScopedReviewMemoryCapApplied)")
        lines.append(contentsOf: continuityTraceLines.prefix(3))
        if !lowSignalDropSampleLines.isEmpty {
            lines.append("low_signal_samples: \(lowSignalDropSampleLines.prefix(3).joined(separator: " | "))")
        }
        if let recentRawContextPolicyHumanLine {
            lines.append(recentRawContextPolicyHumanLine)
        }
        if let assemblyPurposeHumanLine {
            lines.append(assemblyPurposeHumanLine)
        }
        if let reviewMemoryDepthHumanLine {
            lines.append(reviewMemoryDepthHumanLine)
        }
        if let governanceReviewHumanLine {
            lines.append(governanceReviewHumanLine)
        }
        lines.append("supervisor_review_guidance_carrier_present=\(reviewGuidanceCarrierPresent)")
        lines.append("supervisor_memory_latest_review_note_available=\(latestReviewNoteAvailable)")
        lines.append("supervisor_memory_latest_review_note_actualized=\(latestReviewNoteActualized)")
        lines.append("supervisor_memory_latest_guidance_available=\(latestGuidanceAvailable)")
        lines.append("supervisor_memory_latest_guidance_actualized=\(latestGuidanceActualized)")
        if !latestGuidanceAckStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("supervisor_memory_latest_guidance_ack_status=\(latestGuidanceAckStatus)")
        }
        if let latestGuidanceAckRequired {
            lines.append("supervisor_memory_latest_guidance_ack_required=\(latestGuidanceAckRequired)")
        }
        if !latestGuidanceDeliveryMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("supervisor_memory_latest_guidance_delivery_mode=\(latestGuidanceDeliveryMode)")
        }
        if !latestGuidanceInterventionMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("supervisor_memory_latest_guidance_intervention_mode=\(latestGuidanceInterventionMode)")
        }
        if !latestGuidanceSafePointPolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("supervisor_memory_latest_guidance_safe_point_policy=\(latestGuidanceSafePointPolicy)")
        }
        lines.append("supervisor_memory_pending_ack_guidance_available=\(pendingAckGuidanceAvailable)")
        lines.append("supervisor_memory_pending_ack_guidance_actualized=\(pendingAckGuidanceActualized)")
        if !pendingAckGuidanceAckStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("supervisor_memory_pending_ack_guidance_ack_status=\(pendingAckGuidanceAckStatus)")
        }
        if let pendingAckGuidanceAckRequired {
            lines.append("supervisor_memory_pending_ack_guidance_ack_required=\(pendingAckGuidanceAckRequired)")
        }
        if !pendingAckGuidanceDeliveryMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("supervisor_memory_pending_ack_guidance_delivery_mode=\(pendingAckGuidanceDeliveryMode)")
        }
        if !pendingAckGuidanceInterventionMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("supervisor_memory_pending_ack_guidance_intervention_mode=\(pendingAckGuidanceInterventionMode)")
        }
        if !pendingAckGuidanceSafePointPolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("supervisor_memory_pending_ack_guidance_safe_point_policy=\(pendingAckGuidanceSafePointPolicy)")
        }
        if let guidanceContinuityHumanLine {
            lines.append(guidanceContinuityHumanLine)
        }
        if !servingObjectContract.isEmpty {
            lines.append(
                "supervisor_memory_serving_object_contract=\(servingObjectContract.joined(separator: ","))"
            )
        }
        if let supervisorMemoryPolicy {
            lines.append("supervisor_memory_policy_schema_version=\(supervisorMemoryPolicy.schemaVersion)")
            if let json = xtSupervisorMemoryCompactJSONString(supervisorMemoryPolicy) {
                lines.append("supervisor_memory_policy_json=\(json)")
            }
            if let auditRef = supervisorMemoryPolicy.auditRef,
               !auditRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("supervisor_memory_policy_audit_ref=\(auditRef)")
            }
        }
        if let memoryAssemblyResolution = actualizedMemoryAssemblyResolution {
            lines.append("supervisor_memory_resolution_schema_version=\(memoryAssemblyResolution.schemaVersion)")
            if let json = xtSupervisorMemoryCompactJSONString(memoryAssemblyResolution) {
                lines.append("supervisor_memory_assembly_resolution_json=\(json)")
            }
            if !memoryAssemblyResolution.selectedPlanes.isEmpty {
                lines.append(
                    "supervisor_memory_selected_planes=\(memoryAssemblyResolution.selectedPlanes.joined(separator: ","))"
                )
            }
            if !memoryAssemblyResolution.selectedSlots.isEmpty {
                lines.append(
                    "supervisor_memory_selected_slots=\(memoryAssemblyResolution.selectedSlots.joined(separator: ","))"
                )
            }
            if !memoryAssemblyResolution.selectedServingObjects.isEmpty {
                lines.append(
                    "supervisor_memory_selected_serving_objects=\(memoryAssemblyResolution.selectedServingObjects.joined(separator: ","))"
                )
            }
            if !memoryAssemblyResolution.excludedBlocks.isEmpty {
                lines.append(
                    "supervisor_memory_excluded_blocks=\(memoryAssemblyResolution.excludedBlocks.joined(separator: ","))"
                )
            }
            if let budgetSummary = memoryAssemblyResolution.budgetSummary,
               !budgetSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("supervisor_memory_budget_summary=\(budgetSummary)")
            }
            if let auditRef = memoryAssemblyResolution.auditRef,
               !auditRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("supervisor_memory_resolution_audit_ref=\(auditRef)")
            }
        }
        if let scopedPromptRecoveryHumanLine {
            lines.append("scoped_prompt_recovery: \(scopedPromptRecoveryHumanLine)")
        }
        if durableCandidateMirrorAttempted || durableCandidateMirrorStatus != .notNeeded {
            var mirrorLine = "durable_candidate_mirror status=\(durableCandidateMirrorStatus.rawValue)"
            if let durableCandidateMirrorTarget, !durableCandidateMirrorTarget.isEmpty {
                mirrorLine += " target=\(durableCandidateMirrorTarget)"
            }
            if let durableCandidateMirrorErrorCode, !durableCandidateMirrorErrorCode.isEmpty {
                mirrorLine += " reason=\(durableCandidateMirrorErrorCode)"
            }
            if !durableCandidateLocalStoreRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mirrorLine += " local_store_role=\(durableCandidateLocalStoreRole)"
            }
            lines.append(mirrorLine)
        }
        if let localStoreWriteLine {
            lines.append(localStoreWriteLine)
        }
        if let remotePromptBudgetDrillDownLine {
            lines.append(remotePromptBudgetDrillDownLine)
        }
        return lines
    }

    var remoteSnapshotCacheHumanLine: String? {
        let normalizedFreshness = freshness?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let freshnessLabel: String
        switch normalizedFreshness {
        case "ttl_cache":
            freshnessLabel = "remote snapshot TTL cache"
        case "fresh_remote":
            freshnessLabel = "remote snapshot fresh"
        case "fresh_remote_required":
            freshnessLabel = "remote snapshot fresh required"
        case "":
            freshnessLabel = cacheHit == true ? "remote snapshot TTL cache" : ""
        default:
            freshnessLabel = "remote snapshot \(normalizedFreshness)"
        }

        var parts: [String] = []
        if !freshnessLabel.isEmpty {
            parts.append(freshnessLabel)
        }
        if source == "hub_memory_v1_grpc" {
            switch normalizedFreshness {
            case "ttl_cache":
                parts.append("Hub truth via XT cache")
            case "fresh_remote":
                parts.append("Hub truth fresh fetch")
            case "":
                if cacheHit == true {
                    parts.append("Hub truth via XT cache")
                }
            default:
                break
            }
        }
        if let remoteSnapshotAgeMs {
            parts.append("age \(durationSummary(remoteSnapshotAgeMs))")
        }
        if let remoteSnapshotTTLRemainingMs {
            parts.append("ttl_left \(durationSummary(remoteSnapshotTTLRemainingMs))")
        }
        if let remoteSnapshotCacheScope,
           !remoteSnapshotCacheScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(remoteSnapshotCacheScope)
        }
        if let remoteSnapshotCachePosture,
           !remoteSnapshotCachePosture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("posture \(remoteSnapshotCachePosture)")
        }
        if let remoteSnapshotInvalidationReason,
           !remoteSnapshotInvalidationReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("last_invalidation \(remoteSnapshotInvalidationReason)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var remotePromptBudgetHumanLine: String? {
        guard let promptTokens = remotePromptTokenEstimate else { return nil }
        let variant = remotePromptVariantLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? remotePromptVariantLabel!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "full"
        let outputLimit = remoteResponseTokenLimit ?? max(0, (remoteTotalTokenEstimate ?? promptTokens) - promptTokens)
        let totalEstimate = remoteTotalTokenEstimate ?? (promptTokens + max(0, outputLimit))
        if let remoteSingleRequestBudget, remoteSingleRequestBudget > 0 {
            return "本轮远端 prompt：\(variant) 档 · 输入约 \(promptTokens) tokens · 输出上限 \(outputLimit) · 总量约 \(totalEstimate) · \(remoteBudgetSourceLabel) \(remoteSingleRequestBudget)"
        }
        return "本轮远端 prompt：\(variant) 档 · 输入约 \(promptTokens) tokens · 输出上限 \(outputLimit) · 总量约 \(totalEstimate)"
    }

    private var remotePromptBudgetSummaryLine: String? {
        guard let promptTokens = remotePromptTokenEstimate else { return nil }
        var parts: [String] = []
        if let remotePromptVariantLabel, !remotePromptVariantLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("prompt=\(remotePromptVariantLabel)")
        }
        if let remotePromptMode, !remotePromptMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("mode=\(remotePromptMode)")
        }
        parts.append("prompt_tokens=\(promptTokens)")
        if let remoteResponseTokenLimit {
            parts.append("output_limit=\(remoteResponseTokenLimit)")
        }
        if let remoteTotalTokenEstimate {
            parts.append("total_estimate=\(remoteTotalTokenEstimate)")
        }
        if let remoteSingleRequestBudget, remoteSingleRequestBudget > 0 {
            parts.append("single_request_budget=\(remoteSingleRequestBudget)")
        }
        if let remoteSingleRequestBudgetSource,
           !remoteSingleRequestBudgetSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("single_request_budget_source=\(remoteSingleRequestBudgetSource)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var remotePromptBudgetDrillDownLine: String? {
        guard let remotePromptBudgetSummaryLine else { return nil }
        return "remote_prompt \(remotePromptBudgetSummaryLine)"
    }

    private var localStoreWriteLine: String? {
        let parts = [
            localPersonalMemoryWriteIntent.map { "personal_memory=\($0)" },
            localCrossLinkWriteIntent.map { "cross_link=\($0)" },
            localPersonalReviewWriteIntent.map { "personal_review=\($0)" }
        ].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return "xt_local_store_writes " + parts.joined(separator: " ")
    }

    private var remoteBudgetSourceLabel: String {
        switch remoteSingleRequestBudgetSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "paired_device_truth":
            return "设备单次额度"
        case "paired_device_truth_and_model_context":
            return "设备单次额度 / 模型窗口"
        case "remote_model_context":
            return "模型窗口上限"
        case "default_fallback":
            return "默认回退额度"
        default:
            return "参考单次预算"
        }
    }

    private func durationSummary(_ milliseconds: Int) -> String {
        if milliseconds >= 60_000 {
            return "\(milliseconds / 60_000)m"
        }
        if milliseconds >= 1_000 {
            return "\(milliseconds / 1_000)s"
        }
        return "\(milliseconds)ms"
    }

    private func scopedPromptRecoveryModeLabel(_ raw: String) -> String {
        switch raw {
        case "explicit_hidden_project_focus":
            return "显式 hidden project 恢复"
        default:
            return fallbackHumanizedToken(raw)
        }
    }

    private func scopedPromptRecoverySectionLabel(_ raw: String) -> String {
        switch raw {
        case "l1_canonical.focused_project_anchor_pack":
            return "当前项目摘要"
        case "l2_observations.project_recent_events":
            return "观察层 recent events"
        case "l3_working_set.project_activity_memory":
            return "工作集项目活动"
        case "dialogue_window.project_recent_context":
            return "最近对话"
        default:
            return fallbackHumanizedToken(raw)
        }
    }

    private func governanceTriggerSourceLabel(_ raw: String) -> String {
        switch raw {
        case "user_turn":
            return "User Turn"
        case "heartbeat":
            return "Heartbeat"
        case "skill_callback":
            return "Skill Callback"
        case "official_skills_channel":
            return "Official Skills Channel"
        case "guidance_ack":
            return "Guidance Ack"
        case "automation_safe_point":
            return "Automation Safe Point"
        case "incident":
            return "Incident"
        case "external_trigger_ingress":
            return "External Trigger Ingress"
        case "grant_resolution":
            return "Grant Resolution"
        case "approval_resolution":
            return "Approval Resolution"
        default:
            return fallbackHumanizedToken(raw).capitalized
        }
    }

    private func governanceReviewTriggerLabel(_ raw: String) -> String {
        switch raw {
        case "periodic_heartbeat":
            return "Periodic Heartbeat"
        case "periodic_pulse":
            return "Periodic Pulse"
        case "failure_streak":
            return "Failure Streak"
        case "no_progress_window":
            return "No Progress Window"
        case "blocker_detected":
            return "Blocker Detected"
        case "plan_drift":
            return "Plan Drift"
        case "pre_high_risk_action":
            return "Pre High Risk Action"
        case "pre_done_summary":
            return "Pre Done Summary"
        case "manual_request":
            return "Manual Request"
        case "user_override":
            return "User Override"
        default:
            return fallbackHumanizedToken(raw).capitalized
        }
    }

    private func governanceReviewRunKindLabel(_ raw: String) -> String {
        switch raw {
        case "pulse":
            return "Pulse"
        case "brainstorm":
            return "Brainstorm"
        case "event_driven":
            return "Event Driven"
        case "manual":
            return "Manual"
        default:
            return fallbackHumanizedToken(raw).capitalized
        }
    }

    private func rawContextProfileLabel(_ raw: String?, fallback: String) -> String {
        let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let profile = XTSupervisorRecentRawContextProfile(rawValue: normalized) {
            return profile.displayName
        }
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedFallback.isEmpty ? "unknown" : trimmedFallback
    }

    private func reviewDepthProfileLabel(_ raw: String?, fallback: String) -> String {
        let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let profile = XTSupervisorReviewMemoryDepthProfile(rawValue: normalized) {
            return profile.displayName
        }
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedFallback.isEmpty ? "unknown" : trimmedFallback
    }

    private func servingProfileLabel(_ raw: String?, fallback: String) -> String {
        let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let servingProfile = XTMemoryServingProfile.parse(normalized) {
            return XTSupervisorReviewMemoryDepthProfile
                .from(servingProfile: servingProfile)
                .displayName
        }
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedFallback.isEmpty ? "unknown" : trimmedFallback
    }

    private func assemblyPurposeLabel(_ raw: String?, fallback: String) -> String {
        let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let purpose = XTSupervisorMemoryAssemblyPurpose(rawValue: normalized) {
            return purpose.displayName
        }
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedFallback.isEmpty ? "" : trimmedFallback
    }

    private func fallbackHumanizedToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "(none)" }
        return trimmed
            .replacingOccurrences(of: ".", with: " / ")
            .replacingOccurrences(of: "_", with: " ")
    }

    private func guidanceAckStateSummary(
        ackStatus: String,
        ackRequired: Bool?,
        safePointPolicy: String
    ) -> String {
        var parts: [String] = []
        let normalizedStatus = ackStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedStatus.isEmpty {
            parts.append("ack=\(normalizedStatus)")
        }
        if let ackRequired {
            parts.append(ackRequired ? "required" : "optional")
        }
        let normalizedSafePoint = safePointPolicy.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedSafePoint.isEmpty {
            parts.append("safe_point=\(normalizedSafePoint)")
        }
        guard !parts.isEmpty else { return "" }
        return " [" + parts.joined(separator: " · ") + "]"
    }
}

private let supervisorTrackedServingObjectsForExplainability: [String] = [
    "recent_raw_dialogue_window",
    "portfolio_brief",
    "focused_project_anchor_pack",
    "cross_link_refs",
    "longterm_outline",
    "delta_feed",
    "conflict_set",
    "context_refs",
    "evidence_pack",
]

private let supervisorExplainabilityObservablePlaneOrder: [String] = [
    "continuity_lane",
    "assistant_plane",
    "project_plane",
    "cross_link_plane",
]

private let supervisorProjectPlaneServingObjectsForExplainability: Set<String> = [
    "portfolio_brief",
    "focused_project_anchor_pack",
    "longterm_outline",
    "delta_feed",
    "conflict_set",
    "context_refs",
    "evidence_pack",
]

private func relevantSupervisorExplainabilityServingObjects(
    contract: [String]
) -> [String] {
    let mappedContract = xtOrderedUniqueSupervisorExplainabilityValues(
        contract.compactMap(supervisorExplainabilityServingObjectIdentifier(for:))
    )
    return mappedContract.isEmpty
        ? supervisorTrackedServingObjectsForExplainability
        : mappedContract
}

private func actualSupervisorServingObjects(
    from selectedSections: [String],
    fallback: [String]
) -> [String] {
    let mapped = xtOrderedUniqueSupervisorExplainabilityValues(
        selectedSections.compactMap(supervisorServingObjectIdentifier(forSection:))
    )
    return mapped.isEmpty
        ? xtOrderedUniqueSupervisorExplainabilityValues(fallback)
        : mapped
}

private func actualSupervisorSelectedPlanes(
    from servingObjects: [String],
    fallback: [String]
) -> [String] {
    let actualSet = Set(servingObjects)
    let fallbackPlanes = xtOrderedUniqueSupervisorExplainabilityValues(fallback)
    let fallbackPlaneSet = Set(fallbackPlanes)
    var selectedSet = Set<String>()

    if actualSet.contains("recent_raw_dialogue_window") {
        selectedSet.insert("continuity_lane")
    }
    // `assistant_plane` is injected outside `MEMORY_V1`; retain the resolver's
    // claim when present rather than pretending it is observable from sections.
    if fallbackPlaneSet.contains("assistant_plane") {
        selectedSet.insert("assistant_plane")
    }
    if !actualSet.isDisjoint(with: supervisorProjectPlaneServingObjectsForExplainability) {
        selectedSet.insert("project_plane")
    }
    if actualSet.contains("cross_link_refs") {
        selectedSet.insert("cross_link_plane")
    }

    let ordered = supervisorExplainabilityObservablePlaneOrder.filter { selectedSet.contains($0) }
    let extras = fallbackPlanes.filter {
        !selectedSet.contains($0) && !supervisorExplainabilityObservablePlaneOrder.contains($0)
    }
    return ordered + extras
}

private func supervisorExplainabilityServingObjectIdentifier(
    for token: String
) -> String? {
    if let sectionMapped = supervisorServingObjectIdentifier(forSection: token) {
        return sectionMapped
    }

    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard supervisorTrackedServingObjectsForExplainability.contains(trimmed) else {
        return nil
    }
    return trimmed
}

private func supervisorServingObjectIdentifier(
    forSection section: String
) -> String? {
    switch section {
    case "dialogue_window":
        return "recent_raw_dialogue_window"
    case "portfolio_brief",
         "focused_project_anchor_pack",
         "cross_link_refs",
         "longterm_outline",
         "delta_feed",
         "conflict_set",
         "context_refs",
         "evidence_pack":
        return section
    default:
        return nil
    }
}

private func supervisorServingObjectHumanLabel(
    _ raw: String
) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    switch trimmed {
    case "recent_raw_dialogue_window":
        return "最近对话"
    case "portfolio_brief":
        return "项目总览"
    case "focused_project_anchor_pack":
        return "当前项目摘要"
    case "cross_link_refs":
        return "关联线索"
    case "longterm_outline":
        return "长期轮廓"
    case "delta_feed":
        return "最近增量"
    case "conflict_set":
        return "冲突集"
    case "context_refs":
        return "关联引用"
    case "evidence_pack":
        return "执行证据"
    default:
        return trimmed
            .replacingOccurrences(of: ".", with: " / ")
            .replacingOccurrences(of: "_", with: " ")
    }
}

private func xtOrderedUniqueSupervisorExplainabilityValues(
    _ values: [String]
) -> [String] {
    var ordered: [String] = []
    var seen = Set<String>()
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              seen.insert(trimmed).inserted else { continue }
        ordered.append(trimmed)
    }
    return ordered
}
