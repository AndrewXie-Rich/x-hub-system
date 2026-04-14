import Foundation
import Testing
@testable import XTerminal

actor RemoteAuxTimeoutRecorder {
    struct RuntimeSurfaceRequest: Equatable, Sendable {
        var projectId: String?
        var limit: Int
        var timeoutSec: Double
    }

    private var snapshotTimeouts: [Double] = []
    private var retrievalTimeouts: [Double] = []
    private var runtimeSurfaceTimeouts: [Double] = []
    private var runtimeSurfaceRequests: [RuntimeSurfaceRequest] = []

    func appendSnapshotTimeout(_ timeoutSec: Double) {
        snapshotTimeouts.append(timeoutSec)
    }

    func appendRetrievalTimeout(_ timeoutSec: Double) {
        retrievalTimeouts.append(timeoutSec)
    }

    func appendRuntimeSurfaceTimeout(_ timeoutSec: Double) {
        runtimeSurfaceTimeouts.append(timeoutSec)
    }

    func appendRuntimeSurfaceRequest(projectId: String?, limit: Int, timeoutSec: Double) {
        runtimeSurfaceRequests.append(
            RuntimeSurfaceRequest(
                projectId: projectId,
                limit: limit,
                timeoutSec: timeoutSec
            )
        )
    }

    func latestSnapshotTimeout() -> Double? {
        snapshotTimeouts.last
    }

    func latestRetrievalTimeout() -> Double? {
        retrievalTimeouts.last
    }

    func latestRuntimeSurfaceTimeout() -> Double? {
        runtimeSurfaceTimeouts.last
    }

    func runtimeSurfaceTimeoutCount() -> Int {
        runtimeSurfaceTimeouts.count
    }

    func runtimeSurfaceRequestsSnapshot() -> [RuntimeSurfaceRequest] {
        runtimeSurfaceRequests
    }
}

