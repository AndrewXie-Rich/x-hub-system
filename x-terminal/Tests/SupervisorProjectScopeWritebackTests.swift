import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct SupervisorProjectScopeWritebackTests {

    @Test
    func afterTurnWritebackPersistsFocusedProjectBlockerAndNextStepThroughUnifiedLane() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-project-scope-writeback")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.recordSupervisorReplyExecutionForTesting(
            mode: "remote_model",
            actualModelId: "openai/gpt-5.4"
        )

        manager.syncSupervisorAfterTurnWritebackClassificationForTesting(
            userMessage: "亮亮现在 blocker 是 grant pending，下一步是先把授权补齐。",
            responseText: "收到。",
            routingDecision: SupervisorTurnRoutingDecision(
                mode: .projectFirst,
                focusedProjectId: project.projectId,
                focusedProjectName: project.displayName,
                focusedPersonName: nil,
                focusedCommitmentId: nil,
                confidence: 0.94,
                routingReasons: ["explicit_project_mention:亮亮"]
            ),
            now: Date(timeIntervalSince1970: 1_773_820_000)
        )

        let updated = try #require(appModel.registry.project(for: project.projectId))
        #expect(updated.blockerSummary == "grant pending")
        #expect(updated.nextStepSummary == "先把授权补齐")
        #expect(manager.latestRuntimeActivity?.text.contains("after_turn project_memory") == true)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("亮亮接下来呢？")
        #expect(localMemory.contains("grant pending"))
        #expect(localMemory.contains("先把授权补齐"))
    }

    @Test
    func afterTurnWritebackPersistsFocusedProjectGoalDoneAndConstraintsThroughUnifiedLane() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-project-scope-anchor-writeback")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.recordSupervisorReplyExecutionForTesting(
            mode: "remote_model",
            actualModelId: "openai/gpt-5.4"
        )

        manager.syncSupervisorAfterTurnWritebackClassificationForTesting(
            userMessage: "亮亮目标先锁成浏览器版贪吃蛇，完成标准是能直接运行，先不做排行榜，只用原生 JS。",
            responseText: "收到。",
            routingDecision: SupervisorTurnRoutingDecision(
                mode: .projectFirst,
                focusedProjectId: project.projectId,
                focusedProjectName: project.displayName,
                focusedPersonName: nil,
                focusedCommitmentId: nil,
                confidence: 0.96,
                routingReasons: ["explicit_project_mention:亮亮"]
            ),
            now: Date(timeIntervalSince1970: 1_773_820_060)
        )

        let context = try #require(appModel.projectContext(for: project.projectId))
        let capsule = try #require(SupervisorProjectSpecCapsuleStore.load(for: context))
        #expect(capsule.goal == "浏览器版贪吃蛇")
        #expect(capsule.mvpDefinition == "能直接运行")
        #expect(capsule.nonGoals.contains("排行榜"))
        #expect(capsule.approvedTechStack.contains("原生 JS"))

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("亮亮的目标再复述一下")
        #expect(localMemory.contains("浏览器版贪吃蛇"))
        #expect(localMemory.contains("能直接运行"))
        #expect(localMemory.contains("排行榜"))
        #expect(localMemory.contains("原生 JS"))
    }

    @Test
    func afterTurnWritebackDoesNotPromoteProjectMemoryForNonUserTriggers() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-project-scope-non-user")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        manager.syncSupervisorAfterTurnWritebackClassificationForTesting(
            userMessage: "亮亮现在 blocker 是 grant pending，下一步是先把授权补齐。",
            responseText: "收到。",
            triggerSource: "heartbeat",
            routingDecision: SupervisorTurnRoutingDecision(
                mode: .projectFirst,
                focusedProjectId: project.projectId,
                focusedProjectName: project.displayName,
                focusedPersonName: nil,
                focusedCommitmentId: nil,
                confidence: 0.89,
                routingReasons: ["heartbeat_project_focus"]
            ),
            now: Date(timeIntervalSince1970: 1_773_820_120)
        )

        let unchanged = try #require(appModel.registry.project(for: project.projectId))
        #expect(unchanged.blockerSummary == nil)
        #expect(unchanged.nextStepSummary == nil)
    }

    @Test
    func afterTurnWritebackSkipsDuplicateProjectPatchAfterLocalDirectAction() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-project-scope-duplicate-skip")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let text = "现在卡在 voice wake 误触发太多，已经试过调阈值、重建 session，下一步是先把唤醒链路日志打通"
        let rendered = try #require(manager.directSupervisorActionIfApplicableForTesting(text))
        #expect(rendered.contains("当前卡点我已经记进项目现状了"))

        let context = try #require(appModel.projectContext(for: project.projectId))
        let rawLogCountBefore = rawLogLineCount(context)

        manager.recordSupervisorReplyExecutionForTesting(
            mode: "local_direct_action",
            actualModelId: nil
        )
        manager.syncSupervisorAfterTurnWritebackClassificationForTesting(
            userMessage: text,
            responseText: rendered,
            routingDecision: SupervisorTurnRoutingDecision(
                mode: .projectFirst,
                focusedProjectId: project.projectId,
                focusedProjectName: project.displayName,
                focusedPersonName: nil,
                focusedCommitmentId: nil,
                confidence: 0.96,
                routingReasons: ["explicit_project_mention:亮亮"]
            ),
            now: Date(timeIntervalSince1970: 1_773_820_240)
        )

        #expect(rawLogLineCount(context) == rawLogCountBefore)
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

    private func makeProjectEntry(root: URL, displayName: String) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: displayName,
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

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func rawLogLineCount(_ context: AXProjectContext) -> Int {
        guard let data = try? Data(contentsOf: context.rawLogURL),
              let text = String(data: data, encoding: .utf8) else {
            return 0
        }
        return text.split(whereSeparator: \.isNewline).count
    }
}
