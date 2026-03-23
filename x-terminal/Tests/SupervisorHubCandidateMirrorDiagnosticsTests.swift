import Testing
@testable import XTerminal

struct SupervisorHubCandidateMirrorDiagnosticsTests {
    @Test
    func turnExplainabilityShowsMirrorStatusAndLocalStoreRole() throws {
        let presentation = try #require(
            SupervisorMemoryBoardPresentationMapper.turnExplainabilityPresentation(
                decision: nil,
                assembly: nil,
                writeback: SupervisorAfterTurnWritebackClassification(
                    turnMode: .projectFirst,
                    candidates: [
                        SupervisorAfterTurnWritebackCandidate(
                            scope: .projectScope,
                            recordType: "project_blocker",
                            confidence: 0.92,
                            whyPromoted: "focused project fact with durable planning/blocker significance",
                            sourceRef: "user_message",
                            auditRef: "supervisor_writeback:project_scope:project_blocker:proj-liangliang:1",
                            sessionParticipationClass: "scoped_write",
                            writePermissionScope: "project_scope",
                            idempotencyKey: "sha256:test",
                            payloadSummary: "project_id=proj-liangliang;record_type=project_blocker"
                        )
                    ],
                    summaryLine: "project_scope",
                    mirrorStatus: .hubMirrorFailed,
                    mirrorTarget: XTSupervisorDurableCandidateMirror.mirrorTarget,
                    mirrorAttempted: true,
                    mirrorErrorCode: "remote_route_not_preferred",
                    localStoreRole: XTSupervisorDurableCandidateMirror.localStoreRole
                )
            )
        )

        #expect(
            presentation.detailLines.contains {
                $0.contains("Hub mirror：Hub 镜像失败")
                    && $0.contains("reason=remote_route_not_preferred")
            }
        )
        #expect(
            presentation.detailLines.contains {
                $0.contains("本地 store 角色：\(XTSupervisorDurableCandidateMirror.localStoreRole)")
            }
        )
    }

    @Test
    func turnExplainabilityShowsLocalFailClosedReasonForDeniedCandidate() throws {
        let presentation = try #require(
            SupervisorMemoryBoardPresentationMapper.turnExplainabilityPresentation(
                decision: nil,
                assembly: nil,
                writeback: SupervisorAfterTurnWritebackClassification(
                    turnMode: .projectFirst,
                    candidates: [
                        SupervisorAfterTurnWritebackCandidate(
                            scope: .projectScope,
                            recordType: "project_blocker",
                            confidence: 0.92,
                            whyPromoted: "focused project fact with durable planning/blocker significance",
                            sourceRef: "user_message",
                            auditRef: "supervisor_writeback:project_scope:project_blocker:proj-liangliang:1",
                            sessionParticipationClass: "read_only",
                            writePermissionScope: "project_scope",
                            idempotencyKey: "sha256:test-read-only",
                            payloadSummary: "project_id=proj-liangliang;record_type=project_blocker"
                        )
                    ],
                    summaryLine: "project_scope",
                    mirrorStatus: .localOnly,
                    mirrorTarget: XTSupervisorDurableCandidateMirror.mirrorTarget,
                    mirrorAttempted: true,
                    mirrorErrorCode: "supervisor_candidate_session_participation_denied",
                    localStoreRole: XTSupervisorDurableCandidateMirror.localStoreRole
                )
            )
        )

        #expect(
            presentation.detailLines.contains {
                $0.contains("Hub mirror：仅保留本地 fallback")
                    && $0.contains("reason=supervisor_candidate_session_participation_denied")
            }
        )
    }
}
