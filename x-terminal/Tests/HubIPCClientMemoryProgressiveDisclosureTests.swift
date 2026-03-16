import Foundation
import Testing
@testable import XTerminal

actor MemoryProfileAttemptRecorder {
    private var profiles: [String] = []

    func append(_ profile: String) {
        profiles.append(profile)
    }

    func snapshot() -> [String] {
        profiles
    }
}

@Suite(.serialized)
struct HubIPCClientMemoryProgressiveDisclosureTests {

    @Test
    func progressiveDisclosureEscalatesReviewRequestFromM1ToM2WhenInitialStageIsTight() async throws {
        let recorder = MemoryProfileAttemptRecorder()
        HubIPCClient.installMemoryContextResolutionOverrideForTesting { route, mode, _ in
            await recorder.append(route.servingProfile.rawValue)
            return Self.resolutionResult(
                mode: mode,
                profile: route.servingProfile,
                usedTokens: route.servingProfile == .m1Execute ? 1_420 : 980,
                budgetTokens: route.servingProfile == .m1Execute ? 1_600 : 2_880,
                truncatedLayers: route.servingProfile == .m1Execute ? ["l1_canonical"] : []
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let result = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .projectChat,
            requesterRole: .chat,
            projectId: "proj-review",
            projectRoot: "/tmp/proj-review",
            displayName: "proj-review",
            latestUser: "梳理项目结构并给出重构建议",
            constitutionHint: "safe",
            canonicalText: "canonical",
            observationsText: "observations",
            workingSetText: "working",
            rawEvidenceText: "raw",
            progressiveDisclosure: true,
            budgets: nil,
            timeoutSec: 0.1
        )

        let response = try #require(result.response)
        #expect(result.requestedProfile == XTMemoryServingProfile.m2PlanReview.rawValue)
        #expect(result.attemptedProfiles == [
            XTMemoryServingProfile.m1Execute.rawValue,
            XTMemoryServingProfile.m2PlanReview.rawValue
        ])
        #expect(response.requestedProfile == XTMemoryServingProfile.m2PlanReview.rawValue)
        #expect(response.resolvedProfile == XTMemoryServingProfile.m2PlanReview.rawValue)
        #expect(response.attemptedProfiles == [
            XTMemoryServingProfile.m1Execute.rawValue,
            XTMemoryServingProfile.m2PlanReview.rawValue
        ])
        #expect(response.progressiveUpgradeCount == 1)
        #expect(await recorder.snapshot() == [
            XTMemoryServingProfile.m1Execute.rawValue,
            XTMemoryServingProfile.m2PlanReview.rawValue
        ])
    }

    @Test
    func progressiveDisclosureStopsAtM2WhenDeepDiveRequestNoLongerNeedsM3() async throws {
        let recorder = MemoryProfileAttemptRecorder()
        HubIPCClient.installMemoryContextResolutionOverrideForTesting { route, mode, _ in
            await recorder.append(route.servingProfile.rawValue)
            switch route.servingProfile {
            case .m1Execute:
                return Self.resolutionResult(
                    mode: mode,
                    profile: route.servingProfile,
                    usedTokens: 1_360,
                    budgetTokens: 1_600,
                    truncatedLayers: ["l2_observations"]
                )
            case .m2PlanReview:
                return Self.resolutionResult(
                    mode: mode,
                    profile: route.servingProfile,
                    usedTokens: 1_120,
                    budgetTokens: 2_880,
                    truncatedLayers: []
                )
            default:
                return Self.resolutionResult(
                    mode: mode,
                    profile: route.servingProfile,
                    usedTokens: 1_050,
                    budgetTokens: 4_480,
                    truncatedLayers: []
                )
            }
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let result = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .projectChat,
            requesterRole: .chat,
            projectId: "proj-deep-dive",
            projectRoot: "/tmp/proj-deep-dive",
            displayName: "proj-deep-dive",
            latestUser: "先完整通读整个仓库，再给我架构重构路径",
            constitutionHint: "safe",
            canonicalText: "canonical",
            observationsText: "observations",
            workingSetText: "working",
            rawEvidenceText: "raw",
            progressiveDisclosure: true,
            budgets: nil,
            timeoutSec: 0.1
        )

        let response = try #require(result.response)
        #expect(result.requestedProfile == XTMemoryServingProfile.m3DeepDive.rawValue)
        #expect(result.attemptedProfiles == [
            XTMemoryServingProfile.m1Execute.rawValue,
            XTMemoryServingProfile.m2PlanReview.rawValue
        ])
        #expect(response.requestedProfile == XTMemoryServingProfile.m3DeepDive.rawValue)
        #expect(response.resolvedProfile == XTMemoryServingProfile.m2PlanReview.rawValue)
        #expect(response.attemptedProfiles == [
            XTMemoryServingProfile.m1Execute.rawValue,
            XTMemoryServingProfile.m2PlanReview.rawValue
        ])
        #expect(response.progressiveUpgradeCount == 1)
        #expect(await recorder.snapshot() == [
            XTMemoryServingProfile.m1Execute.rawValue,
            XTMemoryServingProfile.m2PlanReview.rawValue
        ])
    }

    @Test
    func focusedSupervisorStrategicReviewDoesNotStartBelowM3Floor() async throws {
        let recorder = MemoryProfileAttemptRecorder()
        HubIPCClient.installMemoryContextResolutionOverrideForTesting { route, mode, _ in
            await recorder.append(route.servingProfile.rawValue)
            return Self.resolutionResult(
                mode: mode,
                profile: route.servingProfile,
                usedTokens: 920,
                budgetTokens: 2_880,
                truncatedLayers: []
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let result = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .supervisorOrchestration,
            requesterRole: .supervisor,
            projectId: nil,
            projectRoot: nil,
            displayName: "Supervisor",
            latestUser: "审查当前项目的上下文记忆，给出最具体的执行方案",
            reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
            constitutionHint: "safe",
            portfolioBriefText: "portfolio",
            focusedProjectAnchorPackText: "project: proj-1 (proj-1)\ngoal: keep strategic alignment",
            longtermOutlineText: "longterm",
            deltaFeedText: "delta",
            conflictSetText: "conflict",
            contextRefsText: "refs",
            evidencePackText: "evidence",
            canonicalText: "canonical",
            observationsText: "observations",
            workingSetText: "working",
            rawEvidenceText: "raw",
            servingProfile: .m3DeepDive,
            progressiveDisclosure: true,
            budgets: nil,
            timeoutSec: 0.1
        )

        let response = try #require(result.response)
        #expect(result.requestedProfile == XTMemoryServingProfile.m3DeepDive.rawValue)
        #expect(result.attemptedProfiles == [XTMemoryServingProfile.m3DeepDive.rawValue])
        #expect(response.resolvedProfile == XTMemoryServingProfile.m3DeepDive.rawValue)
        #expect(response.attemptedProfiles == [XTMemoryServingProfile.m3DeepDive.rawValue])
        #expect(await recorder.snapshot() == [XTMemoryServingProfile.m3DeepDive.rawValue])
    }

    @Test
    func unfocusedSupervisorStrategicReviewStartsAtM2Floor() async throws {
        let recorder = MemoryProfileAttemptRecorder()
        HubIPCClient.installMemoryContextResolutionOverrideForTesting { route, mode, _ in
            await recorder.append(route.servingProfile.rawValue)
            return Self.resolutionResult(
                mode: mode,
                profile: route.servingProfile,
                usedTokens: 920,
                budgetTokens: 2_880,
                truncatedLayers: []
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let result = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .supervisorOrchestration,
            requesterRole: .supervisor,
            projectId: nil,
            projectRoot: nil,
            displayName: "Supervisor",
            latestUser: "审查当前项目的上下文记忆，给出最具体的执行方案",
            reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
            constitutionHint: "safe",
            portfolioBriefText: "portfolio",
            focusedProjectAnchorPackText: "",
            longtermOutlineText: "longterm",
            deltaFeedText: "delta",
            conflictSetText: "conflict",
            contextRefsText: "refs",
            evidencePackText: "",
            canonicalText: "canonical",
            observationsText: "observations",
            workingSetText: "working",
            rawEvidenceText: "raw",
            servingProfile: .m2PlanReview,
            progressiveDisclosure: true,
            budgets: nil,
            timeoutSec: 0.1
        )

        let response = try #require(result.response)
        #expect(result.requestedProfile == XTMemoryServingProfile.m2PlanReview.rawValue)
        #expect(result.attemptedProfiles == [XTMemoryServingProfile.m2PlanReview.rawValue])
        #expect(response.resolvedProfile == XTMemoryServingProfile.m2PlanReview.rawValue)
        #expect(response.attemptedProfiles == [XTMemoryServingProfile.m2PlanReview.rawValue])
        #expect(await recorder.snapshot() == [XTMemoryServingProfile.m2PlanReview.rawValue])
    }

    @Test
    func projectChatLongtermDisclosureReplacesLegacySummaryBlockWithProgressiveRules() {
        let disclosure = HubIPCClient.resolveMemoryLongtermDisclosure(
            useMode: .projectChat,
            retrievalAvailable: true
        )
        let rendered = HubIPCClient.ensureMemoryLongtermDisclosureText(
            """
            [MEMORY_V1]
            [LONGTERM_MEMORY]
            longterm_mode=summary_only
            retrieval_available=false
            fulltext_not_loaded=true
            [/LONGTERM_MEMORY]
            [/MEMORY_V1]
            """,
            disclosure: disclosure
        )

        #expect(rendered.components(separatedBy: "[LONGTERM_MEMORY]").count - 1 == 1)
        #expect(rendered.contains("longterm_mode=progressive_disclosure"))
        #expect(rendered.contains("retrieval_available=true"))
        #expect(rendered.contains("policy=progressive_disclosure_required"))
        #expect(rendered.contains("stage_0=outline_summary"))
        #expect(rendered.contains("stage_1=related_snippets"))
        #expect(rendered.contains("stage_2=explicit_ref_read_only"))
        #expect(rendered.contains("stage_1_rule=state_summary_insufficient_before_requesting_snippets"))
        #expect(rendered.contains("stage_2_rule=explicit_ref_required_before_ref_read"))
        #expect(!rendered.contains("retrieval_available=false"))
    }

    private static func resolutionResult(
        mode: XTMemoryUseMode,
        profile: XTMemoryServingProfile,
        usedTokens: Int,
        budgetTokens: Int,
        truncatedLayers: [String]
    ) -> HubIPCClient.MemoryContextResolutionResult {
        let response = HubIPCClient.MemoryContextResponsePayload(
            text: "profile=\(profile.rawValue)",
            source: "test_override",
            resolvedMode: mode.rawValue,
            resolvedProfile: profile.rawValue,
            budgetTotalTokens: budgetTokens,
            usedTotalTokens: usedTokens,
            layerUsage: [
                HubIPCClient.MemoryContextLayerUsage(
                    layer: "l1_canonical",
                    usedTokens: min(usedTokens, max(1, budgetTokens - 120)),
                    budgetTokens: budgetTokens
                )
            ],
            truncatedLayers: truncatedLayers,
            redactedItems: 0,
            privateDrops: 0
        )
        return HubIPCClient.MemoryContextResolutionResult(
            response: response,
            source: "test_override",
            resolvedMode: mode,
            requestedProfile: profile.rawValue,
            attemptedProfiles: [profile.rawValue],
            freshness: "fresh_local_ipc",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil
        )
    }
}
