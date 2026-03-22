import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorTurnRouterTests {

    @Test
    func routesPersonalFirstForDailyPlanning() {
        let decision = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "我今天先做什么？",
                projects: [
                    makeProject(id: "proj-liangliang", name: "亮亮")
                ]
            )
        )

        #expect(decision.mode == .personalFirst)
        #expect(decision.focusedProjectId == nil)
        #expect(decision.routingReasons.contains("personal_planning_language"))
    }

    @Test
    func routesPersonalFirstForTodayMostImportantQuestion() {
        let decision = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "帮我看下今天最重要的事",
                projects: [
                    makeProject(id: "proj-liangliang", name: "亮亮"),
                    makeProject(id: "proj-alpha", name: "Alpha")
                ]
            )
        )

        #expect(decision.mode == .personalFirst)
        #expect(decision.focusedProjectId == nil)
        #expect(decision.focusedPersonName == nil)
        #expect(decision.routingReasons.contains("personal_planning_language"))
        #expect(decision.routingReasons.contains("portfolio_review_language"))
    }

    @Test
    func routesProjectFirstForExplicitProjectProgressQuestion() {
        let project = makeProject(id: "proj-liangliang", name: "亮亮")
        let decision = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "亮亮下一步怎么推进？",
                projects: [
                    project,
                    makeProject(id: "proj-alpha", name: "Alpha")
                ]
            )
        )

        #expect(decision.mode == .projectFirst)
        #expect(decision.focusedProjectId == project.projectId)
        #expect(decision.focusedProjectName == project.displayName)
        #expect(decision.routingReasons.contains("explicit_project_mention:亮亮"))
    }

    @Test
    func routesHybridWhenProjectAndPersonPressureAppearTogether() {
        let decision = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "Alex 还在等亮亮 demo，我今天怎么安排？",
                projects: [
                    makeProject(id: "proj-liangliang", name: "亮亮")
                ],
                personalMemory: personalMemorySnapshot(
                    relationshipPeople: ["Alex"]
                )
            )
        )

        #expect(decision.mode == .hybrid)
        #expect(decision.focusedProjectName == "亮亮")
        #expect(decision.focusedPersonName == "Alex")
        #expect(decision.routingReasons.contains("explicit_project_mention:亮亮"))
        #expect(decision.routingReasons.contains("explicit_person_mention:Alex"))
    }

    @Test
    func routesPersonalFirstWhenPersonMentionComesFromCrossLinkStore() {
        let decision = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "Alex 还在等什么？",
                projects: [
                    makeProject(id: "proj-liangliang", name: "亮亮")
                ],
                personalMemory: .empty,
                crossLinks: crossLinkSnapshot(personName: "Alex", projectId: "proj-liangliang", projectName: "亮亮")
            )
        )

        #expect(decision.mode == .personalFirst)
        #expect(decision.focusedPersonName == "Alex")
        #expect(decision.routingReasons.contains("explicit_person_mention:Alex"))
    }

    @Test
    func routesPortfolioReviewForOverallPriorityQuestion() {
        let decision = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "现在整体先抓什么？",
                projects: [
                    makeProject(id: "proj-liangliang", name: "亮亮"),
                    makeProject(id: "proj-alpha", name: "Alpha")
                ]
            )
        )

        #expect(decision.mode == .portfolioReview)
        #expect(decision.focusedProjectId == nil)
        #expect(decision.routingReasons.contains("portfolio_review_language"))
    }

    @Test
    func doesNotFabricateFocusForAmbiguousTurnWithoutSignals() {
        let decision = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "接下来呢？",
                projects: [
                    makeProject(id: "proj-liangliang", name: "亮亮"),
                    makeProject(id: "proj-alpha", name: "Alpha")
                ]
            )
        )

        #expect(decision.mode == .personalFirst)
        #expect(decision.focusedProjectId == nil)
        #expect(decision.focusedProjectName == nil)
        #expect(decision.focusedPersonName == nil)
        #expect(decision.focusedCommitmentId == nil)
        #expect(decision.routingReasons == ["default_personal_fallback"])
    }

    @Test
    func usesCurrentProjectPointerForThisProjectLanguage() {
        let project = makeProject(id: "proj-liangliang", name: "亮亮")
        let decision = SupervisorTurnRouter.route(
            SupervisorTurnRoutingInput(
                userMessage: "这个项目下一步怎么推进？",
                projects: [project],
                currentProjectId: project.projectId
            )
        )

        #expect(decision.mode == .projectFirst)
        #expect(decision.focusedProjectId == project.projectId)
        #expect(decision.routingReasons.contains("current_project_pointer:亮亮"))
    }

    @Test
    func managerInjectsTurnRoutingHintIntoPrompt() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_turn_router_prompt_\(UUID().uuidString).json")
        let store = SupervisorPersonalMemoryStore(url: tempURL)
        let alex = SupervisorPersonalMemoryRecord(
            schemaVersion: SupervisorPersonalMemoryRecord.currentSchemaVersion,
            memoryId: "relationship_alex",
            category: .relationship,
            status: .active,
            title: "Relationship: Alex = collaborator",
            detail: "Alex is a collaborator.",
            personName: "Alex",
            tags: ["relationship"],
            dueAtMs: nil,
            createdAtMs: 1,
            updatedAtMs: 1,
            auditRef: "audit-relationship-alex"
        )
        store.upsert(alex)

        let manager = SupervisorManager.makeForTesting(
            supervisorPersonalMemoryStore: store
        )
        let prompt = manager.buildSupervisorSystemPromptForTesting(
            "Alex 还在等亮亮 demo，我今天怎么安排？",
            projects: [
                makeProject(id: "proj-liangliang", name: "亮亮")
            ]
        )

        #expect(prompt.contains("## Turn Routing Hint"))
        #expect(prompt.contains("Dominant turn mode: hybrid"))
        #expect(prompt.contains("Focused project: 亮亮"))
        #expect(prompt.contains("Focused person: Alex"))
        #expect(prompt.contains("Treat personal memory and project memory as co-equal inputs for this turn."))
    }

    @Test
    func managerUsesStoredProjectFocusPointerForPromptRouting() {
        let manager = SupervisorManager.makeForTesting()
        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        manager.setSupervisorFocusPointerStateForTesting(
            SupervisorFocusPointerState(
                schemaVersion: SupervisorFocusPointerState.currentSchemaVersion,
                updatedAtMs: nowMs,
                currentProjectId: "proj-liangliang",
                currentProjectAliases: ["亮亮", "proj-liangliang"],
                currentProjectUpdatedAtMs: nowMs,
                currentPersonName: nil,
                currentPersonUpdatedAtMs: nil,
                currentCommitmentId: nil,
                currentCommitmentUpdatedAtMs: nil,
                currentTopicDigest: "project_first: 亮亮下一步怎么推进？",
                lastTurnMode: .projectFirst,
                lastSeenDeltaCursor: "memory_build:\(nowMs)"
            )
        )

        let prompt = manager.buildSupervisorSystemPromptForTesting(
            "这个项目下一步怎么推进？",
            projects: [
                makeProject(id: "proj-liangliang", name: "亮亮")
            ]
        )

        #expect(prompt.contains("Dominant turn mode: project_first"))
        #expect(prompt.contains("Focused project: 亮亮"))
        #expect(prompt.contains("current_project_pointer:亮亮"))
    }

    @Test
    func managerUsesStoredPersonFocusPointerForPromptRouting() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_turn_router_person_prompt_\(UUID().uuidString).json")
        let store = SupervisorPersonalMemoryStore(url: tempURL)
        store.upsert(
            SupervisorPersonalMemoryRecord(
                schemaVersion: SupervisorPersonalMemoryRecord.currentSchemaVersion,
                memoryId: "relationship_alex",
                category: .relationship,
                status: .active,
                title: "Relationship: Alex = collaborator",
                detail: "Alex is a collaborator.",
                personName: "Alex",
                tags: ["relationship"],
                dueAtMs: nil,
                createdAtMs: 1,
                updatedAtMs: 1,
                auditRef: "audit-relationship-alex"
            )
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorPersonalMemoryStore: store
        )
        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        manager.setSupervisorFocusPointerStateForTesting(
            SupervisorFocusPointerState(
                schemaVersion: SupervisorFocusPointerState.currentSchemaVersion,
                updatedAtMs: nowMs,
                currentProjectId: nil,
                currentProjectAliases: [],
                currentProjectUpdatedAtMs: nil,
                currentPersonName: "Alex",
                currentPersonUpdatedAtMs: nowMs,
                currentCommitmentId: nil,
                currentCommitmentUpdatedAtMs: nil,
                currentTopicDigest: "personal_first: Alex 现在还在等什么？",
                lastTurnMode: .personalFirst,
                lastSeenDeltaCursor: nil
            )
        )

        let prompt = manager.buildSupervisorSystemPromptForTesting("他现在还在等吗？")

        #expect(prompt.contains("Dominant turn mode: personal_first"))
        #expect(prompt.contains("Focused person: Alex"))
        #expect(prompt.contains("current_person_pointer:Alex"))
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

    private func crossLinkSnapshot(
        personName: String,
        projectId: String,
        projectName: String
    ) -> SupervisorCrossLinkSnapshot {
        SupervisorCrossLinkSnapshot(
            schemaVersion: SupervisorCrossLinkSnapshot.currentSchemaVersion,
            updatedAtMs: 1,
            items: [
                SupervisorCrossLinkRecord(
                    schemaVersion: SupervisorCrossLinkRecord.currentSchemaVersion,
                    linkId: "person_waiting_on_project:\(personName.lowercased()):\(projectId)",
                    kind: .personWaitingOnProject,
                    status: .active,
                    summary: "\(personName) 在等 \(projectName)。",
                    personName: personName,
                    commitmentId: nil,
                    projectId: projectId,
                    projectName: projectName,
                    backingRecordRefs: ["audit-cross-link"],
                    createdAtMs: 1,
                    updatedAtMs: 1,
                    auditRef: "audit-cross-link"
                )
            ]
        )
    }
}
