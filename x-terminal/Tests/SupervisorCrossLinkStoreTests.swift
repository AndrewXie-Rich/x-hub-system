import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct SupervisorCrossLinkStoreTests {

    @Test
    func summaryBuilderSelectsFocusedHybridCrossLink() {
        let snapshot = SupervisorCrossLinkSnapshot(
            schemaVersion: SupervisorCrossLinkSnapshot.currentSchemaVersion,
            updatedAtMs: 2,
            items: [
                SupervisorCrossLinkRecord(
                    schemaVersion: SupervisorCrossLinkRecord.currentSchemaVersion,
                    linkId: "person_waiting_on_project:alex:proj-liangliang",
                    kind: .personWaitingOnProject,
                    status: .active,
                    summary: "Alex 在等亮亮 demo。",
                    personName: "Alex",
                    commitmentId: nil,
                    projectId: "proj-liangliang",
                    projectName: "亮亮",
                    backingRecordRefs: ["audit-a"],
                    createdAtMs: 1,
                    updatedAtMs: 2,
                    auditRef: "audit-a"
                ),
                SupervisorCrossLinkRecord(
                    schemaVersion: SupervisorCrossLinkRecord.currentSchemaVersion,
                    linkId: "person_waiting_on_project:sam:proj-alpha",
                    kind: .personWaitingOnProject,
                    status: .active,
                    summary: "Sam 在等 Alpha。",
                    personName: "Sam",
                    commitmentId: nil,
                    projectId: "proj-alpha",
                    projectName: "Alpha",
                    backingRecordRefs: ["audit-b"],
                    createdAtMs: 1,
                    updatedAtMs: 1,
                    auditRef: "audit-b"
                )
            ]
        )

        let summary = SupervisorCrossLinkSummaryBuilder.build(
            snapshot: snapshot,
            lastWriteObservation: SupervisorLocalMemoryWriteObservation(
                surface: .crossLink,
                intent: SupervisorCrossLinkStoreWriteIntent.afterTurnCacheRefresh.rawValue,
                updatedAtMs: 3
            ),
            projects: [
                makeProject(id: "proj-liangliang", name: "亮亮"),
                makeProject(id: "proj-alpha", name: "Alpha")
            ],
            focusedProjectId: "proj-liangliang",
            focusedPersonName: "Alex",
            focusedCommitmentId: nil,
            turnMode: .hybrid,
            now: Date(timeIntervalSince1970: 1_773_711_000)
        )

        #expect(summary.selectedCount == 1)
        #expect(summary.localStoreRole == SupervisorLocalMemoryStoreRole.rawValue)
        #expect(summary.lastLocalWriteIntent == SupervisorCrossLinkStoreWriteIntent.afterTurnCacheRefresh.rawValue)
        #expect(summary.statusLine.contains("XT local cross-link cache"))
        #expect(summary.promptContext.contains("XT local store role: \(SupervisorLocalMemoryStoreRole.rawValue)"))
        #expect(summary.promptContext.contains("Latest XT local write intent: \(SupervisorCrossLinkStoreWriteIntent.afterTurnCacheRefresh.rawValue)"))
        #expect(summary.promptContext.contains("not treat it as the durable source of truth"))
        #expect(summary.promptContext.contains("Alex 在等亮亮 demo"))
        #expect(!summary.promptContext.contains("Sam 在等 Alpha"))
    }

    @Test
    func managerPersistsCrossLinkWritebackAndSurfacesItInNextTurnMemory() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_cross_link_store_\(UUID().uuidString).json")
        let crossLinkStore = SupervisorCrossLinkStore(url: tempURL)
        let manager = SupervisorManager.makeForTesting(
            supervisorCrossLinkStore: crossLinkStore
        )
        let project = makeProject(id: "proj-liangliang", name: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_711_000)
        manager.syncSupervisorAfterTurnWritebackClassificationForTesting(
            userMessage: "Alex 在等亮亮 demo。",
            responseText: "已记住。",
            routingDecision: SupervisorTurnRoutingDecision(
                mode: .hybrid,
                focusedProjectId: project.projectId,
                focusedProjectName: project.displayName,
                focusedPersonName: "Alex",
                focusedCommitmentId: nil,
                confidence: 0.97,
                routingReasons: ["explicit_project_mention:亮亮", "explicit_person_mention:Alex"]
            ),
            now: now
        )

        let stored = try #require(crossLinkStore.snapshot.items.first)
        #expect(stored.kind == .personWaitingOnProject)
        #expect(stored.personName == "Alex")
        #expect(stored.projectId == project.projectId)
        #expect(crossLinkStore.lastWriteObservation?.surface == .crossLink)
        #expect(crossLinkStore.lastWriteObservation?.intent == SupervisorCrossLinkStoreWriteIntent.afterTurnCacheRefresh.rawValue)

        let nextDecision = manager.resolveSupervisorTurnRoutingDecisionForTesting(
            "Alex 还在等什么？",
            projects: [project],
            now: now.addingTimeInterval(60)
        )
        #expect(nextDecision.mode == .personalFirst)
        #expect(nextDecision.focusedPersonName == "Alex")

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("Alex 还在等什么？")
        #expect(localMemory.contains("[CROSS_LINK_REFS]"))
        #expect(localMemory.contains("person_waiting_on_project"))
        #expect(localMemory.contains("Alex 在等亮亮 demo"))
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
