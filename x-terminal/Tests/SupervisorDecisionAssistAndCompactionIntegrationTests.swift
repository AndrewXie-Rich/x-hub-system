import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorDecisionAssistAndCompactionIntegrationTests {
    private func makeProject(
        id: String,
        root: URL,
        displayName: String,
        statusDigest: String? = nil,
        currentState: String? = nil,
        nextStep: String? = nil,
        blocker: String? = nil,
        now: Double
    ) -> AXProjectEntry {
        AXProjectEntry(
            projectId: id,
            rootPath: root.path,
            displayName: displayName,
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: statusDigest,
            currentStateSummary: currentState,
            nextStepSummary: nextStep,
            blockerSummary: blocker,
            lastSummaryAt: now,
            lastEventAt: now
        )
    }

    @Test
    func lowRiskDecisionBlockerGetsStructuredPendingProposal() throws {
        let now = Date(timeIntervalSince1970: 1_776_100_100).timeIntervalSince1970
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w333_decision_assist_low_risk_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProject(
            id: "proj_test_stack",
            root: root,
            displayName: "Test Stack Project",
            blocker: "Need to pick a default test framework before continuing.",
            now: now
        )

        let manager = SupervisorManager.makeForTesting()
        let digest = manager.supervisorMemoryDigestForTesting(project)

        #expect(digest.source.contains("decision_blocker_assist"))
        #expect(digest.nextStep.contains("swift_testing_contract_default"))
        #expect(digest.nextStep.contains("governed adoption"))
        #expect(digest.blocker.contains("default_proposal_pending:test_stack="))
        #expect(digest.blocker.contains("swift_testing_contract"))
        #expect(!digest.nextStep.contains("approved"))
    }

    @Test
    func highRiskDecisionBlockerStaysFailClosedInDigest() throws {
        let now = Date(timeIntervalSince1970: 1_776_100_200).timeIntervalSince1970
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w333_decision_assist_fail_closed_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProject(
            id: "proj_release_scope",
            root: root,
            displayName: "Release Scope Project",
            blocker: "Release scope change requires authorization before ship.",
            now: now
        )

        let manager = SupervisorManager.makeForTesting()
        let digest = manager.supervisorMemoryDigestForTesting(project)

        #expect(digest.source.contains("decision_blocker_assist"))
        #expect(digest.nextStep.contains("显式审批"))
        #expect(digest.nextStep.contains("proposal_only"))
        #expect(digest.blocker.contains("decision_requires_approval:release_scope"))
        #expect(!digest.nextStep.contains("governed adoption"))
    }

    @Test
    func completedProjectSurfacesCompactionRollupArchiveHint() throws {
        let now = Date(timeIntervalSince1970: 1_776_100_300).timeIntervalSince1970
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w333_compaction_runtime_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        var memory = AXMemory.new(projectName: "Archive Candidate Project", projectRoot: root.path)
        memory.goal = "Close the project without losing governed traceability."
        try AXProjectStore.saveMemory(memory, for: ctx)

        let oldTimestamp = now - (10 * 24 * 60 * 60)
        AXRecentContextStore.appendUserMessage(
            ctx: ctx,
            text: "Old implementation chatter for finished project",
            createdAt: oldTimestamp
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: ctx,
            text: "Detailed execution log that should archive cleanly",
            createdAt: oldTimestamp + 10
        )

        let decision = SupervisorDecisionTrackBuilder.build(
            decisionId: "dec_archive_ui",
            projectId: "proj_archive_candidate",
            category: .uiStyle,
            status: .approved,
            statement: "Keep the finished dashboard compact and action-first.",
            source: "user",
            reversible: true,
            approvalRequired: false,
            approvedBy: "user",
            auditRef: "audit_archive_ui",
            evidenceRefs: ["build/reports/xt_w3_33_g_memory_compaction_evidence.v1.json"],
            createdAtMs: Int64((oldTimestamp * 1_000.0).rounded())
        )
        _ = try SupervisorDecisionTrackStore.upsert(decision, for: ctx)

        let project = makeProject(
            id: "proj_archive_candidate",
            root: root,
            displayName: "Archive Candidate Project",
            currentState: "completed",
            now: now
        )

        let manager = SupervisorManager.makeForTesting()
        let digest = manager.supervisorMemoryDigestForTesting(project)

        #expect(digest.source.contains("memory_compaction_rollup"))
        #expect(digest.nextStep.contains("archive rollup"))
        #expect(digest.nextStep.contains("archive"))
    }
}
