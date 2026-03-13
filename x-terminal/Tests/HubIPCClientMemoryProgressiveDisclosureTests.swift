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
