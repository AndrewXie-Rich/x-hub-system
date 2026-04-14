import Foundation
import Testing

struct XTUnifiedDoctorContractDocsSyncTests {
    @Test
    func sourceReportContractFreezesStructuredProjectionEnvelope() throws {
        let contract = try read(
            repoRoot().appendingPathComponent(
                "docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json"
            )
        )

        #expect(contract.contains("\"xt.unified_doctor_report.v1\""))
        #expect(contract.contains("\"projectContextPresentation\""))
        #expect(contract.contains("\"hubMemoryPromptProjection\""))
        #expect(contract.contains("\"projectGovernanceRuntimeReadinessProjection\""))
        #expect(contract.contains("\"projectMemoryPolicyProjection\""))
        #expect(contract.contains("\"projectMemoryReadinessProjection\""))
        #expect(contract.contains("\"projectMemoryAssemblyResolutionProjection\""))
        #expect(contract.contains("\"heartbeatGovernanceProjection\""))
        #expect(contract.contains("\"digestVisibility\""))
        #expect(contract.contains("\"digestReasonCodes\""))
        #expect(contract.contains("\"digestWhatChangedText\""))
        #expect(contract.contains("\"projectMemoryReady\""))
        #expect(contract.contains("\"supervisorReviewTriggerProjection\""))
        #expect(contract.contains("\"supervisorMemoryPolicyProjection\""))
        #expect(contract.contains("\"supervisorMemoryAssemblyResolutionProjection\""))
        #expect(contract.contains("\"supervisorGuidanceContinuityProjection\""))
        #expect(contract.contains("\"supervisorSafePointTimelineProjection\""))
        #expect(contract.contains("\"projectRemoteSnapshotCacheProjection\""))
        #expect(contract.contains("\"supervisorRemoteSnapshotCacheProjection\""))
        #expect(contract.contains("\"memoryRouteTruthProjection\""))
        #expect(contract.contains("\"durableCandidateMirrorProjection\""))
        #expect(contract.contains("\"localStoreWriteProjection\""))
        #expect(contract.contains("\"skillDoctorTruthProjection\""))
        #expect(contract.contains("cache_provenance_only_not_memory_source_of_truth"))
        #expect(contract.contains("Structured section projections should be preferred over reparsing detailLines"))
        #expect(contract.contains("xt.unified_doctor_report_contract.v1"))
    }

