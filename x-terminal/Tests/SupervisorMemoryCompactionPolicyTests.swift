import Foundation
import Testing
@testable import XTerminal

struct SupervisorMemoryCompactionPolicyTests {
    @Test
    func staleObservationsRollUpWhileDecisionNodesStayIntact() throws {
        let nowMs: Int64 = 1_778_300_000_000
        let nodes = [
            makeNode(
                id: "obs-old",
                kind: .observation,
                ageMs: 10 * 24 * 60 * 60 * 1_000,
                nowMs: nowMs,
                summary: "Old implementation chatter"
            ),
            makeNode(
                id: "working-fresh",
                kind: .workingSet,
                ageMs: 2 * 60 * 60 * 1_000,
                nowMs: nowMs,
                summary: "Current working set",
                active: true
            ),
            makeNode(
                id: "dec-tech-stack",
                kind: .decision,
                ageMs: 9 * 24 * 60 * 60 * 1_000,
                nowMs: nowMs,
                summary: "Formal tech stack decision",
                refs: [
                    "audit_decision_001",
                    "build/reports/xt_w3_33_f_decision_blocker_assist_evidence.v1.json"
                ],
                decisionId: "dec_001"
            ),
            makeNode(
                id: "milestone-mvp",
                kind: .milestone,
                ageMs: 8 * 24 * 60 * 60 * 1_000,
                nowMs: nowMs,
                summary: "MVP milestone",
                refs: ["build/reports/xt_w3_33_release_gate_evidence.v1.json"],
                milestoneId: "mvp"
            ),
            makeNode(
                id: "audit-rollup",
                kind: .audit,
                ageMs: 7 * 24 * 60 * 60 * 1_000,
                nowMs: nowMs,
                summary: "Audit anchor",
                refs: ["audit_compaction_001"]
            )
        ]

        let plan = SupervisorMemoryCompactionPolicy.makePlan(
            SupervisorMemoryCompactionPolicyInput(
                projectId: "proj-demo",
                projectState: .active,
                nowMs: nowMs,
                nodes: nodes
            )
        )
        let rollup = try SupervisorArchiveRollup.build(from: plan, updatedAtMs: nowMs)

        #expect(plan.archiveCandidate == false)
        #expect(plan.rollupNodes.map(\.id) == ["obs-old"])
        #expect(plan.keepNodes.map(\.id).contains("dec-tech-stack"))
        #expect(plan.keepNodes.map(\.id).contains("milestone-mvp"))
        #expect(rollup.schemaVersion == "xt.supervisor_memory_compaction_rollup.v1")
        #expect(rollup.decisionNodeLoss == 0)
        #expect(rollup.keptDecisionIds == ["dec_001"])
        #expect(rollup.keptMilestoneIds == ["mvp"])
        #expect(rollup.keptReleaseGateRefs == ["build/reports/xt_w3_33_release_gate_evidence.v1.json"])
        #expect(rollup.archivedRefs.contains("audit_compaction_001"))
    }

    @Test
    func completedProjectTurnsNoiseIntoArchiveCandidateWithoutLosingTraceability() throws {
        let nowMs: Int64 = 1_778_400_000_000
        let nodes = [
            makeNode(
                id: "obs-release-proof",
                kind: .observation,
                ageMs: 3 * 24 * 60 * 60 * 1_000,
                nowMs: nowMs,
                summary: "Old release chatter",
                refs: ["build/reports/xt_w3_33_release_gate_runtime_evidence.v1.json"]
            ),
            makeNode(
                id: "action-log",
                kind: .actionLog,
                ageMs: 2 * 24 * 60 * 60 * 1_000,
                nowMs: nowMs,
                summary: "Detailed finished run log"
            ),
            makeNode(
                id: "dec-release",
                kind: .decision,
                ageMs: 4 * 24 * 60 * 60 * 1_000,
                nowMs: nowMs,
                summary: "Ship under validated-mainline-only scope",
                refs: ["audit_release_scope_001"],
                decisionId: "dec_release_001"
            )
        ]

        let plan = SupervisorMemoryCompactionPolicy.makePlan(
            SupervisorMemoryCompactionPolicyInput(
                projectId: "proj-completed",
                projectState: .completed,
                nowMs: nowMs,
                nodes: nodes
            )
        )
        let rollup = try SupervisorArchiveRollup.build(from: plan, updatedAtMs: nowMs)

        #expect(plan.archiveCandidate == true)
        #expect(Set(plan.archiveNodes.map(\.id)) == Set(["obs-release-proof", "action-log"]))
        #expect(rollup.archiveCandidate == true)
        #expect(Set(rollup.archivedNodeIds) == Set(["obs-release-proof", "action-log"]))
        #expect(rollup.keptDecisionIds == ["dec_release_001"])
        #expect(rollup.archivedRefs.contains("build/reports/xt_w3_33_release_gate_runtime_evidence.v1.json"))
        #expect(rollup.rollupSummary.contains("archive_candidate=true"))
    }

    @Test
    func tamperedPlanFailsClosedWhenDecisionNodeWouldBeLost() {
        let nowMs: Int64 = 1_778_500_000_000
        let nodes = [
            makeNode(
                id: "dec-critical",
                kind: .decision,
                ageMs: 24 * 60 * 60 * 1_000,
                nowMs: nowMs,
                summary: "Critical decision",
                refs: ["audit_decision_loss_001"],
                decisionId: "dec_critical"
            ),
            makeNode(
                id: "obs-noise",
                kind: .observation,
                ageMs: 10 * 24 * 60 * 60 * 1_000,
                nowMs: nowMs,
                summary: "Noise"
            )
        ]
        var plan = SupervisorMemoryCompactionPolicy.makePlan(
            SupervisorMemoryCompactionPolicyInput(
                projectId: "proj-loss",
                projectState: .completed,
                nowMs: nowMs,
                nodes: nodes
            )
        )
        plan.keepNodes.removeAll { $0.id == "dec-critical" }

        let validationErrors = SupervisorArchiveRollup.validate(plan)
        #expect(validationErrors.contains { $0.contains("protected_node_loss:dec-critical") })
        #expect(validationErrors.contains { $0.contains("decision_node_loss:dec_critical") })

        do {
            _ = try SupervisorArchiveRollup.build(from: plan, updatedAtMs: nowMs)
            Issue.record("Expected fail-closed archive rollup error")
        } catch let error as SupervisorArchiveRollupError {
            switch error {
            case .failClosed(let messages):
                #expect(messages.contains { $0.contains("protected_node_loss:dec-critical") })
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeNode(
        id: String,
        kind: SupervisorMemoryNodeKind,
        ageMs: Int64,
        nowMs: Int64,
        summary: String,
        refs: [String] = [],
        decisionId: String? = nil,
        milestoneId: String? = nil,
        pinned: Bool = false,
        active: Bool = false
    ) -> SupervisorMemoryNode {
        SupervisorMemoryNode(
            id: id,
            kind: kind,
            createdAtMs: nowMs - ageMs,
            lastTouchedAtMs: nowMs - ageMs,
            summary: summary,
            refs: refs,
            decisionId: decisionId,
            milestoneId: milestoneId,
            pinned: pinned,
            active: active
        )
    }
}
