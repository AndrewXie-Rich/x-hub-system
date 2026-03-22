import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorViewActionSupportTests {

    @Test
    func dashboardPanelMaxHeightClampsToExpectedBounds() {
        #expect(SupervisorViewActionSupport.dashboardPanelMaxHeight(totalHeight: 100) == 180)
        #expect(SupervisorViewActionSupport.dashboardPanelMaxHeight(totalHeight: 600) == 252)
        #expect(SupervisorViewActionSupport.dashboardPanelMaxHeight(totalHeight: 2_000) == 360)
    }

    @Test
    func triggerBigTaskFlowClearsDraftSendsPromptAndRequestsFocus() {
        let candidate = SupervisorBigTaskCandidate(
            goal: "搭一个能自动拆工单并持续推进的 Agent 平台",
            fingerprint: "fp-big-task"
        )
        var dismissedFingerprint: String?
        var inputText = "stale draft"
        var sentMessages: [String] = []
        var focusRequestCount = 0

        SupervisorViewActionSupport.triggerBigTaskFlow(
            candidate,
            setDismissedFingerprint: { dismissedFingerprint = $0 },
            setInputText: { inputText = $0 },
            sendMessage: { sentMessages.append($0) },
            requestConversationFocus: { focusRequestCount += 1 }
        )

        #expect(dismissedFingerprint == candidate.fingerprint)
        #expect(inputText.isEmpty)
        #expect(sentMessages == [SupervisorBigTaskAssist.prompt(for: candidate)])
        #expect(focusRequestCount == 1)
    }

    @Test
    func performAutomationRuntimeActionUsesResolvedCommand() {
        var commands: [String] = []

        SupervisorViewActionSupport.performAutomationRuntimeAction(
            .advance(.blocked),
            runCommand: { commands.append($0) }
        )

        #expect(commands == [SupervisorAutomationRuntimeActionResolver.command(for: .advance(.blocked))])
    }

    @Test
    func performLaneHealthRowActionRoutesToExpectedHandler() {
        let projectURL = URL(string: "xt://project/project-alpha")!
        var openedURLs: [URL] = []
        var focusedLaneIDs: [String] = []

        SupervisorViewActionSupport.performLaneHealthRowAction(
            .openProject(projectURL),
            openProject: { openedURLs.append($0) },
            focusLane: { focusedLaneIDs.append($0) }
        )
        SupervisorViewActionSupport.performLaneHealthRowAction(
            .focusLane("lane-42"),
            openProject: { openedURLs.append($0) },
            focusLane: { focusedLaneIDs.append($0) }
        )

        #expect(openedURLs == [projectURL])
        #expect(focusedLaneIDs == ["lane-42"])
    }

    @Test
    func refreshSelectedPortfolioDrillDownStabilizesSelectionAndScopeBeforeBuilding() throws {
        let now = Date(timeIntervalSince1970: 1_773_900_000).timeIntervalSince1970
        let manager = SupervisorManager.makeForTesting()
        let appModel = AppModel()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_view_action_support_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let project = AXProjectEntry(
            projectId: "project-alpha",
            rootPath: projectRoot.path,
            displayName: "Alpha",
            lastOpenedAt: now,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "working",
            currentStateSummary: "Wiring supervisor view",
            nextStepSummary: "Render structured drill-down",
            blockerSummary: nil,
            lastSummaryAt: now,
            lastEventAt: now
        )

        let ctx = AXProjectContext(root: projectRoot)
        try ctx.ensureDirs()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: now,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: true,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let digest = manager.supervisorMemoryDigestForTesting(project)
        manager.setSupervisorCanonicalMemoryRetryStateForTesting(
            digests: [digest],
            portfolioSnapshot: SupervisorPortfolioSnapshotBuilder.build(from: [digest], now: now)
        )
        _ = manager.applySupervisorJurisdictionRegistry(
            SupervisorJurisdictionRegistry.ownerDefault(now: now)
                .upserting(
                    projectId: project.projectId,
                    displayName: project.displayName,
                    role: .observer,
                    now: now
                ),
            persist: false,
            normalizeWithKnownProjects: false
        )

        var selectedProjectID: String?
        var selectedScope: SupervisorProjectDrillDownScope = .rawEvidence

        SupervisorViewActionSupport.refreshSelectedPortfolioDrillDown(
            supervisor: manager,
            selectedProjectID: selectedProjectID,
            selectedScope: selectedScope,
            setSelectedProjectID: { selectedProjectID = $0 },
            setSelectedScope: { selectedScope = $0 }
        )

        #expect(selectedProjectID == project.projectId)
        #expect(selectedScope == .rawEvidence)
        #expect(manager.supervisorLastProjectDrillDownSnapshot == nil)

        SupervisorViewActionSupport.refreshSelectedPortfolioDrillDown(
            supervisor: manager,
            selectedProjectID: selectedProjectID,
            selectedScope: selectedScope,
            setSelectedProjectID: { selectedProjectID = $0 },
            setSelectedScope: { selectedScope = $0 }
        )

        #expect(selectedProjectID == project.projectId)
        #expect(selectedScope == .capsuleOnly)
        #expect(manager.supervisorLastProjectDrillDownSnapshot == nil)

        SupervisorViewActionSupport.refreshSelectedPortfolioDrillDown(
            supervisor: manager,
            selectedProjectID: selectedProjectID,
            selectedScope: selectedScope,
            setSelectedProjectID: { selectedProjectID = $0 },
            setSelectedScope: { selectedScope = $0 }
        )

        let drillDown = try #require(manager.supervisorLastProjectDrillDownSnapshot)
        #expect(drillDown.projectId == project.projectId)
        #expect(drillDown.status == .allowed)
        #expect(drillDown.requestedScope == .capsuleOnly)
    }
}
