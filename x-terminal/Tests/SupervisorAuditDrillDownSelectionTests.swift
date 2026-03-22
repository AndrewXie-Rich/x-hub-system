import Foundation
import Testing
@testable import XTerminal

struct SupervisorAuditDrillDownSelectionTests {

    @Test
    func recentSkillActivitySelectionCarriesEmbeddedRecord() {
        let activity = recentSkillActivity(requestId: "req-1")
        let record = fullRecord(requestId: "req-1")

        let selection = SupervisorAuditDrillDownSelection.recentSkillActivity(
            activity,
            fullRecord: record
        )

        #expect(selection.id == activity.id)
        #expect(selection.fullRecord == record)
        #expect(selection.presentation.includesEmbeddedSkillRecord)
        #expect(selection.source == .recentSkillActivity(activity))
    }

    @Test
    func fullRecordFallbackSelectionUsesFallbackPresentationId() {
        let record = fullRecord(requestId: "req-fallback")

        let selection = SupervisorAuditDrillDownSelection.fullRecordFallback(
            projectId: "project-fallback",
            projectName: "Project Fallback",
            record: record
        )

        #expect(selection.id.contains("skill-record-fallback"))
        #expect(selection.fullRecord == record)
        #expect(selection.presentation.requestId == "req-fallback")
        #expect(selection.presentation.includesEmbeddedSkillRecord)
        #expect(selection.source == .fullRecordFallback(
            projectId: "project-fallback",
            projectName: "Project Fallback",
            record: record
        ))
    }

    @Test
    func officialSkillsChannelSelectionHasNoEmbeddedRecord() {
        let selection = SupervisorAuditDrillDownSelection.officialSkillsChannel(
            statusLine: "official healthy skills=24 auto=persisted",
            transitionLine: "current_snapshot_repaired: current snapshot restored via persisted",
            detailLine: "pkg=4 ready=2 blocked=2 active=2",
            blockerSummaries: [
                AXOfficialSkillBlockerSummaryItem(
                    packageSHA256: "sha-agent-browser",
                    title: "Agent Browser",
                    subtitle: "agent-browser",
                    stateLabel: "blocked",
                    summaryLine: "version=2.0.0 package=ready risk=high grant=required",
                    timelineLine: ""
                ),
                AXOfficialSkillBlockerSummaryItem(
                    packageSHA256: "sha-secondary",
                    title: "Secondary Skill",
                    subtitle: "skill.secondary",
                    stateLabel: "blocked",
                    summaryLine: "version=1.8.0 package=ready risk=medium grant=none",
                    timelineLine: ""
                )
            ],
            eventLoopStatusLine: "idle"
        )

        #expect(selection.source == .officialSkillsChannel)
        #expect(selection.fullRecord == nil)
        #expect(!selection.presentation.includesEmbeddedSkillRecord)
        #expect(selection.presentation.title == "Official Skills Channel")
        #expect(selection.presentation.secondaryActions.count == 1)
    }

    private func fullRecord(requestId: String) -> SupervisorSkillFullRecord {
        SupervisorSkillFullRecord(
            requestID: requestId,
            projectName: "Project Fallback",
            title: "Supervisor skill completed",
            latestStatus: "completed",
            latestStatusLabel: "Completed",
            requestMetadata: [],
            approvalFields: [],
            governanceFields: [],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [],
            approvalHistory: [],
            timeline: [],
            supervisorEvidenceJSON: nil
        )
    }

    private func recentSkillActivity(requestId: String) -> SupervisorManager.SupervisorRecentSkillActivity {
        SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: requestId,
                projectId: "project-alpha",
                jobId: "job-1",
                planId: "plan-1",
                stepId: "step-1",
                skillId: "agent-browser",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .completed,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: "done",
                denyCode: "",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-1"
            ),
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open dashboard",
            actionURL: nil,
            governance: nil
        )
    }
}
