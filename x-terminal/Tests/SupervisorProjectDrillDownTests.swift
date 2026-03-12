import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorProjectDrillDownTests {
    @Test
    func ownerCanRequestCapsulePlusRecent() throws {
        let now = Date(timeIntervalSince1970: 1_773_500_000).timeIntervalSince1970
        let manager = SupervisorManager.makeForTesting()
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("xt_w3_31_drill_owner_\(UUID().uuidString)")
        let project = AXProjectEntry(
            projectId: "p-owner",
            rootPath: projectRoot.path,
            displayName: "Owner Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "working",
            currentStateSummary: "Implementing drill-down",
            nextStepSummary: "Check recent turns",
            blockerSummary: nil,
            lastSummaryAt: now,
            lastEventAt: now
        )

        try AXProjectContext(root: projectRoot).ensureDirs()
        AXRecentContextStore.appendUserMessage(ctx: AXProjectContext(root: projectRoot), text: "Need the latest status", createdAt: now - 3)
        AXRecentContextStore.appendAssistantMessage(ctx: AXProjectContext(root: projectRoot), text: "Working on the local contract", createdAt: now - 2)

        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .owner, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(registry, persist: false, normalizeWithKnownProjects: false)

        let snapshot = manager.buildSupervisorProjectDrillDown(
            for: project,
            requestedScope: .capsulePlusRecent,
            recentMessageLimit: 4
        )

        #expect(snapshot.status == .allowed)
        #expect(snapshot.grantedScope == .capsulePlusRecent)
        #expect(snapshot.capsule?.projectId == project.projectId)
        #expect(snapshot.recentMessages.count == 2)
        #expect(snapshot.refs.contains(where: { $0.contains("xterminal.project.capsule.summary_json") }))
        #expect(snapshot.refs.contains(where: { $0.contains("xterminal.project.action.summary_json") }))
        #expect(snapshot.refs.contains(AXRecentContextStore.jsonURL(for: AXProjectContext(root: projectRoot)).path))
    }

    @Test
    func observerCannotEscalateBeyondCapsuleOnly() {
        let now = Date(timeIntervalSince1970: 1_773_500_100).timeIntervalSince1970
        let manager = SupervisorManager.makeForTesting()
        let project = AXProjectEntry(
            projectId: "p-observer",
            rootPath: "/tmp/p-observer",
            displayName: "Observer Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "working",
            currentStateSummary: "Implementing",
            nextStepSummary: "Continue",
            blockerSummary: nil,
            lastSummaryAt: now,
            lastEventAt: now
        )

        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .observer, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(registry, persist: false, normalizeWithKnownProjects: false)

        let denied = manager.buildSupervisorProjectDrillDown(
            for: project,
            requestedScope: .capsulePlusRecent
        )
        let allowed = manager.buildSupervisorProjectDrillDown(
            for: project,
            requestedScope: .capsuleOnly
        )

        #expect(denied.status == .deniedScope)
        #expect(denied.denyReason == "requested_scope_exceeds_jurisdiction_cap")
        #expect(allowed.status == .allowed)
        #expect(allowed.grantedScope == .capsuleOnly)
        #expect(allowed.refs.contains(where: { $0.contains("xterminal.project.capsule.summary_json") }))
        #expect(!allowed.refs.contains(where: { $0.contains("xterminal.project.action.summary_json") }))
    }

    @Test
    func triageOnlyCannotSeeNonCriticalProject() {
        let now = Date(timeIntervalSince1970: 1_773_500_200).timeIntervalSince1970
        let manager = SupervisorManager.makeForTesting()
        let project = AXProjectEntry(
            projectId: "p-triage",
            rootPath: "/tmp/p-triage",
            displayName: "Triage Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "working",
            currentStateSummary: "Implementing",
            nextStepSummary: "Continue",
            blockerSummary: nil,
            lastSummaryAt: now,
            lastEventAt: now
        )

        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(registry, persist: false, normalizeWithKnownProjects: false)

        let denied = manager.buildSupervisorProjectDrillDown(
            for: project,
            requestedScope: .capsuleOnly
        )

        #expect(denied.status == .deniedProjectInvisible)
        #expect(denied.denyReason == "project_not_visible_in_current_jurisdiction")
    }
}
