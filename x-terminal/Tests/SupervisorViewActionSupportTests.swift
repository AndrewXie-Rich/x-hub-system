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
    func prepareConversationPromptNormalizesTextAndRequestsFocus() {
        var inputText = "stale draft"
        var focusRequestCount = 0

        SupervisorViewActionSupport.prepareConversationPrompt(
            "  创建一个project  \n",
            setInputText: { inputText = $0 },
            requestConversationFocus: { focusRequestCount += 1 }
        )

        #expect(inputText == "创建一个project")
        #expect(focusRequestCount == 1)
    }

    @Test
    func submitConversationPromptSendsMessageClearsDraftAndRequestsFocus() {
        var inputText = "stale draft"
        var sentMessages: [String] = []
        var focusRequestCount = 0

        SupervisorViewActionSupport.submitConversationPrompt(
            "  立项 \n",
            currentInputText: "  立项 \n",
            setInputText: { inputText = $0 },
            sendMessage: { sentMessages.append($0) },
            requestConversationFocus: { focusRequestCount += 1 }
        )

        #expect(inputText.isEmpty)
        #expect(sentMessages == ["立项"])
        #expect(focusRequestCount == 1)
    }

    @Test
    func submitConversationPromptPreservesDifferentExistingDraft() {
        var inputText = "继续整理上面的 blocker 分析"
        var sentMessages: [String] = []
        var focusRequestCount = 0

        SupervisorViewActionSupport.submitConversationPrompt(
            "创建一个project",
            currentInputText: inputText,
            setInputText: { inputText = $0 },
            sendMessage: { sentMessages.append($0) },
            requestConversationFocus: { focusRequestCount += 1 }
        )

        #expect(inputText == "继续整理上面的 blocker 分析")
        #expect(sentMessages == ["创建一个project"])
        #expect(focusRequestCount == 1)
    }

    @Test
    func triggerBigTaskFlowClearsDraftPreparesControlPlaneSendsPromptAndRequestsFocus() async {
        let candidate = SupervisorBigTaskCandidate(
            goal: "搭一个能自动拆工单并持续推进的 Agent 平台",
            fingerprint: "fp-big-task"
        )
        let fixture = await buildOneShotControlFixture()
        let snapshot = OneShotControlPlaneSnapshot(
            schemaVersion: "xt.one_shot_control_plane_snapshot.v1",
            normalization: fixture.normalization,
            planDecision: fixture.planning.decision,
            seatGovernor: fixture.planning.seatGovernor,
            runState: fixture.runState,
            fieldFreeze: .ai1Core
        )
        var dismissedFingerprint: String?
        var inputText = "stale draft"
        var preparedSubmission: OneShotIntakeSubmission?
        var sentMessages: [String] = []
        var focusRequestCount = 0

        await SupervisorViewActionSupport.triggerBigTaskFlow(
            candidate,
            setDismissedFingerprint: { dismissedFingerprint = $0 },
            setInputText: { inputText = $0 },
            prepareOneShotControlPlane: { submission in
                preparedSubmission = submission
                return snapshot
            },
            sendMessage: { sentMessages.append($0) },
            requestConversationFocus: { focusRequestCount += 1 }
        )

        #expect(dismissedFingerprint == candidate.fingerprint)
        #expect(inputText.isEmpty)
        let expectedSubmission = SupervisorBigTaskAssist.submission(for: candidate)
        #expect(preparedSubmission?.requestID == expectedSubmission.requestID)
        #expect(preparedSubmission?.userGoal == expectedSubmission.userGoal)
        #expect(preparedSubmission?.contextRefs == expectedSubmission.contextRefs)
        #expect(preparedSubmission?.preferredSplitProfile == expectedSubmission.preferredSplitProfile)
        #expect(preparedSubmission?.participationMode == expectedSubmission.participationMode)
        #expect(preparedSubmission?.deliveryMode == expectedSubmission.deliveryMode)
        #expect(preparedSubmission?.allowAutoLaunch == expectedSubmission.allowAutoLaunch)
        #expect(preparedSubmission?.auditRef == expectedSubmission.auditRef)
        #expect(sentMessages == [SupervisorBigTaskAssist.prompt(for: candidate, controlPlane: snapshot)])
        #expect(focusRequestCount == 1)
    }

    @Test
    func triggerBigTaskFlowBindsSelectedProjectWhenAvailable() async {
        let candidate = SupervisorBigTaskCandidate(
            goal: "继续推进当前项目的大版本改造",
            fingerprint: "fp-big-task-project"
        )
        let project = AXProjectEntry(
            projectId: "project-alpha",
            rootPath: "/tmp/project-alpha",
            displayName: "Alpha",
            lastOpenedAt: 0,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        let fixture = await buildOneShotControlFixture()
        let snapshot = OneShotControlPlaneSnapshot(
            schemaVersion: "xt.one_shot_control_plane_snapshot.v1",
            normalization: fixture.normalization,
            planDecision: fixture.planning.decision,
            seatGovernor: fixture.planning.seatGovernor,
            runState: fixture.runState,
            fieldFreeze: .ai1Core
        )
        var preparedSubmission: OneShotIntakeSubmission?
        var sentMessages: [String] = []

        await SupervisorViewActionSupport.triggerBigTaskFlow(
            candidate,
            selectedProject: project,
            setDismissedFingerprint: { _ in },
            setInputText: { _ in },
            prepareOneShotControlPlane: { submission in
                preparedSubmission = submission
                return snapshot
            },
            sendMessage: { sentMessages.append($0) },
            requestConversationFocus: {}
        )

        let expectedSubmission = SupervisorBigTaskAssist.submission(
            for: candidate,
            selectedProject: project
        )
        #expect(preparedSubmission?.projectID == project.projectId)
        #expect(preparedSubmission?.requestID == expectedSubmission.requestID)
        #expect(preparedSubmission?.contextRefs == expectedSubmission.contextRefs)
        #expect(
            sentMessages == [
                SupervisorBigTaskAssist.prompt(
                    for: candidate,
                    selectedProject: project,
                    controlPlane: snapshot
                )
            ]
        )
    }

    @Test
    func triggerBigTaskFlowLeavesNewProjectCreationRequestsUnscoped() async throws {
        let candidate = SupervisorBigTaskCandidate(
            goal: "你建立一个项目，名字就叫 坦克大战。我要用默认的MVP。",
            fingerprint: "fp-big-task-new-project"
        )
        let project = AXProjectEntry(
            projectId: "project-alpha",
            rootPath: "/tmp/project-alpha",
            displayName: "Alpha",
            lastOpenedAt: 0,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        let fixture = await buildOneShotControlFixture()
        let snapshot = OneShotControlPlaneSnapshot(
            schemaVersion: "xt.one_shot_control_plane_snapshot.v1",
            normalization: fixture.normalization,
            planDecision: fixture.planning.decision,
            seatGovernor: fixture.planning.seatGovernor,
            runState: fixture.runState,
            fieldFreeze: .ai1Core
        )
        var preparedSubmission: OneShotIntakeSubmission?
        var sentMessages: [String] = []

        await SupervisorViewActionSupport.triggerBigTaskFlow(
            candidate,
            selectedProject: project,
            setDismissedFingerprint: { _ in },
            setInputText: { _ in },
            prepareOneShotControlPlane: { submission in
                preparedSubmission = submission
                return snapshot
            },
            sendMessage: { sentMessages.append($0) },
            requestConversationFocus: {}
        )

        let expectedSubmission = SupervisorBigTaskAssist.submission(for: candidate)
        #expect(preparedSubmission?.projectID == nil)
        #expect(preparedSubmission?.requestID == expectedSubmission.requestID)
        #expect(preparedSubmission?.contextRefs == expectedSubmission.contextRefs)
        let prompt = try #require(sentMessages.first)
        #expect(!prompt.contains("bound_project_name: Alpha"))
        #expect(!prompt.contains("bound_project_id: project-alpha"))
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
