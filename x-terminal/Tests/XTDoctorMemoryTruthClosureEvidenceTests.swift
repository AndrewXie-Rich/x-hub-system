import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct XTDoctorMemoryTruthClosureEvidenceTests {
    private static let gate = HubGlobalStateTestGate.shared

    @MainActor
    @Test
    func memoryTruthAndCanonicalSyncClosureStayExplainableAcrossXTAndSupervisorSurfaces() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
            let truthExamples = [
                XTMemoryTruthExample(
                    rawSource: "hub",
                    label: XTMemorySourceTruthPresentation.label("hub"),
                    explainableLabel: XTMemorySourceTruthPresentation.explainableLabel("hub"),
                    truthHint: XTMemorySourceTruthPresentation.truthHint("hub")
                ),
                XTMemoryTruthExample(
                    rawSource: "hub_memory_v1_grpc",
                    label: XTMemorySourceTruthPresentation.label("hub_memory_v1_grpc"),
                    explainableLabel: XTMemorySourceTruthPresentation.explainableLabel("hub_memory_v1_grpc"),
                    truthHint: XTMemorySourceTruthPresentation.truthHint("hub_memory_v1_grpc")
                ),
                XTMemoryTruthExample(
                    rawSource: "local_fallback",
                    label: XTMemorySourceTruthPresentation.label("local_fallback"),
                    explainableLabel: XTMemorySourceTruthPresentation.explainableLabel("local_fallback"),
                    truthHint: XTMemorySourceTruthPresentation.truthHint("local_fallback")
                )
            ]

            #expect(truthExamples[0].explainableLabel == "Hub 记忆（Hub durable truth）")
            #expect(truthExamples[1].explainableLabel == "Hub 快照 + 本地 overlay（快照拼接，非 durable 真相）")
            #expect(truthExamples[2].explainableLabel == "本地 fallback（Hub 不可用时兜底）")

            let projectSummary = AXProjectContextAssemblyDiagnosticsSummary(
                latestEvent: nil,
                detailLines: [
                    "project_context_diagnostics_source=latest_coder_usage",
                    "project_context_project=Snake",
                    "project_memory_v1_source=hub_memory_v1_grpc",
                    "memory_v1_freshness=ttl_cache",
                    "memory_v1_cache_hit=true",
                    "memory_v1_remote_snapshot_cache_scope=mode=project_chat project_id=snake",
                    "memory_v1_remote_snapshot_age_ms=6000",
                    "memory_v1_remote_snapshot_ttl_remaining_ms=9000",
                    "recent_project_dialogue_profile=extended_40_pairs",
                    "recent_project_dialogue_selected_pairs=18",
                    "recent_project_dialogue_floor_pairs=8",
                    "recent_project_dialogue_floor_satisfied=true",
                    "recent_project_dialogue_source=xt_cache",
                    "recent_project_dialogue_low_signal_dropped=3",
                    "project_context_depth=full",
                    "effective_project_serving_profile=m4_full_scan",
                    "workflow_present=true",
                    "execution_evidence_present=true",
                    "review_guidance_present=false",
                    "cross_link_hints_selected=2",
                    "personal_memory_excluded_reason=project_ai_default_scopes_to_project_memory_only",
                    "hub_memory_prompt_projection_projection_source=hub_generate_done_metadata",
                    "hub_memory_prompt_projection_canonical_item_count=3",
                    "hub_memory_prompt_projection_working_set_turn_count=18",
                    "hub_memory_prompt_projection_runtime_truth_item_count=2",
                    "hub_memory_prompt_projection_runtime_truth_source_kinds=guidance_injection,heartbeat_projection"
                ]
            )
            let projectPresentation = try #require(AXProjectContextAssemblyPresentation.from(summary: projectSummary))
            let promptProjection = try #require(projectSummary.hubMemoryPromptProjection)
            #expect(projectPresentation.memorySource == "hub_memory_v1_grpc")
            #expect(projectPresentation.memorySourceLabel == "Hub 快照 + 本地 overlay")
            #expect(projectPresentation.userStatusLine.contains("Hub 快照 + 本地 overlay（快照拼接，非 durable 真相）"))
            #expect(projectPresentation.userStatusLine.contains("remote snapshot：TTL cache"))
            #expect(projectPresentation.userStatusLine.contains("Hub truth via XT cache"))
            #expect(projectPresentation.userStatusLine.contains("age 6s"))
            #expect(projectPresentation.userStatusLine.contains("ttl 剩余 9s"))
            #expect(projectPresentation.userStatusLine.contains("mode=project_chat project_id=snake"))
            #expect(projectPresentation.userStatusLine.contains("Writer + Gate"))
            #expect(promptProjection.projectionSource == "hub_generate_done_metadata")
            #expect(promptProjection.canonicalItemCount == 3)
            #expect(promptProjection.workingSetTurnCount == 18)
            #expect(promptProjection.runtimeTruthItemCount == 2)
            #expect(promptProjection.runtimeTruthSourceKinds == ["guidance_injection", "heartbeat_projection"])
            let projectMemorySource = try #require(projectPresentation.memorySource)
            let projectMemorySourceLabel = try #require(projectPresentation.memorySourceLabel)

            let supervisorSnapshot = SupervisorMemoryAssemblySnapshot(
                source: "hub",
                resolutionSource: "hub_memory",
                updatedAt: 1,
                reviewLevelHint: "r2_strategic",
                requestedProfile: "balanced",
                profileFloor: "balanced",
                resolvedProfile: "balanced",
                attemptedProfiles: ["balanced"],
                progressiveUpgradeCount: 0,
                focusedProjectId: "project-alpha",
                selectedSections: ["l1_canonical", "l3_working_set"],
                omittedSections: [],
                contextRefsSelected: 2,
                contextRefsOmitted: 0,
                evidenceItemsSelected: 1,
                evidenceItemsOmitted: 0,
                budgetTotalTokens: 1200,
                usedTotalTokens: 600,
                truncatedLayers: [],
                freshness: "ttl_cache",
                cacheHit: true,
                remoteSnapshotCacheScope: "mode=supervisor_orchestration project_id=(none)",
                remoteSnapshotCachedAtMs: 1_774_000_005_000,
                remoteSnapshotAgeMs: 3_000,
                remoteSnapshotTTLRemainingMs: 12_000,
                denyCode: nil,
                downgradeCode: nil,
                reasonCode: nil,
                compressionPolicy: "balanced"
            )
            let supervisorPresentation = SupervisorMemoryBoardPresentationMapper.map(
                statusLine: "memory=hub · projects=1",
                memorySource: "hub",
                replyExecutionMode: "remote_model",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "openai/gpt-5.4",
                failureReasonCode: "",
                readiness: .init(ready: true, statusLine: "ready", issues: []),
                rawAssemblyStatusLine: "assembly ok",
                afterTurnSummary: nil,
                pendingFollowUpQuestion: "",
                assemblySnapshot: supervisorSnapshot,
                skillRegistryStatusLine: "registry unavailable",
                skillRegistrySnapshot: nil,
                digests: [],
                preview: ""
            )
            #expect(supervisorPresentation.modeSourceText == "当前记忆来源：Hub 记忆（Hub durable truth） · 用途：Supervisor 编排")
            #expect(
                supervisorPresentation.continuityDetailLine?.contains("本轮从Hub 记忆（Hub durable truth）带入连续对话与背景记忆。") == true
            )
            #expect(supervisorPresentation.continuityDetailLine?.contains("连续性快照：remote snapshot TTL cache") == true)
            #expect(supervisorPresentation.continuityDetailLine?.contains("age 3s") == true)
            #expect(supervisorPresentation.continuityDetailLine?.contains("ttl_left 12s") == true)
            #expect(supervisorPresentation.continuityDetailLine?.contains("mode=supervisor_orchestration project_id=(none)") == true)

            let canonicalIssue = SupervisorMemoryAssemblyIssue(
                code: "memory_canonical_sync_delivery_failed",
                severity: .blocking,
                summary: "Canonical memory 同步链路最近失败",
                detail: """
scope=project scope_id=project-alpha source=file_ipc reason=project_canonical_memory_write_failed audit_ref=audit-project-1 evidence_ref=canonical_memory_item:item-project-1 writeback_ref=canonical_memory_item:item-project-1 detail=xterminal_project_memory_write_failed=NSError:No space left on device
scope=device scope_id=supervisor source=file_ipc reason=device_canonical_memory_write_failed audit_ref=audit-device-1 detail=xterminal_device_memory_write_failed=NSError:Broken pipe
"""
            )
            let doctorPresentation = SupervisorDoctorBoardPresentationMapper.map(
                doctorStatusLine: "doctor=memory-risk",
                doctorReport: nil,
                doctorHasBlockingFindings: false,
                releaseBlockedByDoctorWithoutReport: 0,
                memoryReadiness: .init(
                    ready: false,
                    statusLine: "underfed:memory_canonical_sync_delivery_failed",
                    issues: [canonicalIssue]
                ),
                canonicalRetryFeedback: nil,
                suggestionCards: [],
                doctorReportPath: ""
            )
            let doctorDetailLine = try #require(doctorPresentation.memoryIssueDetailLine)
            #expect(doctorPresentation.memoryIssueSummaryLine == "Canonical memory 同步链路最近失败")
            #expect(doctorDetailLine.contains("audit_ref=audit-project-1"))
            #expect(doctorDetailLine.contains("evidence_ref=canonical_memory_item:item-project-1"))
            #expect(doctorDetailLine.contains("writeback_ref=canonical_memory_item:item-project-1"))

            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_memory_truth_closure_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            HubPaths.setBaseDirOverride(base)
            defer {
                HubPaths.setBaseDirOverride(nil)
                try? FileManager.default.removeItem(at: base)
            }

            try writeCanonicalSyncStatus(
                HubIPCClient.CanonicalMemorySyncStatusSnapshot(
                    schemaVersion: "canonical_memory_sync_status.v1",
                    updatedAtMs: 1_773_000_020_000,
                    items: [
                        HubIPCClient.CanonicalMemorySyncStatusItem(
                            scopeKind: "project",
                            scopeId: "project-alpha",
                            displayName: "Alpha",
                            source: "file_ipc",
                            ok: false,
                            updatedAtMs: 1_773_000_020_000,
                            reasonCode: "project_canonical_memory_write_failed",
                            detail: "xterminal_project_memory_write_failed=NSError:No space left on device",
                            auditRefs: ["audit-project-alpha-incident-1"],
                            evidenceRefs: ["canonical_memory_item:item-project-alpha-incident-1"],
                            writebackRefs: ["canonical_memory_item:item-project-alpha-incident-1"]
                        )
                    ]
                ),
                in: base
            )

            let manager = SupervisorManager.makeForTesting()
            manager.setSupervisorIncidentLedgerForTesting(makeReadyIncidentLedger())
            manager.setSupervisorMemoryAssemblySnapshotForTesting(makeMemorySnapshot())
            let xtReadySnapshot = manager.xtReadyIncidentExportSnapshot(limit: 20)
            let xtReadyDetailLine = try #require(
                xtReadySnapshot.memoryAssemblyDetailLines.first(where: { $0.contains("project_canonical_memory_write_failed") })
            )
            #expect(xtReadySnapshot.memoryAssemblyIssues.contains("memory_canonical_sync_delivery_failed"))
            #expect(xtReadyDetailLine.contains("audit_ref=audit-project-alpha-incident-1"))
            #expect(xtReadyDetailLine.contains("evidence_ref=canonical_memory_item:item-project-alpha-incident-1"))
            #expect(xtReadyDetailLine.contains("writeback_ref=canonical_memory_item:item-project-alpha-incident-1"))
            #expect(xtReadySnapshot.strictE2EIssues.contains("memory:memory_canonical_sync_delivery_failed"))

            guard let captureDir = ProcessInfo.processInfo.environment["XHUB_DOCTOR_XT_MEMORY_TRUTH_CLOSURE_CAPTURE_DIR"],
                  !captureDir.isEmpty else {
                return
            }

            let destinationRoot = URL(fileURLWithPath: captureDir, isDirectory: true)
            try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
            let evidence = XTDoctorMemoryTruthClosureEvidence(
                schemaVersion: "xt.doctor_memory_truth_closure_evidence.v1",
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                status: "pass",
                truthExamples: truthExamples,
                hubPromptProjection: .init(
                    projectionSource: promptProjection.projectionSource,
                    canonicalItemCount: promptProjection.canonicalItemCount,
                    workingSetTurnCount: promptProjection.workingSetTurnCount,
                    runtimeTruthItemCount: promptProjection.runtimeTruthItemCount,
                    runtimeTruthSourceKinds: promptProjection.runtimeTruthSourceKinds
                ),
                projectContext: .init(
                    memorySource: projectMemorySource,
                    memorySourceLabel: projectMemorySourceLabel,
                    userStatusLine: projectPresentation.userStatusLine,
                    writerGateBoundaryPresent: projectPresentation.userStatusLine.contains("Writer + Gate")
                ),
                supervisorMemory: .init(
                    memorySource: "hub",
                    modeSourceText: supervisorPresentation.modeSourceText,
                    continuityDetailLine: supervisorPresentation.continuityDetailLine ?? ""
                ),
                canonicalSyncClosure: .init(
                    doctorSummaryLine: doctorPresentation.memoryIssueSummaryLine ?? "",
                    doctorDetailLine: doctorDetailLine,
                    xtReadyDetailLine: xtReadyDetailLine,
                    auditRef: "audit-project-alpha-incident-1",
                    evidenceRef: "canonical_memory_item:item-project-alpha-incident-1",
                    writebackRef: "canonical_memory_item:item-project-alpha-incident-1",
                    strictIssueCode: "memory:memory_canonical_sync_delivery_failed"
                )
            )
            let destination = destinationRoot.appendingPathComponent("xt_doctor_memory_truth_closure_evidence.v1.json")
            try writeEvidence(evidence, to: destination)
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    @MainActor
    private func makeReadyIncidentLedger() -> [SupervisorLaneIncident] {
        [
            makeIncident(
                code: LaneBlockedReason.grantPending.rawValue,
                laneID: "lane-1",
                status: .handled,
                detectedAt: 100,
                handledAt: 900
            ),
            makeIncident(
                code: LaneBlockedReason.awaitingInstruction.rawValue,
                laneID: "lane-2",
                status: .handled,
                detectedAt: 200,
                handledAt: 800
            ),
            makeIncident(
                code: LaneBlockedReason.runtimeError.rawValue,
                laneID: "lane-3",
                status: .handled,
                detectedAt: 300,
                handledAt: 1_300
            ),
        ]
    }

    private func makeMemorySnapshot() -> SupervisorMemoryAssemblySnapshot {
        SupervisorMemoryAssemblySnapshot(
            source: "unit_test",
            resolutionSource: "unit_test",
            updatedAt: 1_773_000_000,
            reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
            requestedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
            profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
            resolvedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
            attemptedProfiles: [
                XTMemoryServingProfile.m3DeepDive.rawValue,
                XTMemoryServingProfile.m3DeepDive.rawValue
            ],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            selectedSections: [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack",
            ],
            omittedSections: [],
            contextRefsSelected: 2,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 2,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 1_800,
            usedTotalTokens: 1_050,
            truncatedLayers: [],
            freshness: "fresh_local_ipc",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "progressive_disclosure",
            durableCandidateMirrorStatus: .notNeeded,
            durableCandidateMirrorTarget: nil,
            durableCandidateMirrorAttempted: false,
            durableCandidateMirrorErrorCode: nil,
            durableCandidateLocalStoreRole: XTSupervisorDurableCandidateMirror.localStoreRole
        )
    }

    private func writeCanonicalSyncStatus(
        _ snapshot: HubIPCClient.CanonicalMemorySyncStatusSnapshot,
        in base: URL
    ) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(
            to: base.appendingPathComponent("canonical_memory_sync_status.json"),
            options: .atomic
        )
    }

    private func writeEvidence(
        _ evidence: XTDoctorMemoryTruthClosureEvidence,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(evidence)
        try data.write(to: url, options: .atomic)
    }

    private func makeIncident(
        code: String,
        laneID: String,
        status: SupervisorIncidentStatus,
        detectedAt: Int64,
        handledAt: Int64?
    ) -> SupervisorLaneIncident {
        SupervisorLaneIncident(
            id: "incident-\(UUID().uuidString.lowercased())",
            laneID: laneID,
            taskID: UUID(),
            projectID: UUID(),
            incidentCode: code,
            eventType: "supervisor.incident.\(code).handled",
            denyCode: code,
            severity: .medium,
            category: .runtime,
            autoResolvable: true,
            requiresUserAck: false,
            proposedAction: .autoRetry,
            detectedAtMs: detectedAt,
            handledAtMs: handledAt,
            takeoverLatencyMs: handledAt.map { max(0, $0 - detectedAt) },
            auditRef: "audit-\(UUID().uuidString.lowercased())",
            detail: "test",
            status: status
        )
    }
}

