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

    @Test
    @MainActor
    func appModelMirrorsProjectSidebarProjectionIntoFocusedStore() {
        let appModel = AppModel.makeForTesting()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 0,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: true,
            lastSelectedProjectId: nil,
            projects: [
                makeProjectEntry(
                    projectId: "project-d",
                    rootPath: "/tmp/project-d",
                    displayName: "Project D",
                    lastOpenedAt: 0,
                    statusDigest: "running"
                )
            ]
        )

        appModel.selectedProjectId = "project-d"

        let projection = appModel.projectSidebarProjectionStore.snapshot
        #expect(projection.selectedProjectId == "project-d")
        #expect(projection.projectCountText == "1")
        #expect(projection.rows.map(\.id) == ["project-d"])
        #expect(projection.rows.first?.displayName == "Project D")
        #expect(projection.rows.first?.isSelected == true)
        #expect(projection.rows.first?.statusDigest == "running")
    }

    @Test
    func projectSidebarProjectionLoadsSupplementalOnlyForSelectedLoadedProject() {
        let projects = [
            makeProjectEntry(
                projectId: "project-a",
                rootPath: "/tmp/project-a",
                displayName: "Project A",
                lastOpenedAt: 2,
                statusDigest: "active"
            ),
            makeProjectEntry(
                projectId: "project-b",
                rootPath: "/tmp/project-b",
                displayName: "Project B",
                lastOpenedAt: 1,
                statusDigest: "idle"
            )
        ]
        let projectListSnapshot = XTProjectListSnapshot(
            selectedProjectId: "project-a",
            projects: projects,
            selectedProjectName: "Project A"
        )
        let workSurfaceSnapshot = XTWorkSurfaceSnapshot(
            selectedProjectId: "project-a",
            projectContext: nil,
            memory: nil,
            projectConfig: nil,
            isMultiProjectViewEnabled: false,
            selectedPane: .chat
        )
        var governanceRequests: [String] = []
        var summaryRequests: [String] = []

        let projection = XTCoreProjectSidebarProjectionBuilder.build(
            projectListSnapshot: projectListSnapshot,
            workSurfaceSnapshot: workSurfaceSnapshot,
            governancePresentation: { project in
                governanceRequests.append(project.projectId)
                return ProjectGovernancePresentation(
                    executionTier: .a4OpenClaw,
                    supervisorInterventionTier: .s3StrategicCoach,
                    reviewPolicyMode: .hybrid,
                    progressHeartbeatSeconds: 600,
                    reviewPulseSeconds: 1_200,
                    brainstormReviewSeconds: 2_400,
                    eventDrivenReviewEnabled: true
                )
            },
            sessionSummaryPresentation: { project in
                summaryRequests.append(project.projectId)
                return AXSessionSummaryCapsulePresentation(
                    reason: "project_switch",
                    createdAtMs: 1_700_000_000_000
                )
            }
        )

        #expect(governanceRequests == ["project-a"])
        #expect(summaryRequests == ["project-a"])
        #expect(projection.rows.count == 2)
        #expect(projection.rows[0].statusDigest == "active")
        #expect(projection.rows[0].resumeBadgeText?.hasPrefix("最近交接：切项目") == true)
        #expect(projection.rows[0].governance?.executionTierToken == "A4")
        #expect(projection.rows[0].governance?.supervisorTierToken == "S3")
        #expect(projection.rows[1].statusDigest == nil)
        #expect(projection.rows[1].resumeBadgeText == nil)
        #expect(projection.rows[1].governance == nil)
    }

    private func makeProjectEntry(
        projectId: String,
        rootPath: String,
        displayName: String,
        lastOpenedAt: Double,
        statusDigest: String? = nil
    ) -> AXProjectEntry {
        AXProjectEntry(
            projectId: projectId,
            rootPath: rootPath,
            displayName: displayName,
            lastOpenedAt: lastOpenedAt,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: statusDigest,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
    }
}
