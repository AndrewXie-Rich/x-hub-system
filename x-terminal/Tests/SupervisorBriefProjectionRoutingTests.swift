import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorBriefProjectionRoutingTests {

    actor ProjectionFetchCounter {
        private(set) var count: Int = 0

        func mark() {
            count += 1
        }

        func value() -> Int {
            count
        }
    }

    @Test
    func systemDiscussionPromptSkipsSynchronousBriefGuard() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-brief-routing-sync")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.registry = registry(
            with: [
                makeProjectEntry(
                    root: root,
                    displayName: "亮亮",
                    blockerSummary: "等待确认",
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)

        let prompt = "不用当成项目回答，你对这套系统有什么建议，详细说说"
        let reply = manager.directSupervisorReplyIfApplicableForTesting(prompt)

        #expect(reply == nil)
    }

    @Test
    func systemDiscussionPromptSkipsHubBriefProjectionRouting() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-brief-routing-async")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.registry = registry(
            with: [
                makeProjectEntry(
                    root: root,
                    displayName: "亮亮",
                    blockerSummary: "等待确认",
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)

        let fetchCounter = ProjectionFetchCounter()
        manager.installSupervisorBriefProjectionFetcherForTesting { _ in
            await fetchCounter.mark()
            return HubIPCClient.SupervisorBriefProjectionResult(
                ok: false,
                source: "test",
                projection: nil,
                reasonCode: "should_not_run"
            )
        }

        let prompt = "不用当成项目回答，你对这套系统有什么建议，详细说说"
        let reply = await manager.supervisorBriefProjectionReplyIfApplicableForTesting(prompt)

        #expect(reply == nil)
        #expect(await fetchCounter.value() == 0)
    }

    @Test
    func briefProjectionReplyHumanizesKnownBlockerCodes() async throws {
        let manager = SupervisorManager.makeForTesting()
        let reply = manager.renderSupervisorBriefProjectionVoiceReplyForTesting(
            HubIPCClient.SupervisorBriefProjectionSnapshot(
                schemaVersion: "xhub.supervisor_brief_projection.v1",
                projectionId: "projection-project-liangliang",
                projectionKind: "progress_brief",
                projectId: "project-liangliang",
                runId: "",
                missionId: "",
                trigger: "blocked",
                status: "blocked",
                criticalBlocker: "grant_required;deny_code=remote_export_blocked",
                topline: "远端执行被挡住了。",
                nextBestAction: "先去 Hub Recovery 看 remote export gate。",
                pendingGrantCount: 1,
                ttsScript: [],
                cardSummary: "远端执行被挡住了。",
                evidenceRefs: [],
                generatedAtMs: 1_777_000_000_000,
                expiresAtMs: 1_777_000_060_000,
                auditRef: "audit-brief-humanized-blocker"
            ),
            projectName: "亮亮"
        )

        #expect(reply.contains("🧭 Supervisor Brief · 亮亮"))
        #expect(reply.contains("阻塞：Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
        #expect(reply.contains("待授权：1"))
        #expect(reply.contains("下一步：先去 Hub Recovery 看 remote export gate。"))
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

    private func makeProjectEntry(
        root: URL,
        displayName: String,
        blockerSummary: String?,
        nextStepSummary: String?
    ) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: displayName,
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=\(blockerSummary == nil ? "stable" : "blocked")",
            currentStateSummary: blockerSummary == nil ? "运行中" : "阻塞中",
            nextStepSummary: nextStepSummary,
            blockerSummary: blockerSummary,
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
