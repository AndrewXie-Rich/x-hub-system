import Foundation
import Testing
@testable import XTerminal

actor MemoryRetrievalPayloadRecorder {
    private var payloads: [HubIPCClient.MemoryRetrievalPayload] = []

    func append(_ payload: HubIPCClient.MemoryRetrievalPayload) {
        payloads.append(payload)
    }

    func first() -> HubIPCClient.MemoryRetrievalPayload? {
        payloads.first
    }

    func count() -> Int {
        payloads.count
    }
}

@Suite(.serialized)
struct HubIPCClientMemoryRetrievalContractTests {

    @Test
    func projectChatRetrievalCarriesV1ContractFieldsAndNormalizesResult() async throws {
        let recorder = MemoryRetrievalPayloadRecorder()
        HubIPCClient.installMemoryRetrievalOverrideForTesting { payload, _ in
            await recorder.append(payload)
            return HubIPCClient.MemoryRetrievalResponsePayload(
                source: "test_memory_retrieval",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: nil,
                denyCode: nil,
                snippets: [
                    HubIPCClient.MemoryRetrievalSnippet(
                        snippetId: "snippet-1",
                        sourceKind: "decision_track",
                        title: "approved stack",
                        ref: "memory://decision/proj-1/stack",
                        text: "Use Swift + governed Hub memory.",
                        score: 96,
                        truncated: false
                    )
                ],
                truncatedItems: 0,
                redactedItems: 0
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let response = await HubIPCClient.requestProjectMemoryRetrieval(
            requesterRole: .chat,
            useMode: .projectChat,
            projectId: "proj-1",
            projectRoot: "/tmp/proj-1",
            displayName: "亮亮",
            latestUser: "这个项目的 tech stack 决策是什么",
            reason: "project_chat_progressive_disclosure_seed",
            requestedKinds: ["project_spec_capsule", "decision_track"],
            explicitRefs: [],
            maxSnippets: 3,
            maxSnippetChars: 420,
            timeoutSec: 0.1
        )

        let payload = try #require(await recorder.first())
        let normalized = try #require(response)
        let result = try #require(normalized.results?.first)

        #expect(payload.schemaVersion == "xt.memory_retrieval_request.v1")
        #expect(payload.requestId.hasPrefix("memreq_"))
        #expect(payload.mode == XTMemoryUseMode.projectChat.rawValue)
        #expect(payload.query == "这个项目的 tech stack 决策是什么")
        #expect(payload.allowedLayers == [XTMemoryLayer.l1Canonical.rawValue])
        #expect(payload.retrievalKind == "search")
        #expect(payload.maxResults == 3)
        #expect(payload.requireExplainability == true)

        #expect(normalized.schemaVersion == "xt.memory_retrieval_result.v1")
        #expect(normalized.requestId == payload.requestId)
        #expect(normalized.status == "ok")
        #expect(normalized.resolvedScope == "current_project")
        #expect(normalized.truncated == false)
        #expect((normalized.budgetUsedChars ?? 0) > 0)
        #expect(result.sourceKind == "decision_track")
        #expect(result.summary == "approved stack")
        #expect(result.snippet == "Use Swift + governed Hub memory.")
        #expect(abs(result.score - 0.96) < 0.0001)
        #expect(result.redacted == false)
    }

    @Test
    func supervisorRefRetrievalUsesGetRefModeAndNormalizesDeniedResult() async throws {
        let recorder = MemoryRetrievalPayloadRecorder()
        HubIPCClient.installMemoryRetrievalOverrideForTesting { payload, _ in
            await recorder.append(payload)
            return HubIPCClient.MemoryRetrievalResponsePayload(
                source: "test_memory_retrieval",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: "scope_gate",
                denyCode: XTMemoryUseDenyCode.crossScopeMemoryDenied.rawValue,
                snippets: [],
                truncatedItems: 0,
                redactedItems: 0
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let response = await HubIPCClient.requestProjectMemoryRetrieval(
            requesterRole: .supervisor,
            useMode: .supervisorOrchestration,
            projectId: "proj-2",
            projectRoot: "/tmp/proj-2",
            displayName: "项目二",
            latestUser: "展开 memory://decision/proj-2/approved-stack",
            reason: "supervisor_focused_project_review",
            requestedKinds: ["decision_track"],
            explicitRefs: ["memory://decision/proj-2/approved-stack"],
            maxSnippets: 2,
            maxSnippetChars: 300,
            timeoutSec: 0.1
        )

        let payload = try #require(await recorder.first())
        let normalized = try #require(response)

        #expect(payload.mode == XTMemoryUseMode.supervisorOrchestration.rawValue)
        #expect(payload.retrievalKind == "get_ref")
        #expect(payload.allowedLayers == [
            XTMemoryLayer.l1Canonical.rawValue,
            XTMemoryLayer.l2Observations.rawValue
        ])
        #expect(payload.explicitRefs == ["memory://decision/proj-2/approved-stack"])

        #expect(normalized.status == "denied")
        #expect(normalized.requestId == payload.requestId)
        #expect(normalized.resolvedScope == "current_project")
        #expect(normalized.results?.isEmpty == true)
        #expect(normalized.truncated == false)
    }

    @Test
    func genericMemoryRetrievalSupportsToolPlanRequests() async throws {
        let recorder = MemoryRetrievalPayloadRecorder()
        HubIPCClient.installMemoryRetrievalOverrideForTesting { payload, _ in
            await recorder.append(payload)
            return HubIPCClient.MemoryRetrievalResponsePayload(
                source: "test_memory_retrieval",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: nil,
                denyCode: nil,
                snippets: [],
                truncatedItems: 1,
                redactedItems: 0
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let response = await HubIPCClient.requestMemoryRetrieval(
            HubIPCClient.MemoryRetrievalRequest(
                requesterRole: .tool,
                useMode: .toolPlan,
                projectId: "proj-tool-1",
                projectRoot: "/tmp/proj-tool-1",
                displayName: "Tool Project",
                query: "查一下当前项目 blocker 的正式决策",
                reason: "tool_plan_memory_lookup",
                requestedKinds: ["decision_track", "project_spec_capsule"],
                explicitRefs: [],
                allowedLayers: [.l1Canonical],
                retrievalKind: "search",
                maxResults: 2,
                maxSnippetChars: 280
            ),
            timeoutSec: 0.1
        )

        let payload = try #require(await recorder.first())
        let normalized = try #require(response)

        #expect(payload.requesterRole == XTMemoryRequesterRole.tool.rawValue)
        #expect(payload.mode == XTMemoryUseMode.toolPlan.rawValue)
        #expect(payload.allowedLayers == [XTMemoryLayer.l1Canonical.rawValue])
        #expect(payload.maxResults == 2)
        #expect(payload.maxSnippets == 2)
        #expect(payload.retrievalKind == "search")

        #expect(normalized.status == "truncated")
        #expect(normalized.requestId == payload.requestId)
        #expect(normalized.truncated == true)
    }

    @Test
    func governedCodingRuntimeTruthRetrievalUsesAutomationKindsAndDualLayers() async throws {
        let recorder = MemoryRetrievalPayloadRecorder()
        HubIPCClient.installMemoryRetrievalOverrideForTesting { payload, _ in
            await recorder.append(payload)
            return HubIPCClient.MemoryRetrievalResponsePayload(
                source: "test_memory_retrieval",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: nil,
                denyCode: nil,
                snippets: [
                    HubIPCClient.MemoryRetrievalSnippet(
                        snippetId: "runtime-1",
                        sourceKind: "automation_execution_report",
                        title: "Automation execution blocked",
                        ref: "/tmp/proj-runtime/build/reports/xt_automation_run_handoff_run-1.v1.json#run:run-1",
                        text: "run_id: run-1\nblocker_code: automation_verify_failed",
                        score: 94,
                        truncated: false
                    )
                ],
                truncatedItems: 0,
                redactedItems: 0
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let response = await HubIPCClient.requestMemoryRetrieval(
            HubIPCClient.MemoryRetrievalRequest(
                requesterRole: .supervisor,
                useMode: .supervisorOrchestration,
                projectId: "proj-runtime",
                projectRoot: "/tmp/proj-runtime",
                displayName: "Runtime Project",
                query: "当前 blocker、retry plan 和 latest guidance 是什么",
                reason: "supervisor_runtime_truth_review",
                requestedKinds: [
                    "automation_execution_report",
                    "automation_checkpoint",
                    "automation_retry_package",
                    "heartbeat_projection",
                    "guidance_injection"
                ],
                explicitRefs: [],
                allowedLayers: [],
                retrievalKind: "search",
                maxResults: 5,
                maxSnippetChars: 480
            ),
            timeoutSec: 0.1
        )

        let payload = try #require(await recorder.first())
        let normalized = try #require(response)
        let result = try #require(normalized.results?.first)

        #expect(payload.requestedKinds == [
            "automation_execution_report",
            "automation_checkpoint",
            "automation_retry_package",
            "heartbeat_projection",
            "guidance_injection"
        ])
        #expect(Set(payload.allowedLayers) == Set([
            XTMemoryLayer.l1Canonical.rawValue,
            XTMemoryLayer.l2Observations.rawValue
        ]))
        #expect(payload.retrievalKind == "search")
        #expect(normalized.status == "ok")
        #expect(result.sourceKind == "automation_execution_report")
        #expect(result.ref.contains("xt_automation_run_handoff_run-1.v1.json"))
        #expect(abs(result.score - 0.94) < 0.0001)
    }

    @Test
    func grpcRemoteRetrievalFallsBackToLocalWhenAllowed() async throws {
        let localRecorder = MemoryRetrievalPayloadRecorder()
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
        HubIPCClient.installRemoteMemoryRetrievalOverrideForTesting { _, _ in
            nil
        }
        HubIPCClient.installLocalMemoryRetrievalIPCOverrideForTesting { payload, _ in
            await localRecorder.append(payload)
            return HubIPCClient.MemoryRetrievalResponsePayload(
                source: "test_local_ipc",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: nil,
                denyCode: nil,
                snippets: [
                    HubIPCClient.MemoryRetrievalSnippet(
                        snippetId: "local-1",
                        sourceKind: "canonical_memory",
                        title: "fallback result",
                        ref: "memory://hub/fallback",
                        text: "Local IPC fallback handled the retrieval.",
                        score: 91,
                        truncated: false
                    )
                ],
                truncatedItems: 0,
                redactedItems: 0
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let response = await HubIPCClient.requestProjectMemoryRetrieval(
            requesterRole: .chat,
            useMode: .projectChat,
            projectId: "proj-fallback",
            projectRoot: "/tmp/proj-fallback",
            displayName: "Fallback Project",
            latestUser: "查一下 fallback retrieval",
            reason: "fallback_test",
            requestedKinds: ["decision_track"],
            explicitRefs: [],
            maxSnippets: 1,
            maxSnippetChars: 240,
            timeoutSec: 0.1
        )

        let normalized = try #require(response)
        #expect(await localRecorder.count() == 1)
        #expect(normalized.source == "test_local_ipc")
        #expect(normalized.status == "ok")
    }

    @Test
    func grpcRemoteRetrievalFailsClosedWithoutLocalFallback() async throws {
        let localRecorder = MemoryRetrievalPayloadRecorder()
        HubIPCClient.installHubRouteDecisionOverrideForTesting {
            HubRouteDecision(
                mode: .grpc,
                hasRemoteProfile: true,
                preferRemote: true,
                allowFileFallback: false,
                requiresRemote: true,
                remoteUnavailableReasonCode: nil
            )
        }
        HubIPCClient.installRemoteMemoryRetrievalOverrideForTesting { _, _ in
            nil
        }
        HubIPCClient.installLocalMemoryRetrievalIPCOverrideForTesting { payload, _ in
            await localRecorder.append(payload)
            return HubIPCClient.MemoryRetrievalResponsePayload(
                source: "unexpected_local_ipc",
                scope: payload.scope,
                auditRef: payload.auditRef,
                snippets: [],
                truncatedItems: 0,
                redactedItems: 0
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let response = await HubIPCClient.requestProjectMemoryRetrieval(
            requesterRole: .supervisor,
            useMode: .supervisorOrchestration,
            projectId: "proj-remote-only",
            projectRoot: "/tmp/proj-remote-only",
            displayName: "Remote Only",
            latestUser: "展开 remote retrieval",
            reason: "remote_only_test",
            requestedKinds: ["decision_track"],
            explicitRefs: [],
            maxSnippets: 1,
            maxSnippetChars: 240,
            timeoutSec: 0.1
        )

        #expect(response == nil)
        #expect(await localRecorder.count() == 0)
    }
}