@Suite(.serialized)
struct HubIPCClientRemoteAuxTimeoutTests {
    @Test
    func requestMemoryContextDetailedForwardsRemoteSnapshotTimeout() async throws {
        let recorder = RemoteAuxTimeoutRecorder()
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
        HubIPCClient.installRemoteMemorySnapshotOverrideForTesting { mode, projectId, _, timeoutSec in
            await recorder.appendSnapshotTimeout(timeoutSec)
            return HubRemoteMemorySnapshotResult(
                ok: true,
                source: "hub_memory_v1_grpc",
                canonicalEntries: ["goal = keep remote chat responsive"],
                workingEntries: ["user: hello"],
                reasonCode: nil,
                logLines: ["mode=\(mode.rawValue) project=\(projectId ?? "(none)")"]
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let result = await HubIPCClient.requestMemoryContextDetailed(
            useMode: .supervisorOrchestration,
            requesterRole: .supervisor,
            projectId: nil,
            projectRoot: nil,
            displayName: "Supervisor",
            latestUser: "现在远端模型为什么没反应",
            constitutionHint: "safe",
            canonicalText: "local canonical",
            observationsText: "local observations",
            workingSetText: "local working",
            rawEvidenceText: "local raw",
            progressiveDisclosure: false,
            budgets: nil,
            timeoutSec: 0.75
        )

        let response = try #require(result.response)
        let timeout = try #require(await recorder.latestSnapshotTimeout())
        #expect(abs(timeout - 0.75) < 0.0001)
        #expect(response.source == "hub_memory_v1_grpc")
        #expect(response.freshness == "fresh_remote")
    }

    @Test
    func requestSupervisorRemoteContinuityForwardsRemoteSnapshotTimeout() async throws {
        let recorder = RemoteAuxTimeoutRecorder()
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
        HubIPCClient.installRemoteMemorySnapshotOverrideForTesting { mode, _, bypassCache, timeoutSec in
            await recorder.appendSnapshotTimeout(timeoutSec)
            return HubRemoteMemorySnapshotResult(
                ok: true,
                source: bypassCache ? "hub_thread_bypass" : "hub_thread",
                canonicalEntries: [],
                workingEntries: ["assistant: ready"],
                reasonCode: nil,
                logLines: ["mode=\(mode.rawValue)"]
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let result = await HubIPCClient.requestSupervisorRemoteContinuity(
            bypassCache: true,
            timeoutSec: 0.55
        )

        let timeout = try #require(await recorder.latestSnapshotTimeout())
        #expect(abs(timeout - 0.55) < 0.0001)
        #expect(result.ok)
        #expect(result.source == "hub_thread")
        #expect(result.workingEntries == ["assistant: ready"])
    }

    @Test
    func requestMemoryRetrievalForwardsRemoteTimeout() async throws {
        let recorder = RemoteAuxTimeoutRecorder()
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
        HubIPCClient.installRemoteMemoryRetrievalOverrideForTesting { payload, timeoutSec in
            await recorder.appendRetrievalTimeout(timeoutSec)
            return HubIPCClient.MemoryRetrievalResponsePayload(
                schemaVersion: "xt.memory_retrieval_result.v1",
                requestId: payload.requestId,
                status: "ok",
                resolvedScope: payload.scope,
                source: "hub_memory_retrieval_grpc_v1",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: nil,
                denyCode: nil,
                results: [],
                snippets: [],
                truncated: false,
                budgetUsedChars: 0,
                truncatedItems: 0,
                redactedItems: 0
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let response = await HubIPCClient.requestProjectMemoryRetrieval(
            requesterRole: .supervisor,
            useMode: .supervisorOrchestration,
            projectId: "proj-timeout",
            projectRoot: "/tmp/proj-timeout",
            displayName: "proj-timeout",
            latestUser: "给我这个项目的关键上下文",
            reason: "timeout_test",
            requestedKinds: ["plan"],
            explicitRefs: [],
            maxSnippets: 2,
            maxSnippetChars: 180,
            timeoutSec: 0.65
        )

        let timeout = try #require(await recorder.latestRetrievalTimeout())
        #expect(abs(timeout - 0.65) < 0.0001)
        #expect(response?.source == "hub_memory_retrieval_grpc_v1")
    }

    @Test
    func requestProjectRuntimeSurfaceOverrideForwardsRemoteTimeout() async throws {
        let recorder = RemoteAuxTimeoutRecorder()
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
        HubIPCClient.installRemoteRuntimeSurfaceOverridesOverrideForTesting { projectId, limit, timeoutSec in
            await recorder.appendRuntimeSurfaceTimeout(timeoutSec)
            return HubRemoteRuntimeSurfaceOverridesResult(
                ok: true,
                source: "hub_runtime_grpc",
                updatedAtMs: 1_773_320_190_000,
                items: [
                    HubRemoteRuntimeSurfaceOverrideItem(
                        projectId: projectId ?? "project-a",
                        overrideMode: .clampGuided,
                        updatedAtMs: 1_773_320_150_000,
                        reason: "hub_browser_only",
                        auditRef: "audit-runtime-surface-timeout"
                    )
                ],
                reasonCode: limit == 1 ? nil : "unexpected_limit",
                logLines: ["project=\(projectId ?? "(none)") limit=\(limit)"]
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let override = await HubIPCClient.requestProjectRuntimeSurfaceOverride(
            projectId: "project-a",
            timeoutSec: 0.6
        )

        let timeout = try #require(await recorder.latestRuntimeSurfaceTimeout())
        #expect(abs(timeout - 0.6) < 0.0001)
        let resolved = try #require(override)
        #expect(resolved.projectId == "project-a")
        #expect(resolved.overrideMode == .clampGuided)
        #expect(resolved.reason == "hub_browser_only")
        #expect(resolved.auditRef == "audit-runtime-surface-timeout")
    }

    @Test
    func requestProjectRuntimeSurfaceOverrideCachesRecentRemoteMiss() async throws {
        let recorder = RemoteAuxTimeoutRecorder()
        let projectID = "project-runtime-surface-miss"
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
        HubIPCClient.installRemoteRuntimeSurfaceOverridesOverrideForTesting { _, _, timeoutSec in
            await recorder.appendRuntimeSurfaceTimeout(timeoutSec)
            return HubRemoteRuntimeSurfaceOverridesResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "remote_runtime_surface_unavailable",
                logLines: ["simulated remote miss"]
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let first = await HubIPCClient.requestProjectRuntimeSurfaceOverride(
            projectId: projectID,
            bypassCache: false,
            timeoutSec: 0.6
        )
        let second = await HubIPCClient.requestProjectRuntimeSurfaceOverride(
            projectId: projectID,
            bypassCache: false,
            timeoutSec: 0.6
        )

        #expect(first == nil)
        #expect(second == nil)
        #expect(await recorder.runtimeSurfaceTimeoutCount() == 1)
    }

    @Test
    func requestProjectRuntimeSurfaceOverrideUsesSharedSnapshotAndDeduplicatesConcurrentFetches() async throws {
        let recorder = RemoteAuxTimeoutRecorder()
        let projectA = "project-runtime-surface-shared-a"
        let projectB = "project-runtime-surface-shared-b"
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
        HubIPCClient.installRemoteRuntimeSurfaceOverridesOverrideForTesting { projectId, limit, timeoutSec in
            await recorder.appendRuntimeSurfaceRequest(
                projectId: projectId,
                limit: limit,
                timeoutSec: timeoutSec
            )
            try? await Task.sleep(nanoseconds: 150_000_000)
            return HubRemoteRuntimeSurfaceOverridesResult(
                ok: true,
                source: "hub_runtime_grpc",
                updatedAtMs: 1_773_320_290_000,
                items: [
                    HubRemoteRuntimeSurfaceOverrideItem(
                        projectId: projectA,
                        overrideMode: .clampGuided,
                        updatedAtMs: 1_773_320_250_000,
                        reason: "hub_browser_only",
                        auditRef: "audit-runtime-surface-shared-a"
                    ),
                    HubRemoteRuntimeSurfaceOverrideItem(
                        projectId: projectB,
                        overrideMode: .killSwitch,
                        updatedAtMs: 1_773_320_260_000,
                        reason: "hub_emergency_stop",
                        auditRef: "audit-runtime-surface-shared-b"
                    )
                ],
                reasonCode: nil,
                logLines: ["project=\(projectId ?? "(none)") limit=\(limit)"]
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        async let overrideA = HubIPCClient.requestProjectRuntimeSurfaceOverride(
            projectId: projectA,
            timeoutSec: 0.6
        )
        async let overrideB = HubIPCClient.requestProjectRuntimeSurfaceOverride(
            projectId: projectB,
            timeoutSec: 0.6
        )

        let resolvedA = try #require(await overrideA)
        let resolvedB = try #require(await overrideB)
        let requests = await recorder.runtimeSurfaceRequestsSnapshot()

        #expect(resolvedA.projectId == projectA)
        #expect(resolvedA.overrideMode == .clampGuided)
        #expect(resolvedB.projectId == projectB)
        #expect(resolvedB.overrideMode == .killSwitch)
        #expect(requests.count == 1)
        #expect(requests.first?.projectId == nil)
        #expect(requests.first?.limit == 500)
        let timeout = try #require(requests.first?.timeoutSec)
        #expect(abs(timeout - 0.6) < 0.0001)
    }

    @Test
    func requestProjectRuntimeSurfaceOverrideTimesOutSlowSharedFetch() async throws {
        let recorder = RemoteAuxTimeoutRecorder()
        let projectID = "project-runtime-surface-stale-fetch"
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
        HubIPCClient.installRemoteRuntimeSurfaceOverridesOverrideForTesting { projectId, limit, timeoutSec in
            await recorder.appendRuntimeSurfaceRequest(
                projectId: projectId,
                limit: limit,
                timeoutSec: timeoutSec
            )
            if projectId == nil, limit == 500 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            return HubRemoteRuntimeSurfaceOverridesResult(
                ok: true,
                source: "hub_runtime_grpc",
                updatedAtMs: 1_773_320_390_000,
                items: [
                    HubRemoteRuntimeSurfaceOverrideItem(
                        projectId: projectID,
                        overrideMode: .clampGuided,
                        updatedAtMs: 1_773_320_350_000,
                        reason: "hub_browser_only",
                        auditRef: "audit-runtime-surface-stale-fetch"
                    )
                ],
                reasonCode: nil,
                logLines: ["project=\(projectId ?? "(none)") limit=\(limit)"]
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let startedAt = Date()
        let stalledFetch = await HubIPCClient.requestProjectRuntimeSurfaceOverride(
            projectId: projectID,
            timeoutSec: 0.25
        )
        let elapsed = Date().timeIntervalSince(startedAt)
        #expect(elapsed < 1.0)
        let timedOutFallback = try #require(stalledFetch)
        #expect(timedOutFallback.projectId == projectID)
        #expect(timedOutFallback.overrideMode == .clampGuided)

        let recovered = await HubIPCClient.requestProjectRuntimeSurfaceOverride(
            projectId: projectID,
            bypassCache: true,
            timeoutSec: 0.25
        )
        let resolved = try #require(recovered)
        #expect(resolved.projectId == projectID)
        #expect(resolved.overrideMode == .clampGuided)

        let requests = await recorder.runtimeSurfaceRequestsSnapshot()
        #expect(requests.contains {
            $0.projectId == nil && $0.limit == 500 && abs($0.timeoutSec - 0.25) < 0.0001
        })
        #expect(requests.contains {
            $0.projectId == projectID && $0.limit == 1 && abs($0.timeoutSec - 0.25) < 0.0001
        })
    }
}
