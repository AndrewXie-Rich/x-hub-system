import Foundation

extension SupervisorManager {
    func supervisorMemoryAssemblySnapshot(
        from composition: SupervisorMemoryComposition,
        resolution: HubIPCClient.MemoryContextResolutionResult?,
        finalSource: String,
        finalText: String,
        updatedAt: TimeInterval
    ) -> SupervisorMemoryAssemblySnapshot {
        let response = resolution?.response
        let resolvedProfile = response?.resolvedProfile
            ?? resolution?.requestedProfile
            ?? composition.servingProfile.rawValue
        let attemptedProfiles = response?.attemptedProfiles
            ?? resolution?.attemptedProfiles
            ?? [composition.servingProfile.rawValue]
        let progressiveUpgradeCount = response?.progressiveUpgradeCount
            ?? max(0, attemptedProfiles.count - 1)
        let mirrorState = supervisorDurableCandidateMirrorSnapshotState(
            from: supervisorAfterTurnWritebackClassification
        )
        let finalSectionSelection = supervisorActualSectionSelection(
            in: finalText,
            contract: composition.servingObjectContract
        )
        let contextRefsSelectedCount = finalSectionSelection.selected.contains("context_refs")
            ? composition.contextRefsSelectedCount
            : 0
        let contextRefsOmittedCount = finalSectionSelection.selected.contains("context_refs")
            ? composition.contextRefsOmittedCount
            : (composition.contextRefsSelectedCount + composition.contextRefsOmittedCount)
        let evidenceItemsSelectedCount = finalSectionSelection.selected.contains("evidence_pack")
            ? composition.evidenceItemsSelectedCount
            : 0
        let evidenceItemsOmittedCount = finalSectionSelection.selected.contains("evidence_pack")
            ? composition.evidenceItemsOmittedCount
            : (composition.evidenceItemsSelectedCount + composition.evidenceItemsOmittedCount)
        return SupervisorMemoryAssemblySnapshot(
            source: finalSource,
            resolutionSource: resolution?.source,
            updatedAt: updatedAt,
            assemblyPurpose: composition.memoryPolicy.assemblyPurpose.rawValue,
            dominantMode: composition.dominantMode.rawValue,
            memoryResolutionTrigger: composition.memoryPolicy.trigger,
            triggerSource: composition.triggerSource.rawValue,
            governanceReviewTrigger: composition.governanceReviewTrigger?.rawValue ?? "",
            governanceReviewRunKind: composition.governanceReviewRunKind?.rawValue ?? "",
            reviewLevelHint: composition.reviewLevelHint.rawValue,
            requestedProfile: resolution?.requestedProfile ?? composition.servingProfile.rawValue,
            profileFloor: composition.profileFloor.rawValue,
            resolvedProfile: resolvedProfile,
            attemptedProfiles: attemptedProfiles,
            progressiveUpgradeCount: progressiveUpgradeCount,
            focusedProjectId: composition.focusedProjectId,
            configuredRawWindowProfile: composition.memoryPolicy.configuredSupervisorRecentRawContextProfile.rawValue,
            recommendedRawWindowProfile: composition.memoryPolicy.recommendedSupervisorRecentRawContextProfile.rawValue,
            effectiveRawWindowProfile: composition.memoryPolicy.effectiveSupervisorRecentRawContextProfile.rawValue,
            configuredReviewMemoryDepth: composition.memoryPolicy.configuredReviewMemoryDepth.rawValue,
            recommendedReviewMemoryDepth: composition.memoryPolicy.recommendedReviewMemoryDepth.rawValue,
            effectiveReviewMemoryDepth: composition.memoryPolicy.effectiveReviewMemoryDepth.rawValue,
            sTierReviewMemoryCeiling: composition.memoryPolicy.sTierReviewMemoryCeiling.rawValue,
            reviewMemoryCeilingHit: composition.memoryPolicy.ceilingHit,
            purposeScopedReviewMemoryCap: composition.memoryPolicy.purposeScopedReviewMemoryCap?.rawValue,
            purposeScopedReviewMemoryCapApplied: composition.memoryPolicy.purposeCapApplied,
            rawWindowProfile: composition.dialogueWindowProfile.rawValue,
            rawWindowFloorPairs: composition.dialogueWindowFloorPairs,
            rawWindowCeilingPairs: composition.dialogueWindowCeilingPairs,
            rawWindowSelectedPairs: composition.dialogueWindowSelectedPairs,
            eligibleMessages: composition.dialogueWindowEligibleMessages,
            lowSignalDroppedMessages: composition.dialogueWindowLowSignalDroppedMessages,
            rawWindowSource: composition.dialogueWindowSource,
            rollingDigestPresent: composition.rollingDialogueDigestPresent,
            continuityFloorSatisfied: composition.continuityFloorSatisfied,
            truncationAfterFloor: composition.continuityTruncationAfterFloor,
            continuityTraceLines: composition.dialogueWindowContinuityTraceLines,
            lowSignalDropSampleLines: composition.dialogueWindowLowSignalDropSampleLines,
            selectedSections: finalSectionSelection.selected,
            omittedSections: finalSectionSelection.omitted,
            servingObjectContract: composition.servingObjectContract,
            contextRefsSelected: contextRefsSelectedCount,
            contextRefsOmitted: contextRefsOmittedCount,
            evidenceItemsSelected: evidenceItemsSelectedCount,
            evidenceItemsOmitted: evidenceItemsOmittedCount,
            budgetTotalTokens: response?.budgetTotalTokens,
            usedTotalTokens: response?.usedTotalTokens,
            truncatedLayers: response?.truncatedLayers ?? [],
            freshness: response?.freshness ?? resolution?.freshness,
            cacheHit: response?.cacheHit ?? resolution?.cacheHit,
            remoteSnapshotCacheScope: response?.remoteSnapshotCacheScope ?? resolution?.remoteSnapshotCacheScope,
            remoteSnapshotCachedAtMs: response?.remoteSnapshotCachedAtMs ?? resolution?.remoteSnapshotCachedAtMs,
            remoteSnapshotAgeMs: response?.remoteSnapshotAgeMs ?? resolution?.remoteSnapshotAgeMs,
            remoteSnapshotTTLRemainingMs: response?.remoteSnapshotTTLRemainingMs ?? resolution?.remoteSnapshotTTLRemainingMs,
            remoteSnapshotCachePosture: response?.remoteSnapshotCachePosture ?? resolution?.remoteSnapshotCachePosture,
            remoteSnapshotInvalidationReason: response?.remoteSnapshotInvalidationReason ?? resolution?.remoteSnapshotInvalidationReason,
            denyCode: response?.denyCode ?? resolution?.denyCode,
            downgradeCode: response?.downgradeCode ?? resolution?.downgradeCode,
            reasonCode: resolution?.reasonCode,
            compressionPolicy: composition.compressionPolicy,
            durableCandidateMirrorStatus: mirrorState.status,
            durableCandidateMirrorTarget: mirrorState.target,
            durableCandidateMirrorAttempted: mirrorState.attempted,
            durableCandidateMirrorErrorCode: mirrorState.errorCode,
            durableCandidateLocalStoreRole: mirrorState.localStoreRole,
            localPersonalMemoryWriteIntent: supervisorPersonalMemoryStore.lastWriteObservation?.intent,
            localCrossLinkWriteIntent: supervisorCrossLinkStore.lastWriteObservation?.intent,
            localPersonalReviewWriteIntent: supervisorPersonalReviewStore.lastWriteObservation?.intent,
            latestReviewNoteAvailable: composition.latestReviewNoteAvailable,
            latestGuidanceAvailable: composition.latestGuidanceAvailable,
            latestGuidanceAckStatus: composition.latestGuidanceAckStatus,
            latestGuidanceAckRequired: composition.latestGuidanceAckRequired,
            latestGuidanceDeliveryMode: composition.latestGuidanceDeliveryMode,
            latestGuidanceInterventionMode: composition.latestGuidanceInterventionMode,
            latestGuidanceSafePointPolicy: composition.latestGuidanceSafePointPolicy,
            pendingAckGuidanceAvailable: composition.pendingAckGuidanceAvailable,
            pendingAckGuidanceAckStatus: composition.pendingAckGuidanceAckStatus,
            pendingAckGuidanceAckRequired: composition.pendingAckGuidanceAckRequired,
            pendingAckGuidanceDeliveryMode: composition.pendingAckGuidanceDeliveryMode,
            pendingAckGuidanceInterventionMode: composition.pendingAckGuidanceInterventionMode,
            pendingAckGuidanceSafePointPolicy: composition.pendingAckGuidanceSafePointPolicy,
            scopedPromptRecoveryMode: composition.scopedPromptRecoveryMode,
            scopedPromptRecoverySections: composition.scopedPromptRecoverySections,
            supervisorMemoryPolicy: composition.memoryPolicy.snapshot,
            memoryAssemblyResolution: composition.memoryPolicy.resolution
        )
    }
}
