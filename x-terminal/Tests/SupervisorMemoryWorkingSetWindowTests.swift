import Foundation
import Testing
@testable import XTerminal

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
}
