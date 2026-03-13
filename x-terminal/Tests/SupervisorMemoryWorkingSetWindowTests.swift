import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct SupervisorMemoryWorkingSetWindowTests {

    @Test
    func localMemoryWorkingSetKeepsEightUserTurnsByDefault() async {
        let manager = SupervisorManager.makeForTesting()
        manager.messages = makeConversation(turns: 10)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续推进当前项目")
        let lines = Set(localMemory.split(separator: "\n").map(String.init))

        #expect(!lines.contains("user: user-turn-1"))
        #expect(!lines.contains("assistant: assistant-turn-2"))
        #expect(lines.contains("user: user-turn-3"))
        #expect(lines.contains("assistant: assistant-turn-10"))
        #expect(lines.contains("system: system-turn-10"))
    }

    @Test
    func explicitCrossProjectDrillDownAddsStructuredWorkingSetNotFullHistory() async throws {
        let now = Date(timeIntervalSince1970: 1_773_500_500).timeIntervalSince1970
        let manager = SupervisorManager.makeForTesting()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w3_35_cross_drill_\(UUID().uuidString)")
        let project = AXProjectEntry(
            projectId: "p-cross",
            rootPath: projectRoot.path,
            displayName: "Cross Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "blocked",
            currentStateSummary: "waiting on structured drill-down",
            nextStepSummary: "review plan summary",
            blockerSummary: "cross-project context is still digest-only",
            lastSummaryAt: now,
            lastEventAt: now
        )
        let ctx = AXProjectContext(root: projectRoot)
        try ctx.ensureDirs()
        try SupervisorProjectSpecCapsuleStore.upsert(
            SupervisorProjectSpecCapsuleBuilder.build(
                projectId: project.projectId,
                goal: "Let supervisor inspect another project without full chat history",
                mvpDefinition: "Inject explicit structured drill-down block",
                nonGoals: ["Do not inject raw logs"],
                approvedTechStack: ["Swift"],
                milestoneMap: [
                    SupervisorProjectSpecMilestone(
                        milestoneId: "ms-cross-1",
                        title: "cross-project drill-down",
                        status: .active
                    )
                ]
            ),
            for: ctx
        )
        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .owner, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(registry, persist: false, normalizeWithKnownProjects: false)
        _ = manager.buildSupervisorProjectDrillDown(
            for: project,
            requestedScope: .capsuleOnly,
            openedReason: "cross_project_review"
        )

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("看另一个项目的结构化摘要")

        #expect(localMemory.contains("[cross_project_drilldown]"))
        #expect(localMemory.contains("mode=explicit_structured_drilldown"))
        #expect(localMemory.contains("reason=cross_project_review"))
        #expect(localMemory.contains("project=Cross Project (p-cross)"))
        #expect(localMemory.contains("spec_goal=Let supervisor inspect another project without full chat history"))
        #expect(localMemory.contains("scope_safe_refs:"))
        #expect(!localMemory.contains("raw_log.jsonl"))
    }

    @Test
    func reviewProfileExpandsSupervisorConversationWindowBeyondDefaultEightTurns() async {
        let manager = SupervisorManager.makeForTesting()
        manager.messages = makeConversation(turns: 14)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "审查当前项目的上下文记忆，给出最具体的执行方案"
        )
        let lines = Set(localMemory.split(separator: "\n").map(String.init))

        #expect(!lines.contains("user: user-turn-2"))
        #expect(lines.contains("user: user-turn-3"))
        #expect(lines.contains("assistant: assistant-turn-3"))
        #expect(lines.contains("system: system-turn-14"))
    }

    @Test
    func focusedProjectReviewAutoAddsGovernedRetrievalSnippets() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-retrieval")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        HubIPCClient.installMemoryRetrievalOverrideForTesting { payload, _ in
            HubIPCClient.MemoryRetrievalResponsePayload(
                source: "test_supervisor_retrieval",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: nil,
                denyCode: nil,
                snippets: [
                    HubIPCClient.MemoryRetrievalSnippet(
                        snippetId: "snippet-1",
                        sourceKind: "decision_track",
                        title: "approved architecture direction",
                        ref: "memory://decision/proj-liang/dec-1",
                        text: "Use governed project phases: scan, isolate, refactor, verify.",
                        score: 97,
                        truncated: false
                    ),
                    HubIPCClient.MemoryRetrievalSnippet(
                        snippetId: "snippet-2",
                        sourceKind: "project_spec_capsule",
                        title: "tech stack capsule",
                        ref: "memory://spec/proj-liang/capsule",
                        text: "Current stack is Swift + governed Hub memory orchestration.",
                        score: 92,
                        truncated: false
                    )
                ],
                truncatedItems: 0,
                redactedItems: 0
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "审查亮亮项目的上下文记忆，给出最具体的执行方案"
        )

        #expect(localMemory.contains("[focused_project_retrieval]"))
        #expect(localMemory.contains("focus_project=亮亮 (\(project.projectId))"))
        #expect(localMemory.contains("retrieval_source=test_supervisor_retrieval"))
        #expect(localMemory.contains("[decision_track] approved architecture direction"))
        #expect(localMemory.contains("Use governed project phases: scan, isolate, refactor, verify."))
        #expect(localMemory.contains("[project_spec_capsule] tech stack capsule"))
    }

    @Test
    func focusedProjectReviewSurfacesRetrievalDenyMetadata() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-retrieval-denied")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        HubIPCClient.installMemoryRetrievalOverrideForTesting { payload, _ in
            HubIPCClient.MemoryRetrievalResponsePayload(
                source: "test_supervisor_retrieval",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: "scope_gate",
                denyCode: "cross_scope_memory_denied",
                snippets: [],
                truncatedItems: 0,
                redactedItems: 0
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "审查亮亮项目的上下文记忆，给出最具体的执行方案"
        )

        #expect(localMemory.contains("[focused_project_retrieval]"))
        #expect(localMemory.contains("focus_project=亮亮 (\(project.projectId))"))
        #expect(localMemory.contains("status=denied"))
        #expect(localMemory.contains("reason_code=scope_gate"))
        #expect(localMemory.contains("deny_code=cross_scope_memory_denied"))
        #expect(localMemory.contains("retrieval_source=test_supervisor_retrieval"))
    }

    private func makeConversation(turns: Int) -> [SupervisorMessage] {
        var out: [SupervisorMessage] = []
        for index in 1...turns {
            let base = Double(index * 10)
            out.append(
                SupervisorMessage(
                    id: "u-\(index)",
                    role: .user,
                    content: "user-turn-\(index)",
                    isVoice: false,
                    timestamp: base
                )
            )
            out.append(
                SupervisorMessage(
                    id: "a-\(index)",
                    role: .assistant,
                    content: "assistant-turn-\(index)",
                    isVoice: false,
                    timestamp: base + 1
                )
            )
            out.append(
                SupervisorMessage(
                    id: "s-\(index)",
                    role: .system,
                    content: "system-turn-\(index)",
                    isVoice: false,
                    timestamp: base + 2
                )
            )
        }
        return out
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
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=stable",
            currentStateSummary: "运行中",
            nextStepSummary: "梳理结构并给出执行方案",
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: Date().timeIntervalSince1970
        )
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt-\(name)-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
