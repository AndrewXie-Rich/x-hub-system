import Foundation
import Testing
@testable import XTerminal

struct SupervisorProjectCapsuleCanonicalSyncTests {
    @Test
    func itemsIncludeStableCapsuleKeysAndSummaryJSON() throws {
        let capsule = SupervisorProjectCapsule(
            schemaVersion: SupervisorProjectCapsule.schemaVersion,
            projectId: "p-1",
            projectName: "Project One",
            projectState: .blocked,
            goal: "Ship portfolio awareness",
            currentPhase: "blocked",
            currentAction: "等待 Hub 依赖样本",
            topBlocker: "missing_require_real_sample",
            nextStep: "Run RR sample",
            memoryFreshness: .ttlCached,
            updatedAtMs: 123_456,
            statusDigest: "goal=Ship; action=等待 Hub 依赖样本",
            evidenceRefs: ["build/reports/xt_w3_31_b_project_capsule_evidence.v1.json"],
            auditRef: "supervisor_project_capsule:p1:123456"
        )

        let items = SupervisorProjectCapsuleCanonicalSync.items(capsule: capsule)
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0.value) })

        #expect(lookup["xterminal.project.capsule.project_state"] == "blocked")
        #expect(lookup["xterminal.project.capsule.memory_freshness"] == "ttl_cached")
        #expect(lookup["xterminal.project.capsule.audit_ref"] == "supervisor_project_capsule:p1:123456")
        #expect(lookup["xterminal.project.capsule.evidence_refs"] == "1. build/reports/xt_w3_31_b_project_capsule_evidence.v1.json")

        let summary = try #require(lookup["xterminal.project.capsule.summary_json"])
        let summaryData = try #require(summary.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SupervisorProjectCapsule.self, from: summaryData)
        #expect(decoded.projectId == "p-1")
        #expect(decoded.projectState == .blocked)
        #expect(decoded.nextStep == "Run RR sample")
    }

    @Test
    func itemsSkipEmptyEvidenceRefs() {
        let capsule = SupervisorProjectCapsule(
            schemaVersion: SupervisorProjectCapsule.schemaVersion,
            projectId: "p-2",
            projectName: "Project Two",
            projectState: .idle,
            goal: "Keep sync cheap",
            currentPhase: "queued",
            currentAction: "排队中（等待 Hub 执行）",
            topBlocker: "(无)",
            nextStep: "继续当前任务",
            memoryFreshness: .fresh,
            updatedAtMs: 999,
            statusDigest: "goal=Keep sync cheap",
            evidenceRefs: [],
            auditRef: "supervisor_project_capsule:p2:999"
        )

        let items = SupervisorProjectCapsuleCanonicalSync.items(capsule: capsule)
        let keys = Set(items.map(\.key))

        #expect(keys.contains("xterminal.project.capsule.summary_json"))
        #expect(keys.contains("xterminal.project.capsule.current_action"))
        #expect(!keys.contains("xterminal.project.capsule.evidence_refs"))
    }
}
