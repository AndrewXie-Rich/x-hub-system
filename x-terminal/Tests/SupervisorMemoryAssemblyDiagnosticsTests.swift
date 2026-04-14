import Foundation
import Testing
@testable import XTerminal

struct SupervisorMemoryAssemblyDiagnosticsTests {

    @Test
    func evaluateFlagsMissingScopedRecoveryForExplicitHiddenProjectFocus() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
            requestedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
            profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
            resolvedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
            attemptedProfiles: [XTMemoryServingProfile.m3DeepDive.rawValue],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-hidden",
            rawWindowProfile: XTSupervisorRecentRawContextProfile.standard12Pairs.rawValue,
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 12,
            rawWindowSelectedPairs: 8,
            eligibleMessages: 16,
            lowSignalDroppedMessages: 0,
            rawWindowSource: "mixed",
            rollingDigestPresent: false,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [],
            lowSignalDropSampleLines: [],
            selectedSections: [
                "l1_canonical",
                "l2_observations",
                "l3_working_set",
                "dialogue_window"
            ],
            omittedSections: [],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 1,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 1200,
            usedTotalTokens: 640,
            truncatedLayers: [],
            freshness: "fresh_remote",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            scopedPromptRecoveryMode: "explicit_hidden_project_focus",
            scopedPromptRecoverySections: []
        )

        let readiness = SupervisorMemoryAssemblyDiagnostics.evaluate(
            snapshot: snapshot,
            canonicalSyncSnapshot: nil
        )

        #expect(readiness.ready == false)
        #expect(readiness.issueCodes.contains("memory_scoped_hidden_project_recovery_missing"))
        #expect(
            readiness.issues.contains(where: {
                $0.code == "memory_scoped_hidden_project_recovery_missing"
                    && $0.severity == .blocking
                    && $0.detail.contains("focus=project-hidden")
            })
        )
    }

    @Test
    func evaluateFlagsUnexpectedServingObjectsOutsideContract() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
            requestedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
            profileFloor: XTMemoryServingProfile.m2PlanReview.rawValue,
            resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
            attemptedProfiles: [XTMemoryServingProfile.m2PlanReview.rawValue],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            rawWindowProfile: XTSupervisorRecentRawContextProfile.standard12Pairs.rawValue,
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 12,
            rawWindowSelectedPairs: 8,
            eligibleMessages: 16,
            lowSignalDroppedMessages: 0,
            rawWindowSource: "mixed",
            rollingDigestPresent: false,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [],
            lowSignalDropSampleLines: [],
            selectedSections: [
                "dialogue_window",
                "focused_project_anchor_pack",
                "evidence_pack",
            ],
            omittedSections: [],
            servingObjectContract: [
                "dialogue_window",
                "focused_project_anchor_pack",
            ],
            contextRefsSelected: 0,
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
            compressionPolicy: "balanced"
        )

        let readiness = SupervisorMemoryAssemblyDiagnostics.evaluate(
            snapshot: snapshot,
            canonicalSyncSnapshot: nil
        )

        #expect(readiness.ready == false)
        #expect(readiness.issueCodes.contains("memory_unexpected_serving_object_included"))
        #expect(
            readiness.issues.contains(where: {
                $0.code == "memory_unexpected_serving_object_included"
                    && $0.severity == .blocking
                    && $0.detail.contains("unexpected_sections=evidence_pack")
            })
        )
    }

    @Test
    func evaluateFlagsResolutionProjectionDriftAgainstActualServedSections() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
            requestedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
            profileFloor: XTMemoryServingProfile.m2PlanReview.rawValue,
            resolvedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
            attemptedProfiles: [XTMemoryServingProfile.m3DeepDive.rawValue],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            rawWindowProfile: XTSupervisorRecentRawContextProfile.standard12Pairs.rawValue,
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 12,
            rawWindowSelectedPairs: 8,
            eligibleMessages: 16,
            lowSignalDroppedMessages: 0,
            rawWindowSource: "mixed",
            rollingDigestPresent: false,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [],
            lowSignalDropSampleLines: [],
            selectedSections: [
                "dialogue_window",
                "focused_project_anchor_pack",
                "cross_link_refs",
            ],
            omittedSections: ["evidence_pack"],
            servingObjectContract: [
                "dialogue_window",
                "focused_project_anchor_pack",
                "cross_link_refs",
                "evidence_pack",
            ],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 1,
            budgetTotalTokens: 1200,
            usedTotalTokens: 640,
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
                trigger: "heartbeat_no_progress_review",
                configuredDepth: XTSupervisorReviewMemoryDepthProfile.auto.rawValue,
                recommendedDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
                effectiveDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
                ceilingFromTier: XTMemoryServingProfile.m3DeepDive.rawValue,
                ceilingHit: false,
                selectedSlots: [
                    "recent_raw_dialogue_window",
                    "focused_project_anchor_pack",
                    "delta_feed",
                    "evidence_pack",
                ],
                selectedPlanes: ["continuity_lane", "project_plane", "cross_link_plane"],
                selectedServingObjects: [
                    "recent_raw_dialogue_window",
                    "focused_project_anchor_pack",
                    "delta_feed",
                    "evidence_pack",
                ],
                excludedBlocks: []
            )
        )

        let readiness = SupervisorMemoryAssemblyDiagnostics.evaluate(
            snapshot: snapshot,
            canonicalSyncSnapshot: nil
        )

        #expect(readiness.ready == false)
        #expect(readiness.issueCodes.contains("memory_resolution_projection_drift"))
        #expect(
            readiness.issues.contains(where: {
                $0.code == "memory_resolution_projection_drift"
                    && $0.severity == .warning
                    && $0.detail.contains("policy_selected_planes=continuity_lane,project_plane,cross_link_plane")
                    && $0.detail.contains("actual_selected_planes=continuity_lane,project_plane,cross_link_plane")
                    && $0.detail.contains("policy_selected_serving_objects=recent_raw_dialogue_window,focused_project_anchor_pack,delta_feed,evidence_pack")
                    && $0.detail.contains("actual_selected_serving_objects=recent_raw_dialogue_window,focused_project_anchor_pack,cross_link_refs")
                    && $0.detail.contains("actual_excluded_blocks=evidence_pack")
            })
        )
    }

    @Test
    func evaluateFlagsPendingGuidanceAckWhenContinuityCarrierIsMissing() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
            requestedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
            profileFloor: XTMemoryServingProfile.m2PlanReview.rawValue,
            resolvedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
            attemptedProfiles: [XTMemoryServingProfile.m3DeepDive.rawValue],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            rawWindowProfile: XTSupervisorRecentRawContextProfile.standard12Pairs.rawValue,
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 12,
            rawWindowSelectedPairs: 8,
            eligibleMessages: 16,
            lowSignalDroppedMessages: 0,
            rawWindowSource: "mixed",
            rollingDigestPresent: false,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [],
            lowSignalDropSampleLines: [],
            selectedSections: [
                "dialogue_window",
                "delta_feed"
            ],
            omittedSections: [
                "focused_project_anchor_pack",
                "context_refs",
                "evidence_pack"
            ],
            contextRefsSelected: 0,
            contextRefsOmitted: 1,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 1,
            budgetTotalTokens: 700,
            usedTotalTokens: 260,
            truncatedLayers: [],
            freshness: "fresh",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            pendingAckGuidanceAvailable: true,
            pendingAckGuidanceAckStatus: SupervisorGuidanceAckStatus.pending.rawValue,
            pendingAckGuidanceAckRequired: true,
            pendingAckGuidanceDeliveryMode: SupervisorGuidanceDeliveryMode.replanRequest.rawValue,
            pendingAckGuidanceInterventionMode: SupervisorGuidanceInterventionMode.replanNextSafePoint.rawValue,
            pendingAckGuidanceSafePointPolicy: SupervisorGuidanceSafePointPolicy.nextStepBoundary.rawValue
        )

        let readiness = SupervisorMemoryAssemblyDiagnostics.evaluate(
            snapshot: snapshot,
            canonicalSyncSnapshot: nil
        )

        #expect(readiness.ready == false)
        #expect(readiness.issueCodes.contains("memory_pending_guidance_ack_not_carried_forward"))
        #expect(
            readiness.issues.contains(where: {
                $0.code == "memory_pending_guidance_ack_not_carried_forward"
                    && $0.severity == .blocking
                    && $0.detail.contains("carrier_present=false")
                    && $0.detail.contains("ack_status=pending")
                    && $0.detail.contains("safe_point=next_step_boundary")
            })
        )
    }

    @Test
    func evaluateFlagsResolutionProjectionDriftWhenObservablePlanesDisappear() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: SupervisorReviewLevel.r1Pulse.rawValue,
            requestedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
            profileFloor: XTMemoryServingProfile.m1Execute.rawValue,
            resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
            attemptedProfiles: [XTMemoryServingProfile.m2PlanReview.rawValue],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            rawWindowProfile: XTSupervisorRecentRawContextProfile.standard12Pairs.rawValue,
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 12,
            rawWindowSelectedPairs: 8,
            eligibleMessages: 16,
            lowSignalDroppedMessages: 0,
            rawWindowSource: "mixed",
            rollingDigestPresent: false,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [],
            lowSignalDropSampleLines: [],
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
            usedTotalTokens: 160,
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

        let readiness = SupervisorMemoryAssemblyDiagnostics.evaluate(
            snapshot: snapshot,
            canonicalSyncSnapshot: nil
        )

        #expect(readiness.ready == false)
        #expect(readiness.issueCodes.contains("memory_resolution_projection_drift"))
        #expect(
            readiness.issues.contains(where: {
                $0.code == "memory_resolution_projection_drift"
                    && $0.detail.contains("policy_selected_planes=continuity_lane,assistant_plane,project_plane,cross_link_plane")
                    && $0.detail.contains("actual_selected_planes=continuity_lane,assistant_plane")
            })
        )
    }
}
