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

actor RemoteSnapshotFetchCountRecorder {
    private var count: Int = 0

    func increment() {
        count += 1
    }

    func snapshot() -> Int {
        count
    }
}

actor RemoteSnapshotFetchKeyedRecorder {
    private var counts: [String: Int] = [:]

    func increment(_ key: String) {
        counts[key, default: 0] += 1
    }

    func snapshot(_ key: String) -> Int {
        counts[key, default: 0]
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

    @Test
    func remoteSnapshotCacheExposesPostureAndLastInvalidationReasonAfterManualRefresh() async throws {
        let recorder = RemoteSnapshotFetchCountRecorder()
        let projectId = "proj-cache-\(UUID().uuidString.lowercased())"

        HubIPCClient.installHubRouteDecisionOverrideForTesting {
            HubRouteDecision(
                mode: .auto,
                hasRemoteProfile: true,
                preferRemote: true,
                allowFileFallback: true,
                requiresRemote: false,
                remoteUnavailableReasonCode: nil
            )
        }
        HubIPCClient.installRemoteMemorySnapshotOverrideForTesting { mode, projectId, _, _ in
            await recorder.increment()
            return HubRemoteMemorySnapshotResult(
                ok: true,
                source: "hub_memory_v1_grpc",
                canonicalEntries: ["goal: keep memory fast and governed"],
                workingEntries: ["mode=\(mode.rawValue)", "project=\(projectId ?? "(none)")"],
                reasonCode: nil,
                logLines: []
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let first = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .projectChat,
            requesterRole: .chat,
            projectId: projectId,
            projectRoot: "/tmp/\(projectId)",
            displayName: projectId,
            latestUser: "继续当前项目",
            constitutionHint: "safe",
            canonicalText: "local canonical",
            observationsText: "local observations",
            workingSetText: "local working",
            rawEvidenceText: "local raw",
            progressiveDisclosure: false,
            budgets: nil,
            timeoutSec: 0.1
        )
        let firstResponse = try #require(first.response)
        #expect(first.cacheHit == false)
        #expect(firstResponse.remoteSnapshotCachePosture == XTMemoryRemoteSnapshotCachePosture.continuitySafe.rawValue)
        #expect(firstResponse.remoteSnapshotInvalidationReason == nil)

        let second = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .projectChat,
            requesterRole: .chat,
            projectId: projectId,
            projectRoot: "/tmp/\(projectId)",
            displayName: projectId,
            latestUser: "继续当前项目",
            constitutionHint: "safe",
            canonicalText: "local canonical",
            observationsText: "local observations",
            workingSetText: "local working",
            rawEvidenceText: "local raw",
            progressiveDisclosure: false,
            budgets: nil,
            timeoutSec: 0.1
        )
        let secondResponse = try #require(second.response)
        #expect(second.cacheHit == true)
        #expect(secondResponse.freshness == "ttl_cache")
        #expect(await recorder.snapshot() == 1)

        await HubIPCClient.refreshProjectRemoteMemorySnapshotCache(projectId: projectId)

        let third = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .projectChat,
            requesterRole: .chat,
            projectId: projectId,
            projectRoot: "/tmp/\(projectId)",
            displayName: projectId,
            latestUser: "继续当前项目",
            constitutionHint: "safe",
            canonicalText: "local canonical",
            observationsText: "local observations",
            workingSetText: "local working",
            rawEvidenceText: "local raw",
            progressiveDisclosure: false,
            budgets: nil,
            timeoutSec: 0.1
        )

        let thirdResponse = try #require(third.response)
        #expect(third.cacheHit == false)
        #expect(thirdResponse.remoteSnapshotCachePosture == XTMemoryRemoteSnapshotCachePosture.continuitySafe.rawValue)
        #expect(
            thirdResponse.remoteSnapshotInvalidationReason
            == XTMemoryRemoteSnapshotInvalidationReason.manualRefresh.rawValue
        )
        #expect(await recorder.snapshot() == 2)
    }

    @Test
    func transportModeChangeInvalidatesRemoteSnapshotCacheWithRouteReason() async throws {
        let recorder = RemoteSnapshotFetchCountRecorder()
        let projectId = "proj-transport-\(UUID().uuidString.lowercased())"
        let originalMode = HubAIClient.transportMode()

        HubIPCClient.installHubRouteDecisionOverrideForTesting {
            HubRouteDecision(
                mode: .auto,
                hasRemoteProfile: true,
                preferRemote: true,
                allowFileFallback: true,
                requiresRemote: false,
                remoteUnavailableReasonCode: nil
            )
        }
        HubIPCClient.installRemoteMemorySnapshotOverrideForTesting { mode, projectId, _, _ in
            await recorder.increment()
            return HubRemoteMemorySnapshotResult(
                ok: true,
                source: "hub_memory_v1_grpc",
                canonicalEntries: ["goal: keep route changes observable"],
                workingEntries: ["mode=\(mode.rawValue)", "project=\(projectId ?? "(none)")"],
                reasonCode: nil,
                logLines: []
            )
        }
        defer {
            HubIPCClient.resetMemoryContextResolutionOverrideForTesting()
            HubAIClient.setTransportMode(originalMode)
        }

        let first = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .projectChat,
            requesterRole: .chat,
            projectId: projectId,
            projectRoot: "/tmp/\(projectId)",
            displayName: projectId,
            latestUser: "继续当前项目",
            constitutionHint: "safe",
            canonicalText: "local canonical",
            observationsText: "local observations",
            workingSetText: "local working",
            rawEvidenceText: "local raw",
            progressiveDisclosure: false,
            budgets: nil,
            timeoutSec: 0.1
        )
        let firstResponse = try #require(first.response)
        #expect(first.cacheHit == false)
        #expect(firstResponse.remoteSnapshotInvalidationReason == nil)

        let second = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .projectChat,
            requesterRole: .chat,
            projectId: projectId,
            projectRoot: "/tmp/\(projectId)",
            displayName: projectId,
            latestUser: "继续当前项目",
            constitutionHint: "safe",
            canonicalText: "local canonical",
            observationsText: "local observations",
            workingSetText: "local working",
            rawEvidenceText: "local raw",
            progressiveDisclosure: false,
            budgets: nil,
            timeoutSec: 0.1
        )
        #expect(second.cacheHit == true)
        #expect(await recorder.snapshot() == 1)

        let replacementMode: HubTransportMode = originalMode == .grpc ? .auto : .grpc
        HubAIClient.setTransportMode(replacementMode)
        try await Task.sleep(for: .milliseconds(50))

        let third = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .projectChat,
            requesterRole: .chat,
            projectId: projectId,
            projectRoot: "/tmp/\(projectId)",
            displayName: projectId,
            latestUser: "继续当前项目",
            constitutionHint: "safe",
            canonicalText: "local canonical",
            observationsText: "local observations",
            workingSetText: "local working",
            rawEvidenceText: "local raw",
            progressiveDisclosure: false,
            budgets: nil,
            timeoutSec: 0.1
        )

        let thirdResponse = try #require(third.response)
        #expect(third.cacheHit == false)
        #expect(
            thirdResponse.remoteSnapshotInvalidationReason
            == XTMemoryRemoteSnapshotInvalidationReason.routeOrModelPreferenceChanged.rawValue
        )
        #expect(await recorder.snapshot() == 2)
    }

    @Test
    func voiceGrantChallengeInvalidatesProjectAndSupervisorRemoteSnapshotCaches() async throws {
        let projectId = "proj-voice-challenge-\(UUID().uuidString.lowercased())"
        let recorder = RemoteSnapshotFetchKeyedRecorder()

        HubIPCClient.installHubRouteDecisionOverrideForTesting {
            Self.preferredRemoteRouteDecision()
        }
        HubIPCClient.installRemoteMemorySnapshotOverrideForTesting { mode, incomingProjectId, _, _ in
            await recorder.increment("\(mode.rawValue)|\(incomingProjectId ?? "(none)")")
            return Self.remoteSnapshotResult(mode: mode, projectId: incomingProjectId)
        }
        HubIPCClient.installVoiceGrantChallengeOverrideForTesting { payload in
            HubIPCClient.VoiceGrantChallengeResult(
                ok: true,
                source: "hub_memory_v1_grpc",
                challenge: HubIPCClient.VoiceGrantChallengeSnapshot(
                    challengeId: "voice-challenge-\(payload.requestId)",
                    templateId: payload.templateId,
                    actionDigest: payload.actionDigest,
                    scopeDigest: payload.scopeDigest,
                    amountDigest: payload.amountDigest ?? "",
                    challengeCode: payload.challengeCode ?? "confirm",
                    riskLevel: payload.riskLevel,
                    requiresMobileConfirm: payload.requiresMobileConfirm,
                    allowVoiceOnly: payload.allowVoiceOnly,
                    boundDeviceId: payload.boundDeviceId ?? "device-1",
                    mobileTerminalId: payload.mobileTerminalId ?? "terminal-1",
                    issuedAtMs: 1_774_000_100_000,
                    expiresAtMs: 1_774_000_160_000
                ),
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        await HubIPCClient.refreshProjectRemoteMemorySnapshotCache(projectId: projectId)
        await HubIPCClient.refreshSupervisorRemoteMemorySnapshotCache()

        _ = try #require(await Self.requestProjectMemory(projectId: projectId).response)
        let projectCached = await Self.requestProjectMemory(projectId: projectId)
        #expect(projectCached.cacheHit == true)

        _ = try #require(await Self.requestSupervisorMemory(projectId: projectId).response)
        let supervisorCached = await Self.requestSupervisorMemory(projectId: projectId)
        #expect(supervisorCached.cacheHit == true)

        let challenge = await HubIPCClient.issueVoiceGrantChallenge(
            HubIPCClient.VoiceGrantChallengeRequestPayload(
                requestId: "voice-request-\(projectId)",
                projectId: projectId,
                templateId: "voice_authorize_high_risk_action_v1",
                actionDigest: "action-digest-\(projectId)",
                scopeDigest: "scope-digest-\(projectId)",
                amountDigest: "amount-digest-\(projectId)",
                challengeCode: "confirm",
                riskLevel: "high",
                boundDeviceId: "device-1",
                mobileTerminalId: "terminal-1",
                allowVoiceOnly: false,
                requiresMobileConfirm: true,
                ttlMs: 60_000
            )
        )
        #expect(challenge.ok == true)
        #expect(challenge.challenge?.challengeId == "voice-challenge-voice-request-\(projectId)")

        let projectFresh = await Self.requestProjectMemory(projectId: projectId)
        let projectFreshResponse = try #require(projectFresh.response)
        #expect(projectFresh.cacheHit == false)
        #expect(
            projectFreshResponse.remoteSnapshotInvalidationReason
            == XTMemoryRemoteSnapshotInvalidationReason.grantStateChanged.rawValue
        )

        let supervisorFresh = await Self.requestSupervisorMemory(projectId: projectId)
        let supervisorFreshResponse = try #require(supervisorFresh.response)
        #expect(supervisorFresh.cacheHit == false)
        #expect(
            supervisorFreshResponse.remoteSnapshotInvalidationReason
            == XTMemoryRemoteSnapshotInvalidationReason.grantStateChanged.rawValue
        )

        #expect(await recorder.snapshot("\(XTMemoryUseMode.projectChat.rawValue)|\(projectId)") == 2)
        #expect(
            await recorder.snapshot("\(XTMemoryUseMode.supervisorOrchestration.rawValue)|(none)") == 2
        )
    }

    @Test
    func voiceGrantVerificationDenyInvalidatesProjectAndSupervisorRemoteSnapshotCaches() async throws {
        let projectId = "proj-voice-verify-\(UUID().uuidString.lowercased())"
        let recorder = RemoteSnapshotFetchKeyedRecorder()

        HubIPCClient.installHubRouteDecisionOverrideForTesting {
            Self.preferredRemoteRouteDecision()
        }
        HubIPCClient.installRemoteMemorySnapshotOverrideForTesting { mode, incomingProjectId, _, _ in
            await recorder.increment("\(mode.rawValue)|\(incomingProjectId ?? "(none)")")
            return Self.remoteSnapshotResult(mode: mode, projectId: incomingProjectId)
        }
        HubIPCClient.installVoiceGrantVerificationOverrideForTesting { payload in
            HubIPCClient.VoiceGrantVerificationResult(
                ok: true,
                verified: false,
                decision: .deny,
                source: "hub_memory_v1_grpc",
                denyCode: "voice_mismatch",
                challengeId: payload.challengeId,
                transcriptHash: payload.transcriptHash,
                semanticMatchScore: payload.semanticMatchScore ?? 0,
                challengeMatch: false,
                deviceBindingOK: true,
                mobileConfirmed: payload.mobileConfirmed,
                reasonCode: "denied"
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        await HubIPCClient.refreshProjectRemoteMemorySnapshotCache(projectId: projectId)
        await HubIPCClient.refreshSupervisorRemoteMemorySnapshotCache()

        _ = try #require(await Self.requestProjectMemory(projectId: projectId).response)
        let projectCached = await Self.requestProjectMemory(projectId: projectId)
        #expect(projectCached.cacheHit == true)

        _ = try #require(await Self.requestSupervisorMemory(projectId: projectId).response)
        let supervisorCached = await Self.requestSupervisorMemory(projectId: projectId)
        #expect(supervisorCached.cacheHit == true)

        let verification = await HubIPCClient.verifyVoiceGrantResponse(
            HubIPCClient.VoiceGrantVerificationPayload(
                requestId: "voice-verify-\(projectId)",
                projectId: projectId,
                challengeId: "challenge-\(projectId)",
                challengeCode: "confirm",
                transcript: "authorize this action",
                transcriptHash: "transcript-hash-\(projectId)",
                semanticMatchScore: 0.42,
                parsedActionDigest: "action-digest-\(projectId)",
                parsedScopeDigest: "scope-digest-\(projectId)",
                parsedAmountDigest: "amount-digest-\(projectId)",
                verifyNonce: "nonce-\(projectId)",
                boundDeviceId: "device-1",
                mobileConfirmed: true
            )
        )
        #expect(verification.ok == true)
        #expect(verification.decision == .deny)
        #expect(verification.reasonCode == "denied")

        let projectFresh = await Self.requestProjectMemory(projectId: projectId)
        let projectFreshResponse = try #require(projectFresh.response)
        #expect(projectFresh.cacheHit == false)
        #expect(
            projectFreshResponse.remoteSnapshotInvalidationReason
            == XTMemoryRemoteSnapshotInvalidationReason.grantStateChanged.rawValue
        )

        let supervisorFresh = await Self.requestSupervisorMemory(projectId: projectId)
        let supervisorFreshResponse = try #require(supervisorFresh.response)
        #expect(supervisorFresh.cacheHit == false)
        #expect(
            supervisorFreshResponse.remoteSnapshotInvalidationReason
            == XTMemoryRemoteSnapshotInvalidationReason.grantStateChanged.rawValue
        )

        #expect(await recorder.snapshot("\(XTMemoryUseMode.projectChat.rawValue)|\(projectId)") == 2)
        #expect(
            await recorder.snapshot("\(XTMemoryUseMode.supervisorOrchestration.rawValue)|(none)") == 2
        )
    }

    @Test
    func voiceGrantVerificationFailureDoesNotInvalidateRemoteSnapshotCaches() async throws {
        let projectId = "proj-voice-verify-failed-\(UUID().uuidString.lowercased())"
        let recorder = RemoteSnapshotFetchKeyedRecorder()

        HubIPCClient.installHubRouteDecisionOverrideForTesting {
            Self.preferredRemoteRouteDecision()
        }
        HubIPCClient.installRemoteMemorySnapshotOverrideForTesting { mode, incomingProjectId, _, _ in
            await recorder.increment("\(mode.rawValue)|\(incomingProjectId ?? "(none)")")
            return Self.remoteSnapshotResult(mode: mode, projectId: incomingProjectId)
        }
        HubIPCClient.installVoiceGrantVerificationOverrideForTesting { payload in
            HubIPCClient.VoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: payload.challengeId,
                transcriptHash: payload.transcriptHash,
                semanticMatchScore: payload.semanticMatchScore ?? 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: payload.mobileConfirmed,
                reasonCode: "remote_voice_grant_verify_failed"
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        await HubIPCClient.refreshProjectRemoteMemorySnapshotCache(projectId: projectId)
        await HubIPCClient.refreshSupervisorRemoteMemorySnapshotCache()

        _ = try #require(await Self.requestProjectMemory(projectId: projectId).response)
        _ = try #require(await Self.requestSupervisorMemory(projectId: projectId).response)

        let verification = await HubIPCClient.verifyVoiceGrantResponse(
            HubIPCClient.VoiceGrantVerificationPayload(
                requestId: "voice-verify-failed-\(projectId)",
                projectId: projectId,
                challengeId: "challenge-\(projectId)",
                challengeCode: "confirm",
                transcript: "authorize this action",
                transcriptHash: "transcript-hash-\(projectId)",
                semanticMatchScore: 0.2,
                parsedActionDigest: "action-digest-\(projectId)",
                parsedScopeDigest: "scope-digest-\(projectId)",
                parsedAmountDigest: "amount-digest-\(projectId)",
                verifyNonce: "nonce-\(projectId)",
                boundDeviceId: "device-1",
                mobileConfirmed: false
            )
        )
        #expect(verification.ok == false)
        #expect(verification.decision == .failed)

        let projectCached = await Self.requestProjectMemory(projectId: projectId)
        let projectCachedResponse = try #require(projectCached.response)
        #expect(projectCached.cacheHit == true)
        #expect(projectCachedResponse.remoteSnapshotInvalidationReason == nil)

        let supervisorCached = await Self.requestSupervisorMemory(projectId: projectId)
        let supervisorCachedResponse = try #require(supervisorCached.response)
        #expect(supervisorCached.cacheHit == true)
        #expect(supervisorCachedResponse.remoteSnapshotInvalidationReason == nil)

        #expect(await recorder.snapshot("\(XTMemoryUseMode.projectChat.rawValue)|\(projectId)") == 1)
        #expect(
            await recorder.snapshot("\(XTMemoryUseMode.supervisorOrchestration.rawValue)|(none)") == 1
        )
    }

    @Test
    func paidRemoteGenerateGrantApprovalInvalidatesProjectAndSupervisorRemoteSnapshotCaches() async throws {
        let projectId = "proj-paid-grant-approved-\(UUID().uuidString.lowercased())"
        let recorder = RemoteSnapshotFetchKeyedRecorder()

        HubIPCClient.installHubRouteDecisionOverrideForTesting {
            Self.preferredRemoteRouteDecision()
        }
        HubIPCClient.installRemoteMemorySnapshotOverrideForTesting { mode, incomingProjectId, _, _ in
            await recorder.increment("\(mode.rawValue)|\(incomingProjectId ?? "(none)")")
            return Self.remoteSnapshotResult(mode: mode, projectId: incomingProjectId)
        }
        HubAIClient.installRemoteGenerateOverrideForTesting { invocation in
            HubRemoteGenerateResult(
                ok: true,
                text: "paid remote generate succeeded after grant",
                modelId: invocation.modelId,
                requestedModelId: invocation.modelId,
                actualModelId: invocation.modelId,
                runtimeProvider: "Hub (Remote)",
                executionPath: "remote_model",
                fallbackReasonCode: nil,
                grantDecision: .approved,
                grantRequestId: "paid-grant-\(invocation.requestId)",
                reasonCode: nil,
                logLines: []
            )
        }
        defer {
            HubIPCClient.resetMemoryContextResolutionOverrideForTesting()
            HubAIClient.resetRemoteGenerateOverrideForTesting()
        }

        await HubIPCClient.refreshProjectRemoteMemorySnapshotCache(projectId: projectId)
        await HubIPCClient.refreshSupervisorRemoteMemorySnapshotCache()

        _ = try #require(await Self.requestProjectMemory(projectId: projectId).response)
        _ = try #require(await Self.requestSupervisorMemory(projectId: projectId).response)

        let resolution = await HubAIClient.shared.remoteRetryResolutionForTesting(
            preferredModelId: "openai/gpt-5.4",
            remoteBackupModelId: nil,
            projectId: projectId,
            transportMode: .grpc
        )
        #expect(resolution.ok == true)
        #expect(resolution.actualModelId == "openai/gpt-5.4")

        let projectFresh = await Self.requestProjectMemory(projectId: projectId)
        let projectFreshResponse = try #require(projectFresh.response)
        #expect(projectFresh.cacheHit == false)
        #expect(
            projectFreshResponse.remoteSnapshotInvalidationReason
            == XTMemoryRemoteSnapshotInvalidationReason.grantStateChanged.rawValue
        )

        let supervisorFresh = await Self.requestSupervisorMemory(projectId: projectId)
        let supervisorFreshResponse = try #require(supervisorFresh.response)
        #expect(supervisorFresh.cacheHit == false)
        #expect(
            supervisorFreshResponse.remoteSnapshotInvalidationReason
            == XTMemoryRemoteSnapshotInvalidationReason.grantStateChanged.rawValue
        )

        #expect(await recorder.snapshot("\(XTMemoryUseMode.projectChat.rawValue)|\(projectId)") == 2)
        #expect(
            await recorder.snapshot("\(XTMemoryUseMode.supervisorOrchestration.rawValue)|(none)") == 2
        )
    }

    @Test
    func escalatedHeartbeatAnomalyInvalidatesProjectAndSupervisorRemoteSnapshotCaches() async throws {
        let fixture = ToolExecutorProjectFixture(name: "review-schedule-memory-invalidation")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        let projectId = AXProjectRegistryStore.projectId(forRoot: fixture.root)
        var config = AXProjectConfig.default(forProjectRoot: fixture.root)
        config.progressHeartbeatSeconds = 600
        config.reviewPulseSeconds = 900
        config.brainstormReviewSeconds = 1800
        try AXProjectStore.saveConfig(config, for: ctx)

        let recorder = RemoteSnapshotFetchKeyedRecorder()
        HubIPCClient.installHubRouteDecisionOverrideForTesting {
            HubRouteDecision(
                mode: .auto,
                hasRemoteProfile: true,
                preferRemote: true,
                allowFileFallback: true,
                requiresRemote: false,
                remoteUnavailableReasonCode: nil
            )
        }
        HubIPCClient.installRemoteMemorySnapshotOverrideForTesting { mode, incomingProjectId, _, _ in
            await recorder.increment("\(mode.rawValue)|\(incomingProjectId ?? "(none)")")
            return HubRemoteMemorySnapshotResult(
                ok: true,
                source: "hub_memory_v1_grpc",
                canonicalEntries: ["goal: keep escalation visible"],
                workingEntries: ["mode=\(mode.rawValue)", "project=\(incomingProjectId ?? "(none)")"],
                reasonCode: nil,
                logLines: []
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        await HubIPCClient.refreshProjectRemoteMemorySnapshotCache(projectId: projectId)
        await HubIPCClient.refreshSupervisorRemoteMemorySnapshotCache()

        _ = try #require(
            await HubIPCClient.requestMemoryContextDetailed(
                useMode: .projectChat,
                requesterRole: .chat,
                projectId: projectId,
                projectRoot: fixture.root.path,
                displayName: "Project",
                latestUser: "继续当前项目",
                constitutionHint: "safe",
                canonicalText: "canonical",
                observationsText: "observations",
                workingSetText: "working",
                rawEvidenceText: "raw",
                progressiveDisclosure: false,
                budgets: nil,
                timeoutSec: 0.1
            ).response
        )
        let projectCached = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .projectChat,
            requesterRole: .chat,
            projectId: projectId,
            projectRoot: fixture.root.path,
            displayName: "Project",
            latestUser: "继续当前项目",
            constitutionHint: "safe",
            canonicalText: "canonical",
            observationsText: "observations",
            workingSetText: "working",
            rawEvidenceText: "raw",
            progressiveDisclosure: false,
            budgets: nil,
            timeoutSec: 0.1
        )
        #expect(projectCached.cacheHit == true)

        _ = try #require(
            await HubIPCClient.requestMemoryContextDetailed(
                useMode: .supervisorOrchestration,
                requesterRole: .supervisor,
                projectId: nil,
                projectRoot: nil,
                displayName: "Supervisor",
                latestUser: "审查当前 heartbeat 风险",
                reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
                constitutionHint: "safe",
                portfolioBriefText: "portfolio",
                focusedProjectAnchorPackText: "project: \(projectId)",
                longtermOutlineText: "longterm",
                deltaFeedText: "delta",
                conflictSetText: "conflict",
                contextRefsText: "refs",
                evidencePackText: "evidence",
                canonicalText: "canonical",
                observationsText: "observations",
                workingSetText: "working",
                rawEvidenceText: "raw",
                servingProfile: .m2PlanReview,
                progressiveDisclosure: false,
                budgets: nil,
                timeoutSec: 0.1
            ).response
        )
        let supervisorCached = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .supervisorOrchestration,
            requesterRole: .supervisor,
            projectId: nil,
            projectRoot: nil,
            displayName: "Supervisor",
            latestUser: "审查当前 heartbeat 风险",
            reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
            constitutionHint: "safe",
            portfolioBriefText: "portfolio",
            focusedProjectAnchorPackText: "project: \(projectId)",
            longtermOutlineText: "longterm",
            deltaFeedText: "delta",
            conflictSetText: "conflict",
            contextRefsText: "refs",
            evidencePackText: "evidence",
            canonicalText: "canonical",
            observationsText: "observations",
            workingSetText: "working",
            rawEvidenceText: "raw",
            servingProfile: .m2PlanReview,
            progressiveDisclosure: false,
            budgets: nil,
            timeoutSec: 0.1
        )
        #expect(supervisorCached.cacheHit == true)

        let assessment = HeartbeatAssessmentResult(
            meaningfulProgressAtMs: nil,
            qualitySnapshot: HeartbeatQualitySnapshot(
                overallScore: 28,
                overallBand: .weak,
                freshnessScore: 30,
                deltaSignificanceScore: 22,
                evidenceStrengthScore: 25,
                blockerClarityScore: 18,
                nextActionSpecificityScore: 24,
                executionVitalityScore: 20,
                completionConfidenceScore: 16,
                weakReasons: ["weak heartbeat should force a fresh governed reread"],
                computedAtMs: 1_774_000_000_000
            ),
            openAnomalies: [
                HeartbeatAnomalyNote(
                    anomalyId: "hb-anomaly-\(projectId)",
                    projectId: projectId,
                    anomalyType: .weakDoneClaim,
                    severity: .high,
                    confidence: 0.92,
                    reason: "done claim is weak and needs rescue review",
                    evidenceRefs: ["heartbeat://\(projectId)/done"],
                    detectedAtMs: 1_774_000_000_000,
                    recommendedEscalation: .rescueReview
                )
            ],
            heartbeatFingerprint: "hb-fingerprint-1",
            repeatCount: 1,
            projectPhase: .verify,
            executionStatus: .blocked,
            riskTier: .high
        )

        _ = try SupervisorReviewScheduleStore.touchHeartbeat(
            for: ctx,
            config: config,
            assessment: assessment,
            nowMs: 1_774_000_000_000
        )
        try await Task.sleep(for: .milliseconds(50))

        let projectFresh = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .projectChat,
            requesterRole: .chat,
            projectId: projectId,
            projectRoot: fixture.root.path,
            displayName: "Project",
            latestUser: "继续当前项目",
            constitutionHint: "safe",
            canonicalText: "canonical",
            observationsText: "observations",
            workingSetText: "working",
            rawEvidenceText: "raw",
            progressiveDisclosure: false,
            budgets: nil,
            timeoutSec: 0.1
        )
        let projectFreshResponse = try #require(projectFresh.response)
        #expect(projectFresh.cacheHit == false)
        #expect(
            projectFreshResponse.remoteSnapshotInvalidationReason
            == XTMemoryRemoteSnapshotInvalidationReason.heartbeatAnomalyEscalated.rawValue
        )

        let supervisorFresh = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .supervisorOrchestration,
            requesterRole: .supervisor,
            projectId: nil,
            projectRoot: nil,
            displayName: "Supervisor",
            latestUser: "审查当前 heartbeat 风险",
            reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
            constitutionHint: "safe",
            portfolioBriefText: "portfolio",
            focusedProjectAnchorPackText: "project: \(projectId)",
            longtermOutlineText: "longterm",
            deltaFeedText: "delta",
            conflictSetText: "conflict",
            contextRefsText: "refs",
            evidencePackText: "evidence",
            canonicalText: "canonical",
            observationsText: "observations",
            workingSetText: "working",
            rawEvidenceText: "raw",
            servingProfile: .m2PlanReview,
            progressiveDisclosure: false,
            budgets: nil,
            timeoutSec: 0.1
        )
        let supervisorFreshResponse = try #require(supervisorFresh.response)
        #expect(supervisorFresh.cacheHit == false)
        #expect(
            supervisorFreshResponse.remoteSnapshotInvalidationReason
            == XTMemoryRemoteSnapshotInvalidationReason.heartbeatAnomalyEscalated.rawValue
        )

        #expect(await recorder.snapshot("\(XTMemoryUseMode.projectChat.rawValue)|\(projectId)") == 2)
        #expect(
            await recorder.snapshot("\(XTMemoryUseMode.supervisorOrchestration.rawValue)|(none)") == 2
        )
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

    private static func preferredRemoteRouteDecision() -> HubRouteDecision {
        HubRouteDecision(
            mode: .auto,
            hasRemoteProfile: true,
            preferRemote: true,
            allowFileFallback: true,
            requiresRemote: false,
            remoteUnavailableReasonCode: nil
        )
    }

    private static func remoteSnapshotResult(
        mode: XTMemoryUseMode,
        projectId: String?
    ) -> HubRemoteMemorySnapshotResult {
        HubRemoteMemorySnapshotResult(
            ok: true,
            source: "hub_memory_v1_grpc",
            canonicalEntries: ["goal: keep remote snapshot freshness aligned with grant truth"],
            workingEntries: ["mode=\(mode.rawValue)", "project=\(projectId ?? "(none)")"],
            reasonCode: nil,
            logLines: []
        )
    }

    private static func requestProjectMemory(
        projectId: String
    ) async -> HubIPCClient.MemoryContextResolutionResult {
        await HubIPCClient.requestMemoryContextDetailed(
            useMode: .projectChat,
            requesterRole: .chat,
            projectId: projectId,
            projectRoot: "/tmp/\(projectId)",
            displayName: projectId,
            latestUser: "继续当前项目",
            constitutionHint: "safe",
            canonicalText: "canonical",
            observationsText: "observations",
            workingSetText: "working",
            rawEvidenceText: "raw",
            progressiveDisclosure: false,
            budgets: nil,
            timeoutSec: 0.1
        )
    }

    private static func requestSupervisorMemory(
        projectId: String
    ) async -> HubIPCClient.MemoryContextResolutionResult {
        await HubIPCClient.requestMemoryContextDetailed(
            useMode: .supervisorOrchestration,
            requesterRole: .supervisor,
            projectId: nil,
            projectRoot: nil,
            displayName: "Supervisor",
            latestUser: "审查当前授权状态",
            reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
            constitutionHint: "safe",
            portfolioBriefText: "portfolio",
            focusedProjectAnchorPackText: "project: \(projectId)",
            longtermOutlineText: "longterm",
            deltaFeedText: "delta",
            conflictSetText: "conflict",
            contextRefsText: "refs",
            evidencePackText: "evidence",
            canonicalText: "canonical",
            observationsText: "observations",
            workingSetText: "working",
            rawEvidenceText: "raw",
            servingProfile: .m2PlanReview,
            progressiveDisclosure: false,
            budgets: nil,
            timeoutSec: 0.1
        )
    }
}
