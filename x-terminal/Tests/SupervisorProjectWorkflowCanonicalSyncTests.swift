import Foundation
import Testing
@testable import XTerminal

struct SupervisorProjectWorkflowCanonicalSyncTests {
    @Test
    func itemsIncludeLastSkillResultRefAndStatus() throws {
        let job = SupervisorJobRecord(
            schemaVersion: SupervisorJobRecord.currentSchemaVersion,
            jobId: "job-1",
            projectId: "p-1",
            goal: "Run governed workflow",
            priority: .high,
            status: .running,
            source: .supervisor,
            currentOwner: "supervisor",
            activePlanId: "plan-1",
            createdAtMs: 100,
            updatedAtMs: 300,
            auditRef: "audit-job-1"
        )
        let step = SupervisorPlanStepRecord(
            schemaVersion: SupervisorPlanStepRecord.currentSchemaVersion,
            stepId: "step-1",
            title: "Run project snapshot",
            kind: .callSkill,
            status: .completed,
            skillId: "project.snapshot",
            currentOwner: "supervisor",
            detail: "done",
            orderIndex: 0,
            updatedAtMs: 320
        )
        let plan = SupervisorPlanRecord(
            schemaVersion: SupervisorPlanRecord.currentSchemaVersion,
            planId: "plan-1",
            jobId: "job-1",
            projectId: "p-1",
            status: .completed,
            currentOwner: "supervisor",
            steps: [step],
            createdAtMs: 110,
            updatedAtMs: 320,
            auditRef: "audit-plan-1"
        )
        let skillCall = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "req-1",
            projectId: "p-1",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "project.snapshot",
            toolName: "project_snapshot",
            status: .completed,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "project snapshot completed",
            denyCode: "",
            resultEvidenceRef: "local://supervisor_skill_results/req-1.json",
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 120,
            updatedAtMs: 330,
            auditRef: "audit-skill-1"
        )

        let snapshot = try #require(
            SupervisorProjectWorkflowCanonicalSync.snapshot(
                projectId: "p-1",
                projectName: "Project One",
                jobSnapshot: SupervisorProjectJobSnapshot(
                    schemaVersion: SupervisorProjectJobSnapshot.currentSchemaVersion,
                    updatedAtMs: 300,
                    jobs: [job]
                ),
                planSnapshot: SupervisorProjectPlanSnapshot(
                    schemaVersion: SupervisorProjectPlanSnapshot.currentSchemaVersion,
                    updatedAtMs: 320,
                    plans: [plan]
                ),
                skillCallSnapshot: SupervisorProjectSkillCallSnapshot(
                    schemaVersion: SupervisorProjectSkillCallSnapshot.currentSchemaVersion,
                    updatedAtMs: 330,
                    calls: [skillCall]
                )
            )
        )

        let items = SupervisorProjectWorkflowCanonicalSync.items(snapshot: snapshot)
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0.value) })

        #expect(lookup["xterminal.project.supervisor_workflow.last_skill_status"] == "completed")
        #expect(lookup["xterminal.project.supervisor_workflow.last_skill_result_ref"] == "local://supervisor_skill_results/req-1.json")

        let summary = try #require(lookup["xterminal.project.supervisor_workflow.summary_json"])
        let summaryData = try #require(summary.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SupervisorProjectWorkflowSnapshot.self, from: summaryData)
        #expect(decoded.activeSkillCall?.resultEvidenceRef == "local://supervisor_skill_results/req-1.json")
    }

    @Test
    func itemsSkipLastSkillResultRefWhenMissing() {
        let snapshot = SupervisorProjectWorkflowSnapshot(
            projectId: "p-2",
            projectName: "Project Two",
            updatedAtMs: 999,
            activeJob: nil,
            activePlan: nil,
            activeSkillCall: nil,
            auditRef: "audit-empty"
        )

        let keys = Set(SupervisorProjectWorkflowCanonicalSync.items(snapshot: snapshot).map(\.key))
        #expect(!keys.contains("xterminal.project.supervisor_workflow.last_skill_result_ref"))
        #expect(!keys.contains("xterminal.project.supervisor_workflow.last_skill_status"))
    }
}
