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
        #expect(contract.contains("\"memoryRouteTruthProjection\""))
        #expect(contract.contains("\"durableCandidateMirrorProjection\""))
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
        #expect(readme.contains("durableCandidateMirrorProjection"))
        #expect(readme.contains("durable_candidate_mirror_snapshot"))

        #expect(xMemory.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(xMemory.contains("xt.unified_doctor_report_contract.v1"))
        #expect(xMemory.contains("durableCandidateMirrorProjection"))
        #expect(xMemory.contains("durable_candidate_mirror_snapshot"))

        #expect(workingIndex.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(workingIndex.contains("xt.unified_doctor_report_contract.v1"))
        #expect(workingIndex.contains("durableCandidateMirrorProjection"))
        #expect(workingIndex.contains("durable_candidate_mirror_snapshot"))

        #expect(xtReadme.contains("xt_unified_doctor_report_contract.v1.json"))
        #expect(xtReadme.contains("xt.unified_doctor_report_contract.v1"))
        #expect(xtReadme.contains("durableCandidateMirrorProjection"))
        #expect(xtReadme.contains("durable_candidate_mirror_snapshot"))

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

        #expect(xtSmoke.contains("xt.unified_doctor_report_contract.v1"))
        #expect(allSmoke.contains("xt.unified_doctor_report_contract.v1"))
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