    @Test
    func docsAndFixturesKeepXtSourceReportContractVisible() throws {
        let root = repoRoot()
        let readme = try read(root.appendingPathComponent("README.md"))
        let xMemory = try read(root.appendingPathComponent("X_MEMORY.md"))
        let workingIndex = try read(root.appendingPathComponent("docs/WORKING_INDEX.md"))
        let xtReadme = try read(root.appendingPathComponent("x-terminal/README.md"))
        let xhubDoctorOutputSchema = try read(
            root.appendingPathComponent("docs/memory-new/schema/xhub_doctor_output_contract.v1.json")
        )
        let ciReadme = try read(root.appendingPathComponent("scripts/ci/README.md"))
        let sourceGate = try read(root.appendingPathComponent("scripts/ci/xhub_doctor_source_gate.sh"))
        let capabilityMatrix = try read(
            root.appendingPathComponent("docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md")
        )
        let nextTen = try read(
            root.appendingPathComponent("docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md")
        )
        let v1Boundary = try read(
            root.appendingPathComponent("docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md")
        )
        let releaseChecklist = try read(
            root.appendingPathComponent("docs/open-source/OSS_RELEASE_CHECKLIST_v1.md")
        )
        let runtimePack = try read(
            root.appendingPathComponent(
                "x-terminal/work-orders/xt-assistant-runtime-alignment-implementation-pack-v1.md"
            )
        )
        let voiceProductizationPack = try read(
            root.appendingPathComponent(
                "x-terminal/work-orders/xt-w3-29-supervisor-voice-productization-gap-closure-implementation-pack-v1.md"
            )
        )
        let uiProbePack = try read(
            root.appendingPathComponent(
                "x-terminal/work-orders/xt-w3-37-agent-ui-observation-and-governed-visual-review-implementation-pack-v1.md"
            )
        )
        let voiceTtsPack = try read(
            root.appendingPathComponent(
                "x-terminal/work-orders/xt-w3-39-hub-voice-pack-and-supervisor-tts-implementation-pack-v1.md"
            )
        )
        let ironclawChecklist = try read(
            root.appendingPathComponent(
                "docs/memory-new/xhub-ironclaw-reference-adoption-checklist-v1.md"
            )
        )
        let migrationImpact = try read(
            root.appendingPathComponent(
                "docs/memory-new/xhub-memory-control-plane-migration-impact-table-v1.md"
            )
        )
        let tamImplPack = try read(
            root.appendingPathComponent(
                "docs/memory-new/xhub-trusted-automation-mode-implementation-pack-v1.md"
            )
        )
        let tamWorkOrders = try read(
            root.appendingPathComponent(
                "docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md"
            )
        )
        let tamDevicePack = try read(
            root.appendingPathComponent(
                "docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md"
            )
        )
        let remotePairingPack = try read(
            root.appendingPathComponent(
                "docs/memory-new/xhub-remote-pairing-autoreconnect-security-work-orders-v1.md"
            )
        )
        let supervisorContinuityPack = try read(
            root.appendingPathComponent(
                "x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md"
            )
        )
        let xtDoctorSource = try read(
            root.appendingPathComponent("x-terminal/Sources/UI/XTUnifiedDoctor.swift")
        )
        let xtSmoke = try read(root.appendingPathComponent("scripts/smoke_xhub_doctor_xt_source_export.sh"))
        let allSmoke = try read(root.appendingPathComponent("scripts/smoke_xhub_doctor_all_source_export.sh"))

        #expect(readme.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(readme.contains("xt.unified_doctor_report_contract.v1"))
        #expect(readme.contains("heartbeat_governance_snapshot"))
        #expect(readme.contains("latest_quality_band"))
        #expect(readme.contains("project_remote_snapshot_cache_snapshot"))
        #expect(readme.contains("supervisor_remote_snapshot_cache_snapshot"))
        #expect(readme.contains("durableCandidateMirrorProjection"))
        #expect(readme.contains("durable_candidate_mirror_snapshot"))
        #expect(readme.contains("localStoreWriteProjection"))
        #expect(readme.contains("local_store_write_snapshot"))
        #expect(readme.contains("hubMemoryPromptProjection"))
        #expect(readme.contains("hub_memory_prompt_projection"))
        #expect(readme.contains("skillDoctorTruthProjection"))
        #expect(readme.contains("skill_doctor_truth_snapshot"))

        #expect(xMemory.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(xMemory.contains("xt.unified_doctor_report_contract.v1"))
        #expect(xMemory.contains("heartbeatGovernanceProjection"))
        #expect(xMemory.contains("heartbeat_governance_snapshot"))
        #expect(xMemory.contains("projectRemoteSnapshotCacheProjection"))
        #expect(xMemory.contains("project_remote_snapshot_cache_snapshot"))
        #expect(xMemory.contains("supervisor_remote_snapshot_cache_snapshot"))
        #expect(xMemory.contains("durableCandidateMirrorProjection"))
        #expect(xMemory.contains("durable_candidate_mirror_snapshot"))
        #expect(xMemory.contains("localStoreWriteProjection"))
        #expect(xMemory.contains("local_store_write_snapshot"))
        #expect(xMemory.contains("hubMemoryPromptProjection"))
        #expect(xMemory.contains("hub_memory_prompt_projection"))
        #expect(xMemory.contains("skillDoctorTruthProjection"))
        #expect(xMemory.contains("skill_doctor_truth_snapshot"))

        #expect(workingIndex.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(workingIndex.contains("xt.unified_doctor_report_contract.v1"))
        #expect(workingIndex.contains("heartbeatGovernanceProjection"))
        #expect(workingIndex.contains("heartbeat_governance_snapshot"))
        #expect(workingIndex.contains("projectRemoteSnapshotCacheProjection"))
        #expect(workingIndex.contains("project_remote_snapshot_cache_snapshot"))
        #expect(workingIndex.contains("supervisor_remote_snapshot_cache_snapshot"))
        #expect(workingIndex.contains("durableCandidateMirrorProjection"))
        #expect(workingIndex.contains("durable_candidate_mirror_snapshot"))
        #expect(workingIndex.contains("localStoreWriteProjection"))
        #expect(workingIndex.contains("local_store_write_snapshot"))
        #expect(workingIndex.contains("hubMemoryPromptProjection"))
        #expect(workingIndex.contains("hub_memory_prompt_projection"))
        #expect(workingIndex.contains("skillDoctorTruthProjection"))
        #expect(workingIndex.contains("skill_doctor_truth_snapshot"))

        #expect(xtReadme.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(xtReadme.contains("xt.unified_doctor_report_contract.v1"))
        #expect(xtReadme.contains("heartbeat_governance_snapshot"))
        #expect(xtReadme.contains("latest_quality_band"))
        #expect(xtReadme.contains("projectRemoteSnapshotCacheProjection"))
        #expect(xtReadme.contains("project_remote_snapshot_cache_snapshot"))
        #expect(xtReadme.contains("supervisor_remote_snapshot_cache_snapshot"))
        #expect(xtReadme.contains("project_memory_policy"))
        #expect(xtReadme.contains("supervisor_memory_policy"))
        #expect(xtReadme.contains("durableCandidateMirrorProjection"))
        #expect(xtReadme.contains("durable_candidate_mirror_snapshot"))
        #expect(xtReadme.contains("localStoreWriteProjection"))
        #expect(xtReadme.contains("local_store_write_snapshot"))
        #expect(xtReadme.contains("hubMemoryPromptProjection"))
        #expect(xtReadme.contains("hub_memory_prompt_projection"))
        #expect(xtReadme.contains("skillDoctorTruthProjection"))
        #expect(xtReadme.contains("skill_doctor_truth_snapshot"))
        #expect(xhubDoctorOutputSchema.contains("\"hub_memory_prompt_projection\""))
        #expect(xhubDoctorOutputSchema.contains("\"project_governance_runtime_readiness\""))
        #expect(xhubDoctorOutputSchema.contains("\"heartbeat_governance_snapshot\""))
        #expect(xhubDoctorOutputSchema.contains("\"digest_visibility\""))
        #expect(xhubDoctorOutputSchema.contains("\"digest_reason_codes\""))
        #expect(xhubDoctorOutputSchema.contains("\"project_memory_ready\""))
        #expect(xhubDoctorOutputSchema.contains("\"supervisor_review_trigger_snapshot\""))
        #expect(xhubDoctorOutputSchema.contains("\"supervisor_guidance_continuity_snapshot\""))
        #expect(xhubDoctorOutputSchema.contains("\"supervisor_safe_point_timeline_snapshot\""))
        #expect(xhubDoctorOutputSchema.contains("\"project_remote_snapshot_cache_snapshot\""))
        #expect(xhubDoctorOutputSchema.contains("\"supervisor_remote_snapshot_cache_snapshot\""))
        #expect(xhubDoctorOutputSchema.contains("\"project_memory_policy\""))
        #expect(xhubDoctorOutputSchema.contains("\"supervisor_memory_policy\""))
        #expect(xhubDoctorOutputSchema.contains("\"local_store_write_snapshot\""))
        #expect(xhubDoctorOutputSchema.contains("\"skill_doctor_truth_snapshot\""))
        #expect(ciReadme.contains("project_remote_snapshot_cache_support"))
        #expect(ciReadme.contains("supervisor_remote_snapshot_cache_support"))
        #expect(ciReadme.contains("hub_memory_prompt_projection_support"))
        #expect(ciReadme.contains("cache provenance only"))
        #expect(ciReadme.contains("ttl_remaining_ms"))
        #expect(ciReadme.contains("digest_visibility"))
        #expect(ciReadme.contains("digest_reason_codes"))
        #expect(ciReadme.contains("project_memory_ready"))

        #expect(capabilityMatrix.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(nextTen.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(v1Boundary.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(releaseChecklist.contains("xt.unified_doctor_report_contract.v1"))
        #expect(runtimePack.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(runtimePack.contains("xt.unified_doctor_report_contract.v1"))
        #expect(voiceProductizationPack.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(uiProbePack.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(voiceTtsPack.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(ironclawChecklist.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(ironclawChecklist.contains("xt.unified_doctor_report_contract.v1"))
        #expect(migrationImpact.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(migrationImpact.contains("xt.unified_doctor_report_contract.v1"))
        #expect(tamImplPack.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(tamWorkOrders.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(tamDevicePack.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(remotePairingPack.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(supervisorContinuityPack.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(supervisorContinuityPack.contains("xhub_doctor_output_contract.v1.json"))

        #expect(xtDoctorSource.contains("XTUnifiedDoctorReportContract.frozen.schemaVersion"))
        #expect(xtDoctorSource.contains("heartbeatGovernanceProjection"))
        #expect(xtDoctorSource.contains("projectGovernanceRuntimeReadinessProjection"))
        #expect(xtDoctorSource.contains("projectMemoryPolicyProjection"))
        #expect(xtDoctorSource.contains("supervisorMemoryPolicyProjection"))
        #expect(xtDoctorSource.contains("supervisorReviewTriggerProjection"))
        #expect(xtDoctorSource.contains("supervisorGuidanceContinuityProjection"))
        #expect(xtDoctorSource.contains("supervisorSafePointTimelineProjection"))
        #expect(xtDoctorSource.contains("projectRemoteSnapshotCacheProjection"))
        #expect(xtDoctorSource.contains("supervisorRemoteSnapshotCacheProjection"))
        #expect(xtDoctorSource.contains("hubMemoryPromptProjection"))
        #expect(xtDoctorSource.contains("localStoreWriteProjection"))
        #expect(xtDoctorSource.contains("skillDoctorTruthProjection"))
        #expect(sourceGate.contains("compact_remote_snapshot_cache_snapshot"))
        #expect(sourceGate.contains("project_remote_snapshot_cache_support"))
        #expect(sourceGate.contains("supervisor_remote_snapshot_cache_support"))
        #expect(sourceGate.contains("project_remote_snapshot_cache_snapshot"))
        #expect(sourceGate.contains("supervisor_remote_snapshot_cache_snapshot"))

        #expect(xtSmoke.contains("xt.unified_doctor_report_contract.v1"))
        #expect(xtSmoke.contains("heartbeat_governance_snapshot"))
        #expect(xtSmoke.contains("project_remote_snapshot_cache_snapshot"))
        #expect(xtSmoke.contains("supervisor_remote_snapshot_cache_snapshot"))
        #expect(xtSmoke.contains("hub_memory_prompt_projection"))
        #expect(allSmoke.contains("xt.unified_doctor_report_contract.v1"))
        #expect(allSmoke.contains("xt_heartbeat_governance_snapshot"))
        #expect(allSmoke.contains("xt_project_remote_snapshot_cache_snapshot"))
        #expect(allSmoke.contains("xt_supervisor_remote_snapshot_cache_snapshot"))
        #expect(allSmoke.contains("xt_hub_memory_prompt_projection"))
        #expect(xtSmoke.contains("local_store_write_snapshot"))
        #expect(allSmoke.contains("local_store_write_snapshot"))
    }

    private func repoRoot() -> URL {
        monorepoTestRepoRoot(filePath: #filePath)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
