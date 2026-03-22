import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorGovernanceDigestIntegrationTests {
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
    func specGapProducesConcreteNextActionInsteadOfPlaceholder() throws {
        let now = Date(timeIntervalSince1970: 1_776_000_100).timeIntervalSince1970
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w333_integration_spec_gap_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let project = makeProject(
            id: "proj_spec_gap",
            root: root,
            displayName: "Spec Gap Project",
            now: now
        )
        let capsule = SupervisorProjectSpecCapsuleBuilder.build(
            projectId: project.projectId,
            goal: "Ship governed supervisor workflow.",
            mvpDefinition: "",
            nonGoals: [],
            approvedTechStack: [],
            milestoneMap: [],
            updatedAtMs: 1_776_000_100_000
        )
        _ = try SupervisorProjectSpecCapsuleStore.upsert(capsule, for: ctx)

        let manager = SupervisorManager.makeForTesting()
        let digest = manager.supervisorMemoryDigestForTesting(project)
        let snapshot = SupervisorPortfolioSnapshotBuilder.build(from: [digest], now: now)

        #expect(digest.source.contains("spec_capsule"))
        #expect(digest.nextStep.contains("补齐 formal spec 字段"))
        #expect(digest.nextStep != "(暂无)")
        #expect(digest.blocker.contains("formal_spec_missing"))
        #expect(snapshot.projects.first?.nextStep == digest.nextStep)
        #expect(snapshot.projects.first?.projectState == .blocked)
    }

    @Test
    func approvedDecisionBeatsConflictingBackgroundNoteInDigestAndPortfolio() throws {
        let now = Date(timeIntervalSince1970: 1_776_000_200).timeIntervalSince1970
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w333_integration_decision_precedence_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let project = makeProject(
            id: "proj_decision_priority",
            root: root,
            displayName: "Decision Priority Project",
            now: now
        )
        let decision = SupervisorDecisionTrackBuilder.build(
            decisionId: "dec_stack",
            projectId: project.projectId,
            category: .techStack,
            status: .approved,
            statement: "Use SwiftUI + Hub canonical memory.",
            source: "user",
            reversible: true,
            approvalRequired: false,
            approvedBy: "user",
            auditRef: "audit_dec_stack",
            createdAtMs: 1_776_000_200_000
        )
        let background = SupervisorBackgroundPreferenceTrackBuilder.build(
            noteId: "pref_stack",
            projectId: project.projectId,
            domain: .techStack,
            strength: .strong,
            statement: "Prefer cross-platform web.",
            createdAtMs: 1_776_000_200_100
        )
        _ = try SupervisorDecisionTrackStore.upsert(decision, for: ctx)
        _ = try SupervisorBackgroundPreferenceTrackStore.upsert(background, for: ctx)

        let manager = SupervisorManager.makeForTesting()
        let digest = manager.supervisorMemoryDigestForTesting(project)
        let snapshot = SupervisorPortfolioSnapshotBuilder.build(from: [digest], now: now)

        #expect(digest.source.contains("decision_track"))
        #expect(digest.source.contains("background_preference_track"))
        #expect(digest.currentState.contains("Use SwiftUI + Hub canonical memory."))
        #expect(!digest.currentState.contains("cross-platform web"))
        #expect(digest.shadowedBackgroundNoteCount == 1)
        #expect(digest.weakOnlyBackgroundNoteCount == 0)
        #expect(digest.nextStep.contains("tech_stack"))
        #expect(!snapshot.projects.first!.currentAction.contains("cross-platform web"))
        #expect(snapshot.projects.first?.shadowedBackgroundNoteCount == 1)
        #expect(snapshot.projects.first?.hasDecisionRailSignal == true)
        #expect(snapshot.projects.first?.nextStep == digest.nextStep)
    }

    @Test
    func backgroundOnlyStaysWeakSignalAndDoesNotBecomeHardBlocker() throws {
        let now = Date(timeIntervalSince1970: 1_776_000_300).timeIntervalSince1970
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w333_integration_background_only_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let project = makeProject(
            id: "proj_background_only",
            root: root,
            displayName: "Background Only Project",
            now: now
        )
        let background = SupervisorBackgroundPreferenceTrackBuilder.build(
            noteId: "pref_ux",
            projectId: project.projectId,
            domain: .uxStyle,
            strength: .medium,
            statement: "Prefer concise action-first updates.",
            createdAtMs: 1_776_000_300_000
        )
        _ = try SupervisorBackgroundPreferenceTrackStore.upsert(background, for: ctx)

        let manager = SupervisorManager.makeForTesting()
        let digest = manager.supervisorMemoryDigestForTesting(project)
        let snapshot = SupervisorPortfolioSnapshotBuilder.build(from: [digest], now: now)

        #expect(digest.source.contains("background_preference_track"))
        #expect(!digest.source.contains("decision_track"))
        #expect(digest.blocker == "(无)")
        #expect(digest.currentState.contains("背景偏好（弱参考）"))
        #expect(!digest.currentState.contains("已批准决策"))
        #expect(digest.shadowedBackgroundNoteCount == 0)
        #expect(digest.weakOnlyBackgroundNoteCount == 1)
        #expect(snapshot.projects.first?.projectState != .blocked)
        #expect(snapshot.projects.first?.weakOnlyBackgroundNoteCount == 1)
        #expect(snapshot.projects.first?.nextStep == "继续当前任务")
    }
}
