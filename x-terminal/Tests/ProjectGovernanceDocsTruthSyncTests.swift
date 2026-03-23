import Foundation
import Testing

struct ProjectGovernanceDocsTruthSyncTests {
    @Test
    func readmeUsesCurrentGovernanceNaming() throws {
        let readme = try String(
            contentsOf: repoRoot().appendingPathComponent("README.md"),
            encoding: .utf8
        )
        let terminalReadme = try String(
            contentsOf: repoRoot().appendingPathComponent("x-terminal/README.md"),
            encoding: .utf8
        )

        #expect(readme.contains("A4 Agent"))
        #expect(readme.contains("Execution Tier"))
        #expect(readme.contains("Supervisor Tier"))
        #expect(readme.contains("Heartbeat & Review"))
        #expect(!readme.contains("A4 Full Surface"))
        #expect(!readme.contains("A4 OpenClaw"))
        #expect(!readme.contains("the current governance surface already exposes"))
        #expect(!readme.contains("The active `XT-W3-36-B` child pack is finishing"))

        #expect(terminalReadme.contains("Project Governance And Supervisor Review"))
        #expect(terminalReadme.contains("Execution Tier"))
        #expect(terminalReadme.contains("Supervisor Tier"))
        #expect(terminalReadme.contains("Heartbeat & Review"))
        #expect(!terminalReadme.contains("Project Autonomy And Supervisor Review"))
    }

    @Test
    func workingMapsPointToTheActiveGovernanceSplitPack() throws {
        let root = repoRoot()
        let workingIndex = try String(
            contentsOf: root.appendingPathComponent("docs/WORKING_INDEX.md"),
            encoding: .utf8
        )
        let workOrderReadme = try String(
            contentsOf: root.appendingPathComponent("x-terminal/work-orders/README.md"),
            encoding: .utf8
        )
        let parentPack = try String(
            contentsOf: root.appendingPathComponent(
                "x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md"
            ),
            encoding: .utf8
        )

        #expect(workingIndex.contains("xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md"))
        #expect(workingIndex.contains("xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md"))
        #expect(workingIndex.contains("Execution Tier"))
        #expect(workingIndex.contains("Supervisor Tier"))
        #expect(workingIndex.contains("Heartbeat & Review"))
        #expect(workingIndex.contains("A4 Agent"))
        #expect(workingIndex.contains("XT-W3-36-B` is now completed"))
        #expect(workingIndex.contains("Use the parent `XT-W3-36` pack as the live governance roadmap"))
        #expect(workingIndex.contains("xt_w3_36_project_governance_evidence.sh"))
        #expect(workingIndex.contains("xt_release_gate.sh"))
        #expect(workingIndex.contains("ProjectGovernanceDocsTruthSyncTests.swift"))
        #expect(!workingIndex.contains("For the active XT-W3-36 UI split"))

        #expect(workOrderReadme.contains("xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md"))
        #expect(workOrderReadme.contains("A0..A4"))
        #expect(workOrderReadme.contains("S0..S4"))
        #expect(workOrderReadme.contains("A4 Agent"))
        #expect(workOrderReadme.contains("Completed child pack"))
        #expect(workOrderReadme.contains("xt_w3_36_project_governance_evidence.sh"))
        #expect(workOrderReadme.contains("xt_release_gate.sh"))
        #expect(!workOrderReadme.contains("Active child pack"))
        #expect(!workOrderReadme.contains("正在把治理入口收口"))

        #expect(parentPack.contains("- 2026-03-18:"))
        #expect(parentPack.contains("UI split child pack 已收口完成"))
    }

    @Test
    func xMemoryTracksLandedGovernanceSurfaceAndEvidence() throws {
        let xMemory = try String(
            contentsOf: repoRoot().appendingPathComponent("X_MEMORY.md"),
            encoding: .utf8
        )

        #expect(xMemory.contains("A0..A4"))
        #expect(xMemory.contains("S0..S4"))
        #expect(xMemory.contains("A4 Agent"))
        #expect(xMemory.contains("Execution Tier"))
        #expect(xMemory.contains("Supervisor Tier"))
        #expect(xMemory.contains("Heartbeat & Review"))
        #expect(xMemory.contains("xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md"))
        #expect(xMemory.contains("xt_w3_36_project_governance_evidence.sh"))
        #expect(xMemory.contains("xt_release_gate.sh"))
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
