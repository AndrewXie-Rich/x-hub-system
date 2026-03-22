import Foundation
import Testing
@testable import XTerminal

struct SupervisorFocusPointerStateTests {

    @Test
    func projectPointerCarriesAcrossFollowUpTurns() {
        let start = Date(timeIntervalSince1970: 1_773_000_000)
        let project = makeProject(id: "proj-liangliang", name: "亮亮")
        let decision1 = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "亮亮下一步怎么推进？",
                projects: [project]
            )
        )
        let state1 = SupervisorFocusPointerUpdater.update(
            previous: .empty,
            decision: decision1,
            userMessage: "亮亮下一步怎么推进？",
            projects: [project],
            personalMemory: .empty,
            now: start
        )

        #expect(state1.activeProjectId(now: start.addingTimeInterval(60)) == project.projectId)

        let followUpTime = start.addingTimeInterval(300)
        let decision2 = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "这个项目的 blocker 怎么办？",
                projects: [project],
                currentProjectId: state1.activeProjectId(now: followUpTime)
            )
        )
        #expect(decision2.mode == .projectFirst)
        #expect(decision2.focusedProjectId == project.projectId)
        #expect(decision2.routingReasons.contains("current_project_pointer:亮亮"))

        let decision3 = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "按这个继续",
                projects: [project],
                currentProjectId: state1.activeProjectId(now: followUpTime.addingTimeInterval(120))
            )
        )
        #expect(decision3.mode == .projectFirst)
        #expect(decision3.focusedProjectId == project.projectId)
    }

    @Test
    func personPointerCarriesAcrossFollowUpTurns() {
        let start = Date(timeIntervalSince1970: 1_773_000_000)
        let personalMemory = personalMemorySnapshot(relationshipPeople: ["Alex"])
        let decision1 = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "Alex 现在还在等什么？",
                projects: [],
                personalMemory: personalMemory
            )
        )
        let state1 = SupervisorFocusPointerUpdater.update(
            previous: .empty,
            decision: decision1,
            userMessage: "Alex 现在还在等什么？",
            projects: [],
            personalMemory: personalMemory,
            now: start
        )

        #expect(state1.activePersonName(now: start.addingTimeInterval(60)) == "Alex")

        let decision2 = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "他现在还在等吗？",
                projects: [],
                personalMemory: personalMemory,
                currentPersonName: state1.activePersonName(now: start.addingTimeInterval(300))
            )
        )
        #expect(decision2.mode == .personalFirst)
        #expect(decision2.focusedPersonName == "Alex")
        #expect(decision2.routingReasons.contains("current_person_pointer:Alex"))

        let decision3 = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "回他什么比较合适？",
                projects: [],
                personalMemory: personalMemory,
                currentPersonName: state1.activePersonName(now: start.addingTimeInterval(600))
            )
        )
        #expect(decision3.mode == .personalFirst)
        #expect(decision3.focusedPersonName == "Alex")
    }

    @Test
    func expiredPointerFallsBackInsteadOfForcingBinding() {
        let now = Date(timeIntervalSince1970: 1_773_000_000)
        let state = SupervisorFocusPointerState(
            schemaVersion: SupervisorFocusPointerState.currentSchemaVersion,
            updatedAtMs: Int64((now.addingTimeInterval(-3 * 60 * 60).timeIntervalSince1970 * 1000.0).rounded()),
            currentProjectId: "proj-liangliang",
            currentProjectAliases: ["亮亮", "proj-liangliang"],
            currentProjectUpdatedAtMs: Int64((now.addingTimeInterval(-3 * 60 * 60).timeIntervalSince1970 * 1000.0).rounded()),
            currentPersonName: nil,
            currentPersonUpdatedAtMs: nil,
            currentCommitmentId: nil,
            currentCommitmentUpdatedAtMs: nil,
            currentTopicDigest: "project_first: 亮亮下一步怎么推进？",
            lastTurnMode: .projectFirst,
            lastSeenDeltaCursor: "memory_build:1773000000000"
        )
        let project = makeProject(id: "proj-liangliang", name: "亮亮")

        #expect(state.activeProjectId(now: now) == nil)

        let decision = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "这个项目下一步怎么推进？",
                projects: [project],
                currentProjectId: state.activeProjectId(now: now)
            )
        )
        #expect(decision.focusedProjectId == nil)
        #expect(!decision.routingReasons.contains("current_project_pointer:亮亮"))
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

    private func personalMemorySnapshot(
        relationshipPeople: [String]
    ) -> SupervisorPersonalMemorySnapshot {
        let items = relationshipPeople.enumerated().map { index, person in
            SupervisorPersonalMemoryRecord(
                schemaVersion: SupervisorPersonalMemoryRecord.currentSchemaVersion,
                memoryId: "relationship_\(index)",
                category: .relationship,
                status: .active,
                title: "Relationship: \(person)",
                detail: "\(person) is relevant.",
                personName: person,
                tags: ["relationship"],
                dueAtMs: nil,
                createdAtMs: Int64(index + 1),
                updatedAtMs: Int64(index + 1),
                auditRef: "audit-relationship-\(index)"
            )
        }
        return SupervisorPersonalMemorySnapshot(
            schemaVersion: SupervisorPersonalMemorySnapshot.currentSchemaVersion,
            updatedAtMs: Int64(items.count),
            items: items
        )
    }
}
