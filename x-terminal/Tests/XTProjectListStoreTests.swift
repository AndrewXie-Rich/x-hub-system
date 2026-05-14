import Testing
@testable import XTerminal

struct XTProjectListStoreTests {
    @Test
    @MainActor
    func appModelMirrorsRegistryIntoFocusedProjectListStore() {
        let appModel = AppModel.makeForTesting()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 0,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: true,
            lastSelectedProjectId: nil,
            projects: [
                AXProjectEntry(
                    projectId: "project-a",
                    rootPath: "/tmp/project-a",
                    displayName: "Project A",
                    lastOpenedAt: 2,
                    manualOrderIndex: nil,
                    pinned: false,
                    statusDigest: nil,
                    currentStateSummary: nil,
                    nextStepSummary: nil,
                    blockerSummary: nil,
                    lastSummaryAt: nil,
                    lastEventAt: nil
                ),
                AXProjectEntry(
                    projectId: "project-b",
                    rootPath: "/tmp/project-b",
                    displayName: "Project B",
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
            ]
        )

        let snapshot = appModel.projectListStore.snapshot
        #expect(snapshot.projectCount == 2)
        #expect(snapshot.projects.map(\.projectId) == ["project-b", "project-a"])
    }

    @Test
    @MainActor
    func appModelMirrorsSelectedProjectNameIntoFocusedProjectListStore() {
        let appModel = AppModel.makeForTesting()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 0,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: true,
            lastSelectedProjectId: nil,
            projects: [
                AXProjectEntry(
                    projectId: "project-c",
                    rootPath: "/tmp/project-c",
                    displayName: "Project C",
                    lastOpenedAt: 0,
                    manualOrderIndex: nil,
                    pinned: false,
                    statusDigest: nil,
                    currentStateSummary: nil,
                    nextStepSummary: nil,
                    blockerSummary: nil,
                    lastSummaryAt: nil,
                    lastEventAt: nil
                )
            ]
        )

        appModel.selectedProjectId = "project-c"

        let snapshot = appModel.projectListStore.snapshot
        #expect(snapshot.selectedProjectId == "project-c")
        #expect(snapshot.selectedProjectName == "Project C")
    }
}
