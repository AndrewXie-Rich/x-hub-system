import Foundation
import Testing
@testable import XTerminal

actor SupervisorDurableCandidatePayloadRecorder {
    private var payloads: [HubRemoteSupervisorConversationPayload] = []

    func record(_ payload: HubRemoteSupervisorConversationPayload) {
        payloads.append(payload)
    }

    func snapshot() -> HubRemoteSupervisorConversationPayload? {
        payloads.last
    }

    func callCount() -> Int {
        payloads.count
    }
}

@Suite(.serialized)
struct SupervisorHubCandidateMirrorTests {
    @Test
    func mirrorUsesDedicatedThreadAndStructuredCarrierPayload() async throws {
        let recorder = SupervisorDurableCandidatePayloadRecorder()
        XTSupervisorDurableCandidateMirror.installTransportOverrideForTesting { payload in
            await recorder.record(payload)
            return HubRemoteMutationResult(ok: true, reasonCode: nil, logLines: [])
        }
        defer { XTSupervisorDurableCandidateMirror.resetTransportOverrideForTesting() }

        let classification = SupervisorAfterTurnWritebackClassifier.classify(
            SupervisorAfterTurnWritebackClassificationRequest(
                userMessage: "亮亮现在 blocker 是 grant pending。",
                responseText: "已记录。",
                routingDecision: SupervisorTurnRoutingDecision(
                    mode: .projectFirst,
                    focusedProjectId: "proj-liangliang",
                    focusedProjectName: "亮亮",
                    focusedPersonName: nil,
                    focusedCommitmentId: nil,
                    confidence: 0.95,
                    routingReasons: ["explicit_project_mention:亮亮"]
                ),
                projects: [makeProject(id: "proj-liangliang", name: "亮亮")],
                personalMemory: .empty
            )
        )

        let result = await XTSupervisorDurableCandidateMirror.mirror(
            classification: classification,
            createdAt: 12.345
        )
        let payload = try #require(await recorder.snapshot())

        #expect(result.status == .mirroredToHub)
        #expect(result.attempted)
        #expect(payload.threadKey == XTSupervisorDurableCandidateMirror.threadKey)
        #expect(payload.requestId.hasPrefix("xterminal_supervisor_durable_candidate_"))
        #expect(payload.createdAtMs == 12_345)
        #expect(payload.userText.contains("project_scope"))
        #expect(payload.assistantText.contains("\"schema_version\":\"xt.supervisor.durable_candidate_mirror.v1\""))
        #expect(payload.assistantText.contains("\"mirror_target\":\"\(XTSupervisorDurableCandidateMirror.mirrorTarget)\""))
        #expect(payload.assistantText.contains("\"idempotency_key\":\""))
        #expect(payload.assistantText.contains("\"payload_summary\":\"project_id=proj-liangliang;record_type=project_blocker\""))
    }

    @Test
    func workingSetOnlyClassificationDoesNotAttemptMirror() async {
        let classification = SupervisorAfterTurnWritebackClassifier.classify(
            SupervisorAfterTurnWritebackClassificationRequest(
                userMessage: "先按这个方向试一版。",
                responseText: "我先给你出一个草案。",
                routingDecision: SupervisorTurnRoutingDecision(
                    mode: .projectFirst,
                    focusedProjectId: "proj-liangliang",
                    focusedProjectName: "亮亮",
                    focusedPersonName: nil,
                    focusedCommitmentId: nil,
                    confidence: 0.82,
                    routingReasons: ["current_project_pointer:亮亮"]
                ),
                projects: [makeProject(id: "proj-liangliang", name: "亮亮")],
                personalMemory: .empty
            )
        )

        let result = await XTSupervisorDurableCandidateMirror.mirror(
            classification: classification,
            createdAt: 1
        )

        #expect(result.status == .notNeeded)
        #expect(!result.attempted)
    }

    @Test
    func mirrorFailsClosedLocallyForReadOnlyParticipationWithoutTransportCall() async {
        let recorder = SupervisorDurableCandidatePayloadRecorder()
        XTSupervisorDurableCandidateMirror.installTransportOverrideForTesting { payload in
            await recorder.record(payload)
            return HubRemoteMutationResult(ok: true, reasonCode: nil, logLines: [])
        }
        defer { XTSupervisorDurableCandidateMirror.resetTransportOverrideForTesting() }

        let result = await XTSupervisorDurableCandidateMirror.mirror(
            classification: makeMirrorClassification(
                candidate: makeCandidate(sessionParticipationClass: "read_only")
            ),
            createdAt: 2
        )

        #expect(result.status == .localOnly)
        #expect(result.attempted)
        #expect(result.errorCode == "supervisor_candidate_session_participation_denied")
        #expect(await recorder.callCount() == 0)
        #expect(await recorder.snapshot() == nil)
    }

