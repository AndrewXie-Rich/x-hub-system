import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorTurnExplainabilityStateTests {

    @Test
    func afterTurnSyncPublishesLatestRoutingAndAssemblyState() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_turn_explainability_\(UUID().uuidString).json")
        let personalStore = SupervisorPersonalMemoryStore(url: tempURL)
        personalStore.upsert(
            SupervisorPersonalMemoryRecord(
                schemaVersion: SupervisorPersonalMemoryRecord.currentSchemaVersion,
                memoryId: "relationship_alex",
                category: .relationship,
                status: .active,
                title: "Relationship: Alex = collaborator",
                detail: "Alex is waiting on the 亮亮 demo.",
                personName: "Alex",
                tags: ["relationship"],
                dueAtMs: nil,
                createdAtMs: 1,
                updatedAtMs: 1,
                auditRef: "audit-relationship-alex"
            ),
            intent: .testSeed
        )

        let manager = SupervisorManager.makeForTesting(
            supervisorPersonalMemoryStore: personalStore
        )
        let project = makeProject(id: "proj-liangliang", name: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_711_000)
        manager.syncSupervisorAfterTurnWritebackClassificationForTesting(
            userMessage: "Alex 在等亮亮 demo，我今天怎么安排？",
            responseText: "先把亮亮 demo 收口，再同步 Alex。",
            routingDecision: SupervisorTurnRoutingDecision(
                mode: .hybrid,
                focusedProjectId: project.projectId,
                focusedProjectName: project.displayName,
                focusedPersonName: "Alex",
                focusedCommitmentId: nil,
                confidence: 0.97,
                routingReasons: [
                    "explicit_project_mention:亮亮",
                    "explicit_person_mention:Alex",
                    "personal_planning_language"
                ]
            ),
            now: now
        )

        let routing = try #require(manager.supervisorLatestTurnRoutingDecisionForTesting())
        #expect(routing.mode == .hybrid)
        #expect(routing.focusedProjectId == project.projectId)
        #expect(routing.focusedProjectName == "亮亮")
        #expect(routing.focusedPersonName == "Alex")

        let assembly = try #require(manager.supervisorLatestTurnContextAssemblyForTesting())
        #expect(assembly.turnMode == .hybrid)
        #expect(assembly.focusPointers.currentProjectId == project.projectId)
        #expect(assembly.focusPointers.currentPersonName == "Alex")
        #expect(assembly.focusPointers.lastTurnMode == .hybrid)
        #expect(Set(assembly.selectedSlots) == Set([
            .dialogueWindow,
            .personalCapsule,
            .focusedProjectCapsule,
            .portfolioBrief,
            .crossLinkRefs,
            .evidencePack
        ]))
        #expect(assembly.selectedRefs.contains("dialogue_window"))
        #expect(assembly.selectedRefs.contains("personal_capsule"))
        #expect(assembly.assemblyReason.contains("hybrid_requires_cross_link_refs"))

        let writeback = try #require(manager.supervisorAfterTurnWritebackClassificationForTesting())
        #expect(writeback.candidates.first?.scope == .crossLinkScope)
        #expect(writeback.summaryLine.contains("cross_link_scope"))
    }

    @Test
    func afterTurnSyncPublishesLatestModelRouteContext() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_model_route_context_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-coder")
        config = config.settingModelOverride(role: .refine, modelId: "local/writer")
        try AXProjectStore.saveConfig(config, for: ctx)

        let manager = SupervisorManager.makeForTesting()
        let project = AXProjectEntry(
            projectId: "proj-alpha",
            rootPath: root.path,
            displayName: "Alpha",
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
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        manager.syncSupervisorAfterTurnWritebackClassificationForTesting(
            userMessage: "把 Alpha 项目的代码修一下并直接改代码",
            responseText: "已开始修代码。",
            now: Date(timeIntervalSince1970: 1_773_711_100)
        )

        let routeContext = try #require(manager.supervisorLatestModelRouteContextForTesting())
        #expect(routeContext.projectName == "Alpha")
        #expect(routeContext.decision.role == .coder)
        #expect(routeContext.decision.matchedRouteTags == ["codegen"])
        #expect(routeContext.decision.grantPolicy == .projectPolicyRequired)
        #expect(routeContext.decision.projectModelHints == ["openai/gpt-coder", "local/writer"])
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

    private func registry(with projects: [AXProjectEntry]) -> AXProjectRegistry {
        AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projects.first?.projectId,
            projects: projects
        )
    }
}
