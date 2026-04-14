import Foundation
import Testing
@testable import XTerminal

struct SupervisorMemoryAssemblySnapshotTests {

    @Test
    func compactSummarySeparatesReviewDepthTruthFromSTierCeiling() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub_memory",
            updatedAt: 1,
            assemblyPurpose: XTSupervisorMemoryAssemblyPurpose.governanceReview.rawValue,
            reviewLevelHint: "r2_strategic",
            requestedProfile: "balanced",
            profileFloor: "balanced",
            resolvedProfile: "balanced",
            attemptedProfiles: ["balanced"],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            configuredRawWindowProfile: XTSupervisorRecentRawContextProfile.deep20Pairs.rawValue,
            recommendedRawWindowProfile: XTSupervisorRecentRawContextProfile.extended40Pairs.rawValue,
            effectiveRawWindowProfile: XTSupervisorRecentRawContextProfile.extended40Pairs.rawValue,
            configuredReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile.fullScan.rawValue,
            recommendedReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
            effectiveReviewMemoryDepth: XTSupervisorReviewMemoryDepthProfile.planReview.rawValue,
            sTierReviewMemoryCeiling: XTMemoryServingProfile.m2PlanReview.rawValue,
            reviewMemoryCeilingHit: true,
            purposeScopedReviewMemoryCap: XTMemoryServingProfile.m2PlanReview.rawValue,
            purposeScopedReviewMemoryCapApplied: true,
            rawWindowProfile: XTSupervisorRecentRawContextProfile.extended40Pairs.rawValue,
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 40,
            rawWindowSelectedPairs: 18,
            eligibleMessages: 26,
            lowSignalDroppedMessages: 2,
            rawWindowSource: "xt_cache",
            rollingDigestPresent: true,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [],
            lowSignalDropSampleLines: [],
            selectedSections: ["l1_canonical", "l3_working_set"],
            omittedSections: [],
            servingObjectContract: [
                "dialogue_window",
                "focused_project_anchor_pack",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack",
            ],
            contextRefsSelected: 2,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 1,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 1200,
            usedTotalTokens: 640,
            truncatedLayers: [],
            freshness: "fresh",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            supervisorMemoryPolicy: XTSupervisorMemoryPolicySnapshot(
                configuredSupervisorRecentRawContextProfile: .deep20Pairs,
                configuredReviewMemoryDepth: .fullScan,
                recommendedSupervisorRecentRawContextProfile: .extended40Pairs,
                recommendedReviewMemoryDepth: .deepDive,
                effectiveSupervisorRecentRawContextProfile: .extended40Pairs,
                effectiveReviewMemoryDepth: .planReview,
                sTierReviewMemoryCeiling: .m2PlanReview
            ),
            memoryAssemblyResolution: XTMemoryAssemblyResolution(
                role: .supervisor,
                dominantMode: SupervisorTurnMode.projectFirst.rawValue,
                trigger: "heartbeat_no_progress_review",
                configuredDepth: XTSupervisorReviewMemoryDepthProfile.fullScan.rawValue,
                recommendedDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
                effectiveDepth: XTSupervisorReviewMemoryDepthProfile.planReview.rawValue,
                ceilingFromTier: XTMemoryServingProfile.m2PlanReview.rawValue,
                ceilingHit: true,
                selectedSlots: [
                    "recent_raw_dialogue_window",
                    "focused_project_anchor_pack",
                    "delta_feed",
                    "conflict_set",
                    "context_refs",
                    "evidence_pack",
                ],
                selectedPlanes: ["continuity_lane", "project_plane", "cross_link_plane"],
                selectedServingObjects: [
                    "recent_raw_dialogue_window",
                    "focused_project_anchor_pack",
                    "delta_feed",
                    "conflict_set",
                    "context_refs",
                    "evidence_pack",
                ],
                excludedBlocks: []
            )
        )

        let summary = snapshot.compactSummary
        let detailLines = snapshot.continuityDrillDownLines

        #expect(summary.headlineText == "Review Memory · Plan Review / ceiling Plan Review")
        #expect(summary.detailText?.contains("Recent Raw Context Extended") == true)
        #expect(summary.detailText?.contains("18 pairs") == true)
        #expect(summary.detailText?.contains("configured/recommended Full Scan/Deep Dive") == true)
        #expect(summary.detailText?.contains("purpose Governance Review") == true)
        #expect(summary.detailText?.contains("purpose cap Plan Review") == true)
        #expect(summary.detailText?.contains("ceiling hit") == true)
        #expect(summary.detailText?.contains("focus project-alpha") == true)
        #expect(summary.helpText.contains("S-Tier 只提供 Supervisor 的 review-memory ceiling"))
        #expect(summary.helpText.contains("Recent Raw Context 和 Review Memory Depth"))
        #expect(
            detailLines.contains(where: {
                $0.hasPrefix("supervisor_memory_policy_json=")
                    && $0.contains("\"schema_version\":\"xhub.supervisor_memory_policy.v1\"")
            })
        )
        #expect(detailLines.contains("supervisor_memory_selected_planes=continuity_lane,project_plane"))
        #expect(detailLines.contains("supervisor_memory_selected_serving_objects=recent_raw_dialogue_window,focused_project_anchor_pack,delta_feed,conflict_set,context_refs,evidence_pack"))
        #expect(detailLines.contains("supervisor_memory_serving_object_contract=dialogue_window,focused_project_anchor_pack,delta_feed,conflict_set,context_refs,evidence_pack"))
    }

    @Test
    func remoteSnapshotCacheProvenanceAppearsInCompactSummaryAndDrilldown() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub_memory",
            updatedAt: 1,
            reviewLevelHint: "r2_strategic",
            requestedProfile: "balanced",
            profileFloor: "balanced",
            resolvedProfile: "balanced",
            attemptedProfiles: ["balanced"],
            progressiveUpgradeCount: 0,
            selectedSections: ["l1_canonical"],
            omittedSections: [],
            contextRefsSelected: 0,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 600,
            usedTotalTokens: 240,
            truncatedLayers: [],
            freshness: "ttl_cache",
            cacheHit: true,
            remoteSnapshotCacheScope: "mode=supervisor_orchestration project_id=(none)",
            remoteSnapshotCachedAtMs: 1_774_000_000_000,
            remoteSnapshotAgeMs: 6_000,
            remoteSnapshotTTLRemainingMs: 9_000,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced"
        )

        #expect(snapshot.compactSummary.helpText.contains("remote snapshot TTL cache"))
        #expect(snapshot.compactSummary.helpText.contains("age 6s"))
        #expect(snapshot.detailLine.contains("ttl_left 9s"))
        #expect(snapshot.continuityDrillDownLines.contains("remote_snapshot_cache_scope=mode=supervisor_orchestration project_id=(none)"))
        #expect(snapshot.continuityDrillDownLines.contains("remote_snapshot_age_ms=6000"))
        #expect(snapshot.continuityDrillDownLines.contains("remote_snapshot_ttl_remaining_ms=9000"))
    }

    @Test
    func guidanceContinuityAppearsInDetailLineAndDrilldown() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub_memory",
            updatedAt: 1,
            reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
            requestedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
            profileFloor: XTMemoryServingProfile.m2PlanReview.rawValue,
            resolvedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
            attemptedProfiles: [XTMemoryServingProfile.m3DeepDive.rawValue],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            selectedSections: ["dialogue_window", "focused_project_anchor_pack", "context_refs"],
            omittedSections: [],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 900,
            usedTotalTokens: 420,
            truncatedLayers: [],
            freshness: "fresh",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            latestReviewNoteAvailable: true,
            latestGuidanceAvailable: true,
            latestGuidanceAckStatus: SupervisorGuidanceAckStatus.deferred.rawValue,
            latestGuidanceAckRequired: true,
            latestGuidanceSafePointPolicy: SupervisorGuidanceSafePointPolicy.nextStepBoundary.rawValue,
            pendingAckGuidanceAvailable: true,
            pendingAckGuidanceAckStatus: SupervisorGuidanceAckStatus.pending.rawValue,
            pendingAckGuidanceAckRequired: true,
            pendingAckGuidanceSafePointPolicy: SupervisorGuidanceSafePointPolicy.nextStepBoundary.rawValue
        )

        #expect(snapshot.reviewGuidanceCarrierPresent)
        #expect(snapshot.latestReviewNoteActualized)
        #expect(snapshot.latestGuidanceActualized)
        #expect(snapshot.pendingAckGuidanceActualized)
        #expect(snapshot.detailLine.contains("Review / Guidance：latest review carried"))
        #expect(snapshot.detailLine.contains("pending guidance carried [ack=pending"))
        #expect(snapshot.guidanceContinuityRenderedRefs == [
            "latest_review_note",
            "latest_guidance",
            "pending_ack_guidance"
        ])
        #expect(snapshot.continuityDrillDownLines.contains("supervisor_memory_latest_review_note_actualized=true"))
        #expect(snapshot.continuityDrillDownLines.contains("supervisor_memory_latest_guidance_ack_status=deferred"))
        #expect(snapshot.continuityDrillDownLines.contains("supervisor_memory_pending_ack_guidance_ack_status=pending"))
    }

    @Test
    func actualizedMemoryAssemblyResolutionTracksFinalSelectedSections() throws {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub_memory",
            updatedAt: 1,
            reviewLevelHint: "r2_strategic",
            requestedProfile: "m3_deep_dive",
            profileFloor: "m2_plan_review",
            resolvedProfile: "m3_deep_dive",
            attemptedProfiles: ["m3_deep_dive"],
            progressiveUpgradeCount: 0,
            selectedSections: [
                "dialogue_window",
                "portfolio_brief",
                "focused_project_anchor_pack",
                "cross_link_refs",
                "delta_feed",
                "context_refs"
            ],
            omittedSections: ["conflict_set", "evidence_pack"],
            servingObjectContract: [
                "dialogue_window",
                "portfolio_brief",
                "focused_project_anchor_pack",
                "cross_link_refs",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack"
            ],
            contextRefsSelected: 2,
            contextRefsOmitted: 1,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 2,
            budgetTotalTokens: 900,
            usedTotalTokens: 520,
            truncatedLayers: ["evidence_pack"],
            freshness: "fresh",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            memoryAssemblyResolution: XTMemoryAssemblyResolution(
                role: .supervisor,
                dominantMode: SupervisorTurnMode.hybrid.rawValue,
                trigger: "heartbeat_no_progress_review",
                configuredDepth: XTSupervisorReviewMemoryDepthProfile.auto.rawValue,
                recommendedDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
                effectiveDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
                ceilingFromTier: XTMemoryServingProfile.m3DeepDive.rawValue,
                ceilingHit: false,
                selectedSlots: [
                    "recent_raw_dialogue_window",
                    "portfolio_brief",
                    "focused_project_anchor_pack",
                    "delta_feed",
                    "conflict_set",
                    "context_refs",
                    "evidence_pack",
                ],
                selectedPlanes: ["continuity_lane", "assistant_plane", "project_plane", "cross_link_plane"],
                selectedServingObjects: [
                    "recent_raw_dialogue_window",
                    "portfolio_brief",
                    "focused_project_anchor_pack",
                    "delta_feed",
                    "conflict_set",
                    "context_refs",
                    "evidence_pack",
                ],
                excludedBlocks: []
            )
        )

        let resolution = try #require(snapshot.actualizedMemoryAssemblyResolution)

        #expect(resolution.selectedServingObjects == [
            "recent_raw_dialogue_window",
            "portfolio_brief",
            "focused_project_anchor_pack",
            "cross_link_refs",
            "delta_feed",
            "context_refs",
        ])
        #expect(resolution.selectedSlots == [
            "recent_raw_dialogue_window",
            "portfolio_brief",
            "focused_project_anchor_pack",
            "cross_link_refs",
            "delta_feed",
            "context_refs",
        ])
        #expect(resolution.selectedPlanes == [
            "continuity_lane",
            "assistant_plane",
            "project_plane",
            "cross_link_plane",
        ])
        #expect(resolution.excludedBlocks.contains("conflict_set"))
        #expect(resolution.excludedBlocks.contains("evidence_pack"))
        #expect(snapshot.continuityDrillDownLines.contains(
            "supervisor_memory_selected_serving_objects=recent_raw_dialogue_window,portfolio_brief,focused_project_anchor_pack,cross_link_refs,delta_feed,context_refs"
        ))
        #expect(snapshot.continuityDrillDownLines.contains(
            "supervisor_memory_excluded_blocks=conflict_set,evidence_pack"
        ))
    }

    @Test
    func actualizedMemoryAssemblyResolutionScopesExcludedBlocksToServingContract() throws {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub_memory",
            updatedAt: 1,
            reviewLevelHint: "r2_strategic",
            requestedProfile: "m2_plan_review",
            profileFloor: "m1_execute",
            resolvedProfile: "m2_plan_review",
            attemptedProfiles: ["m2_plan_review"],
            progressiveUpgradeCount: 0,
            selectedSections: [
                "dialogue_window",
                "focused_project_anchor_pack"
            ],
            omittedSections: ["delta_feed"],
            servingObjectContract: [
                "dialogue_window",
                "focused_project_anchor_pack",
                "delta_feed"
            ],
            contextRefsSelected: 0,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 400,
            usedTotalTokens: 180,
            truncatedLayers: [],
            freshness: "fresh",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            memoryAssemblyResolution: XTMemoryAssemblyResolution(
                role: .supervisor,
                dominantMode: SupervisorTurnMode.projectFirst.rawValue,
                trigger: "heartbeat_periodic_pulse_review",
                configuredDepth: XTSupervisorReviewMemoryDepthProfile.auto.rawValue,
                recommendedDepth: XTSupervisorReviewMemoryDepthProfile.planReview.rawValue,
                effectiveDepth: XTSupervisorReviewMemoryDepthProfile.planReview.rawValue,
                ceilingFromTier: XTMemoryServingProfile.m2PlanReview.rawValue,
                ceilingHit: false,
                selectedSlots: [
                    "recent_raw_dialogue_window",
                    "focused_project_anchor_pack",
                    "delta_feed",
                    "conflict_set",
                ],
                selectedPlanes: ["continuity_lane", "project_plane"],
                selectedServingObjects: [
                    "recent_raw_dialogue_window",
                    "focused_project_anchor_pack",
                    "delta_feed",
                    "conflict_set",
                ],
                excludedBlocks: []
            )
        )

        let resolution = try #require(snapshot.actualizedMemoryAssemblyResolution)

        #expect(resolution.selectedServingObjects == [
            "recent_raw_dialogue_window",
            "focused_project_anchor_pack",
        ])
        #expect(resolution.selectedPlanes == [
            "continuity_lane",
            "project_plane",
        ])
        #expect(resolution.excludedBlocks == ["delta_feed"])
        #expect(snapshot.continuityDrillDownLines.contains(
            "supervisor_memory_excluded_blocks=delta_feed"
        ))
    }

    @Test
    func actualizedMemoryAssemblyResolutionDropsUnservedObservablePlanesButKeepsAssistantPlane() throws {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub_memory",
            updatedAt: 1,
            reviewLevelHint: "r1_pulse",
            requestedProfile: "m2_plan_review",
            profileFloor: "m1_execute",
            resolvedProfile: "m2_plan_review",
            attemptedProfiles: ["m2_plan_review"],
            progressiveUpgradeCount: 0,
            selectedSections: [
                "dialogue_window"
            ],
            omittedSections: [
                "focused_project_anchor_pack",
                "cross_link_refs",
            ],
            servingObjectContract: [
                "dialogue_window",
                "focused_project_anchor_pack",
                "cross_link_refs",
            ],
            contextRefsSelected: 0,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 320,
            usedTotalTokens: 180,
            truncatedLayers: [],
            freshness: "fresh",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            memoryAssemblyResolution: XTMemoryAssemblyResolution(
                role: .supervisor,
                dominantMode: SupervisorTurnMode.hybrid.rawValue,
                trigger: "user_turn",
                configuredDepth: XTSupervisorReviewMemoryDepthProfile.auto.rawValue,
                recommendedDepth: XTSupervisorReviewMemoryDepthProfile.compact.rawValue,
                effectiveDepth: XTSupervisorReviewMemoryDepthProfile.planReview.rawValue,
                ceilingFromTier: XTMemoryServingProfile.m2PlanReview.rawValue,
                ceilingHit: false,
                selectedSlots: [
                    "recent_raw_dialogue_window",
                    "focused_project_anchor_pack",
                    "cross_link_refs",
                ],
                selectedPlanes: [
                    "continuity_lane",
                    "assistant_plane",
                    "project_plane",
                    "cross_link_plane",
                ],
                selectedServingObjects: [
                    "recent_raw_dialogue_window",
                    "focused_project_anchor_pack",
                    "cross_link_refs",
                ],
                excludedBlocks: []
            )
        )

        let resolution = try #require(snapshot.actualizedMemoryAssemblyResolution)

        #expect(resolution.selectedPlanes == [
            "continuity_lane",
            "assistant_plane",
        ])
    }
}
