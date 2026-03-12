import Foundation
import Testing
@testable import XTerminal

struct SupervisorPortfolioSnapshotCanonicalSyncTests {
    @Test
    func itemsIncludeStablePortfolioKeysAndSummaryJSON() throws {
        let snapshot = SupervisorPortfolioSnapshot(
            updatedAt: 1_773_700_123,
            counts: SupervisorPortfolioProjectCounts(active: 1, blocked: 1, awaitingAuthorization: 1, completed: 0, idle: 2),
            criticalQueue: [
                SupervisorPortfolioCriticalQueueItem(
                    projectId: "p-auth",
                    projectName: "Auth Project",
                    reason: "authorization_required",
                    severity: .authorizationRequired,
                    nextAction: "Approve paid model access"
                )
            ],
            projects: [
                SupervisorPortfolioProjectCard(
                    projectId: "p-auth",
                    displayName: "Auth Project",
                    projectState: .awaitingAuthorization,
                    runtimeState: "进行中",
                    currentAction: "等待授权批准",
                    topBlocker: "grant_required",
                    nextStep: "Approve paid model access",
                    memoryFreshness: .fresh,
                    updatedAt: 1_773_700_123,
                    recentMessageCount: 2
                )
            ]
        )

        let record = SupervisorPortfolioSnapshotCanonicalSync.record(
            snapshot: snapshot,
            supervisorId: "supervisor-main"
        )
        let items = SupervisorPortfolioSnapshotCanonicalSync.items(record: record)
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0.value) })

        #expect(lookup["xterminal.supervisor.portfolio.supervisor_id"] == "supervisor-main")
        #expect(lookup["xterminal.supervisor.portfolio.project_counts.active"] == "1")
        #expect(lookup["xterminal.supervisor.portfolio.project_counts.awaiting_authorization"] == "1")
        #expect(lookup["xterminal.supervisor.portfolio.critical_queue_count"] == "1")
        #expect(lookup["xterminal.supervisor.portfolio.audit_ref"]?.contains("supervisor_portfolio_snapshot") == true)

        let summary = try #require(lookup["xterminal.supervisor.portfolio.summary_json"])
        let data = try #require(summary.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SupervisorPortfolioSnapshotCanonicalRecord.self, from: data)
        #expect(decoded.supervisorId == "supervisor-main")
        #expect(decoded.projectCounts.blocked == 1)
        #expect(decoded.criticalQueue.first?.projectId == "p-auth")
        #expect(decoded.projects.first?.projectState == .awaitingAuthorization)
    }

    @Test
    func fingerprintIgnoresUpdatedAtDrift() {
        let older = SupervisorPortfolioSnapshot(
            updatedAt: 100,
            counts: SupervisorPortfolioProjectCounts(active: 1, blocked: 0, awaitingAuthorization: 0, completed: 0, idle: 0),
            criticalQueue: [],
            projects: [
                SupervisorPortfolioProjectCard(
                    projectId: "p-1",
                    displayName: "Project One",
                    projectState: .active,
                    runtimeState: "进行中",
                    currentAction: "Implementing feature",
                    topBlocker: "",
                    nextStep: "Continue implementation",
                    memoryFreshness: .fresh,
                    updatedAt: 100,
                    recentMessageCount: 1
                )
            ]
        )
        var newer = older
        newer.updatedAt = 200

        let left = SupervisorPortfolioSnapshotCanonicalSync.fingerprint(
            snapshot: older,
            supervisorId: "supervisor-main"
        )
        let right = SupervisorPortfolioSnapshotCanonicalSync.fingerprint(
            snapshot: newer,
            supervisorId: "supervisor-main"
        )

        #expect(left == right)
    }
}