private struct XTDoctorMemoryTruthClosureEvidence: Codable {
    let schemaVersion: String
    let generatedAt: String
    let status: String
    let truthExamples: [XTMemoryTruthExample]
    let hubPromptProjection: XTDoctorMemoryTruthHubPromptProjectionEvidence
    let projectContext: XTDoctorMemoryTruthProjectContextEvidence
    let supervisorMemory: XTDoctorMemoryTruthSupervisorEvidence
    let canonicalSyncClosure: XTDoctorCanonicalSyncClosureEvidence
}

private struct XTMemoryTruthExample: Codable {
    let rawSource: String
    let label: String
    let explainableLabel: String
    let truthHint: String?
}

private struct XTDoctorMemoryTruthProjectContextEvidence: Codable {
    let memorySource: String
    let memorySourceLabel: String
    let userStatusLine: String
    let writerGateBoundaryPresent: Bool
}

private struct XTDoctorMemoryTruthHubPromptProjectionEvidence: Codable {
    let projectionSource: String
    let canonicalItemCount: Int
    let workingSetTurnCount: Int
    let runtimeTruthItemCount: Int
    let runtimeTruthSourceKinds: [String]
}

private struct XTDoctorMemoryTruthSupervisorEvidence: Codable {
    let memorySource: String
    let modeSourceText: String
    let continuityDetailLine: String
}

private struct XTDoctorCanonicalSyncClosureEvidence: Codable {
    let doctorSummaryLine: String
    let doctorDetailLine: String
    let xtReadyDetailLine: String
    let auditRef: String
    let evidenceRef: String
    let writebackRef: String
    let strictIssueCode: String
}