    @Test
    func mirrorFailsClosedLocallyForIgnoreParticipationWithoutTransportCall() async {
        let recorder = SupervisorDurableCandidatePayloadRecorder()
        XTSupervisorDurableCandidateMirror.installTransportOverrideForTesting { payload in
            await recorder.record(payload)
            return HubRemoteMutationResult(ok: true, reasonCode: nil, logLines: [])
        }
        defer { XTSupervisorDurableCandidateMirror.resetTransportOverrideForTesting() }

        let result = await XTSupervisorDurableCandidateMirror.mirror(
            classification: makeMirrorClassification(
                candidate: makeCandidate(sessionParticipationClass: "ignore")
            ),
            createdAt: 3
        )

        #expect(result.status == .localOnly)
        #expect(result.attempted)
        #expect(result.errorCode == "supervisor_candidate_session_participation_denied")
        #expect(await recorder.callCount() == 0)
        #expect(await recorder.snapshot() == nil)
    }

    @Test
    func mirrorFailsClosedLocallyForInvalidParticipationWithoutTransportCall() async {
        let recorder = SupervisorDurableCandidatePayloadRecorder()
        XTSupervisorDurableCandidateMirror.installTransportOverrideForTesting { payload in
            await recorder.record(payload)
            return HubRemoteMutationResult(ok: true, reasonCode: nil, logLines: [])
        }
        defer { XTSupervisorDurableCandidateMirror.resetTransportOverrideForTesting() }

        let result = await XTSupervisorDurableCandidateMirror.mirror(
            classification: makeMirrorClassification(
                candidate: makeCandidate(sessionParticipationClass: "foreground_only")
            ),
            createdAt: 4
        )

        #expect(result.status == .localOnly)
        #expect(result.attempted)
        #expect(result.errorCode == "supervisor_candidate_session_participation_invalid")
        #expect(await recorder.callCount() == 0)
        #expect(await recorder.snapshot() == nil)
    }

    @Test
    func mirrorFailsClosedLocallyForScopeMismatchWithoutTransportCall() async {
        let recorder = SupervisorDurableCandidatePayloadRecorder()
        XTSupervisorDurableCandidateMirror.installTransportOverrideForTesting { payload in
            await recorder.record(payload)
            return HubRemoteMutationResult(ok: true, reasonCode: nil, logLines: [])
        }
        defer { XTSupervisorDurableCandidateMirror.resetTransportOverrideForTesting() }

        let result = await XTSupervisorDurableCandidateMirror.mirror(
            classification: makeMirrorClassification(
                candidate: makeCandidate(writePermissionScope: SupervisorAfterTurnWritebackScope.userScope.rawValue)
            ),
            createdAt: 5
        )

        #expect(result.status == .localOnly)
        #expect(result.attempted)
        #expect(result.errorCode == "supervisor_candidate_scope_mismatch")
        #expect(await recorder.callCount() == 0)
        #expect(await recorder.snapshot() == nil)
    }

    private func makeProject(id: String, name: String) -> AXProjectEntry {
        AXProjectEntry(
            projectId: id,
            rootPath: "/tmp/\(id)",
            displayName: name,
            lastOpenedAt: 1,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
    }

    private func makeMirrorClassification(
        candidate: SupervisorAfterTurnWritebackCandidate
    ) -> SupervisorAfterTurnWritebackClassification {
        SupervisorAfterTurnWritebackClassification(
            turnMode: .projectFirst,
            candidates: [candidate],
            summaryLine: candidate.scope.rawValue
        )
    }

    private func makeCandidate(
        scope: SupervisorAfterTurnWritebackScope = .projectScope,
        sessionParticipationClass: String = "scoped_write",
        writePermissionScope: String? = nil
    ) -> SupervisorAfterTurnWritebackCandidate {
        SupervisorAfterTurnWritebackCandidate(
            scope: scope,
            recordType: "project_blocker",
            confidence: 0.92,
            whyPromoted: "focused project fact with durable planning/blocker significance",
            sourceRef: "user_message",
            auditRef: "supervisor_writeback:\(scope.rawValue):project_blocker:proj-liangliang:1",
            sessionParticipationClass: sessionParticipationClass,
            writePermissionScope: writePermissionScope ?? scope.rawValue,
            idempotencyKey: "sha256:test-\(scope.rawValue)-\(sessionParticipationClass)",
            payloadSummary: "project_id=proj-liangliang;record_type=project_blocker"
        )
    }
}
